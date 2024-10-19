import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc registers_setRegisterText_void_Registers_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc setRegisterText*(text: string; register: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add text.toJson()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_setRegisterText_void_Registers_string_string_wasm(
      argsJsonString.cstring)


proc registers_getRegisterText_string_Registers_string_wasm(arg: cstring): cstring {.
    importc.}
proc getRegisterText*(register: string): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_getRegisterText_string_Registers_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())

