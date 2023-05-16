import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_8287957236*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_8287957428*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_8287957477*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_8287957533*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_8287957628*(self: TextDocumentEditor) =
  discard
proc insertScript_8287957671*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_8287958029*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_8287958099*(self: TextDocumentEditor) =
  discard
proc selectNextScript_8287958327*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_8287958532*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_8287958599*(self: TextDocumentEditor) =
  discard
proc selectLineScript_8287958642*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_8287958692*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_8287958735*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_8287958799*(self: TextDocumentEditor) =
  discard
proc insertTextScript_8287958847*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_8287958906*(self: TextDocumentEditor) =
  discard
proc redoScript_8287958997*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_8287959066*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_8287959178*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_8287959263*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_8287959318*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_8287959373*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_8287959706*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_8287959932*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_8287959983*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_8287960034*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_8287960419*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_8287960468*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_8287960550*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_8287960614*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_8287960671*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_8287960728*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_8287960799*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_8287960870*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_8287960927*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_8287960984*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_8287961034*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_8287961081*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_8287961132*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_8287961183*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_8287961232*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_8287961282*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_8287961332*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_8287961382*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_8287961439*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_8287961495*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_8287961560*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_8287961643*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_8287961830*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_8287962077*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_8287962171*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_8287962290*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_8287962384*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_8287962492*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_8287962600*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_8287962672*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_8287963893*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_8287963940*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_8287963987*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_8287964030*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_8287964090*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_8287964150*(self: TextDocumentEditor) =
  discard
proc acceptScript_8925479553*(self: SelectorPopup) =
  discard
proc cancelScript_8925479648*(self: SelectorPopup) =
  discard
proc prevScript_8925479697*(self: SelectorPopup) =
  discard
proc nextScript_8925479758*(self: SelectorPopup) =
  discard
proc moveCursorScript_8690610363*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8690610459*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8690610514*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8690610557*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8690610607*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8690610656*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8690610725*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8690610794*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8690611000*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8690611046*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8690611092*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8690611184*(self: AstDocumentEditor) =
  discard
proc redoScript2_8690611253*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8690611322*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8690611489*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8690611624*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8690611758*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8690611891*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8690611978*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8690612069*(self: AstDocumentEditor) =
  discard
proc wrapScript_8690612122*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8690612233*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8690612282*(self: AstDocumentEditor) =
  discard
