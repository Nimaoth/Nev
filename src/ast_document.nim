import std/[strformat, strutils, algorithm, math, logging, unicode, sequtils, sugar, tables, macros, options, os, deques, sets]
import print, fusion/matching, fuzzy
import util, input, document, document_editor, text_document, events, id, ast_ids, ast
import compiler

var logger = newConsoleLogger()

let typeAddIntInt = newFunctionType(@[intType(), intType()], intType())
let typeSubIntInt = newFunctionType(@[intType(), intType()], intType())
let typeMulIntInt = newFunctionType(@[intType(), intType()], intType())
let typeDivIntInt = newFunctionType(@[intType(), intType()], intType())
let typeAddStringInt = newFunctionType(@[stringType(), intType()], stringType())

proc newFunctionValue(impl: ValueImpl): Value =
  return Value(kind: vkFunction, impl: impl)

let ctx* = newContext()
ctx.enableLogging = false

proc createBinaryIntOperator(operator: proc(a: int, b: int): int): Value =
  return newFunctionValue proc(node: AstNode): Value =
    let leftValue = ctx.computeValue(node[1])
    let rightValue = ctx.computeValue(node[2])

    if leftValue.kind != vkNumber or rightValue.kind != vkNumber:
      echo "left: ", leftValue.kind, ", right: ", rightValue.kind
      return errorValue()
    return Value(kind: vkNumber, intValue: operator(leftValue.intValue, rightValue.intValue))

let funcAddIntInt = createBinaryIntOperator (a: int, b: int) => a + b
let funcSubIntInt = createBinaryIntOperator (a: int, b: int) => a - b
let funcMulIntInt = createBinaryIntOperator (a: int, b: int) => a * b
let funcDivIntInt = createBinaryIntOperator (a: int, b: int) => a div b

let funcAddStringInt = newFunctionValue proc(node: AstNode): Value =
  let leftValue = ctx.computeValue(node[1])
  let rightValue = ctx.computeValue(node[2])
  if leftValue.kind != vkString:
    return errorValue()
  return Value(kind: vkString, stringValue: leftValue.stringValue & $rightValue)

ctx.globalScope.add(IdAdd, NewSymbol(id: IdAdd, kind: skBuiltin, typ: typeAddIntInt, value: funcAddIntInt))
ctx.globalScope.add(IdSub, NewSymbol(id: IdSub, kind: skBuiltin, typ: typeSubIntInt, value: funcSubIntInt))
ctx.globalScope.add(IdMul, NewSymbol(id: IdMul, kind: skBuiltin, typ: typeMulIntInt, value: funcMulIntInt))
ctx.globalScope.add(IdDiv, NewSymbol(id: IdDiv, kind: skBuiltin, typ: typeDivIntInt, value: funcSubIntInt))
ctx.globalScope.add(IdAppendString, NewSymbol(id: IdAppendString, kind: skBuiltin, typ: typeAddStringInt, value: funcAddStringInt))
for symbol in ctx.globalScope.values:
  discard ctx.newNewSymbol(symbol)

proc `$`(ctx: Context): string = ctx.toString

############################################################################################

type Cursor = seq[int]

# Generate new IDs
when false:
  for i in 0..100:
    echo $newId()
    sleep(100)

type
  SymbolKind* = enum
    Regular
    Prefix
    Postfix
    Infix
    Scope
  Symbol* = ref object
    id*: Id
    kind*: SymbolKind
    name*: string
    node*: AstNode
    parent*: Id
    children*: HashSet[Id]
    precedence*: int

type
  UndoOpKind = enum
    Delete
    Replace
    Insert
    TextChange
    SymbolNameChange
  UndoOp = ref object
    kind: UndoOpKind
    parent: AstNode
    idx: int
    node: AstNode
    text: string

type AstDocument* = ref object of Document
  filename*: string
  symbols*: Table[Id, Symbol]
  rootNode*: AstNode

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

  currentlyEditedSymbol*: Symbol
  currentlyEditedNode*: AstNode
  textEditor*: TextDocumentEditor
  textDocument*: TextDocument
  textEditEventHandler*: EventHandler

  completionText: string
  completions*: seq[Completion]
  selectedCompletion*: int

proc `<`(a, b: Completion): bool = a.score < b.score

