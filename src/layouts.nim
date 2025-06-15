import std/[tables, options, json, sugar, sequtils, strutils, sets]
import bumpy
import misc/[custom_async, custom_logger, rect_utils, myjsonutils, util, jsonex, id]
import document, document_editor, view

logCategory "layouts"

{.push gcsafe.}
{.push raises: [].}

type
  LayoutError* = object of CatchableError

  Layout* = ref object of View
    childTemplate*: Layout
    children*: seq[View]
    activeIndex*: int
    slots*: Table[string, string]
    maxChildren*: int = int.high
    maximize*: bool = false
    temporary*: bool = false

  AutoLayout* = ref object of Layout
    splitRatios*: seq[float]

  HorizontalLayout* = ref object of AutoLayout
  VerticalLayout* = ref object of AutoLayout
  AlternatingLayout* = ref object of AutoLayout

  TabLayout* = ref object of Layout

  CenterLayout* = ref object of Layout
    childTemplates*: seq[Layout]
    splitRatios*: array[4, float] = [0.2, 0.7, 0.25, 0.66]

proc extractSlot*(path: string): tuple[current, remainder: string] =
  let i = path.find('.')
  if i == -1:
    return (path, "")
  else:
    return (path[0..<i], path[(i + 1)..^1])

const MainLayoutLeft* = 0
const MainLayoutRight* = 1
const MainLayoutTop* = 2
const MainLayoutBottom* = 3
const MainLayoutCenter* = 4

proc left*(self: CenterLayout): View = self.children[0]
proc right*(self: CenterLayout): View = self.children[1]
proc top*(self: CenterLayout): View = self.children[2]
proc bottom*(self: CenterLayout): View = self.children[3]
proc center*(self: CenterLayout): View = self.children[4]
proc `left=`*(self: CenterLayout, view: View) = self.children[0] = view
proc `right=`*(self: CenterLayout, view: View) = self.children[1] = view
proc `top=`*(self: CenterLayout, view: View) = self.children[2] = view
proc `bottom=`*(self: CenterLayout, view: View) = self.children[3] = view
proc `center=`*(self: CenterLayout, view: View) = self.children[4] = view

proc leftTemplate*(self: CenterLayout): Layout = self.childTemplates[0]
proc rightTemplate*(self: CenterLayout): Layout = self.childTemplates[1]
proc topTemplate*(self: CenterLayout): Layout = self.childTemplates[2]
proc bottomTemplate*(self: CenterLayout): Layout = self.childTemplates[3]
proc centerTemplate*(self: CenterLayout): Layout = self.childTemplates[4]
proc `leftTemplate=`*(self: CenterLayout, layout: Layout) = self.childTemplates[0] = layout
proc `rightTemplate=`*(self: CenterLayout, layout: Layout) = self.childTemplates[1] = layout
proc `topTemplate=`*(self: CenterLayout, layout: Layout) = self.childTemplates[2] = layout
proc `bottomTemplate=`*(self: CenterLayout, layout: Layout) = self.childTemplates[3] = layout
proc `centerTemplate=`*(self: CenterLayout, layout: Layout) = self.childTemplates[4] = layout

proc getSplitRatio*(self: AutoLayout, index: int): float =
  if index in 0..self.splitRatios.high:
    return self.splitRatios[index]
  return 0.5

proc setSplitRatio*(self: AutoLayout, index: int, value: float) =
  if index < 0:
    return
  if self.splitRatios.high < index:
    let oldLen = self.splitRatios.len
    self.splitRatios.setLen(index + 1)
    for i in oldLen..self.splitRatios.high:
      self.splitRatios[i] = 0.5
  self.splitRatios[index] = value.clamp(0, 1)

method getView*(self: Layout, path: string): View {.base.} =
  if path == "":
    return self
  let (slot, subPath) = path.extractSlot
  case slot
  of "**":
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.getView(slot)
      # Don't return c here becauses for ** we want to return a layout, not a non-layout view
    return self

  of "", "*":
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.getView(subPath)
      return c
    return self

  else:
    try:
      let index = slot.parseInt
      if index in 0..self.children.high:
        let c = self.children[index]
        if c of Layout:
          return c.Layout.getView(subPath)
        return c
      return self
    except:
      return self

