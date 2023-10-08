import std/[strformat, tables, sugar, sequtils, strutils, algorithm, math]
import util, app, document_editor, text/text_editor, custom_logger, widget_builders_base, platform, theme, custom_unicode, config_provider, widget_library
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_text"

type CursorLocationInfo* = tuple[node: UINode, text: string, bounds: Rect, original: Cursor]

when defined(js):
  template tokenColor*(theme: Theme, part: StyledText, default: untyped): Color =
    theme.tokenColor(part.scopeC, default)
else:
  template tokenColor*(theme: Theme, part: StyledText, default: untyped): Color =
    theme.tokenColor(part.scope, default)

proc shouldIgnoreAsContextLine(self: TextDocument, line: int): bool
proc clampToLine(document: TextDocument, selection: Selection, line: StyledLine): tuple[first: RuneIndex, last: RuneIndex]

proc getCursorPos(self: TextDocumentEditor, textRuneLen: int, line: int, startOffset: RuneIndex, pos: Vec2): int =
  var offsetFromLeft = pos.x / self.platform.charWidth
  if self.isThickCursor():
    offsetFromLeft -= 0.0
  else:
    offsetFromLeft += 0.5

  let index = clamp(offsetFromLeft.int, 0, textRuneLen)
  let byteIndex = self.document.lines[line].toOpenArray.runeOffset(startOffset + index.RuneCount)
  return byteIndex

