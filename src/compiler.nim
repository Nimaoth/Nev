import std/[tables, sets, strutils, sequtils, sugar, hashes, options, logging, strformat]
import timer
import fusion/matching
import bumpy, chroma, vmath, pixie/fonts
import ast, id, util, rect_utils
import query_system

var logger = newConsoleLogger()

type
  TypeKind* = enum
    tError
    tVoid
    tString
    tInt
    tFunction
    tAny
    tType

  Type* = ref object
    case kind*: TypeKind
    of tError: discard
    of tVoid: discard
    of tString: discard
    of tInt: discard
    of tType: discard
    of tAny: open: bool
    of tFunction:
      returnType*: Type
      paramTypes*: seq[Type]

  ValueImpl* = proc(values: seq[Value]): Value
  ValueKind* = enum
    vkError
    vkVoid
    vkString
    vkNumber
    vkBuiltinFunction
    vkAstFunction
    vkType

  Value* = object
    case kind*: ValueKind
    of vkError: discard
    of vkVoid: discard
    of vkString: stringValue*: string
    of vkNumber: intValue*: int
    of vkBuiltinFunction: impl*: ValueImpl
    of vkAstFunction: node*: AstNode
    of vkType: typ*: Type

  OperatorNotation* = enum
    Regular
    Prefix
    Postfix
    Infix
    Scope

  SymbolKind* = enum skAstNode, skBuiltin
  Symbol* = ref object
    id*: Id
    name*: string
    case kind*: SymbolKind
    of skAstNode:
      node*: AstNode
    of skBuiltin:
      typ*: Type
      value*: Value
      operatorNotation*: OperatorNotation
      precedence*: int

type FunctionExecutionContext* = ref object
  id*: Id
  node*: AstNode
  arguments*: seq[Value]

func errorType*(): Type = Type(kind: tError)
func voidType*(): Type = Type(kind: tVoid)
func intType*(): Type = Type(kind: tInt)
func stringType*(): Type = Type(kind: tString)
func newFunctionType*(paramTypes: seq[Type], returnType: Type): Type = Type(kind: tFunction, returnType: returnType, paramTypes: paramTypes)
func typeType*(): Type = Type(kind: tType)
func anyType*(open: bool): Type = Type(kind: tAny, open: open)

func `$`*(typ: Type): string =
  case typ.kind
  of tError: return "error"
  of tVoid: return "void"
  of tString: return "string"
  of tInt: return "int"
  of tFunction: return "function " & $typ.paramTypes & " -> " & $typ.returnType & ""
  of tType: return "type"
  of tAny: return fmt"any({typ.open})"

func hash*(typ: Type): Hash =
  case typ.kind
  of tFunction: typ.kind.hash xor typ.returnType.hash xor typ.paramTypes.hash
  of tAny: typ.kind.hash xor typ.open.hash
  else:
    return typ.kind.hash

func `==`*(a: Type, b: Type): bool =
  if a.kind != b.kind: return false
  case a.kind
  of tFunction:
    return a.returnType == b.returnType and a.paramTypes == b.paramTypes
  of tAny:
    return a.open == b.open
  else:
    return true

func fingerprint*(typ: Type): Fingerprint =
  case typ.kind
  of tFunction:
    result = @[typ.kind.int64] & typ.returnType.fingerprint
    for param in typ.paramTypes:
      result.add param.fingerprint
  of tAny:
    result = @[typ.kind.int64, typ.open.int64]
  else:
    result = @[typ.kind.int64]

func errorValue*(): Value = Value(kind: vkError)
func voidValue*(): Value = Value(kind: vkVoid)
func intValue*(value: int): Value = Value(kind: vkNumber, intValue: value)
func stringValue*(value: string): Value = Value(kind: vkString, stringValue: value)
func typeValue*(typ: Type): Value = Value(kind: vkType, typ: typ)
func newFunctionValue*(impl: ValueImpl): Value = return Value(kind: vkBuiltinFunction, impl: impl)
func newAstFunctionValue*(node: AstNode): Value = return Value(kind: vkAstFunction, node: node)

