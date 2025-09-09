
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
  commands

type
  ScrollBehaviour* = enum
    CenterAlways = "center-always", CenterOffscreen = "center-offscreen",
    CenterMargin = "center-margin", ScrollToMargin = "scroll-to-margin",
    TopOfScreen = "top-of-screen"
  ScrollSnapBehaviour* = enum
    Never = "never", Always = "always",
    MinDistanceOffscreen = "min-distance-offscreen",
    MinDistanceCenter = "min-distance-center"
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

proc textEditorRecordCurrentCommandImported(a0: uint64; a1: int32; a2: int32): void {.
    wasmimport("record-current-command", "nev:plugins/text-editor").}
proc recordCurrentCommand*(editor: TextEditor; registers: WitList[WitString]): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
  arg0 = editor.id
  if registers.len > 0:
    arg1 = cast[int32](registers[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](registers.len)
  textEditorRecordCurrentCommandImported(arg0, arg1, arg2)

proc textEditorClearCurrentCommandHistoryImported(a0: uint64; a1: bool): void {.
    wasmimport("clear-current-command-history", "nev:plugins/text-editor").}
proc clearCurrentCommandHistory*(editor: TextEditor; retainLast: bool): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: bool
  arg0 = editor.id
  arg1 = retainLast
  textEditorClearCurrentCommandHistoryImported(arg0, arg1)

proc textEditorSaveCurrentCommandHistoryImported(a0: uint64): void {.
    wasmimport("save-current-command-history", "nev:plugins/text-editor").}
proc saveCurrentCommandHistory*(editor: TextEditor): void {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  textEditorSaveCurrentCommandHistoryImported(arg0)

proc textEditorHideCompletionsImported(a0: uint64): void {.
    wasmimport("hide-completions", "nev:plugins/text-editor").}
proc hideCompletions*(editor: TextEditor): void {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  textEditorHideCompletionsImported(arg0)

proc textEditorScrollToCursorImported(a0: uint64; a1: int8; a2: int8): void {.
    wasmimport("scroll-to-cursor", "nev:plugins/text-editor").}
proc scrollToCursor*(editor: TextEditor; behaviour: Option[ScrollBehaviour]): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int8
    arg2: int8
  arg0 = editor.id
  arg1 = behaviour.isSome.int8
  if behaviour.isSome:
    arg2 = cast[int8](behaviour.get)
  textEditorScrollToCursorImported(arg0, arg1, arg2)

proc textEditorSetNextSnapBehaviourImported(a0: uint64; a1: int8): void {.
    wasmimport("set-next-snap-behaviour", "nev:plugins/text-editor").}
proc setNextSnapBehaviour*(editor: TextEditor; behaviour: ScrollSnapBehaviour): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int8
  arg0 = editor.id
  arg1 = cast[int8](behaviour)
  textEditorSetNextSnapBehaviourImported(arg0, arg1)

proc textEditorUpdateTargetColumnImported(a0: uint64): void {.
    wasmimport("update-target-column", "nev:plugins/text-editor").}
proc updateTargetColumn*(editor: TextEditor): void {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  textEditorUpdateTargetColumnImported(arg0)

proc textEditorGetUsageImported(a0: uint64; a1: int32): void {.
    wasmimport("get-usage", "nev:plugins/text-editor").}
proc getUsage*(editor: TextEditor): WitString {.nodestroy.} =
  ## todo
  var
    retArea: array[8, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorGetUsageImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorGetRevisionImported(a0: uint64): int32 {.
    wasmimport("get-revision", "nev:plugins/text-editor").}
proc getRevision*(editor: TextEditor): int32 {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  let res = textEditorGetRevisionImported(arg0)
  result = convert(res, int32)

proc textEditorSetModeImported(a0: uint64; a1: int32; a2: int32; a3: bool): void {.
    wasmimport("set-mode", "nev:plugins/text-editor").}
proc setMode*(editor: TextEditor; mode: WitString; exclusive: bool): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: bool
  arg0 = editor.id
  if mode.len > 0:
    arg1 = cast[int32](mode[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](mode.len)
  arg3 = exclusive
  textEditorSetModeImported(arg0, arg1, arg2, arg3)

proc textEditorModeImported(a0: uint64; a1: int32): void {.
    wasmimport("mode", "nev:plugins/text-editor").}
proc mode*(editor: TextEditor): WitString {.nodestroy.} =
  ## todo
  var
    retArea: array[8, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorModeImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorModesImported(a0: uint64; a1: int32): void {.
    wasmimport("modes", "nev:plugins/text-editor").}
proc modes*(editor: TextEditor): WitList[WitString] {.nodestroy.} =
  ## todo
  var
    retArea: array[8, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorModesImported(arg0, cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorClearTabStopsImported(a0: uint64): void {.
    wasmimport("clear-tab-stops", "nev:plugins/text-editor").}
proc clearTabStops*(editor: TextEditor): void {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  textEditorClearTabStopsImported(arg0)

proc textEditorSelectNextTabStopImported(a0: uint64): void {.
    wasmimport("select-next-tab-stop", "nev:plugins/text-editor").}
proc selectNextTabStop*(editor: TextEditor): void {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  textEditorSelectNextTabStopImported(arg0)

proc textEditorSelectPrevTabStopImported(a0: uint64): void {.
    wasmimport("select-prev-tab-stop", "nev:plugins/text-editor").}
proc selectPrevTabStop*(editor: TextEditor): void {.nodestroy.} =
  ## todo
  var arg0: uint64
  arg0 = editor.id
  textEditorSelectPrevTabStopImported(arg0)

proc textEditorUndoImported(a0: uint64; a1: int32; a2: int32): void {.
    wasmimport("undo", "nev:plugins/text-editor").}
proc undo*(editor: TextEditor; checkpoint: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
  arg0 = editor.id
  if checkpoint.len > 0:
    arg1 = cast[int32](checkpoint[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](checkpoint.len)
  textEditorUndoImported(arg0, arg1, arg2)

proc textEditorRedoImported(a0: uint64; a1: int32; a2: int32): void {.
    wasmimport("redo", "nev:plugins/text-editor").}
proc redo*(editor: TextEditor; checkpoint: WitString): void {.nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
  arg0 = editor.id
  if checkpoint.len > 0:
    arg1 = cast[int32](checkpoint[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](checkpoint.len)
  textEditorRedoImported(arg0, arg1, arg2)

proc textEditorAddNextCheckpointImported(a0: uint64; a1: int32; a2: int32): void {.
    wasmimport("add-next-checkpoint", "nev:plugins/text-editor").}
proc addNextCheckpoint*(editor: TextEditor; checkpoint: WitString): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
  arg0 = editor.id
  if checkpoint.len > 0:
    arg1 = cast[int32](checkpoint[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](checkpoint.len)
  textEditorAddNextCheckpointImported(arg0, arg1, arg2)

proc textEditorCopyImported(a0: uint64; a1: int32; a2: int32; a3: bool): void {.
    wasmimport("copy", "nev:plugins/text-editor").}
proc copy*(editor: TextEditor; register: WitString; inclusiveEnd: bool): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: bool
  arg0 = editor.id
  if register.len > 0:
    arg1 = cast[int32](register[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](register.len)
  arg3 = inclusiveEnd
  textEditorCopyImported(arg0, arg1, arg2, arg3)

proc textEditorPasteImported(a0: uint64; a1: int32; a2: int32; a3: bool): void {.
    wasmimport("paste", "nev:plugins/text-editor").}
proc paste*(editor: TextEditor; register: WitString; inclusiveEnd: bool): void {.
    nodestroy.} =
  ## todo
  var
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: bool
  arg0 = editor.id
  if register.len > 0:
    arg1 = cast[int32](register[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](register.len)
  arg3 = inclusiveEnd
  textEditorPasteImported(arg0, arg1, arg2, arg3)

proc textEditorSetSearchQueryFromMoveImported(a0: uint64; a1: int32; a2: int32;
    a3: int32; a4: int32; a5: int32; a6: int32; a7: int32; a8: int32): void {.
    wasmimport("set-search-query-from-move", "nev:plugins/text-editor").}
proc setSearchQueryFromMove*(editor: TextEditor; move: WitString; count: int32;
                             prefix: WitString; suffix: WitString): Selection {.
    nodestroy.} =
  ## Set the search query by applying the given move to the current selection.
  ## 'prefix' and 'suffix' are appended to the string after escaping.
  var
    retArea: array[40, uint8]
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: int32
    arg6: int32
    arg7: int32
  arg0 = editor.id
  if move.len > 0:
    arg1 = cast[int32](move[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](move.len)
  arg3 = count
  if prefix.len > 0:
    arg4 = cast[int32](prefix[0].addr)
  else:
    arg4 = 0.int32
  arg5 = cast[int32](prefix.len)
  if suffix.len > 0:
    arg6 = cast[int32](suffix[0].addr)
  else:
    arg6 = 0.int32
  arg7 = cast[int32](suffix.len)
  textEditorSetSearchQueryFromMoveImported(arg0, arg1, arg2, arg3, arg4, arg5,
      arg6, arg7, cast[int32](retArea[0].addr))
  result.first.line = convert(cast[ptr int32](retArea[0].addr)[], int32)
  result.first.column = convert(cast[ptr int32](retArea[4].addr)[], int32)
  result.last.line = convert(cast[ptr int32](retArea[8].addr)[], int32)
  result.last.column = convert(cast[ptr int32](retArea[12].addr)[], int32)

proc textEditorSetSearchQueryImported(a0: uint64; a1: int32; a2: int32;
                                      a3: bool; a4: int32; a5: int32; a6: int32;
                                      a7: int32): bool {.
    wasmimport("set-search-query", "nev:plugins/text-editor").}
proc setSearchQuery*(editor: TextEditor; query: WitString; escapeRegex: bool;
                     prefix: WitString; suffix: WitString): bool {.nodestroy.} =
  ## Set the search query to 'query'. If 'escape-regex' is true the the 'query' string is escaped so special characters
  ## are searched for literally. 'prefix' and 'suffix' are appended to the string after escaping.
  var
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: bool
    arg4: int32
    arg5: int32
    arg6: int32
    arg7: int32
  arg0 = editor.id
  if query.len > 0:
    arg1 = cast[int32](query[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](query.len)
  arg3 = escapeRegex
  if prefix.len > 0:
    arg4 = cast[int32](prefix[0].addr)
  else:
    arg4 = 0.int32
  arg5 = cast[int32](prefix.len)
  if suffix.len > 0:
    arg6 = cast[int32](suffix[0].addr)
  else:
    arg6 = 0.int32
  arg7 = cast[int32](suffix.len)
  let res = textEditorSetSearchQueryImported(arg0, arg1, arg2, arg3, arg4, arg5,
      arg6, arg7)
  result = res.bool

proc textEditorGetSearchQueryImported(a0: uint64; a1: int32): void {.
    wasmimport("get-search-query", "nev:plugins/text-editor").}
proc getSearchQuery*(editor: TextEditor): WitString {.nodestroy.} =
  ## Returns the current search query.
  var
    retArea: array[8, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorGetSearchQueryImported(arg0, cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorApplyMoveImported(a0: uint64; a1: int32; a2: int32; a3: int32;
                                 a4: int32; a5: int32; a6: int32; a7: int32;
                                 a8: bool; a9: bool; a10: int32): void {.
    wasmimport("apply-move", "nev:plugins/text-editor").}
proc applyMove*(editor: TextEditor; selection: Selection; move: WitString;
                count: int32; wrap: bool; includeEol: bool): WitList[Selection] {.
    nodestroy.} =
  ## todo
  var
    retArea: array[48, uint8]
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: int32
    arg6: int32
    arg7: int32
    arg8: bool
    arg9: bool
  arg0 = editor.id
  arg1 = selection.first.line
  arg2 = selection.first.column
  arg3 = selection.last.line
  arg4 = selection.last.column
  if move.len > 0:
    arg5 = cast[int32](move[0].addr)
  else:
    arg5 = 0.int32
  arg6 = cast[int32](move.len)
  arg7 = count
  arg8 = wrap
  arg9 = includeEol
  textEditorApplyMoveImported(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7,
                              arg8, arg9, cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorMultiMoveImported(a0: uint64; a1: int32; a2: int32; a3: int32;
                                 a4: int32; a5: int32; a6: bool; a7: bool;
                                 a8: int32): void {.
    wasmimport("multi-move", "nev:plugins/text-editor").}
proc multiMove*(editor: TextEditor; selections: WitList[Selection];
                move: WitString; count: int32; wrap: bool; includeEol: bool): WitList[
    Selection] {.nodestroy.} =
  var
    retArea: array[40, uint8]
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: int32
    arg6: bool
    arg7: bool
  arg0 = editor.id
  if selections.len > 0:
    arg1 = cast[int32](selections[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](selections.len)
  if move.len > 0:
    arg3 = cast[int32](move[0].addr)
  else:
    arg3 = 0.int32
  arg4 = cast[int32](move.len)
  arg5 = count
  arg6 = wrap
  arg7 = includeEol
  textEditorMultiMoveImported(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7,
                              cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

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

proc textEditorSetSelectionsImported(a0: uint64; a1: int32; a2: int32): void {.
    wasmimport("set-selections", "nev:plugins/text-editor").}
proc setSelections*(editor: TextEditor; s: WitList[Selection]): void {.nodestroy.} =
  ## Sets the selections for the given editor.
  var
    arg0: uint64
    arg1: int32
    arg2: int32
  arg0 = editor.id
  if s.len > 0:
    arg1 = cast[int32](s[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](s.len)
  textEditorSetSelectionsImported(arg0, arg1, arg2)

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

proc textEditorGetSelectionsImported(a0: uint64; a1: int32): void {.
    wasmimport("get-selections", "nev:plugins/text-editor").}
proc getSelections*(editor: TextEditor): WitList[Selection] {.nodestroy.} =
  ## Returns the selections of the given editor.
  var
    retArea: array[8, uint8]
    arg0: uint64
  arg0 = editor.id
  textEditorGetSelectionsImported(arg0, cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorLineLengthImported(a0: uint64; a1: int32): int32 {.
    wasmimport("line-length", "nev:plugins/text-editor").}
proc lineLength*(editor: TextEditor; line: int32): int32 {.nodestroy.} =
  ## Return the length of the given line (0 based)
  var
    arg0: uint64
    arg1: int32
  arg0 = editor.id
  arg1 = line
  let res = textEditorLineLengthImported(arg0, arg1)
  result = convert(res, int32)

proc textEditorAddModeChangedHandlerImported(a0: uint32): int32 {.
    wasmimport("add-mode-changed-handler", "nev:plugins/text-editor").}
proc addModeChangedHandler*(fun: uint32): int32 {.nodestroy.} =
  ## Add a callback which will be called whenever any editor changes mode.
  var arg0: uint32
  arg0 = fun
  let res = textEditorAddModeChangedHandlerImported(arg0)
  result = convert(res, int32)

proc textEditorGetSettingRawImported(a0: uint64; a1: int32; a2: int32; a3: int32): void {.
    wasmimport("get-setting-raw", "nev:plugins/text-editor").}
proc getSettingRaw*(editor: TextEditor; name: WitString): WitString {.nodestroy.} =
  ## Returns the value of the setting with the given path, encoded as JSON.
  var
    retArea: array[16, uint8]
    arg0: uint64
    arg1: int32
    arg2: int32
  arg0 = editor.id
  if name.len > 0:
    arg1 = cast[int32](name[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](name.len)
  textEditorGetSettingRawImported(arg0, arg1, arg2,
                                  cast[int32](retArea[0].addr))
  result = ws(cast[ptr char](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorSetSettingRawImported(a0: uint64; a1: int32; a2: int32;
                                     a3: int32; a4: int32): void {.
    wasmimport("set-setting-raw", "nev:plugins/text-editor").}
proc setSettingRaw*(editor: TextEditor; name: WitString; value: WitString): void {.
    nodestroy.} =
  ## Set the value of the setting with the given path. The value must be encoded as JSON.
  var
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
  if value.len > 0:
    arg3 = cast[int32](value[0].addr)
  else:
    arg3 = 0.int32
  arg4 = cast[int32](value.len)
  textEditorSetSettingRawImported(arg0, arg1, arg2, arg3, arg4)

proc textEditorEditImported(a0: uint64; a1: int32; a2: int32; a3: int32;
                            a4: int32; a5: bool; a6: int32): void {.
    wasmimport("edit", "nev:plugins/text-editor").}
proc edit*(editor: TextEditor; selections: WitList[Selection];
           contents: WitList[WitString]; inclusive: bool): WitList[Selection] {.
    nodestroy.} =
  ## todo
  var
    retArea: array[32, uint8]
    arg0: uint64
    arg1: int32
    arg2: int32
    arg3: int32
    arg4: int32
    arg5: bool
  arg0 = editor.id
  if selections.len > 0:
    arg1 = cast[int32](selections[0].addr)
  else:
    arg1 = 0.int32
  arg2 = cast[int32](selections.len)
  if contents.len > 0:
    arg3 = cast[int32](contents[0].addr)
  else:
    arg3 = 0.int32
  arg4 = cast[int32](contents.len)
  arg5 = inclusive
  textEditorEditImported(arg0, arg1, arg2, arg3, arg4, arg5,
                         cast[int32](retArea[0].addr))
  result = wl(cast[ptr typeof(result[0])](cast[ptr int32](retArea[0].addr)[]),
              cast[ptr int32](retArea[4].addr)[])

proc textEditorDefineMoveImported(a0: int32; a1: int32; a2: uint32; a3: uint32): void {.
    wasmimport("define-move", "nev:plugins/text-editor").}
proc defineMove*(move: WitString; fun: uint32; data: uint32): void {.nodestroy.} =
  var
    arg0: int32
    arg1: int32
    arg2: uint32
    arg3: uint32
  if move.len > 0:
    arg0 = cast[int32](move[0].addr)
  else:
    arg0 = 0.int32
  arg1 = cast[int32](move.len)
  arg2 = fun
  arg3 = data
  textEditorDefineMoveImported(arg0, arg1, arg2, arg3)

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
