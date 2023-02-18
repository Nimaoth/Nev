

import std/[json, strformat, strutils, tables, options, macros, macrocache, typetraits]

import fusion/matching
import util, custom_logger
import compilation_config

when defined(js):
  macro addToCache*(sym: typed, moduleName: static string) =
    discard
else:
  import nimscripter

const mapperFunctions = CacheTable"MapperFunctions" # Maps from type name (referring to nim type) to function which maps these types
const typeWrapper = CacheTable"TypeWrapper"         # Maps from type name (referring to nim type) to type name of the api type (from scripting_api)
const functions = CacheTable"DispatcherFunctions"   # Maps from scope name to list of tuples of name and wrapper
const injectors = CacheTable"Injectors"             # Maps from type name (referring to nim type) to function
const exposedFunctions* = CacheTable"ExposedFunctions" # Maps from type name (referring to nim type) to type name of the api type (from scripting_api)

template varargs*() {.pragma.}

macro addTypeMap*(source: untyped, wrapper: typed, mapperFunction: typed) =
  mapperFunctions[$source] = mapperFunction
  typeWrapper[$source] = wrapper

macro addInjector*(name: untyped, function: typed) =
  injectors[$name] = function

macro addFunction(name: untyped, script: untyped, wrapper: typed, moduleName: static string) =
  ## Registers the nim function `name` in the module `moduleName`. `script` is a symbol referring
  ## to the version of this function with the 'Script' suffix, which is exported to the nim script.
  ## `wrapper`
  let n = nnkStmtList.newTree(name, script, wrapper)
  for name, _ in functions:
    if name == moduleName:
      functions[name].add n
      return
  functions[moduleName] = nnkStmtList.newTree(n)

macro addScriptWrapper(name: untyped, moduleName: static string, lineNumber: static int) =
  let val = nnkStmtList.newTree(name, newLit($lineNumber))
  for list, _ in exposedFunctions:
    if list == moduleName:
      exposedFunctions[list].add val
      return
  exposedFunctions[moduleName] = nnkStmtList.newTree(val)

