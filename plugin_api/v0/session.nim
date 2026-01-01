
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
proc sessionGetSessionDataImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("get-session-data", "nev:plugins/session").}
proc getSessionData*(name: WitString): WitString {.nodestroy.} =
  ## todo
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  sessionGetSessionDataImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc sessionSetSessionDataImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("set-session-data", "nev:plugins/session").}
proc setSessionData*(name: WitString; value: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  if value.len > 0:
    arg2 = cast[int32](value[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](value.len)
  sessionSetSessionDataImported(arg0, arg1, arg2, arg3)
