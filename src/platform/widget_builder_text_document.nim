import std/[strformat, tables, sugar, sequtils, strutils]
import util, app, document_editor, text/text_editor, custom_logger, widgets, platform, theme, custom_unicode, config_provider
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma
import custom_logger

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_text"

type CursorLocationInfo = tuple[node: UINode, text: string, bounds: Rect]

when defined(js):
  template tokenColor*(theme: Theme, part: StyledText, default: untyped): Color =
    theme.tokenColor(part.scopeC, default)
else:
  template tokenColor*(theme: Theme, part: StyledText, default: untyped): Color =
    theme.tokenColor(part.scope, default)

proc updateBaseIndexAndScrollOffset*(height: float, previousBaseIndex: var int, scrollOffset: var float, lines: int, totalLineHeight: float, targetLine: Option[int])

proc getCursorPos(self: TextDocumentEditor, node: UINode, line: int, startOffset: RuneIndex, pos: Vec2): int =
  var offsetFromLeft = pos.x / self.platform.charWidth
  if self.isThickCursor():
    offsetFromLeft -= 0.0
  else:
    offsetFromLeft += 0.5

  let index = clamp(offsetFromLeft.int, 0, node.textRuneLen)
  let byteIndex = self.document.lines[line].toOpenArray.runeOffset(startOffset + index.RuneCount)
  return byteIndex

proc renderLine*(
  self: TextDocumentEditor, builder: UINodeBuilder, app: App,
  line: StyledLine, lineOriginal: openArray[char],
  lineId: int32, parentId: Id, curs: Option[int], cursorLine: int,
  lineNumber: int, lineNumbers: LineNumbers,
  y: float, sizeToContentX: bool, lineNumberTotalWidth: float, lineNumberWidth: float,
  backgroundColor: Color, textColor: Color): Option[CursorLocationInfo] =

  var flags = &{LayoutVertical, FillX, SizeToContentY}
  var flagsInner = &{LayoutHorizontal, FillX, SizeToContentY}
  if sizeToContentX:
    flags.incl SizeToContentX
    flagsInner.incl SizeToContentX

  # let lineNumbers = self.lineNumbers.get getOption[LineNumbers](app, "editor.text.line-numbers", LineNumbers.Absolute) # """

  builder.panel(flagsInner, y = y, userId = newSecondaryId(parentId, lineId)):
    var start = 0
    var startRune = 0.RuneCount
    var lastPartXW: float32 = 0

    # let lineIdStr = $lineId & ": "
    # builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY}, text = lineIdStr, backgroundColor = backgroundColor, textColor = textColor):
    #   lastPartXW = currentNode.bounds.xw

    block:
      var lineNumberText = ""
      var lineNumberX = 0.float
      if lineNumbers != LineNumbers.None and cursorLine == lineNumber:
        lineNumberText = $lineNumber
      else:
        case lineNumbers
        of LineNumbers.Absolute:
          lineNumberText = $lineNumber
          lineNumberX = max(0.0, lineNumberWidth - lineNumberText.len.float * builder.charWidth)
        of LineNumbers.Relative:
          lineNumberText = $(lineNumber - cursorLine).abs
          lineNumberX = max(0.0, lineNumberWidth - lineNumberText.len.float * builder.charWidth)
        else:
          discard

      if lineNumberText.len > 0:
        builder.panel(&{UINodeFlag.FillBackground, SizeToContentY}, w = lineNumberTotalWidth, backgroundColor = backgroundColor):
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = lineNumberText, x = lineNumberX, textColor = textColor)
        lastPartXW = lineNumberTotalWidth

    for part in line.parts:
      defer:
        start += part.text.len
        startRune += part.text.runeLen

      let startRune = startRune

      var partNode: UINode
      builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY}, text = part.text):
        currentNode.backgroundColor = backgroundColor
        currentNode.textColor = if part.scope.len == 0: textColor else: app.theme.tokenColor(part, textColor)

        partNode = currentNode

        capture line, currentNode, startRune:
          onClickAny btn:
            if btn == Left:
              let offset = self.getCursorPos(currentNode, line.index, startRune.RuneIndex, pos)
              self.selection = (line.index, offset).toSelection
              self.markDirty()
            elif btn == TripleClick:
              self.selection = ((line.index, 0), (line.index, self.document.lineLength(line.index)))
              self.markDirty()

          onDrag Left:
            let offset = self.getCursorPos(currentNode, line.index, startRune.RuneIndex, pos)
            self.selection = (line.index, offset).toSelection
            self.markDirty()

        # cursor
        if curs.getSome(curs):
          let selectionLastRune = lineOriginal.runeIndex(curs)

          if selectionLastRune >= startRune.RuneIndex and selectionLastRune < startRune.RuneIndex + part.text.runeLen:
            let cursorX = builder.textWidth(int(selectionLastRune - startRune)).round
            result = some (currentNode, $part.text[selectionLastRune - startRune], rect(cursorX, 0, builder.charWidth, builder.textHeight))

      lastPartXW = partNode.bounds.xw

    # cursor after latest char
    if curs.getSome(curs) and curs == lineOriginal.len:
      result = some (currentNode, "", rect(lastPartXW, 0, builder.charWidth, builder.textHeight))

    # Fill rest of line with background
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = backgroundColor):
      capture line, currentNode:
        onClickAny btn:
          if btn == Left:
            self.selection = (line.index, self.document.lineLength(line.index)).toSelection
            self.markDirty()
          elif btn == TripleClick:
            self.selection = ((line.index, 0), (line.index, self.document.lineLength(line.index)))
            self.markDirty()

        onDrag Left:
          self.selection = (line.index, self.document.lineLength(line.index)).toSelection
          self.markDirty()

