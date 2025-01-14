import std/[strformat, tables, sugar, sequtils, strutils, algorithm, math, options, json]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, regex, rope_utils, timer]
import text/text_editor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/platform
import ui/[widget_builders_base, widget_library]
import app, document_editor, theme, config_provider, layout
import text/language/[lsp_types]
import text/[diff, custom_treesitter, wrap_map, diff_map, display_map]

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

type LineRenderOptions = object
  handleClick: proc(btn: MouseButton, pos: Vec2, line: int, partIndex: Option[int]) {.gcsafe, raises: [].}
  handleDrag: proc(btn: MouseButton, pos: Vec2, line: int, partIndex: Option[int]) {.gcsafe, raises: [].}
  handleBeginHover: proc(node: UINode, pos: Vec2, line: int, partIndex: int) {.gcsafe, raises: [].}
  handleHover: proc(node: UINode, pos: Vec2, line: int, partIndex: int) {.gcsafe, raises: [].}
  handleEndHover: proc(node: UINode, pos: Vec2, line: int, partIndex: int) {.gcsafe, raises: [].}

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

      onDrag MouseButton.Left:
        if handleDrag.isNotNil:
          handleDrag(MouseButton.Left, pos, line.index, partIndex.some)

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
  builder: UINodeBuilder, line: StyledLine, lineOriginal: RopeSlice[int],
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
          capture line:
            onClickAny btn:
              if options.handleClick.isNotNil:
                options.handleClick(btn, pos, line.index, int.none)

            onDrag MouseButton.Left:
              if options.handleDrag.isNotNil:
                options.handleDrag(MouseButton.Left, pos, line.index, int.none)

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

proc createDoubleLines*(builder: UINodeBuilder, previousBaseIndex: int, scrollOffset: float, maxLine: int, sizeToContentX: bool, sizeToContentY: bool, backgroundColor: Color, handleScroll: proc(delta: float) {.gcsafe, raises: [].}, handleLine: proc(line: int, y: float, down: bool) {.gcsafe, raises: [].}) =
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

  let inclusive = app.config.getOption[:bool]("editor.text.inclusive-selection", false)

  let lineNumbers = self.lineNumbers.get app.config.getOption[:LineNumbers]("editor.text.line-numbers", LineNumbers.Absolute)
  let charWidth = builder.charWidth

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let showContextLines = not renderDiff and app.config.getOption[:bool]("editor.text.context-lines", true)

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

    if btn == MouseButton.Left:
      self.runSingleClickCommand()
    elif btn == DoubleClick:
      self.runDoubleClickCommand()
    elif btn == TripleClick:
      self.runTripleClickCommand()

    self.updateTargetColumn(Last)
    self.layout.tryActivateEditor(self)
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
    self.layout.tryActivateEditor(self)
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

  options.wrapLineEndChar = app.config.getOption[:string]("editor.text.wrap-line-end-char", "↲")
  options.wrapLine = app.config.getOption[:bool]("editor.text.wrap-lines", true)
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
      self.scrollText(delta * app.config.asConfigProvider.getValue("text.scroll-speed", 40.0))

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
      const maxTries = 150
      var indentLevel = self.document.getIndentLevelForClosestLine(contextLineTarget)
      var tries = 0
      while indentLevel > 0 and contextLineTarget > 0:
        contextLineTarget -= 1
        let newIndentLevel = self.document.getIndentLevelForClosestLine(contextLineTarget)
        if newIndentLevel < indentLevel and not self.document.shouldIgnoreAsContextLine(contextLineTarget):
          contextLines.add contextLineTarget
          indentLevel = newIndentLevel

        inc tries
        if tries == maxTries:
          break

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

type ChunkBounds = object
  range: rope.Range[Point]
  bounds: Rect
  text: RopeChunk
  charsRange: rope.Range[int]

proc cmp(r: ChunkBounds, point: Point): int =
  if r.range.a.row > point.row:
    return 1
  if point.row == r.range.a.row and r.range.a.column > point.column:
    return 1
  if r.range.b.row < point.row:
    return -1
  if point.row == r.range.b.row and r.range.b.column < point.column:
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

