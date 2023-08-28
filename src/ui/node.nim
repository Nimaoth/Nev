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
  UIContextRoot* = ref object of RootObj
  UIContext*[T] = ref object of UIContextRoot
    data*: T

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
    mInvalidated: bool
    mLastContentChange: int
    mLastPositionChange: int
    mLastSizeChange: int

    mContext: Option[UIContextRoot]

    mFlagsOld: UINodeFlags
    mFlags: UINodeFlags

    mText: string

    mBackgroundColor: Color
    mBorderColor: Color
    mTextColor: Color

    mBoundsOld: Rect
    bounds: Rect
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

func contentDirty*(node: UINode): bool = node.mContentDirty
proc `contentDirty=`*(node: UINode, value: bool) =
  node.mContentDirty = value

func id*(node: UINode): Id = node.mId
func dirty*(node: UINode): bool = node.contentDirty or node.mPositionDirty or node.mSizeDirty
func lastChange*(node: UINode): int = max(node.mLastContentChange, max(node.mLastPositionChange, node.mLastSizeChange))
func flags*(node: UINode): var UINodeFlags = node.mFlags
func text*(node: UINode): string = node.mText
func backgroundColor*(node: UINode): Color = node.mBackgroundColor
func borderColor*(node: UINode): Color = node.mBorderColor
func textColor*(node: UINode): Color = node.mTextColor

proc `flags=`*(node: UINode, value: UINodeFlags)     = node.mFlags        = value
proc `text=`*(node: UINode, value: string)           = node.contentDirty = node.contentDirty or (value != node.mText);            node.mText            = value
proc `backgroundColor=`*(node: UINode, value: Color) = node.contentDirty = node.contentDirty or (value != node.mBackgroundColor); node.mBackgroundColor = value
proc `borderColor=`*(node: UINode, value: Color)     = node.contentDirty = node.contentDirty or (value != node.mBorderColor);     node.mBorderColor     = value
proc `textColor=`*(node: UINode, value: Color)       = node.contentDirty = node.contentDirty or (value != node.mTextColor);       node.mTextColor       = value

func handlePressed*(node: UINode):        (proc(node: UINode, button: MouseButton): bool) = node.mHandlePressed
func handleReleased*(node: UINode):        (proc(node: UINode, button: MouseButton): bool) = node.mHandleReleased
func handleDrag*(node: UINode):         (proc(node: UINode, button: MouseButton, delta: Vec2): bool) = node.mHandleDrag
func handleBeginHover*(node: UINode): (proc(node: UINode): bool) = node.mHandleBeginHover
func handleEndHover*(node: UINode):   (proc(node: UINode): bool) = node.mHandleEndHover
func handleHover*(node: UINode):      (proc(node: UINode): bool) = node.mHandleHover

func `handlePressed=`*(node: UINode, value: proc(node: UINode, button: MouseButton): bool)                = node.mHandlePressed = value
func `handleReleased=`*(node: UINode, value: proc(node: UINode, button: MouseButton): bool)               = node.mHandleReleased = value
func `handleDrag=`* (node: UINode, value: proc(node: UINode, button: MouseButton, delta: Vec2): bool)     = node.mHandleDrag = value
func `handleBeginHover=`*(node: UINode, value: proc(node: UINode): bool)                                  = node.mHandleBeginHover = value
func `handleEndHover=`*(node: UINode,   value: proc(node: UINode): bool)                                  = node.mHandleEndHover = value
func `handleHover=`*(node: UINode,      value: proc(node: UINode): bool)                                  = node.mHandleHover = value

func xy*(node: UINode): Vec2 = node.bounds.xy

func x*(node: UINode): float32 = node.bounds.x
func y*(node: UINode): float32 = node.bounds.y
func w*(node: UINode): float32 = node.bounds.w
func h*(node: UINode): float32 = node.bounds.h
func xw*(node: UINode): float32 = node.bounds.xw
func yh*(node: UINode): float32 = node.bounds.yh
func wh*(node: UINode): Rect = rect(0, 0, node.bounds.w, node.bounds.h)

func lx*(node: UINode): float32 = node.mLx
func ly*(node: UINode): float32 = node.mLy
func lw*(node: UINode): float32 = node.mLw
func lh*(node: UINode): float32 = node.mLh
func lxw*(node: UINode): float32 = node.mLx + node.mLw
func lyh*(node: UINode): float32 = node.mLy + node.mLh

