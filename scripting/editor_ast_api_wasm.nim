import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_ast_moveCursor_void_AstDocumentEditor_int_wasm(arg_8690610370: cstring): cstring {.
    importc.}
proc moveCursor*(self: AstDocumentEditor; direction: int) =
  var argsJson_8690610365 = newJArray()
  argsJson_8690610365.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690610365.add block:
    when int is JsonNode:
      direction
    else:
      direction.toJson()
  let argsJsonString = $argsJson_8690610365
  let res_8690610366 {.used.} = editor_ast_moveCursor_void_AstDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorUp_void_AstDocumentEditor_wasm(arg_8690610480: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: AstDocumentEditor) =
  var argsJson_8690610475 = newJArray()
  argsJson_8690610475.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610475
  let res_8690610476 {.used.} = editor_ast_moveCursorUp_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorDown_void_AstDocumentEditor_wasm(arg_8690610548: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: AstDocumentEditor) =
  var argsJson_8690610543 = newJArray()
  argsJson_8690610543.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610543
  let res_8690610544 {.used.} = editor_ast_moveCursorDown_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorNext_void_AstDocumentEditor_wasm(arg_8690610604: cstring): cstring {.
    importc.}
proc moveCursorNext*(self: AstDocumentEditor) =
  var argsJson_8690610599 = newJArray()
  argsJson_8690610599.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610599
  let res_8690610600 {.used.} = editor_ast_moveCursorNext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorPrev_void_AstDocumentEditor_wasm(arg_8690610678: cstring): cstring {.
    importc.}
proc moveCursorPrev*(self: AstDocumentEditor) =
  var argsJson_8690610673 = newJArray()
  argsJson_8690610673.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610673
  let res_8690610674 {.used.} = editor_ast_moveCursorPrev_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorNextLine_void_AstDocumentEditor_wasm(arg_8690610750: cstring): cstring {.
    importc.}
proc moveCursorNextLine*(self: AstDocumentEditor) =
  var argsJson_8690610745 = newJArray()
  argsJson_8690610745.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610745
  let res_8690610746 {.used.} = editor_ast_moveCursorNextLine_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorPrevLine_void_AstDocumentEditor_wasm(arg_8690610841: cstring): cstring {.
    importc.}
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  var argsJson_8690610836 = newJArray()
  argsJson_8690610836.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610836
  let res_8690610837 {.used.} = editor_ast_moveCursorPrevLine_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectContaining_void_AstDocumentEditor_string_wasm(arg_8690610933: cstring): cstring {.
    importc.}
proc selectContaining*(self: AstDocumentEditor; container: string) =
  var argsJson_8690610928 = newJArray()
  argsJson_8690610928.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690610928.add block:
    when string is JsonNode:
      container
    else:
      container.toJson()
  let argsJsonString = $argsJson_8690610928
  let res_8690610929 {.used.} = editor_ast_selectContaining_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_deleteSelected_void_AstDocumentEditor_wasm(arg_8690611153: cstring): cstring {.
    importc.}
proc deleteSelected*(self: AstDocumentEditor) =
  var argsJson_8690611148 = newJArray()
  argsJson_8690611148.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611148
  let res_8690611149 {.used.} = editor_ast_deleteSelected_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_copySelected_void_AstDocumentEditor_wasm(arg_8690611241: cstring): cstring {.
    importc.}
proc copySelected*(self: AstDocumentEditor) =
  var argsJson_8690611236 = newJArray()
  argsJson_8690611236.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611236
  let res_8690611237 {.used.} = editor_ast_copySelected_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_finishEdit_void_AstDocumentEditor_bool_wasm(arg_8690611300: cstring): cstring {.
    importc.}
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  var argsJson_8690611295 = newJArray()
  argsJson_8690611295.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690611295.add block:
    when bool is JsonNode:
      apply
    else:
      apply.toJson()
  let argsJsonString = $argsJson_8690611295
  let res_8690611296 {.used.} = editor_ast_finishEdit_void_AstDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_ast_undo_void_AstDocumentEditor_wasm(arg_8690611415: cstring): cstring {.
    importc.}
proc undo*(self: AstDocumentEditor) =
  var argsJson_8690611410 = newJArray()
  argsJson_8690611410.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611410
  let res_8690611411 {.used.} = editor_ast_undo_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_redo_void_AstDocumentEditor_wasm(arg_8690611497: cstring): cstring {.
    importc.}
