import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7667196777*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7667196976*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7667197032*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7667197095*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7667197197*(self: TextDocumentEditor) =
  discard
proc insertScript_7667197247*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7667197612*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7667197689*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7667197902*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7667198092*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7667198166*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7667198216*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7667198273*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7667198323*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7667198394*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7667198449*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7667198515*(self: TextDocumentEditor) =
  discard
proc redoScript_7667198613*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7667198689*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7667198808*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7667198900*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7667198962*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7667199024*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7667199345*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7667199563*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7667199621*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7667199679*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7667200041*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7667200130*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7667200201*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7667200265*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7667200329*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7667200407*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7667200485*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7667200549*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7667200613*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7667200670*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7667200724*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7667200782*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7667200840*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7667200896*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7667200953*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7667201010*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7667201067*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7667201131*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7667201194*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7667201267*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7667201357*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7667201551*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7667201805*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7667201906*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7667202032*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7667202133*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7667202248*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7667202363*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7667202442*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7667203247*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7667203301*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7667203355*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7667203405*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7667203469*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7667203533*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_8103406873*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8103406976*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8103407038*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8103407088*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8103407145*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8103407201*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8103407277*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8103407353*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8103407566*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8103407619*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8103407672*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8103407771*(self: AstDocumentEditor) =
  discard
proc redoScript2_8103407847*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8103407923*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8103408097*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8103408239*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8103408380*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8103408520*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8103408614*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8103408712*(self: AstDocumentEditor) =
  discard
proc wrapScript_8103408772*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8103408890*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8103408946*(self: AstDocumentEditor) =
  discard
proc renameScript_8103409010*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8103409060*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8103409121*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8103409182*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8103409345*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8103409395*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8103409445*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8103409498*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8103409652*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8103409807*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8103409857*(self: AstDocumentEditor) =
  discard
proc gotoScript_8103409907*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8103410743*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8103411012*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8103411073*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8103411130*(self: AstDocumentEditor) =
  discard
proc scrollScript_8103411587*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8103411648*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8103411716*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8103411770*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8103411859*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8103411915*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8371831227*(self: SelectorPopup) =
  discard
proc cancelScript_8371831326*(self: SelectorPopup) =
  discard
proc prevScript_8371831382*(self: SelectorPopup) =
  discard
proc nextScript_8371831450*(self: SelectorPopup) =
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
proc openLocalWorkspaceScript_2197824764*(path: string) =
  discard
proc getFlagScript2_2197824820*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197824893*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825006*(flag: string) =
  discard
proc setOptionScript_2197825057*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825149*() =
  discard
proc changeFontSizeScript_2197825193*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825244*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825569*() =
  discard
proc createViewScript_2197825613*() =
  discard
proc closeCurrentViewScript_2197825661*() =
  discard
proc moveCurrentViewToTopScript_2197825750*() =
  discard
proc nextViewScript_2197825845*() =
  discard
proc prevViewScript_2197825895*() =
  discard
proc moveCurrentViewPrevScript_2197825948*() =
  discard
proc moveCurrentViewNextScript_2197826015*() =
  discard
proc setLayoutScript_2197826079*(layout: string) =
  discard
proc commandLineScript_2197826166*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826221*() =
  discard
proc executeCommandLineScript_2197826269*(): bool =
  discard
proc openFileScript_2197826325*(path: string) =
  discard
proc writeFileScript_2197826581*(path: string = "") =
  discard
proc loadFileScript_2197826644*(path: string = "") =
  discard
proc loadThemeScript_2197826713*(name: string) =
  discard
proc chooseThemeScript_2197826800*() =
  discard
proc chooseFileScript_2197827122*(view: string = "new") =
  discard
proc reloadConfigScript_2197827528*() =
  discard
proc logOptionsScript_2197827613*() =
  discard
proc clearCommandsScript_2197827657*(context: string) =
  discard
proc getAllEditorsScript_2197827708*(): seq[EditorId] =
  discard
proc setModeScript22_2197828017*(mode: string) =
  discard
proc modeScript22_2197828100*(): string =
  discard
proc getContextWithModeScript22_2197828150*(context: string): string =
  discard
proc scriptRunActionScript_2197828425*(action: string; arg: string) =
  discard
proc scriptLogScript_2197828461*(message: string) =
  discard
proc addCommandScriptScript_2197828492*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197828565*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197828623*(): EditorId =
  discard
proc getActiveEditorScript_2197828660*(): EditorId =
  discard
proc getActiveEditor2Script_2197828691*(): EditorId =
  discard
proc loadCurrentConfigScript_2197828741*() =
  discard
proc sourceCurrentDocumentScript_2197828785*() =
  discard
proc getEditorScript_2197828829*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197828867*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197828934*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829001*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829100*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197829164*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197829232*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197829300*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197829376*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197829444*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197829522*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197829604*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197829651*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197829763*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197829810*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197829857*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197829932*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830007*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830082*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830157*(path: string; id: int) =
  discard
