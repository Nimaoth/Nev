import std/[strutils, logging, sequtils, sugar, options, json, jsonutils, streams, strformat, os]
import editor, document, document_editor, events, id, util, scripting, vmath
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil

import treesitter/api as ts

import treesitter_c/c
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

var logger = newConsoleLogger()

when not declared(c_malloc):
  proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
  proc c_free(p: pointer): void {.importc: "free", header: "<stdlib.h>".}

type Event*[T] = object
  handlers: seq[tuple[id: Id, callback: (T) -> void]]

type TextDocument* = ref object of Document
  filename*: string
  lines*: seq[string]

  textChanged*: Event[TextDocument]
  singleLine*: bool

  tsParser: ptr ts.TSParser
  currentTree: ptr ts.TSTree
  highlightQuery: ptr ts.TSQuery

type TextDocumentEditor* = ref object of DocumentEditor
  editor*: Editor
  document*: TextDocument
  selection: Selection
  hideCursorWhenInactive*: bool

  scrollOffset*: float
  previousBaseIndex*: int

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
proc selection*(node: ts.TSNode): Selection = (node.startPoint, node.endPoint)
proc root*(tree: ptr ts.TSTree): ts.TSNode = tree.tsTreeRootNode
proc execute*(cursor: ptr ts.TSQueryCursor, query: ptr ts.TSQuery, node: ts.TSNode) = cursor.tsQueryCursorExec(query, node)

proc setPointRange*(cursor: ptr ts.TSQueryCursor, selection: Selection) =
  cursor.tsQueryCursorSetPointRange(ts.TSPoint(row: selection.first.line.uint32, column: selection.first.column.uint32), ts.TSPoint(row: selection.last.line.uint32, column: selection.last.column.uint32))

proc getCaptureName(query: ptr ts.TSQuery, index: uint32): string =
  var length: uint32
  var str = ts.tsQueryCaptureNameForId(query, index, addr length)
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
  # for i in 0..node.high:
  #   str +=

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

  # echo self.currentTree.root

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

  # echo self.currentTree.root

  self.textChanged.invoke(self)

func content*(document: TextDocument): seq[string] =
  return document.lines

func contentString*(document: TextDocument): string =
  return document.lines.join("\n")

func selection*(self: TextDocumentEditor): Selection = self.selection

type StyledText* = object
  text*: string
  scope*: string

type StyledLine* = object
  parts*: seq[StyledText]

proc splitAt(line: var StyledLine, index: int) =
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

proc overrideStyle*(line: var StyledLine, first: int, last: int, scope: string) =
  var index = 0
  for i in 0..line.parts.high:
    if index == first and index + line.parts[i].text.len == last and line.parts[i].scope.len == 0:
      if line.parts[i].scope.len > 0:
        let text = line.parts[i].text
        let oldScope = line.parts[i].scope
        logger.log(lvlInfo, fmt"overriding scope of '{text}' ({oldScope}) with {scope}")
      line.parts[i].scope = scope
    index += line.parts[i].text.len

proc getStyledText*(self: TextDocument, i: int): StyledLine =
  var line = self.lines[i]
  var styledLine = StyledLine(parts: @[StyledText(text: line, scope: "")])

  if not self.tsParser.isNil and not self.highlightQuery.isNil:
    let cursor = ts.tsQueryCursorNew()

    cursor.setPointRange ((i, 0), (i, line.len))
    cursor.execute(self.highlightQuery, self.currentTree.root)

    var match = cursor.nextMatch()
    while match.isSome:
      defer: match = cursor.nextMatch()
      let captures = cast[ptr array[100, ts.TSQueryCapture]](match.get.captures)
      for k in 0..<match.get.capture_count.int:
        let scope = self.highlightQuery.getCaptureName(captures[k].index)

        let node = captures[k].node
        let nodeRange = node.selection

        if nodeRange.first.line == i:
          styledLine.splitAt(nodeRange.first.column)
        if nodeRange.last.line == i:
          styledLine.splitAt(nodeRange.last.column)

        let first = if nodeRange.first.line < i: 0 elif nodeRange.first.line == i: nodeRange.first.column else: line.len
        let last = if nodeRange.last.line < i: 0 elif nodeRange.last.line == i: nodeRange.last.column else: line.len

        styledLine.overrideStyle(first, last, scope)

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
  else:
    # Unsupported language
    logger.log(lvlWarn, fmt"Failed to init treesitter for language '{extension}'")
    return

  let language = case languageId
  of "c": treeSitterC()
  # of "bash": treeSitterBash()
  # of "csharp": treeSitterCSharp()
  # of "cpp": treeSitterCpp()
  # of "css": treeSitterCss()
  # of "go": treeSitterGo()
  # of "haskell": treeSitterHaskell()
  # of "html": treeSitterHtml()
  # of "java": treeSitterJava()
  of "javascript": treeSitterJavascript()
  # of "ocaml": treeSitterOcaml()
  # of "php": treeSitterPhp()
  # of "python": treeSitterPython()
  # of "ruby": treeSitterRuby()
  of "rust": treeSitterRust()
  # of "scala": treeSitterScala()
  # of "typescript": treeSitterTypescript()
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

