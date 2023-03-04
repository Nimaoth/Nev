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
  setModeScript_7683977458(self, mode)
proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  modeScript_7683977657(self)
proc getContextWithMode*(self: TextDocumentEditor; context: string): string =
  ## Appends the current mode to context
  getContextWithModeScript_7683977713(self, context)
proc updateTargetColumn*(self: TextDocumentEditor; cursor: SelectionCursor) =
  updateTargetColumnScript_7683977776(self, cursor)
proc invertSelection*(self: TextDocumentEditor) =
  ## Inverts the current selection. Discards all but the last cursor.
  invertSelectionScript_7683977878(self)
proc insert*(self: TextDocumentEditor; selections: seq[Selection]; text: string;
             notify: bool = true; record: bool = true; autoIndent: bool = true): seq[
    Selection] =
  insertScript_7683977928(self, selections, text, notify, record, autoIndent)
proc delete*(self: TextDocumentEditor; selections: seq[Selection];
             notify: bool = true; record: bool = true): seq[Selection] =
  deleteScript_7683978293(self, selections, notify, record)
proc selectPrev*(self: TextDocumentEditor) =
  selectPrevScript_7683978370(self)
proc selectNext*(self: TextDocumentEditor) =
  selectNextScript_7683978605(self)
proc selectInside*(self: TextDocumentEditor; cursor: Cursor) =
  selectInsideScript_7683978817(self, cursor)
proc selectInsideCurrent*(self: TextDocumentEditor) =
  selectInsideCurrentScript_7683978891(self)
proc selectLine*(self: TextDocumentEditor; line: int) =
  selectLineScript_7683978941(self, line)
proc selectLineCurrent*(self: TextDocumentEditor) =
  selectLineCurrentScript_7683978998(self)
proc selectParentTs*(self: TextDocumentEditor; selection: Selection) =
  selectParentTsScript_7683979048(self, selection)
proc selectParentCurrentTs*(self: TextDocumentEditor) =
  selectParentCurrentTsScript_7683979119(self)
proc insertText*(self: TextDocumentEditor; text: string) =
  insertTextScript_7683979174(self, text)
proc undo*(self: TextDocumentEditor) =
  undoScript_7683979240(self)
proc redo*(self: TextDocumentEditor) =
  redoScript_7683979338(self)
proc scrollText*(self: TextDocumentEditor; amount: float32) =
  scrollTextScript_7683979414(self, amount)
proc duplicateLastSelection*(self: TextDocumentEditor) =
  duplicateLastSelectionScript_7683979533(self)
proc addCursorBelow*(self: TextDocumentEditor) =
  addCursorBelowScript_7683979625(self)
proc addCursorAbove*(self: TextDocumentEditor) =
  addCursorAboveScript_7683979687(self)
proc getPrevFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getPrevFindResultScript_7683979749(self, cursor, offset)
proc getNextFindResult*(self: TextDocumentEditor; cursor: Cursor;
                        offset: int = 0): Selection =
  getNextFindResultScript_7683980089(self, cursor, offset)
proc addNextFindResultToSelection*(self: TextDocumentEditor) =
  addNextFindResultToSelectionScript_7683980322(self)
proc addPrevFindResultToSelection*(self: TextDocumentEditor) =
  addPrevFindResultToSelectionScript_7683980380(self)
proc setAllFindResultToSelection*(self: TextDocumentEditor) =
  setAllFindResultToSelectionScript_7683980438(self)
proc clearSelections*(self: TextDocumentEditor) =
  clearSelectionsScript_7683980830(self)
