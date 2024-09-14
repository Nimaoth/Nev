import std/[os, strutils, sequtils, sugar, options, json, strformat, tables, uri, times, enumerate]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import patty, bumpy
import misc/[id, util, event, custom_logger, custom_async, custom_unicode, myjsonutils, regex, array_set, timer, response]
import platform/[filesystem]
import language/[languages, language_server_base]
import workspaces/[workspace]
import document, document_editor, custom_treesitter, indent, text_language_config, config_provider, theme
import pkg/chroma

import nimsumtree/[buffer, clock, static_array, rope]
from nimsumtree/sumtree as st import summaryType, itemSummary, Bias

from language/lsp_types as lsp_types import nil

export document, document_editor, id

logCategory "text-document"

type
  UndoOpKind = enum
    Delete
    Insert
    Nested
  UndoOp = ref object
    oldSelection: seq[Selection]
    checkpoints: seq[string]
    revision: int
    case kind: UndoOpKind
    of Delete:
      selection: Selection
    of Insert:
      cursor: Cursor
      text: string
    of Nested:
      children: seq[UndoOp]

proc `$`*(op: UndoOp): string =
  result = fmt"{{{op.kind} (old: {op.oldSelection}, checkpoints: {op.checkpoints})"
  if op.kind == Delete: result.add fmt", selections = {op.selection}}}"
  if op.kind == Insert: result.add fmt", selections = {op.cursor}, text: '{op.text}'}}"
  if op.kind == Nested: result.add fmt", {op.children}}}"

type StyledText* = object
  text*: string
  scope*: string
  scopeC*: cstring
  priority*: int
  bounds*: Rect
  opacity*: Option[float]
  joinNext*: bool
  textRange*: Option[tuple[startOffset: int, endOffset: int, startIndex: RuneIndex, endIndex: RuneIndex]]
  visualRange*: Option[tuple[startColumn: int, endColumn: int, subLine: int]]
  underline*: bool
  underlineColor*: Color
  inlayContainCursor*: bool
  scopeIsToken*: bool = true
  canWrap*: bool = true
  modifyCursorAtEndOfLine*: bool = false ## If true and the cursor is at the end of the line
                                         ## then the cursor will be behind the part.

type StyledLine* = ref object
  index*: int
  parts*: seq[StyledText]

proc getSizeBytes(line: StyledLine): int =
  result = sizeof(StyledLine)
  for part in line.parts:
    result += sizeof(StyledText)
    result += part.text.len
    result += part.scope.len

variantp TextDocumentChange:
  Replace(startByte: int, oldEndByte: int, newEndByte: int, startPoint: Point, oldEndPoint: Point, newEndPoint: Point)

type TextDocument* = ref object of Document
  buffer*: Buffer
  lineIds*: seq[int32]
  mLanguageId: string
  version*: int

  nextLineIdCounter: int32 = 0

  isLoadingAsync*: bool = false

  onRequestRerender*: Event[void]
  onPreLoaded*: Event[TextDocument]
  onLoaded*: Event[TextDocument]
  onSaved*: Event[void]
  textChanged*: Event[TextDocument]
  textInserted*: Event[tuple[document: TextDocument, location: Selection, text: string]] # todo: remove
  textDeleted*: Event[tuple[document: TextDocument, location: Selection]] # todo: remove
  onEdit*: Event[tuple[document: TextDocument, edits: seq[tuple[old, new: Selection]]]]
  onOperation*: Event[tuple[document: TextDocument, op: Operation]]
  singleLine*: bool = false
  readOnly*: bool = false
  staged*: bool = false

  changes: seq[TextDocumentChange]
  insertOrDelete: int = 0

  configProvider: ConfigProvider
  languageConfig*: Option[TextLanguageConfig]
  indentStyle*: IndentStyle
  createLanguageServer*: bool = true
  completionTriggerCharacters*: set[char] = {}

  undoOps*: seq[UndoOp]
  redoOps*: seq[UndoOp]
  nextCheckpoints: seq[string]

  autoReload*: bool

  currentContentFailedToParse: bool
  tsLanguage: TSLanguage
  currentTree: TSTree
  highlightQuery: TSQuery
  errorQuery: TSQuery

  languageServer*: Option[LanguageServer]
  languageServerFuture*: Option[Future[Option[LanguageServer]]]
  onRequestSaveHandle*: OnRequestSaveHandle

  styledTextCache: Table[int, StyledLine]

  diagnosticsPerLine*: Table[int, seq[int]]
  currentDiagnostics*: seq[Diagnostic]
  onDiagnosticsUpdated*: Event[void]
  onDiagnosticsHandle: Id

  onLanguageServerAttached*: Event[tuple[document: TextDocument, languageServer: LanguageServer]]

  treesitterParserCursor: RopeCursor ## Used during treesitter parsing to avoid constant seeking

var allTextDocuments*: seq[TextDocument] = @[]

proc reloadTreesitterLanguage*(self: TextDocument)
proc clearStyledTextCache*(self: TextDocument)
proc clearDiagnostics*(self: TextDocument)
proc numLines*(self: TextDocument): int {.noSideEffect.}

func toPoint*(cursor: Cursor): Point = Point.init(cursor.line, cursor.column)
func toPointRange*(selection: Selection): tuple[first, last: Point] = (selection.first.toPoint, selection.last.toPoint)
func toCursor*(point: Point): Cursor = (point.row.int, point.column.int)
func toSelection*(self: (Point, Point)): Selection = (self[0].toCursor, self[1].toCursor)

proc getTotalTextSize*(self: UndoOp): int =
  for c in self.checkpoints:
    result += c.len
  case self.kind:
  of Delete:
    discard
  of Insert:
    result += self.text.len
  of Nested:
    for c in self.children:
      result += c.getTotalTextSize()

method getStatisticsString*(self: TextDocument): string =
  let stats = st.stats(self.buffer.visibleText.tree)

  result.add &"Filename: {self.filename}\n"
  result.add &"Lines: {self.numLines}\n"
  result.add &"Line Ids: {self.lineIds.len}\n"
  result.add &"Text: {($stats).indent(2)}\n"
  result.add &"Changes: {self.changes.len}\n"
  result.add &"Redo Ops: {self.redoOps.len}\n"

  var undoOpsSize = 0
  for c in self.undoOps:
    undoOpsSize += c.getTotalTextSize()
  result.add &"Undo Ops: {self.undoOps.len}, {undoOpsSize} bytes\n"

  var styledTextCacheBytes = 0
  for c in self.styledTextCache.values:
    styledTextCacheBytes += c.getSizeBytes()
  result.add &"Styled line cache: {self.styledTextCache.len}, {styledTextCacheBytes} bytes\n"

  result.add &"Diagnostics per line: {self.diagnosticsPerLine.len}\n"
  result.add &"Diagnostics: {self.currentDiagnostics.len}"

proc tabWidth*(self: TextDocument): int

proc nextLineId*(self: TextDocument): int32 =
  result = self.nextLineIdCounter
  self.nextLineIdCounter.inc

func getLine*(self: TextDocument, line: int): string =
  if line notin 0..<self.numLines:
    return ""

  let visibleText = self.buffer.visibleText.clone()
  let lineBounds = visibleText.lineBounds(line)

  return $visibleText.slice(lineBounds)

func lineLength*(self: TextDocument, line: int): int =
  return self.buffer.visibleText.lineLen(line)

func lineRuneLen*(self: TextDocument, line: int): RuneCount =
  return self.buffer.visibleText.lineRuneLen(line).RuneCount

proc numLines*(self: TextDocument): int {.noSideEffect.} =
  return self.buffer.visibleText.lines