proc lineLength(self: TextDocument, line: int): int =
  if line < self.lines.len:
    return self.lines[line].len
  return 0

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

proc delete(self: TextDocument, selection: Selection, notify: bool = true): Cursor =
  if selection.isEmpty:
    return selection.first

  let startByte = self.byteOffset(selection.first).uint32
  let endByte = self.byteOffset(selection.last).uint32

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

  if notify:
    self.notifyTextChanged()

  return selection.first

proc insert(self: TextDocument, oldCursor: Cursor, text: string, notify: bool = true): Cursor =
  var cursor = oldCursor
  let startByte = self.byteOffset(oldCursor).uint32

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
    # echo self.currentTree.root

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

proc clampSelection*(self: TextDocumentEditor) =
  self.selection = (self.clampCursor(self.selection.first), self.clampCursor(self.selection.last))

proc `selection=`*(self: TextDocumentEditor, selection: Selection) =
  self.selection = self.clampSelection selection

method canEdit*(self: TextDocumentEditor, document: Document): bool =
  if document of TextDocument: return true
  else: return false

method getEventHandlers*(self: TextDocumentEditor): seq[EventHandler] =
  return @[self.eventHandler]

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
  return self.clampCursor cursor

proc doMoveCursorHome(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return (cursor.line, 0)

proc doMoveCursorEnd(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return (cursor.line, self.document.lineLength cursor.line)

proc moveCursor(self: TextDocumentEditor, cursor: string, movement: proc(doc: TextDocumentEditor, c: Cursor, off: int): Cursor, offset: int) =
  case cursor
  of "":
    self.selection.last = movement(self, self.selection.last, offset)
    self.selection.first = self.selection.last
  of "first":
    self.selection.first = movement(self, self.selection.first, offset)
  of "last":
    self.selection.last = movement(self, self.selection.last, offset)
  else:
    logger.log(lvlError, "Unknown cursor " & cursor)

method handleScroll*(self: TextDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  self.scrollOffset += scroll.y * getOption[float](self.editor, "text.scroll-speed", 40)

proc getTextDocumentEditor(wrapper: api.TextDocumentEditor): Option[TextDocumentEditor] =
  if gEditor.isNil: return TextDocumentEditor.none
  if gEditor.getEditorForId(wrapper.id).getSome(editor):
    if editor of TextDocumentEditor:
      return editor.TextDocumentEditor.some
  return TextDocumentEditor.none

static:
  addTypeMap(TextDocumentEditor, api.TextDocumentEditor, getTextDocumentEditor)

proc toJson*(self: api.TextDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.text")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.TextDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc insertTextImpl*(self: TextDocumentEditor, text: string) {.expose("editor.text").} =
  if self.document.singleLine and text == "\n":
    return

  self.selection = self.document.edit(self.selection, text).toSelection

proc scrollTextImpl(self: TextDocumentEditor, amount: float32) {.expose("editor.text").} =
  self.scrollOffset += amount

proc moveCursorColumnImpl*(self: TextDocumentEditor, distance: int, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorColumn, distance)

proc moveCursorLineImpl*(self: TextDocumentEditor, distance: int, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLine, distance)

proc moveCursorHomeImpl*(self: TextDocumentEditor, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorHome, 0)

proc moveCursorEndImpl*(self: TextDocumentEditor, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorEnd, 0)

proc reloadTreesitterImpl*(self: TextDocumentEditor) {.expose("editor.text").} =
  self.document.initTreesitter()

proc backspaceImpl*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selection.isEmpty:
    self.selection = self.document.delete((self.doMoveCursorColumn(self.selection.first, -1), self.selection.first)).toSelection
  else:
    self.selection = self.document.edit(self.selection, "").toSelection

proc deleteImpl*(self: TextDocumentEditor) {.expose("editor.text").} =
  if self.selection.isEmpty:
    self.selection = self.document.delete((self.selection.first, self.doMoveCursorColumn(self.selection.first, 1))).toSelection
  else:
    self.selection = self.document.edit(self.selection, "").toSelection

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
  return Handled

method injectDependencies*(self: TextDocumentEditor, ed: Editor) =
  self.editor = ed
  self.editor.registerEditor(self)

  self.eventHandler = eventHandler(ed.getEventHandlerConfig("editor.text")):
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

method unregister*(self: TextDocumentEditor) =
  self.editor.unregisterEditor(self)