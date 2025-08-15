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
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc registers_startRecordingKeys_void_Registers_string_wasm(arg: cstring): cstring {.
    importc.}
proc startRecordingKeys*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_startRecordingKeys_void_Registers_string_wasm(
      argsJsonString.cstring)


proc registers_stopRecordingKeys_void_Registers_string_wasm(arg: cstring): cstring {.
    importc.}
proc stopRecordingKeys*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_stopRecordingKeys_void_Registers_string_wasm(
      argsJsonString.cstring)


proc registers_startRecordingCommands_void_Registers_string_wasm(arg: cstring): cstring {.
    importc.}
proc startRecordingCommands*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_startRecordingCommands_void_Registers_string_wasm(
      argsJsonString.cstring)


proc registers_stopRecordingCommands_void_Registers_string_wasm(arg: cstring): cstring {.
    importc.}
proc stopRecordingCommands*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_stopRecordingCommands_void_Registers_string_wasm(
      argsJsonString.cstring)


proc registers_isReplayingCommands_bool_Registers_wasm(arg: cstring): cstring {.
    importc.}
proc isReplayingCommands*(): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = registers_isReplayingCommands_bool_Registers_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc registers_isReplayingKeys_bool_Registers_wasm(arg: cstring): cstring {.
    importc.}
proc isReplayingKeys*(): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = registers_isReplayingKeys_bool_Registers_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc registers_isRecordingCommands_bool_Registers_string_wasm(arg: cstring): cstring {.
    importc.}
proc isRecordingCommands*(registry: string): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add registry.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = registers_isRecordingCommands_bool_Registers_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())

