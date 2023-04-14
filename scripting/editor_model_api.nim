import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8422173425(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8422173534(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8422174006(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8422174062(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor) =
  moveCursorLeftScript_8422174125(self)
proc moveCursorRight*(self: ModelDocumentEditor) =
  moveCursorRightScript_8422174205(self)
proc moveCursorUp*(self: ModelDocumentEditor) =
  moveCursorUpScript2_8422174285(self)
proc moveCursorDown*(self: ModelDocumentEditor) =
  moveCursorDownScript2_8422174365(self)
proc moveCursorLeftCell*(self: ModelDocumentEditor) =
  moveCursorLeftCellScript_8422174445(self)
proc moveCursorRightCell*(self: ModelDocumentEditor) =
  moveCursorRightCellScript_8422174525(self)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8422174605(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8422174694(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8422174783(self, input)