proc updateCompletions(editor: AstDocumentEditor)
proc getPrevChild*(document: AstDocument, node: AstNode, max: int = -1): Option[AstNode]
proc getNextChild*(document: AstDocument, node: AstNode, min: int = -1): Option[AstNode]

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

proc node*(editor: AstDocumentEditor): AstNode =
  return editor.selectedNode

proc selectPrevNode*(editor: AstDocumentEditor) =
  while editor.selectionHistory.len > 0:
    let node = editor.selectionHistory.popLast
    if node != nil and node.parent != nil and node.base == editor.document.rootNode:
      editor.selectionHistory.addFirst editor.selectedNode
      editor.selectedNode = node
      return

proc selectNextNode*(editor: AstDocumentEditor) =
  while editor.selectionHistory.len > 0:
    let node = editor.selectionHistory.popFirst
    if node != nil and node.parent != nil and node.base == editor.document.rootNode:
      editor.selectionHistory.addLast editor.selectedNode
      editor.selectedNode = node
      return

proc getSymbol*(doc: AstDocument, id: Id): Option[Symbol] =
  let s = doc.symbols.getOrDefault(id, nil)
  if s == nil:
    return none[Symbol]()
  return some(s)

proc getSymbolNameOrEmpty*(doc: AstDocument, id: Id): string =
  if doc.getSymbol(id).getSome(sym):
    return sym.name
  return ""

proc addSymbol*(doc: AstDocument, symbol: Symbol): Symbol =
  if symbol.id == null:
    symbol.id = newId()
  if symbol.parent == null:
    symbol.parent = doc.rootNode.id
  doc.symbols.add(symbol.id, symbol)
  if doc.getSymbol(symbol.parent).getSome(parent):
    parent.children.incl(symbol.id)
  return symbol

proc removeSymbol*(doc: AstDocument, id: Id) =
  if doc.getSymbol(id).getSome(symbol):
    assert symbol.children.len == 0

  doc.symbols.del id

method `$`*(document: AstDocument): string =
  return document.filename

proc newAstDocument*(filename: string = ""): AstDocument =
  new(result)
  result.filename = filename
  result.rootNode = AstNode(kind: NodeList, parent: nil, id: newId())
  result.symbols = initTable[Id, Symbol]()
  result.symbols.add(result.rootNode.id, Symbol(id: result.rootNode.id, parent: null, kind: Scope, name: "::", node: result.rootNode, children: initHashSet[Id]()))
  discard result.addSymbol Symbol(id: IdPrint, name: "print")
  discard result.addSymbol Symbol(id: IdAdd, name: "+", kind: Infix, precedence: 1)
  discard result.addSymbol Symbol(id: IdSub, name: "-", kind: Infix, precedence: 1)
  discard result.addSymbol Symbol(id: IdMul, name: "*", kind: Infix, precedence: 2)
  discard result.addSymbol Symbol(id: IdDiv, name: "/", kind: Infix, precedence: 2)
  discard result.addSymbol Symbol(id: IdMod, name: "%", kind: Infix, precedence: 2)
  discard result.addSymbol Symbol(id: IdNegate, name: "-", kind: Prefix, precedence: 0)
  discard result.addSymbol Symbol(id: IdNot, name: "!", kind: Prefix, precedence: 0)
  discard result.addSymbol Symbol(id: IdDeref, name: "->", kind: Postfix, precedence: 0)
  discard result.addSymbol Symbol(id: IdAppendString, name: "&", kind: Infix, precedence: 0)

# proc `$`*(cursor: Cursor): string =
#   return

method save*(self: AstDocument, filename: string = "") =
  self.filename = if filename.len > 0: filename else: self.filename
  if self.filename.len == 0:
    raise newException(IOError, "Missing filename")

  # writeFile(self.filename, self.content.join "\n")

