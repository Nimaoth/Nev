import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7683976750*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7683976949*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7683977005*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7683977068*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7683977170*(self: TextDocumentEditor) =
  discard
proc insertScript_7683977220*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7683977585*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7683977662*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7683977875*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7683978065*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7683978139*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7683978189*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7683978246*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7683978296*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7683978367*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7683978422*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7683978488*(self: TextDocumentEditor) =
  discard
proc redoScript_7683978586*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7683978662*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7683978781*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7683978873*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7683978935*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7683978997*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7683979318*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7683979536*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7683979594*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7683979652*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_7683980014*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7683980070*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7683980159*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7683980230*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7683980294*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7683980358*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7683980436*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7683980514*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7683980578*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7683980642*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7683980699*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7683980753*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7683980811*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7683980869*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7683980925*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7683980982*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7683981039*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7683981096*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7683981160*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7683981223*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7683981295*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7683981385*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7683981579*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7683981833*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7683981934*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7683982060*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7683982161*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7683982276*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7683982391*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7683982470*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7683983275*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7683983329*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7683983383*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7683983433*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7683983497*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7683983561*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_8120184417*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8120184520*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8120184582*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8120184632*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8120184689*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8120184745*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8120184821*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8120184897*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8120185110*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8120185163*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8120185216*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8120185315*(self: AstDocumentEditor) =
  discard
proc redoScript2_8120185391*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8120185467*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8120185641*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8120185783*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8120185924*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8120186064*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8120186158*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8120186256*(self: AstDocumentEditor) =
  discard
proc wrapScript_8120186316*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8120186434*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8120186490*(self: AstDocumentEditor) =
  discard
proc renameScript_8120186554*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8120186604*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8120186665*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8120186726*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8120186889*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8120186939*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8120186989*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8120187042*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8120187196*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8120187351*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8120187401*(self: AstDocumentEditor) =
  discard
proc gotoScript_8120187451*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8120188305*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8120188574*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8120188635*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8120188692*(self: AstDocumentEditor) =
  discard
proc scrollScript_8120189149*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8120189210*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8120189278*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8120189332*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8120189421*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8120189477*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8388608560*(self: SelectorPopup) =
  discard
proc cancelScript_8388608659*(self: SelectorPopup) =
  discard
proc prevScript_8388608715*(self: SelectorPopup) =
  discard
proc nextScript_8388608783*(self: SelectorPopup) =
  discard
proc getBackendScript_2197823655*(): Backend =
  discard
proc saveAppStateScript_2197823821*() =
  discard
proc requestRenderScript_2197824612*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824663*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824721*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824779*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824837*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197824972*() =
  discard
proc openGithubWorkspaceScript_2197825020*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825085*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825136*(path: string) =
  discard
proc getFlagScript2_2197825188*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825261*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825374*(flag: string) =
  discard
proc setOptionScript_2197825425*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825517*() =
  discard
proc changeFontSizeScript_2197825561*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825612*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825937*() =
  discard
proc createViewScript_2197825981*() =
  discard
proc closeCurrentViewScript_2197826030*() =
  discard
proc moveCurrentViewToTopScript_2197826119*() =
  discard
proc nextViewScript_2197826214*() =
  discard
proc prevViewScript_2197826264*() =
  discard
proc moveCurrentViewPrevScript_2197826317*() =
  discard
proc moveCurrentViewNextScript_2197826384*() =
  discard
proc setLayoutScript_2197826448*(layout: string) =
  discard
proc commandLineScript_2197826535*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826590*() =
  discard
proc executeCommandLineScript_2197826638*(): bool =
  discard
proc writeFileScript_2197826797*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826867*(path: string = "") =
  discard
proc openFileScript_2197826949*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827117*() =
  discard
proc loadThemeScript_2197827161*(name: string) =
  discard
proc chooseThemeScript_2197827248*() =
  discard
proc chooseFileScript_2197828009*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828310*(token: string) =
  discard
proc reloadConfigScript_2197828361*() =
  discard
proc logOptionsScript_2197828446*() =
  discard
proc clearCommandsScript_2197828490*(context: string) =
  discard
proc getAllEditorsScript_2197828541*(): seq[EditorId] =
  discard
proc setModeScript22_2197828850*(mode: string) =
  discard
proc modeScript22_2197828933*(): string =
  discard
proc getContextWithModeScript22_2197828983*(context: string): string =
  discard
proc scriptRunActionScript_2197829267*(action: string; arg: string) =
  discard
proc scriptLogScript_2197829303*(message: string) =
  discard
proc addCommandScriptScript_2197829334*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829407*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829465*(): EditorId =
  discard
proc getActiveEditorScript_2197829502*(): EditorId =
  discard
proc getActiveEditor2Script_2197829533*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829583*() =
  discard
proc sourceCurrentDocumentScript_2197829627*() =
  discard
proc getEditorScript_2197829671*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829709*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829776*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829843*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829942*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197830006*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197830074*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197830142*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197830218*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197830286*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197830364*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830446*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830493*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830598*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830645*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830692*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830767*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830842*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830917*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830992*(path: string; id: int) =
  discard
