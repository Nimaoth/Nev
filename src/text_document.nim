import std/[strutils, logging, sequtils, sugar, options, json, jsonutils, streams, strformat, os, re, tables, deques, asyncdispatch, asyncfile]
import editor, document, document_editor, events, id, util, scripting, vmath, bumpy, rect_utils, language_server_base, event
import windy except Cursor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil

import treesitter/api as ts

# import treesitter_c/c
# import treesitter_bash/bash
# import treesitter_c_sharp/c_sharp
# import treesitter_cpp/cpp
# import treesitter_css/css
# import treesitter_go/go
# import treesitter_haskell/haskell
# import treesitter_html/html
# import treesitter_java/java
import treesitter_javascript/javascript
# import treesitter_ocaml/ocaml
# import treesitter_php/php
# import treesitter_python/python
# import treesitter_ruby/ruby
import treesitter_rust/rust
# import treesitter_scala/scala
# import treesitter_typescript/typescript
import treesitter_nim/nim
import treesitter_zig/zig

var logger = newConsoleLogger()

when not declared(c_malloc):
  proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>", used.}
  proc c_free(p: pointer): void {.importc: "free", header: "<stdlib.h>", used.}

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

type TextDocument* = ref object of Document
  filename*: string
  lines*: seq[string]
  languageId*: string
  version*: int

  textChanged*: Event[TextDocument]
  textInserted*: Event[tuple[document: TextDocument, location: Cursor, text: string]]
  textDeleted*: Event[tuple[document: TextDocument, selection: Selection]]
  singleLine*: bool

  undoOps*: seq[UndoOp]
  redoOps*: seq[UndoOp]

  tsParser: ptr ts.TSParser
  currentTree: ptr ts.TSTree
  highlightQuery: ptr ts.TSQuery

  languageServer: Option[LanguageServer]

type StyledText* = object
  text*: string
  scope*: string
  priority*: int
  bounds*: Rect

type StyledLine* = object
  index*: int
  parts*: seq[StyledText]

type TextDocumentEditor* = ref object of DocumentEditor
  editor*: Editor
  document*: TextDocument

  selectionsInternal: Selections
  selectionHistory: Deque[Selections]

  searchQuery*: string
  searchRegex*: Option[Regex]
  searchResults*: Table[int, seq[Selection]]

  targetColumn: int
  hideCursorWhenInactive*: bool

  completionEventHandler: EventHandler
  modeEventHandler: EventHandler
  currentMode*: string
  commandCount*: int
  commandCountRestore*: int

  scrollOffset*: float
  previousBaseIndex*: int
  lineNumbers*: Option[LineNumbers]

  lastRenderedLines*: seq[StyledLine]

  completions*: seq[TextCompletion]
  selectedCompletion*: int
  lastItems*: seq[tuple[index: int, bounds: Rect]]
  showCompletions*: bool

proc handleAction(self: TextDocumentEditor, action: string, arg: string): EventResponse
proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse
proc handleInput(self: TextDocumentEditor, input: string): EventResponse

func toTsPoint(cursor: Cursor): ts.TSPoint = ts.TSPoint(row: cursor.line.uint32, column: cursor.column.uint32)
proc len*(node: ts.TSNode): int = node.tsNodeChildCount().int
proc high*(node: ts.TSNode): int = node.len - 1
proc low*(node: ts.TSNode): int = 0
proc startByte*(node: ts.TSNode): int = node.tsNodeStartByte.int
proc endByte*(node: ts.TSNode): int = node.tsNodeEndByte.int
proc startPoint*(node: ts.TSNode): Cursor =
  let point = node.tsNodeStartPoint
  return (point.row.int, point.column.int)
proc endPoint*(node: ts.TSNode): Cursor =
  let point = node.tsNodeEndPoint
  return (point.row.int, point.column.int)
proc getRange*(node: ts.TSNode): Selection = (node.startPoint, node.endPoint)
proc root*(tree: ptr ts.TSTree): ts.TSNode = tree.tsTreeRootNode
proc execute*(cursor: ptr ts.TSQueryCursor, query: ptr ts.TSQuery, node: ts.TSNode) = cursor.tsQueryCursorExec(query, node)
proc prev*(node: ts.TSNode): Option[ts.TSNode] =
  let other = node.tsNodePrevSibling
  if not other.tsNodeIsNull:
    result = other.some
proc next*(node: ts.TSNode): Option[ts.TSNode] =
  let other = node.tsNodeNextSibling
  if not other.tsNodeIsNull:
    result = other.some
proc prevNamed*(node: ts.TSNode): Option[ts.TSNode] =
  let other = node.tsNodePrevNamedSibling
  if not other.tsNodeIsNull:
    result = other.some
proc nextNamed*(node: ts.TSNode): Option[ts.TSNode] =
  let other = node.tsNodeNextNamedSibling
  if not other.tsNodeIsNull:
    result = other.some

template withQueryCursor*(cursor: untyped, body: untyped): untyped =
  block:
    let cursor = ts.tsQueryCursorNew()
    defer: cursor.tsQueryCursorDelete()
    body

