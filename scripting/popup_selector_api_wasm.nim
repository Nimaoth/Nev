import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc popup_selector_accept_void_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc accept*(self: SelectorPopup) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_accept_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_cancel_void_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc cancel*(self: SelectorPopup) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_cancel_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_prev_void_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc prev*(self: SelectorPopup) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_prev_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_next_void_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc next*(self: SelectorPopup) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_next_void_SelectorPopup_wasm(
      argsJsonString.cstring)