proc createHeader(self: TextDocumentEditor, builder: UINodeBuilder, app: App, headerColor: Color, textColor: Color): UINode =
  if self.renderHeader:
    builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal}, backgroundColor = headerColor):
      result = currentNode

      let workspaceName = self.document.workspace.map(wf => " - " & wf.name).get("")

      proc cursorString(cursor: Cursor): string = $cursor.line & ":" & $cursor.column & ":" & $self.document.lines[cursor.line].toOpenArray.runeIndex(cursor.column)

      let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = fmt" {mode} - {self.document.filename} {workspaceName} ")
      builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = fmt" {(cursorString(self.selection.first))}-{(cursorString(self.selection.last))} - {self.id} ")

  else:
    builder.panel(&{FillX}):
      result = currentNode

proc createLines(self: TextDocumentEditor, builder: UINodeBuilder, app: App, backgroundColor: Color, textColor: Color, sizeToContentX: bool, sizeToContentY: bool): Option[CursorLocationInfo] =
  let cursor = self.selection.last

  var flags = 0.UINodeFlags
  if sizeToContentX:
    flags.incl SizeToContentX
  else:
    flags.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
  else:
    flags.incl FillY

  let lineNumbers = self.lineNumbers.get getOption[LineNumbers](app, "editor.text.line-numbers", LineNumbers.Absolute)
  let charWidth = builder.charWidth

  # builder.panel(&{FillX, LayoutVertical}, flags += (if sizeToContentY: &{SizeToContentY} else: &{FillY})):
  builder.panel(flags + MaskContent + OverlappingChildren):
    let linesPanel = currentNode

    builder.panel(flags):
      onScroll:
        let scrollAmount = delta.y * app.asConfigProvider.getValue("text.scroll-speed", 40.0)
        self.scrollOffset += scrollAmount
        self.markDirty()

      let height = currentNode.bounds.h
      var y = self.scrollOffset

      # line numbers
      let maxLineNumber = case lineNumbers
        of LineNumbers.Absolute: self.previousBaseIndex + ((height - self.scrollOffset) / builder.textHeight).int
        of LineNumbers.Relative: 99
        else: 0
      let maxLineNumberLen = ($maxLineNumber).len + 1
      let cursorLine = self.selection.last.line

      let lineNumberPadding = charWidth
      let lineNumberBounds = if lineNumbers != LineNumbers.None:
        vec2(maxLineNumberLen.float32 * charWidth, 0)
      else:
        vec2()

      let lineNumberWidth = if lineNumbers != LineNumbers.None:
        (lineNumberBounds.x + lineNumberPadding).ceil
      else:
        0.0

      for i in self.previousBaseIndex..self.document.lines.high:
        let column = if cursor.line == i: cursor.column.some else: int.none
        let line = self.getStyledText i

        if self.renderLine(builder, app, line, self.document.lines[i], self.document.lineIds[i], self.userId, column, cursorLine, i, lineNumbers, y, sizeToContentX, lineNumberWidth, lineNumberBounds.x, backgroundColor, textColor).getSome(cl):
          result = cl.some

        y = builder.currentChild.yh
        if not sizeToContentY and builder.currentChild.bounds.y > height:
          break

      if y < height:
        builder.panel(&{FillX, FillY, FillBackground}, y = y, backgroundColor = backgroundColor)

      y = self.scrollOffset

      for i in countdown(self.previousBaseIndex - 1, 0):
        let column = if cursor.line == i: cursor.column.some else: int.none
        let line = self.getStyledText i

        if self.renderLine(builder, app, line, self.document.lines[i], self.document.lineIds[i], self.userId, column, cursorLine, i, lineNumbers, y, sizeToContentX, lineNumberWidth, lineNumberBounds.x, backgroundColor, textColor).getSome(cl):
          result = cl.some

        builder.currentChild.rawY = builder.currentChild.y - builder.currentChild.h

        y = builder.currentChild.y
        if not sizeToContentY and builder.currentChild.bounds.yh < 0:
          break

      if not sizeToContentY and y > 0:
        builder.panel(&{FillX, FillBackground}, h = y, backgroundColor = backgroundColor)

    block: #cursor
      let cursorLocation = result
      let (x, y, w, h, text) = if cursorLocation.isSome:
        var bounds = cursorLocation.get.bounds.transformRect(cursorLocation.get.node, linesPanel) - vec2(app.platform.charGap, 0)
        bounds.w += app.platform.charGap
        if not self.cursorVisible:
          bounds.w = 0
        (bounds.x.some, bounds.y.some, bounds.w, bounds.h, cursorLocation.get.text)
      else:
        (float32.none, float32.none, 0, 0, "")

      builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, MaskContent}, x = x, y = y, w = w, h = h, backgroundColor = color(0.7, 0.7, 1), userId = self.cursorsId.newPrimaryId):
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = app.platform.charGap, y = 0, text = text, textColor = color(0.4, 0.2, 2))

    defer:
      self.lastContentBounds = currentNode.bounds

