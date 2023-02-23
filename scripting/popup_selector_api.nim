import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8170504455(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8170504554(self)
proc prev*(self: SelectorPopup) =
  prevScript_8170504610(self)
proc next*(self: SelectorPopup) =
  nextScript_8170504678(self)
