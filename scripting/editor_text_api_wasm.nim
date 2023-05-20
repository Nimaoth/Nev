import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_text_setMode_void_TextDocumentEditor_string_wasm(arg_8287957261: cstring): cstring {.
    importc.}
proc setMode*(self: TextDocumentEditor; mode: string) =
  var argsJson_8287957249 = newJArray()
  argsJson_8287957249.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957249.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_8287957249
  let res_8287957250 {.used.} = editor_text_setMode_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_mode_string_TextDocumentEditor_wasm(arg_8287957493: cstring): cstring {.
    importc.}
proc mode*(self: TextDocumentEditor): string =
  var argsJson_8287957488 = newJArray()
  argsJson_8287957488.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287957488
  let res_8287957489 {.used.} = editor_text_mode_string_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287957489).jsonTo(typeof(result))


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
    arg_8287957625: cstring): cstring {.importc.}
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  var argsJson_8287957620 = newJArray()
  argsJson_8287957620.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957620.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287957620
  let res_8287957621 {.used.} = editor_text_updateTargetColumn_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_invertSelection_void_TextDocumentEditor_wasm(arg_8287957734: cstring): cstring {.
    importc.}
proc invertSelection*(self: TextDocumentEditor) =
  var argsJson_8287957729 = newJArray()
  argsJson_8287957729.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287957729
  let res_8287957730 {.used.} = editor_text_invertSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_bool_wasm(
    arg_8287957790: cstring): cstring {.importc.}
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  var argsJson_8287957785 = newJArray()
  argsJson_8287957785.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287957785.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson_8287957785.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  argsJson_8287957785.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson_8287957785.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  argsJson_8287957785.add block:
    when bool is JsonNode:
      autoIndent
    else:
      autoIndent.toJson()
  let argsJsonString = $argsJson_8287957785
  let res_8287957786 {.used.} = editor_text_insert_seq_Selection_TextDocumentEditor_seq_Selection_string_bool_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287957786).jsonTo(typeof(result))


proc editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_wasm(
    arg_8287958214: cstring): cstring {.importc.}
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  var argsJson_8287958209 = newJArray()
  argsJson_8287958209.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287958209.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  argsJson_8287958209.add block:
    when bool is JsonNode:
      notify
    else:
      notify.toJson()
  argsJson_8287958209.add block:
    when bool is JsonNode:
      record
    else:
      record.toJson()
  let argsJsonString = $argsJson_8287958209
  let res_8287958210 {.used.} = editor_text_delete_seq_Selection_TextDocumentEditor_seq_Selection_bool_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287958210).jsonTo(typeof(result))


proc editor_text_selectPrev_void_TextDocumentEditor_wasm(arg_8287958314: cstring): cstring {.
    importc.}
proc selectPrev*(self: TextDocumentEditor) =
  var argsJson_8287958309 = newJArray()
  argsJson_8287958309.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958309
  let res_8287958310 {.used.} = editor_text_selectPrev_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNext_void_TextDocumentEditor_wasm(arg_8287958555: cstring): cstring {.
    importc.}
proc selectNext*(self: TextDocumentEditor) =
  var argsJson_8287958550 = newJArray()
  argsJson_8287958550.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958550
  let res_8287958551 {.used.} = editor_text_selectNext_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(arg_8287958773: cstring): cstring {.
    importc.}
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  var argsJson_8287958768 = newJArray()
  argsJson_8287958768.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287958768.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287958768
  let res_8287958769 {.used.} = editor_text_selectInside_void_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)


proc editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(arg_8287958856: cstring): cstring {.
    importc.}
proc selectInsideCurrent*(self: TextDocumentEditor) =
  var argsJson_8287958851 = newJArray()
  argsJson_8287958851.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958851
  let res_8287958852 {.used.} = editor_text_selectInsideCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectLine_void_TextDocumentEditor_int_wasm(arg_8287958912: cstring): cstring {.
    importc.}
proc selectLine*(self: TextDocumentEditor; line: int) =
  var argsJson_8287958907 = newJArray()
  argsJson_8287958907.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287958907.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson_8287958907
  let res_8287958908 {.used.} = editor_text_selectLine_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(arg_8287958976: cstring): cstring {.
    importc.}
