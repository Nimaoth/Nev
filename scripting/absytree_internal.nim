import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7667199534*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7667199733*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7667199789*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7667199852*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7667199954*(self: TextDocumentEditor) =
  discard
proc insertScript_7667200004*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7667200369*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7667200446*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7667200659*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7667200849*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7667200923*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7667200973*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7667201030*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7667201080*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7667201151*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7667201206*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7667201272*(self: TextDocumentEditor) =
  discard
proc redoScript_7667201370*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7667201446*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7667201565*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7667201657*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7667201719*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7667201781*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7667202102*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7667202320*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7667202378*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7667202436*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7667202798*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7667202887*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7667202958*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7667203022*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7667203086*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7667203164*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7667203242*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7667203306*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7667203370*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7667203427*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7667203481*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7667203539*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7667203597*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7667203653*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7667203710*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7667203767*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7667203824*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7667203888*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7667203951*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7667204024*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7667204114*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7667204308*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7667204562*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7667204663*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7667204789*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7667204890*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7667205005*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7667205120*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7667205199*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7667206004*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7667206058*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7667206112*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7667206162*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7667206226*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7667206290*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_8103407201*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8103407304*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8103407366*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8103407416*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8103407473*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8103407529*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8103407605*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8103407681*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8103407894*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8103407947*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8103408000*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8103408099*(self: AstDocumentEditor) =
  discard
proc redoScript2_8103408175*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8103408251*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8103408425*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8103408567*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8103408708*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8103408848*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8103408942*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8103409040*(self: AstDocumentEditor) =
  discard
proc wrapScript_8103409100*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8103409218*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8103409274*(self: AstDocumentEditor) =
  discard
proc renameScript_8103409338*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8103409388*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8103409449*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8103409510*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8103409673*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8103409723*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8103409773*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8103409826*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8103409980*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8103410135*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8103410185*(self: AstDocumentEditor) =
  discard
proc gotoScript_8103410235*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8103411089*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8103411358*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8103411419*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8103411476*(self: AstDocumentEditor) =
  discard
proc scrollScript_8103411933*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8103411994*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8103412062*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8103412116*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8103412205*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8103412261*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8371831342*(self: SelectorPopup) =
  discard
proc cancelScript_8371831441*(self: SelectorPopup) =
  discard
proc prevScript_8371831497*(self: SelectorPopup) =
  discard
proc nextScript_8371831565*(self: SelectorPopup) =
  discard
proc getBackendScript_2197824531*(): Backend =
  discard
proc saveAppStateScript_2197824697*() =
  discard
proc requestRenderScript_2197825488*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197825539*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197825597*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197825655*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197825713*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197825848*() =
  discard
proc openGithubWorkspaceScript_2197825896*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825961*(url: string) =
  discard
proc openLocalWorkspaceScript_2197826012*(path: string) =
  discard
proc getFlagScript2_2197826064*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197826137*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197826250*(flag: string) =
  discard
proc setOptionScript_2197826301*(option: string; value: JsonNode) =
  discard
proc quitScript_2197826393*() =
  discard
proc changeFontSizeScript_2197826437*(amount: float32) =
  discard
proc changeLayoutPropScript_2197826488*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197826813*() =
  discard
proc createViewScript_2197826857*() =
  discard
proc closeCurrentViewScript_2197826906*() =
  discard
proc moveCurrentViewToTopScript_2197826995*() =
  discard
proc nextViewScript_2197827090*() =
  discard
proc prevViewScript_2197827140*() =
  discard
proc moveCurrentViewPrevScript_2197827193*() =
  discard
proc moveCurrentViewNextScript_2197827260*() =
  discard
proc setLayoutScript_2197827324*(layout: string) =
  discard
proc commandLineScript_2197827411*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197827466*() =
  discard
proc executeCommandLineScript_2197827514*(): bool =
  discard
proc writeFileScript_2197827673*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197827743*(path: string = "") =
  discard
proc openFileScript_2197827825*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827993*() =
  discard
proc loadThemeScript_2197828037*(name: string) =
  discard
proc chooseThemeScript_2197828124*() =
  discard
proc chooseFileScript_2197828848*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197829146*(token: string) =
  discard
proc reloadConfigScript_2197829197*() =
  discard
proc logOptionsScript_2197829282*() =
  discard
proc clearCommandsScript_2197829326*(context: string) =
  discard
proc getAllEditorsScript_2197829377*(): seq[EditorId] =
  discard
proc setModeScript22_2197829686*(mode: string) =
  discard
proc modeScript22_2197829769*(): string =
  discard
proc getContextWithModeScript22_2197829819*(context: string): string =
  discard
proc scriptRunActionScript_2197830103*(action: string; arg: string) =
  discard
proc scriptLogScript_2197830139*(message: string) =
  discard
proc addCommandScriptScript_2197830170*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197830243*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197830301*(): EditorId =
  discard
proc getActiveEditorScript_2197830338*(): EditorId =
  discard
proc getActiveEditor2Script_2197830369*(): EditorId =
  discard
proc loadCurrentConfigScript_2197830419*() =
  discard
proc sourceCurrentDocumentScript_2197830463*() =
  discard
proc getEditorScript_2197830507*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197830545*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197830612*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197830679*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197830778*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197830842*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197830910*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197830978*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197831054*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197831122*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197831200*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197831282*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197831329*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197831434*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197831481*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197831528*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197831603*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197831678*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197831753*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197831828*(path: string; id: int) =
  discard
