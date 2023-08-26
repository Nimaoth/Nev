import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options]
import fusion/matching
import macro_utils, util, id, input, custom_unicode
import chroma, vmath, rect_utils
import custom_logger

export util, id, input, chroma, vmath, rect_utils

logCategory "ui-node"

var logInvalidationRects* = false
var logPanel* = false
var invalidateOverlapping* = true

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
    MouseHover

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

    mFlagsOld: UINodeFlags
    mFlags: UINodeFlags

    mText: string

    mBackgroundColor: Color
    mBorderColor: Color
    mTextColor: Color

    mBoundsOld: Option[Rect]
    mX, mY, mW, mH: float32
    mLx, mLy, mLw, mLh: float32

    clearRect: Option[Rect] # Rect which describes the area the widget occupied in the previous frame but not in the current frame
    invalidationRect: Option[Rect] # Rect which describes the area which needs to rerendered, and therefore invalidate later siblings in overlay contexts

    mHandlePressed: proc(node: UINode, button: MouseButton): bool
    mHandleReleased: proc(node: UINode, button: MouseButton): bool
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
    hoveredNode*: Option[UINode] = UINode.none

    forwardInvalidationRects: seq[Option[Rect]]
    currentInvalidationRects: seq[Option[Rect]]
    backInvalidationRects: seq[Option[Rect]]

    mousePos: Vec2
    mouseDelta: Vec2
    mousePosClick: array[MouseButton, Vec2]

proc dump*(node: UINode, recurse = false): string

func parent*(node: UINode): UINode = node.parent
func first*(node: UINode): UINode = node.first
func last*(node: UINode): UINode = node.last
func next*(node: UINode): UINode = node.next
func prev*(node: UINode): UINode = node.prev

func id*(node: UINode): Id = node.mId
func dirty*(node: UINode): bool = node.mContentDirty or node.mPositionDirty or node.mSizeDirty
func lastChange*(node: UINode): int = max(node.mLastContentChange, max(node.mLastPositionChange, node.mLastSizeChange))
func flags*(node: UINode): var UINodeFlags = node.mFlags
func text*(node: UINode): string = node.mText
func backgroundColor*(node: UINode): Color = node.mBackgroundColor
func borderColor*(node: UINode): Color = node.mBorderColor
func textColor*(node: UINode): Color = node.mTextColor

func `flags=`*(node: UINode, value: UINodeFlags)     = node.mContentDirty = node.mContentDirty or (value != node.mFlags);           node.mFlags           = value
func `text=`*(node: UINode, value: string)           = node.mContentDirty = node.mContentDirty or (value != node.mText);            node.mText            = value
func `backgroundColor=`*(node: UINode, value: Color) = node.mContentDirty = node.mContentDirty or (value != node.mBackgroundColor); node.mBackgroundColor = value
func `borderColor=`*(node: UINode, value: Color)     = node.mContentDirty = node.mContentDirty or (value != node.mBorderColor);     node.mBorderColor     = value
func `textColor=`*(node: UINode, value: Color)       = node.mContentDirty = node.mContentDirty or (value != node.mTextColor);       node.mTextColor       = value

func handlePressed*(node: UINode):        (proc(node: UINode, button: MouseButton): bool) = node.mHandlePressed
func handleReleased*(node: UINode):        (proc(node: UINode, button: MouseButton): bool) = node.mHandleReleased
func handleDrag*(node: UINode):         (proc(node: UINode, button: MouseButton, delta: Vec2): bool) = node.mHandleDrag
func handleBeginHover*(node: UINode): (proc(node: UINode): bool) = node.mHandleBeginHover
func handleEndHover*(node: UINode):   (proc(node: UINode): bool) = node.mHandleEndHover
func handleHover*(node: UINode):      (proc(node: UINode): bool) = node.mHandleHover

