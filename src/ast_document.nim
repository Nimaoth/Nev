import std/[strformat, strutils, algorithm, math, logging, sugar, tables, macros, options, deques, sets, json]
import timer
import fusion/matching, fuzzy, bumpy, rect_utils, vmath
import util, input, document, document_editor, text_document, events, id, ast_ids, ast
import compiler

var logger = newConsoleLogger()

let ctx* = newContext()
ctx.enableLogging = false

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
  echo result
  return result

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
ctx.globalScope[IdPrint] = Symbol(id: IdPrint, name: "print", kind: skBuiltin, typ: newFunctionType(@[anyType(true)], stringType()), value: funcPrintAny)
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
    filename*: string
    symbols*: Table[Id, Symbol]
    rootNode*: AstNode

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
  document*: AstDocument
  selectedNode: AstNode
  selectionHistory: Deque[AstNode]
  selectionFuture: Deque[AstNode]

  deletedNode: Option[AstNode]

  currentlyEditedSymbol*: Id
  currentlyEditedNode*: AstNode
  textEditor*: TextDocumentEditor
  textDocument*: TextDocument
  textEditEventHandler*: EventHandler

  completionText: string
  completions*: seq[Completion]
  selectedCompletion*: int

  renderSelectedNodeValue*: bool
  scrollOffset*: float
  previousBaseIndex*: int

  lastBounds*: Rect
  lastLayouts*: seq[tuple[layout: NodeLayout, offset: Vec2]]

proc updateCompletions(editor: AstDocumentEditor)
proc getPrevChild*(document: AstDocument, node: AstNode, max: int = -1): Option[AstNode]
proc getNextChild*(document: AstDocument, node: AstNode, min: int = -1): Option[AstNode]

proc node*(editor: AstDocumentEditor): AstNode =
  return editor.selectedNode

proc handleSelectedNodeChanged(editor: AstDocumentEditor) =
  echo "handleSelectedNodeChanged"
  let node = editor.node

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

      if bounds.y < 50:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = 50 - (bounds.y - offset.y)
      elif bounds.yh > editor.lastBounds.h - 50:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = -(bounds.y - offset.y) + editor.lastBounds.h - 50

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
      let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: targetNode.subbase, selectedNode: node.id)
      layout = ctx.computeNodeLayout(input)
      foundNode = true

    elif node.parent == editor.document.rootNode and node.prev.getSome(prev) and layout.nodeToVisualNode.contains(prev.id):
      let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node.subbase, selectedNode: node.id)
      layout = ctx.computeNodeLayout(input)

      offset += layout.bounds.h
      editor.lastLayouts.insert((layout, offset), i + 1)
      for k in (i + 1)..editor.lastLayouts.high:
        editor.lastLayouts[k].offset.y += layout.bounds.h
      foundNode = true

    elif node.parent == editor.document.rootNode and node.next.getSome(next) and layout.nodeToVisualNode.contains(next.id):
      let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node.subbase, selectedNode: node.id)
      layout = ctx.computeNodeLayout(input)

      editor.lastLayouts.insert((layout, offset), i)
      for k in i..editor.lastLayouts.high:
        editor.lastLayouts[k].offset.y += layout.bounds.h
      foundNode = true

    if foundNode:
      let visualNode = layout.nodeToVisualNode[node.id]
      let bounds = visualNode.absoluteBounds + vec2(0, offset.y)

      if not bounds.intersects(editor.lastBounds):
        break

      foundNode = true

      if bounds.y < 50:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = 50 - (bounds.y - offset.y)
      elif bounds.yh > editor.lastBounds.h - 50:
        let subbase = node.subbase
        editor.previousBaseIndex = subbase.index
        editor.scrollOffset = -(bounds.y - offset.y) + editor.lastBounds.h - 50

      return

  # Still didn't find a node
  let subbase = node.subbase
  let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: subbase, selectedNode: node.id)
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

method `$`*(document: AstDocument): string =
  return document.filename

