import std/[strutils, logging, sequtils, sugar, options, json, strformat, tables]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import document, document_editor, id, util, event, ../regex, custom_logger, custom_async, custom_treesitter, indent
import text_language_config
import platform/[platform, filesystem, widgets]
import language/[languages, language_server_base]
import workspaces/[workspace]
import config_provider

export document, document_editor, id

type
  UndoOpKind = enum
    Delete
    Insert
    Nested
  UndoOp = ref object
    oldSelection: seq[Selection]
    case kind: UndoOpKind
    of Delete:
      selection: Selection
    of Insert:
      cursor: Cursor
      text: string
    of Nested:
      children: seq[UndoOp]

proc `$`*(op: UndoOp): string =
  result = fmt"{{{op.kind} ({op.oldSelection})"
  if op.kind == Delete: result.add fmt", selections = {op.selection}}}"
  if op.kind == Insert: result.add fmt", selections = {op.cursor}, text: '{op.text}'}}"
  if op.kind == Nested: result.add fmt", {op.children}}}"

type StyledText* = object
  text*: string
  scope*: string
  priority*: int
  bounds*: Rect

type StyledLine* = ref object
  index*: int
  parts*: seq[StyledText]

type TextDocument* = ref object of Document
  lines*: seq[string]
  languageId*: string
  version*: int

  onLoaded*: Event[TextDocument]
  textChanged*: Event[TextDocument]
  textInserted*: Event[tuple[document: TextDocument, location: Cursor, text: string]]
  textDeleted*: Event[tuple[document: TextDocument, selection: Selection]]
  singleLine*: bool

  configProvider: ConfigProvider
  languageConfig*: Option[TextLanguageConfig]
  indentStyle*: IndentStyle

  undoOps*: seq[UndoOp]
  redoOps*: seq[UndoOp]

  tsParser: TSParser
  tsLanguage: TSLanguage
  currentTree*: TSTree
  highlightQuery: TSQuery

  languageServer*: Option[LanguageServer]
  onRequestSaveHandle*: OnRequestSaveHandle

  styledTextCache: Table[int, StyledLine]

proc getLine*(self: TextDocument, line: int): string =
  if line < self.lines.len:
    return self.lines[line]
  return ""

proc lineLength*(self: TextDocument, line: int): int =
  if line < self.lines.len:
    return self.lines[line].len
  return 0

proc clampCursor*(self: TextDocument, cursor: Cursor): Cursor =
  var cursor = cursor
  if self.lines.len == 0:
    return (0, 0)
  cursor.line = clamp(cursor.line, 0, self.lines.len - 1)
  cursor.column = clamp(cursor.column, 0, self.lineLength cursor.line)
  return cursor

proc clampSelection*(self: TextDocument, selection: Selection): Selection = (self.clampCursor(selection.first), self.clampCursor(selection.last))
proc clampAndMergeSelections*(self: TextDocument, selections: openArray[Selection]): Selections = selections.map((s) => self.clampSelection(s)).deduplicate

proc notifyTextChanged(self: TextDocument) =
  self.textChanged.invoke self
  self.styledTextCache.clear()

proc `content=`*(self: TextDocument, value: string) =
  if self.singleLine:
    self.lines = @[value.replace("\n", "")]
    if self.lines.len == 0:
      self.lines = @[""]
    if not self.tsParser.isNil:
      self.currentTree = self.tsParser.parseString(self.lines[0])
  else:
    self.lines = value.splitLines
    if self.lines.len == 0:
      self.lines = @[""]
    if not self.tsParser.isNil:
      self.currentTree = self.tsParser.parseString(value)

  inc self.version

  self.notifyTextChanged()

proc `content=`*(self: TextDocument, value: seq[string]) =
  if self.singleLine:
    self.lines = @[value.join("")]
  else:
    self.lines = value.toSeq

  if self.lines.len == 0:
    self.lines = @[""]

  let strValue = value.join("\n")

  if not self.tsParser.isNil:
    self.currentTree = self.tsParser.parseString(strValue)

  inc self.version

  self.notifyTextChanged()

func content*(document: TextDocument): seq[string] =
  return document.lines

func contentString*(document: TextDocument): string =
  return document.lines.join("\n")

func contentString*(self: TextDocument, selection: Selection): string =
  let (first, last) = selection.normalized
  if first.line == last.line:
    return self.lines[first.line][first.column..<last.column]

  result = self.lines[first.line][first.column..^1]
  for i in (first.line + 1)..<last.line:
    result.add "\n"
    result.add self.lines[i]

  result.add "\n"
  result.add self.lines[last.line][0..<last.column]

func len*(line: StyledLine): int =
  result = 0
  for p in line.parts:
    result += p.text.len

