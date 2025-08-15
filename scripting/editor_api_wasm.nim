import std/[json, options]
import scripting_api, misc/myjsonutils

## This file is auto generated, don't modify.


proc editor_getOptionJson_JsonNode_ConfigService_string_JsonNode_wasm(
    arg: cstring): cstring {.importc.}
proc getOptionJson*(path: string; default: JsonNode = newJNull()): JsonNode {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add default.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getOptionJson_JsonNode_ConfigService_string_JsonNode_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_reapplyConfigKeybindings_void_App_bool_bool_bool_bool_wasm(
    arg: cstring): cstring {.importc.}
proc reapplyConfigKeybindings*(app: bool = false; home: bool = false;
                               workspace: bool = false; wait: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add app.toJson()
  argsJson.add home.toJson()
  argsJson.add workspace.toJson()
  argsJson.add wait.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reapplyConfigKeybindings_void_App_bool_bool_bool_bool_wasm(
      argsJsonString.cstring)


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
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getHostOs_string_App_wasm(arg: cstring): cstring {.importc.}
proc getHostOs*(): string {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getHostOs_string_App_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_toggleShowDrawnNodes_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleShowDrawnNodes*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleShowDrawnNodes_void_App_wasm(
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


proc editor_clearWorkspaceCaches_void_App_wasm(arg: cstring): cstring {.importc.}
proc clearWorkspaceCaches*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_clearWorkspaceCaches_void_App_wasm(
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
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_platformLineHeight_float32_App_wasm(arg: cstring): cstring {.importc.}
proc platformLineHeight*(): float32 {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_platformLineHeight_float32_App_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
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
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_toggleStatusBarLocation_void_App_wasm(arg: cstring): cstring {.
    importc.}
proc toggleStatusBarLocation*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleStatusBarLocation_void_App_wasm(
      argsJsonString.cstring)


proc editor_logs_void_App_string_bool_bool_wasm(arg: cstring): cstring {.importc.}
proc logs*(slot: string = ""; focus: bool = true; scrollToBottom: bool = false) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add slot.toJson()
  argsJson.add focus.toJson()
  argsJson.add scrollToBottom.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logs_void_App_string_bool_bool_wasm(
      argsJsonString.cstring)


proc editor_toggleConsoleLogger_void_App_wasm(arg: cstring): cstring {.importc.}
proc toggleConsoleLogger*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_toggleConsoleLogger_void_App_wasm(
      argsJsonString.cstring)


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


proc editor_loadTheme_void_App_string_bool_wasm(arg: cstring): cstring {.importc.}
proc loadTheme*(name: string; force: bool = false) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add name.toJson()
  argsJson.add force.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_loadTheme_void_App_string_bool_wasm(
      argsJsonString.cstring)


proc editor_openSession_void_App_string_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc openSession*(root: string = "home://"; preview: bool = true;
                  scaleX: float = 0.9; scaleY: float = 0.8;
                  previewScale: float = 0.4) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add root.toJson()
  argsJson.add preview.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openSession_void_App_string_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_openRecentSession_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc openRecentSession*(preview: bool = true; scaleX: float = 0.9;
                        scaleY: float = 0.8; previewScale: float = 0.4) {.
    gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add preview.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_openRecentSession_void_App_bool_float_float_float_wasm(
      argsJsonString.cstring)


proc editor_chooseTheme_void_App_wasm(arg: cstring): cstring {.importc.}
proc chooseTheme*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_chooseTheme_void_App_wasm(argsJsonString.cstring)


proc editor_crash_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc crash*(message: string = "") {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add message.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_crash_void_App_string_wasm(argsJsonString.cstring)


proc editor_crash2_void_App_wasm(arg: cstring): cstring {.importc.}
proc crash2*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_crash2_void_App_wasm(argsJsonString.cstring)


proc editor_createFile_void_App_string_wasm(arg: cstring): cstring {.importc.}
proc createFile*(path: string) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_createFile_void_App_string_wasm(
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


proc editor_browseSettings_void_App_bool_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc browseSettings*(includeActiveEditor: bool = false; scaleX: float = 0.8;
                     scaleY: float = 0.8; previewScale: float = 0.5) {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add includeActiveEditor.toJson()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_browseSettings_void_App_bool_float_float_float_wasm(
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


proc editor_showPlugins_void_App_float_float_float_wasm(arg: cstring): cstring {.
    importc.}
proc showPlugins*(scaleX: float = 0.9; scaleY: float = 0.9;
                  previewScale: float = 0.6) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add scaleX.toJson()
  argsJson.add scaleY.toJson()
  argsJson.add previewScale.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_showPlugins_void_App_float_float_float_wasm(
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


proc editor_exploreFiles_void_App_string_bool_bool_wasm(arg: cstring): cstring {.
    importc.}
proc exploreFiles*(root: string = ""; showVFS: bool = false;
                   normalize: bool = true) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add root.toJson()
  argsJson.add showVFS.toJson()
  argsJson.add normalize.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_exploreFiles_void_App_string_bool_bool_wasm(
      argsJsonString.cstring)


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


proc editor_reloadTheme_void_App_wasm(arg: cstring): cstring {.importc.}
proc reloadTheme*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_reloadTheme_void_App_wasm(argsJsonString.cstring)


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
  except CatchableError:
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
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_scriptRunAction_JsonNode_string_string_wasm(arg: cstring): cstring {.
    importc.}
proc scriptRunAction*(action: string; arg: string): JsonNode {.gcsafe,
    raises: [].} =
  var argsJson = newJArray()
  argsJson.add action.toJson()
  argsJson.add arg.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptRunAction_JsonNode_string_string_wasm(
      argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


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


proc editor_getActivePopup_EditorId_wasm(arg: cstring): cstring {.importc.}
proc getActivePopup*(): EditorId {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActivePopup_EditorId_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_getActiveEditor_EditorId_wasm(arg: cstring): cstring {.importc.}
proc getActiveEditor*(): EditorId {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_getActiveEditor_EditorId_wasm(argsJsonString.cstring)
  try:
    result = parseJson($res).jsonTo(typeof(result))
  except CatchableError:
    raiseAssert(getCurrentExceptionMsg())


proc editor_logRootNode_void_App_wasm(arg: cstring): cstring {.importc.}
proc logRootNode*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_logRootNode_void_App_wasm(argsJsonString.cstring)


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
  except CatchableError:
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
  except CatchableError:
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
  except CatchableError:
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


proc editor_scriptSetCallback_void_string_int_wasm(arg: cstring): cstring {.
    importc.}
proc scriptSetCallback*(path: string; id: int) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add path.toJson()
  argsJson.add id.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_scriptSetCallback_void_string_int_wasm(
      argsJsonString.cstring)


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


proc editor_echoArgs_void_App_JsonNode_wasm(arg: cstring): cstring {.importc.}
proc echoArgs*(args: JsonNode) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_echoArgs_void_App_JsonNode_wasm(
      argsJsonString.cstring)


proc editor_all_void_App_JsonNode_wasm(arg: cstring): cstring {.importc.}
proc all*(args: JsonNode) {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  argsJson.add args.toJson()
  let argsJsonString = $argsJson
  let res {.used.} = editor_all_void_App_JsonNode_wasm(argsJsonString.cstring)


proc editor_printStatistics_void_App_wasm(arg: cstring): cstring {.importc.}
proc printStatistics*() {.gcsafe, raises: [].} =
  var argsJson = newJArray()
  let argsJsonString = $argsJson
  let res {.used.} = editor_printStatistics_void_App_wasm(argsJsonString.cstring)

