import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823655()
proc saveAppState*() =
  saveAppStateScript_2197823821()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824612(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824663(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824721(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824779(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824837(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197824972()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825020(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825085(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825136(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825188(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825261(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825374(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825425(option, value)
proc quit*() =
  quitScript_2197825517()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825561(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825612(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825937()
proc createView*() =
  createViewScript_2197825981()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826030()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826119()
proc nextView*() =
  nextViewScript_2197826214()
proc prevView*() =
  prevViewScript_2197826264()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826317()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826384()
proc setLayout*(layout: string) =
  setLayoutScript_2197826448(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826535(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826590()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826638()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826797(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826867(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826949(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827117()
proc loadTheme*(name: string) =
  loadThemeScript_2197827161(name)
proc chooseTheme*() =
  chooseThemeScript_2197827248()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197828009(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828310(token)
proc reloadConfig*() =
  reloadConfigScript_2197828361()
proc logOptions*() =
  logOptionsScript_2197828446()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828490(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828541()
proc setMode*(mode: string) =
  setModeScript22_2197828850(mode)
proc mode*(): string =
  modeScript22_2197828933()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828983(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829267(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829303(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829334(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829407(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829465()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829502()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829533()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829583()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829627()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829671(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829709(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829776(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829843(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829942(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830006(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830074(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830142(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830218(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830286(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830364(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830446(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830493(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830598(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830645(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830692(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830767(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830842(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830917(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830992(path, id)
