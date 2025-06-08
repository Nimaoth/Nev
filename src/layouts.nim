import std/[tables, options, json, sugar, sequtils, strutils]
import bumpy
import misc/[custom_async, custom_logger, rect_utils, myjsonutils, util, jsonex]
import document, document_editor, view

logCategory "layouts"

{.push gcsafe.}
{.push raises: [].}

type
  Layout* = ref object of View
    childTemplate*: Layout
    children*: seq[View]
    activeIndex*: int
  HorizontalLayout* = ref object of Layout
  VerticalLayout* = ref object of Layout
  AlternatingLayout* = ref object of Layout

  TabLayout* = ref object of Layout

  MainLayout* = ref object of Layout
    childTemplates*: seq[Layout]

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

proc left*(self: MainLayout): View = self.children[0]
proc right*(self: MainLayout): View = self.children[1]
proc top*(self: MainLayout): View = self.children[2]
proc bottom*(self: MainLayout): View = self.children[3]
proc center*(self: MainLayout): View = self.children[4]
proc `left=`*(self: MainLayout, view: View) = self.children[0] = view
proc `right=`*(self: MainLayout, view: View) = self.children[1] = view
proc `top=`*(self: MainLayout, view: View) = self.children[2] = view
proc `bottom=`*(self: MainLayout, view: View) = self.children[3] = view
proc `center=`*(self: MainLayout, view: View) = self.children[4] = view

proc leftTemplate*(self: MainLayout): Layout = self.childTemplates[0]
proc rightTemplate*(self: MainLayout): Layout = self.childTemplates[1]
proc topTemplate*(self: MainLayout): Layout = self.childTemplates[2]
proc bottomTemplate*(self: MainLayout): Layout = self.childTemplates[3]
proc centerTemplate*(self: MainLayout): Layout = self.childTemplates[4]
proc `leftTemplate=`*(self: MainLayout, layout: Layout) = self.childTemplates[0] = layout
proc `rightTemplate=`*(self: MainLayout, layout: Layout) = self.childTemplates[1] = layout
proc `topTemplate=`*(self: MainLayout, layout: Layout) = self.childTemplates[2] = layout
proc `bottomTemplate=`*(self: MainLayout, layout: Layout) = self.childTemplates[3] = layout
proc `centerTemplate=`*(self: MainLayout, layout: Layout) = self.childTemplates[4] = layout

method getView*(self: Layout, path: string): View {.base.} =
  let (slot, subPath) = path.extractSlot
  case slot
  of "":
    return self

  of "**":
    if self.children.len > 0:
      let c = self.children[self.activeIndex]
      if c of Layout:
        return c.Layout.getView(slot)
      # Don't return c here becauses for ** we want to return a layout, not a non-layout view
    return self

  of "*":
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

method getView*(self: MainLayout, path: string): View =
  let (slot, subPath) = path.extractSlot
  case slot
  of "": return self
  of "**":
    let c = self.children[self.activeIndex]
    if c != nil and c of Layout:
      return c.Layout.getView(slot)
    # Don't return c here becauses for ** we want to return a layout, not a non-layout view
    return self
  of "*": result = self.children[self.activeIndex]
  of "center": result = self.center
  of "left": result = self.left
  of "right": result = self.right
  of "top": result = self.top
  of "bottom": result = self.bottom
  else: return nil
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
method desc*(self: MainLayout): string = "MainLayout"
method desc*(self: HorizontalLayout): string = "HorizontalLayout"
method desc*(self: VerticalLayout): string = "VerticalLayout"
method desc*(self: AlternatingLayout): string = "AlternatingLayout"
method desc*(self: TabLayout): string = "TabLayout"

method kind*(self: View): string {.base.} = ""
method kind*(self: MainLayout): string = "main"
method kind*(self: HorizontalLayout): string = "horizontal"
method kind*(self: VerticalLayout): string = "vertical"
method kind*(self: AlternatingLayout): string = "alternating"
method kind*(self: TabLayout): string = "tab"

method copy*(self: Layout): Layout {.base.} = assert(false)
method copy*(self: MainLayout): Layout =
  MainLayout(
    children: self.children.mapIt(if it != nil: it.Layout.copy.View else: nil),
    childTemplates: self.childTemplates.mapIt(if it != nil: it.copy else: nil),
  )

method copy*(self: HorizontalLayout): Layout =
  HorizontalLayout(children: self.children.mapIt(if it != nil: it.Layout.copy.View else: nil))

method copy*(self: VerticalLayout): Layout =
  VerticalLayout(children: self.children.mapIt(if it != nil: it.Layout.copy.View else: nil))

method copy*(self: AlternatingLayout): Layout =
  AlternatingLayout(children: self.children.mapIt(if it != nil: it.Layout.copy.View else: nil))

method copy*(self: TabLayout): Layout =
  TabLayout(children: self.children.mapIt(if it != nil: it.Layout.copy.View else: nil))


method display*(self: View): string {.base.} = ""

method numLeafViews*(self: Layout): int {.base.} =
  for c in self.children:
    if c != nil:
      if c of Layout:
        result += c.Layout.numLeafViews()
      else:
        inc result

method activeLeafView*(self: View): View {.base.} = self
method activeLeafView*(self: Layout): View =
  if self.activeIndex in 0..self.children.high and self.children[self.activeIndex] != nil:
    return self.children[self.activeIndex].activeLeafView()

