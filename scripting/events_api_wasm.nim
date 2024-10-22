import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


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