proc renderLine*(
  self: TextDocumentEditor, builder: UINodeBuilder, theme: Theme,
  line: StyledLine, lineOriginal: openArray[char],
  lineId: int32, parentId: Id, cursorLine: int,
  lineNumber: int, lineNumbers: LineNumbers,
  y: float, sizeToContentX: bool, lineNumberTotalWidth: float, lineNumberWidth: float, pivot: Vec2,
  backgroundColor: Color, textColor: Color,
  backgroundColors: openArray[tuple[first: RuneIndex, last: RuneIndex, color: Color]], cursors: openArray[int],
  wrapLine: bool, wrapLineEndChar: string, wrapLineEndColor: Color): seq[CursorLocationInfo] =

  var flagsInner = &{FillX, SizeToContentY}
  if sizeToContentX:
    flagsInner.incl SizeToContentX

  # line numbers
  var lineNumberText = ""
  var lineNumberX = 0.float
  if lineNumbers != LineNumbers.None and cursorLine == lineNumber:
    lineNumberText = $lineNumber
  elif lineNumbers == LineNumbers.Absolute:
    lineNumberText = $lineNumber
    lineNumberX = max(0.0, lineNumberWidth - lineNumberText.len.float * builder.charWidth)
  elif lineNumbers == LineNumbers.Relative:
    lineNumberText = $(lineNumber - cursorLine).abs
    lineNumberX = max(0.0, lineNumberWidth - lineNumberText.len.float * builder.charWidth)

  builder.panel(flagsInner + LayoutVertical, y = y, pivot = pivot, userId = newSecondaryId(parentId, lineId)):
    let lineWidth = currentNode.bounds.w

    var subLine: UINode = nil

    var start = 0
    var startRune = 0.RuneCount
    var lastPartXW: float32 = 0
    var partIndex = 0
    var subLineIndex = 0
    var subLinePartIndex = 0
    while partIndex < line.parts.len:

      builder.panel(flagsInner + LayoutHorizontal):
        subLine = currentNode

        if lineNumberText.len > 0:
          builder.panel(&{UINodeFlag.FillBackground, FillY}, w = lineNumberTotalWidth, backgroundColor = backgroundColor):
            if subLineIndex == 0:
              builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = lineNumberText, x = lineNumberX, textColor = textColor)
          lastPartXW = lineNumberTotalWidth

        while partIndex < line.parts.len:
          template part: StyledText = line.parts[partIndex]

          let partRuneLen = part.text.runeLen
          let width = (partRuneLen.float * builder.charWidth).ceil

          if wrapLine and not sizeToContentX and subLinePartIndex > 0:
            var wrapWidth = width
            for partIndex2 in partIndex..<line.parts.high:
              if line.parts[partIndex2].joinNext:
                let nextWidth = (line.parts[partIndex2 + 1].text.runeLen.float * builder.charWidth).ceil
                if lineNumberTotalWidth + wrapWidth + nextWidth + builder.charWidth <= lineWidth:
                  wrapWidth += nextWidth
                  continue
              break

            if lastPartXW + wrapWidth + builder.charWidth >= lineWidth:
              builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY}, text = wrapLineEndChar, backgroundColor = backgroundColor, textColor = wrapLineEndColor):
                defer:
                  lastPartXW = currentNode.xw
              subLineIndex += 1
              subLinePartIndex = 0
              break

          let textColor = if part.scope.len == 0: textColor else: theme.tokenColor(part, textColor)

          # Find background color
          var colorIndex = 0
          while colorIndex < backgroundColors.high and (backgroundColors[colorIndex].first == backgroundColors[colorIndex].last or backgroundColors[colorIndex].last <= startRune):
            inc colorIndex

          var backgroundColor = backgroundColor
          var addBackgroundAsChildren = true
          if backgroundColors[colorIndex].last >= startRune.RuneIndex + partRuneLen:
            backgroundColor = backgroundColors[colorIndex].color
            addBackgroundAsChildren = false

          var partFlags = &{UINodeFlag.FillBackground, SizeToContentX, SizeToContentY}

          # if the entire part is the same background color we can just fill the background and render the text on the part itself
          # otherwise we need to render the background as a separate node and render the text on top of it, as children of the main part node,
          # which still has a background color though
          if not addBackgroundAsChildren:
            partFlags.incl DrawText
          else:
            partFlags.incl OverlappingChildren

          let text = if addBackgroundAsChildren: "" else: part.text
          let textRuneLen = part.text.runeLen.int

          var partNode: UINode
          builder.panel(partFlags, text = text, backgroundColor = backgroundColor, textColor = textColor):
            partNode = currentNode

            capture line, partNode, startRune, textRuneLen:
              onClickAny btn:
                if btn == Left:
                  let offset = self.getCursorPos(textRuneLen, line.index, startRune.RuneIndex, pos)
                  self.selection = (line.index, offset).toSelection
                  self.markDirty()
                elif btn == TripleClick:
                  self.selection = ((line.index, 0), (line.index, self.document.lineLength(line.index)))
                  self.markDirty()

              onDrag Left:
                let offset = self.getCursorPos(textRuneLen, line.index, startRune.RuneIndex, pos)
                let currentSelection = self.selection
                self.selection = (currentSelection.first, (line.index, offset))
                self.markDirty()

            if addBackgroundAsChildren:
              # Add separate background colors for selections/highlights
              while colorIndex < backgroundColors.high and backgroundColors[colorIndex].first < startRune.RuneIndex + partRuneLen:
                let x = max(0.0, backgroundColors[colorIndex].first.float - startRune.float) * builder.charWidth
                let xw = min(partRuneLen.float, backgroundColors[colorIndex].last.float - startRune.float) * builder.charWidth
                if backgroundColor != backgroundColors[colorIndex].color:
                  builder.panel(&{UINodeFlag.FillBackground, FillY}, x = x, w = xw - x, backgroundColor = backgroundColors[colorIndex].color)

                inc colorIndex

              # Add text on top of background colors
              builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = part.text, textColor = textColor)

            # cursor
            for curs in cursors:
              let selectionLastRune = lineOriginal.runeIndex(curs)

              if selectionLastRune >= startRune.RuneIndex and selectionLastRune < startRune.RuneIndex + partRuneLen:
                let cursorX = builder.textWidth(int(selectionLastRune - startRune)).round
                result.add (currentNode, $part.text[selectionLastRune - startRune], rect(cursorX, 0, builder.charWidth, builder.textHeight), (line.index, curs))

          lastPartXW = partNode.bounds.xw
          start += part.text.len
          startRune += partRuneLen
          partIndex += 1
          subLinePartIndex += 1

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
              let currentSelection = self.selection
              self.selection = (currentSelection.first, (line.index, self.document.lineLength(line.index)))
              self.markDirty()

    # cursor after latest char
    for curs in cursors:
      if curs == lineOriginal.len:
        result.add (subLine, "", rect(lastPartXW, 0, builder.charWidth, builder.textHeight), (line.index, curs))

