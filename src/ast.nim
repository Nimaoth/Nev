import std/[options, algorithm, strutils, hashes, enumutils]
import system
import fusion/matching
import util, id

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

func add*(node: AstNode, child: AstNode) =
  child.parent = node
  node.children.add child

func insert*(node: AstNode, child: AstNode, idx: int) =
  child.parent = node
  node.children.insert child, idx

func `[]`*(node: AstNode, index: int): AstNode =
  return node.children[index]

func len*(node: AstNode): int =
  return node.children.len

func base*(node: AstNode): AstNode =
  if node.parent == nil:
    return node
  return node.parent.base

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

func first*(node: AstNode): AstNode =
  if node.len > 0:
    return node[0]
  # raise IndexDefect(msg: "Node has no children")
  return nil

func last*(node: AstNode): AstNode =
  if node.len > 0:
    return node[node.len - 1]
  # raise Defect(msg: "Node has no children")
  return nil

func lastOrSelf*(node: AstNode): AstNode =
  if node.len > 0:
    return node[node.len - 1]
  return node

proc `[]=`*(node: AstNode, index: int, newNode: AstNode) =
  newNode.parent = node
  node.children[index].parent = nil
  node.children[index] = newNode

func delete*(node: AstNode, index: int): AstNode =
  if index < 0 or index >= node.len:
    return node

  node[index].parent = nil

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

proc findChildRec*(node: AstNode, kind: AstNodeKind): Option[AstNode] =
  for c in node.children:
    if c.kind == kind:
      return some(c)
    if c.findChildRec(kind).getSome(c):
      return some(c)

  return none[AstNode]()

# Returns the closest parent node which has itself a parent with the given kind
proc findWithParentRec*(node: AstNode, kind: AstNodeKind): Option[AstNode] =
  if node.parent == nil:
    return none[AstNode]()
  if node.parent.kind == kind:
    return some(node)
  return node.parent.findWithParentRec(kind)

# Returns the closest parent node which has itself a parent with the given kind
proc isChildRec*(node: AstNode, parent: AstNode): bool =
  if node.parent == nil:
    return false
  if node.parent == parent:
    return true
  return node.parent.isChildRec(parent)

func path*(node: AstNode): seq[int] =
  result = @[]
  var node = node
  while node.parent != nil:
    result.add node.index
    node = node.parent
  result.reverse

proc `$`*(node: AstNode): string =
  result = node.kind.symbolName & "("
  if node.id != null:
    result.add $node.id & ", "
  if node.text.len > 0:
    result.add "'" & node.text & "', "
  if node.len > 0:
    result.add $node.len & ", "
  result.add $node.path
  result.add ")"

proc `$$`*(node: AstNode): string =
  case node
  of Declaration():
    result = "Declaration(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent($$child, 2)

  of Call():
    result = "Call():"
    for child in node.children:
      result.add "\n"
      result.add indent($$child, 2)

  of If():
    result = "If()"
    for child in node.children:
      result.add "\n"
      result.add indent($$child, 2)

  of NodeList():
    result = "NodeList()"
    for child in node.children:
      result.add "\n"
      result.add indent($$child, 2)

  of StringLiteral():
    result = "StringLiteral(text: '" & node.text & "')"

  of Identifier():
    result = "Identifier(id: " & $node.id & ", text: '" & node.text & "')"

  of NumberLiteral():
    result = "NumberLiteral(text: '" & node.text & "')"

  of Empty():
    result = "Empty()"

  else:
    return "other"

proc hash*(node: AstNode): Hash = cast[int](addr node[])