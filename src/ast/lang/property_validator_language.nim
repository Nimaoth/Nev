import std/[tables, strformat, options, json]
import misc/[id, util, custom_logger, custom_async]
import ui/node
import ast/[model, cells, cell_builder_database, base_language]
import lang_language, cell_language

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

var propertyValidatorLanguage*: Future[Language] = nil
proc createPropertyValidatorLanguage(): Future[Language] {.async.} =
  let cellLanguage =  cell_language.cellLanguage.await

  proc resolveLanguage(id: LanguageId): Option[Language] =
    if id == IdLangLanguage:
      assert lang_language.langLanguage.isNotNil
      return lang_language.langLanguage.some
    if id == IdCellLanguage:
      assert cellLanguage.isNotNil
      return cellLanguage.some
    if id == IdBaseInterfaces:
      assert base_language.baseInterfaces.isNotNil
      return base_language.baseInterfaces.some
    else:
      log lvlError, "createPropertyValidatorLanguage::resolveLanguage: unknown language id: ", id

  proc resolveModel(project: Project, id: ModelId): Option[Model] =
    assert baseInterfacesModel.isNotNil
    if id == baseInterfacesModel.id:
      return baseInterfacesModel.some
    if id == baseLanguageModel.id:
      return baseLanguageModel.some
    log lvlError, fmt"createPropertyValidatorLanguage::resolveModel: unknown model id: {id}"

  let model = newModel(IdPropertyValidatorLanguage.ModelId)
  model.addLanguage(lang_language.langLanguage)

  const jsonText = staticRead "../model/lang/property-validator.ast-model"
  if not model.loadFromJson("model/lang/property-validator.ast-model", jsonText.parseJson, resolveLanguage, resolveModel):
    log lvlError, "Failed to load property validator model"
    return Language nil

  var language = createLanguageFromModel(model).await
  language.name = "PropertyValidator"
  language.scopeComputers = scopeComputers
  return language

propertyValidatorLanguage = createPropertyValidatorLanguage()

proc updatePropertyValidatorLanguage*(model: Model) {.async.} =
  discard propertyValidatorLanguage.await.updateLanguageFromModel(model).await