import std/[tables, strformat, options, json]
import misc/[id, util, custom_logger, custom_async]
import ui/node
import ast/[model, cells, cell_builder_database, base_language]
import workspaces/[workspace]
import lang_language, lang_builder, cell_language

export id, ast_ids

logCategory "property-validator-language"

# var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
# var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
# var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

scopeComputers[IdPropertyValidatorDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for property validator definition {node}"
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

proc resolveLanguage(project: Project, workspace: WorkspaceFolder, id: LanguageId): Future[Option[Language]] {.async.} =
  if id == IdLangLanguage:
    assert lang_language.langLanguage.isNotNil
    return lang_language.langLanguage.some
  if id == IdCellLanguage:
    let cellLanguage =  cell_language.cellLanguage.await
    assert cellLanguage.isNotNil
    return cellLanguage.some
  if id == IdBaseInterfaces:
    assert base_language.baseInterfaces.isNotNil
    return base_language.baseInterfaces.some
  else:
    log lvlError, "createPropertyValidatorLanguage::resolveLanguage: unknown language id: ", id

proc resolveModel(project: Project, workspace: WorkspaceFolder, id: ModelId): Future[Option[Model]] {.async.} =
  assert baseInterfacesModel.isNotNil
  if id == baseInterfacesModel.id:
    return lang_builder.baseInterfacesModel.some
  if id == baseLanguageModel.id:
    return lang_builder.baseLanguageModel.some
  if id == langLanguageModel.id:
    return lang_builder.langLanguageModel.some
  log lvlError, fmt"createPropertyValidatorLanguage::resolveModel: unknown model id: {id}"

var propertyValidatorLanguage*: Future[Language] = nil
proc createPropertyValidatorLanguage(): Future[Language] {.async.} =

  let model = newModel(IdPropertyValidatorLanguage.ModelId)
  model.addLanguage(lang_language.langLanguage)

  const jsonText = staticRead "../model/lang/property-validator.ast-model"
  if not model.loadFromJsonAsync(nil, nil, "model/lang/property-validator.ast-model", jsonText.parseJson, resolveLanguage, resolveModel).await:
    log lvlError, "Failed to load property validator model"
    return Language nil

  var language = createLanguageFromModel(model).await
  language.name = "PropertyValidator"
  language.scopeComputers = scopeComputers
  return language

propertyValidatorLanguage = createPropertyValidatorLanguage()

proc updatePropertyValidatorLanguage*(model: Model) {.async.} =
  discard propertyValidatorLanguage.await.updateLanguageFromModel(model).await