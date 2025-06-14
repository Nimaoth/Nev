import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc layout_changeSplitSize_void_LayoutService_float_bool_wasm(arg: cstring): cstring {.
    importc.}
proc changeSplitSize*(change: float; vertical: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add change.toJson()
  argsJson.add vertical.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_changeSplitSize_void_LayoutService_float_bool_wasm(
      argsJsonString.cstring)


proc layout_toggleMaximizeViewLocal_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc toggleMaximizeViewLocal*(slot: string = "**") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_toggleMaximizeViewLocal_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_toggleMaximizeView_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc toggleMaximizeView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_toggleMaximizeView_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_setMaxViews_void_LayoutService_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc setMaxViews*(slot: string; maxViews: int = int.high) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  argsJson.add maxViews.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setMaxViews_void_LayoutService_string_int_wasm(
      argsJsonString.cstring)


proc layout_getNumVisibleViews_int_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc getNumVisibleViews*(): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_getNumVisibleViews_int_LayoutService_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc layout_getNumHiddenViews_int_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc getNumHiddenViews*(): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_getNumHiddenViews_int_LayoutService_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc layout_showEditor_void_LayoutService_EditorId_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc showEditor*(editorId: EditorId; slot: string = ""; focus: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  argsJson.add slot.toJson()
  argsJson.add focus.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_showEditor_void_LayoutService_EditorId_string_bool_wasm(
      argsJsonString.cstring)


proc layout_getOrOpenEditor_Option_EditorId_LayoutService_string_wasm(
    arg: cstring): cstring {.importc.}
proc getOrOpenEditor*(path: string): Option[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_getOrOpenEditor_Option_EditorId_LayoutService_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc layout_hideActiveView_void_LayoutService_bool_wasm(arg: cstring): cstring {.
    importc.}
proc hideActiveView*(closeOpenPopup: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add closeOpenPopup.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_hideActiveView_void_LayoutService_bool_wasm(
      argsJsonString.cstring)


proc layout_closeActiveView_void_LayoutService_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeActiveView*(closeOpenPopup: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add closeOpenPopup.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeActiveView_void_LayoutService_bool_wasm(
      argsJsonString.cstring)


proc layout_hideOtherViews_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc hideOtherViews*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_hideOtherViews_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_closeOtherViews_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc closeOtherViews*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeOtherViews_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_focusViewLeft_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc focusViewLeft*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusViewLeft_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_focusViewRight_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc focusViewRight*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusViewRight_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_focusViewUp_void_LayoutService_wasm(arg: cstring): cstring {.importc.}
proc focusViewUp*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusViewUp_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_focusViewDown_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc focusViewDown*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusViewDown_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_focusView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc focusView*(slot: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_focusNextView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc focusNextView*(slot: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusNextView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_focusPrevView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc focusPrevView*(slot: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusPrevView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_openPrevView_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openPrevView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openPrevView_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_openNextView_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openNextView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openNextView_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_openLastView_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openLastView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openLastView_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_setLayout_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc setLayout*(layout: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add layout.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setLayout_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_setActiveViewIndex_void_LayoutService_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc setActiveViewIndex*(slot: string; index: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  argsJson.add index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setActiveViewIndex_void_LayoutService_string_int_wasm(
      argsJsonString.cstring)


proc layout_moveActiveViewFirst_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveActiveViewFirst*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveActiveViewFirst_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveActiveViewPrev_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveActiveViewPrev*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveActiveViewPrev_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveActiveViewNext_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveActiveViewNext*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveActiveViewNext_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveActiveViewNextAndGoBack_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveActiveViewNextAndGoBack*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveActiveViewNextAndGoBack_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_splitView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc splitView*(slot: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_splitView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_moveView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc moveView*(slot: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_chooseLayout_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc chooseLayout*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_chooseLayout_void_LayoutService_wasm(
      argsJsonString.cstring)

