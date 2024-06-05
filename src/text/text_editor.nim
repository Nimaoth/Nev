import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables,
  deques, sets, algorithm, os]
import chroma
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, rect_utils, event, custom_logger, custom_async, fuzzy_matching,
  custom_unicode, delayed_task, myjsonutils, regex, timer, response]
import scripting/[expose]
import platform/[platform, filesystem]
import language/[language_server_base]
import document, document_editor, events, vmath, bumpy, input, custom_treesitter, indent,
  text_document, snippet
import completion, completion_provider_document, completion_provider_lsp,
  completion_provider_snippet, selector_popup_builder, dispatch_tables
import config_provider, app_interface
import diff
import workspaces/workspace
import finder/[previewer, finder]
import vcs/vcs

from language/lsp_types import CompletionList, CompletionItem, InsertTextFormat,
  TextEdit, Range, Position, asTextEdit, asInsertReplaceEdit, toJsonHook

export text_document, document_editor, id

logCategory "texted"
createJavascriptPrototype("editor.text")

let searchResultsId = newId()
let errorNodesHighlightId = newId()

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

  diffDocument*: TextDocument
  diffChanges*: Option[seq[LineMapping]]
  diffRevision: int = 0

  usage*: string # Unique string identifying what the editor is used for,
                 # e.g. command-line/preview/search-bar

  cursorsId*: Id
  completionsId*: Id
  hoverId*: Id
  diagnosticsId*: Id
  lastCursorLocationBounds*: Option[Rect]
  lastHoverLocationBounds*: Option[Rect]
  lastDiagnosticLocationBounds*: Option[Rect]

  configProvider: ConfigProvider

  selectionsInternal: Selections
  targetSelectionsInternal: Option[Selections] # The selections we want to have once
                                               # the document is loaded
  selectionHistory: Deque[Selections]
  dontRecordSelectionHistory: bool

  searchQuery*: string
  searchRegex*: Option[Regex]
  searchResults*: Table[int, seq[Selection]]

  styledTextOverrides: Table[int, seq[tuple[cursor: Cursor, text: string, scope: string]]]

  customHighlights*: Table[int, seq[tuple[id: Id, selection: Selection, color: string, tint: Color]]]

  defaultScrollBehaviour*: ScrollBehaviour = CenterOffscreen
  nextScrollBehaviour*: Option[ScrollBehaviour]
  targetLineMargin*: Option[float]
  targetLine*: Option[int]
  targetColumn: int
  hideCursorWhenInactive*: bool
  cursorVisible*: bool = true
  blinkCursor: bool = true
  blinkCursorTask: DelayedTask

  # hover
  showHoverTask: DelayedTask    # for showing hover info after a delay
  hideHoverTask: DelayedTask    # for hiding hover info after a delay
  currentHoverLocation: Cursor  # the location of the mouse hover
  showHover*: bool              # whether to show hover info in ui
  hoverText*: string            # the text to show in the hover info
  hoverLocation*: Cursor        # where to show the hover info
  hoverScrollOffset*: float     # the scroll offset inside the hover window

  # inline hints
  inlayHints: seq[InlayHint]
  inlayHintsTask: DelayedTask

  # line index to sequence of indices into document.currentDiagnostics
  showDiagnostic*: bool = false
  currentDiagnosticLine*: int
  currentDiagnostic*: Diagnostic

  completionEventHandler: EventHandler
  modeEventHandler: EventHandler
  currentMode*: string
  commandCount*: int
  commandCountRestore*: int
  currentCommandHistory: CommandHistory
  savedCommandHistory: CommandHistory
  bIsRunningSavedCommands: bool
  bRecordCurrentCommand: bool = false
  bIsRecordingCurrentCommand: bool = false

  disableScrolling*: bool
  scrollOffset*: float
  previousBaseIndex*: int
  lineNumbers*: Option[LineNumbers]

  lastRenderedLines*: seq[StyledLine]
  lastTextAreaBounds*: Rect
  lastPressedMouseButton*: MouseButton
  dragStartSelection*: Selection

  completionMatchPositions*: Table[int, seq[int]] # Maps from completion index to char indices
                                                  # of matching chars
  completionMatches*: seq[tuple[index: int, score: float]]
  disableCompletions*: bool
  completions*: seq[Completion]
  selectedCompletion*: int
  completionsBaseIndex*: int
  completionsScrollOffset*: float
  lastItems*: seq[tuple[index: int, bounds: Rect]]
  showCompletions*: bool
  scrollToCompletion*: Option[int]

  completionEngine: CompletionEngine

  updateCompletionsTask: DelayedTask

  currentSnippetData*: Option[SnippetData]

  textChangedHandle: Id
  loadedHandle: Id
  savedHandle: Id
  textInsertedHandle: Id
  textDeletedHandle: Id
  diagnosticsUpdatedHandle: Id
  languageServerAttachedHandle: Id
  onCompletionsUpdatedHandle: Id

  completionsDirty: bool
  searchResultsDirty: bool

var allTextEditors*: seq[TextDocumentEditor] = @[]

method getStatisticsString*(self: TextDocumentEditor): string =
  result.add &"Filename: {self.document.filename}\n"
  result.add &"Selection History: {self.selectionHistory.len}\n"
  result.add &"Search Query: {self.searchQuery}\n"
  result.add &"Search Results: {self.searchResults.len}\n"
  result.add &"Styled Text Overrides: {self.styledTextOverrides.len}\n"
  result.add &"Custom Highlights: {self.customHighlights.len}\n"
  result.add &"Inlay Hints: {self.inlayHints.len}\n"
  result.add &"Current Command History: {self.currentCommandHistory.commands.len}\n"
  result.add &"Saved Command History: {self.savedCommandHistory.commands.len}\n"
  result.add &"Last Rendered Lines: {self.lastRenderedLines.len}\n"

  var temp = 0
  for s in self.completionMatchPositions.values:
    temp += s.len
  result.add &"Completion Match Positions: {self.completionMatchPositions.len}, {temp}\n"
  result.add &"Completion Matches: {self.completionMatches.len}\n"

  result.add &"Completions: {self.completions.len}\n"
  result.add &"LastItems: {self.lastItems.len}"

template noSelectionHistory(self, body: untyped): untyped =
  block:
    let temp = self.dontRecordSelectionHistory
    self.dontRecordSelectionHistory = true
    defer:
      self.dontRecordSelectionHistory = temp
    body

proc newTextEditor*(document: TextDocument, app: AppInterface, configProvider: ConfigProvider
  ): TextDocumentEditor
proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse
proc handleInput(self: TextDocumentEditor, input: string, record: bool): EventResponse
proc showCompletionWindow(self: TextDocumentEditor)
proc refilterCompletions(self: TextDocumentEditor)
proc hideCompletions*(self: TextDocumentEditor)
proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string,
  count: int = 0): Selection
proc extendSelectionWithMove*(self: TextDocumentEditor, selection: Selection, move: string,
  count: int = 0): Selection
proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor = Last)
proc updateInlayHints*(self: TextDocumentEditor)
proc updateDiagnosticsForCurrent*(self: TextDocumentEditor)
proc visibleTextRange*(self: TextDocumentEditor, buffer: int = 0): Selection
proc addCustomHighlight*(self: TextDocumentEditor, id: Id, selection: Selection, color: string,
  tint: Color = color(1, 1, 1))
proc clearCustomHighlights*(self: TextDocumentEditor, id: Id)
proc updateSearchResults(self: TextDocumentEditor)
proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config)
proc centerCursor*(self: TextDocumentEditor, cursor: Cursor)

proc handleTextInserted(self: TextDocumentEditor, document: TextDocument, location: Selection,
    text: string)
proc handleTextDeleted(self: TextDocumentEditor, document: TextDocument, selection: Selection)
proc handleDiagnosticsUpdated(self: TextDocumentEditor)
proc handleLanguageServerAttached(self: TextDocumentEditor, document: TextDocument,
    languageServer: LanguageServer)
proc handleTextDocumentTextChanged(self: TextDocumentEditor)
proc handleTextDocumentLoaded(self: TextDocumentEditor)
proc handleTextDocumentSaved(self: TextDocumentEditor)
proc handleCompletionsUpdated(self: TextDocumentEditor)

proc clampCursor*(self: TextDocumentEditor, cursor: Cursor, includeAfter: bool = true): Cursor =
  self.document.clampCursor(cursor, includeAfter)

proc clampSelection*(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true
    ): Selection =
  self.document.clampSelection(selection, includeAfter)

proc clampAndMergeSelections*(self: TextDocumentEditor, selections: openArray[Selection]): Selections =
  self.document.clampAndMergeSelections(selections)

proc selections*(self: TextDocumentEditor): Selections =
  self.selectionsInternal

proc selection*(self: TextDocumentEditor): Selection =
  self.selectionsInternal[self.selectionsInternal.high]

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

  self.showHover = false
  self.completionsDirty = true
  self.hideCompletions()
  # self.document.addNextCheckpoint("move")

  self.updateDiagnosticsForCurrent()

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

  self.showHover = false
  self.completionsDirty = true
  self.hideCompletions()
  # self.document.addNextCheckpoint("move")

  self.updateDiagnosticsForCurrent()

  self.markDirty()

proc `targetSelection=`*(self: TextDocumentEditor, selection: Selection) =
  self.targetSelectionsInternal = @[selection].some
  self.selection = selection
  self.updateTargetColumn(Last)

proc clampSelection*(self: TextDocumentEditor) =
  self.selections = self.clampAndMergeSelections(self.selectionsInternal)
  self.markDirty()

func useInclusiveSelections*(self: TextDocumentEditor): bool =
  self.configProvider.getValue("editor.text.inclusive-selection", false)

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

proc clearDocument*(self: TextDocumentEditor) =
  if self.document.isNotNil:
    log lvlInfo, &"[clearDocument] ({self.id}): '{self.document.filename}'"
    self.document.textChanged.unsubscribe(self.textChangedHandle)
    self.document.onLoaded.unsubscribe(self.loadedHandle)
    self.document.onSaved.unsubscribe(self.savedHandle)
    self.document.textInserted.unsubscribe(self.textInsertedHandle)
    self.document.textDeleted.unsubscribe(self.textDeletedHandle)
    self.document.onDiagnosticsUpdated.unsubscribe(self.diagnosticsUpdatedHandle)
    self.document.onLanguageServerAttached.unsubscribe(self.languageServerAttachedHandle)

    self.selectionHistory.clear()
    self.styledTextOverrides.clear()
    self.customHighlights.clear()
    self.showHover = false
    self.inlayHints.setLen 0
    self.showDiagnostic = false
    self.scrollOffset = 0
    self.previousBaseIndex = 0
    self.lastRenderedLines.setLen 0
    self.currentSnippetData = SnippetData.none

  self.document = nil

