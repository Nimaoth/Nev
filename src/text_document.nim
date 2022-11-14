import std/[strutils, logging, sequtils, sugar, options, json, jsonutils, streams, strformat, os, re, tables, deques]
import editor, document, document_editor, events, id, util, scripting, vmath, bumpy, rect_utils
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

var logger = newConsoleLogger()

when not declared(c_malloc):
  proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
  proc c_free(p: pointer): void {.importc: "free", header: "<stdlib.h>".}

type Event*[T] = object
  handlers: seq[tuple[id: Id, callback: (T) -> void]]

type
  UndoOpKind = enum
    Delete
    Insert
  UndoOp = ref object
    case kind: UndoOpKind
    of Delete:
      selection: Selection
    of Insert:
      cursor: Cursor
      text: string

type TextDocument* = ref object of Document
  filename*: string
  lines*: seq[string]

  textChanged*: Event[TextDocument]
  singleLine*: bool

  undoOps*: seq[UndoOp]
  redoOps*: seq[UndoOp]

  tsParser: ptr ts.TSParser
  currentTree: ptr ts.TSTree
  highlightQuery: ptr ts.TSQuery

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

  selectionInternal: Selection
  selectionHistory: Deque[Selection]

  targetColumn: int
  hideCursorWhenInactive*: bool

  modeEventHandler: EventHandler
  currentMode*: string

  scrollOffset*: float
  previousBaseIndex*: int

  lastRenderedLines*: seq[StyledLine]

proc handleAction(self: TextDocumentEditor, action: string, arg: string): EventResponse
proc handleInput(self: TextDocumentEditor, input: string): EventResponse

proc subscribe*[T](event: var Event[T], callback: (T) -> void): Id =
  result = newId()
  event.handlers.add (result, callback)

proc unsubscribe*[T](event: var Event[T], id: Id) =
  for i, h in event.handlers:
    if h.id == id:
      event.handlers.del(i)
      break

proc invoke*[T](event: var Event[T], arg: T) =
  for h in event.handlers:
    h.callback(arg)

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

proc lineLength(self: TextDocument, line: int): int =
  if line < self.lines.len:
    return self.lines[line].len
  return 0

proc lineLength(self: TextDocumentEditor, line: int): int =
  if line < self.document.lines.len:
    return self.document.lines[line].len
  return 0

proc clampCursor*(self: TextDocumentEditor, cursor: Cursor): Cursor =
  var cursor = cursor
  if self.document.lines.len == 0:
    return (0, 0)
  cursor.line = clamp(cursor.line, 0, self.document.lines.len - 1)
  cursor.column = clamp(cursor.column, 0, self.lineLength cursor.line)
  return cursor

proc clampSelection*(self: TextDocumentEditor, selection: Selection): Selection =
  return (self.clampCursor(selection.first), self.clampCursor(selection.last))

proc selection*(self: TextDocumentEditor): Selection = self.selectionInternal

proc `selection=`*(self: TextDocumentEditor, selection: Selection) =
  if self.selectionInternal == selection:
    return

  self.selectionHistory.addLast self.selectionInternal
  if self.selectionHistory.len > 100:
    discard self.selectionHistory.popFirst
  self.selectionInternal = self.clampSelection selection

proc clampSelection*(self: TextDocumentEditor) =
  self.selection = self.selectionInternal

proc `content=`*(self: TextDocument, value: string) =
  if self.singleLine:
    self.lines = @[value.replace("\n", "")]
    if self.lines.len == 0:
      self.lines = @[""]
    if not self.tsParser.isNil:
      self.currentTree = self.tsParser.tsParserParseString(nil, self.lines[0], self.lines[0].len.uint32)
  else:
    self.lines = value.splitLines
    if self.lines.len == 0:
      self.lines = @[""]
    if not self.tsParser.isNil:
      self.currentTree = self.tsParser.tsParserParseString(nil, value, value.len.uint32)

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
    self.currentTree = self.tsParser.tsParserParseString(nil, strValue, strValue.len.uint32)

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

proc initTreesitter(self: TextDocument) =
  if not self.tsParser.isNil:
    self.tsParser.tsParserDelete()
    self.tsParser = nil
  if not self.highlightQuery.isNil:
    self.highlightQuery.tsQueryDelete()
    self.highlightQuery = nil

  var extension = self.filename.splitFile.ext
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
  else:
    # Unsupported language
    logger.log(lvlWarn, fmt"Unknown file extension '{extension}'")
    return

  template tryGetLanguage(constructor: untyped): untyped =
    block:
      var l: ptr TSLanguage = nil
      when compiles(constructor()):
        l = constructor()
      else:
        logger.log(lvlWarn, fmt"Language is not available: '{languageId}'")
        return
      l

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
  else:
    logger.log(lvlWarn, fmt"Failed to init treesitter for language '{extension}'")
    return

  self.tsParser = ts.tsParserNew()
  assert self.tsParser.tsParserSetLanguage(language) == true

  try:
    let queryString = readFile(fmt"./languages/{languageId}/queries/highlights.scm")
    var errorOffset: uint32 = 0
    var queryError: ts.TSQueryError = ts.TSQueryErrorNone
    self.highlightQuery = language.tsQueryNew(queryString, queryString.len.uint32, addr errorOffset, addr queryError)
    if queryError != ts.TSQueryErrorNone:
      logger.log(lvlError, fmt"[textedit] {queryError} at byte {errorOffset}: {queryString}")
  except:
    logger.log(lvlError, fmt"[textedit] No highlight queries found for '{languageId}'")

