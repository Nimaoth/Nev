import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc commands_commandLine_void_CommandService_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc commandLine*(initialValue: string = ""; prefix: string = "") {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add initialValue.toJson()
  argsJson.add prefix.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = commands_commandLine_void_CommandService_string_string_wasm(
      argsJsonString.cstring)


proc commands_commandLineResult_void_CommandService_string_wasm(arg: cstring): cstring {.
    importc.}
proc commandLineResult*(value: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = commands_commandLineResult_void_CommandService_string_wasm(
      argsJsonString.cstring)


proc commands_exitCommandLine_void_CommandService_wasm(arg: cstring): cstring {.
    importc.}
proc exitCommandLine*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = commands_exitCommandLine_void_CommandService_wasm(
      argsJsonString.cstring)


proc commands_executeCommandLine_bool_CommandService_wasm(arg: cstring): cstring {.
    importc.}
proc executeCommandLine*(): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = commands_executeCommandLine_bool_CommandService_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc commands_selectPreviousCommandInHistory_void_CommandService_wasm(
    arg: cstring): cstring {.importc.}
proc selectPreviousCommandInHistory*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = commands_selectPreviousCommandInHistory_void_CommandService_wasm(
      argsJsonString.cstring)


proc commands_selectNextCommandInHistory_void_CommandService_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextCommandInHistory*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = commands_selectNextCommandInHistory_void_CommandService_wasm(
      argsJsonString.cstring)


proc commands_runShellCommand_void_CommandService_string_wasm(arg: cstring): cstring {.
    importc.}
proc runShellCommand*(initialValue: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add initialValue.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = commands_runShellCommand_void_CommandService_string_wasm(
      argsJsonString.cstring)