proc drawHighlight(self: TextDocumentEditor, builder: UINodeBuilder, sn: Selection, color: Color, renderCommands: var RenderCommands, chunkBounds: var seq[ChunkBounds]) =
  # renderCommands.buildCommands:
  let (firstFound, firstIndexNormalized) = chunkBounds.binarySearchRange(sn.first.toPoint, Bias.Right, cmp)
  let (lastFound, lastIndexNormalized) = chunkBounds.binarySearchRange(sn.last.toPoint, Bias.Right, cmp)
  if chunkBounds.len > 0:
    let firstIndexClamped = if firstIndexNormalized != -1:
      firstIndexNormalized
    elif sn.first.toPoint < chunkBounds[0].range.a:
      0
    elif sn.first.toPoint > chunkBounds[^1].range.b:
      chunkBounds.high
    else:
      -1

    let lastIndexClamped = if lastIndexNormalized != -1:
      lastIndexNormalized
    elif sn.last.toPoint < chunkBounds[0].range.a:
      0
    elif sn.last.toPoint > chunkBounds[^1].range.b:
      chunkBounds.high
    else:
      -1

    if firstIndexClamped != -1 and lastIndexClamped != -1:
      for i in firstIndexClamped..lastIndexClamped:
        if i >= chunkBounds.len:
          break

        let bounds = chunkBounds[i]
        let lineLen = self.document.lineLength(bounds.range.a.row.int)

        # todo: correctly handle multi byte chars
        let firstOffset = if lineLen == 0:
          0
        elif sn.first.toPoint in bounds.range:
          sn.first.column - bounds.range.a.column.int
        elif sn.first.toPoint < bounds.range.a:
          0
        else:
          bounds.range.len.column.int

        let lastOffset = if lineLen == 0:
          1
        elif sn.last.toPoint in bounds.range:
          sn.last.column - bounds.range.a.column.int
        elif sn.last.toPoint < bounds.range.a:
          0
        else:
          bounds.range.len.column.int

        var selectionBounds = rect(
          bounds.bounds.xy + vec2(firstOffset.float * builder.charWidth, 0),
          vec2((lastOffset - firstOffset).float * builder.charWidth, builder.textHeight))
        # fillRect(selectionBounds, color)
        renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: selectionBounds, color: color))

