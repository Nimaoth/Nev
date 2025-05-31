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


proc terminal_createTerminal_void_TerminalService_string_CreateTerminalOptions_wasm(
    arg: cstring): cstring {.importc.}
proc createTerminal*(command: string = "";
                     options: CreateTerminalOptions = CreateTerminalOptions()) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add command.toJson()
  argsJson.add options.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_createTerminal_void_TerminalService_string_CreateTerminalOptions_wasm(
      argsJsonString.cstring)


proc terminal_runInTerminal_void_TerminalService_string_string_CreateTerminalOptions_wasm(
    arg: cstring): cstring {.importc.}
proc runInTerminal*(shell: string; command: string;
                    options: CreateTerminalOptions = CreateTerminalOptions()) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add shell.toJson()
  argsJson.add command.toJson()
  argsJson.add options.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_runInTerminal_void_TerminalService_string_string_CreateTerminalOptions_wasm(
      argsJsonString.cstring)


proc terminal_scrollTerminal_void_TerminalService_int_wasm(arg: cstring): cstring {.
    importc.}
proc scrollTerminal*(amount: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_scrollTerminal_void_TerminalService_int_wasm(
      argsJsonString.cstring)


proc terminal_sendTerminalInput_void_TerminalService_string_wasm(arg: cstring): cstring {.
    importc.}
proc sendTerminalInput*(input: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add input.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_sendTerminalInput_void_TerminalService_string_wasm(
      argsJsonString.cstring)


proc terminal_sendTerminalInputAndSetMode_void_TerminalService_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc sendTerminalInputAndSetMode*(input: string; mode: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add input.toJson()
  argsJson.add mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_sendTerminalInputAndSetMode_void_TerminalService_string_string_wasm(
      argsJsonString.cstring)


proc terminal_editTerminalBuffer_void_TerminalService_wasm(arg: cstring): cstring {.
    importc.}
proc editTerminalBuffer*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_editTerminalBuffer_void_TerminalService_wasm(
      argsJsonString.cstring)


proc terminal_selectTerminal_void_TerminalService_bool_float_float_float_wasm(
    arg: cstring): cstring {.importc.}
proc selectTerminal*(preview: bool = true; scaleX: float = 0.8;
                     scaleY: float = 0.8; previewScale: float = 0.6) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add preview.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = terminal_selectTerminal_void_TerminalService_bool_float_float_float_wasm(
      argsJsonString.cstring)

