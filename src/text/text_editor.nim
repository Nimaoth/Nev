import std/[strutils, logging, sequtils, sugar, options, json, jsonutils, streams, strformat, tables, deques, sets, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import document, document_editor, events, id, util, vmath, bumpy, rect_utils, event, input, ../regex, custom_logger, custom_async, custom_treesitter, indent, fuzzy_matching
import scripting/[expose]
import platform/[platform, filesystem, widgets]
import language/[languages, language_server_base]
import workspaces/[workspace]
import text_document
import config_provider, app_interface
import delayed_task

export text_document, document_editor, id

type
  Command = object
    isInput: bool
    command: string
    args: JsonNode
  CommandHistory = object
    commands: seq[Command]

type TextDocumentEditor* = ref object of DocumentEditor
  app*: AppInterface
  platform*: Platform
  document*: TextDocument

  configProvider: ConfigProvider

  selectionsInternal: Selections
  targetSelectionsInternal: Option[Selections] # The selections we want to have once the document is loaded
  selectionHistory: Deque[Selections]
  dontRecordSelectionHistory: bool

  searchQuery*: string
  searchRegex*: Option[Regex]
  searchResults*: Table[int, seq[Selection]]

  targetColumn: int
  hideCursorWhenInactive*: bool
  cursorVisible*: bool
  blinkCursor: bool
  blinkCursorTask: DelayedTask

  completionEventHandler: EventHandler
  modeEventHandler: EventHandler
  currentMode*: string
  commandCount*: int
  commandCountRestore*: int
  currentCommandHistory: CommandHistory
  savedCommandHistory: CommandHistory
  bIsRunningSavedCommands: bool

  disableScrolling*: bool
  scrollOffset*: float
  previousBaseIndex*: int
  lineNumbers*: Option[LineNumbers]

  lastRenderedLines*: seq[StyledLine]

  disableCompletions*: bool
  completions*: seq[TextCompletion]
  selectedCompletion*: int
  completionsBaseIndex*: int
  completionsScrollOffset*: float
  lastItems*: seq[tuple[index: int, bounds: Rect]]
  lastCompletionsWidget*: WWidget
  lastCompletionWidgets*: seq[tuple[index: int, widget: WWidget]]
  showCompletions*: bool
  scrollToCompletion*: Option[int]

  updateCompletionsTask: DelayedTask

template noSelectionHistory(self, body: untyped): untyped =
  block:
    let temp = self.dontRecordSelectionHistory
    self.dontRecordSelectionHistory = true
    defer:
      self.dontRecordSelectionHistory = temp
    body

proc newTextEditor*(document: TextDocument, app: AppInterface, configProvider: ConfigProvider): TextDocumentEditor
proc handleAction(self: TextDocumentEditor, action: string, arg: string): EventResponse
proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse
proc handleInput(self: TextDocumentEditor, input: string): EventResponse
proc showCompletionWindow(self: TextDocumentEditor)
proc refilterCompletions(self: TextDocumentEditor)

proc lineLength*(self: TextDocumentEditor, line: int): int =
  if line < self.document.lines.len:
    return self.document.lines[line].len
  return 0

proc clampCursor*(self: TextDocumentEditor, cursor: Cursor): Cursor = self.document.clampCursor(cursor)

proc clampSelection*(self: TextDocumentEditor, selection: Selection): Selection = self.document.clampSelection(selection)

proc clampAndMergeSelections*(self: TextDocumentEditor, selections: openArray[Selection]): Selections = self.document.clampAndMergeSelections(selections)

proc selections*(self: TextDocumentEditor): Selections = self.selectionsInternal
proc selection*(self: TextDocumentEditor): Selection = self.selectionsInternal[self.selectionsInternal.high]

proc `selections=`*(self: TextDocumentEditor, selections: Selections) =
  let selections = self.clampAndMergeSelections(selections)
  if self.selectionsInternal == selections:
    return

  if not self.dontRecordSelectionHistory:
    self.selectionHistory.addLast self.selectionsInternal
    if self.selectionHistory.len > 100:
      discard self.selectionHistory.popFirst
  self.selectionsInternal = selections
  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()
  self.markDirty()

proc `selection=`*(self: TextDocumentEditor, selection: Selection) =
  if self.selectionsInternal.len == 1 and self.selectionsInternal[0] == selection:
    return

  if not self.dontRecordSelectionHistory:
    self.selectionHistory.addLast self.selectionsInternal
    if self.selectionHistory.len > 100:
      discard self.selectionHistory.popFirst
  self.selectionsInternal = @[self.clampSelection selection]
  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()
  self.markDirty()

proc `targetSelection=`*(self: TextDocumentEditor, selection: Selection) =
  self.targetSelectionsInternal = @[selection].some
  self.selection = selection

proc clampSelection*(self: TextDocumentEditor) =
  self.selections = self.clampAndMergeSelections(self.selectionsInternal)
  self.markDirty()

proc startBlinkCursorTask(self: TextDocumentEditor) =
  if not self.blinkCursor:
    return

  if self.blinkCursorTask.isNil:
    self.blinkCursorTask = startDelayed(500, repeat=true):
      if not self.active:
        self.cursorVisible = true
        self.markDirty()
        self.blinkCursorTask.pause()
        return
      self.cursorVisible = not self.cursorVisible
      self.markDirty()
  else:
    self.blinkCursorTask.reschedule()

method shutdown*(self: TextDocumentEditor) =
  self.document.destroy()

# proc `=destroy`[T: object](doc: var TextDocument) =
#   doc.tsParser.tsParserDelete()

method canEdit*(self: TextDocumentEditor, document: Document): bool =
  if document of TextDocument: return true
  else: return false

method getEventHandlers*(self: TextDocumentEditor): seq[EventHandler] =
  result = @[self.eventHandler]
  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler
  if self.showCompletions:
    result.add self.completionEventHandler

proc updateSearchResults(self: TextDocumentEditor) =
  if self.searchRegex.isNone:
    self.searchResults.clear()
    self.markDirty()
    return

  for i, line in self.document.lines:
    var selections: seq[Selection] = @[]
    var start = 0
    while start < line.len:
      let bounds = line.findBounds(self.searchRegex.get, start)
      if bounds.first == -1:
        break
      selections.add ((i, start + bounds.first), (i, start + bounds.last + 1))
      start = start + bounds.last + 1

    if selections.len > 0:
      self.searchResults[i] = selections
    else:
      self.searchResults.del i
  self.markDirty()

method handleDocumentChanged*(self: TextDocumentEditor) =
  self.selection = (self.clampCursor self.selection.first, self.clampCursor self.selection.last)
  self.updateSearchResults()

method handleActivate*(self: TextDocumentEditor) =
  self.startBlinkCursorTask()

method handleDeactivate*(self: TextDocumentEditor) =
  if self.blinkCursorTask.isNotNil:
    self.blinkCursorTask.pause()
    self.cursorVisible = true
    self.markDirty()

proc doMoveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  var cursor = cursor
  let column = cursor.column + offset
  if column < 0:
    if cursor.line > 0:
      cursor.line = cursor.line - 1
      cursor.column = self.lineLength cursor.line
    else:
      cursor.column = 0

  elif column > self.lineLength cursor.line:
    if cursor.line < self.document.lines.len - 1:
      cursor.line = cursor.line + 1
      cursor.column = 0
    else:
      cursor.column = self.lineLength cursor.line

  else:
    cursor.column = column

  return self.clampCursor cursor

proc doMoveCursorLine(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  var cursor = cursor
  let line = cursor.line + offset
  if line < 0:
    cursor = (0, cursor.column)
  elif line >= self.document.lines.len:
    cursor = (self.document.lines.len - 1, cursor.column)
  else:
    cursor.line = line
    cursor.column = self.targetColumn
  return self.clampCursor cursor

proc doMoveCursorHome(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return (cursor.line, 0)

proc doMoveCursorEnd(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return (cursor.line, self.document.lineLength cursor.line)

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0): Selection
proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0): Selection

proc doMoveCursorPrevFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return self.getPrevFindResult(cursor, offset).first

proc doMoveCursorNextFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return self.getNextFindResult(cursor, offset).first

proc centerCursor*(self: TextDocumentEditor, cursor: Cursor) =
  if self.disableScrolling:
    return

  self.previousBaseIndex = cursor.line
  self.scrollOffset = self.lastContentBounds.h * 0.5 - self.platform.totalLineHeight * 0.5

  self.markDirty()

proc scrollToCursor*(self: TextDocumentEditor, cursor: Cursor) =
  if self.disableScrolling:
    return

  let targetLine = cursor.line
  let totalLineHeight = self.platform.totalLineHeight

  let targetLineY = (targetLine - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

  let configMarginRelative = self.configProvider.getValue("text.cursor-margin-relative", true)
  let configMargin = self.configProvider.getValue("text.cursor-margin", 0.2)
  let margin = if configMarginRelative:
    clamp(configMargin, 0.0, 1.0) * 0.5 * self.lastContentBounds.h
  else:
    clamp(configMargin, 0.0, self.lastContentBounds.h * 0.5 - totalLineHeight * 0.5)

  if targetLineY < 0:
    self.centerCursor(cursor)
  elif targetLineY < margin:
    self.scrollOffset = margin
    self.previousBaseIndex = targetLine
  elif targetLineY + totalLineHeight > self.lastContentBounds.h:
    self.centerCursor(cursor)
  elif targetLineY + totalLineHeight > self.lastContentBounds.h - margin:
    self.scrollOffset = self.lastContentBounds.h - margin - totalLineHeight
    self.previousBaseIndex = targetLine

  self.markDirty()

proc getContextWithMode*(self: TextDocumentEditor, context: string): string

proc isThickCursor(self: TextDocumentEditor): bool =
  return self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.wide"), false)

proc getCursor(self: TextDocumentEditor, cursor: SelectionCursor): Cursor =
  case cursor
  of Config:
    let configCursor = self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    return self.getCursor(configCursor)
  of Both, Last, LastToFirst:
    return self.selection.last
  of First:
    return self.selection.first

proc moveCursor(self: TextDocumentEditor, cursor: SelectionCursor, movement: proc(doc: TextDocumentEditor, c: Cursor, off: int): Cursor, offset: int, all: bool) =
  case cursor
  of Config:
    let configCursor = self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    self.moveCursor(configCursor, movement, offset, all)

  of Both:
    if all:
      self.selections = self.selections.map (s) => movement(self, s.last, offset).toSelection
    else:
      var selections = self.selections
      selections[selections.high] = movement(self, selections[selections.high].last, offset).toSelection
      self.selections = selections
    self.scrollToCursor(self.selection.last)

  of First:
    if all:
      self.selections = self.selections.map (s) => (movement(self, s.first, offset), s.last)
    else:
      var selections = self.selections
      selections[selections.high] = (movement(self, selections[selections.high].first, offset), selections[selections.high].last)
      self.selections = selections
    self.scrollToCursor(self.selection.first)

  of Last:
    if all:
      self.selections = self.selections.map (s) => (s.first, movement(self, s.last, offset))
    else:
      var selections = self.selections
      selections[selections.high] = (selections[selections.high].first, movement(self, selections[selections.high].last, offset))
      self.selections = selections
    self.scrollToCursor(self.selection.last)

  of LastToFirst:
    if all:
      self.selections = self.selections.map (s) => (s.last, movement(self, s.last, offset))
    else:
      var selections = self.selections
      selections[selections.high] = (selections[selections.high].last, movement(self, selections[selections.high].last, offset))
      self.selections = selections
    self.scrollToCursor(self.selection.last)

proc getHoveredCompletion*(self: TextDocumentEditor, mousePosWindow: Vec2): int =
  for item in self.lastCompletionWidgets:
    if item.widget.lastBounds.contains(mousePosWindow):
      return item.index

  return 0

method handleScroll*(self: TextDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  if self.disableScrolling:
    return

  let scrollAmount = scroll.y * self.configProvider.getValue("text.scroll-speed", 40.0)
  if not self.lastCompletionsWidget.isNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
    self.completionsScrollOffset += scrollAmount
  else:
    self.scrollOffset += scrollAmount
  self.markDirty()

proc getTextDocumentEditor(wrapper: api.TextDocumentEditor): Option[TextDocumentEditor] =
  if gAppInterface.isNil: return TextDocumentEditor.none
  if gAppInterface.getEditorForId(wrapper.id).getSome(editor):
    if editor of TextDocumentEditor:
      return editor.TextDocumentEditor.some
  return TextDocumentEditor.none

proc getModeConfig(self: TextDocumentEditor, mode: string): EventHandlerConfig =
  return self.app.getEventHandlerConfig("editor.text." & mode)

static:
  addTypeMap(TextDocumentEditor, api.TextDocumentEditor, getTextDocumentEditor)

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config)

proc toJson*(self: api.TextDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.text")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.TextDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc setMode*(self: TextDocumentEditor, mode: string) {.expose("editor.text").} =
  ## Sets the current mode of the editor. If `mode` is "", then no additional scope will be pushed on the scope stac.k
  ## If mode is e.g. "insert", then the scope "editor.text.insert" will be pushed on the scope stack above "editor.text"
  ## Don't use "completion", as that is used for when a completion window is open.
  if mode == "completion":
    logger.log(lvlError, fmt"Can't set mode to '{mode}'")
    return

  if self.currentMode == mode:
    return

  if mode.len == 0:
    self.modeEventHandler = nil
  else:
    let config = self.getModeConfig(mode)
    self.modeEventHandler = eventHandler(config):
      onAction:
        self.handleAction action, arg
      onInput:
        self.handleInput input

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  let oldMode = self.currentMode
  self.currentMode = mode

  self.app.handleModeChanged(self, oldMode, self.currentMode)

  self.markDirty()

proc mode*(self: TextDocumentEditor): string {.expose("editor.text").} =
  ## Returns the current mode of the text editor, or "" if there is no mode
  return self.currentMode

proc getContextWithMode(self: TextDocumentEditor, context: string): string {.expose("editor.text").} =
  ## Appends the current mode to context
  return context & "." & $self.currentMode

proc updateTargetColumn(self: TextDocumentEditor, cursor: SelectionCursor) {.expose("editor.text").} =
  self.targetColumn = self.getCursor(cursor).column

proc invertSelection(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Inverts the current selection. Discards all but the last cursor.
  self.selection = (self.selection.last, self.selection.first)

proc insert(self: TextDocumentEditor, selections: seq[Selection], text: string, notify: bool = true, record: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.insert(selections, self.selections, [text], notify, record)

proc delete(self: TextDocumentEditor, selections: seq[Selection], notify: bool = true, record: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.delete(selections, self.selections, notify, record)

proc selectPrev(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popLast
    self.selectionHistory.addFirst self.selections
    self.selectionsInternal = selection
  self.scrollToCursor(self.selection.last)

proc selectNext(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popFirst
    self.selectionHistory.addLast self.selections
    self.selectionsInternal = selection
  self.scrollToCursor(self.selection.last)

proc selectInside(self: TextDocumentEditor, cursor: Cursor) {.expose("editor.text").} =
  let regex = re("[a-zA-Z0-9_]")
  var first = cursor.column
  # echo self.document.lines[cursor.line], ", ", first, ", ", self.document.lines[cursor.line].matchLen(regex, start = first - 1)
  while first > 0 and self.document.lines[cursor.line].matchLen(regex, start = first - 1) == 1:
    first -= 1
  var last = cursor.column
  while last < self.document.lines[cursor.line].len and self.document.lines[cursor.line].matchLen(regex, start = last) == 1:
    last += 1
  self.selection = ((cursor.line, first), (cursor.line, last))

proc selectInsideCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selectInside(self.selection.last)

proc selectLine(self: TextDocumentEditor, line: int) {.expose("editor.text").} =
  self.selection = ((line, 0), (line, self.lineLength(line)))

proc selectLineCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selectLine(self.selection.last.line)

proc selectParentTs(self: TextDocumentEditor, selection: Selection) {.expose("editor.text").} =
  if self.document.currentTree.isNil:
    return

  var node = self.document.currentTree.root.descendantForRange(selection)
  while node.getRange == selection and node != self.document.currentTree.root:
    node = node.parent

  self.selection = node.getRange

proc selectParentCurrentTs(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selectParentTs(self.selection)

proc getCompletionsAsync(self: TextDocumentEditor): Future[void] {.async.}

proc insertText*(self: TextDocumentEditor, text: string) {.expose("editor.text").} =
  if self.document.singleLine and text == "\n":
    return

  let originalSelections = self.selections.normalized
  var selections = originalSelections

  var texts = @[text]

  var allWhitespace = false
  if text == "\n":
    allWhitespace = true
    for selection in selections:
      if selection.first != selection.last:
        allWhitespace = false
        break
      for c in self.document.lines[selection.first.line]:
        if c != ' ' and c != '\t':
          allWhitespace = false
          break
      if not allWhitespace:
        break

    if allWhitespace:
      for s in selections.mitems:
        s.first.column = 0
        s.last = s.first

    else:
      texts.setLen(selections.len)
      for i, selection in selections:
        let line = self.document.lines[selection.last.line]
        let indent = indentForNewLine(self.document.languageConfig, line, self.document.indentStyle, self.document.tabWidth, selection.last.column)
        texts[i] = "\n" & indent

  selections = self.document.edit(selections, selections, texts)

  if allWhitespace:
    for i in 0..min(self.selections.high, originalSelections.high):
      selections[i].first.column = originalSelections[i].first.column
      selections[i].last.column = originalSelections[i].last.column

  self.selections = selections

  self.updateTargetColumn(Last)

  if not self.disableCompletions and (text == "." or text == "," or text == " "):
    self.showCompletionWindow()
    asyncCheck self.getCompletionsAsync()

proc indent*(self: TextDocumentEditor) {.expose("editor.text").} =
  var linesToIndent = initHashSet[int]()
  for selection in self.selections:
    let selection = selection.normalized
    for l in selection.first.line..selection.last.line:
      if selection.first.line != selection.last.line:
        if l == selection.first.line and selection.first.column == self.document.lines[l].len:
          continue
        if l == selection.last.line and selection.last.column == 0:
          continue
      linesToIndent.incl l

  let indent = self.document.indentStyle.getString()
  var indentSelections: Selections = @[]
  for l in linesToIndent:
    indentSelections.add (l, 0).toSelection

  discard self.document.insert(indentSelections.normalized, self.selections, [indent])

  var selections = self.selections
  for s in selections.mitems:
    if s.first.line in linesToIndent:
      s.first.column += self.document.indentStyle.indentColumns
    if s.last.line in linesToIndent:
      s.last.column += self.document.indentStyle.indentColumns
  self.selections = selections

func firstNonWhitespace(str: string): int =
  result = str.high
  for i, c in str:
    if c == ' ' or c == '\t':
      continue
    return i

proc unindent*(self: TextDocumentEditor) {.expose("editor.text").} =
  var linesToIndent = initHashSet[int]()
  for selection in self.selections:
    let selection = selection.normalized
    for l in selection.first.line..selection.last.line:
      if selection.first.line != selection.last.line:
        if l == selection.first.line and selection.first.column == self.document.lines[l].len:
          continue
        if l == selection.last.line and selection.last.column == 0:
          continue
      linesToIndent.incl l

  var indentSelections: Selections = @[]
  for l in linesToIndent:
    let firstNonWhitespace = self.document.lines[l].firstNonWhitespace
    indentSelections.add ((l, 0), (l, min(self.document.indentStyle.indentColumns, firstNonWhitespace)))

  var selections = self.selections
  discard self.document.delete(indentSelections.normalized, self.selections)

  for s in selections.mitems:
    if s.first.line in linesToIndent:
      s.first.column = max(0, s.first.column - self.document.indentStyle.indentColumns)
    if s.last.line in linesToIndent:
      s.last.column = max(0, s.last.column - self.document.indentStyle.indentColumns)
  self.selections = selections

proc undo*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.undo(self.selections, true).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)

proc redo*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.redo(self.selections, true).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)

proc copy*(self: TextDocumentEditor) {.expose("editor.text").} =
  var text = ""
  for i, selection in self.selections:
    if i > 0:
      text.add "\n"
    text.add self.document.contentString(selection)

  self.app.setRegisterText(text, "")

proc paste*(self: TextDocumentEditor) {.expose("editor.text").} =
  let text = self.app.getRegisterText("")

  let numLines = text.count('\n') + 1

  let newSelections = if numLines == self.selections.len:
    let lines = text.splitLines()
    self.document.edit(self.selections, self.selections, lines, notify=true, record=true)
  else:
    self.document.edit(self.selections, self.selections, [text], notify=true, record=true)

  # add list of selections for what was just pasted to history
  if newSelections.len == self.selections.len:
    var tempSelections = newSelections
    for i in 0..tempSelections.high:
      tempSelections[i].first = self.selections[i].first
    self.selections = tempSelections

  self.selections = newSelections
  self.scrollToCursor(Last)

proc scrollText(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.scrollOffset += amount
  self.markDirty()

proc duplicateLastSelection*(self: TextDocumentEditor) {.expose("editor.text").} =
  let newSelection = self.doMoveCursorColumn(self.selections[self.selections.high].last, 1).toSelection
  self.selections = self.selections & @[newSelection]

proc addCursorBelow*(self: TextDocumentEditor) {.expose("editor.text").} =
  let newCursor = self.doMoveCursorLine(self.selections[self.selections.high].last, 1).toSelection
  if not self.selections.contains(newCursor):
    self.selections = self.selections & @[newCursor]

proc addCursorAbove*(self: TextDocumentEditor) {.expose("editor.text").} =
  let newCursor = self.doMoveCursorLine(self.selections[self.selections.high].last, -1).toSelection
  if not self.selections.contains(newCursor):
    self.selections = self.selections & @[newCursor]

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0): Selection {.expose("editor.text").} =
  var i = 0
  for line in countdown(cursor.line, 0):
    if self.searchResults.contains(line):
      let selections = self.searchResults[line]
      for k in countdown(selections.high, 0):
        if selections[k].last < cursor:
          if i == offset:
            return selections[k]
          inc i
  return cursor.toSelection

proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0): Selection {.expose("editor.text").} =
  var i = 0
  for line in cursor.line..self.document.lines.high:
    if self.searchResults.contains(line):
      for selection in self.searchResults[line]:
        if cursor < selection.first:
          if i == offset:
            return selection
          inc i
  return cursor.toSelection

proc addNextFindResultToSelection*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selections = self.selections & @[self.getNextFindResult(self.selection.last)]

proc addPrevFindResultToSelection*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selections = self.selections & @[self.getPrevFindResult(self.selection.first)]

proc setAllFindResultToSelection*(self: TextDocumentEditor) {.expose("editor.text").} =
  var selections: seq[Selection] = @[]
  for searchResults in self.searchResults.values:
    for s in searchResults:
      selections.add s
  self.selections = selections

proc clearSelections*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selections.len > 1:
    self.selection = self.selection
  else:
    self.selection = self.selection.last.toSelection

proc moveCursorColumn*(self: TextDocumentEditor, distance: int, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorColumn, distance, all)
  self.updateTargetColumn(cursor)

proc moveCursorLine*(self: TextDocumentEditor, distance: int, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLine, distance, all)

proc moveCursorHome*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorHome, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorEnd*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorEnd, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorTo*(self: TextDocumentEditor, str: string, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  proc doMoveCursorTo(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
    let line = self.document.getLine cursor.line
    result = cursor
    let index = line.find(str, cursor.column + 1)
    if index >= 0:
      result = (cursor.line, index)
  self.moveCursor(cursor, doMoveCursorTo, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorBefore*(self: TextDocumentEditor, str: string, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  proc doMoveCursorBefore(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
    let line = self.document.getLine cursor.line
    result = cursor
    let index = line.find(str, cursor.column)
    if index > 0:
      result = (cursor.line, index - 1)

  self.moveCursor(cursor, doMoveCursorBefore, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorNextFindResult*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorNextFindResult, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorPrevFindResult*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorPrevFindResult, 0, all)
  self.updateTargetColumn(cursor)

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.scrollToCursor(self.getCursor(cursor))

proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.centerCursor(self.getCursor(cursor))

proc reloadTreesitter*(self: TextDocumentEditor) {.expose("editor.text").} =
  logger.log(lvlInfo, "reloadTreesitter")

  asyncCheck self.document.initTreesitter()
  self.platform.requestRender()

proc deleteLeft*(self: TextDocumentEditor) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (self.doMoveCursorColumn(selection.first, -1), selection.first)
  self.selections = self.document.delete(selections, self.selections)
  self.updateTargetColumn(Last)

proc deleteRight*(self: TextDocumentEditor) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (selection.first, self.doMoveCursorColumn(selection.first, 1))
  self.selections = self.document.delete(selections, self.selections)
  self.updateTargetColumn(Last)

proc getCommandCount*(self: TextDocumentEditor): int {.expose("editor.text").} =
  return self.commandCount

proc setCommandCount*(self: TextDocumentEditor, count: int) {.expose("editor.text").} =
  self.commandCount = count

proc setCommandCountRestore*(self: TextDocumentEditor, count: int) {.expose("editor.text").} =
  self.commandCountRestore = count

proc updateCommandCount*(self: TextDocumentEditor, digit: int) {.expose("editor.text").} =
  self.commandCount = self.commandCount * 10 + digit

proc setFlag*(self: TextDocumentEditor, name: string, value: bool) {.expose("editor.text").} =
  self.configProvider.setFlag("editor.text." & name, value)
  self.markDirty()

proc getFlag*(self: TextDocumentEditor, name: string): bool {.expose("editor.text").} =
  return self.configProvider.getFlag("editor.text." & name, false)

proc runAction*(self: TextDocumentEditor, action: string, args: JsonNode): bool {.expose("editor.text").} =
  # echo "runAction ", action, ", ", $args
  return self.handleActionInternal(action, args) == Handled

func charCategory(c: char): int =
  if c.isAlphaNumeric or c == '_': return 0
  if c == ' ' or c == '\t': return 1
  return 2

proc findWordBoundary*(self: TextDocumentEditor, cursor: Cursor): Selection {.expose("editor.text").} =
  let line = self.document.getLine cursor.line
  result = cursor.toSelection
  if result.first.column == line.len:
    dec result.first.column
    dec result.last.column

  # Search to the left
  while result.first.column > 0 and result.first.column < line.len:
    let leftCategory = line[result.first.column - 1].charCategory
    let rightCategory = line[result.first.column].charCategory
    if leftCategory != rightCategory:
      break
    result.first.column -= 1

  # Search to the right
  if result.last.column < line.len:
    result.last.column += 1
  while result.last.column >= 0 and result.last.column < line.len:
    let leftCategory = line[result.last.column - 1].charCategory
    let rightCategory = line[result.last.column].charCategory
    if leftCategory != rightCategory:
      break
    result.last.column += 1

proc getSelectionInPair*(self: TextDocumentEditor, cursor: Cursor, delimiter: char): Selection {.expose("editor.text").} =
  result = cursor.toSelection
  # todo

proc getSelectionInPairNested*(self: TextDocumentEditor, cursor: Cursor, open: char, close: char): Selection {.expose("editor.text").} =
  result = cursor.toSelection
  # todo

proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string, count: int = 0): Selection {.expose("editor.text").} =
  case move
  of "word":
    result = self.findWordBoundary(cursor)
    for _ in 1..<count:
      result = result or self.findWordBoundary(result.last) or self.findWordBoundary(result.first)

  of "word-line":
    let line = self.document.getLine cursor.line
    result = self.findWordBoundary(cursor)
    if cursor.column == 0 and cursor.line > 0:
      result.first = (cursor.line - 1, self.document.getLine(cursor.line - 1).len)
    if cursor.column == line.len and cursor.line < self.document.lines.len - 1:
      result.last = (cursor.line + 1, 0)

    for _ in 1..<count:
      result = result or self.findWordBoundary(result.last) or self.findWordBoundary(result.first)
      let line = self.document.getLine result.last.line
      if result.first.column == 0 and result.first.line > 0:
        result.first = (result.first.line - 1, self.document.getLine(result.first.line - 1).len)
      if result.last.column == line.len and result.last.line < self.document.lines.len - 1:
        result.last = (result.last.line + 1, 0)

  of "word-back":
    return self.getSelectionForMove((cursor.line, max(0, cursor.column - 1)), "word", count).reverse

  of "word-line-back":
    return self.getSelectionForMove((cursor.line, max(0, cursor.column - 1)), "word-line", count).reverse

  of "line":
    result = ((cursor.line, 0), (cursor.line, self.document.getLine(cursor.line).len))

  of "line-next":
    result = ((cursor.line, 0), (cursor.line, self.document.getLine(cursor.line).len))
    if result.last.line + 1 < self.document.lines.len:
      result.last = (result.last.line + 1, 0)
    for _ in 1..<count:
      result = result or ((result.last.line, 0), (result.last.line, self.document.getLine(result.last.line).len))
      if result.last.line + 1 < self.document.lines.len:
        result.last = (result.last.line + 1, 0)

  of "line-no-indent":
    let indent = self.document.getIndentForLine(cursor.line)
    result = ((cursor.line, indent), (cursor.line, self.document.getLine(cursor.line).len))

  of "file":
    result.first = (0, 0)
    let line = self.document.lines.len - 1
    result.last = (line, self.document.getLine(line).len)

  of "prev-find-result":
    result = self.getPrevFindResult(cursor, count)

  of "next-find-result":
    result = self.getNextFindResult(cursor, count)

  of "\"":
    result = self.getSelectionInPair(cursor, '"')

  of "'":
    result = self.getSelectionInPair(cursor, '\'')

  of "(", ")":
    result = self.getSelectionInPairNested(cursor, '(', ')')

  of "{", "}":
    result = self.getSelectionInPairNested(cursor, '{', '}')

  of "[", "]":
    result = self.getSelectionInPairNested(cursor, '[', ']')

  else:
    if move.startsWith("move-to "):
      let str = move[8..^1]
      let line = self.document.getLine cursor.line
      result = cursor.toSelection
      let index = line.find(str, cursor.column)
      if index >= 0:
        result.last = (cursor.line, index + 1)
      for _ in 1..<count:
        let index = line.find(str, result.last.column)
        if index >= 0:
          result.last = (result.last.line, index + 1)

    elif move.startsWith("move-before "):
      let str = move[12..^1]
      let line = self.document.getLine cursor.line
      result = cursor.toSelection
      let index = line.find(str, cursor.column + 1)
      if index >= 0:
        result.last = (cursor.line, index)
      for _ in 1..<count:
        let index = line.find(str, result.last.column + 1)
        if index >= 0:
          result.last = (result.last.line, index)
    else:
      result = cursor.toSelection
      logger.log(lvlError, fmt"[error] Unknown move '{move}'")

proc mapAllOrLast[T](self: seq[T], all: bool, p: proc(v: T): T): seq[T] =
  if all:
    result = self.map (s) => p(s)
  else:
    result = self
    if result.len > 0:
      result[result.high] = p(result[result.high])

proc cursor(self: TextDocumentEditor, selection: Selection, which: SelectionCursor): Cursor =
  case which
  of Config:
    return self.cursor(selection, self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both))
  of Both:
    return selection.last
  of First:
    return selection.first
  of Last, LastToFirst:
    return selection.last

proc applyMove*(self: TextDocumentEditor, args {.varargs.}: JsonNode) {.expose("editor.text").} =
  self.configProvider.setValue("text.move-count", self.getCommandCount)
  self.setMode self.configProvider.getValue("text.move-next-mode", "")
  self.setCommandCount self.configProvider.getValue("text.move-command-count", 0)
  discard self.runAction(self.configProvider.getValue("text.move-action", ""), args)
  self.configProvider.setValue("text.move-action", "")

proc deleteMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  # echo fmt"delete-move {move}, {which}, {count}, {inside}"

  let selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (s.last, self.getSelectionForMove(s.last, move, count).last))

  self.selections = self.document.delete(selections, self.selections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc selectMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  self.selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (s.last, self.getSelectionForMove(s.last, move, count).last))

  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc copyMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.selectMove(move, inside, which, all)
  self.copy()
  self.selections = self.selections.mapIt(it.first.toSelection)

proc changeMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  let selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (s.last, self.getSelectionForMove(s.last, move, count).last))

  self.selections = self.document.delete(selections, self.selections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc moveLast*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true, count: int = 0) {.expose("editor.text").} =
  case which
  of Config:
    self.selections = self.selections.mapAllOrLast(all,
      (s) => self.getSelectionForMove(self.cursor(s, which), move, count).last.toSelection(s, self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both))
    )
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(self.cursor(s, which), move, count).last.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc moveFirst*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true, count: int = 0) {.expose("editor.text").} =
  case which
  of Config:
    self.selections = self.selections.mapAllOrLast(all,
      (s) => self.getSelectionForMove(self.cursor(s, which), move, count).first.toSelection(s, self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both))
    )
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(self.cursor(s, which), move, count).first.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc setSearchQuery*(self: TextDocumentEditor, query: string) {.expose("editor.text").} =
  self.searchQuery = query
  self.searchRegex = re(query).some
  self.updateSearchResults()

proc setSearchQueryFromMove*(self: TextDocumentEditor, move: string, count: int = 0) {.expose("editor.text").} =
  let selection = self.getSelectionForMove(self.selection.last, move, count)
  self.selection = selection
  self.setSearchQuery(self.document.contentString(selection))

proc toggleLineComment*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selections = self.document.toggleLineComment(self.selections)

proc gotoDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let definition = await ls.getDefinition(self.document.filename, self.selection.last)
    if definition.getSome(d):
      let relativePath = if self.document.workspace.getSome(workspace):
        await workspace.getRelativePath(d.filename)
      else:
        string.none

      let path = relativePath.get(self.document.filename)

      if path != self.document.filename:
        let editor: Option[DocumentEditor] = if self.document.workspace.getSome(workspace):
          self.app.openWorkspaceFile(path, workspace)
        else:
          self.app.openFile(path)

        if editor.getSome(editor) and editor of TextDocumentEditor:
          let textEditor = editor.TextDocumentEditor
          textEditor.targetSelection = d.location.toSelection
          textEditor.scrollToCursor()

      else:
        self.selection = d.location.toSelection
        self.scrollToCursor()

proc getCompletionSelectionAt(self: TextDocumentEditor, cursor: Cursor): Selection =
  let line = self.document.getLine cursor.line

  var column = cursor.column
  while column > 0:
    case line[column - 1]
    of ' ', '\t', '.', ',', '(', ')', '[', ']', '{', '}', ':', ';':
      break
    else:
      column -= 1

  return ((cursor.line, column), cursor)

proc getCompletionsFromContent(self: TextDocumentEditor): seq[TextCompletion] =
  var s = initHashSet[string]()
  for li, line in self.lastRenderedLines:
    for i, part in line.parts:
      if part.text.len > 50 or part.text.isEmptyOrWhitespace:
        continue
      var use = false
      for c in part.text:
        if c.isAlphaAscii or c == '_' or c == '@' or c == '$' or c == '#':
          use = true
          break
      if not use:
        continue
      s.incl part.text

  for text in s.items:
    result.add(TextCompletion(name: text, scope: "document"))

proc splitIdentifier(str: string): seq[string] =
  var buffer = ""
  for i, c in str:
    if c == '_':
      if buffer.len > 0:
        result.add buffer.toLowerAscii
        buffer.setLen 0
      continue

    if c.isUpperAscii:
      if buffer.len > 0:
        result.add buffer.toLowerAscii
        buffer.setLen 0

    buffer.add c

  if buffer.len > 0:
    result.add buffer

proc refilterCompletions(self: TextDocumentEditor) =
  var matches: seq[(TextCompletion, float)]
  var noMatches: seq[(TextCompletion, float)]

  let selection = self.getCompletionSelectionAt(self.selection.last)
  let currentText = self.document.contentString(selection)

  if currentText.len == 0:
    self.completions.sort((a, b) => cmp(a.name, b.name), Ascending)
    return

  let parts = currentText.splitIdentifier
  assert parts.len > 0

  for c in self.completions:
    var score = 0.0
    for i in 0..parts.high:
      score += matchFuzzySimple(c.name, parts[i])

    if c.name.toLower.startsWith(parts[0]):
      matches.add (c, score)
    else:
      noMatches.add (c, score)

  matches.sort((a, b) => cmp(a[1], b[1]), Descending)
  noMatches.sort((a, b) => cmp(a[1], b[1]), Descending)

  for i in 0..matches.high:
    self.completions[i] = matches[i][0]
  for i in 0..noMatches.high:
    self.completions[i + matches.len] = noMatches[i][0]


proc getCompletionsAsync(self: TextDocumentEditor): Future[void] {.async.} =
  if self.disableCompletions:
    return

  self.showCompletionWindow()

  if self.updateCompletionsTask.isNotNil:
    self.updateCompletionsTask.pause()

  let languageServer = await self.document.getLanguageServer()

  if languageServer.getSome(ls):
    if self.completions.len == 0:
      self.completions = self.getCompletionsFromContent()
    self.completions = await ls.getCompletions(self.document.languageId, self.document.filename, self.selection.last)

  if self.completions.len == 0:
    self.completions = self.getCompletionsFromContent()

  self.refilterCompletions()

  self.selectedCompletion = self.selectedCompletion.clamp(0, self.completions.high)
  self.markDirty()

proc showCompletionWindow(self: TextDocumentEditor) =
  if self.updateCompletionsTask.isNil:
    self.updateCompletionsTask = startDelayed(200, repeat=false):
      asyncCheck self.getCompletionsAsync()

  if not self.updateCompletionsTask.isActive:
    self.updateCompletionsTask.reschedule()

  self.showCompletions = true
  self.markDirty()

proc openSymbolsPopup(self: TextDocumentEditor, symbols: seq[Symbol]) =
  let selections = self.selections
  self.app.openSymbolsPopup(symbols,
    handleItemSelected=(proc(symbol: Symbol) =
      self.noSelectionHistory:
        self.targetSelection = symbol.location.toSelection
        self.scrollToCursor()
    ),
    handleItemConfirmed=(proc(symbol: Symbol) =
      self.targetSelection = symbol.location.toSelection
      self.scrollToCursor()
    ),
    handleCanceled=(proc() =
      self.selections = selections
      self.scrollToCursor()
    ),
  )

proc gotoSymbolAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()

  if languageServer.getSome(ls):
    let symbols = await ls.getSymbols(self.document.filename)
    if symbols.len == 0:
      return

    self.openSymbolsPopup(symbols)

  self.markDirty()

proc gotoDefinition*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoDefinitionAsync()

proc getCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.getCompletionsAsync()

proc gotoSymbol*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoSymbolAsync()

proc hideCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.showCompletions = false
  if self.updateCompletionsTask.isNotNil:
    self.updateCompletionsTask.pause()

  self.markDirty()

proc selectPrevCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completions.len > 0:
    self.selectedCompletion = (self.selectedCompletion - 1).clamp(0, self.completions.len - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc selectNextCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completions.len > 0:
    self.selectedCompletion = (self.selectedCompletion + 1).clamp(0, self.completions.len - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc applySelectedCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if not self.showCompletions:
    return

  if self.selectedCompletion > self.completions.high:
    return

  let com = self.completions[self.selectedCompletion]
  logger.log(lvlInfo, fmt"Applying completion {com}")

  let cursor = self.selection.last
  if cursor.column == 0:
    self.selections = self.document.insert([cursor.toSelection], self.selections, [com.name], true, true)
  else:
    let selection = self.getCompletionSelectionAt(cursor)
    self.selections = self.document.edit([selection], self.selections, [com.name])

  self.hideCompletions()

proc isRunningSavedCommands*(self: TextDocumentEditor): bool {.expose("editor.text").} = self.bIsRunningSavedCommands

proc runSavedCommands*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.bIsRunningSavedCommands:
    return
  self.bIsRunningSavedCommands = true
  defer:
    self.bIsRunningSavedCommands = false

  var commandHistory = self.savedCommandHistory
  for command in commandHistory.commands.mitems:

    if not command.isInput and command.command == "run-saved-commands" or command.command == "runSavedCommands":
      continue

    if command.isInput:
      discard self.handleInput(command.command)
    else:
      discard self.handleActionInternal(command.command, command.args)

  self.savedCommandHistory = commandHistory

proc clearCurrentCommandHistory*(self: TextDocumentEditor, retainLast: bool = false) {.expose("editor.text").} =
  if retainLast and self.currentCommandHistory.commands.len > 0:
    let last = self.currentCommandHistory.commands[self.currentCommandHistory.commands.high]
    self.currentCommandHistory.commands.setLen 0
    self.currentCommandHistory.commands.add last
  else:
    self.currentCommandHistory.commands.setLen 0

proc saveCurrentCommandHistory*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.savedCommandHistory = self.currentCommandHistory
  self.currentCommandHistory.commands.setLen 0

genDispatcher("editor.text")

proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse =
  # echo "[textedit] handleAction ", action, " '", arg, "'"
  if self.app.handleUnknownDocumentEditorAction(self, action, args) == Handled:
    dec self.commandCount
    while self.commandCount > 0:
      if self.app.handleUnknownDocumentEditorAction(self, action, args) != Handled:
        break
      dec self.commandCount
    self.commandCount = self.commandCountRestore
    self.commandCountRestore = 0
    return Handled

  var args = args.copy
  args.elems.insert api.TextDocumentEditor(id: self.id).toJson, 0
  if dispatch(action, args).isSome:
    dec self.commandCount
    while self.commandCount > 0:
      if dispatch(action, args).isNone:
        break
      dec self.commandCount
    self.commandCount = self.commandCountRestore
    self.commandCountRestore = 0
    return Handled

  return Ignored

proc handleAction(self: TextDocumentEditor, action: string, arg: string): EventResponse =
  # debugf "handleAction {action}, {arg}"
  var args = newJArray()
  try:
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    if not self.isRunningSavedCommands:
      self.currentCommandHistory.commands.add Command(command: action, args: args)

    return self.handleActionInternal(action, args)
  except CatchableError:
    logger.log(lvlError, fmt"[editor.text] handleAction: {action}, Failed to parse args: '{arg}'")
    return Failed

proc handleInput(self: TextDocumentEditor, input: string): EventResponse =
  if not self.isRunningSavedCommands:
    self.currentCommandHistory.commands.add Command(isInput: true, command: input)

  # echo "handleInput '", input, "'"
  if self.app.invokeCallback(self.getContextWithMode("editor.text.input-handler"), input.newJString):
    return Handled

  self.insertText(input)
  return Handled

method injectDependencies*(self: TextDocumentEditor, app: AppInterface) =
  self.app = app
  self.platform = app.platform
  self.app.registerEditor(self)
  let config = app.getEventHandlerConfig("editor.text")
  self.eventHandler = eventHandler(config):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

  self.completionEventHandler = eventHandler(app.getEventHandlerConfig("editor.text.completion")):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

proc handleTextDocumentTextChanged(self: TextDocumentEditor) =
  self.clampSelection()
  self.updateSearchResults()

  if self.showCompletions and self.updateCompletionsTask.isNotNil:
    self.updateCompletionsTask.reschedule()

  if self.showCompletions:
    self.refilterCompletions()

  self.markDirty()

proc handleTextDocumentLoaded(self: TextDocumentEditor) =
  if self.targetSelectionsInternal.getSome(s):
    self.selections = s
    self.scrollToCursor()
  self.targetSelectionsInternal = Selections.none

## Only use this to create TextDocumentEditorInstances
proc createTextEditorInstance(): TextDocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, selectionsInternal: @[(0, 0).toSelection])
  when defined(js):
    {.emit: [editor, " = jsCreateWithPrototype(editor_text_prototype, ", editor, ");"].}
    # This " is here to fix syntax highlighting
  editor.cursorVisible = true
  editor.blinkCursor = true
  return editor

proc newTextEditor*(document: TextDocument, app: AppInterface, configProvider: ConfigProvider): TextDocumentEditor =
  var self = createTextEditorInstance()
  self.configProvider = configProvider
  self.document = document

  self.init()
  if self.document.lines.len == 0:
    self.document.lines = @[""]
  self.injectDependencies(app)
  discard document.textChanged.subscribe (_: TextDocument) => self.handleTextDocumentTextChanged()
  discard document.onLoaded.subscribe (_: TextDocument) => self.handleTextDocumentLoaded()

  self.startBlinkCursorTask()

  return self

method getDocument*(self: TextDocumentEditor): Document = self.document

method createWithDocument*(_: TextDocumentEditor, document: Document, configProvider: ConfigProvider): DocumentEditor =
  var self = createTextEditorInstance()
  self.document = document.TextDocument
  self.configProvider = configProvider

  self.init()
  if self.document.lines.len == 0:
    self.document.lines = @[""]
  discard self.document.textChanged.subscribe (_: TextDocument) => self.handleTextDocumentTextChanged()
  discard self.document.onLoaded.subscribe (_: TextDocument) => self.handleTextDocumentLoaded()

  self.startBlinkCursorTask()

  return self

proc getCursorAtPixelPos(self: TextDocumentEditor, mousePosWindow: Vec2): Option[Cursor] =
  let mousePosContent = mousePosWindow - self.lastContentBounds.xy
  for li, line in self.lastRenderedLines:
    var startOffset = 0
    for i, part in line.parts:
      if part.bounds.contains(mousePosContent) or (i == line.parts.high and mousePosContent.y >= part.bounds.y and mousePosContent.y <= part.bounds.yh and mousePosContent.x >= part.bounds.x):
        var offsetFromLeft = (mousePosContent.x - part.bounds.x) / self.platform.charWidth
        if self.isThickCursor():
          offsetFromLeft -= 0.0
        else:
          offsetFromLeft += 0.5

        let index = clamp(offsetFromLeft.int, 0, part.text.len)
        return (line.index, startOffset + index).some
      startOffset += part.text.len
  return Cursor.none

method handleMousePress*(self: TextDocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) =
  if self.showCompletions and self.lastCompletionsWidget.isNotNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
    if button == MouseButton.Left or button == MouseButton.Middle:
      self.selectedCompletion = self.getHoveredCompletion(mousePosWindow)
      self.markDirty()
    return

  if button == MouseButton.Left and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    if Alt in modifiers:
      self.selections = self.selections & cursor.toSelection
    else:
      self.selection = cursor.toSelection

    if Control in modifiers:
      self.gotoDefinition()

  if button == MouseButton.DoubleClick and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selectInside(cursor)

  if button == MouseButton.TripleClick and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selectLine(cursor.line)

method handleMouseRelease*(self: TextDocumentEditor, button: MouseButton, mousePosWindow: Vec2) =
  if button == MouseButton.Left and self.showCompletions and self.lastCompletionsWidget.isNotNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
    let oldSelectedCompletion = self.selectedCompletion
    self.selectedCompletion = self.getHoveredCompletion(mousePosWindow)
    if self.selectedCompletion == oldSelectedCompletion:
      self.applySelectedCompletion()
      self.markDirty()

  # if self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
  #   self.selection = cursor.toSelection(self.selection, Last)
  discard

method handleMouseMove*(self: TextDocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  if self.showCompletions and self.lastCompletionsWidget.isNotNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
    if MouseButton.Middle in buttons:
      self.selectedCompletion = self.getHoveredCompletion(mousePosWindow)
      self.markDirty()
    return

  if MouseButton.Left in buttons and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selection = cursor.toSelection(self.selection, Last)
    self.scrollToCursor()


method unregister*(self: TextDocumentEditor) =
  self.app.unregisterEditor(self)