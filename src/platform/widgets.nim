import std/options
import vmath, bumpy, chroma
import theme, rect_utils, custom_logger, util

export rect_utils, vmath, bumpy

type
  WWidget* = ref object of RootObj
    parent*: WWidget
    anchor*: tuple[min: Vec2, max: Vec2]
    pivot*: Vec2
    left*, right*, top*, bottom*: float
    backgroundColor*: Color
    foregroundColor*: Color
    lastBounds*: Rect
    lastBoundsChange*: int
    lastHierarchyChange*: int
    lastInvalidationRect*: Rect
    lastInvalidation*: int
    sizeToContent*: bool
    drawBorder*: bool
    fillBackground*: bool
    logLayout*: bool
    allowAlpha*: bool

  WPanelLayoutKind* = enum
    Absolute, Horizontal, Vertical

  WPanelLayout* = object
    case kind*: WPanelLayoutKind
    else: discard

  WPanel* = ref object of WWidget
    maskContent*: bool
    layout*: WPanelLayout
    children*: seq[WWidget]

  WStack* = ref object of WWidget
    children*: seq[WWidget]

  WVerticalList* = ref object of WWidget
    children*: seq[WWidget]

  WHorizontalList* = ref object of WWidget
    children*: seq[WWidget]

  WText* = ref object of WWidget
    text*: string
    lastRenderedText*: string
    style*: Style

  WLayoutOptions* = object
    getTextBounds*: proc(text: string): Vec2

proc width*(self: WWidget): float = self.right - self.left
proc height*(self: WWidget): float = self.bottom - self.top

proc `[]=`*(self: WPanel, index: int, child: WWidget) =
  if index >= self.children.len:
    self.children.setLen(index + 1)
  if self.children[index].isNotNil:
    self.children[index].parent = nil
  if child.isNotNil:
    child.parent = self
  self.children[index] = child

proc insert*(self: WPanel, index: int, child: WWidget) =
  child.parent = self
  self.children.insert(child, index)

proc del*(self: WPanel, index: int) =
  self.children[index].parent = nil
  self.children.del index

proc pop*(self: WPanel): WWidget = self.children.pop()

proc `[]`*(self: WPanel, index: int): WWidget = self.children[index]

proc len*(self: WPanel): int = self.children.len
proc high*(self: WPanel): int = self.children.high
proc low*(self: WPanel): int = self.children.low

proc setLen*(self: WPanel, len: int) = self.children.setLen len

proc add*(self: WPanel, child: WWidget) =
  child.parent = self
  self.children.add child

proc getOrCreate*(self: WPanel, index: int, T: typedesc): T =
  defer:
    if result.isNotNil:
      result.parent = self

  if index >= self.children.len:
    self.children.setLen(index + 1)
    self.children[index] = T()
  elif self.children[index].isNotNil and self.children[index] of T:
    return self.children[index].T

  self.children[index] = T()
  return self.children[index].T

proc getOrCreate*(self: WWidget, T: typedesc): T =
  defer:
    if result.isNotNil:
      result.parent = self

  return if self.isNotNil and self of T: self.T else: T()

proc truncate*(self: WPanel, len: int) =
  self.children.setLen min(self.children.len, len)

proc toString*(self: WWidget, indent: string): string =
  var name = ""
  var rest = ""
  if self of WPanel:
    name = "WPanel"
    rest = ":\n"
    for c in self.WPanel.children:
      rest.add c.toString(indent & "  ")
      rest.add "\n"
  if self of WStack:
    name = "WStack"
    rest = ":\n"
    for c in self.WStack.children:
      rest.add c.toString(indent & "  ")
      rest.add "\n"
  if self of WText:
    name = "WText"
    rest = ": "
    rest.add self.WText.text

  result = indent
  result.add name
  result.add fmt"(ltwh: ({self.left}, {self.top}, {self.width}, {self.height}), anchor: {self.anchor}, bounds: {self.lastBounds}, {self.sizeToContent})"
  result.add rest

