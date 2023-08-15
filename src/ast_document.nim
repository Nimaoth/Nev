import std/[strformat, strutils, algorithm, math, logging, sugar, tables, macros, macrocache, options, deques, sets, json, sequtils, streams]
import timer, myjsonutils
import fusion/matching, fuzzy, bumpy, rect_utils, vmath, chroma
import util, document, document_editor, text/text_editor, events, id, ast_ids, ast, scripting/expose, event, theme, input, custom_async
import compiler, selector_popup, config_provider, app_interface
from scripting_api as api import nil
import custom_logger
import platform/[filesystem, platform, widgets]
import workspaces/[workspace]

type ExecutionOutput* = ref object
  lines*: seq[(string, Color)]
  scroll*: int

proc addOutput(self: ExecutionOutput, line: string, color: SomeColor = Color(r: 1, g: 1, b: 1, a: 1)) =
  if self.lines.len >= 1500:
    self.lines.delete(0..(self.lines.len - 1000))
  if self.scroll > 0:
    self.scroll += 1
  self.lines.add (line, color.color)

var executionOutput* = ExecutionOutput()

let ctx* = newContext()
ctx.enableLogging = false
ctx.enableQueryLogging = false

proc createBinaryIntOperator(operator: proc(a: int, b: int): int): Value =
  return newFunctionValue proc(values: seq[Value]): Value =
    if values.len < 2:
      return errorValue()
    if values[0].kind != vkNumber or values[1].kind != vkNumber:
      return errorValue()
    return Value(kind: vkNumber, intValue: operator(values[0].intValue, values[1].intValue))

proc createUnityIntOperator(operator: proc(a: int): int): Value =
  return newFunctionValue proc(values: seq[Value]): Value =
    if values.len < 1:
      return errorValue()
    let value = values[0]
    if value.kind != vkNumber:
      return errorValue()
    return Value(kind: vkNumber, intValue: operator(value.intValue))

let typeAddIntInt = newFunctionType(@[intType(), intType()], intType())
let typeSubIntInt = newFunctionType(@[intType(), intType()], intType())
let typeMulIntInt = newFunctionType(@[intType(), intType()], intType())
let typeDivIntInt = newFunctionType(@[intType(), intType()], intType())
let typeModIntInt = newFunctionType(@[intType(), intType()], intType())
let typeAddStringInt = newFunctionType(@[stringType(), intType()], stringType())
let typeNegInt = newFunctionType(@[intType()], intType())
let typeNotInt = newFunctionType(@[intType()], intType())
let typeFnIntIntInt = newFunctionType(@[intType(), intType()], intType())

let funcAddIntInt = createBinaryIntOperator (a: int, b: int) => a + b
let funcSubIntInt = createBinaryIntOperator (a: int, b: int) => a - b
let funcMulIntInt = createBinaryIntOperator (a: int, b: int) => a * b
let funcDivIntInt = createBinaryIntOperator (a: int, b: int) => a div b
let funcModIntInt = createBinaryIntOperator (a: int, b: int) => a mod b
let funcNegInt = createUnityIntOperator (a: int) => -a
let funcNotInt = createUnityIntOperator (a: int) => (if a != 0: 0 else: 1)
let funcLessIntInt = createBinaryIntOperator (a: int, b: int) => (if a < b: 1 else: 0)
let funcLessEqualIntInt = createBinaryIntOperator (a: int, b: int) => (if a <= b: 1 else: 0)
let funcGreaterIntInt = createBinaryIntOperator (a: int, b: int) => (if a > b: 1 else: 0)
let funcGreaterEqualIntInt = createBinaryIntOperator (a: int, b: int) => (if a >= b: 1 else: 0)
let funcEqualIntInt = createBinaryIntOperator (a: int, b: int) => (if a == b: 1 else: 0)
let funcNotEqualIntInt = createBinaryIntOperator (a: int, b: int) => (if a != b: 1 else: 0)
let funcAndIntInt = createBinaryIntOperator (a: int, b: int) => (if a != 0 and b != 0: 1 else: 0)
let funcOrIntInt = createBinaryIntOperator (a: int, b: int) => (if a != 0 or b != 0: 1 else: 0)
let funcOrderIntInt = createBinaryIntOperator (a: int, b: int) => (if a < b: -1 elif a > b: 1 else: 0)

let funcAddStringInt = newFunctionValue proc(values: seq[Value]): Value =
  if values.len < 2:
    return errorValue()
  let leftValue = values[0]
  let rightValue = values[1]
  if leftValue.kind != vkString:
    return errorValue()
  return Value(kind: vkString, stringValue: leftValue.stringValue & $rightValue)

let funcPrintAny = newFunctionValue proc(values: seq[Value]): Value =
  result = stringValue(values.join "")
  executionOutput.addOutput $result
  log(lvlInfo, result)
  return voidValue()

let funcBuildStringAny = newFunctionValue (values) => stringValue(values.join "")

ctx.globalScope[IdAdd] = Symbol(id: IdAdd, name: "+", kind: skBuiltin, typ: typeAddIntInt, value: funcAddIntInt, operatorNotation: Infix, precedence: 10)
ctx.globalScope[IdSub] = Symbol(id: IdSub, name: "-", kind: skBuiltin, typ: typeSubIntInt, value: funcSubIntInt, operatorNotation: Infix, precedence: 10)
ctx.globalScope[IdMul] = Symbol(id: IdMul, name: "*", kind: skBuiltin, typ: typeMulIntInt, value: funcMulIntInt, operatorNotation: Infix, precedence: 20)
ctx.globalScope[IdDiv] = Symbol(id: IdDiv, name: "/", kind: skBuiltin, typ: typeDivIntInt, value: funcDivIntInt, operatorNotation: Infix, precedence: 20)
ctx.globalScope[IdMod] = Symbol(id: IdMod, name: "%", kind: skBuiltin, typ: typeModIntInt, value: funcModIntInt, operatorNotation: Infix, precedence: 20)
ctx.globalScope[IdNegate] = Symbol(id: IdNegate, name: "-", kind: skBuiltin, typ: typeNegInt, value: funcNegInt, operatorNotation: Prefix)
ctx.globalScope[IdNot] = Symbol(id: IdNot, name: "!", kind: skBuiltin, typ: typeNotInt, value: funcNotInt, operatorNotation: Prefix)
ctx.globalScope[IdAppendString] = Symbol(id: IdAppendString, name: "&", kind: skBuiltin, typ: typeAddStringInt, value: funcAddStringInt, operatorNotation: Infix, precedence: 0)
ctx.globalScope[IdLess] = Symbol(id: IdLess, name: "<", kind: skBuiltin, typ: typeFnIntIntInt, value: funcLessIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdLessEqual] = Symbol(id: IdLessEqual, name: "<=", kind: skBuiltin, typ: typeFnIntIntInt, value: funcLessEqualIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdGreater] = Symbol(id: IdGreater, name: ">", kind: skBuiltin, typ: typeFnIntIntInt, value: funcGreaterIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdGreaterEqual] = Symbol(id: IdGreaterEqual, name: ">=", kind: skBuiltin, typ: typeFnIntIntInt, value: funcGreaterEqualIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdEqual] = Symbol(id: IdEqual, name: "==", kind: skBuiltin, typ: typeFnIntIntInt, value: funcEqualIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdNotEqual] = Symbol(id: IdNotEqual, name: "!=", kind: skBuiltin, typ: typeFnIntIntInt, value: funcNotEqualIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdAnd] = Symbol(id: IdAnd, name: "and", kind: skBuiltin, typ: typeFnIntIntInt, value: funcAndIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdOr] = Symbol(id: IdOr, name: "or", kind: skBuiltin, typ: typeFnIntIntInt, value: funcOrIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdOrder] = Symbol(id: IdOrder, name: "<=>", kind: skBuiltin, typ: typeFnIntIntInt, value: funcOrderIntInt, operatorNotation: Infix, precedence: 5)
ctx.globalScope[IdInt] = Symbol(id: IdInt, name: "int", kind: skBuiltin, typ: typeType(), value: typeValue(intType()))
ctx.globalScope[IdString] = Symbol(id: IdString, name: "string", kind: skBuiltin, typ: typeType(), value: typeValue(stringType()))
ctx.globalScope[IdVoid] = Symbol(id: IdVoid, name: "void", kind: skBuiltin, typ: typeType(), value: typeValue(voidType()))
ctx.globalScope[IdPrint] = Symbol(id: IdPrint, name: "print", kind: skBuiltin, typ: newFunctionType(@[anyType(true)], voidType()), value: funcPrintAny)
ctx.globalScope[IdBuildString] = Symbol(id: IdBuildString, name: "build", kind: skBuiltin, typ: newFunctionType(@[anyType(true)], stringType()), value: funcBuildStringAny)
for symbol in ctx.globalScope.values:
  discard ctx.newSymbol(symbol)

############################################################################################

type Cursor = seq[int]

# Generate new IDs
when false:
  for i in 0..100:
    echo $newId()
    sleep(100)

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

proc `$`(op: UndoOp): string =
  result = fmt"{op.kind}, '{op.text}'"
  if op.id != null: result.add fmt", id = {op.id}"
  if op.node != nil: result.add fmt", node = {op.node}"
  if op.parent != nil: result.add fmt", parent = {op.parent}, index = {op.idx}"

