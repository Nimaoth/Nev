import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc editor_text_setMode_void_TextDocumentEditor_string_impl(
    self: TextDocumentEditor; mode: string)  {.importc.}
proc editor_text_mode_string_TextDocumentEditor_impl(self: TextDocumentEditor): string  {.importc.}
proc editor_text_getContextWithMode_string_TextDocumentEditor_string_impl(
    self: TextDocumentEditor; context: string): string  {.importc.}
proc editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_impl(
    self: TextDocumentEditor; cursor: SelectionCursor)  {.importc.}
proc editor_text_invertSelection_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_impl(
    self: TextDocumentEditor; selections: seq[Selection]; text: string;
    notify: bool = true; record: bool = true): seq[Selection]  {.importc.}
proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_impl(
    self: TextDocumentEditor; selections: seq[Selection]; notify: bool = true;
    record: bool = true): seq[Selection]  {.importc.}
proc editor_text_selectPrev_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_selectNext_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_selectInside_void_TextDocumentEditor_Cursor_impl(
    self: TextDocumentEditor; cursor: Cursor)  {.importc.}
proc editor_text_selectInsideCurrent_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_selectLine_void_TextDocumentEditor_int_impl(
    self: TextDocumentEditor; line: int)  {.importc.}
proc editor_text_selectLineCurrent_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_selectParentTs_void_TextDocumentEditor_Selection_impl(
    self: TextDocumentEditor; selection: Selection)  {.importc.}
proc editor_text_selectParentCurrentTs_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_insertText_void_TextDocumentEditor_string_impl(
    self: TextDocumentEditor; text: string)  {.importc.}
proc editor_text_indent_void_TextDocumentEditor_impl(self: TextDocumentEditor)  {.importc.}
proc editor_text_unindent_void_TextDocumentEditor_impl(self: TextDocumentEditor)  {.importc.}
proc editor_text_undo_void_TextDocumentEditor_impl(self: TextDocumentEditor)  {.importc.}
proc editor_text_redo_void_TextDocumentEditor_impl(self: TextDocumentEditor)  {.importc.}
proc editor_text_copy_void_TextDocumentEditor_impl(self: TextDocumentEditor)  {.importc.}
proc editor_text_paste_void_TextDocumentEditor_impl(self: TextDocumentEditor)  {.importc.}
proc editor_text_scrollText_void_TextDocumentEditor_float32_impl(
    self: TextDocumentEditor; amount: float32)  {.importc.}
proc editor_text_duplicateLastSelection_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_addCursorBelow_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_addCursorAbove_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_impl(
    self: TextDocumentEditor; cursor: Cursor; offset: int = 0): Selection  {.importc.}
proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_impl(
    self: TextDocumentEditor; cursor: Cursor; offset: int = 0): Selection  {.importc.}
proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_setAllFindResultToSelection_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_clearSelections_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_impl(
    self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_impl(
    self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_impl(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true)  {.importc.}
proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_impl(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true)  {.importc.}
proc editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_impl(
    self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_impl(
    self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_impl(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true)  {.importc.}
proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_impl(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
    all: bool = true)  {.importc.}
proc editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_impl(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config)  {.importc.}
proc editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_impl(
    self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config)  {.importc.}
proc editor_text_reloadTreesitter_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_deleteLeft_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_deleteRight_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_getCommandCount_int_TextDocumentEditor_impl(
    self: TextDocumentEditor): int  {.importc.}
proc editor_text_setCommandCount_void_TextDocumentEditor_int_impl(
    self: TextDocumentEditor; count: int)  {.importc.}
proc editor_text_setCommandCountRestore_void_TextDocumentEditor_int_impl(
    self: TextDocumentEditor; count: int)  {.importc.}
proc editor_text_updateCommandCount_void_TextDocumentEditor_int_impl(
    self: TextDocumentEditor; digit: int)  {.importc.}
proc editor_text_setFlag_void_TextDocumentEditor_string_bool_impl(
    self: TextDocumentEditor; name: string; value: bool)  {.importc.}
proc editor_text_getFlag_bool_TextDocumentEditor_string_impl(
    self: TextDocumentEditor; name: string): bool  {.importc.}
proc editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_impl(
    self: TextDocumentEditor; action: string; args: JsonNode): bool  {.importc.}
proc editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_impl(
    self: TextDocumentEditor; cursor: Cursor): Selection  {.importc.}
proc editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_impl(
    self: TextDocumentEditor; cursor: Cursor; delimiter: char): Selection  {.importc.}
proc editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_impl(
    self: TextDocumentEditor; cursor: Cursor; open: char; close: char): Selection  {.importc.}
proc editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_impl(
    self: TextDocumentEditor; cursor: Cursor; move: string; count: int = 0): Selection  {.importc.}
proc editor_text_applyMove_void_TextDocumentEditor_JsonNode_impl(
    self: TextDocumentEditor; args: JsonNode)  {.importc.}
proc editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_impl(
    self: TextDocumentEditor; move: string; inside: bool = false;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_impl(
    self: TextDocumentEditor; move: string;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true;
    count: int = 0)  {.importc.}
proc editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_impl(
    self: TextDocumentEditor; move: string;
    which: SelectionCursor = SelectionCursor.Config; all: bool = true;
    count: int = 0)  {.importc.}
proc editor_text_setSearchQuery_void_TextDocumentEditor_string_impl(
    self: TextDocumentEditor; query: string)  {.importc.}
proc editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_impl(
    self: TextDocumentEditor; move: string; count: int = 0)  {.importc.}
proc editor_text_toggleLineComment_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_gotoDefinition_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_getCompletions_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_gotoSymbol_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_hideCompletions_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_selectPrevCompletion_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_selectNextCompletion_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_applySelectedCompletion_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_isRunningSavedCommands_bool_TextDocumentEditor_impl(
    self: TextDocumentEditor): bool  {.importc.}
proc editor_text_runSavedCommands_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_impl(
    self: TextDocumentEditor; retainLast: bool = false)  {.importc.}
proc editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_impl(
    self: TextDocumentEditor)  {.importc.}
proc editor_text_setSelection_void_TextDocumentEditor_Cursor_string_impl(
    self: TextDocumentEditor; cursor: Cursor; nextMode: string)  {.importc.}
proc editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_impl(
    self: TextDocumentEditor; action: string)  {.importc.}
proc popup_selector_accept_void_SelectorPopup_impl(self: SelectorPopup)  {.importc.}
proc popup_selector_cancel_void_SelectorPopup_impl(self: SelectorPopup)  {.importc.}
proc popup_selector_prev_void_SelectorPopup_impl(self: SelectorPopup)  {.importc.}
proc popup_selector_next_void_SelectorPopup_impl(self: SelectorPopup)  {.importc.}
proc editor_ast_moveCursor_void_AstDocumentEditor_int_impl(
    self: AstDocumentEditor; direction: int)  {.importc.}
proc editor_ast_moveCursorUp_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveCursorDown_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveCursorNext_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveCursorPrev_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveCursorNextLine_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveCursorPrevLine_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_selectContaining_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; container: string)  {.importc.}
proc editor_ast_deleteSelected_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_copySelected_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_finishEdit_void_AstDocumentEditor_bool_impl(
    self: AstDocumentEditor; apply: bool)  {.importc.}
proc editor_ast_undo_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_redo_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_insertAfterSmart_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editor_ast_insertAfter_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editor_ast_insertBefore_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editor_ast_insertChild_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editor_ast_replace_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editor_ast_replaceEmpty_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editor_ast_replaceParent_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_wrap_void_AstDocumentEditor_string_impl(self: AstDocumentEditor;
    nodeTemplate: string)  {.importc.}
proc editor_ast_editPrevEmpty_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_editNextEmpty_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_rename_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_selectPrevCompletion_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_selectNextCompletion_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_applySelectedCompletion_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_cancelAndDelete_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_selectPrev_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_selectNext_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_goto_void_AstDocumentEditor_string_impl(self: AstDocumentEditor;
    where: string)  {.importc.}
proc editor_ast_runSelectedFunction_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_toggleOption_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; name: string)  {.importc.}
proc editor_ast_runLastCommand_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; which: string)  {.importc.}
proc editor_ast_selectCenterNode_void_AstDocumentEditor_impl(
    self: AstDocumentEditor)  {.importc.}
proc editor_ast_scroll_void_AstDocumentEditor_float32_impl(
    self: AstDocumentEditor; amount: float32)  {.importc.}
proc editor_ast_scrollOutput_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; arg: string)  {.importc.}
proc editor_ast_dumpContext_void_AstDocumentEditor_impl(self: AstDocumentEditor)  {.importc.}
proc editor_ast_setMode_void_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; mode: string)  {.importc.}
proc editor_ast_mode_string_AstDocumentEditor_impl(self: AstDocumentEditor): string  {.importc.}
proc editor_ast_getContextWithMode_string_AstDocumentEditor_string_impl(
    self: AstDocumentEditor; context: string): string  {.importc.}
