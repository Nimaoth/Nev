import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_ast_moveCursor_void_AstDocumentEditor_int_wasm(arg_8690610369: cstring): cstring {.
    importc.}
proc moveCursor*(self: AstDocumentEditor; direction: int) =
  var argsJson_8690610364 = newJArray()
  argsJson_8690610364.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690610364.add block:
    when int is JsonNode:
      direction
    else:
      direction.toJson()
  let argsJsonString = $argsJson_8690610364
  let res_8690610365 {.used.} = editor_ast_moveCursor_void_AstDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorUp_void_AstDocumentEditor_wasm(arg_8690610478: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: AstDocumentEditor) =
  var argsJson_8690610473 = newJArray()
  argsJson_8690610473.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610473
  let res_8690610474 {.used.} = editor_ast_moveCursorUp_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorDown_void_AstDocumentEditor_wasm(arg_8690610545: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: AstDocumentEditor) =
  var argsJson_8690610540 = newJArray()
  argsJson_8690610540.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610540
  let res_8690610541 {.used.} = editor_ast_moveCursorDown_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorNext_void_AstDocumentEditor_wasm(arg_8690610600: cstring): cstring {.
    importc.}
proc moveCursorNext*(self: AstDocumentEditor) =
  var argsJson_8690610595 = newJArray()
  argsJson_8690610595.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610595
  let res_8690610596 {.used.} = editor_ast_moveCursorNext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorPrev_void_AstDocumentEditor_wasm(arg_8690610673: cstring): cstring {.
    importc.}
proc moveCursorPrev*(self: AstDocumentEditor) =
  var argsJson_8690610668 = newJArray()
  argsJson_8690610668.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610668
  let res_8690610669 {.used.} = editor_ast_moveCursorPrev_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorNextLine_void_AstDocumentEditor_wasm(arg_8690610744: cstring): cstring {.
    importc.}
proc moveCursorNextLine*(self: AstDocumentEditor) =
  var argsJson_8690610739 = newJArray()
  argsJson_8690610739.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610739
  let res_8690610740 {.used.} = editor_ast_moveCursorNextLine_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorPrevLine_void_AstDocumentEditor_wasm(arg_8690610834: cstring): cstring {.
    importc.}
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  var argsJson_8690610829 = newJArray()
  argsJson_8690610829.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690610829
  let res_8690610830 {.used.} = editor_ast_moveCursorPrevLine_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectContaining_void_AstDocumentEditor_string_wasm(arg_8690610925: cstring): cstring {.
    importc.}
proc selectContaining*(self: AstDocumentEditor; container: string) =
  var argsJson_8690610920 = newJArray()
  argsJson_8690610920.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690610920.add block:
    when string is JsonNode:
      container
    else:
      container.toJson()
  let argsJsonString = $argsJson_8690610920
  let res_8690610921 {.used.} = editor_ast_selectContaining_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_deleteSelected_void_AstDocumentEditor_wasm(arg_8690611144: cstring): cstring {.
    importc.}
proc deleteSelected*(self: AstDocumentEditor) =
  var argsJson_8690611139 = newJArray()
  argsJson_8690611139.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611139
  let res_8690611140 {.used.} = editor_ast_deleteSelected_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_copySelected_void_AstDocumentEditor_wasm(arg_8690611231: cstring): cstring {.
    importc.}
proc copySelected*(self: AstDocumentEditor) =
  var argsJson_8690611226 = newJArray()
  argsJson_8690611226.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611226
  let res_8690611227 {.used.} = editor_ast_copySelected_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_finishEdit_void_AstDocumentEditor_bool_wasm(arg_8690611289: cstring): cstring {.
    importc.}
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  var argsJson_8690611284 = newJArray()
  argsJson_8690611284.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690611284.add block:
    when bool is JsonNode:
      apply
    else:
      apply.toJson()
  let argsJsonString = $argsJson_8690611284
  let res_8690611285 {.used.} = editor_ast_finishEdit_void_AstDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_ast_undo_void_AstDocumentEditor_wasm(arg_8690611403: cstring): cstring {.
    importc.}
proc undo*(self: AstDocumentEditor) =
  var argsJson_8690611398 = newJArray()
  argsJson_8690611398.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611398
  let res_8690611399 {.used.} = editor_ast_undo_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_redo_void_AstDocumentEditor_wasm(arg_8690611484: cstring): cstring {.
    importc.}