type
  OnNodeInserted = proc(doc: AstDocument, node: AstNode)
  AstDocument* = ref object of Document
    symbols*: Table[Id, Symbol]
    rootNode*: AstNode

    nodes*: Table[Id, AstNode]

    onNodeInserted*: seq[OnNodeInserted]

    undoOps*: seq[UndoOp]
    redoOps*: seq[UndoOp]

type
  CompletionKind* = enum
    SymbolCompletion
    AstCompletion
  Completion* = object
    score*: float
    case kind*: CompletionKind
    of SymbolCompletion:
      id*: Id
    of AstCompletion:
      nodeKind*: AstNodeKind
      name*: string

type AstDocumentEditor* = ref object of DocumentEditor
  app*: AppInterface
  configProvider*: ConfigProvider
  document*: AstDocument
  selectedNode: AstNode
  selectionHistory: Deque[AstNode]
  selectionFuture: Deque[AstNode]

  deletedNode: Option[AstNode]

  lastRootNode: AstNode

  currentlyEditedSymbol*: Id
  currentlyEditedNode*: AstNode
  textEditor*: TextDocumentEditor
  textDocument*: TextDocument
  textEditEventHandler*: EventHandler
  textEditorWidget*: WPanel

  modeEventHandler: EventHandler
  currentMode*: string

  completionText: string
  completions*: seq[Completion]
  selectedCompletion*: int
  lastItems*: seq[tuple[index: int, widget: WWidget]]
  completionsBaseIndex*: int
  completionsScrollOffset*: float
  scrollToCompletion*: Option[int]
  lastCompletionsWidget*: WWidget

  scrollOffset*: float
  previousBaseIndex*: int

  lastBounds*: Rect
  lastLayouts*: seq[tuple[layout: NodeLayout, offset: Vec2]]
  lastEditCommand*: (string, string)
  lastMoveCommand*: (string, string)
  lastOtherCommand*: (string, string)
  lastCommand*: (string, string)

import goto_popup

proc updateCompletions(self: AstDocumentEditor)
proc getPrevChild*(document: AstDocument, node: AstNode, max: int = -1): Option[AstNode]
proc getNextChild*(document: AstDocument, node: AstNode, min: int = -1): Option[AstNode]

proc node*(editor: AstDocumentEditor): AstNode =
  return editor.selectedNode

proc handleSelectedNodeChanged(editor: AstDocumentEditor) =
  if editor.app.isNil:
    return

  editor.markDirty()

  let indent = editor.configProvider.getValue("ast.indent", 20.0)
  let inlineBlocks = editor.configProvider.getValue("ast.inline-blocks", false)
  let verticalDivision = editor.configProvider.getValue("ast.vertical-division", false)

  let node = editor.node

  let margin = 5.0 * editor.app.platform.totalLineHeight

  var foundNode = false
  var i = 0
  while i < editor.lastLayouts.len:
    defer: inc i
    var layout = editor.lastLayouts[i].layout
    var offset = editor.lastLayouts[i].offset

    if layout.nodeToVisualNode.contains(node.id):
      # Node layout was already computed for the last selection
      let visualNode = layout.nodeToVisualNode[node.id]
      let bounds = visualNode.absoluteBounds + vec2(0, offset.y)

      if not bounds.intersects(editor.lastBounds):
        break

      if bounds.yh < margin:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = margin - (bounds.yh - offset.y)
      elif bounds.y > editor.lastBounds.h - margin:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = -(bounds.y - offset.y) + editor.lastBounds.h - margin

      return

  # Loop through the nodes again and check if a parent or neighbor is in the existing layouts
  i = 0
  while i < editor.lastLayouts.len:
    defer: inc i
    var layout = editor.lastLayouts[i].layout
    var offset = editor.lastLayouts[i].offset

    var targetNode = node
    while targetNode != nil and not layout.nodeToVisualNode.contains(targetNode.id):
      targetNode = targetNode.parent

    if targetNode != nil:
      # New node is not in layout yet but there is a parent which has a layout already
      let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: targetNode.subbase, selectedNode: node.id, measureText: (t) => editor.app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
      layout = ctx.computeNodeLayout(input)
      foundNode = true

    elif node.parent == editor.document.rootNode and node.prev.getSome(prev) and layout.nodeToVisualNode.contains(prev.id):
      let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node.subbase, selectedNode: node.id, measureText: (t) => editor.app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
      layout = ctx.computeNodeLayout(input)

      offset += layout.bounds.h
      editor.lastLayouts.insert((layout, offset), i + 1)
      for k in (i + 1)..editor.lastLayouts.high:
        editor.lastLayouts[k].offset.y += layout.bounds.h
      foundNode = true

    elif node.parent == editor.document.rootNode and node.next.getSome(next) and layout.nodeToVisualNode.contains(next.id):
      let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node.subbase, selectedNode: node.id, measureText: (t) => editor.app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
      layout = ctx.computeNodeLayout(input)

      editor.lastLayouts.insert((layout, offset), i)
      for k in i..editor.lastLayouts.high:
        editor.lastLayouts[k].offset.y += layout.bounds.h
      foundNode = true

    if foundNode and layout.nodeToVisualNode.contains(node.id):
      let visualNode = layout.nodeToVisualNode[node.id]
      let bounds = visualNode.absoluteBounds + vec2(0, offset.y)

      if not bounds.intersects(editor.lastBounds.whRect):
        break

      if bounds.yh < margin:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = margin - (bounds.yh - offset.y)
      elif bounds.y > editor.lastBounds.h - margin:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = -(bounds.y - offset.y) + editor.lastBounds.h - margin

      return

  # Still didn't find a node
  let subbase = node.subbase
  let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: subbase, selectedNode: node.id, measureText: (t) => editor.app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
  let layout = ctx.computeNodeLayout(input)
  if layout.nodeToVisualNode.contains(node.id):
    let visualNode = layout.nodeToVisualNode[node.id]
    let bounds = visualNode.absoluteBounds
    editor.previousBaseIndex = subbase.index
    editor.scrollOffset = -bounds.y + editor.lastBounds.h * 0.5

proc `node=`*(editor: AstDocumentEditor, node: AstNode) =
  if node == editor.selectedNode:
    return

  if node.parent == nil or node.base != editor.document.rootNode:
    return

  if editor.selectedNode != nil:
    editor.selectionHistory.addLast editor.selectedNode
  if editor.selectionHistory.len > 100:
    discard editor.selectionHistory.popFirst
  editor.selectedNode = node
  editor.handleSelectedNodeChanged()

proc selectPrevNode*(editor: AstDocumentEditor) =
  while editor.selectionHistory.len > 0:
    let node = editor.selectionHistory.popLast
    if node != nil and node.parent != nil and node.base == editor.document.rootNode:
      editor.selectionHistory.addFirst editor.selectedNode
      editor.selectedNode = node
      editor.handleSelectedNodeChanged()
      return

proc selectNextNode*(editor: AstDocumentEditor) =
  while editor.selectionHistory.len > 0:
    let node = editor.selectionHistory.popFirst
    if node != nil and node.parent != nil and node.base == editor.document.rootNode:
      editor.selectionHistory.addLast editor.selectedNode
      editor.selectedNode = node
      editor.handleSelectedNodeChanged()
      return

iterator nextPreOrder*(self: AstDocument, node: AstNode, endNode: AstNode = nil): tuple[key: int, value: AstNode] =
  var n = node
  var idx = -1
  var i = 0

  while true:
    defer: inc i
    if idx == -1:
      yield (i, n)
    if idx + 1 < n.len:
      n = n[idx + 1]
      idx = -1
    elif n.next.getSome(ne) and n != endNode:
      n = ne
      idx = -1
    elif n.parent != nil and n != endNode and n.parent != endNode:
      idx = n.index
      n = n.parent
    else:
      break

iterator nextPostOrder*(self: AstDocument, node: AstNode, idx: int = -1, endNode: AstNode = nil): tuple[key: int, value: AstNode] =
  var n = node
  var idx = idx
  var i = 0

  while true:
    defer: inc i
    if idx == n.len - 1:
      yield (i, n)
      if n.parent != nil and n != endNode and n.parent != endNode:
        idx = n.index
        n = n.parent
      else:
        break
    elif idx + 1 < node.len:
      n = n[idx + 1]
      idx = -1
    else:
      break

iterator nextPreOrderWhere*(self: AstDocument, node: AstNode, predicate: proc(node: AstNode): bool, endNode: AstNode = nil): tuple[key: int, value: AstNode] =
  var i = 0
  for _, child in self.nextPreOrder(node, endNode = endNode):
    if predicate(child):
      yield (i, child)
      inc i

iterator nextPreVisualOrder*(self: AstDocument, node: AstNode): tuple[key: int, value: AstNode] =
  var n = node
  var i = 0
  var gotoChild = true

  while n != nil:
    if gotoChild and n.len > 0:
      n = self.getNextChild(n, -1).get
      yield (i, n)
      gotoChild = true
    elif n.parent != nil and self.getNextChild(n.parent, n.index).getSome(ne):
      n = ne
      yield (i, n)
      gotoChild = true
    else:
      gotoChild = false
      n = n.parent