proc editor_model_scroll_void_ModelDocumentEditor_float32_impl(
    self: ModelDocumentEditor; amount: float32)  {.importc.}
proc editor_model_setMode_void_ModelDocumentEditor_string_impl(
    self: ModelDocumentEditor; mode: string)  {.importc.}
proc editor_model_mode_string_ModelDocumentEditor_impl(self: ModelDocumentEditor): string  {.importc.}
proc editor_model_getContextWithMode_string_ModelDocumentEditor_string_impl(
    self: ModelDocumentEditor; context: string): string  {.importc.}
proc editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorRight_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorUp_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorDown_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_selectNode_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_selectParentCell_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_impl(
    self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc editor_model_deleteLeft_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_deleteRight_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_createNewNode_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_impl(
    self: ModelDocumentEditor; input: string): bool  {.importc.}
proc editor_model_undo_void_ModelDocumentEditor_impl(self: ModelDocumentEditor)  {.importc.}
proc editor_model_redo_void_ModelDocumentEditor_impl(self: ModelDocumentEditor)  {.importc.}
proc editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_showCompletions_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_hideCompletions_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_selectPrevCompletion_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_selectNextCompletion_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_applySelectedCompletion_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_model_runSelectedFunction_void_ModelDocumentEditor_impl(
    self: ModelDocumentEditor)  {.importc.}
proc editor_getBackend_Backend_App_impl(): Backend  {.importc.}
proc editor_saveAppState_void_App_impl()  {.importc.}
proc editor_requestRender_void_App_bool_impl(redrawEverything: bool = false)  {.importc.}
proc editor_setHandleInputs_void_App_string_bool_impl(context: string;
    value: bool)  {.importc.}
proc editor_setHandleActions_void_App_string_bool_impl(context: string;
    value: bool)  {.importc.}
proc editor_setConsumeAllActions_void_App_string_bool_impl(context: string;
    value: bool)  {.importc.}
proc editor_setConsumeAllInput_void_App_string_bool_impl(context: string;
    value: bool)  {.importc.}
proc editor_clearWorkspaceCaches_void_App_impl()  {.importc.}
proc editor_openGithubWorkspace_void_App_string_string_string_impl(user: string;
    repository: string; branchOrHash: string)  {.importc.}
proc editor_openAbsytreeServerWorkspace_void_App_string_impl(url: string)  {.importc.}
proc editor_openLocalWorkspace_void_App_string_impl(path: string)  {.importc.}
proc editor_getFlag_bool_App_string_bool_impl(flag: string;
    default: bool = false): bool  {.importc.}
proc editor_setFlag_void_App_string_bool_impl(flag: string; value: bool)  {.importc.}
proc editor_toggleFlag_void_App_string_impl(flag: string)  {.importc.}
proc editor_setOption_void_App_string_JsonNode_impl(option: string;
    value: JsonNode)  {.importc.}
proc editor_quit_void_App_impl()  {.importc.}
proc editor_changeFontSize_void_App_float32_impl(amount: float32)  {.importc.}
proc editor_changeLayoutProp_void_App_string_float32_impl(prop: string;
    change: float32)  {.importc.}
proc editor_toggleStatusBarLocation_void_App_impl()  {.importc.}
proc editor_createAndAddView_void_App_impl()  {.importc.}
proc editor_closeCurrentView_void_App_impl()  {.importc.}
proc editor_moveCurrentViewToTop_void_App_impl()  {.importc.}
proc editor_nextView_void_App_impl()  {.importc.}
proc editor_prevView_void_App_impl()  {.importc.}
proc editor_moveCurrentViewPrev_void_App_impl()  {.importc.}
proc editor_moveCurrentViewNext_void_App_impl()  {.importc.}
proc editor_setLayout_void_App_string_impl(layout: string)  {.importc.}
proc editor_commandLine_void_App_string_impl(initialValue: string = "")  {.importc.}
proc editor_exitCommandLine_void_App_impl()  {.importc.}
proc editor_executeCommandLine_bool_App_impl(): bool  {.importc.}
proc editor_writeFile_void_App_string_bool_impl(path: string = "";
    app: bool = false)  {.importc.}
proc editor_loadFile_void_App_string_impl(path: string = "")  {.importc.}
proc editor_removeFromLocalStorage_void_App_impl()  {.importc.}
proc editor_loadTheme_void_App_string_impl(name: string)  {.importc.}
proc editor_chooseTheme_void_App_impl()  {.importc.}
proc editor_chooseFile_void_App_string_impl(view: string = "new")  {.importc.}
proc editor_chooseOpen_void_App_string_impl(view: string = "new")  {.importc.}
proc editor_openPreviousEditor_void_App_impl()  {.importc.}
proc editor_openNextEditor_void_App_impl()  {.importc.}
proc editor_setGithubAccessToken_void_App_string_impl(token: string)  {.importc.}
proc editor_reloadConfig_void_App_impl()  {.importc.}
proc editor_logOptions_void_App_impl()  {.importc.}
proc editor_clearCommands_void_App_string_impl(context: string)  {.importc.}
proc editor_getAllEditors_seq_EditorId_App_impl(): seq[EditorId]  {.importc.}
proc editor_setMode_void_App_string_impl(mode: string)  {.importc.}
proc editor_mode_string_App_impl(): string  {.importc.}
proc editor_getContextWithMode_string_App_string_impl(context: string): string  {.importc.}
proc editor_scriptRunAction_void_string_string_impl(action: string; arg: string)  {.importc.}
proc editor_scriptLog_void_string_impl(message: string)  {.importc.}
proc editor_addCommandScript_void_App_string_string_string_string_impl(
    context: string; keys: string; action: string; arg: string = "")  {.importc.}
proc editor_removeCommand_void_App_string_string_impl(context: string;
    keys: string)  {.importc.}
proc editor_getActivePopup_EditorId_impl(): EditorId  {.importc.}
proc editor_getActiveEditor_EditorId_impl(): EditorId  {.importc.}
proc editor_getActiveEditor2_EditorId_App_impl(): EditorId  {.importc.}
proc editor_loadCurrentConfig_void_App_impl()  {.importc.}
proc editor_sourceCurrentDocument_void_App_impl()  {.importc.}
proc editor_getEditor_EditorId_int_impl(index: int): EditorId  {.importc.}
proc editor_scriptIsTextEditor_bool_EditorId_impl(editorId: EditorId): bool  {.importc.}
proc editor_scriptIsAstEditor_bool_EditorId_impl(editorId: EditorId): bool  {.importc.}
proc editor_scriptIsModelEditor_bool_EditorId_impl(editorId: EditorId): bool  {.importc.}
proc editor_scriptRunActionFor_void_EditorId_string_string_impl(
    editorId: EditorId; action: string; arg: string)  {.importc.}
proc editor_scriptInsertTextInto_void_EditorId_string_impl(editorId: EditorId;
    text: string)  {.importc.}
proc editor_scriptTextEditorSelection_Selection_EditorId_impl(editorId: EditorId): Selection  {.importc.}
proc editor_scriptSetTextEditorSelection_void_EditorId_Selection_impl(
    editorId: EditorId; selection: Selection)  {.importc.}
proc editor_scriptTextEditorSelections_seq_Selection_EditorId_impl(
    editorId: EditorId): seq[Selection]  {.importc.}
proc editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_impl(
    editorId: EditorId; selections: seq[Selection])  {.importc.}
proc editor_scriptGetTextEditorLine_string_EditorId_int_impl(editorId: EditorId;
    line: int): string  {.importc.}
proc editor_scriptGetTextEditorLineCount_int_EditorId_impl(editorId: EditorId): int  {.importc.}
proc editor_scriptGetOptionInt_int_string_int_impl(path: string; default: int): int  {.importc.}
proc editor_scriptGetOptionFloat_float_string_float_impl(path: string;
    default: float): float  {.importc.}
proc editor_scriptGetOptionBool_bool_string_bool_impl(path: string;
    default: bool): bool  {.importc.}
proc editor_scriptGetOptionString_string_string_string_impl(path: string;
    default: string): string  {.importc.}
proc editor_scriptSetOptionInt_void_string_int_impl(path: string; value: int)  {.importc.}
proc editor_scriptSetOptionFloat_void_string_float_impl(path: string;
    value: float)  {.importc.}
proc editor_scriptSetOptionBool_void_string_bool_impl(path: string; value: bool)  {.importc.}
proc editor_scriptSetOptionString_void_string_string_impl(path: string;
    value: string)  {.importc.}
proc editor_scriptSetCallback_void_string_int_impl(path: string; id: int)  {.importc.}
proc editor_setRegisterText_void_App_string_string_impl(text: string;
    register: string = "")  {.importc.}
