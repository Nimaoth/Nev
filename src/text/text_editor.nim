import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables,
  deques, sets, algorithm, os]
import chroma
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, rect_utils, event, custom_logger, custom_async, fuzzy_matching,
  custom_unicode, delayed_task, myjsonutils, regex, timer, response, rope_utils]
import scripting/[expose, scripting_base]
import platform/[platform]
import language/[language_server_base]
import document, document_editor, events, vmath, bumpy, input, custom_treesitter, indent,
  text_document, snippet
import completion, completion_provider_document, completion_provider_lsp,
  completion_provider_snippet, selector_popup_builder, dispatch_tables, register
import config_provider, service, layout, platform_service, vfs, vfs_service, command_service
import diff
import workspaces/workspace
import finder/[previewer, finder]
import vcs/vcs
import overlay_map, tab_map, wrap_map, diff_map, display_map

from language/lsp_types import CompletionList, CompletionItem, InsertTextFormat,
  TextEdit, Position, asTextEdit, asInsertReplaceEdit, toJsonHook

import nimsumtree/[buffer, clock, static_array, rope]
from nimsumtree/sumtree as st import summaryType, itemSummary, Bias

export text_document, document_editor, id

{.push gcsafe.}
{.push raises: [].}

logCategory "texted"

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
  platform*: Platform
  configProvider*: ConfigProvider
  editors*: DocumentEditorService
  layout*: LayoutService
  services*: Services
  vcs: VCSService
  events: EventHandlerService
  plugins: PluginService
  registers: Registers
  workspace: Workspace
  vfsService: VFSService
  vfs: VFS
  commands*: CommandService

  document*: TextDocument
  snapshot: BufferSnapshot
  selectionAnchors: seq[(Anchor, Anchor)]

  displayMap*: DisplayMap
  diffDisplayMap*: DisplayMap

  showDiff: bool = false
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

  selectionsBeforeReload: Selections
  selectionsInternal: Selections
  targetSelectionsInternal: Option[Selections] # The selections we want to have once
                                               # the document is loaded
  selectionHistory: Deque[Selections]
  dontRecordSelectionHistory: bool

  cursorMargin*: Option[float]

  searchQuery*: string
  searchResults*: seq[Range[Point]]
  isUpdatingSearchResults: bool
  lastSearchResultUpdate: tuple[buffer: BufferId, version: Global, searchQuery: string]

  styledTextOverrides: Table[int, seq[tuple[cursor: Cursor, text: string, scope: string]]]

  customHighlights*: Table[int, seq[tuple[id: Id, selection: Selection, color: string, tint: Color]]]
  signs*: Table[int, seq[tuple[id: Id, group: string, text: string, tint: Color]]]

  defaultScrollBehaviour*: ScrollBehaviour = CenterOffscreen
  nextScrollBehaviour*: Option[ScrollBehaviour]
  defaultSnapBehaviour*: ScrollSnapBehaviour = MinDistanceOffscreen
  nextSnapBehaviour*: Option[ScrollSnapBehaviour]
  targetLineMargin*: Option[float]
  targetLineRelativeY*: float = 0.5
  targetPoint*: Option[Point]
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
  inlayHints: seq[tuple[anchor: Anchor, hint: InlayHint]]
  inlayHintsTask: DelayedTask
  lastInlayHintTimestamp: Lamport
  lastInlayHintDisplayRange: Selection

  eventHandlerNames: seq[string]
  eventHandlers: seq[EventHandler]
  modeEventHandlers: seq[EventHandler]
  completionEventHandler: EventHandler
  currentMode*: string
  commandCount*: int
  commandCountRestore*: int
  currentCommandHistory: CommandHistory
  savedCommandHistory: CommandHistory
  bIsRunningSavedCommands: bool
  recordCurrentCommandRegisters: seq[string] # List of registers the current command should be recorded into.
  bIsRecordingCurrentCommand: bool = false # True while running a command which is being recorded
  bScrollToEndOnInsert*: bool = false

  disableScrolling*: bool
  scrollOffset*: float
  interpolatedScrollOffset*: float
  lineNumbers*: Option[LineNumbers]

  currentCenterCursor*: Cursor # Cursor representing the center of the screen
  currentCenterCursorRelativeYPos*: float # 0: top of screen, 1: bottom of screen

  lastRenderedChunks*: seq[tuple[range: Range[Point], displayRange: Range[DisplayPoint]]]
  lastRenderedLines*: seq[StyledLine]
  lastTextAreaBounds*: Rect
  lastPressedMouseButton*: MouseButton
  dragStartSelection*: Selection

  completionMatchPositions*: Table[int, seq[int]] # Maps from completion index to char indices
                                                  # of matching chars
  completionMatchPositionsFutures*: Table[int, Future[seq[int]]] # Maps from completion index to char indices
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

  lastEndDisplayPoint: DisplayPoint

  completionEngine: CompletionEngine

  currentSnippetData*: Option[SnippetData]

  onBufferChangedHandle: Id
  textChangedHandle: Id
  onEditHandle: Id
  onRequestRerenderHandle: Id
  onRequestRerenderDiffHandle: Id
  loadedHandle: Id
  preLoadedHandle: Id
  savedHandle: Id
  textInsertedHandle: Id
  textDeletedHandle: Id
  languageServerAttachedHandle: Id
  onCompletionsUpdatedHandle: Id
  onFocusChangedHandle: Id

  lastCompletionTrigger: (Global, Cursor)
  completionsDirty: bool

  customHeader*: string

  onSearchResultsUpdated*: Event[TextDocumentEditor]

type
  TextDocumentEditorService* = ref object of Service
  TextDocumentFactory* = ref object of DocumentFactory
  TextDocumentEditorFactory* = ref object of DocumentEditorFactory

proc newTextEditor*(document: TextDocument, services: Services): TextDocumentEditor

func serviceName*(_: typedesc[TextDocumentEditorService]): string = "TextDocumentEditorService"

addBuiltinService(TextDocumentEditorService, DocumentEditorService)

method init*(self: TextDocumentEditorService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"TextDocumentEditorService.init"
  let editors = self.services.getService(DocumentEditorService).get
  editors.addDocumentFactory(TextDocumentFactory())
  editors.addDocumentEditorFactory(TextDocumentEditorFactory())
  return ok()

method canOpenFile*(self: TextDocumentFactory, path: string): bool =
  return true

method createDocument*(self: TextDocumentFactory, services: Services, path: string): Document =
  return newTextDocument(services, path, app=false, load=true)

method canEditDocument*(self: TextDocumentEditorFactory, document: Document): bool =
  return document of TextDocument

method createEditor*(self: TextDocumentEditorFactory, services: Services, document: Document): DocumentEditor =
  result = newTextEditor(document.TextDocument, services)

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
  result.add &"Diff map: {st.stats(self.displayMap.wrapMap.snapshot.map)}\n"
  result.add &"Wrap map: {st.stats(self.displayMap.diffMap.snapshot.map)}\n"

  var temp = 0
  for s in self.completionMatchPositions.values:
    temp += s.len
  result.add &"Completion Match Positions: {self.completionMatchPositions.len}, {temp}\n"
  result.add &"Completion Matches: {self.completionMatches.len}\n"

  result.add &"Completions: {self.completions.len}\n"
  result.add &"LastItems: {self.lastItems.len}"

proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): Option[JsonNode]
proc handleInput(self: TextDocumentEditor, input: string, record: bool): EventResponse
proc showCompletionWindow(self: TextDocumentEditor)
proc updateCompletionsFromEngine(self: TextDocumentEditor)
proc hideCompletions*(self: TextDocumentEditor)
proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string, count: int = 0): Selection
proc extendSelectionWithMove*(self: TextDocumentEditor, selection: Selection, move: string, count: int = 0): Selection
proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor = Last)
proc updateInlayHints*(self: TextDocumentEditor)
proc visibleTextRange*(self: TextDocumentEditor, buffer: int = 0): Selection
proc addCustomHighlight*(self: TextDocumentEditor, id: Id, selection: Selection, color: string, tint: Color = color(1, 1, 1))
proc clearCustomHighlights*(self: TextDocumentEditor, id: Id)
proc updateSearchResults(self: TextDocumentEditor)
proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config)
proc centerCursor*(self: TextDocumentEditor, cursor: Cursor, relativePosition: float = 0.5)
proc getContextWithMode*(self: TextDocumentEditor, context: string): string
proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config, margin: Option[float] = float.none, scrollBehaviour: Option[ScrollBehaviour] = ScrollBehaviour.none, relativePosition: float = 0.5)
proc getFileName(self: TextDocumentEditor): string
proc closeDiff*(self: TextDocumentEditor)
proc setNextSnapBehaviour*(self: TextDocumentEditor, snapBehaviour: ScrollSnapBehaviour)

proc handleLanguageServerAttached(self: TextDocumentEditor, document: TextDocument, languageServer: LanguageServer)
proc handleEdits(self: TextDocumentEditor, edits: openArray[tuple[old, new: Selection]])
proc handleTextDocumentTextChanged(self: TextDocumentEditor)
proc handleTextDocumentBufferChanged(self: TextDocumentEditor, document: TextDocument)
proc handleTextDocumentLoaded(self: TextDocumentEditor)
proc handleTextDocumentPreLoaded(self: TextDocumentEditor)
proc handleTextDocumentSaved(self: TextDocumentEditor)
proc handleCompletionsUpdated(self: TextDocumentEditor)
proc handleWrapMapUpdated(self: TextDocumentEditor, wrapMap: WrapMap, old: WrapMapSnapshot)
proc handleDisplayMapUpdated(self: TextDocumentEditor, displayMap: DisplayMap)
proc updateEventHandlers(self: TextDocumentEditor)
proc updateModeEventHandlers(self: TextDocumentEditor)

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
  includeAfter: bool = true, wrap: bool = true): Selection
proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
  includeAfter: bool = true, wrap: bool = true): Selection

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
  assert self.selectionsInternal.len > 0, "[selection] Empty selection"
  self.selectionsInternal[self.selectionsInternal.high]

proc `selections=`*(self: TextDocumentEditor, selections: Selections) =
  let selections = self.clampAndMergeSelections(selections)
  assert selections.len > 0, "[selections=] Empty selections"

  if not self.dontRecordSelectionHistory:
    if self.selectionHistory.len == 0 or
        abs(selections[^1].last.line - self.selectionsInternal[^1].last.line) > 1 or
        self.selectionsInternal.len != selections.len:

      self.selectionHistory.addLast self.selectionsInternal
      if self.selectionHistory.len > 100:
        discard self.selectionHistory.popFirst

  self.selectionsInternal = selections
  self.cursorVisible = true

  let snapshot {.cursor.} = self.document.buffer.snapshot
  self.selectionAnchors = self.selectionsInternal.mapIt (snapshot.anchorAfter(it.first.toPoint), snapshot.anchorBefore(it.last.toPoint))

  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  if self.completionEngine.isNotNil:
    self.completionEngine.setCurrentLocations(self.selectionsInternal)

  self.showHover = false
  self.hideCompletions()
  # self.document.addNextCheckpoint("move")

  self.markDirty()

proc `selection=`*(self: TextDocumentEditor, selection: Selection) =
  self.selections = @[selection]

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
      if not self.active or not self.platform.focused:
        self.cursorVisible = true
        self.markDirty()
        self.blinkCursorTask.pause()
        return
      self.cursorVisible = not self.cursorVisible
      self.markDirty()
  else:
    self.blinkCursorTask.reschedule()

proc clearDocument*(self: TextDocumentEditor) =
  self.closeDiff()
  if self.document.isNotNil:
    # log lvlInfo, &"[clearDocument] ({self.id}): '{self.document.filename}'"
    self.document.onBufferChanged.unsubscribe(self.onBufferChangedHandle)
    self.document.onEdit.unsubscribe(self.onEditHandle)
    self.document.textChanged.unsubscribe(self.textChangedHandle)
    self.document.onRequestRerender.unsubscribe(self.onRequestRerenderHandle)
    self.document.onLoaded.unsubscribe(self.loadedHandle)
    self.document.onPreLoaded.unsubscribe(self.preLoadedHandle)
    self.document.onSaved.unsubscribe(self.savedHandle)
    self.document.onLanguageServerAttached.unsubscribe(self.languageServerAttachedHandle)

    let document = self.document
    self.document = nil
    self.editors.tryCloseDocument(document)

    self.selectionHistory.clear()
    self.customHighlights.clear()
    self.signs.clear()
    self.showHover = false
    self.inlayHints.setLen 0
    self.scrollOffset = 0
    self.lastRenderedLines.setLen 0
    self.currentSnippetData = SnippetData.none

