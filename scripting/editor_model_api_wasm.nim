import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_model_scroll_void_ModelDocumentEditor_float32_wasm(arg_8992600594: cstring): cstring {.
    importc.}
proc scroll*(self: ModelDocumentEditor; amount: float32) =
  var argsJson_8992600589 = newJArray()
  argsJson_8992600589.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992600589.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_8992600589
  let res_8992600590 {.used.} = editor_model_scroll_void_ModelDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_model_setMode_void_ModelDocumentEditor_string_wasm(arg_8992600710: cstring): cstring {.
    importc.}
proc setMode*(self: ModelDocumentEditor; mode: string) =
  var argsJson_8992600705 = newJArray()
  argsJson_8992600705.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992600705.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_8992600705
  let res_8992600706 {.used.} = editor_model_setMode_void_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_model_mode_string_ModelDocumentEditor_wasm(arg_8992603847: cstring): cstring {.
    importc.}
proc mode*(self: ModelDocumentEditor): string =
  var argsJson_8992603842 = newJArray()
  argsJson_8992603842.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992603842
  let res_8992603843 {.used.} = editor_model_mode_string_ModelDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8992603843).jsonTo(typeof(result))


proc editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
    arg_8992603909: cstring): cstring {.importc.}
proc getContextWithMode*(self: ModelDocumentEditor; context: string): string =
  var argsJson_8992603904 = newJArray()
  argsJson_8992603904.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992603904.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_8992603904
  let res_8992603905 {.used.} = editor_model_getContextWithMode_string_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8992603905).jsonTo(typeof(result))


proc editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(arg_8992603979: cstring): cstring {.
    importc.}
proc moveCursorLeft*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992603974 = newJArray()
  argsJson_8992603974.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992603974.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992603974
  let res_8992603975 {.used.} = editor_model_moveCursorLeft_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
    arg_8992604084: cstring): cstring {.importc.}
proc moveCursorRight*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604079 = newJArray()
  argsJson_8992604079.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604079.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604079
  let res_8992604080 {.used.} = editor_model_moveCursorRight_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
    arg_8992604178: cstring): cstring {.importc.}
proc moveCursorLeftLine*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604173 = newJArray()
  argsJson_8992604173.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604173.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604173
  let res_8992604174 {.used.} = editor_model_moveCursorLeftLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
    arg_8992604283: cstring): cstring {.importc.}
proc moveCursorRightLine*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604278 = newJArray()
  argsJson_8992604278.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604278.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604278
  let res_8992604279 {.used.} = editor_model_moveCursorRightLine_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
    arg_8992604389: cstring): cstring {.importc.}
proc moveCursorLineStart*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604384 = newJArray()
  argsJson_8992604384.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604384.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604384
  let res_8992604385 {.used.} = editor_model_moveCursorLineStart_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
    arg_8992604486: cstring): cstring {.importc.}
proc moveCursorLineEnd*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604481 = newJArray()
  argsJson_8992604481.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604481.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604481
  let res_8992604482 {.used.} = editor_model_moveCursorLineEnd_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
    arg_8992604586: cstring): cstring {.importc.}
proc moveCursorLineStartInline*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604581 = newJArray()
  argsJson_8992604581.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604581.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604581
  let res_8992604582 {.used.} = editor_model_moveCursorLineStartInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
    arg_8992604684: cstring): cstring {.importc.}
proc moveCursorLineEndInline*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604679 = newJArray()
  argsJson_8992604679.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604679.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604679
  let res_8992604680 {.used.} = editor_model_moveCursorLineEndInline_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(arg_8992604782: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604777 = newJArray()
  argsJson_8992604777.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604777.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604777
  let res_8992604778 {.used.} = editor_model_moveCursorUp_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(arg_8992604906: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992604901 = newJArray()
  argsJson_8992604901.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992604901.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992604901
  let res_8992604902 {.used.} = editor_model_moveCursorDown_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
    arg_8992605025: cstring): cstring {.importc.}
proc moveCursorLeftCell*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605020 = newJArray()
  argsJson_8992605020.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605020.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605020
  let res_8992605021 {.used.} = editor_model_moveCursorLeftCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
    arg_8992605141: cstring): cstring {.importc.}
proc moveCursorRightCell*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605136 = newJArray()
  argsJson_8992605136.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605136.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605136
  let res_8992605137 {.used.} = editor_model_moveCursorRightCell_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(arg_8992605257: cstring): cstring {.
    importc.}
proc selectNode*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605252 = newJArray()
  argsJson_8992605252.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605252.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605252
  let res_8992605253 {.used.} = editor_model_selectNode_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectParentCell_void_ModelDocumentEditor_wasm(arg_8992605403: cstring): cstring {.
    importc.}