iterator prevPostVisualOrder*(self: AstDocument, node: AstNode, gotoChild: bool = true): AstNode =
  var gotoChild = gotoChild
  var n = node

  while n != nil:
    if gotoChild and n.len > 0:
      n = self.getPrevChild(n, -1).get
      gotoChild = true
    elif n.parent != nil and self.getPrevChild(n.parent, n.index).getSome(ne):
      yield n
      n = ne
      gotoChild = true
    else:
      yield n
      gotoChild = false
      n = n.parent

iterator prevPostOrder*(self: AstDocument, node: AstNode): AstNode =
  var idx = 0
  var n = node

  while n != nil:
    if idx - 1 in 0..<n.len:
      n = n[idx - 1]
      idx = n.len
    elif n.prev.getSome(ne):
      yield n
      n = ne
      idx = n.len
    else:
      yield n
      idx = n.index
      n = n.parent

method `$`*(document: AstDocument): string =
  return document.filename

proc newAstDocument*(filename: string = "", app: bool = false, workspaceFolder: Option[WorkspaceFolder]): AstDocument =
  new(result)
  result.filename = filename
  result.rootNode = AstNode(kind: NodeList, parent: nil, id: newId())
  result.symbols = initTable[Id, Symbol]()
  result.appFile = app
  result.workspace = workspaceFolder

  if filename.len > 0:
    result.load()

# when not defined(js):
#   import html_renderer

proc saveHtml*(self: AstDocument) =
  discard
  # when not defined(js):
  #   let pathParts = self.filename.splitFile
  #   let htmlPath = pathParts.dir / (pathParts.name & ".html")
  #   let html = self.serializeHtml(editor.app.theme)
  #   fs.saveFile(htmlPath, html)

method save*(self: AstDocument, filename: string = "", app: bool = false) =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  log lvlInfo, fmt"[astdoc] Saving ast source file '{self.filename}'"
  let serialized = self.rootNode.toJson

  if self.workspace.getSome(ws):
    asyncCheck ws.saveFile(self.filename, serialized.pretty)
  elif self.appFile:
    fs.saveApplicationFile(self.filename, serialized.pretty)
  else:
    fs.saveFile(self.filename, serialized.pretty)

  self.saveHtml()

proc handleNodeInserted*(doc: AstDocument, node: AstNode)

proc loadAsync*(self: AstDocument): Future[void] {.async.} =
  log lvlInfo, fmt"[astdoc] Loading ast source file '{self.filename}'"
  try:
    var jsonText = ""
    if self.workspace.getSome(ws):
      jsonText = await ws.loadFile(self.filename)
    elif self.appFile:
      jsonText = fs.loadApplicationFile(self.filename)
    else:
      jsonText = fs.loadFile(self.filename)

    let json = jsonText.parseJson
    let newAst = json.jsonToAstNode

    log(lvlInfo, fmt"[astdoc] Load new ast {newAst}")

    ctx.deleteAllNodesAndSymbols()
    for symbol in ctx.globalScope.values:
      discard ctx.newSymbol(symbol)

    self.nodes.clear()
    self.rootNode = newAst
    self.handleNodeInserted self.rootNode
    self.undoOps.setLen 0
    self.redoOps.setLen 0

  except CatchableError:
    log lvlError, fmt"[astdoc] Failed to load ast source file '{self.filename}'"

  self.saveHtml()

method load*(self: AstDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename
  asyncCheck self.loadAsync()

proc handleNodeInserted*(doc: AstDocument, node: AstNode) =
  log lvlInfo, fmt"[astdoc] Node inserted: {node}"
  ctx.insertNode(node)
  for handler in doc.onNodeInserted:
    handler(doc, node)

  doc.nodes[node.id] = node
  for (key, child) in node.nextPreOrder:
    doc.nodes[child.id] = child

proc insertNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode]

proc handleNodeDelete*(doc: AstDocument, node: AstNode) =
  log lvlInfo, fmt"[astdoc] Node deleted: {node}"
  for child in node.children:
    doc.handleNodeDelete child

  ctx.deleteNode(node)

  # Remove diagnostics added by the removed node
  for i, update in ctx.updateFunctions:
    let key = (node.getItem, i)
    if ctx.diagnosticsPerQuery.contains(key):
      for id in ctx.diagnosticsPerQuery[key]:
        ctx.diagnosticsPerNode[id].queries.del key
      ctx.diagnosticsPerQuery.del(key)

  doc.nodes.del node.id

proc handleNodeInserted*(self: AstDocumentEditor, doc: AstDocument, node: AstNode) =
  if doc.rootNode != self.lastRootNode:
    self.node = doc.rootNode[0]
    self.lastRootNode = doc.rootNode

  log lvlInfo, fmt"[asteditor] Node inserted: {node}, {self.deletedNode}"
  if self.deletedNode.getSome(deletedNode) and deletedNode == node:
    self.deletedNode = some(node.cloneAndMapIds())
    log lvlInfo, fmt"[asteditor] Clearing editor.deletedNode because it was just inserted"
  self.markDirty()

proc handleTextDocumentChanged*(self: AstDocumentEditor) =
  self.updateCompletions()
  self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc isEditing*(self: AstDocumentEditor): bool = self.textEditor != nil

proc editSymbol*(self: AstDocumentEditor, symbol: Symbol) =
  log(lvlInfo, fmt"Editing symbol {symbol.name} ({symbol.kind}, {symbol.id})")
  if symbol.kind == skAstNode:
    log(lvlInfo, fmt"Editing symbol node {symbol.node}")
  self.currentlyEditedNode = nil
  self.currentlyEditedSymbol = symbol.id
  self.textDocument = newTextDocument(self.configProvider)
  self.textDocument.content = @[symbol.name]
  self.textEditor = newTextEditor(self.textDocument, self.app, self.configProvider)
  self.textEditor.setMode("insert")
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false
  self.textEditor.disableScrolling = true
  self.textEditor.disableCompletions = true
  self.textEditor.lineNumbers = api.LineNumbers.None.some
  discard self.textDocument.textChanged.subscribe (doc: TextDocument) => self.handleTextDocumentChanged()
  self.updateCompletions()
  self.markDirty()

proc editNode*(self: AstDocumentEditor, node: AstNode) =
  log(lvlInfo, fmt"Editing node {node}")
  self.currentlyEditedNode = node
  self.currentlyEditedSymbol = null
  self.textDocument = newTextDocument(self.configProvider)
  self.textDocument.content = node.text.splitLines
  self.textEditor = newTextEditor(self.textDocument, self.app, self.configProvider)
  self.textEditor.setMode("insert")
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false
  self.textEditor.disableScrolling = true
  self.textEditor.disableCompletions = true
  self.textEditor.lineNumbers = api.LineNumbers.None.some
  discard self.textDocument.textChanged.subscribe (doc: TextDocument) => self.handleTextDocumentChanged()
  self.updateCompletions()
  self.markDirty()

proc tryEdit*(self: AstDocumentEditor, node: AstNode): bool =
  if ctx.getSymbol(node.id).getSome(sym):
    self.editSymbol(sym)
    return true
  elif ctx.getSymbol(node.reff).getSome(sym):
    self.editSymbol(sym)
    return true
  else:
    case node.kind:
    of Empty, NumberLiteral, StringLiteral:
      self.editNode(node)
      return true
    else:
      return false

proc getCompletions*(editor: AstDocumentEditor, text: string, contextNode: Option[AstNode] = none[AstNode]()): seq[Completion] =
  result = @[]

  # Find everything matching text
  if contextNode.isNone or contextNode.get.kind == Identifier or contextNode.get.kind == Empty:
    let symbols = ctx.computeSymbols(contextNode.get)
    for (key, symbol) in symbols.pairs:
      let score = fuzzyMatch(text, symbol.name)
      result.add Completion(kind: SymbolCompletion, score: score, id: symbol.id)

  if contextNode.getSome(node) and node.kind == Empty:
    result.add Completion(kind: AstCompletion, nodeKind: If, name: "if", score: fuzzyMatch(text, "if"))
    result.add Completion(kind: AstCompletion, nodeKind: While, name: "while", score: fuzzyMatch(text, "while"))
    result.add Completion(kind: AstCompletion, nodeKind: ConstDecl, name: "const", score: fuzzyMatch(text, "const"))
    result.add Completion(kind: AstCompletion, nodeKind: LetDecl, name: "let", score: fuzzyMatch(text, "let"))
    result.add Completion(kind: AstCompletion, nodeKind: VarDecl, name: "var", score: fuzzyMatch(text, "var"))
    result.add Completion(kind: AstCompletion, nodeKind: StringLiteral, name: "string literal", score: if text.startsWith("\""): 1.1 else: 0)
    result.add Completion(kind: AstCompletion, nodeKind: NodeList, name: "block", score: fuzzyMatch(text, "{"))
    result.add Completion(kind: AstCompletion, nodeKind: FunctionDefinition, name: "fn", score: fuzzyMatch(text, "fn"))

    try:
      discard text.parseFloat
      result.add Completion(kind: AstCompletion, nodeKind: NumberLiteral, name: "number literal", score: 1.1)
    except CatchableError: discard

  result.sort((a, b) => cmp(a.score, b.score), Descending)

  return result

