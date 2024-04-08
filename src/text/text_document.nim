import std/[os, strutils, sequtils, sugar, options, json, strformat, tables, uri]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import patty, bumpy
import misc/[id, util, event, custom_logger, custom_async, custom_unicode, myjsonutils, regex, array_set]
import platform/[filesystem]
import language/[languages, language_server_base]
import workspaces/[workspace]
import document, document_editor, custom_treesitter, indent, text_language_config, config_provider, theme
import pkg/chroma

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
  underline*: bool
  underlineColor*: Color
  inlayContainCursor*: bool
  scopeIsToken*: bool = true
  canWrap*: bool = true

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
  Insert(insertStartByte: int, insertEndByte: int, insertStartColumn: int, insertEndColumn: int, insertStartLine: int, insertEndLine: int)
  Delete(deleteStartByte: int, deleteEndByte: int, deleteStartColumn: int, deleteEndColumn: int, deleteStartLine: int, deleteEndLine: int)

type TextDocument* = ref object of Document
  lines*: seq[string]
  lineIds*: seq[int32]
  languageId*: string
  version*: int

  nextLineIdCounter: int32 = 0

  isLoadingAsync*: bool = false

  onLoaded*: Event[TextDocument]
  onSaved*: Event[void]
  textChanged*: Event[TextDocument]
  textInserted*: Event[tuple[document: TextDocument, location: Selection, text: string]]
  textDeleted*: Event[tuple[document: TextDocument, location: Selection]]
  singleLine*: bool = false
  readOnly*: bool = false
  staged*: bool = false

  changes: seq[TextDocumentChange]

  configProvider: ConfigProvider
  languageConfig*: Option[TextLanguageConfig]
  indentStyle*: IndentStyle
  createLanguageServer*: bool = true

  undoOps*: seq[UndoOp]
  redoOps*: seq[UndoOp]
  nextCheckpoints: seq[string]

  tsParser: TSParser
  tsLanguage: TSLanguage
  currentTree: TSTree
  highlightQuery: TSQuery
  errorQuery: TSQuery

  languageServer*: Option[LanguageServer]
  onRequestSaveHandle*: OnRequestSaveHandle

  styledTextCache: Table[int, StyledLine]

  diagnosticsPerLine*: Table[int, seq[int]]
  currentDiagnostics*: seq[Diagnostic]
  onDiagnosticsUpdated*: Event[void]
  onDiagnosticsHandle: Id

var allTextDocuments*: seq[TextDocument] = @[]

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
  var textSizeBytes = 0
  for l in self.lines:
    textSizeBytes += l.len

  result.add &"Filename: {self.filename}\n"
  result.add &"Lines: {self.lines.len}\n"
  result.add &"Line Ids: {self.lineIds.len}\n"
  result.add &"Text: {textSizeBytes} bytes\n"
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

proc getLine*(self: TextDocument, line: int): string =
  if line < self.lines.len:
    return self.lines[line]
  return ""

proc lineLength*(self: TextDocument, line: int): int =
  if line >= 0 and line < self.lines.len:
    return self.lines[line].len
  return 0

proc lastValidIndex*(self: TextDocument, line: int, includeAfter: bool = true): int =
  if line < self.lines.len:
    if includeAfter or self.lines[line].len == 0:
      return self.lines[line].len
    else:
      return self.lines[line].runeStart(self.lines[line].len - 1)
  return 0

proc lastCursor*(self: TextDocument): Cursor =
  if self.lines.len > 0:
    return (self.lines.high, self.lastValidIndex(self.lines.high))
  return (0, 0)

proc clampCursor*(self: TextDocument, cursor: Cursor, includeAfter: bool = true): Cursor =
  var cursor = cursor
  if self.lines.len == 0:
    return (0, 0)
  cursor.line = clamp(cursor.line, 0, self.lines.len - 1)
  cursor.column = clamp(cursor.column, 0, self.lastValidIndex(cursor.line, includeAfter))
  return cursor

proc clampSelection*(self: TextDocument, selection: Selection, includeAfter: bool = true): Selection = (self.clampCursor(selection.first, includeAfter), self.clampCursor(selection.last, includeAfter))
proc clampAndMergeSelections*(self: TextDocument, selections: openArray[Selection]): Selections = selections.map((s) => self.clampSelection(s)).deduplicate
proc getLanguageServer*(self: TextDocument): Future[Option[LanguageServer]] {.async.}
proc trimTrailingWhitespace*(self: TextDocument)

proc notifyTextChanged*(self: TextDocument) =
  self.textChanged.invoke self
  self.styledTextCache.clear()

