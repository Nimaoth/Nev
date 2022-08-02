import std/[strformat, strutils, algorithm, math, logging, unicode, sequtils, sugar, tables, macros, options, os]
import print, fusion/matching
import input, document, document_editor, text_document, events, id, ast_ids

var logger = newConsoleLogger()

template getSome*[T](opt: Option[T], injected: untyped): bool =
  ((let o = opt; o.isSome())) and ((let injected {.inject.} = o.get(); true))

type Cursor = seq[int]

type
  AstNodeKind* = enum
    Empty
    Identifier
    NumberLiteral
    StringLiteral
    Declaration
    NodeList
    Call
    If

  AstNode* = ref object
    parent*: AstNode
    id*: Id
    kind*: AstNodeKind
    text*: string
    children*: seq[AstNode]

func add(node: AstNode, child: AstNode) =
  child.parent = node
  node.children.add child

func insert(node: AstNode, child: AstNode, idx: int) =
  child.parent = node
  node.children.insert child, idx

# Generate new IDs
when false:
  for i in 0..100:
    echo $newId()
    sleep(100)

type
  OperatorKind* = enum
    Regular
    Prefix
    Postfix
    Infix
  Symbol* = ref object
    id*: Id
    name*: string
    node*: AstNode
    opKind*: OperatorKind

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
  globalScope*: Table[Id, Symbol]
  rootNode*: AstNode

  undoOps*: seq[UndoOp]
  redoOps*: seq[UndoOp]

type AstDocumentEditor* = ref object of DocumentEditor
  document*: AstDocument
  cursor*: Cursor
  node*: AstNode

  currentlyEditedSymbol*: Symbol
  currentlyEditedNode*: AstNode
  textEditor*: TextDocumentEditor
  textDocument*: TextDocument
  textEditEventHandler*: EventHandler

func `[]`*(node: AstNode, index: int): AstNode =
  return node.children[index]

func len*(node: AstNode): int =
  return node.children.len

func index*(node: AstNode): int =
  if node.parent == nil:
    return -1
  return node.parent.children.find node

func next*(node: AstNode): Option[AstNode] =
  if node.parent == nil:
    return none[AstNode]()
  let i = node.index
  if i >= node.parent.len - 1:
    return none[AstNode]()
  return some(node.parent[i + 1])

func prev*(node: AstNode): Option[AstNode] =
  if node.parent == nil:
    return none[AstNode]()
  let i = node.index
  if i <= 0:
    return none[AstNode]()
  return some(node.parent[i - 1])

func lastOrSelf*(node: AstNode): AstNode =
  if node.len > 0:
    return node[node.len - 1]
  return node

proc `[]=`(node: AstNode, index: int, newNode: AstNode) =
  newNode.parent = node
  node.children[index] = newNode

func delete(node: AstNode, index: int): AstNode =
  if index < 0 or index >= node.len:
    return node
  case node
  of If():
    if index == 0:
      node[0] = AstNode(kind: Empty)
      return node[0]
    elif index == 1:
      node[1] = AstNode(kind: Empty)
      return node[1]
    else:
      return node
  of Declaration():
    if index == 0:
      node[0] = AstNode(kind: Empty)
      return node[0]
    else:
      return node
  of Call():
    if index == 0:
      node[0] = AstNode(kind: Empty)
      return node[0]
  else:
    discard

  node.children.delete index
  if index < node.len:
    return node[index]
  elif node.len > 0:
    return node[index - 1]
  else:
    return node

func path*(node: AstNode): seq[int] =
  result = @[]
  var node = node
  while node.parent != nil:
    result.add node.index
    node = node.parent
  result.reverse

proc `$`(node: AstNode): string =
  case node
  of Declaration():
    result = "Declaration(id: " & $node.id & "):"
    if node.len > 0:
      result.add "\n"
      result.add indent($node[0], 2)

  of Call():
    result = "Call():"
    for child in node.children:
      result.add "\n"
      result.add indent($child, 2)

  of If():
    result = "If()"
    for child in node.children:
      result.add "\n"
      result.add indent($child, 2)

  of NodeList():
    result = "NodeList()"
    for child in node.children:
      result.add "\n"
      result.add indent($child, 2)

  of StringLiteral():
    result = "StringLiteral(text: '" & node.text & "')"

  of Identifier():
    result = "Identifier(id: " & $node.id & ", text: '" & node.text & "')"

  of Empty():
    result = "Empty()"

  else:
    return "other"

