import std/[tables, strformat]
import misc/[id, util, custom_logger]
import ui/node
import model, cells, model_state, query_system, ast_ids

export id, ast_ids

template defineComputerHelpers*(typeComputers, valueComputers, scopeComputers, validationComputers: untyped): untyped =
  template typeComputer(id: ClassId, body: untyped): untyped {.used.} =
    block:
      {.push hint[XCannotRaiseY]:off.}
      proc fun(ctx {.inject.}: ModelComputationContextBase, node {.inject.}: AstNode): AstNode {.gcsafe, raises: [CatchableError].} =
        body
      {.pop.}
      typeComputers[id] = TypeComputer(fun: fun)

  template valueComputer(id: ClassId, body: untyped): untyped {.used.} =
    block:
      {.push hint[XCannotRaiseY]:off.}
      proc fun(ctx {.inject.}: ModelComputationContextBase, node {.inject.}: AstNode): AstNode {.gcsafe, raises: [CatchableError].} =
        body
      {.pop.}
      valueComputers[id] = ValueComputer(fun: fun)

  template scopeComputer(id: ClassId, body: untyped): untyped {.used.} =
    block:
      {.push hint[XCannotRaiseY]:off.}
      proc fun(ctx {.inject.}: ModelComputationContextBase, node {.inject.}: AstNode): seq[AstNode] {.gcsafe, raises: [CatchableError].} =
        body
      {.pop.}
      scopeComputers[id] = ScopeComputer(fun: fun)

  template validationComputer(id: ClassId, body: untyped): untyped {.used.} =
    block:
      {.push hint[XCannotRaiseY]:off.}
      proc fun(ctx {.inject.}: ModelComputationContextBase, node {.inject.}: AstNode): bool {.gcsafe, raises: [CatchableError].} =
        body
      {.pop.}
      validationComputers[id] = ValidationComputer(fun: fun)

{.push gcsafe.}

logCategory "base-language"

type FunctionInstantiation = tuple[function: AstNode, arguments: Table[NodeId, AstNode]]
type StructInstantiation = tuple[struct: AstNode, arguments: Table[NodeId, AstNode]]

proc instantiateStruct*(ctx: ModelComputationContextBase, genericStruct: AstNode, arguments: openArray[AstNode], nodeReferenceClass: NodeClass): AstNode

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

  if function.class == IdFunctionImport:
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

proc getGenericTypes*(node: AstNode, res: var seq[AstNode]) =
  if node.class == IdGenericType:
    res.add node
    return

  for children in node.childLists.mitems:
    for c in children.nodes:
      c.getGenericTypes(res)

proc getGenericTypes*(node: AstNode): seq[AstNode] =
  node.getGenericTypes(result)

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

# todo: don't make these global
var functionInstances* = initTable[FunctionInstantiation, tuple[node: AstNode, revision: int]]()
var structInstances* = initTable[StructInstantiation, tuple[node: AstNode, revision: int]]()

proc instantiateStruct*(ctx: ModelComputationContextBase, genericStruct: AstNode, arguments: openArray[AstNode], nodeReferenceClass: NodeClass): AstNode =
  assert genericStruct.isNotNil

  let structInstances = ({.gcsafe.}: structInstances.addr)

  let model = genericStruct.model
  let depGraph = ctx.ModelComputationContext.state.depGraph
  let genericParams = genericStruct.children(IdStructDefinitionParameter)

  var argumentValues = newSeq[AstNode]()
  var map = initTable[NodeId, AstNode]()

  for i, arg in arguments:
    if i < genericParams.len:
      let genericParam = genericParams[i]

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
        # log lvlWarn, fmt"Could not compute value for argument {arg} in call {genericStruct}"

  # debugf"instantiateStruct '{genericStruct.getContainingDeclName()}', args {map}, {genericStruct.dump(recurse=false)}"
  let key = (genericStruct, map)
  if structInstances[].contains(key):
    let (existingConcreteStruct, existingRevision) = structInstances[][key]
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
    # log lvlWarn, fmt"struct instance already exists but is not up to date for {genericStruct}"

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

  structInstances[][key] = (concreteStruct, depGraph.revision)
  return concreteStruct

proc instantiateFunction*(ctx: ModelComputationContextBase, genericFunction: AstNode, arguments: openArray[AstNode], nodeReferenceClass: NodeClass): AstNode =
  assert genericFunction.isNotNil

  let functionInstances = ({.gcsafe.}: functionInstances.addr)

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
  if functionInstances[].contains(key):
    let (existingConcreteFunction, existingRevision) = functionInstances[][key]
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
    # log lvlWarn, fmt"function instance already exists but is not up to date for {genericFunction}"

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

  functionInstances[][key] = (concreteFunction, depGraph.revision)
  return concreteFunction