method load*(self: AstDocument, filename: string = "") =
  let filename = if filename.len > 0: filename else: self.filename
  if filename.len == 0:
    raise newException(IOError, "Missing filename")

  self.filename = filename

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
    elif n.next.getSome(ne):
      n = ne
      idx = -1
    elif n.parent != nil and n.parent != endNode:
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
  var idx = -1
  var i = 0
  var gotoChild = true

  while n != nil:
    echo gotoChild, ", ", n
    if gotoChild and n.len > 0:
      n = self.getNextChild(n, -1).get
      yield (i, n)
      gotoChild = true
    elif n.parent != nil and self.getNextChild(n.parent, n.index).getSome(ne):
    # elif n.prev.getSome(ne):
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
    # echo gotoChild, ", ", n
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
  echo "Node inserted: ", node

  for _, node in doc.nextPreOrder(node, node):
    var parent = node.findWithParentRec(NodeList).get.parent
    echo "handle ", node, ", parent  = ", parent

    if node.kind == NodeList:
      if node.id == null:
        node.id = newId()
      if doc.getSymbol(node.id).getSome(symbol):
        symbol.node = node
        symbol.kind = Scope
      else:
        discard doc.addSymbol Symbol(id: node.id, parent: null, kind: Scope, name: "::", node: node, children: initHashSet[Id]())
      doc.getSymbol(parent.id).get.children.incl node.id

      parent = node

    elif node.kind == Declaration:
      if node.id == null:
        node.id = newId()
      if doc.getSymbol(node.id).getSome(symbol):
        symbol.parent = parent.id
        symbol.node = node
      else:
        discard doc.addSymbol Symbol(id: node.id, parent: parent.id, kind: Regular, name: node.text, node: node)
      doc.getSymbol(parent.id).get.children.incl node.id

  ctx.insertNode(node)

proc insertNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode]

proc handleNodeDelete*(doc: AstDocument, node: AstNode) =
  for child in node.children:
    doc.handleNodeDelete child

  ctx.deleteNode(node)

  if node.kind in {Declaration, NodeList} and doc.getSymbol(node.id).getSome(symbol):
    assert symbol.children.len == 0

    # Store the symbol text in the node so that when we reinsert the node it has the original name
    node.text = symbol.name

    if doc.getSymbol(symbol.parent).getSome(parent):
      parent.children.excl node.id

    doc.removeSymbol(symbol.id)

proc handleTextDocumentChanged*(self: AstDocumentEditor) =
  self.updateCompletions()

proc editSymbol*(self: AstDocumentEditor, symbol: Symbol) =
  self.currentlyEditedNode = nil
  self.currentlyEditedSymbol = symbol
  self.textDocument = newTextDocument()
  self.textDocument.content = @[symbol.name]
  self.textEditor = newTextEditor(self.textDocument)
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false
  self.textDocument.textChanged = (doc: Document) => self.handleTextDocumentChanged()
  self.updateCompletions()

proc editNode*(self: AstDocumentEditor, node: AstNode) =
  self.currentlyEditedNode = node
  self.currentlyEditedSymbol = nil
  self.textDocument = newTextDocument()
  self.textDocument.content = node.text.splitLines
  self.textEditor = newTextEditor(self.textDocument)
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false
  self.textDocument.textChanged = (doc: Document) => self.handleTextDocumentChanged()
  self.updateCompletions()

proc tryEdit*(self: AstDocumentEditor, node: AstNode): bool =
  # todo: use reff?
  if self.document.getSymbol(node.id).getSome(sym):
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
    if self.currentlyEditedSymbol != nil:
      self.document.undoOps.add UndoOp(kind: SymbolNameChange, node: AstNode(kind: Empty, id: self.currentlyEditedSymbol.id), text: self.currentlyEditedSymbol.name)
      self.currentlyEditedSymbol.name = self.textDocument.content.join
    elif self.currentlyEditedNode != nil:
      self.document.undoOps.add UndoOp(kind: TextChange, node: self.currentlyEditedNode, text: self.currentlyEditedNode.text)
      self.currentlyEditedNode.text = self.textDocument.content.join "\n"
      ctx.updateNode(self.currentlyEditedNode)

  self.textEditor = nil
  self.textDocument = nil
  self.currentlyEditedSymbol = nil
  self.currentlyEditedNode = nil
  self.updateCompletions()

