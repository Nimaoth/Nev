import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, id, util
import query_system

var currentIndent = 0

let IdAdd = newId()

type Type* = enum
  Error
  String
  Int

type
  ValueKind = enum ValueError, Number, VKString
  Value* = object
    case kind: ValueKind
    of ValueError: discard
    of Number: intValue: int
    of VKString: stringValue: string

func errorValue(): Value = Value(kind: ValueError)

proc `$`(value: Value): string =
  case value.kind
  of Number: return $value.intValue
  of VKString: return value.stringValue
  else: return "<ValueError>"

proc hash(value: Value): Hash =
  case value.kind
  of Number: return value.intValue.hash
  of VKString: return value.stringValue.hash
  else: return 0

proc fingerprint(typ: Type, res: var Fingerprint) =
  res.add(typ.hash)

proc fingerprint(typ: Type): Fingerprint =
  result = @[]
  typ.fingerprint(result)

proc fingerprint(value: Value): Fingerprint =
  result = @[cast[int64](value.kind), value.hash]

CreateContext Context:
  let a*: Type = String
  proc uiae(ctx: Context, node: AstNode): Type = String
  proc computeTypeImpl*(ctx: Context, node: AstNode): Type
  proc computeValueImpl*(ctx: Context, node: AstNode): Value

# proc computeTypeImpl*(ctx: Context, node: AstNode): Type =
#   return String

# proc computeValueImpl*(ctx: Context, node: AstNode): Value =
#   return Value()

echo computeTypeImpl(newContext(), AstNode())
let customIndentation = "| "

# proc `$`(ctx: Context): string =
#   result = "Context\n"

#   # result.add customIndent(1) & "Cache\n"
#   # for (key, value) in ctx.queryCacheType.pairs:
#   #   result.add customIndent(2) & $key & " -> " & $value & "\n"

#   result.add customIndent(1) & "Input Changed\n"
#   for (key, value) in ctx.inputChanged.pairs:
#     result.add customIndent(2) & $key & " -> " & $value & "\n"

#   result.add indent($ctx.depGraph, 1, customIndentation)

proc computeTypeImpl(ctx: Context, node: AstNode): Type =
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeTypeImpl ", node
  
  case node
  of NumberLiteral():
    return Int

  of StringLiteral():
    return String

  of Call():
    let function = node[0]

    if function.id != IdAdd:
      return Error
    if node.len != 3:
      return Error

    let left = node[1]
    let right = node[2]

    let leftType = ctx.computeType(left)
    let rightType = ctx.computeType(right)

    if leftType == Int and rightType == Int:
      return Int

    if leftType == String:
      return String

    return Error

  else:
    return Error

proc computeValueImpl(ctx: Context, node: AstNode): Value =
  inc currentIndent, 1
  defer: dec currentIndent, 1
  echo repeat("| ", currentIndent - 1), "computeValueImpl ", node
  
  case node
  of NumberLiteral():
    return Value(kind: Number, intValue: node.text.parseInt)

  of StringLiteral():
    return Value(kind: VKString, stringValue: node.text)

  of Call():
    let function = node[0]

    if function.id != IdAdd:
      return errorValue()
    if node.len != 3:
      return errorValue()

    let left = node[1]
    let right = node[2]

    let leftType = ctx.computeType(left)
    let rightType = ctx.computeType(right)

    let leftValue = ctx.computeValue(left)
    let rightValue = ctx.computeValue(right)

    if leftType == Int and rightType == Int:
      if leftValue.kind != Number or rightValue.kind != Number:
        return errorValue()
      let newValue = leftValue.intValue + rightValue.intValue
      return Value(kind: Number, intValue: newValue)

    if leftType == String:
      if leftValue.kind != VKString:
        return errorValue()
      let rightValueString = $rightValue
      let newValue = leftValue.stringValue & rightValueString
      return Value(kind: VKString, stringValue: newValue)

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
  ctx.inputChanged[node] = ctx.depGraph.revision
  for (key, child) in node.nextPreOrder:
    ctx.inputChanged[child] = ctx.depGraph.revision

proc updateNode(ctx: Context, node: AstNode) =
  ctx.depGraph.revision += 1
  ctx.inputChanged[node] = ctx.depGraph.revision

proc replaceNode(ctx: Context, node: AstNode, newNode: AstNode) =
  ctx.inputChanged.del(node)

  for key in ctx.depGraph.dependencies.keys:
    for i, dep in ctx.depGraph.dependencies[key]:
      if dep.node == node:
        ctx.depGraph.dependencies[key][i].node = newNode

  ctx.insertNode(newNode)

let node = makeTree(AstNode):
  # Declaration(id: == newId(), text: "foo"):
  Call():
    Identifier(id: == IdAdd)
    Call():
      Identifier(id: == IdAdd)
      NumberLiteral(text: "1")
      NumberLiteral(text: "2")
    NumberLiteral(text: "3")

let ctx = newContext()

proc `$`(ctx: Context): string = $$ctx

echo "\n\n ============================= Insert node =================================\n\n"
echo ctx, "\n--------------------------------------"
ctx.insertNode(node)
echo ctx, "\n--------------------------------------"

echo "\n\n ============================= Compute Type 1 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
echo ctx, "\n--------------------------------------"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"

# echo "\n\n ============================= Update Node 2 =================================\n\n"
# var newNode = makeTree(AstNode): StringLiteral(text: "lol")
# ctx.replaceNode(node[1][1], newNode)
# node[1][1] = newNode
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 3 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"

# echo "\n\n ============================= Update Node 4 =================================\n\n"
# newNode = makeTree(AstNode): StringLiteral(text: "bar")
# ctx.replaceNode(node[1][2], newNode)
# node[1][2] = newNode
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 5 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"


# echo "\n\n ============================= Update Node 6 =================================\n\n"
# node[2].text = "99"
# ctx.updateNode(node[2])
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 7 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"