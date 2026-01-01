
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
proc eventsListenEventImported(a0: uint32; a1: uint32; a2: int32; a3: int32;
                               a4: int32; a5: int32): void {.
    wasmimport("listen-event", "nev:plugins/events").}
proc listenEvent*(fun: uint32; data: uint32; id: WitString; pattern: WitString): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint32
    arg1: uint32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: int32
  arg0 = fun
  arg1 = data
  if id.len > 0:
    arg2 = cast[int32](id[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](id.len)
  if pattern.len > 0:
    arg4 = cast[int32](pattern[0].addr)
  else:
    arg4 = 0.int32
  arg5 = cast[int32](pattern.len)
  eventsListenEventImported(arg0, arg1, arg2, arg3, arg4, arg5)

proc eventsStopListenEventImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("stop-listen-event", "nev:plugins/events").}
proc stopListenEvent*(id: WitString; pattern: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if id.len > 0:
    arg0 = cast[int32](id[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](id.len)
  if pattern.len > 0:
    arg2 = cast[int32](pattern[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](pattern.len)
  eventsStopListenEventImported(arg0, arg1, arg2, arg3)

proc eventsEmitEventImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("emit-event", "nev:plugins/events").}
proc emitEvent*(event: WitString; payload: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if event.len > 0:
    arg0 = cast[int32](event[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](event.len)
  if payload.len > 0:
    arg2 = cast[int32](payload[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](payload.len)
  eventsEmitEventImported(arg0, arg1, arg2, arg3)
