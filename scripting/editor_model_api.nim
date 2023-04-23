import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8422175722(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8422175831(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8422177211(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8422177267(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftScript_8422177330(self, select)
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightScript_8422177417(self, select)
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftLineScript_8422177504(self, select)
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightLineScript_8422177593(self, select)
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartScript_8422177682(self, select)
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndScript_8422177772(self, select)
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineStartInlineScript_8422177865(self, select)
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLineEndInlineScript_8422177955(self, select)
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorUpScript2_8422178045(self, select)
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorDownScript2_8422178157(self, select)
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorLeftCellScript_8422178269(self, select)
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  moveCursorRightCellScript_8422178356(self, select)
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  selectNodeScript_8422178443(self, select)
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectPrevPlaceholderScript_8422178582(self, select)
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  selectNextPlaceholderScript_8422178650(self, select)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8422178717(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8422178837(self)
proc createNewNode*(self: ModelDocumentEditor) =
  createNewNodeScript_8422179291(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8422179525(self, input)
proc undo*(self: ModelDocumentEditor) =
  undoScript22_8422179615(self)
proc redo*(self: ModelDocumentEditor) =
  redoScript22_8422179665(self)
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  toggleUseDefaultCellBuilderScript_8422179715(self)
