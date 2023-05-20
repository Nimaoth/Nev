import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_model_scroll_void_ModelDocumentEditor_float32_wasm(arg_8992600593: cstring): cstring {.
    importc.}
proc scroll*(self: ModelDocumentEditor; amount: float32) =
  var argsJson_8992600588 = newJArray()
  argsJson_8992600588.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992600588.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_8992600588
  let res_8992600589 {.used.} = editor_model_scroll_void_ModelDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_model_setMode_void_ModelDocumentEditor_string_wasm(arg_8992600708: cstring): cstring {.
    importc.}
proc setMode*(self: ModelDocumentEditor; mode: string) =
  var argsJson_8992600703 = newJArray()
  argsJson_8992600703.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992600703.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_8992600703
  let res_8992600704 {.used.} = editor_model_setMode_void_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_model_mode_string_ModelDocumentEditor_wasm(arg_8992603844: cstring): cstring {.
    importc.}
proc mode*(self: ModelDocumentEditor): string =
  var argsJson_8992603839 = newJArray()
  argsJson_8992603839.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992603839
  let res_8992603840 {.used.} = editor_model_mode_string_ModelDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8992603840).jsonTo(typeof(result))


proc editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
    arg_8992603905: cstring): cstring {.importc.}
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  var argsJson_8992603900 = newJArray()
  argsJson_8992603900.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992603900.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_8992603900
  let res_8992603901 {.used.} = editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8992603901).jsonTo(typeof(result))


proc editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(arg_8992603974: cstring): cstring {.
    importc.}
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992603969 = newJArray()
  argsJson_8992603969.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992603969.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992603969
  let res_8992603970 {.used.} = editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
    arg_8992604078: cstring): cstring {.importc.}
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604073 = newJArray()
  argsJson_8992604073.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604073.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604073
  let res_8992604074 {.used.} = editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
    arg_8992604171: cstring): cstring {.importc.}
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604166 = newJArray()
  argsJson_8992604166.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604166.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604166
  let res_8992604167 {.used.} = editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
    arg_8992604275: cstring): cstring {.importc.}
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604270 = newJArray()
  argsJson_8992604270.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604270.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604270
  let res_8992604271 {.used.} = editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
    arg_8992604380: cstring): cstring {.importc.}
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604375 = newJArray()
  argsJson_8992604375.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604375.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604375
  let res_8992604376 {.used.} = editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
    arg_8992604476: cstring): cstring {.importc.}
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604471 = newJArray()
  argsJson_8992604471.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604471.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604471
  let res_8992604472 {.used.} = editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
    arg_8992604575: cstring): cstring {.importc.}
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604570 = newJArray()
  argsJson_8992604570.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604570.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604570
  let res_8992604571 {.used.} = editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
    arg_8992604672: cstring): cstring {.importc.}
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604667 = newJArray()
  argsJson_8992604667.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604667.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604667
  let res_8992604668 {.used.} = editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(arg_8992604769: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604764 = newJArray()
  argsJson_8992604764.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604764.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604764
  let res_8992604765 {.used.} = editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(arg_8992604892: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604887 = newJArray()
  argsJson_8992604887.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604887.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604887
  let res_8992604888 {.used.} = editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
    arg_8992605010: cstring): cstring {.importc.}
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605005 = newJArray()
  argsJson_8992605005.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605005.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605005
  let res_8992605006 {.used.} = editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
    arg_8992605125: cstring): cstring {.importc.}
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605120 = newJArray()
  argsJson_8992605120.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605120.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605120
  let res_8992605121 {.used.} = editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(arg_8992605240: cstring): cstring {.
    importc.}
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605235 = newJArray()
  argsJson_8992605235.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605235.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605235
  let res_8992605236 {.used.} = editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectParentCell_void_ModelDocumentEditor_wasm(arg_8992605385: cstring): cstring {.
    importc.}