proc newAstDocument*(filename: string = ""): AstDocument =
  new(result)
  result.filename = filename
  result.rootNode = AstNode(kind: NodeList, parent: nil, id: newId())
  result.symbols = initTable[Id, Symbol]()

  if filename.len > 0:
    logger.log lvlInfo, fmt"[astdoc] Loading ast source file '{result.filename}'"
    try:
      let file = readFile(result.filename)
      let jsn = file.parseJson
      result.rootNode = jsn.jsonToAstNode
    except:
      logger.log lvlError, fmt"[astdoc] Failed to load ast source file '{result.filename}'"

method save*(self: AstDocument, filename: string = "") =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  logger.log lvlInfo, fmt"[astdoc] Saving ast source file '{self.filename}'"
  let serialized = self.rootNode.toJson
  writeFile(self.filename, serialized.pretty)

method load*(self: AstDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename

  logger.log lvlInfo, fmt"[astdoc] Loading ast source file '{self.filename}'"
  let jsonText = readFile(self.filename)
  let json = jsonText.parseJson
  let newAst = json.jsonToAstNode

  ctx.deleteAllNodesAndSymbols()
  self.rootNode = newAst
  ctx.insertNode(self.rootNode)
  self.undoOps.setLen 0
  self.redoOps.setLen 0

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

proc handleNodeInserted*(doc: AstDocument, node: AstNode) =
  logger.log lvlInfo, fmt"[astdoc] Node inserted: {node}"
  ctx.insertNode(node)
  for handler in doc.onNodeInserted:
    handler(doc, node)

proc insertNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode]

proc handleNodeDelete*(doc: AstDocument, node: AstNode) =
  for child in node.children:
    doc.handleNodeDelete child

  ctx.deleteNode(node)

proc handleNodeInserted*(self: AstDocumentEditor, doc: AstDocument, node: AstNode) =
  logger.log lvlInfo, fmt"[asteditor] Node inserted: {node}, {self.deletedNode}"
  if self.deletedNode.getSome(deletedNode) and deletedNode == node:
    self.deletedNode = some(node.cloneAndMapIds())
    logger.log lvlInfo, fmt"[asteditor] Clearing editor.deletedNode because it was just inserted"

proc handleTextDocumentChanged*(self: AstDocumentEditor) =
  self.updateCompletions()

proc isEditing*(self: AstDocumentEditor): bool = self.textEditor != nil

proc editSymbol*(self: AstDocumentEditor, symbol: Symbol) =
  logger.log(lvlInfo, fmt"Editing symbol {symbol.name} ({symbol.kind}, {symbol.id})")
  if symbol.kind == skAstNode:
    logger.log(lvlInfo, fmt"Editing symbol node {symbol.node}")
  self.currentlyEditedNode = nil
  self.currentlyEditedSymbol = symbol.id
  self.textDocument = newTextDocument()
  self.textDocument.content = @[symbol.name]
  self.textEditor = newTextEditor(self.textDocument)
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false
  self.textDocument.textChanged = (doc: Document) => self.handleTextDocumentChanged()
  self.updateCompletions()

proc editNode*(self: AstDocumentEditor, node: AstNode) =
  logger.log(lvlInfo, fmt"Editing node {node}")
  self.currentlyEditedNode = node
  self.currentlyEditedSymbol = null
  self.textDocument = newTextDocument()
  self.textDocument.content = node.text.splitLines
  self.textEditor = newTextEditor(self.textDocument)
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false
  self.textDocument.textChanged = (doc: Document) => self.handleTextDocumentChanged()
  self.updateCompletions()

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

proc finishEdit*(self: AstDocumentEditor, apply: bool) =
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

  self.textEditor = nil
  self.textDocument = nil
  self.currentlyEditedSymbol = null
  self.currentlyEditedNode = nil
  self.updateCompletions()

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
    result.add Completion(kind: AstCompletion, nodeKind: ConstDecl, name: "const", score: fuzzyMatch(text, "const"))
    result.add Completion(kind: AstCompletion, nodeKind: LetDecl, name: "let", score: fuzzyMatch(text, "let"))
    result.add Completion(kind: AstCompletion, nodeKind: VarDecl, name: "var", score: fuzzyMatch(text, "var"))
    result.add Completion(kind: AstCompletion, nodeKind: StringLiteral, name: "string literal", score: if text.startsWith("\""): 1.1 else: 0)
    result.add Completion(kind: AstCompletion, nodeKind: NodeList, name: "block", score: fuzzyMatch(text, "{"))
    result.add Completion(kind: AstCompletion, nodeKind: FunctionDefinition, name: "fn", score: fuzzyMatch(text, "fn"))

    try:
      discard text.parseFloat
      result.add Completion(kind: AstCompletion, nodeKind: NumberLiteral, name: "number literal", score: 1.1)
    except: discard

  result.sort((a, b) => cmp(a.score, b.score), Descending)

  return result

