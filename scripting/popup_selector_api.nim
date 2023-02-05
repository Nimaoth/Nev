import std/[json]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript(self)
proc cancel*(self: SelectorPopup) =
  cancelScript(self)
proc prev*(self: SelectorPopup) =
  prevScript(self)
proc next*(self: SelectorPopup) =
  nextScript(self)
