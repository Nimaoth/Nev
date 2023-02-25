import std/[json]
import "../src/scripting_api"
when defined(js):
  import absytree_internal_js
else:
  import absytree_internal

## This file is auto generated, don't modify.

proc setMode*(self: TextDocumentEditor; mode: string) =
  ## Sets the current mode of the editor. If `mode` is "", then no additional scope will be pushed on the scope stac.k
  ## If mode is e.g. "insert", then the scope "editor.text.insert" will be pushed on the scope stack above "editor.text"
  ## Don't use "completion", as that is used for when a completion window is open.
  setModeScript_7683976439(self, mode)
proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  modeScript_7683976638(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  ## Appends the current mode to context
  getContextWithModeScript_7683976694(self, context)
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  updateTargetColumnScript_7683976757(self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  ## Inverts the current selection. Discards all but the last cursor.
  invertSelectionScript_7683976859(self)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  insertScript_7683976909(self, selections, text, notify, record, autoIndent)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  deleteScript_7683977274(self, selections, notify, record)
proc selectPrev*(self: TextDocumentEditor) =
  selectPrevScript_7683977351(self)
proc selectNext*(self: TextDocumentEditor) =
  selectNextScript_7683977564(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  selectInsideScript_7683977754(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  selectInsideCurrentScript_7683977828(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  selectLineScript_7683977878(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  selectLineCurrentScript_7683977935(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  selectParentTsScript_7683977985(self, selection)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  selectParentCurrentTsScript_7683978056(self)
proc insertText*(self: TextDocumentEditor; text: string) =
  insertTextScript_7683978111(self, text)
proc undo*(self: TextDocumentEditor) =
  undoScript_7683978177(self)
proc redo*(self: TextDocumentEditor) =
  redoScript_7683978275(self)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  scrollTextScript_7683978351(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  duplicateLastSelectionScript_7683978470(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  addCursorBelowScript_7683978562(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  addCursorAboveScript_7683978624(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getPrevFindResultScript_7683978686(self, cursor, offset)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getNextFindResultScript_7683979007(self, cursor, offset)
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  addNextFindResultToSelectionScript_7683979225(self)
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  addPrevFindResultToSelectionScript_7683979283(self)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  setAllFindResultToSelectionScript_7683979341(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorColumnScript_7683979703(self, distance, cursor, all)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorLineScript_7683979792(self, distance, cursor, all)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorHomeScript_7683979863(self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  moveCursorEndScript_7683979927(self, cursor, all)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  moveCursorToScript_7683979991(self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorBeforeScript_7683980069(self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorNextFindResultScript_7683980147(self, cursor, all)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorPrevFindResultScript_7683980211(self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  scrollToCursorScript_7683980275(self, cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  reloadTreesitterScript_7683980332(self)
proc deleteLeft*(self: TextDocumentEditor) =
  deleteLeftScript_7683980386(self)
proc deleteRight*(self: TextDocumentEditor) =
  deleteRightScript_7683980444(self)
proc getCommandCount*(self: TextDocumentEditor): int =
  getCommandCountScript_7683980502(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  setCommandCountScript_7683980558(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  setCommandCountRestoreScript_7683980615(self, count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  updateCommandCountScript_7683980672(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  setFlagScript_7683980729(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  getFlagScript_7683980793(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  runActionScript_7683980856(self, action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  findWordBoundaryScript_7683980929(self, cursor)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  getSelectionForMoveScript_7683981019(self, cursor, move, count)
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  setMoveScript_7683981213(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  deleteMoveScript_7683981467(self, move, which, all)
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  selectMoveScript_7683981568(self, move, which, all)
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  changeMoveScript_7683981694(self, move, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  moveLastScript_7683981795(self, move, which, all, count)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  moveFirstScript_7683981910(self, move, which, all, count)
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  setSearchQueryScript_7683982025(self, query)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  setSearchQueryFromMoveScript_7683982104(self, move, count)
proc gotoDefinition*(self: TextDocumentEditor) =
  gotoDefinitionScript_7683982909(self)
proc getCompletions*(self: TextDocumentEditor) =
  getCompletionsScript_7683982963(self)
proc hideCompletions*(self: TextDocumentEditor) =
  hideCompletionsScript_7683983017(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  selectPrevCompletionScript_7683983067(self)
proc selectNextCompletion*(self: TextDocumentEditor) =
  selectNextCompletionScript_7683983131(self)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  applySelectedCompletionScript_7683983195(self)
