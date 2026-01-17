import std/[strformat, tables, strutils, math, options, json, sugar, sequtils, algorithm]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, rope_utils, timer, generational_seq, binary_encoder, render_command, arena, array_view]
import text/text_editor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, document_editor, theme, config_provider, layout
import text/language/[lsp_types]
import text/[diff, custom_treesitter, syntax_map, overlay_map, wrap_map, diff_map, display_map]
import view
import scroll_box

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
    displayChunk: DisplayChunk
    charsRange: rope.Range[int]
    renderCommandIndex: int = -1

  LineBounds = object
    textBounds: Rect
    line: int
    chunks: ArrayView[ChunkBounds]
    lineNumberRenderCommandIndex: int = -1
    dontCenter: bool

  LineDrawerResult = enum Continue, ContinueNextLine, Break
  LineDrawerState = object
    # State required for rendering, readonly
    platform: Platform
    builder: UINodeBuilder
    displayMap: DisplayMap
    diffDisplayMap: DisplayMap
    bounds: Rect
    absoluteBounds: Rect
    diffReverse: bool
    fillLineNumberBackground: bool
    lineNumberBackgroundColor: Color
    insertedTextBackgroundColor: Color
    deletedTextBackgroundColor: Color
    changedTextBackgroundColor: Color
    errorColor: Color
    warningColor: Color
    informationColor: Color
    hintColor: Color

    textColor: Color
    backgroundColor: Color
    signColumnWidth: int
    signColumnPixelWidth: float
    lineNumberWidth: float
    lineNumberBounds: Vec2
    signShow: SignColumnShowKind
    cursorLine: int
    cursorDisplayLine: int
    diffChanges: ptr seq[LineMapping] = nil
    customOverlayRenderers: ptr GenerationalSeq[CustomOverlayRenderer, CustomRendererId] = nil
    signs: ptr Table[int, seq[tuple[id: Id, group: string, text: string, tint: Color, color: string, width: int]]] = nil
    diagnosticsPerLS: ptr seq[DiagnosticsData] = nil
    lineNumbers: LineNumbers
    createIter: proc(): DisplayChunkIterator {.gcsafe, raises: [].}
    renderDiff: bool

    # Temporary state which is updated while rendering
    offset: Vec2
    lastDisplayEndPoint: DisplayPoint
    lastPoint: Point
    currentlyDrawnLine: int = -1
    lineBounds: Rect
    customRendererChunksBelow: seq[OverlayChunk]
    customRendererChunksAbove: seq[OverlayChunk]
    chunkBoundsPerLine: ArrayView[LineBounds]

    # Output state computed while rendering
    cursorOnScreen: bool
    charBounds: ArrayView[Rect]
    chunkBounds: ArrayView[ChunkBounds]
    numDrawnChunks: int

proc cmp(r: ChunkBounds, point: Point): int =
  let range = if r.displayChunk.styledChunk.chunk.external:
    # r.range.a...r.range.a
    r.displayChunk.point...(r.displayChunk.point + point(0, r.displayChunk.styledChunk.chunk.lenOriginal))
  else:
    r.displayChunk.point...(r.displayChunk.point + point(0, r.displayChunk.styledChunk.chunk.lenOriginal))

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

proc getScreenPos(self: TextDocumentEditor, builder: UINodeBuilder, state: var LineDrawerState, cursor: Cursor): Option[Vec2] =
  let dp = self.displayMap.toDisplayPoint(cursor.toPoint)
  let (_, lastIndexDisplay) = state.chunkBounds.toOpenArray().binarySearchRange(dp, Bias.Left, cmp)
  if lastIndexDisplay in 0..<state.chunkBounds.len and dp >= state.chunkBounds[lastIndexDisplay].displayRange.a:
    let offset = (dp - state.chunkBounds[lastIndexDisplay].displayRange.a).toPoint.column.float * builder.charWidth
    let chunkBounds = state.chunkBounds[lastIndexDisplay].bounds
    return vec2(state.absoluteBounds.x + chunkBounds.x + offset, state.absoluteBounds.y + chunkBounds.y).some
  return Vec2.none

proc createHover(self: TextDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
  let backgroundColor = builder.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = builder.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
  let activeHoverColor = builder.theme.color("editor.foreground", color(1, 1, 1))

  var bounds = rect(cursorBounds.xy, vec2())
  var outerSizeFlags = &{SizeToContentX, SizeToContentY}
  var innerSizeFlags = &{SizeToContentX, SizeToContentY}

  if self.hoverView != nil and self.hoverView.detached:
    bounds = self.hoverView.absoluteBounds
    outerSizeFlags = 0.UINodeFlags
    innerSizeFlags = &{FillX, FillY}

  var hoverPanel: UINode = nil
  builder.panel(&{MaskContent, FillBackground, DrawBorder, DrawBorderTerminal, SnapInitialBounds, LayoutVertical, MouseHover} + outerSizeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = backgroundColor, borderColor = borderColor, border = border(1), tag = "hover", pivot = vec2()):
    hoverPanel = currentNode

    if self.hoverView != nil:
      builder.panel(innerSizeFlags):
        discard self.hoverView.createUI(builder)
    else:
      for line in self.hoverText.splitLines:
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = line, textColor = activeHoverColor)

  if self.hoverView == nil or not self.hoverView.detached:
    var clampedX = cursorBounds.x
    if clampedX + hoverPanel.bounds.w > builder.root.w:
      clampedX = max(builder.root.w - hoverPanel.bounds.w, 0)

    hoverPanel.rawX = clampedX
    hoverPanel.rawY = cursorBounds.y
    hoverPanel.pivot = vec2(0, 1)