proc lastValidIndex*(self: TextDocument, line: int, includeAfter: bool = true): int =
  if line < self.numLines:
    let visibleText = self.buffer.visibleText.clone()
    let lineBounds = visibleText.lineBounds(line)
    var res = lineBounds.len
    if not includeAfter and res > 0:
      res = visibleText.validateOffset(lineBounds.b, Bias.Left) - lineBounds.a

    return res

  return 0

proc lastCursor*(self: TextDocument): Cursor =
  if self.numLines > 0:
    return (self.numLines - 1, self.lastValidIndex(self.numLines - 1))
  return (0, 0)

proc clampCursor*(self: TextDocument, cursor: Cursor, includeAfter: bool = true): Cursor =
  var cursor = cursor
  cursor.line = clamp(cursor.line, 0, self.numLines - 1)

  var res = self.buffer.visibleText.clipPoint(cursor.toPoint, Bias.Left).toCursor
  var c = self.buffer.visibleText.cursorT(res.toPoint)
  if not includeAfter and c.currentRune == '\n'.Rune and res.column > 0:
    c.seekPrevRune()
    res = c.position.toCursor
  return res

proc clampSelection*(self: TextDocument, selection: Selection, includeAfter: bool = true): Selection = (self.clampCursor(selection.first, includeAfter), self.clampCursor(selection.last, includeAfter))
proc clampAndMergeSelections*(self: TextDocument, selections: openArray[Selection]): Selections = selections.map((s) => self.clampSelection(s)).deduplicate
proc getLanguageServer*(self: TextDocument): Future[Option[LanguageServer]] {.async.}
proc trimTrailingWhitespace*(self: TextDocument)

proc runeIndexInLine*(self: TextDocument, cursor: Cursor): RuneIndex =
  if cursor.line notin 0..self.numLines - 1:
    return 0.RuneIndex

  var c = self.buffer.visibleText.cursorT(Point.init(cursor.line, 0))
  let runeIndex = c.summary(Count, cursor.toPoint)
  return runeIndex.int.RuneIndex

proc notifyTextChanged*(self: TextDocument) =
  self.textChanged.invoke self

proc notifyRequestRerender*(self: TextDocument) =
  self.onRequestRerender.invoke()

proc applyTreesitterChanges(self: TextDocument) =
  if self.currentTree.isNotNil:
    for change in self.changes:
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

      discard self.currentTree.edit(edit)

  self.changes.setLen 0

let nl = "\n"
proc getTextRangeTreesitter(self: TextDocument; byteIndex: int, cursor: Cursor): (ptr char, int) =
  if cursor.line notin 0..self.numLines - 1:
    return (nil, 0)

  if byteIndex < self.treesitterParserCursor.offset:
    self.treesitterParserCursor.reset()

  self.treesitterParserCursor.seekForward(byteIndex)
  if self.treesitterParserCursor.chunk.getSome(chunk):
    let byteIndexRel = byteIndex - self.treesitterParserCursor.chunkStartPos
    return (chunk.chars[byteIndexRel].addr, chunk.chars.len - byteIndexRel)
  return (nil, 0)

proc reparseTreesitter*(self: TextDocument) =
  # logScope lvlInfo, &"reparseTreesitter({self.filename})"
  self.applyTreesitterChanges()

  if self.currentContentFailedToParse:
    # We already tried to parse the current content and it failed, don't try again
    return

  if self.tsLanguage.isNotNil:
    withParser parser:
      parser.setLanguage(self.tsLanguage)

      try:
        if self.currentTree.isNil:
          self.clearStyledTextCache()

        self.treesitterParserCursor = self.buffer.visibleText.cursor()
        self.currentTree = parser.parseCallback(self.currentTree):
          proc(index: int, cursor: Cursor): (ptr char, int) =
            return self.getTextRangeTreesitter(index, cursor)

        self.currentContentFailedToParse = false
      except:
        log lvlError, &"Failed to parse treesitter tree for '{self.filename}': {getCurrentExceptionMsg()}"
        self.currentContentFailedToParse = true

proc tsTree*(self: TextDocument): TsTree =
  if self.changes.len > 0 or self.currentTree.isNil:
    self.reparseTreesitter()
  return self.currentTree

proc languageId*(self: TextDocument): string =
  self.mLanguageId

proc `languageId=`*(self: TextDocument, languageId: string) =
  if self.mLanguageId != languageId:
    self.mLanguageId = languageId
    self.reloadTreesitterLanguage()

func contentString*(self: TextDocument): string =
  return $self.buffer.visibleText

proc `content=`*(self: TextDocument, value: sink string, buildBuffer: bool = true) =
  self.revision.inc
  self.undoableRevision.inc

  self.undoOps = @[]
  self.redoOps = @[]

  let previousFullSelection = ((0, 0), self.lastCursor)

  let invalidUtf8Index = value.validateUtf8
  if invalidUtf8Index >= 0:
    log lvlWarn,
      &"[content=] Trying to set content with invalid utf-8 string (invalid byte at {invalidUtf8Index})"
    if buildBuffer:
      self.buffer = initBuffer(content = "Invalid utf-8 byte at {invalidUtf8Index}")

  else:
    var index = 0
    const utf8_bom = "\xEF\xBB\xBF"
    if value.len >= 3 and value.startsWith(utf8_bom):
      log lvlInfo, &"[content=] Skipping utf8 bom"
      index = 3

    if buildBuffer:
      self.buffer = initBuffer(content = value[index..^1])

  self.lineIds.setLen self.numLines
  for id in self.lineIds.mitems:
    id = self.nextLineId

  self.currentContentFailedToParse = false
  self.currentTree.delete()
  inc self.version

  self.textDeleted.invoke((self, previousFullSelection))
  self.textInserted.invoke((self, ((0, 0), self.lastCursor), self.contentString))

  self.clearDiagnostics()
  self.clearStyledTextCache()
  self.notifyTextChanged()

proc rebuildBuffer*(self: TextDocument, replicaId: ReplicaId, content: string) =
  self.content = content
  self.buffer = initBuffer(replicaId, content)
  self.notifyRequestRerender()

proc applyRemoteChanges*(self: TextDocument, ops: seq[Operation]) =
  self.buffer.applyRemote(ops)
  # todo: remove once lines is gone
  `content=`(self, self.buffer.contentString, buildBuffer = false)

proc `content=`*(self: TextDocument, value: seq[string]) =
  self.content = value.join("\n")

func contentString*(self: TextDocument, selection: Selection, inclusiveEnd: bool = false): string =
  let selection = selection.normalized

  var c = self.buffer.visibleText.cursorT(selection.first.toPoint)
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
  if cursor.column < 0 or cursor.column > self.getLine(cursor.line).high:
    return 0.char
  return self.getLine(cursor.line)[cursor.column]

func runeAt*(self: TextDocument, cursor: Cursor): Rune =
  if cursor.line < 0 or cursor.line > self.numLines - 1:
    return 0.Rune
  if cursor.column < 0 or cursor.column > self.getLine(cursor.line).high:
    return 0.Rune
  return self.getLine(cursor.line).runeAt(cursor.column)

proc lspRangeToSelection*(self: TextDocument, `range`: lsp_types.Range): Selection =
  if `range`.start.line > self.numLines - 1 or `range`.end.line > self.numLines - 1:
    return (0, 0).toSelection

  let firstColumn = self.getLine(`range`.start.line).runeOffset(`range`.start.character.RuneIndex)
  let lastColumn = self.getLine(`range`.`end`.line).runeOffset(`range`.`end`.character.RuneIndex)
  return ((`range`.start.line, firstColumn), (`range`.`end`.line, lastColumn))

