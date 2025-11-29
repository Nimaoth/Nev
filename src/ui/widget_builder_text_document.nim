import std/[strformat, tables, strutils, math, options, json]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, rope_utils, timer]
import text/text_editor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, document_editor, theme, config_provider, layout
import text/language/[lsp_types]
import text/[diff, custom_treesitter, syntax_map, overlay_map, wrap_map, diff_map, display_map]

import ui/node

import nimsumtree/[buffer, rope]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

{.push gcsafe.}
{.push raises: [].}
{.push stacktrace:off.}
{.push linetrace:off.}

logCategory "widget_builder_text"

type CursorLocationInfo* = tuple[node: UINode, text: string, bounds: Rect, original: Cursor]

type
  ChunkBounds = object
    range: rope.Range[Point]
    displayRange: rope.Range[DisplayPoint]
    bounds: Rect
    text: RopeChunk
    chunk: DisplayChunk
    charsRange: rope.Range[int]

  LineDrawerResult = enum Continue, ContinueNextLine, Break
  LineDrawerState = object
    builder: UINodeBuilder
    displayMap: DisplayMap
    offset: Vec2
    bounds: Rect
    lastDisplayPoint: DisplayPoint
    lastDisplayEndPoint: DisplayPoint
    lastPoint: Point
    cursorOnScreen: bool
    charBounds: seq[Rect]
    chunkBounds: seq[ChunkBounds]
    addedLineNumber: bool = false
    backgroundColor: Option[Color]
    lineNumberBackgroundColor: Color
    fillLineNumberBackground: bool
    reverse: bool

proc cmp(r: ChunkBounds, point: Point): int =
  let range = if r.chunk.styledChunk.chunk.external:
    # r.range.a...r.range.a
    r.chunk.point...(r.chunk.point + point(0, r.chunk.styledChunk.chunk.lenOriginal))
  else:
    r.chunk.point...(r.chunk.point + point(0, r.chunk.styledChunk.chunk.lenOriginal))

  if range.a.row > point.row:
    return 1
  if point.row == range.a.row and range.a.column > point.column:
    return 1
  if range.b.row < point.row:
    return -1
  if point.row == range.b.row and range.b.column < point.column:
    return -1
  return 0

proc cmp(r: ChunkBounds, point: DisplayPoint): int =
  if r.displayRange.a.row > point.row:
    return 1
  if point.row == r.displayRange.a.row and r.displayRange.a.column > point.column:
    return 1
  if r.displayRange.b.row < point.row:
    return -1
  if point.row == r.displayRange.b.row and r.displayRange.b.column < point.column:
    return -1
  return 0

proc cmp(r: Rect, point: Vec2): int =
  if r.y > point.y:
    return 1
  if r.yh <= point.y:
    return -1
  if r.x > point.x:
    return 1
  if r.xw <= point.x:
    return -1
  return 0

proc cmp(r: ChunkBounds, point: Vec2): int =
  return cmp(r.bounds, point)

proc `*`(c: Color, v: Color): Color {.inline.} =
  ## Multiply color by a value.
  result.r = c.r * v.r
  result.g = c.g * v.g
  result.b = c.b * v.b
  result.a = c.a * v.a

proc getCursorPos2(self: TextDocumentEditor, builder: UINodeBuilder, text: openArray[char], pos: Vec2): int =
  ## Calculates the byte index in the original line at the given pos (relative to the parts top left corner)

  let runeLen = text.runeLen

  var offset = 0.0
  var i = 0
  var byteIndex = 0
  # defer:
  #   echo &"{pos} -> {byteIndex}, '{text}'"
  for r in text.runes:
    let w = builder.textWidth($r).round
    let posX = if self.isThickCursor(): pos.x else: pos.x + w * 0.5

    if posX < offset + w:
      if i.RuneCount >= runeLen:
        return 0
      return byteIndex

    offset += w
    inc i
    byteIndex += r.size

  byteIndex

