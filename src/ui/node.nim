import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options]
import macro_utils, util, id, input, custom_unicode
import chroma, vmath, rect_utils
import custom_logger

export util, id, input, chroma, vmath, rect_utils

logCategory "ui-node"

macro defineBitFlag*(body: untyped): untyped =
  let flagName = body[0][0].typeName
  let flagsName = (flagName.repr & "s").ident

  result = genAst(body, flagName, flagsName):
    body
    type flagsName* = distinct uint32

    func contains*(flags: flagsName, flag: flagName): bool {.inline.} = (flags.uint32 and (1.uint32 shl flag.uint32)) != 0
    func all*(flags: flagsName, expected: flagsName): bool {.inline.} = (flags.uint32 and expected.uint32) == expected.uint32
    func any*(flags: flagsName, expected: flagsName): bool {.inline.} = (flags.uint32 and expected.uint32) != 0
    func incl*(flags: var flagsName, flag: flagName) {.inline.} =
      flags = (flags.uint32 or (1.uint32 shl flag.uint32)).flagsName
    func excl*(flags: var flagsName, flag: flagName) {.inline.} =
      flags = (flags.uint32 and not (1.uint32 shl flag.uint32)).flagsName

    func `==`*(a, b: flagsName): bool {.borrow.}

    macro `&`*(flags: static set[flagName]): flagsName =
      var res = 0.flagsName
      for flag in flags:
        res.incl flag
      return genAst(res2 = res.uint32):
        res2.flagsName

    iterator flags*(self: flagsName): flagName =
      for v in flagName.low..flagName.high:
        if (self.uint32 and (1.uint32 shl v.uint32)) != 0:
          yield v

    proc `$`*(self: flagsName): string =
      var res2: string = "{"
      for flag in self.flags:
        if res2.len > 1:
          res2.add ", "
        res2.add $flag
      res2.add "}"
      return res2

defineBitFlag:
  type UINodeFlag* = enum
    SizeToContentX = 0
    SizeToContentY
    FillX
    FillY
    DrawBorder
    FillBackground
    LogLayout
    AllowAlpha
    MaskContent
    DrawText
    LayoutVertical
    LayoutHorizontal
    OverlappingChildren

type
  UINode* = ref object
    parent: UINode
    first: UINode
    last: UINode
    prev: UINode
    next: UINode

    mId: Id
    mContentDirty: bool
    mPositionDirty: bool
    mSizeDirty: bool
    mLastContentChange: int
    mLastPositionChange: int
    mLastSizeChange: int

    mFlags: UINodeFlags

    mText: string

    mBackgroundColor: Color
    mBorderColor: Color
    mTextColor: Color

    mX, mY, mW, mH: float32
    mLx, mLy, mLw, mLh: float32

    mHandleClick: proc(node: UINode, button: MouseButton): bool
    mHandleDrag: proc(node: UINode, button: MouseButton, delta: Vec2): bool
    mHandleBeginHover: proc(node: UINode): bool
    mHandleEndHover: proc(node: UINode): bool
    mHandleHover: proc(node: UINode): bool

  UINodePool* = ref object
    nodes: seq[UINode]
    allNodes: seq[UINode]

  UINodeBuilder* = ref object
    nodePool: UINodePool = nil
    currentChild: UINode = nil
    currentParent: UINode = nil
    root*: UINode = nil
    frameIndex*: int = 0
    charWidth*: float32
    lineHeight*: float32
    lineGap*: float32

proc dump*(node: UINode, recurse = false): string

func parent*(node: UINode): UINode = node.parent
func first*(node: UINode): UINode = node.first
func last*(node: UINode): UINode = node.last
func next*(node: UINode): UINode = node.next
func prev*(node: UINode): UINode = node.prev

func id*(node: UINode): Id = node.mId
func dirty*(node: UINode): bool = node.mContentDirty or node.mPositionDirty or node.mSizeDirty
func lastChange*(node: UINode): int = max(node.mLastContentChange, max(node.mLastPositionChange, node.mLastSizeChange))
func flags*(node: UINode): UINodeFlags = node.mFlags
func text*(node: UINode): string = node.mText
func backgroundColor*(node: UINode): Color = node.mBackgroundColor
func borderColor*(node: UINode): Color = node.mBorderColor
func textColor*(node: UINode): Color = node.mTextColor

