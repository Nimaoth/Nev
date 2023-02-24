import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8371831227(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8371831326(self)
proc prev*(self: SelectorPopup) =
  prevScript_8371831382(self)
proc next*(self: SelectorPopup) =
  nextScript_8371831450(self)
