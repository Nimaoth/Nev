import std/[tables, sets, strutils, hashes, options, logging, strformat]
import timer
import fusion/matching
import vmath
import ast, id, util
import query_system, compiler_types
import lrucache
import custom_logger

export compiler_types

type
  Diagnostic* = object
    message*: string

  Diagnostics* = object
    queries*: Table[Dependency, seq[Diagnostic]]

CreateContext Context:
  input AstNode
  input NodeLayoutInput
  data Symbol
  data FunctionExecutionContext

  var globalScope*: Table[Id, Symbol] = initTable[Id, Symbol]()
  var enableQueryLogging*: bool = false
  var enableExecutionLogging*: bool = false
  var diagnosticsPerNode*: Table[Id, Diagnostics] = initTable[Id, Diagnostics]()
  var diagnosticsPerQuery*: Table[Dependency, seq[Id]] = initTable[Dependency, seq[Id]]()

  proc recoverValue(ctx: Context, key: Dependency) {.recover("Value").}
  proc recoverType(ctx: Context, key: Dependency) {.recover("Type").}
  proc recoverSymbol(ctx: Context, key: Dependency) {.recover("Symbol").}
  proc recoverSymbols(ctx: Context, key: Dependency) {.recover("Symbols").}

  proc computeTypeImpl(ctx: Context, node: AstNode): Type {.query("Type").}
  proc computeValueImpl(ctx: Context, node: AstNode): Value {.query("Value").}
  proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] {.query("Symbol").}
  proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] {.query("Symbols").}
  proc computeValidationImpl(ctx: Context, node: AstNode): bool {.query("Validation").}
  proc computeSymbolTypeImpl(ctx: Context, symbol: Symbol): Type {.query("SymbolType").}
  proc computeSymbolValueImpl(ctx: Context, symbol: Symbol): Value {.query("SymbolValue").}
  proc computeFunctionExecutionImpl(ctx: Context, fec: FunctionExecutionContext): Value {.query("FunctionExecution", useCache = false, useFingerprinting = false).}

  proc computeNodeLayoutImpl(ctx: Context, nodeLayoutInput: NodeLayoutInput): NodeLayout {.query("NodeLayout", useFingerprinting = false).}

import node_layout
import treewalk_interpreter

template logIf(condition: bool, message: string, logResult: bool) =
  let logQuery = condition
  if logQuery: inc currentIndent, 1
  defer:
    if logQuery: dec currentIndent, 1
  if logQuery: echo repeat2("| ", currentIndent - 1), message
  defer:
    if logQuery and logResult:
      echo repeat2("| ", currentIndent) & "-> " & $result

proc computeNodeLayoutImpl(ctx: Context, nodeLayoutInput: NodeLayoutInput): NodeLayout =
  ctx.dependOnCurrentRevision()

  discard ctx.computeValidation(nodeLayoutInput.node)

  # logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeNodeLayoutImpl", false)
  return computeNodeLayoutImpl2(ctx, nodeLayoutInput)

proc computeFunctionExecutionImpl(ctx: Context, fec: FunctionExecutionContext): Value =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeFunctionExecutionImpl " & $fec, true)
  return computeFunctionExecutionImpl2(ctx, fec)

