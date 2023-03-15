import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823666()
proc saveAppState*() =
  saveAppStateScript_2197823832()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824623(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824674(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824732(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824790(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824848(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197824983()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825031(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825096(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825147(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825199(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825272(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825385(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825436(option, value)
proc quit*() =
  quitScript_2197825528()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825572(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825623(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825948()
proc createView*() =
  createViewScript_2197825992()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826041()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826130()
proc nextView*() =
  nextViewScript_2197826225()
proc prevView*() =
  prevViewScript_2197826275()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826328()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826395()
proc setLayout*(layout: string) =
  setLayoutScript_2197826459(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826546(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826601()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826649()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826826(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826896(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826978(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827146()
proc loadTheme*(name: string) =
  loadThemeScript_2197827190(name)
proc chooseTheme*() =
  chooseThemeScript_2197827277()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827917(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828218(token)
proc reloadConfig*() =
  reloadConfigScript_2197828269()
proc logOptions*() =
  logOptionsScript_2197828354()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828398(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828449()
proc setMode*(mode: string) =
  setModeScript22_2197828758(mode)
proc mode*(): string =
  modeScript22_2197828841()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828891(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829175(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829211(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829242(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829315(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829373()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829410()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829441()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829491()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829535()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829579(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829617(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829684(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829751(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829850(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829914(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829982(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830050(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830126(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830194(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830272(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830354(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830401(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830506(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830553(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830600(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830675(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830750(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830825(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830900(path, id)
