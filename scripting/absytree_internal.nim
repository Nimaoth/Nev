import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7683977460*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7683977659*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7683977715*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7683977778*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7683977880*(self: TextDocumentEditor) =
  discard
proc insertScript_7683977930*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7683978295*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7683978372*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7683978607*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7683978819*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7683978893*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7683978943*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7683979000*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7683979050*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7683979121*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7683979176*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7683979242*(self: TextDocumentEditor) =
  discard
proc redoScript_7683979340*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7683979416*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7683979535*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7683979627*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7683979689*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7683979751*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7683980091*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7683980324*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7683980382*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7683980440*(self: TextDocumentEditor) =
  discard
proc clearSelectionsScript_7683980832*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7683980888*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7683980977*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7683981048*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7683981112*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7683981176*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7683981254*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7683981332*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7683981396*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7683981460*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7683981517*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7683981571*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7683981629*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7683981687*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7683981743*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7683981800*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7683981857*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7683981914*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7683981978*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7683982041*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7683982113*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7683982203*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7683982397*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7683982651*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7683982752*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7683982878*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7683982979*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7683983094*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7683983209*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7683983288*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7683984516*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7683984570*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7683984624*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7683984674*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7683984741*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7683984808*(self: TextDocumentEditor) =
  discard
proc acceptScript_8355054209*(self: SelectorPopup) =
  discard
proc cancelScript_8355054311*(self: SelectorPopup) =
  discard
proc prevScript_8355054367*(self: SelectorPopup) =
  discard
proc nextScript_8355054435*(self: SelectorPopup) =
  discard
proc moveCursorScript_8120185019*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_8120185122*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_8120185184*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_8120185234*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_8120185291*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_8120185347*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_8120185423*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_8120185499*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_8120185712*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_8120185765*(self: AstDocumentEditor) =
  discard
proc finishEditScript_8120185818*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_8120185917*(self: AstDocumentEditor) =
  discard
proc redoScript2_8120185993*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_8120186069*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_8120186243*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_8120186385*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_8120186526*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_8120186666*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_8120186760*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_8120186858*(self: AstDocumentEditor) =
  discard
proc wrapScript_8120186918*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_8120187036*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_8120187092*(self: AstDocumentEditor) =
  discard
