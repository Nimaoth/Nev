import std/[macros, macrocache, json, strutils, tables, options, sequtils, os]
import misc/[custom_logger, custom_async, util, myjsonutils]
import expose, compilation_config, service, vfs_service, vfs, dispatch_tables, events, config_provider

{.push gcsafe.}
{.push raises: [].}

logCategory "plugins"

type
  ScriptContext* = ref object of RootObj

  ScriptAction = object
    name: string
    scriptContext: ScriptContext

  PluginManifest* = object
    name*: string
    path*: string
    authors*: seq[string]
    repository*: string
    autoLoad*: bool
    wasm*: string

  PluginState* = enum Unloaded, Loading, Loaded, Disabled, Failed

  PluginInstanceBase* = ref object of RootObj

  Plugin* = ref object
    manifest*: PluginManifest
    state*: PluginState
    pluginSystem*: ScriptContext
    instance*: PluginInstanceBase

  PluginService* = ref object of Service
    scriptContexts*: seq[ScriptContext]
    callbacks*: Table[string, int]
    currentScriptContext*: Option[ScriptContext] = ScriptContext.none
    pluginSystems*: seq[ScriptContext]

    scriptActions*: Table[string, ScriptAction]
    events: EventHandlerService
    vfs: VFS
    settings*: ConfigStore

    plugins*: seq[Plugin]

method init*(self: ScriptContext, path: string, vfs: VFS): Future[void] {.base.} = discard
method deinit*(self: ScriptContext) {.base.} = discard
method reload*(self: ScriptContext): Future[void] {.base.} = discard

method postInitialize*(self: ScriptContext): bool {.base.} = discard
method handleCallback*(self: ScriptContext, id: int, arg: JsonNode): bool {.base.} = discard
method handleAnyCallback*(self: ScriptContext, id: int, arg: JsonNode): JsonNode {.base.} = discard
method handleScriptAction*(self: ScriptContext, name: string, args: JsonNode): JsonNode {.base.} = discard
method getCurrentContext*(self: ScriptContext): string {.base.} = ""
method tryLoadPlugin*(self: ScriptContext, plugin: Plugin): Future[bool] {.base, async: (raises: [IOError]).} = false
method unloadPlugin*(self: ScriptContext, plugin: Plugin): Future[void] {.base, async: (raises: []).} = discard

func serviceName*(_: typedesc[PluginService]): string = "PluginService"

addBuiltinService(PluginService, EventHandlerService, VFSService, ConfigService)

proc loadPluginManifests(self: PluginService) {.async.}

proc desc*(self: Plugin): string = &"'{self.manifest.name}' ({self.manifest.path})"

