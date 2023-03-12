import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8405385776(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8405385875(self)
proc prev*(self: SelectorPopup) =
  prevScript_8405385931(self)
proc next*(self: SelectorPopup) =
  nextScript_8405385999(self)
