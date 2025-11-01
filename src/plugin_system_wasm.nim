import std/[macros, genasts, strutils, strformat, os, tables]
import misc/[custom_logger, custom_async, util, binary_encoder]
import document_editor, vfs, vfs_service, service
import nimsumtree/[rope, sumtree, arc]
import layout
import text/[text_editor, text_document]
import config_provider, compilation_config, command_service
import plugin_service, wasm_engine
import lisp

import wasmtime
import plugin_api/plugin_api_base

from plugin_api/plugin_api as v0 import nil
from plugin_api/plugin_api_dynamic import nil
when enableOldPluginVersions:
  from plugin_api/plugin_api_1 as v1 import nil

logCategory "plugins-v2"

{.push gcsafe, raises: [].}

type
  PluginSystemWasm* = ref object of PluginSystem
    engine: ptr WasmEngineT
    vfs*: VFS
    services*: Services

    v0: PluginApiBase
    when enableOldPluginVersions:
      v1: PluginApiBase

    env: Env
    currentNamedArgs: LispVal

  WasmPluginInstance* = ref object of PluginInstanceBase
    moduleInstance: WasmModuleInstance
    api: PluginApiBase

method setPermissions*(self: WasmPluginInstance, permissions: PluginPermissions) =
  self.moduleInstance.setPermissions(permissions)

proc initPluginApi[T](self: PluginSystemWasm, api: var PluginApiBase) =
  var newApi: T
  new(newApi)
  api = newApi
  api.init(self.services, self.engine)

proc initWasm(self: PluginSystemWasm) =
  self.engine = getGlobalWasmEngine()

  if self.services.getService(ConfigService).get.runtime.get("plugins.debug", false):
    log lvlError, &"Enable debug info for wasm plugins"
    let config = newConfig()
    config.debugInfoSet(true)
    config.craneliftOptLevelSet(OptLevelNone.OptLevelT)
    self.engine = newEngine(config)

  self.initPluginApi[:v0.PluginApi](self.v0)
  when enableOldPluginVersions:
    self.initPluginApi[:v1.PluginApi](self.v1)

proc newPluginSystemWasm*(services: Services): PluginSystemWasm =
  let self = new PluginSystemWasm
  self.services = services
  self.vfs = services.getService(VFSService).get.vfs

  self.initWasm()

  self.env = baseEnv()
  self.env.onUndefinedSymbol = proc(_: Env, name: string): LispVal =
    self.currentNamedArgs = newMap()
    newFunc(name, proc(args: seq[LispVal]): LispVal =
      try:
        if self.currentNamedArgs == nil:
          self.currentNamedArgs = newMap()
        debugf"dynamic dispatch '{name}' with {args} and {self.currentNamedArgs}"
        return self.dispatchDynamic(name, newList(args), self.currentNamedArgs)
      finally:
        self.currentNamedArgs = nil
    )
  self.env["with"] = newFunc("with", false, proc(args: seq[LispVal]): LispVal {.raises: [LispError].} =
    if self.currentNamedArgs == nil:
      log lvlError, &"Lisp error: 'with' only valid as argument to plugin api"
      return nil
    if args.len != 2 or args[0].kind != Symbol:
      log lvlError, &"Lisp error: 'with' expects two arguments, the first must be a symbol"
      return nil
    debugf"add named arg '{args[0].sym}' = {args[1]}"
    self.currentNamedArgs.fields[args[0].sym] = args[1].eval(self.env)
    return nil
  )

  self.services.getService(CommandService).get.addPrefixCommandHandler "(", proc(command: string): Option[string] =
    try:
      debugf"lisp handler: '{command}'"
      var expr = command.parseLisp()
      let res = expr.eval(self.env)
      if res != nil:
        return some($res)
    except CatchableError as e:
      log lvlError, &"Failed to dispatch API command '{command}': {e.msg}"
    return string.none

  return self

method deinit*(self: PluginSystemWasm) = discard

method tryLoadPlugin*(self: PluginSystemWasm, plugin: Plugin): Future[bool] {.async: (raises: [IOError]).} =
  log lvlInfo, &"tryLoadPlugin {plugin.desc}"
  if not plugin.manifest.wasm.endsWith(".m.wasm") and not plugin.manifest.wasm.endsWith(".wat"):
    log lvlInfo, &"Don't load plugin {plugin.desc}, no wasm file specified"
    return false

  let version = if plugin.manifest.apiVersion >= 0:
    plugin.manifest.apiVersion
  else:
    var filenameWithoutExtension = plugin.manifest.wasm.splitPath.tail
    filenameWithoutExtension.removeSuffix(".m.wasm")
    let lastPeriod = filenameWithoutExtension.rfind(".")
    if lastPeriod != -1:
      try:
        filenameWithoutExtension[(lastPeriod + 1)..^1].parseInt
      except:
        0
    else:
      0

  plugin.state = PluginState.Loading
  let module = if plugin.manifest.wasm.endsWith(".wasm"):
    let wasmBytes = self.vfs.read(plugin.manifest.wasm, {Binary}).await
    self.engine.newModule(wasmBytes).okOr(err):
      log lvlError, &"[host] Failed to create wasm module: {err.msg}"
      plugin.state = PluginState.Failed
      return
  else:
    let wat = self.vfs.read(plugin.manifest.wasm).await
    var wasmBytes: WasmByteVecT
    let err = wat2wasm(cast[ptr UncheckedArray[char]](wat[0].addr), wat.len.csize_t, wasmBytes.addr)
    if err != nil:
      log lvlError, &"[host] Failed to convert wat to wasm module: {err.msg}"
      return

    self.engine.newModule(cast[ptr UncheckedArray[uint8]](wasmBytes.data).toOpenArray(0, wasmBytes.size.int - 1)).okOr(err):
      log lvlError, &"[host] Failed to create wasm module: {err.msg}"
      plugin.state = PluginState.Failed
      return

  log lvlInfo, &"Load plugin '{plugin.manifest.wasm}' using version {version}"
  var api: PluginApiBase = nil
  if version == 0:
    api = self.v0
  else:
    when enableOldPluginVersions:
      case version
      of 1: api = self.v1
      else:
        log lvlError, &"Unsupported version {version} for plugin '{plugin.manifest.wasm}'"
        plugin.state = PluginState.Failed
        return false
    else:
      log lvlError, &"Unsupported version {version} for plugin '{plugin.manifest.wasm}'"
      plugin.state = PluginState.Failed
      return false

  let moduleInstance = api.createModule(module, plugin)
  if moduleInstance == nil:
    log lvlError, &"Failed to instantiate wasm module"
    plugin.state = PluginState.Failed
    return false

  plugin.state = PluginState.Loaded
  plugin.instance = WasmPluginInstance(moduleInstance: moduleInstance, api: api)
  plugin.pluginSystem = self

  return true

method unloadPlugin*(self: PluginSystemWasm, plugin: Plugin): Future[void] {.async: (raises: []).} =
  let instance = plugin.instance.WasmPluginInstance
  instance.api.destroyInstance(instance.moduleInstance)
  plugin.state = Unloaded
  plugin.instance = nil
  plugin.pluginSystem = nil

method dispatchDynamic*(self: PluginSystemWasm, name: string, args: LispVal, namedArgs: LispVal): LispVal =
  self.v0.dispatchDynamic(name, args, namedArgs)

# call function using function table
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
