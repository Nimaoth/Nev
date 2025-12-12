import std/[strformat, strutils, os]
import misc/[custom_unicode, custom_logger]
import document, ui/node, view, theme, config_provider, widget_builders_base
import chroma
import service

{.push gcsafe.}
{.push raises: [].}
{.push stacktrace:off.}
{.push linetrace:off.}

logCategory "wigdet-library"

type GridAlignment* {.pure.} = enum Left, Center, Right

proc alignGrid*(rows: seq[seq[UINode]], gap: float, columnAlignments: openArray[GridAlignment]) =
  # Align grid
  var maxWidths: seq[float] = @[]
  for row, nodes in rows:
    for col, node in nodes:
      while maxWidths.len <= col:
        maxWidths.add 0
      maxWidths[col] = max(maxWidths[col], node.bounds.w)

  for row, nodes in rows:
    var x = 0.0
    for col, node in nodes:
      let alignment = if col < columnAlignments.len: columnAlignments[col] else: GridAlignment.Left

      case alignment
      of GridAlignment.Left:
        node.rawX = x
      of GridAlignment.Center:
        node.rawX = maxWidths[col] * 0.5 - node.bounds.w * 0.5
      of GridAlignment.Right:
        node.rawX = maxWidths[col] - node.bounds.w

      x += maxWidths[col] + gap
      node.parent.w = max(node.parent.w, node.bounds.xw)

proc alignGrid*(root: UINode, gap: float, columnAlignments: openArray[GridAlignment]) =
  var rows: seq[seq[UINode]]
  for _, row in root.children:
    var l: seq[UINode]
    for _, node in row.children:
      l.add node
    rows.add l
  alignGrid(rows, gap, columnAlignments)

proc renderCommandKeys*(builder: UINodeBuilder, nextPossibleInputs: openArray[tuple[input: string, description: string, continues: bool]], textColor: Color, continuesTextColor: Color, keysTextColor: Color, backgroundColor: Color, inputLines: int, bounds: Rect, padding: int = 1) =
  let height = (inputLines + padding * 2).float * builder.textHeight
  let padding = padding.float
  builder.panel(&{FillX, FillBackground, MaskContent}, y = bounds.h - height, h = height, backgroundColor = backgroundColor):
    builder.panel(&{LayoutHorizontal}, x = builder.charWidth * padding, y = builder.textHeight * padding, w = currentNode.w - builder.charWidth * padding * 2, h = currentNode.h - builder.textHeight * padding * 2):
      var i = 0
      while i < nextPossibleInputs.len:
        if i > 0:
          builder.panel(0.UINodeFlags, w = builder.charWidth * 2)

        var n: UINode
        builder.panel(&{LayoutVertical, SizeToContentX}):
          n = currentNode
          var row = 0
          while i < nextPossibleInputs.len and row < inputLines:
            let (input, desc, continues) = nextPossibleInputs[i]
            builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
              builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = input, textColor = keysTextColor)
              # builder.panel(&{}, w = builder.charWidth * 2)
              if continues:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = desc, textColor = continuesTextColor)
              else:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = desc, textColor = textColor)

            inc row
            inc i

        alignGrid(n, builder.charWidth * 2, [GridAlignment.Right])
        builder.updateSizeToContent(n)

template createHeader*(builder: UINodeBuilder, inRenderHeader: bool, inMode: string,
    inDocument: Document, inHeaderColor: Color, inTextColor: Color, body: untyped): UINode =

  block:
    var leftFunc: proc() {.gcsafe, raises: [].}
    var rightFunc: proc() {.gcsafe, raises: [].}

    template onLeft(inBody: untyped) {.used.} =
      leftFunc = proc() {.gcsafe, raises: [].} =
        inBody

    template onRight(inBody: untyped) {.used.} =
      rightFunc = proc() {.gcsafe, raises: [].} =
        inBody

    body

    var bar: UINode
    if inRenderHeader:
      builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
          backgroundColor = inHeaderColor):

        bar = currentNode

        let isDirty = inDocument.lastSavedRevision != inDocument.revision
        let dirtyMarker = if isDirty: "*" else: ""

        let modeText = if inMode.len == 0: "-" else: inMode
        let (directory, filename) = inDocument.localizedPath.splitPath
        let text = (" $# - $#$# - $# " % [modeText, dirtyMarker, filename, directory]).catch("")
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = inTextColor, text = text)

        if leftFunc.isNotNil:
          leftFunc()

        builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse}):
          if rightFunc.isNotNil:
            rightFunc()

    else:
      builder.panel(&{FillX}):
        bar = currentNode

    bar