proc setDocument*(self: TextDocumentEditor, document: TextDocument) =
  assert document.isNotNil

  if document == self.document:
    return

  logScope lvlInfo, &"[setDocument] ({self.id}): '{document.filename}'"

  if self.completionEngine.isNotNil:
    self.completionEngine.onCompletionsUpdated.unsubscribe(self.onCompletionsUpdatedHandle)

  self.clearDocument()
  self.document = document

  if self.document.lines.len == 0:
    self.document.lines = @[""]

  self.textChangedHandle = document.textChanged.subscribe (_: TextDocument) =>
    self.handleTextDocumentTextChanged()

  self.loadedHandle = document.onLoaded.subscribe (_: TextDocument) => (block:
      if self.isNil or self.document.isNil:
        return
      self.handleTextDocumentLoaded()
  )

  self.savedHandle = document.onSaved.subscribe () =>
    self.handleTextDocumentSaved()

  self.textInsertedHandle = document.textInserted.subscribe (
      arg: tuple[document: TextDocument, location: Selection, text: string]) =>
    self.handleTextInserted(arg.document, arg.location, arg.text)

  self.textDeletedHandle = document.textDeleted.subscribe (
      arg: tuple[document: TextDocument, location: Selection]) =>
    self.handleTextDeleted(arg.document, arg.location)

  self.diagnosticsUpdatedHandle = document.onDiagnosticsUpdated.subscribe () =>
    self.handleDiagnosticsUpdated()

  self.languageServerAttachedHandle = document.onLanguageServerAttached.subscribe (
      arg: tuple[document: TextDocument, languageServer: LanguageServer]) =>
    self.handleLanguageServerAttached(arg.document, arg.languageServer)

  self.completionEngine = CompletionEngine()
  self.onCompletionsUpdatedHandle = self.completionEngine.onCompletionsUpdated.subscribe () =>
    self.handleCompletionsUpdated()

  if self.document.languageServer.getSome(ls):
    self.handleLanguageServerAttached(self.document, ls)

  if self.document.createLanguageServer:
    self.completionEngine.addProvider newCompletionProviderSnippet(self.configProvider, self.document)
      .withMergeStrategy(MergeStrategy(kind: TakeAll))
      .withPriority(1)
    self.completionEngine.addProvider newCompletionProviderDocument(self.document)
      .withMergeStrategy(MergeStrategy(kind: FillN, max: 20))
      .withPriority(0)

  self.handleDocumentChanged()

method deinit*(self: TextDocumentEditor) =
  let filename = if self.document.isNotNil: self.document.filename else: ""
  logScope lvlInfo, fmt"[deinit] Destroying text editor ({self.id}) for '{filename}'"

  self.unregister()

  if self.diffDocument.isNotNil:
    self.diffDocument.deinit()
    self.diffDocument = nil

  self.clearDocument()

  if self.blinkCursorTask.isNotNil: self.blinkCursorTask.pause()
  if self.updateCompletionsTask.isNotNil: self.updateCompletionsTask.pause()
  if self.inlayHintsTask.isNotNil: self.inlayHintsTask.pause()
  if self.showHoverTask.isNotNil: self.showHoverTask.pause()
  if self.hideHoverTask.isNotNil: self.hideHoverTask.pause()

  if self.completionEngine.isNotNil:
    self.completionEngine.onCompletionsUpdated.unsubscribe(self.onCompletionsUpdatedHandle)

  let i = allTextEditors.find(self)
  allTextEditors.removeSwap(i)

  self[] = default(typeof(self[]))

# proc `=destroy`[T: object](doc: var TextDocument) =
#   doc.tsParser.tsParserDelete()

method getNamespace*(self: TextDocumentEditor): string = "editor.text"

method canEdit*(self: TextDocumentEditor, document: Document): bool =
  if document of TextDocument: return true
  else: return false

method getEventHandlers*(self: TextDocumentEditor, inject: Table[string, EventHandler]
    ): seq[EventHandler] =
  result = @[self.eventHandler]
  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler

  if inject.contains("above-mode"):
    result.add inject["above-mode"]

  if self.showCompletions:
    result.add self.completionEventHandler

  if inject.contains("above-completion"):
    result.add inject["above-completion"]

proc preRender*(self: TextDocumentEditor) =
  if self.configProvider.isNil or self.document.isNil:
    return

  self.clearCustomHighlights(errorNodesHighlightId)
  if self.configProvider.getValue("editor.text.highlight-treesitter-errors", true):
    let errorNodes = self.document.getErrorNodesInRange(
      self.visibleTextRange(buffer = 10))
    for node in errorNodes:
      self.addCustomHighlight(errorNodesHighlightId, node, "editorError.foreground", color(1, 1, 1, 0.3))

  if self.searchResultsDirty:
    self.updateSearchResults()

  if self.showCompletions and self.completionsDirty:
    measureBlock "refilter completions":
      self.refilterCompletions()

iterator splitSelectionIntoLines(self: TextDocumentEditor, selection: Selection,
    includeAfter: bool = true): Selection =
  ## Yields a selection for each line covered by the input selection, covering the same range as the input
  ## If includeAfter is true then the selections will go until line.len, otherwise line.high

  let selection = selection.normalized
  if selection.first.line == selection.last.line:
    yield selection
  else:
    yield (
      selection.first,
      (selection.first.line, self.document.lastValidIndex(selection.first.line, includeAfter))
    )

    for i in (selection.first.line + 1)..<selection.last.line:
      yield ((i, 0), (i, self.document.lastValidIndex(i, includeAfter)))

    yield ((selection.last.line, 0), selection.last)

proc clearCustomHighlights*(self: TextDocumentEditor, id: Id) =
  ## Removes all custom highlights associated with the given id

  for highlights in self.customHighlights.mvalues:
    for i in countdown(highlights.high, 0):
      if highlights[i].id == id:
        highlights.removeSwap(i)

proc addCustomHighlight*(self: TextDocumentEditor, id: Id, selection: Selection, color: string,
    tint: Color = color(1, 1, 1)) =
  # customHighlights*: Table[int, seq[(Id, Selection, Color)]]
  for lineSelection in self.splitSelectionIntoLines(selection):
    assert lineSelection.first.line == lineSelection.last.line
    if self.customHighlights.contains(selection.first.line):
      self.customHighlights[selection.first.line].add (id, selection, color, tint)
    else:
      self.customHighlights[selection.first.line] = @[(id, selection, color, tint)]

proc updateSearchResults(self: TextDocumentEditor) =
  if not self.searchResultsDirty:
    return

  self.searchResultsDirty = false

  self.clearCustomHighlights(searchResultsId)

  if self.searchRegex.isNone:
    self.searchResults.clear()
    self.markDirty()
    return

  for i, line in self.document.lines:
    let selections = self.document.lines[i].findAllBounds(i, self.searchRegex.get)
    for s in selections:
      self.addCustomHighlight(searchResultsId, s, "editor.findMatchBackground")

    if selections.len > 0:
      self.searchResults[i] = selections
    else:
      self.searchResults.del i
  self.markDirty()

method handleDocumentChanged*(self: TextDocumentEditor) =
  self.selection = (self.clampCursor self.selection.first, self.clampCursor self.selection.last)
  self.searchResultsDirty = true

method handleActivate*(self: TextDocumentEditor) =
  self.startBlinkCursorTask()

method handleDeactivate*(self: TextDocumentEditor) =
  log lvlInfo, fmt"Deactivate '{self.document.filename}'"
  if self.blinkCursorTask.isNotNil:
    self.blinkCursorTask.pause()
    self.cursorVisible = true
    self.markDirty()

  self.document.clearStyledTextCache()
  if self.diffDocument.isNotNil:
    self.diffDocument.clearStyledTextCache()

proc doMoveCursorLine(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool = false, includeAfter: bool = false): Cursor =
  var cursor = cursor
  let line = cursor.line + offset
  if line < 0:
    cursor = (0, cursor.column)
  elif line >= self.document.lines.len:
    cursor = (self.document.lines.len - 1, cursor.column)
  else:
    cursor.line = line
    cursor.column = self.document.visualColumnToCursorColumn(line, self.targetColumn)
  return self.clampCursor(cursor, includeAfter)

proc doMoveCursorHome(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor =
  return (cursor.line, 0)

proc doMoveCursorEnd(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor =
  return (cursor.line, self.document.lastValidIndex cursor.line)

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
  includeAfter: bool = true, wrap: bool = true): Selection
proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
  includeAfter: bool = true, wrap: bool = true): Selection

proc doMoveCursorPrevFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool, includeAfter: bool): Cursor =
  return self.getPrevFindResult(cursor, offset, includeAfter=includeAfter).first

proc doMoveCursorNextFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool, includeAfter: bool): Cursor =
  return self.getNextFindResult(cursor, offset, includeAfter=includeAfter).first