method getView*(self: CenterLayout, path: string): View =
  if path == "":
    return self
  let (slot, subPath) = path.extractSlot
  case slot
  of "**":
    let c = self.children[self.activeIndex]
    if c != nil and c of Layout:
      return c.Layout.getView(slot)
    # Don't return c here becauses for ** we want to return a layout, not a non-layout view
    return self
  of "", "*": result = self.children[self.activeIndex]
  of "center": result = self.center
  of "left": result = self.left
  of "right": result = self.right
  of "top": result = self.top
  of "bottom": result = self.bottom
  else:
    try:
      let index = slot.parseInt
      if index in 0..self.children.high:
        result = self.children[index]
      else:
        return nil
    except:
      return nil

  if result != nil and result of Layout:
    result = result.Layout.getView(subPath)


proc forEachViewImpl(self: Layout, cb: proc(view: View): bool {.gcsafe, raises: [].}): bool =
  for i, c in self.children:
    if c == nil:
      continue
    if cb(c):
      return true
    if c of Layout:
      if c.Layout.forEachViewImpl(cb):
        return true

proc forEachView*(self: Layout, cb: proc(view: View): bool {.gcsafe, raises: [].}) =
  discard self.forEachViewImpl(cb)

method forEachVisibleViewImpl(self: Layout, cb: proc(view: View): bool {.gcsafe, raises: [].}): bool {.base.} =
  for i, c in self.children:
    if c == nil:
      continue
    if cb(c):
      return true
    if c of Layout:
      if c.Layout.forEachVisibleViewImpl(cb):
        return true

method forEachVisibleViewImpl(self: TabLayout, cb: proc(view: View): bool {.gcsafe, raises: [].}): bool =
  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if cb(c):
      return true
    if c of Layout:
      return c.Layout.forEachVisibleViewImpl(cb)

proc forEachVisibleView*(self: Layout, cb: proc(view: View): bool {.gcsafe, raises: [].}) =
  discard self.forEachVisibleViewImpl(cb)

proc parentLayout*(self: Layout, view: View): Layout =
  var res: Layout = nil
  self.forEachView proc(v: View): bool =
    if v of Layout and view in v.Layout.children:
      res = v.Layout
      return true
  return res

proc leafViews*(self: Layout): seq[View] =
  var res = newSeq[View]()
  self.forEachView proc(v: View): bool =
    if not (v of Layout):
      res.add v
  return res

proc visibleLeafViews*(self: Layout): seq[View] =
  var res = newSeq[View]()
  self.forEachVisibleView proc(v: View): bool =
    if not (v of Layout):
      res.add v
  return res

method desc*(self: View): string {.base.} = "View"
method desc*(self: Layout): string = "Layout"
method desc*(self: CenterLayout): string = "CenterLayout"
method desc*(self: HorizontalLayout): string = "HorizontalLayout"
method desc*(self: VerticalLayout): string = "VerticalLayout"
method desc*(self: AlternatingLayout): string = "AlternatingLayout"
method desc*(self: TabLayout): string = "TabLayout"

method kind*(self: View): string {.base.} = ""
method kind*(self: CenterLayout): string = "center"
method kind*(self: HorizontalLayout): string = "horizontal"
method kind*(self: VerticalLayout): string = "vertical"
method kind*(self: AlternatingLayout): string = "alternating"
method kind*(self: TabLayout): string = "tab"

method copy*(self: Layout): Layout {.base.} = assert(false)

proc copyNonNilChildren(self: Layout, src: Layout): Layout =
  self.children = collect:
    for c in src.children:
      if c != nil and c of Layout:
        c.Layout.copy().View

proc copyAllChildren(self: Layout, src: Layout): Layout =
  self.children = collect:
    for c in src.children:
      if c != nil and c of Layout:
        c.Layout.copy().View
      else:
        nil

proc copyBase(self: Layout, src: Layout): Layout =
  if src.childTemplate != nil:
    self.childTemplate = src.childTemplate.copy()
  self.activeIndex = src.activeIndex
  self.slots = src.slots
  self.maxChildren = src.maxChildren
  self.maximize = src.maximize
  self.temporary = src.temporary
  return self

method copy*(self: CenterLayout): Layout =
  CenterLayout(
    childTemplates: self.childTemplates.mapIt(if it != nil: it.copy() else: nil),
    splitRatios: self.splitRatios,
  ).copyBase(self).copyAllChildren(self)

method copy*(self: HorizontalLayout): Layout =
  HorizontalLayout(splitRatios: self.splitRatios).copyBase(self).copyNonNilChildren(self)

method copy*(self: VerticalLayout): Layout =
  VerticalLayout(splitRatios: self.splitRatios).copyBase(self).copyNonNilChildren(self)