proc blendColorRanges(colors: var seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]], ranges: var seq[tuple[first: RuneIndex, last: RuneIndex]], color: Color) =
  for s in ranges.mitems:
    var colorIndex = 0
    for i in 0..colors.high:
      if colors[i].last > s.first:
        colorIndex = i
        break

    while colorIndex <= colors.high and colors[colorIndex].last > s.first and colors[colorIndex].first < s.last and s.first != s.last:
      let lastIndex = colors[colorIndex].last
      colors[colorIndex].last = s.first

      if lastIndex < s.last:
        colors.insert (s.first, lastIndex, colors[colorIndex].color.blendNormal(color)), colorIndex + 1
        s.first = lastIndex
        inc colorIndex
      else:
        colors.insert (s.first, s.last, colors[colorIndex].color.blendNormal(color)), colorIndex + 1
        colors.insert (s.last, lastIndex, colors[colorIndex].color), colorIndex + 2
        break

      inc colorIndex

proc createTextLines(self: TextDocumentEditor, builder: UINodeBuilder, app: App, backgroundColor: Color, textColor: Color, sizeToContentX: bool, sizeToContentY: bool): Option[CursorLocationInfo] =
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

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let wrapLineEndChar = getOption[string](app, "editor.text.wrap-line-end-char", "↲")
  let wrapLines = getOption[bool](app, "editor.text.wrap-lines", true)
  let showContextLines = getOption[bool](app, "editor.text.context-lines", true)

  let selectionColor = app.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let highlightColor = app.theme.color(@["editor.findMatchBackground", "editor.rangeHighlightBackground"], color(200/255, 200/255, 200/255))
  let cursorForegroundColor = app.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let contextBackgroundColor = app.theme.color(@["breadcrumbPicker.background", "background"], color(50/255, 70/255, 70/255))
  let wrapLineEndColor = app.theme.tokenColor(@["comment"], color(100/255, 100/255, 100/255))

  var selectionsPerLine = initTable[int, seq[Selection]]()
  for s in self.selections:
    let sn = s.normalized
    for line in sn.first.line..sn.last.line:
      selectionsPerLine.mgetOrPut(line, @[]).add s

  var highlightsPerLine = self.searchResults

  # builder.panel(&{FillX, LayoutVertical}, flags += (if sizeToContentY: &{SizeToContentY} else: &{FillY})):
  builder.panel(flags + MaskContent + OverlappingChildren):
    let linesPanel = currentNode

    let height = currentNode.bounds.h

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

    var cursors: seq[CursorLocationInfo]
    var contextLines: seq[int]
    var contextLineTarget: int = -1

    proc handleScroll(delta: float) =
      let scrollAmount = delta * app.asConfigProvider.getValue("text.scroll-speed", 40.0)
      self.scrollOffset += scrollAmount
      self.markDirty()

    proc handleLine(i: int, y: float, down: bool) =
      let styledLine = self.getStyledText i
      let totalLineHeight = builder.textHeight

      self.lastRenderedLines.add styledLine

      var indexFromTop = if down:
        (y / totalLineHeight + 0.5).ceil.int
      else:
        (y / totalLineHeight - 0.5).ceil.int

      indexFromTop -= 1

      let indentLevel = self.document.getIndentLevelForClosestLine(i)

      var wrapLine = wrapLines
      var i = i
      var backgroundColor = backgroundColor
      if showContextLines and (indexFromTop <= indentLevel and not self.document.shouldIgnoreAsContextLine(i)):
        contextLineTarget = max(contextLineTarget, i)

      # selections and highlights
      var selectionsClampedOnLine = selectionsPerLine.getOrDefault(i, @[]).map (s) => self.document.clampToLine(s.normalized, styledLine)
      var highlightsClampedOnLine = highlightsPerLine.getOrDefault(i, @[]).map (s) => self.document.clampToLine(s.normalized, styledLine)

      selectionsClampedOnLine.sort((a, b) => cmp(a.first, b.first), Ascending)
      highlightsClampedOnLine.sort((a, b) => cmp(a.first, b.first), Ascending)

      var colors: seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]] = @[(0.RuneIndex, self.document.lines[i].runeLen.RuneIndex, backgroundColor.withAlpha(1))]
      blendColorRanges(colors, highlightsClampedOnLine, highlightColor)
      blendColorRanges(colors, selectionsClampedOnLine, selectionColor)

      var cursorsPerLine: seq[int]
      for s in self.selections:
        if s.last.line == i:
          cursorsPerLine.add s.last.column

      let pivot = if down:
        vec2(0, 0)
      else:
        vec2(0, 1)

      cursors.add self.renderLine(builder, app.theme, styledLine, self.document.lines[i], self.document.lineIds[i],
        self.userId, cursorLine, i, lineNumbers, y, sizeToContentX, lineNumberWidth, lineNumberBounds.x, pivot,
        backgroundColor, textColor,
        colors, cursorsPerLine, wrapLine, wrapLineEndChar, wrapLineEndColor,
        )

    self.lastRenderedLines.setLen 0
    builder.createLines(self.previousBaseIndex, self.scrollOffset, self.document.lines.high, sizeToContentX, sizeToContentY, backgroundColor, handleScroll, handleLine)

    # context lines
    if contextLineTarget >= 0:
      var indentLevel = self.document.getIndentLevelForClosestLine(contextLineTarget)
      while indentLevel > 0 and contextLineTarget > 0:
        contextLineTarget -= 1
        let newIndentLevel = self.document.getIndentLevelForClosestLine(contextLineTarget)
        if newIndentLevel < indentLevel and not self.document.shouldIgnoreAsContextLine(contextLineTarget):
          contextLines.add contextLineTarget
          indentLevel = newIndentLevel

      contextLines.sort(Ascending)

      if contextLines.len > 0:
        for indexFromTop, contextLine in contextLines:
          let styledLine = self.getStyledText contextLine
          let y = indexFromTop.float * builder.textHeight
          let colors = [(first: 0.RuneIndex, last: self.document.lines[contextLine].runeLen.RuneIndex, color: contextBackgroundColor)]

          cursors.add self.renderLine(builder, app.theme, styledLine, self.document.lines[contextLine], self.document.lineIds[contextLine],
            self.userId, cursorLine, contextLine, lineNumbers, y, sizeToContentX, lineNumberWidth, lineNumberBounds.x, vec2(0, 0),
            contextBackgroundColor, textColor,
            colors, [], false, wrapLineEndChar, wrapLineEndColor,
            )

        # let fill = self.scrollOffset mod builder.textHeight
        # if fill < builder.textHeight / 2:
        #   builder.panel(&{FillX, FillBackground}, y = contextLines.len.float * builder.textHeight, h = fill, backgroundColor = contextBackgroundColor)

    for cursorIndex, cursorLocation in cursors: #cursor
      if cursorLocation.original == self.selection.last:
        result = cursorLocation.some

      var bounds = cursorLocation.bounds.transformRect(cursorLocation.node, linesPanel) - vec2(app.platform.charGap, 0)
      bounds.w += app.platform.charGap
      if not self.cursorVisible:
        bounds.w = 0

      builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, MaskContent}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = cursorForegroundColor, userId = newSecondaryId(self.cursorsId, cursorIndex.int32)):
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = app.platform.charGap, y = 0, text = cursorLocation.text, textColor = cursorBackgroundColor)

    defer:
      self.lastContentBounds = currentNode.bounds

