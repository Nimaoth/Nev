import std/[strformat, tables, sugar, strutils, json]
import util, app, document_editor, model_document, text/text_document, custom_logger, platform, theme, config_provider, input
import widget_builders_base, widget_library, ui/node, custom_unicode
import vmath, bumpy, chroma
import ast/[types, cells]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_model_document"

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

const cellGenerationBuffer = -10

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
    cell: Cell
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
    remainingHeightDown: float
    remainingHeightUp: float
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
  var noneId = noneUserId
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

  var noneId = noneUserId

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

proc goBackward(self: CellLayoutContext)

proc newCellLayoutContext(parent: CellLayoutContext, cell: Cell, remainingHeightDown, remainingHeightUp: float): CellLayoutContext =
  result = newCellLayoutContext(parent.builder)
  result.parent = parent
  result.remainingHeightDown = remainingHeightDown
  result.remainingHeightUp = remainingHeightUp
  result.cell = cell

  if parent.targetDirection == Backwards:
    result.targetDirection = Backwards

  cell.logc fmt"newCellLayoutContext {remainingHeightDown}, {remainingHeightUp}"

proc currentDirectionData(self: CellLayoutContext): var DirectionData =
  case self.currentDirection
  of Forwards:
    return self.forwardData
  of Backwards:
    return self.backwardData

proc isCurrentLineEmpty(self: CellLayoutContext): bool =
  return self.builder.currentChild == self.currentDirectionData.indentNode

proc updateCurrentIndent(self: CellLayoutContext) =
  if self.hasIndent and self.isCurrentLineEmpty():
    self.currentDirectionData.indentNode.w = self.indentText.len.float * self.currentIndent.float * self.builder.charWidth

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

  self.builder.panel(&{FillY}, w = self.builder.charWidth)

proc newLine(self: CellLayoutContext) =
  inc self.currentLine

  self.builder.finishLine(self.currentDirectionData)
  self.builder.createLineNode(self.currentDirectionData)

  self.hasIndent = false

  self.indent()

proc goBackward(self: CellLayoutContext) =
  if self.currentDirection == Forwards:
    # echo "go backward"
    self.forwardData.saveLastNode(self.builder)
    self.builder.continueFrom(self.backwardData.lineNode, self.backwardData.lastNode)
    self.currentDirection = Backwards
    self.targetDirection = Backwards

proc finish(self: CellLayoutContext) =
  self.currentDirectionData.saveLastNode(self.builder)

  # finish forward
  self.builder.continueFrom(self.forwardData.lineNode, self.forwardData.lastNode)
  self.builder.finishLine(self.forwardData)
  self.builder.finishNode(self.forwardLinesNode)

  # finish backward
  self.builder.continueFrom(self.backwardData.lineNode, self.backwardData.lastNode)
  self.builder.finishLine(self.backwardData)
  self.builder.finishNode(self.parentNode)

  if self.cell.isNotNil:
    self.cell.logc fmt"finish CellLayoutContext {self.remainingHeightDown}, {self.remainingHeightUp}"

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