macro expose*(moduleName: static string, def: untyped): untyped =
  if not exposeScriptingApi:
    return def

  defer:
    discard
  #   echo result.repr

  # echo def.repr
  # echo def.treeRepr

  let functionName = if def[0].kind == nnkPostfix: def[0][1] else: def[0]
  let argCount = def[3].len - 1
  let returnType = if def[3][0].kind != nnkEmpty: def[3][0].some else: NimNode.none
  proc argName(def: NimNode, arg: int): NimNode =
    result = def[3][arg + 1][0]
    if result.kind == nnkPragmaExpr:
      result = result[0]
  proc isVarargs(def: NimNode, arg: int): bool =
    let node = def[3][arg + 1][0]
    if node.kind == nnkPragmaExpr and node.len >= 2 and node[1].kind == nnkPragma and node[1][0].strVal == "varargs":
      return true
    return false
  proc argType(def: NimNode, arg: int): NimNode = def[3][arg + 1][1]
  proc argDefaultValue(def: NimNode, arg: int): Option[NimNode] =
    if def[3][arg + 1][2].kind != nnkEMpty:
      return def[3][arg + 1][2].some
    return NimNode.none
  let documentation = if def[6].len > 0 and def[6][0].kind == nnkCommentStmt:
      def[6][0].some
    else:
      NimNode.none

  var runnableExampls: seq[NimNode] = @[]
  for n in def[6]:
    if (n.kind == nnkCommand or n.kind == nnkCall) and n.len > 0 and n[0].kind == nnkIdent and n[0].strVal == "runnableExamples":
      runnableExampls.add n

  # Name of the Nim function
  let pureFunctionNameStr = functionName.strVal
  let pureFunctionName = ident pureFunctionNameStr

  # Generate suffix to create a unique name, since function overloading is not supported for NimScript interop
  var suffix = ""
  for module, functions in functions.pairs:
    for entry in functions:
      if pureFunctionNameStr == entry[0].repr:
        suffix.add("2")

  # defer:
  #   if pureFunctionNameStr == "setMove":
  #     echo def.treeRepr
  #     echo result.repr

  # The wrapper function which takes JSON arguments and returns JSON and internally calls the Nim function
  let jsonWrapperFunctionName = ident(pureFunctionNameStr & "Api" & suffix)

  # The script function is a wrapper around impl which translates some argument types
  # and inserts some arguments automatically using injectors. This function will be called from the NimScript
  let scriptFunctionSym = ident(pureFunctionNameStr & "Script" & suffix)
  var scriptFunction = def.copy
  scriptFunction[0] = nnkPostfix.newTree(ident"*", scriptFunctionSym)
  var callImplFromScriptFunction = nnkCall.newTree(functionName)

  # Wrapper function for the script function which is inserted into NimScript. This
  var scriptFunctionWrapper = def.copy
  scriptFunctionWrapper[0] = nnkPostfix.newTree(ident"*", pureFunctionName)
  var callScriptFuncFromScriptFuncWrapper = nnkCall.newTree(scriptFunctionSym)

  proc removeVarargs(node: var NimNode) =
    for param in node[3]:
      case param
      of IdentDefs[PragmaExpr[@name, .._], .._]:
        param[0] = name

  removeVarargs(scriptFunction)
  removeVarargs(scriptFunctionWrapper)

  var callScriptFuncFromJson = nnkCall.newTree(scriptFunctionSym)

  var mappedArgIndices = initTable[int, int]()
  for i in 0..<argCount:
    var argumentType = def.argType i
    var wasInjected = false
    for typeName, function in injectors.pairs:
      if argumentType.repr == typeName:
        wasInjected = true
        break

    if not wasInjected:
      mappedArgIndices[i] = mappedArgIndices.len

  # Argument of the JSON wrapper which calls the script function. Defined here so we can use it in the loop.
  let jsonArg = nskParam.genSym

  # Go through each parameter in reverse, fill out the args in `callImplFromScriptFunction`, `callScriptFuncFromScriptFuncWrapper`
  # and `callScriptFuncFromJson`
  for k in 1..argCount:
    let i = argCount - k

    let originalArgumentType = def.argType i
    var mappedArgumentType = originalArgumentType
    let index = newLit(mappedArgIndices.getOrDefault(i, i))
    let isVarargs = newLit(def.isVarargs(i))
    # echo fmt"varargs {i}, {index}: ", isVarargs, ", ", def

    # Check if there is an entry in the type map and override mappedArgumentType if so
    # Also replace the argument type in the scriptFunction
    for source, target in typeWrapper.pairs:
      if source == mappedArgumentType.repr:
        mappedArgumentType = target
        scriptFunction[3][i + 1][1] = target
        scriptFunctionWrapper[3][i + 1][1] = target
        break

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = if def.argDefaultValue(i).getSome(default):
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            when `isVarargs`:
              `jsonArg`[`index`..^1]
            else:
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
            when `isVarargs`:
              `jsonArg`[`index`..^1]
            else:
              `jsonArg`[`index`]
          else:
            `jsonArg`[`index`].jsonTo `mappedArgumentType`

    #
    var callFromScriptArg = scriptFunction[3][i + 1][0]

    for source, mapperFunction in mapperFunctions.pairs:
      if source == def.argType(i).repr:
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
      if mappedArgumentType.repr == typeName:
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
      callScriptFuncFromJson.insert(1, resWrapper)
      callScriptFuncFromScriptFuncWrapper.insert(1, scriptFunctionWrapper.argName(i))
    callImplFromScriptFunction.insert(1, callFromScriptArg)

  scriptFunction[6] = quote do:
    `callImplFromScriptFunction`

  var scriptFunctionWrapperBody = nnkStmtList.newTree()
  if documentation.isSome:
    scriptFunctionWrapperBody.add documentation.get
  for n in runnableExampls:
    scriptFunctionWrapperBody.add n
  scriptFunctionWrapperBody.add callScriptFuncFromScriptFuncWrapper
  scriptFunctionWrapper[6] = scriptFunctionWrapperBody

  let callScriptFuncFromJsonWithReturn = if returnType.isNone:
    callScriptFuncFromJson
  else:
    quote do:
      return `callScriptFuncFromJson`.toJson

  let scriptFunctionWrapperRepr = scriptFunctionWrapper.repr
  let lineNumber = def.lineInfoObj.line

  return quote do:
    `def`

    `scriptFunction`

    proc `jsonWrapperFunctionName`*(`jsonArg`: JsonNode): JsonNode {.nimcall, used.} =
      result = newJNull()
      try:
        `callScriptFuncFromJsonWithReturn`
      except CatchableError:
        let name = `pureFunctionNameStr`
        echo "[editor] Failed to run function " & name & fmt": Invalid arguments: {getCurrentExceptionMsg()}"
        echo getCurrentException().getStackTrace

    static:
      addToCache(`scriptFunctionSym`, "myImpl")
      addFunction(`pureFunctionName`, `scriptFunctionSym`, `jsonWrapperFunctionName`, `moduleName`)

      addScriptWrapper(`scriptFunctionWrapperRepr`, `moduleName`, `lineNumber`)

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