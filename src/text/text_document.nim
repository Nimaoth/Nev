import std/[os, strutils, sequtils, sugar, options, json, strformat, tables, uri, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import patty, bumpy
import misc/[id, util, event, custom_logger, custom_async, custom_unicode, myjsonutils, regex, array_set, timer, response, rope_utils, async_process, jsonex]
import language/[languages, language_server_base]
import workspaces/[workspace]
import document, document_editor, custom_treesitter, indent, config_provider, service, vfs, vfs_service, language_server_list
import syntax_map
import pkg/[chroma, results]

import diff

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

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
  ## Override the ripgrep language name. By default the documents language id is used.
  declare rgLanguage, Option[string], nil

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

declareSettings TrimTrailingWhitespaceSettings, "":
  ## If true trailing whitespace is deleted when saving files.
  declare enabled, bool, true

  ## Don't trim trailing whitespace when filesize is above this limit.
  declare maxSize, int, 1000000

declareSettings FormatSettings, "":
  ## If true run the formatter when saving.
  declare onSave, bool, false

  ## Command to run. First entry is path to the formatter program, subsequent entries are passed as arguments to the formatter.
  declare command, seq[string], newSeq[string]()

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

declareSettingsTemplate TreesitterSettings, "text.treesitter":
  ## Enable parsing code into ASTs using treesitter. Also requires a treesitter parser for a specific language.
  declare enable, bool, true

  ## Override the path to the treesitter parser (.dll/.so/.wasm). By default
  declare path, Option[string], nil

  ## Override the language name used for choosing the treesitter parser. If not set then the documents language id is used.
  declare language, Option[string], nil

  ## Path relative to the repository root where queries are located. If not set then the editor will look for the queries.
  declare queries, Option[string], nil

  ## Path relative to the repository root where queries are located. If not set then the editor will look for the queries.
  declare repository, Option[string], nil

declareSettings TextSettings, "text":
  ##
  use trimTrailingWhitespace, TrimTrailingWhitespaceSettings

  ## Configure search regexes.
  use searchRegexes, SearchRegexSettings

  ## Settings for code formatting.
  use formatter, FormatSettings

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

type

  TextDocumentChange = object
    startByte: int
    oldEndByte: int
    newEndByte: int
    startPoint: Point
    oldEndPoint: Point
    newEndPoint: Point

  TextDocument* = ref object of Document
    isInitialized: bool
    buffer*: Buffer
    mLanguageId: string
    services: Services
    workspace: Workspace

    nextLineIdCounter: int32 = 0

    isLoadingAsync*: bool = false
    isParsingAsync*: bool = false

    singleLine*: bool = false
    readOnly*: bool = false
    staged*: bool = false

    onRequestRerender*: Event[void]
    onPreLoaded*: Event[TextDocument]
    onLoaded*: Event[tuple[document: TextDocument, changed: seq[Selection]]]
    onSaved*: Event[void]
    textChanged*: Event[TextDocument]
    onEdit*: Event[tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]]
    onOperation*: Event[tuple[document: TextDocument, op: Operation]]
    onBufferChanged*: Event[tuple[document: TextDocument]]
    onLanguageServerAttached*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]
    onLanguageServerDetached*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]
    onDiagnostics*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]
    onLanguageChanged*: Event[tuple[document: TextDocument]]

    undoSelections*: Table[Lamport, Selections]
    redoSelections*: Table[Lamport, Selections]

    changes: seq[TextDocumentChange]
    changesAsync: seq[TextDocumentChange]

    configService: ConfigService
    config*: ConfigStore
    createLanguageServer*: bool = true
    completionTriggerCharacters*: set[char] = {}

    nextCheckpoints: seq[string]

    currentContentFailedToParse: bool
    tsLanguage: TSLanguage
    currentTree: TSTree
    highlightQuery*: TSQuery
    errorQuery: TSQuery

    languageServerList*: LanguageServerList

    diagnosticsPerLS*: seq[DiagnosticsData] ## Diagnostics per language server
    languageServerDiagnosticsIndex*: Table[string, int] ## Diagnostics per language server
    diagnosticEndPoints*: seq[DiagnosticEndPoint]
    onDiagnosticsHandles: Table[string, (LanguageServer, Id)]
    diagnosticSnapshots: seq[BufferSnapshot] # todo: reset at appropriate times

    treesitterParserCursor: RopeCursor ## Used during treesitter parsing to avoid constant seeking

    checkpoints: Table[TransactionId, seq[string]]

    settings*: TextSettings
    fileWatchHandle: VFSWatchHandle

  DiagnosticsData = object
    languageServer*: LanguageServer
    currentDiagnostics*: seq[Diagnostic]
    currentDiagnosticsAnchors: seq[Range[Anchor]]
    diagnosticsPerLine*: Table[int, seq[int]]
    lastDiagnosticVersion: Global # todo: reset at appropriate times
    lastDiagnosticAnchorResolve: Global # todo: reset at appropriate times

