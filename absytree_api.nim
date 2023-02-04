import src/scripting_api
import std/[json]

proc setModeScript(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript(self: TextDocumentEditor; context: string): string =
  discard
proc updateTargetColumnScript(self: TextDocumentEditor; cursor: SelectionCursor) =
  discard
proc invertSelectionScript(self: TextDocumentEditor) =
  discard
proc insertScript(self: TextDocumentEditor; selections: seq[Selection];
                  text: string; notify: bool = true; record: bool = true;
                  autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript(self: TextDocumentEditor; selections: seq[Selection];
                  notify: bool = true; record: bool = true): seq[Selection] =
  discard
proc selectPrevScript(self: TextDocumentEditor) =
  discard
proc selectNextScript(self: TextDocumentEditor) =
  discard
proc selectInsideScript(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript(self: TextDocumentEditor) =
  discard
proc selectLineScript(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript(self: TextDocumentEditor) =
  discard
proc selectParentTsScript(self: TextDocumentEditor; selection: Selection) =
  discard
proc selectParentCurrentTsScript(self: TextDocumentEditor) =
  discard
proc insertTextScript(self: TextDocumentEditor; text: string) =
  discard
proc undoScript(self: TextDocumentEditor) =
  discard
proc redoScript(self: TextDocumentEditor) =
  discard
proc scrollTextScript(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript(self: TextDocumentEditor; cursor: Cursor;
                             offset: int = 0): Selection =
  discard
proc getNextFindResultScript(self: TextDocumentEditor; cursor: Cursor;
                             offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript(self: TextDocumentEditor; distance: int;
                            cursor: SelectionCursor = SelectionCursor.Config;
                            all: bool = true) =
  discard
proc moveCursorLineScript(self: TextDocumentEditor; distance: int;
                          cursor: SelectionCursor = SelectionCursor.Config;
                          all: bool = true) =
  discard
proc moveCursorHomeScript(self: TextDocumentEditor;
                          cursor: SelectionCursor = SelectionCursor.Config;
                          all: bool = true) =
  discard
proc moveCursorEndScript(self: TextDocumentEditor;
                         cursor: SelectionCursor = SelectionCursor.Config;
                         all: bool = true) =
  discard
proc moveCursorToScript(self: TextDocumentEditor; str: string;
                        cursor: SelectionCursor = SelectionCursor.Config;
                        all: bool = true) =
  discard
proc moveCursorBeforeScript(self: TextDocumentEditor; str: string;
                            cursor: SelectionCursor = SelectionCursor.Config;
                            all: bool = true) =
  discard
proc moveCursorNextFindResultScript(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorPrevFindResultScript(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc scrollToCursorScript(self: TextDocumentEditor;
                          cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript(self: TextDocumentEditor) =
  discard
proc deleteLeftScript(self: TextDocumentEditor) =
  discard
proc deleteRightScript(self: TextDocumentEditor) =
  discard
proc getCommandCountScript(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript(self: TextDocumentEditor; count: int) =
  discard
proc updateCommandCountScript(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript(self: TextDocumentEditor; name: string; value: bool) =
  discard
proc getFlagScript(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  discard
proc findWordBoundaryScript(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript(self: TextDocumentEditor; cursor: Cursor;
                               move: string; count: int = 0): Selection =
  discard
proc setMoveScript(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript(self: TextDocumentEditor; move: string;
                      which: SelectionCursor = SelectionCursor.Config;
                      all: bool = true) =
  discard
proc selectMoveScript(self: TextDocumentEditor; move: string;
                      which: SelectionCursor = SelectionCursor.Config;
                      all: bool = true) =
  discard
proc changeMoveScript(self: TextDocumentEditor; move: string;
                      which: SelectionCursor = SelectionCursor.Config;
                      all: bool = true) =
  discard
proc moveLastScript(self: TextDocumentEditor; move: string;
                    which: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  discard
proc moveFirstScript(self: TextDocumentEditor; move: string;
                     which: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  discard
proc setSearchQueryScript(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript(self: TextDocumentEditor; move: string;
                                  count: int = 0) =
  discard
proc gotoDefinitionScript(self: TextDocumentEditor) =
  discard
proc getCompletionsScript(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript(editor: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript(self: TextDocumentEditor) =
  discard
proc moveCursorScript(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript(self: AstDocumentEditor) =
  discard
proc selectContainingScript(self: AstDocumentEditor; container: string) =
  discard
proc deleteSelectedScript(self: AstDocumentEditor) =
  discard
proc copySelectedScript(self: AstDocumentEditor) =
  discard
proc finishEditScript(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2(self: AstDocumentEditor) =
  discard
proc redoScript2(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertAfterScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript(self: AstDocumentEditor) =
  discard
proc wrapScript(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript(self: AstDocumentEditor) =
  discard
proc renameScript(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript(self: AstDocumentEditor) =
  discard
proc selectPrevScript2(self: AstDocumentEditor) =
  discard
proc selectNextScript2(self: AstDocumentEditor) =
  discard
proc gotoScript(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript(self: AstDocumentEditor) =
  discard
proc toggleOptionScript(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript(self: AstDocumentEditor) =
  discard
proc scrollScript(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript(self: AstDocumentEditor) =
  discard
proc setModeScript2(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2(self: AstDocumentEditor; context: string): string =
  discard
proc acceptScript(self: SelectorPopup) =
  discard
proc cancelScript(self: SelectorPopup) =
  discard
proc prevScript(self: SelectorPopup) =
  discard
proc nextScript(self: SelectorPopup) =
  discard
proc setHandleInputsScript(context: string; value: bool) =
  discard
proc setHandleActionsScript(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript(context: string; value: bool) =
  discard
proc setConsumeAllInputScript(context: string; value: bool) =
  discard
proc getFlagScript2(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2(flag: string; value: bool) =
  discard
proc toggleFlagScript(flag: string) =
  discard
proc setOptionScript(option: string; value: JsonNode) =
  discard
proc quitScript() =
  discard
proc changeFontSizeScript(amount: float32) =
  discard
proc changeLayoutPropScript(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript() =
  discard
proc createViewScript() =
  discard
proc createKeybindAutocompleteViewScript() =
  discard
proc closeCurrentViewScript() =
  discard
proc moveCurrentViewToTopScript() =
  discard
proc nextViewScript() =
  discard
proc prevViewScript() =
  discard
proc moveCurrentViewPrevScript() =
  discard
proc moveCurrentViewNextScript() =
  discard
proc setLayoutScript(layout: string) =
  discard
proc commandLineScript(initialValue: string = "") =
  discard
proc exitCommandLineScript() =
  discard
proc executeCommandLineScript(): bool =
  discard
proc openFileScript(path: string) =
  discard
proc writeFileScript(path: string = "") =
  discard
proc loadFileScript(path: string = "") =
  discard
proc loadThemeScript(name: string) =
  discard
proc chooseThemeScript() =
  discard
proc chooseFileScript(view: string = "new") =
  discard
proc reloadConfigScript() =
  discard
proc logOptionsScript() =
  discard
proc clearCommandsScript(context: string) =
  discard
proc getAllEditorsScript(): seq[EditorId] =
  discard
proc setModeScript22(mode: string) =
  discard
proc modeScript22(): string =
  discard
proc getContextWithModeScript22(context: string): string =
  discard
proc scriptRunActionScript(action: string; arg: string) =
  discard
proc scriptLogScript(message: string) =
  discard
proc scriptAddCommandScript(context: string; keys: string; action: string;
                            arg: string) =
  discard
proc removeCommandScript(context: string; keys: string) =
  discard
proc getActivePopupScript(): PopupId =
  discard
proc getActiveEditorScript(): EditorId =
  discard
proc getEditorScript(index: int): EditorId =
  discard
proc scriptIsTextEditorScript(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript(editorId: EditorId; action: string; arg: string) =
  discard
proc scriptRunActionForPopupScript(popupId: PopupId; action: string; arg: string) =
  discard
proc scriptInsertTextIntoScript(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript(editorId: EditorId; selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript(editorId: EditorId): seq[Selection] =
  discard
proc scriptSetTextEditorSelectionsScript(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript(path: string; value: string) =
  discard
proc scriptSetCallbackScript(path: string; id: int) =
  discard
proc setMode*(self: TextDocumentEditor; mode: string) =
  setModeScript(self, mode)
proc mode*(self: TextDocumentEditor): string =
  modeScript(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  getContextWithModeScript(self, context)
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  updateTargetColumnScript(self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  invertSelectionScript(self)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  insertScript(self, selections, text, notify, record, autoIndent)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  deleteScript(self, selections, notify, record)
proc selectPrev*(self: TextDocumentEditor) =
  selectPrevScript(self)
proc selectNext*(self: TextDocumentEditor) =
  selectNextScript(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  selectInsideScript(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  selectInsideCurrentScript(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  selectLineScript(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  selectLineCurrentScript(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  selectParentTsScript(self, selection)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  selectParentCurrentTsScript(self)
proc insertText*(self: TextDocumentEditor; text: string) =
  insertTextScript(self, text)
proc undo*(self: TextDocumentEditor) =
  undoScript(self)
proc redo*(self: TextDocumentEditor) =
  redoScript(self)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  scrollTextScript(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  duplicateLastSelectionScript(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  addCursorBelowScript(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  addCursorAboveScript(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getPrevFindResultScript(self, cursor, offset)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getNextFindResultScript(self, cursor, offset)
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  addNextFindResultToSelectionScript(self)
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  addPrevFindResultToSelectionScript(self)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  setAllFindResultToSelectionScript(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorColumnScript(self, distance, cursor, all)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorLineScript(self, distance, cursor, all)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorHomeScript(self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  moveCursorEndScript(self, cursor, all)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  moveCursorToScript(self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorBeforeScript(self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorNextFindResultScript(self, cursor, all)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorPrevFindResultScript(self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  scrollToCursorScript(self, cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  reloadTreesitterScript(self)
proc deleteLeft*(self: TextDocumentEditor) =
  deleteLeftScript(self)
proc deleteRight*(self: TextDocumentEditor) =
  deleteRightScript(self)
proc getCommandCount*(self: TextDocumentEditor): int =
  getCommandCountScript(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  setCommandCountScript(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  setCommandCountRestoreScript(self, count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  updateCommandCountScript(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  setFlagScript(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  getFlagScript(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  runActionScript(self, action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  findWordBoundaryScript(self, cursor)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  getSelectionForMoveScript(self, cursor, move, count)
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  setMoveScript(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  deleteMoveScript(self, move, which, all)
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  selectMoveScript(self, move, which, all)
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  changeMoveScript(self, move, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  moveLastScript(self, move, which, all)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true) =
  moveFirstScript(self, move, which, all)
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  setSearchQueryScript(self, query)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  setSearchQueryFromMoveScript(self, move, count)
proc gotoDefinition*(self: TextDocumentEditor) =
  gotoDefinitionScript(self)
proc getCompletions*(self: TextDocumentEditor) =
  getCompletionsScript(self)
proc hideCompletions*(self: TextDocumentEditor) =
  hideCompletionsScript(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  selectPrevCompletionScript(self)
proc selectNextCompletion*(editor: TextDocumentEditor) =
  selectNextCompletionScript(editor)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  applySelectedCompletionScript(self)
proc moveCursor*(self: AstDocumentEditor; direction: int) =
  moveCursorScript(self, direction)
proc moveCursorUp*(self: AstDocumentEditor) =
  moveCursorUpScript(self)
proc moveCursorDown*(self: AstDocumentEditor) =
  moveCursorDownScript(self)
proc moveCursorNext*(self: AstDocumentEditor) =
  moveCursorNextScript(self)
proc moveCursorPrev*(self: AstDocumentEditor) =
  moveCursorPrevScript(self)
proc moveCursorNextLine*(self: AstDocumentEditor) =
  moveCursorNextLineScript(self)
proc moveCursorPrevLine*(self: AstDocumentEditor) =
  moveCursorPrevLineScript(self)
proc selectContaining*(self: AstDocumentEditor; container: string) =
  selectContainingScript(self, container)
proc deleteSelected*(self: AstDocumentEditor) =
  deleteSelectedScript(self)
proc copySelected*(self: AstDocumentEditor) =
  copySelectedScript(self)
proc finishEdit*(self: AstDocumentEditor; apply: bool) =
  finishEditScript(self, apply)
proc undo*(self: AstDocumentEditor) =
  undoScript2(self)
proc redo*(self: AstDocumentEditor) =
  redoScript2(self)
proc insertAfterSmart*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterSmartScript(self, nodeTemplate)
proc insertAfter*(self: AstDocumentEditor; nodeTemplate: string) =
  insertAfterScript(self, nodeTemplate)
proc insertBefore*(self: AstDocumentEditor; nodeTemplate: string) =
  insertBeforeScript(self, nodeTemplate)
proc insertChild*(self: AstDocumentEditor; nodeTemplate: string) =
  insertChildScript(self, nodeTemplate)
proc replace*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceScript(self, nodeTemplate)
proc replaceEmpty*(self: AstDocumentEditor; nodeTemplate: string) =
  replaceEmptyScript(self, nodeTemplate)
proc replaceParent*(self: AstDocumentEditor) =
  replaceParentScript(self)
proc wrap*(self: AstDocumentEditor; nodeTemplate: string) =
  wrapScript(self, nodeTemplate)
proc editPrevEmpty*(self: AstDocumentEditor) =
  editPrevEmptyScript(self)
proc editNextEmpty*(self: AstDocumentEditor) =
  editNextEmptyScript(self)
proc rename*(self: AstDocumentEditor) =
  renameScript(self)
proc selectPrevCompletion*(self: AstDocumentEditor) =
  selectPrevCompletionScript2(self)
proc selectNextCompletion*(editor: AstDocumentEditor) =
  selectNextCompletionScript2(editor)
proc applySelectedCompletion*(editor: AstDocumentEditor) =
  applySelectedCompletionScript2(editor)
proc cancelAndNextCompletion*(self: AstDocumentEditor) =
  cancelAndNextCompletionScript(self)
proc cancelAndPrevCompletion*(self: AstDocumentEditor) =
  cancelAndPrevCompletionScript(self)
proc cancelAndDelete*(self: AstDocumentEditor) =
  cancelAndDeleteScript(self)
proc moveNodeToPrevSpace*(self: AstDocumentEditor) =
  moveNodeToPrevSpaceScript(self)
proc moveNodeToNextSpace*(self: AstDocumentEditor) =
  moveNodeToNextSpaceScript(self)
proc selectPrev*(self: AstDocumentEditor) =
  selectPrevScript2(self)
proc selectNext*(self: AstDocumentEditor) =
  selectNextScript2(self)
proc goto*(self: AstDocumentEditor; where: string) =
  gotoScript(self, where)
proc runSelectedFunction*(self: AstDocumentEditor) =
  runSelectedFunctionScript(self)
proc toggleOption*(self: AstDocumentEditor; name: string) =
  toggleOptionScript(self, name)
proc runLastCommand*(self: AstDocumentEditor; which: string) =
  runLastCommandScript(self, which)
proc selectCenterNode*(self: AstDocumentEditor) =
  selectCenterNodeScript(self)
proc scroll*(self: AstDocumentEditor; amount: float32) =
  scrollScript(self, amount)
proc scrollOutput*(self: AstDocumentEditor; arg: string) =
  scrollOutputScript(self, arg)
proc dumpContext*(self: AstDocumentEditor) =
  dumpContextScript(self)
proc setMode*(self: AstDocumentEditor; mode: string) =
  setModeScript2(self, mode)
proc mode*(self: AstDocumentEditor): string =
  modeScript2(self)
proc getContextWithMode*(self: AstDocumentEditor; context: string): string =
  getContextWithModeScript2(self, context)
proc accept*(self: SelectorPopup) =
  acceptScript(self)
proc cancel*(self: SelectorPopup) =
  cancelScript(self)
proc prev*(self: SelectorPopup) =
  prevScript(self)
proc next*(self: SelectorPopup) =
  nextScript(self)
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
