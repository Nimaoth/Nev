import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, tables, sets]
import fusion/matching
import chroma, vmath
import misc/[macro_utils, util, id, custom_unicode, array_set, rect_utils, custom_logger]
import input, render_command

export util, id, input, chroma, vmath, rect_utils
export render_command

{.push gcsafe.}
{.push raises: [].}
{.push stacktrace:off.}
{.push linetrace:off.}

logCategory "ui-node"

const logInvalidationRects* = false
const logPanel* = false
var totalNodes = 0

when defined(uiNodeDebugData):
  import std/json
  type UINodeDebugData* = object
    id*: cstring
    metaData*: JsonNode
    css*: seq[string]
else:
  type UINodeDebugData* = object

type
  UIUserIdKind* = enum None, Primary, Secondary
  UIUserId* = object
    case kind*: UIUserIdKind
    of Primary:
      id*: Id
    of Secondary:
      parentId*: Id
      subId*: int32
    else: discard

  UINode* = ref UINodeObject
  UINodeObject* = object
    aDebugData*: UINodeDebugData

    parent: UINode
    first*: UINode
    last*: UINode
    prev: UINode
    next: UINode

    mId: Id
    userId*: UIUserId = UIUserId(kind: None)
    userData*: ref RootObj
    mContentDirty: bool
    mLastContentChange: int
    mLastPositionChange: int
    mLastSizeChange: int
    mLastClearInvalidation: int
    mLastDrawInvalidation: int
    lastRenderTime*: int

    mFlagsOld: UINodeFlags
    flags: UINodeFlags

    mText: string
    mTextRuneLen: int
    mTextNarrow: bool

    mBackgroundColor: Color
    mBorderColor: Color
    mTextColor: Color
    mUnderlineColor: Color

    pivot*: Vec2
    boundsRaw: Rect       # The target bounds, used for layouting.
    boundsOld: Rect       # The last boundsActual
    boundsActual*: Rect   # The actual bounds, used for rendering and invalidation. If not animated then the boundsActual will immediately snap to this position, otherwise it will smoothly interpolate.
    boundsAbsolute*: Rect # The absolute bounds (relative to the root), based on boundsActual

    boundsLerpSpeed: float32 = 0.03

    clearRect: Option[Rect] # Rect which describes the area the widget occupied in the previous frame but not in the current frame
    clearedChildrenBounds: Option[Rect] # Rect which describes the area the widget occupied in the previous frame but not in the current frame
    drawRect: Option[Rect]

    mHandlePressed: proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool {.gcsafe, raises: [].}
    mHandleReleased: proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool {.gcsafe, raises: [].}
    mHandleDrag: proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2, delta: Vec2): bool {.gcsafe, raises: [].}
    mHandleBeginHover: proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].}
    mHandleEndHover: proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].}
    mHandleHover: proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].}
    mHandleScroll: proc(node: UINode, pos: Vec2, delta: Vec2, modifiers: set[Modifier]): bool {.gcsafe, raises: [].}
    renderCommands*: seq[RenderCommand]

  UINodeBuilder* = ref object
    nodes: seq[UINode]
    namedNodes: Table[Id, UINode]

    textWidthImpl*: proc(node: UINode): float32 {.gcsafe, raises: [].}
    textWidthStringImpl*: proc(text: string): float32 {.gcsafe, raises: [].}
    useInvalidation*: bool = false

    currentChild*: UINode = nil
    currentParent*: UINode = nil
    root*: UINode = nil
    frameIndex*: int = 0
    charWidth*: float32
    lineHeight*: float32
    lineGap*: float32

    draggedNodes*: seq[UINode]
    hoveredNodes*: seq[UINode]

    animatingNodes*: seq[Id]
    frameTime*: float32 = 0.1
    animationSpeedModifier*: float32 = 1

    mousePos: Vec2
    mouseDelta: Vec2
    mousePosClick: array[MouseButton, Vec2]

let noneUserId* = UIUserId(kind: None)
proc newPrimaryId*(id: Id = newId()): UIUserId = UIUserId(kind: Primary, id: id)
proc newSecondaryId*(primary: Id, secondary: int32): UIUserId = UIUserId(kind: Secondary, parentId: primary, subId: secondary)
func `==`*(a, b: UIUserId): bool =
  if a.kind != b.kind:
    return false
  return case a.kind
  of None: true
  of Primary: a.id == b.id
  of Secondary: a.subId == b.subId and a.parentId == b.parentId

proc dump*(node: UINode, recurse = false): string

func parent*(node: UINode): UINode {.inline.} = node.parent
func first*(node: UINode): UINode {.inline.} = node.first
func last*(node: UINode): UINode {.inline.} = node.last
func next*(node: UINode): UINode {.inline.} = node.next
func prev*(node: UINode): UINode {.inline.} = node.prev

func contentDirty*(node: UINode): bool {.inline.} = node.mContentDirty
proc `contentDirty=`*(node: UINode, value: bool) {.inline.} =
  # if not node.mContentDirty and value:
  #   echo getStackTrace()
  node.mContentDirty = value

func id*(node: UINode): lent Id {.inline.} = node.mId
func text*(node: UINode): lent string {.inline.} = node.mText
func backgroundColor*(node: UINode): Color {.inline.} = node.mBackgroundColor
func borderColor*(node: UINode): Color {.inline.} = node.mBorderColor
func textColor*(node: UINode): Color {.inline.} = node.mTextColor
func underlineColor*(node: UINode): Color {.inline.} = node.mUnderlineColor

func flags*(node: UINode): UINodeFlags {.inline.} = node.flags

func lastChange*(node: UINode): int {.inline.} = max(node.mLastContentChange, max(node.mLastPositionChange, max(node.mLastSizeChange, max(node.mLastClearInvalidation, node.mLastDrawInvalidation))))
func lastSizeChange*(node: UINode): int {.inline.} = node.mLastSizeChange

func isNarrow(text: string): bool =
  result = true
  for r in text.runes:
    if r.int32 > 0xff:
      return false

proc `text=`*(node: UINode, value: string)           {.inline.} =
  let changed = (value != node.mText)
  node.contentDirty = node.contentDirty or changed
  if changed:
    node.mText = value
    node.mTextRuneLen = value.runeLen.int
    node.mTextNarrow = node.mText.isNarrow

proc textRuneLen*(node: UINode): int = node.mTextRuneLen

proc `backgroundColor=`*(node: UINode, value: Color) {.inline.} = (let changed = (value != node.mBackgroundColor); node.contentDirty = node.contentDirty or changed; if changed: node.mBackgroundColor = value else: discard)
proc `borderColor=`*(node: UINode, value: Color)     {.inline.} = (let changed = (value != node.mBorderColor);     node.contentDirty = node.contentDirty or changed; if changed: node.mBorderColor     = value else: discard)
proc `textColor=`*(node: UINode, value: Color)       {.inline.} = (let changed = (value != node.mTextColor);       node.contentDirty = node.contentDirty or changed; if changed: node.mTextColor       = value else: discard)
proc `underlineColor=`*(node: UINode, value: Color)  {.inline.} = (let changed = (value != node.mUnderlineColor);  node.contentDirty = node.contentDirty or changed; if changed: node.mUnderlineColor  = value else: discard)

