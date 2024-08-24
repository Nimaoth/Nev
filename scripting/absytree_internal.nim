## This file is auto generated, don't modify.

import std/[json, options]
import scripting_api

template varargs*() {.pragma.}

proc editor_text_getFileName_string_TextDocumentEditor_impl*(
    self: TextDocumentEditor): string =
  discard
proc editor_text_lineCount_int_TextDocumentEditor_impl*(self: TextDocumentEditor): int =
  discard
proc editor_text_lineLength_int_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; line: int): int =
  discard
proc editor_text_screenLineCount_int_TextDocumentEditor_impl*(
    self: TextDocumentEditor): int =
  discard
proc editor_text_doMoveCursorLine_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool = false;
    includeAfter: bool = false): Cursor =
  discard
proc editor_text_doMoveCursorVisualLine_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool = false;
    includeAfter: bool = false): Cursor =
  discard
proc editor_text_doMoveCursorHome_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorEnd_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorVisualHome_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorVisualEnd_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorPrevFindResult_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorNextFindResult_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorLineCenter_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorCenter_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool;
    includeAfter: bool): Cursor =
  discard
proc editor_text_doMoveCursorColumn_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int; wrap: bool = true;
    includeAfter: bool = true): Cursor =
  discard
proc editor_text_findSurroundStart_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_impl*(
    editor: TextDocumentEditor; cursor: Cursor; count: int; c0: char; c1: char;
    depth: int = 1): Option[Cursor] =
  discard
proc editor_text_findSurroundEnd_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_impl*(
    editor: TextDocumentEditor; cursor: Cursor; count: int; c0: char; c1: char;
    depth: int = 1): Option[Cursor] =
  discard
proc editor_text_setMode_void_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; mode: string) =
  discard
proc editor_text_mode_string_TextDocumentEditor_impl*(self: TextDocumentEditor): string =
  discard
proc editor_text_getContextWithMode_string_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; context: string): string =
  discard
proc editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = Last) =
  discard
proc editor_text_invertSelection_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_getRevision_int_TextDocumentEditor_impl*(
    self: TextDocumentEditor): int =
  discard
proc editor_text_getUsage_string_TextDocumentEditor_impl*(
    self: TextDocumentEditor): string =
  discard
proc editor_text_getText_string_TextDocumentEditor_Selection_bool_impl*(
    self: TextDocumentEditor; selection: Selection; inclusiveEnd: bool = false): string =
  discard
proc editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_impl*(
    self: TextDocumentEditor; selections: seq[Selection]; text: string;
    notify: bool = true; record: bool = true): seq[Selection] =
  discard
proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_bool_impl*(
    self: TextDocumentEditor; selections: seq[Selection]; notify: bool = true;
    record: bool = true; inclusiveEnd: bool = false): seq[Selection] =
  discard
proc editor_text_edit_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_bool_impl*(
    self: TextDocumentEditor; selections: seq[Selection]; texts: seq[string];
    notify: bool = true; record: bool = true; inclusiveEnd: bool = false): seq[
    Selection] =
  discard
proc editor_text_deleteLines_void_TextDocumentEditor_Slice_int_Selections_impl*(
    self: TextDocumentEditor; slice: Slice[int]; oldSelections: Selections) =
  discard
proc editor_text_selectPrev_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectNext_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectInside_void_TextDocumentEditor_Cursor_impl*(
    self: TextDocumentEditor; cursor: Cursor) =
  discard
proc editor_text_selectInsideCurrent_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectLine_void_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; line: int) =
  discard
proc editor_text_selectLineCurrent_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectParentTs_void_TextDocumentEditor_Selection_impl*(
    self: TextDocumentEditor; selection: Selection) =
  discard
proc editor_text_printTreesitterTree_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_printTreesitterTreeUnderCursor_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectParentCurrentTs_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_shouldShowCompletionsAt_bool_TextDocumentEditor_Cursor_impl*(
    self: TextDocumentEditor; cursor: Cursor): bool =
  discard
