import std/[options, algorithm, strutils, hashes, enumutils, json, jsonutils]
import fusion/matching
import util, id

type
  AstNodeKind* = enum
    Empty
    Identifier
    NumberLiteral
    StringLiteral
    ConstDecl
    LetDecl
    VarDecl
    NodeList
    Call
    If
    FunctionDefinition
    Params

  AstNode* = ref object
    parent*: AstNode
    id*: Id
    reff*: Id
    kind*: AstNodeKind
    text*: string
    children*: seq[AstNode]

proc add*(node: AstNode, child: AstNode) =
  if node.id == null:
    node.id = newId()
  if child.id == null:
    child.id = newId()
  child.parent = node
  node.children.add child

proc insert*(node: AstNode, child: AstNode, idx: int) =
  if node.id == null:
    node.id = newId()
  if child.id == null:
    child.id = newId()
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
  of ConstDecl():
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

func `$`*(node: AstNode): string =
  result = node.kind.symbolName & "("
  if node.id != idNone():
    result.add $node.id & ", "
  if node.reff != idNone():
    result.add "reff: " & $node.reff & ", "
  if node.text.len > 0:
    result.add "'" & node.text & "', "
  if node.len > 0:
    result.add $node.len & ", "
  result.add $node.path
  result.add ")"

proc treeRepr*(node: AstNode): string =
  case node
  of ConstDecl():
    result = "ConstDecl(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of LetDecl():
    result = "LetDecl(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of VarDecl():
    result = "VarDecl(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of Call():
    result = "Call(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of If():
    result = "If(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of NodeList():
    result = "NodeList(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of Params():
    result = "Params(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of FunctionDefinition():
    result = "FunctionDefinition(id: " & $node.id & "):"
    for child in node.children:
      result.add "\n"
      result.add indent(child.treeRepr, 2)

  of StringLiteral():
    result = "StringLiteral(id: " & $node.id & ", text: '" & node.text & "')"

  of Identifier():
    result = "Identifier(id: " & $node.id & ", reff: " & $node.reff & ")"

  of NumberLiteral():
    result = "NumberLiteral(id: " & $node.id & ", text: '" & node.text & "')"

  of Empty():
    result = "Empty(id: " & $node.id & ", text: '" & node.text & "')"

  else:
    return "other"

proc toJson*(node: AstNode, opt = initToJsonOptions()): JsonNode =
  result = newJObject()
  result["kind"] = toJson(node.kind, opt)
  result["id"] = toJson(node.id, opt)
  if node.reff != null: result["reff"] = toJson(node.reff, opt)
  if node.text.len > 0: result["text"] = toJson(node.text, opt)

  if node.len > 0:
    let children = newJArray()
    for child in node.children:
      children.add child.toJson opt
    result["children"] = children

proc jsonToAstNode*(json: JsonNode, opt = Joptions()): AstNode =
  result = AstNode()
  result.kind = json["kind"].jsonTo AstNodeKind
  result.id = json["id"].jsonTo Id

  if json.hasKey("reff"):
    result.reff = json["reff"].jsonTo Id
  if json.hasKey("text"):
    result.text = json["text"].jsonTo string

  if json.hasKey("children"):
    for child in json["children"].items:
      result.add child.jsonToAstNode

proc `$$`*(node: AstNode): string =
  return node.treeRepr

proc hash*(node: AstNode): Hash = cast[int](addr node[])