func handlePressed*   (node: UINode): (proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool {.gcsafe, raises: [].})              {.inline.} = node.mHandlePressed
func handleReleased*  (node: UINode): (proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool {.gcsafe, raises: [].})              {.inline.} = node.mHandleReleased
func handleDrag*      (node: UINode): (proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2, delta: Vec2): bool {.gcsafe, raises: [].}) {.inline.} = node.mHandleDrag
func handleBeginHover*(node: UINode): (proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].})                                                             {.inline.} = node.mHandleBeginHover
func handleEndHover*  (node: UINode): (proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].})                                                             {.inline.} = node.mHandleEndHover
func handleHover*     (node: UINode): (proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].})                                                             {.inline.} = node.mHandleHover
func handleScroll*    (node: UINode): (proc(node: UINode, pos: Vec2, delta: Vec2, modifiers: set[Modifier]): bool {.gcsafe, raises: [].})                      {.inline.} = node.mHandleScroll

func `handlePressed=`*   (node: UINode, value: proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool {.gcsafe, raises: [].})              {.inline.} = node.mHandlePressed = value
func `handleReleased=`*  (node: UINode, value: proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool {.gcsafe, raises: [].})              {.inline.} = node.mHandleReleased = value
func `handleDrag=`*      (node: UINode, value: proc(node: UINode, button: MouseButton, modifiers: set[Modifier], pos: Vec2, delta: Vec2): bool {.gcsafe, raises: [].}) {.inline.} = node.mHandleDrag = value
func `handleBeginHover=`*(node: UINode, value: proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].})                                                             {.inline.} = node.mHandleBeginHover = value
func `handleEndHover=`*  (node: UINode, value: proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].})                                                             {.inline.} = node.mHandleEndHover = value
func `handleHover=`*     (node: UINode, value: proc(node: UINode, pos: Vec2): bool {.gcsafe, raises: [].})                                                             {.inline.} = node.mHandleHover = value
func `handleScroll=`*    (node: UINode, value: proc(node: UINode, pos: Vec2, delta: Vec2, modifiers: set[Modifier]): bool {.gcsafe, raises: [].})                      {.inline.} = node.mHandleScroll = value

func xy*(node: UINode): Vec2 {.inline.} = vec2(mix(node.boundsRaw.x, node.boundsRaw.x - node.boundsRaw.w, node.pivot.x), mix(node.boundsRaw.y, node.boundsRaw.y - node.boundsRaw.h, node.pivot.y))

func x*(node: UINode): float32 {.inline.} = mix(node.boundsRaw.x, node.boundsRaw.x - node.boundsRaw.w, node.pivot.x)
func y*(node: UINode): float32 {.inline.} = mix(node.boundsRaw.y, node.boundsRaw.y - node.boundsRaw.h, node.pivot.y)
func w*(node: UINode): float32 {.inline.} = node.boundsRaw.w
func h*(node: UINode): float32 {.inline.} = node.boundsRaw.h
func xw*(node: UINode): float32 {.inline.} = node.x + node.boundsRaw.w
func yh*(node: UINode): float32 {.inline.} = node.y + node.boundsRaw.h
func wh*(node: UINode): Rect {.inline.} = rect(0, 0, node.boundsRaw.w, node.boundsRaw.h)
func bounds*(node: UINode): Rect {.inline.} = rect(mix(node.boundsRaw.x, node.boundsRaw.x - node.boundsRaw.w, node.pivot.x), mix(node.boundsRaw.y, node.boundsRaw.y - node.boundsRaw.h, node.pivot.y), node.boundsRaw.w, node.boundsRaw.h)
func boundsRaw*(node: UINode): Rect {.inline.} = node.boundsRaw

func lx*(node: UINode): float32 {.inline.} = node.boundsAbsolute.x
func ly*(node: UINode): float32 {.inline.} = node.boundsAbsolute.y
func lw*(node: UINode): float32 {.inline.} = node.boundsAbsolute.w
func lh*(node: UINode): float32 {.inline.} = node.boundsAbsolute.h
func lxw*(node: UINode): float32 {.inline.} = node.boundsAbsolute.xw
func lyh*(node: UINode): float32 {.inline.} = node.boundsAbsolute.yh

func `rawX=`*(node: UINode, value: float32) {.inline.} = node.boundsRaw.x = value
func `rawY=`*(node: UINode, value: float32) {.inline.} = node.boundsRaw.y = value
proc `w=`*(node: UINode, value: float32) {.inline.} = node.boundsRaw.w = value
proc `h=`*(node: UINode, value: float32) {.inline.} = node.boundsRaw.h = value

func `lx=`*(node: UINode, value: float32) {.inline.} = node.boundsAbsolute.x = value
func `ly=`*(node: UINode, value: float32) {.inline.} = node.boundsAbsolute.y = value
func `lw=`*(node: UINode, value: float32) {.inline.} = node.boundsAbsolute.w = value
func `lh=`*(node: UINode, value: float32) {.inline.} = node.boundsAbsolute.h = value
func `pivot=`*(node: UINode, value: Vec2) {.inline.} = node.pivot = value

proc textWidth*(builder: UINodeBuilder, textLen: int): float32 {.inline.} = textLen.float32 * builder.charWidth

proc textWidth*(builder: UINodeBuilder, node: UINode): float32 {.inline.} =
  if builder.textWidthImpl.isNotNil and not node.mTextNarrow:
    builder.textWidthImpl(node)
  else:
    builder.textWidth(node.mTextRuneLen)

proc textWidth*(builder: UINodeBuilder, text: string): float32 {.inline.} =
  if builder.textWidthStringImpl.isNotNil and not text.isNarrow:
    builder.textWidthStringImpl(text)
  else:
    builder.textWidth(text.runeLen.int)

proc textHeight*(builder: UINodeBuilder): float32 {.inline.} = roundPositive(builder.lineHeight + builder.lineGap)

proc unpoolNode*(builder: UINodeBuilder, userId: var UIUserId): UINode
proc findNodeContaining*(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool {.gcsafe, raises: [].}): Option[UINode]
proc findNodesContaining*(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool {.gcsafe, raises: [].}): seq[UINode]

template logi(node: UINode, msg: varargs[string, `$`]) =
  when logInvalidationRects:
    var uiae = ""
    for c in msg:
      uiae.add $c
    echo "i: ", uiae, "    | ", node.dump, ""

template logp(node: UINode, msg: untyped) =
  when logPanel:
    echo "p: ", msg, "    | ", node.dump, ""

proc newNodeBuilder*(): UINodeBuilder =
  new result
  result.frameIndex = 0

  var id = UIUserId(kind: None)
  result.root = result.unpoolNode(userId = id)
  result.animatingNodes = @[]

proc currentParent*(builder: UINodeBuilder): UINode = builder.currentParent

proc hovered*(builder: UINodeBuilder, node: UINode): bool = node in builder.hoveredNodes

proc handleKeyPressed*(builder: UINodeBuilder, button: int64, modifiers: set[Modifier]): bool = false
proc handleKeyReleased*(builder: UINodeBuilder, button: int64, modifiers: set[Modifier]): bool = false