proc createLines*(builder: UINodeBuilder, previousBaseIndex: int, scrollOffset: float,
    maxLine: int, maxHeight: Option[float], flags: UINodeFlags, backgroundColor: Color,
    handleScroll: proc(delta: float) {.gcsafe, raises: [].}, handleLine: proc(line: int, y: float, down: bool) {.gcsafe, raises: [].}): UINode =

  let sizeToContentY = SizeToContentY in flags
  builder.panel(flags):
    result = currentNode

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

      if maxHeight.getSome(maxHeight) and builder.currentChild.bounds.y > maxHeight:
        break

    if y < height: # fill remaining space with background color
      builder.panel(&{FillX, FillY, FillBackground}, y = y, backgroundColor = backgroundColor)

    y = scrollOffset

    # draw lines upwards
    for i in countdown(min(previousBaseIndex - 1, maxLine), 0):
      handleLine(i, y, false)

      y = builder.currentChild.y
      if not sizeToContentY and builder.currentChild.bounds.yh < 0:
        break

      if maxHeight.isSome and builder.currentChild.bounds.yh < 0:
        break

    if not sizeToContentY and y > 0: # fill remaining space with background color
      builder.panel(&{FillX, FillBackground}, h = y, backgroundColor = backgroundColor)

proc createLines*(builder: UINodeBuilder, previousBaseIndex: int, scrollOffset: float,
    maxLine: int, sizeToContentX: bool, sizeToContentY: bool, backgroundColor: Color,
    handleScroll: proc(delta: float) {.gcsafe, raises: [].}, handleLine: proc(line: int, y: float, down: bool) {.gcsafe, raises: [].}) =
  var flags = 0.UINodeFlags
  if sizeToContentX:
    flags.incl SizeToContentX
  else:
    flags.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
  else:
    flags.incl FillY

  discard builder.createLines(previousBaseIndex, scrollOffset, maxLine, float.none, flags,
    backgroundColor, handleScroll, handleLine)

proc createLines*(builder: UINodeBuilder, previousBaseIndex: int, scrollOffset: float, maxLine: int, backgroundColor: Color,
    handleScroll: proc(delta: float) {.gcsafe, raises: [].}, handleLine: proc(line: int, y: float, down: bool) {.gcsafe, raises: [].}) =
  let sizeFlags = builder.currentSizeFlags
  discard builder.createLines(previousBaseIndex, scrollOffset, maxLine, float.none, sizeFlags,
    backgroundColor, handleScroll, handleLine)

proc updateBaseIndexAndScrollOffset*(height: float, previousBaseIndex: var int, scrollOffset: var float,
    lines: int, totalLineHeight: float, targetLine: Option[int], margin: float = 0.0) =

  if targetLine.getSome(targetLine):
    let targetLineY = (targetLine - previousBaseIndex).float32 * totalLineHeight + scrollOffset

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

proc createAbbreviatedText*(builder: UINodeBuilder, text: string, oversize: int, ellipsis: string,
    color: Color, flags: UINodeFlags = 0.UINodeFlags) =

  let textFlags = &{DrawText, SizeToContentX, SizeToContentY} + flags
  let partRuneLen = text.runeLen.int
  let cutoutStartRune = max(0, ((partRuneLen - oversize) div 2) - (ellipsis.len div 2) + 1)
  let cutoutStart = text.runeOffset cutoutStartRune.RuneIndex
  let cutoutEnd = text.runeOffset (cutoutStart + oversize + ellipsis.len).RuneIndex

  if cutoutStart > 0:
    builder.panel(textFlags, text = text[0..<cutoutStart], textColor = color)

  builder.panel(textFlags, text = ellipsis, textColor = color.darken(0.2))

  if cutoutEnd < text.len:
    builder.panel(textFlags, text = text[cutoutEnd..^1], textColor = color)

