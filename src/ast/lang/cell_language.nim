import std/[tables, strformat, options, json]
import misc/[id, util, custom_logger]
import ui/node
import ast/[model, cells, cell_builder_database, base_language]
import lang_language

export id, ast_ids

logCategory "cell-language"

var builder = newCellBuilder(IdCellLanguage)
# var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
# var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
# var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

builder.addBuilderFor IdCellBuilderDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "cell layout for", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: ReferenceCell, referenceRole: IdCellBuilderDefinitionClass, targetProperty: IdINamedName.some, themeForegroundColors: @["variable"], disableEditing: true),
  CellBuilderCommand(kind: ConstantCell, text: ",", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),
  CellBuilderCommand(kind: ConstantCell, text: "only exact match", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: PropertyCell, propertyRole: IdCellBuilderDefinitionOnlyExactMatch, themeForegroundColors: @["variable"], disableEditing: true),
  CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),

  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellBuilderDefinitionCellDefinitions, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
  CellBuilderCommand(kind: EndCollectionCell),
]

builder.addBuilderFor IdCellFlag, idNone(), [CellBuilderCommand(kind: ConstantCell, shadowText: "<cell flag>")]
builder.addBuilderFor IdCellFlagDeleteWhenEmpty, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "DeleteWhenEmpty", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagOnNewLine, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "OnNewLine", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagIndentChildren, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "IndentChildren", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagNoSpaceLeft, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "NoSpaceLeft", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagNoSpaceRight, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "NoSpaceRight", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagVertical, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "Vertical", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagHorizontal, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "Horizontal", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagDisableEditing, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "DisableEditing", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagDisableSelection, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "DisableSelection", themeForegroundColors: @["keyword"], disableEditing: true)]
builder.addBuilderFor IdCellFlagDeleteNeighbor, idNone(), [CellBuilderCommand(kind: ConstantCell, text: "DeleteNeighbor", themeForegroundColors: @["keyword"], disableEditing: true)]


builder.addBuilderFor IdColorDefinition, idNone(), &{OnlyExactMatch}, [CellBuilderCommand(kind: ConstantCell, shadowText: "<color>")]
builder.addBuilderFor IdColorDefinitionText, idNone(), [CellBuilderCommand(kind: PropertyCell, propertyRole: IdColorDefinitionTextScope, themeForegroundColors: @["constant.numeric"])]

builder.addBuilderFor IdCellDefinition, idNone(), &{OnlyExactMatch}, [CellBuilderCommand(kind: ConstantCell, shadowText: "<cell>")]

template defineCellDefinitionCommands*(inBuilder, inId, inBuilderId, commandList: untyped) =
  let commands = CellBuilderCommands(commands: @commandList)
  inBuilder.addBuilderFor inId, inBuilderId, proc(map: NodeCellMap, builder: CellBuilder, node: AstNode, owner: AstNode): Cell =
    var cell = map.buildCellWithCommands(node, owner, commands)
    let (cellFlags, _, _, _, _) = parseCellFlags(node.children(IdCellDefinitionCellFlags))
    if OnNewLine in cellFlags: cell.flags.incl OnNewLine
    if IndentChildren in cellFlags: cell.flags.incl IndentChildren
    if NoSpaceLeft in cellFlags: cell.flags.incl NoSpaceLeft
    if NoSpaceRight in cellFlags: cell.flags.incl NoSpaceRight
    return cell

builder.defineCellDefinitionCommands IdHorizontalCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "[", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  # CellBuilderCommand(kind: ConstantCell, text: "horizontal", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdCollectionCellDefinitionChildren, separator: ",".some, placeholder: "children".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionCellFlags, separator: ",".some, placeholder: "flags".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "]", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
]

builder.defineCellDefinitionCommands IdVerticalCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "{", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionCellFlags, separator: ",".some, placeholder: "flags".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  # CellBuilderCommand(kind: ConstantCell, text: "vertical", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdCollectionCellDefinitionChildren, separator: ",".some, placeholder: "children".some, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
  # CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{OnNewLine}),
  CellBuilderCommand(kind: ConstantCell, text: "}", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{OnNewLine, NoSpaceLeft}),
]

