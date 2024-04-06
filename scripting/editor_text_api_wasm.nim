import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editor_text_lineCount_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc lineCount*(self: TextDocumentEditor): int =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_lineCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_lineLength_int_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc lineLength*(self: TextDocumentEditor; line: int): int =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_lineLength_int_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_screenLineCount_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc screenLineCount*(self: TextDocumentEditor): int =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_screenLineCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_doMoveCursorColumn_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc doMoveCursorColumn*(self: TextDocumentEditor; cursor: Cursor; offset: int;
                         wrap: bool = true; includeAfter: bool = true): Cursor =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_doMoveCursorColumn_Cursor_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_findSurroundStart_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
    arg: cstring): cstring {.importc.}
proc findSurroundStart*(editor: TextDocumentEditor; cursor: Cursor; count: int;
                        c0: char; c1: char; depth: int = 1): Option[Cursor] =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      editor
    else:
      editor.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  argsJson.add block:
    when char is JsonNode:
      c0
    else:
      c0.toJson()
  argsJson.add block:
    when char is JsonNode:
      c1
    else:
      c1.toJson()
  argsJson.add block:
    when int is JsonNode:
      depth
    else:
      depth.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_findSurroundStart_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_findSurroundEnd_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
    arg: cstring): cstring {.importc.}
proc findSurroundEnd*(editor: TextDocumentEditor; cursor: Cursor; count: int;
                      c0: char; c1: char; depth: int = 1): Option[Cursor] =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      editor
    else:
      editor.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  argsJson.add block:
    when char is JsonNode:
      c0
    else:
      c0.toJson()
  argsJson.add block:
    when char is JsonNode:
      c1
    else:
      c1.toJson()
  argsJson.add block:
    when int is JsonNode:
      depth
    else:
      depth.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_findSurroundEnd_Option_Cursor_TextDocumentEditor_Cursor_int_char_char_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_setMode_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setMode*(self: TextDocumentEditor; mode: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setMode_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_mode_string_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc mode*(self: TextDocumentEditor): string =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_mode_string_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getContextWithMode_string_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getContextWithMode_string_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc updateTargetColumn*(self: TextDocumentEditor;
                         cursor: SelectionCursor = Last) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_invertSelection_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc invertSelection*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_invertSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getText_string_TextDocumentEditor_Selection_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getText*(self: TextDocumentEditor; selection: Selection;
              inclusiveEnd: bool = false): string =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inclusiveEnd
    else:
      inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getText_string_TextDocumentEditor_Selection_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true): seq[Selection] =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  argsJson.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true;
             inclusiveEnd: bool = false): seq[Selection] =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inclusiveEnd
    else:
      inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_edit_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc edit*(self: TextDocumentEditor; selections: seq[Selection];
           texts: seq[string]; notify: bool = true; record: bool = true;
           inclusiveEnd: bool = false): seq[Selection] =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson.add block:
    when seq[string] is JsonNode:
      texts
    else:
      texts.toJson()
  argsJson.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inclusiveEnd
    else:
      inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_edit_seq_Selection_TextDocumentEditor_seq_Selection_seq_string_bool_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_deleteLines_void_TextDocumentEditor_Slice_int_Selections_wasm(
    arg: cstring): cstring {.importc.}
