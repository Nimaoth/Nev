import std/[strformat, tables, sugar, strutils, json]
import util, app, document_editor, model_document, text/text_document, custom_logger, platform, theme, config_provider, input
import widget_builders_base, widget_library, ui/node, custom_unicode
import vmath, bumpy, chroma
import ast/[types, cells]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_model_document"

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

const cellGenerationBuffer = -15

type
  Direction = enum
    Center
    Forwards
    Backwards

  DirectionData = object
    lineNode: UINode              # root node of the line
    indentNode: UINode            #   node which contains the indent
    lastNode: UINode              # the last node which was created inside lineNode
    pivot: Vec2
    lastCell: Cell

  CellLayoutContext = ref object
    parent: CellLayoutContext
    builder: UINodeBuilder
    updateContext: UpdateContext
    cell: Cell
    currentIndent: int
    parentNode: UINode
    forwardLinesNode: UINode
    forwardData: DirectionData
    backwardData: DirectionData
    hasIndent: bool
    prevNoSpaceRight: bool
    indentText: string
    remainingHeightDown: float
    remainingHeightUp: float
    currentDirection = Direction.Center # Which line direction data we're currently using
    targetDirection = Direction.Center # Whether we want to generate cells forwards or backwards
    pivot: Vec2

var stackSize = 0
var cellPath = newSeq[int]()
template logc(node: untyped, msg: varargs[string, `$`]) =
  if false:
    var uiae = ""
    for c in msg:
      uiae.add $c
    let xvlc: string = dump(node, false)
    echo "| ".repeat(stackSize), " (", cellPath, "): ", uiae, "    | ", xvlc, ""

proc createLineNode(builder: UINodeBuilder, self: var DirectionData) =
  var noneId = noneUserId
  self.lineNode = builder.prepareNode(&{SizeToContentX, FillX, SizeToContentY, LayoutHorizontal}, string.none, float32.none, float32.none, float32.none, float32.none, self.pivot.some, noneId, UINodeFlags.none)

proc saveLastNode(self: var DirectionData, builder: UINodeBuilder) =
  assert builder.currentChild.parent == self.lineNode
  assert builder.currentParent == self.lineNode
  self.lastNode = builder.currentChild

proc finishLine(builder: UINodeBuilder, updateContext: UpdateContext, data: var DirectionData) =
  let lastCell = data.lastCell

  if lastCell.isNotNil:
    builder.panel(&{FillX, FillY}):
      onClickAny btn:
        if btn == MouseButton.Left:
          let cursor = updateContext.nodeCellMap.toCursor(lastCell, int.high)
          updateContext.handleClick(nil, nil, @[], cursor, false)

      onDrag MouseButton.Left:
        let cursor = updateContext.nodeCellMap.toCursor(lastCell, int.high)
        updateContext.handleClick(nil, nil, @[], cursor, true)

  builder.finishNode(data.lineNode)

proc newCellLayoutContext(builder: UINodeBuilder, updateContext: UpdateContext, requiredDirection: Direction, fillX: bool): CellLayoutContext =
  new result

  var noneId = noneUserId

  result.forwardData.pivot = vec2(0, 0)
  result.backwardData.pivot = vec2(0, 1)

  result.builder = builder
  result.updateContext = updateContext

  let fillXFlag = if fillX: &{FillX} else: 0.UINodeFlags

  case requiredDirection
  of Center:
    result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVerticalReverse} + fillXFlag, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
    result.forwardLinesNode = builder.prepareNode(&{SizeToContentX, FillX, SizeToContentY, LayoutVertical}, string.none, float32.none, float32.none, float32.none, float32.none, vec2(0, 1).some, noneId, UINodeFlags.none)
    result.builder.createLineNode(result.forwardData)

    result.builder.continueFrom(result.parentNode, result.forwardLinesNode)
    result.builder.createLineNode(result.backwardData)

    result.builder.continueFrom(result.forwardData.lineNode, result.forwardData.lastNode)
  of Forwards:
    result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVertical} + fillXFlag, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
    result.builder.createLineNode(result.forwardData)
    result.currentDirection = Forwards
  of Backwards:
    result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVerticalReverse} + fillXFlag, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
    result.builder.createLineNode(result.backwardData)
    result.currentDirection = Backwards

  result.indentText = "··"

proc goBackward(self: CellLayoutContext)

