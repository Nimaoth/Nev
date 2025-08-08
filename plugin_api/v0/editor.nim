
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

proc editorActiveEditorImported(a0: int32): void {.
    wasmimport("active-editor", "nev:plugins/editor").}
proc activeEditor*(): Option[Editor] {.nodestroy.} =
  ## Returns a handle for the currently active text editor.
  var retArea: array[16, uint8]
  editorActiveEditorImported(cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: Editor
    temp.id = convert(cast[ptr uint64](retArea[8].addr)[], uint64)
    result = temp.some

proc editorGetDocumentImported(a0: uint64; a1: int32): void {.
    wasmimport("get-document", "nev:plugins/editor").}
proc getDocument*(editor: Editor): Option[Document] {.nodestroy.} =
  ## Returns the document the given editor is currently editing.
  var
    retArea: array[16, uint8]
    arg0: uint64
  arg0 = editor.id
  editorGetDocumentImported(arg0, cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: Document
    temp.id = convert(cast[ptr uint64](retArea[8].addr)[], uint64)
    result = temp.some