template withTreeCursor*(node: untyped, cursor: untyped, body: untyped): untyped =
  block:
    let cursor = node.tsTreeCursorNew()
    defer: cursor.tsTreeCursorDelete()
    body

proc `[]`*(node: ts.TSNode, index: int): ts.TSNode = node.tsNodeChild(index.uint32)
proc descendantForRange*(node: ts.TSNode, selection: Selection): ts.TSNode = node.ts_node_descendant_for_point_range(selection.first.toTsPoint, selection.last.toTsPoint)
proc parent*(node: ts.TSNode): ts.TSNode = node.tsNodeParent()
proc `==`*(a: ts.TSNode, b: ts.TSNode): bool = a.tsNodeEq(b)
proc current*(cursor: var ts.TSTreeCursor): ts.TSNode = tsTreeCursorCurrentNode(addr cursor)
proc gotoParent*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoParent(addr cursor)
proc gotoNextSibling*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoNextSibling(addr cursor)
proc gotoFirstChild*(cursor: var ts.TSTreeCursor): bool = tsTreeCursorGotoFirstChild(addr cursor)
proc gotoFirstChildForCursor*(cursor: var ts.TSTreeCursor, cursor2: Cursor): int = tsTreeCursorGotoFirstChildForPoint(addr cursor, cursor2.toTsPoint).int

proc setPointRange*(cursor: ptr ts.TSQueryCursor, selection: Selection) =
  cursor.tsQueryCursorSetPointRange(selection.first.toTsPoint, selection.last.toTsPoint)

