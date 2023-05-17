import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_6123696372*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_6123696564*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_6123696613*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_6123696669*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_6123696764*(self: TextDocumentEditor) =
  discard
proc insertScript_6123696807*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_6123697165*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_6123697235*(self: TextDocumentEditor) =
  discard
proc selectNextScript_6123697463*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_6123697668*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_6123697735*(self: TextDocumentEditor) =
  discard
proc selectLineScript_6123697778*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_6123697828*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_6123697871*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_6123697935*(self: TextDocumentEditor) =
  discard
proc insertTextScript_6123697983*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_6123698042*(self: TextDocumentEditor) =
  discard
proc redoScript_6123698133*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_6123698202*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_6123698314*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_6123698399*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_6123698454*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_6123698509*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_6123698842*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_6123699068*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_6123699119*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_6123699170*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_6123699555*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_6123699604*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_6123699686*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_6123699750*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_6123699807*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_6123699864*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_6123699935*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_6123700006*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_6123700063*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_6123700120*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_6123700170*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_6123700217*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_6123700268*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_6123700319*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_6123700368*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_6123700418*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_6123700468*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_6123700518*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_6123700575*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_6123700631*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_6123700696*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_6123700779*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_6123700966*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_6123701213*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_6123701307*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_6123701426*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_6123701520*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_6123701628*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_6123701736*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_6123701808*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_6123703116*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_6123703163*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_6123703210*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_6123703253*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_6123703313*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_6123703373*(self: TextDocumentEditor) =
  discard
proc acceptScript_6593446558*(self: SelectorPopup) =
  discard
proc cancelScript_6593446653*(self: SelectorPopup) =
  discard
proc prevScript_6593446702*(self: SelectorPopup) =
  discard
proc nextScript_6593446763*(self: SelectorPopup) =
  discard
proc moveCursorScript_6425686203*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_6425686299*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_6425686354*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_6425686397*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_6425686447*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_6425686496*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_6425686565*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_6425686634*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_6425686840*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_6425686886*(self: AstDocumentEditor) =
  discard
proc finishEditScript_6425686932*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_6425687024*(self: AstDocumentEditor) =
  discard
proc redoScript2_6425687093*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_6425687162*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_6425687329*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_6425687464*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_6425687598*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_6425687731*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_6425687818*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_6425687909*(self: AstDocumentEditor) =
  discard
proc wrapScript_6425687962*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_6425688073*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_6425688122*(self: AstDocumentEditor) =
  discard