proc handleMouseScroll*(builder: UINodeBuilder, pos: Vec2, delta: Vec2, modifiers: set[Modifier]): bool =
  let targetNodes = builder.root.findNodesContaining(pos, (node) {.gcsafe, raises: [].} => node.handleScroll.isNotNil)
  for node in targetNodes:
    if node.handleScroll()(node, pos, delta, modifiers):
      return true
  return false

proc handleMousePressed*(builder: UINodeBuilder, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
  builder.mousePosClick[button] = pos

  let targetNodes = builder.root.findNodesContaining(pos, (node) {.gcsafe, raises: [].} => node.handlePressed.isNotNil)
  for node in targetNodes:
    if node.handlePressed()(node, button, modifiers, pos - node.boundsAbsolute.xy):
      return true

  return false

proc handleMouseReleased*(builder: UINodeBuilder, button: MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
  if builder.draggedNodes.len > 0:
    builder.draggedNodes.setLen 0
    result = true

  let targetNodes = builder.root.findNodesContaining(pos, (node) {.gcsafe, raises: [].} => node.handleReleased.isNotNil)
  for node in targetNodes:
    if node.handleReleased()(node, button, modifiers, pos - node.boundsAbsolute.xy):
      return true

proc handleMouseMoved*(builder: UINodeBuilder, pos: Vec2, buttons: set[MouseButton]): bool =
  builder.mouseDelta = pos - builder.mousePos
  builder.mousePos = pos

  var targetNode: seq[UINode] = builder.draggedNodes

  if buttons.len > 0:
    for node in builder.draggedNodes:
    # if builder.draggedNodes.getSome(node):
      for button in buttons:
        discard node.handleDrag()(node, button, {}, pos - node.boundsAbsolute.xy, builder.mouseDelta) # todo: modifiers
      result = true
    # else:
    if builder.draggedNodes.len == 0:
      let node = builder.root.findNodeContaining(pos, (node) {.gcsafe, raises: [].} => node.handleDrag.isNotNil)
      if node.getSome(node):
        for button in buttons:
          discard node.handleDrag()(node, button, {}, pos - node.boundsAbsolute.xy, builder.mouseDelta) # todo: modifiers
        result = true


  if targetNode.len == 0:
    targetNode = builder.root.findNodesContaining(pos, (node) {.gcsafe, raises: [].} => MouseHover in node.flags)

  for node in builder.hoveredNodes:
    if node in targetNode:
      if node.handleHover.isNotNil:
        result = node.handleHover()(node, pos - node.boundsAbsolute.xy) or result
    else:
      if node.handleEndHover.isNotNil:
        result = node.handleEndHover()(node, pos - node.boundsAbsolute.xy) or result

  for node in targetNode:
    if node notin builder.hoveredNodes:
      if node.handleBeginHover.isNotNil:
        result = node.handleBeginHover()(node, pos - node.boundsAbsolute.xy) or result


  # case (builder.hoveredNodes, targetNode)
  # of (Some(@a), Some(@b)):
  #   if a == b:
  #     if a.handleHover.isNotNil:
  #       result = a.handleHover()(a, pos - a.boundsAbsolute.xy) or result
  #   else:
  #     if a.handleEndHover.isNotNil:
  #       result = a.handleEndHover()(a, pos - a.boundsAbsolute.xy) or result
  #     if b.handleBeginHover.isNotNil:
  #       result = b.handleBeginHover()(b, pos - b.boundsAbsolute.xy) or result
  #     result = true

  # of (None(), Some(@b)):
  #   if b.handleBeginHover.isNotNil:
  #     result = b.handleBeginHover()(b, pos - b.boundsAbsolute.xy) or result
  #   result = true
  # of (Some(@a), None()):
  #   if a.handleEndHover.isNotNil:
  #     result = a.handleEndHover()(a, pos - a.boundsAbsolute.xy) or result
  #   result = true
  # of (None(), None()):
  #   discard

  builder.hoveredNodes = targetNode

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

proc setUnderlineColor*(node: UINode, r, g, b: float32, a: float32 = 1) =
  if r != node.mUnderlineColor.r or g != node.mUnderlineColor.g or b != node.mUnderlineColor.b or node.mUnderlineColor.a != a:
    node.contentDirty = true
  node.mUnderlineColor.r = r
  node.mUnderlineColor.g = g
  node.mUnderlineColor.b = b
  node.mUnderlineColor.a = a

iterator nextSiblings*(node: UINode): (int, UINode) =
  var i = 0
  var current = node.next
  while current.isNotNil:
    defer: inc i
    let next = current.next
    yield (i, current)
    current = next

iterator children*(node: UINode): (int, UINode) =
  var i = 0
  var current = node.first
  while current.isNotNil:
    defer: inc i
    let next = current.next
    yield (i, current)
    current = next

proc `[]`*(node: UINode, index: int): UINode =
  result = node.first
  for i in 0..<index:
    if result.isNil:
      raise newException(IndexDefect, "Index " & $index & " out of node child range 0..<" & $i)
    result = result.next

proc len*(node: UINode): int =
  result = 0
  for _, _ in node.children:
    result.inc

iterator rchildren*(node: UINode): UINode =
  var current = node.last
  while current.isNotNil:
    let prev = current.prev
    yield current
    current = prev

proc isDescendant*(node: UINode, ancestor: UINode): bool =
  var curr = node
  while curr.isNotNil:
    if curr.parent == ancestor:
      return true
    curr = curr.parent
  return false

proc transformPos*(vec: Vec2, src: UINode, dst: UINode): Vec2 =
  result = vec
  var curr = src
  while curr != dst:
    result = result + curr.xy
    curr = curr.parent
    assert curr.isNotNil, "transformPos: dst is not a (in)direct parent of src"

proc transformRect*(rect: Rect, src: UINode, dst: UINode): Rect =
  result = rect
  var curr = src
  while curr != dst:
    result = result + curr.xy
    curr = curr.parent
    assert curr.isNotNil, "transformPos: dst is not a (in)direct parent of src"

proc transformBounds*(src: UINode, dst: UINode): Rect =
  result = src.bounds
  var curr = src.parent
  while curr != dst:
    result = result + curr.xy
    curr = curr.parent
    assert curr.isNotNil, "transformPos: dst is not a (in)direct parent of src"

proc returnNode*(builder: UINodeBuilder, node: UINode) =
  case node.userId.kind
  of None:
    builder.nodes.add node
  of Primary:
    discard
  of Secondary:
    builder.nodes.add node

  for _, c in node.children:
    builder.returnNode c

  builder.draggedNodes.excl node
  builder.hoveredNodes.excl node

  when defined(uiNodeDebugData):
    node.aDebugData.metaData = nil
    node.aDebugData.css.setLen 0

  node.parent = nil
  node.first = nil
  node.last = nil
  node.next = nil
  node.prev = nil
  node.flags = 0.UINodeFlags
  node.mFlagsOld = 0.UINodeFlags

  node.contentDirty = false
  node.mLastContentChange = 0
  node.mLastPositionChange = 0
  node.mLastSizeChange = 0
  node.mLastClearInvalidation = 0
  node.mLastDrawInvalidation = 0
  node.lastRenderTime = 0

  node.mText = ""
  node.mTextRuneLen = 0

  node.pivot.x = 0
  node.pivot.y = 0

  node.userData = nil

  node.boundsOld.x = 0
  node.boundsOld.y = 0
  node.boundsOld.w = 0
  node.boundsOld.h = 0

  node.boundsRaw.x = 0
  node.boundsRaw.y = 0
  node.boundsRaw.w = 0
  node.boundsRaw.h = 0

  node.boundsActual.x = 0
  node.boundsActual.y = 0
  node.boundsActual.w = 0
  node.boundsActual.h = 0

  node.boundsAbsolute.x = 0
  node.boundsAbsolute.y = 0
  node.boundsAbsolute.w = 0
  node.boundsAbsolute.h = 0

  node.mBackgroundColor.r = 0
  node.mBackgroundColor.g = 0
  node.mBackgroundColor.b = 0
  node.mBackgroundColor.a = 1

  node.mTextColor.r = 1
  node.mTextColor.g = 1
  node.mTextColor.b = 1
  node.mTextColor.a = 1

  node.mUnderlineColor.r = 1
  node.mUnderlineColor.g = 1
  node.mUnderlineColor.b = 1
  node.mUnderlineColor.a = 1

  node.mBorderColor.r = 0.5
  node.mBorderColor.g = 0.5
  node.mBorderColor.b = 0.5
  node.mBorderColor.a = 1

  node.mHandlePressed = nil
  node.mHandleReleased = nil
  node.mHandleDrag = nil
  node.mHandleBeginHover = nil
  node.mHandleEndHover = nil
  node.mHandleHover = nil
  node.mHandleScroll = nil

  node.clearRect = Rect.none

  if node.renderCommands.len > 50:
    node.renderCommands = @[]
  else:
    node.renderCommands.setLen(0)

proc clearUnusedChildren*(builder: UINodeBuilder, node: UINode, last: UINode) =
  if last.isNil:
    for _, child in node.children:
      builder.returnNode child
      node.contentDirty = true
    node.first = nil
    node.last = nil

  else:
    assert last.parent == node, &"parent: {last.parent.dump(true)}\n, last: {last.dump(true)}\n, node: {node.dump(true)}\n"

    var n = last.next
    while n.isNotNil:
      let next = n.next
      builder.returnNode n
      node.contentDirty = true
      n = next

    node.last = last
    last.next = nil

proc clearUnusedChildrenAndGetBounds*(builder: UINodeBuilder, node: UINode, last: UINode): Option[Rect] =
  if last.isNil:
    for _, child in node.children:
      result = result or child.boundsActual.some
      builder.returnNode child
      node.contentDirty = true
    node.first = nil
    node.last = nil

  else:
    assert last.parent == node

    var n = last.next
    while n.isNotNil:
      let next = n.next
      result = result or n.boundsActual.some
      builder.returnNode n
      node.contentDirty = true
      n = next

    node.last = last
    last.next = nil

proc postLayout*(builder: UINodeBuilder, node: UINode)
proc postLayoutChild*(builder: UINodeBuilder, node: UINode, child: UINode)
proc relayout*(builder: UINodeBuilder, node: UINode)
proc preLayout*(builder: UINodeBuilder, node: UINode)

proc preLayout*(builder: UINodeBuilder, node: UINode) =
  # node.logp "preLayout"
  let parent = node.parent

  if LayoutHorizontal in parent.flags:
    if node.prev.isNotNil:
      node.boundsRaw.x = node.prev.xw.roundPositive
    else:
      node.boundsRaw.x = 0
  elif LayoutHorizontalReverse in parent.flags:
    if node.prev.isNotNil:
      node.boundsRaw.x = node.prev.x.roundPositive
    else:
      node.boundsRaw.x = parent.w

  if LayoutVertical in parent.flags:
    if node.prev.isNotNil:
      node.boundsRaw.y = node.prev.yh.roundPositive
    else:
      node.boundsRaw.y = 0
  elif LayoutVerticalReverse in parent.flags:
    if node.prev.isNotNil:
      node.boundsRaw.y = node.prev.y.roundPositive
    else:
      node.boundsRaw.y = parent.h

  if node.flags.all &{SizeToContentX, FillX}:
    if DrawText in node.flags:
      node.boundsRaw.w = max(parent.w - node.x, builder.textWidth(node)).roundPositive
    else:
      node.boundsRaw.w = (parent.w - node.x).roundPositive
  elif SizeToContentX in node.flags:
    if DrawText in node.flags:
      node.boundsRaw.w = builder.textWidth(node).roundPositive
  elif FillX in node.flags:
    if LayoutHorizontalReverse in parent.flags:
      node.boundsRaw.w = node.boundsRaw.x.roundPositive
    else:
      node.boundsRaw.w = (parent.w - node.x).roundPositive

  if node.flags.all &{SizeToContentY, FillY}:
    if DrawText in node.flags:
      node.boundsRaw.h = max(parent.h - node.y, builder.textHeight).roundPositive
    else:
      node.boundsRaw.h = (parent.h - node.y).roundPositive
  elif SizeToContentY in node.flags:
    if DrawText in node.flags:
      node.boundsRaw.h = builder.textHeight.roundPositive
  elif FillY in node.flags:
    if LayoutVerticalReverse in parent.flags:
      node.boundsRaw.h = node.boundsRaw.y.roundPositive
    else:
      node.boundsRaw.h = (parent.h - node.y).roundPositive

  assert not node.boundsRaw.isNan, fmt"node {node.dump}: boundsRaw contains Nan"

proc relayout*(builder: UINodeBuilder, node: UINode) =
  builder.preLayout node
  builder.postLayout node

proc postLayoutChild*(builder: UINodeBuilder, node: UINode, child: UINode) =
  if IgnoreBoundsForSizeToContent in child.flags:
    return

  if SizeToContentX in node.flags and child.xw > node.w:
    node.boundsRaw.w = child.xw.roundPositive

  if SizeToContentY in node.flags and child.yh > node.h:
    node.boundsRaw.h = child.yh.roundPositive

  assert not node.boundsRaw.isNan, fmt"node {node.dump}: boundsRaw contains Nan"

proc updateSizeToContent*(builder: UINodeBuilder, node: UINode) =
  if SizeToContentX in node.flags:
    let childrenWidth = if node.first.isNotNil:
      if LayoutHorizontalReverse in node.flags:
        node.first.xw - node.last.x
      elif LayoutHorizontal in node.flags:
        node.last.xw - node.first.x
      else: # no horizontal layout, check all children
        var xMin = float.high
        var xMax = float.low

        for _, c in node.children:
          if IgnoreBoundsForSizeToContent in c.flags:
            continue
          xMin = min(xMin, c.x)
          xMax = max(xMax, c.xw)

        xMax - xMin

    else: 0

    let strWidth = if DrawText in node.flags:
      builder.textWidth(node)
    else: 0

    node.boundsRaw.w = max(node.w, max(childrenWidth, strWidth)).roundPositive

  if SizeToContentY in node.flags:
    let childrenHeight = if node.first.isNotNil:
      if LayoutVerticalReverse in node.flags:
        node.first.yh - node.last.y
      elif LayoutVertical in node.flags:
        node.last.yh - node.first.y
      else: # no vertical layout, check all children
        var yMin = float.high
        var yMax = float.low

        for _, c in node.children:
          if IgnoreBoundsForSizeToContent in c.flags:
            continue
          yMin = min(yMin, c.y)
          yMax = max(yMax, c.yh)

        yMax - yMin
    else: 0

    let strHeight = if DrawText in node.flags:
      builder.textHeight
    else: 0

    node.boundsRaw.h = max(node.h, max(childrenHeight, strHeight)).roundPositive

  assert not node.boundsRaw.isNan, fmt"node {node.dump}: boundsRaw contains Nan"

proc postLayout*(builder: UINodeBuilder, node: UINode) =
  # node.logp "postLayout"
  builder.updateSizeToContent node

  if FillX in node.flags:
    assert node.parent.isNotNil
    if LayoutHorizontalReverse in node.parent.flags:
      node.boundsRaw.w = node.boundsRaw.x.roundPositive
    else:
      node.boundsRaw.w = max(node.boundsRaw.w, (node.parent.w - node.x).roundPositive)

  if node.flags.any &{SizeToContentX, SizeToContentY}:
    for _, c in node.children:
      builder.relayout(c)

  if node.parent.isNotNil:
    builder.postLayoutChild(node.parent, node)

  builder.updateSizeToContent node

  if FillX in node.flags:
    assert node.parent.isNotNil
    if LayoutHorizontalReverse in node.parent.flags:
      node.boundsRaw.w = node.boundsRaw.x.roundPositive
    else:
      node.boundsRaw.w = max(node.boundsRaw.w, (node.parent.w - node.x).roundPositive)

  if FillY in node.flags:
    assert node.parent.isNotNil
    if LayoutVerticalReverse in node.parent.flags:
      node.boundsRaw.h = node.boundsRaw.y.roundPositive
    else:
      node.boundsRaw.h = (node.parent.h - node.y).roundPositive

  assert not node.boundsRaw.isNan, fmt"node {node.dump}: boundsRaw contains Nan"

  if node.parent.isNotNil:
    builder.postLayoutChild(node.parent, node)

# todo: use sink instead of var
proc unpoolNode*(builder: UINodeBuilder, userId: var UIUserId): UINode =
  if userId.kind == Primary and builder.namedNodes.contains(userId.id):
    result = builder.namedNodes[userId.id]
    # assert result.userId == userId
    return

  if builder.nodes.len > 0:
    result = builder.nodes.pop
    result.userId = userId
    if userId.kind == Primary:
      builder.namedNodes[userId.id] = result

    return

  totalNodes.inc

  result = UINode(mId: newId(), userId: userId)
  when defined(uiNodeDebugData):
    result.aDebugData.id = ($result.mId).cstring
  if userId.kind == Primary:
    builder.namedNodes[userId.id] = result

proc insert*(node: UINode, n: UINode, after: UINode = nil) =
  assert n.parent == nil

  if after.isNil:
    if node.first.isNil:
      node.first = n
      node.last = n
      n.parent = node
      n.prev = nil
      n.next = nil
    else:
      let oldFirst = node.first
      node.first = n
      n.parent = node
      n.next = oldFirst
      n.prev = nil
      oldFirst.prev = n
  else:
    assert after.parent == node
    assert node.first.isNotNil
    assert n != after

    n.parent = node
    n.prev = after
    n.next = after.next

    if after.next.isNotNil:
      assert after != node.last
      after.next.prev = n
    after.next = n

    if node.last == after:
      assert n.next.isNil
      node.last = n

proc replaceWith*(node: UINode, n: UINode) =
  n.parent = node.parent
  n.prev = node.prev
  n.next = node.next

  if node.prev.isNotNil:
    node.prev.next = n

  if node.next.isNotNil:
    node.next.prev = n

  if node.parent.first == node:
    node.parent.first = n

  if node.parent.last == node:
    node.parent.last = n

proc removeFromParent*(node: UINode) =
  if node.prev.isNotNil:
    node.prev.next = node.next
  else:
    assert node.parent.first == node
    node.parent.first = node.next

  if node.next.isNotNil:
    node.next.prev = node.prev
  else:
    assert node.parent.last == node
    node.parent.last = node.prev

  node.parent.contentDirty = true

  node.prev = nil
  node.next = nil
  node.parent = nil

# todo: use sink instead of var
proc getNextOrNewNode(builder: UINodeBuilder, node: UINode, last: UINode, userId: var UIUserId): UINode =
  let insert = true

  # # search ahead to see if we find a matching node
  # let firstOrLast = if last.isNotNil: last else: node.first
  # var matchingNode = UINode.none
  # if userId.kind != None and firstOrLast.isNotNil:
  #   for _, c in firstOrLast.nextSiblings:
  #     if c.userId == userId:
  #       matchingNode = c.some
  #       break

  # if matchingNode.isSome:
  #   if builder.useInvalidation:
  #     node.clearedChildrenBounds = node.clearedChildrenBounds or matchingNode.get.boundsActual.some
  #   matchingNode.get.removeFromParent()
  #   node.insert(matchingNode.get, firstOrLast)

  #   assert firstOrLast.next == matchingNode.get
  #   assert firstOrLast.next.userId == userId

  #   return firstOrLast.next

  if last.isNil: # Creating/Updating first child
    if node.first.isNotNil: # First child already exists
      if node.first.userId == userId: # User id matches, reuse existing
        return node.first

    let newNode = builder.unpoolNode(userId)

    if newNode.parent.isNotNil:
      # node is still in use somewhere else
      # echo "remove target node from parent because we insert it here: ", node.dump
      if builder.useInvalidation:
        newNode.parent.clearedChildrenBounds = newNode.parent.clearedChildrenBounds or newNode.boundsActual.some
      newNode.removeFromParent()

    node.insert(newNode)
    return newNode

  if last.next.isNotNil:
    assert last.next.parent == last.parent
    assert last.next.prev == last
    if last.next.userId == userId:
      return last.next
    elif userId.kind != None: # Has user id, doesn't match

      # search ahead to see if we find a matching node
      var matchingNode = UINode.none
      for _, c in last.nextSiblings:
        if c.userId == userId:
          matchingNode = c.some
          break

      if matchingNode.isSome:
        # echo "found matching node later, delete inbetween"
        # remove all nodes in between
        for _, c in last.nextSiblings:
          if c == matchingNode.get:
            break
          # echo "delete old node ", c.dump(), ", ", node.clearRect
          if builder.useInvalidation:
            node.clearedChildrenBounds = node.clearedChildrenBounds or c.boundsActual.some
          c.removeFromParent()
          builder.returnNode(c)
        assert last.next == matchingNode.get
        assert last.next.userId == userId

        return last.next

      let newNode = builder.unpoolNode(userId)

      if newNode.parent.isNotNil:
        # node is still in use somewhere else
        # echo "remove target node from parent because we insert it here: ", node.dump
        if builder.useInvalidation:
          newNode.parent.clearedChildrenBounds = newNode.parent.clearedChildrenBounds or newNode.boundsActual.some
        newNode.removeFromParent()

      node.insert(newNode, last)
      return newNode

    else: # User id doesn't match and user id is none
      assert userId.kind == None
      let newNode = builder.unpoolNode(userId)
      node.insert(newNode, last)
      return newNode

  # new node at end
  let newNode = builder.unpoolNode(userId)

  if newNode.parent.isNotNil:
    # node is still in use somewhere else
    # echo "remove target node from parent because we insert it here: ", node.dump
    if builder.useInvalidation:
      newNode.parent.clearedChildrenBounds = newNode.parent.clearedChildrenBounds or newNode.boundsActual.some
    newNode.removeFromParent()

  node.insert(newNode, last)
  return newNode

proc prepareNode*(builder: UINodeBuilder, inFlags: UINodeFlags, inText: Option[string], inX, inY, inW, inH: Option[float32], inPivot: Option[Vec2], userId: var UIUserId, inAdditionalFlags: Option[UINodeFlags]): UINode =
  assert builder.currentParent.isNotNil

  var node = builder.getNextOrNewNode(builder.currentParent, builder.currentChild, userId)

  node.flags = inFlags
  if inAdditionalFlags.isSome:
    node.flags = node.flags + inAdditionalFlags.get

  if inText.isSome: node.text = inText.get
  elif node.text.len != 0: node.text = ""

  when defined(uiNodeDebugData):
    node.aDebugData.metaData = newJObject()
    node.aDebugData.css.setLen 0

  node.mHandlePressed = nil
  node.mHandleReleased = nil
  node.mHandleDrag = nil
  node.mHandleBeginHover = nil
  node.mHandleEndHover = nil
  node.mHandleHover = nil
  node.mHandleScroll = nil

  node.userData = nil

  if builder.useInvalidation:
    node.clearRect = Rect.none
    node.clearedChildrenBounds = Rect.none

  node.boundsRaw.x = 0
  node.boundsRaw.y = 0
  node.boundsRaw.w = 0
  node.boundsRaw.h = 0

  if node.parent.isNotNil and AutoPivotChildren in node.parent.flags:
    if LayoutHorizontalReverse in node.parent.flags:
      node.pivot.x = 1
    elif LayoutHorizontal in node.parent.flags:
      node.pivot.x = 0
    if LayoutVerticalReverse in node.parent.flags:
      node.pivot.y = 1
    elif LayoutVertical in node.parent.flags:
      node.pivot.y = 0

  builder.preLayout(node)

  if inX.isSome: node.boundsRaw.x = inX.get.roundPositive
  if inY.isSome: node.boundsRaw.y = inY.get.roundPositive
  if inW.isSome: node.boundsRaw.w = inW.get.roundPositive
  if inH.isSome: node.boundsRaw.h = inH.get.roundPositive
  if inPivot.isSome: node.pivot = inPivot.get

  assert not node.boundsRaw.isNan, fmt"node {node.dump}: boundsRaw contains Nan"

  node.logp fmt"panel begin {builder.currentParent.id}, {builder.currentChild.?id} {node.id}"

  builder.currentParent = node
  builder.currentChild = nil

  return node

proc finishNode*(builder: UINodeBuilder, currentNode: UINode) =
  # remove current invalidation rect
  currentNode.logp fmt"panel end {builder.currentParent.id}, {builder.currentChild.?id}, {currentNode.parent.id}, {currentNode.id}"

  if builder.useInvalidation:
    currentNode.clearedChildrenBounds = currentNode.clearedChildrenBounds or builder.clearUnusedChildrenAndGetBounds(currentNode, builder.currentChild)
  else:
    builder.clearUnusedChildren(currentNode, builder.currentChild)

  builder.postLayout(currentNode)

  builder.currentParent = currentNode.parent
  builder.currentChild = currentNode

proc postProcessNodeBackwards(builder: UINodeBuilder, node: UINode, offsetX: float32 = 0, offsetY: float32 = 0, inClearRect = Rect.none) =
  if node.flags != node.mFlagsOld:
    node.contentDirty = true
    node.mLastContentChange = builder.frameIndex

  let wasAnimating = node.id in builder.animatingNodes

  let animationProgress = clamp(node.boundsLerpSpeed * builder.animationSpeedModifier * builder.frameTime, 0, 1)
  if node.lastRenderTime == 0 and SnapInitialBounds in node.flags:
    node.boundsActual.x = node.x
    node.boundsActual.y = node.y
    node.boundsActual.w = node.w
    node.boundsActual.h = node.h
    builder.animatingNodes.excl node.id

  elif AnimateBounds in node.flags or node.flags.all &{AnimatePosition, AnimateSize}:
    if node.boundsActual.x == node.x and
      node.boundsActual.y == node.y and
      node.boundsActual.w == node.w and
      node.boundsActual.h == node.h:
      builder.animatingNodes.excl node.id
    else:
      node.boundsActual.x = node.boundsActual.x.mix(node.x, animationProgress)
      node.boundsActual.y = node.boundsActual.y.mix(node.y, animationProgress)
      node.boundsActual.w = node.boundsActual.w.mix(node.w, animationProgress)
      node.boundsActual.h = node.boundsActual.h.mix(node.h, animationProgress)

      if node.boundsActual.x.almostEqual(node.x, 1) and
        node.boundsActual.y.almostEqual(node.y, 1) and
        node.boundsActual.w.almostEqual(node.w, 1) and
        node.boundsActual.h.almostEqual(node.h, 1):

        node.boundsActual.x = node.x
        node.boundsActual.y = node.y
        node.boundsActual.w = node.w
        node.boundsActual.h = node.h

      builder.animatingNodes.incl node.id

  elif AnimatePosition in node.flags:
    if node.boundsActual.xy == node.xy:
      builder.animatingNodes.excl node.id
    else:
      node.boundsActual.x = node.boundsActual.x.mix(node.x, animationProgress)
      node.boundsActual.y = node.boundsActual.y.mix(node.y, animationProgress)
      if node.boundsActual.xy.almostEqual(node.xy, 1):
        node.boundsActual.x = node.x
        node.boundsActual.y = node.y
      builder.animatingNodes.incl node.id

    node.boundsActual.w = node.w
    node.boundsActual.h = node.h

  elif AnimateSize in node.flags:
    if node.boundsActual.wh == node.wh.wh:
      builder.animatingNodes.excl node.id
    else:
      node.boundsActual.w = node.boundsActual.w.mix(node.w, animationProgress)
      node.boundsActual.h = node.boundsActual.h.mix(node.h, animationProgress)
      if node.boundsActual.wh.almostEqual(node.wh.wh, 1):
        node.boundsActual.w = node.w
        node.boundsActual.h = node.h
      builder.animatingNodes.incl node.id

    node.boundsActual.x = node.x
    node.boundsActual.y = node.y

  else:
    node.boundsActual.x = node.x
    node.boundsActual.y = node.y
    node.boundsActual.w = node.w
    node.boundsActual.h = node.h
    builder.animatingNodes.excl node.id

  assert not node.boundsActual.isNan, fmt"node {node.dump}: boundsActual contains Nan"

  let newPosAbsoluteX = node.boundsActual.x + offsetX
  let newPosAbsoluteY = node.boundsActual.y + offsetY

  let positionDirty = node.lx != newPosAbsoluteX or node.ly != newPosAbsoluteY or (node.parent.isNotNil and node.parent.mLastPositionChange == builder.frameIndex)
  let sizeDirty = node.lw != node.boundsActual.w or node.lh != node.boundsActual.h or (node.parent.isNotNil and node.parent.mLastSizeChange == builder.frameIndex)

  let animatingDirty = wasAnimating != (node.id in builder.animatingNodes)
  if animatingDirty:
    node.mLastPositionChange = builder.frameIndex
    node.mLastSizeChange = builder.frameIndex

  if positionDirty:
    node.mLastPositionChange = builder.frameIndex

  if sizeDirty:
    node.mLastSizeChange = builder.frameIndex

  if builder.useInvalidation and (positionDirty or sizeDirty):
    node.clearRect = Rect.none
    if node.flags.all(&{FillBackground}):
      if not node.boundsActual.contains(node.boundsOld):
        node.clearRect = node.clearRect or some node.boundsOld.invalidationRect(node.boundsActual)
        # if node.clearRect.isSome:
        #   node.logi "1 node clear rect ", node.clearRect.get
    else:
      if not node.boundsActual.contains(node.boundsOld):
        node.clearRect = node.clearRect or some node.boundsOld.invalidationRect(node.boundsActual)
        # if node.clearRect.isSome:
        #   node.logi "2 node clear rect ", node.clearRect.get

  node.lx = newPosAbsoluteX
  node.ly = newPosAbsoluteY
  node.lw = node.boundsActual.w
  node.lh = node.boundsActual.h

  assert not node.boundsAbsolute.isNan, fmt"node {node.dump}: boundsAbsolute contains Nan"

  node.boundsOld.x = node.boundsActual.x
  node.boundsOld.y = node.boundsActual.y
  node.boundsOld.w = node.boundsActual.w
  node.boundsOld.h = node.boundsActual.h

  assert not node.boundsOld.isNan, fmt"node {node.dump}: boundsOld contains Nan"

  node.mFlagsOld = node.flags

  if builder.useInvalidation and inClearRect.isSome and inClearRect.get.intersects(node.boundsActual):
    node.mLastClearInvalidation = builder.frameIndex
    node.logi "invalidate clear"

  if builder.useInvalidation:
    var childClearRect = (inClearRect or node.clearedChildrenBounds) - node.xy.some

    for c in node.rchildren:
      builder.postProcessNodeBackwards(c, node.lx, node.ly, childClearRect)

      if builder.useInvalidation and (OverlappingChildren in node.flags or true): # todo: only when ovelapping or child is animating
        childClearRect = childClearRect or c.clearRect

      if c.lastChange == builder.frameIndex:
        node.contentDirty = true

  else:
    for c in node.rchildren:
      builder.postProcessNodeBackwards(c, node.lx, node.ly, Rect.none)

      if c.lastChange == builder.frameIndex:
        node.contentDirty = true

  if node.contentDirty:
    node.mLastContentChange = builder.frameIndex
    node.contentDirty = false

proc postProcessNodeForwards(builder: UINodeBuilder, node: UINode, inDrawRect = Rect.none) =
  if inDrawRect.isSome and inDrawRect.get.intersects(node.boundsActual):
    node.mLastDrawInvalidation = builder.frameIndex
    node.logi "invalidate draw"

  node.drawRect = Rect.none
  if node.lastChange == builder.frameIndex:
    if node.flags.any(&{DrawText, FillBackground}):
      node.drawRect = node.boundsActual.some

  var childDrawRect = (inDrawRect or node.drawRect) - node.xy.some

  for _, c in node.children:
    builder.postProcessNodeForwards(c, childDrawRect)

    if OverlappingChildren in node.flags:
      childDrawRect = childDrawRect or c.drawRect

    node.drawRect = node.drawRect or (c.drawRect + node.xy.some)

    if c.lastChange == builder.frameIndex:
      node.mLastContentChange = builder.frameIndex

  if node.lastChange == builder.frameIndex:
    if node.flags.any(&{DrawBorder}):
      node.drawRect = node.boundsActual.some

proc postProcessNodes*(builder: UINodeBuilder) =
  builder.postProcessNodeBackwards(builder.root)

  if builder.useInvalidation:
    builder.postProcessNodeForwards(builder.root)

macro panel*(builder: UINodeBuilder, inFlags: UINodeFlags, args: varargs[untyped]): untyped =
  var body = genAst(): discard

  var inUserId = genAst(): UIUserId(kind: None)
  var inText = genAst(): string.none
  var inX = genAst(): float32.none
  var inY = genAst(): float32.none
  var inW = genAst(): float32.none
  var inH = genAst(): float32.none
  var inPivot = genAst(): Vec2.none
  var inBackgroundColor = genAst(): Color.none
  var inBorderColor = genAst(): Color.none
  var inTextColor = genAst(): Color.none
  var inUnderlineColor = genAst(): Color.none
  var inAdditionalFlags = genAst(): UINodeFlags.none

  for i, arg in args:
    case arg
    of ExprEqExpr[(kind: _ in {nnkSym, nnkIdent}), @value]:
      let name = arg[0].repr
      case name
      of "userId":
        inUserId = genAst(value): value
      of "text":
        inText = genAst(value): some(value)
      of "backgroundColor":
        inBackgroundColor = genAst(value): some(value)
      of "borderColor":
        inBorderColor = genAst(value): some(value)
      of "textColor":
        inTextColor = genAst(value): some(value)
      of "underlineColor":
        inUnderlineColor = genAst(value): some(value)
      of "x":
        inX = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "y":
        inY = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "w":
        inW = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "h":
        inH = genAst(value): some(value).maybeFlatten.mapIt(it.float32)
      of "pivot":
        inPivot = genAst(value): some(value).maybeFlatten
      else:
        error("Unknown ui node property '" & name & "'", arg[0])

    of Infix[Ident(strVal: "+="), Ident(strVal: "flags"), @value]:
      inAdditionalFlags = genAst(value): some(value).maybeFlatten

    elif i == args.len - 1:
      body = arg

    else:
      # echo arg.treeRepr
      error("Only <name> = <value> is allowed here.", arg)

  return genAst(builder, inFlags, inText, inX, inY, inW, inH, inPivot, body, inBackgroundColor, inBorderColor, inTextColor, inUnderlineColor, inUserId, inAdditionalFlags):
    var userId = inUserId
    var node = builder.prepareNode(inFlags, inText, inX, inY, inW, inH, inPivot, userId, inAdditionalFlags)

    if inBackgroundColor.isSome: node.backgroundColor = inBackgroundColor.get
    if inBorderColor.isSome:     node.borderColor     = inBorderColor.get
    if inTextColor.isSome:       node.textColor       = inTextColor.get
    if inUnderlineColor.isSome:  node.underlineColor  = inUnderlineColor.get

    block:
      let currentNode {.used, inject.} = node

      template onClick(button: MouseButton, onClickBody: untyped) {.used.} =
        currentNode.handlePressed = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton, modifiers {.inject.}: set[Modifier], pos {.inject.}: Vec2): bool {.gcsafe, raises: [].} =
          if btn == button:
            onClickBody
          return true

      template onClickAny(btn: untyped, onClickBody: untyped) {.used.} =
        currentNode.handlePressed = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton, modifiers {.inject.}: set[Modifier], pos {.inject.}: Vec2): bool {.gcsafe, raises: [].} =
          onClickBody
          return true

      template onReleased(onBody: untyped) {.used.} =
        currentNode.handleReleased = proc(node {.inject.}: UINode, btn {.inject.}: MouseButton, modifiers {.inject.}: set[Modifier], pos {.inject.}: Vec2): bool {.gcsafe, raises: [].} =
          onBody
          return true

      template onDrag(button: MouseButton, onDragBody: untyped) {.used.} =
        currentNode.handleDrag = proc(node: UINode, btn {.inject.}: MouseButton, modifiers {.inject.}: set[Modifier], pos {.inject.}: Vec2, d: Vec2): bool {.gcsafe, raises: [].} =
          if btn == button:
            onDragBody
          return true

      template onBeginHover(onBody: untyped) {.used.} =
        currentNode.handleBeginHover = proc(node: UINode, pos {.inject.}: Vec2): bool {.gcsafe, raises: [].} =
          onBody
          return true

      template onEndHover(onBody: untyped) {.used.} =
        currentNode.handleEndHover = proc(node: UINode, pos {.inject.}: Vec2): bool {.gcsafe, raises: [].} =
          onBody
          return true

      template onHover(onBody: untyped) {.used.} =
        currentNode.handleHover = proc(node: UINode, pos {.inject.}: Vec2): bool {.gcsafe, raises: [].} =
          onBody
          return true

      template onScroll(onBody: untyped) {.used.} =
        currentNode.handleScroll = proc(node: UINode, pos {.inject.}: Vec2, delta {.inject.}: Vec2, modifiers {.inject.}: set[Modifier]): bool {.gcsafe, raises: [].} =
          onBody
          return true

      defer:
        builder.finishNode(currentNode)

      body

