import std/[strformat, tables, sugar, sequtils, strutils, algorithm, math, options, json]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, regex]
import text/text_editor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, document_editor, theme, config_provider, app_interface
import text/language/[lsp_types]
import text/diff

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_text"

type CursorLocationInfo* = tuple[node: UINode, text: string, bounds: Rect, original: Cursor]
type LocationInfos = object
  cursor: Option[CursorLocationInfo]
  hover: Option[CursorLocationInfo]
  diagnostic: Option[CursorLocationInfo]

type LineRenderOptions = object
  handleClick: proc(btn: MouseButton, pos: Vec2, line: int, partIndex: Option[int])
  handleDrag: proc(btn: MouseButton, pos: Vec2, line: int, partIndex: Option[int])
  handleBeginHover: proc(node: UINode, pos: Vec2, line: int, partIndex: int)
  handleHover: proc(node: UINode, pos: Vec2, line: int, partIndex: int)
  handleEndHover: proc(node: UINode, pos: Vec2, line: int, partIndex: int)

  wrapLine: bool
  wrapLineEndChar: string
  wrapLineEndColor: Color
  lineEndColor: Option[Color]
  backgroundColor: Color
  textColor: Color

  lineNumber: int
  lineNumbers: LineNumbers
  y: float
  sizeToContentX: bool
  lineNumberTotalWidth: float
  lineNumberWidth: float
  pivot: Vec2

  signWidth: float
  signs: seq[string]

  hoverLocation: Cursor

  theme: Theme

  parentId: Id
  cursorLine: int

  indentInSpaces: int

when defined(js):
  template tokenColor*(theme: Theme, part: StyledText, default: untyped): Color =
    if part.scopeIsToken:
      theme.tokenColor(part.scopeC, default)
    else:
      theme.color(part.scope, default)
else:
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
      let byteIndex = self.document.byteOffsetInLine(line, runeOffset)
      return byteIndex

    offset += w
    inc i

  let byteIndex = self.document.byteOffsetInLine(line, startOffset + text.runeLen)
  return byteIndex

proc renderLinePart(
  builder: UINodeBuilder, line: StyledLine,
  backgroundColors: openArray[tuple[first: RuneIndex, last: RuneIndex, color: Color]],
  options: LineRenderOptions, partIndex: int, startRune: RuneIndex, partRuneLen: RuneCount): UINode =

  let part = line.parts[partIndex].addr

  let textColor = if part.scope.len == 0: options.textColor else: options.theme.tokenColor(part[], options.textColor)

  # Find background color
  var colorIndex = 0
  while colorIndex < backgroundColors.high and (backgroundColors[colorIndex].first == backgroundColors[colorIndex].last or backgroundColors[colorIndex].last <= startRune):
    inc colorIndex

  var partBackgroundColor = options.backgroundColor
  var addBackgroundAsChildren = true

  # check if fully covered by background color (inlay text is always fully covered by background color)
  if part[].textRange.isNone or backgroundColors[colorIndex].last >= startRune + partRuneLen:
    partBackgroundColor = backgroundColors[colorIndex].color
    addBackgroundAsChildren = false

  var partFlags = &{SizeToContentX, SizeToContentY, MouseHover}
  var textFlags = 0.UINodeFlags

  # if the entire part is the same background color we can just fill the background and render the text on the part itself
  # otherwise we need to render the background as a separate node and render the text on top of it, as children of the main part node,
  # which still has a background color though
  if not addBackgroundAsChildren:
    partFlags.incl DrawText
    partFlags.incl FillBackground
  else:
    partFlags.incl OverlappingChildren

  if part[].underline:
    if addBackgroundAsChildren:
      textFlags.incl TextUndercurl
      partFlags.incl FillBackground
    else:
      partFlags.incl TextUndercurl

  let text = if addBackgroundAsChildren: "" else: part[].text
  let textRuneLen = part[].text.runeLen.int

  let handleClick = options.handleClick
  let handleDrag = options.handleDrag
  let handleBeginHover = options.handleBeginHover
  let handleHover = options.handleHover
  let handleEndHover = options.handleEndHover

  let isInlay = part[].textRange.isNone
  builder.panel(partFlags, text = text, backgroundColor = partBackgroundColor, textColor = textColor, underlineColor = part[].underlineColor):
    result = currentNode
    let partNode = currentNode

    capture line, partNode, startRune, textRuneLen, isInlay, partIndex:
      onClickAny btn:
        if handleClick.isNotNil:
          handleClick(btn, pos, line.index, partIndex.some)

      onDrag Left:
        if handleDrag.isNotNil:
          handleDrag(Left, pos, line.index, partIndex.some)

      onBeginHover:
        if handleBeginHover.isNotNil:
          handleBeginHover(partNode, pos, line.index, partIndex)

      onHover:
        if handleHover.isNotNil:
          handleHover(partNode, pos, line.index, partIndex)

      onEndHover:
        if handleEndHover.isNotNil:
          handleEndHover(partNode, pos, line.index, partIndex)

    if addBackgroundAsChildren:
      # Add separate background colors for selections/highlights
      while colorIndex <= backgroundColors.high and backgroundColors[colorIndex].first < startRune + partRuneLen:
        let startIndex = backgroundColors[colorIndex].first
        let endIndex = backgroundColors[colorIndex].last
        let startIndexInPart = RuneIndex(startIndex - startRune).max(0.RuneIndex)
        let endIndexInPart = RuneIndex(endIndex - startRune).min(partRuneLen.RuneIndex)
        let x = builder.textWidth(part[].text[0.RuneIndex..<startIndexInPart]).round
        let w = builder.textWidth(part[].text[startIndexInPart..<endIndexInPart]).round
        if partBackgroundColor != backgroundColors[colorIndex].color:
          builder.panel(&{UINodeFlag.FillBackground, FillY}, x = x, w = w, backgroundColor = backgroundColors[colorIndex].color)

        inc colorIndex

      # Add text on top of background colors
      builder.panel(&{DrawText, SizeToContentX, SizeToContentY} + textFlags, text = part[].text, textColor = textColor, underlineColor = part[].underlineColor)

