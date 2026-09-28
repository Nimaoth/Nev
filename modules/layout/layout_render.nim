import std/[os]
import vmath, bumpy, chroma
import ui/[node, widget_library]
import service, platform
import theme
from nuigi import UiBuilder, UiStyleIndex, UiTextStyleIndex, layoutVertical, layoutHorizontal, fillX, fillY, fitY, fit, fillBackground, styleIndex, text, textStyleIndex, node, gap, padding, anchors, finishAnchors, debugName
import nuigi/core/vecmath as nuiVecMath

when not defined(nimony):
  proc forceNim2ToIncludeUiBuilderInTheGeneratedCFile3*(): UiBuilder {.exportc.} = UiBuilder()

proc renderHorizontalLayout(self: View, builder: UINodeBuilder): seq[OverlayFunction] =
  let self = self.HorizontalLayout
  self.resetDirty()

  builder.panel(&{FillX, FillY}, tag = "horizontal"):
    if self.children.len == 0:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))
      return

    if self.maximize:
      builder.panel(&{FillX, FillY}):
        result.add self.children[self.activeIndex].createUI(builder)
      return

    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = rect.splitV(ratio.percent)
      rect = remaining
      rects.add view_rect

    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
    let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

    for i, c in self.children:
      var xy = (rects[i].xy * builder.currentParent.bounds.wh).floor()
      if i > 0:
        builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x, y = -1, w = 1, h = builder.currentParent.bounds.h + 2, border = border(1, 0, 0, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
        builder.currentChild.markDirty(builder)
        xy.x += 1

      let xwyh = (rects[i].xwyh * builder.currentParent.bounds.wh).floor()
      let bounds = rect(xy, xwyh - xy)

      if c != nil:
        builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "hori-slot"):
          if bounds.w > 0 and bounds.h > 0:
            result.add c.createUI(builder)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

proc renderVerticalLayout(self: View, builder: UINodeBuilder): seq[OverlayFunction] =
  let self = self.VerticalLayout
  self.resetDirty()

  builder.panel(&{FillX, FillY}, tag = "vertical"):

    if self.children.len == 0:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))
      return

    if self.maximize:
      builder.panel(&{FillX, FillY}):
        result.add self.children[self.activeIndex].createUI(builder)
      return

    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = rect.splitH(ratio.percent)
      rect = remaining
      rects.add view_rect

    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
    let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

    for i, c in self.children:
      var xy = (rects[i].xy * builder.currentParent.bounds.wh).floor()
      if i > 0:
        builder.panel(&{DrawBorder, DrawBorderTerminal}, x = -1, y = xy.y, w = builder.currentParent.bounds.w + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
        builder.currentChild.markDirty(builder)
        xy.y += 1

      let xwyh = (rects[i].xwyh * builder.currentParent.bounds.wh).floor()
      let bounds = rect(xy, xwyh - xy)

      if c != nil:
        builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "vert-slot"):
          if bounds.w > 0 and bounds.h > 0:
            result.add c.createUI(builder)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

proc renderAlternatingLayout(self: View, builder: UINodeBuilder): seq[OverlayFunction] =
  let self = self.AlternatingLayout
  self.resetDirty()
  if self.children.len == 0:
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))
    return

  if self.maximize:
    builder.panel(&{FillX, FillY}):
      result.add self.children[self.activeIndex].createUI(builder)
    return

  var rects = newSeq[Rect]()
  var rect = rect(0, 0, 1, 1)
  for i, c in self.children:
    let ratio = if i == 0 and self.children.len > 1:
      self.getSplitRatio(i)
    elif i == self.children.len - 1:
      1.0
    else:
      self.getSplitRatio(i)
    let (view_rect, remaining) = if i mod 2 == 0:
      rect.splitV(ratio.percent)
    else:
      rect.splitH(ratio.percent)
    rect = remaining
    rects.add view_rect

  for i, c in self.children:
    if c != nil:
      let xy = rects[i].xy * builder.currentParent.bounds.wh
      let xwyh = rects[i].xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "alt-slot"):
        if bounds.w > 0 and bounds.h > 0:
          result.add c.createUI(builder)
    else:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

