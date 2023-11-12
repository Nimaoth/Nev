import std/[tables, strformat]
import id, ast_ids, util, custom_logger
import model, cells
import ui/node

logCategory "base-language"

let expressionClass* = newNodeClass(IdExpression, "Expression", isAbstract=true)
# let typeClass* = newNodeClass(IdType, "Type", isAbstract=true)

let metaTypeClass* = newNodeClass(IdType, "Type", alias="type", base=expressionClass)
let stringTypeClass* = newNodeClass(IdString, "StringType", alias="string", base=expressionClass)
let intTypeClass* = newNodeClass(IdInt, "IntType", alias="int", base=expressionClass)
let voidTypeClass* = newNodeClass(IdVoid, "VoidType", alias="void", base=expressionClass)
let functionTypeClass* = newNodeClass(IdFunctionType, "FunctionType", alias="fn", base=expressionClass,
  children=[
    NodeChildDescription(id: IdFunctionTypeReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdFunctionTypeParameterTypes, role: "parameterTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore)])
let structTypeClass* = newNodeClass(IdStructType, "StructType", alias="struct", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStructTypeMemberTypes, role: "memberTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let namedInterface* = newNodeClass(IdINamed, "INamed", isAbstract=true, isInterface=true,
  properties=[PropertyDescription(id: IdINamedName, role: "name", typ: PropertyType.String)])

let declarationInterface* = newNodeClass(IdIDeclaration, "IDeclaration", isAbstract=true, isInterface=true, base=namedInterface)

let binaryExpressionClass* = newNodeClass(IdBinaryExpression, "BinaryExpression", isAbstract=true, base=expressionClass, children=[
    NodeChildDescription(id: IdBinaryExpressionLeft, role: "left", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdBinaryExpressionRight, role: "right", class: expressionClass.id, count: ChildCount.One),
  ])
let unaryExpressionClass* = newNodeClass(IdUnaryExpression, "UnaryExpression", isAbstract=true, base=expressionClass, children=[
    NodeChildDescription(id: IdUnaryExpressionChild, role: "child", class: expressionClass.id, count: ChildCount.One),
  ])

let emptyLineClass* = newNodeClass(IdEmptyLine, "EmptyLine", base=expressionClass)

let addExpressionClass* = newNodeClass(IdAdd, "BinaryAddExpression", alias="+", base=binaryExpressionClass, precedence=5)
let subExpressionClass* = newNodeClass(IdSub, "BinarySubExpression", alias="-", base=binaryExpressionClass, precedence=5)
let mulExpressionClass* = newNodeClass(IdMul, "BinaryMulExpression", alias="*", base=binaryExpressionClass, precedence=6)
let divExpressionClass* = newNodeClass(IdDiv, "BinaryDivExpression", alias="/", base=binaryExpressionClass, precedence=6)
let modExpressionClass* = newNodeClass(IdMod, "BinaryModExpression", alias="%", base=binaryExpressionClass, precedence=6)

let appendStringExpressionClass* = newNodeClass(IdAppendString, "BinaryAppendStringExpression", alias="&", base=binaryExpressionClass, precedence=4)
let lessExpressionClass* = newNodeClass(IdLess, "BinaryLessExpression", alias="<", base=binaryExpressionClass, precedence=4)
let lessEqualExpressionClass* = newNodeClass(IdLessEqual, "BinaryLessEqualExpression", alias="<=", base=binaryExpressionClass, precedence=4)
let greaterExpressionClass* = newNodeClass(IdGreater, "BinaryGreaterExpression", alias=">", base=binaryExpressionClass, precedence=4)
let greaterEqualExpressionClass* = newNodeClass(IdGreaterEqual, "BinaryGreaterEqualExpression", alias=">=", base=binaryExpressionClass, precedence=4)
let equalExpressionClass* = newNodeClass(IdEqual, "BinaryEqualExpression", alias="==", base=binaryExpressionClass, precedence=4)
let notEqualExpressionClass* = newNodeClass(IdNotEqual, "BinaryNotEqualExpression", alias="!=", base=binaryExpressionClass, precedence=4)
let orderExpressionClass* = newNodeClass(IdOrder, "BinaryOrderExpression", alias="<=>", base=binaryExpressionClass, precedence=4)
let andExpressionClass* = newNodeClass(IdAnd, "BinaryAndExpression", alias="and", base=binaryExpressionClass, precedence=3)
let orExpressionClass* = newNodeClass(IdOr, "BinaryOrExpression", alias="or", base=binaryExpressionClass, precedence=3)

let negateExpressionClass* = newNodeClass(IdNegate, "UnaryNegateExpression", alias="-", base=unaryExpressionClass)
let notExpressionClass* = newNodeClass(IdNot, "UnaryNotExpression", alias="!", base=unaryExpressionClass)

let printExpressionClass* = newNodeClass(IdPrint, "PrintExpression", alias="print", base=expressionClass,
  children=[
    NodeChildDescription(id: IdPrintArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let buildExpressionClass* = newNodeClass(IdBuildString, "BuildExpression", alias="build", base=expressionClass,
  children=[
    NodeChildDescription(id: IdBuildArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let emptyClass* = newNodeClass(IdEmpty, "Empty", base=expressionClass)
let nodeReferenceClass* = newNodeClass(IdNodeReference, "NodeReference", alias="ref", base=expressionClass, references=[NodeReferenceDescription(id: IdNodeReferenceTarget, role: "target", class: declarationInterface.id)])
let numberLiteralClass* = newNodeClass(IdIntegerLiteral, "IntegerLiteral", alias="number", base=expressionClass, properties=[PropertyDescription(id: IdIntegerLiteralValue, role: "value", typ: PropertyType.Int)], substitutionProperty=IdIntegerLiteralValue.some)
let stringLiteralClass* = newNodeClass(IdStringLiteral, "StringLiteral", alias="''", base=expressionClass, properties=[PropertyDescription(id: IdStringLiteralValue, role: "value", typ: PropertyType.String)])
let boolLiteralClass* = newNodeClass(IdBoolLiteral, "BoolLiteral", alias="bool", base=expressionClass, properties=[PropertyDescription(id: IdBoolLiteralValue, role: "value", typ: PropertyType.Bool)])

let constDeclClass* = newNodeClass(IdConstDecl, "ConstDecl", alias="const", base=expressionClass, interfaces=[declarationInterface],
  children=[
    NodeChildDescription(id: IdConstDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdConstDeclValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let letDeclClass* = newNodeClass(IdLetDecl, "LetDecl", alias="let", base=expressionClass, interfaces=[declarationInterface],
  children=[
    NodeChildDescription(id: IdLetDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdLetDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let varDeclClass* = newNodeClass(IdVarDecl, "VarDecl", alias="var", base=expressionClass, interfaces=[declarationInterface],
  children=[
    NodeChildDescription(id: IdVarDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdVarDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let nodeListClass* = newNodeClass(IdNodeList, "NodeList",
  children=[
    NodeChildDescription(id: IdNodeListChildren, role: "children", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let blockClass* = newNodeClass(IdBlock, "Block", alias="{", base=expressionClass,
  children=[
    NodeChildDescription(id: IdBlockChildren, role: "children", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let callClass* = newNodeClass(IdCall, "Call", base=expressionClass,
  children=[
    NodeChildDescription(id: IdCallFunction, role: "function", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdCallArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let thenCaseClass* = newNodeClass(IdThenCase, "ThenCase", isFinal=true, children=[
    NodeChildDescription(id: IdThenCaseCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdThenCaseBody, role: "body", class: expressionClass.id, count: ChildCount.One),
  ])

let ifClass* = newNodeClass(IdIfExpression, "IfExpression", alias="if", base=expressionClass, children=[
    NodeChildDescription(id: IdIfExpressionThenCase, role: "thenCase", class: thenCaseClass.id, count: ChildCount.OneOrMore),
    NodeChildDescription(id: IdIfExpressionElseCase, role: "elseCase", class: expressionClass.id, count: ChildCount.ZeroOrOne),
  ])

let whileClass* = newNodeClass(IdWhileExpression, "WhileExpression", alias="while", base=expressionClass, children=[
    NodeChildDescription(id: IdWhileExpressionCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdWhileExpressionBody, role: "body", class: expressionClass.id, count: ChildCount.One),
  ])

let breakClass* = newNodeClass(IdBreakExpression, "BreakExpression", alias="break", base=expressionClass)
let continueClass* = newNodeClass(IdContinueExpression, "ContinueExpression", alias="continue", base=expressionClass)
let returnClass* = newNodeClass(IdReturnExpression, "ReturnExpression", alias="return", base=expressionClass)

let parameterDeclClass* = newNodeClass(IdParameterDecl, "ParameterDecl", alias="param", base=expressionClass, interfaces=[declarationInterface],
  children=[
    NodeChildDescription(id: IdParameterDeclType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdParameterDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let functionDefinitionClass* = newNodeClass(IdFunctionDefinition, "FunctionDefinition", alias="fn", base=expressionClass,
  children=[
    NodeChildDescription(id: IdFunctionDefinitionParameters, role: "parameters", class: parameterDeclClass.id, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdFunctionDefinitionReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdFunctionDefinitionBody, role: "body", class: expressionClass.id, count: ChildCount.One)])

let structMemberDefinitionClass* = newNodeClass(IdStructMemberDefinition, "StructMemberDefinition", alias="member", interfaces=[declarationInterface],
  children=[
    NodeChildDescription(id: IdStructMemberDefinitionType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdStructMemberDefinitionValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let structDefinitionClass* = newNodeClass(IdStructDefinition, "StructDefinition", alias="struct", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStructDefinitionMembers, role: "members", class: structMemberDefinitionClass.id, count: ChildCount.ZeroOrMore)])

let structMemberAccessClass* = newNodeClass(IdStructMemberAccess, "StructMemberAccess", base=expressionClass,
  references=[NodeReferenceDescription(id: IdStructMemberAccessMember, role: "member", class: structMemberDefinitionClass.id)],
  children=[NodeChildDescription(id: IdStructMemberAccessValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let assignmentClass* = newNodeClass(IdAssignment, "Assignment", alias="=", base=expressionClass, children=[
    NodeChildDescription(id: IdAssignmentTarget, role: "target", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdAssignmentValue, role: "value", class: expressionClass.id, count: ChildCount.One),
  ])

var builder = newCellBuilder()

builder.addBuilderFor emptyLineClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = ConstantCell(id: newId().CellId, node: node)
  return cell

builder.addBuilderFor emptyClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = ConstantCell(id: newId().CellId, node: node)
  return cell

builder.addBuilderFor numberLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = PropertyCell(id: newId().CellId, node: node, property: IdIntegerLiteralValue, themeForegroundColors: @["constant.numeric"])
  return cell

builder.addBuilderFor boolLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = PropertyCell(id: newId().CellId, node: node, property: IdBoolLiteralValue, themeForegroundColors: @["constant.numeric"])
  return cell

builder.addBuilderFor stringLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.add ConstantCell(node: node, text: "'", style: CellStyle(noSpaceRight: true), disableEditing: true, deleteImmediately: true, themeForegroundColors: @["punctuation.definition.string", "punctuation", "&editor.foreground"])
  cell.add PropertyCell(node: node, property: IdStringLiteralValue, themeForegroundColors: @["string"])
  cell.add ConstantCell(node: node, text: "'", style: CellStyle(noSpaceLeft: true), disableEditing: true, deleteImmediately: true, themeForegroundColors: @["punctuation.definition.string", "punctuation", "&editor.foreground"])
  return cell

builder.addBuilderFor nodeListClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutVertical})
  cell.nodeFactory = proc(): AstNode =
    return newAstNode(emptyLineClass)
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection node list"
    cell.add builder.buildChildren(map, node, IdNodeListChildren, &{LayoutVertical})
  return cell

builder.addBuilderFor blockClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutVertical}, flags: &{IndentChildren, OnNewLine})
  cell.nodeFactory = proc(): AstNode =
    return newAstNode(emptyLineClass)
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection block"
    cell.add builder.buildChildren(map, node, IdBlockChildren, &{LayoutVertical})
  return cell

builder.addBuilderFor constDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdConstDeclType)

    # echo "fill collection const decl"
    cell.add ConstantCell(node: node, text: "const", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", isVisible: isVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdConstDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "<type>")
    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdConstDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor letDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdLetDeclType)

    # echo "fill collection let decl"
    cell.add ConstantCell(node: node, text: "let", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", isVisible: isVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdLetDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "<type>")
    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdLetDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor varDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isTypeVisible(node: AstNode): bool = node.hasChild(IdVarDeclType)
    proc isValueVisible(node: AstNode): bool = node.hasChild(IdVarDeclValue)

    # echo "fill collection var decl"
    cell.add ConstantCell(node: node, text: "var", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", isVisible: isTypeVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdVarDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "<type>")
    cell.add ConstantCell(node: node, text: "=", isVisible: isValueVisible, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdVarDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor assignmentClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection assignment"
    cell.add builder.buildChildren(map, node, IdAssignmentTarget, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdAssignmentValue, &{LayoutHorizontal})
  return cell

builder.addBuilderFor parameterDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdParameterDeclValue)

    # echo "fill collection parameter decl"
    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      builder.buildChildrenT(map, node, IdParameterDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")

    cell.add ConstantCell(node: node, text: "=", isVisible: isVisible, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdParameterDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        visible: isVisible(node)
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor functionDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection func def"
    cell.add ConstantCell(node: node, text: "fn", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add ConstantCell(node: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdFunctionDefinitionParameters, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: "..."

    cell.add ConstantCell(node: node, text: "):", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      builder.buildChildrenT(map, node, IdFunctionDefinitionReturnType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: "..."

    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      builder.buildChildrenT(map, node, IdFunctionDefinitionBody, &{LayoutVertical}, 0.CellFlags):
        placeholder: "..."

  return cell

builder.addBuilderFor structMemberDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdStructMemberDefinitionValue)

    # echo "fill collection let decl"
    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdStructMemberDefinitionType, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdStructMemberDefinitionValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor structDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection func def"
    cell.add ConstantCell(node: node, text: "struct", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add ConstantCell(node: node, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdStructDefinitionMembers, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
        placeholder: "..."

    cell.add ConstantCell(node: node, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{OnNewLine})

  return cell

builder.addBuilderFor structMemberAccessClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection func def"
    cell.add block:
      buildChildrenT(builder, map, node, IdStructMemberAccessValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: "..."

    cell.add ConstantCell(node: node, text: ".", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight})

    cell.add block:
      if node.resolveReference(IdStructMemberAccessMember).getSome(targetNode):
        # var refCell = NodeReferenceCell(id: newId().CellId, node: node, reference: IdStructMemberAccessMember, property: IdINamedName, disableEditing: true)
        PropertyCell(id: newId().CellId, node: node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])
      else:
        PlaceholderCell(id: newId().CellId, node: node, role: IdStructMemberAccessMember, shadowText: "_")

  return cell

builder.addBuilderFor callClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection call"

    cell.add builder.buildChildren(map, node, IdCallFunction, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdCallArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "")

    cell.add ConstantCell(node: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

builder.addBuilderFor thenCaseClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection ThenCase"

    if node.index == 0:
      cell.add ConstantCell(node: node, text: "if", themeForegroundColors: @["keyword"], disableEditing: true)
    else:
      cell.add ConstantCell(node: node, text: "elif", themeForegroundColors: @["keyword"], disableEditing: true, flags: &{OnNewLine})
    cell.add builder.buildChildren(map, node, IdThenCaseCondition, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdThenCaseBody, &{LayoutHorizontal})

  return cell

builder.addBuilderFor ifClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal}, flags: &{DeleteWhenEmpty}, inline: true)
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection if"

    cell.add block:
      builder.buildChildren(map, node, IdIfExpressionThenCase, &{LayoutVertical}, &{DeleteWhenEmpty})

    if node.childCount(IdIfExpressionElseCase) == 0:
      var flags = 0.CellFlags
      if node.childCount(IdIfExpressionThenCase) > 0:
        flags.incl OnNewLine
      cell.add PlaceholderCell(id: newId().CellId, node: node, role: IdIfExpressionElseCase, shadowText: "<else>", flags: flags)
    else:
      for i, c in node.children(IdIfExpressionElseCase):
        if i == 0:
          cell.add ConstantCell(node: node, text: "else", flags: &{OnNewLine}, themeForegroundColors: @["keyword"], disableEditing: true)
          cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
        cell.add builder.buildCell(map, c)

  return cell

builder.addBuilderFor whileClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection while"
    cell.add ConstantCell(node: node, text: "while", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdWhileExpressionCondition, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdWhileExpressionBody, &{LayoutHorizontal})

  return cell

builder.addBuilderFor breakClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor continueClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor returnClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor nodeReferenceClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
    return PropertyCell(id: newId().CellId, node: node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])
  else:
    return ConstantCell(id: newId().CellId, node: node, text: $node.reference(IdNodeReferenceTarget))

# builder.addBuilderFor typeClass.id, idNone(), &{OnlyExactMatch}, proc(builder: CellBuilder, node: AstNode): Cell =
#   var cell = ConstantCell(id: newId().CellId, node: node, shadowText: "<type>", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"])
  # return cell

builder.addBuilderFor expressionClass.id, idNone(), &{OnlyExactMatch}, proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = ConstantCell(id: newId().CellId, node: node, shadowText: "<expr>", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"])
  return cell

builder.addBuilderFor binaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection binary"
    let lowerPrecedence = node.parent.isNotNil and node.parent.nodeClass.precedence >= node.nodeClass.precedence

    if lowerPrecedence:
      cell.add ConstantCell(node: node, text: "(", flags: &{NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add builder.buildChildren(map, node, IdBinaryExpressionLeft, &{LayoutHorizontal})
    cell.add AliasCell(node: node, disableEditing: true)
    cell.add builder.buildChildren(map, node, IdBinaryExpressionRight, &{LayoutHorizontal})

    if lowerPrecedence:
      cell.add ConstantCell(node: node, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

builder.addBuilderFor divExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutVertical}, inline: true)
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection binary"
    cell.add builder.buildChildren(map, node, IdBinaryExpressionLeft, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "------", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdBinaryExpressionRight, &{LayoutHorizontal})
  return cell

builder.addBuilderFor unaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection binary"
    cell.add AliasCell(node: node, style: CellStyle(noSpaceRight: true), disableEditing: true)
    cell.add builder.buildChildren(map, node, IdUnaryExpressionChild, &{LayoutHorizontal})
  return cell

builder.addBuilderFor stringTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor voidTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor intTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor printExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection call"

    cell.add AliasCell(node: node, disableEditing: true)
    cell.add ConstantCell(node: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdPrintArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "")

    cell.add ConstantCell(node: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

builder.addBuilderFor buildExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    # echo "fill collection call"

    cell.add AliasCell(node: node, disableEditing: true)
    cell.add ConstantCell(node: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdBuildArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "")

    cell.add ConstantCell(node: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()

let metaTypeInstance* = newAstNode(metaTypeClass)
let stringTypeInstance* = newAstNode(stringTypeClass)
let intTypeInstance* = newAstNode(intTypeClass)
let voidTypeInstance* = newAstNode(voidTypeClass)

# todo: those should technically return something like metaTypeInstance which needs a new metaTypeClass
# and the valueComputer should return the type instance
typeComputers[stringTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for string type literal {node}"
  return stringTypeInstance
typeComputers[intTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for int type literal {node}"
  return intTypeInstance
typeComputers[voidTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for void type literal {node}"
  return voidTypeInstance

# base expression
typeComputers[expressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for base expression {node}"
  return voidTypeInstance

# literals
typeComputers[stringLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for string type literal {node}"
  return stringTypeInstance

typeComputers[numberLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for int type literal {node}"
  return intTypeInstance

typeComputers[boolLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for bool type literal {node}"
  return intTypeInstance

# declarations
typeComputers[letDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for let decl {node}"
  if node.firstChild(IdLetDeclType).getSome(typeNode):
    return ctx.computeType(typeNode)
  if node.firstChild(IdLetDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

typeComputers[varDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for var decl {node}"
  if node.firstChild(IdVarDeclType).getSome(typeNode):
    return ctx.computeType(typeNode)
  if node.firstChild(IdVarDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

typeComputers[constDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for const decl {node}"
  if node.firstChild(IdConstDeclType).getSome(typeNode):
    return ctx.computeType(typeNode)
  if node.firstChild(IdConstDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

typeComputers[parameterDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for const decl {node}"
  if node.firstChild(IdParameterDeclType).getSome(typeNode):
    return ctx.computeType(typeNode)
  if node.firstChild(IdParameterDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

# control flow
typeComputers[whileClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for while loop {node}"
  return voidTypeInstance

typeComputers[thenCaseClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for then case {node}"
  if node.firstChild(IdThenCaseBody).getSome(body):
    return ctx.computeType(body)
  return voidTypeInstance

typeComputers[ifClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for if expr {node}"

  var ifType: AstNode = voidTypeInstance
  for i, thenCase in node.children(IdIfExpressionThenCase):
    let thenType = ctx.computeType(thenCase)
    if i == 0:
      ifType = thenType
    elif ifType == thenType:
      continue
    else:
      ifType = voidTypeInstance
      break

  if ifType.class != IdVoid and node.firstChild(IdIfExpressionElseCase).getSome(elseCase):
    let elseType = ctx.computeType(elseCase)
    if ifType == elseType:
      return ifType

  return voidTypeInstance

# function definition
typeComputers[functionDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for function definition {node}"
  var returnType = voidTypeInstance

  if node.firstChild(IdFunctionDefinitionReturnType).getSome(returnTypeNode):
    returnType = ctx.computeType(returnTypeNode)

  var functionType = newAstNode(functionTypeClass)
  functionType.add(IdFunctionTypeReturnType, returnType)

  for _, c in node.children(IdFunctionDefinitionParameters):
    if c.firstChild(IdParameterDeclType).getSome(paramTypeNode):
      # todo: This needs computeValue in the future since the type of a type is 'type', and the value is 'int' or 'string' etc.
      var parameterType = ctx.computeType(paramTypeNode)
      if parameterType.isNil:
        # addDiagnostic(paramTypeNode, "Could not compute type for parameter")
        continue
      functionType.add(IdFunctionTypeParameterTypes, parameterType)

  # todo: this shouldn't set the model
  functionType.model = node.model
  functionType.forEach2 n:
    n.model = node.model

  debugf"computed function type: {`$`(functionType, true)}"

  return functionType

typeComputers[assignmentClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for assignment {node}"
  return voidTypeInstance

typeComputers[emptyClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for empty {node}"
  return voidTypeInstance

typeComputers[nodeListClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for node list {node}"

  if node.firstChild(IdNodeListChildren).getSome(childNode):
    return ctx.computeType(childNode)

  return voidTypeInstance

typeComputers[blockClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for block {node}"

  if node.lastChild(IdBlockChildren).getSome(childNode):
    return ctx.computeType(childNode)

  return voidTypeInstance

typeComputers[nodeReferenceClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for node reference {node}"
  # todo
  if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
    return ctx.computeType(targetNode)
  return voidTypeInstance

typeComputers[breakClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for break {node}"
  return voidTypeInstance

typeComputers[continueClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for continue {node}"
  return voidTypeInstance

typeComputers[returnClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for return {node}"
  return voidTypeInstance

# binary expressions
typeComputers[addExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for add {node}"
  return intTypeInstance

typeComputers[subExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for sub {node}"
  return intTypeInstance

typeComputers[mulExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for mul {node}"
  return intTypeInstance

typeComputers[divExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for div {node}"
  return intTypeInstance

typeComputers[modExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for mod {node}"
  return intTypeInstance

typeComputers[lessExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for less {node}"
  return intTypeInstance

typeComputers[lessEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for less equal {node}"
  return intTypeInstance

typeComputers[greaterExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for greater {node}"
  return intTypeInstance

typeComputers[greaterEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for greater equal {node}"
  return intTypeInstance

typeComputers[equalExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for equal {node}"
  return intTypeInstance

typeComputers[notEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for not equal {node}"
  return intTypeInstance

typeComputers[andExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for and {node}"
  return intTypeInstance

typeComputers[orExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for or {node}"
  return intTypeInstance

typeComputers[orderExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for order {node}"
  return intTypeInstance

# unary expressions
typeComputers[negateExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for negate {node}"
  return intTypeInstance

typeComputers[notExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for not {node}"
  return intTypeInstance

# calls
typeComputers[callClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for call {node}"
  defer:
    debugf"result {result} for {node}"

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return voidTypeInstance

  var funcType: AstNode
  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return voidTypeInstance

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return voidTypeInstance

      funcType = ctx.computeType(funcDefNode)

    else: # not a const decl, so call indirect
      funcType = ctx.computeType(funcExprNode)

  else: # not a node reference
    funcType = ctx.computeType(funcExprNode)

  if funcType.class != IdFunctionType:
    log lvlError, fmt"Function type expected, got {funcType}"
    return voidTypeInstance

  if funcType.firstChild(IdFunctionTypeReturnType).getSome(returnType):
    return returnType

  return voidTypeInstance

typeComputers[appendStringExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for append string {node}"
  return voidTypeInstance

typeComputers[printExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for print {node}"
  return voidTypeInstance

typeComputers[buildExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for build {node}"
  return stringTypeInstance

typeComputers[structMemberDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for struct member definition {node}"

  if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
    return ctx.computeType(typeNode)

  return voidTypeInstance

typeComputers[structDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for struct definition {node}"

  return node

  # var structType = newAstNode(structTypeClass)

  # for _, c in node.children(IdStructDefinitionMembers):
  #   if c.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
  #     # todo: This needs computeValue in the future since the type of a type is 'type', and the value is 'int' or 'string' etc.
  #     var typ = ctx.computeType(typeNode)
  #     if typ.isNil:
  #       # addDiagnostic(typeNode, "Could not compute type for parameter")
  #       continue
  #     structType.add(IdStructTypeMemberTypes, typ)
  #   else:
  #     echo "no type node found for struct member definition"
  #     ctx.dependOn(c)

  # # todo: this shouldn't set the model
  # structType.model = node.model
  # structType.forEach2 n:
  #   n.model = node.model

  # return structType

typeComputers[structMemberAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for struct member access {node}"
  if node.resolveReference(IdStructMemberAccessMember).getSome(targetNode):
    return ctx.computeType(targetNode)

  return voidTypeInstance

typeComputers[structMemberDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute scope for struct member definition {node}"

  if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
    return ctx.computeType(typeNode)

  return voidTypeInstance

# scope
scopeComputers[structMemberAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for struct member access {node}"

  let valueNode = node.firstChild(IdStructMemberAccessValue).getOr:
    return @[]

  let valueType = ctx.computeType(valueNode)
  if valueType.class != IdStructDefinition:
    return @[]

  return valueType.children(IdStructDefinitionMembers)

let baseLanguage* = newLanguage(IdBaseLanguage, @[
  namedInterface, declarationInterface,

  # typeClass,
  stringTypeClass, intTypeClass, voidTypeClass, functionTypeClass, structTypeClass,

  expressionClass, binaryExpressionClass, unaryExpressionClass, emptyLineClass,
  numberLiteralClass, stringLiteralClass, boolLiteralClass, nodeReferenceClass, emptyClass, constDeclClass, letDeclClass, varDeclClass, nodeListClass, blockClass, callClass, thenCaseClass, ifClass, whileClass,
  parameterDeclClass, functionDefinitionClass, assignmentClass,
  breakClass, continueClass, returnClass,
  addExpressionClass, subExpressionClass, mulExpressionClass, divExpressionClass, modExpressionClass,
  lessExpressionClass, lessEqualExpressionClass, greaterExpressionClass, greaterEqualExpressionClass, equalExpressionClass, notEqualExpressionClass, andExpressionClass, orExpressionClass, orderExpressionClass,
  negateExpressionClass, notExpressionClass,
  appendStringExpressionClass, printExpressionClass, buildExpressionClass,

  structDefinitionClass, structMemberDefinitionClass, structMemberAccessClass,
], builder, typeComputers, scopeComputers)

let baseModel* = block:
  var model = newModel(newId().ModelId)
  model.addLanguage(baseLanguage)
  model.addRootNode(intTypeInstance)
  model.addRootNode(stringTypeInstance)
  model.addRootNode(voidTypeInstance)

  model

# print baseLanguage