func `x=`*(node: UINode, value: float32) = node.bounds.x = value
func `y=`*(node: UINode, value: float32) = node.bounds.y = value
proc `w=`*(node: UINode, value: float32) = node.bounds.w = value
proc `h=`*(node: UINode, value: float32) = node.bounds.h = value

func `lx=`*(node: UINode, value: float32) = node.mLx = value
func `ly=`*(node: UINode, value: float32) = node.mLy = value
func `lw=`*(node: UINode, value: float32) = node.mLw = value
func `lh=`*(node: UINode, value: float32) = node.mLh = value

proc textWidth*(builder: UINodeBuilder, textLen: int): float32 = textLen.float32 * builder.charWidth
proc textHeight*(builder: UINodeBuilder): float32 = builder.lineHeight + builder.lineGap

proc unpoolNode*(pool: UINodePool): UINode
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
  result.root = result.nodePool.unpoolNode()

proc hovered*(builder: UINodeBuilder, node: UINode): bool = node.some == builder.hoveredNode

proc handleMousePressed*(builder: UINodeBuilder, button: MouseButton, pos: Vec2) =
  builder.mousePosClick[button] = pos

  let targetNode = builder.root.findNodeContaining(pos, (node) => node.handlePressed.isNotNil)
  if targetNode.getSome(node):
    discard node.handlePressed()(node, button)

proc handleMouseReleased*(builder: UINodeBuilder, button: MouseButton, pos: Vec2) =
  if builder.draggedNode.isSome:
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
    node.contentDirty = true
  node.mBackgroundColor.r = r
  node.mBackgroundColor.g = g
  node.mBackgroundColor.b = b
  node.mBackgroundColor.a = a

proc setBorderColor*(node: UINode, r, g, b: float32, a: float32 = 1) =
  if r != node.mBorderColor.r or g != node.mBorderColor.g or b != node.mBorderColor.b or node.mBorderColor.a != a:
    node.contentDirty = true
  node.mBorderColor.r = r
  node.mBorderColor.g = g
  node.mBorderColor.b = b
  node.mBorderColor.a = a

proc setTextColor*(node: UINode, r, g, b: float32, a: float32 = 1) =
  if r != node.mTextColor.r or g != node.mTextColor.g or b != node.mTextColor.b or node.mTextColor.a != a:
    node.contentDirty = true
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

proc unpoolNode*(pool: UINodePool): UINode =
  if pool.nodes.len > 0:
    # debug "reusing node ", pool.nodes[pool.nodes.high].id
    return pool.nodes.pop
  # defer:
    # debug "creating new node ", result.id
  result = UINode(mId: newId())
  pool.allNodes.add result

proc returnNode*(pool: UINodePool, node: UINode) =
  pool.nodes.add node

  for _, c in node.children:
    pool.returnNode c

  node.parent = nil
  node.first = nil
  node.last = nil
  node.next = nil
  node.prev = nil
  node.mFlags = 0.UINodeFlags
  node.mFlagsOld = 0.UINodeFlags

  node.mContext = UIContextRoot.none

  node.contentDirty = false
  node.mPositionDirty = false
  node.mSizeDirty = false
  node.mLastContentChange = 0
  node.mLastPositionChange = 0
  node.mLastSizeChange = 0

  node.mText = ""

  node.mBoundsOld.x = 0
  node.mBoundsOld.y = 0
  node.mBoundsOld.w = 0
  node.mBoundsOld.h = 0

  node.bounds.x = 0
  node.bounds.y = 0
  node.bounds.w = 0
  node.bounds.h = 0

  node.mLx = 0
  node.mLy = 0
  node.mLw = 0
  node.mLh = 0

  node.backgroundColor = color(0, 0, 0)
  node.textColor = color(1, 1, 1)
  node.borderColor = color(0.5, 0.5, 0.5)

  node.mHandlePressed = nil
  node.mHandleReleased = nil
  node.mHandleDrag = nil
  node.mHandleBeginHover = nil
  node.mHandleEndHover = nil
  node.mHandleHover = nil

  node.clearRect = Rect.none
  node.invalidationRect = Rect.none

proc getNextOrNewNode*(pool: UINodePool, node: UINode, last: UINode): UINode =
  if last.isNil:
    if node.first.isNotNil:
      return node.first

    let newNode = pool.unpoolNode()
    newNode.parent = node
    node.first = newNode
    node.last = newNode
    return newNode

  if last.next.isNotNil:
    assert last.next.parent == last.parent
    assert last.next.prev == last
    return last.next

  let newNode = pool.unpoolNode()
  newNode.parent = node
  newNode.prev = last
  last.next = newNode
  node.last = newNode
  return newNode

