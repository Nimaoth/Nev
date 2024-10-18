import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc vcs_chooseGitActiveFiles_void_VCSService_bool_wasm(arg: cstring): cstring {.
    importc.}
proc chooseGitActiveFiles*(all: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = vcs_chooseGitActiveFiles_void_VCSService_bool_wasm(
      argsJsonString.cstring)