proc updateCompletions(self: AstDocumentEditor) =
  if self.textDocument == nil:
    self.completions = @[]
    self.selectedCompletion = 0
    return

  let text = self.textDocument.content.join

  self.completions = self.getCompletions(text, some(self.node))
  self.completionText = text

  if self.completions.len > 0:
    self.selectedCompletion = self.selectedCompletion.clamp(0, self.completions.len - 1)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc finishEdit*(self: AstDocumentEditor, apply: bool)

proc getNodeAt*(self: AstDocumentEditor, cursor: Cursor, index: int = -1): AstNode =
  return self.node

method canEdit*(self: AstDocumentEditor, document: Document): bool =
  if document of AstDocument: return true
  else: return false

method getEventHandlers*(self: AstDocumentEditor): seq[EventHandler] =
  result.add self.eventHandler

  if not self.modeEventHandler.isNil:
    result.add self.modeEventHandler

  if self.textEditor != nil:
    result.add self.textEditor.getEventHandlers
    result.add self.textEditEventHandler

method handleDocumentChanged*(self: AstDocumentEditor) =
  log(lvlInfo, fmt"[ast-editor] Document changed")
  self.selectionHistory.clear
  self.selectionFuture.clear
  self.finishEdit false
  for symbol in ctx.globalScope.values:
    discard ctx.newSymbol(symbol)
  self.node = self.document.rootNode[0]
  self.markDirty()

proc getNextChild*(document: AstDocument, node: AstNode, min: int = -1): Option[AstNode] =
  if node.len == 0:
    return none[AstNode]()

  case node
  of Call():
    if ctx.computeSymbol(node[0]).getSome(sym) and sym.kind == skBuiltin:
      case sym.operatorNotation
      of Infix:
        if node.len == 3:
          if min == 0: return some(node[2])
          if min == 1: return some(node[0])
          if min == 2: return none[AstNode]()
          return some(node[1])
      of Postfix:
        if node.len == 2:
          if min == 0: return none[AstNode]()
          if min == 1: return some(node[0])
          return some(node[1])
      else: discard
  else: discard

  if min < 0:
    return some(node[0])
  if min >= node.len - 1:
    return none[AstNode]()
  return some(node[min + 1])

func shouldSelectNode(node: AstNode): bool =
  case node.kind
  of Call, NodeList, Params, Assignment:
    return node.len == 0
  else:
    return true

proc getNextChildRec*(document: AstDocument, node: AstNode, min: int = -1): Option[AstNode] =
  var node = node
  var idx = -1

  if document.getNextChild(node, min).getSome(child):
    idx = -1
    node = child
  elif node.parent != nil:
    idx = node.index
    node = node.parent
  else:
    return some(node)

  while not shouldSelectNode(node):
    if document.getNextChild(node, idx).getSome(child):
      idx = -1
      node = child
    elif node.parent != nil:
      idx = node.index
      node = node.parent
    else:
      break

  return some(node)

proc getPrevChild*(document: AstDocument, node: AstNode, max: int = -1): Option[AstNode] =
  if node.len == 0:
    return none[AstNode]()

  case node
  of Call():
    if ctx.computeSymbol(node[0]).getSome(sym) and sym.kind == skBuiltin:
      case sym.operatorNotation
      of Infix:
        if node.len == 3:
          if max == 0: return some(node[1])
          if max == 1: return none[AstNode]()
          if max == 2: return some(node[0])
          return some(node[2])
      of Postfix:
        if node.len == 2:
          if max == 0: return some(node[1])
          if max == 1: return none[AstNode]()
          return some(node[0])
      else: discard
  else: discard

  if max < 0:
    return some(node[node.len - 1])
  elif max == 0:
    return none[AstNode]()
  return some(node[max - 1])

proc getPrevChildRec*(document: AstDocument, node: AstNode, max: int = -1): Option[AstNode] =
  for n in document.prevPostOrder node:
    if n.len == 0 and n != node:
      return some(n)

  return none[AstNode]()

proc getNextLine*(document: AstDocument, node: AstNode): Option[AstNode] =
  for _, n in document.nextPreOrder(node):
    if n == node or n.parent == nil:
      continue

    if n.parent.kind == NodeList:
      if n.kind == NodeList and n.len == 0:
        return some(n)
      elif n.kind != NodeList:
        return some(n)

    if n.parent.kind == If:
      let isElse = n == n.parent.last and n.parent.len mod 2 != 0
      let isCondition = not isElse and n.index mod 2 == 0
      if n.kind == NodeList and n.len == 0:
        return some(n)
      elif n.kind != NodeList and (not isCondition or n.index > 0):
        return some(n)

  return none[AstNode]()

proc getPrevLine*(document: AstDocument, node: AstNode): Option[AstNode] =
  for n in document.prevPostOrder(node):
    if n == node or n.parent == nil:
      continue

    if n.parent.kind == NodeList:
      if n.kind == NodeList and n.len == 0:
        return some(n)
      elif n.kind != NodeList:
        return some(n)

    if n.parent.kind == If:
      let isElse = n == n.parent.last and n.parent.len mod 2 != 0
      let isCondition = not isElse and n.index mod 2 == 0
      if n.kind == NodeList and n.len == 0:
        return some(n)
      elif n.kind != NodeList and (not isCondition or n.index > 0):
        return some(n)

    if n.kind == If:
      return some(n)

  return none[AstNode]()

proc replaceNode*(document: AstDocument, node: AstNode, newNode: AstNode): AstNode =
  if node.parent == nil:
    raise newException(Defect, "lol")

  let idx = node.index
  document.undoOps.add UndoOp(kind: Replace, parent: node.parent, idx: idx, node: node)
  document.redoOps = @[]

  document.handleNodeDelete node
  node.parent[idx] = newNode
  document.handleNodeInserted newNode
  return newNode

proc deleteNode*(document: AstDocument, node: AstNode): AstNode =
  if node.parent == nil:
    raise newException(Defect, "lol")

  if node.parent == document.rootNode and document.rootNode.len == 1:
    # We're trying to delete the last child of the root node, replace with empty instead
    return document.replaceNode(node, AstNode(kind: Empty))

  document.undoOps.add UndoOp(kind: Delete, parent: node.parent, idx: node.index, node: node)
  document.redoOps = @[]
  document.handleNodeDelete node
  return node.parent.delete node.index

proc insertNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode] =
  var node = node
  var index = index
  if node == nil:
    node = document.rootNode
    index = 0

  document.undoOps.add UndoOp(kind: Insert, parent: node, idx: index, node: newNode)
  document.redoOps = @[]
  node.insert(newNode, index)
  document.handleNodeInserted newNode
  return some(newNode)

proc insertOrReplaceNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode] =
  document.undoOps.add UndoOp(kind: Insert, parent: node, idx: index, node: newNode)
  document.redoOps = @[]
  node.insert(newNode, index)
  document.handleNodeInserted newNode
  return some(newNode)

proc undo*(document: AstDocument): Option[AstNode] =
  if document.undoOps.len == 0:
    return none[AstNode]()

  let undoOp = document.undoOps.pop
  log(lvlInfo, fmt"Undoing {undoOp}")

  case undoOp.kind:
  of Delete:
    undoOp.parent.insert(undoOp.node, undoOp.idx)
    document.handleNodeInserted undoOp.node
    document.redoOps.add undoOp
    return some(undoOp.node)
  of Replace:
    let oldNode = undoOp.parent[undoOp.idx]
    document.handleNodeDelete undoOp.parent[undoOp.idx]
    undoOp.parent[undoOp.idx] = undoOp.node
    document.handleNodeInserted undoOp.node
    document.redoOps.add UndoOp(kind: Replace, parent: undoOp.parent, idx: undoOp.idx, node: oldNode)
    return some(undoOp.node)
  of Insert:
    document.handleNodeDelete undoOp.parent[undoOp.idx]
    discard undoOp.parent.delete undoOp.idx
    document.redoOps.add undoOp
    if undoOp.idx < undoOp.parent.len:
      return some(undoOp.parent[undoOp.idx])
    elif undoOp.idx > 0:
      return some(undoOp.parent[undoOp.idx - 1])
    return some(undoOp.parent)
  of SymbolNameChange:
    if ctx.getSymbol(undoOp.id).getSome(symbol):
      document.redoOps.add UndoOp(kind: SymbolNameChange, id: undoOp.id, text: symbol.name)
      symbol.name = undoOp.text
      if symbol.kind == skAstNode:
        symbol.node.text = symbol.name
        ctx.updateNode(symbol.node)
      ctx.notifySymbolChanged(symbol)
  of TextChange:
    document.redoOps.add UndoOp(kind: TextChange, node: undoOp.node, text: undoOp.node.text)
    undoOp.node.text = undoOp.text
    ctx.updateNode(undoOp.node)

  return none[AstNode]()