proc getCompletions*(editor: AstDocumentEditor, text: string, contextNode: Option[AstNode] = none[AstNode]()): seq[Completion] =
  result = @[]

  # Find everything matching text
  if contextNode.isNone or contextNode.get.kind == Identifier or contextNode.get.kind == Empty:
    for symbol in editor.document.symbols.values:
      # todo: use reff?
      if symbol.kind == Scope or symbol.parent != editor.document.rootNode.id:
        continue
      let score = fuzzyMatch(text, symbol.name)
      result.add Completion(kind: SymbolCompletion, score: score, id: symbol.id)

  if contextNode.getSome(node) and node.kind == Empty:
    result.add Completion(kind: AstCompletion, nodeKind: If, name: "if", score: fuzzyMatch(text, "if"))
    result.add Completion(kind: AstCompletion, nodeKind: Declaration, name: "let", score: fuzzyMatch(text, "let"))
    result.add Completion(kind: AstCompletion, nodeKind: StringLiteral, name: "string literal", score: if text.startsWith("\""): 1.1 else: 0)
    result.add Completion(kind: AstCompletion, nodeKind: NodeList, name: "block", score: fuzzyMatch(text, "{"))

    var scope = node.findWithParentRec(NodeList).get.parent
    while scope != editor.document.rootNode:
      # todo: use reff?
      if editor.document.getSymbol(scope.id).getSome(scopeSym):
        for childSymId in scopeSym.children:
          if editor.document.getSymbol(childSymId).getSome(childSym):
            let score = fuzzyMatch(text, childSym.name)
            result.add Completion(kind: SymbolCompletion, score: score, id: childSym.id)

      scope = scope.findWithParentRec(NodeList).get.parent

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
  discard

proc getNextChild*(document: AstDocument, node: AstNode, min: int = -1): Option[AstNode] =
  if node.len == 0:
    return none[AstNode]()

  case node
  of Call():
    # todo: use reff?
    if document.getSymbol(node[0].reff).getSome(symbol):
      case symbol.kind
      of Infix:
        if min == 0: return some(node[2])
        if min == 1: return some(node[0])
        if min == 2: return none[AstNode]()
        return some(node[1])
      of Postfix:
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

  while node.kind == Call or node.kind == NodeList:
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
    # todo: use reff?
    if document.getSymbol(node[0].reff).getSome(symbol):
      case symbol.kind
      of Infix:
        if max == 0: return some(node[1])
        if max == 1: return none[AstNode]()
        if max == 2: return some(node[0])
        return some(node[2])
      of Postfix:
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

  # var node = node
  # var idx = -1
  # var down = true

  # if document.getPrevChild(node, max).getSome(child):
  #   idx = -1
  #   node = child
  #   down = true
  # elif node.parent != nil:
  #   idx = node.index
  #   node = node.parent
  #   down = false
  # else:
  #   return some(node)

  # while node.kind == Call or node.kind == NodeList:
  #   if document.getPrevChild(node, idx).getSome(child):
  #     idx = -1
  #     node = child
  #     down = true
  #   elif node.parent != nil:
  #     idx = node.index
  #     node = node.parent
  #     down = false
  #   else:
  #     break

  # return some(node)

proc getNextLine*(document: AstDocument, node: AstNode): Option[AstNode] =
  for _, n in document.nextPreOrder(node):
    if n == node:
      continue
    if n.parent != nil and n.parent.kind == NodeList:
      if n.kind == NodeList and n.len == 0:
        return some(n)
      elif n.kind != NodeList:
        return some(n)

  return none[AstNode]()

proc getPrevLine*(document: AstDocument, node: AstNode): Option[AstNode] =
  for n in document.prevPostOrder(node):
    if n == node:
      continue
    if n.parent != nil and n.parent.kind == NodeList:
      if n.kind == NodeList and n.len == 0:
        return some(n)
      elif n.kind != NodeList:
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

  case node.parent
  of If():
    return document.replaceNode(node, AstNode(kind: Empty))
  of Declaration():
    return document.replaceNode(node, AstNode(kind: Empty))
  of Call():
    # todo: use reff?
    if document.getSymbol(node.parent[0].id).getSome(symbol):
      let idx = node.index
      let isFixed = case symbol.kind
      of Infix: idx in 0..2
      of Prefix: idx in 0..1
      of Postfix: idx in 0..1
      of Regular: idx in 0..0
      of Scope: false
      if isFixed:
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

  echo fmt"insertNode {node}, {index}, {newNode}"
  case node
  of If():
    return none[AstNode]()
  of Declaration():
    return none[AstNode]()
  of Call():
    # todo: use reff?
    if document.getSymbol(node.parent[0].id).getSome(symbol):
      let idx = node.index
      let isFixed = case symbol.kind
      of Infix: idx in 0..2
      of Prefix: idx in 0..1
      of Postfix: idx in 0..1
      of Regular: idx in 0..0
      of Scope: false
      if isFixed:
        return none[AstNode]()

  document.undoOps.add UndoOp(kind: Insert, parent: node, idx: index, node: newNode)
  document.redoOps = @[]
  node.insert(newNode, index)
  document.handleNodeInserted newNode
  return some(newNode)

