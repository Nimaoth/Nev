import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc toast_showToast_void_ToastService_string_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc showToast*(title: string; message: string; color: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add title.toJson()
  argsJson.add message.toJson()
  argsJson.add color.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = toast_showToast_void_ToastService_string_string_string_wasm(
      argsJsonString.cstring)

