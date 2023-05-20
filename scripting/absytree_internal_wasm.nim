import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_8287957247(self: TextDocumentEditor; mode: string)  {.importc.}
proc modeScript_8287957486(self: TextDocumentEditor): string  {.importc.}
proc getContextWithModeScript_8287957548(self: TextDocumentEditor;
    context: string): string  {.importc.}
proc updateTargetColumnScript_8287957618(self: TextDocumentEditor;
    cursor: SelectionCursor)  {.importc.}
proc invertSelectionScript_8287957727(self: TextDocumentEditor)  {.importc.}
proc insertScript_8287957783(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection]  {.importc.}
proc deleteScript_8287958207(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection]  {.importc.}
proc selectPrevScript_8287958307(self: TextDocumentEditor)  {.importc.}
proc selectNextScript_8287958548(self: TextDocumentEditor)  {.importc.}
proc selectInsideScript_8287958766(self: TextDocumentEditor; cursor: Cursor)  {.importc.}
proc selectInsideCurrentScript_8287958849(self: TextDocumentEditor)  {.importc.}
proc selectLineScript_8287958905(self: TextDocumentEditor; line: int)  {.importc.}
proc selectLineCurrentScript_8287958969(self: TextDocumentEditor)  {.importc.}
proc selectParentTsScript_8287959025(self: TextDocumentEditor;
                                     selection: Selection)  {.importc.}
