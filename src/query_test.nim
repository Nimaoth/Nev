import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, ast_ids, id, util
import query_system


type
  TypeKind = enum
    tError
    tVoid
    tString
    tInt
    tFunction

  Type* = ref object
    case kind: TypeKind
    of tError: discard
    of tVoid: discard
    of tString: discard
    of tInt: discard
    of tFunction:
      returnType: Type
      paramTypes: seq[Type]

  ValueImpl = proc(node: AstNode): Value
  ValueKind = enum vkError, vkNumber, vkString, vkFunction
  Value* = object
    case kind: ValueKind
    of vkError: discard
    of vkNumber: intValue: int
    of vkString: stringValue: string
    of vkFunction: impl: ValueImpl

proc `$`(typ: Type): string =
  case typ.kind
  of tError: return "error"
  of tVoid: return "void"
  of tString: return "string"
  of tInt: return "int"
  of tFunction: return "function " & $typ.paramTypes & " -> " & $typ.returnType & ""

proc hash(typ: Type): Hash =
  case typ.kind
  of tFunction: typ.kind.hash xor typ.returnType.hash xor typ.paramTypes.hash
  else:
    return typ.kind.hash

proc `==`(a: Type, b: Type): bool =
  if a.kind != b.kind: return false
  case a.kind
  of tFunction:
    return a.returnType == b.returnType and a.paramTypes == b.paramTypes
  else:
    return true

func newFunctionType(paramTypes: seq[Type], returnType: Type): Type =
  return Type(kind: tFunction, returnType: returnType, paramTypes: paramTypes)

func intType(): Type =
  return Type(kind: tInt)

func stringType(): Type =
  return Type(kind: tString)

func voidType(): Type =
  return Type(kind: tVoid)

func errorType(): Type =
  return Type(kind: tError)

proc `$`(value: Value): string =
  case value.kind
  of vkNumber: return $value.intValue
  of vkString: return value.stringValue
  of vkFunction: return "function"
  of vkError: return "<vkError>"

proc hash(value: Value): Hash =
  case value.kind
  of vkNumber: return value.intValue.hash
  of vkString: return value.stringValue.hash
  of vkFunction: return value.impl.hash
  else: return 0

type
  SymbolKind = enum skAstNode, skBuiltin
  Symbol* = ref object
    id: Id
    reff: Id
    case kind: SymbolKind
    of skAstNode:
      node*: AstNode
    of skBuiltin:
      typ*: Type
      value*: Value

proc `$`(symbol: Symbol): string =
  case symbol.kind
  of skAstNode:
    return "Sym(AstNode, " & $symbol.id & ", " & $symbol.reff & ", " & $symbol.node & ")"
  of skBuiltin:
    return "Sym(Builtin, " & $symbol.id & ", " & $symbol.typ & ", " & $symbol.value & ")"

proc hash(symbol: Symbol): Hash =
  return symbol.id.hash

proc `==`(a: Symbol, b: Symbol): bool =
  return a.id == b.id

func errorValue(): Value = Value(kind: vkError)

proc fingerprint(typ: Type): Fingerprint =
  result = @[typ.hash.int64]

proc fingerprint(value: Value): Fingerprint =
  result = @[value.kind.int64, value.hash]

proc fingerprint(symbols: TableRef[Id, Symbol]): Fingerprint =
  result = @[]
  for (key, value) in symbols.pairs:
    result.add(key.hash)
    result.add(value.hash)

proc getItem*(node: AstNode): ItemId =
  if node.id == null:
    node.id = newId()
  return (node.id, 0)

proc getItem*(symbol: Symbol): ItemId =
  if symbol.id == null:
    symbol.id = newId()
  return (symbol.id, 1)

