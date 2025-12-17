import std/[strutils, sequtils, sugar, options, json, streams, strformat, tables, parseutils,
  deques, sets, algorithm, os]
import chroma
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, rect_utils, event, custom_logger, custom_async, fuzzy_matching,
  custom_unicode, delayed_task, myjsonutils, regex, timer, response, rope_utils, rope_regex, jsonex]
import scripting/[expose]
import platform/[platform]
import language/[language_server_base]
import document, document_editor, events, vmath, bumpy, input, custom_treesitter, indent,
  text_document, snippet
import completion, completion_provider_document, completion_provider_lsp,
  completion_provider_snippet, selector_popup_builder, dispatch_tables, register
import config_provider, service, layout, platform_service, vfs, vfs_service, command_service, toast
import diff, plugin_service, move_database
import workspaces/workspace
import finder/[previewer, finder]
import vcs/vcs
import overlay_map, tab_map, wrap_map, diff_map, display_map
import lisp

from language/lsp_types import CompletionList, CompletionItem, InsertTextFormat,
  TextEdit, Position, asTextEdit, asInsertReplaceEdit, toJsonHook, CodeAction, CodeActionResponse, CodeActionKind,
  Command, WorkspaceEdit, asCommand, asCodeAction

import nimsumtree/[buffer, clock, static_array, rope]
from nimsumtree/sumtree as st import summaryType, itemSummary, Bias, mapOpt

export text_document, document_editor, id, Bias

{.push gcsafe.}
{.push raises: [].}

logCategory "texted"

let searchResultsId = newId()
let wordHighlightId = newId()

const overlayIdPrefix* = 12
const overlayIdColorHighlight* = 13
const overlayIdInlayHint* = 14
const overlayIdChooseCursor* = 15

type
  ColorType* = enum Hex = "hex", Float1 = "float1", Float255 = "float255"

  ScrollToChangeOnReload* {.pure.} = enum First = "first", Last = "last"

  SignColumnShowKind* {.pure.} = enum Auto = "auto", Yes = "yes", No = "no", Number = "number"

proc typeNameToJson*(T: typedesc[ScrollToChangeOnReload]): string =
  return "\"first\" | \"last\""

proc typeNameToJson*(T: typedesc[ColorType]): string =
  return "\"hex\" | \"float1\" | \"float255\""

proc typeNameToJson*(T: typedesc[SignColumnShowKind]): string =
  return "\"auto\" | \"yes\" | \"no\" | \"number\""

declareSettings SignColumnSettings, "":
  ## Defines how the sign column is displayed.
  ## - auto: Signs are next to line numbers, width is based on amount of signs in a line.
  ## - yes: Signs are next to line numbers and sign column is always visible. Width is defined in `max-width`
  ## - no: Don't show the sign column
  ## - number: Show signs instead of the line number, no extra sign column.
  declare show, SignColumnShowKind, SignColumnShowKind.Number

  ## If `show` is `auto` then this is the max width of the sign column, if `show` is `yes` then this is the exact width.
  declare maxWidth, Option[int], 2

declareSettings CodeActionSettings, "":
  ## Character to use as sign for lines where code actions are available. Empty string or null means no sign will be shown for code actions.
  declare sign, string, "⚑"

  ## How many columns the sign occupies.
  declare signWidth, int, 1

  ## What color the sign for code actions should be. Can be a theme color name or hex code (e.g. `#12AB34`).
  declare signColor, string, "info"

declareSettings ColorHighlightSettings, "":
  ## Add colored inlay hints before any occurance of a string representing a color. Color detection is configured per language
  ## in `text.color-highlight.{language-id}.`
  declare enable, bool, false

  ## Regex used to find colors. Use capture groups to match one or more numbers within a color definition, depending on the kind.
  declare regex, RegexSetting, "#([0-9a-fA-F]{6})|#([0-9a-fA-F]{8})"

  ## How to interpret the number.
  ## "hex" means the number is written as either 6 or 8 hex characters, e.g. ABBACA7.
  ## "float1" means the number is a float with 0 being black and 1 being white.
  ## "float255" means the number is a float or int with 0 being black and 255 being white.
  declare kind, ColorType, ColorType.Hex

declareSettings MatchingWordHighlightSettings, "":
  ## Enable highlighting of text matching the current selection or word containing the cursor (if the selection is empty).
  declare enable, bool, true

  ## How long after moving the cursor matching text is highlighted.
  declare delay, int, 250

  ## Don't highlight matching text if the selection spans more bytes than this.
  declare maxSelectionLength, int, 1024

  ## Don't highlight matching text if the selection spans more lines than this.
  declare maxSelectionLines, int, 5

  ## Don't highlight matching text in files above this size (in bytes).
  declare maxFileSize, int, 1024*1024*100

declareSettings TextEditorSettings, "text":
  use colorHighlight, ColorHighlightSettings

  ## Settings for how signs are displayed
  use signs, SignColumnSettings

  ## Settings for highlighting text matching the current selection or word containing the cursor.
  use highlightMatches, MatchingWordHighlightSettings

  ## Configure search regexes.
  use searchRegexes, SearchRegexSettings

  ## Configure code actions.
  use codeActions, CodeActionSettings

  ## Specifies whether a selection includes the character after the end cursor.
  ## If true then a selection like (0:0...0:4) with the text "Hello world" would select "Hello".
  ## If false then the selected text would be "Hell".
  ## If you use Vim motions then the Vim plugin manages this setting.
  declare inclusiveSelection, bool, false

  ## How many characters wide a tab is.
  declare tabWidth, int, 4

  ## Whether `text.cursor-margin` is relative to the screen height (0-1) or an absolute number of lines.
  declare cursorMarginRelative, bool, true

  ## How far from the edge to keep the cursor, either percentage of screen height (0-1) or number of lines,
  ## depending on `text.cursor-margin-relative`.
  declare cursorMargin, float, 0.15

  ## How many milliseconds after hovering a word the lsp hover request is sent.
  declare hoverDelay, int, 200

  ## Enable line wrapping.
  declare wrapLines, bool, true

  ## How many characters from the right edge to start wrapping text.
  declare wrapMargin, int, 1

  ## Show lines containing parent nodes (like function, type, if/for etc) at the top of the window.
  declare contextLines, bool, true

  ## Default mode to set when opening/creating text documents.
  declare defaultMode, string, ""

  ## Maximum number of results to display for regex based workspace symbol search.
  declare searchWorkspaceRegexMaxResults, int, 50_000

  ## Maximum number of locations to highlight choose cursor mode.
  declare chooseCursorMax, int, 300

  ## Command to run after control clicking on some text.
  declare controlClickCommand, string, "goto-definition"

  ## Arguments to the command which is run when control clicking on some text.
  declare controlClickCommandArgs, JsonNode, newJArray()

  ## Command to run after single clicking on some text.
  declare singleClickCommand, string, ""

  ## Arguments to the command which is run when single clicking on some text.
  declare singleClickCommandArgs, JsonNode, newJArray()

  ## Command to run after double clicking on some text.
  declare doubleClickCommand, string, "extend-select-move"

  ## Arguments to the command which is run when double clicking on some text.
  declare doubleClickCommandArgs, JsonNode, %[newJString("word"), newJBool(true)]

  ## Command to run after triple clicking on some text.
  declare tripleClickCommand, string, "extend-select-move"

  ## Arguments to the command which is run when triple clicking on some text.
  declare tripleClickCommandArgs, JsonNode, %[newJString("line"), newJBool(true)]

  ## If not null then scroll to the changed region when a file is reloaded.
  declare scrollToChangeOnReload, Option[ScrollToChangeOnReload], nil

  ## If true then scroll to the end of the file when text is inserted at the end and the cursor
  ## is already at the end.
  declare scrollToEndOnInsert, bool, false

  ## List of input modes text editors.
  declare modes, seq[string], @["editor.text"]

  ## Mode to activate while completion window is open.
  declare completionMode, string, "editor.text.completion"

  ## Command to execute when the mode of the text editor changes
  declare modeChangedHandlerCommand, string, ""

  ## Whether inlay hints are enabled.
  declare inlayHintsEnabled, bool, true

  ## Whether signature help is enabled.
  declare signatureHelpEnabled, bool, true

  ## How often (in milliseconds) to update signature help while typing.
  declare signatureHelpDelay, int, 200

  ## Which move to use to find the beginning of the argument list when showing signature help.
  declare signatureHelpMove, string, "(ts 'call.inner') (overlapping) (last)"

  ## Which characters trigger signature help when inserted.
  declare signatureHelpTriggerChars, RuneSetSetting, %%*["("]

  ## Trigger signature help when editing inside an argument list, as defined by 'signature-help-move'
  declare signatureHelpTriggerOnEditInArgs, bool, true

  ## Automatically insert closing parenthesis, braces, brackets and quotes.
  declare autoInsertClose, bool, true

type
  CodeActionKind {.pure.} = enum Command, CodeAction
  CodeActionOrCommand = object
    languageServerName: string
    selection: Selection
    case kind: CodeActionKind
    of CodeActionKind.Command:
      command: lsp_types.Command
    of CodeActionKind.CodeAction:
      action: lsp_types.CodeAction

type TextDocumentEditor* = ref object of DocumentEditor
  platform*: Platform
  editors*: DocumentEditorService
  layout*: LayoutService
  services*: Services
  vcs: VCSService
  events: EventHandlerService
  plugins: PluginService
  registers: Registers
  workspace: Workspace
  moveDatabase: MoveDatabase
  vfsService: VFSService
  vfs*: VFS
  commands*: CommandService
  configService*: ConfigService
  configChanged: bool = false

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
  signatureHelpId*: Id
  diagnosticsId*: Id
  lastCursorLocationBounds*: Option[Rect]
  lastHoverLocationBounds*: Option[Rect]
  lastSignatureHelpLocationBounds*: Option[Rect]

  selectionsBeforeReload: Selections
  wasAtEndBeforeReload: bool = false
  selectionsInternal: Selections
  targetSelectionsInternal: Option[Selections] # The selections we want to have once
                                               # the document is loaded
  selectionHistory: Deque[Selections]
  dontRecordSelectionHistory: bool

  cursorHistories*: seq[seq[Vec2]]

  searchQuery*: string
  searchResults*: seq[Range[Point]]
  isUpdatingSearchResults: bool
  lastSearchResultUpdate: tuple[buffer: BufferId, version: Global, searchQuery: string]
  isUpdatingMatchingWordHighlights: bool

  styledTextOverrides: Table[int, seq[tuple[cursor: Cursor, text: string, scope: string]]]

  customHighlights*: Table[int, seq[tuple[id: Id, selection: Selection, color: string, tint: Color]]]
  signs*: Table[int, seq[tuple[id: Id, group: string, text: string, tint: Color, color: string, width: int]]]

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
  updateMatchingWordsTask: DelayedTask

  # auto insert closing parens
  lastAutoCloseText: string
  lastAutoCloseLocations: seq[Anchor]

  # hover
  showHoverTask: DelayedTask    # for showing hover info after a delay
  hideHoverTask: DelayedTask    # for hiding hover info after a delay
  currentHoverLocation: Cursor  # the location of the mouse hover
  showHover*: bool              # whether to show hover info in ui
  hoverText*: string            # the text to show in the hover info
  hoverLocation*: Cursor        # where to show the hover info
  hoverScrollOffset*: float     # the scroll offset inside the hover window

  # signatureHelp
  showSignatureHelpTask: DelayedTask    # for showing signatureHelp info after a delay
  showSignatureHelp*: bool              # whether to show signatureHelp info in ui
  signatureHelpLocation*: Cursor        # where to show the signatureHelp info
  signatures*: seq[lsp_types.SignatureInformation]
  currentSignature*: int
  currentSignatureParam*: int

  # inline hints
  inlayHints: seq[tuple[anchor: Anchor, hint: InlayHint]]
  inlayHintsTask: DelayedTask
  lastInlayHintTimestamp: Global
  lastInlayHintDisplayRange: Range[Point]
  lastInlayHintBufferRange: Range[Point]
  lastDiagnosticsVersions: Table[string, int]
  codeActions: Table[string, Table[int, seq[CodeActionOrCommand]]] # LS name -> line -> code actions

  mEventHandlers: seq[EventHandler]
  eventHandlerOverrides: Table[string, proc(config: EventHandlerConfig): EventHandler {.gcsafe, raises: [].}]
  completionEventHandler: EventHandler
  commandCount*: int
  commandCountRestore*: int
  recordCurrentCommandRegisters: seq[string] # List of registers the current command should be recorded into.
  bIsRecordingCurrentCommand: bool = false # True while running a command which is being recorded

  disableScrolling*: bool
  scrollOffset*: Vec2
  interpolatedScrollOffset*: Vec2

  currentCenterCursor*: Cursor # Cursor representing the center of the screen
  currentCenterCursorRelativeYPos*: float # 0: top of screen, 1: bottom of screen

  lastRenderedChunks*: seq[tuple[range: Range[Point], displayRange: Range[DisplayPoint]]]
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
  completionsDirty: bool
  completionEngine: CompletionEngine
  lastCompletionTrigger: (Global, Cursor)
  lastItems*: seq[tuple[index: int, bounds: Rect]]
  showCompletions*: bool
  scrollToCompletion*: Option[int]
  completionsDrawnInReverse*: bool = false

  lastEndDisplayPoint: DisplayPoint

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
  onDiagnosticsHandle: Id
  onCompletionsUpdatedHandle: Id
  onFocusChangedHandle: Id

  customHeader*: string

  onSearchResultsUpdated*: Event[TextDocumentEditor]
  onModeChanged*: Event[tuple[removed: seq[string], added: seq[string]]]

  uiSettings*: UiSettings
  debugSettings*: DebugSettings
  settings*: TextEditorSettings

  moveFallbacks: MoveFunction

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

method createDocument*(self: TextDocumentFactory, services: Services, path: string, load: bool): Document =
  return newTextDocument(services, path, app=false, load=load)

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
  result.add &"Overlay map: {st.stats(self.displayMap.overlay.snapshot.map)}\n"
  result.add &"Wrap map: {st.stats(self.displayMap.diffMap.snapshot.map)}\n"
  result.add &"Diff map: {st.stats(self.displayMap.wrapMap.snapshot.map)}\n"

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
proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string, count: int = 0, includeEol: bool = true): Selection
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
proc getFileName*(self: TextDocumentEditor): string
proc closeDiff*(self: TextDocumentEditor)
proc setNextSnapBehaviour*(self: TextDocumentEditor, snapBehaviour: ScrollSnapBehaviour)
proc numDisplayLines*(self: TextDocumentEditor): int
proc doMoveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool = true, includeAfter: bool = true): Cursor
proc addNextCheckpoint*(self: TextDocumentEditor, checkpoint: string)
proc setDefaultMode*(self: TextDocumentEditor)

proc handleLanguageServerAttached(self: TextDocumentEditor, document: TextDocument, languageServer: LanguageServer)
proc handleDiagnosticsChanged(self: TextDocumentEditor, document: TextDocument, languageServer: LanguageServer)
proc handleEdits(self: TextDocumentEditor, edits: openArray[tuple[old, new: Selection]])
proc handleTextDocumentTextChanged(self: TextDocumentEditor)
proc handleTextDocumentBufferChanged(self: TextDocumentEditor, document: TextDocument)
proc handleTextDocumentLoaded(self: TextDocumentEditor, changes: seq[Selection])
proc handleTextDocumentPreLoaded(self: TextDocumentEditor)
proc handleTextDocumentSaved(self: TextDocumentEditor)
proc handleCompletionsUpdated(self: TextDocumentEditor)
proc handleWrapMapUpdated(self: TextDocumentEditor, wrapMap: WrapMap, old: WrapMapSnapshot)
proc handleDisplayMapUpdated(self: TextDocumentEditor, displayMap: DisplayMap)
proc updateMatchingWordHighlight(self: TextDocumentEditor)
proc updateColorOverlays(self: TextDocumentEditor) {.async.}
proc showSignatureHelpForDelayed*(self: TextDocumentEditor, cursor: Cursor)
proc hideSignatureHelp*(self: TextDocumentEditor)
proc showSignatureHelp*(self: TextDocumentEditor)
proc getSelectionsForMove*(self: TextDocumentEditor, selections: openArray[Selection], move: string, count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Selection]

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
  includeAfter: bool = true, wrap: bool = true): Selection
proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0,
  includeAfter: bool = true, wrap: bool = true): Selection

import workspace_edit

proc debug*(self: TextDocumentEditor): string =
  return &"TE({self.id}, '{self.usage}', '{self.getFileName()}')"

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

