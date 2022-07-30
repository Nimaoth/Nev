import std/[strformat, strutils, algorithm, math, logging, unicode, sequtils, sugar, tables, macros, options, os]
import print, fusion/matching
import input, document, document_editor, text_document, events, id, ast_ids

var logger = newConsoleLogger()

template getSome*[T](opt: Option[T], injected: untyped): bool =
  opt.isSome() and ((let injected {.inject.} = opt.get(); true))

type Cursor = seq[int]

type
  AstNodeKind* = enum
    Empty
    Identifier
    NumberLiteral
    StringLiteral
    Declaration
    Infix
    Prefix
    Postfix
    NodeList
  AstNode* = ref object
    parent*: AstNode
    id*: Id
    kind*: AstNodeKind
    text*: string
    children*: seq[AstNode]

func add(node: AstNode, child: AstNode) =
  child.parent = node
  node.children.add child

# Generate new IDs
when false:
  for i in 0..100:
    echo $newId()
    sleep(100)

type Symbol = ref object
  name*: string
  node*: AstNode

type AstDocument* = ref object of Document
  filename*: string
  globalScope*: Table[Id, Symbol]
  rootNode*: AstNode

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

proc newAstDocument*(filename: string = ""): AstDocument =
  new(result)
  result.filename = filename
  result.globalScope.add IdPrint, Symbol(name: "print")
  result.globalScope.add IdAdd, Symbol(name: "+")
  result.globalScope.add IdSub, Symbol(name: "-")
  result.globalScope.add IdMul, Symbol(name: "*")
  result.globalScope.add IdDiv, Symbol(name: "/")
  result.globalScope.add IdMod, Symbol(name: "%")

proc getSymbol*(doc: AstDocument, id: Id): Option[Symbol] =
  let symbol = doc.globalScope.getOrDefault(id, nil)
  if symbol == nil:
    return none[Symbol]()
  return some(symbol)

method `$`*(document: AstDocument): string =
  return document.filename

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

proc finishEdit*(self: AstDocumentEditor, apply: bool) =
  if apply:
    if self.currentlyEditedSymbol != nil:
      self.currentlyEditedSymbol.name = self.textDocument.content.join
    elif self.currentlyEditedNode != nil:
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

proc getNextChild(node: AstNode, min: int = -1): Option[AstNode] =
  if node.len == 0:
    return none[AstNode]()

  case node
  of Infix():
    if min == 0: return some(node[2])
    if min == 1: return some(node[0])
    if min == 2: return none[AstNode]()
    return some(node[1])
  of Postfix():
    if min == 0: return none[AstNode]()
    if min == 1: return some(node[0])
    return some(node[1])

  if min < 0:
    return some(node[0])
  if min >= node.len - 1:
    return none[AstNode]()
  return some(node[min + 1])

proc getPrevChild(node: AstNode, max: int = -1): Option[AstNode] =
  if node.len == 0:
    return none[AstNode]()

  case node
  of Infix():
    if max == 0: return some(node[1])
    if max == 1: return none[AstNode]()
    if max == 2: return some(node[0])
    return some(node[2])
  of Postfix():
    if max == 0: return some(node[1])
    if max == 1: return none[AstNode]()
    return some(node[0])

  if max < 0:
    return some(node[node.len - 1])
  elif max == 0:
    return none[AstNode]()
  return some(node[max - 1])

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
    let nextChild = node.getNextChild
    if nextChild.getSome(child):
      self.node = child
    else:
      while node.parent != nil:
        let nextChild = node.parent.getNextChild node.index
        if nextChild.getSome(child):
          self.node = child
          break
        elif self.node.parent != self.document.rootNode:
          node = node.parent
      # elif self.node.parent != self.document.rootNode and self.node.parent != nil:
      #   self.node = node.parent

  of "cursor.prev":
    var node = self.node
    let nextChild = node.getPrevChild
    if nextChild.getSome(child):
      self.node = child
    else:
      while node.parent != nil:
        let nextChild = node.parent.getPrevChild node.index
        if nextChild.getSome(child):
          self.node = child
          break
        elif self.node.parent != self.document.rootNode:
          node = node.parent
        # elif self.node.parent != self.document.rootNode and self.node.parent != nil:
        #   self.node = node.parent

  of "insert":
    case arg
    of "empty":
      self.document.rootNode.add AstNode(kind: Empty, id: newId(), text: "new empty")
    of "identifier":
      self.document.rootNode.add AstNode(kind: Identifier, text: "todo")
    of "number-literal":
      self.document.rootNode.add AstNode(kind: NumberLiteral, text: "123")
    of "declaration":
      self.document.rootNode.add AstNode(kind: Declaration, id: newId(), children: @[AstNode(kind: Empty, text: "name"), AstNode(kind: Empty, text: "value")])
    else:
      discard

  of "rename":
    let node = self.getNodeAt(self.cursor)
    if self.document.getSymbol(node.id).getSome(sym):
      self.editSymbol(sym)
    else:
      self.editNode(node)

  of "apply-rename":
    self.finishEdit(true)

  of "cancel-rename":
    self.finishEdit(false)

  else:
    logger.log(lvlError, "[textedit] Unknown action '$1 $2'" % [action, arg])

  echo self.cursor
  return Handled

proc handleInput(self: AstDocumentEditor, input: string): EventResponse =
  echo "handleInput '", input, "'"
  return Handled

method createWithDocument*(self: AstDocumentEditor, document: Document): DocumentEditor =
  let editor = AstDocumentEditor(eventHandler: nil, document: AstDocument(document), textDocument: nil, textEditor: nil)
  editor.init()
  editor.cursor = @[0]

  if editor.document.rootNode == nil:
    editor.document.rootNode = AstNode(parent: nil, id: newId())
  if editor.document.rootNode.len == 0:
    let node = makeTree(AstNode):
      Declaration(id: == newId()):
        Infix:
          Identifier(id: == IdAdd)
          StringLiteral(text: "hi")
          Prefix:
            Identifier(id: == IdMod)
            NumberLiteral(text: "123456")

    editor.document.globalScope.add node.id, Symbol(name: "foo", node: node)
    editor.document.rootNode.add node

    editor.document.rootNode.add makeTree(AstNode) do:
      Postfix:
        Identifier(id: == IdDiv)
        Identifier(id: == node.id)

    editor.document.globalScope.add node.id, Symbol(name: "foo", node: node)

  editor.node = editor.document.rootNode[0]

  editor.eventHandler = eventHandler2:
    command "<LEFT>", "cursor.left"
    command "<RIGHT>", "cursor.right"
    command "<UP>", "cursor.up"
    command "<DOWN>", "cursor.down"
    command "<HOME>", "cursor.home"
    command "<END>", "cursor.end"
    command "t", "cursor.next"
    command "n", "cursor.prev"
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
    command "ie", "insert empty"
    command "in", "insert number-literal"
    command "id", "insert declaration"
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