import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823661()
proc saveAppState*() =
  saveAppStateScript_2197823827()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824618(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824669(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824727(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824785(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824843(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197824978()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825026(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825091(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825142(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825194(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825267(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825380(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825431(option, value)
proc quit*() =
  quitScript_2197825523()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825567(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825618(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825943()
proc createView*() =
  createViewScript_2197825987()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826036()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826125()
proc nextView*() =
  nextViewScript_2197826220()
proc prevView*() =
  prevViewScript_2197826270()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826323()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826390()
proc setLayout*(layout: string) =
  setLayoutScript_2197826454(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826541(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826596()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826644()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826821(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826891(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197826973(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827141()
proc loadTheme*(name: string) =
  loadThemeScript_2197827185(name)
proc chooseTheme*() =
  chooseThemeScript_2197827272()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197828033(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828334(token)
proc reloadConfig*() =
  reloadConfigScript_2197828385()
proc logOptions*() =
  logOptionsScript_2197828470()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828514(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828565()
proc setMode*(mode: string) =
  setModeScript22_2197828874(mode)
proc mode*(): string =
  modeScript22_2197828957()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197829007(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829318(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829354(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829385(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829458(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829516()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829553()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829584()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829634()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829678()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829722(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829760(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829827(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829894(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829993(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830057(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830125(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830193(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830269(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830337(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830415(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830497(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830544(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830649(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830696(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830743(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830818(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830893(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830968(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197831043(path, id)
