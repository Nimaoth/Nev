import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7683976441*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7683976640*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7683976696*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7683976759*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7683976861*(self: TextDocumentEditor) =
  discard
proc insertScript_7683976911*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7683977276*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7683977353*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7683977566*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7683977756*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7683977830*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7683977880*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7683977937*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7683977987*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7683978058*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7683978113*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7683978179*(self: TextDocumentEditor) =
  discard
proc redoScript_7683978277*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7683978353*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7683978472*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7683978564*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7683978626*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7683978688*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7683979009*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7683979227*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7683979285*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7683979343*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7683979705*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7683979794*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7683979865*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7683979929*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7683979993*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7683980071*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7683980149*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7683980213*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7683980277*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7683980334*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7683980388*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7683980446*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7683980504*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7683980560*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7683980617*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7683980674*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7683980731*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7683980795*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7683980858*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7683980931*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7683981021*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7683981215*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7683981469*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7683981570*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7683981696*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7683981797*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7683981912*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7683982027*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7683982106*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7683982911*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7683982965*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7683983019*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7683983069*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7683983133*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7683983197*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_8120184093*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8120184196*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8120184258*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8120184308*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8120184365*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8120184421*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8120184497*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8120184573*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8120184786*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8120184839*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8120184892*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8120184991*(self: AstDocumentEditor) =
  discard
proc redoScript2_8120185067*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8120185143*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8120185317*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8120185459*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8120185600*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8120185740*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8120185834*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8120185932*(self: AstDocumentEditor) =
  discard
proc wrapScript_8120185992*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8120186110*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8120186166*(self: AstDocumentEditor) =
  discard
proc renameScript_8120186230*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8120186280*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8120186341*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8120186402*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8120186565*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8120186615*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8120186665*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8120186718*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8120186872*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8120187027*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8120187077*(self: AstDocumentEditor) =
  discard
proc gotoScript_8120187127*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8120187963*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8120188232*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8120188293*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8120188350*(self: AstDocumentEditor) =
  discard
proc scrollScript_8120188807*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8120188868*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8120188936*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8120188990*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8120189079*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8120189135*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8388608558*(self: SelectorPopup) =
  discard
proc cancelScript_8388608657*(self: SelectorPopup) =
  discard
proc prevScript_8388608713*(self: SelectorPopup) =
  discard
proc nextScript_8388608781*(self: SelectorPopup) =
  discard
proc getBackendScript_2197824182*(): Backend =
  discard
proc saveAppStateScript_2197824348*() =
  discard
proc requestRenderScript_2197824554*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824605*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824663*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824721*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824779*(context: string; value: bool) =
  discard
proc openGithubWorkspaceScript_2197824837*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197824915*(url: string) =
  discard
proc openLocalWorkspaceScript_2197824970*(path: string) =
  discard
proc getFlagScript2_2197825026*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825099*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825212*(flag: string) =
  discard
proc setOptionScript_2197825263*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825355*() =
  discard
proc changeFontSizeScript_2197825399*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825450*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825775*() =
  discard
proc createViewScript_2197825819*() =
  discard
proc closeCurrentViewScript_2197825868*() =
  discard
proc moveCurrentViewToTopScript_2197825957*() =
  discard
proc nextViewScript_2197826052*() =
  discard
proc prevViewScript_2197826102*() =
  discard
proc moveCurrentViewPrevScript_2197826155*() =
  discard
proc moveCurrentViewNextScript_2197826222*() =
  discard
proc setLayoutScript_2197826286*(layout: string) =
  discard
proc commandLineScript_2197826373*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826428*() =
  discard
proc executeCommandLineScript_2197826476*(): bool =
  discard
proc openFileScript_2197826532*(path: string; app: bool = false) =
  discard
proc writeFileScript_2197826791*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826861*(path: string = "") =
  discard
proc removeFromLocalStorageScript_2197826924*() =
  discard
proc loadThemeScript_2197826968*(name: string) =
  discard
proc chooseThemeScript_2197827055*() =
  discard
proc chooseFileScript_2197827779*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828121*(token: string) =
  discard
proc reloadConfigScript_2197828172*() =
  discard
proc logOptionsScript_2197828257*() =
  discard
proc clearCommandsScript_2197828301*(context: string) =
  discard
proc getAllEditorsScript_2197828352*(): seq[EditorId] =
  discard
proc setModeScript22_2197828661*(mode: string) =
  discard
proc modeScript22_2197828744*(): string =
  discard
proc getContextWithModeScript22_2197828794*(context: string): string =
  discard
proc scriptRunActionScript_2197829078*(action: string; arg: string) =
  discard
proc scriptLogScript_2197829114*(message: string) =
  discard
proc addCommandScriptScript_2197829145*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829218*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829276*(): EditorId =
  discard
proc getActiveEditorScript_2197829313*(): EditorId =
  discard
proc getActiveEditor2Script_2197829344*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829394*() =
  discard
proc sourceCurrentDocumentScript_2197829438*() =
  discard
proc getEditorScript_2197829482*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829520*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829587*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829654*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829753*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197829817*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197829885*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197829953*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197830029*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197830097*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197830175*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830257*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830304*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830416*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830463*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830510*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830585*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830660*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830735*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197830810*(path: string; id: int) =
  discard
