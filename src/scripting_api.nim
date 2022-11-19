type
  EditorId* = distinct int
  PopupId* = distinct int
  EditorType* = enum Text, Ast, Other

  TextDocumentEditor* = object
    id*: EditorId
  AstDocumentEditor* = object
    id*: EditorId
  SelectorPopup* = object
    id*: PopupId

type Cursor* = tuple[line, column: int]
type Selection* = tuple[first, last: Cursor]
type SelectionCursor* = enum Config = "config", Both = "both", First = "first", Last = "last", LastToFirst = "last-to-first"
type LineNumbers* = enum None = "none", Absolute = "Absolute", Relative = "relative"

var nextEditorId = 0
proc newEditorId*(): EditorId =
  result = nextEditorId.EditorId
  nextEditorId += 1

proc newPopupId*(): PopupId =
  result = nextEditorId.PopupId
  nextEditorId += 1

func `==`*(a: EditorId, b: EditorId): bool = a.int == b.int
func `$`*(id: EditorId): string = $id.int

func `==`*(a: PopupId, b: PopupId): bool = a.int == b.int
func `$`*(id: PopupId): string = $id.int

func `$`*(cursor: Cursor): string =
  return $cursor.line & ":" & $cursor.column

func `$`*(selection: Selection): string =
  return $selection.first & "-" & $selection.last

func `<`*(a: Cursor, b: Cursor): bool =
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

func isBackwards*(selection: Selection): bool = selection.first > selection.last

func normalized*(selection: Selection): Selection =
  if selection.isBackwards:
    return (selection.last, selection.first)
  else:
    return selection

func reverse*(selection: Selection): Selection = (selection.last, selection.first)

func isEmpty*(selection: Selection): bool = selection.first == selection.last

func contains*(selection: Selection, cursor: Cursor): bool = (cursor >= selection.first and cursor <= selection.last)
func contains*(selection: Selection, other: Selection): bool = (other.first >= selection.first and other.last <= selection.last)

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