proc redo*(document: AstDocument): Option[AstNode] =
  if document.redoOps.len == 0:
    return none[AstNode]()

  let redoOp = document.redoOps.pop
  log(lvlInfo, fmt"Redoing {redoOp}")

  case redoOp.kind:
  of Delete:
    document.undoOps.add UndoOp(kind: Delete, parent: redoOp.parent, idx: redoOp.idx, node: redoOp.node)
    document.handleNodeDelete redoOp.parent[redoOp.idx]
    discard redoOp.parent.delete redoOp.idx
    if redoOp.idx < redoOp.parent.len:
      return some(redoOp.parent[redoOp.idx])
    elif redoOp.idx > 0:
      return some(redoOp.parent[redoOp.idx - 1])
    return some(redoOp.parent)
  of Replace:
    let oldNode = redoOp.parent[redoOp.idx]
    document.handleNodeDelete redoOp.parent[redoOp.idx]
    redoOp.parent[redoOp.idx] = redoOp.node
    document.handleNodeInserted redoOp.node
    document.undoOps.add UndoOp(kind: Replace, parent: redoOp.parent, idx: redoOp.idx, node: oldNode)
    return some(redoOp.node)
  of Insert:
    redoOp.parent.insert redoOp.node, redoOp.idx
    document.handleNodeInserted redoOp.node
    document.undoOps.add redoOp
    return some(redoOp.node)
  of SymbolNameChange:
    if ctx.getSymbol(redoOp.id).getSome(symbol):
      document.undoOps.add UndoOp(kind: SymbolNameChange, id: redoOp.id, text: symbol.name)
      symbol.name = redoOp.text
      if symbol.kind == skAstNode:
        symbol.node.text = symbol.name
        ctx.updateNode(symbol.node)
      ctx.notifySymbolChanged(symbol)
  of TextChange:
    document.undoOps.add UndoOp(kind: TextChange, node: redoOp.node, text: redoOp.node.text)
    redoOp.node.text = redoOp.text
    ctx.updateNode(redoOp.node)

  return none[AstNode]()

proc createNodeFromAction*(editor: AstDocumentEditor, arg: string, node: AstNode, typ: Type): Option[(AstNode, int)] =
  case arg
  of "deleted":
    if editor.deletedNode.getSome(node):
      editor.deletedNode = some(node.cloneAndMapIds())
      return some (node, 0)
    return none (AstNode, int)

  of "empty":
    return some((AstNode(kind: Empty, id: newId(), text: ""), 0))
  of "identifier":
    return some((AstNode(kind: Identifier), 0))
  of "number-literal":
    return some((AstNode(kind: NumberLiteral, text: ""), 0))

  of "const-decl":
    let node = makeTree(AstNode) do:
      ConstDecl(id: == newId()):
        Empty()
    return some (node, 0)

  of "let-decl":
    let node = makeTree(AstNode) do:
      LetDecl(id: == newId()):
        Empty()
        Empty()
    return some (node, 1)

  of "var-decl":
    let node = makeTree(AstNode) do:
      VarDecl(id: == newId()):
        Empty()
        Empty()
    return some (node, 1)

  of "call-func":
    let sym = ctx.computeSymbol(node)
    let kind = if sym.getSome(sym) and sym.kind == skBuiltin:
      sym.operatorNotation
    else:
      Regular

    let node = case kind:
      of Prefix, Postfix:
        makeTree(AstNode) do:
          Call:
            Empty()
            Empty()
      of Infix:
        makeTree(AstNode) do:
          Call:
            Empty()
            Empty()
            Empty()
      of Regular:
        # if sym.getSome(sym):
        let typ = ctx.computeType(node)
        if typ.kind == tError:
          makeTree(AstNode) do:
            Call:
              Empty()
              Empty()
              Empty()
        elif typ.kind != tFunction:
          makeTree(AstNode) do:
            Call:
              Empty()
        else:
          var newNode = makeTree(AstNode) do:
            Call:
              Empty()
          for _ in typ.paramTypes:
            newNode.add makeTree(AstNode) do: Empty()
          newNode

      else:
        return none[(AstNode, int)]()
    return some (node, 0)

  of "call-arg":
    let node = makeTree(AstNode) do:
      Call:
        Empty()
        Empty()
    return some (node, 1)

  of "+":
    let operator = if typ.kind == tString: IdAppendString else: IdAdd
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == operator)
        Empty()
        Empty()
    return some (node, 0)
  of "-":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdSub)
        Empty()
        Empty()
    return some (node, 0)
  of "*":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdMul)
        Empty()
        Empty()
    return some (node, 0)
  of "/":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdDiv)
        Empty()
        Empty()
    return some (node, 0)
  of "%":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdMod)
        Empty()
        Empty()
    return some (node, 0)

  of "\"":
    let node = makeTree(AstNode) do:
        StringLiteral(text: "")
    return some (node, 0)

  of "{":
    let node = makeTree(AstNode) do:
      NodeList:
        Empty()
    return some (node, 0)

  of "=":
    let node = makeTree(AstNode) do:
      Assignment:
        Empty()
        Empty()
    return some (node, 0)

  of "==":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdEqual)
        Empty()
        Empty()
    return some (node, 0)

  of "!=":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdNotEqual)
        Empty()
        Empty()
    return some (node, 0)

  of "<=":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdLessEqual)
        Empty()
        Empty()
    return some (node, 0)

  of ">=":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdGreaterEqual)
        Empty()
        Empty()
    return some (node, 0)

  of "<":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdLess)
        Empty()
        Empty()
    return some (node, 0)

  of ">":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdGreater)
        Empty()
        Empty()
    return some (node, 0)

  of "<>":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdOrder)
        Empty()
        Empty()
    return some (node, 0)

  of "and":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdAnd)
        Empty()
        Empty()
    return some (node, 0)

  of "or":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(reff: == IdOr)
        Empty()
        Empty()
    return some (node, 0)

  else:
    return none[(AstNode, int)]()

proc createDefaultNode*(editor: AstDocumentEditor, kind: AstNodeKind): Option[(AstNode, int)] =
  case kind
  of Empty:
    return some((AstNode(kind: Empty, id: newId(), text: ""), 0))
  of Identifier:
    return some((AstNode(kind: Identifier, text: ""), 0))
  of NumberLiteral:
    return some((AstNode(kind: NumberLiteral, text: ""), 0))
  of StringLiteral:
    return some((AstNode(kind: StringLiteral, text: ""), 0))

  of ConstDecl:
    let node = makeTree(AstNode) do:
      ConstDecl(id: == newId()):
        Empty()
    return some (node, 0)

  of LetDecl:
    let node = makeTree(AstNode) do:
      LetDecl(id: == newId()):
        Empty()
        Empty()
    return some (node, 0)

  of VarDecl:
    let node = makeTree(AstNode) do:
      VarDecl(id: == newId()):
        Empty()
        Empty()
    return some (node, 0)

  of FunctionDefinition:
    let node = makeTree(AstNode) do:
      FunctionDefinition():
        Params()
        Empty()
        NodeList():
          Empty()
    return some (node, 0)

  of If:
    let node = makeTree(AstNode) do:
      If:
        Empty()
        Empty()
    return some (node, 0)

  of While:
    let node = makeTree(AstNode) do:
      While:
        Empty()
        Empty()
    return some (node, 0)

  of NodeList:
    let node = makeTree(AstNode) do:
      NodeList:
        Empty()
    return some (node, 0)

  else:
    return none[(AstNode, int)]()

proc shouldEditNode(doc: AstDocument, node: AstNode): bool =
  if node.kind == Empty and node.text == "":
    return true
  if node.kind == NumberLiteral and node.text == "":
    return true
  if node.kind == ConstDecl:
    return ctx.computeSymbol(node).getSome(symbol) and symbol.name == ""
  if node.kind == LetDecl:
    return ctx.computeSymbol(node).getSome(symbol) and symbol.name == ""
  if node.kind == VarDecl:
    return ctx.computeSymbol(node).getSome(symbol) and symbol.name == ""
  return false

proc getNodeAtPixelPosition(self: AstDocumentEditor, posContent: Vec2): Option[AstNode] =
  result = AstNode.none

  for (layout, offset) in self.lastLayouts:
    let bounds = layout.bounds + offset
    var smallestRange: VisualNodeRange
    if bounds.contains(posContent):
      for (_, child) in layout.node.nextPreOrder:
        if layout.nodeToVisualNode.contains(child.id):
          let visualNode = layout.nodeToVisualNode[child.id]
          let bounds = visualNode.absoluteBounds + vec2(0, offset.y)
          if bounds.contains(posContent):
            if smallestRange.parent.isNil or (visualNode.parent.depth > smallestRange.parent.depth) or
              ((visualNode.parent.depth == smallestRange.parent.depth) and (visualNode.parent.indent > smallestRange.parent.indent)) or
              ((visualNode.parent.depth == smallestRange.parent.depth) and (visualNode.last - visualNode.first) < (smallestRange.last - smallestRange.first)):
              smallestRange = visualNode
              result = child.some

      if result.isNone:
        result = layout.node.some
      return

