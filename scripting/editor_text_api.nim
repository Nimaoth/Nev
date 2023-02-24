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
  setModeScript_7667196777(self, mode)
proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  modeScript_7667196976(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  ## Appends the current mode to context
  getContextWithModeScript_7667197032(self, context)
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  updateTargetColumnScript_7667197095(self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  ## Inverts the current selection. Discards all but the last cursor.
  invertSelectionScript_7667197197(self)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  insertScript_7667197247(self, selections, text, notify, record, autoIndent)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  deleteScript_7667197612(self, selections, notify, record)
proc selectPrev*(self: TextDocumentEditor) =
  selectPrevScript_7667197689(self)
proc selectNext*(self: TextDocumentEditor) =
  selectNextScript_7667197902(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  selectInsideScript_7667198092(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  selectInsideCurrentScript_7667198166(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  selectLineScript_7667198216(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  selectLineCurrentScript_7667198273(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  selectParentTsScript_7667198323(self, selection)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  selectParentCurrentTsScript_7667198394(self)
proc insertText*(self: TextDocumentEditor; text: string) =
  insertTextScript_7667198449(self, text)
proc undo*(self: TextDocumentEditor) =
  undoScript_7667198515(self)
proc redo*(self: TextDocumentEditor) =
  redoScript_7667198613(self)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  scrollTextScript_7667198689(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  duplicateLastSelectionScript_7667198808(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  addCursorBelowScript_7667198900(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  addCursorAboveScript_7667198962(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getPrevFindResultScript_7667199024(self, cursor, offset)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getNextFindResultScript_7667199345(self, cursor, offset)
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  addNextFindResultToSelectionScript_7667199563(self)
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  addPrevFindResultToSelectionScript_7667199621(self)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  setAllFindResultToSelectionScript_7667199679(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorColumnScript_7667200041(self, distance, cursor, all)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorLineScript_7667200130(self, distance, cursor, all)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorHomeScript_7667200201(self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  moveCursorEndScript_7667200265(self, cursor, all)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  moveCursorToScript_7667200329(self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorBeforeScript_7667200407(self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorNextFindResultScript_7667200485(self, cursor, all)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorPrevFindResultScript_7667200549(self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  scrollToCursorScript_7667200613(self, cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  reloadTreesitterScript_7667200670(self)
proc deleteLeft*(self: TextDocumentEditor) =
  deleteLeftScript_7667200724(self)
proc deleteRight*(self: TextDocumentEditor) =
  deleteRightScript_7667200782(self)
proc getCommandCount*(self: TextDocumentEditor): int =
  getCommandCountScript_7667200840(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  setCommandCountScript_7667200896(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  setCommandCountRestoreScript_7667200953(self, count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  updateCommandCountScript_7667201010(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  setFlagScript_7667201067(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  getFlagScript_7667201131(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  runActionScript_7667201194(self, action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  findWordBoundaryScript_7667201267(self, cursor)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  getSelectionForMoveScript_7667201357(self, cursor, move, count)
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  setMoveScript_7667201551(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  deleteMoveScript_7667201805(self, move, which, all)
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  selectMoveScript_7667201906(self, move, which, all)
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  changeMoveScript_7667202032(self, move, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  moveLastScript_7667202133(self, move, which, all, count)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  moveFirstScript_7667202248(self, move, which, all, count)
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  setSearchQueryScript_7667202363(self, query)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  setSearchQueryFromMoveScript_7667202442(self, move, count)
proc gotoDefinition*(self: TextDocumentEditor) =
  gotoDefinitionScript_7667203247(self)
proc getCompletions*(self: TextDocumentEditor) =
  getCompletionsScript_7667203301(self)
proc hideCompletions*(self: TextDocumentEditor) =
  hideCompletionsScript_7667203355(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  selectPrevCompletionScript_7667203405(self)
proc selectNextCompletion*(self: TextDocumentEditor) =
  selectNextCompletionScript_7667203469(self)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  applySelectedCompletionScript_7667203533(self)
