import std/[strformat, strutils, sugar, tables, options, json, streams, algorithm]
import fusion/matching, bumpy, rect_utils, vmath
import util, document, document_editor, text/text_document, events, id, ast_ids, scripting/expose, event, input, custom_async, myjsonutils, custom_unicode, delayed_task
from scripting_api as api import nil
import custom_logger, timer, array_buffer, config_provider, app_interface
import platform/[filesystem, platform]
import workspaces/[workspace]
import ast/[model, base_language, cells]
import ui/node

import ast/[base_language_wasm, model_state]

var project = newProject()

logCategory "model"
createJavascriptPrototype("editor.model")

type
  CellCursor* = object
    map: NodeCellMap
    index*: int
    path*: seq[int]
    node*: AstNode

  CellSelection* = tuple[first: CellCursor, last: CellCursor]

  CellCursorState = object
    index*: int
    path*: seq[int]
    node*: NodeId

type Direction* = enum
  Left, Right

func `-`*(d: Direction): Direction =
  case d
  of Left: return Right
  of Right: return Left

proc toSelection*(cursor: CellCursor): CellSelection = (cursor, cursor)

proc isEmpty*(selection: CellSelection): bool = selection.first == selection.last

proc `$`*(cursor: CellCursor): string = fmt"CellCursor({cursor.index}, {cursor.path}, {cursor.node})"

proc `$`*(selection: CellSelection): string = fmt"({selection.first}, {selection.last})"

proc orderedRange*(selection: CellSelection): Slice[int] =
  return min(selection.first.index, selection.last.index)..max(selection.first.index, selection.last.index)

proc baseCell*(cursor: CellCursor): Cell =
  return cursor.map.cell(cursor.node)

proc targetCell*(cursor: CellCursor): Cell =
  # echo fmt"targetCell {cursor}"
  result = cursor.baseCell
  cursor.map.fill(result)
  for i in cursor.path:
    if result of CollectionCell:
      result = result.CollectionCell.children[i]

proc rootPath*(cell: Cell): tuple[root: Cell, path: seq[int]] =
  var cell = cell
  var path: seq[int] = @[]
  while cell.parent.isNotNil:
    if cell.parent of CollectionCell:
      path.add cell.parent.CollectionCell.children.find(cell)

    cell = cell.parent

  path.reverse()

  return (cell, path)

proc rootPath*(cursor: CellCursor): tuple[root: Cell, path: seq[int]] =
  result = cursor.targetCell.rootPath
  result.path.add cursor.index

proc `<`*(a, b: CellCursor): bool =
  let pathA = a.rootPath
  let pathB = b.rootPath
  for i in 0..min(pathA.path.high, pathB.path.high):
    if pathA.path[i] < pathB.path[i]:
      return true
    if pathA.path[i] > pathB.path[i]:
      return false
  return pathA.path.len < pathB.path.len

proc normalized*(selection: CellSelection): CellSelection =
  return if selection.first < selection.last: selection else: (selection.last, selection.first)

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
    id: Id
    operations*: seq[ModelOperation]

  ModelDocument* = ref object of Document
    model*: Model
    project*: Project
    ctx*: ModelComputationContext

    currentTransaction: ModelTransaction
    undoList: seq[ModelTransaction]
    redoList: seq[ModelTransaction]

    onModelChanged*: Event[ModelDocument]
    onFinishedUndoTransaction*: Event[(ModelDocument, ModelTransaction)]
    onFinishedRedoTransaction*: Event[(ModelDocument, ModelTransaction)]

    builder*: CellBuilder

  ModelCompletionKind* {.pure.} = enum
    SubstituteClass
    SubstituteReference
    ChangeReference

  ModelCompletion* = object
    parent*: AstNode
    role*: Id
    index*: int
    class*: NodeClass
    name*: string
    alwaysApply*: bool # If true then this completion will always be applied when it's the only one, even if the current completion text doesn't match exactly

    case kind*: ModelCompletionKind
    of SubstituteClass:
      property: Option[RoleId] # Property to set on new node from completion text
    of SubstituteReference:
      referenceRole*: Id
      referenceTarget*: AstNode
    of ChangeReference:
      changeReferenceTarget*: AstNode

  ModelDocumentEditor* = ref object of DocumentEditor
    app*: AppInterface
    configProvider*: ConfigProvider
    document*: ModelDocument

    cursorsId*: Id
    completionsId*: Id
    lastCursorLocationBounds*: Option[Rect]
    scrolledNode*: UINode
    targetCellPath* = @[0, 0]

    transactionCursors: Table[Id, CellSelection]

    modeEventHandler: EventHandler
    completionEventHandler: EventHandler
    currentMode*: string

    nodeCellMap*: NodeCellMap
    logicalLines*: seq[seq[Cell]]
    cellWidgetContext*: UpdateContext
    mCursorBeforeTransaction: CellSelection
    mSelection: CellSelection
    lastTargetCell: Cell
    mTargetCursor: Option[CellCursorState]

    cursorVisible*: bool = true
    blinkCursor: bool = false
    blinkCursorTask: DelayedTask

    scrollOffset*: float
    previousBaseIndex*: seq[int]

    lastBounds*: Rect

    showCompletions*: bool
    completionText: string
    hasCompletions*: bool
    filteredCompletions*: seq[ModelCompletion]
    unfilteredCompletions*: seq[ModelCompletion]
    selectedCompletion*: int
    completionsBaseIndex*: int
    completionsScrollOffset*: float
    scrollToCompletion*: Option[int]

  UpdateContext* = ref object
    nodeCellMap*: NodeCellMap
    cellToWidget*: Table[Id, UINode]
    targetNodeOld*: UINode
    targetNode*: UINode
    targetCell*: Cell
    scrolledNode*: UINode
    targetCellPosition*: Vec2
    selection*: CellSelection
    handleClick*: proc(node: UINode, cell: Cell, path: seq[int], cursor: CellCursor, drag: bool)
    setCursor*: proc(cell: Cell, offset: int, drag: bool)
    selectionColor*: Color
    isThickCursor*: bool

proc `$`(op: ModelOperation): string =
  result = fmt"{op.kind}, '{op.value}'"
  if op.id != null: result.add fmt", id = {op.id}"
  if op.node != nil: result.add fmt", node = {op.node}"
  if op.parent != nil: result.add fmt", parent = {op.parent}, index = {op.idx}"

proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse
proc rebuildCells*(self: ModelDocumentEditor)
proc getTargetCell*(cursor: CellCursor, resolveCollection: bool = true): Option[Cell]
proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool
proc applySelectedCompletion*(self: ModelDocumentEditor)
proc updateCompletions(self: ModelDocumentEditor)
proc invalidateCompletions(self: ModelDocumentEditor)
proc refilterCompletions(self: ModelDocumentEditor)
proc updateCursor*(self: ModelDocumentEditor, cursor: CellCursor): Option[CellCursor]
proc isThickCursor*(self: ModelDocumentEditor): bool
proc getContextWithMode*(self: ModelDocumentEditor, context: string): string

proc toCursor*(map: NodeCellMap, cell: Cell, column: int): CellCursor
proc toCursor*(map: NodeCellMap, cell: Cell, start: bool): CellCursor
proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): Option[CellCursor]
proc getPreviousLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool): Option[Cell]
proc canSelect*(cell: Cell): bool
proc isVisible*(cell: Cell): bool
proc getParentInfo*(selection: CellSelection): tuple[cell: Cell, left: seq[int], right: seq[int]]

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
  result.ctx = newModelComputationContext()

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

  log lvlInfo, fmt"Saving model source file '{self.filename}'"
  let serialized = self.model.toJson.pretty

  if self.workspace.getSome(ws):
    asyncCheck ws.saveFile(self.filename, serialized)
  elif self.appFile:
    fs.saveApplicationFile(self.filename, serialized)
  else:
    fs.saveFile(self.filename, serialized)

template cursor*(self: ModelDocumentEditor): CellCursor = self.mSelection.last
template selection*(self: ModelDocumentEditor): CellSelection = self.mSelection

proc startBlinkCursorTask(self: ModelDocumentEditor) =
  if not self.blinkCursor:
    return

  if self.blinkCursorTask.isNil:
    self.blinkCursorTask = startDelayed(500, repeat=true):
      if not self.active:
        self.cursorVisible = true
        self.markDirty()
        self.blinkCursorTask.pause()
        return
      self.cursorVisible = not self.cursorVisible
      self.markDirty()
  else:
    self.blinkCursorTask.reschedule()

proc updateScrollOffset*(self: ModelDocumentEditor, scrollToCursor: bool = true) =
  if self.cellWidgetContext.isNil:
    return

  let newCell = self.selection.last.targetCell
  if self.scrolledNode.isNil:
    return

  if newCell.isNotNil and self.cellWidgetContext.cellToWidget.contains(newCell.id):
    let newUINode = self.cellWidgetContext.cellToWidget[newCell.id]
    let newY = newUINode.transformBounds(self.scrolledNode.parent).y

    let buffer = 5.0
    if newY < buffer * self.app.platform.builder.textHeight:
      self.targetCellPath = newCell.rootPath.path
      self.scrollOffset = buffer * self.app.platform.builder.textHeight
    elif newY > self.scrolledNode.parent.h - buffer * self.app.platform.builder.textHeight:
      self.targetCellPath = newCell.rootPath.path
      self.scrollOffset = self.scrolledNode.parent.h - buffer * self.app.platform.builder.textHeight

  elif scrollToCursor:
    # discard
    # todo
    # echo fmt"new cell doesn't exist, scroll offset {self.scrollOffset}, {self.targetCellPath}"
    self.targetCellPath = self.selection.last.targetCell.rootPath.path
    self.scrollOffset = self.scrolledNode.parent.h / 2

  elif self.lastTargetCell.isNotNil and self.lastTargetCell.node.model.isNotNil:
    self.targetCellPath = self.nodeCellMap.cell(self.lastTargetCell.node).rootPath.path

  else:
    self.targetCellPath = newCell.rootPath.path

  # debugf"updateScrollOffset {self.targetCellPath}:{self.scrollOffset}"

  self.markDirty()