method copy*(self: AlternatingLayout): Layout =
  AlternatingLayout(splitRatios: self.splitRatios).copyBase(self).copyNonNilChildren(self)

method copy*(self: TabLayout): Layout =
  TabLayout().copyBase(self).copyNonNilChildren(self)

method display*(self: View): string {.base.} = ""

method numLeafViews*(self: Layout): int {.base.} =
  for c in self.children:
    if c != nil:
      if c of Layout:
        result += c.Layout.numLeafViews()
      else:
        inc result

proc firstLeaf*(self: Layout): View =
  for c in self.children:
    if c == nil:
      continue
    if c of Layout:
      let leaf = c.Layout.firstLeaf()
      if leaf != nil:
        return leaf
      continue
    return c
  return nil

proc collapseTemporaryViews*(self: Layout) =
  for i, c in self.children:
    if c == nil:
      continue
    if c of Layout:
      let layout = c.Layout
      layout.collapseTemporaryViews()
      if layout.temporary and layout.children.len == 1 and layout.children[0] != nil:
        self.children[i] = layout.children[0]

method activeLeafView*(self: View): View {.base.} = self
method activeLeafView*(self: Layout): View =
  if self.activeIndex in 0..self.children.high and self.children[self.activeIndex] != nil:
    return self.children[self.activeIndex].activeLeafView()

method activeLeafLayout*(self: Layout): Layout {.base.} =
  if self.activeIndex in 0..self.children.high and self.children[self.activeIndex] != nil:
    let child = self.children[self.activeIndex]
    if child of Layout:
      return self.children[self.activeIndex].Layout.activeLeafLayout()

  return self

method removeView*(self: Layout, view: View): bool {.base.} =
  for i, c in self.children:
    if c == view:
      self.children.removeShift(i)
      self.activeIndex = min(self.activeIndex, self.children.high)
      return true
    if c of Layout:
      if c.Layout.removeView(view):
        if self.children.len > 0 and c.Layout.numLeafViews() == 0:
          self.children.removeShift(i)
          self.activeIndex = min(self.activeIndex, self.children.high)
        return true

  return false

method removeView*(self: CenterLayout, view: View): bool =
  for i, c in self.children:
    if c == view:
      self.children[i] = nil
      for k in countdown(self.children.high, 0):
        if self.children[k] != nil:
          self.activeIndex = k
          break
      return true
    if c of Layout:
      if c.Layout.removeView(view):
        if c.Layout.numLeafViews() == 0:
          self.children[i] = nil
          for k in countdown(self.children.high, 0):
            if self.children[k] != nil:
              self.activeIndex = k
              break
        return true

  return false

method saveLayout*(self: View, discardedViews: HashSet[Id]): JsonNode {.base.} =
  result = newJObject()
  result["id"] = self.id.toJson

method saveLayout*(self: Layout, discardedViews: HashSet[Id]): JsonNode =
  if self.children.len == 0:
    return nil
  result = newJObject()
  result["kind"] = self.kind.toJson
  var children = newJArray()
  for i, c in self.children:
    if c == nil:
      children.add newJNull()
    elif c.id notin discardedViews:
      let saved = c.saveLayout(discardedViews)
      if saved != nil:
        children.add saved

  result["activeIndex"] = self.activeIndex.toJson
  result["temporary"] = self.temporary.toJson
  result["max-children"] = self.maxChildren.toJson
  result["children"] = children

method saveLayout*(self: AutoLayout, discardedViews: HashSet[Id]): JsonNode =
  if self.children.len == 0:
    return nil
  result = newJObject()
  result["kind"] = self.kind.toJson
  var children = newJArray()
  for i, c in self.children:
    if c == nil:
      children.add newJNull()
    elif c.id notin discardedViews:
      let saved = c.saveLayout(discardedViews)
      if saved != nil:
        children.add saved

  result["activeIndex"] = self.activeIndex.toJson
  result["children"] = children
  result["temporary"] = self.temporary.toJson
  result["max-children"] = self.maxChildren.toJson
  result["split-ratios"] = self.splitRatios.toJson()

method saveLayout*(self: CenterLayout, discardedViews: HashSet[Id]): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  var children = newJArray()
  for i, c in self.children:
    if c == nil:
      children.add newJNull()
    elif c.id notin discardedViews:
      let saved = c.saveLayout(discardedViews)
      if saved != nil:
        children.add saved
      else:
        children.add newJNull()

  result["activeIndex"] = self.activeIndex.toJson
  result["children"] = children
  result["temporary"] = self.temporary.toJson
  result["max-children"] = self.maxChildren.toJson
  result["split-ratios"] = self.splitRatios.toJson()

