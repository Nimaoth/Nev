import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_text_setMode_void_TextDocumentEditor_string_wasm(arg_8287957247: cstring): cstring {.
    importc.}
proc setMode*(self: TextDocumentEditor; mode: string) =
  var argsJson_8287957235 = newJArray()
  argsJson_8287957235.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957235.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_8287957235
  let res_8287957236 {.used.} = editor_text_setMode_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_mode_string_TextDocumentEditor_wasm(arg_8287957494: cstring): cstring {.
    importc.}
proc mode*(self: TextDocumentEditor): string =
  var argsJson_8287957489 = newJArray()
  argsJson_8287957489.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287957489
  let res_8287957490 {.used.} = editor_text_mode_string_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287957490).jsonTo(typeof(result))


proc editor_text_getContextWithMode_string_TextDocumentEditor_string_wasm(
    arg_8287957555: cstring): cstring {.importc.}
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  var argsJson_8287957550 = newJArray()
  argsJson_8287957550.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957550.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_8287957550
  let res_8287957551 {.used.} = editor_text_getContextWithMode_string_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287957551).jsonTo(typeof(result))


proc editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
    arg_8287957624: cstring): cstring {.importc.}
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  var argsJson_8287957619 = newJArray()
  argsJson_8287957619.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957619.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287957619
  let res_8287957620 {.used.} = editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_invertSelection_void_TextDocumentEditor_wasm(arg_8287957732: cstring): cstring {.
    importc.}
proc invertSelection*(self: TextDocumentEditor) =
  var argsJson_8287957727 = newJArray()
  argsJson_8287957727.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287957727
  let res_8287957728 {.used.} = editor_text_invertSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_bool_wasm(
    arg_8287957787: cstring): cstring {.importc.}
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  var argsJson_8287957782 = newJArray()
  argsJson_8287957782.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957782.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson_8287957782.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  argsJson_8287957782.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson_8287957782.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  argsJson_8287957782.add block:
    when bool is JsonNode:
      autoIndent
    else:
      autoIndent.toJson()
  let argsJsonString = $argsJson_8287957782
  let res_8287957783 {.used.} = editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287957783).jsonTo(typeof(result))


proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_wasm(
    arg_8287958210: cstring): cstring {.importc.}
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  var argsJson_8287958205 = newJArray()
  argsJson_8287958205.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287958205.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson_8287958205.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson_8287958205.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  let argsJsonString = $argsJson_8287958205
  let res_8287958206 {.used.} = editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287958206).jsonTo(typeof(result))


proc editor_text_selectPrev_void_TextDocumentEditor_wasm(arg_8287958309: cstring): cstring {.
    importc.}
proc selectPrev*(self: TextDocumentEditor) =
  var argsJson_8287958304 = newJArray()
  argsJson_8287958304.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958304
  let res_8287958305 {.used.} = editor_text_selectPrev_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNext_void_TextDocumentEditor_wasm(arg_8287958549: cstring): cstring {.
    importc.}
proc selectNext*(self: TextDocumentEditor) =
  var argsJson_8287958544 = newJArray()
  argsJson_8287958544.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958544
  let res_8287958545 {.used.} = editor_text_selectNext_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(arg_8287958766: cstring): cstring {.
    importc.}
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  var argsJson_8287958761 = newJArray()
  argsJson_8287958761.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287958761.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287958761
  let res_8287958762 {.used.} = editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(arg_8287958848: cstring): cstring {.
    importc.}
proc selectInsideCurrent*(self: TextDocumentEditor) =
  var argsJson_8287958843 = newJArray()
  argsJson_8287958843.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958843
  let res_8287958844 {.used.} = editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectLine_void_TextDocumentEditor_int_wasm(arg_8287958903: cstring): cstring {.
    importc.}
proc selectLine*(self: TextDocumentEditor; line: int) =
  var argsJson_8287958898 = newJArray()
  argsJson_8287958898.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287958898.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson_8287958898
  let res_8287958899 {.used.} = editor_text_selectLine_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(arg_8287958966: cstring): cstring {.
    importc.}
