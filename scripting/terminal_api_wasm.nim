import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc terminal_setTerminalMode_void_TerminalService_string_wasm(arg: cstring): cstring {.
    importc.}
proc setTerminalMode*(mode: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_setTerminalMode_void_TerminalService_string_wasm(
      argsJsonString.cstring)


proc terminal_createTerminal_void_TerminalService_wasm(arg: cstring): cstring {.
    importc.}
proc createTerminal*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_createTerminal_void_TerminalService_wasm(
      argsJsonString.cstring)

