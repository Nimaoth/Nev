import std/[json]
import "../src/scripting_api"

## This file is auto generated, don't modify.

proc setModeScript_7113548649*(self: TextDocumentEditor; mode: string) =
  discard
proc modeScript_7113548847*(self: TextDocumentEditor): string =
  discard
proc getContextWithModeScript_7113548902*(self: TextDocumentEditor;
    context: string): string =
  discard
proc updateTargetColumnScript_7113548964*(self: TextDocumentEditor;
    cursor: SelectionCursor) =
  discard
proc invertSelectionScript_7113549065*(self: TextDocumentEditor) =
  discard
proc insertScript_7113549114*(self: TextDocumentEditor;
                             selections: seq[Selection]; text: string;
                             notify: bool = true; record: bool = true;
                             autoIndent: bool = true): seq[Selection] =
  discard
proc deleteScript_7113549478*(self: TextDocumentEditor;
                             selections: seq[Selection]; notify: bool = true;
                             record: bool = true): seq[Selection] =
  discard
proc selectPrevScript_7113549554*(self: TextDocumentEditor) =
  discard
proc selectNextScript_7113549766*(self: TextDocumentEditor) =
  discard
proc selectInsideScript_7113549955*(self: TextDocumentEditor; cursor: Cursor) =
  discard
proc selectInsideCurrentScript_7113550028*(self: TextDocumentEditor) =
  discard
proc selectLineScript_7113550077*(self: TextDocumentEditor; line: int) =
  discard
proc selectLineCurrentScript_7113550133*(self: TextDocumentEditor) =
  discard
proc selectParentTsScript_7113550182*(self: TextDocumentEditor;
                                     selection: Selection) =
  discard
proc selectParentCurrentTsScript_7113550252*(self: TextDocumentEditor) =
  discard
proc insertTextScript_7113550306*(self: TextDocumentEditor; text: string) =
  discard
proc undoScript_7113550371*(self: TextDocumentEditor) =
  discard
proc redoScript_7113550468*(self: TextDocumentEditor) =
  discard
proc scrollTextScript_7113550543*(self: TextDocumentEditor; amount: float32) =
  discard
proc duplicateLastSelectionScript_7113550661*(self: TextDocumentEditor) =
  discard
proc addCursorBelowScript_7113550752*(self: TextDocumentEditor) =
  discard
proc addCursorAboveScript_7113550813*(self: TextDocumentEditor) =
  discard
proc getPrevFindResultScript_7113550874*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc getNextFindResultScript_7113551194*(self: TextDocumentEditor;
                                        cursor: Cursor; offset: int = 0): Selection =
  discard
proc addNextFindResultToSelectionScript_7113551411*(self: TextDocumentEditor) =
  discard
proc addPrevFindResultToSelectionScript_7113551468*(self: TextDocumentEditor) =
  discard
proc setAllFindResultToSelectionScript_7113551525*(self: TextDocumentEditor) =
  discard
proc moveCursorColumnScript_7113551886*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorLineScript_7113551974*(self: TextDocumentEditor; distance: int;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorHomeScript_7113552044*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                     all: bool = true) =
  discard
proc moveCursorEndScript_7113552107*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                                    all: bool = true) =
  discard
proc moveCursorToScript_7113552170*(self: TextDocumentEditor; str: string; cursor: SelectionCursor = SelectionCursor.Config;
                                   all: bool = true) =
  discard
proc moveCursorBeforeScript_7113552247*(self: TextDocumentEditor; str: string;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorNextFindResultScript_7113552324*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc moveCursorPrevFindResultScript_7113552387*(self: TextDocumentEditor;
    cursor: SelectionCursor = SelectionCursor.Config; all: bool = true) =
  discard
proc scrollToCursorScript_7113552450*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config) =
  discard
proc reloadTreesitterScript_7113552506*(self: TextDocumentEditor) =
  discard
proc deleteLeftScript_7113552559*(self: TextDocumentEditor) =
  discard
proc deleteRightScript_7113552616*(self: TextDocumentEditor) =
  discard