proc createBaseLanguage*(repository: Repository, builders: CellBuilderDatabase) =
  log lvlInfo, &"createBaseLanguage"

  let expressionClass = newNodeClass(IdExpression, "Expression", isAbstract=true)
  # let typeClass = newNodeClass(IdType, "Type", base=expressionClass)

  let namedInterface = newNodeClass(IdINamed, "INamed", isAbstract=true, isInterface=true,
    properties=[PropertyDescription(id: IdINamedName, role: "name", typ: PropertyType.String)])

  let declarationInterface = newNodeClass(IdIDeclaration, "IDeclaration", isAbstract=true, isInterface=true, base=namedInterface)

  let metaTypeClass = newNodeClass(IdType, "Type", alias="type", base=expressionClass)
  let stringTypeClass = newNodeClass(IdString, "StringType", alias="string", base=expressionClass)
  let int32TypeClass = newNodeClass(IdInt32, "Int32Type", alias="i32", base=expressionClass)
  let uint32TypeClass = newNodeClass(IdUInt32, "UInt32Type", alias="u32", base=expressionClass)
  let int64TypeClass = newNodeClass(IdInt64, "Int64Type", alias="i64", base=expressionClass)
  let uint64TypeClass = newNodeClass(IdUInt64, "UInt64Type", alias="u64", base=expressionClass)
  let float32TypeClass = newNodeClass(IdFloat32, "Float32Type", alias="f32", base=expressionClass)
  let float64TypeClass = newNodeClass(IdFloat64, "Float64Type", alias="f64", base=expressionClass)
  let voidTypeClass = newNodeClass(IdVoid, "VoidType", alias="void", base=expressionClass)
  let charTypeClass = newNodeClass(IdChar, "CharType", alias="char", base=expressionClass)
  let functionTypeClass = newNodeClass(IdFunctionType, "FunctionType", base=expressionClass,
    children=[
      NodeChildDescription(id: IdFunctionTypeParameterTypes, role: "parameterTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore),
      NodeChildDescription(id: IdFunctionTypeReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.One)])
  let structTypeClass = newNodeClass(IdStructType, "StructType", base=expressionClass,
    children=[
      NodeChildDescription(id: IdStructTypeMemberTypes, role: "memberTypes", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

  let pointerTypeClass = newNodeClass(IdPointerType, "PointerType", base=expressionClass,
    references=[
      NodeReferenceDescription(id: IdPointerTypeTarget, role: "target", class: expressionClass.id)])

  let pointerTypeDeclClass = newNodeClass(IdPointerTypeDecl, "PointerTypeDecl", alias="ptr", base=expressionClass,
    children=[
      NodeChildDescription(id: IdPointerTypeDeclTarget, role: "target", class: expressionClass.id, count: ChildCount.One)])

  let castClass = newNodeClass(IdCast, "Cast", alias="cast", base=expressionClass, children=[
      NodeChildDescription(id: IdCastType, role: "type", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdCastValue, role: "value", class: expressionClass.id, count: ChildCount.One),
    ])

  let binaryExpressionClass = newNodeClass(IdBinaryExpression, "BinaryExpression", isAbstract=true, base=expressionClass, children=[
      NodeChildDescription(id: IdBinaryExpressionLeft, role: "left", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdBinaryExpressionRight, role: "right", class: expressionClass.id, count: ChildCount.One),
    ])
  let unaryExpressionClass = newNodeClass(IdUnaryExpression, "UnaryExpression", isAbstract=true, base=expressionClass, children=[
      NodeChildDescription(id: IdUnaryExpressionChild, role: "child", class: expressionClass.id, count: ChildCount.One),
    ])

  let emptyLineClass = newNodeClass(IdEmptyLine, "EmptyLine", base=expressionClass)

  let addExpressionClass = newNodeClass(IdAdd, "BinaryAddExpression", alias="+", base=binaryExpressionClass, precedence=5)
  let subExpressionClass = newNodeClass(IdSub, "BinarySubExpression", alias="-", base=binaryExpressionClass, precedence=5)
  let mulExpressionClass = newNodeClass(IdMul, "BinaryMulExpression", alias="*", base=binaryExpressionClass, precedence=6)
  let divExpressionClass = newNodeClass(IdDiv, "BinaryDivExpression", alias="/", base=binaryExpressionClass, precedence=6)
  let modExpressionClass = newNodeClass(IdMod, "BinaryModExpression", alias="%", base=binaryExpressionClass, precedence=6)

  let appendStringExpressionClass = newNodeClass(IdAppendString, "BinaryAppendStringExpression", alias="&", base=binaryExpressionClass, precedence=4)
  let lessExpressionClass = newNodeClass(IdLess, "BinaryLessExpression", alias="<", base=binaryExpressionClass, precedence=4)
  let lessEqualExpressionClass = newNodeClass(IdLessEqual, "BinaryLessEqualExpression", alias="<=", base=binaryExpressionClass, precedence=4)
  let greaterExpressionClass = newNodeClass(IdGreater, "BinaryGreaterExpression", alias=">", base=binaryExpressionClass, precedence=4)
  let greaterEqualExpressionClass = newNodeClass(IdGreaterEqual, "BinaryGreaterEqualExpression", alias=">=", base=binaryExpressionClass, precedence=4)
  let equalExpressionClass = newNodeClass(IdEqual, "BinaryEqualExpression", alias="==", base=binaryExpressionClass, precedence=4)
  let notEqualExpressionClass = newNodeClass(IdNotEqual, "BinaryNotEqualExpression", alias="!=", base=binaryExpressionClass, precedence=4)
  let orderExpressionClass = newNodeClass(IdOrder, "BinaryOrderExpression", alias="<=>", base=binaryExpressionClass, precedence=4)
  let andExpressionClass = newNodeClass(IdAnd, "BinaryAndExpression", alias="and", base=binaryExpressionClass, precedence=3)
  let orExpressionClass = newNodeClass(IdOr, "BinaryOrExpression", alias="or", base=binaryExpressionClass, precedence=3)

  let negateExpressionClass = newNodeClass(IdNegate, "UnaryNegateExpression", alias="-", base=unaryExpressionClass)
  let notExpressionClass = newNodeClass(IdNot, "UnaryNotExpression", alias="!", base=unaryExpressionClass)

  let printExpressionClass = newNodeClass(IdPrint, "PrintExpression", alias="print", base=expressionClass,
    children=[
      NodeChildDescription(id: IdPrintArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

  let buildExpressionClass = newNodeClass(IdBuildString, "BuildExpression", alias="build", base=expressionClass,
    children=[
      NodeChildDescription(id: IdBuildArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

  let emptyClass = newNodeClass(IdEmpty, "Empty", base=expressionClass)
  let nodeReferenceClass = newNodeClass(IdNodeReference, "NodeReference", alias="ref", base=expressionClass, substitutionReference=IdNodeReferenceTarget.some, references=[NodeReferenceDescription(id: IdNodeReferenceTarget, role: "target", class: declarationInterface.id)])
  let numberLiteralClass = newNodeClass(IdIntegerLiteral, "IntegerLiteral", alias="number", base=expressionClass, properties=[PropertyDescription(id: IdIntegerLiteralValue, role: "value", typ: PropertyType.Int)], substitutionProperty=IdIntegerLiteralValue.some)
  let stringLiteralClass = newNodeClass(IdStringLiteral, "StringLiteral", alias="''", base=expressionClass, properties=[PropertyDescription(id: IdStringLiteralValue, role: "value", typ: PropertyType.String)])
  let boolLiteralClass = newNodeClass(IdBoolLiteral, "BoolLiteral", alias="bool", base=expressionClass, properties=[PropertyDescription(id: IdBoolLiteralValue, role: "value", typ: PropertyType.Bool)])

  let addressOfClass = newNodeClass(IdAddressOf, "AddressOf", alias="addr", base=expressionClass,
    children=[
      NodeChildDescription(id: IdAddressOfValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

  let derefClass = newNodeClass(IdDeref, "Deref", alias="deref", base=expressionClass,
    children=[
      NodeChildDescription(id: IdDerefValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

  let stringGetPointerClass = newNodeClass(IdStringGetPointer, "StringGetPointer", base=expressionClass,
    children=[
      NodeChildDescription(id: IdStringGetPointerValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

  let stringGetLengthClass = newNodeClass(IdStringGetLength, "StringGetLength", base=expressionClass,
    children=[
      NodeChildDescription(id: IdStringGetLengthValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

  let arrayAccessClass = newNodeClass(IdArrayAccess, "ArrayAccess", alias="[]", base=expressionClass,
    children=[
      NodeChildDescription(id: IdArrayAccessValue, role: "value", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdArrayAccessIndex, role: "index", class: expressionClass.id, count: ChildCount.One)])

  let allocateClass = newNodeClass(IdAllocate, "Allocate", alias="alloc", base=expressionClass,
    children=[
      NodeChildDescription(id: IdAllocateType, role: "type", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdAllocateCount, role: "count", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let genericTypeClass = newNodeClass(IdGenericType, "GenericType", alias="generic", base=expressionClass, interfaces=[declarationInterface],
    references=[
      NodeReferenceDescription(id: IdGenericTypeValue, role: "value", class: expressionClass.id)])

  let constDeclClass = newNodeClass(IdConstDecl, "ConstDecl", alias="const", base=expressionClass, interfaces=[declarationInterface],
    children=[
      NodeChildDescription(id: IdConstDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
      NodeChildDescription(id: IdConstDeclValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

  let letDeclClass = newNodeClass(IdLetDecl, "LetDecl", alias="let", base=expressionClass, interfaces=[declarationInterface],
    children=[
      NodeChildDescription(id: IdLetDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
      NodeChildDescription(id: IdLetDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let varDeclClass = newNodeClass(IdVarDecl, "VarDecl", alias="var", base=expressionClass, interfaces=[declarationInterface],
    children=[
      NodeChildDescription(id: IdVarDeclType, role: "type", class: expressionClass.id, count: ChildCount.ZeroOrOne),
      NodeChildDescription(id: IdVarDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let nodeListClass = newNodeClass(IdNodeList, "NodeList", canBeRoot=true,
    children=[
      NodeChildDescription(id: IdNodeListChildren, role: "children", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

  let blockClass = newNodeClass(IdBlock, "Block", alias="{", base=expressionClass,
    children=[
      NodeChildDescription(id: IdBlockChildren, role: "children", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

  let callClass = newNodeClass(IdCall, "Call", base=expressionClass,
    children=[
      NodeChildDescription(id: IdCallFunction, role: "function", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdCallArguments, role: "arguments", class: expressionClass.id, count: ChildCount.ZeroOrMore)])

  let thenCaseClass = newNodeClass(IdThenCase, "ThenCase", isFinal=true, children=[
      NodeChildDescription(id: IdThenCaseCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdThenCaseBody, role: "body", class: expressionClass.id, count: ChildCount.One),
    ])

  let ifClass = newNodeClass(IdIfExpression, "IfExpression", alias="if", base=expressionClass, children=[
      NodeChildDescription(id: IdIfExpressionThenCase, role: "thenCase", class: thenCaseClass.id, count: ChildCount.OneOrMore),
      NodeChildDescription(id: IdIfExpressionElseCase, role: "elseCase", class: expressionClass.id, count: ChildCount.ZeroOrOne),
    ])

  let loopInterface = newNodeClass(IdILoop, "LoopInterface", isInterface=true)

  let whileClass = newNodeClass(IdWhileExpression, "WhileExpression", alias="while", base=expressionClass, interfaces=[loopInterface], children=[
      NodeChildDescription(id: IdWhileExpressionCondition, role: "condition", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdWhileExpressionBody, role: "body", class: expressionClass.id, count: ChildCount.One),
    ])

  let forLoopClass = newNodeClass(IdForLoop, "ForLoop", alias="for", base=expressionClass, interfaces=[loopInterface], children=[
      NodeChildDescription(id: IdForLoopVariable, role: "variable", class: letDeclClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdForLoopStart, role: "start", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdForLoopEnd, role: "end", class: expressionClass.id, count: ChildCount.ZeroOrOne),
      NodeChildDescription(id: IdForLoopBody, role: "body", class: expressionClass.id, count: ChildCount.One),
    ])

  let breakClass = newNodeClass(IdBreakExpression, "BreakExpression", alias="break", base=expressionClass)
  let continueClass = newNodeClass(IdContinueExpression, "ContinueExpression", alias="continue", base=expressionClass)
  let returnClass = newNodeClass(IdReturnExpression, "ReturnExpression", alias="return", base=expressionClass,
    children=[
      NodeChildDescription(id: IdReturnExpressionValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let parameterDeclClass = newNodeClass(IdParameterDecl, "ParameterDecl", alias="param", interfaces=[declarationInterface], substitutionProperty=IdINamedName.some,
    children=[
      NodeChildDescription(id: IdParameterDeclType, role: "type", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdParameterDeclValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let functionDefinitionClass = newNodeClass(IdFunctionDefinition, "FunctionDefinition", alias="fn", base=expressionClass,
    children=[
      NodeChildDescription(id: IdFunctionDefinitionParameters, role: "parameters", class: parameterDeclClass.id, count: ChildCount.ZeroOrMore),
      NodeChildDescription(id: IdFunctionDefinitionReturnType, role: "returnType", class: expressionClass.id, count: ChildCount.ZeroOrOne),
      NodeChildDescription(id: IdFunctionDefinitionBody, role: "body", class: expressionClass.id, count: ChildCount.One)])

  let functionImportClass = newNodeClass(IdFunctionImport, "FunctionImport", alias="import function", base=expressionClass,
    properties=[PropertyDescription(id: IdFunctionImportName, role: "name", typ: PropertyType.String)],
    children=[NodeChildDescription(id: IdFunctionImportType, role: "type", class: expressionClass.id, count: ChildCount.One)])

  let structMemberDefinitionClass = newNodeClass(IdStructMemberDefinition, "StructMemberDefinition", alias="member", interfaces=[declarationInterface], substitutionProperty=IdINamedName.some,
    children=[
      NodeChildDescription(id: IdStructMemberDefinitionType, role: "type", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdStructMemberDefinitionValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let structParameterClass = newNodeClass(IdStructParameter, "StructParameter", alias="param", interfaces=[declarationInterface], substitutionProperty=IdINamedName.some,
    children=[
      NodeChildDescription(id: IdStructParameterType, role: "type", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdStructParameterValue, role: "value", class: expressionClass.id, count: ChildCount.ZeroOrOne)])

  let structDefinitionClass = newNodeClass(IdStructDefinition, "StructDefinition", alias="struct", base=expressionClass,
    children=[
      NodeChildDescription(id: IdStructDefinitionParameter, role: "params", class: structParameterClass.id, count: ChildCount.ZeroOrMore),
      NodeChildDescription(id: IdStructDefinitionMembers, role: "members", class: structMemberDefinitionClass.id, count: ChildCount.ZeroOrMore)])

  let structMemberAccessClass = newNodeClass(IdStructMemberAccess, "StructMemberAccess", base=expressionClass,
    references=[NodeReferenceDescription(id: IdStructMemberAccessMember, role: "member", class: IdINamed)],
    children=[NodeChildDescription(id: IdStructMemberAccessValue, role: "value", class: expressionClass.id, count: ChildCount.One)])

  let assignmentClass = newNodeClass(IdAssignment, "Assignment", alias="=", base=expressionClass, children=[
      NodeChildDescription(id: IdAssignmentTarget, role: "target", class: expressionClass.id, count: ChildCount.One),
      NodeChildDescription(id: IdAssignmentValue, role: "value", class: expressionClass.id, count: ChildCount.One),
    ])

  var builder = newCellBuilder(IdBaseLanguage)

  template addBuilderFor(id: ClassId, builderId: Id, body: untyped): untyped =
    block:
      proc fun(map {.inject.}: NodeCellMap, builder {.inject.}: CellBuilder, node {.inject.}: AstNode, owner {.inject.}: AstNode): Cell {.gcsafe, raises: [].} =
        body

      builder.addBuilderFor id, builderId, fun

  addBuilderFor(emptyLineClass.id, idNone()):
    var cell = ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node)
    return cell

  addBuilderFor(emptyClass.id, idNone()):
    var cell = ConstantCell(id: newId().CellId, node: owner ?? node, referenceNode: node)
    return cell

  addBuilderFor(numberLiteralClass.id, idNone()):
    var cell = PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdIntegerLiteralValue, themeForegroundColors: @["constant.numeric"])
    return cell

  addBuilderFor(boolLiteralClass.id, idNone()):
    var cell = PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdBoolLiteralValue, themeForegroundColors: @["constant.numeric"])
    return cell

  addBuilderFor(stringLiteralClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "'", style: CellStyle(noSpaceRight: true), disableEditing: true, deleteImmediately: true, themeForegroundColors: @["punctuation.definition.string", "punctuation", "&editor.foreground"])
    cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdStringLiteralValue, themeForegroundColors: @["string"])
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "'", style: CellStyle(noSpaceLeft: true), disableEditing: true, deleteImmediately: true, themeForegroundColors: @["punctuation.definition.string", "punctuation", "&editor.foreground"])
    return cell

  addBuilderFor(nodeListClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical})
    cell.nodeFactory = proc(): AstNode {.gcsafe, raises: [].} =
      return newAstNode(emptyLineClass)
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      cell.add builder.buildChildren(map, node, owner, IdNodeListChildren, &{LayoutVertical})
    return cell

  addBuilderFor(blockClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical}, flags: &{IndentChildren, OnNewLine})
    cell.nodeFactory = proc(): AstNode {.gcsafe, raises: [].} =
      return newAstNode(emptyLineClass)
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      cell.add builder.buildChildren(map, node, owner, IdBlockChildren, &{LayoutVertical})
    return cell

  addBuilderFor(genericTypeClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "generic", themeForegroundColors: @["keyword"], disableEditing: true)
      cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)

      if node.resolveReference(IdGenericTypeValue).isSome:
        cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
        # todo: build value cell
        # cell.add block:
        #   buildChildrenT(builder, map, node, owner, IdGenericTypeValue, &{LayoutHorizontal}, 0.CellFlags):
        #     placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")

    return cell

  addBuilderFor(constDeclClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      proc isVisible(node: AstNode): bool {.gcsafe, raises: [].} = node.hasChild(IdConstDeclType)

      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "const", themeForegroundColors: @["keyword"], disableEditing: true)
      cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", customIsVisible: isVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add block:
        buildChildrenT(builder, map, node, owner, IdConstDeclType, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add block:
        buildChildrenT(builder, map, node, owner, IdConstDeclValue, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
    return cell

  addBuilderFor(letDeclClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      proc isVisible(node: AstNode): bool {.gcsafe, raises: [].} = node.hasChild(IdLetDeclType)

      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "let", themeForegroundColors: @["keyword"], disableEditing: true)
      cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", customIsVisible: isVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add block:
        buildChildrenT(builder, map, node, owner, IdLetDeclType, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add block:
        buildChildrenT(builder, map, node, owner, IdLetDeclValue, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
    return cell

  addBuilderFor(varDeclClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      proc isTypeVisible(node: AstNode): bool {.gcsafe, raises: [].} = node.hasChild(IdVarDeclType)
      proc isValueVisible(node: AstNode): bool {.gcsafe, raises: [].} = node.hasChild(IdVarDeclValue)

      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "var", themeForegroundColors: @["keyword"], disableEditing: true)
      cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", customIsVisible: isTypeVisible, style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add block:
        buildChildrenT(builder, map, node, owner, IdVarDeclType, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "<type>")
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", customIsVisible: isValueVisible, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add block:
        buildChildrenT(builder, map, node, owner, IdVarDeclValue, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
    return cell

  addBuilderFor(assignmentClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      cell.add builder.buildChildren(map, node, owner, IdAssignmentTarget, &{LayoutHorizontal})
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add builder.buildChildren(map, node, owner, IdAssignmentValue, &{LayoutHorizontal})
    return cell

  addBuilderFor(parameterDeclClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      proc isVisible(node: AstNode): bool {.gcsafe, raises: [].} = node.hasChild(IdParameterDeclValue)

      cell.add PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

      cell.add block:
        builder.buildChildrenT(map, node, owner, IdParameterDeclType, &{LayoutHorizontal}, 0.CellFlags):
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")

      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "=", customIsVisible: isVisible, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

      cell.add block:
        buildChildrenT(builder, map, node, owner, IdParameterDeclValue, &{LayoutHorizontal}, 0.CellFlags):
          visible: isVisible(node)
          placeholder: PlaceholderCell(id: newId().CellId, node: owner ?? node, referenceNode: node, role: role, shadowText: "...")
    return cell

  addBuilderFor(functionDefinitionClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
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

  builder.addBuilderFor IdFunctionType, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "(", flags: &{NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdFunctionTypeParameterTypes, separator: ",".some, placeholder: "".some, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ")", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdFunctionTypeReturnType, placeholder: "<return type>".some, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdFunctionImport, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: PropertyCell, propertyRole: IdFunctionImportName),
    CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdFunctionImportType, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdStructMemberDefinition, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: PropertyCell, propertyRole: IdINamedName),
    CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdStructMemberDefinitionType, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdStructMemberDefinitionValue, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdStructParameter, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: PropertyCell, propertyRole: IdINamedName),
    CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdStructParameterType, placeholder: "<type>".some, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "=", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdStructParameterValue, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdStructDefinition, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "struct", themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdStructDefinitionParameter, separator: ",".some, placeholder: "<params>".some, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdStructDefinitionMembers, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
    CellBuilderCommand(kind: ConstantCell, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{OnNewLine}),
  ]

  builder.addBuilderFor IdStructMemberAccess, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdStructMemberAccessValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: ReferenceCell, referenceRole: IdStructMemberAccessMember, targetProperty: IdINamedName.some, themeForegroundColors: @["variable", "&editor.foreground"], disableEditing: true),
  ]

  # builder.addBuilderFor pointerTypeClass.id, idNone(), proc(map: NodeCellMap, builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  #   var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  #   cell.fillChildren = proc(map: NodeCellMap) =
  #     cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true)
  #     # todo: build target cell
  #     # cell.add builder.buildChildren(map, node, owner, IdPointerTypeTarget, &{LayoutHorizontal})
  #   return cell

  builder.addBuilderFor IdPointerType, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true),
    # CellBuilderCommand(kind: ReferenceCell, referenceRole: IdPointerTypeTarget, themeForegroundColors: @["variable", "&editor.foreground"], disableEditing: true),
  ]

  builder.addBuilderFor IdPointerTypeDecl, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdPointerTypeDeclTarget, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdAddressOf, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdAddressOfValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ".addr", flags: &{NoSpaceLeft}, themeForegroundColors: @["keyword"], disableEditing: true),
  ]

  builder.addBuilderFor IdDeref, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdDerefValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ".deref", flags: &{NoSpaceLeft}, themeForegroundColors: @["keyword"], disableEditing: true),
  ]

  builder.addBuilderFor IdCast, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdCastValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: "as", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: "(", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdCastType, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation"], disableEditing: true),
  ]

  builder.addBuilderFor IdStringGetPointer, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdStringGetPointerValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: "ptr", themeForegroundColors: @["keyword"], disableEditing: true),
  ]

  builder.addBuilderFor IdStringGetLength, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdStringGetLengthValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ".", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation"], disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: "len", themeForegroundColors: @["keyword"], disableEditing: true),
  ]

  builder.addBuilderFor IdArrayAccess, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdArrayAccessValue, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "[", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdArrayAccessIndex, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "]", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  ]

  builder.addBuilderFor IdAllocate, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "alloc", themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdAllocateType, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ",", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdAllocateCount, placeholder: "1".some, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdCall, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: Children, childrenRole: IdCallFunction, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "(", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdCallArguments, separator: ",".some, placeholder: "".some , uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  ]

  addBuilderFor(thenCaseClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =

      if node.index == 0:
        cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "if", themeForegroundColors: @["keyword"], disableEditing: true)
      else:
        cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "elif", themeForegroundColors: @["keyword"], disableEditing: true, flags: &{OnNewLine})
      cell.add builder.buildChildren(map, node, owner, IdThenCaseCondition, &{LayoutHorizontal})
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      cell.add builder.buildChildren(map, node, owner, IdThenCaseBody, &{LayoutHorizontal})

    return cell

  addBuilderFor(ifClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal}, flags: &{DeleteWhenEmpty}, inline: true)
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =

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

  builder.addBuilderFor IdWhileExpression, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "while", themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdWhileExpressionCondition, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdWhileExpressionBody, uiFlags: &{LayoutHorizontal}),
  ]

  proc varDeclNameOnlyBuilder(map: NodeCellMap, builder: CellBuilder, node: AstNode, owner: AstNode): Cell {.gcsafe, raises: [].} = PropertyCell(node: owner ?? node, referenceNode: node, property: IdINamedName)

  builder.addBuilderFor IdForLoop, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "for", themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdForLoopVariable, builderFunc: varDeclNameOnlyBuilder, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "in", themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdForLoopStart, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "..<", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdForLoopEnd, placeholder: "inf".some, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdForLoopBody, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdBreakExpression, idNone(), [
    CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true),
  ]

  builder.addBuilderFor IdContinueExpression, idNone(), [
    CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true),
  ]

  builder.addBuilderFor IdReturnExpression, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdReturnExpressionValue, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdNodeReference, idNone(), [
    CellBuilderCommand(kind: ReferenceCell, referenceRole: IdNodeReferenceTarget, targetProperty: IdINamedName.some, themeForegroundColors: @["variable", "&editor.foreground"], disableEditing: true),
  ]

  builder.addBuilderFor IdExpression, idNone(), &{OnlyExactMatch}, [
    CellBuilderCommand(kind: ConstantCell, shadowText: "<expr>", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"]),
  ]

  addBuilderFor(binaryExpressionClass.id, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
      let lowerPrecedence = node.parent.isNotNil and node.parent.nodeClass.precedence >= node.nodeClass.precedence

      if lowerPrecedence:
        cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "(", flags: &{NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

      cell.add builder.buildChildren(map, node, owner, IdBinaryExpressionLeft, &{LayoutHorizontal})
      cell.add AliasCell(node: owner ?? node, referenceNode: node, disableEditing: true)
      cell.add builder.buildChildren(map, node, owner, IdBinaryExpressionRight, &{LayoutHorizontal})

      if lowerPrecedence:
        cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    return cell

  builder.addBuilderFor IdDiv, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical}, inline: true),
    CellBuilderCommand(kind: Children, childrenRole: IdBinaryExpressionLeft, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: ConstantCell, text: "------", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdBinaryExpressionRight, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdUnaryExpression, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, flags: &{NoSpaceRight}, disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdUnaryExpressionChild, uiFlags: &{LayoutHorizontal}),
  ]

  builder.addBuilderFor IdType, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdString, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdVoid, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdInt32, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdUInt32, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdInt64, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdUInt64, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdFloat32, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdFloat64, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]
  builder.addBuilderFor IdChar, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["storage.type", "&editor.foreground"], disableEditing: true)]

  builder.addBuilderFor IdPrint, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: "(", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdPrintArguments, separator: ",".some, placeholder: "".some, uiFlags: &{LayoutHorizontal}, flags: 0.CellFlags),
    CellBuilderCommand(kind: ConstantCell, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  ]

  builder.addBuilderFor IdBuildString, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, disableEditing: true),
    CellBuilderCommand(kind: ConstantCell, text: "(", flags: &{NoSpaceLeft, NoSpaceRight}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdBuildArguments, separator: ",".some, placeholder: "".some, uiFlags: &{LayoutHorizontal}, flags: 0.CellFlags),
    CellBuilderCommand(kind: ConstantCell, text: ")", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  ]

  var typeComputers = initTable[ClassId, TypeComputer]()
  var valueComputers = initTable[ClassId, ValueComputer]()
  var scopeComputers = initTable[ClassId, ScopeComputer]()
  var validationComputers = initTable[ClassId, ValidationComputer]()

  defineComputerHelpers(typeComputers, valueComputers, scopeComputers, validationComputers)

  let metaTypeInstance = newAstNode(metaTypeClass, IdMetaTypeInstance.some)
  let stringTypeInstance = newAstNode(stringTypeClass, IdStringTypeInstance.some)
  let int32TypeInstance = newAstNode(int32TypeClass, IdInt32TypeInstance.some)
  let uint32TypeInstance = newAstNode(uint32TypeClass, IdUint32TypeInstance.some)
  let int64TypeInstance = newAstNode(int64TypeClass, IdInt64TypeInstance.some)
  let uint64TypeInstance = newAstNode(uint64TypeClass, IdUint64TypeInstance.some)
  let float32TypeInstance = newAstNode(float32TypeClass, IdFloat32TypeInstance.some)
  let float64TypeInstance = newAstNode(float64TypeClass, IdFloat64TypeInstance.some)
  let voidTypeInstance = newAstNode(voidTypeClass, IdVoidTypeInstance.some)
  let charTypeInstance = newAstNode(charTypeClass, IdCharTypeInstance.some)

  discard repository.registerNode(metaTypeInstance)
  discard repository.registerNode(stringTypeInstance)
  discard repository.registerNode(int32TypeInstance)
  discard repository.registerNode(uint32TypeInstance)
  discard repository.registerNode(int64TypeInstance)
  discard repository.registerNode(uint64TypeInstance)
  discard repository.registerNode(float32TypeInstance)
  discard repository.registerNode(float64TypeInstance)
  discard repository.registerNode(voidTypeInstance)
  discard repository.registerNode(charTypeInstance)

  typeComputer(metaTypeClass.id, metaTypeInstance)
  typeComputer(stringTypeClass.id, metaTypeInstance)
  typeComputer(int32TypeClass.id, metaTypeInstance)
  typeComputer(uint32TypeClass.id, metaTypeInstance)
  typeComputer(int64TypeClass.id, metaTypeInstance)
  typeComputer(uint64TypeClass.id, metaTypeInstance)
  typeComputer(float32TypeClass.id, metaTypeInstance)
  typeComputer(float64TypeClass.id, metaTypeInstance)
  typeComputer(charTypeClass.id, metaTypeInstance)
  typeComputer(voidTypeClass.id, metaTypeInstance)
  typeComputer(pointerTypeClass.id, metaTypeInstance)
  typeComputer(pointerTypeDeclClass.id, metaTypeInstance)

  valueComputer(metaTypeClass.id, metaTypeInstance)
  valueComputer(stringTypeClass.id, stringTypeInstance)
  valueComputer(int32TypeClass.id, int32TypeInstance)
  valueComputer(uint32TypeClass.id, uint32TypeInstance)
  valueComputer(int64TypeClass.id, int64TypeInstance)
  valueComputer(uint64TypeClass.id, uint64TypeInstance)
  valueComputer(float32TypeClass.id, float32TypeInstance)
  valueComputer(float64TypeClass.id, float64TypeInstance)
  valueComputer(charTypeClass.id, charTypeInstance)
  valueComputer(voidTypeClass.id, voidTypeInstance)

  valueComputer(pointerTypeClass.id):
    # debugf"compute value for pointer type {node}"
    return node

  # valueComputers[pointerTypeDeclClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode {.gcsafe, raises: [CatchableError].} =
  valueComputer(pointerTypeDeclClass.id):
    # debugf"compute value for pointer type {node}"

    if node.firstChild(IdPointerTypeDeclTarget).getSome(targetTypeNode):
      var typ = newAstNode(pointerTypeClass)
      if ctx.getValue(targetTypeNode).isNotNil(targetType):
        typ.setReference(IdPointerTypeTarget, targetType.id)

      node.model.addTempNode(typ)
      return typ

    return voidTypeInstance

  validationComputer(pointerTypeDeclClass.id):
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
  typeComputer(expressionClass.id):
    # debugf"compute type for base expression {node}"
    return voidTypeInstance

  valueComputer(expressionClass.id):
    # debugf"compute value for base expression {node}"
    return nil

  # literals
  typeComputer(stringLiteralClass.id):
    # debugf"compute type for string literal {node}"
    return stringTypeInstance

  valueComputer(stringLiteralClass.id):
    # debugf"compute value for string literal {node}"
    return node

  typeComputer(numberLiteralClass.id):
    # debugf"compute type for number literal {node}"
    if node.property(IdIntegerLiteralValue).getSome(value):
      # if value.intValue.safeIntCast(uint64) > int64.high.uint64:
      #   return uint64TypeInstance
      if value.intValue < int32.low or value.intValue > int32.high:
        return int64TypeInstance
    return int32TypeInstance

  valueComputer(numberLiteralClass.id):
    # debugf"compute value for number literal {node}"
    return node

  typeComputer(boolLiteralClass.id):
    # debugf"compute type for bool literal {node}"
    return int32TypeInstance

  valueComputer(boolLiteralClass.id):
    # debugf"compute value for bool literal {node}"
    return node

  typeComputer(emptyLineClass.id):
    # debugf"compute type for empty line {node}"
    return voidTypeInstance

  # declarations
  typeComputer(genericTypeClass.id):
    # debugf"compute type for generic type {node}"
    return metaTypeInstance

  valueComputer(genericTypeClass.id):
    # debugf"compute value for generic type {node}"
    if node.resolveReference(IdGenericTypeValue).getSome(valueNode):
      return ctx.getValue(valueNode)
    return node

  validationComputer(genericTypeClass.id):
    # debugf"validate generic type {node}"

    # if not ctx.validateChildType(node, IdGenericTypeValue, metaTypeInstance):
    #   return false

    return true

  typeComputer(letDeclClass.id):
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

  validationComputer(letDeclClass.id):
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

  typeComputer(varDeclClass.id):
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

  validationComputer(varDeclClass.id):
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

  typeComputer(constDeclClass.id):
    # debugf"compute type for const decl {node}"
    if node.firstChild(IdConstDeclType).getSome(typeNode):
      return ctx.getValue(typeNode)
    if node.firstChild(IdConstDeclValue).getSome(valueNode):
      return ctx.computeType(valueNode)
    return voidTypeInstance

  valueComputer(constDeclClass.id):
    # debugf"compute value for const decl {node}"
    if node.firstChild(IdConstDeclValue).getSome(valueNode):
      return ctx.getValue(valueNode)
    return nil

  validationComputer(constDeclClass.id):
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

  typeComputer(parameterDeclClass.id):
    # debugf"compute type for parameter decl {node}"
    if node.firstChild(IdParameterDeclType).getSome(typeNode):
      return ctx.getValue(typeNode)
    if node.firstChild(IdParameterDeclValue).getSome(valueNode):
      return ctx.computeType(valueNode)
    return voidTypeInstance

  valueComputer(parameterDeclClass.id):
    # debugf"compute value for parameter decl {node}"
    if node.firstChild(IdParameterDeclValue).getSome(valueNode):
      return ctx.getValue(valueNode)
    if node.firstChild(IdParameterDeclType).getSome(typeNode):
      let typ = ctx.getValue(typeNode)
      if typ.isNotNil and typ.class == IdType:
        var genericType = newAstNode(genericTypeClass)
        let name = node.property(IdINamedName).get.stringValue
        genericType.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: name))
        node.model.addTempNode(genericType)
        return genericType

    return nil

  validationComputer(parameterDeclClass.id):
    # debugf"validate parameter decl {node}"

    if node.firstChild(IdParameterDeclType).getSome(typeNode):
      if not ctx.validateNodeType(typeNode, metaTypeInstance):
        return false

      let expectedType = ctx.getValue(typeNode)

      if not ctx.validateChildType(node, IdParameterDeclValue, expectedType):
        return false

    return true

  # control flow
  typeComputer(whileClass.id):
    # debugf"compute type for while loop {node}"
    return voidTypeInstance

  validationComputer(whileClass.id):
    # debugf"validate while {node}"

    if not ctx.validateHasChild(node, IdWhileExpressionCondition):
      return false

    if not ctx.validateChildType(node, IdWhileExpressionCondition, int32TypeInstance):
      return false

    return true

  typeComputer(forLoopClass.id):
    # debugf"compute type for for loop {node}"
    return voidTypeInstance

  typeComputer(thenCaseClass.id):
    # debugf"compute type for then case {node}"
    if node.firstChild(IdThenCaseBody).getSome(body):
      return ctx.computeType(body)
    return voidTypeInstance

  validationComputer(thenCaseClass.id):
    # debugf"validate then case {node}"

    if not ctx.validateHasChild(node, IdThenCaseCondition):
      return false

    if not ctx.validateChildType(node, IdThenCaseCondition, int32TypeInstance):
      return false

    return true

  typeComputer(ifClass.id):
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

  typeComputer(IdFunctionType):
    return metaTypeInstance

  valueComputer(IdFunctionType):
    var functionType = newAstNode(functionTypeClass)

    if node.firstChild(IdFunctionTypeReturnType).getSome(c):
      var parameterType = ctx.getValue(c) ?? voidTypeInstance
      functionType.add(IdFunctionTypeReturnType, parameterType)
    else:
      functionType.add(IdFunctionTypeReturnType, voidTypeInstance)

    for _, c in node.children(IdFunctionTypeParameterTypes):
      var parameterType = ctx.getValue(c) ?? voidTypeInstance
      functionType.add(IdFunctionTypeParameterTypes, parameterType)

    node.model.addTempNode(functionType)

    return functionType

  # function import
  typeComputer(IdFunctionImport):
    # debugf"compute type for function import {node}"
    let functionTypeNode = node.firstChild(IdFunctionImportType).getOr:
      return voidTypeInstance

    return ctx.getValue(functionTypeNode)

  valueComputer(IdFunctionImport):
    # debugf"compute value for function import {node}"
    return node

  # function definition
  typeComputer(functionDefinitionClass.id):
    # debugf"compute type for function definition {node}"
    # defer:
    #   debugf"-> {result}"

    if not node.hasChild(IdFunctionDefinitionBody):
      return metaTypeInstance

    return ctx.computeFunctionDefinitionType(node)

  # function definition
  valueComputer(functionDefinitionClass.id):
    # debugf"compute value for function definition {node}"
    # defer:
    #   debugf"-> {result}"

    if not node.hasChild(IdFunctionDefinitionBody):
      return ctx.computeFunctionDefinitionType(node)

    return node

  typeComputer(assignmentClass.id):
    # debugf"compute type for assignment {node}"
    return voidTypeInstance

  validationComputer(assignmentClass.id):
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

  typeComputer(emptyClass.id):
    # debugf"compute type for empty {node}"
    return voidTypeInstance

  typeComputer(nodeListClass.id):
    # debugf"compute type for node list {node}"

    if node.firstChild(IdNodeListChildren).getSome(childNode):
      return ctx.computeType(childNode)

    return voidTypeInstance

  typeComputer(blockClass.id):
    # debugf"compute type for block {node}"

    # todo: maybe find better way to ignore empty line nodes
    var lastChild: AstNode = nil
    for _, child in node.children(IdBlockChildren):
      if child.class != IdEmptyLine:
        lastChild = child

    if lastChild.isNotNil:
      return ctx.computeType(lastChild)

    return voidTypeInstance

  typeComputer(castClass.id):
    # debugf"compute type for node reference {node}"
    if node.firstChild(IdCastType).getSome(typeNode):
      return ctx.getValue(typeNode)
    return voidTypeInstance

  typeComputer(nodeReferenceClass.id):
    # debugf"compute type for node reference {node}"
    if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
      return ctx.computeType(targetNode)
    return voidTypeInstance

  valueComputer(nodeReferenceClass.id):
    # debugf"compute value for node reference {node}"
    if node.resolveReference(IdNodeReferenceTarget).getSome(targetNode):
      return ctx.getValue(targetNode)
    if node.reference(IdNodeReferenceTarget) != NodeId.default:
      log lvlError, fmt"Couldn't resolve reference {node}"
    return nil

  validationComputer(nodeReferenceClass.id):
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

  typeComputer(breakClass.id):
    # debugf"compute type for break {node}"
    return voidTypeInstance

  typeComputer(continueClass.id):
    # debugf"compute type for continue {node}"
    return voidTypeInstance

  typeComputer(returnClass.id):
    # debugf"compute type for return {node}"
    return voidTypeInstance

  # binary expressions
  typeComputer(addExpressionClass.id):
    # debugf"compute type for add {node}"
    if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
      return ctx.getBiggerIntType(left, right)
    return int32TypeInstance

  typeComputer(subExpressionClass.id):
    # debugf"compute type for sub {node}"
    if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
      return ctx.getBiggerIntType(left, right)
    return int32TypeInstance

  typeComputer(mulExpressionClass.id):
    # debugf"compute type for mul {node}"
    if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
      return ctx.getBiggerIntType(left, right)
    return int32TypeInstance

  typeComputer(divExpressionClass.id):
    # debugf"compute type for div {node}"
    if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
      return ctx.getBiggerIntType(left, right)
    return int32TypeInstance

  typeComputer(modExpressionClass.id):
    # debugf"compute type for mod {node}"
    if node.firstChild(IdBinaryExpressionLeft).getSome(left) and node.firstChild(IdBinaryExpressionRight).getSome(right):
      return ctx.getBiggerIntType(left, right)
    return int32TypeInstance

  typeComputer(lessExpressionClass.id):
    # debugf"compute type for less {node}"
    return int32TypeInstance

  typeComputer(lessEqualExpressionClass.id):
    # debugf"compute type for less equal {node}"
    return int32TypeInstance

  typeComputer(greaterExpressionClass.id):
    # debugf"compute type for greater {node}"
    return int32TypeInstance

  typeComputer(greaterEqualExpressionClass.id):
    # debugf"compute type for greater equal {node}"
    return int32TypeInstance

  typeComputer(equalExpressionClass.id):
    # debugf"compute type for equal {node}"
    return int32TypeInstance

  typeComputer(notEqualExpressionClass.id):
    # debugf"compute type for not equal {node}"
    return int32TypeInstance

  typeComputer(andExpressionClass.id):
    # debugf"compute type for and {node}"
    return int32TypeInstance

  typeComputer(orExpressionClass.id):
    # debugf"compute type for or {node}"
    return int32TypeInstance

  typeComputer(orderExpressionClass.id):
    # debugf"compute type for order {node}"
    return int32TypeInstance

  # unary expressions
  typeComputer(negateExpressionClass.id):
    # debugf"compute type for negate {node}"
    return int32TypeInstance

  typeComputer(notExpressionClass.id):
    # debugf"compute type for not {node}"
    return int32TypeInstance

  # calls
  typeComputer(callClass.id):
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
          let concreteFunction = ctx.instantiateFunction(targetValue, node.children(IdCallArguments), nodeReferenceClass)
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
  valueComputer(callClass.id):
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
      let concreteType = ctx.instantiateStruct(targetValue, node.children(IdCallArguments), nodeReferenceClass)
      return concreteType

    return nil

  validationComputer(callClass.id):
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
        let concreteFunction = ctx.instantiateFunction(targetValue, arguments, nodeReferenceClass)
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

  typeComputer(appendStringExpressionClass.id):
    # debugf"compute type for append string {node}"
    return voidTypeInstance

  typeComputer(printExpressionClass.id):
    # debugf"compute type for print {node}"
    return voidTypeInstance

  typeComputer(buildExpressionClass.id):
    # debugf"compute type for build {node}"
    return stringTypeInstance

  typeComputer(structParameterClass.id):
    # debugf"compute type for struct parameter {node}"

    if node.firstChild(IdStructParameterType).getSome(typeNode):
      return ctx.getValue(typeNode)

    return voidTypeInstance

  valueComputer(structParameterClass.id):
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

  typeComputer(structMemberDefinitionClass.id):
    # debugf"compute type for struct member definition {node}"

    if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
      return ctx.getValue(typeNode)

    return voidTypeInstance

  typeComputer(structDefinitionClass.id):
    # debugf"compute type for struct definition {node}"

    return metaTypeInstance

  valueComputer(structDefinitionClass.id):
    # debugf"compute value for struct definition {node}"

    return node

  typeComputer(structMemberAccessClass.id):
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

  validationComputer(structMemberAccessClass.id):
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

  typeComputer(structMemberDefinitionClass.id):
    # debugf"compute type for struct member definition {node}"

    if node.firstChild(IdStructMemberDefinitionType).getSome(typeNode):
      return ctx.getValue(typeNode)

    return voidTypeInstance

  typeComputer(allocateClass.id):
    # debugf"compute type for allocate {node}"

    if node.firstChild(IdAllocateType).getSome(typeNode):
      let targetType = ctx.getValue(typeNode)
      var typ = newAstNode(pointerTypeClass)
      typ.setReference(IdPointerTypeTarget, targetType.id)
      node.model.addTempNode(typ)
      return typ

    return voidTypeInstance

  typeComputer(addressOfClass.id):
    # debugf"compute type for address of {node}"

    if node.firstChild(IdAddressOfValue).getSome(valueNode):
      let targetType = ctx.computeType(valueNode)
      var typ = newAstNode(pointerTypeClass)
      typ.setReference(IdPointerTypeTarget, targetType.id)
      node.model.addTempNode(typ)
      return typ

    return voidTypeInstance

  typeComputer(derefClass.id):
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

  typeComputer(stringGetPointerClass.id):
    # debugf"compute type for deref {node}"
    var typ = newAstNode(pointerTypeClass)
    typ.setReference(IdPointerTypeTarget, charTypeInstance.id)
    node.model.addTempNode(typ)
    return typ

  typeComputer(stringGetLengthClass.id):
    # debugf"compute type for deref {node}"
    return int32TypeInstance

  typeComputer(arrayAccessClass.id):
    # debugf"compute type for deref {node}"

    if node.firstChild(IdArrayAccessValue).getSome(typeNode):
      let pointerType = ctx.computeType(typeNode)
      if pointerType.class == IdPointerType and pointerType.resolveReference(IdPointerTypeTarget).getSome(targetType):
        return targetType

    return voidTypeInstance

  # scope
  scopeComputer(structMemberAccessClass.id):
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

  scopeComputer(IdExpression):
    # debugf"compute scope for base expression {node}"
    return ctx.computeDefaultScope(node)

  scopeComputer(IdStructMemberDefinition):
    # debugf"compute scope for struct member {node}"
    return ctx.computeDefaultScope(node)

  scopeComputer(IdStructParameter):
    # debugf"compute scope for struct parameter {node}"
    return ctx.computeDefaultScope(node)

  scopeComputer(IdParameterDecl):
    # debugf"compute scope for parameter {node}"
    return ctx.computeDefaultScope(node)

  scopeComputer(IdThenCase):
    # debugf"compute scope for then case {node}"
    return ctx.computeDefaultScope(node)

  let baseInterfaces = newLanguage(IdBaseInterfaces, "BaseInterfaces", @[namedInterface, declarationInterface])
  builders.registerBuilder(IdBaseInterfaces, newCellBuilder(IdBaseInterfaces))

  let baseLanguage = newLanguage(IdBaseLanguage, "Base",
    @[
      # typeClass,
      metaTypeClass, stringTypeClass, charTypeClass, voidTypeClass, functionTypeClass, structTypeClass, pointerTypeClass, pointerTypeDeclClass,
      int32TypeClass, uint32TypeClass, int64TypeClass, uint64TypeClass, float32TypeClass, float64TypeClass,

      expressionClass, binaryExpressionClass, unaryExpressionClass, emptyLineClass, castClass, functionImportClass,
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
    ], typeComputers, valueComputers, scopeComputers, validationComputers,
    baseLanguages=[baseInterfaces],
    rootNodes=[
      int32TypeInstance, uint32TypeInstance, int64TypeInstance, uint64TypeInstance, float32TypeInstance, float64TypeInstance, stringTypeInstance, voidTypeInstance, charTypeInstance, metaTypeInstance
    ])

  builders.registerBuilder(IdBaseLanguage, builder)

  repository.registerLanguage(baseInterfaces)
  repository.registerLanguage(baseLanguage)
