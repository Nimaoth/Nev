import std/[json, options]
import "../src/scripting_api"
import plugin_api_internal

## This file is auto generated, don't modify.

proc getSelectedItemJson*(self: SelectorPopup): JsonNode =
  popup_selector_getSelectedItemJson_JsonNode_SelectorPopup_impl(self)
proc accept*(self: SelectorPopup) =
  popup_selector_accept_void_SelectorPopup_impl(self)
proc cancel*(self: SelectorPopup) =
  popup_selector_cancel_void_SelectorPopup_impl(self)
proc prev*(self: SelectorPopup; count: int = 1) =
  popup_selector_prev_void_SelectorPopup_int_impl(self, count)
proc next*(self: SelectorPopup; count: int = 1) =
  popup_selector_next_void_SelectorPopup_int_impl(self, count)
proc toggleFocusPreview*(self: SelectorPopup) =
  popup_selector_toggleFocusPreview_void_SelectorPopup_impl(self)
proc setFocusPreview*(self: SelectorPopup; focus: bool) =
  popup_selector_setFocusPreview_void_SelectorPopup_bool_impl(self, focus)