proc `$`*(self: WWidget): string = self.toString("")

proc getForegroundColor*(self: WWidget): Color =
  result = self.foregroundColor
  if not self.allowAlpha:
    result.a = 1

proc getBackgroundColor*(self: WWidget): Color =
  result = self.backgroundColor
  if not self.allowAlpha:
    result.a = 1

proc updateForegroundColor*(self: WWidget, color: Color, frameIndex: int) =
  if self.foregroundColor != color: self.lastHierarchyChange = max(self.lastHierarchyChange, frameIndex)
  self.foregroundColor = color

proc updateBackgroundColor*(self: WWidget, color: Color, frameIndex: int) =
  if self.backgroundColor != color: self.lastHierarchyChange = max(self.lastHierarchyChange, frameIndex)
  self.backgroundColor = color

proc updateLastHierarchyChangeFromChildren*(self: WWidget, currentIndex = -1) =
  if self of WPanel:
    for c in self.WPanel.children:
      c.updateLastHierarchyChangeFromChildren currentIndex
      self.lastHierarchyChange = max(max(self.lastHierarchyChange, c.lastHierarchyChange), c.lastBoundsChange)
  elif self of WStack:
    for c in self.WStack.children:
      c.updateLastHierarchyChangeFromChildren currentIndex
      self.lastHierarchyChange = max(max(self.lastHierarchyChange, c.lastHierarchyChange), c.lastBoundsChange)
  elif self of WVerticalList:
    for c in self.WVerticalList.children:
      c.updateLastHierarchyChangeFromChildren currentIndex
      self.lastHierarchyChange = max(max(self.lastHierarchyChange, c.lastHierarchyChange), c.lastBoundsChange)
  elif self of WHorizontalList:
    for c in self.WHorizontalList.children:
      c.updateLastHierarchyChangeFromChildren currentIndex
      self.lastHierarchyChange = max(max(self.lastHierarchyChange, c.lastHierarchyChange), c.lastBoundsChange)
  elif self of WText:
    if self.WText.text != self.WText.lastRenderedText:
      self.lastHierarchyChange = max(self.lastHierarchyChange, currentIndex)

proc invalidate*(self: WWidget, currentIndex: int, rect: Rect) =
  if not self.lastBounds.intersects(rect) or (self.lastInvalidation >= currentIndex and self.lastInvalidationRect.contains(rect)):
    return

  # debugf"Invalidate({currentIndex}, {rect}) {self.lastBounds}"

  self.lastInvalidationRect = rect and self.lastBounds
  self.lastInvalidation = currentIndex

  if self of WPanel:
    for c in self.WPanel.children:
      c.invalidate(currentIndex, self.lastInvalidationRect)
  elif self of WStack:
    for c in self.WStack.children:
      c.invalidate(currentIndex, self.lastInvalidationRect)
  elif self of WVerticalList:
    for c in self.WVerticalList.children:
      c.invalidate(currentIndex, self.lastInvalidationRect)
  elif self of WHorizontalList:
    for c in self.WHorizontalList.children:
      c.invalidate(currentIndex, self.lastInvalidationRect)

proc updateInvalidationFromChildren*(self: WWidget, currentIndex: int, recurse: bool) =
  if self of WPanel:
    for c in self.WPanel.children:
      if recurse:
        c.updateInvalidationFromChildren(currentIndex, recurse)
      self.lastInvalidation = max(max(self.lastInvalidation, c.lastInvalidation), currentIndex)
  elif self of WStack:
    for c in self.WStack.children:
      if recurse:
        c.updateInvalidationFromChildren(currentIndex, recurse)
      self.lastInvalidation = max(max(self.lastInvalidation, c.lastInvalidation), currentIndex)
  elif self of WVerticalList:
    for c in self.WVerticalList.children:
      if recurse:
        c.updateInvalidationFromChildren(currentIndex, recurse)
      self.lastInvalidation = max(max(self.lastInvalidation, c.lastInvalidation), currentIndex)
  elif self of WHorizontalList:
    for c in self.WHorizontalList.children:
      if recurse:
        c.updateInvalidationFromChildren(currentIndex, recurse)
      self.lastInvalidation = max(max(self.lastInvalidation, c.lastInvalidation), currentIndex)

