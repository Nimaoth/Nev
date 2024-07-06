import std/[json, options]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc prevDebuggerView*() =
  debugger_prevDebuggerView_void_Debugger_impl()
proc nextDebuggerView*() =
  debugger_nextDebuggerView_void_Debugger_impl()
proc setDebuggerView*(view: string) =
  debugger_setDebuggerView_void_Debugger_string_impl(view)
proc selectFirstVariable*() =
  debugger_selectFirstVariable_void_Debugger_impl()
proc selectLastVariable*() =
  debugger_selectLastVariable_void_Debugger_impl()
proc prevThread*() =
  debugger_prevThread_void_Debugger_impl()
proc nextThread*() =
  debugger_nextThread_void_Debugger_impl()
proc prevStackFrame*() =
  debugger_prevStackFrame_void_Debugger_impl()
proc nextStackFrame*() =
  debugger_nextStackFrame_void_Debugger_impl()
proc openFileForCurrentFrame*() =
  debugger_openFileForCurrentFrame_void_Debugger_impl()
proc prevVariable*() =
  debugger_prevVariable_void_Debugger_impl()
proc nextVariable*() =
  debugger_nextVariable_void_Debugger_impl()
proc expandVariable*() =
  debugger_expandVariable_void_Debugger_impl()
proc collapseVariable*() =
  debugger_collapseVariable_void_Debugger_impl()
proc stopDebugSession*() =
  debugger_stopDebugSession_void_Debugger_impl()
proc stopDebugSessionDelayed*() =
  debugger_stopDebugSessionDelayed_void_Debugger_impl()
proc runConfiguration*(name: string) =
  debugger_runConfiguration_void_Debugger_string_impl(name)
proc chooseRunConfiguration*() =
  debugger_chooseRunConfiguration_void_Debugger_impl()
proc runLastConfiguration*() =
  debugger_runLastConfiguration_void_Debugger_impl()
proc addBreakpoint*(editorId: EditorId; line: int) =
  ## Line is 0-based
  debugger_addBreakpoint_void_Debugger_EditorId_int_impl(editorId, line)
proc removeBreakpoint*(path: string; line: int) =
  ## Line is 1-based
  debugger_removeBreakpoint_void_Debugger_string_int_impl(path, line)
proc toggleBreakpointEnabled*(path: string; line: int) =
  ## Line is 1-based
  debugger_toggleBreakpointEnabled_void_Debugger_string_int_impl(path, line)
proc toggleAllBreakpointsEnabled*() =
  debugger_toggleAllBreakpointsEnabled_void_Debugger_impl()
proc toggleBreakpointsEnabled*() =
  debugger_toggleBreakpointsEnabled_void_Debugger_impl()
proc editBreakpoints*() =
  debugger_editBreakpoints_void_Debugger_impl()
proc continueExecution*() =
  debugger_continueExecution_void_Debugger_impl()
proc stepOver*() =
  debugger_stepOver_void_Debugger_impl()
proc stepIn*() =
  debugger_stepIn_void_Debugger_impl()
proc stepOut*() =
  debugger_stepOut_void_Debugger_impl()
