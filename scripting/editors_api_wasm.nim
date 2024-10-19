import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editors_getAllEditors_seq_EditorId_DocumentEditorService_wasm(arg: cstring): cstring {.
    importc.}
proc getAllEditors*(): seq[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editors_getAllEditors_seq_EditorId_DocumentEditorService_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editors_getExistingEditor_Option_EditorId_DocumentEditorService_string_wasm(
    arg: cstring): cstring {.importc.}
proc getExistingEditor*(path: string): Option[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editors_getExistingEditor_Option_EditorId_DocumentEditorService_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())

