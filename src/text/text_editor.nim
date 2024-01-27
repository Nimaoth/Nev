import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables, deques, sets, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, rect_utils, event, custom_logger, custom_async, fuzzy_matching, custom_unicode, delayed_task, myjsonutils, regex]
import scripting/[expose]
import platform/[platform, filesystem]
import language/[language_server_base]
import workspaces/[workspace]
import document, document_editor, events, vmath, bumpy, input, custom_treesitter, indent, text_document
import config_provider, app_interface

export text_document, document_editor, id

logCategory "texted"
createJavascriptPrototype("editor.text")

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

  cursorsId*: Id
  completionsId*: Id
  lastCursorLocationBounds*: Option[Rect]

  configProvider: ConfigProvider

  selectionsInternal: Selections
  targetSelectionsInternal: Option[Selections] # The selections we want to have once the document is loaded
  selectionHistory: Deque[Selections]
  dontRecordSelectionHistory: bool

  searchQuery*: string
  searchRegex*: Option[Regex]
  searchResults*: Table[int, seq[Selection]]

  styledTextOverrides: Table[int, seq[tuple[cursor: Cursor, text: string, scope: string]]]

  targetColumn: int
  hideCursorWhenInactive*: bool
  cursorVisible*: bool = true
  blinkCursor: bool = true
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
  lastTextAreaBounds*: Rect
  lastPressedMouseButton*: MouseButton
  dragStartSelection*: Selection

  completionWidgetId*: Id
  disableCompletions*: bool
  completions*: seq[TextCompletion]
  selectedCompletion*: int
  completionsBaseIndex*: int
  completionsScrollOffset*: float
  lastItems*: seq[tuple[index: int, bounds: Rect]]
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
proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse
proc handleInput(self: TextDocumentEditor, input: string): EventResponse
proc showCompletionWindow(self: TextDocumentEditor)
proc refilterCompletions(self: TextDocumentEditor)
proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string, count: int = 0): Selection
proc extendSelectionWithMove*(self: TextDocumentEditor, selection: Selection, move: string, count: int = 0): Selection
proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor)

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
  self.updateTargetColumn(Last)

proc clampSelection*(self: TextDocumentEditor) =
  self.selections = self.clampAndMergeSelections(self.selectionsInternal)
  self.markDirty()

func useInclusiveSelections*(self: TextDocumentEditor): bool = self.configProvider.getValue("editor.text.inclusive-selection", false)

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
  log lvlInfo, fmt"shutting down {self.document.filename}"
  self.document.destroy()

# proc `=destroy`[T: object](doc: var TextDocument) =
#   doc.tsParser.tsParserDelete()

method canEdit*(self: TextDocumentEditor, document: Document): bool =
  if document of TextDocument: return true
  else: return false

method getEventHandlers*(self: TextDocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] =
  result = @[self.eventHandler]
  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler

  if inject.contains("above-mode"):
    result.add inject["above-mode"]

  if self.showCompletions:
    result.add self.completionEventHandler

  if inject.contains("above-completion"):
    result.add inject["above-completion"]

proc updateSearchResults(self: TextDocumentEditor) =
  if self.searchRegex.isNone:
    self.searchResults.clear()
    self.markDirty()
    return

  for i, line in self.document.lines:
    let selections = self.document.lines[i].findAllBounds(i, self.searchRegex.get)

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
  return (cursor.line, self.document.lastValidIndex cursor.line)

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0): Selection
proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0): Selection

proc doMoveCursorPrevFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return self.getPrevFindResult(cursor, offset).first

proc doMoveCursorNextFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return self.getNextFindResult(cursor, offset).first

