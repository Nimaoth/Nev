import std/[tables, strformat, options]
import id, ast_ids, util, custom_logger
import ../model, ../cells, ../model_state, query_system
import ../base_language
import ui/node
import print
export id, ast_ids

logCategory "lang-language"

let propertyTypeClass* = newNodeClass(IdPropertyType, "PropertyType", isAbstract=true)
let propertyTypeBoolClass* = newNodeClass(IdPropertyTypeBool, "PropertyTypeBool", alias="bool", base=propertyTypeClass)
let propertyTypeStringClass* = newNodeClass(IdPropertyTypeString, "PropertyTypeString", alias="string", base=propertyTypeClass)
let propertyTypeNumberClass* = newNodeClass(IdPropertyTypeNumber, "PropertyTypeNumber", alias="number", base=propertyTypeClass)

let roleDescriptorInterface* = newNodeClass(IdIRoleDescriptor, "roleDescriptorInterface", isInterface=true, interfaces=[namedInterface])

let countClass* = newNodeClass(IdCount, "Count", isAbstract=true)
let countZeroOrOneClass* = newNodeClass(IdCountZeroOrOne, "CountZeroOrOne", alias="0..1", base=countClass)
let countOneClass* = newNodeClass(IdCountOne, "CountnOne", alias="1", base=countClass)
let countZeroOrMoreClass* = newNodeClass(IdCountZeroOrMore, "CountZeroOrMore", alias="0..n", base=countClass)
let countOneOrMoreClass* = newNodeClass(IdCountOneOrMore, "CountOneOrMore", alias="1..n", base=countClass)

let classReferenceClass* = newNodeClass(IdClassReference, "ClassReference",
  references=[
    NodeReferenceDescription(id: IdClassReferenceTarget, role: "class", class: IdClassDefinition),
    ])

let roleReferenceClass* = newNodeClass(IdRoleReference, "RoleReference",
  references=[
    NodeReferenceDescription(id: IdRoleReferenceTarget, role: "role", class: IdIRoleDescriptor),
    ])

let propertyDefinitionClass* = newNodeClass(IdPropertyDefinition, "PropertyDefinition", interfaces=[roleDescriptorInterface],
  children=[
    NodeChildDescription(id: IdPropertyDefinitionType, role: "type", class: IdPropertyType, count: ChildCount.One),
    ])

let referenceDefinitionClass* = newNodeClass(IdReferenceDefinition, "ReferenceDefinition", interfaces=[roleDescriptorInterface],
  children=[
    NodeChildDescription(id: IdReferenceDefinitionClass, role: "class", class: IdClassReference, count: ChildCount.One),
    ])

let childrenDefinitionClass* = newNodeClass(IdChildrenDefinition, "ChildrenDefinition", interfaces=[roleDescriptorInterface],
  children=[
    NodeChildDescription(id: IdChildrenDefinitionClass, role: "class", class: IdClassReference, count: ChildCount.One),
    NodeChildDescription(id: IdChildrenDefinitionCount, role: "count", class: IdCount, count: ChildCount.One),
    ])

let langAspectClass* = newNodeClass(IdLangAspect, "LangAspect", isAbstract=true)

let langRootClass* = newNodeClass(IdLangRoot, "LangRoot", canBeRoot=true,
  children=[NodeChildDescription(id: IdLangRootChildren, role: "children", class: IdLangAspect, count: ChildCount.ZeroOrMore)])

let classDefinitionClass* = newNodeClass(IdClassDefinition, "ClassDefinition", alias="class", base=langAspectClass, interfaces=[namedInterface],
  properties=[
    PropertyDescription(id: IdClassDefinitionAlias, role: "alias", typ: PropertyType.String),
    PropertyDescription(id: IdClassDefinitionAbstract, role: "abstract", typ: PropertyType.Bool),
    PropertyDescription(id: IdClassDefinitionInterface, role: "interface", typ: PropertyType.Bool),
    PropertyDescription(id: IdClassDefinitionFinal, role: "final", typ: PropertyType.Bool),
    PropertyDescription(id: IdClassDefinitionCanBeRoot, role: "can be root", typ: PropertyType.Bool),
    PropertyDescription(id: IdClassDefinitionPrecedence, role: "precedence", typ: PropertyType.Int),
  ],
  children=[
    NodeChildDescription(id: IdClassDefinitionBaseClass, role: "base", class: IdClassReference, count: ChildCount.ZeroOrOne),
    NodeChildDescription(id: IdClassDefinitionInterfaces, role: "interfaces", class: IdClassReference, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdClassDefinitionProperties, role: "properties", class: IdPropertyDefinition, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdClassDefinitionReferences, role: "references", class: IdReferenceDefinition, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdClassDefinitionChildren, role: "children", class: IdChildrenDefinition, count: ChildCount.ZeroOrMore),
    NodeChildDescription(id: IdClassDefinitionSubstitutionProperty, role: "substitution property", class: IdRoleReference, count: ChildCount.ZeroOrOne),
    ])

