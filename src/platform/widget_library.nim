import std/[strformat, strutils]
import document, workspaces/workspace, ui/node
import chroma

template createHeader*(builder: UINodeBuilder, inRenderHeader: bool, inMode: string, inDocument: Document, inHeaderColor: Color, inTextColor: Color, body: untyped): UINode =
  block:
    var leftFunc: proc()
    var rightFunc: proc()

    template left(inBody: untyped) =
      leftFunc = proc() =
        inBody

    template right(inBody: untyped) =
      rightFunc = proc() =
        inBody

    body

    var bar: UINode
    if inRenderHeader:
      builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal}, backgroundColor = inHeaderColor):
        bar = currentNode

        let workspaceName = inDocument.workspace.map(wf => " - " & wf.name).get("")

        let mode = if inMode.len == 0: "normal" else: inMode
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = inTextColor, text = " $# - $# $# " % [mode, inDocument.filename, workspaceName])

        if leftFunc.isNotNil:
          leftFunc()

        builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse}):
          if rightFunc.isNotNil:
            rightFunc()

    else:
      builder.panel(&{FillX}):
        bar = currentNode

    bar

proc createLines*(builder: UINodeBuilder, previousBaseIndex: int, scrollOffset: float, maxLine: int, sizeToContentX: bool, sizeToContentY: bool, backgroundColor: Color, handleScroll: proc(delta: float), handleLine: proc(line: int, y: float, down: bool)) =
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

    if y < height: # fill remaining space with background color
      builder.panel(&{FillX, FillY, FillBackground}, y = y, backgroundColor = backgroundColor)

    y = scrollOffset

    # draw lines upwards
    for i in countdown(previousBaseIndex - 1, 0):
      handleLine(i, y, false)

      y = builder.currentChild.y
      if not sizeToContentY and builder.currentChild.bounds.yh < 0:
        break

    if not sizeToContentY and y > 0: # fill remaining space with background color
      builder.panel(&{FillX, FillBackground}, h = y, backgroundColor = backgroundColor)

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
