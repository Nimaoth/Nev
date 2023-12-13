import std/[tables, strformat]
import id, ast_ids, util, custom_logger
import model, cells, model_state, query_system
import ui/node

export id, ast_ids

logCategory "base-language"

proc instantiateStruct*(ctx: ModelComputationContextBase, genericStruct: AstNode, arguments: openArray[AstNode]): AstNode

proc typesMatch(ctx: ModelComputationContextBase, expected: AstNode, actual: AstNode): bool =
  if expected.isNil or actual.isNil:
    return false

  # debug &"typesMatch: {expected} <> {actual}"
  # defer:
  #   debug &"-> {result}"

  let expected = expected.resolveOriginal(true).get expected
  let actual = actual.resolveOriginal(true).get actual

  if expected == actual:
    return true
  if expected.class != actual.class:
    return false

  if expected.class == IdPointerType:
    # debug &"try compare pointer target types {expected} <> {actual}"
    if expected.resolveReference(IdPointerTypeTarget).getSome(expectedTarget) and actual.resolveReference(IdPointerTypeTarget).getSome(actualTarget):
      # debug &"compare pointer target types {expectedTarget} <> {actualTarget}"
      return ctx.typesMatch(expectedTarget, actualTarget)

  if expected.class == IdFunctionType:
    if expected.firstChild(IdFunctionTypeReturnType).getSome(expectedReturnType) and actual.firstChild(IdFunctionTypeReturnType).getSome(actualReturnType):
      if not ctx.typesMatch(expectedReturnType, actualReturnType):
        return false

    let expectedChildren = expected.children(IdFunctionTypeParameterTypes)
    let actualChildren = actual.children(IdFunctionTypeParameterTypes)
    if expectedChildren.len != actualChildren.len:
      return false

    for i in 0..expectedChildren.high:
      if not ctx.typesMatch(expectedChildren[i], actualChildren[i]):
        return false

    return true

  if [IdInt32, IdUInt32, IdInt64, IdUInt64, IdFloat32, IdFloat64, IdChar, IdString, IdVoid].contains(expected.class):
    return true

  return false

proc validateNodeType(ctx: ModelComputationContextBase, node: AstNode, expectedType: AstNode): bool =
  let typ = ctx.computeType(node)
  if not ctx.typesMatch(expectedType, typ):
    ctx.addDiagnostic(node, fmt"Expected {expectedType}, got {typ}")
    return false
  return true

proc validateHasChild(ctx: ModelComputationContextBase, node: AstNode, role: RoleId): bool =
  if not node.firstChild(role).isSome:
    ctx.addDiagnostic(node, fmt"Expected child for role {role}")
    return false
  return true

proc validateChildType(ctx: ModelComputationContextBase, node: AstNode, role: RoleId, expectedType: AstNode): bool =
  if node.firstChild(role).getSome(child):
    return ctx.validateNodeType(child, expectedType)
  return true

let expressionClass* = newNodeClass(IdExpression, "Expression", isAbstract=true)
# let typeClass* = newNodeClass(IdType, "Type", base=expressionClass)

