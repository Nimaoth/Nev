type
  EditorId* = distinct int
  EditorType* = enum Text, Ast, Other
  DocumentEditor* = object of RootObj
    id*: EditorId
  Popup* = object of RootObj
    id*: EditorId

  TextDocumentEditor* = object of DocumentEditor
  AstDocumentEditor* = object of DocumentEditor

type Cursor* = tuple[line, column: int]
type Selection* = tuple[first, last: Cursor]

var nextEditorId = 0
proc newEditorId*(): EditorId =
  result = nextEditorId.EditorId
  nextEditorId += 1

func `==`*(a: EditorId, b: EditorId): bool = a.int == b.int

func `$`*(cursor: Cursor): string =
  return $cursor.line & ":" & $cursor.column

func `$`*(selection: Selection): string =
  return $selection.first & "-" & $selection.last

func isBackwards*(selection: Selection): bool =
  if selection.last.line < selection.first.line:
    return true
  elif selection.last.line == selection.first.line and selection.last.column < selection.first.column:
    return true
  else:
    return false

func normalized*(selection: Selection): Selection =
  if selection.isBackwards:
    return (selection.last, selection.first)
  else:
    return selection

func toSelection*(cursor: Cursor): Selection =
  (cursor, cursor)

func isEmpty*(selection: Selection): bool =
  return selection.first == selection.last