proc createSignatureHelp(self: TextDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
  let backgroundColor = builder.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = builder.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
  let textColor = builder.theme.color("editor.foreground", color(1, 1, 1))
  let fadedTextColor1 = builder.theme.color("editor.foreground.fade1", textColor.darken(0.15))
  let fadedTextColor2 = builder.theme.color("editor.foreground.fade2", fadedTextColor1.darken(0.15))
  let highlightedTextColor = builder.theme.color("editor.foreground.highlight", textColor.lighten(0.15))

  let activeParamColor = builder.theme.color("signatureHelp.activeParam", highlightedTextColor)
  let activeSignatureColor = builder.theme.color("signatureHelp.activeSignature", textColor)
  let inactiveParamColor = builder.theme.color("signatureHelp.inactiveParam", fadedTextColor1)
  let inactiveSignatureColor = builder.theme.color("signatureHelp.inactiveSignature", fadedTextColor2)

  proc drawSignature(signatureColor: Color, activeParamColor: Color, sig: lsp_types.SignatureInformation) =
    let activeParameter = sig.activeParameter.get(self.currentSignatureParam)
    builder.panel(&{SizeToContentY, SizeToContentX, LayoutHorizontal}):
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = "(", textColor = signatureColor)
      for i, p in sig.parameters:
        if i > 0:
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = ", ", textColor = signatureColor)
        var paramStr = ""
        if p.label.kind == JString:
          paramStr = p.label.getStr
        else:
          paramStr = $p.label
        var paramColor = signatureColor
        if i == activeParameter:
          paramColor = activeParamColor
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = paramStr, textColor = paramColor)

      builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = ")", textColor = signatureColor)

  var signatureHelpPanel: UINode = nil
  builder.panel(&{SizeToContentX, SizeToContentY, MaskContent, FillBackground, DrawBorder, DrawBorderTerminal, SnapInitialBounds, LayoutVertical, MouseHover}, backgroundColor = backgroundColor, borderColor = borderColor, border = border(1), userId = self.signatureHelpId.newPrimaryId, tag = "signature"):
    signatureHelpPanel = currentNode

    var i = 0
    for k, sig in self.signatures:
      if k != self.currentSignature:
        drawSignature(inactiveSignatureColor, inactiveParamColor, sig)
        inc i
        if i > 5:
          break

    if self.currentSignature in 0..self.signatures.high:
      drawSignature(activeSignatureColor, activeParamColor, self.signatures[self.currentSignature])

    if self.signatures.len == 0:
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = "No signatures", textColor = activeSignatureColor)

  var clampedX = cursorBounds.x
  if clampedX + signatureHelpPanel.bounds.w > builder.root.w:
    clampedX = max(builder.root.w - signatureHelpPanel.bounds.w, 0)

  signatureHelpPanel.rawX = clampedX
  signatureHelpPanel.rawY = cursorBounds.y
  signatureHelpPanel.pivot = vec2(0, 1)

