import std/[strformat, tables, sugar, strutils]
import util, app, document_editor, model_document, text/text_document, custom_logger, platform, theme, config_provider, input
import widget_builders_base, widget_library, ui/node
import vmath, bumpy, chroma
import ast/[types, cells]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_model_document"

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

type
  Direction = enum
    Forwards
    Backwards

  DirectionData = object
    lineNode: UINode              # root node of the line
    indentNode: UINode            #   node which contains the indent
    lastNode: UINode              # the last node which was created inside lineNode
    pivot: Vec2

  CellLayoutContext = ref object
    parent: CellLayoutContext
    builder: UINodeBuilder
    currentLine: int
    currentIndent: int
    parentNode: UINode
    forwardLinesNode: UINode
    forwardData: DirectionData
    backwardData: DirectionData
    hasIndent: bool
    prevNoSpaceRight: bool
    layoutOptions: WLayoutOptions
    indentText: string
    remainingHeight: float
    currentDirection = Direction.Forwards # Which line direction data we're currently using
    targetDirection = Direction.Forwards # Whether we want to generate cells forwards or backwards
    pivot: Vec2
    onFirstForwardLine = true

var stackSize = 0
var cellPath = newSeq[int]()
var targetCellPath = @[0, 0]
template logc(node: untyped, msg: varargs[string, `$`]) =
  if false:
    var uiae = ""
    for c in msg:
      uiae.add $c
    let xvlc: string = dump(node, false)
    echo "| ".repeat(stackSize), " (", cellPath, "): ", uiae, "    | ", xvlc, ""

proc createLineNode(builder: UINodeBuilder, self: var DirectionData) =
  var noneId = noneUserId()
  self.lineNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutHorizontal}, string.none, float32.none, float32.none, float32.none, float32.none, self.pivot.some, noneId, UINodeFlags.none)
  builder.panel(&{FillY}, textColor = color(0, 1, 0)):
    self.indentNode = currentNode
    self.lastNode = currentNode

proc saveLastNode(self: var DirectionData, builder: UINodeBuilder) =
  assert builder.currentChild.parent == self.lineNode
  assert builder.currentParent == self.lineNode
  self.lastNode = builder.currentChild

proc finishLine(builder: UINodeBuilder, data: var DirectionData) =
  builder.finishNode(data.lineNode)

proc newCellLayoutContext(builder: UINodeBuilder): CellLayoutContext =
  new result

  var noneId = noneUserId()

  result.forwardData.pivot = vec2(0, 0)
  result.backwardData.pivot = vec2(0, 1)

  result.builder = builder
  result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVerticalReverse}, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
  # result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVertical}, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
  result.forwardLinesNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVertical}, string.none, float32.none, float32.none, float32.none, float32.none, vec2(0, 1).some, noneId, UINodeFlags.none)
  result.builder.createLineNode(result.forwardData)

  result.builder.continueFrom(result.parentNode, result.forwardLinesNode)
  result.builder.createLineNode(result.backwardData)

  result.builder.continueFrom(result.forwardData.lineNode, result.forwardData.lastNode)

  result.indentText = "··"

proc newCellLayoutContext(parent: CellLayoutContext): CellLayoutContext =
  result = newCellLayoutContext(parent.builder)
  result.parent = parent

proc currentDirectionData(self: CellLayoutContext): var DirectionData =
  case self.currentDirection
  of Forwards:
    return self.forwardData
  of Backwards:
    return self.backwardData

proc isCurrentLineEmpty(self: CellLayoutContext): bool =
  return self.builder.currentChild == self.currentDirectionData.indentNode

  # if self.builder.currentParent == self.currentDirectionData.lineForwardNode:
  #   return self.currentDirectionData.lastLineBackwardNode == self.currentDirectionData.lineForwardNode and self.builder.currentChild.isNil
  # elif self.builder.currentParent == self.currentDirectionData.lineBackwardNode:
  #   return self.currentDirectionData.lineForwardNode == self.builder.currentChild and self.currentDirectionData.lastLineForwardNode.isNil
  # else:
  #   assert false
  #   return self.currentDirectionData.lastLineBackwardNode == self.currentDirectionData.lineForwardNode and self.currentDirectionData.lastLineForwardNode.isNil

