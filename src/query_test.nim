import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, ast_ids, id, util
import query_system

type Type* = enum
  tError
  tVoid
  tString
  tInt
  tFunction

type
  ValueKind = enum vkError, vkNumber, vkString, vkFunction
  Value* = object
    case kind: ValueKind
    of vkError: discard
    of vkNumber: intValue: int
    of vkString: stringValue: string
    of vkFunction: impl: proc(): Value

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

proc `$`(value: Value): string =
  case value.kind
  of vkNumber: return $value.intValue
  of vkString: return "\"" & value.stringValue & "\""
  else: return "<vkError>"

proc hash(value: Value): Hash =
  case value.kind
  of vkNumber: return value.intValue.hash
  of vkString: return value.stringValue.hash
  else: return 0

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
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeTypeImpl ", node

  case node
  of NumberLiteral():
    return tInt

  of StringLiteral():
    return tString

  of Call():
    let function = node[0]

    let functionType = ctx.computeType(function)
    if functionType == tError:
      return tError

    if function.reff != IdAdd:
      return tError
    if node.len != 3:
      return tError

    let left = node[1]
    let right = node[2]

    let leftType = ctx.computeType(left)
    let rightType = ctx.computeType(right)

    if leftType == tInt and rightType == tInt:
      return tInt

    if leftType == tString:
      return tString

    return tError

  of Declaration():
    if node.len == 0:
      return tError
    return ctx.computeType(node[0])

  of Identifier():
    let id = node.reff
    let symbols = ctx.computeSymbols(node)
    if symbols.contains(id):
      let symbol = symbols[id]
      return ctx.computeSymbolType(symbol)

    echo "Unkown symbol ", id
    return tError

  of NodeList():
    if node.len == 0:
      return tVoid
    return ctx.computeType(node.last)

  else:
    return tError

proc computeSymbolsImpl(ctx: Context, node: AstNode): TableRef[Id, Symbol] =
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeSymbolsImpl ", node

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
      let symbol = ctx.newData(Symbol(kind: skAstNode, id: child.id, node: child))
      result.add(child.id, symbol)

  for symbol in ctx.globalScope.values:
    ctx.recordDependency(symbol.getItem)
    result.add(symbol.id, symbol)

proc computeValueImpl(ctx: Context, node: AstNode): Value =
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeValueImpl ", node

  case node
  of NumberLiteral():
    return Value(kind: vkNumber, intValue: node.text.parseInt)

  of StringLiteral():
    return Value(kind: vkString, stringValue: node.text)

  of Call():
    let function = node[0]

    let functionType = ctx.computeType(function)
    if functionType == tError:
      return errorValue()

    if function.reff != IdAdd:
      return errorValue()
    if node.len != 3:
      return errorValue()

    let left = node[1]
    let right = node[2]

    let leftType = ctx.computeType(left)
    let rightType = ctx.computeType(right)

    let leftValue = ctx.computeValue(left)
    let rightValue = ctx.computeValue(right)

    if leftType == tInt and rightType == tInt:
      if leftValue.kind != vkNumber or rightValue.kind != vkNumber:
        return errorValue()
      let newValue = leftValue.intValue + rightValue.intValue
      return Value(kind: vkNumber, intValue: newValue)

    if leftType == tString:
      if leftValue.kind != vkString:
        return errorValue()
      let rightValueString = $rightValue
      let newValue = leftValue.stringValue & rightValueString
      return Value(kind: vkString, stringValue: newValue)

    return errorValue()

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

proc replaceNode(ctx: Context, node: AstNode, newNode: AstNode) =
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
        Identifier(reff: == IdAdd)
        Call():
          Identifier(reff: == IdAdd)
          NumberLiteral(text: "1")
          NumberLiteral(text: "2")
        NumberLiteral(text: "3")
    Call():
      Identifier(reff: == IdAdd)
      Identifier(reff: == tempId)
      NumberLiteral(text: "4")
    # Identifier(reff: == IdAdd)

echo node.treeRepr

let ctx = newContext()
ctx.globalScope.add(IdAdd, Symbol(id: IdAdd, kind: skBuiltin, typ: tFunction, value: errorValue()))
for symbol in ctx.globalScope.values:
  discard ctx.newData(symbol)

proc `$`(ctx: Context): string = $$ctx

echo "\n\n ============================= Insert node =================================\n\n"
# echo ctx, "\n--------------------------------------"
ctx.insertNode(node)
echo ctx, "\n--------------------------------------"

echo "\n\n ============================= Compute Type 1 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo "type ", ctx.computeType(node), "\n--------------------------------------"
# echo "value ", ctx.computeValue(node), "\n--------------------------------------"

echo "\n\n ============================= Update Node 2 =================================\n\n"
var newNode = makeTree(AstNode): StringLiteral(text: "lol")
ctx.replaceNode(node[0][0][1][1], newNode)
node[0][0][1][1] = newNode
# echo ctx, "\n--------------------------------------"
echo node.treeRepr

echo "\n\n ============================= Compute Type 3 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo "type ", ctx.computeType(node), "\n--------------------------------------"
# echo "value ", ctx.computeValue(node), "\n--------------------------------------"

# echo "\n\n ============================= Update Node 4 =================================\n\n"
# newNode = makeTree(AstNode): StringLiteral(text: "bar")
# ctx.replaceNode(node[0][0][1][2], newNode)
# node[0][0][1][2] = newNode
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
