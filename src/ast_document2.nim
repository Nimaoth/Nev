import std/[strformat, strutils, algorithm, math, logging, sugar, tables, macros, macrocache, options, deques, sets, json, jsonutils, sequtils, streams, os]
import timer
import fusion/matching, fuzzy, bumpy, rect_utils, vmath, chroma
import editor, util, document, document_editor, text_document, events, id, ast_ids, scripting/expose, event, theme, input, custom_async
from scripting_api as api import nil
import custom_logger
import platform/[filesystem, platform, widgets]
import workspaces/[workspace]
import ast/[types, base_language]
import print

from ast import AstNodeKind

var project = newProject()

type
  UndoOpKind = enum
    Delete
    Replace
    Insert
    TextChange
    SymbolNameChange
  UndoOp = ref object
    kind: UndoOpKind
    id: Id
    parent: AstNode
    idx: int
    node: AstNode
    text: string

  ModelDocument* = ref object of Document
    filename*: string
    model*: Model
    project*: Project

    undoOps*: seq[UndoOp]
    redoOps*: seq[UndoOp]

    onNodeInserted*: Event[(ModelDocument, AstNode)]

    builder*: CellBuilder

  ModelDocumentEditor* = ref object of DocumentEditor
    editor*: Editor
    document*: ModelDocument

    modeEventHandler: EventHandler
    currentMode*: string

    scrollOffset*: float
    previousBaseIndex*: seq[int]

    lastBounds*: Rect

proc `$`(op: UndoOp): string =
  result = fmt"{op.kind}, '{op.text}'"
  if op.id != null: result.add fmt", id = {op.id}"
  if op.node != nil: result.add fmt", node = {op.node}"
  if op.parent != nil: result.add fmt", parent = {op.parent}, index = {op.idx}"

proc handleNodeInserted*(doc: ModelDocument, node: AstNode)
proc handleNodeInserted*(self: ModelDocumentEditor, doc: ModelDocument, node: AstNode)
proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse

method `$`*(document: ModelDocument): string =
  return document.filename

proc newModelDocument*(filename: string = "", app: bool = false, workspaceFolder: Option[WorkspaceFolder]): ModelDocument =
  new(result)
  result.filename = filename
  result.appFile = app
  result.workspace = workspaceFolder
  result.project = project


  var testModel = newModel(newId())
  testModel.addLanguage(base_language.baseLanguage)

  let a = newAstNode(stringLiteralClass)
  let b = newAstNode(nodeReferenceClass)
  let c = newAstNode(binaryExpressionClass)

  c.add(IdBinaryExpressionLeft, a)
  c.add(IdBinaryExpressionRight, b)

  testModel.addRootNode(c)

  debugf"temp root: {c}"

  result.model = testModel

  result.builder = newCellBuilder()
  for language in result.model.languages:
    result.builder.addBuilder(language.builder)

  project.addModel(result.model)
  project.builder = result.builder

  if filename.len > 0:
    result.load()