proc updateCurrentIndent(self: CellLayoutContext) =
  if self.hasIndent and self.isCurrentLineEmpty():
    # let size = self.layoutOptions.getTextBounds self.indentText.repeat(self.currentIndent)
    self.currentDirectionData.indentNode.w = self.indentText.len.float * self.currentIndent.float * self.builder.charWidth
    # self.currentDirectionData.indentNode.text = self.indentText.repeat(self.currentIndent)

proc increaseIndent(self: CellLayoutContext) =
  inc self.currentIndent
  self.updateCurrentIndent()

proc decreaseIndent(self: CellLayoutContext) =
  if self.currentIndent == 0:
    return
  dec self.currentIndent
  self.updateCurrentIndent()

proc indent(self: CellLayoutContext) =
  if self.currentIndent == 0:
    return

  self.hasIndent = true
  self.updateCurrentIndent()

proc addSpace(self: CellLayoutContext) =
  if self.isCurrentLineEmpty:
    return

  # let size = self.layoutOptions.getTextBounds " "
  self.builder.panel(&{FillY}, w = self.builder.charWidth)

proc newLine(self: CellLayoutContext) =
  inc self.currentLine
  # debugf "new line {self.currentLine}, {self.currentDirection}, {self.targetDirection}"

  # self.currentDirectionData.saveLastNode(self.builder)

  self.builder.finishLine(self.currentDirectionData)
  self.builder.createLineNode(self.currentDirectionData)

  self.hasIndent = false

  self.indent()

proc goForward(self: CellLayoutContext) =
  if self.targetDirection == Backwards:
    echo "go forward"
    # self.currentDirectionData.saveLastNode(self.builder)
    # self.builder.continueFrom(self.forwardData.lineForwardNode, self.forwardData.lastLineForwardNode)
    # self.targetDirection = Forwards
    # self.currentDirection = Forwards
    # self.forwardData.currentDirection = Forwards
    # self.forwardData.pivot = vec2(0, 0)

proc goBackward(self: CellLayoutContext) =
  if self.targetDirection == Forwards:
    echo "go backward"

    # self.currentDirectionData.saveLastNode(self.builder)

    # if self.onFirstForwardLine:
    #   self.builder.continueFrom(self.forwardData.lineBackwardNode, self.forwardData.lastLineBackwardNode)
    #   self.currentDirection = Forwards
    #   self.forwardData.pivot = vec2(1, 0)
    # else:
    #   self.builder.continueFrom(self.backwardData.lineBackwardNode, self.backwardData.lastLineBackwardNode)
    #   self.currentDirection = Backwards
    #   self.backwardData.pivot = vec2(1, 0)

    self.forwardData.saveLastNode(self.builder)
    self.builder.continueFrom(self.backwardData.lineNode, self.backwardData.lastNode)
    self.targetDirection = Backwards
    self.currentDirection = Backwards

proc finish(self: CellLayoutContext) =
  # self.currentParent.logp ""

  self.currentDirectionData.saveLastNode(self.builder)

  # finish forward
  self.builder.continueFrom(self.forwardData.lineNode, self.forwardData.lastNode)
  self.builder.finishLine(self.forwardData)
  self.builder.finishNode(self.forwardLinesNode)

  # finish backward
  self.builder.continueFrom(self.backwardData.lineNode, self.backwardData.lastNode)
  self.builder.finishLine(self.backwardData)
  self.builder.finishNode(self.parentNode)

proc getTextAndColor(app: App, cell: Cell, defaultShadowText: string = ""): (string, Color) =
  if cell.currentText.len == 0:
    let text = if cell.shadowText.len == 0:
      defaultShadowText
    else:
      cell.shadowText
    let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255)).withAlpha(0.7)
    return (text, textColor)
  else:
    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)
    return (cell.currentText, textColor)

