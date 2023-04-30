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
  saveAppStateScript_2197823831()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824660(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824704(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824755(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824806(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824857(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197824985()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825026(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825084(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825128(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825173(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825239(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825345(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825389(option, value)
proc quit*() =
  quitScript_2197825474()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825511(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825555(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825873()
proc createView*() =
  createViewScript_2197825910()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825952()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826034()
proc nextView*() =
  nextViewScript_2197826122()
proc prevView*() =
  prevViewScript_2197826165()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826211()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826271()
proc setLayout*(layout: string) =
  setLayoutScript_2197826328(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826408(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826456()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826497()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826667(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826730(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826805(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197826975()
proc loadTheme*(name: string) =
  loadThemeScript_2197827012(name)
proc chooseTheme*() =
  chooseThemeScript_2197827092()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827725(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828019(token)
proc reloadConfig*() =
  reloadConfigScript_2197828063()
proc logOptions*() =
  logOptionsScript_2197828141()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828178(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828222()
proc setMode*(mode: string) =
  setModeScript222_2197828524(mode)
proc mode*(): string =
  modeScript222_2197828600()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828643(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828920(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828949(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197828973(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829039(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829090()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829120()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829144()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829187()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829224()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829261(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829292(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829352(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829412(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829472(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829564(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829621(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829682(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829743(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829812(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829873(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829944(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830019(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830059(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830157(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830197(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830237(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830305(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830373(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830441(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830509(path, id)
