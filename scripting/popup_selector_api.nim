import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc accept*(self: SelectorPopup) =
  acceptScript_8925479553(self)
proc cancel*(self: SelectorPopup) =
  cancelScript_8925479665(self)
proc prev*(self: SelectorPopup) =
  prevScript_8925479727(self)
proc next*(self: SelectorPopup) =
  nextScript_8925479801(self)