proc applyTreesitterChanges(self: TextDocument) =
  if self.currentTree.isNotNil:
    for change in self.changes:
      let edit = (block:
        match change:
          Insert(startByte, endByte, startColumn, endColumn, startLine, endLine):
            TSInputEdit(
              startIndex: startByte,
              oldEndIndex: startByte,
              newEndIndex: endByte,
              startPosition: TSPoint(row: startLine, column: startColumn),
              oldEndPosition: TSPoint(row: startLine, column: startColumn),
              newEndPosition: TSPoint(row: endLine, column: endColumn),
            )
          Delete(startByte, endByte, startColumn, endColumn, startLine, endLine):
            TSInputEdit(
              startIndex: startByte,
              oldEndIndex: endByte,
              newEndIndex: startByte,
              startPosition: TSPoint(row: startLine, column: startColumn),
              oldEndPosition: TSPoint(row: endLine, column: endColumn),
              newEndPosition: TSPoint(row: startLine, column: startColumn),
            )
      )

      discard self.currentTree.edit(edit)

  self.changes.setLen 0

proc reparseTreesitter*(self: TextDocument) =
  self.applyTreesitterChanges()
  if self.tsParser.isNotNil:
    let strValue = self.lines.join("\n")
    if self.currentTree.isNotNil:
      self.currentTree = self.tsParser.parseString(strValue, self.currentTree.some)
    else:
      self.currentTree = self.tsParser.parseString(strValue)

proc tsTree*(self: TextDocument): TsTree =
  if self.changes.len > 0 or self.currentTree.isNil:
    self.reparseTreesitter()
  return self.currentTree

proc `content=`*(self: TextDocument, value: string) =
  self.revision.inc
  self.undoableRevision.inc

  if self.singleLine:
    self.lines = @[value.replace("\n", "")]
    if self.lines.len == 0:
      self.lines = @[""]
  else:
    self.lines = value.splitLines
    if self.lines.len == 0:
      self.lines = @[""]

  self.lineIds.setLen self.lines.len
  for id in self.lineIds.mitems:
    id = self.nextLineId

  self.currentTree.delete()
  self.reparseTreesitter()

  inc self.version

  self.notifyTextChanged()

proc `content=`*(self: TextDocument, value: seq[string]) =
  self.revision.inc
  self.undoableRevision.inc

  if self.singleLine:
    self.lines = @[value.join("")]
  else:
    self.lines = value.toSeq

  if self.lines.len == 0:
    self.lines = @[""]

  self.lineIds.setLen self.lines.len
  for id in self.lineIds.mitems:
    id = self.nextLineId

  self.currentTree.delete()
  self.reparseTreesitter()

  inc self.version

  self.notifyTextChanged()

func content*(self: TextDocument): seq[string] =
  return self.lines

func contentString*(self: TextDocument): string =
  return self.lines.join("\n")

func contentString*(self: TextDocument, selection: Selection, inclusiveEnd: bool = false): string =
  let (first, last) = selection.normalized

  let lastLineLen = self.lines[last.line].len
  let lastColumn = if inclusiveEnd and self.lines[last.line].len > 0:
    self.lines[last.line].nextRuneStart(min(last.column, lastLineLen - 1))
  else:
    last.column

  let firstColumn = first.column.clamp(0, self.lines[first.line].len)

  if first.line == last.line:
    return self.lines[first.line][firstColumn..<lastColumn]

  result = self.lines[first.line][firstColumn..^1]
  for i in (first.line + 1)..<last.line:
    result.add "\n"
    result.add self.lines[i]

  result.add "\n"

  result.add self.lines[last.line][0..<lastColumn]

func contentString*(self: TextDocument, selection: TSRange): string =
  return self.contentString selection.toSelection

func charAt*(self: TextDocument, cursor: Cursor): char =
  if cursor.line < 0 or cursor.line > self.lines.high:
    return 0.char
  if cursor.column < 0 or cursor.column > self.lines[cursor.line].high:
    return 0.char
  return self.lines[cursor.line][cursor.column]

func runeAt*(self: TextDocument, cursor: Cursor): Rune =
  if cursor.line < 0 or cursor.line > self.lines.high:
    return 0.Rune
  if cursor.column < 0 or cursor.column > self.lines[cursor.line].high:
    return 0.Rune
  return self.lines[cursor.line].runeAt(cursor.column)

proc lspRangeToSelection*(self: TextDocument, `range`: lsp_types.Range): Selection =
  if `range`.start.line > self.lines.high or `range`.end.line > self.lines.high:
    return (0, 0).toSelection

  let firstColumn = self.lines[`range`.start.line].runeOffset(`range`.start.character.RuneIndex)
  let lastColumn = self.lines[`range`.`end`.line].runeOffset(`range`.`end`.character.RuneIndex)
  return ((`range`.start.line, firstColumn), (`range`.`end`.line, lastColumn))

proc runeCursorToCursor*(self: TextDocument, cursor: CursorT[RuneIndex]): Cursor =
  if cursor.line < 0 or cursor.line > self.lines.high:
    return (0, 0)

  return (cursor.line, self.lines[cursor.line].runeOffset(min(self.lines[cursor.line].runeLen.RuneIndex, max(0.RuneIndex, cursor.column))))

