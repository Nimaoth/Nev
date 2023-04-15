import std/[strformat, strutils, algorithm, math, logging, sugar, tables, macros, macrocache, options, deques, sets, json, jsonutils, sequtils, streams, os]
import timer
import fusion/matching, fuzzy, bumpy, rect_utils, vmath, chroma
import editor, util, document, document_editor, text_document, events, id, ast_ids, scripting/expose, event, theme, input, custom_async
from scripting_api as api import nil
import custom_logger
import platform/[filesystem, platform, widgets]
import workspaces/[workspace]
import ast/[types, base_language, cells]
import print

from ast import AstNodeKind

var project = newProject()

type
  CellCursor* = object
    firstIndex*: int
    lastIndex*: int
    path*: seq[int]
    node*: AstNode
    cell*: Cell

proc `$`*(cursor: CellCursor): string =
  return fmt"CellCursor({cursor.firstIndex}:{cursor.lastIndex}, {cursor.path}, {cursor.node})"

proc `column=`(cursor: var CellCursor, column: int) =
  cursor.firstIndex = column
  cursor.lastIndex = column

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
    onChanged*: Event[ModelDocument]

    builder*: CellBuilder

  ModelDocumentEditor* = ref object of DocumentEditor
    editor*: Editor
    document*: ModelDocument

    modeEventHandler: EventHandler
    currentMode*: string

    nodeToCell*: Table[Id, Cell] # Map from AstNode.id to Cell
    logicalLines*: seq[seq[Cell]]
    cellWidgetContext*: UpdateContext
    cursor*: CellCursor

    scrollOffset*: float
    previousBaseIndex*: seq[int]

    lastBounds*: Rect

  UpdateContext* = ref object
    cellToWidget*: Table[Id, WWidget]

proc `$`(op: UndoOp): string =
  result = fmt"{op.kind}, '{op.text}'"
  if op.id != null: result.add fmt", id = {op.id}"
  if op.node != nil: result.add fmt", node = {op.node}"
  if op.parent != nil: result.add fmt", parent = {op.parent}, index = {op.idx}"

proc handleNodeInserted*(doc: ModelDocument, node: AstNode)
proc handleNodeInserted*(self: ModelDocumentEditor, doc: ModelDocument, node: AstNode)
proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse
proc rebuildCells*(self: ModelDocumentEditor)
proc getCellForCursor*(self: ModelDocumentEditor, cursor: CellCursor, resolveCollection: bool = true): Option[Cell]
proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool
proc getCursorInLine*(self: ModelDocumentEditor, line: int, xPos: float): Option[CellCursor]

proc toCursor*(cell: Cell, column: int): CellCursor
proc toCursor*(cell: Cell, start: bool): CellCursor
proc canSelect*(cell: Cell): bool
proc isVisible*(cell: Cell): bool
proc selectCursor(a, b: CellCursor, combine: bool): CellCursor

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
classes[ConstDecl] = (constDeclClass, IdINamedName)
classes[LetDecl] = (letDeclClass, IdINamedName)
classes[VarDecl] = (varDeclClass, IdINamedName)
classes[NodeList] = (blockClass, idNone())
classes[Call] = (callClass, idNone())
classes[If] = (ifClass, idNone())
classes[While] = (whileClass, idNone())
classes[FunctionDefinition] = (functionDefinitionClass, idNone())
classes[Params] = (parameterDeclClass, idNone())
classes[Assignment] = (assignmentClass, idNone())

var binaryOperators = initTable[Id, NodeClass]()
binaryOperators[IdAdd] = addExpressionClass
binaryOperators[IdSub] = subExpressionClass
binaryOperators[IdMul] = mulExpressionClass
binaryOperators[IdDiv] = divExpressionClass
binaryOperators[IdMod] = modExpressionClass
binaryOperators[IdAppendString] = appendStringExpressionClass
binaryOperators[IdLess] = lessExpressionClass
binaryOperators[IdLessEqual] = lessEqualExpressionClass
binaryOperators[IdGreater] = greaterExpressionClass
binaryOperators[IdGreaterEqual] = greaterEqualExpressionClass
binaryOperators[IdEqual] = equalExpressionClass
binaryOperators[IdNotEqual] = notEqualExpressionClass
binaryOperators[IdAnd] = andExpressionClass
binaryOperators[IdOr] = orExpressionClass
binaryOperators[IdOrder] = orderExpressionClass

var unaryOperators = initTable[Id, NodeClass]()
unaryOperators[IdNot] = notExpressionClass
unaryOperators[IdNegate] = negateExpressionClass

