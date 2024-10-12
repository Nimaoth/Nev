import std/[strformat, strutils, sugar, tables, options, json, streams, algorithm, sets, sequtils, os]
import fusion/matching, bumpy, vmath
import misc/[util, custom_logger, timer, array_buffer, id, event, custom_async, myjsonutils, custom_unicode, delayed_task, rect_utils]
from scripting_api as api import nil
import platform/[filesystem, platform]
import workspaces/[workspace]
import ui/node
import lang/[lang_language, lang_builder, cell_language, property_validator_language, scope_language]
import finder/[finder]

import ast/[generator_wasm, base_language_wasm, editor_language_wasm, model_state]
import document, document_editor, text/text_document, events, scripting/expose, input
import config_provider, app_interface, dispatch_tables, selector_popup
import model, base_language, editor_language, cells, ast_ids, project

{.push gcsafe.}
{.push raises: [].}

logCategory "model"

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

proc toCellCursorState(cursor: CellCursor): CellCursorState =
  return CellCursorState(index: cursor.index, path: cursor.path, node: cursor.node.id)

proc toCellSelectionState(selection: CellSelection): (CellCursorState, CellCursorState) =
  return (selection.first.toCellCursorState, selection.last.toCellCursorState)

proc toSelection*(cursor: CellCursor): CellSelection = (cursor, cursor)

proc isEmpty*(selection: CellSelection): bool = selection.first == selection.last

proc `$`*(cursor: CellCursor): string = fmt"CellCursor({cursor.index}, {cursor.path}, {cursor.node})"

proc `$`*(selection: CellSelection): string = fmt"({selection.first}, {selection.last})"

proc isValid*(cursor: CellCursor): bool = cursor.map.isNotNil and cursor.node.isNotNil
proc isValid*(selection: CellSelection): bool = selection.first.isValid and selection.last.isValid

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
    role: RoleId          # The role where a node was inserted/deleted
    value: PropertyValue  # The new/old text of a property
    id: NodeId            # The new/old id of a reference
    slice: Slice[int]     # The range of text that changed

  ModelTransaction* = object
    id: Id
    operations*: seq[ModelOperation]

  ModelDocument* = ref object of Document
    model*: Model
    projectService*: AstProjectService
    project*: Project
    ctx*: ModelComputationContext

    currentTransaction: ModelTransaction
    undoList: seq[ModelTransaction]
    redoList: seq[ModelTransaction]

    onModelChanged*: Event[ModelDocument]
    onFinishedUndoTransaction*: Event[(ModelDocument, ModelTransaction)]
    onFinishedRedoTransaction*: Event[(ModelDocument, ModelTransaction)]
    onBuilderChanged*: Event[void]

    builder*: CellBuilder

  ModelCompletionKind* {.pure.} = enum
    SubstituteClass
    SubstituteReference
    ChangeReference

  ModelCompletion* = object
    parent*: AstNode
    role*: RoleId
    index*: int
    class*: NodeClass
    name*: string
    alwaysApply*: bool # If true then this completion will always be applied when it's the only one, even if the current completion text doesn't match exactly

    case kind*: ModelCompletionKind
    of SubstituteClass:
      property: Option[RoleId] # Property to set on new node from completion text
    of SubstituteReference:
      referenceRole*: RoleId
      referenceTarget*: AstNode
    of ChangeReference:
      changeReferenceTarget*: AstNode

  ModelDocumentEditor* = ref object of DocumentEditor
    app*: AppInterface
    configProvider*: ConfigProvider
    document*: ModelDocument

    projectService*: AstProjectService

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
    detailsNodeCellMap*: NodeCellMap
    logicalLines*: seq[seq[Cell]]
    cellWidgetContext*: UpdateContext
    mCursorBeforeTransaction: CellSelection
    mSelection: CellSelection
    lastTargetCell: Cell
    mTargetCursor: Option[CellCursorState]
    selectionHistory: seq[(CellCursorState, CellCursorState)]

    cursorVisible*: bool = true
    blinkCursor: bool = false
    blinkCursorTask: DelayedTask

    validateNodesTask: DelayedTask

    scrollOffset*: float
    previousBaseIndex*: seq[int]

    lastBounds*: Rect

    showCompletions*: bool
    completionText: string
    hasCompletions*: bool
    filteredCompletions*: seq[ModelCompletion]
    unfilteredCompletions*: HashSet[ModelCompletion]
    selectedCompletion*: int
    completionsBaseIndex*: int
    completionsScrollOffset*: float
    scrollToCompletion*: Option[int]

  UpdateContext* = ref object
    nodeCellMap*: NodeCellMap
    cellToWidget*: Table[CellId, UINode]
    targetNodeOld*: UINode
    targetNode*: UINode
    targetCell*: Cell
    scrolledNode*: UINode
    targetCellPosition*: Vec2
    selection*: CellSelection
    handleClick*: proc(node: UINode, cell: Cell, path: seq[int], cursor: CellCursor, drag: bool) {.gcsafe, raises: [].}
    setCursor*: proc(cell: Cell, offset: int, drag: bool) {.gcsafe, raises: [].}
    selectionColor*: Color
    errorColor*: Color
    isThickCursor*: bool
    ctx*: ModelComputationContext

proc `==`*(a, b: ModelCompletion): bool =
  if a.parent != b.parent: return false
  if a.role != b.role: return false
  if a.index != b.index: return false
  if a.class != b.class: return false
  if a.name != b.name: return false
  if a.alwaysApply != b.alwaysApply: return false
  if a.kind != b.kind: return false
  case a.kind
  of SubstituteClass:
    if a.property != b.property: return false
  of SubstituteReference:
    if a.referenceRole != b.referenceRole: return false
    if a.referenceTarget != b.referenceTarget: return false
  of ChangeReference:
    if a.changeReferenceTarget != b.changeReferenceTarget: return false
  return true

proc `$`(op: ModelOperation): string =
  result = fmt"{op.kind}, '{op.value}'"
  if op.id.isSome: result.add fmt", id = {op.id}"
  if op.node != nil: result.add fmt", node = {op.node}"
  if op.parent != nil: result.add fmt", parent = {op.parent}, index = {op.idx}"

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
proc showCompletionWindow*(self: ModelDocumentEditor)

proc toCursor*(map: NodeCellMap, cell: Cell, column: int): CellCursor
proc toCursor*(map: NodeCellMap, cell: Cell, start: bool): CellCursor
proc getFirstEditableCellOfNode*(self: ModelDocumentEditor, node: AstNode): Option[CellCursor]
proc getPreviousLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell]
proc getParentInfo*(selection: CellSelection): tuple[cell: Cell, left: seq[int], right: seq[int]]

proc handleNodeDeleted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: RoleId, index: int)
proc handleNodeInserted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: RoleId, index: int)
proc handleNodePropertyChanged(self: ModelDocument, model: Model, node: AstNode, role: RoleId, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int])
proc handleNodeReferenceChanged(self: ModelDocument, model: Model, node: AstNode, role: RoleId, oldRef: NodeId, newRef: NodeId)

method `$`*(document: ModelDocument): string =
  return document.filename

proc newModelDocument*(filename: string = "", app: bool = false, workspaceFolder: Option[Workspace]): ModelDocument =
  new(result)
  let self = result

  log lvlInfo, fmt"newModelDocument {filename}"

  self.filename = filename
  self.appFile = app
  self.workspace = workspaceFolder

  self.builder = newCellBuilder(idNone().LanguageId)