proc renameScript_8690612339*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8690612382*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8690612442*(self: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8690612502*(self: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8690612658*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8690612701*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8690612744*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8690612790*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8690612937*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8690613085*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8690613128*(self: AstDocumentEditor) =
  discard
proc openGotoSymbolPopupScript_8690613188*(self: AstDocumentEditor) =
  discard
proc gotoScript_8690613470*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8690613942*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8690614204*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8690614258*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8690614308*(self: AstDocumentEditor) =
  discard
proc scrollScript_8690614758*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8690614812*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8690614873*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8690614920*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8690615002*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8690615051*(self: AstDocumentEditor;
    context: string): string =
  discard
proc scrollScript2_8992597668*(self: ModelDocumentEditor; amount: float32) =
  discard
proc setModeScript22_8992597770*(self: ModelDocumentEditor; mode: string) =
  discard
proc modeScript22_8992600867*(self: ModelDocumentEditor): string =
  discard
proc getContextWithModeScript22_8992600916*(self: ModelDocumentEditor;
    context: string): string =
  discard
proc moveCursorLeftScript_8992600972*(self: ModelDocumentEditor;
                                     select: bool = false) =
  discard
proc moveCursorRightScript_8992601052*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftLineScript_8992601132*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightLineScript_8992601214*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineStartScript_8992601296*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndScript_8992601379*(self: ModelDocumentEditor;
                                        select: bool = false) =
  discard
proc moveCursorLineStartInlineScript_8992601465*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorLineEndInlineScript_8992601548*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorUpScript2_8992601631*(self: ModelDocumentEditor;
                                    select: bool = false) =
  discard
proc moveCursorDownScript2_8992601736*(self: ModelDocumentEditor;
                                      select: bool = false) =
  discard
proc moveCursorLeftCellScript_8992601841*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc moveCursorRightCellScript_8992601943*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNodeScript_8992602045*(self: ModelDocumentEditor; select: bool = false) =
  discard
proc selectParentCellScript_8992602177*(self: ModelDocumentEditor) =
  discard
proc selectPrevPlaceholderScript_8992602233*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc selectNextPlaceholderScript_8992602312*(self: ModelDocumentEditor;
    select: bool = false) =
  discard
proc deleteLeftScript2_8992603241*(self: ModelDocumentEditor) =
  discard
proc deleteRightScript2_8992603284*(self: ModelDocumentEditor) =
  discard
proc createNewNodeScript_8992603878*(self: ModelDocumentEditor) =
  discard
proc insertTextAtCursorScript_8992603962*(self: ModelDocumentEditor;
    input: string): bool =
  discard
proc undoScript22_8992604134*(self: ModelDocumentEditor) =
  discard
proc redoScript22_8992604435*(self: ModelDocumentEditor) =
  discard
proc toggleUseDefaultCellBuilderScript_8992604635*(self: ModelDocumentEditor) =
  discard
proc showCompletionsScript_8992604678*(self: ModelDocumentEditor) =
  discard
proc hideCompletionsScript2_8992604721*(self: ModelDocumentEditor) =
  discard
proc selectPrevCompletionScript22_8992604768*(self: ModelDocumentEditor) =
  discard
proc selectNextCompletionScript22_8992604819*(self: ModelDocumentEditor) =
  discard
proc applySelectedCompletionScript22_8992604870*(self: ModelDocumentEditor) =
  discard
proc getBackendScript_2197823697*(): Backend =
  discard
proc saveAppStateScript_2197823856*() =
  discard
proc requestRenderScript_2197824685*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824729*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824780*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824831*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824882*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197825010*() =
  discard
proc openGithubWorkspaceScript_2197825051*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825109*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825153*(path: string) =
  discard
proc getFlagScript2_2197825198*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825264*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825370*(flag: string) =
  discard
proc setOptionScript_2197825414*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825499*() =
  discard
proc changeFontSizeScript_2197825536*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825580*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825898*() =
  discard
proc createViewScript_2197825935*() =
  discard
proc closeCurrentViewScript_2197825977*() =
  discard
proc moveCurrentViewToTopScript_2197826059*() =
  discard
proc nextViewScript_2197826147*() =
  discard
proc prevViewScript_2197826190*() =
  discard
proc moveCurrentViewPrevScript_2197826236*() =
  discard
proc moveCurrentViewNextScript_2197826296*() =
  discard
proc setLayoutScript_2197826353*(layout: string) =
  discard
proc commandLineScript_2197826433*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826481*() =
  discard
proc executeCommandLineScript_2197826522*(): bool =
  discard
proc writeFileScript_2197826692*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826755*(path: string = "") =
  discard
proc openFileScript_2197826830*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827000*() =
  discard
proc loadThemeScript_2197827037*(name: string) =
  discard
proc chooseThemeScript_2197827117*() =
  discard
proc chooseFileScript_2197827750*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828044*(token: string) =
  discard
proc reloadConfigScript_2197828088*() =
  discard
proc logOptionsScript_2197828166*() =
  discard
proc clearCommandsScript_2197828203*(context: string) =
  discard
proc getAllEditorsScript_2197828247*(): seq[EditorId] =
  discard
proc setModeScript222_2197828549*(mode: string) =
  discard
proc modeScript222_2197828625*(): string =
  discard
proc getContextWithModeScript222_2197828668*(context: string): string =
  discard
proc scriptRunActionScript_2197828945*(action: string; arg: string) =
  discard
proc scriptLogScript_2197828974*(message: string) =
  discard
proc addCommandScriptScript_2197828998*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829064*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829115*(): EditorId =
  discard
proc getActiveEditorScript_2197829145*(): EditorId =
  discard
proc getActiveEditor2Script_2197829169*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829212*() =
  discard
proc sourceCurrentDocumentScript_2197829249*() =
  discard
proc getEditorScript_2197829286*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829317*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829377*(editorId: EditorId): bool =
  discard
proc scriptIsModelEditorScript_2197829437*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829497*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829589*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197829646*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197829707*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197829768*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197829837*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197829898*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197829969*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830044*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830084*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830182*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830222*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830262*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830330*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830398*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830466*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830534*(path: string; id: int) =
  discard