proc splitAt*(line: var StyledLine, index: int) =
  var index = index
  var i = 0
  while i < line.parts.len and index >= line.parts[i].text.len:
    index -= line.parts[i].text.len
    i += 1

  if i < line.parts.len and index != 0 and index != line.parts[i].text.len:
    var copy = line.parts[i]
    line.parts[i].text = line.parts[i].text[0..<index]
    copy.text = copy.text[index..^1]
    line.parts.insert(copy, i + 1)

proc overrideStyle*(line: var StyledLine, first: int, last: int, scope: string, priority: int) =
  var index = 0
  for i in 0..line.parts.high:
    if index >= first and index + line.parts[i].text.len <= last and priority < line.parts[i].priority:
      line.parts[i].scope = scope
      line.parts[i].priority = priority
    index += line.parts[i].text.len

proc getStyledText*(self: TextDocument, i: int): StyledLine =
  if self.styledTextCache.contains(i):
    result = self.styledTextCache[i]
  else:
    var line = self.lines[i]
    result = StyledLine(index: i, parts: @[StyledText(text: line, scope: "", priority: 1000000000)])
    self.styledTextCache[i] = result

    var regexes = initTable[string, Regex]()

    if self.tsParser.isNil or self.highlightQuery.isNil or self.currentTree.isNil:
      return

    for match in self.highlightQuery.matches(self.currentTree.root, ((i, 0), (i, line.len))):
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
            #   logger.log(lvlError, fmt"Unknown predicate '{predicate.name}'")

            else:
              logger.log(lvlError, fmt"Unknown predicate '{predicate.operator}'")

          if self.configProvider.getFlag("text.print-matches", false):
            let nodeText = self.contentString(node.getRange)
            logger.log(lvlInfo, fmt"{match.pattern}: '{nodeText}' {node} (matches: {matches})")

        if not matches:
          continue

        let nodeRange = node.getRange

        if nodeRange.first.line == i:
          result.splitAt(nodeRange.first.column)
        if nodeRange.last.line == i:
          result.splitAt(nodeRange.last.column)

        let first = if nodeRange.first.line < i: 0 elif nodeRange.first.line == i: nodeRange.first.column else: line.len
        let last = if nodeRange.last.line < i: 0 elif nodeRange.last.line == i: nodeRange.last.column else: line.len

        result.overrideStyle(first, last, $scope, match.pattern)

proc initTreesitter*(self: TextDocument): Future[void] {.async.} =
  if not self.tsParser.isNil:
    self.tsParser.deinit()
    self.tsParser = nil
  if not self.highlightQuery.isNil:
    self.highlightQuery.deinit()
    self.highlightQuery = nil

  let languageId = if getLanguageForFile(self.filename).getSome(languageId):
    languageId
  else:
    return

  let config = self.configProvider.getValue("editor.text.treesitter." & languageId, newJObject())
  var language = await loadLanguage(languageId, config)

  if language.isNone:
    logger.log(lvlWarn, fmt"Language is not available: '{languageId}'")
    return

  self.tsParser = createTSParser()
  if self.tsParser.isNil:
    logger.log(lvlWarn, fmt"Failed to create ts parser for: '{languageId}'")
    return

  self.tsParser.setLanguage(language.get)
  self.tsLanguage = language.get

  self.currentTree = self.tsParser.parseString(self.contentString)

  try:
    let queryString = fs.loadFile(fmt"./languages/{languageId}/queries/highlights.scm")
    self.highlightQuery = language.get.query(queryString)
  except CatchableError:
    logger.log(lvlError, fmt"[textedit] No highlight queries found for '{languageId}'")

  # We now have a treesitter grammar + highlight query, so retrigger rendering
  self.notifyTextChanged()

proc newTextDocument*(configProvider: ConfigProvider, filename: string = "", content: string | seq[string] = "", app: bool = false): TextDocument =
  new(result)
  var self = result
  self.filename = filename
  self.currentTree = nil
  self.appFile = app
  self.configProvider = configProvider

  self.indentStyle = IndentStyle(kind: Spaces, spaces: 2)
  self.languageConfig = some TextLanguageConfig(
    tabWidth: 2,
    indentAfter: @[":", "=", "(", "{", "[", "enum", "object"]
  )

  asyncCheck self.initTreesitter()

  let language = getLanguageForFile(filename)
  if language.isSome:
    self.languageId = language.get

  self.content = content

proc newTextDocument*(configProvider: ConfigProvider, filename: string, app: bool, workspaceFolder: Option[WorkspaceFolder]): TextDocument =
  result = newTextDocument(configProvider, filename, "", app)
  result.workspace = workspaceFolder
  result.load()