proc newTextDocument*(filename: string = "", content: string | seq[string] = ""): TextDocument =
  new(result)
  result.filename = filename
  result.currentTree = nil

  result.initTreesitter()

  result.content = content

proc destroy*(self: TextDocument) =
  if not self.tsParser.isNil:
    self.tsParser.tsParserDelete()

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

proc delete(self: TextDocument, selection: Selection, notify: bool = true, record: bool = true): Cursor =
  if selection.isEmpty:
    return selection.first
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
    self.currentTree = self.tsParser.tsParserParseString(self.currentTree, strValue, strValue.len.uint32)
    # echo self.currentTree.root

  if record:
    self.undoOps.add UndoOp(kind: Insert, cursor: selection.first, text: deletedText)
    self.redoOps = @[]

  if notify:
    self.notifyTextChanged()

  return selection.first

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

proc insert(self: TextDocument, oldCursor: Cursor, text: string, notify: bool = true, record: bool = true, autoIndent: bool = true): Cursor =
  var cursor = oldCursor
  let startByte = self.byteOffset(oldCursor).uint32

  var newEmptyLines: seq[int]

  var i: int = 0
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
      defer: inc i
      if i > 0:
        # Split line
        self.lines.insert(self.lines[cursor.line][cursor.column..^1], cursor.line + 1)
        newEmptyLines.add (cursor.line + 1)

        if cursor.column < self.lineLength cursor.line:
          self.lines[cursor.line].delete(cursor.column..<(self.lineLength cursor.line))
        cursor = (cursor.line + 1, 0)

      if line.len > 0:
        self.lines[cursor.line].insert(line, cursor.column)
        cursor.column += line.len

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
    self.currentTree = self.tsParser.tsParserParseString(self.currentTree, strValue, strValue.len.uint32)

  if autoIndent:
    for line in newEmptyLines:
      let indent = self.getTargetIndentForLine(line)
      cursor = self.insert((line, 0), ' '.repeat(indent), notify = false, record = false, autoIndent = false)

  if record:
    self.undoOps.add UndoOp(kind: Delete, selection: (oldCursor, cursor))
    self.redoOps = @[]

  if notify:
    self.notifyTextChanged()

  return cursor

proc edit(self: TextDocument, selection: Selection, text: string, notify: bool = true): Cursor =
  let selection = selection.normalized
  # echo "edit ", selection, ": ", self.lines
  var cursor = self.delete(selection, false)
  # echo "after delete ", cursor, ": ", self.lines
  cursor = self.insert(cursor, text)
  # echo "after insert ", cursor, ": ", self.lines
  return cursor

proc undo*(document: TextDocument): Option[Selection] =
  result = Selection.none

  if document.undoOps.len == 0:
    return

  let op = document.undoOps.pop[]

  case op.kind:
  of Delete:
    document.redoOps.add UndoOp(kind: Insert, cursor: op.selection.first, text: document.contentString(op.selection))
    result = document.delete(op.selection, record = false).toSelection.some

  of Insert:
    let cursor = document.insert(op.cursor, op.text, record = false, autoIndent = false)
    result = cursor.toSelection.some
    document.redoOps.add UndoOp(kind: Delete, selection: (op.cursor, cursor))
  else:
    discard

proc redo*(document: TextDocument): Option[Selection] =
  result = Selection.none

  if document.redoOps.len == 0:
    return

  let op = document.redoOps.pop[]

  case op.kind:
  of Delete:
    document.undoOps.add UndoOp(kind: Insert, cursor: op.selection.first, text: document.contentString(op.selection))
    result = document.delete(op.selection, record = false).toSelection.some

  of Insert:
    let cursor = document.insert(op.cursor, op.text, record = false, autoIndent = false)
    result = cursor.toSelection.some
    document.undoOps.add UndoOp(kind: Delete, selection: (op.cursor, cursor))
  else:
    discard

method canEdit*(self: TextDocumentEditor, document: Document): bool =
  if document of TextDocument: return true
  else: return false

method getEventHandlers*(self: TextDocumentEditor): seq[EventHandler] =
  if self.modeEventHandler.isNil:
    return @[self.eventHandler]
  return @[self.eventHandler, self.modeEventHandler]

method handleDocumentChanged*(self: TextDocumentEditor) =
  self.selection = (self.clampCursor self.selection.first, self.clampCursor self.selection.last)

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

proc scrollToCursor(self: TextDocumentEditor, cursor: Cursor) =
  let targetLine = cursor.line
  let totalLineHeight = self.editor.renderCtx.lineHeight + getOption[float32](self.editor, "text.line-distance")

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

