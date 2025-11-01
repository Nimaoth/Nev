import std/[json, strutils, sequtils, tables, options, macros, genasts, macrocache, typetraits, sugar]
import fusion/matching
import misc/[util, custom_logger, macro_utils, wrap]
import compilation_config, dispatch_tables

const mapperFunctions = CacheTable"MapperFunctions" # Maps from type name (referring to nim type) to function which maps these types
const typeWrapper = CacheTable"TypeWrapper"         # Maps from type name (referring to nim type) to type name of the api type (from scripting_api)
const functions = CacheTable"DispatcherFunctions"   # Maps from scope name to list of tuples of name and wrapper
const injectors = CacheTable"Injectors"             # Maps from type name (referring to nim type) to function

template varargs*() {.pragma.}

macro addTypeMap*(source: untyped, wrapper: typed, mapperFunction: typed) =
  mapperFunctions[$source] = mapperFunction
  typeWrapper[$source] = wrapper

macro addInjector*(name: untyped, function: typed) =
  injectors[$name] = function

macro addFunction(name: untyped, original: typed, wrapper: typed, moduleName: static string, docs: typed) =
  ## Registers the nim function `name` in the module `moduleName`. `script` is a symbol referring
  ## to the version of this function with the 'Script' suffix, which is exported to the nim script.
  ## `wrapper`
  let n = nnkStmtList.newTree(name, wrapper, original, docs)
  for name, _ in functions:
    if name == moduleName:
      functions[name].add n
      return
  functions[moduleName] = nnkStmtList.newTree(n)

macro printDispatchStats*() =
  when defined(debugPrintDispatchStats):
    for moduleName, functions in functions:
      echo &"module '{moduleName}': {functions.len} functions"
  return nnkStmtList.newTree()

proc generateUniqueName*(moduleName: string, def: NimNode): string =
  result = moduleName
  result.add "_"

  if def[0].kind == nnkPostfix:
    result.add def[0][1].strVal
  else:
    result.add def[0].strVal

  let argCount = def[3].len - 1
  if def.returnType.getSome(returnType):
    result.add "_"
    result.add returnType.repr
  else:
    result.add "_void"

  for i in 0..<argCount:
    let originalArgumentType = def.argType i
    result.add "_"
    result.add originalArgumentType.repr

  return result.multiReplace(("[", "_"), ("]", "_"), ("(", "_"), (")", "_"), (":", "_"), (".", "_"), (",", "_"), (";", "_"), (" ", "")).multiReplace(("__", "_")).multiReplace(("__", "_")).multiReplace(("__", "_")).strip(chars={'_'})

proc removePragmas(node: var NimNode) =
  for param in node[3]:
    case param
    of IdentDefs[PragmaExpr[@name, .._], .._]:
      param[0] = name

