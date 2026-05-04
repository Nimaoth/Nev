import wasmtime

include dynlib_export

proc getGlobalWasmEngine*(): ptr WasmEngineT {.apprtl, gcsafe, raises: [].}

when implModule:
  let config = newConfig()
  var gEngine = newEngine(config)

  proc getGlobalWasmEngine*(): ptr WasmEngineT =
    {.gcsafe.}:
      return gEngine
