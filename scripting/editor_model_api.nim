import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8422173551(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8422173660(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8422174132(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8422174188(self, context)
proc moveCursorLeft*(self: ModelDocumentEditor) =
  moveCursorLeftScript_8422174251(self)
proc moveCursorRight*(self: ModelDocumentEditor) =
  moveCursorRightScript_8422174331(self)
proc moveCursorUp*(self: ModelDocumentEditor) =
  moveCursorUpScript2_8422174411(self)
proc moveCursorDown*(self: ModelDocumentEditor) =
  moveCursorDownScript2_8422174491(self)
proc moveCursorLeftCell*(self: ModelDocumentEditor) =
  moveCursorLeftCellScript_8422174571(self)
proc moveCursorRightCell*(self: ModelDocumentEditor) =
  moveCursorRightCellScript_8422174651(self)
proc deleteLeft*(self: ModelDocumentEditor) =
  deleteLeftScript2_8422174731(self)
proc deleteRight*(self: ModelDocumentEditor) =
  deleteRightScript2_8422174820(self)
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  insertTextAtCursorScript_8422174909(self, input)
