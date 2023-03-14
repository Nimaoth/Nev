import std/[strformat, tables, sugar, sequtils]
import util, editor, document_editor, text_document, custom_logger, widgets, platform, theme
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

proc clampToLine(selection: Selection, line: int, lineLength: int): tuple[first: int, last: int] =
  result.first = if selection.first.line < line: 0 elif selection.first.line == line: selection.first.column else: lineLength
  result.last = if selection.last.line < line: 0 elif selection.last.line == line: selection.last.column else: lineLength

proc renderTextHighlight(panel: WPanel, app: Editor, startOffset: float, endOffset: float, line: int, startIndex: int, selection: Selection, selectionClamped: tuple[first: int, last: int], part: StyledText, color: Color, totalLineHeight: float) =
  let startOffset = startOffset.floor
  let endOffset = endOffset.ceil
  ## Fills a selection rect in the given color
  var left, right: float
  if startIndex < selectionClamped.last and startIndex + part.text.len > selectionClamped.first and part.text.len > 0:
    left = startOffset + max(0, selectionClamped.first - startIndex).float32 / (part.text.len.float32 - 0) * (endOffset - startOffset)
    right = startOffset + min(part.text.len, selectionClamped.last - startIndex).float32 / (part.text.len.float32 - 0) * (endOffset - startOffset)
  elif part.text.len == 0 and selection.contains((line, startIndex)) and not selection.isEmpty:
    left = startOffset
    right = ceil(startOffset + app.platform.charWidth * 0.5)
  else:
    return

  if left == right:
    return

  panel.children.add(WPanel(
    anchor: (vec2(0, 0), vec2(0, 0)),
    left: left,
    right: right,
    bottom: totalLineHeight,
    fillBackground: true,
    backgroundColor: color,
    lastHierarchyChange: panel.lastHierarchyChange
  ))

proc renderTextHighlight(panel: WPanel, app: Editor, startOffset: float, endOffset: float, line: int, startIndex: int, selections: openArray[Selection], selectionClamped: openArray[tuple[first: int, last: int]], part: StyledText, color: Color, totalLineHeight: float) =
  ## Fills selections rect in the given color
  for i in 0..<selections.len:
    renderTextHighlight(panel, app, startOffset, endOffset, line, startIndex, selections[i], selectionClamped[i], part, color, totalLineHeight)

proc createPartWidget*(text: string, startOffset: float, width: float, height: float, color: Color, frameIndex: int): WText

proc updateBaseIndexAndScrollOffset*(contentPanel: WPanel, previousBaseIndex: var int, scrollOffset: var float, lines: int, totalLineHeight: float, targetLine: Option[int]) =

  if targetLine.getSome(targetLine):
    let targetLineY = (targetLine - previousBaseIndex).float32 * totalLineHeight + scrollOffset

    # let margin = clamp(getOption[float32](self.editor, "text.cursor-margin", 25.0), 0.0, self.lastContentBounds.h * 0.5 - totalLineHeight * 0.5)
    let margin = 0.0
    if targetLineY < margin:
      scrollOffset = margin
      previousBaseIndex = targetLine
    elif targetLineY + totalLineHeight > contentPanel.lastBounds.h - margin:
      scrollOffset = contentPanel.lastBounds.h - margin - totalLineHeight
      previousBaseIndex = targetLine

  previousBaseIndex = previousBaseIndex.clamp(0..lines)

  # Adjust scroll offset and base index so that the first node on screen is the base
  while scrollOffset < 0 and previousBaseIndex + 1 < lines:
    if scrollOffset + totalLineHeight >= contentPanel.lastBounds.h:
      break
    previousBaseIndex += 1
    scrollOffset += totalLineHeight

  # Adjust scroll offset and base index so that the first node on screen is the base
  while scrollOffset > contentPanel.lastBounds.h and previousBaseIndex > 0:
    if scrollOffset - totalLineHeight <= 0:
      break
    previousBaseIndex -= 1
    scrollOffset -= totalLineHeight

