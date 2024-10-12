import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editor_model_scrollPixels_void_ModelDocumentEditor_float32_wasm(
    arg: cstring): cstring {.importc.}
proc scrollPixels*(self: ModelDocumentEditor; amount: float32) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_scrollPixels_void_ModelDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_model_scrollLines_void_ModelDocumentEditor_float32_wasm(arg: cstring): cstring {.
    importc.}
proc scrollLines*(self: ModelDocumentEditor; lines: float32) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add lines.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_scrollLines_void_ModelDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_model_setMode_void_ModelDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setMode*(self: ModelDocumentEditor; mode: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_setMode_void_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_model_mode_string_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc mode*(self: ModelDocumentEditor): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_mode_string_ModelDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_model_isThickCursor_bool_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc isThickCursor*(self: ModelDocumentEditor): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_isThickCursor_bool_ModelDocumentEditor_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_model_gotoDefinition_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc gotoDefinition*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoDefinition_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_gotoPrevReference_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoPrevReference*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoPrevReference_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_gotoNextReference_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoNextReference*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoNextReference_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_gotoPrevInvalidNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoPrevInvalidNode*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoPrevInvalidNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_gotoNextInvalidNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc gotoNextInvalidNode*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoNextInvalidNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_gotoPrevNodeOfClass_void_ModelDocumentEditor_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc gotoPrevNodeOfClass*(self: ModelDocumentEditor; className: string;
                          select: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add className.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoPrevNodeOfClass_void_ModelDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_model_gotoNextNodeOfClass_void_ModelDocumentEditor_string_bool_wasm(
    arg: cstring): cstring {.importc.}
proc gotoNextNodeOfClass*(self: ModelDocumentEditor; className: string;
                          select: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add className.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_gotoNextNodeOfClass_void_ModelDocumentEditor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_model_toggleBoolCell_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc toggleBoolCell*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_toggleBoolCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_invertSelection_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc invertSelection*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_invertSelection_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrev_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrev*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectPrev_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectNext_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNext*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNext_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc selectNode*(self: ModelDocumentEditor; select: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevNeighbor_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectPrevNeighbor*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectPrevNeighbor_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextNeighbor_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectNextNeighbor*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNextNeighbor_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add select.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_deleteLeft_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteLeft*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_deleteLeft_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_deleteRight_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteRight*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_deleteRight_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_replaceLeft_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc replaceLeft*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_replaceLeft_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_replaceRight_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc replaceRight*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_replaceRight_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_createNewNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc createNewNode*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_createNewNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add input.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_model_undo_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc undo*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_undo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_redo_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc redo*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_redo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_showCompletions_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc showCompletions*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_showCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_showCompletionWindow_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc showCompletionWindow*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_showCompletionWindow_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_hideCompletions_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc hideCompletions*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_hideCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc selectPrevCompletion*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc selectNextCompletion*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
    arg: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_printSelectionInfo_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc printSelectionInfo*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_printSelectionInfo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_clearModelCache_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc clearModelCache*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_clearModelCache_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_runSelectedFunction_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSelectedFunction*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_runSelectedFunction_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_copyNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc copyNode*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_copyNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_pasteNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc pasteNode*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_pasteNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_addLanguage_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addLanguage*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_addLanguage_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_createNewModel_void_ModelDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc createNewModel*(self: ModelDocumentEditor; name: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_createNewModel_void_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_model_addModelToProject_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addModelToProject*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_addModelToProject_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_importModel_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc importModel*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_importModel_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_compileLanguage_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc compileLanguage*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_compileLanguage_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_addRootNode_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc addRootNode*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_addRootNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_saveProject_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc saveProject*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_saveProject_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_loadLanguageModel_void_ModelDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc loadLanguageModel*(self: ModelDocumentEditor) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_loadLanguageModel_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_findDeclaration_void_ModelDocumentEditor_bool_wasm(
    arg: cstring): cstring {.importc.}
proc findDeclaration*(self: ModelDocumentEditor; global: bool) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add self.toJson()
  argsJson.add global.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_model_findDeclaration_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)

