import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc collab_connectCollaborator_void_int_wasm(arg: cstring): cstring {.importc.}
proc connectCollaborator*(port: int = 6969) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add port.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = collab_connectCollaborator_void_int_wasm(
      argsJsonString.cstring)


proc collab_hostCollaborator_void_int_wasm(arg: cstring): cstring {.importc.}
proc hostCollaborator*(port: int = 6969) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add port.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = collab_hostCollaborator_void_int_wasm(
      argsJsonString.cstring)

