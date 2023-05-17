import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823692()
proc saveAppState*() =
  saveAppStateScript_2197823851()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824680(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824724(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824775(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824826(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824877(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825005()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825046(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825104(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825148(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825193(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825259(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825365(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825409(option, value)
proc quit*() =
  quitScript_2197825494()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825531(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825575(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825893()
proc createView*() =
  createViewScript_2197825930()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825972()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826054()
proc nextView*() =
  nextViewScript_2197826142()
proc prevView*() =
  prevViewScript_2197826185()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826231()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826291()
proc setLayout*(layout: string) =
  setLayoutScript_2197826348(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826428(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826476()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826517()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826687(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826750(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826825(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197826995()
proc loadTheme*(name: string) =
  loadThemeScript_2197827032(name)
proc chooseTheme*() =
  chooseThemeScript_2197827112()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827745(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828039(token)
proc reloadConfig*() =
  reloadConfigScript_2197828083()
proc logOptions*() =
  logOptionsScript_2197828161()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828198(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828242()
proc setMode*(mode: string) =
  setModeScript222_2197828544(mode)
proc mode*(): string =
  modeScript222_2197828620()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828663(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828940(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828969(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197828993(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829059(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829110()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829140()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829164()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829207()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829244()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829281(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829312(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829372(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829432(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829492(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829584(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829641(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829702(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829763(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829832(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829893(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829964(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830039(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830079(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830177(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830217(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830257(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830325(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830393(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830461(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830529(path, id)
