import std/[os, math]
import vmath, bumpy, chroma
import service, platform
import theme
import nuigi
import nuigi/core/vecmath as nuiVecMath

when not defined(nimony):
  proc forceNim2ToIncludeUiBuilderInTheGeneratedCFile3*(): UiBuilder {.exportc.} = UiBuilder()

const SplitterHandleWidth = 2.0'f32

proc splitGap(areaExtent: float, pixelExtent, requestedWidth: float32): float32 =
  min(max(areaExtent.float32 * pixelExtent, 0.0'f32), requestedWidth)

proc splitterCenter(boundary: float, gap, pixelExtent: float32): float =
  if pixelExtent > 0:
    return boundary + gap / (2.0'f32 * pixelExtent)
  boundary

proc splitVAligned(area: Rect, ratio: float, pixelWidth: float32,
    handleWidth = 0.0'f32): tuple[first, remaining: Rect] =
  (result.first, result.remaining) = area.splitV(ratio.percent)
  if pixelWidth > 0:
    let totalPixels = max(area.w.float32 * pixelWidth, 0.0'f32)
    let gapPixels = min(totalPixels, handleWidth)
    let firstPixels = round((totalPixels - gapPixels) * ratio.float32)
    result.first.w = firstPixels / pixelWidth
    result.remaining.x = area.x + (firstPixels + gapPixels) / pixelWidth
    result.remaining.w = (totalPixels - firstPixels - gapPixels) / pixelWidth

proc splitHAligned(area: Rect, ratio: float, pixelHeight: float32,
    handleWidth = 0.0'f32): tuple[first, remaining: Rect] =
  (result.first, result.remaining) = area.splitH(ratio.percent)
  if pixelHeight > 0:
    let totalPixels = max(area.h.float32 * pixelHeight, 0.0'f32)
    let gapPixels = min(totalPixels, handleWidth)
    let firstPixels = round((totalPixels - gapPixels) * ratio.float32)
    result.first.h = firstPixels / pixelHeight
    result.remaining.y = area.y + (firstPixels + gapPixels) / pixelHeight
    result.remaining.h = (totalPixels - firstPixels - gapPixels) / pixelHeight

proc previousLayoutSize(nui: var UiBuilder): nuiVecMath.Vec2 =
  let previousIndex = nui.previousNodeIndex(nui.currentNode.id, nui.currentNodeIndex)
  if previousIndex >= 0:
    let size = nui.previousFrame.nodes[previousIndex].size
    return nuiVecMath.vec2(size.x, size.y)
  nui.frameCtx.viewportSize

proc buildSplitHandle(nui: var UiBuilder, key: string, boundary: float,
    verticalDivider: bool, layoutExtent, ratioExtent: float32): float =
  if layoutExtent <= 0:
    return 0
  var delta = 0.0
  let handleStart = max(0.0'f32, boundary.float32 * layoutExtent - 1.0'f32)
  let handleEnd = min(layoutExtent, boundary.float32 * layoutExtent + 1.0'f32)
  let topLeft = if verticalDivider:
    nuiVecMath.vec2(handleStart / layoutExtent, 0.0'f32)
  else:
    nuiVecMath.vec2(0.0'f32, handleStart / layoutExtent)
  let bottomRight = if verticalDivider:
    nuiVecMath.vec2(handleEnd / layoutExtent, 1.0'f32)
  else:
    nuiVecMath.vec2(1.0'f32, handleEnd / layoutExtent)
  nui.node(key):
    var hovered = false
    var held = false
    nui.node("splitter-drag-hit"):
      discard nui.ignoreInContentExtent()
      let leftOffset = if verticalDivider: -1.0'f32 else: 0.0'f32
      let topOffset = if verticalDivider: 0.0'f32 else: -1.0'f32
      let rightOffset = if verticalDivider: 1.0'f32 else: 0.0'f32
      let bottomOffset = if verticalDivider: 0.0'f32 else: 1.0'f32
      discard nui.anchors(0, 0, 1, 1)
        .offsets(leftOffset, topOffset, rightOffset, bottomOffset).finishAnchors()
      hovered = nui.wasHovered()
      held = MouseLeft in nui.frameCtx.input.mouseDown and
        nui.previousOutput.heldId == nui.currentNode.id
      let pressed = MouseLeft in nui.frameCtx.input.mousePressed and hovered
      if (pressed or held) and ratioExtent > 0:
        let pointerDelta = if verticalDivider: nui.frameCtx.input.mouseDelta.x else: nui.frameCtx.input.mouseDelta.y
        delta = pointerDelta / ratioExtent
    discard nui.anchors(topLeft, bottomRight).fillBackground()
      .styleIndex(if hovered or held: UiStyleIndexAccent else: UiStyleIndexHeader)
      .padding(0).finishAnchors()
  delta

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
    nui.node:
      nui.debugName("horizontal-layout")
      discard nui.fillX().fillY()
      let layoutSize = nui.previousLayoutSize()
      var rects = newSeq[Rect]()
      var splitExtents = newSeq[float32]()
      var splitGaps = newSeq[float32]()
      var rect = rect(0, 0, 1, 1)
      for i, c in self.children:
        let handleWidth = if i == self.children.high: 0.0'f32 else: SplitterHandleWidth
        let ratio = if i == self.children.high: 1.0 else: self.getSplitRatio(i)
        let gap = splitGap(rect.w, layoutSize.x, handleWidth)
        splitExtents.add max(rect.w.float32 * layoutSize.x - gap, 0.0'f32)
        splitGaps.add gap
        let (viewRect, remaining) = splitVAligned(rect, ratio, layoutSize.x, handleWidth)
        rect = remaining
        rects.add viewRect
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
      for i in 0 ..< self.children.high:
        let boundary = splitterCenter(rects[i].x + rects[i].w, splitGaps[i], layoutSize.x)
        let delta = nui.buildSplitHandle("horizontal-splitter-" & $i, boundary,
          true, layoutSize.x, splitExtents[i])
        if delta != 0:
          self.setSplitRatio(i, self.getSplitRatio(i) + delta)

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
    nui.node:
      nui.debugName("vertical-layout")
      discard nui.fillX().fillY()
      let layoutSize = nui.previousLayoutSize()
      var rects = newSeq[Rect]()
      var splitExtents = newSeq[float32]()
      var splitGaps = newSeq[float32]()
      var rect = rect(0, 0, 1, 1)
      for i, c in self.children:
        let handleWidth = if i == self.children.high: 0.0'f32 else: SplitterHandleWidth
        let ratio = if i == self.children.high: 1.0 else: self.getSplitRatio(i)
        let gap = splitGap(rect.h, layoutSize.y, handleWidth)
        splitExtents.add max(rect.h.float32 * layoutSize.y - gap, 0.0'f32)
        splitGaps.add gap
        let (viewRect, remaining) = splitHAligned(rect, ratio, layoutSize.y, handleWidth)
        rect = remaining
        rects.add viewRect
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
      for i in 0 ..< self.children.high:
        let boundary = splitterCenter(rects[i].y + rects[i].h, splitGaps[i], layoutSize.y)
        let delta = nui.buildSplitHandle("vertical-splitter-" & $i, boundary,
          false, layoutSize.y, splitExtents[i])
        if delta != 0:
          self.setSplitRatio(i, self.getSplitRatio(i) + delta)

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
    nui.node:
      discard nui.fillX().fillY()
      let layoutSize = nui.previousLayoutSize()
      var rects = newSeq[Rect]()
      var rect = rect(0, 0, 1, 1)
      for i, c in self.children:
        let ratio = if i == self.children.high: 1.0 else: self.getSplitRatio(i)
        let (viewRect, remaining) = if i mod 2 == 0:
          splitVAligned(rect, ratio, layoutSize.x)
        else:
          splitHAligned(rect, ratio, layoutSize.y)
        rect = remaining
        rects.add viewRect
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
      discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel).backendGap(4).backendPadding(0)
      if not hideTabBarWhenSingle or self.children.len > 1:
        nui.layoutHorizontal("tab-bar"):
          discard nui.fillX().fitY().fillBackground().styleIndex(UiStyleIndexHeader).backendGap(4).backendPadding(4)
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
    nui.node:
      nui.debugName("center-layout")
      discard nui.fillX().fillY()
      let layoutSize = nui.previousLayoutSize()
      var rects: array[5, Rect]
      var remaining = rect(0, 0, 1, 1)
      var leftGap = 0.0'f32
      var rightGap = 0.0'f32
      var topGap = 0.0'f32
      var bottomGap = 0.0'f32
      var leftRatioExtent = layoutSize.x
      var rightRatioExtent = layoutSize.x
      var topRatioExtent = layoutSize.y
      var bottomRatioExtent = layoutSize.y
      if self.left != nil:
        leftGap = splitGap(remaining.w, layoutSize.x, SplitterHandleWidth)
        leftRatioExtent = remaining.w.float32 * layoutSize.x - leftGap
        (rects[0], remaining) = splitVAligned(remaining, self.splitRatios[0], layoutSize.x, SplitterHandleWidth)
      if self.right != nil:
        rightGap = splitGap(remaining.w, layoutSize.x, SplitterHandleWidth)
        rightRatioExtent = remaining.w.float32 * layoutSize.x - rightGap
        let (centerPart, rightPart) = splitVAligned(remaining, self.splitRatios[1], layoutSize.x, SplitterHandleWidth)
        remaining = centerPart
        rects[1] = rightPart
      if self.top != nil:
        topGap = splitGap(remaining.h, layoutSize.y, SplitterHandleWidth)
        topRatioExtent = remaining.h.float32 * layoutSize.y - topGap
        (rects[2], remaining) = splitHAligned(remaining, self.splitRatios[2], layoutSize.y, SplitterHandleWidth)
      if self.bottom != nil:
        bottomGap = splitGap(remaining.h, layoutSize.y, SplitterHandleWidth)
        bottomRatioExtent = remaining.h.float32 * layoutSize.y - bottomGap
        let (centerPart, bottomPart) = splitHAligned(remaining, self.splitRatios[3], layoutSize.y, SplitterHandleWidth)
        remaining = centerPart
        rects[3] = bottomPart
      rects[4] = remaining
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
      if self.left != nil:
        let boundary = splitterCenter(rects[0].x + rects[0].w, leftGap, layoutSize.x)
        let delta = nui.buildSplitHandle("center-left-splitter", boundary,
          true, layoutSize.x, leftRatioExtent)
        if delta != 0:
          self.splitRatios[0] = (self.splitRatios[0] + delta).clamp(0, 1)
      if self.right != nil:
        let boundary = splitterCenter(rects[1].x, -rightGap, layoutSize.x)
        let delta = nui.buildSplitHandle("center-right-splitter", boundary,
          true, layoutSize.x, rightRatioExtent)
        if delta != 0:
          self.splitRatios[1] = (self.splitRatios[1] + delta).clamp(0, 1)
      if self.top != nil:
        let boundary = splitterCenter(rects[2].y + rects[2].h, topGap, layoutSize.y)
        let delta = nui.buildSplitHandle("center-top-splitter", boundary,
          false, layoutSize.y, topRatioExtent)
        if delta != 0:
          self.splitRatios[2] = (self.splitRatios[2] + delta).clamp(0, 1)
      if self.bottom != nil:
        let boundary = splitterCenter(rects[3].y, -bottomGap, layoutSize.y)
        let delta = nui.buildSplitHandle("center-bottom-splitter", boundary,
          false, layoutSize.y, bottomRatioExtent)
        if delta != 0:
          self.splitRatios[3] = (self.splitRatios[3] + delta).clamp(0, 1)