method leftLeaf*(self: View): View {.base.} = self
method rightLeaf*(self: View): View {.base.} = self
method topLeaf*(self: View): View {.base.} = self
method bottomLeaf*(self: View): View {.base.} = self

method leftLeaf*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].leftLeaf()

method leftLeaf*(self: VerticalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].leftLeaf()

method leftLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].leftLeaf()
    return self.children[0].leftLeaf()

method leftLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].leftLeaf()
    return self.children[0].leftLeaf()

method leftLeaf*(self: CenterLayout): View =
  if self.left != nil: return self.left.leftLeaf()
  if self.center != nil: return self.center.leftLeaf()
  if self.top != nil: return self.top.leftLeaf()
  if self.bottom != nil: return self.bottom.leftLeaf()
  if self.right != nil: return self.right.leftLeaf()
  return nil

method rightLeaf*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].rightLeaf()

method rightLeaf*(self: VerticalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].rightLeaf()

method rightLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].rightLeaf()
    return self.children.last.rightLeaf()

method rightLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].rightLeaf()
    if self.activeIndex mod 2 != 0:
      return self.children[self.activeIndex].rightLeaf()
    return self.children.last.rightLeaf()

method rightLeaf*(self: CenterLayout): View =
  if self.right != nil: return self.right.rightLeaf()
  if self.center != nil: return self.center.rightLeaf()
  if self.bottom != nil: return self.bottom.rightLeaf()
  if self.top != nil: return self.top.rightLeaf()
  if self.left != nil: return self.left.rightLeaf()
  return nil

method topLeaf*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].topLeaf()

method topLeaf*(self: VerticalLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].topLeaf()
    return self.children[0].topLeaf()

method topLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].topLeaf()

method topLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].topLeaf()
    if self.activeIndex <= 1:
      return self.children[self.activeIndex].topLeaf()
    return self.children[0].topLeaf()

method topLeaf*(self: CenterLayout): View =
  if self.top != nil: return self.top.topLeaf()
  if self.center != nil: return self.center.topLeaf()
  if self.left != nil: return self.left.topLeaf()
  if self.right != nil: return self.right.topLeaf()
  if self.bottom != nil: return self.bottom.topLeaf()
  return nil

method bottomLeaf*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].bottomLeaf()

method bottomLeaf*(self: VerticalLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].bottomLeaf()
    return self.children.last.bottomLeaf()

method bottomLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].bottomLeaf()

method bottomLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.maximize:
      return self.children[self.activeIndex].bottomLeaf()
    if self.activeIndex mod 2 == 0:
      return self.children[self.activeIndex].bottomLeaf()
    return self.children.last.bottomLeaf()

method bottomLeaf*(self: CenterLayout): View =
  if self.bottom != nil: return self.bottom.bottomLeaf()
  if self.center != nil: return self.center.bottomLeaf()
  if self.right != nil: return self.right.bottomLeaf()
  if self.left != nil: return self.left.bottomLeaf()
  if self.top != nil: return self.top.bottomLeaf()
  return nil

