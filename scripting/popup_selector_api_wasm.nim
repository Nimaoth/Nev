import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc popup_selector_accept_void_SelectorPopup_wasm(arg_8925479560: cstring): cstring {.
    importc.}
proc accept*(self: SelectorPopup) =
  var argsJson_8925479555 = newJArray()
  argsJson_8925479555.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479555
  let res_8925479556 {.used.} = popup_selector_accept_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_cancel_void_SelectorPopup_wasm(arg_8925479672: cstring): cstring {.
    importc.}
proc cancel*(self: SelectorPopup) =
  var argsJson_8925479667 = newJArray()
  argsJson_8925479667.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479667
  let res_8925479668 {.used.} = popup_selector_cancel_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_prev_void_SelectorPopup_wasm(arg_8925479734: cstring): cstring {.
    importc.}
proc prev*(self: SelectorPopup) =
  var argsJson_8925479729 = newJArray()
  argsJson_8925479729.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479729
  let res_8925479730 {.used.} = popup_selector_prev_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_next_void_SelectorPopup_wasm(arg_8925479808: cstring): cstring {.
    importc.}
proc next*(self: SelectorPopup) =
  var argsJson_8925479803 = newJArray()
  argsJson_8925479803.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8925479803
  let res_8925479804 {.used.} = popup_selector_next_void_SelectorPopup_wasm(
      argsJsonString.cstring)

