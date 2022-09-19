import std/[tables, sets, strutils, hashes, options, macros, logging, strformat]
import sugar
import system
import print
import fusion/matching
import ast, ast_ids, id, util
import query_system

var logger = newConsoleLogger()

type
  TypeKind* = enum
    tError
    tVoid
    tString
    tInt
    tFunction

  Type* = ref object
    case kind*: TypeKind
    of tError: discard
    of tVoid: discard
    of tString: discard
    of tInt: discard
    of tFunction:
      returnType*: Type
      paramTypes*: seq[Type]

  ValueImpl* = proc(node: AstNode): Value
  ValueKind* = enum
    vkError
    vkVoid
    vkString
    vkNumber
    vkFunction

  Value* = object
    case kind*: ValueKind
    of vkError: discard
    of vkVoid: discard
    of vkString: stringValue*: string
    of vkNumber: intValue*: int
    of vkFunction: impl*: ValueImpl

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

proc `$`*(typ: Type): string =
  case typ.kind
  of tError: return "error"
  of tVoid: return "void"
  of tString: return "string"
  of tInt: return "int"
  of tFunction: return "function " & $typ.paramTypes & " -> " & $typ.returnType & ""

proc hash*(typ: Type): Hash =
  case typ.kind
  of tFunction: typ.kind.hash xor typ.returnType.hash xor typ.paramTypes.hash
  else:
    return typ.kind.hash

proc `==`*(a: Type, b: Type): bool =
  if a.kind != b.kind: return false
  case a.kind
  of tFunction:
    return a.returnType == b.returnType and a.paramTypes == b.paramTypes
  else:
    return true

proc `==`*(a: Value, b: Value): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vkError: return true
  of vkVoid: return true
  of vkNumber: return a.intValue == b.intValue
  of vkString: return a.stringValue == b.stringValue
  of vkFunction: return a.impl == b.impl

func errorType*(): Type = Type(kind: tError)
func voidType*(): Type = Type(kind: tVoid)
func intType*(): Type = Type(kind: tInt)
func stringType*(): Type = Type(kind: tString)
func newFunctionType*(paramTypes: seq[Type], returnType: Type): Type = Type(kind: tFunction, returnType: returnType, paramTypes: paramTypes)

func errorValue*(): Value = Value(kind: vkError)
func voidValue*(): Value = Value(kind: vkVoid)
func intValue*(value: int): Value = Value(kind: vkNumber, intValue: value)
func stringValue*(value: string): Value = Value(kind: vkString, stringValue: value)

proc `$`*(value: Value): string =
  case value.kind
  of vkError: return "<vkError>"
  of vkVoid: return "void"
  of vkString: return value.stringValue
  of vkNumber: return $value.intValue
  of vkFunction: return "function"

proc hash*(value: Value): Hash =
  case value.kind
  of vkNumber: return value.intValue.hash
  of vkString: return value.stringValue.hash
  of vkFunction: return value.impl.hash
  else: return value.kind.hash


proc `$`*(symbol: Symbol): string =
  case symbol.kind
  of skAstNode:
    return "Sym(AstNode, " & $symbol.id & ", " & $symbol.node & ")"
  of skBuiltin:
    return "Sym(Builtin, " & $symbol.id & ", " & $symbol.typ & ", " & $symbol.value & ")"

proc hash*(symbol: Symbol): Hash =
  return symbol.id.hash

proc `==`*(a: Symbol, b: Symbol): bool =
  if a.id != b.id: return false
  if a.kind != b.kind: return false
  if a.name != b.name: return false
  case a.kind
  of skBuiltin:
    return a.typ == b.typ and a.value == b.value and a.operatorNotation == b.operatorNotation and a.precedence == b.precedence
  of skAstNode:
    return a.node == b.node

proc fingerprint*(typ: Type): Fingerprint =
  result = @[typ.hash.int64]

proc fingerprint*(value: Value): Fingerprint =
  result = @[value.kind.int64, value.hash]

proc fingerprint*(symbol: Symbol): Fingerprint =
  case symbol.kind
  of skAstNode:
    result = @[symbol.id.hash.int64, symbol.name.hash.int64, symbol.kind.int64]
  of skBuiltin:
    result = @[symbol.id.hash.int64, symbol.name.hash.int64, symbol.kind.int64, symbol.precedence, symbol.operatorNotation.int64]

proc fingerprint*(symbols: TableRef[Id, Symbol]): Fingerprint =
  result = @[]
  for (key, value) in symbols.pairs:
    result.add value.fingerprint

proc fingerprint*(symbol: Option[Symbol]): Fingerprint =
  if symbol.getSome(s):
    return s.fingerprint
  return @[]

