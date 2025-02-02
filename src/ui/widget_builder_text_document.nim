import std/[strformat, tables, sugar, sequtils, strutils, algorithm, math, options, json]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, regex, rope_utils, timer]
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
type LocationInfos = object
  cursor: Option[CursorLocationInfo]
  hover: Option[CursorLocationInfo]
  diagnostic: Option[CursorLocationInfo]

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
    reverse: bool

proc cmp(r: ChunkBounds, point: Point): int =
  let range = if r.chunk.styledChunk.chunk.external:
    r.range.a...r.range.a
  else:
    r.range

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

template tokenColor*(theme: Theme, part: StyledText, default: untyped): Color =
  if part.scopeIsToken:
    theme.tokenColor(part.scope, default)
  else:
    theme.color(part.scope, default)

proc shouldIgnoreAsContextLine(self: TextDocument, line: int): bool
proc clampToLine(document: TextDocument, selection: Selection, line: StyledLine): tuple[first: RuneIndex, last: RuneIndex]

proc getTextRange(line: StyledLine, partIndex: int): (RuneIndex, RuneIndex) =
  var startRune = 0.RuneIndex
  var endRune = 0.RuneIndex

  if partIndex >= line.parts.len:
    return

  if line.parts[partIndex].textRange.isSome:
    startRune = line.parts[partIndex].textRange.get.startIndex
    endRune = line.parts[partIndex].textRange.get.endIndex
  else:
    # Inlay text, find start rune of neighbor, prefer left side
    var found = false
    for i in countdown(partIndex - 1, 0):
      if line.parts[i].textRange.isSome:
        startRune = line.parts[i].textRange.get.endIndex
        if not line.parts[partIndex].inlayContainCursor:
          # choose background color of right neighbor
          startRune -= 1.RuneCount

        found = true
        break

    if not found:
      for i in countup(partIndex + 1, line.parts.high):
        if line.parts[i].textRange.isSome:
          startRune = line.parts[i].textRange.get.startIndex
          break

    endRune = startRune

  return (startRune, endRune)

proc `*`(c: Color, v: Color): Color {.inline.} =
  ## Multiply color by a value.
  result.r = c.r * v.r
  result.g = c.g * v.g
  result.b = c.b * v.b
  result.a = c.a * v.a