proc updateScrollOffsetToPrevCell(self: ModelDocumentEditor): bool =
  if self.cellWidgetContext.isNil:
    return false
  if self.scrolledNode.isNil:
    return false

  let cursor = self.selection.normalized.first
  let sourceCell = cursor.targetCell
  # echo fmt"source {sourceCell}"

  var lastLeafOnScreen = Cell.none
  discard sourceCell.getPreviousLeafWhere(self.nodeCellMap, proc(cell: Cell): bool =
    if self.cellWidgetContext.cellToWidget.contains(cell.id):
      lastLeafOnScreen = cell.some
      return false
    return true
  )

  let prevLeaf = lastLeafOnScreen

  if prevLeaf.isNone:
    return false

  let newCell = prevLeaf.get
  if not self.cellWidgetContext.cellToWidget.contains(newCell.id):
    return false

  let oldY = self.cellWidgetContext.targetNode.transformBounds(self.scrolledNode.parent).y

  let newUINode = self.cellWidgetContext.cellToWidget[newCell.id]
  let newY = newUINode.transformBounds(self.scrolledNode.parent).y

  # debugf"updateScrollOffsetToPrevCell {self.targetCellPath}:{self.scrollOffset} -> {newCell.rootPath.path}:{newY}, {newCell}, {newCell.parent}, {oldY}"
  self.targetCellPath = newCell.rootPath.path
  self.scrollOffset = newY
  return true

proc `selection=`*(self: ModelDocumentEditor, selection: CellSelection) =
  assert self.mSelection.first.map.isNotNil
  assert self.mSelection.last.map.isNotNil

  # debugf"selection = {selection.last}"

  if self.lastTargetCell != selection.last.targetCell:
    self.mSelection = selection
    self.invalidateCompletions()
  else:
    self.mSelection = selection
    self.refilterCompletions()
  # debugf"selection = {selection}"
  self.lastTargetCell = selection.last.targetCell

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

proc updateSelection*(self: ModelDocumentEditor, cursor: CellCursor, extend: bool) =
  if extend:
    self.selection = (self.selection.first, cursor)
  else:
    self.selection = (cursor, cursor)

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursor) =
  self.selection = (cursor, cursor)

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursorState) =
  if self.document.model.resolveReference(cursor.node).getSome(node):
    self.cursor = CellCursor(map: self.nodeCellMap, index: cursor.index, path: cursor.path, node: node)
  else:
    self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get

proc `targetCursor=`*(self: ModelDocumentEditor, cursor: CellCursorState) =
  self.mTargetCursor = cursor.some
  self.cursor = cursor

proc handleNodeDeleted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  # debugf "handleNodeDeleted {parent}, {child}, {role}, {index}"
  self.currentTransaction.operations.add ModelOperation(kind: Delete, parent: parent, node: child, idx: index, role: role)
  self.ctx.state.deleteNode(child, recurse=true)

proc handleNodeInserted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: Id, index: int) =
  # debugf "handleNodeInserted {parent}, {child}, {role}, {index}"
  self.currentTransaction.operations.add ModelOperation(kind: Insert, parent: parent, node: child, idx: index, role: role)
  self.ctx.state.insertNode(child)

