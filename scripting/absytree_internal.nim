import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7683976439*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7683976638*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7683976694*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7683976757*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7683976859*(self: TextDocumentEditor) =
  discard
proc insertScript_7683976909*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7683977274*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7683977351*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7683977564*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7683977754*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7683977828*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7683977878*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7683977935*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7683977985*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7683978056*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7683978111*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7683978177*(self: TextDocumentEditor) =
  discard
proc redoScript_7683978275*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7683978351*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7683978470*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7683978562*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7683978624*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7683978686*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7683979007*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7683979225*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7683979283*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7683979341*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7683979703*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7683979792*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7683979863*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7683979927*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7683979991*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7683980069*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7683980147*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7683980211*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7683980275*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7683980332*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7683980386*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7683980444*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7683980502*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7683980558*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7683980615*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7683980672*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7683980729*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7683980793*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7683980856*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7683980929*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7683981019*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7683981213*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7683981467*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7683981568*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7683981694*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7683981795*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7683981910*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7683982025*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7683982104*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7683982909*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7683982963*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7683983017*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7683983067*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7683983131*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7683983195*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_8120184089*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8120184192*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8120184254*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8120184304*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8120184361*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8120184417*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8120184493*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8120184569*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8120184782*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8120184835*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8120184888*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8120184987*(self: AstDocumentEditor) =
  discard
proc redoScript2_8120185063*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8120185139*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8120185313*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8120185455*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8120185596*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8120185736*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8120185830*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8120185928*(self: AstDocumentEditor) =
  discard
proc wrapScript_8120185988*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8120186106*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8120186162*(self: AstDocumentEditor) =
  discard
proc renameScript_8120186226*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8120186276*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8120186337*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8120186398*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8120186561*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8120186611*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8120186661*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8120186714*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8120186868*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8120187023*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8120187073*(self: AstDocumentEditor) =
  discard
proc gotoScript_8120187123*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8120187959*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8120188228*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8120188289*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8120188346*(self: AstDocumentEditor) =
  discard
proc scrollScript_8120188803*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8120188864*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8120188932*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8120188986*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8120189075*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8120189131*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8388608558*(self: SelectorPopup) =
  discard
proc cancelScript_8388608657*(self: SelectorPopup) =
  discard
proc prevScript_8388608713*(self: SelectorPopup) =
  discard
proc nextScript_8388608781*(self: SelectorPopup) =
  discard
proc getBackendScript_2197824237*(): Backend =
  discard
proc requestRenderScript_2197824403*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824454*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824512*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824570*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824628*(context: string; value: bool) =
  discard
proc openGithubWorkspaceScript_2197824686*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197824764*(url: string) =
  discard
proc openLocalWorkspaceScript_2197824819*(path: string) =
  discard
proc getFlagScript2_2197824875*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197824948*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825061*(flag: string) =
  discard
proc setOptionScript_2197825112*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825204*() =
  discard
proc changeFontSizeScript_2197825248*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825299*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825624*() =
  discard
proc createViewScript_2197825668*() =
  discard
proc closeCurrentViewScript_2197825716*() =
  discard
proc moveCurrentViewToTopScript_2197825805*() =
  discard
proc nextViewScript_2197825900*() =
  discard
proc prevViewScript_2197825950*() =
  discard
proc moveCurrentViewPrevScript_2197826003*() =
  discard
proc moveCurrentViewNextScript_2197826070*() =
  discard
proc setLayoutScript_2197826134*(layout: string) =
  discard
proc commandLineScript_2197826221*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826276*() =
  discard
proc executeCommandLineScript_2197826324*(): bool =
  discard
proc openFileScript_2197826380*(path: string) =
  discard
proc writeFileScript_2197826630*(path: string = "") =
  discard
proc loadFileScript_2197826693*(path: string = "") =
  discard
proc loadThemeScript_2197826756*(name: string) =
  discard
proc chooseThemeScript_2197826843*() =
  discard
proc chooseFileScript_2197827557*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197827910*(token: string) =
  discard
proc reloadConfigScript_2197827961*() =
  discard
proc logOptionsScript_2197828046*() =
  discard
proc clearCommandsScript_2197828090*(context: string) =
  discard
proc getAllEditorsScript_2197828141*(): seq[EditorId] =
  discard
proc setModeScript22_2197828450*(mode: string) =
  discard
proc modeScript22_2197828533*(): string =
  discard
proc getContextWithModeScript22_2197828583*(context: string): string =
  discard
proc scriptRunActionScript_2197828858*(action: string; arg: string) =
  discard
proc scriptLogScript_2197828894*(message: string) =
  discard
proc addCommandScriptScript_2197828925*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197828998*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829056*(): EditorId =
  discard
proc getActiveEditorScript_2197829093*(): EditorId =
  discard
proc getActiveEditor2Script_2197829124*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829174*() =
  discard
proc sourceCurrentDocumentScript_2197829218*() =
  discard
proc getEditorScript_2197829262*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829300*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829367*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829434*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829533*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197829597*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197829665*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197829733*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197829809*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197829877*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197829955*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830037*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830084*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830196*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830243*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830290*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830365*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830440*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830515*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830590*(path: string; id: int) =
  discard
