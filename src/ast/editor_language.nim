import std/[tables, strformat]
import id, ast_ids, util, custom_logger
import model, cells, model_state, base_language, cell_builder_database
import ui/node

export base_language

logCategory "base-language"

let IdEditorLanguage* = "654fbb281446e19b3822521f".parseId.LanguageId

let IdLoadAppFile* = "654fbb281446e19b3822521d".parseId.ClassId
let IdLoadAppFileArgument* = "654fbb281446e19b3822521e".parseId.RoleId

let Id654fbb281446e19b38225220* = "654fbb281446e19b38225220".parseId
let Id654fbb281446e19b38225221* = "654fbb281446e19b38225221".parseId
let Id654fbb281446e19b38225222* = "654fbb281446e19b38225222".parseId
let Id654fbb281446e19b38225223* = "654fbb281446e19b38225223".parseId
let Id654fbb281446e19b38225224* = "654fbb281446e19b38225224".parseId
let Id654fbb281446e19b38225225* = "654fbb281446e19b38225225".parseId
let Id654fbb281446e19b38225226* = "654fbb281446e19b38225226".parseId
let Id654fbb281446e19b38225227* = "654fbb281446e19b38225227".parseId
let Id654fbb281446e19b38225228* = "654fbb281446e19b38225228".parseId
let Id654fbb281446e19b38225229* = "654fbb281446e19b38225229".parseId

let loadAppFileClass* = newNodeClass(IdLoadAppFile, "LoadAppFile", alias="load app file", base=expressionClass,
  children=[
    NodeChildDescription(id: IdLoadAppFileArgument, role: "file", class: expressionClass.id, count: ChildCount.One)])

var builder = newCellBuilder()

builder.addBuilderFor IdLoadAppFile, idNone(), [
  CellBuilderCommand(kind: CollectionCell, uiFlags: &{LayoutHorizontal}),
  CellBuilderCommand(kind: AliasCell, disableEditing: true),
  CellBuilderCommand(kind: Children, childrenRole: IdLoadAppFileArgument, placeholder: "<filename>".some, uiFlags: &{LayoutHorizontal}),
]

var typeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var valueComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): AstNode]()
var scopeComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): seq[AstNode]]()
var validationComputers = initTable[ClassId, proc(ctx: ModelComputationContextBase, node: AstNode): bool]()

typeComputers[loadAppFileClass.id] = proc(ctx: ModelComputationContextBase, node: AstNode): AstNode =
  debugf"compute type for load app file {node}"
  return stringTypeInstance

# scope

let editorLanguage* = newLanguage(IdEditorLanguage, "Editor", @[
  loadAppFileClass,
], typeComputers, valueComputers, scopeComputers, validationComputers, [base_language.baseLanguage])
registerBuilder(IdEditorLanguage, builder)

let editorModel* = block:
  var model = newModel(newId().ModelId)
  model.addLanguage(base_language.baseLanguage)
  model.addLanguage(editorLanguage)

  model

# print baseLanguage
