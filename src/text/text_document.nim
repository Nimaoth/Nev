import std/[os, strutils, sequtils, sugar, options, json, strformat, tables, uri, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[id, util, event, custom_logger, custom_async, custom_unicode, myjsonutils, regex, array_set, timer, rope_utils, jsonex]
import language/[languages, language_server_base]
import workspaces/[workspace]
import document, document_editor, custom_treesitter, indent, config_provider, service, vfs, vfs_service, language_server_list
import syntax_map
import pkg/[chroma, results]
import vcs/vcs, event_service, toast
import language_server_component, config_component, move_database, move_component, text_component, treesitter_component,
  language_component, formatting_component
import display_map

include dynlib_export

import diff

import nimsumtree/[buffer, clock, static_array, rope, clone]
import nimsumtree/sumtree except Cursor, mapIt

from language/lsp_types as lsp_types import nil
export document, document_editor, id

logCategory "text-document"

{.push gcsafe.}
{.push raises: [].}

proc typeNameToJson*(T: typedesc[IndentStyleKind]): string =
  return "\"tabs\" | \"spaces\""

declareSettings SearchRegexSettings, "":
  ## If true then the search results will only show the part of a line that matched the regex.
  ## If false then the entire line is shown.
  declare showOnlyMatchingPart, bool, true

  ## Regex to use when using the goto-definition feature.
  declare gotoDefinition, Option[RegexSetting], nil

  ## Regex to use when using the goto-declaration feature.
  declare gotoDeclaration, Option[RegexSetting], nil

  ## Regex to use when using the goto-type-definition feature.
  declare gotoTypeDefinition, Option[RegexSetting], nil

  ## Regex to use when using the goto-implementation feature.
  declare gotoImplementation, Option[RegexSetting], nil

  ## Regex to use when using the goto-references feature.
  declare gotoReferences, Option[RegexSetting], nil

  ## Regex to use when using the symbols feature.
  declare symbols, Option[RegexSetting], nil

  ## Regex to use when using the workspace-symbols feature.
  declare workspaceSymbols, Option[RegexSetting], nil

  ## Regex to use when using the workspace-symbols feature. Keys are LSP symbol kinds, values are the corresponding regex.
  declare workspaceSymbolsByKind, Option[Table[string, RegexSetting]], nil

declareSettings RipgrepSettings, "":
  ## Pass the --type argument to ripgrep using either the language id or the value from `file-type`.
  declare passType, bool, true

  ## Override the ripgrep type name. By default the documents language id is used.
  declare fileType, Option[string], nil

  ## Extra arguments passed to ripgrep
  declare extraArgs, seq[string], newJArray()

declareSettings TrimTrailingWhitespaceSettings, "":
  ## If true trailing whitespace is deleted when saving files.
  declare enabled, bool, true

  ## Don't trim trailing whitespace when filesize is above this limit.
  declare maxSize, int, 1000000

declareSettings IndentDetectionSettings, "":
  ## Enable auto detecting the indent style when opening files.
  declare enable, bool, true

  ## How many indent characters to process when detecting the indent style. Increase this if it fails for files which start with many unindented lines.
  declare samples, int, 50

  ## Max number of milliseconds to spend trying to detect the indent style.
  declare timeout, int, 20

declareSettings DiffReloadSettings, "":
  ## When reloading a file the editor will compute the diff between the file on disk and the in memory document,
  ## and then apply the diff to the in memory version so it matches the content on disk.
  ## This can reduce memory usage when reloading files often (although it increases memory usage while reloading and increases load times).
  ## It's also better for collaboration as it doesn't affect the entire file.
  declare enable, bool, true

  ## Max number of milliseconds to use for diffing. If the timeout is exceeded then the file will be reloaded normally.
  declare timeout, int, 250

declareSettings DiagnosticsSettings, "":
  ## Enable diagnostics. Also requires a language server which supports diagnostics.
  declare enable, bool, true

  ## How many snapshots to keep when editing. Snapshots are used to fix up diagnostic locations when receiving diagnostics
  ## for an older version of the document (e.g when you continue editing and the languages doesn't respond fast enough).
  ## You might want to increase this if you are using a language server which is very slow and you want diagnostics to
  ## show up even when you're actively typing (diagnostics received for old document versions are discarded).
  declare snapshotHistory, int, 5

declareSettings TextSettings, "text":
  ##
  use trimTrailingWhitespace, TrimTrailingWhitespaceSettings

  ## Settings for using ripgrep
  use ripgrep, RipgrepSettings

  ## Configure search regexes.
  use searchRegexes, SearchRegexSettings

  ## Settings for automatically detecting the indent style of files.
  use indentDetection, IndentDetectionSettings

  ## Settings for the diff reload feature.
  use diffReload, DiffReloadSettings

  ## Settings for diagnostics.
  use diagnostics, DiagnosticsSettings

  ## Settings for treesitter.
  use treesitter, TreesitterSettings

  ## How many characters wide a tab is.
  declare tabWidth, int, 4

  ## String which starts a line comment
  declare lineComment, Option[string], nil

  ## When you insert a new line, if the current line ends with one of these strings then the new line will be indented.
  declare indentAfter, Option[seq[string]], nil

  ##
  declare completionWordChars, RuneSetSetting, %%*[["a", "z"], ["A", "Z"], ["0", "9"], "_"]

  ## Whether to used spaces or tabs for indentation. When indent detection is enabled then this only specfies the default
  ## for new files and files where the indentation type can't be detected automatically.
  declare indent, IndentStyleKind, IndentStyleKind.Spaces

  ## If true then files will be automatically reloaded when the content on disk changes (except if you have unsaved changes).
  declare autoReload, bool, false

  ## If true then newly saved files will be added to the vcs (only for perforce right now, does nothing for git)
  declare addNewFileVcs, bool, false

  ## If true then you will be prompted when saving a new file on whether to add it to the vcs, otherwise the file is always added.
  declare addNewFileVcsPrompt, bool, true

type

  TextDocument* = ref object of Document
    languageComponent*: LanguageComponent
    textComponent*: TextComponentImpl
    treesitterComponent*: TreesitterComponentImpl
    lsComponent*: LanguageServerComponent
    formattingComponent: FormattingComponent
    services: Services
    workspace: Workspace
    editors: DocumentEditorService
    eventBus: EventService
    moveDatabase: MoveDatabase

    nextLineIdCounter: int32 = 0

    singleLine*: bool = false

    lastSavedTimer: Timer

    onRequestRerender*: Event[void]
    onPreLoaded*: Event[TextDocument]
    onLoaded*: Event[tuple[document: TextDocument, changed: seq[Selection]]]
    onSaved*: Event[void]
    textChanged*: Event[TextDocument]
    onEdit*: Event[tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]]
    onOperation*: Event[tuple[document: TextDocument, op: buffer.Operation]]
    onBufferChanged*: Event[tuple[document: TextDocument]]
    onLanguageServerAttached*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]
    onLanguageServerDetached*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]
    onDiagnostics*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]
    onLanguageChanged*: Event[tuple[document: TextDocument]]

    undoSelections*: Table[TransactionId, Selections]
    redoSelections*: Table[TransactionId, Selections]

    configService: ConfigService
    config*: ConfigStore
    createLanguageServer*: bool = true
    completionTriggerCharacters*: set[char] = {}

    nextCheckpoints: seq[string]

    languageServerList*: LanguageServerList

    diagnosticsPerLS*: seq[DiagnosticsData] ## Diagnostics per language server
    languageServerDiagnosticsIndex*: Table[string, int] ## Diagnostics per language server
    diagnosticEndPoints*: seq[DiagnosticEndPoint]
    onDiagnosticsHandles: Table[string, (LanguageServer, Id)]
    diagnosticSnapshots: seq[BufferSnapshot] # todo: reset at appropriate times

    checkpoints: Table[TransactionId, seq[string]]

    settings*: TextSettings
    fileWatchHandle: VFSWatchHandle

    moveFallbacks: MoveFunction

    currentDisplayMap: DisplayMap

  DiagnosticsData* = object
    languageServer*: LanguageServer
    currentDiagnostics*: seq[Diagnostic]
    currentDiagnosticsAnchors: seq[Range[Anchor]]
    diagnosticsPerLine*: Table[int, seq[int]]
    lastDiagnosticVersion: Global # todo: reset at appropriate times
    lastDiagnosticAnchorResolve: Global # todo: reset at appropriate times

template returnIfInvalid(): untyped =
  if not self.isInitialized:
    return