proc canInsertInto*(self: AstDocumentEditor, parent: AstNode): bool =
  case parent.kind
  of Empty, Identifier, NumberLiteral, StringLiteral:
    return false
  of ConstDecl:
    return parent.len < 1
  of LetDecl, VarDecl, While, Assignment:
    return parent.len < 2
  of FunctionDefinition:
    return parent.len < 3
  of NodeList, If, Params:
    return true
  of Call:
    if parent.len == 0:
      return true
    if ctx.computeSymbol(parent[0]).getSome(sym):
      if sym.kind == skBuiltin:
        case sym.operatorNotation
        of Prefix, Postfix:
          return parent.len < 2
        of Infix:
          return parent.len < 3
        else:
          discard
    let typ = ctx.computeType(parent[0])
    if typ.kind == tFunction:
      if typ.paramTypes.len > 0 and typ.paramTypes[typ.paramTypes.high] == anyType(true):
        return true
      return parent.len < typ.paramTypes.len + 1
    return true

proc getAstDocumentEditor(wrapper: api.AstDocumentEditor): Option[AstDocumentEditor] =
  if gAppInterface.isNil: return AstDocumentEditor.none
  if gAppInterface.getEditorForId(wrapper.id).getSome(editor):
    if editor of AstDocumentEditor:
      return editor.AstDocumentEditor.some
  return AstDocumentEditor.none

static:
  addTypeMap(AstDocumentEditor, api.AstDocumentEditor, getAstDocumentEditor)

proc toJson*(self: api.AstDocumentEditor, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["type"] = newJString("editor.ast")
  result["id"] = newJInt(self.id.int)

proc fromJsonHook*(t: var api.AstDocumentEditor, jsonNode: JsonNode) =
  t.id = api.EditorId(jsonNode["id"].jsonTo(int))

proc moveCursor*(self: AstDocumentEditor, direction: int) {.expose("editor.ast").} =
  if direction < 0:
    if self.isEditing: return
    let index = self.node.index
    if index > 0:
      self.node = self.node.parent[index - 1]
  else:
    if self.isEditing: return
    let index = self.node.index
    if index >= 0 and index < self.node.parent.len - 1:
      self.node = self.node.parent[index + 1]

proc moveCursorUp*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.node != self.document.rootNode and self.node.parent != self.document.rootNode and self.node.parent != nil:
    self.node = self.node.parent

proc moveCursorDown*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.node.len > 0:
    self.node = self.node[0]

proc moveCursorNext*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  var node = self.node
  for _, n in self.document.nextPreVisualOrder(self.node):
    if not shouldSelectNode(n):
      continue
    if n != self.node:
      self.node = n
      break

proc moveCursorPrev*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  var node = self.node
  for n in self.document.prevPostVisualOrder(self.node, gotoChild = false):
    if not shouldSelectNode(n):
      continue
    if n != self.node:
      self.node = n
      break

proc moveCursorNextLine*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.document.getNextLine(self.node).getSome(next):
    self.node = next

proc moveCursorPrevLine*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.document.getPrevLine(self.node).getSome(prev):
    self.node = prev

proc selectContaining*(self: AstDocumentEditor, container: string) {.expose("editor.ast").} =
  if self.isEditing: return
  case container
  of "function":
    if self.node.findWithParentRec(FunctionDefinition).getSome(child):
      self.node = child.parent
  of "const-decl":
    if self.node.findWithParentRec(ConstDecl).getSome(child):
      self.node = child.parent
  of "line":
    if self.node.findWithParentRec(NodeList).getSome(child):
      self.node = child
  of "node-list":
    if self.node.findWithParentRec(NodeList).getSome(child):
      self.node = child.parent
  of "if":
    if self.node.findWithParentRec(If).getSome(child):
      self.node = child.parent
  of "while":
    if self.node.findWithParentRec(While).getSome(child):
      self.node = child.parent

proc deleteSelected*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  self.deletedNode = some(self.node)
  self.node = self.document.deleteNode self.node

proc copySelected*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  self.deletedNode = some(self.node.cloneAndMapIds())

proc finishEdit*(self: AstDocumentEditor, apply: bool) {.expose("editor.ast").} =
  if not self.isEditing: return

  if apply:
    if self.currentlyEditedSymbol != null:
      if ctx.getSymbol(self.currentlyEditedSymbol).getSome(sym):
        self.document.undoOps.add UndoOp(kind: SymbolNameChange, id: self.currentlyEditedSymbol, text: sym.name)
        sym.name = self.textDocument.content.join

        if sym.kind == skAstNode:
          sym.node.text = sym.name
          ctx.updateNode(sym.node)
        ctx.notifySymbolChanged(sym)

    elif self.currentlyEditedNode != nil:
      self.document.undoOps.add UndoOp(kind: TextChange, node: self.currentlyEditedNode, text: self.currentlyEditedNode.text)
      self.currentlyEditedNode.text = self.textDocument.content.join "\n"
      ctx.updateNode(self.currentlyEditedNode)

  self.textEditor.unregister()
  self.textEditor = nil
  self.textDocument = nil
  self.currentlyEditedSymbol = null
  self.currentlyEditedNode = nil
  self.updateCompletions()

  self.markDirty()

proc undo*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  self.finishEdit false
  if self.document.undo.getSome(node):
    self.node = node

  self.markDirty()

proc redo*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  self.finishEdit false
  if self.document.redo.getSome(node):
    self.node = node

  self.markDirty()

proc insertAfterSmart*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return

  var node = self.node
  for next in node.parents(includeSelf = true):
    if self.canInsertInto(next.parent):
      node = next
      break
  let index = node.index

  if self.createNodeFromAction(nodeTemplate, node, errorType()).getSome(newNodeIndex):
    let (newNode, _) = newNodeIndex
    if self.document.insertNode(node.parent, index + 1, newNode).getSome(node):
      self.node = node

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

    else:
      log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node.parent} at {index + 1}")

proc insertAfter*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return
  let node = self.node
  let index = node.index

  if self.createNodeFromAction(nodeTemplate, node, errorType()).getSome(newNodeIndex):
    let (newNode, _) = newNodeIndex
    if self.document.insertNode(node.parent, index + 1, newNode).getSome(node):
      self.node = node

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

    else:
      log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node.parent} at {index + 1}")

proc insertBefore*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return
  let index = self.node.index
  if self.createNodeFromAction(nodeTemplate, self.node, errorType()).getSome(newNodeIndex):
    let (newNode, _) = newNodeIndex
    if self.document.insertNode(self.node.parent, index, newNode).getSome(node):
      self.node = node

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

    else:
      log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node.parent} at {index}")

proc insertChild*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.createNodeFromAction(nodeTemplate, self.node, errorType()).getSome(newNodeIndex):
    let (newNode, _) = newNodeIndex
    if self.document.insertNode(self.node, self.node.len, newNode).getSome(node):
      self.node = node

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

    else:
      log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node} at {self.node.len}")

proc replace*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.createNodeFromAction(nodeTemplate, self.node, errorType()).getSome(newNodeIndex):
    let (newNode, _) = newNodeIndex
    self.node = self.document.replaceNode(self.node, newNode)

    for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
      self.node = emptyNode
      discard self.tryEdit self.node
      break

proc replaceEmpty*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return
  if self.node.kind == Empty and self.createNodeFromAction(nodeTemplate, self.node, errorType()).getSome(newNodeIndex):
    let (newNode, _) = newNodeIndex
    self.node = self.document.replaceNode(self.node, newNode)

    for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
      self.node = emptyNode
      discard self.tryEdit self.node
      break

proc replaceParent*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing:
    return
  let node = self.node
  if node.parent == nil or node.parent == self.document.rootNode:
    return
  let parent = node.parent
  discard self.document.deleteNode(self.node)
  self.node = self.document.replaceNode(parent, node)

proc wrap*(self: AstDocumentEditor, nodeTemplate: string) {.expose("editor.ast").} =
  if self.isEditing: return
  let typ = ctx.computeType(self.node)

  if self.createNodeFromAction(nodeTemplate, self.node, typ).getSome(newNodeIndex):
    var (newNode, index) = newNodeIndex
    let oldNode = self.node
    self.node = self.document.replaceNode(self.node, newNode)
    for i, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => n.kind == Empty, endNode = newNode):
      if i == index:
        self.node = self.document.replaceNode(emptyNode, oldNode)
        break
    for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
      self.node = emptyNode
      discard self.tryEdit self.node
      break

proc editPrevEmpty*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  let current = self.node
  for emptyNode in self.document.prevPostOrder(self.node):
    if emptyNode != current and self.document.shouldEditNode(emptyNode):
      self.node = emptyNode
      discard self.tryEdit self.node
      break

proc editNextEmpty*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  let current = self.node
  for _, emptyNode in self.document.nextPreOrderWhere(self.node, (n) => n != current and self.document.shouldEditNode(n)):
    self.node = emptyNode
    discard self.tryEdit self.node
    break

proc rename*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  discard self.tryEdit self.node

proc selectPrevCompletion*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.completions.len > 0:
    if self.selectedCompletion == 0:
      self.selectedCompletion = self.completions.high
    else:
      self.selectedCompletion = (self.selectedCompletion - 1).clamp(0, self.completions.high)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc selectNextCompletion*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.completions.len > 0:
    if self.selectedCompletion == self.completions.high:
      self.selectedCompletion = 0
    else:
      self.selectedCompletion = (self.selectedCompletion + 1).clamp(0, self.completions.high)
  else:
    self.selectedCompletion = 0
  self.scrollToCompletion = self.selectedCompletion.some
  self.markDirty()

