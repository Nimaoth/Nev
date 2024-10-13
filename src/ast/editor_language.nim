import std/[tables, strformat]
import ui/node
import misc/[id, util, custom_logger]
import scripting/scripting_wasm
import model, cells, base_language

export base_language

logCategory "base-language"

const IdEditorLanguage* = "654fbb281446e19b3822521f".parseId.LanguageId

const IdLoadAppFile* = "654fbb281446e19b3822521d".parseId.ClassId
const IdLoadAppFileArgument* = "654fbb281446e19b3822521e".parseId.RoleId

proc createEditorLanguage*(repository: Repository, builders: CellBuilderDatabase) =
  var typeComputers = initTable[ClassId, TypeComputer]()
  var valueComputers = initTable[ClassId, ValueComputer]()
  var scopeComputers = initTable[ClassId, ScopeComputer]()
  var validationComputers = initTable[ClassId, ValidationComputer]()

  defineComputerHelpers(typeComputers, valueComputers, scopeComputers, validationComputers)

  let expressionClass = repository.resolveClass(IdExpression)
  let stringTypeInstance = repository.getNode(IdStringTypeInstance).get

  var classes = newSeq[NodeClass]()
  var builder = newCellBuilder(IdEditorLanguage)

  var editorImports = ({.gcsafe.}: createEditorWasmImports())
  for i, name in editorImports.functionNames:
    let id = editorImports.ids[i].ClassId
    let argId = editorImports.argIds[i].RoleId
    classes.add newNodeClass(id, name, alias=name, base=expressionClass,
      children=[
        NodeChildDescription(id: argId, role: "arg", class: IdExpression, count: ChildCount.One)])

    builder.addBuilderFor id, idNone(), [
      CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
      CellBuilderCommand(kind: AliasCell, disableEditing: true),
      CellBuilderCommand(kind: Children, childrenRole: argId, placeholder: "<arg>".some, uiFlags: &{LayoutHorizontal}),
    ]

    # capture name:
    typeComputer(id):
      debugf"compute type for '{name}' {node}"
      stringTypeInstance

  let loadAppFileClass = newNodeClass(IdLoadAppFile, "LoadAppFile", alias="load app file", base=expressionClass,
    children=[
      NodeChildDescription(id: IdLoadAppFileArgument, role: "file", class: IdExpression, count: ChildCount.One)])
  classes.add loadAppFileClass

  builder.addBuilderFor IdLoadAppFile, idNone(), [
    CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
    CellBuilderCommand(kind: AliasCell, disableEditing: true),
    CellBuilderCommand(kind: Children, childrenRole: IdLoadAppFileArgument, placeholder: "<filename>".some, uiFlags: &{LayoutHorizontal}),
  ]

  typeComputer(IdLoadAppFile):
    debugf"compute type for load app file {node}"
    stringTypeInstance

  let baseLanguage = repository.language(IdBaseLanguage).get

  let editorLanguage = newLanguage(IdEditorLanguage, "Editor", classes, typeComputers, valueComputers, scopeComputers, validationComputers, [baseLanguage])

  builders.registerBuilder(IdEditorLanguage, builder)

  let editorModel = newModel(newId().ModelId)
  editorModel.addLanguage(baseLanguage)
  editorModel.addLanguage(editorLanguage)

  repository.registerLanguage(editorLanguage)