proc renderTabLayout(self: View, builder: UINodeBuilder): seq[OverlayFunction] =
  let self = self.TabLayout
  self.resetDirty()
  let activeTabColor = builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
  let inactiveTabColor = builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
  let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

  # todo
  let width = 10 # app.uiSettings.tabHeaderWidth.get()
  let hideTabBarWhenSingle = true # app.uiSettings.hideTabBarWhenSingle.get()

  let index = self.activeIndex.clamp(0, self.children.high)
  builder.panel(&{FillX, FillY, LayoutVertical}, tag = "tab"):
    # tabs
    if not hideTabBarWhenSingle or self.children.len > 1:
      builder.panel(&{FillX, LayoutHorizontal, FillBackground}, h = builder.textHeight, backgroundColor = inactiveTabColor):
        builder.panel(&{SizeToContentX, FillY, DrawText}, text = "| ", textColor = textColor)
        for i, c in self.children:
          let i = i
          if i > 0:
            builder.panel(&{SizeToContentX, FillY, DrawText}, text = " | ", textColor = textColor)

          let backgroundColor = if i == index:
            activeTabColor
          else:
            inactiveTabColor

          builder.panel(&{SizeToContentX, FillY, LayoutHorizontal, FillBackground}, backgroundColor = backgroundColor):
            capture i:
              onClickAny btn:
                self.activeIndex = i
                getServiceChecked(PlatformService).platform.requestRender(true)

            let leaf = c.activeLeafView()
            let desc = if leaf != nil:
              leaf.display()
            else:
              "-"

            let headLen = desc.splitPath.head.len
            var highlightIndices = newSeq[int]()
            for i in (headLen + 1)..desc.high:
              highlightIndices.add(i)
            discard builder.highlightedText(desc, highlightIndices, textColor.darken(0.2), textColor, width)

        builder.panel(&{SizeToContentX, FillY, DrawText}, text = " |", textColor = textColor)

      let w = currentNode.w
      builder.panel(&{DrawBorder, DrawBorderTerminal}, x = -1, w = w + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")

    builder.panel(&{FillX, FillY, MaskContent}, tag = "tab-slot"):
      if index in 0..self.children.high:
        result.add self.children[index].createUI(builder)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

proc renderCenterLayout(self: View, builder: UINodeBuilder): seq[OverlayFunction] =
  let self = self.CenterLayout
  self.resetDirty()

  var rects: array[5, Rect]
  var remaining = rect(0, 0, 1, 1)
  if self.left != nil:
    (rects[0], remaining) = remaining.splitV(self.splitRatios[0].percent)
  if self.right != nil:
    (remaining, rects[1]) = remaining.splitV(self.splitRatios[1].percent)
  if self.top != nil:
    (rects[2], remaining) = remaining.splitH(self.splitRatios[2].percent)
  if self.bottom != nil:
    (remaining, rects[3]) = remaining.splitH(self.splitRatios[3].percent)

  rects[4] = remaining

  let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
  let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

  builder.panel(&{FillX, FillY}, tag = "center"):
    for i, c in self.children:
      if c != nil:
        var xy = (rects[i].xy * builder.currentParent.bounds.wh).floor()
        var xwyh = (rects[i].xwyh * builder.currentParent.bounds.wh).floor()
        if i == 0:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xwyh.x - 1, y = -1, w = 1, h = builder.currentParent.bounds.h + 1, border = border(1, 0, 0, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xwyh.x -= 1
        elif i == 1:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x, y = -1, w = 1, h = builder.currentParent.bounds.h + 1, border = border(1, 0, 0, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xy.x += 1
        elif i == 2:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x - 1, y = xwyh.y - 1, w = xwyh.x - xy.x + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xwyh.y -= 1
        elif i == 3:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x - 1, y = xy.y, w = xwyh.x - xy.x + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xy.y += 1

        let bounds = rect(xy, xwyh - xy)
        builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "center-slot"):
          if bounds.w > 0 and bounds.h > 0:
            result.add c.createUI(builder)

    if self.center == nil:
      let xy = remaining.xy * builder.currentParent.bounds.wh
      let xwyh = remaining.xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(&{FillBackground}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = color(0, 0, 0))

proc renderHorizontalLayoutNui(self: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    let self = self.HorizontalLayout
    self.resetDirty()
    if self.children.len == 0:
      nui.node:
        nui.debugName("horizontal-layout")
        discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel)
      return
    if self.maximize:
      nui.node:
        nui.debugName("horizontal-layout")
        discard nui.fillX().fillY()
        self.children[self.activeIndex].render(nui)
      return
    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = rect.splitV(ratio.percent)
      rect = remaining
      rects.add view_rect
    nui.node:
      nui.debugName("horizontal-layout")
      discard nui.fillX().fillY()
      for i, c in self.children:
        let r = rects[i]
        # NUI-GAP: old H layout drew 1px separators (DrawBorder border(1,0,0,0),
        # panel.border/editor.background colors) with markDirty hit-slots, xy.x+=1
        # offset and floor(parent.bounds) pixel snap; dropped here (see §24).
        # NUI-GAP: old culled slots with bounds.w>0 and bounds.h>0; unconditional here.
        if c != nil:
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).padding(0).finishAnchors()
            c.render(nui)
        else:
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).finishAnchors()

