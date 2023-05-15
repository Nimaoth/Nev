import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823711()
proc saveAppState*() =
  saveAppStateScript_2197823870()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824699(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824743(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824794(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824845(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824896(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825024()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825065(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825123(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825167(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825212(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825278(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825384(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825428(option, value)
proc quit*() =
  quitScript_2197825513()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825550(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825594(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825912()
proc createView*() =
  createViewScript_2197825949()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825991()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826073()
proc nextView*() =
  nextViewScript_2197826161()
proc prevView*() =
  prevViewScript_2197826204()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826250()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826310()
proc setLayout*(layout: string) =
  setLayoutScript_2197826367(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826447(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826495()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826536()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826706(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826769(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826844(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827014()
proc loadTheme*(name: string) =
  loadThemeScript_2197827051(name)
proc chooseTheme*() =
  chooseThemeScript_2197827131()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827764(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828058(token)
proc reloadConfig*() =
  reloadConfigScript_2197828102()
proc logOptions*() =
  logOptionsScript_2197828180()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828217(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828261()
proc setMode*(mode: string) =
  setModeScript222_2197828563(mode)
proc mode*(): string =
  modeScript222_2197828639()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828682(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828959(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828988(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829012(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829078(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829129()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829159()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829183()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829226()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829263()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829300(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829331(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829391(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829451(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829511(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829603(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829660(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829721(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829782(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829851(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829912(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829983(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830058(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830098(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830196(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830236(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830276(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830344(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830412(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830480(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830548(path, id)