builder.defineCellDefinitionCommands IdPropertyCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "(", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  CellBuilderCommand(kind: ConstantCell, text: "prop", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdPropertyCellDefinitionRole, themeForegroundColors: @["variable"]),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionCellFlags, separator: ",".some, placeholder: "flags".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: ")", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
]

builder.defineCellDefinitionCommands IdReferenceCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "(", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  CellBuilderCommand(kind: ConstantCell, text: "ref", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdReferenceCellDefinitionRole, themeForegroundColors: @["variable"]),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdReferenceCellDefinitionTargetProperty, placeholder: "<target property>".some, themeForegroundColors: @["variable"]),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionCellFlags, separator: ",".some, placeholder: "flags".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: ")", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
]

builder.defineCellDefinitionCommands IdChildrenCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "<", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  # CellBuilderCommand(kind: ConstantCell, text: "children", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdChildrenCellDefinitionRole, placeholder: "role".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionCellFlags, separator: ",".some, placeholder: "flags".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: ">", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
]

builder.defineCellDefinitionCommands IdAliasCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "(", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  CellBuilderCommand(kind: ConstantCell, text: "alias", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: ")", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
]

builder.defineCellDefinitionCommands IdConstantCellDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "(", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceRight}),
  CellBuilderCommand(kind: ConstantCell, text: "constant", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: PropertyCell, propertyRole: IdConstantCellDefinitionText, themeForegroundColors: @["constant.numeric"]),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: PropertyCell, propertyRole: IdCellDefinitionShadowText, themeForegroundColors: @["constant.numeric"]),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionCellFlags, separator: ",".some, placeholder: "flags".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionForegroundColor, separator: ",".some, placeholder: "fg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "|", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft, NoSpaceRight}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellDefinitionBackgroundColor, separator: ",".some, placeholder: "bg".some, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: ")", themeForegroundColors: @["punctuation"], disableEditing: true, flags: &{NoSpaceLeft}),
]

scopeComputers[IdCellBuilderDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for cell builder definition {node}"
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

  return nodes

# scopeComputers[IdReferenceCellDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
#   debugf"compute scope for reference cell definition {node}"
#   var nodes: seq[AstNode] = @[]

#   # todo: improve this
#   for model in node.model.models:
#     for root in model.rootNodes:
#       for _, aspect in root.children(IdLangRootChildren):
#         if aspect.class == IdClassDefinition:
#           nodes.add aspect

#   for root in node.model.rootNodes:
#     for _, aspect in root.children(IdLangRootChildren):
#       if aspect.class == IdClassDefinition:
#         nodes.add aspect

#   return nodes

var cellLanguage*: Language = block createCellLanguage:
  proc resolveLanguage(id: LanguageId): Option[Language] =
    if id == IdLangLanguage:
      return lang_language.langLanguage.some
    else:
      echo "Unknown language id: ", id

  proc resolveModel(project: Project, id: ModelId): Option[Model] = discard

  let model = newModel(IdCellLanguage.ModelId)
  model.addLanguage(lang_language.langLanguage)

  const jsonText = staticRead "../model/cell-builder.ast-model"
  if not model.loadFromJson("model/cell-builder.ast-model", jsonText.parseJson, resolveLanguage, resolveModel):
    echo "Failed to load cell builder model"
    break createCellLanguage

  var language = createLanguageFromModel(model)
  language.name = "Cells"
  language.scopeComputers = scopeComputers
  language

registerBuilder(IdCellLanguage, builder)

# let langLanguageModel = block:
#   let model = newModel(IdLangLanguageModel)
#   model.addLanguage(langLanguage)
#   model.addRootNode createNodesForLanguage(langLanguage)
#   model
# langLanguage.model = langLanguageModel
# langLanguage.model.addRootNode createNodesForLanguage(langLanguage)

proc updateCellLanguage*(model: Model) =
  cellLanguage.updateLanguageFromModel(model)