import std/[strformat, tables, strutils, math, options, json, algorithm, os]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, rope_utils, timer, generational_seq, render_command, arena, array_view, diff]
import text/text_editor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform
import ui/[widget_library]
import document_editor, theme, config_provider, layout/layout, service
import core_settings
import language_server
import text/[syntax_map, overlay_map, wrap_map, diff_map, display_map]
import view, treesitter/treesitter
import scroll_box, treesitter_component, decoration_component, hover_component, contextline_component

import ui/node
from nuigi import UiBuilder, UiBackendType, UiStyleIndex, UiTextStyleIndex, UiNodeStorageData, UiNodeText, UiRenderCommand, UiRenderCommandKind, text, textStyleIndex, maskChildren, fit, fitX, fitY, node, fillX, fillY, fill, width, fillBackground, styleIndex, backgroundColor, accentVariation, themeStyle, themeTextStyle, padding, gap, layoutVertical, layoutHorizontal, layoutHorizontalReverse, currentNode, currentNodeIndex, nodeStorage, nodeStorageGet, nodeStorageParent, rgba, textColor, fontSize, uiString, getTextArrangement, deferBuild, enqueueNextFrame, position, size, noHover, value, height, wasPressed, borderColor, borderWidth, wrapText, maskChildren, measuredTextSize, absoluteNodePos, absoluteNodePosPrev, withParent, pushId, popId, customRenderCommands
import nuigi/debug/profiler
from nuigi/widgets import checkbox, highlightedText, tableColumnFit
import nuigi/widgets/dynamic_virtuallist
import nuigi/widgets/list_table
import nuigi/text/graphemes
from nuigi/core/arena import allocRaw

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
    lineNumberBackgroundColor: Color
    insertedLineBackgroundColor: Color
    deletedLineBackgroundColor: Color
    changedLineBackgroundColor: Color
    insertedTextBackgroundColor: Color
    deletedTextBackgroundColor: Color
    changedTextBackgroundColor: Color
    errorColor: Color
    warningColor: Color
    informationColor: Color
    hintColor: Color
    scrollOffset: Vec2

    highlightInlineChanges: bool
    textColor: Color
    backgroundColor: Color
    signColumnWidth: int
    signColumnPixelWidth: float
    lineNumberWidth: float
    lineNumberBounds: Vec2
    fillLineNumberBackground: bool
    signShow: core_settings.SignColumnShowKind
    cursorLine: int
    cursorDisplayLine: int
    diffChanges: ptr seq[LineMapping] = nil
    customOverlayRenderers: ptr GenerationalSeq[CustomOverlayRenderer, CustomRendererId] = nil
    signs: ptr Table[int, seq[tuple[id: Id, group: string, text: string, tint: Color, color: string, width: int]]] = nil
    diagnosticsPerLS: ptr seq[DiagnosticsData] = nil
    lineNumbers: LineNumbers
    diagnosticsLocation: core_settings.DiagnosticsLocation
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

proc createHover(self: TextDocumentEditor, builder: UINodeBuilder, cursorBounds: Rect) =
  let backgroundColor = builder.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
  let borderColor = builder.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
  let activeHoverColor = builder.theme.color("editor.foreground", color(1, 1, 1))

  var bounds = rect(cursorBounds.xy, vec2())
  var outerSizeFlags = &{SizeToContentX, SizeToContentY}
  var innerSizeFlags = &{SizeToContentX, SizeToContentY}

  if self.hoverComponent.hoverView != nil and self.hoverComponent.hoverView.detached:
    bounds = self.hoverComponent.hoverView.absoluteBounds
    outerSizeFlags = 0.UINodeFlags
    innerSizeFlags = &{FillX, FillY}

  var hoverPanel: UINode = nil
  builder.panel(&{MaskContent, FillBackground, DrawBorder, DrawBorderTerminal, SnapInitialBounds, LayoutVertical, MouseHover} + outerSizeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = backgroundColor, borderColor = borderColor, border = border(1), tag = "hover", pivot = vec2()):
    hoverPanel = currentNode

    if self.hoverComponent.hoverView != nil:
      builder.panel(innerSizeFlags):
        discard self.hoverComponent.hoverView.createUI(builder)
    else:
      for line in self.hoverComponent.hoverText.splitLines:
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = line, textColor = activeHoverColor)

  if self.hoverComponent.hoverView == nil or not self.hoverComponent.hoverView.detached:
    var clampedX = cursorBounds.x
    if clampedX + hoverPanel.bounds.w > builder.root.w:
      clampedX = max(builder.root.w - hoverPanel.bounds.w, 0)

    hoverPanel.rawX = clampedX
    hoverPanel.rawY = cursorBounds.y
    hoverPanel.pivot = vec2(0, 1)

proc createSignatureHelp(self: TextDocumentEditor, builder: UINodeBuilder, cursorBounds: Rect) =
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

  proc drawSignature(signatureColor: Color, activeParamColor: Color, sig: language_server.SignatureInformation) =
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

proc createCompletions(self: TextDocumentEditor, builder: UINodeBuilder, cursorBounds: Rect) =
  let totalLineHeight = builder.textHeight
  let charWidth = builder.charWidth

  let transparentBackground = self.config.getUiBackgroundTransparent()
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
  let completionPanelHeight = min(self.completionMatches.len, numLinesToShow).float * totalLineHeight + 2
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
      let scrollAmount = delta * self.config.getUiScrollSpeed()
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
      var y = if reverse: completionPanelHeight - totalLineHeight - 2 else: 0

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
        builder.panel(&{UINodeFlag.FillBackground, MaskContent, DrawBorder, DrawBorderTerminal},
            x = listNode.xw, w = docsWidth * charWidth, h = listNode.h, border = border(1),
            backgroundColor = backgroundColor, borderColor = borderColor):
          builder.panel(&{DrawText, TextWrap, FillX, FillY}, text = docText, textColor = docsColor)

  if completionsPanel.bounds.yh > completionsPanel.parent.bounds.h:
    completionsPanel.rawY = cursorBounds.y
    completionsPanel.pivot = vec2(0, 1)

  if completionsPanel.bounds.xw > completionsPanel.parent.bounds.w:
    completionsPanel.rawX = max(completionsPanel.parent.bounds.w - completionsPanel.bounds.w, 0)

proc drawHighlight(builder: UINodeBuilder, sn: Selection, color: Color, renderCommands: var RenderCommands, state: var LineDrawerState, cursor: var RopeCursorT[Point], drawEmpty: bool, debug = false) =

  let r = sn.first.toPoint...sn.last.toPoint

  let (_, firstIndexNormalized) = state.chunkBounds.toOpenArray().binarySearchRange(r.a, Bias.Right, cmp)
  let (_, lastIndexNormalized) = state.chunkBounds.toOpenArray().binarySearchRange(r.b, Bias.Right, cmp)
  if debug:
    debugf"drawHighlight {r} {color}: firstLastNormalized = {firstIndexNormalized}...{lastIndexNormalized}, chunk bounds: {state.chunkBounds.len}"
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

    if debug:
      debugf"  firstIndexClamped={firstIndexClamped}, lastIndexClamped={lastIndexClamped}"
    if firstIndexClamped != -1 and lastIndexClamped != -1:
      for i in firstIndexClamped..lastIndexClamped:
        let drawEmpty = drawEmpty and i == firstIndexClamped
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

        if debug:
          debugf"  firstOffset={firstOffset}, lastOffset={lastOffset}"

        if firstOffset == lastOffset and not drawEmpty:
          continue

        var selectionBounds = rect(
          (bounds.bounds.xy + vec2(firstOffset.float * builder.charWidth, 0)),
          (vec2((lastOffset - firstOffset).float * builder.charWidth, max(builder.textHeight, bounds.bounds.h))))

        let firstIndexClamped = firstOffset.clamp(0, bounds.charsRange.len - 1)
        let lastIndexClamped = lastOffset.clamp(0, bounds.charsRange.len)

        if debug:
          debugf"  firstIndexClamped={firstIndexClamped}, lastIndexClamped={lastIndexClamped}"

        if firstIndexClamped != -1 and lastIndexClamped != -1 and lastIndexClamped > firstIndexClamped and
            bounds.charsRange.a + firstIndexClamped in 0..<state.charBounds.len and
            bounds.charsRange.a + lastIndexClamped - 1 in 0..<state.charBounds.len:
          let firstBounds = state.charBounds[bounds.charsRange.a + firstIndexClamped] + bounds.bounds.xy
          let lastBounds = state.charBounds[bounds.charsRange.a + lastIndexClamped - 1] + bounds.bounds.xy
          selectionBounds = rect(firstBounds.xy, vec2(lastBounds.xw - firstBounds.x, max(builder.textHeight, bounds.bounds.h)))

        if selectionBounds.w == 0:
          selectionBounds.w = ceil(builder.charWidth * 0.25)

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
    lineNumberX = max(0.0, lineNumberBounds.x - builder.charWidth - lineNumberText.len.float * builder.charWidth)
  elif lineNumbers == LineNumbers.Relative:
    lineNumberText = $abs((lineNumber + 1) - cursorLine)
    lineNumberX = max(0.0, lineNumberBounds.x - builder.charWidth - lineNumberText.len.float * builder.charWidth)

  if lineNumberText.len > 0:
    let width = builder.textWidth(lineNumberText)
    buildCommands(renderCommands):
      drawText(lineNumberText, rect(offset.x + lineNumberX, offset.y, width, builder.textHeight), textColor, 0.UINodeFlags)

proc toUINodeFlags(fontStyle: set[FontStyle]): UINodeFlags =
  result = 0.UINodeFlags
  if Italic in fontStyle:
    result.incl TextItalic
  if Bold in fontStyle:
    result.incl TextBold