proc destroy*(self: TextDocument) =
  if not self.tsParser.isNil:
    self.tsParser.deinit()
    self.tsParser = nil

  if self.languageServer.getSome(ls):
    ls.removeOnRequestSaveHandler(self.onRequestSaveHandle)
    ls.stop()
    self.languageServer = LanguageServer.none

method `$`*(document: TextDocument): string =
  return document.filename

method save*(self: TextDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.appFile = app

  if self.workspace.getSome(ws):
    asyncCheck ws.saveFile(self.filename, self.contentString)
  elif self.appFile:
    fs.saveApplicationFile(self.filename, self.contentString)
  else:
    fs.saveFile(self.filename, self.contentString)

proc loadAsync(self: TextDocument, ws: WorkspaceFolder): Future[void] {.async.} =
  self.content = await ws.loadFile(self.filename)
  self.onLoaded.invoke self

method load*(self: TextDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename

  if self.workspace.getSome(ws):
    asyncCheck self.loadAsync(ws)
  elif self.appFile:
    self.content = fs.loadApplicationFile(self.filename)
    self.onLoaded.invoke self
  else:
    self.content = fs.loadFile(self.filename)
    self.onLoaded.invoke self

proc byteOffset*(self: TextDocument, cursor: Cursor): int =
  result = cursor.column
  for i in 0..<cursor.line:
    result += self.lines[i].len + 1

proc tabWidth*(self: TextDocument): int =
  return self.languageConfig.map(c => c.tabWidth).get(4)

proc delete*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], notify: bool = true, record: bool = true): seq[Selection] =
  result = self.clampAndMergeSelections selections

  var undoOp = UndoOp(kind: Nested, children: @[], oldSelection: @oldSelection)

  for i, selection in result:
    if selection.isEmpty:
      continue

    let selection = selection.normalized

    let startByte = self.byteOffset(selection.first)
    let endByte = self.byteOffset(selection.last)

    let deletedText = self.contentString(selection)

    let (first, last) = selection.normalized
    # echo "delete: ", selection, ", lines = ", self.lines
    if first.line == last.line:
      # Single line selection
      self.lines[last.line].delete first.column..<last.column
    else:
      # Multi line selection
      # Delete from first cursor to end of first line and add last line
      if first.column < self.lineLength first.line:
        self.lines[first.line].delete(first.column..<(self.lineLength first.line))
      self.lines[first.line].add self.lines[last.line][last.column..^1]
      # Delete all lines in between
      self.lines.delete (first.line + 1)..last.line

    result[i] = selection.first.toSelection
    for k in (i+1)..result.high:
      result[k] = result[k].subtract(selection)

    if not self.tsParser.isNil:
      let edit = TSInputEdit(
        startIndex: startByte,
        oldEndIndex: endByte,
        newEndIndex: startByte,
        startPosition: TSPoint(row: selection.first.line, column: selection.first.column),
        oldEndPosition: TSPoint(row: selection.last.line, column: selection.last.column),
        newEndPosition: TSPoint(row: selection.first.line, column: selection.first.column),
      )
      discard self.currentTree.edit(edit)
      let strValue = self.lines.join("\n")
      self.currentTree = self.tsParser.parseString(strValue, self.currentTree.some)
      # echo self.currentTree.root

    inc self.version

    if record:
      undoOp.children.add UndoOp(kind: Insert, cursor: selection.first, text: deletedText)

    if notify:
      self.textDeleted.invoke((self, selection))

  if notify:
    self.notifyTextChanged()

  if record and undoOp.children.len > 0:
    self.undoOps.add undoOp
    self.redoOps = @[]

proc getNodeRange*(self: TextDocument, selection: Selection, parentIndex: int = 0, siblingIndex: int = 0): Option[Selection] =
  result = Selection.none
  if self.currentTree.isNil:
    return

  var node = self.currentTree.root.descendantForRange selection

  for i in 0..<parentIndex:
    if node == self.currentTree.root:
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

  result = node.getRange.some

proc getIndentForLine*(self: TextDocument, line: int): int =
  result = 0
  for c in self.lines[line]:
    if c != ' ':
      break
    result += 1

