import std/[strformat, tables, macros, json, strutils, sugar, sequtils, genasts, options, compilesettings]
import misc/[event, util, myjsonutils, macro_utils, embed_source]
import plugin_api, script_expose

export plugin_api, util, strformat, tables, json, strutils, sugar, sequtils, scripting_api, script_expose
export embed_source.embedSource, embed_source.currentSourceLocation

embedSource()

type AnyDocumentEditor = TextDocumentEditor | ModelDocumentEditor

var voidCallbacks = initTable[int, proc(args: JsonNode): void]()
var boolCallbacks = initTable[int, proc(args: JsonNode): bool]()
var anyCallbacks = initTable[int, proc(args: JsonNode): JsonNode]()
var onEditorModeChanged* = initEvent[tuple[editor: EditorId, oldMode: string, newMode: string]]()
var callbackId = 0

proc emscripten_notify_memory_growth*(a: int32) {.exportc.} = discard
const env* = "wasm"

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

proc addCallback*(action: proc(args: JsonNode): JsonNode): int =
  result = callbackId
  anyCallbacks[result] = action
  callbackId += 1

func toJsonString[T: string](value: T): string = escapeJson(value)
func toJsonString[T: char](value: T): string = escapeJson($value)
func toJsonString[T](value: T): string = $value

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

template isModelEditor*(editorId: EditorId, injected: untyped): bool =
  (scriptIsModelEditor(editorId) and ((let injected {.inject.} = ModelDocumentEditor(id: editorId); true)))

template isSelectorPopup*(editorId: EditorId, injected: untyped): bool =
  (scriptIsSelectorPopup(editorId) and ((let injected {.inject.} = SelectorPopup(id: editorId); true)))

proc handleCallbackImpl*(id: int, args: JsonNode): bool =
  # infof"handleCallbackImpl {id}, {args}"
  if voidCallbacks.contains(id):
    voidCallbacks[id](args)
    return true
  elif boolCallbacks.contains(id):
    return boolCallbacks[id](args)
  elif anyCallbacks.contains(id):
    return anyCallbacks[id](args).isNotNil
  return false

proc handleAnyCallbackImpl*(id: int, args: JsonNode): JsonNode =
  # infof"handleAnyCallbackImpl {id}, {args}"
  if voidCallbacks.contains(id):
    voidCallbacks[id](args)
    return newJNull()
  elif boolCallbacks.contains(id):
    return newJBool(boolCallbacks[id](args))
  elif anyCallbacks.contains(id):
    return anyCallbacks[id](args)
  return nil

proc handleScriptActionImpl*(name: string, args: JsonNode): JsonNode =
  # infof"handleScriptActionImpl {name}, {args}"
  if scriptActions.contains(name):
    return scriptActions[name](args)
  return nil

proc runAction*(id: EditorId, action: string, arg: string = "") =
  scriptRunActionFor(id, action, arg)

proc runAction*(editor: TextDocumentEditor, action: string, arg: string = "") =
  scriptRunActionFor(editor.id, action, arg)

proc selection*(editor: TextDocumentEditor): Selection =
  return editor.getSelection()

proc selections*(editor: TextDocumentEditor): seq[Selection] =
  return editor.getSelections()

proc `selection=`*(editor: TextDocumentEditor, selection: Selection) =
  editor.setSelection(selection)

proc `selections=`*(editor: TextDocumentEditor, selections: seq[Selection]) =
  editor.setSelections(selections)

proc `targetSelection=`*(editor: TextDocumentEditor, selection: Selection) =
  editor.setTargetSelection(selection)

proc getOption*[T](path: string, default: T = T.default): T =
  try:
    let json: JsonNode = plugin_api.getOptionJson(path, newJNull())
    return json.jsonTo T
  except:
    return default

proc setOption*[T](path: string, value: T) =
  plugin_api.setOption(path, value.toJson)

proc getSessionData*[T](path: string, default: T = T.default): T =
  return getSessionDataJson(path, default.toJson).jsonTo(T)

proc setSessionData*[T](path: string, value: T) =
  setSessionDataJson(path, value.toJson)

proc bindArgs*(args: NimNode): tuple[stmts: NimNode, arg: NimNode] =
  var stmts = nnkStmtList.newTree()
  let str = nskVar.genSym "str"
  stmts.addAst(str):
    var str = ""
  for arg in args:
    if arg.kind == nnkExprEqExpr:
      # todo: check name
      stmts.addAst(str, arg = arg[1]):
        str.add " "
        str.add arg.toJsonString
    else:
      stmts.addAst(str, arg):
        str.add " "
        str.add arg.toJsonString

  return (stmts, str)

var keysPrefix*: string = ""

template withKeys*(keys: varargs[string], body: untyped): untyped =
  for key in keys:
    let oldValue = keysPrefix
    keysPrefix = keysPrefix & key
    defer:
      keysPrefix = oldValue
    body

