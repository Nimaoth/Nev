import std/[strformat, strutils, math, sugar, tables, options, json, streams, algorithm]
import fusion/matching, bumpy, rect_utils, vmath
import util, document, document_editor, text/text_document, events, id, ast_ids, scripting/expose, event, input, custom_async, myjsonutils
from scripting_api as api import nil
import custom_logger, timer, array_buffer, config_provider, app_interface
import platform/[filesystem, platform]
import workspaces/[workspace]
import ast/[types, base_language, cells]
import ui/node

import ast/base_language_wasm

var project = newProject()

logCategory "model"
createJavascriptPrototype("editor.model")

type
  CellCursor* = object
    map: NodeCellMap
    firstIndex*: int
    lastIndex*: int
    path*: seq[int]
    node*: AstNode

  CellSelection* = tuple[first: CellCursor, last: CellCursor]

  CellCursorState = object
    firstIndex*: int
    lastIndex*: int
    path*: seq[int]
    node*: NodeId

type Direction* = enum
  Left, Right

func `-`*(d: Direction): Direction =
  case d
  of Left: return Right
  of Right: return Left

proc invalidate*(map: NodeCellMap) =
  map.map.clear()

proc cell*(map: NodeCellMap, node: AstNode): Cell =
  if map.map.contains(node.id):
    return map.map[node.id]
  let cell = map.builder.buildCell(map, node, false)
  map.map[node.id] = cell
  return cell

proc toSelection*(cursor: CellCursor): CellSelection = (cursor, cursor)

proc empty*(selection: CellSelection): bool = selection.first == selection.last

proc `$`*(cursor: CellCursor): string = fmt"CellCursor({cursor.firstIndex}:{cursor.lastIndex}, {cursor.path}, {cursor.node})"

proc `$`*(selection: CellSelection): string = fmt"({selection.first}, {selection.last})"

proc `column=`(cursor: var CellCursor, column: int) =
  cursor.firstIndex = column
  cursor.lastIndex = column

proc orderedRange*(cursor: CellCursor): Slice[int] =
  return min(cursor.firstIndex, cursor.lastIndex)..max(cursor.firstIndex, cursor.lastIndex)

proc cell*(cursor: CellCursor): Cell =
  return cursor.map.cell(cursor.node)

proc targetCell*(cursor: CellCursor): Cell =
  result = cursor.cell
  cursor.map.fill(result)
  for i in cursor.path:
    if result of CollectionCell:
      result = result.CollectionCell.children[i]

proc rootPath*(cursor: CellCursor): tuple[root: Cell, path: seq[int]] =
  var cell = cursor.targetCell
  var path: seq[int] = @[]
  while cell.parent.isNotNil:
    let idx = cell.parent.CollectionCell.children.find(cell)
    path.add idx
    cell = cell.parent

  path.reverse()
  path.add cursor.lastIndex

  return (cell, path)

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

  ModelDocumentEditor* = ref object of DocumentEditor
    app*: AppInterface
    configProvider*: ConfigProvider
    document*: ModelDocument

    cursorsId*: Id
    completionsId*: Id
    lastCursorLocationBounds*: Option[Rect]

    transactionCursors: Table[Id, CellSelection]

    modeEventHandler: EventHandler
    completionEventHandler: EventHandler
    currentMode*: string

    nodeCellMap*: NodeCellMap
    logicalLines*: seq[seq[Cell]]
    cellWidgetContext*: UpdateContext
    mCursorBeforeTransaction: CellSelection
    mSelection: CellSelection
    mTargetCursor: Option[CellCursorState]

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
    completionsBaseIndex*: int
    completionsScrollOffset*: float
    scrollToCompletion*: Option[int]

  UpdateContext* = ref object
    nodeCellMap*: NodeCellMap
    cellToWidget*: Table[Id, UINode]
    targetNodeOld*: UINode
    targetNode*: UINode
    targetCell*: Cell
    handleClick*: proc(node: UINode, cell: Cell, path: seq[int], cursor: CellCursor, drag: bool)
    selectionColor*: Color

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
proc updateCursor*(self: ModelDocumentEditor, cursor: CellCursor): Option[CellCursor]

proc toCursor*(map: NodeCellMap, cell: Cell, column: int): CellCursor
proc toCursor*(map: NodeCellMap, cell: Cell, start: bool): CellCursor
proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): Option[CellCursor]
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

