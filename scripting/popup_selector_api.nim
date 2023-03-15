import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8355054209(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8355054311(self)
proc prev*(self: SelectorPopup) =
  prevScript_8355054367(self)
proc next*(self: SelectorPopup) =
  nextScript_8355054435(self)
