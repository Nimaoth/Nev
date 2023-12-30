import std/[tables, strformat, options, os, sugar]
import misc/[id, util, custom_logger, custom_async, array_buffer, array_table]
import ui/node
import ast/[ast_ids, model, cells, cell_builder_database, base_language, generator_wasm, base_language_wasm]
import scripting/wasm
import lang_api, lang_language

logCategory "lang-builder"

proc createNodeClassFromLangDefinition*(classMap: var Table[ClassId, NodeClass], def: AstNode): Option[NodeClass] =
  if classMap.contains(def.id.ClassId):
    return classMap[def.id.ClassId].some

  # log lvlInfo, fmt"createNodeClassFromLangDefinition {def.dump(recurse=true)}"

  let name = def.property(IdINamedName).get.stringValue
  let alias = def.property(IdClassDefinitionAlias).get.stringValue

  let isAbstract = def.property(IdClassDefinitionAbstract).get.boolValue
  let isInterface = def.property(IdClassDefinitionInterface).get.boolValue
  let isFinal = def.property(IdClassDefinitionFinal).get.boolValue
  let canBeRoot = def.property(IdClassDefinitionCanBeRoot).get.boolValue
  let precedence = def.property(IdClassDefinitionPrecedence).get.intValue.int

  let substitutionProperty = if def.firstChild(IdClassDefinitionSubstitutionProperty).getSome(substitutionProperty):
    substitutionProperty.reference(IdRoleReferenceTarget).RoleId.some
  else:
    RoleId.none

  let substitutionReference = if def.firstChild(IdClassDefinitionSubstitutionReference).getSome(substitutionReference):
    substitutionReference.reference(IdRoleReferenceTarget).RoleId.some
  else:
    RoleId.none

  # use node id of the class definition node as class id
  var class = newNodeClass(def.id.ClassId, name, alias=alias,
    isAbstract=isAbstract, isInterface=isInterface, isFinal=isFinal, canBeRoot=canBeRoot,
    substitutionProperty=substitutionProperty, substitutionReference=substitutionReference, precedence=precedence)
  classMap[def.id.ClassId] = class

  for _, prop in def.children(IdClassDefinitionProperties):
    let propName = prop.property(IdINamedName).get.stringValue
    let typ = if prop.firstChild(IdPropertyDefinitionType).getSome(typ):
      if typ.class == IdPropertyTypeBool:
        PropertyType.Bool
      elif typ.class == IdPropertyTypeString:
        PropertyType.String
      elif typ.class == IdPropertyTypeNumber:
        PropertyType.Int
      else:
        log lvlError, fmt"Invalid property type specified for {prop}: {typ}"
        continue
    else:
      log lvlError, fmt"No property type specified for {prop}"
      continue

    class.properties.add PropertyDescription(id: prop.id.RoleId, role: propName, typ: typ)

  for _, reference in def.children(IdClassDefinitionReferences):
    let referenceName = reference.property(IdINamedName).get.stringValue
    let classId: ClassId = if reference.firstChild(IdReferenceDefinitionClass).getSome(classNode):
      assert classNode.class == IdClassReference
      if classNode.resolveReference(IdClassReferenceTarget).getSome(target):
        # use node id of the class definition node as class id
        target.id.ClassId
      else:
        log lvlError, fmt"No class specified for {reference}: {classNode}"
        continue
    else:
      log lvlError, fmt"No class specified for {reference}"
      continue

    class.references.add NodeReferenceDescription(id: reference.id.RoleId, role: referenceName, class: classId)

  for _, children in def.children(IdClassDefinitionChildren):
    let childrenName = children.property(IdINamedName).get.stringValue
    let classId: ClassId = if children.firstChild(IdChildrenDefinitionClass).getSome(classNode):
      assert classNode.class == IdClassReference
      if classNode.resolveReference(IdClassReferenceTarget).getSome(target):
        # use node id of the class definition node as class id
        target.id.ClassId
      else:
        log lvlError, fmt"No class specified for {children}: {classNode}"
        continue
    else:
      log lvlError, fmt"No class specified for {children}"
      continue

    let count = if children.firstChild(IdChildrenDefinitionCount).getSome(count):
      if count.class == IdCountZeroOrOne:
        ChildCount.ZeroOrOne
      elif count.class == IdCountOne:
        ChildCount.One
      elif count.class == IdCountZeroOrMore:
        ChildCount.ZeroOrMore
      elif count.class == IdCountOneOrMore:
        ChildCount.OneOrMore
      else:
        log lvlError, fmt"Invalid child count specified for {children}: {count}"
        continue
    else:
      log lvlError, fmt"No child count specified for {children}"
      continue

    class.children.add NodeChildDescription(id: children.id.RoleId, role: childrenName, class: classId, count: count)

  if def.firstChild(IdClassDefinitionBaseClass).getSome(baseClassReference):
    if baseClassReference.resolveReference(IdClassReferenceTarget).getSome(baseClassNode):
      if createNodeClassFromLangDefinition(classMap, baseClassNode).getSome(baseClass):
        class.base = baseClass
      else:
        log lvlError, fmt"Failed to create base class for {def}: {baseClassNode}"

  for _, interfaceReferenceNode in def.children(IdClassDefinitionInterfaces):
    if interfaceReferenceNode.resolveReference(IdClassReferenceTarget).getSome(interfaceNode):
      if createNodeClassFromLangDefinition(classMap, interfaceNode).getSome(interfaceClass):
        class.interfaces.add interfaceClass
      else:
        log lvlError, fmt"Failed to create base class for {def}: {interfaceNode}"

  # debugf"{class}"
  # print class

  return class.some