proc getCursorPos(self: TextDocumentEditor, builder: UINodeBuilder, text: string, line: int, startOffset: RuneIndex, pos: Vec2): int =
  ## Calculates the byte index in the original line at the given pos (relative to the parts top left corner)

  var offset = 0.0
  var i = 0
  for r in text.runes:
    let w = builder.textWidth($r).round
    let posX = if self.isThickCursor(): pos.x else: pos.x + w * 0.5

    if posX < offset + w:
      let runeOffset = startOffset + i.RuneCount
      if runeOffset.RuneCount >= self.document.lineRuneLen(line):
        return 0
      let byteIndex = self.document.buffer.visibleText.byteOffsetInLine(line, runeOffset)
      return byteIndex

    offset += w
    inc i

  let byteIndex = self.document.buffer.visibleText.byteOffsetInLine(line, startOffset + text.runeLen)
  return byteIndex

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

  let backgroundColor = app.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = app.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
  let docsColor = app.theme.color("editor.foreground", color(1, 1, 1))

  let numLinesToShow = min(10, self.hoverText.countLines)
  let (top, bottom) = (cursorBounds.yh.float, cursorBounds.yh.float + totalLineHeight * numLinesToShow.float)
  let height = bottom - top

  const docsWidth = 50.0
  let totalWidth = charWidth * docsWidth
  var clampedX = cursorBounds.x
  if clampedX + totalWidth > builder.root.w:
    clampedX = max(builder.root.w - totalWidth, 0)

  var hoverPanel: UINode = nil
  builder.panel(&{SizeToContentX, MaskContent, FillBackground, DrawBorder, MouseHover, SnapInitialBounds, AnimateBounds}, x = clampedX, y = top, h = height, pivot = vec2(0, 0), backgroundColor = backgroundColor, borderColor = borderColor, userId = self.hoverId.newPrimaryId):
    hoverPanel = currentNode
    var textNode: UINode = nil
    # todo: height
    builder.panel(&{DrawText, SizeToContentX}, x = 0, y = self.hoverScrollOffset, h = 1000, text = self.hoverText, textColor = docsColor):
      textNode = currentNode

    onScroll:
      let scrollSpeed = app.config.asConfigProvider.getValue("text.hover-scroll-speed", 20.0)
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

  let transparentBackground = app.config.getOption[:bool]("ui.background.transparent", false)
  var backgroundColor = app.theme.color(@["editorSuggestWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = app.theme.color(@["editorSuggestWidget.border", "panel.background"], color(30/255, 30/255, 30/255))
  let selectedBackgroundColor = app.theme.color(@["editorSuggestWidget.selectedBackground", "list.activeSelectionBackground"], color(200/255, 200/255, 200/255))
  let docsColor = app.theme.color(@["editorSuggestWidget.foreground", "editor.foreground"], color(1, 1, 1))
  let nameColor = app.theme.color(@["editorSuggestWidget.foreground", "editor.foreground"], color(1, 1, 1))
  let nameSelectedColor = app.theme.color(@["editorSuggestWidget.highlightForeground", "editor.foreground"], color(1, 1, 1))
  let scopeColor = app.theme.color(@["descriptionForeground", "editor.foreground"], color(175/255, 1, 175/255))

  if transparentBackground:
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  const numLinesToShow = 25
  let (top, bottom) = (cursorBounds.yh.float, cursorBounds.yh.float + totalLineHeight * numLinesToShow)

  const docsWidth = 75.0
  const maxLabelLen = 30
  const maxTypeLen = 30
  updateBaseIndexAndScrollOffset(bottom - top, self.completionsBaseIndex, self.completionsScrollOffset, self.completionMatches.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  var rows: seq[UINode] = @[]

  var completionsPanel: UINode = nil
  builder.panel(&{SizeToContentX, SizeToContentY, AnimateBounds, MaskContent}, x = cursorBounds.x, y = top, pivot = vec2(0, 0), userId = self.completionsId.newPrimaryId):
    completionsPanel = currentNode

    proc handleScroll(delta: float) =
      let scrollAmount = delta * app.config.asConfigProvider.getValue("text.scroll-speed", 40.0)
      self.scrollOffset += scrollAmount
      self.markDirty()

    var maxLabelWidth = 4 * builder.charWidth
    var maxDetailWidth = 1 * builder.charWidth
    var detailColumn: seq[UINode] = @[]

    proc handleLine(i: int, y: float, down: bool) =
      var backgroundColor = backgroundColor

      if i == self.selectedCompletion:
        backgroundColor = selectedBackgroundColor

      let pivot = if down:
        vec2(0, 0)
      else:
        vec2(0, 1)

      builder.panel(&{SizeToContentY, FillBackground}, y = y, pivot = pivot, backgroundColor = backgroundColor):
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
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = currentNode.w, pivot = vec2(0, 0), text = scopeText, textColor = scopeColor):
          detailColumn.add currentNode
          maxDetailWidth = max(maxDetailWidth, currentNode.w)

    var listNode: UINode
    builder.panel(&{UINodeFlag.MaskContent, DrawBorder, SizeToContentX, SizeToContentY}, borderColor = borderColor):
      listNode = currentNode
      let lineFlags = &{SizeToContentX, SizeToContentY}
      let maxHeight = bottom - top
      let linesNode = builder.createLines(self.completionsBaseIndex, self.completionsScrollOffset, self.completionMatches.high, maxHeight.some, lineFlags, backgroundColor, handleScroll, handleLine)

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
        builder.panel(&{UINodeFlag.FillBackground, DrawText, MaskContent, TextWrap},
          x = listNode.xw, w = docsWidth * charWidth, h = listNode.h,
          backgroundColor = backgroundColor, textColor = docsColor, text = docText)

  if completionsPanel.bounds.yh > completionsPanel.parent.bounds.h:
    completionsPanel.rawY = cursorBounds.y
    completionsPanel.pivot = vec2(0, 1)

    # Reverse order of rows
    for i in 0..<(rows.len div 2):
      let y1 = rows[i].bounds.y
      let y2 = rows[rows.high - i].bounds.y
      rows[i].rawY = y2
      rows[rows.high - i].rawY = y1

  if completionsPanel.bounds.xw > completionsPanel.parent.bounds.w:
    completionsPanel.rawX = max(completionsPanel.parent.bounds.w - completionsPanel.bounds.w, 0)

proc drawHighlight(self: TextDocumentEditor, builder: UINodeBuilder, sn: Selection, color: Color, renderCommands: var RenderCommands, chunkBounds: var seq[ChunkBounds], iter: var DisplayChunkIterator, cursor: var RopeCursorT[Point]) =

  # if sn.first.toPoint < iter.point:
  #   echo &"reset-------------------------------------"
  #   iter = self.displayMap.iter()

  # iter.seek(sn.first.toPoint)
  # let dpFirst = iter.displayPoint
  # iter.seek(sn.last.toPoint)
  # let dpLast = iter.displayPoint

  # let dpFirst = self.displayMap.toDisplayPoint(sn.first.toPoint)
  # let dpLast = self.displayMap.toDisplayPoint(sn.last.toPoint)

  # if dpFirst != dpFirst2:
  #   echo &"{sn} -> {dpFirst} != {dpFirst2}"

  # if dpLast != dpLast2:
  #   echo &"{sn} -> {dpLast} != {dpLast2}"

  # let (firstFound, firstIndexNormalized) = chunkBounds.binarySearchRange(dpFirst, Bias.Right, cmp)
  # let (lastFound, lastIndexNormalized) = chunkBounds.binarySearchRange(dpLast, Bias.Right, cmp)

  let r = sn.first.toPoint...sn.last.toPoint

  let (firstFound, firstIndexNormalized) = chunkBounds.binarySearchRange(r.a, Bias.Right, cmp)
  let (lastFound, lastIndexNormalized) = chunkBounds.binarySearchRange(r.b, Bias.Right, cmp)
  # echo &"{sn} -> {r} -> first: {firstFound}, {firstIndexNormalized}, last: {lastFound}, {lastIndexNormalized} / {chunkBounds.len}"
  # echo &"{sn} -> {dpFirst}...{dpLast} -> first: {firstFound}, {firstIndexNormalized}, last: {lastFound}, {lastIndexNormalized} / {chunkBounds.len}"
  if chunkBounds.len > 0:
    let firstIndexClamped = if firstIndexNormalized != -1:
      firstIndexNormalized
    elif r.a < chunkBounds[0].range.a:
      0
    elif r.a > chunkBounds[^1].range.b:
      chunkBounds.high
    else:
      -1

    let lastIndexClamped = if lastIndexNormalized != -1:
      lastIndexNormalized
    elif r.b < chunkBounds[0].range.a:
      0
    elif r.b > chunkBounds[^1].range.b:
      chunkBounds.high
    else:
      -1

    if firstIndexClamped != -1 and lastIndexClamped != -1:
      for i in firstIndexClamped..lastIndexClamped:
        if i >= chunkBounds.len:
          break

        let bounds = chunkBounds[i]

        let linePoint = point(bounds.range.a.row, 0)
        if cursor.position > linePoint:
          cursor.resetCursor()
        if cursor.position < linePoint or not cursor.didSeek:
          cursor.seekForward(linePoint)
          cursor.cacheOffset()

        let lineEmpty = cursor.currentChar() == '\n'

        # todo: correctly handle multi byte chars
        let firstOffset = if lineEmpty or bounds.chunk.styledChunk.chunk.external:
          0
        elif r.a in bounds.range:
          r.a.column.int - bounds.range.a.column.int
        elif r.a < bounds.range.a:
          0
        else:
          bounds.range.len.column.int

        let lastOffset = if lineEmpty or bounds.chunk.styledChunk.chunk.external:
          1
        elif r.b in bounds.range:
          r.b.column.int - bounds.range.a.column.int
        elif r.b < bounds.range.a:
          0
        else:
          bounds.range.len.column.int

        var selectionBounds = rect(
          (bounds.bounds.xy + vec2(firstOffset.float * builder.charWidth, 0)),
          (vec2((lastOffset - firstOffset).float * builder.charWidth, builder.textHeight)))

        if renderCommands.commands.len > 0:
          let last = renderCommands.commands[^1].addr
          if last.kind == RenderCommandKind.FilledRect and last.bounds.y == selectionBounds.y and last.bounds.h == selectionBounds.h and abs(last.bounds.xw - selectionBounds.x) < 0.1 and last.color == color:
            last.bounds.w += selectionBounds.w
          else:
            renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: selectionBounds, color: color))
        else:
          renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: selectionBounds, color: color))

