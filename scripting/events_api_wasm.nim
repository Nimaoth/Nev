import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc events_addKeyDefinitions_void_EventHandlerService_string_seq_string_wasm(
    arg: cstring): cstring {.importc.}
proc addKeyDefinitions*(name: string; keys: seq[string]) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  argsJson.add keys.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_addKeyDefinitions_void_EventHandlerService_string_seq_string_wasm(
      argsJsonString.cstring)


proc events_setKeyDefinitions_void_EventHandlerService_string_seq_string_wasm(
    arg: cstring): cstring {.importc.}
proc setKeyDefinitions*(name: string; keys: seq[string]) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  argsJson.add keys.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_setKeyDefinitions_void_EventHandlerService_string_seq_string_wasm(
      argsJsonString.cstring)


proc events_setLeader_void_EventHandlerService_string_wasm(arg: cstring): cstring {.
    importc.}
proc setLeader*(leader: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leader.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_setLeader_void_EventHandlerService_string_wasm(
      argsJsonString.cstring)


proc events_setLeaders_void_EventHandlerService_seq_string_wasm(arg: cstring): cstring {.
    importc.}
proc setLeaders*(leaders: seq[string]) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leaders.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_setLeaders_void_EventHandlerService_seq_string_wasm(
      argsJsonString.cstring)


proc events_addLeader_void_EventHandlerService_string_wasm(arg: cstring): cstring {.
    importc.}
proc addLeader*(leader: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leader.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_addLeader_void_EventHandlerService_string_wasm(
      argsJsonString.cstring)


proc events_addLeaders_void_EventHandlerService_seq_string_wasm(arg: cstring): cstring {.
    importc.}
proc addLeaders*(leaders: seq[string]) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leaders.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_addLeaders_void_EventHandlerService_seq_string_wasm(
      argsJsonString.cstring)


proc events_clearCommands_void_EventHandlerService_string_wasm(arg: cstring): cstring {.
    importc.}
proc clearCommands*(context: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_clearCommands_void_EventHandlerService_string_wasm(
      argsJsonString.cstring)


proc events_removeCommand_void_EventHandlerService_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc removeCommand*(context: string; keys: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add keys.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_removeCommand_void_EventHandlerService_string_string_wasm(
      argsJsonString.cstring)


proc events_addCommandDescription_void_EventHandlerService_string_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc addCommandDescription*(context: string; keys: string;
                            description: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add keys.toJson()
  argsJson.add description.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = events_addCommandDescription_void_EventHandlerService_string_string_string_wasm(
      argsJsonString.cstring)

