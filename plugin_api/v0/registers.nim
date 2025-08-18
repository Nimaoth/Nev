
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
proc registersIsReplayingCommandsImported(): bool {.
    wasmimport("is-replaying-commands", "nev:plugins/registers").}
proc isReplayingCommands*(): bool {.nodestroy.} =
  ## todo
  let res = registersIsReplayingCommandsImported()
  result = res.bool

proc registersSetRegisterTextImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("set-register-text", "nev:plugins/registers").}
proc setRegisterText*(text: WitString; register: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
  if text.len > 0:
    arg0 = cast[int32](text[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](text.len)
  if register.len > 0:
    arg2 = cast[int32](register[0].addr)
  else:
    arg2 = 0.int32
  arg3 = cast[int32](register.len)
  registersSetRegisterTextImported(arg0, arg1, arg2, arg3)

proc registersStartRecordingCommandsImported(a0: int32; a1: int32): void {.
    wasmimport("start-recording-commands", "nev:plugins/registers").}
proc startRecordingCommands*(register: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: int32
    arg1: int32
  if register.len > 0:
    arg0 = cast[int32](register[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](register.len)
  registersStartRecordingCommandsImported(arg0, arg1)