func `$`*(value: Value): string =
  case value.kind
  of vkError: return "<vkError>"
  of vkVoid: return "void"
  of vkString: return value.stringValue
  of vkNumber: return $value.intValue
  of vkBuiltinFunction: return "<builtin-function>"
  of vkAstFunction: return "<ast-function " & $value.node & ">"
  of vkType: return $value.typ

func hash*(value: Value): Hash =
  case value.kind
  of vkError: return value.kind.hash
  of vkVoid: return value.kind.hash
  of vkNumber: return value.intValue.hash
  of vkString: return value.stringValue.hash
  of vkBuiltinFunction: return value.impl.hash
  of vkAstFunction: return value.node.hash
  of vkType: return value.typ.hash

func `==`*(a: Value, b: Value): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vkError: return true
  of vkVoid: return true
  of vkNumber: return a.intValue == b.intValue
  of vkString: return a.stringValue == b.stringValue
  of vkBuiltinFunction: return a.impl == b.impl
  of vkAstFunction: return a.node == b.node
  of vkType: return a.typ == b.typ

func fingerprint*(value: Value): Fingerprint =
  case value.kind
  of vkError: return @[value.kind.int64]
  of vkVoid: return @[value.kind.int64]
  of vkNumber: return @[value.kind.int64, value.intValue]
  of vkString: return @[value.kind.int64, value.stringValue.hash]
  of vkBuiltinFunction: return @[value.kind.int64, value.impl.hash]
  of vkAstFunction: return @[value.kind.int64, value.node.hash]
  of vkType: return @[value.kind.int64] & value.typ.fingerprint

func `$`*(fec: FunctionExecutionContext): string =
  return fmt"Call {fec.node}({fec.arguments})"

func hash*(fec: FunctionExecutionContext): Hash =
  return fec.node.hash xor fec.arguments.hash

func `==`*(a: FunctionExecutionContext, b: FunctionExecutionContext): bool =
  if a.node != b.node:
    return false
  if a.arguments != b.arguments:
    return false
  return true

func `$`*(symbol: Symbol): string =
  case symbol.kind
  of skAstNode:
    return "Sym(AstNode, " & $symbol.id & ", " & $symbol.node & ")"
  of skBuiltin:
    return "Sym(Builtin, " & $symbol.id & ", " & $symbol.typ & ", " & $symbol.value & ")"

func hash*(symbol: Symbol): Hash =
  return symbol.id.hash

func `==`*(a: Symbol, b: Symbol): bool =
  if a.id != b.id: return false
  if a.kind != b.kind: return false
  if a.name != b.name: return false
  case a.kind
  of skBuiltin:
    return a.typ == b.typ and a.value == b.value and a.operatorNotation == b.operatorNotation and a.precedence == b.precedence
  of skAstNode:
    return a.node == b.node

func fingerprint*(symbol: Symbol): Fingerprint =
  case symbol.kind
  of skAstNode:
    result = @[symbol.id.hash.int64, symbol.name.hash.int64, symbol.kind.int64, symbol.node.id.hash.int64]
  of skBuiltin:
    result = @[symbol.id.hash.int64, symbol.name.hash.int64, symbol.kind.int64, symbol.precedence, symbol.operatorNotation.int64] & symbol.typ.fingerprint & symbol.value.fingerprint

func fingerprint*(symbols: TableRef[Id, Symbol]): Fingerprint =
  result = @[]
  for (key, value) in symbols.pairs:
    result.add value.fingerprint

func fingerprint*(symbol: Option[Symbol]): Fingerprint =
  if symbol.getSome(s):
    return s.fingerprint
  return @[]

type
  VisualNode* = ref object
    parent*: VisualNode
    node*: AstNode
    text*: string
    color*: Color
    bounds*: Rect
    indent*: float32
    font*: Font
    children*: seq[VisualNode]

  VisualNodeRange* = object
    parent*: VisualNode
    first*: int
    last*: int

  NodeLayout* = object
    root*: VisualNode
    nodeToVisualNode*: Table[Id, VisualNodeRange]