proc runeSelectionToSelection*(self: TextDocument, cursor: SelectionT[RuneIndex]): Selection =
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
  let line {.cursor.} = self.getLine(line)
  var column = 0
  let tabWidth = self.tabWidth

  for i, c in line:
    result = i

    if c == '\t':
      column = align(column + 1, tabWidth)
    else:
      column += 1

    if column > visualColumn:
      return

  return line.len

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
  line.splitAt(self.lines[line.index].toOpenArray.runeIndex(index, returnLen=true))

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
  line.overrideStyle(self.lines[line.index].toOpenArray.runeIndex(first, returnLen=true), self.lines[line.index].toOpenArray.runeIndex(last, returnLen=true), scope, priority)

proc overrideUnderline*(self: TextDocument, line: var StyledLine, first: int, last: int, underline: bool, color: Color) =
  line.overrideUnderline(self.lines[line.index].toOpenArray.runeIndex(first, returnLen=true), self.lines[line.index].toOpenArray.runeIndex(last, returnLen=true), underline, color)

proc overrideStyleAndText*(self: TextDocument, line: var StyledLine, first: int, text: string, scope: string, priority: int, opacity: Option[float] = float.none, joinNext: bool = false) =
  line.overrideStyleAndText(self.lines[line.index].toOpenArray.runeIndex(first, returnLen=true), text, scope, priority, opacity, joinNext)

proc insertText*(self: TextDocument, line: var StyledLine, offset: RuneIndex, text: string, scope: string, containCursor: bool) =
  line.splitAt(offset)
  for i in 0..line.parts.high:
    if line.parts[i].textRange.getSome(r):
      if offset == r.endIndex:
        line.parts.insert(StyledText(text: text, scope: scope, scopeC: scope.cstring, priority: 1000000000, inlayContainCursor: containCursor), i + 1)
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
  if self.tsParser.isNil or self.errorQuery.isNil or self.tsTree.isNil:
    return

  for match in self.errorQuery.matches(self.tsTree.root, tsRange(tsPoint(selection.first.line, 0), tsPoint(selection.last.line, 0))):
    for capture in match.captures:
      result.add capture.node.getRange.toSelection

proc replaceSpaces(self: TextDocument, line: var StyledLine) =
  # override whitespace
  let opacity = self.configProvider.getValue("editor.text.whitespace.opacity", 0.4)
  let ch = self.configProvider.getValue("editor.text.whitespace.char", "·")
  if opacity <= 0:
    return

  let pattern = re"[ ]+"
  let bounds = self.lines[line.index].findAllBounds(line.index, pattern)
  for s in bounds:
    line.splitAt(self.lines[line.index].toOpenArray.runeIndex(s.first.column, returnLen=true))
    line.splitAt(self.lines[line.index].toOpenArray.runeIndex(s.last.column, returnLen=true))

  for s in bounds:
    let start = self.lines[line.index].toOpenArray.runeIndex(s.first.column, returnLen=true)
    let text = ch.repeat(s.last.column - s.first.column)
    line.overrideStyleAndText(start, text, "comment", 0, opacity=opacity.some)

proc replaceTabs(self: TextDocument, line: var StyledLine) =
  let opacity = self.configProvider.getValue("editor.text.whitespace.opacity", 0.4)
  let pattern = re"\t"
  let bounds = self.lines[line.index].findAllBounds(line.index, pattern)
  for s in bounds:
    line.splitAt(self.lines[line.index].toOpenArray.runeIndex(s.first.column, returnLen=true))
    line.splitAt(self.lines[line.index].toOpenArray.runeIndex(s.last.column, returnLen=true))

  if bounds.len == 0:
    return

  let tabWidth = self.tabWidth
  var currentOffset = 0
  var previousEnd = 0

  for s in bounds:
    currentOffset += s.first.column - previousEnd

    let alignCorrection = currentOffset mod tabWidth
    let currentTabWidth = tabWidth - alignCorrection
    let t = "|"
    let runeIndex = self.lines[line.index].toOpenArray.runeIndex(s.first.column, returnLen=true)
    line.overrideStyleAndText(runeIndex, t, "comment", 0, opacity=opacity.some)
    if currentTabWidth > 1:
      self.insertText(line, runeIndex + 1.RuneCount, " ".repeat(currentTabWidth - 1), "comment", containCursor=false)

    currentOffset += currentTabWidth
    previousEnd = s.last.column

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
        of Error: "editorError.foreground"
        of Warning: "editorWarning.foreground"
        of Information: "editorInfo.foreground"
        of Hint: "editorHint.foreground"
      else:
        "editorHint.foreground"

      let color = if gTheme.isNotNil:
        gTheme.color(colorName, color(1, 1, 1))
      elif diagnostic.severity.getSome(severity):
        case severity
        of Error: color(1, 0, 0)
        of Warning: color(1, 0.8, 0.2)
        of Information: color(1, 1, 1)
        of Hint: color(0.7, 0.7, 0.7)
      else:
        color(0.7, 0.7, 0.7)

      line.splitAt(self.lines[line.index].toOpenArray.runeIndex(diagnostic.selection.first.column, returnLen=true))
      line.splitAt(self.lines[line.index].toOpenArray.runeIndex(diagnostic.selection.last.column, returnLen=true))
      self.overrideUnderline(line, diagnostic.selection.first.column, diagnostic.selection.last.column, true, color)

      let newLineIndex = diagnostic.message.find("\n")
      let maxIndex = if newLineIndex != -1:
        newLineIndex
      else:
        diagnostic.message.len

      let diagnosticMessage: string = "     ■ " & diagnostic.message[0..<maxIndex]
      line.parts.add StyledText(text: diagnosticMessage, scope: colorName, scopeC: colorName.cstring, inlayContainCursor: true, scopeIsToken: false, canWrap: false, priority: 1000000000)


