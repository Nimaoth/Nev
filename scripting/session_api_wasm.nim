import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc session_setSessionDataJson_void_SessionService_string_JsonNode_bool_wasm(
    arg: cstring): cstring {.importc.}
proc setSessionDataJson*(path: string; value: JsonNode; override: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add value.toJson()
  argsJson.add override.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = session_setSessionDataJson_void_SessionService_string_JsonNode_bool_wasm(
      argsJsonString.cstring)


proc session_getSessionDataJson_JsonNode_SessionService_string_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc getSessionDataJson*(path: string; default: JsonNode): JsonNode {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = session_getSessionDataJson_JsonNode_SessionService_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())

