import std/[tables, strformat]
import id, ast_ids, util, custom_logger
import model, cells, model_state
import ui/node

logCategory "base-language"

let expressionClass* = newNodeClass(IdExpression, "Expression", isAbstract=true)
# let typeClass* = newNodeClass(IdType, "Type", base=expressionClass)

let metaTypeClass* = newNodeClass(IdType, "Type", alias="type", base=expressionClass)
let stringTypeClass* = newNodeClass(IdString, "StringType", alias="string", base=expressionClass)
let intTypeClass* = newNodeClass(IdInt, "IntType", alias="int", base=expressionClass)
let voidTypeClass* = newNodeClass(IdVoid, "VoidType", alias="void", base=expressionClass)
let functionTypeClass* = newNodeClass(IdFunctionType, "FunctionType", base=expressionClass,
  children=[
    NodeChildDescription(id: IdFunctionTypeReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdFunctionTypeParameterTypes, role: "parameterTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore)])
let structTypeClass* = newNodeClass(IdStructType, "StructType", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStructTypeMemberTypes, role: "memberTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore)])
let pointerTypeClass* = newNodeClass(IdPointerType, "PointerType", alias="ptr", base=expressionClass,
  children=[
    NodeChildDescription(id: IdPointerTypeTarget, role: "target", class: expressionClass.id, count: ChildCount.One)])

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

let addressOfClass* = newNodeClass(IdAddressOf, "AddressOf", alias="addr", base=expressionClass,
  children=[
    NodeChildDescription(id: IdAddressOfValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let derefClass* = newNodeClass(IdDeref, "Deref", alias="deref", base=expressionClass,
  children=[
    NodeChildDescription(id: IdDerefValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let arrayAccessClass* = newNodeClass(IdArrayAccess, "ArrayAccess", alias="[]", base=expressionClass,
  children=[
    NodeChildDescription(id: IdArrayAccessValue, role: "value", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdArrayAccessIndex, role: "index", class: expressionClass.id, count: ChildCount.One)])

let allocateClass* = newNodeClass(IdAllocate, "Allocate", alias="alloc", base=expressionClass,
  children=[
    NodeChildDescription(id: IdAllocateType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdAllocateCount, role: "count", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

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

let parameterDeclClass* = newNodeClass(IdParameterDecl, "ParameterDecl", alias="param", interfaces=[declarationInterface], substitutionProperty=IdINamedName.some,
  children=[
    NodeChildDescription(id: IdParameterDeclType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdParameterDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let functionDefinitionClass* = newNodeClass(IdFunctionDefinition, "FunctionDefinition", alias="fn", base=expressionClass,
  children=[
    NodeChildDescription(id: IdFunctionDefinitionParameters, role: "parameters", class: parameterDeclClass.id, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdFunctionDefinitionReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdFunctionDefinitionBody, role: "body", class: expressionClass.id, count: ChildCount.One)])

let structMemberDefinitionClass* = newNodeClass(IdStructMemberDefinition, "StructMemberDefinition", alias="member", interfaces=[declarationInterface], substitutionProperty=IdINamedName.some,
  children=[
    NodeChildDescription(id: IdStructMemberDefinitionType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdStructMemberDefinitionValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let structParameterClass* = newNodeClass(IdStructParameter, "StructParameter", alias="param", interfaces=[declarationInterface], substitutionProperty=IdINamedName.some,
  children=[
    NodeChildDescription(id: IdStructParameterType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdStructParameterValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let structDefinitionClass* = newNodeClass(IdStructDefinition, "StructDefinition", alias="struct", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStructDefinitionParameter, role: "params", class: structParameterClass.id, count: ChildCount.ZeroOrMore),
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
    cell.add builder.buildChildren(map, node, IdNodeListChildren, &{LayoutVertical})
  return cell

builder.addBuilderFor blockClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutVertical}, flags: &{IndentChildren, OnNewLine})
  cell.nodeFactory = proc(): AstNode =
    return newAstNode(emptyLineClass)
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, IdBlockChildren, &{LayoutVertical})
  return cell

builder.addBuilderFor constDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdConstDeclType)

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
    cell.add builder.buildChildren(map, node, IdAssignmentTarget, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdAssignmentValue, &{LayoutHorizontal})
  return cell

builder.addBuilderFor parameterDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdParameterDeclValue)

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

    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdStructMemberDefinitionType, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdStructMemberDefinitionValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor structParameterClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add PropertyCell(node: node, property: IdINamedName)
    cell.add ConstantCell(node: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdStructParameterType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "<type>")

    cell.add ConstantCell(node: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdStructParameterValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "<?>")
  return cell

builder.addBuilderFor structDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: node, text: "struct", themeForegroundColors: @["keyword"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdStructDefinitionParameter, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: "<params>"

    cell.add ConstantCell(node: node, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdStructDefinitionMembers, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
        placeholder: "..."

    let hasChildren = node.childCount(IdStructDefinitionMembers) > 0
    cell.add ConstantCell(node: node, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: hasChildren ?? OnNewLine)

  return cell

builder.addBuilderFor structMemberAccessClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
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

builder.addBuilderFor pointerTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: node, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdPointerTypeTarget, &{LayoutHorizontal})
  return cell

builder.addBuilderFor addressOfClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: node, text: "addr", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdAddressOfValue, &{LayoutHorizontal})
  return cell

builder.addBuilderFor derefClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: node, text: "deref", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdDerefValue, &{LayoutHorizontal})
  return cell

builder.addBuilderFor IdArrayAccess, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, IdArrayAccessValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "[", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdArrayAccessIndex, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "]", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor IdAllocate, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: node, text: "alloc", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdAllocateType, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: ",", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, IdAllocateCount, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "1")
  return cell

builder.addBuilderFor callClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =

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
    cell.add builder.buildChildren(map, node, IdBinaryExpressionLeft, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: "------", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdBinaryExpressionRight, &{LayoutHorizontal})
  return cell

builder.addBuilderFor unaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add AliasCell(node: node, style: CellStyle(noSpaceRight: true), disableEditing: true)
    cell.add builder.buildChildren(map, node, IdUnaryExpressionChild, &{LayoutHorizontal})
  return cell

builder.addBuilderFor metaTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
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

    cell.add AliasCell(node: node, disableEditing: true)
    cell.add ConstantCell(node: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, IdBuildArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: node, role: role, shadowText: "")

    cell.add ConstantCell(node: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()

let metaTypeInstance* = newAstNode(metaTypeClass)
let stringTypeInstance* = newAstNode(stringTypeClass)
let intTypeInstance* = newAstNode(intTypeClass)
let voidTypeInstance* = newAstNode(voidTypeClass)

# todo: those should technically return something like metaTypeInstance which needs a new metaTypeClass
# and the valueComputer should return the type instance
typeComputers[metaTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for meta type literal {node}"
  return metaTypeInstance
typeComputers[stringTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for string type literal {node}"
  return metaTypeInstance
typeComputers[intTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for int type literal {node}"
  return metaTypeInstance
typeComputers[voidTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for void type literal {node}"
  return metaTypeInstance
typeComputers[pointerTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for pointer type {node}"
  return metaTypeInstance

valueComputers[metaTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for meta type literal {node}"
  return metaTypeInstance
valueComputers[stringTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for string type literal {node}"
  return stringTypeInstance
valueComputers[intTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for int type literal {node}"
  return intTypeInstance
valueComputers[voidTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for void type literal {node}"
  return voidTypeInstance
valueComputers[pointerTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for pointer type {node}"

  if node.firstChild(IdPointerTypeTarget).getSome(targetTypeNode):
    let targetType = ctx.getValue(targetTypeNode)
    var typ = newAstNode(pointerTypeClass)
    typ.add(IdPointerTypeTarget, targetType)
    typ.model = node.model
    typ.forEach2 n:
      n.model = node.model
    return typ

  return node

# base expression
typeComputers[expressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for base expression {node}"
  return voidTypeInstance

valueComputers[expressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for base expression {node}"
  return nil

# literals
typeComputers[stringLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for string literal {node}"
  return stringTypeInstance

valueComputers[stringLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for string literal {node}"
  return node

typeComputers[numberLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for number literal {node}"
  return intTypeInstance

valueComputers[numberLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for number literal {node}"
  return node

typeComputers[boolLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for bool literal {node}"
  return intTypeInstance

valueComputers[boolLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for bool literal {node}"
  return node

# declarations
typeComputers[letDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for let decl {node}"
  if node.firstChild(IdLetDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdLetDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

typeComputers[varDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for var decl {node}"
  if node.firstChild(IdVarDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdVarDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

typeComputers[constDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for const decl {node}"
  if node.firstChild(IdConstDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdConstDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

valueComputers[constDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for const decl {node}"
  if node.firstChild(IdConstDeclValue).getSome(valueNode):
    return ctx.getValue(valueNode)
  return voidTypeInstance

typeComputers[parameterDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for const decl {node}"
  if node.firstChild(IdParameterDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdParameterDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

# control flow
typeComputers[whileClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for while loop {node}"
  return voidTypeInstance

typeComputers[thenCaseClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for then case {node}"
  if node.firstChild(IdThenCaseBody).getSome(body):
    return ctx.computeType(body)
  return voidTypeInstance

typeComputers[ifClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for if expr {node}"

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
  # debugf"compute type for function definition {node}"
  var returnType = voidTypeInstance

  if node.firstChild(IdFunctionDefinitionReturnType).getSome(returnTypeNode):
    returnType = ctx.getValue(returnTypeNode)

  var functionType = newAstNode(functionTypeClass)
  functionType.add(IdFunctionTypeReturnType, returnType)

  for _, c in node.children(IdFunctionDefinitionParameters):
    if c.firstChild(IdParameterDeclType).getSome(paramTypeNode):
      # todo: This needs computeValue in the future since the type of a type is 'type', and the value is 'int' or 'string' etc.
      var parameterType = ctx.getValue(paramTypeNode)
      if parameterType.isNil:
        # addDiagnostic(paramTypeNode, "Could not compute type for parameter")
        continue
      functionType.add(IdFunctionTypeParameterTypes, parameterType)

  # todo: this shouldn't set the model
  functionType.model = node.model
  functionType.forEach2 n:
    n.model = node.model

  # debugf"computed function type: {`$`(functionType, true)}"

  return functionType

typeComputers[assignmentClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for assignment {node}"
  return voidTypeInstance

typeComputers[emptyClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for empty {node}"
  return voidTypeInstance

typeComputers[nodeListClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for node list {node}"

  if node.firstChild(IdNodeListChildren).getSome(childNode):
    return ctx.computeType(childNode)

  return voidTypeInstance

typeComputers[blockClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for block {node}"

  if node.lastChild(IdBlockChildren).getSome(childNode):
    return ctx.computeType(childNode)

  return voidTypeInstance

typeComputers[nodeReferenceClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for node reference {node}"
  if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
    return ctx.computeType(targetNode)
  return voidTypeInstance

valueComputers[nodeReferenceClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for node reference {node}"
  if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
    return ctx.getValue(targetNode)
  return nil

typeComputers[breakClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for break {node}"
  return voidTypeInstance

typeComputers[continueClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for continue {node}"
  return voidTypeInstance

typeComputers[returnClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for return {node}"
  return voidTypeInstance

# binary expressions
typeComputers[addExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for add {node}"
  return intTypeInstance

typeComputers[subExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for sub {node}"
  return intTypeInstance

typeComputers[mulExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for mul {node}"
  return intTypeInstance

typeComputers[divExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for div {node}"
  return intTypeInstance

typeComputers[modExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for mod {node}"
  return intTypeInstance

typeComputers[lessExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for less {node}"
  return intTypeInstance

typeComputers[lessEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for less equal {node}"
  return intTypeInstance

typeComputers[greaterExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for greater {node}"
  return intTypeInstance

typeComputers[greaterEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for greater equal {node}"
  return intTypeInstance

typeComputers[equalExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for equal {node}"
  return intTypeInstance

typeComputers[notEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for not equal {node}"
  return intTypeInstance

typeComputers[andExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for and {node}"
  return intTypeInstance

typeComputers[orExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for or {node}"
  return intTypeInstance

typeComputers[orderExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for order {node}"
  return intTypeInstance

# unary expressions
typeComputers[negateExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for negate {node}"
  return intTypeInstance

typeComputers[notExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for not {node}"
  return intTypeInstance

# calls
typeComputers[callClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for call {node}"
  # defer:
  #   debugf"result {result} for {node}"

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return voidTypeInstance

  var targetType: AstNode
  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return voidTypeInstance

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return voidTypeInstance

      targetType = ctx.computeType(funcDefNode)

    else: # not a const decl, so call indirect
      targetType = ctx.computeType(funcExprNode)

  else: # not a node reference
    targetType = ctx.computeType(funcExprNode)

  if targetType.class == IdFunctionType:
    if targetType.firstChild(IdFunctionTypeReturnType).getSome(returnType):
      return returnType

    log lvlError, fmt"Function type expected, got {targetType}"
    return voidTypeInstance

  if targetType.class == IdType:
    return metaTypeInstance

  return voidTypeInstance

# calls
valueComputers[callClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for call {node}"
  # defer:
  #   debugf"result {result} for {node}"

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return nil

  var targetType: AstNode
  var targetValue: AstNode
  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return nil

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return nil

      targetType = ctx.computeType(funcDefNode)
      targetValue = ctx.getValue(funcDefNode)

    else: # not a const decl, so call indirect
      targetType = ctx.computeType(funcExprNode)
      targetValue = ctx.getValue(funcExprNode)

  else: # not a node reference
    targetType = ctx.computeType(funcExprNode)
    targetValue = ctx.getValue(funcExprNode)

  if targetType.class == IdFunctionType:
    return nil

  if targetType.class == IdType and targetValue.class == IdStructDefinition:
    var parameters: seq[AstNode]
    for _, arg in node.children(IdCallArguments):
      parameters.add ctx.getValue(arg).cloneAndMapIds()

    if parameters.len != targetValue.childCount(IdStructDefinitionParameter):
      return voidTypeInstance

    var concreteType = targetValue.cloneAndMapIds()

    concreteType.references.add (IdStructTypeGenericBase, targetValue.id)

    for i, param in concreteType.children(IdStructDefinitionParameter):
      param.add(IdStructParameterValue, parameters[i])

    for i, member in concreteType.children(IdStructDefinitionMembers):
      # debugf"link member {member} to {targetValue.children(IdStructDefinitionMembers)[i].id}"
      member.references.add (IdStructTypeGenericMember, targetValue.children(IdStructDefinitionMembers)[i].id)

    # todo: this isn't very nice. When do we remove the temporary node?
    node.model.addTempNode(concreteType)
    ctx.ModelComputationContext.state.insertNode(concreteType)

    # debugf"generic type {`$`(targetValue, true)}"
    # debugf"concrete type {`$`(concreteType, true)}"
    return concreteType

  return nil

typeComputers[appendStringExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for append string {node}"
  return voidTypeInstance

typeComputers[printExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for print {node}"
  return voidTypeInstance

typeComputers[buildExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for build {node}"
  return stringTypeInstance

typeComputers[structParameterClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for struct parameter {node}"

  if node.firstChild(IdStructParameterType).getSome(typeNode):
    return ctx.getValue(typeNode)

  return voidTypeInstance

valueComputers[structParameterClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for struct parameter {node}"

  if node.firstChild(IdStructParameterValue).getSome(valueNode):
    return ctx.getValue(valueNode)

  return nil

typeComputers[structMemberDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for struct member definition {node}"

  if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
    return ctx.getValue(typeNode)

  return voidTypeInstance

typeComputers[structDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for struct definition {node}"

  return metaTypeInstance

valueComputers[structDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for struct definition {node}"

  return node

typeComputers[structMemberAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for struct member access {node}"

  let memberNode = node.resolveReference(IdStructMemberAccessMember).getOr:
    return voidTypeInstance

  let valueNode = node.firstChild(IdStructMemberAccessValue).getOr:
    return voidTypeInstance

  let structType = ctx.computeType(valueNode)
  # echo structType
  var isGeneric = structType.hasReference(IdStructTypeGenericBase)

  if isGeneric:
    var genericInstanceMemberNode: AstNode = nil
    for _, member in structType.children(IdStructDefinitionMembers):
      let originalMember = member.reference(IdStructTypeGenericMember)
      # debugf"originalMember: {originalMember}, target: {memberNode.id}"
      if memberNode.id == originalMember:
        genericInstanceMemberNode = member
        break

    if genericInstanceMemberNode.isNil:
      return voidTypeInstance

    return ctx.computeType(genericInstanceMemberNode)

  else:
    return ctx.computeType(memberNode)

typeComputers[structMemberDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute scope for struct member definition {node}"

  if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
    return ctx.getValue(typeNode)

  return voidTypeInstance

typeComputers[IdAllocate] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute scope for allocate {node}"

  if node.firstChild(IdAllocateType).getSome(typeNode):
    let targetType = ctx.getValue(typeNode)
    var typ = newAstNode(pointerTypeClass)
    typ.add(IdPointerTypeTarget, targetType)
    typ.model = node.model
    typ.forEach2 n:
      n.model = node.model
    return typ

  return voidTypeInstance

typeComputers[IdAddressOf] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute scope for address of {node}"

  if node.firstChild(IdAddressOfValue).getSome(valueNode):
    let targetType = ctx.computeType(valueNode)
    var typ = newAstNode(pointerTypeClass)
    typ.add(IdPointerTypeTarget, targetType)
    typ.model = node.model
    typ.forEach2 n:
      n.model = node.model
    return typ

  return voidTypeInstance

typeComputers[IdDeref] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute scope for deref {node}"

  if node.firstChild(IdDerefValue).getSome(typeNode):
    let pointerType = ctx.computeType(typeNode)
    if pointerType.class == IdPointerType and pointerType.firstChild(IdPointerTypeTarget).getSome(targetType):
      return targetType

  return voidTypeInstance

typeComputers[IdArrayAccess] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute scope for deref {node}"

  if node.firstChild(IdArrayAccessValue).getSome(typeNode):
    let pointerType = ctx.computeType(typeNode)
    if pointerType.class == IdPointerType and pointerType.firstChild(IdPointerTypeTarget).getSome(targetType):
      return targetType

  return voidTypeInstance

# scope
scopeComputers[structMemberAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for struct member access {node}"

  let valueNode = node.firstChild(IdStructMemberAccessValue).getOr:
    return @[]

  let valueType = ctx.computeType(valueNode)
  if valueType.class != IdStructDefinition:
    return @[]

  let genericType = valueType.reference(IdStructTypeGenericBase)
  if genericType.isSome:
    if node.model.resolveReference(genericType).getSome(genericTypeNode):
      return genericTypeNode.children(IdStructDefinitionMembers)
    return @[]

  return valueType.children(IdStructDefinitionMembers)

proc computeDefaultScope(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  var nodes: seq[AstNode] = @[]

  var prev = node
  var current = node.parent
  while current.isNotNil:
    ctx.dependOn(current)

    if current.class == IdFunctionDefinition:
      for _, c in current.children(IdFunctionDefinitionParameters):
        ctx.dependOn(c)
        nodes.add c

    if current.class == IdStructDefinition:
      for _, c in current.children(IdStructDefinitionParameter):
        ctx.dependOn(c)
        nodes.add c
      for _, c in current.children(IdStructDefinitionMembers):
        ctx.dependOn(c)
        nodes.add c

    if current.class == IdBlock:
      for _, c in current.children(IdBlockChildren):
        if c == prev:
          break
        ctx.dependOn(c)
        nodes.add c

    if current.class == IdNodeList and current.parent.isNil:
      for _, c in current.children(IdNodeListChildren):
        ctx.dependOn(c)
        nodes.add c

    prev = current
    current = current.parent

  return nodes

scopeComputers[IdExpression] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for base expression {node}"
  return ctx.computeDefaultScope(node)

scopeComputers[IdStructMemberDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for struct member {node}"
  return ctx.computeDefaultScope(node)

scopeComputers[IdStructParameter] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for struct parameter {node}"
  return ctx.computeDefaultScope(node)

scopeComputers[IdParameterDecl] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for parameter {node}"
  return ctx.computeDefaultScope(node)

let baseLanguage* = newLanguage(IdBaseLanguage, @[
  namedInterface, declarationInterface,

  # typeClass,
  metaTypeClass, stringTypeClass, intTypeClass, voidTypeClass, functionTypeClass, structTypeClass, pointerTypeClass,

  expressionClass, binaryExpressionClass, unaryExpressionClass, emptyLineClass,
  numberLiteralClass, stringLiteralClass, boolLiteralClass, nodeReferenceClass, emptyClass, constDeclClass, letDeclClass, varDeclClass, nodeListClass, blockClass, callClass, thenCaseClass, ifClass, whileClass,
  parameterDeclClass, functionDefinitionClass, assignmentClass,
  breakClass, continueClass, returnClass,
  addExpressionClass, subExpressionClass, mulExpressionClass, divExpressionClass, modExpressionClass,
  lessExpressionClass, lessEqualExpressionClass, greaterExpressionClass, greaterEqualExpressionClass, equalExpressionClass, notEqualExpressionClass, andExpressionClass, orExpressionClass, orderExpressionClass,
  negateExpressionClass, notExpressionClass,
  appendStringExpressionClass, printExpressionClass, buildExpressionClass, allocateClass,

  structDefinitionClass, structMemberDefinitionClass, structParameterClass, structMemberAccessClass,
  addressOfClass, derefClass, arrayAccessClass,
], builder, typeComputers, valueComputers, scopeComputers)

let baseModel* = block:
  var model = newModel(newId().ModelId)
  model.addLanguage(baseLanguage)
  model.addRootNode(intTypeInstance)
  model.addRootNode(stringTypeInstance)
  model.addRootNode(voidTypeInstance)
  model.addRootNode(metaTypeInstance)

  model

# print baseLanguage
