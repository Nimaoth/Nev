import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc plugins_bindKeys_void_PluginService_string_string_string_string_string_string_tuple_filename_string_line_int_column_int_wasm(
    arg: cstring): cstring {.importc.}
proc bindKeys*(context: string; subContext: string; keys: string;
               action: string; arg: string = ""; description: string = "";
    source: tuple[filename: string, line: int, column: int] = ("", 0, 0)) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add subContext.toJson()
  argsJson.add keys.toJson()
  argsJson.add action.toJson()
  argsJson.add arg.toJson()
  argsJson.add description.toJson()
  argsJson.add source.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = plugins_bindKeys_void_PluginService_string_string_string_string_string_string_tuple_filename_string_line_int_column_int_wasm(
      argsJsonString.cstring)


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


proc plugins_addScriptAction_void_PluginService_string_string_seq_tuple_name_string_typ_string_string_bool_string_wasm(
    arg: cstring): cstring {.importc.}
proc addScriptAction*(name: string; docs: string = "";
                      params: seq[tuple[name: string, typ: string]] = @[];
                      returnType: string = ""; active: bool = false;
                      context: string = "script") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  argsJson.add docs.toJson()
  argsJson.add params.toJson()
  argsJson.add returnType.toJson()
  argsJson.add active.toJson()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = plugins_addScriptAction_void_PluginService_string_string_seq_tuple_name_string_typ_string_string_bool_string_wasm(
      argsJsonString.cstring)