proc createCompletions(self: ModelDocumentEditor, builder: UINodeBuilder, app: App, cursorBounds: Rect) =
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
  const docsWidth = 0.0
  let totalWidth = charWidth * listWidth + charWidth * docsWidth
  var clampedX = cursorBounds.x
  if clampedX + totalWidth > builder.root.w:
    clampedX = max(builder.root.w - totalWidth, 0)

  updateBaseIndexAndScrollOffset(bottom - top, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  # self.lastCompletionWidgets.setLen 0

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

        case completion.kind
        of ModelCompletionKind.SubstituteClass:
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = completion.name, textColor = nameColor)

        of ModelCompletionKind.SubstituteReference:
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = completion.name, textColor = nameColor)

          let className = if completion.class.alias.len > 0: completion.class.alias else: completion.class.name
          builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, x = currentNode.w, pivot = vec2(1, 0), text = className, textColor = scopeColor)

    builder.panel(&{UINodeFlag.MaskContent}, w = listWidth * charWidth, h = bottom - top):
      builder.createLines(self.completionsBaseIndex, self.completionsScrollOffset, self.completions.high, false, false, backgroundColor, handleScroll, handleLine)

    # builder.panel(&{UINodeFlag.FillBackground, DrawText, MaskContent, TextWrap},
    #   x = listWidth * charWidth, w = docsWidth * charWidth, h = bottom - top,
    #   backgroundColor = backgroundColor, textColor = docsColor, text = self.completions[self.selectedCompletion].doc)

  if completionsPanel.bounds.yh > completionsPanel.parent.bounds.h:
    completionsPanel.rawY = cursorBounds.y
    completionsPanel.pivot = vec2(0, 1)

proc updateTargetCellPath(cellPath: openArray[int]) =
  # echo cellPath
  targetCellPath = @cellPath

method createCellUI*(cell: Cell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) {.base.} = discard