proc drawLineNumber(renderCommands: var RenderCommands, builder: UINodeBuilder, lineNumber: int, offset: Vec2, cursorLine: int, lineNumbers: LineNumbers, lineNumberBounds: Vec2, textColor: Color) =
  var lineNumberText = ""
  var lineNumberX = 0.float
  if lineNumbers != LineNumbers.None and cursorLine == lineNumber:
    lineNumberText = $(lineNumber + 1)
  elif lineNumbers == LineNumbers.Absolute:
    lineNumberText = $(lineNumber + 1)
    lineNumberX = max(0.0, lineNumberBounds.x - lineNumberText.len.float * builder.charWidth)
  elif lineNumbers == LineNumbers.Relative:
    lineNumberText = $abs((lineNumber + 1) - cursorLine)
    lineNumberX = max(0.0, lineNumberBounds.x - lineNumberText.len.float * builder.charWidth)

  if lineNumberText.len > 0:
    let width = builder.textWidth(lineNumberText)
    buildCommands(renderCommands):
      drawText(lineNumberText, rect(offset.x + lineNumberX, offset.y, width, builder.textHeight), textColor, 0.UINodeFlags)

proc drawCursors(self: TextDocumentEditor, builder: UINodeBuilder, app: App, currentNode: UINode, renderCommands: var RenderCommands, state: var LineDrawerState) =

  let cursorForegroundColor = app.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let cursorSpeed: float = app.config.asConfigProvider.getValue("ui.cursor-speed", 100.0)
  let cursorTrail: int = app.config.asConfigProvider.getValue("ui.cursor-trail", 2)
  let isThickCursor = self.isThickCursor

  buildCommands(renderCommands):
    self.cursorHistories.setLen(self.selections.len)
    for i, s in self.selections:
      let dp = self.displayMap.toDisplayPoint(s.last.toPoint)
      let (found, lastIndex) = state.chunkBounds.binarySearchRange(dp, Bias.Right, cmp)
      if lastIndex in 0..<state.chunkBounds.len and dp in state.chunkBounds[lastIndex].displayRange:
        let chunk = state.chunkBounds[lastIndex]
        # todo: correctly handle multi byte chars
        let relativeOffset = dp.column.int - chunk.displayRange.a.column.int
        var cursorBounds = rect(chunk.bounds.xy + vec2(relativeOffset.float * builder.charWidth, 0), vec2(builder.charWidth, builder.textHeight))

        let charBounds = cursorBounds
        if not isThickCursor:
          cursorBounds.w *= 0.2

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
              fillRect(rect(xyInterp, cursorBounds.wh), cursorForegroundColor)
            last = xy

          let dist = (cursorBounds.xy - last).length
          for i in 0..<dist.int:
            let xyInterp = mix(last, cursorBounds.xy, i.float / dist)
            fillRect(rect(xyInterp, cursorBounds.wh), cursorForegroundColor)

          fillRect(cursorBounds, cursorForegroundColor)
          if isThickCursor:
            let currentRune = self.document.runeAt(s.last)
            drawText($currentRune, charBounds, cursorBackgroundColor, 0.UINodeFlags)

        self.lastCursorLocationBounds = (cursorBounds + currentNode.boundsAbsolute.xy).some

      if i == self.selections.high:
        let dp = self.displayMap.toDisplayPoint(s.last.toPoint)
        let p = self.displayMap.toPoint(dp)
        let ob = self.displayMap.overlay.snapshot.toOverlayBytes(dp.OverlayPoint)
        let (foundDisplay, lastIndexDisplay) = state.chunkBounds.binarySearchRange(dp, Bias.Left, cmp)
        if lastIndexDisplay in 0..<state.chunkBounds.len and dp >= state.chunkBounds[lastIndexDisplay].displayRange.a:
          state.cursorOnScreen = true
          self.currentCenterCursor = s.last
          self.currentCenterCursorRelativeYPos = (state.chunkBounds[lastIndexDisplay].bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h
          self.lastHoverLocationBounds = state.chunkBounds[lastIndexDisplay].bounds.some

proc createTextLinesNew(self: TextDocumentEditor, builder: UINodeBuilder, app: App, currentNode: UINode, selectionsNode: UINode, backgroundColor: Color, textColor: Color, sizeToContentX: bool, sizeToContentY: bool) =
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
    currentNode.w = builder.charWidth
    min(self.document.rope.len.float * builder.charWidth, 500.0) # todo: figure out max height
  else:
    currentNode.bounds.w

  let parentHeight = if sizeToContentY:
    currentNode.h = builder.textHeight
    min(self.document.rope.lines.float * builder.textHeight, 500.0) # todo: figure out max height
  else:
    currentNode.bounds.h

  let enableSmoothScrolling = app.config.asConfigProvider.getValue("ui.smooth-scroll", true)
  let snapBehaviour = self.nextSnapBehaviour.get(self.defaultSnapBehaviour)
  let scrollSnapDistance: float = parentHeight * app.config.asConfigProvider.getValue("ui.scroll-snap-min-distance", 0.5)
  let smoothScrollSpeed: float = app.config.asConfigProvider.getValue("ui.smooth-scroll-speed", 15.0)

  self.scrollOffset = clamp(self.scrollOffset, (1.0 - self.numDisplayLines.float) * builder.textHeight, parentHeight - builder.textHeight)

  if enableSmoothScrolling:
    if self.interpolatedScrollOffset == self.scrollOffset:
      self.nextSnapBehaviour = ScrollSnapBehaviour.none
    elif snapBehaviour == ScrollSnapBehaviour.Always:
      self.interpolatedScrollOffset = self.scrollOffset
      self.nextSnapBehaviour = ScrollSnapBehaviour.none
    elif snapBehaviour in {ScrollSnapBehaviour.MinDistanceOffscreen, MinDistanceCenter} and abs(self.interpolatedScrollOffset - self.scrollOffset) > scrollSnapDistance:
      if snapBehaviour == ScrollSnapBehaviour.MinDistanceCenter:
        self.interpolatedScrollOffset = self.scrollOffset
        self.nextSnapBehaviour = ScrollSnapBehaviour.none
      else:
        self.interpolatedScrollOffset = self.scrollOffset + sign(self.interpolatedScrollOffset - self.scrollOffset) * scrollSnapDistance
        self.markDirty()
    else:
      let alpha = 1 - exp(-smoothScrollSpeed * app.platform.deltaTime)
      self.interpolatedScrollOffset = mix(self.interpolatedScrollOffset, self.scrollOffset, alpha)
      if abs(self.interpolatedScrollOffset - self.scrollOffset) < 1:
        self.interpolatedScrollOffset = self.scrollOffset
        self.nextSnapBehaviour = ScrollSnapBehaviour.none
      self.markDirty()

  else:
    self.interpolatedScrollOffset = self.scrollOffset
    self.nextSnapBehaviour = ScrollSnapBehaviour.none

  let inclusive = app.config.getOption[:bool]("editor.text.inclusive-selection", false)
  let drawChunks = app.config.getOption[:bool]("editor.text.draw-chunks", false)

  let charWidth = builder.charWidth
  let isThickCursor = self.isThickCursor

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let showContextLines = not renderDiff and app.config.getOption[:bool]("editor.text.context-lines", true)

  let selectionColor = app.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let contextBackgroundColor = app.theme.color(@["breadcrumbPicker.background", "background"], color(50/255, 70/255, 70/255))
  let insertedTextBackgroundColor = app.theme.color(@["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"], color(0.1, 0.2, 0.1))
  let deletedTextBackgroundColor = app.theme.color(@["diffEditor.removedTextBackground", "diffEditor.removedLineBackground"], color(0.2, 0.1, 0.1))
  var changedTextBackgroundColor = app.theme.color(@["diffEditor.changedTextBackground", "diffEditor.changedLineBackground"], color(0.2, 0.2, 0.1))
  let commentColor = app.theme.tokenColor("comment", textColor)

  # line numbers
  let lineNumbers = self.lineNumbers.get app.config.getOption[:LineNumbers]("editor.text.line-numbers", LineNumbers.Absolute)
  let maxLineNumber = case lineNumbers
    of LineNumbers.Absolute: self.document.numLines
    of LineNumbers.Relative: 99
    else: 0
  let maxLineNumberLen = ($maxLineNumber).len + 1
  let cursorLine = self.selection.last.line
  let cursorDisplayLine = self.displayMap.toDisplayPoint(self.selection.last.toPoint).row.int

  let lineNumberPadding = builder.charWidth
  let lineNumberBounds = if lineNumbers != LineNumbers.None:
    vec2(maxLineNumberLen.float32 * builder.charWidth, 0)
  else:
    vec2()

  let lineNumberWidth = if lineNumbers != LineNumbers.None:
    (lineNumberBounds.x + lineNumberPadding).ceil
  else:
    0.0

  let scrollOffset = self.interpolatedScrollOffset
  var startLine = max((-scrollOffset / builder.textHeight).int - 1, 0)
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

  let highlight = app.config.asConfigProvider.getValue("ui.highlight", true)

  var iter = self.displayMap.iter()
  if self.document.tsTree.isNotNil and self.document.highlightQuery.isNotNil and highlight:
    iter.styledChunks.highlighter = Highlighter(query: self.document.highlightQuery, tree: self.document.tsTree).some
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

  let mainOffset = if renderDiff:
    floor(parentWidth * 0.5)
  else:
    0

  var state = LineDrawerState(
    builder: builder,
    displayMap: self.displayMap,
    bounds: rect(mainOffset, 0, parentWidth - mainOffset, parentHeight),
    offset: vec2(lineNumberWidth + mainOffset, scrollOffset - startLineOffsetFromScrollOffset + (iter.displayPoint.row.int - startLine).float * builder.textHeight),
    lastDisplayPoint: iter.displayPoint,
    lastDisplayEndPoint: iter.displayPoint,
    lastPoint: iter.point,
    cursorOnScreen: false,
    reverse: true,
  )

  var diffState = LineDrawerState(
    builder: builder,
    displayMap: self.diffDisplayMap,
    bounds: rect(0, 0, mainOffset, parentHeight),
    offset: vec2(lineNumberWidth, scrollOffset - startLineOffsetFromScrollOffset + (diffIter.displayPoint.row.int - startLine).float * builder.textHeight),
    lastDisplayPoint: diffIter.displayPoint,
    lastDisplayEndPoint: diffIter.displayPoint,
    lastPoint: diffIter.point,
    cursorOnScreen: false,
    reverse: false,
  )

  self.lastRenderedChunks.setLen(0)

  selectionsNode.renderCommands.clear()
  currentNode.renderCommands.clear()
  currentNode.renderCommands.spacesColor = commentColor
  buildCommands(currentNode.renderCommands):

    proc drawChunk(chunk: DisplayChunk, state: var LineDrawerState): LineDrawerResult =
      let external = chunk.styledChunk.chunk.external
      if state.reverse and not external:
        self.lastRenderedChunks.add((chunk.point...chunk.endPoint, chunk.displayPoint...chunk.displayEndPoint))

      if state.lastPoint.row != chunk.point.row and not external:
        state.addedLineNumber = false

      while state.lastDisplayPoint.row < chunk.displayPoint.row:
        if state.lastDisplayEndPoint.column == 0:
          if state.displayMap.diffMap.snapshot.isEmptySpace(state.lastDisplayPoint.DiffPoint):
            fillRect(rect(state.bounds.x + lineNumberWidth, state.offset.y, state.bounds.w - lineNumberWidth, builder.textHeight), backgroundColor.darken(0.03))

        state.lastDisplayPoint.row += 1
        state.lastDisplayPoint.column = 0
        state.lastDisplayEndPoint.row += 1
        state.lastDisplayEndPoint.column = 0
        state.offset.y += state.builder.textHeight
        state.offset.x = state.bounds.x + lineNumberWidth

      if renderDiff and state.lastDisplayEndPoint.column == 0 and self.diffChanges.isSome:
        let diffRow = self.diffChanges.get.mapLine(chunk.point.row.int, state.reverse)
        if diffRow.getSome(d):
          if d.changed:
            fillRect(rect(state.bounds.x + lineNumberWidth, state.offset.y, state.bounds.w - lineNumberWidth, builder.textHeight), changedTextBackgroundColor)
        else:
          let color = if state.reverse: insertedTextBackgroundColor else: deletedTextBackgroundColor
          fillRect(rect(state.bounds.x + lineNumberWidth, state.offset.y, state.bounds.w - lineNumberWidth, builder.textHeight), color)

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
        currentNode.renderCommands.drawLineNumber(state.builder, chunk.point.row.int, vec2(state.bounds.x, state.offset.y), cursorLine, lineNumbers, lineNumberBounds, textColor)

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

        let textColor = if chunk.scope.len == 0: textColor else: app.theme.tokenColor(chunk.scope, textColor)
        var flags = 0.UINodeFlags
        if chunk.styledChunk.drawWhitespace:
          flags.incl UINodeFlag.TextDrawSpaces
        drawText(chunk.toOpenArray, arrangementIndex, bounds, textColor, flags)
        state.offset.x += width
        if sizeToContentY:
          currentNode.h = max(currentNode.h, bounds.yh)

        if drawChunks:
          drawRect(bounds, color(1, 0, 0))

        # if not external and self.selection.last.toPoint in chunk.point...chunk.endPoint:
        #   debugf"{chunk}  |  {self.selection.last.toPoint} -> {self.displayMap.toDisplayPoint(self.selection.last.toPoint)}"

      else:
        # todo: use display points for chunkBounds, or both?
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

      if state.chunkBounds.len > 1000000:
        assert false, "Rendering too much text, your font size is too small or there is a bug"

      case drawChunk(chunk, state)
      of Continue: discard
      of ContinueNextLine: iter.seekLine(chunk.displayPoint.row.int + 1)
      of Break: break

    if showContextLines and contextLines.len > 0:
      let startDisplayPoint = self.displayMap.toDisplayPoint(point(contextLines.last, 0))
      var contextLinesIter = self.displayMap.iter()
      if self.document.tsTree.isNotNil and self.document.highlightQuery.isNotNil and highlight:
        contextLinesIter.styledChunks.highlighter = Highlighter(query: self.document.highlightQuery, tree: self.document.tsTree).some
      var contextLinesState = LineDrawerState(
        builder: builder,
        displayMap: self.displayMap,
        bounds: rect(mainOffset, 0, parentWidth - mainOffset, parentHeight),
        offset: vec2(lineNumberWidth + mainOffset, 0),
        lastDisplayPoint: startDisplayPoint,
        lastDisplayEndPoint: startDisplayPoint,
        lastPoint: point(contextLines.last, 0),
        cursorOnScreen: false,
        reverse: true,
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
          fillRect(rect(contextLinesState.bounds.x, (contextLines.high - i).float * builder.textHeight, contextLinesState.bounds.w, builder.textHeight), backgroundColor.lighten(0.05))
          contextLinesState.offset.x = lineNumberWidth + mainOffset
          contextLinesState.offset.y += builder.textHeight
          contextLinesState.lastDisplayPoint = nextDisplayPoint
          contextLinesState.lastDisplayEndPoint = nextDisplayPoint
          contextLinesState.lastPoint = nextPoint
          contextLinesState.addedLineNumber = false
          continue

        case drawChunk(chunk, contextLinesState)
        of Continue: discard
        of ContinueNextLine: discard
        of Break: break

    if renderDiff:
      startScissor(diffState.bounds)
      while diffIter.next().getSome(chunk):
        case drawChunk(chunk, diffState)
        of Continue: discard
        of ContinueNextLine: diffIter.seekLine(chunk.displayPoint.row.int + 1)
        of Break: break
      endScissor()

  self.drawCursors(builder, app, currentNode, currentNode.renderCommands, state)

  var ropeCursor = self.displayMap.buffer.visibleText.cursorT(Point)
  var highlightIter = self.displayMap.iter()
  let visibleTextRange = self.visibleTextRange(2)
  for selections in self.customHighlights.values:
    for s in selections:
      var sn = s.selection.normalized
      if sn.last < visibleTextRange.first or sn.first > visibleTextRange.last:
        continue
      let color = app.theme.color(s.color, color(200/255, 200/255, 200/255)) * s.tint
      self.drawHighlight(builder, sn, color, selectionsNode.renderCommands, state.chunkBounds, highlightIter, ropeCursor)

  for s in self.selections:
    var sn = s.normalized
    if isThickCursor and inclusive:
      sn.last.column += 1
    if sn.last < visibleTextRange.first or sn.first > visibleTextRange.last:
      continue

    self.drawHighlight(builder, sn, selectionColor, selectionsNode.renderCommands, state.chunkBounds, highlightIter, ropeCursor)

  selectionsNode.markDirty(builder)
  currentNode.markDirty(builder)

  proc handleMouseEvent(self: TextDocumentEditor, btn: MouseButton, pos: Vec2, drag: bool) =
    if self.document.isNil:
      return

    var (found, index) = state.chunkBounds.binarySearchRange(pos, Bias.Left, cmp)
    if index notin 0..state.chunkBounds.high:
      return

    if index + 1 < state.chunkBounds.len and pos.y >= state.chunkBounds[index].bounds.yh and pos.y < state.chunkBounds[index + 1].bounds.yh:
      index += 1

    self.lastPressedMouseButton = btn

    if btn notin {MouseButton.Left, DoubleClick, TripleClick}:
      return
    # if line >= self.document.numLines:
    #   return

    let chunk = state.chunkBounds[index]

    let posAdjusted = if self.isThickCursor(): pos else: pos + vec2(builder.charWidth * 0.5, 0)
    let searchPosition = vec2(posAdjusted.x - chunk.bounds.x, 0)
    var (charFound, charIndex) = state.charBounds.toOpenArray(chunk.charsRange.a, chunk.charsRange.b - 1).binarySearchRange(searchPosition, Left, cmp)

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
        self.runSingleClickCommand()
      elif btn == DoubleClick:
        self.runDoubleClickCommand()
      elif btn == TripleClick:
        self.runTripleClickCommand()

    self.updateTargetColumn(Last)
    self.layout.tryActivateEditor(self)
    self.markDirty()

  builder.panel(&{UINodeFlag.FillX, FillY}):
    onClickAny btn:
      self.handleMouseEvent(btn, pos, drag = false)
    onDrag MouseButton.Left:
      self.handleMouseEvent(MouseButton.Left, pos, drag = true)

  # Get center line
  if not state.cursorOnScreen:
    # todo: move this to a function
    let centerPos = currentNode.bounds.wh * 0.5 + vec2(0, builder.textHeight * -0.5)
    var (found, index) = state.chunkBounds.binarySearchRange(centerPos, Bias.Left, cmp)
    if index notin 0..state.chunkBounds.high:
      return

    if index + 1 < state.chunkBounds.len and centerPos.y >= state.chunkBounds[index].bounds.yh and centerPos.y < state.chunkBounds[index + 1].bounds.yh:
      index += 1

    let chunk = state.chunkBounds[index]
    let centerPoint = (chunk.range.a.row.int, (chunk.range.a.column + chunk.range.b.column).int div 2)
    self.currentCenterCursor = centerPoint
    self.currentCenterCursorRelativeYPos = (chunk.bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h

method createUI*(self: TextDocumentEditor, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.preRender(builder.currentParent.bounds)

  let dirty = self.dirty
  self.resetDirty()

  let logNewRenderer = app.config.getOption[:bool]("ui.new-log", false)
  let transparentBackground = app.config.getOption[:bool]("ui.background.transparent", false)
  let darkenInactive = app.config.getOption[:float]("text.background.inactive-darken", 0.025)

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: app.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: app.theme.color("editor.background", color(25/255, 25/255, 25/255)).darken(darkenInactive)

  if transparentBackground:
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  var headerColor = if self.active: app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))

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

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId):
    onClickAny btn:
      self.layout.tryActivateEditor(self)

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.currentMode, self.document, headerColor, textColor):
          onRight:
            proc cursorString(cursor: Cursor): string = $cursor.line & ":" & $cursor.column & ":" & $self.document.buffer.visibleText.runeIndexInLine(cursor)
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

        builder.panel(sizeFlags + &{FillBackground, MaskContent}, backgroundColor = backgroundColor):
          var selectionsNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}):
            selectionsNode = currentNode
            selectionsNode.renderCommands.clear()

          onScroll:
            self.scrollText(delta.y * app.config.asConfigProvider.getValue("text.scroll-speed", 40.0))


          var t = startTimer()

          self.createTextLinesNew(builder, app, currentNode, selectionsNode, backgroundColor, textColor, sizeToContentX, sizeToContentY)

          let e = t.elapsed.ms
          if logNewRenderer:
            debugf"Render new took {e} ms"

          self.lastContentBounds = currentNode.bounds

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))

  if self.showHover:
    result.add proc() =
      self.createHover(builder, app, self.lastHoverLocationBounds.get(rect(100, 100, 10, 10)))

proc shouldIgnoreAsContextLine(self: TextDocument, line: int): bool =
  if line == 0 or self.languageConfig.isNone:
    return false

  let indent = self.getIndentLevelForLine(line)
  if self.getIndentLevelForLine(line - 1) < indent:
    return false

  if self.languageConfig.get.ignoreContextLinePrefix.isSome:
    return self.rope.lineStartsWith(line, self.languageConfig.get.ignoreContextLinePrefix.get, true)

  if self.languageConfig.get.ignoreContextLineRegex.isSome:
    # todo: don't use getLine
    return ($self.getLine(line)).match(self.languageConfig.get.ignoreContextLineRegex.get)

  return false

proc clampToLine(document: TextDocument, selection: Selection, line: StyledLine): tuple[first: RuneIndex, last: RuneIndex] =
  result.first = if selection.first.line < line.index:
    0.RuneIndex
  elif selection.first.line == line.index:
    document.buffer.visibleText.runeIndexInLine(selection.first)
  else: line.runeLen.RuneIndex

  result.last = if selection.last.line < line.index:
    0.RuneIndex
  elif selection.last.line == line.index:
    document.buffer.visibleText.runeIndexInLine(selection.last)
  else:
    line.runeLen.RuneIndex
