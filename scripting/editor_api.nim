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
  requestRenderScript_2197824682(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824733(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824791(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824849(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824907(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825042()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825090(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825155(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197825206(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197825258(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825331(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825444(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825495(option, value)
proc quit*() =
  quitScript_2197825587()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825631(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825682(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197826007()
proc createView*() =
  createViewScript_2197826051()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826100()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826189()
proc nextView*() =
  nextViewScript_2197826284()
proc prevView*() =
  prevViewScript_2197826334()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826387()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826454()
proc setLayout*(layout: string) =
  setLayoutScript_2197826518(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826605(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826660()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826708()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197826885(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197826955(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197827037(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827214()
proc loadTheme*(name: string) =
  loadThemeScript_2197827258(name)
proc chooseTheme*() =
  chooseThemeScript_2197827345()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827985(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197828286(token)
proc reloadConfig*() =
  reloadConfigScript_2197828337()
proc logOptions*() =
  logOptionsScript_2197828422()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828466(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828517()
proc setMode*(mode: string) =
  setModeScript222_2197828826(mode)
proc mode*(): string =
  modeScript222_2197828909()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript222_2197828959(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197829243(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197829279(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829310(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829383(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829441()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829478()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829509()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829559()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829603()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829647(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829685(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829752(editorId)
proc scriptIsModelEditor*(editorId: EditorId): bool =
  scriptIsModelEditorScript_2197829819(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829886(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829985(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830049(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830117(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197830185(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197830261(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197830329(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830407(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830489(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830536(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830641(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830688(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830735(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830810(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830885(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830960(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197831035(path, id)