proc newCellLayoutContext(parent: CellLayoutContext, cell: Cell, remainingHeightDown, remainingHeightUp: float, fillX: bool): CellLayoutContext =
  let requiredDirection = if cell of CollectionCell and LayoutVertical notin cell.CollectionCell.flags:
    Direction.Forwards
  else:
    parent.targetDirection

  result = newCellLayoutContext(parent.builder, parent.updateContext, requiredDirection, fillX)
  result.parent = parent
  result.remainingHeightDown = remainingHeightDown
  result.remainingHeightUp = remainingHeightUp
  result.cell = cell

  result.targetDirection = parent.targetDirection

  cell.logc fmt"newCellLayoutContext {remainingHeightDown}, {remainingHeightUp}"

proc currentDirectionData(self: CellLayoutContext): var DirectionData =
  case self.currentDirection
  of Center:
    assert self.forwardData.lineNode.isNotNil
    return self.forwardData
  of Forwards:
    assert self.forwardData.lineNode.isNotNil
    return self.forwardData
  of Backwards:
    assert self.backwardData.lineNode.isNotNil
    return self.backwardData

proc isCurrentLineEmpty(self: CellLayoutContext): bool =
  return self.builder.currentChild == self.currentDirectionData.indentNode

proc findNodeContainingMinX(node: UINode, pos: Vec2, predicate: proc(node: UINode): bool): Option[UINode] =
  result = UINode.none
  if pos.x > node.lx + node.lw or pos.y < node.ly or pos.y > node.ly + node.lh:
    return

  if node.first.isNil: # has no children
    if predicate.isNotNil and not predicate(node):
      return

    return node.some

  else: # has children
    var minX = float.high
    var minNode: UINode = nil
    for c in node.rchildren:
      if c.findNodeContainingMinX(pos, predicate).getSome(res):
        if res.lx < minX:
          minX = res.lx
          minNode = res

    if minNode.isNotNil:
      return minNode.some

    if predicate.isNotNil and predicate(node):
      return node.some

proc handleIndentClickOrDrag(builder: UINodeBuilder, btn: MouseButton, modifiers: Modifiers, currentNode: UINode, drag: bool, pos: Vec2) =
  if currentNode.next.isNotNil:
    let posAbs = rect(pos, vec2()).transformRect(currentNode, builder.root).xy
    let targetNode = currentNode.next.findNodeContainingMinX(posAbs, (node) => node.handlePressed.isNotNil)
    if targetNode.getSome(node):
      if drag:
        discard node.handleDrag()(node, btn, modifiers, posAbs - node.boundsAbsolute.xy, vec2())
      else:
        discard node.handlePressed()(node, btn, modifiers, posAbs - node.boundsAbsolute.xy)

proc updateCurrentIndent(self: CellLayoutContext) =
  if self.isCurrentLineEmpty():
    if self.currentDirectionData.indentNode.isNil:
      self.builder.panel(&{FillY}, textColor = color(0, 1, 0)):
        self.currentDirectionData.indentNode = currentNode
        self.currentDirectionData.lastNode = currentNode

        onClickAny btn:
          if btn == MouseButton.Left:
            handleIndentClickOrDrag(self.builder, btn, modifiers, currentNode, false, pos)

        onDrag MouseButton.Left:
          handleIndentClickOrDrag(self.builder, btn, modifiers, currentNode, true, pos)

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

proc notifyCellCreated(self: CellLayoutContext, cell: Cell) =
  self.currentDirectionData.lastCell = cell

proc handleSpaceClickOrDrag(builder: UINodeBuilder, updateContext: UpdateContext, node: UINode, lastCell: Cell, cell: Cell, cellPath: seq[int], drag: bool, pos: Vec2) =
  let cursor = if pos.x <= builder.charWidth * 0.5 and lastCell.isNotNil and lastCell.canSelect:
    updateContext.nodeCellMap.toCursor(lastCell, int.high)
  elif cell.canSelect:
    updateContext.nodeCellMap.toCursor(cell, -1)
  else:
    return

  updateContext.handleClick(node, cell, cellPath, cursor, drag)

proc addSpace(self: CellLayoutContext, cell: Cell, updateContext: UpdateContext) =
  if self.isCurrentLineEmpty:
    return

  let cellPath = cellPath
  let builder = self.builder
  let lastCell = self.currentDirectionData.lastCell

  self.builder.panel(&{FillY}, w = self.builder.charWidth):
    onClickAny btn:
      if btn == MouseButton.Left:
        handleSpaceClickOrDrag(builder, updateContext, currentNode, lastCell, cell, cellPath, false, pos)

    onDrag MouseButton.Left:
      handleSpaceClickOrDrag(builder, updateContext, currentNode, lastCell, cell, cellPath, true, pos)