proc drawCursors(self: TextDocumentEditor, builder: UINodeBuilder, currentNode: UINode, renderCommands: var RenderCommands, state: var LineDrawerState) =
  if state.chunkBounds.len == 0:
    return

  renderCommands.startScissor(state.bounds)
  defer:
    renderCommands.endScissor()

  let cursorForegroundColor = builder.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = builder.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let cursorTrailColor = cursorForegroundColor.darken(0.1)
  let cursorSpeed: float = self.config.getUiCursorTrailSpeed()
  let cursorTrail: int = self.config.getUiCursorTrailLength()
  let isThickCursor = self.isThickCursor

  buildCommands(renderCommands):
    self.cursorHistories.setLen(self.selections.len)

    # debugf"==================="
    for i, s in self.selections:
      let p = s.last.toPoint
      let (_, initialIndex) = state.chunkBounds.toOpenArray().binarySearchRange(p, Bias.Left, cmp)

      var lastIndex = initialIndex
      if lastIndex > 0 and p in state.chunkBounds[lastIndex - 1].range and not state.chunkBounds[lastIndex - 1].displayChunk.styledChunk.chunk.external and not state.chunkBounds[lastIndex].displayChunk.diffChunk.wrapChunk.inputChunk.wasTab:
        dec lastIndex

      var currentExternal = state.chunkBounds[lastIndex].displayChunk.styledChunk.chunk.external
      while lastIndex < state.chunkBounds.high:
        if state.chunkBounds[lastIndex].displayChunk.diffChunk.wrapChunk.inputChunk.wasTab:
          if p == state.chunkBounds[lastIndex].range.a:
            break
        elif not currentExternal and p < state.chunkBounds[lastIndex].range.b:
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
        #   debugf"  {chunk}\n  {state.chunkBounds[lastIndex + 1]}\n  {state.chunkBounds[lastIndex + 2]}"

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
            let alpha = 1 - exp(-cursorSpeed * state.platform.deltaTime)
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

      if i == self.selections.high:
        let dp = self.displayMap.toDisplayPoint(s.last.toPoint)
        let (_, lastIndexDisplay) = state.chunkBounds.toOpenArray().binarySearchRange(dp, Bias.Left, cmp)
        if lastIndexDisplay in 0..<state.chunkBounds.len and dp >= state.chunkBounds[lastIndexDisplay].displayRange.a:
          state.cursorOnScreen = true
          self.currentCenterCursor = s.last
          self.currentCenterCursorRelativeYPos = (state.chunkBounds[lastIndexDisplay].bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h

  let hoverScreenPos = self.getScreenPos(builder, state, self.hoverComponent.hoverLocation.toCursor)
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

    if bounds.xw >= 0:
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
    of overlay_map.OverlayRenderLocation.Inline:
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
    of overlay_map.OverlayRenderLocation.Below:
      state.customRendererChunksBelow.add(chunk.diffChunk.inputChunk.inputChunk.inputChunk)
    of overlay_map.OverlayRenderLocation.Above:
      state.customRendererChunksAbove.add(chunk.diffChunk.inputChunk.inputChunk.inputChunk)

  # buildCommands(commands):
  #   drawRect(chunkBounds, color(1, 0, 0))

  return LineDrawerResult.Continue

proc drawLine*(state: var LineDrawerState, commands: var RenderCommands, lineNumberCommands: var RenderCommands, iter: var DisplayChunkIterator, line: int, columnRange: Option[rope.Range[int]] = rope.Range[int].none): Option[Vec2] =
  if line < 0 or line > state.displayMap.endDisplayPoint.row.int:
    return Vec2.none
  if state.chunkBoundsPerLine.len >= state.chunkBoundsPerLine.cap:
    return Vec2.none

  let maxNumChunks = max(ceil(state.bounds.w / state.builder.charWidth).int + 5, 1)
  state.chunkBoundsPerLine.add LineBounds(
    line: line,
    chunks: state.builder.arena.allocEmptyArray(maxNumChunks, ChunkBounds)
  )

  # When drawing lines upwards we have to reset the iterator because it can iterate backwards
  if iter.displayPoint.row.int != line or not iter.didSeek or columnRange.isSome:
    iter = state.createIter()
    if columnRange.isSome:
      iter.seek(displayPoint(line, columnRange.get.a))
    else:
      iter.seekLine(line)
    discard iter.next()
    if iter.displayChunk.isSome:
      state.lastDisplayEndPoint = iter.displayChunk.get.displayPoint

  # Add a transform render command for which we later override the y offset to the correct y offset calculated by the
  # scroll box. Every render command for a line can then just use (0, 0) as the origin.
  commands.startTransform(vec2(0))
  defer:
    commands.endTransform()

  if iter.displayChunk.isNone or iter.displayChunk.get.displayPoint.row.int != line:
    return vec2(state.bounds.w, state.builder.textHeight).some

  let chunk {.cursor.} = iter.displayChunk.get

  # Check whether we are rendering the first display line of a given real line
  let point = state.displayMap.toPoint(displayPoint(line, 0))
  let firstDisplayLine = state.displayMap.toDisplayPoint(point(point.row.int, 0))
  let firstDisplayLineInRealLine = firstDisplayLine.row.int == line

  # Do some things (like line numbers) only on the first display line for a real line
  let hasLineNumbers = state.lineNumbers != LineNumbers.None
  let lineNumberWidth = if hasLineNumbers: state.lineNumberWidth else: 0

  # Iterate through chunks and render them until we reach the end or get a chunk which is on the next display line.
  state.offset = state.bounds.xy + vec2(lineNumberWidth, 0) + vec2(state.scrollOffset.x, 0)
  state.lastDisplayEndPoint = displayPoint(line, 0)
  if columnRange.isSome:
    state.lastDisplayEndPoint.column = columnRange.get.a.uint32
  state.customRendererChunksBelow.setLen(0)
  state.customRendererChunksAbove.setLen(0)
  state.lineBounds = rect(0, 0, 0, 0)
  while iter.displayChunk.isSome:
    if iter.displayChunk.get.displayPoint.row.int > line:
      break
    # todo: this sometimes happens for a frame or two, probably because some data structures are in an invalid state
    # which causes an infinte loop here.
    # Just breaking and trying again will be fine for now, but the root cause should be fixed.
    if state.numDrawnChunks > 10000:
      log lvlWarn, "Rendering too much text, your font size is too small or there is a bug"
      break
    let res = drawChunk(iter.displayChunk.get, state, commands)
    discard iter.next()
    if columnRange.isSome and state.lineBounds.w >= columnRange.get.len.float * state.builder.charWidth:
      break
    case res
    of Continue: discard
    of ContinueNextLine: break
    of Break: break

  var height = max(state.builder.textHeight, state.lineBounds.h)

  # Draw chunks with custom render location Below
  for customRenderChunk in state.customRendererChunksBelow:
    let customRenderId = customRenderChunk.renderId
    let cb = state.customOverlayRenderers[].tryGet(customRenderId.CustomRendererId)
    if cb.isSome:
      let bounds = rect(state.bounds.x + lineNumberWidth, height, floor(state.bounds.w - lineNumberWidth), state.builder.textHeight)
      commands.startTransform(bounds.xy)
      let fun = (cb.get)
      let actualBounds = fun(customRenderId, bounds.wh, customRenderChunk.localOffset, commands)
      commands.endTransform()
      height += actualBounds.y
      state.chunkBoundsPerLine[^1].dontCenter = true

  var drawDiagnostics = false
  if firstDisplayLineInRealLine:
    drawDiagnostics = true

  # Draw diagnostics
  if drawDiagnostics and state.diagnosticsPerLS != nil:
    let renderBelow = case state.diagnosticsLocation
      of core_settings.DiagnosticsLocation.Below: true
      of core_settings.DiagnosticsLocation.LineEnd: false
      of core_settings.DiagnosticsLocation.LineEndOrBelow: line == state.cursorLine

    if renderBelow:
      for diagnosticsData in state.diagnosticsPerLS[].mitems:
        diagnosticsData.diagnosticsPerLine.withValue(line, val):
          for i in val[].mitems:
            let i = i
            let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[i]
            var maxIndex = min(diagnostic.message.len, 500)
            var message = "     ■ " & diagnostic.message[0..<maxIndex]
            if maxIndex < diagnostic.message.len:
              message.add "..."
            let width = message.runeLen.float * state.builder.charWidth # todo: measure text
            let color = case diagnostic.severity.get(language_server.DiagnosticSeverity.Hint)
            of language_server.DiagnosticSeverity.Error: state.errorColor
            of language_server.DiagnosticSeverity.Warning: state.warningColor
            of language_server.DiagnosticSeverity.Information: state.informationColor
            of language_server.DiagnosticSeverity.Hint: state.hintColor
            commands.drawText(message, rect(lineNumberWidth, height, width, state.builder.textHeight), color, 0.UINodeFlags)
            height += state.builder.textHeight * message.countLines.float
            state.chunkBoundsPerLine[^1].dontCenter = true
    else:
      # Show only the first diagnostic inline at the end of the line; height is not increased
      block lineEndDiag:
        for diagnosticsData in state.diagnosticsPerLS[].mitems:
          diagnosticsData.diagnosticsPerLine.withValue(line, val):
            if val[].len == 0:
              continue
            for i in val[]:
              let i = i
              let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[i]
              if diagnostic.selection.first.line != line:
                continue
              let nlIndex = diagnostic.message.find("\n")
              var maxIndex = if nlIndex != -1: nlIndex else: diagnostic.message.len
              let xPos = max(state.lineBounds.w, lineNumberWidth)
              let availableChars = max(((state.bounds.xw - xPos) / state.builder.charWidth).int - 2, 0)
              maxIndex = min(maxIndex, availableChars)
              if maxIndex <= 0:
                continue
              var message = " ■ " & diagnostic.message[0..<maxIndex]
              if maxIndex < diagnostic.message.len:
                message.add "..."
              let width = message.runeLen.float * state.builder.charWidth # todo: measure text
              let color = case diagnostic.severity.get(language_server.DiagnosticSeverity.Hint)
              of language_server.DiagnosticSeverity.Error: state.errorColor
              of language_server.DiagnosticSeverity.Warning: state.warningColor
              of language_server.DiagnosticSeverity.Information: state.informationColor
              of language_server.DiagnosticSeverity.Hint: state.hintColor
              commands.drawText(message, rect(xPos, 0, width, state.builder.textHeight), color, 0.UINodeFlags)
              state.lineBounds.w += width

              # if xPos > state.bounds.w:
              #   break lineEndDiag

  if firstDisplayLineInRealLine:
    var doDrawLineNumber = hasLineNumbers

    state.chunkBoundsPerLine[^1].lineNumberRenderCommandIndex = lineNumberCommands.commands.len
    lineNumberCommands.startTransform(vec2(0))

    if state.lineNumbers != LineNumbers.None and state.fillLineNumberBackground:
      lineNumberCommands.fillRect(rect(vec2(0), vec2(state.lineNumberBounds.x, height)), state.backgroundColor)

    # Draw signs
    if state.signs != nil:
      state.signs[].withValue(chunk.point.row.int, value):
        var bounds = rect(lineNumberWidth - state.signColumnPixelWidth, 0, state.signColumnPixelWidth, state.builder.textHeight)
        if state.signShow == core_settings.SignColumnShowKind.Number:
          doDrawLineNumber = false
          bounds = rect(vec2(state.builder.charWidth, 0), state.lineNumberBounds)

        var i = 0
        for s in value[]:
          if i + s.width > state.signColumnWidth:
            break

          var color = state.textColor
          if s.color != "":
            color = state.builder.theme.tokenColor(s.color, state.textColor)
          lineNumberCommands.drawText(s.text, bounds, color * s.tint, 0.UINodeFlags)
          bounds.x += state.builder.charWidth * s.width.float
          i += s.width

    # Draw line numbers
    if doDrawLineNumber:
      let lineNumber = chunk.point.row.int
      lineNumberCommands.drawLineNumber(state.builder, lineNumber, state.bounds.xy, state.cursorLine, state.lineNumbers, state.lineNumberBounds - vec2(state.signColumnPixelWidth, 0), state.textColor)
    lineNumberCommands.endTransform()

  return vec2(state.bounds.w, height).some

proc drawDiffBackgrounds(state: var LineDrawerState, backgroundCommands: var RenderCommands, scrollBox: var ScrollBox) =
  backgroundCommands.startScissor(state.bounds)
  defer:
    backgroundCommands.endScissor()

  # Draw backgrounds for added/removed/changed lines in the diff view
  if state.renderDiff and state.diffChanges != nil:
    for item in scrollBox.items:
      let line = state.displayMap.toPoint(displayPoint(item.index, 0))
      let bounds = rect(vec2(state.bounds.x, state.bounds.y + item.bounds.y), item.bounds.wh)
      let diffRow = state.diffChanges[].mapLine(line.row.int, state.diffReverse)
      if diffRow.getSome(d):
        if d.changed:
          backgroundCommands.fillRect(bounds, state.changedLineBackgroundColor)
      else:
        let color = if state.diffReverse: state.insertedLineBackgroundColor else: state.deletedLineBackgroundColor
        backgroundCommands.fillRect(bounds, color)

      let diffLine = state.diffDisplayMap.toPoint(displayPoint(item.index, 0))
      let row = state.diffChanges[].mapLine(diffLine.row.int, not state.diffReverse)
      if row.isNone:
        backgroundCommands.fillRect(bounds, state.backgroundColor.darken(0.03))

proc drawPreciseDiffHighlights(state: var LineDrawerState, backgroundCommands: var RenderCommands, scrollBox: var ScrollBox, reverse: bool) =
  if not state.renderDiff or scrollBox.items.len == 0:
    return

  backgroundCommands.startScissor(state.bounds)
  defer:
    backgroundCommands.endScissor()

  let insertedColor = state.insertedTextBackgroundColor
  let deletedColor = state.deletedTextBackgroundColor
  let changedColor = state.changedTextBackgroundColor

  let firstDisplayLine = scrollBox.items[0].index
  let lastDisplayLine = scrollBox.items[^1].index

  let firstPoint = state.displayMap.toPoint(displayPoint(firstDisplayLine, 0))
  let lastPoint = state.displayMap.toPoint(displayPoint(lastDisplayLine, 0) + displayPoint(1, 0))

  let visibleRange = firstPoint...lastPoint

  var ropeCursor = state.displayMap.buffer.visibleText.cursorT(Point)

  for ropeDiff in state.displayMap.diffMap.snapshot.inlineMappings:
    if ropeDiff.diff.edits.len == 0:
      continue
    let mappingStart = ropeDiff.srcBase
    let mappingEnd = ropeDiff.srcBase + ropeDiff.diff.edits[^1].old.b

    if mappingStart.row > visibleRange.b.row:
      break
    if mappingEnd.row < visibleRange.a.row:
      continue

    for edit in ropeDiff.diff.edits:
      let startPt = ropeDiff.srcBase + edit.old.a

      var deletedRangeRel: Point = edit.new.b - edit.new.a
      var insertedRangeRel: Point = edit.old.b - edit.old.a
      let changedRangeRel = min(deletedRangeRel, insertedRangeRel)
      let changedRange = startPt...(startPt + changedRangeRel)
      var deletedRange = changedRange.b...changedRange.b
      var insertedRange = changedRange.b...(startPt + insertedRangeRel)

      if reverse:
        swap deletedRange, insertedRange
        swap deletedRangeRel, insertedRangeRel

      drawHighlight(state.builder, (changedRange).toSelection, changedColor, backgroundCommands, state, ropeCursor, false)

      if insertedRangeRel > deletedRangeRel:
        drawHighlight(state.builder, (insertedRange).toSelection, insertedColor, backgroundCommands, state, ropeCursor, true)
      elif insertedRangeRel < deletedRangeRel:
        drawHighlight(state.builder, (deletedRange).toSelection, deletedColor, backgroundCommands, state, ropeCursor, true)

proc fixupRenderCommandsAndChunkBounds(state: var LineDrawerState, i: int, commands: var RenderCommands, lineNumberCommands: var RenderCommands, lineBounds: Rect) =
  var line = state.chunkBoundsPerLine[i].addr
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
  if line.lineNumberRenderCommandIndex in 0..lineNumberCommands.commands.high:
    let offset = ceil((line.textBounds.h - state.builder.textHeight) * 0.5)
    lineNumberCommands.commands[line.lineNumberRenderCommandIndex].bounds.y = lineBounds.y + offset

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

proc drawLines(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, lineNumberCommands: var RenderCommands, scrollBox: var ScrollBox) =
  var iter = state.createIter()
  commands.startScissor(state.bounds)
  defer:
    commands.endScissor()

  scrollBox.beginRender(state.bounds.wh, 0.UINodeFlags, state.displayMap.endDisplayPoint.row.int)

  let maxNumLines = max(ceil(state.bounds.h / state.builder.textHeight).int + 50, 1)
  let maxNumCharsPerLine = max(ceil(state.bounds.w / state.builder.charWidth).int + 5, 1)

  state.chunkBoundsPerLine = state.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  state.charBounds = state.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)

  if state.lineNumbers != LineNumbers.None:
    lineNumberCommands.fillRect(rect(state.bounds.xy, vec2(state.lineNumberBounds.x, state.bounds.h)), state.backgroundColor)

  # List of TransformStart render command indices where we need to fix the offset when we know it the offset after rendering all lines.
  var fixups = state.builder.arena.allocEmptyArray(maxNumLines, tuple[line: int, renderCommandHead: int])

  # Render lines
  while true:
    let renderedItem = scrollBox.renderItemT:
      let renderCommandHead = commands.commands.len
      let size = drawLine(state, commands, lineNumberCommands, iter, scrollBox.currentIndex)
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
        bounds: rect(vec2(0, lineBounds.y), vec2(0)),
      )

    fixupRenderCommandsAndChunkBounds(state, i, commands, lineNumberCommands, lineBounds)

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
  if state.highlightInlineChanges:
    state.drawPreciseDiffHighlights(backgroundCommands, scrollBox, false)

