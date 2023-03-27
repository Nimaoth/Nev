import std/[strformat]
import id, ast_ids
import types, cells
import print

let expressionClass* = newNodeClass(IdExpression, "Expression", isAbstract=true)
let binaryExpressionClass* = newNodeClass(IdBinaryExpression, "BinaryExpression", isAbstract=true, children=[
    NodeChildDescription(id: IdBinaryExpressionLeft, role: "left", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdBinaryExpressionRight, role: "right", class: expressionClass.id, count: ChildCount.One),
  ])

let numberLiteralClass* = newNodeClass(IdIntegerLiteral, "IntegerLiteral", alias="int", base=expressionClass, properties=[PropertyDescription(id: IdIntegerLiteralValue, role: "value", typ: PropertyType.Int)])
let stringLiteralClass* = newNodeClass(IdStringLiteral, "StringLiteral", alias="string", base=expressionClass, properties=[PropertyDescription(id: IdStringLiteralValue, role: "value", typ: PropertyType.String)])
let boolLiteralClass* = newNodeClass(IdBoolLiteral, "BoolLiteral", alias="bool", base=expressionClass, properties=[PropertyDescription(id: IdBoolLiteralValue, role: "value", typ: PropertyType.Bool)])
let nodeReferenceClass* = newNodeClass(IdNodeReference, "NodeReference", alias="ref", base=expressionClass, references=[NodeReferenceDescription(id: IdNodeReferenceTarget, role: "target", class: expressionClass.id)])

var builder = newCellBuilder()

builder.addBuilderFor numberLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = PropertyCell(property: IdIntegerLiteralValue)
  return cell

builder.addBuilderFor boolLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = PropertyCell(property: IdBoolLiteralValue)
  return cell

builder.addBuilderFor stringLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell()
  cell.children.add ConstantCell(text: "'")
  cell.children.add PropertyCell(property: IdStringLiteralValue)
  cell.children.add ConstantCell(text: "'")
  return cell

builder.addBuilderFor nodeReferenceClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = NodeReferenceCell(reference: IdNodeReferenceTarget)
  return cell

builder.addBuilderFor binaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell()
  for c in node.children(IdBinaryExpressionLeft):
    cell.children.add builder.buildCell(c)
  cell.children.add ConstantCell(text: "+")
  for c in node.children(IdBinaryExpressionRight):
    cell.children.add builder.buildCell(c)
  return cell

let baseLanguage* = newLanguage(IdBaseLanguage, @[
  expressionClass, binaryExpressionClass,
  numberLiteralClass, stringLiteralClass, boolLiteralClass,
  nodeReferenceClass,
], builder)

print baseLanguage
