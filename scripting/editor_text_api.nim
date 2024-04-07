import std/[json, options]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc lineCount*(self: TextDocumentEditor): int =
  editor_text_lineCount_int_TextDocumentEditor_impl(self)
proc lineLength*(self: TextDocumentEditor; line: int): int =
  editor_text_lineLength_int_TextDocumentEditor_int_impl(self, line)
proc screenLineCount*(self: TextDocumentEditor): int =
  ## Returns the number of lines that can be shown on the screen
  ## This value depends on the size of the view this editor is in and the font size
  editor_text_screenLineCount_int_TextDocumentEditor_impl(self)
proc doMoveCursorColumn*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                         wrap: bool = true; includeAfter: bool = true): Cursor =
  editor_text_doMoveCursorColumn_Cursor_TextDocumentEditor_Cursor_int_bool_bool_impl(
      self, cursor, offset, wrap, includeAfter)
proc findSurroundStart*(editor: TextDocumentEditor; cursor: Cursor; count: int;
                        c0: char; c1: char; depth: int = 1): Option[Cursor] =
  editor_text_findSurroundStart_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_impl(
      editor, cursor, count, c0, c1, depth)
proc findSurroundEnd*(editor: TextDocumentEditor; cursor: Cursor; count: int;
                      c0: char; c1: char; depth: int = 1): Option[Cursor] =
  editor_text_findSurroundEnd_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_impl(
      editor, cursor, count, c0, c1, depth)
proc setMode*(self: TextDocumentEditor; mode: string) =
  ## Sets the current mode of the editor. If `mode` is "", then no additional scope will be pushed on the scope stac.k
  ## If mode is e.g. "insert", then the scope "editor.text.insert" will be pushed on the scope stack above "editor.text"
  ## Don't use "completion", as that is used for when a completion window is open.
  editor_text_setMode_void_TextDocumentEditor_string_impl(self, mode)
proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  editor_text_mode_string_TextDocumentEditor_impl(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  ## Appends the current mode to context
  editor_text_getContextWithMode_string_TextDocumentEditor_string_impl(self,
      context)
proc updateTargetColumn*(self: TextDocumentEditor;
                         cursor: SelectionCursor = Last) =
  editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_impl(
      self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  ## Inverts the current selection. Discards all but the last cursor.
  editor_text_invertSelection_void_TextDocumentEditor_impl(self)
proc getText*(self: TextDocumentEditor; selection: Selection;
              inclusiveEnd: bool = false): string =
  editor_text_getText_string_TextDocumentEditor_Selection_bool_impl(self,
      selection, inclusiveEnd)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true): seq[Selection] =
  editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_impl(
      self, selections, text, notify, record)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true;
             inclusiveEnd: bool = false): seq[Selection] =
  editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_bool_impl(
      self, selections, notify, record, inclusiveEnd)
proc edit*(self: TextDocumentEditor; selections: seq[Selection];
           texts: seq[string]; notify: bool = true; record: bool = true;
           inclusiveEnd: bool = false): seq[Selection] =
  editor_text_edit_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_bool_impl(
      self, selections, texts, notify, record, inclusiveEnd)
proc deleteLines*(self: TextDocumentEditor; slice: Slice[int];
                  oldSelections: Selections) =
  editor_text_deleteLines_void_TextDocumentEditor_Slice_int_Selections_impl(
      self, slice, oldSelections)
proc selectPrev*(self: TextDocumentEditor) =
  editor_text_selectPrev_void_TextDocumentEditor_impl(self)
