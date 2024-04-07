import std/[json, options]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc updateCompletions*(self: SelectorPopup) =
  popup_selector_updateCompletions_void_SelectorPopup_impl(self)
proc getSelectedItem*(self: SelectorPopup): JsonNode =
  popup_selector_getSelectedItem_JsonNode_SelectorPopup_impl(self)
proc accept*(self: SelectorPopup) =
  popup_selector_accept_void_SelectorPopup_impl(self)
proc cancel*(self: SelectorPopup) =
  popup_selector_cancel_void_SelectorPopup_impl(self)
proc prev*(self: SelectorPopup) =
  popup_selector_prev_void_SelectorPopup_impl(self)
proc next*(self: SelectorPopup) =
  popup_selector_next_void_SelectorPopup_impl(self)