proc reloadTreesitterLanguage*(self: TextDocument)
proc clearDiagnostics*(self: TextDocument, languageServerName: string = "")
proc numLines*(self: TextDocument): int {.noSideEffect.}
proc handlePatch(self: TextDocument, oldText: Rope, patch: Patch[uint32])
proc resolveDiagnosticAnchors*(self: TextDocument)
proc recordSnapshotForDiagnostics(self: TextDocument)
proc addTreesitterChange(self: TextDocument, startByte: int, oldEndByte: int, newEndByte: int, startPoint: Point, oldEndPoint: Point, newEndPoint: Point)
proc format*(self: TextDocument, runOnTempFile: bool): Future[void] {.async.}
proc enableAutoReload*(self: TextDocument, enabled: bool)
proc handleLanguageServerAttached(self: TextDocument, languageServer: LanguageServer)
proc handleLanguageServerDetached*(self: TextDocument, languageServer: LanguageServer)
proc addNextCheckpoint*(self: TextDocument, checkpoint: string)
proc setFileAndContent*[S: string | Rope](self: TextDocument, filename: string, content: sink S)

func buffer*(self: TextDocument): var Buffer = self.textComponent.buffer
func rope*(self: TextDocument): lent Rope = self.buffer.snapshot.visibleText

method getStatisticsString*(self: TextDocument): string =
  try:
    let visibleTextStats = stats(self.buffer.snapshot.visibleText.tree)
    let deletedTextStats = stats(self.buffer.snapshot.deletedText.tree)
    let fragmentStats = stats(self.buffer.snapshot.fragments)
    let insertionStats = stats(self.buffer.snapshot.insertions)
    let undoStats = stats(self.buffer.snapshot.undoMap.tree)

    result.add &"Filename: {self.filename}\n"
    result.add &"Lines: {self.numLines}\n"
    result.add &"VisibleText: {visibleTextStats}\n"
    result.add &"DeletedText: {deletedTextStats}\n"
    result.add &"Fragment: {fragmentStats}\n"
    result.add &"Insertion: {insertionStats}\n"
    result.add &"Undo: {undoStats}\n"
  except:
    discard

proc tabWidth*(self: TextDocument): int

proc nextLineId*(self: TextDocument): int32 =
  result = self.nextLineIdCounter
  self.nextLineIdCounter.inc

func getLine*(self: TextDocument, line: int, D: typedesc = int): RopeSlice[D] =
  if line notin 0..<self.numLines:
    return Rope.new("").slice(D)

  let lineRange = self.rope.lineRange(line, int)
  return self.rope.slice(lineRange)

func lineLength*(self: TextDocument, line: int): int =
  return self.rope.lineLen(line)

func lineRuneLen*(self: TextDocument, line: int): RuneCount =
  return self.rope.lineRuneLen(line).RuneCount

proc numLines*(self: TextDocument): int {.noSideEffect.} =
  return self.rope.lines

proc lastCursor*(self: TextDocument): Cursor =
  if self.numLines > 0:
    return (self.numLines - 1, self.rope.lastValidIndex(self.numLines - 1))
  return (0, 0)

proc clampCursor*(self: TextDocument, cursor: Cursor, includeAfter: bool = true): Cursor =
  var cursor = cursor
  cursor.line = clamp(cursor.line, 0, self.numLines - 1)

  var res = self.rope.clipPoint(cursor.toPoint, Bias.Left).toCursor
  var c = self.rope.cursorT(res.toPoint)
  if not includeAfter and c.currentRune == '\n'.Rune and res.column > 0:
    c.seekPrevRune()
    res = c.position.toCursor
  return res

proc clampSelection*(self: TextDocument, selection: Selection, includeAfter: bool = true): Selection = (self.clampCursor(selection.first, includeAfter), self.clampCursor(selection.last, includeAfter))
proc clampAndMergeSelections*(self: TextDocument, selections: openArray[Selection]): Selections = selections.map((s) => self.clampSelection(s)).deduplicate
proc trimTrailingWhitespace*(self: TextDocument)

proc notifyTextChanged*(self: TextDocument) =
  self.textChanged.invoke self

proc notifyRequestRerender*(self: TextDocument) =
  self.onRequestRerender.invoke()

proc tsLanguage*(self: TextDocument): lent TSLanguage = self.treesitterComponent.tsLanguage

proc tsTree*(self: TextDocument): TsTree =
  return self.treesitterComponent.syntaxMap.tsTree

proc languageId*(self: TextDocument): string =
  if self.languageComponent != nil:
    return self.languageComponent.languageId
  return ""

proc `languageId=`*(self: TextDocument, languageId: string) =
  if self.languageComponent != nil:
    self.languageComponent.setLanguageId(languageId)

proc handleLanguageChanged*(self: TextDocument) =
  self.config.setParent(self.configService.getLanguageStore(self.languageId))
  if not self.requiresLoad:
    self.reloadTreesitterLanguage()
  self.onLanguageChanged.invoke (self,)

func contentString*(self: TextDocument): string =
  if self.rope.tree.isNil:
    # todo: this shouldn't be happening
    return ""
  return $self.rope

proc `content=`*(self: TextDocument, value: sink Rope) =
  self.revision.inc
  self.undoableRevision.inc

  self.textComponent.initBuffer(self.buffer.timestamp.replicaId, content = value, remoteId = getNextBufferId())

  self.treesitterComponent.syntaxMap.resetTree(self.rope)

  self.onBufferChanged.invoke (self,)

  self.clearDiagnostics()
  self.notifyTextChanged()

proc `content=`*(self: TextDocument, value: sink string) =
  self.revision.inc
  self.undoableRevision.inc

  let invalidUtf8Index = value.validateUtf8
  if invalidUtf8Index >= 0:
    log lvlWarn, &"[content=] Trying to set content with invalid utf-8 string (invalid byte at {invalidUtf8Index})"
    self.textComponent.initBuffer(content = &"Invalid utf-8 byte at {invalidUtf8Index}", remoteId = getNextBufferId())

  else:
    var index = 0
    const utf8_bom = "\xEF\xBB\xBF"
    if value.len >= 3 and value.startsWith(utf8_bom):
      log lvlInfo, &"[content=] Skipping utf8 bom"
      index = 3

    self.textComponent.initBuffer(content = value[index..^1], remoteId = getNextBufferId())

  self.treesitterComponent.syntaxMap.resetTree(self.rope)

  self.onBufferChanged.invoke (self,)

  self.clearDiagnostics()
  self.notifyTextChanged()