method layoutWidget*(self: WWidget, bounds: Rect, frameIndex: int, options: WLayoutOptions) {.base.} = discard

proc changed*(self: WWidget, frameIndex: int): bool =
  result = self.lastBoundsChange >= frameIndex or self.lastHierarchyChange >= frameIndex or self.lastInvalidation >= frameIndex

proc calculateBounds(self: WWidget, container: Rect): Rect =
  when not defined(js):
    let topLeft = container.xy + self.anchor.min * container.wh + vec2(self.left, self.top)
    let bottomRight = container.xy + self.anchor.max * container.wh + vec2(self.right, self.bottom)
    let pivotOffset = self.pivot * (bottomRight - topLeft)
    result = rect(topLeft - pivotOffset, bottomRight - topLeft)

  else:
    # Optimized version for javascript, prevents a ton of copies
    let left = container.x + self.anchor.min.x * container.w + self.left
    let top = container.y + self.anchor.min.y * container.h + self.top
    let right = container.x + self.anchor.max.x * container.w + self.right
    let bottom = container.y + self.anchor.max.y * container.h + self.bottom

    let px = self.pivot.x * (right - left)
    let py = self.pivot.y * (bottom - top)

    result.x = left - px
    result.y = top - py
    result.w = right - left
    result.h = bottom - top

method layoutWidget*(self: WPanel, container: Rect, frameIndex: int, options: WLayoutOptions) =
  var newBounds = self.calculateBounds(container)

  if self.logLayout:
    debugf"layoutPanel({container}, {frameIndex}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"
    if newBounds != self.lastBounds:
      debugf"bounds changed {self.lastBounds} -> {newBounds}"

  if self.sizeToContent:
    newBounds.wh = vec2()

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if (self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex) and self.children.len > 0:
    var last = vec2(self.children[0].left, self.children[0].top)
    for i, c in self.children:
      case self.layout.kind
      of Absolute: discard
      of Horizontal:
        let width = c.width
        c.left = last.x
        c.right = last.x + width

      of Vertical:
        let height = c.height
        c.top = last.y
        c.bottom = last.y + height

      c.layoutWidget(newBounds, frameIndex, options)

      if self.sizeToContent:
        newBounds = newBounds or c.lastBounds

      last.x = c.lastBounds.xw - newBounds.x
      last.y = c.lastBounds.yh - newBounds.y

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

method layoutWidget*(self: WStack, container: Rect, frameIndex: int, options: WLayoutOptions) =
  let newBounds = self.calculateBounds(container)

  if self.logLayout:
    debugf"layoutStack({container}, {frameIndex}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"
    if newBounds != self.lastBounds:
      debugf"bounds changed {self.lastBounds} -> {newBounds}"

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    for i, c in self.children:
      let oldBounds = c.lastBounds
      c.layoutWidget(newBounds, frameIndex, options)
      let newBounds = c.lastBounds
      if oldBounds != newBounds and not newBounds.contains(oldBounds):
        # Bounds shrinked
        let invalidationRect = oldBounds
        for k in countdown(i - 1, 0):
          self.children[k].invalidate(frameIndex, invalidationRect)
          # If the k-child bounds fully contains the invalidion rect, then we don't need to invalidate any more children before k
          if self.children[k].lastBounds.contains(invalidationRect):
            break

    var invalidationRect: Option[Rect] = Rect.none
    for i, c in self.children:
      if invalidationRect.isSome:
        c.invalidate(frameIndex, invalidationRect.get)

      invalidationRect = if invalidationRect.isSome:
        (invalidationRect.get or c.lastBounds).some
      else:
        c.lastBounds.some


