import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editor_text_enableAutoReload_void_TextDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc enableAutoReload*(self: TextDocumentEditor; enabled: bool) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add enabled.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_enableAutoReload_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getFileName_string_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getFileName*(self: TextDocumentEditor): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getFileName_string_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_lineCount_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc lineCount*(self: TextDocumentEditor): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_lineCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_lineLength_int_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc lineLength*(self: TextDocumentEditor; line: int): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_lineLength_int_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_screenLineCount_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc screenLineCount*(self: TextDocumentEditor): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_screenLineCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorLine_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorLine*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                       wrap: bool = false; includeAfter: bool = false): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorLine_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorVisualLine_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorVisualLine*(self: TextDocumentEditor; cursor: Cursor;
                             offset: int; wrap: bool = false;
                             includeAfter: bool = false): Cursor {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorVisualLine_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorHome_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorHome*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                       wrap: bool; includeAfter: bool): Cursor {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorHome_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorEnd_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorEnd*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                      wrap: bool; includeAfter: bool): Cursor {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorEnd_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorVisualHome_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorVisualHome*(self: TextDocumentEditor; cursor: Cursor;
                             offset: int; wrap: bool; includeAfter: bool): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorVisualHome_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorVisualEnd_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorVisualEnd*(self: TextDocumentEditor; cursor: Cursor;
                            offset: int; wrap: bool; includeAfter: bool): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorVisualEnd_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorPrevFindResult_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                                 offset: int; wrap: bool; includeAfter: bool): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorPrevFindResult_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorNextFindResult_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                                 offset: int; wrap: bool; includeAfter: bool): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorNextFindResult_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorLineCenter_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorLineCenter*(self: TextDocumentEditor; cursor: Cursor;
                             offset: int; wrap: bool; includeAfter: bool): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorLineCenter_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorCenter_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorCenter*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                         wrap: bool; includeAfter: bool): Cursor {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorCenter_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_doMoveCursorColumn_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorColumn*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                         wrap: bool = true; includeAfter: bool = true): Cursor {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorColumn_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_includeSelectionEnd_Selection_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc includeSelectionEnd*(self: TextDocumentEditor; res: Selection;
                          includeAfter: bool = true): Selection {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add res.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_includeSelectionEnd_Selection_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_findSurroundStart_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
    arg: cstring): cstring {.importc.}
proc findSurroundStart*(editor: TextDocumentEditor; cursor: Cursor; count: int;
                        c0: char; c1: char; depth: int = 1): Option[Cursor] {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editor.toJson()
  argsJson.add cursor.toJson()
  argsJson.add count.toJson()
  argsJson.add c0.toJson()
  argsJson.add c1.toJson()
  argsJson.add depth.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_findSurroundStart_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_findSurroundEnd_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
    arg: cstring): cstring {.importc.}
proc findSurroundEnd*(editor: TextDocumentEditor; cursor: Cursor; count: int;
                      c0: char; c1: char; depth: int = 1): Option[Cursor] {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editor.toJson()
  argsJson.add cursor.toJson()
  argsJson.add count.toJson()
  argsJson.add c0.toJson()
  argsJson.add c1.toJson()
  argsJson.add depth.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_findSurroundEnd_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_setMode_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setMode*(self: TextDocumentEditor; mode: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setMode_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_mode_string_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc mode*(self: TextDocumentEditor): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_mode_string_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getContextWithMode_string_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc getContextWithMode*(self: TextDocumentEditor; context: string): string {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getContextWithMode_string_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc updateTargetColumn*(self: TextDocumentEditor;
                         cursor: SelectionCursor = Last) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_invertSelection_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc invertSelection*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_invertSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getRevision_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getRevision*(self: TextDocumentEditor): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getRevision_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getUsage_string_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getUsage*(self: TextDocumentEditor): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getUsage_string_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getText_string_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getText*(self: TextDocumentEditor; selection: Selection;
              inclusiveEnd: bool = false): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getText_string_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true): seq[Selection] {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selections.toJson()
  argsJson.add text.toJson()
  argsJson.add notify.toJson()
  argsJson.add record.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_insertMulti_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc insertMulti*(self: TextDocumentEditor; selections: seq[Selection];
                  texts: seq[string]; notify: bool = true; record: bool = true): seq[
    Selection] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selections.toJson()
  argsJson.add texts.toJson()
  argsJson.add notify.toJson()
  argsJson.add record.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insertMulti_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true;
             inclusiveEnd: bool = false): seq[Selection] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selections.toJson()
  argsJson.add notify.toJson()
  argsJson.add record.toJson()
  argsJson.add inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_edit_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc edit*(self: TextDocumentEditor; selections: seq[Selection];
           texts: seq[string]; notify: bool = true; record: bool = true;
           inclusiveEnd: bool = false): seq[Selection] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selections.toJson()
  argsJson.add texts.toJson()
  argsJson.add notify.toJson()
  argsJson.add record.toJson()
  argsJson.add inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_edit_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_deleteLines_void_TextDocumentEditor_Slice_int_Selections_wasm(
    arg: cstring): cstring {.importc.}
proc deleteLines*(self: TextDocumentEditor; slice: Slice[int];
                  oldSelections: Selections) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add slice.toJson()
  argsJson.add oldSelections.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteLines_void_TextDocumentEditor_Slice_int_Selections_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrev_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrev*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectPrev_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNext_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNext*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectNext_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(arg: cstring): cstring {.
    importc.}
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectInsideCurrent*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectLine_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc selectLine*(self: TextDocumentEditor; line: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectLine_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectLineCurrent*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getParentNodeSelection_Selection_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getParentNodeSelection*(self: TextDocumentEditor; selection: Selection;
                             includeAfter: bool = true): Selection {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getParentNodeSelection_Selection_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getNextNamedSiblingNodeSelection_Option_Selection_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextNamedSiblingNodeSelection*(self: TextDocumentEditor;
                                       selection: Selection;
                                       includeAfter: bool = true): Option[
    Selection] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextNamedSiblingNodeSelection_Option_Selection_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getNextSiblingNodeSelection_Option_Selection_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextSiblingNodeSelection*(self: TextDocumentEditor;
                                  selection: Selection;
                                  includeAfter: bool = true): Option[Selection] {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextSiblingNodeSelection_Option_Selection_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getParentNodeSelections_Selections_TextDocumentEditor_Selections_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getParentNodeSelections*(self: TextDocumentEditor; selections: Selections;
                              includeAfter: bool = true): Selections {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selections.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getParentNodeSelections_Selections_TextDocumentEditor_Selections_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_selectParentTs_void_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectParentTs*(self: TextDocumentEditor; selection: Selection;
                     includeAfter: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectParentTs_void_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)


proc editor_text_printTreesitterMemoryUsage_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc printTreesitterMemoryUsage*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_printTreesitterMemoryUsage_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_printTreesitterTree_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc printTreesitterTree*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_printTreesitterTree_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_printTreesitterTreeUnderCursor_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc printTreesitterTreeUnderCursor*(self: TextDocumentEditor) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_printTreesitterTreeUnderCursor_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentCurrentTs_void_TextDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectParentCurrentTs*(self: TextDocumentEditor; includeAfter: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectParentCurrentTs_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getNextNodeWithSameType_Option_Selection_TextDocumentEditor_Selection_int_bool_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextNodeWithSameType*(self: TextDocumentEditor; selection: Selection;
                              offset: int = 0; includeAfter: bool = true;
                              wrap: bool = true; stepIn: bool = true;
                              stepOut: bool = true): Option[Selection] {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add offset.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  argsJson.add stepIn.toJson()
  argsJson.add stepOut.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextNodeWithSameType_Option_Selection_TextDocumentEditor_Selection_int_bool_bool_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_shouldShowCompletionsAt_bool_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc shouldShowCompletionsAt*(self: TextDocumentEditor; cursor: Cursor): bool {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_shouldShowCompletionsAt_bool_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_autoShowCompletions_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc autoShowCompletions*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_autoShowCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insertText_void_TextDocumentEditor_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc insertText*(self: TextDocumentEditor; text: string; autoIndent: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add text.toJson()
  argsJson.add autoIndent.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insertText_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_indent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc indent*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_indent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_unindent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc unindent*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_unindent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insertIndent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc insertIndent*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insertIndent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_undo_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc undo*(self: TextDocumentEditor; checkpoint: string = "word") {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add checkpoint.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_undo_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_redo_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc redo*(self: TextDocumentEditor; checkpoint: string = "word") {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add checkpoint.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_redo_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_addNextCheckpoint_void_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc addNextCheckpoint*(self: TextDocumentEditor; checkpoint: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add checkpoint.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addNextCheckpoint_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_copy_void_TextDocumentEditor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc copy*(self: TextDocumentEditor; register: string = "";
           inclusiveEnd: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add register.toJson()
  argsJson.add inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_copy_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_paste_void_TextDocumentEditor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc paste*(self: TextDocumentEditor; registerName: string = "";
            inclusiveEnd: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add registerName.toJson()
  argsJson.add inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_paste_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_scrollText_void_TextDocumentEditor_float32_wasm(arg: cstring): cstring {.
    importc.}
proc scrollText*(self: TextDocumentEditor; amount: float32) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_scrollText_void_TextDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_text_scrollLines_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc scrollLines*(self: TextDocumentEditor; amount: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_scrollLines_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc duplicateLastSelection*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorBelow_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addCursorBelow*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addCursorBelow_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorAbove_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addCursorAbove*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addCursorAbove_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0; includeAfter: bool = true;
                        wrap: bool = true): Selection {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0; includeAfter: bool = true;
                        wrap: bool = true): Selection {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add offset.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getPrevDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevDiagnostic*(self: TextDocumentEditor; cursor: Cursor;
                        severity: int = 0; offset: int = 0;
                        includeAfter: bool = true; wrap: bool = true): Selection {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add severity.toJson()
  argsJson.add offset.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getNextDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextDiagnostic*(self: TextDocumentEditor; cursor: Cursor;
                        severity: int = 0; offset: int = 0;
                        includeAfter: bool = true; wrap: bool = true): Selection {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add severity.toJson()
  argsJson.add offset.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_closeDiff_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc closeDiff*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_closeDiff_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getPrevChange_Selection_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevChange*(self: TextDocumentEditor; cursor: Cursor): Selection {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevChange_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getNextChange_Selection_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc getNextChange*(self: TextDocumentEditor; cursor: Cursor): Selection {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextChange_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_updateDiff_void_TextDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc updateDiff*(self: TextDocumentEditor; gotoFirstDiff: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add gotoFirstDiff.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateDiff_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_checkoutFile_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc checkoutFile*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_checkoutFile_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc addNextFindResultToSelection*(self: TextDocumentEditor;
                                   includeAfter: bool = true; wrap: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addNextFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc addPrevFindResultToSelection*(self: TextDocumentEditor;
                                   includeAfter: bool = true; wrap: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add includeAfter.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc setAllFindResultToSelection*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearSelections_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearSelections*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearSelections_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true; wrap: bool = true;
                       includeAfter: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add distance.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true; wrap: bool = true;
                     includeAfter: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add distance.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorVisualLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorVisualLine*(self: TextDocumentEditor; distance: int;
                           cursor: SelectionCursor = SelectionCursor.Config;
                           all: bool = true; wrap: bool = true;
                           includeAfter: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add distance.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add wrap.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorVisualLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true; includeAfter: bool = true) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorVisualHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorVisualHome*(self: TextDocumentEditor;
                           cursor: SelectionCursor = SelectionCursor.Config;
                           all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorVisualHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorVisualEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorVisualEnd*(self: TextDocumentEditor;
                          cursor: SelectionCursor = SelectionCursor.Config;
                          all: bool = true; includeAfter: bool = true) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorVisualEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add str.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add str.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; wrap: bool = true) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; wrap: bool = true) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  argsJson.add wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLineCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineCenter*(self: TextDocumentEditor;
                           cursor: SelectionCursor = SelectionCursor.Config;
                           all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorLineCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorCenter*(self: TextDocumentEditor;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_setNextScrollBehaviour_void_TextDocumentEditor_ScrollBehaviour_wasm(
    arg: cstring): cstring {.importc.}
proc setNextScrollBehaviour*(self: TextDocumentEditor;
                             scrollBehaviour: ScrollBehaviour) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add scrollBehaviour.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setNextScrollBehaviour_void_TextDocumentEditor_ScrollBehaviour_wasm(
      argsJsonString.cstring)


proc editor_text_setCursorScrollOffset_void_TextDocumentEditor_float_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc setCursorScrollOffset*(self: TextDocumentEditor; offset: float;
                            cursor: SelectionCursor = SelectionCursor.Config) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add offset.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setCursorScrollOffset_void_TextDocumentEditor_float_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_getContentBounds_Vec2_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getContentBounds*(self: TextDocumentEditor): Vec2 {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getContentBounds_Vec2_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc centerCursor*(self: TextDocumentEditor;
                   cursor: SelectionCursor = SelectionCursor.Config) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc reloadTreesitter*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteLeft_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteLeft*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteLeft_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteRight_void_TextDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc deleteRight*(self: TextDocumentEditor; includeAfter: bool = true) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteRight_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getCommandCount_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getCommandCount*(self: TextDocumentEditor): int {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getCommandCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc setCommandCount*(self: TextDocumentEditor; count: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
    arg: cstring): cstring {.importc.}
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
    arg: cstring): cstring {.importc.}
proc updateCommandCount*(self: TextDocumentEditor; digit: int) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add digit.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add name.toJson()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getFlag_bool_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc getFlag*(self: TextDocumentEditor; name: string): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getFlag_bool_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_runAction_Option_JsonNode_TextDocumentEditor_string_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): Option[
    JsonNode] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add action.toJson()
  argsJson.add args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runAction_Option_JsonNode_TextDocumentEditor_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_wasm(
    arg: cstring): cstring {.importc.}
proc getSelectionInPair*(self: TextDocumentEditor; cursor: Cursor;
                         delimiter: char): Selection {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add delimiter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_wasm(
    arg: cstring): cstring {.importc.}
proc getSelectionInPairNested*(self: TextDocumentEditor; cursor: Cursor;
                               open: char; close: char): Selection {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add open.toJson()
  argsJson.add close.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_extendSelectionWithMove_Selection_TextDocumentEditor_Selection_string_int_wasm(
    arg: cstring): cstring {.importc.}
proc extendSelectionWithMove*(self: TextDocumentEditor; selection: Selection;
                              move: string; count: int = 0): Selection {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  argsJson.add move.toJson()
  argsJson.add count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_extendSelectionWithMove_Selection_TextDocumentEditor_Selection_string_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
    arg: cstring): cstring {.importc.}
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  argsJson.add move.toJson()
  argsJson.add count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_applyMove_void_TextDocumentEditor_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc applyMove*(self: TextDocumentEditor; args: JsonNode) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_applyMove_void_TextDocumentEditor_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc deleteMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add inside.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add inside.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_extendSelectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc extendSelectMove*(self: TextDocumentEditor; move: string;
                       inside: bool = false;
                       which: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add inside.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_extendSelectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc copyMove*(self: TextDocumentEditor; move: string; inside: bool = false;
               which: SelectionCursor = SelectionCursor.Config; all: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add inside.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc changeMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add inside.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg: cstring): cstring {.importc.}
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  argsJson.add count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg: cstring): cstring {.importc.}
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add which.toJson()
  argsJson.add all.toJson()
  argsJson.add count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQuery_void_TextDocumentEditor_string_bool_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc setSearchQuery*(self: TextDocumentEditor; query: string;
                     escapeRegex: bool = false; prefix: string = "";
                     suffix: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add query.toJson()
  argsJson.add escapeRegex.toJson()
  argsJson.add prefix.toJson()
  argsJson.add suffix.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSearchQuery_void_TextDocumentEditor_string_bool_string_string_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQueryFromMove_Selection_TextDocumentEditor_string_int_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0; prefix: string = "";
                             suffix: string = ""): Selection {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add move.toJson()
  argsJson.add count.toJson()
  argsJson.add prefix.toJson()
  argsJson.add suffix.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSearchQueryFromMove_Selection_TextDocumentEditor_string_int_string_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_toggleLineComment_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc toggleLineComment*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_toggleLineComment_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoDefinition_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoDefinition*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoDefinition_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoDeclaration_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoDeclaration*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoDeclaration_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoTypeDefinition_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoTypeDefinition*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoTypeDefinition_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoImplementation_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoImplementation*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoImplementation_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoReferences_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoReferences*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoReferences_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_switchSourceHeader_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc switchSourceHeader*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_switchSourceHeader_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getCompletions_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getCompletions*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoSymbol_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoSymbol*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoSymbol_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_fuzzySearchLines_void_TextDocumentEditor_float_bool_wasm(
    arg: cstring): cstring {.importc.}
proc fuzzySearchLines*(self: TextDocumentEditor; minScore: float = 0.2;
                       sort: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add minScore.toJson()
  argsJson.add sort.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_fuzzySearchLines_void_TextDocumentEditor_float_bool_wasm(
      argsJsonString.cstring)


proc editor_text_gotoWorkspaceSymbol_void_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc gotoWorkspaceSymbol*(self: TextDocumentEditor; query: string = "") {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add query.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoWorkspaceSymbol_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_hideCompletions_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideCompletions*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hideCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hasTabStops_bool_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hasTabStops*(self: TextDocumentEditor): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hasTabStops_bool_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_clearTabStops_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearTabStops*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearTabStops_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNextTabStop_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextTabStop*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectNextTabStop_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrevTabStop_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrevTabStop*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectPrevTabStop_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_applyCompletion_void_TextDocumentEditor_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc applyCompletion*(self: TextDocumentEditor; completion: JsonNode) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add completion.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_applyCompletion_void_TextDocumentEditor_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_showHoverFor_void_TextDocumentEditor_Cursor_wasm(arg: cstring): cstring {.
    importc.}
proc showHoverFor*(self: TextDocumentEditor; cursor: Cursor) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_showHoverFor_void_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)


proc editor_text_showHoverForCurrent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc showHoverForCurrent*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_showHoverForCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideHover_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideHover*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hideHover_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_cancelDelayedHideHover_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc cancelDelayedHideHover*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_cancelDelayedHideHover_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideHoverDelayed_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideHoverDelayed*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hideHoverDelayed_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearDiagnostics_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearDiagnostics*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearDiagnostics_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_setReadOnly_void_TextDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setReadOnly*(self: TextDocumentEditor; readOnly: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add readOnly.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setReadOnly_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_setFileReadOnly_void_TextDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setFileReadOnly*(self: TextDocumentEditor; readOnly: bool) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add readOnly.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setFileReadOnly_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_isRunningSavedCommands_bool_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc isRunningSavedCommands*(self: TextDocumentEditor): bool {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_isRunningSavedCommands_bool_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_runSavedCommands_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSavedCommands*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runSavedCommands_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc clearCurrentCommandHistory*(self: TextDocumentEditor;
                                 retainLast: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add retainLast.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc saveCurrentCommandHistory*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getSelection_Selection_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getSelection*(self: TextDocumentEditor): Selection {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelection_Selection_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_text_setSelection_void_TextDocumentEditor_Selection_wasm(
    arg: cstring): cstring {.importc.}
proc setSelection*(self: TextDocumentEditor; selection: Selection) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSelection_void_TextDocumentEditor_Selection_wasm(
      argsJsonString.cstring)


proc editor_text_setTargetSelection_void_TextDocumentEditor_Selection_wasm(
    arg: cstring): cstring {.importc.}
proc setTargetSelection*(self: TextDocumentEditor; selection: Selection) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add selection.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setTargetSelection_void_TextDocumentEditor_Selection_wasm(
      argsJsonString.cstring)


proc editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc enterChooseCursorMode*(self: TextDocumentEditor; action: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add action.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_recordCurrentCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc recordCurrentCommand*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_recordCurrentCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runSingleClickCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSingleClickCommand*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runSingleClickCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runDoubleClickCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runDoubleClickCommand*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runDoubleClickCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runTripleClickCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runTripleClickCommand*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runTripleClickCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runDragCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runDragCommand*(self: TextDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runDragCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)

