import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8422176159(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8422176261(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8422177928(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8422177977(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_8422178033(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_8422178113(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_8422178193(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_8422178275(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_8422178357(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_8422178440(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_8422178526(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_8422178609(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_8422178692(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_8422178797(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_8422178902(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_8422178982(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_8422179062(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_8422179194(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_8422179250(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_8422179304(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8422179358(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8422179502(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_8422179980(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8422180207(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_8422180297(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_8422180385(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_8422180454(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_8422180497(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_8422180540(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_8422180587(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_8422180638(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_8422180689(self)
