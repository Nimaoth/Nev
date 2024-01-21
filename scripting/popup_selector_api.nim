import std/[json, options]
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
  popup_selector_accept_void_SelectorPopup_impl(self)
proc cancel*(self: SelectorPopup) =
  popup_selector_cancel_void_SelectorPopup_impl(self)
proc prev*(self: SelectorPopup) =
  popup_selector_prev_void_SelectorPopup_impl(self)
proc next*(self: SelectorPopup) =
  popup_selector_next_void_SelectorPopup_impl(self)
