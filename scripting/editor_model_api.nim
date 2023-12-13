import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scrollPixels*(self: ModelDocumentEditor; amount: float32) =
  editor_model_scrollPixels_void_ModelDocumentEditor_float32_impl(self, amount)
proc scrollLines*(self: ModelDocumentEditor; lines: float32) =
  editor_model_scrollLines_void_ModelDocumentEditor_float32_impl(self, lines)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  editor_model_setMode_void_ModelDocumentEditor_string_impl(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  editor_model_mode_string_ModelDocumentEditor_impl(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  editor_model_getContextWithMode_string_ModelDocumentEditor_string_impl(self,
      context)
proc isThickCursor*(self: ModelDocumentEditor): bool =
  editor_model_isThickCursor_bool_ModelDocumentEditor_impl(self)
proc gotoDefinition*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_gotoDefinition_void_ModelDocumentEditor_bool_impl(self, select)
proc gotoPrevNodeOfClass*(self: ModelDocumentEditor; className: string;
                          select: bool = false) =
  editor_model_gotoPrevNodeOfClass_void_ModelDocumentEditor_string_bool_impl(
      self, className, select)
proc gotoNextNodeOfClass*(self: ModelDocumentEditor; className: string;
                          select: bool = false) =
  editor_model_gotoNextNodeOfClass_void_ModelDocumentEditor_string_bool_impl(
      self, className, select)
proc toggleBoolCell*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_toggleBoolCell_void_ModelDocumentEditor_bool_impl(self, select)
proc invertSelection*(self: ModelDocumentEditor) =
  editor_model_invertSelection_void_ModelDocumentEditor_impl(self)
proc selectPrev*(self: ModelDocumentEditor) =
  editor_model_selectPrev_void_ModelDocumentEditor_impl(self)
proc selectNext*(self: ModelDocumentEditor) =
  editor_model_selectNext_void_ModelDocumentEditor_impl(self)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_impl(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorRight_void_ModelDocumentEditor_bool_impl(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_impl(self,
      select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_impl(self,
      select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_impl(self,
      select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_impl(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_impl(
      self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_impl(self,
      select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorUp_void_ModelDocumentEditor_bool_impl(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorDown_void_ModelDocumentEditor_bool_impl(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_impl(self,
      select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_impl(self,
      select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_selectNode_void_ModelDocumentEditor_bool_impl(self, select)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_impl(self,
      select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_impl(self,
      select)
proc deleteLeft*(self: ModelDocumentEditor) =
  editor_model_deleteLeft_void_ModelDocumentEditor_impl(self)
proc deleteRight*(self: ModelDocumentEditor) =
  editor_model_deleteRight_void_ModelDocumentEditor_impl(self)
proc replaceLeft*(self: ModelDocumentEditor) =
  editor_model_replaceLeft_void_ModelDocumentEditor_impl(self)
proc replaceRight*(self: ModelDocumentEditor) =
  editor_model_replaceRight_void_ModelDocumentEditor_impl(self)
proc createNewNode*(self: ModelDocumentEditor) =
  editor_model_createNewNode_void_ModelDocumentEditor_impl(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_impl(self,
      input)
proc undo*(self: ModelDocumentEditor) =
  editor_model_undo_void_ModelDocumentEditor_impl(self)
proc redo*(self: ModelDocumentEditor) =
  editor_model_redo_void_ModelDocumentEditor_impl(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_impl(self)
proc showCompletions*(self: ModelDocumentEditor) =
  editor_model_showCompletions_void_ModelDocumentEditor_impl(self)
proc showCompletionWindow*(self: ModelDocumentEditor) =
  editor_model_showCompletionWindow_void_ModelDocumentEditor_impl(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  editor_model_hideCompletions_void_ModelDocumentEditor_impl(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  editor_model_selectPrevCompletion_void_ModelDocumentEditor_impl(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  editor_model_selectNextCompletion_void_ModelDocumentEditor_impl(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  editor_model_applySelectedCompletion_void_ModelDocumentEditor_impl(self)
proc printSelectionInfo*(self: ModelDocumentEditor) =
  editor_model_printSelectionInfo_void_ModelDocumentEditor_impl(self)
proc clearModelCache*(self: ModelDocumentEditor) =
  editor_model_clearModelCache_void_ModelDocumentEditor_impl(self)
proc runSelectedFunction*(self: ModelDocumentEditor) =
  editor_model_runSelectedFunction_void_ModelDocumentEditor_impl(self)
proc copyNode*(self: ModelDocumentEditor) =
  editor_model_copyNode_void_ModelDocumentEditor_impl(self)
proc pasteNode*(self: ModelDocumentEditor) =
  editor_model_pasteNode_void_ModelDocumentEditor_impl(self)
proc addLanguage*(self: ModelDocumentEditor) =
  editor_model_addLanguage_void_ModelDocumentEditor_impl(self)
proc createNewModel*(self: ModelDocumentEditor; name: string) =
  editor_model_createNewModel_void_ModelDocumentEditor_string_impl(self, name)
proc addModelToProject*(self: ModelDocumentEditor) =
  editor_model_addModelToProject_void_ModelDocumentEditor_impl(self)
proc importModel*(self: ModelDocumentEditor) =
  editor_model_importModel_void_ModelDocumentEditor_impl(self)
proc compileLanguage*(self: ModelDocumentEditor) =
  editor_model_compileLanguage_void_ModelDocumentEditor_impl(self)
proc addRootNode*(self: ModelDocumentEditor) =
  editor_model_addRootNode_void_ModelDocumentEditor_impl(self)
proc saveProject*(self: ModelDocumentEditor) =
  editor_model_saveProject_void_ModelDocumentEditor_impl(self)
proc loadBaseLanguageModel*(self: ModelDocumentEditor) =
  editor_model_loadBaseLanguageModel_void_ModelDocumentEditor_impl(self)
proc findDeclaration*(self: ModelDocumentEditor; global: bool) =
  editor_model_findDeclaration_void_ModelDocumentEditor_bool_impl(self, global)
