import std/[tables, strformat, options, json]
import misc/[id, util, custom_logger, custom_async]
import ui/node
import ast/[model, base_language, cells]
import workspaces/[workspace]
import lang_language, lang_builder, cell_language

export id, ast_ids

logCategory "property-validator-language"

proc createPropertyValidatorLanguage*(repository: Repository, builders: CellBuilderDatabase) {.async.} =
  var typeComputers = initTable[ClassId, TypeComputer]()
  var valueComputers = initTable[ClassId, ValueComputer]()
  var scopeComputers = initTable[ClassId, ScopeComputer]()
  var validationComputers = initTable[ClassId, ValidationComputer]()

  defineComputerHelpers(typeComputers, valueComputers, scopeComputers, validationComputers)

  scopeComputer(IdPropertyValidatorDefinition):
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

    nodes

  proc resolveLanguage(project: Project, workspace: Workspace, id: LanguageId): Future[Option[Language]] {.gcsafe, async: (raises: []).} =
    repository.language(id)

  proc resolveModel(project: Project, workspace: Workspace, id: ModelId): Future[Option[Model]] {.gcsafe, async: (raises: []).} =
    repository.model(id)

  let model = newModel(IdPropertyValidatorLanguage.ModelId)
  model.addLanguage(repository.language(IdLangLanguage).get)

  const jsonText = staticRead "../model/lang/property-validator.ast-model"
  if not model.loadFromJsonAsync(nil, nil, "model/lang/property-validator.ast-model", jsonText.parseJson, resolveLanguage, resolveModel).await:
    log lvlError, "Failed to load property validator model"
    return

  var language = repository.createLanguageFromModel(model, builders).await
  language.name = "PropertyValidator"
  language.scopeComputers = scopeComputers
