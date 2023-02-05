import std/[json]
import "../src/scripting_api"
import absytree_internal

## This file is auto generated, don't modify.

proc setHandleInputs*(context: string; value: bool) =
  setHandleInputsScript(context, value)
proc setHandleActions*(context: string; value: bool) =
  setHandleActionsScript(context, value)
proc setConsumeAllActions*(context: string; value: bool) =
  setConsumeAllActionsScript(context, value)
proc setConsumeAllInput*(context: string; value: bool) =
  setConsumeAllInputScript(context, value)
proc getFlag*(flag: string; default: bool = false): bool =
  getFlagScript2(flag, default)
proc setFlag*(flag: string; value: bool) =
  setFlagScript2(flag, value)
proc toggleFlag*(flag: string) =
  toggleFlagScript(flag)
proc setOption*(option: string; value: JsonNode) =
  setOptionScript(option, value)
proc quit*() =
  quitScript()
proc changeFontSize*(amount: float32) =
  changeFontSizeScript(amount)
proc changeLayoutProp*(prop: string; change: float32) =
  changeLayoutPropScript(prop, change)
proc toggleStatusBarLocation*() =
  toggleStatusBarLocationScript()
proc createView*() =
  createViewScript()
proc createKeybindAutocompleteView*() =
  createKeybindAutocompleteViewScript()
proc closeCurrentView*() =
  closeCurrentViewScript()
proc moveCurrentViewToTop*() =
  moveCurrentViewToTopScript()
proc nextView*() =
  nextViewScript()
proc prevView*() =
  prevViewScript()
proc moveCurrentViewPrev*() =
  moveCurrentViewPrevScript()
proc moveCurrentViewNext*() =
  moveCurrentViewNextScript()
proc setLayout*(layout: string) =
  setLayoutScript(layout)
proc commandLine*(initialValue: string = "") =
  commandLineScript(initialValue)
proc exitCommandLine*() =
  exitCommandLineScript()
proc executeCommandLine*(): bool =
  executeCommandLineScript()
proc openFile*(path: string) =
  openFileScript(path)
proc writeFile*(path: string = "") =
  writeFileScript(path)
proc loadFile*(path: string = "") =
  loadFileScript(path)
proc loadTheme*(name: string) =
  loadThemeScript(name)
proc chooseTheme*() =
  chooseThemeScript()
proc chooseFile*(view: string = "new") =
  chooseFileScript(view)
proc reloadConfig*() =
  reloadConfigScript()
proc logOptions*() =
  logOptionsScript()
proc clearCommands*(context: string) =
  clearCommandsScript(context)
proc getAllEditors*(): seq[EditorId] =
  getAllEditorsScript()
proc setMode*(mode: string) =
  setModeScript22(mode)
proc mode*(): string =
  modeScript22()
proc getContextWithMode*(context: string): string =
  getContextWithModeScript22(context)
proc scriptRunAction*(action: string; arg: string) =
  scriptRunActionScript(action, arg)
proc scriptLog*(message: string) =
  scriptLogScript(message)
proc scriptAddCommand*(context: string; keys: string; action: string;
                       arg: string) =
  scriptAddCommandScript(context, keys, action, arg)
proc removeCommand*(context: string; keys: string) =
  removeCommandScript(context, keys)
proc getActivePopup*(): PopupId =
  getActivePopupScript()
proc getActiveEditor*(): EditorId =
  getActiveEditorScript()
proc getEditor*(index: int): EditorId =
  getEditorScript(index)
proc scriptIsTextEditor*(editorId: EditorId): bool =
  scriptIsTextEditorScript(editorId)
proc scriptIsAstEditor*(editorId: EditorId): bool =
  scriptIsAstEditorScript(editorId)
proc scriptRunActionFor*(editorId: EditorId; action: string; arg: string) =
  scriptRunActionForScript(editorId, action, arg)
proc scriptRunActionForPopup*(popupId: PopupId; action: string; arg: string) =
  scriptRunActionForPopupScript(popupId, action, arg)
proc scriptInsertTextInto*(editorId: EditorId; text: string) =
  scriptInsertTextIntoScript(editorId, text)
proc scriptTextEditorSelection*(editorId: EditorId): Selection =
  scriptTextEditorSelectionScript(editorId)
proc scriptSetTextEditorSelection*(editorId: EditorId; selection: Selection) =
  scriptSetTextEditorSelectionScript(editorId, selection)
proc scriptTextEditorSelections*(editorId: EditorId): seq[Selection] =
  scriptTextEditorSelectionsScript(editorId)
proc scriptSetTextEditorSelections*(editorId: EditorId;
                                    selections: seq[Selection]) =
  scriptSetTextEditorSelectionsScript(editorId, selections)
proc scriptGetTextEditorLine*(editorId: EditorId; line: int): string =
  scriptGetTextEditorLineScript(editorId, line)
proc scriptGetTextEditorLineCount*(editorId: EditorId): int =
  scriptGetTextEditorLineCountScript(editorId)
proc scriptGetOptionInt*(path: string; default: int): int =
  scriptGetOptionIntScript(path, default)
proc scriptGetOptionFloat*(path: string; default: float): float =
  scriptGetOptionFloatScript(path, default)
proc scriptGetOptionBool*(path: string; default: bool): bool =
  scriptGetOptionBoolScript(path, default)
proc scriptGetOptionString*(path: string; default: string): string =
  scriptGetOptionStringScript(path, default)
proc scriptSetOptionInt*(path: string; value: int) =
  scriptSetOptionIntScript(path, value)
proc scriptSetOptionFloat*(path: string; value: float) =
  scriptSetOptionFloatScript(path, value)
proc scriptSetOptionBool*(path: string; value: bool) =
  scriptSetOptionBoolScript(path, value)
proc scriptSetOptionString*(path: string; value: string) =
  scriptSetOptionStringScript(path, value)
proc scriptSetCallback*(path: string; id: int) =
  scriptSetCallbackScript(path, id)