proc updateCompletions(editor: AstDocumentEditor) =
  if editor.textDocument == nil:
    editor.completions = @[]
    editor.selectedCompletion = 0
    return

  let text = editor.textDocument.content.join

  editor.completions = editor.getCompletions(text, some(editor.node))
  editor.completionText = text

  if editor.completions.len > 0:
    editor.selectedCompletion = editor.selectedCompletion.clamp(0, editor.completions.len - 1)
  else:
    editor.selectedCompletion = 0

proc selectNextCompletion(editor: AstDocumentEditor) =
  if editor.completions.len > 0:
    editor.selectedCompletion = (editor.selectedCompletion + 1).clamp(0, editor.completions.len - 1)
  else:
    editor.selectedCompletion = 0

proc selectPrevCompletion(editor: AstDocumentEditor) =
  if editor.completions.len > 0:
    editor.selectedCompletion = (editor.selectedCompletion - 1).clamp(0, editor.completions.len - 1)
  else:
    editor.selectedCompletion = 0

proc getNodeAt*(self: AstDocumentEditor, cursor: Cursor, index: int = -1): AstNode =
  return self.node

method canEdit*(self: AstDocumentEditor, document: Document): bool =
  if document of AstDocument: return true
  else: return false

method getEventHandlers*(self: AstDocumentEditor): seq[EventHandler] =
  if self.textEditor != nil:
    return @[self.eventHandler] & self.textEditor.getEventHandlers & @[self.textEditEventHandler]
  return @[self.eventHandler]

method handleDocumentChanged*(self: AstDocumentEditor) =
  logger.log(lvlInfo, fmt"[ast-editor] Document changed")
  self.selectionHistory.clear
  self.selectionFuture.clear
  self.finishEdit false
  for symbol in ctx.globalScope.values:
    discard ctx.newSymbol(symbol)
  self.node = self.document.rootNode[0]

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
  logger.log(lvlInfo, fmt"Undoing {undoOp}")

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
  logger.log(lvlInfo, fmt"Redoing {redoOp}")

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

proc applySelectedCompletion(editor: AstDocumentEditor) =
  if editor.textDocument == nil:
    return

  if editor.completions.len == 0:
    return

  let com = editor.completions[editor.selectedCompletion]
  let completionText = editor.completionText

  logger.log(lvlInfo, fmt"[astedit] Applying completion {editor.selectedCompletion} ({completionText})")

  editor.finishEdit false

  case com.kind
  of SymbolCompletion:
    if ctx.getSymbol(com.id).getSome(symbol):
      editor.node = editor.document.replaceNode(editor.node, AstNode(kind: Identifier, reff: symbol.id))
  of AstCompletion:
    if editor.createDefaultNode(com.nodeKind).getSome(nodeIndex):
      let (newNode, _) = nodeIndex
      discard editor.document.replaceNode(editor.node, newNode)

      if newNode.kind == NumberLiteral:
        newNode.text = completionText
        ctx.updateNode(newNode)
      elif newNode.kind == StringLiteral:
        assert completionText[0] == '"'
        newNode.text = completionText[1..^1]
        ctx.updateNode(newNode)

      editor.node = newNode

      for _, emptyNode in editor.document.nextPreOrderWhere(newNode, (n) => editor.document.shouldEditNode(n), endNode = newNode):
        editor.node = emptyNode
        discard editor.tryEdit editor.node
        break

