import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc lsp_lspLogVerbose_void_bool_wasm(arg: cstring): cstring {.importc.}
proc lspLogVerbose*(val: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      val
    else:
      val.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = lsp_lspLogVerbose_void_bool_wasm(argsJsonString.cstring)


proc lsp_lspLogServerDebug_void_bool_wasm(arg: cstring): cstring {.importc.}
proc lspLogServerDebug*(val: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      val
    else:
      val.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = lsp_lspLogServerDebug_void_bool_wasm(argsJsonString.cstring)

