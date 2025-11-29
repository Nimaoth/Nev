import service, wasmtime, plugin_service, lisp

type
  PluginApiBase* = ref object of RootObj
  WasmModuleInstance* = ref object of RootObj

{.push gcsafe, raises: [].}

method init*(self: PluginApiBase, services: Services, engine: ptr WasmEngineT) {.base.} = discard
method createModule*(self: PluginApiBase, module: ptr ModuleT, plugin: Plugin, state: seq[uint8]): WasmModuleInstance {.base.} = discard
method destroyInstance*(self: PluginApiBase, instance: WasmModuleInstance) {.base.} = discard
method dispatchDynamic*(self: PluginApiBase, name: string, args: LispVal, namedArgs: LispVal): LispVal {.base.} = discard
method savePluginState*(self: PluginApiBase, instance: WasmModuleInstance): seq[uint8] {.base.} = @[]

method setPermissions*(instance: WasmModuleInstance, permissions: PluginPermissions) {.base.} = discard
