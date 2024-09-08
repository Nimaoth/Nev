import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc popup_selector_setPreviewVisible_void_SelectorPopup_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setPreviewVisible*(self: SelectorPopup; visible: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      visible
    else:
      visible.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_setPreviewVisible_void_SelectorPopup_bool_wasm(
      argsJsonString.cstring)


proc popup_selector_togglePreview_void_SelectorPopup_wasm(arg: cstring): cstring {.
    importc.}
proc togglePreview*(self: SelectorPopup) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_togglePreview_void_SelectorPopup_wasm(
      argsJsonString.cstring)


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


proc popup_selector_sort_void_SelectorPopup_ToggleBool_wasm(arg: cstring): cstring {.
    importc.}
proc sort*(self: SelectorPopup; sort: ToggleBool) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when ToggleBool is JsonNode:
      sort
    else:
      sort.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_sort_void_SelectorPopup_ToggleBool_wasm(
      argsJsonString.cstring)


proc popup_selector_setMinScore_void_SelectorPopup_float_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setMinScore*(self: SelectorPopup; value: float; add: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when float is JsonNode:
      value
    else:
      value.toJson()
  argsJson.add block:
    when bool is JsonNode:
      add
    else:
      add.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_setMinScore_void_SelectorPopup_float_bool_wasm(
      argsJsonString.cstring)


proc popup_selector_prev_void_SelectorPopup_int_wasm(arg: cstring): cstring {.
    importc.}
proc prev*(self: SelectorPopup; count: int = 1) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_prev_void_SelectorPopup_int_wasm(
      argsJsonString.cstring)


proc popup_selector_next_void_SelectorPopup_int_wasm(arg: cstring): cstring {.
    importc.}
proc next*(self: SelectorPopup; count: int = 1) =
  var argsJson = newJArray()
  argsJson.add block:
    when SelectorPopup is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = popup_selector_next_void_SelectorPopup_int_wasm(
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

