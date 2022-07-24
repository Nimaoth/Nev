import std/[strformat, strutils, algorithm, math, logging, unicode, sequtils]
import print
import input, document, document_editor, events

var logger = newConsoleLogger()

type Cursor = tuple[line, column: int]
type Selection = tuple[first, last: Cursor]

type TextDocument* = ref object of Document
  filename*: string
  content*: seq[string]

type TextDocumentEditor* = ref object of DocumentEditor
  document*: TextDocument
  selection*: Selection

method `$`*(document: TextDocument): string =
  return document.filename

proc `$`*(cursor: Cursor): string =
  return "$1:$2" % [$cursor.line, $cursor.column]

proc `$`*(selection: Selection): string =
  return "$1:$2-$3:$4" % [$selection.first.line, $selection.first.column, $selection.last.line, $selection.last.column]

proc toSelection(cursor: Cursor): Selection =
  (cursor, cursor)

proc isEmpty(selection: Selection): bool =
  return selection.first == selection.last

proc lineLength(self: TextDocument, line: int): int =
  if line < self.content.len:
    return self.content[line].len
  return 0

proc isBackwards(selection: Selection): bool =
  if selection.last.line < selection.first.line:
    return true
  elif selection.last.line == selection.first.line and selection.last.column < selection.first.column:
    return true
  else:
    return false

proc normalized(selection: Selection): Selection =
  if selection.isBackwards:
    return (selection.last, selection.first)
  else:
    return selection

proc delete(self: TextDocument, selection: Selection): Cursor =
  if selection.isEmpty:
    return selection.first

  let (first, last) = selection.normalized
  # echo "delete: ", selection, ", content = ", self.content
  if first.line == last.line:
    # Single line selection
    self.content[last.line].delete first.column..<last.column
  else:
    # Multi line selection
    # Delete from first cursor to end of first line and add last line
    if first.column < self.lineLength first.line:
      self.content[first.line].delete(first.column..<(self.lineLength first.line))
    self.content[first.line].add self.content[last.line][last.column..^1]
    # Delete all lines in between
    self.content.delete (first.line + 1)..last.line

  return selection.first

proc insert(self: TextDocument, cursor: Cursor, text: string): Cursor =
  var cursor = cursor
  var i: int = 0
  # echo "insert ", cursor, ": ", text
  for line in text.splitLines(false):
    defer: inc i
    if i > 0:
      # Split line
      self.content.insert(self.content[cursor.line][cursor.column..^1], cursor.line + 1)
      if cursor.column < self.lineLength cursor.line:
        self.content[cursor.line].delete(cursor.column..<(self.lineLength cursor.line))
      cursor = (cursor.line + 1, 0)

    if line.len > 0:
      self.content[cursor.line].insert(line, cursor.column)
      cursor.column += line.len

  return cursor

proc edit(self: TextDocument, selection: Selection, text: string): Cursor =
  let selection = selection.normalized
  # echo "edit ", selection, ": ", self.content
  var cursor = self.delete(selection)
  # echo "after delete ", cursor, ": ", self.content
  cursor = self.insert(cursor, text)
  # echo "after insert ", cursor, ": ", self.content
  return cursor

method canEdit*(self: TextDocumentEditor, document: Document): bool =
  if document of TextDocument: return true
  else: return false

method getEventHandlers*(self: TextDocumentEditor): seq[EventHandler] =
  return @[self.eventHandler]

proc lineLength(self: TextDocumentEditor, line: int): int =
  if line < self.document.content.len:
    return self.document.content[line].len
  return 0

proc clampCursor(self: TextDocumentEditor, cursor: Cursor): Cursor =
  var cursor = cursor
  if self.document.content.len == 0:
    return (0, 0)
  cursor.line = clamp(cursor.line, 0, self.document.content.len)
  cursor.column = clamp(cursor.column, 0, self.lineLength cursor.line)
  return cursor

proc moveCursorColumn(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  var cursor = cursor
  let column = cursor.column + offset
  if column < 0:
    if cursor.line > 0:
      cursor.line = cursor.line - 1
      cursor.column = self.lineLength cursor.line
    else:
      cursor.column = 0

  elif column > self.lineLength cursor.line:
    if cursor.line < self.document.content.len - 1:
      cursor.line = cursor.line + 1
      cursor.column = 0
    else:
      cursor.column = self.lineLength cursor.line

  else:
    cursor.column = column

  return self.clampCursor cursor

proc moveCursorLine(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  var cursor = cursor
  let line = cursor.line + offset
  if line < 0:
    cursor = (0, cursor.column)
  elif line >= self.document.content.len:
    cursor = (self.document.content.len - 1, cursor.column)
  else:
    cursor.line = line
  return self.clampCursor cursor

proc moveCursorHome(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
  return (cursor.line, 0)

proc moveCursorEnd(self: TextDocumentEditor, cursor: Cursor, offset: int): Cursor =
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

proc handleAction(self: TextDocumentEditor, action: string, arg: string): EventResponse =
  # echo "handleAction ", action, " '", arg, "'"
  case action
  of "backspace":
    if self.selection.isEmpty:
      self.selection = self.document.delete((self.moveCursorColumn(self.selection.first, -1), self.selection.first)).toSelection
    else:
      self.selection = self.document.edit(self.selection, "").toSelection
  of "delete":
    if self.selection.isEmpty:
      self.selection = self.document.delete((self.selection.first, self.moveCursorColumn(self.selection.first, 1))).toSelection
    else:
      self.selection = self.document.edit(self.selection, "").toSelection
  of "editor.insert": self.selection = self.document.edit(self.selection, arg).toSelection
  of "editor.newline": self.selection = self.document.edit(self.selection, "\n").toSelection
  of "cursor.left": self.moveCursor(arg, moveCursorColumn, -1)
  of "cursor.right": self.moveCursor(arg, moveCursorColumn, 1)
  of "cursor.up": self.moveCursor(arg, moveCursorLine, -1)
  of "cursor.down": self.moveCursor(arg, moveCursorLine, 1)
  of "cursor.home": self.moveCursor(arg, moveCursorHome, 0)
  of "cursor.end": self.moveCursor(arg, moveCursorEnd, 0)
  else:
    logger.log(lvlError, "[textedit] Unknown action '$1 $2'" % [action, arg])
  return Handled

proc handleInput(self: TextDocumentEditor, input: string): EventResponse =
  # echo "handleInput '", input, "'"
  self.selection = self.document.edit(self.selection, input).toSelection
  return Handled

method createWithDocument*(self: TextDocumentEditor, document: Document): DocumentEditor =
  let editor = TextDocumentEditor(eventHandler: nil, document: TextDocument(document))
  if editor.document.content.len == 0:
    editor.document.content = @[""]
  editor.eventHandler = eventHandler2:
    command "<LEFT>", "cursor.left"
    command "<RIGHT>", "cursor.right"
    command "<UP>", "cursor.up"
    command "<DOWN>", "cursor.down"
    command "<HOME>", "cursor.home"
    command "<END>", "cursor.end"
    command "<S-LEFT>", "cursor.left last"
    command "<S-RIGHT>", "cursor.right last"
    command "<S-UP>", "cursor.up last"
    command "<S-DOWN>", "cursor.down last"
    command "<S-HOME>", "cursor.home last"
    command "<S-END>", "cursor.end last"
    command "<ENTER>", "editor.insert \n"
    command "<SPACE>", "editor.insert  "
    command "<BACKSPACE>", "backspace"
    command "<DELETE>", "delete"
    onAction:
      editor.handleAction action, arg
    onInput:
      editor.handleInput input
  return editor