proc addSymbol*(doc: AstDocument, symbol: Symbol): Symbol =
  doc.globalScope.add symbol.id, symbol
  return symbol

proc getSymbol*(doc: AstDocument, id: Id): Option[Symbol] =
  let symbol = doc.globalScope.getOrDefault(id, nil)
  if symbol == nil:
    return none[Symbol]()
  return some(symbol)

method `$`*(document: AstDocument): string =
  return document.filename

proc newAstDocument*(filename: string = ""): AstDocument =
  new(result)
  result.filename = filename
  discard result.addSymbol Symbol(id: IdPrint, name: "print")
  discard result.addSymbol Symbol(id: IdAdd, name: "+", opKind: Infix)
  discard result.addSymbol Symbol(id: IdSub, name: "-", opKind: Infix)
  discard result.addSymbol Symbol(id: IdMul, name: "*", opKind: Infix)
  discard result.addSymbol Symbol(id: IdDiv, name: "/", opKind: Infix)
  discard result.addSymbol Symbol(id: IdMod, name: "%", opKind: Infix)
  discard result.addSymbol Symbol(id: IdNegate, name: "-", opKind: Prefix)
  discard result.addSymbol Symbol(id: IdNot, name: "!", opKind: Prefix)
  discard result.addSymbol Symbol(id: IdDeref, name: "->", opKind: Postfix)

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

  # let file = readFile(self.filename)
  # self.content = collect file.splitLines

proc editSymbol*(self: AstDocumentEditor, symbol: Symbol) =
  self.currentlyEditedNode = nil
  self.currentlyEditedSymbol = symbol
  self.textDocument = newTextDocument()
  self.textDocument.content = @[symbol.name]
  self.textEditor = newTextEditor(self.textDocument)
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false

proc editNode*(self: AstDocumentEditor, node: AstNode) =
  self.currentlyEditedNode = node
  self.currentlyEditedSymbol = nil
  self.textDocument = newTextDocument()
  self.textDocument.content = node.text.splitLines
  self.textEditor = newTextEditor(self.textDocument)
  self.textEditor.renderHeader = false
  self.textEditor.fillAvailableSpace = false

proc tryEdit*(self: AstDocumentEditor, node: AstNode): bool =
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

  self.textEditor = nil
  self.textDocument = nil
  self.currentlyEditedSymbol = nil
  self.currentlyEditedNode = nil

proc getNodeAt*(self: AstDocumentEditor, cursor: Cursor, index: int = -1): AstNode =
  return self.node
  # var nodes = self.document.nodes

  # let actualIndex = if index > 0: index else: cursor.len + index

  # # echo $cursor, ": ", actualIndex

  # for i, nodeIndex in cursor:
  #   if nodes.len == 0 or nodeIndex < 0 or nodeIndex >= nodes.len:
  #     break

  #   if i == actualIndex:
  #     return some(nodes[nodeIndex])
  #   else:
  #     nodes = nodes[nodeIndex].children

  # return none[AstNode]()

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
    if document.getSymbol(node[0].id).getSome(symbol):
      case symbol.opKind
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
  # var node = node
  # var min = min
  # while document.getNextChild(node, min).getSome(child):
  #   if child.kind == Call:
  #     node = child
  #     min = -1
  #     continue
  #   return some(child)

  # return none[AstNode]()
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
    if document.getSymbol(node[0].id).getSome(symbol):
      case symbol.opKind
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
  var node = node
  var idx = -1
  var down = true

  if document.getPrevChild(node, max).getSome(child):
    idx = -1
    node = child
    down = true
  elif node.parent != nil:
    idx = node.index
    node = node.parent
    down = false
  else:
    return some(node)

  while node.kind == Call or node.kind == NodeList:
    if document.getPrevChild(node, idx).getSome(child):
      idx = -1
      node = child
      down = true
    elif node.parent != nil:
      idx = node.index
      node = node.parent
      down = false
    else:
      break

  return some(node)

proc findChildRec*(node: AstNode, kind: AstNodeKind): Option[AstNode] =
  for c in node.children:
    if c.kind == kind:
      return some(c)
    if c.findChildRec(kind).getSome(c):
      return some(c)

  return none[AstNode]()

