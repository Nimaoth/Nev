import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_8304734452*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_8304734644*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_8304734693*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_8304734749*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_8304734844*(self: TextDocumentEditor) =
  discard
proc insertScript_8304734887*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_8304735245*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_8304735315*(self: TextDocumentEditor) =
  discard
proc selectNextScript_8304735543*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_8304735748*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_8304735815*(self: TextDocumentEditor) =
  discard
proc selectLineScript_8304735858*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_8304735908*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_8304735951*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_8304736015*(self: TextDocumentEditor) =
  discard
proc insertTextScript_8304736063*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_8304736122*(self: TextDocumentEditor) =
  discard
proc redoScript_8304736213*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_8304736282*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_8304736394*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_8304736479*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_8304736534*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_8304736589*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_8304736922*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_8304737148*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_8304737199*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_8304737250*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_8304737635*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_8304737684*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_8304737766*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_8304737830*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_8304737887*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_8304737944*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_8304738015*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_8304738086*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_8304738143*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_8304738200*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_8304738250*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_8304738297*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_8304738348*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_8304738399*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_8304738448*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_8304738498*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_8304738548*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_8304738598*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_8304738655*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_8304738711*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_8304738776*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_8304738859*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_8304739046*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_8304739293*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_8304739387*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_8304739506*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_8304739600*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_8304739708*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_8304739816*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_8304739888*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_8304741109*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_8304741156*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_8304741203*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_8304741246*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_8304741306*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_8304741366*(self: TextDocumentEditor) =
  discard
proc acceptScript_8942256769*(self: SelectorPopup) =
  discard
proc cancelScript_8942256864*(self: SelectorPopup) =
  discard
proc prevScript_8942256913*(self: SelectorPopup) =
  discard
proc nextScript_8942256974*(self: SelectorPopup) =
  discard
proc moveCursorScript_8707387579*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8707387675*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8707387730*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8707387773*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8707387823*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8707387872*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8707387941*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8707388010*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8707388216*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8707388262*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8707388308*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8707388400*(self: AstDocumentEditor) =
  discard
proc redoScript2_8707388469*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8707388538*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8707388705*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8707388840*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8707388974*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8707389107*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8707389194*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8707389285*(self: AstDocumentEditor) =
  discard
proc wrapScript_8707389338*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8707389449*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8707389498*(self: AstDocumentEditor) =
  discard