proc renameScript_8120187156*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_8120187206*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_8120187273*(self: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_8120187340*(self: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_8120187503*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_8120187553*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_8120187603*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_8120187656*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_8120187810*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_8120187965*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_8120188015*(self: AstDocumentEditor) =
  discard
proc openGotoSymbolPopupScript_8120188082*(self: AstDocumentEditor) =
  discard
proc gotoScript_8120188371*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_8120188850*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_8120189119*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_8120189180*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_8120189237*(self: AstDocumentEditor) =
  discard
proc scrollScript_8120189694*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_8120189755*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_8120189823*(self: AstDocumentEditor) =
  discard
proc setModeScript2_8120189877*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_8120189966*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_8120190022*(self: AstDocumentEditor;
    context: string): string =
  discard
proc scrollScript2_8422173551*(self: ModelDocumentEditor; amount: float32) =
  discard
proc setModeScript22_8422173660*(self: ModelDocumentEditor; mode: string) =
  discard
proc modeScript22_8422174132*(self: ModelDocumentEditor): string =
  discard
proc getContextWithModeScript22_8422174188*(self: ModelDocumentEditor;
    context: string): string =
  discard
proc moveCursorLeftScript_8422174251*(self: ModelDocumentEditor) =
  discard
proc moveCursorRightScript_8422174331*(self: ModelDocumentEditor) =
  discard
proc moveCursorUpScript2_8422174411*(self: ModelDocumentEditor) =
  discard
proc moveCursorDownScript2_8422174491*(self: ModelDocumentEditor) =
  discard
proc moveCursorLeftCellScript_8422174571*(self: ModelDocumentEditor) =
  discard
proc moveCursorRightCellScript_8422174651*(self: ModelDocumentEditor) =
  discard
proc deleteLeftScript2_8422174731*(self: ModelDocumentEditor) =
  discard
proc deleteRightScript2_8422174820*(self: ModelDocumentEditor) =
  discard
proc insertTextAtCursorScript_8422174909*(self: ModelDocumentEditor;
    input: string): bool =
  discard
proc getBackendScript_2197823672*(): Backend =
  discard
proc saveAppStateScript_2197823838*() =
  discard
proc requestRenderScript_2197824682*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824733*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824791*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824849*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824907*(context: string; value: bool) =
  discard
proc clearWorkspaceCachesScript_2197825042*() =
  discard
proc openGithubWorkspaceScript_2197825090*(user: string; repository: string;
    branchOrHash: string) =
  discard
proc openAbsytreeServerWorkspaceScript_2197825155*(url: string) =
  discard
proc openLocalWorkspaceScript_2197825206*(path: string) =
  discard
proc getFlagScript2_2197825258*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197825331*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197825444*(flag: string) =
  discard
proc setOptionScript_2197825495*(option: string; value: JsonNode) =
  discard
proc quitScript_2197825587*() =
  discard
proc changeFontSizeScript_2197825631*(amount: float32) =
  discard
proc changeLayoutPropScript_2197825682*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197826007*() =
  discard
proc createViewScript_2197826051*() =
  discard
proc closeCurrentViewScript_2197826100*() =
  discard
proc moveCurrentViewToTopScript_2197826189*() =
  discard
proc nextViewScript_2197826284*() =
  discard
proc prevViewScript_2197826334*() =
  discard
proc moveCurrentViewPrevScript_2197826387*() =
  discard
proc moveCurrentViewNextScript_2197826454*() =
  discard
proc setLayoutScript_2197826518*(layout: string) =
  discard
proc commandLineScript_2197826605*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197826660*() =
  discard
proc executeCommandLineScript_2197826708*(): bool =
  discard
proc writeFileScript_2197826885*(path: string = ""; app: bool = false) =
  discard
proc loadFileScript_2197826955*(path: string = "") =
  discard
proc openFileScript_2197827037*(path: string; app: bool = false) =
  discard
proc removeFromLocalStorageScript_2197827214*() =
  discard
proc loadThemeScript_2197827258*(name: string) =
  discard
proc chooseThemeScript_2197827345*() =
  discard
proc chooseFileScript_2197827985*(view: string = "new") =
  discard
proc setGithubAccessTokenScript_2197828286*(token: string) =
  discard
proc reloadConfigScript_2197828337*() =
  discard
proc logOptionsScript_2197828422*() =
  discard
proc clearCommandsScript_2197828466*(context: string) =
  discard
proc getAllEditorsScript_2197828517*(): seq[EditorId] =
  discard
proc setModeScript222_2197828826*(mode: string) =
  discard
proc modeScript222_2197828909*(): string =
  discard
proc getContextWithModeScript222_2197828959*(context: string): string =
  discard
proc scriptRunActionScript_2197829243*(action: string; arg: string) =
  discard
proc scriptLogScript_2197829279*(message: string) =
  discard
proc addCommandScriptScript_2197829310*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197829383*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197829441*(): EditorId =
  discard
proc getActiveEditorScript_2197829478*(): EditorId =
  discard
proc getActiveEditor2Script_2197829509*(): EditorId =
  discard
proc loadCurrentConfigScript_2197829559*() =
  discard
proc sourceCurrentDocumentScript_2197829603*() =
  discard
proc getEditorScript_2197829647*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197829685*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197829752*(editorId: EditorId): bool =
  discard
proc scriptIsModelEditorScript_2197829819*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197829886*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197829985*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197830049*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197830117*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197830185*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197830261*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197830329*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197830407*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197830489*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197830536*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197830641*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197830688*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197830735*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197830810*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197830885*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197830960*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197831035*(path: string; id: int) =
  discard