proc recoverValue(ctx: Context, key: Dependency) =
  log(lvlInfo, fmt"[compiler] Recovering value for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheValue[node] = errorValue()

proc recoverType(ctx: Context, key: Dependency) =
  log(lvlInfo, fmt"[compiler] Recovering type for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheType[node] = errorType()

proc recoverSymbol(ctx: Context, key: Dependency) =
  log(lvlInfo, fmt"[compiler] Recovering symbol for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheSymbol[node] = none[Symbol]()

proc recoverSymbols(ctx: Context, key: Dependency) =
  log(lvlInfo, fmt"[compiler] Recovering symbols for {key}")
  if ctx.getAstNode(key.item.id).getSome(node):
    ctx.queryCacheSymbols[node] = newTable[Id, Symbol]()

proc computeSymbolTypeImpl(ctx: Context, symbol: Symbol): Type =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeSymbolTypeImpl " & $symbol, true)

  case symbol.kind:
  of skAstNode:
    return ctx.computeType(symbol.node)
  of skBuiltin:
    return symbol.typ

proc computeSymbolValueImpl(ctx: Context, symbol: Symbol): Value =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeSymbolValueImpl " & $symbol, true)

  case symbol.kind:
  of skAstNode:
    return ctx.computeValue(symbol.node)
  of skBuiltin:
    return symbol.value

template enableDiagnostics(key: untyped): untyped =
  # Delete old diagnostics
  if ctx.diagnosticsPerQuery.contains(key):
    for id in ctx.diagnosticsPerQuery[key]:
      ctx.diagnosticsPerNode[id].queries.del key

  var diagnostics: seq[Diagnostic] = @[]
  var ids: seq[Id] = @[]
  defer:
    if diagnostics.len > 0:
      ctx.diagnosticsPerQuery[key] = ids

      for i in 0..ids.high:
        let id = ids[i]
        let diag = diagnostics[i]
        if not ctx.diagnosticsPerNode.contains(id):
          ctx.diagnosticsPerNode[id] = Diagnostics()
        if not ctx.diagnosticsPerNode[id].queries.contains(key):
          ctx.diagnosticsPerNode[id].queries[key] = @[]

        ctx.diagnosticsPerNode[id].queries[key].add diag
    else:
      ctx.diagnosticsPerQuery.del key

  template addDiagnostic(id: Id, msg: untyped) {.used.} =
    ids.add(id)
    diagnostics.add Diagnostic(message: msg)

proc computeValidationImpl(ctx: Context, node: AstNode): bool =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeValidationImpl " & $node, true)

  let key: Dependency = ctx.getValidationKey(node.getItem)
  enableDiagnostics(key)

  result = true

  let typ = ctx.computeType(node)
  if typ.kind == tError:
    result = false

  block switch:
    case node
    of FunctionDefinition():
      if typ.kind != tFunction:
        addDiagnostic(node.id, fmt"Type of function is not a function type, but {typ}")
        return false

      if node.len != 3:
        addDiagnostic(node.id, fmt"Function node must have 3 children, but has {node.len}")
        return false

      let returnType = typ.returnType

      let body = node[2]
      let bodyType = ctx.computeType(body)

      if bodyType.kind == tError:
        return false

      if returnType != bodyType:
        addDiagnostic(body.id, fmt"Function return type is {returnType}, but body returns {bodyType}")
        return false

    else:
      discard

  if result:
    for c in node.children:
      result = result and ctx.computeValidation(c)

proc computeTypeImpl(ctx: Context, node: AstNode): Type =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeTypeImpl " & $node, true)

  let key: Dependency = ctx.getTypeKey(node.getItem)
  enableDiagnostics(key)

  case node
  of Empty():
    return voidType()

  of NumberLiteral():
    try:
      discard node.text.parseInt
      return intType()
    except CatchableError:
      addDiagnostic(node.id, fmt"Number literal is not valid or outside of range")
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
      addDiagnostic(returnTypeNode.id, fmt"Expected type, got {returnTypeType}")
      return errorType()

    let returnTypeValue = ctx.computeValue(returnTypeNode)
    if returnTypeValue.kind == vkError:
      return errorType()

    if returnTypeValue.kind != vkType:
      addDiagnostic(returnTypeNode.id, fmt"Expected type value, got {returnTypeValue}")
      return errorType()

    let returnType = returnTypeValue.typ

    return newFunctionType(paramTypes, returnType)

  of Call():
    if node.len == 0:
      addDiagnostic(node.id, fmt"Empty call node")
      return errorType()

    let function = node[0]

    let functionType = ctx.computeType(function)

    if functionType.kind == tError:
      return Type(kind: tError)

    if functionType.kind != tFunction:
      addDiagnostic(function.id, fmt"Trying to call non-function type {functionType}")
      return Type(kind: tError)

    let numArgs = node.len - 1

    # Check if last param is open any
    let isValidOpenAnyCall = functionType.paramTypes.len > 0 and
        functionType.paramTypes[functionType.paramTypes.high] == anyType(true) and
        numArgs >= functionType.paramTypes.len - 1

    # Check arg num
    if numArgs != functionType.paramTypes.len and not isValidOpenAnyCall:
      addDiagnostic(node.id, fmt"Wrong number of arguments. Expected {functionType.paramTypes.len} got {numArgs}")
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
        addDiagnostic(node[i].id, fmt"Argument {i} has the wrong type. Expected {functionType.paramTypes[i - 1]} got {argType}")
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
        addDiagnostic(typeNode.id, fmt"Expected type, got {typeNodeType}")
        return errorType()

      let typeNodeValue = ctx.computeValue(typeNode)
      if typeNodeValue.kind == vkError:
        return errorType()
      if typeNodeValue.kind != vkType:
        addDiagnostic(typeNode.id, fmt"Expected type value, got {typeNodeValue}")
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
          addDiagnostic(valueNode.id, fmt"Expected {typ}, got {valueNodeType}")
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
        addDiagnostic(typeNode.id, fmt"Expected type, got {typeNodeType}")
        return errorType()

      let typeNodeValue = ctx.computeValue(typeNode)
      if typeNodeValue.kind == vkError:
        return errorType()
      if typeNodeValue.kind != vkType:
        addDiagnostic(typeNode.id, fmt"Expected type value, got {typeNodeValue}")
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
          addDiagnostic(valueNode.id, fmt"Expected {typ}, got {valueNodeType}")
          return errorType()

    return typ

  of Identifier():
    let id = node.reff
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(id):
      let symbol = symbols[id]
      return ctx.computeSymbolType(symbol)

    addDiagnostic(node.id, fmt"Unknown symbol '{id}'")
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
        addDiagnostic(condition.id, fmt"Condition of if statement must be an int but is {conditionType}")
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

  of While():
    if node.len < 2:
      return errorType()

    var ok = true

    let conditionType = ctx.computeType(node[0])
    if conditionType.kind == tError:
      ok = false
    elif conditionType.kind != tInt:
      addDiagnostic(node[0].id, fmt"Condition of while statement must be an int but is {conditionType}")
      ok = false

    let bodyType = ctx.computeType(node[1])
    if bodyType.kind == tError:
      ok = false

    if ok:
      return voidType()
    else:
      return errorType()

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
      addDiagnostic(value.id, fmt"Can't assign {valueType} to {targetType}")
      return errorType()

    if ctx.computeSymbol(target).getSome(sym):
      if sym.kind == skBuiltin:
        addDiagnostic(target.id, fmt"Can't assign to builtin symbol {sym}")
        return errorType()

      assert sym.kind == skAstNode
      if sym.node.kind != VarDecl:
        addDiagnostic(target.id, fmt"Can't assign to non-mutable symbol {sym}")
        return errorType()

    return voidType()

  else:
    return errorType()

proc computeValueImpl(ctx: Context, node: AstNode): Value =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeValueImpl " & $node, true)

  let key: Dependency = ctx.getValueKey(node.getItem)
  enableDiagnostics(key)

  case node
  of NumberLiteral():
    let value = try: node.text.parseInt except CatchableError: return errorValue()
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
        log lvlError, fmt"[compiler]: Can't call function at compile time '{function.id}' at {node}"
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
        log(lvlError, fmt"[compiler] Condition of if statement must be an int but is {conditionValue}")
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
    let currentRev = if ctx.getValue(node).getSome(value) and value.kind == vkAstFunction: value.rev else: 0
    return newAstFunctionValue(node, currentRev + 1)

  else:
    return errorValue()

proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeSymbolImpl " & $node, true)

  case node
  of Identifier():
    let symbols = ctx.computeSymbols(node)

    if symbols.contains(node.reff):
      return some(symbols[node.reff])

  of ConstDecl():
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  of LetDecl():
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  of VarDecl():
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  else:
    log(lvlError, fmt"Failed to get symbol from node {node}")
    return none[Symbol]()

proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] =
  logIf(ctx.enableLogging or ctx.enableQueryLogging, "computeSymbolsImpl " & $node, false)

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
  ctx.depGraph.changed[(sym.getItem, -1)] = ctx.depGraph.revision
  log(lvlInfo, fmt"[compiler] Invalidating symbol {sym.name} ({sym.id})")

proc insertNode*(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, -1)] = ctx.depGraph.revision

  if node.parent != nil:
    ctx.depGraph.changed[(node.parent.getItem, -1)] = ctx.depGraph.revision

  ctx.itemsAstNode[node.getItem] = node
  for (key, child) in node.nextPreOrder:
    ctx.depGraph.changed[(child.getItem, -1)] = ctx.depGraph.revision
    ctx.itemsAstNode[child.getItem] = child

  var parent = node.parent
  while parent != nil and parent.findWithParentRec(FunctionDefinition).getSome(child):
    let functionDefinition = child.parent
    ctx.depGraph.changed[(functionDefinition.getItem, -1)] = ctx.depGraph.revision
    parent = functionDefinition.parent

proc updateNode*(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, -1)] = ctx.depGraph.revision

  var parent = node.parent
  while parent != nil and parent.findWithParentRec(FunctionDefinition).getSome(child):
    let functionDefinition = child.parent
    ctx.depGraph.changed[(functionDefinition.getItem, -1)] = ctx.depGraph.revision
    parent = functionDefinition.parent

  log(lvlInfo, fmt"[compiler] Invalidating node {node}")

