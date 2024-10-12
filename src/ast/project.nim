import std/[strformat, sugar, tables, options, json, os]
import fusion/matching
import misc/[util, custom_logger, custom_async, myjsonutils, custom_unicode]
import workspaces/[workspace]
import ui/node
import lang/[lang_language, lang_builder, cell_language, property_validator_language, scope_language]
import ast/[model_state, base_language, editor_language, ast_ids, model, cells]
import service
import results

{.push gcsafe.}

logCategory "ast-project"

type
  AstProjectService* = ref object of Service
    project*: Project
    workspace*: Workspace
    repository*: Repository
    builders*: CellBuilderDatabase
    resolveLanguage*: proc(project: Project, workspace: Workspace, id: LanguageId): Future[Option[Language]] {.gcsafe, async: (raises: []).}
    resolveModel: proc(project: Project, workspace: Workspace, id: ModelId): Future[Option[Model]] {.gcsafe, async: (raises: []).}

func serviceName*(_: typedesc[AstProjectService]): string = "AstProjectService"

addBuiltinService(AstProjectService, WorkspaceService)

proc loadModelAsync*(self: AstProjectService, path: string): Future[Option[Model]] {.async: (raises: []).}

method init*(self: AstProjectService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"AstProjectService.init"
  let workspaceService = self.services.getServiceAsync(WorkspaceService).await.get

  while workspaceService.workspace.isNil:
    try:
      sleepAsync(10.milliseconds).await
    except CancelledError:
      discard

  log lvlInfo, &"AstProjectService.init 2"
  self.workspace = workspaceService.workspace

  let projectPath = self.workspace.getAbsolutePath("./model/playground.ast-project")
  log lvlInfo, fmt"[getGlobalProject] Loading project source file '{projectPath}'"

  self.project = newProject()
  self.project.rootDirectory = projectPath.splitPath[0]
  self.project.path = projectPath
  self.project.computationContext = newModelComputationContext(self.project)

  self.repository = Repository()
  self.builders = CellBuilderDatabase()

  proc resolveLanguage(project: Project, ws: Workspace, id: LanguageId): Future[Option[Language]] {.gcsafe, async: (raises: []).} =
    if self.repository.language(id).getSome(language):
      return language.some
    elif project.dynamicLanguages.contains(id):
      return project.dynamicLanguages[id].some
    elif project.modelPaths.contains(id.ModelId):
      let languageModel = self.loadModelAsync(project.modelPaths[id.ModelId]).await.getOr:
        return Language.none

      if not languageModel.hasLanguage(IdLangLanguage):
        return Language.none

      let language = self.repository.createLanguageFromModel(languageModel, self.builders, ctx = project.computationContext.some).await
      project.dynamicLanguages[language.id] = language
      return language.some
    else:
      return Language.none

  proc resolveModel(project: Project, ws: Workspace, id: ModelId): Future[Option[Model]] {.gcsafe, async: (raises: []).} =
    if self.repository.model(id).getSome(model):
      return model.some

    assert project.loaded

    log lvlInfo, fmt"resolveModel {id}"
    if project.getModel(id).getSome(model):
      return model.some

    if project.modelPaths.contains(id):
      let path = project.modelPaths[id]
      return self.loadModelAsync(path).await

    log lvlError, fmt"project.resolveModel {id}: not found"
    return Model.none

  self.resolveLanguage = resolveLanguage
  self.resolveModel = resolveModel

  try:
    self.repository.createBaseLanguage(self.builders)
    self.repository.createLangLanguage(self.builders)
    self.repository.createBaseAndLangModels()
    await self.repository.createCellLanguage(self.builders)
    await self.repository.createScopeLanguage(self.builders)
    await self.repository.createPropertyValidatorLanguage(self.builders)
    self.repository.createEditorLanguage(self.builders)
  except CatchableError as e:
    result.err(e)
    return

  try:
    let jsonText = self.workspace.loadFile(self.project.path).await
    let json = jsonText.parseJson
    if self.project.loadFromJson(json):
      self.project.loaded = true
  except CatchableError as e:
    result.err(e)
    return

  return ok()

proc save*(self: AstProjectService): Future[void] {.async.} =
  let project = self.project

  log lvlInfo, fmt"Saving project '{project.path}'..."
  let serialized = project.toJson.pretty
  self.workspace.saveFile(project.path, serialized).await
  log lvlInfo, fmt"Saving project '{project.path}' done"

proc loadModelAsync*(self: AstProjectService, path: string): Future[Option[Model]] {.async: (raises: []).} =
  let project = self.project
  log lvlInfo, fmt"loadModelAsync {path}"

  try:
    let jsonText = self.workspace.loadFile(path).await

    let json = jsonText.parseJson.catch:
      log lvlError, &"project.loadModelAsync: Failed to parse json: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return Model.none

    var model = newModel()
    if not model.loadFromJsonAsync(project, self.workspace, path, json, self.resolveLanguage, self.resolveModel).await:
      log lvlError, fmt"project.loadModelAsync: Failed to load model: no id"
      return Model.none

    if project.getModel(model.id).getSome(existing):
      log lvlInfo, fmt"project.loadModelAsync: Model {model.id} already exists in project"
      return existing.some

    project.addModel(model)

    return model.some
  except CatchableError as e:
    log lvlError, &"Failed to load model '{path}': {e.msg}"
    return Model.none

proc getAllAvailableLanguages*(project: Project): seq[LanguageId] =
  let l = collect(newSeq):
    for languageId in project.dynamicLanguages.keys:
      languageId
  return @[IdBaseLanguage, IdBaseInterfaces, IdEditorLanguage, IdLangLanguage, IdCellLanguage, IdPropertyValidatorLanguage, IdScopeLanguage] & l

proc updateLanguageFromModel*(self: AstProjectService, model: Model): Future[void] {.async.} =
  let languageId = model.id.LanguageId

  if self.repository.language(languageId).getSome(language):
    log lvlInfo, fmt"Updating language {language.name} ({languageId}) with model {model.path} ({model.id})"
    try:
      discard await self.repository.updateLanguageFromModel(language, model, self.builders, updateBuilder=false)
    except CatchableError:
      log lvlError, fmt"Failed to update language from model: {getCurrentExceptionMsg()}"
    return

  if self.project.dynamicLanguages.contains(languageId):
    let language = self.project.dynamicLanguages[languageId]
    try:
      log lvlInfo, fmt"Updating language {language.name} ({language.id}) with model {model.path} ({model.id})"
      discard self.repository.updateLanguageFromModel(language, model, self.builders, ctx = self.project.computationContext.some).await
      return
    except CatchableError:
      log lvlError, fmt"Failed to update language from model: {getCurrentExceptionMsg()}"

  log lvlInfo, fmt"Compiling language from model {model.path} ({model.id})"
  let language = self.repository.createLanguageFromModel(model, self.builders, ctx = self.project.computationContext.some).await
  self.project.dynamicLanguages[language.id] = language