func `handlePressed=`*(node: UINode, value: proc(node: UINode, button: MouseButton): bool)              = node.mContentDirty = node.mContentDirty or (value != node.mHandlePressed);        node.mHandlePressed = value
func `handleReleased=`*(node: UINode, value: proc(node: UINode, button: MouseButton): bool)              = node.mContentDirty = node.mContentDirty or (value != node.mHandleReleased);        node.mHandleReleased = value
func `handleDrag=`* (node: UINode, value: proc(node: UINode, button: MouseButton, delta: Vec2): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleDrag);         node.mHandleDrag = value
func `handleBeginHover=`*(node: UINode, value: proc(node: UINode): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleBeginHover); node.mHandleBeginHover = value
func `handleEndHover=`*(node: UINode,   value: proc(node: UINode): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleEndHover);   node.mHandleEndHover = value
func `handleHover=`*(node: UINode,      value: proc(node: UINode): bool) = node.mContentDirty = node.mContentDirty or (value != node.mHandleHover);      node.mHandleHover = value

func bounds*(node: UINode): Rect = rect(node.mX, node.mY, node.mW, node.mH)
func xy*(node: UINode): Vec2 = vec2(node.mX, node.mY)

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
proc findNodeContaining*(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool): Option[UINode]

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

proc hovered*(builder: UINodeBuilder, node: UINode): bool = node.some == builder.hoveredNode

proc handleMousePressed*(builder: UINodeBuilder, button: MouseButton, pos: Vec2) =
  builder.mousePosClick[button] = pos

  let targetNode = builder.root.findNodeContaining(pos, (node) => node.handlePressed.isNotNil)
  if targetNode.getSome(node):
    discard node.handlePressed()(node, button)

proc handleMouseReleased*(builder: UINodeBuilder, button: MouseButton, pos: Vec2) =
  if builder.draggedNode.getSome(node):
    builder.draggedNode = UINode.none

proc handleMouseMoved*(builder: UINodeBuilder, pos: Vec2, buttons: set[MouseButton]): bool =
  builder.mouseDelta = pos - builder.mousePos
  builder.mousePos = pos

  var targetNode: Option[UINode] = builder.draggedNode

  if buttons.len > 0:
    if builder.draggedNode.getSome(node):
      for button in buttons:
        discard node.handleDrag()(node, button, builder.mouseDelta)
        result = true

  if targetNode.isNone:
    targetNode = builder.root.findNodeContaining(pos, (node) => MouseHover in node.mFlags)

  case (builder.hoveredNode, targetNode)
  of (Some(@a), Some(@b)):
    if a == b:
      if a.handleHover.isNotNil:
        result = a.handleHover()(a) or result
    else:
      if a.handleEndHover.isNotNil:
        result = a.handleEndHover()(a) or result
      if b.handleBeginHover.isNotNil:
        result = b.handleBeginHover()(b) or result
      result = true

  of (None(), Some(@b)):
    if b.handleBeginHover.isNotNil:
      result = b.handleBeginHover()(b) or result
    result = true
  of (Some(@a), None()):
    if a.handleEndHover.isNotNil:
      result = a.handleEndHover()(a) or result
    result = true
  of (None(), None()):
    discard

  builder.hoveredNode = targetNode

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