proc doMoveCursorLineCenter(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor =
  return (cursor.line, self.document.lineLength(cursor.line) div 2)

proc doMoveCursorCenter(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor =
  if self.lastRenderedLines.len == 0:
    return cursor

  let r = self.visibleTextRange()
  let line = clamp((r.first.line + r.last.line) div 2, 0, self.document.lines.len - 1)
  let column = self.document.visualColumnToCursorColumn(line, self.targetColumn)
  return (line, column)

proc scrollToTop*(self: TextDocumentEditor) =
  if self.disableScrolling:
    return

  self.targetLine = 0.some
  self.nextScrollBehaviour = TopOfScreen.some
  self.targetLineMargin = float.none

  self.updateInlayHints()
  self.markDirty()

proc centerCursor*(self: TextDocumentEditor, cursor: Cursor) =
  if self.disableScrolling:
    return

  self.targetLine = cursor.line.some
  self.nextScrollBehaviour = CenterAlways.some
  self.targetLineMargin = float.none

  self.updateInlayHints()
  self.markDirty()

proc scrollToCursor*(self: TextDocumentEditor, cursor: Cursor, margin: Option[float] = float.none,
    scrollBehaviour = ScrollBehaviour.none) =
  if self.disableScrolling:
    return

  self.targetLine = cursor.line.some
  self.nextScrollBehaviour = scrollBehaviour
  self.targetLineMargin = margin

  self.updateInlayHints()
  self.markDirty()

proc getContextWithMode*(self: TextDocumentEditor, context: string): string

proc isThickCursor*(self: TextDocumentEditor): bool =
  if not self.platform.supportsThinCursor:
    return true
  return self.configProvider.getValue(self.getContextWithMode("editor.text.cursor.wide"), false)

proc getCursor(self: TextDocumentEditor, selection: Selection, which: SelectionCursor): Cursor =
  case which
  of Config:
    let key = self.getContextWithMode("editor.text.cursor.movement")
    let configCursor = self.configProvider.getValue(key, SelectionCursor.Both)
    return self.getCursor(selection, configCursor)
  of Both, Last, LastToFirst:
    return selection.last
  of First:
    return selection.first

proc getCursor(self: TextDocumentEditor, which: SelectionCursor): Cursor =
  return self.getCursor(self.selection, which)

proc moveCursor(self: TextDocumentEditor, cursor: SelectionCursor,
    movement: proc(doc: TextDocumentEditor, c: Cursor, off: int, wrap: bool, includeAfter: bool): Cursor,
    offset: int, all: bool, wrap: bool = false, includeAfter: bool = false) =
  case cursor
  of Config:
    let key = self.getContextWithMode("editor.text.cursor.movement")
    let configCursor = self.configProvider.getValue(key, SelectionCursor.Both)
    self.moveCursor(configCursor, movement, offset, all, wrap, includeAfter)

  of Both:
    if all:
      self.selections = self.selections.map (s) =>
        movement(self, s.last, offset, wrap, includeAfter).toSelection
    else:
      var selections = self.selections
      selections[selections.high] = movement(self, selections[selections.high].last, offset,
        wrap, includeAfter).toSelection
      self.selections = selections
    self.scrollToCursor(self.selection.last)

  of First:
    if all:
      self.selections = self.selections.map (s) =>
        (movement(self, s.first, offset, wrap, includeAfter), s.last)
    else:
      var selections = self.selections
      selections[selections.high] = (
        movement(self, selections[selections.high].first, offset, wrap, includeAfter),
        selections[selections.high].last
      )
      self.selections = selections
    self.scrollToCursor(self.selection.first)

  of Last:
    if all:
      self.selections = self.selections.map (s) =>
        (s.first, movement(self, s.last, offset, wrap, includeAfter))
    else:
      var selections = self.selections
      selections[selections.high] = (
        selections[selections.high].first,
        movement(self, selections[selections.high].last, offset, wrap, includeAfter)
      )
      self.selections = selections
    self.scrollToCursor(self.selection.last)

  of LastToFirst:
    if all:
      self.selections = self.selections.map (s) =>
        (s.last, movement(self, s.last, offset, wrap, includeAfter))
    else:
      var selections = self.selections
      selections[selections.high] = (
        selections[selections.high].last,
        movement(self, selections[selections.high].last, offset, wrap, includeAfter)
      )
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
  # if not self.lastCompletionsWidget.isNil and
  #     self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
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

proc lineLength*(self: TextDocumentEditor, line: int): int {.expose: "editor.text".} =
  return self.document.lineLength(line)

proc screenLineCount(self: TextDocumentEditor): int {.expose: "editor.text".} =
  ## Returns the number of lines that can be shown on the screen
  ## This value depends on the size of the view this editor is in and the font size
  return (self.lastContentBounds.h / self.platform.totalLineHeight).int

proc visibleTextRange*(self: TextDocumentEditor, buffer: int = 0): Selection =
  assert self.lineCount > 0
  let baseLine = int(self.scrollOffset / self.platform.totalLineHeight)
  result.first.line = clamp(self.previousBaseIndex - baseLine - buffer, 0, self.lineCount - 1)
  result.last.line = clamp(self.previousBaseIndex - baseLine + self.screenLineCount + buffer,
    0, self.lineCount - 1)
  result.last.column = self.document.lastValidIndex(result.last.line)

proc doMoveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool = true, includeAfter: bool = true): Cursor {.expose: "editor.text".} =
  var cursor = cursor
  var column = cursor.column

  template currentLine: openArray[char] = self.document.lines[cursor.line].toOpenArray

  var lastIndex = self.document.lastValidIndex(cursor.line, includeAfter)

  if offset > 0:
    for i in 0..<offset:
      if column >= lastIndex:
        if not wrap:
          break
        if cursor.line < self.document.lines.high:
          cursor.line = cursor.line + 1
          cursor.column = 0
          lastIndex = self.document.lastValidIndex(cursor.line, includeAfter)
          continue
        else:
          cursor.column = lastIndex
          break

      cursor.column = currentLine.nextRuneStart(cursor.column)

  elif offset < 0:
    for i in 0..<(-offset):
      if column == 0:
        if not wrap:
          break
        if cursor.line > 0:
          cursor.line = cursor.line - 1
          lastIndex = self.document.lastValidIndex(cursor.line, includeAfter)
          cursor.column = lastIndex
          continue
        else:
          cursor.column = 0
          break

      cursor.column = currentLine.runeStart(cursor.column - 1)

  return self.clampCursor(cursor, includeAfter)

proc findSurroundStart*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char,
    depth: int = 1): Option[Cursor] {.expose: "editor.text".} =
  var depth = depth
  var res = cursor

  while res.line >= 0:
    let line = editor.document.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column >= 0:
      let c = line[res.column]
      # debugf"findSurroundStart: {res} -> {depth}, '{c}'"
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

proc findSurroundEnd*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char,
    depth: int = 1): Option[Cursor] {.expose: "editor.text".} =
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
  ## Sets the current mode of the editor.
  ## If `mode` is "", then no additional scope will be pushed on the scope stac.k
  ## If mode is e.g. "insert",
  ## then the scope "editor.text.insert" will be pushed on the scope stack above "editor.text"
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
        self.handleAction action, arg, record=true
      onInput:
        self.handleInput input, record=true

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

proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor = Last ) {.
    expose("editor.text").} =
  let cursor = self.getCursor(cursor)
  self.targetColumn = self.document.cursorToVisualColumn(cursor)

proc invertSelection(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Inverts the current selection. Discards all but the last cursor.
  self.selection = (self.selection.last, self.selection.first)

proc getRevision*(self: TextDocumentEditor): int {.expose("editor.text").} =
  return self.document.revision

proc getUsage*(self: TextDocumentEditor): string {.expose("editor.text").} =
  return self.usage

proc getText*(self: TextDocumentEditor, selection: Selection, inclusiveEnd: bool = false):
    string {.expose("editor.text").} =
  return self.document.contentString(selection, inclusiveEnd)

proc insert*(self: TextDocumentEditor, selections: seq[Selection], text: string, notify: bool = true,
    record: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.insert(selections, self.selections, [text], notify, record)

proc delete*(self: TextDocumentEditor, selections: seq[Selection], notify: bool = true,
    record: bool = true, inclusiveEnd: bool = false): seq[Selection] {.expose("editor.text").} =
  return self.document.delete(selections, self.selections, notify, record, inclusiveEnd=inclusiveEnd)

proc edit*(self: TextDocumentEditor, selections: seq[Selection], texts: seq[string],
    notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] {.
    expose("editor.text").} =
  return self.document.edit(selections, self.selections, texts, notify, record,
    inclusiveEnd=inclusiveEnd)

proc deleteLines(self: TextDocumentEditor, slice: Slice[int], oldSelections: Selections) {.
    expose("editor.text").} =
  var selection: Selection = (
    (slice.a.clamp(0, self.lineCount - 1), 0),
    (slice.b.clamp(0, self.lineCount - 1), 0)
  ).normalized
  selection.last.column = self.document.lastValidIndex(selection.last.line)
  if selection.last.line < self.document.lines.high:
    selection.last = (selection.last.line + 1, 0)
  elif selection.first.line > 0:
    selection.first = (selection.first.line - 1, self.document.lastValidIndex(selection.first.line - 1))
  discard self.document.delete([selection], oldSelections)

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
  # # echo self.document.lines[cursor.line], ", ", first, ", ",
  #   self.document.lines[cursor.line].matchLen(regex, start = first - 1)
  # while first > 0 and self.document.lines[cursor.line].matchLen(regex, start = first - 1) == 1:
  #   first -= 1
  # var last = cursor.column
  # while last < self.document.lines[cursor.line].len and
  #   self.document.lines[cursor.line].matchLen(regex, start = last) == 1:
  #   last += 1
  # self.selection = ((cursor.line, first), (cursor.line, last))

proc selectInsideCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selection = self.extendSelectionWithMove(self.selection, "word")

proc selectLine*(self: TextDocumentEditor, line: int) {.expose("editor.text").} =
  self.selection = ((line, 0), (line, self.document.lastValidIndex(line)))

proc selectLineCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  let first = (
    (self.selection.first.line, 0),
    (self.selection.first.line, self.document.lastValidIndex(self.selection.first.line))
  )
  let last = (
    (self.selection.last.line, 0),
    (self.selection.last.line, self.document.lastValidIndex(self.selection.last.line))
  )
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

proc printTreesitterTree*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    log lvlError, "No tree available."
    return

  let tree = self.document.tsTree

  log lvlInfo, $tree.root

proc printTreesitterTreeUnderCursor*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    log lvlError, "No tree available."
    return

  let selectionRange = self.selection.tsRange
  let node = self.document.tsTree.root.descendantForRange(selectionRange)

  log lvlInfo, $node

proc selectParentCurrentTs*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selectParentTs(self.selection)

proc shouldShowCompletionsAt*(self: TextDocumentEditor, cursor: Cursor): bool {.expose("editor.text").} =
  ## Returns true if the completion window should automatically open at the given position
  let line = self.document.getLine(cursor.line)
  if cursor.column <= 0 or cursor.column > line.len:
    return false

  let previousRune = line.runeAt(line.runeStart(cursor.column - 1))
  let triggerChars = IdentChars + {'.'}
  if previousRune.char in triggerChars:
    return true

  if previousRune.isAlpha:
    return true

  return false

proc autoShowCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.shouldShowCompletionsAt(self.selection.last):
    self.showCompletionWindow()
  else:
    self.hideCompletions()

proc insertText*(self: TextDocumentEditor, text: string, autoIndent: bool = true) {.
    expose("editor.text").} =
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

    elif autoIndent:
      texts.setLen(selections.len)
      for i, selection in selections:
        let line = self.document.lines[selection.last.line]
        let indent = indentForNewLine(self.document.languageConfig, line, self.document.indentStyle,
          self.document.tabWidth, selection.last.column)
        texts[i] = "\n" & indent

  elif autoIndent and (text == "}" or text == ")" or text == "]"):
    # Adjust indent of closing paren by searching for the matching opening paren
    let (open, close) = case text[0]
      of ')': ('(', ')')
      of '}': ('{', '}')
      of ']': ('[', ']')
      else:
        assert false
        return

    texts.setLen(0)
    for s in selections.mitems:
      let openLocation = self.findSurroundStart((s.first.line, s.first.column - 1),
          0, open, close, 1).getOr:
        texts.add text
        continue

      if openLocation.line == s.first.line:
        # Closing paren is on same line as opening paren, don't apply auto indent
        texts.add text
        continue

      let closeIndent = self.document.lines[s.first.line].firstNonWhitespace
      if closeIndent != s.first.column:
        # Closing paren is not at beginning of line, don't apply auto indent
        texts.add text
        continue

      let openIndent = self.document.lines[openLocation.line].firstNonWhitespace
      if openIndent == closeIndent:
        # Indent is already correct, just insert the paren
        texts.add text
        continue

      # Copy indent of opening parens line
      let indent = self.document.lines[openLocation.line][0..<openIndent]
      texts.add indent & text
      s.first.column = 0

  selections = self.document.edit(selections, selections, texts).mapIt(it.last.toSelection)

  if allWhitespace:
    for i in 0..min(self.selections.high, originalSelections.high):
      selections[i].first.column = originalSelections[i].first.column
      selections[i].last.column = originalSelections[i].last.column

  self.selections = selections

  self.updateTargetColumn(Last)

  if not self.disableCompletions:
    self.autoShowCompletions()

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
    case self.document.indentStyle.kind
    of Spaces:
      let firstNonWhitespace = self.document.lines[l].firstNonWhitespace
      indentSelections.add ((l, 0), (l, min(self.document.indentStyle.indentColumns, firstNonWhitespace)))
    of Tabs:
      indentSelections.add ((l, 0), (l, 1))

  var selections = self.selections
  discard self.document.delete(indentSelections.normalized, self.selections)

  for s in selections.mitems:
    if s.first.line in linesToIndent:
      s.first.column = max(0, s.first.column - self.document.indentStyle.indentColumns)
    if s.last.line in linesToIndent:
      s.last.column = max(0, s.last.column - self.document.indentStyle.indentColumns)
  self.selections = selections

proc insertIndent*(self: TextDocumentEditor) {.expose("editor.text").} =
  var insertTexts = newSeq[string]()

  # todo: for spaces, calculate alignment
  let indent = self.document.indentStyle.getString()
  for selection in self.selections:
    insertTexts.add indent

  self.selections = self.document.edit(self.selections, self.selections, insertTexts).mapIt(
    it.last.toSelection)

proc undo*(self: TextDocumentEditor, checkpoint: string = "word") {.expose("editor.text").} =
  if self.document.undo(self.selections, true, checkpoint).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)

proc redo*(self: TextDocumentEditor, checkpoint: string = "word") {.expose("editor.text").} =
  if self.document.redo(self.selections, true, checkpoint).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)