proc `selection=`*(self: ModelDocumentEditor, selection: CellSelection) =
  assert self.mSelection.first.map.isNotNil
  assert self.mSelection.last.map.isNotNil
  if self.mSelection.last.targetCell != selection.last.targetCell:
    self.mSelection = selection
    self.invalidateCompletions()
  else:
    self.mSelection = selection
    self.refilterCompletions()

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursor) =
  self.selection = (cursor, cursor)

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursorState) =
  if self.document.model.resolveReference(cursor.node).getSome(node):
    if self.updateCursor(CellCursor(map: self.nodeCellMap, firstIndex: cursor.firstIndex, lastIndex: cursor.lastIndex, path: cursor.path, node: node)).getSome(cursor):
      self.cursor = cursor

proc `targetCursor=`*(self: ModelDocumentEditor, cursor: CellCursorState) =
  self.mTargetCursor = cursor.some
  self.cursor = cursor

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
  if class.references.len == 1:
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
  let index = self.cursor.lastIndex
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

  let parentClass = parent.nodeClass
  let childDesc = parentClass.nodeChildDescription(role).get

  let model = node.model

  let desc = childDesc
  let slotClass = model.resolveClass(desc.class)

  debugf"updateCompletions {node}, {node.model.isNotNil}, {slotClass.name}"

  for language in model.languages:
    language.forEachChildClass slotClass, proc(childClass: NodeClass) =
      if self.getSubstitutionsForClass(targetCell, childClass, (c) -> void => self.unfilteredCompletions.add(c)):
        return

      if childClass.isAbstract or childClass.isInterface:
        return

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
    let vertical = LayoutVertical in coll.flags

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

  self.nodeCellMap.invalidate()

  self.logicalLines.setLen 0

  for node in self.document.model.rootNodes:
    let cell = builder.buildCell(self.nodeCellMap, node, self.useDefaultCellBuilder)
    cell.buildNodeCellMap(self.nodeCellMap.map)

    var temp = true
    discard self.assignToLogicalLines(cell, 0, temp)

