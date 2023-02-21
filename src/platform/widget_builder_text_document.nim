import std/[strformat, tables, sugar, sequtils]
import util, editor, document_editor, text_document, custom_logger, widgets, platform, theme
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

proc clampToLine(selection: Selection, line: int, lineLength: int): tuple[first: int, last: int] =
  result.first = if selection.first.line < line: 0 elif selection.first.line == line: selection.first.column else: lineLength
  result.last = if selection.last.line < line: 0 elif selection.last.line == line: selection.last.column else: lineLength

proc renderTextHighlight(panel: WPanel, app: Editor, startOffset: float, endOffset: float, line: int, startIndex: int, selection: Selection, selectionClamped: tuple[first: int, last: int], part: StyledText, color: Color) =
  ## Fills a selection rect in the given color
  var left, right: float
  if startIndex < selectionClamped.last and startIndex + part.text.len > selectionClamped.first and part.text.len > 0:
    left = startOffset + max(0, selectionClamped.first - startIndex).float32 / (part.text.len.float32 - 0) * (endOffset - startOffset)
    right = startOffset + min(part.text.len, selectionClamped.last - startIndex).float32 / (part.text.len.float32 - 0) * (endOffset - startOffset)
  elif part.text.len == 0 and selection.contains((line, startIndex)) and not selection.isEmpty:
    left = 0
    right = ceil(app.platform.charWidth * 0.5)
  else:
    return
  panel.children.add(WPanel(
    anchor: (vec2(0, 0), vec2(0, 1)),
    left: left,
    right: right,
    fillBackground: true,
    backgroundColor: color,
    lastHierarchyChange: panel.lastHierarchyChange
  ))

proc renderTextHighlight(panel: WPanel, app: Editor, startOffset: float, endOffset: float, line: int, startIndex: int, selections: openArray[Selection], selectionClamped: openArray[tuple[first: int, last: int]], part: StyledText, color: Color) =
  ## Fills selections rect in the given color
  for i in 0..<selections.len:
    renderTextHighlight(panel, app, startOffset, endOffset, line, startIndex, selections[i], selectionClamped[i], part, color)