proc edit*[S](self: TextDocument, selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[S], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =
  let selections = self.clampAndMergeSelections(selections).map (s) => s.normalized
  if selections.len == 0:
    return selections

  var sortedSelections = collect:
    for i, s in selections:
      (i, s)

  sortedSelections.sort((a, b) => cmp(a[1].first, b[1].first))

  var pointDiff = PointDiff.default
  var byteDiff = 0

  var edits = newSeqOfCap[tuple[old, new: Selection]](selections.len)
  var c = self.rope.cursorT(Point)

  var ranges = newSeqOfCap[(Range[int], S)](selections.len)
  var newSelections = newSeqOfCap[(int, Selection)](selections.len)
  var tsChanges = newSeqOfCap[tuple[startByte: int, oldEndByte: int, newEndByte: int, startPoint: Point, oldEndPoint: Point, newEndPoint: Point]](selections.len)
  for i, sortedSelection in sortedSelections:
    var selection = sortedSelection[1]

    var text = if texts.len == 1:
      texts[0].clone()
    elif texts.len == selections.len:
      texts[i].clone()
    else:
      texts[min(i, texts.high)].clone()

    let summary = TextSummary.init(text)

    c.seekForward(selection.first.toPoint)

    let startByte = c.offset()
    if selection.last > selection.first:
      c.seekForward(selection.last.toPoint)

    if inclusiveEnd and selection.last.column < self.lineLength(selection.last.line):
      c.seekNextRune()
      selection.last = c.position.toCursor
    let endByte = c.offset()

    assert startByte <= self.buffer.contentLength and endByte <= self.buffer.contentLength
    ranges.add (startByte...endByte, text.move)

    let oldByteRange = (startByte + byteDiff, endByte + byteDiff)
    let newByteRangeEnd = oldByteRange[0] + summary.bytes
    let oldPointRange = (selection.first.toPoint + pointDiff, selection.last.toPoint + pointDiff)
    let newPointRangeEnd = oldPointRange[0] + summary.lines

    let newSelection = (oldPointRange[0], newPointRangeEnd).toSelection
    newSelections.add (sortedSelection[0], newSelection)
    edits.add (selection, newSelection)

    if not self.tsLanguage.isNil:
      tsChanges.add (oldByteRange[0], oldByteRange[1], newByteRangeEnd, oldPointRange[0], oldPointRange[1], newPointRangeEnd)

    pointDiff = newPointRangeEnd - selection.last.toPoint
    byteDiff = newByteRangeEnd - endByte

  newSelections.sort((a, b) => cmp(a[0], b[0]))
  result = newSelections.mapIt(it[1])
  assert result.len > 0

  self.revision.inc
  self.undoableRevision.inc

  if self.nextCheckpoints.len > 0:
    discard self.buffer.startTransaction()
    if oldSelections.len > 0:
      self.undoSelections[self.buffer.currentTransaction.id] = @oldSelections
  elif self.buffer.currentTransaction.editIds.len == 0:
    self.undoSelections[self.buffer.currentTransaction.id] = @oldSelections

  let oldText = self.rope
  let (transactionId, op) = self.buffer.edit(ranges)
  self.recordSnapshotForDiagnostics()

  for tsChange in tsChanges:
    self.addTreesitterChange(tsChange.startByte, tsChange.oldEndByte, tsChange.newEndByte, tsChange.startPoint, tsChange.oldEndPoint, tsChange.newEndPoint)

  self.nextCheckpoints.setLen 0

  self.onOperation.invoke (self, op)
  self.onEdit.invoke (self, edits)

  var patch = Patch[Point]()
  for e in edits:
    patch.edits.add initEdit(e.old.toRange, e.new.toRange)
  self.textComponent.onEdit.invoke (oldText, patch)

  self.redoSelections[transactionId] = result.mapIt(it.last.toSelection)
  self.treesitterComponent.syntaxMap.currentContentFailedToParse = false

  if notify:
    self.notifyTextChanged()

  for s in result.items:
    assert s.first.line in 0..int32.high
    assert s.first.column in 0..int32.high
    assert s.last.line in 0..int32.high
    assert s.last.column in 0..int32.high

proc replaceAll*(self: TextDocument, value: sink Rope) =
  let fullRange = ((0, 0), self.rope.summary().lines.toCursor)
  self.nextCheckpoints.incl ""
  discard self.edit([fullRange], [], [value])
  discard self.buffer.endTransaction()

proc replaceAll*(self: TextDocument, value: sink string) =
  let invalidUtf8Index = value.validateUtf8
  if invalidUtf8Index >= 0:
    log lvlError, &"[content=] Trying to set content with invalid utf-8 string (invalid byte at {invalidUtf8Index})"
    return

  var index = 0
  const utf8_bom = "\xEF\xBB\xBF"
  if value.len >= 3 and value.startsWith(utf8_bom):
    log lvlInfo, &"[content=] Skipping utf8 bom"
    index = 3

  let fullRange = ((0, 0), self.rope.summary().lines.toCursor)
  self.nextCheckpoints.incl ""
  discard self.edit([fullRange], [], [value[index..^1]])
  discard self.buffer.endTransaction()

proc rebuildBuffer*(self: TextDocument, replicaId: ReplicaId, bufferId: BufferId, content: string) =
  self.content = content
  self.textComponent.initBuffer(replicaId, content, bufferId)

  self.notifyRequestRerender()

proc recordSnapshotForDiagnostics(self: TextDocument) =
  let diagnosticHistoryMaxLength = self.settings.diagnostics.snapshotHistory.get()
  self.diagnosticSnapshots.add(self.buffer.snapshot.clone())
  while self.diagnosticSnapshots.len > diagnosticHistoryMaxLength:
    self.diagnosticSnapshots.removeShift(0)

proc applyRemoteChanges*(self: TextDocument, ops: sink seq[buffer.Operation]) =
  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  # todo: checkpoints
  discard self.buffer.applyRemote(ops)
  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

proc `content=`*(self: TextDocument, value: seq[string]) =
  self.content = value.join("\n")

func contentString*(self: TextDocument, selection: Selection, inclusiveEnd: bool = false): string =
  let selection = selection.normalized

  var c = self.rope.cursorT(selection.first.toPoint)
  var target = selection.last
  if inclusiveEnd and target.column < self.lineLength(target.line):
    target.column += 1

  let res = c.slice(target.toPoint, Bias.Right)
  return $res

func contentString*(self: TextDocument, selection: TSRange): string =
  return self.contentString selection.toSelection

func charAt*(self: TextDocument, cursor: Cursor): char =
  if cursor.line < 0 or cursor.line > self.numLines - 1:
    return 0.char
  if cursor.column < 0 or cursor.column > self.lineLength(cursor.line):
    return 0.char

  var c = self.rope.cursorT(cursor.toPoint)
  return c.currentChar

func runeAt*(self: TextDocument, cursor: Cursor): Rune =
  if cursor.line < 0 or cursor.line > self.numLines - 1:
    return 0.Rune
  if cursor.column < 0 or cursor.column > self.lineLength(cursor.line):
    return 0.Rune

  var c = self.rope.cursorT(cursor.toPoint)
  return c.currentRune

proc runeCursorToCursor*(self: TextDocument, cursor: RuneCursor): Cursor =
  if cursor.line < 0:
    return (0, 0)
  if cursor.line >= self.rope.lines:
    return self.rope.endPoint.toCursor

  return (cursor.line, self.rope.byteOffsetInLine(cursor.line, cursor.column))

proc runeSelectionToSelection*(self: TextDocument, cursor: RuneSelection): Selection =
  return (self.runeCursorToCursor(cursor.first), self.runeCursorToCursor(cursor.last))

proc lspRangeToSelection*(self: TextDocument, r: lsp_types.Range): Selection =
  let runeSelection = (
    (r.start.line, r.start.character.RuneIndex),
    (r.`end`.line, r.`end`.character.RuneIndex))
  return self.runeSelectionToSelection(runeSelection)

proc isAtExpressionStartBasic*(self: TextDocument, location: Cursor): bool =
  let r = self.runeAt(location)
  if r <= char.high.Rune and r.char in {')', '}', ']', '>', '\n', ' ', ',', ';'}:
    return false
  return true

proc isAtExpressionStart*(self: TextDocument, location: Cursor): bool =
  if self.tsTree.isNil:
    return self.isAtExpressionStartBasic(location)

  var leaf = self.tsTree.root.descendantForRange(location.toSelection.tsRange)
  if leaf.len == 0 and location >= leaf.getRange.toSelection.first and location <= leaf.getRange.toSelection.last:
    return self.isAtExpressionStartBasic(location)

  while not leaf.isNamed and not leaf.parent.isNull():
    leaf = leaf.parent
    if not leaf.isNamed and location >= leaf.getRange.toSelection.first and location <= leaf.getRange.toSelection.last:
      return self.isAtExpressionStartBasic(location)

  return location == leaf.getRange.toSelection.first

proc loadTreesitterLanguage(self: TextDocument): Future[void] {.async.} =
  # logScope lvlInfo, &"loadTreesitterLanguage '{self.filename}'"

  self.treesitterComponent.clear()

  if self.languageId == "":
    return

  let prevLanguageId = self.languageId
  let pathOverride = self.settings.treesitter.path.get()
  let treesitterLanguageName = self.settings.treesitter.language.get().get(self.languageId)
  var language = await getTreesitterLanguage(self.vfs, treesitterLanguageName, pathOverride)
  if not self.isInitialized:
    return

  if prevLanguageId != self.languageId:
    return

  if language.isNone:
    return

  # log lvlInfo, &"loadTreesitterLanguage {prevLanguageId}: Loaded language, apply"
  self.treesitterComponent.tsLanguage = language.get

  # todo: this awaits, check if still current request afterwards
  # todo: allow specifying queries in home and workspace config
  let highlightQueryPath = &"app://languages/{treesitterLanguageName}/queries/highlights.scm"
  let highlightQuery = language.get.queryFile(self.vfs, "highlights", highlightQueryPath).await
  if not self.isInitialized:
    return
  if highlightQuery.isSome:
    if prevLanguageId != self.languageId:
      return

    self.treesitterComponent.highlightQuery = highlightQuery.get

  let textObjectsQueryPath = &"app://languages/{treesitterLanguageName}/queries/textobjects.scm"
  let textObjectsQuery = language.get.queryFile(self.vfs, "textobjects", textObjectsQueryPath).await
  if not self.isInitialized:
    return
  if textObjectsQuery.isSome:
    if prevLanguageId != self.languageId:
      return

    self.treesitterComponent.textObjectsQuery = textObjectsQuery.get

  let tagsQueryPath = &"app://languages/{treesitterLanguageName}/queries/tags.scm"
  let tagsQuery = language.get.queryFile(self.vfs, "tags", tagsQueryPath).await
  if not self.isInitialized:
    return
  if tagsQuery.isSome:
    if prevLanguageId != self.languageId:
      return

    self.treesitterComponent.tagsQuery = tagsQuery.get

  if not self.isInitialized:
    return

  let errorQueryPath = &"app://languages/{treesitterLanguageName}/queries/errors.scm"
  var errorQuery = language.get.queryFile(self.vfs, "error", errorQueryPath, cacheOnFail = false).await
  if not self.isInitialized:
    return
  if errorQuery.isSome:
    if prevLanguageId != self.languageId:
      return
    self.treesitterComponent.errorQuery = errorQuery.get
  else:
    errorQuery = language.get.query("error", "(ERROR) @error").await
    if errorQuery.isSome:
      self.treesitterComponent.errorQuery = errorQuery.get

  if not self.isInitialized:
    return

  if prevLanguageId != self.languageId:
    return

  let injectionQueryPath = &"app://languages/{treesitterLanguageName}/queries/injections.scm"
  let injectionQuery = language.get.queryFile(self.vfs, "injections", injectionQueryPath, cacheOnFail = false).await
  if not self.isInitialized:
    return
  if prevLanguageId != self.languageId:
    return

  self.treesitterComponent.syntaxMap.setLanguage(language.get, self.treesitterComponent.highlightQuery, injectionQuery.get(nil), self.rope)
  self.notifyRequestRerender()

proc tsQuery*(self: TextDocument, name: string): Future[Option[TSQuery]] {.async.} =
  self.treesitterComponent.tsQueries.withValue(name, q):
    return q[]

  if self.tsLanguage.isNil:
    return TSQuery.none

  let prevLanguageId = self.languageId
  let treesitterLanguageName = self.settings.treesitter.language.get().get(self.languageId)
  let path = &"app://languages/{treesitterLanguageName}/queries/{name}.scm"
  let query = self.tsLanguage.queryFile(self.vfs, name, path).await
  if prevLanguageId != self.languageId:
    return TSQuery.none

  self.treesitterComponent.tsQueries[name] = query
  return query

proc reloadTreesitterLanguage*(self: TextDocument) =
  asyncSpawn self.loadTreesitterLanguage()

proc displayMap(self: TextDocument): DisplayMap =
  if self.currentDisplayMap == nil:
    self.currentDisplayMap = DisplayMap.new()
    self.currentDisplayMap.setBuffer(self.buffer.snapshot.clone())
  elif self.currentDisplayMap.buffer.version != self.buffer.version:
    debugf"Update display map to current {self.currentDisplayMap.buffer.version} -> {self.buffer.version}"
    self.currentDisplayMap.setBuffer(self.buffer.snapshot.clone())
  return self.currentDisplayMap

proc getLanguageWordBoundary*(self: TextDocument, cursor: Cursor): Selection

proc applyMoveFallback*(self: TextDocument, move: string, selections: openArray[Selection], count: int, largs: openArray[LispVal], env: Env): seq[Selection] =

  try:
    case move
    of "language-word":
      return selections.mapIt(self.getLanguageWordBoundary(it.last))
    of "completion-selection":
      return selections.mapIt(block:
        if it.last.column == 0:
          it.last.toSelection
        else:
          var c = self.rope.cursorT(it.last.toPoint)

          let identRunes {.cursor.} = self.settings.completionWordChars.get()
          var column = c.position.column
          while c.position.column > 0:
            c.seekPrevRune()
            if c.currentRune in identRunes:
              column = c.position.column
            else:
              break

          ((it.last.line, column.int), it.last)
      )

    of "ts-text-object", "ts":
      let capture = if largs.len > 0:
        largs[0].toJson.jsonTo(string)
      else:
        ""
      let captureMove = if largs.len > 1:
        largs[1]
      else:
        parseLisp("(combine)")

      if self.treesitterComponent.textObjectsQuery != nil and not self.tsTree.isNil:
        for s in selections:
          for captures in self.treesitterComponent.textObjectsQuery.query(self.tsTree, s):
            var captureSelections = newSeqOfCap[Selection](captures.len)
            if self.moveDatabase.debugMoves:
              debugf"move 'ts' {move}: {captures.len} captures"
            for (node, nodeCapture) in captures:
              if capture == "" or capture == nodeCapture:
                var sel = node.getRange().toSelection
                captureSelections.add sel
                if self.moveDatabase.debugMoves:
                  debugf"    {sel}"

            let captureSelectionsTransformed = self.moveDatabase.applyMove(self.displayMap, captureMove, captureSelections, env, self.moveFallbacks)

            result.add captureSelectionsTransformed

    else:
      log lvlWarn, &"Unknown move '{move}'"
      return @selections

  except CatchableError as e:
    log lvlWarn, &"Failed to apply move '{move}': {e.msg}"
    return @selections

proc newTextDocument*(
    services: Services,
    filename: string = "",
    content: string = "",
    app: bool = false,
    language: Option[string] = string.none,
    languageServer: Option[LanguageServer] = LanguageServer.none,
    load: bool = false,
    createLanguageServer: bool = true,
    id = Id.none,
    initialSettings: JsonNodeEx = newJexObject()): TextDocument =

  log lvlInfo, &"Creating new text document '{filename}', (lang: {language})"
  new(result)

  var self = result
  if id.isSome:
    self.uniqueId = id.get
  else:
    self.uniqueId = newId()
  self.isInitialized = true
  self.appFile = app
  self.workspace = services.getService(Workspace).get
  self.services = services
  self.configService = services.getService(ConfigService).get
  self.vfs = services.getService(VFSService).get.vfs
  self.vfs2 = services.getService(VFSService).get.vfs2
  self.editors = services.getService(DocumentEditorService).get
  self.eventBus = self.services.getService(EventService).get
  self.moveDatabase = self.services.getService(MoveDatabase).get
  self.createLanguageServer = createLanguageServer
  self.filename = self.vfs2.normalize(filename)
  self.isBackedByFile = load
  self.requiresLoad = load

  assert initialSettings != nil
  self.config = self.configService.addStore("document/" & self.filename, &"settings://document/{self.filename}", settings = initialSettings)
  self.settings = TextSettings.new(self.config)
  self.languageServerList = newLanguageServerList(self.config)

  self.languageComponent = newLanguageComponent()
  self.addComponent(self.languageComponent)
  discard self.languageComponent.onLanguageChanged.subscribe proc (c: LanguageComponent) =
    c.owner.TextDocument.handleLanguageChanged()

  self.textComponent = newTextComponent()
  self.textComponent.editString = proc(selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[string],
      notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Selection] {.gcsafe, raises: [].} =
    if checkpoint != "":
      self.addNextCheckpoint(checkpoint)
    self.edit(selections, oldSelections, texts, notify, record, inclusiveEnd)
  self.textComponent.editRope = proc(selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[Rope],
      notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Selection] {.gcsafe, raises: [].} =
    if checkpoint != "":
      self.addNextCheckpoint(checkpoint)
    self.edit(selections, oldSelections, texts, notify, record, inclusiveEnd)
  self.textComponent.editRopeSlice = proc(selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[RopeSlice[int]],
      notify: bool = true, record: bool = true, inclusiveEnd: bool = false, checkpoint: string = ""): seq[Selection] {.gcsafe, raises: [].} =
    if checkpoint != "":
      self.addNextCheckpoint(checkpoint)
    self.edit(selections, oldSelections, texts, notify, record, inclusiveEnd)
  self.textComponent.setFileAndContentImpl = proc(filename: string, content: sink Rope) =
    self.setFileAndContent(filename, content)
  self.addComponent(self.textComponent)

  self.treesitterComponent = newTreesitterComponent(self.vfs)
  self.addComponent(self.treesitterComponent)
  discard self.treesitterComponent.syntaxMap.onParsed.subscribe(proc() =
    self.notifyRequestRerender()
  )

  self.formattingComponent = newFormattingComponent(services.getService(VFSService).get.vfs2, self.config)
  self.addComponent(self.formattingComponent)

  self.moveFallbacks = proc(move: string, selections: openArray[Selection], count: int, args: openArray[LispVal], env: Env): seq[Selection] =
    self.applyMoveFallback(move, selections, count, args, env)

  if language.getSome(language):
    self.languageId = language
  else:
    getLanguageForFile(self.config, filename).applyIt:
      self.languageId = it

  self.addComponent(newConfigComponent(self.config))
  self.addComponent(newMoveComponent(self.services, self.displayMap, self.moveFallbacks))

  self.lsComponent = newLanguageServerComponent(self.languageServerList)
  discard self.lsComponent.onLanguageServerAttached.subscribe proc(arg: auto) {.gcsafe, raises: [].} =
    self.handleLanguageServerAttached(arg[1])
  discard self.lsComponent.onLanguageServerDetached.subscribe proc(arg: auto) {.gcsafe, raises: [].} =
    self.handleLanguageServerDetached(arg[1])
  self.addComponent(self.lsComponent)

  self.content = content

  if languageServer.isSome:
    discard self.lsComponent.addLanguageServer(languageServer.get)

  self.editors.registerDocument(self)
  self.eventBus.emit(&"document/{self.id}/registered", $self.id)

method deinit*(self: TextDocument) =
  # debugf"[deinit] Destroying text document '{self.filename}'"
  if not self.isInitialized:
    return

  self.editors.unregisterDocument(self)

  self.fileWatchHandle.unwatch()

  self.treesitterComponent.clear()

  if self.languageServerList.isNotNil:
    self.languageServerList.disconnect(self)

  for (ls, id) in self.onDiagnosticsHandles.values:
    ls.onDiagnostics.unsubscribe(id)

  self[] = default(typeof(self[]))

method `$`*(self: TextDocument): string =
  return self.filename

proc addFileVcsAsync*(self: TextDocument, prompt: bool = true) {.async.}

proc saveAsync*(self: TextDocument) {.async.} =
  try:
    log lvlInfo, &"[save] '{self.filename}'"

    if self.filename.len == 0:
      log lvlError, &"save: Missing filename"
      return

    if self.staged:
      return

    self.onDocumentBeforeSave.invoke(self)
    for h in self.preSaveHandlers:
      await h(self)
    if not self.isInitialized:
      return

    let trimTrailingWhitespace = self.settings.trimTrailingWhitespace.enabled.get()
    let maxFileSizeForTrim = self.settings.trimTrailingWhitespace.maxSize.get()
    if trimTrailingWhitespace:
      if self.rope.len <= maxFileSizeForTrim:
        self.trimTrailingWhitespace()
      else:
        log lvlWarn, &"File is bigger than max size: {self.rope.len} > {maxFileSizeForTrim}"
    else:
      log lvlWarn, &"Don't trim whitespace"

    var newFile = false
    if self.vfs2.getFileKind(self.filename).await.isNone:
      newFile = true
    if not self.isInitialized:
      return

    discard self.buffer.endTransaction()

    self.lastSavedTimer = startTimer()
    await self.vfs2.write(self.filename, self.rope.slice())
    self.lastSavedTimer = startTimer()

    if not self.isInitialized:
      return

    self.isBackedByFile = true
    self.lastSavedRevision = self.undoableRevision
    # todo: what if someone changes the document while saving?
    self.textComponent.savedVersion = self.buffer.history.undoTree.nodes[self.buffer.history.undoTree.current].transaction.id
    self.onSaved.invoke()
    self.onDocumentSaved.invoke(self)
    self.eventBus.emit(&"document/{self.id}/saved", $self.id)

    if newFile and self.settings.addNewFileVcs.get():
      asyncSpawn self.addFileVcsAsync(prompt=self.settings.addNewFileVcsPrompt.get());

  except IOError as e:
    log lvlError, &"Failed to save file '{self.filename}': {e.msg}"

method save*(self: TextDocument, filename: string = "", app: bool = false): Future[void] {.async: (raises: []).} =
  self.filename = if filename.len > 0: self.vfs2.normalize(filename) else: self.filename

  if self.filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  if self.staged:
    return

  self.appFile = app

  try:
    await self.saveAsync()
  except CatchableError:
    discard

proc autoDetectIndentStyle(self: TextDocument) =
  if not self.settings.indentDetection.enable.get():
    return

  let maxSamples = self.settings.indentDetection.samples.get()
  let maxTime = self.settings.indentDetection.timeout.get().float64

  var containsTab = false
  var linePos = Point.init(0, 0)
  var c = self.rope.cursorT(linePos)

  var minIndent = int.high
  var samples = 0

  var t = startTimer()
  while not c.atEnd:
    if c.currentRune == '\t'.Rune:
      containsTab = true
      break
    if c.currentRune == ' '.Rune:
      let lineIndent = self.rope.indentBytes(linePos.row.int)
      if lineIndent in {2, 4, 8}:
        minIndent = min(minIndent, lineIndent)
      containsTab = false
      inc samples
      if samples == maxSamples:
        break

    if t.elapsed.ms >= maxTime:
      break

    linePos.row += 1
    c.seekForward(linePos)

  if containsTab:
    self.settings.indent.set(Tabs)
  else:
    if minIndent != int.high:
      self.settings.tabWidth.set(minIndent)
      self.settings.indent.set(Spaces)

  # log lvlInfo, &"[Text_document] Detected indent: {self.settings.indent.get()}, {self.settings.tabWidth.get()}"

proc reloadFromRope*(self: TextDocument, rope: sink Rope): Future[seq[Selection]] {.async.} =
  if self.settings.diffReload.enable.get():
    let diffTimeout = self.settings.diffReload.timeout.get()
    let t = startTimer()

    try:
      let oldRope = self.rope.clone()
      var diff = RopeDiff[int]()
      await diffRopeAsync(oldRope.clone(), rope.clone(), diff.addr).wait(diffTimeout.milliseconds)
      if not self.isInitialized:
        return
      log lvlDebug, &"Diff took {t.elapsed.ms} ms"

      if diff.edits.len > 0:
        var selections = newSeq[Selection]()
        var texts = newSeq[RopeSlice[int]]()
        for edit in diff.edits:
          let a = oldRope.convert(edit.old.a, Point)
          let b = oldRope.convert(edit.old.b, Point)
          selections.add (a.toCursor, b.toCursor)
          texts.add edit.text.clone()

        result = self.edit(selections, [], texts)
        discard self.buffer.endTransaction()

        when defined(appCheckDiffReload):
          if $self.rope != $rope:
            log lvlError, &"Failed diff: {self.rope.len} != {rope.len}: {selections}, {texts}"
            await self.vfs2.write("app://failed_diffs/old.txt", oldRope)
            returnIfInvalid()
            await self.vfs2.write("app://failed_diffs/new-edit.txt", self.rope)
            returnIfInvalid()
            await self.vfs2.write("app://failed_diffs/new.txt", rope)
            returnIfInvalid()
            self.replaceAll(rope.move)
            return @[((0, 0), (self.rope.endPoint.toCursor))]

        return

    except AsyncTimeoutError:
      log lvlDebug, &"Timeout after {t.elapsed.ms} ms"
      self.replaceAll(rope.move)

  else:
    self.replaceAll(rope.move)

  return @[((0, 0), (self.rope.endPoint.toCursor))]

proc loadAsync*(self: TextDocument, isReload: bool, filename: string, temp: bool = false): Future[void] {.async.} =
  logScope lvlInfo, &"loadAsync '{self.filename}', reload = {isReload}"

  if not temp:
    self.isBackedByFile = true
    self.isLoadingAsync = true
    self.readOnly = true

  var rope: Rope = Rope.new()
  try:
    await self.vfs2.readRope(filename, rope.addr)

    if not self.isInitialized:
      return
  except InvalidUtf8Error as e:
    log lvlWarn, &"[loadAsync] Failed to load file {filename}: {e.msg}"
    rope = Rope.new(e.msg)
  except IOError as e:
    log lvlError, &"[loadAsync] Failed to load file {filename}: {e.msg}"
    self.readOnly = false
    return

  if not self.isInitialized:
    return

  self.onPreLoaded.invoke self

  let changedRegions = if isReload:
    await self.reloadFromRope(rope.clone())
  else:
    self.content = rope.clone()
    @[((0, 0), (self.rope.endPoint.toCursor))]

  if not self.isInitialized:
    return

  if self.settings.autoReload.get():
    self.enableAutoReload(true)
  else:
    self.fileWatchHandle.unwatch()

  if self.vfs2.getFileAttributes(filename).await.mapIt(it.writable).get(true):
    self.readOnly = false

  if not self.isInitialized:
    return
  self.autoDetectIndentStyle()

  if not temp:
    self.lastSavedRevision = self.undoableRevision
    self.textComponent.savedVersion = self.buffer.history.undoTree.nodes[self.buffer.history.undoTree.current].transaction.id
  self.isLoadingAsync = false
  self.onLoaded.invoke (self, changedRegions)
  self.onDocumentLoaded.invoke self
  self.eventBus.emit(&"document/{self.id}/loaded", $self.id)

proc enableAutoReload*(self: TextDocument, enabled: bool) =
  self.settings.autoReload.set(enabled)
  if enabled and (not self.fileWatchHandle.isBound or self.fileWatchHandle.path != self.filename):
    self.fileWatchHandle.unwatch()
    self.fileWatchHandle = self.vfs2.watch(self.filename, proc(events: seq[PathEvent]) =
      if not self.isInitialized or not self.settings.autoReload.get():
        return
      if self.lastSavedTimer.elapsed.ms < 1000:
        # Probably notification about our own saving, dont reload in that case.
        return
      let isDirty = self.lastSavedRevision != self.revision
      if isDirty:
        log lvlError, &"Failed to auto reload '{self.filename}': Unsaved changes"
        return
      for e in events:
        case e.action
        of Modify:
          # if self.services.getService(ToastService).getSome(toasts):
          #   toasts.showToast(self.filename, &"Auto reloaded", "info")
          asyncSpawn self.loadAsync(true, self.filename)
          break

        else:
          discard
    )
    self.fileWatchHandle.path = self.filename

  elif not enabled:
    self.fileWatchHandle.unwatch()

proc setFileAndContent*[S: string | Rope](self: TextDocument, filename: string, content: sink S) =
  let filename = if filename.len > 0: self.vfs2.normalize(filename) else: self.filename
  if filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  logScope lvlInfo, &"[setFileAndContent] '{filename}'"

  self.filename = filename
  self.isBackedByFile = false

  getLanguageForFile(self.config, filename).applyIt:
    self.languageId = it
  do:
    self.languageId = ""

  self.onPreLoaded.invoke self

  self.content = content.move

  self.autoDetectIndentStyle()
  let changedRegions = @[((0, 0), (self.rope.endPoint.toCursor))]
  self.onLoaded.invoke (self, changedRegions)
  self.onDocumentLoaded.invoke self
  self.eventBus.emit(&"document/{self.id}/loaded", $self.id)

method load*(self: TextDocument, filename: string = "", temp: bool = false) =
  let filename = if filename.len > 0: self.vfs2.normalize(filename) else: self.filename
  if filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  if self.requiresLoad:
    self.reloadTreesitterLanguage()

  let isReload = self.isBackedByFile and filename == self.filename and not self.requiresLoad
  if not temp:
    self.filename = filename
    self.isBackedByFile = true
  self.requiresLoad = false

  asyncSpawn self.loadAsync(isReload, filename, temp)

proc format*(self: TextDocument, runOnTempFile: bool): Future[void] {.async.} =
  try:
    await self.formattingComponent.format()
  except Exception as e:
    log lvlError, &"Failed to format document '{self.filename}': {e.msg}\n{e.getStackTrace()}"

proc updateDiagnosticEndPoints(self: TextDocument) =
  self.diagnosticEndPoints.setLen(0)
  for diagnostics in self.diagnosticsPerLS.mitems:
    for i, d in diagnostics.currentDiagnostics:
      let severity = d.severity.get(lsp_types.DiagnosticSeverity.Hint)
      self.diagnosticEndPoints.add DiagnosticEndPoint(severity: severity, point: d.selection.first.toPoint, start: true)
      self.diagnosticEndPoints.add DiagnosticEndPoint(severity: severity, point: d.selection.last.toPoint, start: false)

  self.diagnosticEndPoints.sort proc(a, b: DiagnosticEndPoint): int = cmp(a.point, b.point)

proc resolveDiagnosticAnchors*(self: var DiagnosticsData, buffer: sink BufferSnapshot) =
  if self.currentDiagnostics.len == 0:
    return

  if self.lastDiagnosticAnchorResolve == buffer.version:
    return

  let snapshot = buffer.clone()
  self.lastDiagnosticAnchorResolve = buffer.version
  self.diagnosticsPerLine.clear()

  for i in countdown(self.currentDiagnostics.high, 0):
    if self.currentDiagnosticsAnchors[i].summaryOpt(Point, snapshot, resolveDeleted = false).getSome(range):
      self.currentDiagnostics[i].selection = range.toSelection
      self.currentDiagnosticsAnchors[i] = snapshot.anchorAt(self.currentDiagnostics[i].selection.toRange, Right, Left)
    else:
      self.currentDiagnostics.removeSwap(i)
      self.currentDiagnosticsAnchors.removeSwap(i)
      continue

  for i, d in self.currentDiagnostics:
    for line in d.selection.first.line..d.selection.last.line:
      self.diagnosticsPerLine.mgetOrPut(line, @[]).add i

proc resolveDiagnosticAnchors*(self: TextDocument) =
  for diagnostics in self.diagnosticsPerLS.mitems:
    diagnostics.resolveDiagnosticAnchors(self.buffer.snapshot.clone())
  self.updateDiagnosticEndPoints()

proc setCurrentDiagnostics(self: TextDocument, languageServer: LanguageServer, diagnostics: openArray[lsp_types.Diagnostic], snapshot: sink Option[BufferSnapshot]) =

  let snapshot = snapshot.take(self.buffer.snapshot.clone())

  if languageServer.name notin self.languageServerDiagnosticsIndex:
    self.diagnosticsPerLS.add DiagnosticsData(languageServer: languageServer)
    self.languageServerDiagnosticsIndex[languageServer.name] = self.diagnosticsPerLS.high

  proc setDiagnostics(diagnosticsData: var DiagnosticsData, diagnostics: openArray[lsp_types.Diagnostic], snapshot: sink BufferSnapshot) =

    diagnosticsData.currentDiagnostics.setLen diagnostics.len
    diagnosticsData.currentDiagnosticsAnchors.setLen diagnostics.len
    diagnosticsData.diagnosticsPerLine.clear()

    for i, d in diagnostics:
      let runeSelection = (
        (d.`range`.start.line, d.`range`.start.character.RuneIndex),
        (d.`range`.`end`.line, d.`range`.`end`.character.RuneIndex))
      let selection = self.runeSelectionToSelection(runeSelection).normalized

      diagnosticsData.currentDiagnostics[i] = language_server_base.Diagnostic(
        selection: selection,
        severity: d.severity,
        code: d.code,
        codeDescription: d.codeDescription,
        source: d.source,
        message: d.message,
        tags: d.tags,
        relatedInformation: d.relatedInformation,
        data: d.data,
      )

      diagnosticsData.currentDiagnosticsAnchors[i] = snapshot.anchorAt(selection.toRange, Right, Left)

      for line in selection.first.line..selection.last.line:
        diagnosticsData.diagnosticsPerLine.mgetOrPut(line, @[]).add i

    # diagnosticsData.updateDiagnosticEndPoints()

    if snapshot.version != self.buffer.version:
      diagnosticsData.lastDiagnosticAnchorResolve = snapshot.version
      diagnosticsData.resolveDiagnosticAnchors(snapshot)

  self.updateDiagnosticEndPoints()

  if languageServer.name notin self.languageServerDiagnosticsIndex:
    self.diagnosticsPerLS.add DiagnosticsData(languageServer: languageServer)
    self.languageServerDiagnosticsIndex[languageServer.name] = self.diagnosticsPerLS.high

  self.diagnosticsPerLS[self.languageServerDiagnosticsIndex[languageServer.name]].setDiagnostics(diagnostics, snapshot)

  self.onDiagnostics.invoke (self, languageServer)
  self.notifyRequestRerender()

proc updateDiagnosticsAsync*(self: TextDocument): Future[void] {.async.} =
  discard
  # todo
  # if self.languageServerList.languageServers.len > 0:
  #   let snapshot = self.buffer.snapshot.clone()
  #   let diagnostics = await self.languageServerList.getDiagnostics(self.filename)

  #   if not self.isInitialized:
  #     return

  #   if not diagnostics.isSuccess:
  #     return

  #   if not snapshot.version.observedAll(self.lastDiagnosticVersion):
  #     log lvlWarn, &"Got diagnostics older that the current. Current {self.lastDiagnosticVersion}, received {snapshot.version}"
  #     return

  #   self.lastDiagnosticVersion = snapshot.version
  #   self.setCurrentDiagnostics(ls, diagnostics.result, snapshot.some)

proc handleDiagnosticsReceived(self: TextDocument, languageServer: LanguageServer, diagnostics: lsp_types.PublicDiagnosticsParams) =
  if not self.settings.diagnostics.enable.get():
    self.clearDiagnostics(languageServer.name)
    return

  let uri = diagnostics.uri.decodeUrl.parseUri
  if uri.path.normalizePathUnix != self.localizedPath:
    return

  if languageServer.name notin self.languageServerDiagnosticsIndex:
    self.diagnosticsPerLS.add DiagnosticsData(languageServer: languageServer)
    self.languageServerDiagnosticsIndex[languageServer.name] = self.diagnosticsPerLS.high

  let diagnosticsData = self.diagnosticsPerLS[self.languageServerDiagnosticsIndex[languageServer.name]].addr
  let version = diagnostics.version.mapIt(self.buffer.history.versions.get(it)).flatten
  if version.getSome(version) and not version.observedAll(diagnosticsData[].lastDiagnosticVersion):
    log lvlWarn, &"Got diagnostics older than the current. Current {diagnosticsData[].lastDiagnosticVersion}, received {version}"
    return

  if version.getSome(version):
    diagnosticsData[].lastDiagnosticVersion = version

  var snapshot: Option[BufferSnapshot] = BufferSnapshot.none
  for i in 0..self.diagnosticSnapshots.high:
    if self.diagnosticSnapshots[i].version.some == version:
      snapshot = self.diagnosticSnapshots[i].clone().some
      break

  if snapshot.isNone and version.isSome:
    log lvlWarn, &"Got diagnostics for old version {version.get}, currently on {self.buffer.version}, ignore"
    return

  self.setCurrentDiagnostics(languageServer, diagnostics.diagnostics, snapshot)

proc addLanguageServer*(self: TextDocument, languageServer: LanguageServer): bool =
  self.lsComponent.addLanguageServer(languageServer)

proc removeLanguageServer*(self: TextDocument, languageServer: LanguageServer): bool =
  self.lsComponent.removeLanguageServer(languageServer)

proc handleLanguageServerAttached(self: TextDocument, languageServer: LanguageServer) =
  languageServer.connect(self)

  # todo: only do that if language server supports sending diagnostics
  # if languageServer.capabilities.diagnosticProvider.isSome:
  let onDiagnosticsHandle = languageServer.onDiagnostics.subscribe proc(diagnostics: lsp_types.PublicDiagnosticsParams) =
    self.handleDiagnosticsReceived(languageServer, diagnostics)
  self.onDiagnosticsHandles[languageServer.name] = (languageServer, onDiagnosticsHandle)

  self.completionTriggerCharacters = {}
  for ls in self.languageServerList.languageServers:
    self.completionTriggerCharacters.incl ls.getCompletionTriggerChars()
  self.onLanguageServerAttached.invoke (self, languageServer)

proc handleLanguageServerDetached*(self: TextDocument, languageServer: LanguageServer) =
  if languageServer.name in self.onDiagnosticsHandles:
    languageServer.onDiagnostics.unsubscribe(self.onDiagnosticsHandles[languageServer.name][1])
    self.onDiagnosticsHandles.del(languageServer.name)

  self.onLanguageServerDetached.invoke (self, languageServer)

proc hasLanguageServer*(self: TextDocument, languageServer: LanguageServer): bool =
  self.languageServerList.languageServers.find(languageServer) != -1

proc getLanguageServer*(self: TextDocument): Option[LanguageServer] =
  if self.languageServerList.languageServers.len > 0:
    return self.languageServerList.LanguageServer.some
  return LanguageServer.none

proc clearDiagnostics*(self: TextDocument, languageServerName: string = "") =
  if languageServerName == "":
    for diagnostics in self.diagnosticsPerLS.mitems:
      if diagnostics.currentDiagnostics.len == 0:
        continue
      diagnostics.diagnosticsPerLine.clear()
      diagnostics.currentDiagnostics.setLen 0
      diagnostics.currentDiagnosticsAnchors.setLen 0
  elif languageServerName in self.languageServerDiagnosticsIndex:
    let index = self.languageServerDiagnosticsIndex[languageServerName]
    let diagnostics = self.diagnosticsPerLS[index].addr
    if diagnostics[].currentDiagnostics.len == 0:
      return
    diagnostics[].diagnosticsPerLine.clear()
    diagnostics[].currentDiagnostics.setLen 0
    diagnostics[].currentDiagnosticsAnchors.setLen 0

  self.updateDiagnosticEndPoints()

proc tabWidth*(self: TextDocument): int =
  return self.settings.tabWidth.get()

proc getCompletionSelectionAt*(self: TextDocument, cursor: Cursor): Selection =
  return self.applyMoveFallback("completion-selection", [cursor.toSelection], 1, [], nil)[0]

proc getNodeRange*(self: TextDocument, selection: Selection, parentIndex: int = 0, siblingIndex: int = 0): Option[Selection] =
  result = Selection.none
  let tree = self.tsTree
  if tree.isNil:
    return

  let rang = selection.tsRange
  var node = tree.root.descendantForRange rang

  for i in 0..<parentIndex:
    if node == tree.root:
      break
    node = node.parent

  for i in 0..<siblingIndex:
    if node.next.getSome(sibling):
      node = sibling
    else:
      break

  for i in siblingIndex..<0:
    if node.prev.getSome(sibling):
      node = sibling
    else:
      break

  result = node.getRange.toSelection.some

proc lastNonWhitespace*(str: string): int =
  result = str.high
  while result >= 0:
    if str[result] != ' ' and str[result] != '\t':
      break
    result -= 1

proc getIndentString*(self: TextDocument): string =
  getIndentString(self.settings.indent.get(), self.settings.tabWidth.get())

proc getIndentColumns*(self: TextDocument): int =
  case self.settings.indent.get()
  of Tabs: return 1
  of Spaces: return self.settings.tabWidth.get()

proc getIndentLevelForLine*(self: TextDocument, line: int, tabWidth: int): int =
  if line < 0 or line >= self.numLines:
    return 0

  let indentWidth = self.settings.tabWidth.get()

  var c = self.rope.cursorT(Point.init(line, 0))
  var indent = 0
  while not c.atEnd:
    case c.currentRune
    of '\t'.Rune:
      indent += tabWidthAt(indent, tabWidth)
    of ' '.Rune:
      indent += 1
    else:
      break
    c.seekNextRune()

  indent = indent div indentWidth
  return indent

proc traverse*(line, column: int, text: openArray[char]): (int, int) =
  var line = line
  var column = column
  for rune in text:
    if rune == '\n':
      inc line
      column = 0
    else:
      inc column

  return (line, column)

func charCategory(c: char): int =
  if c.isAlphaNumeric or c == '_': return 0
  if c in Whitespace: return 1
  return 2

proc getLanguageWordBoundary*(self: TextDocument, cursor: Cursor): Selection =
  if cursor.column == 0:
    return cursor.toSelection

  var c = self.rope.cursorT(cursor.toPoint)

  result = cursor.toSelection

  let identRunes {.cursor.} = self.settings.completionWordChars.get()
  while c.position.column > 0:
    c.seekPrevRune()
    if c.currentRune in identRunes:
      result.first.column = c.position.column.int
    else:
      break

  c = self.rope.cursorT(cursor.toPoint)
  while not c.atEnd and c.position.row.int == cursor.line:
    if c.currentRune in identRunes:
      c.seekNextRune()
      result.last.column = c.position.column.int
    else:
      break

proc findWordBoundary*(self: TextDocument, cursor: Cursor): Selection =
  # todo: use RopeCursor
  let line = self.getLine(cursor.line)
  result = cursor.toSelection
  if result.first.column == line.len:
    dec result.first.column
    dec result.last.column

  # Search to the left
  while result.first.column > 0 and result.first.column < line.len:
    let leftCategory = line.charAt(result.first.column - 1).charCategory
    let rightCategory = line.charAt(result.first.column).charCategory
    if leftCategory != rightCategory:
      break
    result.first.column -= 1

  # Search to the right
  if result.last.column < line.len:
    result.last.column += 1
  while result.last.column >= 0 and result.last.column < line.len:
    let leftCategory = line.charAt(result.last.column - 1).charCategory
    let rightCategory = line.charAt(result.last.column).charCategory
    if leftCategory != rightCategory:
      break
    result.last.column += 1

proc updateCursorAfterInsert*(self: TextDocument, location: Cursor, inserted: Selection): Cursor =
  result = location
  if result.line == inserted.first.line and result.column > inserted.first.column:
    # inserted text on same line before inlayHint
    result.column += inserted.last.column - inserted.first.column
    result.line += inserted.last.line - inserted.first.line
  elif result.line == inserted.first.line and result.column == inserted.first.column:
    # Inserted text at inlayHint location
    # Usually the inlay hint will be on a word boundary, so if it's not anymore then move the inlay hint
    # (this happens if you e.g. change the name of the variable by appending some text)
    # If it's still on a word boundary, then the new inlay hint will probably be at the same location so don't move it now
    let wordBoundary = self.findWordBoundary(result)
    if result != wordBoundary.first and result != wordBoundary.last:
      result.column += inserted.last.column - inserted.first.column
      result.line += inserted.last.line - inserted.first.line
  elif result.line > inserted.first.line:
    # inserted text on line before inlay hint
    result.line += inserted.last.line - inserted.first.line

proc updateCursorAfterDelete*(self: TextDocument, location: Cursor, deleted: Selection): Option[Cursor] =
  var res = location
  if deleted.first.line == deleted.last.line:
    if res.line == deleted.first.line and res.column >= deleted.last.column:
      res.column -= deleted.last.column - deleted.first.column
    elif res.line == deleted.first.line and res.column > deleted.first.column and res.column < deleted.last.column:
      return Cursor.none

  else:
    if res.line == deleted.first.line and res.column >= deleted.first.column:
      return Cursor.none
    if res.line > deleted.first.line and res.line < deleted.last.line:
      return Cursor.none
    if res.line == deleted.last.line and res.column <= deleted.last.column:
      return Cursor.none

    if res.line == deleted.last.line and res.column >= deleted.last.column:
      res.column -= deleted.last.column - deleted.first.column

    if res.line >= deleted.last.line:
      res.line -= deleted.last.line - deleted.first.line

  return res.some

proc addTreesitterChange(self: TextDocument, startByte: int, oldEndByte: int, newEndByte: int, startPoint: Point, oldEndPoint: Point, newEndPoint: Point) =
  self.treesitterComponent.syntaxMap.addEdit(TSInputEdit(
    startIndex: startByte,
    oldEndIndex: oldEndByte,
    newEndIndex: newEndByte,
    startPosition: TSPoint(row: startPoint.row.int, column: startPoint.column.int),
    oldEndPosition: TSPoint(row: oldEndPoint.row.int, column: oldEndPoint.column.int),
    newEndPosition: TSPoint(row: newEndPoint.row.int, column: newEndPoint.column.int),
  ), self.buffer.visibleText)

proc handlePatch(self: TextDocument, oldText: Rope, patch: Patch[uint32]) =
  var co = oldText.cursorT(Point)
  var cn = self.rope.cursorT(Point)

  var edits = newSeqOfCap[tuple[old, new: Selection]](patch.edits.len)
  var pointPatch = Patch[Point]()

  for edit in patch.edits:
    co.seekForward(edit.old.a.int)
    cn.seekForward(edit.new.a.int)

    let startPosOld = co.position
    let startPosNew = cn.position

    if edit.old.len > 0:
      co.seekForward(edit.old.b.int)

    if edit.new.len > 0:
      cn.seekForward(edit.new.b.int)

    let endPosOld = co.position
    let endPosNew = cn.position
    edits.add ((startPosOld, endPosOld).toSelection, (startPosNew, endPosNew).toSelection)
    pointPatch.edits.add initEdit(startPosOld...endPosOld, startPosNew...endPosNew)

    if not self.tsLanguage.isNil:
      self.addTreesitterChange(edit.new.a.int, edit.new.a.int + edit.old.len.int, edit.new.b.int, startPosOld, endPosOld, endPosNew)

  self.onEdit.invoke (self, edits)
  self.textComponent.onEdit.invoke (oldText, pointPatch)

proc updateDirtyAfterUndo(self: TextDocument) =
  if self.buffer.history.undoTree.nodes[self.buffer.history.undoTree.current].transaction.id == self.textComponent.savedVersion:
    self.lastSavedRevision = self.undoableRevision

proc undo*(self: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool, untilCheckpoint: string = ""): Option[seq[Selection]] =
  result = seq[Selection].none
  if self.readOnly:
    return

  discard self.buffer.endTransaction()
  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  var lastTransaction: TransactionId
  while true:
    let undoOp = self.buffer.undo()
    if undoOp.isNone:
      break
    self.onOperation.invoke (self, undoOp.get.op)
    lastTransaction = undoOp.get.transactionId
    if untilCheckpoint == "Y":
      if not hasMoreThanOneChild(self.buffer.history.undoTree, self.buffer.history.undoTree.current):
        continue
      else:
        break
    else:
      break

  self.undoSelections.withValue(lastTransaction, selections):
    result = selections[].some

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

  self.updateDirtyAfterUndo()

proc redo*(self: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool, untilCheckpoint: string = ""): Option[seq[Selection]] =
  result = seq[Selection].none
  if self.readOnly:
    return

  discard self.buffer.endTransaction()
  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  var lastTransaction: TransactionId
  while true:
    let redoOp = self.buffer.redo()
    if redoOp.isNone:
      break
    self.onOperation.invoke (self, redoOp.get.op)
    lastTransaction = redoOp.get.transactionId
    if untilCheckpoint == "Y":
      if hasMoreThanOneChild(self.buffer.history.undoTree, self.buffer.history.undoTree.current):
        break
      else:
        continue
    else:
      break


  self.redoSelections.withValue(lastTransaction, selections):
    result = selections[].some

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

  self.updateDirtyAfterUndo()

proc startTransaction*(self: TextDocument) =
  discard self.buffer.startTransaction()

proc endTransaction*(self: TextDocument) =
  discard self.buffer.endTransaction()

template withTransaction*(self: TextDocument, body: untyped): untyped =
  try:
    self.startTransaction()
    body
  finally:
    self.endTransaction()

proc undoToPreviousSibling*(self: TextDocument, redoUntilBranch: bool = false): Option[seq[Selection]] =
  result = seq[Selection].none
  if self.readOnly:
    return

  discard self.buffer.endTransaction()
  let tree = self.buffer.history.undoTree.addr
  if tree.current <= 0:
    return

  let (targetSiblingIdx, undoCount) = findPreviousSiblingRecursive(tree[], tree.current)
  if targetSiblingIdx == -1:
    return

  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  for i in 0..<undoCount:
    let undoOp = self.buffer.undo()
    if undoOp.isSome:
      self.onOperation.invoke (self, undoOp.get.op)

  var lastRedoTransaction = TransactionId.default
  let redoNode = tree.nodes[targetSiblingIdx]
  var redoOp = self.buffer.redo(redoNode.transaction.id.some)
  if redoOp.isSome:
    lastRedoTransaction = redoOp.get.transactionId
    self.onOperation.invoke (self, redoOp.get.op)

  if redoUntilBranch:
    while tree.current > 0:
      if hasMoreThanOneChild(tree[], tree.current):
        break
      redoOp = self.buffer.redo()
      if redoOp.isSome:
        lastRedoTransaction = redoOp.get.transactionId
        self.onOperation.invoke (self, redoOp.get.op)
      else:
        break

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)
  self.redoSelections.withValue(lastRedoTransaction, selections):
    result = selections[].some

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

  self.updateDirtyAfterUndo()