proc editor_text_autoShowCompletions_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_insertText_void_TextDocumentEditor_string_bool_impl*(
    self: TextDocumentEditor; text: string; autoIndent: bool = true) =
  discard
proc editor_text_indent_void_TextDocumentEditor_impl*(self: TextDocumentEditor) =
  discard
proc editor_text_unindent_void_TextDocumentEditor_impl*(self: TextDocumentEditor) =
  discard
proc editor_text_insertIndent_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_undo_void_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; checkpoint: string = "word") =
  discard
proc editor_text_redo_void_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; checkpoint: string = "word") =
  discard
proc editor_text_addNextCheckpoint_void_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; checkpoint: string) =
  discard
proc editor_text_printUndoHistory_void_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; max: int = 50) =
  discard
proc editor_text_copy_void_TextDocumentEditor_string_bool_impl*(
    self: TextDocumentEditor; register: string = ""; inclusiveEnd: bool = false) =
  discard
proc editor_text_paste_void_TextDocumentEditor_string_bool_impl*(
    self: TextDocumentEditor; register: string = ""; inclusiveEnd: bool = false) =
  discard
proc editor_text_scrollText_void_TextDocumentEditor_float32_impl*(
    self: TextDocumentEditor; amount: float32) =
  discard
proc editor_text_scrollLines_void_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; amount: int) =
  discard
proc editor_text_duplicateLastSelection_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_addCursorBelow_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_addCursorAbove_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int = 0;
    includeAfter: bool = true; wrap: bool = true): Selection =
  discard
proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; offset: int = 0;
    includeAfter: bool = true; wrap: bool = true): Selection =
  discard
proc editor_text_getPrevDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; severity: int = 0;
    offset: int = 0; includeAfter: bool = true; wrap: bool = true): Selection =
  discard
proc editor_text_getNextDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_impl*(
    self: TextDocumentEditor; cursor: Cursor; severity: int = 0;
    offset: int = 0; includeAfter: bool = true; wrap: bool = true): Selection =
  discard
proc editor_text_closeDiff_void_TextDocumentEditor_impl*(self: TextDocumentEditor) =
  discard
proc editor_text_getPrevChange_Selection_TextDocumentEditor_Cursor_impl*(
    self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc editor_text_getNextChange_Selection_TextDocumentEditor_Cursor_impl*(
    self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc editor_text_updateDiff_void_TextDocumentEditor_bool_impl*(
    self: TextDocumentEditor; gotoFirstDiff: bool = false) =
  discard
proc editor_text_checkoutFile_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_bool_bool_impl*(
    self: TextDocumentEditor; includeAfter: bool = true; wrap: bool = true) =
  discard
proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_bool_bool_impl*(
    self: TextDocumentEditor; includeAfter: bool = true; wrap: bool = true) =
  discard
proc editor_text_setAllFindResultToSelection_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_clearSelections_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_impl*(
    self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true;
    wrap: bool = true; includeAfter: bool = true) =
  discard
proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_impl*(
    self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true;
    wrap: bool = true; includeAfter: bool = true) =
  discard
proc editor_text_moveCursorVisualLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_impl*(
    self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true;
    wrap: bool = true; includeAfter: bool = true) =
  discard
proc editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true) =
  discard
proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true; includeAfter: bool = true) =
  discard
proc editor_text_moveCursorVisualHome_void_TextDocumentEditor_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true) =
  discard
proc editor_text_moveCursorVisualEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true; includeAfter: bool = true) =
  discard
proc editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true; wrap: bool = true) =
  discard
proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true; wrap: bool = true) =
  discard
proc editor_text_moveCursorLineCenter_void_TextDocumentEditor_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true) =
  discard
proc editor_text_moveCursorCenter_void_TextDocumentEditor_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true) =
  discard
proc editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc editor_text_setNextScrollBehaviour_void_TextDocumentEditor_ScrollBehaviour_impl*(
    self: TextDocumentEditor; scrollBehaviour: ScrollBehaviour) =
  discard
