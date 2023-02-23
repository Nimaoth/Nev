import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7113548649*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7113548848*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7113548904*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7113548967*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7113549069*(self: TextDocumentEditor) =
  discard
proc insertScript_7113549119*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7113549484*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7113549561*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7113549774*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7113549964*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7113550038*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7113550088*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7113550145*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7113550195*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7113550266*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7113550321*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7113550387*(self: TextDocumentEditor) =
  discard
proc redoScript_7113550485*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7113550561*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7113550680*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7113550772*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7113550834*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7113550896*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7113551217*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7113551435*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7113551493*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7113551551*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7113551913*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7113552002*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7113552073*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7113552137*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7113552201*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7113552279*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7113552357*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7113552421*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7113552485*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7113552542*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7113552596*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7113552654*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7113552712*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7113552768*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7113552825*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7113552882*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7113552939*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7113553003*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7113553066*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7113553139*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7113553229*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7113553423*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7113553677*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7113553778*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7113553904*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7113554005*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7113554120*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7113554235*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7113554314*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7113555119*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7113555173*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7113555227*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7113555277*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7113555341*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7113555405*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_7902080281*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_7902080384*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_7902080446*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_7902080496*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_7902080553*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_7902080609*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_7902080685*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_7902080761*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_7902080974*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_7902081027*(self: AstDocumentEditor) =
  discard
proc finishEditScript_7902081080*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_7902081179*(self: AstDocumentEditor) =
  discard
proc redoScript2_7902081255*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_7902081331*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_7902081505*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_7902081647*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_7902081788*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_7902081928*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_7902082022*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_7902082120*(self: AstDocumentEditor) =
  discard
proc wrapScript_7902082180*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_7902082298*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_7902082354*(self: AstDocumentEditor) =
  discard
proc renameScript_7902082418*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_7902082468*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_7902082529*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_7902082590*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_7902082753*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_7902082803*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_7902082853*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_7902082906*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_7902083060*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_7902083215*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_7902083265*(self: AstDocumentEditor) =
  discard
proc gotoScript_7902083315*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_7902084151*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_7902084420*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_7902084481*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_7902084538*(self: AstDocumentEditor) =
  discard
proc scrollScript_7902084995*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_7902085056*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_7902085124*(self: AstDocumentEditor) =
  discard
proc setModeScript2_7902085178*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_7902085267*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_7902085323*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8170504455*(self: SelectorPopup) =
  discard
proc cancelScript_8170504554*(self: SelectorPopup) =
  discard
proc prevScript_8170504610*(self: SelectorPopup) =
  discard
proc nextScript_8170504678*(self: SelectorPopup) =
  discard
proc getBackendScript_2197823911*(): Backend =
  discard
proc requestRenderScript_2197824077*(redrawEverything: bool = false) =
  discard
proc setHandleInputsScript_2197824128*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824186*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824244*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824302*(context: string; value: bool) =
  discard
proc getFlagScript2_2197824360*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197824433*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197824546*(flag: string) =
  discard
proc setOptionScript_2197824597*(option: string; value: JsonNode) =
  discard
proc quitScript_2197824689*() =
  discard
proc changeFontSizeScript_2197824733*(amount: float32) =
  discard
proc changeLayoutPropScript_2197824784*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825091*() =
  discard
proc createViewScript_2197825135*() =
  discard
proc closeCurrentViewScript_2197825183*() =
  discard
proc moveCurrentViewToTopScript_2197825272*() =
  discard
proc nextViewScript_2197825367*() =
  discard
proc prevViewScript_2197825417*() =
  discard
proc moveCurrentViewPrevScript_2197825470*() =
  discard
proc moveCurrentViewNextScript_2197825537*() =
  discard
proc setLayoutScript_2197825601*(layout: string) =
  discard
proc commandLineScript_2197825688*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197825743*() =
  discard
proc executeCommandLineScript_2197825791*(): bool =
  discard
proc openFileScript_2197825847*(path: string) =
  discard
proc writeFileScript_2197825940*(path: string = "") =
  discard
proc loadFileScript_2197826003*(path: string = "") =
  discard
proc loadThemeScript_2197826066*(name: string) =
  discard
proc chooseThemeScript_2197826153*() =
  discard
proc chooseFileScript_2197826475*(view: string = "new") =
  discard
proc reloadConfigScript_2197826606*() =
  discard
proc logOptionsScript_2197826691*() =
  discard
proc clearCommandsScript_2197826735*(context: string) =
  discard
proc getAllEditorsScript_2197826786*(): seq[EditorId] =
  discard
proc setModeScript22_2197827077*(mode: string) =
  discard
proc modeScript22_2197827160*(): string =
  discard
proc getContextWithModeScript22_2197827210*(context: string): string =
  discard
proc scriptRunActionScript_2197827485*(action: string; arg: string) =
  discard
proc scriptLogScript_2197827521*(message: string) =
  discard
proc addCommandScriptScript_2197827552*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197827625*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197827683*(): EditorId =
  discard
proc getActiveEditorScript_2197827720*(): EditorId =
  discard
proc getActiveEditor2Script_2197827751*(): EditorId =
  discard
proc loadCurrentConfigScript_2197827801*() =
  discard
proc sourceCurrentDocumentScript_2197827845*() =
  discard
proc getEditorScript_2197827889*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197827927*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197827994*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197828061*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197828160*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197828224*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197828292*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197828360*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197828436*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197828504*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197828582*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197828664*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197828711*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197828823*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197828870*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197828917*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197828992*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197829067*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197829142*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197829217*(path: string; id: int) =
  discard