proc findNodesContaining*(res: var seq[UINode], node: UINode, pos: Vec2, predicate: proc(node: UINode): bool {.gcsafe, raises: [].}) =
  if pos.x < node.lx or pos.x >= node.lx + node.lw or pos.y < node.ly or pos.y >= node.ly + node.lh:
    return

  # debugf"findNodeContaining at {pos} with {(node.lx, node.ly, node.lw, node.lh)}: {node.dump}"

  if node.first.isNil: # has no children
    if predicate.isNotNil and not predicate(node):
      return

    res.add node

  else: # has children
    for c in node.rchildren:
      findNodesContaining(res, c, pos, predicate)

    if predicate.isNotNil and predicate(node):
      res.add node

proc findNodesContaining*(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool {.gcsafe, raises: [].}): seq[UINode] =
  findNodesContaining(result, node, pos, predicate)

proc findNodeContaining*(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool {.gcsafe, raises: [].}): Option[UINode] =
  result = UINode.none
  if pos.x < node.lx or pos.x >= node.lx + node.lw or pos.y < node.ly or pos.y >= node.ly + node.lh:
    return

  # debugf"findNodeContaining at {pos} with {(node.lx, node.ly, node.lw, node.lh)}: {node.dump}"

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

proc forEachOverlappingLeafNode*(node: UINode, rect: Rect, f: proc(node: UINode) {.gcsafe, raises: [].}) =
  if not node.boundsAbsolute.intersects(rect):
    return

  f(node)

  if node.first.isNotNil:
    for _, c in node.children:
      c.forEachOverlappingLeafNode(rect, f)