proc setDocument*(self: TextDocumentEditor, document: TextDocument) =
  assert document.isNotNil

  if document == self.document:
    return

  # logScope lvlInfo, &"[setDocument] ({self.id}): '{document.filename}'"

  if self.completionEngine.isNotNil:
    self.completionEngine.onCompletionsUpdated.unsubscribe(self.onCompletionsUpdatedHandle)

  self.clearDocument()
  self.document = document
  self.snapshot = document.buffer.snapshot.clone()
  self.displayMap.setBuffer(self.snapshot.clone())

  self.onEditHandle = document.onEdit.subscribe (arg: tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]) =>
    self.handleEdits(arg.edits)

  self.textChangedHandle = document.textChanged.subscribe (_: TextDocument) =>
    self.handleTextDocumentTextChanged()

  self.onBufferChangedHandle = document.onBufferChanged.subscribe (arg: tuple[document: TextDocument]) =>
    self.handleTextDocumentBufferChanged(arg.document)

  self.onRequestRerenderHandle = document.onRequestRerender.subscribe () =>
    self.markDirty()

  self.loadedHandle = document.onLoaded.subscribe (_: TextDocument) => (block:
      if self.isNil or self.document.isNil:
        return
      self.handleTextDocumentLoaded()
  )

  self.preLoadedHandle = document.onPreLoaded.subscribe (_: TextDocument) => (block:
      if self.isNil or self.document.isNil:
        return
      self.handleTextDocumentPreLoaded()
  )

  self.savedHandle = document.onSaved.subscribe () =>
    self.handleTextDocumentSaved()

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
  # logScope lvlInfo, fmt"[deinit] Destroying text editor ({self.id}) for '{filename}'"

  self.platform.onFocusChanged.unsubscribe self.onFocusChangedHandle

  self.unregister()

  if self.diffDocument.isNotNil:
    self.diffDocument.onRequestRerender.unsubscribe(self.onRequestRerenderDiffHandle)
    self.diffDocument.deinit()
    self.diffDocument = nil

  self.clearDocument()

  if self.blinkCursorTask.isNotNil: self.blinkCursorTask.pause()
  if self.inlayHintsTask.isNotNil: self.inlayHintsTask.pause()
  if self.showHoverTask.isNotNil: self.showHoverTask.pause()
  if self.hideHoverTask.isNotNil: self.hideHoverTask.pause()

  if self.completionEngine.isNotNil:
    self.completionEngine.onCompletionsUpdated.unsubscribe(self.onCompletionsUpdatedHandle)

  {.gcsafe.}:
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
  result = self.eventHandlers
  result.add self.modeEventHandlers

  if inject.contains("above-mode"):
    result.add inject["above-mode"]

  if self.showCompletions:
    result.add self.completionEventHandler

  if inject.contains("above-completion"):
    result.add inject["above-completion"]

proc updateInlayHintsAfterChange(self: TextDocumentEditor) =
  if self.inlayHints.len > 0 and self.lastInlayHintTimestamp != self.document.buffer.timestamp:
    self.lastInlayHintTimestamp = self.document.buffer.timestamp
    let snapshot = self.document.buffer.snapshot.clone()

    for i in countdown(self.inlayHints.high, 0):
      if self.inlayHints[i].anchor.summaryOpt(Point, snapshot, resolveDeleted = false).getSome(point):
        self.inlayHints[i].hint.location = point.toCursor
        self.inlayHints[i].anchor = snapshot.anchorAt(self.inlayHints[i].hint.location.toPoint, Left)
      else:
        self.inlayHints.removeSwap(i)

    self.displayMap.overlay.clear(14)
    for hint in self.inlayHints:
      let point = hint.hint.location.toPoint
      self.displayMap.overlay.addOverlay(point...point, hint.hint.label, 14, "comment")

proc preRender*(self: TextDocumentEditor, bounds: Rect) =
  if self.configProvider.isNil or self.document.isNil:
    return

  if self.document.requiresLoad:
    self.document.load()
    self.document.reloadTreesitterLanguage()
    self.document.requiresLoad = false

  var wrapWidth = max(floor(bounds.w / self.platform.charWidth).int - 10, 10)
  if self.diffDocument.isNotNil:
    # todo: this should account for the line number width
    wrapWidth = wrapWidth div 2 - 2

  let tabWidth = self.configProvider.getValue("text.tab-width", self.document.tabWidth)
  self.displayMap.tabMap.setTabWidth(tabWidth)

  if self.displayMap.remoteId != self.document.buffer.remoteId:
    self.displayMap.setBuffer(self.document.buffer.snapshot.clone())

  if self.diffDocument.isNotNil:
    if self.diffDisplayMap.remoteId != self.diffDocument.buffer.remoteId:
      self.diffDisplayMap.setBuffer(self.diffDocument.buffer.snapshot.clone())
    if self.diffDocument.rope.len > 1:
      self.diffDisplayMap.update(wrapWidth)

  if self.document.rope.len > 1:
    self.displayMap.update(wrapWidth)

  self.clearCustomHighlights(errorNodesHighlightId)
  if self.configProvider.getValue("editor.text.highlight-treesitter-errors", true):
    let errorNodes = self.document.getErrorNodesInRange(
      self.visibleTextRange(buffer = 10))
    for node in errorNodes:
      self.addCustomHighlight(errorNodesHighlightId, node, "editorError.foreground", color(1, 1, 1, 0.3))

  self.updateInlayHintsAfterChange()
  let visibleRange = self.visibleTextRange
  if visibleRange != self.lastInlayHintDisplayRange:
    self.lastInlayHintDisplayRange = visibleRange
    self.updateInlayHints()

  let newVersion = (self.document.buffer.version, self.selections[^1].last)
  if self.showCompletions and newVersion != self.lastCompletionTrigger:
    if self.completionEngine.isNotNil:
      self.completionEngine.updateCompletions()
    self.lastCompletionTrigger = newVersion

  if self.showCompletions:
    self.updateCompletionsFromEngine()

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
      (selection.first.line, self.document.rope.lastValidIndex(selection.first.line, includeAfter))
    )

    for i in (selection.first.line + 1)..<selection.last.line:
      yield ((i, 0), (i, self.document.rope.lastValidIndex(i, includeAfter)))

    yield ((selection.last.line, 0), selection.last)

proc clearCustomHighlights*(self: TextDocumentEditor, id: Id) =
  ## Removes all custom highlights associated with the given id

  var anyChanges = false
  for highlights in self.customHighlights.mvalues:
    for i in countdown(highlights.high, 0):
      if highlights[i].id == id:
        highlights.removeSwap(i)
        anyChanges = true

  if anyChanges:
    self.markDirty()

proc addCustomHighlight*(self: TextDocumentEditor, id: Id, selection: Selection, color: string,
    tint: Color = color(1, 1, 1)) =
  # customHighlights*: Table[int, seq[(Id, Selection, Color)]]
  for lineSelection in self.splitSelectionIntoLines(selection):
    assert lineSelection.first.line == lineSelection.last.line
    self.customHighlights.withValue(selection.first.line, val):
      val[].add (id, selection, color, tint)
    do:
      self.customHighlights[selection.first.line] = @[(id, selection, color, tint)]
  self.markDirty()

proc clearSigns*(self: TextDocumentEditor, group: string = "") =
  var linesToRemove: seq[int] = @[]
  for line, signs in self.signs.mpairs:
    for i in countdown(signs.high, 0):
      if signs[i].group == group:
        signs.removeSwap(i)
    if signs.len == 0:
      linesToRemove.add line

  for line in linesToRemove:
    self.signs.del line

  self.markDirty()

proc addSign*(self: TextDocumentEditor, id: Id, line: int, text: string, group: string = "",
    tint: Color = color(1, 1, 1)): Id =
  self.signs.withValue(line, val):
    val[].add (id, group, text, tint)
  do:
    self.signs[line] = @[(id, group, text, tint)]
  self.markDirty()

proc updateSearchResultsAsync(self: TextDocumentEditor) {.async.} =
  if self.isUpdatingSearchResults:
    return
  self.isUpdatingSearchResults = true
  defer:
    self.isUpdatingSearchResults = false

  while true:
    let buffer = self.document.buffer.snapshot.clone()
    let searchQuery = self.searchQuery
    if searchQuery.len == 0:
      self.clearCustomHighlights(searchResultsId)
      self.searchResults.setLen(0)
      self.markDirty()
      return

    if self.lastSearchResultUpdate == (buffer.remoteId, buffer.version, searchQuery):
      return

    let t = startTimer()
    let searchResults = await findAllAsync(buffer.visibleText.clone(), searchQuery)
    if self.document.isNil:
      return

    self.searchResults = searchResults
    self.lastSearchResultUpdate = (buffer.remoteId, buffer.version, searchQuery)
    self.clearCustomHighlights(searchResultsId)
    for s in searchResults:
      self.addCustomHighlight(searchResultsId, s.toSelection, "editor.findMatchBackground")

    self.onSearchResultsUpdated.invoke(self)

    if self.document.buffer.remoteId != buffer.remoteId or self.document.buffer.version != buffer.version:
      continue

    if self.searchQuery != searchQuery:
      continue

    self.markDirty()
    break

proc updateSearchResults(self: TextDocumentEditor) =
  asyncSpawn self.updateSearchResultsAsync()

method handleDocumentChanged*(self: TextDocumentEditor) =
  self.selection = (self.clampCursor self.selection.first, self.clampCursor self.selection.last)
  self.updateSearchResults()

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

proc scrollToCursor*(self: TextDocumentEditor, cursor: Cursor, margin: Option[float] = float.none,
    scrollBehaviour = ScrollBehaviour.none, relativePosition: float = 0.5) =
  if self.disableScrolling:
    return

  self.targetPoint = cursor.toPoint.some
  self.targetLineMargin = margin
  self.targetLineRelativeY = relativePosition

  let targetPoint = cursor.toPoint
  let textHeight = self.platform.totalLineHeight
  let displayPoint = self.displayMap.toDisplayPoint(targetPoint)
  let targetDisplayLine = displayPoint.row.int
  let targetLineY = targetDisplayLine.float32 * textHeight + self.interpolatedScrollOffset

  let configMarginRelative = self.configProvider.getValue("text.cursor-margin-relative", true)
  let configMargin = self.cursorMargin.get(self.configProvider.getValue("text.cursor-margin", 0.2))
  let margin = if margin.getSome(margin):
    clamp(margin, 0.0, self.lastContentBounds.h * 0.5 - textHeight * 0.5)
  elif configMarginRelative:
    clamp(configMargin, 0.0, 1.0) * 0.5 * self.lastContentBounds.h
  else:
    clamp(configMargin, 0.0, self.lastContentBounds.h * 0.5 - textHeight * 0.5)

  let center = case scrollBehaviour.get(self.defaultScrollBehaviour):
    of CenterAlways: true
    of CenterOffscreen: targetLineY < 0 or targetLineY + textHeight > self.lastContentBounds.h
    of CenterMargin: targetLineY < margin or targetLineY + textHeight > self.lastContentBounds.h - margin
    of ScrollToMargin: false
    of TopOfScreen: false

  self.nextScrollBehaviour = if center:
    CenterAlways.some
  else:
    scrollBehaviour

  if center:
    self.scrollOffset = self.lastContentBounds.h * relativePosition - textHeight * 0.5 - targetDisplayLine.float * textHeight

  else:
    case scrollBehaviour.get(self.defaultScrollBehaviour)
    of TopOfScreen:
      self.scrollOffset = margin - targetDisplayLine.float * textHeight
    else:
      if targetLineY < margin:
        self.scrollOffset = margin - targetDisplayLine.float * textHeight
      elif targetLineY + textHeight > self.lastContentBounds.h - margin:
        self.scrollOffset = self.lastContentBounds.h - margin - textHeight - targetDisplayLine.float * textHeight

  self.markDirty()

proc scrollToTop*(self: TextDocumentEditor) =
  self.scrollToCursor((0, 0), scrollBehaviour = TopOfScreen.some)

proc centerCursor*(self: TextDocumentEditor, cursor: Cursor, relativePosition: float = 0.5) =
  self.scrollToCursor(cursor, scrollBehaviour = CenterAlways.some, relativePosition = relativePosition)

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
    movement: proc(doc: TextDocumentEditor, c: Cursor, off: int, wrap: bool, includeAfter: bool): Cursor {.gcsafe, raises: [].},
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
  {.gcsafe.}:
    if gServices.getService(DocumentEditorService).getSome(editors):
      if editors.getEditorForId(wrapper.id).getSome(editor):
        if editor of TextDocumentEditor:
          return editor.TextDocumentEditor.some
  return TextDocumentEditor.none

static:
  addTypeMap(TextDocumentEditor, api.TextDocumentEditor, getTextDocumentEditor)