proc handleNodePropertyChanged(self: ModelDocument, model: Model, node: AstNode, role: Id, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  # debugf "handleNodePropertyChanged {node}, {role}, {oldValue}, {newValue}"
  self.currentTransaction.operations.add ModelOperation(kind: PropertyChange, node: node, role: role, value: oldValue, slice: slice)
  self.ctx.state.updateNode(node)

proc handleNodeReferenceChanged(self: ModelDocument, model: Model, node: AstNode, role: Id, oldRef: Id, newRef: Id) =
  # debugf "handleNodeReferenceChanged {node}, {role}, {oldRef}, {newRef}"
  self.currentTransaction.operations.add ModelOperation(kind: ReferenceChange, node: node, role: role, id: oldRef)
  self.ctx.state.updateNode(node)

proc loadAsync*(self: ModelDocument): Future[void] {.async.} =
  log lvlInfo, fmt"Loading model source file '{self.filename}'"
  try:
    var jsonText = ""
    if self.workspace.getSome(ws):
      jsonText = await ws.loadFile(self.filename)
    elif self.appFile:
      jsonText = fs.loadApplicationFile(self.filename)
    else:
      jsonText = fs.loadFile(self.filename)

    let json = jsonText.parseJson

    var model = newModel(newId())
    model.addLanguage(base_language.baseLanguage)
    model.loadFromJson(json)
    self.model = model

    discard self.model.onNodeDeleted.subscribe proc(d: auto) = self.handleNodeDeleted(d[0], d[1], d[2], d[3], d[4])
    discard self.model.onNodeInserted.subscribe proc(d: auto) = self.handleNodeInserted(d[0], d[1], d[2], d[3], d[4])
    discard self.model.onNodePropertyChanged.subscribe proc(d: auto) = self.handleNodePropertyChanged(d[0], d[1], d[2], d[3], d[4], d[5])
    discard self.model.onNodeReferenceChanged.subscribe proc(d: auto) = self.handleNodeReferenceChanged(d[0], d[1], d[2], d[3], d[4])

    self.builder = newCellBuilder()
    for language in self.model.languages:
      self.builder.addBuilder(language.builder)

    project.addModel(self.model)
    project.builder = self.builder

    self.undoList.setLen 0
    self.redoList.setLen 0

    for rootNode in self.model.rootNodes:
      self.ctx.state.insertNode(rootNode)

  except CatchableError:
    log lvlError, fmt"Failed to load model source file '{self.filename}': {getCurrentExceptionMsg()}"

  self.onModelChanged.invoke (self)

method load*(self: ModelDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename
  asyncCheck self.loadAsync()

proc getSubstitutionTarget(cell: Cell): (AstNode, Id, int) =
  ## Returns the parent cell, role, and index where to insert/replace a substitution
  if cell of PlaceholderCell:
    return (cell.node, cell.PlaceholderCell.role, 0)
  return (cell.node.parent, cell.node.role, cell.node.index)

proc getSubstitutionsForClass(self: ModelDocumentEditor, targetCell: Cell, class: NodeClass, addCompletion: proc(c: ModelCompletion): void): bool =
  if class.references.len == 1 and class.children.len == 0 and class.properties.len == 0:
    let desc = class.references[0]
    let language = self.document.model.getLanguageForClass(desc.class)
    let refClass = language.resolveClass(desc.class)

    let (parent, role, index) = targetCell.getSubstitutionTarget()

    for node in self.document.model.rootNodes:
      var res = false
      node.forEach2 n:
        let nClass = language.resolveClass(n.class)
        if nClass.isSubclassOf(refClass.id):
          let name = if n.property(IdINamedName).getSome(name): name.stringValue else: $n.id
          addCompletion ModelCompletion(kind: ModelCompletionKind.SubstituteReference, name: name, class: class, parent: parent, role: role, index: index, referenceRole: desc.id, referenceTarget: n)
          res = true
      if res:
        result = true

  if class.substitutionProperty.getSome(propertyRole):
    let (parent, role, index) = targetCell.getSubstitutionTarget()
    addCompletion ModelCompletion(kind: ModelCompletionKind.SubstituteClass, name: class.alias, class: class, parent: parent, role: role, index: index, alwaysApply: true, property: propertyRole.some)
    result = true

proc refilterCompletions(self: ModelDocumentEditor) =
  self.filteredCompletions.setLen 0

  let targetCell = self.cursor.targetCell
  if targetCell of CollectionCell:
    return

  let text = targetCell.currentText
  let index = self.cursor.index
  let prefix = text[0..<index]

  # debugf "refilter '{text}' {index} -> '{prefix}'"

  for completion in self.unfilteredCompletions:
    if completion.kind == ModelCompletionKind.SubstituteClass and completion.property.getSome(role):
      let language = self.document.model.getLanguageForClass(completion.class.id)
      if language.isValidPropertyValue(completion.class, role, prefix):
        self.filteredCompletions.add completion
        continue

    if completion.name.startsWith(prefix):
      self.filteredCompletions.add completion
      continue

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

  let model = node.model
  let parentClass = parent.nodeClass
  if parentClass.nodeChildDescription(role).getSome(childDesc):
    let slotClass = model.resolveClass(childDesc.class)
    debugf"updateCompletions {node}, {node.model.isNotNil}, {slotClass.name}"

    model.forEachChildClass slotClass, proc(childClass: NodeClass) =
      if self.getSubstitutionsForClass(targetCell, childClass, (c) -> void => self.unfilteredCompletions.add(c)):
        return

      if childClass.isAbstract or childClass.isInterface:
        return

      let name = if childClass.alias.len > 0: childClass.alias else: childClass.name
      self.unfilteredCompletions.add ModelCompletion(kind: ModelCompletionKind.SubstituteClass, name: name, class: childClass, parent: parent, role: role, index: index)
  elif parentClass.nodeReferenceDescription(role).getSome(desc):
    let slotClass = model.resolveClass(desc.class)
    debugf"updateCompletions {node}, {node.model.isNotNil}, {slotClass.name}"
    let scope = self.document.ctx.getScope(node)
    for decl in scope:
      if decl.nodeClass.isSubclassOf(slotClass.id):
        let name = if decl.property(IdINamedName).getSome(name): name.stringValue else: $decl.id
        self.unfilteredCompletions.add ModelCompletion(kind: ModelCompletionKind.ChangeReference, name: name, class: slotClass, parent: node, role: role, index: index, changeReferenceTarget: decl)

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
  if self.currentTransaction.id == idNone():
    self.currentTransaction.id = newId()

  if self.currentTransaction.operations.len > 0:
    self.undoList.add self.currentTransaction
    if clearRedoList:
      self.redoList.setLen 0
    self.onFinishedUndoTransaction.invoke (self, self.undoList[self.undoList.high])
  self.currentTransaction = ModelTransaction(id: newId())

proc finishRedoTransaction*(self: ModelDocument, clearUndoList: bool = false) =
  if self.currentTransaction.id == idNone():
    self.currentTransaction.id = newId()

  if self.currentTransaction.operations.len > 0:
    self.redoList.add self.currentTransaction
    if clearUndoList:
      self.undoList.setLen 0
    self.onFinishedRedoTransaction.invoke (self, self.redoList[self.redoList.high])
  self.currentTransaction = ModelTransaction(id: newId())

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

proc undo*(self: ModelDocument): Option[(Id, ModelOperation)] =
  self.finishTransaction()

  if self.undoList.len == 0:
    return

  let t = self.undoList.pop
  log(lvlInfo, fmt"Undoing {t}")

  for i in countdown(t.operations.high, 0):
    let op = t.operations[i]
    result = (t.id, op).some
    self.reverseModelOperation(op)

  self.finishRedoTransaction()

proc redo*(self: ModelDocument): Option[(Id, ModelOperation)] =
  self.finishTransaction()

  if self.redoList.len == 0:
    return

  let t = self.redoList.pop
  log(lvlInfo, fmt"Redoing {t}")

  for i in countdown(t.operations.high, 0):
    let op = t.operations[i]
    result = (t.id, op).some
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

  self.mSelection.first.node = self.document.model.rootNodes[0]
  self.mSelection.last.node = self.document.model.rootNodes[0]

  if self.mTargetCursor.getSome(c):
    self.cursor = c
    assert self.cursor.map == self.nodeCellMap
  else:
    self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get

  self.updateScrollOffset()

  self.mCursorBeforeTransaction = self.selection

  self.markDirty()

proc handleFinishedUndoTransaction*(self: ModelDocumentEditor, document: ModelDocument, transaction: ModelTransaction) =
  self.transactionCursors[transaction.id] = self.mCursorBeforeTransaction
  self.mCursorBeforeTransaction = self.selection

proc handleFinishedRedoTransaction*(self: ModelDocumentEditor, document: ModelDocument, transaction: ModelTransaction) =
  self.transactionCursors[transaction.id] = self.mCursorBeforeTransaction
  self.mCursorBeforeTransaction = self.selection

method handleDocumentChanged*(self: ModelDocumentEditor) =
  log lvlInfo, fmt"Document changed"
  # self.selectionHistory.clear
  # self.selectionFuture.clear
  # self.finishEdit false
  # for symbol in ctx.globalScope.values:
  #   discard ctx.newSymbol(symbol)
  # self.node = self.document.rootNode[0]
  self.nodeCellMap.builder = self.document.builder
  self.rebuildCells()
  self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get
  self.updateScrollOffset()

  self.markDirty()

method handleActivate*(self: ModelDocumentEditor) =
  self.startBlinkCursorTask()

method handleDeactivate*(self: ModelDocumentEditor) =
  if self.blinkCursorTask.isNotNil:
    self.blinkCursorTask.pause()
    self.cursorVisible = true
    self.markDirty()

proc buildNodeCellMap(self: Cell, map: var Table[Id, Cell]) =
  if self.node.isNotNil and not map.contains(self.node.id):
    map[self.node.id] = self
  if self of CollectionCell:
    for c in self.CollectionCell.children:
      c.buildNodeCellMap(map)

proc rebuildCells(self: ModelDocumentEditor) =
  # debugf"rebuildCells"
  self.nodeCellMap.invalidate()
  self.logicalLines.setLen 0
  self.markDirty()

proc toJson*(self: api.ModelDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.model")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.ModelDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc handleInput(self: ModelDocumentEditor, input: string): EventResponse =
  # log lvlInfo, fmt"[modeleditor]: Handle input '{input}'"

  self.mCursorBeforeTransaction = self.selection

  if self.app.invokeCallback(self.getContextWithMode("editor.model.input-handler"), input.newJString):
    self.document.finishTransaction()
    return Handled

  if self.insertTextAtCursor(input):
    self.document.finishTransaction()
    return Handled

  return Ignored

proc getItemAtPixelPosition(self: ModelDocumentEditor, posWindow: Vec2): Option[int] =
  result = int.none
  # todo
  # for (index, widget) in self.lastItems:
  #   if widget.lastBounds.contains(posWindow) and index >= 0 and index < self.completionsLen:
  #     return index.some

method handleScroll*(self: ModelDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  let scrollAmount = scroll.y * self.configProvider.getValue("model.scroll-speed", 20.0)

  # todo
  # if self.showCompletions and not self.lastCompletionsWidget.isNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
  #   self.completionsScrollOffset += scrollAmount
  #   self.markDirty()
  # else:
  self.scrollOffset += scrollAmount
  self.markDirty()

proc getLeafCellContainingPoint*(self: ModelDocumentEditor, cell: Cell, point: Vec2): Option[Cell] =
  discard
  # todo
  # let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id, nil)
  # if widget.isNil:
  #   return Cell.none

  # # debugf"getLeafCellContainingPoint {cell.node}, {point}, {widget.lastBounds}"
  # if not widget.lastBounds.contains(point):
  #   return Cell.none

  # if cell of CollectionCell:
  #   for c in cell.CollectionCell.children:
  #     if self.getLeafCellContainingPoint(c, point).getSome(leaf):
  #       return leaf.some
  #   return Cell.none

  # # debugf"-> {cell.node}, {point}, {widget.lastBounds}"
  # return cell.some

method handleMousePress*(self: ModelDocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) =
  if self.showCompletions and self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if button == MouseButton.Left or button == MouseButton.Middle:
      self.selectedCompletion = item
      self.markDirty()
    return

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

method canEdit*(self: ModelDocumentEditor, document: Document): bool =
  if document of ModelDocument: return true
  else: return false

method getEventHandlers*(self: ModelDocumentEditor): seq[EventHandler] =
  result.add self.eventHandler

  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler

  if self.showCompletions:
    result.add self.completionEventHandler

method getDocument*(self: ModelDocumentEditor): Document = self.document

method createWithDocument*(_: ModelDocumentEditor, document: Document, configProvider: ConfigProvider): DocumentEditor =
  let self = ModelDocumentEditor(eventHandler: nil, document: ModelDocument(document))
  self.configProvider = configProvider

  # Emit this to set the editor prototype to editor_model_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [self, " = jsCreateWithPrototype(editor_model_prototype, ", self, ");"].}
    # This " is here to fix syntax highlighting

  self.cursorsId = newId()
  self.completionsId = newId()
  self.nodeCellMap.new
  self.nodeCellMap.builder = self.document.builder
  self.mSelection.first.map = self.nodeCellMap
  self.mSelection.last.map = self.nodeCellMap

  self.init()
  discard self.document.onModelChanged.subscribe proc(d: auto) = self.handleModelChanged(d)
  discard self.document.onFinishedUndoTransaction.subscribe proc(d: auto) = self.handleFinishedUndoTransaction(d[0], d[1])
  discard self.document.onFinishedRedoTransaction.subscribe proc(d: auto) = self.handleFinishedRedoTransaction(d[0], d[1])

  self.rebuildCells()
  self.mSelection.first.node = self.document.model.rootNodes[0]
  self.mSelection.last.node = self.document.model.rootNodes[0]
  self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get
  self.updateScrollOffset()

  self.startBlinkCursorTask()

  return self

method injectDependencies*(self: ModelDocumentEditor, app: AppInterface) =
  self.app = app
  self.app.registerEditor(self)

  self.eventHandler = eventHandler(app.getEventHandlerConfig("editor.model")):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

  self.completionEventHandler = eventHandler(app.getEventHandlerConfig("editor.model.completion")):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

method unregister*(self: ModelDocumentEditor) =
  self.app.unregisterEditor(self)

proc getModelDocumentEditor(wrapper: api.ModelDocumentEditor): Option[ModelDocumentEditor] =
  if gAppInterface.isNil: return ModelDocumentEditor.none
  if gAppInterface.getEditorForId(wrapper.id).getSome(editor):
    if editor of ModelDocumentEditor:
      return editor.ModelDocumentEditor.some
  return ModelDocumentEditor.none

proc getTargetCell*(cursor: CellCursor, resolveCollection: bool = true): Option[Cell] =
  let cell = cursor.baseCell
  assert cell.isNotNil

  # debugf"getTargetCell {cursor}"
  # defer:
  #   if result.isSome:
  #     debugf"{result.get.dump}"

  var subCell = cell
  for i in cursor.path:
    if subCell of CollectionCell and subCell.CollectionCell.children.len > 0:
      var collectionCell = subCell.CollectionCell
      subCell = collectionCell.children[i.clamp(0, collectionCell.children.high)]
    else:
      break

  if resolveCollection and subCell of CollectionCell and cursor.index >= 0 and cursor.index < subCell.CollectionCell.children.len:
    return subCell.CollectionCell.children[cursor.index].some

  return subCell.some

static:
  addTypeMap(ModelDocumentEditor, api.ModelDocumentEditor, getModelDocumentEditor)

proc scrollPixels*(self: ModelDocumentEditor, amount: float32) {.expose("editor.model").} =
  self.scrollOffset += amount
  self.markDirty()

proc scrollLines*(self: ModelDocumentEditor, lines: float32) {.expose("editor.model").} =
  self.scrollOffset += self.app.platform.builder.textHeight * lines.float
  self.markDirty()

proc getModeConfig(self: ModelDocumentEditor, mode: string): EventHandlerConfig =
  return self.app.getEventHandlerConfig("editor.model." & mode)

proc setMode*(self: ModelDocumentEditor, mode: string) {.expose("editor.model").} =
  if mode.len == 0:
    self.modeEventHandler = nil
  else:
    let config = self.getModeConfig(mode)
    self.modeEventHandler = eventHandler(config):
      onAction:
        self.handleAction action, arg
      onInput:
        self.handleInput input

  self.cursorVisible = true
  if self.blinkCursorTask.isNotNil and self.active:
    self.blinkCursorTask.reschedule()

  self.currentMode = mode
  self.markDirty()

proc getCursorOffset(builder: UINodeBuilder, cell: Cell, posX: float, isThickCursor: bool): int =
  var offsetFromLeft = posX / builder.charWidth
  if isThickCursor:
    offsetFromLeft -= 0.0
  else:
    offsetFromLeft += 0.5

  let line = cell.getText
  let index = clamp(offsetFromLeft.int, 0, line.runeLen.int)
  let byteIndex = line.runeOffset(index.RuneIndex)
  return byteIndex

proc getCellInLine*(builder: UINodeBuilder, updateContext: UpdateContext, target: Vec2, direction: int, isThickCursor: bool): Option[tuple[cell: Cell, offset: int]] =
  ## Searches for the next cell in a line base way.
  ## direction:
  ##   If direction is 0 then only the same line as the input cell is searched.
  ##   If direction is -1 then the previous lines will be searched.
  ##   If direction is +1 then the next lines will be searched.
  ## targetX: return the cell closest to this X location

  let uiRoot = updateContext.scrolledNode
  let maxYDiff = builder.lineHeight / 2
  let buffer = 2.0

  var offset = 0
  while true:
    offset = offset + direction
    let gap = builder.lineGap
    let searchRect = rect(uiRoot.lx, target.y + offset.float * builder.lineHeight + gap, uiRoot.lw, builder.lineHeight - gap * 2)

    if searchRect.yh < -builder.lineHeight * buffer or searchRect.y > uiRoot.lyh + builder.lineHeight * buffer:
      return

    var xDiffMin = float.high
    var selectedNode: UINode = nil
    var selectedCell: Cell = nil
    uiRoot.forEachOverlappingLeafNode(searchRect, proc(uiNode: UINode) =
      if abs(uiNode.ly - searchRect.y) > maxYDiff:
        return
      if uiNode.userData.isNil or not (uiNode.userData of Cell):
        return
      let currentCell = uiNode.userData.Cell

      let xDiff = if target.x < uiNode.lx:
        uiNode.lx - target.x
      elif target.x > uiNode.lxw:
        target.x - uiNode.lxw
      else:
        0

      if xDiff == 0:
        let offset = getCursorOffset(builder, currentCell, target.x - uiNode.lx, isThickCursor)
        if offset < currentCell.editableLow or offset > currentCell.editableHigh:
          return

      if xDiff < xDiffMin:
        xDiffMin = xDiff
        selectedNode = uiNode
        selectedCell = currentCell
    )

    if selectedCell.isNotNil:
      let offset = getCursorOffset(builder, selectedCell, target.x - selectedNode.lx, isThickCursor)
      return (selectedCell, offset).some

    if direction == 0:
      return

proc getCellInLine*(self: ModelDocumentEditor, cell: Cell, direction: int, targetX: float): Option[tuple[cell: Cell, offset: int]] =
  ## Searches for the next cell in a line base way.
  ## direction:
  ##   If direction is 0 then only the same line as the input cell is searched.
  ##   If direction is -1 then the previous lines will be searched.
  ##   If direction is +1 then the next lines will be searched.
  ## targetX: return the cell closest to this X location

  if not self.cellWidgetContext.cellToWidget.contains(cell.id):
    return

  let cellUINode = self.cellWidgetContext.cellToWidget[cell.id]
  return getCellInLine(self.app.platform.builder, self.cellWidgetContext, vec2(targetX, cellUINode.ly), direction, self.isThickCursor)

proc getPreviousCellInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  let uiRoot = self.scrolledNode
  let maxYDiff = self.app.platform.builder.lineHeight / 2

  if not self.cellWidgetContext.cellToWidget.contains(cell.id):
    return cell

  let cellUINode = self.cellWidgetContext.cellToWidget[cell.id]
  let charGap = self.app.platform.charGap
  let searchRect = rect(uiRoot.lx, cellUINode.ly + charGap, cellUINode.lx - uiRoot.lx, cellUINode.lh - charGap * 2)

  var xMax = float.low
  var selectedNode: UINode = nil
  var selectedCell: Cell = nil
  uiRoot.forEachOverlappingLeafNode(searchRect, proc(uiNode: UINode) =
    if uiNode.lxw > searchRect.xw or abs(uiNode.ly - searchRect.y) > maxYDiff:
      return

    if uiNode.userData.isNil or not (uiNode.userData of Cell):
      return

    let currentCell = uiNode.userData.Cell

    if currentCell == cell:
      return

    if uiNode.lxw > xMax:
      xMax = uiNode.lxw
      selectedNode = uiNode
      selectedCell = currentCell
  )

  if selectedCell.isNotNil:
    return selectedCell

  if self.getCellInLine(cell, -1, 10000).getSome(target):
    return target.cell

  return cell

proc getNextCellInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  let uiRoot = self.scrolledNode
  let maxYDiff = self.app.platform.builder.lineHeight / 2

  if not self.cellWidgetContext.cellToWidget.contains(cell.id):
    return cell

  let cellUINode = self.cellWidgetContext.cellToWidget[cell.id]
  let charGap = self.app.platform.charGap
  let searchRect = rect(cellUINode.lxw, cellUINode.ly + charGap, uiRoot.lxw - cellUINode.lxw, cellUINode.lh - charGap * 2)

  var xMin = float.high
  var selectedNode: UINode = nil
  var selectedCell: Cell = nil
  uiRoot.forEachOverlappingLeafNode(searchRect, proc(uiNode: UINode) =
    if uiNode.lx < searchRect.x or abs(uiNode.ly - searchRect.y) > maxYDiff:
      return

    if uiNode.userData.isNil or not (uiNode.userData of Cell):
      return

    let currentCell = uiNode.userData.Cell

    if currentCell == cell:
      return

    if uiNode.lx < xMin:
      xMin = uiNode.lx
      selectedNode = uiNode
      selectedCell = currentCell
  )

  if selectedCell.isNotNil:
    return selectedCell

  if self.getCellInLine(cell, 1, 0).getSome(target):
    return target.cell

  return cell

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

method getCursorLeft*(cell: Cell, map: NodeCellMap, cursor: CellCursor): CellCursor {.base.} = discard
method getCursorRight*(cell: Cell, map: NodeCellMap, cursor: CellCursor): CellCursor {.base.} = discard

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

proc getFirstLeaf*(cell: Cell, map: NodeCellMap): Cell =
  map.fill(cell)
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.CollectionCell.children[0].getFirstLeaf(map)
  return cell

proc getLastLeaf*(cell: Cell, map: NodeCellMap): Cell =
  map.fill(cell)
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.CollectionCell.children[cell.CollectionCell.children.high].getLastLeaf(map)
  return cell

proc getPreviousLeaf*(cell: Cell, map: NodeCellMap, childIndex: Option[int] = int.none): Option[Cell] =
  if cell.parent.isNil and cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.getLastLeaf(map).some

  if cell.parent.isNil:
    return Cell.none

  let parent = cell.parent.CollectionCell

  var index = parent.indexOf(cell)

  if index > 0:
    return parent.children[index - 1].getLastLeaf(map).some
  else:
    var newParent: Cell = parent
    var parentIndex = newParent.index
    while parentIndex != -1 and parentIndex == 0:
      newParent = newParent.parent
      parentIndex = newParent.index

    if parentIndex > 0:
      return newParent.previousDirect().map(proc(p: Cell): Cell = p.getLastLeaf(map))

    return cell.some

proc getNextLeaf*(cell: Cell, map: NodeCellMap, childIndex: Option[int] = int.none): Option[Cell] =
  if cell.parent.isNil and cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.getFirstLeaf(map).some

  if cell.parent.isNil:
    return Cell.none

  let parent = cell.parent.CollectionCell

  var index = parent.indexOf(cell)

  if index < parent.children.high:
    return parent.children[index + 1].getFirstLeaf(map).some
  else:
    var newParent: Cell = parent
    var parentIndex = newParent.index
    while parentIndex != -1 and parentIndex >= newParent.parentHigh:
      newParent = newParent.parent
      parentIndex = newParent.index

    if parentIndex < newParent.parentHigh:
      return newParent.nextDirect().map(proc(p: Cell): Cell = p.getFirstLeaf(map))

    return cell.some

proc getPreviousLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool): Option[Cell] =
  var temp = cell
  while true:
    var c = temp.getPreviousLeaf(map)
    # echo fmt"getPreviousLeafWhere {c}"
    if c.isNone:
      return Cell.none
    if predicate(c.get):
      return c
    if c.get == temp:
      return Cell.none
    temp = c.get

proc getNextLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool): Option[Cell] =
  var temp = cell
  while true:
    var c = temp.getNextLeaf(map)
    if c.isNone:
      return Cell.none
    if predicate(c.get):
      return c
    if c.get == temp:
      return Cell.none
    temp = c.get

proc getNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): (bool, Option[Cell])): Option[Cell] =
  var temp = cell
  while true:
    var c = if direction == Left: temp.getPreviousLeaf(map) else: temp.getNextLeaf(map)
    if c.isNone:
      return Cell.none
    let (done, res) = predicate(c.get)
    if done:
      return res
    if c.get == temp:
      return Cell.none
    temp = c.get