proc toModel(json: JsonNode, root: bool = false): AstNode =
  let kind = json["kind"].jsonTo AstNodeKind
  let data = classes[kind]
  var node = newAstNode(data.class, json["id"].jsonTo(Id).some)

  # debugf"kind: {kind}, {data}, {node.id}"
  if kind == Empty:
    return nil

  if json.hasKey("reff"):
    let target = json["reff"].jsonTo Id
    if target == IdString:
      node = newAstNode(stringTypeClass, json["id"].jsonTo(Id).some)
    elif target == IdInt:
      node = newAstNode(intTypeClass, json["id"].jsonTo(Id).some)
    elif target == IdVoid:
      node = newAstNode(voidTypeClass, json["id"].jsonTo(Id).some)
    else:
      node.setReference(data.link, target)

  if json.hasKey("text"):
    if kind == NumberLiteral:
      node.setProperty(data.link, PropertyValue(kind: PropertyType.Int, intValue: json["text"].jsonTo(string).parseInt))
    else:
      node.setProperty(data.link, PropertyValue(kind: PropertyType.String, stringValue: json["text"].jsonTo string))

  if json.hasKey("children"):
    let children = json["children"].elems

    case kind
    of NodeList:
      if root:
        node = newAstNode(nodeListClass, json["id"].jsonTo(Id).some)
        for c in children:
          node.add(IdNodeListChildren, c.toModel)
          node.add(IdNodeListChildren, newAstNode(emptyLineClass))

      else:
        for c in children:
          node.add(IdBlockChildren, c.toModel)

    of ConstDecl:
      node.add(IdConstDeclValue, children[0].toModel)
    of LetDecl:
      node.add(IdLetDeclType, children[0].toModel)
      node.add(IdLetDeclValue, children[1].toModel)
    of VarDecl:
      node.add(IdVarDeclType, children[0].toModel)
      node.add(IdVarDeclValue, children[1].toModel)

    of Call:
      let fun = children[0]["reff"].jsonTo(Id)

      if binaryOperators.contains(fun):
        node = newAstNode(binaryOperators[fun], json["id"].jsonTo(Id).some)
        node.add(IdBinaryExpressionLeft, children[1].toModel)
        node.add(IdBinaryExpressionRight, children[2].toModel)

      elif unaryOperators.contains(fun):
        node = newAstNode(unaryOperators[fun], json["id"].jsonTo(Id).some)
        node.add(IdUnaryExpressionChild, children[1].toModel)

      elif fun == IdPrint:
        node = newAstNode(printExpressionClass, json["id"].jsonTo(Id).some)
        for c in children[1..^1]:
          node.add(IdPrintArguments, c.toModel)

      elif fun == IdBuildString:
        node = newAstNode(buildExpressionClass, json["id"].jsonTo(Id).some)
        for c in children[1..^1]:
          node.add(IdBuildArguments, c.toModel)

      else:
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
          param.setProperty(IdINamedName, PropertyValue(kind: PropertyType.String, stringValue: c["text"].jsonTo string))
          param.add(IdParameterDeclType, c["children"][0].toModel)
          node.add(IdFunctionDefinitionParameters, param)
      node.add(IdFunctionDefinitionReturnType, children[1].toModel)
      node.add(IdFunctionDefinitionBody, children[2].toModel)

    else:
      discard

  return node

proc createTypes*(self: ModelDocument) =
  let stringType = () => newAstNode(stringTypeClass)
  let intType = () => newAstNode(intTypeClass)
  let voidType = () => newAstNode(voidTypeClass)
  let functionType = proc (returnType: AstNode, parameterTypes: seq[AstNode]): AstNode =
    result = newAstNode(functionTypeClass)
    result.add(IdFunctionTypeReturnType, returnType)
    for pt in parameterTypes:
      result.add(IdFunctionTypeParameterTypes, pt)

  # testModel.addRootNode(c)
  # self.model.addRootNode functionType()

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

    let root = json.toModel true

    testModel.addRootNode(root)

    self.model = testModel

    self.builder = newCellBuilder()
    for language in self.model.languages:
      self.builder.addBuilder(language.builder)

    project.addModel(self.model)
    project.builder = self.builder

    when defined(js):
      let uiae = `$`(root, true)
      logger.log(lvlDebug, fmt"[modeldoc] Load new model {uiae}")

    self.undoOps.setLen 0
    self.redoOps.setLen 0

  except CatchableError:
    logger.log lvlError, fmt"[modeldoc] Failed to load model source file '{self.filename}': {getCurrentExceptionMsg()}"

  self.onChanged.invoke (self)

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
  self.rebuildCells()
  self.cursor = CellCursor(node: self.document.model.rootNodes[0], path: @[0])
  self.cursor.cell = self.nodeToCell.getOrDefault(self.cursor.node.id)
  print self.cursor
  self.markDirty()