proc loadWorkspaceFile*(path: string, action: proc(content: Option[string]): void {.closure, gcsafe.}) =
  let key = "$loadWorkspaceFile" & $callbackId
  callbackId += 1
  scriptActions[key] = proc(args: JsonNode): JsonNode =
    action(args.jsonTo(Option[string]))
    scriptActions.del(key)
    return newJNull()
  addScriptAction(key, "", @[("path", "string"), ("callback", "proc(content: Option[string])")], "", false)
  loadWorkspaceFile(path, key)

proc runProcess*(process: string, args: seq[string], workingDir: Option[string] = string.none, eval: bool = false, callback: proc(output: string, err: string): void {.closure, gcsafe.} = nil) =
  let key = "$runProcess" & $callbackId
  callbackId += 1
  scriptActions[key] = proc(args: JsonNode): JsonNode =
    let args = args.jsonTo(Option[tuple[output: string, err: string]])
    if callback != nil and args.isSome:
      callback(args.get.output, args.get.err)
    scriptActions.del(key)
    return newJNull()
  addScriptAction(key, "", @[("process", "string"), ("args", "seq[string]"), ("workingDir", "Option[string]"), ("callback", "proc(content: Option[string])")], "", false)
  runProcess(process, args, key.some, workingDir, eval)

macro addCommand*(context: string, keys: string, action: string, args: varargs[untyped]): untyped =
  let (stmts, str) = bindArgs(args)
  return genAst(stmts, context, keys, action, str):
    stmts
    addCommandScript(context, "", keysPrefix & keys, action, str, source = currentSourceLocation(-2))

proc addCommand*(context: string, keys: string, action: proc(): void, source = currentSourceLocation()) =
  let key = "$" & context & keys
  scriptActions[key] = proc(args: JsonNode): JsonNode =
    action()
    return newJNull()

  # addCommandScript(context, "", keysPrefix & keys, "lambda-action", key.toJsonString)
  addCommandScript(context, "", keysPrefix & keys, key, "", source = source)

proc addCommandDesc(context: string, keys: string, desc: string, action: proc(): void, source = currentSourceLocation()) =
  let key = "$" & context & keys
  scriptActions[key] = proc(args: JsonNode): JsonNode =
    action()
    return newJNull()

  addCommandScript(context, "", keysPrefix & keys, key, "", desc, source)

proc addCommand*[T: proc](context: string, keys: string, args: string, action: T, source = currentSourceLocation()) =
  let key = "$" & context & keys
  scriptActions[key] = proc(args: JsonNode): JsonNode =
    return callJson(action, args)

  addCommandScript(context, "", keysPrefix & keys, key, args, source = source)

proc addCommandDesc[T: proc](context: string, keys: string, args: string, desc: string, action: T, source = currentSourceLocation()) =
  let key = "$" & context & keys
  scriptActions[key] = proc(args: JsonNode): JsonNode =
    return callJson(action, args)

  addCommandScript(context, "", keysPrefix & keys, key, args, desc, source)

template addCommandBlock*(context: string, keys: string, body: untyped): untyped =
  block:
    let p = proc() =
      body
    addCommand context, keys, p, currentSourceLocation(-2)

template addCommandBlockDesc*(context: string, keys: string, desc: string, body: untyped): untyped =
  block:
    let p = proc() =
      body
    addCommandDesc context, keys, desc, p, currentSourceLocation(-2)

func getContextWithMode*(context: string, mode: string): string =
  if mode.contains("."):
    return mode
  if mode.len == 0 or mode[0] == '#':
    return context & mode
  else:
    return context & "." & mode

# App commands
template addEditorCommandBlock*(mode: string, keys: string, body: untyped): untyped =
  addCommand getContextWithMode("editor", mode), keys, proc() =
    body

proc addEditorCommand*(mode: string, keys: string, action: proc(): void, source = currentSourceLocation()) =
  block:
    let p = proc() =
      action()
    addCommand getContextWithMode("editor", mode), keys, p, source = source

macro addEditorCommand*(mode: string, keys: string, action: string, args: varargs[untyped]): untyped =
  var stmts = nnkStmtList.newTree()
  let str = nskVar.genSym "str"
  stmts.add quote do:
    var `str` = ""
  for arg in args:
    stmts.add quote do:
      `str`.add " "
      `str`.add `arg`.toJsonString

  return genAst(stmts, mode, keys, action, str):
    stmts
    addCommandScript(getContextWithMode("editor", mode), "", keysPrefix & keys, action, str, source = currentSourceLocation(-2))

