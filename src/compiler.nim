import std/[tables, sets, strutils, sequtils, sugar, hashes, options, logging, strformat]
import timer
import fusion/matching
import bumpy, chroma, vmath, pixie/fonts
import ast, id, util, rect_utils
import query_system, compiler_types

export compiler_types

var logger* = newConsoleLogger()

CreateContext Context:
  input AstNode
  input NodeLayoutInput
  data Symbol
  data FunctionExecutionContext

  var globalScope*: Table[Id, Symbol] = initTable[Id, Symbol]()
  var enableQueryLogging*: bool = false
  var enableExecutionLogging*: bool = false

  proc recoverValue(ctx: Context, key: Dependency) {.recover("Value").}
  proc recoverType(ctx: Context, key: Dependency) {.recover("Type").}
  proc recoverSymbol(ctx: Context, key: Dependency) {.recover("Symbol").}
  proc recoverSymbols(ctx: Context, key: Dependency) {.recover("Symbols").}

  proc computeTypeImpl(ctx: Context, node: AstNode): Type {.query("Type").}
  proc computeValueImpl(ctx: Context, node: AstNode): Value {.query("Value").}
  proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] {.query("Symbol").}
  proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] {.query("Symbols").}
  proc computeSymbolTypeImpl(ctx: Context, symbol: Symbol): Type {.query("SymbolType").}
  proc computeSymbolValueImpl(ctx: Context, symbol: Symbol): Value {.query("SymbolValue").}
  proc computeFunctionExecutionImpl(ctx: Context, fec: FunctionExecutionContext): Value {.query("FunctionExecution", useCache = false, useFingerprinting = false).}

  proc computeNodeLayoutImpl(ctx: Context, nodeLayoutInput: NodeLayoutInput): NodeLayout {.query("NodeLayout", useCache = false, useFingerprinting = false).}

import node_layout
import treewalk_interpreter

proc computeNodeLayoutImpl(ctx: Context, nodeLayoutInput: NodeLayoutInput): NodeLayout =
  return computeNodeLayoutImpl2(ctx, nodeLayoutInput)

proc computeFunctionExecutionImpl(ctx: Context, fec: FunctionExecutionContext): Value =
  return computeFunctionExecutionImpl2(ctx, fec)

proc recoverValue(ctx: Context, key: Dependency) =
  logger.log(lvlInfo, fmt"[compiler] Recovering value for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheValue[node] = errorValue()

proc recoverType(ctx: Context, key: Dependency) =
  logger.log(lvlInfo, fmt"[compiler] Recovering type for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheType[node] = errorType()

proc recoverSymbol(ctx: Context, key: Dependency) =
  logger.log(lvlInfo, fmt"[compiler] Recovering symbol for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheSymbol[node] = none[Symbol]()

proc recoverSymbols(ctx: Context, key: Dependency) =
  logger.log(lvlInfo, fmt"[compiler] Recovering symbols for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheSymbols[node] = newTable[Id, Symbol]()

proc computeSymbolTypeImpl(ctx: Context, symbol: Symbol): Type =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent - 1), "computeSymbolTypeImpl ", symbol
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent), "-> ", result

  case symbol.kind:
  of skAstNode:
    return ctx.computeType(symbol.node)
  of skBuiltin:
    return symbol.typ

proc computeSymbolValueImpl(ctx: Context, symbol: Symbol): Value =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent - 1), "computeSymbolValueImpl ", symbol
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent), "-> ", result

  case symbol.kind:
  of skAstNode:
    return ctx.computeValue(symbol.node)
  of skBuiltin:
    return symbol.value

