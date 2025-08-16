
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
proc settingsGetSettingRawImported(a0: int32; a1: int32; a2: int32): void {.
    wasmimport("get-setting-raw", "nev:plugins/settings").}
proc getSettingRaw*(name: WitString): WitString {.nodestroy.} =
  ## Returns the value of the setting with the given path, encoded as JSON.
  var
    retArea: array[8, uint8]
    arg0: int32
    arg1: int32
  if name.len > 0:
    arg0 = cast[int32](name[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](name.len)
  settingsGetSettingRawImported(arg0, arg1, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc settingsSetSettingRawImported(a0: int32; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("set-setting-raw", "nev:plugins/settings").}
proc setSettingRaw*(name: WitString; value: WitString): void {.nodestroy.} =
  ## Set the value of the setting with the given path. The value must be encoded as JSON.
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
  settingsSetSettingRawImported(arg0, arg1, arg2, arg3)