proc addNextCheckpoint*(self: TextDocumentEditor, checkpoint: string) {.expose("editor.text").} =
  self.document.addNextCheckpoint checkpoint

proc printUndoHistory*(self: TextDocumentEditor, max: int = 50) {.expose("editor.text").} =
  for i in countup(0, self.document.redoOps.high):
    debugf"redo: {self.document.redoOps[i]}"
  debugf"-----"
  for i in countdown(self.document.undoOps.high, 0):
    debugf"undo: {self.document.undoOps[i]}"

proc copyAsync*(self: TextDocumentEditor, register: string, inclusiveEnd: bool): Future[void] {.async.} =
  log lvlInfo, fmt"copy register into '{register}', inclusiveEnd: {inclusiveEnd}"
  var text = ""
  for i, selection in self.selections:
    if i > 0:
      text.add "\n"
    text.add self.document.contentString(selection, inclusiveEnd)

  self.app.setRegisterTextAsync(text, register).await

proc copy*(self: TextDocumentEditor, register: string = "", inclusiveEnd: bool = false) {.
    expose("editor.text").} =
  asyncCheck self.copyAsync(register, inclusiveEnd)

proc pasteAsync*(self: TextDocumentEditor, register: string, inclusiveEnd: bool = false):
    Future[void] {.async.} =
  log lvlInfo, fmt"paste register from '{register}', inclusiveEnd: {inclusiveEnd}"
  let text = self.app.getRegisterTextAsync(register).await

  let numLines = text.count('\n') + 1

  let newSelections = if numLines == self.selections.len:
    let lines = text.splitLines()
    self.document.edit(self.selections, self.selections, lines, notify=true, record=true,
      inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
  else:
    self.document.edit(self.selections, self.selections, [text], notify=true, record=true,
      inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)

  # add list of selections for what was just pasted to history
  if newSelections.len == self.selections.len:
    var tempSelections = newSelections
    for i in 0..tempSelections.high:
      tempSelections[i].first = self.selections[i].first
    self.selections = tempSelections

  self.selections = newSelections
  self.scrollToCursor(Last)
  self.markDirty()

proc paste*(self: TextDocumentEditor, register: string = "", inclusiveEnd: bool = false) {.
    expose("editor.text").} =
  asyncCheck self.pasteAsync(register, inclusiveEnd)

proc scrollText*(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.scrollOffset += amount
  self.updateInlayHints()
  self.markDirty()

proc scrollLines(self: TextDocumentEditor, amount: int) {.expose("editor.text").} =
  ## Scroll the text up (positive) or down (negative) by the given number of lines

  if self.disableScrolling:
    return

  self.previousBaseIndex += amount

  while self.previousBaseIndex <= 0:
    self.previousBaseIndex.inc
    self.scrollOffset += self.platform.totalLineHeight

  while self.previousBaseIndex >= self.document.lines.len - 1:
    self.previousBaseIndex.dec
    self.scrollOffset -= self.platform.totalLineHeight

  self.updateInlayHints()
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

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
    includeAfter: bool = true, wrap: bool = true): Selection {.expose("editor.text").} =
  self.updateSearchResults()

  var i = 0
  for line in countdown(cursor.line, 0):
    if self.searchResults.contains(line):
      let selections = self.searchResults[line]
      for k in countdown(selections.high, 0):
        if selections[k].last < cursor:
          if i == offset:
            if includeAfter:
              return selections[k]
            else:
              return (selections[k].first, self.doMoveCursorColumn(selections[k].last, -1, wrap = false))
          inc i

  let nextSearchStart = (self.lineCount, 0)
  if cursor != nextSearchStart:
    let wrapped = self.getPrevFindResult(nextSearchStart, offset - i,
      includeAfter=includeAfter, wrap=wrap)
    if not wrapped.isEmpty:
      return wrapped
  return cursor.toSelection

proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
    includeAfter: bool = true, wrap: bool = true): Selection {.expose("editor.text").} =
  self.updateSearchResults()

  var i = 0
  for line in cursor.line..self.document.lines.high:
    if self.searchResults.contains(line):
      for selection in self.searchResults[line]:
        if cursor < selection.first:
          if i == offset:
            if includeAfter:
              return selection
            else:
              return (selection.first, self.doMoveCursorColumn(selection.last, -1, wrap = false))
          inc i

  if cursor != (0, 0):
    let wrapped = self.getNextFindResult((0, 0), offset - i, includeAfter=includeAfter, wrap=wrap)
    if not wrapped.isEmpty:
      return wrapped
  return cursor.toSelection