macro expose*(moduleName: static string, def: untyped): untyped =
  if not exposeScriptingApi:
    return def

  var def = def

  let uniqueName = generateUniqueName(moduleName, def)

  let functionName = if def[0].kind == nnkPostfix: def[0][1] else: def[0]
  let argCount = def[3].len - 1
  let documentation = def.getDocumentation()
  let documentationStr = documentation.map((it) => it.strVal).get("").newLit
  let signature = nnkProcDef.newTree(newEmptyNode(), newEMptyNode(), newEmptyNode(), def[3], newEmptyNode(), newEmptyNode(), newEmptyNode())

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

  # The wrapper function which takes JSON arguments and returns JSON and internally calls the Nim function
  let jsonWrapperFunctionName = ident(uniqueName & "_json")

  # The script function is a wrapper around impl which translates some argument types
  # and inserts some arguments automatically using injectors. This function will be called from the json wrapper.
  # This function has a unique name, otherwise we can't call it from nimscript
  let scriptFunctionSym = ident(uniqueName & "_impl")
  var scriptFunction = def.copy
  scriptFunction[0] = nnkPostfix.newTree(ident"*", scriptFunctionSym)
  var callImplFromScriptFunction = nnkCall.newTree(functionName)

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

  # Go through each parameter in reverse, fill out the args in `callImplFromScriptFunction`
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
        break

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = if def.argDefaultValue(i).getSome(default):
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            when `isVarargs`:
              if `jsonArg`.len >= `index`:
                `jsonArg`[`index`..^1]
              else:
                @[]
            else:
              if `jsonArg`.len > `index`:
                `jsonArg`[`index`]
              else:
                raise newException(JsonCallError, "Failed to call json wrapped function: Not enough arguments! ")
          else:
            if `jsonArg`.len > `index`:
              var a = `mappedArgumentType`.default
              a.fromJson(`jsonArg`[`index`], JOptions(allowExtraKeys: true, allowMissingKeys: true))
              a
            else:
              `default`
    else:
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            when `isVarargs`:
              if `jsonArg`.len >= `index`:
                `jsonArg`[`index`..^1]
              else:
                @[]
            else:
              if `jsonArg`.len > `index`:
                `jsonArg`[`index`]
              else:
                raise newException(JsonCallError, "Failed to call json wrapped function: Not enough arguments! ")
          else:
            if `jsonArg`.len > `index`:
              var a = `mappedArgumentType`.default
              a.fromJson(`jsonArg`[`index`], JOptions(allowExtraKeys: true, allowMissingKeys: true))
              a
            else:
              raise newException(JsonCallError, "Failed to call json wrapped function: Not enough arguments! ")

    #
    var callFromScriptArg = scriptFunction.argName(i)

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
        callFromScriptArg = quote do:
          block:
            let r = `function`()
            if r.isNone:
              return
            r.get
        break

    if not wasInjected:
      callScriptFuncFromJson.insert(1, resWrapper)

    callImplFromScriptFunction.insert(1, callFromScriptArg)

  scriptFunction[6] = quote do:
    `callImplFromScriptFunction`

  let jsonWrapperFunction = createJsonWrapper(scriptFunction, jsonWrapperFunctionName)

  # todo: why do we remove pragmas again?
  removePragmas(def)
  removePragmas(scriptFunction)

  jsonWrapperFunction.addPragma(ident"gcsafe")
  scriptFunction.addPragma(ident"gcsafe")
  def.addPragma(ident"gcsafe")

  scriptFunction.addPragma(nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree()))
  def.addPragma(nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree()))

  result = quote do:
    `def`

    `scriptFunction`

  if not def.hasCustomPragma("nojsonwrapper"):
    result.add jsonWrapperFunction

  result.add quote do:
    static:
      # This makes the function dispatchable
      addFunction(`pureFunctionName`, `signature`, `jsonWrapperFunctionName`, `moduleName`, `documentationStr`)

  # echo "==========================="
  # echo result.repr

macro genDispatchTable*(moduleName: static string): untyped =
  var funcs = genSym(nskVar, "functionList")

  let blk = nnkStmtList.newTree()

  for module, functions in functions.pairs:
    if module == moduleName:
      for entry in functions:
        let name = entry[0].strVal
        let target = entry[1]
        let def: NimNode = entry[2]
        let docs = entry[3].strVal

        var alternative = ""
        for c in name:
          if c.isUpperAscii:
            alternative.add "-"
            alternative.add c.toLowerAscii
          else:
            alternative.add c

        let returnType = if def[3][0].kind == nnkEmpty: "" else: def[3][0].repr
        var params: seq[(string, string)] = @[]
        for param in def[3][1..^1]:
          params.add (param[0].repr, param[1].repr)

        let signature = "(" & params.mapIt(it[0] & ": " & it[1]).join(", ") & ")" & returnType

        let stm = genAst(funcs, n = alternative, d = target, ddocs = docs, pparams = params, rreturnType = returnType, ssignature = signature):
          funcs.add(ExposedFunction(name: n, dispatch: d, docs: ddocs, params: pparams, returnType: rreturnType, signature: ssignature))
        blk.add stm

  return genAst(funcs, blk):
    block:
      var funcs: seq[ExposedFunction] = @[]
      blk
      funcs

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
        let target = entry[1]

        var alternative = ""
        for c in name:
          if c.isUpperAscii:
            alternative.add "-"
            alternative.add c.toLowerAscii
          else:
            alternative.add c

        let call = genAst(target, arg):
          let res = target(arg)
          if res.isNil:
            return JsonNode.none
          return res.some

        if name == alternative:
          switch.add nnkOfBranch.newTree(newLit(name), call)
        else:
          switch.add nnkOfBranch.newTree(newLit(name), newLit(alternative), call)

  switch.add nnkElse.newTree(quote do: JsonNode.none)

  return quote do:
    proc dispatch(`command`: string, `arg`: JsonNode): Option[JsonNode] {.gcsafe, raises: [JsonCallError].} =
      result = `switch`
