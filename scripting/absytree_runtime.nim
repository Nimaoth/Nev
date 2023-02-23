import std/[strformat, tables, macros, json, strutils, sugar, sequtils]

import absytree_api
export absytree_api, strformat, tables, json, strutils, sugar, sequtils, scripting_api

type AnyDocumentEditor = TextDocumentEditor | AstDocumentEditor

var lambdaActions = initTable[string, proc(): void]()
var voidCallbacks = initTable[int, proc(args: JsonNode): void]()
var boolCallbacks = initTable[int, proc(args: JsonNode): bool]()
var callbackId = 0

proc info*(args: varargs[string, `$`]) =
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  var result = newStringOfCap(msgLen + 5)
  for arg in args:
    result.add(arg)
  scriptLog(result)

proc addCallback*(action: proc(args: JsonNode): void): int =
  result = callbackId
  voidCallbacks[result] = action
  callbackId += 1

proc addCallback*(action: proc(args: JsonNode): bool): int =
  result = callbackId
  boolCallbacks[result] = action
  callbackId += 1

func toJsonString[T: string](value: T): string = escapeJson(value)
func toJsonString[T: char](value: T): string = escapeJson($value)
func toJsonString[T](value: T): string = $value

proc handleLambdaAction*(key: string): bool =
  if lambdaActions.contains(key):
    lambdaActions[key]()
    return true
  return false

proc removeCommand*(context: string, keys: string) =
  removeCommand(context, keys)

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

proc handleCallbackImpl*(id: int, args: JsonNode): bool =
  if voidCallbacks.contains(id):
    voidCallbacks[id](args)
    return true
  elif boolCallbacks.contains(id):
    return boolCallbacks[id](args)
  return false

proc runAction*(id: EditorId, action: string, arg: string = "") =
  scriptRunActionFor(id, action, arg)

proc runAction*(editor: TextDocumentEditor, action: string, arg: string = "") =
  scriptRunActionFor(editor.id, action, arg)

proc insertText*(editor: AnyDocumentEditor, text: string) =
  scriptInsertTextInto(editor.id, text)

proc selection*(editor: TextDocumentEditor): Selection =
  return scriptTextEditorSelection(editor.id)

proc `selection=`*(editor: TextDocumentEditor, selection: Selection) =
  scriptSetTextEditorSelection(editor.id, selection)

proc selections*(editor: TextDocumentEditor): seq[Selection] =
  return scriptTextEditorSelections(editor.id)

proc `selections=`*(editor: TextDocumentEditor, selection: seq[Selection]) =
  scriptSetTextEditorSelections(editor.id, selection)

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
  # echo "setOption ", path, ", ", value
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
    addCommandScript(`context`, `keys`, `action`, `str`)

proc addCommand*(context: string, keys: string, action: proc(): void) =
  let key = context & keys
  lambdaActions[key] = action
  addCommandScript(context, keys, "lambda-action", key.toJsonString)

template addCommandBlock*(context: static[string], keys: string, body: untyped): untyped =
  addCommand context, keys, proc() =
    body

# Editor commands
template addEditorCommandBlock*(mode: static[string], keys: string, body: untyped): untyped =
  let context = if mode.len == 0: "editor" else: "editor." & mode
  addCommand context, keys, proc() =
    body

proc addEditorCommand*(mode: string, keys: string, action: proc(): void) =
  let context = if mode.len == 0: "editor" else: "editor." & mode
  addCommand context, keys, proc() =
    action()

macro addEditorCommand*(mode: static[string], keys: string, action: string, args: varargs[untyped]): untyped =
  let context = if mode.len == 0: "editor" else: "editor." & mode
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
    addCommandScript(`context`, `keys`, `action`, `str`)

# Text commands
template addTextCommandBlock*(mode: static[string], keys: string, body: untyped): untyped =
  let context = if mode.len == 0: "editor.text" else: "editor.text." & mode
  addCommand context, keys, proc() =
    let editor {.inject.} = TextDocumentEditor(id: getActiveEditor())
    body

proc addTextCommand*(mode: string, keys: string, action: proc(editor: TextDocumentEditor): void) =
  let context = if mode.len == 0: "editor.text" else: "editor.text." & mode
  addCommand context, keys, proc() =
    action(TextDocumentEditor(id: getActiveEditor()))

macro addTextCommand*(mode: static[string], keys: string, action: string, args: varargs[untyped]): untyped =
  let context = if mode.len == 0: "editor.text" else: "editor.text." & mode
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
    addCommandScript(`context`, `keys`, `action`, `str`)

proc setTextInputHandler*(context: string, action: proc(editor: TextDocumentEditor, input: string): bool) =
  let id = addCallback proc(args: JsonNode): bool =
    let input = args.str
    action(TextDocumentEditor(id: getActiveEditor()), input)
  scriptSetCallback("editor.text.input-handler." & context, id)
  setHandleInputs("editor.text." & context, true)

# Text commands
template addAstCommandBlock*(mode: static[string], keys: string, body: untyped): untyped =
  let context = if mode.len == 0: "editor.ast" else: "editor.ast." & mode
  addCommand context, keys, proc() =
    let editor {.inject.} = AstDocumentEditor(id: getActiveEditor())
    body

proc addAstCommand*(mode: string, keys: string, action: proc(editor: AstDocumentEditor): void) =
  let context = if mode.len == 0: "editor.ast" else: "editor.ast." & mode
  addCommand context, keys, proc() =
    action(AstDocumentEditor(id: getActiveEditor()))

macro addAstCommand*(mode: static[string], keys: string, action: string, args: varargs[untyped]): untyped =
  let context = if mode.len == 0: "editor.ast" else: "editor.ast." & mode
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
    addCommandScript(`context`, `keys`, `action`, `str`)