proc toJson*(self: api.ModelDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.model")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.ModelDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc handleInput(self: ModelDocumentEditor, input: string): EventResponse =
  log lvlInfo, fmt"[modeleditor]: Handle input '{input}'"

  self.mCursorBeforeTransaction = self.selection

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

  if button != MouseButton.Left:
    return

  for rootNode in self.document.model.rootNodes:
    let cell = self.nodeCellMap.cell(rootNode)
    if cell.isNil:
      continue

    if self.getLeafCellContainingPoint(cell, mousePosWindow).getSome(leafCell):
      if leafCell.line < self.logicalLines.high:
        if self.getCursorInLine(leafCell.line, mousePosWindow.x).getSome(newCursor):
          self.cursor = selectCursor(self.cursor, newCursor, false)
          self.markDirty()
          break

      self.cursor = self.nodeCellMap.toCursor(leafCell, true)
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
      let cell = self.nodeCellMap.cell(rootNode)
      if cell.isNil:
        continue

      if self.getLeafCellContainingPoint(cell, mousePosWindow).getSome(leafCell):
        if leafCell.line < self.logicalLines.high:
          if self.getCursorInLine(leafCell.line, mousePosWindow.x).getSome(newCursor):
            self.cursor = selectCursor(self.cursor, newCursor, true)
            self.markDirty()
            break

        # debugf"line {leafCell.parent.id}|{leafCell.id}: {leafCell.line}"
        self.cursor = selectCursor(self.cursor, self.nodeCellMap.toCursor(leafCell, true), true)
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
  # echo self.cursor

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
  let cell = cursor.cell
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

  if resolveCollection and subCell of CollectionCell and cursor.lastIndex >= 0 and cursor.lastIndex < subCell.CollectionCell.children.len:
    return subCell.CollectionCell.children[cursor.lastIndex].some

  return subCell.some

static:
  addTypeMap(ModelDocumentEditor, api.ModelDocumentEditor, getModelDocumentEditor)

proc scroll*(self: ModelDocumentEditor, amount: float32) {.expose("editor.model").} =
  self.scrollOffset += amount
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
        Ignored

  self.currentMode = mode

proc getCursorInLine*(self: ModelDocumentEditor, line: int, xPos: float): Option[CellCursor] =
  if line notin 0..self.logicalLines.high:
    return CellCursor.none

  let line = self.logicalLines[line]
  if line.len == 0:
    return CellCursor.none

  let charWidth = self.app.platform.charWidth

  # todo
  # var closest = 10000000000.0
  # for c in line:
  #   if not c.canSelect:
  #     continue
    # let widget = self.cellWidgetContext.cellToWidget.getOrDefault(c.id, nil)
    # if widget.isNil:
    #   continue

    # let xMin = if c.style.isNotNil and c.style.noSpaceLeft:
    #   widget.lastBounds.x + charWidth
    # else:
    #   widget.lastBounds.x

    # let xMax = if c.style.isNotNil and c.style.noSpaceRight:
    #   widget.lastBounds.xw - charWidth
    # else:
    #   widget.lastBounds.xw

    # if xPos < xMin:
    #   if result.isNone or xMin - xPos < closest:
    #     result = c.toCursor(true).some
    #     closest = xMin - xPos
    # elif xPos > xMax:
    #   if result.isNone or xPos - xMax < closest:
    #     result = c.toCursor(false).some
    #     closest = xPos - xMax
    # else:
    #   result = c.toCursor(true).some

    #   let text = c.currentText
    #   if text.len > 0:
    #     let alpha = (xPos - widget.lastBounds.x) / widget.lastBounds.w
    #     result.get.firstIndex = (alpha * text.len.float).round.int
    #     result.get.lastIndex = (alpha * text.len.float).round.int

    #   return

proc getCursorXPos*(self: ModelDocumentEditor, cursor: CellCursor): float =
  result = 0
  # todo
  # if getTargetCell(cursor).getSome(cell):
  #   let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id, nil)
  #   if widget.isNotNil:
  #     let text = cell.currentText
  #     if text.len == 0:
  #       result = widget.lastBounds.x
  #     else:
  #       let alpha = cursor.lastIndex.float / text.len.float
  #       result = widget.lastBounds.x * (1 - alpha) + widget.lastBounds.xw * alpha

proc getPreviousCellInLine*(self: ModelDocumentEditor, cell: Cell): Cell =
  # defer:
  #   debugf"getPreviousCellInLine {cell.dump} -> {result.dump}"

  if cell.line < 0 or cell.line > self.logicalLines.high:
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

  if cell.line < 0 or cell.line > self.logicalLines.high:
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

proc getPreviousLeaf*(cell: Cell, childIndex: Option[int] = int.none): Option[Cell] =
  if cell.parent.isNil and cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.getLastLeaf().some

  if cell.parent.isNil:
    return Cell.none

  let parent = cell.parent.CollectionCell

  var index = parent.indexOf(cell)

  if index > 0:
    return parent.children[index - 1].getLastLeaf().some
  else:
    var newParent: Cell = parent
    var parentIndex = newParent.index
    while parentIndex != -1 and parentIndex == 0:
      newParent = newParent.parent
      parentIndex = newParent.index

    if parentIndex > 0:
      return newParent.previousDirect().map(p => p.getLastLeaf())

    return cell.some

proc getNextLeaf*(cell: Cell, childIndex: Option[int] = int.none): Option[Cell] =
  if cell.parent.isNil and cell of CollectionCell and cell.CollectionCell.children.len > 0:
    return cell.getFirstLeaf().some

  if cell.parent.isNil:
    return Cell.none

  let parent = cell.parent.CollectionCell

  var index = parent.indexOf(cell)

  if index < parent.children.high:
    return parent.children[index + 1].getFirstLeaf().some
  else:
    var newParent: Cell = parent
    var parentIndex = newParent.index
    while parentIndex != -1 and parentIndex >= newParent.parentHigh:
      newParent = newParent.parent
      parentIndex = newParent.index

    if parentIndex < newParent.parentHigh:
      return newParent.nextDirect().map(p => p.getFirstLeaf())

    return cell.some

proc getPreviousLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Option[Cell] =
  var temp = cell
  while true:
    var c = temp.getPreviousLeaf()
    if c.isNone:
      return Cell.none
    if predicate(c.get):
      return c
    if c.get == temp:
      return Cell.none
    temp = c.get

proc getNextLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Option[Cell] =
  var temp = cell
  while true:
    var c = temp.getNextLeaf()
    if c.isNone:
      return Cell.none
    if predicate(c.get):
      return c
    if c.get == temp:
      return Cell.none
    temp = c.get

proc getNeighborLeafWhere*(cell: Cell, direction: Direction, predicate: proc(cell: Cell): (bool, Option[Cell])): Option[Cell] =
  var temp = cell
  while true:
    var c = if direction == Left: temp.getPreviousLeaf() else: temp.getNextLeaf()
    if c.isNone:
      return Cell.none
    let (done, res) = predicate(c.get)
    if done:
      return res
    if c.get == temp:
      return Cell.none
    temp = c.get

proc getNeighborLeafWhere*(cell: Cell, direction: Direction, predicate: proc(cell: Cell): bool): Option[Cell] =
  case direction
  of Left:
    return cell.getPreviousLeafWhere(isVisible)
  of Right:
    return cell.getNextLeafWhere(isVisible)

proc getSelfOrPreviousLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getPreviousLeafWhere(predicate)

proc getSelfOrNextLeafWhere*(cell: Cell, predicate: proc(cell: Cell): bool): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getNextLeafWhere(predicate)

proc getSelfOrNeighborLeafWhere*(cell: Cell, direction: Direction, predicate: proc(cell: Cell): (bool, Option[Cell])): Option[Cell] =
  if cell.isLeaf:
    let (stop, res) = predicate(cell)
    if stop:
      return res
  return cell.getNeighborLeafWhere(direction, predicate)

proc getSelfOrNeighborLeafWhere*(cell: Cell, direction: Direction, predicate: proc(cell: Cell): bool): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getNeighborLeafWhere(direction, predicate)

proc getPreviousSelectableLeaf*(cell: Cell): Option[Cell] =
  return cell.getPreviousLeafWhere(canSelect)

proc getNextSelectableLeaf*(cell: Cell): Option[Cell] =
  return cell.getNextLeafWhere(canSelect)

proc getNeighborSelectableLeaf*(cell: Cell, direction: Direction): Option[Cell] =
  return cell.getNeighborLeafWhere(direction, canSelect)

proc getPreviousVisibleLeaf*(cell: Cell): Option[Cell] =
  return cell.getPreviousLeafWhere(isVisible)

proc getNextVisibleLeaf*(cell: Cell): Option[Cell] =
  return cell.getNextLeafWhere(isVisible)

proc getNeighborVisibleLeaf*(cell: Cell, direction: Direction): Option[Cell] =
  return cell.getNeighborLeafWhere(direction, isVisible)

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
  result.column = clamp(column, cell.editableLow, cell.editableHigh)

proc toCursor*(map: NodeCellMap, cell: Cell, start: bool): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  if start:
    result.column = cell.editableLow
  else:
    result.column = cell.editableHigh

proc toCursor*(map: NodeCellMap, cell: Cell): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  result.firstIndex = 0
  result.lastIndex = cell.editableHigh(true)

proc toCursorBackwards*(map: NodeCellMap, cell: Cell): CellCursor =
  let (rootCell, path) = cell.nodeRootCellPath()
  result.map = map
  result.node = rootCell.node
  result.path = path
  result.lastIndex = 0
  result.firstIndex = cell.editableHigh(true)

proc selectParentCell*(cursor: CellCursor): CellCursor =
  result = cursor
  if result.path.len > 0:
    result.column = result.path[result.path.high]
    discard result.path.pop()
  elif result.cell.parent.isNotNil:
    return cursor.map.toCursor(result.cell.parent, result.cell.index)

proc selectParentNodeCell*(cursor: CellCursor): CellCursor =
  result = cursor
  while result.node == cursor.node and result.cell.parent.isNotNil:
    result = result.selectParentCell()

proc updateCursor*(self: ModelDocumentEditor, cursor: CellCursor): Option[CellCursor] =
  let nodeCell = self.nodeCellMap.cell(cursor.node)
  if nodeCell.isNil:
    return CellCursor.none

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

  res.path.setLen len
  res.firstIndex = clamp(res.firstIndex, 0, cell.editableHigh(true))
  res.lastIndex = clamp(res.lastIndex, 0, cell.editableHigh(true))

  return res.some

proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): Option[CellCursor] =
  result = CellCursor.none

  var nodeCell = self.nodeCellMap.cell(node)
  if nodeCell.isNil:
    return

  nodeCell = nodeCell.getFirstLeaf()

  proc editableDescendant(n: Cell): (bool, Option[Cell]) =
    if n.node == nodeCell.node or n.node.isDescendant(nodeCell.node):
      return (isVisible(n) and not n.disableEditing, n.some)
    else:
      return (true, Cell.none)

  if nodeCell.getSelfOrNeighborLeafWhere(Right, editableDescendant).getSome(targetCell):
    return self.nodeCellMap.toCursor(targetCell, true).some

  if nodeCell.getSelfOrNextLeafWhere((n) => isVisible(n) and not n.disableSelection).getSome(targetCell):
    return self.nodeCellMap.toCursor(targetCell, true).some