proc applyTreesitterHighlighting(self: TextDocument, line: var StyledLine) =
  var regexes = initTable[string, Regex]()

  if self.tsParser.isNil or self.highlightQuery.isNil or self.tsTree.isNil:
    return

  let lineLen = self.lines[line.index].len

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
            let regex = if regexes.contains(value):
              regexes[value]
            else:
              let regex = re(value)
              regexes[value] = regex
              regex

            let nodeText = self.contentString(node.getRange)
            if nodeText.matchLen(regex, 0) != nodeText.len:
              matches = false
              break

          of "not-match?":
            let regex = if regexes.contains(value):
              regexes[value]
            else:
              let regex = re(value)
              regexes[value] = regex
              regex

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
            log(lvlError, fmt"Unknown predicate '{predicate.operator}'")

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
    if i >= self.lines.len:
      log lvlError, fmt"getStyledText({i}) out of range {self.lines.len}"
      return StyledLine()

    var line = self.lines[i]
    result = StyledLine(index: i, parts: @[StyledText(text: line, scope: "", scopeC: "", priority: 1000000000, textRange: (0, line.len, 0.RuneIndex, line.runeLen.RuneIndex).some)])
    self.styledTextCache[i] = result

    self.applyTreesitterHighlighting(result)
    self.replaceSpaces(result)
    self.replaceTabs(result)
    self.addDiagnosticsUnderline(result)

proc initTreesitter*(self: TextDocument): Future[void] {.async.} =
  if not self.tsParser.isNil:
    self.tsParser.deinit()
    self.tsParser = nil
  if not self.highlightQuery.isNil:
    self.highlightQuery.deinit()
    self.highlightQuery = nil
  if not self.errorQuery.isNil:
    self.errorQuery.deinit()
    self.errorQuery = nil

  self.styledTextCache.clear()

  let languageId = self.languageId

  let config = self.configProvider.getValue("editor.text.treesitter." & languageId, newJObject())
  var language = await loadLanguage(languageId, config)

  if language.isNone:
    log(lvlWarn, fmt"Treesitter language is not available for '{languageId}'")
    return

  self.tsParser = createTSParser()
  if self.tsParser.isNil:
    log(lvlWarn, fmt"Failed to create treesitter parser for '{languageId}'")
    return

  self.tsParser.setLanguage(language.get)
  self.tsLanguage = language.get

  self.reparseTreesitter()

  try:
    let queryString = fs.loadApplicationFile(fmt"./languages/{languageId}/queries/highlights.scm")
    self.highlightQuery = language.get.query(queryString)
    if self.highlightQuery.isNil:
      log(lvlError, fmt"Failed to create highlight query for '{languageId}'")
  except CatchableError:
    log(lvlError, fmt"No highlight queries found for '{languageId}'")

  try:
    var errorQueryString = fs.loadApplicationFile(fmt"./languages/{languageId}/queries/errors.scm")
    if errorQueryString.len == 0:
      errorQueryString = "(ERROR) @error"
    self.errorQuery = language.get.query(errorQueryString)
    if self.errorQuery.isNil:
      log(lvlError, fmt"Failed to create error query for '{languageId}'")
  except CatchableError:
    log(lvlError, fmt"No error queries found for '{languageId}'")

  # We now have a treesitter grammar + highlight query, so retrigger rendering
  self.notifyTextChanged()