method createCellUI*(cell: ConstantCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  let cellPath = cellPath

  stackSize.inc
  defer:
    stackSize.dec

  cell.logc fmt"createCellUI (ConstantCell) {path}"

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
    onClick MouseButton.Left:
      capture cellPath:
        updateTargetCellPath(cellPath)
        app.platform.requestRender(true)

  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: PlaceholderCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  let cellPath = cellPath

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}"

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
    onClick MouseButton.Left:
      capture cellPath:
        updateTargetCellPath(cellPath)
        app.platform.requestRender(true)
  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: AliasCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  let cellPath = cellPath

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}"

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
    onClick MouseButton.Left:
      capture cellPath:
        updateTargetCellPath(cellPath)
        app.platform.requestRender(true)

  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: NodeReferenceCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  let cellPath = cellPath

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}"

  # updateContext.cellToWidget[cell.id] = widget
  if cell.child.isNil:
    let reference = cell.node.reference(cell.reference)
    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)

    if spaceLeft:
      ctx.addSpace()

    builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = $reference, textColor = textColor, userId = cell.id.newPrimaryId):
      onClick MouseButton.Left:
        capture cellPath:
          updateTargetCellPath(cellPath)
          app.platform.requestRender(true)


    # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent

  else:
    cell.child.createCellUI(builder, app, ctx, updateContext, spaceLeft, path)

  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: PropertyCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  let cellPath = cellPath

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}"

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
    onClick MouseButton.Left:
      capture cellPath:
        updateTargetCellPath(cellPath)
        app.platform.requestRender(true)

  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: CollectionCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    cell.logc fmt"createCellUI end (CollectionCell) {path}"
    stackSize.dec
  cell.logc fmt"createCellUI begin (CollectionCell) {path}"

  # updateContext.cellToWidget[cell.id] = myCtx.parentWidget

  # myCtx.layoutOptions = app.platform.layoutOptions

  let vertical = LayoutVertical in cell.flags

  cell.fill()

  let centerIndex = if path.len > 0: path[0].clamp(0, cell.children.high) elif ctx.targetDirection == Direction.Backwards: cell.children.high else: 0

  if cell.children.len == 0:
    return

  if vertical:
    # echo "center ", centerIndex
    let c = cell.children[centerIndex]
    cellPath.add centerIndex
    ctx.newLine()
    if cell.style.isNotNil and cell.style.indentChildren:
      ctx.increaseIndent()
      ctx.indent()

    defer:
      if cell.style.isNotNil and cell.style.indentChildren:
        ctx.decreaseIndent()
        ctx.indent()

    block:
      let myCtx = newCellLayoutContext(ctx)
      defer:
        myCtx.finish()
      c.createCellUI(builder, app, myCtx, updateContext, false, if path.len > 1: path[1..^1] else: @[0])
      discard cellPath.pop

    for i in (centerIndex + 1)..cell.children.high:
      # echo "down ", i
      let c = cell.children[i]
      cellPath.add i
      ctx.newLine()
      if cell.style.isNotNil and cell.style.indentChildren:
        ctx.increaseIndent()
        ctx.indent()

      let myCtx = newCellLayoutContext(ctx)
      defer:
        myCtx.finish()
      c.createCellUI(builder, app, myCtx, updateContext, false, @[0])
      discard cellPath.pop

    if centerIndex > 0:
      ctx.goBackward()
      for i in countdown(centerIndex - 1, 0):
        echo "up ", i
        let c = cell.children[i]
        cellPath.add i
        ctx.newLine()
        if cell.style.isNotNil and cell.style.indentChildren:
          ctx.increaseIndent()
          ctx.indent()

        let myCtx = newCellLayoutContext(ctx)
        defer:
          myCtx.finish()
        c.createCellUI(builder, app, myCtx, updateContext, false, @[0])
        discard cellPath.pop

  else:
    for i in 0..cell.children.high:
      let c = cell.children[i]

      var spaceLeft = not ctx.prevNoSpaceRight
      if c.style.isNotNil:
        if c.style.noSpaceLeft:
          spaceLeft = false


      cellPath.add i
      c.createCellUI(builder, app, ctx, updateContext, spaceLeft, if i == centerIndex and path.len > 1: path[1..^1] else: @[0])
      discard cellPath.pop

      ctx.prevNoSpaceRight = false
      if c.style.isNotNil:
        ctx.prevNoSpaceRight = c.style.noSpaceRight


  # if not vertical:
  #   for i in 0..cell.children.high:
  #     let c = cell.children[i]

  #     cellPath.add i
  #     const empty: array[0, int] = []
  #     c.createCellUI(builder, app, myCtx, updateContext, false, if path.len > 1 and i == centerIndex: path[1..^1] else: empty[0..^1])
  #     discard cellPath.pop

  # if cell.style.isNotNil and cell.style.indentChildren:
  #   myCtx.increaseIndent()
  #   myCtx.indent()

  # defer:
  #   if cell.style.isNotNil and cell.style.indentChildren:
  #     myCtx.decreaseIndent()

  # if cell.children.len > 0:
  #   echo "center ", centerIndex
  #   cellPath.add centerIndex
  #   const empty = [0]
  #   cell.children[centerIndex].createCellUI(builder, app, myCtx, updateContext, false, if path.len > 1: path[1..^1] else: empty[0..0])
  #   discard cellPath.pop

  # if ctx.targetDirection == Direction.Backwards:
  #   # myCtx.goBackward()
  #   echo centerIndex, "..0"

  #   for i in countdown(centerIndex, 0):
  #     let c = cell.children[i]
  #     if vertical and (i > 0 or not myCtx.isCurrentLineEmpty()):
  #       myCtx.newLine()

  #     if c.style.isNotNil:
  #       if c.style.addNewlineAfter:
  #         myCtx.newLine()

  #     cellPath.add i
  #     # let empty = if c of CollectionCell: [c.CollectionCell.children.len] else: [0]
  #     # c.createCellUI(builder, app, myCtx, updateContext, spaceLeft, empty)
  #     const empty: array[0, int] = []
  #     c.createCellUI(builder, app, myCtx, updateContext, spaceLeft, if path.len > 1 and i == centerIndex: path[1..^1] else: empty[0..^1])
  #     discard cellPath.pop

  #     if c.style.isNotNil:
  #       if c.style.onNewLine and not myCtx.isCurrentLineEmpty():
  #         myCtx.newLine()

  #     cell.logc myCtx.parentNode.h

  # echo myCtx.parentNode.h

  # # if centerIndex < cell.children.high and true:
  # if myCtx.targetDirection == Direction.Forwards:
  #   # myCtx.goForward()
  #   echo centerIndex, "..", cell.children.high

  #   for i in (centerIndex)..cell.children.high:
  #     if myCtx.parentNode.h > myCtx.remainingHeight:
  #       break

  #     if i == centerIndex and path.len == 1:
  #       debugf"ignore center index"
  #       continue

  #     let c = cell.children[i]
  #     if c.increaseIndentBefore:
  #       myCtx.increaseIndent()

  #     if c.decreaseIndentBefore:
  #       myCtx.decreaseIndent()

  #     if vertical and (i > 0 or not myCtx.isCurrentLineEmpty()):
  #       myCtx.newLine()

  #     var spaceLeft = not myCtx.prevNoSpaceRight
  #     if c.style.isNotNil:
  #       if c.style.onNewLine and not myCtx.isCurrentLineEmpty():
  #         myCtx.newLine()
  #       if c.style.noSpaceLeft:
  #         spaceLeft = false

  #     cellPath.add i
  #     const empty: array[0, int] = []
  #     c.createCellUI(builder, app, myCtx, updateContext, spaceLeft, if path.len > 1 and i == centerIndex: path[1..^1] else: empty[0..^1])
  #     discard cellPath.pop

  #     if c.increaseIndentAfter:
  #       myCtx.increaseIndent()

  #     if c.decreaseIndentAfter:
  #       myCtx.decreaseIndent()

  #     myCtx.prevNoSpaceRight = false
  #     if c.style.isNotNil:
  #       if c.style.addNewlineAfter:
  #         myCtx.newLine()
  #       myCtx.prevNoSpaceRight = c.style.noSpaceRight

