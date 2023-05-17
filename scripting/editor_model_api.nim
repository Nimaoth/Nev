import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_6643787428(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_6643787530(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_6643790627(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_6643790676(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_6643790732(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_6643790812(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_6643790892(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_6643790974(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_6643791056(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_6643791139(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_6643791225(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_6643791308(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_6643791391(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_6643791496(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_6643791601(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_6643791703(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_6643791805(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_6643791937(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_6643791993(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_6643792072(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_6643793001(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_6643793044(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_6643793638(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_6643793722(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_6643793894(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_6643794195(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_6643794395(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_6643794438(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_6643794481(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_6643794528(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_6643794579(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_6643794630(self)
