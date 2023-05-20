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
  scrollScript2_8992600587(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8992600703(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8992603840(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8992603902(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_8992603972(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_8992604077(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_8992604171(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_8992604276(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_8992604382(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_8992604479(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_8992604579(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_8992604677(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_8992604775(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_8992604899(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_8992605018(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_8992605134(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_8992605250(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_8992605396(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_8992605465(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_8992605558(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8992606501(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8992606637(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_8992607244(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8992607379(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_8992607565(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_8992607906(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_8992608123(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_8992608179(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_8992608235(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_8992608295(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_8992608359(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_8992608423(self)