# todo: replace lineOriginal with RopeSlice
proc renderLine*(
  builder: UINodeBuilder, line: StyledLine, lineOriginal: openArray[char],
  backgroundColors: openArray[tuple[first: RuneIndex, last: RuneIndex, color: Color]], cursors: openArray[int],
  options: LineRenderOptions, useUserId: bool = true):
    tuple[cursors: seq[CursorLocationInfo], hover: Option[CursorLocationInfo], diagnostic: Option[CursorLocationInfo]] =

  var flagsInner = &{FillX, SizeToContentY}
  if options.sizeToContentX:
    flagsInner.incl SizeToContentX

  # line numbers
  var lineNumberText = ""
  var lineNumberX = 0.float
  if options.lineNumbers != LineNumbers.None and options.cursorLine == options.lineNumber:
    lineNumberText = $(options.lineNumber + 1)
  elif options.lineNumbers == LineNumbers.Absolute:
    lineNumberText = $(options.lineNumber + 1)
    lineNumberX = max(0.0, options.lineNumberWidth - lineNumberText.len.float * builder.charWidth)
  elif options.lineNumbers == LineNumbers.Relative:
    lineNumberText = $abs((options.lineNumber + 1) - options.cursorLine)
    lineNumberX = max(0.0, options.lineNumberWidth - lineNumberText.len.float * builder.charWidth)

  # todo: do we still need the id?
  builder.panel(flagsInner + LayoutVertical + FillBackground, y = options.y, pivot = options.pivot, backgroundColor = options.backgroundColor, userId = newSecondaryId(options.parentId, line.index.int32)):
    let lineWidth = currentNode.bounds.w

    var cursorBaseNode: UINode = nil
    var cursorBaseXW: float32 = 0

    var lastTextSubLine: UINode = nil
    var lastTextPartXW: float32 = 0

    var subLine: UINode = nil

    var start = 0
    var lastPartXW: float32 = 0
    var partIndex = 0
    var subLineIndex = 0
    var subLinePartIndex = 0
    var previousInlayNode: UINode = nil

    var textStartX = 0.0
    if options.signWidth > 0:
      textStartX += options.signWidth

    if lineNumberText.len > 0:
      textStartX += options.lineNumberTotalWidth

    while partIndex < line.parts.len: # outer loop for wrapped lines within this line

      builder.panel(flagsInner + LayoutHorizontal):
        subLine = currentNode
        if lastTextSubLine.isNil or partIndex < line.parts.len:
          lastTextSubLine = subLine

        if options.signWidth > 0:
          builder.panel(&{UINodeFlag.FillBackground, FillY}, w = options.signWidth,
              backgroundColor = options.backgroundColor):
            if subLineIndex == 0 and options.signs.len > 0:
              builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = options.signs[0],
                textColor = options.textColor)
          lastPartXW = options.signWidth
          if partIndex < line.parts.len:
            lastTextPartXW = lastPartXW

        if lineNumberText.len > 0:
          builder.panel(&{UINodeFlag.FillBackground, FillY}, w = options.lineNumberTotalWidth, backgroundColor = options.backgroundColor):
            if subLineIndex == 0:
              builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = lineNumberText,
                x = lineNumberX, textColor = options.textColor)
          lastPartXW = options.lineNumberTotalWidth
          if partIndex < line.parts.len:
            lastTextPartXW = lastPartXW

        if subLineIndex > 0:
          builder.panel(&{}, w = options.indentInSpaces.float * builder.charWidth):
            lastPartXW = currentNode.bounds.xw

        while partIndex < line.parts.len: # inner loop for parts within a wrapped line part
          template part: StyledText = line.parts[partIndex]

          let partRuneLen = part.text.runeLen
          let width = (partRuneLen.float * builder.charWidth).ceil

          if options.wrapLine and part.canWrap and not options.sizeToContentX and subLinePartIndex > 0:
            var wrapWidth = width
            for partIndex2 in partIndex..<line.parts.high:
              if line.parts[partIndex2].joinNext:
                let nextWidth = (line.parts[partIndex2 + 1].text.runeLen.float * builder.charWidth).ceil
                if options.lineNumberTotalWidth + wrapWidth + nextWidth + builder.charWidth <= lineWidth:
                  wrapWidth += nextWidth
                  continue
              break

            if lastPartXW + wrapWidth + builder.charWidth >= lineWidth:
              builder.panel(&{DrawText, FillBackground, SizeToContentX, SizeToContentY}, text = options.wrapLineEndChar, backgroundColor = options.backgroundColor, textColor = options.wrapLineEndColor):
                defer:
                  lastPartXW = currentNode.xw
                  lastTextPartXW = lastPartXW
              subLineIndex += 1
              subLinePartIndex = 0
              break

          let (startRune, _) = line.getTextRange(partIndex)
          let partNode = renderLinePart(builder, line, backgroundColors, options, partIndex, startRune, partRuneLen)

          if part.textRange.isSome or part.modifyCursorAtEndOfLine:
            cursorBaseNode = subLine
            cursorBaseXW = partNode.bounds.xw

          if part.textRange.isSome:
            part.visualRange = (
              ((partNode.bounds.x - textStartX + 0.5) / builder.charWidth).int,
              ((partNode.bounds.xw - textStartX + 0.5) / builder.charWidth).int,
              subLineIndex,
            ).some

          # cursor
          for curs in cursors:
            let selectionLastRune = lineOriginal.runeIndex(curs)

            if part.textRange.isSome:
              if selectionLastRune >= part.textRange.get.startIndex and selectionLastRune < part.textRange.get.endIndex:
                let node = if selectionLastRune == startRune and previousInlayNode.isNotNil and line.parts[partIndex - 1].inlayContainCursor:
                  # show cursor on first position of previous inlay
                  previousInlayNode
                else:
                  partNode

                let indexInString = RuneIndex(selectionLastRune - part.textRange.get.startIndex)
                let rune = part.text[indexInString]
                let cursorX = builder.textWidth(part.text[0.RuneIndex..<indexInString]).round
                let cursorW = builder.textWidth($rune).round
                result.cursors.add (node, $rune, rect(cursorX, 0, max(builder.charWidth, cursorW), builder.textHeight), (line.index, curs))

            # Set hover info if the hover location is within this part
            if line.index == options.hoverLocation.line and part.textRange.isSome:
              let startRune = part.textRange.get.startIndex
              let endRune = part.textRange.get.endIndex
              let hoverRune = lineOriginal.runeIndex(options.hoverLocation.column)
              if hoverRune >= startRune and hoverRune < endRune:
                result.hover = (partNode, "", rect(0, 0, builder.charWidth, builder.textHeight), options.hoverLocation).some

          if part.textRange.isNone:
            previousInlayNode = partNode
          else:
            previousInlayNode = nil

          lastPartXW = partNode.bounds.xw
          lastTextPartXW = lastPartXW
          start += part.text.len
          partIndex += 1
          subLinePartIndex += 1

        # endwhile partIndex < line.parts.len:

        # Fill rest of line with background
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = options.backgroundColor):
          capture line, currentNode:
            onClickAny btn:
              if options.handleClick.isNotNil:
                options.handleClick(btn, pos, line.index, int.none)

            onDrag Left:
              if options.handleDrag.isNotNil:
                options.handleDrag(Left, pos, line.index, int.none)

          if options.lineEndColor.getSome(color):
            builder.panel(&{FillY, FillBackground}, w = builder.charWidth, backgroundColor = color)

    # cursor after latest char
    for curs in cursors:
      if curs == lineOriginal.len:
        result.cursors.add (cursorBaseNode, "", rect(cursorBaseXW, 0, builder.charWidth, builder.textHeight), (line.index, curs))

    # set hover info if the hover location is at the end of this line
    if line.index == options.hoverLocation.line and options.hoverLocation.column == lineOriginal.len:
      result.hover = (cursorBaseNode, "", rect(cursorBaseXW, 0, builder.charWidth, builder.textHeight), options.hoverLocation).some

