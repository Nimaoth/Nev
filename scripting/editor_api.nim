import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  editor_getBackend_Backend_Editor_impl()
proc saveAppState*() =
  editor_saveAppState_void_Editor_impl()
proc requestRender*(redrawEverything: bool = false) =
  editor_requestRender_void_Editor_bool_impl(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  editor_setHandleInputs_void_Editor_string_bool_impl(context, value)
proc setHandleActions*(context: string; value: bool) =
  editor_setHandleActions_void_Editor_string_bool_impl(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  editor_setConsumeAllActions_void_Editor_string_bool_impl(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  editor_setConsumeAllInput_void_Editor_string_bool_impl(context, value)
proc clearWorkspaceCaches*() =
  editor_clearWorkspaceCaches_void_Editor_impl()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  editor_openGithubWorkspace_void_Editor_string_string_string_impl(user,
      repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  editor_openAbsytreeServerWorkspace_void_Editor_string_impl(url)
proc openLocalWorkspace*(path: string) =
  editor_openLocalWorkspace_void_Editor_string_impl(path)
proc getFlag*(flag: string; default: bool = false): bool =
  editor_getFlag_bool_Editor_string_bool_impl(flag, default)
proc setFlag*(flag: string; value: bool) =
  editor_setFlag_void_Editor_string_bool_impl(flag, value)
proc toggleFlag*(flag: string) =
  editor_toggleFlag_void_Editor_string_impl(flag)
proc setOption*(option: string; value: JsonNode) =
  editor_setOption_void_Editor_string_JsonNode_impl(option, value)
proc quit*() =
  editor_quit_void_Editor_impl()
proc changeFontSize*(amount: float32) =
  editor_changeFontSize_void_Editor_float32_impl(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  editor_changeLayoutProp_void_Editor_string_float32_impl(prop, change)
proc toggleStatusBarLocation*() =
  editor_toggleStatusBarLocation_void_Editor_impl()
proc createView*() =
  editor_createView_void_Editor_impl()
proc closeCurrentView*() =
  editor_closeCurrentView_void_Editor_impl()
proc moveCurrentViewToTop*() =
  editor_moveCurrentViewToTop_void_Editor_impl()
proc nextView*() =
  editor_nextView_void_Editor_impl()
proc prevView*() =
  editor_prevView_void_Editor_impl()
proc moveCurrentViewPrev*() =
  editor_moveCurrentViewPrev_void_Editor_impl()
proc moveCurrentViewNext*() =
  editor_moveCurrentViewNext_void_Editor_impl()
proc setLayout*(layout: string) =
  editor_setLayout_void_Editor_string_impl(layout)
proc commandLine*(initialValue: string = "") =
  editor_commandLine_void_Editor_string_impl(initialValue)
proc exitCommandLine*() =
  editor_exitCommandLine_void_Editor_impl()
proc executeCommandLine*(): bool =
  editor_executeCommandLine_bool_Editor_impl()
proc writeFile*(path: string = ""; app: bool = false) =
  editor_writeFile_void_Editor_string_bool_impl(path, app)
proc loadFile*(path: string = "") =
  editor_loadFile_void_Editor_string_impl(path)
proc openFile*(path: string; app: bool = false) =
  editor_openFile_void_Editor_string_bool_impl(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  editor_removeFromLocalStorage_void_Editor_impl()
proc loadTheme*(name: string) =
  editor_loadTheme_void_Editor_string_impl(name)
proc chooseTheme*() =
  editor_chooseTheme_void_Editor_impl()
proc chooseFile*(view: string = "new") =
  editor_chooseFile_void_Editor_string_impl(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  editor_setGithubAccessToken_void_Editor_string_impl(token)
proc reloadConfig*() =
  editor_reloadConfig_void_Editor_impl()
proc logOptions*() =
  editor_logOptions_void_Editor_impl()
proc clearCommands*(context: string) =
  editor_clearCommands_void_Editor_string_impl(context)
proc getAllEditors*(): seq[EditorId] =
  editor_getAllEditors_seq_EditorId_Editor_impl()
proc setMode*(mode: string) =
  editor_setMode_void_Editor_string_impl(mode)
proc mode*(): string =
  editor_mode_string_Editor_impl()
proc getContextWithMode*(context: string): string =
  editor_getContextWithMode_string_Editor_string_impl(context)
proc scriptRunAction*(action: string; arg: string) =
  editor_scriptRunAction_void_string_string_impl(action, arg)
proc scriptLog*(message: string) =
  editor_scriptLog_void_string_impl(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  editor_addCommandScript_void_Editor_string_string_string_string_impl(context,
      keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  editor_removeCommand_void_Editor_string_string_impl(context, keys)
proc getActivePopup*(): EditorId =
  editor_getActivePopup_EditorId_impl()
proc getActiveEditor*(): EditorId =
  editor_getActiveEditor_EditorId_impl()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  editor_getActiveEditor2_EditorId_Editor_impl()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  editor_loadCurrentConfig_void_Editor_impl()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  editor_sourceCurrentDocument_void_Editor_impl()
proc getEditor*(index: int): EditorId =
  editor_getEditor_EditorId_int_impl(index)
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
  editor_setRegisterText_void_Editor_string_string_impl(text, register)
