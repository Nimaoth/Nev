import std/options
import vmath, bumpy, chroma
import theme, rect_utils, custom_logger

export rect_utils, vmath, bumpy

type
  WWidget* = ref object of RootObj
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

  WPanel* = ref object of WWidget
    maskContent*: bool
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
  let topLeft = container.xy + self.anchor.min * container.wh + vec2(self.left, self.top)
  let bottomRight = container.xy + self.anchor.max * container.wh + vec2(self.right, self.bottom)
  let pivotOffset = self.pivot * (bottomRight - topLeft)
  result = rect(topLeft - pivotOffset, bottomRight - topLeft)

method layoutWidget*(self: WPanel, container: Rect, frameIndex: int, options: WLayoutOptions) =
  let newBounds = self.calculateBounds(container)

  if self.logLayout:
    debugf"layoutPanel({container}, {frameIndex}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"
    if newBounds != self.lastBounds:
      debugf"bounds changed {self.lastBounds} -> {newBounds}"

  if newBounds != self.lastBounds:
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    for c in self.children:
      c.layoutWidget(newBounds, frameIndex, options)

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