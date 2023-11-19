import std/[json]
import scripting_api, myjsonutils

## This file is auto generated, don't modify.


proc editor_model_scrollPixels_void_ModelDocumentEditor_float32_wasm(
    arg: cstring): cstring {.importc.}
proc scrollPixels*(self: ModelDocumentEditor; amount: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_scrollPixels_void_ModelDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_model_scrollLines_void_ModelDocumentEditor_float32_wasm(arg: cstring): cstring {.
    importc.}
proc scrollLines*(self: ModelDocumentEditor; lines: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when float32 is JsonNode:
      lines
    else:
      lines.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_scrollLines_void_ModelDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_model_setMode_void_ModelDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setMode*(self: ModelDocumentEditor; mode: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_setMode_void_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_model_mode_string_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc mode*(self: ModelDocumentEditor): string =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_mode_string_ModelDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_model_isThickCursor_bool_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc isThickCursor*(self: ModelDocumentEditor): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_isThickCursor_bool_ModelDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_deleteLeft_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteLeft*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_deleteLeft_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_deleteRight_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteRight*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_deleteRight_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_replaceLeft_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc replaceLeft*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_replaceLeft_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_replaceRight_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc replaceRight*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_replaceRight_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_createNewNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc createNewNode*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_createNewNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      input
    else:
      input.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_model_undo_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc undo*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_undo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_redo_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc redo*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_redo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_showCompletions_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc showCompletions*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_showCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_hideCompletions_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideCompletions*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_hideCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc selectNextCompletion*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_printSelectionInfo_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc printSelectionInfo*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_printSelectionInfo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_clearModelCache_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearModelCache*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_clearModelCache_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_runSelectedFunction_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSelectedFunction*(self: ModelDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_runSelectedFunction_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)