proc buildNodeCellMap(self: Cell, map: var Table[Id, Cell]) =
  if self.node.isNotNil and not map.contains(self.node.id):
    map[self.node.id] = self
  if self of CollectionCell:
    for c in self.CollectionCell.children:
      c.buildNodeCellMap(map)

proc assignToLogicalLines(self: ModelDocumentEditor, cell: Cell, startLine: int, currentLineEmpty: var bool): int =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return startLine

  cell.line = startLine

  if cell of CollectionCell:
    let coll = cell.CollectionCell
    let vertical = coll.layout.kind == Vertical

    var currentLine = startLine
    var maxLine = startLine

    # debugf"assignToLogicalLines {cell.id}, {startLine}, {currentLineEmpty}"

    var currentLineEmptyTemp = currentLineEmpty
    if coll.inline:
      currentLineEmptyTemp = true

    for i, c in coll.children:
      if vertical and (i > 0 or not currentLineEmptyTemp):
        currentLineEmptyTemp = true
        inc currentLine

      if c.style.isNotNil:
        if c.style.onNewLine:
          currentLineEmptyTemp = true
          inc currentLine

      let newLine = self.assignToLogicalLines(c, currentLine, currentLineEmptyTemp)
      if vertical:
        currentLine = newLine
      maxLine = max(maxLine, newLine)

      if c.style.isNotNil:
        if c.style.addNewlineAfter:
          currentLineEmptyTemp = true
          inc currentLine

    if not coll.inline:
      currentLineEmpty = currentLineEmptyTemp

    return maxLine

  else:
    while self.logicalLines.len <= startLine:
      self.logicalLines.add @[]
    self.logicalLines[startLine].add cell
    currentLineEmpty = false
    return startLine

proc rebuildCells(self: ModelDocumentEditor) =
  var builder = self.document.builder

  self.nodeToCell.clear()

  self.logicalLines.setLen 0

  for node in self.document.model.rootNodes:
    let cell = builder.buildCell(node)
    cell.buildNodeCellMap(self.nodeToCell)

    var temp = true
    discard self.assignToLogicalLines(cell, 0, temp)

proc handleNodeInserted*(self: ModelDocumentEditor, doc: ModelDocument, node: AstNode) =
  discard

proc handleDocumentChanged*(self: ModelDocumentEditor, document: Document) =
  self.rebuildCells()
  self.cursor = CellCursor(node: self.document.model.rootNodes[0], path: @[0])
  self.cursor.cell = self.nodeToCell.getOrDefault(self.cursor.node.id)
  # echo self.cursor

  self.markDirty()