proc newTextDocument*(
    configProvider: ConfigProvider,
    filename: string = "",
    content: string = "",
    app: bool = false,
    workspaceFolder: Option[WorkspaceFolder] = WorkspaceFolder.none,
    language: Option[string] = string.none,
    languageServer: Option[LanguageServer] = LanguageServer.none,
    load: bool = false,
    createLanguageServer: bool = true): TextDocument =

  new(result)
  allTextDocuments.add result

  var self = result
  self.filename = filename.normalizePathUnix
  self.currentTree = nil
  self.appFile = app
  self.workspace = workspaceFolder
  self.configProvider = configProvider
  self.createLanguageServer = createLanguageServer

  self.indentStyle = IndentStyle(kind: Spaces, spaces: 2)

  if language.getSome(language):
    self.languageId = language
  elif getLanguageForFile(filename).getSome(language):
    self.languageId = language

  if self.languageId != "":
    if (let value = self.configProvider.getValue("editor.text.language." & self.languageId, newJNull()); value.kind == JObject):
      self.languageConfig = value.jsonTo(TextLanguageConfig, Joptions(allowExtraKeys: true, allowMissingKeys: true)).some
      if value.hasKey("indent"):
        case value["indent"].str:
        of "spaces":
          self.indentStyle = IndentStyle(kind: Spaces, spaces: self.languageConfig.map((c) => c.tabWidth).get(4))
        of "tabs":
          self.indentStyle = IndentStyle(kind: Tabs)

  asyncCheck self.initTreesitter()

  self.languageServer = languageServer
  if self.languageServer.getSome(ls):
    # debugf"register save handler '{self.filename}'"
    let callback = proc (targetFilename: string): Future[void] {.async.} =
      # debugf"save temp file '{targetFilename}'"
      if self.languageServer.getSome(ls):
        await ls.saveTempFile(targetFilename, self.contentString)
    self.onRequestSaveHandle = ls.addOnRequestSaveHandler(self.filename, callback)

  elif createLanguageServer and self.configProvider.getValue("editor.text.auto-start-language-server", false) and self.languageServer.isNone:
      asyncCheck self.getLanguageServer()

      # debugf"using language for {filename}: {value}, {self.indentStyle}"

  self.content = content

  if load:
    self.load()

method deinit*(self: TextDocument) =
  log lvlInfo, fmt"Destroying text document '{self.filename}'"
  if self.highlightQuery.isNotNil:
    self.highlightQuery.deinit()
  if not self.errorQuery.isNil:
    self.errorQuery.deinit()
    self.errorQuery = nil

  if not self.tsParser.isNil:
    self.tsParser.deinit()

  if self.languageServer.getSome(ls):
    ls.onDiagnostics.unsubscribe(self.onDiagnosticsHandle)
    ls.removeOnRequestSaveHandler(self.onRequestSaveHandle)
    ls.disconnect()
    self.languageServer = LanguageServer.none

  let i = allTextDocuments.find(self)
  allTextDocuments.removeSwap(i)

  self[] = default(typeof(self[]))

method `$`*(self: TextDocument): string =
  return self.filename

