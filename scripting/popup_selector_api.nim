import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8942256769(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8942256864(self)
proc prev*(self: SelectorPopup) =
  prevScript_8942256913(self)
proc next*(self: SelectorPopup) =
  nextScript_8942256974(self)
