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


proc debugger_setDebuggerView_void_Debugger_string_wasm(arg: cstring): cstring {.
    importc.}
proc setDebuggerView*(view: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      view
    else:
      view.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_setDebuggerView_void_Debugger_string_wasm(
      argsJsonString.cstring)


proc debugger_selectFirstVariable_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc selectFirstVariable*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_selectFirstVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_selectLastVariable_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc selectLastVariable*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_selectLastVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_prevThread_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc prevThread*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevThread_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextThread_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc nextThread*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextThread_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_prevStackFrame_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc prevStackFrame*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevStackFrame_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextStackFrame_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc nextStackFrame*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextStackFrame_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_openFileForCurrentFrame_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc openFileForCurrentFrame*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_openFileForCurrentFrame_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_prevVariable_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc prevVariable*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextVariable_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc nextVariable*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_expandVariable_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc expandVariable*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_expandVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_collapseVariable_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc collapseVariable*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_collapseVariable_void_Debugger_wasm(
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