method save*(self: TextDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: filename.normalizePathUnix else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  if self.staged:
    return

  self.appFile = app

  self.onSaved.invoke()

  self.trimTrailingWhitespace()

  if self.workspace.getSome(ws):
    asyncCheck ws.saveFile(self.filename, self.contentString)
  elif self.appFile:
    fs.saveApplicationFile(self.filename, self.contentString)
  else:
    fs.saveFile(self.filename, self.contentString)

  self.isBackedByFile = true
  self.lastSavedRevision = self.undoableRevision

proc autoDetectIndentStyle(self: TextDocument) =
  var containsTab = false
  for line in self.lines:
    if line.find('\t') != -1:
      containsTab = true
      break

  if containsTab:
    self.indentStyle = IndentStyle(kind: Tabs)
  else:
    self.indentStyle = IndentStyle(kind: Spaces, spaces: self.tabWidth)

  log lvlInfo, &"[Text_document] Detected indent: {self.indentStyle}, {self.languageConfig.get(TextLanguageConfig())[]}"

proc loadAsync(self: TextDocument, ws: WorkspaceFolder): Future[void] {.async.} =
  # self.content = await ws.loadFile(self.filename)
  self.isBackedByFile = true
  self.isLoadingAsync = true
  self.content = catch ws.loadFile(self.filename).await:
    log lvlError, &"[loadAsync] Failed to load workspace file {self.filename}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    ""

  self.autoDetectIndentStyle()

  self.lastSavedRevision = self.undoableRevision
  self.isLoadingAsync = false
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
    self.content = catch fs.loadApplicationFile(self.filename):
      log lvlError, fmt"Failed to load application file {filename}"
      ""
    self.lastSavedRevision = self.undoableRevision
    self.autoDetectIndentStyle()
    self.onLoaded.invoke self
  else:
    self.content = catch fs.loadFile(self.filename):
      log lvlError, fmt"Failed to load file {filename}"
      ""
    self.lastSavedRevision = self.undoableRevision
    self.autoDetectIndentStyle()
    self.onLoaded.invoke self

proc getLanguageServer*(self: TextDocument): Future[Option[LanguageServer]] {.async.} =
  let languageId = if self.languageId != "":
    self.languageId
  elif getLanguageForFile(self.filename).getSome(languageId):
    languageId
  else:
    return LanguageServer.none

  if self.languageServer.isSome:
    return self.languageServer

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

  self.languageServer = await getOrCreateLanguageServer(languageId, self.filename, workspaces, config, self.workspace)
  if self.languageServer.getSome(ls):
    ls.connect()
    let callback = proc (targetFilename: string): Future[void] {.async.} =
      if self.languageServer.getSome(ls):
        await ls.saveTempFile(targetFilename, self.contentString)

    self.onRequestSaveHandle = ls.addOnRequestSaveHandler(self.filename, callback)

    self.onDiagnosticsHandle = ls.onDiagnostics.subscribe proc(diagnostics: lsp_types.PublicDiagnosticsParams) =
      let uri = diagnostics.uri.decodeUrl.parseUri
      if uri.path.normalizePathUnix == self.filename:
        self.currentDiagnostics.setLen diagnostics.diagnostics.len
        self.diagnosticsPerLine.clear()

        for i, d in diagnostics.diagnostics:
          let selection = self.runeSelectionToSelection(((d.`range`.start.line, d.`range`.start.character.RuneIndex), (d.`range`.`end`.line, d.`range`.`end`.character.RuneIndex)))
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

        self.styledTextCache.clear()
        self.onDiagnosticsUpdated.invoke()

  return self.languageServer

proc clearDiagnostics*(self: TextDocument) =
  self.diagnosticsPerLine.clear()
  self.currentDiagnostics.setLen 0
  self.styledTextCache.clear()

proc clearStyledTextCache*(self: TextDocument) =
  self.styledTextCache.clear()

proc byteOffset*(self: TextDocument, cursor: Cursor): int =
  result = cursor.column
  for i in 0..<cursor.line:
    result += self.lines[i].len + 1

proc tabWidth*(self: TextDocument): int =
  return self.languageConfig.map(c => c.tabWidth).get(4)

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

  template currentLine: openArray[char] = self.lines[cursor.line].toOpenArray

  if offset > 0:
    for i in 0..<offset:
      if column == currentLine.len:
        if not wrap:
          break
        if cursor.line < self.lines.high:
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
    if c != ' ':
      break
    result += 1

proc lineStartsWith*(self: TextDocument, line: int, text: string, ignoreWhitespace: bool): bool =
  if ignoreWhitespace:
    let index = self.lines[line].firstNonWhitespace
    return self.lines[line][index..^1].startsWith(text)
  else:
    return self.lines[line].startsWith(text)

proc lastNonWhitespace*(str: string): int =
  result = str.high
  while result >= 0:
    if str[result] != ' ' and str[result] != '\t':
      break
    result -= 1

proc getIndentForLine*(self: TextDocument, line: int): int =
  if line < 0 or line >= self.lines.len:
    return 0
  return self.lines[line].firstNonWhitespace

proc getIndentLevelForLine*(self: TextDocument, line: int): int =
  if line < 0 or line >= self.lines.len:
    return 0
  let indentWidth = self.indentStyle.indentWidth(self.tabWidth)
  return indentLevelForLine(self.lines[line], self.tabWidth, indentWidth)

proc getIndentLevelForClosestLine*(self: TextDocument, line: int): int =
  for i in line..self.lines.high:
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
  for d in self.currentDiagnostics.mitems:
    d.selection.first = self.updateCursorAfterInsert(d.selection.first, inserted)
    d.selection.last = self.updateCursorAfterInsert(d.selection.last, inserted)

proc updateDiagnosticPositionsAfterDelete(self: TextDocument, selection: Selection) =
  let selection = selection.normalized
  for i in countdown(self.currentDiagnostics.high, 0):
    if self.updateCursorAfterDelete(self.currentDiagnostics[i].selection.first, selection).getSome(first) and
        self.updateCursorAfterDelete(self.currentDiagnostics[i].selection.last, selection).getSome(last):
      self.currentDiagnostics[i].selection = (first, last)
    else:
      self.currentDiagnostics[i].removed = true

proc insert*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], texts: openArray[string], notify: bool = true, record: bool = true): seq[Selection] =
  # be careful with logging inside this function, because the logs are written to another document using this function to insert, which can cause infinite recursion
  # when inserting a log line logs something.
  # Use echo for debugging instead

  result = self.clampAndMergeSelections selections

  if self.readOnly:
    return

  self.revision.inc
  self.undoableRevision.inc

  var undoOp = UndoOp(kind: Nested, children: @[], oldSelection: @oldSelection)

  var startNewCheckpoint = false
  var checkInsertedTextForCheckpoint = false

  if self.undoOps.len == 0:
    startNewCheckpoint = true
  elif self.undoOps.last.kind == Insert:
    startNewCheckpoint = true
  elif self.undoOps.last.kind == Nested and self.undoOps.last.children.len != result.len:
    startNewCheckpoint = true
  elif self.undoOps.last.kind in {Nested, Delete}:
    checkInsertedTextForCheckpoint = true

  for i, selection in result:
    let text = if texts.len == 1:
      texts[0]
    elif texts.len == result.len:
      texts[i]
    else:
      texts[min(i, texts.high)]

    let oldCursor = selection.last
    var cursor = selection.last
    let startByte = self.byteOffset(cursor)

    var cursorColumnRune = self.lines[cursor.line].toOpenArray.runeIndex(cursor.column)

    var lineCounter: int = 0
    if self.singleLine:
      let text = text.replace("\n", " ")
      if self.lines.len == 0:
        self.lines.add text
        self.lineIds.add self.nextLineId
        assert self.lines.len == self.lineIds.len
      else:
        self.lines[0].insert(text, cursor.column)
      cursor.column += text.len
      cursorColumnRune += text.runeLen

    else:
      for line in text.splitLines(false):
        defer: inc lineCounter
        if lineCounter > 0:
          # Split line
          self.lines.insert(self.lines[cursor.line][cursor.column..^1], cursor.line + 1)
          self.lineIds.insert(self.nextLineId, cursor.line + 1)
          assert self.lines.len == self.lineIds.len

          if cursor.column < self.lastValidIndex cursor.line:
            self.lines[cursor.line].delete(cursor.column..<(self.lineLength cursor.line))
          cursor = (cursor.line + 1, 0)

        if line.len > 0:
          self.lines[cursor.line].insert(line, cursor.column)
          cursor.column += line.len
          cursorColumnRune += line.runeLen

    result[i] = (oldCursor, cursor)
    for k in (i+1)..result.high:
      result[k] = result[k].add((oldCursor, cursor))

    if not self.tsParser.isNil:
      let (_, end_column) = traverse(oldCursor.line, oldCursor.column, text)
      self.changes.add(Insert(startByte, startByte + text.len, oldCursor.column, end_column, oldCursor.line, cursor.line))

    inc self.version

    if record:
      if checkInsertedTextForCheckpoint:
        # echo fmt"kind: {self.undoOps.last.kind}, len: {self.undoOps.last.children.len} == {result.len}, child kind: {self.undoOps.last.children[i].kind}, cursor {self.undoOps.last.children[i].selection.last} != {oldCursor}"
        if text.len > 1:
          startNewCheckpoint = true
        elif self.undoOps.len > 0 and self.undoOps.last.kind == Nested and self.undoOps.last.children.len == result.len and result.len > i and self.undoOps.last.children[i].kind == Delete:
          if self.undoOps.last.children[i].selection.last != oldCursor:
            startNewCheckpoint = true
          else:
            let lastInsertedChar = if oldCursor.column == 0: '\n' else: self.charAt(self.moveCursorColumn(oldCursor, -1))
            let newInsertedChar = text[0]
            # echo fmt"last: '{lastInsertedChar}', new: '{newInsertedChar}'"

            if lastInsertedChar notin Whitespace and newInsertedChar in Whitespace or lastInsertedChar == '\n':
              startNewCheckpoint = true

      undoOp.children.add UndoOp(kind: Delete, selection: (oldCursor, cursor))

    self.updateDiagnosticPositionsAfterInsert (oldCursor, cursor)
    if notify:
      self.textInserted.invoke((self, (oldCursor, cursor), text))

  if notify:
    self.notifyTextChanged()

  if record and undoOp.children.len > 0:
    if startNewCheckpoint:
      undoOp.checkpoints.add "word"
    undoOp.checkpoints.add self.nextCheckpoints

    self.undoOps.add undoOp
    self.redoOps = @[]

    self.nextCheckpoints = @[]