proc addSpace(self: CellLayoutContext, cell: Cell, updateContext: UpdateContext, color: Color) =
  if self.isCurrentLineEmpty:
    return

  let cellPath = cellPath
  let builder = self.builder
  let lastCell = self.currentDirectionData.lastCell

  self.builder.panel(&{FillY, FillBackground}, w = self.builder.charWidth, backgroundColor = color):
    onClickAny btn:
      if btn == MouseButton.Left:
        handleSpaceClickOrDrag(builder, updateContext, currentNode, lastCell, cell, cellPath, false, pos)

    onDrag MouseButton.Left:
      handleSpaceClickOrDrag(builder, updateContext, currentNode, lastCell, cell, cellPath, true, pos)

proc newLine(self: CellLayoutContext) =
  self.builder.finishLine(self.updateContext, self.currentDirectionData)
  self.builder.createLineNode(self.currentDirectionData)

  self.hasIndent = false

  self.indent()

proc goBackward(self: CellLayoutContext) =
  if self.currentDirection != Backwards:
    # echo "go backward"
    if self.forwardData.lineNode.isNotNil:
      self.forwardData.saveLastNode(self.builder)
    assert self.backwardData.lineNode.isNotNil
    self.builder.continueFrom(self.backwardData.lineNode, self.backwardData.lastNode)
    self.currentDirection = Backwards
    self.targetDirection = Backwards

proc finish(self: CellLayoutContext) =
  self.currentDirectionData.saveLastNode(self.builder)

  # finish forward
  if self.forwardData.lineNode.isNotNil:
    self.builder.continueFrom(self.forwardData.lineNode, self.forwardData.lastNode)
    self.builder.finishLine(self.updateContext, self.forwardData)

  if self.forwardLinesNode.isNotNil:
    self.builder.finishNode(self.forwardLinesNode)

  # finish backward
  if self.backwardData.lineNode.isNotNil:
    self.builder.continueFrom(self.backwardData.lineNode, self.backwardData.lastNode)
    self.builder.finishLine(self.updateContext, self.backwardData)

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
  # let docsColor = app.theme.color("editor.foreground", color(1, 1, 1))
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

proc getCursorPos(builder: UINodeBuilder, line: openArray[char], startOffset: RuneIndex, pos: Vec2, isThickCursor: bool): int =
  var offsetFromLeft = pos.x / builder.charWidth
  if isThickCursor:
    offsetFromLeft -= 0.0
  else:
    offsetFromLeft += 0.5

  let index = clamp(offsetFromLeft.int, 0, line.runeLen.int)
  let byteIndex = line.runeOffset(startOffset + index.RuneCount)
  return byteIndex

proc createLeafCellUI*(cell: Cell, builder: UINodeBuilder, inText: string, inTextColor: Color, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, cursorFirst: openArray[int], cursorLast: openArray[int]) =
  var selectionStart = 0
  var selectionEnd = 0
  var spaceSelected = false

  var backgroundFlags = 0.UINodeFlags
  var backgroundColor = color(0, 0, 0)
  if cursorFirst.len == 1 and cursorLast.len == 1:
    let first = cursorFirst[0]
    let last = cursorLast[0]
    if first <= 0 and last >= inText.len:
      backgroundColor = updateContext.selectionColor
      backgroundFlags.incl FillBackground
      # cell.logc fmt"full selection {selectionStart}, {selectionEnd}"
    else:
      selectionStart = first.clamp(0, inText.len)
      selectionEnd = last.clamp(0, inText.len)

    if first < 0 and last >= 0:
      spaceSelected = true

  defer:
    ctx.notifyCellCreated(cell)

  if spaceLeft:
    if spaceSelected:
      ctx.addSpace(cell, updateContext, updateContext.selectionColor)
    else:
      ctx.addSpace(cell, updateContext)

  if selectionStart == selectionEnd:
    builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText} + backgroundFlags, text = inText, textColor = inTextColor, backgroundColor = backgroundColor):
      updateContext.cellToWidget[cell.id] = currentNode
      currentNode.userData = cell
      onClickAny btn:
        if btn == MouseButton.Left:
          if cell.canSelect:
            let offset = builder.getCursorPos(inText, 0.RuneIndex, pos, updateContext.isThickCursor)
            let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
            let cellPath = cell.rootPath.path
            updateContext.handleClick(currentNode, cell, cellPath, cursor, false)

      onDrag MouseButton.Left:
        if cell.canSelect:
          let offset = builder.getCursorPos(inText, 0.RuneIndex, pos, updateContext.isThickCursor)
          let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
          let cellPath = cell.rootPath.path
          updateContext.handleClick(currentNode, cell, cellPath, cursor, true)

  else:
    # cell.logc fmt"partial selection {selectionStart}, {selectionEnd}"
    builder.panel(&{SizeToContentX, SizeToContentY, FillY, OverlappingChildren}):
      let x = selectionStart.float * builder.charWidth
      let xw = selectionEnd.float * builder.charWidth
      builder.panel(&{FillY, FillBackground}, x = x, w = xw - x, backgroundColor = updateContext.selectionColor)

      builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = inText, textColor = inTextColor):
        updateContext.cellToWidget[cell.id] = currentNode
        currentNode.userData = cell
        onClickAny btn:
          if btn == MouseButton.Left:
            if cell.canSelect:
              let offset = builder.getCursorPos(inText, 0.RuneIndex, pos, updateContext.isThickCursor)
              let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
              let cellPath = cell.rootPath.path
              updateContext.handleClick(currentNode, cell, cellPath, cursor, false)

        onDrag MouseButton.Left:
          if cell.canSelect:
            let offset = builder.getCursorPos(inText, 0.RuneIndex, pos, updateContext.isThickCursor)
            let cursor = updateContext.nodeCellMap.toCursor(cell, offset)
            let cellPath = cell.rootPath.path
            updateContext.handleClick(currentNode, cell, cellPath, cursor, true)

