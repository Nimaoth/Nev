
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
import
  types

import
  core

proc textEditorActiveTextEditorImported(a0: int32): void {.
    wasmimport("active-text-editor", "nev:plugins/text-editor").}
proc activeTextEditor*(): Option[TextEditor] {.nodestroy.} =
  ## Returns a handle for the currently active text editor.
  var retArea: array[16, uint8]
  textEditorActiveTextEditorImported(cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: TextEditor
    temp.id = convert(cast[ptr uint64](retArea[8].addr)[], uint64)
    result = temp.some

proc textEditorGetDocumentImported(a0: uint64; a1: int32): void {.
    wasmimport("get-document", "nev:plugins/text-editor").}
proc getDocument*(editor: TextEditor): Option[TextDocument] {.nodestroy.} =
  ## Returns the text document the given editor is currently editing.
  var
    retArea: array[16, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorGetDocumentImported(arg0, cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: TextDocument
    temp.id = convert(cast[ptr uint64](retArea[8].addr)[], uint64)
    result = temp.some

proc textEditorAsTextEditorImported(a0: uint64; a1: int32): void {.
    wasmimport("as-text-editor", "nev:plugins/text-editor").}
proc asTextEditor*(editor: Editor): Option[TextEditor] {.nodestroy.} =
  ## Try to cast the given editor handle to a text editor handle.
  var
    retArea: array[16, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorAsTextEditorImported(arg0, cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: TextEditor
    temp.id = convert(cast[ptr uint64](retArea[8].addr)[], uint64)
    result = temp.some

proc textEditorAsTextDocumentImported(a0: uint64; a1: int32): void {.
    wasmimport("as-text-document", "nev:plugins/text-editor").}
proc asTextDocument*(document: Document): Option[TextDocument] {.nodestroy.} =
  ## Try to cast the given document handle to a text document handle.
  var
    retArea: array[16, uint8]
    arg0: uint64
  arg0 = document.id
  textEditorAsTextDocumentImported(arg0, cast[int32](retArea[0].addr))
  if cast[ptr int64](retArea[0].addr)[] != 0:
    var temp: TextDocument
    temp.id = convert(cast[ptr uint64](retArea[8].addr)[], uint64)
    result = temp.some

proc textEditorCommandImported(a0: uint64; a1: int32; a2: int32; a3: int32;
                               a4: int32; a5: int32): void {.
    wasmimport("command", "nev:plugins/text-editor").}
proc command*(editor: TextEditor; name: WitString; arguments: WitString): Result[
    WitString, CommandError] {.nodestroy.} =
  ## Run the given command on the given text editor. This requires 'command' permissions.
  var
    retArea: array[24, uint8]
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
  arg0 = editor.id
  if name.len > 0:
    arg1 = cast[int32](name[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](name.len)
  if arguments.len > 0:
    arg3 = cast[int32](arguments[0].addr)
  else:
    arg3 = 0.int32
  arg4 = cast[int32](arguments.len)
  textEditorCommandImported(arg0, arg1, arg2, arg3, arg4,
                            cast[int32](retArea[0].addr))
  if cast[ptr int32](retArea[0].addr)[] == 0:
    var tempOk: WitString
    tempOk = ws(cast[ptr char](cast[ptr int32](retArea[4].addr)[]),
                cast[ptr int32](retArea[8].addr)[])
    result = results.Result[WitString, CommandError].ok(tempOk)
  else:
    var tempErr: CommandError
    tempErr = cast[CommandError](cast[ptr int32](retArea[4].addr)[])
    result = results.Result[WitString, CommandError].err(tempErr)

proc textEditorSetSelectionImported(a0: uint64; a1: int32; a2: int32; a3: int32;
                                    a4: int32): void {.
    wasmimport("set-selection", "nev:plugins/text-editor").}
proc setSelection*(editor: TextEditor; s: Selection): void {.nodestroy.} =
  ## Sets the given selection as the only selection for the given editor.
  var
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
  arg0 = editor.id
  arg1 = s.first.line
  arg2 = s.first.column
  arg3 = s.last.line
  arg4 = s.last.column
  textEditorSetSelectionImported(arg0, arg1, arg2, arg3, arg4)

proc textEditorGetSelectionImported(a0: uint64; a1: int32): void {.
    wasmimport("get-selection", "nev:plugins/text-editor").}
proc getSelection*(editor: TextEditor): Selection {.nodestroy.} =
  ## Returns the last selection of the given editor.
  var
    retArea: array[16, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorGetSelectionImported(arg0, cast[int32](retArea[0].addr))
  result.first.line = convert(cast[ptr int32](retArea[0].addr)[], int32)
  result.first.column = convert(cast[ptr int32](retArea[4].addr)[], int32)
  result.last.line = convert(cast[ptr int32](retArea[8].addr)[], int32)
  result.last.column = convert(cast[ptr int32](retArea[12].addr)[], int32)

proc textEditorAddModeChangedHandlerImported(a0: uint32): int32 {.
    wasmimport("add-mode-changed-handler", "nev:plugins/text-editor").}
proc addModeChangedHandler*(fun: uint32): int32 {.nodestroy.} =
  ## Add a callback which will be called whenever any editor changes mode.
  var arg0: uint32
  arg0 = fun
  let res = textEditorAddModeChangedHandlerImported(arg0)
  result = convert(res, int32)

proc textEditorContentImported(a0: uint64): int32 {.
    wasmimport("content", "nev:plugins/text-editor").}
proc content*(editor: TextEditor): Rope {.nodestroy.} =
  ## Returns the rope containing the current content of the text editors document.
  ## This rope is not automatically kept up to date when the document changes, but
  ## represents the content at the point in time this is called instead. Keeping ropes
  ## around should not have significant memory overhead because ropes share data under the hood.
  var arg0: uint64
  arg0 = editor.id
  let res = textEditorContentImported(arg0)
  result.handle = res + 1