proc createCompletions(self: TextDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let backgroundColor = app.theme.color("panel.background", color(30/255, 30/255, 30/255))
  let selectedBackgroundColor = app.theme.color("list.activeSelectionBackground", color(200/255, 200/255, 200/255))
  let docsColor = app.theme.color("editor.foreground", color(1, 1, 1))
  let nameColor = app.theme.tokenColor(@["entity.name.label", "entity.name"], color(1, 1, 1))
  let scopeColor = app.theme.color("string", color(175/255, 1, 175/255))

  const numLinesToShow = 20
  let (top, bottom) = (cursorBounds.yh.float, cursorBounds.yh.float + totalLineHeight * numLinesToShow)

  const listWidth = 120.0
  const docsWidth = 50.0
  let totalWidth = charWidth * listWidth + charWidth * docsWidth
  var clampedX = cursorBounds.x
  if clampedX + totalWidth > builder.root.w:
    clampedX = max(builder.root.w - totalWidth, 0)

  updateBaseIndexAndScrollOffset(bottom - top, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  var completionsPanel: UINode = nil
  builder.panel(&{SizeToContentX, SizeToContentY, AnimateBounds, MaskContent}, x = clampedX, y = top, w = totalWidth, h = bottom - top, pivot = vec2(0, 0), userId = self.completionsId.newPrimaryId):
    completionsPanel = currentNode

    proc handleScroll(delta: float) =
      let scrollAmount = delta * app.asConfigProvider.getValue("text.scroll-speed", 40.0)
      self.scrollOffset += scrollAmount
      self.markDirty()

    proc handleLine(i: int, y: float, down: bool) =
      var backgroundColor = backgroundColor
      if i == self.selectedCompletion:
        backgroundColor = selectedBackgroundColor

      backgroundColor.a = 1

      let pivot = if down:
        vec2(0, 0)
      else:
        vec2(0, 1)

      builder.panel(&{FillX, SizeToContentY, FillBackground}, y = y, pivot = pivot, backgroundColor = backgroundColor):
        let completion = self.completions[i]

        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = completion.name, textColor = nameColor)

        let scopeText = completion.typ & " : " & completion.scope
        builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = currentNode.w, pivot = vec2(1, 0), text = scopeText, textColor = scopeColor)

    builder.panel(&{UINodeFlag.MaskContent}, w = listWidth * charWidth, h = bottom - top):
      builder.createLines(self.completionsBaseIndex, self.completionsScrollOffset, self.completions.high, false, false, backgroundColor, handleScroll, handleLine)

    builder.panel(&{UINodeFlag.FillBackground, DrawText, MaskContent, TextWrap},
      x = listWidth * charWidth, w = docsWidth * charWidth, h = bottom - top,
      backgroundColor = backgroundColor, textColor = docsColor, text = self.completions[self.selectedCompletion].doc)

  if completionsPanel.bounds.yh > completionsPanel.parent.bounds.h:
    completionsPanel.rawY = cursorBounds.y
    completionsPanel.pivot = vec2(0, 1)

