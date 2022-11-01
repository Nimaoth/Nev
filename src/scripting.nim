import std/[json, strformat, strutils, tables, options, macros, macrocache, typetraits]
import os
import compiler/options as copts

import nimscripter, nimscripter/[vmconversion, vmaddins]

type ScriptContext* = ref object
  inter*: Option[Interpreter]
  script: NimScriptPath
  addins: VMAddins

let stdPath = "C:/Users/nimao/.choosenim/toolchains/nim-#devel/lib"

proc errorHook(config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) {.gcsafe.} =
  if (severity == Error or severity == Warning) and config.errorCounter >= config.errorMax:
    var fileName: string
    for k, v in config.m.filenameToIndexTbl.pairs:
      if v == info.fileIndex:
        fileName = k
    echo fmt"[vm {severity}]: $1:$2:$3 $4." % [fileName, $info.line, $(info.col + 1), msg]
    raise (ref VMQuit)(info: info, msg: msg)

proc setGlobalVariable*[T](intr: Option[Interpreter] or Interpreter; name: string, value: T) =
  ## Easy access of a global nimscript variable
  when intr is Option[Interpreter]:
    assert intr.isSome
    let intr = intr.get
  let sym = intr.selectUniqueSymbol(name)
  if sym != nil:
    intr.setGlobalValue(sym, toVm(value))
  else:
    raise newException(VmSymNotFound, name & " is not a global symbol in the script.")

proc newScriptContext*(path: string, addins: VMAddins): ScriptContext =
  new result
  result.script = NimScriptPath(path)
  result.addins = addins
  result.inter = loadScript(result.script, addins, "scripting_api", stdPath = stdPath, searchPaths = @["src"], vmErrorHook = errorHook)

proc reloadScript*(ctx: ScriptContext) =
  ctx.inter.safeLoadScriptWithState(ctx.script, ctx.addins, "scripting_api", stdPath = stdPath, searchPaths = @["src"], vmErrorHook = errorHook)

when false:
  proc doThing(): int = 41
  proc log(str: string) = echo "[nim] ", str

  exportTo(myImpl, doThing, log)

  addCallable(myImpl):
    proc logScript(str: string)
  const
    scriptProcs = implNimScriptModule(myImpl)
    ourScript = NimScriptPath("script.nims")

  echo scriptProcs
  let intr = loadScript(ourScript, scriptProcs, stdPath = stdPath, vmErrorHook = errorHook)

  intr.invoke(logScript, "hi")

  getGlobalNimsVars intr:
    a: bool
    b: string
    c: int
    d: TestType
    e: TestType2

  echo a
  echo b
  echo c
  echo d
  print e

  var d2 = d
  d2.a += 2
  d2.b = "hi"
  d2.c[6] = "six"
  intr.setGlobalVariable("d", d2)

  intr.invoke(run)

const typeMap = CacheTable"TypeMap"
const typeWrapper = CacheTable"TypeWrapper"
const functions = CacheTable"DispatcherFunctions"

macro addTypeMap*(source: untyped, wrapper: typed, target: typed) =
  typeMap[$source] = target
  typeWrapper[$source] = wrapper

macro addFunction(source: untyped, wrapper: typed, moduleName: static string) =
  let n = nnkStmtList.newTree(source, wrapper)
  for name, _ in functions:
    if name == moduleName:
      functions[name].add n
      return
  functions[moduleName] = nnkStmtList.newTree(n)


macro expose*(moduleName: static string, def: untyped): untyped =
  defer:
    echo result.repr

  let functionName = if def[0].kind == nnkPostfix: def[0][1] else: def[0]
  let argCount = def[3].len - 1
  let returnType = if def[3][0].kind != nnkEmpty: def[3][0].some else: NimNode.none
  proc argType(def: NimNode, arg: int): NimNode = def[3][arg + 1][1]

  let functionNameStr = functionName.strVal
  let wrapperName = ident(functionNameStr[0..^5] & "Api")
  let returnsVoid = newLit(returnType.isNone)
  var callFromScript = nnkCall.newTree(functionName)

  let arg = nskParam.genSym

  let scriptFunctionName = ident(functionNameStr[0..^5])
  var scriptFunction = def.copy
  scriptFunction[0] = nnkPostfix.newTree(ident"*", scriptFunctionName)

  var call = nnkCall.newTree(scriptFunctionName)

  for i in 0..<argCount:
    let index = newLit(i)
    var at = def.argType i
    for source, target in typeWrapper.pairs:
      if source == $at:
        at = target
        scriptFunction[3][i + 1][1] = target
        break

    let resWrapper = quote do:
      block:
        `arg`[`index`].jsonTo `at`

    var resScript = scriptFunction[3][i + 1][0]
    for source, target in typeMap.pairs:
      if source == $def.argType(i):
        resScript = quote do:
          block:
            let r = `target`(`resScript`)
            if r.isNone:
              return
            r.get
        break

    call.add resWrapper
    callFromScript.add resScript

  scriptFunction[6] = quote do:
    block:
      `callFromScript`

  return quote do:
    `def`

    `scriptFunction`

    proc `wrapperName`*(`arg`: JsonNode): JsonNode {.nimcall, used.} =
      result = newJNull()
      try:
        when `returnsVoid`:
          `call`
        else:
          result = `call`.toJson
      except:
        let name = `functionNameStr`
        logger.log(lvlError, "[editor] Failed to run function " & name & fmt": Invalid arguments: {getCurrentExceptionMsg()}")
        echo getCurrentException().getStackTrace

    static:
      addToCache(`scriptFunctionName`, "myImpl")
      addFunction(`scriptFunctionName`, `wrapperName`, `moduleName`)

macro genDispatcher*(moduleName: static string): untyped =
  defer:
    echo result.repr

  let arg = nskParam.genSym "arg"
  let command = nskParam.genSym "command"
  let switch = nnkCaseStmt.newTree(command)
  for module, functions in functions.pairs:
    if module == moduleName:
      for entry in functions:
        let source = entry[0]
        let target = entry[1]
        switch.add nnkOfBranch.newTree(newLit($source), nnkCall.newTree(target, arg))
  switch.add nnkElse.newTree(quote do: newJNull())
  return quote do:
    proc dispatch(`command`: string, `arg`: JsonNode): JsonNode =
      result = newJNull()
      result = `switch`