proc drawLineNumber(renderCommands: var RenderCommands, builder: UINodeBuilder, lineNumber: int, offset: Vec2, cursorLine: int, lineNumbers: LineNumbers, lineNumberBounds: Vec2, textColor: Color) =
  var lineNumberText = ""
  var lineNumberX = 0.float
  if lineNumbers != LineNumbers.None and cursorLine == lineNumber:
    lineNumberText = $(lineNumber + 0)
  elif lineNumbers == LineNumbers.Absolute:
    lineNumberText = $(lineNumber + 0)
    lineNumberX = max(0.0, lineNumberBounds.x - lineNumberText.len.float * builder.charWidth)
  elif lineNumbers == LineNumbers.Relative:
    lineNumberText = $abs((lineNumber + 0) - cursorLine)
    lineNumberX = max(0.0, lineNumberBounds.x - lineNumberText.len.float * builder.charWidth)

  if lineNumberText.len > 0:
    let width = builder.textWidth(lineNumberText)
    buildCommands(renderCommands):
      drawText(lineNumberText, rect(offset.x + lineNumberX, offset.y, width, builder.textHeight), textColor, 0.UINodeFlags)

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

  let inclusive = app.config.getOption[:bool]("editor.text.inclusive-selection", false)
  let drawChunks = app.config.getOption[:bool]("editor.text.draw-chunks", false)

  let charWidth = builder.charWidth
  let isThickCursor = self.isThickCursor

  let renderDiff = self.diffDocument.isNotNil and self.diffChanges.isSome

  # ↲ ↩ ⤦ ⤶ ⤸ ⮠
  let showContextLines = not renderDiff and app.config.getOption[:bool]("editor.text.context-lines", true)

  let selectionColor = app.theme.color("selection.background", color(200/255, 200/255, 200/255))
  let cursorForegroundColor = app.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))
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

  let lineNumberPadding = builder.charWidth
  let lineNumberBounds = if lineNumbers != LineNumbers.None:
    vec2(maxLineNumberLen.float32 * builder.charWidth, 0)
  else:
    vec2()

  let lineNumberWidth = if lineNumbers != LineNumbers.None:
    (lineNumberBounds.x + lineNumberPadding).ceil
  else:
    0.0

  var startLine = max(self.previousBaseIndex - (self.scrollOffset / builder.textHeight).int - 1, 0)
  let startLineOffsetFromScrollOffset = (self.previousBaseIndex - startLine).float * builder.textHeight
  var slice = self.document.rope.slice()
  let displayEndPoint = self.displayMap.toDisplayPoint(slice.summary.lines)

  if startLine > displayEndPoint.row.int:
    currentNode.renderCommands.clear()
    selectionsNode.renderCommands.clear()
    return

  let highlight = app.config.asConfigProvider.getValue("ui.highlight", true)

  var iter = DisplayChunkIterator.init(slice, self.displayMap)
  if self.document.tsTree.isNotNil and self.document.highlightQuery.isNotNil and highlight:
    iter.diffChunks.wrapChunks.chunks.highlighter = Highlighter(query: self.document.highlightQuery, tree: self.document.tsTree).some
  iter.seekLine(startLine)

  var diffRopeSlice: RopeSlice[int]
  var diffIter: DisplayChunkIterator
  if renderDiff:
    diffRopeSlice = self.diffDocument.rope.slice()
    diffIter = DisplayChunkIterator.init(diffRopeSlice, self.diffDisplayMap)
    if self.diffDocument.tsTree.isNotNil and self.diffDocument.highlightQuery.isNotNil and highlight:
      diffIter.diffChunks.wrapChunks.chunks.highlighter = Highlighter(query: self.diffDocument.highlightQuery, tree: self.diffDocument.tsTree).some
    diffIter.seekLine(startLine)

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

  let mainOffset = if renderDiff:
    floor(parentWidth * 0.5)
  else:
    0

  type
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

  var state = LineDrawerState(
    builder: builder,
    displayMap: self.displayMap,
    bounds: rect(mainOffset, 0, parentWidth - mainOffset, parentHeight),
    offset: vec2(lineNumberWidth + mainOffset, self.scrollOffset - startLineOffsetFromScrollOffset + (iter.displayPoint.row.int - startLine).float * builder.textHeight),
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
    offset: vec2(lineNumberWidth, self.scrollOffset - startLineOffsetFromScrollOffset + (diffIter.displayPoint.row.int - startLine).float * builder.textHeight),
    lastDisplayPoint: diffIter.displayPoint,
    lastDisplayEndPoint: diffIter.displayPoint,
    lastPoint: diffIter.point,
    cursorOnScreen: false,
    reverse: false,
  )

  currentNode.renderCommands.clear()
  currentNode.renderCommands.spacesColor = commentColor
  buildCommands(currentNode.renderCommands):

    proc drawChunk(chunk: DisplayChunk, state: var LineDrawerState): LineDrawerResult =
      if state.lastPoint.row != chunk.point.row:
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

      state.offset.x += (chunk.displayPoint.column - state.lastDisplayEndPoint.column).float * state.builder.charWidth

      if state.lastPoint.row != chunk.point.row:
        state.lastDisplayPoint.column = 0

      if state.offset.y >= state.bounds.yh:
        return LineDrawerResult.Break

      if state.offset.x >= state.bounds.xw:
        return LineDrawerResult.ContinueNextLine

      state.lastPoint = chunk.point
      state.lastDisplayPoint = chunk.displayPoint
      state.lastDisplayEndPoint = chunk.displayEndPoint

      if not state.addedLineNumber:
        state.addedLineNumber = true
        currentNode.renderCommands.drawLineNumber(state.builder, chunk.point.row.int, vec2(state.bounds.x, state.offset.y), cursorLine, lineNumbers, lineNumberBounds, textColor)

      if chunk.len > 0:
        let layout = self.platform.layoutText($chunk)
        let width = layout.totalBounds.x
        let bounds = rect(state.offset, vec2(width, state.builder.textHeight))
        let charBoundsStart = state.charBounds.len
        state.chunkBounds.add ChunkBounds(
          range: chunk.point...Point(row: chunk.point.row, column: chunk.point.column + chunk.len.uint32),
          bounds: bounds,
          text: chunk.diffChunk.wrapChunk.styledChunk.chunk,
          charsRange: charBoundsStart...(charBoundsStart + layout.len),
        )
        state.charBounds.add layout

        if state.backgroundColor.getSome(color):
          fillRect(bounds, color)

        let textColor = if chunk.scope.len == 0: textColor else: app.theme.tokenColor(chunk.scope, textColor)
        drawText(chunk.toOpenArray, bounds, textColor, &{UINodeFlag.TextDrawSpaces})
        state.offset.x += width
        if sizeToContentY:
          currentNode.h = max(currentNode.h, bounds.yh)

        if drawChunks:
          drawRect(bounds, color(1, 0, 0))

      else:
        # todo: use display points for chunkBounds, or both?
        state.chunkBounds.add ChunkBounds(
          range: chunk.point...Point(row: chunk.point.row, column: chunk.point.column + chunk.len.uint32),
          bounds: rect(state.offset, vec2(state.builder.charWidth, state.builder.textHeight)),
          text: chunk.diffChunk.wrapChunk.styledChunk.chunk,
          charsRange: state.charBounds.len...state.charBounds.len,
        )

        if drawChunks:
          drawRect(rect(state.offset, vec2(state.builder.charWidth, state.builder.textHeight)), color(1, 0, 0))

      return LineDrawerResult.Continue

    while iter.next().getSome(chunk):
      case drawChunk(chunk, state)
      of Continue: discard
      of ContinueNextLine: iter.seekLine(chunk.displayPoint.row.int + 1)
      of Break: break

    if renderDiff:
      startScissor(diffState.bounds)
      while diffIter.next().getSome(chunk):
        case drawChunk(chunk, diffState)
        of Continue: discard
        of ContinueNextLine: diffIter.seekLine(chunk.displayPoint.row.int + 1)
        of Break: break
      endScissor()

    for i, s in self.selections:
      let (found, lastIndex) = state.chunkBounds.binarySearchRange(s.last.toPoint, Bias.Right, cmp)
      if lastIndex in 0..<state.chunkBounds.len and s.last.toPoint in state.chunkBounds[lastIndex].range:
        let chunk = state.chunkBounds[lastIndex]
        # todo: correctly handle multi byte chars
        let relativeOffset = s.last.column - chunk.range.a.column.int
        var cursorBounds = rect(chunk.bounds.xy + vec2(relativeOffset.float * builder.charWidth, 0), vec2(builder.charWidth, builder.textHeight))

        let charBounds = cursorBounds
        if not isThickCursor:
          cursorBounds.w *= 0.2

        if self.cursorVisible:
          fillRect(cursorBounds, cursorForegroundColor)
          if isThickCursor:
            let currentRune = self.document.runeAt(s.last)
            drawText($currentRune, charBounds, cursorBackgroundColor, 0.UINodeFlags)

        self.lastCursorLocationBounds = (cursorBounds + currentNode.boundsAbsolute.xy).some

      if i == self.selections.high:
        let (found, lastIndex) = state.chunkBounds.binarySearchRange(s.last.toPoint, Bias.Left, cmp)
        if lastIndex in 0..<state.chunkBounds.len and s.last.toPoint >= state.chunkBounds[lastIndex].range.a:
          state.cursorOnScreen = true
          self.currentCenterCursor = s.last
          self.currentCenterCursorRelativeYPos = (state.chunkBounds[lastIndex].bounds.y + builder.textHeight * 0.5) / currentNode.bounds.h

  selectionsNode.renderCommands.clear()

  for selections in self.customHighlights.values:
    for s in selections:
      var sn = s.selection.normalized
      let color = app.theme.color(s.color, color(200/255, 200/255, 200/255)) * s.tint
      self.drawHighlight(builder, sn, color, selectionsNode.renderCommands, state.chunkBounds)

  for s in self.selections:
    var sn = s.normalized
    if isThickCursor and inclusive:
      sn.last.column += 1

    self.drawHighlight(builder, sn, selectionColor, selectionsNode.renderCommands, state.chunkBounds)

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
      log lvlError, &"no center point, {index} notin {0..state.chunkBounds.high}"
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

  let useNewRenderer = app.config.getOption[:bool]("ui.new", true)
  let logNewRenderer = app.config.getOption[:bool]("ui.new-log", true)
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
          if not self.disableScrolling and not sizeToContentY:
            let bounds = currentNode.bounds

            if self.targetPoint.getSome(targetPoint):
              let displayPoint = self.displayMap.toDisplayPoint(targetPoint)
              let targetDisplayLine = displayPoint.row.int
              let targetLineY = (targetDisplayLine - self.previousBaseIndex).float32 * builder.textHeight + self.scrollOffset

              let center = case self.nextScrollBehaviour.get(self.defaultScrollBehaviour):
                of CenterAlways: true
                of CenterOffscreen: targetLineY < 0 or targetLineY + builder.textHeight > self.lastContentBounds.h
                of ScrollToMargin: false
                of TopOfScreen: false

              if center:
                self.previousBaseIndex = targetDisplayLine
                self.scrollOffset = bounds.h * self.targetLineRelativeY - builder.textHeight * 0.5

              else:
                case self.nextScrollBehaviour.get(self.defaultScrollBehaviour)
                of TopOfScreen:
                  self.previousBaseIndex = targetDisplayLine
                  self.scrollOffset = 0
                else:
                  let configMarginRelative = app.config.getOption[:bool]("text.cursor-margin-relative", true)
                  let configMargin = app.config.getOption[:float]("text.cursor-margin", 0.2)
                  let margin = if self.targetLineMargin.getSome(margin):
                    clamp(margin, 0.0, bounds.h * 0.5 - builder.textHeight * 0.5)
                  elif configMarginRelative:
                    clamp(configMargin, 0.0, 1.0) * 0.5 * bounds.h
                  else:
                    clamp(configMargin, 0.0, bounds.h * 0.5 - builder.textHeight * 0.5)

                  let oldPreviousBaseIndex = self.previousBaseIndex
                  let oldScrollOffset = self.scrollOffset
                  updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.numDisplayLines, builder.textHeight, targetLine=targetDisplayLine.some, margin=margin)

            else:
              let oldPreviousBaseIndex = self.previousBaseIndex
              let oldScrollOffset = self.scrollOffset
              updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.numDisplayLines, builder.textHeight, targetLine=int.none)

            self.targetPoint = Point.none
            self.nextScrollBehaviour = ScrollBehaviour.none

          var selectionsNode: UINode
          builder.panel(&{UINodeFlag.FillX, FillY}):
            selectionsNode = currentNode
            selectionsNode.renderCommands.clear()

          if useNewRenderer:
            onScroll:
              self.scrollText(delta.y * app.config.asConfigProvider.getValue("text.scroll-speed", 40.0))

            var t = startTimer()

            self.createTextLinesNew(builder, app, currentNode, selectionsNode, backgroundColor, textColor, sizeToContentX, sizeToContentY)

            let e = t.elapsed.ms
            if logNewRenderer:
              debugf"Render new took {e} ms"

          else:
            currentNode.renderCommands.clear()
            var t = startTimer()
            let infos = self.createTextLines(builder, app, backgroundColor, textColor, sizeToContentX, sizeToContentY)
            let e = t.elapsed.ms
            if logNewRenderer:
              debugf"Old new took {e} ms"
            if infos.cursor.getSome(info):
              self.lastCursorLocationBounds = info.bounds.transformRect(info.node, builder.root).some
            if infos.hover.getSome(info):
              self.lastHoverLocationBounds = info.bounds.transformRect(info.node, builder.root).some

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