func size*(node: VisualNode): Vec2 = node.bounds.wh
func relativeBounds*(node: VisualNode, parent: VisualNode): Rect =
  if node == parent:
    result = rect(vec2(), node.bounds.wh)
  elif node.parent == nil:
    result = node.bounds
  else:
    result = rect(node.parent.relativeBounds(parent).xy + node.bounds.xy, node.bounds.wh)

func absoluteBounds*(node: VisualNode): Rect =
  if node.parent == nil:
    result = node.bounds
  else:
    result = rect(node.parent.absoluteBounds.xy + node.bounds.xy, node.bounds.wh)

func bounds*(nodeRange: VisualNodeRange): Rect =
  result = nodeRange.parent.children[nodeRange.first].bounds
  for i in (nodeRange.first + 1)..<nodeRange.last:
    result = result or nodeRange.parent.children[i].bounds
  result.xy = result.xy + nodeRange.parent.absoluteBounds.xy

func `$`*(vnode: VisualNode): string =
  result = "VNode" & "('"
  result.add vnode.text & "', "
  result.add $vnode.bounds & ", "
  if vnode.node != nil:
    result.add $vnode.node & ", "
  result.add $vnode.color & ", "
  result.add ")"
  if vnode.children.len > 0:
    result.add ":"
    for child in vnode.children:
      result.add "\n" & indent($child, 1, "| ")

func hash*(vnode: VisualNode): Hash =
  result = vnode.text.hash xor vnode.color.hash or vnode.bounds.hash or vnode.children.hash
  result = !$result

func fingerprint*(vnode: VisualNode): Fingerprint =
  let h = vnode.text.hash xor vnode.color.hash or vnode.bounds.hash or vnode.children.hash
  result = @[h.int64] & vnode.children.map(c => c.fingerprint).foldl(a & b, @[0.int64])

func `==`*(a: VisualNode, b: VisualNode): bool =
  if a.text != b.text:
    return false
  if a.node != b.node:
    return false
  if a.color != b.color:
    return false
  if a.bounds != b.bounds:
    return false
  return a.children == b.children

proc add*(node: var VisualNode, child: VisualNode): VisualNodeRange =
  node.children.add child
  child.bounds.x = node.bounds.w
  node.bounds = node.bounds or (child.bounds + node.bounds.xy)
  return VisualNodeRange(parent: node, first: node.children.high, last: node.children.len)

proc addLine*(node: var VisualNode, child: var VisualNode) =
  node.children.add child
  child.bounds.y = node.bounds.h
  node.bounds = node.bounds or (child.bounds + node.bounds.xy)

func `$`*(nodeLayout: NodeLayout): string =
  result = nodeLayout.root.children.join "\n"

func hash*(nodeLayout: NodeLayout): Hash =
  result = nodeLayout.root.hash
  result = !$result

func `==`*(a: NodeLayout, b: NodeLayout): bool =
  return a.root == b.root

func fingerprint*(nodeLayout: NodeLayout): Fingerprint =
  result = nodeLayout.root.fingerprint

func bounds*(nodeLayout: NodeLayout): Rect =
  return nodeLayout.root.bounds

CreateContext Context:
  input AstNode
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
  proc executeFunctionImpl(ctx: Context, fec: FunctionExecutionContext): Value {.query("FunctionExecution", useCache = false, useFingerprinting = false).}

  proc computeNodeLayoutImpl(ctx: Context, node: AstNode): NodeLayout {.query("NodeLayout", useCache = false, useFingerprinting = false).}

import node_layout

proc computeNodeLayoutImpl(ctx: Context, node: AstNode): NodeLayout =
  return computeNodeLayoutImpl2(ctx, node)

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