CreateContext Context:
  input AstNode
  data Symbol

  var globalScope: Table[Id, Symbol] = initTable[Id, Symbol]()
  var enableQueryLogging: bool = false

  proc computeTypeImpl(ctx: Context, node: AstNode): Type {.query("Type").}
  proc computeValueImpl(ctx: Context, node: AstNode): Value {.query("Value").}
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
  of NumberLiteral():
    return Type(kind: tInt)

  of StringLiteral():
    return Type(kind: tString)

  of Call():
    let function = node[0]

    let functionType = ctx.computeType(function)
    if functionType.kind == tError:
      return Type(kind: tError)

    if functionType.kind != tFunction:
      echo node, ": trying to call non-function type ", functionType
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
      return Type(kind: tError)

    return functionType.returnType

  of Declaration():
    if node.len == 0:
      return Type(kind: tError)
    return ctx.computeType(node[0])

  of Identifier():
    let id = node.reff
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(id):
      let symbol = symbols[id]
      return ctx.computeSymbolType(symbol)

    echo node, ": Unkown symbol ", id
    return Type(kind: tError)

  of NodeList():
    if node.len == 0:
      return Type(kind: tVoid)
    return ctx.computeType(node.last)

  else:
    return Type(kind: tError)

proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] =
  if ctx.enableLogging or ctx.enableQueryLogging: inc currentIndent, 1
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: dec currentIndent, 1
  if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent - 1), "computeSymbolsImpl ", node
  defer:
    if ctx.enableLogging or ctx.enableQueryLogging: echo repeat("| ", currentIndent), "-> ", result

  result = newTable[Id, Symbol]()

  if node.findWithParentRec(NodeList).getSome(parentInNodeList):
    ctx.recordDependency(parentInNodeList.parent.getItem)
    for child in parentInNodeList.parent.children:
      if child == parentInNodeList:
        break
      if child.kind != Declaration:
        continue
      assert child.id != null

      ctx.recordDependency(child.getItem)
      let symbol = ctx.newSymbol(Symbol(kind: skAstNode, id: child.id, node: child))
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
    return Value(kind: vkNumber, intValue: node.text.parseInt)

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

proc insertNode(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, nil)] = ctx.depGraph.revision
  ctx.itemsAstNode[node.getItem] = node
  for (key, child) in node.nextPreOrder:
    ctx.depGraph.changed[(child.getItem, nil)] = ctx.depGraph.revision
    ctx.itemsAstNode[child.getItem] = child

