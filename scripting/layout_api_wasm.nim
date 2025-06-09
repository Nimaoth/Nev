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


proc layout_closeCurrentView_void_LayoutService_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeCurrentView*(keepHidden: bool = true; closeOpenPopup: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add keepHidden.toJson()
  argsJson.add closeOpenPopup.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeCurrentView_void_LayoutService_bool_bool_wasm(
      argsJsonString.cstring)


proc layout_closeOtherViews_void_LayoutService_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeOtherViews*(keepHidden: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add keepHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeOtherViews_void_LayoutService_bool_wasm(
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


proc layout_setLayout_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc setLayout*(layout: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add layout.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setLayout_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_focusView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc focusView*(slot: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_focusView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_nextView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc nextView*(slot: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_nextView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_prevView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc prevView*(slot: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_prevView_void_LayoutService_string_wasm(
      argsJsonString.cstring)


proc layout_openPreviousEditor_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openPreviousEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openPreviousEditor_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_openNextEditor_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openNextEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openNextEditor_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_openLastEditor_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openLastEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openLastEditor_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_setActiveIndex_void_LayoutService_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc setActiveIndex*(slot: string; index: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  argsJson.add index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setActiveIndex_void_LayoutService_string_int_wasm(
      argsJsonString.cstring)


proc layout_moveCurrentViewToTop_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewToTop*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveCurrentViewToTop_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveCurrentViewPrev_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewPrev*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveCurrentViewPrev_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveCurrentViewNext_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewNext*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveCurrentViewNext_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveCurrentViewNextAndGoBack_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewNextAndGoBack*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveCurrentViewNextAndGoBack_void_LayoutService_wasm(
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