method save*(self: ModelDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  log lvlInfo, fmt"Saving model source file '{self.filename}'"
  let serialized = $self.model.toJson

  if self.workspace.getSome(ws):
    asyncSpawn ws.saveFile(self.filename, serialized)
  elif self.appFile:
    self.fs.saveApplicationFile(self.filename, serialized)
  else:
    self.fs.saveFile(self.filename, serialized)

template cursor*(self: ModelDocumentEditor): CellCursor = self.mSelection.last
template selection*(self: ModelDocumentEditor): CellSelection = self.mSelection

proc requestEditorForModel(self: ModelDocumentEditor, model: Model): Option[ModelDocumentEditor] =
  let editor: Option[DocumentEditor] = self.app.openWorkspaceFile(model.path)
  if editor.getSome(editor) and editor of ModelDocumentEditor:
    return editor.ModelDocumentEditor.some
  return ModelDocumentEditor.none

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

proc retriggerValidation*(self: ModelDocumentEditor) =
  if self.validateNodesTask.isNil:
    self.validateNodesTask = startDelayed(500, repeat=false):
      measureBlock "validateNodes":
        for cell in self.nodeCellMap.cells.values:
          try:
            discard self.document.ctx.validateNode(cell.node)
          except Exception:
            discard
      self.markDirty()
  else:
    self.validateNodesTask.reschedule()

proc updateScrollOffset*(self: ModelDocumentEditor, scrollToCursor: bool = true) =
  if self.cellWidgetContext.isNil or self.scrolledNode.isNil or self.scrolledNode.parent.isNil:
    return

  let newCell = self.selection.last.targetCell
  if self.scrolledNode.isNil:
    return

  if newCell.isNotNil and self.cellWidgetContext.cellToWidget.contains(newCell.id):
    let newUINode = self.cellWidgetContext.cellToWidget[newCell.id]
    if newUINode.isDescendant(self.scrolledNode.parent):
      let newY = newUINode.transformBounds(self.scrolledNode.parent).y

      let buffer = 5.0
      if newY < buffer * self.app.platform.builder.textHeight:
        self.targetCellPath = newCell.rootPath.path
        self.scrollOffset = buffer * self.app.platform.builder.textHeight
      elif newY > self.scrolledNode.parent.h - buffer * self.app.platform.builder.textHeight:
        self.targetCellPath = newCell.rootPath.path
        self.scrollOffset = self.scrolledNode.parent.h - buffer * self.app.platform.builder.textHeight
    else:
      self.targetCellPath = self.selection.last.targetCell.rootPath.path
      self.scrollOffset = self.scrolledNode.parent.h / 2

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

  self.retriggerValidation()

  self.markDirty()

proc updateScrollOffsetToPrevCell(self: ModelDocumentEditor): bool =
  # debugf"updateScrollOffsetToPrevCell {self.selection}"
  if self.cellWidgetContext.isNil:
    return false
  if self.scrolledNode.isNil:
    return false

  let cursor = self.selection.normalized.first
  let sourceCell = cursor.targetCell
  # echo fmt"source {sourceCell}"

  var lastLeafOnScreen = Cell.none
  discard sourceCell.getPreviousLeafWhere(self.nodeCellMap, proc(cell: Cell): bool =
    if not self.cellWidgetContext.cellToWidget.contains(cell.id):
      return true

    if cell.node == sourceCell.node or cell.node == sourceCell.node.parent:
      return true

    lastLeafOnScreen = cell.some
    return false
  )

  let prevLeaf = lastLeafOnScreen

  if prevLeaf.isNone:
    # debugf"no previous leaf"
    return false

  let newCell = prevLeaf.get
  if not self.cellWidgetContext.cellToWidget.contains(newCell.id):
    # debugf"new cell not found / visible"
    return false

  # let oldY = self.cellWidgetContext.targetNode.transformBounds(self.scrolledNode.parent).y

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

  if self.mSelection == selection:
    return

  let hasValidSelection = self.mSelection.first.node.isNotNil and self.mSelection.last.node.isNotNil
  if hasValidSelection:
    self.selectionHistory.add (self.mSelection.first.toCellCursorState, self.mSelection.last.toCellCursorState)

  if hasValidSelection and self.lastTargetCell != selection.last.targetCell:
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

proc `selection=`*(self: ModelDocumentEditor, selection: (CellCursorState, CellCursorState)) =
  if self.document.model.resolveReference(selection[0].node).getSome(first) and self.document.model.resolveReference(selection[1].node).getSome(last):
    self.selection = (
      CellCursor(map: self.nodeCellMap, index: selection[0].index, path: selection[0].path, node: first),
      CellCursor(map: self.nodeCellMap, index: selection[1].index, path: selection[1].path, node: last))

proc updateSelection*(self: ModelDocumentEditor, cursor: CellCursor, extend: bool) =
  if extend:
    self.selection = (self.selection.first, cursor)
  else:
    self.selection = (cursor, cursor)

  # debugf"updateSelection to {self.selection}"

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursor) =
  self.selection = (cursor, cursor)

proc `cursor=`*(self: ModelDocumentEditor, cursor: CellCursorState) =
  if self.document.model.rootNodes.len == 0:
    return
  if self.document.model.resolveReference(cursor.node).getSome(node):
    self.cursor = CellCursor(map: self.nodeCellMap, index: cursor.index, path: cursor.path, node: node)
  else:
    self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get

proc `targetCursor=`*(self: ModelDocumentEditor, cursor: CellCursorState) =
  self.mTargetCursor = cursor.some
  if self.document.model.isNotNil and self.document.model.rootNodes.len > 0:
    self.cursor = cursor

proc handleNodeDeleted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: RoleId, index: int) =
  # debugf "handleNodeDeleted {parent}, {child}, {role}, {index}"
  self.currentTransaction.operations.add ModelOperation(kind: Delete, parent: parent, node: child, idx: index, role: role)
  self.ctx.state.deleteNode(child, recurse=true)

proc handleNodeInserted(self: ModelDocument, model: Model, parent: AstNode, child: AstNode, role: RoleId, index: int) =
  # debugf "handleNodeInserted {parent}, {child}, {role}, {index}"
  self.currentTransaction.operations.add ModelOperation(kind: Insert, parent: parent, node: child, idx: index, role: role)
  self.ctx.state.insertNode(child)