proc beginFrame*(builder: UINodeBuilder, size: Vec2) =
  builder.frameIndex.inc

  builder.currentParent = builder.root
  builder.currentChild = nil

  builder.root.boundsRaw.x = 0
  builder.root.boundsRaw.y = 0
  builder.root.boundsRaw.w = size.x
  builder.root.boundsRaw.h = size.y
  builder.root.flags = &{LayoutVertical}

proc endFrame*(builder: UINodeBuilder) =
  builder.clearUnusedChildren(builder.root, builder.currentChild)
  builder.postLayout(builder.root)
  builder.postProcessNodes()

proc continueFrom*(builder: UINodeBuilder, node: UINode, last: UINode = nil) =
  # let lastDump = if last.isNotNil: last.dump else: ""
  # debugf"continueFrom {node.dump} -> {lastDump}"
  assert last.isNil or last.parent == node
  builder.currentParent = node
  builder.currentChild = last

proc retain*(builder: UINodeBuilder): bool =
  let node = builder.currentParent

  if node.lastChange == 0:
    # first time the node was created, can't retain because content wasn't created yet
    # echo "first time for ", node.dump
    return false

  let w = if SizeToContentX in node.flags: max(node.w, node.boundsOld.w) else: node.w
  let h = if SizeToContentY in node.flags: max(node.h, node.boundsOld.h) else: node.h

  if w != node.boundsOld.w or h != node.boundsOld.h:
    # echo "size dirty ", node.boundsRaw.wh, ", ", node.boundsOld.wh, ", (", w, ", ", h, ")"
    return false

  node.boundsRaw.w = w
  node.boundsRaw.h = h
  assert not node.boundsRaw.isNan, fmt"node {node.dump}: boundsRaw contains Nan"

  builder.currentChild = builder.currentParent.last

  return true

