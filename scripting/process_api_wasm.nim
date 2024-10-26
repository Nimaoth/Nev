import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc process_runProcess_void_PluginService_string_seq_string_Option_string_Option_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc runProcess*(process: string; args: seq[string];
                 callback: Option[string] = string.none;
                 workingDir: Option[string] = string.none; eval: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add process.toJson()
  argsJson.add args.toJson()
  argsJson.add callback.toJson()
  argsJson.add workingDir.toJson()
  argsJson.add eval.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = process_runProcess_void_PluginService_string_seq_string_Option_string_Option_string_bool_wasm(
      argsJsonString.cstring)