proc getCaptureName(query: ptr ts.TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryCaptureNameForId(query, index, addr length)
  defer: assert result.len == length.int
  return $str

proc getStringValue(query: ptr ts.TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryStringValueForId(query, index, addr length)
  defer: assert result.len == length.int
  return $str

proc nextMatch*(cursor: ptr ts.TSQueryCursor): Option[ts.TSQueryMatch] =
  result = ts.TSQueryMatch.none
  var match: ts.TSQueryMatch
  if cursor.tsQueryCursorNextMatch(addr match):
    result = match.some

proc nextCapture*(cursor: ptr ts.TSQueryCursor): Option[tuple[match: ts.TSQueryMatch, captureIndex: int]] =
  var match: ts.TSQueryMatch
  var index: uint32
  if cursor.tsQueryCursorNextCapture(addr match, addr index):
    result = (match, index.int).some

proc `$`*(node: ts.TSNode): string =
  let c_str = node.tsNodeString()
  defer: c_str.c_free
  result = $c_str

proc getLine*(self: TextDocument, line: int): string =
  if line < self.lines.len:
    return self.lines[line]
  return ""

proc lineLength*(self: TextDocument, line: int): int =
  if line < self.lines.len:
    return self.lines[line].len
  return 0

proc lineLength*(self: TextDocumentEditor, line: int): int =
  if line < self.document.lines.len:
    return self.document.lines[line].len
  return 0

proc clampCursor*(self: TextDocument, cursor: Cursor): Cursor =
  var cursor = cursor
  if self.lines.len == 0:
    return (0, 0)
  cursor.line = clamp(cursor.line, 0, self.lines.len - 1)
  cursor.column = clamp(cursor.column, 0, self.lineLength cursor.line)
  return cursor

proc clampCursor*(self: TextDocumentEditor, cursor: Cursor): Cursor = self.document.clampCursor(cursor)

proc clampSelection*(self: TextDocument, selection: Selection): Selection = (self.clampCursor(selection.first), self.clampCursor(selection.last))
proc clampSelection*(self: TextDocumentEditor, selection: Selection): Selection = self.document.clampSelection(selection)

proc clampAndMergeSelections*(self: TextDocument, selections: openArray[Selection]): Selections = selections.map((s) => self.clampSelection(s)).deduplicate
proc clampAndMergeSelections*(self: TextDocumentEditor, selections: openArray[Selection]): Selections = self.document.clampAndMergeSelections(selections)

proc selections*(self: TextDocumentEditor): Selections = self.selectionsInternal
proc selection*(self: TextDocumentEditor): Selection = self.selectionsInternal[self.selectionsInternal.high]

proc `selection=`*(self: TextDocumentEditor, selection: Selection) =
  if self.selectionsInternal.len == 1 and self.selectionsInternal[0] == selection:
    return

  self.selectionHistory.addLast self.selectionsInternal
  if self.selectionHistory.len > 100:
    discard self.selectionHistory.popFirst
  self.selectionsInternal = @[self.clampSelection selection]

proc `selections=`*(self: TextDocumentEditor, selections: Selections) =
  if self.selectionsInternal == selections:
    return

  self.selectionHistory.addLast self.selectionsInternal
  if self.selectionHistory.len > 100:
    discard self.selectionHistory.popFirst
  self.selectionsInternal = self.clampAndMergeSelections selections
  if self.selectionsInternal.len == 0:
    self.selectionsInternal = @[(0, 0).toSelection]

proc clampSelection*(self: TextDocumentEditor) =
  self.selections = self.clampAndMergeSelections(self.selectionsInternal)

proc `content=`*(self: TextDocument, value: string) =
  if self.singleLine:
    self.lines = @[value.replace("\n", "")]
    if self.lines.len == 0:
      self.lines = @[""]
    if not self.tsParser.isNil:
      self.currentTree = self.tsParser.tsParserParseString(nil, self.lines[0].cstring, self.lines[0].len.uint32)
  else:
    self.lines = value.splitLines
    if self.lines.len == 0:
      self.lines = @[""]
    if not self.tsParser.isNil:
      self.currentTree = self.tsParser.tsParserParseString(nil, value, value.len.uint32)

  inc self.version

  self.textChanged.invoke(self)

proc `content=`*(self: TextDocument, value: seq[string]) =
  if self.singleLine:
    self.lines = @[value.join("")]
  else:
    self.lines = value.toSeq

  if self.lines.len == 0:
    self.lines = @[""]

  let strValue = value.join("\n")

  if not self.tsParser.isNil:
    self.currentTree = self.tsParser.tsParserParseString(nil, strValue.cstring, strValue.len.uint32)

  inc self.version

  self.textChanged.invoke(self)

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

import language_server

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
  var line = self.lines[i]
  var styledLine = StyledLine(index: i, parts: @[StyledText(text: line, scope: "", priority: 1000000000)])

  var regexes = initTable[string, Regex]()

  if self.tsParser.isNil or self.highlightQuery.isNil:
    return styledLine

  withQueryCursor(cursor):
    cursor.setPointRange ((i, 0), (i, line.len))
    cursor.execute(self.highlightQuery, self.currentTree.root)

    var match = cursor.nextMatch()
    while match.isSome:
      defer: match = cursor.nextMatch()

      var predicatesLength: uint32 = 0
      let predicatesPtr = self.highlightQuery.tsQueryPredicatesForPattern(match.get.patternIndex, addr predicatesLength)
      let predicatesRaw = cast[ptr array[100, ts.TSQueryPredicateStep]](predicatesPtr)

      var argIndex = 0
      var predicateName: string = ""
      var predicateArgs: seq[string] = @[]

      var predicates: seq[tuple[name: string, args: seq[string]]] = @[]

      for k in 0..<predicatesLength:
        case predicatesRaw[k].`type`:
        of ts.TSQueryPredicateStepTypeString:
          let value = self.highlightQuery.getStringValue(predicatesRaw[k].valueId)
          if argIndex == 0:
            predicateName = value
          else:
            predicateArgs.add value
          argIndex += 1

        of ts.TSQueryPredicateStepTypeCapture:
          predicateArgs.add self.highlightQuery.getCaptureName(predicatesRaw[k].valueId)
          argIndex += 1

        of ts.TSQueryPredicateStepTypeDone:
          predicates.add (predicateName, predicateArgs)
          predicateName = ""
          predicateArgs.setLen 0
          argIndex = 0

      let captures = cast[ptr array[100, ts.TSQueryCapture]](match.get.captures)
      for k in 0..<match.get.capture_count.int:
        let scope = self.highlightQuery.getCaptureName(captures[k].index)

        let node = captures[k].node

        var matches = true
        for predicate in predicates:
          if predicate.args[0] != scope:
            continue
          case predicate.name
          of "match?":
            let regex = if regexes.contains(predicate.args[1]):
              regexes[predicate.args[1]]
            else:
              let regex = re(predicate.args[1], {})
              regexes[predicate.args[1]] = regex
              regex

            let nodeText = self.contentString(node.getRange)
            if nodeText.matchLen(regex) != nodeText.len:
              matches = false
              break

          of "not-match?":
            let regex = if regexes.contains(predicate.args[1]):
              regexes[predicate.args[1]]
            else:
              let regex = re(predicate.args[1], {})
              regexes[predicate.args[1]] = regex
              regex

            let nodeText = self.contentString(node.getRange)
            if nodeText.matchLen(regex) == nodeText.len:
              matches = false
              break

          of "eq?":
            # @todo: second arg can be capture aswell
            let nodeText = self.contentString(node.getRange)
            if nodeText != predicate.args[1]:
              matches = false
              break

          of "not-eq?":
            # @todo: second arg can be capture aswell
            let nodeText = self.contentString(node.getRange)
            if nodeText == predicate.args[1]:
              matches = false
              break

          of "any-of?":
            logger.log(lvlError, fmt"Unknown predicate '{predicate.name}'")

          else:
            logger.log(lvlError, fmt"Unknown predicate '{predicate.name}'")

        if gEditor.getFlag("text.print-matches"):
          let nodeText = self.contentString(node.getRange)
          echo fmt"{match.get.patternIndex}: '{nodeText}' {node} (matches: {matches})"

        if not matches:
          continue

        let nodeRange = node.getRange

        if nodeRange.first.line == i:
          styledLine.splitAt(nodeRange.first.column)
        if nodeRange.last.line == i:
          styledLine.splitAt(nodeRange.last.column)

        let first = if nodeRange.first.line < i: 0 elif nodeRange.first.line == i: nodeRange.first.column else: line.len
        let last = if nodeRange.last.line < i: 0 elif nodeRange.last.line == i: nodeRange.last.column else: line.len

        styledLine.overrideStyle(first, last, scope, match.get.patternIndex.int)

  return styledLine

proc getLanguageForFile(filename: string): Option[string] =
  var extension = filename.splitFile.ext
  if extension.len > 0:
    extension = extension[1..^1]
  let languageId = case extension
  of "c", "cc", "inc": "c"
  of "sh": "bash"
  of "cs": "csharp"
  of "cpp", "hpp", "h": "cpp"
  of "css": "css"
  of "go": "go"
  of "hs": "haskell"
  of "html": "html"
  of "java": "java"
  of "js", "jsx", "json": "javascript"
  of "ocaml": "ocaml"
  of "php": "php"
  of "py": "python"
  of "ruby": "ruby"
  of "rs": "rust"
  of "scala": "scala"
  of "ts": "typescript"
  of "nim", "nims": "nim"
  of "zig": "zig"
  else:
    # Unsupported language
    logger.log(lvlWarn, fmt"Unknown file extension '{extension}'")
    return string.none
  return languageId.some

proc initTreesitter(self: TextDocument) =
  if not self.tsParser.isNil:
    self.tsParser.tsParserDelete()
    self.tsParser = nil
  if not self.highlightQuery.isNil:
    self.highlightQuery.tsQueryDelete()
    self.highlightQuery = nil

  template tryGetLanguage(constructor: untyped): untyped =
    block:
      var l: ptr TSLanguage = nil
      when compiles(constructor()):
        l = constructor()
      l

  let languageId = if getLanguageForFile(self.filename).getSome(languageId):
    languageId
  else:
    return

  let language = case languageId
  of "c": tryGetLanguage(treeSitterC)
  of "bash": tryGetLanguage(treeSitterBash)
  of "csharp": tryGetLanguage(treeSitterCShap)
  of "cpp": tryGetLanguage(treeSitterCpp)
  of "css": tryGetLanguage(treeSitterCss)
  of "go": tryGetLanguage(treeSitterGo)
  of "haskell": tryGetLanguage(treeSitterHaskell)
  of "html": tryGetLanguage(treeSitterHtml)
  of "java": tryGetLanguage(treeSitterJava)
  of "javascript": tryGetLanguage(treeSitterJavascript)
  of "ocaml": tryGetLanguage(treeSitterOcaml)
  of "php": tryGetLanguage(treeSitterPhp)
  of "python": tryGetLanguage(treeSitterPython)
  of "ruby": tryGetLanguage(treeSitterRuby)
  of "rust": tryGetLanguage(treeSitterRust)
  of "scala": tryGetLanguage(treeSitterScala)
  of "typescript": tryGetLanguage(treeSitterTypecript)
  of "nim": tryGetLanguage(treeSitterNim)
  of "zig": tryGetLanguage(treeSitterZig)
  else:
    logger.log(lvlWarn, fmt"Failed to init treesitter for language '{languageId}'")
    return

  if language.isNil:
    logger.log(lvlWarn, fmt"Language is not available: '{languageId}'")
    return

  self.tsParser = ts.tsParserNew()
  assert self.tsParser.tsParserSetLanguage(language) == true

  try:
    let queryString = readFile(fmt"./languages/{languageId}/queries/highlights.scm")
    var errorOffset: uint32 = 0
    var queryError: ts.TSQueryError = ts.TSQueryErrorNone
    self.highlightQuery = language.tsQueryNew(queryString.cstring, queryString.len.uint32, addr errorOffset, addr queryError)
    if queryError != ts.TSQueryErrorNone:
      logger.log(lvlError, fmt"[textedit] {queryError} at byte {errorOffset}: {queryString}")
  except CatchableError:
    logger.log(lvlError, fmt"[textedit] No highlight queries found for '{languageId}'")

proc saveTempFile*(self: TextDocument, filename: string): Future[void] {.async.} =
  let text = self.contentString
  var file = openAsync(filename, fmWrite)
  await file.write text
  file.close()

proc newTextDocument*(filename: string = "", content: string | seq[string] = ""): TextDocument =
  new(result)
  var self = result
  self.filename = filename
  self.currentTree = nil

  self.initTreesitter()

  let language = getLanguageForFile(filename)
  if language.isSome:
    self.languageId = language.get
    if language.get == "nim":
      proc saveTempFileClosure(filename: string): Future[void] {.async.} =
        await self.saveTempFile(filename)
      self.languageServer = LanguageServer(newLanguageServerNimSuggest(filename, saveTempFileClosure)).some
      self.languageServer.get.start()
    asyncCheck getOrCreateLanguageServerLSP(self.languageId)

  self.content = content

proc destroy*(self: TextDocument) =
  if not self.tsParser.isNil:
    self.tsParser.tsParserDelete()
    self.tsParser = nil

  if self.languageServer.isSome:
    self.languageServer.get.stop()
    self.languageServer = LanguageServer.none

method shutdown*(self: TextDocumentEditor) =
  self.document.destroy()

# proc `=destroy`[T: object](doc: var TextDocument) =
#   doc.tsParser.tsParserDelete()

method `$`*(document: TextDocument): string =
  return document.filename

method save*(self: TextDocument, filename: string = "") =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  writeFile(self.filename, self.lines.join "\n")

method load*(self: TextDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename

  let file = readFile(self.filename)
  self.content = file

proc notifyTextChanged(self: TextDocument) =
  self.textChanged.invoke self

proc byteOffset(self: TextDocument, cursor: Cursor): int =
  result = cursor.column
  for i in 0..<cursor.line:
    result += self.lines[i].len + 1

proc delete(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], notify: bool = true, record: bool = true): seq[Selection] =
  result = self.clampAndMergeSelections selections

  var undoOp = UndoOp(kind: Nested, children: @[], oldSelection: @oldSelection)

  for i, selection in result:
    if selection.isEmpty:
      continue

    let selection = selection.normalized

    let startByte = self.byteOffset(selection.first).uint32
    let endByte = self.byteOffset(selection.last).uint32

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
      let edit = ts.TSInputEdit(
        start_byte: startByte,
        old_end_byte: endByte,
        new_end_byte: startByte,
        start_point: TSPoint(row: selection.first.line.uint32, column: selection.first.column.uint32),
        old_end_point: TSPoint(row: selection.last.line.uint32, column: selection.last.column.uint32),
        new_end_point: TSPoint(row: selection.first.line.uint32, column: selection.first.column.uint32),
      )
      self.currentTree.tsTreeEdit(addr edit)
      let strValue = self.lines.join("\n")
      self.currentTree = self.tsParser.tsParserParseString(self.currentTree, strValue.cstring, strValue.len.uint32)
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

proc getTargetIndentForLine(self: TextDocument, line: int): int =
  if line == 0:
    return 0
  # return self.getIndentForLine(line - 1)
  if self.currentTree.isNil:
    return

  let curr = (line, 0)
  let prev = (line - 1, self.lineLength(line - 1))

  var nodePrev = self.currentTree.root.descendantForRange prev.toSelection
  var nodeCurr = self.currentTree.root.descendantForRange curr.toSelection

  let currChildOfPrev = nodePrev.getRange.contains(nodeCurr.getRange)
  # echo "prev: ", nodePrev.getRange, ", ", $nodePrev, "\n", self.contentString(nodePrev.getRange)
  # echo "curr: ", nodeCurr.getRange, ", ", $nodeCurr, "\n", self.contentString(nodeCurr.getRange)

  if currChildOfPrev:
    # echo "currChildOfPrev"
    return nodeCurr.getRange.first.column + 2
  else:
    # echo "not currChildOfPrev"
    return nodePrev.getRange.first.column + 2

  # return node.getRange.first.column + 2

proc insert(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], text: string, notify: bool = true, record: bool = true, autoIndent: bool = true): seq[Selection] =
  var newEmptyLines: seq[int]

  result = self.clampAndMergeSelections selections

  var undoOp = UndoOp(kind: Nested, children: @[], oldSelection: @oldSelection)

  for i, selection in result:
    let oldCursor = selection.last
    var cursor = selection.last
    let startByte = self.byteOffset(cursor).uint32

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
      let edit = ts.TSInputEdit(
        start_byte: startByte,
        old_end_byte: startByte,
        new_end_byte: startByte + text.len.uint32,
        start_point: TSPoint(row: oldCursor.line.uint32, column: oldCursor.column.uint32),
        old_end_point: TSPoint(row: oldCursor.line.uint32, column: oldCursor.column.uint32),
        new_end_point: TSPoint(row: cursor.line.uint32, column: cursor.column.uint32),
      )
      self.currentTree.tsTreeEdit(addr edit)
      let strValue = self.lines.join("\n")
      self.currentTree = self.tsParser.tsParserParseString(self.currentTree, strValue.cstring, strValue.len.uint32)

    # if autoIndent:
    #   for line in newEmptyLines:
    #     let indent = self.getTargetIndentForLine(line)
    #     cursor = self.insert((line, 0), oldSelection, ' '.repeat(indent), notify = false, record = false, autoIndent = false)

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

proc edit(self: TextDocument, selections: openArray[Selection], oldSelection: openArray[Selection], text: string, notify: bool = true): seq[Selection] =
  let selections = selections.map (s) => s.normalized
  result = self.delete(selections, oldSelection, false)
  result = self.insert(result, oldSelection, text)

proc doUndo(document: TextDocument, op: UndoOp, oldSelection: openArray[Selection], useOldSelection: bool, redoOps: var seq[UndoOp]): seq[Selection] =
  case op.kind:
  of Delete:
    let text = document.contentString(op.selection)
    result = document.delete([op.selection], op.oldSelection, record = false)
    redoOps.add UndoOp(kind: Insert, cursor: op.selection.first, text: text, oldSelection: @oldSelection)

  of Insert:
    let selections = document.insert([op.cursor.toSelection], op.oldSelection, op.text, record = false, autoIndent = false)
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
    result = document.insert([op.cursor.toSelection], [op.cursor.toSelection], op.text, record = false, autoIndent = false)
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
    return

  for i, line in self.document.lines:
    var selections: seq[Selection] = @[]
    var start = 0
    while start < line.len:
      let bounds = line.findBounds(self.searchRegex.get, start)
      if bounds.first == -1:
        break
      selections.add ((i, bounds.first), (i, bounds.last + 1))
      start = bounds.last + 1

    if selections.len > 0:
      self.searchResults[i] = selections
    else:
      self.searchResults.del i

method handleDocumentChanged*(self: TextDocumentEditor) =
  self.selection = (self.clampCursor self.selection.first, self.clampCursor self.selection.last)
  self.updateSearchResults()

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

proc scrollToCursor(self: TextDocumentEditor, cursor: Cursor, keepVerticalOffset: bool = false) =
  let targetLine = cursor.line
  let totalLineHeight = self.editor.renderCtx.lineHeight + getOption[float32](self.editor, "text.line-distance")

  if keepVerticalOffset:
    let currentLineY = (self.selection.last.line - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset
    self.previousBaseIndex = targetLine
    self.scrollOffset = currentLineY
  else:
    let targetLineY = (targetLine - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

    let margin = clamp(getOption[float32](self.editor, "text.cursor-margin", 25.0), 0.0, self.lastContentBounds.h * 0.5 - totalLineHeight * 0.5)
    if targetLineY < margin:
      self.scrollOffset = margin
      self.previousBaseIndex = targetLine
    elif targetLineY + totalLineHeight > self.lastContentBounds.h - margin:
      self.scrollOffset = self.lastContentBounds.h - margin - totalLineHeight
      self.previousBaseIndex = targetLine

proc getContextWithMode*(self: TextDocumentEditor, context: string): string

proc isThickCursor(self: TextDocumentEditor): bool =
  return getOption[bool](self.editor, self.getContextWithMode("editor.text.cursor.wide"), false)

proc getCursor(self: TextDocumentEditor, cursor: SelectionCursor): Cursor =
  case cursor
  of Config:
    let configCursor = getOption[SelectionCursor](self.editor, self.getContextWithMode("editor.text.cursor.movement"), Both)
    return self.getCursor(configCursor)
  of Both, Last, LastToFirst:
    return self.selection.last
  of First:
    return self.selection.first

proc moveCursor(self: TextDocumentEditor, cursor: SelectionCursor, movement: proc(doc: TextDocumentEditor, c: Cursor, off: int): Cursor, offset: int, all: bool) =
  case cursor
  of Config:
    let configCursor = getOption[SelectionCursor](self.editor, self.getContextWithMode("editor.text.cursor.movement"), Both)
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

method handleScroll*(self: TextDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  self.scrollOffset += scroll.y * getOption[float](self.editor, "text.scroll-speed", 40)

proc getTextDocumentEditor(wrapper: api.TextDocumentEditor): Option[TextDocumentEditor] =
  if gEditor.isNil: return TextDocumentEditor.none
  if gEditor.getEditorForId(wrapper.id).getSome(editor):
    if editor of TextDocumentEditor:
      return editor.TextDocumentEditor.some
  return TextDocumentEditor.none

proc getModeConfig(self: TextDocumentEditor, mode: string): EventHandlerConfig =
  return self.editor.getEventHandlerConfig("editor.text." & mode)

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
  if mode.len == 0:
    self.modeEventHandler = nil
  else:
    let config = self.getModeConfig(mode)
    self.modeEventHandler = eventHandler(config):
      onAction:
        self.handleAction action, arg
      onInput:
        self.handleInput input

  self.currentMode = mode

proc mode*(self: TextDocumentEditor): string {.expose("editor.text").} =
  return self.currentMode

proc getContextWithMode(self: TextDocumentEditor, context: string): string {.expose("editor.text").} =
  return context & "." & $self.currentMode

proc updateTargetColumn(self: TextDocumentEditor, cursor: SelectionCursor) {.expose("editor.text").} =
  self.targetColumn = self.getCursor(cursor).column

proc invertSelection(self: TextDocumentEditor) {.expose("editor.text").} =
  self.selection = (self.selection.last, self.selection.first)

proc insert(self: TextDocumentEditor, selections: seq[Selection], text: string, notify: bool = true, record: bool = true, autoIndent: bool = true): seq[Selection] {.expose("editor.text").} =
  return self.document.insert(selections, self.selections, text, notify, record, autoIndent)

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

proc getCompletionsAsync(self: TextDocumentEditor): Future[void]

proc insertText*(self: TextDocumentEditor, text: string) {.expose("editor.text").} =
  if self.document.singleLine and text == "\n":
    return

  let selections = self.selections.normalized
  self.selections = self.document.edit(self.selections, self.selections, text)
  self.updateTargetColumn(Last)

  if text == "." or text == ",":
    self.showCompletions = true
    asyncCheck self.getCompletionsAsync()
  elif self.showCompletions:
    asyncCheck self.getCompletionsAsync()

proc undo(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.undo(self.selections, true).getSome(selections):
    self.selections = selections

proc redo(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.redo(self.selections, true).getSome(selections):
    self.selections = selections

proc scrollText(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  self.scrollOffset += amount

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

proc reloadTreesitter*(self: TextDocumentEditor) {.expose("editor.text").} =
  echo "reloadTreesitter"
  self.document.initTreesitter()

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
  self.editor.setFlag("editor.text." & name, value)

proc getFlag*(self: TextDocumentEditor, name: string): bool {.expose("editor.text").} =
  return self.editor.getFlag("editor.text." & name)

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

  of "file":
    result.first = (0, 0)
    let line = self.document.lines.len - 1
    result.last = (line, self.document.getLine(line).len)

  of "prev-find-result":
    result = self.getPrevFindResult(cursor, count)

  of "next-find-result":
    result = self.getNextFindResult(cursor, count)

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
    return self.cursor(selection, getOption(self.editor, self.getContextWithMode("editor.text.cursor.movement"), Both))
  of Both:
    return selection.last
  of First:
    return selection.first
  of Last, LastToFirst:
    return selection.last

proc setMove*(self: TextDocumentEditor, args {.varargs.}: JsonNode) {.expose("editor.text").} =
  setOption[int](self.editor, "text.move-count", self.getCommandCount)
  self.setMode getOption[string](self.editor, "text.move-next-mode")
  self.setCommandCount getOption[int](self.editor, "text.move-command-count")
  discard self.runAction(getOption[string](self.editor, "text.move-action"), args)
  setOption[string](self.editor, "text.move-action", "")

proc deleteMove*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = getOption[int](self.editor, "text.move-count")
  let inside = self.getFlag("move-inside")

  # echo fmt"delete-move {move}, {which}, {count}, {inside}"

  let selections = self.selections.map (s) => (if inside:
    self.getSelectionForMove(s.last, move, count)
  else:
    (s.last, self.getSelectionForMove(s.last, move, count).last))

  self.selections = self.document.delete(selections, self.selections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc selectMove*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = getOption[int](self.editor, "text.move-count")
  self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(s.last, move, count))
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc changeMove*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  let count = getOption[int](self.editor, "text.move-count")
  let inside = self.getFlag("move-inside")

  let selections = self.selections.map (s) => (if inside:
    self.getSelectionForMove(s.last, move, count)
  else:
    (s.last, self.getSelectionForMove(s.last, move, count).last))

  self.selections = self.document.delete(selections, self.selections)
  self.scrollToCursor(Last)
  self.updateTargetColumn(Last)

proc moveLast*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  case which
  of Config:
    self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(self.cursor(s, which), move).last.toSelection(s, getOption(self.editor, self.getContextWithMode("editor.text.cursor.movement"), Both)))
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(self.cursor(s, which), move).last.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc moveFirst*(self: TextDocumentEditor, move: string, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("editor.text").} =
  case which
  of Config:
    self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(self.cursor(s, which), move).first.toSelection(s, getOption(self.editor, self.getContextWithMode("editor.text.cursor.movement"), Both)))
  else:
    self.selections = self.selections.mapAllOrLast(all, (s) => self.getSelectionForMove(self.cursor(s, which), move).first.toSelection(s, which))
  self.scrollToCursor(which)
  self.updateTargetColumn(which)

proc setSearchQuery*(self: TextDocumentEditor, query: string) {.expose("editor.text").} =
  self.searchQuery = query
  self.searchRegex = re(query, {}).some
  self.updateSearchResults()

proc setSearchQueryFromMove*(self: TextDocumentEditor, move: string, count: int = 0) {.expose("editor.text").} =
  let selection = self.getSelectionForMove(self.selection.last, move, count)
  self.selection = selection
  self.setSearchQuery(self.document.contentString(selection))

proc getLanguageServer(self: TextDocumentEditor): Future[Option[LanguageServer]] {.async.} =
  let languageId = if getLanguageForFile(self.document.filename).getSome(languageId):
    languageId
  else:
    return

  if self.document.languageServer.isSome:
    return self.document.languageServer
  else:
    let languageServer = await getOrCreateLanguageServerLSP(languageId)
    if languageServer.isNone:
      return LanguageServer.none

    return some(LanguageServer(languageServer.get))

proc gotoDefinitionAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.isSome:
    let definition = await languageServer.get.getDefinition(self.document.filename, self.selection.last)
    if definition.isSome:
      self.selection = definition.get.location.toSelection

proc getCompletionsAsync(self: TextDocumentEditor): Future[void] {.async.} =
  let languageServer = await self.getLanguageServer()
  if languageServer.isNone:
    return

  if languageServer.isSome:
    let completions = await languageServer.get.getCompletions(self.document.languageId, self.document.filename, self.selection.last)
    self.completions = completions
    self.selectedCompletion = self.selectedCompletion.clamp(0, self.completions.high)
    if self.completions.len == 0:
      self.showCompletions = false
    else:
      self.showCompletions = true

# proc testAsync*(self: TextDocumentEditor) {.expose("editor.text").} =
#   echo "testAsync"
#   let f = self.foo()
#   f.addCallback proc(f: Future[int]) =
#     echo "-> ", f.read

proc gotoDefinition*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.gotoDefinitionAsync()

proc getCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  asyncCheck self.getCompletionsAsync()

proc hideCompletions*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.showCompletions = false

proc selectPrevCompletion(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.completions.len > 0:
    self.selectedCompletion = (self.selectedCompletion - 1).clamp(0, self.completions.len - 1)
  else:
    self.selectedCompletion = 0

proc selectNextCompletion(editor: TextDocumentEditor) {.expose("editor.text").} =
  if editor.completions.len > 0:
    editor.selectedCompletion = (editor.selectedCompletion + 1).clamp(0, editor.completions.len - 1)
  else:
    editor.selectedCompletion = 0

proc applySelectedCompletion*(self: TextDocumentEditor) {.expose("editor.text").} =
  if not self.showCompletions:
    return

  if self.selectedCompletion > self.completions.high:
    return

  let com = self.completions[self.selectedCompletion]
  echo "Applying completion ", com

  let cursor = self.selection.last
  if cursor.column == 0:
    self.selections = self.document.insert([cursor.toSelection], self.selections, com.name, true, true, false)
  else:
    let line = self.document.getLine cursor.line
    var column = cursor.column
    while column > 0:
      case line[column - 1]
      of ' ', '\t', '.', ',', '(', ')', '[', ']', '{', '}', ':', ';':
        break
      else:
        column -= 1

    self.selections = self.document.edit([((cursor.line, column), cursor)], self.selections, com.name)

genDispatcher("editor.text")

proc handleActionInternal(self: TextDocumentEditor, action: string, args: JsonNode): EventResponse =
  # echo "[textedit] handleAction ", action, " '", arg, "'"
  if self.editor.handleUnknownDocumentEditorAction(self, action, args) == Handled:
    dec self.commandCount
    while self.commandCount > 0:
      if self.editor.handleUnknownDocumentEditorAction(self, action, args) != Handled:
        break
      dec self.commandCount
    self.commandCount = self.commandCountRestore
    self.commandCountRestore = 0
    return Handled

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
  # echo "handleAction ", action, ", ", arg
  var args = newJArray()
  try:
    for a in newStringStream(arg).parseJsonFragments():
      args.add a
    return self.handleActionInternal(action, args)
  except CatchableError:
    logger.log(lvlError, fmt"[editor.text] handleAction: {action}, Failed to parse args: '{arg}'")
    return Failed

proc handleInput(self: TextDocumentEditor, input: string): EventResponse =
  # echo "handleInput '", input, "'"
  if self.editor.invokeCallback(self.getContextWithMode("editor.text.input-handler"), input.newJString):
    return Handled

  self.insertText(input)
  return Handled

method injectDependencies*(self: TextDocumentEditor, ed: Editor) =
  self.editor = ed
  self.editor.registerEditor(self)
  let config = ed.getEventHandlerConfig("editor.text")
  self.eventHandler = eventHandler(config):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

  self.completionEventHandler = eventHandler(ed.getEventHandlerConfig("editor.text.completion")):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

proc handleTextDocumentTextChanged(self: TextDocumentEditor) =
  self.clampSelection()
  self.updateSearchResults()

proc newTextEditor*(document: TextDocument, ed: Editor): TextDocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, document: document, selectionsInternal: @[(0, 0).toSelection])
  editor.init()
  if editor.document.lines.len == 0:
    editor.document.lines = @[""]
  editor.injectDependencies(ed)
  discard document.textChanged.subscribe (_: TextDocument) => editor.handleTextDocumentTextChanged()
  return editor

method createWithDocument*(self: TextDocumentEditor, document: Document): DocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, document: TextDocument(document), selectionsInternal: @[(0, 0).toSelection])
  editor.init()
  if editor.document.lines.len == 0:
    editor.document.lines = @[""]
  discard editor.document.textChanged.subscribe (_: TextDocument) => editor.handleTextDocumentTextChanged()
  return editor

proc getCursorAtPixelPos(self: TextDocumentEditor, mousePosWindow: Vec2): Option[Cursor] =
  for line in self.lastRenderedLines:
    var startOffset = 0
    for i, part in line.parts:
      if part.bounds.contains(mousePosWindow) or (i == line.parts.high and mousePosWindow.y >= part.bounds.y and mousePosWindow.y <= part.bounds.yh and mousePosWindow.x >= part.bounds.x):
        var offsetFromLeft = (mousePosWindow.x - part.bounds.x) / self.editor.renderCtx.charWidth
        if self.isThickCursor():
          offsetFromLeft -= 0.0
        else:
          offsetFromLeft += 0.5

        let index = clamp(offsetFromLeft.int, 0, part.text.len)
        return (line.index, startOffset + index).some
      startOffset += part.text.len
  return Cursor.none

method handleMousePress*(self: TextDocumentEditor, button: windy.Button, mousePosWindow: Vec2) =
  if button == MouseLeft and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selection = cursor.toSelection

  if button == DoubleClick and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selectInside(cursor)

  if button == TripleClick and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selectLine(cursor.line)

method handleMouseRelease*(self: TextDocumentEditor, button: windy.Button, mousePosWindow: Vec2) =
  # if self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
  #   self.selection = cursor.toSelection(self.selection, Last)
  discard

method handleMouseMove*(self: TextDocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2) =
  if self.editor.window.buttonDown[windy.MouseLeft] and self.getCursorAtPixelPos(mousePosWindow).getSome(cursor):
    self.selection = cursor.toSelection(self.selection, Last)

method unregister*(self: TextDocumentEditor) =
  self.editor.unregisterEditor(self)