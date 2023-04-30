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

proc orderedRange*(cursor: CellCursor): Slice[int] =
  return min(cursor.firstIndex, cursor.lastIndex)..max(cursor.firstIndex, cursor.lastIndex)

proc targetCell*(cursor: CellCursor): Cell =
  result = cursor.cell
  for i in cursor.path:
    if result of CollectionCell:
      result = result.CollectionCell.children[i]

proc selectEntireNode*(cursor: CellCursor): CellCursor =
  result = cursor
  if result.path.len > 0:
    result.column = result.path[result.path.high]
    discard result.path.pop()

type
  ModelOperationKind = enum
    Delete
    Replace
    Insert
    PropertyChange
    ReferenceChange

  ModelOperation = ref object
    kind: ModelOperationKind
    parent: AstNode       # The parent where a node was in inserted or deleted
    node: AstNode         # The node which was inserted/deleted
    idx: int              # The index where a node was inserted/deleted
    role: Id              # The role where a node was inserted/deleted
    value: PropertyValue  # The new/old text of a property
    id: Id                # The new/old id of a reference
    slice: Slice[int]     # The range of text that changed

  ModelTransaction* = object
    operations*: seq[ModelOperation]

  ModelDocument* = ref object of Document
    filename*: string
    model*: Model
    project*: Project

    currentTransaction: ModelTransaction
    undoList: seq[ModelTransaction]
    redoList: seq[ModelTransaction]

    onModelChanged*: Event[ModelDocument]

    builder*: CellBuilder

  ModelCompletionKind* {.pure.} = enum
    SubstituteClass
    SubstituteReference

  ModelCompletion* = object
    parent*: AstNode
    role*: Id
    index*: int
    class*: NodeClass
    name*: string

    case kind*: ModelCompletionKind
    of SubstituteClass:
      discard
    of SubstituteReference:
      referenceRole*: Id
      referenceTarget*: AstNode

  ModelDocumentEditor* = ref object of DocumentEditor
    editor*: Editor
    document*: ModelDocument

    modeEventHandler: EventHandler
    completionEventHandler: EventHandler
    currentMode*: string

    nodeToCell*: Table[Id, Cell] # Map from AstNode.id to Cell
    logicalLines*: seq[seq[Cell]]
    cellWidgetContext*: UpdateContext
    mCursor: CellCursor

    useDefaultCellBuilder*: bool

    scrollOffset*: float
    previousBaseIndex*: seq[int]

    lastBounds*: Rect

    showCompletions*: bool
    completionText: string
    hasCompletions*: bool
    filteredCompletions*: seq[ModelCompletion]
    unfilteredCompletions*: seq[ModelCompletion]
    selectedCompletion*: int
    lastItems*: seq[tuple[index: int, widget: WWidget]]
    completionsBaseIndex*: int
    completionsScrollOffset*: float
    scrollToCompletion*: Option[int]
    lastCompletionsWidget*: WWidget

  UpdateContext* = ref object
    cellToWidget*: Table[Id, WWidget]

proc `$`(op: ModelOperation): string =
  result = fmt"{op.kind}, '{op.value}'"
  if op.id != null: result.add fmt", id = {op.id}"
  if op.node != nil: result.add fmt", node = {op.node}"
  if op.parent != nil: result.add fmt", parent = {op.parent}, index = {op.idx}"

proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse
proc rebuildCells*(self: ModelDocumentEditor)
proc getTargetCell*(cursor: CellCursor, resolveCollection: bool = true): Option[Cell]
proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool
proc getCursorInLine*(self: ModelDocumentEditor, line: int, xPos: float): Option[CellCursor]
proc applySelectedCompletion*(self: ModelDocumentEditor)
proc updateCompletions(self: ModelDocumentEditor)
proc invalidateCompletions(self: ModelDocumentEditor)
proc refilterCompletions(self: ModelDocumentEditor)

proc toCursor*(cell: Cell, column: int): CellCursor
proc toCursor*(cell: Cell, start: bool): CellCursor
proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): CellCursor
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

proc cursor*(self: ModelDocumentEditor): CellCursor = self.mCursor

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursor) =
  if self.mCursor.targetCell != cursor.targetCell:
    self.mCursor = cursor
    self.invalidateCompletions()
  else:
    self.mCursor = cursor
    self.refilterCompletions()

proc handleNodeDeleted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  # debugf "handleNodeDeleted {parent}, {child}, {role}, {index}"
  self.currentTransaction.operations.add ModelOperation(kind: Delete, parent: parent, node: child, idx: index, role: role)