proc selectNext*(self: TextDocumentEditor) =
  editor_text_selectNext_void_TextDocumentEditor_impl(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  editor_text_selectInside_void_TextDocumentEditor_Cursor_impl(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  editor_text_selectInsideCurrent_void_TextDocumentEditor_impl(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  editor_text_selectLine_void_TextDocumentEditor_int_impl(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  editor_text_selectLineCurrent_void_TextDocumentEditor_impl(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  editor_text_selectParentTs_void_TextDocumentEditor_Selection_impl(self,
      selection)
proc printTreesitterTree*(self: TextDocumentEditor) =
  editor_text_printTreesitterTree_void_TextDocumentEditor_impl(self)
proc printTreesitterTreeUnderCursor*(self: TextDocumentEditor) =
  editor_text_printTreesitterTreeUnderCursor_void_TextDocumentEditor_impl(self)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  editor_text_selectParentCurrentTs_void_TextDocumentEditor_impl(self)
proc insertText*(self: TextDocumentEditor; text: string; autoIndent: bool = true) =
  editor_text_insertText_void_TextDocumentEditor_string_bool_impl(self, text,
      autoIndent)
proc indent*(self: TextDocumentEditor) =
  editor_text_indent_void_TextDocumentEditor_impl(self)
proc unindent*(self: TextDocumentEditor) =
  editor_text_unindent_void_TextDocumentEditor_impl(self)
proc undo*(self: TextDocumentEditor; checkpoint: string = "word") =
  editor_text_undo_void_TextDocumentEditor_string_impl(self, checkpoint)
proc redo*(self: TextDocumentEditor; checkpoint: string = "word") =
  editor_text_redo_void_TextDocumentEditor_string_impl(self, checkpoint)
proc addNextCheckpoint*(self: TextDocumentEditor; checkpoint: string) =
  editor_text_addNextCheckpoint_void_TextDocumentEditor_string_impl(self,
      checkpoint)
proc printUndoHistory*(self: TextDocumentEditor; max: int = 50) =
  editor_text_printUndoHistory_void_TextDocumentEditor_int_impl(self, max)
proc copy*(self: TextDocumentEditor; register: string = "";
           inclusiveEnd: bool = false) =
  editor_text_copy_void_TextDocumentEditor_string_bool_impl(self, register,
      inclusiveEnd)
proc paste*(self: TextDocumentEditor; register: string = "";
            inclusiveEnd: bool = false) =
  editor_text_paste_void_TextDocumentEditor_string_bool_impl(self, register,
      inclusiveEnd)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  editor_text_scrollText_void_TextDocumentEditor_float32_impl(self, amount)
proc scrollLines*(self: TextDocumentEditor; amount: int) =
  ## Scroll the text up (positive) or down (negative) by the given number of lines
  editor_text_scrollLines_void_TextDocumentEditor_int_impl(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  editor_text_duplicateLastSelection_void_TextDocumentEditor_impl(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  editor_text_addCursorBelow_void_TextDocumentEditor_impl(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  editor_text_addCursorAbove_void_TextDocumentEditor_impl(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0; includeAfter: bool = true;
                        wrap: bool = true): Selection =
  editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_impl(
      self, cursor, offset, includeAfter, wrap)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0; includeAfter: bool = true;
                        wrap: bool = true): Selection =
  editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_impl(
      self, cursor, offset, includeAfter, wrap)
proc getPrevDiagnostic*(self: TextDocumentEditor; cursor: Cursor;
                        severity: int = 0; offset: int = 0;
                        includeAfter: bool = true; wrap: bool = true): Selection =
  editor_text_getPrevDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_impl(
      self, cursor, severity, offset, includeAfter, wrap)
proc getNextDiagnostic*(self: TextDocumentEditor; cursor: Cursor;
                        severity: int = 0; offset: int = 0;
                        includeAfter: bool = true; wrap: bool = true): Selection =
  editor_text_getNextDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_impl(
      self, cursor, severity, offset, includeAfter, wrap)
proc closeDiff*(self: TextDocumentEditor) =
  editor_text_closeDiff_void_TextDocumentEditor_impl(self)
proc getPrevChange*(self: TextDocumentEditor; cursor: Cursor): Selection =
  editor_text_getPrevChange_Selection_TextDocumentEditor_Cursor_impl(self,
      cursor)
proc getNextChange*(self: TextDocumentEditor; cursor: Cursor): Selection =
  editor_text_getNextChange_Selection_TextDocumentEditor_Cursor_impl(self,
      cursor)
proc updateDiff*(self: TextDocumentEditor) =
  editor_text_updateDiff_void_TextDocumentEditor_impl(self)
proc addNextFindResultToSelection*(self: TextDocumentEditor;
                                   includeAfter: bool = true; wrap: bool = true) =
  editor_text_addNextFindResultToSelection_void_TextDocumentEditor_bool_bool_impl(
      self, includeAfter, wrap)
proc addPrevFindResultToSelection*(self: TextDocumentEditor;
                                   includeAfter: bool = true; wrap: bool = true) =
  editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_bool_bool_impl(
      self, includeAfter, wrap)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  editor_text_setAllFindResultToSelection_void_TextDocumentEditor_impl(self)
proc clearSelections*(self: TextDocumentEditor) =
  editor_text_clearSelections_void_TextDocumentEditor_impl(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true; wrap: bool = true;
                       includeAfter: bool = true) =
  editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_impl(
      self, distance, cursor, all, wrap, includeAfter)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true; wrap: bool = true;
                     includeAfter: bool = true) =
  editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_impl(
      self, distance, cursor, all, wrap, includeAfter)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_impl(
      self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true; includeAfter: bool = true) =
  editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_impl(
      self, cursor, all, includeAfter)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_impl(
      self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_impl(
      self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; wrap: bool = true) =
  editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_impl(
      self, cursor, all, wrap)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; wrap: bool = true) =
  editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_impl(
      self, cursor, all, wrap)
proc moveCursorLineCenter*(self: TextDocumentEditor;
                           cursor: SelectionCursor = SelectionCursor.Config;
                           all: bool = true) =
  editor_text_moveCursorLineCenter_void_TextDocumentEditor_SelectionCursor_bool_impl(
      self, cursor, all)
proc moveCursorCenter*(self: TextDocumentEditor;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  editor_text_moveCursorCenter_void_TextDocumentEditor_SelectionCursor_bool_impl(
      self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_impl(self,
      cursor)
proc setNextScrollBehaviour*(self: TextDocumentEditor;
                             scrollBehaviour: ScrollBehaviour) =
  editor_text_setNextScrollBehaviour_void_TextDocumentEditor_ScrollBehaviour_impl(
      self, scrollBehaviour)
proc setCursorScrollOffset*(self: TextDocumentEditor; offset: float;
                            cursor: SelectionCursor = SelectionCursor.Config) =
  editor_text_setCursorScrollOffset_void_TextDocumentEditor_float_SelectionCursor_impl(
      self, offset, cursor)
proc getContentBounds*(self: TextDocumentEditor): Vec2 =
  editor_text_getContentBounds_Vec2_TextDocumentEditor_impl(self)
proc centerCursor*(self: TextDocumentEditor;
                   cursor: SelectionCursor = SelectionCursor.Config) =
  editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_impl(self,
      cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  editor_text_reloadTreesitter_void_TextDocumentEditor_impl(self)
proc deleteLeft*(self: TextDocumentEditor) =
  editor_text_deleteLeft_void_TextDocumentEditor_impl(self)
proc deleteRight*(self: TextDocumentEditor; includeAfter: bool = true) =
  editor_text_deleteRight_void_TextDocumentEditor_bool_impl(self, includeAfter)
proc getCommandCount*(self: TextDocumentEditor): int =
  editor_text_getCommandCount_int_TextDocumentEditor_impl(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  editor_text_setCommandCount_void_TextDocumentEditor_int_impl(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  editor_text_setCommandCountRestore_void_TextDocumentEditor_int_impl(self,
      count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  editor_text_updateCommandCount_void_TextDocumentEditor_int_impl(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  editor_text_setFlag_void_TextDocumentEditor_string_bool_impl(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  editor_text_getFlag_bool_TextDocumentEditor_string_impl(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_impl(self,
      action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_impl(self,
      cursor)
proc getSelectionInPair*(self: TextDocumentEditor; cursor: Cursor;
                         delimiter: char): Selection =
  editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_impl(
      self, cursor, delimiter)
proc getSelectionInPairNested*(self: TextDocumentEditor; cursor: Cursor;
                               open: char; close: char): Selection =
  editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_impl(
      self, cursor, open, close)
proc extendSelectionWithMove*(self: TextDocumentEditor; selection: Selection;
                              move: string; count: int = 0): Selection =
  editor_text_extendSelectionWithMove_Selection_TextDocumentEditor_Selection_string_int_impl(
      self, selection, move, count)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_impl(
      self, cursor, move, count)
proc applyMove*(self: TextDocumentEditor; args {.varargs.}: JsonNode) =
  editor_text_applyMove_void_TextDocumentEditor_JsonNode_impl(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  ## Deletes text based on the current selections.
  ## 
  ## `move` specifies which move should be applied to each selection.
  editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
      self, move, inside, which, all)
proc selectMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
      self, move, inside, which, all)
proc extendSelectMove*(self: TextDocumentEditor; move: string;
                       inside: bool = false;
                       which: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  editor_text_extendSelectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
      self, move, inside, which, all)
proc copyMove*(self: TextDocumentEditor; move: string; inside: bool = false;
               which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
      self, move, inside, which, all)
proc changeMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
      self, move, inside, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_impl(
      self, move, which, all, count)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_impl(
      self, move, which, all, count)
proc setSearchQuery*(self: TextDocumentEditor; query: string;
                     escapeRegex: bool = false) =
  editor_text_setSearchQuery_void_TextDocumentEditor_string_bool_impl(self,
      query, escapeRegex)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0; prefix: string = "";
                             suffix: string = ""): Selection =
  editor_text_setSearchQueryFromMove_Selection_TextDocumentEditor_string_int_string_string_impl(
      self, move, count, prefix, suffix)
proc toggleLineComment*(self: TextDocumentEditor) =
  editor_text_toggleLineComment_void_TextDocumentEditor_impl(self)
proc gotoDefinition*(self: TextDocumentEditor) =
  editor_text_gotoDefinition_void_TextDocumentEditor_impl(self)
proc getCompletions*(self: TextDocumentEditor) =
  editor_text_getCompletions_void_TextDocumentEditor_impl(self)
proc gotoSymbol*(self: TextDocumentEditor) =
  editor_text_gotoSymbol_void_TextDocumentEditor_impl(self)
proc hideCompletions*(self: TextDocumentEditor) =
  editor_text_hideCompletions_void_TextDocumentEditor_impl(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  editor_text_selectPrevCompletion_void_TextDocumentEditor_impl(self)
proc selectNextCompletion*(self: TextDocumentEditor) =
  editor_text_selectNextCompletion_void_TextDocumentEditor_impl(self)
proc hasTabStops*(self: TextDocumentEditor): bool =
  editor_text_hasTabStops_bool_TextDocumentEditor_impl(self)
proc clearTabStops*(self: TextDocumentEditor) =
  editor_text_clearTabStops_void_TextDocumentEditor_impl(self)
proc selectNextTabStop*(self: TextDocumentEditor) =
  editor_text_selectNextTabStop_void_TextDocumentEditor_impl(self)
proc selectPrevTabStop*(self: TextDocumentEditor) =
  editor_text_selectPrevTabStop_void_TextDocumentEditor_impl(self)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  editor_text_applySelectedCompletion_void_TextDocumentEditor_impl(self)
proc showHoverFor*(self: TextDocumentEditor; cursor: Cursor) =
  ## Shows lsp hover information for the given cursor.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  editor_text_showHoverFor_void_TextDocumentEditor_Cursor_impl(self, cursor)
proc showHoverForCurrent*(self: TextDocumentEditor) =
  ## Shows lsp hover information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  editor_text_showHoverForCurrent_void_TextDocumentEditor_impl(self)
proc hideHover*(self: TextDocumentEditor) =
  ## Hides the hover information.
  editor_text_hideHover_void_TextDocumentEditor_impl(self)
proc cancelDelayedHideHover*(self: TextDocumentEditor) =
  editor_text_cancelDelayedHideHover_void_TextDocumentEditor_impl(self)
proc hideHoverDelayed*(self: TextDocumentEditor) =
  ## Hides the hover information after a delay.
  editor_text_hideHoverDelayed_void_TextDocumentEditor_impl(self)
proc clearDiagnostics*(self: TextDocumentEditor) =
  editor_text_clearDiagnostics_void_TextDocumentEditor_impl(self)
proc updateDiagnosticsForCurrent*(self: TextDocumentEditor) =
  editor_text_updateDiagnosticsForCurrent_void_TextDocumentEditor_impl(self)
proc showDiagnosticsForCurrent*(self: TextDocumentEditor) =
  editor_text_showDiagnosticsForCurrent_void_TextDocumentEditor_impl(self)
proc isRunningSavedCommands*(self: TextDocumentEditor): bool =
  editor_text_isRunningSavedCommands_bool_TextDocumentEditor_impl(self)
proc runSavedCommands*(self: TextDocumentEditor) =
  editor_text_runSavedCommands_void_TextDocumentEditor_impl(self)
proc clearCurrentCommandHistory*(self: TextDocumentEditor;
                                 retainLast: bool = false) =
  editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_impl(self,
      retainLast)
proc saveCurrentCommandHistory*(self: TextDocumentEditor) =
  editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_impl(self)
proc setSelection*(self: TextDocumentEditor; cursor: Cursor; nextMode: string) =
  editor_text_setSelection_void_TextDocumentEditor_Cursor_string_impl(self,
      cursor, nextMode)
proc enterChooseCursorMode*(self: TextDocumentEditor; action: string) =
  editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_impl(self,
      action)
proc recordCurrentCommand*(self: TextDocumentEditor) =
  editor_text_recordCurrentCommand_void_TextDocumentEditor_impl(self)
proc runSingleClickCommand*(self: TextDocumentEditor) =
  editor_text_runSingleClickCommand_void_TextDocumentEditor_impl(self)
proc runDoubleClickCommand*(self: TextDocumentEditor) =
  editor_text_runDoubleClickCommand_void_TextDocumentEditor_impl(self)
proc runTripleClickCommand*(self: TextDocumentEditor) =
  editor_text_runTripleClickCommand_void_TextDocumentEditor_impl(self)
proc runDragCommand*(self: TextDocumentEditor) =
  editor_text_runDragCommand_void_TextDocumentEditor_impl(self)