proc renameScript_6425688179*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_6425688222*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_6425688282*(self: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_6425688342*(self: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_6425688498*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_6425688541*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_6425688584*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_6425688630*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_6425688777*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_6425688925*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_6425688968*(self: AstDocumentEditor) =
  discard
proc openGotoSymbolPopupScript_6425689028*(self: AstDocumentEditor) =
  discard
proc gotoScript_6425689310*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_6425689782*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_6425690044*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_6425690098*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_6425690148*(self: AstDocumentEditor) =
  discard
proc scrollScript_6425690598*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_6425690652*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_6425690713*(self: AstDocumentEditor) =
  discard
proc setModeScript2_6425690760*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_6425690842*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_6425690891*(self: AstDocumentEditor;
    context: string): string =
  discard
proc scrollScript2_6643787428*(self: ModelDocumentEditor; amount: float32) =
  discard
proc setModeScript22_6643787530*(self: ModelDocumentEditor; mode: string) =
  discard
proc modeScript22_6643790627*(self: ModelDocumentEditor): string =
  discard
proc getContextWithModeScript22_6643790676*(self: ModelDocumentEditor;
    context: string): string =
  discard
proc moveCursorLeftScript_6643790732*(self: ModelDocumentEditor;
                                     select: bool = false) =
  discard
proc moveCursorRightScript_6643790812*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftLineScript_6643790892*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightLineScript_6643790974*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineStartScript_6643791056*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndScript_6643791139*(self: ModelDocumentEditor;
                                        select: bool = false) =
  discard
proc moveCursorLineStartInlineScript_6643791225*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndInlineScript_6643791308*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorUpScript2_6643791391*(self: ModelDocumentEditor;
                                    select: bool = false) =
  discard
proc moveCursorDownScript2_6643791496*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftCellScript_6643791601*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightCellScript_6643791703*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNodeScript_6643791805*(self: ModelDocumentEditor; select: bool = false) =
  discard
proc selectParentCellScript_6643791937*(self: ModelDocumentEditor) =
  discard
proc selectPrevPlaceholderScript_6643791993*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNextPlaceholderScript_6643792072*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc deleteLeftScript2_6643793001*(self: ModelDocumentEditor) =
  discard
proc deleteRightScript2_6643793044*(self: ModelDocumentEditor) =
  discard
proc createNewNodeScript_6643793638*(self: ModelDocumentEditor) =
  discard
proc insertTextAtCursorScript_6643793722*(self: ModelDocumentEditor;
    input: string): bool =
  discard
proc undoScript22_6643793894*(self: ModelDocumentEditor) =
  discard
proc redoScript22_6643794195*(self: ModelDocumentEditor) =
  discard
proc toggleUseDefaultCellBuilderScript_6643794395*(self: ModelDocumentEditor) =
  discard
proc showCompletionsScript_6643794438*(self: ModelDocumentEditor) =
  discard
proc hideCompletionsScript2_6643794481*(self: ModelDocumentEditor) =
  discard
proc selectPrevCompletionScript22_6643794528*(self: ModelDocumentEditor) =
  discard
proc selectNextCompletionScript22_6643794579*(self: ModelDocumentEditor) =
  discard
proc applySelectedCompletionScript22_6643794630*(self: ModelDocumentEditor) =
  discard
proc getBackendScript_1946165457*(): Backend =
  discard
proc saveAppStateScript_1946165616*() =
  discard
proc requestRenderScript_1946166445*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_1946166489*(context: string; value: bool) =
  discard
proc setHandleActionsScript_1946166540*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_1946166591*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_1946166642*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_1946166770*() =
  discard
proc openGithubWorkspaceScript_1946166811*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_1946166869*(url: string) =
  discard
proc openLocalWorkspaceScript_1946166913*(path: string) =
  discard
proc getFlagScript2_1946166958*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_1946167024*(flag: string; value: bool) =
  discard
proc toggleFlagScript_1946167130*(flag: string) =
  discard
proc setOptionScript_1946167174*(option: string; value: JsonNode) =
  discard
proc quitScript_1946167259*() =
  discard
proc changeFontSizeScript_1946167296*(amount: float32) =
  discard
proc changeLayoutPropScript_1946167340*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_1946167658*() =
  discard
proc createViewScript_1946167695*() =
  discard
proc closeCurrentViewScript_1946167737*() =
  discard
proc moveCurrentViewToTopScript_1946167819*() =
  discard
proc nextViewScript_1946167907*() =
  discard
proc prevViewScript_1946167950*() =
  discard
proc moveCurrentViewPrevScript_1946167996*() =
  discard
proc moveCurrentViewNextScript_1946168056*() =
  discard
proc setLayoutScript_1946168113*(layout: string) =
  discard
proc commandLineScript_1946168193*(initialValue: string = "") =
  discard
proc exitCommandLineScript_1946168241*() =
  discard
proc executeCommandLineScript_1946168282*(): bool =
  discard
proc writeFileScript_1946168452*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_1946168515*(path: string = "") =
  discard
proc openFileScript_1946168590*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_1946168760*() =
  discard
proc loadThemeScript_1946168797*(name: string) =
  discard
proc chooseThemeScript_1946168877*() =
  discard
proc chooseFileScript_1946169539*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_1946169833*(token: string) =
  discard
proc reloadConfigScript_1946169877*() =
  discard
proc logOptionsScript_1946169955*() =
  discard
proc clearCommandsScript_1946169992*(context: string) =
  discard
proc getAllEditorsScript_1946170036*(): seq[EditorId] =
  discard
proc setModeScript222_1946170338*(mode: string) =
  discard
proc modeScript222_1946170414*(): string =
  discard
proc getContextWithModeScript222_1946170457*(context: string): string =
  discard
proc scriptRunActionScript_1946170734*(action: string; arg: string) =
  discard
proc scriptLogScript_1946170763*(message: string) =
  discard
proc addCommandScriptScript_1946170787*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_1946170853*(context: string; keys: string) =
  discard
proc getActivePopupScript_1946170904*(): EditorId =
  discard
proc getActiveEditorScript_1946170934*(): EditorId =
  discard
proc getActiveEditor2Script_1946170958*(): EditorId =
  discard
proc loadCurrentConfigScript_1946171001*() =
  discard
proc sourceCurrentDocumentScript_1946171038*() =
  discard
proc getEditorScript_1946171075*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_1946171106*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_1946171166*(editorId: EditorId): bool =
  discard
proc scriptIsModelEditorScript_1946171226*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_1946171286*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_1946171378*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_1946171435*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_1946171496*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_1946171557*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_1946171626*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_1946171687*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_1946171758*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_1946171833*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_1946171873*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_1946171971*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_1946172011*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_1946172051*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_1946172119*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_1946172187*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_1946172255*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_1946172323*(path: string; id: int) =
  discard
