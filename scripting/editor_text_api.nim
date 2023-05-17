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
  setModeScript_6123696372(self, mode)
proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  modeScript_6123696564(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  ## Appends the current mode to context
  getContextWithModeScript_6123696613(self, context)
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  updateTargetColumnScript_6123696669(self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  ## Inverts the current selection. Discards all but the last cursor.
  invertSelectionScript_6123696764(self)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  insertScript_6123696807(self, selections, text, notify, record, autoIndent)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  deleteScript_6123697165(self, selections, notify, record)
proc selectPrev*(self: TextDocumentEditor) =
  selectPrevScript_6123697235(self)
proc selectNext*(self: TextDocumentEditor) =
  selectNextScript_6123697463(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  selectInsideScript_6123697668(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  selectInsideCurrentScript_6123697735(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  selectLineScript_6123697778(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  selectLineCurrentScript_6123697828(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  selectParentTsScript_6123697871(self, selection)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  selectParentCurrentTsScript_6123697935(self)
proc insertText*(self: TextDocumentEditor; text: string) =
  insertTextScript_6123697983(self, text)
proc undo*(self: TextDocumentEditor) =
  undoScript_6123698042(self)
proc redo*(self: TextDocumentEditor) =
  redoScript_6123698133(self)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  scrollTextScript_6123698202(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  duplicateLastSelectionScript_6123698314(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  addCursorBelowScript_6123698399(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  addCursorAboveScript_6123698454(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getPrevFindResultScript_6123698509(self, cursor, offset)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getNextFindResultScript_6123698842(self, cursor, offset)
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  addNextFindResultToSelectionScript_6123699068(self)
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  addPrevFindResultToSelectionScript_6123699119(self)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  setAllFindResultToSelectionScript_6123699170(self)
proc clearSelections*(self: TextDocumentEditor) =
  clearSelectionsScript_6123699555(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorColumnScript_6123699604(self, distance, cursor, all)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorLineScript_6123699686(self, distance, cursor, all)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorHomeScript_6123699750(self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  moveCursorEndScript_6123699807(self, cursor, all)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  moveCursorToScript_6123699864(self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorBeforeScript_6123699935(self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorNextFindResultScript_6123700006(self, cursor, all)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorPrevFindResultScript_6123700063(self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  scrollToCursorScript_6123700120(self, cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  reloadTreesitterScript_6123700170(self)
proc deleteLeft*(self: TextDocumentEditor) =
  deleteLeftScript_6123700217(self)
proc deleteRight*(self: TextDocumentEditor) =
  deleteRightScript_6123700268(self)
proc getCommandCount*(self: TextDocumentEditor): int =
  getCommandCountScript_6123700319(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  setCommandCountScript_6123700368(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  setCommandCountRestoreScript_6123700418(self, count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  updateCommandCountScript_6123700468(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  setFlagScript_6123700518(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  getFlagScript_6123700575(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  runActionScript_6123700631(self, action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  findWordBoundaryScript_6123700696(self, cursor)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  getSelectionForMoveScript_6123700779(self, cursor, move, count)
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  setMoveScript_6123700966(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  deleteMoveScript_6123701213(self, move, which, all)
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  selectMoveScript_6123701307(self, move, which, all)
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  changeMoveScript_6123701426(self, move, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  moveLastScript_6123701520(self, move, which, all, count)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  moveFirstScript_6123701628(self, move, which, all, count)
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  setSearchQueryScript_6123701736(self, query)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  setSearchQueryFromMoveScript_6123701808(self, move, count)
proc gotoDefinition*(self: TextDocumentEditor) =
  gotoDefinitionScript_6123703116(self)
proc getCompletions*(self: TextDocumentEditor) =
  getCompletionsScript_6123703163(self)
proc hideCompletions*(self: TextDocumentEditor) =
  hideCompletionsScript_6123703210(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  selectPrevCompletionScript_6123703253(self)
proc selectNextCompletion*(self: TextDocumentEditor) =
  selectNextCompletionScript_6123703313(self)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  applySelectedCompletionScript_6123703373(self)