proc handleNodePropertyChanged(self: ModelDocument, model: Model, node: AstNode, role: RoleId, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  # debugf "handleNodePropertyChanged {node}, {role}, {oldValue}, {newValue}"
  self.currentTransaction.operations.add ModelOperation(kind: PropertyChange, node: node, role: role, value: oldValue, slice: slice)
  self.ctx.state.updateNode(node)

proc handleNodeReferenceChanged(self: ModelDocument, model: Model, node: AstNode, role: RoleId, oldRef: NodeId, newRef: NodeId) =
  # debugf "handleNodeReferenceChanged {node}, {role}, {oldRef}, {newRef}"
  self.currentTransaction.operations.add ModelOperation(kind: ReferenceChange, node: node, role: role, id: oldRef)
  self.ctx.state.updateNode(node)

proc loadAsync*(self: ModelDocument): Future[void] {.async.} =
  while self.project.isNil:
    await sleepAsync(10.milliseconds)

  self.ctx = self.project.computationContext.ModelComputationContext

  log lvlInfo, fmt"Loading model source file '{self.filename}'"
  try:
    if self.workspace.isNone:
      log lvlError, fmt"Can only open model files from workspaces right now"
      return

    if self.projectService.loadModelAsync(self.filename).await.getSome(model):
      self.model = model

      discard self.model.onNodeDeleted.subscribe proc(d: auto) = self.handleNodeDeleted(d[0], d[1], d[2], d[3], d[4])
      discard self.model.onNodeInserted.subscribe proc(d: auto) = self.handleNodeInserted(d[0], d[1], d[2], d[3], d[4])
      discard self.model.onNodePropertyChanged.subscribe proc(d: auto) = self.handleNodePropertyChanged(d[0], d[1], d[2], d[3], d[4], d[5])
      discard self.model.onNodeReferenceChanged.subscribe proc(d: auto) = self.handleNodeReferenceChanged(d[0], d[1], d[2], d[3], d[4])

      self.builder.clear()
      for language in self.model.languages:
        self.builder.addBuilder(self.projectService.builders.getBuilder(language.id))

      # self.project.builder = self.builder

      self.undoList.setLen 0
      self.redoList.setLen 0

      {.gcsafe.}:
        functionInstances.clear()
        structInstances.clear()
      self.ctx.state.clearCache()

  except CatchableError:
    log lvlError, fmt"Failed to load model source file '{self.filename}': {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()

  if self.model.isNotNil:
    self.onModelChanged.invoke (self)

method load*(self: ModelDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    log lvlError, &"save: Missing filename"
    return

  self.filename = filename
  asyncSpawn self.loadAsync()

proc getSubstitutionTarget(cell: Cell): (AstNode, RoleId, int) =
  ## Returns the parent cell, role, and index where to insert/replace a substitution
  if cell of PlaceholderCell:
    return (cell.node, cell.PlaceholderCell.role, 0)
  return (cell.node.parent, cell.node.role, cell.node.index)

proc getSubstitutionsForClass(self: ModelDocumentEditor, targetCell: Cell, class: NodeClass, addCompletion: proc(c: ModelCompletion): void {.gcsafe, raises: [].}): bool =
  # if it's a reference and there is only one reference role, then we can substitute the reference using the scope
  if class.substitutionReference.getSome(referenceRole):
    # debugf"getSubstitutionsForClass {class.name}"
    let desc = class.nodeReferenceDescription(referenceRole).get
    let language = self.document.model.getLanguageForClass(desc.class)
    if language.isNil:
      log lvlError, fmt"getSubstitutionsForClass: Failed to resolve language for class '{desc.class}'"
      return false

    let refClass = language.resolveClass(desc.class)
    if refClass.isNil:
      log lvlError, fmt"getSubstitutionsForClass: Failed to resolve class '{desc.class}'"
      return false

    let (parent, role, index) = targetCell.getSubstitutionTarget()

    # debugf"getScope {parent}, {targetCell.node}"
    let scope = self.document.ctx.getScope(targetCell.node).catch:
      log lvlError, &"Failed to get scope for {targetCell.node}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return false

    for decl in scope:
      # debugf"scope: {decl}, {decl.nodeClass.isSubclassOf(refClass.id)}"
      if decl.nodeClass.isSubclassOf(refClass.id):
        let name = if decl.property(IdINamedName).getSome(name): name.stringValue else: $decl.id
        addCompletion ModelCompletion(kind: ModelCompletionKind.SubstituteReference, name: name, class: class, parent: parent, role: role, index: index, referenceRole: desc.id, referenceTarget: decl)
        result = true

  if class.substitutionProperty.getSome(propertyRole):
    let (parent, role, index) = targetCell.getSubstitutionTarget()
    # debugf"substitutionProperty {propertyRole} for {class.name}"
    addCompletion ModelCompletion(kind: ModelCompletionKind.SubstituteClass, name: class.alias, class: class, parent: parent, role: role, index: index, alwaysApply: true, property: propertyRole.some)
    result = true

proc updateCompletions(self: ModelDocumentEditor) =
  self.unfilteredCompletions.clear()
  # debugf"updateCompletions"

  let targetCell = self.cursor.targetCell
  if targetCell of CollectionCell or targetCell of PropertyCell:
    self.refilterCompletions()
    return

  let (parent, role, index) = targetCell.getSubstitutionTarget()
  if parent.isNil:
    return

  let node = self.cursor.node

  let model = node.model
  let parentClass = parent.nodeClass
  if parentClass.nodeChildDescription(role).getSome(childDesc): # add class substitutions
    let slotClass = model.resolveClass(childDesc.class)
    if slotClass.isNil:
      log lvlError, fmt"updateCompletions: Failed to resolve class '{childDesc.class}'"
      return

    debugf"updateCompletions child {parent}, {node}, {node.model.isNotNil}, {slotClass.name}"

    model.forEachChildClass slotClass, proc(childClass: NodeClass) =
      if self.getSubstitutionsForClass(targetCell, childClass, (c) -> void => self.unfilteredCompletions.incl(c)):
        return

      if childClass.isAbstract or childClass.isInterface:
        return

      let name = if childClass.alias.len > 0: childClass.alias else: childClass.name
      self.unfilteredCompletions.incl ModelCompletion(kind: ModelCompletionKind.SubstituteClass, name: name, class: childClass, parent: parent, role: role, index: index)
  elif parentClass.nodeReferenceDescription(role).getSome(desc):
    let slotClass = model.resolveClass(desc.class)
    if slotClass.isNil:
      log lvlError, fmt"updateCompletions: Failed to resolve class '{desc.class}'"
      return

    debugf"updateCompletions ref {parent}, {node}, {node.model.isNotNil}, {slotClass.name}"
    let scope = self.document.ctx.getScope(node).catch:
      log lvlError, &"Failed to get scope for {node}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return

    for decl in scope:
      # debugf"scope: {decl}, {decl.nodeClass.name}, {decl.nodeClass.isSubclassOf(slotClass.id)}"
      if decl.nodeClass.isSubclassOf(slotClass.id):
        let name = if decl.property(IdINamedName).getSome(name): name.stringValue else: $decl.id
        self.unfilteredCompletions.incl ModelCompletion(kind: ModelCompletionKind.ChangeReference, name: name, class: slotClass, parent: node, role: role, index: index, changeReferenceTarget: decl)

  self.refilterCompletions()
  self.markDirty()

proc refilterCompletions(self: ModelDocumentEditor) =
  self.filteredCompletions.setLen 0

  let targetCell = self.cursor.targetCell
  if targetCell of CollectionCell:
    return

  let text = targetCell.currentText
  let index = self.cursor.index
  # debugf "refilter '{text}' {index}"
  let prefix = text[0..<index]

  # debugf "refilter '{text}' {index} -> '{prefix}'"

  for completion in self.unfilteredCompletions:
    if completion.kind == ModelCompletionKind.SubstituteClass and completion.property.getSome(role):
      let language = self.document.model.getLanguageForClass(completion.class.id)
      if language.isValidPropertyValue(completion.class, role, prefix):
        self.filteredCompletions.add completion
        continue

    if completion.name.toLower.startsWith(prefix.toLower):
      self.filteredCompletions.add completion
      continue

  self.hasCompletions = true

  self.filteredCompletions.sort(proc(a, b: ModelCompletion): int =
    if a.name.len < b.name.len:
      return -1
    if a.name.len > b.name.len:
      return 1
    return cmp(a.name, b.name))

  if self.filteredCompletions.len > 0:
    self.selectedCompletion = self.selectedCompletion.clamp(0, self.filteredCompletions.len - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some

proc invalidateCompletions(self: ModelDocumentEditor) =
  self.unfilteredCompletions.clear()
  self.filteredCompletions.setLen 0
  self.hasCompletions = false

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

proc handleNodeDeleted(self: ModelDocumentEditor, model: Model, parent: AstNode, child: AstNode, role: RoleId, index: int) =
  # debugf "handleNodeDeleted {parent}, {child}, {role}, {index}"
  self.invalidateCompletions()
  self.retriggerValidation()

proc handleNodeInserted(self: ModelDocumentEditor, model: Model, parent: AstNode, child: AstNode, role: RoleId, index: int) =
  # debugf "handleNodeInserted {parent}, {child}, {role}, {index}"
  self.invalidateCompletions()
  self.retriggerValidation()

proc handleNodePropertyChanged(self: ModelDocumentEditor, model: Model, node: AstNode, role: RoleId, oldValue: PropertyValue, newValue: PropertyValue, slice: Slice[int]) =
  # debugf "handleNodePropertyChanged {node}, {role}, {oldValue}, {newValue}"
  self.invalidateCompletions()
  self.retriggerValidation()
  self.markDirty()

proc handleNodeReferenceChanged(self: ModelDocumentEditor, model: Model, node: AstNode, role: RoleId, oldRef: NodeId, newRef: NodeId) =
  # debugf "handleNodeReferenceChanged {node}, {role}, {oldRef}, {newRef}"
  self.invalidateCompletions()
  self.retriggerValidation()

proc handleBuilderChanged(self: ModelDocumentEditor) =
  self.rebuildCells()
  self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get
  self.updateScrollOffset()
  self.markDirty()

proc handleModelChanged(self: ModelDocumentEditor, document: ModelDocument) =
  discard self.document.model.onNodeDeleted.subscribe proc(d: auto) = self.handleNodeDeleted(d[0], d[1], d[2], d[3], d[4])
  discard self.document.model.onNodeInserted.subscribe proc(d: auto) = self.handleNodeInserted(d[0], d[1], d[2], d[3], d[4])
  discard self.document.model.onNodePropertyChanged.subscribe proc(d: auto) = self.handleNodePropertyChanged(d[0], d[1], d[2], d[3], d[4], d[5])
  discard self.document.model.onNodeReferenceChanged.subscribe proc(d: auto) = self.handleNodeReferenceChanged(d[0], d[1], d[2], d[3], d[4])

  self.mSelection.first = CellCursor.default
  self.mSelection.last = CellCursor.default
  self.mSelection.first.map = self.nodeCellMap
  self.mSelection.last.map = self.nodeCellMap

  self.rebuildCells()

  if self.document.model.rootNodes.len > 0:
    self.mSelection.first.node = self.document.model.rootNodes[0]
    self.mSelection.last.node = self.document.model.rootNodes[0]

    if self.mTargetCursor.getSome(c):
      self.cursor = c
      assert self.cursor.map == self.nodeCellMap
    else:
      self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes[0]).get

    self.updateScrollOffset(true)
  else:
    self.mSelection.first = CellCursor.default
    self.mSelection.last = CellCursor.default
    self.mSelection.first.map = self.nodeCellMap
    self.mSelection.last.map = self.nodeCellMap

  self.mCursorBeforeTransaction = self.selection

  self.retriggerValidation()

  self.markDirty()

proc handleFinishedUndoTransaction*(self: ModelDocumentEditor, document: ModelDocument, transaction: ModelTransaction) =
  self.transactionCursors[transaction.id] = self.mCursorBeforeTransaction
  self.mCursorBeforeTransaction = self.selection

proc handleFinishedRedoTransaction*(self: ModelDocumentEditor, document: ModelDocument, transaction: ModelTransaction) =
  self.transactionCursors[transaction.id] = self.mCursorBeforeTransaction
  self.mCursorBeforeTransaction = self.selection

method getNamespace*(self: ModelDocumentEditor): string = "editor.model"

method handleDocumentChanged*(self: ModelDocumentEditor) =
  log lvlInfo, fmt"Document changed"
  # self.selectionHistory.clear
  # self.selectionFuture.clear
  # self.finishEdit false
  # for symbol in ctx.globalScope.values:
  #   discard ctx.newSymbol(symbol)
  # self.node = self.document.rootNode[0]
  self.nodeCellMap.builder = self.document.builder
  self.detailsNodeCellMap.builder = self.document.builder
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

proc buildNodeCellMap(self: Cell, map: var Table[NodeId, Cell]) =
  if self.node.isNotNil and not map.contains(self.node.id):
    map[self.node.id] = self
  if self of CollectionCell:
    for c in self.CollectionCell.children:
      c.buildNodeCellMap(map)

proc rebuildCells(self: ModelDocumentEditor) =
  # debugf"rebuildCells"
  self.nodeCellMap.invalidate()
  self.detailsNodeCellMap.invalidate()
  self.logicalLines.setLen 0

proc toJson*(self: api.ModelDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.model")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.ModelDocumentEditor, jsonNode: JsonNode) {.raises: [ValueError].} =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc handleInput(self: ModelDocumentEditor, input: string): EventResponse =
  # log lvlInfo, fmt"[modeleditor]: Handle input '{input}'"

  self.mCursorBeforeTransaction = self.selection

  if self.app.invokeCallback(self.getContextWithMode("editor.model.input-handler"), input.newJString):
    self.document.finishTransaction()
    self.markDirty()
    return Handled

  if self.insertTextAtCursor(input):
    self.document.finishTransaction()
    self.markDirty()
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
  self.retriggerValidation()
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

method getEventHandlers*(self: ModelDocumentEditor, inject: Table[string, EventHandler]): seq[EventHandler] =
  result.add self.eventHandler

  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler

  if self.showCompletions:
    result.add self.completionEventHandler

method getDocument*(self: ModelDocumentEditor): Document = self.document

method createWithDocument*(_: ModelDocumentEditor, document: Document, configProvider: ConfigProvider): DocumentEditor =
  let self = ModelDocumentEditor(eventHandler: nil, document: ModelDocument(document))
  self.configProvider = configProvider
  self.unfilteredCompletions = initHashSet[ModelCompletion]()

  self.cursorsId = newId()
  self.completionsId = newId()
  self.nodeCellMap.new
  self.nodeCellMap.builder = self.document.builder
  self.detailsNodeCellMap.new
  self.detailsNodeCellMap.builder = self.document.builder
  self.mSelection.first.map = self.nodeCellMap
  self.mSelection.last.map = self.nodeCellMap

  self.init()
  discard self.document.onModelChanged.subscribe proc(d: auto) = self.handleModelChanged(d)
  discard self.document.onFinishedUndoTransaction.subscribe proc(d: auto) = self.handleFinishedUndoTransaction(d[0], d[1])
  discard self.document.onFinishedRedoTransaction.subscribe proc(d: auto) = self.handleFinishedRedoTransaction(d[0], d[1])
  discard self.document.onBuilderChanged.subscribe proc() = self.handleBuilderChanged()

  self.rebuildCells()
  self.startBlinkCursorTask()

  return self

proc waitForProjectService(self: ModelDocumentEditor) {.async: (raises: []).} =
  if self.app.getServices().getServiceAsync(AstProjectService).await.getSome(s):
    self.projectService = s
    self.document.projectService = s
    self.document.project = s.project
    if self.document.filename.len > 0:
      self.document.load()
  else:
    log lvlError, &"Failed to get AstProjectService"

method injectDependencies*(self: ModelDocumentEditor, app: AppInterface, fs: Filesystem) =
  self.app = app
  self.app.registerEditor(self)
  self.fs = fs

  asyncSpawn self.waitForProjectService()

  self.eventHandler = eventHandler(app.getEventHandlerConfig("editor.model")):
    onAction:
      if self.handleAction(action, arg).isSome:
        Handled
      else:
        Ignored
    onInput:
      self.handleInput input

  self.completionEventHandler = eventHandler(app.getEventHandlerConfig("editor.model.completion")):
    onAction:
      if self.handleAction(action, arg).isSome:
        Handled
      else:
        Ignored
    onInput:
      self.handleInput input

method unregister*(self: ModelDocumentEditor) =
  self.app.unregisterEditor(self)

proc getModelDocumentEditor(wrapper: api.ModelDocumentEditor): Option[ModelDocumentEditor] =
  {.gcsafe.}:
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
  self.retriggerValidation()
  self.markDirty()

proc scrollLines*(self: ModelDocumentEditor, lines: float32) {.expose("editor.model").} =
  self.scrollOffset += self.app.platform.builder.textHeight * lines.float
  self.retriggerValidation()
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
        if self.handleAction(action, arg).isSome:
          Handled
        else:
          Ignored
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

proc getCellInLine*(builder: UINodeBuilder, uiRoot: UINode, target: Vec2, direction: int, isThickCursor: bool): Option[tuple[cell: Cell, offset: int]] =
  ## Searches for the next cell in a line base way.
  ## direction:
  ##   If direction is 0 then only the same line as the input cell is searched.
  ##   If direction is -1 then the previous lines will be searched.
  ##   If direction is +1 then the next lines will be searched.
  ## targetX: return the cell closest to this X location

  # debugf"getCellInLine {target}, {direction}, {isThickCursor}"

  let maxYDiff = builder.lineHeight / 2
  let buffer = 2.0

  var offset = 0
  while true:
    offset = offset + direction
    let gap = builder.lineGap
    let searchRect = rect(uiRoot.lx, target.y + offset.float * builder.lineHeight + gap, uiRoot.lw, builder.lineHeight - gap * 2)

    # debugf"gap: {gap}, searchRect: {searchRect}, lineHeight: {builder.lineHeight}, offset: {offset}"
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
        # debugf"update selectedCell: {xDiff}, {currentCell}"
        xDiffMin = xDiff
        selectedNode = uiNode
        selectedCell = currentCell
    )

    if selectedCell.isNotNil:
      # debugf"selectedCell: {selectedCell}"
      let offset = getCursorOffset(builder, selectedCell, target.x - selectedNode.lx, isThickCursor)
      return (selectedCell, offset).some

    # debugf"no selectedCell"
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
  return getCellInLine(self.app.platform.builder, self.cellWidgetContext.scrolledNode, vec2(targetX, cellUINode.ly), direction, false)

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

proc getPreviousInLineWhere*(self: ModelDocumentEditor, cell: Cell, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Cell =
  result = self.getPreviousCellInLine(cell)
  while not predicate(result):
    let oldResult = result
    result = self.getPreviousCellInLine(result)
    if result == oldResult:
      break

proc getNextInLineWhere*(self: ModelDocumentEditor, cell: Cell, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Cell =
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

proc getPreviousLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell] =
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

proc getNextLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell] =
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

proc getNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): (bool, Option[Cell]) {.gcsafe, raises: [].}): Option[Cell] =
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

