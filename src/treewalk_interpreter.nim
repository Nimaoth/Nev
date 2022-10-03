import std/[tables, strutils, sequtils, sugar, hashes, options, logging, strformat]
import fusion/matching
import pixie/fonts, bumpy, chroma, vmath
import compiler, ast, util, id, query_system

proc cacheValuesInFunction(ctx: Context, node: AstNode, values: var Table[Id, Value]) =
  case node.kind:
  of ConstDecl:
    if ctx.getValue(node).getSome(value):
      values[node.id] = value
  else:
    for child in node.children:
      ctx.cacheValuesInFunction(child, values)

proc executeNodeRec(ctx: Context, node: AstNode, variables: var Table[Id, Value]): Value =
  if ctx.enableExecutionLogging: inc currentIndent, 1
  defer:
    if ctx.enableExecutionLogging: dec currentIndent, 1
  if ctx.enableExecutionLogging: echo repeat2("| ", currentIndent - 1), "executeNodeRec ", node
  defer:
    if ctx.enableExecutionLogging: echo repeat2("| ", currentIndent), "-> ", result

  case node
  of Empty():
    return voidValue()

  of NodeList():
    var lastValue = errorValue()
    for child in node.children:
      lastValue = ctx.executeNodeRec(child, variables)
    return lastValue

  of StringLiteral():
    return Value(kind: vkString, stringValue: node.text)

  of NumberLiteral():
    let value = try: node.text.parseInt except: return errorValue()
    return Value(kind: vkNumber, intValue: value)

  of If():
    if node.len < 2:
      return errorValue()

    # Iterate through all ifs/elifs
    var index: int = 0
    while index + 1 < node.len:
      defer: index += 2

      let condition = node[index]
      let trueCase = node[index + 1]

      let conditionValue = ctx.executeNodeRec(condition, variables)
      if conditionValue.kind == vkError:
        return errorValue()

      if conditionValue.kind != vkNumber:
        logger.log(lvlError, fmt"[compiler] Condition of if statement must be an int but is {conditionValue}")
        return errorValue()

      if conditionValue.intValue != 0:
        let trueCaseValue = ctx.executeNodeRec(trueCase, variables)
        return trueCaseValue

    # else case
    if node.len mod 2 != 0:
      let falseCaseValue = ctx.executeNodeRec(node.last, variables)
      return falseCaseValue

    return voidValue()

  of While():
    if node.len < 2:
      return errorValue()

    let condition = node[0]
    let body = node[1]

    var index: int = 0
    while true:
      defer: index += 1
      if index > 1000:
        logger.log(lvlError, fmt"[compiler] Max loop iterations reached for {node}")
        return errorValue()

      let conditionValue = ctx.executeNodeRec(condition, variables)
      if conditionValue.kind == vkError:
        return errorValue()

      if conditionValue.kind != vkNumber:
        logger.log(lvlError, fmt"[compiler] Condition of if statement must be an int but is {conditionValue}")
        return errorValue()

      if conditionValue.intValue == 0:
        break

      let bodyValue = ctx.executeNodeRec(body, variables)
      if bodyValue.kind == vkError:
        return errorValue()

    return voidValue()

  of Identifier():
    let id = node.reff
    if variables.contains(id):
      return variables[id]

    if ctx.computeSymbol(node).getSome(sym):
      let value = ctx.computeSymbolValue(sym)
      variables[id] = value
      return value

    logger.log(lvlError, fmt"executeNodeRec {node}: Failed to look up value for identifier")
    return errorValue()

  of Call():
    let function = ctx.executeNodeRec(node[0], variables)

    case function.kind:
    of vkError:
      return errorValue()

    of vkBuiltinFunction:
      var args: seq[Value] = @[]
      for arg in node.children[1..^1]:
        let value = ctx.executeNodeRec(arg, variables)
        if value.kind == vkError:
          return errorValue()
        args.add value
      return function.impl(args)

    of vkAstFunction:
      var args: seq[Value] = @[]
      for arg in node.children[1..^1]:
        let value = ctx.executeNodeRec(arg, variables)
        if value.kind == vkError:
          return errorValue()
        args.add value
      let fec = ctx.newFunctionExecutionContext(FunctionExecutionContext(node: function.node, arguments: args))
      return ctx.computeFunctionExecution(fec)

    else:
      return errorValue()

  of LetDecl():
    if node.len < 2:
      return errorValue()
    let valueNode = node[1]
    let value = ctx.executeNodeRec(valueNode, variables)
    variables[node.id] = value
    return value

  of VarDecl():
    if node.len < 2:
      return errorValue()
    let valueNode = node[1]
    let value = ctx.executeNodeRec(valueNode, variables)
    variables[node.id] = value
    return value

  of ConstDecl():
    let id = node.id
    if variables.contains(id):
      return variables[id]

  of Assignment():
    if node.len < 2:
      return errorValue()
    let targetNode = node[0]
    let valueNode = node[1]
    if ctx.computeSymbol(targetNode).getSome(sym):
      let value = ctx.executeNodeRec(valueNode, variables)
      variables[sym.id] = value
      return voidValue()
    else:
      logger.log(lvlError, fmt"executeNodeRec {node}: Failed to assign to {targetNode}: no symbol found")
      return errorValue()

  else:
    logger.log(lvlError, fmt"executeNodeRec not implemented for {node}")
    return errorValue()

proc computeFunctionExecutionImpl2*(ctx: Context, fec: FunctionExecutionContext): Value =
  if ctx.enableQueryLogging or ctx.enableExecutionLogging: inc currentIndent, 1
  defer:
    if ctx.enableQueryLogging or ctx.enableExecutionLogging: dec currentIndent, 1
  if ctx.enableQueryLogging or ctx.enableExecutionLogging: echo repeat2("| ", currentIndent - 1), "computeFunctionExecutionImpl ", fec
  defer:
    if ctx.enableQueryLogging or ctx.enableExecutionLogging: echo repeat2("| ", currentIndent), "-> ", result

  let body = fec.node[2]

  var variables = initTable[Id, Value]()

  # Add values of all arguments
  let params = fec.node[0]
  for i, arg in fec.arguments:
    if i >= params.len:
      logger.log(lvlError, fmt"Wrong number of arguments, expected {params.len}, got {fec.arguments.len}")
      return errorValue()
    let param = params[i]
    variables[param.id] = arg

  return ctx.executeNodeRec(body, variables)