proc selectLineCurrent*(self: TextDocumentEditor) =
  var argsJson_8287958971 = newJArray()
  argsJson_8287958971.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287958971
  let res_8287958972 {.used.} = editor_text_selectLineCurrent_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentTs_void_TextDocumentEditor_Selection_wasm(
    arg_8287959032: cstring): cstring {.importc.}
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  var argsJson_8287959027 = newJArray()
  argsJson_8287959027.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959027.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  let argsJsonString = $argsJson_8287959027
  let res_8287959028 {.used.} = editor_text_selectParentTs_void_TextDocumentEditor_Selection_wasm(
      argsJsonString.cstring)


proc editor_text_selectParentCurrentTs_void_TextDocumentEditor_wasm(arg_8287959111: cstring): cstring {.
    importc.}
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  var argsJson_8287959106 = newJArray()
  argsJson_8287959106.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959106
  let res_8287959107 {.used.} = editor_text_selectParentCurrentTs_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_insertText_void_TextDocumentEditor_string_wasm(arg_8287959172: cstring): cstring {.
    importc.}
proc insertText*(self: TextDocumentEditor; text: string) =
  var argsJson_8287959167 = newJArray()
  argsJson_8287959167.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959167.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  let argsJsonString = $argsJson_8287959167
  let res_8287959168 {.used.} = editor_text_insertText_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_undo_void_TextDocumentEditor_wasm(arg_8287959245: cstring): cstring {.
    importc.}
proc undo*(self: TextDocumentEditor) =
  var argsJson_8287959240 = newJArray()
  argsJson_8287959240.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959240
  let res_8287959241 {.used.} = editor_text_undo_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_redo_void_TextDocumentEditor_wasm(arg_8287959353: cstring): cstring {.
    importc.}
proc redo*(self: TextDocumentEditor) =
  var argsJson_8287959348 = newJArray()
  argsJson_8287959348.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959348
  let res_8287959349 {.used.} = editor_text_redo_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_scrollText_void_TextDocumentEditor_float32_wasm(arg_8287959439: cstring): cstring {.
    importc.}
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  var argsJson_8287959434 = newJArray()
  argsJson_8287959434.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959434.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_8287959434
  let res_8287959435 {.used.} = editor_text_scrollText_void_TextDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
    arg_8287959565: cstring): cstring {.importc.}
proc duplicateLastSelection*(self: TextDocumentEditor) =
  var argsJson_8287959560 = newJArray()
  argsJson_8287959560.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959560
  let res_8287959561 {.used.} = editor_text_duplicateLastSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorBelow_void_TextDocumentEditor_wasm(arg_8287959663: cstring): cstring {.
    importc.}
proc addCursorBelow*(self: TextDocumentEditor) =
  var argsJson_8287959658 = newJArray()
  argsJson_8287959658.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959658
  let res_8287959659 {.used.} = editor_text_addCursorBelow_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addCursorAbove_void_TextDocumentEditor_wasm(arg_8287959735: cstring): cstring {.
    importc.}
proc addCursorAbove*(self: TextDocumentEditor) =
  var argsJson_8287959730 = newJArray()
  argsJson_8287959730.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287959730
  let res_8287959731 {.used.} = editor_text_addCursorAbove_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
    arg_8287959803: cstring): cstring {.importc.}
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  var argsJson_8287959798 = newJArray()
  argsJson_8287959798.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287959798.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287959798.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  let argsJsonString = $argsJson_8287959798
  let res_8287959799 {.used.} = editor_text_getPrevFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287959799).jsonTo(typeof(result))


proc editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
    arg_8287960158: cstring): cstring {.importc.}
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  var argsJson_8287960153 = newJArray()
  argsJson_8287960153.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287960153.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287960153.add block:
    when int is JsonNode:
      offset
    else:
      offset.toJson()
  let argsJsonString = $argsJson_8287960153
  let res_8287960154 {.used.} = editor_text_getNextFindResult_Selection_TextDocumentEditor_Cursor_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287960154).jsonTo(typeof(result))