proc undoToNextSibling*(self: TextDocument, redoUntilBranch: bool = false): Option[seq[Selection]] =
  result = seq[Selection].none
  if self.readOnly:
    return

  discard self.buffer.endTransaction()
  let tree = self.buffer.history.undoTree.addr
  if tree.current <= 0:
    return

  let (targetSiblingIdx, undoCount) = findNextSiblingRecursive(tree[], tree.current)
  if targetSiblingIdx == -1:
    return

  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  for i in 0..<undoCount:
    let undoOp = self.buffer.undo()
    if undoOp.isSome:
      self.onOperation.invoke (self, undoOp.get.op)

  var lastRedoTransaction = TransactionId.default
  let redoNode = tree.nodes[targetSiblingIdx]
  var redoOp = self.buffer.redo(redoNode.transaction.id.some)
  if redoOp.isSome:
    lastRedoTransaction = redoOp.get.transactionId
    self.onOperation.invoke (self, redoOp.get.op)

  if redoUntilBranch:
    while tree.current > 0:
      if hasMoreThanOneChild(tree[], tree.current):
        break
      redoOp = self.buffer.redo()
      if redoOp.isSome:
        lastRedoTransaction = redoOp.get.transactionId
        self.onOperation.invoke (self, redoOp.get.op)
      else:
        break

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)
  self.redoSelections.withValue(lastRedoTransaction, selections):
    result = selections[].some

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

  self.updateDirtyAfterUndo()