proc moveCursorColumn*(self: TextDocumentEditor; distance: int;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorColumnScript_7683980886(self, distance, cursor, all)
proc moveCursorLine*(self: TextDocumentEditor; distance: int;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorLineScript_7683980975(self, distance, cursor, all)
proc moveCursorHome*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config;
                     all: bool = true) =
  moveCursorHomeScript_7683981046(self, cursor, all)
proc moveCursorEnd*(self: TextDocumentEditor;
                    cursor: SelectionCursor = SelectionCursor.Config;
                    all: bool = true) =
  moveCursorEndScript_7683981110(self, cursor, all)
proc moveCursorTo*(self: TextDocumentEditor; str: string;
                   cursor: SelectionCursor = SelectionCursor.Config;
                   all: bool = true) =
  moveCursorToScript_7683981174(self, str, cursor, all)
proc moveCursorBefore*(self: TextDocumentEditor; str: string;
                       cursor: SelectionCursor = SelectionCursor.Config;
                       all: bool = true) =
  moveCursorBeforeScript_7683981252(self, str, cursor, all)
proc moveCursorNextFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorNextFindResultScript_7683981330(self, cursor, all)
proc moveCursorPrevFindResult*(self: TextDocumentEditor; cursor: SelectionCursor = SelectionCursor.Config;
                               all: bool = true) =
  moveCursorPrevFindResultScript_7683981394(self, cursor, all)
proc scrollToCursor*(self: TextDocumentEditor;
                     cursor: SelectionCursor = SelectionCursor.Config) =
  scrollToCursorScript_7683981458(self, cursor)
proc reloadTreesitter*(self: TextDocumentEditor) =
  reloadTreesitterScript_7683981515(self)
proc deleteLeft*(self: TextDocumentEditor) =
  deleteLeftScript_7683981569(self)
proc deleteRight*(self: TextDocumentEditor) =
  deleteRightScript_7683981627(self)
proc getCommandCount*(self: TextDocumentEditor): int =
  getCommandCountScript_7683981685(self)
proc setCommandCount*(self: TextDocumentEditor; count: int) =
  setCommandCountScript_7683981741(self, count)
proc setCommandCountRestore*(self: TextDocumentEditor; count: int) =
  setCommandCountRestoreScript_7683981798(self, count)
proc updateCommandCount*(self: TextDocumentEditor; digit: int) =
  updateCommandCountScript_7683981855(self, digit)
proc setFlag*(self: TextDocumentEditor; name: string; value: bool) =
  setFlagScript_7683981912(self, name, value)
proc getFlag*(self: TextDocumentEditor; name: string): bool =
  getFlagScript_7683981976(self, name)
proc runAction*(self: TextDocumentEditor; action: string; args: JsonNode): bool =
  runActionScript_7683982039(self, action, args)
proc findWordBoundary*(self: TextDocumentEditor; cursor: Cursor): Selection =
  findWordBoundaryScript_7683982111(self, cursor)
proc getSelectionForMove*(self: TextDocumentEditor; cursor: Cursor;
                          move: string; count: int = 0): Selection =
  getSelectionForMoveScript_7683982201(self, cursor, move, count)
proc setMove*(self: TextDocumentEditor; args: JsonNode) =
  setMoveScript_7683982395(self, args)
proc deleteMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  deleteMoveScript_7683982649(self, move, which, all)
proc selectMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  selectMoveScript_7683982750(self, move, which, all)
proc changeMove*(self: TextDocumentEditor; move: string;
                 which: SelectionCursor = SelectionCursor.Config;
                 all: bool = true) =
  changeMoveScript_7683982876(self, move, which, all)
proc moveLast*(self: TextDocumentEditor; move: string;
               which: SelectionCursor = SelectionCursor.Config;
               all: bool = true; count: int = 0) =
  moveLastScript_7683982977(self, move, which, all, count)
proc moveFirst*(self: TextDocumentEditor; move: string;
                which: SelectionCursor = SelectionCursor.Config;
                all: bool = true; count: int = 0) =
  moveFirstScript_7683983092(self, move, which, all, count)
proc setSearchQuery*(self: TextDocumentEditor; query: string) =
  setSearchQueryScript_7683983207(self, query)
proc setSearchQueryFromMove*(self: TextDocumentEditor; move: string;
                             count: int = 0) =
  setSearchQueryFromMoveScript_7683983286(self, move, count)
proc gotoDefinition*(self: TextDocumentEditor) =
  gotoDefinitionScript_7683984502(self)
proc getCompletions*(self: TextDocumentEditor) =
  getCompletionsScript_7683984556(self)
proc hideCompletions*(self: TextDocumentEditor) =
  hideCompletionsScript_7683984610(self)
proc selectPrevCompletion*(self: TextDocumentEditor) =
  selectPrevCompletionScript_7683984660(self)
proc selectNextCompletion*(self: TextDocumentEditor) =
  selectNextCompletionScript_7683984727(self)
proc applySelectedCompletion*(self: TextDocumentEditor) =
  applySelectedCompletionScript_7683984794(self)
