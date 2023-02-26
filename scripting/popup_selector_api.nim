import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8371831342(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8371831441(self)
proc prev*(self: SelectorPopup) =
  prevScript_8371831497(self)
proc next*(self: SelectorPopup) =
  nextScript_8371831565(self)