proc getCommandCountScript_7113552673*(self: TextDocumentEditor): int =
  discard
proc setCommandCountScript_7113552728*(self: TextDocumentEditor; count: int) =
  discard
proc setCommandCountRestoreScript_7113552784*(self: TextDocumentEditor;
    count: int) =
  discard
proc updateCommandCountScript_7113552840*(self: TextDocumentEditor; digit: int) =
  discard
proc setFlagScript_7113552896*(self: TextDocumentEditor; name: string;
                              value: bool) =
  discard
proc getFlagScript_7113552959*(self: TextDocumentEditor; name: string): bool =
  discard
proc runActionScript_7113553021*(self: TextDocumentEditor; action: string;
                                args: JsonNode): bool =
  discard
proc findWordBoundaryScript_7113553093*(self: TextDocumentEditor; cursor: Cursor): Selection =
  discard
proc getSelectionForMoveScript_7113553182*(self: TextDocumentEditor;
    cursor: Cursor; move: string; count: int = 0): Selection =
  discard
proc setMoveScript_7113553375*(self: TextDocumentEditor; args: JsonNode) =
  discard
proc deleteMoveScript_7113553628*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc selectMoveScript_7113553728*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc changeMoveScript_7113553853*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                 all: bool = true) =
  discard
proc moveLastScript_7113553953*(self: TextDocumentEditor; move: string;
                               which: SelectionCursor = SelectionCursor.Config;
                               all: bool = true; count: int = 0) =
  discard
proc moveFirstScript_7113554067*(self: TextDocumentEditor; move: string; which: SelectionCursor = SelectionCursor.Config;
                                all: bool = true; count: int = 0) =
  discard
proc setSearchQueryScript_7113554181*(self: TextDocumentEditor; query: string) =
  discard
proc setSearchQueryFromMoveScript_7113554259*(self: TextDocumentEditor;
    move: string; count: int = 0) =
  discard
proc gotoDefinitionScript_7113555063*(self: TextDocumentEditor) =
  discard
proc getCompletionsScript_7113555116*(self: TextDocumentEditor) =
  discard
proc hideCompletionsScript_7113555169*(self: TextDocumentEditor) =
  discard
proc selectPrevCompletionScript_7113555218*(self: TextDocumentEditor) =
  discard
proc selectNextCompletionScript_7113555281*(self: TextDocumentEditor) =
  discard
proc applySelectedCompletionScript_7113555344*(self: TextDocumentEditor) =
  discard
proc moveCursorScript_7902080281*(self: AstDocumentEditor; direction: int) =
  discard
proc moveCursorUpScript_7902080383*(self: AstDocumentEditor) =
  discard
proc moveCursorDownScript_7902080444*(self: AstDocumentEditor) =
  discard
proc moveCursorNextScript_7902080493*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevScript_7902080549*(self: AstDocumentEditor) =
  discard
proc moveCursorNextLineScript_7902080604*(self: AstDocumentEditor) =
  discard
proc moveCursorPrevLineScript_7902080679*(self: AstDocumentEditor) =
  discard
proc selectContainingScript_7902080754*(self: AstDocumentEditor;
                                       container: string) =
  discard
proc deleteSelectedScript_7902080966*(self: AstDocumentEditor) =
  discard
proc copySelectedScript_7902081018*(self: AstDocumentEditor) =
  discard
proc finishEditScript_7902081070*(self: AstDocumentEditor; apply: bool) =
  discard
proc undoScript2_7902081168*(self: AstDocumentEditor) =
  discard
proc redoScript2_7902081243*(self: AstDocumentEditor) =
  discard
proc insertAfterSmartScript_7902081318*(self: AstDocumentEditor;
                                       nodeTemplate: string) =
  discard
proc insertAfterScript_7902081491*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertBeforeScript_7902081632*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc insertChildScript_7902081772*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceScript_7902081911*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceEmptyScript_7902082004*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc replaceParentScript_7902082101*(self: AstDocumentEditor) =
  discard