proc clearUnusedChildren*(pool: UINodePool, node: UINode, last: UINode): Option[Rect] =
  if last.isNil:
    for _, child in node.children:
      result = result or child.bounds.some
      pool.returnNode child
      node.contentDirty = true
    node.first = nil
    node.last = nil

  else:
    assert last.parent == node

    var n = last.next
    while n.isNotNil:
      let next = n.next
      result = result or n.bounds.some
      pool.returnNode n
      node.contentDirty = true
      n = next

    node.last = last
    last.next = nil

proc postLayout*(builder: UINodeBuilder, node: UINode)
proc postLayoutChild*(builder: UINodeBuilder, node: UINode, child: UINode)
proc relayout*(builder: UINodeBuilder, node: UINode)
proc preLayout*(builder: UINodeBuilder, node: UINode)

proc preLayout*(builder: UINodeBuilder, node: UINode) =
  let parent = node.parent

  if LayoutHorizontal in parent.flags:
    if node.prev.isNotNil:
      node.x = node.prev.x + node.prev.w

  if LayoutVertical in parent.flags:
    if node.prev.isNotNil:
      node.y = node.prev.y + node.prev.h

  if node.mFlags.all &{SizeToContentX, FillX}:
    if DrawText in node.flags:
      node.w = max(parent.w - node.x, builder.textWidth(node.text.runeLen.int))
    else:
      node.w = parent.w - node.x
  elif SizeToContentX in node.flags:
    if DrawText in node.flags:
      node.w = builder.textWidth(node.text.runeLen.int)
  elif FillX in node.flags:
    node.w = parent.w - node.x

  if node.mFlags.all &{SizeToContentY, FillY}:
    if DrawText in node.flags:
      node.h = max(parent.h - node.y, builder.textHeight)
    else:
      node.h = parent.h - node.y
  elif SizeToContentY in node.flags:
    if DrawText in node.flags:
      node.h = builder.textHeight
  elif FillY in node.flags:
    node.h = parent.h - node.y

proc relayout*(builder: UINodeBuilder, node: UINode) =
  builder.preLayout node
  for _, c in node.children:
    builder.relayout c
  builder.postLayout node

proc postLayoutChild*(builder: UINodeBuilder, node: UINode, child: UINode) =
  var recurse = false
  if SizeToContentX in node.flags and child.xw > node.w:
    node.w = child.xw
    recurse = true

  if SizeToContentY in node.flags and child.yh > node.h:
    node.h = child.yh
    recurse = true

  if recurse:
    for _, c in node.children:
      if c == child:
        break
      builder.relayout(c)

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

  if node.x != node.mBoundsOld.x or node.y != node.mBoundsOld.y:
    node.mPositionDirty = true
  if node.w != node.mBoundsOld.w or node.h != node.mBoundsOld.h:
    node.mSizeDirty = true

  if (node.mPositionDirty or node.mSizeDirty) and not node.bounds.contains(node.mBoundsOld):
    node.clearRect = some node.mBoundsOld.invalidationRect(node.bounds)
  else:
    node.clearRect = Rect.none

  node.mBoundsOld = node.bounds

  # mark content dirty if flags changed
  if node.mFlags != node.mFlagsOld:
    node.contentDirty = true
  node.mFlagsOld = node.mFlags

  # mark content dirty if intersects with current invalidation rect
  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi "postLayout, invalidate", builder.currentInvalidationRects.last.get, ", ", node.bounds, " -> ", builder.currentInvalidationRects.last.get.intersects(node.bounds)
    if builder.currentInvalidationRects.last.get.intersects(node.bounds):
      node.contentDirty = true

  # mark parent dirty if size or position changed
  if node.parent.isNotNil:
    builder.postLayoutChild(node.parent, node)

  if node.dirty and node.mFlags.any(&{DrawText, DrawBorder, FillBackground}):
    let existing = builder.forwardInvalidationRects[builder.forwardInvalidationRects.high]
    if existing.isSome:
      node.logi "postLayout: a: ",  existing.get, " , ", node.wh, " -> ", node.wh or existing.get
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some node.wh or existing.get
    else:
      node.logi "postLayout, b: ",  "none -> ", node.wh
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some node.wh

  for _, c in node.children:
    if c .lastChange == builder.frameIndex:
      node.contentDirty = true
      break

  # update last change indices
  if node.contentDirty:
    node.mLastContentChange = builder.frameIndex
    node.contentDirty = false

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

