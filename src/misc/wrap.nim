
import std/[json, tables, options, macros, genasts, macrocache]
import util, macro_utils, myjsonutils

export macro_utils

type
  JsonCallError* = object of CatchableError

proc createJsonWrapper*(def: NimNode, newName: NimNode): NimNode =
  # defer:
  #   echo "======================================================================= createJsonWrapper for "
  #   echo def.repr
  #   echo "------------------------------------------->"
  #   echo result.repr

  var callScriptFuncFromJson = nnkCall.newTree(def.name)

  # Argument of the JSON wrapper which calls the script function.
  # Defined here so we can use it in the loop.
  let jsonArg = nskParam.genSym

  # Go through each parameter in reverse, fill out the args in `callImplFromScriptFunction`,
  # `callScriptFuncFromScriptFuncWrapper` and `callScriptFuncFromJson`
  let argCount = def[3].len - 1
  for k in 1..argCount:
    let i = argCount - k
    let originalArgumentType = def.argType i
    var mappedArgumentType = originalArgumentType
    let index = newLit(i)

    let isJson = originalArgumentType.repr == "JsonNode"

    let tempArg = if def.isVarargs(i):
      genAst(jsonArg, index): jsonArg[index..^1]
    else:
      genAst(jsonArg, index, newName = def.name.repr.newLit):
        if index < jsonArg.elems.len:
          jsonArg[index]
        else:
          raise newException(JsonCallError, "Missing argument " & $(index + 1) & " for call to " & newName)

    let tempArg2 = genAst(jsonArg, index, mappedArgumentType, newName = def.name.repr.newLit):
      if index < jsonArg.elems.len:
        jsonArg[index].jsonTo(mappedArgumentType, JOptions(allowExtraKeys: true))
      else:
        raise newException(JsonCallError, "Missing argument " & $(index + 1) & " for call to " & newName)

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = if def.argDefaultValue(i).getSome(default):
      if isJson:
        quote do:
          if `jsonArg`.len > `index`:
            `tempArg`
          else:
            `default`.toJson
      else:
        quote do:
          if `jsonArg`.len > `index`:
            `tempArg2`
          else:
            `default`
    else:
      if isJson:
        quote do:
          `tempArg`
      else:
        quote do:
          `tempArg2`

    callScriptFuncFromJson.insert(1, resWrapper)

  let returnType = def.returnType

  let call = if returnType.isNone:
    genAst(callScriptFuncFromJson):
      callScriptFuncFromJson
      return newJNull()
  else:
    quote do:
      return `callScriptFuncFromJson`.toJson

  result = genAst(functionName = newName, functionNameStr = newName.repr, call, argName = jsonArg):
    proc functionName*(argName: JsonNode): JsonNode {.nimcall, used, raises: [JsonCallError].} =
      try:
        call
      except Exception as e:
        raise newException(JsonCallError, "Failed to call json wrapped function " & functionNameStr & ": " & e.msg, e)

proc serializeArgumentsToJson*(def: NimNode, targetUiae: NimNode): (NimNode, NimNode) =
  let argsName = genSym(nskVar)

  let init = genAst(target = argsName):
    var target = newJArray()

  var stmts = nnkStmtList.newTree(init)

  for i in 0..<(def[3].len - 1):
    let arg = def.argName(i)
    let typ = def.argType(i)
    let s = genAst(target = argsName, arg, typ):
      when typ is JsonNode:
        target.add arg
      else:
        target.add arg.toJson
    stmts.add s

  result = (stmts, argsName)

proc createJsonWrapper*(fun: NimNode, typ: NimNode, newName: NimNode): NimNode =
  ## Create a wrapper function with name `newName` for `fun` with the function type `typ`.
  ## The wrapper function takes a JsonNode as argument and calls `fun`,
  ## converting the arguments from JsonNode to parameter types of `fun`.
  ## The return value is converted to JsonNode.

  assert typ.kind == nnkBracketExpr
  assert typ[0].repr == "proc"

  var callScriptFuncFromJson = nnkCall.newTree(fun)

  # Argument of the JSON wrapper which calls the script function.
  # Defined here so we can use it in the loop.
  let jsonArg = nskParam.genSym

  # Go through each parameter in reverse, fill out the args in `callImplFromScriptFunction`,
  # `callScriptFuncFromScriptFuncWrapper` and `callScriptFuncFromJson`
  for i in countdown(typ.len - 1, 2):
    let originalArgumentType = typ[i]
    var mappedArgumentType = originalArgumentType.repr.parseExpr
    let index = newLit(i - 2)

    let tempArg = if false: # def.isVarargs(i): # todo
      genAst(jsonArg, index): jsonArg[index..^1]
    else:
      genAst(jsonArg, index, newName = typ.repr.newLit):
        if index < jsonArg.elems.len:
          jsonArg[index]
        else:
          raise newException(JsonCallError, "Missing argument " & $(index + 1) & " for call to " & newName)

    let tempArg2 = genAst(jsonArg, index, mappedArgumentType, name = typ.repr.newLit):
      if index < jsonArg.elems.len:
        jsonArg[index].jsonTo(mappedArgumentType, JOptions(allowExtraKeys: true))
      else:
        raise newException(JsonCallError, "Missing argument " & $(index + 1) & " for call to " & name)

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = quote do:
      block:
        when `originalArgumentType` is JsonNode:
          `tempArg`
        else:
          `tempArg2`

    callScriptFuncFromJson.insert(1, resWrapper)

  let returnType = typ[1]

  let call = if returnType.repr == "void":
    genAst(callScriptFuncFromJson):
      callScriptFuncFromJson
      return newJNull()
  else:
    quote do:
      return `callScriptFuncFromJson`.toJson

  result = genAst(functionName = newName, call, argName = jsonArg):
    proc functionName(argName: JsonNode): JsonNode {.nimcall, used.} =
      call
