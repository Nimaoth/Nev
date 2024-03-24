import std/[algorithm, sequtils, sugar]

when defined(nimscript):
  type
    GVec2*[T] = object
      arr: array[2, T]
    Vec2* = GVec2[float]
else:
  import vmath
  export vmath

type
  EditorId* = int
  EditorType* = enum Text, Ast, Model, Other

  TextDocumentEditor* = object
    id*: EditorId
  AstDocumentEditor* = object
    id*: EditorId
  ModelDocumentEditor* = object
    id*: EditorId
  SelectorPopup* = object
    id*: EditorId

type CursorT*[T] = tuple[line: int, column: T]
type SelectionT*[T] = tuple[first, last: CursorT[T]]
type Cursor* = CursorT[int]
type Selection* = SelectionT[int]
type SelectionCursor* = enum Config = "config", Both = "both", First = "first", Last = "last", LastToFirst = "last-to-first"
type LineNumbers* = enum None = "none", Absolute = "Absolute", Relative = "relative"
type Backend* = enum Gui = "gui", Terminal = "terminal", Browser = "browser"

type Selections* = seq[Selection]

proc normalize*(self: var Selections) =
  self.sort

proc normalized*(self: Selections): Selections =
  return self.sorted

proc lastLineLen*(self: Selection): int =
  ## Returns the length of the selection on the last line covered by the selection
  if self.first.line == self.last.line:
    result = self.last.column - self.first.column
  else:
    result = self.last.column

proc byteIndexToCursor*(text: string, index: int): Cursor =
  ## Converts a byte index to a cursor
  var line = 0
  var column = 0
  for i in 0..<index:
    if text[i] == '\n':
      line += 1
      column = 0
    else:
      column += 1
  return (line, column)

var nextEditorId = 0
proc newEditorId*(): EditorId =
  ## Returns a new unique id for an editor
  result = nextEditorId.EditorId
  nextEditorId += 1

func `$`*(cursor: Cursor): string =
  return $cursor.line & ":" & $cursor.column

func `$`*(selection: Selection): string =
  return $selection.first & "-" & $selection.last

func `<`*(a: Cursor, b: Cursor): bool =
  ## Returns true if the cursor `a` comes before `b`
  if a.line < b.line:
    return true
  elif a.line == b.line and a.column < b.column:
    return true
  else:
    return false

func `>`*(a: Cursor, b: Cursor): bool =
  if a.line > b.line:
    return true
  elif a.line == b.line and a.column > b.column:
    return true
  else:
    return false

func min*(a: Cursor, b: Cursor): Cursor =
  if a < b:
    return a
  return b

func max*(a: Cursor, b: Cursor): Cursor =
  if a >= b:
    return a
  return b

func isBackwards*(selection: Selection): bool =
  ## Returns true if the first cursor of the selection is after the second cursor
  return selection.first > selection.last

func normalized*(selection: Selection): Selection =
  ## Returns the normalized selection, i.e. where first < last.
  ## Switches first and last if backwards.
  if selection.isBackwards:
    return (selection.last, selection.first)
  else:
    return selection

func `in`*(a: Cursor, b: Selection): bool =
  ## Returns true if the cursor is contained within the selection
  let b = b.normalized
  return a >= b.first and a <= b.last

func reverse*(selection: Selection): Selection = (selection.last, selection.first)

func isEmpty*(selection: Selection): bool = selection.first == selection.last
func allEmpty*(selections: Selections): bool = selections.allIt(it.isEmpty)

func contains*(selection: Selection, cursor: Cursor): bool = (cursor >= selection.first and cursor <= selection.last)
func contains*(selection: Selection, other: Selection): bool = (other.first >= selection.first and other.last <= selection.last)

func contains*(self: Selections, cursor: Cursor): bool = self.`any` (s) => s.contains(cursor)
func contains*(self: Selections, other: Selection): bool = self.`any` (s) => s.contains(other)

func `or`*(a: Selection, b: Selection): Selection =
  let an = a.normalized
  let bn = b.normalized
  return (min(an.first, bn.first), max(an.last, bn.last))

func toSelection*[T](cursor: CursorT[T]): SelectionT[T] =
  (cursor, cursor)

func toSelection*(cursor: Cursor, default: Selection, which: SelectionCursor): Selection =
  case which
  of Config: return default
  of Both: return (cursor, cursor)
  of First: return (cursor, default.last)
  of Last: return (default.first, cursor)
  of LastToFirst: return (default.last, cursor)

func subtract*(cursor: Cursor, selection: Selection): Cursor =
  if cursor <= selection.first:
    # cursor before selection
    return cursor
  if cursor <= selection.last:
    # cursor inside selection
    return selection.first
  if cursor.line == selection.last.line:
    # cursor after selection but on same line as end
    if selection.first.line == selection.last.line:
      return (cursor.line, cursor.column - (selection.last.column - selection.first.column))
    else:
      return (selection.first.line, selection.first.column + (cursor.column - selection.last.column))
  return (cursor.line - (selection.last.line - selection.first.line), cursor.column)

func subtract*(self: Selection, other: Selection): Selection =
  return (self.first.subtract(other), self.last.subtract(other))

func add*(cursor: Cursor, selection: Selection): Cursor =
  if cursor <= selection.first:
    # cursor before selection
    return cursor
  # cursor after start of selection
  if selection.first.line == selection.last.line:
    if cursor.line == selection.first.line:
      return (cursor.line, cursor.column + (selection.last.column - selection.first.column))
    else:
      return cursor
  elif cursor.line == selection.first.line:
    # cursor is on same line as start of selection
    return (selection.last.line, selection.last.column + (cursor.column - selection.first.column))
  else:
    # cursor is on line after start of selection
    return (cursor.line + (selection.last.line - selection.first.line), cursor.column)

func add*(self: Selection, other: Selection): Selection =
  return (self.first.add(other), self.last.add(other))

func mergeLines*(selections: Selections): Selections =
  for s in selections.sorted:
    let sn = s.normalized
    if result.len == 0 or result[result.high].last.line < sn.first.line:
      result.add sn
    else:
      result[result.high].last.line = sn.last.line