proc drawDiffLines(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, lineNumberCommands: var RenderCommands, scrollBox: var ScrollBox) =
  let maxNumLines = max(ceil(state.bounds.h / state.builder.textHeight).int + 15, 1)
  let maxNumCharsPerLine = max(ceil(state.bounds.w / state.builder.charWidth).int + 5, 1)

  state.chunkBoundsPerLine = state.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  state.charBounds = state.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)

  if state.lineNumbers != LineNumbers.None:
    lineNumberCommands.fillRect(rect(state.bounds.xy, vec2(state.lineNumberBounds.x, state.bounds.h)), state.backgroundColor)

  commands.startScissor(state.bounds)
  var iter = state.createIter()
  for i, item in scrollBox.items:
    var head = commands.commands.len
    let size = drawLine(state, commands, lineNumberCommands, iter, item.index)
    if size.isNone:
      continue
    if head in 0..commands.commands.high and commands.commands[head].kind == RenderCommandKind.TransformStart:
      commands.commands[head] = RenderCommand(kind: RenderCommandKind.TransformStart, bounds: item.bounds)
    fixupRenderCommandsAndChunkBounds(state, i, commands, lineNumberCommands, item.bounds)

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
  if state.highlightInlineChanges:
    state.drawPreciseDiffHighlights(backgroundCommands, scrollBox, true)

  commands.endScissor()

proc drawContextLines(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, lineNumberCommands: var RenderCommands, contextLines: openArray[ContextLineEntry]) =

  let contextBackgroundColor = state.builder.theme.color(@["breadcrumbPicker.background"], state.backgroundColor.lighten(0.05))

  var state = state
  state.diagnosticsPerLS = nil
  state.signs = nil
  state.customOverlayRenderers = nil
  state.fillLineNumberBackground = true

  let maxNumLines = contextLines.len
  state.chunkBoundsPerLine = state.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  let maxNumCharsPerLine = max(ceil(state.bounds.w / state.builder.charWidth).int + 5, 1)
  state.charBounds = state.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)

  var iter = state.createIter()
  var y = 0.0
  for i, entry in contextLines:
    let startDisplayPoint = state.displayMap.toDisplayPoint(point(entry.line, 0))

    var head = commands.commands.len
    commands.fillRect(rect(0, 0, 0, 0), contextBackgroundColor)
    let size = drawLine(state, commands, lineNumberCommands, iter, startDisplayPoint.row.int)
    if size.isNone:
      continue

    let lineBounds = rect(state.bounds.x, state.bounds.y + y, size.get.x, size.get.y)

    commands.commands[head].bounds = lineBounds
    let transformIndex = head + 1
    if transformIndex in 0..commands.commands.high and commands.commands[transformIndex].kind == RenderCommandKind.TransformStart:
      commands.commands[transformIndex] = RenderCommand(kind: RenderCommandKind.TransformStart, bounds: rect(0, y, 0, 0))
    fixupRenderCommandsAndChunkBounds(state, i, commands, lineNumberCommands, lineBounds)
    y += size.get.y

proc drawContextBreadcrumbs*(state: var LineDrawerState, commands: var RenderCommands, backgroundCommands: var RenderCommands, lineNumberCommands: var RenderCommands, entries: openArray[ContextLineEntry], separator: string, maxEntryLength: int) =
  let contextBackgroundColor = state.builder.theme.color(@["breadcrumbPicker.background"], state.backgroundColor.lighten(0.05))
  let backgroundColor = contextBackgroundColor.darken(0.05)
  let separatorColor = state.builder.theme.color(@["breadcrumb.foreground"], state.textColor.darken(0.3))

  if entries.len == 0:
    return

  let bounds = rect(state.bounds.xy, vec2(state.bounds.w, state.builder.textHeight))
  let backgroundCommandIndex = commands.commands.len
  commands.fillRect(bounds, backgroundColor)

  var entryState = state
  let maxNumLines = entries.len
  entryState.chunkBoundsPerLine = entryState.builder.arena.allocEmptyArray(maxNumLines, LineBounds)
  let maxNumCharsPerLine = max(ceil(entryState.bounds.w / entryState.builder.charWidth).int + 5, 1)
  entryState.charBounds = entryState.builder.arena.allocEmptyArray(maxNumLines * maxNumCharsPerLine, Rect)
  entryState.diagnosticsPerLS = nil
  entryState.signs = nil
  entryState.customOverlayRenderers = nil
  entryState.scrollOffset =  vec2(0)
  entryState.fillLineNumberBackground = true

  var x = 0.0
  var y = 0.0
  var h = 0.0
  var iter = entryState.createIter()
  for i, entry in entries:
    let startDisplayPoint = entryState.displayMap.toDisplayPoint(entry.lineRange.a)

    var head = commands.commands.len
    commands.fillRect(rect(0, 0, 0, 0), contextBackgroundColor)

    let columnRange = startDisplayPoint.column.int...(startDisplayPoint.column.int + maxEntryLength)

    entryState.lineNumbers = if i == 0: state.lineNumbers else: LineNumbers.None # Only draw line numbers on first line
    let size = drawLine(entryState, commands, lineNumberCommands, iter, startDisplayPoint.row.int, columnRange.some)
    if size.isNone:
      continue

    if x + entryState.lineBounds.w > entryState.bounds.w:
      x = state.lineNumberWidth
      y += h
      h = 0

    let lineBounds = rect(vec2(x, 0), entryState.lineBounds.wh)
    let padding = (state.builder.charWidth * 0.5).floor
    commands.commands[head].bounds = rect(x - padding, y, entryState.lineBounds.w + padding * 2, entryState.lineBounds.h)
    let transformIndex = head + 1
    if transformIndex in 0..commands.commands.high and commands.commands[transformIndex].kind == RenderCommandKind.TransformStart:
      commands.commands[transformIndex] = RenderCommand(kind: RenderCommandKind.TransformStart, bounds: rect(x, y, 0, 0))
    fixupRenderCommandsAndChunkBounds(entryState, i, commands, lineNumberCommands, lineBounds)
    h = max(h, entryState.lineBounds.h)
    x += entryState.lineBounds.w

    if i < entries.high:
      let sepText = " " & separator & " "
      let sepWidth = entryState.builder.textWidth(sepText)
      commands.drawText(sepText, rect(vec2(x, bounds.y + y), vec2(sepWidth, entryState.builder.textHeight)), separatorColor, 0.UINodeFlags)
      x += sepWidth

  commands.commands[backgroundCommandIndex].bounds.h = y + h