proc moveCursor(self: TextDocumentEditor, cursor: SelectionCursor, movement: proc(doc: TextDocumentEditor, c: Cursor, off: int): Cursor, offset: int) =
  case cursor
  of Config:
    let configCursor = getOption[SelectionCursor](self.editor, self.getContextWithMode("editor.text.cursor.movement"), Both)
    self.moveCursor(configCursor, movement, offset)
  of Both:
    self.selection = movement(self, self.selection.last, offset).toSelection
    self.scrollToCursor(self.selection.last)
  of First:
    self.selection = (movement(self, self.selection.first, offset), self.selection.last)
    self.scrollToCursor(self.selection.first)
  of Last:
    self.selection = (self.selection.first, movement(self, self.selection.last, offset))
    self.scrollToCursor(self.selection.last)
  of LastToFirst:
    self.selection = (self.selection.last, movement(self, self.selection.last, offset))
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

proc insert(self: TextDocumentEditor, oldCursor: Cursor, text: string, notify: bool = true, record: bool = true, autoIndent: bool = true): Cursor {.expose("editor.text").} =
  self.document.insert(oldCursor, text, notify, record, autoIndent)

proc delete(self: TextDocumentEditor, selection: Selection, notify: bool = true, record: bool = true): Cursor {.expose("editor.text").} =
  self.document.delete(selection, notify, record)

proc selectPrev(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popLast
    self.selectionHistory.addFirst self.selection
    self.selectionInternal = selection
  self.scrollToCursor(self.selection.last)

proc selectNext(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selectionHistory.len > 0:
    let selection = self.selectionHistory.popFirst
    self.selectionHistory.addLast self.selection
    self.selectionInternal = selection
  self.scrollToCursor(self.selection.last)

proc selectInside(self: TextDocumentEditor, cursor: Cursor) {.expose("editor.text").} =
  let regex = re("[a-zA-Z0-9_]")
  var first = cursor.column
  echo self.document.lines[cursor.line], ", ", first, ", ", self.document.lines[cursor.line].matchLen(regex, start = first - 1)
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

proc insertText*(self: TextDocumentEditor, text: string) {.expose("editor.text").} =
  if self.document.singleLine and text == "\n":
    return

  self.selection = self.document.edit(self.selection, text).toSelection
  self.updateTargetColumn(Last)

proc undo(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.undo.getSome(selection):
    self.selection = selection

proc redo(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.document.redo.getSome(selection):
    self.selection = selection

proc scrollText(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  self.scrollOffset += amount

proc moveCursorColumn*(self: TextDocumentEditor, distance: int, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorColumn, distance)
  self.updateTargetColumn(cursor)

proc moveCursorLine*(self: TextDocumentEditor, distance: int, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLine, distance)

proc moveCursorHome*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorHome, 0)
  self.updateTargetColumn(cursor)

proc moveCursorEnd*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorEnd, 0)
  self.updateTargetColumn(cursor)

proc scrollToCursor*(self: TextDocumentEditor, cursor: SelectionCursor = SelectionCursor.Config) {.expose("editor.text").} =
  self.scrollToCursor(self.getCursor(cursor))

proc reloadTreesitter*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.document.initTreesitter()

proc deleteLeft*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selection.isEmpty:
    self.selection = self.document.delete((self.doMoveCursorColumn(self.selection.first, -1), self.selection.first)).toSelection
  else:
    self.selection = self.document.delete(self.selection).toSelection
  self.updateTargetColumn(Last)

proc deleteRight*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selection.isEmpty:
    self.selection = self.document.delete((self.selection.first, self.doMoveCursorColumn(self.selection.first, 1))).toSelection
  else:
    self.selection = self.document.delete(self.selection).toSelection
  self.updateTargetColumn(Last)

genDispatcher("editor.text")

proc handleAction(self: TextDocumentEditor, action: string, arg: string): EventResponse =
  # echo "[textedit] handleAction ", action, " '", arg, "'"
  if self.editor.handleUnknownDocumentEditorAction(self, action, arg) == Handled:
    return Handled

  var args = newJArray()
  args.add api.TextDocumentEditor(id: self.id).toJson
  for a in newStringStream(arg).parseJsonFragments():
    args.add a
  if dispatch(action, args).isSome:
    return Handled

  return Ignored

proc handleInput(self: TextDocumentEditor, input: string): EventResponse =
  # echo "handleInput '", input, "'"
  self.selection = self.document.edit(self.selection, input).toSelection
  self.updateTargetColumn(Last)
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

proc newTextEditor*(document: TextDocument, ed: Editor): TextDocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, document: document)
  editor.init()
  if editor.document.lines.len == 0:
    editor.document.lines = @[""]
  editor.injectDependencies(ed)
  discard document.textChanged.subscribe (_: TextDocument) => editor.clampSelection()
  return editor

method createWithDocument*(self: TextDocumentEditor, document: Document): DocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, document: TextDocument(document))
  editor.init()
  if editor.document.lines.len == 0:
    editor.document.lines = @[""]
  discard editor.document.textChanged.subscribe (_: TextDocument) => editor.clampSelection()
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