import wasmtime

let config = newConfig()
var gEngine = newEngine(config)

proc getGlobalWasmEngine*(): ptr WasmEngineT {.gcsafe.} =
  {.gcsafe.}:
    return gEngine
