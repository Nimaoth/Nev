import std/[json, jsonutils]
import "../src/scripting_api"

## This file is auto generated, don't modify.


proc editor_getBackend_Backend_Editor_wasm(arg: cstring): cstring {.importc.}
proc getBackend*(): Backend =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getBackend_Backend_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_saveAppState_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc saveAppState*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_saveAppState_void_Editor_wasm(argsJsonString.cstring)


proc editor_requestRender_void_Editor_bool_wasm(arg: cstring): cstring {.importc.}
proc requestRender*(redrawEverything: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      redrawEverything
    else:
      redrawEverything.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_requestRender_void_Editor_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleInputs_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setHandleInputs*(context: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setHandleInputs_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleActions_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setHandleActions*(context: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setHandleActions_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllActions_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setConsumeAllActions*(context: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setConsumeAllActions_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllInput_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setConsumeAllInput*(context: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setConsumeAllInput_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_clearWorkspaceCaches_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc clearWorkspaceCaches*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearWorkspaceCaches_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_openGithubWorkspace_void_Editor_string_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      user
    else:
      user.toJson()
  argsJson.add block:
    when string is JsonNode:
      repository
    else:
      repository.toJson()
  argsJson.add block:
    when string is JsonNode:
      branchOrHash
    else:
      branchOrHash.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openGithubWorkspace_void_Editor_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_openAbsytreeServerWorkspace_void_Editor_string_wasm(arg: cstring): cstring {.
    importc.}
proc openAbsytreeServerWorkspace*(url: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      url
    else:
      url.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openAbsytreeServerWorkspace_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_openLocalWorkspace_void_Editor_string_wasm(arg: cstring): cstring {.
    importc.}
proc openLocalWorkspace*(path: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openLocalWorkspace_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_getFlag_bool_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc getFlag*(flag: string; default: bool = false): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  argsJson.add block:
    when bool is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getFlag_bool_Editor_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_setFlag_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setFlag*(flag: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setFlag_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_toggleFlag_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc toggleFlag*(flag: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleFlag_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_setOption_void_Editor_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc setOption*(option: string; value: JsonNode) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      option
    else:
      option.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setOption_void_Editor_string_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_quit_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc quit*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_quit_void_Editor_wasm(argsJsonString.cstring)


proc editor_changeFontSize_void_Editor_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeFontSize*(amount: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeFontSize_void_Editor_float32_wasm(
      argsJsonString.cstring)


proc editor_changeLayoutProp_void_Editor_string_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeLayoutProp*(prop: string; change: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      prop
    else:
      prop.toJson()
  argsJson.add block:
    when float32 is JsonNode:
      change
    else:
      change.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeLayoutProp_void_Editor_string_float32_wasm(
      argsJsonString.cstring)


proc editor_toggleStatusBarLocation_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc toggleStatusBarLocation*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleStatusBarLocation_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_createView_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc createView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_createView_void_Editor_wasm(argsJsonString.cstring)


proc editor_closeCurrentView_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc closeCurrentView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeCurrentView_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewToTop_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewToTop*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewToTop_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_nextView_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc nextView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_nextView_void_Editor_wasm(argsJsonString.cstring)


proc editor_prevView_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc prevView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_prevView_void_Editor_wasm(argsJsonString.cstring)


proc editor_moveCurrentViewPrev_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewPrev*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewPrev_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewNext_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc moveCurrentViewNext*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewNext_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_setLayout_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc setLayout*(layout: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      layout
    else:
      layout.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLayout_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_commandLine_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc commandLine*(initialValue: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      initialValue
    else:
      initialValue.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_commandLine_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_exitCommandLine_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc exitCommandLine*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exitCommandLine_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_executeCommandLine_bool_Editor_wasm(arg: cstring): cstring {.importc.}
proc executeCommandLine*(): bool =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_executeCommandLine_bool_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_writeFile_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc writeFile*(path: string = ""; app: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_writeFile_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_loadFile_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc loadFile*(path: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadFile_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_openFile_void_Editor_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc openFile*(path: string; app: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openFile_void_Editor_string_bool_wasm(
      argsJsonString.cstring)


proc editor_removeFromLocalStorage_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc removeFromLocalStorage*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_removeFromLocalStorage_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_loadTheme_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc loadTheme*(name: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadTheme_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_chooseTheme_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc chooseTheme*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseTheme_void_Editor_wasm(argsJsonString.cstring)


proc editor_chooseFile_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc chooseFile*(view: string = "new") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      view
    else:
      view.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseFile_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_setGithubAccessToken_void_Editor_string_wasm(arg: cstring): cstring {.
    importc.}
proc setGithubAccessToken*(token: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      token
    else:
      token.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setGithubAccessToken_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_reloadConfig_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc reloadConfig*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadConfig_void_Editor_wasm(argsJsonString.cstring)


proc editor_logOptions_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc logOptions*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logOptions_void_Editor_wasm(argsJsonString.cstring)


proc editor_clearCommands_void_Editor_string_wasm(arg: cstring): cstring {.
    importc.}
proc clearCommands*(context: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearCommands_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_getAllEditors_seq_EditorId_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc getAllEditors*(): seq[EditorId] =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getAllEditors_seq_EditorId_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_setMode_void_Editor_string_wasm(arg: cstring): cstring {.importc.}
proc setMode*(mode: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setMode_void_Editor_string_wasm(
      argsJsonString.cstring)


proc editor_mode_string_Editor_wasm(arg: cstring): cstring {.importc.}
proc mode*(): string =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_mode_string_Editor_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getContextWithMode_string_Editor_string_wasm(arg: cstring): cstring {.
    importc.}
proc getContextWithMode*(context: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getContextWithMode_string_Editor_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptRunAction_void_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptRunAction*(action: string; arg: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptRunAction_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptLog_void_string_wasm(arg: cstring): cstring {.importc.}
proc scriptLog*(message: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      message
    else:
      message.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptLog_void_string_wasm(argsJsonString.cstring)


proc editor_addCommandScript_void_Editor_string_string_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when string is JsonNode:
      keys
    else:
      keys.toJson()
  argsJson.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addCommandScript_void_Editor_string_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_removeCommand_void_Editor_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc removeCommand*(context: string; keys: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when string is JsonNode:
      keys
    else:
      keys.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_removeCommand_void_Editor_string_string_wasm(
      argsJsonString.cstring)


proc editor_getActivePopup_EditorId_wasm(arg: cstring): cstring {.importc.}
proc getActivePopup*(): EditorId =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActivePopup_EditorId_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getActiveEditor_EditorId_wasm(arg: cstring): cstring {.importc.}
proc getActiveEditor*(): EditorId =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActiveEditor_EditorId_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getActiveEditor2_EditorId_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc getActiveEditor2*(): EditorId =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActiveEditor2_EditorId_Editor_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_loadCurrentConfig_void_Editor_wasm(arg: cstring): cstring {.importc.}
proc loadCurrentConfig*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadCurrentConfig_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_sourceCurrentDocument_void_Editor_wasm(arg: cstring): cstring {.
    importc.}
proc sourceCurrentDocument*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_sourceCurrentDocument_void_Editor_wasm(
      argsJsonString.cstring)


proc editor_getEditor_EditorId_int_wasm(arg: cstring): cstring {.importc.}
proc getEditor*(index: int): EditorId =
  var argsJson = newJArray()
  argsJson.add block:
    when int is JsonNode:
      index
    else:
      index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getEditor_EditorId_int_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptIsTextEditor_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsTextEditor*(editorId: EditorId): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsTextEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptIsAstEditor_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsAstEditor*(editorId: EditorId): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsAstEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptIsModelEditor_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsModelEditor*(editorId: EditorId): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsModelEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptRunActionFor_void_EditorId_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when string is JsonNode:
      action
    else:
      action.toJson()
  argsJson.add block:
    when string is JsonNode:
      arg
    else:
      arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptRunActionFor_void_EditorId_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptInsertTextInto_void_EditorId_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptInsertTextInto_void_EditorId_string_wasm(
      argsJsonString.cstring)


proc editor_scriptTextEditorSelection_Selection_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptTextEditorSelection_Selection_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptSetTextEditorSelection_void_EditorId_Selection_wasm(
    arg: cstring): cstring {.importc.}
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when Selection is JsonNode:
      selection
    else:
      selection.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetTextEditorSelection_void_EditorId_Selection_wasm(
      argsJsonString.cstring)


proc editor_scriptTextEditorSelections_seq_Selection_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptTextEditorSelections_seq_Selection_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_wasm(
    arg: cstring): cstring {.importc.}
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when seq[Selection] is JsonNode:
      selections
    else:
      selections.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_wasm(
      argsJsonString.cstring)


proc editor_scriptGetTextEditorLine_string_EditorId_int_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when int is JsonNode:
      line
    else:
      line.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetTextEditorLine_string_EditorId_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptGetTextEditorLineCount_int_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetTextEditorLineCount_int_EditorId_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptGetOptionInt_int_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetOptionInt*(path: string; default: int): int =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when int is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetOptionInt_int_string_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptGetOptionFloat_float_string_float_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetOptionFloat*(path: string; default: float): float =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when float is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetOptionFloat_float_string_float_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptGetOptionBool_bool_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetOptionBool*(path: string; default: bool): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when bool is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetOptionBool_bool_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptGetOptionString_string_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetOptionString*(path: string; default: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when string is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetOptionString_string_string_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptSetOptionInt_void_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetOptionInt*(path: string; value: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when int is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetOptionInt_void_string_int_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionFloat_void_string_float_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetOptionFloat*(path: string; value: float) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when float is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetOptionFloat_void_string_float_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionBool_void_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetOptionBool*(path: string; value: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when bool is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetOptionBool_void_string_bool_wasm(
      argsJsonString.cstring)


proc editor_scriptSetOptionString_void_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetOptionString*(path: string; value: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when string is JsonNode:
      value
    else:
      value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetOptionString_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptSetCallback_void_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetCallback*(path: string; id: int) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when int is JsonNode:
      id
    else:
      id.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetCallback_void_string_int_wasm(
      argsJsonString.cstring)


proc editor_setRegisterText_void_Editor_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc setRegisterText*(text: string; register: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      text
    else:
      text.toJson()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setRegisterText_void_Editor_string_string_wasm(
      argsJsonString.cstring)