method createUI*(self: TextDocumentEditor, builder: UINodeBuilder, app: App) =
  let dirty = self.dirty
  self.resetDirty()

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: app.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: app.theme.color("editor.background", color(25/255, 25/255, 25/255)) * 0.85
  backgroundColor.a = 1

  var headerColor = if self.active: app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1

  var flags = &{UINodeFlag.MaskContent, OverlappingChildren}
  var flagsInner = &{LayoutVertical}

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags
  if sizeToContentX:
    flags.incl SizeToContentX
    flagsInner.incl SizeToContentX
  else:
    flags.incl FillX
    flagsInner.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
    flagsInner.incl SizeToContentY
  else:
    flags.incl FillY
    flagsInner.incl FillY

  builder.panel(flags, userId = self.userId.newPrimaryId):
    if dirty or app.platform.redrawEverything or not builder.retain():
      # echo "render text editor ", self.document.filename

      var cursorLocation = CursorLocationInfo.none
      var header: UINode

      builder.panel(flagsInner):
        header = self.createHeader(builder, app, backgroundColor, textColor)
        cursorLocation = self.createLines(builder, app, backgroundColor, textColor, sizeToContentX, sizeToContentY)

    if not self.disableScrolling and not sizeToContentY:
      updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, builder.textHeight, int.none)

let completionListWidgetId* = newId()
let completionDocsWidgetId* = newId()

proc shouldIgnoreAsContextLine(self: TextDocument, line: int): bool =
  let indent = self.getIndentLevelForLine(line)
  return line > 0 and self.languageConfig.isSome and self.languageConfig.get.ignoreContextLinePrefix.isSome and
        self.lineStartsWith(line, self.languageConfig.get.ignoreContextLinePrefix.get, true) and self.getIndentLevelForLine(line - 1) == indent

proc getPreviousLineWithIndent(self: TextDocument, line: int, indent: int): int =
  result = line
  while true:
    if result notin 0..self.lines.high:
      return line

    if self.lines[result] == "":
      dec result
      continue

    let i = self.getIndentLevelForLine(result)

    if self.shouldIgnoreAsContextLine(result):
      dec result
      continue

    if i == indent or result <= 0:
      return

    dec result


proc clampToLine(document: TextDocument, selection: Selection, line: var StyledLine): tuple[first: RuneIndex, last: RuneIndex] =
  result.first = if selection.first.line < line.index: 0.RuneIndex elif selection.first.line == line.index: document.lines[line.index].runeIndex(selection.first.column) else: line.runeLen.RuneIndex
  result.last = if selection.last.line < line.index: 0.RuneIndex elif selection.last.line == line.index: document.lines[line.index].runeIndex(selection.last.column) else: line.runeLen.RuneIndex

