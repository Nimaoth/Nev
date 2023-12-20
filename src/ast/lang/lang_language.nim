import std/[tables, strformat, options, os]
import id, util, custom_logger
import ui/node
import ast/[ast_ids, model, cells, cell_builder_database, base_language]

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

let classReferenceClass* = newNodeClass(IdClassReference, "ClassReference", substitutionReference=IdClassReferenceTarget.some,
  references=[
    NodeReferenceDescription(id: IdClassReferenceTarget, role: "class", class: IdClassDefinition),
    ])

let roleReferenceClass* = newNodeClass(IdRoleReference, "RoleReference", substitutionReference=IdRoleReferenceTarget.some,
  references=[
    NodeReferenceDescription(id: IdRoleReferenceTarget, role: "role", class: IdIRoleDescriptor),
    ])

let propertyDefinitionClass* = newNodeClass(IdPropertyDefinition, "PropertyDefinition", interfaces=[roleDescriptorInterface], substitutionProperty=IdINamedName.some,
  children=[
    NodeChildDescription(id: IdPropertyDefinitionType, role: "type", class: IdPropertyType, count: ChildCount.One),
    ])

let referenceDefinitionClass* = newNodeClass(IdReferenceDefinition, "ReferenceDefinition", interfaces=[roleDescriptorInterface], substitutionProperty=IdINamedName.some,
  children=[
    NodeChildDescription(id: IdReferenceDefinitionClass, role: "class", class: IdClassReference, count: ChildCount.One),
    ])

let childrenDefinitionClass* = newNodeClass(IdChildrenDefinition, "ChildrenDefinition", interfaces=[roleDescriptorInterface], substitutionProperty=IdINamedName.some,
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
    NodeChildDescription(id: IdClassDefinitionSubstitutionReference, role: "substitution reference", class: IdRoleReference, count: ChildCount.ZeroOrOne),
  ])

var builder = newCellBuilder()

builder.addBuilderFor IdPropertyTypeBool, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdPropertyTypeString, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdPropertyTypeNumber, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCountZeroOrOne, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCountOne, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCountZeroOrMore, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCountOneOrMore, idNone(), [CellBuilderCommand(kind: AliasCell, themeForegroundColors: @["keyword"], disableEditing: true)]

builder.addBuilderFor IdClassReference, idNone(), [
  CellBuilderCommand(kind: ReferenceCell, referenceRole: IdClassReferenceTarget, targetProperty: IdINamedName.some, themeForegroundColors: @["variable", "&editor.foreground"], disableEditing: true),
]

builder.addBuilderFor IdRoleReference, idNone(), [
  CellBuilderCommand(kind: ReferenceCell, referenceRole: IdRoleReferenceTarget, targetProperty: IdINamedName.some, themeForegroundColors: @["variable", "&editor.foreground"], disableEditing: true),
]

builder.addBuilderFor IdPropertyDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: PropertyCell, propertyRole: IdINamedName, themeForegroundColors: @["variable"]),
  CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdPropertyDefinitionType, uiFlags: &{LayoutHorizontal}),
]

builder.addBuilderFor IdReferenceDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: PropertyCell, propertyRole: IdINamedName, themeForegroundColors: @["variable"]),
  CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdReferenceDefinitionClass, uiFlags: &{LayoutHorizontal}),
]

builder.addBuilderFor IdChildrenDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: PropertyCell, propertyRole: IdINamedName, themeForegroundColors: @["variable"]),
  CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdChildrenDefinitionClass, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: ",", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdChildrenDefinitionCount, uiFlags: &{LayoutHorizontal}),
]

builder.addBuilderFor IdLangRoot, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical}),
  CellBuilderCommand(kind: Children, childrenRole: IdLangRootChildren, separator: "".some, placeholder: "...".some, uiFlags: &{LayoutVertical}),
]

builder.addBuilderFor IdLangAspect, idNone(), &{OnlyExactMatch}, [CellBuilderCommand(kind: ConstantCell, shadowText: "...", themeBackgroundColors: @["&inputValidation.errorBackground", "&debugConsole.errorForeground"])]