proc updateNode(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.depGraph.changed[(node.getItem, nil)] = ctx.depGraph.revision

proc replaceNodeChild(ctx: Context, parent: AstNode, index: int, newNode: AstNode) =
  let node = parent[index]
  parent[index] = newNode
  ctx.depGraph.changed.del((node.getItem, nil))

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.item == node.getItem:
        ctx.depGraph.dependencies[key][i].item = newNode.getItem

  ctx.insertNode(newNode)

let tempId = newId()
let node = makeTree(AstNode):
  NodeList():
    Declaration(id: == tempId):
      Call():
        Identifier(reff: == IdMul)
        Call():
          Identifier(reff: == IdAdd)
          NumberLiteral(text: "1")
          NumberLiteral(text: "2")
        NumberLiteral(text: "3")
    Call():
      Identifier(reff: == IdAdd)
      Identifier(reff: == tempId)
      NumberLiteral(text: "4")

echo node.treeRepr

let typeAddIntInt = newFunctionType(@[intType(), intType()], intType())
let typeSubIntInt = newFunctionType(@[intType(), intType()], intType())
let typeMulIntInt = newFunctionType(@[intType(), intType()], intType())
let typeDivIntInt = newFunctionType(@[intType(), intType()], intType())
let typeAddStringInt = newFunctionType(@[stringType(), intType()], stringType())

proc newFunctionValue(impl: ValueImpl): Value =
  return Value(kind: vkFunction, impl: impl)

let ctx = newContext()

proc createBinaryIntOperator(operator: proc(a: int, b: int): int): Value =
  return newFunctionValue proc(node: AstNode): Value =
    let leftValue = ctx.computeValue(node[1])
    let rightValue = ctx.computeValue(node[2])

    if leftValue.kind != vkNumber or rightValue.kind != vkNumber:
      echo "left: ", leftValue.kind, ", right: ", rightValue.kind
      return errorValue()
    return Value(kind: vkNumber, intValue: operator(leftValue.intValue, rightValue.intValue))

let funcAddIntInt = createBinaryIntOperator (a: int, b: int) => a + b
let funcSubIntInt = createBinaryIntOperator (a: int, b: int) => a - b
let funcMulIntInt = createBinaryIntOperator (a: int, b: int) => a * b
let funcDivIntInt = createBinaryIntOperator (a: int, b: int) => a div b

let funcAddStringInt = newFunctionValue proc(node: AstNode): Value =
  let leftValue = ctx.computeValue(node[1])
  let rightValue = ctx.computeValue(node[2])
  if leftValue.kind != vkString:
    return errorValue()
  return Value(kind: vkString, stringValue: leftValue.stringValue & $rightValue)

ctx.globalScope.add(IdAdd, Symbol(id: IdAdd, kind: skBuiltin, typ: typeAddIntInt, value: funcAddIntInt))
ctx.globalScope.add(IdSub, Symbol(id: IdSub, kind: skBuiltin, typ: typeSubIntInt, value: funcSubIntInt))
ctx.globalScope.add(IdMul, Symbol(id: IdMul, kind: skBuiltin, typ: typeMulIntInt, value: funcMulIntInt))
ctx.globalScope.add(IdDiv, Symbol(id: IdDiv, kind: skBuiltin, typ: typeDivIntInt, value: funcSubIntInt))
ctx.globalScope.add(IdAppendString, Symbol(id: IdAppendString, kind: skBuiltin, typ: typeAddStringInt, value: funcAddStringInt))
for symbol in ctx.globalScope.values:
  discard ctx.newSymbol(symbol)

proc `$`(ctx: Context): string = $$ctx

echo "\n\n ============================= Insert node =================================\n\n"
# echo ctx, "\n--------------------------------------"
ctx.insertNode(node)
echo ctx, "\n--------------------------------------"

echo "\n\n ============================= Compute Type 1 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"

echo "\n\n ============================= Update Node 2 =================================\n\n"
ctx.replaceNodeChild(node[0][0][1], 1, makeTree(AstNode, StringLiteral(text: "lol")))
# echo ctx, "\n--------------------------------------"
echo node.treeRepr, "\n"

echo "\n\n ============================= Compute Type 3 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo "type ", ctx.computeType(node), "\n--------------------------------------"
# echo "value ", ctx.computeValue(node), "\n--------------------------------------"

echo "\n\n ============================= Update Node 4 =================================\n\n"
node[0][0][1][0].reff = IdAppendString
ctx.updateNode(node[0][0][1][0])
echo node.treeRepr, "\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
node[0][0][0].reff = IdAppendString
ctx.updateNode(node[0][0][0])
echo node.treeRepr, "\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
node[1][0].reff = IdAppendString
ctx.updateNode(node[1][0])
# echo ctx, "\n--------------------------------------"
echo node.treeRepr, "\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
# ctx.replaceNodeChild(node[0][0][1], 2, makeTree(AstNode, StringLiteral(text: "bar")))
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 5 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"


# echo "\n\n ============================= Update Node 6 =================================\n\n"
# node[0][0][1][1].text = "2 and 3 is "
# ctx.updateNode(node[0][0][1][1])
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 7 =================================\n\n"
# echo "type ", ctx.computeType(node), "\n--------------------------------------"
# echo "value ", ctx.computeValue(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo "type ", ctx.computeType(node), "\n--------------------------------------"
# echo "value ", ctx.computeValue(node), "\n--------------------------------------"
