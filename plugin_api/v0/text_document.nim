
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
