import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8992597668(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8992597770(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8992600867(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8992600916(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_8992600972(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_8992601052(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_8992601132(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_8992601214(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_8992601296(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_8992601379(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_8992601465(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_8992601548(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_8992601631(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_8992601736(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_8992601841(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_8992601943(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_8992602045(self, select)
proc selectParentCell*(self: ModelDocumentEditor) =
  selectParentCellScript_8992602177(self)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_8992602233(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_8992602312(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8992603241(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8992603284(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_8992603878(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8992603962(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_8992604134(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_8992604435(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_8992604635(self)
proc showCompletions*(self: ModelDocumentEditor) =
  showCompletionsScript_8992604678(self)
proc hideCompletions*(self: ModelDocumentEditor) =
  hideCompletionsScript2_8992604721(self)
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  selectPrevCompletionScript22_8992604768(self)
proc selectNextCompletion*(self: ModelDocumentEditor) =
  selectNextCompletionScript22_8992604819(self)
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  applySelectedCompletionScript22_8992604870(self)
