import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8992600587(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8992600689(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8992603786(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8992603835(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_8992603891(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_8992603971(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_8992604051(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_8992604133(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_8992604215(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_8992604298(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_8992604384(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_8992604467(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_8992604550(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_8992604655(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_8992604760(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_8992604862(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_8992604964(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_8992605096(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_8992605152(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_8992605231(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8992606160(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8992606203(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_8992606797(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8992606881(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_8992607053(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_8992607354(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_8992607554(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_8992607597(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_8992607640(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_8992607687(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_8992607738(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_8992607789(self)
