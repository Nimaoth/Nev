import std/[strutils, logging, sequtils, sugar, options, json, jsonutils, streams]
import editor, document, document_editor, events, id, util, scripting
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil

import treesitter/api as ts
import treesitter_javascript/javascript as tsjs

var logger = newConsoleLogger()

when not declared(c_malloc):
  proc c_malloc(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
  proc c_free(p: pointer): void {.importc: "free", header: "<stdlib.h>".}

type Event*[T] = object
  handlers: seq[tuple[id: Id, callback: (T) -> void]]

type TextDocument* = ref object of Document
  filename*: string
  lines: seq[string]

  textChanged*: Event[TextDocument]
  singleLine*: bool

  tsParser: ptr ts.TSParser
  currentTree: ptr ts.TSTree

type TextDocumentEditor* = ref object of DocumentEditor
  editor*: Editor
  document*: TextDocument
  selection: Selection
  hideCursorWhenInactive*: bool

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
proc root*(tree: ptr ts.TSTree): ts.TSNode = tree.tsTreeRootNode

proc `$`*(node: ts.TSNode): string =
  let c_str = node.tsNodeString()
  defer: c_str.c_free
  result = $c_str
  # for i in 0..node.high:
  #   str +=


proc `content=`*(document: TextDocument, value: string) =
  if document.singleLine:
    document.lines = @[value.replace("\n", "")]
    if document.lines.len == 0:
      document.lines = @[""]
    document.currentTree = document.tsParser.tsParserParseString(nil, document.lines[0], document.lines[0].len.uint32)
  else:
    document.lines = value.splitLines
    if document.lines.len == 0:
      document.lines = @[""]
    document.currentTree = document.tsParser.tsParserParseString(nil, value, value.len.uint32)

  let node = document.currentTree.tsTreeRootNode()

  document.textChanged.invoke(document)

proc `content=`*(document: TextDocument, value: seq[string]) =
  if document.singleLine:
    document.lines = @[value.join("")]
  else:
    document.lines = value.toSeq

  if document.lines.len == 0:
    document.lines = @[""]

  let strValue = value.join("\n")
  document.currentTree = document.tsParser.tsParserParseString(nil, strValue, strValue.len.uint32)

  let node = document.currentTree.tsTreeRootNode()
  echo node.tsNodeStartPoint
  echo node.tsNodeEndPoint

  document.textChanged.invoke(document)

func content*(document: TextDocument): seq[string] =
  return document.lines

func contentString*(document: TextDocument): string =
  return document.lines.join("\n")

func selection*(self: TextDocumentEditor): Selection = self.selection

proc newTextDocument*(filename: string = "", content: string | seq[string] = ""): TextDocument =
  new(result)
  result.filename = filename
  result.currentTree = nil

  result.tsParser = ts.tsParserNew()
  assert result.tsParser.tsParserSetLanguage(tsjs.treeSitterjavascript()) == true

  result.content = content


proc destroy*(doc: TextDocument) =
  doc.tsParser.tsParserDelete()

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
  self.lines = collect file.splitLines

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
  echo self.currentTree.root

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
  echo self.currentTree.root

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

proc moveCursorColumnImpl*(self: TextDocumentEditor, distance: int, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorColumn, distance)

proc moveCursorLineImpl*(self: TextDocumentEditor, distance: int, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorLine, distance)

proc moveCursorHomeImpl*(self: TextDocumentEditor, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorHome, 0)

proc moveCursorEndImpl*(self: TextDocumentEditor, cursor: string = "") {.expose("editor.text").} =
  self.moveCursor(cursor, doMoveCursorEnd, 0)

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