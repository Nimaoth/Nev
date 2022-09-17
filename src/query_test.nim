import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, id, util
import query_system

let IdAdd = newId()

type Type* = enum
  tError
  tString
  tInt

type
  ValueKind = enum vkError, vkNumber, vkString
  Value* = object
    case kind: ValueKind
    of vkError: discard
    of vkNumber: intValue: int
    of vkString: stringValue: string

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

CreateContext Context:
  proc computeTypeImpl(ctx: Context, node: AstNode): Type {.query("Type").}
  proc computeValueImpl(ctx: Context, node: AstNode): Value {.query("Value").}

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

    if function.id != IdAdd:
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

  else:
    return tError

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

echo "\n\n ============================= Update Node 2 =================================\n\n"
var newNode = makeTree(AstNode): StringLiteral(text: "lol")
ctx.replaceNode(node[1][1], newNode)
node[1][1] = newNode
echo ctx, "\n--------------------------------------"

echo "\n\n ============================= Compute Type 3 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
echo ctx, "\n--------------------------------------"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"

# echo "\n\n ============================= Update Node 4 =================================\n\n"
# newNode = makeTree(AstNode): StringLiteral(text: "bar")
# ctx.replaceNode(node[1][2], newNode)
# node[1][2] = newNode
# echo ctx, "\n--------------------------------------"

# echo "\n\n ============================= Compute Type 5 =================================\n\n"
# echo ctx.computeType(node), "\n--------------------------------------"
# echo ctx, "\n--------------------------------------"
# echo ctx.computeType(node), "\n--------------------------------------"


echo "\n\n ============================= Update Node 6 =================================\n\n"
node[1][1].text = "2 and 3 is "
ctx.updateNode(node[1][1])
echo ctx, "\n--------------------------------------"

echo "\n\n ============================= Compute Type 7 =================================\n\n"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
echo ctx, "\n--------------------------------------"
echo "type ", ctx.computeType(node), "\n--------------------------------------"
echo "value ", ctx.computeValue(node), "\n--------------------------------------"
