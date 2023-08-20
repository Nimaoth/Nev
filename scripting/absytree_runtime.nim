import std/[strformat, tables, macros, json, strutils, sugar, sequtils, genasts]

import absytree_api, event, util, wrap
export absytree_api, util, strformat, tables, json, strutils, sugar, sequtils, scripting_api

type AnyDocumentEditor = TextDocumentEditor | AstDocumentEditor

var lambdaActions = initTable[string, proc(): void]()
var voidCallbacks = initTable[int, proc(args: JsonNode): void]()
var boolCallbacks = initTable[int, proc(args: JsonNode): bool]()
var onEditorModeChanged*: Event[tuple[editor: EditorId, oldMode: string, newMode: string]]
var callbackId = 0
var scriptActions = initTable[string, proc(args: JsonNode): JsonNode]()

when defined(wasm):
  const env* = "wasm"
else:
  const env* = "nims"

proc info*(args: varargs[string, `$`]) =
  var msgLen = 0
  for arg in args:
    msgLen += arg.len
  var result = newStringOfCap(msgLen + 12)
  result.add "["
  result.add env
  result.add "] "

  for arg in args:
    result.add(arg)
  scriptLog(result)

template infof*(x: static string) =
  scriptLog("[" & env & "] " & fmt(x))

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

proc handleLambdaAction*(args: JsonNode): bool =
  let key = args[0].str
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

proc handleScriptActionImpl*(name: string, args: JsonNode): JsonNode =
  if scriptActions.contains(name):
    return scriptActions[name](args)
  return nil

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

var keysPrefix: string = ""

template withKeys*(keys: varargs[string], body: untyped): untyped =
  for key in keys:
    let oldValue = keysPrefix & "" # do this to copy the value (only really necessary in nimscript for some reason)
    keysPrefix = keysPrefix & key
    defer:
      keysPrefix = oldValue
    body

macro addCommand*(context: string, keys: string, action: string, args: varargs[untyped]): untyped =
  var stmts = nnkStmtList.newTree()
  let str = nskVar.genSym "str"
  stmts.add quote do:
    var `str` = ""
  for arg in args:
    stmts.add quote do:
      `str`.add " "
      `str`.add `arg`.toJsonString

  return genAst(stmts, context, keys, action, str):
    stmts
    addCommandScript(context, keysPrefix & keys, action, str)

proc addCommand*(context: string, keys: string, action: proc(): void) =
  let key = context & keys
  lambdaActions[key] = action
  addCommandScript(context, keysPrefix & keys, "lambda-action", key.toJsonString)

template addCommandBlock*(context: static[string], keys: string, body: untyped): untyped =
  addCommand context, keys, proc() =
    body

# App commands
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

  return genAst(stmts, context, keys, action, str):
    stmts
    addCommandScript(context, keysPrefix & keys, action, str)

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

  return genAst(stmts, context, keys, action, str):
    stmts
    addCommandScript(context, keysPrefix & keys, action, str)

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

  return genAst(stmts, context, keys, action, str):
    stmts
    addCommandScript(context, keysPrefix & keys, action, str)

when defined(wasm):
  macro wasmexport*(t: typed): untyped =
    if t.kind notin {nnkProcDef, nnkFuncDef}:
      error("Can only export procedures", t)
    let
      newProc = copyNimTree(t)
      codeGen = nnkExprColonExpr.newTree(ident"codegendecl", newLit"EMSCRIPTEN_KEEPALIVE $# $#$#")
    if newProc[4].kind == nnkEmpty:
      newProc[4] = nnkPragma.newTree(codeGen)
    else:
      newProc[4].add codeGen
    newProc[4].add ident"exportC"
    result = newStmtList()
    result.add:
      quote do:
        {.emit: "/*INCLUDESECTION*/\n#include <emscripten.h>".}
    result.add:
      newProc

  proc NimMain() {.importc.}
  proc emscripten_stack_init() {.importc.}
  # proc init_pthread_self() {.importc.} # todo

  proc absytree_main*() {.wasmexport.} =
    emscripten_stack_init()
    # init_pthread_self()
    NimMain()

  proc my_alloc*(len: uint32): pointer {.wasmexport.} =
    return alloc0(len)

  proc my_dealloc*(p: pointer) {.wasmexport.} =
    dealloc(p)

else:
  template wasmexport*(t: typed): untyped = t

proc exportImpl(name: string, implementNims: bool, def: NimNode): NimNode =
  # defer:
  #   echo result.repr

  when defined(wasm):
    let jsonWrapperName = (def.name.repr & "Json").ident
    let jsonWrapper = createJsonWrapper(def, jsonWrapperName)

    let documentation = def.getDocumentation()
    let documentationStr = documentation.map((it) => it.strVal).get("").newLit

    let returnType = if def[3][0].kind == nnkEmpty: "" else: def[3][0].repr
    var params: seq[(string, string)] = @[]
    for param in def[3][1..^1]:
      params.add (param[0].repr, param[1].repr)

    return genAst(name, def, jsonWrapper, jsonWrapperName, documentationStr, params, returnType):
      def
      jsonWrapper

      static:
        echo "Expose script action ", name, " (", params, ", ", returnType, ")"
      scriptActions[name] = jsonWrapperName
      addScriptAction(name, documentationStr, params, returnType)

  else:
    let argsName2 = genSym(nskVar)
    let (addArgs, argsName) = def.serializeArgumentsToJson(argsName2)
    var call = genAst(name, argsName, addArgs):
      # var argsName = newJArray()
      addArgs
      let temp = callScriptAction(name, argsName)
      if not temp.isNil:
        return

    if implementNims:
      def.body.insert(0, call)
    else:
      def.body = call

    return def

macro scriptActionWasm*(name: static string, def: untyped): untyped =
  ## Register as a script action
  ## If called in wasm then it directly runs the function
  ## If called in nimscript the script action is executed instead
  return exportImpl(name, false, def)

macro scriptActionWasmNims*(name: static string, def: untyped): untyped =
  ## Register as a script action
  ## If called in wasm then it directly runs the function
  ## If called in nimscript the script action. If no script action is found, runs directly in nimscript
  return exportImpl(name, true, def)
