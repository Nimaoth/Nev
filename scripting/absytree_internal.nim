import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7683977458*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7683977657*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7683977713*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7683977776*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7683977878*(self: TextDocumentEditor) =
  discard
proc insertScript_7683977928*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7683978293*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7683978370*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7683978605*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7683978817*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7683978891*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7683978941*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7683978998*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7683979048*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7683979119*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7683979174*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7683979240*(self: TextDocumentEditor) =
  discard
proc redoScript_7683979338*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7683979414*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7683979533*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7683979625*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7683979687*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7683979749*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7683980089*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7683980322*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7683980380*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7683980438*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_7683980830*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7683980886*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7683980975*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7683981046*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7683981110*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7683981174*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7683981252*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7683981330*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7683981394*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7683981458*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7683981515*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7683981569*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7683981627*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7683981685*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7683981741*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7683981798*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7683981855*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7683981912*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7683981976*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7683982039*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7683982111*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7683982201*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7683982395*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7683982649*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7683982750*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7683982876*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7683982977*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7683983092*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7683983207*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7683983286*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7683984502*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7683984556*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7683984610*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7683984660*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7683984727*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7683984794*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_8120184996*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8120185099*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8120185161*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8120185211*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8120185268*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8120185324*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8120185400*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8120185476*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8120185689*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8120185742*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8120185795*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8120185894*(self: AstDocumentEditor) =
  discard
proc redoScript2_8120185970*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8120186046*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8120186220*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8120186362*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8120186503*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8120186643*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8120186737*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8120186835*(self: AstDocumentEditor) =
  discard
proc wrapScript_8120186895*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8120187013*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8120187069*(self: AstDocumentEditor) =
  discard
proc renameScript_8120187133*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8120187183*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8120187244*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8120187305*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8120187468*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8120187518*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8120187568*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8120187621*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8120187775*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8120187930*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8120187980*(self: AstDocumentEditor) =
  discard
proc gotoScript_8120188030*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8120188551*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8120188820*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8120188881*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8120188938*(self: AstDocumentEditor) =
  discard
proc scrollScript_8120189395*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8120189456*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8120189524*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8120189578*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8120189667*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8120189723*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8371831344*(self: SelectorPopup) =
  discard
proc cancelScript_8371831443*(self: SelectorPopup) =
  discard
proc prevScript_8371831499*(self: SelectorPopup) =
  discard
proc nextScript_8371831567*(self: SelectorPopup) =
  discard
proc getBackendScript_2197823661*(): Backend =
  discard
proc saveAppStateScript_2197823827*() =
  discard
proc requestRenderScript_2197824618*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824669*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824727*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824785*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824843*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197824978*() =
  discard
proc openGithubWorkspaceScript_2197825026*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825091*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825142*(path: string) =
  discard
proc getFlagScript2_2197825194*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825267*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825380*(flag: string) =
  discard
proc setOptionScript_2197825431*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825523*() =
  discard
proc changeFontSizeScript_2197825567*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825618*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825943*() =
  discard
proc createViewScript_2197825987*() =
  discard
proc closeCurrentViewScript_2197826036*() =
  discard
proc moveCurrentViewToTopScript_2197826125*() =
  discard
proc nextViewScript_2197826220*() =
  discard
proc prevViewScript_2197826270*() =
  discard
proc moveCurrentViewPrevScript_2197826323*() =
  discard
proc moveCurrentViewNextScript_2197826390*() =
  discard
proc setLayoutScript_2197826454*(layout: string) =
  discard
proc commandLineScript_2197826541*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826596*() =
  discard
proc executeCommandLineScript_2197826644*(): bool =
  discard
proc writeFileScript_2197826821*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826891*(path: string = "") =
  discard
proc openFileScript_2197826973*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827141*() =
  discard
proc loadThemeScript_2197827185*(name: string) =
  discard
proc chooseThemeScript_2197827272*() =
  discard
proc chooseFileScript_2197828033*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828334*(token: string) =
  discard
proc reloadConfigScript_2197828385*() =
  discard
proc logOptionsScript_2197828470*() =
  discard
proc clearCommandsScript_2197828514*(context: string) =
  discard
proc getAllEditorsScript_2197828565*(): seq[EditorId] =
  discard
proc setModeScript22_2197828874*(mode: string) =
  discard
proc modeScript22_2197828957*(): string =
  discard
proc getContextWithModeScript22_2197829007*(context: string): string =
  discard
proc scriptRunActionScript_2197829291*(action: string; arg: string) =
  discard
proc scriptLogScript_2197829327*(message: string) =
  discard
proc addCommandScriptScript_2197829358*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829431*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829489*(): EditorId =
  discard
proc getActiveEditorScript_2197829526*(): EditorId =
  discard
proc getActiveEditor2Script_2197829557*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829607*() =
  discard
proc sourceCurrentDocumentScript_2197829651*() =
  discard
proc getEditorScript_2197829695*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829733*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829800*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829867*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829966*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197830030*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197830098*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197830166*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197830242*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197830310*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197830388*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830470*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830517*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830622*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830669*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830716*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830791*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830866*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830941*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197831016*(path: string; id: int) =
  discard
