import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc debugger_prevDebuggerView_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc prevDebuggerView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevDebuggerView_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextDebuggerView_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc nextDebuggerView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextDebuggerView_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_stopDebugSession_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc stopDebugSession*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stopDebugSession_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_stopDebugSessionDelayed_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc stopDebugSessionDelayed*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stopDebugSessionDelayed_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_runConfiguration_void_Debugger_string_wasm(arg: cstring): cstring {.
    importc.}
proc runConfiguration*(name: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_runConfiguration_void_Debugger_string_wasm(
      argsJsonString.cstring)


proc debugger_chooseRunConfiguration_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc chooseRunConfiguration*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_chooseRunConfiguration_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_runLastConfiguration_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc runLastConfiguration*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_runLastConfiguration_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_addBreakpoint_void_Debugger_EditorId_int_wasm(arg: cstring): cstring {.
    importc.}
proc addBreakpoint*(editorId: EditorId; line: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_addBreakpoint_void_Debugger_EditorId_int_wasm(
      argsJsonString.cstring)


proc debugger_continueExecution_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc continueExecution*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_continueExecution_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_stepOver_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc stepOver*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stepOver_void_Debugger_wasm(argsJsonString.cstring)


proc debugger_stepIn_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc stepIn*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stepIn_void_Debugger_wasm(argsJsonString.cstring)


proc debugger_stepOut_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc stepOut*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stepOut_void_Debugger_wasm(argsJsonString.cstring)