proc runeCursorToCursor*(self: TextDocument, cursor: RuneCursor): Cursor =
  if cursor.line < 0 or cursor.line > self.numLines - 1:
    return (0, 0)

  return (cursor.line, self.getLine(cursor.line).runeOffset(min(self.getLine(cursor.line).runeLen.RuneIndex, max(0.RuneIndex, cursor.column))))

proc runeSelectionToSelection*(self: TextDocument, cursor: RuneSelection): Selection =
  return (self.runeCursorToCursor(cursor.first), self.runeCursorToCursor(cursor.last))

func len*(line: StyledLine): int =
  result = 0
  for p in line.parts:
    result += p.text.len

proc runeIndex*(line: StyledLine, index: int): RuneIndex =
  var i = 0
  for part in line.parts.mitems:
    if index >= i and index < i + part.text.len:
      result += part.text.toOpenArray.runeIndex(index - i).RuneCount
      return
    i += part.text.len
    result += part.text.toOpenArray.runeLen

proc runeLen*(line: StyledLine): RuneCount =
  for part in line.parts.mitems:
    result += part.text.toOpenArray.runeLen

proc visualColumnToCursorColumn*(self: TextDocument, line: int, visualColumn: int): int =
  var column = 0
  let tabWidth = self.tabWidth

  var c = self.buffer.visibleText.cursorT(Point.init(line, 0))
  while not c.atEnd:
    let r = c.currentRune

    if r == '\t'.Rune:
      column = align(column + 1, tabWidth)
    else:
      column += 1

    result += r.size
    if column >= visualColumn:
      break

    c.seekNextRune()

proc cursorToVisualColumn*(self: TextDocument, cursor: Cursor): int =
  let line {.cursor.} = self.getLine(cursor.line)
  let tabWidth = self.tabWidth

  for i in 0..<min(cursor.column, line.len):
    if line[i] == '\t':
      result = align(result + 1, tabWidth)
    else:
      result += 1

proc splitPartAt*(line: var StyledLine, partIndex: int, index: RuneIndex) =
  if partIndex < line.parts.len and index != 0.RuneIndex and index != line.parts[partIndex].text.runeLen.RuneIndex:
    var copy = line.parts[partIndex]
    let byteIndex = line.parts[partIndex].text.toOpenArray.runeOffset(index)
    line.parts[partIndex].text = line.parts[partIndex].text[0..<byteIndex]
    if line.parts[partIndex].textRange.isSome:
      let byteIndexGlobal = line.parts[partIndex].textRange.get.startOffset + byteIndex
      let indexGlobal = line.parts[partIndex].textRange.get.startIndex + index.RuneCount
      line.parts[partIndex].textRange.get.endOffset = byteIndexGlobal
      line.parts[partIndex].textRange.get.endIndex = indexGlobal
      copy.textRange.get.startOffset = byteIndexGlobal
      copy.textRange.get.startIndex = indexGlobal

    copy.text = copy.text[byteIndex..^1]
    line.parts.insert(copy, partIndex + 1)

proc splitAt*(line: var StyledLine, index: RuneIndex) =
  for i in 0..line.parts.high:
    if line.parts[i].textRange.getSome(r) and index > r.startIndex and index < r.endIndex:
      splitPartAt(line, i, RuneIndex(index - r.startIndex))
      break

proc splitAt*(self: TextDocument, line: var StyledLine, index: int) =
  line.splitAt(self.runeIndexInLine((line.index, index)))

proc findAllBounds*(str: string, line: int, regex: Regex): seq[Selection] =
  var start = 0
  while start < str.len:
    let bounds = str.findBounds(regex, start)
    if bounds.first == -1:
      break
    result.add ((line, bounds.first), (line, bounds.last + 1))
    start = bounds.last + 1

proc overrideStyle*(line: var StyledLine, first: RuneIndex, last: RuneIndex, scope: string, priority: int) =
  var index = 0.RuneIndex
  for i in 0..line.parts.high:
    if index >= first and index + line.parts[i].text.runeLen <= last and priority < line.parts[i].priority:
      line.parts[i].scope = scope
      line.parts[i].scopeC = line.parts[i].scope.cstring
      line.parts[i].priority = priority
    index += line.parts[i].text.runeLen

proc overrideUnderline*(line: var StyledLine, first: RuneIndex, last: RuneIndex, underline: bool, color: Color) =
  var index = 0.RuneIndex
  for i in 0..line.parts.high:
    if index >= first and index + line.parts[i].text.runeLen <= last:
      line.parts[i].underline = underline
      line.parts[i].underlineColor = color
    index += line.parts[i].text.runeLen

proc overrideStyleAndText*(line: var StyledLine, first: RuneIndex, text: string, scope: string, priority: int, opacity: Option[float] = float.none, joinNext: bool = false) =
  let textRuneLen = text.runeLen

  for i in 0..line.parts.high:
    if line.parts[i].textRange.getSome(r):
      let firstInRange = r.startIndex >= first
      let lastInRange = r.endIndex <= first + textRuneLen
      let higherPriority = priority < line.parts[i].priority

      if firstInRange and lastInRange and higherPriority:
        line.parts[i].scope = scope
        line.parts[i].scopeC = line.parts[i].scope.cstring
        line.parts[i].priority = priority
        line.parts[i].opacity = opacity

        let textOverrideFirst: RuneIndex = r.startIndex - first.RuneCount
        let textOverrideLast: RuneIndex = r.startIndex + (line.parts[i].text.runeLen.RuneIndex - first)
        line.parts[i].text = text[textOverrideFirst..<textOverrideLast]
        line.parts[i].joinNext = joinNext or line.parts[i].joinNext

proc overrideStyle*(self: TextDocument, line: var StyledLine, first: int, last: int, scope: string, priority: int) =
  line.overrideStyle(self.runeIndexInLine((line.index, first)), self.runeIndexInLine((line.index, last)), scope, priority)

proc overrideUnderline*(self: TextDocument, line: var StyledLine, first: int, last: int, underline: bool, color: Color) =
  line.overrideUnderline(self.runeIndexInLine((line.index, first)), self.runeIndexInLine((line.index, last)), underline, color)

proc overrideStyleAndText*(self: TextDocument, line: var StyledLine, first: int, text: string, scope: string, priority: int, opacity: Option[float] = float.none, joinNext: bool = false) =
  line.overrideStyleAndText(self.runeIndexInLine((line.index, first)), text, scope, priority, opacity, joinNext)

proc insertText*(self: TextDocument, line: var StyledLine, offset: RuneIndex, text: string, scope: string, containCursor: bool, modifyCursorAtEndOfLine: bool = false) =
  line.splitAt(offset)
  for i in 0..line.parts.high:
    if line.parts[i].textRange.getSome(r):
      if offset == r.endIndex:
        line.parts.insert(StyledText(text: text, scope: scope, scopeC: scope.cstring, priority: 1000000000, inlayContainCursor: containCursor, modifyCursorAtEndOfLine: modifyCursorAtEndOfLine), i + 1)
        return

proc insertTextBefore*(self: TextDocument, line: var StyledLine, offset: RuneIndex, text: string, scope: string) =
  line.splitAt(offset)
  var index = 0.RuneIndex
  for i in 0..line.parts.high:
    if offset == index:
      line.parts.insert(StyledText(text: text, scope: scope, scopeC: scope.cstring, priority: 1000000000), i)
      return
    index += line.parts[i].text.runeLen

proc getErrorNodesInRange*(self: TextDocument, selection: Selection): seq[Selection] =
  if self.errorQuery.isNil or self.tsTree.isNil:
    return

  for match in self.errorQuery.matches(self.tsTree.root, tsRange(tsPoint(selection.first.line, 0), tsPoint(selection.last.line, 0))):
    for capture in match.captures:
      result.add capture.node.getRange.toSelection

