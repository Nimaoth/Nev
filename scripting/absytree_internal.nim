import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7683977460*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7683977652*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7683977701*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7683977757*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7683977852*(self: TextDocumentEditor) =
  discard
proc insertScript_7683977895*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7683978253*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7683978323*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7683978551*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7683978756*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7683978823*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7683978866*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7683978916*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7683978959*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7683979023*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7683979071*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7683979130*(self: TextDocumentEditor) =
  discard
proc redoScript_7683979221*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7683979290*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7683979402*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7683979487*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7683979542*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7683979597*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7683979930*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7683980156*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7683980207*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7683980258*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_7683980643*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7683980692*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7683980774*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7683980838*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7683980895*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7683980952*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7683981023*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7683981094*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7683981151*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7683981208*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7683981258*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7683981305*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7683981356*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7683981407*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7683981456*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7683981506*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7683981556*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7683981606*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7683981663*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7683981719*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7683981784*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7683981867*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7683982054*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7683982301*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7683982395*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7683982514*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7683982608*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7683982716*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7683982824*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7683982896*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7683984117*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7683984164*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7683984211*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7683984254*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7683984314*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7683984374*(self: TextDocumentEditor) =
  discard
proc acceptScript_8355054209*(self: SelectorPopup) =
  discard
proc cancelScript_8355054304*(self: SelectorPopup) =
  discard
proc prevScript_8355054353*(self: SelectorPopup) =
  discard
proc nextScript_8355054414*(self: SelectorPopup) =
  discard
proc moveCursorScript_8120185021*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8120185117*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8120185172*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8120185215*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8120185265*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8120185314*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8120185383*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8120185452*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8120185658*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8120185704*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8120185750*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8120185842*(self: AstDocumentEditor) =
  discard
proc redoScript2_8120185911*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8120185980*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8120186147*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8120186282*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8120186416*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8120186549*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8120186636*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8120186727*(self: AstDocumentEditor) =
  discard
proc wrapScript_8120186780*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8120186891*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8120186940*(self: AstDocumentEditor) =
  discard