method layoutWidget*(self: WVerticalList, container: Rect, frameIndex: int, options: WLayoutOptions) =
  let newBounds = self.calculateBounds(container)

  if self.logLayout:
    debugf"layoutVerticalList({container}, {frameIndex}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"
    if newBounds != self.lastBounds:
      debugf"bounds changed {self.lastBounds} -> {newBounds}"

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    var lastY = 0.0
    for c in self.children:
      let height = c.height
      c.top = lastY
      c.bottom = lastY + height
      c.layoutWidget(newBounds, frameIndex, options)
      lastY = c.lastBounds.yh - newBounds.y

method layoutWidget*(self: WHorizontalList, container: Rect, frameIndex: int, options: WLayoutOptions) =
  let newBounds = self.calculateBounds(container)

  if self.logLayout:
    debugf"layoutHorizontalList({container}, {frameIndex}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"
    if newBounds != self.lastBounds:
      debugf"bounds changed {self.lastBounds} -> {newBounds}"

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    var lastX = 0.0
    for c in self.children:
      let width = c.width
      c.left = lastX
      c.right = lastX + width
      c.layoutWidget(newBounds, frameIndex, options)
      lastX = c.lastBounds.xw - newBounds.x

method layoutWidget*(self: WText, container: Rect, frameIndex: int, options: WLayoutOptions) =
  var newBounds = self.calculateBounds(container)

  if self.sizeToContent:
    let size = options.getTextBounds self.text
    let incX = max(size.x - newBounds.w, 0)
    let incY = max(size.y - newBounds.h, 0)

    newBounds.w = size.x
    newBounds.h = size.y
    newBounds.x -= incX * self.pivot.x
    newBounds.y -= incY * self.pivot.y

    # self.bottom = self.top + size.y

  if self.logLayout:
    debugf"layoutText('{self.text}', {container}, {frameIndex}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"
    if newBounds != self.lastBounds:
      debugf"bounds changed {self.lastBounds} -> {newBounds}"

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

# @todo: use a macro so we don't forget adding properties to copy here
proc copyTo(self: WWidget, to: var WWidget) =
  to.anchor = self.anchor
  to.pivot = self.pivot
  to.left = self.left
  to.top = self.top
  to.right = self.right
  to.bottom = self.bottom
  to.backgroundColor = self.backgroundColor
  to.foregroundColor = self.foregroundColor
  to.lastBounds = self.lastBounds
  to.lastBoundsChange = self.lastBoundsChange
  to.lastHierarchyChange = self.lastHierarchyChange
  to.lastInvalidationRect = self.lastInvalidationRect
  to.lastInvalidation = self.lastInvalidation
  to.sizeToContent = self.sizeToContent
  to.drawBorder = self.drawBorder
  to.fillBackground = self.fillBackground
  to.logLayout = self.logLayout
  to.allowAlpha = self.allowAlpha

method clone*(self: WWidget): WWidget {.base.} = discard

method clone*(self: WPanel): WWidget =
  result = WPanel(children: @[], maskContent: self.maskContent)
  self.copyTo(result)
  let r = result.WPanel
  for c in self.children:
    r.children.add c.clone()

method clone*(self: WHorizontalList): WWidget =
  result = WHorizontalList(children: @[])
  self.copyTo(result)
  let r = result.WHorizontalList
  for c in self.children:
    r.children.add c.clone()

method clone*(self: WVerticalList): WWidget =
  result = WVerticalList(children: @[])
  self.copyTo(result)
  let r = result.WVerticalList
  for c in self.children:
    r.children.add c.clone()

method clone*(self: WStack): WWidget =
  result = WStack(children: @[])
  self.copyTo(result)
  let r = result.WStack
  for c in self.children:
    r.children.add c.clone()

method clone*(self: WText): WWidget =
  result = WText(text: self.text, style: self.style)
  self.copyTo(result)