proc doMoveCursorLineCenter(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return (cursor.line, self.document.lineLength(cursor.line) div 2)

proc doMoveCursorCenter(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  if self.lastRenderedLines.len == 0:
    return cursor

  let line = clamp(self.lastRenderedLines[self.lastRenderedLines.high div 2].index + offset, 0, self.document.lines.high)
  return (line, self.targetColumn)

proc centerCursor*(self: TextDocumentEditor, cursor: Cursor) =
  if self.disableScrolling:
    return

  self.previousBaseIndex = cursor.line
  self.scrollOffset = self.lastContentBounds.h * 0.5 - self.platform.totalLineHeight * 0.5

  self.markDirty()

proc scrollToCursor*(self: TextDocumentEditor, cursor: Cursor, margin: Option[float] = float.none, allowCenter = true) =
  if self.disableScrolling:
    return

  let targetLine = cursor.line
  let totalLineHeight = self.platform.totalLineHeight

  let targetLineY = (targetLine - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

  let configMarginRelative = self.configProvider.getValue("text.cursor-margin-relative", true)
  let configMargin = self.configProvider.getValue("text.cursor-margin", 0.2)
  let margin = if margin.getSome(margin):
    clamp(margin, 0.0, self.lastContentBounds.h * 0.5 - totalLineHeight * 0.5)
  elif configMarginRelative:
    clamp(configMargin, 0.0, 1.0) * 0.5 * self.lastContentBounds.h
  else:
    clamp(configMargin, 0.0, self.lastContentBounds.h * 0.5 - totalLineHeight * 0.5)

  if allowCenter and targetLineY < 0:
    self.centerCursor(cursor)
  elif targetLineY < margin:
    self.scrollOffset = margin
    self.previousBaseIndex = targetLine
  elif allowCenter and targetLineY + totalLineHeight > self.lastContentBounds.h:
    self.centerCursor(cursor)
  elif targetLineY + totalLineHeight > self.lastContentBounds.h - margin:
    self.scrollOffset = self.lastContentBounds.h - margin - totalLineHeight
    self.previousBaseIndex = targetLine

  self.markDirty()

proc getContextWithMode*(self: TextDocumentEditor, context: string): string

proc isThickCursor*(self: TextDocumentEditor): bool =
  if not self.platform.supportsThinCursor:
    return true
  return self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.wide"), false)

proc getCursor(self: TextDocumentEditor, selection: Selection, which: SelectionCursor): Cursor =
  case which
  of Config:
    let configCursor = self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    return self.getCursor(selection, configCursor)
  of Both, Last, LastToFirst:
    return selection.last
  of First:
    return selection.first

proc getCursor(self: TextDocumentEditor, which: SelectionCursor): Cursor =
  return self.getCursor(self.selection, which)

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
  # todo
  # for item in self.lastCompletionWidgets:
  #   if item.widget.lastBounds.contains(mousePosWindow):
  #     return item.index

  return 0

method handleScroll*(self: TextDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  if self.disableScrolling:
    return

  let scrollAmount = scroll.y * self.configProvider.getValue("text.scroll-speed", 40.0)
  # todo
  # if not self.lastCompletionsWidget.isNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
  #   self.completionsScrollOffset += scrollAmount
  # else:
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

proc lineCount(self: TextDocumentEditor): int {.expose: "editor.text".} =
  return self.document.lines.len

proc lineLength(self: TextDocumentEditor, line: int): int {.expose: "editor.text".} =
  return self.document.lineLength(line)

proc screenLineCount(self: TextDocumentEditor): int {.expose: "editor.text".} =
  ## Returns the number of lines that can be shown on the screen
  ## This value depends on the size of the view this editor is in and the font size
  return (self.lastContentBounds.h / self.platform.totalLineHeight).int

proc doMoveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor {.expose: "editor.text".} =
  var cursor = cursor
  var column = cursor.column

  template currentLine: openArray[char] = self.document.lines[cursor.line].toOpenArray

  if offset > 0:
    for i in 0..<offset:
      if column == currentLine.len:
        if cursor.line < self.document.lines.high:
          cursor.line = cursor.line + 1
          cursor.column = 0
          continue
        else:
          cursor.column = currentLine.len
          break

      cursor.column = currentLine.nextRuneStart(cursor.column)

  elif offset < 0:
    for i in 0..<(-offset):
      if column == 0:
        if cursor.line > 0:
          cursor.line = cursor.line - 1
          cursor.column = currentLine.len
          continue
        else:
          cursor.column = 0
          break

      cursor.column = currentLine.runeStart(cursor.column - 1)

  return self.clampCursor cursor

proc findSurroundStart*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char, depth: int = 1): Option[Cursor] {.expose: "editor.text".} =
  var depth = depth
  var res = cursor

  while res.line >= 0:
    let line = editor.document.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column >= 0:
      let c = line[res.column]
      # echo &"findSurroundStart: {res} -> {depth}, '{c}'"
      if c == c1 and (depth < 1 or c0 != c1):
        inc depth
        if depth == 0:
          return res.some
      elif c == c0:
        dec depth
        if depth == 0:
          return res.some
      dec res.column

    if res.line == 0:
      return Cursor.none

    res = (res.line - 1, editor.lineLength(res.line - 1) - 1)

  return Cursor.none

proc findSurroundEnd*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char, depth: int = 1): Option[Cursor] {.expose: "editor.text".} =
  let lineCount = editor.lineCount
  var depth = depth
  var res = cursor

  while res.line < lineCount:
    let line = editor.document.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column < line.len:
      let c = line[res.column]
      # echo &"findSurroundEnd: {res} -> {depth}, '{c}'"
      if c == c0 and (depth < 1 or c0 != c1):
        inc depth
        if depth == 0:
          return res.some
      elif c == c1:
        dec depth
        if depth == 0:
          return res.some
      inc res.column

    if res.line == lineCount - 1:
      return Cursor.none

    res = (res.line + 1, 0)

  return Cursor.none

proc setMode*(self: TextDocumentEditor, mode: string) {.expose("editor.text").} =
  ## Sets the current mode of the editor. If `mode` is "", then no additional scope will be pushed on the scope stac.k
  ## If mode is e.g. "insert", then the scope "editor.text.insert" will be pushed on the scope stack above "editor.text"
  ## Don't use "completion", as that is used for when a completion window is open.
  if mode == "completion":
    log(lvlError, fmt"Can't set mode to '{mode}'")
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

proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor) {.expose("editor.text").} =
  self.targetColumn = self.getCursor(cursor).column

proc invertSelection(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Inverts the current selection. Discards all but the last cursor.
  self.selection = (self.selection.last, self.selection.first)

proc insert(self: TextDocumentEditor, selections: seq[Selection], text: string, notify: bool = true, record: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.insert(selections, self.selections, [text], notify, record)

proc delete(self: TextDocumentEditor, selections: seq[Selection], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] {.expose("editor.text").} =
  return self.document.delete(selections, self.selections, notify, record, inclusiveEnd=inclusiveEnd)

proc selectPrev(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popLast
    self.selectionHistory.addFirst self.selections
    self.selectionsInternal = selection
    self.cursorVisible = true
    if self.blinkCursorTask.isNotNil and self.active:
      self.blinkCursorTask.reschedule()
  self.scrollToCursor(self.selection.last)

proc selectNext(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popFirst
    self.selectionHistory.addLast self.selections
    self.selectionsInternal = selection
    self.cursorVisible = true
    if self.blinkCursorTask.isNotNil and self.active:
      self.blinkCursorTask.reschedule()
  self.scrollToCursor(self.selection.last)

proc selectInside*(self: TextDocumentEditor, cursor: Cursor) {.expose("editor.text").} =
  self.selection = self.getSelectionForMove(cursor, "word")
  # todo
  # let regex = re("[a-zA-Z0-9_]")
  # var first = cursor.column
  # # echo self.document.lines[cursor.line], ", ", first, ", ", self.document.lines[cursor.line].matchLen(regex, start = first - 1)
  # while first > 0 and self.document.lines[cursor.line].matchLen(regex, start = first - 1) == 1:
  #   first -= 1
  # var last = cursor.column
  # while last < self.document.lines[cursor.line].len and self.document.lines[cursor.line].matchLen(regex, start = last) == 1:
  #   last += 1
  # self.selection = ((cursor.line, first), (cursor.line, last))

proc selectInsideCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selection = self.extendSelectionWithMove(self.selection, "word")

proc selectLine*(self: TextDocumentEditor, line: int) {.expose("editor.text").} =
  self.selection = ((line, 0), (line, self.document.lastValidIndex(line)))

proc selectLineCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  let first = ((self.selection.first.line, 0), (self.selection.first.line, self.document.lastValidIndex(self.selection.first.line)))
  let last = ((self.selection.last.line, 0), (self.selection.last.line, self.document.lastValidIndex(self.selection.last.line)))
  let wasBackwards = self.selection.isBackwards
  self.selection = first or last
  if wasBackwards:
    self.selection = self.selection.reverse

proc selectParentTs(self: TextDocumentEditor, selection: Selection) {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    return

  let tree = self.document.tsTree

  let selectionRange = selection.tsRange
  var node = self.document.tsTree.root.descendantForRange(selectionRange)
  while node.getRange == selectionRange and node != tree.root:
    node = node.parent

  self.selection = node.getRange.toSelection

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
  discard self.document.delete(indentSelections.normalized, self.selections, inclusiveEnd=self.useInclusiveSelections)

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

proc copyAsync*(self: TextDocumentEditor, register: string, inclusiveEnd: bool): Future[void] {.async.} =
  var text = ""
  for i, selection in self.selections:
    if i > 0:
      text.add "\n"
    text.add self.document.contentString(selection, inclusiveEnd)

  self.app.setRegisterText(text, register).await

proc copy*(self: TextDocumentEditor, register: string = "", inclusiveEnd: bool = false) {.expose("editor.text").} =
  asyncCheck self.copyAsync(register, inclusiveEnd)

proc pasteAsync*(self: TextDocumentEditor, register: string): Future[void] {.async.} =
  let text = self.app.getRegisterText(register).await

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

proc paste*(self: TextDocumentEditor, register: string = "") {.expose("editor.text").} =
  asyncCheck self.pasteAsync(register)

proc scrollText(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.scrollOffset += amount
  self.markDirty()

proc scrollLines(self: TextDocumentEditor, amount: int) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.previousBaseIndex += amount
  while self.previousBaseIndex <= 0:
    self.previousBaseIndex.inc
    self.scrollOffset += self.platform.totalLineHeight
  while self.previousBaseIndex >= self.screenLineCount - 1:
    self.previousBaseIndex.dec
    self.scrollOffset -= self.platform.totalLineHeight
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

proc moveCursorLineCenter*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLineCenter, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorCenter*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorCenter, 0, all)

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.scrollToCursor(self.getCursor(cursor))

proc setCursorScrollOffset*(self: TextDocumentEditor, offset: float, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  let line = self.getCursor(cursor).line
  self.previousBaseIndex = line
  self.scrollOffset = offset
  self.markDirty()

proc getContentBounds*(self: TextDocumentEditor): Vec2 {.expose("editor.text").} =
  return self.lastContentBounds.wh

proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.centerCursor(self.getCursor(cursor))

proc reloadTreesitter*(self: TextDocumentEditor) {.expose("editor.text").} =
  log(lvlInfo, "reloadTreesitter")

  asyncCheck self.document.initTreesitter()
  self.platform.requestRender()

proc deleteLeft*(self: TextDocumentEditor) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (self.doMoveCursorColumn(selection.first, -1), selection.first)
  self.selections = self.document.delete(selections, self.selections, inclusiveEnd=self.useInclusiveSelections)
  self.updateTargetColumn(Last)

proc deleteRight*(self: TextDocumentEditor) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (selection.first, self.doMoveCursorColumn(selection.first, 1))
  self.selections = self.document.delete(selections, self.selections, inclusiveEnd=self.useInclusiveSelections)
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
  if c in Whitespace: return 1
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

proc extendSelectionWithMove*(self: TextDocumentEditor, selection: Selection, move: string, count: int = 0): Selection {.expose("editor.text").} =
  result = self.getSelectionForMove(selection.first, move, count) or self.getSelectionForMove(selection.last, move, count)
  if selection.isBackwards:
    result = result.reverse

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
      result.first = (cursor.line - 1, self.document.lineLength(cursor.line - 1))
    if cursor.column == line.len and cursor.line < self.document.lines.len - 1:
      result.last = (cursor.line + 1, 0)

    for _ in 1..<count:
      result = result or self.findWordBoundary(result.last) or self.findWordBoundary(result.first)
      let line = self.document.getLine result.last.line
      if result.first.column == 0 and result.first.line > 0:
        result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))
      if result.last.column == line.len and result.last.line < self.document.lines.len - 1:
        result.last = (result.last.line + 1, 0)

  of "word-back":
    return self.getSelectionForMove((cursor.line, max(0, cursor.column - 1)), "word", count).reverse

  of "word-line-back":
    return self.getSelectionForMove((cursor.line, max(0, cursor.column - 1)), "word-line", count).reverse

  of "line-back":
    let first = if cursor.line > 0 and cursor.column == 0:
      (cursor.line - 1, self.document.lineLength(cursor.line - 1))
    else:
      (cursor.line, 0)
    result = (first, (cursor.line, self.document.lineLength(cursor.line)))

  of "line":
    result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))

  of "line-next":
    result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))
    if result.last.line + 1 < self.document.lines.len:
      result.last = (result.last.line + 1, 0)
    for _ in 1..<count:
      result = result or ((result.last.line, 0), (result.last.line, self.document.lineLength(result.last.line)))
      if result.last.line + 1 < self.document.lines.len:
        result.last = (result.last.line + 1, 0)

  of "line-prev":
    result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))
    if result.first.line > 0:
      result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))
    for _ in 1..<count:
      result = result or ((result.first.line, 0), result.first)
      if result.first.line > 0:
        result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))

  of "line-no-indent":
    let indent = self.document.getIndentForLine(cursor.line)
    result = ((cursor.line, indent), (cursor.line, self.document.lineLength(cursor.line)))

  of "file":
    result.first = (0, 0)
    let line = self.document.lines.len - 1
    result.last = (line, self.document.lineLength(line))

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

      let cursorJson = self.app.invokeAnyCallback("editor.text.custom-move", %*{
        "editor": self.id,
        "move": move,
        "cursor": cursor.toJson,
        "count": count,
      })

      result = cursorJson.jsonTo(Selection).catch:
        log(lvlError, fmt"Failed to parse selection from custom move '{move}': {cursorJson}")
        return cursor.toSelection

      return result

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
  let command = self.configProvider.getValue("text.move-action", "")
  discard self.runAction(command, args)
  self.configProvider.setValue("text.move-action", "")