method createUI*(self: ModelDocumentEditor, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
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

  if self.cellWidgetContext.isNil:
    self.cellWidgetContext = UpdateContext()
  # todo
  # self.cellWidgetContext.cellToWidget = initTable[Id, WWidget](self.cellWidgetContext.cellToWidget.len)

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId):
    # if not self.disableScrolling and not sizeToContentY:
    #   updateBaseIndexAndScrollOffset(currentNode.bounds.h, self.previousBaseIndex, self.scrollOffset, self.document.lines.len, builder.textHeight, int.none)

    defer:
      self.lastContentBounds = currentNode.bounds

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.currentMode, self.document, headerColor, textColor):
          right:
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, pivot = vec2(1, 0), textColor = textColor, text = fmt" {self.id} ")
        # if self.createTextLines(builder, app, backgroundColor, textColor, sizeToContentX, sizeToContentY).getSome(info):
        #   self.lastCursorLocationBounds = info.bounds.transformRect(info.node, builder.root).some

        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = backgroundColor):
          onScroll:
            let scrollAmount = delta.y * app.asConfigProvider.getValue("text.scroll-speed", 40.0)
            self.scrollOffset += scrollAmount
            self.markDirty()

          let h = currentNode.h
          builder.panel(&{FillX, FillBackground}, y = h / 10 + self.scrollOffset, h = h - h / 5 - self.scrollOffset, backgroundColor = backgroundColor.lighten(0.1)):

            var i = 0
            for node in self.document.model.rootNodes:
              # if not self.nodeToCell.contains(node.id):
              #   self.rebuildCells()

              # if not self.nodeToCell.contains(node.id):
              #   continue

              # let cell = builder.buildCell(node)
              # let cell = self.nodeToCell[node.id]

              let cell = self.document.builder.buildCell(node, self.useDefaultCellBuilder)
              if cell.isNil:
                continue
              # echo cell.dump(true)

              let myCtx = newCellLayoutContext(builder)
              myCtx.remainingHeight = h
              cell.createCellUI(builder, app, myCtx, self.cellWidgetContext, false, targetCellPath)
              # cell.createCellUI(builder, app, myCtx, self.cellWidgetContext, false, [0, 2, 2])
              myCtx.finish()

              debugf"render from {targetCellPath}"

              inc i

            defer:
              self.lastBounds = currentNode.bounds

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))