proc insertOrReplaceNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode] =
  case node
  of If():
    return some document.replaceNode(node[index], newNode)
  of Declaration():
    return some document.replaceNode(node[index], newNode)
  of Call():
    # todo: use reff?
    if document.getSymbol(node.parent[0].id).getSome(symbol):
      let idx = node.index
      let isFixed = case symbol.kind
      of Infix: idx in 0..2
      of Prefix: idx in 0..1
      of Postfix: idx in 0..1
      of Regular: idx in 0..0
      of Scope: false
      if isFixed:
        return some document.replaceNode(node[index], newNode)

  document.undoOps.add UndoOp(kind: Insert, parent: node, idx: index, node: newNode)
  document.redoOps = @[]
  node.insert(newNode, index)
  document.handleNodeInserted newNode
  return some(newNode)

proc undo*(document: AstDocument): Option[AstNode] =
  if document.undoOps.len == 0:
    return none[AstNode]()

  let undoOp = document.undoOps.pop
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
    # todo: use reff?
    if document.getSymbol(undoOp.node.id).getSome(symbol):
      document.redoOps.add UndoOp(kind: SymbolNameChange, node: undoOp.node, text: symbol.name)
      symbol.name = undoOp.text
  of TextChange:
    document.redoOps.add UndoOp(kind: TextChange, node: undoOp.node, text: undoOp.node.text)
    undoOp.node.text = undoOp.text

  return none[AstNode]()

proc redo*(document: AstDocument): Option[AstNode] =
  if document.redoOps.len == 0:
    return none[AstNode]()

  let redoOp = document.redoOps.pop
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
    # todo: use reff?
    if document.getSymbol(redoOp.node.id).getSome(symbol):
      document.undoOps.add UndoOp(kind: SymbolNameChange, node: redoOp.node, text: symbol.name)
      symbol.name = redoOp.text
  of TextChange:
    document.undoOps.add UndoOp(kind: TextChange, node: redoOp.node, text: redoOp.node.text)
    redoOp.node.text = redoOp.text

  return none[AstNode]()

proc createNodeFromAction*(editor: AstDocumentEditor, arg: string, node: AstNode, typ: Type): Option[(AstNode, int)] =
  case arg
  of "empty":
    return some((AstNode(kind: Empty, id: newId(), text: ""), 0))
  of "identifier":
    return some((AstNode(kind: Identifier, text: "todo"), 0))
  of "number-literal":
    return some((AstNode(kind: NumberLiteral, text: ""), 0))
  of "declaration":
    let node = makeTree(AstNode) do:
      Declaration(id: == newId()):
        Empty()
    return some (node, 0)

  of "call-func":
    # todo: use reff?
    let kind = if editor.document.getSymbol(node.id).getSome(symbol):
      symbol.kind
    else:
      Regular

    let node = case kind:
      of Prefix, Postfix, Regular:
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
  of Declaration:
    let node = makeTree(AstNode) do:
      Declaration(id: == newId()):
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
  if node.kind == Declaration:
    # todo: use reff?
    return doc.getSymbol(node.id).getSome(symbol) and symbol.name == ""
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
    # todo: use reff?
    if editor.document.getSymbol(com.id).getSome(symbol):
      editor.node = editor.document.replaceNode(editor.node, AstNode(kind: Identifier, id: symbol.id))
  of AstCompletion:
    if editor.createDefaultNode(com.nodeKind).getSome(nodeIndex):
      let (newNode, _) = nodeIndex
      discard editor.document.replaceNode(editor.node, newNode)
      editor.node = newNode
      echo nodeIndex

      if newNode.kind == NumberLiteral:
        newNode.text = completionText
      elif newNode.kind == StringLiteral:
        assert completionText[0] == '"'
        newNode.text = completionText[1..^1]

      for _, emptyNode in editor.document.nextPreOrderWhere(newNode, (n) => editor.document.shouldEditNode(n), endNode = newNode):
        echo emptyNode
        editor.node = emptyNode
        discard editor.tryEdit editor.node
        break
  else:
    discard