proc deleteMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  ## Deletes text based on the current selections.
  ##
  ## `move` specifies which move should be applied to each selection.
  let count = self.configProvider.getValue("text.move-count", 0)

  # echo fmt"delete-move {move}, {which}, {count}, {inside}"

  let selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.selections = self.document.delete(selections, self.selections, inclusiveEnd=self.useInclusiveSelections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc selectMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  self.selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc extendSelectMove*(self: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  self.selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.extendSelectionWithMove(s, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (
      self.getCursor(s, which),
      self.getCursor(self.extendSelectionWithMove(s, move, count), which)
    ))

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
    self.selections.mapAllOrLast(all, (s) => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.selections = self.document.delete(selections, self.selections, inclusiveEnd=self.useInclusiveSelections)
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
    let definition = await ls.getDefinition(self.document.fullPath, self.selection.last)
    if definition.getSome(d):
      let (relativePath, isInSameWorkspace) = if self.document.workspace.getSome(workspace):
        if workspace.getRelativePath(d.filename).await.getSome(filePath):
          (filePath.some, true)
        else:
          (d.filename.some, false)
      else:
        (d.filename.some, false)

      debugf"{self.document.filename} found definition in {relativePath}: {d}"
      let path = relativePath.get(self.document.filename)

      if path != self.document.filename:
        let editor: Option[DocumentEditor] = if isInSameWorkspace and self.document.workspace.getSome(workspace):
          self.app.openWorkspaceFile(path, workspace)
        else:
          self.app.openFile(path)

        if editor.getSome(editor) and editor of TextDocumentEditor:
          let textEditor = editor.TextDocumentEditor
          textEditor.targetSelection = d.location.toSelection
          textEditor.scrollToCursor()

      else:
        self.selection = d.location.toSelection
        self.updateTargetColumn(Last)
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

  if result.len == 0:
    result.add str

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
    self.completions = await ls.getCompletions(self.document.languageId, self.document.fullPath, self.selection.last)

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

  log lvlInfo, fmt"showCompletions {self.document.filename}"
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
    let symbols = await ls.getSymbols(self.document.fullPath)
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
  log lvlInfo, fmt"hideCompletions {self.document.filename}"
  self.showCompletions = false
  if self.updateCompletionsTask.isNotNil:
    self.updateCompletionsTask.pause()

  self.markDirty()

proc selectPrevCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completions.len > 0:
    self.selectedCompletion = (self.selectedCompletion - 1 + self.completions.len) mod self.completions.len
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc selectNextCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completions.len > 0:
    self.selectedCompletion = (self.selectedCompletion + 1) mod self.completions.len
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
  log(lvlInfo, fmt"Applying completion {com}")

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

proc getAvailableCursors*(self: TextDocumentEditor): seq[Cursor] =
  let pattern = re"[_a-zA-Z0-9]+"

  for li, line in self.lastRenderedLines:
    for s in self.document.getLine(line.index).findAllBounds(line.index, pattern):
      result.add s.first

    # continue

    # let lineNumber = line.index
    # var column = 0
    # for i, part in line.parts:
    #   defer:
    #     column += part.text.len

    #   if part.text.isEmptyOrWhitespace:
    #     continue

    #   if not part.text.strip().match(pattern, 0):
    #     continue

    #   echo part.text

    #   let offset = part.text.firstNonWhitespace
    #   result.add (lineNumber, column + offset)

  let line = self.selection.last.line
  result.sort proc(a, b: auto): int =
    let lineDistA = abs(a.line - line)
    let lineDistB = abs(b.line - line)
    if lineDistA != lineDistB:
      return cmp(lineDistA, lineDistB)
    return cmp(a.column, b.column)

proc getCombinationsOfLength*(self: TextDocumentEditor, keys: openArray[string], disallowedPairs: HashSet[string], length: int, disallowDoubles: bool): seq[string] =
  if length <= 1:
    return @keys
  for key in keys:
    for next in self.getCombinationsOfLength(keys, disallowedPairs, length - 1, disallowDoubles):
      if (key & next[0]) in disallowedPairs or (next[0] & key) in disallowedPairs:
        continue
      if disallowDoubles and key == next[0..0]:
        continue

      result.add key & next

proc assignKeys*(self: TextDocumentEditor, cursors: openArray[Cursor]): seq[string] =
  let possibleKeys = ["r", "a", "n", "e", "t", "i", "g", "l", "f", "v", "d", "u", "o", "s"]
  let disallowedPairs = ["ao", "io", "rs", "ts", "iv", "al", "ec", "eo", "ns", "nh", "rg", "tf", "ui", "dt", "sd", "ou", "uv", "df"].toHashSet
  for length in 1..3:
    if result.len == cursors.len:
      return
    for c in self.getCombinationsOfLength(possibleKeys, disallowedPairs, length, disallowDoubles=true):
      result.add c
      if result.len == cursors.len:
        return

proc setSelection*(self: TextDocumentEditor, cursor: Cursor, nextMode: string) {.expose("editor.text").} =
  self.selection = cursor.toSelection
  self.scrollToCursor()
  self.setMode(nextMode)

proc enterChooseCursorMode*(self: TextDocumentEditor, action: string) {.expose("editor.text").} =
  const mode = "choose-cursor"
  let oldMode = self.currentMode

  let cursors = self.getAvailableCursors()
  let keys = self.assignKeys(cursors)
  var config = EventHandlerConfig(context: "editor.text.choose-cursor", handleActions: true, handleInputs: true, consumeAllActions: true, consumeAllInput: true)

  for i in 0..min(cursors.high, keys.high):
    config.addCommand("", keys[i] & "<SPACE>", action & " " & $cursors[i].toJson & " " & $oldMode.toJson)

  var progress = ""

  proc updateStyledTextOverrides() =
    self.styledTextOverrides.clear()

    var options: seq[Cursor] = @[]
    for i in 0..min(cursors.high, keys.high):
      if not keys[i].startsWith(progress):
        continue

      if not self.styledTextOverrides.contains(cursors[i].line):
        self.styledTextOverrides[cursors[i].line] = @[]

      if progress.len > 0:
        self.styledTextOverrides[cursors[i].line].add (cursors[i], progress, "entity.name.function")

      let cursor = (cursors[i].line, cursors[i].column + progress.len)
      let text = keys[i][progress.len..^1]
      self.styledTextOverrides[cursors[i].line].add (cursor, text, "variable")

      options.add cursors[i]

    if options.len == 1:
      self.styledTextOverrides.clear()
      self.document.notifyTextChanged()
      self.markDirty()
      discard self.handleAction(action, ($options[0].toJson & " " & $oldMode.toJson))

    self.document.notifyTextChanged()
    self.markDirty()

  updateStyledTextOverrides()

  config.addCommand("", "<ESCAPE>", "setMode \"\"")

  self.modeEventHandler = eventHandler(config):
    onAction:
      self.styledTextOverrides.clear()
      self.document.notifyTextChanged()
      self.markDirty()
      self.handleAction action, arg
    onInput:
      self.handleInput input
    onProgress:
      progress.add inputToString(input)
      updateStyledTextOverrides()

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  self.currentMode = mode

  self.app.handleModeChanged(self, oldMode, self.currentMode)

  self.markDirty()

genDispatcher("editor.text")
# addGlobalDispatchTable "editor.text", genDispatchTable("editor.text")

proc getStyledText*(self: TextDocumentEditor, i: int): StyledLine =
  result = self.document.getStyledText(i)

  let chars = (self.lastTextAreaBounds.w / self.platform.charWidth - 2).RuneCount
  if chars > 0.RuneCount:
    var i = 0
    while i < result.parts.len:
      if result.parts[i].text.runeLen > chars:
        splitPartAt(result, i, chars.RuneIndex)
      inc i

  if self.styledTextOverrides.contains(i):
    result.overrideStyle(0.RuneIndex, result.runeLen.RuneIndex, "", -1)

    for override in self.styledTextOverrides[i]:
      self.document.splitAt(result, override.cursor.column)
      self.document.splitAt(result, override.cursor.column + override.text.len)
      self.document.overrideStyleAndText(result, override.cursor.column, override.text, override.scope, -2, joinNext = true)

proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse =
  # debugf"[textedit] handleAction {action}, '{args}'"

  var args = args.copy
  args.elems.insert api.TextDocumentEditor(id: self.id).toJson, 0

  if self.app.handleUnknownDocumentEditorAction(self, action, args) == Handled:
    dec self.commandCount
    while self.commandCount > 0:
      if self.app.handleUnknownDocumentEditorAction(self, action, args) != Handled:
        break
      dec self.commandCount
    self.commandCount = self.commandCountRestore
    self.commandCountRestore = 0
    return Handled

  if self.app.invokeAnyCallback(action, args).isNotNil:
    dec self.commandCount
    while self.commandCount > 0:
      if self.app.invokeAnyCallback(action, args).isNil:
        break
      dec self.commandCount
    self.commandCount = self.commandCountRestore
    self.commandCountRestore = 0
    return Handled

  try:
    # debugf"dispatch {action}, {args}"
    if dispatch(action, args).isSome:
      dec self.commandCount
      while self.commandCount > 0:
        if dispatch(action, args).isNone:
          break
        dec self.commandCount
      self.commandCount = self.commandCountRestore
      self.commandCountRestore = 0
      return Handled
  except CatchableError:
    log(lvlError, fmt"Failed to dispatch action '{action} {args}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return Ignored

method handleAction*(self: TextDocumentEditor, action: string, arg: string): EventResponse =
  # debugf "handleAction {action}, '{arg}'"
  var args = newJArray()
  try:
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    if not self.isRunningSavedCommands:
      self.currentCommandHistory.commands.add Command(command: action, args: args)

    return self.handleActionInternal(action, args)
  except CatchableError:
    log(lvlError, fmt"handleAction: {action}, Failed to parse args: '{arg}'")
    return Failed

proc handleInput(self: TextDocumentEditor, input: string): EventResponse =
  if not self.isRunningSavedCommands:
    self.currentCommandHistory.commands.add Command(isInput: true, command: input)

  # echo "handleInput '", input, "'"
  if self.app.invokeCallback(self.getContextWithMode("editor.text.input-handler"), input.newJString):
    return Handled

  self.insertText(input)
  return Handled

proc runSingleClickCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  let commandName = self.configProvider.getValue("editor.text.single-click-command", "")
  let args = self.configProvider.getValue("editor.text.single-click-command-args", newJArray())
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runDoubleClickCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  let commandName = self.configProvider.getValue("editor.text.double-click-command", "extend-select-move")
  let args = self.configProvider.getValue("editor.text.double-click-command-args", %[newJString("word"), newJBool(true)])
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runTripleClickCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  let commandName = self.configProvider.getValue("editor.text.triple-click-command", "extend-select-move")
  let args = self.configProvider.getValue("editor.text.triple-click-command-args", %[newJString("line"), newJBool(true)])
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runDragCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.lastPressedMouseButton == Left:
    self.runSingleClickCommand()
  elif self.lastPressedMouseButton == DoubleClick:
    self.runDoubleClickCommand()
  elif self.lastPressedMouseButton == TripleClick:
    self.runTripleClickCommand()

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
  self.updateTargetColumn(Last)

## Only use this to create TextDocumentEditorInstances
proc createTextEditorInstance(): TextDocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, selectionsInternal: @[(0, 0).toSelection])
  when defined(js):
    {.emit: [editor, " = jsCreateWithPrototype(editor_text_prototype, ", editor, ");"].}
    # This " is here to fix syntax highlighting
  editor.cursorsId = newId()
  editor.completionsId = newId()
  return editor

proc newTextEditor*(document: TextDocument, app: AppInterface, configProvider: ConfigProvider): TextDocumentEditor =
  var self = createTextEditorInstance()
  self.configProvider = configProvider
  self.document = document
  self.completionWidgetId = newId()

  self.init()
  if self.document.lines.len == 0:
    self.document.lines = @[""]
  self.injectDependencies(app)
  discard document.textChanged.subscribe (_: TextDocument) => self.handleTextDocumentTextChanged()
  discard document.onLoaded.subscribe (_: TextDocument) => self.handleTextDocumentLoaded()

  self.startBlinkCursorTask()

  self.setMode(configProvider.getValue("editor.text.default-mode", ""))

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
    var startOffset = 0.RuneIndex
    for i, part in line.parts:
      if part.bounds.contains(mousePosContent) or (i == line.parts.high and mousePosContent.y >= part.bounds.y and mousePosContent.y <= part.bounds.yh and mousePosContent.x >= part.bounds.x):
        var offsetFromLeft = (mousePosContent.x - part.bounds.x) / self.platform.charWidth
        if self.isThickCursor():
          offsetFromLeft -= 0.0
        else:
          offsetFromLeft += 0.5

        let index = clamp(offsetFromLeft.int, 0, part.text.runeLen.int)
        let byteIndex = self.document.lines[line.index].toOpenArray.runeOffset(startOffset + index.RuneCount)
        return (line.index, byteIndex).some
      startOffset += part.text.runeLen
  return Cursor.none

method unregister*(self: TextDocumentEditor) =
  self.app.unregisterEditor(self)

method getStateJson*(self: TextDocumentEditor): JsonNode =
  return %*{
    "selection": self.selection.toJson
  }

method restoreStateJson*(self: TextDocumentEditor, state: JsonNode) =
  if state.kind != JObject:
    return
  if state.hasKey("selection"):
    let selection = state["selection"].jsonTo Selection
    self.targetSelection = selection
    self.scrollToCursor()
    self.markDirty()
