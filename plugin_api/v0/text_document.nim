
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

proc textDocumentContentImported(a0: uint64): int32 {.
    wasmimport("content", "nev:plugins/text-document").}
proc content*(document: TextDocument): Rope {.nodestroy.} =
  ## Returns the rope containing the current content of the document.
  ## This rope is not automatically kept up to date when the document changes, but
  ## represents the content at the point in time this is called instead. Keeping ropes
  ## around should not have significant memory overhead because ropes share data under the hood.
  var arg0: uint64
  arg0 = document.id
  let res = textDocumentContentImported(arg0)
  result.handle = res + 1

proc textDocumentPathImported(a0: uint64; a1: int32): void {.
    wasmimport("path", "nev:plugins/text-document").}
proc path*(document: TextDocument): WitString {.nodestroy.} =
  ## VFS file path
  var
    retArea: array[8, uint8]
    arg0: uint64
  arg0 = document.id
  textDocumentPathImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])