proc toJson*(self: api.ModelDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.model")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.ModelDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc handleInput(self: ModelDocumentEditor, input: string): EventResponse =
  logger.log lvlInfo, fmt"[modeleditor]: Handle input '{input}'"

  if self.insertTextAtCursor(input):
    return Handled

  return Ignored

method handleScroll*(self: ModelDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  let scrollAmount = scroll.y * getOption[float](self.editor, "model.scroll-speed", 20)

  self.scrollOffset += scrollAmount
  self.markDirty()

proc getLeafCellContainingPoint*(self: ModelDocumentEditor, cell: Cell, point: Vec2): Option[Cell] =
  let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id, nil)
  if widget.isNil:
    return Cell.none

  # debugf"getLeafCellContainingPoint {cell.node}, {point}, {widget.lastBounds}"
  if not widget.lastBounds.contains(point):
    return Cell.none

  if cell of CollectionCell:
    for c in cell.CollectionCell.children:
      if self.getLeafCellContainingPoint(c, point).getSome(leaf):
        return leaf.some
    return Cell.none

  # debugf"-> {cell.node}, {point}, {widget.lastBounds}"
  return cell.some

method handleMousePress*(self: ModelDocumentEditor, button: MouseButton, mousePosWindow: Vec2) =
  # Make mousePos relative to contentBounds
  if button != MouseButton.Left:
    return

  for rootNode in self.document.model.rootNodes:
    let cell = self.nodeToCell.getOrDefault(rootNode.id, nil)
    if cell.isNil:
      continue

    if self.getLeafCellContainingPoint(cell, mousePosWindow).getSome(leafCell):
      if leafCell.line < self.logicalLines.high:
        if self.getCursorInLine(leafCell.line, mousePosWindow.x).getSome(newCursor):
          self.cursor = selectCursor(self.cursor, newCursor, false)
          self.markDirty()
          break

      self.cursor = leafCell.toCursor(true)
      self.markDirty()
      break

method handleMouseRelease*(self: ModelDocumentEditor, button: MouseButton, mousePosWindow: Vec2) =
  discard

method handleMouseMove*(self: ModelDocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  if MouseButton.Left in buttons:
    for rootNode in self.document.model.rootNodes:
      let cell = self.nodeToCell.getOrDefault(rootNode.id, nil)
      if cell.isNil:
        continue

      if self.getLeafCellContainingPoint(cell, mousePosWindow).getSome(leafCell):
        if leafCell.line < self.logicalLines.high:
          if self.getCursorInLine(leafCell.line, mousePosWindow.x).getSome(newCursor):
            self.cursor = selectCursor(self.cursor, newCursor, true)
            self.markDirty()
            break

        # debugf"line {leafCell.parent.id}|{leafCell.id}: {leafCell.line}"
        self.cursor = selectCursor(self.cursor, leafCell.toCursor(true), true)
        self.markDirty()
        break

method canEdit*(self: ModelDocumentEditor, document: Document): bool =
  if document of ModelDocument: return true
  else: return false

method getEventHandlers*(self: ModelDocumentEditor): seq[EventHandler] =
  result.add self.eventHandler

  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler

method createWithDocument*(_: ModelDocumentEditor, document: Document): DocumentEditor =
  let self = ModelDocumentEditor(eventHandler: nil, document: ModelDocument(document))

  # Emit this to set the editor prototype to editor_model_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [self, " = createWithPrototype(editor_model_prototype, ", self, ");"].}
    # This " is here to fix syntax highlighting

  self.init()
  discard self.document.onNodeInserted.subscribe proc(d: auto) = self.handleNodeInserted(d[0], d[1])
  discard self.document.onChanged.subscribe proc(d: auto) = self.handleDocumentChanged(d)

  self.rebuildCells()
  self.cursor = CellCursor(node: self.document.model.rootNodes[0], path: @[0])
  self.cursor.cell = self.nodeToCell.getOrDefault(self.cursor.node.id)
  # echo self.cursor

  return self

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

proc getCellForCursor*(self: ModelDocumentEditor, cursor: CellCursor, resolveCollection: bool = true): Option[Cell] =
  # let cell = self.nodeToCell.getOrDefault(cursor.node.id, nil)
  # if cell.isNil:
  #   return Cell.none
  let cell = cursor.cell
  assert cell.isNotNil

  # debugf"getCellForCursor {cursor}"
  # defer:
  #   if result.isSome:
  #     debugf"{result.get.dump}"

  var subCell = cell
  for i in cursor.path:
    if subCell of CollectionCell:
      var collectionCell = subCell.CollectionCell
      subCell = collectionCell.children[i.clamp(0, collectionCell.children.high)]
    else:
      break

  if resolveCollection and subCell of CollectionCell:
    return subCell.CollectionCell.children[cursor.lastIndex].some

  return subCell.some

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

proc getCursorInLine*(self: ModelDocumentEditor, line: int, xPos: float): Option[CellCursor] =
  if line notin 0..self.logicalLines.high:
    return CellCursor.none

  let line = self.logicalLines[line]
  if line.len == 0:
    return CellCursor.none

  let charWidth = self.editor.platform.charWidth

  var closest = 10000000000.0
  for c in line:
    if not c.canSelect:
      continue
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(c.id, nil)
    if widget.isNil:
      continue

    let xMin = if c.style.isNotNil and c.style.noSpaceLeft:
      widget.lastBounds.x + charWidth
    else:
      widget.lastBounds.x

    let xMax = if c.style.isNotNil and c.style.noSpaceRight:
      widget.lastBounds.xw - charWidth
    else:
      widget.lastBounds.xw

    if xPos < xMin:
      if result.isNone or xMin - xPos < closest:
        result = c.toCursor(true).some
        closest = xMin - xPos
    elif xPos > xMax:
      if result.isNone or xPos - xMax < closest:
        result = c.toCursor(false).some
        closest = xPos - xMax
    else:
      result = c.toCursor(true).some

      let text = c.getText()
      if text.len > 0:
        let alpha = (xPos - widget.lastBounds.x) / widget.lastBounds.w
        result.get.firstIndex = (alpha * text.len.float).round.int
        result.get.lastIndex = (alpha * text.len.float).round.int

      return

proc getCursorXPos*(self: ModelDocumentEditor, cursor: CellCursor): float =
  result = 0
  if self.getCellForCursor(cursor).getSome(cell):
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id, nil)
    if widget.isNotNil:
      let text = cell.getText()
      if text.len == 0:
        result = widget.lastBounds.x
      else:
        let alpha = cursor.lastIndex.float / text.len.float
        result = widget.lastBounds.x * (1 - alpha) + widget.lastBounds.xw * alpha

proc getPreviousCellInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  # defer:
  #   debugf"getPreviousCellInLine {cell.dump} -> {result.dump}"

  if cell.line < 0 and cell.line > self.logicalLines.high:
    return cell

  let line = self.logicalLines[cell.line]

  var index = -1
  for i, c in line:
    if c.isDecendant(cell) and index == -1:
      index = i
    elif c == cell:
      index = i
      break

  if index == -1:
    index = 0

  # echo index

  if index == 0:
    # Last cell in line, find next cell on next line
    for k in 0..(cell.line - 1):
      let i = cell.line - 1 - k
      if self.logicalLines[i].len > 0:
        return self.logicalLines[i][self.logicalLines[i].high]
    return cell
  else:
    return line[index - 1]

proc getNextCellInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  # defer:
  #   debugf"getNextCellInLine {cell.dump} -> {result.dump}"

  if cell.line < 0 and cell.line > self.logicalLines.high:
    return cell

  let line = self.logicalLines[cell.line]

  var index = line.high
  for i, c in line:
    if c.isDecendant(cell):
      index = i
    elif c == cell:
      index = i
      break

  if index >= line.high:
    # Last cell in line, find next cell on next line
    for i in (cell.line + 1)..self.logicalLines.high:
      if self.logicalLines[i].len > 0:
        return self.logicalLines[i][0]
    return cell
  else:
    return line[index + 1]

proc getPreviousInLineWhere*(self: ModelDocumentEditor, cell: Cell, predicate: proc(cell: Cell): bool): Cell =
  result = self.getPreviousCellInLine(cell)
  while not predicate(result):
    let oldResult = result
    result = self.getPreviousCellInLine(result)
    if result == oldResult:
      break

proc getNextInLineWhere*(self: ModelDocumentEditor, cell: Cell, predicate: proc(cell: Cell): bool): Cell =
  result = self.getNextCellInLine(cell)
  while not predicate(result):
    let oldResult = result
    result = self.getNextCellInLine(result)
    if result == oldResult:
      break

proc getPreviousSelectableInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  return self.getPreviousInLineWhere(cell, canSelect)

proc getNextSelectableInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  return self.getNextInLineWhere(cell, canSelect)

proc getPreviousVisibleInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  return self.getPreviousInLineWhere(cell, isVisible)

proc getNextVisibleInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  return self.getNextInLineWhere(cell, isVisible)

method getCursorLeft*(cell: Cell, cursor: CellCursor): CellCursor {.base.} = discard
method getCursorRight*(cell: Cell, cursor: CellCursor): CellCursor {.base.} = discard

proc isVisible*(cell: Cell): bool =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return false

  return true

proc canSelect*(cell: Cell): bool =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return false
  if cell.disableSelection:
    return false
  if cell.editableLow > cell.editableHigh + 1:
    return false

  return true

proc getFirstLeaf*(cell: Cell): Cell =
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.CollectionCell.children[0].getFirstLeaf()
  return cell

proc getLastLeaf*(cell: Cell): Cell =
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.CollectionCell.children[cell.CollectionCell.children.high].getLastLeaf()
  return cell

proc getPreviousLeaf*(cell: Cell, childIndex: Option[int] = int.none): Cell =
  if cell of CollectionCell:
    return cell.getLastLeaf()
  # if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    # let index = if childIndex.getSome(index): index else: cell.CollectionCell.children.len
    # if index > 0:
    #   result = cell.CollectionCell.children[index - 1]
    #   if result of CollectionCell:
    #     result = result.getPreviousLeaf()
    #   return

  if cell.parent.isNil:
    return cell

  let parent = cell.parent.CollectionCell

  var index = parent.indexOf(cell)

  if index > 0:
    return parent.children[index - 1].getLastLeaf()
  else:
    var newParent: Cell = parent
    var parentIndex = newParent.index
    while parentIndex != -1 and parentIndex == 0:
      newParent = newParent.parent
      parentIndex = newParent.index

    if parentIndex > 0:
      let prevParent = newParent.previousDirect()
      return prevParent.getLastLeaf()

    return cell

proc getNextLeaf*(cell: Cell, childIndex: Option[int] = int.none): Cell =
  if cell of CollectionCell:
    return cell.getFirstLeaf()
  # if cell of CollectionCell and cell.CollectionCell.children.len > 0:
  #   let index = if childIndex.getSome(index): index else: 0
  #   if index < cell.CollectionCell.children.high:
  #     result = cell.CollectionCell.children[index + 1]
  #     if result of CollectionCell:
  #       result = result.getNextLeaf()
  #     return

  if cell.parent.isNil:
    return cell

  let parent = cell.parent.CollectionCell

  var index = parent.indexOf(cell)

  if index < parent.children.high:
    return parent.children[index + 1].getFirstLeaf()
  else:
    var newParent: Cell = parent
    var parentIndex = newParent.index
    while parentIndex != -1 and parentIndex >= newParent.parentHigh:
      newParent = newParent.parent
      parentIndex = newParent.index

    if parentIndex < newParent.parentHigh:
      let prevParent = newParent.nextDirect()
      return prevParent.getFirstLeaf()

    return cell

proc getPreviousLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Cell =
  result = cell.getPreviousLeaf()
  while not predicate(result):
    let oldResult = result
    result = result.getPreviousLeaf()
    if result == oldResult:
      break

proc getNextLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Cell =
  result = cell.getNextLeaf()
  while not predicate(result):
    let oldResult = result
    result = result.getNextLeaf()
    if result == oldResult:
      break

proc getPreviousSelectableLeaf*(cell: Cell): Cell =
  return cell.getPreviousLeafWhere(canSelect)

proc getNextSelectableLeaf*(cell: Cell): Cell =
  return cell.getNextLeafWhere(canSelect)

proc getPreviousVisibleLeaf*(cell: Cell): Cell =
  return cell.getPreviousLeafWhere(isVisible)

proc getNextVisibleLeaf*(cell: Cell): Cell =
  return cell.getNextLeafWhere(isVisible)

proc nodeRootCell*(cell: Cell, targetNode: Option[AstNode] = AstNode.none): Cell =
  ### Returns the highest parent cell which has the same node (or itself if the parent has a different node)
  result = cell

  if targetNode.getSome(targetNode):
    while result.parent.isNotNil and (result.node != targetNode or result.parent.node == cell.node):
      result = result.parent
  else:
    while result.parent.isNotNil and result.parent.node == cell.node:
      result = result.parent

proc nodeRootCellPath*(cell: Cell): tuple[cell: Cell, path: seq[int]] =
  ### Returns the highest parent cell which has the same node (or itself if the parent has a different node)
  ### aswell as the path from the parent cell to this cell
  result.cell = cell
  result.path = @[]

  while result.cell.parent.isNotNil and result.cell.parent.node == cell.node:
    let index = result.cell.parent.CollectionCell.indexOf(cell)
    result.path.add index
    result.cell = result.cell.parent

proc toCursor*(cell: Cell, column: int): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.node = cell.node
  result.cell = rootCell
  result.path = path
  result.column = clamp(column, cell.editableLow, cell.editableHigh + 1)

proc toCursor*(cell: Cell, start: bool): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.node = cell.node
  result.cell = rootCell
  result.path = path
  if start:
    result.column = cell.editableLow
  else:
    result.column = cell.editableHigh + 1

method getCursorLeft*(cell: CollectionCell, cursor: CellCursor): CellCursor =
  if cell.children.len == 0:
    return cursor

  let childCell = cell.children[0]
  result.node = childCell.node
  result.path = if cell.node == childCell.node: cursor.path & 0 else: @[]
  result.cell = cell
  result.column = 0

method getCursorLeft*(cell: ConstantCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex > cell.editableLow:
    result = cursor
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getPreviousSelectableLeaf().toCursor(false)

method getCursorLeft*(cell: NodeReferenceCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex > cell.editableLow:
    result = cursor
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getPreviousSelectableLeaf().toCursor(false)

method getCursorLeft*(cell: AliasCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex > cell.editableLow:
    result = cursor
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getPreviousSelectableLeaf().toCursor(false)

method getCursorLeft*(cell: PropertyCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex > cell.editableLow:
    result = cursor
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getPreviousSelectableLeaf().toCursor(false)

method getCursorRight*(cell: ConstantCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex <= cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: NodeReferenceCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex <= cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: AliasCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex <= cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: PropertyCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex <= cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: CollectionCell, cursor: CellCursor): CellCursor =
  if cell.children.len == 0:
    return cursor

  let childCell = cell.children[cell.children.high]
  result.node = childCell.node
  result.path = if cell.node == childCell.node: cursor.path & cell.children.high else: @[]
  result.cell = cell
  result.column = 0

proc combineCursors(a, b: CellCursor): CellCursor =
  # defer:
    # echo result

  if a.node == b.node:
    result.node = a.node
    result.cell = a.cell
    if a.path == b.path:
      # debugf"same node and path {a.firstIndex}:{a.lastIndex}, {b.firstIndex}:{b.lastIndex}, {a.path}, {a.node}"
      result.path = a.path
      result.firstIndex = a.firstIndex
      result.lastIndex = b.lastIndex
    elif a.path.len == 0 or b.path.len == 0:
      # debugf"same node one path empty {a.firstIndex}:{a.lastIndex}, {b.firstIndex}:{b.lastIndex}, {a.path}, {b.path}, {a.node}"
      result.path = @[]
      result.firstIndex = 0
      result.lastIndex = 0

      if a.path.len == 0 and b.path.len > 0:
        result.firstIndex = a.firstIndex
        # result.firstIndex = child.cell.ancestor(result.cell).index
        result.lastIndex = b.path[0]
      elif a.path.len > 0 and b.path.len == 0:
        result.firstIndex = a.path[0]
        result.lastIndex = b.lastIndex
        # result.lastIndex = child.cell.ancestor(result.cell).index

    else:
      # debugf"same node diff path {a.firstIndex}:{a.lastIndex}, {b.firstIndex}:{b.lastIndex}, {a.path}, {b.path}, {a.node}"
      var firstDifference = 0
      for i in 0..min(a.path.high, b.path.high):
        if a.path[i] != b.path[i]:
          firstDifference = i
          break

      result.path = a.path[0..<firstDifference]
      result.firstIndex = a.path[firstDifference]
      result.lastIndex = b.path[firstDifference]

  else:
    # debugf"different node {a.firstIndex}:{a.lastIndex}, {b.firstIndex}:{b.lastIndex}, {a.path}, {b.path}, {a.node}, {b.node}"
    let depthA = a.node.depth
    let depthB = b.node.depth

    # Selector ancestors of a.node and b.node so they are at the same depth
    var node1 = a.node
    var node2 = b.node
    var child = a   # Either a or b, the one lower in the tree
    if depthA < depthB:
      child = b
      node2 = node2.ancestor(depthB - depthA)
    elif depthA > depthB:
      child = a
      node1 = node1.ancestor(depthA - depthB)

    # debugf"same depth: {node1}, {node2}, {child.node}"

    if node1 == node2:
      # After moving one node up they node are the same, so one was the child of the other
      result.node = node1
      result.cell = if depthA < depthB: a.cell else: b.cell
      # result.cell = a.cell.nodeRootCell(result.node.some)

      result.path = @[]

      let childIndex = child.cell.ancestor(result.cell).index

      if depthA < depthB:
        # b is child
        # echo "b is child"
        result.firstIndex = if a.path.len > 0: a.path[0] else: a.firstIndex
        result.lastIndex = childIndex
      elif depthA > depthB:
        # b is child
        # echo "a is child"
        result.firstIndex = childIndex
        result.lastIndex = if b.path.len > 0: b.path[0] else: b.lastIndex

      # if a.path.len == 0 and b.path.len > 0:
      #   # result.firstIndex = a.firstIndex
      #   result.firstIndex =
      #   result.lastIndex = b.path[0]
      # elif a.path.len > 0 and b.path.len == 0:
      #   result.firstIndex = a.path[0]
      #   # result.lastIndex = b.lastIndex
      #   result.lastIndex = child.cell.ancestor(result.cell).index
      else:
        result.firstIndex = 0
        result.lastIndex = result.cell.high
      return

    # Find common parent of node1 and node2, assuming they are at the same depth
    while node1.parent != node2.parent and node1.parent.isNotNil and node2.parent.isNotNil:
      node1 = node1.parent
      node2 = node2.parent

    # debugf"common parent: {node1}, {node2}, {node1.parent}, {node2.parent}"

    if node1.parent == node2.parent:
      result.node = node1.parent
      result.cell = a.cell.nodeRootCell(result.node.some)
      result.path = @[]
      # echo a.cell.dump
      # echo b.cell.dump
      # echo result.cell.dump true
      result.firstIndex = a.cell.ancestor(result.cell).index
      result.lastIndex = b.cell.ancestor(result.cell).index
      # result.lastIndex = result.cell.high
    else:
      return b

proc selectCursor(a, b: CellCursor, combine: bool): CellCursor =
  if combine:
    return combineCursors(a, b)
  return b

method handleDeleteLeft*(cell: Cell, column: int): CellCursor {.base.} = discard
method handleDeleteRight*(cell: Cell, column: int): CellCursor {.base.} = discard

method handleDeleteLeft*(cell: PropertyCell, column: int): CellCursor =
  var text = cell.getText()
  if column >= 1 and column <= text.len:
    text.delete(column - 1, column - 1)
    cell.setText(text)
    return cell.toCursor(column - 1)

method handleDeleteRight*(cell: PropertyCell, column: int): CellCursor =
  var text = cell.getText()
  if column >= 0 and column < text.len:
    text.delete(column, column)
    cell.setText(text)
    return cell.toCursor(column)

proc mode*(self: ModelDocumentEditor): string {.expose("editor.model").} =
  return self.currentMode

proc getContextWithMode*(self: ModelDocumentEditor, context: string): string {.expose("editor.model").} =
  return context & "." & $self.currentMode

proc moveCursorLeft*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    let newCursor = cell.getCursorLeft(self.cursor)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorRight*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    let newCursor = cell.getCursorRight(self.cursor)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorLeftLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    var newCursor = cell.getCursorLeft(self.cursor)
    # echo newCursor
    if newCursor.node == self.cursor.node:
      # echo "a"
      self.cursor = selectCursor(self.cursor, newCursor, select)
    else:
      # self.cursor = selectCursor(self.cursor, self.getPreviousSelectableInLine(cell).toCursor(false), select)
      # echo "b"
      let nextCell = self.getPreviousSelectableInLine(cell)
      # echo nextCell.dump
      newCursor = nextCell.toCursor(false)
      # echo newCursor
      self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorRightLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    var newCursor = cell.getCursorRight(self.cursor)
    # echo newCursor
    if newCursor.node == self.cursor.node:
      # echo "a"
      self.cursor = selectCursor(self.cursor, newCursor, select)
    else:
      # echo "b"
      let nextCell = self.getNextSelectableInLine(cell)
      # echo nextCell.dump
      newCursor = nextCell.toCursor(true)
      # echo newCursor
      self.cursor = selectCursor(self.cursor, newCursor, select)
  self.markDirty()

proc moveCursorLineStart*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    if cell.line >= 0 and cell.line <= self.logicalLines.high and self.logicalLines[cell.line].len > 0:
      let newCursor = self.logicalLines[cell.line][0].toCursor(true)
      self.cursor = selectCursor(self.cursor, newCursor, select)
  self.markDirty()

proc moveCursorLineEnd*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    if cell.line >= 0 and cell.line <= self.logicalLines.high and self.logicalLines[cell.line].len > 0:
      let newCursor = self.logicalLines[cell.line][self.logicalLines[cell.line].high].toCursor(false)
      self.cursor = selectCursor(self.cursor, newCursor, select)
  self.markDirty()

proc moveCursorLineStartInline*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    var parent = cell.closestInlineAncestor()

    if parent.isNil:
      self.moveCursorLineStart()
      return

    var prevCell = cell
    while true:
      let currentCell = self.getPreviousSelectableInLine(prevCell)
      if currentCell.line != prevCell.line:
        break
      if not currentCell.hasAncestor(parent):
        break

      prevCell = currentCell

    let newCursor = prevCell.toCursor(true)
    self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorLineEndInline*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    var parent = cell.closestInlineAncestor()

    if parent.isNil:
      self.moveCursorLineEnd()
      return

    var prevCell = cell
    while true:
      let currentCell = self.getNextSelectableInLine(prevCell)
      if currentCell.line != prevCell.line:
        break
      if not currentCell.hasAncestor(parent):
        break

      prevCell = currentCell

    let newCursor = prevCell.toCursor(false)
    self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorUp*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    if cell.line > 0 and cell.line <= self.logicalLines.high:
      if self.getCursorInLine(cell.line - 1, self.getCursorXPos(self.cursor)).getSome(newCursor):
        self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorDown*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    if cell.line < self.logicalLines.high:
      if self.getCursorInLine(cell.line + 1, self.getCursorXPos(self.cursor)).getSome(newCursor):
        self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorLeftCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    let newCursor = cell.getPreviousSelectableLeaf().toCursor(false)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorRightCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    let newCursor = cell.getNextSelectableLeaf().toCursor(true)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc deleteLeft*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    if self.cursor.lastIndex <= cell.editableLow:
      let prev = cell.getPreviousVisibleLeaf()
      if prev != cell:
        let newCursor = prev.handleDeleteLeft(prev.high)
        if newCursor.node.isNotNil:
          self.cursor = newCursor
    else:
      let newCursor = cell.handleDeleteLeft(self.cursor.lastIndex)
      if newCursor.node.isNotNil:
        self.cursor = newCursor

  self.markDirty()

proc deleteRight*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    if self.cursor.lastIndex >= cell.editableHigh + 1:
      let prev = cell.getNextVisibleLeaf()
      if prev != cell:
        let newCursor = prev.handleDeleteRight(0)
        if newCursor.node.isNotNil:
          self.cursor = newCursor
    else:
      let newCursor = cell.handleDeleteRight(self.cursor.lastIndex)
      if newCursor.node.isNotNil:
        self.cursor = newCursor

  self.markDirty()

proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool {.expose("editor.model").} =
  if self.getCellForCursor(self.cursor).getSome(cell):
    let newColumn = cell.insertText(self.cursor.lastIndex, input)
    if newColumn != self.cursor.lastIndex:
      self.cursor.lastIndex = newColumn
      self.markDirty()
      return true
  return false

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