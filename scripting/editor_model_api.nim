import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc scroll*(self: ModelDocumentEditor; amount: float32) =
  scrollScript2_8422163476(self, amount)
proc setMode*(self: ModelDocumentEditor; mode: string) =
  setModeScript22_8422163585(self, mode)
proc mode*(self: ModelDocumentEditor): string =
  modeScript22_8422163674(self)
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  getContextWithModeScript22_8422163730(self, context)
