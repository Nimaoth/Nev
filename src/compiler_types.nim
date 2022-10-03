import std/[tables, strutils, sequtils, sugar, hashes, options, logging, strformat]
import fusion/matching
import bumpy, chroma, vmath, pixie/fonts
import ast, id, util, rect_utils
import query_system

type
  TypeKind* = enum
    tError
    tVoid
    tString
    tInt
    tFunction
    tAny
    tType

  Type* = ref object
    case kind*: TypeKind
    of tError: discard
    of tVoid: discard
    of tString: discard
    of tInt: discard
    of tType: discard
    of tAny: open: bool
    of tFunction:
      returnType*: Type
      paramTypes*: seq[Type]

  ValueImpl* = proc(values: seq[Value]): Value
  ValueKind* = enum
    vkError
    vkVoid
    vkString
    vkNumber
    vkBuiltinFunction
    vkAstFunction
    vkType

  Value* = object
    case kind*: ValueKind
    of vkError: discard
    of vkVoid: discard
    of vkString: stringValue*: string
    of vkNumber: intValue*: int
    of vkBuiltinFunction: impl*: ValueImpl
    of vkAstFunction:
      node*: AstNode
      rev*: int
    of vkType: typ*: Type

  OperatorNotation* = enum
    Regular
    Prefix
    Postfix
    Infix
    Scope

  SymbolKind* = enum skAstNode, skBuiltin
  Symbol* = ref object
    id*: Id
    name*: string
    case kind*: SymbolKind
    of skAstNode:
      node*: AstNode
    of skBuiltin:
      typ*: Type
      value*: Value
      operatorNotation*: OperatorNotation
      precedence*: int

type FunctionExecutionContext* = ref object
  id*: Id
  node*: AstNode
  arguments*: seq[Value]

type
  VisualNodeRenderFunc* = proc(bounds: Rect)
  VisualNode* = ref object
    parent*: VisualNode
    node*: AstNode
    text*: string
    color*: Color
    bounds*: Rect
    indent*: float32
    font*: Font
    render*: VisualNodeRenderFunc
    children*: seq[VisualNode]

  VisualNodeRange* = object
    parent*: VisualNode
    first*: int
    last*: int

  NodeLayout* = object
    root*: VisualNode
    nodeToVisualNode*: Table[Id, VisualNodeRange]

  NodeLayoutInput* = ref object
    id*: Id
    node*: AstNode
    selectedNode*: Id
    replacements*: Table[Id, VisualNode]

func index*(node: VisualNode): int =
  if node.parent == nil:
    return -1

  result = 0
  for i in node.parent.children:
    if cast[pointer](i) == cast[pointer](node): return
    inc(result)

func `[]`*(node: VisualNode, index: int): VisualNode =
  return node.children[index]

func len*(node: VisualNode): int =
  return node.children.len

func next*(node: VisualNode): Option[VisualNode] =
  if node.parent == nil:
    return none[VisualNode]()
  let i = node.index
  if i >= node.parent.len - 1:
    return none[VisualNode]()
  return some(node.parent[i + 1])

func prev*(node: VisualNode): Option[VisualNode] =
  if node.parent == nil:
    return none[VisualNode]()
  let i = node.index
  if i <= 0:
    return none[VisualNode]()
  return some(node.parent[i - 1])

iterator nextPreOrder*(node: VisualNode, endNode: VisualNode = nil): tuple[key: int, value: VisualNode] =
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


func errorType*(): Type = Type(kind: tError)
func voidType*(): Type = Type(kind: tVoid)
func intType*(): Type = Type(kind: tInt)
func stringType*(): Type = Type(kind: tString)
func newFunctionType*(paramTypes: seq[Type], returnType: Type): Type = Type(kind: tFunction, returnType: returnType, paramTypes: paramTypes)
func typeType*(): Type = Type(kind: tType)
func anyType*(open: bool): Type = Type(kind: tAny, open: open)

func `$`*(typ: Type): string =
  case typ.kind
  of tError: return "error"
  of tVoid: return "void"
  of tString: return "string"
  of tInt: return "int"
  of tFunction: return $typ.paramTypes & " -> " & $typ.returnType
  of tType: return "type"
  of tAny: return fmt"any({typ.open})"

func hash*(typ: Type): Hash =
  case typ.kind
  of tFunction: typ.kind.hash xor typ.returnType.hash xor typ.paramTypes.hash
  of tAny: typ.kind.hash xor typ.open.hash
  else:
    return typ.kind.hash

