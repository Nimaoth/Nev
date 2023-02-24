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
  writeFileScript_2197826581(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197826644(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826713(name)
proc chooseTheme*() =
  chooseThemeScript_2197826800()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197827122(view)
proc reloadConfig*() =
  reloadConfigScript_2197827528()
proc logOptions*() =
  logOptionsScript_2197827613()
proc clearCommands*(context: string) =
  clearCommandsScript_2197827657(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197827708()
proc setMode*(mode: string) =
  setModeScript22_2197828017(mode)
proc mode*(): string =
  modeScript22_2197828100()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197828150(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197828425(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197828461(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197828492(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197828565(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197828623()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197828660()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197828691()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197828741()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197828785()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197828829(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197828867(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197828934(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197829001(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197829100(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197829164(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197829232(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197829300(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197829376(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197829444(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197829522(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197829604(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197829651(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197829763(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197829810(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197829857(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197829932(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197830007(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197830082(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197830157(path, id)
