import std/[tables, sets, strutils, hashes, options, macros]
import sugar
import system
import print
import fusion/matching
import ast, ast_ids, id, util
import query_system, compiler

let tempId = newId()
let node = makeTree(AstNode):
  NodeList():
    ConstDecl(id: == tempId):
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
