import std/[json]
import scripting_api, myjsonutils

## This file is auto generated, don't modify.


proc editor_ast_moveCursor_void_AstDocumentEditor_int_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursor*(self: AstDocumentEditor; direction: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when int is JsonNode:
      direction
    else:
      direction.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursor_void_AstDocumentEditor_int_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorUp_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorUp*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursorUp_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorDown_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorDown*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursorDown_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorNext_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorNext*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursorNext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorPrev_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorPrev*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursorPrev_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorNextLine_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorNextLine*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursorNextLine_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveCursorPrevLine_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveCursorPrevLine_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectContaining_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc selectContaining*(self: AstDocumentEditor; container: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      container
    else:
      container.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_selectContaining_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_deleteSelected_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc deleteSelected*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_deleteSelected_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_copySelected_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc copySelected*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_copySelected_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_finishEdit_void_AstDocumentEditor_bool_wasm(arg: cstring): cstring {.
    importc.}
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when bool is JsonNode:
      apply
    else:
      apply.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_finishEdit_void_AstDocumentEditor_bool_wasm(
      argsJsonString.cstring)


proc editor_ast_undo_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc undo*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_undo_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_redo_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc redo*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_redo_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_insertAfterSmart_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_insertAfterSmart_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertAfter_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_insertAfter_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertBefore_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_insertBefore_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_insertChild_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_insertChild_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replace_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_replace_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replaceEmpty_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_replaceEmpty_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_replaceParent_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc replaceParent*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_replaceParent_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_wrap_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      nodeTemplate
    else:
      nodeTemplate.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_wrap_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_editPrevEmpty_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc editPrevEmpty*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_editPrevEmpty_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_editNextEmpty_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc editNextEmpty*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_editNextEmpty_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_rename_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc rename*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_rename_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectPrevCompletion_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrevCompletion*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_selectPrevCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectNextCompletion_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextCompletion*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_selectNextCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_applySelectedCompletion_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc applySelectedCompletion*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_applySelectedCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_cancelAndNextCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_cancelAndPrevCompletion_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_cancelAndDelete_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc cancelAndDelete*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_cancelAndDelete_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveNodeToPrevSpace_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_moveNodeToNextSpace_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectPrev_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectPrev*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_selectPrev_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_selectNext_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectNext*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_selectNext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc openGotoSymbolPopup*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_openGotoSymbolPopup_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_goto_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc goto*(self: AstDocumentEditor; where: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      where
    else:
      where.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_goto_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_runSelectedFunction_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc runSelectedFunction*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_runSelectedFunction_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_toggleOption_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc toggleOption*(self: AstDocumentEditor; name: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_toggleOption_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_runLastCommand_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      which
    else:
      which.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_runLastCommand_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_selectCenterNode_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc selectCenterNode*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_selectCenterNode_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_scroll_void_AstDocumentEditor_float32_wasm(arg: cstring): cstring {.
    importc.}
proc scroll*(self: AstDocumentEditor; amount: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_scroll_void_AstDocumentEditor_float32_wasm(
      argsJsonString.cstring)


proc editor_ast_scrollOutput_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_scrollOutput_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_dumpContext_void_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc dumpContext*(self: AstDocumentEditor) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_dumpContext_void_AstDocumentEditor_wasm(
      argsJsonString.cstring)


proc editor_ast_setMode_void_AstDocumentEditor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setMode*(self: AstDocumentEditor; mode: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_setMode_void_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)


proc editor_ast_mode_string_AstDocumentEditor_wasm(arg: cstring): cstring {.
    importc.}
proc mode*(self: AstDocumentEditor): string =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_mode_string_AstDocumentEditor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_ast_getContextWithMode_string_AstDocumentEditor_string_wasm(
    arg: cstring): cstring {.importc.}
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when AstDocumentEditor is JsonNode:
      self
    else:
      self.toJson()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_ast_getContextWithMode_string_AstDocumentEditor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))

