import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc popup_selector_accept_void_SelectorPopup_wasm(arg_8925479559: cstring): cstring {.
    importc.}
proc accept*(self: SelectorPopup) =
  var argsJson_8925479554 = newJArray()
  argsJson_8925479554.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479554
  let res_8925479555 {.used.} = popup_selector_accept_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_cancel_void_SelectorPopup_wasm(arg_8925479670: cstring): cstring {.
    importc.}
proc cancel*(self: SelectorPopup) =
  var argsJson_8925479665 = newJArray()
  argsJson_8925479665.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479665
  let res_8925479666 {.used.} = popup_selector_cancel_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_prev_void_SelectorPopup_wasm(arg_8925479731: cstring): cstring {.
    importc.}
proc prev*(self: SelectorPopup) =
  var argsJson_8925479726 = newJArray()
  argsJson_8925479726.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479726
  let res_8925479727 {.used.} = popup_selector_prev_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_next_void_SelectorPopup_wasm(arg_8925479804: cstring): cstring {.
    importc.}
proc next*(self: SelectorPopup) =
  var argsJson_8925479799 = newJArray()
  argsJson_8925479799.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479799
  let res_8925479800 {.used.} = popup_selector_next_void_SelectorPopup_wasm(
      argsJsonString.cstring)