iterator children*(node: UINode): (int, UINode) =
  var i = 0
  var current = node.first
  while current.isNotNil:
    defer: inc i
    let next = current.next
    yield (i, current)
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
  for _, c in node.children:
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

  node.mBoundsOld = Rect.none

  node.mX = 0
  node.mY = 0
  node.mW = 0
  node.mH = 0

  node.mLx = 0
  node.mLy = 0
  node.mLw = 0
  node.mLh = 0

  node.mHandlePressed = nil
  node.mHandleReleased = nil
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
    for _, child in node.children:
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

  # invalidate if it intersects with the current invalidation rect
  if builder.currentInvalidationRects.last.isSome:
    node.logi "preLayout, invalidate", builder.currentInvalidationRects.last.get, ", ", rect(0, 0, node.mW, node.mH), " -> ", builder.currentInvalidationRects.last.get.intersects(rect(0, 0, node.mW, node.mH))
    if builder.currentInvalidationRects.last.get.intersects(rect(0, 0, node.mW, node.mH)):
      node.mContentDirty = true

      if node.mFlags.any &{DrawText, FillBackground}:
        builder.currentInvalidationRects.last = builder.currentInvalidationRects.last or rect(0, 0, node.mW, node.mH).some

  # invalidate if border dissappeared
  if invalidateOverlapping and DrawBorder in node.mFlagsOld and DrawBorder notin node.mFlags:
    builder.currentInvalidationRects.last = builder.currentInvalidationRects.last or rect(0, 0, node.mW, node.mH).some

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

  node.clearRect = Rect.none

  if node.mBoundsOld.getSome(b):
    if node.mX != b.x or node.mY != b.y:
      node.mPositionDirty = true
    if node.mW != b.w or node.mH != b.h:
      node.mSizeDirty = true

    if node.mPositionDirty or node.mSizeDirty and not node.bounds.contains(b):
      # echo "invalidate ", b.invalidationRect(node.bounds)
      node.clearRect = some b.invalidationRect(node.bounds)

  else:
    node.mPositionDirty = true
    node.mSizeDirty = true

  node.mBoundsOld = some node.bounds
  node.mFlagsOld = node.mFlags

  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi "postLayout, invalidate", builder.currentInvalidationRects.last.get, ", ", node.bounds, " -> ", builder.currentInvalidationRects.last.get.intersects(node.bounds)
    if builder.currentInvalidationRects.last.get.intersects(node.bounds):
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

  if node.mContentDirty:
    node.mLastContentChange = builder.frameIndex
    node.mContentDirty = false

  if node.mPositionDirty:
    node.mLastPositionChange = builder.frameIndex
    node.mPositionDirty = false

  if node.mSizeDirty:
    node.mLastSizeChange = builder.frameIndex
    node.mSizeDirty = false

proc invalidateByRect*(builder: UINodeBuilder, node: UINode, rect: Rect): Option[Rect] =
  if not node.bounds.intersects(rect):
    return Rect.none

  node.mLastContentChange = builder.frameIndex

  if node.mFlags.any &{DrawText, DrawBorder, FillBackground}:
    result = node.bounds.some

  for _, c in node.children:
    let childRect = builder.invalidateByRect(c, rect - node.xy)

    result = result or (childRect + node.xy.some)

proc prepareNode(builder: UINodeBuilder, inFlags: UINodeFlags): UINode =
  assert builder.currentParent.isNotNil

  var node = builder.nodePool.getNextOrNewNode(builder.currentParent, builder.currentChild)
  node.logp "panel begin"

  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi fmt"panel, begin, current: {builder.currentInvalidationRects.last.get}"

  builder.currentChild = node

  node.flags = inFlags

  builder.preLayout(node)

  builder.currentParent = node
  builder.currentChild = nil
  builder.forwardInvalidationRects.add Rect.none

  return node