proc parseCellFlags*(nodes: openArray[AstNode]): tuple[cellFlags: CellFlags, uiFlags: UINodeFlags, disableEditing: bool, disableSelection: bool, deleteNeighbor: bool] =
  for node in nodes:
    if node.class == IdCellFlagDeleteWhenEmpty: result.cellFlags = result.cellFlags + DeleteWhenEmpty
    elif node.class == IdCellFlagOnNewLine: result.cellFlags = result.cellFlags + OnNewLine
    elif node.class == IdCellFlagIndentChildren: result.cellFlags = result.cellFlags + IndentChildren
    elif node.class == IdCellFlagNoSpaceLeft: result.cellFlags = result.cellFlags + NoSpaceLeft
    elif node.class == IdCellFlagNoSpaceRight: result.cellFlags = result.cellFlags + NoSpaceRight
    elif node.class == IdCellFlagVertical: result.uiFlags = result.uiFlags + LayoutVertical
    elif node.class == IdCellFlagHorizontal: result.uiFlags = result.uiFlags + LayoutHorizontal
    elif node.class == IdCellFlagDisableEditing: result.disableEditing = true
    elif node.class == IdCellFlagDisableSelection: result.disableSelection = true
    elif node.class == IdCellFlagDeleteNeighbor: result.deleteNeighbor = true
    elif node.class == IdCellFlag: discard
    else:
      log lvlError, fmt"Invalid cell flag: {node}"