method save*(self: ModelDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  logger.log lvlInfo, fmt"[modeldoc] Saving model source file '{self.filename}'"
  # let serialized = self.model.toJson

  # if self.workspace.getSome(ws):
  #   asyncCheck ws.saveFile(self.filename, serialized.pretty)
  # elif self.appFile:
  #   fs.saveApplicationFile(self.filename, serialized.pretty)
  # else:
  #   fs.saveFile(self.filename, serialized.pretty)

var classes = initTable[AstNodeKind, tuple[class: NodeClass, link: Id]]()
classes[Empty] = (emptyClass, idNone())
classes[Identifier] = (nodeReferenceClass, IdNodeReferenceTarget)
classes[NumberLiteral] = (numberLiteralClass, IdIntegerLiteralValue)
classes[StringLiteral] = (stringLiteralClass, IdStringLiteralValue)
classes[ConstDecl] = (constDeclClass, IdConstDeclName)
classes[LetDecl] = (letDeclClass, IdLetDeclName)
classes[VarDecl] = (varDeclClass, IdVarDeclName)
classes[NodeList] = (nodeListClass, idNone())
classes[Call] = (callClass, idNone())
classes[If] = (ifClass, idNone())
classes[While] = (whileClass, idNone())
classes[FunctionDefinition] = (functionDefinitionClass, idNone())
classes[Params] = (parameterDeclClass, idNone())
classes[Assignment] = (assignmentClass, idNone())

proc toModel(json: JsonNode): AstNode =
  let kind = json["kind"].jsonTo AstNodeKind
  let data = classes[kind]
  var node = newAstNode(data.class, json["id"].jsonTo(Id).some)

  debugf"kind: {kind}, {data}, {node.id}"

  if json.hasKey("reff"):
    node.setReference(data.link, json["reff"].jsonTo Id)

  if json.hasKey("text"):
    if kind == NumberLiteral:
      node.setProperty(data.link, PropertyValue(kind: PropertyType.Int, intValue: json["text"].jsonTo(string).parseInt))
    else:
      node.setProperty(data.link, PropertyValue(kind: PropertyType.String, stringValue: json["text"].jsonTo string))

  if json.hasKey("children"):
    let children = json["children"].elems

    case kind
    of NodeList:
      for c in children:
        node.add(IdNodeListChildren, c.toModel)

    of ConstDecl:
      node.add(IdConstDeclValue, children[0].toModel)
    of LetDecl:
      node.add(IdLetDeclType, children[0].toModel)
      node.add(IdLetDeclValue, children[1].toModel)
    of VarDecl:
      node.add(IdVarDeclType, children[0].toModel)
      node.add(IdVarDeclValue, children[1].toModel)

    of Call:
      node.add(IdCallFunction, children[0].toModel)
      for c in children[1..^1]:
        node.add(IdCallArguments, c.toModel)

    of If:
      node.add(IdIfExpressionCondition, children[0].toModel)
      node.add(IdIfExpressionThenCase, children[1].toModel)

      var nodeTemp = node

      var i = 2
      while i + 1 < children.len:
        defer: i += 2

        var el = newAstNode(ifClass)
        el.add(IdIfExpressionCondition, children[i].toModel)
        el.add(IdIfExpressionThenCase, children[i + 1].toModel)
        nodeTemp.add(IdIfExpressionElseCase, el)
        nodeTemp = el

      if i < children.len:
        nodeTemp.add(IdIfExpressionElseCase, children[i].toModel)

    of While:
      node.add(IdWhileExpressionCondition, children[0].toModel)
      node.add(IdWhileExpressionBody, children[1].toModel)

    of Assignment:
      node.add(IdAssignmentTarget, children[0].toModel)
      node.add(IdAssignmentValue, children[1].toModel)

    of FunctionDefinition:
      if children[0].hasKey("children"):
        for c in children[0]["children"].elems:
          var param = newAstNode(parameterDeclClass, c["id"].jsonTo(Id).some)
          param.setProperty(IdParameterDeclName, PropertyValue(kind: PropertyType.String, stringValue: c["text"].jsonTo string))
          param.add(IdParameterDeclType, c["children"][0].toModel)
          node.add(IdFunctionDefinitionParameters, param)
      node.add(IdFunctionDefinitionReturnType, children[1].toModel)
      node.add(IdFunctionDefinitionBody, children[2].toModel)

    else:
      discard

  return node

proc loadAsync*(self: ModelDocument): Future[void] {.async.} =
  logger.log lvlInfo, fmt"[modeldoc] Loading model source file '{self.filename}'"
  try:
    var jsonText = ""
    if self.workspace.getSome(ws):
      jsonText = await ws.loadFile(self.filename)
    elif self.appFile:
      jsonText = fs.loadApplicationFile(self.filename)
    else:
      jsonText = fs.loadFile(self.filename)

    let json = jsonText.parseJson
    var testModel = newModel(newId())
    testModel.addLanguage(base_language.baseLanguage)

    let root = json.toModel

    testModel.addRootNode(root)

    self.model = testModel

    self.builder = newCellBuilder()
    for language in self.model.languages:
      self.builder.addBuilder(language.builder)

    project.addModel(self.model)
    project.builder = self.builder

    logger.log(lvlDebug, fmt"[modeldoc] Load new model {root}")

    self.undoOps.setLen 0
    self.redoOps.setLen 0

  except CatchableError:
    logger.log lvlError, fmt"[modeldoc] Failed to load model source file '{self.filename}': {getCurrentExceptionMsg()}"

method load*(self: ModelDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename
  asyncCheck self.loadAsync()

proc handleNodeInserted*(doc: ModelDocument, node: AstNode) =
  logger.log lvlInfo, fmt"[modeldoc] Node inserted: {node}"
  # ctx.insertNode(node)
  doc.onNodeInserted.invoke (doc, node)

  # doc.nodes[node.id] = node
  # for (key, child) in node.nextPreOrder:
  #   doc.nodes[child.id] = child

method handleDocumentChanged*(self: ModelDocumentEditor) =
  logger.log(lvlInfo, fmt"[model-editor] Document changed")
  # self.selectionHistory.clear
  # self.selectionFuture.clear
  # self.finishEdit false
  # for symbol in ctx.globalScope.values:
  #   discard ctx.newSymbol(symbol)
  # self.node = self.document.rootNode[0]
  self.markDirty()

proc handleNodeInserted*(self: ModelDocumentEditor, doc: ModelDocument, node: AstNode) =
  discard

proc toJson*(self: api.ModelDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.model")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.ModelDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc handleInput(self: ModelDocumentEditor, input: string): EventResponse =
  # logger.log lvlInfo, fmt"[modeleditor]: Handle input '{input}'"
  return Ignored

method handleScroll*(self: ModelDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  let scrollAmount = scroll.y * getOption[float](self.editor, "model.scroll-speed", 20)

  self.scrollOffset += scrollAmount
  self.markDirty()

method handleMousePress*(self: ModelDocumentEditor, button: MouseButton, mousePosWindow: Vec2) =
  # Make mousePos relative to contentBounds
  let mousePosContent = mousePosWindow - self.lastBounds.xy

method handleMouseRelease*(self: ModelDocumentEditor, button: MouseButton, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: ModelDocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  discard

method canEdit*(self: ModelDocumentEditor, document: Document): bool =
  if document of ModelDocument: return true
  else: return false

method createWithDocument*(self: ModelDocumentEditor, document: Document): DocumentEditor =
  let editor = ModelDocumentEditor(eventHandler: nil, document: ModelDocument(document))

  # Emit this to set the editor prototype to editor_model_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [editor, " = createWithPrototype(editor_model_prototype, ", editor, ");"].}
    # This " is here to fix syntax highlighting

  editor.init()
  discard editor.document.onNodeInserted.subscribe proc(d: auto) = editor.handleNodeInserted(d[0], d[1])

  return editor

method injectDependencies*(self: ModelDocumentEditor, ed: Editor) =
  self.editor = ed
  self.editor.registerEditor(self)

  self.eventHandler = eventHandler(ed.getEventHandlerConfig("editor.model")):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

method unregister*(self: ModelDocumentEditor) =
  self.editor.unregisterEditor(self)

proc getModelDocumentEditor(wrapper: api.ModelDocumentEditor): Option[ModelDocumentEditor] =
  if gEditor.isNil: return ModelDocumentEditor.none
  if gEditor.getEditorForId(wrapper.id).getSome(editor):
    if editor of ModelDocumentEditor:
      return editor.ModelDocumentEditor.some
  return ModelDocumentEditor.none

static:
  addTypeMap(ModelDocumentEditor, api.ModelDocumentEditor, getModelDocumentEditor)

proc scroll*(self: ModelDocumentEditor, amount: float32) {.expose("editor.model").} =
  self.scrollOffset += amount
  self.markDirty()

proc getModeConfig(self: ModelDocumentEditor, mode: string): EventHandlerConfig =
  return self.editor.getEventHandlerConfig("editor.model." & mode)

proc setMode*(self: ModelDocumentEditor, mode: string) {.expose("editor.model").} =
  if mode.len == 0:
    self.modeEventHandler = nil
  else:
    let config = self.getModeConfig(mode)
    self.modeEventHandler = eventHandler(config):
      onAction:
        self.handleAction action, arg
      onInput:
        Ignored

  self.currentMode = mode

proc mode*(self: ModelDocumentEditor): string {.expose("editor.model").} =
  return self.currentMode

proc getContextWithMode(self: ModelDocumentEditor, context: string): string {.expose("editor.model").} =
  return context & "." & $self.currentMode

genDispatcher("editor.model")

proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse =
  # logger.log lvlInfo, fmt"[modeleditor]: Handle action {action}, '{arg}'"

  var args = newJArray()
  args.add api.ModelDocumentEditor(id: self.id).toJson
  for a in newStringStream(arg).parseJsonFragments():
    args.add a

  # var newLastCommand = (action, arg)
  # defer: self.lastCommand = newLastCommand

  if self.editor.handleUnknownDocumentEditorAction(self, action, args) == Handled:
    return Handled

  if dispatch(action, args).isSome:
    return Handled

  return Ignored