proc blendColorRanges(colors: var seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]], ranges: var seq[tuple[first: RuneIndex, last: RuneIndex]], color: Color, inclusive: bool) =
  let inclusiveOffset = if inclusive: 1.RuneCount else: 0.RuneCount
  for s in ranges.mitems:
    var colorIndex = 0
    for i in 0..colors.high:
      if colors[i].last > s.first:
        colorIndex = i
        break

    while colorIndex <= colors.high and colors[colorIndex].last > s.first and colors[colorIndex].first < s.last + inclusiveOffset and s.first != s.last + inclusiveOffset:
      let lastIndex = colors[colorIndex].last
      colors[colorIndex].last = s.first

      if lastIndex < s.last + inclusiveOffset:
        colors.insert (s.first, lastIndex, colors[colorIndex].color.withAlpha(1).blendNormal(color)), colorIndex + 1
        s.first = lastIndex
        inc colorIndex
      else:
        colors.insert (s.first, s.last + inclusiveOffset, colors[colorIndex].color.withAlpha(1).blendNormal(color)), colorIndex + 1
        colors.insert (s.last + inclusiveOffset, lastIndex, colors[colorIndex].color), colorIndex + 2
        break

      inc colorIndex

proc blendColorRanges(colors: var seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]], ranges: var seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]], inclusive: bool) =
  let inclusiveOffset = if inclusive: 1.RuneCount else: 0.RuneCount
  for s in ranges.mitems:
    var colorIndex = 0
    for i in 0..colors.high:
      if colors[i].last > s.first:
        colorIndex = i
        break

    while colorIndex <= colors.high and colors[colorIndex].last > s.first and colors[colorIndex].first < s.last + inclusiveOffset and s.first != s.last + inclusiveOffset:
      let lastIndex = colors[colorIndex].last
      colors[colorIndex].last = s.first

      if lastIndex < s.last + inclusiveOffset:
        colors.insert (s.first, lastIndex, colors[colorIndex].color.withAlpha(1).blendNormal(s.color)), colorIndex + 1
        s.first = lastIndex
        inc colorIndex
      else:
        colors.insert (s.first, s.last + inclusiveOffset, colors[colorIndex].color.withAlpha(1).blendNormal(s.color)), colorIndex + 1
        colors.insert (s.last + inclusiveOffset, lastIndex, colors[colorIndex].color), colorIndex + 2
        break

      inc colorIndex