proc switchUndoBranch*(self: TextDocument, targetNode: int32): Option[seq[Selection]] =
  result = seq[Selection].none
  if self.readOnly:
    return

  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  var res = self.buffer.switchUndoBranch(targetNode)
  if res.isNone:
    return
  for op in res.get.ops.mitems:
    self.onOperation.invoke (self, op)

  if res.get.wasRedo:
    self.redoSelections.withValue(res.get.lastTransaction, selections):
      result = selections[].some

  else:
    self.undoSelections.withValue(res.get.lastTransaction, selections):
      result = selections[].some

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

  self.updateDirtyAfterUndo()

proc addNextCheckpoint*(self: TextDocument, checkpoint: string) =
  self.nextCheckpoints.incl checkpoint

proc isLineCommented*(self: TextDocument, line: int): bool =
  let lineComment = self.settings.lineComment.get()
  if lineComment.isNone:
    return false
  return self.rope.lineStartsWith(line, lineComment.get, ignoreWhitespace = true)

proc getLineCommentRange*(self: TextDocument, line: int): Selection =
  let lineComment = self.settings.lineComment.get()
  if line > self.numLines - 1 or lineComment.isNone:
    return (line, 0).toSelection

  # todo: use RopeCursor
  let prefix = lineComment.get
  let index = self.getLine(line).find(prefix)
  if index == -1:
    return (line, 0).toSelection

  var endIndex = index + prefix.len
  # todo: don't use getLine
  if endIndex < self.lineLength(line) and self.rope.charAt(Point.init(line, endIndex)) in Whitespace:
    endIndex += 1

  return ((line, index), (line, endIndex))