proc deleteNode*(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed.del((node.getItem, -1))

  if node.parent != nil:
    ctx.depGraph.changed[(node.parent.getItem, -1)] = ctx.depGraph.revision

  var parent = node.parent
  while parent != nil and parent.findWithParentRec(FunctionDefinition).getSome(child):
    let functionDefinition = child.parent
    ctx.depGraph.changed[(functionDefinition.getItem, -1)] = ctx.depGraph.revision
    parent = functionDefinition.parent

proc deleteAllNodesAndSymbols*(ctx: Context) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed.clear
  ctx.depGraph.verified.clear
  ctx.depGraph.fingerprints.clear
  ctx.depGraph.dependencies.clear
  ctx.itemsAstNode.clear
  ctx.itemsSymbol.clear
  ctx.itemsNodeLayoutInput.clear
  ctx.itemsFunctionExecutionContext.clear
  ctx.queryCacheType.clear
  ctx.queryCacheValue.clear
  ctx.queryCacheSymbolType.clear
  ctx.queryCacheSymbolValue.clear
  ctx.queryCacheSymbol.clear
  ctx.queryCacheSymbols.clear
  ctx.queryCacheFunctionExecution.clear
  ctx.queryCacheNodeLayout.clear

proc replaceNodeChild*(ctx: Context, parent: AstNode, index: int, newNode: AstNode) =
  let node = parent[index]
  parent[index] = newNode
  ctx.depGraph.changed.del((node.getItem, -1))

  ctx.insertNode(newNode)