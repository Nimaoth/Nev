import std/[strformat, sugar]
import platform/[widgets]
import id, ast_ids, util, custom_logger
import types, cells
import print

let typeClass* = newNodeClass(IdType, "Type", isAbstract=true)
let stringTypeClass* = newNodeClass(IdString, "StringType", alias="string", base=typeClass)
let intTypeClass* = newNodeClass(IdInt, "IntType", alias="int", base=typeClass)
let voidTypeClass* = newNodeClass(IdVoid, "VoidType", alias="void", base=typeClass)
let functionTypeClass* = newNodeClass(IdFunctionType, "FunctionType", base=typeClass,
  children=[
    NodeChildDescription(id: IdFunctionTypeReturnType, role: "returnType", class: typeClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdFunctionTypeParameterTypes, role: "parameterTypes", class: typeClass.id, count: ChildCount.ZeroOrMore)])

let namedInterface* = newNodeClass(IdINamed, "INamed", isAbstract=true, isInterface=true,
  properties=[PropertyDescription(id: IdINamedName, role: "name", typ: PropertyType.String)])

let expressionClass* = newNodeClass(IdExpression, "Expression", isAbstract=true)
let binaryExpressionClass* = newNodeClass(IdBinaryExpression, "BinaryExpression", isAbstract=true, base=expressionClass, children=[
    NodeChildDescription(id: IdBinaryExpressionLeft, role: "left", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdBinaryExpressionRight, role: "right", class: expressionClass.id, count: ChildCount.One),
  ])
let unaryExpressionClass* = newNodeClass(IdUnaryExpression, "BinaryExpression", isAbstract=true, base=expressionClass, children=[
    NodeChildDescription(id: IdUnaryExpressionChild, role: "child", class: expressionClass.id, count: ChildCount.One),
  ])

let addExpressionClass* = newNodeClass(IdAdd, "BinaryAddExpression", alias="+", base=binaryExpressionClass)
let subExpressionClass* = newNodeClass(IdSub, "BinarySubExpression", alias="+", base=binaryExpressionClass)
let mulExpressionClass* = newNodeClass(IdMul, "BinaryMulExpression", alias="+", base=binaryExpressionClass)
let divExpressionClass* = newNodeClass(IdDiv, "BinaryDivExpression", alias="+", base=binaryExpressionClass)
let modExpressionClass* = newNodeClass(IdMod, "BinaryModExpression", alias="+", base=binaryExpressionClass)

let appendStringExpressionClass* = newNodeClass(IdAppendString, "BinaryAppendStringExpression", alias="+", base=binaryExpressionClass)
let lessExpressionClass* = newNodeClass(IdLess, "BinaryLessExpression", alias="<", base=binaryExpressionClass)
let lessEqualExpressionClass* = newNodeClass(IdLessEqual, "BinaryLessEqualExpression", alias="<=", base=binaryExpressionClass)
let greaterExpressionClass* = newNodeClass(IdGreater, "BinaryGreaterExpression", alias=">", base=binaryExpressionClass)
let greaterEqualExpressionClass* = newNodeClass(IdGreaterEqual, "BinaryGreaterEqualExpression", alias=">=", base=binaryExpressionClass)
let equalExpressionClass* = newNodeClass(IdEqual, "BinaryEqualExpression", alias="==", base=binaryExpressionClass)
let notEqualExpressionClass* = newNodeClass(IdNotEqual, "BinaryNotEqualExpression", alias="!=", base=binaryExpressionClass)
let andExpressionClass* = newNodeClass(IdAnd, "BinaryAndExpression", alias="and", base=binaryExpressionClass)
let orExpressionClass* = newNodeClass(IdOr, "BinaryOrExpression", alias="or", base=binaryExpressionClass)
let orderExpressionClass* = newNodeClass(IdOrder, "BinaryOrderExpression", alias="<=>", base=binaryExpressionClass)

