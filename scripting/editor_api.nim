import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823994()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824160(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824211(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824269(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824327(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824385(context, value)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197824443(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197824516(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197824629(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197824680(option, value)
proc quit*() =
  quitScript_2197824772()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197824816(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197824867(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825174()
proc createView*() =
  createViewScript_2197825218()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825266()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825355()
proc nextView*() =
  nextViewScript_2197825450()
proc prevView*() =
  prevViewScript_2197825500()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197825553()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197825620()
proc setLayout*(layout: string) =
  setLayoutScript_2197825684(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197825771(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197825826()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197825874()
proc openFile*(path: string) =
  openFileScript_2197825930(path)
proc writeFile*(path: string = "") =
  writeFileScript_2197826023(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197826086(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826149(name)
proc chooseTheme*() =
  chooseThemeScript_2197826236()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197826549(view)
proc reloadConfig*() =
  reloadConfigScript_2197826671()
proc logOptions*() =
  logOptionsScript_2197826756()
proc clearCommands*(context: string) =
  clearCommandsScript_2197826800(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197826851()
proc setMode*(mode: string) =
  setModeScript22_2197827142(mode)
proc mode*(): string =
  modeScript22_2197827225()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197827275(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197827550(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197827586(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197827617(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197827690(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197827748()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197827785()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197827816()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197827866()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197827910()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197827954(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197827992(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197828059(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197828126(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197828225(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197828289(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197828357(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197828425(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197828501(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197828569(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197828647(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197828729(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197828776(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197828888(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197828935(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197828982(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197829057(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197829132(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197829207(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197829282(path, id)