proc getNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): bool): Option[Cell] =
  case direction
  of Left:
    return cell.getPreviousLeafWhere(map, isVisible)
  of Right:
    return cell.getNextLeafWhere(map, isVisible)

proc getSelfOrPreviousLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getPreviousLeafWhere(map, predicate)

proc getSelfOrNextLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getNextLeafWhere(map, predicate)

proc getSelfOrNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): (bool, Option[Cell])): Option[Cell] =
  if cell.isLeaf:
    let (stop, res) = predicate(cell)
    if stop:
      return res
  return cell.getNeighborLeafWhere(map, direction, predicate)

proc getSelfOrNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): bool): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getNeighborLeafWhere(map, direction, predicate)

proc getPreviousSelectableLeaf*(cell: Cell, map: NodeCellMap): Option[Cell] =
  return cell.getPreviousLeafWhere(map, canSelect)

proc getNextSelectableLeaf*(cell: Cell, map: NodeCellMap): Option[Cell] =
  return cell.getNextLeafWhere(map, canSelect)

proc getNeighborSelectableLeaf*(cell: Cell, map: NodeCellMap, direction: Direction): Option[Cell] =
  return cell.getNeighborLeafWhere(map, direction, canSelect)

proc getPreviousVisibleLeaf*(cell: Cell, map: NodeCellMap): Option[Cell] =
  return cell.getPreviousLeafWhere(map, isVisible)

proc getNextVisibleLeaf*(cell: Cell, map: NodeCellMap): Option[Cell] =
  return cell.getNextLeafWhere(map, isVisible)

