import service, wasmtime

type PluginApiBase* = ref object of RootObj

{.push gcsafe, raises: [].}

method init*(self: PluginApiBase, services: Services, engine: ptr WasmEngineT) {.base.} = discard
method createModule*(self: PluginApiBase, module: ptr ModuleT) {.base.} = discard
