import std/[os]
import vmath, bumpy, chroma
import ui/[node, widget_library]
import service, platform_service
import theme

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