proc selectLineCurrent*(self: TextDocumentEditor) =
  var argsJson_8287958961 = newJArray()
  argsJson_8287958961.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958961
  let res_8287958962 {.used.} = editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentTs_void_TextDocumentEditor_Selection_wasm(
    arg_8287959021: cstring): cstring {.importc.}
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  var argsJson_8287959016 = newJArray()
  argsJson_8287959016.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959016.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  let argsJsonString = $argsJson_8287959016
  let res_8287959017 {.used.} = editor_text_selectParentTs_void_TextDocumentEditor_Selection_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentCurrentTs_void_TextDocumentEditor_wasm(arg_8287959099: cstring): cstring {.
    importc.}
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  var argsJson_8287959094 = newJArray()
  argsJson_8287959094.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959094
  let res_8287959095 {.used.} = editor_text_selectParentCurrentTs_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insertText_void_TextDocumentEditor_string_wasm(arg_8287959159: cstring): cstring {.
    importc.}
proc insertText*(self: TextDocumentEditor; text: string) =
  var argsJson_8287959154 = newJArray()
  argsJson_8287959154.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959154.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  let argsJsonString = $argsJson_8287959154
  let res_8287959155 {.used.} = editor_text_insertText_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_undo_void_TextDocumentEditor_wasm(arg_8287959231: cstring): cstring {.
    importc.}
proc undo*(self: TextDocumentEditor) =
  var argsJson_8287959226 = newJArray()
  argsJson_8287959226.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959226
  let res_8287959227 {.used.} = editor_text_undo_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_redo_void_TextDocumentEditor_wasm(arg_8287959338: cstring): cstring {.
    importc.}
proc redo*(self: TextDocumentEditor) =
  var argsJson_8287959333 = newJArray()
  argsJson_8287959333.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959333
  let res_8287959334 {.used.} = editor_text_redo_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_scrollText_void_TextDocumentEditor_float32_wasm(arg_8287959423: cstring): cstring {.
    importc.}
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  var argsJson_8287959418 = newJArray()
  argsJson_8287959418.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959418.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_8287959418
  let res_8287959419 {.used.} = editor_text_scrollText_void_TextDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
    arg_8287959548: cstring): cstring {.importc.}
proc duplicateLastSelection*(self: TextDocumentEditor) =
  var argsJson_8287959543 = newJArray()
  argsJson_8287959543.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959543
  let res_8287959544 {.used.} = editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorBelow_void_TextDocumentEditor_wasm(arg_8287959645: cstring): cstring {.
    importc.}
proc addCursorBelow*(self: TextDocumentEditor) =
  var argsJson_8287959640 = newJArray()
  argsJson_8287959640.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959640
  let res_8287959641 {.used.} = editor_text_addCursorBelow_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorAbove_void_TextDocumentEditor_wasm(arg_8287959716: cstring): cstring {.
    importc.}
proc addCursorAbove*(self: TextDocumentEditor) =
  var argsJson_8287959711 = newJArray()
  argsJson_8287959711.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959711
  let res_8287959712 {.used.} = editor_text_addCursorAbove_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
    arg_8287959783: cstring): cstring {.importc.}
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  var argsJson_8287959778 = newJArray()
  argsJson_8287959778.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959778.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287959778.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  let argsJsonString = $argsJson_8287959778
  let res_8287959779 {.used.} = editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287959779).jsonTo(typeof(result))


proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
    arg_8287960137: cstring): cstring {.importc.}
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  var argsJson_8287960132 = newJArray()
  argsJson_8287960132.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287960132.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287960132.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  let argsJsonString = $argsJson_8287960132
  let res_8287960133 {.used.} = editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287960133).jsonTo(typeof(result))


proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_wasm(
    arg_8287960386: cstring): cstring {.importc.}
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson_8287960381 = newJArray()
  argsJson_8287960381.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960381
  let res_8287960382 {.used.} = editor_text_addNextFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_wasm(
    arg_8287960449: cstring): cstring {.importc.}
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson_8287960444 = newJArray()
  argsJson_8287960444.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960444
  let res_8287960445 {.used.} = editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
    arg_8287960512: cstring): cstring {.importc.}
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson_8287960507 = newJArray()
  argsJson_8287960507.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960507
  let res_8287960508 {.used.} = editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearSelections_void_TextDocumentEditor_wasm(arg_8287960924: cstring): cstring {.
    importc.}