proc redo*(self: AstDocumentEditor) =
  var argsJson_8690611492 = newJArray()
  argsJson_8690611492.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611492
  let res_8690611493 {.used.} = editor_ast_redo_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_insertAfterSmart_void_AstDocumentEditor_string_wasm(arg_8690611579: cstring): cstring {.
    importc.}
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690611574 = newJArray()
  argsJson_8690611574.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690611574.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690611574
  let res_8690611575 {.used.} = editor_ast_insertAfterSmart_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertAfter_void_AstDocumentEditor_string_wasm(arg_8690611998: cstring): cstring {.
    importc.}
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690611993 = newJArray()
  argsJson_8690611993.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690611993.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690611993
  let res_8690611994 {.used.} = editor_ast_insertAfter_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertBefore_void_AstDocumentEditor_string_wasm(arg_8690612182: cstring): cstring {.
    importc.}
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612177 = newJArray()
  argsJson_8690612177.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612177.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612177
  let res_8690612178 {.used.} = editor_ast_insertBefore_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertChild_void_AstDocumentEditor_string_wasm(arg_8690612365: cstring): cstring {.
    importc.}
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612360 = newJArray()
  argsJson_8690612360.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612360.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612360
  let res_8690612361 {.used.} = editor_ast_insertChild_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replace_void_AstDocumentEditor_string_wasm(arg_8690612547: cstring): cstring {.
    importc.}
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612542 = newJArray()
  argsJson_8690612542.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612542.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612542
  let res_8690612543 {.used.} = editor_ast_replace_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replaceEmpty_void_AstDocumentEditor_string_wasm(arg_8690612683: cstring): cstring {.
    importc.}
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612678 = newJArray()
  argsJson_8690612678.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612678.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612678
  let res_8690612679 {.used.} = editor_ast_replaceEmpty_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replaceParent_void_AstDocumentEditor_wasm(arg_8690612823: cstring): cstring {.
    importc.}
proc replaceParent*(self: AstDocumentEditor) =
  var argsJson_8690612818 = newJArray()
  argsJson_8690612818.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690612818
  let res_8690612819 {.used.} = editor_ast_replaceParent_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_wrap_void_AstDocumentEditor_string_wasm(arg_8690612889: cstring): cstring {.
    importc.}
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612884 = newJArray()
  argsJson_8690612884.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612884.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612884
  let res_8690612885 {.used.} = editor_ast_wrap_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_editPrevEmpty_void_AstDocumentEditor_wasm(arg_8690613061: cstring): cstring {.
    importc.}
proc editPrevEmpty*(self: AstDocumentEditor) =
  var argsJson_8690613056 = newJArray()
  argsJson_8690613056.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613056
  let res_8690613057 {.used.} = editor_ast_editPrevEmpty_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_editNextEmpty_void_AstDocumentEditor_wasm(arg_8690613130: cstring): cstring {.
    importc.}
proc editNextEmpty*(self: AstDocumentEditor) =
  var argsJson_8690613125 = newJArray()
  argsJson_8690613125.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613125
  let res_8690613126 {.used.} = editor_ast_editNextEmpty_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_rename_void_AstDocumentEditor_wasm(arg_8690613237: cstring): cstring {.
    importc.}