proc handleAction(self: AstDocumentEditor, action: string, arg: string): EventResponse =
  echo "handleAction ", action, " '", arg, "'"
  case action
  of "cursor.left":
    let index = self.node.index
    if index > 0:
      self.node = self.node.parent[index - 1]
  of "cursor.right":
    let index = self.node.index
    if index >= 0 and index < self.node.parent.len - 1:
      self.node = self.node.parent[index + 1]

  of "cursor.up":
    if self.node != self.document.rootNode and self.node.parent != self.document.rootNode and self.node.parent != nil:
      self.node = self.node.parent

  of "cursor.down":
    if self.node.len > 0:
      self.node = self.node[0]

  of "cursor.next":
    var node = self.node
    # let nextChild = self.document.getNextChildRec node
    # if nextChild.getSome(child):
    #   self.node = child
    for _, n in self.document.nextPreVisualOrder(self.node):
      if n.kind == Call or n.kind == NodeList:
        continue
      if n != self.node:
        self.node = n
        break

  of "cursor.prev":
    var node = self.node
    for n in self.document.prevPostVisualOrder(self.node, gotoChild = false):
      if n.kind == Call or n.kind == NodeList:
        continue
      if n != self.node:
        self.node = n
        break

  of "cursor.next-line":
    if self.document.getNextLine(self.node).getSome(next):
      self.node = next

  of "cursor.prev-line":
    if self.document.getPrevLine(self.node).getSome(prev):
      self.node = prev

  of "selected.delete":
    self.node = self.document.deleteNode self.node

  of "undo":
    self.finishEdit false
    if self.document.undo.getSome(node):
      self.node = node

  of "redo":
    self.finishEdit false
    if self.document.redo.getSome(node):
      self.node = node

  of "insert-after":
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
        logger.log(lvlError, fmt"Failed to insert node {newNode} into {self.node.parent} at {index + 1}")

  of "insert-before":
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
        logger.log(lvlError, fmt"Failed to insert node {newNode} into {self.node.parent} at {index}")

  of "replace":
    if self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      self.node = self.document.replaceNode(self.node, newNode)

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

  of "replace-empty":
    if self.node.kind == Empty and self.createNodeFromAction(arg, self.node, errorType()).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      self.node = self.document.replaceNode(self.node, newNode)

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

  of "wrap":
    let typ = ctx.computeType(self.node)

    if self.createNodeFromAction(arg, self.node, typ).getSome(newNodeIndex):
      var (newNode, index) = newNodeIndex
      let oldNode = self.node
      self.node = self.document.replaceNode(self.node, newNode)
      for i, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        if i == index:
          self.node = self.document.replaceNode(emptyNode, oldNode)
          break
      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => self.document.shouldEditNode(n), endNode = newNode):
        self.node = emptyNode
        discard self.tryEdit self.node
        break

  of "edit-next-empty":
    for _, emptyNode in self.document.nextPreOrderWhere(self.node, (n) => self.document.shouldEditNode(n)):
      self.node = emptyNode
      discard self.tryEdit self.node
      break

  of "rename":
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
    self.selectPrevNode()

  of "select-next":
    self.selectNextNode()

  of "goto":
    case arg
    of "definition":
      # todo: use reff?
      if self.document.getSymbol(self.node.id).getSome(sym):
        if sym.node != nil and sym.node != self.document.rootNode:
          self.node = sym.node
    of "next-usage":
      # todo: use reff?
      let id = self.node.id
      for _, n in self.document.nextPreOrderWhere(self.node, n => n != self.node and n.id == id):
        self.node = n
        break
    of "prev-usage":
      # todo: use reff?
      let id = self.node.id
      for n in self.document.prevPostOrder(self.node):
        if n != self.node and n.id == id:
          self.node = n
          break

  of "toggle-logging":
    ctx.enableLogging = not ctx.enableLogging

  else:
    logger.log(lvlError, "[textedit] Unknown action '$1 $2'" % [action, arg])

  return Handled