proc finishNode(builder: UINodeBuilder, currentNode: UINode) =
  # remove current invalidation rect
  assert builder.currentInvalidationRects.len > 0
  discard builder.currentInvalidationRects.pop

  currentNode.logp fmt"panel end"

  builder.nodePool.clearUnusedChildren(currentNode, builder.currentChild)
  builder.postLayout(currentNode)

  builder.currentParent = currentNode.parent
  builder.currentChild = currentNode

  # Extend current invalidation rect by forward validation rect
  let invalidationRect = builder.forwardInvalidationRects.pop
  currentNode.invalidationRect = invalidationRect
  if invalidationRect.isSome: currentNode.logi "invalidation rect: ", invalidationRect.get
  if invalidationRect.isSome and OverlappingChildren in currentNode.parent.mFlags:
    if builder.currentInvalidationRects.last.isSome:
      currentNode.logi "panel end, parent overlapping, extend: ", builder.currentInvalidationRects.last.get, " or ", invalidationRect.get, " -> ", builder.currentInvalidationRects.last.get or invalidationRect.get
      builder.currentInvalidationRects.last = some builder.currentInvalidationRects.last.get or (invalidationRect.get + vec2(currentNode.mX, currentNode.mY))
    else:
      currentNode.logi "panel end, parent overlapping, new: ", invalidationRect.get + vec2(currentNode.mX, currentNode.mY)
      builder.currentInvalidationRects.last = some invalidationRect.get + vec2(currentNode.mX, currentNode.mY)

  #
  if builder.forwardInvalidationRects.len > 0:
    let existing = builder.forwardInvalidationRects[builder.forwardInvalidationRects.high]
    if existing.isSome and invalidationRect.isSome:
      currentNode.logi "panel, c: ",  existing.get, ", ", invalidationRect.get, " -> ", invalidationRect.get + vec2(currentNode.mX, currentNode.mY), " -> ", (invalidationRect.get + vec2(currentNode.mX, currentNode.mY)) or existing.get
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some (invalidationRect.get + vec2(currentNode.mX, currentNode.mY)) or existing.get
    elif invalidationRect.isSome:
      currentNode.logi "panel, d: ",  "none, ", invalidationRect.get, " -> ", invalidationRect.get + vec2(currentNode.mX, currentNode.mY)
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some invalidationRect.get + vec2(currentNode.mX, currentNode.mY)

  if invalidateOverlapping and OverlappingChildren in currentNode.mFlags:
    # invalidate cleared areas backwards
    # echo "backwards pass"
    var rects: seq[Option[Rect]]

    var currRect = Rect.none
    for child in currentNode.rchildren:
      # echo currRect
      if currRect.getSome(rec):
        rects.add builder.invalidateByRect(child, rec)
      else:
        rects.add Rect.none

      # create/extend invalidation rect with child
      if child.clearRect.getSome(rec):
        if currRect.getSome(curr):
          currRect = some curr or rec
        else:
          currRect = some rec

    # echo rects
    # invalidate areas forwards one last time

    # echo "forwards pass"
    currRect = Rect.none
    for i, child in currentNode.children:
      # echo currRect
      if currRect.getSome(rec):
        discard builder.invalidateByRect(child, rec)

      # create/extend invalidation rect with child
      currRect = currRect or rects[^(i + 1)]

template panel*(builder: UINodeBuilder, inFlags: UINodeFlags, body: untyped): untyped =
  var node = builder.prepareNode(inFlags)

  block:
    let currentNode {.used, inject.} = node

    template onClick(onClickBody: untyped) {.used.} =
      currentNode.handlePressed = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
        onClickBody

    template onReleased(onBody: untyped) {.used.} =
      currentNode.handleReleased = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
        onBody

    template onDrag(button: MouseButton, delta: untyped, onDragBody: untyped) {.used.} =
      currentNode.handleDrag = proc(node: UINode, btn {.inject.}: MouseButton, d: Vec2): bool =
        if btn == button:
          let delta {.inject.} = d
          onDragBody

    template onBeginHover(onBody: untyped) {.used.} =
      currentNode.handleBeginHover = proc(node: UINode): bool =
        onBody

    template onEndHover(onBody: untyped) {.used.} =
      currentNode.handleEndHover = proc(node: UINode): bool =
        onBody

    template onHover(onBody: untyped) {.used.} =
      currentNode.handleHover = proc(node: UINode): bool =
        onBody

    inc stackSize
    defer:
      dec stackSize
      builder.finishNode(currentNode)

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

    for _, c in node.children:
      if c.findNodeContaining(pos, predicate).getSome(res):
        result = res.some

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

proc dump*(node: UINode, recurse = false): string =
  if node.isNil:
    return "nil"
  result.add fmt"Node({node.mLastContentChange} ({node.mContentDirty}), {node.mLastPositionChange} ({node.mPositionDirty}), {node.mLastSizeChange} ({node.mSizeDirty}), {node.id} '{node.text}', {node.flags}, ({node.x}, {node.y}, {node.w}, {node.h}))"
  if recurse and node.first.isNotNil:
    result.add ":"
    for _, c in node.children:
      result.add "\n"
      result.add c.dump(recurse=recurse).indent(1, "  ")