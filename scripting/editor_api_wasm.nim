import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editor_reapplyConfigKeybindings_void_App_bool_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc reapplyConfigKeybindings*(app: bool = false; home: bool = false;
                               workspace: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      app
    else:
      app.toJson()
  argsJson.add block:
    when bool is JsonNode:
      home
    else:
      home.toJson()
  argsJson.add block:
    when bool is JsonNode:
      workspace
    else:
      workspace.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reapplyConfigKeybindings_void_App_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_splitView_void_App_wasm(arg: cstring): cstring {.importc.}
proc splitView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_splitView_void_App_wasm(argsJsonString.cstring)


proc editor_runExternalCommand_void_App_string_seq_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc runExternalCommand*(command: string; args: seq[string] = @[];
                         workingDir: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      command
    else:
      command.toJson()
  argsJson.add block:
    when seq[string] is JsonNode:
      args
    else:
      args.toJson()
  argsJson.add block:
    when string is JsonNode:
      workingDir
    else:
      workingDir.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_runExternalCommand_void_App_string_seq_string_string_wasm(
      argsJsonString.cstring)


proc editor_disableLogFrameTime_void_App_bool_wasm(arg: cstring): cstring {.
    importc.}
proc disableLogFrameTime*(disable: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      disable
    else:
      disable.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_disableLogFrameTime_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_enableDebugPrintAsyncAwaitStackTrace_void_App_bool_wasm(arg: cstring): cstring {.
    importc.}
proc enableDebugPrintAsyncAwaitStackTrace*(enable: bool) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      enable
    else:
      enable.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_enableDebugPrintAsyncAwaitStackTrace_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_showDebuggerView_void_App_wasm(arg: cstring): cstring {.importc.}
proc showDebuggerView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_showDebuggerView_void_App_wasm(
      argsJsonString.cstring)


proc editor_setLocationListFromCurrentPopup_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc setLocationListFromCurrentPopup*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLocationListFromCurrentPopup_void_App_wasm(
      argsJsonString.cstring)


proc editor_getBackend_Backend_App_wasm(arg: cstring): cstring {.importc.}
proc getBackend*(): Backend =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getBackend_Backend_App_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getHostOs_string_App_wasm(arg: cstring): cstring {.importc.}
proc getHostOs*(): string =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getHostOs_string_App_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_loadApplicationFile_Option_string_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc loadApplicationFile*(path: string): Option[string] =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadApplicationFile_Option_string_App_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_toggleShowDrawnNodes_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleShowDrawnNodes*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleShowDrawnNodes_void_App_wasm(
      argsJsonString.cstring)


proc editor_setMaxViews_void_App_int_bool_wasm(arg: cstring): cstring {.importc.}
proc setMaxViews*(maxViews: int; openExisting: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when int is JsonNode:
      maxViews
    else:
      maxViews.toJson()
  argsJson.add block:
    when bool is JsonNode:
      openExisting
    else:
      openExisting.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setMaxViews_void_App_int_bool_wasm(
      argsJsonString.cstring)


proc editor_saveAppState_void_App_wasm(arg: cstring): cstring {.importc.}
proc saveAppState*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_saveAppState_void_App_wasm(argsJsonString.cstring)


proc editor_requestRender_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc requestRender*(redrawEverything: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      redrawEverything
    else:
      redrawEverything.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_requestRender_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleInputs_void_App_string_bool_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_setHandleInputs_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleActions_void_App_string_bool_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_setHandleActions_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllActions_void_App_string_bool_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_setConsumeAllActions_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllInput_void_App_string_bool_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_setConsumeAllInput_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_clearWorkspaceCaches_void_App_wasm(arg: cstring): cstring {.importc.}
proc clearWorkspaceCaches*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearWorkspaceCaches_void_App_wasm(
      argsJsonString.cstring)


proc editor_openGithubWorkspace_void_App_string_string_string_wasm(arg: cstring): cstring {.
    importc.}
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
  let res {.used.} = editor_openGithubWorkspace_void_App_string_string_string_wasm(
      argsJsonString.cstring)


proc editor_openRemoteServerWorkspace_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc openRemoteServerWorkspace*(url: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      url
    else:
      url.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openRemoteServerWorkspace_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_callScriptAction_JsonNode_App_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc callScriptAction*(context: string; args: JsonNode): JsonNode =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      args
    else:
      args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_callScriptAction_JsonNode_App_string_JsonNode_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_addScriptAction_void_App_string_string_seq_tuple_name_string_typ_string_string_bool_string_wasm(
    arg: cstring): cstring {.importc.}
proc addScriptAction*(name: string; docs: string = "";
                      params: seq[tuple[name: string, typ: string]] = @[];
                      returnType: string = ""; active: bool = false;
                      context: string = "script") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  argsJson.add block:
    when string is JsonNode:
      docs
    else:
      docs.toJson()
  argsJson.add block:
    when seq[tuple[name: string, typ: string]] is JsonNode:
      params
    else:
      params.toJson()
  argsJson.add block:
    when string is JsonNode:
      returnType
    else:
      returnType.toJson()
  argsJson.add block:
    when bool is JsonNode:
      active
    else:
      active.toJson()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addScriptAction_void_App_string_string_seq_tuple_name_string_typ_string_string_bool_string_wasm(
      argsJsonString.cstring)


proc editor_openLocalWorkspace_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc openLocalWorkspace*(path: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openLocalWorkspace_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_getFlag_bool_App_string_bool_wasm(arg: cstring): cstring {.importc.}
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
  let res {.used.} = editor_getFlag_bool_App_string_bool_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_setFlag_void_App_string_bool_wasm(arg: cstring): cstring {.importc.}
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
  let res {.used.} = editor_setFlag_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_toggleFlag_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc toggleFlag*(flag: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      flag
    else:
      flag.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleFlag_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_setOption_void_App_string_JsonNode_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setOption*(option: string; value: JsonNode; override: bool = true) =
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
  argsJson.add block:
    when bool is JsonNode:
      override
    else:
      override.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setOption_void_App_string_JsonNode_bool_wasm(
      argsJsonString.cstring)


proc editor_quit_void_App_wasm(arg: cstring): cstring {.importc.}
proc quit*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_quit_void_App_wasm(argsJsonString.cstring)


proc editor_quitImmediately_void_App_int_wasm(arg: cstring): cstring {.importc.}
proc quitImmediately*(exitCode: int = 0) =
  var argsJson = newJArray()
  argsJson.add block:
    when int is JsonNode:
      exitCode
    else:
      exitCode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_quitImmediately_void_App_int_wasm(
      argsJsonString.cstring)


proc editor_help_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc help*(about: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      about
    else:
      about.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_help_void_App_string_wasm(argsJsonString.cstring)


proc editor_loadWorkspaceFile_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc loadWorkspaceFile*(path: string; callback: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when string is JsonNode:
      callback
    else:
      callback.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadWorkspaceFile_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_writeWorkspaceFile_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc writeWorkspaceFile*(path: string; content: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when string is JsonNode:
      content
    else:
      content.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_writeWorkspaceFile_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_changeFontSize_void_App_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeFontSize*(amount: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeFontSize_void_App_float32_wasm(
      argsJsonString.cstring)


proc editor_changeLineDistance_void_App_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeLineDistance*(amount: float32) =
  var argsJson = newJArray()
  argsJson.add block:
    when float32 is JsonNode:
      amount
    else:
      amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeLineDistance_void_App_float32_wasm(
      argsJsonString.cstring)


proc editor_platformTotalLineHeight_float32_App_wasm(arg: cstring): cstring {.
    importc.}
proc platformTotalLineHeight*(): float32 =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformTotalLineHeight_float32_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_platformLineHeight_float32_App_wasm(arg: cstring): cstring {.importc.}
proc platformLineHeight*(): float32 =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformLineHeight_float32_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_platformLineDistance_float32_App_wasm(arg: cstring): cstring {.
    importc.}
proc platformLineDistance*(): float32 =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformLineDistance_float32_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_changeLayoutProp_void_App_string_float32_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_changeLayoutProp_void_App_string_float32_wasm(
      argsJsonString.cstring)


proc editor_toggleStatusBarLocation_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc toggleStatusBarLocation*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleStatusBarLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_logs_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc logs*(scrollToBottom: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      scrollToBottom
    else:
      scrollToBottom.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logs_void_App_bool_wasm(argsJsonString.cstring)


proc editor_toggleConsoleLogger_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleConsoleLogger*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleConsoleLogger_void_App_wasm(
      argsJsonString.cstring)


proc editor_showEditor_void_App_EditorId_Option_int_wasm(arg: cstring): cstring {.
    importc.}
proc showEditor*(editorId: EditorId; viewIndex: Option[int] = int.none) =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  argsJson.add block:
    when Option[int] is JsonNode:
      viewIndex
    else:
      viewIndex.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_showEditor_void_App_EditorId_Option_int_wasm(
      argsJsonString.cstring)


proc editor_getVisibleEditors_seq_EditorId_App_wasm(arg: cstring): cstring {.
    importc.}
proc getVisibleEditors*(): seq[EditorId] =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getVisibleEditors_seq_EditorId_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getHiddenEditors_seq_EditorId_App_wasm(arg: cstring): cstring {.
    importc.}
proc getHiddenEditors*(): seq[EditorId] =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getHiddenEditors_seq_EditorId_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getExistingEditor_Option_EditorId_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getExistingEditor*(path: string): Option[EditorId] =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getExistingEditor_Option_EditorId_App_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getOrOpenEditor_Option_EditorId_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getOrOpenEditor*(path: string): Option[EditorId] =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getOrOpenEditor_Option_EditorId_App_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_closeView_void_App_int_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeView*(index: int; keepHidden: bool = true; restoreHidden: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when int is JsonNode:
      index
    else:
      index.toJson()
  argsJson.add block:
    when bool is JsonNode:
      keepHidden
    else:
      keepHidden.toJson()
  argsJson.add block:
    when bool is JsonNode:
      restoreHidden
    else:
      restoreHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeView_void_App_int_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_closeCurrentView_void_App_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeCurrentView*(keepHidden: bool = true; restoreHidden: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      keepHidden
    else:
      keepHidden.toJson()
  argsJson.add block:
    when bool is JsonNode:
      restoreHidden
    else:
      restoreHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeCurrentView_void_App_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_closeOtherViews_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc closeOtherViews*(keepHidden: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      keepHidden
    else:
      keepHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeOtherViews_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewToTop_void_App_wasm(arg: cstring): cstring {.importc.}
proc moveCurrentViewToTop*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewToTop_void_App_wasm(
      argsJsonString.cstring)


proc editor_nextView_void_App_wasm(arg: cstring): cstring {.importc.}
proc nextView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_nextView_void_App_wasm(argsJsonString.cstring)


proc editor_prevView_void_App_wasm(arg: cstring): cstring {.importc.}
proc prevView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_prevView_void_App_wasm(argsJsonString.cstring)


proc editor_toggleMaximizeView_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleMaximizeView*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleMaximizeView_void_App_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewPrev_void_App_wasm(arg: cstring): cstring {.importc.}
proc moveCurrentViewPrev*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewPrev_void_App_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewNext_void_App_wasm(arg: cstring): cstring {.importc.}
proc moveCurrentViewNext*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewNext_void_App_wasm(
      argsJsonString.cstring)


proc editor_setLayout_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc setLayout*(layout: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      layout
    else:
      layout.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLayout_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_commandLine_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc commandLine*(initialValue: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      initialValue
    else:
      initialValue.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_commandLine_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_exitCommandLine_void_App_wasm(arg: cstring): cstring {.importc.}
proc exitCommandLine*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exitCommandLine_void_App_wasm(argsJsonString.cstring)


proc editor_selectPreviousCommandInHistory_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc selectPreviousCommandInHistory*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_selectPreviousCommandInHistory_void_App_wasm(
      argsJsonString.cstring)


proc editor_selectNextCommandInHistory_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextCommandInHistory*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_selectNextCommandInHistory_void_App_wasm(
      argsJsonString.cstring)


proc editor_executeCommandLine_bool_App_wasm(arg: cstring): cstring {.importc.}
proc executeCommandLine*(): bool =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_executeCommandLine_bool_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_writeFile_void_App_string_bool_wasm(arg: cstring): cstring {.importc.}
proc writeFile*(path: string = ""; appFile: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when bool is JsonNode:
      appFile
    else:
      appFile.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_writeFile_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_loadFile_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc loadFile*(path: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadFile_void_App_string_wasm(argsJsonString.cstring)


proc editor_removeFromLocalStorage_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc removeFromLocalStorage*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_removeFromLocalStorage_void_App_wasm(
      argsJsonString.cstring)


proc editor_loadTheme_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc loadTheme*(name: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      name
    else:
      name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadTheme_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_chooseTheme_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseTheme*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseTheme_void_App_wasm(argsJsonString.cstring)


proc editor_createFile_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc createFile*(path: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_createFile_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_mountVfs_void_App_string_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc mountVfs*(parentPath: string; prefix: string; config: JsonNode) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      parentPath
    else:
      parentPath.toJson()
  argsJson.add block:
    when string is JsonNode:
      prefix
    else:
      prefix.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      config
    else:
      config.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_mountVfs_void_App_string_string_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_browseKeybinds_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc browseKeybinds*(preview: bool = true; scaleX: float = 0.9;
                     scaleY: float = 0.8; previewScale: float = 0.4) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      preview
    else:
      preview.toJson()
  argsJson.add block:
    when float is JsonNode:
      scaleX
    else:
      scaleX.toJson()
  argsJson.add block:
    when float is JsonNode:
      scaleY
    else:
      scaleY.toJson()
  argsJson.add block:
    when float is JsonNode:
      previewScale
    else:
      previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_browseKeybinds_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_chooseFile_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc chooseFile*(preview: bool = true; scaleX: float = 0.8; scaleY: float = 0.8;
                 previewScale: float = 0.5) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      preview
    else:
      preview.toJson()
  argsJson.add block:
    when float is JsonNode:
      scaleX
    else:
      scaleX.toJson()
  argsJson.add block:
    when float is JsonNode:
      scaleY
    else:
      scaleY.toJson()
  argsJson.add block:
    when float is JsonNode:
      previewScale
    else:
      previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseFile_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_openLastEditor_void_App_wasm(arg: cstring): cstring {.importc.}
proc openLastEditor*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openLastEditor_void_App_wasm(argsJsonString.cstring)


proc editor_chooseOpen_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc chooseOpen*(preview: bool = true; scaleX: float = 0.8; scaleY: float = 0.8;
                 previewScale: float = 0.6) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      preview
    else:
      preview.toJson()
  argsJson.add block:
    when float is JsonNode:
      scaleX
    else:
      scaleX.toJson()
  argsJson.add block:
    when float is JsonNode:
      scaleY
    else:
      scaleY.toJson()
  argsJson.add block:
    when float is JsonNode:
      previewScale
    else:
      previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseOpen_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_chooseOpenDocument_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseOpenDocument*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseOpenDocument_void_App_wasm(
      argsJsonString.cstring)


proc editor_gotoNextLocation_void_App_wasm(arg: cstring): cstring {.importc.}
proc gotoNextLocation*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_gotoNextLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_gotoPrevLocation_void_App_wasm(arg: cstring): cstring {.importc.}
proc gotoPrevLocation*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_gotoPrevLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_chooseLocation_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseLocation*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseLocation_void_App_wasm(argsJsonString.cstring)


proc editor_searchGlobalInteractive_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc searchGlobalInteractive*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_searchGlobalInteractive_void_App_wasm(
      argsJsonString.cstring)


proc editor_searchGlobal_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc searchGlobal*(query: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      query
    else:
      query.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_searchGlobal_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_installTreesitterParser_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc installTreesitterParser*(language: string; host: string = "github.com") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      language
    else:
      language.toJson()
  argsJson.add block:
    when string is JsonNode:
      host
    else:
      host.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_installTreesitterParser_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_chooseGitActiveFiles_void_App_bool_wasm(arg: cstring): cstring {.
    importc.}
proc chooseGitActiveFiles*(all: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      all
    else:
      all.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseGitActiveFiles_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_exploreFiles_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc exploreFiles*(root: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      root
    else:
      root.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreFiles_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_exploreUserConfigDir_void_App_wasm(arg: cstring): cstring {.importc.}
proc exploreUserConfigDir*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreUserConfigDir_void_App_wasm(
      argsJsonString.cstring)


proc editor_exploreAppConfigDir_void_App_wasm(arg: cstring): cstring {.importc.}
proc exploreAppConfigDir*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreAppConfigDir_void_App_wasm(
      argsJsonString.cstring)


proc editor_exploreHelp_void_App_wasm(arg: cstring): cstring {.importc.}
proc exploreHelp*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreHelp_void_App_wasm(argsJsonString.cstring)


proc editor_exploreWorkspacePrimary_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc exploreWorkspacePrimary*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreWorkspacePrimary_void_App_wasm(
      argsJsonString.cstring)


proc editor_exploreCurrentFileDirectory_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc exploreCurrentFileDirectory*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreCurrentFileDirectory_void_App_wasm(
      argsJsonString.cstring)


proc editor_openPreviousEditor_void_App_wasm(arg: cstring): cstring {.importc.}
proc openPreviousEditor*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openPreviousEditor_void_App_wasm(
      argsJsonString.cstring)


proc editor_openNextEditor_void_App_wasm(arg: cstring): cstring {.importc.}
proc openNextEditor*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openNextEditor_void_App_wasm(argsJsonString.cstring)


proc editor_setGithubAccessToken_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc setGithubAccessToken*(token: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      token
    else:
      token.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setGithubAccessToken_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_reloadConfig_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc reloadConfig*(clearOptions: bool = false) =
  var argsJson = newJArray()
  argsJson.add block:
    when bool is JsonNode:
      clearOptions
    else:
      clearOptions.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadConfig_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_reloadPlugin_void_App_wasm(arg: cstring): cstring {.importc.}
proc reloadPlugin*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadPlugin_void_App_wasm(argsJsonString.cstring)


proc editor_reloadState_void_App_wasm(arg: cstring): cstring {.importc.}
proc reloadState*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadState_void_App_wasm(argsJsonString.cstring)


proc editor_saveSession_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc saveSession*(sessionFile: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      sessionFile
    else:
      sessionFile.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_saveSession_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_logOptions_void_App_wasm(arg: cstring): cstring {.importc.}
proc logOptions*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logOptions_void_App_wasm(argsJsonString.cstring)


proc editor_dumpKeymapGraphViz_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc dumpKeymapGraphViz*(context: string = "") =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_dumpKeymapGraphViz_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_clearCommands_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc clearCommands*(context: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_getAllEditors_seq_EditorId_App_wasm(arg: cstring): cstring {.importc.}
proc getAllEditors*(): seq[EditorId] =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getAllEditors_seq_EditorId_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_setMode_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc setMode*(mode: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      mode
    else:
      mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setMode_void_App_string_wasm(argsJsonString.cstring)


proc editor_mode_string_App_wasm(arg: cstring): cstring {.importc.}
proc mode*(): string =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_mode_string_App_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_getContextWithMode_string_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getContextWithMode*(context: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getContextWithMode_string_App_string_wasm(
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


proc editor_changeAnimationSpeed_void_App_float_wasm(arg: cstring): cstring {.
    importc.}
proc changeAnimationSpeed*(factor: float) =
  var argsJson = newJArray()
  argsJson.add block:
    when float is JsonNode:
      factor
    else:
      factor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeAnimationSpeed_void_App_float_wasm(
      argsJsonString.cstring)


proc editor_setLeader_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc setLeader*(leader: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      leader
    else:
      leader.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLeader_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_setLeaders_void_App_seq_string_wasm(arg: cstring): cstring {.importc.}
proc setLeaders*(leaders: seq[string]) =
  var argsJson = newJArray()
  argsJson.add block:
    when seq[string] is JsonNode:
      leaders
    else:
      leaders.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLeaders_void_App_seq_string_wasm(
      argsJsonString.cstring)


proc editor_addLeader_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc addLeader*(leader: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      leader
    else:
      leader.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addLeader_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_registerPluginSourceCode_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc registerPluginSourceCode*(path: string; content: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when string is JsonNode:
      content
    else:
      content.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_registerPluginSourceCode_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_addCommandScript_void_App_string_string_string_string_string_string_tuple_filename_string_line_int_column_int_wasm(
    arg: cstring): cstring {.importc.}
proc addCommandScript*(context: string; subContext: string; keys: string;
                       action: string; arg: string = "";
                       description: string = ""; source: tuple[filename: string,
    line: int, column: int] = ("", 0, 0)) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      context
    else:
      context.toJson()
  argsJson.add block:
    when string is JsonNode:
      subContext
    else:
      subContext.toJson()
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
  argsJson.add block:
    when string is JsonNode:
      description
    else:
      description.toJson()
  argsJson.add block:
    when tuple[filename: string, line: int, column: int] is JsonNode:
      source
    else:
      source.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addCommandScript_void_App_string_string_string_string_string_string_tuple_filename_string_line_int_column_int_wasm(
      argsJsonString.cstring)


proc editor_removeCommand_void_App_string_string_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_removeCommand_void_App_string_string_wasm(
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


proc editor_getActiveEditor2_EditorId_App_wasm(arg: cstring): cstring {.importc.}
proc getActiveEditor2*(): EditorId =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActiveEditor2_EditorId_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_logRootNode_void_App_wasm(arg: cstring): cstring {.importc.}
proc logRootNode*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logRootNode_void_App_wasm(argsJsonString.cstring)


proc editor_sourceCurrentDocument_void_App_wasm(arg: cstring): cstring {.importc.}
proc sourceCurrentDocument*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_sourceCurrentDocument_void_App_wasm(
      argsJsonString.cstring)


proc editor_getEditorInView_EditorId_int_wasm(arg: cstring): cstring {.importc.}
proc getEditorInView*(index: int): EditorId =
  var argsJson = newJArray()
  argsJson.add block:
    when int is JsonNode:
      index
    else:
      index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getEditorInView_EditorId_int_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptIsSelectorPopup_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsSelectorPopup*(editorId: EditorId): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when EditorId is JsonNode:
      editorId
    else:
      editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsSelectorPopup_bool_EditorId_wasm(
      argsJsonString.cstring)
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


proc editor_setSessionDataJson_void_App_string_JsonNode_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setSessionDataJson*(path: string; value: JsonNode; override: bool = true) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      value
    else:
      value.toJson()
  argsJson.add block:
    when bool is JsonNode:
      override
    else:
      override.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setSessionDataJson_void_App_string_JsonNode_bool_wasm(
      argsJsonString.cstring)


proc editor_getSessionDataJson_JsonNode_App_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc getSessionDataJson*(path: string; default: JsonNode): JsonNode =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getSessionDataJson_JsonNode_App_string_JsonNode_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_scriptGetOptionJson_JsonNode_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc scriptGetOptionJson*(path: string; default: JsonNode): JsonNode =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      path
    else:
      path.toJson()
  argsJson.add block:
    when JsonNode is JsonNode:
      default
    else:
      default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptGetOptionJson_JsonNode_string_JsonNode_wasm(
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


proc editor_setRegisterText_void_App_string_string_wasm(arg: cstring): cstring {.
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
  let res {.used.} = editor_setRegisterText_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_getRegisterText_string_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getRegisterText*(register: string): string =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getRegisterText_string_App_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_startRecordingKeys_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc startRecordingKeys*(register: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_startRecordingKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_stopRecordingKeys_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc stopRecordingKeys*(register: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_stopRecordingKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_startRecordingCommands_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc startRecordingCommands*(register: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_startRecordingCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_stopRecordingCommands_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc stopRecordingCommands*(register: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_stopRecordingCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_isReplayingCommands_bool_App_wasm(arg: cstring): cstring {.importc.}
proc isReplayingCommands*(): bool =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_isReplayingCommands_bool_App_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_isReplayingKeys_bool_App_wasm(arg: cstring): cstring {.importc.}
proc isReplayingKeys*(): bool =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_isReplayingKeys_bool_App_wasm(argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_isRecordingCommands_bool_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc isRecordingCommands*(registry: string): bool =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      registry
    else:
      registry.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_isRecordingCommands_bool_App_string_wasm(
      argsJsonString.cstring)
  result = parseJson($res).jsonTo(typeof(result))


proc editor_replayCommands_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc replayCommands*(register: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_replayCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_replayKeys_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc replayKeys*(register: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      register
    else:
      register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_replayKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_inputKeys_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc inputKeys*(input: string) =
  var argsJson = newJArray()
  argsJson.add block:
    when string is JsonNode:
      input
    else:
      input.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_inputKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_collectGarbage_void_App_wasm(arg: cstring): cstring {.importc.}
proc collectGarbage*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_collectGarbage_void_App_wasm(argsJsonString.cstring)


proc editor_printStatistics_void_App_wasm(arg: cstring): cstring {.importc.}
proc printStatistics*() =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_printStatistics_void_App_wasm(argsJsonString.cstring)

