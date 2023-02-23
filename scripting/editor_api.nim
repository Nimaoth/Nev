import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823911()
proc requestRender*(redrawEverything: bool = false) =
  requestRenderScript_2197824077(redrawEverything)
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824128(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824186(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824244(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824302(context, value)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197824360(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197824433(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197824546(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197824597(option, value)
proc quit*() =
  quitScript_2197824689()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197824733(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197824784(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825091()
proc createView*() =
  createViewScript_2197825135()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825183()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825272()
proc nextView*() =
  nextViewScript_2197825367()
proc prevView*() =
  prevViewScript_2197825417()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197825470()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197825537()
proc setLayout*(layout: string) =
  setLayoutScript_2197825601(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197825688(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197825743()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197825791()
proc openFile*(path: string) =
  openFileScript_2197825847(path)
proc writeFile*(path: string = "") =
  writeFileScript_2197825940(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197826003(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826066(name)
proc chooseTheme*() =
  chooseThemeScript_2197826153()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197826475(view)
proc reloadConfig*() =
  reloadConfigScript_2197826606()
proc logOptions*() =
  logOptionsScript_2197826691()
proc clearCommands*(context: string) =
  clearCommandsScript_2197826735(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197826786()
proc setMode*(mode: string) =
  setModeScript22_2197827077(mode)
proc mode*(): string =
  modeScript22_2197827160()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197827210(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197827485(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197827521(message)
proc addCommandScript*(context: string; keys: string; action: string;
                       arg: string = "") =
  addCommandScriptScript_2197827552(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197827625(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197827683()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197827720()
proc getActiveEditor2*(): EditorId =
  ## Returns the active editor instance
  getActiveEditor2Script_2197827751()
proc loadCurrentConfig*() =
  ## Javascript backend only!
  ## Opens the config file in a new view.
  loadCurrentConfigScript_2197827801()
proc sourceCurrentDocument*() =
  ## Javascript backend only!
  ## Runs the content of the active editor as javascript using `eval()`.
  ## "use strict" is prepended to the content to force strict mode.
  sourceCurrentDocumentScript_2197827845()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197827889(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197827927(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197827994(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197828061(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197828160(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197828224(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197828292(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197828360(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197828436(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197828504(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197828582(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197828664(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197828711(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197828823(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197828870(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197828917(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197828992(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197829067(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197829142(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197829217(path, id)