proc handleInput(self: AstDocumentEditor, input: string): EventResponse =
  echo "handleInput '", input, "'"
  return Handled

method createWithDocument*(self: AstDocumentEditor, document: Document): DocumentEditor =
  let editor = AstDocumentEditor(eventHandler: nil, document: AstDocument(document), textDocument: nil, textEditor: nil)
  editor.init()

  editor.selectedCompletion = 0
  editor.completions = @[]

  if editor.document.rootNode.len == 0:
    let node = makeTree(AstNode):
      Declaration(id: == newId(), text: "foo"):
        Call():
      #     Identifier(reff: == IdPrint)
      #     StringLiteral(text: "hi")
      #     Call:
      #       Identifier(reff: == IdMul)
      #       Call:
      #         Identifier(reff: == IdNegate)
      #         NumberLiteral(text: "123456")
      #       Call:
      #         Identifier(reff: == IdDiv)
      #         StringLiteral(text: "")
      #         NumberLiteral(text: "42069")
      #     Identifier(reff: == IdAdd)
      #     Call:
      #       Identifier(reff: == IdDeref)
      #       Identifier(reff: == IdPrint)
          Identifier(reff: == IdMul)
          Call():
            Identifier(reff: == IdAdd)
            NumberLiteral(text: "1")
            NumberLiteral(text: "2")
          NumberLiteral(text: "3")

    editor.document.rootNode.add node

    editor.document.rootNode.add makeTree(AstNode) do:
      # If:
      #   Call:
      #     Empty(text: "bar")
      #     Identifier(reff: == node.id)
      #     StringLiteral(text: "bar")
      #   NodeList:
      #     Call:
      #       Identifier(reff: == IdPrint)
      #       StringLiteral(text: "hi")
      #       Call:
      #         Identifier(reff: == IdMul)
      #         Call:
      #           Identifier(reff: == IdNegate)
      #           NumberLiteral(text: "123456")
      #         Call:
      #           Identifier(reff: == IdDiv)
      #           StringLiteral(text: "")
      #           NumberLiteral(text: "42069")
      #       Identifier(reff: == IdAdd)
      #       Call:
      #         Identifier(reff: == IdDeref)
      #         Identifier(reff: == IdPrint)
      #     Call:
      #       Identifier(reff: == IdDeref)
      #       Identifier(reff: == node.id)
      Declaration(text: "bar"):
        Call():
          Identifier(reff: == IdAdd)
          Identifier(reff: == node.id)
          NumberLiteral(text: "4")

    editor.document.rootNode.add makeTree(AstNode) do:
    #   Call:
    #     Identifier(reff: == IdDeref)
    #     Identifier(reff: == node.id)
      Declaration(text: "baz"):
        Call():
          Identifier(reff: == IdAdd)
          Identifier(reff: == editor.document.rootNode.last.id)
          NumberLiteral(text: "4")

  editor.node = editor.document.rootNode[0]
  for c in editor.document.rootNode.children:
    editor.document.handleNodeInserted c

  ctx.insertNode(editor.document.rootNode)

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
    command "<ENTER>", "editor.insert \n"
    command "<SPACE>", "editor.insert  "
    command "<BACKSPACE>", "backspace"
    command "<DELETE>", "delete"
    command "<TAB>", "edit-next-empty"

    command "rr", "rename"
    command "e", "rename"

    command "ae", "insert-after empty"
    command "an", "insert-after number-literal"
    command "ad", "insert-after declaration"
    command "a+", "insert-after +"
    command "af", "insert-after call-func"

    command "ie", "insert-before empty"
    command "in", "insert-before number-literal"
    command "id", "insert-before declaration"
    command "i+", "insert-before +"
    command "if", "insert-before call-func"

    command "re", "replace empty"
    command "rn", "replace number-literal"
    command "rd", "replace declaration"
    command "r+", "replace +"
    command "rf", "replace call-func"

    command "gd", "goto definition"
    command "gn", "goto next-usage"
    command "gp", "goto prev-usage"

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

    command "d", "selected.delete"

    command "u", "undo"
    command "U", "redo"

    command "<C-LEFT>", "select-prev"
    command "<C-RIGHT>", "select-next"
    command "<C-e>l", "toggle-logging"

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
      Ignored
  return editor