proc getPrevDiagnostic*(self: TextDocumentEditor, cursor: Cursor, severity: int = 0,
    offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection {.expose("editor.text").} =
  var i = 0
  for line in countdown(cursor.line, 0):
    if self.document.diagnosticsPerLine.contains(line):
      let diagnosticsOnCurrentLine {.cursor.} = self.document.diagnosticsPerLine[line]
      for k in countdown(diagnosticsOnCurrentLine.high, 0):
        let diagnosticIndex = diagnosticsOnCurrentLine[k]
        if diagnosticIndex > self.document.currentDiagnostics.high:
          continue

        let diagnostic {.cursor.} = self.document.currentDiagnostics[diagnosticIndex]
        if diagnostic.removed:
          continue

        if severity != 0 and diagnostic.severity.getSome(s) and s.ord != severity:
          continue

        let selection = diagnostic.selection

        if selection.last < cursor:
          if i == offset:
            if includeAfter:
              return selection
            else:
              return (selection.first, self.doMoveCursorColumn(selection.last, -1, wrap = false))
          inc i

  let nextSearchStart = (self.lineCount, 0)
  if cursor != nextSearchStart:
    let wrapped = self.getPrevDiagnostic(nextSearchStart, severity, offset - i,
      includeAfter=includeAfter, wrap=wrap)
    if not wrapped.isEmpty:
      return wrapped
  return cursor.toSelection

proc getNextDiagnostic*(self: TextDocumentEditor, cursor: Cursor, severity: int = 0,
    offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection {.expose("editor.text").} =
  var i = 0
  for line in cursor.line..self.document.lines.high:
    if self.document.diagnosticsPerLine.contains(line):
      for diagnosticIndex in self.document.diagnosticsPerLine[line]:
        if diagnosticIndex > self.document.currentDiagnostics.high:
          continue

        let diagnostic {.cursor.} = self.document.currentDiagnostics[diagnosticIndex]
        if diagnostic.removed:
          continue

        if severity != 0 and diagnostic.severity.getSome(s) and s.ord != severity:
          continue

        let selection = diagnostic.selection

        if cursor < selection.first:
          if i == offset:
            if includeAfter:
              return selection
            else:
              return (selection.first, self.doMoveCursorColumn(selection.last, -1, wrap = false))
          inc i

  if cursor != (0, 0):
    let wrapped = self.getNextDiagnostic((0, 0), severity, offset - i,
      includeAfter=includeAfter, wrap=wrap)
    if not wrapped.isEmpty:
      return wrapped
  return cursor.toSelection

proc closeDiff*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.diffDocument.isNil:
    return
  self.diffDocument.deinit()
  self.diffDocument = nil
  self.markDirty()

proc getPrevChange*(self: TextDocumentEditor, cursor: Cursor): Selection {.expose("editor.text").} =
  if self.diffChanges.isNone:
    return cursor.toSelection

  for i in countdown(self.diffChanges.get.high, 0):
    if self.diffChanges.get[i].target.first < cursor.line:
      return (self.diffChanges.get[i].target.first, 0).toSelection

  return cursor.toSelection

proc getNextChange*(self: TextDocumentEditor, cursor: Cursor): Selection {.expose("editor.text").} =
  if self.diffChanges.isNone:
    return cursor.toSelection

  for mapping in self.diffChanges.get:
    if mapping.target.first > cursor.line:
      return (mapping.target.first, 0).toSelection

  return cursor.toSelection

proc updateDiffAsync*(self: TextDocumentEditor, gotoFirstDiff: bool, force: bool = false) {.async.} =
  if self.document.isNil:
    return

  if self.document.workspace.isNone:
    log lvlWarn, &"Can't diff file '{self.document.filename}' without workspace."
    return

  inc self.diffRevision
  let revision = self.diffRevision

  let vcs = self.document.workspace.get.getVcsForFile(self.document.filename).getOr:
    log lvlWarn, fmt"[updateDiffAsync] File is not part of any vcs: '{self.document.filename}'"
    return

  log lvlInfo, fmt"Diff document '{self.document.filename}'"

  let relPath = self.document.workspace.mapIt(
    it.getRelativePath(self.document.filename).await
  ).flatten.get(self.document.filename)
  if self.diffRevision > revision:
    return

  if self.document.staged:
    let committedFileContent = vcs.getCommittedFileContent(relPath).await
    if self.diffRevision > revision:
      return

    let stagedFileContent = vcs.getStagedFileContent(relPath).await
    if self.diffRevision > revision:
      return

    let changes = vcs.getFileChanges(relPath, staged = true).await
    if self.diffRevision > revision:
      return

    if self.diffDocument.isNil:
      self.diffDocument = newTextDocument(self.configProvider,
        language=self.document.languageId.some, createLanguageServer = false)
      self.diffDocument.readOnly = true

    self.document.content = stagedFileContent
    self.diffChanges = changes
    self.diffDocument.content = committedFileContent

  else:
    let stagedFileContent = vcs.getStagedFileContent(relPath).await
    if self.diffRevision > revision:
      return

    let changes = vcs.getFileChanges(relPath, staged = false).await
    if self.diffRevision > revision:
      return

    if self.diffDocument.isNil:
      self.diffDocument = newTextDocument(self.configProvider,
        language=self.document.languageId.some, createLanguageServer = false)
      self.diffDocument.readOnly = true

    self.diffChanges = changes
    self.diffDocument.content = stagedFileContent

  if gotoFirstDiff and self.diffChanges.getSome(changes) and changes.len > 0:
    self.selection = (changes[0].target.first, 0).toSelection
    self.updateTargetColumn(Last)
    self.centerCursor(self.selection.last)

  self.markDirty()

proc updateDiff*(self: TextDocumentEditor, gotoFirstDiff: bool = false) {.expose("editor.text").} =
  asyncCheck self.updateDiffAsync(gotoFirstDiff)

proc checkoutFileAsync*(self: TextDocumentEditor) {.async.} =
  if self.document.isNil:
    return

  if self.document.workspace.isNone:
    return

  let ws = self.document.workspace.get
  let path = self.document.filename
  let vcs = ws.getVcsForFile(path).getOr:
    log lvlError, fmt"No vcs assigned to document '{path}'"
    return

  let res = await vcs.checkoutFile(path)
  log lvlInfo, &"Checkout result: {res}"

  self.document.setReadOnly(ws.isFileReadOnly(path).await)
  self.markDirty()

proc checkoutFile*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.checkoutFileAsync()

proc addNextFindResultToSelection*(self: TextDocumentEditor, includeAfter: bool = true,
    wrap: bool = true) {.expose("editor.text").} =
  self.selections = self.selections &
    @[self.getNextFindResult(self.selection.last, includeAfter=includeAfter)]

proc addPrevFindResultToSelection*(self: TextDocumentEditor, includeAfter: bool = true,
    wrap: bool = true) {.expose("editor.text").} =
  self.selections = self.selections &
    @[self.getPrevFindResult(self.selection.first, includeAfter=includeAfter)]

proc setAllFindResultToSelection*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.updateSearchResults()

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

proc moveCursorColumn*(self: TextDocumentEditor, distance: int,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true,
    includeAfter: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorColumn, distance, all, wrap, includeAfter)
  self.updateTargetColumn(cursor)

proc moveCursorLine*(self: TextDocumentEditor, distance: int,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true,
    includeAfter: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLine, distance, all, wrap, includeAfter)

proc moveCursorHome*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorHome, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorEnd*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true, includeAfter: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorEnd, 0, all, includeAfter=includeAfter)
  self.updateTargetColumn(cursor)

proc moveCursorTo*(self: TextDocumentEditor, str: string,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  proc doMoveCursorTo(self: TextDocumentEditor, cursor: Cursor, offset: int,
      wrap: bool = true, includeAfter: bool = true): Cursor =
    let line = self.document.getLine cursor.line
    result = cursor
    let index = line.find(str, cursor.column + 1)
    if index >= 0:
      result = (cursor.line, index)
  self.moveCursor(cursor, doMoveCursorTo, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorBefore*(self: TextDocumentEditor, str: string,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  proc doMoveCursorBefore(self: TextDocumentEditor, cursor: Cursor, offset: int,
      wrap: bool = true, includeAfter: bool = true): Cursor =
    let line = self.document.getLine cursor.line
    result = cursor
    let index = line.find(str, cursor.column)
    if index > 0:
      result = (cursor.line, index - 1)

  self.moveCursor(cursor, doMoveCursorBefore, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorNextFindResult*(self: TextDocumentEditor,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true) {.
    expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorNextFindResult, 0, all, wrap)
  self.updateTargetColumn(cursor)

proc moveCursorPrevFindResult*(self: TextDocumentEditor,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true) {.
    expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorPrevFindResult, 0, all, wrap)
  self.updateTargetColumn(cursor)

proc moveCursorLineCenter*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLineCenter, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorCenter*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorCenter, 0, all)

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.
    expose("editor.text").} =
  self.scrollToCursor(self.getCursor(cursor))

proc setNextScrollBehaviour*(self: TextDocumentEditor, scrollBehaviour: ScrollBehaviour) {.
    expose("editor.text").} =
  self.nextScrollBehaviour = scrollBehaviour.some

proc setCursorScrollOffset*(self: TextDocumentEditor, offset: float,
    cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  let line = self.getCursor(cursor).line
  self.previousBaseIndex = line
  self.scrollOffset = offset
  self.updateInlayHints()
  self.markDirty()

proc getContentBounds*(self: TextDocumentEditor): Vec2 {.expose("editor.text").} =
  return self.lastContentBounds.wh

proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.
    expose("editor.text").} =
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

  self.selections = self.document.delete(selections, self.selections,
    inclusiveEnd=self.useInclusiveSelections)

  if not self.disableCompletions:
    self.autoShowCompletions()

proc deleteRight*(self: TextDocumentEditor, includeAfter: bool = true) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (selection.first, self.doMoveCursorColumn(selection.first, 1))

  self.selections = self.document.delete(selections, self.selections,
    inclusiveEnd=self.useInclusiveSelections).mapIt(self.clampSelection(it, includeAfter))

  if not self.disableCompletions:
    self.autoShowCompletions()

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

proc runAction*(self: TextDocumentEditor, action: string, args: JsonNode): bool {.
    expose("editor.text").} =
  # echo "runAction ", action, ", ", $args
  return self.handleActionInternal(action, args) == Handled

proc findWordBoundary*(self: TextDocumentEditor, cursor: Cursor): Selection {.expose("editor.text").} =
  self.document.findWordBoundary(cursor)

proc getSelectionInPair*(self: TextDocumentEditor, cursor: Cursor, delimiter: char): Selection {.
    expose("editor.text").} =
  result = cursor.toSelection
  # todo

proc getSelectionInPairNested*(self: TextDocumentEditor, cursor: Cursor, open: char,
    close: char): Selection {.expose("editor.text").} =
  result = cursor.toSelection
  # todo

proc extendSelectionWithMove*(self: TextDocumentEditor, selection: Selection, move: string,
    count: int = 0): Selection {.expose("editor.text").} =
  result = self.getSelectionForMove(selection.first, move, count) or
    self.getSelectionForMove(selection.last, move, count)
  if selection.isBackwards:
    result = result.reverse

proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string,
    count: int = 0): Selection {.expose("editor.text").} =
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
      result = result or (
        (result.last.line, 0),
        (result.last.line, self.document.lineLength(result.last.line))
      )
      if result.last.line + 1 < self.document.lines.len:
        result.last = (result.last.line + 1, 0)

  of "line-prev":
    result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))
    if result.first.line > 0:
      result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))
    for _ in 1..<count:
      result = result or (Cursor (result.first.line, 0), result.first)
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
    let key = self.getContextWithMode("editor.text.cursor.movement")
    let cursorSelector = self.configProvider.getValue(key, SelectionCursor.Both)
    return self.cursor(selection, cursorSelector)
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

proc deleteMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
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

  self.selections = self.document.delete(selections, self.selections,
    inclusiveEnd=self.useInclusiveSelections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc selectMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
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

proc extendSelectMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
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

proc copyMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  self.selectMove(move, inside, which, all)
  self.copy()
  self.selections = self.selections.mapIt(it.first.toSelection)

proc changeMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  let selections = if inside:
    self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.selections = self.document.delete(selections, self.selections,
    inclusiveEnd=self.useInclusiveSelections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc moveLast*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config,
    all: bool = true, count: int = 0) {.expose("editor.text").} =
  case which
  of Config:
    let cursorSelector = self.configProvider.getValue(
      self.getContextWithMode("editor.text.cursor.movement"),
      SelectionCursor.Both
    )
    self.selections = self.selections.mapAllOrLast(all, (s) =>
      self.getSelectionForMove(self.cursor(s, which), move, count).last.toSelection(s, cursorSelector)
    )
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) =>
      self.getSelectionForMove(self.cursor(s, which), move, count).last.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc moveFirst*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config,
    all: bool = true, count: int = 0) {.expose("editor.text").} =
  case which
  of Config:
    let cursorSelector = self.configProvider.getValue(
      self.getContextWithMode("editor.text.cursor.movement"),
      SelectionCursor.Both
    )
    self.selections = self.selections.mapAllOrLast(all, (s) =>
      self.getSelectionForMove(self.cursor(s, which), move, count).first.toSelection(s, cursorSelector)
    )
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) =>
      self.getSelectionForMove(self.cursor(s, which), move, count).first.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc setSearchQuery*(self: TextDocumentEditor, query: string, escapeRegex: bool = false,
    prefix: string = "", suffix: string = "") {.expose("editor.text").} =
  if self.searchQuery == query:
    return

  if query.len == 0:
    return

  try:
    let query = if escapeRegex:
      query.escapeRegex
    else:
      query

    self.searchRegex = re(prefix & query & suffix).some
    self.searchResultsDirty = true
    self.searchQuery = query

  except:
    discard
    # todo: can't log here because the auto generated popCurrentException() raises
    # because currException is nil at the end of this scope when we add some code here
    # Maybe log raises an exception internally?
    # log lvlError, &"[setSearchQuery] Invalid regex query: '{query}', escape: {escapeRegex}"

proc setSearchQueryFromMove*(self: TextDocumentEditor, move: string,
    count: int = 0, prefix: string = "", suffix: string = ""): Selection {.expose("editor.text").} =
  let selection = self.getSelectionForMove(self.selection.last, move, count)
  let searchText = self.document.contentString(selection)
  self.setSearchQuery(searchText, escapeRegex=true, prefix, suffix)
  return selection

proc toggleLineComment*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selections = self.document.toggleLineComment(self.selections)