proc editor_text_addNextFindResultToSelection_void_TextDocumentEditor_wasm(
    arg_8287960408: cstring): cstring {.importc.}
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson_8287960403 = newJArray()
  argsJson_8287960403.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960403
  let res_8287960404 {.used.} = editor_text_addNextFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_wasm(
    arg_8287960472: cstring): cstring {.importc.}
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson_8287960467 = newJArray()
  argsJson_8287960467.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960467
  let res_8287960468 {.used.} = editor_text_addPrevFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
    arg_8287960536: cstring): cstring {.importc.}
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  var argsJson_8287960531 = newJArray()
  argsJson_8287960531.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960531
  let res_8287960532 {.used.} = editor_text_setAllFindResultToSelection_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_clearSelections_void_TextDocumentEditor_wasm(arg_8287960949: cstring): cstring {.
    importc.}
proc clearSelections*(self: TextDocumentEditor) =
  var argsJson_8287960944 = newJArray()
  argsJson_8287960944.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287960944
  let res_8287960945 {.used.} = editor_text_clearSelections_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
    arg_8287961011: cstring): cstring {.importc.}
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson_8287961006 = newJArray()
  argsJson_8287961006.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961006.add block:
    when int is JsonNode:
      distance
    else:
      distance.toJson()
  argsJson_8287961006.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961006.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961006
  let res_8287961007 {.used.} = editor_text_moveCursorColumn_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
    arg_8287961154: cstring): cstring {.importc.}
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  var argsJson_8287961149 = newJArray()
  argsJson_8287961149.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961149.add block:
    when int is JsonNode:
      distance
    else:
      distance.toJson()
  argsJson_8287961149.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961149.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961149
  let res_8287961150 {.used.} = editor_text_moveCursorLine_void_TextDocumentEditor_int_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961234: cstring): cstring {.importc.}
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  var argsJson_8287961229 = newJArray()
  argsJson_8287961229.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961229.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961229.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961229
  let res_8287961230 {.used.} = editor_text_moveCursorHome_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961308: cstring): cstring {.importc.}
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  var argsJson_8287961303 = newJArray()
  argsJson_8287961303.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961303.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961303.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961303
  let res_8287961304 {.used.} = editor_text_moveCursorEnd_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287961382: cstring): cstring {.importc.}
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  var argsJson_8287961377 = newJArray()
  argsJson_8287961377.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961377.add block:
    when string is JsonNode:
      str
    else:
      str.toJson()
  argsJson_8287961377.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961377.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961377
  let res_8287961378 {.used.} = editor_text_moveCursorTo_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287961494: cstring): cstring {.importc.}
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  var argsJson_8287961489 = newJArray()
  argsJson_8287961489.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961489.add block:
    when string is JsonNode:
      str
    else:
      str.toJson()
  argsJson_8287961489.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961489.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961489
  let res_8287961490 {.used.} = editor_text_moveCursorBefore_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961606: cstring): cstring {.importc.}
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  var argsJson_8287961601 = newJArray()
  argsJson_8287961601.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961601.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961601.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961601
  let res_8287961602 {.used.} = editor_text_moveCursorNextFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
    arg_8287961678: cstring): cstring {.importc.}
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  var argsJson_8287961673 = newJArray()
  argsJson_8287961673.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961673.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287961673.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287961673
  let res_8287961674 {.used.} = editor_text_moveCursorPrevFindResult_void_TextDocumentEditor_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
    arg_8287961750: cstring): cstring {.importc.}
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  var argsJson_8287961745 = newJArray()
  argsJson_8287961745.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287961745.add block:
    when SelectionCursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287961745
  let res_8287961746 {.used.} = editor_text_scrollToCursor_void_TextDocumentEditor_SelectionCursor_wasm(
      argsJsonString.cstring)


proc editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(arg_8287961814: cstring): cstring {.
    importc.}
proc reloadTreesitter*(self: TextDocumentEditor) =
  var argsJson_8287961809 = newJArray()
  argsJson_8287961809.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287961809
  let res_8287961810 {.used.} = editor_text_reloadTreesitter_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteLeft_void_TextDocumentEditor_wasm(arg_8287961938: cstring): cstring {.
    importc.}