proc toggleLineComment*(self: TextDocument, selections: Selections): seq[Selection] =
  result = selections

  let lineComment = self.settings.lineComment.get()
  if lineComment.isNone:
    return

  let mergedSelections = self.clampAndMergeSelections(selections).mergeLines

  var allCommented = true
  for s in mergedSelections:
    for l in s.first.line..s.last.line:
      if not self.getLine(l).isEmptyOrWhitespace:
        allCommented = allCommented and self.isLineCommented(l)

  let comment = not allCommented

  var insertSelections: Selections
  for s in mergedSelections:
    var minIndent = int.high
    for l in s.first.line..s.last.line:
      if not self.getLine(l).isEmptyOrWhitespace:
        minIndent = min(minIndent, self.rope.indentBytes(l))

    for l in s.first.line..s.last.line:
      if not self.getLine(l).isEmptyOrWhitespace:
        if comment:
          insertSelections.add (l, minIndent).toSelection
        else:
          insertSelections.add self.getLineCommentRange(l)

  if comment:
    let prefix = lineComment.get & " "
    discard self.edit(insertSelections, selections, [prefix])
  else:
    discard self.edit(insertSelections, selections, [""])

proc trimTrailingWhitespace*(self: TextDocument) =
  var selections: seq[Selection]
  for i in 0..self.numLines - 1:
    # todo: don't use getLine
    let index = ($self.getLine(i)).lastNonWhitespace
    if index == self.lineLength(i) - 1:
      continue
    selections.add ((i, index + 1), (i, self.lineLength(i)))

  if selections.len > 0:
    discard self.edit(selections, selections, [""])

func isInitialized*(self: TextDocument): bool = self.isInitialized

import layout/layout

proc addFileVcsAsync*(self: TextDocument, prompt: bool = true) {.async.} =
  let path = self.localizedPath
  let vcsService = self.services.getService(VCSService).get
  let vcs = vcsService.getVcsForFile(path).getOr:
    return

  if prompt:
    let layoutService = self.services.getService(LayoutService).get
    let text = await layoutService.prompt(@["Yes", "No"], "VCS: Add " & path)
    if not self.isInitialized:
      return
    if text.isSome and text.get != "Yes":
      return

  let res = await vcs.addFile(path)
  if not self.isInitialized:
    return

  log lvlInfo, &"Add result: {res}"
