import std/[json, strformat, strutils, tables, options, macros, macrocache, typetraits]
import os
import compiler/options as copts
import util

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
  result.inter = loadScript(result.script, addins, ["scripting_api", "std/json"], stdPath = stdPath, searchPaths = @["src"], vmErrorHook = errorHook)

proc reloadScript*(ctx: ScriptContext) =
  ctx.inter.safeLoadScriptWithState(ctx.script, ctx.addins, ["scripting_api", "std/json"], stdPath = stdPath, searchPaths = @["src"], vmErrorHook = errorHook)

const mapperFunctions = CacheTable"MapperFunctions" # Maps from type name (referring to nim type) to function which maps these types
const typeWrapper = CacheTable"TypeWrapper"         # Maps from type name (referring to nim type) to type name of the api type (from scripting_api)
const functions = CacheTable"DispatcherFunctions"   # Maps from scope name to list of tuples of name and wrapper
const injectors = CacheTable"Injectors"             # Maps from type name (referring to nim type) to function

macro addTypeMap*(source: untyped, wrapper: typed, mapperFunction: typed) =
  mapperFunctions[$source] = mapperFunction
  typeWrapper[$source] = wrapper

macro addInjector*(name: untyped, function: typed) =
  injectors[$name] = function

macro addFunction(name: untyped, script: untyped, wrapper: typed, moduleName: static string) =
  let n = nnkStmtList.newTree(name, script, wrapper)
  for name, _ in functions:
    if name == moduleName:
      functions[name].add n
      return
  functions[moduleName] = nnkStmtList.newTree(n)

macro expose*(moduleName: static string, def: untyped): untyped =
  defer:
    discard
  #   echo result.repr

  let functionName = if def[0].kind == nnkPostfix: def[0][1] else: def[0]
  let argCount = def[3].len - 1
  let returnType = if def[3][0].kind != nnkEmpty: def[3][0].some else: NimNode.none
  proc argName(def: NimNode, arg: int): NimNode = def[3][arg + 1][0]
  proc argType(def: NimNode, arg: int): NimNode = def[3][arg + 1][1]
  proc argDefaultValue(def: NimNode, arg: int): Option[NimNode] =
    if def[3][arg + 1][2].kind != nnkEMpty:
      return def[3][arg + 1][2].some
    return NimNode.none

  let functionNameStr = functionName.strVal
  if not functionNameStr.endsWith("Impl"):
    return quote do:
      {.fatal: "Function name has to end with 'Impl': " & `functionNameStr`.}

  let pureFunctionName = ident functionNameStr[0..^5]

  var postfix = ""
  for module, functions in functions.pairs:
    for entry in functions:
      if pureFunctionName.strVal == $entry[0]:
        postfix.add("2")

  defer:
    discard
    # if pureFunctionName.strVal == "selectPrev":
    #   echo result.repr

  let wrapperName = ident(pureFunctionName.strVal & "Api" & postfix)
  var callToImplFromBuiltin = nnkCall.newTree(functionName)

  let jsonArg = nskParam.genSym

  let scriptFunctionSym = ident(pureFunctionName.strVal & "Script" & postfix)
  # let scriptFunctionSym = nskProc.genSym(pureFunctionName.strVal & "Scriptuiae")
  # let scriptFunctionName = ident $scriptFunctionSym
  # echo scriptFunctionName
  var scriptFunction = def.copy
  scriptFunction[0] = nnkPostfix.newTree(ident"*", scriptFunctionSym)
  var scriptFunctionWrapper = def.copy
  scriptFunctionWrapper[0] = pureFunctionName

  var callToBuiltinFunctionFromJson = nnkCall.newTree(scriptFunctionSym)
  var callToBuiltinFunctionFromScript = nnkCall.newTree(scriptFunctionSym)

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

    let originalArgumentType = def.argType i
    var mappedArgumentType = originalArgumentType
    let index = newLit(mappedArgIndices.getOrDefault(i, i))

    # Check if there is an entry in the type map and override mappedArgumentType if so
    # Also replace the argument type in the scriptFunction
    for source, target in typeWrapper.pairs:
      if source == $mappedArgumentType:
        mappedArgumentType = target
        scriptFunction[3][i + 1][1] = target
        scriptFunctionWrapper[3][i + 1][1] = target
        break

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = if def.argDefaultValue(i).getSome(default):
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            `jsonArg`[`index`]
          else:
            if `jsonArg`.len > `index`:
              `jsonArg`[`index`].jsonTo `mappedArgumentType`
            else:
              `default`
    else:
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            `jsonArg`[`index`]
          else:
            `jsonArg`[`index`].jsonTo `mappedArgumentType`

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
      if $mappedArgumentType == typeName:
        wasInjected = true
        scriptFunction[3].del(i + 1)
        scriptFunctionWrapper[3].del(i + 1)
        callFromScriptArg = quote do:
          block:
            let r = `function`()
            if r.isNone:
              return
            r.get
        break

    if not wasInjected:
      callToBuiltinFunctionFromJson.insert(1, resWrapper)
      callToBuiltinFunctionFromScript.insert(1, scriptFunctionWrapper.argName(i))
    callToImplFromBuiltin.insert(1, callFromScriptArg)

  scriptFunction[6] = quote do:
    `callToImplFromBuiltin`

  scriptFunctionWrapper[6] = quote do:
    `callToBuiltinFunctionFromScript`

  let adjustedCall = if returnType.isNone:
    callToBuiltinFunctionFromJson
  else:
    quote do:
      return `callToBuiltinFunctionFromJson`.toJson

  var scriptFunctionForward = scriptFunction.copy
  scriptFunctionForward[0] = scriptFunctionSym
  scriptFunctionForward[6] = newEmptyNode()

  return quote do:
    `def`

    `scriptFunction`

    proc `wrapperName`*(`jsonArg`: JsonNode): JsonNode {.nimcall, used.} =
      result = newJNull()
      try:
        `adjustedCall`
      except:
        let name = `functionNameStr`
        echo "[editor] Failed to run function " & name & fmt": Invalid arguments: {getCurrentExceptionMsg()}"
        echo getCurrentException().getStackTrace

    static:
      addToCache(`scriptFunctionSym`, "myImpl")
      addFunction(`pureFunctionName`, `scriptFunctionSym`, `wrapperName`, `moduleName`)
      exportCode("myImpl"):
        `scriptFunctionForward`
        `scriptFunctionWrapper`

macro genDispatcher*(moduleName: static string): untyped =
  # defer:
  #   echo result.repr

  let arg = nskParam.genSym "arg"
  let command = nskParam.genSym "command"
  let switch = nnkCaseStmt.newTree(command)
  for module, functions in functions.pairs:
    if module == moduleName:
      for entry in functions:
        let name = entry[0].strVal
        let target = entry[2]

        var alternative = ""
        for c in name:
          if c.isUpperAscii:
            alternative.add "-"
            alternative.add c.toLowerAscii
          else:
            alternative.add c

        if name == alternative:
          switch.add nnkOfBranch.newTree(newLit(name), quote do: `target`(`arg`).some)
        else:
          switch.add nnkOfBranch.newTree(newLit(name), newLit(alternative), quote do: `target`(`arg`).some)

  switch.add nnkElse.newTree(quote do: JsonNode.none)

  return quote do:
    proc dispatch(`command`: string, `arg`: JsonNode): Option[JsonNode] =
      result = `switch`