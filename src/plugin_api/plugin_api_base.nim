import service, wasmtime, plugin_service

type
  PluginApiBase* = ref object of RootObj
  WasmModuleInstance* = ref object of RootObj

{.push gcsafe, raises: [].}

method init*(self: PluginApiBase, services: Services, engine: ptr WasmEngineT) {.base.} = discard
method createModule*(self: PluginApiBase, module: ptr ModuleT, permissions: PluginPermissions): WasmModuleInstance {.base.} = discard
method destroyInstance*(self: PluginApiBase, instance: WasmModuleInstance) {.base.} = discard

method setPermissions*(instance: WasmModuleInstance, permissions: PluginPermissions) {.base.} = discard
