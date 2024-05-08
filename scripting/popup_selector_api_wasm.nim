import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc popup_selector_getSelectedItemJson_JsonNode_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc getSelectedItemJson*(self: SelectorPopup): JsonNode =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_getSelectedItemJson_JsonNode_SelectorPopup_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


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


proc popup_selector_toggleFocusPreview_void_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc toggleFocusPreview*(self: SelectorPopup) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_toggleFocusPreview_void_SelectorPopup_wasm(
      argsJsonString.cstring)


proc popup_selector_setFocusPreview_void_SelectorPopup_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setFocusPreview*(self: SelectorPopup; focus: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      focus
    else:
      focus.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_setFocusPreview_void_SelectorPopup_bool_wasm(
      argsJsonString.cstring)