let spacePattern = re"[ ]+"
let tabPattern = re"\t"

proc replaceSpaces(self: TextDocument, line: var StyledLine) =
  # override whitespace
  let opacity = self.configProvider.getValue("editor.text.whitespace.opacity", 0.4)
  if opacity <= 0:
    return

  var bounds: seq[Range[int]] # Rune indices
  var c = self.buffer.visibleText.cursorT(Point.init(line.index, 0))
  var index = 0
  while not c.atEnd:
    let r = c.currentRune
    if r == ' '.Rune:
      if bounds.len > 0 and index == bounds[^1].b:
        bounds[^1].b += 1
      else:
        bounds.add index...(index + 1)
    elif r == '\n'.Rune:
      break

    index += r.size
    c.seekNextRune()

  if bounds.len == 0:
    return

  for s in bounds:
    line.splitAt(s.a.RuneIndex)
    line.splitAt(s.b.RuneIndex)

  let ch = self.configProvider.getValue("editor.text.whitespace.char", "·")
  for s in bounds:
    let text = ch.repeat(s.len)
    line.overrideStyleAndText(s.a.RuneIndex, text, "comment", 0, opacity=opacity.some)

proc replaceTabs(self: TextDocument, line: var StyledLine) =
  var bounds: seq[Range[int]] # Rune indices
  var c = self.buffer.visibleText.cursorT(Point.init(line.index, 0))
  var index = 0
  while not c.atEnd:
    let r = c.currentRune
    if r == '\t'.Rune:
      bounds.add index...(index + 1)
    elif r == '\n'.Rune:
      break

    index += r.size
    c.seekNextRune()

  if bounds.len == 0:
    return

  let opacity = self.configProvider.getValue("editor.text.whitespace.opacity", 0.4)

  for s in bounds:
    line.splitAt(s.a.RuneIndex)
    line.splitAt(s.b.RuneIndex)

  let tabWidth = self.tabWidth
  var currentOffset = 0
  var previousEnd = 0

  for s in bounds:
    currentOffset += s.a - previousEnd

    let alignCorrection = currentOffset mod tabWidth
    let currentTabWidth = tabWidth - alignCorrection
    let t = "|"
    let runeIndex = s.a.RuneIndex
    line.overrideStyleAndText(runeIndex, t, "comment", 0, opacity=opacity.some)
    if currentTabWidth > 1:
      self.insertText(line, runeIndex + 1.RuneCount, " ".repeat(currentTabWidth - 1), "comment", containCursor=false, modifyCursorAtEndOfLine=true)

    currentOffset += currentTabWidth
    previousEnd = s.b

proc addDiagnosticsUnderline(self: TextDocument, line: var StyledLine) =
  # diagnostics
  if self.diagnosticsPerLine.contains(line.index):
    let indices {.cursor.} = self.diagnosticsPerLine[line.index]

    const maxNonErrors = 2
    const maxErrors = 4

    var nonErrorDiagnostics = 0
    var errorDiagnostics = 0

    for diagnosticIndex in indices:
      let diagnostic {.cursor.} = self.currentDiagnostics[diagnosticIndex]
      if diagnostic.removed:
        continue

      let isError = diagnostic.severity.isSome and diagnostic.severity.get == lsp_types.DiagnosticSeverity.Error
      if isError:
        if errorDiagnostics >= maxErrors:
          continue
        errorDiagnostics.inc
      else:
        if nonErrorDiagnostics >= maxNonErrors:
          continue
        nonErrorDiagnostics.inc

      let colorName = if diagnostic.severity.getSome(severity):
        case severity
        of lsp_types.DiagnosticSeverity.Error: "editorError.foreground"
        of lsp_types.DiagnosticSeverity.Warning: "editorWarning.foreground"
        of lsp_types.DiagnosticSeverity.Information: "editorInfo.foreground"
        of lsp_types.DiagnosticSeverity.Hint: "editorHint.foreground"
      else:
        "editorHint.foreground"

      let color = if gTheme.isNotNil:
        gTheme.color(colorName, color(1, 1, 1))
      elif diagnostic.severity.getSome(severity):
        case severity
        of lsp_types.DiagnosticSeverity.Error: color(1, 0, 0)
        of lsp_types.DiagnosticSeverity.Warning: color(1, 0.8, 0.2)
        of lsp_types.DiagnosticSeverity.Information: color(1, 1, 1)
        of lsp_types.DiagnosticSeverity.Hint: color(0.7, 0.7, 0.7)
      else:
        color(0.7, 0.7, 0.7)

      line.splitAt(self.getLine(line.index).toOpenArray.runeIndex(diagnostic.selection.first.column, returnLen=true))
      line.splitAt(self.getLine(line.index).toOpenArray.runeIndex(diagnostic.selection.last.column, returnLen=true))
      self.overrideUnderline(line, diagnostic.selection.first.column, diagnostic.selection.last.column, true, color)

      let newLineIndex = diagnostic.message.find("\n")
      let maxIndex = if newLineIndex != -1:
        newLineIndex
      else:
        diagnostic.message.len

      let diagnosticMessage: string = "     ■ " & diagnostic.message[0..<maxIndex]
      line.parts.add StyledText(text: diagnosticMessage, scope: colorName, scopeC: colorName.cstring, inlayContainCursor: true, scopeIsToken: false, canWrap: false, priority: 1000000000)

var regexes = initTable[string, Regex]()
proc applyTreesitterHighlighting(self: TextDocument, line: var StyledLine) =
  # logScope lvlInfo, &"applyTreesitterHighlighting({line.index}, {self.filename})"

  if self.highlightQuery.isNil or self.tsTree.isNil:
    return


  let lineLen = self.lineLength(line.index)

  for match in self.highlightQuery.matches(self.tsTree.root, tsRange(tsPoint(line.index, 0), tsPoint(line.index, lineLen))):
    let predicates = self.highlightQuery.predicatesForPattern(match.pattern)

    for capture in match.captures:
      let scope = capture.name
      let node = capture.node

      var matches = true
      for predicate in predicates:

        if not matches:
          break

        for operand in predicate.operands:
          let value = $operand.`type`

          if operand.name != scope:
            matches = false
            break

          case $predicate.operator
          of "match?":
            if not regexes.contains(value):
              regexes[value] = re(value)
            let regex {.cursor.} = regexes[value]

            let nodeText = self.contentString(node.getRange)
            if nodeText.matchLen(regex, 0) != nodeText.len:
              matches = false
              break

          of "not-match?":
            if not regexes.contains(value):
              regexes[value] = re(value)
            let regex {.cursor.} = regexes[value]

            let nodeText = self.contentString(node.getRange)
            if nodeText.matchLen(regex, 0) == nodeText.len:
              matches = false
              break

          of "eq?":
            # @todo: second arg can be capture aswell
            let nodeText = self.contentString(node.getRange)
            if nodeText != value:
              matches = false
              break

          of "not-eq?":
            # @todo: second arg can be capture aswell
            let nodeText = self.contentString(node.getRange)
            if nodeText == value:
              matches = false
              break

          # of "any-of?":
          #   log(lvlError, fmt"Unknown predicate '{predicate.name}'")

          else:
            # log(lvlError, fmt"Unknown predicate '{predicate.operator}'")
            discard

        if self.configProvider.getFlag("text.print-matches", false):
          let nodeText = self.contentString(node.getRange)
          log(lvlInfo, fmt"{match.pattern}: '{nodeText}' {node} (matches: {matches})")

      if not matches:
        continue

      let nodeRange = node.getRange

      if nodeRange.first.row == line.index:
        splitAt(self, line, nodeRange.first.column)
      if nodeRange.last.row == line.index:
        splitAt(self, line, nodeRange.last.column)

      let first = if nodeRange.first.row < line.index:
        0
      elif nodeRange.first.row == line.index:
        nodeRange.first.column
      else:
        lineLen

      let last = if nodeRange.last.row < line.index:
        0
      elif nodeRange.last.row == line.index:
        nodeRange.last.column
      else:
        lineLen

      overrideStyle(self, line, first, last, $scope, match.pattern)