proc renderTextHighlight(panel: WPanel, app: App, startOffset: float, endOffset: float, line: int, startRuneIndex: RuneIndex,
    selection: tuple[first: RuneIndex, last: RuneIndex], selectionClamped: tuple[first: RuneIndex, last: RuneIndex], part: StyledText, color: Color, totalLineHeight: float) =
  let startOffset = startOffset.floor
  let endOffset = endOffset.ceil

  let runeCount = part.text.runeLen

  ## Fills a selection rect in the given color
  var left, right: float
  if startRuneIndex < selectionClamped.last and startRuneIndex + runeCount > selectionClamped.first and runeCount > 0.RuneCount:
    left = startOffset + max(0.RuneCount, selectionClamped.first - startRuneIndex).float32 / (runeCount.float32 - 0) * (endOffset - startOffset)
    right = startOffset + min(runeCount, selectionClamped.last - startRuneIndex).float32 / (runeCount.float32 - 0) * (endOffset - startOffset)
  elif runeCount == 0.RuneCount and startRuneIndex >= selection.first and startRuneIndex <= selection.last and selection.first != selection.last:
    left = startOffset
    right = ceil(startOffset + app.platform.charWidth * 0.5)
  else:
    return

  left = left.floor
  right = right.ceil

  if left == right:
    return

  panel.add(WPanel(
    anchor: (vec2(0, 0), vec2(0, 0)),
    left: left,
    right: right,
    bottom: totalLineHeight,
    flags: &{FillBackground, AllowAlpha},
    backgroundColor: color,
    lastHierarchyChange: panel.lastHierarchyChange
  ))

proc renderTextHighlight(panel: WPanel, app: App, startOffset: float, endOffset: float, line: int, startRuneIndex: RuneIndex,
    selections: openArray[tuple[first: RuneIndex, last: RuneIndex]], selectionClamped: openArray[tuple[first: RuneIndex, last: RuneIndex]], part: StyledText, color: Color, totalLineHeight: float) =
  ## Fills selections rect in the given color
  for i in 0..<selections.len:
    renderTextHighlight(panel, app, startOffset, endOffset, line, startRuneIndex, selections[i], selectionClamped[i], part, color, totalLineHeight)

proc createPartWidget*(text: string, startOffset: float, width: float, height: float, color: Color, frameIndex: int): WText

proc updateBaseIndexAndScrollOffset*(height: float, previousBaseIndex: var int, scrollOffset: var float, lines: int, totalLineHeight: float, targetLine: Option[int]) =

  if targetLine.getSome(targetLine):
    let targetLineY = (targetLine - previousBaseIndex).float32 * totalLineHeight + scrollOffset

    # let margin = clamp(getOption[float32](self.editor, "text.cursor-margin", 25.0), 0.0, self.lastContentBounds.h * 0.5 - totalLineHeight * 0.5)
    let margin = 0.0
    if targetLineY < margin:
      scrollOffset = margin
      previousBaseIndex = targetLine
    elif targetLineY + totalLineHeight > height - margin:
      scrollOffset = height - margin - totalLineHeight
      previousBaseIndex = targetLine

  previousBaseIndex = previousBaseIndex.clamp(0..lines)

  # Adjust scroll offset and base index so that the first node on screen is the base
  while scrollOffset < 0 and previousBaseIndex + 1 < lines:
    if scrollOffset + totalLineHeight >= height:
      break
    previousBaseIndex += 1
    scrollOffset += totalLineHeight

  # Adjust scroll offset and base index so that the first node on screen is the base
  while scrollOffset > height and previousBaseIndex > 0:
    if scrollOffset - totalLineHeight <= 0:
      break
    previousBaseIndex -= 1
    scrollOffset -= totalLineHeight