proc redo*(self: AstDocumentEditor) =
  var argsJson_8690611479 = newJArray()
  argsJson_8690611479.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690611479
  let res_8690611480 {.used.} = editor_ast_redo_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_insertAfterSmart_void_AstDocumentEditor_string_wasm(arg_8690611565: cstring): cstring {.
    importc.}
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690611560 = newJArray()
  argsJson_8690611560.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690611560.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690611560
  let res_8690611561 {.used.} = editor_ast_insertAfterSmart_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertAfter_void_AstDocumentEditor_string_wasm(arg_8690611983: cstring): cstring {.
    importc.}
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690611978 = newJArray()
  argsJson_8690611978.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690611978.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690611978
  let res_8690611979 {.used.} = editor_ast_insertAfter_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertBefore_void_AstDocumentEditor_string_wasm(arg_8690612166: cstring): cstring {.
    importc.}
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612161 = newJArray()
  argsJson_8690612161.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612161.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612161
  let res_8690612162 {.used.} = editor_ast_insertBefore_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertChild_void_AstDocumentEditor_string_wasm(arg_8690612348: cstring): cstring {.
    importc.}
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612343 = newJArray()
  argsJson_8690612343.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612343.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612343
  let res_8690612344 {.used.} = editor_ast_insertChild_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replace_void_AstDocumentEditor_string_wasm(arg_8690612529: cstring): cstring {.
    importc.}
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612524 = newJArray()
  argsJson_8690612524.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612524.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612524
  let res_8690612525 {.used.} = editor_ast_replace_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replaceEmpty_void_AstDocumentEditor_string_wasm(arg_8690612664: cstring): cstring {.
    importc.}
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612659 = newJArray()
  argsJson_8690612659.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612659.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612659
  let res_8690612660 {.used.} = editor_ast_replaceEmpty_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replaceParent_void_AstDocumentEditor_wasm(arg_8690612803: cstring): cstring {.
    importc.}
proc replaceParent*(self: AstDocumentEditor) =
  var argsJson_8690612798 = newJArray()
  argsJson_8690612798.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690612798
  let res_8690612799 {.used.} = editor_ast_replaceParent_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_wrap_void_AstDocumentEditor_string_wasm(arg_8690612868: cstring): cstring {.
    importc.}
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson_8690612863 = newJArray()
  argsJson_8690612863.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690612863.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson_8690612863
  let res_8690612864 {.used.} = editor_ast_wrap_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_editPrevEmpty_void_AstDocumentEditor_wasm(arg_8690613039: cstring): cstring {.
    importc.}
proc editPrevEmpty*(self: AstDocumentEditor) =
  var argsJson_8690613034 = newJArray()
  argsJson_8690613034.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613034
  let res_8690613035 {.used.} = editor_ast_editPrevEmpty_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_editNextEmpty_void_AstDocumentEditor_wasm(arg_8690613107: cstring): cstring {.
    importc.}
proc editNextEmpty*(self: AstDocumentEditor) =
  var argsJson_8690613102 = newJArray()
  argsJson_8690613102.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613102
  let res_8690613103 {.used.} = editor_ast_editNextEmpty_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_rename_void_AstDocumentEditor_wasm(arg_8690613213: cstring): cstring {.
    importc.}