var allTextDocuments*: seq[TextDocument] = @[]

proc reloadTreesitterLanguage*(self: TextDocument)
proc clearDiagnostics*(self: TextDocument, languageServerName: string = "")
proc numLines*(self: TextDocument): int {.noSideEffect.}
proc handlePatch(self: TextDocument, oldText: Rope, patch: Patch[uint32])
proc resolveDiagnosticAnchors*(self: TextDocument)
proc recordSnapshotForDiagnostics(self: TextDocument)
proc addTreesitterChange(self: TextDocument, startByte: int, oldEndByte: int, newEndByte: int, startPoint: Point, oldEndPoint: Point, newEndPoint: Point)
proc format*(self: TextDocument, runOnTempFile: bool): Future[void] {.async.}
proc enableAutoReload*(self: TextDocument, enabled: bool)
proc addLanguageServer*(self: TextDocument, languageServer: LanguageServer): bool
proc removeLanguageServer*(self: TextDocument, languageServer: LanguageServer): bool

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
    result.add &"Changes: {self.changes.len}\n"
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

proc applyTreesitterChanges(self: TextDocument, tree: TSTree, changes: var seq[TextDocumentChange]) =
  if tree.isNotNil:
    for change in changes:
      let edit = (block:
        match change:
          Replace(startByte, oldEndByte, newEndByte, startPoint, oldEndPoint, newEndPoint):
            TSInputEdit(
              startIndex: startByte,
              oldEndIndex: oldEndByte,
              newEndIndex: newEndByte,
              startPosition: TSPoint(row: startPoint.row.int, column: startPoint.column.int),
              oldEndPosition: TSPoint(row: oldEndPoint.row.int, column: oldEndPoint.column.int),
              newEndPosition: TSPoint(row: newEndPoint.row.int, column: newEndPoint.column.int),
            )
      )

      discard tree.edit(edit)

  changes.setLen 0

proc parseTreesitterThread(parser: ptr TSParser, oldTree: TSTree, text: sink Rope): TSTree =
  var ropeCursor = text.cursor()
  let newTree = parser[].parseCallback(oldTree):
    proc(byteIndex: int, cursor: Cursor): (ptr char, int) =
      if byteIndex < ropeCursor.offset:
        ropeCursor.resetCursor()

      assert not ropeCursor.rope.tree.isNil
      ropeCursor.seekForward(byteIndex)
      if ropeCursor.chunk.getSome(chunk):
        let byteIndexRel = byteIndex - ropeCursor.chunkStartPos
        return (chunk.chars[byteIndexRel].addr, chunk.chars.len - byteIndexRel)

      return (nil, 0)

  return newTree

proc reparseTreesitterAsync*(self: TextDocument) {.async.} =
  self.isParsingAsync = true
  defer:
    self.isParsingAsync = false

  if self.tsLanguage.isNotNil:
    withParser parser:
      self.applyTreesitterChanges(self.currentTree, self.changes)
      self.changesAsync.setLen(0)

      while true:
        if self.currentContentFailedToParse:
          # We already tried to parse the current content and it failed, don't try again
          return

        if not parser.setLanguage(self.tsLanguage):
          return

        var oldLanguage = self.tsLanguage
        let oldBufferId = self.buffer.remoteId
        let oldVersion = self.buffer.version
        let oldTree: TSTree = if self.currentTree.isNotNil:
          self.currentTree.clone()
        else:
          TSTree()

        let flowVar = spawn parseTreesitterThread(parser.addr, oldTree, self.rope.clone())

        while not flowVar.isReady:
          await sleepAsync(1.milliseconds)

        if not self.isInitialized:
          return

        let newTree = ^flowVar

        oldTree.delete()
        self.currentTree.delete()

        if self.buffer.remoteId != oldBufferId or self.tsLanguage != oldLanguage:
          newTree.delete()
          self.changes.setLen(0)
          self.changesAsync.setLen(0)
          continue

        self.currentTree = newTree
        self.currentContentFailedToParse = self.currentTree.isNil
        self.notifyRequestRerender()

        if self.buffer.version == oldVersion:
          assert self.changes.len == 0
          assert self.changesAsync.len == 0
          return

        self.currentContentFailedToParse = false
        self.applyTreesitterChanges(self.currentTree, self.changesAsync)
        self.changes.setLen(0)