let metaTypeClass* = newNodeClass(IdType, "Type", alias="type", base=expressionClass)
let stringTypeClass* = newNodeClass(IdString, "StringType", alias="string", base=expressionClass)
let int32TypeClass* = newNodeClass(IdInt32, "Int32Type", alias="i32", base=expressionClass)
let uint32TypeClass* = newNodeClass(IdUInt32, "UInt32Type", alias="u32", base=expressionClass)
let int64TypeClass* = newNodeClass(IdInt64, "Int64Type", alias="i64", base=expressionClass)
let uint64TypeClass* = newNodeClass(IdUInt64, "UInt64Type", alias="u64", base=expressionClass)
let float32TypeClass* = newNodeClass(IdFloat32, "Float32Type", alias="f32", base=expressionClass)
let float64TypeClass* = newNodeClass(IdFloat64, "Float64Type", alias="f64", base=expressionClass)
let voidTypeClass* = newNodeClass(IdVoid, "VoidType", alias="void", base=expressionClass)
let charTypeClass * = newNodeClass(IdChar, "CharType", alias="char", base=expressionClass)
let functionTypeClass* = newNodeClass(IdFunctionType, "FunctionType", base=expressionClass,
  children=[
    NodeChildDescription(id: IdFunctionTypeParameterTypes, role: "parameterTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdFunctionTypeReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.One)])
let structTypeClass* = newNodeClass(IdStructType, "StructType", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStructTypeMemberTypes, role: "memberTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

let pointerTypeClass* = newNodeClass(IdPointerType, "PointerType", base=expressionClass,
  references=[
    NodeReferenceDescription(id: IdPointerTypeTarget, role: "target", class: expressionClass.id)])

let pointerTypeDeclClass* = newNodeClass(IdPointerTypeDecl, "PointerTypeDecl", alias="ptr", base=expressionClass,
  children=[
    NodeChildDescription(id: IdPointerTypeDeclTarget, role: "target", class: expressionClass.id, count: ChildCount.One)])

let namedInterface* = newNodeClass(IdINamed, "INamed", isAbstract=true, isInterface=true,
  properties=[PropertyDescription(id: IdINamedName, role: "name", typ: PropertyType.String)])

let declarationInterface* = newNodeClass(IdIDeclaration, "IDeclaration", isAbstract=true, isInterface=true, base=namedInterface)

let castClass* = newNodeClass(IdCast, "Cast", alias="cast", base=expressionClass, children=[
    NodeChildDescription(id: IdCastType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdCastValue, role: "value", class: expressionClass.id, count: ChildCount.One),
  ])

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
let nodeReferenceClass* = newNodeClass(IdNodeReference, "NodeReference", alias="ref", base=expressionClass, substitutionReference=IdNodeReferenceTarget.some, references=[NodeReferenceDescription(id: IdNodeReferenceTarget, role: "target", class: declarationInterface.id)])
let numberLiteralClass* = newNodeClass(IdIntegerLiteral, "IntegerLiteral", alias="number", base=expressionClass, properties=[PropertyDescription(id: IdIntegerLiteralValue, role: "value", typ: PropertyType.Int)], substitutionProperty=IdIntegerLiteralValue.some)
let stringLiteralClass* = newNodeClass(IdStringLiteral, "StringLiteral", alias="''", base=expressionClass, properties=[PropertyDescription(id: IdStringLiteralValue, role: "value", typ: PropertyType.String)])
let boolLiteralClass* = newNodeClass(IdBoolLiteral, "BoolLiteral", alias="bool", base=expressionClass, properties=[PropertyDescription(id: IdBoolLiteralValue, role: "value", typ: PropertyType.Bool)])

let addressOfClass* = newNodeClass(IdAddressOf, "AddressOf", alias="addr", base=expressionClass,
  children=[
    NodeChildDescription(id: IdAddressOfValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let derefClass* = newNodeClass(IdDeref, "Deref", alias="deref", base=expressionClass,
  children=[
    NodeChildDescription(id: IdDerefValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let stringGetPointerClass* = newNodeClass(IdStringGetPointer, "StringGetPointer", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStringGetPointerValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let stringGetLengthClass* = newNodeClass(IdStringGetLength, "StringGetLength", base=expressionClass,
  children=[
    NodeChildDescription(id: IdStringGetLengthValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let arrayAccessClass* = newNodeClass(IdArrayAccess, "ArrayAccess", alias="[]", base=expressionClass,
  children=[
    NodeChildDescription(id: IdArrayAccessValue, role: "value", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdArrayAccessIndex, role: "index", class: expressionClass.id, count: ChildCount.One)])

let allocateClass* = newNodeClass(IdAllocate, "Allocate", alias="alloc", base=expressionClass,
  children=[
    NodeChildDescription(id: IdAllocateType, role: "type", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdAllocateCount, role: "count", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

let genericTypeClass* = newNodeClass(IdGenericType, "GenericType", alias="generic", base=expressionClass, interfaces=[declarationInterface],
  references=[
    NodeReferenceDescription(id: IdGenericTypeValue, role: "value", class: expressionClass.id)])

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

let nodeListClass* = newNodeClass(IdNodeList, "NodeList", canBeRoot=true,
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

let loopInterface* = newNodeClass(IdILoop, "LoopInterface", isInterface=true)

let whileClass* = newNodeClass(IdWhileExpression, "WhileExpression", alias="while", base=expressionClass, interfaces=[loopInterface], children=[
    NodeChildDescription(id: IdWhileExpressionCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdWhileExpressionBody, role: "body", class: expressionClass.id, count: ChildCount.One),
  ])

let forLoopClass* = newNodeClass(IdForLoop, "ForLoop", alias="for", base=expressionClass, interfaces=[loopInterface], children=[
    NodeChildDescription(id: IdForLoopVariable, role: "variable", class: letDeclClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdForLoopStart, role: "start", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdForLoopEnd, role: "end", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdForLoopBody, role: "body", class: expressionClass.id, count: ChildCount.One),
  ])

let breakClass* = newNodeClass(IdBreakExpression, "BreakExpression", alias="break", base=expressionClass)
let continueClass* = newNodeClass(IdContinueExpression, "ContinueExpression", alias="continue", base=expressionClass)
let returnClass* = newNodeClass(IdReturnExpression, "ReturnExpression", alias="return", base=expressionClass,
  children=[
    NodeChildDescription(id: IdReturnExpressionValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

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
  references=[NodeReferenceDescription(id: IdStructMemberAccessMember, role: "member", class: IdINamed)],
  children=[NodeChildDescription(id: IdStructMemberAccessValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

let assignmentClass* = newNodeClass(IdAssignment, "Assignment", alias="=", base=expressionClass, children=[
    NodeChildDescription(id: IdAssignmentTarget, role: "target", class: expressionClass.id, count: ChildCount.One),
    NodeChildDescription(id: IdAssignmentValue, role: "value", class: expressionClass.id, count: ChildCount.One),
  ])

var builder = newCellBuilder()

builder.addBuilderFor emptyLineClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node)
  return cell

builder.addBuilderFor emptyClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node)
  return cell

builder.addBuilderFor numberLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdIntegerLiteralValue, themeForegroundColors: @["constant.numeric"])
  return cell

builder.addBuilderFor boolLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdBoolLiteralValue, themeForegroundColors: @["constant.numeric"])
  return cell

builder.addBuilderFor stringLiteralClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "'", style: CellStyle(noSpaceRight: true), disableEditing: true, deleteImmediately: true, themeForegroundColors: @["punctuation.definition.string", "punctuation", "&editor.foreground"])
  cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdStringLiteralValue, themeForegroundColors: @["string"])
  cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "'", style: CellStyle(noSpaceLeft: true), disableEditing: true, deleteImmediately: true, themeForegroundColors: @["punctuation.definition.string", "punctuation", "&editor.foreground"])
  return cell

builder.addBuilderFor nodeListClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical})
  cell.nodeFactory = proc(): AstNode =
    return newAstNode(emptyLineClass)
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdNodeListChildren, &{LayoutVertical})
  return cell

builder.addBuilderFor blockClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical}, flags: &{IndentChildren, OnNewLine})
  cell.nodeFactory = proc(): AstNode =
    return newAstNode(emptyLineClass)
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdBlockChildren, &{LayoutVertical})
  return cell

builder.addBuilderFor genericTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "generic", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)

    if node.resolveReference(IdGenericTypeValue).isSome:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      # todo: build value cell
      # cell.add block:
      #   buildChildrenT(builder, map, node, owner, IdGenericTypeValue, &{LayoutHorizontal}, 0.CellFlags):
      #     placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")

  return cell

builder.addBuilderFor constDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdConstDeclType)

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "const", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", isVisible: isVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdConstDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdConstDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor letDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdLetDeclType)

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "let", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", isVisible: isVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdLetDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdLetDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor varDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isTypeVisible(node: AstNode): bool = node.hasChild(IdVarDeclType)
    proc isValueVisible(node: AstNode): bool = node.hasChild(IdVarDeclValue)

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "var", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", isVisible: isTypeVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdVarDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", isVisible: isValueVisible, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdVarDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor assignmentClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdAssignmentTarget, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdAssignmentValue, &{LayoutHorizontal})
  return cell

builder.addBuilderFor parameterDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdParameterDeclValue)

    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      builder.buildChildrenT(map, node, owner, IdParameterDeclType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", isVisible: isVisible, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdParameterDeclValue, &{LayoutHorizontal}, 0.CellFlags):
        visible: isVisible(node)
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor functionDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "fn", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdFunctionDefinitionParameters, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: owner ?? node, referenceNode: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: "..."

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "):", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      builder.buildChildrenT(map, node, owner, IdFunctionDefinitionReturnType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: "..."

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      builder.buildChildrenT(map, node, owner, IdFunctionDefinitionBody, &{LayoutVertical}, 0.CellFlags):
        placeholder: "..."

  return cell

builder.addBuilderFor structMemberDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc isVisible(node: AstNode): bool = node.hasChild(IdStructMemberDefinitionValue)

    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdStructMemberDefinitionType, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdStructMemberDefinitionValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
  return cell

builder.addBuilderFor structParameterClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdStructParameterType, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdStructParameterValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<?>")
  return cell

builder.addBuilderFor structDefinitionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "struct", themeForegroundColors: @["keyword"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdStructDefinitionParameter, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: owner ?? node, referenceNode: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: "<params>"

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdStructDefinitionMembers, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
        placeholder: "..."

    let hasChildren = node.childCount(IdStructDefinitionMembers) > 0
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: hasChildren ?? OnNewLine)

  return cell

builder.addBuilderFor structMemberAccessClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdStructMemberAccessValue, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: "..."

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ".", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight})

    cell.add block:
      if node.resolveReference(IdStructMemberAccessMember).getSome(targetNode):
        # var refCell = NodeReferenceCell(id: newId().CellId, node: owner ?? node, referenceNode: node, reference: IdStructMemberAccessMember, property: IdINamedName, disableEditing: true)
        PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])
      else:
        PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: IdStructMemberAccessMember, shadowText: "_")

  return cell

builder.addBuilderFor pointerTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true)
    # todo: build target cell
    # cell.add builder.buildChildren(map, node, owner, IdPointerTypeTarget, &{LayoutHorizontal})
  return cell

builder.addBuilderFor pointerTypeDeclClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdPointerTypeDeclTarget, &{LayoutHorizontal})
  return cell

builder.addBuilderFor addressOfClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdAddressOfValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ".addr", flags: &{NoSpaceLeft}, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor derefClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdDerefValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ".deref", flags: &{NoSpaceLeft}, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor castClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdCastValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "as", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdCastType, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation"], disableEditing: true)
  return cell

builder.addBuilderFor stringGetPointerClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdStringGetPointerValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor stringGetLengthClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdStringGetLengthValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "len", themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor IdArrayAccess, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdArrayAccessValue, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "[", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdArrayAccessIndex, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "]", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor IdAllocate, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "alloc", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdAllocateType, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ",", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add block:
      buildChildrenT(builder, map, node, owner, IdAllocateCount, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "1")
  return cell

builder.addBuilderFor callClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =

    cell.add builder.buildChildren(map, node, owner, IdCallFunction, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdCallArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: owner ?? node, referenceNode: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "")

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

builder.addBuilderFor thenCaseClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =

    if node.index == 0:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "if", themeForegroundColors: @["keyword"], disableEditing: true)
    else:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "elif", themeForegroundColors: @["keyword"], disableEditing: true, flags: &{OnNewLine})
    cell.add builder.buildChildren(map, node, owner, IdThenCaseCondition, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdThenCaseBody, &{LayoutHorizontal})

  return cell