proc editor_text_setCursorScrollOffset_void_TextDocumentEditor_float_SelectionCursor_impl*(
    self: TextDocumentEditor; offset: float;
    cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc editor_text_getContentBounds_Vec2_TextDocumentEditor_impl*(
    self: TextDocumentEditor): Vec2 =
  discard
proc editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_impl*(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc editor_text_reloadTreesitter_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_deleteLeft_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_deleteRight_void_TextDocumentEditor_bool_impl*(
    self: TextDocumentEditor; includeAfter: bool = true) =
  discard
proc editor_text_getCommandCount_int_TextDocumentEditor_impl*(
    self: TextDocumentEditor): int =
  discard
proc editor_text_setCommandCount_void_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; count: int) =
  discard
proc editor_text_setCommandCountRestore_void_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; count: int) =
  discard
proc editor_text_updateCommandCount_void_TextDocumentEditor_int_impl*(
    self: TextDocumentEditor; digit: int) =
  discard
proc editor_text_setFlag_void_TextDocumentEditor_string_bool_impl*(
    self: TextDocumentEditor; name: string; value: bool) =
  discard
proc editor_text_getFlag_bool_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; name: string): bool =
  discard
proc editor_text_runAction_Option_JsonNode_TextDocumentEditor_string_JsonNode_impl*(
    self: TextDocumentEditor; action: string; args: JsonNode): Option[JsonNode] =
  discard
