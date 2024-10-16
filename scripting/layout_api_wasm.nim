import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc layout_setLayout_void_LayoutService_string_wasm(arg: cstring): cstring {.
    importc.}
proc setLayout*(layout: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add layout.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = layout_setLayout_void_LayoutService_string_wasm(
      argsJsonString.cstring)


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