proc getCursorPos(builder: UINodeBuilder, line: openArray[char], startOffset: RuneIndex, pos: Vec2): int =
  var offsetFromLeft = pos.x / builder.charWidth
  if false: # self.isThickCursor(): # todo
    offsetFromLeft -= 0.0
  else:
    offsetFromLeft += 0.5

  let index = clamp(offsetFromLeft.int, 0, line.runeLen.int)
  let byteIndex = line.runeOffset(startOffset + index.RuneCount)
  return byteIndex

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

  let (text, color) = app.getTextAndColor(cell)
  # builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color):
    updateContext.cellToWidget[cell.id] = currentNode
    onClickAny btn:
      if btn == MouseButton.Left:
        if cell.canSelect:
          let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
          let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
          capture cellPath:
            updateContext.handleClick(currentNode, cell, cellPath, cursor)

    onDrag MouseButton.Left:
      if cell.canSelect:
        let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
        let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
        capture cellPath:
          updateContext.handleClick(currentNode, cell, cellPath, cursor)



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

  let (text, color) = app.getTextAndColor(cell)
  # builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color):
    updateContext.cellToWidget[cell.id] = currentNode
    onClickAny btn:
      if btn == MouseButton.Left:
        if cell.canSelect:
          let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
          let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
          capture cellPath:
            updateContext.handleClick(currentNode, cell, cellPath, cursor)

    onDrag MouseButton.Left:
      if cell.canSelect:
        let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
        let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
        capture cellPath:
          updateContext.handleClick(currentNode, cell, cellPath, cursor)

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

  let (text, color) = app.getTextAndColor(cell)
  # builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color):
    updateContext.cellToWidget[cell.id] = currentNode
    onClickAny btn:
      if btn == MouseButton.Left:
        if cell.canSelect:
          let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
          let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
          capture cellPath:
            updateContext.handleClick(currentNode, cell, cellPath, cursor)

    onDrag MouseButton.Left:
      if cell.canSelect:
        let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
        let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
        capture cellPath:
          updateContext.handleClick(currentNode, cell, cellPath, cursor)

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

  let (text, color) = app.getTextAndColor(cell)
  # builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId):
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color):
    updateContext.cellToWidget[cell.id] = currentNode
    onClickAny btn:
      if btn == MouseButton.Left:
        if cell.canSelect:
          let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
          let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
          capture cellPath:
            updateContext.handleClick(currentNode, cell, cellPath, cursor)

    onDrag MouseButton.Left:
      if cell.canSelect:
        let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
        let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
        capture cellPath:
          updateContext.handleClick(currentNode, cell, cellPath, cursor)

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

  if cell.child.isNil:
    let reference = cell.node.reference(cell.reference)
    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)

    if spaceLeft:
      ctx.addSpace()

    # builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = $reference, textColor = textColor, userId = cell.id.newPrimaryId):
    let text = $reference
    builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = textColor):
      updateContext.cellToWidget[cell.id] = currentNode
      onClickAny btn:
        if btn == MouseButton.Left:
          if cell.canSelect:
            let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
            let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
            capture cellPath:
              updateContext.handleClick(currentNode, cell, cellPath, cursor)

      onDrag MouseButton.Left:
        if cell.canSelect:
          let offset = builder.getCursorPos(text, 0.RuneIndex, pos)
          let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
          capture cellPath:
            updateContext.handleClick(currentNode, cell, cellPath, cursor)

  else:
    cell.child.createCellUI(builder, app, ctx, updateContext, spaceLeft, path)
    updateContext.cellToWidget[cell.id] = builder.currentChild

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

  let parentCtx = ctx
  var ctx = ctx
  var hasContext = false
  if cell.inline and ctx.cell != cell:
    ctx = newCellLayoutContext(ctx, cell, ctx.remainingHeightDown, ctx.remainingHeightUp)
    hasContext = true

  defer:
    if hasContext:
      ctx.finish()
      if parentCtx.targetDirection == Forwards:
        parentCtx.remainingHeightDown -= ctx.parentNode.h
      else:
        parentCtx.remainingHeightUp -= ctx.parentNode.h

  let vertical = LayoutVertical in cell.flags

  updateContext.nodeCellMap.fill(cell)

  let centerIndex = if path.len > 0: path[0].clamp(0, cell.children.high) elif ctx.targetDirection == Direction.Backwards: cell.children.high else: 0

  if cell.children.len == 0:
    return

  if vertical:
    let c = cell.children[centerIndex]
    ctx.newLine()
    if cell.style.isNotNil and cell.style.indentChildren:
      ctx.increaseIndent()
      ctx.indent()

    defer:
      if cell.style.isNotNil and cell.style.indentChildren:
        ctx.decreaseIndent()
        ctx.indent()

    # center
    block:
      # echo "center ", centerIndex
      let myCtx = newCellLayoutContext(ctx, c, ctx.remainingHeightDown, ctx.remainingHeightUp)
      defer:
        myCtx.finish()

        if updateContext.targetNode.isNotNil and path.len > 1:
          let targetBounds = updateContext.targetNode.bounds.transformRect(updateContext.targetNode.parent, myCtx.parentNode)
          # debugf"targetBounds: {targetBounds}, h: {myCtx.parentNode.h}, down: {myCtx.parentNode.h - targetBounds.y}, up: {targetBounds.y}"
          ctx.remainingHeightUp -= targetBounds.y
          ctx.remainingHeightDown -= myCtx.parentNode.h - targetBounds.y
        elif ctx.targetDirection == Direction.Forwards:
          ctx.remainingHeightDown -= myCtx.parentNode.h
        elif ctx.targetDirection == Direction.Backwards:
          ctx.remainingHeightUp -= myCtx.parentNode.h
        else:

          # echo myCtx.parentNode.h, ", ", (ctx.remainingHeightDown - myCtx.remainingHeightDown), ", ", (ctx.remainingHeightUp - myCtx.remainingHeightUp)
          let heightDownChange = ctx.remainingHeightDown - myCtx.remainingHeightDown
          let heightUpChange = ctx.remainingHeightUp - myCtx.remainingHeightUp

          # ctx.remainingHeightDown -= myCtx.parentNode.h - heightUpChange
          # ctx.remainingHeightUp -= myCtx.parentNode.h
          ctx.remainingHeightDown -= heightDownChange
          ctx.remainingHeightUp -= heightUpChange

        if ctx.remainingHeightDown < 0 and ctx.remainingHeightUp < 0:
          cell.logc "1: reached bottom"
          return

      cellPath.add centerIndex
      c.createCellUI(builder, app, myCtx, updateContext, false, if path.len > 1: path[1..^1] else: @[])
      discard cellPath.pop

      if path.len == 1 and updateContext.targetNode.isNil:
        # echo "set target ", cellPath, ", ", path
        updateContext.targetCell = c
        updateContext.targetNode = builder.currentChild

      when defined(uiNodeDebugData):
        if path.len == 1:
          builder.currentChild.aDebugData.css.add "border: 1px solid red;"
          builder.currentChild.aDebugData.metaData["target"] = newJBool(true)

    # forwards
    for i in (centerIndex + 1)..cell.children.high:
      # echo "down ", i
      let c = cell.children[i]
      ctx.newLine()
      if cell.style.isNotNil and cell.style.indentChildren:
        ctx.increaseIndent()
        ctx.indent()


      let myCtx = newCellLayoutContext(ctx, c, ctx.remainingHeightDown, 0)
      defer:
        myCtx.finish()
        # echo myCtx.parentNode.h
        ctx.remainingHeightDown -= myCtx.parentNode.h
        if ctx.remainingHeightDown < 0:
          cell.logc "2: reached bottom"
          break

      cellPath.add i
      c.createCellUI(builder, app, myCtx, updateContext, false, @[])
      discard cellPath.pop

      # builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = fmt"{myCtx.parentNode.h}, {ctx.remainingHeightDown}, {ctx.remainingHeightUp}", textColor = color(0, 1, 0))

    # backwards
    if centerIndex > 0:
      ctx.goBackward()
      for i in countdown(centerIndex - 1, 0):
        # echo "up ", i
        let c = cell.children[i]
        ctx.newLine()
        if cell.style.isNotNil and cell.style.indentChildren:
          ctx.increaseIndent()
          ctx.indent()

        let myCtx = newCellLayoutContext(ctx, c, 0, ctx.remainingHeightUp)
        defer:
          myCtx.finish()
          # echo myCtx.parentNode.h
          ctx.remainingHeightUp -= myCtx.parentNode.h
          if ctx.remainingHeightUp < 0:
            cell.logc "3: reached top"
            break

        cellPath.add i
        c.createCellUI(builder, app, myCtx, updateContext, false, @[])
        discard cellPath.pop

  else:
    for i in 0..cell.children.high:
      let c = cell.children[i]

      var spaceLeft = not ctx.prevNoSpaceRight
      if c.style.isNotNil:
        if c.style.noSpaceLeft:
          spaceLeft = false
        if c.style.onNewLine:
          ctx.newLine()

      cellPath.add i
      c.createCellUI(builder, app, ctx, updateContext, spaceLeft, if i == centerIndex and path.len > 1: path[1..^1] else: @[])
      discard cellPath.pop

      if i == centerIndex and path.len == 1:
        # echo "set target ", cellPath, ", ", path
        when defined(uiNodeDebugData):
          builder.currentChild.aDebugData.css.add "border: 1px solid red;"
          builder.currentChild.aDebugData.metaData["target"] = newJBool(true)

        updateContext.targetCell = c
        updateContext.targetNode = builder.currentChild

      ctx.prevNoSpaceRight = false
      if c.style.isNotNil:
        ctx.prevNoSpaceRight = c.style.noSpaceRight

