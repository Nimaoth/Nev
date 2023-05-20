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

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  editor_model_scroll_void_ModelDocumentEditor_float32_impl(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  editor_model_setMode_void_ModelDocumentEditor_string_impl(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  editor_model_mode_string_ModelDocumentEditor_impl(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  editor_model_getContextWithMode_string_ModelDocumentEditor_string_impl(self,
      context)
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
proc selectParentCell*(self: ModelDocumentEditor) =
  editor_model_selectParentCell_void_ModelDocumentEditor_impl(self)
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
proc hideCompletions*(self: ModelDocumentEditor) =
  editor_model_hideCompletions_void_ModelDocumentEditor_impl(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  editor_model_selectPrevCompletion_void_ModelDocumentEditor_impl(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  editor_model_selectNextCompletion_void_ModelDocumentEditor_impl(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  editor_model_applySelectedCompletion_void_ModelDocumentEditor_impl(self)
