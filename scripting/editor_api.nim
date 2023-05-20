import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
elif defined(wasm):
  # import absytree_internal_wasm
  discard
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823683()
proc saveAppState*() =
  saveAppStateScript_2197823854()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824706(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824763(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824828(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824893(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824958(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825100()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825157(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825234(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825291(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825349(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825429(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825555(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825612(option, value)
proc quit*() =
  quitScript_2197825716()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825765(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825822(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197826154()
proc createView*() =
  createViewScript_2197826203()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826285()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826379()
proc nextView*() =
  nextViewScript_2197826479()
proc prevView*() =
  prevViewScript_2197826534()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826592()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826664()
proc setLayout*(layout: string) =
  setLayoutScript_2197826733(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826826(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826887()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826940()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197827122(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197827199(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197827287(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827471()
proc loadTheme*(name: string) =
  loadThemeScript_2197827520(name)
proc chooseTheme*() =
  chooseThemeScript_2197827613()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197828311(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828874(token)
proc reloadConfig*() =
  reloadConfigScript_2197828931()
proc logOptions*() =
  logOptionsScript_2197829022()
proc clearCommands*(context: string) =
  clearCommandsScript_2197829071(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197829128()
proc setMode*(mode: string) =
  setModeScript222_2197829453(mode)
proc mode*(): string =
  modeScript222_2197829568()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197829623(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829913(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829955(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829991(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197830073(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197830138()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197830179()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197830214()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197830269()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197830318()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197830367(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197830410(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197830482(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197830554(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197830626(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197830732(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830802(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830879(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830953(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197831034(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197831108(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197831192(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197831279(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197831333(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197831445(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197831499(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197831553(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197831640(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197831727(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197831814(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197831901(path, id)
