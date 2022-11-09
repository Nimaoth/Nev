# import std/logging
import std/[strformat, tables, macros]

type AnyDocumentEditor = TextDocumentEditor | AstDocumentEditor

var lambdaActions = initTable[string, proc(): void]()

func toJsonString[T: string](value: T): string = "\"" & value & "\""
func toJsonString[T: char](value: T): string = "\"" & $value & "\""
func toJsonString[T](value: T): string = $value

macro addCommand*(context: string, keys: string, action: string, args: varargs[untyped]): untyped =
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

macro runAction*(action: string, args: varargs[untyped]): untyped =
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
    scriptRunAction(`action`, `str`)

template isTextEditor*(editorId: EditorId, injected: untyped): bool =
  (scriptIsTextEditor(editorId) and ((let injected {.inject.} = TextDocumentEditor(id: editorId); true)))

template isAstEditor*(editorId: EditorId, injected: untyped): bool =
  (scriptIsAstEditor(editorId) and ((let injected {.inject.} = AstDocumentEditor(id: editorId); true)))

proc getActiveEditor*(): EditorId =
  return scriptGetActiveEditorHandle()

proc getActivePopup*(): PopupId =
  return scriptGetActivePopupHandle()

proc getTextEditor*(index: int): EditorId =
  return scriptGetEditorHandle(index)

proc handleAction*(action: string, arg: string): bool
proc handleDocumentEditorAction*(id: EditorId, action: string, arg: string): bool
proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, arg: string): bool
proc handleAstEditorAction*(editor: AstDocumentEditor, action: string, arg: string): bool
proc handlePopupAction*(popup: PopupId, action: string, arg: string): bool

proc handleGlobalAction*(action: string, arg: string): bool =
  if action == "lambda-action":
    return handleLambdaAction(arg)
  return handleAction(action, arg)

proc handleEditorAction*(id: EditorId, action: string, arg: string): bool =
  if action == "lambda-action":
    return handleLambdaAction(arg)

  if id.isTextEditor(editor):
    return handleTextEditorAction(editor, action, arg)

  elif id.isAstEditor(editor):
    return handleAstEditorAction(editor, action, arg)

  return handleDocumentEditorAction(id, action, arg)

proc handleUnknownPopupAction*(id: PopupId, action: string, arg: string): bool =
  return handlePopupAction(id, action, arg)

proc runAction*(id: EditorId, action: string, arg: string = "") =
  scriptRunActionFor(id, action, arg)

proc runAction*(id: PopupId, action: string, arg: string = "") =
  scriptRunActionForPopup(id, action, arg)

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
  elif T is enum:
    return parseEnum[T](scriptGetOptionString(path, ""), default)
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
  elif T is enum:
    scriptSetOptionString(path, $value)
  elif T is Ordinal:
    scriptSetOptionInt(path, value.int)
  elif T is float32 | float64:
    scriptSetOptionFloat(path, value.float64)
  elif T is string:
    scriptSetOptionString(path, value)
  else:
    {.fatal: ("Can't set option with type " & $T).}

proc log*(args: varargs[string, `$`]) =
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  var result = newStringOfCap(msgLen + 5)
  for arg in args:
    result.add(arg)
  scriptLog(result)