proc createCompletions(self: TextDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let transparentBackground = self.uiSettings.background.transparent.get()
  var backgroundColor = builder.theme.color(@["editorSuggestWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = builder.theme.color(@["editorSuggestWidget.border", "panel.background"], color(30/255, 30/255, 30/255))
  let selectedBackgroundColor = builder.theme.color(@["editorSuggestWidget.selectedBackground", "list.activeSelectionBackground"], color(200/255, 200/255, 200/255))
  let docsColor = builder.theme.color(@["editorSuggestWidget.foreground", "editor.foreground"], color(1, 1, 1))
  let nameColor = builder.theme.color(@["editorSuggestWidget.foreground", "editor.foreground"], color(1, 1, 1))
  let nameSelectedColor = builder.theme.color(@["editorSuggestWidget.highlightForeground", "editor.foreground"], color(1, 1, 1))
  let scopeColor = builder.theme.color(@["descriptionForeground", "editor.foreground"], color(175/255, 1, 175/255))

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
  builder.panel(&{SizeToContentX, SizeToContentY, MaskContent}, x = cursorBounds.x, y = top, pivot = vec2(0, 0), userId = self.completionsId.newPrimaryId, tag = "completions"):
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
    builder.panel(&{UINodeFlag.MaskContent, DrawBorder, DrawBorderTerminal, SizeToContentX}, border = border(1), h = completionPanelHeight, backgroundColor = backgroundColor, borderColor = borderColor):
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
        builder.panel(&{UINodeFlag.FillBackground, DrawText, MaskContent, TextWrap, DrawBorder, DrawBorderTerminal},
          x = listNode.xw, w = docsWidth * charWidth, h = listNode.h, border = border(1),
          backgroundColor = backgroundColor, textColor = docsColor, text = docText, borderColor = borderColor)

  if completionsPanel.bounds.yh > completionsPanel.parent.bounds.h:
    completionsPanel.rawY = cursorBounds.y
    completionsPanel.pivot = vec2(0, 1)

  if completionsPanel.bounds.xw > completionsPanel.parent.bounds.w:
    completionsPanel.rawX = max(completionsPanel.parent.bounds.w - completionsPanel.bounds.w, 0)

proc drawHighlight(self: TextDocumentEditor, builder: UINodeBuilder, sn: Selection, color: Color, renderCommands: var RenderCommands, state: var LineDrawerState, cursor: var RopeCursorT[Point]) =

  let r = sn.first.toPoint...sn.last.toPoint

  let (_, firstIndexNormalized) = state.chunkBounds.toOpenArray().binarySearchRange(r.a, Bias.Right, cmp)
  let (_, lastIndexNormalized) = state.chunkBounds.toOpenArray().binarySearchRange(r.b, Bias.Right, cmp)
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
        let ropeChunk = bounds.displayChunk.styledChunk.chunk
        let rangeOriginal = ropeChunk.point...(ropeChunk.point + point(0, ropeChunk.lenOriginal))

        let firstOffset = if bounds.displayChunk.styledChunk.chunk.external and r.a.column.int < rangeOriginal.a.column.int:
          0
        elif bounds.displayChunk.styledChunk.chunk.external and r.a.column.int >= rangeOriginal.b.column.int:
          bounds.displayChunk.toOpenArray.runeLen.int
        elif lineEmpty:
          0
        elif r.a in rangeOriginal:
          bounds.displayChunk.styledChunk.chunk.toOpenArrayOriginal.offsetToCount(r.a.column.int - rangeOriginal.a.column.int).int
        elif r.a < rangeOriginal.a:
          0
        else:
          bounds.displayChunk.toOpenArray.runeLen.int

        let lastOffset = if bounds.displayChunk.styledChunk.chunk.external and r.b.column.int > rangeOriginal.b.column.int:
          bounds.displayChunk.toOpenArray.runeLen.int
        elif lineEmpty:
          1
        elif r.b in rangeOriginal:
          bounds.displayChunk.styledChunk.chunk.toOpenArrayOriginal.offsetToCount(r.b.column.int - rangeOriginal.a.column.int).int
        elif r.b < rangeOriginal.a:
          0
        else:
          bounds.displayChunk.toOpenArray.runeLen.int

        if firstOffset == lastOffset:
          continue

        var selectionBounds = rect(
          (bounds.bounds.xy + vec2(firstOffset.float * builder.charWidth, 0)),
          (vec2((lastOffset - firstOffset).float * builder.charWidth, max(builder.textHeight, bounds.bounds.h))))

        let firstIndexClamped = firstOffset.clamp(0, bounds.charsRange.len - 1)
        let lastIndexClamped = lastOffset.clamp(0, bounds.charsRange.len)
        if firstIndexClamped != -1 and lastIndexClamped != -1:
          let firstBounds = state.charBounds[bounds.charsRange.a + firstIndexClamped] + bounds.bounds.xy
          let lastBounds = state.charBounds[bounds.charsRange.a + lastIndexClamped - 1] + bounds.bounds.xy
          selectionBounds = rect(firstBounds.xy, vec2(lastBounds.xw - firstBounds.x, max(builder.textHeight, bounds.bounds.h)))

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

proc toUINodeFlags(fontStyle: set[FontStyle]): UINodeFlags =
  var result = 0.UINodeFlags
  if Italic in fontStyle:
    result.incl TextItalic
  if Bold in fontStyle:
    result.incl TextBold

proc drawCursors(self: TextDocumentEditor, builder: UINodeBuilder, app: App, currentNode: UINode, renderCommands: var RenderCommands, state: var LineDrawerState) =
  if state.chunkBounds.len == 0:
    return

  let cursorForegroundColor = builder.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = builder.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let cursorTrailColor = cursorForegroundColor.darken(0.1)
  let cursorSpeed: float = self.uiSettings.cursorTrailSpeed.get()
  let cursorTrail: int = self.uiSettings.cursorTrailLength.get()
  let isThickCursor = self.isThickCursor
  let debugBounds = self.config.get("debug.log-chunk-bounds", false)

  buildCommands(renderCommands):
    self.cursorHistories.setLen(self.selections.len)

    # debugf"==================="
    for i, s in self.selections:
      let p = s.last.toPoint
      let (_, initialIndex) = state.chunkBounds.toOpenArray().binarySearchRange(p, Bias.Left, cmp)

      var lastIndex = initialIndex
      if lastIndex > 0 and p in state.chunkBounds[lastIndex - 1].range and not state.chunkBounds[lastIndex - 1].displayChunk.styledChunk.chunk.external:
        dec lastIndex

      var currentExternal = state.chunkBounds[lastIndex].displayChunk.styledChunk.chunk.external
      while lastIndex < state.chunkBounds.high:
        if not currentExternal and p < state.chunkBounds[lastIndex].range.b:
          break
        let nextExternal = state.chunkBounds[lastIndex + 1].displayChunk.styledChunk.chunk.external
        if not nextExternal and p < state.chunkBounds[lastIndex + 1].range.a:
          break

        currentExternal = nextExternal
        inc lastIndex
      # debugf"{p} -> {initialIndex} -> {lastIndex}"
      if not (p in state.chunkBounds[lastIndex].range):
        # Scanning forwards didn't find another valid chunk, so use the first one. This can happen for
        # inlays on empty lines, when the cursor is before the inlay
        # debugf"xvlc"
        lastIndex = initialIndex

      if lastIndex in 0..<state.chunkBounds.len and p in state.chunkBounds[lastIndex].range:
        let chunk = state.chunkBounds[lastIndex]
        # if lastIndex + 2 < state.chunkBounds.len:
        #   echo &"  {chunk}\n  {state.chunkBounds[lastIndex + 1]}\n  {state.chunkBounds[lastIndex + 2]}"

        let relativeOffset = p.column.int - chunk.range.a.column.int
        let runeOffset = if p.column.int == chunk.range.b.column.int:
          chunk.displayChunk.styledChunk.chunk.toOpenArrayOriginal.runeLen.int
        else:
          chunk.displayChunk.styledChunk.chunk.toOpenArrayOriginal.offsetToCount(relativeOffset).int
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

          cursorBounds.h = chunk.bounds.h

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
              let textFlags = chunk.displayChunk.styledChunk.fontStyle.toUINodeFlags
              let fontScale = chunk.displayChunk.styledChunk.fontScale
              drawText($currentRune, charBounds, cursorBackgroundColor, textFlags, fontScale)

        self.lastCursorLocationBounds = (cursorBounds + currentNode.boundsAbsolute.xy).some

        # if i == self.selections.high:
        #   if cursorBounds.x > currentNode.w - currentNode.x - 5 * builder.charWidth:
        #     self.scrollOffset.x += cursorBounds.x - (currentNode.w - currentNode.x - 5 * builder.charWidth)
        #   if cursorBounds.x < 5 * builder.charWidth:
        #     self.scrollOffset.x += cursorBounds.x
        #   self.scrollOffset.x = max(self.scrollOffset.x, 0)

      if i == self.selections.high:
        let dp = self.displayMap.toDisplayPoint(s.last.toPoint)
        let (_, lastIndexDisplay) = state.chunkBounds.toOpenArray().binarySearchRange(dp, Bias.Left, cmp)
        if lastIndexDisplay in 0..<state.chunkBounds.len and dp >= state.chunkBounds[lastIndexDisplay].displayRange.a:
          state.cursorOnScreen = true
          self.currentCenterCursor = s.last
          self.currentCenterCursorRelativeYPos = (state.chunkBounds[lastIndexDisplay].bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h

  let hoverScreenPos = self.getScreenPos(builder, state, self.hoverLocation)
  if hoverScreenPos.isSome:
    self.lastHoverLocationBounds = rect(hoverScreenPos.get.x, hoverScreenPos.get.y, builder.charWidth, builder.textHeight).some

  let signatureHelpScreenPos = self.getScreenPos(builder, state, self.signatureHelpLocation)
  if signatureHelpScreenPos.isSome:
    self.lastSignatureHelpLocationBounds = rect(signatureHelpScreenPos.get.x, signatureHelpScreenPos.get.y, builder.charWidth, builder.textHeight).some

proc drawChunk(chunk: DisplayChunk, state: var LineDrawerState, commands: var RenderCommands): LineDrawerResult =
  inc state.numDrawnChunks
  var outLineBounds = state.chunkBoundsPerLine[^1].addr
  if outLineBounds.chunks.len >= outLineBounds.chunks.cap:
    return LineDrawerResult.Break

  if chunk.displayPoint.column > state.lastDisplayEndPoint.column:
    state.offset.x += (chunk.displayPoint.column - state.lastDisplayEndPoint.column).float * state.builder.charWidth

  if state.offset.x >= state.bounds.xw:
    return LineDrawerResult.ContinueNextLine

  if not chunk.styledChunk.chunk.external:
    state.lastPoint = chunk.point
  state.lastDisplayEndPoint = chunk.displayEndPoint

  if chunk.len > 0:
    let (textColor, fontStyle, fontScale) = (chunk.styledChunk.color, chunk.styledChunk.fontStyle, chunk.styledChunk.fontScale)
    let textFlags = fontStyle.toUINodeFlags

    let font = state.platform.getFontInfo(state.platform.fontSize * fontScale, textFlags)
    let arrangementIndex = commands.typeset(chunk.toOpenArray, font)
    let layoutBounds = commands.layoutBounds(arrangementIndex)
    let width = layoutBounds.x
    let indices {.cursor.} = commands.arrangements[arrangementIndex]
    var bounds = rect(state.offset, vec2(width, state.builder.lineHeight))
    bounds.h = max(bounds.h, layoutBounds.y)
    bounds.h += state.builder.lineGap
    let charBoundsStart = state.charBounds.len
    outLineBounds.chunks.add ChunkBounds(
      range: chunk.point...chunk.endPoint,
      displayRange: chunk.displayPoint...chunk.endDisplayPoint,
      bounds: bounds,
      text: chunk.styledChunk.chunk,
      displayChunk: chunk,
      charsRange: charBoundsStart...(charBoundsStart + indices.selectionRects.len),
      renderCommandIndex: commands.commands.len,
    )
    if state.charBounds.len + indices.selectionRects.b - indices.selectionRects.a + 1 <= state.charBounds.cap:
      state.charBounds.add commands.arrangement.selectionRects.toOpenArray(indices.selectionRects.a, indices.selectionRects.b)

    let (underlineColor, underlineFlags) = if chunk.styledChunk.underline.getSome(underline):
      (underline.color, &{TextUndercurl})
    else:
      (color(1, 1, 1), 0.UINodeFlags)

    var flags = underlineFlags + textFlags
    if chunk.styledChunk.drawWhitespace:
      flags.incl UINodeFlag.TextDrawSpaces
    buildCommands(commands):
      drawText(chunk.toOpenArray, arrangementIndex, bounds, textColor, flags, underlineColor, fontScale)
    state.offset.x += width

  else:
    outLineBounds.chunks.add ChunkBounds(
      range: chunk.point...chunk.endPoint,
      displayRange: chunk.displayPoint...chunk.endDisplayPoint,
      bounds: rect(state.offset, vec2(state.builder.charWidth, state.builder.textHeight)),
      text: chunk.styledChunk.chunk,
      displayChunk: chunk,
      charsRange: state.charBounds.len...state.charBounds.len,
      # renderCommandIndex: commands.commands.len,
    )

  let chunkBounds = outLineBounds.chunks[^1].bounds
  state.lineBounds.w = max(state.lineBounds.w, chunkBounds.xw)
  state.lineBounds.h = max(state.lineBounds.h, chunkBounds.yh)
  outLineBounds.textBounds.w = max(outLineBounds.textBounds.w, chunkBounds.xw)
  outLineBounds.textBounds.h = max(outLineBounds.textBounds.h, chunkBounds.yh)

  let customRenderId = chunk.diffChunk.inputChunk.inputChunk.inputChunk.renderId
  if customRenderId != 0 and state.customOverlayRenderers != nil:
    let customRenderLocation = chunk.diffChunk.inputChunk.inputChunk.inputChunk.location
    case customRenderLocation
    of Inline:
      let cb = state.customOverlayRenderers[].tryGet(customRenderId.CustomRendererId)
      if cb.isSome:
        commands.startTransform(chunkBounds.xy)
        let fun = (cb.get)
        let actualBounds = fun(customRenderId, vec2(chunkBounds.w, state.builder.textHeight), chunk.diffChunk.inputChunk.inputChunk.inputChunk.localOffset, commands)
        commands.endTransform()
        if actualBounds.y > state.builder.textHeight:
          outLineBounds.dontCenter = true
        state.lineBounds.h = max(state.lineBounds.h, actualBounds.y)
        if actualBounds.x > chunkBounds.w:
          state.offset.x += actualBounds.x - chunkBounds.w
    of Below:
      state.customRendererChunksBelow.add(chunk.diffChunk.inputChunk.inputChunk.inputChunk)
    of Above:
      state.customRendererChunksAbove.add(chunk.diffChunk.inputChunk.inputChunk.inputChunk)

  return LineDrawerResult.Continue

proc drawLine(state: var LineDrawerState, commands: var RenderCommands, iter: var DisplayChunkIterator, index: int): Option[Vec2] =
  if index < 0 or index > state.displayMap.endDisplayPoint.row.int:
    return Vec2.none
  if state.chunkBoundsPerLine.len >= state.chunkBoundsPerLine.cap:
    return Vec2.none

  let maxNumChunks = ceil(state.bounds.w / state.builder.charWidth).int + 5
  state.chunkBoundsPerLine.add LineBounds(
    line: index,
    chunks: state.builder.arena.allocEmptyArray(maxNumChunks, ChunkBounds)
  )

  # When drawing lines upwards we have to reset the iterator because it can iterate backwards
  if iter.displayPoint.row.int != index or not iter.didSeek:
    iter = state.createIter()
    iter.seekLine(index)
    discard iter.next()
    if iter.displayChunk.isSome:
      state.lastDisplayEndPoint = iter.displayChunk.get.displayPoint

  # Add a transform render command for which we later override the y offset to the correct y offset calculated by the
  # scroll box. Every render command for a line can then just use (0, 0) as the origin.
  commands.startTransform(vec2(0))
  defer:
    commands.endTransform()

  if iter.displayChunk.isNone or iter.displayChunk.get.displayPoint.row.int != index:
    return vec2(state.bounds.w, state.builder.textHeight).some

  let chunk {.cursor.} = iter.displayChunk.get

  # Check whether we are rendering the first display line of a given real line
  let point = state.displayMap.toPoint(displayPoint(index, 0))
  let firstDisplayLine = state.displayMap.toDisplayPoint(point(point.row.int, 0))
  let firstDisplayLineInRealLine = firstDisplayLine.row.int == index

  # Do some things (like line numbers) only on the first display line for a real line
  var drawDiagnostics = false
  if firstDisplayLineInRealLine:
    drawDiagnostics = true

    var doDrawLineNumber = true
    state.chunkBoundsPerLine[^1].lineNumberRenderCommandIndex = commands.commands.len
    commands.startTransform(vec2(0))

    # Draw signs
    if state.signs != nil:
      state.signs[].withValue(chunk.point.row.int, value):
        var bounds = rect(state.lineNumberWidth - state.signColumnPixelWidth, 0, state.signColumnPixelWidth, state.builder.textHeight)
        if state.signShow == SignColumnShowKind.Number:
          doDrawLineNumber = false
          bounds = rect(vec2(state.builder.charWidth, 0), state.lineNumberBounds)

          if state.fillLineNumberBackground:
            commands.fillRect(rect(vec2(0), state.lineNumberBounds), state.lineNumberBackgroundColor)

        var i = 0
        for s in value[]:
          if i + s.width > state.signColumnWidth:
            break

          var color = state.textColor
          if s.color != "":
            color = state.builder.theme.tokenColor(s.color, state.textColor)
          commands.drawText(s.text, bounds, color * s.tint, 0.UINodeFlags)
          bounds.x += state.builder.charWidth * s.width.float
          i += s.width

    # Draw line numbers
    if doDrawLineNumber:
      let lineNumber = chunk.point.row.int
      commands.drawLineNumber(state.builder, lineNumber, state.bounds.xy, state.cursorLine, state.lineNumbers, state.lineNumberBounds - vec2(state.signColumnPixelWidth, 0), state.textColor, state.lineNumberBackgroundColor, state.fillLineNumberBackground)
    commands.endTransform()

  # Iterate through chunks and render them until we reach the end or get a chunk which is on the next display line.
  state.offset = state.bounds.xy + vec2(state.lineNumberWidth, 0)
  state.lastDisplayEndPoint = displayPoint(index, 0)
  state.customRendererChunksBelow.setLen(0)
  state.customRendererChunksAbove.setLen(0)
  state.lineBounds = rect(0, 0, 0, 0)
  while iter.displayChunk.isSome:
    if iter.displayChunk.get.displayPoint.row.int > index:
      break
    # todo: this sometimes happens for a frame or two, probably because some data structures are in an invalid state
    # which causes an infinte loop here.
    # Just breaking and trying again will be fine for now, but the root cause should be fixed.
    if state.numDrawnChunks > 10000:
      log lvlWarn, "Rendering too much text, your font size is too small or there is a bug"
      break
    let res = drawChunk(iter.displayChunk.get, state, commands)
    discard iter.next()
    case res
    of Continue: discard
    of ContinueNextLine: break
    of Break: break

  var height = max(state.builder.textHeight, state.lineBounds.h)

  # # Draw chunks with custom render location Below
  for customRenderChunk in state.customRendererChunksBelow:
    let customRenderId = customRenderChunk.renderId
    let cb = state.customOverlayRenderers[].tryGet(customRenderId.CustomRendererId)
    if cb.isSome:
      let bounds = rect(state.bounds.x + state.lineNumberWidth, height, floor(state.bounds.w - state.lineNumberWidth), state.builder.textHeight)
      commands.startTransform(bounds.xy)
      let fun = (cb.get)
      let actualBounds = fun(customRenderId, bounds.wh, customRenderChunk.localOffset, commands)
      commands.endTransform()
      height += actualBounds.y
      state.chunkBoundsPerLine[^1].dontCenter = true

  # # Draw diagnostics
  if drawDiagnostics and state.diagnosticsPerLS != nil:
    for diagnosticsData in state.diagnosticsPerLS[].mitems:
      diagnosticsData.diagnosticsPerLine.withValue(state.lastPoint.row.int, val):
        for i in val[].mitems:
          let i = i
          let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[i]
          let nlIndex = diagnostic.message.find("\n")
          var maxIndex = if nlIndex != -1: nlIndex else: diagnostic.message.len
          maxIndex = min(maxIndex, max(((state.bounds.w - state.lineNumberWidth) / state.builder.charWidth).int - 3, 0))
          var message = "     ■ " & diagnostic.message[0..<maxIndex]
          if maxIndex < diagnostic.message.len:
            message.add "..."
          let width = message.runeLen.float * state.builder.charWidth # todo: measure text
          let color = case diagnostic.severity.get(lsp_types.DiagnosticSeverity.Hint)
          of lsp_types.DiagnosticSeverity.Error: state.errorColor
          of lsp_types.DiagnosticSeverity.Warning: state.warningColor
          of lsp_types.DiagnosticSeverity.Information: state.informationColor
          of lsp_types.DiagnosticSeverity.Hint: state.hintColor
          commands.drawText(message, rect(state.lineNumberWidth, height, width, state.builder.textHeight), color, 0.UINodeFlags)
          height += state.builder.textHeight
          state.chunkBoundsPerLine[^1].dontCenter = true

  return vec2(state.bounds.w, height).some

proc drawDiffBackgrounds(state: var LineDrawerState, backgroundCommands: var RenderCommands, scrollBox: var ScrollBox) =
  # Draw backgrounds for added/removed/changed lines in the diff view
  if state.renderDiff and state.diffChanges != nil:
    for item in scrollBox.items:
      let line = state.displayMap.toPoint(displayPoint(item.index, 0))
      let diffRow = state.diffChanges[].mapLine(line.row.int, state.diffReverse)
      if diffRow.getSome(d):
        if d.changed:
          backgroundCommands.fillRect(item.bounds + state.bounds.xy, state.changedTextBackgroundColor)
      else:
        let color = if state.diffReverse: state.insertedTextBackgroundColor else: state.deletedTextBackgroundColor
        backgroundCommands.fillRect(item.bounds + state.bounds.xy, color)

      let diffLine = state.diffDisplayMap.toPoint(displayPoint(item.index, 0))
      let row = state.diffChanges[].mapLine(diffLine.row.int, not state.diffReverse)
      if row.isNone:
        backgroundCommands.fillRect(item.bounds + state.bounds.xy, state.backgroundColor.darken(0.03))

proc fixupRenderCommandsAndChunkBounds(state: var LineDrawerState, i: int, commands: var RenderCommands, lineBounds: Rect) =
  var line = state.chunkBoundsPerLine[i].addr
  let center = not line.dontCenter
  ## Offset chunk bounds and chunk render commands according to line bounds
  for chunk in line.chunks.mitems:
    chunk.bounds.y = lineBounds.y

    # Fix chunk render command offset to draw it in the center of the line
    if chunk.renderCommandIndex != -1 and chunk.renderCommandIndex in 0..commands.commands.high:
      let offset = ceil((line.textBounds.h - chunk.bounds.h) * 0.5)
      chunk.bounds.y += offset
      let renderCommand = commands.commands[chunk.renderCommandIndex].addr
      renderCommand.bounds.y += offset

  # Fix line number render command offset to draw it in the center of the line
  let lineNumberRenderCommandIndex = line.lineNumberRenderCommandIndex
  if lineNumberRenderCommandIndex in 0..commands.commands.high:
    let offset = ceil((line.textBounds.h - state.builder.textHeight) * 0.5)
    commands.commands[lineNumberRenderCommandIndex].bounds.y += offset

func quickSort*[T](a: var openArray[T],
              cmp: proc (x, y: T): int {.closure.},
              low: int,
              high: int,
              order = SortOrder.Ascending) {.effectsOf: cmp.} =
  if low >= high:
    return

  let pivot = a[(low + high) div 2]
  var i = low
  var j = high

  while i < j:
    while cmp(a[i], pivot) * order < 0:
      inc i
    while cmp(a[j], pivot) * order > 0:
      dec j
    if i < j:
      swap(a[i], a[j])
    if i <= j:
      inc i
      dec j

  if low < j:
    quickSort(a, cmp, low, j, order)
  if i < high:
    quickSort(a, cmp, i, high, order)

func quickSort*[T](a: var openArray[T],
              cmp: proc (x, y: T): int {.closure.},
              order = SortOrder.Ascending) {.effectsOf: cmp.} =
  if a.len > 1:
    quickSort(a, cmp, 0, a.high, order)

proc drawLines(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, scrollBox: var ScrollBox) =
  var iter = state.createIter()
  commands.startScissor(state.bounds)
  defer:
    commands.endScissor()

  scrollBox.beginRender(state.bounds.wh, 0.UINodeFlags, state.displayMap.endDisplayPoint.row.int)

  let maxNumLines = ceil(state.bounds.h / state.builder.textHeight).int + 50
  let maxNumCharsPerLine = ceil(state.bounds.w / state.builder.charWidth).int + 5

  state.chunkBoundsPerLine = state.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  state.charBounds = state.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)

  # List of TransformStart render command indices where we need to fix the offset when we know it the offset after rendering all lines.
  var fixups = state.builder.arena.allocEmptyArray(maxNumLines, tuple[line: int, renderCommandHead: int])

  # Render lines
  while true:
    let renderedItem = scrollBox.renderItemT:
      let renderCommandHead = commands.commands.len
      let size = drawLine(state, commands, iter, scrollBox.currentIndex)
      if size.isSome:
        fixups.add (scrollBox.currentIndex, renderCommandHead)
      size

    if not renderedItem:
      break

  scrollBox.endRender()
  scrollBox.clamp(state.displayMap.endDisplayPoint.row.int)

  state.chunkBoundsPerLine.toOpenArray().quickSort(proc(a, b: auto): int = cmp(a.line, b.line))
  fixups.toOpenArray().quickSort(proc(a, b: auto): int = cmp(a.line, b.line))

  # Fixup chunk bounds and Transform render commands now that we know the line bounds
  assert fixups.len == state.chunkBoundsPerLine.len
  assert fixups.len == scrollBox.items.len
  for i in 0..<fixups.len:
    assert fixups[i].line == scrollBox.items[i].index
    assert fixups[i].line == state.chunkBoundsPerLine[i].line
    let fix = fixups[i]
    let lineBounds = scrollBox.items[i].bounds

    # Offset TransformStart render command according to scroll box item bounds
    if fix.renderCommandHead in 0..commands.commands.high and
        commands.commands[fix.renderCommandHead].kind == RenderCommandKind.TransformStart:
      commands.commands[fix.renderCommandHead] = RenderCommand(
        kind: RenderCommandKind.TransformStart,
        bounds: rect((vec2(0, lineBounds.y)), vec2(0)),
      )

    fixupRenderCommandsAndChunkBounds(state, i, commands, lineBounds)

  if state.chunkBoundsPerLine.len > 0:
    var total = 0
    for line in state.chunkBoundsPerLine.toOpenArray():
      total += line.chunks.len
    state.chunkBounds = state.builder.arena.allocEmptyArray(total, ChunkBounds)
    for line in state.chunkBoundsPerLine.toOpenArray():
      state.chunkBounds.add(line.chunks)

  # Draw highlighted background for display line containing the last cursor
  if scrollBox.itemBounds(state.cursorDisplayLine).getSome(b):
    backgroundCommands.fillRect(b + state.bounds.xy, state.backgroundColor.lighten(0.05))

  state.drawDiffBackgrounds(backgroundCommands, scrollBox)

proc drawDiffLines(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, scrollBox: var ScrollBox) =
  let maxNumLines = ceil(state.bounds.h / state.builder.textHeight).int + 15
  let maxNumCharsPerLine = ceil(state.bounds.w / state.builder.charWidth).int + 5

  state.chunkBoundsPerLine = state.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  state.charBounds = state.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)

  commands.startScissor(state.bounds)
  var iter = state.createIter()
  for i, item in scrollBox.items:
    var head = commands.commands.len
    let size = drawLine(state, commands, iter, item.index)
    if size.isNone:
      continue
    if head in 0..commands.commands.high and commands.commands[head].kind == RenderCommandKind.TransformStart:
      commands.commands[head] = RenderCommand(kind: RenderCommandKind.TransformStart, bounds: item.bounds)
    fixupRenderCommandsAndChunkBounds(state, i, commands, item.bounds)

    # Draw highlighted background for display line containing the last cursor
    if scrollBox.itemBounds(state.cursorDisplayLine).getSome(b):
      backgroundCommands.fillRect(b + state.bounds.xy, state.backgroundColor.lighten(0.05))

  state.drawDiffBackgrounds(backgroundCommands, scrollBox)

  commands.endScissor()

proc drawContextLines(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, contextLines: openArray[int]) =

  let contextBackgroundColor = state.builder.theme.color(@["breadcrumbPicker.background"], state.backgroundColor.lighten(0.05))

  var state = state
  let maxNumLines = contextLines.len
  state.chunkBoundsPerLine = state.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  let maxNumCharsPerLine = ceil(state.bounds.w / state.builder.charWidth).int + 5
  state.charBounds = state.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)

  var iter = state.createIter()
  var y = 0.0
  for i, line in contextLines:
    let startDisplayPoint = state.displayMap.toDisplayPoint(point(line, 0))

    var head = commands.commands.len
    commands.fillRect(rect(0, 0, 0, 0), contextBackgroundColor)
    let size = drawLine(state, commands, iter, startDisplayPoint.row.int)
    if size.isNone:
      continue

    let lineBounds = rect(state.bounds.x, state.bounds.y + y, size.get.x, size.get.y)

    commands.commands[head].bounds = lineBounds
    let transformIndex = head + 1
    if transformIndex in 0..commands.commands.high and commands.commands[transformIndex].kind == RenderCommandKind.TransformStart:
      commands.commands[transformIndex] = RenderCommand(kind: RenderCommandKind.TransformStart, bounds: rect(0, y, 0, 0))
    fixupRenderCommandsAndChunkBounds(state, i, commands, lineBounds)
    y += size.get.y

proc createTextLines(self: TextDocumentEditor, builder: UINodeBuilder, app: App, currentNode: UINode,
    selectionsNode: UINode, backgroundColor: Color, textColor: Color, sizeToContentX: bool,
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

  let inclusive = self.config.get("text.inclusive-selection", false)
  let drawChunks = self.debugSettings.drawTextChunks.get()

  let isThickCursor = self.isThickCursor

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let showContextLines = not renderDiff and self.settings.contextLines.get()

  let selectionColor = builder.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let insertedTextBackgroundColor = builder.theme.color(@["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"], color(0.1, 0.2, 0.1))
  let deletedTextBackgroundColor = builder.theme.color(@["diffEditor.removedTextBackground", "diffEditor.removedLineBackground"], color(0.2, 0.1, 0.1))
  var changedTextBackgroundColor = builder.theme.color(@["diffEditor.changedTextBackground", "diffEditor.changedLineBackground"], color(0.2, 0.2, 0.1))

  let cursorLine = self.selection.last.line
  let cursorDisplayLine = self.displayMap.toDisplayPoint(self.selection.last.toPoint).row.int

  let lineNumbers = self.uiSettings.lineNumbers.get()
  let lineNumberBounds = self.lineNumberBounds()

  let highlight = self.uiSettings.syntaxHighlighting.get()
  let indentGuide = self.uiSettings.indentGuide.get()

  proc createIter(): DisplayChunkIterator =
    var highlighter = Highlighter.none
    if self.document.tsTree.isNotNil and self.document.highlightQuery.isNotNil and highlight:
      highlighter = Highlighter(query: self.document.highlightQuery, tree: self.document.tsTree).some
    var res = self.displayMap.iter(highlighter, builder.theme)
    res.styledChunks.diagnosticEndPoints = self.document.diagnosticEndPoints # todo: don't copy everything here
    if indentGuide:
      let cursorIndentLevel = self.document.rope.indentRunes(self.selection.last.line).int
      res.indentGuideColumn = cursorIndentLevel.some
    return res

  proc createDiffIter(): DisplayChunkIterator =
    var highlighter = Highlighter.none
    if self.diffDocument.tsTree.isNotNil and self.diffDocument.highlightQuery.isNotNil and highlight:
      highlighter = Highlighter(query: self.diffDocument.highlightQuery, tree: self.diffDocument.tsTree).some
    var res = self.diffDisplayMap.iter(highlighter, builder.theme)
    return res

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
    floor(parentWidth * 0.5)
  else:
    0

  let width = if renderDiff:
    floor(parentWidth * 0.5)
  else:
    parentWidth

  var state = LineDrawerState(
    builder: builder,
    platform: self.platform,
    displayMap: self.displayMap,
    diffDisplayMap: self.diffDisplayMap,
    createIter: createIter,
    diffReverse: true,
    renderDiff: renderDiff,
    diffChanges: if self.diffChanges.isSome: self.diffChanges.get.addr else: nil,

    customOverlayRenderers: self.customOverlayRenderers.addr,
    signs: self.signs.addr,
    diagnosticsPerLS: self.document.diagnosticsPerLS.addr,

    absoluteBounds: rect(currentNode.boundsAbsolute.x + mainOffset, currentNode.boundsAbsolute.y, width, parentHeight),
    bounds: rect(mainOffset, 0, width, parentHeight),
    cursorLine: cursorLine,
    cursorDisplayLine: cursorDisplayLine,

    textColor: textColor,
    errorColor: builder.theme.tokenColor("error", color(0.8, 0.2, 0.2)),
    warningColor: builder.theme.tokenColor("warning", color(0.8, 0.8, 0.2)),
    informationColor: builder.theme.tokenColor("information", color(0.8, 0.8, 0.8)),
    hintColor: builder.theme.tokenColor("hint", color(0.7, 0.7, 0.7)),
    backgroundColor: backgroundColor,
    insertedTextBackgroundColor: insertedTextBackgroundColor,
    deletedTextBackgroundColor: deletedTextBackgroundColor,
    changedTextBackgroundColor: changedTextBackgroundColor,

    signShow: signShow,
    signColumnPixelWidth: signColumnPixelWidth,
    signColumnWidth: signColumnWidth,
    lineNumbers: lineNumbers,
    lineNumberWidth: lineNumberWidth,
    lineNumberBounds: lineNumberBounds,
  )

  var diffState = LineDrawerState(
    builder: builder,
    platform: self.platform,
    displayMap: self.diffDisplayMap,
    diffDisplayMap: self.displayMap,
    createIter: createDiffIter,
    diffReverse: false,
    renderDiff: renderDiff,
    diffChanges: if self.diffChanges.isSome: self.diffChanges.get.addr else: nil,

    absoluteBounds: rect(currentNode.boundsAbsolute.x, currentNode.boundsAbsolute.y, width, parentHeight),
    bounds: rect(0, 0, width, parentHeight),
    cursorLine: if self.diffChanges.isSome: self.diffChanges.get.mapLine(cursorLine, true).get((-1, false)).line else: -1,
    cursorDisplayLine: cursorDisplayLine,

    textColor: textColor,
    errorColor: builder.theme.tokenColor("error", color(0.8, 0.2, 0.2)),
    warningColor: builder.theme.tokenColor("warning", color(0.8, 0.8, 0.2)),
    informationColor: builder.theme.tokenColor("information", color(0.8, 0.8, 0.8)),
    hintColor: builder.theme.tokenColor("hint", color(0.7, 0.7, 0.7)),

    backgroundColor: backgroundColor,
    insertedTextBackgroundColor: insertedTextBackgroundColor,
    deletedTextBackgroundColor: deletedTextBackgroundColor,
    changedTextBackgroundColor: changedTextBackgroundColor,

    signColumnPixelWidth: signColumnPixelWidth,
    signColumnWidth: signColumnWidth,
    lineNumbers: lineNumbers,
    lineNumberWidth: lineNumberWidth,
    lineNumberBounds: lineNumberBounds,
  )

  let space = self.uiSettings.whitespaceChar.get()
  let spaceColorName = self.uiSettings.whitespaceColor.get()
  if space.len > 0:
    currentNode.renderCommands.space = space.runeAt(0)

  currentNode.renderCommands.spacesColor = builder.theme.tokenColor(spaceColorName, textColor)

  self.scrollBox.smoothScroll = self.uiSettings.smoothScroll.get()
  self.scrollBox.enableScrolling = not self.disableScrolling
  if self.disableScrolling:
    self.scrollBox.index = 0
    self.scrollBox.offset = 0
    self.scrollBox.margin = 0
  else:
    let height = builder.currentParent.bounds.h
    let configMarginRelative = self.settings.cursorMarginRelative.get()
    let configMargin = self.settings.cursorMargin.get()
    let margin = if configMarginRelative:
      clamp(configMargin, 0.0, 1.0) * 0.5 * height
    else:
      clamp(configMargin * builder.textHeight, 0.0, height * 0.5 - builder.textHeight * 0.5)

    self.scrollBox.margin = margin

  selectionsNode.renderCommands.clear()
  currentNode.renderCommands.clear()
  drawLines(state, currentNode.renderCommands, selectionsNode.renderCommands, self.scrollBox)
  if renderDiff:
    drawDiffLines(diffState, currentNode.renderCommands, selectionsNode.renderCommands, self.scrollBox)

  elif showContextLines and self.scrollBox.items.len > 0:
    let startLine = self.scrollBox.items[0].index
    var contextLines: seq[int]
    for i in 0..10:
      let displayPoint = displayPoint(startLine + i + 2, 0)
      if displayPoint.row.int >= self.numDisplayLines:
        break
      let s = self.displayMap.toPoint(displayPoint)
      contextLines = self.getContextLines(s.toCursor)
      if contextLines.len <= i:
        break
    contextLines.reverse()

    drawContextLines(state, currentNode.renderCommands, selectionsNode.renderCommands, contextLines)

  # Store rendered chunk ranges for e.g. choose-cursor command
  self.lastRenderedChunks.setLen(0)
  for chunk in state.chunkBounds:
    if not chunk.displayChunk.styledChunk.chunk.external:
      self.lastRenderedChunks.add (chunk.range, chunk.displayRange)

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
      let color = builder.theme.color(s.color, color(200/255, 200/255, 200/255)) * s.tint
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

  let chunkBounds = @(state.chunkBounds.toOpenArray(0, state.chunkBounds.high))
  let charBounds = @(state.charBounds.toOpenArray(0, state.charBounds.high))
  type MouseEventKind = enum Click, Drag, Hover
  proc handleMouseEvent(self: TextDocumentEditor, btn: MouseButton, pos: Vec2, mods: set[Modifier], event: MouseEventKind) =
    if self.document.isNil:
      return

    var (_, index) = chunkBounds.binarySearchRange(pos, Bias.Left, cmp)
    if index notin 0..chunkBounds.high:
      return

    if index + 1 < chunkBounds.len and pos.y >= chunkBounds[index].bounds.yh and pos.y < chunkBounds[index + 1].bounds.yh:
      index += 1

    if event == Click:
      self.lastPressedMouseButton = btn

    if btn notin {MouseButton.Left, DoubleClick, TripleClick}:
      return
    # if line >= self.document.numLines:
    #   return

    let chunk = chunkBounds[index]

    let posAdjusted = if self.isThickCursor(): pos else: pos + vec2(builder.charWidth * 0.5, 0)
    let searchPosition = vec2(posAdjusted.x - chunk.bounds.x, 0)
    var (_, charIndex) = charBounds.toOpenArray(chunk.charsRange.a, chunk.charsRange.b - 1).binarySearchRange(searchPosition, Left, cmp)

    var newCursor = self.selection.last
    if charIndex + chunk.charsRange.a in chunk.charsRange.a..<chunk.charsRange.b:
      if searchPosition.x >= charBounds[chunk.charsRange.a + charIndex].xw and (index == chunkBounds.high or chunkBounds[index + 1].range.a.row > chunk.range.a.row):
        charIndex += 1
      newCursor = chunk.range.a.toCursor + (0, charIndex) # todo unicode offset

    else:
      let offset = self.getCursorPos2(builder, chunk.text.toOpenArray, pos - chunk.bounds.xy)
      newCursor = chunk.range.a.toCursor + (0, offset)

    case event
    of Drag:
      let currentSelection = self.dragStartSelection
      let first = if (currentSelection.isBackwards and newCursor < currentSelection.first) or (not currentSelection.isBackwards and newCursor >= currentSelection.first):
        currentSelection.first
      else:
        currentSelection.last
      self.selection = (first, newCursor)
      self.runDragCommand()

      self.updateTargetColumn(Last)
      self.layout.tryActivateEditor(self)
      self.markDirty()

    of Click:
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

    of Hover:
      self.mouseHoverLocation = newCursor
      self.mouseHoverMods = mods
      self.showHoverDelayed()

  let textNode = currentNode
  builder.panel(&{UINodeFlag.FillX, FillY, MouseHover}, tag = "text-editor-hover"):
    onClickAny btn:
      self.handleMouseEvent(btn, pos - vec2(textNode.x, 0), modifiers, Click)
    onDrag MouseButton.Left:
      self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, Drag)
    onBeginHover:
      if not self.isHovered:
        self.markDirty()
      self.isHovered = true
      self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, Hover)
    onHover:
      self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, Hover)
    onEndHover:
      if self.isHovered:
        self.markDirty()
      self.isHovered = false
      self.cancelHover()

  # Get center line
  if not state.cursorOnScreen:
    # todo: move this to a function
    let centerPos = currentNode.bounds.wh * 0.5 + vec2(0, builder.textHeight * -0.5)
    var (_, index) = state.chunkBounds.toOpenArray().binarySearchRange(centerPos, Bias.Left, cmp)
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

  let arenaCheckpoint = builder.arena.checkpoint()
  defer:
    builder.arena.restoreCheckpoint(arenaCheckpoint)

  let dirty = self.dirty
  self.resetDirty()

  let smoothScrollSpeed: float = self.uiSettings.smoothScrollSpeed.get()
  self.scrollBox.scrollSpeed = smoothScrollSpeed
  self.scrollBox.updateScroll(self.platform.deltaTime)

  let logNewRenderer = self.debugSettings.logTextRenderTime.get()
  let transparentBackground = self.uiSettings.background.transparent.get()
  let inactiveBrightnessChange = self.uiSettings.background.inactiveBrightnessChange.get()

  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: builder.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)

  if transparentBackground:
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  var headerColor = if self.active: builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))

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

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId, tag = "text-root"):
    onClickAny btn:
      self.layout.tryActivateEditor(self)

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.mode, self.document, headerColor, textColor):
          onRight:
            proc cursorString(cursor: Cursor): string =
              if self.document != nil and self.document.isInitialized:
                $cursor.line & ":" & $cursor.column
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

            let text = fmt"{self.customHeader} | {readOnlyText}{stagedText}{diffText} '{currentRuneText}' (U+{currentRuneHexText}) {(cursorString(self.selection.first))}-{(cursorString(self.selection.last))}"
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText, FillBackground},
              pivot = vec2(1, 0), textColor = textColor, text = text, backgroundColor = headerColor)

        let lineNumberWidth = self.lineNumberWidth()
        builder.panel(sizeFlags + &{FillBackground, MaskContent}, backgroundColor = backgroundColor):
          var selectionsNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}, tag = "selections"):
            selectionsNode = currentNode
            selectionsNode.renderCommands.clear()

          var textNode: UINode
          builder.panel(sizeFlags + &{MaskContent}, tag = "text-lines"):
            textNode = currentNode
            textNode.renderCommands.clear()

          onScroll:
            if Control in modifiers:
              self.scrollTextHorizontal(delta.y * self.uiSettings.scrollSpeed.get() / builder.charWidth)
            else:
              self.scrollText(delta.y * self.uiSettings.scrollSpeed.get())

          var t = startTimer()

          if self.document != nil and self.document.isInitialized:
            self.createTextLines(builder, app, textNode, selectionsNode,
              backgroundColor, textColor, sizeToContentX, sizeToContentY)

          let e = t.elapsed.ms
          if logNewRenderer:
            debugf"Render new took {e} ms"

          self.lastContentBounds = textNode.bounds

  var res = newSeq[OverlayFunction]()
  proc addDrawOverlayView(view: View): OverlayFunction =
    return proc() =
      let backgroundColor = builder.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
      let borderColor = builder.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
      let bounds = view.absoluteBounds
      builder.panel(&{MaskContent, FillBackground, DrawBorder, DrawBorderTerminal, SnapInitialBounds, LayoutVertical, MouseHover}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = backgroundColor, borderColor = borderColor, border = border(1), tag = "hover", pivot = vec2()):
        builder.panel(&{FillX, FillY}):
          discard view.createUI(builder)

  for overlay in self.overlayViews:
    res.add addDrawOverlayView(overlay)

  if self.showCompletions and self.active:
    res.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))

  if self.showHover:
    res.add proc() =
      self.createHover(builder, app, self.lastHoverLocationBounds.get(rect(100, 100, 10, 10)))

  if self.showSignatureHelp:
    res.add proc() =
      self.createSignatureHelp(builder, app, self.lastSignatureHelpLocationBounds.get(rect(100, 100, 10, 10)))

  if self.scrollBox.scrollMomentum.abs > 0.0001:
    self.markDirty()
  else:
    self.scrollBox.scrollMomentum = 0

  return res
