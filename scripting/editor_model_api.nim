import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_9009376562(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_9009376664(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_9009379897(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_9009379946(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_9009380002(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_9009380082(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_9009380162(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_9009380244(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_9009380326(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_9009380409(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_9009380495(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_9009380578(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_9009380661(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_9009380766(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_9009380871(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_9009380973(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_9009381075(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_9009381207(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_9009381263(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_9009381342(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_9009382275(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_9009382318(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_9009382912(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_9009382996(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_9009383168(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_9009383533(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_9009383773(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_9009383816(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_9009383859(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_9009383906(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_9009383957(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_9009384008(self)