method removeView*(self: Layout, view: View): bool {.base.} =
  debugf"{self.desc}.removeView {view.desc}"
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

method removeView*(self: MainLayout, view: View): bool =
  debugf"{self.desc}.removeView {view.desc}"
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

method saveLayout*(self: View): JsonNode {.base.} = nil
method saveLayout*(self: Layout): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  var children = newJArray()
  for i, c in self.children:
    if c == nil:
      children.add newJNull()
    else:
      let saved = c.saveLayout()
      if saved != nil:
        children.add saved

  result["activeIndex"] = self.activeIndex.toJson
  result["children"] = children

method saveLayout*(self: MainLayout): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  var children = newJArray()
  for i, c in self.children:
    if c == nil:
      children.add newJNull()
    else:
      let saved = c.saveLayout()
      if saved != nil:
        children.add saved
      else:
        children.add newJNull()

  result["activeIndex"] = self.activeIndex.toJson
  result["children"] = children

method leftLeaf*(self: View): View {.base.} = self
method rightLeaf*(self: View): View {.base.} = self
method topLeaf*(self: View): View {.base.} = self
method bottomLeaf*(self: View): View {.base.} = self

method leftLeaf*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].leftLeaf()

method leftLeaf*(self: VerticalLayout): View =
  if self.children.len > 0:
    return self.children[0].leftLeaf()

method leftLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[0].leftLeaf()

method leftLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    return self.children[0].leftLeaf()

method leftLeaf*(self: MainLayout): View =
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
    return self.children[0].rightLeaf()

method rightLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children.last.rightLeaf()

method rightLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.activeIndex mod 2 != 0:
      return self.children[self.activeIndex].rightLeaf()
    return self.children.last.rightLeaf()

method rightLeaf*(self: MainLayout): View =
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
    return self.children[0].topLeaf()

method topLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[0].topLeaf()

method topLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.activeIndex <= 1:
      return self.children[self.activeIndex].topLeaf()
    return self.children[0].topLeaf()

method topLeaf*(self: MainLayout): View =
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
    return self.children.last.bottomLeaf()

method bottomLeaf*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children.last.bottomLeaf()

method bottomLeaf*(self: AlternatingLayout): View =
  if self.children.len > 0:
    if self.activeIndex mod 2 == 0:
      return self.children[self.activeIndex].bottomLeaf()
    return self.children.last.bottomLeaf()

method bottomLeaf*(self: MainLayout): View =
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
    if result != nil:
      return
  if self.activeIndex > 0:
    return self.children[self.activeIndex - 1].rightLeaf

method tryGetViewLeft*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewLeft()
    if result != nil:
      return
  if self.activeIndex > 0:
    if self.activeIndex mod 2 == 0:
      return self.children[self.activeIndex - 2].rightLeaf
    else:
      return self.children[self.activeIndex - 1].rightLeaf

method tryGetViewLeft*(self: MainLayout): View =
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
    if result != nil:
      return
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].leftLeaf

method tryGetViewRight*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewRight()
    if result != nil:
      return
  if self.activeIndex mod 2 != 0:
    return nil
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].leftLeaf

method tryGetViewRight*(self: MainLayout): View =
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
    if result != nil:
      return
  if self.activeIndex > 0:
    return self.children[self.activeIndex - 1].bottomLeaf

method tryGetViewUp*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewUp()

method tryGetViewUp*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewUp()
    if result != nil:
      return
  if self.activeIndex <= 1:
    return nil
  if self.activeIndex mod 2 == 0:
    return self.children[self.activeIndex - 1].bottomLeaf
  if self.activeIndex > 0:
    return self.children[self.activeIndex - 2].bottomLeaf

method tryGetViewUp*(self: MainLayout): View =
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
    if result != nil:
      return
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].topLeaf

method tryGetViewDown*(self: HorizontalLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewDown()

method tryGetViewDown*(self: AlternatingLayout): View =
  if self.children.len > 0:
    result = self.children[self.activeIndex].tryGetViewDown()
    if result != nil:
      return
  if self.activeIndex mod 2 == 0:
    return nil
  if self.activeIndex < self.children.high:
    return self.children[self.activeIndex + 1].topLeaf

method tryGetViewDown*(self: MainLayout): View =
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

method tryGetViewDown*(self: TabLayout): View =
  if self.children.len > 0:
    return self.children[self.activeIndex].tryGetViewDown()

method addView*(self: Layout, view: View, path: string = "", focus: bool = true): View {.base.} =
  debugf"{self.desc}.addView {view.desc()} to slot '{path}', focus = {focus}"
  let (slot, subPath) = path.extractSlot
  case slot
  of "+":
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
  of "", "*":
    if self.children.len > 0:
      if self.children[self.activeIndex] != nil and self.children[self.activeIndex] of Layout:
        return self.children[self.activeIndex].Layout.addView(view, subPath, focus)
      else:
        result = self.children[self.activeIndex]
        self.children[self.activeIndex] = view
    else:
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

method addView*(self: MainLayout, view: View, path: string = "", focus: bool = true): View =
  debugf"MainLayout.addView {view.desc()} to slot '{path}', focus = {focus}"
  var index = 4
  let (slot, subPath) = path.extractSlot
  case slot
  of "", "*": index = self.activeIndex
  of "left": index = 0
  of "right": index = 1
  of "top": index = 2
  of "bottom": index = 3
  of "center": index = 4

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
