import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript*(self: TextDocumentEditor; context: string): string =
  discard
proc updateTargetColumnScript*(self: TextDocumentEditor; cursor: SelectionCursor) =
  discard
proc invertSelectionScript*(self: TextDocumentEditor) =
  discard
proc insertScript*(self: TextDocumentEditor; selections: seq[Selection];
                  text: string; notify: bool = true; record: bool = true;
                  autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript*(self: TextDocumentEditor; selections: seq[Selection];
                  notify: bool = true; record: bool = true): seq[Selection] =
  discard
proc selectPrevScript*(self: TextDocumentEditor) =
  discard
proc selectNextScript*(self: TextDocumentEditor) =
  discard
proc selectInsideScript*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript*(self: TextDocumentEditor) =
  discard
proc selectLineScript*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript*(self: TextDocumentEditor; selection: Selection) =
  discard
proc selectParentCurrentTsScript*(self: TextDocumentEditor) =
  discard
proc insertTextScript*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript*(self: TextDocumentEditor) =
  discard
proc redoScript*(self: TextDocumentEditor) =
  discard
proc scrollTextScript*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript*(self: TextDocumentEditor; cursor: Cursor;
                             offset: int = 0): Selection =
  discard
proc getNextFindResultScript*(self: TextDocumentEditor; cursor: Cursor;
                             offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript*(self: TextDocumentEditor; distance: int;
                            cursor: SelectionCursor = SelectionCursor.Config;
                            all: bool = true) =
  discard
proc moveCursorLineScript*(self: TextDocumentEditor; distance: int;
                          cursor: SelectionCursor = SelectionCursor.Config;
                          all: bool = true) =
  discard
proc moveCursorHomeScript*(self: TextDocumentEditor;
                          cursor: SelectionCursor = SelectionCursor.Config;
                          all: bool = true) =
  discard
proc moveCursorEndScript*(self: TextDocumentEditor;
                         cursor: SelectionCursor = SelectionCursor.Config;
                         all: bool = true) =
  discard
proc moveCursorToScript*(self: TextDocumentEditor; str: string;
                        cursor: SelectionCursor = SelectionCursor.Config;
                        all: bool = true) =
  discard
proc moveCursorBeforeScript*(self: TextDocumentEditor; str: string;
                            cursor: SelectionCursor = SelectionCursor.Config;
                            all: bool = true) =
  discard
proc moveCursorNextFindResultScript*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorPrevFindResultScript*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc scrollToCursorScript*(self: TextDocumentEditor;
                          cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript*(self: TextDocumentEditor) =
  discard
proc deleteRightScript*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript*(self: TextDocumentEditor; count: int) =
  discard
proc updateCommandCountScript*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript*(self: TextDocumentEditor; name: string; value: bool) =
  discard
proc getFlagScript*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  discard
proc findWordBoundaryScript*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript*(self: TextDocumentEditor; cursor: Cursor;
                               move: string; count: int = 0): Selection =
  discard
proc setMoveScript*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript*(self: TextDocumentEditor; move: string;
                      which: SelectionCursor = SelectionCursor.Config;
                      all: bool = true) =
  discard
proc selectMoveScript*(self: TextDocumentEditor; move: string;
                      which: SelectionCursor = SelectionCursor.Config;
                      all: bool = true) =
  discard
proc changeMoveScript*(self: TextDocumentEditor; move: string;
                      which: SelectionCursor = SelectionCursor.Config;
                      all: bool = true) =
  discard
proc moveLastScript*(self: TextDocumentEditor; move: string;
                    which: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  discard
proc moveFirstScript*(self: TextDocumentEditor; move: string;
                     which: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  discard
proc setSearchQueryScript*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript*(self: TextDocumentEditor; move: string;
                                  count: int = 0) =
  discard
proc gotoDefinitionScript*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript*(self: TextDocumentEditor) =
  discard
proc moveCursorScript*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript*(self: AstDocumentEditor) =
  discard
proc selectContainingScript*(self: AstDocumentEditor; container: string) =
  discard
proc deleteSelectedScript*(self: AstDocumentEditor) =
  discard
proc copySelectedScript*(self: AstDocumentEditor) =
  discard
proc finishEditScript*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2*(self: AstDocumentEditor) =
  discard
proc redoScript2*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertAfterScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript*(self: AstDocumentEditor) =
  discard
proc wrapScript*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript*(self: AstDocumentEditor) =
  discard
proc renameScript*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2*(self: AstDocumentEditor) =
  discard
proc selectNextScript2*(self: AstDocumentEditor) =
  discard
proc gotoScript*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript*(self: AstDocumentEditor) =
  discard
proc scrollScript*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript*(self: AstDocumentEditor) =
  discard
proc setModeScript2*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2*(self: AstDocumentEditor; context: string): string =
  discard
proc acceptScript*(self: SelectorPopup) =
  discard
proc cancelScript*(self: SelectorPopup) =
  discard
proc prevScript*(self: SelectorPopup) =
  discard
proc nextScript*(self: SelectorPopup) =
  discard
proc getBackendScript*(): Backend =
  discard
proc setHandleInputsScript*(context: string; value: bool) =
  discard
proc setHandleActionsScript*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript*(context: string; value: bool) =
  discard
proc getFlagScript2*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2*(flag: string; value: bool) =
  discard
proc toggleFlagScript*(flag: string) =
  discard
proc setOptionScript*(option: string; value: JsonNode) =
  discard
proc quitScript*() =
  discard
proc changeFontSizeScript*(amount: float32) =
  discard
proc changeLayoutPropScript*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript*() =
  discard
proc createViewScript*() =
  discard
proc createKeybindAutocompleteViewScript*() =
  discard
proc closeCurrentViewScript*() =
  discard
proc moveCurrentViewToTopScript*() =
  discard
proc nextViewScript*() =
  discard
proc prevViewScript*() =
  discard
proc moveCurrentViewPrevScript*() =
  discard
proc moveCurrentViewNextScript*() =
  discard
proc setLayoutScript*(layout: string) =
  discard
proc commandLineScript*(initialValue: string = "") =
  discard
proc exitCommandLineScript*() =
  discard
proc executeCommandLineScript*(): bool =
  discard
proc openFileScript*(path: string) =
  discard
proc writeFileScript*(path: string = "") =
  discard
proc loadFileScript*(path: string = "") =
  discard
proc loadThemeScript*(name: string) =
  discard
proc chooseThemeScript*() =
  discard
proc chooseFileScript*(view: string = "new") =
  discard
proc reloadConfigScript*() =
  discard
proc logOptionsScript*() =
  discard
proc clearCommandsScript*(context: string) =
  discard
proc getAllEditorsScript*(): seq[EditorId] =
  discard
proc setModeScript22*(mode: string) =
  discard
proc modeScript22*(): string =
  discard
proc getContextWithModeScript22*(context: string): string =
  discard
proc scriptRunActionScript*(action: string; arg: string) =
  discard
proc scriptLogScript*(message: string) =
  discard
proc scriptAddCommandScript*(context: string; keys: string; action: string;
                            arg: string) =
  discard
proc removeCommandScript*(context: string; keys: string) =
  discard
proc getActivePopupScript*(): EditorId =
  discard
proc getActiveEditorScript*(): EditorId =
  discard
proc getEditorScript*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript*(editorId: EditorId; action: string; arg: string) =
  discard
proc scriptInsertTextIntoScript*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript*(editorId: EditorId; selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript*(editorId: EditorId): seq[Selection] =
  discard
proc scriptSetTextEditorSelectionsScript*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript*(path: string; value: string) =
  discard
proc scriptSetCallbackScript*(path: string; id: int) =
  discard