proc clearSelections*(self: TextDocumentEditor) =
  var argsJson_8287960919 = newJArray()
  argsJson_8287960919.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960919
  let res_8287960920 {.used.} = editor_text_clearSelections_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
    arg_8287960985: cstring): cstring {.importc.}
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson_8287960980 = newJArray()
  argsJson_8287960980.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287960980.add block:
    when int is JsonNode:
      distance
    else:
      distance.toJson()
  argsJson_8287960980.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287960980.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287960980
  let res_8287960981 {.used.} = editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
    arg_8287961127: cstring): cstring {.importc.}
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  var argsJson_8287961122 = newJArray()
  argsJson_8287961122.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961122.add block:
    when int is JsonNode:
      distance
    else:
      distance.toJson()
  argsJson_8287961122.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961122.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961122
  let res_8287961123 {.used.} = editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961206: cstring): cstring {.importc.}
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  var argsJson_8287961201 = newJArray()
  argsJson_8287961201.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961201.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961201.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961201
  let res_8287961202 {.used.} = editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961279: cstring): cstring {.importc.}
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  var argsJson_8287961274 = newJArray()
  argsJson_8287961274.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961274.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961274.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961274
  let res_8287961275 {.used.} = editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287961352: cstring): cstring {.importc.}
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  var argsJson_8287961347 = newJArray()
  argsJson_8287961347.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961347.add block:
    when string is JsonNode:
      str
    else:
      str.toJson()
  argsJson_8287961347.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961347.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961347
  let res_8287961348 {.used.} = editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287961463: cstring): cstring {.importc.}
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson_8287961458 = newJArray()
  argsJson_8287961458.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961458.add block:
    when string is JsonNode:
      str
    else:
      str.toJson()
  argsJson_8287961458.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961458.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961458
  let res_8287961459 {.used.} = editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961574: cstring): cstring {.importc.}
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  var argsJson_8287961569 = newJArray()
  argsJson_8287961569.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961569.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961569.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961569
  let res_8287961570 {.used.} = editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961645: cstring): cstring {.importc.}
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  var argsJson_8287961640 = newJArray()
  argsJson_8287961640.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961640.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961640.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961640
  let res_8287961641 {.used.} = editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
    arg_8287961716: cstring): cstring {.importc.}
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  var argsJson_8287961711 = newJArray()
  argsJson_8287961711.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961711.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287961711
  let res_8287961712 {.used.} = editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(arg_8287961779: cstring): cstring {.
    importc.}
proc reloadTreesitter*(self: TextDocumentEditor) =
  var argsJson_8287961774 = newJArray()
  argsJson_8287961774.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287961774
  let res_8287961775 {.used.} = editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteLeft_void_TextDocumentEditor_wasm(arg_8287961902: cstring): cstring {.
    importc.}
proc deleteLeft*(self: TextDocumentEditor) =
  var argsJson_8287961897 = newJArray()
  argsJson_8287961897.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287961897
  let res_8287961898 {.used.} = editor_text_deleteLeft_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteRight_void_TextDocumentEditor_wasm(arg_8287961971: cstring): cstring {.
    importc.}
proc deleteRight*(self: TextDocumentEditor) =
  var argsJson_8287961966 = newJArray()
  argsJson_8287961966.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287961966
  let res_8287961967 {.used.} = editor_text_deleteRight_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getCommandCount_int_TextDocumentEditor_wasm(arg_8287962040: cstring): cstring {.
    importc.}
proc getCommandCount*(self: TextDocumentEditor): int =
  var argsJson_8287962035 = newJArray()
  argsJson_8287962035.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287962035
  let res_8287962036 {.used.} = editor_text_getCommandCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962036).jsonTo(typeof(result))


proc editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(arg_8287962101: cstring): cstring {.
    importc.}
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  var argsJson_8287962096 = newJArray()
  argsJson_8287962096.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962096.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287962096
  let res_8287962097 {.used.} = editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
    arg_8287962164: cstring): cstring {.importc.}
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  var argsJson_8287962159 = newJArray()
  argsJson_8287962159.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962159.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287962159
  let res_8287962160 {.used.} = editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
    arg_8287962227: cstring): cstring {.importc.}
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  var argsJson_8287962222 = newJArray()
  argsJson_8287962222.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962222.add block:
    when int is JsonNode:
      digit
    else:
      digit.toJson()
  let argsJsonString = $argsJson_8287962222
  let res_8287962223 {.used.} = editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(arg_8287962290: cstring): cstring {.
    importc.}
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  var argsJson_8287962285 = newJArray()
  argsJson_8287962285.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962285.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  argsJson_8287962285.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_8287962285
  let res_8287962286 {.used.} = editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getFlag_bool_TextDocumentEditor_string_wasm(arg_8287962361: cstring): cstring {.
    importc.}
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  var argsJson_8287962356 = newJArray()
  argsJson_8287962356.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962356.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson_8287962356
  let res_8287962357 {.used.} = editor_text_getFlag_bool_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962357).jsonTo(typeof(result))


