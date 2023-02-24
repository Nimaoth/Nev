import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8204058912(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8204059011(self)
proc prev*(self: SelectorPopup) =
  prevScript_8204059067(self)
proc next*(self: SelectorPopup) =
  nextScript_8204059135(self)
