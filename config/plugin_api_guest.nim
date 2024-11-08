
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime

{.pop.}
type
  Cursor* = object
    line*: int32
    column*: int32
  Selection* = object
    first*: Cursor
    last*: Cursor
proc getSelectionImported*(a0: int32): void {.
    wasmimport("get-selection", "nev:plugins/text-editor").}
proc getSelection*(): Selection =
  var retArea: array[16, uint8]
  getSelectionImported(cast[int32](retArea[0].addr))
  result.first.line = cast[ptr int32](retArea[0].addr)[]
  result.first.column = cast[ptr int32](retArea[4].addr)[]
  result.last.line = cast[ptr int32](retArea[8].addr)[]
  result.last.column = cast[ptr int32](retArea[12].addr)[]

proc initPlugin(): void
proc initPluginExported(): void {.wasmexport("init-plugin").} =
  initPlugin()
