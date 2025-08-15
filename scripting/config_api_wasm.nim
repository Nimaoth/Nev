import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc config_logOptions_void_ConfigService_wasm(arg: cstring): cstring {.importc.}
proc logOptions*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = config_logOptions_void_ConfigService_wasm(
      argsJsonString.cstring)


proc config_setOption_void_ConfigService_string_JsonNode_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setOption*(option: string; value: JsonNode; override: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add option.toJson()
  argsJson.add value.toJson()
  argsJson.add override.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = config_setOption_void_ConfigService_string_JsonNode_bool_wasm(
      argsJsonString.cstring)


proc config_getFlag_bool_ConfigService_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc getFlag*(flag: string; default: bool = false): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add flag.toJson()
  argsJson.add default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = config_getFlag_bool_ConfigService_string_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc config_setFlag_void_ConfigService_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setFlag*(flag: string; value: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add flag.toJson()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = config_setFlag_void_ConfigService_string_bool_wasm(
      argsJsonString.cstring)


proc config_toggleFlag_void_ConfigService_string_wasm(arg: cstring): cstring {.
    importc.}
proc toggleFlag*(flag: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add flag.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = config_toggleFlag_void_ConfigService_string_wasm(
      argsJsonString.cstring)

