import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_8287957247*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_8287957486*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_8287957548*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_8287957618*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_8287957727*(self: TextDocumentEditor) =
  discard
proc insertScript_8287957783*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_8287958207*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_8287958307*(self: TextDocumentEditor) =
  discard
proc selectNextScript_8287958548*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_8287958766*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_8287958849*(self: TextDocumentEditor) =
  discard
proc selectLineScript_8287958905*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_8287958969*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_8287959025*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_8287959104*(self: TextDocumentEditor) =
  discard
proc insertTextScript_8287959165*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_8287959238*(self: TextDocumentEditor) =
  discard
proc redoScript_8287959346*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_8287959432*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_8287959558*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_8287959656*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_8287959728*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_8287959796*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_8287960151*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_8287960401*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_8287960465*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_8287960529*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_8287960942*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_8287961004*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_8287961147*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_8287961227*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_8287961301*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_8287961375*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_8287961487*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_8287961599*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_8287961671*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_8287961743*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_8287961807*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_8287961931*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_8287962001*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_8287962071*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_8287962133*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_8287962197*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_8287962261*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_8287962325*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_8287962397*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_8287962467*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_8287962547*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_8287962646*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_8287962892*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_8287963153*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_8287963289*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_8287963473*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_8287963609*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_8287963761*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_8287963913*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_8287963999*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_8287965235*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_8287965524*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_8287965666*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_8287965722*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_8287965795*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_8287965868*(self: TextDocumentEditor) =
  discard
proc acceptScript_8925479553*(self: SelectorPopup) =
  discard
proc cancelScript_8925479665*(self: SelectorPopup) =
  discard
proc prevScript_8925479727*(self: SelectorPopup) =
  discard
proc nextScript_8925479801*(self: SelectorPopup) =
  discard
proc moveCursorScript_8690610363*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8690610473*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8690610541*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8690610597*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8690610671*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8690610743*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8690610834*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8690610926*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8690611146*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8690611234*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8690611293*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8690611408*(self: AstDocumentEditor) =
  discard
proc redoScript2_8690611490*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8690611572*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8690611991*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8690612175*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8690612358*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8690612540*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8690612676*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8690612816*(self: AstDocumentEditor) =
  discard
proc wrapScript_8690612882*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8690613054*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8690613123*(self: AstDocumentEditor) =
  discard