proc createLinesInPanel*(app: Editor, contentPanel: WPanel, previousBaseIndex: int, scrollOffset: float, lines: int, frameIndex: int, onlyRenderInBounds: bool,
  renderLine: proc(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool) =

  let totalLineHeight = app.platform.totalLineHeight

  # Render all lines after base index
  for i in previousBaseIndex..<lines:
    let top = (i - previousBaseIndex).float32 * totalLineHeight + scrollOffset

    # Bounds of the previous line part
    if onlyRenderInBounds and top >= contentPanel.lastBounds.h:
      break

    if onlyRenderInBounds and top + totalLineHeight <= 0:
      continue

    var lineWidget = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), left: 0, right: 0, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)

    if not renderLine(lineWidget, i, true, frameIndex):
      break

    contentPanel.children.add lineWidget

  # Render all lines before base index
  for k in 1..previousBaseIndex:
    let i = previousBaseIndex - k

    let top = (i - previousBaseIndex).float32 * totalLineHeight + scrollOffset

    # Bounds of the previous line part
    if onlyRenderInBounds and top >= contentPanel.lastBounds.h:
      continue

    if onlyRenderInBounds and top + totalLineHeight <= 0:
      break

    var lineWidget = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, right: -1, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)

    if not renderLine(lineWidget, i, false, frameIndex):
      break

    contentPanel.children.add lineWidget