var builder = newCellBuilder()

builder.addBuilderFor IdPropertyTypeBool, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdPropertyTypeString, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdPropertyTypeNumber, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdCountZeroOrOne, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdCountOne, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdCountZeroOrMore, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdCountOneOrMore, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  return AliasCell(id: newId().CellId, node: node, themeForegroundColors: @["keyword"], disableEditing: true)

builder.addBuilderFor IdClassReference, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  if node.resolveReference(IdClassReferenceTarget).getSome(targetNode):
    return PropertyCell(id: newId().CellId, node: node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])
  else:
    return PlaceholderCell(id: newId().CellId, node: node, role: IdClassReferenceTarget, shadowText: "<class>")

builder.addBuilderFor IdRoleReference, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  if node.resolveReference(IdRoleReferenceTarget).getSome(targetNode):
    return PropertyCell(id: newId().CellId, node: node, referenceNode: targetNode, property: IdINamedName, themeForegroundColors: @["variable", "&editor.foreground"])
  else:
    return PlaceholderCell(id: newId().CellId, node: node, role: IdRoleReferenceTarget, shadowText: "<role>")

builder.addBuilderFor IdPropertyDefinition, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add PropertyCell(id: newId().CellId, node: node, property: IdINamedName, themeForegroundColors: @["variable"])
    cell.add ConstantCell(node: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdPropertyDefinitionType, &{LayoutHorizontal})

  return cell

builder.addBuilderFor IdReferenceDefinition, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add PropertyCell(id: newId().CellId, node: node, property: IdINamedName, themeForegroundColors: @["variable"])
    cell.add ConstantCell(node: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdReferenceDefinitionClass, &{LayoutHorizontal})

  return cell

builder.addBuilderFor IdChildrenDefinition, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add PropertyCell(id: newId().CellId, node: node, property: IdINamedName, themeForegroundColors: @["variable"])
    cell.add ConstantCell(node: node, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdChildrenDefinitionClass, &{LayoutHorizontal})
    cell.add ConstantCell(node: node, text: ",", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
    cell.add builder.buildChildren(map, node, IdChildrenDefinitionCount, &{LayoutHorizontal})

  return cell

builder.addBuilderFor IdLangRoot, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutVertical})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add block:
      buildChildrenT(builder, map, node, IdLangRootChildren, &{LayoutVertical}, 0.CellFlags):
        separator: ConstantCell(node: node, text: "", disableEditing: true, disableSelection: true)
        placeholder: "..."

  return cell

