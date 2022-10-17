type
  EditorType* = enum Text, Ast, Other
  DocumentEditor* = object of RootObj
    id*: int

  TextDocumentEditor* = object of DocumentEditor
  AstDocumentEditor* = object of DocumentEditor

type Cursor* = tuple[line, column: int]
type Selection* = tuple[first, last: Cursor]

proc `$`*(cursor: Cursor): string =
  return $cursor.line & ":" & $cursor.column

proc `$`*(selection: Selection): string =
  return $selection.first.line & ":" & $selection.first.column & "-" & $selection.last.line & ":" & $selection.last.column

func isBackwards*(selection: Selection): bool =
  if selection.last.line < selection.first.line:
    return true
  elif selection.last.line == selection.first.line and selection.last.column < selection.first.column:
    return true
  else:
    return false

proc normalized*(selection: Selection): Selection =
  if selection.isBackwards:
    return (selection.last, selection.first)
  else:
    return selection

func toSelection*(cursor: Cursor): Selection =
  (cursor, cursor)

func isEmpty*(selection: Selection): bool =
  return selection.first == selection.last