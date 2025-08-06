import std/[macros, macrocache, json, strutils, tables, options, sequtils, os, sugar, streams]
import misc/[custom_logger, custom_async, util, myjsonutils]
import scripting/expose
import compilation_config, service, vfs_service, vfs, dispatch_tables, events, config_provider, command_service

{.push gcsafe.}
{.push raises: [].}

logCategory "plugins"

type PluginCommandLoadBehaviour* = enum
  DontRun = "dont-run"
  AsyncRun = "async-run"
  WaitAndRun = "wait-and-run"
  AsyncOrWait = "async-or-wait"

declareSettings PluginSettings, "plugins":
  # use openSession, OpenSessionSettings

  ## Whether to watch the plugin directories for changes and load new plugins
  declare watchPluginDirectories, bool, true

  ## Defines if and how to run commands which trigger a plugin to load.
  ## "dont-run": Don't run the command after the plugin is loaded. You have to manually run the command again.
  ## "async-run": Asynchronously load the plugin and run the command afterwards. If the command returns something
  ##              then the return value will not be available if the command is e.g. called from a plugin.
  ## "wait-and-run": Synchronously load the plugin and run the command afterwards. Return values work fine, but the editor
  ##                 will freeze while loading the plugin.
  ## "async-or-wait": Use "async-run" behaviour for commands with no return value and "wait-and-run" for commands with return values.
  declare commandLoadBehaviour, PluginCommandLoadBehaviour, AsyncOrWait

type
  PluginSystem* = ref object of RootObj

  ScriptAction = object
    name: string
    pluginSystem: PluginSystem

  PluginCommandDescription* = object
    parameters*: seq[tuple[name: string, `type`: string]]
    returnType*: string
    description*: string

  PluginManifest* = object
    name*: string
    id*: string
    path*: string
    authors*: seq[string]
    repository*: string
    autoLoad*: bool
    wasm*: string
    permissions*: JsonNode
    load*: seq[JsonNode]
    commands*: Table[string, PluginCommandDescription]

  PluginState* = enum Unloaded, Loading, Loaded, Disabled, Failed

  PluginInstanceBase* = ref object of RootObj

  FilesystemPermissions* = object
    allowAll*: Option[bool]
    disallowAll*: Option[bool]
    allow*: seq[string]
    disallow*: seq[string]

  PluginPermissions* = object
    filesystem*: FilesystemPermissions
    commands*: CommandPermissions
    time*: bool

  Plugin* = ref object
    manifest*: PluginManifest
    state*: PluginState
    pluginSystem*: PluginSystem
    instance*: PluginInstanceBase
    dirty*: bool ## True if there are changes on disk for the plugin
    settings*: ConfigStore
    permissions*: PluginPermissions
    loadOnCommand*: bool = true

  PluginDirectory* = ref object
    path*: string
    watchHandle*: VFSWatchHandle

  VFSEvent = tuple
    pluginFolder: PluginDirectory
    path: string
    newPath: string
    action: FileEventAction

  PluginService* = ref object of Service
    pluginSystems*: seq[PluginSystem]
    callbacks*: Table[string, int]
    currentPluginSystem*: Option[PluginSystem] = PluginSystem.none

    scriptActions: Table[string, ScriptAction]
    events: EventHandlerService
    vfs: VFS
    commands*: CommandService
    configService*: ConfigService
    settings*: ConfigStore

    pluginFolders*: seq[PluginDirectory]
    plugins*: seq[Plugin]
    pathToPlugin*: Table[string, Plugin]
    idToPlugin*: Table[string, Plugin]

    pluginSettings*: PluginSettings

    isHandlingVFSEvents: bool
    vfsEvents: seq[VFSEvent]

method init*(self: PluginSystem, path: string, vfs: VFS): Future[void] {.base.} = discard
method deinit*(self: PluginSystem) {.base.} = discard
method reload*(self: PluginSystem): Future[void] {.base.} = discard

method postInitialize*(self: PluginSystem): bool {.base.} = discard
method handleCallback*(self: PluginSystem, id: int, arg: JsonNode): bool {.base.} = discard
method handleAnyCallback*(self: PluginSystem, id: int, arg: JsonNode): JsonNode {.base.} = discard
method handleScriptAction*(self: PluginSystem, name: string, args: JsonNode): JsonNode {.base.} = discard
method getCurrentContext*(self: PluginSystem): string {.base.} = ""
method tryLoadPlugin*(self: PluginSystem, plugin: Plugin): Future[bool] {.base, async: (raises: [IOError]).} = false
method unloadPlugin*(self: PluginSystem, plugin: Plugin): Future[void] {.base, async: (raises: []).} = discard