builder.addBuilderFor IdLangAspect, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  # return PlaceholderCell(id: newId().CellId, node: node, role: IdClassReferenceTarget, shadowText: "<class>")
  var cell = ConstantCell(id: newId().CellId, node: node, shadowText: "...", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"])
  return cell

builder.addBuilderFor IdClassDefinition, idNone(), proc(builder: CellBuilder, node: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: node, text: "class", themeForegroundColors: @["keyword"], disableEditing: true)

    cell.add PropertyCell(id: newId().CellId, node: node, property: IdINamedName, themeForegroundColors: @["variable"])

    cell.add ConstantCell(node: node, text: "as", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(id: newId().CellId, node: node, property: IdClassDefinitionAlias, themeForegroundColors: @["variable"])

    cell.add block:
      cell.add ConstantCell(node: node, text: "extends", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      buildChildrenT(builder, map, node, IdClassDefinitionBaseClass, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: "<base>"

    cell.add block:
      cell.add ConstantCell(node: node, text: "implements", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      buildChildrenT(builder, map, node, IdClassDefinitionInterfaces, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: "<interface>"

    cell.add ConstantCell(node: node, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    var vertCell = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren})

    vertCell.addHorizontal(node, 0.CellFlags):
      sub.add ConstantCell(node: node, text: "abstract", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: node, property: IdClassDefinitionAbstract, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: node, text: "interface", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: node, property: IdClassDefinitionInterface, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: node, text: "final", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: node, property: IdClassDefinitionFinal, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: node, text: "root", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: node, property: IdClassDefinitionCanBeRoot, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: node, text: "precedence", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: node, property: IdClassDefinitionPrecedence, themeForegroundColors: @["variable"])

    block:
      var sub = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
      sub.add ConstantCell(node: node, text: "properties:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      sub.add block:
        buildChildrenT(builder, map, node, IdClassDefinitionProperties, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
          placeholder: "..."

      if node.childCount(IdClassDefinitionProperties) > 0 or node.childCount(IdClassDefinitionReferences) > 0:
        vertCell.add sub
        sub = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})

      sub.add ConstantCell(node: node, text: "references:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      sub.add block:
        buildChildrenT(builder, map, node, IdClassDefinitionReferences, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
          placeholder: "..."

      if node.childCount(IdClassDefinitionReferences) > 0 or node.childCount(IdClassDefinitionChildren) > 0:
        vertCell.add sub
        sub = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})

      sub.add ConstantCell(node: node, text: "children:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      sub.add block:
        buildChildrenT(builder, map, node, IdClassDefinitionChildren, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
          placeholder: "..."

      vertCell.add sub

    let totalRoles = node.childCount(IdClassDefinitionProperties) + node.childCount(IdClassDefinitionReferences) + node.childCount(IdClassDefinitionChildren)
    if totalRoles > 0:
      vertCell.add block:
        var sub = CollectionCell(id: newId().CellId, node: node, uiFlags: &{LayoutHorizontal})
        sub.add ConstantCell(node: node, text: "substitution property:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
        sub.add block:
          buildChildrenT(builder, map, node, IdClassDefinitionSubstitutionProperty, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
            placeholder: "<role>"
        sub

    cell.add vertCell
    cell.add ConstantCell(node: node, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{OnNewLine})

  return cell

var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()

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

    if current.class == IdNodeList and current.parent.isNil:
      for _, c in current.children(IdNodeListChildren):
        ctx.dependOn(c)
        nodes.add c

    prev = current
    current = current.parent

  return nodes

scopeComputers[IdClassReference] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for class reference {node}"
  log lvlWarn, "uaie"
  var nodes: seq[AstNode] = @[]

  for model in node.model.models:
    echo "model ", model.id
    for root in model.rootNodes:
      echo "import root ", root
      for _, aspect in root.children(IdLangRootChildren):
        if aspect.class == IdClassDefinition:
          nodes.add aspect

  for root in node.model.rootNodes:
    echo "root ", root
    for _, aspect in root.children(IdLangRootChildren):
      if aspect.class == IdClassDefinition:
        nodes.add aspect

  return nodes

scopeComputers[IdClassDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for class definition {node}"
  var nodes: seq[AstNode] = @[]

  # todo: improve this
  for model in node.model.models:
    for root in model.rootNodes:
      for _, aspect in root.children(IdLangRootChildren):
        if aspect.class == IdClassDefinition:
          nodes.add aspect

  for root in node.model.rootNodes:
    for _, aspect in root.children(IdLangRootChildren):
      if aspect.class == IdClassDefinition:
        nodes.add aspect

  for _, prop in node.children(IdClassDefinitionProperties):
    nodes.add prop

  for _, reference in node.children(IdClassDefinitionReferences):
    nodes.add reference

  for _, children in node.children(IdClassDefinitionChildren):
    nodes.add children

  return nodes

scopeComputers[IdRoleReference] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for role reference {node}"
  var nodes: seq[AstNode] = @[]

  # todo: improve this
  var parent = node.parent
  while parent.isNotNil and parent.class != IdClassDefinition:
    parent = parent.parent

  if parent.isNil:
    return nodes

  for _, prop in parent.children(IdClassDefinitionProperties):
    nodes.add prop

  for _, reference in parent.children(IdClassDefinitionReferences):
    nodes.add reference

  for _, children in parent.children(IdClassDefinitionChildren):
    nodes.add children

  return nodes

let langLanguage* = newLanguage(IdLangLanguage, @[
  langRootClass, langAspectClass,
  roleDescriptorInterface,
  propertyTypeClass, propertyTypeBoolClass, propertyTypeStringClass, propertyTypeNumberClass, propertyDefinitionClass, classDefinitionClass,
  classReferenceClass, roleReferenceClass, referenceDefinitionClass, childrenDefinitionClass,
  countClass, countZeroOrOneClass, countOneClass, countZeroOrMoreClass, countOneOrMoreClass,
], builder, typeComputers, valueComputers, scopeComputers)

proc createNodeClassFromLangDefinition*(def: AstNode): Option[NodeClass] =
  log lvlInfo, fmt"createNodeClassFromLangDefinition {def.dump(recurse=true)}"
  let name = def.property(IdINamedName).get.stringValue
  let alias = def.property(IdClassDefinitionAlias).get.stringValue

  let isAbstract = def.property(IdClassDefinitionAbstract).get.boolValue
  let isInterface = def.property(IdClassDefinitionInterface).get.boolValue
  let isFinal = def.property(IdClassDefinitionFinal).get.boolValue
  let canBeRoot = def.property(IdClassDefinitionCanBeRoot).get.boolValue
  let precedence = def.property(IdClassDefinitionPrecedence).get.intValue

  var properties = newSeqOfCap[PropertyDescription](def.childCount(IdClassDefinitionProperties))
  var references = newSeqOfCap[NodeReferenceDescription](def.childCount(IdClassDefinitionReferences))
  var childDescriptions = newSeqOfCap[NodeChildDescription](def.childCount(IdClassDefinitionChildren))

  let substitutionProperty = if def.firstChild(IdClassDefinitionSubstitutionProperty).getSome(substitutionProperty):
    substitutionProperty.reference(IdRoleReferenceTarget).RoleId.some
  else:
    RoleId.none

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
        return NodeClass.none
    else:
      log lvlError, fmt"No property type specified for {prop}"
      return NodeClass.none

    properties.add PropertyDescription(id: prop.id.RoleId, role: propName, typ: typ)

  for _, reference in def.children(IdClassDefinitionReferences):
    let referenceName = reference.property(IdINamedName).get.stringValue
    let class: ClassId = if reference.firstChild(IdReferenceDefinitionClass).getSome(classNode):
      assert classNode.class == IdClassReference
      if classNode.resolveReference(IdClassReferenceTarget).getSome(target):
        # use node id of the class definition node as class id
        target.id.ClassId
      else:
        log lvlError, fmt"No class specified for {reference}: {classNode}"
        return NodeClass.none
    else:
      log lvlError, fmt"No class specified for {reference}"
      return NodeClass.none

    references.add NodeReferenceDescription(id: reference.id.RoleId, role: referenceName, class: class)

  for _, children in def.children(IdClassDefinitionChildren):
    let childrenName = children.property(IdINamedName).get.stringValue
    let class: ClassId = if children.firstChild(IdChildrenDefinitionClass).getSome(classNode):
      assert classNode.class == IdClassReference
      if classNode.resolveReference(IdClassReferenceTarget).getSome(target):
        # use node id of the class definition node as class id
        target.id.ClassId
      else:
        log lvlError, fmt"No class specified for {children}: {classNode}"
        return NodeClass.none
    else:
      log lvlError, fmt"No class specified for {children}"
      return NodeClass.none

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
        return NodeClass.none
    else:
      log lvlError, fmt"No child count specified for {children}"
      return NodeClass.none

    childDescriptions.add NodeChildDescription(id: children.id.RoleId, role: childrenName, class: class, count: count)

  let baseClass: NodeClass = nil # todo
  let interfaces: seq[NodeClass] = @[] # todo

  # use node id of the class definition node as class id
  let class = newNodeClass(def.id.ClassId, name, alias=alias, base=baseClass, interfaces=interfaces,
    isAbstract=isAbstract, isInterface=isInterface, isFinal=isFinal, canBeRoot=canBeRoot,
    substitutionProperty=substitutionProperty, precedence=precedence,
    properties=properties, references=references, children=childDescriptions)
  # debugf"{class}"
  print class

  return class.some

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

proc createNodesForLanguage*(language: Language): AstNode =
  result = newAstNode(langRootClass)

  var classes = initTable[ClassId, AstNode]()
  for class in language.classes.values:
    result.add IdLangRootChildren, createNodeFromNodeClass(classes, class)