proc rename*(self: AstDocumentEditor) =
  var argsJson_8690613232 = newJArray()
  argsJson_8690613232.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613232
  let res_8690613233 {.used.} = editor_ast_rename_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectPrevCompletion_void_AstDocumentEditor_wasm(arg_8690613293: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613288 = newJArray()
  argsJson_8690613288.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613288
  let res_8690613289 {.used.} = editor_ast_selectPrevCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectNextCompletion_void_AstDocumentEditor_wasm(arg_8690613366: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613361 = newJArray()
  argsJson_8690613361.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613361
  let res_8690613362 {.used.} = editor_ast_selectNextCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_applySelectedCompletion_void_AstDocumentEditor_wasm(arg_8690613439: cstring): cstring {.
    importc.}
proc applySelectedCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613434 = newJArray()
  argsJson_8690613434.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613434
  let res_8690613435 {.used.} = editor_ast_applySelectedCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_wasm(arg_8690613679: cstring): cstring {.
    importc.}
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613674 = newJArray()
  argsJson_8690613674.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613674
  let res_8690613675 {.used.} = editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_wasm(arg_8690613735: cstring): cstring {.
    importc.}
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613730 = newJArray()
  argsJson_8690613730.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613730
  let res_8690613731 {.used.} = editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndDelete_void_AstDocumentEditor_wasm(arg_8690613791: cstring): cstring {.
    importc.}
proc cancelAndDelete*(self: AstDocumentEditor) =
  var argsJson_8690613786 = newJArray()
  argsJson_8690613786.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613786
  let res_8690613787 {.used.} = editor_ast_cancelAndDelete_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_wasm(arg_8690613850: cstring): cstring {.
    importc.}
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  var argsJson_8690613845 = newJArray()
  argsJson_8690613845.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613845
  let res_8690613846 {.used.} = editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_wasm(arg_8690614018: cstring): cstring {.
    importc.}
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  var argsJson_8690614013 = newJArray()
  argsJson_8690614013.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614013
  let res_8690614014 {.used.} = editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectPrev_void_AstDocumentEditor_wasm(arg_8690614190: cstring): cstring {.
    importc.}
proc selectPrev*(self: AstDocumentEditor) =
  var argsJson_8690614185 = newJArray()
  argsJson_8690614185.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614185
  let res_8690614186 {.used.} = editor_ast_selectPrev_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectNext_void_AstDocumentEditor_wasm(arg_8690614247: cstring): cstring {.
    importc.}
proc selectNext*(self: AstDocumentEditor) =
  var argsJson_8690614242 = newJArray()
  argsJson_8690614242.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614242
  let res_8690614243 {.used.} = editor_ast_selectNext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_wasm(arg_8690614321: cstring): cstring {.
    importc.}
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  var argsJson_8690614316 = newJArray()
  argsJson_8690614316.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614316
  let res_8690614317 {.used.} = editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_goto_void_AstDocumentEditor_string_wasm(arg_8690614652: cstring): cstring {.
    importc.}
proc goto*(self: AstDocumentEditor; where: string) =
  var argsJson_8690614647 = newJArray()
  argsJson_8690614647.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690614647.add block:
    when string is JsonNode:
      where
    else:
      where.toJson()
  let argsJsonString = $argsJson_8690614647
  let res_8690614648 {.used.} = editor_ast_goto_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_runSelectedFunction_void_AstDocumentEditor_wasm(arg_8690615250: cstring): cstring {.
    importc.}
proc runSelectedFunction*(self: AstDocumentEditor) =
  var argsJson_8690615245 = newJArray()
  argsJson_8690615245.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690615245
  let res_8690615246 {.used.} = editor_ast_runSelectedFunction_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_toggleOption_void_AstDocumentEditor_string_wasm(arg_8690615526: cstring): cstring {.
    importc.}
proc toggleOption*(self: AstDocumentEditor; name: string) =
  var argsJson_8690615521 = newJArray()
  argsJson_8690615521.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690615521.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson_8690615521
  let res_8690615522 {.used.} = editor_ast_toggleOption_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_runLastCommand_void_AstDocumentEditor_string_wasm(arg_8690615594: cstring): cstring {.
    importc.}
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  var argsJson_8690615589 = newJArray()
  argsJson_8690615589.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690615589.add block:
    when string is JsonNode:
      which
    else:
      which.toJson()
  let argsJsonString = $argsJson_8690615589
  let res_8690615590 {.used.} = editor_ast_runLastCommand_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_selectCenterNode_void_AstDocumentEditor_wasm(arg_8690615658: cstring): cstring {.
    importc.}
proc selectCenterNode*(self: AstDocumentEditor) =
  var argsJson_8690615653 = newJArray()
  argsJson_8690615653.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690615653
  let res_8690615654 {.used.} = editor_ast_selectCenterNode_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_scroll_void_AstDocumentEditor_float32_wasm(arg_8690616141: cstring): cstring {.
    importc.}
proc scroll*(self: AstDocumentEditor; amount: float32) =
  var argsJson_8690616136 = newJArray()
  argsJson_8690616136.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616136.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_8690616136
  let res_8690616137 {.used.} = editor_ast_scroll_void_AstDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_ast_scrollOutput_void_AstDocumentEditor_string_wasm(arg_8690616209: cstring): cstring {.
    importc.}
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  var argsJson_8690616204 = newJArray()
  argsJson_8690616204.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616204.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_8690616204
  let res_8690616205 {.used.} = editor_ast_scrollOutput_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_dumpContext_void_AstDocumentEditor_wasm(arg_8690616284: cstring): cstring {.
    importc.}
proc dumpContext*(self: AstDocumentEditor) =
  var argsJson_8690616279 = newJArray()
  argsJson_8690616279.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690616279
  let res_8690616280 {.used.} = editor_ast_dumpContext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_setMode_void_AstDocumentEditor_string_wasm(arg_8690616344: cstring): cstring {.
    importc.}
proc setMode*(self: AstDocumentEditor; mode: string) =
  var argsJson_8690616339 = newJArray()
  argsJson_8690616339.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616339.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_8690616339
  let res_8690616340 {.used.} = editor_ast_setMode_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_mode_string_AstDocumentEditor_wasm(arg_8690616466: cstring): cstring {.
    importc.}
proc mode*(self: AstDocumentEditor): string =
  var argsJson_8690616461 = newJArray()
  argsJson_8690616461.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690616461
  let res_8690616462 {.used.} = editor_ast_mode_string_AstDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8690616462).jsonTo(typeof(result))


proc editor_ast_getContextWithMode_string_AstDocumentEditor_string_wasm(
    arg_8690616528: cstring): cstring {.importc.}
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  var argsJson_8690616523 = newJArray()
  argsJson_8690616523.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616523.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_8690616523
  let res_8690616524 {.used.} = editor_ast_getContextWithMode_string_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8690616524).jsonTo(typeof(result))

