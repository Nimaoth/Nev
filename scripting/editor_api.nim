import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197824532()
proc saveAppState*() =
  saveAppStateScript_2197824698()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197825489(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197825540(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197825598(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197825656(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197825714(context, value)
proc clearWorkspaceCaches*() =
  clearWorkspaceCachesScript_2197825849()
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197825897(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197825962(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197826013(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197826065(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197826138(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197826251(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197826302(option, value)
proc quit*() =
  quitScript_2197826394()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197826438(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197826489(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197826814()
proc createView*() =
  createViewScript_2197826858()
proc closeCurrentView*() =
  closeCurrentViewScript_2197826907()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197826996()
proc nextView*() =
  nextViewScript_2197827091()
proc prevView*() =
  prevViewScript_2197827141()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197827194()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197827261()
proc setLayout*(layout: string) =
  setLayoutScript_2197827325(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197827412(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197827467()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197827515()
proc writeFile*(path: string = ""; app: bool = false) =
  writeFileScript_2197827674(path, app)
proc loadFile*(path: string = "") =
  loadFileScript_2197827744(path)
proc openFile*(path: string; app: bool = false) =
  openFileScript_2197827826(path, app)
proc removeFromLocalStorage*() =
  ## Browser only
  ## Clears the content of the current document in local storage
  removeFromLocalStorageScript_2197827994()
proc loadTheme*(name: string) =
  loadThemeScript_2197828038(name)
proc chooseTheme*() =
  chooseThemeScript_2197828125()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197828886(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197829187(token)
proc reloadConfig*() =
  reloadConfigScript_2197829238()
proc logOptions*() =
  logOptionsScript_2197829323()
proc clearCommands*(context: string) =
  clearCommandsScript_2197829367(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197829418()
proc setMode*(mode: string) =
  setModeScript22_2197829727(mode)
proc mode*(): string =
  modeScript22_2197829810()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197829860(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197830144(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197830180(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197830211(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197830284(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197830342()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197830379()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197830410()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197830460()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197830504()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197830548(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197830586(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197830653(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197830720(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197830819(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197830883(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197830951(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197831019(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197831095(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197831163(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197831241(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197831323(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197831370(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197831475(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197831522(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197831569(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197831644(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197831719(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197831794(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197831869(path, id)
