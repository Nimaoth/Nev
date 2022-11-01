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

const mapperFunctions = CacheTable"MapperFunctions" # Maps from type name (referring to nim type) to function which maps these types
const typeWrapper = CacheTable"TypeWrapper"         # Maps from type name (referring to nim type) to type name of the api type (from scripting_api)
const functions = CacheTable"DispatcherFunctions"   # Maps from scope name to list of tuples of name and wrapper
const injectors = CacheTable"Injectors"             # Maps from type name (referring to nim type) to function

macro addTypeMap*(source: untyped, wrapper: typed, mapperFunction: typed) =
  mapperFunctions[$source] = mapperFunction
  typeWrapper[$source] = wrapper

macro addInjector*(name: untyped, function: typed) =
  injectors[$name] = function

macro addFunction(name: untyped, wrapper: typed, moduleName: static string) =
  let n = nnkStmtList.newTree(name, wrapper)
  for name, _ in functions:
    if name == moduleName:
      functions[name].add n
      return
  functions[moduleName] = nnkStmtList.newTree(n)

macro expose*(moduleName: static string, def: untyped): untyped =
  # defer:
  #   echo result.repr

  let functionName = if def[0].kind == nnkPostfix: def[0][1] else: def[0]
  let argCount = def[3].len - 1
  let returnType = if def[3][0].kind != nnkEmpty: def[3][0].some else: NimNode.none
  proc argType(def: NimNode, arg: int): NimNode = def[3][arg + 1][1]

  let functionNameStr = functionName.strVal
  if not functionNameStr.endsWith("Impl"):
    return quote do:
      {.fatal: "Function name has to end with 'Impl': " & `functionNameStr`.}

  let wrapperName = ident(functionNameStr[0..^5] & "Api")
  let returnsVoid = newLit(returnType.isNone)
  var callFromScript = nnkCall.newTree(functionName)

  let arg = nskParam.genSym

  let scriptFunctionName = ident(functionNameStr[0..^5])
  var scriptFunction = def.copy
  scriptFunction[0] = nnkPostfix.newTree(ident"*", scriptFunctionName)

  var call = nnkCall.newTree(scriptFunctionName)

  var mappedArgIndices = initTable[int, int]()
  for i in 0..<argCount:
    var argumentType = def.argType i
    var wasInjected = false
    for typeName, function in injectors.pairs:
      if $argumentType == typeName:
        wasInjected = true
        break

    if not wasInjected:
      mappedArgIndices[i] = mappedArgIndices.len

  for k in 1..argCount:
    let i = argCount - k

    var argumentType = def.argType i
    let index = newLit(mappedArgIndices.getOrDefault(i, i))

    # Check if there is an entry in the type map and override argumentType if so
    # Also replace the argument type in the scriptFunction
    for source, target in typeWrapper.pairs:
      if source == $argumentType:
        argumentType = target
        scriptFunction[3][i + 1][1] = target
        break

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = quote do:
      block:
        `arg`[`index`].jsonTo `argumentType`

    #
    var callFromScriptArg = scriptFunction[3][i + 1][0]

    for source, mapperFunction in mapperFunctions.pairs:
      if source == $def.argType(i):
        callFromScriptArg = quote do:
          block:
            let r = `mapperFunction`(`callFromScriptArg`)
            if r.isNone:
              return
            r.get
        break

    var wasInjected = false

    # Check if the type is injected, if so replace callFromScriptArg
    # and remove the parameter from scriptFunction
    for typeName, function in injectors.pairs:
      if $argumentType == typeName:
        wasInjected = true
        scriptFunction[3].del(i + 1)
        callFromScriptArg = quote do:
          block:
            let r = `function`()
            if r.isNone:
              return
            r.get
        break

    if not wasInjected:
      call.insert(1, resWrapper)
    callFromScript.insert(1, callFromScriptArg)

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
        echo "[editor] Failed to run function " & name & fmt": Invalid arguments: {getCurrentExceptionMsg()}"
        echo getCurrentException().getStackTrace

    static:
      addToCache(`scriptFunctionName`, "myImpl")
      addFunction(`scriptFunctionName`, `wrapperName`, `moduleName`)

macro genDispatcher*(moduleName: static string): untyped =
  # defer:
  #   echo result.repr

  let arg = nskParam.genSym "arg"
  let command = nskParam.genSym "command"
  let switch = nnkCaseStmt.newTree(command)
  for module, functions in functions.pairs:
    if module == moduleName:
      for entry in functions:
        let source = entry[0]
        let target = entry[1]

        let name = $source

        var alternative = ""
        for c in name:
          if c.isUpperAscii:
            alternative.add "-"
            alternative.add c.toLowerAscii
          else:
            alternative.add c

        if name == alternative:
          switch.add nnkOfBranch.newTree(newLit(name), nnkCall.newTree(target, arg))
        else:
          switch.add nnkOfBranch.newTree(newLit(name), newLit(alternative), nnkCall.newTree(target, arg))

  switch.add nnkElse.newTree(quote do: newJNull())
  return quote do:
    proc dispatch(`command`: string, `arg`: JsonNode): JsonNode =
      result = newJNull()
      result = `switch`