proc prepareNode(builder: UINodeBuilder, inFlags: UINodeFlags, inText: Option[string], inX, inY, inW, inH: Option[float32]): UINode =
  assert builder.currentParent.isNotNil

  if builder.currentChild.isNil: # first child, extent current invalidation rect if parent border dissappeared
    if invalidateOverlapping and DrawBorder in builder.currentParent.mFlagsOld and DrawBorder notin builder.currentParent.mFlags:
      builder.currentParent.logi "preLayout, border dissappeared, extend current invalidation rect ", builder.currentInvalidationRects.last, " , ", builder.currentParent.wh, " -> ", builder.currentParent.wh.some or builder.currentInvalidationRects.last
      builder.currentInvalidationRects.last = builder.currentInvalidationRects.last or builder.currentParent.wh.some

  var node = builder.nodePool.getNextOrNewNode(builder.currentParent, builder.currentChild)
  node.logp "panel begin"

  if builder.currentInvalidationRects.len > 0 and builder.currentInvalidationRects.last.isSome:
    node.logi fmt"panel, begin, current: {builder.currentInvalidationRects.last.get}"

  builder.currentChild = node

  node.flags = inFlags
  if inText.isSome: node.text = inText.get
  else: node.text = ""

  node.bounds.x = 0
  node.bounds.y = 0
  node.bounds.w = 0
  node.bounds.h = 0

  builder.preLayout(node)

  if inX.isSome: node.x = inX.get
  if inY.isSome: node.y = inY.get
  if inW.isSome: node.w = inW.get
  if inH.isSome: node.h = inH.get

  # Add current invalidation rect for new node, copying parent if it exists
  if builder.currentInvalidationRects.len > 0:
    if builder.currentInvalidationRects.last.isSome:
      node.logi "panel begin, copy invalidation rect from parent ", builder.currentInvalidationRects.last.get, ", ", node.bounds.xy, " -> ", builder.currentInvalidationRects.last.get - node.bounds.xy
      builder.currentInvalidationRects.add some(builder.currentInvalidationRects.last.get - node.bounds.xy)
    else:
      builder.currentInvalidationRects.add Rect.none
  else:
    builder.currentInvalidationRects.add Rect.none

  # invalidate if it intersects with the current invalidation rect
  if builder.currentInvalidationRects.last.isSome:
    node.logi "preLayout, invalidate", builder.currentInvalidationRects.last.get, ", ", node.wh, " -> ", builder.currentInvalidationRects.last.get.intersects(node.wh)
    if builder.currentInvalidationRects.last.get.intersects(node.wh):
      node.contentDirty = true

      if node.mFlags.any &{DrawText, FillBackground}:
        builder.currentInvalidationRects.last = builder.currentInvalidationRects.last or node.wh.some


  builder.currentParent = node
  builder.currentChild = nil
  builder.forwardInvalidationRects.add Rect.none

  return node

proc finishNode(builder: UINodeBuilder, currentNode: UINode) =
  # remove current invalidation rect
  assert builder.currentInvalidationRects.len > 0
  discard builder.currentInvalidationRects.pop

  currentNode.logp fmt"panel end"

  let clearedChildrenBounds = builder.nodePool.clearUnusedChildren(currentNode, builder.currentChild)
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
      builder.currentInvalidationRects.last = some builder.currentInvalidationRects.last.get or (invalidationRect.get + currentNode.bounds.xy)
    else:
      currentNode.logi "panel end, parent overlapping, new: ", invalidationRect.get + currentNode.bounds.xy
      builder.currentInvalidationRects.last = some invalidationRect.get + currentNode.bounds.xy

  #
  if builder.forwardInvalidationRects.len > 0:
    let existing = builder.forwardInvalidationRects[builder.forwardInvalidationRects.high]
    if existing.isSome and invalidationRect.isSome:
      currentNode.logi "panel, c: ",  existing.get, ", ", invalidationRect.get, " -> ", invalidationRect.get + currentNode.bounds.xy, " -> ", (invalidationRect.get + currentNode.bounds.xy) or existing.get
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some (invalidationRect.get + currentNode.bounds.xy) or existing.get
    elif invalidationRect.isSome:
      currentNode.logi "panel, d: ",  "none, ", invalidationRect.get, " -> ", invalidationRect.get + currentNode.bounds.xy
      builder.forwardInvalidationRects[builder.forwardInvalidationRects.high] = some invalidationRect.get + currentNode.bounds.xy

  if invalidateOverlapping and OverlappingChildren in currentNode.mFlags:
    # invalidate cleared areas backwards
    var rects: seq[Option[Rect]]

    var currRect = clearedChildrenBounds
    for child in currentNode.rchildren:
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

    # invalidate areas forwards one last time

    currRect = Rect.none
    for i, child in currentNode.children:
      if currRect.getSome(rec):
        discard builder.invalidateByRect(child, rec)

      # create/extend invalidation rect with child
      currRect = currRect or rects[^(i + 1)]