proc editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_impl*(
    self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_impl*(
    self: TextDocumentEditor; cursor: Cursor; delimiter: char): Selection =
  discard
proc editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_impl*(
    self: TextDocumentEditor; cursor: Cursor; open: char; close: char): Selection =
  discard
proc editor_text_extendSelectionWithMove_Selection_TextDocumentEditor_Selection_string_int_impl*(
    self: TextDocumentEditor; selection: Selection; move: string; count: int = 0): Selection =
  discard
proc editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_impl*(
    self: TextDocumentEditor; cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc editor_text_applyMove_void_TextDocumentEditor_JsonNode_impl*(
    self: TextDocumentEditor; args: JsonNode) =
  discard
proc editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_extendSelectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl*(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_impl*(
    self: TextDocumentEditor; move: string;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true;
    count: int = 0) =
  discard
proc editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_impl*(
    self: TextDocumentEditor; move: string;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true;
    count: int = 0) =
  discard
proc editor_text_setSearchQuery_void_TextDocumentEditor_string_bool_string_string_impl*(
    self: TextDocumentEditor; query: string; escapeRegex: bool = false;
    prefix: string = ""; suffix: string = "") =
  discard
proc editor_text_setSearchQueryFromMove_Selection_TextDocumentEditor_string_int_string_string_impl*(
    self: TextDocumentEditor; move: string; count: int = 0; prefix: string = "";
    suffix: string = ""): Selection =
  discard
proc editor_text_toggleLineComment_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoDefinition_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoDeclaration_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoTypeDefinition_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoImplementation_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoReferences_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_switchSourceHeader_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_getCompletions_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoSymbol_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_gotoWorkspaceSymbol_void_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; query: string = "") =
  discard
proc editor_text_hideCompletions_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectPrevCompletion_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectNextCompletion_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_hasTabStops_bool_TextDocumentEditor_impl*(
    self: TextDocumentEditor): bool =
  discard
proc editor_text_clearTabStops_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectNextTabStop_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_selectPrevTabStop_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_applyCompletion_void_TextDocumentEditor_JsonNode_impl*(
    self: TextDocumentEditor; completion: JsonNode) =
  discard
proc editor_text_applySelectedCompletion_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_showHoverFor_void_TextDocumentEditor_Cursor_impl*(
    self: TextDocumentEditor; cursor: Cursor) =
  discard
proc editor_text_showHoverForCurrent_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_hideHover_void_TextDocumentEditor_impl*(self: TextDocumentEditor) =
  discard
proc editor_text_cancelDelayedHideHover_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_hideHoverDelayed_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_clearDiagnostics_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_updateDiagnosticsForCurrent_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_showDiagnosticsForCurrent_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_setReadOnly_void_TextDocumentEditor_bool_impl*(
    self: TextDocumentEditor; readOnly: bool) =
  discard
proc editor_text_setFileReadOnly_void_TextDocumentEditor_bool_impl*(
    self: TextDocumentEditor; readOnly: bool) =
  discard
proc editor_text_isRunningSavedCommands_bool_TextDocumentEditor_impl*(
    self: TextDocumentEditor): bool =
  discard
proc editor_text_runSavedCommands_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_impl*(
    self: TextDocumentEditor; retainLast: bool = false) =
  discard
proc editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_getSelection_Selection_TextDocumentEditor_impl*(
    self: TextDocumentEditor): Selection =
  discard
proc editor_text_setSelection_void_TextDocumentEditor_Selection_impl*(
    self: TextDocumentEditor; selection: Selection) =
  discard
proc editor_text_setTargetSelection_void_TextDocumentEditor_Selection_impl*(
    self: TextDocumentEditor; selection: Selection) =
  discard
proc editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_impl*(
    self: TextDocumentEditor; action: string) =
  discard
proc editor_text_recordCurrentCommand_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_runSingleClickCommand_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_runDoubleClickCommand_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_runTripleClickCommand_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc editor_text_runDragCommand_void_TextDocumentEditor_impl*(
    self: TextDocumentEditor) =
  discard
proc debugger_prevDebuggerView_void_Debugger_impl*() =
  discard
proc debugger_nextDebuggerView_void_Debugger_impl*() =
  discard
proc debugger_setDebuggerView_void_Debugger_string_impl*(view: string) =
  discard
proc debugger_selectFirstVariable_void_Debugger_impl*() =
  discard
proc debugger_selectLastVariable_void_Debugger_impl*() =
  discard
proc debugger_prevThread_void_Debugger_impl*() =
  discard
proc debugger_nextThread_void_Debugger_impl*() =
  discard
proc debugger_prevStackFrame_void_Debugger_impl*() =
  discard
proc debugger_nextStackFrame_void_Debugger_impl*() =
  discard
proc debugger_openFileForCurrentFrame_void_Debugger_impl*() =
  discard
proc debugger_prevVariable_void_Debugger_impl*() =
  discard
proc debugger_nextVariable_void_Debugger_impl*() =
  discard
proc debugger_expandVariable_void_Debugger_impl*() =
  discard
proc debugger_collapseVariable_void_Debugger_impl*() =
  discard
proc debugger_stopDebugSession_void_Debugger_impl*() =
  discard
proc debugger_stopDebugSessionDelayed_void_Debugger_impl*() =
  discard
proc debugger_runConfiguration_void_Debugger_string_impl*(name: string) =
  discard
proc debugger_chooseRunConfiguration_void_Debugger_impl*() =
  discard
proc debugger_runLastConfiguration_void_Debugger_impl*() =
  discard
proc debugger_addBreakpoint_void_Debugger_EditorId_int_impl*(editorId: EditorId;
    line: int) =
  discard
proc debugger_removeBreakpoint_void_Debugger_string_int_impl*(path: string;
    line: int) =
  discard
proc debugger_toggleBreakpointEnabled_void_Debugger_string_int_impl*(
    path: string; line: int) =
  discard
proc debugger_toggleAllBreakpointsEnabled_void_Debugger_impl*() =
  discard
proc debugger_toggleBreakpointsEnabled_void_Debugger_impl*() =
  discard
proc debugger_editBreakpoints_void_Debugger_impl*() =
  discard
proc debugger_continueExecution_void_Debugger_impl*() =
  discard
proc debugger_stepOver_void_Debugger_impl*() =
  discard
proc debugger_stepIn_void_Debugger_impl*() =
  discard
proc debugger_stepOut_void_Debugger_impl*() =
  discard
proc lsp_lspLogVerbose_void_bool_impl*(val: bool) =
  discard
proc lsp_lspToggleLogServerDebug_void_impl*() =
  discard
proc lsp_lspLogServerDebug_void_bool_impl*(val: bool) =
  discard
proc popup_selector_getSelectedItemJson_JsonNode_SelectorPopup_impl*(
    self: SelectorPopup): JsonNode =
  discard
proc popup_selector_accept_void_SelectorPopup_impl*(self: SelectorPopup) =
  discard
proc popup_selector_cancel_void_SelectorPopup_impl*(self: SelectorPopup) =
  discard
proc popup_selector_prev_void_SelectorPopup_int_impl*(self: SelectorPopup;
    count: int = 1) =
  discard
proc popup_selector_next_void_SelectorPopup_int_impl*(self: SelectorPopup;
    count: int = 1) =
  discard
proc popup_selector_toggleFocusPreview_void_SelectorPopup_impl*(
    self: SelectorPopup) =
  discard
proc popup_selector_setFocusPreview_void_SelectorPopup_bool_impl*(
    self: SelectorPopup; focus: bool) =
  discard
proc editor_reapplyConfigKeybindings_void_App_bool_bool_bool_impl*(
    app: bool = false; home: bool = false; workspace: bool = false) =
  discard
proc editor_splitView_void_App_impl*() =
  discard
proc editor_runExternalCommand_void_App_string_seq_string_string_impl*(
    command: string; args: seq[string] = @[]; workingDir: string = "") =
  discard
proc editor_disableLogFrameTime_void_App_bool_impl*(disable: bool) =
  discard
proc editor_showDebuggerView_void_App_impl*() =
  discard
proc editor_setLocationListFromCurrentPopup_void_App_impl*() =
  discard
proc editor_getBackend_Backend_App_impl*(): Backend =
  discard
proc editor_getHostOs_string_App_impl*(): string =
  discard
proc editor_loadApplicationFile_Option_string_App_string_impl*(path: string): Option[
    string] =
  discard
proc editor_toggleShowDrawnNodes_void_App_impl*() =
  discard
proc editor_setMaxViews_void_App_int_bool_impl*(maxViews: int;
    openExisting: bool = false) =
  discard
proc editor_saveAppState_void_App_impl*() =
  discard
proc editor_requestRender_void_App_bool_impl*(redrawEverything: bool = false) =
  discard
proc editor_setHandleInputs_void_App_string_bool_impl*(context: string;
    value: bool) =
  discard
proc editor_setHandleActions_void_App_string_bool_impl*(context: string;
    value: bool) =
  discard
proc editor_setConsumeAllActions_void_App_string_bool_impl*(context: string;
    value: bool) =
  discard
proc editor_setConsumeAllInput_void_App_string_bool_impl*(context: string;
    value: bool) =
  discard
proc editor_clearWorkspaceCaches_void_App_impl*() =
  discard
proc editor_openGithubWorkspace_void_App_string_string_string_impl*(user: string;
    repository: string; branchOrHash: string) =
  discard
proc editor_openAbsytreeServerWorkspace_void_App_string_impl*(url: string) =
  discard
proc editor_callScriptAction_JsonNode_App_string_JsonNode_impl*(context: string;
    args: JsonNode): JsonNode =
  discard
proc editor_addScriptAction_void_App_string_string_seq_tuple_name_string_typ_string_string_bool_string_impl*(
    name: string; docs: string = "";
    params: seq[tuple[name: string, typ: string]] = @[];
    returnType: string = ""; active: bool = false; context: string = "script") =
  discard
proc editor_openLocalWorkspace_void_App_string_impl*(path: string) =
  discard
proc editor_getFlag_bool_App_string_bool_impl*(flag: string;
    default: bool = false): bool =
  discard
proc editor_setFlag_void_App_string_bool_impl*(flag: string; value: bool) =
  discard
proc editor_toggleFlag_void_App_string_impl*(flag: string) =
  discard
proc editor_setOption_void_App_string_JsonNode_bool_impl*(option: string;
    value: JsonNode; override: bool = true) =
  discard
proc editor_quit_void_App_impl*() =
  discard
proc editor_quitImmediately_void_App_int_impl*(exitCode: int = 0) =
  discard
proc editor_help_void_App_string_impl*(about: string = "") =
  discard
proc editor_loadWorkspaceFile_void_App_string_string_impl*(path: string;
    callback: string) =
  discard
proc editor_writeWorkspaceFile_void_App_string_string_impl*(path: string;
    content: string) =
  discard
proc editor_changeFontSize_void_App_float32_impl*(amount: float32) =
  discard
proc editor_changeLineDistance_void_App_float32_impl*(amount: float32) =
  discard
proc editor_platformTotalLineHeight_float32_App_impl*(): float32 =
  discard
proc editor_platformLineHeight_float32_App_impl*(): float32 =
  discard
proc editor_platformLineDistance_float32_App_impl*(): float32 =
  discard
proc editor_changeLayoutProp_void_App_string_float32_impl*(prop: string;
    change: float32) =
  discard
proc editor_toggleStatusBarLocation_void_App_impl*() =
  discard
proc editor_logs_void_App_impl*() =
  discard
proc editor_toggleConsoleLogger_void_App_impl*() =
  discard
proc editor_showEditor_void_App_EditorId_Option_int_impl*(editorId: EditorId;
    viewIndex: Option[int] = int.none) =
  discard
proc editor_getVisibleEditors_seq_EditorId_App_impl*(): seq[EditorId] =
  discard
proc editor_getHiddenEditors_seq_EditorId_App_impl*(): seq[EditorId] =
  discard
proc editor_getExistingEditor_Option_EditorId_App_string_impl*(path: string): Option[
    EditorId] =
  discard
proc editor_getOrOpenEditor_Option_EditorId_App_string_impl*(path: string): Option[
    EditorId] =
  discard
proc editor_closeView_void_App_int_bool_bool_impl*(index: int;
    keepHidden: bool = true; restoreHidden: bool = true) =
  discard
proc editor_closeCurrentView_void_App_bool_bool_impl*(keepHidden: bool = true;
    restoreHidden: bool = true) =
  discard
proc editor_closeOtherViews_void_App_bool_impl*(keepHidden: bool = true) =
  discard
proc editor_moveCurrentViewToTop_void_App_impl*() =
  discard
proc editor_nextView_void_App_impl*() =
  discard
proc editor_prevView_void_App_impl*() =
  discard
proc editor_toggleMaximizeView_void_App_impl*() =
  discard
proc editor_moveCurrentViewPrev_void_App_impl*() =
  discard
proc editor_moveCurrentViewNext_void_App_impl*() =
  discard
proc editor_setLayout_void_App_string_impl*(layout: string) =
  discard
proc editor_commandLine_void_App_string_impl*(initialValue: string = "") =
  discard
proc editor_exitCommandLine_void_App_impl*() =
  discard
proc editor_selectPreviousCommandInHistory_void_App_impl*() =
  discard
proc editor_selectNextCommandInHistory_void_App_impl*() =
  discard
proc editor_executeCommandLine_bool_App_impl*(): bool =
  discard
proc editor_writeFile_void_App_string_bool_impl*(path: string = "";
    appFile: bool = false) =
  discard
proc editor_loadFile_void_App_string_impl*(path: string = "") =
  discard
proc editor_removeFromLocalStorage_void_App_impl*() =
  discard
proc editor_loadTheme_void_App_string_impl*(name: string) =
  discard
proc editor_chooseTheme_void_App_impl*() =
  discard
proc editor_createFile_void_App_string_impl*(path: string) =
  discard
proc editor_browseKeybinds_void_App_impl*() =
  discard
proc editor_chooseFile_void_App_bool_float_float_float_impl*(
    preview: bool = true; scaleX: float = 0.8; scaleY: float = 0.8;
    previewScale: float = 0.5) =
  discard
proc editor_chooseOpen_void_App_bool_float_float_float_impl*(
    preview: bool = true; scaleX: float = 0.8; scaleY: float = 0.8;
    previewScale: float = 0.6) =
  discard
proc editor_chooseOpenDocument_void_App_impl*() =
  discard
proc editor_gotoNextLocation_void_App_impl*() =
  discard
proc editor_gotoPrevLocation_void_App_impl*() =
  discard
proc editor_chooseLocation_void_App_impl*() =
  discard
proc editor_searchGlobalInteractive_void_App_impl*() =
  discard
proc editor_searchGlobal_void_App_string_impl*(query: string) =
  discard
proc editor_installTreesitterParser_void_App_string_string_impl*(
    language: string; host: string = "github.com") =
  discard
proc editor_chooseGitActiveFiles_void_App_bool_impl*(all: bool = false) =
  discard
proc editor_exploreFiles_void_App_string_impl*(root: string = "") =
  discard
proc editor_exploreUserConfigDir_void_App_impl*() =
  discard
proc editor_exploreAppConfigDir_void_App_impl*() =
  discard
proc editor_exploreHelp_void_App_impl*() =
  discard
proc editor_exploreWorkspacePrimary_void_App_impl*() =
  discard
proc editor_exploreCurrentFileDirectory_void_App_impl*() =
  discard
proc editor_openPreviousEditor_void_App_impl*() =
  discard
proc editor_openNextEditor_void_App_impl*() =
  discard
proc editor_setGithubAccessToken_void_App_string_impl*(token: string) =
  discard
proc editor_reloadConfig_void_App_bool_impl*(clearOptions: bool = false) =
  discard
proc editor_reloadPlugin_void_App_impl*() =
  discard
proc editor_reloadState_void_App_impl*() =
  discard
proc editor_saveSession_void_App_string_impl*(sessionFile: string = "") =
  discard
proc editor_logOptions_void_App_impl*() =
  discard
proc editor_dumpKeymapGraphViz_void_App_string_impl*(context: string = "") =
  discard
proc editor_clearCommands_void_App_string_impl*(context: string) =
  discard
proc editor_getAllEditors_seq_EditorId_App_impl*(): seq[EditorId] =
  discard
proc editor_setMode_void_App_string_impl*(mode: string) =
  discard
proc editor_mode_string_App_impl*(): string =
  discard
proc editor_getContextWithMode_string_App_string_impl*(context: string): string =
  discard
proc editor_scriptRunAction_void_string_string_impl*(action: string; arg: string) =
  discard
proc editor_scriptLog_void_string_impl*(message: string) =
  discard
proc editor_changeAnimationSpeed_void_App_float_impl*(factor: float) =
  discard
proc editor_setLeader_void_App_string_impl*(leader: string) =
  discard
proc editor_setLeaders_void_App_seq_string_impl*(leaders: seq[string]) =
  discard
proc editor_addLeader_void_App_string_impl*(leader: string) =
  discard
proc editor_addCommandScript_void_App_string_string_string_string_string_string_impl*(
    context: string; subContext: string; keys: string; action: string;
    arg: string = ""; description: string = "") =
  discard
proc editor_removeCommand_void_App_string_string_impl*(context: string;
    keys: string) =
  discard
proc editor_getActivePopup_EditorId_impl*(): EditorId =
  discard
proc editor_getActiveEditor_EditorId_impl*(): EditorId =
  discard
proc editor_getActiveEditor2_EditorId_App_impl*(): EditorId =
  discard
proc editor_loadCurrentConfig_void_App_impl*() =
  discard
proc editor_logRootNode_void_App_impl*() =
  discard
proc editor_sourceCurrentDocument_void_App_impl*() =
  discard
proc editor_getEditorInView_EditorId_int_impl*(index: int): EditorId =
  discard
proc editor_scriptIsSelectorPopup_bool_EditorId_impl*(editorId: EditorId): bool =
  discard
proc editor_scriptIsTextEditor_bool_EditorId_impl*(editorId: EditorId): bool =
  discard
proc editor_scriptIsAstEditor_bool_EditorId_impl*(editorId: EditorId): bool =
  discard
proc editor_scriptIsModelEditor_bool_EditorId_impl*(editorId: EditorId): bool =
  discard
proc editor_scriptRunActionFor_void_EditorId_string_string_impl*(
    editorId: EditorId; action: string; arg: string) =
  discard
proc editor_scriptInsertTextInto_void_EditorId_string_impl*(editorId: EditorId;
    text: string) =
  discard
proc editor_scriptTextEditorSelection_Selection_EditorId_impl*(editorId: EditorId): Selection =
  discard
proc editor_scriptSetTextEditorSelection_void_EditorId_Selection_impl*(
    editorId: EditorId; selection: Selection) =
  discard
proc editor_scriptTextEditorSelections_seq_Selection_EditorId_impl*(
    editorId: EditorId): seq[Selection] =
  discard
proc editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_impl*(
    editorId: EditorId; selections: seq[Selection]) =
  discard
proc editor_scriptGetTextEditorLine_string_EditorId_int_impl*(editorId: EditorId;
    line: int): string =
  discard
proc editor_scriptGetTextEditorLineCount_int_EditorId_impl*(editorId: EditorId): int =
  discard
proc editor_setSessionDataJson_void_App_string_JsonNode_bool_impl*(path: string;
    value: JsonNode; override: bool = true) =
  discard
proc editor_getSessionDataJson_JsonNode_App_string_JsonNode_impl*(path: string;
    default: JsonNode): JsonNode =
  discard
proc editor_scriptGetOptionJson_JsonNode_string_JsonNode_impl*(path: string;
    default: JsonNode): JsonNode =
  discard
proc editor_scriptGetOptionInt_int_string_int_impl*(path: string; default: int): int =
  discard
proc editor_scriptGetOptionFloat_float_string_float_impl*(path: string;
    default: float): float =
  discard
proc editor_scriptGetOptionBool_bool_string_bool_impl*(path: string;
    default: bool): bool =
  discard
proc editor_scriptGetOptionString_string_string_string_impl*(path: string;
    default: string): string =
  discard
proc editor_scriptSetOptionInt_void_string_int_impl*(path: string; value: int) =
  discard
proc editor_scriptSetOptionFloat_void_string_float_impl*(path: string;
    value: float) =
  discard
proc editor_scriptSetOptionBool_void_string_bool_impl*(path: string; value: bool) =
  discard
proc editor_scriptSetOptionString_void_string_string_impl*(path: string;
    value: string) =
  discard
proc editor_scriptSetCallback_void_string_int_impl*(path: string; id: int) =
  discard
proc editor_setRegisterText_void_App_string_string_impl*(text: string;
    register: string = "") =
  discard
proc editor_getRegisterText_string_App_string_impl*(register: string): string =
  discard
proc editor_startRecordingKeys_void_App_string_impl*(register: string) =
  discard
proc editor_stopRecordingKeys_void_App_string_impl*(register: string) =
  discard
proc editor_startRecordingCommands_void_App_string_impl*(register: string) =
  discard
proc editor_stopRecordingCommands_void_App_string_impl*(register: string) =
  discard
proc editor_isReplayingCommands_bool_App_impl*(): bool =
  discard
proc editor_isReplayingKeys_bool_App_impl*(): bool =
  discard
proc editor_isRecordingCommands_bool_App_string_impl*(registry: string): bool =
  discard
proc editor_replayCommands_void_App_string_impl*(register: string) =
  discard
proc editor_replayKeys_void_App_string_impl*(register: string) =
  discard
proc editor_inputKeys_void_App_string_impl*(input: string) =
  discard
proc editor_collectGarbage_void_App_impl*() =
  discard
proc editor_printStatistics_void_App_impl*() =
  discard