proc getNeighborVisibleLeaf*(cell: Cell, map: NodeCellMap, direction: Direction): Option[Cell] =
  return cell.getNeighborLeafWhere(map, direction, isVisible)

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

  var node = cell.node

  if result.cell.parent.isNotNil and result.cell.parent of NodeReferenceCell:
    result.cell = result.cell.parent
    node = result.cell.node

  while result.cell.parent.isNotNil and result.cell.parent.node == node:
    let index = result.cell.parent.CollectionCell.indexOf(result.cell)
    result.path.insert index, 0
    result.cell = result.cell.parent

    if result.cell.parent.isNotNil and result.cell.parent of NodeReferenceCell:
      result.cell = result.cell.parent
      node = result.cell.node

proc toCursor*(map: NodeCellMap, cell: Cell, column: int): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  result.index = clamp(column, cell.editableLow, cell.editableHigh)

proc toCursor*(map: NodeCellMap, cell: Cell, start: bool): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  if start:
    result.index = cell.editableLow
  else:
    result.index = cell.editableHigh

proc toCursor*(map: NodeCellMap, cell: Cell): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  result.index = cell.editableHigh(true)

proc toSelection*(map: NodeCellMap, cell: Cell): CellSelection = (map.toCursor(cell, true), map.toCursor(cell, false))

proc toCursorBackwards*(map: NodeCellMap, cell: Cell): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  result.index = 0

proc toSelectionBackwards*(map: NodeCellMap, cell: Cell): CellSelection = (map.toCursor(cell, false), map.toCursor(cell, true))

proc selectParentCell*(cursor: CellCursor): CellCursor =
  result = cursor
  if result.path.len > 0:
    result.index = result.path[result.path.high]
    discard result.path.pop()
  elif result.baseCell.parent.isNotNil:
    return cursor.map.toCursor(result.baseCell.parent, result.baseCell.index)

proc selectParentNodeCell*(cursor: CellCursor): CellCursor =
  result = cursor
  while result.node == cursor.node and result.baseCell.parent.isNotNil:
    result = result.selectParentCell()

proc updateCursor*(self: ModelDocumentEditor, cursor: CellCursor): Option[CellCursor] =
  let nodeCell = self.nodeCellMap.cell(cursor.node)
  if nodeCell.isNil:
    return CellCursor.none

  self.nodeCellMap.fill(nodeCell)

  var res = cursor

  var len = 0
  var cell = nodeCell
  for k, i in cursor.path:
    if not (cell of CollectionCell) or cell.CollectionCell.children.len == 0:
      break

    if i < 0 or i > cell.CollectionCell.children.high:
      break

    len = k + 1
    cell = cell.CollectionCell.children[i]

  debugf"updateCursor {cursor}, len {res.path.len} -> {len}, index {res.index} -> {(clamp(res.index, 0, cell.editableHigh(true)))}"
  res.path.setLen len
  res.index = clamp(res.index, 0, cell.editableHigh(true))

  return res.some

proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): Option[CellCursor] =
  result = CellCursor.none

  # debugf"getFirstEditableCellOfNode {node}"
  var nodeCell = self.nodeCellMap.cell(node)
  if nodeCell.isNil:
    return

  nodeCell = nodeCell.getFirstLeaf(self.nodeCellMap)
  # debugf"first leaf {nodeCell}"

  proc editableDescendant(n: Cell): (bool, Option[Cell]) =
    if n.node == nodeCell.node or n.node.isDescendant(nodeCell.node):
      return (isVisible(n) and not n.disableEditing, n.some)
    else:
      return (true, Cell.none)

  if nodeCell.getSelfOrNeighborLeafWhere(self.nodeCellMap, Right, editableDescendant).getSome(targetCell):
    # debugf"a: editable descendant {targetCell}"
    return self.nodeCellMap.toCursor(targetCell, true).some

  if nodeCell.getSelfOrNextLeafWhere(self.nodeCellMap, (n) => isVisible(n) and not n.disableSelection).getSome(targetCell):
    # debugf"a: visible descendant {targetCell}"
    return self.nodeCellMap.toCursor(targetCell, true).some

proc getFirstSelectableCellOfNode*(self: ModelDocumentEditor, node: AstNode): Option[CellCursor] =
  result = CellCursor.none

  debugf"getFirstSelectableCellOfNode {node}"
  var nodeCell = self.nodeCellMap.cell(node)
  if nodeCell.isNil:
    return

  nodeCell = nodeCell.getFirstLeaf(self.nodeCellMap)
  # echo fmt"first leaf {nodeCell}"

  proc selectableDescendant(n: Cell): (bool, Option[Cell]) =
    if n.node == nodeCell.node or n.node.isDescendant(nodeCell.node):
      return (isVisible(n) and n.canSelect, n.some)
    else:
      return (true, Cell.none)

  if nodeCell.getSelfOrNeighborLeafWhere(self.nodeCellMap, Right, selectableDescendant).getSome(targetCell):
    # echo fmt"a: selectable descendant {targetCell}"
    return self.nodeCellMap.toCursor(targetCell, true).some

  if nodeCell.getSelfOrNextLeafWhere(self.nodeCellMap, (n) => isVisible(n) and not n.disableSelection).getSome(targetCell):
    # echo fmt"a: visible descendant {targetCell}"
    return self.nodeCellMap.toCursor(targetCell, true).some

proc getFirstPropertyCellOfNode*(self: ModelDocumentEditor, node: AstNode, role: Id): Option[CellCursor] =
  result = CellCursor.none

  let nodeCell = self.nodeCellMap.cell(node)
  if nodeCell.isNil:
    return

  if nodeCell.getSelfOrNextLeafWhere(self.nodeCellMap, (n) => isVisible(n) and not n.disableEditing and n of PropertyCell and n.PropertyCell.property == role).getSome(targetCell):
    return self.nodeCellMap.toCursor(targetCell, true).some