func `==`*(a: Type, b: Type): bool =
  if a.isNil: return b.isNil
  if b.isNil: return false
  if a.kind != b.kind: return false
  case a.kind
  of tFunction:
    return a.returnType == b.returnType and a.paramTypes == b.paramTypes
  of tAny:
    return a.open == b.open
  else:
    return true

func fingerprint*(typ: Type): Fingerprint =
  case typ.kind
  of tFunction:
    result = @[typ.kind.int64] & typ.returnType.fingerprint
    for param in typ.paramTypes:
      result.add param.fingerprint
  of tAny:
    result = @[typ.kind.int64, typ.open.int64]
  else:
    result = @[typ.kind.int64]

func errorValue*(): Value = Value(kind: vkError)
func voidValue*(): Value = Value(kind: vkVoid)
func intValue*(value: int): Value = Value(kind: vkNumber, intValue: value)
func stringValue*(value: string): Value = Value(kind: vkString, stringValue: value)
func typeValue*(typ: Type): Value = Value(kind: vkType, typ: typ)
func newFunctionValue*(impl: ValueImpl): Value = return Value(kind: vkBuiltinFunction, impl: impl)
func newAstFunctionValue*(node: AstNode, rev: int): Value = return Value(kind: vkAstFunction, node: node, rev: rev)

func `$`*(value: Value): string =
  case value.kind
  of vkError: return "<vkError>"
  of vkVoid: return "void"
  of vkString: return value.stringValue
  of vkNumber: return $value.intValue
  of vkBuiltinFunction: return "<builtin-function>"
  of vkAstFunction: return "<ast-function " & $value.node & ">"
  of vkType: return $value.typ

func hash*(value: Value): Hash =
  case value.kind
  of vkError: return value.kind.hash
  of vkVoid: return value.kind.hash
  of vkNumber: return value.intValue.hash
  of vkString: return value.stringValue.hash
  of vkBuiltinFunction: return value.impl.hash
  of vkAstFunction: return value.node.hash
  of vkType: return value.typ.hash

func `==`*(a: Value, b: Value): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vkError: return true
  of vkVoid: return true
  of vkNumber: return a.intValue == b.intValue
  of vkString: return a.stringValue == b.stringValue
  of vkBuiltinFunction: return a.impl == b.impl
  of vkAstFunction: return a.node == b.node
  of vkType: return a.typ == b.typ

func fingerprint*(value: Value): Fingerprint =
  case value.kind
  of vkError: return @[value.kind.int64]
  of vkVoid: return @[value.kind.int64]
  of vkNumber: return @[value.kind.int64, value.intValue]
  of vkString: return @[value.kind.int64, value.stringValue.hash]
  of vkBuiltinFunction: return @[value.kind.int64, value.impl.hash]
  of vkAstFunction: return @[value.kind.int64, value.node.hash, value.rev.int64]
  of vkType: return @[value.kind.int64] & value.typ.fingerprint

func `$`*(fec: FunctionExecutionContext): string =
  return fmt"Call {fec.node}({fec.arguments})"

func hash*(fec: FunctionExecutionContext): Hash =
  return fec.node.hash xor fec.arguments.hash

func `==`*(a: FunctionExecutionContext, b: FunctionExecutionContext): bool =
  if a.isNil: return b.isNil
  if b.isNil: return false
  if a.node != b.node:
    return false
  if a.arguments != b.arguments:
    return false
  return true

func `$`*(symbol: Symbol): string =
  case symbol.kind
  of skAstNode:
    return "Sym(AstNode, " & $symbol.id & ", " & $symbol.node & ")"
  of skBuiltin:
    return "Sym(Builtin, " & $symbol.id & ", " & $symbol.typ & ", " & $symbol.value & ")"

func hash*(symbol: Symbol): Hash =
  return symbol.id.hash

func `==`*(a: Symbol, b: Symbol): bool =
  if a.isNil: return b.isNil
  if b.isNil: return false
  if a.id != b.id: return false
  if a.kind != b.kind: return false
  if a.name != b.name: return false
  case a.kind
  of skBuiltin:
    return a.typ == b.typ and a.value == b.value and a.operatorNotation == b.operatorNotation and a.precedence == b.precedence
  of skAstNode:
    return a.node == b.node

func fingerprint*(symbol: Symbol): Fingerprint =
  case symbol.kind
  of skAstNode:
    result = @[symbol.id.hash.int64, symbol.name.hash.int64, symbol.kind.int64, symbol.node.id.hash.int64]
  of skBuiltin:
    result = @[symbol.id.hash.int64, symbol.name.hash.int64, symbol.kind.int64, symbol.precedence, symbol.operatorNotation.int64] & symbol.typ.fingerprint & symbol.value.fingerprint

