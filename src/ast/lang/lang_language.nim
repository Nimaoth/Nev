import std/[tables, strformat, options]
import misc/[id, util, custom_logger]
import ui/node
import ast/[ast_ids, model, cells, base_language]

export id, ast_ids

logCategory "lang-language"

{.push gcsafe.}
{.push raises: [CatchableError].}

proc createLangLanguage*(repository: Repository, builders: CellBuilderDatabase) =
  log lvlInfo, &"createLangLanguage"

  let baseLanguage = repository.language(IdBaseLanguage).get
  let namedInterface = repository.resolveClass(IdINamed)

  let propertyTypeClass = newNodeClass(IdPropertyType, "PropertyType", isAbstract=true)
  let propertyTypeBoolClass = newNodeClass(IdPropertyTypeBool, "PropertyTypeBool", alias="bool", base=propertyTypeClass)
  let propertyTypeStringClass = newNodeClass(IdPropertyTypeString, "PropertyTypeString", alias="string", base=propertyTypeClass)
  let propertyTypeNumberClass = newNodeClass(IdPropertyTypeNumber, "PropertyTypeNumber", alias="number", base=propertyTypeClass)

  let roleDescriptorInterface = newNodeClass(IdIRoleDescriptor, "roleDescriptorInterface", isInterface=true, interfaces=[namedInterface])

  let countClass = newNodeClass(IdCount, "Count", isAbstract=true)
  let countZeroOrOneClass = newNodeClass(IdCountZeroOrOne, "CountZeroOrOne", alias="0..1", base=countClass)
  let countOneClass = newNodeClass(IdCountOne, "CountnOne", alias="1", base=countClass)
  let countZeroOrMoreClass = newNodeClass(IdCountZeroOrMore, "CountZeroOrMore", alias="0..n", base=countClass)
  let countOneOrMoreClass = newNodeClass(IdCountOneOrMore, "CountOneOrMore", alias="1..n", base=countClass)

  let classReferenceClass = newNodeClass(IdClassReference, "ClassReference", substitutionReference=IdClassReferenceTarget.some,
    references=[
      NodeReferenceDescription(id: IdClassReferenceTarget, role: "class", class: IdClassDefinition),
      ])

  let roleReferenceClass = newNodeClass(IdRoleReference, "RoleReference", substitutionReference=IdRoleReferenceTarget.some,
    references=[
      NodeReferenceDescription(id: IdRoleReferenceTarget, role: "role", class: IdIRoleDescriptor),
      ])

  let propertyDefinitionClass = newNodeClass(IdPropertyDefinition, "PropertyDefinition", interfaces=[roleDescriptorInterface], substitutionProperty=IdINamedName.some,
    children=[
      NodeChildDescription(id: IdPropertyDefinitionType, role: "type", class: IdPropertyType, count: ChildCount.One),
      ])

  let referenceDefinitionClass = newNodeClass(IdReferenceDefinition, "ReferenceDefinition", interfaces=[roleDescriptorInterface], substitutionProperty=IdINamedName.some,
    children=[
      NodeChildDescription(id: IdReferenceDefinitionClass, role: "class", class: IdClassReference, count: ChildCount.One),
      ])

  let childrenDefinitionClass = newNodeClass(IdChildrenDefinition, "ChildrenDefinition", interfaces=[roleDescriptorInterface], substitutionProperty=IdINamedName.some,
    children=[
      NodeChildDescription(id: IdChildrenDefinitionClass, role: "class", class: IdClassReference, count: ChildCount.One),
      NodeChildDescription(id: IdChildrenDefinitionCount, role: "count", class: IdCount, count: ChildCount.One),
      ])

  let langAspectClass = newNodeClass(IdLangAspect, "LangAspect", isAbstract=true)

  let langRootClass = newNodeClass(IdLangRoot, "LangRoot", canBeRoot=true,
    children=[NodeChildDescription(id: IdLangRootChildren, role: "children", class: IdLangAspect, count: ChildCount.ZeroOrMore)])

  let classDefinitionClass = newNodeClass(IdClassDefinition, "ClassDefinition", alias="class", base=langAspectClass, interfaces=[namedInterface],
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

  var builder = newCellBuilder(IdLangLanguage)

  template addBuilder(b: CellBuilder, id: ClassId, builderId: Id, body: untyped): untyped =
    block:
      proc fun(map {.inject.}: NodeCellMap, builder {.inject.}: CellBuilder, node {.inject.}: AstNode, owner {.inject.}: AstNode): Cell {.gcsafe, raises: [].} =
        body

      b.addBuilderFor id, builderId, fun

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

  builder.addBuilder(IdClassDefinition, idNone()):
    var cell = CollectionCell(id: newId().CellId, node: owner ?? node, referenceNode: node, uiFlags: &{LayoutHorizontal})
    cell.fillChildren = proc(map: NodeCellMap) {.gcsafe, raises: [].} =
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

  var typeComputers = initTable[ClassId, TypeComputer]()
  var valueComputers = initTable[ClassId, ValueComputer]()
  var scopeComputers = initTable[ClassId, ScopeComputer]()
  var validationComputers = initTable[ClassId, ValidationComputer]()

  defineComputerHelpers(typeComputers, valueComputers, scopeComputers, validationComputers)

  scopeComputer(IdClassReference):
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

  scopeComputer(IdClassDefinition):
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
    # debugf"collectRoles: {classNode.dump(recurse=true)}"
    for _, prop in classNode.children(IdClassDefinitionProperties):
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

  scopeComputer(IdRoleReference):
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

      if parent.class == IdPropertyValidatorDefinition:
        ctx.dependOn(parent)
        if parent.resolveReference(IdPropertyValidatorDefinitionClass).getSome(node):
          classNode = node
        break

      if parent.class == IdScopeDefinition:
        ctx.dependOn(parent)
        if parent.resolveReference(IdScopeDefinitionClass).getSome(node):
          classNode = node
        break

      parent = parent.parent

    if classNode.isNil:
      return nodes

    collectRoles(classNode, nodes)

    return nodes

  let langLanguage = newLanguage(IdLangLanguage, "Language Creation", @[
    langRootClass, langAspectClass,
    roleDescriptorInterface,
    propertyTypeClass, propertyTypeBoolClass, propertyTypeStringClass, propertyTypeNumberClass, propertyDefinitionClass, classDefinitionClass,
    classReferenceClass, roleReferenceClass, referenceDefinitionClass, childrenDefinitionClass,
    countClass, countZeroOrOneClass, countOneClass, countZeroOrMoreClass, countOneOrMoreClass,
  ], typeComputers, valueComputers, scopeComputers, validationComputers)

  repository.registerLanguage(langLanguage)
  builders.registerBuilder(IdLangLanguage, builder)