proc selectParentCell*(self: ModelDocumentEditor) =
  var argsJson_8992605380 = newJArray()
  argsJson_8992605380.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992605380
  let res_8992605381 {.used.} = editor_model_selectParentCell_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg_8992605453: cstring): cstring {.importc.}
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605448 = newJArray()
  argsJson_8992605448.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605448.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605448
  let res_8992605449 {.used.} = editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg_8992605545: cstring): cstring {.importc.}
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605540 = newJArray()
  argsJson_8992605540.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605540.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605540
  let res_8992605541 {.used.} = editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_deleteLeft_void_ModelDocumentEditor_wasm(arg_8992606487: cstring): cstring {.
    importc.}
proc deleteLeft*(self: ModelDocumentEditor) =
  var argsJson_8992606482 = newJArray()
  argsJson_8992606482.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992606482
  let res_8992606483 {.used.} = editor_model_deleteLeft_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_deleteRight_void_ModelDocumentEditor_wasm(arg_8992606622: cstring): cstring {.
    importc.}
proc deleteRight*(self: ModelDocumentEditor) =
  var argsJson_8992606617 = newJArray()
  argsJson_8992606617.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992606617
  let res_8992606618 {.used.} = editor_model_deleteRight_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_createNewNode_void_ModelDocumentEditor_wasm(arg_8992607228: cstring): cstring {.
    importc.}
proc createNewNode*(self: ModelDocumentEditor) =
  var argsJson_8992607223 = newJArray()
  argsJson_8992607223.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992607223
  let res_8992607224 {.used.} = editor_model_createNewNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
    arg_8992607362: cstring): cstring {.importc.}
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  var argsJson_8992607357 = newJArray()
  argsJson_8992607357.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992607357.add block:
    when string is JsonNode:
      input
    else:
      input.toJson()
  let argsJsonString = $argsJson_8992607357
  let res_8992607358 {.used.} = editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8992607358).jsonTo(typeof(result))


proc editor_model_undo_void_ModelDocumentEditor_wasm(arg_8992607547: cstring): cstring {.
    importc.}
proc undo*(self: ModelDocumentEditor) =
  var argsJson_8992607542 = newJArray()
  argsJson_8992607542.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992607542
  let res_8992607543 {.used.} = editor_model_undo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_redo_void_ModelDocumentEditor_wasm(arg_8992607887: cstring): cstring {.
    importc.}
proc redo*(self: ModelDocumentEditor) =
  var argsJson_8992607882 = newJArray()
  argsJson_8992607882.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992607882
  let res_8992607883 {.used.} = editor_model_redo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
    arg_8992608103: cstring): cstring {.importc.}
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  var argsJson_8992608098 = newJArray()
  argsJson_8992608098.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608098
  let res_8992608099 {.used.} = editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_showCompletions_void_ModelDocumentEditor_wasm(arg_8992608158: cstring): cstring {.
    importc.}
proc showCompletions*(self: ModelDocumentEditor) =
  var argsJson_8992608153 = newJArray()
  argsJson_8992608153.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608153
  let res_8992608154 {.used.} = editor_model_showCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_hideCompletions_void_ModelDocumentEditor_wasm(arg_8992608213: cstring): cstring {.
    importc.}
proc hideCompletions*(self: ModelDocumentEditor) =
  var argsJson_8992608208 = newJArray()
  argsJson_8992608208.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608208
  let res_8992608209 {.used.} = editor_model_hideCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
    arg_8992608272: cstring): cstring {.importc.}
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  var argsJson_8992608267 = newJArray()
  argsJson_8992608267.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608267
  let res_8992608268 {.used.} = editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
    arg_8992608335: cstring): cstring {.importc.}
proc selectNextCompletion*(self: ModelDocumentEditor) =
  var argsJson_8992608330 = newJArray()
  argsJson_8992608330.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608330
  let res_8992608331 {.used.} = editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
    arg_8992608398: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  var argsJson_8992608393 = newJArray()
  argsJson_8992608393.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608393
  let res_8992608394 {.used.} = editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)

