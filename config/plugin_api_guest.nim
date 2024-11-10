
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
  Rope* = object
    handle*: int32
proc textRopeDrop(a: int32): void {.wasmimport("[resource-drop]rope",
    "nev:plugins/text").}
proc `=copy`*(a: var Rope; b: Rope) {.error.}
proc `=destroy`*(a: Rope) =
  if a.handle != 0:
    textRopeDrop(a.handle - 1)

proc textEditorGetSelectionImported(a0: int32): void {.
    wasmimport("get-selection", "nev:plugins/text-editor").}
proc getSelection*(): Selection {.nodestroy.} =
  var retArea: array[16, uint8]
  textEditorGetSelectionImported(cast[int32](retArea[0].addr))
  result.first.line = cast[ptr int32](retArea[0].addr)[]
  result.first.column = cast[ptr int32](retArea[4].addr)[]
  result.last.line = cast[ptr int32](retArea[8].addr)[]
  result.last.column = cast[ptr int32](retArea[12].addr)[]

proc textNewRopeImported(a0: int32; a1: int32): int32 {.
    wasmimport("[constructor]rope", "nev:plugins/text").}
proc newRope*(content: WitString): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
  if content.len > 0:
    arg0 = cast[int32](content[0].addr)
  else:
    arg0 = 0
  arg1 = content.len
  let res = textNewRopeImported(arg0, arg1)
  result.handle = res + 1

proc textCloneImported(a0: int32): int32 {.
    wasmimport("[method]rope.clone", "nev:plugins/text").}
proc clone*(self: Rope): Rope {.nodestroy.} =
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = textCloneImported(arg0)
  result.handle = res + 1

proc textTextImported(a0: int32; a1: int32): void {.
    wasmimport("[method]rope.text", "nev:plugins/text").}
proc text*(self: Rope): WitString {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  textTextImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textDebugImported(a0: int32; a1: int32): void {.
    wasmimport("[method]rope.debug", "nev:plugins/text").}
proc debug*(self: Rope): WitString {.nodestroy.} =
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  textDebugImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textSliceImported(a0: int32; a1: int64; a2: int64): int32 {.
    wasmimport("[method]rope.slice", "nev:plugins/text").}
proc slice*(self: Rope; a: int64; b: int64): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int64
    arg2: int64
  arg0 = cast[int32](self.handle - 1)
  arg1 = cast[int64](a)
  arg2 = cast[int64](b)
  let res = textSliceImported(arg0, arg1, arg2)
  result.handle = res + 1

proc textSlicePointsImported(a0: int32; a1: int32; a2: int32; a3: int32;
                             a4: int32): int32 {.
    wasmimport("[method]rope.slice-points", "nev:plugins/text").}
proc slicePoints*(self: Rope; a: Cursor; b: Cursor): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = cast[int32](a.line)
  arg2 = cast[int32](a.column)
  arg3 = cast[int32](b.line)
  arg4 = cast[int32](b.column)
  let res = textSlicePointsImported(arg0, arg1, arg2, arg3, arg4)
  result.handle = res + 1

proc textGetCurrentEditorRopeImported(): int32 {.
    wasmimport("[static]rope.get-current-editor-rope", "nev:plugins/text").}
proc getCurrentEditorRope*(): Rope {.nodestroy.} =
  let res = textGetCurrentEditorRopeImported()
  result.handle = res + 1

proc initPlugin(): void
proc initPluginExported(): void {.wasmexport("init-plugin").} =
  initPlugin()