proc getNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell] =
  case direction
  of Left:
    return cell.getPreviousLeafWhere(map, predicate)
  of Right:
    return cell.getNextLeafWhere(map, predicate)

proc getSelfOrPreviousLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getPreviousLeafWhere(map, predicate)

proc getSelfOrNextLeafWhere*(cell: Cell, map: NodeCellMap, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell] =
  if cell.isLeaf and predicate(cell):
    return cell.some
  return cell.getNextLeafWhere(map, predicate)

proc getSelfOrNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): (bool, Option[Cell]) {.gcsafe, raises: [].}): Option[Cell] =
  if cell.isLeaf:
    let (stop, res) = predicate(cell)
    if stop:
      return res
  return cell.getNeighborLeafWhere(map, direction, predicate)

proc getSelfOrNeighborLeafWhere*(cell: Cell, map: NodeCellMap, direction: Direction, predicate: proc(cell: Cell): bool {.gcsafe, raises: [].}): Option[Cell] =
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

  while result.cell.parent.isNotNil and result.cell.parent.node == node:
    let index = result.cell.parent.CollectionCell.indexOf(result.cell)
    result.path.insert index, 0
    result.cell = result.cell.parent

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
    log lvlError, fmt"nodeCell is nil"
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

  log lvlError, fmt"no editable cell found"

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

proc getFirstPropertyCellOfNode*(self: ModelDocumentEditor, node: AstNode, role: RoleId): Option[CellCursor] =
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

proc gotoDefinition*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    if cell.node.references.len == 0:
      return

    if cell.node.references.len == 1:
      if cell.node.model.resolveReference(cell.node.references[0].node).getSome(target):
        if target.model == self.document.model:
          self.cursor = self.getFirstEditableCellOfNode(target).get
          self.updateScrollOffset()
        else:
          if self.requestEditorForModel(target.model).getSome(editor):
            editor.cursor = editor.getFirstEditableCellOfNode(target).get
            editor.updateScrollOffset(true)
            editor.markDirty()
            self.app.tryActivateEditor(editor)

  self.markDirty()

proc gotoNeighborReference*(self: ModelDocumentEditor, direction: Direction) =
  if getTargetCell(self.cursor, false).getSome(cell):
    let originalNode = cell.node
    let targetId = if cell.node.references.len == 1:
      cell.node.references[0].node
    else:
      cell.node.id

    var nextCell = getNeighborLeafWhere(cell, self.nodeCellMap, direction, proc(cell: Cell): bool =
        if cell.node == originalNode or cell.node.references.len == 0:
          return false
        for i in 0..cell.node.references.high:
          if cell.node.references[i].node == targetId:
            return true
        return false
      )

    if nextCell.isNone: # wrap around
      let endCell = if direction == Left: cell.rootPath.root.getLastLeaf(self.nodeCellMap) else: cell.rootPath.root.getFirstLeaf(self.nodeCellMap)
      nextCell = getNeighborLeafWhere(endCell, self.nodeCellMap, direction, proc(cell: Cell): bool =
          if cell.node.references.len == 0:
            return false
          for i in 0..cell.node.references.high:
            if cell.node.references[i].node == targetId:
              return true
          return false
        )

    if nextCell.getSome(c):
      self.cursor = self.getFirstEditableCellOfNode(c.node).get
      self.updateScrollOffset()
      self.markDirty()

proc gotoPrevReference*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.gotoNeighborReference(Left)

proc gotoNextReference*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.gotoNeighborReference(Right)

proc gotoInvalidNode*(self: ModelDocumentEditor, direction: Direction) =
  if getTargetCell(self.cursor, false).getSome(cell):
    let originalNode = cell.node

    var nextCell = getNeighborLeafWhere(cell, self.nodeCellMap, direction, proc(c: Cell): bool =
        if c == cell or c.node == originalNode or not isVisible(cell):
          return false
        try:
          discard self.document.ctx.validateNode(c.node)
          if self.document.ctx.getDiagnostics(c.node.id).len > 0:
            return true
        except Exception:
          discard
        return false
      )

    if nextCell.isNone: # wrap around
      let endCell = if direction == Left: cell.rootPath.root.getLastLeaf(self.nodeCellMap) else: cell.rootPath.root.getFirstLeaf(self.nodeCellMap)
      nextCell = getNeighborLeafWhere(endCell, self.nodeCellMap, direction, proc(c: Cell): bool =
          if not isVisible(cell):
            return false
          if c == cell:
            return true
          try:
            discard self.document.ctx.validateNode(c.node)
            if self.document.ctx.getDiagnostics(c.node.id).len > 0:
              return true
          except Exception:
            discard
          return false
        )

    if nextCell.getSome(c):
      self.cursor = self.nodeCellMap.toCursor(c, true)
      # self.cursor = self.getFirstEditableCellOfNode(c.node).get
      self.updateScrollOffset()
      self.markDirty()

proc gotoPrevInvalidNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.gotoInvalidNode(Left)

proc gotoNextInvalidNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.gotoInvalidNode(Right)

proc gotoPrevNodeOfClass*(self: ModelDocumentEditor, className: string, select: bool = false) {.expose("editor.model").} =
  log lvlInfo, fmt"gotoPrevNodeOfClass {className}"
  if getTargetCell(self.cursor, false).getSome(cell):
    let startNode = cell.node

    proc predicate(cell: Cell): bool =
      # debugf"prev cell {cell}"
      if cell.node == startNode:
        return false
      let class = cell.node.nodeClass
      if class.isNil:
        return false
      return class.name == className

    if cell.getPreviousLeafWhere(self.nodeCellMap, predicate).getSome(c):
      let node = c.node
      if select:
        discard
      elif self.getFirstSelectableCellOfNode(node).getSome(cursor):
        self.cursor = cursor
      else:
        self.cursor = self.nodeCellMap.toCursor(c, true)
      self.updateScrollOffset(true)

  self.markDirty()