proc reparseTreesitter*(self: TextDocument) =
  if self.isParsingAsync:
    return

  asyncSpawn self.reparseTreesitterAsync()

proc tsTree*(self: TextDocument): TsTree =
  if self.changes.len > 0 or self.currentTree.isNil:
    self.applyTreesitterChanges(self.currentTree, self.changes)
    self.reparseTreesitter()
  return self.currentTree

proc languageId*(self: TextDocument): string =
  self.mLanguageId

proc `languageId=`*(self: TextDocument, languageId: string) =
  if self.mLanguageId != languageId:
    self.mLanguageId = languageId
    self.config.setParent(self.configService.getLanguageStore(self.mLanguageId))
    if not self.requiresLoad:
      self.reloadTreesitterLanguage()
    self.onLanguageChanged.invoke (self,)

func contentString*(self: TextDocument): string =
  if self.rope.tree.isNil:
    # todo: this shouldn't be happening
    return ""
  return $self.rope

var nextBufferId = 1.BufferId
proc getNextBufferId(): BufferId =
  result = nextBufferId
  inc nextBufferId

proc `content=`*(self: TextDocument, value: sink Rope) =
  self.revision.inc
  self.undoableRevision.inc

  self.buffer = initBuffer(self.buffer.timestamp.replicaId, content = value, remoteId = getNextBufferId())

  self.currentContentFailedToParse = false
  self.currentTree.delete()
  self.changes.setLen(0)
  self.changesAsync.setLen(0)

  self.onBufferChanged.invoke (self,)

  self.clearDiagnostics()
  self.notifyTextChanged()

proc `content=`*(self: TextDocument, value: sink string) =
  self.revision.inc
  self.undoableRevision.inc

  let invalidUtf8Index = value.validateUtf8
  if invalidUtf8Index >= 0:
    log lvlWarn, &"[content=] Trying to set content with invalid utf-8 string (invalid byte at {invalidUtf8Index})"
    self.buffer = initBuffer(content = &"Invalid utf-8 byte at {invalidUtf8Index}", remoteId = getNextBufferId())

  else:
    var index = 0
    const utf8_bom = "\xEF\xBB\xBF"
    if value.len >= 3 and value.startsWith(utf8_bom):
      log lvlInfo, &"[content=] Skipping utf8 bom"
      index = 3

    self.buffer = initBuffer(content = value[index..^1], remoteId = getNextBufferId())

  self.currentContentFailedToParse = false
  self.currentTree.delete()
  self.changes.setLen(0)
  self.changesAsync.setLen(0)

  self.onBufferChanged.invoke (self,)

  self.clearDiagnostics()
  self.notifyTextChanged()