proc wrapScript_7902082160*(self: AstDocumentEditor; nodeTemplate: string) =
  discard
proc editPrevEmptyScript_7902082277*(self: AstDocumentEditor) =
  discard
proc editNextEmptyScript_7902082332*(self: AstDocumentEditor) =
  discard
proc renameScript_7902082395*(self: AstDocumentEditor) =
  discard
proc selectPrevCompletionScript2_7902082444*(self: AstDocumentEditor) =
  discard
proc selectNextCompletionScript2_7902082504*(editor: AstDocumentEditor) =
  discard
proc applySelectedCompletionScript2_7902082564*(editor: AstDocumentEditor) =
  discard
proc cancelAndNextCompletionScript_7902082726*(self: AstDocumentEditor) =
  discard
proc cancelAndPrevCompletionScript_7902082775*(self: AstDocumentEditor) =
  discard
proc cancelAndDeleteScript_7902082824*(self: AstDocumentEditor) =
  discard
proc moveNodeToPrevSpaceScript_7902082876*(self: AstDocumentEditor) =
  discard
proc moveNodeToNextSpaceScript_7902083029*(self: AstDocumentEditor) =
  discard
proc selectPrevScript2_7902083183*(self: AstDocumentEditor) =
  discard
proc selectNextScript2_7902083232*(self: AstDocumentEditor) =
  discard
proc gotoScript_7902083281*(self: AstDocumentEditor; where: string) =
  discard
proc runSelectedFunctionScript_7902084116*(self: AstDocumentEditor) =
  discard
proc toggleOptionScript_7902084384*(self: AstDocumentEditor; name: string) =
  discard
proc runLastCommandScript_7902084444*(self: AstDocumentEditor; which: string) =
  discard
proc selectCenterNodeScript_7902084500*(self: AstDocumentEditor) =
  discard
proc scrollScript_7902084956*(self: AstDocumentEditor; amount: float32) =
  discard
proc scrollOutputScript_7902085016*(self: AstDocumentEditor; arg: string) =
  discard
proc dumpContextScript_7902085083*(self: AstDocumentEditor) =
  discard
proc setModeScript2_7902085136*(self: AstDocumentEditor; mode: string) =
  discard
proc modeScript2_7902085224*(self: AstDocumentEditor): string =
  discard
proc getContextWithModeScript2_7902085279*(self: AstDocumentEditor;
    context: string): string =
  discard
proc acceptScript_8170504455*(self: SelectorPopup) =
  discard
proc cancelScript_8170504553*(self: SelectorPopup) =
  discard
proc prevScript_8170504608*(self: SelectorPopup) =
  discard
proc nextScript_8170504675*(self: SelectorPopup) =
  discard
proc getBackendScript_2197823911*(): Backend =
  discard
proc requestRenderScript_2197824076*() =
  discard
proc setHandleInputsScript_2197824119*(context: string; value: bool) =
  discard
proc setHandleActionsScript_2197824176*(context: string; value: bool) =
  discard
proc setConsumeAllActionsScript_2197824233*(context: string; value: bool) =
  discard
proc setConsumeAllInputScript_2197824290*(context: string; value: bool) =
  discard
proc getFlagScript2_2197824347*(flag: string; default: bool = false): bool =
  discard
proc setFlagScript2_2197824419*(flag: string; value: bool) =
  discard
proc toggleFlagScript_2197824531*(flag: string) =
  discard
proc setOptionScript_2197824581*(option: string; value: JsonNode) =
  discard
proc quitScript_2197824672*() =
  discard
proc changeFontSizeScript_2197824715*(amount: float32) =
  discard
proc changeLayoutPropScript_2197824765*(prop: string; change: float32) =
  discard
proc toggleStatusBarLocationScript_2197825071*() =
  discard
proc createViewScript_2197825114*() =
  discard
proc closeCurrentViewScript_2197825161*() =
  discard
proc moveCurrentViewToTopScript_2197825249*() =
  discard
proc nextViewScript_2197825343*() =
  discard