CreateContext Context:
  input AstNode
  data Symbol

  var globalScope*: Table[Id, Symbol] = initTable[Id, Symbol]()
  var enableQueryLogging*: bool = false

  proc computeTypeImpl(ctx: Context, node: AstNode): Type {.query("Type").}
  proc computeValueImpl(ctx: Context, node: AstNode): Value {.query("Value").}
  proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] {.query("Symbol").}
  proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] {.query("Symbols").}
  proc computeSymbolTypeImpl(ctx: Context, symbol: Symbol): Type {.query("SymbolType").}
  proc computeSymbolValueImpl(ctx: Context, symbol: Symbol): Value {.query("SymbolValue").}

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
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent - 1), "computeTypeImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent), "-> ", result

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

  of Call():
    let function = node[0]

    let functionType = ctx.computeType(function)
    if functionType.kind == tError:
      return Type(kind: tError)

    if functionType.kind != tFunction:
      logger.log(lvlError, fmt"[compiler] Trying to call non-function type {functionType} at {node}")
      return Type(kind: tError)

    # Check arg num
    let numArgs = node.len - 1
    if numArgs != functionType.paramTypes.len:
      echo node, ": trying to call with wrong number of arguments. Expected ", functionType.paramTypes.len, ", got ", numArgs
      return Type(kind: tError)

    var allArgsOk = true
    for i in 1..numArgs:
      let argType = ctx.computeType(node[i])
      if argType.kind == tError:
        allArgsOk = false
        continue
      if argType != functionType.paramTypes[i - 1]:
        echo node, ": Argument ", i, " has the wrong type. Expected ", functionType.paramTypes[i - 1], ", got ", argType
        allArgsOk = false

    if not allArgsOk:
      return errorType()

    return functionType.returnType

  of Declaration():
    if node.len == 0:
      return errorType()
    return ctx.computeType(node[0])

  of Identifier():
    let id = node.reff
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(id):
      let symbol = symbols[id]
      return ctx.computeSymbolType(symbol)

    echo node, ": Unkown symbol ", id
    return errorType()

  of NodeList():
    if node.len == 0:
      return voidType()
    return ctx.computeType(node.last)

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

  else:
    return errorType()

proc computeSymbolImpl(ctx: Context, node: AstNode): Option[Symbol] =
  case node
  of Identifier():
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(node.reff):
      return some(symbols[node.reff])

  of Declaration():
    logger.log(lvlDebug, fmt"computeSymbol {node}")
    return some(ctx.newSymbol(Symbol(kind: skAstNode, id: node.id, node: node, name: node.text)))

  else:
    logger.log(lvlError, fmt"Failed to get symbol from node {node}")
    return none[Symbol]()

proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent - 1), "computeSymbolsImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent), "-> ", result

  result = newTable[Id, Symbol]()

  if node.findWithParentRec(NodeList).getSome(parentInNodeList):
    let parentSymbols = ctx.computeSymbols(parentInNodeList.parent)
    for (id, sym) in parentSymbols.pairs:
      result.add(id, sym)

    ctx.recordDependency(parentInNodeList.parent.getItem)
    for child in parentInNodeList.parent.children:
      if child == parentInNodeList:
        break
      if child.kind != Declaration:
        continue
      assert child.id != null

      ctx.recordDependency(child.getItem)
      # let symbol = ctx.newSymbol(Symbol(kind: skAstNode, id: child.id, node: child))
      if ctx.computeSymbol(child).getSome(symbol):
        result.add(child.id, symbol)

  for symbol in ctx.globalScope.values:
    ctx.recordDependency(symbol.getItem)
    result.add(symbol.id, symbol)

proc computeValueImpl(ctx: Context, node: AstNode): Value =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent - 1), "computeValueImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent), "-> ", result

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

    if functionValue.kind != vkFunction:
      return errorValue()

    if functionValue.impl == nil:
      echo node, ": Can't call function at compile time: ", function.id
      return errorValue()

    return functionValue.impl(node)

  of NodeList():
    if node.len == 0:
      return errorValue()
    return ctx.computeValue(node.last)

  of Declaration():
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

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.item == node.getItem:
        ctx.depGraph.dependencies[key][i] = ((null, -1), nil)

proc replaceNodeChild*(ctx: Context, parent: AstNode, index: int, newNode: AstNode) =
  let node = parent[index]
  parent[index] = newNode
  ctx.depGraph.changed.del((node.getItem, nil))

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.item == node.getItem:
        ctx.depGraph.dependencies[key][i].item = newNode.getItem

  ctx.insertNode(newNode)