
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

proc textEditorGetSelectionImported(a0: int32): void {.
    wasmimport("get-selection", "nev:plugins/text-editor").}
proc getSelection*(): Selection {.nodestroy.} =
  var retArea: array[16, uint8]
  textEditorGetSelectionImported(cast[int32](retArea[0].addr))
  result.first.line = convert(cast[ptr int32](retArea[0].addr)[], int32)
  result.first.column = convert(cast[ptr int32](retArea[4].addr)[], int32)
  result.last.line = convert(cast[ptr int32](retArea[8].addr)[], int32)
  result.last.column = convert(cast[ptr int32](retArea[12].addr)[], int32)

proc textEditorAddModeChangedHandlerImported(a0: uint32): int32 {.
    wasmimport("add-mode-changed-handler", "nev:plugins/text-editor").}
proc addModeChangedHandler*(fun: uint32): int32 {.nodestroy.} =
  var arg0: uint32
  arg0 = fun
  let res = textEditorAddModeChangedHandlerImported(arg0)
  result = convert(res, int32)
