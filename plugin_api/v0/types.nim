
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  ## Represents a cursor in a text editor. Line and column are both zero based.
  ## The column is in bytes.
  Cursor* = object
    line*: int32
    column*: int32
  ## The column of 'last' is exclusive.
  Selection* = object
    first*: Cursor
    last*: Cursor
  Vec2f* = object
    x*: float32
    y*: float32
  Rect* = object
    pos*: Vec2f
    size*: Vec2f
  ## Shared reference to a rope. The rope data is stored in the editor, not in the plugin, so ropes
  ## can be used to efficiently access any document content or share a string with another plugin.
  ## Ropes are reference counted internally, and this resource also affects that reference count.
  Rope* = object
    handle*: int32
  Editor* = object
    id*: uint64
  TextEditor* = object
    id*: uint64
  Document* = object
    id*: uint64
  TextDocument* = object
    id*: uint64
proc typesRopeDrop(a: int32): void {.wasmimport("[resource-drop]rope",
    "nev:plugins/types").}
proc `=copy`*(a: var Rope; b: Rope) {.error.}
proc `=destroy`*(a: Rope) =
  if a.handle != 0:
    typesRopeDrop(a.handle - 1)

proc typesNewRopeImported(a0: int32; a1: int32): int32 {.
    wasmimport("[constructor]rope", "nev:plugins/types").}
proc newRope*(content: WitString): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
  if content.len > 0:
    arg0 = cast[int32](content[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](content.len)
  let res = typesNewRopeImported(arg0, arg1)
  result.handle = res + 1

proc typesCloneImported(a0: int32): int32 {.
    wasmimport("[method]rope.clone", "nev:plugins/types").}
proc clone*(self: Rope): Rope {.nodestroy.} =
  ## Returns another reference to the same rope.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = typesCloneImported(arg0)
  result.handle = res + 1

proc typesTextImported(a0: int32; a1: int32): void {.
    wasmimport("[method]rope.text", "nev:plugins/types").}
proc text*(self: Rope): WitString {.nodestroy.} =
  ## Returns the text of the rope as a string. This is expensive for large ropes.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  typesTextImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc typesSliceImported(a0: int32; a1: int64; a2: int64): int32 {.
    wasmimport("[method]rope.slice", "nev:plugins/types").}
proc slice*(self: Rope; a: int64; b: int64): Rope {.nodestroy.} =
  ## Returns a slice of the rope from 'a' to 'b'. 'a' and 'b' are byte indices, 'b' is exclusive.
  ## This operation is cheap because it doesn't create a copy of the text.
  var
    arg0: int32
    arg1: int64
    arg2: int64
  arg0 = cast[int32](self.handle - 1)
  arg1 = a
  arg2 = b
  let res = typesSliceImported(arg0, arg1, arg2)
  result.handle = res + 1

proc typesSlicePointsImported(a0: int32; a1: int32; a2: int32; a3: int32;
                              a4: int32): int32 {.
    wasmimport("[method]rope.slice-points", "nev:plugins/types").}
proc slicePoints*(self: Rope; a: Cursor; b: Cursor): Rope {.nodestroy.} =
  ## Returns a slice of the rope from 'a' to 'b'. The column of 'b' is exclusive. Columns are in bytes.
  ## This operation is cheap because it doesn't create a copy of the text.
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = a.line
  arg2 = a.column
  arg2 = b.line
  arg3 = b.column
  let res = typesSlicePointsImported(arg0, arg1, arg2, arg3, arg4)
  result.handle = res + 1