# builder.addBuilderFor IdClassDefinition, idNone(), [
#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "class", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdINamedName, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: ConstantCell, text: "as", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdClassDefinitionAlias, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: ConstantCell, text: "extends", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
#   CellBuilderCommand(kind: Children, childrenRole: IdClassDefinitionBaseClass, placeholder: "<base>".some, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "implements", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
#   CellBuilderCommand(kind: Children, childrenRole: IdClassDefinitionInterfaces, separator: ",".some, placeholder: "<interface>".some, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),

#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "abstract", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdClassDefinitionAbstract, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: ConstantCell, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
#   CellBuilderCommand(kind: ConstantCell, text: "interface", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdClassDefinitionInterface, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: ConstantCell, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
#   CellBuilderCommand(kind: ConstantCell, text: "final", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdClassDefinitionFinal, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: ConstantCell, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
#   CellBuilderCommand(kind: ConstantCell, text: "root", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdClassDefinitionCanBeRoot, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: ConstantCell, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
#   CellBuilderCommand(kind: ConstantCell, text: "precedence", themeForegroundColors: @["keyword"], disableEditing: true),
#   CellBuilderCommand(kind: PropertyCell, propertyRole: IdClassDefinitionPrecedence, themeForegroundColors: @["variable"]),
#   CellBuilderCommand(kind: EndCollectionCell),

#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "properties:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
#   CellBuilderCommand(kind: Children, childrenRole: IdClassDefinitionProperties, placeholder: "...".some, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
#   CellBuilderCommand(kind: EndCollectionCell),

#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "references:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
#   CellBuilderCommand(kind: Children, childrenRole: IdClassDefinitionReferences, placeholder: "...".some, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
#   CellBuilderCommand(kind: EndCollectionCell),

#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "children:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
#   CellBuilderCommand(kind: Children, childrenRole: IdClassDefinitionChildren, placeholder: "...".some, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
#   CellBuilderCommand(kind: EndCollectionCell),

#   CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
#   CellBuilderCommand(kind: ConstantCell, text: "substitution property:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
#   CellBuilderCommand(kind: Children, childrenRole: IdClassDefinitionSubstitutionProperty, placeholder: "<role>".some, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
#   CellBuilderCommand(kind: EndCollectionCell),

#   CellBuilderCommand(kind: EndCollectionCell), # vertical cell
#   CellBuilderCommand(kind: ConstantCell, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{OnNewLine}),
# ]