proc openFileAt(self: TextDocumentEditor, filename: string, location: Option[Selection]) =
  let editor = if self.document.workspace.getSome(workspace):
    self.app.openWorkspaceFile(filename, workspace)
  else:
    self.app.openFile(filename)

  if editor.getSome(editor):
    if location.getSome(location):
      if editor == self:
        self.selection = location
        self.updateTargetColumn(Last)
        self.centerCursor()

      elif editor of TextDocumentEditor:
        let textEditor = editor.TextDocumentEditor
        textEditor.targetSelection = location
        textEditor.centerCursor()

  else:
    log lvlError, fmt"Failed to open file '{filename}' at {location}"

import finder/[workspace_file_previewer]

proc openLocationFromFinderItem(self: TextDocumentEditor, item: FinderItem) =
  try:
    let (path, location) = item.parsePathAndLocationFromItemData().getOr:
      log lvlError, fmt"Failed to open location from finder item because of invalid data format. " &
        fmt"Expected path or json object with path property {item}"
      return

    self.openFileAt(path, location.mapIt(it.toSelection))
  except:
    log lvlError, fmt"Failed to parse data from item {item}"

proc encodeFileLocationForFinderItem(path: string, location: Option[Cursor]): string =
  result = $ %*{
    "path": path,
    "line": location.get((0, 0)).line,
    "column": location.get((0, 0)).column,
  }

proc gotoLocationAsync(self: TextDocumentEditor, definitions: seq[Definition]): Future[void] {.async.} =
  if definitions.len == 1:
    let d = definitions[0]
    self.openFileAt(d.filename, d.location.toSelection.some)

  elif self.document.workspace.getSome(workspace):
    var builder = SelectorPopupBuilder()
    builder.scope = "text-lsp-locations".some
    builder.scaleX = 0.85
    builder.scaleY = 0.8

    var res = newSeq[FinderItem]()
    for i, definition in definitions:
      let relPath = workspace.getRelativePathSync(definition.filename).get(definition.filename)
      let (_, name) = definition.filename.splitPath
      res.add FinderItem(
        displayName: name,
        detail: relPath.splitPath[0],
        data: encodeFileLocationForFinderItem(definition.filename, definition.location.some),
      )

    builder.previewer = newWorkspaceFilePreviewer(workspace, self.configProvider).Previewer.some

    let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
    builder.finder = finder.some

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      self.openLocationFromFinderItem(item)
      true

    discard self.app.pushSelectorPopup(builder)