proc createDoubleLines*(builder: UINodeBuilder, previousBaseIndex: int, scrollOffset: float, maxLine: int, sizeToContentX: bool, sizeToContentY: bool, backgroundColor: Color, handleScroll: proc(delta: float), handleLine: proc(line: int, y: float, down: bool)) =
  var flags = 0.UINodeFlags
  if sizeToContentX:
    flags.incl SizeToContentX
  else:
    flags.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
  else:
    flags.incl FillY

  builder.panel(flags):
    onScroll:
      handleScroll(delta.y)

    let height = currentNode.bounds.h
    var y = scrollOffset

    # draw lines downwards
    for i in previousBaseIndex..maxLine:
      handleLine(i, y, true)

      y = builder.currentChild.yh
      if not sizeToContentY and builder.currentChild.bounds.y > height:
        break

    y = scrollOffset

    # draw lines upwards
    for i in countdown(previousBaseIndex - 1, 0):
      handleLine(i, y, false)

      y = builder.currentChild.y
      if not sizeToContentY and builder.currentChild.bounds.yh < 0:
        break

proc createTextLines(self: TextDocumentEditor, builder: UINodeBuilder, app: App, backgroundColor: Color, textColor: Color, sizeToContentX: bool, sizeToContentY: bool): LocationInfos =
  var flags = 0.UINodeFlags
  if sizeToContentX:
    flags.incl SizeToContentX
  else:
    flags.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
  else:
    flags.incl FillY

  let inclusive = getOption[bool](app, "editor.text.inclusive-selection", false)

  let lineNumbers = self.lineNumbers.get getOption[LineNumbers](app, "editor.text.line-numbers", LineNumbers.Absolute)
  let charWidth = builder.charWidth

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let showContextLines = not renderDiff and getOption[bool](app, "editor.text.context-lines", true)

  let selectionColor = app.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let cursorForegroundColor = app.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
  let contextBackgroundColor = app.theme.color(@["breadcrumbPicker.background", "background"], color(50/255, 70/255, 70/255))
  let insertedTextBackgroundColor = app.theme.color(@["diffEditor.insertedTextBackground", "diffEditor.insertedLineBackground"], color(0.1, 0.2, 0.1))
  let deletedTextBackgroundColor = app.theme.color(@["diffEditor.removedTextBackground", "diffEditor.removedLineBackground"], color(0.2, 0.1, 0.1))
  let changedTextBackgroundColor = app.theme.color(@["diffEditor.changedTextBackground", "diffEditor.changedLineBackground"], color(0.2, 0.2, 0.1))

  proc handleClick(btn: MouseButton, pos: Vec2, line: int, partIndex: Option[int]) =
    if self.document.isNil:
      return

    self.lastPressedMouseButton = btn

    if btn notin {MouseButton.Left, DoubleClick, TripleClick}:
      return
    if line >= self.document.numLines:
      return

    if partIndex.getSome(partIndex):
      let styledLine = self.getStyledText(line)
      let (startRune, _) = styledLine.getTextRange(partIndex)
      if partIndex notin 0..<styledLine.parts.len:
        return

      let part = styledLine.parts[partIndex]
      let isInlay = part.textRange.isNone
      let offset = self.getCursorPos(builder, part.text, line, startRune, if isInlay: vec2() else: pos)
      self.selection = (line, offset).toSelection
    else:
      self.selection = (line, self.document.lineLength(line)).toSelection

    self.dragStartSelection = self.selection

    if btn == Left:
      self.runSingleClickCommand()
    elif btn == DoubleClick:
      self.runDoubleClickCommand()
    elif btn == TripleClick:
      self.runTripleClickCommand()

    self.updateTargetColumn(Last)
    self.app.tryActivateEditor(self)
    self.markDirty()

  proc handleDrag(btn: MouseButton, pos: Vec2, line: int, partIndex: Option[int]) =
    if self.document.isNil:
      return

    if line >= self.document.numLines:
      return

    if not self.active:
      return

    let currentSelection = self.dragStartSelection

    let newCursor = if partIndex.getSome(partIndex):
      let styledLine = self.getStyledText(line)
      let (startRune, _) = styledLine.getTextRange(partIndex)
      if partIndex notin 0..<styledLine.parts.len:
        return

      let part = styledLine.parts[partIndex]
      let isInlay = part.textRange.isNone
      let offset = self.getCursorPos(builder, part.text, line, startRune, if isInlay: vec2() else: pos)
      (line, offset)
    else:
      (line, self.document.lineLength(line))

    let first = if (currentSelection.isBackwards and newCursor < currentSelection.first) or (not currentSelection.isBackwards and newCursor >= currentSelection.first):
      currentSelection.first
    else:
      currentSelection.last
    self.selection = (first, newCursor)
    self.runDragCommand()
    self.updateTargetColumn(Last)
    self.app.tryActivateEditor(self)
    self.markDirty()

  proc handleBeginHover(node: UINode, pos: Vec2, line: int, partIndex: int) =
    if self.document.isNil:
      return

    if line >= self.document.numLines:
      return

    let styledLine = self.getStyledText(line)
    let (startRune, _) = styledLine.getTextRange(partIndex)
    if partIndex notin 0..<styledLine.parts.len:
      return

    let part = styledLine.parts[partIndex]
    let offset = self.getCursorPos(builder, part.text, line, startRune, pos)
    self.lastHoverLocationBounds = node.boundsAbsolute.some
    self.showHoverForDelayed (line, offset)

  proc handleHover(node: UINode, pos: Vec2, line: int, partIndex: int) =
    if self.document.isNil:
      return

    if line >= self.document.numLines:
      return

    let styledLine = self.getStyledText(line)
    let (startRune, _) = styledLine.getTextRange(partIndex)
    if partIndex notin 0..<styledLine.parts.len:
      return

    let part = styledLine.parts[partIndex]
    let offset = self.getCursorPos(builder, part.text, line, startRune, pos)
    self.lastHoverLocationBounds = node.boundsAbsolute.some
    self.showHoverForDelayed (line, offset)

  proc handleEndHover(node: UINode, pos: Vec2, line: int, partIndex: int) =
    if self.document.isNil:
      return

    self.hideHoverDelayed()

  var options = LineRenderOptions(
    backgroundColor: backgroundColor,
    textColor: textColor,
    hoverLocation: self.hoverLocation,
    theme: app.theme,
  )

  options.handleClick = handleClick
  options.handleDrag = handleDrag
  options.handleBeginHover = handleBeginHover
  options.handleHover = handleHover
  options.handleEndHover = handleEndHover

  options.wrapLineEndChar = getOption[string](app, "editor.text.wrap-line-end-char", "↲")
  options.wrapLine = getOption[bool](app, "editor.text.wrap-lines", true)
  options.wrapLineEndColor = app.theme.tokenColor(@["comment"], color(100/255, 100/255, 100/255))

  var selectionsPerLine = initTable[int, seq[Selection]]()
  for s in self.selections:
    let sn = s.normalized
    for line in sn.first.line..sn.last.line:
      selectionsPerLine.mgetOrPut(line, @[]).add s

  builder.panel(flags + MaskContent + OverlappingChildren):
    let linesPanel = currentNode

    # line numbers
    let maxLineNumber = case lineNumbers
      of LineNumbers.Absolute: self.document.numLines
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

    options.lineNumbers = lineNumbers
    options.sizeToContentX = sizeToContentX
    options.lineNumberTotalWidth = lineNumberWidth
    options.lineNumberWidth = lineNumberBounds.x

    if self.signs.len > 0:
      options.signWidth = 2 * charWidth

    var cursors: seq[CursorLocationInfo]
    var contextLines: seq[int]
    var contextLineTarget: int = -1
    var hoverInfo = CursorLocationInfo.none
    var diagnosticInfo = CursorLocationInfo.none

    proc handleScroll(delta: float) =
      self.scrollText(delta * app.asConfigProvider.getValue("text.scroll-speed", 40.0))

    proc handleLine(i: int, y: float, down: bool) =
      assert i in 0..<self.document.numLines

      let styledLine = self.getStyledText i
      let totalLineHeight = builder.textHeight

      self.lastRenderedLines.add styledLine

      let indexFromTop = if down:
        (y / totalLineHeight + 0.5).ceil.int - 1
      else:
        (y / totalLineHeight - 0.5).ceil.int - 1

      let indentLevel = self.document.getIndentLevelForClosestLine(i)

      let diffEmptyBackgroundColor = backgroundColor.darken(0.03)

      var backgroundColor = if cursorLine == i:
        backgroundColor.lighten(0.05)
      else:
        backgroundColor

      let nextLineDiff = self.diffChanges.mapIt(mapLineTargetToSource(it, i + 1)).flatten

      let lineRuneLen = self.document.lineRuneLen(i).RuneIndex
      let otherLine = self.diffChanges.mapIt(mapLineTargetToSource(it, i)).flatten
      if renderDiff:
        if otherLine.getSome(otherLine) and otherLine.changed:
          backgroundColor = backgroundColor.withAlpha(1).blendNormal(changedTextBackgroundColor)
        elif otherLine.isNone:
          backgroundColor = backgroundColor.withAlpha(1).blendNormal(insertedTextBackgroundColor)

      options.backgroundColor = backgroundColor

      if showContextLines and (indexFromTop <= indentLevel and not self.document.shouldIgnoreAsContextLine(i)):
        contextLineTarget = max(contextLineTarget, i)

      proc parseColor(str: string): Color = app.theme.color(str, color(200/255, 200/255, 200/255))

      # selections and highlights
      var selectionsClampedOnLine = selectionsPerLine.getOrDefault(i, @[]).map (s) => self.document.clampToLine(s.normalized, styledLine)
      var highlightsClampedOnLine: seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]] =
        self.customHighlights.getOrDefault(i, @[]).map (s) => (let x = self.document.clampToLine(s.selection.normalized, styledLine); (x[0], x[1], parseColor(s.color) * s.tint))

      selectionsClampedOnLine.sort((a, b) => cmp(a.first, b.first), Ascending)
      highlightsClampedOnLine.sort((a, b) => cmp(a.first, b.first), Ascending)
      var colors: seq[tuple[first: RuneIndex, last: RuneIndex, color: Color]] = @[(0.RuneIndex, lineRuneLen, backgroundColor)]
      blendColorRanges(colors, highlightsClampedOnLine, inclusive)
      blendColorRanges(colors, selectionsClampedOnLine, selectionColor, inclusive)

      var cursorsPerLine: seq[int]
      for s in self.selections:
        if s.last.line == i:
          cursorsPerLine.add s.last.column

      options.lineEndColor = Color.none
      if self.document.lineLength(i) == 0 and selectionsClampedOnLine.len > 0 and (cursorsPerLine.len == 0 or inclusive):
        options.lineEndColor = selectionColor.some

      let pivot = if down:
        vec2(0, 0)
      else:
        vec2(0, 1)

      options.lineNumber = i
      options.y = y
      options.pivot = pivot
      options.parentId = self.userId
      options.cursorLine = cursorLine

      if renderDiff:
        let otherLine = self.diffChanges.get.mapLineTargetToSource(i)
        options.y = 0
        options.pivot = vec2(0, 0)

        builder.panel(&{FillX, SizeToContentY}, y = y, pivot = pivot):
          let width = currentNode.bounds.w
          var leftOffsetY = 0'f32
          if otherLine.getSome(otherLine) and otherLine.line < self.diffDocument.numLines:

            options.handleClick = nil
            options.handleDrag = nil
            options.handleBeginHover = nil
            options.handleHover = nil
            options.handleEndHover = nil

            let otherCursorLine = self.diffChanges.mapIt(mapLineTargetToSource(it, cursorLine))
            builder.panel(&{SizeToContentY, LayoutVertical}, w = width / 2):
              if i == 0 and otherLine.line > 0:
                for k in 0..<otherLine.line:
                  let styledLine = self.diffDocument.getStyledText k
                  options.backgroundColor = backgroundColor.withAlpha(1).blendNormal(deletedTextBackgroundColor)
                  let colors = [(
                    0.RuneIndex,
                    self.diffDocument.lineRuneLen(k).RuneIndex,
                    options.backgroundColor
                  )]

                  options.lineNumber = k
                  options.cursorLine = -1
                  options.indentInSpaces = self.diffDocument.getIndentLevelForLineInSpaces(k, 2)
                  discard renderLine(builder, styledLine, self.diffDocument.getLine(k), colors, [], options)
                  let lastLine = builder.currentChild
                  leftOffsetY = lastLine.bounds.yh

              let styledLine = self.diffDocument.getStyledText otherLine.line
              options.backgroundColor = backgroundColor
              options.lineNumber = otherLine.line
              options.cursorLine = otherCursorLine.flatten.get((-1, false)).line
              options.indentInSpaces = self.diffDocument.getIndentLevelForLineInSpaces(otherLine.line, 2)
              let colors = [(0.RuneIndex, self.diffDocument.lineRuneLen(otherLine.line).RuneIndex, backgroundColor)]
              discard renderLine(builder, styledLine, self.diffDocument.getLine(otherLine.line), colors, [], options)

              if nextLineDiff.getSome(nextLineDiff) and nextLineDiff.line > otherLine.line + 1:
                for k in (otherLine.line + 1)..<nextLineDiff.line:
                  let styledLine = self.diffDocument.getStyledText k
                  options.backgroundColor = backgroundColor.withAlpha(1).blendNormal(deletedTextBackgroundColor)
                  let colors = [(0.RuneIndex, self.diffDocument.lineRuneLen(k).RuneIndex, options.backgroundColor)]
                  options.lineNumber = k
                  options.indentInSpaces = self.diffDocument.getIndentLevelForLineInSpaces(k, 2)
                  discard renderLine(builder, styledLine, self.diffDocument.getLine(k), colors, [], options)

          else:
            builder.panel(&{FillY, FillBackground}, w = width / 2, backgroundColor = diffEmptyBackgroundColor)

          builder.panel(&{SizeToContentY, FillY, FillBackground}, y = leftOffsetY, x = width / 2, w = width / 2, backgroundColor = diffEmptyBackgroundColor):
            options.lineNumber = i
            options.indentInSpaces = self.document.getIndentLevelForLineInSpaces(i, 2)
            options.cursorLine = cursorLine
            options.backgroundColor = backgroundColor

            options.handleClick = handleClick
            options.handleDrag = handleDrag
            options.handleBeginHover = handleBeginHover
            options.handleHover = handleHover
            options.handleEndHover = handleEndHover

            let infos = renderLine(builder, styledLine, self.document.getLine(i), colors, cursorsPerLine, options)
            cursors.add infos.cursors
            if infos.hover.isSome:
              hoverInfo = infos.hover
            if infos.diagnostic.isSome:
              diagnosticInfo = infos.diagnostic

      else:

        options.signs.setLen 0

        if self.signs.contains(i):
          for sign in self.signs[i]:
            options.signs.add sign.text

        options.indentInSpaces = self.document.getIndentLevelForLineInSpaces(i, 2)
        let infos = renderLine(builder, styledLine, self.document.getLine(i), colors, cursorsPerLine, options)
        cursors.add infos.cursors
        if infos.hover.isSome:
          hoverInfo = infos.hover
        if infos.diagnostic.isSome:
          diagnosticInfo = infos.diagnostic

    self.lastRenderedLines.setLen 0

    if renderDiff:
      builder.createDoubleLines(self.previousBaseIndex, self.scrollOffset, self.document.numLines - 1, sizeToContentX, sizeToContentY, backgroundColor, handleScroll, handleLine)
    else:
      builder.createLines(self.previousBaseIndex, self.scrollOffset, self.document.numLines - 1, sizeToContentX, sizeToContentY, backgroundColor, handleScroll, handleLine)

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
        options.lineEndColor = Color.none
        options.wrapLine = false
        options.backgroundColor = contextBackgroundColor
        options.pivot = vec2(0, 0)

        for indexFromTop, contextLine in contextLines:
          let styledLine = self.getStyledText contextLine
          let y = indexFromTop.float * builder.textHeight
          let colors = [(first: 0.RuneIndex, last: self.document.lineRuneLen(contextLine).RuneIndex, color: contextBackgroundColor)]

          options.lineNumber = contextLine
          options.y = y
          options.parentId = self.userId
          options.cursorLine = cursorLine
          options.indentInSpaces = self.document.getIndentLevelForLineInSpaces(contextLine, 2)

          let infos = renderLine(builder, styledLine, self.document.getLine(contextLine), colors, [], options)
          cursors.add infos.cursors
          if infos.hover.isSome:
            result.hover = infos.hover

        # let fill = self.scrollOffset mod builder.textHeight
        # if fill < builder.textHeight / 2:
        #   builder.panel(&{FillX, FillBackground}, y = contextLines.len.float * builder.textHeight, h = fill, backgroundColor = contextBackgroundColor)

    let isThickCursor = self.isThickCursor

    if hoverInfo.isSome:
      result.hover = hoverInfo
    if diagnosticInfo.isSome:
      result.diagnostic = diagnosticInfo

    for cursorIndex, cursorLocation in cursors: #cursor
      if cursorLocation.original == self.selection.last:
        result.cursor = cursorLocation.some

      var bounds = cursorLocation.bounds.transformRect(cursorLocation.node, linesPanel) - vec2(app.platform.charGap, 0)
      bounds.w += app.platform.charGap

      if not isThickCursor:
        bounds.w = 0.2 * app.platform.charWidth

      if not self.cursorVisible:
        bounds.w = 0

      builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, MaskContent}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = cursorForegroundColor, userId = newSecondaryId(self.cursorsId, cursorIndex.int32)):
        if isThickCursor:
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = app.platform.charGap, y = 0, text = cursorLocation.text, textColor = cursorBackgroundColor)

    defer:
      self.lastContentBounds = currentNode.bounds

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
      let scrollSpeed = app.asConfigProvider.getValue("text.hover-scroll-speed", 20.0)
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

  let transparentBackground = getOption[bool](app, "ui.background.transparent", false)
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
      let scrollAmount = delta * app.asConfigProvider.getValue("text.scroll-speed", 40.0)
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