proc delete*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =
  result = self.clampAndMergeSelections selections

  if self.readOnly:
    return

  self.revision.inc
  self.undoableRevision.inc

  var undoOp = UndoOp(kind: Nested, children: @[], oldSelection: @oldSelection)

  for i, selectionRaw in result:
    let normalizedSelection = selectionRaw.normalized
    let selection: Selection = if inclusiveEnd and self.lines[normalizedSelection.last.line].len > 0:
      let nextColumn = self.lines[normalizedSelection.last.line].nextRuneStart(min(normalizedSelection.last.column, self.lines[normalizedSelection.last.line].high)).int
      (normalizedSelection.first, (normalizedSelection.last.line, nextColumn))
    else:
      normalizedSelection

    if selection.isEmpty:
      continue

    let (first, last) = selection

    let startByte = self.byteOffset(first)
    let endByte = self.byteOffset(last)

    let deletedText = self.contentString(selection)

    if first.line == last.line:
      # Single line selection
      self.lines[last.line].delete first.column..<last.column
    else:
      # Multi line selection
      # Delete from first cursor to end of first line and add last line
      if first.column < self.lastValidIndex first.line:
        self.lines[first.line].delete(first.column..<(self.lineLength first.line))
      self.lines[first.line].add self.lines[last.line][last.column..^1]
      # Delete all lines in between
      assert self.lines.len == self.lineIds.len
      self.lines.delete (first.line + 1)..last.line
      self.lineIds.delete (first.line + 1)..last.line

    result[i] = selection.first.toSelection
    for k in (i+1)..result.high:
      result[k] = result[k].subtract(selection)

    if not self.tsParser.isNil:
      self.changes.add(Delete(startByte, endByte, first.column, last.column, selection.first.line, selection.last.line))

    inc self.version

    if record:
      undoOp.children.add UndoOp(kind: Insert, cursor: selection.first, text: deletedText)

    self.updateDiagnosticPositionsAfterDelete selection
    if notify:
      self.textDeleted.invoke((self, selection))

  if notify:
    self.notifyTextChanged()

  if record and undoOp.children.len > 0:
    undoOp.checkpoints.add self.nextCheckpoints
    self.undoOps.add undoOp
    self.redoOps = @[]

    self.nextCheckpoints = @[]

