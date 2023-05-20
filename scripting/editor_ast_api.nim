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

proc moveCursor*(self: AstDocumentEditor; direction: int) =
  editor_ast_moveCursor_void_AstDocumentEditor_int_impl(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  editor_ast_moveCursorUp_void_AstDocumentEditor_impl(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  editor_ast_moveCursorDown_void_AstDocumentEditor_impl(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  editor_ast_moveCursorNext_void_AstDocumentEditor_impl(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  editor_ast_moveCursorPrev_void_AstDocumentEditor_impl(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  editor_ast_moveCursorNextLine_void_AstDocumentEditor_impl(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  editor_ast_moveCursorPrevLine_void_AstDocumentEditor_impl(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  editor_ast_selectContaining_void_AstDocumentEditor_string_impl(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  editor_ast_deleteSelected_void_AstDocumentEditor_impl(self)
proc copySelected*(self: AstDocumentEditor) =
  editor_ast_copySelected_void_AstDocumentEditor_impl(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  editor_ast_finishEdit_void_AstDocumentEditor_bool_impl(self, apply)
proc undo*(self: AstDocumentEditor) =
  editor_ast_undo_void_AstDocumentEditor_impl(self)
proc redo*(self: AstDocumentEditor) =
  editor_ast_redo_void_AstDocumentEditor_impl(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_insertAfterSmart_void_AstDocumentEditor_string_impl(self,
      nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_insertAfter_void_AstDocumentEditor_string_impl(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_insertBefore_void_AstDocumentEditor_string_impl(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_insertChild_void_AstDocumentEditor_string_impl(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_replace_void_AstDocumentEditor_string_impl(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_replaceEmpty_void_AstDocumentEditor_string_impl(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  editor_ast_replaceParent_void_AstDocumentEditor_impl(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  editor_ast_wrap_void_AstDocumentEditor_string_impl(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editor_ast_editPrevEmpty_void_AstDocumentEditor_impl(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editor_ast_editNextEmpty_void_AstDocumentEditor_impl(self)
proc rename*(self: AstDocumentEditor) =
  editor_ast_rename_void_AstDocumentEditor_impl(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  editor_ast_selectPrevCompletion_void_AstDocumentEditor_impl(self)
proc selectNextCompletion*(self: AstDocumentEditor) =
  editor_ast_selectNextCompletion_void_AstDocumentEditor_impl(self)
proc applySelectedCompletion*(self: AstDocumentEditor) =
  editor_ast_applySelectedCompletion_void_AstDocumentEditor_impl(self)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_impl(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_impl(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  editor_ast_cancelAndDelete_void_AstDocumentEditor_impl(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_impl(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_impl(self)
proc selectPrev*(self: AstDocumentEditor) =
  editor_ast_selectPrev_void_AstDocumentEditor_impl(self)
proc selectNext*(self: AstDocumentEditor) =
  editor_ast_selectNext_void_AstDocumentEditor_impl(self)
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_impl(self)
proc goto*(self: AstDocumentEditor; where: string) =
  editor_ast_goto_void_AstDocumentEditor_string_impl(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  editor_ast_runSelectedFunction_void_AstDocumentEditor_impl(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  editor_ast_toggleOption_void_AstDocumentEditor_string_impl(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  editor_ast_runLastCommand_void_AstDocumentEditor_string_impl(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  editor_ast_selectCenterNode_void_AstDocumentEditor_impl(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  editor_ast_scroll_void_AstDocumentEditor_float32_impl(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  editor_ast_scrollOutput_void_AstDocumentEditor_string_impl(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  editor_ast_dumpContext_void_AstDocumentEditor_impl(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  editor_ast_setMode_void_AstDocumentEditor_string_impl(self, mode)
proc mode*(self: AstDocumentEditor): string =
  editor_ast_mode_string_AstDocumentEditor_impl(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  editor_ast_getContextWithMode_string_AstDocumentEditor_string_impl(self,
      context)