proc deleteLines*(self: TextDocumentEditor; slice: Slice[int];
                  oldSelections: Selections) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Slice[int] is JsonNode:
      slice
    else:
      slice.toJson()
  argsJson.add block:
    when Selections is JsonNode:
      oldSelections
    else:
      oldSelections.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteLines_void_TextDocumentEditor_Slice_int_Selections_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrev_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrev*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectPrev_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNext_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNext*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectNext_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(arg: cstring): cstring {.
    importc.}
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectInsideCurrent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectLine_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc selectLine*(self: TextDocumentEditor; line: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectLine_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectLineCurrent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentTs_void_TextDocumentEditor_Selection_wasm(
    arg: cstring): cstring {.importc.}
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectParentTs_void_TextDocumentEditor_Selection_wasm(
      argsJsonString.cstring)


proc editor_text_printTreesitterTree_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc printTreesitterTree*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_printTreesitterTree_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_printTreesitterTreeUnderCursor_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc printTreesitterTreeUnderCursor*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_printTreesitterTreeUnderCursor_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentCurrentTs_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectParentCurrentTs_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insertText_void_TextDocumentEditor_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc insertText*(self: TextDocumentEditor; text: string; autoIndent: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  argsJson.add block:
    when bool is JsonNode:
      autoIndent
    else:
      autoIndent.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insertText_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_indent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc indent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_indent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_unindent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc unindent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_unindent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_undo_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc undo*(self: TextDocumentEditor; checkpoint: string = "word") =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      checkpoint
    else:
      checkpoint.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_undo_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_redo_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc redo*(self: TextDocumentEditor; checkpoint: string = "word") =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      checkpoint
    else:
      checkpoint.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_redo_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_addNextCheckpoint_void_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc addNextCheckpoint*(self: TextDocumentEditor; checkpoint: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      checkpoint
    else:
      checkpoint.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addNextCheckpoint_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_printUndoHistory_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc printUndoHistory*(self: TextDocumentEditor; max: int = 50) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      max
    else:
      max.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_printUndoHistory_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_copy_void_TextDocumentEditor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc copy*(self: TextDocumentEditor; register: string = "";
           inclusiveEnd: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inclusiveEnd
    else:
      inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_copy_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_paste_void_TextDocumentEditor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc paste*(self: TextDocumentEditor; register: string = "";
            inclusiveEnd: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inclusiveEnd
    else:
      inclusiveEnd.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_paste_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_scrollText_void_TextDocumentEditor_float32_wasm(arg: cstring): cstring {.
    importc.}
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_scrollText_void_TextDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_text_scrollLines_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc scrollLines*(self: TextDocumentEditor; amount: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_scrollLines_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc duplicateLastSelection*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorBelow_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addCursorBelow*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addCursorBelow_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorAbove_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addCursorAbove*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addCursorAbove_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0; includeAfter: bool = true;
                        wrap: bool = true): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0; includeAfter: bool = true;
                        wrap: bool = true): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getPrevDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevDiagnostic*(self: TextDocumentEditor; cursor: Cursor;
                        severity: int = 0; offset: int = 0;
                        includeAfter: bool = true; wrap: bool = true): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      severity
    else:
      severity.toJson()
  argsJson.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getNextDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc getNextDiagnostic*(self: TextDocumentEditor; cursor: Cursor;
                        severity: int = 0; offset: int = 0;
                        includeAfter: bool = true; wrap: bool = true): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when int is JsonNode:
      severity
    else:
      severity.toJson()
  argsJson.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextDiagnostic_Selection_TextDocumentEditor_Cursor_int_int_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_closeDiff_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc closeDiff*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_closeDiff_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getPrevChange_Selection_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevChange*(self: TextDocumentEditor; cursor: Cursor): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevChange_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getNextChange_Selection_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc getNextChange*(self: TextDocumentEditor; cursor: Cursor): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextChange_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_updateDiff_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc updateDiff*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateDiff_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc addNextFindResultToSelection*(self: TextDocumentEditor;
                                   includeAfter: bool = true; wrap: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addNextFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc addPrevFindResultToSelection*(self: TextDocumentEditor;
                                   includeAfter: bool = true; wrap: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearSelections_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearSelections*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearSelections_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true; wrap: bool = true;
                       includeAfter: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      distance
    else:
      distance.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true; wrap: bool = true;
                     includeAfter: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      distance
    else:
      distance.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true; includeAfter: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      str
    else:
      str.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      str
    else:
      str.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; wrap: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; wrap: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when bool is JsonNode:
      wrap
    else:
      wrap.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLineCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineCenter*(self: TextDocumentEditor;
                           cursor: SelectionCursor = SelectionCursor.Config;
                           all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorLineCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorCenter*(self: TextDocumentEditor;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorCenter_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_setNextScrollBehaviour_void_TextDocumentEditor_ScrollBehaviour_wasm(
    arg: cstring): cstring {.importc.}
proc setNextScrollBehaviour*(self: TextDocumentEditor;
                             scrollBehaviour: ScrollBehaviour) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when ScrollBehaviour is JsonNode:
      scrollBehaviour
    else:
      scrollBehaviour.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setNextScrollBehaviour_void_TextDocumentEditor_ScrollBehaviour_wasm(
      argsJsonString.cstring)


proc editor_text_setCursorScrollOffset_void_TextDocumentEditor_float_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc setCursorScrollOffset*(self: TextDocumentEditor; offset: float;
                            cursor: SelectionCursor = SelectionCursor.Config) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when float is JsonNode:
      offset
    else:
      offset.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setCursorScrollOffset_void_TextDocumentEditor_float_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_getContentBounds_Vec2_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getContentBounds*(self: TextDocumentEditor): Vec2 =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getContentBounds_Vec2_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_wasm(
    arg: cstring): cstring {.importc.}
proc centerCursor*(self: TextDocumentEditor;
                   cursor: SelectionCursor = SelectionCursor.Config) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_centerCursor_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc reloadTreesitter*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteLeft_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteLeft*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteLeft_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteRight_void_TextDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc deleteRight*(self: TextDocumentEditor; includeAfter: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      includeAfter
    else:
      includeAfter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteRight_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getCommandCount_int_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getCommandCount*(self: TextDocumentEditor): int =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getCommandCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
    arg: cstring): cstring {.importc.}
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
    arg: cstring): cstring {.importc.}
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      digit
    else:
      digit.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getFlag_bool_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getFlag_bool_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
    arg: cstring): cstring {.importc.}
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_wasm(
    arg: cstring): cstring {.importc.}
proc getSelectionInPair*(self: TextDocumentEditor; cursor: Cursor;
                         delimiter: char): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when char is JsonNode:
      delimiter
    else:
      delimiter.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelectionInPair_Selection_TextDocumentEditor_Cursor_char_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_wasm(
    arg: cstring): cstring {.importc.}
proc getSelectionInPairNested*(self: TextDocumentEditor; cursor: Cursor;
                               open: char; close: char): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when char is JsonNode:
      open
    else:
      open.toJson()
  argsJson.add block:
    when char is JsonNode:
      close
    else:
      close.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelectionInPairNested_Selection_TextDocumentEditor_Cursor_char_char_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_extendSelectionWithMove_Selection_TextDocumentEditor_Selection_string_int_wasm(
    arg: cstring): cstring {.importc.}
proc extendSelectionWithMove*(self: TextDocumentEditor; selection: Selection;
                              move: string; count: int = 0): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_extendSelectionWithMove_Selection_TextDocumentEditor_Selection_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
    arg: cstring): cstring {.importc.}
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_applyMove_void_TextDocumentEditor_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc applyMove*(self: TextDocumentEditor; args: JsonNode) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_applyMove_void_TextDocumentEditor_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc deleteMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inside
    else:
      inside.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inside
    else:
      inside.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_extendSelectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc extendSelectMove*(self: TextDocumentEditor; move: string;
                       inside: bool = false;
                       which: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inside
    else:
      inside.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_extendSelectMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc copyMove*(self: TextDocumentEditor; move: string; inside: bool = false;
               which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inside
    else:
      inside.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_copyMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc changeMove*(self: TextDocumentEditor; move: string; inside: bool = false;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when bool is JsonNode:
      inside
    else:
      inside.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_changeMove_void_TextDocumentEditor_string_bool_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg: cstring): cstring {.importc.}
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg: cstring): cstring {.importc.}
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQuery_void_TextDocumentEditor_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc setSearchQuery*(self: TextDocumentEditor; query: string;
                     escapeRegex: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      query
    else:
      query.toJson()
  argsJson.add block:
    when bool is JsonNode:
      escapeRegex
    else:
      escapeRegex.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSearchQuery_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQueryFromMove_Selection_TextDocumentEditor_string_int_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0; prefix: string = "";
                             suffix: string = ""): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  argsJson.add block:
    when string is JsonNode:
      prefix
    else:
      prefix.toJson()
  argsJson.add block:
    when string is JsonNode:
      suffix
    else:
      suffix.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSearchQueryFromMove_Selection_TextDocumentEditor_string_int_string_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_toggleLineComment_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc toggleLineComment*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_toggleLineComment_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoDefinition_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoDefinition*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoDefinition_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getCompletions_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc getCompletions*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_gotoSymbol_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoSymbol*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_gotoSymbol_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideCompletions_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideCompletions*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hideCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hasTabStops_bool_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hasTabStops*(self: TextDocumentEditor): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hasTabStops_bool_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_clearTabStops_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearTabStops*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearTabStops_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNextTabStop_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextTabStop*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectNextTabStop_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrevTabStop_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrevTabStop*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_selectPrevTabStop_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_showHoverFor_void_TextDocumentEditor_Cursor_wasm(arg: cstring): cstring {.
    importc.}
proc showHoverFor*(self: TextDocumentEditor; cursor: Cursor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_showHoverFor_void_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)


proc editor_text_showHoverForCurrent_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc showHoverForCurrent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_showHoverForCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideHover_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideHover*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hideHover_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_cancelDelayedHideHover_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc cancelDelayedHideHover*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_cancelDelayedHideHover_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideHoverDelayed_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideHoverDelayed*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_hideHoverDelayed_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearDiagnostics_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearDiagnostics*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearDiagnostics_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_updateDiagnosticsForCurrent_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc updateDiagnosticsForCurrent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_updateDiagnosticsForCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_showDiagnosticsForCurrent_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc showDiagnosticsForCurrent*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_showDiagnosticsForCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_isRunningSavedCommands_bool_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc isRunningSavedCommands*(self: TextDocumentEditor): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_isRunningSavedCommands_bool_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_runSavedCommands_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSavedCommands*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runSavedCommands_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc clearCurrentCommandHistory*(self: TextDocumentEditor;
                                 retainLast: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      retainLast
    else:
      retainLast.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_clearCurrentCommandHistory_void_TextDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc saveCurrentCommandHistory*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_saveCurrentCommandHistory_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_setSelection_void_TextDocumentEditor_Cursor_string_wasm(
    arg: cstring): cstring {.importc.}
proc setSelection*(self: TextDocumentEditor; cursor: Cursor; nextMode: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson.add block:
    when string is JsonNode:
      nextMode
    else:
      nextMode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSelection_void_TextDocumentEditor_Cursor_string_wasm(
      argsJsonString.cstring)


proc editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc enterChooseCursorMode*(self: TextDocumentEditor; action: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_enterChooseCursorMode_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_recordCurrentCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc recordCurrentCommand*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_recordCurrentCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runSingleClickCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSingleClickCommand*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runSingleClickCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runDoubleClickCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runDoubleClickCommand*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runDoubleClickCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runTripleClickCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runTripleClickCommand*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runTripleClickCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_runDragCommand_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runDragCommand*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_runDragCommand_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)