proc edit*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], texts: openArray[string], notify: bool = true, record: bool = true, inclusiveEnd: bool = false): seq[Selection] =
  let selections = selections.map (s) => s.normalized
  result = self.delete(selections, oldSelection, record=record, inclusiveEnd=inclusiveEnd)
  result = self.insert(result, oldSelection, texts, record=record)

proc doUndo(self: TextDocument, op: UndoOp, oldSelection: openArray[Selection], useOldSelection: bool, redoOps: var seq[UndoOp]): seq[Selection] =
  case op.kind:
  of Delete:
    let text = self.contentString(op.selection)
    result = self.delete([op.selection], op.oldSelection, record=false)
    redoOps.add UndoOp(kind: Insert, revision: self.undoableRevision, cursor: op.selection.first, text: text, oldSelection: @oldSelection, checkpoints: op.checkpoints)

  of Insert:
    let selections = self.insert([op.cursor.toSelection], op.oldSelection, [op.text], record=false)
    result = selections
    redoOps.add UndoOp(kind: Delete, revision: self.undoableRevision, selection: (op.cursor, selections[0].last), oldSelection: @oldSelection, checkpoints: op.checkpoints)

  of Nested:
    result = op.oldSelection

    var redoOp = UndoOp(kind: Nested, revision: self.undoableRevision, oldSelection: @oldSelection, checkpoints: op.checkpoints)
    for i in countdown(op.children.high, 0):
      discard self.doUndo(op.children[i], oldSelection, useOldSelection, redoOp.children)

    redoOps.add redoOp

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
  case op.kind:
  of Delete:
    let text = self.contentString(op.selection)
    result = self.delete([op.selection], op.oldSelection, record=false)
    undoOps.add UndoOp(kind: Insert, revision: self.undoableRevision, cursor: op.selection.first, text: text, oldSelection: @oldSelection, checkpoints: op.checkpoints)

  of Insert:
    result = self.insert([op.cursor.toSelection], [op.cursor.toSelection], [op.text], record=false)
    undoOps.add UndoOp(kind: Delete, revision: self.undoableRevision, selection: (op.cursor, result[0].last), oldSelection: @oldSelection, checkpoints: op.checkpoints)

  of Nested:
    result = op.oldSelection

    var undoOp = UndoOp(kind: Nested, revision: self.undoableRevision, oldSelection: @oldSelection, checkpoints: op.checkpoints)
    for i in countdown(op.children.high, 0):
      discard self.doRedo(op.children[i], oldSelection, useOldSelection, undoOp.children)

    undoOps.add undoOp

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
  if line > self.lines.high:
    return false
  return self.lines[line].isEmptyOrWhitespace

proc isLineCommented*(self: TextDocument, line: int): bool =
  if line > self.lines.high or self.languageConfig.isNone or self.languageConfig.get.lineComment.isNone:
    return false
  return custom_unicode.strip(self.lines[line], trailing=false).startsWith(self.languageConfig.get.lineComment.get)

proc getLineCommentRange*(self: TextDocument, line: int): Selection =
  if line > self.lines.high or self.languageConfig.isNone or self.languageConfig.get.lineComment.isNone:
    return (line, 0).toSelection

  let prefix = self.languageConfig.get.lineComment.get
  let index = self.lines[line].find(prefix)
  if index == -1:
    return (line, 0).toSelection

  var endIndex = index + prefix.len
  if endIndex < self.lineLength(line) and self.lines[line][endIndex] in Whitespace:
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
        minIndent = min(minIndent, self.getIndentForLine(l))

    for l in s.first.line..s.last.line:
      if not self.isLineEmptyOrWhitespace(l):
        if comment:
          insertSelections.add (l, minIndent).toSelection
        else:
          insertSelections.add self.getLineCommentRange(l)

  if comment:
    let prefix = self.languageConfig.get.lineComment.get & " "
    discard self.insert(insertSelections, selections, [prefix])
  else:
    discard self.delete(insertSelections, selections)

proc trimTrailingWhitespace*(self: TextDocument) =
  var selections: seq[Selection]
  for i in 0..self.lines.high:
    let index = self.lines[i].lastNonWhitespace
    if index == self.lines[i].high:
      continue
    selections.add ((i, index + 1), (i, self.lines[i].len))

  if selections.len > 0:
    discard self.delete(selections, selections)