# Returns a the closest parent node which has itself a parent with kind
proc findWithParentRec*(node: AstNode, kind: AstNodeKind): Option[AstNode] =
  if node.parent == nil:
    return none[AstNode]()
  if node.parent.kind == kind:
    return some(node)
  return node.parent.findWithParentRec(kind)

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

  document.undoOps.add UndoOp(kind: Replace, parent: node.parent, idx: node.index, node: node)
  document.redoOps = @[]
  node.parent[node.index] = newNode
  return newNode

proc deleteNode*(document: AstDocument, node: AstNode): AstNode =
  if node.parent == nil:
    raise newException(Defect, "lol")

  case node.parent
  of If():
    return document.replaceNode(node, AstNode(kind: Empty))
  of Declaration():
    return document.replaceNode(node, AstNode(kind: Empty))
  of Call():
    if document.getSymbol(node.parent[0].id).getSome(symbol):
      let idx = node.index
      let isFixed = case symbol.opKind
      of Infix: idx in 0..2
      of Prefix: idx in 0..1
      of Postfix: idx in 0..1
      of Regular: idx in 0..0
      if isFixed:
        return document.replaceNode(node, AstNode(kind: Empty))

  document.undoOps.add UndoOp(kind: Delete, parent: node.parent, idx: node.index, node: node)
  document.redoOps = @[]
  return node.parent.delete node.index

proc insertNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode] =
  echo fmt"insertNode {node}, {index}, {newNode}"
  case node
  of If():
    return none[AstNode]()
  of Declaration():
    return none[AstNode]()
  of Call():
    if document.getSymbol(node.parent[0].id).getSome(symbol):
      let idx = node.index
      let isFixed = case symbol.opKind
      of Infix: idx in 0..2
      of Prefix: idx in 0..1
      of Postfix: idx in 0..1
      of Regular: idx in 0..0
      if isFixed:
        return none[AstNode]()

  node.insert(newNode, index)
  document.undoOps.add UndoOp(kind: Insert, parent: node, idx: index, node: newNode)
  document.redoOps = @[]
  return some(newNode)

proc insertOrReplaceNode*(document: AstDocument, node: AstNode, index: int, newNode: AstNode): Option[AstNode] =
  case node
  of If():
    return some document.replaceNode(node[index], newNode)
  of Declaration():
    return some document.replaceNode(node[index], newNode)
  of Call():
    if document.getSymbol(node.parent[0].id).getSome(symbol):
      let idx = node.index
      let isFixed = case symbol.opKind
      of Infix: idx in 0..2
      of Prefix: idx in 0..1
      of Postfix: idx in 0..1
      of Regular: idx in 0..0
      if isFixed:
        return some document.replaceNode(node[index], newNode)

  node.insert(newNode, index)
  document.undoOps.add UndoOp(kind: Insert, parent: node, idx: index, node: newNode)
  document.redoOps = @[]
  return some(newNode)


proc undo*(document: AstDocument): Option[AstNode] =
  if document.undoOps.len == 0:
    return none[AstNode]()

  let undoOp = document.undoOps.pop
  case undoOp.kind:
  of Delete:
    undoOp.parent.insert(undoOp.node, undoOp.idx)
    document.redoOps.add undoOp
    return some(undoOp.node)
  of Replace:
    let oldNode = undoOp.parent[undoOp.idx]
    undoOp.parent[undoOp.idx] = undoOp.node
    document.redoOps.add UndoOp(kind: Replace, parent: undoOp.parent, idx: undoOp.idx, node: oldNode)
    return some(undoOp.node)
  of Insert: # @todo
    discard undoOp.parent.delete undoOp.idx
    document.redoOps.add undoOp
    return some(undoOp.parent)
  of SymbolNameChange:
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
    return some(redoOp.parent.delete redoOp.idx)
  of Replace:
    let oldNode = redoOp.parent[redoOp.idx]
    redoOp.parent[redoOp.idx] = redoOp.node
    document.undoOps.add UndoOp(kind: Replace, parent: redoOp.parent, idx: redoOp.idx, node: oldNode)
    return some(redoOp.node)
  of Insert: # @todo
    redoOp.parent.insert redoOp.node, redoOp.idx
    document.undoOps.add redoOp
    return some(redoOp.node)
  of SymbolNameChange:
    if document.getSymbol(redoOp.node.id).getSome(symbol):
      document.undoOps.add UndoOp(kind: SymbolNameChange, node: redoOp.node, text: symbol.name)
      symbol.name = redoOp.text
  of TextChange:
    document.undoOps.add UndoOp(kind: TextChange, node: redoOp.node, text: redoOp.node.text)
    redoOp.node.text = redoOp.text

  return none[AstNode]()

