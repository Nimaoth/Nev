import std/[macros, genasts, json, strutils, strformat, os]
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
  PluginSystemWasm* = ref object of ScriptContext
    engine: ptr WasmEngineT
    moduleVfs*: VFS
    vfs*: VFS
    services*: Services

    v0: PluginApiBase
    when enableOldPluginVersions:
      v1: PluginApiBase

  WasmPluginInstance* = ref object of PluginInstanceBase
    moduleInstance: WasmModuleInstance
    api: PluginApiBase

proc initPluginApi[T](self: PluginSystemWasm, api: var PluginApiBase) =
  var newApi: T
  new(newApi)
  api = newApi
  api.init(self.services, self.engine)

proc initWasm(self: PluginSystemWasm) =
  let config = newConfig()
  self.engine = newEngine(config)

  self.initPluginApi[:v0.PluginApi](self.v0)
  when enableOldPluginVersions:
    self.initPluginApi[:v1.PluginApi](self.v1)

method init*(self: PluginSystemWasm, path: string, vfs: VFS): Future[void] {.async.} =
  self.vfs = vfs
  self.initWasm()

method deinit*(self: PluginSystemWasm) = discard

method tryLoadPlugin*(self: PluginSystemWasm, plugin: Plugin): Future[bool] {.async: (raises: [IOError]).} =
  log lvlInfo, &"tryLoadPlugin {plugin.desc}"
  if not plugin.manifest.wasm.endsWith(".m.wasm"):
    log lvlInfo, &"Don't load plugin {plugin.desc}, no wasm file specified"
    return false

  var filenameWithoutExtension = plugin.manifest.wasm.splitPath.tail
  filenameWithoutExtension.removeSuffix(".m.wasm")
  let lastPeriod = filenameWithoutExtension.rfind(".")
  let version = if lastPeriod != -1:
    try:
      filenameWithoutExtension[(lastPeriod + 1)..^1].parseInt
    except:
      0
  else:
    0

  plugin.state = PluginState.Loading
  let wasmBytes = self.vfs.read(plugin.manifest.wasm, {Binary}).await
  let module = self.engine.newModule(wasmBytes).okOr(err):
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

  let moduleInstance = api.createModule(module)
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
