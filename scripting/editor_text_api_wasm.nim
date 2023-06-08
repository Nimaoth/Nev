import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


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
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
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


proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
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
  let res {.used.} = editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


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


proc editor_text_insertText_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc insertText*(self: TextDocumentEditor; text: string) =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_insertText_void_TextDocumentEditor_string_wasm(
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


proc editor_text_undo_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc undo*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_undo_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_redo_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc redo*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_redo_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_copy_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc copy*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_copy_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_paste_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc paste*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_paste_void_TextDocumentEditor_wasm(
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


proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
    arg: cstring): cstring {.importc.}
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
    arg: cstring): cstring {.importc.}
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addNextFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_wasm(
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


proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
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


proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorEnd*(self: TextDocumentEditor;
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
  let res {.used.} = editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_wasm(
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


proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
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
  let res {.used.} = editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
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
  let res {.used.} = editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
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


proc editor_text_deleteRight_void_TextDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteRight*(self: TextDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_deleteRight_void_TextDocumentEditor_wasm(
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


proc editor_text_setMove_void_TextDocumentEditor_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
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
  let res {.used.} = editor_text_setMove_void_TextDocumentEditor_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_text_deleteMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc deleteMove*(self: TextDocumentEditor; move: string;
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
  let res {.used.} = editor_text_deleteMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_selectMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectMove*(self: TextDocumentEditor; move: string;
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
  let res {.used.} = editor_text_selectMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_changeMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc changeMove*(self: TextDocumentEditor; move: string;
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
  let res {.used.} = editor_text_changeMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
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


proc editor_text_setSearchQuery_void_TextDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSearchQuery_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_wasm(
    arg: cstring): cstring {.importc.}
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
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
  let argsJsonString = $argsJson
  let res {.used.} = editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_wasm(
      argsJsonString.cstring)


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