func fingerprint*(symbols: TableRef[Id, Symbol]): Fingerprint =
  result = @[]
  for (key, value) in symbols.pairs:
    result.add value.fingerprint

func fingerprint*(symbol: Option[Symbol]): Fingerprint =
  if symbol.getSome(s):
    return s.fingerprint
  return @[]

func clone*(node: VisualNode): VisualNode =
  new result
  result.parent = node.parent
  result.node = node.node
  result.text = node.text
  result.color = node.color
  result.bounds = node.bounds
  result.indent = node.indent
  result.font = node.font
  result.render = node.render
  result.children = node.children.map c => c.clone
  for c in result.children:
    c.parent = result

func size*(node: VisualNode): Vec2 = node.bounds.wh
func relativeBounds*(node: VisualNode, parent: VisualNode): Rect =
  if node == parent:
    result = rect(vec2(), node.bounds.wh)
  elif node.parent == nil:
    result = node.bounds
  else:
    result = rect(node.parent.relativeBounds(parent).xy + node.bounds.xy, node.bounds.wh)

func absoluteBounds*(node: VisualNode): Rect =
  if node.parent == nil:
    result = node.bounds
  else:
    result = rect(node.parent.absoluteBounds.xy + node.bounds.xy, node.bounds.wh)

func absoluteBounds*(nodeRange: VisualNodeRange): Rect =
  result = nodeRange.parent.children[nodeRange.first].bounds
  for i in (nodeRange.first + 1)..<nodeRange.last:
    result = result or nodeRange.parent.children[i].bounds
  result.xy = result.xy + nodeRange.parent.absoluteBounds.xy

func `$`*(vnode: VisualNode): string =
  result = "VNode" & "('"
  result.add vnode.text & "', "
  result.add $vnode.bounds & ", "
  if vnode.node != nil:
    result.add $vnode.node & ", "
  result.add $vnode.color & ", "
  result.add ")"
  # if vnode.children.len > 0:
  #   result.add ":"
  #   for child in vnode.children:
  #     result.add "\n" & indent($child, 1, "| ")

func hash*(vnode: VisualNode): Hash =
  result = vnode.text.hash !& vnode.color.hash !& vnode.bounds.hash !& vnode.children.hash
  result = !$result

func fingerprint*(vnode: VisualNode): Fingerprint =
  let h = vnode.text.hash !& vnode.color.hash !& vnode.bounds.hash !& vnode.children.hash
  result = @[h.int64] & vnode.children.map(c => c.fingerprint).foldl(a & b, @[0.int64])

func `==`*(a: VisualNode, b: VisualNode): bool =
  if a.isNil: return b.isNil
  if b.isNil: return false
  if a.text != b.text:
    return false
  if a.node != b.node:
    return false
  if a.color != b.color:
    return false
  if a.bounds != b.bounds:
    return false
  if a.render != b.render:
    return false
  return a.children == b.children

proc add*(node: var VisualNode, child: VisualNode): VisualNodeRange =
  node.children.add child
  child.parent = node
  child.bounds.x = node.bounds.w
  node.bounds = node.bounds or (child.bounds + node.bounds.xy)
  return VisualNodeRange(parent: node, first: node.children.high, last: node.children.len)

proc addLine*(node: var VisualNode, child: var VisualNode) =
  node.children.add child
  child.parent = node
  child.bounds.y = node.bounds.h
  node.bounds = node.bounds or (child.bounds + node.bounds.xy)

func `$`*(nodeLayout: NodeLayout): string =
  result = nodeLayout.root.children.join "\n"

func hash*(nodeLayout: NodeLayout): Hash =
  result = nodeLayout.root.hash
  result = !$result

func `==`*(a: NodeLayout, b: NodeLayout): bool =
  return a.root == b.root

func fingerprint*(nodeLayout: NodeLayout): Fingerprint =
  result = nodeLayout.root.fingerprint

func bounds*(nodeLayout: NodeLayout): Rect =
  return nodeLayout.root.bounds

func `$`*(input: NodeLayoutInput): string =
  return fmt"NodeLayoutInput({input.id}, node: {input.node}, selected: {input.selectedNode})"

func hash*(input: NodeLayoutInput): Hash =
  return input.node.hash !& input.selectedNode.hash

func `==`*(a: NodeLayoutInput, b: NodeLayoutInput): bool =
  if a.isNil: return b.isNil
  if b.isNil: return false
  # We don't care about the id of the NodeLayoutInput
  if a.node != b.node: return false
  if a.selectedNode != b.selectedNode: return false
  if a.replacements != b.replacements: return false
  return true