# Text commands
template addTextCommandBlock*(mode: string, keys: string, body: untyped): untyped =
  block:
    let p = proc() =
      try:
        let editor {.inject, used.} = TextDocumentEditor(id: getActiveEditor())
        body
      except:
        let m {.inject.} = mode
        let k {.inject.} = keys
        infof"TextCommandBlock {m} {k}: {getCurrentExceptionMsg()}"
    addCommand getContextWithMode("editor.text", mode), keys, p, currentSourceLocation(-2)

template addTextCommandBlockDesc*(mode: string, keys: string, desc: string, body: untyped): untyped =
  block:
    let p = proc() =
      try:
        let editor {.inject, used.} = TextDocumentEditor(id: getActiveEditor())
        body
      except:
        let m {.inject.} = mode
        let k {.inject.} = keys
        infof"TextCommandBlock {m} {k}: {getCurrentExceptionMsg()}"
    addCommandDesc getContextWithMode("editor.text", mode), keys, desc, p, currentSourceLocation(-2)


proc addTextCommand*(mode: string, keys: string, action: proc(editor: TextDocumentEditor): void, source = currentSourceLocation()) =
  block:
    let context = getContextWithMode("editor.text", mode)
    let p = proc() =
      try:
        action(TextDocumentEditor(id: getActiveEditor()))
      except:
        let m {.inject.} = mode
        let k {.inject.} = keys
        infof"TextCommand {m} {k}: {getCurrentExceptionMsg()}"
    addCommand context, keys, p, source = source

macro addTextCommand*(mode: string, keys: string, action: string, args: varargs[untyped]): untyped =
  let (stmts, str) = bindArgs(args)
  return genAst(stmts, mode, keys, action, str):
    stmts
    addCommandScript(getContextWithMode("editor.text", mode), "", keysPrefix & keys, action, str, source = currentSourceLocation(-2))

proc setTextInputHandler*(context: string, action: proc(editor: TextDocumentEditor, input: string): bool) =
  let id = addCallback proc(args: JsonNode): bool =
    try:
      let input = args.str
      return action(TextDocumentEditor(id: getActiveEditor()), input)
    except:
      infof"TextInputHandler {context}: {getCurrentExceptionMsg()}"

  scriptSetCallback("editor.text.input-handler." & context, id)
  setHandleInputs("editor.text." & context, true)

var customMoves = initTable[string, proc(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection]()
proc handleCustomTextMove*(editor: TextDocumentEditor, move: string, cursor: Cursor, count: int): Option[Selection] =
  if customMoves.contains(move):
    return customMoves[move](editor, cursor, count).some
  return Selection.none

block: # Custom moves
  let id = addCallback proc(args: JsonNode): JsonNode =
    type Payload = object
      editor: EditorId
      move: string
      cursor: Cursor
      count: int

    let input = args.jsonTo(Payload)
    if input.editor.isTextEditor editor:
      let selection = handleCustomTextMove(editor, input.move, input.cursor, input.count)
      if selection.isSome:
        return selection.toJson
      return nil
    else:
      infof"Custom move: editor {input.editor} is not a text editor"
      return nil

  scriptSetCallback("editor.text.custom-move", id)

proc addCustomTextMove*(name: string, action: proc(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection) =
  customMoves[name] = action

# Model commands
template addModelCommandBlock*(mode: static[string], keys: string, body: untyped): untyped =
  let context = getContextWithMode("editor.model", mode)
  addCommand context, keys, proc() =
    try:
      let editor {.inject, used.} = ModelDocumentEditor(id: getActiveEditor())
      body
    except:
      let m {.inject.} = mode
      let k {.inject.} = keys
      infof"ModelCommandBlock {m} {k}: {getCurrentExceptionMsg()}"

proc addModelCommand*(mode: string, keys: string, action: proc(editor: ModelDocumentEditor): void) =
  let context = getContextWithMode("editor.model", mode)
  addCommand context, keys, proc() =
    action(ModelDocumentEditor(id: getActiveEditor()))

macro addModelCommand*(mode: static[string], keys: string, action: string, args: varargs[untyped]): untyped =
  let context = getContextWithMode("editor.model", mode)
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
    addCommandScript(context, "", keysPrefix & keys, action, str, source = currentSourceLocation(-2))

proc setModelInputHandler*(context: string, action: proc(editor: ModelDocumentEditor, input: string): bool) =
  let id = addCallback proc(args: JsonNode): bool =
    let input = args.str
    action(ModelDocumentEditor(id: getActiveEditor()), input)
  scriptSetCallback("editor.model.input-handler." & context, id)
  setHandleInputs("editor.model." & context, true)

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

  proc plugin_main*() {.wasmexport.} =
    emscripten_stack_init()
    # init_pthread_self()
    NimMain()

  proc my_alloc*(len: uint32): pointer {.wasmexport.} =
    return alloc0(len)

  proc my_dealloc*(p: pointer) {.wasmexport.} =
    dealloc(p)

else:
  template wasmexport*(t: typed): untyped = t
