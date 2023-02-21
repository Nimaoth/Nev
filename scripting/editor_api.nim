import std/[json]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc getBackend*(): Backend =
  getBackendScript_2197823911()
proc requestRender*() =
  requestRenderScript_2197824076()
proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript_2197824119(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript_2197824176(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript_2197824233(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript_2197824290(context, value)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2_2197824347(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2_2197824419(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript_2197824531(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript_2197824581(option, value)
proc quit*() =
  quitScript_2197824672()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript_2197824715(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript_2197824765(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript_2197825071()
proc createView*() =
  createViewScript_2197825114()
proc closeCurrentView*() =
  closeCurrentViewScript_2197825161()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript_2197825249()
proc nextView*() =
  nextViewScript_2197825343()
proc prevView*() =
  prevViewScript_2197825392()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript_2197825444()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript_2197825510()
proc setLayout*(layout: string) =
  setLayoutScript_2197825573(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript_2197825659(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript_2197825713()
proc executeCommandLine*(): bool =
  executeCommandLineScript_2197825760()
proc openFile*(path: string) =
  openFileScript_2197825815(path)
proc writeFile*(path: string = "") =
  writeFileScript_2197825907(path)
proc loadFile*(path: string = "") =
  loadFileScript_2197825969(path)
proc loadTheme*(name: string) =
  loadThemeScript_2197826031(name)
proc chooseTheme*() =
  chooseThemeScript_2197826117()
proc chooseFile*(view: string = "new") =
  chooseFileScript_2197826438(view)
proc reloadConfig*() =
  reloadConfigScript_2197826568()
proc logOptions*() =
  logOptionsScript_2197826652()
proc clearCommands*(context: string) =
  clearCommandsScript_2197826695(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript_2197826745()
proc setMode*(mode: string) =
  setModeScript22_2197827035(mode)
proc mode*(): string =
  modeScript22_2197827117()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22_2197827166(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript_2197827704(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript_2197827739(message)
proc scriptAddCommand*(context: string; keys: string; action: string;
                       arg: string = "") =
  scriptAddCommandScript_2197827769(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript_2197827819(context, keys)
proc getActivePopup*(): EditorId =
  getActivePopupScript_2197827854()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript_2197827890()
proc getEditor*(index: int): EditorId =
  getEditorScript_2197827920(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript_2197827957(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript_2197828023(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript_2197828089(editorId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript_2197828187(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript_2197828250(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript_2197828317(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript_2197828384(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript_2197828459(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript_2197828526(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript_2197828603(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript_2197828684(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript_2197828730(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript_2197828841(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript_2197828887(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript_2197828933(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript_2197829007(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript_2197829081(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript_2197829155(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript_2197829229(path, id)
