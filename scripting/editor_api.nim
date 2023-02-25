import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197824237()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824403(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824454(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824512(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824570(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824628(context, value)
proc openGithubWorkspace*(user: string; repository: string; branchOrHash: string) =
  openGithubWorkspaceScript_2197824686(user, repository, branchOrHash)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197824764(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197824820(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197824893(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825006(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825057(option, value)
proc quit*() =
  quitScript_2197825149()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825193(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825244(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825569()
proc createView*() =
  createViewScript_2197825613()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825661()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825750()
proc nextView*() =
  nextViewScript_2197825845()
proc prevView*() =
  prevViewScript_2197825895()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197825948()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826015()
proc setLayout*(layout: string) =
  setLayoutScript_2197826079(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826166(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826221()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826269()
proc openFile*(path: string) =
  openFileScript_2197826325(path)
proc writeFile*(path: string = "") =
  writeFileScript_2197826575(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197826638(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826701(name)
proc chooseTheme*() =
  chooseThemeScript_2197826788()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827276(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197827669(token)
proc reloadConfig*() =
  reloadConfigScript_2197827720()
proc logOptions*() =
  logOptionsScript_2197827805()
proc clearCommands*(context: string) =
  clearCommandsScript_2197827849(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197827900()
proc setMode*(mode: string) =
  setModeScript22_2197828209(mode)
proc mode*(): string =
  modeScript22_2197828292()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828342(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828617(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828653(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197828684(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197828757(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197828815()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197828852()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197828883()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197828933()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197828977()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829021(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829059(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829126(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829193(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829292(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829356(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829424(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829492(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829568(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829636(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829714(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197829796(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197829843(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197829955(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830002(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830049(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830124(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830199(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830274(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830349(path, id)