let negateExpressionClass* = newNodeClass(IdNegate, "UnaryNegateExpression", alias="-", base=unaryExpressionClass)
let notExpressionClass* = newNodeClass(IdNot, "UnaryNotExpression", alias="!", base=unaryExpressionClass)

let printExpressionClass* = newNodeClass(IdPrint, "PrintExpression", alias="print", base=expressionClass,
  children=[
    NodeChildDescription(id: IdPrintArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let buildExpressionClass* = newNodeClass(IdBuildString, "BuildExpression", alias="build", base=expressionClass,
  children=[
    NodeChildDescription(id: IdBuildArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let emptyClass* = newNodeClass(IdEmpty, "Empty", base=expressionClass)
let nodeReferenceClass* = newNodeClass(IdNodeReference, "NodeReference", alias="ref", base=expressionClass, references=[NodeReferenceDescription(id: IdNodeReferenceTarget, role: "target", class: expressionClass.id)])
let numberLiteralClass* = newNodeClass(IdIntegerLiteral, "IntegerLiteral", alias="int", base=expressionClass, properties=[PropertyDescription(id: IdIntegerLiteralValue, role: "value", typ: PropertyType.Int)])
let stringLiteralClass* = newNodeClass(IdStringLiteral, "StringLiteral", alias="string", base=expressionClass, properties=[PropertyDescription(id: IdStringLiteralValue, role: "value", typ: PropertyType.String)])
let boolLiteralClass* = newNodeClass(IdBoolLiteral, "BoolLiteral", alias="bool", base=expressionClass, properties=[PropertyDescription(id: IdBoolLiteralValue, role: "value", typ: PropertyType.Bool)])

let constDeclClass* = newNodeClass(IdConstDecl, "ConstDecl", alias="const", base=expressionClass, interfaces=[namedInterface],
  children=[
    NodeChildDescription(id: IdConstDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdConstDeclValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let letDeclClass* = newNodeClass(IdLetDecl, "LetDecl", alias="let", base=expressionClass, interfaces=[namedInterface],
  children=[
    NodeChildDescription(id: IdLetDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdLetDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let varDeclClass* = newNodeClass(IdVarDecl, "VarDecl", alias="var", base=expressionClass, interfaces=[namedInterface],
  children=[
    NodeChildDescription(id: IdVarDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdVarDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let nodeListClass* = newNodeClass(IdNodeList, "NodeList", base=expressionClass,
  children=[
    NodeChildDescription(id: IdNodeListChildren, role: "children", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let callClass* = newNodeClass(IdCall, "Call", base=expressionClass,
  children=[
    NodeChildDescription(id: IdCallFunction, role: "function", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdCallArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let ifClass* = newNodeClass(IdIfExpression, "IfExpression", alias="if", base=expressionClass, children=[
    NodeChildDescription(id: IdIfExpressionCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdIfExpressionThenCase, role: "thenCase", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdIfExpressionElseCase, role: "elseCase", class: expressionClass.id, count: ChildCount.ZeroOrOne),
  ])

let whileClass* = newNodeClass(IdWhileExpression, "WhileExpression", alias="while", base=expressionClass, children=[
    NodeChildDescription(id: IdWhileExpressionCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdWhileExpressionBody, role: "body", class: expressionClass.id, count: ChildCount.One),
  ])

let parameterDeclClass* = newNodeClass(IdParameterDecl, "ParameterDecl", alias="parameter", base=expressionClass, interfaces=[namedInterface],
  children=[
    NodeChildDescription(id: IdParameterDeclType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdParameterDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let functionDefinitionClass* = newNodeClass(IdFunctionDefinition, "FunctionDefinition", base=expressionClass,
  children=[
    NodeChildDescription(id: IdFunctionDefinitionParameters, role: "parameters", class: parameterDeclClass.id, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdFunctionDefinitionReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdFunctionDefinitionBody, role: "body", class: expressionClass.id, count: ChildCount.One)])

let assignmentClass* = newNodeClass(IdAssignment, "Assignment", alias="=", base=expressionClass, children=[
    NodeChildDescription(id: IdAssignmentTarget, role: "target", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdAssignmentValue, role: "value", class: expressionClass.id, count: ChildCount.One),
  ])

var builder = newCellBuilder()

builder.addBuilderFor emptyClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = ConstantCell(node: node)
  return cell

builder.addBuilderFor numberLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = PropertyCell(node: node, property: IdIntegerLiteralValue)
  return cell

builder.addBuilderFor boolLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = PropertyCell(node: node, property: IdBoolLiteralValue)
  return cell

builder.addBuilderFor stringLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.children.add ConstantCell(node: node, text: "'")
  cell.children.add PropertyCell(node: node, property: IdStringLiteralValue)
  cell.children.add ConstantCell(node: node, text: "'")
  return cell

builder.addBuilderFor nodeListClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Vertical))
  cell.fillChildren = proc() =
    # echo "fill collection node list"
    for c in node.children(IdNodeListChildren):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor constDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection const decl"
    cell.children.add ConstantCell(node: node, text: "const ")
    cell.children.add PropertyCell(node: node, property: IdINamedName)
    cell.children.add ConstantCell(node: node, text: " : ", isVisible: (node) => node.hasChild(IdConstDeclType))
    for c in node.children(IdConstDeclType):
      cell.children.add builder.buildCell(c)
    cell.children.add ConstantCell(node: node, text: " = ")
    for c in node.children(IdConstDeclValue):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor letDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection let decl"
    cell.children.add ConstantCell(node: node, text: "let ")
    cell.children.add PropertyCell(node: node, property: IdINamedName)
    cell.children.add ConstantCell(node: node, text: " : ", isVisible: (node) => node.hasChild(IdLetDeclType))
    for c in node.children(IdLetDeclType):
      cell.children.add builder.buildCell(c)
    cell.children.add ConstantCell(node: node, text: " = ")
    for c in node.children(IdLetDeclValue):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor varDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection var decl"
    cell.children.add ConstantCell(node: node, text: "var ")
    cell.children.add PropertyCell(node: node, property: IdINamedName)
    cell.children.add ConstantCell(node: node, text: " : ", isVisible: (node) => node.hasChild(IdVarDeclType))
    for c in node.children(IdVarDeclType):
      cell.children.add builder.buildCell(c)
    cell.children.add ConstantCell(node: node, text: " = ", isVisible: (node) => node.hasChild(IdVarDeclValue))
    for c in node.children(IdVarDeclValue):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor assignmentClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection assignment"
    for c in node.children(IdAssignmentTarget):
      cell.children.add builder.buildCell(c)
    cell.children.add ConstantCell(node: node, text: " = ")
    for c in node.children(IdAssignmentValue):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor parameterDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection parameter decl"
    cell.children.add PropertyCell(node: node, property: IdINamedName)
    cell.children.add ConstantCell(node: node, text: " : ")
    for c in node.children(IdParameterDeclType):
      cell.children.add builder.buildCell(c)
    cell.children.add ConstantCell(node: node, text: " = ", isVisible: (node) => node.hasChild(IdParameterDeclValue))
    for c in node.children(IdParameterDeclValue):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor functionDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection func def"
    cell.children.add ConstantCell(node: node, text: "fn")
    cell.children.add ConstantCell(node: node, text: "(")

    for i, c in node.children(IdFunctionDefinitionParameters):
      if i > 0:
        cell.children.add ConstantCell(node: node, text: ", ")
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: ")")
    cell.children.add ConstantCell(node: node, text: ": ")

    for c in node.children(IdFunctionDefinitionReturnType):
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: "=", style: CellStyle(addNewlineAfter: true, indentAfter: true))

    for c in node.children(IdFunctionDefinitionBody):
      cell.children.add builder.buildCell(c)

  return cell

builder.addBuilderFor callClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection call"

    for c in node.children(IdCallFunction):
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: "(")

    for i, c in node.children(IdCallArguments):
      if i > 0:
        cell.children.add ConstantCell(node: node, text: ", ")
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: ")")

  return cell

builder.addBuilderFor ifClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection if"

    cell.children.add ConstantCell(node: node, text: "if ")

    for c in node.children(IdIfExpressionCondition):
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: ":", style: CellStyle(addNewlineAfter: true, indentAfter: true))

    for c in node.children(IdIfExpressionThenCase):
      var cc = builder.buildCell(c)
      cc.style = CellStyle(addNewlineAfter: true)
      cell.children.add cc

    for i, c in node.children(IdIfExpressionElseCase):
      if i == 0:
        cell.children.add ConstantCell(node: node, text: "else:", style: CellStyle(addNewlineAfter: true, indentAfter: true))
      cell.children.add builder.buildCell(c)

  return cell

builder.addBuilderFor whileClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection while"

    cell.children.add ConstantCell(node: node, text: "while ")

    for c in node.children(IdWhileExpressionCondition):
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: ":", style: CellStyle(addNewlineAfter: true, indentAfter: true))

    for c in node.children(IdWhileExpressionBody):
      cell.children.add builder.buildCell(c)

  return cell

builder.addBuilderFor nodeReferenceClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = NodeReferenceCell(node: node, reference: IdNodeReferenceTarget, property: IdINamedName)
  if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
    cell.child = PropertyCell(node: targetNode, property: IdINamedName)
  return cell

builder.addBuilderFor binaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection binary"
    for c in node.children(IdBinaryExpressionLeft):
      cell.children.add builder.buildCell(c)
    cell.children.add AliasCell(node: node)
    for c in node.children(IdBinaryExpressionRight):
      cell.children.add builder.buildCell(c)
  return cell

builder.addBuilderFor unaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection binary"
    for c in node.children(IdBinaryExpressionLeft):
      cell.children.add builder.buildCell(c)
    cell.children.add AliasCell(node: node)
  return cell

builder.addBuilderFor stringTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(node: node)
  return cell

builder.addBuilderFor voidTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(node: node)
  return cell

builder.addBuilderFor intTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(node: node)
  return cell

builder.addBuilderFor printExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection call"

    cell.children.add AliasCell(node: node)
    cell.children.add ConstantCell(node: node, text: "(")

    for i, c in node.children(IdPrintArguments):
      if i > 0:
        cell.children.add ConstantCell(node: node, text: ", ")
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: ")")

  return cell

builder.addBuilderFor buildExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(node: node, layout: WPanelLayout(kind: Horizontal))
  cell.fillChildren = proc() =
    # echo "fill collection call"

    cell.children.add AliasCell(node: node)
    cell.children.add ConstantCell(node: node, text: "(")

    for i, c in node.children(IdBuildArguments):
      if i > 0:
        cell.children.add ConstantCell(node: node, text: ", ")
      cell.children.add builder.buildCell(c)

    cell.children.add ConstantCell(node: node, text: ")")

  return cell

let baseLanguage* = newLanguage(IdBaseLanguage, @[
  namedInterface,

  typeClass, stringTypeClass, intTypeClass, voidTypeClass, functionTypeClass,

  expressionClass, binaryExpressionClass, unaryExpressionClass,
  numberLiteralClass, stringLiteralClass, boolLiteralClass, nodeReferenceClass, emptyClass, constDeclClass, letDeclClass, varDeclClass, nodeListClass, callClass, ifClass, whileClass,
  parameterDeclClass, functionDefinitionClass, assignmentClass,
  addExpressionClass, subExpressionClass, mulExpressionClass, divExpressionClass, modExpressionClass,
  lessExpressionClass, lessEqualExpressionClass, greaterExpressionClass, greaterEqualExpressionClass, equalExpressionClass, notEqualExpressionClass, andExpressionClass, orExpressionClass, orderExpressionClass,
  negateExpressionClass, notExpressionClass,
  appendStringExpressionClass, printExpressionClass, buildExpressionClass,
], builder)

print baseLanguage