func `flags=`*(node: UINode, value: UINodeFlags)     = node.mContentDirty = node.mContentDirty or (value != node.mFlags);           node.mFlags           = value
func `text=`*(node: UINode, value: string)           = node.mContentDirty = node.mContentDirty or (value != node.mText);            node.mText            = value
func `backgroundColor=`*(node: UINode, value: Color) = node.mContentDirty = node.mContentDirty or (value != node.mBackgroundColor); node.mBackgroundColor = value
func `borderColor=`*(node: UINode, value: Color)     = node.mContentDirty = node.mContentDirty or (value != node.mBorderColor);     node.mBorderColor     = value
func `textColor=`*(node: UINode, value: Color)       = node.mContentDirty = node.mContentDirty or (value != node.mTextColor);       node.mTextColor       = value

func handleClick*(node: UINode):        (proc(node: UINode, button: MouseButton): bool) = node.mHandleClick
func handleDrag*(node: UINode):         (proc(node: UINode, button: MouseButton, delta: Vec2): bool) = node.mHandleDrag
# func handleBeginOverlap*(node: UINode): (proc(node: UINode, button: MouseButton): bool) = node.mHandleBeginOverlap
# func handleEndOverlap*(node: UINode):   (proc(node: UINode, button: MouseButton): bool) = node.mHandleEndOverlap
# func handleOverlap*(node: UINode):      (proc(node: UINode, button: MouseButton): bool) = node.mHandleOverlap

func `handleClick=`*(node: UINode, value: proc(node: UINode, button: MouseButton): bool)              = node.mContentDirty = node.mContentDirty or (value != node.mHandleClick);        node.mHandleClick = value
func `handleDrag=`* (node: UINode, value: proc(node: UINode, button: MouseButton, delta: Vec2): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleDrag);         node.mHandleDrag = value
# func `handleBeginOverlap=`*(node: UINode, value: proc(node: UINode, button: MouseButton): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleBeginOverlap); node.mHandleBeginOverlap = value
# func `handleEndOverlap=`*(node: UINode,   value: proc(node: UINode, button: MouseButton): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleEndOverlap);   node.mHandleEndOverlap = value
# func `handleOverlap=`*(node: UINode,      value: proc(node: UINode, button: MouseButton): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleOverlap);      node.mHandleOverlap = value

func x*(node: UINode): float32 = node.mX
func y*(node: UINode): float32 = node.mY
func w*(node: UINode): float32 = node.mW
func h*(node: UINode): float32 = node.mH
func xw*(node: UINode): float32 = node.mX + node.mW
func yh*(node: UINode): float32 = node.mY + node.mH

func lx*(node: UINode): float32 = node.mLx
func ly*(node: UINode): float32 = node.mLy
func lw*(node: UINode): float32 = node.mLw
func lh*(node: UINode): float32 = node.mLh
func lxw*(node: UINode): float32 = node.mLx + node.mLw
func lyh*(node: UINode): float32 = node.mLy + node.mLh

func `x=`*(node: UINode, value: float32) = node.mPositionDirty = node.mPositionDirty or (value != node.mX);   node.mX = value
func `y=`*(node: UINode, value: float32) = node.mPositionDirty = node.mPositionDirty or (value != node.mY);   node.mY = value
proc `w=`*(node: UINode, value: float32) = node.mSizeDirty = node.mSizeDirty or (value != node.mW);           node.mW = value
proc `h=`*(node: UINode, value: float32) = node.mSizeDirty = node.mSizeDirty or (value != node.mH);           node.mH = value
# proc `w=`*(node: UINode, value: float32) = echo(node.mW, " -> ", value, " : ", node.dump); node.mSizeDirty = node.mSizeDirty or (value != node.mW);           node.mW = value
# proc `h=`*(node: UINode, value: float32) = echo(node.mH, " -> ", value, " : ", node.dump); node.mSizeDirty = node.mSizeDirty or (value != node.mH);           node.mH = value
# func `xw=`*(node: UINode, value: float32) = node.mSizeDirty = node.mSizeDirty or (value - node.mX != node.mW); node.mW = value - node.mX
# func `yh=`*(node: UINode, value: float32) = node.mSizeDirty = node.mSizeDirty or (value - node.mY != node.mH); node.mH = value - node.mY

func `lx=`*(node: UINode, value: float32) = node.mLx = value
func `ly=`*(node: UINode, value: float32) = node.mLy = value
func `lw=`*(node: UINode, value: float32) = node.mLw = value
func `lh=`*(node: UINode, value: float32) = node.mLh = value

proc textWidth*(builder: UINodeBuilder, textLen: int): float32 = textLen.float32 * builder.charWidth
proc textHeight*(builder: UINodeBuilder): float32 = builder.lineHeight + builder.lineGap

proc createNode*(pool: UINodePool): UINode

proc newNodeBuilder*(): UINodeBuilder =
  new result
  new result.nodePool
  result.frameIndex = 0
  result.root = result.nodePool.createNode()