builder.addBuilderFor ifClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal}, flags: &{DeleteWhenEmpty}, inline: true)
  cell.fillChildren = proc(map: NodeCellMap) =

    cell.add block:
      builder.buildChildren(map, node, owner, IdIfExpressionThenCase, &{LayoutVertical}, &{DeleteWhenEmpty})

    if node.childCount(IdIfExpressionElseCase) == 0:
      var flags = 0.CellFlags
      if node.childCount(IdIfExpressionThenCase) > 0:
        flags.incl OnNewLine
      cell.add PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: IdIfExpressionElseCase, shadowText: "<else>", flags: flags)
    else:
      for i, c in node.children(IdIfExpressionElseCase):
        if i == 0:
          cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "else", flags: &{OnNewLine}, themeForegroundColors: @["keyword"], disableEditing: true)
          cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
        cell.add builder.buildCell(map, c)

  return cell

builder.addBuilderFor whileClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "while", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdWhileExpressionCondition, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdWhileExpressionBody, &{LayoutHorizontal})

  return cell

builder.addBuilderFor forLoopClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    proc varDeclNameOnlyBuilder(builder: CellBuilder, node: AstNode, owner: AstNode): Cell = PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "for", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdForLoopVariable, &{LayoutHorizontal}, builderFunc=varDeclNameOnlyBuilder)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "in", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdForLoopStart, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "..<", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdForLoopEnd, &{LayoutHorizontal},
      placeholderFunc = proc(builder: CellBuilder, node: AstNode, owner: AstNode, role: RoleId, flags: CellFlags = 0.CellFlags): Cell =
        return PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, flags: flags, shadowText: "∞"))
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdForLoopBody, &{LayoutHorizontal})

  return cell

builder.addBuilderFor breakClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor continueClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["keyword"], disableEditing: true)
  return cell

builder.addBuilderFor returnClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdReturnExpressionValue, &{LayoutHorizontal})
  return cell

builder.addBuilderFor nodeReferenceClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
    if targetNode.nodeClass.isSubclassOf(IdINamed):
      return PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])

    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) =
      cell.add ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, text: "<", flags: &{NoSpaceRight}, themeForegroundColors: @["keyword"])
      cell.add buildReference(map, node, owner, IdNodeReferenceTarget, &{LayoutHorizontal})
      cell.add ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, text: ">", flags: &{NoSpaceLeft}, themeForegroundColors: @["keyword"])
    return cell
  else:
    return ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, text: $node.reference(IdNodeReferenceTarget))

# builder.addBuilderFor typeClass.id, idNone(), &{OnlyExactMatch}, proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
#   var cell = ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, shadowText: "<type>", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"])
  # return cell

builder.addBuilderFor expressionClass.id, idNone(), &{OnlyExactMatch}, proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node, shadowText: "<expr>", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"])
  return cell

builder.addBuilderFor binaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    let lowerPrecedence = node.parent.isNotNil and node.parent.nodeClass.precedence >= node.nodeClass.precedence

    if lowerPrecedence:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", flags: &{NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add builder.buildChildren(map, node, owner, IdBinaryExpressionLeft, &{LayoutHorizontal})
    cell.add AliasCell(node: owner ?? node, referenceNode: node, disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdBinaryExpressionRight, &{LayoutHorizontal})

    if lowerPrecedence:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

builder.addBuilderFor divExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical}, inline: true)
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add builder.buildChildren(map, node, owner, IdBinaryExpressionLeft, &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "------", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdBinaryExpressionRight, &{LayoutHorizontal})
  return cell

builder.addBuilderFor unaryExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add AliasCell(node: owner ?? node, referenceNode: node, style: CellStyle(noSpaceRight: true), disableEditing: true)
    cell.add builder.buildChildren(map, node, owner, IdUnaryExpressionChild, &{LayoutHorizontal})
  return cell

builder.addBuilderFor metaTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor stringTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor voidTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor int32TypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor uint32TypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor int64TypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor uint64TypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor float32TypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor float64TypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor charTypeClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = AliasCell(id: newId().CellId, node: owner ?? node, referenceNode: node, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)
  return cell

builder.addBuilderFor printExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =

    cell.add AliasCell(node: owner ?? node, referenceNode: node, disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdPrintArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: owner ?? node, referenceNode: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "")

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