proc applySelectedCompletion*(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.textDocument == nil:
    return

  if self.completions.len == 0:
    return

  let com = self.completions[self.selectedCompletion]
  let completionText = self.completionText

  log(lvlInfo, fmt"[astedit] Applying completion {self.selectedCompletion} ({completionText})")

  self.finishEdit false
  self.markDirty()

  case com.kind
  of SymbolCompletion:
    if ctx.getSymbol(com.id).getSome(symbol):
      self.node = self.document.replaceNode(self.node, AstNode(kind: Identifier, reff: symbol.id))
  of AstCompletion:
    if self.createDefaultNode(com.nodeKind).getSome(nodeIndex):
      let (newNode, _) = nodeIndex
      discard self.document.replaceNode(self.node, newNode)

      if newNode.kind == NumberLiteral:
        newNode.text = completionText
        ctx.updateNode(newNode)
      elif newNode.kind == StringLiteral:
        assert completionText[0] == '"'
        newNode.text = completionText[1..^1]
        ctx.updateNode(newNode)

      self.node = newNode

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

proc cancelAndNextCompletion(self: AstDocumentEditor) {.expose("editor.ast").} =
  self.finishEdit(false)
  self.editNextEmpty()

proc cancelAndPrevCompletion(self: AstDocumentEditor) {.expose("editor.ast").} =
  self.finishEdit(false)
  self.editPrevEmpty()

proc cancelAndDelete(self: AstDocumentEditor) {.expose("editor.ast").} =
  self.finishEdit(false)
  self.deletedNode = some(self.node)
  self.node = self.document.deleteNode self.node

proc moveNodeToPrevSpace(self: AstDocumentEditor) {.expose("editor.ast").} =
  let wasEditing = self.isEditing
  self.finishEdit(false)

  # Find spot where to insert
  var targetNode = AstNode.none
  # log(lvlInfo, fmt"start: {self.node}")
  for next in self.document.prevPostOrder(self.node):
    # echo next
    if next == self.node:
      continue
    if self.canInsertInto(next) and (next != self.node.parent or self.node.index > 0):
      targetNode = next.some
      break

  if targetNode.getSome(newParent):
    let nodeToMove = self.node

    let index = if nodeToMove.parent == newParent:
      # Inserting into own parent
      nodeToMove.index - 1
    elif nodeToMove.index(newParent).getSome(index):
      # Inserting into parent of parent
      index
    else:
      # Inserting into unrelated node
      newParent.len

    self.node = self.document.deleteNode nodeToMove
    if self.document.insertNode(newParent, index, nodeToMove).getSome(newNode):
      self.node = newNode

      if wasEditing:
        discard self.tryEdit self.node

proc moveNodeToNextSpace(self: AstDocumentEditor) {.expose("editor.ast").} =
  let wasEditing = self.isEditing
  self.finishEdit(false)

  # Find spot where to insert
  var targetNode = AstNode.none
  # echo "start: ", self.node
  for (_, next) in self.document.nextPostOrder(self.node.parent, self.node.index):
    # echo next
    if next == self.node:
      continue
    if self.canInsertInto(next) and (next != self.node.parent or self.node.index + 1 < self.node.parent.len):
      targetNode = next.some
      break

  if targetNode.getSome(newParent):
    let nodeToMove = self.node

    let index = if nodeToMove.parent == newParent:
      # Inserting into own parent
      nodeToMove.index + 1
    elif nodeToMove.index(newParent).getSome(index):
      # Inserting into parent of parent
      index + 1
    else:
      # Inserting into unrelated node
      0

    self.node = self.document.deleteNode nodeToMove
    if self.document.insertNode(newParent, index, nodeToMove).getSome(newNode):
      self.node = newNode

      if wasEditing:
        discard self.tryEdit self.node

proc selectPrev(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  self.selectPrevNode()

proc selectNext(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return
  self.selectNextNode()

type AstSymbolSelectorItem* = ref object of SelectorItem
  completion*: Completion

method changed*(self: AstSymbolSelectorItem, other: SelectorItem): bool =
  let other = other.AstSymbolSelectorItem
  return self.completion.id != other.completion.id

proc openGotoSymbolPopup(self: AstDocumentEditor) {.expose("editor.ast").} =
  var popup = self.app.createSelectorPopup().SelectorPopup
  popup.getCompletions = proc(popup: SelectorPopup, text: string): seq[SelectorItem] =
    # Find everything matching text
    let symbols = ctx.computeSymbols(self.document.rootNode)
    for (key, symbol) in symbols.pairs:
      if symbol.kind != skAstNode:
        continue
      let score = fuzzyMatchSmart(text, symbol.name)
      result.add AstSymbolSelectorItem(completion: Completion(kind: SymbolCompletion, score: score, id: symbol.id))

    result.sort((a, b) => cmp(a.AstSymbolSelectorItem.completion.score, b.AstSymbolSelectorItem.completion.score), Descending)

  let prevSelection = self.node

  popup.handleItemSelected = proc(item: SelectorItem) =
    let completion = item.AstSymbolSelectorItem.completion
    let id = completion.id
    if ctx.getAstNode(id).getSome(node) and node.base == self.document.rootNode:
      self.node = node

  popup.handleCanceled = proc() =
    if prevSelection.base == self.document.rootNode:
      self.node = prevSelection

  popup.updateCompletions()

  self.app.pushPopup popup

proc goto(self: AstDocumentEditor, where: string) {.expose("editor.ast").} =
  if self.isEditing: return
  case where
  of "definition":
    if ctx.computeSymbol(self.node).getSome(sym):
      if sym.kind == skAstNode and sym.node != self.document.rootNode:
        self.node = sym.node
  of "next-usage":
    let id = case self.node
    of Identifier(): self.node.reff
    else: self.node.id
    for _, n in self.document.nextPreOrderWhere(self.node, n => n != self.node and (n.id == id or n.reff == id)):
      self.node = n
      break
  of "prev-usage":
    let id = case self.node
    of Identifier(): self.node.reff
    else: self.node.id
    for n in self.document.prevPostOrder(self.node):
      if n != self.node and (n.id == id or n.reff == id):
        self.node = n
        break

  of "next-error":
    for _, n in self.document.nextPreOrderWhere(self.node, n => n != self.node and ctx.computeType(n).kind == tError):
      self.node = n
      break
  of "prev-error":
    for n in self.document.prevPostOrder(self.node):
      if n != self.node and ctx.computeType(n).kind == tError:
        self.node = n
        break

  of "next-error-diagnostic":
    for _, n in self.document.nextPreOrderWhere(self.node, n => n != self.node):
      if ctx.diagnosticsPerNode.contains(n.id):
        var found = false
        for diags in ctx.diagnosticsPerNode[n.id].queries.values:
          if diags.len > 0:
            found = true
        if found:
          self.node = n
        break

  of "prev-error-diagnostic":
    for n in self.document.prevPostOrder(self.node):
      if n == self.node:
        continue
      if ctx.diagnosticsPerNode.contains(n.id):
        var found = false
        for diags in ctx.diagnosticsPerNode[n.id].queries.values:
          if diags.len > 0:
            found = true
        if found:
          self.node = n
          break

  of "symbol":
    self.openGotoSymbolPopup()

proc runSelectedFunction(self: AstDocumentEditor) {.expose("editor.ast").} =
  if self.isEditing: return

  var node = self.node

  while node.parent != nil:
    if node.parent == self.document.rootNode and node.kind == Call:
      let timer = startTimer()
      log(lvlInfo, fmt"[asteditor] Executing call {node}")

      # Update node to force recomputation of value
      ctx.updateNode(node)
      let result = ctx.computeValue(node)
      if result.kind != vkVoid:
        executionOutput.addOutput($result, if result.kind == vkError: rgb(255, 50, 50) else: rgb(50, 255, 50))
      log(lvlInfo, fmt"[asteditor] {node} returned {result} (Took {timer.elapsed.ms}ms)")
      return

    if node.kind == ConstDecl and node.len > 0 and node[0].kind == FunctionDefinition:
      let functionType = ctx.computeType(node)
      if functionType.kind == tError:
        log(lvlError, fmt"[asteditor] Function failed to compile: {node}")
        return

      if functionType.kind != tFunction:
        log(lvlError, fmt"[asteditor] Function has wrong type: {node}, type is {functionType}")
        return

      if functionType.paramTypes.len > 0:
        log(lvlError, fmt"[asteditor] Can't call function with arguments directly {node}, type is {functionType}")
        return

      log(lvlInfo, fmt"[asteditor] Calling function {node} ({functionType})")

      let timer = startTimer()

      let maxLoopIterations = self.configProvider.getValue("ast.max-loop-iterations", 1000)
      let fec = ctx.newFunctionExecutionContext(FunctionExecutionContext(node: node[0], arguments: @[], maxLoopIterations: some(maxLoopIterations)))
      let result = ctx.computeFunctionExecution(fec)
      if result.kind != vkVoid:
        executionOutput.addOutput($result, if result.kind == vkError: rgb(255, 50, 50) else: rgb(50, 255, 50))
      log(lvlInfo, fmt"[asteditor] Function {node} returned {result} (Took {timer.elapsed.ms}ms)")
      return

    node = node.parent

  log(lvlError, fmt"[asteditor] No function or call found to execute for {self.node}")

proc toggleOption(self: AstDocumentEditor, name: string) {.expose("editor.ast").} =
  case name
  of "logging":
    ctx.enableLogging = not ctx.enableLogging

proc handleAction(self: AstDocumentEditor, action: string, arg: string): EventResponse

proc runLastCommand(self: AstDocumentEditor, which: string) {.expose("editor.ast").} =
  case which
  of "":
    discard self.handleAction(self.lastCommand[0], self.lastCommand[1])
  of "move":
    discard self.handleAction(self.lastMoveCommand[0], self.lastMoveCommand[1])
  of "edit":
    discard self.handleAction(self.lastEditCommand[0], self.lastEditCommand[1])
  of "other":
    discard self.handleAction(self.lastOtherCommand[0], self.lastOtherCommand[1])

proc selectCenterNode(self: AstDocumentEditor) {.expose("editor.ast").} =
  var nodes: seq[tuple[y: float32, node: VisualNode]] = @[]
  for (layout, offset) in self.lastLayouts:
    for (i, node) in layout.root.nextPreOrder:
      if not isNil(node.node) and node.len > 0:
        let bounds = node.absoluteBounds
        if self.lastBounds.whRect.intersects(bounds + vec2(0, offset.y)):
          nodes.add (bounds.y + offset.y, node)

  nodes.sort (a, b) => cmp(a.y, b.y)

  if nodes.len > 0:
    let firstY = nodes[0].y
    let lastY = nodes[nodes.high].y
    let middleY = (firstY + lastY) * 0.5

    for i, (y, node) in nodes:
      if i == nodes.high or nodes[i + 1].y > middleY:
        self.node = node.node
        break

proc scroll*(self: AstDocumentEditor, amount: float32) {.expose("editor.ast").} =
  self.scrollOffset += amount
  self.markDirty()

proc scrollOutput(self: AstDocumentEditor, arg: string) {.expose("editor.ast").} =
  case arg
  of "home":
    executionOutput.scroll = executionOutput.lines.len

  of "end":
    executionOutput.scroll = 0

  else:
    executionOutput.scroll = clamp(executionOutput.scroll + arg.parseInt, 0, executionOutput.lines.len)

proc dumpContext(self: AstDocumentEditor) {.expose("editor.ast").} =
  log(lvlInfo, "=================================================")
  log(lvlInfo, ctx.toString)
  log(lvlInfo, "=================================================")

proc getModeConfig(self: AstDocumentEditor, mode: string): EventHandlerConfig =
  return self.app.getEventHandlerConfig("editor.ast." & mode)

proc setMode*(self: AstDocumentEditor, mode: string) {.expose("editor.ast").} =
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

proc mode*(self: AstDocumentEditor): string {.expose("editor.ast").} =
  return self.currentMode

proc getContextWithMode(self: AstDocumentEditor, context: string): string {.expose("editor.ast").} =
  return context & "." & $self.currentMode

genDispatcher("editor.ast")

proc handleAction(self: AstDocumentEditor, action: string, arg: string): EventResponse =
  # log lvlInfo, fmt"[asteditor]: Handle action {action}, '{arg}'"

  var args = newJArray()
  args.add api.AstDocumentEditor(id: self.id).toJson
  for a in newStringStream(arg).parseJsonFragments():
    args.add a

  var newLastCommand = (action, arg)
  defer: self.lastCommand = newLastCommand

  if self.app.handleUnknownDocumentEditorAction(self, action, args) == Handled:
    return Handled

  if dispatch(action, args).isSome:
    return Handled

  return Ignored

proc handleInput(self: AstDocumentEditor, input: string): EventResponse =
  # log lvlInfo, fmt"[asteditor]: Handle input '{input}'"
  return Ignored

proc getItemAtPixelPosition(self: AstDocumentEditor, posWindow: Vec2): Option[int] =
  result = int.none
  for (index, widget) in self.lastItems:
    if widget.lastBounds.contains(posWindow) and index >= 0 and index <= self.completions.high:
      return index.some

method handleScroll*(self: AstDocumentEditor, scroll: Vec2, mousePosWindow: Vec2) =
  let scrollAmount = scroll.y * self.configProvider.getValue("ast.scroll-speed", 20.0)

  if not self.lastCompletionsWidget.isNil and self.lastCompletionsWidget.lastBounds.contains(mousePosWindow):
    self.completionsScrollOffset += scrollAmount
    self.markDirty()
  else:
    self.scrollOffset += scrollAmount
    self.markDirty()

method handleMousePress*(self: AstDocumentEditor, button: MouseButton, mousePosWindow: Vec2, modifiers: Modifiers) =
  # Make mousePos relative to contentBounds
  let mousePosContent = mousePosWindow - self.lastBounds.xy

  if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if button == MouseButton.Left or button == MouseButton.Middle:
      self.selectedCompletion = item
      self.markDirty()
    return

  if button == MouseButton.Left:
    if self.getItemAtPixelPosition(mousePosWindow).getSome(index):
      self.selectedCompletion = index
      self.applySelectedCompletion()

    elif not self.isEditing and self.getNodeAtPixelPosition(mousePosContent).getSome(n):
      self.node = n

method handleMouseRelease*(self: AstDocumentEditor, button: MouseButton, mousePosWindow: Vec2) =
  if button == MouseButton.Left and self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if self.selectedCompletion == item:
      self.applySelectedCompletion()
      self.markDirty()

  discard

method handleMouseMove*(self: AstDocumentEditor, mousePosWindow: Vec2, mousePosDelta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]) =
  if self.getItemAtPixelPosition(mousePosWindow).getSome(item):
    if MouseButton.Middle in buttons:
      self.selectedCompletion = item
      self.markDirty()
    return

  if MouseButton.Left in buttons:
    let mousePosContent = mousePosWindow - self.lastBounds.xy
    if not self.isEditing and self.getNodeAtPixelPosition(mousePosContent).getSome(n):
      self.node = n

method getDocument*(self: AstDocumentEditor): Document = self.document

method createWithDocument*(self: AstDocumentEditor, document: Document, configProvider: ConfigProvider): DocumentEditor =
  let editor = AstDocumentEditor(eventHandler: nil, document: AstDocument(document), textDocument: nil, textEditor: nil)
  editor.configProvider = configProvider

  # Emit this to set the editor prototype to editor_ast_prototype, which needs to be set up before calling this
  when defined(js):
    {.emit: [editor, " = jsCreateWithPrototype(editor_ast_prototype, ", editor, ");"].}
    # This " is here to fix syntax highlighting

  editor.init()
  editor.document.onNodeInserted.add (doc: AstDocument, node: AstNode) => editor.handleNodeInserted(doc, node)

  editor.selectedCompletion = 0
  editor.completions = @[]

  # if editor.document.rootNode.len == 0:
  #   let paramA = newId()
  #   let paramB = newId()
  #   let resultId = newId()
  #   editor.document.rootNode.add makeTree(AstNode) do:
  #     ConstDecl(text: "add"):
  #       FunctionDefinition():
  #         Params():
  #           LetDecl(id: == paramA, text: "a"):
  #             Identifier(reff: == IdInt)
  #             Empty()
  #           LetDecl(id: == paramB, text: "b"):
  #             Identifier(reff: == IdInt)
  #             Empty()
  #         Identifier(reff: == IdInt)
  #         NodeList():
  #           LetDecl(id: == resultId, text: "result"):
  #             Empty()
  #             Call():
  #               Identifier(reff: == IdAdd)
  #               Identifier(reff: == paramA)
  #               Identifier(reff: == paramB)
  #           Identifier(reff: == resultId)

  #   let addId = editor.document.rootNode.last.id

  #   editor.document.rootNode.add makeTree(AstNode) do:
  #     ConstDecl(text: "main"):
  #       FunctionDefinition():
  #         Params()
  #         Identifier(reff: == IdVoid)
  #         NodeList():
  #           Call():
  #             Identifier(reff: == addId)
  #             NumberLiteral(text: "69")
  #             NumberLiteral(text: "420")
  editor.document.rootNode.add makeTree(AstNode) do:
    Empty()

  for c in editor.document.rootNode.children:
    editor.document.handleNodeInserted c

  ctx.insertNode(editor.document.rootNode)

  editor.node = editor.document.rootNode[0]

  return editor

method injectDependencies*(self: AstDocumentEditor, app: AppInterface) =
  self.app = app
  self.app.registerEditor(self)

  self.eventHandler = eventHandler(app.getEventHandlerConfig("editor.ast")):
    onAction:
      self.handleAction action, arg
    onInput:
      self.handleInput input

  self.textEditEventHandler = eventHandler(app.getEventHandlerConfig("editor.ast.completion")):
    onAction:
      self.handleAction action, arg
    onInput:
      Ignored

method unregister*(self: AstDocumentEditor) =
  self.finishEdit(false)
  self.app.unregisterEditor(self)