proc toJson*(self: api.TextDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.text")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.TextDocumentEditor, jsonNode: JsonNode) {.raises: [ValueError].} =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc enableAutoReload(self: TextDocumentEditor, enabled: bool) {.expose: "editor.text".} =
  self.document.enableAutoReload(enabled)

proc getFileName(self: TextDocumentEditor): string {.expose: "editor.text".} =
  if self.document.isNil:
    return ""
  return self.document.filename

proc lineCount(self: TextDocumentEditor): int {.expose: "editor.text".} =
  return self.document.numLines

proc lineLength*(self: TextDocumentEditor, line: int): int {.expose: "editor.text".} =
  return self.document.lineLength(line)

proc numDisplayLines*(self: TextDocumentEditor): int {.expose: "editor.text".} =
  return self.displayMap.toDisplayPoint(self.document.rope.summary.lines).row.int + 1

proc displayEndPoint*(self: TextDocumentEditor): DisplayPoint =
  return self.displayMap.toDisplayPoint(self.document.rope.summary.lines)

proc numWrapLines*(self: TextDocumentEditor): int {.expose: "editor.text".} =
  return self.displayMap.wrapMap.endWrapPoint.row.int + 1

proc wrapEndPoint*(self: TextDocumentEditor): WrapPoint =
  return self.displayMap.wrapMap.endWrapPoint

proc screenLineCount(self: TextDocumentEditor): int {.expose: "editor.text".} =
  ## Returns the number of lines that can be shown on the screen
  ## This value depends on the size of the view this editor is in and the font size
  # todo
  return (self.lastContentBounds.h / self.platform.totalLineHeight).int

proc visibleTextRange*(self: TextDocumentEditor, buffer: int = 0): Selection =
  assert self.numDisplayLines > 0
  let baseLine = int(-self.scrollOffset / self.platform.totalLineHeight)
  var displayRange: Range[DisplayPoint]
  displayRange.a.row = clamp(baseLine - buffer, 0, self.numDisplayLines - 1).uint32
  displayRange.b.row = clamp(baseLine + self.screenLineCount + buffer + 1, 0, self.numDisplayLines - 1).uint32
  # result.last.column = self.document.rope.lastValidIndex(result.last.line)
  result.first = self.displayMap.toPoint(displayRange.a).toCursor
  result.last = self.displayMap.toPoint(displayRange.b).toCursor

proc doMoveCursorLine(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool = false, includeAfter: bool = false): Cursor {.expose: "editor.text".} =
  var cursor = cursor
  let line = cursor.line + offset
  if line < 0:
    cursor = (0, cursor.column)
  elif line >= self.document.numLines:
    cursor = (self.document.numLines - 1, cursor.column)
  else:
    cursor.line = line
    let wrapPoint = self.displayMap.toWrapPoint(Point.init(line, 0))
    cursor.column = self.displayMap.toPoint(wrapPoint(wrapPoint.row.int, self.targetColumn)).column.int
  return self.clampCursor(cursor, includeAfter)

proc getLastRenderedVisualLine(self: TextDocumentEditor, line: int): Option[StyledLine] =
  # todo
  for l in self.lastRenderedLines:
    if l.index == line:
      return l.some

proc getPartContaining(line: StyledLine, column: int): Option[ptr StyledText] =
  for i in countdown(line.parts.high, 0):
    template part: untyped = line.parts[i]
    if part.visualRange.isSome:
      if column in part.textRange.get.startOffset..part.textRange.get.endOffset:
        return part.addr.some

proc getPartContainingVisual(line: StyledLine, subLine: int, visualColumn: int): Option[ptr StyledText] =
  var closest = int.high
  for part in line.parts.mitems:
    if part.visualRange.getSome(r) and r.subLine == subLine:

      if visualColumn in part.visualRange.get.startColumn..<part.visualRange.get.endColumn:
        closest = 0
        return part.addr.some
      else:
        let distance = min(
          (visualColumn - part.visualRange.get.startColumn).abs,
          (visualColumn - part.visualRange.get.endColumn + 1).abs,
        )
        if distance < closest:
          closest = distance
          result = part.addr.some

proc numSubLines(line: StyledLine): int =
  for i in countdown(line.parts.high, 0):
    if line.parts[i].visualRange.getSome(r):
      return r.subLine + 1

proc doMoveCursorVisualLine(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool = false, includeAfter: bool = false): Cursor {.expose: "editor.text".} =
  let wrapPointOld = self.displayMap.toWrapPoint(cursor.toPoint)
  let wrapPoint = wrapPoint(max(wrapPointOld.row.int + offset, 0), self.targetColumn).clamp(wrapPoint()...self.wrapEndPoint)
  let newCursor = self.displayMap.toPoint(wrapPoint, if offset < 0: Bias.Left else: Bias.Right).toCursor
  if offset < 0 and newCursor.line > 0 and newCursor.line == cursor.line and self.displayMap.toWrapPoint(newCursor.toPoint).row == wrapPointOld.row:
    let newCursor2 = point(cursor.line - 1, self.document.rope.lineLen(cursor.line - 1))
    let displayPoint = self.displayMap.toDisplayPoint(newCursor2)
    let displayPoint2 = displayPoint(displayPoint.row, self.targetColumn.uint32)
    let point = self.displayMap.toPoint(displayPoint2)

    # echo &"doMoveCursorVisualLine {cursor}, {offset} -> {newCursor2} -> {displayPoint} -> {displayPoint2} -> {point}"
    return point.toCursor
  elif offset > 0:
    # go to wrap point and back to point one more time because if we land inside of e.g an overlay then the position will
    # be clamped which can screw up the target column we set before, so we need to calculate the target column again.
    let wrapPoint2 = wrapPoint(self.displayMap.toWrapPoint(newCursor.toPoint).row, self.targetColumn).clamp(wrapPoint()...self.wrapEndPoint)
    let newCursor2 = self.displayMap.toPoint(wrapPoint2, if offset < 0: Bias.Left else: Bias.Right).toCursor

    # echo &"doMoveCursorVisualLine {cursor}, {offset} -> {newCursor}, wp: {wrapPointOld} -> {wrapPoint} -> {self.displayMap.toWrapPoint(newCursor.toPoint)}, {wrapPoint2} -> {newCursor2}"
    if newCursor2.line >= self.document.numLines:
      return cursor
    return self.clampCursor(newCursor2, includeAfter)

  if newCursor.line >= self.document.numLines:
    return cursor
  return self.clampCursor(newCursor, includeAfter)

proc doMoveCursorHome(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor {.expose: "editor.text".} =
  return (cursor.line, 0)

proc doMoveCursorEnd(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor {.expose: "editor.text".} =
  return (cursor.line, self.document.rope.lastValidIndex cursor.line)

proc doMoveCursorVisualHome(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor {.expose: "editor.text".} =
  var wrapPoint = self.displayMap.toWrapPoint(cursor.toPoint)
  wrapPoint.column = 0
  let newCursor = self.displayMap.toPoint(wrapPoint).toCursor
  return self.clampCursor(newCursor, includeAfter)

proc doMoveCursorVisualEnd(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor {.expose: "editor.text".} =
  if self.getLastRenderedVisualLine(cursor.line).getSome(line) and
      line.getPartContaining(cursor.column).getSome(part):

    let r = part[].visualRange.get
    if line.getPartContainingVisual(r.subLine, int.high).getSome(part):
      if includeAfter:
        return (cursor.line, part[].textRange.get.endOffset)
      else:
        return (cursor.line, part[].textRange.get.endOffset - 1)

  return (cursor.line, self.document.rope.lastValidIndex cursor.line)

proc doMoveCursorPrevFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool, includeAfter: bool): Cursor {.expose: "editor.text".} =
  return self.getPrevFindResult(cursor, offset, includeAfter=includeAfter).first

proc doMoveCursorNextFindResult(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool, includeAfter: bool): Cursor {.expose: "editor.text".} =
  return self.getNextFindResult(cursor, offset, includeAfter=includeAfter).first

proc doMoveCursorLineCenter(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor {.expose: "editor.text".} =
  return (cursor.line, self.document.lineLength(cursor.line) div 2)

proc doMoveCursorCenter(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool,
    includeAfter: bool): Cursor {.expose: "editor.text".} =
  # todo
  if self.lastRenderedLines.len == 0:
    return cursor

  let r = self.visibleTextRange()
  let line = clamp((r.first.line + r.last.line) div 2, 0, self.document.numLines - 1)
  let column = self.document.visualColumnToCursorColumn(line, self.targetColumn)
  return (line, column)

proc doMoveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int,
    wrap: bool = true, includeAfter: bool = true): Cursor {.expose: "editor.text".} =
  var cursor = cursor

  if cursor.line notin 0..<self.document.numLines:
    return cursor

  var c = self.document.rope.cursorT(cursor.toPoint)
  var lastIndex = self.document.rope.lastValidIndex(cursor.line, includeAfter)

  if offset > 0:
    for i in 0..<offset:
      if cursor.column >= lastIndex:
        if not wrap:
          break
        if cursor.line < self.document.numLines - 1:
          cursor.line = cursor.line + 1
          cursor.column = 0
          lastIndex = self.document.rope.lastValidIndex(cursor.line, includeAfter)
          c.seekForward(point(cursor.line, 0))
          continue
        else:
          cursor.column = lastIndex
          break

      c.seekNextRune()
      cursor = c.position.toCursor

  elif offset < 0:
    for i in 0..<(-offset):
      if cursor.column == 0:
        if not wrap:
          break
        if cursor.line > 0:
          cursor.line = cursor.line - 1
          lastIndex = self.document.rope.lastValidIndex(cursor.line, includeAfter)
          c.seekPrevRune()
          if not includeAfter:
            c.seekPrevRune()
          cursor.column = lastIndex
          continue
        else:
          cursor.column = 0
          break

      c.seekPrevRune()
      cursor = c.position.toCursor

  return self.clampCursor(cursor, includeAfter)

proc includeSelectionEnd*(self: TextDocumentEditor, res: Selection, includeAfter: bool = true): Selection {.expose: "editor.text".} =
    result = res
    if not includeAfter:
      result = (res.first, self.doMoveCursorColumn(res.last, -1, wrap = false))

proc findSurroundStart*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char,
    depth: int = 1): Option[Cursor] {.expose: "editor.text".} =
  var depth = depth
  var res = cursor

  # todo: use RopeCursor
  while res.line >= 0:
    let line = editor.document.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column >= 0:
      let c = line.charAt(res.column)
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

  # todo: use RopeCursor
  while res.line < lineCount:
    let line = editor.document.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column < line.len:
      let c = line.charAt(res.column)
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

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  let oldMode = self.currentMode
  self.currentMode = mode

  self.updateModeEventHandlers()

  self.plugins.handleModeChanged(self, oldMode, self.currentMode)

  self.markDirty()

proc mode*(self: TextDocumentEditor): string {.expose("editor.text").} =
  ## Returns the current mode of the text editor, or "" if there is no mode
  return self.currentMode

proc getContextWithMode(self: TextDocumentEditor, context: string): string {.expose("editor.text").} =
  ## Appends the current mode to context
  return context & "." & $self.currentMode

proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor = Last) {.
    expose("editor.text").} =
  let cursor = self.getCursor(cursor)
  let wrapPoint = self.displayMap.toWrapPoint(cursor.toPoint)
  self.targetColumn = wrapPoint.column.int

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

proc getLine*(self: TextDocumentEditor, line: int): string {.expose("editor.text").} =
  return $self.document.getLine(line)

proc insert*(self: TextDocumentEditor, selections: seq[Selection], text: string, notify: bool = true,
    record: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.edit(selections, self.selections, [text], notify, record)

proc insertMulti*(self: TextDocumentEditor, selections: seq[Selection], texts: seq[string], notify: bool = true,
    record: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.edit(selections, self.selections, texts, notify, record)

proc delete*(self: TextDocumentEditor, selections: seq[Selection], notify: bool = true,
    record: bool = true, inclusiveEnd: bool = false): seq[Selection] {.expose("editor.text").} =
  return self.document.edit(selections, self.selections, [""], notify, record, inclusiveEnd=inclusiveEnd)

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
  selection.last.column = self.document.rope.lastValidIndex(selection.last.line)
  if selection.last.line < self.document.numLines - 1:
    selection.last = (selection.last.line + 1, 0)
  elif selection.first.line > 0:
    selection.first = (selection.first.line - 1, self.document.rope.lastValidIndex(selection.first.line - 1))
  discard self.document.edit([selection], oldSelections, [""])

proc selectPrev(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popLast
    assert selection.len > 0, "[selectPrev] Empty selection"
    self.selectionHistory.addFirst self.selections
    self.selectionsInternal = selection
    self.cursorVisible = true
    if self.blinkCursorTask.isNotNil and self.active:
      self.blinkCursorTask.reschedule()
  self.scrollToCursor(self.selection.last)
  self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

proc selectNext(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popFirst
    assert selection.len > 0, "[selectNext] Empty selection"
    self.selectionHistory.addLast self.selections
    self.selectionsInternal = selection
    self.cursorVisible = true
    if self.blinkCursorTask.isNotNil and self.active:
      self.blinkCursorTask.reschedule()
  self.scrollToCursor(self.selection.last)
  self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

proc selectInside*(self: TextDocumentEditor, cursor: Cursor) {.expose("editor.text").} =
  self.selection = self.getSelectionForMove(cursor, "word")
  # todo
  # let regex = re("[a-zA-Z0-9_]")
  # var first = cursor.column
  # # echo self.document.getLine(cursor.line), ", ", first, ", ",
  #   self.document.getLine(cursor.line).matchLen(regex, start = first - 1)
  # while first > 0 and self.document.getLine(cursor.line).matchLen(regex, start = first - 1) == 1:
  #   first -= 1
  # var last = cursor.column
  # while last < self.document.lineLength(cursor.line) and
  #   self.document.getLine(cursor.line).matchLen(regex, start = last) == 1:
  #   last += 1
  # self.selection = ((cursor.line, first), (cursor.line, last))

proc selectInsideCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selection = self.extendSelectionWithMove(self.selection, "word")

proc selectLine*(self: TextDocumentEditor, line: int) {.expose("editor.text").} =
  self.selection = ((line, 0), (line, self.document.rope.lastValidIndex(line)))

proc selectLineCurrent(self: TextDocumentEditor) {.expose("editor.text").} =
  let first = (
    (self.selection.first.line, 0),
    (self.selection.first.line, self.document.rope.lastValidIndex(self.selection.first.line))
  )
  let last = (
    (self.selection.last.line, 0),
    (self.selection.last.line, self.document.rope.lastValidIndex(self.selection.last.line))
  )
  let wasBackwards = self.selection.isBackwards
  self.selection = first or last
  if wasBackwards:
    self.selection = self.selection.reverse

proc getParentNodeSelection(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true): Selection {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    return selection

  let tree = self.document.tsTree

  var node = self.document.tsTree.root.descendantForRange(selection.tsRange)
  while node != tree.root:
    var r = self.includeSelectionEnd(node.getRange.toSelection, includeAfter)
    if r != selection:
      break

    node = node.parent

  result = node.getRange.toSelection
  result = self.includeSelectionEnd(result, includeAfter)

proc getNextNamedSiblingNodeSelection(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true): Option[Selection] {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    return Selection.none

  let tree = self.document.tsTree
  var node = tree.root.descendantForRange(selection.tsRange)
  while node != tree.root:
    if node.nextNamed.getSome(nextNode):
      return self.includeSelectionEnd(nextNode.getRange.toSelection, includeAfter).some

    node = node.parent
    let r = self.includeSelectionEnd(node.getRange.toSelection, includeAfter)
    if r != selection:
      break

  return Selection.none

proc getNextSiblingNodeSelection(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true): Option[Selection] {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    return Selection.none

  let tree = self.document.tsTree
  var node = tree.root.descendantForRange(selection.tsRange)
  while node != tree.root:
    if node.next.getSome(nextNode):
      return self.includeSelectionEnd(nextNode.getRange.toSelection, includeAfter).some

    node = node.parent
    let r = self.includeSelectionEnd(node.getRange.toSelection, includeAfter)
    if r != selection:
      break

  return Selection.none

proc getParentNodeSelections(self: TextDocumentEditor, selections: Selections, includeAfter: bool = true): Selections {.expose("editor.text").} =
  return selections.mapIt(self.getParentNodeSelection(it, includeAfter))

proc selectParentTs(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true) {.expose("editor.text").} =
  if self.document.tsTree.isNil:
    return
  self.selection = self.getParentNodeSelection(selection, includeAfter)

proc printTreesitterMemoryUsage*(self: TextDocumentEditor) {.expose("editor.text").} =
  let allocated = custom_treesitter.tsAllocated
  let freed = custom_treesitter.tsFreed
  log lvlInfo, &"Treesitter allocated: {allocated.float / 1000000.0} MB, freed: {freed.float / 1000000.0} MB, total: {(allocated - freed).float / 1000000.0} MB"

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

proc selectParentCurrentTs*(self: TextDocumentEditor, includeAfter: bool = true) {.expose("editor.text").} =
  self.selections = self.getParentNodeSelections(self.selections, includeAfter)

proc getNextNodeWithSameType*(self: TextDocumentEditor, selection: Selection, offset: int = 0,
    includeAfter: bool = true, wrap: bool = true, stepIn: bool = true, stepOut: bool = true): Option[Selection] {.expose("editor.text").} =

  if self.document.tsTree.isNil:
    return Selection.none

  let selectionRange = selection.tsRange
  let originalNode = self.document.tsTree.root.descendantForRange(selectionRange)
  let targetType = originalNode.nodeType

  var targetNode = TSNode.none
  originalNode.withTreeCursor(cursor):
    var indentLevel = cursor.currentDepth
    var down = true
    var node = originalNode

    while true:
      if cursor.currentNode != originalNode and cursor.currentNode.nodeType == targetType:
        targetNode = cursor.currentNode.some
        break

      if down and stepIn and cursor.gotoFirstChild():
        indentLevel += 1
        continue

      if cursor.gotoNextSibling():
        down = true
        continue

      if (cursor.currentNode != node or stepOut) and cursor.gotoParent():
        indentLevel -= 1
        down = false
        continue

      if cursor.currentNode == node:
        let prevNode = node
        node = node.parent
        if node.isNull:
          break

        cursor.reset(node)

        assert cursor.gotoFirstChild()
        while cursor.currentNode != prevNode:
          assert cursor.gotoNextSibling()

        down = false
        continue

      break

  if targetNode.getSome(targetNode):
    var res = targetNode.getRange.toSelection
    res = self.includeSelectionEnd(res, includeAfter)
    return res.some

  return Selection.none

proc shouldShowCompletionsAt*(self: TextDocumentEditor, cursor: Cursor): bool {.expose("editor.text").} =
  ## Returns true if the completion window should automatically open at the given position
  # todo: use RopeCursor
  let line = self.document.getLine(cursor.line)
  if cursor.column <= 0 or cursor.column > line.len:
    return false

  let previousRune = line.runeAt(line.clip(cursor.column - 1, Bias.Left))
  let wordChars = self.document.languageConfig.mapIt(it.completionWordChars).get(IdentChars)
  let extraTriggerChars = if self.document.completionTriggerCharacters.len > 0:
    self.document.completionTriggerCharacters
  else:
    {'.'}

  let allTriggerChars = wordChars + extraTriggerChars

  if previousRune.int <= char.high.int and previousRune.char in allTriggerChars:
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
      # todo: don't use getLine
      for c in self.document.getLine(selection.first.line).chars:
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
        # todo: don't use getLine
        let line = $self.document.getLine(selection.last.line)
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

      # todo: don't use getLine
      let closeIndent = self.document.getLine(s.first.line).firstNonWhitespace
      if closeIndent != s.first.column:
        # Closing paren is not at beginning of line, don't apply auto indent
        texts.add text
        continue

      # todo: don't use getLine
      let openIndent = self.document.getLine(openLocation.line).firstNonWhitespace
      if openIndent == closeIndent:
        # Indent is already correct, just insert the paren
        texts.add text
        continue

      # Copy indent of opening parens line
      # todo: don't use getLine
      let indent = $self.document.getLine(openLocation.line).slice(0...openIndent)
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
        if l == selection.first.line and selection.first.column == self.document.lineLength(l):
          continue
        if l == selection.last.line and selection.last.column == 0:
          continue
      linesToIndent.incl l

  let indent = self.document.indentStyle.getString()
  var indentSelections: Selections = @[]
  for l in linesToIndent:
    indentSelections.add (l, 0).toSelection

  discard self.document.edit(indentSelections.normalized, self.selections, [indent])

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
        if l == selection.first.line and selection.first.column == self.document.lineLength(l):
          continue
        if l == selection.last.line and selection.last.column == 0:
          continue
      linesToIndent.incl l

  var indentSelections: Selections = @[]
  for l in linesToIndent:
    case self.document.indentStyle.kind
    of Spaces:
      let firstNonWhitespace = self.document.rope.indentBytes(l)
      indentSelections.add ((l, 0), (l, min(self.document.indentStyle.indentColumns, firstNonWhitespace)))
    of Tabs:
      indentSelections.add ((l, 0), (l, 1))

  var selections = self.selections
  discard self.document.edit(indentSelections.normalized, self.selections, [""])

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
    self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

proc redo*(self: TextDocumentEditor, checkpoint: string = "word") {.expose("editor.text").} =
  if self.document.redo(self.selections, true, checkpoint).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)
    self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

proc addNextCheckpoint*(self: TextDocumentEditor, checkpoint: string) {.expose("editor.text").} =
  self.document.addNextCheckpoint checkpoint

proc copyAsync*(self: TextDocumentEditor, register: string, inclusiveEnd: bool): Future[void] {.async.} =
  log lvlInfo, fmt"copy register into '{register}', inclusiveEnd: {inclusiveEnd}"
  var text = Rope.new()
  var c = self.document.rope.cursorT(Point)

  for i, selection in self.selections:
    let selection = selection.normalized

    if i > 0:
      text.add "\n"

    if c.position.toCursor > selection.first:
      c.resetCursor()
    c.seekForward(selection.first.toPoint)

    var target = selection.last
    if inclusiveEnd and target.column < self.document.lineLength(target.line):
      target.column += 1

    text.add(c.sliceRope(target.toPoint, Bias.Right))

  self.registers.setRegisterAsync(register, Register(kind: Rope, rope: text.move)).await

proc copy*(self: TextDocumentEditor, register: string = "", inclusiveEnd: bool = false) {.
    expose("editor.text").} =
  asyncSpawn self.copyAsync(register, inclusiveEnd)

proc pasteAsync*(self: TextDocumentEditor, registerName: string, inclusiveEnd: bool = false):
    Future[void] {.async.} =
  log lvlInfo, fmt"paste register from '{registerName}', inclusiveEnd: {inclusiveEnd}"

  var register: Register
  if not self.registers.getRegisterAsync(registerName, register.addr).await:
    return

  if self.document.isNil:
    return

  let numLines = register.numLines()

  let newSelections = if numLines == self.selections.len and numLines > 1:
    case register.kind
    of RegisterKind.Text:
      let lines = register.text.splitLines()
      self.document.edit(self.selections, self.selections, lines, notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
    of RegisterKind.Rope:
      let lines = register.rope.splitLines()
      self.document.edit(self.selections, self.selections, lines, notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
  else:
    case register.kind
    of RegisterKind.Text:
      self.document.edit(self.selections, self.selections, [register.text.move], notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
    of RegisterKind.Rope:
      self.document.edit(self.selections, self.selections, [register.rope.move], notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)

  # add list of selections for what was just pasted to history
  if newSelections.len == self.selections.len:
    var tempSelections = newSelections
    for i in 0..tempSelections.high:
      tempSelections[i].first = self.selections[i].first
    self.selections = tempSelections

  self.selections = newSelections
  self.scrollToCursor(Last)
  self.markDirty()

proc paste*(self: TextDocumentEditor, registerName: string = "", inclusiveEnd: bool = false) {.
    expose("editor.text").} =
  asyncSpawn self.pasteAsync(registerName, inclusiveEnd)

proc scrollText*(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.scrollOffset += amount
  self.markDirty()

proc scrollLines(self: TextDocumentEditor, amount: int) {.expose("editor.text").} =
  ## Scroll the text up (positive) or down (negative) by the given number of lines

  if self.disableScrolling:
    return

  self.scrollOffset += self.platform.totalLineHeight * amount.float

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

  if self.searchResults.len == 0:
    return cursor.toSelection

  var i = 0
  let (found, index) = self.searchResults.binarySearchRange(cursor.toPoint, Bias.Left, (r, p) => cmp(r.a, p))
  if found:
    if index > 0:
      result = self.searchResults[index - 1].toSelection
    elif wrap:
      result = self.searchResults.last.toSelection
    else:
      return cursor.toSelection
  elif index == 0 and cursor.toPoint < self.searchResults[0].a:
    if wrap:
      result = self.searchResults.last.toSelection
    else:
      return cursor.toSelection
  elif index >= 0:
    result = self.searchResults[index].toSelection
  else:
    return cursor.toSelection

  if not includeAfter:
    result.last = self.doMoveCursorColumn(result.last, -1, wrap = false)

proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
    includeAfter: bool = true, wrap: bool = true): Selection {.expose("editor.text").} =
  self.updateSearchResults()

  if self.searchResults.len == 0:
    return cursor.toSelection

  var i = 0
  let (found, index) = self.searchResults.binarySearchRange(cursor.toPoint, Bias.Right, (r, p) => cmp(r.a, p))
  if found:
    if index < self.searchResults.high:
      result = self.searchResults[index + 1].toSelection
    elif wrap:
      result = self.searchResults[0].toSelection
    else:
      return cursor.toSelection
  elif index == self.searchResults.len:
    if wrap:
      result = self.searchResults[0].toSelection
    else:
      return cursor.toSelection
  elif index >= 0 and index <= self.searchResults.high:
    result = self.searchResults[index].toSelection
  else:
    return cursor.toSelection

  if not includeAfter:
    result.last = self.doMoveCursorColumn(result.last, -1, wrap = false)

proc createAnchors*(self: TextDocumentEditor, selections: Selections): seq[(Anchor, Anchor)] {.expose("editor.text").} =
  let snapshot {.cursor.} = self.document.buffer.snapshot
  return selections.mapIt (snapshot.anchorAfter(it.first.toPoint), snapshot.anchorBefore(it.last.toPoint))

proc resolveAnchors*(self: TextDocumentEditor, anchors: seq[(Anchor, Anchor)]): Selections {.expose("editor.text").} =
  return anchors.mapIt (it[0].summaryOpt(Point, self.snapshot).get(Point()), it[1].summaryOpt(Point, self.snapshot).get(Point())).toSelection

proc getPrevDiagnostic*(self: TextDocumentEditor, cursor: Cursor, severity: int = 0,
    offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection {.expose("editor.text").} =

  self.document.resolveDiagnosticAnchors()

  var i = 0
  for line in countdown(cursor.line, 0):
    self.document.diagnosticsPerLine.withValue(line, val):
      let diagnosticsOnCurrentLine {.cursor.} = val[]
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

  self.document.resolveDiagnosticAnchors()

  var i = 0
  for line in cursor.line..<self.document.numLines:
    self.document.diagnosticsPerLine.withValue(line, val):
      for diagnosticIndex in val[]:
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
  self.showDiff = false
  self.displayMap.diffMap.clear()
  self.diffDisplayMap = DisplayMap.new()
  discard self.diffDisplayMap.wrapMap.onUpdated.subscribe (args: (WrapMap, WrapMapSnapshot)) => self.handleWrapMapUpdated(args[0], args[1])
  discard self.diffDisplayMap.onUpdated.subscribe (args: (DisplayMap,)) => self.handleDisplayMapUpdated(args[0])

  self.diffDocument.onRequestRerender.unsubscribe(self.onRequestRerenderDiffHandle)
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

  inc self.diffRevision
  let revision = self.diffRevision

  let localizedPath = self.document.localizedPath
  let vcs = self.vcs.getVcsForFile(localizedPath).getOr:
    log lvlWarn, fmt"[updateDiffAsync] File is not part of any vcs: '{localizedPath}'"
    return

  log lvlInfo, fmt"Diff document '{localizedPath}'"

  let relPath = self.workspace.getRelativePathSync(localizedPath).get(localizedPath)
  if self.document.isNil or self.diffRevision > revision or not self.showDiff:
    return

  if self.document.staged:
    let committedFileContent = vcs.getCommittedFileContent(relPath).await
    if self.document.isNil or self.diffRevision > revision or not self.showDiff:
      return

    let stagedFileContent = vcs.getStagedFileContent(relPath).await
    if self.document.isNil or self.diffRevision > revision or not self.showDiff:
      return

    let changes = vcs.getFileChanges(relPath, staged = true).await
    if self.document.isNil or self.diffRevision > revision or not self.showDiff:
      return

    # Note: this currently clears the diff document
    self.document.content = stagedFileContent

    if self.diffDocument.isNil:
      self.diffDocument = newTextDocument(self.services, language=self.document.languageId.some, createLanguageServer = false)
      self.onRequestRerenderDiffHandle = self.diffDocument.onRequestRerender.subscribe () =>
        self.markDirty()

    self.diffChanges = changes
    self.diffDocument.languageId = self.document.languageId
    self.diffDocument.readOnly = true
    self.diffDocument.content = committedFileContent

  else:
    let stagedFileContent = vcs.getStagedFileContent(relPath).await
    if self.document.isNil or self.diffRevision > revision or not self.showDiff:
      return

    let changes = vcs.getFileChanges(relPath, staged = false).await
    if self.document.isNil or self.diffRevision > revision or not self.showDiff:
      return

    if self.diffDocument.isNil:
      self.diffDocument = newTextDocument(self.services, language=self.document.languageId.some, createLanguageServer = false)
      self.onRequestRerenderDiffHandle = self.diffDocument.onRequestRerender.subscribe () =>
        self.markDirty()

    self.diffChanges = changes
    self.diffDocument.languageId = self.document.languageId
    self.diffDocument.readOnly = true
    self.diffDocument.content = stagedFileContent

  assert self.diffDocument.isNotNil
  self.diffDisplayMap.setBuffer(self.diffDocument.buffer.snapshot.clone())
  self.displayMap.diffMap.update(self.diffChanges, self.diffDisplayMap.wrapMap.snapshot, reverse = true)
  self.diffDisplayMap.diffMap.update(self.diffChanges, self.displayMap.wrapMap.snapshot, reverse = false)

  if gotoFirstDiff and self.diffChanges.getSome(changes) and changes.len > 0:
    self.selection = (changes[0].target.first, 0).toSelection
    self.updateTargetColumn(Last)
    self.centerCursor(self.selection.last)

  self.markDirty()

proc testReplace*(self: TextDocumentEditor) {.expose("editor.text").} =
  for s in self.selections:
    var s = s.normalized
    s.last = self.doMoveCursorColumn(s.last, 1, wrap = false, includeAfter = true)
    self.displayMap.overlay.addOverlay(s.first.toPoint...s.last.toPoint, self.document.contentString(s).toUpperAscii, 1)
  self.markDirty()

proc testReplaceLonger*(self: TextDocumentEditor) {.expose("editor.text").} =
  for s in self.selections:
    var s = s.normalized
    s.last = self.doMoveCursorColumn(s.last, 1, wrap = false, includeAfter = true)
    self.displayMap.overlay.addOverlay(s.first.toPoint...s.last.toPoint, "<>" & self.document.contentString(s).toUpperAscii & "</>", 2)
  self.markDirty()

proc testReplaceShorter*(self: TextDocumentEditor) {.expose("editor.text").} =
  for s in self.selections:
    var s = s.normalized
    s.last = self.doMoveCursorColumn(s.last, 1, wrap = false, includeAfter = true)
    self.displayMap.overlay.addOverlay(s.first.toPoint...s.last.toPoint, self.document.contentString(s).toUpperAscii[1..^2], 3)
  self.markDirty()

proc testReplaceShort*(self: TextDocumentEditor) {.expose("editor.text").} =
  for s in self.selections:
    var s = s.normalized
    s.last = self.doMoveCursorColumn(s.last, 1, wrap = false, includeAfter = true)
    self.displayMap.overlay.addOverlay(s.first.toPoint...s.last.toPoint, "...", 4)
  self.markDirty()

proc testInsertNewLine*(self: TextDocumentEditor) {.expose("editor.text").} =
  for s in self.selections:
    var s = s.normalized
    s.last = self.doMoveCursorColumn(s.last, 1, wrap = false, includeAfter = true)
    let p = point(s.first.line + 1, 0)
    self.displayMap.overlay.addOverlay(p...p, " ".repeat(s.first.column) & "^----- you are here!\n", 5)
  self.markDirty()

proc testInsert*(self: TextDocumentEditor) {.expose("editor.text").} =
  for s in self.selections:
    var s = s.normalized
    s.last = self.doMoveCursorColumn(s.last, 1, wrap = false, includeAfter = true)
    self.displayMap.overlay.addOverlay(s.first.toPoint...s.first.toPoint, "hellope", 6)
  self.markDirty()

proc clearOverlays*(self: TextDocumentEditor, id: int = -1) {.expose("editor.text").} =
  self.displayMap.overlay.clear(id)

proc updateDiff*(self: TextDocumentEditor, gotoFirstDiff: bool = false) {.expose("editor.text").} =
  self.showDiff = true
  asyncSpawn self.updateDiffAsync(gotoFirstDiff)

proc stageFileAsync(self: TextDocumentEditor): Future[void] {.async.} =
  if self.vcs.getVcsForFile(self.document.filename).getSome(vcs):
    let res = await vcs.stageFile(self.document.localizedPath)

    if self.diffDocument.isNotNil:
      self.updateDiff()

proc stageFile*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.stageFileAsync()

proc format*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.document.format(runOnTempFile = true)

proc checkoutFileAsync*(self: TextDocumentEditor) {.async.} =
  if self.document.isNil:
    return

  let path = self.document.localizedPath
  let vcs = self.vcs.getVcsForFile(path).getOr:
    log lvlError, fmt"No vcs assigned to document '{path}'"
    return

  let res = await vcs.checkoutFile(path)
  if self.document.isNil:
    return

  log lvlInfo, &"Checkout result: {res}"

  self.document.setReadOnly(self.vfs.getFileAttributes(path).await.mapIt(not it.writable).get(false))
  self.markDirty()

proc checkoutFile*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.checkoutFileAsync()

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
  for s in self.searchResults:
    selections.add s.toSelection
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

proc moveCursorVisualLine*(self: TextDocumentEditor, distance: int,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true,
    includeAfter: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorVisualLine, distance, all, wrap, includeAfter)

proc moveCursorHome*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorHome, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorEnd*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true, includeAfter: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorEnd, 0, all, includeAfter=includeAfter)
  self.updateTargetColumn(cursor)

proc moveCursorVisualHome*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorVisualHome, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorVisualEnd*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true, includeAfter: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorVisualEnd, 0, all, includeAfter=includeAfter)
  self.updateTargetColumn(cursor)

proc moveCursorTo*(self: TextDocumentEditor, str: string,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  proc doMoveCursorTo(self: TextDocumentEditor, cursor: Cursor, offset: int,
      wrap: bool = true, includeAfter: bool = true): Cursor =
    # todo: use RopeCursor
    let line = self.document.getLine cursor.line
    result = cursor
    let index = line.suffix(cursor.column + 1).find(str)
    if index >= 0:
      result = (cursor.line, index + cursor.column + 1)
  self.moveCursor(cursor, doMoveCursorTo, 0, all)
  self.updateTargetColumn(cursor)

proc moveCursorBefore*(self: TextDocumentEditor, str: string,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  proc doMoveCursorBefore(self: TextDocumentEditor, cursor: Cursor, offset: int,
      wrap: bool = true, includeAfter: bool = true): Cursor =
    # todo: use RopeCursor
    let line = self.document.getLine cursor.line
    result = cursor
    let index = line.suffix(cursor.column).find(str)
    if index > 0:
      result = (cursor.line, index - 1 + cursor.column)

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

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    margin: Option[float] = float.none, scrollBehaviour: Option[ScrollBehaviour] = ScrollBehaviour.none, relativePosition: float = 0.5) {.expose("editor.text").} =
  self.scrollToCursor(self.getCursor(cursor), margin, scrollBehaviour, relativePosition)

proc setNextScrollBehaviour*(self: TextDocumentEditor, scrollBehaviour: ScrollBehaviour) {.expose("editor.text").} =
  self.nextScrollBehaviour = scrollBehaviour.some

proc setDefaultSnapBehaviour*(self: TextDocumentEditor, snapBehaviour: ScrollSnapBehaviour) {.expose("editor.text").} =
  self.defaultSnapBehaviour = snapBehaviour

proc setNextSnapBehaviour*(self: TextDocumentEditor, snapBehaviour: ScrollSnapBehaviour) {.expose("editor.text").} =
  self.nextSnapBehaviour = snapBehaviour.some
  if snapBehaviour == Always:
    self.interpolatedScrollOffset = self.scrollOffset

proc setCursorScrollOffset*(self: TextDocumentEditor, offset: float,
    cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  let displayPoint = self.displayMap.toDisplayPoint(self.getCursor(cursor).toPoint)
  self.scrollOffset = offset - displayPoint.row.float * self.platform.totalLineHeight
  self.markDirty()

proc getContentBounds*(self: TextDocumentEditor): Vec2 {.expose("editor.text").} =
  # todo
  return self.lastContentBounds.wh

proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.
    expose("editor.text").} =
  self.centerCursor(self.getCursor(cursor))

proc reloadTreesitter*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Reload the treesitter parser and queries for the language of the current document.
  log(lvlInfo, "reloadTreesitter")

  unloadTreesitterLanguage(self.document.languageId)
  for doc in self.editors.getAllDocuments():
    if doc of TextDocument:
      let doc = doc.TextDocument
      if doc.languageId == self.document.languageId:
        doc.reloadTreesitterLanguage()

proc deleteLeft*(self: TextDocumentEditor) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (self.doMoveCursorColumn(selection.first, -1), selection.first)

  # echo &"delete left {self.selections} -> {selections}"
  self.selections = self.document.edit(selections, self.selections, [""],
    inclusiveEnd=self.useInclusiveSelections)

  if not self.disableCompletions:
    self.autoShowCompletions()

proc deleteRight*(self: TextDocumentEditor, includeAfter: bool = true) {.expose("editor.text").} =
  var selections = self.selections
  for i, selection in selections:
    if selection.isEmpty:
      selections[i] = (selection.first, self.doMoveCursorColumn(selection.first, 1))

  self.selections = self.document.edit(selections, self.selections, [""],
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

proc runAction*(self: TextDocumentEditor, action: string, args: JsonNode): Option[JsonNode] {.
    expose("editor.text").} =
  # echo "runAction ", action, ", ", $args
  return self.handleActionInternal(action, args)

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
    # todo: use RopeCursor
    let line = self.document.getLine cursor.line
    result = self.findWordBoundary(cursor)
    if cursor.column == 0 and cursor.line > 0:
      result.first = (cursor.line - 1, self.document.lineLength(cursor.line - 1))
    if cursor.column == line.len and cursor.line < self.document.numLines - 1:
      result.last = (cursor.line + 1, 0)

    for _ in 1..<count:
      result = result or self.findWordBoundary(result.last) or self.findWordBoundary(result.first)
      let line = self.document.getLine result.last.line
      if result.first.column == 0 and result.first.line > 0:
        result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))
      if result.last.column == line.len and result.last.line < self.document.numLines - 1:
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

  of "visual-line":
    let wrapPoint = self.displayMap.toWrapPoint(cursor.toPoint)
    let displayLineStart = wrapPoint(wrapPoint.row)
    let displayLineEnd = wrapPoint(wrapPoint.row + 1)
    result[0] = self.displayMap.toPoint(displayLineStart, Right).toCursor
    result[1] = self.displayMap.toPoint(displayLineEnd, Right).toCursor
    if result[1].column == 0:
      result[1].line -= 1
      result[1].column = self.document.lineLength(result[1].line)

  of "line-next":
    result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))
    if result.last.line + 1 < self.document.numLines:
      result.last = (result.last.line + 1, 0)
    for _ in 1..<count:
      result = result or (
        (result.last.line, 0),
        (result.last.line, self.document.lineLength(result.last.line))
      )
      if result.last.line + 1 < self.document.numLines:
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
    let indent = self.document.rope.indentBytes(cursor.line)
    result = ((cursor.line, indent), (cursor.line, self.document.lineLength(cursor.line)))

  of "file":
    result.first = (0, 0)
    let line = self.document.numLines - 1
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
      # todo: use RopeCursor
      let str = move[8..^1]
      let line = self.document.getLine cursor.line
      result = cursor.toSelection
      let index = line.suffix(cursor.column).find(str)
      if index >= 0:
        result.last = (cursor.line, index + 1 + cursor.column)
      for _ in 1..<count:
        let index = line.suffix(result.last.column).find(str)
        if index >= 0:
          result.last = (result.last.line, index + 1 + result.last.column)

    elif move.startsWith("move-before "):
      # todo: use RopeCursor
      let str = move[12..^1]
      let line = self.document.getLine cursor.line
      result = cursor.toSelection
      let index = line.suffix(cursor.column + 1).find(str)
      if index >= 0:
        result.last = (cursor.line, index + cursor.column + 1)
      for _ in 1..<count:
        let index = line.suffix(result.last.column + 1).find(str)
        if index >= 0:
          result.last = (result.last.line, index + result.last.column + 1)
    else:
      result = cursor.toSelection

      let cursorJson = self.plugins.invokeAnyCallback("editor.text.custom-move", %*{
        "editor": self.id,
        "move": move,
        "cursor": cursor.toJson,
        "count": count,
      })

      if cursorJson.isNil:
        log(lvlError, fmt"editor.text.custom-move returned nil")
        return result

      result = cursorJson.jsonTo(Selection).catch:
        log(lvlError, fmt"Failed to parse selection from custom move '{move}': {cursorJson}")
        return cursor.toSelection

      return result

proc mapAllOrLast[T](self: openArray[T], all: bool, p: proc(v: T): T {.gcsafe, raises: [].}): seq[T] =
  if all:
    result = self.map p
  else:
    result = @self
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
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.selections = self.document.edit(selections, self.selections, [""],
    inclusiveEnd=self.useInclusiveSelections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc selectMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  self.selections = if inside:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc extendSelectMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.configProvider.getValue("text.move-count", 0)

  self.selections = if inside:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => self.extendSelectionWithMove(s, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => (
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
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => self.getSelectionForMove(s.last, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => (
      self.getCursor(s, which),
      self.getCursor(self.getSelectionForMove(s.last, move, count), which)
    ))

  self.selections = self.document.edit(selections, self.selections, [""],
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
    self.selections = self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} =>
      self.getSelectionForMove(self.cursor(s, which), move, count).last.toSelection(s, cursorSelector)
    )
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} =>
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
    self.selections = self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} =>
      self.getSelectionForMove(self.cursor(s, which), move, count).first.toSelection(s, cursorSelector)
    )
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} =>
      self.getSelectionForMove(self.cursor(s, which), move, count).first.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc setSearchQuery*(self: TextDocumentEditor, query: string, escapeRegex: bool = false,
    prefix: string = "", suffix: string = "") {.expose("editor.text").} =

  let query = if escapeRegex:
    query.escapeRegex
  else:
    query

  let finalQuery = prefix & query & suffix
  if self.searchQuery == finalQuery:
    return

  self.searchQuery = finalQuery
  self.updateSearchResults()

proc openSearchBar*(self: TextDocumentEditor, query: string = "", scrollToPreview: bool = true, select: bool = true) {.expose("editor.text").} =
  let commandLineEditor = self.editors.commandLineEditor.TextDocumentEditor
  if commandLineEditor == self:
    return

  let prevSearchQuery = self.searchQuery
  self.commands.openCommandLine "", proc(command: Option[string]): bool =
    if command.getSome(command):
      self.setSearchQuery(command)
      if select:
        self.selection = self.getNextFindResult(self.selection.last).first.toSelection
      self.scrollToCursor(self.selection.last)
    else:
      self.setSearchQuery(prevSearchQuery)
      if scrollToPreview:
        self.scrollToCursor(self.selection.last)

  let document = commandLineEditor.document

  commandLineEditor.disableCompletions = true
  commandLineEditor.moveLast("file")
  commandLineEditor.updateTargetColumn()

  var onEditHandle = Id.new
  var onActiveHandle = Id.new
  var onSearchHandle = Id.new

  onEditHandle[] = document.onEdit.subscribe proc(arg: tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]) =
    self.setSearchQuery(arg.document.contentString.replace(r".set-search-query \"))

  onActiveHandle[] = commandLineEditor.onActiveChanged.subscribe proc(editor: DocumentEditor) =
    if not editor.active:
      document.onEdit.unsubscribe(onEditHandle[])
      commandLineEditor.onActiveChanged.unsubscribe(onActiveHandle[])
      self.onSearchResultsUpdated.unsubscribe(onSearchHandle[])

  onSearchHandle[] = self.onSearchResultsUpdated.subscribe proc(_: TextDocumentEditor) =
    if self.searchResults.len == 0:
      self.scrollToCursor(self.selection.last)
    else:
      let s = self.getNextFindResult(self.selection.last)
      if scrollToPreview:
        self.scrollToCursor(s.last)

proc setSearchQueryFromMove*(self: TextDocumentEditor, move: string,
    count: int = 0, prefix: string = "", suffix: string = ""): Selection {.expose("editor.text").} =
  let selection = self.getSelectionForMove(self.selection.last, move, count)
  let searchText = self.document.contentString(selection)
  self.setSearchQuery(searchText, escapeRegex=true, prefix, suffix)
  return selection

proc toggleLineComment*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selections = self.document.toggleLineComment(self.selections)

proc openFileAt(self: TextDocumentEditor, filename: string, location: Option[Selection]) =
  if self.document.filename == filename:
    if location.getSome(location):
      self.selection = location
      self.updateTargetColumn(Last)
      self.centerCursor()
      self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)
      self.layout.showEditor(self.id)

  else:
    let editor = self.layout.openFile(filename)

    if editor.getSome(editor):
      if location.getSome(location):
        if editor == self:
          self.selection = location
          self.updateTargetColumn(Last)
          self.centerCursor()
          self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

        elif editor of TextDocumentEditor:
          let textEditor = editor.TextDocumentEditor
          textEditor.targetSelection = location
          textEditor.centerCursor()
          textEditor.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

    else:
      log lvlError, fmt"Failed to open file '{filename}' at {location}"

import finder/[file_previewer]

proc openLocationFromFinderItem(self: TextDocumentEditor, item: FinderItem) =
  try:
    let (path, location, _, _) = item.parsePathAndLocationFromItemData().getOr:
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

  else:
    var builder = SelectorPopupBuilder()
    builder.scope = "text-lsp-locations".some
    builder.scaleX = 0.85
    builder.scaleY = 0.8

    var res = newSeq[FinderItem]()
    for i, definition in definitions:
      let relPath = self.workspace.getRelativePathSync(definition.filename).get(definition.filename)
      let (_, name) = definition.filename.splitPath
      res.add FinderItem(
        displayName: name,
        detail: relPath.splitPath[0],
        data: encodeFileLocationForFinderItem(definition.filename, definition.location.some),
      )

    builder.previewer = newFilePreviewer(self.vfs, self.services).Previewer.some

    let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
    builder.finder = finder.some

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      self.openLocationFromFinderItem(item)
      true

    discard self.layout.pushSelectorPopup(builder)

proc gotoDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil or languageServer.isNone:
    return

  if languageServer.getSome(ls):
    # todo: absolute paths
    let locations = await ls.getDefinition(self.document.localizedPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoDeclarationAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil or languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getDeclaration(self.document.localizedPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoTypeDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil or languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getTypeDefinition(self.document.localizedPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoImplementationAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil or languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getImplementation(self.document.localizedPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc gotoReferencesAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil or languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getReferences(self.document.localizedPath, self.selection.last)
    await self.gotoLocationAsync(locations)

proc switchSourceHeaderAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil or languageServer.isNone:
    return

  if languageServer.getSome(ls):
    let filename = await ls.switchSourceHeader(self.document.localizedPath)
    if filename.getSome(filename):
      discard self.layout.openFile(filename)

proc updateCompletionMatches(self: TextDocumentEditor, completionIndex: int): Future[seq[int]] {.async.} =
  let revision = self.completionEngine.revision

  await sleepAsync(0.milliseconds)
  if revision != self.completionEngine.revision or self.document.isNil:
    return

  while gAsyncFrameTimer.elapsed.ms > 5:
    await sleepAsync(0.milliseconds)
    if revision != self.completionEngine.revision or self.document.isNil:
      return

  if completionIndex notin 0..self.completionMatches.high:
    return newSeq[int]()

  let index = self.completionMatches[completionIndex].index
  let filterText = self.completions[index].filterText
  let label = self.completions[index].item.label

  var matches = newSeqOfCap[int](filterText.len)
  discard matchFuzzySublime(filterText, label, matches, true, defaultCompletionMatchingConfig)

  self.completionMatchPositions[index] = matches
  if self.showCompletions:
    self.markDirty()

  return matches

proc getCompletionMatches*(self: TextDocumentEditor, completionIndex: int): seq[int] =
  self.updateCompletionsFromEngine()

  if completionIndex in self.completionMatchPositions:
    return self.completionMatchPositions[completionIndex]

  if completionIndex in self.completionMatchPositionsFutures:
    let f = self.completionMatchPositionsFutures[completionIndex]
    if f.finished:
      return f.readFinished
    else:
      return @[]

  if completionIndex < self.completionMatches.len:
    self.completionMatchPositionsFutures[completionIndex] = self.updateCompletionMatches(completionIndex)

  return @[]

proc updateCompletionsFromEngine(self: TextDocumentEditor) =
  if not self.completionsDirty:
    return

  self.completions = self.completionEngine.getCompletions()
  self.completionMatches.setLen self.completions.len
  for i in 0..<self.completionMatches.len:
    self.completionMatches[i] = (i, 0)
  self.completionMatchPositions.clear()
  self.completionMatchPositionsFutures.clear()

  self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.completionsDirty = false

proc showCompletionWindow(self: TextDocumentEditor) =
  self.showCompletions = true
  self.markDirty()

proc openLineSelectorPopup(self: TextDocumentEditor, minScore: float, sort: bool) =
  var builder = SelectorPopupBuilder()
  builder.scope = "lines".some
  builder.scaleX = 1
  builder.scaleY = 0.8
  builder.maxDisplayNameWidth = 90
  builder.maxDisplayNameWidth = 100

  # todo: use RopeCursor?
  var res = newSeq[FinderItem]()
  for i in 0..<self.document.numLines:
    let line = self.document.getLine(i)
    if not line.isEmptyOrWhitespace:
      res.add FinderItem(
        displayName: $line,
        data: encodeFileLocationForFinderItem(self.document.filename, (i, 0).some),
      )

  builder.previewer = newFilePreviewer(self.vfs, self.services).Previewer.some
  let finder = newFinder(newStaticDataSource(res), filterAndSort=true, minScore=minScore, sort=sort)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    self.openLocationFromFinderItem(item)
    true

  discard self.layout.pushSelectorPopup(builder)

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

  builder.previewer = newFilePreviewer(self.vfs, self.services).Previewer.some
  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    self.openLocationFromFinderItem(item)
    true

  discard self.layout.pushSelectorPopup(builder)

proc gotoSymbolAsync(self: TextDocumentEditor): Future[void] {.async.} =
  if self.document.getLanguageServer().await.getSome(ls):
    if self.document.isNil:
      return
    let symbols = await ls.getSymbols(self.document.localizedPath)
    if symbols.len == 0:
      return

    self.openSymbolSelectorPopup(symbols, navigateOnSelect=true)

type
  LspWorkspaceSymbolsDataSource* = ref object of DataSource
    workspace: Workspace
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

proc newLspWorkspaceSymbolsDataSource(languageServer: LanguageServer, workspace: Workspace):
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
      asyncSpawn self.getWorkspaceSymbols()
  else:
    self.delayedTask.reschedule()

proc gotoWorkspaceSymbolAsync(self: TextDocumentEditor, query: string = ""): Future[void] {.async.} =
  if self.document.getLanguageServer().await.getSome(ls):
    if self.document.isNil:
      return

    var builder = SelectorPopupBuilder()
    builder.scope = "text-lsp-locations".some
    builder.scaleX = 0.85
    builder.scaleY = 0.8

    builder.previewer = newFilePreviewer(self.vfs, self.services).Previewer.some
    let finder = newFinder(newLspWorkspaceSymbolsDataSource(ls, self.workspace), filterAndSort=true)
    builder.finder = finder.some

    builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
      self.openLocationFromFinderItem(item)
      true

    discard self.layout.pushSelectorPopup(builder)

proc gotoDefinition*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoDefinitionAsync()

proc gotoDeclaration*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoDeclarationAsync()

proc gotoTypeDefinition*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoTypeDefinitionAsync()

proc gotoImplementation*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoImplementationAsync()

proc gotoReferences*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoReferencesAsync()

proc switchSourceHeader*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.switchSourceHeaderAsync()

proc getCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.showCompletionWindow()

proc gotoSymbol*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoSymbolAsync()

proc fuzzySearchLines*(self: TextDocumentEditor, minScore: float = 0.2, sort: bool = true) {.expose("editor.text").} =
  self.openLineSelectorPopup(minScore, sort)

proc gotoWorkspaceSymbol*(self: TextDocumentEditor, query: string = "") {.expose("editor.text").} =
  asyncSpawn self.gotoWorkspaceSymbolAsync(query)

proc hideCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  # log lvlInfo, fmt"hideCompletions {self.document.filename}"
  self.showCompletions = false
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
    self.currentSnippetData.get.tabStops.withValue(self.currentSnippetData.get.currentTabStop, val):
      self.selections = val[]
      foundTabStop = true
      break

  if not foundTabStop:
    self.currentSnippetData.get.currentTabStop = 0
    self.selections = self.currentSnippetData.get.tabStops[0]

proc selectPrevTabStop*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.currentSnippetData.isNone:
    return

  if self.currentSnippetData.get.currentTabStop == 0:
    self.currentSnippetData.get.currentTabStop = self.currentSnippetData.get.highestTabStop
    self.currentSnippetData.get.tabStops.withValue(self.currentSnippetData.get.currentTabStop, val):
      self.selections = val[]
    return

  while self.currentSnippetData.get.currentTabStop > 1:
    self.currentSnippetData.get.currentTabStop.dec
    self.currentSnippetData.get.tabStops.withValue(self.currentSnippetData.get.currentTabStop, val):
      self.selections = val[]
      break

proc applyCompletion*(self: TextDocumentEditor, completion: Completion) =
  let completion = completion
  log(lvlInfo, fmt"Applying completion {completion.item.label}")

  let insertTextFormat = completion.item.insertTextFormat.get(InsertTextFormat.PlainText)

  var cursorEditSelections: seq[Selection] = @[]
  var cursorInsertTexts: seq[string] = @[]
  var editSelection: Selection

  let cursor = self.selection.last
  let cursorColumnIndex = self.document.rope.runeIndexInLine(cursor)
  let offset: tuple[lines: int, columns: RuneCount] = if completion.origin.getSome(origin):
    (cursor.line - origin.line, cursorColumnIndex - origin.column)
  else:
    (0, 0.RuneCount)

  if completion.item.textEdit.getSome(edit):
    if edit.asTextEdit().getSome(edit):
      if edit.`range`.start.line < 0:
        editSelection = self.document.getCompletionSelectionAt(cursor)
      else:
        let r = edit.`range`
        let runeSelection = (
          (r.start.line + offset.lines, r.start.character.RuneIndex + offset.columns),
          (r.`end`.line + offset.lines, r.`end`.character.RuneIndex + offset.columns),
        )
        let selection = self.document.runeSelectionToSelection(runeSelection)

        editSelection = selection
        editSelection.last = cursor

      for s in self.selections:
        cursorEditSelections.add self.document.getCompletionSelectionAt(s.last)
        cursorInsertTexts.add edit.newText

    elif edit.asInsertReplaceEdit().getSome(edit):
      return

    else:
      return

  else:
    let insertText = completion.item.insertText.get(completion.item.label)
    for i in 0..self.selections.high:
      cursorInsertTexts.add insertText
    cursorEditSelections = self.selections.mapIt(self.document.getCompletionSelectionAt(it.last))
    editSelection = cursorEditSelections[^1]

  editSelection = cursorEditSelections[^1]

  var snippetData = SnippetData.none
  if insertTextFormat == InsertTextFormat.Snippet:
    let insertText = cursorInsertTexts[^1]
    let snippet = parseSnippet(insertText)
    if snippet.isSome:
      let filenameParts = self.document.filename.splitFile
      let variables = toTable {
        "TM_FILENAME": filenameParts.name & filenameParts.ext,
        "TM_FILENAME_BASE": filenameParts.name,
        "TM_FILETPATH": self.document.localizedPath,
        "TM_DIRECTORY": filenameParts.dir,
        "TM_LINE_INDEX": $editSelection.last.line,
        "TM_LINE_NUMBER": $(editSelection.last.line + 1),
        "TM_CURRENT_LINE": $self.document.getLine(editSelection.last.line),
        "TM_CURRENT_WORD": "todo",
        "TM_SELECTED_TEXT": self.document.contentString(self.selection),
      }

      let indents = cursorEditSelections.mapIt(self.document.rope.indentBytes(it.first.line))
      try:
        var data = snippet.get.createSnippetData(cursorEditSelections, variables, indents)
        let indent = self.document.indentStyle.getString()
        for i, insertText in cursorInsertTexts.mpairs:
          insertText = data.text.indentExtraLines(self.document.getIndentLevelForLine(cursorEditSelections[i].first.line), indent)
        snippetData = data.some
      except CatchableError:
        discard

  var editSelections: seq[Selection] = @[]
  var insertTexts: seq[string] = @[]

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

  let numAdditionalEdits = editSelections.len

  editSelections.add cursorEditSelections
  insertTexts.add cursorInsertTexts

  let newSelections = self.document.edit(editSelections, self.selections, insertTexts)
  self.selections = newSelections[numAdditionalEdits..^1].mapIt(it.last.toSelection)

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
  let runeCursor = (cursor.line, self.document.rope.runeIndexInLine(cursor))
  var completion = self.completions[self.completionMatches[self.selectedCompletion].index]

  self.addNextCheckpoint("insert")
  self.applyCompletion(completion)

  # apply-selected-completion commands are not recorded, instead the specific selected completion is so that
  # repeating always inserts what was completed when recording.
  if self.bIsRecordingCurrentCommand:
    completion.origin = runeCursor.some
    self.registers.recordCommand("." & "apply-completion", $completion.toJson)

proc showHoverForAsync(self: TextDocumentEditor, cursor: Cursor): Future[void] {.async.} =
  if self.hideHoverTask.isNotNil:
    self.hideHoverTask.pause()

  let languageServer = await self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let hoverInfo = await ls.getHover(self.document.localizedPath, cursor)
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
  asyncSpawn self.showHoverForAsync(cursor)

proc showHoverForCurrent*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp hover information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncSpawn self.showHoverForAsync(self.selection.last)

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
    let snapshot = self.document.buffer.snapshot.clone()
    let inlayHints: Response[seq[language_server_base.InlayHint]] = await ls.getInlayHints(self.document.localizedPath, visibleRange)
    # todo: detect if canceled instead
    if inlayHints.isSuccess:
      # log lvlInfo, fmt"Updating inlay hints: {inlayHints}"
      self.inlayHints = inlayHints.result.mapIt (snapshot.anchorAt(it.location.toPoint, Left), it)
      self.lastInlayHintTimestamp = self.document.buffer.timestamp

      self.displayMap.overlay.clear(14)
      for hint in self.inlayHints:
        let point = hint.hint.location.toPoint
        self.displayMap.overlay.addOverlay(point...point, hint.hint.label, 14, "comment")

      self.markDirty()

proc clearDiagnostics*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.document.clearDiagnostics()
  self.markDirty()

proc updateInlayHints*(self: TextDocumentEditor) =
  if self.inlayHintsTask.isNil:
    self.inlayHintsTask = startDelayed(200, repeat=false):
      asyncSpawn self.updateInlayHintsAsync()
  else:
    self.inlayHintsTask.reschedule()

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
  asyncSpawn self.setFileReadOnlyAsync(readOnly)

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
  let max = self.configProvider.getValue("text.choose-cursor-max", 300)
  for chunk in self.lastRenderedChunks:
    let str = self.document.contentString((chunk.range.a.toCursor, chunk.range.b.toCursor))
    var i = 0
    while i < str.len and str[i] == ' ':
      inc i

    if i + 1 < str.len:
      result.add (chunk.range.a + point(0, i)).toCursor
      if result.len >= max:
        break

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
  for length in 2..4:
    if result.len == cursors.len:
      return
    for c in self.getCombinationsOfLength(possibleKeys, disallowedPairs, length, disallowDoubles=true):
      result.add c
      if result.len == cursors.len:
        return

proc getSelection*(self: TextDocumentEditor): Selection {.expose("editor.text").} =
  self.selection

proc getSelections*(self: TextDocumentEditor): Selections {.expose("editor.text").} =
  self.selections

proc setSelection*(self: TextDocumentEditor, selection: Selection) {.expose("editor.text").} =
  self.selection = selection

proc setSelections*(self: TextDocumentEditor, selections: Selections) {.expose("editor.text").} =
  self.selections = selections

proc setTargetSelection*(self: TextDocumentEditor, selection: Selection) {.expose("editor.text").} =
  self.targetSelection = selection

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
    self.displayMap.overlay.clear(15)
    try:

      var options: seq[Cursor] = @[]
      for i in 0..min(cursors.high, keys.high):
        if not keys[i].startsWith(progress):
          continue

        if progress.len > 0:
          self.displayMap.overlay.addOverlay(cursors[i].toPoint...point(cursors[i].line, cursors[i].column + progress.len), progress, 15, "string")

        let cursor = (line: cursors[i].line, column: cursors[i].column + progress.len)
        let text = keys[i][progress.len..^1]
        self.displayMap.overlay.addOverlay(cursor.toPoint...point(cursor.line, cursor.column + text.len), text, 15, "constant.numeric")

        options.add cursors[i]

      if options.len == 1:
        self.displayMap.overlay.clear(15)
        self.document.notifyTextChanged()
        self.markDirty()
        discard self.handleAction(action, ($options[0].toJson & " " & $oldMode.toJson), record=false)
    except:
      discard

    self.document.notifyTextChanged()
    self.markDirty()

  updateStyledTextOverrides()

  config.addCommand("", "<ESCAPE>", "setMode \"\"")

  self.modeEventHandlers.setLen(1)
  assignEventHandler(self.modeEventHandlers[0], config):
    onAction:
      self.displayMap.overlay.clear(15)
      self.document.notifyTextChanged()
      self.markDirty()
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored

    onInput:
      Ignored

    onProgress:
      progress.add inputToString(input)
      updateStyledTextOverrides()

    onCanceled:
      self.displayMap.overlay.clear(15)
      self.setMode(oldMode)

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  self.currentMode = mode
  self.plugins.handleModeChanged(self, oldMode, self.currentMode)

  self.markDirty()

proc recordCurrentCommand*(self: TextDocumentEditor, registers: seq[string] = @[]) {.expose("editor.text").} =
  self.recordCurrentCommandRegisters = if registers.len > 0:
    registers
  else:
    self.registers.recordingCommands

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
  if self.lastPressedMouseButton == MouseButton.Left:
    self.runSingleClickCommand()
  elif self.lastPressedMouseButton == MouseButton.DoubleClick:
    self.runDoubleClickCommand()
  elif self.lastPressedMouseButton == MouseButton.TripleClick:
    self.runTripleClickCommand()

proc addEventHandler*(self: TextDocumentEditor, name: string) {.expose("editor.text").} =
  if name notin self.eventHandlerNames:
    self.eventHandlerNames.add name
    self.updateEventHandlers()
    self.updateModeEventHandlers()

proc removeEventHandler*(self: TextDocumentEditor, name: string) {.expose("editor.text").} =
  let idx = self.eventHandlerNames.find(name)
  if idx != -1:
    self.eventHandlerNames.removeShift(idx)
    self.updateEventHandlers()
    self.updateModeEventHandlers()

proc getCurrentEventHandlers*(self: TextDocumentEditor): seq[string] {.expose("editor.text").} =
  return self.eventHandlerNames

proc setCustomHeader*(self: TextDocumentEditor, text: string) {.expose("editor.text").} =
  self.customHeader = text
  self.markDirty()

genDispatcher("editor.text")
addActiveDispatchTable "editor.text", genDispatchTable("editor.text")

proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): Option[JsonNode] =
  # debugf"[textedit] handleAction {action}, '{args}'"

  var args = args.copy
  args.elems.insert api.TextDocumentEditor(id: self.id).toJson, 0

  block:
    let res = self.plugins.invokeAnyCallback(action, args)
    if res.isNotNil:
      dec self.commandCount
      while self.commandCount > 0:
        if self.plugins.invokeAnyCallback(action, args).isNil:
          break
        dec self.commandCount
      self.commandCount = self.commandCountRestore
      self.commandCountRestore = 0
      return res.some

  try:
    # debugf"dispatch {action}, {args}"
    if dispatch(action, args).getSome(res):
      dec self.commandCount
      while self.commandCount > 0:
        if dispatch(action, args).isNone:
          break
        dec self.commandCount
      self.commandCount = self.commandCountRestore
      self.commandCountRestore = 0
      return res.some
  except:
    let argsText = if args.isNil: "nil" else: $args
    log(lvlError, fmt"Failed to dispatch action '{action} {argsText}': {getCurrentExceptionMsg()}")
    log(lvlError, getCurrentException().getStackTrace())

  return JsonNode.none

method handleAction*(self: TextDocumentEditor, action: string, arg: string, record: bool): Option[JsonNode] =
  # debugf "handleAction {action}, '{arg}'"

  try:
    let oldIsRecordingCurrentCommand = self.bIsRecordingCurrentCommand
    defer:
      self.bIsRecordingCurrentCommand = oldIsRecordingCurrentCommand

    self.bIsRecordingCurrentCommand = record

    let noRecordActions = [
      "apply-selected-completion",
      "applySelectedCompletion",
    ].toHashSet

    if record and action notin noRecordActions:
      self.registers.recordCommand("." & action, arg)

    defer:
      if record and self.recordCurrentCommandRegisters.len > 0:
        self.registers.recordCommand("." & action, arg, self.recordCurrentCommandRegisters)
      self.recordCurrentCommandRegisters.setLen(0)

    var args = newJArray()
    try:
      for a in newStringStream(arg).parseJsonFragments():
        args.add a

      if not self.isRunningSavedCommands:
        self.currentCommandHistory.commands.add Command(command: action, args: args)

      return self.handleActionInternal(action, args)
    except CatchableError:
      log(lvlError, fmt"handleAction: {action}, Failed to parse args: '{arg}'")
      return JsonNode.none
  except:
    discard

proc handleInput(self: TextDocumentEditor, input: string, record: bool): EventResponse =
  try:
    if not self.isRunningSavedCommands:
      self.currentCommandHistory.commands.add Command(isInput: true, command: input)

    if record:
      self.registers.recordCommand(".insert-text", $input.newJString)

    # echo "handleInput '", input, "'"
    if self.plugins.invokeCallback(self.getContextWithMode("editor.text.input-handler"), input.newJString):
      return Handled

    self.insertText(input)
  except:
    discard
  return Handled

proc handleFocusChanged*(self: TextDocumentEditor, focused: bool) =
  if focused:
    if self.active and self.blinkCursorTask.isNotNil:
      self.blinkCursorTask.reschedule()

proc handleLanguageServerAttached(self: TextDocumentEditor, document: TextDocument,
    languageServer: LanguageServer) =
  # log lvlInfo, fmt"[handleLanguageServerAttached] {self.document.filename}"
  self.completionEngine.addProvider newCompletionProviderLsp(document, languageServer)
    .withMergeStrategy(MergeStrategy(kind: TakeAll))
    .withPriority(2)
  self.updateInlayHints()

proc handleTextDocumentBufferChanged(self: TextDocumentEditor, document: TextDocument) =
  if document != self.document:
    return

  self.closeDiff()
  self.snapshot = self.document.buffer.snapshot.clone()
  self.displayMap.setBuffer(self.snapshot.clone())
  self.selections = self.selections
  self.inlayHints.setLen(0)
  self.hideCompletions()
  self.updateInlayHints()
  self.updateSearchResults()
  self.markDirty()

proc handleEdits(self: TextDocumentEditor, edits: openArray[tuple[old, new: Selection]]) =
  self.displayMap.edit(self.document.buffer.snapshot.clone(), edits)
  if self.configProvider.getValue("text.auto-wrap", true):
    self.displayMap.wrapMap.update(self.displayMap.tabMap.snapshot.clone(), force = true)

proc handleTextDocumentTextChanged(self: TextDocumentEditor) =
  let oldSnapshot = self.snapshot.move
  self.snapshot = self.document.buffer.snapshot.clone()

  if self.bScrollToEndOnInsert and self.selections.len == 1 and self.selection == oldSnapshot.visibleText.summary.lines.toCursor.toSelection:
    self.selection = self.document.lastCursor.toSelection
    self.scrollToCursor()

  elif self.snapshot.replicaId == oldSnapshot.replicaId and self.snapshot.ownVersion >= oldSnapshot.ownVersion:
    let temp = self.selectionAnchors.mapIt (it[0].summaryOpt(Point, self.snapshot), it[1].summaryOpt(Point, self.snapshot))
    if temp.allIt(it[0].isSome and it[1].isSome):
      let newSelections = temp.mapIt (it[0].get, it[1].get).toSelection

      if newSelections.len > 0:
        self.selections = newSelections
    else:
      log lvlWarn, &"Invalid anchors: {self.selectionAnchors} -> {temp}"
      self.selectionAnchors = @[]

  self.clampSelection()
  self.updateSearchResults()
  self.updateInlayHints()

  self.markDirty()

proc handleTextDocumentPreLoaded(self: TextDocumentEditor) =
  if self.document.isNil:
    return

  self.selectionsBeforeReload = self.selections

proc handleTextDocumentLoaded(self: TextDocumentEditor) =
  if self.document.isNil:
    return

  # log lvlInfo, &"handleTextDocumentLoaded {self.id}, {self.usage}, {self.document.filename}: targetSelectionsInternal: {self.targetSelectionsInternal}, selectionsBeforeReload: {self.selectionsBeforeReload}"

  if self.targetSelectionsInternal.getSome(s):
    self.selections = s
    self.centerCursor()
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

  elif self.document.autoReload:
    if self.selection == self.selectionsBeforeReload[self.selectionsBeforeReload.high]:
      self.selection = self.document.lastCursor.toSelection
      self.scrollToCursor()
      self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)

  elif self.selectionsBeforeReload.len > 0:
    self.selections = self.selectionsBeforeReload
    self.scrollToCursor()
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

  self.targetSelectionsInternal = Selections.none
  self.updateTargetColumn(Last)

  if self.diffDocument.isNotNil:
    asyncSpawn self.updateDiffAsync(gotoFirstDiff=false)

proc handleTextDocumentSaved(self: TextDocumentEditor) =
  log lvlInfo, fmt"handleTextDocumentSaved '{self.document.filename}'"
  if self.diffDocument.isNotNil:
    asyncSpawn self.updateDiffAsync(gotoFirstDiff=false)
  self.markDirty()

proc handleCompletionsUpdated(self: TextDocumentEditor) =
  self.completionsDirty = true
  self.markDirty()

proc handleWrapMapUpdated(self: TextDocumentEditor, wrapMap: WrapMap, old: WrapMapSnapshot) =
  if self.document.isNil or self.diffDocument.isNil:
    return
  if wrapMap == self.displayMap.wrapMap:
    self.diffDisplayMap.diffMap.update(self.diffChanges, self.displayMap.wrapMap.snapshot, reverse = false)
  elif wrapMap == self.diffDisplayMap.wrapMap:
    self.displayMap.diffMap.update(self.diffChanges, self.diffDisplayMap.wrapMap.snapshot, reverse = true)

proc handleDisplayMapUpdated(self: TextDocumentEditor, displayMap: DisplayMap) =
  if self.document.isNil:
    return

  if displayMap == self.displayMap:
    if displayMap.endDisplayPoint.row != self.lastEndDisplayPoint.row:
      self.lastEndDisplayPoint = displayMap.endDisplayPoint
      self.updateTargetColumn()
      let oldScrollOffset = self.scrollOffset

      if self.targetPoint.getSome(point):
        self.scrollToCursor(point.toCursor, self.targetLineMargin, self.nextScrollBehaviour, self.targetLineRelativeY)
      else:
        self.scrollOffset = self.interpolatedScrollOffset

      let oldInterpolatedScrollOffset = self.interpolatedScrollOffset
      let displayPoint = self.displayMap.toDisplayPoint(self.currentCenterCursor.toPoint)
      self.interpolatedScrollOffset = self.lastContentBounds.h * self.currentCenterCursorRelativeYPos - self.platform.totalLineHeight * 0.5 - displayPoint.row.float * self.platform.totalLineHeight
      # debugf"handleDisplayMapUpdated {self.getFileName()}: {oldScrollOffset} -> {self.scrollOffset}, {oldInterpolatedScrollOffset} -> {self.interpolatedScrollOffset}, target {self.targetPoint}"

    self.markDirty()
  elif displayMap == self.diffDisplayMap:
    self.markDirty()

## Only use this to create TextDocumentEditorInstances
proc createTextEditorInstance(): TextDocumentEditor =
  let editor = TextDocumentEditor(selectionsInternal: @[(0, 0).toSelection])
  editor.cursorsId = newId()
  editor.completionsId = newId()
  editor.hoverId = newId()
  editor.inlayHints = @[]
  editor.init()
  {.gcsafe.}:
    allTextEditors.add editor
  return editor

proc updateEventHandlers(self: TextDocumentEditor) =
  self.eventHandlers.setLen(self.eventHandlerNames.len)
  for i, name in self.eventHandlerNames:
    let config = self.events.getEventHandlerConfig(name)
    assignEventHandler(self.eventHandlers[i], config):
      onAction:
        if self.handleAction(action, arg, record=true).isSome:
          Handled
        else:
          Ignored
      onInput:
        self.handleInput input, record=true

proc updateModeEventHandlers(self: TextDocumentEditor) =
  if self.currentMode.len == 0:
    self.modeEventHandlers.setLen(0)
  else:
    self.modeEventHandlers.setLen(self.eventHandlerNames.len)
    for i, name in self.eventHandlerNames:
      let config = self.events.getEventHandlerConfig(name & "." & self.currentMode)
      assignEventHandler(self.modeEventHandlers[i], config):
        onAction:
          if self.handleAction(action, arg, record=true).isSome:
            Handled
          else:
            Ignored
        onInput:
          self.handleInput input, record=true

proc newTextEditor*(document: TextDocument, services: Services): TextDocumentEditor =
  var self = createTextEditorInstance()
  self.services = services
  self.platform = self.services.getService(PlatformService).get.platform
  self.configProvider = services.getService(ConfigService).get.asConfigProvider
  self.editors = services.getService(DocumentEditorService).get
  self.layout = services.getService(LayoutService).get
  self.vcs = self.services.getService(VCSService).get
  self.events = self.services.getService(EventHandlerService).get
  self.plugins = self.services.getService(PluginService).get
  self.registers = self.services.getService(Registers).get
  self.workspace = self.services.getService(Workspace).get
  self.vfs = self.services.getService(VFSService).get.vfs
  self.commands = self.services.getService(CommandService).get
  self.eventHandlerNames = @["editor.text"]
  self.displayMap = DisplayMap.new()
  self.diffDisplayMap = DisplayMap.new()
  discard self.displayMap.wrapMap.onUpdated.subscribe (args: (WrapMap, WrapMapSnapshot)) => self.handleWrapMapUpdated(args[0], args[1])
  discard self.diffDisplayMap.wrapMap.onUpdated.subscribe (args: (WrapMap, WrapMapSnapshot)) => self.handleWrapMapUpdated(args[0], args[1])
  discard self.displayMap.onUpdated.subscribe (args: (DisplayMap,)) => self.handleDisplayMapUpdated(args[0])
  discard self.diffDisplayMap.onUpdated.subscribe (args: (DisplayMap,)) => self.handleDisplayMapUpdated(args[0])

  self.setDocument(document)

  self.startBlinkCursorTask()

  self.editors.registerEditor(self)

  self.updateEventHandlers()

  assignEventHandler(self.completionEventHandler, self.events.getEventHandlerConfig("editor.text.completion")):
    onAction:
      if self.handleAction(action, arg, record=true).isSome:
        Handled
      else:
        Ignored
    onInput:
      self.handleInput input, record=true

  self.onFocusChangedHandle = self.platform.onFocusChanged.subscribe proc(focused: bool) = self.handleFocusChanged(focused)

  self.setMode(self.configProvider.getValue("editor.text.default-mode", ""))

  return self

method getDocument*(self: TextDocumentEditor): Document = self.document

method unregister*(self: TextDocumentEditor) =
  self.editors.unregisterEditor(self)

method getStateJson*(self: TextDocumentEditor): JsonNode =
  let selection = if self.targetSelectionsInternal.getSome(s) and s.len > 0:
    s.last
  else:
    self.selection
  return %*{
    "selection": selection.toJson
  }

method restoreStateJson*(self: TextDocumentEditor, state: JsonNode) =
  if state.kind != JObject:
    return
  try:
    if state.hasKey("selection"):
      let selection = state["selection"].jsonTo Selection
      self.targetSelection = selection
      self.scrollToCursor()
      self.markDirty()
  except:
    log lvlError, &"Failed to restore state from json: {getCurrentExceptionMsg()}\n{state}"