proc createTextWithMaxWidth*(builder: UINodeBuilder, text: string, maxWidth: int, ellipsis: string,
    color: Color, flags: UINodeFlags = 0.UINodeFlags): UINode =

  let oversize = text.runeLen.int - maxWidth
  if oversize > 0:
    builder.panel(&{LayoutHorizontal, SizeToContentX, SizeToContentY}):
      result = currentNode
      builder.createAbbreviatedText(text, oversize, ellipsis, color, flags)
  else:
    let textFlags = &{DrawText, SizeToContentX, SizeToContentY} + flags
    builder.panel(textFlags + flags, text = text, textColor = color):
      result = currentNode

proc highlightedText*(builder: UINodeBuilder, text: string, highlightedIndices: openArray[int],
    color: Color, highlightColor: Color, maxWidth: int = int.high): UINode =
  ## Create a text panel wher the characters at the indices in `highlightedIndices` are highlighted
  ## with `highlightColor`.

  const ellipsis = "..."

  let runeLen = text.runeLen.int

  # How much we're over the limit, gets reduced as we replace text with ...
  var oversize = runeLen - maxWidth

  let textFlags = &{DrawText, SizeToContentX, SizeToContentY}

  if highlightedIndices.len > 0:
    builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}):
      result = currentNode
      var start = 0
      for matchIndex in highlightedIndices:
        if matchIndex >= text.len:
          break

        # Add non highlighted text between last highlight and before next
        if matchIndex > start:
          let partText = text[start..<matchIndex]
          let partOversizeMax = partText.runeLen.int - ellipsis.len
          if oversize > 0 and partOversizeMax > 0:
            let partOversize = min(oversize, partOversizeMax)
            builder.createAbbreviatedText(partText, partOversize, ellipsis, color)
            oversize -= partOversize

          else:
            builder.panel(textFlags, text = partText, textColor = color)

        # Add highlighted text
        builder.panel(textFlags, text = $text.runeAt(matchIndex),
          textColor = highlightColor)

        start = text.nextRuneStart(matchIndex)

      # Add non highlighted part at end of text
      if start < text.len:
        let partText = text[start..^1]
        let partOversizeMax = partText.runeLen.int - ellipsis.len
        if oversize > 0 and partOversizeMax > 0:
          let partOversize = min(oversize, partOversizeMax)
          builder.createAbbreviatedText(partText, partOversize, ellipsis, color)

        else:
          builder.panel(textFlags, text = partText, textColor = color)

  else:
    if oversize > 0:
      builder.panel(&{LayoutHorizontal, SizeToContentX, SizeToContentY}):
        result = currentNode
        builder.createAbbreviatedText(text, oversize, ellipsis, color)

    else:
      builder.panel(textFlags, text = text, textColor = color):
        result = currentNode

proc renderView*(self: View, builder: UINodeBuilder,
    body: proc(): seq[OverlayFunction] {.gcsafe, raises: [].},
    header: proc(): seq[OverlayFunction] {.gcsafe, raises: [].}): seq[OverlayFunction] =
  let services = ({.gcsafe.}: gServices)
  let dirty = self.dirty
  self.resetDirty()

  let config = services.getServiceChecked(ConfigService).runtime
  let uiSettings = UISettings.new(config)

  let transparentBackground = config.get("ui.background.transparent", false)
  let inactiveBrightnessChange = uiSettings.background.inactiveBrightnessChange.get()
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var backgroundColor = if self.active: builder.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)

  if transparentBackground:
    backgroundColor.a = 0
  else:
    backgroundColor.a = 1

  let headerColor = if self.active: builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))

  let sizeFlags = builder.currentSizeFlags

  builder.panel(&{OverlappingChildren} + sizeFlags):
    builder.panel(&{LayoutVertical} + sizeFlags):
      # Header
      builder.panel(&{FillX, SizeToContentY, FillBackground, MaskContent, LayoutHorizontal}, backgroundColor = headerColor):
        result.add header()

      # Body
      builder.panel(sizeFlags + &{FillBackground, MaskContent}, backgroundColor = backgroundColor):
        result.add body()
