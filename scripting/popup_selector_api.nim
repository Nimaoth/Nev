import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8388608558(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8388608657(self)
proc prev*(self: SelectorPopup) =
  prevScript_8388608713(self)
proc next*(self: SelectorPopup) =
  nextScript_8388608781(self)
