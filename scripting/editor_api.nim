import std/[json, options]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc reapplyConfigKeybindings*(app: bool = false; home: bool = false;
                               workspace: bool = false) =
  editor_reapplyConfigKeybindings_void_App_bool_bool_bool_impl(app, home,
      workspace)
proc splitView*() =
  editor_splitView_void_App_impl()
proc disableLogFrameTime*(disable: bool) =
  editor_disableLogFrameTime_void_App_bool_impl(disable)
proc showDebuggerView*() =
  editor_showDebuggerView_void_App_impl()
proc setLocationListFromCurrentPopup*() =
  editor_setLocationListFromCurrentPopup_void_App_impl()
proc getBackend*(): Backend =
  editor_getBackend_Backend_App_impl()
proc getHostOs*(): string =
  editor_getHostOs_string_App_impl()
proc loadApplicationFile*(path: string): Option[string] =
  ## Load a file from the application directory (path is relative to the executable)
  editor_loadApplicationFile_Option_string_App_string_impl(path)
proc toggleShowDrawnNodes*() =
  editor_toggleShowDrawnNodes_void_App_impl()
proc setMaxViews*(maxViews: int; openExisting: bool = false) =
  ## Set the maximum number of views that can be open at the same time
  ## Closes any views that exceed the new limit
  editor_setMaxViews_void_App_int_bool_impl(maxViews, openExisting)
proc saveAppState*() =
  editor_saveAppState_void_App_impl()