proc gotoDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    # todo: absolute paths
    let locations = await ls.getDefinition(self.document.fullPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoDeclarationAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getDeclaration(self.document.fullPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoTypeDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getTypeDefinition(self.document.fullPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoImplementationAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getImplementation(self.document.fullPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoReferencesAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getReferences(self.document.fullPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc switchSourceHeaderAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let filename = await ls.switchSourceHeader(self.document.fullPath)
    if filename.getSome(filename):
      if self.document.workspace.getSome(workspace):
        discard self.app.openWorkspaceFile(filename, workspace)
      else:
        discard self.app.openFile(filename)

proc getCompletionMatches*(self: TextDocumentEditor, completionIndex: int): seq[int] =
  self.refilterCompletions()

  if completionIndex in self.completionMatchPositions:
    return self.completionMatchPositions[completionIndex]

  if completionIndex < self.completionMatches.len:
    let completionIndex = self.completionMatches[completionIndex].index
    let filterText = self.completions[completionIndex].filterText
    let label = self.completions[completionIndex].item.label

    var matches = newSeqOfCap[int](filterText.len)
    discard matchFuzzySublime(filterText, label, matches, true, defaultCompletionMatchingConfig)

    self.completionMatchPositions[completionIndex] = matches
    return matches

  return @[]

proc refilterCompletions(self: TextDocumentEditor) =
  if not self.completionsDirty:
    return

  self.completions = self.completionEngine.getCompletions()
  self.completionMatches.setLen self.completions.len
  for i in 0..<self.completionMatches.len:
    self.completionMatches[i] = (i, 0)
  self.completionMatchPositions.clear()

  self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.completionsDirty = false

proc showCompletionWindow(self: TextDocumentEditor) =
  self.showCompletions = true
  self.markDirty()

proc openSymbolSelectorPopup(self: TextDocumentEditor, symbols: seq[Symbol], navigateOnSelect: bool) =
  var builder = SelectorPopupBuilder()
  builder.scope = "text-lsp-locations".some
  builder.scaleX = 0.85
  builder.scaleY = 0.8

  var res = newSeq[FinderItem]()
  for i, symbol in symbols:
    res.add FinderItem(
      displayName: symbol.name,
      detail: $symbol.symbolType,
      data: encodeFileLocationForFinderItem(symbol.filename, symbol.location.some),
    )

  if self.document.workspace.getSome(workspace):
    builder.previewer = newWorkspaceFilePreviewer(workspace, self.configProvider).Previewer.some
  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    self.openLocationFromFinderItem(item)
    true

  discard self.app.pushSelectorPopup(builder)

proc gotoSymbolAsync(self: TextDocumentEditor): Future[void] {.async.} =
  if self.document.getLanguageServer().await.getSome(ls):
    let symbols = await ls.getSymbols(self.document.fullPath)
    if symbols.len == 0:
      return

    self.openSymbolSelectorPopup(symbols, navigateOnSelect=true)

type
  LspWorkspaceSymbolsDataSource* = ref object of DataSource
    workspace: WorkspaceFolder
    languageServer: LanguageServer
    query: string
    delayedTask: DelayedTask

proc getWorkspaceSymbols(self: LspWorkspaceSymbolsDataSource): Future[void] {.async.} =
  let symbols = self.languageServer.getWorkspaceSymbols(self.query).await

  let t = startTimer()
  var items = newItemList(symbols.len)
  var index = 0
  for symbol in symbols:
    if self.workspace.ignorePath(symbol.filename):
      continue

    let relPath = self.workspace.getRelativePathSync(symbol.filename).get(symbol.filename)

    items[index] = FinderItem(
      displayName: symbol.name,
      detail: $symbol.symbolType & "\t" & relPath.splitPath[0],
      data: encodeFileLocationForFinderItem(symbol.filename, symbol.location.some),
    )
    inc index

  debugf"[getWorkspaceSymbols] {t.elapsed.ms}ms"

  items.setLen(index)
  self.onItemsChanged.invoke items

proc newLspWorkspaceSymbolsDataSource(languageServer: LanguageServer, workspace: WorkspaceFolder):
    LspWorkspaceSymbolsDataSource =

  new result
  result.languageServer = languageServer
  result.workspace = workspace

method close*(self: LspWorkspaceSymbolsDataSource) =
  self.delayedTask.deinit()
  self.delayedTask = nil

method setQuery*(self: LspWorkspaceSymbolsDataSource, query: string) =
  self.query = query

  if self.delayedTask.isNil:
    self.delayedTask = startDelayed(200, repeat=false):
      asyncCheck self.getWorkspaceSymbols()
  else:
    self.delayedTask.reschedule()

proc gotoWorkspaceSymbolAsync(self: TextDocumentEditor, query: string = ""): Future[void] {.async.} =
  if self.document.workspace.getSome(workspace) and
      self.document.getLanguageServer().await.getSome(ls):

    var builder = SelectorPopupBuilder()
    builder.scope = "text-lsp-locations".some
    builder.scaleX = 0.85
    builder.scaleY = 0.8

    builder.previewer = newWorkspaceFilePreviewer(workspace, self.configProvider).Previewer.some
    let finder = newFinder(newLspWorkspaceSymbolsDataSource(ls, workspace), filterAndSort=true)
    builder.finder = finder.some

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      self.openLocationFromFinderItem(item)
      true

    discard self.app.pushSelectorPopup(builder)

proc gotoDefinition*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoDefinitionAsync()

proc gotoDeclaration*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoDeclarationAsync()

proc gotoTypeDefinition*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoTypeDefinitionAsync()

proc gotoImplementation*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoImplementationAsync()

proc gotoReferences*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoReferencesAsync()

proc switchSourceHeader*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.switchSourceHeaderAsync()

proc getCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.completionsDirty = true
  if self.completionEngine.isNotNil:
    self.completionEngine.updateCompletionsAt(self.selection.last)
  self.showCompletionWindow()

proc gotoSymbol*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoSymbolAsync()

proc gotoWorkspaceSymbol*(self: TextDocumentEditor, query: string = "") {.expose("editor.text").} =
  asyncCheck self.gotoWorkspaceSymbolAsync(query)

proc hideCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  # log lvlInfo, fmt"hideCompletions {self.document.filename}"
  self.showCompletions = false
  if self.updateCompletionsTask.isNotNil:
    self.updateCompletionsTask.pause()

  self.markDirty()

proc selectPrevCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completionMatches.len > 0:
    let len = self.completionMatches.len
    self.selectedCompletion = (self.selectedCompletion - 1 + len) mod len
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc selectNextCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completionMatches.len > 0:
    self.selectedCompletion = (self.selectedCompletion + 1) mod self.completionMatches.len
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc hasTabStops*(self: TextDocumentEditor): bool {.expose("editor.text").} =
  return self.currentSnippetData.isSome

proc clearTabStops*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.currentSnippetData = SnippetData.none

proc selectNextTabStop*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.currentSnippetData.isNone:
    return

  var foundTabStop = false
  while self.currentSnippetData.get.currentTabStop < self.currentSnippetData.get.highestTabStop:
    self.currentSnippetData.get.currentTabStop.inc
    if self.currentSnippetData.get.currentTabStop in self.currentSnippetData.get.tabStops:
      self.selections = self.currentSnippetData.get.tabStops[self.currentSnippetData.get.currentTabStop]
      foundTabStop = true
      break

  if not foundTabStop:
    self.selections = self.currentSnippetData.get.tabStops[0]
    self.currentSnippetData = SnippetData.none

proc selectPrevTabStop*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.currentSnippetData.isNone:
    return

  if self.currentSnippetData.get.currentTabStop == 0:
    return

  while self.currentSnippetData.get.currentTabStop > 1:
    self.currentSnippetData.get.currentTabStop.dec
    if self.currentSnippetData.get.currentTabStop in self.currentSnippetData.get.tabStops:
      self.selections = self.currentSnippetData.get.tabStops[self.currentSnippetData.get.currentTabStop]
      break

proc applyCompletion*(self: TextDocumentEditor, completion: Completion) =
  let completion = completion
  log(lvlInfo, fmt"Applying completion {completion}")

  let insertTextFormat = completion.item.insertTextFormat.get(InsertTextFormat.PlainText)

  var editSelection: Selection
  var insertText = ""

  let cursor = self.selection.last
  let cursorColumnIndex = self.document.getLine(cursor.line).runeIndex(cursor.column, returnLen=true)
  let offset: tuple[lines: int, columns: RuneCount] = if completion.origin.getSome(origin):
    (cursor.line - origin.line, cursorColumnIndex - origin.column)
  else:
    (0, 0.RuneCount)

  if completion.item.textEdit.getSome(edit):
    if edit.asTextEdit().getSome(edit):
      if edit.`range`.start.line < 0:
        if cursor.column == 0:
          editSelection = cursor.toSelection
        else:
          editSelection = self.document.getCompletionSelectionAt(cursor)
      else:
        let r = edit.`range`
        let runeSelection = (
          (r.start.line + offset.lines, r.start.character.RuneIndex + offset.columns),
          (r.`end`.line + offset.lines, r.`end`.character.RuneIndex + offset.columns),
        )
        let selection = self.document.runeSelectionToSelection(runeSelection)

        editSelection = selection

      insertText = edit.newText

    if edit.asInsertReplaceEdit().getSome(edit):
      debugf"text edit: {edit.insert}, {edit.replace} -> '{edit.newText}'"
      return

  else:
    insertText = completion.item.insertText.get(completion.item.label)
    if cursor.column == 0:
      editSelection = cursor.toSelection
    else:
      editSelection = self.document.getCompletionSelectionAt(cursor)

  var editSelections: seq[Selection] = @[]
  var insertTexts: seq[string] = @[]

  var snippetData = SnippetData.none
  if insertTextFormat == InsertTextFormat.Snippet:
    let snippet = parseSnippet(insertText)
    if snippet.isSome:
      let filenameParts = self.document.filename.splitFile
      debugf"parts: {filenameParts}"
      let variables = toTable {
        "TM_FILENAME": filenameParts.name & filenameParts.ext,
        "TM_FILENAME_BASE": filenameParts.name,
        "TM_FILETPATH": self.document.filename,
        "TM_DIRECTORY": filenameParts.dir,
        "TM_LINE_INDEX": $editSelection.last.line,
        "TM_LINE_NUMBER": $(editSelection.last.line + 1),
        "TM_CURRENT_LINE": self.document.lines[editSelection.last.line],
        "TM_CURRENT_WORD": "todo",
        "TM_SELECTED_TEXT": self.document.contentString(self.selection),
      }
      var data = snippet.get.createSnippetData(editSelection.first, variables)
      insertText = data.text
      snippetData = data.some

  for edit in completion.item.additionalTextEdits:
    let runeSelection = (
      (edit.`range`.start.line, edit.`range`.start.character.RuneIndex),
      (edit.`range`.`end`.line, edit.`range`.`end`.character.RuneIndex),
    )
    let selection = self.document.runeSelectionToSelection(runeSelection)
    editSelections.add selection
    insertTexts.add edit.newText

    let changedSelection = selection.getChangedSelection(edit.newText)

    if snippetData.isSome:
      snippetData.get.offset(changedSelection)

  editSelections.add editSelection
  insertTexts.add insertText

  let newSelections = self.document.edit(editSelections, self.selections, insertTexts)
  self.selection = newSelections[newSelections.high].last.toSelection

  self.currentSnippetData = snippetData
  self.selectNextTabStop()

  self.hideCompletions()

proc applyCompletion*(self: TextDocumentEditor, completion: JsonNode) {.expose("editor.text").} =
  try:
    let completion = completion.jsonTo(Completion)
    self.applyCompletion(completion)
  except:
    log lvlError, &"[applyCompletion] Failed to parse completion {completion}"

proc applySelectedCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if not self.showCompletions:
    return

  if self.selectedCompletion > self.completionMatches.high:
    return

  let cursor = self.selection.last
  let runeCursor = (cursor.line, self.document.getLine(cursor.line).runeIndex(cursor.column))
  var completion = self.completions[self.completionMatches[self.selectedCompletion].index]

  self.addNextCheckpoint("insert")
  self.applyCompletion(completion)

  if self.bIsRecordingCurrentCommand:
    completion.origin = runeCursor.some
    self.app.recordCommand("." & "apply-completion", $completion.toJson)

proc showHoverForAsync(self: TextDocumentEditor, cursor: Cursor): Future[void] {.async.} =
  if self.hideHoverTask.isNotNil:
    self.hideHoverTask.pause()

  let languageServer = await self.document.getLanguageServer()

  if languageServer.getSome(ls):
    let hoverInfo = await ls.getHover(self.document.fullPath, cursor)
    if hoverInfo.getSome(hoverInfo):
      self.showHover = true
      self.hoverScrollOffset = 0
      self.hoverText = hoverInfo
      self.hoverLocation = cursor
    else:
      self.showHover = false

  self.markDirty()

proc showHoverFor*(self: TextDocumentEditor, cursor: Cursor) {.expose("editor.text").} =
  ## Shows lsp hover information for the given cursor.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncCheck self.showHoverForAsync(cursor)

proc showHoverForCurrent*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp hover information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncCheck self.showHoverForAsync(self.selection.last)

proc hideHover*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Hides the hover information.
  self.showHover = false
  self.markDirty()

proc cancelDelayedHideHover*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.hideHoverTask.isNotNil:
    self.hideHoverTask.pause()

proc hideHoverDelayed*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Hides the hover information after a delay.
  if self.showHoverTask.isNotNil:
    self.showHoverTask.pause()

  let hoverDelayMs = self.configProvider.getValue("text.hover-delay", 200)
  if self.hideHoverTask.isNil:
    self.hideHoverTask = startDelayed(hoverDelayMs, repeat=false):
      self.hideHover()
  else:
    self.hideHoverTask.interval = hoverDelayMs
    self.hideHoverTask.reschedule()

proc showHoverForDelayed*(self: TextDocumentEditor, cursor: Cursor) =
  ## Show hover information for the given cursor after a delay.
  self.currentHoverLocation = cursor

  if self.hideHoverTask.isNotNil:
    self.hideHoverTask.pause()

  let hoverDelayMs = self.configProvider.getValue("text.hover-delay", 200)
  if self.showHoverTask.isNil:
    self.showHoverTask = startDelayed(hoverDelayMs, repeat=false):
      self.showHoverFor(self.currentHoverLocation)
  else:
    self.showHoverTask.interval = hoverDelayMs
    self.showHoverTask.reschedule()

  self.markDirty()

proc updateInlayHintsAsync*(self: TextDocumentEditor): Future[void] {.async.} =
  if self.document.isNil:
    return

  if self.document.getLanguageServer().await.getSome(ls):
    if self.document.isNil:
      return

    let visibleRange = self.visibleTextRange(self.screenLineCount)
    let inlayHints = await ls.getInlayHints(self.document.fullPath, visibleRange)
    # todo: detect if canceled instead
    if inlayHints.len > 0:
      # log lvlInfo, fmt"Updating inlay hints: {inlayHints}"
      self.inlayHints = inlayHints
      self.markDirty()

proc clearDiagnostics*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.document.clearDiagnostics()
  self.currentDiagnosticLine = -1
  self.markDirty()

proc updateDiagnosticsAsync*(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if languageServer.getSome(ls):
    let diagnostics = await ls.getDiagnostics(self.document.fullPath)
    debugf"diagnostics: {diagnostics}"

proc updateInlayHints*(self: TextDocumentEditor) =
  if self.inlayHintsTask.isNil:
    self.inlayHintsTask = startDelayed(200, repeat=false):
      asyncCheck self.updateInlayHintsAsync()
      # asyncCheck self.updateDiagnosticsAsync()
  else:
    self.inlayHintsTask.reschedule()

proc updateDiagnosticsForCurrent*(self: TextDocumentEditor) {.expose("editor.text").} =
  let line = self.selection.last.line
  if self.document.diagnosticsPerLine.contains(line):
    let diagnostics {.cursor.} = self.document.diagnosticsPerLine[line]
    let index = diagnostics[0]
    if index >= self.document.currentDiagnostics.len:
      self.currentDiagnosticLine = -1
    else:
      self.currentDiagnosticLine = line
      self.currentDiagnostic = self.document.currentDiagnostics[index]
      self.showDiagnostic = true
  else:
    self.currentDiagnosticLine = -1

  self.markDirty()

proc showDiagnosticsForCurrent*(self: TextDocumentEditor) {.expose("editor.text").} =
  let line = self.selection.last.line
  if self.showDiagnostic and self.currentDiagnostic.selection.first.line == line:
    self.showDiagnostic = false
    self.markDirty()
    return

  if self.document.diagnosticsPerLine.contains(line):
    let diagnostics {.cursor.} = self.document.diagnosticsPerLine[line]
    self.currentDiagnosticLine = line
    let index = diagnostics[0]
    if index >= self.document.currentDiagnostics.len:
      self.showDiagnostic = false
      self.markDirty()
      return

    self.currentDiagnostic = self.document.currentDiagnostics[index]
    self.showDiagnostic = true
  else:
    self.showDiagnostic = false

  self.markDirty()

proc setReadOnly*(self: TextDocumentEditor, readOnly: bool) {.expose("editor.text").} =
  ## Sets the interal readOnly flag, but doesn't not change permissions of the underlying file
  self.document.setReadOnly(readOnly)
  self.markDirty()

proc setFileReadOnlyAsync*(self: TextDocumentEditor, readOnly: bool) {.async.} =
  ## Tries to set the underlying files write permissions
  if not self.document.setFileReadOnlyAsync(readOnly).await:
    log lvlError, fmt"Failed to change readOnly status of '{self.document.filename}'"
    return

  self.markDirty()

proc setFileReadOnly*(self: TextDocumentEditor, readOnly: bool) {.expose("editor.text").} =
  asyncCheck self.setFileReadOnlyAsync(readOnly)

proc isRunningSavedCommands*(self: TextDocumentEditor): bool {.expose("editor.text").} =
  self.bIsRunningSavedCommands

proc runSavedCommands*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.bIsRunningSavedCommands:
    return
  self.bIsRunningSavedCommands = true
  defer:
    self.bIsRunningSavedCommands = false

  var commandHistory = self.savedCommandHistory
  for command in commandHistory.commands.mitems:
    let isRecursive = command.command == "run-saved-commands" or command.command == "runSavedCommands"
    if not command.isInput and isRecursive:
      continue

    if command.isInput:
      discard self.handleInput(command.command, record=false)
    else:
      discard self.handleActionInternal(command.command, command.args)

  self.savedCommandHistory = commandHistory

proc clearCurrentCommandHistory*(self: TextDocumentEditor, retainLast: bool = false) {.
    expose("editor.text").} =
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

proc getCombinationsOfLength*(self: TextDocumentEditor, keys: openArray[string],
    disallowedPairs: HashSet[string], length: int, disallowDoubles: bool): seq[string] =
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
  let disallowedPairs = [
    "ao", "io", "rs", "ts", "iv", "al", "ec", "eo", "ns",
    "nh", "rg", "tf", "ui", "dt", "sd", "ou", "uv", "df"
  ].toHashSet
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
  var config = EventHandlerConfig(
    context: "editor.text.choose-cursor",
    handleActions: true,
    handleInputs: true,
    consumeAllActions: true,
    consumeAllInput: true
  )

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
      self.styledTextOverrides[cursors[i].line].add (cursor, text, "constant.numeric")

      options.add cursors[i]

    if options.len == 1:
      self.styledTextOverrides.clear()
      self.document.notifyTextChanged()
      self.markDirty()
      discard self.handleAction(action, ($options[0].toJson & " " & $oldMode.toJson), record=false)

    self.document.notifyTextChanged()
    self.markDirty()

  updateStyledTextOverrides()

  config.addCommand("", "<ESCAPE>", "setMode \"\"")

  self.modeEventHandler = eventHandler(config):
    onAction:
      self.styledTextOverrides.clear()
      self.document.notifyTextChanged()
      self.markDirty()
      self.handleAction action, arg, record=true

    onInput:
      Ignored

    onProgress:
      progress.add inputToString(input)
      updateStyledTextOverrides()

    onCanceled:
      self.styledTextOverrides.clear()
      self.setMode(oldMode)

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  self.currentMode = mode

  self.app.handleModeChanged(self, oldMode, self.currentMode)

  self.markDirty()

proc recordCurrentCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.bRecordCurrentCommand = true

proc runSingleClickCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  let commandName = self.configProvider.getValue("editor.text.single-click-command", "")
  let args = self.configProvider.getValue("editor.text.single-click-command-args", newJArray())
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runDoubleClickCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  let commandName = self.configProvider.getValue("editor.text.double-click-command", "extend-select-move")
  let args = self.configProvider.getValue("editor.text.double-click-command-args",
    %[newJString("word"), newJBool(true)])
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runTripleClickCommand*(self: TextDocumentEditor) {.expose("editor.text").} =
  let commandName = self.configProvider.getValue("editor.text.triple-click-command", "extend-select-move")
  let args = self.configProvider.getValue("editor.text.triple-click-command-args",
    %[newJString("line"), newJBool(true)])
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

genDispatcher("editor.text")
addActiveDispatchTable "editor.text", genDispatchTable("editor.text")

proc getStyledText*(self: TextDocumentEditor, i: int): StyledLine =
  result = StyledLine(index: i, parts: self.document.getStyledText(i).parts)

  let chars = (self.lastTextAreaBounds.w / self.platform.charWidth - 2).RuneCount
  if chars > 0.RuneCount:
    var i = 0
    while i < result.parts.len:
      if result.parts[i].text.runeLen > chars:
        splitPartAt(result, i, chars.RuneIndex)
      inc i

  # Highlight the indentation of the cursor line
  let cursorIndentLevel = self.document.getIndentForLine(self.selection.last.line)
  let currentIndentLevel = self.document.getIndentForLine(i)
  if currentIndentLevel > cursorIndentLevel:
    let opacity = self.configProvider.getValue("editor.text.whitespace.opacity", 0.4)
    let start = self.document.lines[i].toOpenArray.runeIndex(cursorIndentLevel, returnLen=true)
    result.splitAt(start)
    result.splitAt(start + 1.RuneCount)
    result.overrideStyleAndText(start, "|", "comment", -1, opacity=opacity.some)

  if self.styledTextOverrides.contains(i):
    result.overrideStyle(0.RuneIndex, result.runeLen.RuneIndex, "comment", -1)

    for override in self.styledTextOverrides[i]:
      self.document.splitAt(result, override.cursor.column)
      self.document.splitAt(result, override.cursor.column + override.text.len)
      self.document.overrideStyleAndText(result, override.cursor.column, override.text,
        override.scope, -2, joinNext = true)

  for inlayHint in self.inlayHints:
    if inlayHint.location.line != i:
      continue

    self.document.insertText(result, inlayHint.location.column.RuneIndex, inlayHint.label,
      "comment", containCursor=true)

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

method handleAction*(self: TextDocumentEditor, action: string, arg: string, record: bool): EventResponse =
  # debugf "handleAction {action}, '{arg}'"

  let oldIsRecordingCurrentCommand = self.bIsRecordingCurrentCommand
  defer:
    self.bIsRecordingCurrentCommand = oldIsRecordingCurrentCommand

  self.bIsRecordingCurrentCommand = record

  let noRecordActions = [
    "apply-selected-completion",
    "applySelectedCompletion",
  ].toHashSet

  if record and action notin noRecordActions:
    self.app.recordCommand("." & action, arg)

  defer:
    if record and self.bRecordCurrentCommand:
      self.app.recordCommand("." & action, arg)
    self.bRecordCurrentCommand = false

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

proc handleInput(self: TextDocumentEditor, input: string, record: bool): EventResponse =
  if not self.isRunningSavedCommands:
    self.currentCommandHistory.commands.add Command(isInput: true, command: input)

  if record:
    self.app.recordCommand(".insert-text", $input.newJString)

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
      self.handleAction action, arg, record=true
    onInput:
      self.handleInput input, record=true

  self.completionEventHandler = eventHandler(app.getEventHandlerConfig("editor.text.completion")):
    onAction:
      self.handleAction action, arg, record=true
    onInput:
      self.handleInput input, record=true

  self.setMode(self.configProvider.getValue("editor.text.default-mode", ""))

proc updateInlayHintPositionsAfterInsert(self: TextDocumentEditor, inserted: Selection) =
  for i in countdown(self.inlayHints.high, 0):
    # todo: correctly handle unicode (inlay hint location comes from lsp, so probably a RuneIndex)
    template inlayHint: InlayHint = self.inlayHints[i]
    if inlayHint.location == inserted.first:
      self.inlayHints.removeSwap(i)
    else:
      inlayHint.location = self.document.updateCursorAfterInsert(inlayHint.location, inserted)

  if self.currentSnippetData.isSome:
    for (key, tabStops) in self.currentSnippetData.get.tabStops.mpairs:
      for selection in tabStops.mitems:
        selection.first = self.document.updateCursorAfterInsert(selection.first, inserted)
        selection.last = self.document.updateCursorAfterInsert(selection.last, inserted)

proc updateInlayHintPositionsAfterDelete(self: TextDocumentEditor, selection: Selection) =
  let selection = selection.normalized
  for i in countdown(self.inlayHints.high, 0):
    # todo: correctly handle unicode (inlay hint location comes from lsp, so probably a RuneIndex)
    template inlayHint: InlayHint = self.inlayHints[i]
    if self.document.updateCursorAfterDelete(inlayHint.location, selection).getSome(location):
      self.inlayHints[i].location = location
    else:
      self.inlayHints.removeSwap(i)

  if self.currentSnippetData.isSome:
    for (key, tabStops) in self.currentSnippetData.get.tabStops.mpairs:
      for tabStopSelection in tabStops.mitems:

        if self.document.updateCursorAfterDelete(tabStopSelection.first, selection).getSome(first):
          tabStopSelection.first = first
        else:
          tabStopSelection.first = selection.first

        if self.document.updateCursorAfterDelete(tabStopSelection.last, selection).getSome(last):
          tabStopSelection.last = last
        else:
          tabStopSelection.last = selection.first

proc handleTextInserted(self: TextDocumentEditor, document: TextDocument, location: Selection,
    text: string) =
  self.updateInlayHintPositionsAfterInsert(location)
  self.completionsDirty = true

proc handleTextDeleted(self: TextDocumentEditor, document: TextDocument, selection: Selection) =
  self.updateInlayHintPositionsAfterDelete(selection)
  self.completionsDirty = true

proc handleDiagnosticsUpdated(self: TextDocumentEditor) =
  # log lvlInfo, fmt"Got diagnostics for {self.document.filename}: {self.document.currentDiagnostics.len}"
  self.updateDiagnosticsForCurrent()

proc handleLanguageServerAttached(self: TextDocumentEditor, document: TextDocument,
    languageServer: LanguageServer) =
  # log lvlInfo, fmt"[handleLanguageServerAttached] {self.document.filename}"
  self.completionEngine.addProvider newCompletionProviderLsp(document, languageServer)
    .withMergeStrategy(MergeStrategy(kind: TakeAll))
    .withPriority(2)
  self.completionsDirty = true

proc handleTextDocumentTextChanged(self: TextDocumentEditor) =
  self.clampSelection()
  self.searchResultsDirty = true
  self.completionsDirty = true

  if self.showCompletions and self.updateCompletionsTask.isNotNil:
    self.updateCompletionsTask.reschedule()

  self.updateInlayHints()
  self.updateDiagnosticsForCurrent()

  self.markDirty()

proc handleTextDocumentLoaded(self: TextDocumentEditor) =
  if self.document.isNil:
    return

  if self.targetSelectionsInternal.getSome(s):
    self.selections = s
    self.centerCursor()
  self.targetSelectionsInternal = Selections.none
  self.updateTargetColumn(Last)

proc handleTextDocumentSaved(self: TextDocumentEditor) =
  log lvlInfo, fmt"handleTextDocumentSaved '{self.document.filename}'"
  if self.diffDocument.isNotNil:
    asyncCheck self.updateDiffAsync(gotoFirstDiff=false)

proc handleCompletionsUpdated(self: TextDocumentEditor) =
  self.completionsDirty = true
  self.markDirty()

## Only use this to create TextDocumentEditorInstances
proc createTextEditorInstance(): TextDocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, selectionsInternal: @[(0, 0).toSelection])
  when defined(js):
    {.emit: [editor, " = jsCreateWithPrototype(editor_text_prototype, ", editor, ");"].}
    # This " is here to fix syntax highlighting
  editor.cursorsId = newId()
  editor.completionsId = newId()
  editor.hoverId = newId()
  editor.inlayHints = @[]
  allTextEditors.add editor
  return editor

proc newTextEditor*(document: TextDocument, app: AppInterface, configProvider: ConfigProvider):
    TextDocumentEditor =

  assert app.isNotNil

  var self = createTextEditorInstance()
  self.configProvider = configProvider
  self.setDocument(document)

  self.init()
  self.startBlinkCursorTask()
  self.injectDependencies(app)

  if self.document.lines.len == 0:
    self.document.lines = @[""]

  return self

method getDocument*(self: TextDocumentEditor): Document = self.document

method createWithDocument*(_: TextDocumentEditor, document: Document, configProvider: ConfigProvider):
    DocumentEditor =

  var self = createTextEditorInstance()
  self.configProvider = configProvider

  self.setDocument(document.TextDocument)
  self.init()
  self.startBlinkCursorTask()

  if self.document.lines.len == 0:
    self.document.lines = @[""]

  return self

method unregister*(self: TextDocumentEditor) =
  if self.app.isNil:
    log lvlError, &"[unregister] app is nil, probably called twice"
    return

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
