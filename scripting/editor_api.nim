import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823672()
proc saveAppState*() =
  saveAppStateScript_2197823838()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824629(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824680(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824738(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824796(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824854(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197824989()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825037(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825102(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825153(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825205(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825278(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825391(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825442(option, value)
proc quit*() =
  quitScript_2197825534()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825578(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825629(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825954()
proc createView*() =
  createViewScript_2197825998()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826047()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826136()
proc nextView*() =
  nextViewScript_2197826231()
proc prevView*() =
  prevViewScript_2197826281()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826334()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826401()
proc setLayout*(layout: string) =
  setLayoutScript_2197826465(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826552(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826607()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826655()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826832(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826902(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826984(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827161()
proc loadTheme*(name: string) =
  loadThemeScript_2197827205(name)
proc chooseTheme*() =
  chooseThemeScript_2197827292()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827932(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828233(token)
proc reloadConfig*() =
  reloadConfigScript_2197828284()
proc logOptions*() =
  logOptionsScript_2197828369()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828413(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828464()
proc setMode*(mode: string) =
  setModeScript222_2197828773(mode)
proc mode*(): string =
  modeScript222_2197828856()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828906(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829190(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829226(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829257(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829330(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829388()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829425()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829456()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829506()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829550()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829594(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829632(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829699(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829766(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829833(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829932(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829996(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830064(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830132(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830208(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830276(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830354(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830436(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830483(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830588(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830635(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830682(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830757(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830832(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830907(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830982(path, id)