proc createNodeFromAction*(editor: AstDocumentEditor, arg: string): Option[(AstNode, int)] =
  case arg
  of "empty":
    return some((AstNode(kind: Empty, id: newId(), text: "new empty"), 0))
  of "identifier":
    return some((AstNode(kind: Identifier, text: "todo"), 0))
  of "number-literal":
    return some((AstNode(kind: NumberLiteral, text: "123"), 0))
  of "declaration":
    return some((AstNode(kind: Declaration, id: newId(), children: @[AstNode(kind: Empty, text: "name"), AstNode(kind: Empty, text: "value")]), 0))

  of "call-func":
    let node = makeTree(AstNode) do:
      Call:
        Empty()
    return some (node, 0)

  of "call-arg":
    let node = makeTree(AstNode) do:
      Call:
        Empty()
        Empty()
    return some (node, 1)

  of "+":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(id: == IdAdd)
        Empty()
        Empty()
    return some (node, 0)
  of "-":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(id: == IdSub)
        Empty()
        Empty()
    return some (node, 0)
  of "*":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(id: == IdMul)
        Empty()
        Empty()
    return some (node, 0)
  of "/":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(id: == IdDiv)
        Empty()
        Empty()
    return some (node, 0)
  of "%":
    let node = makeTree(AstNode) do:
      Call:
        Identifier(id: == IdMod)
        Empty()
        Empty()
    return some (node, 0)

  of "\"":
    let node = makeTree(AstNode) do:
        StringLiteral(text: "")
    return some (node, 0)

  else:
    return none[(AstNode, int)]()

proc handleAction(self: AstDocumentEditor, action: string, arg: string): EventResponse =
  echo "handleAction ", action, " '", arg, "', ", self.cursor
  case action
  of "cursor.left":
    if self.node != self.document.rootNode and self.node.parent != self.document.rootNode and self.node.parent != nil:
      self.node = self.node.parent
  of "cursor.right":
    if self.node.len > 0:
      self.node = self.node[0]

  of "cursor.up":
    let index = self.node.index
    if index > 0:
      self.node = self.node.parent[index - 1]

  of "cursor.down":
    let index = self.node.index
    if index >= 0 and index < self.node.parent.len - 1:
      self.node = self.node.parent[index + 1]

  of "cursor.next":
    var node = self.node
    let nextChild = self.document.getNextChildRec node
    if nextChild.getSome(child):
      self.node = child

  of "cursor.prev":
    var node = self.node
    let nextChild = self.document.getPrevChildRec node
    if nextChild.getSome(child):
      self.node = child

  of "cursor.next-line":
    if self.document.getNextLine(self.node).getSome(next):
      self.node = next

  of "cursor.prev-line":
    if self.document.getPrevLine(self.node).getSome(prev):
      self.node = prev

  of "selected.delete":
    self.node = self.document.deleteNode self.node

  of "undo":
    if self.document.undo.getSome(node):
      self.node = node

  of "redo":
    if self.document.redo.getSome(node):
      self.node = node

  of "insert-after":
    let index = self.node.index
    if self.createNodeFromAction(arg).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      if self.document.insertNode(self.node.parent, index + 1, newNode).getSome(node):
        self.node = node

        for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => n.kind == Empty and n.text == "", endNode = newNode):
          self.node = emptyNode
          break

        discard self.tryEdit self.node
      else:
        logger.log(lvlError, fmt"Failed to insert node {newNode} into {self.node.parent} at {index + 1}")

  of "insert-before":
    let index = self.node.index
    if self.createNodeFromAction(arg).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      if self.document.insertNode(self.node.parent, index, newNode).getSome(node):
        self.node = node

        for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => n.kind == Empty and n.text == "", endNode = newNode):
          self.node = emptyNode
          break

        discard self.tryEdit self.node
      else:
        logger.log(lvlError, fmt"Failed to insert node {newNode} into {self.node.parent} at {index}")

  of "replace":
    if self.createNodeFromAction(arg).getSome(newNodeIndex):
      let (newNode, _) = newNodeIndex
      self.node = self.document.replaceNode(self.node, newNode)

      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => n.kind == Empty and n.text == "", endNode = newNode):
        self.node = emptyNode
        break
      discard self.tryEdit self.node

  of "wrap":
    if self.createNodeFromAction(arg).getSome(newNodeIndex):
      var (newNode, index) = newNodeIndex
      echo index
      let oldNode = self.node
      self.node = self.document.replaceNode(self.node, newNode)
      for i, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => n.kind == Empty and n.text == "", endNode = newNode):
        if i == index:
          self.node = self.document.replaceNode(emptyNode, oldNode)
          break
      for _, emptyNode in self.document.nextPreOrderWhere(newNode, (n) => n.kind == Empty and n.text == "", endNode = newNode):
        self.node = emptyNode
        break
      discard self.tryEdit self.node

  of "rename":
    discard self.tryEdit self.node

  of "apply-rename":
    self.finishEdit(true)

  of "cancel-rename":
    self.finishEdit(false)

  else:
    logger.log(lvlError, "[textedit] Unknown action '$1 $2'" % [action, arg])

  return Handled

