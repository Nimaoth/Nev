import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197824531()
proc saveAppState*() =
  saveAppStateScript_2197824697()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197825488(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197825539(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197825597(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197825655(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197825713(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825848()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825896(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825961(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197826012(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197826064(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197826137(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197826250(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197826301(option, value)
proc quit*() =
  quitScript_2197826393()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197826437(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197826488(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197826813()
proc createView*() =
  createViewScript_2197826857()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826906()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826995()
proc nextView*() =
  nextViewScript_2197827090()
proc prevView*() =
  prevViewScript_2197827140()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197827193()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197827260()
proc setLayout*(layout: string) =
  setLayoutScript_2197827324(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197827411(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197827466()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197827514()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197827673(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197827743(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197827825(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827993()
proc loadTheme*(name: string) =
  loadThemeScript_2197828037(name)
proc chooseTheme*() =
  chooseThemeScript_2197828124()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197828848(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197829146(token)
proc reloadConfig*() =
  reloadConfigScript_2197829197()
proc logOptions*() =
  logOptionsScript_2197829282()
proc clearCommands*(context: string) =
  clearCommandsScript_2197829326(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197829377()
proc setMode*(mode: string) =
  setModeScript22_2197829686(mode)
proc mode*(): string =
  modeScript22_2197829769()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197829819(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197830103(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197830139(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197830170(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197830243(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197830301()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197830338()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197830369()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197830419()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197830463()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197830507(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197830545(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197830612(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197830679(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197830778(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830842(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830910(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830978(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197831054(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197831122(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197831200(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197831282(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197831329(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197831434(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197831481(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197831528(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197831603(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197831678(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197831753(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197831828(path, id)