proc runSelectedFunction(self: AstDocumentEditor) =
  let node = self.node
  if node.kind != ConstDecl or node.len < 1 or node[0].kind != FunctionDefinition:
    logger.log(lvlError, fmt"[asteditor] Can't run non-function definition: {node}")
    return

  let functionType = ctx.computeType(node)
  if functionType.kind == tError:
    logger.log(lvlError, fmt"[asteditor] Function failed to compile: {node}")
    return

  if functionType.kind != tFunction:
    logger.log(lvlError, fmt"[asteditor] Function has wrong type: {node}, type is {functionType}")
    return

  if functionType.paramTypes.len > 0:
    logger.log(lvlError, fmt"[asteditor] Can't call function with arguments directly {node}, type is {functionType}")
    return

  logger.log(lvlInfo, fmt"[asteditor] Calling function {node} ({functionType})")

  let timer = startTimer()

  let fec = ctx.newFunctionExecutionContext(FunctionExecutionContext(node: node[0], arguments: @[]))
  let result = ctx.computeFunctionExecution(fec)
  logger.log(lvlInfo, fmt"[asteditor] Function {node} returned {result} (Took {timer.elapsed.ms}ms)")

proc handleAction(self: AstDocumentEditor, action: string, arg: string): EventResponse =
  logger.log lvlInfo, fmt"[asteditor]: Handle action {action}, '{arg}'"
  case action
  of "cursor.left":
    if self.isEditing: return
    let index = self.node.index
    if index > 0:
      self.node = self.node.parent[index - 1]

  of "cursor.right":
    if self.isEditing: return
    let index = self.node.index
    if index >= 0 and index < self.node.parent.len - 1:
      self.node = self.node.parent[index + 1]

  of "cursor.up":
    if self.isEditing: return
    if self.node != self.document.rootNode and self.node.parent != self.document.rootNode and self.node.parent != nil:
      self.node = self.node.parent

  of "cursor.down":
    if self.isEditing: return
    if self.node.len > 0:
      self.node = self.node[0]

  of "cursor.next":
    if self.isEditing: return
    var node = self.node
    for _, n in self.document.nextPreVisualOrder(self.node):
      if not shouldSelectNode(n):
        continue
      if n != self.node:
        self.node = n
        break

  of "cursor.prev":
    if self.isEditing: return
    var node = self.node
    for n in self.document.prevPostVisualOrder(self.node, gotoChild = false):
      if not shouldSelectNode(n):
        continue
      if n != self.node:
        self.node = n
        break

  of "cursor.next-line":
    if self.isEditing: return
    if self.document.getNextLine(self.node).getSome(next):
      self.node = next

  of "cursor.prev-line":
    if self.isEditing: return
    if self.document.getPrevLine(self.node).getSome(prev):
      self.node = prev

  of "selected.delete":
    if self.isEditing: return
    self.deletedNode = some(self.node)
    self.node = self.document.deleteNode self.node

  of "selected.copy":
    if self.isEditing: return
    self.deletedNode = some(self.node.cloneAndMapIds())

  of "undo":
    if self.isEditing: return
    self.finishEdit false
    if self.document.undo.getSome(node):
      self.node = node

  of "redo":
    if self.isEditing: return
    self.finishEdit false
    if self.document.redo.getSome(node):
      self.node = node

  of "insert-after":
    if self.isEditing: return
    let index = self.node.index
    if self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      if self.document.insertNode(self.node.parent, index + 1, newNode).getSome(node):
        self.node = node

        for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
          self.node = emptyNode
          discard self.tryEdit self.node
          break

      else:
        logger.log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node.parent} at {index + 1}")

  of "insert-before":
    if self.isEditing: return
    let index = self.node.index
    if self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      if self.document.insertNode(self.node.parent, index, newNode).getSome(node):
        self.node = node

        for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
          self.node = emptyNode
          discard self.tryEdit self.node
          break

      else:
        logger.log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node.parent} at {index}")

  of "insert-child":
    if self.isEditing: return
    if self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      if self.document.insertNode(self.node, self.node.len, newNode).getSome(node):
        self.node = node

        for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
          self.node = emptyNode
          discard self.tryEdit self.node
          break

      else:
        logger.log(lvlError, fmt"[astedit] Failed to insert node {newNode} into {self.node} at {self.node.len}")

  of "replace":
    if self.isEditing: return
    if self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      self.node = self.document.replaceNode(self.node, newNode)

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

  of "replace-empty":
    if self.isEditing: return
    if self.node.kind == Empty and self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      self.node = self.document.replaceNode(self.node, newNode)

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

  of "replace-parent":
    if self.isEditing: return
    let node = self.node
    if node.parent == nil or node.parent == self.document.rootNode: return
    let parent = node.parent
    discard self.document.deleteNode(self.node)
    self.node = self.document.replaceNode(parent, node)

  of "wrap":
    if self.isEditing: return
    let typ = ctx.computeType(self.node)

    if self.createNodeFromAction(arg, self.node, typ).getSome(newNodeIndex):
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

  of "edit-next-empty":
    if self.isEditing: return
    for _, emptyNode in self.document.nextPreOrderWhere(self.node, (n) => self.document.shouldEditNode(n)):
      self.node = emptyNode
      discard self.tryEdit self.node
      break

  of "rename":
    if self.isEditing: return
    discard self.tryEdit self.node

  of "apply-rename":
    self.finishEdit(true)

  of "cancel-rename":
    self.finishEdit(false)

  of "prev-completion":
    self.selectPrevCompletion()

  of "next-completion":
    self.selectNextCompletion()

  of "apply-completion":
    self.applySelectedCompletion()

  of "select-prev":
    if self.isEditing: return
    self.selectPrevNode()

  of "select-next":
    if self.isEditing: return
    self.selectNextNode()

  of "goto":
    if self.isEditing: return
    case arg
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

  of "run-selected-function":
    if self.isEditing: return
    self.runSelectedFunction()

  of "toggle-logging":
    ctx.enableLogging = not ctx.enableLogging

  of "toggle-render-selected-value":
    self.renderSelectedNodeValue = not self.renderSelectedNodeValue

  of "select-center-node":
    var nodes: seq[tuple[y: float32, node: VisualNode]] = @[]
    for (layout, offset) in self.lastLayouts:
      for (i, node) in layout.root.nextPreOrder:
        if not isNil(node.node) and node.len > 0:
          let bounds = node.absoluteBounds
          if self.lastBounds.intersects(bounds + vec2(0, offset.y)):
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

  of "scroll":
    self.scrollOffset += arg.parseFloat

  of "dump-context":
    echo "================================================="
    echo ctx.toString
    echo "================================================="

  else:
    logger.log(lvlError, "[textedit] Unknown action '$1 $2'" % [action, arg])

  return Handled

