import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options]
import macro_utils, util, id, input, custom_unicode
import chroma, vmath, rect_utils
import custom_logger

export util, id, input, chroma, vmath, rect_utils

logCategory "ui-node"

var logInvalidationRects* = false
var logPanel* = false

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

    mXOld, mYOld, mWOld, mHOld: float32
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

    draggedNode*: Option[UINode] = UINode.none

    forwardInvalidationRects: seq[Option[Rect]]
    currentInvalidationRects: seq[Option[Rect]]
    backInvalidationRects: seq[Option[Rect]]

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

func `x=`*(node: UINode, value: float32) = node.mX = value
func `y=`*(node: UINode, value: float32) = node.mY = value
proc `w=`*(node: UINode, value: float32) = node.mW = value
proc `h=`*(node: UINode, value: float32) = node.mH = value

func `lx=`*(node: UINode, value: float32) = node.mLx = value
func `ly=`*(node: UINode, value: float32) = node.mLy = value
func `lw=`*(node: UINode, value: float32) = node.mLw = value
func `lh=`*(node: UINode, value: float32) = node.mLh = value

proc textWidth*(builder: UINodeBuilder, textLen: int): float32 = textLen.float32 * builder.charWidth
proc textHeight*(builder: UINodeBuilder): float32 = builder.lineHeight + builder.lineGap

proc createNode*(pool: UINodePool): UINode

var stackSize = 0
template logi(node: UINode, msg: varargs[string, `$`]) =
  if logInvalidationRects:
    var uiae = ""
    for c in msg:
      uiae.add $c
    echo "  ".repeat(stackSize), "i: ", uiae, "    | ", node.dump, ""

template logp(node: UINode, msg: untyped) =
  if logPanel:
    echo "  ".repeat(stackSize), "p: ", msg, "    | ", node.dump, ""

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

iterator rchildren*(node: UINode): UINode =
  var current = node.last
  while current.isNotNil:
    let prev = current.prev
    yield current
    current = prev

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

  node.mXOld = 0
  node.mYOld = 0
  node.mWOld = 0
  node.mHOld = 0

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

