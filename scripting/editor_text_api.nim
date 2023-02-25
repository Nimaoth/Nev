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
  setModeScript_7667199223(self, mode)
proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  modeScript_7667199422(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  ## Appends the current mode to context
  getContextWithModeScript_7667199478(self, context)
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  updateTargetColumnScript_7667199541(self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  ## Inverts the current selection. Discards all but the last cursor.
  invertSelectionScript_7667199643(self)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  insertScript_7667199693(self, selections, text, notify, record, autoIndent)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  deleteScript_7667200058(self, selections, notify, record)
proc selectPrev*(self: TextDocumentEditor) =
  selectPrevScript_7667200135(self)
proc selectNext*(self: TextDocumentEditor) =
  selectNextScript_7667200348(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  selectInsideScript_7667200538(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  selectInsideCurrentScript_7667200612(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  selectLineScript_7667200662(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  selectLineCurrentScript_7667200719(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  selectParentTsScript_7667200769(self, selection)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  selectParentCurrentTsScript_7667200840(self)
proc insertText*(self: TextDocumentEditor; text: string) =
  insertTextScript_7667200895(self, text)
proc undo*(self: TextDocumentEditor) =
  undoScript_7667200961(self)
proc redo*(self: TextDocumentEditor) =
  redoScript_7667201059(self)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  scrollTextScript_7667201135(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  duplicateLastSelectionScript_7667201254(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  addCursorBelowScript_7667201346(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  addCursorAboveScript_7667201408(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getPrevFindResultScript_7667201470(self, cursor, offset)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getNextFindResultScript_7667201791(self, cursor, offset)
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  addNextFindResultToSelectionScript_7667202009(self)
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  addPrevFindResultToSelectionScript_7667202067(self)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  setAllFindResultToSelectionScript_7667202125(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorColumnScript_7667202487(self, distance, cursor, all)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorLineScript_7667202576(self, distance, cursor, all)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorHomeScript_7667202647(self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  moveCursorEndScript_7667202711(self, cursor, all)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  moveCursorToScript_7667202775(self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorBeforeScript_7667202853(self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorNextFindResultScript_7667202931(self, cursor, all)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorPrevFindResultScript_7667202995(self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  scrollToCursorScript_7667203059(self, cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  reloadTreesitterScript_7667203116(self)
proc deleteLeft*(self: TextDocumentEditor) =
  deleteLeftScript_7667203170(self)
proc deleteRight*(self: TextDocumentEditor) =
  deleteRightScript_7667203228(self)
proc getCommandCount*(self: TextDocumentEditor): int =
  getCommandCountScript_7667203286(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  setCommandCountScript_7667203342(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  setCommandCountRestoreScript_7667203399(self, count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  updateCommandCountScript_7667203456(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  setFlagScript_7667203513(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  getFlagScript_7667203577(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  runActionScript_7667203640(self, action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  findWordBoundaryScript_7667203713(self, cursor)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  getSelectionForMoveScript_7667203803(self, cursor, move, count)
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  setMoveScript_7667203997(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  deleteMoveScript_7667204251(self, move, which, all)
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  selectMoveScript_7667204352(self, move, which, all)
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  changeMoveScript_7667204478(self, move, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  moveLastScript_7667204579(self, move, which, all, count)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  moveFirstScript_7667204694(self, move, which, all, count)
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  setSearchQueryScript_7667204809(self, query)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  setSearchQueryFromMoveScript_7667204888(self, move, count)
proc gotoDefinition*(self: TextDocumentEditor) =
  gotoDefinitionScript_7667205693(self)
proc getCompletions*(self: TextDocumentEditor) =
  getCompletionsScript_7667205747(self)
proc hideCompletions*(self: TextDocumentEditor) =
  hideCompletionsScript_7667205801(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  selectPrevCompletionScript_7667205851(self)
proc selectNextCompletion*(self: TextDocumentEditor) =
  selectNextCompletionScript_7667205915(self)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  applySelectedCompletionScript_7667205979(self)