method tryGetViewLeft*(self: View): View {.base.} = nil
method tryGetViewLeft*(self: Layout): View = nil
method tryGetViewLeft*(self: VerticalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewLeft()

method tryGetViewLeft*(self: HorizontalLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewLeft()
    if self.maximize or result != nil:
      return
  if self.activeIndex > 0:
    return self.children[self.activeIndex - 1].rightLeaf

method tryGetViewLeft*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewLeft()
    if self.maximize or result != nil:
      return
  if self.activeIndex > 0:
    if self.activeIndex mod 2 == 0:
      return self.children[self.activeIndex - 2].rightLeaf
    else:
      return self.children[self.activeIndex - 1].rightLeaf

method tryGetViewLeft*(self: CenterLayout): View =
  result = self.children[self.activeIndex].tryGetViewLeft()
  if result != nil:
    return
  const order = [MainLayoutRight, MainLayoutCenter, MainLayoutLeft]
  var k = order.find(self.activeIndex)
  if k == -1:
    k = 1
  for i in (k + 1)..order.high:
    let index = order[i]
    if self.children[index] != nil:
      result = self.children[index].rightLeaf
      if result != nil:
        return

method tryGetViewLeft*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewLeft()

method tryGetViewRight*(self: View): View {.base.} = nil
method tryGetViewRight*(self: Layout): View = nil
method tryGetViewRight*(self: VerticalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewRight()

method tryGetViewRight*(self: HorizontalLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewRight()
    if self.maximize or result != nil:
      return
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].leftLeaf

method tryGetViewRight*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewRight()
    if self.maximize or result != nil:
      return
  if self.activeIndex mod 2 != 0:
    return nil
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].leftLeaf

method tryGetViewRight*(self: CenterLayout): View =
  result = self.children[self.activeIndex].tryGetViewRight()
  if result != nil:
    return
  const order = [MainLayoutLeft, MainLayoutCenter, MainLayoutRight]
  var k = order.find(self.activeIndex)
  if k == -1:
    k = 1
  for i in (k + 1)..order.high:
    let index = order[i]
    if self.children[index] != nil:
      result = self.children[index].leftLeaf
      if result != nil:
        return

method tryGetViewRight*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewRight()

method tryGetViewUp*(self: View): View {.base.} = nil
method tryGetViewUp*(self: Layout): View = nil
method tryGetViewUp*(self: VerticalLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewUp()
    if self.maximize or result != nil:
      return
  if self.activeIndex > 0:
    return self.children[self.activeIndex - 1].bottomLeaf

method tryGetViewUp*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewUp()

method tryGetViewUp*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewUp()
    if self.maximize or result != nil:
      return
  if self.activeIndex <= 1:
    return nil
  if self.activeIndex mod 2 == 0:
    return self.children[self.activeIndex - 1].bottomLeaf
  if self.activeIndex > 0:
    return self.children[self.activeIndex - 2].bottomLeaf

method tryGetViewUp*(self: CenterLayout): View =
  result = self.children[self.activeIndex].tryGetViewUp()
  if result != nil:
    return
  const order = [MainLayoutBottom, MainLayoutCenter, MainLayoutTop]
  let k = order.find(self.activeIndex)
  if k == -1:
    return
  for i in (k + 1)..order.high:
    let index = order[i]
    if self.children[index] != nil:
      result = self.children[index].bottomLeaf
      if result != nil:
        return

method tryGetViewUp*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewUp()

method tryGetViewDown*(self: View): View {.base.} = nil
method tryGetViewDown*(self: Layout): View = nil
method tryGetViewDown*(self: VerticalLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewDown()
    if self.maximize or result != nil:
      return
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].topLeaf

method tryGetViewDown*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewDown()

method tryGetViewDown*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewDown()
    if self.maximize or result != nil:
      return
  if self.activeIndex mod 2 == 0:
    return nil
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].topLeaf

method tryGetViewDown*(self: CenterLayout): View =
  result = self.children[self.activeIndex].tryGetViewDown()
  if result != nil:
    return
  const order = [MainLayoutTop, MainLayoutCenter, MainLayoutBottom]
  let k = order.find(self.activeIndex)
  if k == -1:
    return
  for i in (k + 1)..order.high:
    let index = order[i]
    if self.children[index] != nil:
      result = self.children[index].topLeaf
      if result != nil:
        return

method tryGetNextView*(self: Layout): View {.base.} =
  var i = self.activeIndex + 1
  while i < self.children.len:
    if self.children[i] != nil:
      break
    inc i
  if i < self.children.len:
    return self.children[i]
  else:
    for i in 0..<self.activeIndex:
      if self.children[i] != nil:
        return self.children[i]

method tryGetPrevView*(self: Layout): View {.base.} =
  var i = self.activeIndex - 1
  while i >= 0:
    if self.children[i] != nil:
      break
    dec i
  if i >= 0:
    return self.children[i]
  else:
    for i in countdown(self.children.high, self.activeIndex + 1):
      if self.children[i] != nil:
        return self.children[i]

method tryGetViewDown*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewDown()

method activeLeafSlot*(self: Layout): string {.base.} =
  if self.children.len > 0 and self.children[self.activeIndex] != nil and self.children[self.activeIndex] of Layout:
    result.add $self.activeIndex
    let childSlot = self.children[self.activeIndex].Layout.activeLeafSlot()
    if childSlot.len > 0:
      result.add "."
      result.add childSlot

method getSlot*(self: Layout, view: View): string {.base.} =
  for i, c in self.children:
    if c == view:
      return $i
    if c of Layout:
      let subSlot = c.Layout.getSlot(view)
      if subSlot != "":
        return $i & "." & subSlot

  return ""

proc slotName*(_: typedesc[CenterLayout], index: int): string =
  case index
  of MainLayoutLeft: return "left"
  of MainLayoutRight: return "right"
  of MainLayoutTop: return "top"
  of MainLayoutBottom: return "bottom"
  of MainLayoutCenter: return "center"
  else: return ""

method getSlot*(self: CenterLayout, view: View): string =
  for i, c in self.children:
    if c == view:
      return CenterLayout.slotName(i)
    if c of Layout:
      let subSlot = c.Layout.getSlot(view)
      if subSlot != "":
        return CenterLayout.slotName(i) & "." & subSlot

  return ""

method addView*(self: Layout, view: View, path: string = "", focus: bool = true): View {.base, raises: [LayoutError].} =
  # debugf"{self.desc}.addView {view.desc()} to slot '{path}', focus = {focus}"
  var index = self.children.len
  var path = path
  var (slot, subPath) = path.extractSlot
  var insert = false
  var replaceLast = true
  while true:
    case slot
    of "":
      index = self.activeIndex
    of "**":
      if self.children.len > 0 and self.children[self.activeIndex] of Layout:
        return self.children[self.activeIndex].Layout.addView(view, path, focus)
      slot = subPath
      subPath = ""
      continue
    else:
      if slot.startsWith("*") or slot.startsWith("+"):
        var i = 0
        while i < slot.len:
          defer:
            inc i
          let c = slot[i]
          let next = if i + 1 < slot.len: slot[i + 1] else: '\0'
          case c
          of '*':
            index = self.activeIndex
          of '+':
            insert = true
          of '<':
            if next == '>':
              index = self.activeIndex + 1
              if index >= self.children.len and (self.children.len == self.maxChildren or not insert):
                index = self.activeIndex - 1
              inc i
            else:
              index = self.activeIndex - 1
          of '>':
            index = self.activeIndex + 1
          of '?':
            replaceLast = false
          else:
            raise newException(LayoutError, &"Unknown character in slot '{slot}' at index {i}: '{c}'. Expected one of {{'*', '+', '<', '>', '?'}}")

        break

      elif slot.startsWith("#"):
        let slotName = slot[1..^1]
        if slotName in self.slots:
          path = self.slots[slotName]
          (slot, subPath) = path.extractSlot
          continue
        raise newException(LayoutError, &"Unknown slot '{slotName}'")

      else:
        try:
          index = slot.parseInt.clamp(0, self.children.len)
          if index == self.children.len:
            insert = true
          break
        except Exception as e:
          raise newException(LayoutError, &"Invalid slot: {e.msg}", e)

    break

  if insert:
    index = index.clamp(0, self.children.len)
  else:
    index = index.clamp(0, self.children.high)

  if insert:
    if self.children.len == self.maxChildren:
      if self.children[index] of Layout:
        return self.children[index].Layout.addView(view, path, focus)
      if replaceLast or index >= self.children.len:
        result = self.children.pop()
      else:
        result = self.children[index]
        self.children.removeShift(index)
      index = index.clamp(0, self.children.len)
    if self.childTemplate != nil:
      let newChild = self.childTemplate.copy()
      self.children.insert(newChild, index)
      if focus:
        self.activeIndex = index
      self.activeIndex = self.activeIndex.clamp(0, self.children.high)
      return newChild.addView(view, subPath, focus)
    else:
      self.children.insert(view, index)
      if focus:
        self.activeIndex = index
      self.activeIndex = self.activeIndex.clamp(0, self.children.high)

  elif self.children.len == 0:
    if self.childTemplate != nil:
      let newChild = self.childTemplate.copy()
      self.children.add(newChild)
      if focus:
        self.activeIndex = self.children.high
      self.activeIndex = self.activeIndex.clamp(0, self.children.high)
      return newChild.addView(view, subPath, focus)
    else:
      self.children.add(view)
      if focus:
        self.activeIndex = self.children.high
      self.activeIndex = self.activeIndex.clamp(0, self.children.high)
  elif self.children[index] != nil and self.children[index] of Layout:
    if focus:
      self.activeIndex = index
    return self.children[index].Layout.addView(view, subPath, focus)
  elif self.childTemplate != nil:
    result = self.children[index]
    let newChild = self.childTemplate.copy()
    self.children[index] = newChild
    if focus:
      self.activeIndex = index
    discard newChild.addView(view, subPath, focus)
  else:
    result = self.children[index]
    self.children[index] = view
    if focus:
      self.activeIndex = index

method addView*(self: CenterLayout, view: View, path: string = "", focus: bool = true): View {.raises: [LayoutError].} =
  # debugf"CenterLayout.addView {view.desc()} to slot '{path}', focus = {focus}"
  var index = 4
  var (slot, subPath) = path.extractSlot
  while true:
    case slot
    of "", "*": index = self.activeIndex
    of "left": index = 0
    of "right": index = 1
    of "top": index = 2
    of "bottom": index = 3
    of "center": index = 4
    else:
      if slot.startsWith("#"):
        let slotName = slot[1..^1]
        if slotName in self.slots:
          (slot, subPath) = self.slots[slotName].extractSlot
          continue
        raise newException(LayoutError, &"Unknown slot '{slotName}'")

      try:
        index = slot.parseInt.clamp(0, self.children.high)
      except Exception as e:
        raise newException(LayoutError, &"Invalid slot: {e.msg}", e)

    break

  if self.children[index] != nil and self.children[index] of Layout:
    if focus:
      self.activeIndex = index
    return self.children[index].Layout.addView(view, subPath, focus)
  elif self.childTemplates[index] != nil:
    let newChild = self.childTemplates[index].copy()
    self.children[index] = newChild
    if focus:
      self.activeIndex = index
    return newChild.addView(view, subPath, focus)
  else:
    result = self.children[index]
    self.children[index] = view
    if focus:
      self.activeIndex = index

method tryActivateView*(self: Layout, predicate: proc(view: View): bool {.gcsafe, raises: [].}): bool {.base.} =
  for i, c in self.children:
    if c == nil:
      continue
    if predicate(c):
      self.activeIndex = i
      return true
    if c of Layout:
      if c.Layout.tryActivateView(predicate):
        self.activeIndex = i
        return true

  return false

method changeSplitSize*(self: Layout, change: float, vertical: bool): bool {.base.} =
  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if c of Layout:
      return c.Layout.changeSplitSize(change, vertical)

  return false

method changeSplitSize*(self: AutoLayout, change: float, vertical: bool): bool =
  if self.maximize:
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.changeSplitSize(change, vertical)
    return false

  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if c of Layout and c.Layout.changeSplitSize(change, vertical):
        return true

    var index = self.activeIndex
    if index == self.children.high:
      index -= 1

    self.setSplitRatio(index, self.getSplitRatio(index) + change)
    return true

  return false

method changeSplitSize*(self: VerticalLayout, change: float, vertical: bool): bool =
  if self.maximize:
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.changeSplitSize(change, vertical)
    return false

  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if c of Layout and c.Layout.changeSplitSize(change, vertical):
      return true

    if not vertical:
      return false

    var index = self.activeIndex
    if index == self.children.high:
      index -= 1

    self.setSplitRatio(index, self.getSplitRatio(index) + change)
    return true

  return false

method changeSplitSize*(self: HorizontalLayout, change: float, vertical: bool): bool =
  if self.maximize:
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.changeSplitSize(change, vertical)
    return false

  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if c of Layout and c.Layout.changeSplitSize(change, vertical):
      return true

    if vertical:
      return false

    var index = self.activeIndex
    if index == self.children.high:
      index -= 1

    self.setSplitRatio(index, self.getSplitRatio(index) + change)
    return true

  return false

method changeSplitSize*(self: AlternatingLayout, change: float, vertical: bool): bool =
  if self.maximize:
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.changeSplitSize(change, vertical)
    return false

  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if c of Layout and c.Layout.changeSplitSize(change, vertical):
      return true

    var index = self.activeIndex
    if index == self.children.high:
      index -= 1

    if index < 0:
      return false

    if not vertical and index mod 2 != 0:
      index -= 1
    elif vertical and index > 0 and index mod 2 == 0:
      index -= 1
    elif vertical and index == 0:
      return false
    elif vertical and index == 0:
      return false

    self.setSplitRatio(index, self.getSplitRatio(index) + change)
    return true

  return false

method changeSplitSize*(self: TabLayout, change: float, vertical: bool): bool =
  if self.children.len > 0:
    let c = self.children[self.activeIndex]
    if c of Layout:
      return c.Layout.changeSplitSize(change, vertical)

  return false

method changeSplitSize*(self: CenterLayout, change: float, vertical: bool): bool =
  let c = self.children[self.activeIndex]
  if c != nil and c of Layout:
    if c.Layout.changeSplitSize(change, vertical):
      return true

  var index = self.activeIndex
  if index == MainLayoutCenter:
    if vertical:
      if self.children[MainLayoutBottom] != nil:
        index = MainLayoutBottom
      elif self.children[MainLayoutTop] != nil:
        index = MainLayoutTop
      else:
        return false
    else:
      if self.children[MainLayoutLeft] != nil:
        index = MainLayoutLeft
      elif self.children[MainLayoutRight] != nil:
        index = MainLayoutRight
      else:
        return false

  if index < 4:
    self.splitRatios[index] = (self.splitRatios[index] + change).clamp(0, 1)
    return true

  return false

proc createLayout*(config: JsonNode, resolve: proc(id: Id): View {.gcsafe, raises: [].} = nil): View {.raises: [ValueError].} =
  if config.kind == JNull:
    return nil

  if config.hasKey("id"):
    if resolve != nil:
      return resolve(config["id"].jsonTo(Id))
    else:
      raise newException(ValueError, "Can't resolve layout id, no resolver")

  checkJson config.hasKey("kind") and config["kind"].kind == Jstring, "Expected field 'kind' of type string"
  let kind = config["kind"].getStr

  template parseLayoutFields(res: Layout): untyped =
    if config.hasKey("children"):
      let children = config["children"]
      checkJson children.kind == JArray, "'children' must be an array"
      for i, c in children.elems:
        res.children.add createLayout(c, resolve)
    if config.hasKey("childTemplate"):
      res.childTemplate = createLayout(config["childTemplate"], resolve).Layout
    if config.hasKey("activeIndex"):
      let activeIndex = config["activeIndex"]
      checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
      res.activeIndex = activeIndex.getInt.clamp(0, res.children.high)
    if config.hasKey("slots"):
      res.slots = config["slots"].jsonTo(Table[string, string])
    if config.hasKey("max-children"):
      res.maxChildren = config["max-children"].jsonTo(int)
    if config.hasKey("temporary"):
      res.temporary = config["temporary"].jsonTo(bool)

  template parseAutoLayoutFields(res: AutoLayout): untyped =
    if config.hasKey("split-ratios"):
      res.splitRatios = config["split-ratios"].jsonTo(seq[float]).mapIt(it.clamp(0, 1))

  case kind
  of "center":
    let res = CenterLayout(children: newSeq[View](5), childTemplates: newSeq[Layout](5))
    if config.hasKey("slots"):
      res.slots = config["slots"].jsonTo(Table[string, string])
    if config.hasKey("children"):
      let children = config["children"]
      checkJson children.kind == JArray, "'children' must be an array"
      for i, c in children.elems:
        if i < res.children.len:
          res.children[i] = createLayout(c, resolve)
    else:
      if config.hasKey("left"):
        res.leftTemplate = createLayout(config["left"], resolve).Layout
      if config.hasKey("right"):
        res.rightTemplate = createLayout(config["right"], resolve).Layout
      if config.hasKey("top"):
        res.topTemplate = createLayout(config["top"], resolve).Layout
      if config.hasKey("bottom"):
        res.bottomTemplate = createLayout(config["bottom"], resolve).Layout
      if config.hasKey("center"):
        res.centerTemplate = createLayout(config["center"], resolve).Layout

    if config.hasKey("activeIndex"):
      let activeIndex = config["activeIndex"]
      checkJson activeIndex.kind == JInt, "'activeIndex' must be an integer"
      res.activeIndex = activeIndex.getInt.clamp(0, res.children.high)

    if config.hasKey("split-ratios"):
      res.splitRatios = config["split-ratios"].jsonTo(array[4, float])
      for i in 0..<res.splitRatios.len:
        res.splitRatios[i] = res.splitRatios[i].clamp(0, 1)

    return res

  of "horizontal":
    let res = HorizontalLayout()
    res.parseLayoutFields()
    res.parseAutoLayoutFields()
    return res

  of "vertical":
    let res = VerticalLayout()
    res.parseLayoutFields()
    res.parseAutoLayoutFields()
    return res

  of "alternating":
    let res = AlternatingLayout()
    res.parseLayoutFields()
    res.parseAutoLayoutFields()
    return res

  of "tab":
    let res = TabLayout()
    res.parseLayoutFields()
    return res

  else:
    raise newException(ValueError, &"Invalid kind for layout: '{kind}'")