proc computeTypeImpl(ctx: Context, node: AstNode): Type =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent - 1), "computeTypeImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent), "-> ", result

  case node
  of Empty():
    return voidType()

  of NumberLiteral():
    try:
      discard node.text.parseInt
      return intType()
    except:
      return errorType()

  of StringLiteral():
    return stringType()

  of Params():
    return voidType()

  of FunctionDefinition():
    if node.len < 3:
      return errorType()

    let params = node[0]
    ctx.recordDependency(params.getItem)

    let returnTypeNode = node[1]

    var paramTypes: seq[Type] = @[]

    var ok = true
    for param in params.children:
      let paramType = ctx.computeType(param)
      if paramType.kind == tError:
        ok = false
        continue

      paramTypes.add paramType

    let returnTypeType = ctx.computeType(returnTypeNode)
    if returnTypeType.kind == tError:
      return errorType()

    if returnTypeType.kind != tType:
      logger.log(lvlError, fmt"[compiler] Expected type, got {returnTypeType}")
      return errorType()

    let returnTypeValue = ctx.computeValue(returnTypeNode)
    if returnTypeValue.kind == vkError:
      return errorType()

    if returnTypeValue.kind != vkType:
      logger.log(lvlError, fmt"[compiler] Expected type value, got {returnTypeValue}")
      return errorType()

    let returnType = returnTypeValue.typ

    return newFunctionType(paramTypes, returnType)

  of Call():
    let function = node[0]

    let functionType = ctx.computeType(function)

    if functionType.kind == tError:
      return Type(kind: tError)

    if functionType.kind != tFunction:
      logger.log(lvlError, fmt"[compiler] Trying to call non-function type {functionType} at {node}")
      return Type(kind: tError)

    let numArgs = node.len - 1

    # Check if last param is open any
    let isValidOpenAnyCall = functionType.paramTypes.len > 0 and
        functionType.paramTypes[functionType.paramTypes.high] == anyType(true) and
        numArgs >= functionType.paramTypes.len - 1

    # Check arg num
    if numArgs != functionType.paramTypes.len and not isValidOpenAnyCall:
      logger.log(lvlError, fmt"Trying to call with wrong number of arguments. Expected {functionType.paramTypes.len} got {numArgs}")
      return Type(kind: tError)

    var allArgsOk = true
    for i in 1..numArgs:
      let argType = ctx.computeType(node[i])
      if argType.kind == tError:
        allArgsOk = false
        continue

      if isValidOpenAnyCall and i > functionType.paramTypes.high:
        continue

      if argType != functionType.paramTypes[i - 1]:
        logger.log(lvlError, fmt"Argument {i} has the wrong type. Expected {functionType.paramTypes[i - 1]} got {argType}")
        allArgsOk = false

    if not allArgsOk:
      return errorType()

    return functionType.returnType

  of ConstDecl():
    if node.len == 0:
      return errorType()
    return ctx.computeType(node[0])

  of LetDecl():
    if node.len < 1:
      return errorType()

    let typeNode = node[0]

    var typ = voidType()
    if typeNode.kind != Empty:
      let typeNodeType = ctx.computeType(typeNode)
      if typeNodeType.kind == tError:
        return errorType()
      if typeNodeType.kind != tType:
        logger.log(lvlError, fmt"[compiler] Expected type, got {typeNodeType}")
        return errorType()

      let typeNodeValue = ctx.computeValue(typeNode)
      if typeNodeValue.kind == vkError:
        return errorType()
      if typeNodeValue.kind == vkError:
        logger.log(lvlFatal, fmt"[compiler] Expected type value, got {typeNodeValue}")
        return errorType()

      typ = typeNodeValue.typ

    if node.len >= 2:
      let valueNode = node[1]
      if valueNode.kind != Empty:
        let valueNodeType = ctx.computeType(valueNode)
        if valueNodeType.kind == tError:
          return errorType()

        if typ.kind == tVoid:
          typ = valueNodeType

        if valueNodeType != typ:
          logger.log(lvlError, fmt"[compiler] Expected {typ}, got {valueNodeType}")
          return errorType()

    return typ

  of VarDecl():
    if node.len < 1:
      return errorType()

    let typeNode = node[0]

    var typ = voidType()
    if typeNode.kind != Empty:
      let typeNodeType = ctx.computeType(typeNode)
      if typeNodeType.kind == tError:
        return errorType()
      if typeNodeType.kind != tType:
        logger.log(lvlError, fmt"[compiler] Expected type, got {typeNodeType}")
        return errorType()

      let typeNodeValue = ctx.computeValue(typeNode)
      if typeNodeValue.kind == vkError:
        return errorType()
      if typeNodeValue.kind == vkError:
        logger.log(lvlFatal, fmt"[compiler] Expected type value, got {typeNodeValue}")
        return errorType()

      typ = typeNodeValue.typ

    if node.len >= 2:
      let valueNode = node[1]
      if valueNode.kind != Empty:
        let valueNodeType = ctx.computeType(valueNode)
        if valueNodeType.kind == tError:
          return errorType()

        if typ.kind == tVoid:
          typ = valueNodeType

        if valueNodeType != typ:
          logger.log(lvlError, fmt"[compiler] Expected {typ}, got {valueNodeType}")
          return errorType()

    return typ

  of Identifier():
    let id = node.reff
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(id):
      let symbol = symbols[id]
      return ctx.computeSymbolType(symbol)

    logger.log lvlError, fmt"[compiler]: Unknown symbol '{id}' at {node}"
    return errorType()

  of NodeList():
    if node.len == 0:
      return voidType()

    var lastType: Type = nil
    for child in node.children:
      lastType = ctx.computeType(child)
      if lastType.kind == tError:
        return errorType()

    return lastType

  of If():
    if node.len < 2:
      return errorType()

    var ok = true

    var commonType = none[Type]()

    # Iterate through all ifs/elifs
    var index: int = 0
    while index + 1 < node.len:
      defer: index += 2

      let condition = node[index]
      let trueCase = node[index + 1]

      let conditionType = ctx.computeType(condition)
      if conditionType.kind == tError:
        ok = false
      elif conditionType.kind != tInt:
        logger.log(lvlError, fmt"[compiler] Condition of if statement must be an int but is {conditionType}")
        ok = false

      let trueCaseType = ctx.computeType(trueCase)
      if trueCaseType.kind == tError:
        ok = false
        continue

      if commonType.isNone or trueCaseType == commonType.get:
        commonType = some(trueCaseType)
      else:
        commonType = some(voidType())

    # else case
    if node.len mod 2 != 0:
      let falseCaseType = ctx.computeType(node.last)
      if falseCaseType.kind == tError:
        return errorType()

      if commonType.isNone or falseCaseType == commonType.get:
        commonType = some(falseCaseType)
      else:
        commonType = some(voidType())

    if not ok:
      return errorType()

    return commonType.get voidType()

  of Assignment():
    if node.len < 2:
      return errorType()

    let target =  node[0]
    let value = node[1]

    let targetType = ctx.computeType(target)
    if targetType.kind == tError:
      return errorType()

    let valueType = ctx.computeType(value)
    if valueType.kind == tError:
      return errorType()

    if targetType != valueType:
      logger.log(lvlError, fmt"[compiler] Can't assign {valueType} to {targetType}")
      return errorType()

    if ctx.computeSymbol(target).getSome(sym):
      if sym.kind == skBuiltin:
        logger.log(lvlError, fmt"[compiler] Can't assign to builtin symbol {sym}")
        return errorType()

      assert sym.kind == skAstNode
      if sym.node.kind != VarDecl:
        logger.log(lvlError, fmt"[compiler] Can't assign to non-mutable symbol {sym}")
        return errorType()

    return voidType()

  else:
    return errorType()

