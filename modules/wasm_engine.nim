import wasmtime

const currentSourcePath2 = currentSourcePath()
include module_base

proc getGlobalWasmEngine*(): ptr WasmEngineT {.modrtl, gcsafe, raises: [].}

when implModule:
  let config = newConfig()
  var gEngine = newEngine(config)

  proc getGlobalWasmEngine*(): ptr WasmEngineT =
    {.gcsafe.}:
      return gEngine