proc renameScript_8707389555*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8707389598*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8707389658*(self: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8707389718*(self: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8707389874*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8707389917*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8707389960*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8707390006*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8707390153*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8707390301*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8707390344*(self: AstDocumentEditor) =
  discard
proc openGotoSymbolPopupScript_8707390404*(self: AstDocumentEditor) =
  discard
proc gotoScript_8707390686*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8707391158*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8707391420*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8707391474*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8707391524*(self: AstDocumentEditor) =
  discard
proc scrollScript_8707391974*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8707392028*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8707392089*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8707392136*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8707392218*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8707392267*(self: AstDocumentEditor;
    context: string): string =
  discard
proc scrollScript2_9009376562*(self: ModelDocumentEditor; amount: float32) =
  discard
proc setModeScript22_9009376664*(self: ModelDocumentEditor; mode: string) =
  discard
proc modeScript22_9009379897*(self: ModelDocumentEditor): string =
  discard
proc getContextWithModeScript22_9009379946*(self: ModelDocumentEditor;
    context: string): string =
  discard
proc moveCursorLeftScript_9009380002*(self: ModelDocumentEditor;
                                     select: bool = false) =
  discard
proc moveCursorRightScript_9009380082*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftLineScript_9009380162*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightLineScript_9009380244*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineStartScript_9009380326*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndScript_9009380409*(self: ModelDocumentEditor;
                                        select: bool = false) =
  discard
proc moveCursorLineStartInlineScript_9009380495*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndInlineScript_9009380578*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorUpScript2_9009380661*(self: ModelDocumentEditor;
                                    select: bool = false) =
  discard
proc moveCursorDownScript2_9009380766*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftCellScript_9009380871*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightCellScript_9009380973*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNodeScript_9009381075*(self: ModelDocumentEditor; select: bool = false) =
  discard
proc selectParentCellScript_9009381207*(self: ModelDocumentEditor) =
  discard
proc selectPrevPlaceholderScript_9009381263*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNextPlaceholderScript_9009381342*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc deleteLeftScript2_9009382275*(self: ModelDocumentEditor) =
  discard
proc deleteRightScript2_9009382318*(self: ModelDocumentEditor) =
  discard
proc createNewNodeScript_9009382912*(self: ModelDocumentEditor) =
  discard
proc insertTextAtCursorScript_9009382996*(self: ModelDocumentEditor;
    input: string): bool =
  discard
proc undoScript22_9009383168*(self: ModelDocumentEditor) =
  discard
proc redoScript22_9009383533*(self: ModelDocumentEditor) =
  discard
proc toggleUseDefaultCellBuilderScript_9009383773*(self: ModelDocumentEditor) =
  discard
proc showCompletionsScript_9009383816*(self: ModelDocumentEditor) =
  discard
proc hideCompletionsScript2_9009383859*(self: ModelDocumentEditor) =
  discard
proc selectPrevCompletionScript22_9009383906*(self: ModelDocumentEditor) =
  discard
proc selectNextCompletionScript22_9009383957*(self: ModelDocumentEditor) =
  discard
proc applySelectedCompletionScript22_9009384008*(self: ModelDocumentEditor) =
  discard
proc getBackendScript_2197823711*(): Backend =
  discard
proc saveAppStateScript_2197823870*() =
  discard
proc requestRenderScript_2197824699*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824743*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824794*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824845*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824896*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197825024*() =
  discard
proc openGithubWorkspaceScript_2197825065*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825123*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825167*(path: string) =
  discard
proc getFlagScript2_2197825212*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825278*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825384*(flag: string) =
  discard
proc setOptionScript_2197825428*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825513*() =
  discard
proc changeFontSizeScript_2197825550*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825594*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825912*() =
  discard
proc createViewScript_2197825949*() =
  discard
proc closeCurrentViewScript_2197825991*() =
  discard
proc moveCurrentViewToTopScript_2197826073*() =
  discard
proc nextViewScript_2197826161*() =
  discard
proc prevViewScript_2197826204*() =
  discard
proc moveCurrentViewPrevScript_2197826250*() =
  discard
proc moveCurrentViewNextScript_2197826310*() =
  discard
proc setLayoutScript_2197826367*(layout: string) =
  discard
proc commandLineScript_2197826447*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826495*() =
  discard
proc executeCommandLineScript_2197826536*(): bool =
  discard
proc writeFileScript_2197826706*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826769*(path: string = "") =
  discard
proc openFileScript_2197826844*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827014*() =
  discard
proc loadThemeScript_2197827051*(name: string) =
  discard
proc chooseThemeScript_2197827131*() =
  discard
proc chooseFileScript_2197827764*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828058*(token: string) =
  discard
proc reloadConfigScript_2197828102*() =
  discard
proc logOptionsScript_2197828180*() =
  discard
proc clearCommandsScript_2197828217*(context: string) =
  discard
proc getAllEditorsScript_2197828261*(): seq[EditorId] =
  discard
proc setModeScript222_2197828563*(mode: string) =
  discard
proc modeScript222_2197828639*(): string =
  discard
proc getContextWithModeScript222_2197828682*(context: string): string =
  discard
proc scriptRunActionScript_2197828959*(action: string; arg: string) =
  discard
proc scriptLogScript_2197828988*(message: string) =
  discard
proc addCommandScriptScript_2197829012*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829078*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829129*(): EditorId =
  discard
proc getActiveEditorScript_2197829159*(): EditorId =
  discard
proc getActiveEditor2Script_2197829183*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829226*() =
  discard
proc sourceCurrentDocumentScript_2197829263*() =
  discard
proc getEditorScript_2197829300*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829331*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829391*(editorId: EditorId): bool =
  discard
proc scriptIsModelEditorScript_2197829451*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829511*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829603*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197829660*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197829721*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197829782*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197829851*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197829912*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197829983*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830058*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830098*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830196*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830236*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830276*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830344*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830412*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830480*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830548*(path: string; id: int) =
  discard