proc handleInput(self: AstDocumentEditor, input: string): EventResponse =
  echo "handleInput '", input, "'"
  return Handled

method createWithDocument*(self: AstDocumentEditor, document: Document): DocumentEditor =
  let editor = AstDocumentEditor(eventHandler: nil, document: AstDocument(document), textDocument: nil, textEditor: nil)
  editor.init()
  editor.cursor = @[0]

  if editor.document.rootNode == nil:
    editor.document.rootNode = AstNode(kind: NodeList, parent: nil, id: newId())
  if editor.document.rootNode.len == 0:
    let node = makeTree(AstNode):
      Declaration(id: == newId()):
        Call():
          Identifier(id: == IdPrint)
          StringLiteral(text: "hi")
          Call:
            Identifier(id: == IdMul)
            Call:
              Identifier(id: == IdNegate)
              NumberLiteral(text: "123456")
            Call:
              Identifier(id: == IdDiv)
              StringLiteral(text: "")
              NumberLiteral(text: "42069")
          Identifier(id: == IdAdd)
          Call:
            Identifier(id: == IdDeref)
            Identifier(id: == IdPrint)

    discard editor.document.addSymbol Symbol(id: node.id, name: "foo", node: node)
    editor.document.rootNode.add node

    editor.document.rootNode.add makeTree(AstNode) do:
      If:
        Call:
          Empty(text: "bar")
          Identifier(id: == node.id)
          StringLiteral(text: "bar")
        NodeList:
          Call:
            Identifier(id: == IdPrint)
            StringLiteral(text: "hi")
            Call:
              Identifier(id: == IdMul)
              Call:
                Identifier(id: == IdNegate)
                NumberLiteral(text: "123456")
              Call:
                Identifier(id: == IdDiv)
                StringLiteral(text: "")
                NumberLiteral(text: "42069")
            Identifier(id: == IdAdd)
            Call:
              Identifier(id: == IdDeref)
              Identifier(id: == IdPrint)
          Call:
            Identifier(id: == IdDeref)
            Identifier(id: == node.id)
          Declaration(id: == newId()):
            NumberLiteral(text: "6")

    editor.document.rootNode.add makeTree(AstNode) do:
      Call:
        Identifier(id: == IdDeref)
        Identifier(id: == node.id)

    discard editor.document.addSymbol Symbol(id: node.id, name: "foo", node: node)

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
    command "<ENTER>", "editor.insert \n"
    command "<SPACE>", "editor.insert  "
    command "<BACKSPACE>", "backspace"
    command "<DELETE>", "delete"

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
    command "\"", "replace \""
    command "'", "replace \""

    command "+", "wrap +"
    command "-", "wrap -"
    command "*", "wrap *"
    command "/", "wrap /"
    command "%", "wrap %"
    command "(", "wrap call-func"
    command ")", "wrap call-arg"

    command "u", "undo"
    command "U", "redo"
    command "d", "selected.delete"
    onAction:
      editor.handleAction action, arg
    onInput:
      editor.handleInput input

  editor.textEditEventHandler = eventHandler2:
    command "<ENTER>", "apply-rename"
    command "<ESCAPE>", "cancel-rename"
    onAction:
      editor.handleAction action, arg
    onInput:
      Ignored
  return editor