proc deleteLeft*(self: TextDocumentEditor) =
  var argsJson_8287961933 = newJArray()
  argsJson_8287961933.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287961933
  let res_8287961934 {.used.} = editor_text_deleteLeft_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_deleteRight_void_TextDocumentEditor_wasm(arg_8287962008: cstring): cstring {.
    importc.}
proc deleteRight*(self: TextDocumentEditor) =
  var argsJson_8287962003 = newJArray()
  argsJson_8287962003.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287962003
  let res_8287962004 {.used.} = editor_text_deleteRight_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getCommandCount_int_TextDocumentEditor_wasm(arg_8287962078: cstring): cstring {.
    importc.}
proc getCommandCount*(self: TextDocumentEditor): int =
  var argsJson_8287962073 = newJArray()
  argsJson_8287962073.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287962073
  let res_8287962074 {.used.} = editor_text_getCommandCount_int_TextDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962074).jsonTo(typeof(result))


proc editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(arg_8287962140: cstring): cstring {.
    importc.}
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  var argsJson_8287962135 = newJArray()
  argsJson_8287962135.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962135.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287962135
  let res_8287962136 {.used.} = editor_text_setCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
    arg_8287962204: cstring): cstring {.importc.}
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  var argsJson_8287962199 = newJArray()
  argsJson_8287962199.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962199.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287962199
  let res_8287962200 {.used.} = editor_text_setCommandCountRestore_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
    arg_8287962268: cstring): cstring {.importc.}
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  var argsJson_8287962263 = newJArray()
  argsJson_8287962263.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962263.add block:
    when int is JsonNode:
      digit
    else:
      digit.toJson()
  let argsJsonString = $argsJson_8287962263
  let res_8287962264 {.used.} = editor_text_updateCommandCount_void_TextDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(arg_8287962332: cstring): cstring {.
    importc.}
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  var argsJson_8287962327 = newJArray()
  argsJson_8287962327.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962327.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  argsJson_8287962327.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson_8287962327
  let res_8287962328 {.used.} = editor_text_setFlag_void_TextDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_text_getFlag_bool_TextDocumentEditor_string_wasm(arg_8287962404: cstring): cstring {.
    importc.}
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  var argsJson_8287962399 = newJArray()
  argsJson_8287962399.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962399.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson_8287962399
  let res_8287962400 {.used.} = editor_text_getFlag_bool_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962400).jsonTo(typeof(result))


proc editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_wasm(
    arg_8287962474: cstring): cstring {.importc.}
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  var argsJson_8287962469 = newJArray()
  argsJson_8287962469.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962469.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson_8287962469.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson_8287962469
  let res_8287962470 {.used.} = editor_text_runAction_bool_TextDocumentEditor_string_JsonNode_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962470).jsonTo(typeof(result))


proc editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
    arg_8287962554: cstring): cstring {.importc.}
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  var argsJson_8287962549 = newJArray()
  argsJson_8287962549.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962549.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  let argsJsonString = $argsJson_8287962549
  let res_8287962550 {.used.} = editor_text_findWordBoundary_Selection_TextDocumentEditor_Cursor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962550).jsonTo(typeof(result))


proc editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
    arg_8287962653: cstring): cstring {.importc.}
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  var argsJson_8287962648 = newJArray()
  argsJson_8287962648.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962648.add block:
    when Cursor is JsonNode:
      cursor
    else:
      cursor.toJson()
  argsJson_8287962648.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287962648.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287962648
  let res_8287962649 {.used.} = editor_text_getSelectionForMove_Selection_TextDocumentEditor_Cursor_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8287962649).jsonTo(typeof(result))