method createCellUI*(cell: Cell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) {.base.} = discard

method createCellUI*(cell: ConstantCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec

  cell.logc fmt"createCellUI (ConstantCell) {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: PlaceholderCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: AliasCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: PropertyCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: NodeReferenceCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (ConstantCell) {path}, {cursorFirst}, {cursorLast}"

  if cell.child.isNil:
    let reference = cell.node.reference(cell.reference)
    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)

    let text = $reference
    createLeafCellUI(cell, builder, text, textColor, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

  else:
    cell.child.createCellUI(builder, app, ctx, updateContext, spaceLeft, path, cursorFirst, cursorLast)
    updateContext.cellToWidget[cell.id] = builder.currentChild

  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

template getChildPath(cursor: openArray[int], index: int): openArray[int] =
  if cursor.len > 0:
    if index == cursor[0]:
      cursor[1..^1]
    else:
      if index < cursor[0]:
        @[int.high]
      else:
        @[-1]
  else:
    @[]

method createCellUI*(cell: CollectionCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    cell.logc fmt"createCellUI end (CollectionCell) {path}, {cursorFirst}, {cursorLast}"
    stackSize.dec
  cell.logc fmt"createCellUI begin (CollectionCell) {path}, {cursorFirst}, {cursorLast}"

  let parentCtx = ctx
  var ctx = ctx
  var hasContext = false
  if cell.inline and ctx.cell != cell:
    ctx = newCellLayoutContext(ctx, cell, ctx.remainingHeightDown, ctx.remainingHeightUp, false)
    hasContext = true

  defer:
    if hasContext:
      ctx.finish()
      if parentCtx.targetDirection in {Direction.Forwards, Center}:
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
    if not ctx.isCurrentLineEmpty:
      ctx.newLine()

    if cell.style.isNotNil and cell.style.indentChildren:
      ctx.increaseIndent()

    defer:
      if cell.style.isNotNil and cell.style.indentChildren:
        ctx.decreaseIndent()

    # center
    block:
      # echo "center ", centerIndex
      let myCtx = newCellLayoutContext(ctx, c, ctx.remainingHeightDown, ctx.remainingHeightUp, true)
      defer:
        myCtx.finish()

        if updateContext.targetNode.isNotNil and path.len > 1:
          let targetBounds = updateContext.targetNode.bounds.transformRect(updateContext.targetNode.parent, myCtx.parentNode)
          # debugf"targetBounds: {targetBounds}, h: {myCtx.parentNode.h}, down: {myCtx.parentNode.h - targetBounds.y}, up: {targetBounds.y}"
          ctx.remainingHeightUp -= targetBounds.y
          ctx.remainingHeightDown -= myCtx.parentNode.h - targetBounds.y
        elif ctx.targetDirection in {Direction.Forwards, Center}:
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
          # cell.logc "1: reached bottom"
          return

      cellPath.add centerIndex
      c.createCellUI(builder, app, myCtx, updateContext, false, if path.len > 1: path[1..^1] else: @[], cursorFirst.getChildPath(centerIndex), cursorLast.getChildPath(centerIndex))
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
    if centerIndex < cell.children.high:
      ctx.currentDirection = Forwards
      ctx.targetDirection = Forwards
      for i in (centerIndex + 1)..cell.children.high:
        # echo "down ", i
        let c = cell.children[i]
        ctx.newLine()
        if cell.style.isNotNil and cell.style.indentChildren:
          ctx.increaseIndent()

        let myCtx = newCellLayoutContext(ctx, c, ctx.remainingHeightDown, 0, true)
        defer:
          myCtx.finish()
          # echo myCtx.parentNode.h
          ctx.remainingHeightDown -= myCtx.parentNode.h
          if ctx.remainingHeightDown < 0:
            # cell.logc "2: reached bottom"
            break

        cellPath.add i
        c.createCellUI(builder, app, myCtx, updateContext, false, @[], cursorFirst.getChildPath(i), cursorLast.getChildPath(i))
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

        let myCtx = newCellLayoutContext(ctx, c, 0, ctx.remainingHeightUp, true)
        defer:
          myCtx.finish()
          # echo myCtx.parentNode.h
          ctx.remainingHeightUp -= myCtx.parentNode.h
          if ctx.remainingHeightUp < 0:
            # cell.logc "3: reached top"
            break

        cellPath.add i
        c.createCellUI(builder, app, myCtx, updateContext, false, @[], cursorFirst.getChildPath(i), cursorLast.getChildPath(i))
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
      c.createCellUI(builder, app, ctx, updateContext, spaceLeft, if i == centerIndex and path.len > 1: path[1..^1] else: @[], cursorFirst.getChildPath(i), cursorLast.getChildPath(i))
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

proc pathAfter(a, b: openArray[int]): bool =
  for i in 0..min(a.high, b.high):
    if a[i] != b[i]:
      return a[i] > b[i]
  return a.len > b.len

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
  self.cellWidgetContext.selectionColor = app.theme.color("selection.background", color(200/255, 200/255, 200/255))

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.userId.newPrimaryId):
    defer:
      self.lastContentBounds = currentNode.bounds

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      self.cellWidgetContext.cellToWidget = initTable[Id, UINode](self.cellWidgetContext.cellToWidget.len)
      self.cellWidgetContext.isThickCursor = self.isThickCursor()

      builder.panel(&{LayoutVertical} + sizeFlags):
        header = builder.createHeader(self.renderHeader, self.currentMode, self.document, headerColor, textColor):
          onRight:
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
              let scrolledNode = currentNode
              self.scrolledNode = scrolledNode

              defer:
                self.lastBounds = currentNode.bounds

              for node in self.document.model.rootNodes:
                let cell = self.nodeCellMap.cell(node)
                # let cell = self.document.builder.buildCell(self.nodeCellMap, node, self.useDefaultCellBuilder)
                if cell.isNil:
                  continue

                self.cellWidgetContext.targetNode = nil
                self.cellWidgetContext.handleClick = proc(node: UINode, cell: Cell, cellPath: seq[int], cursor: CellCursor, drag: bool) =
                  if node.isNotNil:
                    let bounds = node.bounds.transformRect(node.parent, scrolledNode.parent)
                    self.targetCellPath = cellPath
                    # debugf"click: {self.scrollOffset} -> {bounds.y} | {cell.dump} | {node.dump}"
                    self.scrollOffset = bounds.y

                  self.updateSelection(cursor, drag)

                  self.markDirty()

                # echo fmt"scroll offset {self.scrollOffset}"
                block:
                  let myCtx = newCellLayoutContext(builder, self.cellWidgetContext, Direction.Center, true)
                  defer:
                    myCtx.finish()

                  myCtx.remainingHeightUp = self.scrollOffset - cellGenerationBuffer
                  myCtx.remainingHeightDown = (h - self.scrollOffset) - cellGenerationBuffer

                  var cursorFirst = self.selection.first.rootPath
                  var cursorLast = self.selection.last.rootPath
                  if cursorFirst.path.pathAfter(cursorLast.path):
                    swap(cursorFirst, cursorLast)

                  cell.createCellUI(builder, app, myCtx, self.cellWidgetContext, false, self.targetCellPath, cursorFirst.path, cursorLast.path)

                if self.cellWidgetContext.targetNodeOld != self.cellWidgetContext.targetNode:
                  if self.cellWidgetContext.targetNodeOld.isNotNil:
                    self.cellWidgetContext.targetNodeOld.contentDirty = true
                  if self.cellWidgetContext.targetNode.isNotNil:
                    self.cellWidgetContext.targetNode.contentDirty = true

                self.cellWidgetContext.targetNodeOld = self.cellWidgetContext.targetNode

                if self.cellWidgetContext.targetNode.isNotNil:
                  var bounds = self.cellWidgetContext.targetNode.bounds.transformRect(self.cellWidgetContext.targetNode.parent, scrolledNode.parent)
                  # echo fmt"1 target node {bounds}: {self.cellWidgetContext.targetNode.dump}"
                  # echo scrolledNode.boundsRaw.y, " -> ", scrolledNode.boundsRaw.y + (self.scrollOffset - bounds.y)
                  scrolledNode.rawY = scrolledNode.boundsRaw.y + (self.scrollOffset - bounds.y)
                  bounds = self.cellWidgetContext.targetNode.bounds.transformRect(self.cellWidgetContext.targetNode.parent, scrolledNode.parent)
                  # echo fmt"2 target node {bounds}: {self.cellWidgetContext.targetNode.dump}"

                if self.scrollOffset < cellGenerationBuffer or self.scrollOffset >= h - cellGenerationBuffer:
                  let forward = self.scrollOffset < cellGenerationBuffer
                  if self.cellWidgetContext.updateTargetPath(scrolledNode.parent, cell, forward, self.targetCellPath, @[]).getSome(path):
                    # echo "update path ", path, " (was ", targetCellPath, ")"
                    self.targetCellPath = path[1]
                    self.scrollOffset = path[0]

          # cursor
          block:
            if self.selection.last.getTargetCell(true).getSome(targetCell) and self.cellWidgetContext.cellToWidget.contains(targetCell.id):
              let node = self.cellWidgetContext.cellToWidget[targetCell.id]
              # debugf"cursor {self.cursor} at {targetCell.dump}, {node.dump}"

              let index = self.selection.last.lastIndex
              var bounds = rect(index.float * builder.charWidth, 0, 0, 0).transformRect(node, overlapPanel)

              if self.isThickCursor:
                let text = targetCell.getText
                let index = self.selection.last.lastIndex.clamp(0, text.runeLen.int).RuneIndex
                let ch = if index < text.runeLen.RuneIndex: text[index..index] else: " "

                builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, SnapInitialBounds}, x = bounds.x, y = bounds.y, w = builder.charWidth, h = builder.textHeight, backgroundColor = textColor, userId = newSecondaryId(self.cursorsId, 0)):
                  builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = backgroundColor, text = ch)
              else:
                builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, SnapInitialBounds}, x = bounds.x, y = bounds.y, w = max(builder.charWidth * 0.2, 1), h = builder.textHeight, backgroundColor = textColor, userId = newSecondaryId(self.cursorsId, 0))

              self.lastCursorLocationBounds = rect(index.float * builder.charWidth, 0, builder.charWidth, builder.textHeight).transformRect(node, builder.root).some

            if not self.selection.empty and self.selection.first.getTargetCell(true).getSome(targetCell) and self.cellWidgetContext.cellToWidget.contains(targetCell.id):
              let node = self.cellWidgetContext.cellToWidget[targetCell.id]
              # debugf"cursor {self.cursor} at {targetCell.dump}, {node.dump}"

              let index = self.selection.first.lastIndex
              var bounds = rect(index.float * builder.charWidth, 0, 0, 0).transformRect(node, overlapPanel)

              if self.isThickCursor:
                let text = targetCell.getText
                let index = self.selection.first.lastIndex.clamp(0, text.runeLen.int).RuneIndex
                let ch = if index < text.runeLen.RuneIndex: text[index..index] else: " "

                builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, SnapInitialBounds}, x = bounds.x, y = bounds.y, w = builder.charWidth, h = builder.textHeight, backgroundColor = textColor, userId = newSecondaryId(self.cursorsId, 1)):
                  builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = backgroundColor, text = ch)
              else:
                builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, SnapInitialBounds}, x = bounds.x, y = bounds.y, w = max(builder.charWidth * 0.2, 1), h = builder.textHeight, backgroundColor = textColor, userId = newSecondaryId(self.cursorsId, 1))

        # echo builder.currentChild.dump(true)

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))