proc updateTargetPath(updateContext: UpdateContext, root: UINode, cell: Cell, forward: bool, targetPath: openArray[int], currentPath: seq[int]): Option[(float32, seq[int])] =
  if cell of CollectionCell:
    let centerIndex = if targetPath.len > 0: targetPath[0].clamp(0, cell.CollectionCell.children.high) elif forward: 0 else: cell.CollectionCell.children.high
    if forward:
      for i in centerIndex..cell.CollectionCell.children.high:
        let c = cell.CollectionCell.children[i]
        result = updateContext.updateTargetPath(root, c, forward, if targetPath.len > 1: targetPath[1..^1] else: @[], currentPath & @[i])
        if result.isSome:
          return
    else:
      for i in countdown(centerIndex, 0):
        let c = cell.CollectionCell.children[i]
        result = updateContext.updateTargetPath(root, c, forward, if targetPath.len > 1: targetPath[1..^1] else: @[], currentPath & @[i])
        if result.isSome:
          return
  elif updateContext.cellToWidget.contains(cell.id):
    let node = updateContext.cellToWidget[cell.id]
    let bounds = node.bounds.transformRect(node.parent, root)
    # echo "found ", cell.dump, ", ", node.dump, ": ", bounds
    if bounds.y > cellGenerationBuffer and bounds.yh < root.h - cellGenerationBuffer:
      return (bounds.y, currentPath).some

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
    self.cellWidgetContext = UpdateContext(nodeCellMap: self.nodeCellMap)

  self.cellWidgetContext.cellToWidget = initTable[Id, UINode](self.cellWidgetContext.cellToWidget.len)

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId):
    defer:
      self.lastContentBounds = currentNode.bounds

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.currentMode, self.document, headerColor, textColor):
          right:
            builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, pivot = vec2(1, 0), textColor = textColor, text = fmt" {self.id} ")

        var scrollContent: UINode

        let animate = 0.UINodeFlags
        # when defined(js):
        #   let animate = 0.UINodeFlags
        # else:
        #   let animate = if builder.charWidth > 1: &{AnimatePosition} else: 0.UINodeFlags

        builder.panel(&{FillX, FillY, FillBackground, MaskContent, OverlappingChildren}, backgroundColor = backgroundColor):
          onScroll:
            let scrollAmount = delta.y * app.asConfigProvider.getValue("model.scroll-speed", 10.0)
            self.scrollOffset += scrollAmount

            if AnimatePosition in animate:
              scrollContent.boundsActual.y -= scrollAmount

            self.markDirty()

          let overlapPanel = currentNode

          let h = currentNode.h
          builder.panel(&{FillX, FillY} + animate, y = 0, userId = newSecondaryId(self.userId, -1)):
            scrollContent = currentNode

            builder.panel(&{FillX, SizeToContentY}):
              let uiae = currentNode

              defer:
                self.lastBounds = currentNode.bounds

              for node in self.document.model.rootNodes:
                let cell = self.nodeCellMap.cell(node)
                # let cell = self.document.builder.buildCell(self.nodeCellMap, node, self.useDefaultCellBuilder)
                if cell.isNil:
                  continue

                self.cellWidgetContext.targetNode = nil
                self.cellWidgetContext.handleClick = proc(node: UINode, cell: Cell, cellPath: seq[int], cursor: CellCursor) =
                  let bounds = node.bounds.transformRect(node.parent, uiae.parent)
                  targetCellPath = cellPath
                  # debugf"click: {self.scrollOffset} -> {bounds.y} | {cell.dump} | {node.dump}"
                  self.scrollOffset = bounds.y
                  self.cursor = cursor
                  # echo cursor.node
                  self.markDirty()

                # echo self.scrollOffset
                let myCtx = newCellLayoutContext(builder)
                myCtx.remainingHeightUp = self.scrollOffset - cellGenerationBuffer
                myCtx.remainingHeightDown = (h - self.scrollOffset) - cellGenerationBuffer
                cell.createCellUI(builder, app, myCtx, self.cellWidgetContext, false, targetCellPath)
                myCtx.finish()

                if self.cellWidgetContext.targetNodeOld != self.cellWidgetContext.targetNode:
                  if self.cellWidgetContext.targetNodeOld.isNotNil:
                    self.cellWidgetContext.targetNodeOld.contentDirty = true
                  if self.cellWidgetContext.targetNode.isNotNil:
                    self.cellWidgetContext.targetNode.contentDirty = true

                self.cellWidgetContext.targetNodeOld = self.cellWidgetContext.targetNode

                if self.cellWidgetContext.targetNode.isNotNil:
                  var bounds = self.cellWidgetContext.targetNode.bounds.transformRect(self.cellWidgetContext.targetNode.parent, uiae.parent)
                  # echo fmt"1 target node {bounds}: {self.cellWidgetContext.targetNode.dump}"
                  currentNode.rawY = currentNode.boundsRaw.y + (self.scrollOffset - bounds.y)
                  bounds = self.cellWidgetContext.targetNode.bounds.transformRect(self.cellWidgetContext.targetNode.parent, uiae.parent)
                  # echo fmt"2 target node {bounds}: {self.cellWidgetContext.targetNode.dump}"

                if self.scrollOffset < cellGenerationBuffer or self.scrollOffset >= h - cellGenerationBuffer:
                  let forward = self.scrollOffset < cellGenerationBuffer
                  if self.cellWidgetContext.updateTargetPath(currentNode.parent, cell, forward, targetCellPath, @[]).getSome(path):
                    # echo "update path ", path, " (was ", targetCellPath, ")"
                    targetCellPath = path[1]
                    self.scrollOffset = path[0]

          # cursor
          block:
            if self.cursor.getTargetCell(true).getSome(targetCell) and self.cellWidgetContext.cellToWidget.contains(targetCell.id):
              let node = self.cellWidgetContext.cellToWidget[targetCell.id]
              # debugf"cursor {self.cursor} at {targetCell.dump}, {node.dump}"

              let index = self.cursor.lastIndex
              var bounds = rect(index.float * builder.charWidth, 0, 0, 0).transformRect(node, overlapPanel)
              builder.panel(&{UINodeFlag.FillBackground, AnimatePosition}, x = bounds.x, y = bounds.y, w = max(builder.charWidth * 0.2, 1), h = builder.textHeight, backgroundColor = textColor, userId = newPrimaryId(self.cursorsId))

        # echo builder.currentChild.dump(true)

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))