proc dump*(node: UINode, recurse = false): string =
  if node.isNil:
    return "nil"
  # result.add fmt"Node({node.userId}, {node.mLastContentChange}, {node.mLastPositionChange}, {node.mLastSizeChange}, {node.mLastClearInvalidation}, {node.mLastDrawInvalidation}, {node.id} '{node.text}', {node.flags}, ({node.bounds}), {node.boundsActual}, {node.boundsOld})"
  result.add fmt"Node({node.id} '{node.text}', ({node.mLastContentChange}, {node.mLastPositionChange}, {node.mLastSizeChange}), {node.flags}, {node.boundsAbsolute}, bounds: {node.bounds}, raw: {node.boundsRaw}, actual: {node.boundsActual}), pivot: {node.pivot}"
  if recurse and node.first.isNotNil:
    result.add ":"
    for _, c in node.children:
      result.add "\n"
      for c in c.dump(recurse=recurse).indent(1, "  "):
        result.add c

proc nodeSizeBytes*(self: UINode): int =
  result += sizeof(UINodeObject)
  result += self.mText.len
  for _, c in self.children:
    result += c.nodeSizeBytes

proc getStatisticsString*(self: UINodeBuilder): string =
  var allNodeSize = 0
  for n in self.nodes:
    allNodeSize += n.nodeSizeBytes()

  var namedNodeSize = 0
  for n in self.namedNodes.values:
    namedNodeSize += n.nodeSizeBytes()

  result.add &"Nodes: {self.nodes.len}/{totalNodes}, {allNodeSize} bytes\n"
  result.add &"Named Nodes: {self.namedNodes.len}, {namedNodeSize} bytes\n"
  result.add &"Root size: {self.root.nodeSizeBytes} bytes\n"