proc createLinesInPanel*(app: App, contentPanel: WPanel, previousBaseIndex: int, scrollOffset: float, lines: int, frameIndex: int, onlyRenderInBounds: bool,
  renderLine: proc(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool) =

  let totalLineHeight = app.platform.totalLineHeight

  var top = (scrollOffset / totalLineHeight).floor * totalLineHeight

  # Render all lines after base index
  for i in previousBaseIndex..<lines:
    # Bounds of the previous line part
    if onlyRenderInBounds and top >= contentPanel.lastBounds.h:
      break

    if onlyRenderInBounds and top + totalLineHeight <= 0:
      continue

    var lineWidget = WPanel(anchor: (vec2(0, 0), vec2(0, 0)), left: 0, right: contentPanel.lastBounds.w, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)
    lineWidget.layoutWidget(contentPanel.lastBounds, frameIndex, app.platform.layoutOptions)

    if not renderLine(lineWidget, i, true, frameIndex):
      break

    contentPanel.add lineWidget
    top = lineWidget.bottom

  top = (scrollOffset / totalLineHeight).floor * totalLineHeight

  # Render all lines before base index
  for k in 1..previousBaseIndex:
    let i = previousBaseIndex - k

    # Bounds of the previous line part
    if onlyRenderInBounds and top >= contentPanel.lastBounds.h:
      continue

    if onlyRenderInBounds and top + totalLineHeight <= 0:
      break

    var lineWidget = WPanel(anchor: (vec2(0, 0), vec2(0, 0)), left: 0, right: contentPanel.lastBounds.w, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)
    lineWidget.layoutWidget(contentPanel.lastBounds, frameIndex, app.platform.layoutOptions)

    if not renderLine(lineWidget, i, false, frameIndex):
      break

    let height = lineWidget.height
    lineWidget.top = top - height
    lineWidget.bottom = top

    top = lineWidget.top

    contentPanel.add lineWidget

proc renderCompletions(self: TextDocumentEditor, app: App, completionsPanel: WPanel, cursorBounds: Rect, frameIndex: int, renderAboveCursor: bool) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let backgroundColor = app.theme.color("panel.background", color(30/255, 30/255, 30/255))
  let selectedBackgroundColor = app.theme.color("list.activeSelectionBackground", color(200/255, 200/255, 200/255))
  let docsColor = app.theme.color("editor.foreground", color(1, 1, 1))
  let nameColor = app.theme.tokenColor(@["entity.name.label", "entity.name"], color(1, 1, 1))
  let scopeColor = app.theme.color("string", color(175/255, 1, 175/255))

  const numLinesToShow = 20
  let (top, bottom) = if renderAboveCursor:
    (cursorBounds.y.float - totalLineHeight * (numLinesToShow + 1), cursorBounds.y.float)
  else:
    (cursorBounds.yh.float, cursorBounds.yh.float + totalLineHeight * numLinesToShow)

  completionsPanel.updateLastHierarchyChange frameIndex
  let panel: WPanel = completionsPanel[self.completionWidgetId, WPanel]
  panel.anchor = (vec2(0, 0), vec2(1, 1))

  const listWidth = 120.0
  const docsWidth = 50.0
  let totalWidth = charWidth * listWidth + charWidth * docsWidth
  var clampedX = cursorBounds.x
  if clampedX + totalWidth > completionsPanel.lastBounds.w:
    clampedX = max(completionsPanel.lastBounds.w - totalWidth, 0)

  let list: WPanel = panel[completionListWidgetId, WPanel]
  list.left = clampedX
  list.right = clampedX + charWidth * listWidth
  list.top = top
  list.bottom = bottom
  list.fillBackground = true
  list.backgroundColor = backgroundColor
  list.lastHierarchyChange = frameIndex
  list.maskContent = true
  list.children.setLen 0

  let docs: WText = panel[completionDocsWidgetId, WText]
  docs.left = clampedX + charWidth * listWidth
  docs.right = docs.left + charWidth * docsWidth
  docs.top = top
  docs.bottom = bottom
  docs.fillBackground = true
  docs.backgroundColor = backgroundColor
  docs.foregroundColor = docsColor
  docs.lastHierarchyChange = frameIndex
  docs.wrap = true

  panel.layoutWidget(completionsPanel.lastBounds, frameIndex, app.platform.layoutOptions)
  list.layoutWidget(panel.lastBounds, frameIndex, app.platform.layoutOptions)
  docs.layoutWidget(panel.lastBounds, frameIndex, app.platform.layoutOptions)

  self.lastCompletionsWidget = list

  updateBaseIndexAndScrollOffset(list.lastBounds.h, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  self.lastCompletionWidgets.setLen 0

  proc renderLine(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool =
    let completion = self.completions[i]

    if i == self.selectedCompletion:
      lineWidget.fillBackground = true
      lineWidget.backgroundColor = selectedBackgroundColor
      docs.text = completion.doc
      docs.updateLastHierarchyChangeFromChildren()

    let nameWidget = createPartWidget(completion.name, 0, completion.name.len.float * charWidth, totalLineHeight, nameColor, frameIndex)
    lineWidget.add(nameWidget)

    let scopeText = completion.typ & " : " & completion.scope
    var scopeWidget = createPartWidget(scopeText, -scopeText.len.float * charWidth, totalLineHeight, scopeText.len.float * charWidth, scopeColor, frameIndex)
    scopeWidget.anchor.min.x = 1
    scopeWidget.anchor.max.x = 1
    lineWidget.add(scopeWidget)

    self.lastCompletionWidgets.add (i, lineWidget)

    return true

  app.createLinesInPanel(list, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, frameIndex, onlyRenderInBounds=true, renderLine)

  panel.updateLastHierarchyChange list.lastHierarchyChange
  panel.updateLastHierarchyChange docs.lastHierarchyChange
  completionsPanel.updateLastHierarchyChange panel.lastHierarchyChange

method updateWidget*(self: TextDocumentEditor, app: App, widget: WPanel, completionsPanel: WPanel, frameIndex: int) =
  let lineHeight = app.platform.lineHeight
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

  let sizeToContent = widget.sizeToContent

  var headerPanel: WPanel
  var headerPart1Text: WText
  var headerPart2Text: WText
  var contentPanel: WPanel
  if widget.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    widget.add(headerPanel)

    headerPart1Text = WText(text: "", flags: &{SizeToContent}, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.add(headerPart1Text)

    headerPart2Text = WText(text: "", flags: &{SizeToContent}, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.add(headerPart2Text)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
  else:
    headerPanel = widget[0].WPanel
    headerPart1Text = headerPanel[0].WText
    headerPart2Text = headerPanel[1].WText
    contentPanel = widget[1].WPanel

  # Update header
  if self.renderHeader:
    headerPanel.bottom = totalLineHeight
    contentPanel.top = totalLineHeight

    let color = if self.active: app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
    else: app.theme.color("tab.inactiveBackground", color(45/255/255/255, 45/255/255, 45/255))
    headerPanel.updateBackgroundColor(color, frameIndex)

    let workspaceName = self.document.workspace.map(wf => " - " & wf.name).get("")

    proc cursorString(cursor: Cursor): string = $cursor.line & ":" & $cursor.column & ":" & $self.document.lines[cursor.line].toOpenArray.runeIndex(cursor.column)

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPart1Text.text = fmt" {mode} - {self.document.filename} {workspaceName} "
    headerPart2Text.text = fmt" {(cursorString(self.selection.first))}-{(cursorString(self.selection.last))} - {self.id} "

    if self.dirty:
      headerPanel.invalidateHierarchy frameIndex
    else:
      headerPanel.updateLastHierarchyChangeFromChildren frameIndex

  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  self.lastContentBounds = contentPanel.lastBounds
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.sizeToContent = sizeToContent
  contentPanel.updateBackgroundColor(
    if self.active: app.theme.color("editor.background", color(25/255/255/255, 25/255/255, 40/255)) else: app.theme.color("editor.background", color(25/255, 25/255, 25/255)) * 0.85,
    frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty or app.platform.redrawEverything):
    return

  self.resetDirty()

  # either layout or content changed, update the lines
  # let timer = startTimer()
  contentPanel.setLen 0

  if not sizeToContent:
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)

  if not self.disableScrolling:
    updateBaseIndexAndScrollOffset(contentPanel.lastBounds.h, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, totalLineHeight, int.none)

  var selectionsPerLine = initTable[int, seq[Selection]]()
  for s in self.selections:
    let sn = s.normalized
    for line in sn.first.line..sn.last.line:
      selectionsPerLine.mgetOrPut(line, @[]).add s

  var highlightsPerLine = self.searchResults

  let lineNumbers = self.lineNumbers.get getOption[LineNumbers](app, "editor.text.line-numbers", LineNumbers.Absolute) # """

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let wrapLineEndChar = getOption[string](app, "editor.text.wrap-line-end-char", "⤶")
  let wrapLines = getOption[bool](app, "editor.text.wrap-lines", true)
  let showContextLines = getOption[bool](app, "editor.text.context-lines", true)

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

  let lineNumberTotalWidth = if lineNumbers != LineNumbers.None:
    (lineNumberBounds.x + lineNumberPadding).ceil
  else:
    0.0

  self.lastTextAreaBounds = self.lastContentBounds
  self.lastTextAreaBounds.x += lineNumberTotalWidth
  self.lastTextAreaBounds.w -= lineNumberTotalWidth

  self.lastRenderedLines.setLen 0

  let isWide = self.isThickCursor()
  let cursorWidth = if isWide: 1.0 else: 0.2

  let selectionColor = app.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let highlightColor = app.theme.color(@["editor.findMatchBackground", "editor.rangeHighlightBackground"], color(200/255, 200/255, 200/255))
  let cursorForegroundColor = app.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let contextBackgroundColor = app.theme.color(@["breadcrumbPicker.background", "background"], color(50/255, 70/255, 70/255))
  let wrapLineEndColor = app.theme.tokenColor(@["comment"], color(100/255, 100/255, 100/255))

  var cursorBounds = rect(vec2(), vec2())

  # Update content
  proc renderLine(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool =
    var i = i

    # Pixel coordinate of the top left corner of the entire line. Includes line number
    let top = lineWidget.top

    let indexFromTop = if down:
      (top / totalLineHeight).ceil.int
    else:
      (top / totalLineHeight - 1).ceil.int

    let indentLevel = self.document.getIndentLevelForClosestLine(i)

    var showingContext = false
    var wrapLine = wrapLines
    if showContextLines and (indexFromTop < indentLevel or (indexFromTop == indentLevel and self.document.shouldIgnoreAsContextLine(i))):
      i = self.document.getPreviousLineWithIndent(i, indexFromTop)
      showingContext = true
      wrapLine = false
      lineWidget.backgroundColor = contextBackgroundColor
      lineWidget.fillBackground = true

    if sizeToContent:
      lineWidget.sizeToContent = true

    var styledText = self.getStyledText(i)

    let selectionsNormalizedOnLine = selectionsPerLine.getOrDefault(i, @[]).map proc(s: auto): auto =
      let s = s.normalized
      return (self.document.lines[s.first.line].toOpenArray.runeIndex(s.first.column), styledText.runeIndex(s.last.column))
    let selectionsClampedOnLine = selectionsPerLine.getOrDefault(i, @[]).map (s) => self.document.clampToLine(s.normalized, styledText)

    let highlightsNormalizedOnLine = highlightsPerLine.getOrDefault(i, @[]).map proc(s: auto): auto =
      let s = s.normalized
      return (self.document.lines[s.first.line].toOpenArray.runeIndex(s.first.column), styledText.runeIndex(s.last.column))
    let highlightsClampedOnLine = highlightsPerLine.getOrDefault(i, @[]).map (s) => self.document.clampToLine(s.normalized, styledText)

    let lineNumber = i

    if lineNumbers != LineNumbers.None and cursorLine == lineNumber:
      var partWidget = createPartWidget($lineNumber, 0, lineNumberBounds.x, totalLineHeight, textColor, frameIndex)
      lineWidget.add partWidget
    else:
      case lineNumbers
      of LineNumbers.Absolute:
        let text = $lineNumber
        let x = max(0.0, lineNumberBounds.x - text.len.float * charWidth)
        var partWidget = createPartWidget(text, x, lineNumberBounds.x, totalLineHeight, textColor, frameIndex)
        lineWidget.add partWidget
      of LineNumbers.Relative:
        let text = $(lineNumber - cursorLine).abs
        let x = max(0.0, lineNumberBounds.x - text.len.float * charWidth)
        var partWidget = createPartWidget(text, x, lineNumberBounds.x, totalLineHeight, textColor, frameIndex)
        lineWidget.add partWidget
      else:
        discard

    var containsCursor = false
    var subLineWidget = lineWidget

    var startOffset = lineNumberTotalWidth
    var startRuneIndex = 0.RuneIndex
    var subLineYOffset = 0.0
    var subLineTop = lineWidget.top
    for partIndex, part in styledText.parts:
      let width = (part.text.runeLen.float * charWidth).ceil

      if wrapLine:
        var wrapWidth = width
        for partIndex2 in partIndex..<styledText.parts.high:
          if styledText.parts[partIndex2].joinNext:
            let nextWidth = (styledText.parts[partIndex2 + 1].text.runeLen.float * charWidth).ceil
            if lineNumberTotalWidth + wrapWidth + nextWidth + charWidth <= lineWidget.lastBounds.w:
              wrapWidth += nextWidth
              continue
          break

        if startOffset + wrapWidth + charWidth >= lineWidget.lastBounds.w:
          var partWidget = createPartWidget(wrapLineEndChar, startOffset, wrapLineEndChar.runeLen.float * charWidth, totalLineHeight, wrapLineEndColor, frameIndex)
          subLineWidget.add partWidget

          subLineYOffset += totalLineHeight
          subLineWidget = WPanel(anchor: (vec2(0, 0), vec2(0, 0)), left: 0, right: contentPanel.lastBounds.w, top: subLineYOffset, bottom: subLineYOffset + totalLineHeight, lastHierarchyChange: frameIndex)
          lineWidget.add subLineWidget
          startOffset = lineNumberTotalWidth
          lineWidget.bottom += totalLineHeight
          subLineTop += totalLineHeight

      # Draw background if selected
      renderTextHighlight(subLineWidget, app, startOffset, startOffset + width, i, startRuneIndex, selectionsNormalizedOnLine, selectionsClampedOnLine, part, selectionColor, totalLineHeight)
      renderTextHighlight(subLineWidget, app, startOffset, startOffset + width, i, startRuneIndex, highlightsNormalizedOnLine, highlightsClampedOnLine, part, highlightColor, totalLineHeight)

      let color = if part.scope.len == 0: textColor else: app.theme.tokenColor(part.scope, color(255/255, 200/255, 200/255))
      var partWidget = createPartWidget(part.text, startOffset, width, totalLineHeight, color, frameIndex)
      if part.opacity.getSome(opacity):
        partWidget.allowAlpha = true
        partWidget.foregroundColor.a = opacity

      styledText.parts[partIndex].bounds.x = partWidget.left
      styledText.parts[partIndex].bounds.y = subLineTop
      styledText.parts[partIndex].bounds.w = partWidget.right - partWidget.left
      styledText.parts[partIndex].bounds.h = subLineWidget.height

      subLineWidget.add(partWidget)

      # Set last cursor pos if its contained in this part
      for selection in selectionsPerLine.getOrDefault(i, @[]):
        let selectionLastRune = self.document.lines[selection.last.line].toOpenArray.runeIndex(selection.last.column, returnLen=true)
        let indexInPart: RuneIndex = selectionLastRune - startRuneIndex.RuneCount
        if selection.last.line == i and indexInPart >= 0.RuneIndex and indexInPart <= part.text.runeLen:
          let characterUnderCursor: Rune = if indexInPart < part.text.runeLen: part.text[indexInPart] else: ' '.Rune
          let offsetFromPartStart = if part.text.len == 0: 0.0 else: indexInPart.float32 / part.text.runeLen.float32 * width
          var w = WText(
            anchor: (vec2(0, 0), vec2(0, 0)),
            left: startOffset + offsetFromPartStart,
            right: startOffset + offsetFromPartStart + cursorWidth * charWidth,
            bottom: totalLineHeight,
            backgroundColor: cursorForegroundColor,
            foregroundColor: cursorBackgroundColor,
            lastHierarchyChange: frameIndex,
            text: if self.cursorVisible and isWide: $characterUnderCursor else: ""
          )

          w.fillBackground = self.cursorVisible
          subLineWidget.add w

          containsCursor = true
          cursorBounds = rect(startOffset + offsetFromPartStart, top, charWidth * cursorWidth, lineHeight)

      startOffset += width
      startRuneIndex += part.text.runeLen

    self.lastRenderedLines.add styledText

    if not down:
      for partIndex in 0..styledText.parts.high:
        styledText.parts[partIndex].bounds.y -= lineWidget.height

      if containsCursor:
        cursorBounds.y -= lineWidget.height

    return true

  let renderOnlyLinesInBounds = not sizeToContent
  app.createLinesInPanel(contentPanel, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, frameIndex, renderOnlyLinesInBounds, renderLine)

  if self.showCompletions and self.active:
    let bounds = cursorBounds + (contentPanel.lastBounds.xy - completionsPanel.lastBounds.xy)
    let renderAbove = bounds.y > completionsPanel.lastBounds.h / 2
    self.renderCompletions(app, completionsPanel, bounds, frameIndex, renderAbove)
  else:
    completionsPanel.delete self.completionWidgetId
    completionsPanel.updateLastHierarchyChange frameIndex

  contentPanel.updateLastHierarchyChange frameIndex
  widget.updateLastHierarchyChange frameIndex

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {contentPanel.len} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

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
