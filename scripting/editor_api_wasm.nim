import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editor_getOptionJson_JsonNode_ConfigService_string_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc getOptionJson*(path: string; default: JsonNode): JsonNode {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getOptionJson_JsonNode_ConfigService_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_reapplyConfigKeybindings_void_App_bool_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc reapplyConfigKeybindings*(app: bool = false; home: bool = false;
                               workspace: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add app.toJson()
  argsJson.add home.toJson()
  argsJson.add workspace.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reapplyConfigKeybindings_void_App_bool_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_splitView_void_App_wasm(arg: cstring): cstring {.importc.}
proc splitView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_splitView_void_App_wasm(argsJsonString.cstring)


proc editor_runExternalCommand_void_App_string_seq_string_string_wasm(
    arg: cstring): cstring {.importc.}
proc runExternalCommand*(command: string; args: seq[string] = @[];
                         workingDir: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add command.toJson()
  argsJson.add args.toJson()
  argsJson.add workingDir.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_runExternalCommand_void_App_string_seq_string_string_wasm(
      argsJsonString.cstring)


proc editor_disableLogFrameTime_void_App_bool_wasm(arg: cstring): cstring {.
    importc.}
proc disableLogFrameTime*(disable: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add disable.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_disableLogFrameTime_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_enableDebugPrintAsyncAwaitStackTrace_void_App_bool_wasm(arg: cstring): cstring {.
    importc.}
proc enableDebugPrintAsyncAwaitStackTrace*(enable: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add enable.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_enableDebugPrintAsyncAwaitStackTrace_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_showDebuggerView_void_App_wasm(arg: cstring): cstring {.importc.}
proc showDebuggerView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_showDebuggerView_void_App_wasm(
      argsJsonString.cstring)


proc editor_setLocationListFromCurrentPopup_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc setLocationListFromCurrentPopup*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLocationListFromCurrentPopup_void_App_wasm(
      argsJsonString.cstring)


proc editor_getBackend_Backend_App_wasm(arg: cstring): cstring {.importc.}
proc getBackend*(): Backend {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getBackend_Backend_App_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getHostOs_string_App_wasm(arg: cstring): cstring {.importc.}
proc getHostOs*(): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getHostOs_string_App_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_loadApplicationFile_Option_string_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc loadApplicationFile*(path: string): Option[string] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadApplicationFile_Option_string_App_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_toggleShowDrawnNodes_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleShowDrawnNodes*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleShowDrawnNodes_void_App_wasm(
      argsJsonString.cstring)


proc editor_setMaxViews_void_App_int_bool_wasm(arg: cstring): cstring {.importc.}
proc setMaxViews*(maxViews: int; openExisting: bool = false) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add maxViews.toJson()
  argsJson.add openExisting.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setMaxViews_void_App_int_bool_wasm(
      argsJsonString.cstring)


proc editor_saveAppState_void_App_wasm(arg: cstring): cstring {.importc.}
proc saveAppState*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_saveAppState_void_App_wasm(argsJsonString.cstring)


proc editor_requestRender_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc requestRender*(redrawEverything: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add redrawEverything.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_requestRender_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleInputs_void_App_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setHandleInputs*(context: string; value: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setHandleInputs_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setHandleActions_void_App_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setHandleActions*(context: string; value: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setHandleActions_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllActions_void_App_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setConsumeAllActions*(context: string; value: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setConsumeAllActions_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_setConsumeAllInput_void_App_string_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setConsumeAllInput*(context: string; value: bool) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add value.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setConsumeAllInput_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_clearWorkspaceCaches_void_App_wasm(arg: cstring): cstring {.importc.}
proc clearWorkspaceCaches*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearWorkspaceCaches_void_App_wasm(
      argsJsonString.cstring)


proc editor_callScriptAction_JsonNode_App_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc callScriptAction*(context: string; args: JsonNode): JsonNode {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_callScriptAction_JsonNode_App_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_addScriptAction_void_App_string_string_seq_tuple_name_string_typ_string_string_bool_string_wasm(
    arg: cstring): cstring {.importc.}
proc addScriptAction*(name: string; docs: string = "";
                      params: seq[tuple[name: string, typ: string]] = @[];
                      returnType: string = ""; active: bool = false;
                      context: string = "script") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  argsJson.add docs.toJson()
  argsJson.add params.toJson()
  argsJson.add returnType.toJson()
  argsJson.add active.toJson()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addScriptAction_void_App_string_string_seq_tuple_name_string_typ_string_string_bool_string_wasm(
      argsJsonString.cstring)


proc editor_openLocalWorkspace_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc openLocalWorkspace*(path: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openLocalWorkspace_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_quit_void_App_wasm(arg: cstring): cstring {.importc.}
proc quit*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_quit_void_App_wasm(argsJsonString.cstring)


proc editor_quitImmediately_void_App_int_wasm(arg: cstring): cstring {.importc.}
proc quitImmediately*(exitCode: int = 0) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add exitCode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_quitImmediately_void_App_int_wasm(
      argsJsonString.cstring)


proc editor_help_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc help*(about: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add about.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_help_void_App_string_wasm(argsJsonString.cstring)


proc editor_loadWorkspaceFile_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc loadWorkspaceFile*(path: string; callback: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add callback.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadWorkspaceFile_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_writeWorkspaceFile_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc writeWorkspaceFile*(path: string; content: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add content.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_writeWorkspaceFile_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_changeFontSize_void_App_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeFontSize*(amount: float32) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeFontSize_void_App_float32_wasm(
      argsJsonString.cstring)


proc editor_changeLineDistance_void_App_float32_wasm(arg: cstring): cstring {.
    importc.}
proc changeLineDistance*(amount: float32) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add amount.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeLineDistance_void_App_float32_wasm(
      argsJsonString.cstring)


proc editor_platformTotalLineHeight_float32_App_wasm(arg: cstring): cstring {.
    importc.}
proc platformTotalLineHeight*(): float32 {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformTotalLineHeight_float32_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_platformLineHeight_float32_App_wasm(arg: cstring): cstring {.importc.}
proc platformLineHeight*(): float32 {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformLineHeight_float32_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_platformLineDistance_float32_App_wasm(arg: cstring): cstring {.
    importc.}
proc platformLineDistance*(): float32 {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformLineDistance_float32_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_toggleStatusBarLocation_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc toggleStatusBarLocation*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleStatusBarLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_logs_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc logs*(scrollToBottom: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add scrollToBottom.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logs_void_App_bool_wasm(argsJsonString.cstring)


proc editor_toggleConsoleLogger_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleConsoleLogger*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleConsoleLogger_void_App_wasm(
      argsJsonString.cstring)


proc editor_showEditor_void_App_EditorId_Option_int_wasm(arg: cstring): cstring {.
    importc.}
proc showEditor*(editorId: EditorId; viewIndex: Option[int] = int.none) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  argsJson.add viewIndex.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_showEditor_void_App_EditorId_Option_int_wasm(
      argsJsonString.cstring)


proc editor_getVisibleEditors_seq_EditorId_App_wasm(arg: cstring): cstring {.
    importc.}
proc getVisibleEditors*(): seq[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getVisibleEditors_seq_EditorId_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getHiddenEditors_seq_EditorId_App_wasm(arg: cstring): cstring {.
    importc.}
proc getHiddenEditors*(): seq[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getHiddenEditors_seq_EditorId_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getExistingEditor_Option_EditorId_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getExistingEditor*(path: string): Option[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getExistingEditor_Option_EditorId_App_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getOrOpenEditor_Option_EditorId_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getOrOpenEditor*(path: string): Option[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getOrOpenEditor_Option_EditorId_App_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_closeView_void_App_int_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeView*(index: int; keepHidden: bool = true; restoreHidden: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add index.toJson()
  argsJson.add keepHidden.toJson()
  argsJson.add restoreHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeView_void_App_int_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_closeCurrentView_void_App_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc closeCurrentView*(keepHidden: bool = true; restoreHidden: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add keepHidden.toJson()
  argsJson.add restoreHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeCurrentView_void_App_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_closeOtherViews_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc closeOtherViews*(keepHidden: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add keepHidden.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_closeOtherViews_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewToTop_void_App_wasm(arg: cstring): cstring {.importc.}
proc moveCurrentViewToTop*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewToTop_void_App_wasm(
      argsJsonString.cstring)


proc editor_nextView_void_App_wasm(arg: cstring): cstring {.importc.}
proc nextView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_nextView_void_App_wasm(argsJsonString.cstring)


proc editor_prevView_void_App_wasm(arg: cstring): cstring {.importc.}
proc prevView*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_prevView_void_App_wasm(argsJsonString.cstring)


proc editor_moveCurrentViewPrev_void_App_wasm(arg: cstring): cstring {.importc.}
proc moveCurrentViewPrev*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewPrev_void_App_wasm(
      argsJsonString.cstring)


proc editor_moveCurrentViewNext_void_App_wasm(arg: cstring): cstring {.importc.}
proc moveCurrentViewNext*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_moveCurrentViewNext_void_App_wasm(
      argsJsonString.cstring)


proc editor_commandLine_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc commandLine*(initialValue: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add initialValue.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_commandLine_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_exitCommandLine_void_App_wasm(arg: cstring): cstring {.importc.}
proc exitCommandLine*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exitCommandLine_void_App_wasm(argsJsonString.cstring)


proc editor_selectPreviousCommandInHistory_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc selectPreviousCommandInHistory*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_selectPreviousCommandInHistory_void_App_wasm(
      argsJsonString.cstring)


proc editor_selectNextCommandInHistory_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc selectNextCommandInHistory*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_selectNextCommandInHistory_void_App_wasm(
      argsJsonString.cstring)


proc editor_executeCommandLine_bool_App_wasm(arg: cstring): cstring {.importc.}
proc executeCommandLine*(): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_executeCommandLine_bool_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_writeFile_void_App_string_bool_wasm(arg: cstring): cstring {.importc.}
proc writeFile*(path: string = ""; appFile: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add appFile.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_writeFile_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_loadFile_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc loadFile*(path: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadFile_void_App_string_wasm(argsJsonString.cstring)


proc editor_loadTheme_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc loadTheme*(name: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadTheme_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_chooseTheme_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseTheme*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseTheme_void_App_wasm(argsJsonString.cstring)


proc editor_createFile_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc createFile*(path: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_createFile_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_mountVfs_void_App_string_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc mountVfs*(parentPath: string; prefix: string; config: JsonNode) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add parentPath.toJson()
  argsJson.add prefix.toJson()
  argsJson.add config.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_mountVfs_void_App_string_string_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_browseKeybinds_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc browseKeybinds*(preview: bool = true; scaleX: float = 0.9;
                     scaleY: float = 0.8; previewScale: float = 0.4) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add preview.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_browseKeybinds_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_chooseFile_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc chooseFile*(preview: bool = true; scaleX: float = 0.8; scaleY: float = 0.8;
                 previewScale: float = 0.5) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add preview.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseFile_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_openLastEditor_void_App_wasm(arg: cstring): cstring {.importc.}
proc openLastEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openLastEditor_void_App_wasm(argsJsonString.cstring)


proc editor_chooseOpen_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc chooseOpen*(preview: bool = true; scaleX: float = 0.8; scaleY: float = 0.8;
                 previewScale: float = 0.6) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add preview.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseOpen_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_chooseOpenDocument_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseOpenDocument*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseOpenDocument_void_App_wasm(
      argsJsonString.cstring)


proc editor_gotoNextLocation_void_App_wasm(arg: cstring): cstring {.importc.}
proc gotoNextLocation*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_gotoNextLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_gotoPrevLocation_void_App_wasm(arg: cstring): cstring {.importc.}
proc gotoPrevLocation*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_gotoPrevLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_chooseLocation_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseLocation*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseLocation_void_App_wasm(argsJsonString.cstring)


proc editor_searchGlobalInteractive_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc searchGlobalInteractive*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_searchGlobalInteractive_void_App_wasm(
      argsJsonString.cstring)


proc editor_searchGlobal_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc searchGlobal*(query: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add query.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_searchGlobal_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_installTreesitterParser_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc installTreesitterParser*(language: string; host: string = "github.com") {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add language.toJson()
  argsJson.add host.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_installTreesitterParser_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_exploreFiles_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc exploreFiles*(root: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add root.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreFiles_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_exploreUserConfigDir_void_App_wasm(arg: cstring): cstring {.importc.}
proc exploreUserConfigDir*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreUserConfigDir_void_App_wasm(
      argsJsonString.cstring)


proc editor_exploreAppConfigDir_void_App_wasm(arg: cstring): cstring {.importc.}
proc exploreAppConfigDir*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreAppConfigDir_void_App_wasm(
      argsJsonString.cstring)


proc editor_exploreHelp_void_App_wasm(arg: cstring): cstring {.importc.}
proc exploreHelp*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreHelp_void_App_wasm(argsJsonString.cstring)


proc editor_exploreWorkspacePrimary_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc exploreWorkspacePrimary*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreWorkspacePrimary_void_App_wasm(
      argsJsonString.cstring)


proc editor_exploreCurrentFileDirectory_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc exploreCurrentFileDirectory*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreCurrentFileDirectory_void_App_wasm(
      argsJsonString.cstring)


proc editor_openPreviousEditor_void_App_wasm(arg: cstring): cstring {.importc.}
proc openPreviousEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openPreviousEditor_void_App_wasm(
      argsJsonString.cstring)


proc editor_openNextEditor_void_App_wasm(arg: cstring): cstring {.importc.}
proc openNextEditor*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openNextEditor_void_App_wasm(argsJsonString.cstring)


proc editor_setGithubAccessToken_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc setGithubAccessToken*(token: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add token.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setGithubAccessToken_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_reloadConfig_void_App_bool_wasm(arg: cstring): cstring {.importc.}
proc reloadConfig*(clearOptions: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add clearOptions.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadConfig_void_App_bool_wasm(
      argsJsonString.cstring)


proc editor_reloadPlugin_void_App_wasm(arg: cstring): cstring {.importc.}
proc reloadPlugin*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadPlugin_void_App_wasm(argsJsonString.cstring)


proc editor_reloadState_void_App_wasm(arg: cstring): cstring {.importc.}
proc reloadState*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadState_void_App_wasm(argsJsonString.cstring)


proc editor_saveSession_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc saveSession*(sessionFile: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add sessionFile.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_saveSession_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_dumpKeymapGraphViz_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc dumpKeymapGraphViz*(context: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_dumpKeymapGraphViz_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_clearCommands_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc clearCommands*(context: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_getAllEditors_seq_EditorId_App_wasm(arg: cstring): cstring {.importc.}
proc getAllEditors*(): seq[EditorId] {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getAllEditors_seq_EditorId_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_setMode_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc setMode*(mode: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add mode.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setMode_void_App_string_wasm(argsJsonString.cstring)


proc editor_mode_string_App_wasm(arg: cstring): cstring {.importc.}
proc mode*(): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_mode_string_App_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getContextWithMode_string_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getContextWithMode*(context: string): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getContextWithMode_string_App_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptRunAction_void_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptRunAction*(action: string; arg: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add action.toJson()
  argsJson.add arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptRunAction_void_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptLog_void_string_wasm(arg: cstring): cstring {.importc.}
proc scriptLog*(message: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add message.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptLog_void_string_wasm(argsJsonString.cstring)


proc editor_changeAnimationSpeed_void_App_float_wasm(arg: cstring): cstring {.
    importc.}
proc changeAnimationSpeed*(factor: float) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add factor.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_changeAnimationSpeed_void_App_float_wasm(
      argsJsonString.cstring)


proc editor_setLeader_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc setLeader*(leader: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leader.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLeader_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_setLeaders_void_App_seq_string_wasm(arg: cstring): cstring {.importc.}
proc setLeaders*(leaders: seq[string]) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leaders.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setLeaders_void_App_seq_string_wasm(
      argsJsonString.cstring)


proc editor_addLeader_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc addLeader*(leader: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add leader.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addLeader_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_registerPluginSourceCode_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc registerPluginSourceCode*(path: string; content: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add content.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_registerPluginSourceCode_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_addCommandScript_void_App_string_string_string_string_string_string_tuple_filename_string_line_int_column_int_wasm(
    arg: cstring): cstring {.importc.}
proc addCommandScript*(context: string; subContext: string; keys: string;
                       action: string; arg: string = "";
                       description: string = ""; source: tuple[filename: string,
    line: int, column: int] = ("", 0, 0)) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add subContext.toJson()
  argsJson.add keys.toJson()
  argsJson.add action.toJson()
  argsJson.add arg.toJson()
  argsJson.add description.toJson()
  argsJson.add source.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_addCommandScript_void_App_string_string_string_string_string_string_tuple_filename_string_line_int_column_int_wasm(
      argsJsonString.cstring)


proc editor_removeCommand_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc removeCommand*(context: string; keys: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add context.toJson()
  argsJson.add keys.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_removeCommand_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_getActivePopup_EditorId_wasm(arg: cstring): cstring {.importc.}
proc getActivePopup*(): EditorId {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActivePopup_EditorId_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getActiveEditor_EditorId_wasm(arg: cstring): cstring {.importc.}
proc getActiveEditor*(): EditorId {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActiveEditor_EditorId_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_logRootNode_void_App_wasm(arg: cstring): cstring {.importc.}
proc logRootNode*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logRootNode_void_App_wasm(argsJsonString.cstring)


proc editor_getEditorInView_EditorId_int_wasm(arg: cstring): cstring {.importc.}
proc getEditorInView*(index: int): EditorId {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add index.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getEditorInView_EditorId_int_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptIsSelectorPopup_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsSelectorPopup*(editorId: EditorId): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsSelectorPopup_bool_EditorId_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptIsTextEditor_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsTextEditor*(editorId: EditorId): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsTextEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptIsAstEditor_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsAstEditor*(editorId: EditorId): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsAstEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptIsModelEditor_bool_EditorId_wasm(arg: cstring): cstring {.
    importc.}
proc scriptIsModelEditor*(editorId: EditorId): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptIsModelEditor_bool_EditorId_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptRunActionFor_void_EditorId_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  argsJson.add action.toJson()
  argsJson.add arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptRunActionFor_void_EditorId_string_string_wasm(
      argsJsonString.cstring)


proc editor_scriptInsertTextInto_void_EditorId_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptInsertTextInto*(editorId: EditorId; text: string) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add editorId.toJson()
  argsJson.add text.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptInsertTextInto_void_EditorId_string_wasm(
      argsJsonString.cstring)


proc editor_setSessionDataJson_void_App_string_JsonNode_bool_wasm(arg: cstring): cstring {.
    importc.}
proc setSessionDataJson*(path: string; value: JsonNode; override: bool = true) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add value.toJson()
  argsJson.add override.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setSessionDataJson_void_App_string_JsonNode_bool_wasm(
      argsJsonString.cstring)


proc editor_getSessionDataJson_JsonNode_App_string_JsonNode_wasm(arg: cstring): cstring {.
    importc.}
proc getSessionDataJson*(path: string; default: JsonNode): JsonNode {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getSessionDataJson_JsonNode_App_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptSetCallback_void_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetCallback*(path: string; id: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add id.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetCallback_void_string_int_wasm(
      argsJsonString.cstring)


proc editor_setRegisterText_void_App_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc setRegisterText*(text: string; register: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add text.toJson()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_setRegisterText_void_App_string_string_wasm(
      argsJsonString.cstring)


proc editor_getRegisterText_string_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc getRegisterText*(register: string): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getRegisterText_string_App_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_startRecordingKeys_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc startRecordingKeys*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_startRecordingKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_stopRecordingKeys_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc stopRecordingKeys*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_stopRecordingKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_startRecordingCommands_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc startRecordingCommands*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_startRecordingCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_stopRecordingCommands_void_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc stopRecordingCommands*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_stopRecordingCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_isReplayingCommands_bool_App_wasm(arg: cstring): cstring {.importc.}
proc isReplayingCommands*(): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_isReplayingCommands_bool_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_isReplayingKeys_bool_App_wasm(arg: cstring): cstring {.importc.}
proc isReplayingKeys*(): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_isReplayingKeys_bool_App_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_isRecordingCommands_bool_App_string_wasm(arg: cstring): cstring {.
    importc.}
proc isRecordingCommands*(registry: string): bool {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add registry.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_isRecordingCommands_bool_App_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except:
    raiseAssert(getCurrentExceptionMsg())


proc editor_replayCommands_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc replayCommands*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_replayCommands_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_replayKeys_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc replayKeys*(register: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add register.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_replayKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_inputKeys_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc inputKeys*(input: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add input.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_inputKeys_void_App_string_wasm(
      argsJsonString.cstring)


proc editor_collectGarbage_void_App_wasm(arg: cstring): cstring {.importc.}
proc collectGarbage*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_collectGarbage_void_App_wasm(argsJsonString.cstring)


proc editor_printStatistics_void_App_wasm(arg: cstring): cstring {.importc.}
proc printStatistics*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_printStatistics_void_App_wasm(argsJsonString.cstring)