proc prevViewScript_2197825392*() =
  discard
proc moveCurrentViewPrevScript_2197825444*() =
  discard
proc moveCurrentViewNextScript_2197825510*() =
  discard
proc setLayoutScript_2197825573*(layout: string) =
  discard
proc commandLineScript_2197825659*(initialValue: string = "") =
  discard
proc exitCommandLineScript_2197825713*() =
  discard
proc executeCommandLineScript_2197825760*(): bool =
  discard
proc openFileScript_2197825815*(path: string) =
  discard
proc writeFileScript_2197825907*(path: string = "") =
  discard
proc loadFileScript_2197825969*(path: string = "") =
  discard
proc loadThemeScript_2197826031*(name: string) =
  discard
proc chooseThemeScript_2197826117*() =
  discard
proc chooseFileScript_2197826438*(view: string = "new") =
  discard
proc reloadConfigScript_2197826568*() =
  discard
proc logOptionsScript_2197826652*() =
  discard
proc clearCommandsScript_2197826695*(context: string) =
  discard
proc getAllEditorsScript_2197826745*(): seq[EditorId] =
  discard
proc setModeScript22_2197827035*(mode: string) =
  discard
proc modeScript22_2197827117*(): string =
  discard
proc getContextWithModeScript22_2197827166*(context: string): string =
  discard
proc scriptRunActionScript_2197827440*(action: string; arg: string) =
  discard
proc scriptLogScript_2197827475*(message: string) =
  discard
proc scriptAddCommandScript_2197827505*(context: string; keys: string;
                                       action: string; arg: string = "") =
  discard
proc removeCommandScript_2197827555*(context: string; keys: string) =
  discard
proc getActivePopupScript_2197827590*(): EditorId =
  discard
proc getActiveEditorScript_2197827626*(): EditorId =
  discard
proc getActiveEditor2Script_2197827656*(): EditorId =
  discard
proc loadCurrentConfigScript_2197827705*() =
  discard
proc sourceCurrentDocumentScript_2197827748*() =
  discard
proc getEditorScript_2197827791*(index: int): EditorId =
  discard
proc scriptIsTextEditorScript_2197827828*(editorId: EditorId): bool =
  discard
proc scriptIsAstEditorScript_2197827894*(editorId: EditorId): bool =
  discard
proc scriptRunActionForScript_2197827960*(editorId: EditorId; action: string;
    arg: string) =
  discard
proc scriptInsertTextIntoScript_2197828058*(editorId: EditorId; text: string) =
  discard
proc scriptTextEditorSelectionScript_2197828121*(editorId: EditorId): Selection =
  discard
proc scriptSetTextEditorSelectionScript_2197828188*(editorId: EditorId;
    selection: Selection) =
  discard
proc scriptTextEditorSelectionsScript_2197828255*(editorId: EditorId): seq[
    Selection] =
  discard
proc scriptSetTextEditorSelectionsScript_2197828330*(editorId: EditorId;
    selections: seq[Selection]) =
  discard
proc scriptGetTextEditorLineScript_2197828397*(editorId: EditorId; line: int): string =
  discard
proc scriptGetTextEditorLineCountScript_2197828474*(editorId: EditorId): int =
  discard
proc scriptGetOptionIntScript_2197828555*(path: string; default: int): int =
  discard
proc scriptGetOptionFloatScript_2197828601*(path: string; default: float): float =
  discard
proc scriptGetOptionBoolScript_2197828712*(path: string; default: bool): bool =
  discard
proc scriptGetOptionStringScript_2197828758*(path: string; default: string): string =
  discard
proc scriptSetOptionIntScript_2197828804*(path: string; value: int) =
  discard
proc scriptSetOptionFloatScript_2197828878*(path: string; value: float) =
  discard
proc scriptSetOptionBoolScript_2197828952*(path: string; value: bool) =
  discard
proc scriptSetOptionStringScript_2197829026*(path: string; value: string) =
  discard
proc scriptSetCallbackScript_2197829100*(path: string; id: int) =
  discard
