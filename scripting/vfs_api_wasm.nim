import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc vfs_mountVfs_void_VFSService_string_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc mountVfs*(parentPath: string; prefix: string; config: JsonNode) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add parentPath.toJson()
  argsJson.add prefix.toJson()
  argsJson.add config.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = vfs_mountVfs_void_VFSService_string_string_JsonNode_wasm(
      argsJsonString.cstring)


proc vfs_normalizePath_string_VFSService_string_wasm(arg: cstring): cstring {.
    importc.}
proc normalizePath*(path: string): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = vfs_normalizePath_string_VFSService_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc vfs_dumpVfsHierarchy_void_VFSService_wasm(arg: cstring): cstring {.importc.}
proc dumpVfsHierarchy*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = vfs_dumpVfsHierarchy_void_VFSService_wasm(
      argsJsonString.cstring)