builder.addBuilderFor IdClassDefinition, idNone(), proc(map: NodeCellMap, builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
  var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
  cell.fillChildren = proc(map: NodeCellMap) =
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "class", themeForegroundColors: @["keyword"], disableEditing: true)

    cell.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdINamedName, themeForegroundColors: @["variable"])

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "as", themeForegroundColors: @["keyword"], disableEditing: true)
    cell.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdClassDefinitionAlias, themeForegroundColors: @["variable"])

    cell.add block:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "extends", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      buildChildrenT(builder, map, node, owner, IdClassDefinitionBaseClass, &{LayoutHorizontal}, 0.CellFlags):
        placeholder: "<base>"

    cell.add block:
      cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "implements", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      buildChildrenT(builder, map, node, owner, IdClassDefinitionInterfaces, &{LayoutHorizontal}, 0.CellFlags):
        separator: ConstantCell(node: owner ?? node, referenceNode: node, text: ",", style: CellStyle(noSpaceLeft: true), themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, disableSelection: true, deleteNeighbor: true)
        placeholder: "<interface>"

    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "{", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)

    var vertCell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren})

    vertCell.addHorizontal(node, 0.CellFlags):
      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "abstract", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdClassDefinitionAbstract, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "interface", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdClassDefinitionInterface, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "final", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdClassDefinitionFinal, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "root", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdClassDefinitionCanBeRoot, themeForegroundColors: @["variable"])

      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: ",", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft})
      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "precedence", themeForegroundColors: @["keyword"], disableEditing: true)
      sub.add PropertyCell(id: newId().CellId, node: owner ?? node, referenceNode: node, property: IdClassDefinitionPrecedence, themeForegroundColors: @["variable"])

    block:
      var sub = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "properties:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      sub.add block:
        buildChildrenT(builder, map, node, owner, IdClassDefinitionProperties, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
          placeholder: "..."

      if node.childCount(IdClassDefinitionProperties) > 0 or node.childCount(IdClassDefinitionReferences) > 0:
        vertCell.add sub
        sub = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})

      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "references:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      sub.add block:
        buildChildrenT(builder, map, node, owner, IdClassDefinitionReferences, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
          placeholder: "..."

      if node.childCount(IdClassDefinitionReferences) > 0 or node.childCount(IdClassDefinitionChildren) > 0:
        vertCell.add sub
        sub = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})

      sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "children:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
      sub.add block:
        buildChildrenT(builder, map, node, owner, IdClassDefinitionChildren, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
          placeholder: "..."

      vertCell.add sub

    let totalRoles = node.childCount(IdClassDefinitionProperties) + node.childCount(IdClassDefinitionReferences) + node.childCount(IdClassDefinitionChildren)
    if totalRoles > 0:
      vertCell.add block:
        var sub = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
        sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "substitution property:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
        sub.add block:
          buildChildrenT(builder, map, node, owner, IdClassDefinitionSubstitutionProperty, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
            placeholder: "<role>"
        sub

      vertCell.add block:
        var sub = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
        sub.add ConstantCell(node: owner ?? node, referenceNode: node, text: "substitution reference:", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true)
        sub.add block:
          buildChildrenT(builder, map, node, owner, IdClassDefinitionSubstitutionReference, &{LayoutVertical}, &{OnNewLine, IndentChildren}):
            placeholder: "<role>"
        sub

    cell.add vertCell
    cell.add ConstantCell(node: owner ?? node, referenceNode: node, text: "}", themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true, flags: &{OnNewLine})

  return cell

var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

scopeComputers[IdClassReference] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for class reference {node}"
  var nodes: seq[AstNode] = @[]

  for model in node.model.models:
    for root in model.rootNodes:
      for _, aspect in root.children(IdLangRootChildren):
        if aspect.class == IdClassDefinition:
          nodes.add aspect

  # todo: I want to be able to reference RoleReference in cell-builder.ast-model, which is only in the language model so far.
  # Maybe move role reference to a separate model?
  # With this I can also referene stuff from the lang language model in e.g. the test language, which shouldn't be possible
  for language in node.model.languages:
    for root in language.model.rootNodes:
      for _, aspect in root.children(IdLangRootChildren):
        if aspect.class == IdClassDefinition:
          nodes.add aspect

  for root in node.model.rootNodes:
    for _, aspect in root.children(IdLangRootChildren):
      if aspect.class == IdClassDefinition:
        nodes.add aspect

  return nodes

scopeComputers[IdClassDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for class definition {node}"
  var nodes: seq[AstNode] = @[]

  for model in node.model.models:
    for root in model.rootNodes:
      for _, aspect in root.children(IdLangRootChildren):
        if aspect.class == IdClassDefinition:
          nodes.add aspect

  # todo: I want to be able to reference RoleReference in cell-builder.ast-model, which is only in the language model so far.
  # Maybe move role reference to a separate model?
  # With this I can also referene stuff from the lang language model in e.g. the test language, which shouldn't be possible
  for language in node.model.languages:
    for root in language.model.rootNodes:
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

proc collectRoles(classNode: AstNode, nodes: var seq[AstNode]) =
  # echo fmt"collectRoles: {classNode.dump(recurse=true)}"
  for _, prop in classNode.children(IdClassDefinitionProperties):
    # echo fmt"{classNode}: {prop}"
    nodes.add prop

  for _, reference in classNode.children(IdClassDefinitionReferences):
    nodes.add reference

  for _, children in classNode.children(IdClassDefinitionChildren):
    nodes.add children

  if classNode.firstChild(IdClassDefinitionBaseClass).getSome(baseClassReference):
    if baseClassReference.resolveReference(IdClassReferenceTarget).getSome(baseClassNode):
      collectRoles(baseClassNode, nodes)

  for _, interfaceReference in classNode.children(IdClassDefinitionInterfaces):
    if interfaceReference.resolveReference(IdClassReferenceTarget).getSome(baseClassNode):
      collectRoles(baseClassNode, nodes)

scopeComputers[IdRoleReference] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for role reference {node}"
  var nodes: seq[AstNode] = @[]

  if node.role == IdReferenceCellDefinitionTargetProperty:
    let referenceCellNode = node.parent
    let referenceRoleNode = referenceCellNode.firstChild(IdReferenceCellDefinitionRole).getOr:
      return @[]

    let referenceRole = referenceRoleNode.resolveReference(IdRoleReferenceTarget).getOr:
      return @[]

    # debugf"referenceRole: {referenceRole}"

    let classReferenceNode = referenceRole.firstChild(IdReferenceDefinitionClass).getOr:
      return @[]

    # debugf"classReferenceNode: {classReferenceNode}"
    let classNode = classReferenceNode.resolveReference(IdClassReferenceTarget).getOr:
      return @[]

    # debugf"classNode: {classNode.dump(recurse=true)}"
    collectRoles(classNode, nodes)
    return nodes

  # todo: improve this
  var parent = node.parent
  var classNode: AstNode = nil
  while parent.isNotNil:
    if parent.class == IdClassDefinition:
      classNode = parent
      break

    if parent.class == IdCellBuilderDefinition:
      ctx.dependOn(parent)
      if parent.resolveReference(IdCellBuilderDefinitionClass).getSome(node):
        classNode = node
      break

    parent = parent.parent

  if classNode.isNil:
    return nodes

  collectRoles(classNode, nodes)

  return nodes

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
        return NodeClass.none
    else:
      log lvlError, fmt"No property type specified for {prop}"
      return NodeClass.none

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
        return NodeClass.none
    else:
      log lvlError, fmt"No class specified for {reference}"
      return NodeClass.none

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

    class.children.add NodeChildDescription(id: children.id.RoleId, role: childrenName, class: classId, count: count)

  if def.firstChild(IdClassDefinitionBaseClass).getSome(baseClassReference):
    if baseClassReference.resolveReference(IdClassReferenceTarget).getSome(baseClassNode):
      if createNodeClassFromLangDefinition(classMap, baseClassNode).getSome(baseClass):
        class.base = baseClass
      else:
        log lvlError, fmt"Failed to create base class for {def}: {baseClassNode}"
        return NodeClass.none

  for _, interfaceReferenceNode in def.children(IdClassDefinitionInterfaces):
    if interfaceReferenceNode.resolveReference(IdClassReferenceTarget).getSome(interfaceNode):
      if createNodeClassFromLangDefinition(classMap, interfaceNode).getSome(interfaceClass):
        class.interfaces.add interfaceClass
      else:
        log lvlError, fmt"Failed to create base class for {def}: {interfaceNode}"
        return NodeClass.none

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
    else:
      log lvlError, fmt"Invalid cell flag: {node}"

proc createCellBuilderCommandFromDefinition(builder: CellBuilder, def: AstNode, commands: var seq[CellBuilderCommand], isRoot: bool = false) =
  let shadowText = if def.property(IdCellDefinitionShadowText).getSome(shadowText):
    shadowText.stringValue
  else:
    ""

  let (cellFlags, uiFlags, disableEditing, disableSelection, deleteNeighbor)  = def.children(IdCellDefinitionCellFlags).parseCellFlags

  var foregroundColors: seq[string] = @[]
  var backgroundColors: seq[string] = @[]
  for _, colorNode in def.children(IdCellDefinitionForegroundColor):
    if colorNode.class == IdColorDefinitionText:
      foregroundColors.add colorNode.property(IdColorDefinitionTextScope).get.stringValue
    else:
      log lvlError, fmt"Invalid theme foreground color: {colorNode}"

  for _, colorNode in def.children(IdCellDefinitionBackgroundColor):
    if colorNode.class == IdColorDefinitionText:
      backgroundColors.add colorNode.property(IdColorDefinitionTextScope).get.stringValue
    else:
      log lvlError, fmt"Invalid theme foreground color: {colorNode}"

  if def.class == IdHorizontalCellDefinition:
    commands.add CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal} + uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
      themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    for _, c in def.children(IdCollectionCellDefinitionChildren):
      createCellBuilderCommandFromDefinition(builder, c, commands)
    if not isRoot:
      commands.add CellBuilderCommand(kind: EndCollectionCell)

  elif def.class == IdVerticalCellDefinition:
    commands.add CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical} + uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
      themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    for _, c in def.children(IdCollectionCellDefinitionChildren):
      createCellBuilderCommandFromDefinition(builder, c, commands)
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

  elif def.class == IdPropertyCellDefinition:
    if def.firstChild(IdPropertyCellDefinitionRole).getSome(propertyRoleNode):
      let propertyRole = propertyRoleNode.reference(IdRoleReferenceTarget).RoleId
      commands.add CellBuilderCommand(kind: PropertyCell, propertyRole: propertyRole, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
        themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    else:
      log lvlError, fmt"Missing role for property definition: {def}"

  elif def.class == IdChildrenCellDefinition:
    if def.firstChild(IdChildrenCellDefinitionRole).getSome(childRoleNode):
      let childRole = childRoleNode.reference(IdRoleReferenceTarget).RoleId
      commands.add CellBuilderCommand(kind: Children, childrenRole: childRole, uiFlags: uiFlags, flags: cellFlags, shadowText: shadowText, disableEditing: disableEditing, disableSelection: disableSelection, deleteNeighbor: deleteNeighbor,
        themeForegroundColors: foregroundColors, themeBackgroundColors: backgroundColors)
    else:
      log lvlError, fmt"Missing role for children definition: {def}"

  else:
    log lvlError, fmt"Invalid cell definition: {def}"

proc createCellBuilderFromDefinition(builder: CellBuilder, def: AstNode) =
  let targetClass = def.reference(IdCellBuilderDefinitionClass)
  var commands: seq[CellBuilderCommand] = @[]

  for _, c in def.children(IdCellBuilderDefinitionCellDefinitions):
    builder.createCellBuilderCommandFromDefinition(c, commands, true)

  builder.addBuilderFor targetClass.ClassId, idNone(), commands

proc createLanguageFromModel*(model: Model): Language =
  log lvlInfo, fmt"createLanguageFromModel {model.path} ({model.id})"
  var classMap = initTable[ClassId, NodeClass]()
  var classes: seq[NodeClass] = @[]
  var builder = newCellBuilder()

  for def in model.rootNodes:
    for _, c in def.children(IdLangRootChildren):
      if c.class == IdClassDefinition:
        if createNodeClassFromLangDefinition(classMap, c).getSome(class):
          classes.add class
      if c.class == IdCellBuilderDefinition:
        builder.createCellBuilderFromDefinition(c)

  var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
  var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
  var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
  var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

  let name = model.path.splitFile.name
  result = newLanguage(model.id.LanguageId, name, classes, typeComputers, valueComputers, scopeComputers, validationComputers)
  registerBuilder(result.id, builder)

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

let langLanguage* = newLanguage(IdLangLanguage, "Language Creation", @[
  langRootClass, langAspectClass,
  roleDescriptorInterface,
  propertyTypeClass, propertyTypeBoolClass, propertyTypeStringClass, propertyTypeNumberClass, propertyDefinitionClass, classDefinitionClass,
  classReferenceClass, roleReferenceClass, referenceDefinitionClass, childrenDefinitionClass,
  countClass, countZeroOrOneClass, countOneClass, countZeroOrMoreClass, countOneOrMoreClass,
], typeComputers, valueComputers, scopeComputers, validationComputers)
registerBuilder(IdLangLanguage, builder)

proc createModelForLanguage*(language: Language): Model =
  result = newModel(language.id.ModelId)
  result.addLanguage(langLanguage)

  let root = newAstNode(langRootClass)
  var classes = initTable[ClassId, AstNode]()
  for class in language.classes.values:
    root.add IdLangRootChildren, createNodeFromNodeClass(classes, class)

  result.addRootNode(root)

# let langLanguageModel = block:
#   let model = newModel(IdLangLanguageModel)
#   model.addLanguage(langLanguage)
#   model.addRootNode createModelForLanguage(langLanguage)
#   model
# langLanguage.model = langLanguageModel
langLanguage.model.addRootNode createModelForLanguage(langLanguage).rootNodes[0]

let baseInterfacesModel* = createModelForLanguage(base_language.baseInterfaces)