proc editor_text_setMove_void_TextDocumentEditor_JsonNode_wasm(arg_8287962899: cstring): cstring {.
    importc.}
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  var argsJson_8287962894 = newJArray()
  argsJson_8287962894.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287962894.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson_8287962894
  let res_8287962895 {.used.} = editor_text_setMove_void_TextDocumentEditor_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_text_deleteMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287963160: cstring): cstring {.importc.}
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson_8287963155 = newJArray()
  argsJson_8287963155.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963155.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963155.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963155.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287963155
  let res_8287963156 {.used.} = editor_text_deleteMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_selectMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287963296: cstring): cstring {.importc.}
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson_8287963291 = newJArray()
  argsJson_8287963291.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963291.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963291.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963291.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287963291
  let res_8287963292 {.used.} = editor_text_selectMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_changeMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
    arg_8287963480: cstring): cstring {.importc.}
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  var argsJson_8287963475 = newJArray()
  argsJson_8287963475.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963475.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963475.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963475.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson_8287963475
  let res_8287963476 {.used.} = editor_text_changeMove_void_TextDocumentEditor_string_SelectionCursor_bool_wasm(
      argsJsonString.cstring)


proc editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg_8287963616: cstring): cstring {.importc.}
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  var argsJson_8287963611 = newJArray()
  argsJson_8287963611.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963611.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963611.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963611.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson_8287963611.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287963611
  let res_8287963612 {.used.} = editor_text_moveLast_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
    arg_8287963768: cstring): cstring {.importc.}
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  var argsJson_8287963763 = newJArray()
  argsJson_8287963763.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963763.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287963763.add block:
    when SelectionCursor is JsonNode:
      which
    else:
      which.toJson()
  argsJson_8287963763.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  argsJson_8287963763.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287963763
  let res_8287963764 {.used.} = editor_text_moveFirst_void_TextDocumentEditor_string_SelectionCursor_bool_int_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQuery_void_TextDocumentEditor_string_wasm(arg_8287963920: cstring): cstring {.
    importc.}
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  var argsJson_8287963915 = newJArray()
  argsJson_8287963915.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287963915.add block:
    when string is JsonNode:
      query
    else:
      query.toJson()
  let argsJsonString = $argsJson_8287963915
  let res_8287963916 {.used.} = editor_text_setSearchQuery_void_TextDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_wasm(
    arg_8287964006: cstring): cstring {.importc.}
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  var argsJson_8287964001 = newJArray()
  argsJson_8287964001.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8287964001.add block:
    when string is JsonNode:
      move
    else:
      move.toJson()
  argsJson_8287964001.add block:
    when int is JsonNode:
      count
    else:
      count.toJson()
  let argsJsonString = $argsJson_8287964001
  let res_8287964002 {.used.} = editor_text_setSearchQueryFromMove_void_TextDocumentEditor_string_int_wasm(
      argsJsonString.cstring)


proc editor_text_gotoDefinition_void_TextDocumentEditor_wasm(arg_8287965242: cstring): cstring {.
    importc.}
proc gotoDefinition*(self: TextDocumentEditor) =
  var argsJson_8287965237 = newJArray()
  argsJson_8287965237.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965237
  let res_8287965238 {.used.} = editor_text_gotoDefinition_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_getCompletions_void_TextDocumentEditor_wasm(arg_8287965531: cstring): cstring {.
    importc.}
proc getCompletions*(self: TextDocumentEditor) =
  var argsJson_8287965526 = newJArray()
  argsJson_8287965526.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965526
  let res_8287965527 {.used.} = editor_text_getCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_hideCompletions_void_TextDocumentEditor_wasm(arg_8287965673: cstring): cstring {.
    importc.}
proc hideCompletions*(self: TextDocumentEditor) =
  var argsJson_8287965668 = newJArray()
  argsJson_8287965668.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965668
  let res_8287965669 {.used.} = editor_text_hideCompletions_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(arg_8287965729: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: TextDocumentEditor) =
  var argsJson_8287965724 = newJArray()
  argsJson_8287965724.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965724
  let res_8287965725 {.used.} = editor_text_selectPrevCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(arg_8287965802: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: TextDocumentEditor) =
  var argsJson_8287965797 = newJArray()
  argsJson_8287965797.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965797
  let res_8287965798 {.used.} = editor_text_selectNextCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
    arg_8287965875: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: TextDocumentEditor) =
  var argsJson_8287965870 = newJArray()
  argsJson_8287965870.add block:
    when TextDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8287965870
  let res_8287965871 {.used.} = editor_text_applySelectedCompletion_void_TextDocumentEditor_wasm(
      argsJsonString.cstring)

