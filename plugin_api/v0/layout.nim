
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  ## Shared handle for a view.
  View* = object
    id*: int32
proc layoutShowImported(a0: int32; a1: int32; a2: int32; a3: bool; a4: bool): void {.
    wasmimport("show", "nev:plugins/layout").}
proc show*(v: View; slot: WitString; focus: bool; addToHistory: bool): void {.
    nodestroy.} =
  ## Show the given view in the given slot.  If focus is true it's also focused, otherwise focus remains as is if possible.
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
  ## Close the given view. If 'keep-hidden' is true then the view will only be removed from the layout tree but remains open
  ## in the background. If 'restore-hidden' is true the the current view will be replaced by the last hidden view,
  ## otherwise the current slot is removed from the layout.
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
  ## Set focus to the view in the given slot.
  var
    arg0: int32
    arg1: int32
  if slot.len > 0:
    arg0 = cast[int32](slot[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](slot.len)
  layoutFocusImported(arg0, arg1)

proc layoutCloseActiveViewImported(a0: bool; a1: bool): void {.
    wasmimport("close-active-view", "nev:plugins/layout").}
proc closeActiveView*(closeOpenPopup: bool; restoreHidden: bool): void {.
    nodestroy.} =
  ## Close the active view. If 'close-open-popup' is set and a popup is open then the popup will be closed.
  ## If 'restore-hidden' is true then the view will be replaced by a hidden view, otherwise the slot will be removed from the layout..
  var
    arg0: bool
    arg1: bool
  arg0 = closeOpenPopup
  arg1 = restoreHidden
  layoutCloseActiveViewImported(arg0, arg1)