proc handleInput(self: AstDocumentEditor, input: string): EventResponse =
  # logger.log lvlInfo, fmt"[asteditor]: Handle input '{input}'"
  return Ignored

method createWithDocument*(self: AstDocumentEditor, document: Document): DocumentEditor =
  let editor = AstDocumentEditor(eventHandler: nil, document: AstDocument(document), textDocument: nil, textEditor: nil)
  editor.init()
  editor.document.onNodeInserted.add (doc: AstDocument, node: AstNode) => editor.handleNodeInserted(doc, node)

  editor.selectedCompletion = 0
  editor.completions = @[]

  if editor.document.rootNode.len == 0:
    let paramA = newId()
    let paramB = newId()
    let resultId = newId()
    editor.document.rootNode.add makeTree(AstNode) do:
      ConstDecl(text: "add"):
        FunctionDefinition():
          Params():
            LetDecl(id: == paramA, text: "a"):
              Identifier(reff: == IdInt)
              Empty()
            LetDecl(id: == paramB, text: "b"):
              Identifier(reff: == IdInt)
              Empty()
          Identifier(reff: == IdInt)
          NodeList():
            LetDecl(id: == resultId, text: "result"):
              Empty()
              Call():
                Identifier(reff: == IdAdd)
                Identifier(reff: == paramA)
                Identifier(reff: == paramB)
            Identifier(reff: == resultId)

    let addId = editor.document.rootNode.last.id

    editor.document.rootNode.add makeTree(AstNode) do:
      ConstDecl(text: "main"):
        FunctionDefinition():
          Params()
          Identifier(reff: == IdVoid)
          NodeList():
            Call():
              Identifier(reff: == addId)
              NumberLiteral(text: "69")
              NumberLiteral(text: "420")

  for c in editor.document.rootNode.children:
    editor.document.handleNodeInserted c

  ctx.insertNode(editor.document.rootNode)

  editor.node = editor.document.rootNode[0]

  editor.eventHandler = eventHandler2:
    command "<A-LEFT>", "cursor.left"
    command "<A-RIGHT>", "cursor.right"
    command "<A-UP>", "cursor.up"
    command "<A-DOWN>", "cursor.down"
    command "<HOME>", "cursor.home"
    command "<END>", "cursor.end"
    command "<UP>", "cursor.prev-line"
    command "<DOWN>", "cursor.next-line"
    command "<LEFT>", "cursor.prev"
    command "<RIGHT>", "cursor.next"
    command "n", "cursor.prev"
    command "t", "cursor.next"
    command "<S-LEFT>", "cursor.left last"
    command "<S-RIGHT>", "cursor.right last"
    command "<S-UP>", "cursor.up last"
    command "<S-DOWN>", "cursor.down last"
    command "<S-HOME>", "cursor.home last"
    command "<S-END>", "cursor.end last"
    command "<BACKSPACE>", "backspace"
    command "<DELETE>", "delete"
    command "<TAB>", "edit-next-empty"

    command "e", "rename"

    command "ae", "insert-after empty"
    command "an", "insert-after number-literal"
    command "ap", "insert-after deleted"

    command "ie", "insert-before empty"
    command "in", "insert-before number-literal"
    command "ip", "insert-before deleted"

    command "ke", "insert-child empty"
    command "kp", "insert-child deleted"

    command "s", "replace empty"
    command "re", "replace empty"
    command "rn", "replace number-literal"
    command "rf", "replace call-func"
    command "rp", "replace deleted"

    command "rr", "replace-parent"

    command "gd", "goto definition"
    command "gp", "goto prev-usage"
    command "gn", "goto next-usage"
    command "GE", "goto prev-error"
    command "ge", "goto next-error"

    command "<F5>", "run-selected-function"

    command "\"", "replace-empty \""
    command "'", "replace-empty \""

    command "+", "wrap +"
    command "-", "wrap -"
    command "*", "wrap *"
    command "/", "wrap /"
    command "%", "wrap %"
    command "(", "wrap call-func"
    command ")", "wrap call-arg"
    command "{", "wrap {"
    command "=<ENTER>", "wrap ="
    command "==", "wrap =="
    command "!=", "wrap !="
    command "\\<\\>", "wrap <>"
    command "\\<=", "wrap <="
    command "\\>=", "wrap >="
    command "\\<<ENTER>", "wrap <"
    command "\\><ENTER>", "wrap >"
    command "<SPACE>and", "wrap and"
    command "<SPACE>or", "wrap or"

    command "vc", "wrap const-decl"
    command "vl", "wrap let-decl"
    command "vv", "wrap var-decl"

    command "d", "selected.delete"
    command "y", "selected.copy"

    command "u", "undo"
    command "U", "redo"

    command "<C-d>", "scroll -150"
    command "<C-u>", "scroll 150"

    command "<PAGE_DOWN>", "scroll -450"
    command "<PAGE_UP>", "scroll 450"
    command "<C-f>", "select-center-node"

    command "<C-r>", "select-prev"
    command "<C-t>", "select-next"
    command "<C-LEFT>", "select-prev"
    command "<C-RIGHT>", "select-next"
    command "<C-e>l", "toggle-logging"
    command "<C-e>dc", "dump-context"
    command "<C-e>v", "toggle-render-selected-value"

    onAction:
      editor.handleAction action, arg
    onInput:
      editor.handleInput input

  editor.textEditEventHandler = eventHandler2:
    command "<ENTER>", "apply-rename"
    command "<ESCAPE>", "cancel-rename"
    command "<UP>", "prev-completion"
    command "<DOWN>", "next-completion"
    command "<TAB>", "apply-completion"
    onAction:
      editor.handleAction action, arg
    onInput:
      discard input
      Ignored
  return editor