proc renderCompletions(self: TextDocumentEditor, app: Editor, contentPanel: WPanel, cursorBounds: Rect, frameIndex: int) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let backgroundColor = app.theme.color("panel.background", rgb(30, 30, 30))
  let selectedBackgroundColor = app.theme.color("list.activeSelectionBackground", rgb(200, 200, 200))
  let nameColor = app.theme.tokenColor(@["entity.name.label", "entity.name"], rgb(255, 255, 255))
  let textColor = app.theme.color("list.inactiveSelectionForeground", rgb(175, 175, 175))
  let scopeColor = app.theme.color("string", rgb(175, 255, 175))

  var panel = WPanel(
    left: cursorBounds.x, top: cursorBounds.yh, right: cursorBounds.x + charWidth * 60.0, bottom: cursorBounds.yh + totalLineHeight * 20.0,
    fillBackground: true, backgroundColor: backgroundColor, lastHierarchyChange: frameIndex, maskContent: true)
  panel.layoutWidget(contentPanel.lastBounds, frameIndex, app.platform.layoutOptions)
  contentPanel.children.add(panel)

  self.lastCompletionsWidget = panel

  updateBaseIndexAndScrollOffset(panel, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  self.lastCompletionWidgets.setLen 0

  proc renderLine(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool =
    # Pixel coordinate of the top left corner of the entire line. Includes line number
    let top = (i - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

    if i == self.selectedCompletion:
      lineWidget.fillBackground = true
      lineWidget.backgroundColor = selectedBackgroundColor

    let completion = self.completions[i]

    let nameWidget = createPartWidget(completion.name, 0, completion.name.len.float * charWidth, totalLineHeight, nameColor, frameIndex)
    lineWidget.children.add(nameWidget)

    var scopeWidget = createPartWidget(completion.scope, -completion.scope.len.float * charWidth, totalLineHeight, completion.scope.len.float * charWidth, scopeColor, frameIndex)
    scopeWidget.anchor.min.x = 1
    scopeWidget.anchor.max.x = 1
    lineWidget.children.add(scopeWidget)

    self.lastCompletionWidgets.add (i, lineWidget)

    return true

  app.createLinesInPanel(panel, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, frameIndex, onlyRenderInBounds=true, renderLine)

method updateWidget*(self: TextDocumentEditor, app: Editor, widget: WPanel, frameIndex: int) =
  let lineHeight = app.platform.lineHeight
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  let sizeToContent = widget.sizeToContent

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

    let workspaceName = self.document.workspace.map(wf => " - " & wf.name).get("")

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPart1Text.text = fmt" {mode} - {self.document.filename} {workspaceName} "
    headerPart2Text.text = fmt" {self.selection} - {self.id} "

    headerPanel.updateLastHierarchyChangeFromChildren frameIndex
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  self.lastContentBounds = contentPanel.lastBounds
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.sizeToContent = sizeToContent
  contentPanel.updateBackgroundColor(
    if self.active: app.theme.color("editor.background", rgb(25, 25, 40)) else: app.theme.color("editor.background", rgb(25, 25, 25)) * 0.75,
    frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty or app.platform.redrawEverything):
    return

  self.resetDirty()

  # either layout or content changed, update the lines
  # let timer = startTimer()
  contentPanel.children.setLen 0

  if not self.disableScrolling:
    updateBaseIndexAndScrollOffset(contentPanel, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, totalLineHeight, int.none)

  var selectionsPerLine = initTable[int, seq[Selection]]()
  for s in self.selections:
    let sn = s.normalized
    for line in sn.first.line..sn.last.line:
      selectionsPerLine.mgetOrPut(line, @[]).add s

  var highlightsPerLine = self.searchResults

  let lineNumbers = self.lineNumbers.get getOption[LineNumbers](app, "editor.text.line-numbers", LineNumbers.Absolute) # """

  let maxLineNumber = case lineNumbers
    of LineNumbers.Absolute: self.previousBaseIndex + ((contentPanel.lastBounds.h - self.scrollOffset) / totalLineHeight).int
    of LineNumbers.Relative: 99
    else: 0
  let maxLineNumberLen = ($maxLineNumber).len + 1
  let cursorLine = self.selection.last.line

  let lineNumberPadding = charWidth
  let lineNumberBounds = if lineNumbers != LineNumbers.None:
    vec2(maxLineNumberLen.float32 * charWidth, 0)
  else:
    vec2()

  self.lastRenderedLines.setLen 0

  let isWide = getOption[bool](app, self.getContextWithMode("editor.text.cursor.wide"))
  let cursorWidth = if isWide: 1.0 else: 0.2

  let selectionColor = app.theme.color("selection.background", rgb(200, 200, 200))
  let highlightColor = app.theme.color(@["editor.rangeHighlightBackground"], rgb(200, 200, 200))
  let cursorColor = app.theme.color(@["editorCursor.foreground", "foreground"], rgba(255, 255, 255, 127)) # """

  var cursorBounds = rect(vec2(), vec2())

  # Update content
  proc renderLine(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool =
    # Pixel coordinate of the top left corner of the entire line. Includes line number
    let top = (i - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

    if sizeToContent:
      lineWidget.sizeToContent = true

    var styledText = self.document.getStyledText(i)

    let selectionsNormalizedOnLine = selectionsPerLine.getOrDefault(i, @[]).map (s) => s.normalized
    let selectionsClampedOnLine = selectionsNormalizedOnLine.map (s) => s.clampToLine(i, styledText.len)
    let highlightsNormalizedOnLine = highlightsPerLine.getOrDefault(i, @[]).map (s) => s.normalized
    let highlightsClampedOnLine = highlightsNormalizedOnLine.map (s) => s.clampToLine(i, styledText.len)

    if lineNumbers != LineNumbers.None and cursorLine == i:
      var partWidget = createPartWidget($i, 0, lineNumberBounds.x, totalLineHeight, textColor, frameIndex)
      lineWidget.children.add partWidget
    else:
      case lineNumbers
      of LineNumbers.Absolute:
        let text = $i
        let x = max(0.0, lineNumberBounds.x - text.len.float * charWidth)
        var partWidget = createPartWidget(text, x, lineNumberBounds.x, totalLineHeight, textColor, frameIndex)
        lineWidget.children.add partWidget
      of LineNumbers.Relative:
        let text = $(i - cursorLine).abs
        let x = max(0.0, lineNumberBounds.x - text.len.float * charWidth)
        var partWidget = createPartWidget(text, x, lineNumberBounds.x, totalLineHeight, textColor, frameIndex)
        lineWidget.children.add partWidget
      else:
        discard

    var startOffset = if lineNumbers == LineNumbers.None: 0.0 else: lineNumberBounds.x + lineNumberPadding
    var startIndex = 0
    for partIndex, part in styledText.parts:
      let width = part.text.len.float * charWidth

      # Draw background if selected
      renderTextHighlight(lineWidget, app, startOffset, startOffset + width, i, startIndex, selectionsNormalizedOnLine, selectionsClampedOnLine, part, selectionColor, totalLineHeight)
      renderTextHighlight(lineWidget, app, startOffset, startOffset + width, i, startIndex, highlightsNormalizedOnLine, highlightsClampedOnLine, part, highlightColor, totalLineHeight)

      # Set last cursor pos if its contained in this part
      for selection in selectionsPerLine.getOrDefault(i, @[]):
        if selection.last.line == i and selection.last.column >= startIndex and selection.last.column <= startIndex + part.text.len:
          let offsetFromPartStart = if part.text.len == 0: 0.0 else: (selection.last.column - startIndex).float32 / (part.text.len.float32) * width
          lineWidget.children.add(WPanel(
            anchor: (vec2(0, 0), vec2(0, 0)),
            left: startOffset + offsetFromPartStart,
            right: startOffset + offsetFromPartStart + cursorWidth * charWidth,
            bottom: totalLineHeight,
            fillBackground: true,
            backgroundColor: cursorColor,
            lastHierarchyChange: frameIndex
          ))
          cursorBounds = rect(startOffset + offsetFromPartStart, top, charWidth * cursorWidth, lineHeight)

      let color = if part.scope.len == 0: textColor else: app.theme.tokenColor(part.scope, rgb(255, 200, 200))
      var partWidget = createPartWidget(part.text, startOffset, width, totalLineHeight, color, frameIndex)

      styledText.parts[partIndex].bounds.x = partWidget.left
      styledText.parts[partIndex].bounds.y = lineWidget.top
      styledText.parts[partIndex].bounds.w = partWidget.right - partWidget.left
      styledText.parts[partIndex].bounds.h = lineWidget.bottom - lineWidget.top

      startOffset += width
      startIndex += part.text.len

      lineWidget.children.add(partWidget)

    self.lastRenderedLines.add styledText

    return true

  let renderOnlyLinesInBounds = not sizeToContent
  app.createLinesInPanel(contentPanel, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, frameIndex, renderOnlyLinesInBounds, renderLine)

  if self.showCompletions:
    self.renderCompletions(app, contentPanel, cursorBounds, frameIndex)

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {contentPanel.children.len} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

when defined(js):
  # Optimized version for javascript backend
  proc createPartWidget*(text: string, startOffset: float, width: float, height: float, color: Color, frameIndex: int): WText =
    new result
    {.emit: [result, ".text = ", text, ".slice(0);"] .} #"""
    {.emit: [result, ".anchor = {Field0: {x: 0, y: 0}, Field1: {x: 0, y: 0}};"] .} #"""
    {.emit: [result, ".left = ", startOffset, ";"] .} #"""
    {.emit: [result, ".right = ", startOffset, " + ", width, ";"] .} #"""
    {.emit: [result, ".bottom = ", height, ";"] .} #"""
    {.emit: [result, ".frameIndex = ", frameIndex, ";"] .} #"""
    {.emit: [result, ".foregroundColor = ", color, ";"] .} #"""
    # """

else:
  proc createPartWidget*(text: string, startOffset: float, width: float, height: float, color: Color, frameIndex: int): WText =
    result = WText(text: text, anchor: (vec2(0, 0), vec2(0, 0)), left: startOffset, right: startOffset + width, bottom: height, foregroundColor: color, lastHierarchyChange: frameIndex)
