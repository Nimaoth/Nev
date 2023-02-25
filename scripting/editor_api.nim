import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197824182()
proc saveAppState*() =
  saveAppStateScript_2197824348()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824554(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824605(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824663(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824721(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824779(context, value)
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197824837(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197824915(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197824970(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825026(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825099(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825212(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825263(option, value)
proc quit*() =
  quitScript_2197825355()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825399(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825450(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825775()
proc createView*() =
  createViewScript_2197825819()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825868()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825957()
proc nextView*() =
  nextViewScript_2197826052()
proc prevView*() =
  prevViewScript_2197826102()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826155()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826222()
proc setLayout*(layout: string) =
  setLayoutScript_2197826286(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826373(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826428()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826476()
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826532(path, app)
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826791(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826861(path)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197826924()
proc loadTheme*(name: string) =
  loadThemeScript_2197826968(name)
proc chooseTheme*() =
  chooseThemeScript_2197827055()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827779(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828121(token)
proc reloadConfig*() =
  reloadConfigScript_2197828172()
proc logOptions*() =
  logOptionsScript_2197828257()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828301(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828352()
proc setMode*(mode: string) =
  setModeScript22_2197828661(mode)
proc mode*(): string =
  modeScript22_2197828744()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828794(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829078(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829114(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829145(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829218(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829276()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829313()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829344()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829394()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829438()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829482(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829520(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829587(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829654(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829753(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829817(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829885(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829953(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830029(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830097(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830175(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830257(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830304(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830416(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830463(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830510(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830585(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830660(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830735(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830810(path, id)
