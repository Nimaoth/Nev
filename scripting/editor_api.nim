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
  requestRenderScript_2197824674(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824725(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824783(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824841(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824899(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825034()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825082(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825147(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825198(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825250(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825323(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825436(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825487(option, value)
proc quit*() =
  quitScript_2197825579()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825623(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825674(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825999()
proc createView*() =
  createViewScript_2197826043()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826092()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826181()
proc nextView*() =
  nextViewScript_2197826276()
proc prevView*() =
  prevViewScript_2197826326()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826379()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826446()
proc setLayout*(layout: string) =
  setLayoutScript_2197826510(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826597(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826652()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826700()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826877(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826947(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197827029(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827206()
proc loadTheme*(name: string) =
  loadThemeScript_2197827250(name)
proc chooseTheme*() =
  chooseThemeScript_2197827337()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827977(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828278(token)
proc reloadConfig*() =
  reloadConfigScript_2197828329()
proc logOptions*() =
  logOptionsScript_2197828414()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828458(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828509()
proc setMode*(mode: string) =
  setModeScript222_2197828818(mode)
proc mode*(): string =
  modeScript222_2197828901()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828951(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829235(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829271(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829302(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829375(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829433()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829470()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829501()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829551()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829595()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829639(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829677(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829744(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829811(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829878(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829977(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830041(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830109(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830177(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830253(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830321(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830399(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830481(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830528(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830633(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830680(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830727(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830802(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830877(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830952(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197831027(path, id)
