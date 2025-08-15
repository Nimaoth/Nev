
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  View* = object
    id*: int32
proc layoutShowImported(a0: int32; a1: int32; a2: int32; a3: bool; a4: bool): void {.
    wasmimport("show", "nev:plugins/layout").}
proc show*(v: View; slot: WitString; focus: bool; addToHistory: bool): void {.
    nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: bool
    arg4: bool
  arg0 = v.id
  if slot.len > 0:
    arg1 = cast[int32](slot[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](slot.len)
  arg3 = focus
  arg4 = addToHistory
  layoutShowImported(arg0, arg1, arg2, arg3, arg4)

proc layoutCloseImported(a0: int32; a1: bool; a2: bool): void {.
    wasmimport("close", "nev:plugins/layout").}
proc close*(v: View; keepHidden: bool; restoreHidden: bool): void {.nodestroy.} =
  var
    arg0: int32
    arg1: bool
    arg2: bool
  arg0 = v.id
  arg1 = keepHidden
  arg2 = restoreHidden
  layoutCloseImported(arg0, arg1, arg2)

proc layoutFocusImported(a0: int32; a1: int32): void {.
    wasmimport("focus", "nev:plugins/layout").}
proc focus*(slot: WitString): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
  if slot.len > 0:
    arg0 = cast[int32](slot[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](slot.len)
  layoutFocusImported(arg0, arg1)