method updateWidget*(self: TextDocumentEditor, app: Editor, widget: WPanel, frameIndex: int) =
  let lineHeight = app.platform.lineHeight
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var headerPanel: WPanel
  var headerPart1Text: WText
  var headerPart2Text: WText
  var contentPanel: WPanel
  if widget.children.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    widget.children.add(headerPanel)

    headerPart1Text = WText(text: "", sizeToContent: true, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.children.add(headerPart1Text)

    headerPart2Text = WText(text: "", sizeToContent: true, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.children.add(headerPart2Text)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.children.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
  else:
    headerPanel = widget.children[0].WPanel
    headerPart1Text = headerPanel.children[0].WText
    headerPart2Text = headerPanel.children[1].WText
    contentPanel = widget.children[1].WPanel

  # Update header
  if self.renderHeader:
    headerPanel.bottom = totalLineHeight
    contentPanel.top = totalLineHeight

    let color = if self.active: app.theme.color("tab.activeBackground", rgb(45, 45, 60))
    else: app.theme.color("tab.inactiveBackground", rgb(45, 45, 45))
    headerPanel.updateBackgroundColor(color, frameIndex)

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPart1Text.text = fmt" {mode} - {self.document.filename} "
    headerPart2Text.text = fmt" {self.selection} - {self.id} "

    headerPanel.updateLastHierarchyChangeFromChildren frameIndex
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  self.lastContentBounds = contentPanel.lastBounds
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.updateBackgroundColor(
    if self.active: app.theme.color("editor.background", rgb(25, 25, 40)) else: app.theme.color("editor.background", rgb(25, 25, 25)) * 0.75,
    frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty):
    return

  self.resetDirty()

  # either layout or content changed, update the lines
  # let timer = startTimer()
  contentPanel.children.setLen 0

  block:
    self.previousBaseIndex = self.previousBaseIndex.clamp(0..self.document.lines.len)

    # Adjust scroll offset and base index so that the first node on screen is the base
    while self.scrollOffset < 0 and self.previousBaseIndex + 1 < self.document.lines.len:
      if self.scrollOffset + totalLineHeight >= contentPanel.lastBounds.h:
        break
      self.previousBaseIndex += 1
      self.scrollOffset += totalLineHeight

    # Adjust scroll offset and base index so that the first node on screen is the base
    while self.scrollOffset > contentPanel.lastBounds.h and self.previousBaseIndex > 0:
      if self.scrollOffset - lineHeight <= 0:
        break
      self.previousBaseIndex -= 1
      self.scrollOffset -= totalLineHeight

  var selectionsPerLine = initTable[int, seq[Selection]]()
  for s in self.selections:
    let sn = s.normalized
    for line in sn.first.line..sn.last.line:
      selectionsPerLine.mgetOrPut(line, @[]).add s

  var highlightsPerLine = self.searchResults

  let lineNumbers = self.lineNumbers.get getOption[LineNumbers](app, "editor.text.line-numbers", LineNumbers.Absolute)
  let maxLineNumber = case lineNumbers
    of LineNumbers.Absolute: self.previousBaseIndex + ((contentPanel.lastBounds.h - self.scrollOffset) / totalLineHeight).int
    of LineNumbers.Relative: 99
    else: 0
  let maxLineNumberLen = ($maxLineNumber).len + 1
  let cursorLine = self.selection.last.line

  self.lastRenderedLines.setLen 0

  # Update content
  proc renderLine(i: int, down: bool): bool =
    # Pixel coordinate of the top left corner of the entire line. Includes line number
    let top = (i - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

    # Bounds of the previous line part
    if top >= contentPanel.lastBounds.h:
      return not down
    if top + totalLineHeight <= 0:
      return down

    var styledText = self.document.getStyledText(i)

    let selectionsNormalizedOnLine = selectionsPerLine.getOrDefault(i, @[]).map (s) => s.normalized
    let selectionsClampedOnLine = selectionsNormalizedOnLine.map (s) => s.clampToLine(i, styledText.len)
    let highlightsNormalizedOnLine = highlightsPerLine.getOrDefault(i, @[]).map (s) => s.normalized
    let highlightsClampedOnLine = highlightsNormalizedOnLine.map (s) => s.clampToLine(i, styledText.len)

    var lineWidget = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, right: -1, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)

    var startOffset = 0.0
    var startIndex = 0
    for partIndex, part in styledText.parts:
      let width = part.text.len.float * charWidth

      # Draw background if selected
      let selectionColor = app.theme.color("selection.background", rgb(200, 200, 200))
      renderTextHighlight(lineWidget, app, startOffset, startOffset + width, i, startIndex, selectionsNormalizedOnLine, selectionsClampedOnLine, part, selectionColor)

      let highlightColor = app.theme.color(@["editor.rangeHighlightBackground"], rgb(200, 200, 200))
      renderTextHighlight(lineWidget, app, startOffset, startOffset + width, i, startIndex, highlightsNormalizedOnLine, highlightsClampedOnLine, part, highlightColor)

      let isWide = getOption[bool](app, self.getContextWithMode("editor.text.cursor.wide"))
      let cursorWidth = if isWide: 1.0 else: 0.2

      # Set last cursor pos if it's contained in this part
      let cursorColor = app.theme.color(@["editorCursor.foreground", "foreground"], rgba(255, 255, 255, 127))
      for selection in selectionsPerLine.getOrDefault(i, @[]):
        if selection.last.line == i and selection.last.column >= startIndex and selection.last.column <= startIndex + part.text.len:
          let offsetFromPartStart = if part.text.len == 0: 0.0 else: (selection.last.column - startIndex).float32 / (part.text.len.float32) * width
          lineWidget.children.add(WPanel(
            anchor: (vec2(0, 0), vec2(0, 1)),
            left: startOffset + offsetFromPartStart,
            right: startOffset + offsetFromPartStart + cursorWidth * charWidth,
            fillBackground: true,
            backgroundColor: cursorColor,
            lastHierarchyChange: frameIndex
          ))

      let color = if part.scope.len == 0: textColor else: app.theme.tokenColor(part.scope, rgb(255, 200, 200))
      var partWidget = WText(text: part.text, anchor: (vec2(0, 0), vec2(0, 1)), left: startOffset, right: startOffset + width, foregroundColor: color, lastHierarchyChange: frameIndex)

      styledText.parts[partIndex].bounds = rect(partWidget.left, lineWidget.top, partWidget.right - partWidget.left, lineWidget.bottom - lineWidget.top)

      startOffset += width
      startIndex += part.text.len

      lineWidget.children.add(partWidget)

    self.lastRenderedLines.add styledText

    contentPanel.children.add lineWidget

    return true

  # Render all lines after base index
  for i in self.previousBaseIndex..self.document.lines.high:
    if not renderLine(i, true):
      break

  # Render all lines before base index
  for k in 1..self.previousBaseIndex:
    let i = self.previousBaseIndex - k
    if not renderLine(i, false):
      break

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {contentPanel.children.len} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