proc requestRender*(redrawEverything: bool = false) =
  editor_requestRender_void_App_bool_impl(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  editor_setHandleInputs_void_App_string_bool_impl(context, value)
proc setHandleActions*(context: string; value: bool) =
  editor_setHandleActions_void_App_string_bool_impl(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  editor_setConsumeAllActions_void_App_string_bool_impl(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  editor_setConsumeAllInput_void_App_string_bool_impl(context, value)
proc clearWorkspaceCaches*() =
  editor_clearWorkspaceCaches_void_App_impl()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  editor_openGithubWorkspace_void_App_string_string_string_impl(user,
      repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  editor_openAbsytreeServerWorkspace_void_App_string_impl(url)
proc callScriptAction*(context: string; args: JsonNode): JsonNode =
  editor_callScriptAction_JsonNode_App_string_JsonNode_impl(context, args)
proc addScriptAction*(name: string; docs: string = "";
                      params: seq[tuple[name: string, typ: string]] = @[];
                      returnType: string = ""; active: bool = false;
                      context: string = "script") =
  editor_addScriptAction_void_App_string_string_seq_tuple_name_string_typ_string_string_bool_string_impl(
      name, docs, params, returnType, active, context)
proc openLocalWorkspace*(path: string) =
  editor_openLocalWorkspace_void_App_string_impl(path)
proc getFlag*(flag: string; default: bool = false): bool =
  editor_getFlag_bool_App_string_bool_impl(flag, default)
proc setFlag*(flag: string; value: bool) =
  editor_setFlag_void_App_string_bool_impl(flag, value)
proc toggleFlag*(flag: string) =
  editor_toggleFlag_void_App_string_impl(flag)
proc setOption*(option: string; value: JsonNode; override: bool = true) =
  editor_setOption_void_App_string_JsonNode_bool_impl(option, value, override)
proc quit*() =
  editor_quit_void_App_impl()
proc help*(about: string = "") =
  editor_help_void_App_string_impl(about)
proc loadWorkspaceFile*(path: string; callback: string) =
  editor_loadWorkspaceFile_void_App_string_string_impl(path, callback)
proc writeWorkspaceFile*(path: string; content: string) =
  editor_writeWorkspaceFile_void_App_string_string_impl(path, content)
proc changeFontSize*(amount: float32) =
  editor_changeFontSize_void_App_float32_impl(amount)
proc changeLineDistance*(amount: float32) =
  editor_changeLineDistance_void_App_float32_impl(amount)
proc platformTotalLineHeight*(): float32 =
  editor_platformTotalLineHeight_float32_App_impl()
proc platformLineHeight*(): float32 =
  editor_platformLineHeight_float32_App_impl()
proc platformLineDistance*(): float32 =
  editor_platformLineDistance_float32_App_impl()
proc changeLayoutProp*(prop: string; change: float32) =
  editor_changeLayoutProp_void_App_string_float32_impl(prop, change)
proc toggleStatusBarLocation*() =
  editor_toggleStatusBarLocation_void_App_impl()
proc logs*() =
  editor_logs_void_App_impl()
proc toggleConsoleLogger*() =
  editor_toggleConsoleLogger_void_App_impl()
proc showEditor*(editorId: EditorId; viewIndex: Option[int] = int.none) =
  ## Make the given editor visible
  ## If viewIndex is none, the editor will be opened in the currentView,
  ## Otherwise the editor will be opened in the view with the given index.
  editor_showEditor_void_App_EditorId_Option_int_impl(editorId, viewIndex)
proc getVisibleEditors*(): seq[EditorId] =
  ## Returns a list of all editors which are currently shown
  editor_getVisibleEditors_seq_EditorId_App_impl()
proc getHiddenEditors*(): seq[EditorId] =
  ## Returns a list of all editors which are currently hidden
  editor_getHiddenEditors_seq_EditorId_App_impl()
proc getExistingEditor*(path: string): Option[EditorId] =
  ## Returns an existing editor for the given file if one exists,
  ## or none otherwise.
  editor_getExistingEditor_Option_EditorId_App_string_impl(path)
proc getOrOpenEditor*(path: string): Option[EditorId] =
  ## Returns an existing editor for the given file if one exists,
  ## otherwise a new editor is created for the file.
  ## The returned editor will not be shown automatically.
  editor_getOrOpenEditor_Option_EditorId_App_string_impl(path)
proc closeView*(index: int; keepHidden: bool = true; restoreHidden: bool = true) =
  ## Closes the current view. If `keepHidden` is true the view is not closed but hidden instead.
  editor_closeView_void_App_int_bool_bool_impl(index, keepHidden, restoreHidden)
proc closeCurrentView*(keepHidden: bool = true; restoreHidden: bool = true) =
  editor_closeCurrentView_void_App_bool_bool_impl(keepHidden, restoreHidden)
proc closeOtherViews*(keepHidden: bool = true) =
  ## Closes all views except for the current one. If `keepHidden` is true the views are not closed but hidden instead.
  editor_closeOtherViews_void_App_bool_impl(keepHidden)
proc closeEditor*(path: string) =
  editor_closeEditor_void_App_string_impl(path)
proc moveCurrentViewToTop*() =
  editor_moveCurrentViewToTop_void_App_impl()
proc nextView*() =
  editor_nextView_void_App_impl()
proc prevView*() =
  editor_prevView_void_App_impl()
proc toggleMaximizeView*() =
  editor_toggleMaximizeView_void_App_impl()
proc moveCurrentViewPrev*() =
  editor_moveCurrentViewPrev_void_App_impl()
proc moveCurrentViewNext*() =
  editor_moveCurrentViewNext_void_App_impl()
proc setLayout*(layout: string) =
  editor_setLayout_void_App_string_impl(layout)
proc commandLine*(initialValue: string = "") =
  editor_commandLine_void_App_string_impl(initialValue)
proc exitCommandLine*() =
  editor_exitCommandLine_void_App_impl()
proc selectPreviousCommandInHistory*() =
  editor_selectPreviousCommandInHistory_void_App_impl()
proc selectNextCommandInHistory*() =
  editor_selectNextCommandInHistory_void_App_impl()
proc executeCommandLine*(): bool =
  editor_executeCommandLine_bool_App_impl()
proc writeFile*(path: string = ""; appFile: bool = false) =
  editor_writeFile_void_App_string_bool_impl(path, appFile)
proc loadFile*(path: string = "") =
  editor_loadFile_void_App_string_impl(path)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  editor_removeFromLocalStorage_void_App_impl()
proc loadTheme*(name: string) =
  editor_loadTheme_void_App_string_impl(name)
proc chooseTheme*() =
  editor_chooseTheme_void_App_impl()
proc createFile*(path: string) =
  editor_createFile_void_App_string_impl(path)
proc browseKeybinds*() =
  editor_browseKeybinds_void_App_impl()
proc chooseFile*() =
  ## Opens a file dialog which shows all files in the currently open workspaces
  ## Press <ENTER> to select a file
  ## Press <ESCAPE> to close the dialogue
  editor_chooseFile_void_App_impl()
proc chooseOpen*() =
  editor_chooseOpen_void_App_impl()
proc chooseOpenDocument*() =
  editor_chooseOpenDocument_void_App_impl()
proc gotoNextLocation*() =
  editor_gotoNextLocation_void_App_impl()
proc gotoPrevLocation*() =
  editor_gotoPrevLocation_void_App_impl()
proc chooseLocation*() =
  editor_chooseLocation_void_App_impl()
proc searchGlobalInteractive*() =
  editor_searchGlobalInteractive_void_App_impl()
proc searchGlobal*(query: string) =
  editor_searchGlobal_void_App_string_impl(query)
proc chooseGitActiveFiles*(all: bool = false) =
  editor_chooseGitActiveFiles_void_App_bool_impl(all)
proc exploreFiles*(root: string = "") =
  editor_exploreFiles_void_App_string_impl(root)
proc exploreUserConfigDir*() =
  editor_exploreUserConfigDir_void_App_impl()
proc exploreAppConfigDir*() =
  editor_exploreAppConfigDir_void_App_impl()
proc exploreHelp*() =
  editor_exploreHelp_void_App_impl()
proc exploreWorkspacePrimary*() =
  editor_exploreWorkspacePrimary_void_App_impl()
proc exploreCurrentFileDirectory*() =
  editor_exploreCurrentFileDirectory_void_App_impl()
proc openPreviousEditor*() =
  editor_openPreviousEditor_void_App_impl()
proc openNextEditor*() =
  editor_openNextEditor_void_App_impl()
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  editor_setGithubAccessToken_void_App_string_impl(token)
proc reloadConfig*(clearOptions: bool = false) =
  ## Reloads settings.json and keybindings.json from the app directory, home directory and workspace
  editor_reloadConfig_void_App_bool_impl(clearOptions)
proc reloadPlugin*() =
  editor_reloadPlugin_void_App_impl()
proc reloadState*() =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  editor_reloadState_void_App_impl()
proc saveSession*(sessionFile: string = "") =
  ## Reloads some of the state stored in the session file (default: config/config.json)
  editor_saveSession_void_App_string_impl(sessionFile)
proc logOptions*() =
  editor_logOptions_void_App_impl()
proc clearCommands*(context: string) =
  editor_clearCommands_void_App_string_impl(context)
proc getAllEditors*(): seq[EditorId] =
  editor_getAllEditors_seq_EditorId_App_impl()
proc setMode*(mode: string) =
  editor_setMode_void_App_string_impl(mode)
proc mode*(): string =
  editor_mode_string_App_impl()
proc getContextWithMode*(context: string): string =
  editor_getContextWithMode_string_App_string_impl(context)
proc scriptRunAction*(action: string; arg: string) =
  editor_scriptRunAction_void_string_string_impl(action, arg)
proc scriptLog*(message: string) =
  editor_scriptLog_void_string_impl(message)
proc changeAnimationSpeed*(factor: float) =
  editor_changeAnimationSpeed_void_App_float_impl(factor)
proc setLeader*(leader: string) =
  editor_setLeader_void_App_string_impl(leader)
proc setLeaders*(leaders: seq[string]) =
  editor_setLeaders_void_App_seq_string_impl(leaders)
proc addLeader*(leader: string) =
  editor_addLeader_void_App_string_impl(leader)
proc addCommandScript*(context: string; subContext: string; keys: string;
                       action: string; arg: string = "";
                       description: string = "") =
  editor_addCommandScript_void_App_string_string_string_string_string_string_impl(
      context, subContext, keys, action, arg, description)
proc removeCommand*(context: string; keys: string) =
  editor_removeCommand_void_App_string_string_impl(context, keys)
proc getActivePopup*(): EditorId =
  editor_getActivePopup_EditorId_impl()
proc getActiveEditor*(): EditorId =
  editor_getActiveEditor_EditorId_impl()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  editor_getActiveEditor2_EditorId_App_impl()
proc loadCurrentConfig*() =
  ## Opens the default config file in a new view.
  editor_loadCurrentConfig_void_App_impl()
proc logRootNode*() =
  editor_logRootNode_void_App_impl()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  editor_sourceCurrentDocument_void_App_impl()
proc getEditorInView*(index: int): EditorId =
  editor_getEditorInView_EditorId_int_impl(index)
proc scriptIsSelectorPopup*(editorId: EditorId): bool =
  editor_scriptIsSelectorPopup_bool_EditorId_impl(editorId)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  editor_scriptIsTextEditor_bool_EditorId_impl(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  editor_scriptIsAstEditor_bool_EditorId_impl(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  editor_scriptIsModelEditor_bool_EditorId_impl(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  editor_scriptRunActionFor_void_EditorId_string_string_impl(editorId, action,
      arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  editor_scriptInsertTextInto_void_EditorId_string_impl(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  editor_scriptTextEditorSelection_Selection_EditorId_impl(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  editor_scriptSetTextEditorSelection_void_EditorId_Selection_impl(editorId,
      selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  editor_scriptTextEditorSelections_seq_Selection_EditorId_impl(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  editor_scriptSetTextEditorSelections_void_EditorId_seq_Selection_impl(
      editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  editor_scriptGetTextEditorLine_string_EditorId_int_impl(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  editor_scriptGetTextEditorLineCount_int_EditorId_impl(editorId)
proc setSessionDataJson*(path: string; value: JsonNode; override: bool = true) =
  editor_setSessionDataJson_void_App_string_JsonNode_bool_impl(path, value,
      override)
proc getSessionDataJson*(path: string; default: JsonNode): JsonNode =
  editor_getSessionDataJson_JsonNode_App_string_JsonNode_impl(path, default)
proc scriptGetOptionJson*(path: string; default: JsonNode): JsonNode =
  editor_scriptGetOptionJson_JsonNode_string_JsonNode_impl(path, default)
proc scriptGetOptionInt*(path: string; default: int): int =
  editor_scriptGetOptionInt_int_string_int_impl(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  editor_scriptGetOptionFloat_float_string_float_impl(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  editor_scriptGetOptionBool_bool_string_bool_impl(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  editor_scriptGetOptionString_string_string_string_impl(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  editor_scriptSetOptionInt_void_string_int_impl(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  editor_scriptSetOptionFloat_void_string_float_impl(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  editor_scriptSetOptionBool_void_string_bool_impl(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  editor_scriptSetOptionString_void_string_string_impl(path, value)
proc scriptSetCallback*(path: string; id: int) =
  editor_scriptSetCallback_void_string_int_impl(path, id)
proc setRegisterText*(text: string; register: string = "") =
  editor_setRegisterText_void_App_string_string_impl(text, register)
proc getRegisterText*(register: string): string =
  editor_getRegisterText_string_App_string_impl(register)
proc startRecordingKeys*(register: string) =
  editor_startRecordingKeys_void_App_string_impl(register)
proc stopRecordingKeys*(register: string) =
  editor_stopRecordingKeys_void_App_string_impl(register)
proc startRecordingCommands*(register: string) =
  editor_startRecordingCommands_void_App_string_impl(register)
proc stopRecordingCommands*(register: string) =
  editor_stopRecordingCommands_void_App_string_impl(register)
proc isReplayingCommands*(): bool =
  editor_isReplayingCommands_bool_App_impl()
proc isReplayingKeys*(): bool =
  editor_isReplayingKeys_bool_App_impl()
proc isRecordingCommands*(registry: string): bool =
  editor_isRecordingCommands_bool_App_string_impl(registry)
proc replayCommands*(register: string) =
  editor_replayCommands_void_App_string_impl(register)
proc replayKeys*(register: string) =
  editor_replayKeys_void_App_string_impl(register)
proc inputKeys*(input: string) =
  editor_inputKeys_void_App_string_impl(input)
proc collectGarbage*() =
  editor_collectGarbage_void_App_impl()
proc printStatistics*() =
  editor_printStatistics_void_App_impl()
