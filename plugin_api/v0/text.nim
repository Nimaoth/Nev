
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

type
  ## Shared reference to a rope. The rope data is stored in the editor, not in the plugin, so ropes
  ## can be used to efficiently access any document content or share a string with another plugin.
  ## Ropes are reference counted internally, and this resource also affects that reference count.
  Rope* = object
    handle*: int32
proc textRopeDrop(a: int32): void {.wasmimport("[resource-drop]rope",
    "nev:plugins/text").}
proc `=copy`*(a: var Rope; b: Rope) {.error.}
proc `=destroy`*(a: Rope) =
  if a.handle != 0:
    textRopeDrop(a.handle - 1)

proc textContentImported(a0: uint64): int32 {.
    wasmimport("content", "nev:plugins/text").}
proc content*(document: TextDocument): Rope {.nodestroy.} =
  ## Returns the rope containing the current content of the document.
  ## This rope is not automatically kept up to date when the document changes, but
  ## represents the content at the point in time this is called instead. Keeping ropes
  ## around should not have significant memory overhead because ropes share data under the hood.
  var arg0: uint64
  arg0 = document.id
  let res = textContentImported(arg0)
  result.handle = res + 1

proc textNewRopeImported(a0: int32; a1: int32): int32 {.
    wasmimport("[constructor]rope", "nev:plugins/text").}
proc newRope*(content: WitString): Rope {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
  if content.len > 0:
    arg0 = cast[int32](content[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](content.len)
  let res = textNewRopeImported(arg0, arg1)
  result.handle = res + 1

proc textCloneImported(a0: int32): int32 {.
    wasmimport("[method]rope.clone", "nev:plugins/text").}
proc clone*(self: Rope): Rope {.nodestroy.} =
  ## Returns another reference to the same rope.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = textCloneImported(arg0)
  result.handle = res + 1

proc textTextImported(a0: int32; a1: int32): void {.
    wasmimport("[method]rope.text", "nev:plugins/text").}
proc text*(self: Rope): WitString {.nodestroy.} =
  ## Returns the text of the rope as a string. This is expensive for large ropes.
  var
    retArea: array[8, uint8]
    arg0: int32
  arg0 = cast[int32](self.handle - 1)
  textTextImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textSliceImported(a0: int32; a1: int64; a2: int64): int32 {.
    wasmimport("[method]rope.slice", "nev:plugins/text").}
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
  let res = textSliceImported(arg0, arg1, arg2)
  result.handle = res + 1

proc textSlicePointsImported(a0: int32; a1: int32; a2: int32; a3: int32;
                             a4: int32): int32 {.
    wasmimport("[method]rope.slice-points", "nev:plugins/text").}
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
  arg3 = b.line
  arg4 = b.column
  let res = textSlicePointsImported(arg0, arg1, arg2, arg3, arg4)
  result.handle = res + 1