proc edit*[S](self: TextDocument, selections: openArray[Selection], oldSelections: openArray[Selection], texts: openArray[S], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =

  let selections = self.clampAndMergeSelections(selections).map (s) => s.normalized

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
      self.addTreesitterChange(oldByteRange[0], oldByteRange[1], newByteRangeEnd, oldPointRange[0], oldPointRange[1], newPointRangeEnd)

    pointDiff = newPointRangeEnd - selection.last.toPoint
    byteDiff = newByteRangeEnd - endByte

  newSelections.sort((a, b) => cmp(a[0], b[0]))
  result = newSelections.mapIt(it[1])
  assert result.len > 0

  self.revision.inc
  self.undoableRevision.inc

  let op = self.buffer.edit(ranges)
  self.recordSnapshotForDiagnostics()

  let last {.cursor.} = self.buffer.history.undoStack[^1]
  if self.nextCheckpoints.len > 0:
    self.checkpoints[last.transaction.id] = self.nextCheckpoints
  self.nextCheckpoints.setLen 0

  self.onOperation.invoke (self, op)
  self.onEdit.invoke (self, edits)

  if oldSelections.len > 0:
    self.undoSelections[op.timestamp] = @oldSelections
  self.redoSelections[op.timestamp] = result.mapIt(it.last.toSelection)
  self.currentContentFailedToParse = false

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

proc rebuildBuffer*(self: TextDocument, replicaId: ReplicaId, bufferId: BufferId, content: string) =
  self.content = content
  self.buffer = initBuffer(replicaId, content, bufferId)

  self.notifyRequestRerender()

proc recordSnapshotForDiagnostics(self: TextDocument) =
  let diagnosticHistoryMaxLength = self.settings.diagnostics.snapshotHistory.get()
  self.diagnosticSnapshots.add(self.buffer.snapshot.clone())
  while self.diagnosticSnapshots.len > diagnosticHistoryMaxLength:
    self.diagnosticSnapshots.removeShift(0)

proc applyRemoteChanges*(self: TextDocument, ops: sink seq[Operation]) =
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
  if cursor.line < 0 or cursor.line > self.numLines - 1:
    return (0, 0)

  return (cursor.line, self.rope.byteOffsetInLine(cursor.line, cursor.column))

proc runeSelectionToSelection*(self: TextDocument, cursor: RuneSelection): Selection =
  return (self.runeCursorToCursor(cursor.first), self.runeCursorToCursor(cursor.last))

proc lspRangeToSelection*(self: TextDocument, r: lsp_types.Range): Selection =
  let runeSelection = (
    (r.start.line, r.start.character.RuneIndex),
    (r.`end`.line, r.`end`.character.RuneIndex))
  return self.runeSelectionToSelection(runeSelection)

proc getErrorNodesInRange*(self: TextDocument, selection: Selection): seq[Selection] =
  if self.errorQuery.isNil or self.tsTree.isNil:
    return

  for match in self.errorQuery.matches(self.tsTree.root, tsRange(tsPoint(selection.first.line, 0), tsPoint(selection.last.line, 0))):
    for capture in match.captures:
      result.add capture.node.getRange.toSelection

proc loadTreesitterLanguage(self: TextDocument): Future[void] {.async.} =
  # logScope lvlInfo, &"loadTreesitterLanguage '{self.filename}'"

  self.highlightQuery = nil
  self.errorQuery = nil
  self.currentContentFailedToParse = false
  self.tsLanguage = nil
  self.currentTree.delete()

  if self.languageId == "":
    return

  let prevLanguageId = self.languageId
  let pathOverride = self.settings.treesitter.path.get()
  let treesitterLanguageName = self.settings.treesitter.language.get().get(self.languageId)
  var language = await getTreesitterLanguage(self.vfs, treesitterLanguageName, pathOverride)

  if prevLanguageId != self.languageId:
    return

  if language.isNone:
    return

  # log lvlInfo, &"loadTreesitterLanguage {prevLanguageId}: Loaded language, apply"
  self.currentContentFailedToParse = false
  self.tsLanguage = language.get
  self.currentTree.delete()

  # todo: this awaits, check if still current request afterwards
  # todo: allow specifying queries in home and workspace config
  let highlightQueryPath = &"app://languages/{treesitterLanguageName}/queries/highlights.scm"
  if language.get.queryFile(self.vfs, "highlight", highlightQueryPath).await.getSome(query):
    if prevLanguageId != self.languageId:
      return

    self.highlightQuery = query

  if not self.isInitialized:
    return

  let errorQueryPath = &"app://languages/{treesitterLanguageName}/queries/errors.scm"
  if language.get.queryFile(self.vfs, "error", errorQueryPath, cacheOnFail = false).await.getSome(query):
    if prevLanguageId != self.languageId:
      return
    self.errorQuery = query
  elif language.get.query("error", "(ERROR) @error").await.getSome(query):
    self.errorQuery = query

  if not self.isInitialized:
    return

  if prevLanguageId != self.languageId:
    return

  self.notifyRequestRerender()

proc reloadTreesitterLanguage*(self: TextDocument) =
  asyncSpawn self.loadTreesitterLanguage()

proc newTextDocument*(
    services: Services,
    filename: string = "",
    content: string = "",
    app: bool = false,
    language: Option[string] = string.none,
    languageServer: Option[LanguageServer] = LanguageServer.none,
    load: bool = false,
    createLanguageServer: bool = true): TextDocument =

  # log lvlInfo, &"Creating new text document '{filename}', (lang: {language}, app: {app}, ls: {createLanguageServer})"
  new(result)

  {.gcsafe.}:
    allTextDocuments.add result

  var self = result
  self.id = newId().DocumentId
  self.isInitialized = true
  self.currentTree = TSTree()
  self.appFile = app
  self.workspace = services.getService(Workspace).get
  self.services = services
  self.configService = services.getService(ConfigService).get
  self.vfs = services.getService(VFSService).get.vfs
  self.createLanguageServer = createLanguageServer
  self.buffer = initBuffer(content = "", remoteId = getNextBufferId())
  self.filename = self.vfs.normalize(filename)
  self.isBackedByFile = load
  self.requiresLoad = load

  self.config = self.configService.addStore("document/" & self.filename, &"settings://document/{self.filename}")
  self.settings = TextSettings.new(self.config)
  self.languageServerList = newLanguageServerList(self.config)

  if language.getSome(language):
    self.languageId = language
  else:
    getLanguageForFile(self.config, filename).applyIt:
      self.languageId = it

  self.content = content
  if languageServer.isSome:
    discard self.addLanguageServer(languageServer.get)

method deinit*(self: TextDocument) =
  # logScope lvlInfo, fmt"[deinit] Destroying text document '{self.filename}'"
  if not self.isInitialized:
    return

  self.fileWatchHandle.unwatch()

  if self.currentTree.isNotNil:
    self.currentTree.delete()
  self.highlightQuery = nil
  self.errorQuery = nil

  if self.languageServerList.isNotNil:
    self.languageServerList.disconnect(self)

  for (ls, id) in self.onDiagnosticsHandles.values:
    ls.onDiagnostics.unsubscribe(id)

  {.gcsafe.}:
    let i = allTextDocuments.find(self)
    if i >= 0:
      allTextDocuments.removeSwap(i)

  self[] = default(typeof(self[]))

method `$`*(self: TextDocument): string =
  return self.filename

proc saveAsync*(self: TextDocument) {.async.} =
  try:
    log lvlInfo, &"[save] '{self.filename}'"

    if self.filename.len == 0:
      log lvlError, &"save: Missing filename"
      return

    if self.staged:
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

    await self.vfs.write(self.filename, self.rope.slice())

    if not self.isInitialized:
      return

    self.isBackedByFile = true
    self.lastSavedRevision = self.undoableRevision
    self.onSaved.invoke()

    if self.settings.formatter.onSave.get():
      asyncSpawn self.format(runOnTempFile = false)
  except IOError as e:
    log lvlError, &"Failed to save file '{self.filename}': {e.msg}"

method save*(self: TextDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: self.vfs.normalize(filename) else: self.filename

  if self.filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  if self.staged:
    return

  self.appFile = app

  asyncSpawn self.saveAsync()

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
      minIndent = min(minIndent, self.rope.indentBytes(linePos.row.int))
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

        when defined(appCheckDiffReload):
          if $self.rope != $rope:
            log lvlError, &"Failed diff: {self.rope.len} != {rope.len}: {selections}, {texts}"
            self.replaceAll(rope.move)
            return @[((0, 0), (self.rope.endPoint.toCursor))]

        return

    except AsyncTimeoutError:
      log lvlDebug, &"Timeout after {t.elapsed.ms} ms"
      self.replaceAll(rope.move)

  else:
    self.replaceAll(rope.move)

  return @[((0, 0), (self.rope.endPoint.toCursor))]

proc loadAsync*(self: TextDocument, isReload: bool): Future[void] {.async.} =
  logScope lvlInfo, &"loadAsync '{self.filename}', reload = {isReload}"

  self.isBackedByFile = true
  self.isLoadingAsync = true
  self.readOnly = true

  var rope: Rope = Rope.new()
  try:
    await self.vfs.readRope(self.filename, rope.addr)

    if not self.isInitialized:
      return
  except IOError as e:
    log lvlError, &"[loadAsync] Failed to load file {self.filename}: {e.msg}\n{e.getStackTrace()}"
    return

  self.onPreLoaded.invoke self

  let changedRegions = if isReload:
    await self.reloadFromRope(rope.clone())
  else:
    self.content = rope.clone()
    @[((0, 0), (self.rope.endPoint.toCursor))]

  if self.settings.autoReload.get():
    self.enableAutoReload(true)
  else:
    self.fileWatchHandle.unwatch()

  if self.vfs.getFileAttributes(self.filename).await.mapIt(it.writable).get(true):
    self.readOnly = false

  self.autoDetectIndentStyle()

  self.lastSavedRevision = self.undoableRevision
  self.isLoadingAsync = false
  self.onLoaded.invoke (self, changedRegions)

proc setReadOnly*(self: TextDocument, readOnly: bool) =
  ## Sets the interal readOnly flag, but doesn't not changed permission of the underlying file
  self.readOnly = readOnly

proc enableAutoReload*(self: TextDocument, enabled: bool) =
  self.settings.autoReload.set(enabled)
  if enabled and (not self.fileWatchHandle.isBound or self.fileWatchHandle.path != self.filename):
    self.fileWatchHandle.unwatch()
    self.fileWatchHandle = self.vfs.watch(self.filename, proc(events: seq[PathEvent]) =
      if not self.isInitialized or not self.settings.autoReload.get():
        return
      let isDirty = self.lastSavedRevision != self.revision
      if isDirty:
        return
      for e in events:
        case e.action
        of Modify:
          asyncSpawn self.loadAsync(true)
          break

        else:
          discard
    )
    self.fileWatchHandle.path = self.filename

  elif not enabled:
    self.fileWatchHandle.unwatch()

proc setFileReadOnlyAsync*(self: TextDocument, readOnly: bool): Future[bool] {.async.} =
  ## Tries to set the underlying file permissions
  try:
    await self.vfs.setFileAttributes(self.filename, FileAttributes(writable: not readOnly, readable: true))
    self.readOnly = readOnly
    return true
  except IOError as e:
    log lvlError, &"Failed to change file permissions of '{self.filename}': {e.msg}"
    return false

proc setFileAndContent*[S: string | Rope](self: TextDocument, filename: string, content: sink S) =
  let filename = if filename.len > 0: self.vfs.normalize(filename) else: self.filename
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

method load*(self: TextDocument, filename: string = "") =
  let filename = if filename.len > 0: self.vfs.normalize(filename) else: self.filename
  if filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  let isReload = self.isBackedByFile and filename == self.filename and not self.requiresLoad
  self.filename = filename
  self.isBackedByFile = true

  asyncSpawn self.loadAsync(isReload)

proc format*(self: TextDocument, runOnTempFile: bool): Future[void] {.async.} =
  try:
    let command = self.settings.formatter.command.get()
    if command.len == 0:
      return

    let formatterPath = command[0]
    let formatterArgs = command[1..^1]

    log lvlInfo, &"Format document '{self.filename}' with '{formatterPath} {formatterArgs}'"

    if runOnTempFile:
      let ext = self.filename.splitFile.ext
      let tempFile = self.vfs.genTempPath(prefix = "format/", suffix = ext)
      try:
        var rope = self.rope.clone()
        await self.vfs.write(tempFile, self.rope)
      except IOError as e:
        log lvlError, &"[format] Failed to write file {tempFile}: {e.msg}\n{e.getStackTrace()}"
        return

      defer:
        asyncSpawn asyncDiscard self.vfs.delete(tempFile)

      discard await runProcessAsync(formatterPath, formatterArgs & @[self.vfs.localize(tempFile)])

      var rope: Rope = Rope.new()
      try:
        await self.vfs.readRope(tempFile, rope.addr)
      except IOError as e:
        log lvlError, &"[format] Failed to load file {tempFile}: {e.msg}\n{e.getStackTrace()}"
        return

      discard await self.reloadFromRope(rope.clone())

    else:
      discard await runProcessAsync(formatterPath, formatterArgs & @[self.localizedPath])
      await self.loadAsync(isReload = true)

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
      let selection = self.runeSelectionToSelection(runeSelection)

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
  # log lvlInfo, &"Attach language server '{languageServer.name}' to '{self.filename}'"
  if not self.languageServerList.addLanguageServer(languageServer):
    return false
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

  return true

proc removeLanguageServer*(self: TextDocument, languageServer: LanguageServer): bool =
  if languageServer.name in self.onDiagnosticsHandles:
    languageServer.onDiagnostics.unsubscribe(self.onDiagnosticsHandles[languageServer.name][1])
    self.onDiagnosticsHandles.del(languageServer.name)

  if self.languageServerList.removeLanguageServer(languageServer):
    log lvlWarn, &"Detach language server '{languageServer.name}' from '{self.filename}'"
    self.onLanguageServerDetached.invoke (self, languageServer)
    return true
  return false

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
  if cursor.column == 0:
    return cursor.toSelection

  var c = self.rope.cursorT(cursor.toPoint)

  let identRunes {.cursor.} = self.settings.completionWordChars.get()
  var column = c.position.column
  while c.position.column > 0:
    c.seekPrevRune()
    if c.currentRune in identRunes:
      column = c.position.column
    else:
      break

  result = ((cursor.line, column.int), cursor)

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
  self.changes.add(TextDocumentChange(startByte: startByte, oldEndByte: oldEndByte, newEndByte: newEndByte, startPoint: startPoint, oldEndPoint: oldEndPoint, newEndPoint: newEndPoint))
  self.changesAsync.add(TextDocumentChange(startByte: startByte, oldEndByte: oldEndByte, newEndByte: newEndByte, startPoint: startPoint, oldEndPoint: oldEndPoint, newEndPoint: newEndPoint))

proc handlePatch(self: TextDocument, oldText: Rope, patch: Patch[uint32]) =
  var co = oldText.cursorT(Point)
  var cn = self.rope.cursorT(Point)

  var edits = newSeqOfCap[tuple[old, new: Selection]](patch.edits.len)

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

    if not self.tsLanguage.isNil:
      self.addTreesitterChange(edit.new.a.int, edit.new.a.int + edit.old.len.int, edit.new.b.int, startPosOld, endPosOld, endPosNew)

  self.onEdit.invoke (self, edits)

proc undo*(self: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool, untilCheckpoint: string = ""): Option[seq[Selection]] =
  result = seq[Selection].none

  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  var lastUndo: UndoOperation
  while self.buffer.undo().getSome(undo):
    self.onOperation.invoke (self, undo.op)
    lastUndo = undo.op.undo
    if untilCheckpoint.len == 0 or (undo.transactionId in self.checkpoints and
        (untilCheckpoint in self.checkpoints[undo.transactionId] or
        "" in self.checkpoints[undo.transactionId])):
      break

  for editId in lastUndo.counts.keys:
    self.undoSelections.withValue(editId, selections):
      result = selections[].some
      break

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

proc redo*(self: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool, untilCheckpoint: string = ""): Option[seq[Selection]] =
  result = seq[Selection].none

  let oldText = self.buffer.snapshot().visibleText.clone()
  let numPatchesBefore = self.buffer.patches.len

  var lastRedo: UndoOperation
  while self.buffer.redo().getSome(redo):
    self.onOperation.invoke (self, redo.op)
    lastRedo = redo.op.undo
    if untilCheckpoint.len == 0 or self.buffer.history.redoStack.len == 0:
      break

    let nextRedo {.cursor.} = self.buffer.history.redoStack[^1]
    if nextRedo.transaction.id in self.checkpoints and
        (untilCheckpoint in self.checkpoints[nextRedo.transaction.id] or
        "" in self.checkpoints[nextRedo.transaction.id]):
      break

  for editId in lastRedo.counts.keys:
    self.redoSelections.withValue(editId, selections):
      result = selections[].some
      break

  self.recordSnapshotForDiagnostics()

  var patch = Patch[uint32]()
  for i in numPatchesBefore..self.buffer.patches.high:
    patch = patch.compose(self.buffer.patches[i].patch.edits)

  self.handlePatch(oldText, patch)

  self.revision.inc
  self.undoableRevision.inc
  self.notifyTextChanged()

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
