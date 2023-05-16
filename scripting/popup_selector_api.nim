import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8925479553(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8925479648(self)
proc prev*(self: SelectorPopup) =
  prevScript_8925479697(self)
proc next*(self: SelectorPopup) =
  nextScript_8925479758(self)
