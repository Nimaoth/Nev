import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc layout_changeLayoutProp_void_LayoutService_string_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeLayoutProp*(prop: string; change: float32) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add prop.toJson()
  argsJson.add change.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_changeLayoutProp_void_LayoutService_string_float32_wasm(
      argsJsonString.cstring)


proc layout_toggleMaximizeView_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc toggleMaximizeView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_toggleMaximizeView_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_setMaxViews_void_LayoutService_int_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setMaxViews*(maxViews: int; openExisting: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add maxViews.toJson()
  argsJson.add openExisting.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setMaxViews_void_LayoutService_int_bool_wasm(
      argsJsonString.cstring)


proc layout_getEditorInView_EditorId_LayoutService_int_wasm(arg: cstring): cstring {.
    importc.}
proc getEditorInView*(index: int): EditorId {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_getEditorInView_EditorId_LayoutService_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc layout_getVisibleEditors_seq_EditorId_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc getVisibleEditors*(): seq[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_getVisibleEditors_seq_EditorId_LayoutService_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc layout_getHiddenEditors_seq_EditorId_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc getHiddenEditors*(): seq[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_getHiddenEditors_seq_EditorId_LayoutService_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


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


proc layout_showEditor_void_LayoutService_EditorId_Option_int_wasm(arg: cstring): cstring {.
    importc.}
proc showEditor*(editorId: EditorId; viewIndex: Option[int] = int.none) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  argsJson.add viewIndex.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_showEditor_void_LayoutService_EditorId_Option_int_wasm(
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


proc layout_closeView_void_LayoutService_int_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeView*(index: int; keepHidden: bool = true; restoreHidden: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add index.toJson()
  argsJson.add keepHidden.toJson()
  argsJson.add restoreHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeView_void_LayoutService_int_bool_bool_wasm(
      argsJsonString.cstring)


proc layout_closeCurrentView_void_LayoutService_bool_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeCurrentView*(keepHidden: bool = true; restoreHidden: bool = true;
                       closeOpenPopup: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add keepHidden.toJson()
  argsJson.add restoreHidden.toJson()
  argsJson.add closeOpenPopup.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeCurrentView_void_LayoutService_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc layout_closeOtherViews_void_LayoutService_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeOtherViews*(keepHidden: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add keepHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_closeOtherViews_void_LayoutService_bool_wasm(
      argsJsonString.cstring)


proc layout_moveCurrentViewToTop_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewToTop*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveCurrentViewToTop_void_LayoutService_wasm(
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


proc layout_setActiveIndex_void_LayoutService_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc setActiveIndex*(slot: string; index: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  argsJson.add index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setActiveIndex_void_LayoutService_string_int_wasm(
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


proc layout_openLastEditor_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc openLastEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_openLastEditor_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveCurrentViewNextAndGoBack_void_LayoutService_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewNextAndGoBack*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveCurrentViewNextAndGoBack_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_splitView_void_LayoutService_wasm(arg: cstring): cstring {.importc.}
proc splitView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = layout_splitView_void_LayoutService_wasm(
      argsJsonString.cstring)


proc layout_moveView_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc moveView*(slot: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_moveView_void_LayoutService_string_wasm(
      argsJsonString.cstring)