method createUI*(self: EditorView, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  self.editor.createUI(builder, app)

method createUI*(self: TextDocumentEditor, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  self.preRender()

  let dirty = self.dirty
  self.resetDirty()

  let transparentBackground = getOption[bool](app, "ui.background.transparent", false)
  let darkenInactive = getOption[float](app, "text.background.inactive-darken", 0.025)

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
      self.app.tryActivateEditor(self)

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.currentMode, self.document, headerColor, textColor):
          onRight:
            proc cursorString(cursor: Cursor): string = $cursor.line & ":" & $cursor.column & ":" & $self.document.runeIndexInLine(cursor)
            let readOnlyText = if self.document.readOnly: "-readonly- " else: ""
            let stagedText = if self.document.staged: "-staged- " else: ""
            let diffText = if renderDiff: "-diff- " else: ""

            let currentRune = self.document.runeAt(self.selection.last)
            let currentRuneText = if currentRune == 0.Rune:
              "\\0"
            elif currentRune == '\t'.Rune:
              "\\t"
            else:
              $currentRune

            var currentRuneHexText = currentRune.int.toHex.strip(trailing=false, chars={'0'})
            if currentRuneHexText.len == 0:
              currentRuneHexText = "0"

            let text = fmt"| {readOnlyText}{stagedText}{diffText}{self.document.undoableRevision}/{self.document.revision}  '{currentRuneText}' (U+{currentRuneHexText}) {(cursorString(self.selection.first))}-{(cursorString(self.selection.last))} - {self.id} "
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, pivot = vec2(1, 0), textColor = textColor, text = text)

        builder.panel(sizeFlags + &{FillBackground}, backgroundColor = backgroundColor):
          if not self.disableScrolling and not sizeToContentY:
            let bounds = currentNode.bounds

            if self.targetLine.getSome(targetLine):
              let targetLineY = (targetLine - self.previousBaseIndex).float32 * builder.textHeight + self.scrollOffset

              let center = case self.nextScrollBehaviour.get(self.defaultScrollBehaviour):
                of CenterAlways: true
                of CenterOffscreen: targetLineY < 0 or targetLineY + builder.textHeight > self.lastContentBounds.h
                of ScrollToMargin: false
                of TopOfScreen: false

              if center:
                self.previousBaseIndex = targetLine
                self.scrollOffset = bounds.h * 0.5 - builder.textHeight - 0.5

              else:
                case self.nextScrollBehaviour.get(self.defaultScrollBehaviour)
                of TopOfScreen:
                  self.previousBaseIndex = targetLine
                  self.scrollOffset = 0
                else:
                  let configMarginRelative = getOption[bool](app, "text.cursor-margin-relative", true)
                  let configMargin = getOption[float](app, "text.cursor-margin", 0.2)
                  let margin = if self.targetLineMargin.getSome(margin):
                    clamp(margin, 0.0, bounds.h * 0.5 - builder.textHeight * 0.5)
                  elif configMarginRelative:
                    clamp(configMargin, 0.0, 1.0) * 0.5 * bounds.h
                  else:
                    clamp(configMargin, 0.0, bounds.h * 0.5 - builder.textHeight * 0.5)
                  updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.document.numLines, builder.textHeight, targetLine=targetLine.some, margin=margin)

            else:
              updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.document.numLines, builder.textHeight, targetLine=int.none)

            self.targetLine = int.none
            self.nextScrollBehaviour = ScrollBehaviour.none

          let infos = self.createTextLines(builder, app, backgroundColor, textColor, sizeToContentX, sizeToContentY)
          if infos.cursor.getSome(info):
            self.lastCursorLocationBounds = info.bounds.transformRect(info.node, builder.root).some
          if infos.hover.getSome(info):
            self.lastHoverLocationBounds = info.bounds.transformRect(info.node, builder.root).some

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
    return self.lineStartsWith(line, self.languageConfig.get.ignoreContextLinePrefix.get, true)

  if self.languageConfig.get.ignoreContextLineRegex.isSome:
    # todo: don't use getLine
    return self.getLine(line).match(self.languageConfig.get.ignoreContextLineRegex.get)

  return false

proc clampToLine(document: TextDocument, selection: Selection, line: StyledLine): tuple[first: RuneIndex, last: RuneIndex] =
  result.first = if selection.first.line < line.index:
    0.RuneIndex
  elif selection.first.line == line.index:
    document.runeIndexInLine(selection.first)
  else: line.runeLen.RuneIndex

  result.last = if selection.last.line < line.index:
    0.RuneIndex
  elif selection.last.line == line.index:
    document.runeIndexInLine(selection.last)
  else:
    line.runeLen.RuneIndex
