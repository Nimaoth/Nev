import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_6593446558(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_6593446653(self)
proc prev*(self: SelectorPopup) =
  prevScript_6593446702(self)
proc next*(self: SelectorPopup) =
  nextScript_6593446763(self)