proc editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_wasm(
    arg_8287962430: cstring): cstring {.importc.}
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  var argsJson_8287962425 = newJArray()
  argsJson_8287962425.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962425.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_8287962425.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson_8287962425
  let res_8287962426 {.used.} = editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962426).jsonTo(typeof(result))


proc editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
    arg_8287962509: cstring): cstring {.importc.}
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  var argsJson_8287962504 = newJArray()
  argsJson_8287962504.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962504.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287962504
  let res_8287962505 {.used.} = editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962505).jsonTo(typeof(result))


proc editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
    arg_8287962607: cstring): cstring {.importc.}
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  var argsJson_8287962602 = newJArray()
  argsJson_8287962602.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962602.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287962602.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287962602.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287962602
  let res_8287962603 {.used.} = editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962603).jsonTo(typeof(result))


proc editor_text_setMove_void_TextDocumentEditor_JsonNode_wasm(arg_8287962852: cstring): cstring {.
    importc.}
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  var argsJson_8287962847 = newJArray()
  argsJson_8287962847.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962847.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson_8287962847
  let res_8287962848 {.used.} = editor_text_setMove_void_TextDocumentEditor_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_text_deleteMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287963112: cstring): cstring {.importc.}
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson_8287963107 = newJArray()
  argsJson_8287963107.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963107.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963107.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963107.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287963107
  let res_8287963108 {.used.} = editor_text_deleteMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_selectMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287963247: cstring): cstring {.importc.}
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson_8287963242 = newJArray()
  argsJson_8287963242.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963242.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963242.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963242.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287963242
  let res_8287963243 {.used.} = editor_text_selectMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_changeMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287963430: cstring): cstring {.importc.}
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson_8287963425 = newJArray()
  argsJson_8287963425.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963425.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963425.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963425.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287963425
  let res_8287963426 {.used.} = editor_text_changeMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg_8287963565: cstring): cstring {.importc.}
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  var argsJson_8287963560 = newJArray()
  argsJson_8287963560.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963560.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963560.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963560.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson_8287963560.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287963560
  let res_8287963561 {.used.} = editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg_8287963716: cstring): cstring {.importc.}
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  var argsJson_8287963711 = newJArray()
  argsJson_8287963711.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963711.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963711.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963711.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson_8287963711.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287963711
  let res_8287963712 {.used.} = editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQuery_void_TextDocumentEditor_string_wasm(arg_8287963867: cstring): cstring {.
    importc.}
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  var argsJson_8287963862 = newJArray()
  argsJson_8287963862.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963862.add block:
    when string is JsonNode:
      query
    else:
      query.toJson()
  let argsJsonString = $argsJson_8287963862
  let res_8287963863 {.used.} = editor_text_setSearchQuery_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_wasm(
    arg_8287963952: cstring): cstring {.importc.}
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  var argsJson_8287963947 = newJArray()
  argsJson_8287963947.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963947.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963947.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287963947
  let res_8287963948 {.used.} = editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_wasm(
      argsJsonString.cstring)


proc editor_text_gotoDefinition_void_TextDocumentEditor_wasm(arg_8287965187: cstring): cstring {.
    importc.}
proc gotoDefinition*(self: TextDocumentEditor) =
  var argsJson_8287965182 = newJArray()
  argsJson_8287965182.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965182
  let res_8287965183 {.used.} = editor_text_gotoDefinition_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getCompletions_void_TextDocumentEditor_wasm(arg_8287965475: cstring): cstring {.
    importc.}
proc getCompletions*(self: TextDocumentEditor) =
  var argsJson_8287965470 = newJArray()
  argsJson_8287965470.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965470
  let res_8287965471 {.used.} = editor_text_getCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideCompletions_void_TextDocumentEditor_wasm(arg_8287965616: cstring): cstring {.
    importc.}
proc hideCompletions*(self: TextDocumentEditor) =
  var argsJson_8287965611 = newJArray()
  argsJson_8287965611.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965611
  let res_8287965612 {.used.} = editor_text_hideCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(arg_8287965671: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: TextDocumentEditor) =
  var argsJson_8287965666 = newJArray()
  argsJson_8287965666.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965666
  let res_8287965667 {.used.} = editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(arg_8287965743: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: TextDocumentEditor) =
  var argsJson_8287965738 = newJArray()
  argsJson_8287965738.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965738
  let res_8287965739 {.used.} = editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
    arg_8287965815: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: TextDocumentEditor) =
  var argsJson_8287965810 = newJArray()
  argsJson_8287965810.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965810
  let res_8287965811 {.used.} = editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)

