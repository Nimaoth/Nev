import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823697()
proc saveAppState*() =
  saveAppStateScript_2197823856()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824685(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824729(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824780(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824831(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824882(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825010()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825051(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825109(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825153(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825198(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825264(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825370(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825414(option, value)
proc quit*() =
  quitScript_2197825499()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825536(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825580(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825898()
proc createView*() =
  createViewScript_2197825935()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825977()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826059()
proc nextView*() =
  nextViewScript_2197826147()
proc prevView*() =
  prevViewScript_2197826190()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826236()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826296()
proc setLayout*(layout: string) =
  setLayoutScript_2197826353(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826433(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826481()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826522()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826692(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826755(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826830(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827000()
proc loadTheme*(name: string) =
  loadThemeScript_2197827037(name)
proc chooseTheme*() =
  chooseThemeScript_2197827117()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827750(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828044(token)
proc reloadConfig*() =
  reloadConfigScript_2197828088()
proc logOptions*() =
  logOptionsScript_2197828166()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828203(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828247()
proc setMode*(mode: string) =
  setModeScript222_2197828549(mode)
proc mode*(): string =
  modeScript222_2197828625()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828668(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828945(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828974(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197828998(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829064(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829115()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829145()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829169()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829212()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829249()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829286(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829317(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829377(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829437(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829497(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829589(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829646(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829707(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829768(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829837(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829898(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829969(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830044(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830084(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830182(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830222(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830262(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830330(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830398(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830466(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830534(path, id)