proc `selections=`*(self: TextDocumentEditor, selections: Selections, addToHistory: Option[bool] = bool.none) =
  let selections = self.clampAndMergeSelections(selections)
  if selections.len == 0:
    log lvlWarn, "Trying to set empty selections, not allowed"
    return

  var changedLine = false
  if self.selectionsInternal.len != selections.len:
    changedLine = true
  else:
    for i in 0..<selections.len:
      if self.selectionsInternal[i].last.line != selections[i].last.line or
          self.selectionsInternal[i].first.line != selections[i].first.line:
        changedLine = true

  if not self.dontRecordSelectionHistory:
    let addToHistory = addToHistory.get(self.selectionHistory.len == 0 or
        abs(selections[^1].last.line - self.selectionsInternal[^1].last.line) > 1 or
        self.selectionsInternal.len != selections.len)
    if addToHistory:
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
  if self.showSignatureHelp:
    if changedLine:
      self.hideSignatureHelp()
    else:
      self.showSignatureHelpForDelayed(self.selection.last)
  self.hideCompletions()
  self.updateMatchingWordHighlight()
  # self.document.addNextCheckpoint("move")

  self.markDirty()

proc `selection=`*(self: TextDocumentEditor, selection: Selection) =
  self.selections = @[selection]

proc `targetSelection=`*(self: TextDocumentEditor, selection: Selection) =
  if self.document.isLoadingAsync or self.document.requiresLoad:
    self.targetSelectionsInternal = @[selection].some
  else:
    self.selection = selection
    self.updateTargetColumn(Last)

proc clampSelection*(self: TextDocumentEditor) =
  self.selections = self.clampAndMergeSelections(self.selectionsInternal)
  self.markDirty()

proc useInclusiveSelections*(self: TextDocumentEditor): bool =
  self.settings.inclusiveSelection.get()

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
    self.document.onDiagnostics.unsubscribe(self.onDiagnosticsHandle)

    let document = self.document
    self.document = nil
    self.editors.tryCloseDocument(document)

    self.selectionHistory.clear()
    self.customHighlights.clear()
    self.signs.clear()
    self.showHover = false
    self.showSignatureHelp = false
    self.inlayHints.setLen 0
    self.scrollOffset = vec2(0, 0)
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
  self.config.setParent(self.document.config)

  self.onEditHandle = document.onEdit.subscribe (arg: tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]) =>
    self.handleEdits(arg.edits)

  self.textChangedHandle = document.textChanged.subscribe (_: TextDocument) =>
    self.handleTextDocumentTextChanged()

  self.onBufferChangedHandle = document.onBufferChanged.subscribe (arg: tuple[document: TextDocument]) =>
    self.handleTextDocumentBufferChanged(arg.document)

  self.onRequestRerenderHandle = document.onRequestRerender.subscribe () =>
    self.markDirty()

  self.loadedHandle = document.onLoaded.subscribe (args: tuple[document: TextDocument, changed: seq[Selection]]) => (block:
      if self.isNil or self.document.isNil:
        return
      self.handleTextDocumentLoaded(args.changed)
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

  self.onDiagnosticsHandle = document.onDiagnostics.subscribe (
      arg: tuple[document: TextDocument, languageServer: LanguageServer]) =>
    self.handleDiagnosticsChanged(arg.document, arg.languageServer)

  self.completionEngine = CompletionEngine()
  self.onCompletionsUpdatedHandle = self.completionEngine.onCompletionsUpdated.subscribe () =>
    self.handleCompletionsUpdated()

  if self.document.getLanguageServer().getSome(ls):
    self.handleLanguageServerAttached(self.document, ls)

  if self.document.createLanguageServer:
    self.completionEngine.addProvider newCompletionProviderSnippet(self.config, self.document)
      .withMergeStrategy(MergeStrategy(kind: TakeAll))
      .withPriority(1)
    self.completionEngine.addProvider newCompletionProviderDocument(self.document)
      .withMergeStrategy(MergeStrategy(kind: FillN, max: 20))
      .withPriority(0)

  self.handleDocumentChanged()

method deinit*(self: TextDocumentEditor) =
  self.platform.onFocusChanged.unsubscribe self.onFocusChangedHandle

  self.configService.removeStore(self.config)

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
  if self.showSignatureHelpTask.isNotNil: self.showSignatureHelpTask.pause()

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

proc createEventHandler(self: TextDocumentEditor, config: EventHandlerConfig): EventHandler =
  if self.eventHandlerOverrides.contains(config.context):
    result = self.eventHandlerOverrides[config.context](config)
  else:
    assignEventHandler(result, config):
      onAction:
        if self.handleAction(action, arg, record=true).isSome:
          Handled
        else:
          Ignored
      onInput:
        self.handleInput input, record=true

proc getConfigEventHandlers(self: TextDocumentEditor): seq[EventHandler] =
  let modes = self.settings.modes.get()

  var rebuild = false
  if modes.len != self.mEventHandlers.len:
    rebuild = true
  else:
    for i, mode in modes:
      if self.mEventHandlers[i].config.context != mode:
        rebuild = true
        break

  if rebuild:
    self.mEventHandlers.setLen(modes.len)
    for i, mode in modes:
      let config = self.events.getEventHandlerConfig(mode)
      self.mEventHandlers[i] = self.createEventHandler(config)

  return self.mEventHandlers

method getEventHandlers*(self: TextDocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] =
  result = self.getConfigEventHandlers()

  if inject.contains("above-mode"):
    result.add inject["above-mode"]

  if self.showCompletions:
    let completionMode = self.settings.completionMode.get()
    if self.completionEventHandler == nil or self.completionEventHandler.config.context != completionMode:
      let config = self.events.getEventHandlerConfig(completionMode)
      assignEventHandler(self.completionEventHandler, config):
        onAction:
          if self.handleAction(action, arg, record=true).isSome:
            Handled
          else:
            Ignored
        onInput:
          self.handleInput input, record=true

    result.add self.completionEventHandler

  if inject.contains("above-completion"):
    result.add inject["above-completion"]

proc updateInlayHintsAfterChange(self: TextDocumentEditor) =
  if self.inlayHints.len > 0 and self.lastInlayHintTimestamp != self.document.buffer.snapshot.version:
    self.lastInlayHintTimestamp = self.document.buffer.snapshot.version
    let snapshot = self.document.buffer.snapshot.clone()

    for i in countdown(self.inlayHints.high, 0):
      if self.inlayHints[i].anchor.summaryOpt(Point, snapshot, resolveDeleted = false).getSome(point):
        self.inlayHints[i].hint.location = point.toCursor
        self.inlayHints[i].anchor = snapshot.anchorAt(self.inlayHints[i].hint.location.toPoint, Left)
      else:
        self.inlayHints.removeSwap(i)

proc tabWidth*(self: TextDocumentEditor): int =
  result = self.settings.tabWidth.get()
  if result == 0:
    log lvlError, &"Invalid tab width of 0 for editor '{self.getFileName()}'"
    return 4

proc requiredSignColumnWidth*(self: TextDocumentEditor): int =
  case self.settings.signs.show.get()
  of SignColumnShowKind.Auto:
    var width = 0
    let selection = self.visibleTextRange(1)
    for line in selection.first.line..selection.last.line:
      self.signs.withValue(line, value):
        var subWidth = 0
        for s in value[]:
          subWidth += s.width
        width = max(width, subWidth)

    if self.settings.signs.maxWidth.get().getSome(maxWidth):
      width = min(width, maxWidth)
    return width

  of SignColumnShowKind.Yes:
    if self.settings.signs.maxWidth.get().getSome(maxWidth):
      return maxWidth
    return 1

  of SignColumnShowKind.No:
    return 0

  of SignColumnShowKind.Number:
    return 0

proc lineNumberBounds*(self: TextDocumentEditor): Vec2 =
  # line numbers
  let lineNumbers = self.uiSettings.lineNumbers.get()
  let maxLineNumber = case lineNumbers
    of LineNumbers.Absolute: self.document.numLines
    of LineNumbers.Relative: 99
    else: 0
  let maxLineNumberLen = ($maxLineNumber).len + 1

  let lineNumberPadding = self.platform.charWidth
  result = if lineNumbers != LineNumbers.None:
    vec2(maxLineNumberLen.float32 * self.platform.charWidth + lineNumberPadding, self.platform.totalLineHeight)
  else:
    vec2()

  result.x += self.requiredSignColumnWidth().float * self.platform.charWidth

proc lineNumberWidth*(self: TextDocumentEditor): float =
  return self.lineNumberBounds.x.ceil

proc preRender*(self: TextDocumentEditor, bounds: Rect) =
  if self.document.isNil or not self.document.isInitialized:
    return

  if self.document.requiresLoad:
    self.document.load()

  let diff = self.diffDocument != nil and self.diffDocument.isInitialized

  # todo: this should account for the line number width
  let wrapWidth = if self.settings.wrapLines.get():
    let wrapMargin = self.settings.wrapMargin.get()
    let lineNumberWidth = self.lineNumberWidth()
    var wrapWidth = max(floor((bounds.w - lineNumberWidth) / self.platform.charWidth).int - wrapMargin, 10)
    if diff:
      wrapWidth = max(floor((bounds.w / 2 - lineNumberWidth) / self.platform.charWidth).int - wrapMargin, 10)
    wrapWidth
  else:
    0

  self.displayMap.setTabWidth(self.tabWidth())

  if self.displayMap.remoteId != self.document.buffer.remoteId:
    self.displayMap.setBuffer(self.document.buffer.snapshot.clone())

  if diff:
    if self.diffDisplayMap.remoteId != self.diffDocument.buffer.remoteId:
      self.diffDisplayMap.setBuffer(self.diffDocument.buffer.snapshot.clone())
    if self.diffDocument.rope.len > 1:
      self.diffDisplayMap.update(wrapWidth)

  if self.document.rope.len > 1:
    self.displayMap.update(wrapWidth)

  if self.configChanged:
    self.configChanged = false
    asyncSpawn self.updateColorOverlays()

  self.updateInlayHintsAfterChange()
  self.document.resolveDiagnosticAnchors()
  let visibleRange = self.visibleTextRange.toRange
  let bufferRange = self.lastInlayHintBufferRange
  if visibleRange.a < bufferRange.a or visibleRange.b > bufferRange.b:
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
    tint: Color = color(1, 1, 1), color: string = "", width: int = 1): Id =
  self.signs.withValue(line, val):
    val[].add (id, group, text, tint, color, width)
  do:
    self.signs[line] = @[(id, group, text, tint, color, width)]
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

    let searchResults = await findAllAsync(buffer.visibleText.slice(int), searchQuery)
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
  self.cursorHistories.setLen(0)
  self.updateSearchResults()
  self.config.detail = self.document.filename

method handleActivate*(self: TextDocumentEditor) =
  self.startBlinkCursorTask()

method handleDeactivate*(self: TextDocumentEditor) =
  log lvlInfo, fmt"Deactivate '{self.document.filename}'"
  if self.blinkCursorTask.isNotNil:
    self.blinkCursorTask.pause()
    self.cursorVisible = true
    self.markDirty()

proc scrollToCursor*(self: TextDocumentEditor, cursor: Cursor, margin: Option[float] = float.none,
    scrollBehaviour = ScrollBehaviour.none, relativePosition: float = 0.5) =
  if self.disableScrolling:
    return

  # debugf"scrollToCursor {cursor}, {margin}, {scrollBehaviour}"

  self.targetPoint = cursor.toPoint.some
  self.targetLineMargin = margin
  self.targetLineRelativeY = relativePosition

  let targetPoint = cursor.toPoint
  let textHeight = self.platform.totalLineHeight
  let charWidth = self.platform.charWidth
  let displayPoint = self.displayMap.toDisplayPoint(targetPoint)
  let targetDisplayLine = displayPoint.row.int
  let targetLineY = targetDisplayLine.float32 * textHeight + self.interpolatedScrollOffset.y
  let targetColumnX = displayPoint.column.float32 * charWidth + self.interpolatedScrollOffset.x

  let configMarginRelative = self.settings.cursorMarginRelative.get()
  let configMargin = self.settings.cursorMargin.get()
  let margin = if margin.getSome(margin):
    clamp(margin, 0.0, self.lastContentBounds.h * 0.5 - textHeight * 0.5)
  elif configMarginRelative:
    clamp(configMargin, 0.0, 1.0) * 0.5 * self.lastContentBounds.h
  else:
    clamp(configMargin * textHeight, 0.0, self.lastContentBounds.h * 0.5 - textHeight * 0.5)

  # todo: make this configurable
  let marginX = charWidth * 5

  let centerY = case scrollBehaviour.get(self.defaultScrollBehaviour):
    of CenterAlways: true
    of CenterOffscreen: targetLineY < 0 or targetLineY + textHeight > self.lastContentBounds.h
    of CenterMargin: targetLineY < margin or targetLineY + textHeight > self.lastContentBounds.h - margin
    of ScrollToMargin: false
    of TopOfScreen: false

  let centerX = case scrollBehaviour.get(self.defaultScrollBehaviour):
    of CenterAlways: true
    of CenterOffscreen: targetColumnX < 0 or targetColumnX + charWidth > self.lastContentBounds.w
    of CenterMargin: targetColumnX < marginX or targetColumnX + charWidth > self.lastContentBounds.w - marginX
    of ScrollToMargin: false
    of TopOfScreen: false

  self.nextScrollBehaviour = if centerY:
    CenterAlways.some
  else:
    scrollBehaviour

  if centerY:
    self.scrollOffset.y = self.lastContentBounds.h * relativePosition - textHeight * 0.5 - targetDisplayLine.float * textHeight
  else:
    case scrollBehaviour.get(self.defaultScrollBehaviour)
    of TopOfScreen:
      self.scrollOffset.y = margin - targetDisplayLine.float * textHeight
    else:
      if targetLineY < margin:
        self.scrollOffset.y = margin - targetDisplayLine.float * textHeight
      elif targetLineY + textHeight > self.lastContentBounds.h - margin:
        self.scrollOffset.y = self.lastContentBounds.h - margin - textHeight - targetDisplayLine.float * textHeight

  if self.scrollOffset.x != 0 or not self.settings.wrapLines.get():
    if centerX:
      self.scrollOffset.x = self.lastContentBounds.w * 0.5 - (displayPoint.column.float + 0.5) * charWidth
    else:
      case scrollBehaviour.get(self.defaultScrollBehaviour)
      of TopOfScreen:
        self.scrollOffset.x = self.lastContentBounds.w * 0.5 - (displayPoint.column.float + 0.5) * charWidth
      else:
        if targetColumnX < marginX:
          self.scrollOffset.x = marginX - displayPoint.column.float * charWidth
        elif targetColumnX + charWidth > self.lastContentBounds.w - marginX:
          self.scrollOffset.x = self.lastContentBounds.w - marginX - charWidth - displayPoint.column.float * charWidth

  self.markDirty()

proc scrollToTop*(self: TextDocumentEditor) =
  self.scrollToCursor((0, 0), scrollBehaviour = TopOfScreen.some)

proc centerCursor*(self: TextDocumentEditor, cursor: Cursor, relativePosition: float = 0.5) =
  self.scrollToCursor(cursor, scrollBehaviour = CenterAlways.some, relativePosition = relativePosition)

proc isThickCursor*(self: TextDocumentEditor): bool =
  if not self.platform.supportsThinCursor:
    return true
  return self.config.get(self.getContextWithMode("editor.text.cursor.wide"), false)

proc getCursor(self: TextDocumentEditor, selection: Selection, which: SelectionCursor): Cursor =
  case which
  of Config:
    let key = self.getContextWithMode("editor.text.cursor.movement")
    let configCursor = self.config.get(key, SelectionCursor.Both)
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
    let configCursor = self.config.get(key, SelectionCursor.Both)
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

  let scrollAmount = scroll * self.uiSettings.scrollSpeed.get()
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
      if editors.getEditorForId(wrapper.id.EditorIdNew).getSome(editor):
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

proc setLanguage(self: TextDocumentEditor, language: string) {.expose: "editor.text".} =
  self.document.languageId = language

proc getFileName*(self: TextDocumentEditor): string =
  if self.document.isNil:
    return ""
  return self.document.filename

proc lineCount(self: TextDocumentEditor): int =
  return self.document.numLines

proc lineLength*(self: TextDocumentEditor, line: int): int =
  return self.document.lineLength(line)

proc numDisplayLines*(self: TextDocumentEditor): int =
  return self.displayMap.toDisplayPoint(self.document.rope.summary.lines).row.int + 1

proc displayEndPoint*(self: TextDocumentEditor): DisplayPoint =
  return self.displayMap.toDisplayPoint(self.document.rope.summary.lines)

proc endDisplayPoint*(self: TextDocumentEditor): DisplayPoint =
  return self.displayMap.endDisplayPoint

proc endPoint*(self: TextDocumentEditor): Point =
  return self.displayMap.buffer.visibleText.endPoint

proc numWrapLines*(self: TextDocumentEditor): int =
  return self.displayMap.wrapMap.endWrapPoint.row.int + 1

proc wrapEndPoint*(self: TextDocumentEditor): WrapPoint =
  return self.displayMap.wrapMap.endWrapPoint

proc screenLineCount*(self: TextDocumentEditor): int =
  ## Returns the number of lines that can be shown on the screen
  ## This value depends on the size of the view this editor is in and the font size
  # todo
  return (self.lastContentBounds.h / self.platform.totalLineHeight).int

