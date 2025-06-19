import std/[macros, macrocache, json, strutils, tables, options, sequtils]
import misc/[custom_logger, custom_async, util, myjsonutils]
import expose, document_editor, compilation_config, service, vfs, dispatch_tables

{.push gcsafe.}
{.push raises: [].}

logCategory "plugins"

type
  ScriptContext* = ref object of RootObj

  ScriptAction = object
    name: string
    scriptContext: ScriptContext

  PluginService* = ref object of Service
    scriptContexts*: seq[ScriptContext]
    callbacks*: Table[string, int]
    currentScriptContext*: Option[ScriptContext] = ScriptContext.none

    scriptActions*: Table[string, ScriptAction]

method init*(self: ScriptContext, path: string, vfs: VFS): Future[void] {.base.} = discard
method deinit*(self: ScriptContext) {.base.} = discard
method reload*(self: ScriptContext): Future[void] {.base.} = discard

method handleEditorModeChanged*(self: ScriptContext, editor: DocumentEditor, oldMode: string, newMode: string) {.base.} = discard
method postInitialize*(self: ScriptContext): bool {.base.} = discard
method handleCallback*(self: ScriptContext, id: int, arg: JsonNode): bool {.base.} = discard
method handleAnyCallback*(self: ScriptContext, id: int, arg: JsonNode): JsonNode {.base.} = discard
method handleScriptAction*(self: ScriptContext, name: string, args: JsonNode): JsonNode {.base.} = discard
method getCurrentContext*(self: ScriptContext): string {.base.} = ""

func serviceName*(_: typedesc[PluginService]): string = "PluginService"

addBuiltinService(PluginService)

method init*(self: PluginService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  return ok()

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

proc handleModeChanged*(self: PluginService, editor: DocumentEditor, oldMode: string, newMode: string) =
  try:
    for sc in self.scriptContexts:
      withScriptContext self, sc:
        sc.handleEditorModeChanged(editor, oldMode, newMode)
  except CatchableError:
    log(lvlError, fmt"Failed to run script handleDocumentModeChanged '{oldMode} -> {newMode}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

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
    context: string = "script")
    {.expose("plugins").} =

  if self.scriptActions.contains(name):
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
