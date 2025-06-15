import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc debugger_prevDebuggerView_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc prevDebuggerView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevDebuggerView_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextDebuggerView_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc nextDebuggerView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextDebuggerView_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_setDebuggerView_void_Debugger_string_wasm(arg: cstring): cstring {.
    importc.}
proc setDebuggerView*(view: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add view.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_setDebuggerView_void_Debugger_string_wasm(
      argsJsonString.cstring)


proc debugger_selectFirstVariable_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc selectFirstVariable*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_selectFirstVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_selectLastVariable_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc selectLastVariable*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_selectLastVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_prevThread_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc prevThread*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevThread_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextThread_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc nextThread*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextThread_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_prevStackFrame_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc prevStackFrame*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevStackFrame_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextStackFrame_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc nextStackFrame*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextStackFrame_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_openFileForCurrentFrame_void_Debugger_string_wasm(arg: cstring): cstring {.
    importc.}
proc openFileForCurrentFrame*(slot: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_openFileForCurrentFrame_void_Debugger_string_wasm(
      argsJsonString.cstring)


proc debugger_prevVariable_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc prevVariable*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_prevVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_nextVariable_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc nextVariable*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_nextVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_expandVariable_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc expandVariable*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_expandVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_collapseVariable_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc collapseVariable*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_collapseVariable_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_stopDebugSession_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc stopDebugSession*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stopDebugSession_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_stopDebugSessionDelayed_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc stopDebugSessionDelayed*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stopDebugSessionDelayed_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_runConfiguration_void_Debugger_string_wasm(arg: cstring): cstring {.
    importc.}
proc runConfiguration*(name: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_runConfiguration_void_Debugger_string_wasm(
      argsJsonString.cstring)


proc debugger_chooseRunConfiguration_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc chooseRunConfiguration*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_chooseRunConfiguration_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_runLastConfiguration_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc runLastConfiguration*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_runLastConfiguration_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_addBreakpoint_void_Debugger_EditorId_int_wasm(arg: cstring): cstring {.
    importc.}
proc addBreakpoint*(editorId: EditorId; line: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  argsJson.add line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_addBreakpoint_void_Debugger_EditorId_int_wasm(
      argsJsonString.cstring)


proc debugger_removeBreakpoint_void_Debugger_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc removeBreakpoint*(path: string; line: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_removeBreakpoint_void_Debugger_string_int_wasm(
      argsJsonString.cstring)


proc debugger_toggleBreakpointEnabled_void_Debugger_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc toggleBreakpointEnabled*(path: string; line: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_toggleBreakpointEnabled_void_Debugger_string_int_wasm(
      argsJsonString.cstring)


proc debugger_toggleAllBreakpointsEnabled_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc toggleAllBreakpointsEnabled*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_toggleAllBreakpointsEnabled_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_toggleBreakpointsEnabled_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc toggleBreakpointsEnabled*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_toggleBreakpointsEnabled_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_editBreakpoints_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc editBreakpoints*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_editBreakpoints_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_continueExecution_void_Debugger_wasm(arg: cstring): cstring {.
    importc.}
proc continueExecution*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_continueExecution_void_Debugger_wasm(
      argsJsonString.cstring)


proc debugger_stepOver_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc stepOver*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stepOver_void_Debugger_wasm(argsJsonString.cstring)


proc debugger_stepIn_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc stepIn*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stepIn_void_Debugger_wasm(argsJsonString.cstring)


proc debugger_stepOut_void_Debugger_wasm(arg: cstring): cstring {.importc.}
proc stepOut*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = debugger_stepOut_void_Debugger_wasm(argsJsonString.cstring)