proc getStyledText*(self: TextDocument, i: int): StyledLine =
  if self.styledTextCache.contains(i):
    result = self.styledTextCache[i]
  else:
    if i >= self.numLines:
      log lvlError, fmt"getStyledText({i}) out of range {self.numLines}"
      return StyledLine()

    if self.changes.len > 0 or self.currentTree.isNil:
      self.reparseTreesitter()

    # logScope lvlInfo, &"getStyledText({i}, {self.filename})"

    var line = self.getLine(i)
    var parts = newSeqOfCap[StyledText](50)
    parts.add StyledText(text: line, scope: "", scopeC: "", priority: 1000000000, textRange: (0, line.len, 0.RuneIndex, line.runeLen.RuneIndex).some)
    result = StyledLine(index: i, parts: parts.move)
    self.styledTextCache[i] = result

    self.applyTreesitterHighlighting(result)
    self.replaceSpaces(result)
    self.replaceTabs(result)
    self.addDiagnosticsUnderline(result)

proc loadTreesitterLanguage(self: TextDocument): Future[void] {.async.} =
  logScope lvlInfo, &"loadTreesitterLanguage {self.filename}"

  self.highlightQuery = nil
  self.errorQuery = nil
  self.currentContentFailedToParse = false
  self.tsLanguage = nil
  self.currentTree.delete()
  self.clearStyledTextCache()

  if self.languageId == "":
    return

  let prevLanguageId = self.languageId
  let config = self.configProvider.getValue("treesitter." & self.languageId, newJObject())
  var language = await getTreesitterLanguage(self.languageId, config)

  if prevLanguageId != self.languageId:
    log lvlWarn, &"loadTreesitterLanguage {prevLanguageId}: ignore, newer language was set"
    return

  if language.isNone:
    log lvlWarn, &"Treesitter language is not available for '{self.languageId}'"
    return

  log lvlInfo, &"loadTreesitterLanguage {prevLanguageId}: Loaded language, apply"
  self.currentContentFailedToParse = false
  self.tsLanguage = language.get
  self.currentTree.delete()

  # todo: this awaits, check if still current request afterwards
  let highlightQueryPath = fs.getApplicationFilePath(&"languages/{self.languageId}/queries/highlights.scm")
  if language.get.queryFile("highlight", highlightQueryPath).await.getSome(query):
    if prevLanguageId != self.languageId:
      return

    self.highlightQuery = query
  else:
    log(lvlError, fmt"No highlight queries found for '{self.languageId}'")

  let errorQueryPath = fs.getApplicationFilePath(&"languages/{self.languageId}/queries/errors.scm")
  if language.get.queryFile("error", errorQueryPath, cacheOnFail = false).await.getSome(query):
    if prevLanguageId != self.languageId:
      return
    self.errorQuery = query
  elif language.get.query("error", "(ERROR) @error").await.getSome(query):
    self.errorQuery = query
  else:
    log(lvlError, fmt"No error queries found for '{self.languageId}'")

  if prevLanguageId != self.languageId:
    return

  self.clearStyledTextCache()
  self.notifyRequestRerender()

proc reloadTreesitterLanguage*(self: TextDocument) =
  asyncCheck self.loadTreesitterLanguage()

proc newTextDocument*(
    configProvider: ConfigProvider,
    filename: string = "",
    content: string = "",
    app: bool = false,
    workspaceFolder: Option[Workspace] = Workspace.none,
    language: Option[string] = string.none,
    languageServer: Option[LanguageServer] = LanguageServer.none,
    load: bool = false,
    createLanguageServer: bool = true): TextDocument =

  log lvlInfo, &"Creating new text document '{filename}', (lang: {language}, app: {app}, ls: {createLanguageServer})"
  new(result)
  allTextDocuments.add result

  var self = result
  self.filename = filename.normalizePathUnix
  self.currentTree = nil
  self.appFile = app
  self.workspace = workspaceFolder
  self.configProvider = configProvider
  self.createLanguageServer = createLanguageServer
  self.buffer = initBuffer(content = "")

  self.indentStyle = IndentStyle(kind: Spaces, spaces: 2)

  if language.getSome(language):
    self.languageId = language
  elif getLanguageForFile(self.configProvider, filename).getSome(language):
    self.languageId = language

  if self.languageId != "":
    if (let value = self.configProvider.getValue("languages." & self.languageId, newJNull()); value.kind == JObject):
      self.languageConfig = value.jsonTo(TextLanguageConfig, Joptions(allowExtraKeys: true, allowMissingKeys: true)).some
      if value.hasKey("indent"):
        case value["indent"].str:
        of "spaces":
          self.indentStyle = IndentStyle(
            kind: Spaces,
            spaces: self.languageConfig.map((c) => c.tabWidth).get(4)
          )
        of "tabs":
          self.indentStyle = IndentStyle(kind: Tabs)

  let autoStartServer = self.configProvider.getValue("editor.text.auto-start-language-server", false)

  self.content = content
  self.languageServer = languageServer.mapIt(it)

  if load:
    self.load()

  if self.languageServer.getSome(ls):
    # debugf"register save handler '{self.filename}'"
    let callback = proc (targetFilename: string): Future[void] {.async.} =
      # debugf"save temp file '{targetFilename}'"
      if self.languageServer.getSome(ls):
        await ls.saveTempFile(targetFilename, self.contentString)
    self.onRequestSaveHandle = ls.addOnRequestSaveHandler(self.filename, callback)

  elif createLanguageServer and autoStartServer:
    asyncCheck self.getLanguageServer()

method deinit*(self: TextDocument) =
  logScope lvlInfo, fmt"[deinit] Destroying text document '{self.filename}'"
  if self.currentTree.isNotNil:
    self.currentTree.delete()
  self.highlightQuery = nil
  self.errorQuery = nil

  if self.languageServer.getSome(ls):
    ls.onDiagnostics.unsubscribe(self.onDiagnosticsHandle)
    ls.removeOnRequestSaveHandler(self.onRequestSaveHandle)
    ls.disconnect(self)
    self.languageServer = LanguageServer.none

  let i = allTextDocuments.find(self)
  if i >= 0:
    allTextDocuments.removeSwap(i)

  self[] = default(typeof(self[]))

method `$`*(self: TextDocument): string =
  return self.filename

proc saveAsync(self:  TextDocument, ws: Workspace) {.async.} =
  await ws.saveFile(self.filename, self.contentString)
  self.onSaved.invoke()