proc renameScript_8690613230*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8690613286*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8690613359*(self: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8690613432*(self: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8690613672*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8690613728*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8690613784*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8690613843*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8690614011*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8690614183*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8690614240*(self: AstDocumentEditor) =
  discard
proc openGotoSymbolPopupScript_8690614314*(self: AstDocumentEditor) =
  discard
proc gotoScript_8690614645*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8690615243*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8690615519*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8690615587*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8690615651*(self: AstDocumentEditor) =
  discard
proc scrollScript_8690616134*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8690616202*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8690616277*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8690616337*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8690616459*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8690616521*(self: AstDocumentEditor;
    context: string): string =
  discard
proc scrollScript2_8992600587*(self: ModelDocumentEditor; amount: float32) =
  discard
proc setModeScript22_8992600703*(self: ModelDocumentEditor; mode: string) =
  discard
proc modeScript22_8992603840*(self: ModelDocumentEditor): string =
  discard
proc getContextWithModeScript22_8992603902*(self: ModelDocumentEditor;
    context: string): string =
  discard
proc moveCursorLeftScript_8992603972*(self: ModelDocumentEditor;
                                     select: bool = false) =
  discard
proc moveCursorRightScript_8992604077*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftLineScript_8992604171*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightLineScript_8992604276*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineStartScript_8992604382*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndScript_8992604479*(self: ModelDocumentEditor;
                                        select: bool = false) =
  discard
proc moveCursorLineStartInlineScript_8992604579*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndInlineScript_8992604677*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorUpScript2_8992604775*(self: ModelDocumentEditor;
                                    select: bool = false) =
  discard
proc moveCursorDownScript2_8992604899*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftCellScript_8992605018*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightCellScript_8992605134*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNodeScript_8992605250*(self: ModelDocumentEditor; select: bool = false) =
  discard
proc selectParentCellScript_8992605396*(self: ModelDocumentEditor) =
  discard
proc selectPrevPlaceholderScript_8992605465*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNextPlaceholderScript_8992605558*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc deleteLeftScript2_8992606501*(self: ModelDocumentEditor) =
  discard
proc deleteRightScript2_8992606637*(self: ModelDocumentEditor) =
  discard
proc createNewNodeScript_8992607244*(self: ModelDocumentEditor) =
  discard
proc insertTextAtCursorScript_8992607379*(self: ModelDocumentEditor;
    input: string): bool =
  discard
proc undoScript22_8992607565*(self: ModelDocumentEditor) =
  discard
proc redoScript22_8992607906*(self: ModelDocumentEditor) =
  discard
proc toggleUseDefaultCellBuilderScript_8992608123*(self: ModelDocumentEditor) =
  discard
proc showCompletionsScript_8992608179*(self: ModelDocumentEditor) =
  discard
proc hideCompletionsScript2_8992608235*(self: ModelDocumentEditor) =
  discard
proc selectPrevCompletionScript22_8992608295*(self: ModelDocumentEditor) =
  discard
proc selectNextCompletionScript22_8992608359*(self: ModelDocumentEditor) =
  discard
proc applySelectedCompletionScript22_8992608423*(self: ModelDocumentEditor) =
  discard
proc getBackendScript_2197823683*(): Backend =
  discard
proc saveAppStateScript_2197823854*() =
  discard
proc requestRenderScript_2197824706*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824763*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824828*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824893*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824958*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197825100*() =
  discard
proc openGithubWorkspaceScript_2197825157*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825234*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825291*(path: string) =
  discard
proc getFlagScript2_2197825349*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825429*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825555*(flag: string) =
  discard
proc setOptionScript_2197825612*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825716*() =
  discard
proc changeFontSizeScript_2197825765*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825822*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197826154*() =
  discard
proc createViewScript_2197826203*() =
  discard
proc closeCurrentViewScript_2197826285*() =
  discard
proc moveCurrentViewToTopScript_2197826379*() =
  discard
proc nextViewScript_2197826479*() =
  discard
proc prevViewScript_2197826534*() =
  discard
proc moveCurrentViewPrevScript_2197826592*() =
  discard
proc moveCurrentViewNextScript_2197826664*() =
  discard
proc setLayoutScript_2197826733*(layout: string) =
  discard
proc commandLineScript_2197826826*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826887*() =
  discard
proc executeCommandLineScript_2197826940*(): bool =
  discard
proc writeFileScript_2197827122*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197827199*(path: string = "") =
  discard
proc openFileScript_2197827287*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827471*() =
  discard
proc loadThemeScript_2197827520*(name: string) =
  discard
proc chooseThemeScript_2197827613*() =
  discard
proc chooseFileScript_2197828311*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828874*(token: string) =
  discard
proc reloadConfigScript_2197828931*() =
  discard
proc logOptionsScript_2197829022*() =
  discard
proc clearCommandsScript_2197829071*(context: string) =
  discard
proc getAllEditorsScript_2197829128*(): seq[EditorId] =
  discard
proc setModeScript222_2197829453*(mode: string) =
  discard
proc modeScript222_2197829568*(): string =
  discard
proc getContextWithModeScript222_2197829623*(context: string): string =
  discard
proc scriptRunActionScript_2197829913*(action: string; arg: string) =
  discard
proc scriptLogScript_2197829955*(message: string) =
  discard
proc addCommandScriptScript_2197829991*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197830073*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197830138*(): EditorId =
  discard
proc getActiveEditorScript_2197830179*(): EditorId =
  discard
proc getActiveEditor2Script_2197830214*(): EditorId =
  discard
proc loadCurrentConfigScript_2197830269*() =
  discard
proc sourceCurrentDocumentScript_2197830318*() =
  discard
proc getEditorScript_2197830367*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197830410*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197830482*(editorId: EditorId): bool =
  discard
proc scriptIsModelEditorScript_2197830554*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197830626*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197830732*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197830802*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197830879*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197830953*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197831034*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197831108*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197831192*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197831279*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197831333*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197831445*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197831499*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197831553*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197831640*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197831727*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197831814*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197831901*(path: string; id: int) =
  discard
