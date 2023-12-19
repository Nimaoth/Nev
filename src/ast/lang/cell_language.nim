import std/[tables, strformat, options, json]
import id, ast_ids, util, custom_logger
import ../model, ../cells, ../model_state, query_system, ../cell_builder_database
import ../base_language
import lang_language
import ui/node
import print
export id, ast_ids

logCategory "cell-language"

var builder = newCellBuilder()
var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

builder.addBuilderFor IdCellBuilderDefinition, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: ConstantCell, text: "cell layout for", themeForegroundColors: @["keyword"], disableEditing: true),
  CellBuilderCommand(kind: ReferenceCell, referenceRole: IdCellBuilderDefinitionClass, targetProperty: IdINamedName.some, themeForegroundColors: @["variable"], disableEditing: true),
  CellBuilderCommand(kind: ConstantCell, text: ":", flags: &{NoSpaceLeft}, themeForegroundColors: @["punctuation", "&editor.foreground"], disableEditing: true),

  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
  CellBuilderCommand(kind: Children, childrenRole: IdCellBuilderDefinitionCellDefinitions, uiFlags: &{LayoutVertical}, flags: &{OnNewLine, IndentChildren}),
  CellBuilderCommand(kind: EndCollectionCell),
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
  cellLanguage = createLanguageFromModel(model)
  cellLanguage.name = "Cells"