import std/[algorithm, sequtils, sugar]

type
  EditorId* = int
  EditorType* = enum Text, Ast, Other

  TextDocumentEditor* = object
    id*: EditorId
  AstDocumentEditor* = object
    id*: EditorId
  SelectorPopup* = object
    id*: EditorId

type Cursor* = tuple[line, column: int]
type Selection* = tuple[first, last: Cursor]
type SelectionCursor* = enum Config = "config", Both = "both", First = "first", Last = "last", LastToFirst = "last-to-first"
type LineNumbers* = enum None = "none", Absolute = "Absolute", Relative = "relative"
type Backend* = enum Gui = "gui", Terminal = "terminal"

type Selections* = seq[Selection]

proc normalize*(self: var Selections) =
  self.sort

proc normalized*(self: Selections): Selections =
  return self.sorted

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

func reverse*(selection: Selection): Selection = (selection.last, selection.first)

func isEmpty*(selection: Selection): bool = selection.first == selection.last

func contains*(selection: Selection, cursor: Cursor): bool = (cursor >= selection.first and cursor <= selection.last)
func contains*(selection: Selection, other: Selection): bool = (other.first >= selection.first and other.last <= selection.last)

func contains*(self: Selections, cursor: Cursor): bool = self.`any` (s) => s.contains(cursor)
func contains*(self: Selections, other: Selection): bool = self.`any` (s) => s.contains(other)

func `or`*(a: Selection, b: Selection): Selection =
  let an = a.normalized
  let bn = b.normalized
  return (min(an.first, bn.first), max(an.last, bn.last))

func toSelection*(cursor: Cursor): Selection =
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