proc getFirstPropertyCellOfNode*(self: ModelDocumentEditor, node: AstNode, role: Id): Option[CellCursor] =
  result = CellCursor.none

  let nodeCell = self.nodeCellMap.cell(node)
  if nodeCell.isNil:
    return

  if nodeCell.getSelfOrNextLeafWhere((n) => isVisible(n) and not n.disableEditing and n of PropertyCell and n.PropertyCell.property == role).getSome(targetCell):
    return self.nodeCellMap.toCursor(targetCell, true).some

method getCursorLeft*(cell: ConstantCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex > cell.editableLow:
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getPreviousSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: NodeReferenceCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex > cell.editableLow:
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getPreviousSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: AliasCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex > cell.editableLow:
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getPreviousSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: PlaceholderCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex > cell.editableLow:
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getPreviousSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorLeft*(cell: PropertyCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex > cell.editableLow:
    dec result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getPreviousSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, false)

method getCursorRight*(cell: ConstantCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex < cell.editableHigh:
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getNextSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: NodeReferenceCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex < cell.editableHigh:
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getNextSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: AliasCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex < cell.editableHigh:
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getNextSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: PlaceholderCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex < cell.editableHigh:
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getNextSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorRight*(cell: PropertyCell, cursor: CellCursor): CellCursor =
  result = cursor
  if cursor.lastIndex < cell.editableHigh:
    inc result.lastIndex
    result.firstIndex = result.lastIndex
  else:
    if cell.getNextSelectableLeaf().getSome(c):
      result = cursor.map.toCursor(c, true)

method getCursorLeft*(cell: CollectionCell, cursor: CellCursor): CellCursor =
  result = cursor
  # if cell.children.len == 0 or cursor.lastIndex == 0:
  #   if cell.getPreviousSelectableLeaf().getSome(c):
  #     result = c.toCursor(true)
  #   return

  if cell.getPreviousSelectableLeaf().getSome(c):
    result = cursor.map.toCursor(c, true)
    return

  let childCell = cell.children[0]
  result.node = childCell.node
  result.path = if cell.node == childCell.node: cursor.path & 0 else: @[]
  result.column = 0

method getCursorRight*(cell: CollectionCell, cursor: CellCursor): CellCursor =
  # if cell.children.len == 0:
  #   return cursor

  if cell.getNextSelectableLeaf().getSome(c):
    result = cursor.map.toCursor(c, true)
    return

  let childCell = cell.children[cell.children.high]
  result.node = childCell.node
  result.path = if cell.node == childCell.node: cursor.path & cell.children.high else: @[]
  result.column = 0

proc combineCursors(a, b: CellCursor): CellCursor =
  # defer:
    # echo result

  if a.node == b.node:
    result.node = a.node
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

method handleDeleteLeft*(map: NodeCellMap, cell: Cell, slice: Slice[int]): Option[CellCursor] {.base.} = discard
method handleDeleteRight*(map: NodeCellMap, cell: Cell, slice: Slice[int]): Option[CellCursor] {.base.} = discard

proc handleDelete*(map: NodeCellMap, cell: Cell, slice: Slice[int], direction: Direction): Option[CellCursor] =
  case direction
  of Left:
    return map.handleDeleteLeft(cell, slice)
  of Right:
    return map.handleDeleteRight(cell, slice)

method handleDeleteLeft*(map: NodeCellMap, cell: PropertyCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteLeft*(map: NodeCellMap, cell: ConstantCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteLeft*(map: NodeCellMap, cell: PlaceholderCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteLeft*(map: NodeCellMap, cell: AliasCell, slice: Slice[int]): Option[CellCursor] =
  if cell.disableEditing or cell.currentText.len == 0 or slice == 0..0:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: max(0, slice.a - 1)..slice.b
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(map: NodeCellMap, cell: PropertyCell, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(map: NodeCellMap, cell: ConstantCell, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(map: NodeCellMap, cell: PlaceholderCell, slice: Slice[int]): Option[CellCursor] =
  let currentText = cell.currentText
  if cell.disableEditing or currentText.len == 0 or slice == currentText.len..currentText.len:
    return CellCursor.none
  let slice = if slice.a != slice.b: slice else: slice.a..min(slice.b + 1, currentText.len)
  let newIndex = cell.replaceText(slice, "")
  return map.toCursor(cell, newIndex).some

method handleDeleteRight*(map: NodeCellMap, cell: AliasCell, slice: Slice[int]): Option[CellCursor] =
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

proc moveCursorLeft*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    let newCursor = cell.getCursorLeft(self.cursor)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorRight*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    let newCursor = cell.getCursorRight(self.cursor)
    if newCursor.node.isNotNil:
      self.cursor = selectCursor(self.cursor, newCursor, select)
    # echo self.cursor

  self.markDirty()

proc moveCursorLeftLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
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
      newCursor = self.nodeCellMap.toCursor(nextCell, false)
      # echo newCursor
      self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorRightLine*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    var newCursor = cell.getCursorRight(self.cursor)
    # echo newCursor
    if newCursor.node == self.cursor.node:
      # echo "a"
      self.cursor = selectCursor(self.cursor, newCursor, select)
    else:
      # echo "b"
      let nextCell = self.getNextSelectableInLine(cell)
      # echo nextCell.dump
      newCursor = self.nodeCellMap.toCursor(nextCell, true)
      # echo newCursor
      self.cursor = selectCursor(self.cursor, newCursor, select)

  self.markDirty()

proc moveCursorLineStart*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.line >= 0 and cell.line <= self.logicalLines.high and self.logicalLines[cell.line].len > 0:
      let newCursor = self.nodeCellMap.toCursor(self.logicalLines[cell.line][0], true)
      self.cursor = selectCursor(self.cursor, newCursor, select)
  self.markDirty()

proc moveCursorLineEnd*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.line >= 0 and cell.line <= self.logicalLines.high and self.logicalLines[cell.line].len > 0:
      let newCursor = self.nodeCellMap.toCursor(self.logicalLines[cell.line][self.logicalLines[cell.line].high], false)
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

    let newCursor = self.nodeCellMap.toCursor(prevCell, true)
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

    let newCursor = self.nodeCellMap.toCursor(prevCell, false)
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
    if cell.getPreviousSelectableLeaf().getSome(c):
      self.cursor = selectCursor(self.cursor, self.nodeCellMap.toCursor(c, false), select)

  self.markDirty()

proc moveCursorRightCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor).getSome(cell):
    if cell.getNextSelectableLeaf().getSome(c):
      self.cursor = selectCursor(self.cursor, self.nodeCellMap.toCursor(c, true), select)

  self.markDirty()

proc selectNode*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.cursor.path.len == 0:
    if self.cursor.firstIndex == 0 and self.cursor.lastIndex == self.cursor.cell.high:
      if self.cursor.node.parent.isNotNil:
        self.cursor = CellCursor(map: self.nodeCellMap, node: self.cursor.node.parent, path: self.cursor.path, firstIndex: 0, lastIndex: self.cursor.cell.editableHigh)
    else:
      self.cursor = CellCursor(map: self.nodeCellMap, node: self.cursor.node, path: self.cursor.path, firstIndex: 0, lastIndex: self.cursor.cell.editableHigh)
  else:
    self.cursor = CellCursor(map: self.nodeCellMap, node: self.cursor.node, path: @[], firstIndex: 0, lastIndex: self.cursor.cell.editableHigh)

  self.markDirty()

proc selectParentCell*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.cursor = self.cursor.selectParentCell()
  self.markDirty()

proc shouldEdit*(cell: Cell): bool =
  if (cell of PlaceholderCell):
    return true
  let class = cell.node.nodeClass
  if class.isNotNil and (class.isAbstract or class.isInterface):
    return true
  return false

proc selectPrevPlaceholder*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.cursor.targetCell.getPreviousLeafWhere(proc(c: Cell): bool = isVisible(c) and shouldEdit(c)).getSome(candidate):
    if not shouldEdit(candidate):
      return

    self.cursor = self.nodeCellMap.toCursor(candidate, true)
    self.markDirty()

proc selectNextPlaceholder*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if self.cursor.targetCell.getNextLeafWhere(proc(c: Cell): bool = isVisible(c) and shouldEdit(c)).getSome(candidate):
    if not shouldEdit(candidate):
      return

    self.cursor = self.nodeCellMap.toCursor(candidate, true)
    self.markDirty()

proc delete*(self: ModelDocumentEditor, direction: Direction) =
  let cell = self.cursor.targetCell
  if cell of CollectionCell:

    let parent = cell.node.parent

    if cell.node.deleteOrReplaceWithDefault().getSome(newNode):
      self.rebuildCells()
      self.cursor = self.getFirstEditableCellOfNode(newNode).get
    else:
      self.rebuildCells()
      if self.getFirstEditableCellOfNode(parent).getSome(c):
        self.cursor = c

  else:
    let endIndex = if direction == Left: 0 else: cell.currentText.len

    var potentialCells: seq[(Cell, Slice[int], Direction)] = @[(cell, self.cursor.orderedRange, direction)]
    if self.cursor.lastIndex == endIndex and self.cursor.firstIndex == self.cursor.lastIndex and cell.getNeighborSelectableLeaf(direction).getSome(prev):
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

      if self.nodeCellMap.handleDelete(c, slice, direction).getSome(newCursor):
        self.cursor = newCursor

        if c.currentText.len == 0 and not c.dontReplaceWithDefault and c.parent.node != c.node:
          if c.node.replaceWithDefault().getSome(newNode):
            self.rebuildCells()
            self.cursor = self.getFirstEditableCellOfNode(newNode).get

        break

      if c.currentText.len == 0 and not c.dontReplaceWithDefault and c.parent.node != c.node and not c.node.isRequiredAndDefault():
        let parent = c.node.parent

        if c.node.deleteOrReplaceWithDefault().getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get
        else:
          let targetCell = c.getNeighborLeafWhere(cursorMoveDirection, proc(cell: Cell): (bool, Option[Cell]) =
            if cell.node != c.node and cell.node != parent and not cell.node.isDescendant(parent):
              return (true, Cell.none)
            if not isVisible(cell) or not canSelect(cell):
              return (false, Cell.none)
            if cell == c or cell.node == c.node or cell.node == parent:
              return (false, Cell.none)
            return (true, cell.some)
          )

          if targetCell.getSome(targetCell):
            let cursor = self.nodeCellMap.toCursor(targetCell, cursorMoveDirection == Right)
            self.rebuildCells()
            if self.updateCursor(cursor).getSome(newCursor):
              self.cursor = newCursor
              break

          let uiae = self.nodeCellMap.toCursor(c)

          var parentCellCursor = uiae.selectParentCell()
          assert parentCellCursor.node == c.node.parent

          self.rebuildCells()
          if self.updateCursor(parentCellCursor).flatMap((c: CellCursor) -> Option[Cell] => c.getTargetCell(true)).getSome(newCell):
            if i == 0 and direction == Left and newCell.getNeighborSelectableLeaf(direction).getSome(c):
              self.cursor = self.nodeCellMap.toCursor(c)
            elif newCell.getSelfOrNeighborLeafWhere(direction, (c) -> bool => isVisible(c)).getSome(c):
              self.cursor = self.nodeCellMap.toCursor(c, true)
            else:
              self.cursor = self.nodeCellMap.toCursor(newCell, true)
          else:
            self.cursor = self.getFirstEditableCellOfNode(parent).get
        break

      if slice.a == slice.b and slice.a == endIndex:
        continue

      if c.disableEditing:
        if c.deleteImmediately or (slice.a == 0 and slice.b == c.currentText.len):

          if c.deleteNeighbor:
            let neighbor = if direction == Left: c.previousDirect() else: c.nextDirect()
            if neighbor.getSome(neighbor):
              let parent = neighbor.node.parent

              let selectionTarget = c.getNeighborSelectableLeaf(-direction)

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
            self.cursor = self.nodeCellMap.toCursorBackwards(c)
          of Right:
            self.cursor = self.nodeCellMap.toCursor(c)
        break

proc deleteLeft*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()
  self.delete(Left)
  self.markDirty()

proc deleteRight*(self: ModelDocumentEditor) {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()
  self.delete(Right)
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

  if (not ok or candidate.isNone) and not originalNode.canHaveSiblings():
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

  if self.cursor.firstIndex != self.cursor.lastIndex:
    return

  echo "createNewNode"

  if self.createNewNodeAt(self.cursor).getSome(newNode):
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(newNode).get
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
      self.mSelection.last.column = newColumn
      self.mSelection.first = self.mSelection.last

      if self.unfilteredCompletions.len == 0:
        self.updateCompletions()
      else:
        self.refilterCompletions()

      if not self.showCompletions and self.completionsLen == 1 and (self.getCompletion(0).alwaysApply or self.getCompletion(0).name == cell.currentText):
        self.applySelectedCompletion()

      self.markDirty()
      return true
  return false

proc getCursorForOp(self: ModelDocumentEditor, op: ModelOperation): CellCursor =
  result = self.cursor
  case op.kind
  of Delete:
    return self.getFirstEditableCellOfNode(op.node).get(self.cursor)
  of Insert:
    return self.getFirstEditableCellOfNode(op.parent).get(self.cursor)
  of PropertyChange:
    if self.getFirstPropertyCellOfNode(op.node, op.role).getSome(c):
      result = c
      result.firstIndex = op.slice.a
      result.lastIndex = op.slice.b
  of ReferenceChange:
    return self.getFirstEditableCellOfNode(op.node).get(self.cursor)
  of Replace:
    discard

proc undo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.undo().getSome(t):
    self.rebuildCells()
    if self.transactionCursors.contains(t[0]):
      self.selection = self.transactionCursors[t[0]]
    else:
      self.cursor = self.getCursorForOp(t[1])
    self.markDirty()

proc redo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.redo().getSome(t):
    self.rebuildCells()
    if self.transactionCursors.contains(t[0]):
      self.selection = self.transactionCursors[t[0]]
    else:
      self.cursor = self.getCursorForOp(t[1])
    self.markDirty()

proc toggleUseDefaultCellBuilder*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.useDefaultCellBuilder = not self.useDefaultCellBuilder
  self.rebuildCells()
  self.markDirty()

proc showCompletions*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.showCompletions:
    self.mSelection.last.column = 0
    self.mSelection.first = self.mSelection.last
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

    self.showCompletions = false

  var c = self.cursor
  c.column = c.targetCell.editableHigh
  self.cursor = c

  self.markDirty()

proc findContainingFunction(node: AstNode): Option[AstNode] =
  if node.class == IdFunctionDefinition:
    return node.some
  if node.parent.isNotNil:
    return node.parent.findContainingFunction()
  return AstNode.none

import scripting/wasm

proc runSelectedFunctionAsync*(self: ModelDocumentEditor): Future[void] {.async.} =
  let function = self.cursor.node.findContainingFunction()
  if function.isNone:
    log(lvlInfo, fmt"Not inside function")
    return

  if function.get.childCount(IdFunctionDefinitionParameters) > 0:
    log(lvlInfo, fmt"Can't call function with parameters")
    return

  let parent = function.get.parent
  let name = if parent.isNotNil and parent.class == IdConstDecl:
    parent.property(IdINamedName).get.stringValue
  else:
    "<anonymous>"

  log(lvlInfo, fmt"Running function {name}")

  let timer = startTimer()
  defer:
    log(lvlInfo, fmt"Running function took {timer.elapsed.ms} ms")

  var compiler = newBaseLanguageWasmCompiler()
  let binary = compiler.compileToBinary(function.get)
  if self.document.workspace.getSome(workspace):
    discard workspace.saveFile("jstest.wasm", binary.toArrayBuffer)

  proc test(a: int32) =
    echo "test ", a

  var imp = WasmImports(namespace: "env")
  imp.addFunction("test", test)

  let module = await newWasmModule(binary.toArrayBuffer, @[imp])
  if module.isNone:
    echo "Failed to load module"
    return

  if module.get.findFunction("test", int32, proc(): int32).getSome(f):
    echo "call test"
    let r = f()
    echo "Result: ", r

  if module.get.findFunction("test", void, proc(): void).getSome(f):
    echo "call test"
    f()

proc runSelectedFunction*(self: ModelDocumentEditor) {.expose("editor.model").} =
  asyncCheck runSelectedFunctionAsync(self)

genDispatcher("editor.model")

proc handleAction(self: ModelDocumentEditor, action: string, arg: string): EventResponse =
  # log lvlInfo, fmt"[modeleditor]: Handle action {action}, '{arg}'"
  # defer:
  #   log lvlDebug, &"line: {self.cursor.targetCell.line}, cursor: {self.cursor},\ncell: {self.cursor.cell.dump()}\ntargetCell: {self.cursor.targetCell.dump()}"

  self.mCursorBeforeTransaction = self.selection

  var args = newJArray()
  args.add api.ModelDocumentEditor(id: self.id).toJson
  for a in newStringStream(arg).parseJsonFragments():
    args.add a

  # var newLastCommand = (action, arg)
  # defer: self.lastCommand = newLastCommand

  if self.app.handleUnknownDocumentEditorAction(self, action, args) == Handled:
    return Handled

  try:
    if dispatch(action, args).isSome:
      return Handled
  except CatchableError:
    log lvlError, fmt"Failed to dispatch action '{action} {args}': {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()

  return Ignored

method getStateJson*(self: ModelDocumentEditor): JsonNode =
  return %*{
    "cursor": %*{
      "firstIndex": self.cursor.firstIndex,
      "lastIndex": self.cursor.lastIndex,
      "path": self.cursor.path,
      "nodeId": self.cursor.node.id.Id.toJson,
    }
  }

method restoreStateJson*(self: ModelDocumentEditor, state: JsonNode) =
  if state.kind != JObject:
    return
  if state.hasKey("cursor"):
    let cursorState = state["cursor"]
    echo cursorState.pretty
    let firstIndex = cursorState["firstIndex"].jsonTo int
    let lastIndex = cursorState["lastIndex"].jsonTo int
    let path = cursorState["path"].jsonTo seq[int]
    let nodeId = cursorState["nodeId"].jsonTo(Id).NodeId
    self.targetCursor = CellCursorState(firstIndex: firstIndex, lastIndex: lastIndex, path: path, node: nodeId)