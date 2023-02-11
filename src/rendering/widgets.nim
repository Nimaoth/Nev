import std/[colors]
import vmath, bumpy
import ../theme, ../rect_utils

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
    sizeToContent*: bool
    drawBorder*: bool

  WPanel* = ref object of WWidget
    children*: seq[WWidget]

  WHorizontalList* = ref object of WWidget
    children*: seq[WWidget]
  WVerticalList* = ref object of WWidget
    children*: seq[WWidget]

  WText* = ref object of WWidget
    text*: string
    style*: Style

method layoutWidget*(self: WWidget, bounds: Rect, frameIndex: int) {.base.} = discard

proc changed*(self: WWidget, frameIndex: int): bool =
  result = self.lastBoundsChange >= frameIndex or self.lastHierarchyChange >= frameIndex

proc calculateBounds(self: WWidget, container: Rect): Rect =
  let topLeft = container.xy + self.anchor.min * container.wh + vec2(self.left, self.top)
  let bottomRight = container.xy + self.anchor.max * container.wh + vec2(self.right, self.bottom)
  let pivotOffset = self.pivot * (bottomRight - topLeft)
  result = rect(topLeft - pivotOffset, bottomRight - topLeft)

method layoutWidget*(self: WPanel, container: Rect, frameIndex: int) =
  let newBounds = self.calculateBounds(container)
  # debugf"layoutWidgetPanel({container}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"

  if newBounds != self.lastBounds:
    # debugf"bounds changed {self.lastBounds} -> {newBounds}"
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    for c in self.children:
      c.layoutWidget(newBounds, frameIndex)

method layoutWidget*(self: WVerticalList, container: Rect, frameIndex: int) =
  let newBounds = self.calculateBounds(container)
  # debugf"layoutWidgetVerticalList({container}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"

  if newBounds != self.lastBounds:
    # debugf"bounds changed {self.lastBounds} -> {newBounds}"
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    var lastY = 0.0
    for c in self.children:
      c.top = lastY
      c.bottom = lastY + 1
      c.layoutWidget(newBounds, frameIndex)
      lastY = c.lastBounds.yh - newBounds.y

method layoutWidget*(self: WHorizontalList, container: Rect, frameIndex: int) =
  let newBounds = self.calculateBounds(container)
  # debugf"layoutWidgetHorizontalList({container}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"

  if newBounds != self.lastBounds:
    # debugf"bounds changed {self.lastBounds} -> {newBounds}"
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex

  if self.lastHierarchyChange >= frameIndex or self.lastBoundsChange >= frameIndex:
    var lastX = 0.0
    for c in self.children:
      c.left = lastX
      c.right = lastX + 1
      c.layoutWidget(newBounds, frameIndex)
      lastX = c.lastBounds.xw - newBounds.x

method layoutWidget*(self: WText, container: Rect, frameIndex: int) =
  # self.pivot.x = fractional(frameIndex.float / 100.0f)
  if self.sizeToContent:
    self.right = self.left + self.text.len.float
  let newBounds = self.calculateBounds(container)
  # debugf"layoutWidgetText({container}): anchor={self.anchor}, pivot={self.pivot}, {self.left},{self.top}, {self.right},{self.bottom} -> {newBounds}"

  if newBounds != self.lastBounds:
    # debugf"bounds changed {self.lastBounds} -> {newBounds}"
    self.lastBounds = newBounds
    self.lastBoundsChange = frameIndex