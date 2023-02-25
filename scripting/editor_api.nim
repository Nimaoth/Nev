import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197824313()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824479(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824530(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824588(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824646(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824704(context, value)
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197824762(user, repository, branchOrHash)
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197824840(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197824895(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197824951(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197825024(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825137(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825188(option, value)
proc quit*() =
  quitScript_2197825280()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825324(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825375(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825700()
proc createView*() =
  createViewScript_2197825744()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825792()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825881()
proc nextView*() =
  nextViewScript_2197825976()
proc prevView*() =
  prevViewScript_2197826026()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826079()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826146()
proc setLayout*(layout: string) =
  setLayoutScript_2197826210(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826297(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826352()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826400()
proc openFile*(path: string) =
  openFileScript_2197826456(path)
proc writeFile*(path: string = "") =
  writeFileScript_2197826706(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197826769(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826832(name)
proc chooseTheme*() =
  chooseThemeScript_2197826919()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827643(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197827985(token)
proc reloadConfig*() =
  reloadConfigScript_2197828036()
proc logOptions*() =
  logOptionsScript_2197828121()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828165(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828216()
proc setMode*(mode: string) =
  setModeScript22_2197828525(mode)
proc mode*(): string =
  modeScript22_2197828608()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828658(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828941(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828977(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197829008(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197829081(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829139()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829176()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829207()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829257()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829301()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829345(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829383(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829450(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829517(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829616(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829680(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829748(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829816(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829892(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829960(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197830038(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830120(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830167(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830279(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830326(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830373(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830448(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830523(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830598(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830673(path, id)