proc gotoNextNodeOfClass*(self: ModelDocumentEditor, className: string, select: bool = false) {.expose("editor.model").} =
  log lvlInfo, fmt"gotoNextNodeOfClass {className}"
  if getTargetCell(self.cursor, false).getSome(cell):
    let startNode = cell.node

    proc predicate(cell: Cell): bool =
      if cell.node == startNode:
        return false
      let class = cell.node.nodeClass
      if class.isNil:
        return false
      # debugf"next cell {cell}, {class.name} == {className}"
      return class.name == className

    if cell.getNextLeafWhere(self.nodeCellMap, predicate).getSome(c):
      let node = c.node
      if select:
        discard
      elif self.getFirstSelectableCellOfNode(node).getSome(cursor):
        self.cursor = cursor
      else:
        self.cursor = self.nodeCellMap.toCursor(c, true)
      self.updateScrollOffset(true)

  self.markDirty()

proc toggleBoolCell*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  if getTargetCell(self.cursor, false).getSome(cell):
    if cell of PropertyCell:
      let prop = cell.PropertyCell.property

      if cell.targetNode.property(prop).getSome(value) and value.kind == PropertyType.Bool:
        cell.targetNode.setProperty(prop, PropertyValue(kind: PropertyType.Bool, boolValue: not value.boolValue))

  self.markDirty()

proc invertSelection*(self: ModelDocumentEditor) {.expose("editor.model").} =
  swap(self.selection.first, self.selection.last)
  self.markDirty()

proc selectPrev*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.selectionHistory.len == 0:
    return

  let oldSelection = self.selection
  self.selection = self.selectionHistory.pop()
  discard self.selectionHistory.pop() # remove latest selection
  self.selectionHistory.insert(oldSelection.toCellSelectionState, 0)
  self.updateScrollOffset(true)

  self.markDirty()

proc selectNext*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.selectionHistory.len == 0:
    return

  let oldSelection = self.selection
  self.selection = self.selectionHistory[0]
  self.selectionHistory.delete 0
  discard self.selectionHistory.pop() # remove latest selection
  self.selectionHistory.add oldSelection.toCellSelectionState
  self.updateScrollOffset(true)

  self.markDirty()

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

proc selectPrevNeighbor*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  discard

proc selectNextNeighbor*(self: ModelDocumentEditor, select: bool = false) {.expose("editor.model").} =
  discard

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
  return (parentCell, firstPath.path[childIndex..^1], lastPath.path[childIndex..^1])

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

  let (parentTargetCell, firstChildPath, lastChildPath) = selection.getParentInfo
  if parentTargetCell.isNil:
    return

  let parentBaseCell = parentTargetCell.nodeRootCell      # the root cell for the given node

  let firstIndex = if firstChildPath.len > 0: firstChildPath[0] else: 0
  let lastIndex = if lastChildPath.len > 0: lastChildPath[0] else: parentTargetCell.high

  # debugf"common parent {firstIndex}..{lastIndex}, {parentBaseCell}, {parentTargetCell}, {parentBaseCell == parentTargetCell}"

  # let firstCell = parentCell.getSelfOrNextLeafWhere(proc(cell: Cell): bool = cell.canSelect())
  # let lastCell = parentCell.getSelfOrPreviousLeafWhere(proc(cell: Cell): bool = cell.canSelect())

  if parentTargetCell of CollectionCell:
    let parentCell = parentTargetCell.CollectionCell
    let firstContained = selection.contains(parentCell.children[firstIndex])
    let lastContained = selection.contains(parentCell.children[lastIndex])

    # debug firstContained, ", ", lastContained, ", ", parentCell.high
    if firstContained and lastContained:
      if firstIndex == parentCell.visibleLow and lastIndex == parentCell.visibleHigh and parentTargetCell == parentBaseCell: # entire parent selected
        # debugf"all cells selected"

        var targetNode = parentCell.node

        if parentCell.parent.isNotNil and DeleteWhenEmpty in parentCell.parent.flags and parentCell.parent.len == 1: # Selected only child of parent:
          targetNode = parentCell.parent.node

        if replace and targetNode.replaceWithDefault().getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get
        elif not replace and targetNode.deleteOrReplaceWithDefault().getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get
        elif targetNode.parent.isNotNil:
          let targetParentNode = targetNode.parent
          self.rebuildCells()
          if self.getFirstEditableCellOfNode(targetParentNode).getSome(c):
            self.cursor = c
        else:
          log lvlError, fmt"Failed to delete node {targetNode}"
          return

      else: # some children of parent cell selected
        var nodesToDelete: seq[AstNode]
        for c in parentCell.children[firstIndex..lastIndex]:
          if c.node != parentCell.node:
            nodesToDelete.add c.node

        # debug "some children of parent cell selected ", nodesToDelete

        var targetSelectedNode: AstNode = nil
        for i, n in nodesToDelete:
          if i == 0 and replace:
            if n.replaceWithDefault().getSome(n) and targetSelectedNode.isNil:
              targetSelectedNode = n
          else:
            if n.deleteOrReplaceWithDefault().getSome(n) and targetSelectedNode.isNil:
              targetSelectedNode = n

        self.rebuildCells()

        if targetSelectedNode.isNotNil:
          self.cursor = self.getFirstEditableCellOfNode(targetSelectedNode).get
        else:
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
      elif not replace and parentTargetCell.node.deleteOrReplaceWithDefault().getSome(newNode):
        self.rebuildCells()
        self.cursor = self.getFirstEditableCellOfNode(newNode).get
      else:
        self.rebuildCells()
        if self.getFirstEditableCellOfNode(parentTargetCell.node.parent).getSome(c):
          self.cursor = c

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

proc insertIntoNode*(self: ModelDocumentEditor, parent: AstNode, role: RoleId, index: int): Option[AstNode] =
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
    # if c.node.selfDescription().getSome(desc):
      # debugf"{desc.role}, {desc.count}, {c.node.index}, {c.dump}, {c.node}"

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
      # if c.node.selfDescription().getSome(desc):
      #   debugf"{desc.role}, {desc.count}, {c.node.index}, {c.dump}, {c.node}"
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

  if self.showCompletions and self.hasCompletions:
    self.applySelectedCompletion()
    self.markDirty()
    return

  if self.document.model.rootNodes.len == 0:
    var class: NodeClass
    for language in self.document.model.languages:
      if language.rootNodeClasses.len > 0:
        class = language.rootNodeClasses[0]
        break

    if class.isNil:
      log lvlError, "No root node classes found"
      return

    self.document.model.addRootNode newAstNode(class)
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes.last).get

  else:
    if not self.selection.isEmpty:
      let (parentCell, _, _) = self.selection.getParentInfo
      if parentCell.node.canHaveSiblings():
        if self.insertAfterNode(parentCell.node).getSome(newNode):
          self.rebuildCells()
          self.cursor = self.getFirstEditableCellOfNode(newNode).get

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

type
  NodeTransformationKind* = enum Wrap
  NodeTransformation* = object
    selectNextPlaceholder*: bool
    selectPrevPlaceholder*: bool
    case kind*: NodeTransformationKind
    of Wrap:
      wrapClass*: ClassId
      wrapRole*: RoleId
      wrapCursorTargetRole*: RoleId
      wrapChildIndex*: int

  NodeClassTransformations* = Table[ClassId, Table[string, NodeTransformation]]

proc findTransformation(self: NodeClassTransformations, class: NodeClass, input: string): Option[NodeTransformation] =
  var class = class
  while class.isNotNil:
    if self.contains(class.id):
      if self[class.id].contains(input):
        return self[class.id][input].some
    class = class.base

proc applyTransformation(self: ModelDocumentEditor, node: AstNode, transformation: NodeTransformation): CellCursor =
  case transformation.kind
  of Wrap:
    debugf"applyTransformation wrap {transformation.wrapRole}, {transformation.wrapChildIndex}"

    let class = node.model.resolveClass(transformation.wrapClass)

    var newNode = newAstNode(class)
    node.replaceWith(newNode)
    newNode.insert(transformation.wrapRole, transformation.wrapChildIndex, node)

    self.rebuildCells()

    if transformation.wrapCursorTargetRole.isSome:
      if self.nodeCellMap.cell(newNode).getFirstLeaf(self.nodeCellMap).getSelfOrNextLeafWhere(self.nodeCellMap, proc(c: Cell): bool =
          isVisible(c) and c.role == transformation.wrapCursorTargetRole
        ).getSome(candidate):
        return self.nodeCellMap.toCursor(candidate, true)

    if transformation.selectNextPlaceholder and self.cursor.targetCell.getNextLeafWhere(self.nodeCellMap, proc(c: Cell): bool = isVisible(c) and shouldEdit(c)).getSome(candidate):
      return self.nodeCellMap.toCursor(candidate, true)

    if transformation.selectPrevPlaceholder and self.cursor.targetCell.getPreviousLeafWhere(self.nodeCellMap, proc(c: Cell): bool = isVisible(c) and shouldEdit(c)).getSome(candidate):
      return self.nodeCellMap.toCursor(candidate, true)

    return self.cursor

