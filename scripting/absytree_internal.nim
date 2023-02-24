import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7415538537*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7415538736*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7415538792*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7415538855*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7415538957*(self: TextDocumentEditor) =
  discard
proc insertScript_7415539007*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7415539372*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7415539449*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7415539662*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7415539852*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7415539926*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7415539976*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7415540033*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7415540083*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7415540154*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7415540209*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7415540275*(self: TextDocumentEditor) =
  discard
proc redoScript_7415540373*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7415540449*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7415540568*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7415540660*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7415540722*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7415540784*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7415541105*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7415541323*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7415541381*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7415541439*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7415541801*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7415541890*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7415541961*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7415542025*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7415542089*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7415542167*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7415542245*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7415542309*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7415542373*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7415542430*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7415542484*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7415542542*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7415542600*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7415542656*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7415542713*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7415542770*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7415542827*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7415542891*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7415542954*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7415543027*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7415543117*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7415543311*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7415543565*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7415543666*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7415543792*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7415543893*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7415544008*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7415544123*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7415544202*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7415545007*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7415545061*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7415545115*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7415545165*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7415545229*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7415545293*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_7935634713*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_7935634816*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_7935634878*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_7935634928*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_7935634985*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_7935635041*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_7935635117*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_7935635193*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_7935635406*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_7935635459*(self: AstDocumentEditor) =
  discard
proc finishEditScript_7935635512*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_7935635611*(self: AstDocumentEditor) =
  discard
proc redoScript2_7935635687*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_7935635763*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_7935635937*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_7935636079*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_7935636220*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_7935636360*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_7935636454*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_7935636552*(self: AstDocumentEditor) =
  discard
proc wrapScript_7935636612*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_7935636730*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_7935636786*(self: AstDocumentEditor) =
  discard
proc renameScript_7935636850*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_7935636900*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_7935636961*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_7935637022*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_7935637185*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_7935637235*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_7935637285*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_7935637338*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_7935637492*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_7935637647*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_7935637697*(self: AstDocumentEditor) =
  discard
proc gotoScript_7935637747*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_7935638583*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_7935638852*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_7935638913*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_7935638970*(self: AstDocumentEditor) =
  discard
proc scrollScript_7935639427*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_7935639488*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_7935639556*(self: AstDocumentEditor) =
  discard
proc setModeScript2_7935639610*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_7935639699*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_7935639755*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8204058912*(self: SelectorPopup) =
  discard
proc cancelScript_8204059011*(self: SelectorPopup) =
  discard
proc prevScript_8204059067*(self: SelectorPopup) =
  discard
proc nextScript_8204059135*(self: SelectorPopup) =
  discard
proc getBackendScript_2197823994*(): Backend =
  discard
proc requestRenderScript_2197824160*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824211*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824269*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824327*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824385*(context: string; value: bool) =
  discard
proc getFlagScript2_2197824443*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197824516*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197824629*(flag: string) =
  discard
proc setOptionScript_2197824680*(option: string; value: JsonNode) =
  discard
proc quitScript_2197824772*() =
  discard
proc changeFontSizeScript_2197824816*(amount: float32) =
  discard
proc changeLayoutPropScript_2197824867*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825174*() =
  discard
proc createViewScript_2197825218*() =
  discard
proc closeCurrentViewScript_2197825266*() =
  discard
proc moveCurrentViewToTopScript_2197825355*() =
  discard
proc nextViewScript_2197825450*() =
  discard
proc prevViewScript_2197825500*() =
  discard
proc moveCurrentViewPrevScript_2197825553*() =
  discard
proc moveCurrentViewNextScript_2197825620*() =
  discard
proc setLayoutScript_2197825684*(layout: string) =
  discard
proc commandLineScript_2197825771*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197825826*() =
  discard
proc executeCommandLineScript_2197825874*(): bool =
  discard
proc openFileScript_2197825930*(path: string) =
  discard
proc writeFileScript_2197826023*(path: string = "") =
  discard
proc loadFileScript_2197826086*(path: string = "") =
  discard
proc loadThemeScript_2197826149*(name: string) =
  discard
proc chooseThemeScript_2197826236*() =
  discard
proc chooseFileScript_2197826549*(view: string = "new") =
  discard
proc reloadConfigScript_2197826671*() =
  discard
proc logOptionsScript_2197826756*() =
  discard
proc clearCommandsScript_2197826800*(context: string) =
  discard
proc getAllEditorsScript_2197826851*(): seq[EditorId] =
  discard
proc setModeScript22_2197827142*(mode: string) =
  discard
proc modeScript22_2197827225*(): string =
  discard
proc getContextWithModeScript22_2197827275*(context: string): string =
  discard
proc scriptRunActionScript_2197827550*(action: string; arg: string) =
  discard
proc scriptLogScript_2197827586*(message: string) =
  discard
proc addCommandScriptScript_2197827617*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197827690*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197827748*(): EditorId =
  discard
proc getActiveEditorScript_2197827785*(): EditorId =
  discard
proc getActiveEditor2Script_2197827816*(): EditorId =
  discard
proc loadCurrentConfigScript_2197827866*() =
  discard
proc sourceCurrentDocumentScript_2197827910*() =
  discard
proc getEditorScript_2197827954*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197827992*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197828059*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197828126*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197828225*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197828289*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197828357*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197828425*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197828501*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197828569*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197828647*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197828729*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197828776*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197828888*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197828935*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197828982*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197829057*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197829132*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197829207*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197829282*(path: string; id: int) =
  discard
