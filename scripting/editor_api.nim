import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_1946165457()
proc saveAppState*() =
  saveAppStateScript_1946165616()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_1946166445(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_1946166489(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_1946166540(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_1946166591(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_1946166642(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_1946166770()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_1946166811(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_1946166869(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_1946166913(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_1946166958(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_1946167024(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_1946167130(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_1946167174(option, value)
proc quit*() =
  quitScript_1946167259()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_1946167296(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_1946167340(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_1946167658()
proc createView*() =
  createViewScript_1946167695()
proc closeCurrentView*() =
  closeCurrentViewScript_1946167737()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_1946167819()
proc nextView*() =
  nextViewScript_1946167907()
proc prevView*() =
  prevViewScript_1946167950()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_1946167996()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_1946168056()
proc setLayout*(layout: string) =
  setLayoutScript_1946168113(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_1946168193(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_1946168241()
proc executeCommandLine*(): bool =
  executeCommandLineScript_1946168282()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_1946168452(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_1946168515(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_1946168590(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_1946168760()
proc loadTheme*(name: string) =
  loadThemeScript_1946168797(name)
proc chooseTheme*() =
  chooseThemeScript_1946168877()
proc chooseFile*(view: string = "new") =
  chooseFileScript_1946169539(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_1946169833(token)
proc reloadConfig*() =
  reloadConfigScript_1946169877()
proc logOptions*() =
  logOptionsScript_1946169955()
proc clearCommands*(context: string) =
  clearCommandsScript_1946169992(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_1946170036()
proc setMode*(mode: string) =
  setModeScript222_1946170338(mode)
proc mode*(): string =
  modeScript222_1946170414()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_1946170457(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_1946170734(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_1946170763(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_1946170787(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_1946170853(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_1946170904()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_1946170934()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_1946170958()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_1946171001()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_1946171038()
proc getEditor*(index: int): EditorId =
  getEditorScript_1946171075(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_1946171106(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_1946171166(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_1946171226(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_1946171286(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_1946171378(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_1946171435(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_1946171496(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_1946171557(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_1946171626(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_1946171687(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_1946171758(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_1946171833(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_1946171873(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_1946171971(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_1946172011(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_1946172051(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_1946172119(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_1946172187(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_1946172255(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_1946172323(path, id)
