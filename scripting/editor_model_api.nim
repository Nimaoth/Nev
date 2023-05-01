import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8422176225(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8422176327(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8422179287(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8422179336(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_8422179392(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_8422179472(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_8422179552(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_8422179634(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_8422179716(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_8422179799(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_8422179885(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_8422179968(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_8422180051(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_8422180156(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_8422180261(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_8422180363(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_8422180465(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_8422180597(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_8422180653(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_8422180732(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8422181669(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8422181712(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_8422182090(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8422182376(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_8422182548(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_8422182636(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_8422182705(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_8422182748(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_8422182791(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_8422182838(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_8422182889(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_8422182940(self)