proc selectParentCurrentTsScript_8287959104(self: TextDocumentEditor)  {.importc.}
proc insertTextScript_8287959165(self: TextDocumentEditor; text: string)  {.importc.}
proc undoScript_8287959238(self: TextDocumentEditor)  {.importc.}
proc redoScript_8287959346(self: TextDocumentEditor)  {.importc.}
proc scrollTextScript_8287959432(self: TextDocumentEditor; amount: float32)  {.importc.}
proc duplicateLastSelectionScript_8287959558(self: TextDocumentEditor)  {.importc.}
proc addCursorBelowScript_8287959656(self: TextDocumentEditor)  {.importc.}
proc addCursorAboveScript_8287959728(self: TextDocumentEditor)  {.importc.}
proc getPrevFindResultScript_8287959796(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection  {.importc.}
proc getNextFindResultScript_8287960151(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection  {.importc.}
proc addNextFindResultToSelectionScript_8287960401(self: TextDocumentEditor)  {.importc.}
proc addPrevFindResultToSelectionScript_8287960465(self: TextDocumentEditor)  {.importc.}
proc setAllFindResultToSelectionScript_8287960529(self: TextDocumentEditor)  {.importc.}
proc clearSelectionsScript_8287960942(self: TextDocumentEditor)  {.importc.}
proc moveCursorColumnScript_8287961004(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc moveCursorLineScript_8287961147(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc moveCursorHomeScript_8287961227(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true)  {.importc.}
proc moveCursorEndScript_8287961301(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true)  {.importc.}
proc moveCursorToScript_8287961375(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true)  {.importc.}
proc moveCursorBeforeScript_8287961487(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc moveCursorNextFindResultScript_8287961599(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc moveCursorPrevFindResultScript_8287961671(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true)  {.importc.}
proc scrollToCursorScript_8287961743(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config)  {.importc.}
proc reloadTreesitterScript_8287961807(self: TextDocumentEditor)  {.importc.}
proc deleteLeftScript_8287961931(self: TextDocumentEditor)  {.importc.}
proc deleteRightScript_8287962001(self: TextDocumentEditor)  {.importc.}
proc getCommandCountScript_8287962071(self: TextDocumentEditor): int  {.importc.}
proc setCommandCountScript_8287962133(self: TextDocumentEditor; count: int)  {.importc.}
proc setCommandCountRestoreScript_8287962197(self: TextDocumentEditor;
    count: int)  {.importc.}
proc updateCommandCountScript_8287962261(self: TextDocumentEditor; digit: int)  {.importc.}
proc setFlagScript_8287962325(self: TextDocumentEditor; name: string;
                              value: bool)  {.importc.}
proc getFlagScript_8287962397(self: TextDocumentEditor; name: string): bool  {.importc.}
proc runActionScript_8287962467(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool  {.importc.}
proc findWordBoundaryScript_8287962547(self: TextDocumentEditor; cursor: Cursor): Selection  {.importc.}
proc getSelectionForMoveScript_8287962646(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection  {.importc.}
proc setMoveScript_8287962892(self: TextDocumentEditor; args: JsonNode)  {.importc.}
proc deleteMoveScript_8287963153(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true)  {.importc.}
proc selectMoveScript_8287963289(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true)  {.importc.}
proc changeMoveScript_8287963473(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true)  {.importc.}
proc moveLastScript_8287963609(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0)  {.importc.}
proc moveFirstScript_8287963761(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0)  {.importc.}
proc setSearchQueryScript_8287963913(self: TextDocumentEditor; query: string)  {.importc.}
proc setSearchQueryFromMoveScript_8287963999(self: TextDocumentEditor;
    move: string; count: int = 0)  {.importc.}
proc gotoDefinitionScript_8287965235(self: TextDocumentEditor)  {.importc.}
proc getCompletionsScript_8287965524(self: TextDocumentEditor)  {.importc.}
proc hideCompletionsScript_8287965666(self: TextDocumentEditor)  {.importc.}
proc selectPrevCompletionScript_8287965722(self: TextDocumentEditor)  {.importc.}
proc selectNextCompletionScript_8287965795(self: TextDocumentEditor)  {.importc.}
proc applySelectedCompletionScript_8287965868(self: TextDocumentEditor)  {.importc.}
proc acceptScript_8925479553(self: SelectorPopup)  {.importc.}
proc cancelScript_8925479665(self: SelectorPopup)  {.importc.}
proc prevScript_8925479727(self: SelectorPopup)  {.importc.}
proc nextScript_8925479801(self: SelectorPopup)  {.importc.}
proc moveCursorScript_8690610363(self: AstDocumentEditor; direction: int)  {.importc.}
proc moveCursorUpScript_8690610473(self: AstDocumentEditor)  {.importc.}
proc moveCursorDownScript_8690610541(self: AstDocumentEditor)  {.importc.}
proc moveCursorNextScript_8690610597(self: AstDocumentEditor)  {.importc.}
proc moveCursorPrevScript_8690610671(self: AstDocumentEditor)  {.importc.}
proc moveCursorNextLineScript_8690610743(self: AstDocumentEditor)  {.importc.}
proc moveCursorPrevLineScript_8690610834(self: AstDocumentEditor)  {.importc.}
proc selectContainingScript_8690610926(self: AstDocumentEditor;
                                       container: string)  {.importc.}
proc deleteSelectedScript_8690611146(self: AstDocumentEditor)  {.importc.}
proc copySelectedScript_8690611234(self: AstDocumentEditor)  {.importc.}
proc finishEditScript_8690611293(self: AstDocumentEditor; apply: bool)  {.importc.}
proc undoScript2_8690611408(self: AstDocumentEditor)  {.importc.}
proc redoScript2_8690611490(self: AstDocumentEditor)  {.importc.}
proc insertAfterSmartScript_8690611572(self: AstDocumentEditor;
                                       nodeTemplate: string)  {.importc.}
proc insertAfterScript_8690611991(self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc insertBeforeScript_8690612175(self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc insertChildScript_8690612358(self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc replaceScript_8690612540(self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc replaceEmptyScript_8690612676(self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc replaceParentScript_8690612816(self: AstDocumentEditor)  {.importc.}
proc wrapScript_8690612882(self: AstDocumentEditor; nodeTemplate: string)  {.importc.}
proc editPrevEmptyScript_8690613054(self: AstDocumentEditor)  {.importc.}
proc editNextEmptyScript_8690613123(self: AstDocumentEditor)  {.importc.}
proc renameScript_8690613230(self: AstDocumentEditor)  {.importc.}
proc selectPrevCompletionScript2_8690613286(self: AstDocumentEditor)  {.importc.}
proc selectNextCompletionScript2_8690613359(self: AstDocumentEditor)  {.importc.}
proc applySelectedCompletionScript2_8690613432(self: AstDocumentEditor)  {.importc.}
proc cancelAndNextCompletionScript_8690613672(self: AstDocumentEditor)  {.importc.}
proc cancelAndPrevCompletionScript_8690613728(self: AstDocumentEditor)  {.importc.}
proc cancelAndDeleteScript_8690613784(self: AstDocumentEditor)  {.importc.}
proc moveNodeToPrevSpaceScript_8690613843(self: AstDocumentEditor)  {.importc.}
proc moveNodeToNextSpaceScript_8690614011(self: AstDocumentEditor)  {.importc.}
proc selectPrevScript2_8690614183(self: AstDocumentEditor)  {.importc.}
proc selectNextScript2_8690614240(self: AstDocumentEditor)  {.importc.}
proc openGotoSymbolPopupScript_8690614314(self: AstDocumentEditor)  {.importc.}
proc gotoScript_8690614645(self: AstDocumentEditor; where: string)  {.importc.}
proc runSelectedFunctionScript_8690615243(self: AstDocumentEditor)  {.importc.}
proc toggleOptionScript_8690615519(self: AstDocumentEditor; name: string)  {.importc.}
proc runLastCommandScript_8690615587(self: AstDocumentEditor; which: string)  {.importc.}
proc selectCenterNodeScript_8690615651(self: AstDocumentEditor)  {.importc.}
proc scrollScript_8690616134(self: AstDocumentEditor; amount: float32)  {.importc.}
proc scrollOutputScript_8690616202(self: AstDocumentEditor; arg: string)  {.importc.}
proc dumpContextScript_8690616277(self: AstDocumentEditor)  {.importc.}
proc setModeScript2_8690616337(self: AstDocumentEditor; mode: string)  {.importc.}
proc modeScript2_8690616459(self: AstDocumentEditor): string  {.importc.}
proc getContextWithModeScript2_8690616521(self: AstDocumentEditor;
    context: string): string  {.importc.}
proc scrollScript2_8992600587(self: ModelDocumentEditor; amount: float32)  {.importc.}
proc setModeScript22_8992600703(self: ModelDocumentEditor; mode: string)  {.importc.}
proc modeScript22_8992603840(self: ModelDocumentEditor): string  {.importc.}
proc getContextWithModeScript22_8992603902(self: ModelDocumentEditor;
    context: string): string  {.importc.}
proc moveCursorLeftScript_8992603972(self: ModelDocumentEditor;
                                     select: bool = false)  {.importc.}
proc moveCursorRightScript_8992604077(self: ModelDocumentEditor;
                                      select: bool = false)  {.importc.}
proc moveCursorLeftLineScript_8992604171(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc moveCursorRightLineScript_8992604276(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc moveCursorLineStartScript_8992604382(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc moveCursorLineEndScript_8992604479(self: ModelDocumentEditor;
                                        select: bool = false)  {.importc.}
proc moveCursorLineStartInlineScript_8992604579(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc moveCursorLineEndInlineScript_8992604677(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc moveCursorUpScript2_8992604775(self: ModelDocumentEditor;
                                    select: bool = false)  {.importc.}
proc moveCursorDownScript2_8992604899(self: ModelDocumentEditor;
                                      select: bool = false)  {.importc.}
proc moveCursorLeftCellScript_8992605018(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc moveCursorRightCellScript_8992605134(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc selectNodeScript_8992605250(self: ModelDocumentEditor; select: bool = false)  {.importc.}
proc selectParentCellScript_8992605396(self: ModelDocumentEditor)  {.importc.}
proc selectPrevPlaceholderScript_8992605465(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc selectNextPlaceholderScript_8992605558(self: ModelDocumentEditor;
    select: bool = false)  {.importc.}
proc deleteLeftScript2_8992606501(self: ModelDocumentEditor)  {.importc.}
proc deleteRightScript2_8992606637(self: ModelDocumentEditor)  {.importc.}
proc createNewNodeScript_8992607244(self: ModelDocumentEditor)  {.importc.}
proc insertTextAtCursorScript_8992607379(self: ModelDocumentEditor;
    input: string): bool  {.importc.}
proc undoScript22_8992607565(self: ModelDocumentEditor)  {.importc.}
proc redoScript22_8992607906(self: ModelDocumentEditor)  {.importc.}
proc toggleUseDefaultCellBuilderScript_8992608123(self: ModelDocumentEditor)  {.importc.}
proc showCompletionsScript_8992608179(self: ModelDocumentEditor)  {.importc.}
proc hideCompletionsScript2_8992608235(self: ModelDocumentEditor)  {.importc.}
proc selectPrevCompletionScript22_8992608295(self: ModelDocumentEditor)  {.importc.}
proc selectNextCompletionScript22_8992608359(self: ModelDocumentEditor)  {.importc.}
proc applySelectedCompletionScript22_8992608423(self: ModelDocumentEditor)  {.importc.}
proc getBackendScript_2197823683(): Backend  {.importc.}
proc saveAppStateScript_2197823854()  {.importc.}
proc requestRenderScript_2197824706(redrawEverything: bool = false)  {.importc.}
proc setHandleInputsScript_2197824763(context: string; value: bool)  {.importc.}
proc setHandleActionsScript_2197824828(context: string; value: bool)  {.importc.}
proc setConsumeAllActionsScript_2197824893(context: string; value: bool)  {.importc.}
proc setConsumeAllInputScript_2197824958(context: string; value: bool)  {.importc.}
proc clearWorkspaceCachesScript_2197825100()  {.importc.}
proc openGithubWorkspaceScript_2197825157(user: string; repository: string;
    branchOrHash: string)  {.importc.}
proc openAbsytreeServerWorkspaceScript_2197825234(url: string)  {.importc.}
proc openLocalWorkspaceScript_2197825291(path: string)  {.importc.}
proc getFlagScript2_2197825349(flag: string; default: bool = false): bool  {.importc.}
proc setFlagScript2_2197825429(flag: string; value: bool)  {.importc.}
proc toggleFlagScript_2197825555(flag: string)  {.importc.}
proc setOptionScript_2197825612(option: string; value: JsonNode)  {.importc.}
proc quitScript_2197825716()  {.importc.}
proc changeFontSizeScript_2197825765(amount: float32)  {.importc.}
proc changeLayoutPropScript_2197825822(prop: string; change: float32)  {.importc.}
proc toggleStatusBarLocationScript_2197826154()  {.importc.}
proc createViewScript_2197826203()  {.importc.}
proc closeCurrentViewScript_2197826285()  {.importc.}
proc moveCurrentViewToTopScript_2197826379()  {.importc.}
proc nextViewScript_2197826479()  {.importc.}
proc prevViewScript_2197826534()  {.importc.}
proc moveCurrentViewPrevScript_2197826592()  {.importc.}
proc moveCurrentViewNextScript_2197826664()  {.importc.}
proc setLayoutScript_2197826733(layout: string)  {.importc.}
proc commandLineScript_2197826826(initialValue: string = "")  {.importc.}
proc exitCommandLineScript_2197826887()  {.importc.}
proc executeCommandLineScript_2197826940(): bool  {.importc.}
proc writeFileScript_2197827122(path: string = ""; app: bool = false)  {.importc.}
proc loadFileScript_2197827199(path: string = "")  {.importc.}
proc openFileScript_2197827287(path: string; app: bool = false)  {.importc.}
proc removeFromLocalStorageScript_2197827471()  {.importc.}
proc loadThemeScript_2197827520(name: string)  {.importc.}
proc chooseThemeScript_2197827613()  {.importc.}
proc chooseFileScript_2197828311(view: string = "new")  {.importc.}
proc setGithubAccessTokenScript_2197828874(token: string)  {.importc.}
proc reloadConfigScript_2197828931()  {.importc.}
proc logOptionsScript_2197829022()  {.importc.}
proc clearCommandsScript_2197829071(context: string)  {.importc.}
proc getAllEditorsScript_2197829128(): seq[EditorId]  {.importc.}
proc setModeScript222_2197829453(mode: string)  {.importc.}
proc modeScript222_2197829568(): string  {.importc.}
proc getContextWithModeScript222_2197829623(context: string): string  {.importc.}
proc scriptRunActionScript_2197829913(action: string; arg: string)  {.importc.}
proc scriptLogScript_2197829955(message: string)  {.importc.}
proc addCommandScriptScript_2197829991(context: string; keys: string;
                                       action: string; arg: string = "")  {.importc.}
proc removeCommandScript_2197830073(context: string; keys: string)  {.importc.}
proc getActivePopupScript_2197830138(): EditorId  {.importc.}
proc getActiveEditorScript_2197830179(): EditorId  {.importc.}
proc getActiveEditor2Script_2197830214(): EditorId  {.importc.}
proc loadCurrentConfigScript_2197830269()  {.importc.}
proc sourceCurrentDocumentScript_2197830318()  {.importc.}
proc getEditorScript_2197830367(index: int): EditorId  {.importc.}
proc scriptIsTextEditorScript_2197830410(editorId: EditorId): bool  {.importc.}
proc scriptIsAstEditorScript_2197830482(editorId: EditorId): bool  {.importc.}
proc scriptIsModelEditorScript_2197830554(editorId: EditorId): bool  {.importc.}
proc scriptRunActionForScript_2197830626(editorId: EditorId; action: string;
    arg: string)  {.importc.}
proc scriptInsertTextIntoScript_2197830732(editorId: EditorId; text: string)  {.importc.}
proc scriptTextEditorSelectionScript_2197830802(editorId: EditorId): Selection  {.importc.}
proc scriptSetTextEditorSelectionScript_2197830879(editorId: EditorId;
    selection: Selection)  {.importc.}
proc scriptTextEditorSelectionsScript_2197830953(editorId: EditorId): seq[
    Selection]  {.importc.}
proc scriptSetTextEditorSelectionsScript_2197831034(editorId: EditorId;
    selections: seq[Selection])  {.importc.}
proc scriptGetTextEditorLineScript_2197831108(editorId: EditorId; line: int): string  {.importc.}
proc scriptGetTextEditorLineCountScript_2197831192(editorId: EditorId): int  {.importc.}
proc scriptGetOptionIntScript_2197831279(path: string; default: int): int  {.importc.}
proc scriptGetOptionFloatScript_2197831333(path: string; default: float): float  {.importc.}
proc scriptGetOptionBoolScript_2197831445(path: string; default: bool): bool  {.importc.}
proc scriptGetOptionStringScript_2197831499(path: string; default: string): string  {.importc.}
proc scriptSetOptionIntScript_2197831553(path: string; value: int)  {.importc.}
proc scriptSetOptionFloatScript_2197831640(path: string; value: float)  {.importc.}
proc scriptSetOptionBoolScript_2197831727(path: string; value: bool)  {.importc.}
proc scriptSetOptionStringScript_2197831814(path: string; value: string)  {.importc.}
proc scriptSetCallbackScript_2197831901(path: string; id: int)  {.importc.}