proc renameScript_8120186997*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8120187040*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8120187100*(self: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8120187160*(self: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8120187316*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8120187359*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8120187402*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8120187448*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8120187595*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8120187743*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8120187786*(self: AstDocumentEditor) =
  discard
proc openGotoSymbolPopupScript_8120187846*(self: AstDocumentEditor) =
  discard
proc gotoScript_8120188128*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8120188600*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8120188862*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8120188916*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8120188966*(self: AstDocumentEditor) =
  discard
proc scrollScript_8120189416*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8120189470*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8120189531*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8120189578*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8120189660*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8120189709*(self: AstDocumentEditor;
    context: string): string =
  discard
proc scrollScript2_8422176225*(self: ModelDocumentEditor; amount: float32) =
  discard
proc setModeScript22_8422176327*(self: ModelDocumentEditor; mode: string) =
  discard
proc modeScript22_8422179287*(self: ModelDocumentEditor): string =
  discard
proc getContextWithModeScript22_8422179336*(self: ModelDocumentEditor;
    context: string): string =
  discard
proc moveCursorLeftScript_8422179392*(self: ModelDocumentEditor;
                                     select: bool = false) =
  discard
proc moveCursorRightScript_8422179472*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftLineScript_8422179552*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightLineScript_8422179634*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineStartScript_8422179716*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndScript_8422179799*(self: ModelDocumentEditor;
                                        select: bool = false) =
  discard
proc moveCursorLineStartInlineScript_8422179885*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndInlineScript_8422179968*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorUpScript2_8422180051*(self: ModelDocumentEditor;
                                    select: bool = false) =
  discard
proc moveCursorDownScript2_8422180156*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftCellScript_8422180261*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightCellScript_8422180363*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNodeScript_8422180465*(self: ModelDocumentEditor; select: bool = false) =
  discard
proc selectParentCellScript_8422180597*(self: ModelDocumentEditor) =
  discard
proc selectPrevPlaceholderScript_8422180653*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNextPlaceholderScript_8422180732*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc deleteLeftScript2_8422181669*(self: ModelDocumentEditor) =
  discard
proc deleteRightScript2_8422181712*(self: ModelDocumentEditor) =
  discard
proc createNewNodeScript_8422182090*(self: ModelDocumentEditor) =
  discard
proc insertTextAtCursorScript_8422182376*(self: ModelDocumentEditor;
    input: string): bool =
  discard
proc undoScript22_8422182548*(self: ModelDocumentEditor) =
  discard
proc redoScript22_8422182636*(self: ModelDocumentEditor) =
  discard
proc toggleUseDefaultCellBuilderScript_8422182705*(self: ModelDocumentEditor) =
  discard
proc showCompletionsScript_8422182748*(self: ModelDocumentEditor) =
  discard
proc hideCompletionsScript2_8422182791*(self: ModelDocumentEditor) =
  discard
proc selectPrevCompletionScript22_8422182838*(self: ModelDocumentEditor) =
  discard
proc selectNextCompletionScript22_8422182889*(self: ModelDocumentEditor) =
  discard
proc applySelectedCompletionScript22_8422182940*(self: ModelDocumentEditor) =
  discard
proc getBackendScript_2197823672*(): Backend =
  discard
proc saveAppStateScript_2197823831*() =
  discard
proc requestRenderScript_2197824660*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824704*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824755*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824806*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824857*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197824985*() =
  discard
proc openGithubWorkspaceScript_2197825026*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825084*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825128*(path: string) =
  discard
proc getFlagScript2_2197825173*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825239*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825345*(flag: string) =
  discard
proc setOptionScript_2197825389*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825474*() =
  discard
proc changeFontSizeScript_2197825511*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825555*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825873*() =
  discard
proc createViewScript_2197825910*() =
  discard
proc closeCurrentViewScript_2197825952*() =
  discard
proc moveCurrentViewToTopScript_2197826034*() =
  discard
proc nextViewScript_2197826122*() =
  discard
proc prevViewScript_2197826165*() =
  discard
proc moveCurrentViewPrevScript_2197826211*() =
  discard
proc moveCurrentViewNextScript_2197826271*() =
  discard
proc setLayoutScript_2197826328*(layout: string) =
  discard
proc commandLineScript_2197826408*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826456*() =
  discard
proc executeCommandLineScript_2197826497*(): bool =
  discard
proc writeFileScript_2197826667*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826730*(path: string = "") =
  discard
proc openFileScript_2197826805*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197826975*() =
  discard
proc loadThemeScript_2197827012*(name: string) =
  discard
proc chooseThemeScript_2197827092*() =
  discard
proc chooseFileScript_2197827725*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828019*(token: string) =
  discard
proc reloadConfigScript_2197828063*() =
  discard
proc logOptionsScript_2197828141*() =
  discard
proc clearCommandsScript_2197828178*(context: string) =
  discard
proc getAllEditorsScript_2197828222*(): seq[EditorId] =
  discard
proc setModeScript222_2197828524*(mode: string) =
  discard
proc modeScript222_2197828600*(): string =
  discard
proc getContextWithModeScript222_2197828643*(context: string): string =
  discard
proc scriptRunActionScript_2197828920*(action: string; arg: string) =
  discard
proc scriptLogScript_2197828949*(message: string) =
  discard
proc addCommandScriptScript_2197828973*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829039*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829090*(): EditorId =
  discard
proc getActiveEditorScript_2197829120*(): EditorId =
  discard
proc getActiveEditor2Script_2197829144*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829187*() =
  discard
proc sourceCurrentDocumentScript_2197829224*() =
  discard
proc getEditorScript_2197829261*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829292*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829352*(editorId: EditorId): bool =
  discard
proc scriptIsModelEditorScript_2197829412*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829472*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829564*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197829621*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197829682*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197829743*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197829812*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197829873*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197829944*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830019*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830059*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830157*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830197*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830237*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830305*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830373*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830441*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830509*(path: string; id: int) =
  discard