proc createTextLines(self: TextDocumentEditor, builder: UINodeBuilder, currentNode: UINode,
    selectionsNode: UINode, lineNumberNode: UINode, backgroundColor: Color, textColor: Color, sizeToContentX: bool,
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

  let inclusive = self.config.get("text.inclusive-selection", false)
  let isThickCursor = self.isThickCursor
  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome
  let showContextLines = not renderDiff and self.config.getContextLinesEnabled()

  let selectionColor = builder.theme.color("selection.background", color(200/255, 200/255, 200/255))
  var insertedLineBackgroundColor = builder.theme.color(@["diffEditor.insertedLineBackground", "diffEditor.insertedTextBackground"], color(0.1, 0.2, 0.1))
  var deletedLineBackgroundColor = builder.theme.color(@["diffEditor.removedLineBackground", "diffEditor.removedTextBackground"], color(0.2, 0.1, 0.1))
  var changedLineBackgroundColor = builder.theme.color(@["diffEditor.changedLineBackground", "diffEditor.changedTextBackground"], color(0.2, 0.2, 0.1))
  var insertedTextBackgroundColor = builder.theme.color("diffEditor.insertedTextBackground", insertedLineBackgroundColor.lighten(0.1))
  var deletedTextBackgroundColor = builder.theme.color("diffEditor.removedTextBackground", deletedLineBackgroundColor.lighten(0.1))
  var changedTextBackgroundColor = builder.theme.color("diffEditor.changedTextBackground", changedLineBackgroundColor.lighten(0.1))

  let cursorLine = self.selection.last.line
  let cursorDisplayLine = self.displayMap.toDisplayPoint(self.selection.last.toPoint).row.int

  let lineNumbers = self.config.getUiLineNumbers()
  let diagnosticsLocation = self.config.getUiDiagnosticsLocation()
  let lineNumberBounds = self.lineNumberBounds()
  let rainbowParens = self.config.getUiRainbowParentheses()

  let highlight = self.config.getUiSyntaxHighlighting()
  let indentGuide = self.config.getUiIndentGuide()

  proc createIter(): DisplayChunkIterator =
    var highlighter = Highlighter.none
    let sm = self.document.treesitterComponent.syntaxMap
    if highlight:
      if sm.snapshot.layers.len > 0:
        highlighter = Highlighter.init(sm, rainbowParens).some
    var res = self.displayMap.iter(builder.arena.addr, highlighter, builder.theme)
    res.styledChunks.diagnosticEndPoints = self.document.diagnosticEndPoints # todo: don't copy everything here
    if indentGuide:
      let cursorIndentLevel = self.document.rope.indentRunes(self.selection.last.line).int
      res.indentGuideColumn = cursorIndentLevel.some
    return res

  proc createDiffIter(): DisplayChunkIterator =
    var highlighter = Highlighter.none
    let sm = self.diffDocument.treesitterComponent.syntaxMap
    if highlight:
      if sm.snapshot.layers.len > 0:
        highlighter = Highlighter.init(sm, rainbowParens).some
    var res = self.diffDisplayMap.iter(builder.arena.addr, highlighter, builder.theme)
    return res

  let signShow = self.config.getTextSignsShow()
  let lineNumberWidth = self.lineNumberWidth()
  let signColumnWidth = if signShow == core_settings.SignColumnShowKind.Number:
    floor(lineNumberWidth / builder.charWidth).int - 2
  else:
    self.requiredSignColumnWidth()
  let signColumnPixelWidth = if signShow == core_settings.SignColumnShowKind.Number:
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

    customOverlayRenderers: self.decorations.customOverlayRenderers.addr,
    signs: self.decorations.signs.addr,
    diagnosticsPerLS: self.document.diagnosticsPerLS.addr,
    scrollOffset: self.scrollBox.offset,

    absoluteBounds: rect(currentNode.boundsAbsolute.x + mainOffset, currentNode.boundsAbsolute.y, width, parentHeight),
    bounds: rect(mainOffset, 0, width, parentHeight),
    cursorLine: cursorLine,
    cursorDisplayLine: cursorDisplayLine,

    highlightInlineChanges: self.config.getUiHighlightInlineChanges(),
    textColor: textColor,
    errorColor: builder.theme.tokenColor("error", color(0.8, 0.2, 0.2)),
    warningColor: builder.theme.tokenColor("warning", color(0.8, 0.8, 0.2)),
    informationColor: builder.theme.tokenColor("information", color(0.8, 0.8, 0.8)),
    hintColor: builder.theme.tokenColor("hint", color(0.7, 0.7, 0.7)),
    backgroundColor: backgroundColor,
    insertedTextBackgroundColor: insertedTextBackgroundColor,
    deletedTextBackgroundColor: deletedTextBackgroundColor,
    changedTextBackgroundColor: changedTextBackgroundColor,
    insertedLineBackgroundColor: insertedLineBackgroundColor,
    deletedLineBackgroundColor: deletedLineBackgroundColor,
    changedLineBackgroundColor: changedLineBackgroundColor,

    signShow: signShow,
    signColumnPixelWidth: signColumnPixelWidth,
    signColumnWidth: signColumnWidth,
    lineNumbers: lineNumbers,
    diagnosticsLocation: diagnosticsLocation,
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
    scrollOffset: self.scrollBox.offset,

    highlightInlineChanges: self.config.getUiHighlightInlineChanges(),
    textColor: textColor,
    errorColor: builder.theme.tokenColor("error", color(0.8, 0.2, 0.2)),
    warningColor: builder.theme.tokenColor("warning", color(0.8, 0.8, 0.2)),
    informationColor: builder.theme.tokenColor("information", color(0.8, 0.8, 0.8)),
    hintColor: builder.theme.tokenColor("hint", color(0.7, 0.7, 0.7)),

    backgroundColor: backgroundColor,
    insertedTextBackgroundColor: insertedTextBackgroundColor,
    deletedTextBackgroundColor: deletedTextBackgroundColor,
    changedTextBackgroundColor: changedTextBackgroundColor,
    insertedLineBackgroundColor: insertedLineBackgroundColor,
    deletedLineBackgroundColor: deletedLineBackgroundColor,
    changedLineBackgroundColor: changedLineBackgroundColor,

    signColumnPixelWidth: signColumnPixelWidth,
    signColumnWidth: signColumnWidth,
    lineNumbers: lineNumbers,
    diagnosticsLocation: diagnosticsLocation,
    lineNumberWidth: lineNumberWidth,
    lineNumberBounds: lineNumberBounds,
  )

  let space = self.config.getUiWhitespaceChar()
  let spaceColorName = self.config.getUiWhitespaceColor()
  if space.len > 0:
    currentNode.renderCommands.space = space.runeAt(0)

  currentNode.renderCommands.spacesColor = builder.theme.tokenColor(spaceColorName, textColor)

  self.scrollBox.smoothScroll = self.config.getUiSmoothScroll()
  self.scrollBox.enableScrolling = not self.disableScrolling
  self.scrollBox.defaultItemHeight = builder.textHeight
  if self.disableScrolling:
    self.scrollBox.index = 0
    self.scrollBox.offset = vec2(0)
    self.scrollBox.margin = 0
  else:
    let height = builder.currentParent.bounds.h
    let configMarginRelative = self.config.getTextCursorMarginRelative()
    let configMargin = self.config.getTextCursorMargin()
    let margin = if configMarginRelative:
      clamp(configMargin, 0.0, 1.0) * 0.5 * height
    else:
      clamp(configMargin * builder.textHeight, 0.0, height * 0.5 - builder.textHeight * 0.5)

    self.scrollBox.margin = margin

  selectionsNode.renderCommands.clear()
  currentNode.renderCommands.clear()
  drawLines(state, currentNode.renderCommands, selectionsNode.renderCommands, lineNumberNode.renderCommands, self.scrollBox)
  if renderDiff:
    drawDiffLines(diffState, currentNode.renderCommands, selectionsNode.renderCommands, lineNumberNode.renderCommands, self.scrollBox)

  elif showContextLines and self.scrollBox.items.len > 0:
    let style = self.config.getContextLinesStyle()
    let contextLines = self.contextLineComponent.getContextLines()
    if style == "breadcrumb":
      let separator = self.config.getContextLinesSeparator()
      const maxEntryLength = 50
      drawContextBreadcrumbs(state, currentNode.renderCommands, selectionsNode.renderCommands, lineNumberNode.renderCommands, contextLines, separator, maxEntryLength)
    else:
      drawContextLines(state, currentNode.renderCommands, selectionsNode.renderCommands, lineNumberNode.renderCommands, contextLines)

  # Store rendered chunk ranges for e.g. choose-cursor command
  self.lastRenderedChunks.setLen(0)
  for chunk in state.chunkBounds:
    if not chunk.displayChunk.styledChunk.chunk.external:
      self.lastRenderedChunks.add (chunk.range, chunk.displayRange)

  self.drawCursors(builder, currentNode, currentNode.renderCommands, state)

  var ropeCursor = self.displayMap.buffer.visibleText.cursorT(Point)
  let visibleTextRange = self.visibleTextRange(2)
  for selections in self.decorations.customHighlights.values:
    for s in selections:
      var sn = s.selection.normalized
      if sn.last < visibleTextRange.first or sn.first > visibleTextRange.last:
        continue
      let color = builder.theme.color(s.color, color(200/255, 200/255, 200/255)) * s.tint
      drawHighlight(builder, sn, color, selectionsNode.renderCommands, state, ropeCursor, true)

  for s in self.selections:
    var sn = s.normalized
    if isThickCursor and inclusive:
      sn.last.column += 1
    if sn.isEmpty:
      continue
    if sn.last < visibleTextRange.first or sn.first > visibleTextRange.last:
      continue

    drawHighlight(builder, sn, selectionColor, selectionsNode.renderCommands, state, ropeCursor, false)

  # Scroll bar
  if self.config.getUiScrollBar():
    buildCommands(selectionsNode.renderCommands):
      if self.scrollBox.items.len > 0:
        let scrollOffsetNorm = self.scrollBox.getScrollOffsetNorm()
        let scrollableSize = self.scrollBox.getScrollableSize()
        if scrollableSize > 0:
          let scrollBarColor = builder.theme.color(@["scrollBar", "scrollbarSlider.background"], backgroundColor.lighten(0.1))
          let w = ceil(builder.charWidth * 0.5)
          let thumbHeightRatio = self.scrollBox.getScrollBarHandleHeightRatio()
          let thumbHeight = clamp(thumbHeightRatio * currentNode.bounds.h.float, builder.textHeight, max(currentNode.bounds.h - builder.textHeight, currentNode.bounds.h * 0.9))
          let scrollableHeight = currentNode.bounds.h.float - thumbHeight
          let thumbY = scrollOffsetNorm * scrollableHeight
          fillRect(rect(currentNode.bounds.w - w, floor(thumbY), w, ceil(thumbHeight)), scrollBarColor)

  selectionsNode.markDirty(builder)
  currentNode.markDirty(builder)

  # todo: avoid allocations for these two. We could store the states persistently on the editor/editor component
  let chunkBounds = @(state.chunkBounds.toOpenArray(0, state.chunkBounds.high))
  let charBounds = @(state.charBounds.toOpenArray(0, state.charBounds.high))
  type MouseEventKind = enum Click, Drag, Hover
  proc handleMouseEvent(self: TextDocumentEditor, btn: MouseButton, pos: Vec2, mods: set[Modifier], event: MouseEventKind) =
    if self.document.isNil:
      return

    if event == Click:
      self.layout.tryActivateEditor(self)

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
    if chunk.charsRange.a notin 0..charBounds.high or chunk.charsRange.b notin 0..charBounds.len:
      return
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

      self.scrollToCursor(Last)
      self.updateTargetColumn(Last)
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

      self.scrollToCursor(Last)
      self.updateTargetColumn(Last)
      self.markDirty()

    of Hover:
      self.hoverComponent.mouseHoverLocation = newCursor.toPoint
      self.hoverComponent.mouseHoverMods = mods
      self.hoverComponent.showHoverDelayed()

  let textNode = currentNode
  builder.panel(&{UINodeFlag.FillX, FillY, MouseHover}, tag = "text-editor-hover"):
    onClickAny btn:
      if self.document.isNotNil:
        self.handleMouseEvent(btn, pos - vec2(textNode.x, 0), modifiers, Click)
    onDrag MouseButton.Left:
      if self.document.isNotNil:
        self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, Drag)
    onBeginHover:
      if self.document.isNotNil:
        if not self.hoverComponent.isHovered:
          self.markDirty()
        self.hoverComponent.isHovered = true
        self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, Hover)
    onHover:
      if self.document.isNotNil:
        self.handleMouseEvent(MouseButton.Left, pos - vec2(textNode.x, 0), modifiers, Hover)
    onEndHover:
      if self.document.isNotNil:
        if self.hoverComponent.isHovered:
          self.markDirty()
        self.hoverComponent.isHovered = false
        self.hoverComponent.cancelHover()

  if renderDiff and self.config.getUiRenderDiffNavigationButtons():
    # Add diff change navigation buttons
    if self.diffChanges.isSome and self.diffChanges.get.len > 0:
      let cursorLine = self.selection.last.line
      var hasPrev = false
      var hasNext = false
      for mapping in self.diffChanges.get:
        if mapping.target.first < cursorLine:
          hasPrev = true
        if mapping.target.first > cursorLine:
          hasNext = true
          break

      let buttonWidth = (builder.charWidth * 1.5).floor
      let buttonHeight = (builder.textHeight * 1.5).floor
      let buttonBgColor = backgroundColor.darken(0.1)

      if hasNext:
        # Top right button - next change
        builder.panel(&{FillBackground, DrawText, MouseHover},
          x = diffState.bounds.xw - buttonWidth, y = (diffState.bounds.y + diffState.bounds.yh) * 0.5 + buttonHeight,
          w = buttonWidth, h = buttonHeight,
          backgroundColor = buttonBgColor, text = "▼", textColor = textColor, fontScale = 1.5):
          onClickAny btn:
            self.selection = self.getNextChange(self.selection.last)
            self.centerCursor(Last)
            self.markDirty()

      if hasPrev:
        # Bottom right button - previous change
        builder.panel(&{FillBackground, DrawText, MouseHover},
          x = diffState.bounds.xw - buttonWidth, y = (diffState.bounds.y + diffState.bounds.yh) * 0.5,
          w = buttonWidth, h = buttonHeight,
          backgroundColor = buttonBgColor, text = "▲", textColor = textColor, fontScale = 1.5):
          onClickAny btn:
            self.selection = self.getPrevChange(self.selection.last)
            self.centerCursor(Last)
            self.markDirty()

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

