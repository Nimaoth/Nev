import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc plugins_callScriptAction_JsonNode_PluginService_string_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc callScriptAction*(context: string; args: JsonNode): JsonNode {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = plugins_callScriptAction_JsonNode_PluginService_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc plugins_addScriptAction_void_PluginService_string_string_seq_tuple_name_string_typ_string_string_bool_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc addScriptAction*(name: string; docs: string = "";
                      params: seq[tuple[name: string, typ: string]] = @[];
                      returnType: string = ""; active: bool = false;
                      context: string = "script"; override: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  argsJson.add docs.toJson()
  argsJson.add params.toJson()
  argsJson.add returnType.toJson()
  argsJson.add active.toJson()
  argsJson.add context.toJson()
  argsJson.add override.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = plugins_addScriptAction_void_PluginService_string_string_seq_tuple_name_string_typ_string_string_bool_string_bool_wasm(
      argsJsonString.cstring)

