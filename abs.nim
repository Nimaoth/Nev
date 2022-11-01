# import std/logging
import std/[strformat, tables, macros]

type AnyDocumentEditor = DocumentEditor | TextDocumentEditor | AstDocumentEditor
type AnyPopup = Popup

var lambdaActions = initTable[string, proc(): void]()

func toJsonString[T: string](value: T): string = "\"" & value & "\""
func toJsonString[T: char](value: T): string = "\"" & $value & "\""
func toJsonString[T](value: T): string = $value

macro addCommand*(context: string, keys: string, action: string, args: varargs[untyped]) =
  var stmts = nnkStmtList.newTree()
  let str = nskVar.genSym "str"
  stmts.add quote do:
    var `str` = ""
  for arg in args:
    stmts.add quote do:
      `str`.add " "
      `str`.add `arg`.toJsonString

  return quote do:
    `stmts`
    scriptAddCommand(`context`, `keys`, `action`, `str`)

proc addCommand*(context: string, keys: string, action: proc(): void) =
  let key = context & keys
  lambdaActions[key] = action
  scriptAddCommand(context, keys, "lambda-action", key)

proc handleLambdaAction*(key: string): bool =
  if lambdaActions.contains(key):
    lambdaActions[key]()
    return true
  return false

proc removeCommand*(context: string, keys: string) =
  scriptRemoveCommand(context, keys)

proc runAction*(action: string, arg: string = "") =
  scriptRunAction(action, arg)

template isTextEditor*(editor: DocumentEditor, injected: untyped): bool =
  ((let o = editor; scriptIsTextEditor(editor.id))) and ((let injected {.inject.} = editor.TextDocumentEditor; true))

template isAstEditor*(editor: DocumentEditor, injected: untyped): bool =
  ((let o = editor; scriptIsAstEditor(editor.id))) and ((let injected {.inject.} = editor.AstDocumentEditor; true))

proc getActiveEditor*(): DocumentEditor =
  return DocumentEditor(id: scriptGetActiveEditorHandle())

proc getEditor*(index: int): DocumentEditor =
  return DocumentEditor(id: scriptGetEditorHandle(index))

proc handleAction*(action: string, arg: string): bool
proc handleDocumentEditorAction*(editor: DocumentEditor, action: string, arg: string): bool
proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, arg: string): bool
proc handleAstEditorAction*(editor: AstDocumentEditor, action: string, arg: string): bool
proc handlePopupAction*(popup: Popup, action: string, arg: string): bool

proc handleGlobalAction*(action: string, arg: string): bool =
  if action == "lambda-action":
    return handleLambdaAction(arg)
  return handleAction(action, arg)

proc handleEditorAction*(id: EditorId, action: string, arg: string): bool =
  if action == "lambda-action":
    return handleLambdaAction(arg)

  let editor = DocumentEditor(id: id)

  if editor.isTextEditor(editor):
    return handleTextEditorAction(editor, action, arg)

  elif editor.isAstEditor(editor):
    return handleAstEditorAction(editor, action, arg)

  return handleDocumentEditorAction(editor, action, arg)

proc handleUnknownPopupAction*(id: EditorId, action: string, arg: string): bool =
  let popup = Popup(id: id)

  return handlePopupAction(popup, action, arg)

proc runAction*(editor: DocumentEditor, action: string, arg: string = "") =
  scriptRunActionFor(editor.id, action, arg)

proc runAction*(popup: Popup, action: string, arg: string = "") =
  scriptRunActionForPopup(popup.id, action, arg)

proc insertText*(editor: AnyDocumentEditor, text: string) =
  scriptInsertTextInto(editor.id, text)

proc selection*(editor: TextDocumentEditor): Selection =
  return scriptTextEditorSelection(editor.id)

proc `selection=`*(editor: TextDocumentEditor, selection: Selection) =
  scriptSetTextEditorSelection(editor.id, selection)

proc getLine*(editor: TextDocumentEditor, line: int): string =
  return scriptGetTextEditorLine(editor.id, line)

proc getLineCount*(editor: TextDocumentEditor): int =
  return scriptGetTextEditorLineCount(editor.id)

proc getOption*[T](path: string, default: T = T.default): T =
  when T is bool:
    return scriptGetOptionBool(path, default).T
  elif T is Ordinal:
    return scriptGetOptionInt(path, default).T
  elif T is float32 | float64:
    return scriptGetOptionFloat(path, default).T
  elif T is string:
    return scriptGetOptionString(path, default).T
  else:
    {.fatal: ("Can't get option with type " & $T).}

proc setOption*[T](path: string, value: T) =
  when T is bool:
    scriptSetOptionBool(path, value)
  elif T is Ordinal:
    scriptSetOptionInt(path, value.int)
  elif T is float32 | float64:
    scriptSetOptionFloat(path, value.float64)
  elif T is string:
    scriptSetOptionString(path, value)
  else:
    {.fatal: ("Can't set option with type " & $T).}

proc getFlag*(flag: string, default: bool = false): bool =
  return getOption[bool](flag, default)

proc setFlag*(flag: string, value: bool) =
  setOption[bool](flag, value)

proc log*(args: varargs[string, `$`]) =
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  var result = newStringOfCap(msgLen + 5)
  for arg in args:
    result.add(arg)
  scriptLog(result)