proc createUI*(self: TextDocumentEditor, builder: UINodeBuilder): seq[OverlayFunction] =
  self.preRender(builder.currentParent.bounds)

  let arenaCheckpoint = builder.arena.checkpoint()
  defer:
    builder.arena.restoreCheckpoint(arenaCheckpoint)

  let dirty = self.dirty
  self.resetDirty()

  let smoothScrollSpeed: float = self.config.getUiSmoothScrollSpeed()
  self.scrollBox.scrollSpeed = smoothScrollSpeed
  self.scrollBox.updateScroll(self.platform.deltaTime)

  let logNewRenderer = self.config.getDebugLogTextRenderTime()
  let transparentBackground = self.config.getUiBackgroundTransparent()
  let inactiveBrightnessChange = self.config.getUiBackgroundInactiveBrightnessChange()

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

    if dirty or not builder.retain():
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

        builder.panel(sizeFlags + &{FillBackground, MaskContent}, backgroundColor = backgroundColor):
          var selectionsNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}, tag = "selections"):
            selectionsNode = currentNode
            selectionsNode.renderCommands.clear()

          var textNode: UINode
          builder.panel(sizeFlags + &{MaskContent}, tag = "text-lines"):
            textNode = currentNode
            textNode.renderCommands.clear()

          var lineNumberNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}, tag = "line-numbers"):
            lineNumberNode = currentNode
            lineNumberNode.renderCommands.clear()

          onScroll:
            if Shift in modifiers:
              self.scrollTextHorizontal(delta.y * self.config.getUiScrollSpeed() / builder.charWidth)
            else:
              self.scrollText(delta.y * self.config.getUiScrollSpeed())

          var t = startTimer()

          if self.document != nil and self.document.isInitialized:
            self.createTextLines(builder, textNode, selectionsNode, lineNumberNode,
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

  for overlay in self.hoverComponent.overlayViews:
    res.add addDrawOverlayView(overlay)

  if self.showCompletions and self.active:
    res.add proc() =
      self.createCompletions(builder, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))

  if self.hoverComponent.showHover:
    res.add proc() =
      self.createHover(builder, self.lastHoverLocationBounds.get(rect(100, 100, 10, 10)))

  if self.showSignatureHelp:
    res.add proc() =
      self.createSignatureHelp(builder, self.lastSignatureHelpLocationBounds.get(rect(100, 100, 10, 10)))

  if self.scrollBox.scrollMomentum.x.abs > 0.0001 or self.scrollBox.scrollMomentum.y.abs > 0.0001:
    self.markDirty()
  else:
    self.scrollBox.scrollMomentum = vec2(0)

  return res

const textLineHeightHint* = 18.0'f32

type TextChunkIndexEntry* = object
  ## Rendered-chunk index entry, mirrors legacy ChunkBounds
  ## (widget_builder_text_document.nim:33): UI node index of the chunk text node
  ## (current frame), chunk start points, and top-left px relative to the virtual
  ## list body (viewport-relative, like legacy scroll item bounds). Plain float
  ## coords (not Vec2) to avoid the vmath/vecmath Vec2 clash; x is a monospace
  ## estimate accumulated from the line indent, y replicates the virtual list's
  ## itemTop minus its scroll offset.
  nodeIndex*: int
  displayPoint*: DisplayPoint
  displayEndPoint*: DisplayPoint
  point*: Point
  endPoint*: Point
  posX*: float32
  posY*: float32

type TextDocumentEditorNuiStorage* = ref object of UiNodeStorageData
  editor*: TextDocumentEditor
  theme*: Theme
  arena*: Arena
  useHighlight*: bool
  rainbowParens*: bool
  lineNumbers*: LineNumbers
  cursorLine*: int
  charWidth*: float32
  lineHeight*: float32
  gutterWidthPx*: float32
  chunkIndex*: seq[TextChunkIndexEntry]
  highlightCommands*: seq[UiRenderCommand]
  listStorage*: UiDynamicVirtualListStorage
  itemHeightHint*: float32
  textIter*: DisplayChunkIterator
  iterNextRow*: int

proc getOrCreateTextEditorNuiStorage(b: var UiBuilder, node: auto): TextDocumentEditorNuiStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[TextDocumentEditorNuiStorage](existing)
  var storage = TextDocumentEditorNuiStorage()
  b.nodeStorage(node, storage)
  return storage

proc createNuiIter(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage) =
  ## Fresh forward iterator for this frame, stored on the node storage and reused
  ## across lines (one construction per frame instead of per line).
  ## Display iterators are single-pass by design: no level clears atEnd/done on
  ## seek and lower levels assert forward-only seeks. That is safe here because
  ## the iterator is fresh every frame (theme/highlighter always current) and
  ## rows arrive in ascending order, so the frontier only ever moves forward
  ## (legacy createIter convention at widget_builder_text_document.nim:1375).
  var editor = self
  var highlighter = Highlighter.none
  if storage.useHighlight and storage.theme != nil:
    let sm = editor.document.treesitterComponent.syntaxMap
    if sm.snapshot.layers.len > 0:
      highlighter = Highlighter.init(sm, storage.rainbowParens).some
  storage.textIter = editor.displayMap.iter(storage.arena.addr, highlighter, storage.theme)
  storage.iterNextRow = -1
  # TODO(nui-text): copy diagnosticEndPoints like legacy createIter does, once
  # diagnostics (§14) are implemented (needs diagnosticsPerLS snapshot).

proc nuiMeasuredPrefixWidth(b: var UiBuilder, text: string, byteCount: int,
    textStyle: UiNodeText): float32 {.nimcall, gcsafe, raises: [].} =
  ## Measured width of text[0 ..< byteCount] in the given style (mirrors
  ## textfield.measuredPrefixWidth, which is private to that widget).
  {.cast(gcsafe).}:
    try:
      if byteCount <= 0:
        return 0.0'f32
      var prefixStyle = textStyle
      prefixStyle.text = text[0 ..< byteCount].uiString
      return b.measuredTextSize(prefixStyle.addr).x
    except:
      return 0.0'f32

proc nuiByteOffsetAtX(b: var UiBuilder, text: string, pointerX: float32,
    textStyle: UiNodeText): int {.nimcall, gcsafe, raises: [].} =
  ## Byte offset of the grapheme boundary nearest pointerX (mirrors textfield
  ## cursorPositionAtX, which is private to that widget).
  {.cast(gcsafe).}:
    try:
      if pointerX <= 0.0'f32 or text.len == 0:
        return 0
      var previousPosition = 0
      var position = text.nextGraphemeBoundary(0)
      while position <= text.len:
        let previousX = b.nuiMeasuredPrefixWidth(text, previousPosition, textStyle)
        let currentX = b.nuiMeasuredPrefixWidth(text, position, textStyle)
        if pointerX < (previousX + currentX) * 0.5'f32:
          return previousPosition
        if position == text.len:
          return text.len
        previousPosition = position
        position = text.nextGraphemeBoundary(position)
      return text.len
    except:
      return 0

proc nuiArenaIntText(b: var UiBuilder, num: int): tuple[buf: ptr UncheckedArray[char], len: int] {.nimcall, gcsafe, raises: [].} =
  ## Decimal rendering of num into frame-arena chars for zero-alloc node text
  ## (text(openArray) borrows the view; the backing lives until end of frame).
  ## Returns a raw buf/len pair because openArray is not returnable from procs.
  {.cast(gcsafe).}:
    var buf: array[20, char]
    var len = 0
    var n = num
    var neg = false
    if n < 0:
      neg = true
      n = -n
    if n == 0:
      buf[0] = '0'
      len = 1
    else:
      while n > 0:
        buf[len] = chr(ord('0') + n mod 10)
        inc len
        n = n div 10
      if neg:
        buf[len] = '-'
        inc len
      for i in 0 ..< len div 2:
        let t = buf[i]
        buf[i] = buf[len - 1 - i]
        buf[len - 1 - i] = t
    let mem = b.frame.arena[].allocRaw(len, 1)
    copyMem(mem, buf[0].addr, len)
    return (cast[ptr UncheckedArray[char]](mem), len)

proc buildTextLineNui(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  discard b.fillX().fitY()
  {.cast(gcsafe).}:
    prof("buildTextLineNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.displayMap.isNil or self.document.isNil:
        b.layoutHorizontal:
          discard b.fillX().fitY()
          b.node:
            discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text("")
        return
      # Per-frame settings snapshotted onto text-root storage in createUINui.
      let lineNumbers = storage.lineNumbers
      let cursorLine = storage.cursorLine
      # Stored iterator reused across lines (created once per frame in createUINui):
      # only seek when the frontier does not match; rows arrive ascending so the
      # frontier only moves forward, which keeps every level's forward-only seeks
      # and atEnd flags sound.
      if storage.iterNextRow != itemIndex:
        storage.textIter.seekLine(itemIndex)
        discard storage.textIter.next()
      let arenaCheckpoint = storage.arena.checkpoint()
      # Real line for this display line; legacy drawLineNumber shows the number only
      # on the first display row of a real line, and always for the cursor line.
      var realLine = -1
      var firstDisplayRow = -1
      if storage.textIter.displayChunk.isSome:
        realLine = storage.textIter.displayChunk.get.point.row.int
        firstDisplayRow = self.displayMap.toDisplayPoint(point(realLine, 0)).row.int
      # Line number digits rendered into the frame arena (no string alloc);
      # the gutter node below gives them an explicit width instead.
      var showNumber = false
      var numberBuf: ptr UncheckedArray[char]
      var numberLen = 0
      if lineNumbers != LineNumbers.None and realLine >= 0 and firstDisplayRow == itemIndex:
        var num = -1
        if cursorLine == realLine:
          num = realLine + 1
        elif lineNumbers == LineNumbers.Absolute:
          num = realLine + 1
        elif lineNumbers == LineNumbers.Relative:
          num = abs((realLine + 1) - cursorLine)
        if num >= 0:
          showNumber = true
          let t = b.nuiArenaIntText(num)
          numberBuf = t.buf
          numberLen = t.len
      # Right-align like the legacy gutter (drawLineNumber/lineNumberBounds):
      # pad to the width of the largest possible number.
      let baseFontSize = b.themeTextStyle(int(UiStyleIndexDefaultText))[].fontSize
      let gutterPx = storage.gutterWidthPx
      # Left indent of the first chunk: gutter on first rows, gutter + wrap
      # indent on wrapped continuation rows (drawLine:842, wrap_map.nim:99).
      let isContinuation = realLine >= 0 and firstDisplayRow != itemIndex
      var indentPx = 0.0'f32
      if showNumber:
        indentPx = gutterPx
      elif isContinuation:
        indentPx = gutterPx
        var wrapIndentCols = 4
        if self.displayMap.wrapMap != nil:
          wrapIndentCols = self.displayMap.wrapMap.snapshot.wrappedIndent
        indentPx += wrapIndentCols.float32 * storage.charWidth
      # Chunk index y replicates the virtual list's own itemTop math
      # (dynamic_virtuallist.estimatedItemTop) minus its scroll offset, so entries
      # land exactly where the list positions the row; x accumulates monospace
      # estimates from the indent. Rebuilt every frame (cleared in createUINui).
      var yLine = 0.0'f32
      if storage.listStorage != nil:
        var top = itemIndex.float32 * storage.itemHeightHint
        for sample in storage.listStorage.heights:
          if sample.itemIndex >= itemIndex:
            break
          top += sample.height - storage.itemHeightHint
        yLine = top - storage.listStorage.scrollOffsetY
      var xCursor = indentPx
      b.layoutHorizontal:
        discard b.fillX().fitY()
        if showNumber:
          # Fixed-width gutter column with the number right-aligned
          # (reverse row packs the single child at the right edge).
          b.layoutHorizontalReverse:
            discard b.width(gutterPx).fitY()
            b.node:
              # TODO(nui-text): dim line-number color (editorLineNumber.foreground),
              # gutter background (fillLineNumberBackground) and cursor-line highlight.
              discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(toOpenArray(numberBuf, 0, numberLen - 1))
        elif isContinuation:
          # Continuation (wrapped) display row without a line number: reserve the
          # indent explicitly to keep chunk text aligned with first rows.
          b.node:
            discard b.width(indentPx).fitY()
        # TODO(nui-text): sign column (§14) renders here, before the text chunks.
        var guard = 0
        var hasChunks = false
        var lineH = storage.lineHeight
        while storage.textIter.displayChunk.isSome:
          prof("chunk")
          if guard > 500:
            break
          inc guard
          let chunk = storage.textIter.displayChunk.get
          if chunk.displayPoint.row.int != itemIndex:
            break
          let styled = chunk.styledChunk
          let chunkColor = styled.color
          let chunkScale = styled.fontScale
          let chunkDisplayPoint = chunk.displayPoint
          let chunkDisplayEndPoint = chunk.endDisplayPoint
          let chunkPoint = chunk.point
          let chunkEndPoint = chunk.endPoint
          # TODO(nui-text): styled.fontStyle (Bold/Italic) + underline/undercurl +
          # drawWhitespace have no nuigi UiNodeText equivalent; only color + scale
          # are applied. Whole-line backgroundColumn (diff/selection/cursor-line)
          # and inline diagnostics (§14) are not rendered yet either.
          discard storage.textIter.next()
          if chunk.len == 0:
            continue
          hasChunks = true
          let uiColor = rgba(chunkColor.r.float32, chunkColor.g.float32, chunkColor.b.float32, chunkColor.a.float32)
          let entryX = xCursor
          var chunkNodeIdx = -1
          b.node:
            chunkNodeIdx = b.currentNodeIndex
            discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(uiColor).fontSize(baseFontSize * chunkScale.float32).text(chunk.toOpenArray)
            # text() synchronously re-measures fit nodes (updateNodeFit), so the
            # real width is available right away for the chunk index.
            xCursor += b.currentNode.size.x
          lineH = max(lineH, b.frame.nodes[chunkNodeIdx].size.y)
          storage.chunkIndex.add TextChunkIndexEntry(
            nodeIndex: chunkNodeIdx,
            displayPoint: chunkDisplayPoint,
            displayEndPoint: chunkDisplayEndPoint,
            point: chunkPoint,
            endPoint: chunkEndPoint,
            posX: entryX,
            posY: yLine)
          # Click handling (textfield pattern: polled wasPressed, no callbacks):
          # move the cursor to the pressed position.
          block:
            let cn = b.frame.nodes[chunkNodeIdx].addr
            if b.wasPressed(cn.id, false, chunkNodeIdx):
              let prevPos = b.absoluteNodePosPrev(cn.id, chunkNodeIdx)
              let slot = int(cn.textIndex)
              if slot > 0 and slot <= b.frame.texts.len:
                var clickStyle = b.frame.texts[slot - 1]
                # Materialize the chunk text only on actual press (not per frame).
                var clickText = newStringOfCap(chunk.len)
                for c in chunk.toOpenArray:
                  clickText.add c
                let off = nuiByteOffsetAtX(b, clickText, b.frameCtx.input.mouse.x - prevPos.x, clickStyle)
                let newCursor = chunkPoint.toCursor + (0, off)
                b.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} =
                  self.layout.tryActivateEditor(self)
                  # TODO(nui-text): double/triple/control-click commands
                  # (runDoubleClickCommand etc.) + drag selection (§14). Clicks only
                  # land on visible rows, so no scroll-follow is needed here.
                  self.selection = newCursor.toSelection
                  self.dragStartSelection = self.selection
                  self.updateTargetColumn(Last)
                  self.markDirty())
        # Frontier advance: the iterator now yields itemIndex + 1, so the next
        # sequential line continues without seeking.
        storage.iterNextRow = itemIndex + 1
        if not hasChunks:
          # Index the fallback node too so cursors on empty lines have a position.
          var fallbackNodeIdx = -1
          b.node:
            fallbackNodeIdx = b.currentNodeIndex
            discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(" ")
          try:
            let emptyPoint = self.displayMap.toPoint(displayPoint(itemIndex, 0))
            storage.chunkIndex.add TextChunkIndexEntry(
              nodeIndex: fallbackNodeIdx,
              displayPoint: displayPoint(itemIndex, 0),
              displayEndPoint: displayPoint(itemIndex, 0),
              point: emptyPoint,
              endPoint: emptyPoint,
              posX: xCursor,
              posY: yLine)
          except:
            discard
        # Rest-of-line click target: filler takes the remaining row width so clicks
        # past the last chunk place the cursor at end of line.
        var fillerNodeIdx = -1
        b.node:
          fillerNodeIdx = b.currentNodeIndex
          discard b.fillX().height(lineH)
        block:
          let fn = b.frame.nodes[fillerNodeIdx].addr
          if b.wasPressed(fn.id, false, fillerNodeIdx):
            let lineEnd = self.displayMap.toPoint(displayPoint(itemIndex, self.displayMap.lineLen(itemIndex))).toCursor
            b.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} =
              self.layout.tryActivateEditor(self)
              # TODO(nui-text): double/triple/control-click commands + drag (§14).
              self.selection = lineEnd.toSelection
              self.dragStartSelection = self.selection
              self.updateTargetColumn(Last)
              self.markDirty())
        # TODO(nui-text): below-line content (§14) – inline diagnostics (Below mode),
        # context lines, custom overlay renderers (Below/Above), diff backgrounds,
        # selections, cursors, scrollbar – none rendered yet; see checklist in ui_rewrite.md §14.
      storage.arena.restoreCheckpoint(arenaCheckpoint)
    except:
      discard

