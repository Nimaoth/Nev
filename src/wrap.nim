
import std/[json, strutils, sequtils, tables, options, macros, genasts, macrocache, typetraits, sugar]
import util, macro_utils, myjsonutils

export macro_utils

proc createJsonWrapper*(def: NimNode, newName: NimNode): NimNode =
  # defer:
  #   echo "======================================================================= createJsonWrapper for "
  #   echo def.repr
  #   echo "------------------------------------------->"
  #   echo result.repr

  var callScriptFuncFromJson = nnkCall.newTree(def.name)

  # Argument of the JSON wrapper which calls the script function. Defined here so we can use it in the loop.
  let jsonArg = nskParam.genSym

  # Go through each parameter in reverse, fill out the args in `callImplFromScriptFunction`, `callScriptFuncFromScriptFuncWrapper`
  # and `callScriptFuncFromJson`
  let argCount = def[3].len - 1
  for k in 1..argCount:
    let i = argCount - k
    let originalArgumentType = def.argType i
    var mappedArgumentType = originalArgumentType
    let index = newLit(i)
    let isVarargs = newLit(def.isVarargs(i))

    let tempArg = if def.isVarargs(i):
      genAst(jsonArg, index): jsonArg[index..^1]
    else:
      genAst(jsonArg, index): jsonArg[index]

    let tempArg2 = genAst(jsonArg, index, mappedArgumentType): jsonArg[index].jsonTo(mappedArgumentType)

    # The argument for the call to scriptFunction in the wrapper
    let resWrapper = if def.argDefaultValue(i).getSome(default):
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            if `jsonArg`.len > `index`:
              `tempArg`
            else:
              `default`.toJson
          else:
            if `jsonArg`.len > `index`:
              `tempArg2`
            else:
              `default`
    else:
      quote do:
        block:
          when `originalArgumentType` is JsonNode:
            `tempArg`
          else:
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

  result = genAst(functionName = newName, call, argName = jsonArg):
    proc functionName*(argName: JsonNode): JsonNode {.nimcall, used.} =
      # try:
      call
      # except CatchableError:
      #   let name = `pureFunctionNameStr`
      #   echo "[editor] Failed to run function " & name & fmt": Invalid arguments: {getCurrentExceptionMsg()}"
      #   echo getCurrentException().getStackTrace

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