proc insert*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], texts: openArray[string], notify: bool = true, record: bool = true): seq[Selection] =
  var newEmptyLines: seq[int]

  result = self.clampAndMergeSelections selections

  var undoOp = UndoOp(kind: Nested, children: @[], oldSelection: @oldSelection)

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

    var lineCounter: int = 0
    # echo "insert ", cursor, ": ", text
    if self.singleLine:
      let text = text.replace("\n", " ")
      if self.lines.len == 0:
        self.lines.add text
      else:
        self.lines[0].insert(text, cursor.column)
      cursor.column += text.len

    else:
      for line in text.splitLines(false):
        defer: inc lineCounter
        if lineCounter > 0:
          # Split line
          self.lines.insert(self.lines[cursor.line][cursor.column..^1], cursor.line + 1)
          newEmptyLines.add (cursor.line + 1)

          if cursor.column < self.lineLength cursor.line:
            self.lines[cursor.line].delete(cursor.column..<(self.lineLength cursor.line))
          cursor = (cursor.line + 1, 0)

        if line.len > 0:
          self.lines[cursor.line].insert(line, cursor.column)
          cursor.column += line.len

    result[i] = cursor.toSelection
    for k in (i+1)..result.high:
      result[k] = result[k].add((oldCursor, cursor))

    if not self.tsParser.isNil:
      let edit = TSInputEdit(
        startIndex: startByte,
        oldEndIndex: startByte,
        newEndIndex: startByte + text.len,
        startPosition: TSPoint(row: oldCursor.line, column: oldCursor.column),
        oldEndPosition: TSPoint(row: oldCursor.line, column: oldCursor.column),
        newEndPosition: TSPoint(row: cursor.line, column: cursor.column),
      )
      discard self.currentTree.edit(edit)
      let strValue = self.lines.join("\n")
      self.currentTree = self.tsParser.parseString(strValue, self.currentTree.some)

    inc self.version

    if record:
      undoOp.children.add UndoOp(kind: Delete, selection: (oldCursor, cursor))

    if notify:
      self.textInserted.invoke((self, oldCursor, text))

  if notify:
    self.notifyTextChanged()

  if record and undoOp.children.len > 0:
    self.undoOps.add undoOp
    self.redoOps = @[]

proc edit*(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], texts: openArray[string], notify: bool = true, record: bool = true): seq[Selection] =
  let selections = selections.map (s) => s.normalized
  result = self.delete(selections, oldSelection, false, record=record)
  result = self.insert(result, oldSelection, texts, record=record)

proc doUndo(document: TextDocument, op: UndoOp, oldSelection: openArray[Selection], useOldSelection: bool, redoOps: var seq[UndoOp]): seq[Selection] =
  case op.kind:
  of Delete:
    let text = document.contentString(op.selection)
    result = document.delete([op.selection], op.oldSelection, record = false)
    redoOps.add UndoOp(kind: Insert, cursor: op.selection.first, text: text, oldSelection: @oldSelection)

  of Insert:
    let selections = document.insert([op.cursor.toSelection], op.oldSelection, [op.text], record = false)
    result = selections
    redoOps.add UndoOp(kind: Delete, selection: (op.cursor, selections[0].last), oldSelection: @oldSelection)

  of Nested:
    result = op.oldSelection

    var redoOp = UndoOp(kind: Nested, oldSelection: @oldSelection)
    for i in countdown(op.children.high, 0):
      discard document.doUndo(op.children[i], oldSelection, useOldSelection, redoOp.children)

    redoOps.add redoOp

  if useOldSelection:
    result = op.oldSelection

proc undo*(document: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool): Option[seq[Selection]] =
  result = seq[Selection].none

  if document.undoOps.len == 0:
    return

  let op = document.undoOps.pop
  return document.doUndo(op, oldSelection, useOldSelection, document.redoOps).some

proc doRedo(document: TextDocument, op: UndoOp, oldSelection: openArray[Selection], useOldSelection: bool, undoOps: var seq[UndoOp]): seq[Selection] =
  case op.kind:
  of Delete:
    let text = document.contentString(op.selection)
    result = document.delete([op.selection], op.oldSelection, record = false)
    undoOps.add UndoOp(kind: Insert, cursor: op.selection.first, text: text, oldSelection: @oldSelection)

  of Insert:
    result = document.insert([op.cursor.toSelection], [op.cursor.toSelection], [op.text], record = false)
    undoOps.add UndoOp(kind: Delete, selection: (op.cursor, result[0].last), oldSelection: @oldSelection)

  of Nested:
    result = op.oldSelection

    var undoOp = UndoOp(kind: Nested, oldSelection: @oldSelection)
    for i in countdown(op.children.high, 0):
      discard document.doRedo(op.children[i], oldSelection, useOldSelection, undoOp.children)

    undoOps.add undoOp

  if useOldSelection:
    result = op.oldSelection

proc redo*(document: TextDocument, oldSelection: openArray[Selection], useOldSelection: bool): Option[seq[Selection]] =
  result = seq[Selection].none

  if document.redoOps.len == 0:
    return

  let op = document.redoOps.pop
  return document.doRedo(op, oldSelection, useOldSelection, document.undoOps).some
