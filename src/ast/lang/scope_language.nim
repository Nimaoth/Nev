import std/[tables, strformat, options, json]
import misc/[id, util, custom_logger, custom_async]
import ui/node
import ast/[model, base_language]
import workspaces/[workspace]
import lang_language, lang_builder, cell_language

export id, ast_ids

logCategory "scope-language"

# var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
# var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
# var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

scopeComputers[IdScopeDefinition] = proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode] =
  debugf"compute scope for scope definition {node}"
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

proc resolveLanguage(project: Project, workspace: Workspace, id: LanguageId): Future[Option[Language]] {.async.} =
  if id == IdLangLanguage:
    assert lang_language.langLanguage.isNotNil
    return lang_language.langLanguage.some
  if id == IdCellLanguage:
    let cellLanguage =  cell_language.getCellLanguage().await
    assert cellLanguage.isNotNil
    return cellLanguage.some
  if id == IdBaseInterfaces:
    assert base_language.baseInterfaces.isNotNil
    return base_language.baseInterfaces.some
  else:
    log lvlError, "createScopeLanguage::resolveLanguage: unknown language id: ", id

proc resolveModel(project: Project, workspace: Workspace, id: ModelId): Future[Option[Model]] {.async.} =
  assert baseInterfacesModel.isNotNil
  if id == baseInterfacesModel.id:
    return lang_builder.baseInterfacesModel.some
  if id == baseLanguageModel.id:
    return lang_builder.baseLanguageModel.some
  if id == langLanguageModel.id:
    return lang_builder.langLanguageModel.some
  log lvlError, fmt"createScopeLanguage::resolveModel: unknown model id: {id}"

var scopeLanguage: Future[Language] = nil
proc createScopeLanguage(): Future[Language] {.async.} =

  let model = newModel(IdScopeLanguage.ModelId)
  model.addLanguage(lang_language.langLanguage)

  const jsonText = staticRead "../model/lang/scope.ast-model"
  if not model.loadFromJsonAsync(nil, nil, "model/lang/scope.ast-model", jsonText.parseJson, resolveLanguage, resolveModel).await:
    log lvlError, "Failed to load scope model"
    return Language nil

  var language = createLanguageFromModel(model).await
  language.name = "Scope"
  language.scopeComputers = scopeComputers
  return language

proc getScopeLanguage*(): Future[Language] =
  if scopeLanguage.isNil:
    scopeLanguage = createScopeLanguage()
  return scopeLanguage

proc updateScopeLanguage*(model: Model) {.async.} =
  discard getScopeLanguage().await.updateLanguageFromModel(model).await