proc postProcessNode(builder: UINodeBuilder, node: UINode) =
  echo "postProcessNode ", node.dump

  for _, c in node.children:
    builder.postProcessNode(c)

proc postProcessNodes(builder: UINodeBuilder) =
  builder.postProcessNode(builder.root)


macro panel*(builder: UINodeBuilder, inFlags: UINodeFlags, args: varargs[untyped]): untyped =
  var body = genAst(): discard

  var inText = genAst(): string.none
  var inX = genAst(): float32.none
  var inY = genAst(): float32.none
  var inW = genAst(): float32.none
  var inH = genAst(): float32.none
  var inBackgroundColor = genAst(): Color.none
  var inBorderColor = genAst(): Color.none
  var inTextColor = genAst(): Color.none

  for i, arg in args:
    case arg
    of ExprEqExpr[(kind: _ in {nnkSym, nnkIdent}), @value]:
      let name = arg[0].repr
      case name
      of "text":
        inText = genAst(value): some(value)
      of "backgroundColor":
        inBackgroundColor = genAst(value): some(value)
      of "borderColor":
        inBorderColor = genAst(value): some(value)
      of "textColor":
        inTextColor = genAst(value): some(value)
      of "x":
        inX = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "y":
        inY = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "w":
        inW = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "h":
        inH = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      else:
        error("Unknown ui node property '" & name & "'", arg[0])

    elif i == args.len - 1:
      body = arg

    else:
      error("Only <name> = <value> is allowed here.", arg)

  return genAst(builder, inFlags, inText, inX, inY, inW, inH, body, inBackgroundColor, inBorderColor, inTextColor):
    var node = builder.prepareNode(inFlags, inText, inX, inY, inW, inH)

    if inBackgroundColor.isSome: node.backgroundColor = inBackgroundColor.get
    if inBorderColor.isSome:     node.borderColor     = inBorderColor.get
    if inTextColor.isSome:       node.textColor       = inTextColor.get

    block:
      let currentNode {.used, inject.} = node

      template onClick(onClickBody: untyped) {.used.} =
        currentNode.handlePressed = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
          onClickBody

      template onClick(button: MouseButton, onClickBody: untyped) {.used.} =
        currentNode.handlePressed = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
          if btn == button:
            onClickBody

      template onClick(button: MouseButton, ctx: untyped, onClickBody: untyped) {.used.} =
        type ContextType = UIContext[typeof(ctx)]
        let assign = if currentNode.mContext.isNone or not (currentNode.mContext.get of ContextType) or ContextType(currentNode.mContext.get).data != ctx:
          currentNode.mContext = ContextType(data: ctx).UIContextRoot.some
          true
        else:
          currentNode.handlePressed.isNil

        if assign:
          currentNode.handlePressed = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
            if btn == button:
              onClickBody

      template onReleased(onBody: untyped) {.used.} =
        currentNode.handleReleased = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton): bool =
          onBody

      template onDrag(button: MouseButton, onDragBody: untyped) {.used.} =
        currentNode.handleDrag = proc(node: UINode, btn {.inject.}: MouseButton, d: Vec2): bool =
          if btn == button:
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

  if node.first.isNil: # has no children
    if predicate.isNotNil and not predicate(node):
      return

    return node.some

  else: # has children
    for c in node.rchildren:
      if c.findNodeContaining(pos, predicate).getSome(res):
        return res.some

    if predicate.isNotNil and predicate(node):
      return node.some

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
  # builder.postProcessNodes()
  discard builder.nodePool.clearUnusedChildren(builder.root, builder.currentChild)
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
  result.add fmt"Node({node.mLastContentChange} ({node.contentDirty}), {node.mLastPositionChange} ({node.mPositionDirty}), {node.mLastSizeChange} ({node.mSizeDirty}), {node.id} '{node.text}', {node.flags}, ({node.x}, {node.y}, {node.w}, {node.h}), {node.mBoundsOld})"
  if recurse and node.first.isNotNil:
    result.add ":"
    for _, c in node.children:
      result.add "\n"
      result.add c.dump(recurse=recurse).indent(1, "  ")