proc cacheValuesInFunction(ctx: Context, node: AstNode, values: var Table[Id, Value]) =
  let value = ctx.computeValue(node)
  if value.kind == vkError:
    for child in node.children:
      ctx.cacheValuesInFunction(child, values)
  else:
    values[node.id] = value

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

  of Identifier():
    let id = node.reff
    if variables.contains(id):
      return variables[id]

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

proc executeFunctionImpl(ctx: Context, fec: FunctionExecutionContext): Value =
  if ctx.enableQueryLogging or ctx.enableExecutionLogging: inc currentIndent, 1
  defer:
    if ctx.enableQueryLogging or ctx.enableExecutionLogging: dec currentIndent, 1
  if ctx.enableQueryLogging or ctx.enableExecutionLogging: echo repeat2("| ", currentIndent - 1), "executeFunctionImpl ", fec
  defer:
    if ctx.enableQueryLogging or ctx.enableExecutionLogging: echo repeat2("| ", currentIndent), "-> ", result

  let body = fec.node[2]

  # Add values of all symbols in the global scope
  var variables = initTable[Id, Value]()
  for (key, sym) in ctx.globalScope.pairs:
    let value = ctx.computeSymbolValue(sym)
    if value.kind != vkError:
      variables[key] = value

  # Add values of all symbols in the scope of the function we're trying to call
  let scope = ctx.computeSymbols(fec.node)
  for (key, sym) in scope.pairs:
    let value = ctx.computeSymbolValue(sym)
    if value.kind != vkError:
      variables[key] = value

  # Add values of all arguments
  let params = fec.node[0]
  for i, arg in fec.arguments:
    if i >= params.len:
      logger.log(lvlError, fmt"Wrong number of arguments, expected {params.len}, got {fec.arguments.len}")
      return errorValue()
    let param = params[i]
    variables[param.id] = arg

  ctx.cacheValuesInFunction(body, variables)

  return ctx.executeNodeRec(body, variables)

proc computeSymbolTypeImpl(ctx: Context, symbol: Symbol): Type =
  case symbol.kind:
  of skAstNode:
    return ctx.computeType(symbol.node)
  of skBuiltin:
    return symbol.typ

proc computeSymbolValueImpl(ctx: Context, symbol: Symbol): Value =
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
    if node.len < 2:
      return errorType()

    let typeNode = node[0]
    let valueNode = node[1]

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
    if node.len < 2:
      return errorType()

    let typeNode = node[0]
    let valueNode = node[1]

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

proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] =
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

  if node.parent != nil and node.parent.kind == FunctionDefinition:
    if node.parent.len > 0:
      let params = node.parent[0]
      ctx.recordDependency(params.getItem)
      for param in params.children:
        ctx.recordDependency(param.getItem)
        if ctx.computeSymbol(param).getSome(symbol):
          result[param.id] = symbol

  elif node.findWithParentRec(NodeList).getSome(parentInNodeList) and parentInNodeList.parent.parent != nil:
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

    if functionValue.kind != vkBuiltinFunction:
      return errorValue()

    if functionValue.impl == nil:
      logger.log lvlError, fmt"[compiler]: Can't call function at compile time '{function.id}' at {node}"
      return errorValue()

    var args: seq[Value] = @[]
    for arg in node.children[1..^1]:
      let value = ctx.computeValue(arg)
      if value.kind == vkError:
        return errorValue()
      args.add value

    return functionValue.impl(args)

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

iterator nextPreOrder*(node: AstNode): tuple[key: int, value: AstNode] =
  var n = node
  var idx = -1
  var i = 0

  while true:
    defer: inc i
    if idx == -1:
      yield (i, n)
    if idx + 1 < n.len:
      n = n[idx + 1]
      idx = -1
    elif n.next.getSome(ne):
      n = ne
      idx = -1
    elif n.parent != nil and n.parent != node:
      idx = n.index
      n = n.parent
    else:
      break

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

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.item == node.getItem:
        ctx.depGraph.dependencies[key][i] = ((null, -1), nil)

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

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.item == node.getItem:
        ctx.depGraph.dependencies[key][i].item = newNode.getItem

  ctx.insertNode(newNode)