method getCursorLeft*(cell: ConstantCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index > cell.editableLow:
    dec result.index
  else:
    if cell.getPreviousSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: NodeReferenceCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index > cell.editableLow:
    dec result.index
  else:
    if cell.getPreviousSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: AliasCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index > cell.editableLow:
    dec result.index
  else:
    if cell.getPreviousSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: PlaceholderCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index > cell.editableLow:
    dec result.index
  else:
    if cell.getPreviousSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: PropertyCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index > cell.editableLow:
    dec result.index
  else:
    if cell.getPreviousSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorRight*(cell: ConstantCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index < cell.editableHigh:
    inc result.index
  else:
    if cell.getNextSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: NodeReferenceCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index < cell.editableHigh:
    inc result.index
  else:
    if cell.getNextSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: AliasCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index < cell.editableHigh:
    inc result.index
  else:
    if cell.getNextSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: PlaceholderCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index < cell.editableHigh:
    inc result.index
  else:
    if cell.getNextSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: PropertyCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.index < cell.editableHigh:
    inc result.index
  else:
    if cell.getNextSelectableLeaf(map).getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorLeft*(cell: CollectionCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  result = cursor
  # if cell.children.len == 0 or cursor.index == 0:
  #   if cell.getPreviousSelectableLeaf().getSome(c):
  #     result = c.toCursor(true)
  #   return

  if cell.getPreviousSelectableLeaf(map).getSome(c):
    result = cursor.map.toCursor(c, true)
    return

  let childCell = cell.children[0]
  result.node = childCell.node
  result.path = if cell.node == childCell.node: cursor.path & 0 else: @[]
  result.index = 0

method getCursorRight*(cell: CollectionCell, map: NodeCellMap, cursor: CellCursor): CellCursor =
  # if cell.children.len == 0:
  #   return cursor

  if cell.getNextSelectableLeaf(map).getSome(c):
    result = cursor.map.toCursor(c, true)
    return

  let childCell = cell.children[cell.children.high]
  result.node = childCell.node
  result.path = if cell.node == childCell.node: cursor.path & cell.children.high else: @[]
  result.index = 0

method handleDeleteLeft*(cell: Cell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] {.base.} = discard
method handleDeleteRight*(cell: Cell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] {.base.} = discard

proc handleDelete*(map: NodeCellMap, cell: Cell, slice: Slice[int], direction: Direction): Option[CellCursor] =
  case direction
  of Left:
    return cell.handleDeleteLeft(map, slice)
  of Right:
    return cell.handleDeleteRight(map, slice)

method handleDeleteLeft*(cell: PropertyCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteLeft*(cell: ConstantCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteLeft*(cell: PlaceholderCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteLeft*(cell: AliasCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(cell: PropertyCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(cell: ConstantCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(cell: PlaceholderCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(cell: AliasCell, map: NodeCellMap, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

proc mode*(self: ModelDocumentEditor): string {.expose("editor.model").} =
  return self.currentMode

proc getContextWithMode*(self: ModelDocumentEditor, context: string): string {.expose("editor.model").} =
  return context & "." & $self.currentMode

proc isThickCursor*(self: ModelDocumentEditor): bool {.expose("editor.model").} =
  if not self.app.platform.supportsThinCursor:
    return true
  return self.configProvider.getValue(self.getContextWithMode("editor.model.cursor.wide"), false)

proc moveCursorLeft*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    let newCursor = cell.getCursorLeft(self.nodeCellMap, self.cursor)
    if newCursor.node.isNotNil:
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()

  self.markDirty()

proc moveCursorRight*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    let newCursor = cell.getCursorRight(self.nodeCellMap, self.cursor)
    if newCursor.node.isNotNil:
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()

  self.markDirty()

proc moveCursorLeftLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    var newCursor = cell.getCursorLeft(self.nodeCellMap, self.cursor)
    if newCursor.node == self.cursor.node:
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()
    else:
      let nextCell = self.getPreviousSelectableInLine(cell)
      newCursor = self.nodeCellMap.toCursor(nextCell, false)
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()

  self.markDirty()

proc moveCursorRightLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    var newCursor = cell.getCursorRight(self.nodeCellMap, self.cursor)
    if newCursor.node == self.cursor.node:
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()
    else:
      let nextCell = self.getNextSelectableInLine(cell)
      newCursor = self.nodeCellMap.toCursor(nextCell, true)
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()

  self.markDirty()

proc moveCursorLineStart*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if self.getCellInLine(cell, 0, 0).getSome(target):
      let newCursor = self.nodeCellMap.toCursor(target.cell, target.offset)
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()
  self.markDirty()

proc moveCursorLineEnd*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if self.getCellInLine(cell, 0, 10000).getSome(target):
      let newCursor = self.nodeCellMap.toCursor(target.cell, target.offset)
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()
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

    let newCursor = self.nodeCellMap.toCursor(prevCell, true)
    self.updateSelection(newCursor, select)
    self.updateScrollOffset()

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

    let newCursor = self.nodeCellMap.toCursor(prevCell, false)
    self.updateSelection(newCursor, select)
    self.updateScrollOffset()

  self.markDirty()

proc moveCursorUp*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell) and
    self.lastCursorLocationBounds.getSome(cursorBounds) and
    self.getCellInLine(cell, -1, cursorBounds.x).getSome(target):

    let newCursor = self.nodeCellMap.toCursor(target.cell, target.offset)
    self.updateSelection(newCursor, select)
    self.updateScrollOffset()

  else:
    self.moveCursorLeft(select)

  self.markDirty()

proc moveCursorDown*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell) and
    self.lastCursorLocationBounds.getSome(cursorBounds) and
    self.getCellInLine(cell, 1, cursorBounds.x).getSome(target):

    let newCursor = self.nodeCellMap.toCursor(target.cell, target.offset)
    self.updateSelection(newCursor, select)
    self.updateScrollOffset()

  else:
    self.moveCursorRight(select)

  self.markDirty()

proc moveCursorLeftCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.getPreviousSelectableLeaf(self.nodeCellMap).getSome(c):
      let newCursor = self.nodeCellMap.toCursor(c, false)
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()

  self.markDirty()

proc moveCursorRightCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.getNextSelectableLeaf(self.nodeCellMap).getSome(c):
      let newCursor = self.nodeCellMap.toCursor(c, true)
      self.updateSelection(newCursor, select)
      self.updateScrollOffset()

  self.markDirty()

proc selectNode*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  let (parentCell, _, _) = self.selection.getParentInfo
  if parentCell.isNil:
    return

  var newSelection = (
    parentCell.getFirstLeaf(self.nodeCellMap).getSelfOrNextLeafWhere(self.nodeCellMap, canSelect).mapIt(self.nodeCellMap.toCursor(it, true)),
    parentCell.getLastLeaf(self.nodeCellMap).getSelfOrPreviousLeafWhere(self.nodeCellMap, canSelect).mapIt(self.nodeCellMap.toCursor(it, false)))

  if parentCell.parent.isNotNil and (newSelection[0].isNone or newSelection[1].isNone or self.selection.normalized == (newSelection[0].get, newSelection[1].get)):
    newSelection = (
      parentCell.parent.getFirstLeaf(self.nodeCellMap).getSelfOrNextLeafWhere(self.nodeCellMap, canSelect).mapIt(self.nodeCellMap.toCursor(it, true)),
      parentCell.parent.getLastLeaf(self.nodeCellMap).getSelfOrPreviousLeafWhere(self.nodeCellMap, canSelect).mapIt(self.nodeCellMap.toCursor(it, false)))

  if parentCell.node.parent.isNotNil and (newSelection[0].isNone or newSelection[1].isNone or self.selection.normalized == (newSelection[0].get, newSelection[1].get)):
    let parentNodeCell = self.nodeCellMap.cell(parentCell.node.parent)
    newSelection = (
      parentNodeCell.getFirstLeaf(self.nodeCellMap).getSelfOrNextLeafWhere(self.nodeCellMap, canSelect).mapIt(self.nodeCellMap.toCursor(it, true)),
      parentNodeCell.getLastLeaf(self.nodeCellMap).getSelfOrPreviousLeafWhere(self.nodeCellMap, canSelect).mapIt(self.nodeCellMap.toCursor(it, false)))

  if newSelection[0].isSome and newSelection[1].isSome:
    self.selection = (newSelection[0].get, newSelection[1].get)

  self.updateScrollOffset()

  self.markDirty()

proc shouldEdit*(cell: Cell): bool =
  if (cell of PlaceholderCell):
    return true
  let class = cell.node.nodeClass
  if class.isNotNil and (class.isAbstract or class.isInterface):
    return true
  return false

proc selectPrevPlaceholder*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.cursor.targetCell.getPreviousLeafWhere(self.nodeCellMap, proc(c: Cell): bool = isVisible(c) and shouldEdit(c)).getSome(candidate):
    if not shouldEdit(candidate):
      return

    self.cursor = self.nodeCellMap.toCursor(candidate, true)
    self.updateScrollOffset()
    self.markDirty()

proc selectNextPlaceholder*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.cursor.targetCell.getNextLeafWhere(self.nodeCellMap, proc(c: Cell): bool = isVisible(c) and shouldEdit(c)).getSome(candidate):
    if not shouldEdit(candidate):
      return

    self.cursor = self.nodeCellMap.toCursor(candidate, true)
    self.updateScrollOffset()
    self.markDirty()

proc deleteDirection*(self: ModelDocumentEditor, direction: Direction) =
  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

  let cell = self.selection.last.targetCell
  let endIndex = if direction == Left: 0 else: cell.currentText.len

  var potentialCells: seq[(Cell, Slice[int], Direction)] = @[(cell, self.selection.orderedRange, direction)]
  if self.selection.last.index == endIndex and self.selection.first.index == self.selection.last.index and cell.getNeighborSelectableLeaf(self.nodeCellMap, direction).getSome(prev):
    let index = if direction == Left:
      prev.editableHigh(true)
    else:
      prev.editableLow(true)

    potentialCells.add (prev, index..index, -direction)

  for i, (c, slice, cursorMoveDirection) in potentialCells:
    let node = c.node
    let parent = node.parent
    assert parent.isNotNil

    let endIndex = if direction == Left: 0 else: c.currentText.len

    proc getAdjacentCell(c: Cell, direction: Direction): Option[Cell] =
      if direction == Left:
        let leaf = c.nodeRootCell.getFirstLeaf(self.nodeCellMap)
        leaf.getPreviousSelectableLeaf(self.nodeCellMap)
      else:
        let leaf = c.nodeRootCell.getLastLeaf(self.nodeCellMap)
        leaf.getNextSelectableLeaf(self.nodeCellMap)

    var nextCellDirection = direction
    var nextSelectableCell = getAdjacentCell(c, direction)
    if nextSelectableCell.isNone:
      nextCellDirection = -direction
      nextSelectableCell = getAdjacentCell(c, -direction)

    if self.nodeCellMap.handleDelete(c, slice, direction).getSome(newCursor):
      self.cursor = newCursor

      if c.currentText.len == 0 and not c.dontReplaceWithDefault and c.parent.node != c.node:
        if c.node.replaceWithDefault().getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get

      break

    let nextSelectableCursor = self.nodeCellMap.toCursor(nextSelectableCell.get, nextCellDirection == Right)

    if c.currentText.len == 0 and not c.dontReplaceWithDefault and c.parent.node != c.node and not c.node.isRequiredAndDefault():
      let parent = c.node.parent

      if c.node.deleteOrReplaceWithDefault().getSome(newNode): # Node was replaced
        self.rebuildCells()
        self.cursor = self.getFirstEditableCellOfNode(newNode).get
      else: # Node was removed
        self.rebuildCells()
        if self.updateCursor(nextSelectableCursor).getSome(newCursor):
          self.cursor = newCursor
        else:
          self.cursor = self.getFirstEditableCellOfNode(parent).get

        # # Get next neighbor cell which is of a different node and not a child, and can be selected
        # var targetCell = c.getNeighborLeafWhere(self.nodeCellMap, cursorMoveDirection, proc(cell: Cell): (bool, Option[Cell]) =
        #   if cell.node != c.node and cell.node != parent and not cell.node.isDescendant(parent):
        #     return (true, Cell.none)
        #   if not isVisible(cell) or not canSelect(cell):
        #     return (false, Cell.none)
        #   if cell == c or cell.node == c.node or cell.node == parent:
        #     return (false, Cell.none)
        #   return (true, cell.some)
        # )

        # # Get next neighbor cell which is of a different node and not a child, and can be selected
        # if targetCell.isNone:
        #   targetCell = c.getNeighborLeafWhere(self.nodeCellMap, -cursorMoveDirection, proc(cell: Cell): (bool, Option[Cell]) =
        #     if cell.node != c.node and cell.node != parent and not cell.node.isDescendant(parent):
        #       return (true, Cell.none)
        #     if not isVisible(cell) or not canSelect(cell):
        #       return (false, Cell.none)
        #     if cell == c or cell.node == c.node or cell.node == parent:
        #       return (false, Cell.none)
        #     return (true, cell.some)
        #   )

        # if targetCell.getSome(targetCell):
        #   debugf"delete left "
        #   let cursor = self.nodeCellMap.toCursor(targetCell, cursorMoveDirection == Right)
        #   debugf"{targetCell}, {cursor}"
        #   self.rebuildCells()
        #   if self.updateCursor(cursor).getSome(newCursor):
        #     self.cursor = newCursor
        #     break

        # let uiae = self.nodeCellMap.toCursor(c)

        # var parentCellCursor = uiae.selectParentCell()
        # assert parentCellCursor.node == c.node.parent

        # self.rebuildCells()
        # if self.updateCursor(parentCellCursor).flatMap((c: CellCursor) -> Option[Cell] => c.getTargetCell(true)).getSome(newCell):
        #   if i == 0 and direction == Left and newCell.getNeighborSelectableLeaf(self.nodeCellMap, direction).getSome(c):
        #     self.cursor = self.nodeCellMap.toCursor(c)
        #   elif newCell.getSelfOrNeighborLeafWhere(self.nodeCellMap, direction, (c) -> bool => isVisible(c)).getSome(c):
        #     self.cursor = self.nodeCellMap.toCursor(c, true)
        #   else:
        #     self.cursor = self.nodeCellMap.toCursor(newCell, true)
        # else:
        #   self.cursor = self.getFirstEditableCellOfNode(parent).get
      break

    if slice.a == slice.b and slice.a == endIndex:
      continue

    if c.disableEditing:
      if c.deleteImmediately or (slice.a == 0 and slice.b == c.currentText.len):

        if c.deleteNeighbor:
          let neighbor = if direction == Left: c.previousDirect() else: c.nextDirect()
          if neighbor.getSome(neighbor):
            let parent = neighbor.node.parent

            let selectionTarget = c.getNeighborSelectableLeaf(self.nodeCellMap, -direction)

            if neighbor.node.deleteOrReplaceWithDefault().getSome(newNode):
              self.rebuildCells()
              self.cursor = self.getFirstEditableCellOfNode(newNode).get
            else:
              self.rebuildCells()
              if selectionTarget.getSome(selectionTarget) and self.updateCursor(self.nodeCellMap.toCursor(selectionTarget, direction == Left)).getSome(newCursor):
                self.cursor = newCursor
              else:
                self.cursor = self.getFirstEditableCellOfNode(parent).get

        elif c.node.replaceWithDefault().getSome(newNode):
            self.rebuildCells()
            self.cursor = self.getFirstEditableCellOfNode(newNode).get
      else:
        case direction
        of Left:
          self.selection = self.nodeCellMap.toSelectionBackwards(c)
        of Right:
          self.selection = self.nodeCellMap.toSelection(c)
      break

proc getParentInfo*(selection: CellSelection): tuple[cell: Cell, left: seq[int], right: seq[int]] =
  ## Returns information about common parent cell of the selection, as well as the path from the parent cell to the first and last selected cell
  ## result.cell: the common parent cell. Nil if the cells don't share a common root
  ## result.left: the path from the parent cell to the first selected cell
  ## result.right: the path from the parent cell to the last selected cell

  if selection.isEmpty:
    return (selection.first.targetCell, @[], @[])

  let firstPath = selection.first.rootPath
  let lastPath = selection.last.rootPath

  if firstPath.root != lastPath.root:
    return (nil, @[], @[])

  var commonParentIndex = -1
  for i in 0..min(firstPath.path.high, lastPath.path.high):
    if firstPath.path[i] != lastPath.path[i]:
      break
    commonParentIndex = i
  let childIndex = commonParentIndex + 1

  let rootCell = firstPath.root
  var parentCursor = CellCursor(map: selection.first.map, node: rootCell.node, path: firstPath.path[0..commonParentIndex], index: 0)
  let parentCell = parentCursor.targetCell
  return (parentCell, firstPath.path[childIndex+1..^1], lastPath.path[childIndex+1..^1])

proc clampedPathToCell*(cursor: CellCursor, cell: Cell, direction: Direction): tuple[path: seq[int], outside: bool] =
  let cellPath = cell.rootPath
  let cursorPath = cursor.rootPath

  # debugf"clampedPathToCell {cursor}, {cell}"
  # echo cursorPath.path, ", ", cellPath.path

  let count = min(cellPath.path.high, cursorPath.path.high)
  for i in 0..count:
    if cursorPath.path[i] < cellPath.path[i]:
      return (@[], direction == Left)
    if cursorPath.path[i] > cellPath.path[i]:
      return (@[], direction == Right)

  return (cursorPath.path[count+1..^1], false)

proc contains*(selection: CellSelection, cell: Cell): bool =
  let selection = selection.normalized
  let parentInfo = selection.getParentInfo()
  if parentInfo.cell.isNil:
    return false

  if not cell.isDescendant(parentInfo.cell) and cell != parentInfo.cell:
    return false

  let left = selection.first.clampedPathToCell(cell, Right)
  let right = selection.last.clampedPathToCell(cell, Left)
  if left.outside or right.outside:
    return false

  # echo "contains ", cell, ": ", left, ", ", right

  return cell.isFullyContained(left.path, right.path)

proc deleteOrReplace*(self: ModelDocumentEditor, direction: Direction, replace: bool) =
  # debugf"delete {self.selection.first} .. {self.selection.last}"
  # debugf"delete {self.selection.first.rootPath.path} .. {self.selection.last.rootPath.path}"

  if self.selection.isEmpty:
    self.deleteDirection(direction)
    return

  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

  let selection = self.selection.normalized
  let firstPath = selection.first.rootPath
  let lastPath = selection.last.rootPath

  if firstPath.root != lastPath.root:
    return

  var commonParentIndex = -1
  for i in 0..min(firstPath.path.high, lastPath.path.high):
    if firstPath.path[i] != lastPath.path[i]:
      break
    commonParentIndex = i
  let childIndex = commonParentIndex + 1

  let rootCell = firstPath.root
  var parentCursor = CellCursor(map: self.nodeCellMap, node: rootCell.node, path: firstPath.path[0..commonParentIndex], index: 0)
  let parentTargetCell = parentCursor.targetCell  # the actual targeted cell
  parentCursor = self.nodeCellMap.toCursor(parentTargetCell, true)
  let parentBaseCell = parentCursor.baseCell      # the root cell for the given node

  let firstIndex = if commonParentIndex < firstPath.path.len: firstPath.path[childIndex] else: 0
  let lastIndex = if commonParentIndex < lastPath.path.len: lastPath.path[childIndex] else: parentTargetCell.len

  # debugf"common parent {commonParentIndex}, {firstIndex}..{lastIndex}, {parentBaseCell}, {parentTargetCell}, {parentBaseCell == parentTargetCell}"

  # let firstCell = parentCell.getSelfOrNextLeafWhere(proc(cell: Cell): bool = cell.canSelect())
  # let lastCell = parentCell.getSelfOrPreviousLeafWhere(proc(cell: Cell): bool = cell.canSelect())

  if parentTargetCell of CollectionCell:
    let parentCell = parentTargetCell.CollectionCell
    let firstContained = self.selection.contains(parentCell.children[firstIndex])
    let lastContained = self.selection.contains(parentCell.children[lastIndex])

    # debug firstContained, ", ", lastContained
    if firstContained and lastContained:
      if firstIndex == 0 and lastIndex == parentCell.high and parentTargetCell == parentBaseCell: # entire parent selected
        # debugf"all cells selected"

        var targetNode = parentCell.node

        if DeleteWhenEmpty in parentCell.parent.flags and parentCell.parent.len == 1: # Selected only child of parent:
          targetNode = parentCell.parent.node

        let targetParentNode = targetNode.parent

        if replace and targetNode.replaceWithDefault().getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get
        elif not replace and targetNode.deleteOrReplaceWithDefault().getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get
        else:
          self.rebuildCells()
          if self.getFirstEditableCellOfNode(targetParentNode).getSome(c):
            self.cursor = c

      else: # some children of parent cell selected
        var nodesToDelete: seq[AstNode]
        for c in parentCell.children[firstIndex..lastIndex]:
          if c.node != parentCell.node:
            nodesToDelete.add c.node

        # debug "some children of parent cell selected ", nodesToDelete

        for n in nodesToDelete:
          if replace:
            discard n.replaceWithDefault()
          else:
            discard n.deleteOrReplaceWithDefault()

        self.rebuildCells()
        self.cursor = self.getFirstEditableCellOfNode(parentCell.node).get

    else: # not all nodes fully contained
      # debugf"not all nodes fully contained"
      discard

  else: # not collection cell
    # debug firstIndex, ", ", lastIndex, "/", parentTargetCell.len
    if selection.contains(parentTargetCell):
      if replace and parentTargetCell.node.replaceWithDefault().getSome(newNode):
        self.rebuildCells()
        self.cursor = self.getFirstEditableCellOfNode(newNode).get
        self.updateScrollOffset()
      elif not replace and parentTargetCell.node.deleteOrReplaceWithDefault().getSome(newNode):
        self.rebuildCells()
        self.cursor = self.getFirstEditableCellOfNode(newNode).get
        self.updateScrollOffset()
      else:
        self.rebuildCells()
        if self.getFirstEditableCellOfNode(parentTargetCell.node.parent).getSome(c):
          self.cursor = c
          self.updateScrollOffset()

proc deleteLeft*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()
  self.deleteOrReplace(Left, false)
  self.markDirty()

proc deleteRight*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()
  self.deleteOrReplace(Right, false)
  self.markDirty()

proc replaceLeft*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()
  self.deleteOrReplace(Left, true)
  self.markDirty()

proc replaceRight*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()
  self.deleteOrReplace(Right, true)
  self.markDirty()

proc isAtBeginningOfFirstCellOfNode*(cursor: CellCursor): bool =
  result = cursor.index == 0
  if result:
    for i in cursor.path:
      if i != 0:
        return false

proc isAtEndOfLastCellOfNode*(cursor: CellCursor): bool =
  var cell = cursor.baseCell
  for i in cursor.path:
    if i != cell.high:
      return false
    cell = cell.CollectionCell.children[i]
  if cell of CollectionCell:
    return cursor.index == cell.high
  else:
    return cursor.index == cell.high + 1

proc insertIntoNode*(self: ModelDocumentEditor, parent: AstNode, role: Id, index: int): Option[AstNode] =
  let parentCell = self.nodeCellMap.cell(parent)
  debugf"insertIntoNode {index} {parent}, {parentCell.nodeFactory.isNotNil}"

  if parentCell.nodeFactory.isNotNil:
    let newNode = parentCell.nodeFactory()
    parent.insert(role, index, newNode)
    return newNode.some
  else:
    return parent.insertDefaultNode(role, index)

proc insertBeforeNode*(self: ModelDocumentEditor, node: AstNode): Option[AstNode] =
  let parentCell = self.nodeCellMap.cell(node.parent)
  debugf"01 insert before {node.index} {node.parent}, {parentCell.nodeFactory.isNotNil}"

  return self.insertIntoNode(node.parent, node.role, node.index)

proc insertAfterNode*(self: ModelDocumentEditor, node: AstNode): Option[AstNode] =
  let parentCell = self.nodeCellMap.cell(node.parent)
  debugf"01 insert before {node.index} {node.parent}, {parentCell.nodeFactory.isNotNil}"

  return self.insertIntoNode(node.parent, node.role, node.index + 1)

proc createNewNodeAt*(self: ModelDocumentEditor, cursor: CellCursor): Option[AstNode] =
  let canHaveSiblings = cursor.node.canHaveSiblings()

  defer:
    self.rebuildCells()

  if cursor.isAtEndOfLastCellOfNode() and canHaveSiblings:
    return self.insertAfterNode(cursor.node)

  if canHaveSiblings and cursor.isAtBeginningOfFirstCellOfNode():
    return self.insertBeforeNode(cursor.node)

  var temp = cursor
  while true:
    let newParent = temp.selectParentNodeCell
    debugf"temp: {temp}, parent: {newParent}"
    if newParent.node == temp.node:
      break
    if newParent.isAtEndOfLastCellOfNode():
      if newParent.node.canHaveSiblings():
        return self.insertAfterNode(newParent.node)
      temp = newParent
      continue

    if newParent.isAtBeginningOfFirstCellOfNode():
      if newParent.node.canHaveSiblings():
        return self.insertBeforeNode(newParent.node)
      temp = newParent
      continue

    break


  let cell = cursor.targetCell
  var i = 0
  let originalNode = cell.node

  var ok = false
  var addBefore = true
  var candidate = cell.getSelfOrNextLeafWhere(self.nodeCellMap, proc(c: Cell): bool =
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
  )

  if (not ok or candidate.isNone) and not originalNode.canHaveSiblings():
    debug "search outside"
    candidate = cell.getSelfOrNextLeafWhere(self.nodeCellMap, proc(c: Cell): bool =
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
    )

  debugf"ok: {ok}, addBefore: {addBefore}"
  if ok and candidate.isSome:
    if addBefore:
      return self.insertBeforeNode(candidate.get.node)
    else:
      return self.insertAfterNode(candidate.get.node)

  if originalNode.canHaveSiblings():
    if addBefore:
      return self.insertBeforeNode(originalNode)
    else:
      return self.insertAfterNode(originalNode)

  return AstNode.none

proc createNewNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  if not self.selection.isEmpty:
    return

  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

  debug "createNewNode"

  if self.createNewNodeAt(self.cursor).getSome(newNode):
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(newNode).get
    debug self.cursor

  self.markDirty()

proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  if getTargetCell(self.cursor).getSome(cell):
    if cell.disableEditing:
      return false

    let newColumn = cell.replaceText(self.cursor.index..self.cursor.index, input)
    if newColumn != self.cursor.index:
      var newCursor = self.selection.last
      newCursor.index = newColumn
      self.cursor = newCursor
      self.updateScrollOffset()

      if self.unfilteredCompletions.len == 0:
        self.updateCompletions()
      else:
        self.refilterCompletions()

      if not self.showCompletions and self.completionsLen == 1 and (self.getCompletion(0).alwaysApply or self.getCompletion(0).name == cell.currentText):
        self.applySelectedCompletion()

      self.markDirty()
      return true
  return false

proc getCursorForOp(self: ModelDocumentEditor, op: ModelOperation): CellSelection =
  result = self.selection
  case op.kind
  of Delete:
    return self.getFirstEditableCellOfNode(op.node).get(self.cursor).toSelection
  of Insert:
    return self.getFirstEditableCellOfNode(op.parent).get(self.cursor).toSelection
  of PropertyChange:
    if self.getFirstPropertyCellOfNode(op.node, op.role).getSome(c):
      result = (c, c)
      result.first.index = op.slice.a
      result.last.index = op.slice.b
  of ReferenceChange:
    return self.getFirstEditableCellOfNode(op.node).get(self.cursor).toSelection
  of Replace:
    discard

proc undo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.undo().getSome(t):
    self.rebuildCells()
    if self.transactionCursors.contains(t[0]):
      self.selection = self.transactionCursors[t[0]]
    else:
      self.selection = self.getCursorForOp(t[1])
    self.updateScrollOffset(false)
    self.markDirty()

proc redo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.redo().getSome(t):
    self.rebuildCells()
    if self.transactionCursors.contains(t[0]):
      self.selection = self.transactionCursors[t[0]]
    else:
      self.selection = self.getCursorForOp(t[1])
    self.updateScrollOffset(false)
    self.markDirty()

proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.nodeCellMap.builder.forceDefault = not self.nodeCellMap.builder.forceDefault
  self.rebuildCells()
  if self.getFirstEditableCellOfNode(self.selection.first.node).getSome(first) and self.getFirstEditableCellOfNode(self.selection.last.node).getSome(last):
    self.selection = (first, last)
  elif self.getFirstSelectableCellOfNode(self.selection.first.node).getSome(first) and self.getFirstSelectableCellOfNode(self.selection.last.node).getSome(last):
    self.selection = (first, last)
  else:
    self.cursor = self.nodeCellMap.toCursor(self.nodeCellMap.cell(self.cursor.node).getFirstLeaf(self.nodeCellMap), true)
  self.updateScrollOffset()
  self.markDirty()

proc showCompletions*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.showCompletions:
    var newCursor = self.selection.last
    newCursor.index = 0
    self.cursor = newCursor
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

  let completionText = self.cursor.targetCell.currentText

  if self.selectedCompletion < self.completionsLen:
    let completion = self.getCompletion(self.selectedCompletion)
    let parent = completion.parent
    let role = completion.role
    let index = completion.index

    case completion.kind:
    of ModelCompletionKind.SubstituteClass:
      parent.remove(role, index)

      var newNode = newAstNode(completion.class)
      newNode.fillDefaultChildren(parent.model, true)
      parent.insert(role, index, newNode)
      self.rebuildCells()
      self.cursor = self.getFirstEditableCellOfNode(newNode).get

      if completion.property.getSome(role):
        var cell = PropertyCell(node: newNode, property: role)
        cell.setText(completionText)

    of ModelCompletionKind.SubstituteReference:
      parent.remove(role, index)

      let newNode = newAstNode(completion.class)
      newNode.setReference(completion.referenceRole, completion.referenceTarget.id)
      parent.insert(role, index, newNode)
      self.rebuildCells()
      self.cursor = self.getFirstEditableCellOfNode(newNode).get

    of ModelCompletionKind.ChangeReference:
      debugf"update reference of {completion.parent}:{completion.role} to {completion.changeReferenceTarget}"
      completion.parent.setReference(completion.role, completion.changeReferenceTarget.id)
      self.rebuildCells()
      # self.cursor = self.getFirstEditableCellOfNode(newNode).get

    self.showCompletions = false

  var c = self.cursor
  c.index = c.targetCell.editableHigh
  self.cursor = c

  self.markDirty()

proc findContainingFunction(node: AstNode): Option[AstNode] =
  if node.class == IdFunctionDefinition:
    return node.some
  if node.parent.isNotNil:
    return node.parent.findContainingFunction()
  return AstNode.none

import scripting/wasm

proc intToString(a: int32): cstring =
  let res = $a
  return res.cstring

proc runSelectedFunctionAsync*(self: ModelDocumentEditor): Future[void] {.async.} =
  let timer = startTimer()
  defer:
    log(lvlInfo, fmt"runSelectedFunctionAsync took {timer.elapsed.ms} ms")

  let function = self.cursor.node.findContainingFunction()
  if function.isNone:
    log(lvlError, fmt"Not inside function")
    return

  block: # todo
    self.document.ctx.state.updateNode(function.get)

    let typ = self.document.ctx.computeType(function.get)
    log lvlDebug, `$`(typ, true)

  if function.get.childCount(IdFunctionDefinitionParameters) > 0:
    log(lvlError, fmt"Can't call function with parameters")
    return

  let parent = function.get.parent
  let name = if parent.isNotNil and parent.class == IdConstDecl:
    parent.property(IdINamedName).get.stringValue
  else:
    "<anonymous>"

  measureBlock fmt"Compile '{name}' to wasm":
    var compiler = newBaseLanguageWasmCompiler(self.document.ctx)
    let binary = compiler.compileToBinary(function.get)

  if self.document.workspace.getSome(workspace):
    discard workspace.saveFile("jstest.wasm", binary.toArrayBuffer)

  var lineBuffer {.global.} = ""

  proc printI32(a: int32) =
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

  proc printString(a: cstring) =
    lineBuffer.add $a

  proc printLine() =
    log lvlInfo, lineBuffer
    lineBuffer = ""

  var imp = WasmImports(namespace: "env")
  imp.addFunction("print_i32", printI32)
  imp.addFunction("print_string", printString)
  imp.addFunction("print_line", printLine)
  imp.addFunction("intToString", intToString)

  measureBlock fmt"Create wasm module for '{name}'":
    let module = await newWasmModule(binary.toArrayBuffer, @[imp])
    if module.isNone:
      log lvlError, "Failed to create wasm module from generated binary for {name}"
      return

  if module.get.findFunction($function.get.id, void, proc(): void).getSome(f):
    measureBlock fmt"Run '{name}'":
      f()
  else:
    log lvlError, fmt"Failed to find function {function.get.id} in wasm module"

proc runSelectedFunction*(self: ModelDocumentEditor) {.expose("editor.model").} =
  asyncCheck runSelectedFunctionAsync(self)

genDispatcher("editor.model")

proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse =
  # log lvlInfo, fmt"[modeleditor]: Handle action {action}, '{arg}'"
  # defer:
  #   log lvlDebug, &"line: {self.cursor.targetCell.line}, cursor: {self.cursor},\ncell: {self.cursor.cell.dump()}\ntargetCell: {self.cursor.targetCell.dump()}"

  self.mCursorBeforeTransaction = self.selection

  var args = newJArray()
  try:
    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    if self.app.handleUnknownDocumentEditorAction(self, action, args) == Handled:
      return Handled

    args.elems.insert api.ModelDocumentEditor(id: self.id).toJson, 0

    if dispatch(action, args).isSome:
      return Handled
  except CatchableError:
    log lvlError, fmt"Failed to dispatch action '{action} {args}': {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()

  return Ignored

method getStateJson*(self: ModelDocumentEditor): JsonNode =
  return %*{
    "cursor": %*{
      "index": self.cursor.index,
      "path": self.cursor.path,
      "nodeId": self.cursor.node.id.Id.toJson,
    }
  }

method restoreStateJson*(self: ModelDocumentEditor, state: JsonNode) =
  if state.kind != JObject:
    return
  if state.hasKey("cursor"):
    try:
      let cursorState = state["cursor"]
      debug cursorState.pretty
      let index = cursorState["index"].jsonTo int
      let path = cursorState["path"].jsonTo seq[int]
      let nodeId = cursorState["nodeId"].jsonTo(NodeId)
      self.targetCursor = CellCursorState(index: index, path: path, node: nodeId)
    except:
      log lvlError, fmt"Failed to restore cursor state: {getCurrentExceptionMsg()}"