proc setBackgroundColor*(node: UINode, r, g, b: float32, a: float32 = 1) =
  if r != node.mBackgroundColor.r or g != node.mBackgroundColor.g or b != node.mBackgroundColor.b or node.mBackgroundColor.a != a:
    node.mContentDirty = true
  node.mBackgroundColor.r = r
  node.mBackgroundColor.g = g
  node.mBackgroundColor.b = b
  node.mBackgroundColor.a = a

proc setBorderColor*(node: UINode, r, g, b: float32, a: float32 = 1) =
  if r != node.mBorderColor.r or g != node.mBorderColor.g or b != node.mBorderColor.b or node.mBorderColor.a != a:
    node.mContentDirty = true
  node.mBorderColor.r = r
  node.mBorderColor.g = g
  node.mBorderColor.b = b
  node.mBorderColor.a = a

proc setTextColor*(node: UINode, r, g, b: float32, a: float32 = 1) =
  if r != node.mTextColor.r or g != node.mTextColor.g or b != node.mTextColor.b or node.mTextColor.a != a:
    node.mContentDirty = true
  node.mTextColor.r = r
  node.mTextColor.g = g
  node.mTextColor.b = b
  node.mTextColor.a = a

iterator children*(node: UINode): UINode =
  var current = node.first
  while current.isNotNil:
    let next = current.next
    yield current
    current = next

proc createNode*(pool: UINodePool): UINode =
  if pool.nodes.len > 0:
    # debug "reusing node ", pool.nodes[pool.nodes.high].id
    return pool.nodes.pop
  # defer:
    # debug "creating new node ", result.id
  result = UINode(mId: newId())
  pool.allNodes.add result

proc returnNode*(pool: UINodePool, node: UINode) =
  for c in node.children:
    pool.returnNode c

  # debug "returning node ", node.id

  node.parent = nil
  node.first = nil
  node.last = nil
  node.next = nil
  node.prev = nil
  node.mFlags = 0.UINodeFlags
  node.mLastContentChange = 0
  node.mLastPositionChange = 0
  node.mLastSizeChange = 0

  node.mContentDirty = false
  node.mPositionDirty = false
  node.mSizeDirty = false

  node.mText = ""

  node.mX = 0
  node.mY = 0
  node.mW = 0
  node.mH = 0

  node.mLx = 0
  node.mLy = 0
  node.mLw = 0
  node.mLh = 0

  node.mHandleClick = nil
  node.mHandleDrag = nil
  node.mHandleBeginHover = nil
  node.mHandleEndHover = nil
  node.mHandleHover = nil

  pool.nodes.add node

proc getNextOrNewNode*(pool: UINodePool, node: UINode, last: UINode): UINode =
  if last.isNil:
    if node.first.isNotNil:
      return node.first

    let newNode = pool.createNode()
    newNode.parent = node
    node.first = newNode
    node.last = newNode
    return newNode

  if last.next.isNotNil:
    assert last.next.parent == last.parent
    assert last.next.prev == last
    return last.next

  let newNode = pool.createNode()
  newNode.parent = node
  newNode.prev = last
  last.next = newNode
  node.last = newNode
  return newNode

proc pruneUnused*(pool: UINodePool, node: UINode, last: UINode) =
  if last.isNil:
    for child in node.children:
      pool.returnNode child
      node.mContentDirty = true
    node.first = nil
    node.last = nil

  else:
    assert last.parent == node

    var n = last.next
    while n.isNotNil:
      let next = n.next
      pool.returnNode n
      node.mContentDirty = true
      n = next

    node.last = last
    last.next = nil

proc preLayout*(builder: UINodeBuilder, node: UINode) =
  let parent = node.parent

  if LayoutHorizontal in parent.flags:
    if node.prev.isNotNil:
      node.x = node.prev.x + node.prev.w
    else:
      node.x = 0

  if LayoutVertical in parent.flags:
    if node.prev.isNotNil:
      node.y = node.prev.y + node.prev.h
    else:
      node.y = 0

  if SizeToContentX in node.flags:
    # node.w = 0
    if DrawText in node.flags:
      node.w = builder.textWidth(node.text.runeLen.int)

  elif FillX in node.flags:
    node.w = parent.w - node.x

  if SizeToContentY in node.flags:
    # node.h = 0
    if DrawText in node.flags:
      node.h = builder.textHeight

  elif FillY in node.flags:
    node.h = parent.h - node.y

proc postLayoutChild*(builder: UINodeBuilder, node: UINode, child: UINode) =
  if SizeToContentX in node.flags:
    node.w = max(node.w, child.xw)

  if SizeToContentY in node.flags:
    node.h = max(node.h, child.yh)

