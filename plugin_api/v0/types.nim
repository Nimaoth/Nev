
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
  ## Non-owning handle to an editor.
  Editor* = object
    id*: uint64
  ## Non-owning handle to a text editor.
  TextEditor* = object
    id*: uint64
  ## Non-owning handle to a document.
  Document* = object
    id*: uint64
  ## Non-owning handle to a text document.
  TextDocument* = object
    id*: uint64
  Task* = object
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

proc typesBytesImported(a0: int32): int64 {.
    wasmimport("[method]rope.bytes", "nev:plugins/types").}
proc bytes*(self: Rope): int64 {.nodestroy.} =
  ## Returns the number of bytes in the rope. This operation is cheap.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = typesBytesImported(arg0)
  result = convert(res, int64)

proc typesRunesImported(a0: int32): int64 {.
    wasmimport("[method]rope.runes", "nev:plugins/types").}
proc runes*(self: Rope): int64 {.nodestroy.} =
  ## Returns the number of UTF-8 code points. This operation is cheap.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = typesRunesImported(arg0)
  result = convert(res, int64)

proc typesLinesImported(a0: int32): int64 {.
    wasmimport("[method]rope.lines", "nev:plugins/types").}
proc lines*(self: Rope): int64 {.nodestroy.} =
  ## Returns the number of lines. This operation is cheap.
  var arg0: int32
  arg0 = cast[int32](self.handle - 1)
  let res = typesLinesImported(arg0)
  result = convert(res, int64)

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

proc typesSliceImported(a0: int32; a1: int64; a2: int64; a3: bool): int32 {.
    wasmimport("[method]rope.slice", "nev:plugins/types").}
proc slice*(self: Rope; a: int64; b: int64; inclusive: bool): Rope {.nodestroy.} =
  ## Returns a slice of the rope from 'a' to 'b'. 'a' and 'b' are byte indices, 'b' is inclusive if `inclusive` is true.
  ## This operation is cheap because it doesn't create a copy of the text.
  var
    arg0: int32
    arg1: int64
    arg2: int64
    arg3: bool
  arg0 = cast[int32](self.handle - 1)
  arg1 = a
  arg2 = b
  arg3 = inclusive
  let res = typesSliceImported(arg0, arg1, arg2, arg3)
  result.handle = res + 1

proc typesSliceSelectionImported(a0: int32; a1: int32; a2: int32; a3: int32;
                                 a4: int32; a5: bool): int32 {.
    wasmimport("[method]rope.slice-selection", "nev:plugins/types").}
proc sliceSelection*(self: Rope; s: Selection; inclusive: bool): Rope {.
    nodestroy.} =
  ## Returns a slice of the rope from the given selection. 's.last' is inclusive if `inclusive` is true.
  ## This operation is cheap because it doesn't create a copy of the text.
  var
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: bool
  arg0 = cast[int32](self.handle - 1)
  arg1 = s.first.line
  arg2 = s.first.column
  arg3 = s.last.line
  arg4 = s.last.column
  arg5 = inclusive
  let res = typesSliceSelectionImported(arg0, arg1, arg2, arg3, arg4, arg5)
  result.handle = res + 1

proc typesFindImported(a0: int32; a1: int32; a2: int32; a3: int64; a4: int32): void {.
    wasmimport("[method]rope.find", "nev:plugins/types").}
proc find*(self: Rope; sub: WitString; start: int64): Option[int64] {.nodestroy.} =
  ## Find the byte index of the sub string 'sub', starting the search at 'start'. The returned index is relative to the start of the rope, not 'start'.
  var
    retArea: array[24, uint8]
    arg0: int32
    arg1: int32
    arg2: int32
    arg3: int64
  arg0 = cast[int32](self.handle - 1)
  if sub.len > 0:
    arg1 = cast[int32](sub[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](sub.len)
  arg3 = start
  typesFindImported(arg0, arg1, arg2, arg3, cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: int64
    temp = convert(cast[ptr int64](retArea[8].addr)[], int64)
    result = temp.some

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
  arg3 = b.line
  arg4 = b.column
  let res = typesSlicePointsImported(arg0, arg1, arg2, arg3, arg4)
  result.handle = res + 1

proc typesLineLengthImported(a0: int32; a1: int64): int64 {.
    wasmimport("[method]rope.line-length", "nev:plugins/types").}
proc lineLength*(self: Rope; line: int64): int64 {.nodestroy.} =
  ## Return the length in bytes of the given line (0 based).
  var
    arg0: int32
    arg1: int64
  arg0 = cast[int32](self.handle - 1)
  arg1 = line
  let res = typesLineLengthImported(arg0, arg1)
  result = convert(res, int64)

proc typesRuneAtImported(a0: int32; a1: int32; a2: int32): Rune {.
    wasmimport("[method]rope.rune-at", "nev:plugins/types").}
proc runeAt*(self: Rope; a: Cursor): Rune {.nodestroy.} =
  ## /// Returns a slice of the rope from line 'a' to 'b'. 'b' is inclusive.
  ## /// This operation is cheap because it doesn't create a copy of the text.
  ## slice-lines: func(a: s64, b: s64) -> rope;
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = a.line
  arg2 = a.column
  let res = typesRuneAtImported(arg0, arg1, arg2)
  result = res.Rune

proc typesByteAtImported(a0: int32; a1: int32; a2: int32): uint8 {.
    wasmimport("[method]rope.byte-at", "nev:plugins/types").}
proc byteAt*(self: Rope; a: Cursor): uint8 {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: int32
  arg0 = cast[int32](self.handle - 1)
  arg1 = a.line
  arg2 = a.column
  let res = typesByteAtImported(arg0, arg1, arg2)
  result = convert(res, uint8)