method init*(self: PluginService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.events = self.services.getService(EventHandlerService).get
  self.vfs = self.services.getService(VFSService).get.vfs
  self.settings = self.services.getService(ConfigService).get.runtime
  asyncSpawn self.loadPluginManifests()
  return ok()

proc loadPlugin*(self: PluginService, plugin: Plugin) {.async.} =
  if plugin.state == PluginState.Disabled or plugin.state == PluginState.Loaded:
    return

  log lvlNotice, &"Load plugin {plugin.desc}"
  for ps in self.pluginSystems:
    try:
      if ps.tryLoadPlugin(plugin).await:
        return
    except IOError as e:
      log lvlError, &"Plugin {plugin.desc} could not be loaded: {e.msg}"

  log lvlError, &"Plugin {plugin.desc} could not be loaded."

proc unloadPlugin*(self: PluginService, plugin: Plugin) {.async.} =
  if plugin.state != PluginState.Loaded:
    return

  if plugin.pluginSystem != nil:
    log lvlNotice, &"Unload plugin {plugin.desc}"
    await plugin.pluginSystem.unloadPlugin(plugin)
    plugin.pluginSystem = nil
    plugin.instance = nil

  plugin.state = PluginState.Unloaded

proc reloadPlugin*(self: PluginService, plugin: Plugin) {.async.} =
  if plugin.state == PluginState.Disabled:
    return
  await self.unloadPlugin(plugin)
  await self.loadPlugin(plugin)

proc unloadPlugin*(self: PluginService, path: string) {.async.} =
  for p in self.plugins:
    if p.manifest.path == path:
      await self.unloadPlugin(p)
      return

proc loadPlugin*(self: PluginService, path: string) {.async.} =
  for p in self.plugins:
    if p.manifest.path == path:
      await self.loadPlugin(p)
      return

proc reloadPlugin*(self: PluginService, path: string) {.async.} =
  for p in self.plugins:
    if p.manifest.path == path:
      await self.reloadPlugin(p)
      return

proc loadPlugins*(self: PluginService) =
  for p in self.plugins:
    if not p.manifest.autoLoad:
      continue
    if p.state == PluginState.Unloaded:
      asyncSpawn self.loadPlugin(p)

proc createPlugin(self: PluginService, manifest: sink PluginManifest) =
  log lvlNotice, &"Register plugin {manifest}"
  let plugin = Plugin(
    manifest: manifest.ensureMove,
  )
  self.plugins.add(plugin)

proc loadPluginManifests(self: PluginService) {.async.} =
  let root = "app://plugins"
  let listing = await self.vfs.getDirectoryListing(root)
  for file in listing.files:
    if file.endsWith(".m.wasm"):
      let (_, name, ext) = file.splitFile
      self.createPlugin(PluginManifest(
        name: name,
        path: root // file,
        wasm: root // file,
      ))

  for folder in listing.folders:
    try:
      let manifestJson = self.vfs.read(root // folder // "manifest.json").await
      var manifest = manifestJson.parseJson().jsonTo(PluginManifest, Joptions(allowExtraKeys: true, allowMissingKeys: true))
      manifest.path = root // folder // "manifest.json"
      if manifest.wasm != "":
        manifest.wasm = root // folder // manifest.wasm
      self.createPlugin(manifest)
    except IOError:
      log lvlError, &"Failed to find manifest.json in '{folder}'"

{.pop.} # raises

proc generateScriptingApiPerModule*() {.compileTime.} =
  var imports_content = "import \"../src/scripting_api\"\nexport scripting_api\n\n## This file is auto generated, don't modify.\n\n"

  for moduleName, list in exposedFunctions:
    var script_api_content_wasm = """
import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.

"""

    for m, list in wasmImportedFunctions:
      if moduleName != m:
        continue
      for f in list:
        script_api_content_wasm.add f[2].repr
        script_api_content_wasm.add "\n"
        script_api_content_wasm.add f[1].repr
        script_api_content_wasm.add "\n"

    let file_name = moduleName.replace(".", "_")

    echo fmt"Writing scripting/{file_name}_api_wasm.nim"
    writeFile(fmt"scripting/{file_name}_api_wasm.nim", script_api_content_wasm)

    imports_content.add fmt"import {file_name}_api_wasm" & "\n"
    imports_content.add fmt"export {file_name}_api_wasm" & "\n"

  when enableAst:
    imports_content.add "\nconst enableAst* = true\n"
  else:
    imports_content.add "\nconst enableAst* = false\n"

  echo fmt"Writing scripting/plugin_api.nim"
  writeFile(fmt"scripting/plugin_api.nim", imports_content)

template withScriptContext*(self: PluginService, scriptContext: untyped, body: untyped): untyped =
  if scriptContext.isNotNil:
    let oldScriptContext = self.currentScriptContext
    {.push hint[ConvFromXtoItselfNotNeeded]:off.}
    self.currentScriptContext = scriptContext.ScriptContext.some
    {.pop.}
    defer:
      self.currentScriptContext = oldScriptContext
    body

proc invokeCallback*(self: PluginService, context: string, args: JsonNode): bool =
  try:
    if not self.callbacks.contains(context):
      return false
    let id = self.callbacks[context]

    for sc in self.scriptContexts:
      withScriptContext self, sc:
        if sc.handleCallback(id, args):
          return true
    return false
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleCallback {context}: {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return false

proc invokeAnyCallback*(self: PluginService, context: string, args: JsonNode): JsonNode =
  if self.callbacks.contains(context):
    try:
      let id = self.callbacks[context]

      for sc in self.scriptContexts:
        withScriptContext self, sc:
          let res = sc.handleAnyCallback(id, args)
          if res.isNotNil:
            return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleAnyCallback {context}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

  else:
    try:
      for sc in self.scriptContexts:
        withScriptContext self, sc:
          let res = sc.handleScriptAction(context, args)
          if res.isNotNil:
            return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleScriptAction {context}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

proc clearScriptActionsFor*(self: PluginService, scriptContext: ScriptContext) =
  var keysToRemove: seq[string]
  for (key, value) in self.scriptActions.pairs:
    if value.scriptContext == scriptContext:
      keysToRemove.add key

  for key in keysToRemove:
    self.scriptActions.del key

proc getPluginService(): Option[PluginService] =
  {.gcsafe.}:
    if gServices.isNil: return PluginService.none
    return gServices.getService(PluginService)

static:
  addInjector(PluginService, getPluginService)

proc bindKeys*(self: PluginService, context: string, subContext: string, keys: string, action: string, arg: string = "", description: string = "", source: tuple[filename: string, line: int, column: int] = ("", 0, 0)) {.expose("plugins").} =
  let command = if arg.len == 0: action else: action & " " & arg
  log(lvlInfo, fmt"Adding command to '{context}': ('{subContext}', '{keys}', '{command}')")

  let (context, subContext) = if (let i = context.find('#'); i != -1):
    (context[0..<i], context[i+1..^1] & subContext)
  else:
    (context, subContext)

  if description.len > 0:
    self.events.commandDescriptions[context & subContext & keys] = description

  var source = source
  if self.currentScriptContext.getSome(scriptContext):
    source.filename = scriptContext.getCurrentContext() & source.filename

  self.events.getEventHandlerConfig(context).addCommand(subContext, keys, command, source)
  self.events.invalidateCommandToKeysMap()

proc callScriptAction*(self: PluginService, context: string, args: JsonNode): JsonNode {.expose("plugins").} =
  if not self.scriptActions.contains(context):
    log lvlError, fmt"Unknown script action '{context}'"
    return nil
  let action = self.scriptActions[context]
  try:
    withScriptContext self, action.scriptContext:
      return action.scriptContext.handleScriptAction(context, args)
    log lvlError, fmt"No script context for action '{context}'"
    return nil
  except CatchableError:
    log(lvlError, fmt"Failed to run script action {context}: {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())
    return nil

proc addScriptAction*(self: PluginService, name: string, docs: string = "",
    params: seq[tuple[name: string, typ: string]] = @[], returnType: string = "", active: bool = false,
    context: string = "script", override: bool = false)
    {.expose("plugins").} =

  if not override and self.scriptActions.contains(name):
    log lvlError, fmt"Duplicate script action {name}"
    return

  if self.currentScriptContext.isNone:
    log lvlError, fmt"addScriptAction({name}) should only be called from a script"
    return

  self.scriptActions[name] = ScriptAction(name: name, scriptContext: self.currentScriptContext.get)

  proc dispatch(arg: JsonNode): JsonNode =
    return self.callScriptAction(name, arg)

  let signature = "(" & params.mapIt(it[0] & ": " & it[1]).join(", ") & ")" & returnType
  {.gcsafe.}:
    if active:
      extendActiveDispatchTable context, ExposedFunction(name: name, docs: docs, dispatch: dispatch, params: params, returnType: returnType, signature: signature)
    else:
      extendGlobalDispatchTable context, ExposedFunction(name: name, docs: docs, dispatch: dispatch, params: params, returnType: returnType, signature: signature)

addGlobalDispatchTable "plugins", genDispatchTable("plugins")