proc rename*(self: AstDocumentEditor) =
  var argsJson_8690613208 = newJArray()
  argsJson_8690613208.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613208
  let res_8690613209 {.used.} = editor_ast_rename_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectPrevCompletion_void_AstDocumentEditor_wasm(arg_8690613268: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613263 = newJArray()
  argsJson_8690613263.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613263
  let res_8690613264 {.used.} = editor_ast_selectPrevCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectNextCompletion_void_AstDocumentEditor_wasm(arg_8690613340: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613335 = newJArray()
  argsJson_8690613335.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613335
  let res_8690613336 {.used.} = editor_ast_selectNextCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_applySelectedCompletion_void_AstDocumentEditor_wasm(arg_8690613412: cstring): cstring {.
    importc.}
proc applySelectedCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613407 = newJArray()
  argsJson_8690613407.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613407
  let res_8690613408 {.used.} = editor_ast_applySelectedCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_wasm(arg_8690613651: cstring): cstring {.
    importc.}
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613646 = newJArray()
  argsJson_8690613646.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613646
  let res_8690613647 {.used.} = editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_wasm(arg_8690613706: cstring): cstring {.
    importc.}
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  var argsJson_8690613701 = newJArray()
  argsJson_8690613701.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613701
  let res_8690613702 {.used.} = editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndDelete_void_AstDocumentEditor_wasm(arg_8690613761: cstring): cstring {.
    importc.}
proc cancelAndDelete*(self: AstDocumentEditor) =
  var argsJson_8690613756 = newJArray()
  argsJson_8690613756.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613756
  let res_8690613757 {.used.} = editor_ast_cancelAndDelete_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_wasm(arg_8690613819: cstring): cstring {.
    importc.}
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  var argsJson_8690613814 = newJArray()
  argsJson_8690613814.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613814
  let res_8690613815 {.used.} = editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_wasm(arg_8690613986: cstring): cstring {.
    importc.}
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  var argsJson_8690613981 = newJArray()
  argsJson_8690613981.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690613981
  let res_8690613982 {.used.} = editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectPrev_void_AstDocumentEditor_wasm(arg_8690614157: cstring): cstring {.
    importc.}
proc selectPrev*(self: AstDocumentEditor) =
  var argsJson_8690614152 = newJArray()
  argsJson_8690614152.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614152
  let res_8690614153 {.used.} = editor_ast_selectPrev_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectNext_void_AstDocumentEditor_wasm(arg_8690614213: cstring): cstring {.
    importc.}
proc selectNext*(self: AstDocumentEditor) =
  var argsJson_8690614208 = newJArray()
  argsJson_8690614208.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614208
  let res_8690614209 {.used.} = editor_ast_selectNext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_wasm(arg_8690614286: cstring): cstring {.
    importc.}
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  var argsJson_8690614281 = newJArray()
  argsJson_8690614281.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690614281
  let res_8690614282 {.used.} = editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_goto_void_AstDocumentEditor_string_wasm(arg_8690614616: cstring): cstring {.
    importc.}
proc goto*(self: AstDocumentEditor; where: string) =
  var argsJson_8690614611 = newJArray()
  argsJson_8690614611.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690614611.add block:
    when string is JsonNode:
      where
    else:
      where.toJson()
  let argsJsonString = $argsJson_8690614611
  let res_8690614612 {.used.} = editor_ast_goto_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_runSelectedFunction_void_AstDocumentEditor_wasm(arg_8690615213: cstring): cstring {.
    importc.}
proc runSelectedFunction*(self: AstDocumentEditor) =
  var argsJson_8690615208 = newJArray()
  argsJson_8690615208.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690615208
  let res_8690615209 {.used.} = editor_ast_runSelectedFunction_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_toggleOption_void_AstDocumentEditor_string_wasm(arg_8690615488: cstring): cstring {.
    importc.}
proc toggleOption*(self: AstDocumentEditor; name: string) =
  var argsJson_8690615483 = newJArray()
  argsJson_8690615483.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690615483.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson_8690615483
  let res_8690615484 {.used.} = editor_ast_toggleOption_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_runLastCommand_void_AstDocumentEditor_string_wasm(arg_8690615555: cstring): cstring {.
    importc.}
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  var argsJson_8690615550 = newJArray()
  argsJson_8690615550.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690615550.add block:
    when string is JsonNode:
      which
    else:
      which.toJson()
  let argsJsonString = $argsJson_8690615550
  let res_8690615551 {.used.} = editor_ast_runLastCommand_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_selectCenterNode_void_AstDocumentEditor_wasm(arg_8690615618: cstring): cstring {.
    importc.}
proc selectCenterNode*(self: AstDocumentEditor) =
  var argsJson_8690615613 = newJArray()
  argsJson_8690615613.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690615613
  let res_8690615614 {.used.} = editor_ast_selectCenterNode_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_scroll_void_AstDocumentEditor_float32_wasm(arg_8690616100: cstring): cstring {.
    importc.}
proc scroll*(self: AstDocumentEditor; amount: float32) =
  var argsJson_8690616095 = newJArray()
  argsJson_8690616095.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616095.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson_8690616095
  let res_8690616096 {.used.} = editor_ast_scroll_void_AstDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_ast_scrollOutput_void_AstDocumentEditor_string_wasm(arg_8690616167: cstring): cstring {.
    importc.}
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  var argsJson_8690616162 = newJArray()
  argsJson_8690616162.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616162.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson_8690616162
  let res_8690616163 {.used.} = editor_ast_scrollOutput_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_dumpContext_void_AstDocumentEditor_wasm(arg_8690616241: cstring): cstring {.
    importc.}
proc dumpContext*(self: AstDocumentEditor) =
  var argsJson_8690616236 = newJArray()
  argsJson_8690616236.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690616236
  let res_8690616237 {.used.} = editor_ast_dumpContext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_setMode_void_AstDocumentEditor_string_wasm(arg_8690616300: cstring): cstring {.
    importc.}
proc setMode*(self: AstDocumentEditor; mode: string) =
  var argsJson_8690616295 = newJArray()
  argsJson_8690616295.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616295.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson_8690616295
  let res_8690616296 {.used.} = editor_ast_setMode_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_mode_string_AstDocumentEditor_wasm(arg_8690616421: cstring): cstring {.
    importc.}
proc mode*(self: AstDocumentEditor): string =
  var argsJson_8690616416 = newJArray()
  argsJson_8690616416.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson_8690616416
  let res_8690616417 {.used.} = editor_ast_mode_string_AstDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8690616417).jsonTo(typeof(result))


proc editor_ast_getContextWithMode_string_AstDocumentEditor_string_wasm(
    arg_8690616482: cstring): cstring {.importc.}
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  var argsJson_8690616477 = newJArray()
  argsJson_8690616477.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson_8690616477.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson_8690616477
  let res_8690616478 {.used.} = editor_ast_getContextWithMode_string_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res_8690616478).jsonTo(typeof(result))