proc visibleDisplayRange*(self: TextDocumentEditor, buffer: int = 0): Range[DisplayPoint] =
  assert self.numDisplayLines > 0
  if self.platform.totalLineHeight == 0:
    return displayPoint(0, 0)...displayPoint(0, 0)
  let baseLine = int(-self.interpolatedScrollOffset.y / self.platform.totalLineHeight)
  var displayRange: Range[DisplayPoint]
  displayRange.a.row = clamp(baseLine - buffer, 0, self.numDisplayLines - 1).uint32
  displayRange.b.row = clamp(baseLine + self.screenLineCount + buffer + 1, 0, self.numDisplayLines).uint32
  if displayRange.b > self.endDisplayPoint:
    displayRange.b = self.endDisplayPoint

  return displayRange

proc visibleTextRange*(self: TextDocumentEditor, buffer: int = 0): Selection =
  let displayRange = self.visibleDisplayRange(buffer)
  result.first = self.displayMap.toPoint(displayRange.a).toCursor
  result.last = self.displayMap.toPoint(displayRange.b).toCursor

proc evaluateJsNode(c: var TSTreeCursor, rope: Rope, floatingPoint: var bool): float64 =
  let node = c.currentNode

  template checkRes(b: untyped): untyped =
    if not b:
      return 0

  case node.nodeType
  of "program":
    checkRes c.gotoFirstChild()
    return c.evaluateJsNode(rope, floatingPoint)

  of "expression_statement":
    checkRes c.gotoFirstChild()
    return c.evaluateJsNode(rope, floatingPoint)

  of "binary_expression":
    checkRes c.gotoFirstChild()
    checkRes c.gotoNextSibling()
    let op = c.currentNode.nodeType
    checkRes c.gotoParent()

    checkRes c.gotoFirstChild()
    let a = c.evaluateJsNode(rope, floatingPoint)
    checkRes c.gotoLastChild()
    let b = c.evaluateJsNode(rope, floatingPoint)
    checkRes c.gotoParent()
    return case op
    of "+": a + b
    of "-": a - b
    of "*": a * b
    of "/":
      let res = a / b
      if res != res.int.float:
        floatingPoint = true
      res
    of "%": a mod b
    else: a

  of "unary_expression":
    checkRes c.gotoFirstChild()
    let op = c.currentNode.nodeType
    checkRes c.gotoNextSibling()
    let a = c.evaluateJsNode(rope, floatingPoint)
    checkRes c.gotoParent()
    return case op
    of "+": a
    of "-": -a
    else: a

  of "parenthesized_expression":
    checkRes c.gotoFirstChild()
    checkRes c.gotoNextSibling()
    let a = c.evaluateJsNode(rope, floatingPoint)
    checkRes c.gotoParent()
    return a

  of "number":
    let valStr = $rope.slice(node.getRange.toSelection.toRange)
    if valStr.contains("."):
      floatingPoint = true
    let val = valStr.parseFloat.catch(0)
    checkRes c.gotoParent()
    return val

  else:
    log lvlWarn, &"Unknown js tree node type '{node.nodeType}': {node}"
    return 0

proc evaluateExpressionAsync(self: TextDocumentEditor, selections: Selections, inclusiveEnd: bool = false, prefix: string = "", suffix: string = "", addSelectionIndex: bool = false) {.async.} =
  let l = self.vfs.getTreesitterLanguage("javascript").await
  if l.getSome(l):
    withParser(p):
      if not p.setLanguage(l):
        log lvlError, &"Failed to parse: couldn't set parser language"
        return

      var texts: seq[string]
      for i, selection in selections:
        let originalText = self.document.contentString(selection, inclusiveEnd)
        var text = prefix & originalText & suffix
        if addSelectionIndex:
          text.add "+"
          text.add $i

        let rope = Rope.new(text)
        let tree = p.parseString(text)
        if tree.isNotNil:
          defer:
            tree.delete()
          tree.root.withTreeCursor(c):
            var floatingPoint = false
            let res = c.evaluateJsNode(rope, floatingPoint)
            let resStr = if floatingPoint:
              $res
            else:
              $int(res.round)
            texts.add resStr
        else:
          texts.add originalText

      assert selections.len == texts.len
      let selections = self.document.edit(selections, self.selections, texts, inclusiveEnd=inclusiveEnd)
      if inclusiveEnd:
        self.selections = selections.mapIt((it.first, self.doMoveCursorColumn(it.last, -1)))
      else:
        self.selections = selections

proc evaluateExpressions*(self: TextDocumentEditor, selections: Selections, inclusiveEnd: bool = false, prefix: string = "", suffix: string = "", addSelectionIndex: bool = false) {.expose: "editor.text".} =
  asyncSpawn self.evaluateExpressionAsync(selections, inclusiveEnd, prefix, suffix, addSelectionIndex)

# todo: remove
proc doMoveCursorLine(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool = false, includeAfter: bool = false): Cursor =
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

proc setDefaultScrollBehaviour(self: TextDocumentEditor, scrollBehaviour: ScrollBehaviour) {.expose: "editor.text".} =
  self.defaultScrollBehaviour = scrollBehaviour

# todo: remove
proc doMoveCursorVisualLine(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool = false, includeAfter: bool = false, targetColumn: Option[int] = int.none): Cursor =
  let targetColumn = targetColumn.get(self.targetColumn)
  let wrapPointOld = self.displayMap.toWrapPoint(cursor.toPoint)
  let wrapPoint = wrapPoint(max(wrapPointOld.row.int + offset, 0), targetColumn).clamp(wrapPoint()...self.wrapEndPoint)
  let newCursor = self.displayMap.toPoint(wrapPoint, if offset < 0: Bias.Left else: Bias.Right).toCursor
  if offset < 0 and newCursor.line > 0 and newCursor.line == cursor.line and self.displayMap.toWrapPoint(newCursor.toPoint).row == wrapPointOld.row:
    let newCursor2 = point(cursor.line - 1, self.document.rope.lineLen(cursor.line - 1))
    let displayPoint = self.displayMap.toDisplayPoint(newCursor2)
    let displayPoint2 = displayPoint(displayPoint.row, targetColumn.uint32)
    let point = self.displayMap.toPoint(displayPoint2)

    # echo &"doMoveCursorVisualLine {cursor}, {offset} -> {newCursor2} -> {displayPoint} -> {displayPoint2} -> {point}"
    return point.toCursor
  elif offset > 0:
    # go to wrap point and back to point one more time because if we land inside of e.g an overlay then the position will
    # be clamped which can screw up the target column we set before, so we need to calculate the target column again.
    let wrapPoint2 = wrapPoint(self.displayMap.toWrapPoint(newCursor.toPoint).row, targetColumn).clamp(wrapPoint()...self.wrapEndPoint)
    let newCursor2 = self.displayMap.toPoint(wrapPoint2, if offset < 0: Bias.Left else: Bias.Right).toCursor

    # echo &"doMoveCursorVisualLine {cursor}, {offset} -> {newCursor}, wp: {wrapPointOld} -> {wrapPoint} -> {self.displayMap.toWrapPoint(newCursor.toPoint)}, {wrapPoint2} -> {newCursor2}"
    if newCursor2.line >= self.document.numLines:
      return cursor
    return self.clampCursor(newCursor2, includeAfter)

  if newCursor.line >= self.document.numLines:
    return cursor
  return self.clampCursor(newCursor, includeAfter)

# todo: remove
proc doMoveCursorLineCenter(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool, includeAfter: bool): Cursor =
  return (cursor.line, self.document.lineLength(cursor.line) div 2)

# todo: remove
proc doMoveCursorCenter(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool, includeAfter: bool): Cursor =
  let r = self.visibleDisplayRange()
  let line = clamp((r.a.row.int + r.b.row.int) div 2, 0, self.numDisplayLines - 1)
  return self.displayMap.toPoint(displayPoint(line, self.targetColumn)).toCursor

# todo: remove
proc doMoveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int, wrap: bool = true, includeAfter: bool = true): Cursor =
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

proc includeSelectionEnd*(self: TextDocumentEditor, res: Selection, includeAfter: bool = true): Selection =
    result = res
    if not includeAfter:
      result = (res.first, self.doMoveCursorColumn(res.last, -1, wrap = false))

proc toggleFlag*(self: TextDocumentEditor, key: string) {.expose("editor.text").} =
  try:
    let value = self.config.get(key, false)
    self.config.set(key, not value)
  except CatchableError:
    discard

proc setConfig*(self: TextDocumentEditor, key: string, value: JsonNode) {.expose("editor.text").} =
  self.config.set(key, value)

proc getConfig*(self: TextDocumentEditor, key: string): JsonNode {.expose("editor.text").} =
  self.config.get(key, newJexNull()).toJson()

proc removeMode*(self: TextDocumentEditor, mode: string) {.expose("editor.text").} =
  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  var modes = self.settings.modes.get()
  let i = modes.find(mode)
  if i == -1:
    return

  modes.removeShift(mode)
  self.settings.modes.set(modes)

  let handler = self.settings.modeChangedHandlerCommand.get()
  if handler != "":
    discard self.handleActionInternal(handler, [[mode].toJson, newJArray()].toJson)

  self.markDirty()

proc setMode*(self: TextDocumentEditor, mode: string, exclusive: bool = true) {.expose("editor.text").} =
  ## Sets the current mode of the editor.
  ## If `mode` is "", then no additional scope will be pushed on the scope stac.k
  ## If mode is e.g. "insert",
  ## then the scope "editor.text.insert" will be pushed on the scope stack above "editor.text"
  ## Don't use "completion", as that is used for when a completion window is open.
  if mode == "completion":
    log(lvlError, fmt"Can't set mode to '{mode}'")
    return

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  let prefix = if exclusive:
    let i = mode.find('.')
    if i != -1:
      mode[0..i]
    else:
      ""
  else:
    ""

  var changed = false
  var removedModes = newSeq[string]()
  var modes = self.settings.modes.get()
  let alreadyContained = modes.find(mode) != -1
  var i = 0
  if exclusive and prefix != "":
    while i < modes.len:
      if modes[i].startsWith(prefix) and modes[i] != mode:
        removedModes.add(modes[i])
        modes.removeShift(i)
        changed = true
        continue
      inc i

  if not alreadyContained and mode != "":
    modes.add(mode)
    changed = true

  if not changed:
    return

  self.settings.modes.set(modes)

  self.onModeChanged.invoke (removedModes, @[mode])
  let handler = self.settings.modeChangedHandlerCommand.get()
  if handler != "":
    discard self.handleActionInternal(handler, [removedModes.toJson, [mode].toJson].toJson)

  self.markDirty()

proc setDefaultMode*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.setMode(self.settings.defaultMode.get())

proc mode*(self: TextDocumentEditor): string =
  ## Returns the current mode of the text editor, or "" if there is no mode
  let modes = self.settings.modes.get()
  if modes.len > 0:
    return modes.last
  return ""

proc modes*(self: TextDocumentEditor): seq[string] =
  ## Returns the current modes of the text editor
  return self.settings.modes.get()

proc getContextWithMode(self: TextDocumentEditor, context: string): string =
  ## Appends the current mode to context
  return context & "." & $self.mode

proc updateTargetColumn*(self: TextDocumentEditor, cursor: SelectionCursor = Last) =
  let cursor = self.getCursor(cursor)
  let wrapPoint = self.displayMap.toWrapPoint(cursor.toPoint)
  self.targetColumn = wrapPoint.column.int

proc getRevision*(self: TextDocumentEditor): int =
  return self.document.revision

proc getUsage*(self: TextDocumentEditor): string =
  return self.usage

proc getChar*(self: TextDocumentEditor, cursor: Cursor): char =
  return self.document.rope.slice(Point).charAt(cursor.toPoint)

proc getText*(self: TextDocumentEditor, selection: Selection, inclusiveEnd: bool = false): string =
  return self.document.contentString(selection, inclusiveEnd)

proc getLine*(self: TextDocumentEditor, line: int): string =
  return $self.document.getLine(line)

proc insert*(self: TextDocumentEditor, selections: seq[Selection], text: string, notify: bool = true, record: bool = true): seq[Selection] =
  return self.document.edit(selections, self.selections, [text], notify, record)

