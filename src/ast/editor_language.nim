import std/[tables, strformat]
import ui/node
import misc/[id, util, custom_logger]
import model, cells, base_language

export base_language

logCategory "base-language"

const IdEditorLanguage* = "654fbb281446e19b3822521f".parseId.LanguageId

const IdLoadAppFile* = "654fbb281446e19b3822521d".parseId.ClassId
const IdLoadAppFileArgument* = "654fbb281446e19b3822521e".parseId.RoleId

const Id654fbb281446e19b38225220* = "654fbb281446e19b38225220".parseId
const Id654fbb281446e19b38225221* = "654fbb281446e19b38225221".parseId
const Id654fbb281446e19b38225222* = "654fbb281446e19b38225222".parseId
const Id654fbb281446e19b38225223* = "654fbb281446e19b38225223".parseId
const Id654fbb281446e19b38225224* = "654fbb281446e19b38225224".parseId
const Id654fbb281446e19b38225225* = "654fbb281446e19b38225225".parseId
const Id654fbb281446e19b38225226* = "654fbb281446e19b38225226".parseId
const Id654fbb281446e19b38225227* = "654fbb281446e19b38225227".parseId
const Id654fbb281446e19b38225228* = "654fbb281446e19b38225228".parseId
const Id654fbb281446e19b38225229* = "654fbb281446e19b38225229".parseId

proc createEditorLanguage*(repository: Repository, builders: CellBuilderDatabase) =
  var typeComputers = initTable[ClassId, TypeComputer]()
  var valueComputers = initTable[ClassId, ValueComputer]()
  var scopeComputers = initTable[ClassId, ScopeComputer]()
  var validationComputers = initTable[ClassId, ValidationComputer]()

  defineComputerHelpers(typeComputers, valueComputers, scopeComputers, validationComputers)

  let expressionClass = repository.resolveClass(IdExpression)
  let stringTypeInstance = repository.getNode(IdStringTypeInstance).get

  let loadAppFileClass = newNodeClass(IdLoadAppFile, "LoadAppFile", alias="load app file", base=expressionClass,
    children=[
      NodeChildDescription(id: IdLoadAppFileArgument, role: "file", class: expressionClass.id, count: ChildCount.One)])

  var builder = newCellBuilder(IdEditorLanguage)

  builder.addBuilderFor IdLoadAppFile, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdLoadAppFileArgument, placeholder: "<filename>".some, uiFlags: &{LayoutHorizontal}),
  ]

  typeComputer(loadAppFileClass.id):
    debugf"compute type for load app file {node}"
    stringTypeInstance

  let baseLanguage = repository.language(IdBaseLanguage).get

  let editorLanguage = newLanguage(IdEditorLanguage, "Editor", @[
    loadAppFileClass,
  ], typeComputers, valueComputers, scopeComputers, validationComputers, [baseLanguage])

  builders.registerBuilder(IdEditorLanguage, builder)

  let editorModel = newModel(newId().ModelId)
  editorModel.addLanguage(baseLanguage)
  editorModel.addLanguage(editorLanguage)

  repository.registerLanguage(editorLanguage)