proc handleNodeInserted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  # debugf "handleNodeInserted {parent}, {child}, {role}, {index}"
  self.currentTransaction.operations.add ModelOperation(kind: Insert, parent: parent, node: child, idx: index, role: role)

proc handleNodePropertyChanged(self: ModelDocument, model: Model, node: AstNode, role: Id, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  # debugf "handleNodePropertyChanged {node}, {role}, {oldValue}, {newValue}"
  self.currentTransaction.operations.add ModelOperation(kind: PropertyChange, node: node, role: role, value: oldValue, slice: slice)

proc handleNodeReferenceChanged(self: ModelDocument, model: Model, node: AstNode, role: Id, oldRef: Id, newRef: Id) =
  # debugf "handleNodeReferenceChanged {node}, {role}, {oldRef}, {newRef}"
  self.currentTransaction.operations.add ModelOperation(kind: ReferenceChange, node: node, role: role, id: oldRef)

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
    discard self.model.onNodeDeleted.subscribe proc(d: auto) = self.handleNodeDeleted(d[0], d[1], d[2], d[3], d[4])
    discard self.model.onNodeInserted.subscribe proc(d: auto) = self.handleNodeInserted(d[0], d[1], d[2], d[3], d[4])
    discard self.model.onNodePropertyChanged.subscribe proc(d: auto) = self.handleNodePropertyChanged(d[0], d[1], d[2], d[3], d[4], d[5])
    discard self.model.onNodeReferenceChanged.subscribe proc(d: auto) = self.handleNodeReferenceChanged(d[0], d[1], d[2], d[3], d[4])

    self.builder = newCellBuilder()
    for language in self.model.languages:
      self.builder.addBuilder(language.builder)

    project.addModel(self.model)
    project.builder = self.builder

    when defined(js):
      let uiae = `$`(root, true)
      logger.log(lvlDebug, fmt"[modeldoc] Load new model {uiae}")

    self.undoList.setLen 0
    self.redoList.setLen 0

  except CatchableError:
    logger.log lvlError, fmt"[modeldoc] Failed to load model source file '{self.filename}': {getCurrentExceptionMsg()}"

  self.onModelChanged.invoke (self)

method load*(self: ModelDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename
  asyncCheck self.loadAsync()

proc getSubstitutionTarget(cell: Cell): (AstNode, Id, int) =
  if cell of PlaceholderCell:
    return (cell.node, cell.PlaceholderCell.role, 0)
  return (cell.node.parent, cell.node.role, cell.node.index)

proc getSubstitutionsForClass(self: ModelDocumentEditor, targetCell: Cell, class: NodeClass, outCompletions: var seq[ModelCompletion]): bool =
  if class.references.len == 1:
    let desc = class.references[0]
    let language = self.document.model.getLanguageForClass(desc.class)
    let refClass = language.resolveClass(desc.class)

    let (parent, role, index) = targetCell.getSubstitutionTarget()

    for node in self.document.model.rootNodes:
      node.forEach2 n:
        let nClass = language.resolveClass(n.class)
        if nClass.isSubclassOf(refClass.id):
          let name = if n.property(IdINamedName).getSome(name): name.stringValue else: $n.id
          outCompletions.add ModelCompletion(kind: ModelCompletionKind.SubstituteReference, name: name, class: class, referenceRole: desc.id, referenceTarget: n, parent: parent, role: role, index: index)

  return false

proc refilterCompletions(self: ModelDocumentEditor) =
  self.filteredCompletions.setLen 0

  let targetCell = self.cursor.targetCell
  if targetCell of CollectionCell:
    return

  let text = targetCell.currentText
  let index = self.cursor.lastIndex

  let prefix = text[0..<index]

  # debugf "refilter '{text}' {index} -> '{prefix}'"

  for completion in self.unfilteredCompletions:
    if completion.name.startsWith(prefix):
      self.filteredCompletions.add completion

  self.hasCompletions = true

  if self.filteredCompletions.len > 0:
    self.selectedCompletion = self.selectedCompletion.clamp(0, self.filteredCompletions.len - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some

proc invalidateCompletions(self: ModelDocumentEditor) =
  self.unfilteredCompletions.setLen 0
  self.filteredCompletions.setLen 0
  self.hasCompletions = false

proc updateCompletions(self: ModelDocumentEditor) =
  self.unfilteredCompletions.setLen 0

  let targetCell = self.cursor.targetCell
  if targetCell of CollectionCell or targetCell of PropertyCell:
    self.refilterCompletions()
    return

  let (parent, role, index) = targetCell.getSubstitutionTarget()
  let node = self.cursor.node

  let parentClass = parent.nodeClass
  let childDesc = parentClass.nodeChildDescription(role).get

  # Substitutions for owner of target cell
  let model = node.model

  let desc = childDesc
  let slotClass = model.resolveClass(desc.class)

  # debugf"updateCompletions {node}, {node.model.isNotNil}, {slotClass.name}"

  for language in model.languages:
    language.forEachChildClass slotClass, proc(childClass: NodeClass) =
      if self.getSubstitutionsForClass(targetCell, childClass, self.unfilteredCompletions):
        return

      if childClass.isAbstract or childClass.isInterface:
        return

      # debugf"{parent}, {role}, {index}"
      let name = if childClass.alias.len > 0: childClass.alias else: childClass.name
      self.unfilteredCompletions.add ModelCompletion(kind: ModelCompletionKind.SubstituteClass, name: name, class: childClass, parent: parent, role: role, index: index)

  self.refilterCompletions()
  self.markDirty()

proc getCompletion*(self: ModelDocumentEditor, index: int): ModelCompletion =
  if not self.hasCompletions:
    self.updateCompletions()
  return self.filteredCompletions[index]

proc completions*(self: ModelDocumentEditor): seq[ModelCompletion] =
  if not self.hasCompletions:
    self.updateCompletions()
  return self.filteredCompletions

proc completionsLen*(self: ModelDocumentEditor): int =
  if not self.hasCompletions:
    self.updateCompletions()
  return self.filteredCompletions.len

proc finishTransaction*(self: ModelDocument, clearRedoList: bool = true) =
  if self.currentTransaction.operations.len > 0:
    self.undoList.add self.currentTransaction
    if clearRedoList:
      self.redoList.setLen 0
  self.currentTransaction = ModelTransaction()

proc finishRedoTransaction*(self: ModelDocument, clearUndoList: bool = false) =
  if self.currentTransaction.operations.len > 0:
    self.redoList.add self.currentTransaction
    if clearUndoList:
      self.undoList.setLen 0
  self.currentTransaction = ModelTransaction()

proc reverseModelOperation*(self: ModelDocument, op: ModelOperation) =
  case op.kind
  of Delete:
    op.parent.insert(op.role, op.idx, op.node)
  of Insert:
    op.parent.remove(op.node)
  of PropertyChange:
    op.node.setProperty(op.role, op.value)
  of ReferenceChange:
    op.node.setReference(op.role, op.id)
  else:
    discard

proc undo*(self: ModelDocument): Option[ModelOperation] =
  self.finishTransaction()

  if self.undoList.len == 0:
    return ModelOperation.none

  let t = self.undoList.pop
  logger.log(lvlInfo, fmt"Undoing {t}")

  for i in countdown(t.operations.high, 0):
    let op = t.operations[i]
    result = op.some
    self.reverseModelOperation(op)

  self.finishRedoTransaction()

proc redo*(self: ModelDocument): Option[ModelOperation] =
  self.finishTransaction()

  if self.redoList.len == 0:
    return ModelOperation.none

  let t = self.redoList.pop
  logger.log(lvlInfo, fmt"Redoing {t}")

  for i in countdown(t.operations.high, 0):
    let op = t.operations[i]
    result = op.some
    self.reverseModelOperation(op)

  self.finishTransaction(false)

proc handleNodeDeleted(self: ModelDocumentEditor, model: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  # debugf "handleNodeDeleted {parent}, {child}, {role}, {index}"
  self.invalidateCompletions()

proc handleNodeInserted(self: ModelDocumentEditor, model: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  # debugf "handleNodeInserted {parent}, {child}, {role}, {index}"
  self.invalidateCompletions()

proc handleNodePropertyChanged(self: ModelDocumentEditor, model: Model, node: AstNode, role: Id, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  # debugf "handleNodePropertyChanged {node}, {role}, {oldValue}, {newValue}"
  self.invalidateCompletions()

proc handleNodeReferenceChanged(self: ModelDocumentEditor, model: Model, node: AstNode, role: Id, oldRef: Id, newRef: Id) =
  # debugf "handleNodeReferenceChanged {node}, {role}, {oldRef}, {newRef}"
  self.invalidateCompletions()

proc handleModelChanged(self: ModelDocumentEditor, document: ModelDocument) =
  # debugf "handleModelChanged"

  discard self.document.model.onNodeDeleted.subscribe proc(d: auto) = self.handleNodeDeleted(d[0], d[1], d[2], d[3], d[4])
  discard self.document.model.onNodeInserted.subscribe proc(d: auto) = self.handleNodeInserted(d[0], d[1], d[2], d[3], d[4])
  discard self.document.model.onNodePropertyChanged.subscribe proc(d: auto) = self.handleNodePropertyChanged(d[0], d[1], d[2], d[3], d[4], d[5])
  discard self.document.model.onNodeReferenceChanged.subscribe proc(d: auto) = self.handleNodeReferenceChanged(d[0], d[1], d[2], d[3], d[4])

  self.rebuildCells()
  self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0])

  self.markDirty()

method handleDocumentChanged*(self: ModelDocumentEditor) =
  logger.log(lvlInfo, fmt"[model-editor] Document changed")
  # self.selectionHistory.clear
  # self.selectionFuture.clear
  # self.finishEdit false
  # for symbol in ctx.globalScope.values:
  #   discard ctx.newSymbol(symbol)
  # self.node = self.document.rootNode[0]
  self.rebuildCells()
  self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0])

  print self.cursor
  self.markDirty()

proc buildNodeCellMap(self: Cell, map: var Table[Id, Cell]) =
  if self.node.isNotNil and not map.contains(self.node.id):
    map[self.node.id] = self
  if self of CollectionCell:
    for c in self.CollectionCell.children:
      c.buildNodeCellMap(map)

proc assignToLogicalLines(self: ModelDocumentEditor, cell: Cell, startLine: int, currentLineEmpty: var bool): tuple[currentLine: int, maxLine: int] =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return (startLine, startLine)

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
        currentLine = maxLine
        inc currentLine
        maxLine = max(maxLine, currentLine)

      if c.style.isNotNil:
        if c.style.onNewLine and not currentLineEmptyTemp:
          currentLineEmptyTemp = true
          currentLine = maxLine
          inc currentLine
          maxLine = max(maxLine, currentLine)

      let (newCurrentLine, newMaxLine) = self.assignToLogicalLines(c, currentLine, currentLineEmptyTemp)
      maxLine = max(maxLine, newMaxLine)

      if not (c of CollectionCell and c.CollectionCell.inline):
        currentLine = newCurrentLine

      maxLine = max(maxLine, currentLine)

      if c.style.isNotNil:
        if c.style.addNewlineAfter:
          currentLine = maxLine
          currentLineEmptyTemp = true
          inc currentLine
          maxLine = max(maxLine, currentLine)

    if not coll.inline:
      currentLineEmpty = currentLineEmptyTemp

    return (currentLine, maxLine)

  else:
    while self.logicalLines.len <= startLine:
      self.logicalLines.add @[]
    self.logicalLines[startLine].add cell
    currentLineEmpty = false
    return (startLine, startLine)

proc rebuildCells(self: ModelDocumentEditor) =
  var builder = self.document.builder

  self.nodeToCell.clear()

  self.logicalLines.setLen 0

  for node in self.document.model.rootNodes:
    let cell = builder.buildCell(node, self.useDefaultCellBuilder)
    cell.buildNodeCellMap(self.nodeToCell)

    var temp = true
    discard self.assignToLogicalLines(cell, 0, temp)

proc toJson*(self: api.ModelDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.model")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.ModelDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc handleInput(self: ModelDocumentEditor, input: string): EventResponse =
  logger.log lvlInfo, fmt"[modeleditor]: Handle input '{input}'"

  if self.insertTextAtCursor(input):
    self.document.finishTransaction()
    return Handled

  return Ignored

proc getItemAtPixelPosition(self: ModelDocumentEditor, posWindow: Vec2): Option[int] =
  result = int.none
  for (index, widget) in self.lastItems:
    if widget.lastBounds.contains(posWindow) and index >= 0 and index < self.completionsLen:
      return index.some

method handleScroll*(self: ModelDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  let scrollAmount = scroll.y * getOption[float](self.editor, "model.scroll-speed", 20)

  if self.showCompletions and not self.lastCompletionsWidget.isNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
    self.completionsScrollOffset += scrollAmount
    self.markDirty()
  else:
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
  if self.showCompletions and self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if button == MouseButton.Left or button == MouseButton.Middle:
      self.selectedCompletion = item
      self.markDirty()
    return

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
  if self.showCompletions and button == MouseButton.Left and self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if self.selectedCompletion == item:
      self.applySelectedCompletion()
      self.markDirty()

method handleMouseMove*(self: ModelDocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  if self.showCompletions and self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if MouseButton.Middle in buttons:
      self.selectedCompletion = item
      self.markDirty()
    return

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

  if self.showCompletions:
    result.add self.completionEventHandler

method createWithDocument*(_: ModelDocumentEditor, document: Document): DocumentEditor =
  let self = ModelDocumentEditor(eventHandler: nil, document: ModelDocument(document))

  # Emit this to set the editor prototype to editor_model_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [self, " = createWithPrototype(editor_model_prototype, ", self, ");"].}
    # This " is here to fix syntax highlighting

  self.init()
  discard self.document.onModelChanged.subscribe proc(d: auto) = self.handleModelChanged(d)

  self.rebuildCells()
  self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0])
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

  self.completionEventHandler = eventHandler(ed.getEventHandlerConfig("editor.model.completion")):
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

proc getTargetCell*(cursor: CellCursor, resolveCollection: bool = true): Option[Cell] =
  let cell = cursor.cell
  assert cell.isNotNil

  # debugf"getTargetCell {cursor}"
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

      let text = c.currentText
      if text.len > 0:
        let alpha = (xPos - widget.lastBounds.x) / widget.lastBounds.w
        result.get.firstIndex = (alpha * text.len.float).round.int
        result.get.lastIndex = (alpha * text.len.float).round.int

      return

proc getCursorXPos*(self: ModelDocumentEditor, cursor: CellCursor): float =
  result = 0
  if getTargetCell(cursor).getSome(cell):
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id, nil)
    if widget.isNotNil:
      let text = cell.currentText
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
  if cell.editableLow > cell.editableHigh:
    return false

  if cell of CollectionCell and cell.CollectionCell.children.len == 0:
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
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.getLastLeaf()

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
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.getFirstLeaf()

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

proc getSelfOrPreviousLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Cell =
  result = cell
  if result of CollectionCell:
    result = result.getPreviousLeaf()
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

proc getSelfOrNextLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Cell =
  result = cell
  if result of CollectionCell:
    result = result.getNextLeaf()
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
    let index = result.cell.parent.CollectionCell.indexOf(result.cell)
    result.path.insert index, 0
    result.cell = result.cell.parent

proc toCursor*(cell: Cell, column: int): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.node = cell.node
  result.cell = rootCell
  result.path = path
  result.column = clamp(column, cell.editableLow, cell.editableHigh)

proc toCursor*(cell: Cell, start: bool): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.node = cell.node
  result.cell = rootCell
  result.path = path
  if start:
    result.column = cell.editableLow
  else:
    result.column = cell.editableHigh

proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): CellCursor =
  let nodeCell = self.nodeToCell.getOrDefault(node.id)
  if nodeCell.isNil:
    return

  let targetCell = nodeCell.getSelfOrNextLeafWhere (n) => isVisible(n) and not n.disableEditing
  echo targetCell.dump()
  return targetCell.toCursor(true)

proc getFirstPropertyCellOfNode*(self: ModelDocumentEditor, node: AstNode, role: Id): CellCursor =
  let nodeCell = self.nodeToCell.getOrDefault(node.id)
  if nodeCell.isNil:
    return

  let targetCell = nodeCell.getSelfOrNextLeafWhere (n) => isVisible(n) and not n.disableEditing and n of PropertyCell and n.PropertyCell.property == role
  echo targetCell.dump()
  return targetCell.toCursor(true)

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

method getCursorLeft*(cell: PlaceholderCell, cursor: CellCursor): CellCursor =
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
  if cursor.lastIndex < cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: NodeReferenceCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex < cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: AliasCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex < cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: PlaceholderCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex < cell.editableHigh:
    result = cursor
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    result = cell.getNextSelectableLeaf().toCursor(true)

method getCursorRight*(cell: PropertyCell, cursor: CellCursor): CellCursor =
  if cursor.lastIndex < cell.editableHigh:
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

method handleDeleteLeft*(cell: Cell, slice: Slice[int]): Option[CellCursor] {.base.} = discard
method handleDeleteRight*(cell: Cell, slice: Slice[int]): Option[CellCursor] {.base.} = discard

method handleDeleteLeft*(cell: PropertyCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return cell.toCursor(newIndex).some

method handleDeleteLeft*(cell: ConstantCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return cell.toCursor(newIndex).some

method handleDeleteLeft*(cell: PlaceholderCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return cell.toCursor(newIndex).some

method handleDeleteRight*(cell: PropertyCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, cell.currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return cell.toCursor(newIndex).some

method handleDeleteRight*(cell: ConstantCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, cell.currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return cell.toCursor(newIndex).some

method handleDeleteRight*(cell: PlaceholderCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, cell.currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return cell.toCursor(newIndex).some

proc mode*(self: ModelDocumentEditor): string {.expose("editor.model").} =
  return self.currentMode

proc getContextWithMode*(self: ModelDocumentEditor, context: string): string {.expose("editor.model").} =
  return context & "." & $self.currentMode

proc moveCursorLeft*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    let newCursor = cell.getCursorLeft(self.cursor)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorRight*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    let newCursor = cell.getCursorRight(self.cursor)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorLeftLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
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
  if getTargetCell(self.cursor).getSome(cell):
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
  if getTargetCell(self.cursor).getSome(cell):
    if cell.line >= 0 and cell.line <= self.logicalLines.high and self.logicalLines[cell.line].len > 0:
      let newCursor = self.logicalLines[cell.line][0].toCursor(true)
      self.cursor = selectCursor(self.cursor, newCursor, select)
  self.markDirty()

proc moveCursorLineEnd*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.line >= 0 and cell.line <= self.logicalLines.high and self.logicalLines[cell.line].len > 0:
      let newCursor = self.logicalLines[cell.line][self.logicalLines[cell.line].high].toCursor(false)
      self.cursor = selectCursor(self.cursor, newCursor, select)
  self.markDirty()

proc moveCursorLineStartInline*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
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
  if getTargetCell(self.cursor).getSome(cell):
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
  if getTargetCell(self.cursor).getSome(cell):
    if cell.line > 0 and cell.line <= self.logicalLines.high:
      if self.getCursorInLine(cell.line - 1, self.getCursorXPos(self.cursor)).getSome(newCursor):
        self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorDown*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.line < self.logicalLines.high:
      if self.getCursorInLine(cell.line + 1, self.getCursorXPos(self.cursor)).getSome(newCursor):
        self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorLeftCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    let newCursor = cell.getPreviousSelectableLeaf().toCursor(false)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorRightCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    let newCursor = cell.getNextSelectableLeaf().toCursor(true)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc selectNode*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.cursor.path.len == 0:
    if self.cursor.firstIndex == 0 and self.cursor.lastIndex == self.cursor.cell.high:
      if self.cursor.node.parent.isNotNil:
        self.cursor = CellCursor(node: self.cursor.node.parent, cell: self.nodeToCell.getOrDefault(self.cursor.node.id, nil), path: self.cursor.path, firstIndex: 0, lastIndex: self.cursor.cell.editableHigh)
    else:
      self.cursor = CellCursor(node: self.cursor.node, cell: self.cursor.cell, path: self.cursor.path, firstIndex: 0, lastIndex: self.cursor.cell.editableHigh)
  else:
    self.cursor = CellCursor(node: self.cursor.node, cell: self.cursor.cell, path: @[], firstIndex: 0, lastIndex: self.cursor.cell.editableHigh)

  self.markDirty()

proc shouldEdit*(cell: Cell): bool =
  if (cell of PlaceholderCell):
    return true
  let class = cell.node.nodeClass
  if class.isNotNil and (class.isAbstract or class.isInterface):
    return true
  return false

proc selectPrevPlaceholder*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  var candidate = self.cursor.targetCell.getPreviousLeafWhere proc(c: Cell): bool = isVisible(c) and shouldEdit(c)
  if not shouldEdit(candidate):
    return

  self.cursor = candidate.toCursor(true)
  self.markDirty()

proc selectNextPlaceholder*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  var candidate = self.cursor.targetCell.getNextLeafWhere proc(c: Cell): bool = isVisible(c) and shouldEdit(c)
  if not shouldEdit(candidate):
    return

  self.cursor = candidate.toCursor(true)
  self.markDirty()

proc deleteLeft*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  let cell = self.cursor.targetCell
  if cell of CollectionCell:
    let parent = cell.node.parent
    cell.node.removeFromParent()
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(parent)
  else:
    if self.cursor.firstIndex == self.cursor.lastIndex and self.cursor.lastIndex <= cell.editableLow:
      let prev = cell.getPreviousVisibleLeaf()
      if prev != cell:
        if prev.handleDeleteLeft(prev.high..prev.high).getSome(newCursor):
          self.cursor = newCursor
    elif self.cursor.firstIndex == self.cursor.lastIndex and cell.disableEditing:
      self.cursor = self.cursor.selectEntireNode()
    else:
      if cell.handleDeleteLeft(self.cursor.orderedRange).getSome(newCursor):
        self.cursor = newCursor

  self.markDirty()

proc deleteRight*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  let cell = self.cursor.targetCell
  if cell of CollectionCell:
    let parent = cell.node.parent
    cell.node.removeFromParent()
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(parent)
  else:
    if self.cursor.firstIndex == self.cursor.lastIndex and self.cursor.lastIndex >= cell.editableHigh:
      let prev = cell.getNextVisibleLeaf()
      if prev != cell:
        if prev.handleDeleteRight(0..0).getSome(newCursor):
          self.cursor = newCursor
    elif self.cursor.firstIndex == self.cursor.lastIndex and cell.disableEditing:
      self.cursor = self.cursor.selectEntireNode()
    else:
      if cell.handleDeleteRight(self.cursor.orderedRange).getSome(newCursor):
        self.cursor = newCursor

  self.markDirty()

proc isAtBeginningOfFirstCellOfNode*(cursor: CellCursor): bool =
  result = cursor.lastIndex == 0
  if result:
    for i in cursor.path:
      if i != 0:
        return false

proc isAtEndOfLastCellOfNode*(cursor: CellCursor): bool =
  var cell = cursor.cell
  for i in cursor.path:
    if i != cell.high:
      return false
    cell = cell.CollectionCell.children[i]
  if cell of CollectionCell:
    return cursor.lastIndex == cell.high
  else:
    return cursor.lastIndex == cell.high + 1

proc insertIntoNode*(self: ModelDocumentEditor, parent: AstNode, role: Id, index: int): Option[AstNode] =
  let parentCell = self.nodeToCell.getOrDefault(parent.id)
  debugf"insertIntoNode {index} {parent}, {parentCell.nodeFactory.isNotNil}"

  if parentCell.nodeFactory.isNotNil:
    let newNode = parentCell.nodeFactory()
    parent.insert(role, index, newNode)
    return newNode.some
  else:
    return parent.insertDefaultNode(role, index)

proc insertBeforeNode*(self: ModelDocumentEditor, node: AstNode): Option[AstNode] =
  let parentCell = self.nodeToCell.getOrDefault(node.parent.id)
  debugf"01 insert before {node.index} {node.parent}, {parentCell.nodeFactory.isNotNil}"

  return self.insertIntoNode(node.parent, node.role, node.index)

proc insertAfterNode*(self: ModelDocumentEditor, node: AstNode): Option[AstNode] =
  let parentCell = self.nodeToCell.getOrDefault(node.parent.id)
  debugf"01 insert before {node.index} {node.parent}, {parentCell.nodeFactory.isNotNil}"

  return self.insertIntoNode(node.parent, node.role, node.index + 1)

proc createNewNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  if self.cursor.firstIndex != self.cursor.lastIndex:
    return

  echo "createNewNode"

  let isAtBeginningOfFirstCellOfNode = block:
    var result = self.cursor.lastIndex == 0
    if result:
      for i in self.cursor.path:
        if i != 0:
          result = false
          break
    result

  let isAtEndOfLastCellOfNode = block:
    var result = self.cursor.lastIndex == self.cursor.cell.high
    if result:
      for i in self.cursor.path:
        if i != 0:
          result = false
          break
    result

  let canHaveSiblings = self.cursor.node.canHaveSiblings()

  let newNode = if canHaveSiblings and self.cursor.isAtEndOfLastCellOfNode():
    self.insertAfterNode(self.cursor.node)

  elif canHaveSiblings and self.cursor.isAtBeginningOfFirstCellOfNode():
    self.insertBeforeNode(self.cursor.node)

  else:
    let cell = self.cursor.targetCell
    var i = 0
    let originalNode = cell.node

    var ok = false
    var addBefore = true
    var candidate = cell.getSelfOrNextLeafWhere proc(c: Cell): bool =
      if c.node.selfDescription().getSome(desc):
        debugf"{desc.role}, {desc.count}, {c.node.index}, {c.dump}, {c.node}"

      if c.node != originalNode and not c.node.isDescendant(originalNode):
        return true
      if c.node == originalNode:
        return false

      inc i

      if c.node.canHaveSiblings():
        ok = true
        return true

      return false

    if not ok and not originalNode.canHaveSiblings():
      echo "search outside"
      candidate = cell.getSelfOrNextLeafWhere proc(c: Cell): bool =
        # inc i
        if c.node.selfDescription().getSome(desc):
          debugf"{desc.role}, {desc.count}, {c.node.index}, {c.dump}, {c.node}"
        # return isVisible(c)
        # return i > 10

        if c.node.canHaveSiblings():
          addBefore = false
          ok = true
          return true

        return false

    debugf"ok: {ok}, addBefore: {addBefore}"
    if ok:
      if addBefore:
        self.insertBeforeNode(candidate.node)
      else:
        self.insertAfterNode(candidate.node)
    elif originalNode.canHaveSiblings():
      if addBefore:
        self.insertBeforeNode(originalNode)
      else:
        self.insertAfterNode(originalNode)
    else:
      AstNode.none

  # echo cell.dump()
  # echo candidate.dump()

  if newNode.getSome(node):
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(node)
    echo self.cursor

  self.markDirty()

proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  if getTargetCell(self.cursor).getSome(cell):
    if cell.disableEditing:
      return false

    let newColumn = cell.replaceText(self.cursor.orderedRange, input)
    if newColumn != self.cursor.lastIndex:
      self.mCursor.column = newColumn

      if self.unfilteredCompletions.len == 0:
        self.updateCompletions()
      else:
        self.refilterCompletions()

      if not self.showCompletions and self.completionsLen == 1 and self.getCompletion(0).name == cell.currentText:
        self.applySelectedCompletion()

      self.markDirty()
      return true
  return false

proc getCursorForOp(self: ModelDocumentEditor, op: ModelOperation): CellCursor =
  result = self.cursor
  case op.kind
  of Delete:
    return self.getFirstEditableCellOfNode(op.node)
  of Insert:
    return self.getFirstEditableCellOfNode(op.parent)
  of PropertyChange:
    result = self.getFirstPropertyCellOfNode(op.node, op.role)
    result.firstIndex = op.slice.a
    result.lastIndex = op.slice.b
  of ReferenceChange:
    return self.getFirstEditableCellOfNode(op.node)
  of Replace:
    discard

proc undo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.undo().getSome(op):
    self.rebuildCells()
    self.cursor = self.getCursorForOp(op)
    self.markDirty()

proc redo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.redo().getSome(op):
    self.rebuildCells()
    self.cursor = self.getCursorForOp(op)
    self.markDirty()

proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.useDefaultCellBuilder = not self.useDefaultCellBuilder
  self.rebuildCells()
  self.markDirty()

proc showCompletions*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.showCompletions:
    self.mCursor.column = 0
  self.updateCompletions()
  self.showCompletions = true
  self.markDirty()

proc hideCompletions*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.unfilteredCompletions.setLen 0
  self.showCompletions = false
  self.markDirty()

proc selectPrevCompletion*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.completionsLen > 0:
    if self.selectedCompletion == 0:
      self.selectedCompletion = self.completionsLen
    else:
      self.selectedCompletion = (self.selectedCompletion - 1).clamp(0, self.completionsLen - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc selectNextCompletion*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.completionsLen > 0:
    if self.selectedCompletion == self.completionsLen - 1:
      self.selectedCompletion = 0
    else:
      self.selectedCompletion = (self.selectedCompletion + 1).clamp(0, self.completionsLen - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc applySelectedCompletion*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  if self.selectedCompletion < self.completionsLen:
    let completion = self.getCompletion(self.selectedCompletion)
    let parent = completion.parent
    let role = completion.role
    let index = completion.index

    case completion.kind:
    of ModelCompletionKind.SubstituteClass:
      parent.remove(role, index)

      let newNode = newAstNode(completion.class)
      parent.insert(role, index, newNode)
      self.rebuildCells()
      self.cursor = self.getFirstEditableCellOfNode(newNode)

    of ModelCompletionKind.SubstituteReference:
      parent.remove(role, index)

      let newNode = newAstNode(completion.class)
      newNode.setReference(completion.referenceRole, completion.referenceTarget.id)
      parent.insert(role, index, newNode)
      self.rebuildCells()
      self.cursor = self.getFirstEditableCellOfNode(newNode)

    self.showCompletions = false

  self.markDirty()

genDispatcher("editor.model")

proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse =
  # logger.log lvlInfo, fmt"[modeleditor]: Handle action {action}, '{arg}'"
  defer:
    logger.log lvlDebug, &"line: {self.cursor.targetCell.line}, cursor: {self.cursor},\ncell: {self.cursor.cell.dump()}\ntargetCell: {self.cursor.targetCell.dump()}"

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