proc createHover(self: TextDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let backgroundColor = app.themes.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = app.themes.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
  let docsColor = app.themes.theme.color("editor.foreground", color(1, 1, 1))

  let numLinesToShow = min(10, self.hoverText.countLines)
  let (top, bottom) = (
    cursorBounds.yh.float - floor(builder.charWidth * 0.5),
    cursorBounds.yh.float + totalLineHeight * numLinesToShow.float - floor(builder.charWidth * 0.5))
  let height = bottom - top

  const docsWidth = 50.0
  let totalWidth = charWidth * docsWidth
  var clampedX = cursorBounds.x
  if clampedX + totalWidth > builder.root.w:
    clampedX = max(builder.root.w - totalWidth, 0)

  let border = ceil(builder.charWidth * 0.5)

  var hoverPanel: UINode = nil
  builder.panel(&{SizeToContentX, MaskContent, FillBackground, DrawBorder, DrawBorderTerminal, MouseHover, SnapInitialBounds}, x = clampedX, y = top, h = height + border * 2, pivot = vec2(0, 0), backgroundColor = backgroundColor, borderColor = borderColor, userId = self.hoverId.newPrimaryId):
    hoverPanel = currentNode

    var textNode: UINode = nil
    builder.panel(&{SizeToContentX}, x = border, y = border, w = 0, h = height):
      # todo: height
      builder.panel(&{DrawText, SizeToContentX}, x = 0, y = self.hoverScrollOffset, w = 0, h = 1000, text = self.hoverText, textColor = docsColor):
        textNode = currentNode

    currentNode.w = currentNode.w + border

    onScroll:
      let scrollSpeed = self.config.get("text.hover-scroll-speed", 20.0)
      # todo: clamp bottom
      self.hoverScrollOffset = clamp(self.hoverScrollOffset + delta.y * scrollSpeed, -1000, 0)
      self.markDirty()

    onBeginHover:
      self.cancelDelayedHideHover()

    onEndHover:
      self.hideHoverDelayed()

  hoverPanel.rawY = cursorBounds.y
  hoverPanel.pivot = vec2(0, 1)

proc createCompletions(self: TextDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let transparentBackground = self.uiSettings.background.transparent.get()
  var backgroundColor = app.themes.theme.color(@["editorSuggestWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = app.themes.theme.color(@["editorSuggestWidget.border", "panel.background"], color(30/255, 30/255, 30/255))
  let selectedBackgroundColor = app.themes.theme.color(@["editorSuggestWidget.selectedBackground", "list.activeSelectionBackground"], color(200/255, 200/255, 200/255))
  let docsColor = app.themes.theme.color(@["editorSuggestWidget.foreground", "editor.foreground"], color(1, 1, 1))
  let nameColor = app.themes.theme.color(@["editorSuggestWidget.foreground", "editor.foreground"], color(1, 1, 1))
  let nameSelectedColor = app.themes.theme.color(@["editorSuggestWidget.highlightForeground", "editor.foreground"], color(1, 1, 1))
  let scopeColor = app.themes.theme.color(@["descriptionForeground", "editor.foreground"], color(175/255, 1, 175/255))

  if transparentBackground:
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  const numLinesToShow = 25
  let completionPanelHeight = min(self.completionMatches.len, numLinesToShow).float * totalLineHeight
  let (top, bottom) = (cursorBounds.yh.float, cursorBounds.yh.float + totalLineHeight * numLinesToShow)

  const docsWidth = 75.0
  const maxLabelLen = 30
  const maxTypeLen = 30
  updateBaseIndexAndScrollOffset(bottom - top, self.completionsBaseIndex, self.completionsScrollOffset, self.completionMatches.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  var rows: seq[UINode] = @[]

  var completionsPanel: UINode = nil
  builder.panel(&{SizeToContentX, SizeToContentY, MaskContent}, x = cursorBounds.x, y = top, pivot = vec2(0, 0), userId = self.completionsId.newPrimaryId):
    completionsPanel = currentNode
    let reverse = top + completionPanelHeight > completionsPanel.parent.bounds.h
    self.completionsDrawnInReverse = reverse

    proc handleScroll(delta: float) =
      let scrollAmount = delta * self.uiSettings.scrollSpeed.get()
      self.completionsScrollOffset += scrollAmount
      self.markDirty()

    var maxLabelWidth = 4 * builder.charWidth
    var maxDetailWidth = 1 * builder.charWidth
    var detailColumn: seq[UINode] = @[]

    proc handleLine(i: int, y: float) =
      var backgroundColor = backgroundColor

      if i == self.selectedCompletion:
        backgroundColor = selectedBackgroundColor

      builder.panel(&{FillBackground}, y = y, h = totalLineHeight, backgroundColor = backgroundColor):
        rows.add currentNode

        let completion {.cursor.} = self.completions[self.completionMatches[i].index]
        let color = if i == self.selectedCompletion: nameSelectedColor else: nameColor

        let matchIndices = self.getCompletionMatches(i)
        let label = if completion.item.label.len < maxLabelLen:
            completion.item.label
          else:
            completion.item.label[0..<(maxLabelLen - 3)] & "..."

        let labelNode = builder.highlightedText(label, matchIndices, color, color.lighten(0.15))

        maxLabelWidth = max(maxLabelWidth, labelNode.w)

        let detail = if completion.item.detail.getSome(detail):
          if detail.len < maxTypeLen:
            detail
          else:
            detail[0..<(maxTypeLen - 3)] & "..."
        else:
          ""
        let scopeText = completion.source & " " & detail
        builder.panel(&{DrawText, SizeToContentX}, x = currentNode.w, h = totalLineHeight, text = scopeText, textColor = scopeColor):
          detailColumn.add currentNode
          maxDetailWidth = max(maxDetailWidth, currentNode.w)

    var listNode: UINode
    builder.panel(&{UINodeFlag.MaskContent, DrawBorder, SizeToContentX}, borderColor = borderColor, h = completionPanelHeight):
      listNode = currentNode
      let lineFlags = &{SizeToContentX, FillY}
      let firstIndex = max(self.completionsBaseIndex - (self.completionsScrollOffset / totalLineHeight).int, 0)
      var y = if reverse: completionPanelHeight - totalLineHeight else: 0

      builder.panel(lineFlags):
        onScroll:
          handleScroll(delta.y)

        for i in firstIndex..self.completionMatches.high:
          handleLine(i, y)
          if reverse:
            y -= totalLineHeight
            if y <= -totalLineHeight:
              break
          else:
            y += totalLineHeight
            if y > completionPanelHeight:
              break

      let linesNode = currentNode.last
      let totalWidth = maxLabelWidth + maxDetailWidth + builder.charWidth
      linesNode.w = totalWidth

      # Adjust offset and width of detail nodes to align them
      for detailNode in detailColumn:
        detailNode.rawX = maxLabelWidth + builder.charWidth
        detailNode.w = maxDetailWidth
        detailNode.parent.w = totalWidth # parent is line node

    if self.selectedCompletion >= 0 and self.selectedCompletion < self.completionMatches.len:
      template selectedCompletion: untyped = self.completions[self.completionMatches[self.selectedCompletion].index]

      var docText = ""
      if selectedCompletion.item.label.len >= maxLabelLen:
        docText.add selectedCompletion.item.label
        docText.add "\n"

      if selectedCompletion.item.detail.getSome(detail):
        docText.add detail

      if selectedCompletion.item.documentation.getSome(doc):
        if docText.len > 0:
          docText.add "\n\n"
        if doc.asString().getSome(doc):
          docText.add doc
        elif doc.asMarkupContent().getSome(markup):
          docText.add markup.value

      if docText.len > 0:
        builder.panel(&{UINodeFlag.FillBackground, DrawText, MaskContent, TextWrap, DrawBorder},
          x = listNode.xw, w = docsWidth * charWidth, h = listNode.h,
          backgroundColor = backgroundColor, textColor = docsColor, text = docText, borderColor = borderColor)

  if completionsPanel.bounds.yh > completionsPanel.parent.bounds.h:
    completionsPanel.rawY = cursorBounds.y
    completionsPanel.pivot = vec2(0, 1)

  if completionsPanel.bounds.xw > completionsPanel.parent.bounds.w:
    completionsPanel.rawX = max(completionsPanel.parent.bounds.w - completionsPanel.bounds.w, 0)

proc drawHighlight(self: TextDocumentEditor, builder: UINodeBuilder, sn: Selection, color: Color, renderCommands: var RenderCommands, state: var LineDrawerState, cursor: var RopeCursorT[Point]) =

  let r = sn.first.toPoint...sn.last.toPoint

  let (_, firstIndexNormalized) = state.chunkBounds.binarySearchRange(r.a, Bias.Right, cmp)
  let (_, lastIndexNormalized) = state.chunkBounds.binarySearchRange(r.b, Bias.Right, cmp)
  if state.chunkBounds.len > 0:
    let firstIndexClamped = if firstIndexNormalized != -1:
      firstIndexNormalized
    elif r.a < state.chunkBounds[0].range.a:
      0
    elif r.a > state.chunkBounds[^1].range.b:
      state.chunkBounds.high
    else:
      -1

    let lastIndexClamped = if lastIndexNormalized != -1:
      lastIndexNormalized
    elif r.b < state.chunkBounds[0].range.a:
      0
    elif r.b > state.chunkBounds[^1].range.b:
      state.chunkBounds.high
    else:
      -1

    if firstIndexClamped != -1 and lastIndexClamped != -1:
      for i in firstIndexClamped..lastIndexClamped:
        if i >= state.chunkBounds.len:
          break

        let bounds = state.chunkBounds[i]

        let linePoint = point(bounds.range.a.row, 0)
        if cursor.position > linePoint:
          cursor.resetCursor()
        if cursor.position < linePoint or not cursor.didSeek:
          cursor.seekForward(linePoint)
          cursor.cacheOffset()

        let lineEmpty = cursor.currentChar() == '\n'
        let ropeChunk = bounds.chunk.styledChunk.chunk
        let rangeOriginal = ropeChunk.point...(ropeChunk.point + point(0, ropeChunk.lenOriginal))

        let firstOffset = if bounds.chunk.styledChunk.chunk.external and r.a.column.int < rangeOriginal.a.column.int:
          0
        elif bounds.chunk.styledChunk.chunk.external and r.a.column.int >= rangeOriginal.b.column.int:
          bounds.chunk.toOpenArray.runeLen.int
        elif lineEmpty:
          0
        elif r.a in rangeOriginal:
          bounds.chunk.styledChunk.chunk.toOpenArrayOriginal.offsetToCount(r.a.column.int - rangeOriginal.a.column.int).int
        elif r.a < rangeOriginal.a:
          0
        else:
          bounds.chunk.toOpenArray.runeLen.int

        let lastOffset = if bounds.chunk.styledChunk.chunk.external and r.b.column.int > rangeOriginal.b.column.int:
          bounds.chunk.toOpenArray.runeLen.int
        elif lineEmpty:
          1
        elif r.b in rangeOriginal:
          bounds.chunk.styledChunk.chunk.toOpenArrayOriginal.offsetToCount(r.b.column.int - rangeOriginal.a.column.int).int
        elif r.b < rangeOriginal.a:
          0
        else:
          bounds.chunk.toOpenArray.runeLen.int

        if firstOffset == lastOffset:
          continue

        var selectionBounds = rect(
          (bounds.bounds.xy + vec2(firstOffset.float * builder.charWidth, 0)),
          (vec2((lastOffset - firstOffset).float * builder.charWidth, builder.textHeight)))

        let firstIndexClamped = firstOffset.clamp(0, bounds.charsRange.len - 1)
        let lastIndexClamped = lastOffset.clamp(0, bounds.charsRange.len)
        if firstIndexClamped != -1 and lastIndexClamped != -1:
          let firstBounds = state.charBounds[bounds.charsRange.a + firstIndexClamped] + bounds.bounds.xy
          let lastBounds = state.charBounds[bounds.charsRange.a + lastIndexClamped - 1] + bounds.bounds.xy
          selectionBounds = rect(firstBounds.xy, vec2(lastBounds.xw - firstBounds.x, builder.textHeight))

        if renderCommands.commands.len > 0:
          let last = renderCommands.commands[^1].addr
          if last.kind == RenderCommandKind.FilledRect and last.bounds.y == selectionBounds.y and last.bounds.h == selectionBounds.h and abs(last.bounds.xw - selectionBounds.x) < 0.1 and last.color == color:
            last.bounds.w += selectionBounds.w
          else:
            renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: selectionBounds, color: color))
        else:
          renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: selectionBounds, color: color))

proc drawLineNumber(renderCommands: var RenderCommands, builder: UINodeBuilder, lineNumber: int, offset: Vec2, cursorLine: int, lineNumbers: LineNumbers, lineNumberBounds: Vec2, textColor: Color, backgroundColor: Color, fillBackground: bool) =
  var lineNumberText = ""
  var lineNumberX = 0.float
  if lineNumbers != LineNumbers.None and cursorLine == lineNumber:
    lineNumberText = $(lineNumber + 1)
  elif lineNumbers == LineNumbers.Absolute:
    lineNumberText = $(lineNumber + 1)
    lineNumberX = max(0.0, lineNumberBounds.x - builder.charWidth - lineNumberText.len.float * builder.charWidth)
  elif lineNumbers == LineNumbers.Relative:
    lineNumberText = $abs((lineNumber + 1) - cursorLine)
    lineNumberX = max(0.0, lineNumberBounds.x - builder.charWidth - lineNumberText.len.float * builder.charWidth)

  if lineNumberText.len > 0:
    let width = builder.textWidth(lineNumberText)
    buildCommands(renderCommands):
      if fillBackground:
        fillRect(rect(offset, lineNumberBounds), backgroundColor)
      drawText(lineNumberText, rect(offset.x + lineNumberX, offset.y, width, builder.textHeight), textColor, 0.UINodeFlags)

proc drawCursors(self: TextDocumentEditor, builder: UINodeBuilder, app: App, currentNode: UINode, renderCommands: var RenderCommands, state: var LineDrawerState) =

  let cursorForegroundColor = app.themes.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.themes.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let cursorTrailColor = cursorForegroundColor.darken(0.1)
  let cursorSpeed: float = self.uiSettings.cursorTrailSpeed.get()
  let cursorTrail: int = self.uiSettings.cursorTrailLength.get()
  let isThickCursor = self.isThickCursor

  buildCommands(renderCommands):
    self.cursorHistories.setLen(self.selections.len)
    for i, s in self.selections:
      let p = s.last.toPoint
      var (_, lastIndex) = state.chunkBounds.binarySearchRange(p, Bias.Left, cmp)

      while lastIndex in 0..<state.chunkBounds.high and p in state.chunkBounds[lastIndex + 1].range:
        inc lastIndex

      if lastIndex in 0..<state.chunkBounds.len and p in state.chunkBounds[lastIndex].range:
        let chunk = state.chunkBounds[lastIndex]
        # if chunk.chunk.styledChunk.chunk.external:
        #   continue

        let relativeOffset = p.column.int - chunk.range.a.column.int
        let runeOffset = if p.column.int == chunk.range.b.column.int:
          chunk.chunk.styledChunk.chunk.toOpenArrayOriginal.runeLen.int
        else:
          chunk.chunk.styledChunk.chunk.toOpenArrayOriginal.offsetToCount(relativeOffset).int
        var cursorBounds = rect(chunk.bounds.xy + vec2(runeOffset.float * builder.charWidth, 0), vec2(builder.charWidth, builder.textHeight))

        if chunk.range.a != chunk.range.b:
          if p.column.int == chunk.range.b.column.int and chunk.charsRange.a + runeOffset - 1 in 0..state.charBounds.high:
            cursorBounds.xy = state.charBounds[chunk.charsRange.a + runeOffset - 1].xwy + chunk.bounds.xy
          elif chunk.charsRange.a + runeOffset in 0..state.charBounds.high:
            cursorBounds = state.charBounds[chunk.charsRange.a + runeOffset] + chunk.bounds.xy
            cursorBounds.h = builder.textHeight

        let charBounds = cursorBounds
        if not isThickCursor:
          cursorBounds.w = builder.charWidth * 0.2

        var cursorVisible = self.cursorVisible
        if cursorTrail > 0:
          if self.cursorHistories[i].len != 0:
            let alpha = 1 - exp(-cursorSpeed * app.platform.deltaTime)
            var nextPos = mix(self.cursorHistories[i].last, cursorBounds.xy, alpha)
            if (nextPos - cursorBounds.xy).length < 1:
              nextPos = cursorBounds.xy
            self.cursorHistories[i].add nextPos

            for p in self.cursorHistories[i]:
              if p != cursorBounds.xy:
                cursorVisible = true
                self.markDirty()

          else:
            self.cursorHistories[i].add cursorBounds.xy
            self.markDirty()
            self.cursorVisible = true

          while self.cursorHistories[i].len > cursorTrail.clamp(0, 100):
            self.cursorHistories[i].removeShift(0)

        else:
          self.cursorHistories[i].setLen(0)

        if cursorVisible:
          var last = if self.cursorHistories[i].len > 0:
            self.cursorHistories[i][0]
          else:
            cursorBounds.xy

          for xy in self.cursorHistories[i]:
            let dist = (xy - last).length
            for i in 0..<dist.int:
              let xyInterp = mix(last, xy, i.float / dist)
              fillRect(rect(xyInterp, cursorBounds.wh), cursorTrailColor)
            last = xy

          let dist = (cursorBounds.xy - last).length
          for i in 0..<dist.int:
            let xyInterp = mix(last, cursorBounds.xy, i.float / dist)
            fillRect(rect(xyInterp, cursorBounds.wh), cursorTrailColor)

          fillRect(cursorBounds, cursorForegroundColor)
          if isThickCursor:
            let currentRune = self.document.runeAt(s.last)
            if currentRune != 0.Rune and currentRune.int >= ' '.int:
              drawText($currentRune, charBounds, cursorBackgroundColor, 0.UINodeFlags)

        self.lastCursorLocationBounds = (cursorBounds + currentNode.boundsAbsolute.xy).some

        # if i == self.selections.high:
        #   if cursorBounds.x > currentNode.w - currentNode.x - 5 * builder.charWidth:
        #     self.scrollOffset.x += cursorBounds.x - (currentNode.w - currentNode.x - 5 * builder.charWidth)
        #   if cursorBounds.x < 5 * builder.charWidth:
        #     self.scrollOffset.x += cursorBounds.x
        #   self.scrollOffset.x = max(self.scrollOffset.x, 0)

      if i == self.selections.high:
        let dp = self.displayMap.toDisplayPoint(s.last.toPoint)
        let (_, lastIndexDisplay) = state.chunkBounds.binarySearchRange(dp, Bias.Left, cmp)
        if lastIndexDisplay in 0..<state.chunkBounds.len and dp >= state.chunkBounds[lastIndexDisplay].displayRange.a:
          state.cursorOnScreen = true
          self.currentCenterCursor = s.last
          self.currentCenterCursorRelativeYPos = (state.chunkBounds[lastIndexDisplay].bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h
          self.lastHoverLocationBounds = (state.chunkBounds[lastIndexDisplay].bounds + currentNode.boundsAbsolute.xy).some

proc createTextLines(self: TextDocumentEditor, builder: UINodeBuilder, app: App, currentNode: UINode,
    selectionsNode: UINode, lineNumbersNode: UINode, backgroundColor: Color, textColor: Color, sizeToContentX: bool,
    sizeToContentY: bool) =
  var flags = 0.UINodeFlags
  if sizeToContentX:
    flags.incl SizeToContentX
  else:
    flags.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
  else:
    flags.incl FillY

  let parentWidth = if sizeToContentX:
    # todo
    min((self.document.rope.len + 1).clamp(1, 200).float * builder.charWidth, builder.currentMaxBounds().x)
  else:
    currentNode.bounds.w

  let parentHeight = if sizeToContentY:
    # todo
    min(self.numDisplayLines.clamp(1, 200).float * builder.textHeight, builder.currentMaxBounds().y)
  else:
    currentNode.bounds.h

  if sizeToContentY:
    currentNode.h = parentHeight

  let enableSmoothScrolling = self.uiSettings.smoothScroll.get()
  let snapBehaviour = self.nextSnapBehaviour.get(self.defaultSnapBehaviour)
  let scrollSnapDistance: float = parentHeight * self.uiSettings.smoothScrollSnapThreshold.get()
  let scrollSnapDistanceX: float = parentWidth * self.uiSettings.smoothScrollSnapThreshold.get()
  let smoothScrollSpeed: float = self.uiSettings.smoothScrollSpeed.get()

  self.scrollOffset.y = clamp(self.scrollOffset.y, (1.0 - self.numDisplayLines.float) * builder.textHeight, parentHeight - builder.textHeight)
  self.scrollOffset.x = clamp(self.scrollOffset.x, -float.high, 0)

  if enableSmoothScrolling:
    # echo &"{self.interpolatedScrollOffset}, {self.scrollOffset}, {snapBehaviour}"
    if self.interpolatedScrollOffset == self.scrollOffset:
      self.nextSnapBehaviour = ScrollSnapBehaviour.none
    elif snapBehaviour == ScrollSnapBehaviour.Always:
      self.interpolatedScrollOffset = self.scrollOffset
      self.nextSnapBehaviour = ScrollSnapBehaviour.none
    elif snapBehaviour in {ScrollSnapBehaviour.MinDistanceOffscreen, MinDistanceCenter}:
      if abs(self.interpolatedScrollOffset.y - self.scrollOffset.y) > scrollSnapDistance:
        if snapBehaviour == ScrollSnapBehaviour.MinDistanceCenter:
          self.interpolatedScrollOffset.y = self.scrollOffset.y
          self.nextSnapBehaviour = ScrollSnapBehaviour.none
        elif self.interpolatedScrollOffset.y != self.scrollOffset.y:
          self.interpolatedScrollOffset.y = self.scrollOffset.y + sign(self.interpolatedScrollOffset.y - self.scrollOffset.y) * scrollSnapDistance
          self.markDirty()

      if abs(self.interpolatedScrollOffset.x - self.scrollOffset.x) > scrollSnapDistanceX:
        if snapBehaviour == ScrollSnapBehaviour.MinDistanceCenter:
          self.interpolatedScrollOffset.x = self.scrollOffset.x
          self.nextSnapBehaviour = ScrollSnapBehaviour.none
        elif self.interpolatedScrollOffset.x != self.scrollOffset.x:
          self.interpolatedScrollOffset.x = self.scrollOffset.x + sign(self.interpolatedScrollOffset.x - self.scrollOffset.x) * scrollSnapDistanceX
          self.markDirty()

    if self.interpolatedScrollOffset != self.scrollOffset:
      let alpha = 1 - exp(-smoothScrollSpeed * app.platform.deltaTime)
      if self.interpolatedScrollOffset.x != self.scrollOffset.x:
        self.interpolatedScrollOffset.x = mix(self.interpolatedScrollOffset.x, self.scrollOffset.x, alpha)
      if self.interpolatedScrollOffset.y != self.scrollOffset.y:
        self.interpolatedScrollOffset.y = mix(self.interpolatedScrollOffset.y, self.scrollOffset.y, alpha)
      if length(self.interpolatedScrollOffset - self.scrollOffset) < 1:
        self.interpolatedScrollOffset = self.scrollOffset
        self.nextSnapBehaviour = ScrollSnapBehaviour.none
      self.markDirty()

  else:
    self.interpolatedScrollOffset = self.scrollOffset
    self.nextSnapBehaviour = ScrollSnapBehaviour.none

  # echo &"{self.interpolatedScrollOffset}"

  let inclusive = self.config.get("text.inclusive-selection", false)
  let drawChunks = self.debugSettings.drawTextChunks.get()

  let isThickCursor = self.isThickCursor

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let showContextLines = not renderDiff and self.settings.contextLines.get()

  let selectionColor = app.themes.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let contextBackgroundColor = app.themes.theme.color(@["breadcrumbPicker.background"], backgroundColor.lighten(0.05))
  let insertedTextBackgroundColor = app.themes.theme.color(@["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"], color(0.1, 0.2, 0.1))
  let deletedTextBackgroundColor = app.themes.theme.color(@["diffEditor.removedTextBackground", "diffEditor.removedLineBackground"], color(0.2, 0.1, 0.1))
  var changedTextBackgroundColor = app.themes.theme.color(@["diffEditor.changedTextBackground", "diffEditor.changedLineBackground"], color(0.2, 0.2, 0.1))

  let cursorLine = self.selection.last.line
  let cursorDisplayLine = self.displayMap.toDisplayPoint(self.selection.last.toPoint).row.int

  let lineNumbers = self.uiSettings.lineNumbers.get()
  let lineNumberBounds = self.lineNumberBounds()

  let scrollOffset = self.interpolatedScrollOffset
  var startLine = max((-scrollOffset.y / builder.textHeight).int - 1, 0)
  let startLineOffsetFromScrollOffset = (-startLine).float * builder.textHeight
  var slice = self.document.rope.slice()
  let displayEndPoint = self.displayMap.toDisplayPoint(slice.summary.lines)

  if startLine > displayEndPoint.row.int:
    currentNode.renderCommands.clear()
    selectionsNode.renderCommands.clear()
    return

  let contextLines = if showContextLines:
    var contextLines: seq[int]
    for i in 0..10:
      let displayPoint = displayPoint(startLine + i + 2, 0)
      if displayPoint.row.int >= self.numDisplayLines:
        break
      let s = self.displayMap.toPoint(displayPoint)
      contextLines = self.getContextLines(s.toCursor)
      if contextLines.len <= i:
        break

    contextLines
  else:
    @[]

  let highlight = self.uiSettings.syntaxHighlighting.get()
  let indentGuide = self.uiSettings.indentGuide.get()

  var iter = self.displayMap.iter()
  iter.styledChunks.diagnosticEndPoints = self.document.diagnosticEndPoints # todo: don't copy everything here
  if self.document.tsTree.isNotNil and self.document.highlightQuery.isNotNil and highlight:
    iter.styledChunks.highlighter = Highlighter(query: self.document.highlightQuery, tree: self.document.tsTree).some
  if indentGuide:
    let cursorIndentLevel = self.document.rope.indentRunes(self.selection.last.line).int
    iter.indentGuideColumn = cursorIndentLevel.some
  iter.seekLine(startLine)
  # echo &"startLine: {startLine}, scrollOffset: {scrollOffset}, uiae: {startLineOffsetFromScrollOffset}, point: {iter.point}, {iter.diffChunks.wrapChunks.overlayChunks.overlayPoint}, {iter.diffChunks.wrapChunks.wrapPoint}, {iter.diffChunks.diffPoint}, {iter.displayPoint}, "

  var diffRopeSlice: RopeSlice[int]
  var diffIter: DisplayChunkIterator
  if renderDiff:
    diffRopeSlice = self.diffDocument.rope.slice()
    diffIter = self.diffDisplayMap.iter()
    if self.diffDocument.tsTree.isNotNil and self.diffDocument.highlightQuery.isNotNil and highlight:
      diffIter.styledChunks.highlighter = Highlighter(query: self.diffDocument.highlightQuery, tree: self.diffDocument.tsTree).some
    diffIter.seekLine(startLine)

  let signShow = self.settings.signs.show.get()
  let lineNumberWidth = self.lineNumberWidth()
  let signColumnWidth = if signShow == SignColumnShowKind.Number:
    floor(lineNumberWidth / builder.charWidth).int - 2
  else:
    self.requiredSignColumnWidth()
  let signColumnPixelWidth = if signShow == SignColumnShowKind.Number:
    0.float
  else:
    signColumnWidth.float * builder.charWidth

  let mainOffset = if renderDiff:
    floor((parentWidth + lineNumberWidth) * 0.5)
  else:
    0

  let width = if renderDiff:
    floor((parentWidth + lineNumberWidth) * 0.5 - lineNumberWidth)
  else:
    parentWidth

  var state = LineDrawerState(
    builder: builder,
    displayMap: self.displayMap,
    bounds: rect(mainOffset, 0, width, parentHeight),
    offset: vec2(mainOffset + scrollOffset.x, scrollOffset.y - startLineOffsetFromScrollOffset + (iter.displayPoint.row.int - startLine).float * builder.textHeight).floor,
    lastDisplayPoint: iter.displayPoint,
    lastDisplayEndPoint: iter.displayPoint,
    lastPoint: iter.point,
    cursorOnScreen: false,
    reverse: true,
  )

  var diffState = LineDrawerState(
    builder: builder,
    displayMap: self.diffDisplayMap,
    bounds: rect(0, 0, width, parentHeight),
    offset: vec2(-scrollOffset.x, scrollOffset.y - startLineOffsetFromScrollOffset + (diffIter.displayPoint.row.int - startLine).float * builder.textHeight).floor,
    lastDisplayPoint: diffIter.displayPoint,
    lastDisplayEndPoint: diffIter.displayPoint,
    lastPoint: diffIter.point,
    cursorOnScreen: false,
    reverse: false,
  )

  let errorColor = app.themes.theme.tokenColor("error", color(0.8, 0.2, 0.2))
  let warningColor = app.themes.theme.tokenColor("warning", color(0.8, 0.8, 0.2))
  let informationColor = app.themes.theme.tokenColor("information", color(0.8, 0.8, 0.8))
  let hintColor = app.themes.theme.tokenColor("hint", color(0.7, 0.7, 0.7))

  let space = self.uiSettings.whitespaceChar.get()
  let spaceColorName = self.uiSettings.whitespaceColor.get()
  if space.len > 0:
    currentNode.renderCommands.space = space.runeAt(0)

  currentNode.renderCommands.spacesColor = app.themes.theme.tokenColor(spaceColorName, textColor)

  self.lastRenderedChunks.setLen(0)

  lineNumbersNode.renderCommands.clear()
  selectionsNode.renderCommands.clear()
  currentNode.renderCommands.clear()
  buildCommands(currentNode.renderCommands):

    proc drawChunk(chunk: DisplayChunk, state: var LineDrawerState): LineDrawerResult =
      let external = chunk.styledChunk.chunk.external
      if state.reverse and not external:
        self.lastRenderedChunks.add((chunk.point...chunk.endPoint, chunk.displayPoint...chunk.displayEndPoint))

      if state.lastPoint.row != chunk.point.row and not external:
        state.addedLineNumber = false

      while state.lastDisplayPoint.row < chunk.displayPoint.row:
        for diagnosticsData in self.document.diagnosticsPerLS.mitems:
          diagnosticsData.diagnosticsPerLine.withValue(state.lastPoint.row.int, val):
            for i in val[].mitems:
              let i = i
              let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[i]
              let nlIndex = diagnostic.message.find("\n")
              var maxIndex = if nlIndex != -1: nlIndex else: diagnostic.message.len
              maxIndex = min(maxIndex, 100)
              var message = "     ■ " & diagnostic.message[0..<maxIndex]
              if maxIndex < diagnostic.message.len:
                message.add "..."
              let width = message.runeLen.float * builder.charWidth # todo: measure text
              let color = case diagnostic.severity.get(lsp_types.DiagnosticSeverity.Hint)
              of lsp_types.DiagnosticSeverity.Error: errorColor
              of lsp_types.DiagnosticSeverity.Warning: warningColor
              of lsp_types.DiagnosticSeverity.Information: informationColor
              of lsp_types.DiagnosticSeverity.Hint: hintColor
              drawText(message, rect(state.offset.x, state.offset.y, width, builder.textHeight), color, 0.UINodeFlags)
              state.offset.x += width

        if state.lastDisplayEndPoint.column == 0:
          if state.displayMap.diffMap.snapshot.isEmptySpace(state.lastDisplayPoint.DiffPoint):
            fillRect(rect(state.bounds.x, state.offset.y, state.bounds.w, builder.textHeight), backgroundColor.darken(0.03))

        state.lastDisplayPoint.row += 1
        state.lastDisplayPoint.column = 0
        state.lastDisplayEndPoint.row += 1
        state.lastDisplayEndPoint.column = 0
        state.offset.y += state.builder.textHeight
        state.offset.x = state.bounds.x + scrollOffset.x

      if renderDiff and state.lastDisplayEndPoint.column == 0 and self.diffChanges.isSome:
        let diffRow = self.diffChanges.get.mapLine(chunk.point.row.int, state.reverse)
        if diffRow.getSome(d):
          if d.changed:
            fillRect(rect(state.bounds.x, state.offset.y, state.bounds.w, builder.textHeight), changedTextBackgroundColor)
        else:
          let color = if state.reverse: insertedTextBackgroundColor else: deletedTextBackgroundColor
          fillRect(rect(state.bounds.x, state.offset.y, state.bounds.w, builder.textHeight), color)

      if chunk.displayPoint.column > state.lastDisplayEndPoint.column:
        state.offset.x += (chunk.displayPoint.column - state.lastDisplayEndPoint.column).float * state.builder.charWidth

      if state.lastPoint.row != chunk.point.row and not external:
        state.lastDisplayPoint.column = 0

      if state.offset.y >= state.bounds.yh:
        return LineDrawerResult.Break

      if state.offset.x >= state.bounds.xw:
        return LineDrawerResult.ContinueNextLine

      if not external:
        state.lastPoint = chunk.point
      state.lastDisplayPoint = chunk.displayPoint
      state.lastDisplayEndPoint = chunk.displayEndPoint

      if not state.addedLineNumber:
        state.addedLineNumber = true

        if state.fillLineNumberBackground and signShow != SignColumnShowKind.Number and signShow != SignColumnShowKind.No:
          buildCommands(lineNumbersNode.renderCommands):
            let bounds = rect(floor(state.bounds.x + lineNumberWidth - signColumnPixelWidth), state.offset.y, signColumnPixelWidth, builder.textHeight)
            fillRect(bounds, state.lineNumberBackgroundColor)

        var drawLineNumber = true
        self.signs.withValue(chunk.point.row.int, value):
          buildCommands(lineNumbersNode.renderCommands):
            var bounds = rect(state.bounds.x + lineNumberWidth - signColumnPixelWidth, state.offset.y, signColumnPixelWidth, builder.textHeight)
            if signShow == SignColumnShowKind.Number:
              drawLineNumber = false
              bounds = rect(vec2(state.bounds.x + builder.charWidth, state.offset.y), lineNumberBounds)

              if state.fillLineNumberBackground:
                fillRect(rect(vec2(state.bounds.x, state.offset.y), lineNumberBounds), state.lineNumberBackgroundColor)

            var i = 0
            for s in value[]:
              if i + s.width > signColumnWidth:
                break

              var color = textColor
              if s.color != "":
                color = app.themes.theme.tokenColor(s.color, textColor)
              drawText(s.text, bounds, color * s.tint, 0.UINodeFlags)
              bounds.x += builder.charWidth * s.width.float
              i += s.width

        if drawLineNumber:
          lineNumbersNode.renderCommands.drawLineNumber(state.builder, chunk.point.row.int, vec2(state.bounds.x, state.offset.y), cursorLine, lineNumbers, lineNumberBounds - vec2(signColumnPixelWidth, 0), textColor, state.lineNumberBackgroundColor, state.fillLineNumberBackground)

      if chunk.len > 0:
        let font = self.platform.getFontInfo(self.platform.fontSize, 0.UINodeFlags)
        let arrangementIndex = currentNode.renderCommands.typeset(chunk.toOpenArray, font)
        let width = currentNode.renderCommands.layoutBounds(arrangementIndex).x
        let indices {.cursor.} = currentNode.renderCommands.arrangements[arrangementIndex]
        let bounds = rect(state.offset, vec2(width, state.builder.textHeight))
        let charBoundsStart = state.charBounds.len
        state.chunkBounds.add ChunkBounds(
          range: chunk.point...chunk.endPoint,
          displayRange: chunk.displayPoint...chunk.endDisplayPoint,
          bounds: bounds,
          text: chunk.styledChunk.chunk,
          chunk: chunk,
          charsRange: charBoundsStart...(charBoundsStart + indices.selectionRects.len),
        )
        state.charBounds.add currentNode.renderCommands.arrangement.selectionRects[indices.selectionRects]

        if state.backgroundColor.getSome(color):
          fillRect(bounds, color)

        let (underlineColor, underlineFlags) = if chunk.styledChunk.underline.getSome(underline):
          let underlineColor = app.themes.theme.tokenColor(underline.color, textColor)
          (underlineColor, &{TextUndercurl})
        else:
          (color(1, 1, 1), 0.UINodeFlags)

        let textColor = if chunk.scope.len == 0: textColor else: app.themes.theme.tokenColor(chunk.scope, textColor)
        var flags = underlineFlags
        if chunk.styledChunk.drawWhitespace:
          flags.incl UINodeFlag.TextDrawSpaces
        drawText(chunk.toOpenArray, arrangementIndex, bounds, textColor, flags, underlineColor)
        state.offset.x += width

        if drawChunks:
          drawRect(bounds, color(1, 0, 0))

      else:
        state.chunkBounds.add ChunkBounds(
          range: chunk.point...chunk.endPoint,
          displayRange: chunk.displayPoint...chunk.endDisplayPoint,
          bounds: rect(state.offset, vec2(state.builder.charWidth, state.builder.textHeight)),
          text: chunk.styledChunk.chunk,
          chunk: chunk,
          charsRange: state.charBounds.len...state.charBounds.len,
        )

        if drawChunks:
          drawRect(rect(state.offset, vec2(state.builder.charWidth, state.builder.textHeight)), color(1, 0, 0))

      return LineDrawerResult.Continue

    var addedCursorLineBackground = false
    while iter.next().getSome(chunk):
      if not addedCursorLineBackground and chunk.displayPoint.row.int == cursorDisplayLine:
        let yOffset = (chunk.displayPoint.row.int - state.lastDisplayPoint.row.int).float * builder.textHeight
        selectionsNode.renderCommands.commands.add(RenderCommand(
          kind: RenderCommandKind.FilledRect,
          bounds: rect(state.bounds.x, state.offset.y + yOffset, state.bounds.w, builder.textHeight),
          color: backgroundColor.lighten(0.05)))
        addedCursorLineBackground = true

      # todo: this sometimes happens for a frame or two, probably because some data structures are in an invalid state
      # which causes an infinte loop here.
      # Just breaking and trying again will be fine for now, but the root cause should be fixed.
      if state.chunkBounds.len > 10000:
        log lvlWarn, "Rendering too much text, your font size is too small or there is a bug"
        break

      case drawChunk(chunk, state)
      of Continue: discard
      of ContinueNextLine: iter.seekLine(chunk.displayPoint.row.int + 1)
      of Break: break

    if showContextLines and contextLines.len > 0:
      let startDisplayPoint = self.displayMap.toDisplayPoint(point(contextLines.last, 0))
      var contextLinesIter = self.displayMap.iter()
      if self.document.tsTree.isNotNil and self.document.highlightQuery.isNotNil and highlight:
        contextLinesIter.styledChunks.highlighter = Highlighter(query: self.document.highlightQuery, tree: self.document.tsTree).some
      if indentGuide:
        let cursorIndentLevel = self.document.rope.indentRunes(self.selection.last.line).int
        contextLinesIter.indentGuideColumn = cursorIndentLevel.some
      var contextLinesState = LineDrawerState(
        builder: builder,
        displayMap: self.displayMap,
        bounds: rect(mainOffset, 0, width, parentHeight),
        offset: vec2(mainOffset, 0),
        lastDisplayPoint: startDisplayPoint,
        lastDisplayEndPoint: startDisplayPoint,
        lastPoint: point(contextLines.last, 0),
        cursorOnScreen: false,
        reverse: true,
        lineNumberBackgroundColor: backgroundColor.lighten(0.05),
        fillLineNumberBackground: true,
      )
      contextLinesIter.seekLine(startDisplayPoint.row.int)

      fillRect(rect(contextLinesState.bounds.x, contextLinesState.bounds.y, contextLinesState.bounds.w, builder.textHeight), backgroundColor.lighten(0.05))

      var i = contextLines.high
      while contextLinesIter.next().getSome(chunk):
        if chunk.displayPoint.row > contextLinesState.lastDisplayPoint.row:
          dec i
          if i < 0:
            break
          let nextPoint = point(contextLines[i], 0)
          let nextDisplayPoint = self.displayMap.toDisplayPoint(nextPoint)
          contextLinesIter.seekLine(nextDisplayPoint.row.int)
          fillRect(rect(contextLinesState.bounds.x, (contextLines.high - i).float * builder.textHeight, contextLinesState.bounds.w, builder.textHeight), contextBackgroundColor)
          contextLinesState.offset.x = mainOffset
          contextLinesState.offset.y += builder.textHeight
          contextLinesState.lastDisplayPoint = nextDisplayPoint
          contextLinesState.lastDisplayEndPoint = nextDisplayPoint
          contextLinesState.lastPoint = nextPoint
          contextLinesState.addedLineNumber = false
          continue

        if contextLinesState.chunkBounds.len > 10000:
          log lvlError, "Rendering too much text, your font size is too small or there is a bug"
          break

        case drawChunk(chunk, contextLinesState)
        of Continue: discard
        of ContinueNextLine: discard
        of Break: break

    if renderDiff:
      startScissor(diffState.bounds)
      while diffIter.next().getSome(chunk):
        if diffState.chunkBounds.len > 10000:
          log lvlError, "Rendering too much text, your font size is too small or there is a bug"
          break
        case drawChunk(chunk, diffState)
        of Continue: discard
        of ContinueNextLine: diffIter.seekLine(chunk.displayPoint.row.int + 1)
        of Break: break
      endScissor()

  self.drawCursors(builder, app, currentNode, currentNode.renderCommands, state)

  var ropeCursor = self.displayMap.buffer.visibleText.cursorT(Point)
  let visibleTextRange = self.visibleTextRange(2)
  for selections in self.customHighlights.values:
    for s in selections:
      if s.selection.isEmpty:
        continue
      var sn = s.selection.normalized
      if sn.last < visibleTextRange.first or sn.first > visibleTextRange.last:
        continue
      let color = app.themes.theme.color(s.color, color(200/255, 200/255, 200/255)) * s.tint
      self.drawHighlight(builder, sn, color, selectionsNode.renderCommands, state, ropeCursor)

  for s in self.selections:
    var sn = s.normalized
    if isThickCursor and inclusive:
      sn.last.column += 1
    if sn.isEmpty:
      continue
    if sn.last < visibleTextRange.first or sn.first > visibleTextRange.last:
      continue

    self.drawHighlight(builder, sn, selectionColor, selectionsNode.renderCommands, state, ropeCursor)

  selectionsNode.markDirty(builder)
  currentNode.markDirty(builder)

  proc handleMouseEvent(self: TextDocumentEditor, btn: MouseButton, pos: Vec2, mods: set[Modifier], drag: bool) =
    if self.document.isNil:
      return

    var (_, index) = state.chunkBounds.binarySearchRange(pos, Bias.Left, cmp)
    if index notin 0..state.chunkBounds.high:
      return

    if index + 1 < state.chunkBounds.len and pos.y >= state.chunkBounds[index].bounds.yh and pos.y < state.chunkBounds[index + 1].bounds.yh:
      index += 1

    if not drag:
      self.lastPressedMouseButton = btn

    if btn notin {MouseButton.Left, DoubleClick, TripleClick}:
      return
    # if line >= self.document.numLines:
    #   return

    let chunk = state.chunkBounds[index]

    let posAdjusted = if self.isThickCursor(): pos else: pos + vec2(builder.charWidth * 0.5, 0)
    let searchPosition = vec2(posAdjusted.x - chunk.bounds.x, 0)
    var (_, charIndex) = state.charBounds.toOpenArray(chunk.charsRange.a, chunk.charsRange.b - 1).binarySearchRange(searchPosition, Left, cmp)

    var newCursor = self.selection.last
    if charIndex + chunk.charsRange.a in chunk.charsRange.a..<chunk.charsRange.b:
      if searchPosition.x >= state.charBounds[chunk.charsRange.a + charIndex].xw and (index == state.chunkBounds.high or state.chunkBounds[index + 1].range.a.row > chunk.range.a.row):
        charIndex += 1
      newCursor = chunk.range.a.toCursor + (0, charIndex) # todo unicode offset

    else:
      let offset = self.getCursorPos2(builder, chunk.text.toOpenArray, pos - chunk.bounds.xy)
      newCursor = chunk.range.a.toCursor + (0, offset)

    if drag:
      let currentSelection = self.dragStartSelection
      let first = if (currentSelection.isBackwards and newCursor < currentSelection.first) or (not currentSelection.isBackwards and newCursor >= currentSelection.first):
        currentSelection.first
      else:
        currentSelection.last
      self.selection = (first, newCursor)
      self.runDragCommand()

    else:
      self.selection = newCursor.toSelection
      self.dragStartSelection = self.selection

      if btn == MouseButton.Left:
        if mods == {Control}:
          self.runControlClickCommand()
        else:
          self.runSingleClickCommand()
      elif btn == DoubleClick:
        self.runDoubleClickCommand()
      elif btn == TripleClick:
        self.runTripleClickCommand()

    self.updateTargetColumn(Last)
    self.layout.tryActivateEditor(self)
    self.markDirty()

  let textNode = currentNode
  builder.panel(&{UINodeFlag.FillX, FillY}):
    onClickAny btn:
      self.handleMouseEvent(btn, pos - vec2(textNode.x, 0), modifiers, drag = false)
    onDrag MouseButton.Left:
      self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, drag = true)

  # Get center line
  if not state.cursorOnScreen:
    # todo: move this to a function
    let centerPos = currentNode.bounds.wh * 0.5 + vec2(0, builder.textHeight * -0.5)
    var (_, index) = state.chunkBounds.binarySearchRange(centerPos, Bias.Left, cmp)
    if index notin 0..state.chunkBounds.high:
      return

    if index + 1 < state.chunkBounds.len and centerPos.y >= state.chunkBounds[index].bounds.yh and centerPos.y < state.chunkBounds[index + 1].bounds.yh:
      index += 1

    let chunk = state.chunkBounds[index]
    let centerPoint = (chunk.range.a.row.int, (chunk.range.a.column + chunk.range.b.column).int div 2)
    self.currentCenterCursor = centerPoint
    self.currentCenterCursorRelativeYPos = (chunk.bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h

method createUI*(self: TextDocumentEditor, builder: UINodeBuilder): seq[OverlayFunction] =
  let app = ({.gcsafe.}: gEditor)
  self.preRender(builder.currentParent.bounds)

  let dirty = self.dirty
  self.resetDirty()

  let logNewRenderer = self.debugSettings.logTextRenderTime.get()
  let transparentBackground = self.uiSettings.background.transparent.get()
  let inactiveBrightnessChange = self.uiSettings.background.inactiveBrightnessChange.get()

  let textColor = app.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: app.themes.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: app.themes.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)

  if transparentBackground:
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  var headerColor = if self.active: app.themes.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: app.themes.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  var sizeFlags = 0.UINodeFlags
  if sizeToContentX:
    sizeFlags.incl SizeToContentX
  else:
    sizeFlags.incl FillX

  if sizeToContentY:
    sizeFlags.incl SizeToContentY
  else:
    sizeFlags.incl FillY

  let renderDiff = self.diffDocument.isNotNil and self.diffDocument.isInitialized and self.diffChanges.isSome

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId):
    onClickAny btn:
      self.layout.tryActivateEditor(self)

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.mode, self.document, headerColor, textColor):
          onRight:
            proc cursorString(cursor: Cursor): string =
              if self.document != nil and self.document.isInitialized:
                $cursor.line & ":" & $cursor.column & ":" & $self.document.buffer.visibleText.runeIndexInLine(cursor)
              else:
                ""
            let readOnlyText = if self.document.readOnly: "-readonly- " else: ""
            let stagedText = if self.document.staged: "-staged- " else: ""
            let diffText = if renderDiff: "-diff- " else: ""

            let currentRune = self.document.runeAt(self.selection.last)
            let currentRuneText = if currentRune == 0.Rune:
              "\\0"
            elif currentRune == '\t'.Rune:
              "\\t"
            elif currentRune == '\n'.Rune:
              "\\n"
            else:
              $currentRune

            var currentRuneHexText = currentRune.int.toHex.strip(trailing=false, chars={'0'})
            if currentRuneHexText.len == 0:
              currentRuneHexText = "0"

            let text = fmt"{self.customHeader} | {readOnlyText}{stagedText}{diffText}{self.document.undoableRevision}/{self.document.revision}  '{currentRuneText}' (U+{currentRuneHexText}) {(cursorString(self.selection.first))}-{(cursorString(self.selection.last))} - {self.id} "
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, pivot = vec2(1, 0), textColor = textColor, text = text)

        let lineNumberWidth = self.lineNumberWidth()
        builder.panel(sizeFlags + &{FillBackground, MaskContent}, backgroundColor = backgroundColor):
          var selectionsNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}, x = lineNumberWidth):
            selectionsNode = currentNode
            selectionsNode.renderCommands.clear()

          var textNode: UINode
          builder.panel(sizeFlags + &{MaskContent}, x = lineNumberWidth):
            textNode = currentNode
            textNode.renderCommands.clear()

          var lineNumbersNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}):
            lineNumbersNode = currentNode
            lineNumbersNode.renderCommands.clear()

          onScroll:
            if Control in modifiers:
              self.scrollTextHorizontal(delta.y * self.uiSettings.scrollSpeed.get() / builder.charWidth)
            else:
              self.scrollText(delta.y * self.uiSettings.scrollSpeed.get())

          var t = startTimer()

          if self.document != nil and self.document.isInitialized:
            self.createTextLines(builder, app, textNode, selectionsNode, lineNumbersNode,
              backgroundColor, textColor, sizeToContentX, sizeToContentY)

          let e = t.elapsed.ms
          if logNewRenderer:
            debugf"Render new took {e} ms"

          self.lastContentBounds = textNode.bounds

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))

  if self.showHover:
    result.add proc() =
      self.createHover(builder, app, self.lastHoverLocationBounds.get(rect(100, 100, 10, 10)))