proc clearUnusedChildren*(pool: UINodePool, node: UINode, last: UINode) =
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

  # Add current invalidation rect for new node, copying parent if it exists
  if builder.currentInvalidationRects.len > 0:
    if builder.currentInvalidationRects.last.isSome:
      node.logi "panel begin, copy invalidation rect from parent ", builder.currentInvalidationRects.last.get, ", ", vec2(node.mX, node.mY), " -> ", builder.currentInvalidationRects.last.get - vec2(node.mX, node.mY)
      builder.currentInvalidationRects.add some(builder.currentInvalidationRects.last.get - vec2(node.mX, node.mY))
    else:
      builder.currentInvalidationRects.add Rect.none
  else:
    builder.currentInvalidationRects.add Rect.none

  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi "preLayout, invalidate", builder.currentInvalidationRects.last.get, ", ", rect(0, 0, node.mW, node.mH), " -> ", builder.currentInvalidationRects.last.get.intersects(rect(0, 0, node.mW, node.mH))
    if builder.currentInvalidationRects.last.get.intersects(rect(0, 0, node.mW, node.mH)):
      node.mContentDirty = true

      if node.mFlags.any &{DrawText, FillBackground}:
        if builder.currentInvalidationRects.last.isSome:
          builder.currentInvalidationRects.last = some(builder.currentInvalidationRects.last.get or rect(0, 0, node.mW, node.mH))
        else:
          builder.currentInvalidationRects.last = some rect(0, 0, node.mW, node.mH)

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

  if node.mX != node.mXOld or node.mY != node.mYOld:
    node.mPositionDirty = true
  if node.mW != node.mWOld or node.mH != node.mHOld:
    node.mSizeDirty = true

  node.mXOld = node.mX
  node.mYOld = node.mY
  node.mWOld = node.mW
  node.mHOld = node.mH

  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi "postLayout, invalidate", builder.currentInvalidationRects.last.get, ", ", rect(node.mX, node.mY, node.mW, node.mH), " -> ", builder.currentInvalidationRects.last.get.intersects(rect(node.mX, node.mY, node.mW, node.mH))
    if builder.currentInvalidationRects.last.get.intersects(rect(node.mX, node.mY, node.mW, node.mH)):
      node.mContentDirty = true

  if node.parent.isNotNil:
    builder.postLayoutChild(node.parent, node)
    node.parent.mContentDirty = node.parent.mContentDirty or node.dirty

  if node.dirty and node.mFlags.any(&{DrawText, DrawBorder, FillBackground}):
    let existing = builder.forwardInvalidationRects[builder.forwardInvalidationRects.high]
    if existing.isSome:
      node.logi "postLayout: a: ",  existing.get, " , ", rect(0, 0, node.mW, node.mH), " -> ", rect(0, 0, node.mW, node.mH) or existing.get
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some rect(0, 0, node.mW, node.mH) or existing.get
    else:
      node.logi "postLayout, b: ",  "none -> ", rect(0, 0, node.mW, node.mH)
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some rect(0, 0, node.mW, node.mH)

  # if OverlappingChildren in parent.mFlags:


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
  builder.nodePool.clearUnusedChildren(builder.root, builder.currentChild)
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
  node.logp "panel begin"

  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi fmt"panel, begin, current: {builder.currentInvalidationRects.last.get}"

  if OverlappingChildren in builder.currentParent.mFlags and builder.currentChild.isNotNil:
    let current = builder.currentInvalidationRects.last

  builder.currentChild = node

  node.flags = inFlags

  builder.preLayout(node)

  block:
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

    builder.currentParent = currentNode
    builder.currentChild = nil
    builder.forwardInvalidationRects.add Rect.none

    # if currentNode.mFlags.any &{DrawText, FillBackground}:
    #   if builder.currentInvalidationRects.last.isSome:
    #     builder.currentInvalidationRects.last = some(builder.currentInvalidationRects.last.get or rect(0, 0, currentNode.mW, currentNode.mH))
    #   else:
    #     builder.currentInvalidationRects.last = some rect(0, 0, currentNode.mW, currentNode.mH)

    # if OverlappingChildren in currentNode.mFlags:
    #   if builder.currentInvalidationRects.len > 0:
    #     currentNode.logi "panel, begin, overlapping, current, todo"
    #     if builder.currentInvalidationRects.last.isSome:
    #       builder.currentInvalidationRects.add some(builder.currentInvalidationRects.last.get) # todo: offset to get from parent space to local space
    #     else:
    #       builder.currentInvalidationRects.add Rect.none
    #   else:
    #     currentNode.logi "panel, begin, overlapping, no current, add Rect.none"
    #     builder.currentInvalidationRects.add Rect.none

    inc stackSize
    defer:
      dec stackSize

      # remove current invalidation rect
      assert builder.currentInvalidationRects.len > 0
      discard builder.currentInvalidationRects.pop

      currentNode.logp fmt"panel end"

      builder.nodePool.clearUnusedChildren(currentNode, builder.currentChild)
      builder.postLayout(currentNode)

      builder.currentParent = currentNode.parent
      builder.currentChild = currentNode

      let invalidationRect = builder.forwardInvalidationRects.pop
      if invalidationRect.isSome: currentNode.logi "invalidation rect: ", invalidationRect.get
      if invalidationRect.isSome and OverlappingChildren in currentNode.parent.mFlags:
        if builder.currentInvalidationRects.last.isSome:
          currentNode.logi "panel end, parent overlapping, extend: ", builder.currentInvalidationRects.last.get, " or ", invalidationRect.get, " -> ", builder.currentInvalidationRects.last.get or invalidationRect.get
          builder.currentInvalidationRects.last = some builder.currentInvalidationRects.last.get or (invalidationRect.get + vec2(currentNode.mX, currentNode.mY))
        else:
          currentNode.logi "panel end, parent overlapping, new: ", invalidationRect.get + vec2(currentNode.mX, currentNode.mY)
          builder.currentInvalidationRects.last = some invalidationRect.get + vec2(currentNode.mX, currentNode.mY)

      if builder.forwardInvalidationRects.len > 0:
        let existing = builder.forwardInvalidationRects[builder.forwardInvalidationRects.high]
        if existing.isSome and invalidationRect.isSome:
          currentNode.logi "panel, c: ",  existing.get, ", ", invalidationRect.get, " -> ", invalidationRect.get + vec2(currentNode.mX, currentNode.mY), " -> ", (invalidationRect.get + vec2(currentNode.mX, currentNode.mY)) or existing.get
          builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some (invalidationRect.get + vec2(currentNode.mX, currentNode.mY)) or existing.get
        elif invalidationRect.isSome:
          currentNode.logi "panel, d: ",  "none, ", invalidationRect.get, " -> ", invalidationRect.get + vec2(currentNode.mX, currentNode.mY)
          builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some invalidationRect.get + vec2(currentNode.mX, currentNode.mY)

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
  result.add fmt"Node({node.mLastContentChange} ({node.mContentDirty}), {node.mLastPositionChange} ({node.mPositionDirty}), {node.mLastSizeChange} ({node.mSizeDirty}), {node.id} '{node.text}', {node.flags}, ({node.x}, {node.y}, {node.w}, {node.h}))"
  if recurse and node.first.isNotNil:
    result.add ":"
    for c in node.children:
      result.add "\n"
      result.add c.dump(recurse=recurse).indent(1, "  ")