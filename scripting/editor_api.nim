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
proc openAbsytreeServerWorkspace*(url: string) =
  openAbsytreeServerWorkspaceScript_2197824764(url)
proc openLocalWorkspace*(path: string) =
  openLocalWorkspaceScript_2197824819(path)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197824875(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197824948(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197825061(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197825112(option, value)
proc quit*() =
  quitScript_2197825204()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197825248(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197825299(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825624()
proc createView*() =
  createViewScript_2197825668()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825716()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825805()
proc nextView*() =
  nextViewScript_2197825900()
proc prevView*() =
  prevViewScript_2197825950()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197826003()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197826070()
proc setLayout*(layout: string) =
  setLayoutScript_2197826134(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197826221(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197826276()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197826324()
proc openFile*(path: string) =
  openFileScript_2197826380(path)
proc writeFile*(path: string = "") =
  writeFileScript_2197826630(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197826693(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826756(name)
proc chooseTheme*() =
  chooseThemeScript_2197826843()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827557(view)
proc setGithubAccessToken*(token: string) =
  ## Stores the give token in local storage as 'GithubAccessToken', which will be used in requests to the github api
  setGithubAccessTokenScript_2197827910(token)
proc reloadConfig*() =
  reloadConfigScript_2197827961()
proc logOptions*() =
  logOptionsScript_2197828046()
proc clearCommands*(context: string) =
  clearCommandsScript_2197828090(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197828141()
proc setMode*(mode: string) =
  setModeScript22_2197828450(mode)
proc mode*(): string =
  modeScript22_2197828533()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828583(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828858(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828894(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197828925(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197828998(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197829056()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197829093()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197829124()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197829174()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197829218()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197829262(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197829300(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197829367(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829434(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829533(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829597(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829665(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829733(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829809(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829877(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829955(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197830037(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197830084(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197830196(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197830243(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197830290(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197830365(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830440(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830515(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830590(path, id)