proc computeValueImpl(ctx: Context, node: AstNode): Value =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent - 1), "computeValueImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent), "-> ", result

  case node
  of NumberLiteral():
    let value = try: node.text.parseInt except: return errorValue()
    return Value(kind: vkNumber, intValue: value)

  of StringLiteral():
    return Value(kind: vkString, stringValue: node.text)

  of Call():
    let function = node[0]

    let functionValue = ctx.computeValue(function)
    if functionValue.kind == vkError:
      return errorValue()

    var args: seq[Value] = @[]
    for arg in node.children[1..^1]:
      let value = ctx.computeValue(arg)
      if value.kind == vkError:
        return errorValue()
      args.add value

    if functionValue.kind == vkBuiltinFunction:
      if functionValue.impl == nil:
        logger.log lvlError, fmt"[compiler]: Can't call function at compile time '{function.id}' at {node}"
        return errorValue()
      return functionValue.impl(args)

    if functionValue.kind == vkAstFunction:
      let fec = ctx.getOrCreateFunctionExecutionContext(FunctionExecutionContext(node: functionValue.node, arguments: args))
      return ctx.computeFunctionExecution(fec)

    return errorValue()

  of NodeList():
    if node.len == 0:
      return errorValue()
    return ctx.computeValue(node.last)

  of ConstDecl():
    if node.len == 0:
      return errorValue()
    return ctx.computeValue(node[0])

  of Identifier():
    let id = node.reff
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(id):
      let symbol = symbols[id]
      return ctx.computeSymbolValue(symbol)

    return errorValue()

  of If():
    if node.len < 2:
      return errorValue()

    # Iterate through all ifs/elifs
    var index: int = 0
    while index + 1 < node.len:
      defer: index += 2

      let condition = node[index]
      let trueCase = node[index + 1]

      let conditionValue = ctx.computeValue(condition)
      if conditionValue.kind == vkError:
        return errorValue()

      if conditionValue.kind != vkNumber:
        logger.log(lvlError, fmt"[compiler] Condition of if statement must be an int but is {conditionValue}")
        return errorValue()

      if conditionValue.intValue != 0:
        let trueCaseValue = ctx.computeValue(trueCase)
        return trueCaseValue

    # else case
    if node.len mod 2 != 0:
      let falseCaseValue = ctx.computeValue(node.last)
      return falseCaseValue

    return voidValue()

  of FunctionDefinition():
    return newAstFunctionValue(node)

  else:
    return errorValue()

proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent - 1), "computeSymbolImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent), "-> ", result

  case node
  of Identifier():
    let symbols = ctx.computeSymbols(node)

    if symbols.contains(node.reff):
      return some(symbols[node.reff])

  of ConstDecl():
    logger.log(lvlDebug, fmt"computeSymbol {node}")
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  of LetDecl():
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  of VarDecl():
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  else:
    logger.log(lvlError, fmt"Failed to get symbol from node {node}")
    return none[Symbol]()

proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent - 1), "computeSymbolsImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat2("| ", currentIndent), "-> ", result

  result = newTable[Id, Symbol]()

  if node.findWithParentRec(NodeList).getSome(parentInNodeList) and parentInNodeList.parent.parent != nil:
    let parentSymbols = ctx.computeSymbols(parentInNodeList.parent)
    for (id, sym) in parentSymbols.pairs:
      result[id] = sym

    ctx.recordDependency(parentInNodeList.parent.getItem)

    let bIsOrderDependent = parentInNodeList.parent.parent != nil
    for child in parentInNodeList.parent.children:
      if bIsOrderDependent and child == parentInNodeList:
        break

      if child.kind != ConstDecl and child.kind != LetDecl and child.kind != VarDecl:
        continue

      if ctx.computeSymbol(child).getSome(symbol):
        result[symbol.id] = symbol

  elif node.findWithParentRec(FunctionDefinition).getSome(parentInFunctionDef):
    let functionDefinition = parentInFunctionDef.parent
    if functionDefinition.len > 0:
      let params = functionDefinition[0]
      ctx.recordDependency(params.getItem)
      for param in params.children:
        ctx.recordDependency(param.getItem)
        if ctx.computeSymbol(param).getSome(symbol):
          result[param.id] = symbol

  # Add symbols from global scope
  let root = node.base
  ctx.recordDependency(root.getItem)
  for child in root.children:
    if child.kind != ConstDecl and child.kind != LetDecl and child.kind != VarDecl:
      continue

    if ctx.computeSymbol(child).getSome(symbol):
      result[symbol.id] = symbol

  for (key, symbol) in ctx.globalScope.pairs:
    ctx.recordDependency(symbol.getItem)
    result[symbol.id] = symbol

proc notifySymbolChanged*(ctx: Context, sym: Symbol) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(sym.getItem, nil)] = ctx.depGraph.revision
  logger.log(lvlInfo, fmt"[compiler] Invalidating symbol {sym.name} ({sym.id})")

proc insertNode*(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, nil)] = ctx.depGraph.revision

  if node.parent != nil:
    ctx.depGraph.changed[(node.parent.getItem, nil)] = ctx.depGraph.revision

  ctx.itemsAstNode[node.getItem] = node
  for (key, child) in node.nextPreOrder:
    ctx.depGraph.changed[(child.getItem, nil)] = ctx.depGraph.revision
    ctx.itemsAstNode[child.getItem] = child

proc updateNode*(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, nil)] = ctx.depGraph.revision
  logger.log(lvlInfo, fmt"[compiler] Invalidating node {node}")

proc deleteNode*(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed.del((node.getItem, nil))

  if node.parent != nil:
    ctx.depGraph.changed[(node.parent.getItem, nil)] = ctx.depGraph.revision

proc deleteAllNodesAndSymbols*(ctx: Context) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed.clear
  ctx.depGraph.verified.clear
  ctx.depGraph.fingerprints.clear
  ctx.depGraph.dependencies.clear
  ctx.itemsAstNode.clear
  ctx.itemsSymbol.clear

proc replaceNodeChild*(ctx: Context, parent: AstNode, index: int, newNode: AstNode) =
  let node = parent[index]
  parent[index] = newNode
  ctx.depGraph.changed.del((node.getItem, nil))

  ctx.insertNode(newNode)