proc insertTextAtCursor*(self: ModelDocumentEditor, input: string): bool {.expose("editor.model").} =
  defer:
    self.document.finishTransaction()

  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

  # todo: get these transformations from the language itself
  # let selectionTransformations = toTable {
  #   IdExpression: {
  #     "+": NodeTransformation(kind: Wrap, wrapClass: IdAdd, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "-": NodeTransformation(kind: Wrap, wrapClass: IdSub, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "*": NodeTransformation(kind: Wrap, wrapClass: IdMul, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "/": NodeTransformation(kind: Wrap, wrapClass: IdDiv, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "%": NodeTransformation(kind: Wrap, wrapClass: IdMod, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "=": NodeTransformation(kind: Wrap, wrapClass: IdAssignment, wrapRole: IdAssignmentTarget, wrapCursorTargetRole: IdAssignmentValue, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     ".": NodeTransformation(kind: Wrap, wrapClass: IdStructMemberAccess, wrapRole: IdStructMemberAccessValue, wrapCursorTargetRole: IdStructMemberAccessMember, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "(": NodeTransformation(kind: Wrap, wrapClass: IdCall, wrapRole: IdCallFunction, wrapCursorTargetRole: IdCallArguments, selectNextPlaceholder: true, wrapChildIndex: 0),
  #     "[": NodeTransformation(kind: Wrap, wrapClass: IdArrayAccess, wrapRole: IdArrayAccessValue, wrapCursorTargetRole: IdArrayAccessIndex, selectNextPlaceholder: true, wrapChildIndex: 0),
  #   }.toTable
  # }

  let postfixTransformations = toTable {
    IdExpression: {
      "+": NodeTransformation(kind: Wrap, wrapClass: IdAdd, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
      "-": NodeTransformation(kind: Wrap, wrapClass: IdSub, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
      "*": NodeTransformation(kind: Wrap, wrapClass: IdMul, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
      "/": NodeTransformation(kind: Wrap, wrapClass: IdDiv, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
      "%": NodeTransformation(kind: Wrap, wrapClass: IdMod, wrapRole: IdBinaryExpressionLeft, wrapCursorTargetRole: IdBinaryExpressionRight, selectNextPlaceholder: true, wrapChildIndex: 0),
      "=": NodeTransformation(kind: Wrap, wrapClass: IdAssignment, wrapRole: IdAssignmentTarget, wrapCursorTargetRole: IdAssignmentValue, selectNextPlaceholder: true, wrapChildIndex: 0),
      ".": NodeTransformation(kind: Wrap, wrapClass: IdStructMemberAccess, wrapRole: IdStructMemberAccessValue, wrapCursorTargetRole: IdStructMemberAccessMember, selectNextPlaceholder: true, wrapChildIndex: 0),
      "(": NodeTransformation(kind: Wrap, wrapClass: IdCall, wrapRole: IdCallFunction, wrapCursorTargetRole: IdCallArguments, selectNextPlaceholder: true, wrapChildIndex: 0),
      "[": NodeTransformation(kind: Wrap, wrapClass: IdArrayAccess, wrapRole: IdArrayAccessValue, wrapCursorTargetRole: IdArrayAccessIndex, selectNextPlaceholder: true, wrapChildIndex: 0),
    }.toTable
  }

  let prefixTransformations = toTable {
    IdExpression: {
      "+": NodeTransformation(kind: Wrap, wrapClass: IdAdd, wrapRole: IdBinaryExpressionRight, wrapCursorTargetRole: IdBinaryExpressionLeft, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "-": NodeTransformation(kind: Wrap, wrapClass: IdSub, wrapRole: IdBinaryExpressionRight, wrapCursorTargetRole: IdBinaryExpressionLeft, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "*": NodeTransformation(kind: Wrap, wrapClass: IdMul, wrapRole: IdBinaryExpressionRight, wrapCursorTargetRole: IdBinaryExpressionLeft, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "/": NodeTransformation(kind: Wrap, wrapClass: IdDiv, wrapRole: IdBinaryExpressionRight, wrapCursorTargetRole: IdBinaryExpressionLeft, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "%": NodeTransformation(kind: Wrap, wrapClass: IdMod, wrapRole: IdBinaryExpressionRight, wrapCursorTargetRole: IdBinaryExpressionLeft, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "=": NodeTransformation(kind: Wrap, wrapClass: IdAssignment, wrapRole: IdAssignmentValue, wrapCursorTargetRole: IdAssignmentTarget, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "(": NodeTransformation(kind: Wrap, wrapClass: IdCall, wrapRole: IdCallArguments, wrapCursorTargetRole: IdCallFunction, selectPrevPlaceholder: true, wrapChildIndex: 0),
      "[": NodeTransformation(kind: Wrap, wrapClass: IdArrayAccess, wrapRole: IdArrayAccessIndex, wrapCursorTargetRole: IdArrayAccessValue, selectPrevPlaceholder: true, wrapChildIndex: 0),
    }.toTable
  }

  # var typePostfixTransformations = initTable[(ClassId, string), NodeTransformation]()
  # typePostfixTransformations[(IdString, ".ptr")] = NodeTransformation(kind: Wrap, wrapClass: IdStringGetPointer, wrapRole: IdStringGetPointerValue, wrapCursorTargetRole: IdStringGetPointerValue, selectNextPlaceholder: true, wrapChildIndex: 0)
  # typePostfixTransformations[(IdString, ".len")] = NodeTransformation(kind: Wrap, wrapClass: IdStringGetLength, wrapRole: IdStringGetLengthValue, wrapCursorTargetRole: IdStringGetLengthValue, selectNextPlaceholder: true, wrapChildIndex: 0)

  if not self.selection.isEmpty and not self.showCompletions:
    let (parentCell, _, _) = self.selection.getParentInfo
    if self.selection.first < self.selection.last:
      if postfixTransformations.findTransformation(parentCell.node.nodeClass, input).getSome(transformation):
        self.cursor = self.applyTransformation(parentCell.node, transformation)
        return true
    else:
      if prefixTransformations.findTransformation(parentCell.node.nodeClass, input).getSome(transformation):
        self.cursor = self.applyTransformation(parentCell.node, transformation)
        return true

  if getTargetCell(self.cursor).getSome(cell):
    if self.selection.isEmpty and not self.showCompletions:
      if self.cursor.isAtEndOfLastCellOfNode and postfixTransformations.findTransformation(cell.node.nodeClass, input).getSome(transformation):
        self.cursor = self.applyTransformation(cell.node, transformation)
        return true

      elif self.cursor.isAtBeginningOfFirstCellOfNode and prefixTransformations.findTransformation(cell.node.nodeClass, input).getSome(transformation):
        self.cursor = self.applyTransformation(cell.node, transformation)
        return true

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

      if self.completionsLen == 1 and (self.getCompletion(0).alwaysApply or self.getCompletion(0).name == cell.currentText):
        self.applySelectedCompletion()
      # elif self.completionsLen > 0 and self.getCompletion(self.selectedCompletion).name == cell.currentText:
      #   self.applySelectedCompletion()
      elif self.completionsLen > 0 and not self.showCompletions:
        self.showCompletionWindow()

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
  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

  if self.document.undo().getSome(t):
    self.rebuildCells()
    if self.transactionCursors.contains(t[0]):
      self.selection = self.transactionCursors[t[0]]
    else:
      self.selection = self.getCursorForOp(t[1])
    self.updateScrollOffset(false)
    self.markDirty()

proc redo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

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

proc showCompletionWindow*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.showCompletions:
    var newCursor = self.selection.last
    newCursor.index = 0
    self.cursor = newCursor
  self.updateCompletions()
  self.showCompletions = true
  self.markDirty()

proc hideCompletions*(self: ModelDocumentEditor) {.expose("editor.model").} =
  self.unfilteredCompletions.clear()
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

proc printSelectionInfo*(self: ModelDocumentEditor) {.expose("editor.model").} =
  try:
    let typ = self.document.ctx.computeType(self.selection.last.node)
    let value = self.document.ctx.getValue(self.selection.last.node)
    log lvlInfo, &"selected:\n  type: {`$`(typ, true)}\n  value: {`$`(value, true)}"
  except CatchableError:
    log lvlError, &"Failet to get type and value of selected: {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()

proc clearModelCache*(self: ModelDocumentEditor) {.expose("editor.model").} =
  log lvlInfo, fmt"Clearing model cache"
  self.document.ctx.state.clearCache()
  for node in self.document.model.tempNodes:
    log lvlInfo, fmt"Deleting temporary node from model: {node}"
    node.forEach2 n:
      n.model.nodes.del n.id
      n.model = nil
  self.document.model.tempNodes.setLen 0

  {.gcsafe.}:
    functionInstances.clear()
    structInstances.clear()

  # for rootNode in self.document.model.rootNodes:
  #   self.document.ctx.state.insertNode(rootNode)

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

var lineBuffer {.global.} = ""

proc printI32(a: int32) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printU32(a: uint32) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printI64(a: int64) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printU64(a: uint64) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printF32(a: float32) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printF64(a: float64) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printChar(a: int32) =
  {.gcsafe.}:
    lineBuffer.add $a.Rune

proc printString(a: cstring, len: int32) =
  {.gcsafe.}:
    let str = $a
    assert len <= a.len
    lineBuffer.add str[0..<len]

proc printLine() =
  {.gcsafe.}:
    let l = lineBuffer
    lineBuffer = ""
    log lvlInfo, l

proc loadAppFile(a: cstring): cstring =
  {.gcsafe.}:
    let file = fs.loadApplicationFile($a)
    # log lvlInfo, fmt"loadAppFile {a} -> {file}"
    return file.cstring

proc runSelectedFunctionAsync*(self: ModelDocumentEditor): Future[void] {.async.} =
  let timer = startTimer()
  defer:
    log(lvlInfo, fmt"runSelectedFunctionAsync took {timer.elapsed.ms} ms")

  let function = self.cursor.node.findContainingFunction()
  if function.isNone:
    log(lvlError, fmt"Not inside function")
    return

  block: # todo
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
    var compiler = newBaseLanguageWasmCompiler(self.projectService.repository, self.document.ctx)
    compiler.addBaseLanguage()
    compiler.addEditorLanguage()
    compiler.addFunctionToCompile(function.get)
    let binary = compiler.compileToBinary()

  if self.document.workspace.getSome(workspace):
    discard workspace.saveFile("jstest.wasm", binary.toArrayBuffer)

  var imp = WasmImports(namespace: "env")
  imp.addFunction("print_i32", printI32)
  imp.addFunction("print_u32", printU32)
  imp.addFunction("print_i64", printI64)
  imp.addFunction("print_u64", printU64)
  imp.addFunction("print_f32", printF32)
  imp.addFunction("print_f64", printF64)
  imp.addFunction("print_char", printChar)
  imp.addFunction("print_string", printString)
  imp.addFunction("print_line", printLine)
  imp.addFunction("intToString", intToString)
  imp.addFunction("loadAppFile", loadAppFile)

  measureBlock fmt"Create wasm module for '{name}'":
    let module = await newWasmModule(binary.toArrayBuffer, @[imp])
    if module.isNone:
      log lvlError, fmt"Failed to create wasm module from generated binary for {name}: {getCurrentExceptionMsg()}"
      return

  if module.get.findFunction($function.get.id, void, proc(): void {.gcsafe, raises: [CatchableError].}).getSome(f):
    measureBlock fmt"Run '{name}'":
      try:
        f()
      except Exception as e:
        log lvlError, &"Failed to run function {function.get.id}: {e.msg}\n{e.getStackTrace()}"

  else:
    log lvlError, fmt"Failed to find function {function.get.id} in wasm module"

proc runSelectedFunction*(self: ModelDocumentEditor) {.expose("editor.model").} =
  asyncSpawn runSelectedFunctionAsync(self)

proc copyNodeAsync*(self: ModelDocumentEditor): Future[void] {.async.} =
  let selection = self.selection.normalized
  let (parentTargetCell, firstPath, lastPath) = selection.getParentInfo
  let parentBaseCell = parentTargetCell.nodeRootCell      # the root cell for the given node
  let firstIndex = if firstPath.len > 0: firstPath[0] else: 0
  let lastIndex = if lastPath.len > 0: lastPath[0] else: parentTargetCell.len
  # debugf"copyNode {firstPath} {lastPath} {parentTargetCell}"

  var json: JsonNode = nil

  if parentTargetCell of CollectionCell:
    let parentCell = parentTargetCell.CollectionCell
    let firstContained = selection.contains(parentCell.children[firstIndex])
    let lastContained = selection.contains(parentCell.children[lastIndex])

    # debug firstContained, ", ", lastContained, ", ", parentCell.high
    if firstContained and lastContained:
      if firstIndex == parentCell.visibleLow and lastIndex == parentCell.visibleHigh and parentTargetCell == parentBaseCell: # entire parent selected
        json = parentCell.node.toJson

      else: # some children of parent selected
        json = newJArray()
        for c in parentCell.children[firstIndex..lastIndex]:
          if c.node != parentCell.node:
            json.add c.node.toJson

    else: # not fully contained
      discard # todo

  else: # not collection cell
    json = parentTargetCell.node.toJson

  if json.isNotNil:
    self.app.setRegisterTextAsync($json, "").await

proc copyNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  asyncSpawn self.copyNodeAsync()

proc getNodeFromRegister(self: ModelDocumentEditor, register: string): Future[seq[AstNode]] {.async.} =
  let text = self.app.getRegisterTextAsync(register).await
  let json = text.parseJson
  var res = newSeq[AstNode]()

  if json.kind == JObject:
    if json.jsonToAstNode(self.document.model).getSome(node):
      res.add node
  elif json.kind == JArray:
    for j in json:
      if j.jsonToAstNode(self.document.model).getSome(node):
        res.add node
  else:
    log lvlError, fmt"Can't parse node from register"

  return res

proc pasteNodeAsync*(self: ModelDocumentEditor): Future[void] {.async.} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  let updatedScrollOffset = self.updateScrollOffsetToPrevCell()
  defer:
    if not updatedScrollOffset:
      self.updateScrollOffset()

  defer:
    self.document.finishTransaction()

  let nodes = self.getNodeFromRegister("").await
  if nodes.len == 0:
    log lvlError, fmt"Can't parse node from register"
    return

  let (parent, role, index) = if self.selection.isEmpty:
    let targetCell = self.cursor.targetCell
    let (parent, role, index) = targetCell.getSubstitutionTarget
    if targetCell.node != parent:
      targetCell.node.removeFromParent()
    # debugf"empty: targetCell: {targetCell} || {parent} || {role} || {index}"
    (parent, role, index)
  else:
    let (parentCell, _, _) = self.selection.getParentInfo
    let nodeToRemove = parentCell.node
    let parent = nodeToRemove.parent
    # debugf"replace {parentCell} ||| {parent} ||| {nodeToRemove}"
    # debugf"paste node {newNode}"
    let role = nodeToRemove.role
    let index = nodeToRemove.index
    nodeToRemove.removeFromParent()
    (parent, role, index)

  var idMap = initTable[NodeId, NodeId]()
  for i, node in nodes:
    var foundExisting = false
    for child in node.childrenRec:
      if self.document.project.resolveReference(node.id).isSome:
        log lvlInfo, fmt"Node {node} already exists in model, inserting a clone"
        foundExisting = true
        break

    let newNode = if foundExisting:
      # clone node because the model already contains a node with an id from new node
      let newNode = node.clone(idMap, self.document.model, false)
      newNode.replaceReferences(idMap)
      newNode
    else:
      node

    parent.insert(role, index + i, newNode)
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(newNode).get

  self.markDirty()

proc pasteNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  asyncSpawn self.pasteNodeAsync()

proc chooseLanguageFromUser*(self: ModelDocumentEditor, languageIds: openArray[LanguageId],
    handleConfirmed: proc(language: Language) {.gcsafe, raises: [].}) =

  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  let languageIds = @languageIds
  var languages = initTable[LanguageId, Language]()

  proc getLanguagesAsync(): Future[ItemList] {.async.} =
    var items = newItemList(languageIds.len)
    for i, id in languageIds:
      let language = await self.projectService.resolveLanguage(self.document.model.project, self.document.workspace.get, id)
      if language.getSome(language):
        languages[id] = language
        items[i] = FinderItem(
          displayName: language.name,
          detail: $id,
          data: $id
        )

    return items

  var builder = SelectorPopupBuilder()
  builder.scope = "model-choose-language".some
  builder.scaleX = 0.4
  builder.scaleY = 0.5

  let finder = newFinder(newAsyncCallbackDataSource(getLanguagesAsync), filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    let id = item.data.parseId.LanguageId
    if not languages.contains(id):
      log lvlError, &"[chooseLanguageFromUser] Selected invalid language item: {item}"
      return

    handleConfirmed(languages[id])
    true

  discard self.app.pushSelectorPopup(builder)

proc addLanguage*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return
  let languages = self.document.project.getAllAvailableLanguages().filterIt(not self.document.model.hasLanguage(it))
  self.chooseLanguageFromUser(languages, proc(language: Language) =
    log lvlInfo, fmt"Add language {language.name} ({language.id}) to model {self.document.model.id}"
    self.document.model.addLanguage(language)
    self.document.builder.addBuilder(self.projectService.builders.getBuilder(language.id))
  )

proc createNewModelAsync*(self: ModelDocumentEditor, name: string) {.async.} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  if self.document.workspace.getSome(ws):
    var model = newModel(newId().ModelId)
    model.path = name & ".ast-model"
    self.document.project.addModel(model)
    let serialized = $model.toJson
    await ws.saveFile(model.path, serialized)

    discard self.app.openWorkspaceFile(model.path)
  else:
    log lvlError, fmt"Failed to create model: no workspace"

proc createNewModel*(self: ModelDocumentEditor, name: string) {.expose("editor.model").} =
  asyncSpawn self.createNewModelAsync(name)

proc addModelToProject*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  let workspace: Workspace = self.document.workspace.get

  proc getModelsAsync(): Future[ItemList] {.async.} =
    let files = await workspace.getDirectoryListingRec("")

    var items = newItemList(files.len)
    var index = 0

    for file in files:
      if not file.endsWith(".ast-model"):
        continue

      if self.document.project.findModelByPath(file).isSome:
        continue

      let (directory, name) = file.splitPath
      var relativeDirectory = workspace.getRelativePathSync(directory).get(directory)

      items[index] = FinderItem(
        displayName: name,
        detail: relativeDirectory,
        data: file,
      )
      inc index

    items.setLen(index)

    return items

  var builder = SelectorPopupBuilder()
  builder.scope = "model-add-model-to-project".some
  builder.scaleX = 0.4
  builder.scaleY = 0.5

  let finder = newFinder(newAsyncCallbackDataSource(getModelsAsync), filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    log lvlInfo, fmt"Add model {item.displayName} to project"
    asyncSpawn self.document.projectService.loadModelAsync(item.data).asyncDiscard
    true

  discard self.app.pushSelectorPopup(builder)

proc importModel*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  let workspace = self.document.workspace.get

  proc getModels(): seq[FinderItem] =
    for model in self.document.project.models.values:
      if self.document.model.hasImport(model.id):
        continue

      let (directory, name) = model.path.splitPath
      let relativeDirectory = workspace.getRelativePathSync(directory).get(directory)

      result.add FinderItem(
        displayName: name,
        detail: &"{model.id}\t./{relativeDirectory}",
        data: $model.id,
      )

    for (languageId, model) in self.projectService.repository.languageModels.pairs:
      if not self.document.model.hasImport(model.id):
        log lvlInfo, fmt"Add imported model {model.path} ({model.id})"
        let language = self.projectService.repository.language(languageId).get
        result.add FinderItem(
          displayName: language.name,
          detail: $model.id & "\tBuiltin",
          data: $model.id,
        )

  var builder = SelectorPopupBuilder()
  builder.scope = "model-import-model".some
  builder.scaleX = 0.4
  builder.scaleY = 0.5

  let source = newSyncDataSource(getModels)
  let finder = newFinder(source, filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    let modelId = item.data.parseId.ModelId
    log lvlInfo, fmt"Import model {item.displayName} ({modelId}) to model {self.document.model.id}"

    defer:
      source.retrigger()

    for (languageId, model) in self.projectService.repository.languageModels.pairs:
      if modelId == model.id:
        log lvlInfo, fmt"Add imported model {model.path} ({model.id})"
        self.document.model.addImport(model)

    if self.document.project.getModel(modelId).getSome(model):
      log lvlInfo, fmt"Add imported model {model.path} ({model.id})"
      self.document.model.addImport(model)
      return false

    log lvlError, fmt"[importModel] Failed to find model {modelId} in project"

    false

  discard self.app.pushSelectorPopup(builder)

proc compileLanguageAsync*(self: ModelDocumentEditor) {.async.} =
  while self.document.project.isNil or self.document.model.isNil:
    await sleepAsync(1.milliseconds)

  let project = self.document.project
  let model = self.document.model

  if not model.hasLanguage(IdLangLanguage):
    return

  let languageId = model.id.LanguageId

  defer:
    for document in self.app.getAllDocuments:
      if document of ModelDocument:
        let modelDocument = document.ModelDocument
        if modelDocument.model.hasLanguage(languageId):
          modelDocument.builder.addBuilder(self.projectService.builders.getBuilder(languageId))
          modelDocument.onBuilderChanged.invoke()

          for root in modelDocument.model.rootNodes:
            root.forEach2 child:
              modelDocument.ctx.state.updateNode(child)

  self.projectService.updateLanguageFromModel(model).await

proc compileLanguage*(self: ModelDocumentEditor) {.expose("editor.model").} =
  asyncSpawn self.compileLanguageAsync()

proc addRootNode*(self: ModelDocumentEditor) {.expose("editor.model").} =
  var classes = initTable[ClassId, NodeClass]()

  proc getClasses(): seq[FinderItem] =
    for language in self.document.model.languages:
      for rootNodeClass in language.rootNodeClasses:
        classes[rootNodeClass.id] = rootNodeClass

        let name = rootNodeClass.name
        result.add FinderItem(
          displayName: name,
          detail: $rootNodeClass.id,
          data: $rootNodeClass.id,
        )

  proc handleConfirmed(popup: ISelectorPopup, item: FinderItem): bool =
    let classId = item.data.parseId.ClassId
    log lvlInfo, fmt"Add root node of class {item.displayName} to model {self.document.model.id}"

    let class = classes[classId]

    defer:
      self.document.finishTransaction()

    self.document.model.addRootNode newAstNode(class)
    self.rebuildCells()
    self.cursor = self.getFirstEditableCellOfNode(self.document.model.rootNodes.last).get
    self.updateScrollOffset(true)
    self.markDirty()

    true

  var builder = SelectorPopupBuilder()
  builder.scope = "model-add-root-node".some
  builder.scaleX = 0.4
  builder.scaleY = 0.5
  builder.handleItemConfirmed = handleConfirmed

  let source = newSyncDataSource(getClasses)
  let finder = newFinder(source, filterAndSort=true)
  builder.finder = finder.some

  discard self.app.pushSelectorPopup(builder)

proc saveProject*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  asyncSpawn self.document.projectService.save()

proc loadLanguageModel*(self: ModelDocumentEditor) {.expose("editor.model").} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return
  let languages = self.document.project.getAllAvailableLanguages()
  self.chooseLanguageFromUser(languages, proc(language: Language) =
    log lvlInfo, fmt"Loading language model of {language.name} ({language.id})"

    try:
      let project = self.document.project

      let model = if project.getModel(language.id.ModelId).getSome(model):
        model
      else:
        let model = self.projectService.repository.createModelForLanguage(language)
        project.addModel(model)
        model

      self.document.model = model

      discard self.document.model.onNodeDeleted.subscribe proc(d: auto) = self.document.handleNodeDeleted(d[0], d[1], d[2], d[3], d[4])
      discard self.document.model.onNodeInserted.subscribe proc(d: auto) = self.document.handleNodeInserted(d[0], d[1], d[2], d[3], d[4])
      discard self.document.model.onNodePropertyChanged.subscribe proc(d: auto) = self.document.handleNodePropertyChanged(d[0], d[1], d[2], d[3], d[4], d[5])
      discard self.document.model.onNodeReferenceChanged.subscribe proc(d: auto) = self.document.handleNodeReferenceChanged(d[0], d[1], d[2], d[3], d[4])

      self.document.builder.clear()
      for language in self.document.model.languages:
        self.document.builder.addBuilder(self.projectService.builders.getBuilder(language.id))

      self.document.undoList.setLen 0
      self.document.redoList.setLen 0

      {.gcsafe.}:
        functionInstances.clear()
        structInstances.clear()
      self.document.ctx.state.clearCache()

    except CatchableError:
      log lvlError, fmt"Failed to load model source file '{self.document.filename}': {getCurrentExceptionMsg()}"
      log lvlError, getCurrentException().getStackTrace()

    self.document.onModelChanged.invoke (self.document)

  )

proc findDeclaration*(self: ModelDocumentEditor, global: bool) {.expose("editor.model").} =
  if self.document.project.isNil:
    log lvlError, fmt"No project set for model document '{self.document.filename}'"
    return

  var nodes = initTable[NodeId, AstNode]()

  proc getNodes(): seq[FinderItem] =
    var models = newSeq[Model]()
    if global:
      for model in self.document.project.models.values:
        models.add model
    else:
      models.add self.document.model

    for model in models:
      for rootNode in model.rootNodes:
        for children in rootNode.childLists.mitems:
          for child in children.nodes:
            let class = child.nodeClass
            if class.isNotNil and class.isSubclassOf(IdINamed):
              let name = child.property(IdINamedName).get.stringValue
              nodes[child.id] = child
              result.add FinderItem(
                displayName: name,
                detail: $child.id,
                data: $child.id,
              )

  proc handleSelected(popup: ISelectorPopup, item: FinderItem) =
    log lvlInfo, fmt"Select node {item.displayName}"

    let nodeId = item.data.parseId.NodeId
    let node = nodes[nodeId]

    if node.model.isNil:
      log lvlError, fmt"Node is no longer part of a model"
      return

    if node.model == self.document.model and self.getFirstEditableCellOfNode(node).getSome(cursor):
      self.cursor = cursor
      self.updateScrollOffset(true)
      self.markDirty()
    elif node.model != self.document.model:
      if self.requestEditorForModel(node.model).getSome(editor):
        editor.cursor = editor.getFirstEditableCellOfNode(node).get
        editor.updateScrollOffset(true)
        editor.markDirty()
        self.app.tryActivateEditor(editor)

  proc handleConfirmed(popup: ISelectorPopup, item: FinderItem): bool =
    log lvlInfo, fmt"Select node {item.displayName}"

    let nodeId = item.data.parseId.NodeId
    let node = nodes[nodeId]

    if node.model.isNil:
      log lvlError, fmt"Node is no longer part of a model"
      return

    if node.model == self.document.model and self.getFirstEditableCellOfNode(node).getSome(cursor):
      self.cursor = cursor
      self.updateScrollOffset(true)
      self.markDirty()
    elif node.model != self.document.model:
      if self.requestEditorForModel(node.model).getSome(editor):
        editor.cursor = editor.getFirstEditableCellOfNode(node).get
        editor.updateScrollOffset(true)
        editor.markDirty()
        self.app.tryActivateEditor(editor)

    return true

  var builder = SelectorPopupBuilder()
  builder.scope = "model-find-declaration".some
  builder.scaleX = 0.4
  builder.scaleY = 0.5
  builder.handleItemConfirmed = handleConfirmed
  builder.handleItemSelected = handleSelected

  let source = newSyncDataSource(getNodes)
  let finder = newFinder(source, filterAndSort=true)
  builder.finder = finder.some

  discard self.app.pushSelectorPopup(builder)

genDispatcher("editor.model")
addActiveDispatchTable "editor.model", genDispatchTable("editor.model")

method handleAction*(self: ModelDocumentEditor, action: string, arg: string, record: bool): Option[JsonNode] =
  # log lvlInfo, fmt"[modeleditor]: Handle action {action}, '{arg}'"
  # defer:
  #   log lvlDebug, &"line: {self.cursor.targetCell.line}, cursor: {self.cursor},\ncell: {self.cursor.cell.dump()}\ntargetCell: {self.cursor.targetCell.dump()}"

  self.mCursorBeforeTransaction = self.selection

  var args = newJArray()
  try:
    args.add api.ModelDocumentEditor(id: self.id).toJson

    for a in newStringStream(arg).parseJsonFragments():
      args.add a

    if dispatch(action, args).getSome(res):
      self.markDirty()
      return res.some
  except CatchableError:
    log lvlError, fmt"Failed to dispatch action '{action} {args}': {getCurrentExceptionMsg()}"
    log lvlError, getCurrentException().getStackTrace()

  return JsonNode.none

method getStateJson*(self: ModelDocumentEditor): JsonNode {.gcsafe, raises: [].} =
  if self.cursor.node.isNil:
    return %*{}
  else:
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
      let index = cursorState["index"].jsonTo int
      let path = cursorState["path"].jsonTo seq[int]
      let nodeId = cursorState["nodeId"].jsonTo(NodeId)
      self.targetCursor = CellCursorState(index: index, path: path, node: nodeId)
    except:
      log lvlError, fmt"Failed to restore cursor state: {getCurrentExceptionMsg()}"