method save*(self: TextDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: filename.normalizePathUnix else: self.filename
  logScope lvlInfo, &"[save] '{self.filename}'"

  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  if self.staged:
    return

  self.appFile = app

  # Todo: make optional
  self.trimTrailingWhitespace()

  if self.workspace.getSome(ws):
    asyncCheck self.saveAsync(ws)

  elif self.appFile:
    fs.saveApplicationFile(self.filename, self.contentString)
    self.onSaved.invoke()

  else:
    fs.saveFile(self.filename, self.contentString)
    self.onSaved.invoke()

  self.isBackedByFile = true
  self.lastSavedRevision = self.undoableRevision

proc autoDetectIndentStyle(self: TextDocument) =
  var containsTab = false
  var linePos = Point.init(0, 0)
  var c = self.buffer.visibleText.cursorT(linePos)
  while not c.atEnd:
    if c.currentRune == '\t'.Rune:
      containsTab = true
      break
    linePos.row += 1
    c.seekForward(linePos)

  if containsTab:
    self.indentStyle = IndentStyle(kind: Tabs)
  else:
    self.indentStyle = IndentStyle(kind: Spaces, spaces: self.tabWidth)

  log lvlInfo, &"[Text_document] Detected indent: {self.indentStyle}, {self.languageConfig.get(TextLanguageConfig())[]}"

proc loadAsync*(self: TextDocument, ws: Workspace, reloadTreesitter: bool = false): Future[void] {.async.} =

  logScope lvlInfo, &"loadAsync '{self.filename}'"
  # self.content = await ws.loadFile(self.filename)
  self.isBackedByFile = true
  self.isLoadingAsync = true
  self.readOnly = true

  var data = ""
  catch ws.loadFile(self.filename, data.addr).await:
    log lvlError, &"[loadAsync] Failed to load workspace file {self.filename}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

  self.onPreLoaded.invoke self
  self.content = data.move

  if not ws.isFileReadOnly(self.filename).await:
    self.readOnly = false

  self.autoDetectIndentStyle()

  self.lastSavedRevision = self.undoableRevision
  self.isLoadingAsync = false
  self.onLoaded.invoke self

proc setReadOnly*(self: TextDocument, readOnly: bool) =
  ## Sets the interal readOnly flag, but doesn't not changed permission of the underlying file
  self.readOnly = readOnly

proc reloadTask(self: TextDocument) {.async.} =
  defer:
    self.autoReload = false

  var lastModTime = getLastModificationTime(self.filename)
  while self.autoReload and not self.workspace.isNone:
    var modTime = getLastModificationTime(self.filename)
    if modTime > lastModTime:
      lastModTime = modTime
      log lvlInfo, &"File '{self.filename}' changed on disk, reload"
      await self.loadAsync(self.workspace.get)

    await sleepAsync(1000)

proc enableAutoReload*(self: TextDocument, enabled: bool) =
  if not self.autoReload and enabled:
    self.autoReload = true
    asyncCheck self.reloadTask()
    return

  self.autoReload = enabled

proc setFileReadOnlyAsync*(self: TextDocument, readOnly: bool): Future[bool] {.async.} =
  ## Tries to set the underlying file permissions
  if self.workspace.getSome(workspace):
    if workspace.setFileReadOnly(self.filename, readOnly).await:
      self.readOnly = readOnly
      return true

  return false

proc setFileAndContent*(self: TextDocument, filename: string, content: sink string) =
  let filename = if filename.len > 0: filename.normalizePathUnix else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  logScope lvlInfo, &"[setFileAndContent] '{filename}'"

  self.filename = filename
  self.isBackedByFile = false

  if getLanguageForFile(self.configProvider, filename).getSome(language):
    self.languageId = language
  else:
    self.languageId = ""

  self.onPreLoaded.invoke self

  self.undoOps.setLen 0
  self.redoOps.setLen 0
  self.content = content.move

  self.clearStyledTextCache()
  self.autoDetectIndentStyle()
  self.onLoaded.invoke self

proc setFileAndReload*(self: TextDocument, filename: string, workspace: Option[Workspace]) =
  let filename = if filename.len > 0: filename.normalizePathUnix else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.workspace = workspace
  self.filename = filename
  self.isBackedByFile = true
  if getLanguageForFile(self.configProvider, filename).getSome(language):
    self.languageId = language
  else:
    self.languageId = ""

  self.highlightQuery = nil
  self.errorQuery = nil

  self.clearStyledTextCache()

  if self.workspace.getSome(ws):
    asyncCheck self.loadAsync(ws, true)
  elif self.appFile:
    self.onPreLoaded.invoke self
    self.content = catch fs.loadApplicationFile(self.filename):
      log lvlError, fmt"Failed to load application file {filename}"
      ""
    self.lastSavedRevision = self.undoableRevision
    self.autoDetectIndentStyle()
    self.onLoaded.invoke self
  else:
    self.onPreLoaded.invoke self
    self.content = catch fs.loadFile(self.filename):
      log lvlError, fmt"Failed to load file {filename}"
      ""
    self.lastSavedRevision = self.undoableRevision
    self.autoDetectIndentStyle()
    self.onLoaded.invoke self

method load*(self: TextDocument, filename: string = "") =
  let filename = if filename.len > 0: filename.normalizePathUnix else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename
  self.isBackedByFile = true

  if self.workspace.getSome(ws):
    asyncCheck self.loadAsync(ws)
  elif self.appFile:
    self.onPreLoaded.invoke self
    self.content = catch fs.loadApplicationFile(self.filename):
      log lvlError, fmt"Failed to load application file {filename}"
      ""
    self.lastSavedRevision = self.undoableRevision
    self.autoDetectIndentStyle()
    self.onLoaded.invoke self
  else:
    self.onPreLoaded.invoke self
    self.content = catch fs.loadFile(self.filename):
      log lvlError, fmt"Failed to load file {filename}"
      ""
    self.lastSavedRevision = self.undoableRevision
    self.autoDetectIndentStyle()
    self.onLoaded.invoke self

proc setCurrentDiagnostics(self: TextDocument, diagnostics: openArray[lsp_types.Diagnostic]) =
  for line in self.diagnosticsPerLine.keys:
    self.styledTextCache.del(line)

  self.currentDiagnostics.setLen diagnostics.len
  self.diagnosticsPerLine.clear()

  for i, d in diagnostics:
    let selection = self.runeSelectionToSelection((
      (d.`range`.start.line, d.`range`.start.character.RuneIndex),
      (d.`range`.`end`.line, d.`range`.`end`.character.RuneIndex)))

    self.currentDiagnostics[i] = language_server_base.Diagnostic(
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

    self.diagnosticsPerLine.mgetOrPut(selection.first.line, @[]).add i
    self.styledTextCache.del(selection.first.line)

proc updateDiagnosticsAsync*(self: TextDocument): Future[void] {.async.} =
  let languageServer = await self.getLanguageServer()
  if languageServer.getSome(ls):
    let diagnostics = await ls.getDiagnostics(self.filename)
    if diagnostics.isSuccess:
      self.setCurrentDiagnostics(diagnostics.result)

proc getLanguageServer*(self: TextDocument): Future[Option[LanguageServer]] {.async.} =
  let languageId = if self.languageId != "":
    self.languageId
  elif getLanguageForFile(self.configProvider, self.filename).getSome(languageId):
    languageId
  else:
    return LanguageServer.none

  if self.languageServer.isSome:
    return self.languageServer

  if self.languageServerFuture.getSome(fut):
    return fut.await

  if not self.createLanguageServer:
    return LanguageServer.none

  let url = self.configProvider.getValue("editor.text.languages-server.url", "")
  let port = self.configProvider.getValue("editor.text.languages-server.port", 0)
  let config = if url != "" and port != 0:
    (url, port).some
  else:
    (string, int).none

  let workspaces = if self.workspace.getSome(ws):
    @[ws.getWorkspacePath()]
  else:
    when declared(getCurrentDir):
      @[getCurrentDir()]
    else:
      @[]

  let languageServerFuture = getOrCreateLanguageServer(languageId, self.filename, workspaces,
    config, self.workspace)

  self.languageServerFuture = languageServerFuture.some
  self.languageServer = await languageServerFuture

  if self.languageServer.getSome(ls):
    self.completionTriggerCharacters = ls.getCompletionTriggerChars()

    ls.connect(self)
    let callback = proc (targetFilename: string): Future[void] {.async.} =
      if self.languageServer.getSome(ls):
        await ls.saveTempFile(targetFilename, self.contentString)

    self.onRequestSaveHandle = ls.addOnRequestSaveHandler(self.filename, callback)

    self.onDiagnosticsHandle = ls.onDiagnostics.subscribe proc(diagnostics: lsp_types.PublicDiagnosticsParams) =
      let uri = diagnostics.uri.decodeUrl.parseUri
      if uri.path.normalizePathUnix == self.filename:
        self.setCurrentDiagnostics(diagnostics.diagnostics)

    self.onLanguageServerAttached.invoke (self, ls)

  return self.languageServer

proc clearDiagnostics*(self: TextDocument) =
  self.diagnosticsPerLine.clear()
  self.currentDiagnostics.setLen 0
  self.clearStyledTextCache()

proc clearStyledTextCache*(self: TextDocument) =
  self.styledTextCache.clear()

proc byteOffset*(self: TextDocument, cursor: Cursor): int =
  result = cursor.column
  for i in 0..<cursor.line:
    result += self.lineLength(i) + 1

proc tabWidth*(self: TextDocument): int =
  return self.languageConfig.map(c => c.tabWidth).get(4)

proc getCompletionSelectionAt*(self: TextDocument, cursor: Cursor): Selection =
  if cursor.column == 0:
    return cursor.toSelection

  let line = self.getLine cursor.line

  let identChars = self.languageConfig.mapIt(it.completionWordChars).get(IdentChars)

  var column = min(cursor.column, line.len)
  while column > 0:
    let prevColumn = line.runeStart(column - 1)
    let r = line.runeAt(prevColumn)
    if (r.int <= char.high.int and r.char in identChars) or r.isAlpha:
      column = prevColumn
      continue
    break

  return ((cursor.line, column), cursor)

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

proc moveCursorColumn(self: TextDocument, cursor: Cursor, offset: int, wrap: bool = true): Cursor =
  var cursor = cursor
  var column = cursor.column

  template currentLine: openArray[char] = self.getLine(cursor.line).toOpenArray

  if offset > 0:
    for i in 0..<offset:
      if column == currentLine.len:
        if not wrap:
          break
        if cursor.line < self.numLines - 1:
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
        if not wrap:
          break
        if cursor.line > 0:
          cursor.line = cursor.line - 1
          cursor.column = currentLine.len
          continue
        else:
          cursor.column = 0
          break

      cursor.column = currentLine.runeStart(cursor.column - 1)

  return self.clampCursor cursor

proc firstNonWhitespace*(str: string): int =
  result = 0
  for c in str:
    if c != ' ' and c != '\t':
      break
    result += 1

proc lineStartsWith*(self: TextDocument, line: int, text: string, ignoreWhitespace: bool): bool =
  # todo: user RopeCursor
  if ignoreWhitespace:
    let index = self.getLine(line).firstNonWhitespace
    return self.getLine(line)[index..^1].startsWith(text)
  else:
    return self.getLine(line).startsWith(text)

proc lastNonWhitespace*(str: string): int =
  result = str.high
  while result >= 0:
    if str[result] != ' ' and str[result] != '\t':
      break
    result -= 1

proc getIndentInBytes*(self: TextDocument, line: int): int =
  if line < 0 or line >= self.numLines:
    return 0

  var c = self.buffer.visibleText.cursorT(Point.init(line, 0))
  while not c.atEnd:
    let r = c.currentRune
    if not r.isWhitespace or r == '\n'.Rune:
      break
    result += r.size
    c.seekNextRune()

proc getIndentLevelForLine*(self: TextDocument, line: int): int =
  if line < 0 or line >= self.numLines:
    return 0

  let indentWidth = self.indentStyle.indentWidth(self.tabWidth)

  var c = self.buffer.visibleText.cursorT(Point.init(line, 0))
  var indent = 0
  while not c.atEnd:
    case c.currentRune
    of '\t'.Rune:
      indent += tabWidthAt(indent, self.tabWidth)
    of ' '.Rune:
      indent += 1
    else:
      break
    c.seekNextRune()

  indent = indent div indentWidth
  return indent

proc getIndentLevelForLineInSpaces*(self: TextDocument, line: int, offset: int = 0): int =
  let indentWidth = self.indentStyle.indentWidth(self.tabWidth)
  if line < 0 or line >= self.numLines:
    return 0
  return max((self.getIndentLevelForLine(line) + offset) * indentWidth, 0)

proc getIndentLevelForClosestLine*(self: TextDocument, line: int): int =
  for i in line..self.numLines - 1:
    if self.lineLength(i) > 0:
        return self.getIndentLevelForLine(i)
  for i in countdown(line, 0):
    if self.lineLength(i) > 0:
        return self.getIndentLevelForLine(i)
  return 0

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
  let line = self.getLine cursor.line
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

proc updateDiagnosticPositionsAfterInsert(self: TextDocument, inserted: Selection) =
  self.diagnosticsPerLine.clear()
  var i = 0
  for d in self.currentDiagnostics.mitems:
    self.styledTextCache.del(d.selection.first.line)
    self.styledTextCache.del(d.selection.last.line)

    d.selection.first = self.updateCursorAfterInsert(d.selection.first, inserted)
    d.selection.last = self.updateCursorAfterInsert(d.selection.last, inserted)

    self.styledTextCache.del(d.selection.first.line)
    self.styledTextCache.del(d.selection.last.line)

    self.diagnosticsPerLine.mgetOrPut(d.selection.first.line, @[]).add i

    inc i

proc updateDiagnosticPositionsAfterDelete(self: TextDocument, selection: Selection) =
  self.diagnosticsPerLine.clear()
  let selection = selection.normalized
  for i in countdown(self.currentDiagnostics.high, 0):
    self.styledTextCache.del(self.currentDiagnostics[i].selection.first.line)
    self.styledTextCache.del(self.currentDiagnostics[i].selection.last.line)

    if self.updateCursorAfterDelete(self.currentDiagnostics[i].selection.first, selection).getSome(first) and
        self.updateCursorAfterDelete(self.currentDiagnostics[i].selection.last, selection).getSome(last):

      self.currentDiagnostics[i].selection = (first, last)

      self.styledTextCache.del(self.currentDiagnostics[i].selection.first.line)
      self.styledTextCache.del(self.currentDiagnostics[i].selection.last.line)

      self.diagnosticsPerLine.mgetOrPut(self.currentDiagnostics[i].selection.first.line, @[]).add i

    else:
      self.currentDiagnostics[i].removed = true

proc edit*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =
  # todo: finish this function
  let selections = self.clampAndMergeSelections(selections).map (s) => s.normalized

  self.insertOrDelete.inc
  defer:
    self.insertOrDelete.dec

  var pointDiff = PointDiff.default
  var byteDiff = 0

  var edits: seq[tuple[old, new: Selection]]


  var ranges = newSeq[(Slice[int], string)]()
  for i, selection in selections:
    let text = if texts.len == 1:
      texts[0]
    elif texts.len == selections.len:
      texts[i]
    else:
      texts[min(i, texts.high)]

    let selection: Selection = if inclusiveEnd and self.lineLength(selection.last.line) > 0:
      let nextColumn = self.getLine(selection.last.line).nextRuneStart(min(selection.last.column, self.lineLength(selection.last.line) - 1)).int
      (selection.first, (selection.last.line, nextColumn))
    else:
      selection

    # todo: use cursor to calculate byte offset
    let startByte = self.byteOffset(selection.first)
    let endByte = self.byteOffset(selection.last)
    assert startByte <= self.buffer.contentLength and endByte <= self.buffer.contentLength
    ranges.add (startByte..<endByte, text)

    let summary = TextSummary.init(text)
    let oldByteRange = (startByte + byteDiff, endByte + byteDiff)
    let newByteRangeEnd = oldByteRange[0] + summary.bytes
    let oldPointRange = (selection.first.toPoint + pointDiff, selection.last.toPoint + pointDiff)
    let newPointRangeEnd = oldPointRange[0] + summary.lines

    pointDiff = newPointRangeEnd - selection.last.toPoint
    byteDiff = newByteRangeEnd - endByte

    let newSelection = (oldPointRange[0], newPointRangeEnd).toSelection
    result.add newSelection
    edits.add (selection, newSelection)

    if not self.tsLanguage.isNil:
      self.changes.add(Replace(oldByteRange[0], oldByteRange[1], newByteRangeEnd, oldPointRange[0], oldPointRange[1], newPointRangeEnd))

  let ops = self.buffer.edit(ranges)
  self.onOperation.invoke (self, ops)
  self.onEdit.invoke (self, edits)

  if notify:
    self.notifyTextChanged()
  self.clearStyledTextCache()

proc doUndo(self: TextDocument, op: UndoOp, oldSelection: openArray[Selection], useOldSelection: bool, redoOps: var seq[UndoOp]): seq[Selection] =
  # todo
  # case op.kind:
  # of Delete:
  #   let text = self.contentString(op.selection)
  #   result = self.delete([op.selection], op.oldSelection, record=false)
  #   redoOps.add UndoOp(kind: Insert, revision: self.undoableRevision, cursor: op.selection.first, text: text, oldSelection: @oldSelection, checkpoints: op.checkpoints)

  # of Insert:
  #   let selections = self.insert([op.cursor.toSelection], op.oldSelection, [op.text], record=false)
  #   result = selections
  #   redoOps.add UndoOp(kind: Delete, revision: self.undoableRevision, selection: (op.cursor, selections[0].last), oldSelection: @oldSelection, checkpoints: op.checkpoints)

  # of Nested:
  #   result = op.oldSelection

  #   var redoOp = UndoOp(kind: Nested, revision: self.undoableRevision, oldSelection: @oldSelection, checkpoints: op.checkpoints)
  #   for i in countdown(op.children.high, 0):
  #     discard self.doUndo(op.children[i], oldSelection, useOldSelection, redoOp.children)

  #   redoOps.add redoOp

  if useOldSelection:
    result = op.oldSelection

proc undo*(self: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool, untilCheckpoint: string = ""): Option[seq[Selection]] =
  # debugf"undo {untilCheckpoint}"
  result = seq[Selection].none

  if self.undoOps.len == 0:
    return

  result = some @oldSelection

  while self.undoOps.len > 0:
    let op = self.undoOps.pop
    result = self.doUndo(op, result.get, useOldSelection, self.redoOps).some
    # self.undoableRevision = op.revision # todo
    if untilCheckpoint.len == 0 or untilCheckpoint in op.checkpoints:
      break

proc doRedo(self: TextDocument, op: UndoOp, oldSelection: openArray[Selection], useOldSelection: bool, undoOps: var seq[UndoOp]): seq[Selection] =
  # todo
  # case op.kind:
  # of Delete:
  #   let text = self.contentString(op.selection)
  #   result = self.delete([op.selection], op.oldSelection, record=false)
  #   undoOps.add UndoOp(kind: Insert, revision: self.undoableRevision, cursor: op.selection.first, text: text, oldSelection: @oldSelection, checkpoints: op.checkpoints)

  # of Insert:
  #   result = self.insert([op.cursor.toSelection], [op.cursor.toSelection], [op.text], record=false)
  #   undoOps.add UndoOp(kind: Delete, revision: self.undoableRevision, selection: (op.cursor, result[0].last), oldSelection: @oldSelection, checkpoints: op.checkpoints)

  # of Nested:
  #   result = op.oldSelection

  #   var undoOp = UndoOp(kind: Nested, revision: self.undoableRevision, oldSelection: @oldSelection, checkpoints: op.checkpoints)
  #   for i in countdown(op.children.high, 0):
  #     discard self.doRedo(op.children[i], oldSelection, useOldSelection, undoOp.children)

  #   undoOps.add undoOp

  if useOldSelection:
    result = op.oldSelection

proc redo*(self: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool, untilCheckpoint: string = ""): Option[seq[Selection]] =
  # debugf"redo {untilCheckpoint}"
  result = seq[Selection].none

  if self.redoOps.len == 0:
    return

  result = some @oldSelection

  while self.redoOps.len > 0:
    let op = self.redoOps.pop
    result = self.doRedo(op, result.get, useOldSelection, self.undoOps).some
    # self.undoableRevision = op.revision # todo
    if untilCheckpoint.len == 0 or (self.redoOps.len > 0 and untilCheckpoint in self.redoOps.last.checkpoints):
      break

proc addNextCheckpoint*(self: TextDocument, checkpoint: string) =
  self.nextCheckpoints.incl checkpoint

proc isLineEmptyOrWhitespace*(self: TextDocument, line: int): bool =
  if line > self.numLines - 1:
    return false
  return self.getLine(line).isEmptyOrWhitespace

proc isLineCommented*(self: TextDocument, line: int): bool =
  if line > self.numLines - 1 or self.languageConfig.isNone or self.languageConfig.get.lineComment.isNone:
    return false
  return custom_unicode.strip(self.getLine(line), trailing=false).startsWith(self.languageConfig.get.lineComment.get)

proc getLineCommentRange*(self: TextDocument, line: int): Selection =
  if line > self.numLines - 1 or self.languageConfig.isNone or self.languageConfig.get.lineComment.isNone:
    return (line, 0).toSelection

  let prefix = self.languageConfig.get.lineComment.get
  let index = self.getLine(line).find(prefix)
  if index == -1:
    return (line, 0).toSelection

  var endIndex = index + prefix.len
  # todo: don't use getLine
  if endIndex < self.lineLength(line) and self.getLine(line)[endIndex] in Whitespace:
    endIndex += 1

  return ((line, index), (line, endIndex))

proc toggleLineComment*(self: TextDocument, selections: Selections): seq[Selection] =
  result = selections

  if self.languageConfig.isNone:
    return

  if self.languageConfig.get.lineComment.isNone:
    return

  let mergedSelections = self.clampAndMergeSelections(selections).mergeLines

  var allCommented = true
  for s in mergedSelections:
    for l in s.first.line..s.last.line:
      if not self.isLineEmptyOrWhitespace(l):
        allCommented = allCommented and self.isLineCommented(l)

  let comment = not allCommented

  var insertSelections: Selections
  for s in mergedSelections:
    var minIndent = int.high
    for l in s.first.line..s.last.line:
      if not self.isLineEmptyOrWhitespace(l):
        minIndent = min(minIndent, self.getIndentInBytes(l))

    for l in s.first.line..s.last.line:
      if not self.isLineEmptyOrWhitespace(l):
        if comment:
          insertSelections.add (l, minIndent).toSelection
        else:
          insertSelections.add self.getLineCommentRange(l)

  if comment:
    let prefix = self.languageConfig.get.lineComment.get & " "
    discard self.edit(insertSelections, selections, [prefix])
  else:
    discard self.edit(insertSelections, selections, [""])

proc trimTrailingWhitespace*(self: TextDocument) =
  var selections: seq[Selection]
  for i in 0..self.numLines - 1:
    # todo: don't use getLine
    let index = self.getLine(i).lastNonWhitespace
    if index == self.lineLength(i) - 1:
      continue
    selections.add ((i, index + 1), (i, self.lineLength(i)))

  if selections.len > 0:
    discard self.edit(selections, selections, [""])