proc delete*(self: TextDocumentEditor, selections: seq[Selection], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =
  return self.document.edit(selections, self.selections, [""], notify, record, inclusiveEnd=inclusiveEnd)

proc edit*(self: TextDocumentEditor, selections: seq[Selection], texts: seq[string],
    notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =
  return self.document.edit(selections, self.selections, texts, notify, record, inclusiveEnd=inclusiveEnd)

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

proc getParentNodeSelection(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true): Selection =
  if self.document.tsTree.isNil:
    return selection

  let tree = self.document.tsTree

  var node = tree.root.descendantForRange(selection.tsRange)
  while node != tree.root:
    var r = self.includeSelectionEnd(node.getRange.toSelection, includeAfter)
    if r != selection:
      break

    node = node.parent

  result = node.getRange.toSelection
  result = self.includeSelectionEnd(result, includeAfter)

proc getNextNamedSiblingNodeSelection(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true): Option[Selection] =
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

proc getNextSiblingNodeSelection(self: TextDocumentEditor, selection: Selection, includeAfter: bool = true): Option[Selection] =
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

proc getParentNodeSelections(self: TextDocumentEditor, selections: Selections, includeAfter: bool = true): Selections =
  return selections.mapIt(self.getParentNodeSelection(it, includeAfter))

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

  if self.services.getService(ToastService).getSome(toasts):
    toasts.showToast("Treesitter tree", $node, "info")
  log lvlInfo, $node

# todo
proc selectParentCurrentTs*(self: TextDocumentEditor, includeAfter: bool = true) {.expose("editor.text").} =
  self.`selections=`(self.getParentNodeSelections(self.selections, includeAfter), addToHistory = true.some)

proc getNextNodeWithSameType*(self: TextDocumentEditor, selection: Selection, offset: int = 0,
    includeAfter: bool = true, wrap: bool = true, stepIn: bool = true, stepOut: bool = true): Option[Selection] =

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

proc shouldShowCompletionsAt*(self: TextDocumentEditor, cursor: Cursor): bool =
  ## Returns true if the completion window should automatically open at the given position
  # todo: use RopeCursor
  if cursor.column <= 0 or cursor.column > self.document.rope.lineLen(cursor.line):
    return false

  var c = self.document.rope.cursorT(cursor.toPoint)
  c.seekPrevRune()
  let previousRune = c.currentRune()
  let wordRunes {.cursor.} = self.document.settings.completionWordChars.get()
  let extraTriggerChars = if self.document.completionTriggerCharacters.len > 0:
    self.document.completionTriggerCharacters
  else:
    {'.'}

  if previousRune in wordRunes or (previousRune.int <= char.high.int and previousRune.char in extraTriggerChars):
    return true

  return false

proc autoShowSignatureHelp*(self: TextDocumentEditor, insertedText: string) {.expose("editor.text").} =
  if self.showSignatureHelp:
    return

  let triggerChars {.cursor.} = self.settings.signatureHelpTriggerChars.get()
  if insertedText.len > 0 and insertedText[0] in triggerChars:
    self.showSignatureHelp()

  elif self.settings.signatureHelpTriggerOnEditInArgs.get():
    let move = self.settings.signatureHelpMove.get()
    let argListRanges = self.getSelectionsForMove(@[self.selection], move)
    if argListRanges.len > 0:
      self.showSignatureHelp()

proc autoShowCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.disableCompletions:
    return
  if self.shouldShowCompletionsAt(self.selection.last):
    self.showCompletionWindow()
  else:
    self.hideCompletions()

proc insertText*(self: TextDocumentEditor, text: string, autoIndent: bool = true, autoClose: Option[bool] = bool.none) {.expose("editor.text").} =
  if self.document.singleLine and text == "\n":
    return

  let originalSelections = self.selections.normalized
  var selections = originalSelections
  var resultSelectionsRelative = newSeq[Cursor]()
  for i in 0..<selections.len:
    resultSelectionsRelative.add TextSummary.init(text).lines.toCursor

  var texts = @[text]

  var locations = initHashSet[Cursor]()
  for anchor in self.lastAutoCloseLocations:
    let cursor = anchor.summaryOpt(Point, self.document.buffer.snapshot)
    if cursor.isSome:
      locations.incl cursor.get.toCursor

  var insertedExistingAutoClose = false
  if text.len > 0 and text == self.lastAutoCloseText and self.lastAutoCloseLocations.len > 0:
    for s in selections.mitems:
      if s.isEmpty and s.last in locations and self.document.runeAt(s.last) == text.runeAt(0):
        s.last.column += 1
        insertedExistingAutoClose = true

  var allWhitespace = false
  var insertedAutoIndent = false
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
      insertedAutoIndent = true
      texts.setLen(selections.len)

      let matchingClosingGroupText = getMatchingGroupChar(text)

      for i, selection in selections:
        var indentClosing = false
        if selection.first.column > 0:
          let runeLeft = self.document.runeAt (selection.first.line, selection.first.column - 1)
          let runeRight = self.document.runeAt selection.last

          if runeLeft.getMatchingGroupChar() == runeRight:
            indentClosing = true

        # todo: don't use getLine
        let line = $self.document.getLine(selection.last.line)
        let indent = indentForNewLine(self.document.settings.indentAfter.get(), line, self.document.settings.indent.get(), self.document.settings.tabWidth.get(), selection.last.column)
        if indent.len > 0:
          texts[i].add indent
          resultSelectionsRelative[i].column += indent.len

          if indentClosing:
            let indent2 = indentForNewLine(self.document.settings.indentAfter.get(), line, self.document.settings.indent.get(), self.document.settings.tabWidth.get(), selection.last.column, -1)
            texts[i].add "\n"
            texts[i].add indent2

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
      let openLocation = self.document.rope.findSurroundStart((s.first.line, s.first.column - 1), open, close, 1).getOr:
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

  var insertedAutoClose = false
  if not insertedExistingAutoClose and autoClose.get(self.settings.autoInsertClose.get()):
    case text
    of "(", "{", "[", "\"", "'", "<":
      let close = case text
      of "(": ")"
      of "{": "}"
      of "[": "]"
      of "\"": "\""
      of "'": "'"
      of "<": ">"
      else:
        "?"

      var isAtExpressionStart = false
      for s in selections:
        if self.document.isAtExpressionStart(s.last):
          isAtExpressionStart = true
          break

      var isAfterSpace = false
      if text == "<":
        for s in selections:
          if s.last.column > 0 and self.document.runeAt((s.last.line, s.last.column - 1)) == ' '.Rune:
            isAfterSpace = true
            break

      if not isAtExpressionStart and not isAfterSpace:
        for t in texts.mitems:
          t.add close
        insertedAutoClose = true
        self.lastAutoCloseText = close
    else:
      discard

  var newSelections = self.document.edit(selections, selections, texts)
  selections = newSelections.mapIt(it.last.toSelection)

  for i in 0..newSelections.high:
    if i < resultSelectionsRelative.len:
      selections[i].last = (newSelections[i].first.toPoint + resultSelectionsRelative[i].toPoint).toCursor
      selections[i].first = selections[i].last

  if insertedAutoClose:
    self.lastAutoCloseLocations.setLen(0)
    for s in newSelections.items:
      self.lastAutoCloseLocations.add self.document.buffer.snapshot.anchorAfter(point(s.last.line, s.last.column - 1))

  if allWhitespace:
    for i in 0..min(self.selections.high, originalSelections.high):
      selections[i].first.column = originalSelections[i].first.column
      selections[i].last.column = originalSelections[i].last.column

  self.selections = selections

  self.updateTargetColumn(Last)

  self.autoShowCompletions()
  self.autoShowSignatureHelp(text)

proc insertRawAsync(self: TextDocumentEditor) {.async.} =
  let text = await self.layout.promptString("Enter number")
  if text.isNone or self.document.isNil:
    return

  try:
    var num = 0
    if text.get.startsWith("0x"):
      discard text.get.toOpenArray(2, text.get.high).parseHex(num)
    elif text.get.startsWith("0b"):
      discard text.get.toOpenArray(2, text.get.high).parseBin(num)
    elif text.get.startsWith("0o"):
      discard text.get.toOpenArray(2, text.get.high).parseOct(num)
    else:
      discard text.get.parseInt(num)

    let r = num.Rune
    self.insertText($r)
  except CatchableError as e:
    log lvlError, &"Failed to parse '{text}': {e.msg}"

proc insertRaw*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.insertRawAsync()

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

  let indent = self.document.getIndentString()
  var indentSelections: Selections = @[]
  for l in linesToIndent:
    indentSelections.add (l, 0).toSelection

  discard self.document.edit(indentSelections.normalized, self.selections, [indent])

  var selections = self.selections
  for s in selections.mitems:
    if s.first.line in linesToIndent:
      s.first.column += self.document.getIndentColumns()
    if s.last.line in linesToIndent:
      s.last.column += self.document.getIndentColumns()
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
    case self.document.settings.indent.get()
    of Spaces:
      let firstNonWhitespace = self.document.rope.indentBytes(l)
      indentSelections.add ((l, 0), (l, min(self.document.getIndentColumns(), firstNonWhitespace)))
    of Tabs:
      indentSelections.add ((l, 0), (l, 1))

  var selections = self.selections
  discard self.document.edit(indentSelections.normalized, self.selections, [""])

  for s in selections.mitems:
    if s.first.line in linesToIndent:
      s.first.column = max(0, s.first.column - self.document.getIndentColumns())
    if s.last.line in linesToIndent:
      s.last.column = max(0, s.last.column - self.document.getIndentColumns())
  self.selections = selections

proc insertIndent*(self: TextDocumentEditor) {.expose("editor.text").} =
  var insertTexts = newSeq[string]()

  # todo: for spaces, calculate alignment
  let indent = self.document.getIndentString()
  for selection in self.selections:
    insertTexts.add indent

  self.selections = self.document.edit(self.selections, self.selections, insertTexts).mapIt(
    it.last.toSelection)

proc undo*(self: TextDocumentEditor, checkpoint: string = "word") {.expose("editor.text").} =
  if self.document.undo(self.selections, true, checkpoint).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

proc redo*(self: TextDocumentEditor, checkpoint: string = "word") {.expose("editor.text").} =
  if self.document.redo(self.selections, true, checkpoint).getSome(selections):
    self.selections = selections
    self.scrollToCursor(Last)
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

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

proc copy*(self: TextDocumentEditor, register: string = "", inclusiveEnd: bool = false) {.expose("editor.text").} =
  asyncSpawn self.copyAsync(register, inclusiveEnd)

proc pasteAsync*(self: TextDocumentEditor, selections: seq[Selection], registerName: string, inclusiveEnd: bool = false):
    Future[void] {.async.} =
  log lvlInfo, fmt"paste register from '{registerName}', inclusiveEnd: {inclusiveEnd}"

  var register: Register
  if not self.registers.getRegisterAsync(registerName, register.addr).await:
    return

  if self.document.isNil:
    return

  let numLines = register.numLines()

  let newSelections = if numLines == selections.len and numLines > 1:
    case register.kind
    of RegisterKind.Text:
      let lines = register.text.splitLines()
      self.document.edit(selections, selections, lines, notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
    of RegisterKind.Rope:
      let lines = register.rope.splitLines()
      self.document.edit(selections, selections, lines, notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
  else:
    case register.kind
    of RegisterKind.Text:
      self.document.edit(selections, selections, [register.text.move], notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)
    of RegisterKind.Rope:
      self.document.edit(selections, selections, [register.rope.move], notify=true, record=true, inclusiveEnd=inclusiveEnd).mapIt(it.last.toSelection)

  # add list of selections for what was just pasted to history
  if newSelections.len == selections.len:
    var tempSelections = newSelections
    for i in 0..tempSelections.high:
      tempSelections[i].first = selections[i].first
    self.selections = tempSelections

  self.selections = newSelections
  self.scrollToCursor(Last)
  self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)
  self.markDirty()

proc paste*(self: TextDocumentEditor, registerName: string = "", inclusiveEnd: bool = false) {.expose("editor.text").} =
  asyncSpawn self.pasteAsync(self.selections, registerName, inclusiveEnd)

proc scrollText*(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.scrollOffset.y += amount
  self.markDirty()

proc scrollTextHorizontal*(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  if self.disableScrolling:
    return
  self.scrollOffset.x += amount * self.platform.charWidth
  self.markDirty()

proc scrollLines(self: TextDocumentEditor, amount: int) {.expose("editor.text").} =
  ## Scroll the text up (positive) or down (negative) by the given number of lines

  if self.disableScrolling:
    return

  self.scrollOffset.y += self.platform.totalLineHeight * amount.float

  self.markDirty()

# todo
proc addCursorBelow*(self: TextDocumentEditor) {.expose("editor.text").} =
  let newCursor = self.doMoveCursorLine(self.selections[self.selections.high].last, 1).toSelection
  if not self.selections.contains(newCursor):
    self.selections = self.selections & @[newCursor]

# todo
proc addCursorAbove*(self: TextDocumentEditor) {.expose("editor.text").} =
  let newCursor = self.doMoveCursorLine(self.selections[self.selections.high].last, -1).toSelection
  if not self.selections.contains(newCursor):
    self.selections = self.selections & @[newCursor]

proc getPrevFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection =
  self.updateSearchResults()

  if self.searchResults.len == 0:
    return cursor.toSelection

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

proc getNextFindResult*(self: TextDocumentEditor, cursor: Cursor, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection =
  self.updateSearchResults()

  if self.searchResults.len == 0:
    return cursor.toSelection

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

proc createAnchors*(self: TextDocumentEditor, selections: Selections): seq[(Anchor, Anchor)] =
  if self.document.requiresLoad:
    return @[]
  let snapshot {.cursor.} = self.document.buffer.snapshot
  return selections.mapIt (snapshot.anchorAfter(it.first.toPoint), snapshot.anchorBefore(it.last.toPoint))

proc resolveAnchors*(self: TextDocumentEditor, anchors: seq[(Anchor, Anchor)]): Selections =
  if self.document.requiresLoad:
    return @[]
  return anchors.mapIt (it[0].summaryOpt(Point, self.snapshot).get(Point()), it[1].summaryOpt(Point, self.snapshot).get(Point())).toSelection

proc getPrevDiagnostic*(self: TextDocumentEditor, cursor: Cursor, severity: int = 0, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection =

  self.document.resolveDiagnosticAnchors()

  var i = 0
  for line in countdown(cursor.line, 0):
    for diagnosticsData in self.document.diagnosticsPerLS.mitems:
      diagnosticsData.diagnosticsPerLine.withValue(line, val):
        let diagnosticsOnCurrentLine {.cursor.} = val[]
        for k in countdown(diagnosticsOnCurrentLine.high, 0):
          let diagnosticIndex = diagnosticsOnCurrentLine[k]
          if diagnosticIndex > diagnosticsData.currentDiagnostics.high:
            continue

          let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[diagnosticIndex]
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

proc getNextDiagnostic*(self: TextDocumentEditor, cursor: Cursor, severity: int = 0, offset: int = 0, includeAfter: bool = true, wrap: bool = true): Selection =

  self.document.resolveDiagnosticAnchors()

  var i = 0
  for line in cursor.line..<self.document.numLines:
    for diagnosticsData in self.document.diagnosticsPerLS.mitems:
      diagnosticsData.diagnosticsPerLine.withValue(line, val):
        for diagnosticIndex in val[]:
          if diagnosticIndex > diagnosticsData.currentDiagnostics.high:
            continue

          let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[diagnosticIndex]
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

  self.cursorHistories.setLen(0)
  self.diffDocument.onRequestRerender.unsubscribe(self.onRequestRerenderDiffHandle)
  self.diffDocument.deinit()
  self.diffDocument = nil
  self.markDirty()

proc getPrevChange*(self: TextDocumentEditor, cursor: Cursor): Selection =
  if self.diffChanges.isNone:
    return cursor.toSelection

  for i in countdown(self.diffChanges.get.high, 0):
    if self.diffChanges.get[i].target.first < cursor.line:
      return (self.diffChanges.get[i].target.first, 0).toSelection

  return cursor.toSelection

proc getNextChange*(self: TextDocumentEditor, cursor: Cursor): Selection =
  if self.diffChanges.isNone:
    return cursor.toSelection

  for mapping in self.diffChanges.get:
    if mapping.target.first > cursor.line:
      return ((mapping.target.first, 0), (mapping.target.last, 0))

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
      self.diffDocument.usage = "text-diff"
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
      self.diffDocument.usage = "text-diff"
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
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

  self.cursorHistories.setLen(0)
  self.markDirty()

proc clearOverlays*(self: TextDocumentEditor, id: int = -1) {.expose("editor.text").} =
  self.displayMap.overlay.clear(id)
  self.markDirty()

proc addOverlay*(self: TextDocumentEditor, selection: Selection, text: string, id: int, scope: string, bias: Bias) {.expose("editor.text").} =
  self.displayMap.overlay.addOverlay(selection.toRange, text, id, scope, bias)
  self.markDirty()

proc updateDiff*(self: TextDocumentEditor, gotoFirstDiff: bool = false) {.expose("editor.text").} =
  self.showDiff = true
  asyncSpawn self.updateDiffAsync(gotoFirstDiff)

proc revertSelectedAsync*(self: TextDocumentEditor, inclusiveEnd: bool = false) {.async: (raises: []).} =
  try:
    if self.diffDocument.isNil or self.diffChanges.isNone:
      return

    var selection = self.selection.normalized
    if inclusiveEnd:
      selection.last = self.doMoveCursorColumn(selection.last, 1)

    log lvlInfo, &"Revert ranges {selection}"

    let ropeOld = self.diffDocument.rope.clone()
    var ropeDiff: RopeDiff[Point]

    for mapping in self.diffChanges.get:
      var rangeOld: Range[Point]
      var rangeNew: Range[Point]
      rangeOld.a.row = mapping.source.first.uint32
      rangeOld.b.row = mapping.source.last.uint32
      rangeNew.a.row = mapping.target.first.uint32
      rangeNew.b.row = mapping.target.last.uint32

      var text = Rope.new("")
      for line in mapping.lines:
        text.add line
        text.add "\n"

      if rangeNew.a <= selection.last.toPoint and rangeNew.b >= selection.first.toPoint:
        ropeDiff.edits.add (rangeNew, rangeOld, ropeOld.slice(rangeOld))

    let selections = ropeDiff.edits.mapIt(it.old.toSelection)
    let texts = ropeDiff.edits.mapIt(it.text)
    discard self.document.edit(selections, self.selections, texts)
    await self.document.saveAsync()
    self.updateDiff()
  except CatchableError as e:
    log lvlError, &"Failed to revert the selected change: {e.msg}"

proc unstageSelectedAsync*(self: TextDocumentEditor, inclusiveEnd: bool = false) {.async: (raises: []).} =
  try:
    if self.diffDocument.isNil or self.diffChanges.isNone:
      return

    var selection = self.selection.normalized
    if inclusiveEnd:
      selection.last = self.doMoveCursorColumn(selection.last, 1)

    log lvlInfo, &"Revert ranges {selection}"

    let ropeOld = self.diffDocument.rope.clone()
    var ropeDiff: RopeDiff[Point]

    for mapping in self.diffChanges.get:
      var rangeOld: Range[Point]
      var rangeNew: Range[Point]
      rangeOld.a.row = mapping.source.first.uint32
      rangeOld.b.row = mapping.source.last.uint32
      rangeNew.a.row = mapping.target.first.uint32
      rangeNew.b.row = mapping.target.last.uint32

      var text = Rope.new("")
      for line in mapping.lines:
        text.add line
        text.add "\n"

      if rangeNew.a <= selection.last.toPoint and rangeNew.b >= selection.first.toPoint:
        # todo
        discard

      else:
        ropeDiff.edits.add (rangeOld, rangeNew, text.slice(Point))

    let new = ropeOld.slice(Point).apply(ropeDiff)
    let filename = self.getFileName().extractFilename
    let backupPath = &"ws0://temp/git/backup.{filename}"
    let originalPath = self.document.filename
    let originalPathLocalized = self.document.localizedPath
    let backupPathLocalized = self.vfs.localize(backupPath)
    if self.vcs.getVcsForFile(originalPathLocalized).getSome(vcs):
      log lvlInfo, &"backup {originalPath} to {backupPath}"
      await self.vfs.copyFile(originalPathLocalized, backupPathLocalized)
      await self.vfs.write(originalPath, new)
      discard await vcs.stageFile(originalPathLocalized)
      log lvlInfo, &"restore backup {backupPath} -> {originalPath}"
      await self.vfs.copyFile(backupPathLocalized, originalPathLocalized)
      discard await self.vfs.delete(backupPath)

      self.updateDiff()
  except CatchableError as e:
    log lvlError, &"Failed to unstage the selected change: {e.msg}"

proc stageSelectedAsync*(self: TextDocumentEditor, inclusiveEnd: bool = false) {.async: (raises: []).} =
  try:
    if self.diffDocument.isNil or self.diffChanges.isNone:
      return

    var selection = self.selection.normalized
    if inclusiveEnd:
      selection.last = self.doMoveCursorColumn(selection.last, 1)

    log lvlInfo, &"Stage ranges {selection}"

    var ropeDiff: RopeDiff[Point]

    let stagedRope = self.diffDocument.rope.clone()

    for mapping in self.diffChanges.get:
      var rangeOld: Range[Point]
      var rangeNew: Range[Point]
      rangeOld.a.row = mapping.source.first.uint32
      rangeOld.b.row = mapping.source.last.uint32
      rangeNew.a.row = mapping.target.first.uint32
      rangeNew.b.row = mapping.target.last.uint32

      if rangeNew.a <= selection.last.toPoint and rangeNew.b >= selection.first.toPoint:
        var rangeNewClamped = rangeNew
        rangeNewClamped.a = max(rangeNew.a, selection.first.toPoint)
        rangeNewClamped.b = min(rangeNew.b, selection.last.toPoint)

        var text = Rope.new("")
        for line in mapping.lines:
          text.add line
          text.add "\n"

        let rangeNewRel = (rangeNewClamped.a - rangeNew.a).toPoint...(rangeNewClamped.b - rangeNew.a).toPoint
        if selection.isEmpty or (selection.first.toPoint <= rangeNew.a and selection.last.toPoint >= rangeNew.b):
          ropeDiff.edits.add (rangeOld, rangeNew, text.slice(Point))

        else:
          let textOld = stagedRope.slice(rangeOld)
          let diff = diff(textOld, text.slice(Point))
          let rangeOldRel = diff.newToOld(rangeNewRel)
          let rangeOldClamped = rangeOld.a + rangeOldRel

          ropeDiff.edits.add (rangeOldClamped, rangeNewClamped, text.slice(rangeNewRel))

    let new = self.diffDocument.rope.slice(Point).apply(ropeDiff)
    let filename = self.getFileName().extractFilename
    let backupPath = &"ws0://temp/git/backup.{filename}"
    let originalPath = self.document.filename
    let originalPathLocalized = self.document.localizedPath
    let backupPathLocalized = self.vfs.localize(backupPath)
    if self.vcs.getVcsForFile(originalPathLocalized).getSome(vcs):
      log lvlInfo, &"backup {originalPath} to {backupPath}"
      await self.vfs.copyFile(originalPathLocalized, backupPathLocalized)
      await self.vfs.write(originalPath, new)
      discard await vcs.stageFile(originalPathLocalized)
      log lvlInfo, &"restore backup {backupPath} -> {originalPath}"
      await self.vfs.copyFile(backupPathLocalized, originalPathLocalized)
      discard await self.vfs.delete(backupPath)

      self.updateDiff()
  except CatchableError as e:
    log lvlError, &"Failed to stage the selected change: {e.msg}"

  # this tries to create a patch and apply it to the index directly, but git refuses the patch and the line indices
  # are maybe wrong

  # let stagedPath = &"ws0://temp/git/staged.{filename}"
  # let newPath = &"ws0://temp/git/new.{filename}"
  # let diffPath = &"ws0://temp/git/{filename}.diff"
  # await self.vfs.write(stagedPath, self.diffDocument.rope.clone())
  # await self.vfs.write(newPath, new)

  # let workspaceRoot = self.vfs.localize("ws0://")

  # let pathA = self.vfs.localize(stagedPath)
  # let pathB = self.vfs.localize(newPath)
  # let gitDiff = await runProcessAsyncOutput("git", @["diff", "--no-index", "-U0", pathA, pathB])

  # let originalPath = self.document.localizedPath.relativePath(workspaceRoot).catch(self.document.localizedPath)
  # var patch = gitDiff.output.replace(pathA, originalPath).replace(pathB, originalPath)
  # let nl1 = patch.find("\n")
  # let nl2 = patch.find("\n", nl1 + 1)
  # if nl2 > 0:
  #   patch = patch[nl2+1..^1]
  # await self.vfs.write(diffPath, patch)

  # let gitApply = await runProcessAsyncOutput("git", @["apply", "--cached", "-v", self.vfs.localize(diffPath)])
  # echo &"git apply -> \n{gitApply.output}\n--------\n{gitApply.err}\n=============="
  # self.updateDiff()

proc revertSelected*(self: TextDocumentEditor, inclusiveEnd: bool = false) {.expose("editor.text").} =
  asyncSpawn self.revertSelectedAsync(inclusiveEnd)

proc stageSelected*(self: TextDocumentEditor, inclusiveEnd: bool = false) {.expose("editor.text").} =
  if self.document.staged:
    asyncSpawn self.unstageSelectedAsync(inclusiveEnd)
  else:
    asyncSpawn self.stageSelectedAsync(inclusiveEnd)

proc stageFileAsync(self: TextDocumentEditor): Future[void] {.async.} =
  if self.vcs.getVcsForFile(self.document.filename).getSome(vcs):
    discard await vcs.stageFile(self.document.localizedPath)

    if self.diffDocument.isNotNil:
      self.updateDiff()

proc stageFile*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.stageFileAsync()

proc format*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.document.format(runOnTempFile = true)

proc checkoutFileAsync*(self: TextDocumentEditor, saveAfterwards: bool = false) {.async.} =
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
  self.document.save()
  self.markDirty()

proc checkoutFile*(self: TextDocumentEditor, saveAfterwards: bool = false) {.expose("editor.text").} =
  asyncSpawn self.checkoutFileAsync(saveAfterwards)

proc addFileVcs*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.document.addFileVcsAsync(prompt = false)

# todo
proc addNextFindResultToSelection*(self: TextDocumentEditor, includeAfter: bool = true,
    wrap: bool = true) {.expose("editor.text").} =
  self.selections = self.selections &
    @[self.getNextFindResult(self.selection.last, includeAfter=includeAfter)]

# todo
proc addPrevFindResultToSelection*(self: TextDocumentEditor, includeAfter: bool = true,
    wrap: bool = true) {.expose("editor.text").} =
  self.selections = self.selections &
    @[self.getPrevFindResult(self.selection.first, includeAfter=includeAfter)]

# todo
proc setAllFindResultToSelection*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.updateSearchResults()

  var selections: seq[Selection] = @[]
  for s in self.searchResults:
    selections.add s.toSelection
  if selections.len > 0:
    self.selections = selections

# todo
proc moveCursorVisualLine*(self: TextDocumentEditor, distance: int,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true,
    includeAfter: bool = true) {.expose("editor.text").} =

  var minLine = int.high
  var maxLine = int.low
  for s in self.selections:
    minLine = min(minLine, s.last.line)
    maxLine = max(maxLine, s.last.line)

  proc doMoveCursor(self: TextDocumentEditor, cursor: Cursor, offset: int,
      wrap: bool = true, includeAfter: bool = true): Cursor =
    let targetColumn = if maxLine - minLine + 1 < self.selections.len:
      self.displayMap.toDisplayPoint(cursor.toPoint).column.int
    else:
      self.targetColumn
    self.doMoveCursorVisualLine(cursor, offset, wrap, includeAfter, targetColumn.some)
  self.moveCursor(cursor, doMoveCursor, distance, all, wrap, includeAfter)

# todo
proc moveCursorVisualPage*(self: TextDocumentEditor, distance: float,
    cursor: SelectionCursor = SelectionCursor.Config, all: bool = true, wrap: bool = true,
    includeAfter: bool = true) {.expose("editor.text").} =

  let visibleLines = self.screenLineCount()
  let linesToMove = int(visibleLines.float * distance)
  self.moveCursorVisualLine(linesToMove, cursor, all, wrap, includeAfter)

# todo
proc moveCursorLineCenter*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLineCenter, 0, all)
  self.updateTargetColumn(cursor)

# todo
proc moveCursorCenter*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    all: bool = true) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorCenter, 0, all)

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config,
    margin: Option[float] = float.none, scrollBehaviour: Option[ScrollBehaviour] = ScrollBehaviour.none, relativePosition: float = 0.5) =
  self.scrollToCursor(self.getCursor(cursor), margin, scrollBehaviour, relativePosition)

proc setNextScrollBehaviour*(self: TextDocumentEditor, scrollBehaviour: ScrollBehaviour) =
  self.nextScrollBehaviour = scrollBehaviour.some

proc setDefaultSnapBehaviour*(self: TextDocumentEditor, snapBehaviour: ScrollSnapBehaviour) {.expose("editor.text").} =
  self.defaultSnapBehaviour = snapBehaviour

proc setNextSnapBehaviour*(self: TextDocumentEditor, snapBehaviour: ScrollSnapBehaviour) =
  self.nextSnapBehaviour = snapBehaviour.some
  if snapBehaviour == Always:
    self.interpolatedScrollOffset = self.scrollOffset

proc setCursorScrollOffset*(self: TextDocumentEditor, offset: float,
    cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  let displayPoint = self.displayMap.toDisplayPoint(self.getCursor(cursor).toPoint)
  self.scrollOffset.y = offset - displayPoint.row.float * self.platform.totalLineHeight
  self.markDirty()

proc setCursorScrollOffset*(self: TextDocumentEditor, cursor: Cursor, offset: float) =
  let displayPoint = self.displayMap.toDisplayPoint(cursor.toPoint)
  self.scrollOffset.y = offset * self.platform.totalLineHeight - displayPoint.row.float * self.platform.totalLineHeight
  self.markDirty()

proc getContentBounds*(self: TextDocumentEditor): Vec2 =
  # todo
  return self.lastContentBounds.wh

proc centerCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
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

proc getCommandCount*(self: TextDocumentEditor): int =
  return self.commandCount

proc setCommandCount*(self: TextDocumentEditor, count: int) =
  self.commandCount = count

proc setCommandCountRestore*(self: TextDocumentEditor, count: int) =
  self.commandCountRestore = count

proc updateCommandCount*(self: TextDocumentEditor, digit: int) =
  self.commandCount = self.commandCount * 10 + digit

proc runAction*(self: TextDocumentEditor, action: string, args: JsonNode): Option[JsonNode] {.expose("editor.text").} =
  # echo "runAction ", action, ", ", $args
  return self.handleActionInternal(action, args)

proc findWordBoundary*(self: TextDocumentEditor, cursor: Cursor): Selection =
  self.document.findWordBoundary(cursor)

proc extendSelectionWithMove*(self: TextDocumentEditor, selection: Selection, move: string, count: int = 0): Selection =
  result = self.getSelectionForMove(selection.first, move, count) or
    self.getSelectionForMove(selection.last, move, count)
  if selection.isBackwards:
    result = result.reverse

proc applyMoveFallback(self: TextDocumentEditor, move: string, selections: openArray[Selection], count: int, largs: openArray[LispVal], env: Env): seq[Selection] =
  if self.moveDatabase.debugMoves:
    debugf"applyMoveFallback {move}, {count}, {@largs}, {env.env}"

  let includeEol = true

  let cursorSelector = self.config.get(self.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)

  var move = move
  var args: JsonNode = nil
  var argsString = ""
  var hasArgs = false
  var parsedArgs = false
  let argsStart = move.find(" ")
  if argsStart > 0:
    hasArgs = true
    argsString = move[(argsStart + 1)..^1]
    move = move[0..<argsStart]

  proc parseArgs(move: var string, args: var JsonNode) =
    parsedArgs = true
    if hasArgs:
      try:
        args = newJArray()
        for a in newStringStream(argsString).parseJsonFragments():
          args.add a
      except CatchableError as e:
        log lvlError, &"getSelectionsForMove: '{move}', Failed to parse args: {e.msg}"

  template getArg(index: int, typ: untyped, default: untyped): untyped =
    block:
      if not parsedArgs:
        parseArgs(move, args)

      if args != nil and index < args.len:
        try:
          args[index].to(typ)
        except CatchableError as e:
          log lvlError, "In move '" & move & "': Failed to convert argument " & $index & " to typ " & $typ & ": " & e.msg
          default
      else:
        default

  try:
    case move
    of "word":
      return selections.mapIt(self.findWordBoundary(it.last))

    of "page":
      let linesToMove = int(self.screenLineCount() * count div 100)
      return selections.mapIt(self.doMoveCursorLine(it.last, linesToMove, false, includeEol).toSelection(it, cursorSelector))

    of "prev-search-result":
      let count = getArg(0, int, 0)
      let wrap = getArg(1, bool, true)
      result = selections.mapIt(self.getPrevFindResult(it.last, count, includeEol, wrap))

    of "next-search-result":
      let count = getArg(0, int, 0)
      let wrap = getArg(1, bool, true)
      result = selections.mapIt(self.getNextFindResult(it.last, count, includeEol, wrap))

    of "prev-change":
      result = selections.mapIt(self.getPrevChange(it.last))

    of "next-change":
      result = selections.mapIt(self.getNextChange(it.last))

    of "prev-diagnostic":
      let severity = getArg(0, int, 0)
      let count = getArg(1, int, 0)
      let wrap = getArg(2, bool, true)
      result = selections.mapIt(self.getPrevDiagnostic(it.last, severity, count, includeEol, wrap))

    of "next-diagnostic":
      let severity = getArg(0, int, 0)
      let count = getArg(1, int, 0)
      let wrap = getArg(2, bool, true)
      result = selections.mapIt(self.getNextDiagnostic(it.last, severity, count, includeEol, wrap))

    of "next-tab-stop":
      result = @selections
      if self.currentSnippetData.isNone:
        return

      var foundTabStop = false
      while self.currentSnippetData.get.currentTabStop < self.currentSnippetData.get.highestTabStop:
        self.currentSnippetData.get.currentTabStop.inc
        self.currentSnippetData.get.tabStops.withValue(self.currentSnippetData.get.currentTabStop, val):
          result = val[]
          foundTabStop = true
          break

      if not foundTabStop:
        self.currentSnippetData.get.currentTabStop = 0
        result = self.currentSnippetData.get.tabStops[0]

    of "prev-tab-stop":
      result = @selections
      if self.currentSnippetData.isNone:
        return

      if self.currentSnippetData.get.currentTabStop == 0:
        self.currentSnippetData.get.currentTabStop = self.currentSnippetData.get.highestTabStop
        self.currentSnippetData.get.tabStops.withValue(self.currentSnippetData.get.currentTabStop, val):
          result = val[]
        return

      while self.currentSnippetData.get.currentTabStop > 1:
        self.currentSnippetData.get.currentTabStop.dec
        self.currentSnippetData.get.tabStops.withValue(self.currentSnippetData.get.currentTabStop, val):
          result = val[]
          break

    of "ts-text-object", "ts":
      let capture = if largs.len > 0:
        largs[0].toJson.jsonTo(string)
      else:
        ""
      let captureMove = if largs.len > 1:
        largs[1]
      else:
        parseLisp("(combine)")

      if self.document.textObjectsQuery != nil and not self.document.tsTree.isNil:
        for s in selections:
          for captures in self.document.textObjectsQuery.query(self.document.tsTree, s):
            var captureSelections = newSeqOfCap[Selection](captures.len)
            if self.moveDatabase.debugMoves:
              echo &"move 'ts' {move}: {captures.len} captures"
            for (node, nodeCapture) in captures:
              if capture == "" or capture == nodeCapture:
                var sel = node.getRange().toSelection
                captureSelections.add sel
                if self.moveDatabase.debugMoves:
                  echo &"    {sel}"

            let captureSelectionsTransformed = self.moveDatabase.applyMove(self.displayMap, captureMove, captureSelections, env, self.moveFallbacks)

            result.add captureSelectionsTransformed

    else:
      log lvlError, &"Unknown move '{move}'"
      return @selections

  except CatchableError as e:
    log lvlError, &"Failed to apply move '{move}': {e.msg}"
    return @selections

proc getSelectionsForMove*(self: TextDocumentEditor, selections: openArray[Selection], move: string,
    count: int = 0, includeEol: bool = true, wrap: bool = true, options: JsonNode = nil): seq[Selection] =
  var env = Env()
  env["screen-lines"] = newNumber(self.screenLineCount())
  env["target-column"] = newNumber(self.targetColumn)
  env["count"] = newNumber(count)
  env["include-eol"] = newBool(includeEol)
  env["wrap"] = newBool(wrap)
  env["ts?"] = newBool(not self.document.tsTree.isNil)
  env["ts.to?"] = newBool(self.document.textObjectsQuery != nil and not self.document.tsTree.isNil)
  defer:
    env.clear()

  proc readOptions(env: var Env, options: JsonNode) =
    if options.kind == JObject:
      for (key, val) in options.fields.pairs:
        try:
          env[key] = val.jsonTo(LispVal)
        except CatchableError as e:
          log lvlError, "Failed to convert option " & key & " = " & $val & " to lisp value: " & e.msg
    else:
      log lvlError, "Invalid move options, expected object: " & $options

  if options != nil:
    if options.kind == JArray:
      for o in options.elems:
        env.readOptions(o)
    else:
      env.readOptions(options)

  return self.moveDatabase.applyMove(self.displayMap, move, selections, self.moveFallbacks, env)

proc getSelectionForMove*(self: TextDocumentEditor, cursor: Cursor, move: string,
    count: int = 0, includeEol: bool = true): Selection =
  let selections = self.getSelectionsForMove([cursor.toSelection], move, count, includeEol)
  if selections.len > 0:
    return selections[0]
  else:
    return cursor.toSelection
  # defer:
  #   debugf"getSelectionForMove '{move}', {cursor} -> {result}"
  # case move

  # of "line-back":
  #   let first = if cursor.line > 0 and cursor.column == 0:
  #     (cursor.line - 1, self.document.lineLength(cursor.line - 1))
  #   else:
  #     (cursor.line, 0)
  #   result = (first, (cursor.line, self.document.lineLength(cursor.line)))

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
    let cursorSelector = self.config.get(key, SelectionCursor.Both)
    return self.cursor(selection, cursorSelector)
  of Both:
    return selection.last
  of First:
    return selection.first
  of Last, LastToFirst:
    return selection.last

proc deleteMove*(self: TextDocumentEditor, move: string, updateTargetColumn: bool = true, options {.varargs.}: JsonNode = newJObject()) {.expose("editor.text").} =
  ## Deletes text based on the current selections.
  ##
  ## `move` specifies which move should be applied to each selection.
  let selections = self.getSelectionsForMove(self.selections, move, 1, true, true, options)
  self.selections = self.document.edit(selections, self.selections, [""])
  self.scrollToCursor(Last)
  self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)
  if updateTargetColumn:
    self.updateTargetColumn(Last)

proc extendSelectMove*(self: TextDocumentEditor, move: string, inside: bool = false,
    which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = self.config.get("text.move-count", 0)

  self.selections = if inside:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => self.extendSelectionWithMove(s, move, count))
  else:
    self.selections.mapAllOrLast(all, (s) {.gcsafe, raises: [].} => (
      self.getCursor(s, which),
      self.getCursor(self.extendSelectionWithMove(s, move, count), which)
    ))

  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc move*(self: TextDocumentEditor, move: string, updateTargetColumn: bool = true, options {.varargs.}: JsonNode = newJObject()) {.expose("editor.text").} =
  self.selections = self.getSelectionsForMove(self.selections, move, 1, true, true, options)
  self.scrollToCursor(Last)
  if updateTargetColumn:
    self.updateTargetColumn(Last)

proc getSearchQuery*(self: TextDocumentEditor): string =
  return self.searchQuery

proc setSearchQuery*(self: TextDocumentEditor, query: string, escapeRegex: bool = false, prefix: string = "", suffix: string = ""): bool {.expose("editor.text").} =
  debugf"setSearchQuery '{query}'"

  let query = if escapeRegex:
    query.escapeRegex
  else:
    query

  let finalQuery = prefix & query & suffix
  if self.searchQuery == finalQuery:
    return false

  self.searchQuery = finalQuery
  self.updateSearchResults()
  return true

proc openSearchBar*(self: TextDocumentEditor, query: string = "", scrollToPreview: bool = true, select: bool = true) {.expose("editor.text").} =
  let commandLineEditor = self.editors.commandLineEditor.TextDocumentEditor
  if commandLineEditor == self:
    return

  let prevSearchQuery = self.searchQuery
  self.commands.openCommandLine "", "/", proc(command: Option[string]): Option[string] =
    if command.getSome(command):
      discard self.setSearchQuery(command)
      if select:
        self.selection = self.getNextFindResult(self.selection.last).first.toSelection
      self.scrollToCursor(self.selection.last)
    else:
      discard self.setSearchQuery(prevSearchQuery)
      if scrollToPreview:
        self.scrollToCursor(self.selection.last)

  let document = commandLineEditor.document

  commandLineEditor.disableCompletions = true
  commandLineEditor.move("(file) (end)")
  commandLineEditor.updateTargetColumn()

  var onEditHandle = Id.new
  var onActiveHandle = Id.new
  var onSearchHandle = Id.new

  onEditHandle[] = document.onEdit.subscribe proc(arg: tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]) =
    discard self.setSearchQuery(arg.document.contentString.replace(r".set-search-query \"))

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

proc setSearchQueryFromMove*(self: TextDocumentEditor, move: string, count: int = 0, prefix: string = "", suffix: string = ""): Selection =
  let selection = self.getSelectionForMove(self.selection.last, move, count)
  let searchText = self.document.contentString(selection)
  discard self.setSearchQuery(searchText, escapeRegex=true, prefix, suffix)
  return selection

proc toggleDebugMoves*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.moveDatabase.toggleDebugMoves()

proc toggleLineComment*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selections = self.document.toggleLineComment(self.selections)

proc openFileAt(self: TextDocumentEditor, filename: string, location: Option[Selection]) =
  if self.document.filename == filename:
    if location.getSome(location):
      self.selection = location
      self.updateTargetColumn(Last)
      self.centerCursor()
      self.setNextSnapBehaviour(ScrollSnapBehaviour.MinDistanceOffscreen)
      self.layout.showEditor(self.id.EditorId)

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
        details: @[relPath.splitPath[0]],
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
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getDefinition(self.document.filename, self.selection.last)
    if self.document.isNil:
      return
    await self.gotoLocationAsync(locations)

proc gotoDeclarationAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getDeclaration(self.document.filename, self.selection.last)
    if self.document.isNil:
      return
    await self.gotoLocationAsync(locations)

proc gotoTypeDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getTypeDefinition(self.document.filename, self.selection.last)
    if self.document.isNil:
      return
    await self.gotoLocationAsync(locations)

proc gotoImplementationAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getImplementation(self.document.filename, self.selection.last)
    if self.document.isNil:
      return
    await self.gotoLocationAsync(locations)

proc gotoReferencesAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let locations = await ls.getReferences(self.document.filename, self.selection.last)
    if self.document.isNil:
      return
    await self.gotoLocationAsync(locations)

proc switchSourceHeaderAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let filename = await ls.switchSourceHeader(self.document.filename)
    if self.document.isNil:
      return
    if filename.getSome(filename):
      discard self.layout.openFile(filename)

proc updateCompletionMatches(self: TextDocumentEditor, completionIndex: int): Future[seq[int]] {.async.} =
  let revision = self.completionEngine.revision

  await sleepAsync(0.milliseconds)
  if self.document.isNil or revision != self.completionEngine.revision:
    return

  while gAsyncFrameTimer.elapsed.ms > 5:
    await sleepAsync(0.milliseconds)
    if self.document.isNil or revision != self.completionEngine.revision:
      return

  if completionIndex notin 0..self.completionMatches.high:
    return newSeq[int]()

  let index = self.completionMatches[completionIndex].index
  let filterText = self.completions[index].filterText
  let label = self.completions[index].item.label

  var matches = newSeqOfCap[int](filterText.len)
  discard matchFuzzy(filterText, label, matches, true, defaultCompletionMatchingConfig)

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

proc openSymbolSelectorPopup(self: TextDocumentEditor, symbols: seq[Symbol], navigateOnSelect: bool, detailFilename: bool = false) =
  var builder = SelectorPopupBuilder()
  builder.scope = "text-lsp-locations".some
  builder.scaleX = 0.85
  builder.scaleY = 0.8

  var res = newSeq[FinderItem]()
  for i, symbol in symbols:
    var details = @[$symbol.symbolType]
    if detailFilename:
      details.add symbol.filename
    res.add FinderItem(
      displayName: symbol.name,
      details: details,
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
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let symbols = await ls.getSymbols(self.document.filename)
    if self.document.isNil:
      return
    if symbols.len == 0:
      return

    self.openSymbolSelectorPopup(symbols, navigateOnSelect=true)

type
  LspWorkspaceSymbolsDataSource* = ref object of DataSource
    workspace: Workspace
    languageServer: LanguageServer
    query: string
    delayedTask: DelayedTask
    filename: string

proc getWorkspaceSymbols(self: LspWorkspaceSymbolsDataSource): Future[void] {.async.} =
  let symbols = self.languageServer.getWorkspaceSymbols(self.filename, self.query).await
  # let t = startTimer()
  var items = newItemList(symbols.len)
  var index = 0
  for symbol in symbols:
    let relPath = self.workspace.getRelativePathSync(symbol.filename).get(symbol.filename)

    items[index] = FinderItem(
      displayName: symbol.name,
      details: @[$symbol.symbolType, relPath.splitPath[0]],
      data: encodeFileLocationForFinderItem(symbol.filename, symbol.location.some),
    )
    inc index

  # debugf"[getWorkspaceSymbols] {t.elapsed.ms}ms"

  items.setLen(index)
  self.onItemsChanged.invoke items

proc newLspWorkspaceSymbolsDataSource(languageServer: LanguageServer, workspace: Workspace, filename: string):
    LspWorkspaceSymbolsDataSource =

  new result
  result.languageServer = languageServer
  result.workspace = workspace
  result.filename = filename

method close*(self: LspWorkspaceSymbolsDataSource) =
  self.delayedTask.deinit()
  self.delayedTask = nil

method setQuery*(self: LspWorkspaceSymbolsDataSource, query: string) =
  self.query = query

  if self.delayedTask.isNil:
    asyncSpawn self.getWorkspaceSymbols()
    self.delayedTask = startDelayedPaused(200, repeat=false):
      asyncSpawn self.getWorkspaceSymbols()
  else:
    if self.languageServer.refetchWorkspaceSymbolsOnQueryChange:
      self.delayedTask.reschedule()

proc gotoWorkspaceSymbolAsync(self: TextDocumentEditor, query: string = ""): Future[void] {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    var builder = SelectorPopupBuilder()
    builder.scope = "text-lsp-locations".some
    builder.scaleX = 0.85
    builder.scaleY = 0.8

    builder.previewer = newFilePreviewer(self.vfs, self.services).Previewer.some
    let finder = newFinder(newLspWorkspaceSymbolsDataSource(ls, self.workspace, self.getFileName()), filterAndSort=true)
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
  if self.completionEngine.isNotNil:
    self.completionEngine.setCurrentLocations(self.selections)
    self.completionEngine.updateCompletions()
    self.lastCompletionTrigger = (self.document.buffer.version, self.selections[^1].last)
  self.completionsDirty = true
  self.showCompletionWindow()

proc gotoSymbol*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.gotoSymbolAsync()

proc fuzzySearchLines*(self: TextDocumentEditor, minScore: float = 0.2, sort: bool = true) {.expose("editor.text").} =
  self.openLineSelectorPopup(minScore, sort)

proc gotoWorkspaceSymbol*(self: TextDocumentEditor, query: string = "") {.expose("editor.text").} =
  asyncSpawn self.gotoWorkspaceSymbolAsync(query)

proc renameAsync(self: TextDocumentEditor) {.async.} =
  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.isNone:
    log lvlError, &"Can't rename, no language server"
    return

  let commandLineEditor = self.editors.commandLineEditor.TextDocumentEditor
  if commandLineEditor == self:
    return

  let s = self.getSelectionForMove(self.selection.last, "word")
  let text = self.document.contentString(s)

  self.commands.openCommandLine text, "new name: ", proc(newName: Option[string]): Option[string] =
    if newName.getSome(newName):
      let name = newName
      languageServer.get.rename(self.document.filename, self.selection.last, name).thenIt:
        if self.document.isNil:
          return

        if it.isSuccess and it.result.len > 0:
          log lvlInfo, &"Apply workspace edit for rename:\n{it.result[0]}"
          # todo: handle multiple workspace edits by allowing to choose one.
          asyncSpawn asyncDiscard applyWorkspaceEdit(self.editors, self.vfs, it.result[0])
        elif it.isError:
          log lvlError, &"Failed to rename to '{name}': {it.error}"

  commandLineEditor.disableCompletions = true
  commandLineEditor.move("(file) (end)")

proc rename*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.renameAsync()

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

proc selectPrevCompletionVisual*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completionsDrawnInReverse:
    self.selectNextCompletion()
  else:
    self.selectPrevCompletion()

proc selectNextCompletionVisual*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completionsDrawnInReverse:
    self.selectPrevCompletion()
  else:
    self.selectNextCompletion()

proc hasTabStops*(self: TextDocumentEditor): bool =
  return self.currentSnippetData.isSome

proc clearTabStops*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.currentSnippetData = SnippetData.none

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

      for i, s in self.selections:
        if i < self.selections.high:
          cursorEditSelections.add self.document.getCompletionSelectionAt(s.last)
          cursorInsertTexts.add edit.newText

      cursorEditSelections.add editSelection
      cursorInsertTexts.add edit.newText

    elif edit.asInsertReplaceEdit().isSome:
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
        let indent = self.document.getIndentString()
        for i, insertText in cursorInsertTexts.mpairs:
          let indentLevel = self.document.getIndentLevelForLine(cursorEditSelections[i].first.line, self.document.tabWidth())
          insertText = data.text.indentExtraLines(indentLevel, indent)
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
  self.move("(next-tab-stop)")

  if completion.item.showCompletionsAgain.get(false):
    self.autoShowCompletions()

proc applyCompletion*(self: TextDocumentEditor, completion: JsonNode) {.expose("editor.text").} =
  try:
    let completion = completion.jsonTo(Completion)
    self.applyCompletion(completion)
  except:
    log lvlError, &"[applyCompletion] Failed to parse completion {completion}"

proc isShowingCompletions*(self: TextDocumentEditor): bool =
  return self.showCompletions and self.completions.len > 0

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
    self.registers.recordCommand(".apply-completion " & $completion.toJson)

proc showHoverForAsync(self: TextDocumentEditor, cursor: Cursor): Future[void] {.async.} =
  if self.hideHoverTask.isNotNil:
    self.hideHoverTask.pause()

  let languageServer = self.document.getLanguageServer()
  if self.document.isNil:
    return

  if languageServer.getSome(ls):
    let hoverInfo = await ls.getHover(self.document.filename, cursor)
    if self.document.isNil:
      return
    if hoverInfo.getSome(hoverInfo):
      self.showHover = true
      self.showSignatureHelp = false
      self.hoverScrollOffset = 0
      self.hoverText = hoverInfo
      self.hoverLocation = cursor
    else:
      self.showHover = false

  self.markDirty()

proc showSignatureHelpAsync(self: TextDocumentEditor, cursor: Cursor, hideIfEmpty: bool): Future[void] {.async.} =
  if not self.settings.signatureHelpEnabled.get():
    return

  let languageServer = self.document.getLanguageServer()
  if languageServer.isNone:
    return

  let signatureHelps = await languageServer.get.getSignatureHelp(self.document.filename, cursor)
  if self.document.isNil:
    return

  if self.selection.last.line != cursor.line:
    return

  if signatureHelps.isSuccess:
    var numSignatures = 0
    for res in signatureHelps.result:
      numSignatures += res.signatures.len

    if numSignatures == 0:
      # If we don't find signatures, check if we're still in the parameter list of the last successful signature help,
      # and reuse that if so.
      let move = self.settings.signatureHelpMove.get()
      let argListRanges = self.getSelectionsForMove(@[cursor.toSelection], move)
      if argListRanges.len > 0 and self.signatureHelpLocation == argListRanges[0].first:
        # Argument list still starts at same place, so assume same argument list and show the previous.
        return

    self.showSignatureHelp = true
    self.signatures.setLen(0)
    var signatureIndex = 0
    var parameterIndex = 0
    for res in signatureHelps.result:
      if res.activeSignature.isSome:
        signatureIndex = res.activeSignature.get()

      if res.activeParameter.isSome:
        parameterIndex = res.activeParameter.get()

      for sig in res.signatures:
        self.signatures.add sig

    self.currentSignature = signatureIndex
    self.currentSignatureParam = parameterIndex

    if self.signatures.len == 0 and hideIfEmpty:
      self.showSignatureHelp = false

    else:
      self.showHover = false
      self.signatureHelpLocation = cursor
      let move = self.settings.signatureHelpMove.get()
      let argListRanges = self.getSelectionsForMove(@[cursor.toSelection], move)
      if argListRanges.len > 0:
        self.signatureHelpLocation = argListRanges[0].first

  else:
    self.showSignatureHelp = false
    log lvlError, $signatureHelps

  self.markDirty()

proc showHoverFor*(self: TextDocumentEditor, cursor: Cursor) =
  ## Shows lsp hover information for the given cursor.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncSpawn self.showHoverForAsync(cursor)

proc showHoverForCurrent*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp hover information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncSpawn self.showHoverForAsync(self.selection.last)

proc showHover*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp hover information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncSpawn self.showHoverForAsync(self.selection.last)

proc toggleHover*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp hover information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  if self.showHover:
    self.showHover = false
    self.markDirty()
  else:
    asyncSpawn self.showHoverForAsync(self.selection.last)

proc hideHover*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Hides the hover information.
  self.showHover = false
  self.markDirty()

proc showSignatureHelp*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp signature information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  asyncSpawn self.showSignatureHelpAsync(self.selection.last, hideIfEmpty = false)

proc toggleSignatureHelp*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Shows lsp signature information for the current selection.
  ## Does nothing if no language server is available or the language server doesn't return any info.
  if self.showSignatureHelp:
    self.showSignatureHelp = false
    self.markDirty()
  else:
    asyncSpawn self.showSignatureHelpAsync(self.selection.last, hideIfEmpty = false)

proc hideSignatureHelp*(self: TextDocumentEditor) {.expose("editor.text").} =
  ## Hides the hover information.
  self.showSignatureHelp = false
  self.markDirty()

proc cancelDelayedHideHover*(self: TextDocumentEditor) =
  if self.hideHoverTask.isNotNil:
    self.hideHoverTask.pause()

proc hideHoverDelayed*(self: TextDocumentEditor) =
  ## Hides the hover information after a delay.
  if self.showHoverTask.isNotNil:
    self.showHoverTask.pause()

  let hoverDelayMs = self.settings.hoverDelay.get()
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

  let hoverDelayMs = self.settings.hoverDelay.get()
  if self.showHoverTask.isNil:
    self.showHoverTask = startDelayed(hoverDelayMs, repeat=false):
      self.showHoverFor(self.currentHoverLocation)
  else:
    self.showHoverTask.interval = hoverDelayMs
    self.showHoverTask.reschedule()

  self.markDirty()

proc showSignatureHelpForDelayed*(self: TextDocumentEditor, cursor: Cursor) =
  ## Show signature information for the given cursor after a delay.
  let delayMs = self.settings.signatureHelpDelay.get()
  if self.showSignatureHelpTask.isNil:
    self.showSignatureHelpTask = startDelayed(delayMs, repeat=false):
      asyncSpawn self.showSignatureHelpAsync(self.selection.last, hideIfEmpty = true)
  else:
    self.showSignatureHelpTask.interval = delayMs
    self.showSignatureHelpTask.schedule()

  self.markDirty()

proc getContextLines*(self: TextDocumentEditor, cursor: Cursor): seq[int] =
  if self.document.tsTree.isNil:
    return @[]

  let tree = self.document.tsTree

  var node = tree.root.descendantForRange(cursor.toSelection.tsRange)
  var lastColumn = int.high
  while node != tree.root:
    var r = node.getRange.toSelection
    # echo &"getContextLines {cursor}, last: {lastColumn}, node: {r.first}, -> {result}"
    let indent = self.document.getIndentLevelForLine(r.first.line, self.document.tabWidth())
    if r.first.line != cursor.line and (result.len == 0 or r.first.line != result.last):
      if result.len > 0 and indent == lastColumn:
        result[result.high] = r.first.line
      elif (result.len > 0 and result.last != r.first.line) or indent < lastColumn:
        result.add r.first.line
        lastColumn = indent

    node = node.parent

proc updateInlayHintsAsync*(self: TextDocumentEditor): Future[void] {.async.} =
  if self.document.isNil:
    return
  if not self.settings.inlayHintsEnabled.get():
    return
  if self.document.requiresLoad or self.document.isLoadingAsync:
    return

  if self.document.getLanguageServer().getSome(ls):
    if self.document.isNil:
      return

    let screenLineCount = self.screenLineCount
    let visibleRangeHalf = self.visibleTextRange(screenLineCount div 2)
    let visibleRange = self.visibleTextRange(screenLineCount)
    let snapshot = self.document.buffer.snapshot.clone()
    let inlayHints: Response[seq[language_server_base.InlayHint]] = await ls.getInlayHints(self.document.filename, visibleRange)
    if self.document.isNil:
      return

    # todo: detect if canceled instead
    if inlayHints.isSuccess:
      template getBias(hint: untyped): Bias =
        if hint.paddingRight:
          Bias.Right
        else:
          Bias.Left

      self.inlayHints = inlayHints.result.mapIt (snapshot.anchorAt(it.location.toPoint, it.getBias), it)
      self.lastInlayHintTimestamp = snapshot.version
      self.updateInlayHintsAfterChange()
      self.lastInlayHintDisplayRange = visibleRange.toRange
      self.lastInlayHintBufferRange = visibleRangeHalf.toRange

      self.displayMap.overlay.clear(overlayIdInlayHint)
      for hint in self.inlayHints:
        let point = hint.hint.location.toPoint
        let bias = hint.hint.getBias
        if hint.hint.paddingLeft:
          self.displayMap.overlay.addOverlay(point...point, " " & hint.hint.label, overlayIdInlayHint, "comment", bias)
        elif hint.hint.paddingRight:
          self.displayMap.overlay.addOverlay(point...point, hint.hint.label & " ", overlayIdInlayHint, "comment", bias)
        else:
          self.displayMap.overlay.addOverlay(point...point, hint.hint.label, overlayIdInlayHint, "comment", bias)

      self.markDirty()

proc getDiagnosticsWithNoCodeActionFetched(self: TextDocumentEditor, languageServer: LanguageServer): seq[lsp_types.Diagnostic] =
  let codeActions = self.codeActions.mgetOrPut(languageServer.name).addr
  let visibleRange = self.visibleTextRange(0)
  for diagnosticsData in self.document.diagnosticsPerLS.mitems:
    if languageServer != nil and diagnosticsData.languageServer != languageServer:
      continue

    for d in diagnosticsData.currentDiagnostics.mitems:
      if d.selection.first > visibleRange.last or d.selection.last < visibleRange.first:
        continue

      if codeActions[].contains(d.selection.first.line):
        continue
      codeActions[][d.selection.first.line] = @[]

      # todo: correctly convert selection coordinate (line, bytes) to lsp (line, rune?)
      result.add lsp_types.Diagnostic(
        range: lsp_types.Range(
          start: lsp_types.Position(line: d.selection.first.line, character: d.selection.first.column),
          `end`: lsp_types.Position(line: d.selection.last.line, character: d.selection.last.column),
        ),
        severity: d.severity,
        code: d.code,
        codeDescription: d.codeDescription,
        source: d.source,
        message: d.message,
        tags: d.tags,
        relatedInformation: d.relatedInformation,
        data: d.data,
      )

proc executeCommandOrCodeAction(self: TextDocumentEditor, commandOrAction: CodeActionOrCommand) {.async.} =
  if self.document.getLanguageServer().getSome(ls):
    if self.document.isNil:
      return

    case commandOrAction.kind:
    of CodeActionKind.Command:
      log lvlInfo, &"Run lsp command {commandOrAction.command}"
      let res = await ls.executeCommand(commandOrAction.command.command, commandOrAction.command.arguments)
      if res.isError:
        log lvlError, &"Failed to execute lsp command '{commandOrAction.command.command}, {commandOrAction.command.arguments}': {res.error}"

    of CodeActionKind.CodeAction:
      if commandOrAction.action.edit.getSome(edit):
        discard await applyWorkspaceEdit(self.editors, self.vfs, edit)
        if self.document.isNil:
          return

      if commandOrAction.action.command.getSome(command):
        log lvlInfo, &"Run lsp command {command}"
        let res = await ls.executeCommand(command.command, command.arguments)
        if res.isError:
          log lvlError, &"Failed to execute lsp command '{command.command}, {command.arguments}': {res.error}"

proc updateCodeActionAsync(self: TextDocumentEditor, ls: LanguageServer, selection: Selection, versionId: BufferVersionId,
    diagnosticsVersion: int, addSign: bool): Future[void] {.async.} =
  # todo: correctly convert selection coordinate (line, bytes) to lsp (line, rune?)
  let codeActions = self.codeActions.mgetOrPut(ls.name).addr
  let actions = await ls.getCodeActions(self.document.filename, selection, @[])
  let lastDiagnosticsVersion = self.lastDiagnosticsVersions.getOrDefault(ls.name, 0)
  if self.document == nil or self.document.buffer.versionId != versionId or lastDiagnosticsVersion != diagnosticsVersion:
    return
  if actions.kind == Success and actions.result.len > 0:
    if addSign:
      let sign = self.settings.codeActions.sign.get()
      if sign.len > 0:
        let signWidth = self.settings.codeActions.signWidth.get()
        let color = self.settings.codeActions.signColor.get()
        discard self.addSign(idNone(), selection.first.line, sign, group = "code-actions-" & ls.name, color = color, width = signWidth)

    for actionOrCommand in actions.result:
      if actionOrCommand.asCommand().getSome(command):
        codeActions[].mgetOrPut(selection.first.line, @[]).add CodeActionOrCommand(kind: CodeActionKind.Command, command: command, selection: selection, languageServerName: ls.name)
      elif actionOrCommand.asCodeAction().getSome(codeAction):
        codeActions[].mgetOrPut(selection.first.line, @[]).add CodeActionOrCommand(kind: CodeActionKind.CodeAction, action: codeAction, selection: selection, languageServerName: ls.name)
      else:
        log lvlError, &"Failed to parse code action: {actionOrCommand}"

  self.markDirty()

proc selectCodeActionAsync(self: TextDocumentEditor) {.async.} =
  let line = self.selection.last.line
  var res = newSeq[FinderItem]()

  proc collectCodeActions() =
    for codeActions in self.codeActions.mvalues:
      if line notin codeActions:
        continue

      for i, commandOrAction in codeActions[line]:
        if commandOrAction.selection.first > self.selection.last or commandOrAction.selection.last < self.selection.last:
          continue

        case commandOrAction.kind:
        of CodeActionKind.Command:
          res.add FinderItem(
            displayName: commandOrAction.command.title,
            data: $commandOrAction.toJson,
          )
        of CodeActionKind.CodeAction:
          res.add FinderItem(
            displayName: commandOrAction.action.title,
            data: $commandOrAction.toJson,
          )

  collectCodeActions()

  if res.len == 0:
    if self.document.getLanguageServer().getSome(ls):
      let lastDiagnosticsVersion = self.lastDiagnosticsVersions.getOrDefault(ls.name, 0)
      await self.updateCodeActionAsync(ls, self.selection, self.document.buffer.versionId, lastDiagnosticsVersion, addSign = false)
    else:
      log lvlError, &"Can't select code actions: No language server attached."
      return

    collectCodeActions()

  if res.len == 0:
    return

  var builder = SelectorPopupBuilder()
  builder.scope = "code-actions".some
  builder.scaleX = 0.4
  builder.scaleY = 0.4

  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some
  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    try:
      let commandOrAction = item.data.parseJson.jsonTo(CodeActionOrCommand)
      asyncSpawn self.executeCommandOrCodeAction(commandOrAction)
    except:
      discard
    true

  discard self.layout.pushSelectorPopup(builder)

proc selectCodeAction(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncSpawn self.selectCodeActionAsync()

proc updateCodeActionsAsync*(self: TextDocumentEditor, languageServer: Option[LanguageServer]): Future[void] {.async.} =
  if self.document.isNil:
    return

  if self.document.requiresLoad or self.document.isLoadingAsync:
    return

  let languageServers = if languageServer.getSome(ls):
    @[ls]
  else:
    self.document.languageServerList.languageServers

  for ls in languageServers:
    let versionId = self.document.buffer.versionId
    let diagnostics = self.getDiagnosticsWithNoCodeActionFetched(ls)
    if diagnostics.len == 0:
      return

    let diagnosticsVersion = self.lastDiagnosticsVersions.getOrDefault(ls.name, 0)

    for d in diagnostics:
      let selection: Selection = (
        (d.`range`.start.line, d.`range`.start.character),
        (d.`range`.`end`.line, d.`range`.`end`.character))
      asyncSpawn self.updateCodeActionAsync(ls, selection, versionId, diagnosticsVersion, addSign = true)

proc clearDiagnostics*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.document.clearDiagnostics()
  self.markDirty()

proc updateInlayHints*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.inlayHintsTask.isNil:
    self.inlayHintsTask = startDelayed(200, repeat=false):
      asyncSpawn self.updateInlayHintsAsync()
      asyncSpawn self.updateCodeActionsAsync(LanguageServer.none)
  else:
    self.inlayHintsTask.reschedule()

proc lspInfo(self: TextDocumentEditor) {.expose("editor.text").} =
  var builder = SelectorPopupBuilder()
  builder.scope = "lsp-info".some
  builder.scaleX = 0.4
  builder.scaleY = 0.4

  var res = newSeq[FinderItem]()
  for ls in self.document.languageServerList.languageServers:
    res.add FinderItem(
      displayName: ls.name,
    )

  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some

  discard self.layout.pushSelectorPopup(builder)

proc setReadOnly*(self: TextDocumentEditor, readOnly: bool) {.expose("editor.text").} =
  ## Sets the internal readOnly flag, but doesn't not change permissions of the underlying file
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

proc getAvailableCursors*(self: TextDocumentEditor): seq[Cursor] =
  let wordRunes {.cursor.} = self.document.settings.completionWordChars.get()
  let rope {.cursor.} = self.document.rope

  let max = self.settings.chooseCursorMax.get()
  for chunk in self.lastRenderedChunks:
    var startsWithWord = true
    if chunk.range.a.column > 0:
      let currentIsWord = rope.runeAt(chunk.range.a) in wordRunes
      let prevIsWord = rope.runeAt(rope.clipPoint(point(chunk.range.a.row, chunk.range.a.column - 1), Bias.Left)) in wordRunes
      if prevIsWord == currentIsWord:
        startsWithWord = false

    let str = self.document.contentString((chunk.range.a.toCursor, chunk.range.b.toCursor))
    var i = 0
    while i < str.len:
      while i < str.len and str[i] == ' ':
        inc i
        startsWithWord = true

      var endIndex = str.find(' ', i)
      if endIndex == -1:
        endIndex = str.len

      if startsWithWord and endIndex - i >= 2:
        result.add (chunk.range.a + point(0, i)).toCursor
        if result.len >= max:
          break

      i = endIndex
      startsWithWord = true

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

proc getSelection*(self: TextDocumentEditor): Selection =
  self.selection

proc getSelections*(self: TextDocumentEditor): Selections =
  self.selections

proc setSelection*(self: TextDocumentEditor, selection: Selection, addToHistory: Option[bool] = bool.none) =
  self.`selections=`(@[selection], addToHistory)

proc setSelections*(self: TextDocumentEditor, selections: Selections, addToHistory: Option[bool] = bool.none) =
  if selections.len == 0:
    log lvlError, &"Failed to set selections for '{self.getFileName()}': no selections provided"
    return
  self.`selections=`(selections, addToHistory)

proc setTargetSelection*(self: TextDocumentEditor, selection: Selection) =
  self.targetSelection = selection

proc enterChooseCursorMode*(self: TextDocumentEditor, action: string) {.expose("editor.text").} =
  const mode = "temp.choose-cursor"
  let cursors = self.getAvailableCursors()
  let keys = self.assignKeys(cursors)
  var config = self.events.getEventHandlerConfig(mode)

  for i in 0..min(cursors.high, keys.high):
    config.addCommand("", keys[i] & "<SPACE>", action & " " & $cursors[i].toJson)

  var progress = ""

  proc updateStyledTextOverrides() =
    self.displayMap.overlay.clear(overlayIdChooseCursor)
    try:

      var options: seq[Cursor] = @[]
      for i in 0..min(cursors.high, keys.high):
        if not keys[i].startsWith(progress):
          continue

        if progress.len > 0:
          self.displayMap.overlay.addOverlay(cursors[i].toPoint...point(cursors[i].line, cursors[i].column + progress.len), progress, overlayIdChooseCursor, "string")

        let cursor = (line: cursors[i].line, column: cursors[i].column + progress.len)
        let text = keys[i][progress.len..^1]
        self.displayMap.overlay.addOverlay(cursor.toPoint...point(cursor.line, cursor.column + text.len), text, overlayIdChooseCursor, "constant.numeric")

        options.add cursors[i]

      if options.len == 1:
        self.displayMap.overlay.clear(overlayIdChooseCursor)
        self.document.notifyTextChanged()
        self.markDirty()
        self.removeMode(mode)
        discard self.handleAction(action, ($options[0].toJson), record=false)
    except:
      discard

    self.document.notifyTextChanged()
    self.markDirty()

  updateStyledTextOverrides()

  config.addCommand("", "<ESCAPE>", "setMode \"\"")

  let weakSelf {.cursor.} = self

  self.eventHandlerOverrides[mode] = proc(config: EventHandlerConfig): EventHandler =
    assignEventHandler(result, config):
      onAction:
        weakSelf.displayMap.overlay.clear(overlayIdChooseCursor)
        weakSelf.document.notifyTextChanged()
        weakSelf.markDirty()
        weakSelf.removeMode(mode)
        if weakSelf.handleAction(action, arg, record=true).isSome:
          Handled
        else:
          Ignored

      onInput:
        Ignored

      onProgress:
        progress.add inputToString(input)
        updateStyledTextOverrides()

      onCanceled:
        weakSelf.displayMap.overlay.clear(overlayIdChooseCursor)
        weakSelf.removeMode(mode)

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  self.setMode(mode)

  self.markDirty()

proc recordCurrentCommand*(self: TextDocumentEditor, registers: seq[string] = @[]) =
  self.recordCurrentCommandRegisters = if registers.len > 0:
    registers
  else:
    self.registers.recordingCommands

proc runControlClickCommand*(self: TextDocumentEditor) =
  let commandName = self.settings.controlClickCommand.get()
  let args = self.settings.controlClickCommandArgs.get()
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runSingleClickCommand*(self: TextDocumentEditor) =
  let commandName = self.settings.singleClickCommand.get()
  let args = self.settings.singleClickCommandArgs.get()
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runDoubleClickCommand*(self: TextDocumentEditor) =
  let commandName = self.settings.doubleClickCommand.get()
  let args = self.settings.doubleClickCommandArgs.get()
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runTripleClickCommand*(self: TextDocumentEditor) =
  let commandName = self.settings.tripleClickCommand.get()
  let args = self.settings.tripleClickCommandArgs.get()
  if commandName.len == 0:
    return
  discard self.runAction(commandName, args)

proc runDragCommand*(self: TextDocumentEditor) =
  if self.lastPressedMouseButton == MouseButton.Left:
    self.runSingleClickCommand()
  elif self.lastPressedMouseButton == MouseButton.DoubleClick:
    self.runDoubleClickCommand()
  elif self.lastPressedMouseButton == MouseButton.TripleClick:
    self.runTripleClickCommand()

proc getCurrentEventHandlers*(self: TextDocumentEditor): seq[string] =
  return self.settings.modes.get()

proc setCustomHeader*(self: TextDocumentEditor, text: string) {.expose("editor.text").} =
  self.customHeader = text
  self.markDirty()

proc cycleCase*(self: TextDocumentEditor, selection: Selection, inclusiveEnd: bool = false): string =
  return self.document.contentString(selection, inclusiveEnd).cycleCase()

proc cycleSelectedCase*(self: TextDocumentEditor) {.expose("editor.text").} =
  var newTexts = self.selections.mapIt(self.cycleCase(it, self.useInclusiveSelections))
  self.selections = self.document.edit(self.selections, self.selections, newTexts, inclusiveEnd=self.useInclusiveSelections)
  if self.useInclusiveSelections:
    self.selections = self.selections.mapIt((it.first, self.doMoveCursorColumn(it.last, -1, wrap = false)))
  self.updateTargetColumn()
  self.markDirty()

genDispatcher("editor.text")
addActiveDispatchTable "editor.text", genDispatchTable("editor.text")

proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): Option[JsonNode] =
  # debugf"[textedit] handleAction {action}, '{args}'"

  var args = args.copy
  args.elems.insert api.TextDocumentEditor(id: self.id.EditorId).toJson, 0

  if self.commands.activeCommands.contains(action):
    try:
      let res = self.commands.activeCommands[action].execute(args.elems.mapIt($it).join(" "))
      if res == "":
        return newJNull().some
      return res.parseJson().some
    except CatchableError as e:
      log lvlError, &"Failed to execute command '{action} {args}': {e.msg}"
      return newJNull().some

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
    log(lvlError, fmt"Failed to dispatch command '{action} {argsText}': {getCurrentExceptionMsg()}")
    return JsonNode.none

  return JsonNode.none

method handleAction*(self: TextDocumentEditor, action: string, arg: string, record: bool): Option[JsonNode] =
  # debugf "handleAction '{action}', '{arg}', record = {record}"

  try:
    var doRecord = record
    if self.commands.dontRecord:
      doRecord = false

    let oldDontRecord = self.commands.dontRecord
    if record:
      self.commands.dontRecord = true
    defer:
      if record:
        self.commands.dontRecord = oldDontRecord

    let noRecordActions = [
      "apply-selected-completion",
      "applySelectedCompletion",
    ].toHashSet

    let oldIsRecordingCurrentCommand = self.bIsRecordingCurrentCommand
    self.bIsRecordingCurrentCommand = doRecord

    defer:
      self.bIsRecordingCurrentCommand = oldIsRecordingCurrentCommand

    defer:
      if self.recordCurrentCommandRegisters.len > 0:
        self.registers.recordCommand("." & action & " " & arg, self.recordCurrentCommandRegisters)
      self.recordCurrentCommandRegisters.setLen(0)

    if doRecord and action notin noRecordActions:
      self.registers.recordCommand("." & action & " " & arg)

    var args = newJArray()
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    result = self.handleActionInternal(action, args)
    if result.isSome:
      return

    let res = self.commands.executeCommand(action & " " & arg, record = false)
    if res.isSome:
      return newJString(res.get).some
  except CatchableError:
    log(lvlError, fmt"handleCommand: '{action}', Failed to parse args: '{arg}'")
  return JsonNode.none

proc handleInput(self: TextDocumentEditor, input: string, record: bool): EventResponse =
  try:
    if record:
      self.registers.recordCommand(".insert-text " & $input.newJString)

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
  # log lvlInfo, fmt"[handleLanguageServerAttached] '{self.document.filename}'"
  if languageServer.capabilities.completionProvider.isSome:
    self.completionEngine.addProvider newCompletionProviderLsp(document, languageServer)
      .withMergeStrategy(MergeStrategy(kind: TakeAll))
      .withPriority(2)

  self.updateInlayHints()

proc handleDiagnosticsChanged(self: TextDocumentEditor, document: TextDocument, languageServer: LanguageServer) =
  if document != self.document:
    return

  self.lastDiagnosticsVersions.mgetOrPut(languageServer.name).inc
  self.codeActions.mgetOrPut(languageServer.name).clear()
  self.clearSigns("code-actions-" & languageServer.name)
  asyncSpawn self.updateCodeActionsAsync(languageServer.some)

proc handleTextDocumentBufferChanged(self: TextDocumentEditor, document: TextDocument) =
  if document != self.document:
    return

  self.closeDiff()
  self.snapshot = self.document.buffer.snapshot.clone()
  self.displayMap.setBuffer(self.snapshot.clone())
  self.selections = self.selections
  self.inlayHints.setLen(0)
  self.cursorHistories.setLen(0)
  self.hideCompletions()
  self.updateInlayHints()
  self.updateSearchResults()
  self.markDirty()

proc handleEdits(self: TextDocumentEditor, edits: openArray[tuple[old, new: Selection]]) =
  self.displayMap.edit(self.document.buffer.snapshot.clone(), edits)
  if self.settings.wrapLines.get():
    self.displayMap.wrapMap.update(self.displayMap.tabMap.snapshot.clone(), force = true)

proc updateMatchingWordHighlightAsync(self: TextDocumentEditor) {.async.} =
  if self.isUpdatingMatchingWordHighlights:
    return
  self.isUpdatingMatchingWordHighlights = true
  defer:
    self.isUpdatingMatchingWordHighlights = false

  while true:
    if self.document.rope.len > self.settings.highlightMatches.maxFileSize.get():
      return

    let oldSelection = self.selection.normalized
    if oldSelection.last.line - oldSelection.first.line > self.settings.highlightMatches.maxSelectionLines.get():
      return

    let (selection, inclusive, addWordBoundary) = if oldSelection.isEmpty:
      var s = self.document.rope.vimMotionWord(oldSelection.last, false).normalized
      const AlphaNumeric = {'A'..'Z', 'a'..'z', '0'..'9', '_'}
      if self.document.rope.charAt(s.first.toPoint) notin AlphaNumeric:
        let prev = (oldSelection.last.line, oldSelection.last.column - 1)
        if s.first.column > 0 and self.document.rope.charAt(prev.toPoint) in AlphaNumeric:
          s = self.document.rope.vimMotionWord(prev, false).normalized
        else:
          self.clearCustomHighlights(wordHighlightId)
          return
      if self.document.rope.charAt(s.first.toPoint) notin AlphaNumeric:
        self.clearCustomHighlights(wordHighlightId)
        return
      (s, false, true)
    else:
      (oldSelection.normalized, self.useInclusiveSelections, false)

    let startByte = self.document.rope.pointToOffset(selection.first.toPoint)
    let endByte = self.document.rope.pointToOffset(selection.last.toPoint)
    assert endByte >= startByte

    if endByte - startByte > self.settings.highlightMatches.maxSelectionLength.get():
      return

    let text = self.document.contentString(selection, inclusive)
    var regex = text.escapeRegex
    if addWordBoundary:
      regex = "\\b" & regex & "\\b"

    try:
      let version = self.document.buffer.version
      let rope = self.document.rope.clone()
      let ranges = await findAllAsync(rope.slice(int), regex)
      if self.document.isNil:
        return
      if self.document.buffer.version != version or self.selection != oldSelection:
        continue

      self.clearCustomHighlights(wordHighlightId)
      for r in ranges:
        self.addCustomHighlight(wordHighlightId, r.toSelection, "matching-text-highlight")

      break
    except Exception as e:
      log lvlError, &"Failed to find matching words: {e.msg}"

proc updateMatchingWordHighlight(self: TextDocumentEditor) =
  if not self.settings.highlightMatches.enable.get():
    self.clearCustomHighlights(wordHighlightId)
    return

  if self.isUpdatingMatchingWordHighlights:
    return

  if self.updateMatchingWordsTask.isNil:
    self.updateMatchingWordsTask = startDelayed(2, repeat=false):
      if self.document.isNil:
        return
      asyncSpawn self.updateMatchingWordHighlightAsync()

  self.updateMatchingWordsTask.interval = self.settings.highlightMatches.delay.get()
  self.updateMatchingWordsTask.schedule()

proc updateColorOverlays(self: TextDocumentEditor) {.async.} =
  if not self.settings.colorHighlight.enable.get():
    self.displayMap.overlay.clear(overlayIdColorHighlight)
    return

  let regex = self.settings.colorHighlight.regex.getRegex()
  let kind = self.settings.colorHighlight.kind.get()
  let floatRegex = re"(\d+(\.\d+)?)"

  try:
    let rope = self.document.rope.clone()
    let colorRanges = await findAllAsync(rope.slice(int), regex)
    if self.document.isNil:
      return

    # todo: this can scale up pretty quickly, could be done in a background thread
    self.displayMap.overlay.clear(overlayIdColorHighlight)
    for r in colorRanges:
      let text = rope[r]
      let color = case kind
      of Hex:
        if text.startsWith("#"):
          $text
        else:
          "#" & $text
      of Float1:
        var c = color(0, 0, 0)
        let text = $text
        let numbers = text.findAllBounds(0, floatRegex)
        if numbers.len >= 3:
          c.r = (text[numbers[0].first.column..<numbers[0].last.column]).parseFloat
          c.g = (text[numbers[1].first.column..<numbers[1].last.column]).parseFloat
          c.b = (text[numbers[2].first.column..<numbers[2].last.column]).parseFloat
        "#" & c.toHex
      of Float255:
        var c = color(0, 0, 0)
        let text = $text
        let numbers = text.findAllBounds(0, floatRegex)
        if numbers.len >= 3:
          c.r = (text[numbers[0].first.column..<numbers[0].last.column]).parseFloat / 255.0
          c.g = (text[numbers[1].first.column..<numbers[1].last.column]).parseFloat / 255.0
          c.b = (text[numbers[2].first.column..<numbers[2].last.column]).parseFloat / 255.0
        "#" & c.toHex

      self.displayMap.overlay.addOverlay(r.a...r.a, "■", overlayIdColorHighlight, color)

  except Exception as e:
    log lvlError, &"Failed to find colors: {e.msg}"

proc handleTextDocumentTextChanged(self: TextDocumentEditor) =
  let oldSnapshot = self.snapshot.move
  self.snapshot = self.document.buffer.snapshot.clone()

  if self.settings.scrollToEndOnInsert.get() and self.selections.len == 1 and self.selection == oldSnapshot.visibleText.summary.lines.toCursor.toSelection:
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

  asyncSpawn self.updateColorOverlays()

  self.markDirty()

proc handleTextDocumentPreLoaded(self: TextDocumentEditor) =
  if self.document.isNil:
    return

  self.selectionsBeforeReload = self.selections
  self.wasAtEndBeforeReload = self.selectionsBeforeReload.len == 1 and self.selectionsBeforeReload[0] == self.document.lastCursor.toSelection

proc handleTextDocumentLoaded(self: TextDocumentEditor, changes: seq[Selection]) =
  if self.document.isNil:
    return

  # debugf"handleTextDocumentLoaded {self.id}, {self.usage}, '{self.document.filename}': targetSelectionsInternal: {self.targetSelectionsInternal}"

  if self.targetSelectionsInternal.getSome(s):
    self.selections = s
    self.centerCursor()
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

  elif self.settings.scrollToChangeOnReload.get().getSome(scrollToChangeOnReload):
    case scrollToChangeOnReload
    of ScrollToChangeOnReload.First:
      if changes.len > 0:
        self.selection = changes[0].first.toSelection
        self.scrollToCursor()
    of ScrollToChangeOnReload.Last:
      if changes.len > 0 and self.wasAtEndBeforeReload:
        self.selection = changes[^1].last.toSelection
        self.scrollToCursor()

  elif self.selectionsBeforeReload.len > 0:
    self.selections = self.selectionsBeforeReload
    self.scrollToCursor()
    self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)

  self.cursorHistories.setLen(0)
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

  if self.lastContentBounds.w == 0 or self.lastContentBounds.h == 0:
    return

  if displayMap == self.displayMap:
    if displayMap.endDisplayPoint.row != self.lastEndDisplayPoint.row:
      self.lastEndDisplayPoint = displayMap.endDisplayPoint
      # let oldScrollOffset = self.scrollOffset.y

      # debugf"handleDisplayMapUpdated '{self.getFileName()}': target {self.targetPoint}, {displayMap.endDisplayPoint.row} -> {self.lastEndDisplayPoint.row}, {self.lastContentBounds}"
      if self.targetPoint.getSome(point):
        self.scrollToCursor(point.toCursor, self.targetLineMargin, self.nextScrollBehaviour, self.targetLineRelativeY)
        self.setNextSnapBehaviour(ScrollSnapBehaviour.Always)
      else:
        self.scrollOffset = self.interpolatedScrollOffset

      # let oldInterpolatedScrollOffset = self.interpolatedScrollOffset.y
      let displayPoint = self.displayMap.toDisplayPoint(self.currentCenterCursor.toPoint)
      self.interpolatedScrollOffset.y = self.lastContentBounds.h * self.currentCenterCursorRelativeYPos - self.platform.totalLineHeight * 0.5 - displayPoint.row.float * self.platform.totalLineHeight
      # debugf"handleDisplayMapUpdated '{self.getFileName()}': {oldScrollOffset} -> {self.scrollOffset}, {oldInterpolatedScrollOffset} -> {self.interpolatedScrollOffset.y}, target {self.targetPoint}"

    self.markDirty()
  elif displayMap == self.diffDisplayMap:
    self.markDirty()

## Only use this to create TextDocumentEditorInstances
proc createTextEditorInstance(): TextDocumentEditor =
  let editor = TextDocumentEditor(selectionsInternal: @[(0, 0).toSelection])
  editor.cursorsId = newId()
  editor.completionsId = newId()
  editor.hoverId = newId()
  editor.signatureHelpId = newId()
  editor.inlayHints = @[]
  editor.init()
  {.gcsafe.}:
    allTextEditors.add editor
  return editor

proc newTextEditor*(document: TextDocument, services: Services): TextDocumentEditor =
  var self = createTextEditorInstance()
  let s {.cursor.} = self
  self.services = services
  self.platform = self.services.getService(PlatformService).get.platform
  self.configService = services.getService(ConfigService).get
  self.editors = services.getService(DocumentEditorService).get
  self.layout = services.getService(LayoutService).get
  self.vcs = self.services.getService(VCSService).get
  self.events = self.services.getService(EventHandlerService).get
  self.plugins = self.services.getService(PluginService).get
  self.registers = self.services.getService(Registers).get
  self.workspace = self.services.getService(Workspace).get
  self.moveDatabase = self.services.getService(MoveDatabase).get
  self.vfs = self.services.getService(VFSService).get.vfs
  self.commands = self.services.getService(CommandService).get
  self.displayMap = DisplayMap.new()
  self.diffDisplayMap = DisplayMap.new()
  discard self.displayMap.wrapMap.onUpdated.subscribe (args: (WrapMap, WrapMapSnapshot)) => s.handleWrapMapUpdated(args[0], args[1])
  discard self.diffDisplayMap.wrapMap.onUpdated.subscribe (args: (WrapMap, WrapMapSnapshot)) => s.handleWrapMapUpdated(args[0], args[1])
  discard self.displayMap.onUpdated.subscribe (args: (DisplayMap,)) => s.handleDisplayMapUpdated(args[0])
  discard self.diffDisplayMap.onUpdated.subscribe (args: (DisplayMap,)) => s.handleDisplayMapUpdated(args[0])

  self.config = self.configService.addStore("editor/" & $self.id, &"settings://editor/{self.id}")
  discard self.config.onConfigChanged.subscribe proc(key: string) =
    # Keep this simple and cheap, this is called often
    s.configChanged = true
    s.markDirty()

  self.uiSettings = UiSettings.new(self.config)
  self.debugSettings = DebugSettings.new(self.config)
  self.settings = TextEditorSettings.new(self.config)

  self.moveFallbacks = proc(move: string, selections: openArray[Selection], count: int, args: openArray[LispVal], env: Env): seq[Selection] =
    s.applyMoveFallback(move, selections, count, args, env)

  self.setDocument(document)

  self.startBlinkCursorTask()

  self.editors.registerEditor(self)

  self.onFocusChangedHandle = self.platform.onFocusChanged.subscribe proc(focused: bool) = s.handleFocusChanged(focused)

  self.setDefaultMode()

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