method createUI*(self: TextDocumentEditor, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let dirty = self.dirty
  self.resetDirty()

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: app.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: app.theme.color("editor.background", color(25/255, 25/255, 25/255)) * 0.85
  backgroundColor.a = 1

  var headerColor = if self.active: app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1

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

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId):
    if not self.disableScrolling and not sizeToContentY:
      updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, builder.textHeight, int.none)

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.currentMode, self.document, headerColor, textColor):
          onRight:
            proc cursorString(cursor: Cursor): string = $cursor.line & ":" & $cursor.column & ":" & $self.document.lines[cursor.line].toOpenArray.runeIndex(cursor.column)
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, pivot = vec2(1, 0), textColor = textColor, text = fmt" {(cursorString(self.selection.first))}-{(cursorString(self.selection.last))} - {self.id} ")
        if self.createTextLines(builder, app, backgroundColor, textColor, sizeToContentX, sizeToContentY).getSome(info):
          self.lastCursorLocationBounds = info.bounds.transformRect(info.node, builder.root).some

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))

proc shouldIgnoreAsContextLine(self: TextDocument, line: int): bool =
  let indent = self.getIndentLevelForLine(line)
  return line > 0 and self.languageConfig.isSome and self.languageConfig.get.ignoreContextLinePrefix.isSome and
        self.lineStartsWith(line, self.languageConfig.get.ignoreContextLinePrefix.get, true) and self.getIndentLevelForLine(line - 1) == indent

proc clampToLine(document: TextDocument, selection: Selection, line: StyledLine): tuple[first: RuneIndex, last: RuneIndex] =
  result.first = if selection.first.line < line.index: 0.RuneIndex elif selection.first.line == line.index: document.lines[line.index].runeIndex(selection.first.column) else: line.runeLen.RuneIndex
  result.last = if selection.last.line < line.index: 0.RuneIndex elif selection.last.line == line.index: document.lines[line.index].runeIndex(selection.last.column) else: line.runeLen.RuneIndex