proc selectParentCell*(self: ModelDocumentEditor) =
  var argsJson_8992605398 = newJArray()
  argsJson_8992605398.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992605398
  let res_8992605399 {.used.} = editor_model_selectParentCell_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg_8992605472: cstring): cstring {.importc.}
proc selectPrevPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605467 = newJArray()
  argsJson_8992605467.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605467.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605467
  let res_8992605468 {.used.} = editor_model_selectPrevPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
    arg_8992605565: cstring): cstring {.importc.}
proc selectNextPlaceholder*(self: ModelDocumentEditor; select: bool = false) =
  var argsJson_8992605560 = newJArray()
  argsJson_8992605560.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992605560.add block:
    when bool is JsonNode:
      select
    else:
      select.toJson()
  let argsJsonString = $argsJson_8992605560
  let res_8992605561 {.used.} = editor_model_selectNextPlaceholder_void_ModelDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_model_deleteLeft_void_ModelDocumentEditor_wasm(arg_8992606508: cstring): cstring {.
    importc.}
proc deleteLeft*(self: ModelDocumentEditor) =
  var argsJson_8992606503 = newJArray()
  argsJson_8992606503.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992606503
  let res_8992606504 {.used.} = editor_model_deleteLeft_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_deleteRight_void_ModelDocumentEditor_wasm(arg_8992606644: cstring): cstring {.
    importc.}
proc deleteRight*(self: ModelDocumentEditor) =
  var argsJson_8992606639 = newJArray()
  argsJson_8992606639.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992606639
  let res_8992606640 {.used.} = editor_model_deleteRight_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_createNewNode_void_ModelDocumentEditor_wasm(arg_8992607251: cstring): cstring {.
    importc.}
proc createNewNode*(self: ModelDocumentEditor) =
  var argsJson_8992607246 = newJArray()
  argsJson_8992607246.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992607246
  let res_8992607247 {.used.} = editor_model_createNewNode_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
    arg_8992607386: cstring): cstring {.importc.}
proc insertTextAtCursor*(self: ModelDocumentEditor; input: string): bool =
  var argsJson_8992607381 = newJArray()
  argsJson_8992607381.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8992607381.add block:
    when string is JsonNode:
      input
    else:
      input.toJson()
  let argsJsonString = $argsJson_8992607381
  let res_8992607382 {.used.} = editor_model_insertTextAtCursor_bool_ModelDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8992607382).jsonTo(typeof(result))


proc editor_model_undo_void_ModelDocumentEditor_wasm(arg_8992607572: cstring): cstring {.
    importc.}
proc undo*(self: ModelDocumentEditor) =
  var argsJson_8992607567 = newJArray()
  argsJson_8992607567.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992607567
  let res_8992607568 {.used.} = editor_model_undo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_redo_void_ModelDocumentEditor_wasm(arg_8992607913: cstring): cstring {.
    importc.}
proc redo*(self: ModelDocumentEditor) =
  var argsJson_8992607908 = newJArray()
  argsJson_8992607908.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992607908
  let res_8992607909 {.used.} = editor_model_redo_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
    arg_8992608130: cstring): cstring {.importc.}
proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) =
  var argsJson_8992608125 = newJArray()
  argsJson_8992608125.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608125
  let res_8992608126 {.used.} = editor_model_toggleUseDefaultCellBuilder_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_showCompletions_void_ModelDocumentEditor_wasm(arg_8992608186: cstring): cstring {.
    importc.}
proc showCompletions*(self: ModelDocumentEditor) =
  var argsJson_8992608181 = newJArray()
  argsJson_8992608181.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608181
  let res_8992608182 {.used.} = editor_model_showCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_hideCompletions_void_ModelDocumentEditor_wasm(arg_8992608242: cstring): cstring {.
    importc.}
proc hideCompletions*(self: ModelDocumentEditor) =
  var argsJson_8992608237 = newJArray()
  argsJson_8992608237.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608237
  let res_8992608238 {.used.} = editor_model_hideCompletions_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
    arg_8992608302: cstring): cstring {.importc.}
proc selectPrevCompletion*(self: ModelDocumentEditor) =
  var argsJson_8992608297 = newJArray()
  argsJson_8992608297.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608297
  let res_8992608298 {.used.} = editor_model_selectPrevCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
    arg_8992608366: cstring): cstring {.importc.}
proc selectNextCompletion*(self: ModelDocumentEditor) =
  var argsJson_8992608361 = newJArray()
  argsJson_8992608361.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608361
  let res_8992608362 {.used.} = editor_model_selectNextCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
    arg_8992608430: cstring): cstring {.importc.}
proc applySelectedCompletion*(self: ModelDocumentEditor) =
  var argsJson_8992608425 = newJArray()
  argsJson_8992608425.add block:
    when ModelDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8992608425
  let res_8992608426 {.used.} = editor_model_applySelectedCompletion_void_ModelDocumentEditor_wasm(
      argsJsonString.cstring)