proc createCellBuilderCommandFromDefinition(builder: CellBuilder, def: AstNode, commands: var seq[CellBuilderCommand], isRoot: bool = false): bool =
  let shadowText = if def.property(IdCellDefinitionShadowText).getSome(shadowText):
    shadowText.stringValue
  else:
    ""

  let (cellFlags, uiFlags, disableEditing, disableSelection, deleteNeighbor)  = def.children(IdCellDefinitionCellFlags).parseCellFlags

  result = true

  var foregroundColors: seq[string] = @[]
  var backgroundColors: seq[string] = @[]
  for _, colorNode in def.children(IdCellDefinitionForegroundColor):
    if colorNode.class == IdColorDefinitionText:
      foregroundColors.add colorNode.property(IdColorDefinitionTextScope).get.stringValue
    else:
      log lvlError, fmt"Invalid theme foreground color: {colorNode}"
      return false

  for _, colorNode in def.children(IdCellDefinitionBackgroundColor):
    if colorNode.class == IdColorDefinitionText:
      backgroundColors.add colorNode.property(IdColorDefinitionTextScope).get.stringValue
    else:
      log lvlError, fmt"Invalid theme foreground color: {colorNode}"
      return false

  if def.class == IdHorizontalCellDefinition:
    commands.add CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal} + uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
      themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    for _, c in def.children(IdCollectionCellDefinitionChildren):
      if not createCellBuilderCommandFromDefinition(builder, c, commands):
        return false
    if not isRoot:
      commands.add CellBuilderCommand(kind: EndCollectionCell)

  elif def.class == IdVerticalCellDefinition:
    commands.add CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical} + uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
      themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    for _, c in def.children(IdCollectionCellDefinitionChildren):
      if not createCellBuilderCommandFromDefinition(builder, c, commands):
        return false
    if not isRoot:
      commands.add CellBuilderCommand(kind: EndCollectionCell)

  elif def.class == IdConstantCellDefinition:
    let text = def.property(IdConstantCellDefinitionText).get.stringValue
    commands.add CellBuilderCommand(kind: ConstantCell, text: text, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
      themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)

  elif def.class == IdAliasCellDefinition:
    commands.add CellBuilderCommand(kind: AliasCell, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
      themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)

  elif def.class == IdReferenceCellDefinition:
    let targetProperty = def.firstChild(IdReferenceCellDefinitionTargetProperty).mapIt(it.reference(IdRoleReferenceTarget).RoleId)

    if def.firstChild(IdReferenceCellDefinitionRole).getSome(referenceRoleNode):
      let referenceRole = referenceRoleNode.reference(IdRoleReferenceTarget).RoleId
      commands.add CellBuilderCommand(kind: ReferenceCell, referenceRole: referenceRole, targetProperty: targetProperty, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText,
        disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
        themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    else:
      log lvlError, fmt"Missing role for property definition: {def}"
      return false

  elif def.class == IdPropertyCellDefinition:
    if def.firstChild(IdPropertyCellDefinitionRole).getSome(propertyRoleNode):
      let propertyRole = propertyRoleNode.reference(IdRoleReferenceTarget).RoleId
      commands.add CellBuilderCommand(kind: PropertyCell, propertyRole: propertyRole, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
        themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    else:
      log lvlError, fmt"Missing role for property definition: {def}"
      return false

  elif def.class == IdChildrenCellDefinition:
    if def.firstChild(IdChildrenCellDefinitionRole).getSome(childRoleNode):
      let childRole = childRoleNode.reference(IdRoleReferenceTarget).RoleId
      commands.add CellBuilderCommand(kind: Children, childrenRole: childRole, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
        themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    else:
      log lvlError, fmt"Missing role for children definition: {def}"
      return false

  else:
    log lvlError, fmt"Invalid cell definition: {def}"
    return false

proc createCellBuilderFromDefinition(builder: CellBuilder, def: AstNode): bool =
  let targetClass = def.reference(IdCellBuilderDefinitionClass)
  var commands: seq[CellBuilderCommand] = @[]

  for _, c in def.children(IdCellBuilderDefinitionCellDefinitions):
    if not builder.createCellBuilderCommandFromDefinition(c, commands, true):
      return false

  builder.addBuilderFor targetClass.ClassId, idNone(), commands

  return true

##### temp stuff
var lineBuffer {.global.} = ""

proc printI32(a: int32) =
  if lineBuffer.len > 0:
    lineBuffer.add " "
  lineBuffer.add $a

proc printU32(a: uint32) =
  if lineBuffer.len > 0:
    lineBuffer.add " "
  lineBuffer.add $a

proc printI64(a: int64) =
  if lineBuffer.len > 0:
    lineBuffer.add " "
  lineBuffer.add $a

proc printU64(a: uint64) =
  if lineBuffer.len > 0:
    lineBuffer.add " "
  lineBuffer.add $a

proc printF32(a: float32) =
  if lineBuffer.len > 0:
    lineBuffer.add " "
  lineBuffer.add $a

proc printF64(a: float64) =
  if lineBuffer.len > 0:
    lineBuffer.add " "
  lineBuffer.add $a

proc printChar(a: int32) =
  lineBuffer.add $a.char

proc printString(a: cstring, len: int32) =
  let str = $a
  assert len <= a.len
  lineBuffer.add str[0..<len]

proc printLine() =
  log lvlInfo, lineBuffer
  lineBuffer = ""

proc intToString(a: int32): cstring =
  let res = $a
  return res.cstring

##### end of temp stuff

proc createScopeComputerFromNode*(class: ClassId, functionNode: AstNode, module: WasmModule, scopeComputers: var Table[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]) =
  let name = $functionNode.id
  if module.findFunction(name, void, proc(arrPtr: WasmPtr, node: WasmPtr)).getSome(computeScopeImpl):
    proc computeScopeImplWrapper(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
      let sp = module.stackSave()
      defer:
        module.stackRestore(sp)

      let index = gNodeRegistry.getNodeIndex(node)

      let arrPtr: WasmPtr = module.stackAlloc(4 * 3)
      let indexPtr: WasmPtr = module.stackAlloc(4)
      module.setInt32(indexPtr, index)
      computeScopeImpl(arrPtr, indexPtr)

      let resultLen = module.getInt32(arrPtr)
      let resultPtr = module.getInt32(arrPtr + 8).WasmPtr

      var nodes = newSeqOfCap[AstNode](resultLen)
      for i in 0..<resultLen:
        let nodeIndex = module.getInt32(resultPtr + i * 4)
        if gNodeRegistry.getNode(nodeIndex).getSome(node):
          nodes.add node
        else:
          log lvlError, fmt"Invalid node index returned from scope function: {nodeIndex}"

      return nodes

    scopeComputers[class] = computeScopeImplWrapper


proc updateLanguageFromModel*(language: Language, model: Model, updateBuilder: bool = true, ctx = ModelComputationContextBase.none): Future[bool] {.async.} =
  log lvlInfo, fmt"updateLanguageFromModel {model.path} ({model.id})"
  var classMap = initTable[ClassId, NodeClass]()
  var classes: seq[NodeClass] = @[]
  var builder = newCellBuilder(language.id)

  var propertyValidators = newSeq[tuple[classId: ClassId, roleId: RoleId, functionNode: AstNode]]()
  var scopeDefinitions = newSeq[tuple[classId: ClassId, functionNode: AstNode]]()

  for def in model.rootNodes:
    for _, c in def.children(IdLangRootChildren):
      if c.class == IdClassDefinition:
        if createNodeClassFromLangDefinition(classMap, c).getSome(class):
          classes.add class
        else:
          log lvlError, fmt"Failed to create class for {c}"
          return false
      if updateBuilder and c.class == IdCellBuilderDefinition:
        if not builder.createCellBuilderFromDefinition(c):
          return false

      if c.class == IdPropertyValidatorDefinition:
        let functionNode = c.firstChild(IdPropertyValidatorDefinitionImplementation).getOr:
          log lvlError, fmt"Missing function for property validator: {c}"
          continue

        if functionNode.class != IdFunctionDefinition:
          log lvlError, fmt"Invalid function for property validator: {functionNode}"
          continue

        let classId = c.reference(IdPropertyValidatorDefinitionClass).ClassId
        if functionNode.class != IdFunctionDefinition:
          log lvlError, fmt"Invalid function for property validator: {functionNode}"
          continue

        let propertyRoleReference = c.firstChild(IdPropertyValidatorDefinitionProperty).getOr:
          log lvlError, fmt"Missing property role for property validator: {c}"
          continue

        let roleId = propertyRoleReference.reference(IdRoleReferenceTarget).RoleId
        propertyValidators.add (classId, roleId, functionNode)

      if c.class == IdScopeDefinition:
        let functionNode = c.firstChild(IdScopeDefinitionImplementation).getOr:
          log lvlError, fmt"Missing function for scope: {c}"
          continue

        if functionNode.class != IdFunctionDefinition:
          log lvlError, fmt"Invalid function for scope: {functionNode}"
          continue

        let classId = c.reference(IdScopeDefinitionClass).ClassId
        if functionNode.class != IdFunctionDefinition:
          log lvlError, fmt"Invalid function for scope: {functionNode}"
          continue

        scopeDefinitions.add (classId, functionNode)

  let wasmModule = if ctx.getSome(ctx):
    measureBlock fmt"Compile language model '{model.path}' to wasm":
      var compiler = newBaseLanguageWasmCompiler(ctx)
      compiler.addBaseLanguage()

      for (_, _, functionNode) in propertyValidators:
        compiler.addFunctionToCompile(functionNode)

      for (_, functionNode) in scopeDefinitions:
        compiler.addFunctionToCompile(functionNode)

      let binary = compiler.compileToBinary()

    var imports = newSeq[WasmImports]()

    var imp = WasmImports(namespace: "env")
    imp.addFunction("print_i32", printI32)
    imp.addFunction("print_u32", printU32)
    imp.addFunction("print_i64", printI64)
    imp.addFunction("print_u64", printU64)
    imp.addFunction("print_f32", printF32)
    imp.addFunction("print_f64", printF64)
    imp.addFunction("print_char", printChar)
    imp.addFunction("print_string", printString)
    imp.addFunction("print_line", printLine)
    imp.addFunction("intToString", intToString)
    imports.add imp

    imports.add getLangApiImports()

    measureBlock fmt"Create wasm module for language '{model.path}'":
      let module = await newWasmModule(binary.toArrayBuffer, imports)
      if module.isNone:
        log lvlError, fmt"Failed to create wasm module from generated binary for {model.path}"

    module

  else:
    WasmModule.none

  var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
  var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
  var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
  var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

  if wasmModule.getSome(module):
    for (class, functionNode) in scopeDefinitions:
      capture class, functionNode:
        createScopeComputerFromNode(class, functionNode, module, scopeComputers)
  language.update(classes, typeComputers, valueComputers, scopeComputers, validationComputers)

  if wasmModule.getSome(module):
    for (class, role, functionNode) in propertyValidators:
      capture class, role, functionNode:
        let name = $functionNode.id
        if module.findFunction(name, bool, proc(node: WasmPtr, a: string): bool).getSome(validateImpl):
          let validator = if not language.validators.contains(class):
            let validator = NodeValidator()
            language.validators[class] = validator
            validator
          else:
            language.validators[class]

          proc validateImplWrapper(node: Option[AstNode], propertyValue: string): bool =
            let sp = module.stackSave()
            defer:
              module.stackRestore(sp)

            let p: WasmPtr = module.stackAlloc(4)
            let index: int32 = if node.getSome(node):
              gNodeRegistry.getNodeIndex(node)
            else:
              0
            module.setInt32(p, index)
            validateImpl(p, propertyValue)

          # debugf"register propertyy validator for {class}, {role}"
          validator.propertyValidators[role] = PropertyValidator(kind: Custom, impl: validateImplWrapper)

  if updateBuilder:
    registerBuilder(language.id, builder)

  return true

proc createLanguageFromModel*(model: Model, ctx = ModelComputationContextBase.none): Future[Language] {.async.} =
  log lvlInfo, fmt"createLanguageFromModel {model.path} ({model.id})"

  let name = model.path.splitFile.name
  let language = newLanguage(model.id.LanguageId, name)
  if not language.updateLanguageFromModel(model, ctx = ctx).await:
    return Language nil
  return language

proc createNodeFromNodeClass(classes: var Table[ClassId, AstNode], class: NodeClass): AstNode =
  # log lvlInfo, fmt"createNodeFromNodeClass {class.name}"

  result = newAstNode(classDefinitionClass, class.id.NodeId.some)
  # classes[class.id] = result

  result.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: class.name))
  result.setProperty(IdClassDefinitionAlias, PropertyValue(kind: String, stringValue: class.alias))

  result.setProperty(IdClassDefinitionAbstract, PropertyValue(kind: Bool, boolValue: class.isAbstract))
  result.setProperty(IdClassDefinitionInterface, PropertyValue(kind: Bool, boolValue: class.isInterface))
  result.setProperty(IdClassDefinitionFinal, PropertyValue(kind: Bool, boolValue: class.isFinal))
  result.setProperty(IdClassDefinitionCanBeRoot, PropertyValue(kind: Bool, boolValue: class.canBeRoot))
  result.setProperty(IdClassDefinitionPrecedence, PropertyValue(kind: Int, intValue: class.precedence))

  if class.base.isNotNil:
    var baseClass = newAstNode(classReferenceClass)
    baseClass.setReference(IdClassReferenceTarget, class.base.id.NodeId)
    result.add(IdClassDefinitionBaseClass, baseClass)

  for class in class.interfaces:
    var baseClass = newAstNode(classReferenceClass)
    baseClass.setReference(IdClassReferenceTarget, class.id.NodeId)
    result.add(IdClassDefinitionInterfaces, baseClass)

  if class.substitutionProperty.getSome(property):
    var roleReference = newAstNode(roleReferenceClass)
    roleReference.setReference(IdRoleReferenceTarget, property.NodeId)
    result.add(IdClassDefinitionSubstitutionProperty, roleReference)

  if class.substitutionReference.getSome(property):
    var roleReference = newAstNode(roleReferenceClass)
    roleReference.setReference(IdRoleReferenceTarget, property.NodeId)
    result.add(IdClassDefinitionSubstitutionReference, roleReference)

  for property in class.properties:
    var propertyNode = newAstNode(propertyDefinitionClass, property.id.NodeId.some)
    propertyNode.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: property.role))

    let propertyTypeClass = if property.typ == Int:
      propertyTypeNumberClass
    elif property.typ == String:
      propertyTypeStringClass
    elif property.typ == Bool:
      propertyTypeBoolClass
    else:
      log lvlError, fmt"Invalid property type specified for {property}"
      return nil

    propertyNode.add(IdPropertyDefinitionType, newAstNode(propertyTypeClass))
    result.add(IdClassDefinitionProperties, propertyNode)

  for reference in class.references:
    var referenceNode = newAstNode(referenceDefinitionClass, reference.id.NodeId.some)
    referenceNode.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: reference.role))

    let classReference = newAstNode(classReferenceClass)
    classReference.setReference(IdClassReferenceTarget, reference.class.NodeId)
    referenceNode.add(IdReferenceDefinitionClass, classReference)

    result.add(IdClassDefinitionReferences, referenceNode)

  for children in class.children:
    var childrenNode = newAstNode(childrenDefinitionClass, children.id.NodeId.some)
    childrenNode.setProperty(IdINamedName, PropertyValue(kind: String, stringValue: children.role))

    let classReference = newAstNode(classReferenceClass)
    classReference.setReference(IdClassReferenceTarget, children.class.NodeId)
    childrenNode.add(IdChildrenDefinitionClass, classReference)

    let childrenCountClass = if children.count == ChildCount.ZeroOrOne:
      countZeroOrOneClass
    elif children.count == ChildCount.One:
      countOneClass
    elif children.count == ChildCount.ZeroOrMore:
      countZeroOrMoreClass
    elif children.count == ChildCount.OneOrMore:
      countOneOrMoreClass
    else:
      log lvlError, fmt"Invalid child count specified for {children}"
      return nil

    childrenNode.add(IdChildrenDefinitionCount, newAstNode(childrenCountClass))

    result.add(IdClassDefinitionChildren, childrenNode)

  # debugf"node {result.dump(recurse=true)}"

proc createModelForLanguage*(language: Language): Model =
  result = newModel(language.id.ModelId)
  result.addLanguage(lang_language.langLanguage)

  let root = newAstNode(langRootClass)
  var classes = initTable[ClassId, AstNode]()
  for class in language.classes.values:
    root.add IdLangRootChildren, createNodeFromNodeClass(classes, class)

  result.addRootNode(root)

let baseInterfacesModel* = createModelForLanguage(base_language.baseInterfaces)

let baseLanguageModel* = createModelForLanguage(base_language.baseLanguage)
baseLanguageModel.addImport(baseInterfacesModel)

let langLanguageModel* = createModelForLanguage(lang_language.langLanguage)
langLanguageModel.addImport(baseInterfacesModel)