builder.addBuilderFor buildExpressionClass.id, idNone(), proc(builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =

    cell.add AliasCell(node: owner ?? node, referenceNode: node, disableEditing: true)
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", style: CellStyle(noSpaceLeft: true, noSpaceRight: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    cell.add block:
      buildChildrenT(builder, map, node, owner, IdBuildArguments, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: owner ?? node, referenceNode: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "")

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ")", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

  return cell

var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

let metaTypeInstance* = newAstNode(metaTypeClass)
let stringTypeInstance* = newAstNode(stringTypeClass)
let int32TypeInstance* = newAstNode(int32TypeClass)
let uint32TypeInstance* = newAstNode(uint32TypeClass)
let int64TypeInstance* = newAstNode(int64TypeClass)
let uint64TypeInstance* = newAstNode(uint64TypeClass)
let float32TypeInstance* = newAstNode(float32TypeClass)
let float64TypeInstance* = newAstNode(float64TypeClass)
let voidTypeInstance* = newAstNode(voidTypeClass)
let charTypeInstance* = newAstNode(charTypeClass)

typeComputers[metaTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[stringTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[int32TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[uint32TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[int64TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[uint64TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[float32TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[float64TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[charTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[voidTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[pointerTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
typeComputers[pointerTypeDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance

valueComputers[metaTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = metaTypeInstance
valueComputers[stringTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = stringTypeInstance
valueComputers[int32TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = int32TypeInstance
valueComputers[uint32TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = uint32TypeInstance
valueComputers[int64TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = int64TypeInstance
valueComputers[uint64TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = uint64TypeInstance
valueComputers[float32TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = float32TypeInstance
valueComputers[float64TypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = float64TypeInstance
valueComputers[charTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = charTypeInstance
valueComputers[voidTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode = voidTypeInstance

valueComputers[pointerTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for pointer type {node}"
  return node

valueComputers[pointerTypeDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for pointer type {node}"

  if node.firstChild(IdPointerTypeDeclTarget).getSome(targetTypeNode):
    var typ = newAstNode(pointerTypeClass)
    if ctx.getValue(targetTypeNode).isNotNil(targetType):
      typ.setReference(IdPointerTypeTarget, targetType.id)

    node.model.addTempNode(typ)
    return typ

  return voidTypeInstance

validationComputers[pointerTypeDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate pointer type decl {node}"

  let targetTypeNode = node.firstChild(IdPointerTypeDeclTarget).getOr:
    ctx.addDiagnostic(node, "Pointer type must have a target type")
    return false

  let typ = ctx.computeType(targetTypeNode)
  if not ctx.typesMatch(metaTypeInstance, typ):
    ctx.addDiagnostic(node, fmt"Expected meta type, got {typ}")
    return false

  return true

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
  if node.property(IdIntegerLiteralValue).getSome(value):
    # if value.intValue.safeIntCast(uint64) > int64.high.uint64:
    #   return uint64TypeInstance
    if value.intValue < int32.low or value.intValue > int32.high:
      return int64TypeInstance
  return int32TypeInstance

valueComputers[numberLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for number literal {node}"
  return node

typeComputers[boolLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for bool literal {node}"
  return int32TypeInstance

valueComputers[boolLiteralClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for bool literal {node}"
  return node

typeComputers[emptyLineClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for empty line {node}"
  return voidTypeInstance

# declarations
typeComputers[genericTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for generic type {node}"
  return metaTypeInstance

valueComputers[genericTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for generic type {node}"
  if node.resolveReference(IdGenericTypeValue).getSome(valueNode):
    return ctx.getValue(valueNode)
  return node

validationComputers[genericTypeClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate generic type {node}"

  # if not ctx.validateChildType(node, IdGenericTypeValue, metaTypeInstance):
  #   return false

  return true

typeComputers[letDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for let decl {node}"
  if node.role == IdForLoopVariable:
    let forLoop = node.parent
    if forLoop.firstChild(IdForLoopStart).getSome(startNode):
      return ctx.computeType(startNode)
    if forLoop.firstChild(IdForLoopEnd).getSome(endNode):
      return ctx.computeType(endNode)
    return int32TypeInstance

  if node.firstChild(IdLetDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdLetDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

validationComputers[letDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate let decl {node}"

  if node.role == IdForLoopVariable:
    return true

  if not ctx.validateHasChild(node, IdLetDeclValue):
    return false

  if node.firstChild(IdLetDeclType).getSome(typeNode):
    if not ctx.validateNodeType(typeNode, metaTypeInstance):
      return false

    let expectedType = ctx.getValue(typeNode)
    if ctx.typesMatch(metaTypeInstance, expectedType):
      ctx.addDiagnostic(node, "Let decl can't be of type meta type")
      return false

    if not ctx.validateChildType(node, IdLetDeclValue, expectedType):
      return false

  else:
    let valueNode = node.firstChild(IdLetDeclValue).get
    let valueType = ctx.computeType(valueNode)
    if ctx.typesMatch(metaTypeInstance, valueType):
      ctx.addDiagnostic(node, "Let decl can't be of type meta type")
      return false

  return true

typeComputers[varDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for var decl {node}"
  if node.role == IdForLoopVariable:
    let forLoop = node.parent
    if forLoop.firstChild(IdForLoopStart).getSome(startNode):
      return ctx.computeType(startNode)
    if forLoop.firstChild(IdForLoopEnd).getSome(endNode):
      return ctx.computeType(endNode)
    return int32TypeInstance

  if node.firstChild(IdVarDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdVarDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

validationComputers[varDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate var decl {node}"

  if node.role == IdForLoopVariable:
    return true

  if node.firstChild(IdVarDeclType).getSome(typeNode):
    if not ctx.validateNodeType(typeNode, metaTypeInstance):
      return false

    let expectedType = ctx.getValue(typeNode)
    if ctx.typesMatch(metaTypeInstance, expectedType):
      ctx.addDiagnostic(node, "Var decl can't be of type meta type")
      return false

    if not ctx.validateChildType(node, IdVarDeclValue, expectedType):
      return false

  elif node.firstChild(IdVarDeclValue).getSome(valueNode):
    let valueType = ctx.computeType(valueNode)
    if ctx.typesMatch(metaTypeInstance, valueType):
      ctx.addDiagnostic(node, "Var decl can't be of type meta type")
      return false

  return true

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
  return nil

validationComputers[constDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate const decl {node}"

  if not ctx.validateHasChild(node, IdConstDeclValue):
    return false

  if node.firstChild(IdConstDeclType).getSome(typeNode):
    if not ctx.validateNodeType(typeNode, metaTypeInstance):
      return false

    let expectedType = ctx.getValue(typeNode)
    if not ctx.validateChildType(node, IdConstDeclValue, expectedType):
      return false

  let value = ctx.getValue(node.firstChild(IdConstDeclValue).get)
  if value.isNil:
    ctx.addDiagnostic(node, "Could not compute value for const decl")
    return false

  return true

typeComputers[parameterDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for parameter decl {node}"
  if node.firstChild(IdParameterDeclType).getSome(typeNode):
    return ctx.getValue(typeNode)
  if node.firstChild(IdParameterDeclValue).getSome(valueNode):
    return ctx.computeType(valueNode)
  return voidTypeInstance

valueComputers[parameterDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for parameter decl {node}"
  if node.firstChild(IdParameterDeclValue).getSome(valueNode):
    return ctx.getValue(valueNode)
  if node.firstChild(IdParameterDeclType).getSome(typeNode):
    let typ = ctx.getValue(typeNode)
    if typ.class == IdType:
      var genericType = newAstNode(genericTypeClass)
      let name = node.property(IdINamedName).get.stringValue
      genericType.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: name))
      node.model.addTempNode(genericType)
      return genericType

  return nil

validationComputers[parameterDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate parameter decl {node}"

  if node.firstChild(IdParameterDeclType).getSome(typeNode):
    if not ctx.validateNodeType(typeNode, metaTypeInstance):
      return false

    let expectedType = ctx.getValue(typeNode)

    if not ctx.validateChildType(node, IdParameterDeclValue, expectedType):
      return false

  return true

# control flow
typeComputers[whileClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for while loop {node}"
  return voidTypeInstance

validationComputers[whileClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate while {node}"

  if not ctx.validateHasChild(node, IdWhileExpressionCondition):
    return false

  if not ctx.validateChildType(node, IdWhileExpressionCondition, int32TypeInstance):
    return false

  return true

typeComputers[forLoopClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for for loop {node}"
  return voidTypeInstance

typeComputers[thenCaseClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for then case {node}"
  if node.firstChild(IdThenCaseBody).getSome(body):
    return ctx.computeType(body)
  return voidTypeInstance

validationComputers[thenCaseClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate then case {node}"

  if not ctx.validateHasChild(node, IdThenCaseCondition):
    return false

  if not ctx.validateChildType(node, IdThenCaseCondition, int32TypeInstance):
    return false

  return true

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
proc computeFunctionDefinitionType(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  var returnType = voidTypeInstance

  if node.firstChild(IdFunctionDefinitionReturnType).getSome(returnTypeNode):
    returnType = ctx.getValue(returnTypeNode)

  var functionType = newAstNode(functionTypeClass)

  if returnType.isNotNil:
    functionType.add(IdFunctionTypeReturnType, returnType)

  for _, c in node.children(IdFunctionDefinitionParameters):
    if c.firstChild(IdParameterDeclType).getSome(paramTypeNode):
      var parameterType = ctx.getValue(paramTypeNode)
      if parameterType.isNil:
        # addDiagnostic(paramTypeNode, "Could not compute type for parameter")
        continue
      functionType.add(IdFunctionTypeParameterTypes, parameterType)

  node.model.addTempNode(functionType)

  # debugf"computed function type: {`$`(functionType, true)}"

  return functionType

# function definition
typeComputers[functionDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for function definition {node}"
  # defer:
  #   debugf"-> {result}"

  if not node.hasChild(IdFunctionDefinitionBody):
    return metaTypeInstance

  return ctx.computeFunctionDefinitionType(node)

# function definition
valueComputers[functionDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute value for function definition {node}"
  # defer:
  #   debugf"-> {result}"

  if not node.hasChild(IdFunctionDefinitionBody):
    return ctx.computeFunctionDefinitionType(node)

  return node

typeComputers[assignmentClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for assignment {node}"
  return voidTypeInstance

validationComputers[assignmentClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate assignment {node}"

  if not ctx.validateHasChild(node, IdAssignmentTarget):
    return false
  if not ctx.validateHasChild(node, IdAssignmentValue):
    return false

  let targetType = ctx.computeType(node.firstChild(IdAssignmentTarget).get)
  let valueType = ctx.computeType(node.firstChild(IdAssignmentValue).get)

  if not ctx.typesMatch(targetType, valueType):
    ctx.addDiagnostic(node, fmt"Expected {targetType}, got {valueType}")
    return false

  return true

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

  # todo: maybe find better way to ignore empty line nodes
  var lastChild: AstNode = nil
  for _, child in node.children(IdBlockChildren):
    if child.class != IdEmptyLine:
      lastChild = child

  if lastChild.isNotNil:
    return ctx.computeType(lastChild)

  return voidTypeInstance

typeComputers[castClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for node reference {node}"
  if node.firstChild(IdCastType).getSome(typeNode):
    return ctx.getValue(typeNode)
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
  if node.reference(IdNodeReferenceTarget) != NodeId.default:
    log lvlError, fmt"Couldn't resolve reference {node}"
  return nil

validationComputers[nodeReferenceClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate node reference {node}"

  let targetNode = node.resolveReference(IdNodeReferenceTarget).getOr:
    ctx.addDiagnostic(node, "Could not resolve node reference")
    ctx.dependOnCurrentRevision()
    return false

  let scope = ctx.getScope(node)
  if not scope.contains(targetNode):
    ctx.addDiagnostic(node, fmt"Target not in scope")
    return false

  return true

typeComputers[breakClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for break {node}"
  return voidTypeInstance

typeComputers[continueClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for continue {node}"
  return voidTypeInstance

typeComputers[returnClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for return {node}"
  return voidTypeInstance

proc getTypeSize(ctx: ModelComputationContextBase, typ: AstNode): int =
  # if typ.class == IdMetaType: return 0
  if typ.class == IdInt32 or typ.class == IdUInt32: return 4
  if typ.class == IdInt64 or typ.class == IdUInt64: return 8
  if typ.class == IdFloat32: return 4
  if typ.class == IdFloat64: return 8
  if typ.class == IdChar: return 1
  if typ.class == IdPointerType: return 4
  if typ.class == IdGenericType: return 0
  log lvlError, fmt"Not implemented: getTypeSize for {typ}"
  return 0

proc getBiggerIntType*(ctx: ModelComputationContextBase, left: AstNode, right: AstNode): AstNode =
  let leftType = ctx.computeType(left)
  let rightType = ctx.computeType(right)
  let leftSize = ctx.getTypeSize(leftType)
  let rightSize = ctx.getTypeSize(rightType)

  if leftSize >= rightSize:
    return leftType
  return rightType

# binary expressions
typeComputers[addExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for add {node}"
  if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
    return ctx.getBiggerIntType(left, right)
  return int32TypeInstance

typeComputers[subExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for sub {node}"
  if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
    return ctx.getBiggerIntType(left, right)
  return int32TypeInstance

typeComputers[mulExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for mul {node}"
  if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
    return ctx.getBiggerIntType(left, right)
  return int32TypeInstance

typeComputers[divExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for div {node}"
  if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
    return ctx.getBiggerIntType(left, right)
  return int32TypeInstance

typeComputers[modExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for mod {node}"
  if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
    return ctx.getBiggerIntType(left, right)
  return int32TypeInstance

typeComputers[lessExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for less {node}"
  return int32TypeInstance

typeComputers[lessEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for less equal {node}"
  return int32TypeInstance

typeComputers[greaterExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for greater {node}"
  return int32TypeInstance

typeComputers[greaterEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for greater equal {node}"
  return int32TypeInstance

typeComputers[equalExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for equal {node}"
  return int32TypeInstance

typeComputers[notEqualExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for not equal {node}"
  return int32TypeInstance

typeComputers[andExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for and {node}"
  return int32TypeInstance

typeComputers[orExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for or {node}"
  return int32TypeInstance

typeComputers[orderExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for order {node}"
  return int32TypeInstance

# unary expressions
typeComputers[negateExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for negate {node}"
  return int32TypeInstance

typeComputers[notExpressionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for not {node}"
  return int32TypeInstance

proc isTypeGeneric*(typ: AstNode, ctx: ModelComputationContextBase): bool =
  # debugf"isTypeGeneric {typ}"
  # defer:
  #   debugf"isTypeGeneric {typ} -> {result}"
  if typ.class == IdGenericType:
    return true

  if typ.class == IdStructDefinition:
    for _, node in typ.children(IdStructDefinitionParameter):
      if node.firstChild(IdStructParameterValue).getSome(valueNode):
        let value = ctx.getValue(valueNode)
        if value.isTypeGeneric(ctx):
          return true
      else:
        return true
    return false

  if typ.class == IdPointerType:
    if typ.resolveReference(IdPointerTypeTarget).getSome(targetTypeNode):
      return targetTypeNode.isTypeGeneric(ctx)
    return true

  return false

proc isGeneric*(function: AstNode, ctx: ModelComputationContextBase): bool =
  # debugf"isGeneric {function}"
  # defer:
  #   debugf"isGeneric {function} -> {result}"
  result = false
  if function.class == IdFunctionDefinition:
    for _, param in function.children(IdFunctionDefinitionParameters):
      let paramType = ctx.computeType(param)
      if paramType.isNil or paramType.isTypeGeneric(ctx):
        return true

      # debugf"param: {param}, type: {paramType}"
      if paramType.class == IdType:
        return true
    return false

  log lvlError, fmt"Unknown class for isGeneric: {function}"
  return false

proc substituteGenericTypeValues*(ctx: ModelComputationContextBase, genericType: AstNode, concreteType: AstNode, map: var Table[NodeId, AstNode]) =
  # echo &"substitute {genericType.dump(recurse=true)}\n with {concreteType.dump(recurse=true)}"
  if genericType.class == IdGenericType:
    let originalId = genericType.reference(IdCloneOriginal)
    if originalId.isSome:
      if genericType.model.resolveReference(originalId).getSome(original):
        # debugf"set generic {original.property(IdINamedName)}, {original}"
        map[original.id] = concreteType
    else:
      # debugf"set generic {genericType.property(IdINamedName)}, {genericType}"
      map[genericType.id] = concreteType

    return

  if genericType.class != concreteType.class:
    return

  if genericType.class == IdStructDefinition:
    let genericChildren = genericType.children(IdStructDefinitionParameter)
    let concreteChildren = concreteType.children(IdStructDefinitionParameter)
    for i in 0..min(genericChildren.high, concreteChildren.high):
      let genericValue = ctx.getValue(genericChildren[i].firstChild(IdStructParameterValue).get)
      let concreteValue = ctx.getValue(concreteChildren[i].firstChild(IdStructParameterValue).get)
      ctx.substituteGenericTypeValues(genericValue, concreteValue, map)
    return

  if genericType.class == IdPointerType:
    let genericChild = genericType.resolveReference(IdPointerTypeTarget)
    let concreteChild = concreteType.resolveReference(IdPointerTypeTarget)
    if genericChild.isSome and concreteChild.isSome:
      ctx.substituteGenericTypeValues(genericChild.get, concreteChild.get, map)
    return

  # for genericChildren in genericType.childLists.mitems:
  #   var concreteChildren = concreteType.children(genericChildren.role)
  #   for i, genericChild in genericChildren.nodes:
  #     if i < concreteChildren.len:
  #       substituteGenericTypeValues(ctx, genericChild, concreteChildren[i], map)

type FunctionInstantiation = tuple[function: AstNode, arguments: Table[NodeId, AstNode]]
type StructInstantiation = tuple[struct: AstNode, arguments: Table[NodeId, AstNode]]

var functionInstances* = initTable[FunctionInstantiation, tuple[node: AstNode, revision: int]]()
var structInstances* = initTable[StructInstantiation, tuple[node: AstNode, revision: int]]()

proc getContainingFunction*(node: AstNode): AstNode =
  var current = node.parent
  while current.isNotNil:
    if current.class == IdFunctionDefinition:
      return current
    current = current.parent
  return nil

proc getContainingDecl*(node: AstNode): AstNode =
  var current = node.parent
  while current.isNotNil:
    if current.nodeClass.isSubclassOf(IdIDeclaration):
      return current
    current = current.parent
  return nil

proc getContainingDeclName*(node: AstNode): string =
  let containingDecl = node.getContainingDecl
  if containingDecl.isNil:
    return "<anonymous " & $node.id & ">"
  return containingDecl.property(IdINamedName).get.stringValue

proc instantiateStruct*(ctx: ModelComputationContextBase, genericStruct: AstNode, arguments: openArray[AstNode]): AstNode =
  assert genericStruct.isNotNil

  let model = genericStruct.model
  let depGraph = ctx.ModelComputationContext.state.depGraph
  let genericParams = genericStruct.children(IdStructDefinitionParameter)

  var argumentValues = newSeq[AstNode]()
  var map = initTable[NodeId, AstNode]()

  for i, arg in arguments:
    if i < genericParams.len:
      let genericParam = genericParams[i]
      let genericParamType = ctx.computeType(genericParam)

      # debugf"compute value of {arg.dump(node.model, true)}"
      let value = ctx.getValue(arg)
      if value.isNotNil:
        # debugf"y: clone {value}"
        # log lvlWarn, fmt"getValue call: clone arg value {value}"
        argumentValues.add value
        map[genericParam.id] = value
        # debugf"-> {arguments.last}"
      else:
        argumentValues.add nil
        log lvlWarn, fmt"Could not compute value for argument {arg} in call {genericStruct}"

  # debugf"instantiateStruct '{genericStruct.getContainingDeclName()}', args {map}, {genericStruct.dump(recurse=false)}"
  let key = (genericStruct, map)
  if structInstances.contains(key):
    let (existingConcreteStruct, existingRevision) = structInstances[key]
    var allGreen = true
    genericStruct.forEach2 n:
      let item = n.getItem
      let key = (item, -1)
      let lastChange = depGraph.lastChange(key, depGraph.revision)
      if lastChange > existingRevision:
        allGreen = false

    # debugf"struct instance already exists: {existingConcreteStruct.dump(recurse=false)}"
    if allGreen:
      # log lvlWarn, fmt"struct instance already exists for {genericStruct}"
      return existingConcreteStruct
    log lvlWarn, fmt"struct instance already exists but is not up to date for {genericStruct}"

  # log lvlWarn, fmt"instantiateStruct: clone generic struct {genericStruct}"
  var concreteStruct = genericStruct.cloneAndMapIds(linkOriginal=true)
  concreteStruct.references.add (IdStructTypeGenericBase, genericStruct.id)

  for i, param in concreteStruct.children(IdStructDefinitionParameter):
    if argumentValues[i].isNotNil:
      # let argumentValue = argumentValues[i].cloneAndMapIds(linkOriginal=true)
      # log lvlWarn, fmt"instantiateFunction: clone argument {argumentValues[i]} -> {argumentValue.dump(model)}"
      let argumentValue = newAstNode(nodeReferenceClass)
      argumentValue.setReference(IdNodeReferenceTarget, argumentValues[i].id)
      param.add(IdStructParameterValue, argumentValue)

  for i, member in concreteStruct.children(IdStructDefinitionMembers):
    # debugf"link member {member} to {targetValue.children(IdStructDefinitionMembers)[i].id}"
    member.references.add (IdStructTypeGenericMember, genericStruct.children(IdStructDefinitionMembers)[i].id)

  model.addTempNode(concreteStruct)
  # debugf"concrete struct {concreteStruct.dump(recurse=true)}"

  structInstances[key] = (concreteStruct, depGraph.revision)
  return concreteStruct

proc instantiateFunction*(ctx: ModelComputationContextBase, genericFunction: AstNode, arguments: openArray[AstNode]): AstNode =
  assert genericFunction.isNotNil

  let model = genericFunction.model
  let depGraph = ctx.ModelComputationContext.state.depGraph
  let genericParams = genericFunction.children(IdFunctionDefinitionParameters)

  var map = initTable[NodeId, AstNode]()

  for i, arg in arguments:
    if i < genericParams.len:
      let genericParam = genericParams[i]
      let genericParamType = ctx.computeType(genericParam)

      # debugf"{i}: generic param {genericParam.dump(recurse=true)}"
      # debugf"{i}: generic param type {genericParamType.dump(recurse=true)}"
      if genericParamType.class == IdType:
        let value = ctx.getValue(arg)
        if value.isNil:
          log lvlError, fmt"Could not compute value for argument {arg}"
          continue
        # debugf"{i}: value {value}"
        map[genericParam.id] = value

      else:
        # debugf"substitute"
        let typ = ctx.computeType(arg)
        # debugf"{i}: type {typ}"
        # debugf"{i}: substitute generic {`$`(genericParamType, true)}"
        # debugf"{i}: with {`$`(typ, true)}"
        ctx.substituteGenericTypeValues(genericParamType, typ, map)

  # for (key, value) in map.pairs:
  #   debugf"map: {key} -> {value}"

  # debugf"instantiateFunction '{genericFunction.getContainingDeclName()}', args {map}, {genericFunction.dump(recurse=false)}"

  # if map.len != genericParams.len:
  #   debugf"missing arguments"

  let key = (genericFunction, map)
  if functionInstances.contains(key):
    let (existingConcreteFunction, existingRevision) = functionInstances[key]
    var allGreen = true
    genericFunction.forEach2 n:
      let item = n.getItem
      let key = (item, -1)
      let lastChange = depGraph.lastChange(key, depGraph.revision)
      if lastChange > existingRevision:
        allGreen = false

    # debugf"function instance already exists: {existingConcreteFunction.dump(recurse=false)}"
    if allGreen:
      # log lvlWarn, fmt"function instance already exists for {genericFunction}"
      return existingConcreteFunction
    log lvlWarn, fmt"function instance already exists but is not up to date for {genericFunction}"

  # log lvlWarn, fmt"instantiateFunction: clone generic function {genericFunction}"
  var concreteFunction = genericFunction.cloneAndMapIds(linkOriginal=true)

  # debug concreteFunction.dump(model, true)
  # set concrete function arguments as values for paramaters
  concreteFunction.forEach2 n:
    let originalId = n.reference(IdCloneOriginal)
    if map.contains(originalId):
      if n.class == IdGenericType:
        n.setReference(IdGenericTypeValue, map[originalId].id)
      elif n.class == IdParameterDecl:
        # let argumentValue = map[originalId].cloneAndMapIds(linkOriginal=true)
        # log lvlWarn, fmt"instantiateFunction: clone argument {map[originalId]} -> {argumentValue.dump(model)}"
        let argumentValue = newAstNode(nodeReferenceClass)
        argumentValue.setReference(IdNodeReferenceTarget, map[originalId].id)
        n.forceSetChild(IdParameterDeclValue, argumentValue)

      else:
        assert false, "unknown class for generic type value substitution"
  # debug concreteFunction.dump(model, true)

  # log lvlWarn, &"addTempNode concrete function {concreteFunction}"
  model.addTempNode(concreteFunction)
  # debugf"concrete function {concreteFunction.dump(recurse=true)}"

  functionInstances[key] = (concreteFunction, depGraph.revision)
  return concreteFunction

# calls
typeComputers[callClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for call {node}"
  # defer:
  #   debugf"result type {result} for {node}"

  let funcExprNode = node.firstChild(IdCallFunction).getOr:
    log lvlError, fmt"No function specified for call {node}"
    return voidTypeInstance

  var targetType: AstNode
  var targetValue: AstNode
  if funcExprNode.class == IdNodeReference:
    let funcDeclNode = funcExprNode.resolveReference(IdNodeReferenceTarget).getOr:
      log lvlError, fmt"Function not found: {funcExprNode}"
      return voidTypeInstance

    if funcDeclNode.class == IdConstDecl:
      let funcDefNode = funcDeclNode.firstChild(IdConstDeclValue).getOr:
        log lvlError, fmt"No value: {funcDeclNode} in call {node}"
        return voidTypeInstance

      targetType = ctx.computeType(funcDefNode)
      targetValue = ctx.getValue(funcDefNode)

    else: # not a const decl, so call indirect
      targetType = ctx.computeType(funcExprNode)
      targetValue = ctx.getValue(funcExprNode)

  else: # not a node reference
    targetType = ctx.computeType(funcExprNode)
    targetValue = ctx.getValue(funcExprNode)

  # debugf"type targetType: {targetType}"
  # debugf"type targetValue: {targetValue}"

  if targetType.class == IdFunctionType:
    if targetValue.isNotNil and targetValue.class == IdFunctionDefinition:
      if targetValue.isGeneric(ctx):
        # debugf"function instantiation from {node.getContainingDeclName} {node}"
        let concreteFunction = ctx.instantiateFunction(targetValue, node.children(IdCallArguments))
        let concreteFunctionType = ctx.computeType(concreteFunction)
        # debugf"concrete function: {concreteFunction.dump(recurse=true)}"
        # debugf"concrete function: {concreteFunctionType.dump(recurse=true)}"
        if concreteFunctionType.firstChild(IdFunctionTypeReturnType).getSome(returnType):
          return returnType

        log lvlError, fmt"Function type expected, got {targetType}"
        return voidTypeInstance

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
  #   debugf"result value {result} for {node}"

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

  # debugf"value targetType: {targetType}"
  # debugf"value targetValue: {targetValue}"

  if targetType.class == IdType and targetValue.class == IdStructDefinition:
    if node.childCount(IdCallArguments) != targetValue.childCount(IdStructDefinitionParameter):
      # debugf"wrong number of arguments"
      return voidTypeInstance

    # debugf"struct instantiation from {node.getContainingDeclName} {node}"
    let concreteType = ctx.instantiateStruct(targetValue, node.children(IdCallArguments))
    return concreteType

  return nil

validationComputers[callClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate call {node}"

  if not ctx.validateHasChild(node, IdCallFunction):
    return false

  let funcExprNode = node.firstChild(IdCallFunction).get

  let targetType = ctx.computeType(funcExprNode)
  let targetValue = ctx.getValue(funcExprNode)

  # debugf"type targetType: {targetType}"
  # debugf"type targetValue: {targetValue}"
  var arguments = node.children(IdCallArguments)

  if targetType.class == IdFunctionType:

    var parameterTypes: seq[AstNode]
    if targetValue.isNotNil and targetValue.class == IdFunctionDefinition and targetValue.isGeneric(ctx):
      let concreteFunction = ctx.instantiateFunction(targetValue, arguments)
      let concreteFunctionType = ctx.computeType(concreteFunction)
      parameterTypes = concreteFunctionType.children(IdFunctionTypeParameterTypes)
    else:
      parameterTypes = targetType.children(IdFunctionTypeParameterTypes)

    if arguments.len != parameterTypes.len:
      ctx.addDiagnostic(node, fmt"Wrong number of arguments, expected {parameterTypes.len}, got {arguments.len}")
      return false

    for i in 0..<min(arguments.len, parameterTypes.len):
      let argument = arguments[i]
      let parameterType = parameterTypes[i]
      let argumentType = ctx.computeType(argument)
      if not ctx.typesMatch(parameterType, argumentType):
        ctx.addDiagnostic(argument, fmt"Expected {parameterType}, got {argumentType}")
        result = false

  if targetType.class == IdType:
    return true

  return true

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

  # # todo: non type parameters
  # var genericType = newAstNode(genericTypeClass)
  # let name = node.property(IdINamedName).get.stringValue
  # genericType.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: name))
  # node.model.addTempNode(genericType)
  # return genericType

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

  let typ = ctx.computeType(valueNode)
  let structType = if typ.class == IdPointerType:
    typ.resolveReference(IdPointerTypeTarget).getOr:
      return
  else:
    typ

  let isGeneric = structType.hasReference(IdStructTypeGenericBase)

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

validationComputers[structMemberAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): bool =
  # debugf"validate assignment {node}"

  if not ctx.validateHasChild(node, IdStructMemberAccessValue):
    return false
  # if not ctx.validateHasChild(node, IdStructMemberAccessMember):
  #   return false

  let targetNode = node.resolveReference(IdStructMemberAccessMember).getOr:
    ctx.addDiagnostic(node, "Could not resolve struct member")
    ctx.dependOnCurrentRevision()
    return false

  let scope = ctx.getScope(node)
  if not scope.contains(targetNode):
    ctx.addDiagnostic(node, fmt"Struct member not in scope")
    return false

  let typ = ctx.computeType(node.firstChild(IdStructMemberAccessValue).get)

  let structType = if typ.class == IdPointerType:
    typ.resolveReference(IdPointerTypeTarget).getOr:
      return
  else:
    typ

  if structType.class != IdStructDefinition:
    ctx.addDiagnostic(node, fmt"Expected struct type or pointer to struct typ, got {structType}")
    return false

  return true

typeComputers[structMemberDefinitionClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for struct member definition {node}"

  if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
    return ctx.getValue(typeNode)

  return voidTypeInstance

typeComputers[allocateClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for allocate {node}"

  if node.firstChild(IdAllocateType).getSome(typeNode):
    let targetType = ctx.getValue(typeNode)
    var typ = newAstNode(pointerTypeClass)
    typ.setReference(IdPointerTypeTarget, targetType.id)
    node.model.addTempNode(typ)
    return typ

  return voidTypeInstance

typeComputers[addressOfClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for address of {node}"

  if node.firstChild(IdAddressOfValue).getSome(valueNode):
    let targetType = ctx.computeType(valueNode)
    var typ = newAstNode(pointerTypeClass)
    typ.setReference(IdPointerTypeTarget, targetType.id)
    node.model.addTempNode(typ)
    return typ

  return voidTypeInstance

typeComputers[derefClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for deref {node}"

  if node.firstChild(IdDerefValue).getSome(valueNode):
    let pointerType = ctx.computeType(valueNode)
    # debugf"try resolve reference {pointerType.dump(recurse=true)}"
    if pointerType.class == IdPointerType and pointerType.resolveReference(IdPointerTypeTarget).getSome(targetType):
      return targetType
    # log lvlError, fmt"Could not resolve pointer type {pointerType}"
    if pointerType.resolveReference(IdPointerTypeTarget).getSome(targetType):
      return targetType

  return voidTypeInstance

typeComputers[stringGetPointerClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for deref {node}"
  var typ = newAstNode(pointerTypeClass)
  typ.setReference(IdPointerTypeTarget, charTypeInstance.id)
  node.model.addTempNode(typ)
  return typ

typeComputers[stringGetLengthClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for deref {node}"
  return int32TypeInstance

typeComputers[arrayAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  # debugf"compute type for deref {node}"

  if node.firstChild(IdArrayAccessValue).getSome(typeNode):
    let pointerType = ctx.computeType(typeNode)
    if pointerType.class == IdPointerType and pointerType.resolveReference(IdPointerTypeTarget).getSome(targetType):
      return targetType

  return voidTypeInstance

# scope
scopeComputers[structMemberAccessClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for struct member access {node}"

  let valueNode = node.firstChild(IdStructMemberAccessValue).getOr:
    return @[]

  let valueType = ctx.computeType(valueNode)

  let structType = if valueType.class == IdPointerType:
    valueType.resolveReference(IdPointerTypeTarget).getOr:
      return
  else:
    valueType

  if structType.class == IdType:
    let actualType = ctx.getValue(valueNode)
    if actualType.class == IdStructDefinition:
      return actualType.children(IdStructDefinitionParameter)

    return @[]

  let genericType = structType.reference(IdStructTypeGenericBase)
  # debugf"value type {`$`(structType, true)}"
  if genericType.isSome:
    if node.model.resolveReference(genericType).getSome(genericTypeNode):
      # debugf"generic type {`$`(genericTypeNode, true)}"
      return genericTypeNode.children(IdStructDefinitionMembers)
    return @[]

  return structType.children(IdStructDefinitionMembers)

proc getGenericTypes(node: AstNode, res: var seq[AstNode]) =
  if node.class == IdGenericType:
    res.add node
    return

  for children in node.childLists.mitems:
    for c in children.nodes:
      c.getGenericTypes(res)

proc getGenericTypes(node: AstNode): seq[AstNode] =
  node.getGenericTypes(result)

proc computeDefaultScope(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  var nodes: seq[AstNode] = @[]

  # todo: improve this
  for model in node.model.models:
    for root in model.rootNodes:
      if root.class == IdNodeList:
        for _, c in root.children(IdNodeListChildren):
          nodes.add c

  var prev = node
  var current = node.parent
  while current.isNotNil:
    ctx.dependOn(current)

    if current.class == IdFunctionDefinition:
      for _, c in current.children(IdFunctionDefinitionParameters):
        ctx.dependOn(c)
        nodes.add c
        c.getGenericTypes(nodes)

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

    if current.class == IdForLoop:
      for _, c in current.children(IdForLoopVariable):
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

scopeComputers[IdThenCase] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  # debugf"compute scope for then case {node}"
  return ctx.computeDefaultScope(node)

let baseLanguage* = newLanguage(IdBaseLanguage,
  @[
    namedInterface, declarationInterface,

    # typeClass,
    metaTypeClass, stringTypeClass, charTypeClass, voidTypeClass, functionTypeClass, structTypeClass, pointerTypeClass, pointerTypeDeclClass,
    int32TypeClass, uint32TypeClass, int64TypeClass, uint64TypeClass, float32TypeClass, float64TypeClass,

    expressionClass, binaryExpressionClass, unaryExpressionClass, emptyLineClass, castClass,
    numberLiteralClass, stringLiteralClass, boolLiteralClass, nodeReferenceClass, emptyClass, genericTypeClass, constDeclClass, letDeclClass, varDeclClass, nodeListClass, blockClass, callClass, thenCaseClass, ifClass, whileClass, forLoopClass,
    parameterDeclClass, functionDefinitionClass, assignmentClass,
    breakClass, continueClass, returnClass,
    addExpressionClass, subExpressionClass, mulExpressionClass, divExpressionClass, modExpressionClass,
    lessExpressionClass, lessEqualExpressionClass, greaterExpressionClass, greaterEqualExpressionClass, equalExpressionClass, notEqualExpressionClass, andExpressionClass, orExpressionClass, orderExpressionClass,
    negateExpressionClass, notExpressionClass,
    appendStringExpressionClass, printExpressionClass, buildExpressionClass, allocateClass,
    stringGetPointerClass, stringGetLengthClass,

    structDefinitionClass, structMemberDefinitionClass, structParameterClass, structMemberAccessClass,
    addressOfClass, derefClass, arrayAccessClass,
  ], builder, typeComputers, valueComputers, scopeComputers, validationComputers,
  rootNodes=[
    int32TypeInstance, uint32TypeInstance, int64TypeInstance, uint64TypeInstance, float32TypeInstance, float64TypeInstance, stringTypeInstance, voidTypeInstance, charTypeInstance, metaTypeInstance
  ])

# print baseLanguage