func serviceName*(_: typedesc[PluginService]): string = "PluginService"

addBuiltinService(PluginService, EventHandlerService, VFSService, ConfigService)

proc addPluginFolder(self: PluginService, path: string) {.async.}
proc registerPluginCommands(self: PluginService, plugin: Plugin)

proc desc*(self: Plugin): string = &"'{self.manifest.name}' ({self.manifest.path})"

method init*(self: PluginService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.events = self.services.getService(EventHandlerService).get
  self.vfs = self.services.getService(VFSService).get.vfs
  self.commands = self.services.getService(CommandService).get
  self.configService = self.services.getService(ConfigService).get
  self.settings = self.configService.runtime
  self.pluginSettings = PluginSettings.new(self.settings)

  asyncSpawn self.addPluginFolder("app://plugins")
  asyncSpawn self.addPluginFolder("home://.nev/plugins")
  return ok()

proc updatePermissions(self: PluginService, plugin: Plugin) =
  try:
    plugin.settings.set("permissions", plugin.manifest.permissions)
    let permissionsJson = plugin.settings.get("permissions", newJObject())
    plugin.permissions = permissionsJson.jsonTo(PluginPermissions, Joptions(allowExtraKeys: true, allowMissingKeys: true))
  except CatchableError as e:
    log lvlError, &"Failed to parse permissions for {plugin.desc}: {e.msg}"

proc loadPlugin*(self: PluginService, plugin: Plugin) {.async.} =
  if plugin.state notin {PluginState.Unloaded, PluginState.Failed}:
    return

  log lvlNotice, &"Load plugin {plugin.desc}"
  plugin.state = Loading
  self.updatePermissions(plugin)
  for ps in self.pluginSystems:
    try:
      if ps.tryLoadPlugin(plugin).await:
        plugin.state = Loaded
        plugin.dirty = false
        return
    except IOError as e:
      plugin.state = Failed
      log lvlError, &"Plugin {plugin.desc} could not be loaded: {e.msg}"

  plugin.state = Failed
  log lvlError, &"Plugin {plugin.desc} could not be loaded."

proc unloadPlugin*(self: PluginService, plugin: Plugin) {.async.} =
  if plugin.state != PluginState.Loaded:
    return

  if plugin.pluginSystem != nil:
    log lvlNotice, &"Unload plugin {plugin.desc}"
    await plugin.pluginSystem.unloadPlugin(plugin)
    plugin.pluginSystem = nil
    plugin.instance = nil

    # Register these commands again so the plugin can get loaded again when running one of these commands
    self.registerPluginCommands(plugin)

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

proc registerPluginCommands(self: PluginService, plugin: Plugin) =
  for (name, desc) in plugin.manifest.commands.pairs:
    let name = plugin.manifest.id & "." & name
    capture name, desc:
      let id = self.commands.registerCommand(command_service.Command(
        name: name,
        parameters: desc.parameters,
        description: desc.description,
        execute: (proc(args: string): string =
          if plugin.state == PluginState.Unloaded and plugin.loadOnCommand:
            var commandLoadBehaviour = self.pluginSettings.commandLoadBehaviour.get()
            if commandLoadBehaviour == AsyncOrWait:
              if desc.returnType == "":
                commandLoadBehaviour = AsyncRun
              else:
                commandLoadBehaviour = WaitAndRun

            let fut = self.loadPlugin(plugin)
            case commandLoadBehaviour
            of DontRun:
              asyncSpawn fut

            of AsyncRun:
              fut.thenIt:
                if plugin.state == Loaded:
                  discard self.commands.executeCommand(name & " " & args)

            of WaitAndRun:
              try:
                waitFor fut
                if plugin.state == Loaded:
                  return self.commands.executeCommand(name & " " & args).get("")
                return ""
              except CatchableError as e:
                log lvlError, &"Failed to wait for plugin to load: {e.msg}"
                return ""

            of AsyncOrWait:
              assert false
        )
      ), override = true)

proc createPlugin(self: PluginService, manifest: sink PluginManifest) =
  log lvlNotice, &"Register plugin {manifest}"
  if self.idToPlugin.contains(manifest.id):
    log lvlError, &"Failed to register plugin manifest\n{manifest}\nPlugin with same id already exists:\n{self.idToPlugin[manifest.id].manifest}"
    return

  let plugin = Plugin(
    manifest: manifest.ensureMove,
  )
  if plugin.manifest.permissions == nil:
    plugin.manifest.permissions = newJObject()

  plugin.settings = self.configService.addStore("plugin-" & plugin.manifest.id, &"settings://plugin/{plugin.manifest.id}")
  plugin.settings.prefix = "plugin." & plugin.manifest.id
  self.updatePermissions(plugin)
  self.plugins.add(plugin)
  self.pathToPlugin[plugin.manifest.path] = plugin
  self.idToPlugin[plugin.manifest.id] = plugin
  self.registerPluginCommands(plugin)

proc addManifestFromFile(self: PluginService, pluginFolder: PluginDirectory, file: string) {.async.} =
  if file.endsWith(".m.wasm"):
    var name = file.splitPath.tail
    name.removeSuffix(".m.wasm")
    self.createPlugin(PluginManifest(
      name: name,
      id: name,
      path: pluginFolder.path // file,
      wasm: pluginFolder.path // file,
      permissions: newJObject(),
    ))

proc addManifestFromFolder(self: PluginService, pluginFolder: PluginDirectory, folder: string) {.async.} =
  try:
    let manifestJson = self.vfs.read(pluginFolder.path // folder // "manifest.json").await
    var manifest = manifestJson.parseJson().jsonTo(PluginManifest, Joptions(allowExtraKeys: true, allowMissingKeys: true))
    manifest.path = pluginFolder.path // folder
    manifest.id = folder
    if manifest.wasm != "":
      manifest.wasm = pluginFolder.path // folder // manifest.wasm
    if manifest.permissions == nil:
      manifest.permissions = newJObject()
    self.createPlugin(manifest)
  except IOError as e:
    log lvlError, &"Failed to find manifest.json in '{folder}': {e.msg}"
  except ValueError as e:
    log lvlError, &"Failed to parse manifest.json in '{folder}': {e.msg}"
  except CatchableError as e:
    log lvlError, &"Failed to load manifest.json in '{folder}': {e.msg}"

proc getPlugin(self: PluginService, path: string): Option[Plugin] =
  if self.pathToPlugin.contains(path):
    return self.pathToPlugin[path].some
  return Plugin.none

proc handleVFSEvents(self: PluginService) {.async.} =
  boolLock(self.isHandlingVFSEvents)
  var i = 0
  while i < self.vfsEvents.len:
    defer:
      inc i

    let e = self.vfsEvents[i]
    case e.action
    of FileEventAction.Modify:
      let fullPath = e.pluginFolder.path // e.path
      let isDir = self.vfs.getFileKind(fullPath).await
      let (container, item) = e.path.splitPath
      if isDir.getSome(isDir):
        let pluginPathRelative = if container == "":
          e.path
        else:
          container
        let pluginPath = e.pluginFolder.path // pluginPathRelative

        if self.getPlugin(pluginPath).getSome(existingPlugin):
          log lvlInfo, "Changed existing plugin"
          existingPlugin.dirty = true
        else:
          log lvlInfo, "New plugin ", pluginPath
          if container != "" or isDir == FileKind.Directory:
            await self.addManifestFromFolder(e.pluginFolder, pluginPathRelative)
          else:
            await self.addManifestFromFile(e.pluginFolder, pluginPathRelative)


    else:
      discard

  self.vfsEvents.setLen(0)

proc loadPluginManifests(self: PluginService, pluginFolder: PluginDirectory) {.async.} =
  log lvlNotice, &"Load plugin manifests from '{pluginFolder.path}'"
  let root = pluginFolder.path
  let listing = await self.vfs.getDirectoryListing(root)

  for path in listing.files:
    await self.addManifestFromFile(pluginFolder, path)

  for path in listing.folders:
    await self.addManifestFromFolder(pluginFolder, path)

  if self.pluginSettings.watchPluginDirectories.get():
    log lvlInfo, &"Watch plugin pluginFolder: {pluginFolder.path}"
    pluginFolder.watchHandle = self.vfs.watch(pluginFolder.path, proc(events: seq[PathEvent]) =
      var vfsEvents = newSeq[VFSEvent]()
      for event in events:
        vfsEvents.add (pluginFolder, event.name.normalizeNativePath, event.newName.normalizeNativePath, event.action)
      self.vfsEvents.add vfsEvents
      asyncSpawn self.handleVFSEvents()
    )

proc addPluginFolder(self: PluginService, path: string) {.async.} =
  for it in self.pluginFolders:
    if it.path == path:
      return

  log lvlNotice, &"Add plugin folder '{path}'"
  self.pluginFolders.add PluginDirectory(path: path)
  await self.loadPluginManifests(self.pluginFolders.last)

{.pop.} # raises

template withPluginSystem*(self: PluginService, pluginSystem: untyped, body: untyped): untyped =
  if pluginSystem.isNotNil:
    let oldScriptContext = self.currentPluginSystem
    {.push hint[ConvFromXtoItselfNotNeeded]:off.}
    self.currentPluginSystem = pluginSystem.PluginSystem.some
    {.pop.}
    defer:
      self.currentPluginSystem = oldScriptContext
    body

proc invokeCallback*(self: PluginService, context: string, args: JsonNode): bool =
  try:
    if not self.callbacks.contains(context):
      return false
    let id = self.callbacks[context]

    for sc in self.pluginSystems:
      withPluginSystem self, sc:
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

      for sc in self.pluginSystems:
        withPluginSystem self, sc:
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
      for sc in self.pluginSystems:
        withPluginSystem self, sc:
          let res = sc.handleScriptAction(context, args)
          if res.isNotNil:
            return res
      return nil
    except CatchableError:
      log(lvlError, fmt"Failed to run script handleScriptAction {context}: {getCurrentExceptionMsg()}")
      log(lvlError, getCurrentException().getStackTrace())
      return nil

proc clearScriptActionsFor*(self: PluginService, pluginSystem: PluginSystem) =
  var keysToRemove: seq[string]
  for (key, value) in self.scriptActions.pairs:
    if value.pluginSystem == pluginSystem:
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
  if self.currentPluginSystem.getSome(pluginSystem):
    source.filename = pluginSystem.getCurrentContext() & source.filename

  self.events.getEventHandlerConfig(context).addCommand(subContext, keys, command, source)
  self.events.invalidateCommandToKeysMap()

proc callScriptAction*(self: PluginService, context: string, args: JsonNode): JsonNode {.expose("plugins").} =
  if not self.scriptActions.contains(context):
    log lvlError, fmt"Unknown script action '{context}'"
    return nil
  let action = self.scriptActions[context]
  try:
    withPluginSystem self, action.pluginSystem:
      return action.pluginSystem.handleScriptAction(context, args)
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
  # todo: replace all usages of this with the new plugin system

  if not override and self.scriptActions.contains(name):
    log lvlError, fmt"Duplicate script action {name}"
    return

  if self.currentPluginSystem.isNone:
    log lvlError, fmt"addScriptAction({name}) should only be called from a script"
    return

  self.scriptActions[name] = ScriptAction(name: name, pluginSystem: self.currentPluginSystem.get)

  proc dispatch(arg: JsonNode): JsonNode =
    return self.callScriptAction(name, arg)

  let signature = "(" & params.mapIt(it[0] & ": " & it[1]).join(", ") & ")" & returnType
  {.gcsafe.}:
    if active:
      # todo: use commands for this instead
      extendActiveDispatchTable context, ExposedFunction(name: name, docs: docs, dispatch: dispatch, params: params, returnType: returnType, signature: signature)
    else:
      let id = self.commands.registerCommand(command_service.Command(
        name: name,
        parameters: params.mapIt((it.name, it.typ)),
        returnType: returnType,
        description: docs,
        execute: (proc(args: string): string =
          try:
            var argsJson = newJArray()
            try:
              for a in newStringStream(args).parseJsonFragments():
                argsJson.add a
            except CatchableError as e:
              log(lvlError, fmt"Failed to parse arguments '{args}': {e.msg}")

            let resJson = self.callScriptAction(name, argsJson)
            return $resJson
          except CatchableError as e:
            log lvlError, &"Failed to execute command '{name}': {e.msg}"
            return ""
        )
      ))

addGlobalDispatchTable "plugins", genDispatchTable("plugins")