proc postLayout*(builder: UINodeBuilder, node: UINode) =
  if node.parent.isNotNil:
    builder.postLayoutChild(node.parent, node)

  if SizeToContentX in node.flags:
    let childrenWidth = if node.last.isNotNil:
      node.last.x + node.last.w
    else: 0

    let strWidth = if DrawText in node.flags:
      builder.textWidth(node.text.runeLen.int)
    else: 0

    node.w = max(childrenWidth, strWidth)

  elif FillX in node.flags:
    assert node.parent.isNotNil
    node.w = node.parent.w - node.x

  if SizeToContentY in node.flags:
    let childrenHeight = if node.last.isNotNil:
      node.last.y + node.last.h
    else: 0

    let strHeight = if DrawText in node.flags:
      builder.textHeight
    else: 0

    node.h = max(childrenHeight, strHeight)

  elif FillY in node.flags:
    assert node.parent.isNotNil
    node.h = node.parent.h - node.y

  if node.parent.isNotNil:
    builder.postLayoutChild(node.parent, node)
    node.parent.mContentDirty = node.parent.mContentDirty or node.dirty

  if node.mContentDirty:
    node.mLastContentChange = builder.frameIndex
    node.mContentDirty = false

  if node.mPositionDirty:
    node.mLastPositionChange = builder.frameIndex
    node.mPositionDirty = false

  if node.mSizeDirty:
    node.mLastSizeChange = builder.frameIndex
    node.mSizeDirty = false

  # if recurse:
  #   debug "recurse ", node.dump
  #   for c in node.children:
  #     c.postLayout()

proc beginFrame*(builder: UINodeBuilder, size: Vec2) =
  builder.frameIndex.inc

  builder.currentParent = builder.root
  builder.currentChild = nil

  builder.root.x = 0
  builder.root.y = 0
  builder.root.w = size.x
  builder.root.h = size.y
  builder.root.flags = &{LayoutVertical}

proc endFrame*(builder: UINodeBuilder) =
  builder.nodePool.pruneUnused(builder.root, builder.currentChild)
  builder.postLayout(builder.root)

proc retain*(builder: UINodeBuilder) =
  if builder.currentChild.isNotNil and builder.currentChild.next.isNotNil:
    builder.currentChild = builder.currentChild.next
  elif builder.currentChild.isNil and builder.currentParent.first.isNotNil:
    builder.currentChild = builder.currentParent.first

  if builder.currentChild.isNotNil:
    builder.preLayout(builder.currentChild)
    builder.postLayout(builder.currentChild)

template panel*(builder: UINodeBuilder, inFlags: UINodeFlags, body: untyped): untyped =
  assert builder.currentParent.isNotNil
  # debug "panel ", inFlags, ", ", builder.currentParent.dump, ", ", builder.currentChild.dump

  var node = builder.nodePool.getNextOrNewNode(builder.currentParent, builder.currentChild)
  builder.currentChild = node

  node.flags = inFlags

  builder.preLayout(node)

  block:
    defer:
      builder.nodePool.pruneUnused(node, builder.currentChild)
      builder.postLayout(node)

      builder.currentParent = node.parent
      builder.currentChild = node

    builder.currentParent = node
    builder.currentChild = nil

    let currentNode {.used, inject.} = node

    template onClick(onClickBody: untyped) {.used.} =
      currentNode.handleClick = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
        # echo "clicked ", node.dump
        onClickBody

    template onDrag(button: MouseButton, delta: untyped, onDragBody: untyped) {.used.} =
      currentNode.handleDrag = proc(node: UINode, btn {.inject.}: MouseButton, d: Vec2): bool =
        if btn == button:
          let delta {.inject.} = d
          onDragBody

    body

proc findNodeContaining*(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool): Option[UINode] =
  result = UINode.none
  if pos.x < node.lx or pos.x > node.lx + node.lw or pos.y < node.ly or pos.y > node.ly + node.lh:
    return

  # echo "findNodeContaining ", node.dump, " at " ,pos, " with ", (node.lx, node.ly, node.lw, node.lh)

  if node.first.isNil:
    # has no children
    if predicate.isNotNil and not predicate(node):
      return

    return node.some

  else:
    # has children
    if predicate.isNotNil and predicate(node):
      return node.some

    for c in node.children:
      if c.findNodeContaining(pos, predicate).getSome(res):
        result = res.some

proc dump*(node: UINode, recurse = false): string =
  if node.isNil:
    return "nil"
  result.add fmt"Node({node.mLastContentChange}, {node.mLastPositionChange}, {node.mLastSizeChange}, {node.id} '{node.text}', {node.flags}, ({node.x}, {node.y}, {node.w}, {node.h}))"
  if recurse and node.first.isNotNil:
    result.add ":"
    for c in node.children:
      result.add "\n"
      result.add c.dump(recurse=recurse).indent(1, "  ")