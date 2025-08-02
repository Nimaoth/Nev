import std/[macros, genasts, json, strutils, strformat]
import misc/[custom_logger, custom_async, util]
import document_editor, vfs, service
import nimsumtree/[rope, sumtree, arc]
import layout
import text/[text_editor, text_document]
import scripting/[binary_encoder, scripting_base], config_provider, compilation_config

import wasmtime
import plugin_api/plugin_api_base

from plugin_api/plugin_api as v0 import nil
when enableOldPluginVersions:
  from plugin_api/plugin_api_1 as v1 import nil

logCategory "plugins-v2"

{.push gcsafe, raises: [].}

type
  WasmPluginSystem* = ref object of ScriptContext
    engine: ptr WasmEngineT
    moduleVfs*: VFS
    vfs*: VFS
    services*: Services

    v0: PluginApiBase
    when enableOldPluginVersions:
      v1: PluginApiBase

# proc call[T](instance: InstanceT, context: ptr ContextT, name: string, parameters: openArray[ValT], nresults: static[int]): T =

#   echo &"[host] ------------------------------- call {name}, {parameters} -------------------------------------"

#   let fun = instance.getExport(context, name)
#   if fun.isNone:
#     echo &"Failed to find export '{name}'"
#     return

#   var trap: ptr WasmTrapT = nil
#   var res: array[max(nresults, 1), ValT]
#   fun.get.of_field.func_field.addr.call(context, parameters, res.toOpenArray(0, nresults - 1), trap.addr).toResult(void).okOr(err):
#     log lvlError, &"[host] Failed to call func '{name}': {err.msg}"
#     return

#   if nresults > 0:
#     echo &"[host] call func {name} -> {res}"

#   when T isnot void:
#     res[0].to(T)

proc loadModules(self: WasmPluginSystem, path: string): Future[void] {.async.} =
  let listing = await self.vfs.getDirectoryListing(path)

  await sleepAsync(1.seconds)

  for file2 in listing.files:
    if not file2.endsWith(".m.wasm"):
      continue

    let file = path // file2

    var filenameWithoutExtension = file2
    filenameWithoutExtension.removeSuffix(".m.wasm")
    let lastPeriod = filenameWithoutExtension.rfind(".")
    let version = if lastPeriod != -1:
      try:
        filenameWithoutExtension[(lastPeriod + 1)..^1].parseInt
      except:
        0
    else:
      0

    let wasmBytes = self.vfs.read(file, {Binary}).await
    let module = self.engine.newModule(wasmBytes).okOr(err):
      log lvlError, &"[host] Failed to create wasm module: {err.msg}"
      continue

    log lvlInfo, &"Load plugin '{file}' using version {version}"
    if version == 0:
      self.v0.createModule(module)
    else:
      when enableOldPluginVersions:
        case version
        of 1: self.v1.createModule(module)
        else:
          log lvlError, &"Unsupported version {version} for plugin '{file}'"
      else:
        log lvlError, &"Unsupported version {version} for plugin '{file}'"

    # let functionTableExport = wasmModule.get.instance.getExport(ctx, "__indirect_function_table")
    # var functionTable = functionTableExport.get.of_field.table
    # echo &"function table {ctx.size(functionTable.addr)}"

    # for cb in self.context.callbacks:
    #   echo &"[host] ============== call callback {cb}"
    #   let fun = functionTable.get(ctx, cb)
    #   if fun.isNone:
    #     echo &"[host] Failed to find callback {cb}"
    #     continue

    #   var results: array[1, ValT]
    #   fun.get.of_field.funcref.addr.call(ctx, [38.int32.toWasmVal], results, trap.addr).toResult(void).okOr(err):
    #     echo &"[host] Failed to call callback {cb}: ", err.msg
    #     continue

    #   echo &"[host] callback {cb} -> {results[0].of_field.i32}"

proc initPluginApi[T](self: WasmPluginSystem, api: var PluginApiBase) =
  # this doesn't work
  # api = newWasmContext(self.services)
  # but this does
  var newApi: T
  new(newApi)
  api = newApi
  # and this also doesn't work... WTF???
  # api = WasmContext()
  api.init(self.services, self.engine)

proc initWasm(self: WasmPluginSystem) =
  let config = newConfig()
  self.engine = newEngine(config)

  self.initPluginApi[:v0.PluginApi](self.v0)
  when enableOldPluginVersions:
    self.initPluginApi[:v1.PluginApi](self.v1)

  # let e = block:
  #   self.linker.defineFuncUnchecked("env", "addCallback", newFunctype([WasmValkind.I32], [])):
  #     discard
  #     let mem = v0.getMemory(caller, store, self.context)
  #     let funcIdxPtr = parameters[0].i32.WasmPtr
  #     let funcIdx = mem.read[:int32](funcIdxPtr)
  #     echo &"[host] addCallback {funcIdxPtr.int} -> {funcIdx}"
  #     self.context.callbacks.add(funcIdx)
  # if e.isErr:
  #   echo "[host] Failed to define component: ", e.err.msg
  # v0.init(self.context, self.services)

method init*(self: WasmPluginSystem, path: string, vfs: VFS): Future[void] {.async.} =
  self.vfs = vfs
  self.initWasm()
  await self.loadModules("app://config/wasm")

method deinit*(self: WasmPluginSystem) = discard

method reload*(self: WasmPluginSystem): Future[void] {.async.} =
  await self.loadModules("app://config/wasm")

method handleScriptAction*(self: WasmPluginSystem, name: string, arg: JsonNode): JsonNode =
  # echo &"handleScriptAction {name}, {arg}"
  try:
    result = nil
    # let argStr = $arg
    # for module in self.modules:
    #   # self.stack.add m
    #   # defer: discard self.stack.pop
    #   try:
    #     discard
    #     # let str = module.instance.call[:string](module.store.context, "handle-command", [name.toWasmVal, argStr.toWasmVal], 1)
    #     # return str.parseJson
    #   except:
    #     # log lvlError, &"Failed to parse json from callback {id}({arg}): '{str}' is not valid json.\n{getCurrentExceptionMsg()}"
    #     continue
  except:
    log lvlError, &"Failed to run handleScriptAction: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