proc appendTextHighlightNui(b: var UiBuilder, storage: TextDocumentEditorNuiStorage,
    selection: Selection, highlightColor: Color, drawEmpty: bool) =
  let normalized = selection.normalized
  let selectionStart = normalized.first.toPoint
  let selectionEnd = normalized.last.toPoint
  let empty = normalized.isEmpty
  if empty and not drawEmpty:
    return

  let uiColor = rgba(highlightColor.r.float32, highlightColor.g.float32,
    highlightColor.b.float32, highlightColor.a.float32)
  var rects: seq[tuple[x, y, w, h: float32]] = @[]
  for entry in storage.chunkIndex:
    if empty:
      if selectionStart < entry.point or selectionStart > entry.endPoint:
        continue
    elif entry.endPoint < selectionStart or entry.point >= selectionEnd:
      continue
    if entry.nodeIndex < 0 or entry.nodeIndex >= b.frame.nodes.len:
      continue
    let chunkNode = b.frame.nodes[entry.nodeIndex].addr
    let textSlot = int(chunkNode.textIndex)
    if textSlot <= 0 or textSlot > b.frame.texts.len:
      continue
    let nodeText = b.frame.texts[textSlot - 1]
    let chunkText = nodeText.text.value
    var firstByte = 0
    var lastByte = chunkText.len
    if selectionStart > entry.point and selectionStart.row == entry.point.row:
      firstByte = (selectionStart.column.int - entry.point.column.int).clamp(0, chunkText.len)
    if selectionEnd < entry.endPoint and selectionEnd.row == entry.point.row:
      lastByte = (selectionEnd.column.int - entry.point.column.int).clamp(0, chunkText.len)
    if lastByte < firstByte or (lastByte == firstByte and not empty):
      continue

    let firstX = b.nuiMeasuredPrefixWidth(chunkText, firstByte, nodeText)
    let lastX = b.nuiMeasuredPrefixWidth(chunkText, lastByte, nodeText)
    let x = entry.posX + firstX
    let y = entry.posY
    let w = max(lastX - firstX, ceil(storage.charWidth * 0.25'f32))
    let h = max(storage.lineHeight, chunkNode.size.y)
    if rects.len > 0 and rects[^1].y == y and rects[^1].h == h and
        abs((rects[^1].x + rects[^1].w) - x) < 0.1'f32:
      rects[^1].w += w
    else:
      rects.add (x, y, w, h)
    if empty:
      break

  for bounds in rects:
    var command = UiRenderCommand(kind: CmdRectFill, color: uiColor)
    command.pos.x = bounds.x
    command.pos.y = bounds.y
    command.size.x = bounds.w
    command.size.y = bounds.h
    storage.highlightCommands.add command

proc buildTextHighlightsNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, raises: [].} =
  ## Highlight backgrounds share one deferred command layer. The cursor layer is
  ## declared after this one, so cursors always paint on top.
  {.cast(gcsafe).}:
    prof("buildTextHighlightsNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      let self = storage.editor
      if self.isNil or self.document.isNil or storage.theme.isNil or
          not self.document.isInitialized or storage.chunkIndex.len == 0:
        return

      storage.highlightCommands.setLen(0)
      for highlights in self.decorations.customHighlights.values:
        for highlight in highlights:
          let highlightColor = storage.theme.color(highlight.color,
            color(200/255, 200/255, 200/255)) * highlight.tint
          b.appendTextHighlightNui(storage, highlight.selection, highlightColor, true)

      let selectionColor = storage.theme.color("selection.background", color(200/255, 200/255, 200/255))
      let inclusive = self.config.get("text.inclusive-selection", false)
      let thick = self.isThickCursor()
      for selection in self.selections:
        var selection = selection.normalized
        if thick and inclusive:
          selection.last.column += 1
        b.appendTextHighlightNui(storage, selection, selectionColor, false)

      if storage.highlightCommands.len > 0:
        discard b.customRenderCommands(storage.highlightCommands)
    except:
      discard

proc buildTextCursorNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, raises: [].} =
  ## Cursor overlay, deferred after the virtual list (registered after it, so chunk
  ## index positions and node sizes are final). One rect per selection cursor plus
  ## rune inversion for block cursors (mirrors legacy drawCursors).
  {.cast(gcsafe).}:
    prof("buildTextCursorNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.displayMap.isNil or self.document.isNil or storage.theme.isNil:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0 or not self.cursorVisible:
        return
      # TODO(nui-text): cursor trail animation (cursorHistories + markDirty loop),
      # lastCursorLocationBounds / hover + signature-help anchors (§14).
      let cursorFg = storage.theme.color("editorCursor.foreground", color(200/255, 200/255, 200/255))
      let cursorBg = storage.theme.color("editorCursor.background", color(50/255, 50/255, 50/255))
      let fgUi = rgba(cursorFg.r.float32, cursorFg.g.float32, cursorFg.b.float32, cursorFg.a.float32)
      let bgUi = rgba(cursorBg.r.float32, cursorBg.g.float32, cursorBg.b.float32, cursorBg.a.float32)
      let charW = storage.charWidth
      let thick = self.isThickCursor()
      for s in self.selections:
        let p = s.last.toPoint
        # Last entry starting at/before the cursor on its row (entries are built in
        # display order, like legacy Bias.Left search; off-screen cursor → skip).
        var best = -1
        for i, e in storage.chunkIndex:
          if e.point.row.int != p.row.int:
            continue
          if e.point.column.int <= p.column.int:
            best = i
          else:
            break
        if best < 0:
          continue
        let e = storage.chunkIndex[best]
        if e.nodeIndex < 0 or e.nodeIndex >= b.frame.nodes.len:
          continue
        let entryNode = b.frame.nodes[e.nodeIndex].addr
        let textSlot = int(entryNode.textIndex)
        if textSlot <= 0 or textSlot > b.frame.texts.len:
          continue
        let nt = b.frame.texts[textSlot - 1].addr
        let nodeText = nt.text.value
        # Exact x via substring measurement with the chunk's own font (same shaper
        # that draws the node, so positions match what is rendered).
        var byteOff = p.column.int - e.point.column.int
        if byteOff < 0:
          byteOff = 0
        if byteOff > nodeText.len:
          byteOff = nodeText.len
        var prefixW = 0.0'f32
        if byteOff > 0:
          var tmp = UiNodeText(text: nodeText[0 ..< byteOff].uiString, fontId: nt.fontId, fontSize: nt.fontSize)
          let arr = b.getTextArrangement(tmp.addr, -1)
          if arr != nil:
            prefixW = arr.size.x
        let cx = e.posX + prefixW
        let ch = max(storage.lineHeight, entryNode.size.y)
        let cw = if thick: charW else: charW * 0.2'f32
        b.node:
          discard b.position(cx, e.posY).size(cw, ch).fillBackground().backgroundColor(fgUi)
        if thick:
          let r = self.document.runeAt(s.last)
          if r != 0.Rune and r.int >= ' '.int:
            b.node:
              discard b.position(cx, e.posY).fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(bgUi).fontSize(nt.fontSize).text($r)
    except:
      discard

proc nuiPopupAnchor(b: var UiBuilder, storage: TextDocumentEditorNuiStorage,
    p: Point): tuple[cx: float32, cy: float32, found: bool] {.nimcall, gcsafe, raises: [].} =
  ## Viewport-relative anchor for a buffer point, mirroring the cursor lookup in
  ## buildTextCursorNui (last chunk entry starting at/before the point on its
  ## row, exact x via substring measurement with the chunk's own font).
  {.cast(gcsafe).}:
    try:
      var best = -1
      for i, e in storage.chunkIndex:
        if e.point.row.int != p.row.int:
          continue
        if e.point.column.int <= p.column.int:
          best = i
        else:
          break
      if best < 0:
        return (0.0'f32, 0.0'f32, false)
      let e = storage.chunkIndex[best]
      if e.nodeIndex < 0 or e.nodeIndex >= b.frame.nodes.len:
        return (0.0'f32, 0.0'f32, false)
      let entryNode = b.frame.nodes[e.nodeIndex].addr
      let textSlot = int(entryNode.textIndex)
      if textSlot <= 0 or textSlot > b.frame.texts.len:
        return (e.posX, e.posY, true)
      let nt = b.frame.texts[textSlot - 1].addr
      let nodeText = nt.text.value
      var byteOff = p.column.int - e.point.column.int
      if byteOff < 0:
        byteOff = 0
      if byteOff > nodeText.len:
        byteOff = nodeText.len
      var prefixW = 0.0'f32
      if byteOff > 0:
        var tmp = UiNodeText(text: nodeText[0 ..< byteOff].uiString, fontId: nt.fontId, fontSize: nt.fontSize)
        let arr = b.getTextArrangement(tmp.addr, -1)
        if arr != nil:
          prefixW = arr.size.x
      return (e.posX + prefixW, e.posY, true)
    except:
      return (0.0'f32, 0.0'f32, false)

proc buildCompletionRowNui(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Single completion row for the listTable popup (userData is the text-root
  ## node index, like buildTextLineNui). The deferred list build already wraps
  ## each item in a positioned node, so the current node IS the row: style it
  ## directly (full-row background) and emit one child node per cell
  ## (label + source/detail) – no horizontal wrapper, listTableColumnLayout
  ## aligns cells into columns across the rendered batch. Completion match
  ## colors are derived from the selected/unselected text style slots.
  # todo: reverse order
  discard b.fillX().fitY()
  {.cast(gcsafe).}:
    prof("buildCompletionRowNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil:
        return
      if itemIndex < 0 or itemIndex >= self.completionMatches.len:
        return
      const maxLabelLen = 30
      const maxTypeLen = 30
      let completion {.cursor.} = self.completions[self.completionMatches[itemIndex].index]
      let isSel = itemIndex == self.selectedCompletion
      discard b.fillBackground().styleIndex(if isSel: UiStyleIndexMenuItemHover else: UiStyleIndexMenuItem)
      let labelStyle = if isSel: UiStyleIndexMenuItemHoverText else: UiStyleIndexMenuItemText
      let label = if completion.item.label.len < maxLabelLen:
          completion.item.label
        else:
          completion.item.label[0..<(maxLabelLen - 3)] & "..."
      let matchIndices = self.getCompletionMatches(itemIndex)
      let labelColor = b.themeTextStyle(labelStyle)[].textColor
      let highlightColor = b.themeStyle(UiStyleIndexAccent)[].fillColor
      b.highlightedText(label, matchIndices, labelColor, highlightColor)
      let detail = if completion.item.detail.getSome(d):
          if d.len < maxTypeLen: d else: d[0..<(maxTypeLen - 3)] & "..."
        else:
          ""
      b.node:
        discard b.fit().textStyleIndex(int(UiStyleIndexMutedText)).text(completion.source & " " & detail)
      if b.wasPressed(includeChildren = true):
        self.selectedCompletion = itemIndex
        self.markDirty()
    except:
      discard

proc buildTextCompletionsNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Completion popup, deferred after the virtual list so chunk-index anchors are
  ## final (mirrors legacy createCompletions at widget_builder_text_document:288).
  ## Rows render virtualized via listTable (nested deferred build, picked up by
  ## the flush loop in the same frame; columns Fit/Fit so source/detail aligns
  ## across the rendered batch); docs for the selected item render in
  ## a panel to the right of the list, same height (mirrors legacy x = listNode.xw).
  ## If the popup would overflow the layer below the cursor it flips above the
  ## cursor line (mirrors legacy createCompletions reverse/pivot and the
  ## dropdownPopupReposition clamp in nuigi/widgets.nim).
  ## The popup attaches to the overlay node (like dropdown-popup) so it paints
  ## above the editor layout and is not clipped by it: the layer-relative
  ## anchor is converted to absolute coords via absoluteNodePos and clamped
  ## against the overlay size.
  ## v1 parity note: fuzzy-match highlight not yet ported.
  {.cast(gcsafe).}:
    prof("buildTextCompletionsNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil:
        return
      if not self.showCompletions or not self.active or self.completionMatches.len == 0:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0:
        return
      let lineH = if storage.lineHeight > 0.0'f32: storage.lineHeight else: textLineHeightHint
      let anchor = b.nuiPopupAnchor(storage, self.selection.last.toPoint)
      if not anchor.found:
        return
      const maxLabelLen = 30
      const numLinesToShow = 15
      const docsWidthChars = 75.0'f32
      let totalRows = self.completionMatches.len
      let listW = 340.0'f32
      let listH = min(totalRows, numLinesToShow).float32 * lineH + 4.0'f32
      let popupH = listH
      var docText = ""
      if self.selectedCompletion >= 0 and self.selectedCompletion < self.completionMatches.len:
        let sel = self.completions[self.completionMatches[self.selectedCompletion].index]
        if sel.item.label.len >= maxLabelLen:
          docText.add sel.item.label
          docText.add "\n"
        if sel.item.detail.getSome(detail):
          docText.add detail
        if sel.item.documentation.getSome(doc):
          if docText.len > 0:
            docText.add "\n\n"
          if doc.asString().getSome(docStr):
            docText.add docStr
          elif doc.asMarkupContent().getSome(markup):
            docText.add markup.value
      let charW = max(storage.charWidth, 1.0'f32)
      let docsW = if docText.len > 0: docsWidthChars * charW else: 0.0'f32
      let popupW = listW + docsW
      var px = anchor.cx
      var py = anchor.cy + lineH
      if px < 0.0'f32:
        px = 0.0'f32
      # Layer-relative -> absolute: the popup lives under the overlay node.
      var absX = px
      var absY = py
      try:
        let layerAbs = b.absoluteNodePos(nodeIdx)
        absX += layerAbs.x
        absY += layerAbs.y
      except:
        discard
      try:
        let overlayIdx = b.currentNodeIndex(b.overlays)
        if overlayIdx >= 0 and overlayIdx < b.frame.nodes.len:
          let overlaySize = b.frame.nodes[overlayIdx].size
          if overlaySize.x > popupW and absX + popupW > overlaySize.x:
            absX = max(overlaySize.x - popupW, 0.0'f32)
          if absY + popupH > overlaySize.y:
            let aboveY = absY - lineH - popupH
            absY = if aboveY >= 0.0'f32: aboveY else: max(0.0'f32, overlaySize.y - popupH)
          if absY < 0.0'f32:
            absY = 0.0'f32
      except:
        discard
      if absX < 0.0'f32:
        absX = 0.0'f32
      b.withParent(b.overlays):
        b.pushId(userData.uint64)
        b.node("text-completions-popup-overlay"):
          discard b.position(absX, absY).fitX().height(popupH).fillBackground().styleIndex(UiStyleIndexMenu)
          b.layoutHorizontal("text-completions-popup"):
            discard b.fitX().fillY().gap(2)
            b.node("text-completions-list"):
              discard b.width(listW).fillY()
              let listStorage = b.listTable(totalRows, lineH, [tableColumnFit(), tableColumnFit()], buildCompletionRowNui, userData)
              # Follow keyboard selection like legacy updateBaseIndexAndScrollOffset:
              # scrollToCompletion is set on selection change and consumed here.
              if self.scrollToCompletion.isSome:
                let target = self.scrollToCompletion.get
                if target >= 0 and target < totalRows:
                  discard listStorage.ensureItemVisible(target, b.currentNode.size.y, 0.0'f32)
                self.scrollToCompletion = none(int)
            if docText.len > 0:
              b.node("text-completions-docs"):
                discard b.width(docsW).fillY().fillBackground().styleIndex(UiStyleIndexTooltip).padding(4).wrapText().maskChildren().textStyleIndex(int(UiStyleIndexDefaultText)).text(docText)
        b.popId()
    except:
      discard

proc buildTextHoverNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Hover popup, deferred after the virtual list (mirrors legacy createHover at
  ## widget_builder_text_document:196). Anchored at the hover location from the
  ## chunk index; custom hover views render via View.renderNui, otherwise plain
  ## hover text lines. v1 places the popup below the cursor (legacy pivots it
  ## above); clamping to the viewport is best-effort.
  {.cast(gcsafe).}:
    prof("buildTextHoverNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil or storage.theme.isNil:
        return
      if self.hoverComponent.isNil or not self.hoverComponent.showHover:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0:
        return
      let lineH = if storage.lineHeight > 0.0'f32: storage.lineHeight else: textLineHeightHint
      let anchor = b.nuiPopupAnchor(storage, self.hoverComponent.hoverLocation)
      if not anchor.found:
        return
      let bg = storage.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
      let border = storage.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
      let fg = storage.theme.color("editor.foreground", color(1, 1, 1))
      let bgUi = rgba(bg.r.float32, bg.g.float32, bg.b.float32, bg.a.float32)
      let borderUi = rgba(border.r.float32, border.g.float32, border.b.float32, border.a.float32)
      let fgUi = rgba(fg.r.float32, fg.g.float32, fg.b.float32, fg.a.float32)
      const popupW = 400.0'f32
      var px = anchor.cx
      let py = anchor.cy + lineH
      if px < 0.0'f32:
        px = 0.0'f32
      try:
        if nodeIdx >= 0 and nodeIdx < b.frame.nodes.len:
          let layerW = b.frame.nodes[nodeIdx].size.x
          if layerW > popupW and px + popupW > layerW:
            px = max(layerW - popupW, 0.0'f32)
      except:
        discard
      b.node:
        discard b.position(px, py).width(popupW).fitY().fillBackground().styleIndex(UiStyleIndexPanel).backgroundColor(bgUi).borderColor(borderUi).borderWidth(1.0'f32).padding(6)
        if self.hoverComponent.hoverView != nil:
          try:
            self.hoverComponent.hoverView.render(b)
          except:
            b.node:
              discard b.fillX().fitY().wrapText().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(fgUi).text("[hover view]")
        else:
          for line in self.hoverComponent.hoverText.splitLines:
            b.node:
              discard b.fillX().fitY().wrapText().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(fgUi).text(line)
        for overlay in self.hoverComponent.overlayViews:
          if overlay.isNil:
            continue
          try:
            overlay.render(b)
          except:
            discard
    except:
      discard

proc buildTextSignatureHelpNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Signature-help popup, deferred after the virtual list (mirrors legacy
  ## createSignatureHelp at widget_builder_text_document:230). Inactive
  ## signatures render dimmed (capped like legacy), the active signature and its
  ## active parameter render highlighted. v1 places the popup below the cursor
  ## (legacy pivots it above); per-param text colors are content colors.
  {.cast(gcsafe).}:
    prof("buildTextSignatureHelpNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil or storage.theme.isNil:
        return
      if not self.showSignatureHelp:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0:
        return
      let lineH = if storage.lineHeight > 0.0'f32: storage.lineHeight else: textLineHeightHint
      let anchor = b.nuiPopupAnchor(storage, self.signatureHelpLocation.toPoint)
      if not anchor.found:
        return
      let bg = storage.theme.color(@["editorHoverWidget.background", "panel.background"], color(30/255, 30/255, 30/255))
      let border = storage.theme.color(@["editorHoverWidget.border", "focusBorder"], color(30/255, 30/255, 30/255))
      let fg = storage.theme.color("editor.foreground", color(1, 1, 1))
      let faded1 = storage.theme.color("editor.foreground.fade1", fg.darken(0.15))
      let faded2 = storage.theme.color("editor.foreground.fade2", faded1.darken(0.15))
      let highlighted = storage.theme.color("editor.foreground.highlight", fg.lighten(0.15))
      let activeParamC = storage.theme.color("signatureHelp.activeParam", highlighted)
      let activeSigC = storage.theme.color("signatureHelp.activeSignature", fg)
      let inactiveParamC = storage.theme.color("signatureHelp.inactiveParam", faded1)
      let inactiveSigC = storage.theme.color("signatureHelp.inactiveSignature", faded2)
      let bgUi = rgba(bg.r.float32, bg.g.float32, bg.b.float32, bg.a.float32)
      let borderUi = rgba(border.r.float32, border.g.float32, border.b.float32, border.a.float32)
      let activeParamUi = rgba(activeParamC.r.float32, activeParamC.g.float32, activeParamC.b.float32, activeParamC.a.float32)
      let activeSigUi = rgba(activeSigC.r.float32, activeSigC.g.float32, activeSigC.b.float32, activeSigC.a.float32)
      let inactiveParamUi = rgba(inactiveParamC.r.float32, inactiveParamC.g.float32, inactiveParamC.b.float32, inactiveParamC.a.float32)
      let inactiveSigUi = rgba(inactiveSigC.r.float32, inactiveSigC.g.float32, inactiveSigC.b.float32, inactiveSigC.a.float32)
      const popupW = 420.0'f32
      var px = anchor.cx
      let py = anchor.cy + lineH
      if px < 0.0'f32:
        px = 0.0'f32
      try:
        if nodeIdx >= 0 and nodeIdx < b.frame.nodes.len:
          let layerW = b.frame.nodes[nodeIdx].size.x
          if layerW > popupW and px + popupW > layerW:
            px = max(layerW - popupW, 0.0'f32)
      except:
        discard
      b.node:
        discard b.position(px, py).width(popupW).fitY().fillBackground().styleIndex(UiStyleIndexPanel).backgroundColor(bgUi).borderColor(borderUi).borderWidth(1.0'f32).padding(6)
        b.layoutVertical("text-signature-rows"):
          discard b.fillX().fitY().gap(2)
          var shown = 0
          for k, sig in self.signatures:
            if k == self.currentSignature:
              continue
            let activeParam = sig.activeParameter.get(self.currentSignatureParam)
            b.layoutHorizontal("signature-row"):
              discard b.fillX().fitY()
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(inactiveSigUi).text("(")
              for i, p in sig.parameters:
                if i > 0:
                  b.node:
                    discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(inactiveSigUi).text(", ")
                var paramStr = ""
                if p.label.kind == JString:
                  paramStr = p.label.getStr
                else:
                  paramStr = $p.label
                let paramUi = if i == activeParam: inactiveParamUi else: inactiveSigUi
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(paramUi).text(paramStr)
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(inactiveSigUi).text(")")
            inc shown
            if shown > 5:
              break
          if self.currentSignature in 0..self.signatures.high:
            let sig = self.signatures[self.currentSignature]
            let activeParam = sig.activeParameter.get(self.currentSignatureParam)
            b.layoutHorizontal("signature-active-row"):
              discard b.fillX().fitY()
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text("(")
              for i, p in sig.parameters:
                if i > 0:
                  b.node:
                    discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text(", ")
                var paramStr = ""
                if p.label.kind == JString:
                  paramStr = p.label.getStr
                else:
                  paramStr = $p.label
                let paramUi = if i == activeParam: activeParamUi else: activeSigUi
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(paramUi).text(paramStr)
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text(")")
          if self.signatures.len == 0:
            b.node:
              discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text("No signatures")
    except:
      discard

proc createUINui*(self: TextDocumentEditor, nui: var UiBuilder) {.gcsafe, raises: [].} =
  # The virtual list always reserves its scrollbar track beside the viewport
  # (dynamic_virtuallist scrollbarWidth: 10px GUI, 1px terminal), so the wrap
  # width must exclude it or lines wrap under the scrollbar.
  let sbW = if nui.backendType == UiBackendType.Terminal: 1.0'f32 else: 10.0'f32
  self.preRender(rect(0, 0, max(nui.currentNode.size.x - sbW, 0), nui.currentNode.size.y))

  let dirty = self.dirty

  {.cast(gcsafe).}:
    self.resetDirty()
    # Background color based on active state – use accentVariation instead of switching styleIndex (nuigi.nim:1122)
    let baseBg = nui.themeStyle(UiStyleIndexPanel)[].fillColor
    let bgColor = if self.active: accentVariation(baseBg, 0.06'f32, 1.12'f32) else: baseBg
    let headerBase = nui.themeStyle(UiStyleIndexHeader)[].fillColor
    let headerColor = if self.active: accentVariation(headerBase, 0.04'f32, 1.10'f32) else: headerBase
    nui.layoutVertical("text-root"):
      discard nui.fillX().fillY().fillBackground().styleIndex(UiStyleIndexPanel).backgroundColor(bgColor).padding(0).gap(4)
      nui.nodeStorageParent()
      nui.getOrCreateTextEditorNuiStorage(nui.currentNode).editor = self
      let rootIndex = nui.currentNodeIndex
      # Snapshot per-frame settings for the deferred line builder (buildTextLineNui
      # runs later and only sees the storage, not self).
      block:
        let storage = nui.getOrCreateTextEditorNuiStorage(nui.frame.nodes[rootIndex].addr)
        if not storage.arena.isValid:
          echo "in it arena"
          storage.arena = initArena()
        try:
          storage.theme = self.services.getServiceChecked(ThemeService).theme
        except:
          discard
        try:
          storage.useHighlight = self.config.getUiSyntaxHighlighting()
          storage.rainbowParens = self.config.getUiRainbowParentheses()
          storage.lineNumbers = self.config.getUiLineNumbers()
          storage.cursorLine = self.selection.last.line
        except:
          discard
        # Fresh chunk index every frame; the deferred line builder appends while
        # rendering (mirrors legacy per-frame chunkBounds).
        storage.chunkIndex.setLen(0)
        storage.itemHeightHint = textLineHeightHint
        # Character metrics measured from the mono font like terminal/render.nim:479,
        # so the line-number gutter gets an explicit pixel width instead of spaces.
        var charW = 8.0'f32
        var charH = 16.0'f32
        if self.platform != nil:
          try:
            charW = self.platform.charWidth.float32
            charH = self.platform.lineHeight.float32
          except: discard
        try:
          let monoStyle = nui.themeTextStyle(UiStyleIndexDefaultMono)[]
          var tmpText = UiNodeText(text: "M".uiString, fontId: monoStyle.fontId, fontSize: monoStyle.fontSize.float32)
          let arr = nui.getTextArrangement(tmpText.addr, -1)
          if arr != nil:
            if arr.size.x > 0: charW = arr.size.x
            if arr.size.y > 0: charH = arr.size.y
        except:
          discard
        if charW <= 0: charW = 8.0'f32
        if charH <= 0: charH = 16.0'f32
        storage.charWidth = charW
        storage.lineHeight = charH
        # Total line-number column width ahead of time (mirrors lineNumberBounds in
        # text_editor.nim:672: digits of the largest number + 1 padding, in pixels).
        var gutterPx = 0.0'f32
        try:
          case storage.lineNumbers
          of LineNumbers.Absolute:
            if self.document != nil:
              gutterPx = (($self.document.numLines).len + 1).float32 * charW
          of LineNumbers.Relative:
            gutterPx = (($99).len + 1).float32 * charW
          else: discard
        except:
          discard
        storage.gutterWidthPx = gutterPx
        # Fresh forward iterator for this frame, reused across lines (one
        # construction per frame instead of per line).
        if self.document != nil and self.displayMap != nil:
          createNuiIter(self, storage)
      # Header – replicates `createHeader` logic from widget_library (mode, dirty, file, dir + right side)
      if self.renderHeader:
        nui.layoutHorizontal("text-header"):
          discard nui.fillX().fitY().fillBackground().styleIndex(UiStyleIndexHeader).backgroundColor(headerColor).padding(4).gap(8)
          let modeText = if self.mode.len == 0: "-" else: self.mode
          let isDirty = if self.document != nil: self.document.lastSavedRevision != self.document.revision else: false
          let dirtyMarker = if isDirty: "*" else: ""
          let (directory, filename) = if self.document != nil: self.document.localizedPath.splitPath else: ("", "untitled")
          let leftText = " " & modeText & " - " & dirtyMarker & filename & " - " & directory & " "
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(leftText)
          # Spacer pushes right side to the end
          nui.layoutHorizontalReverse:
            discard nui.fillX().fitY()
            discard nui.checkbox("Syntax cache", gEnableSyntaxCache)
            # Right side – mirrors `createHeader` onRight: customHeader, readOnly, staged, diff, rune, cursor positions
            let readOnlyText = if self.document != nil and self.document.readOnly: "-readonly- " else: ""
            let stagedText = if self.document != nil and self.document.staged: "-staged- " else: ""
            let renderDiff = self.diffDocument != nil and self.diffDocument.isInitialized and self.diffChanges.isSome
            let diffText = if renderDiff: "-diff- " else: ""
            let currentRune = if self.document != nil: self.document.runeAt(self.selection.last) else: 0.Rune
            let currentRuneText = if currentRune == 0.Rune: "\\0"
                                  elif currentRune == '\t'.Rune: "\\t"
                                  elif currentRune == '\n'.Rune: "\\n"
                                  else: $currentRune
            var currentRuneHexText = currentRune.int.toHex.strip(trailing=false, chars={'0'})
            if currentRuneHexText.len == 0: currentRuneHexText = "0"
            proc cursorString(cursor: Cursor): string =
              if self.document != nil and self.document.isInitialized:
                $cursor.line & ":" & $cursor.column
              else: ""
            let rightText = self.customHeader & " | " & readOnlyText & stagedText & diffText & "'" & currentRuneText & "' (U+" & currentRuneHexText & ") " & cursorString(self.selection.first) & "-" & cursorString(self.selection.last)
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(rightText)
      # Body – lines via dynamic virtual list; each line is a horizontal node with one child node per chunk
      nui.node("text-body"):
        discard nui.fillX().fillY()
        var lineCount = 0
        try:
          if self.document != nil and self.displayMap != nil:
            lineCount = self.numDisplayLines
        except:
          lineCount = 0
        if lineCount <= 0:
          let path = if self.document != nil: self.document.filename
                     elif self.currentDocument != nil: self.currentDocument.filename
                     else: ""
          let displayPath = if path.len > 0: path else: "untitled"
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(displayPath)
        else:
          # Keep the list storage so the deferred line builder can replicate
          # itemTop math for chunk index positions.
          nui.getOrCreateTextEditorNuiStorage(nui.frame.nodes[rootIndex].addr).listStorage =
            nui.dynamicVirtualList(lineCount, textLineHeightHint, buildTextLineNui, rootIndex)
          # Apply pending scroll requests stored by scrollTo*/scrollLines
          # (dual-written alongside the legacy scrollBox). Consumed here so the
          # deferred list build lays out from the new offset this frame.
          # Requests are kept pending when the viewport height is still unknown.
          block:
            let editorStorage = nui.getOrCreateTextEditorNuiStorage(nui.frame.nodes[rootIndex].addr)
            let listStorage = editorStorage.listStorage
            let tec = self.textEditorComponent
            if listStorage != nil and tec != nil:
              var vpH = listStorage.viewportHeight
              if vpH <= 0.0'f32:
                try:
                  vpH = nui.currentNode.size.y
                except:
                  discard
              # Cursor margin mirrors the legacy path: relative fraction of the
              # viewport or margin-in-lines, clamped like ScrollBox.margin.
              var marginPx = 0.0'f32
              try:
                if not self.disableScrolling:
                  let lineH = if editorStorage.lineHeight > 0.0'f32: editorStorage.lineHeight else: textLineHeightHint
                  if self.config.getTextCursorMarginRelative():
                    marginPx = clamp(self.config.getTextCursorMargin(), 0.0, 1.0).float32 * 0.5'f32 * vpH
                  else:
                    marginPx = clamp(self.config.getTextCursorMargin().float32 * lineH, 0.0'f32, vpH * 0.5'f32 - lineH * 0.5'f32)
              except:
                discard
              if marginPx < 0.0'f32:
                marginPx = 0.0'f32
              if tec.nuiPendingScrollDeltaY != 0:
                listStorage.scrollByY(tec.nuiPendingScrollDeltaY.float32)
                tec.nuiPendingScrollDeltaY = 0
              if tec.nuiPendingScrollToY.isSome:
                let t = tec.nuiPendingScrollToY.get
                if listStorage.scrollToItemAtOffset(t.index, t.yOffset.float32, vpH):
                  tec.nuiPendingScrollToY = none(tuple[index: int, yOffset: float])
              elif tec.nuiPendingScrollTo.isSome:
                let t = tec.nuiPendingScrollTo.get
                if listStorage.scrollToItem(t.index, vpH, marginPx, t.center, t.centerOffscreen):
                  tec.nuiPendingScrollTo = none(tuple[index: int, center: bool, centerOffscreen: bool, snap: bool])
          nui.node("text-highlight-layer"):
            discard nui.fillX().fillY().noHover()
            discard nui.deferBuild(buildTextHighlightsNui, rootIndex)
          # Cursor overlay after the selection layer (paints on top); positions
          # resolve from the chunk index once the list is laid out.
          nui.node("text-cursor-layer"):
            discard nui.fillX().fillY().noHover()
            discard nui.deferBuild(buildTextCursorNui, rootIndex)
          # Popup overlays after cursors (paint on top); anchors resolve from
          # the chunk index once the list is laid out (mirrors the legacy
          # OverlayFunctions at widget_builder_text_document:1877).
          if self.showCompletions and self.active:
            nui.node("text-completions-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextCompletionsNui, rootIndex)
          if self.hoverComponent != nil and self.hoverComponent.showHover:
            nui.node("text-hover-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextHoverNui, rootIndex)
          if self.showSignatureHelp:
            nui.node("text-signature-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextSignatureHelpNui, rootIndex)