proc renderVerticalLayoutNui(self: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    let self = self.VerticalLayout
    self.resetDirty()
    if self.children.len == 0:
      nui.node:
        nui.debugName("vertical-layout")
        discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel)
      return
    if self.maximize:
      nui.node:
        nui.debugName("vertical-layout")
        discard nui.fillX().fillY()
        self.children[self.activeIndex].render(nui)
      return
    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = rect.splitH(ratio.percent)
      rect = remaining
      rects.add view_rect
    nui.node:
      nui.debugName("vertical-layout")
      discard nui.fillX().fillY()
      for i, c in self.children:
        let r = rects[i]
        # NUI-GAP: old V layout drew 1px separators (DrawBorder border(0,0,1,0))
        # with markDirty hit-slots, xy.y+=1 offset and pixel snap; dropped (see §24).
        # NUI-GAP: old culled slots with bounds.w>0 and bounds.h>0; unconditional here.
        if c != nil:
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).padding(0).finishAnchors()
            c.render(nui)
        else:
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).finishAnchors()

proc renderAlternatingLayoutNui(self: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    let self = self.AlternatingLayout
    self.resetDirty()
    if self.children.len == 0:
      nui.node:
        discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel)
      return
    if self.maximize:
      nui.node:
        discard nui.fillX().fillY()
        self.children[self.activeIndex].render(nui)
      return
    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = if i mod 2 == 0:
        rect.splitV(ratio.percent)
      else:
        rect.splitH(ratio.percent)
      rect = remaining
      rects.add view_rect
    nui.node:
      discard nui.fillX().fillY()
      for i, c in self.children:
        let r = rects[i]
        # NUI-GAP: old alt slots used explicit x,y,w,h alt-slot panels with a
        # bounds.w>0 and bounds.h>0 guard; guard dropped here (see §24).
        if c != nil:
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).padding(0).finishAnchors()
            c.render(nui)
        else:
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).finishAnchors()

proc renderTabLayoutNui(self: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    let self = self.TabLayout
    self.resetDirty()
    let hideTabBarWhenSingle = true
    let idx = self.activeIndex.clamp(0, self.children.high)
    nui.layoutVertical("tab-" & $self.mId):
      discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel).gap(4)
      if not hideTabBarWhenSingle or self.children.len > 1:
        nui.layoutHorizontal("tab-bar"):
          discard nui.fillX().fitY().fillBackground().styleIndex(UiStyleIndexHeader).gap(4).padding(4)
          # NUI-GAP (tab bar, see §24): old had onClickAny (activeIndex=i +
          # requestRender) so tabs were switchable; highlightedText with
          # splitPath.head highlightIndices (darken 0.2, width 10);
          # tab.activeBackground/inactiveBackground FillBackground switch;
          # "| "/" | "/" |" separators + 1px DrawBorder below bar; centered
          # activeLeafView().display() label ("-" fallback); FillX/FillY
          # MaskContent tab-slot clipping; theme colors. New is text-only and
          # not clickable; c.display() also skips the activeLeafView() lookup.
          for i, c in self.children:
            if c != nil:
              let isActive = i == idx
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(if isActive: "[" & c.display() & "]" else: c.display())
      nui.node:
        discard nui.fillX().fillY()
        if idx in 0..self.children.high and self.children[idx] != nil:
          self.children[idx].render(nui)
        else:
          discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel)

proc renderCenterLayoutNui(self: View, nui: var UiBuilder) {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    let self = self.CenterLayout
    self.resetDirty()
    if self.children.len != 5:
      nui.node:
        nui.debugName("center-layout")
        discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel)
      return
    var rects: array[5, Rect]
    var remaining = rect(0, 0, 1, 1)
    if self.left != nil:
      (rects[0], remaining) = remaining.splitV(self.splitRatios[0].percent)
    if self.right != nil:
      (remaining, rects[1]) = remaining.splitV(self.splitRatios[1].percent)
    if self.top != nil:
      (rects[2], remaining) = remaining.splitH(self.splitRatios[2].percent)
    if self.bottom != nil:
      (remaining, rects[3]) = remaining.splitH(self.splitRatios[3].percent)
    rects[4] = remaining
    nui.node:
      nui.debugName("center-layout")
      discard nui.fillX().fillY()
      # NUI-GAP: old center regions drew DrawBorder separators (left/right
      # border(1,0,0,0), top/bottom border(0,0,1,0)) with markDirty hit-slots and
      # xy/xwyh ±1 adjustments, plus a bounds.w>0 and bounds.h>0 guard; all
      # dropped here (see §24).
      for i, c in self.children:
        if c != nil:
          let r = rects[i]
          nui.node:
            discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).padding(0).finishAnchors()
            c.render(nui)
      if self.center == nil:
        let r = rects[4]
        nui.node:
          discard nui.anchors(nuiVecMath.vec2(r.x.float32, r.y.float32), nuiVecMath.vec2((r.x + r.w).float32, (r.y + r.h).float32)).fillBackground().styleIndex(UiStyleIndexPanel).finishAnchors()
