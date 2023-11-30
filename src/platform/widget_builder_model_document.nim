import std/[strformat, tables, sugar, strutils, json]
import util, app, document_editor, model_document, text/text_document, custom_logger, platform, theme, config_provider, input, app_interface
import widget_builders_base, widget_library, ui/node, custom_unicode
import vmath, bumpy, chroma
import ast/[model, cells, model_state]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_model_document"

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

const cellGenerationBuffer = -15
const targetCellBuffer = 50
# const cellGenerationBuffer = 150

type
  Direction = enum
    Center
    Forwards
    Backwards

  DirectionData = object
    pivot: Vec2
    lastCell: Cell
    lines: seq[seq[UINode]]
    currentPos: Vec2

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
    prevNoSpaceRight: bool = false
    centerNoSpaceLeft: bool = false
    indentText: string
    remainingHeightDown: float
    remainingHeightUp: float
    currentDirection = Direction.Forwards # Which line direction data we're currently using
    pivot: Vec2
    tempNode: UINode
    joinLines: bool = false
    containsCenter: bool = false
    childContainsCenter: bool = false
    centerChildTargetPos: Vec2 # target position of the child node that contains the center, in content space (i.e. same space as scroll offset)

var stackSize = 0
var cellPath = newSeq[int]()
var enableLogc {.exportc.} = false
template logc(node: untyped, msg: varargs[string, `$`]) =
  if enableLogc:
    var uiae = ""
    for c in msg:
      uiae.add $c
    let xvlc: string = dump(node, false)
    debug "| ".repeat(stackSize), " (", cellPath, "): ", uiae, "    | ", xvlc, ""

proc newCellLayoutContext(builder: UINodeBuilder, updateContext: UpdateContext, requiredDirection: Direction, fillX: bool): CellLayoutContext =
  new result

  var noneId = noneUserId

  result.forwardData.pivot = vec2(0, 0)
  result.backwardData.pivot = vec2(0, 1)

  result.builder = builder
  result.updateContext = updateContext

  let fillXFlag = if fillX: &{FillX} else: 0.UINodeFlags

  result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVertical} + fillXFlag, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
  # result.builder.createLineNode(result.forwardData)
  result.currentDirection = Forwards

  result.tempNode = builder.unpoolNode(noneId)
  builder.currentParent = result.tempNode
  builder.currentChild = nil

  result.indentText = "··"

proc goBackward(self: CellLayoutContext)

proc newCellLayoutContext(parent: CellLayoutContext, cell: Cell, remainingHeightDown, remainingHeightUp: float, fillX: bool): CellLayoutContext =
  result = newCellLayoutContext(parent.builder, parent.updateContext, Forwards, fillX)
  result.parent = parent
  result.remainingHeightDown = remainingHeightDown
  result.remainingHeightUp = remainingHeightUp
  result.forwardData.currentPos = parent.forwardData.currentPos
  result.backwardData.currentPos = parent.backwardData.currentPos
  result.cell = cell

  when defined(uiNodeDebugData):
    result.parentNode.aDebugData.metaData["indent"] = result.parent.currentIndent.newJInt

    result.parentNode.aDebugData.metaData["remainingHeightDown"] = newJFloat(result.parent.remainingHeightDown)
    result.parentNode.aDebugData.metaData["remainingHeightUp"] = newJFloat(result.parent.remainingHeightUp)

  # cell.logc fmt"newCellLayoutContext {remainingHeightDown}, {remainingHeightUp}"

proc currentDirectionData(self: CellLayoutContext): var DirectionData =
  case self.currentDirection
  of Forwards:
    return self.forwardData
  of Backwards:
    return self.backwardData
  else:
    assert false

proc isCurrentLineEmpty(self: CellLayoutContext): bool =
  return (self.currentDirectionData.lines.len == 0 or self.currentDirectionData.lines.last.len == 0) and self.tempNode.first.isNil

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

proc handleIndentClickOrDrag(builder: UINodeBuilder, updateContext: UpdateContext, btn: MouseButton, modifiers: Modifiers, currentNode: UINode, drag: bool, pos: Vec2) =
  let posAbs = pos.transformPos(currentNode, builder.root).xy
  if getCellInLine(builder, updateContext.scrolledNode, posAbs - vec2(0, builder.textHeight / 2), 0, true).getSome(target):
    updateContext.setCursor(target.cell, target.offset, drag)

proc increaseIndent(self: CellLayoutContext) =
  inc self.currentIndent

proc decreaseIndent(self: CellLayoutContext) =
  if self.currentIndent == 0:
    return
  dec self.currentIndent

proc notifyCellCreated(self: CellLayoutContext, cell: Cell) =
  self.currentDirectionData.lastCell = cell

proc handleSpaceClickOrDrag(builder: UINodeBuilder, node: UINode, drag: bool, pos: Vec2, btn: MouseButton, modifiers: Modifiers) =
  let posAbs = rect(pos, vec2()).transformRect(node, builder.root).xy

  let targetNode = if node.prev.isNil:
    node.next
  elif node.next.isNil:
    node.prev
  elif pos.x <= builder.charWidth * 0.5:
    node.prev
  else:
    node.next

  # debugf"handleSpaceClickOrDrag {targetNode.dump}, {pos}"

  if targetNode.isNotNil:
    if drag and targetNode.handleDrag.isNotNil:
      discard targetNode.handleDrag()(targetNode, btn, modifiers, posAbs - targetNode.boundsAbsolute.xy, vec2())
    elif not drag and targetNode.handlePressed.isNotNil:
      discard targetNode.handlePressed()(targetNode, btn, modifiers, posAbs - targetNode.boundsAbsolute.xy)

proc addSpace(self: CellLayoutContext, cell: Cell, updateContext: UpdateContext) =
  if self.isCurrentLineEmpty and not (self.joinLines and self.currentDirectionData.lines.len == 0):
    return

  # # echo "add space, current indent ", self.currentIndent, ", ", cell

  let builder = self.builder

  self.builder.panel(&{FillY}, w = self.builder.charWidth):
    onClickAny btn:
      if btn == MouseButton.Left:
        handleSpaceClickOrDrag(builder, currentNode, false, pos, btn, modifiers)

    onDrag MouseButton.Left:
      handleSpaceClickOrDrag(builder, currentNode, true, pos, btn, modifiers)

    when defined(uiNodeDebugData):
      currentNode.aDebugData.metaData["isForward"] = newJBool self.currentDirection == Forwards
      currentNode.aDebugData.metaData["isSpace"] = newJBool true

proc addSpace(self: CellLayoutContext, cell: Cell, updateContext: UpdateContext, color: Color) =
  if self.isCurrentLineEmpty and not (self.joinLines and self.currentDirectionData.lines.len == 0):
    return

  # # echo "add space, current indent ", self.currentIndent, ", ", cell
  let builder = self.builder

  self.builder.panel(&{FillY, FillBackground}, w = self.builder.charWidth, backgroundColor = color):
    onClickAny btn:
      if btn == MouseButton.Left:
        handleSpaceClickOrDrag(builder, currentNode, false, pos, btn, modifiers)

    onDrag MouseButton.Left:
      handleSpaceClickOrDrag(builder, currentNode, true, pos, btn, modifiers)

    when defined(uiNodeDebugData):
      currentNode.aDebugData.metaData["isSpace"] = newJBool true

proc saveLine(self: CellLayoutContext) =
  # echo "new line, current indent ", self.currentIndent, ", ", self.cell
  if self.currentDirectionData.lines.len == 0:
    self.currentDirectionData.lines.add @[]

  if self.currentDirection == Forwards:
    for i, c in self.tempNode.children:
      c.removeFromParent()
      self.forwardData.lines.last.add c
  else:
    for i, c in self.tempNode.children:
      c.removeFromParent()
      self.backwardData.lines.last.add c

  when defined(uiNodeDebugData):
    for node in self.currentDirectionData.lines.last:
      node.aDebugData.metaData["pos"] = newJString $self.currentDirectionData.currentPos

  self.builder.continueFrom(self.tempNode, nil)

proc newLine(self: CellLayoutContext) =
  self.saveLine()

  var maxHeight = 0.0
  for node in self.currentDirectionData.lines.last:
    self.builder.updateSizeToContent(node)
    maxHeight = max(maxHeight, node.h)

  if self.currentDirection == Forwards:
    self.currentDirectionData.currentPos.y += maxHeight
  else:
    self.currentDirectionData.currentPos.y -= maxHeight

  if self.currentDirectionData.lines.last.len > 0:
    self.currentDirectionData.lines.add @[]

  self.tempNode.first = nil
  self.tempNode.last = nil
  self.builder.currentParent = self.tempNode
  self.builder.currentChild = nil

proc goBackward(self: CellLayoutContext) =
  if self.currentDirection != Backwards:
    self.saveLine()
    self.currentDirection = Backwards

proc goForward(self: CellLayoutContext) =
  if self.currentDirection != Forwards:
    self.saveLine()
    self.currentDirection = Forwards

proc getTextAndColor(app: App, cell: Cell, defaultShadowText: string = ""): (string, Color) =
  let currentText = cell.currentText
  if currentText.len == 0:
    let text = if cell.shadowText.len == 0:
      defaultShadowText
    else:
      cell.shadowText
    let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255)).withAlpha(0.7)
    return (text, textColor)
  else:
    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)
    return (currentText, textColor)

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

        of ModelCompletionKind.ChangeReference:
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

    if ctx.currentDirection == Forwards:
      if first < 0 and last >= 0:
        spaceSelected = true
    else:
      if first <= inText.len and last > inText.len:
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

      when defined(uiNodeDebugData):
        if updateContext.selection.contains(cell):
          currentNode.aDebugData.css.add "border: 1px solid yellow;"

        if ctx.currentIndent > 0:
          currentNode.aDebugData.metaData["indent"] = ctx.currentIndent.newJInt

  else:
    # cell.logc fmt"partial selection {selectionStart}, {selectionEnd}"
    builder.panel(&{SizeToContentX, SizeToContentY, FillY, OverlappingChildren}):
      let x = selectionStart.float * builder.charWidth
      let xw = selectionEnd.float * builder.charWidth
      let w = xw - x
      builder.panel(&{FillY, FillBackground, IgnoreBoundsForSizeToContent}, x = x, w = w, backgroundColor = updateContext.selectionColor)

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

      when defined(uiNodeDebugData):
        if updateContext.selection.contains(cell):
          currentNode.aDebugData.css.add "border: 1px solid yellow;"

        if ctx.currentIndent > 0:
          currentNode.aDebugData.metaData["indent"] = ctx.currentIndent.newJInt

method createCellUI*(cell: Cell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) {.base.} = discard

method createCellUI*(cell: ConstantCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec

  cell.logc fmt"createCellUI (ConstantCell) {ctx.remainingHeightDown}, {ctx.remainingHeightUp}, {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: PlaceholderCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (PlaceholderCell) {ctx.remainingHeightDown}, {ctx.remainingHeightUp}, {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: AliasCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (AliasCell) {ctx.remainingHeightDown}, {ctx.remainingHeightUp}, {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

method createCellUI*(cell: PropertyCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    stackSize.dec
  cell.logc fmt"createCellUI (PropertyCell) {ctx.remainingHeightDown}, {ctx.remainingHeightUp}, {path}, {cursorFirst}, {cursorLast}"

  let (text, color) = app.getTextAndColor(cell)
  createLeafCellUI(cell, builder, text, color, ctx, updateContext, spaceLeft, cursorFirst, cursorLast)

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

proc finish(self: CellLayoutContext) =
  self.saveLine()

  # debugf"finish {self.joinLines}"
  # echo self.tempNode.dump

  var builder = self.builder
  builder.continueFrom(self.parentNode, nil)

  var noneId = noneUserId

  var lineNode: UINode
  for line in countdown(self.backwardData.lines.high, 0):
    lineNode = builder.prepareNode(&{SizeToContentX, FillX, SizeToContentY, LayoutHorizontal}, string.none, float32.none, float32.none, float32.none, float32.none, vec2(0, 0).some, noneId, UINodeFlags.none)
    builder.clearUnusedChildren(lineNode, nil)

    if self.currentIndent > 0:
      builder.panel(&{FillY}, w = self.indentText.len.float * self.currentIndent.float * builder.charWidth, textColor = color(0, 1, 0)):
        capture currentNode:
          onClickAny btn:
            if btn == MouseButton.Left:
              handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, false, pos)

          onDrag MouseButton.Left:
            handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, true, pos)

        when defined(uiNodeDebugData):
          currentNode.aDebugData.metaData["isBackwards"] = newJBool true
          currentNode.aDebugData.metaData["isIndent"] = newJBool true

    for i in countdown(self.backwardData.lines[line].high, 0):
      # self.backwardData.lines[line][i].removeFromParent()
      lineNode.insert(self.backwardData.lines[line][i], lineNode.last)
      builder.continueFrom(lineNode, lineNode.last)

    if line != 0 or not self.joinLines:

      # add space after last cell in line for mouse handling
      builder.panel(&{FillX, FillY}):
        capture currentNode:
          onClickAny btn:
            if btn == MouseButton.Left:
              handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, false, pos)

          onDrag MouseButton.Left:
            handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, true, pos)

        when defined(uiNodeDebugData):
          currentNode.aDebugData.metaData["isPostSpace"] = newJBool true
          currentNode.aDebugData.metaData["isForward"] = newJBool true

      builder.finishNode(lineNode)

  for line in 0..self.forwardData.lines.high:

    if lineNode.isNil or line > 0 or not self.joinLines:
      lineNode = builder.prepareNode(&{SizeToContentX, FillX, SizeToContentY, LayoutHorizontal}, string.none, float32.none, float32.none, float32.none, float32.none, vec2(0, 0).some, noneId, UINodeFlags.none)
      builder.clearUnusedChildren(lineNode, nil)

      if self.currentIndent > 0:
        builder.panel(&{FillY}, w = self.indentText.len.float * self.currentIndent.float * builder.charWidth, textColor = color(0, 1, 0)):
          capture currentNode:
            onClickAny btn:
              if btn == MouseButton.Left:
                handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, false, pos)

            onDrag MouseButton.Left:
              handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, true, pos)

          when defined(uiNodeDebugData):
            currentNode.aDebugData.metaData["isForwards"] = newJBool true
            currentNode.aDebugData.metaData["isIndent"] = newJBool true

    # else:
      # echo "join ", lineNode.last.text, " and ", self.forwardData.lines[line][0].text

    for i in 0..self.forwardData.lines[line].high:
      lineNode.insert(self.forwardData.lines[line][i], lineNode.last)
      builder.continueFrom(lineNode, lineNode.last)

    # add space after last cell in line for mouse handling
    builder.panel(&{FillX, FillY}):
      capture currentNode:
        onClickAny btn:
          if btn == MouseButton.Left:
            handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, false, pos)

        onDrag MouseButton.Left:
          handleIndentClickOrDrag(builder, self.updateContext, btn, modifiers, currentNode, true, pos)

      when defined(uiNodeDebugData):
        currentNode.aDebugData.metaData["isPostSpace"] = newJBool true
        currentNode.aDebugData.metaData["isForward"] = newJBool true

    builder.finishNode(lineNode)

  builder.finishNode(self.parentNode)

  assert self.tempNode.first.isNil
  builder.returnNode(self.tempNode)

proc shouldBeOnNewLine(cell: Cell): bool =
  if OnNewLine in cell.flags:
    return true
  if cell.parent.isNil:
    return false

  if LayoutVertical in cell.parent.CollectionCell.uiFlags:
    return true

  if cell == cell.parent.CollectionCell.children[0]:
    return cell.parent.shouldBeOnNewLine()

  return false

method createCellUI*(cell: CollectionCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool, path: openArray[int], cursorFirst: openArray[int], cursorLast: openArray[int]) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  stackSize.inc
  defer:
    cell.logc fmt"createCellUI end (CollectionCell) {path}, {cursorFirst}, {cursorLast}"
    stackSize.dec
  cell.logc fmt"createCellUI begin (CollectionCell) {path}, {cursorFirst}, {cursorLast}"

  let vertical = LayoutVertical in cell.uiFlags

  if vertical and spaceLeft:
    ctx.addSpace(cell, updateContext)

  let parentCtx = ctx
  var ctx = ctx
  var hasContext = false
  if cell.inline or vertical:
    ctx = newCellLayoutContext(parentCtx, cell, ctx.remainingHeightDown, ctx.remainingHeightUp, not cell.inline)
    hasContext = true

  if IndentChildren in cell.flags:
    ctx.increaseIndent()

  defer:
    if IndentChildren in cell.flags:
      ctx.decreaseIndent()

  defer:
    if hasContext:
      ctx.finish()

      if ctx.containsCenter or ctx.childContainsCenter:
        parentCtx.childContainsCenter = true

        let targetCellPosInSelf = updateContext.targetNode.transformBounds(ctx.parentNode)
        # let targetPosSelf = updateContext.targetCellPos.transformPos(updateContext.targetNode, updateContext.scrolledNode.parent)
        let newTargetCellPos = updateContext.targetCellPosition - targetCellPosInSelf.xy
        # debugf"targetCellPos: {updateContext.targetCellPosition}, self: {targetCellPosInSelf}, new: {newTargetCellPos}"
        parentCtx.centerChildTargetPos = newTargetCellPos
        parentCtx.forwardData.currentPos = newTargetCellPos
        parentCtx.backwardData.currentPos = newTargetCellPos

  updateContext.nodeCellMap.fill(cell)
  if cell.children.len == 0:
    return

  let centerIndex = if path.len > 0: path[0].clamp(-1, cell.children.len) elif ctx.currentDirection == Direction.Backwards: cell.children.len else: -1

  let adjustedCenterIndex = centerIndex.clamp(0, cell.children.len)

  var centerNewLine = false
  var lastNewLine = false

  # forwards
  if adjustedCenterIndex <= cell.children.high:
    for i in adjustedCenterIndex..cell.children.high:
      if ctx.forwardData.currentPos.y - updateContext.targetCellPosition.y > ctx.remainingHeightDown:
        # debugf"reached bottom {cell}"
        break

      ctx.goForward()

      let c = cell.children[i]

      if c.isVisible.isNotNil and not c.isVisible(c.node):
        continue

      # c.logc fmt"down {i}, {ctx.remainingHeightDown}, {c}        {cell}"

      var onNewLine = vertical

      var noSpaceLeft = false
      if c.style.isNotNil:
        if c.style.noSpaceLeft:
          noSpaceLeft = true
      if NoSpaceLeft in c.flags:
        noSpaceLeft = true
      if OnNewLine in c.flags:
        onNewLine = true

      var spaceLeft = not ctx.prevNoSpaceRight and not noSpaceLeft
      if onNewLine and not ctx.isCurrentLineEmpty:
        ctx.newLine()
        spaceLeft = false
        ctx.prevNoSpaceRight = true
        lastNewLine = true
      else:
        lastNewLine = false

      try:
        cellPath.add i
        c.createCellUI(
          builder, app, ctx, updateContext, spaceLeft,
          if i == centerIndex and path.len > 1:
            path[1..^1]
          elif i >= centerIndex:
            @[-1]
          else:
            @[int.high],
          cursorFirst.getChildPath(i), cursorLast.getChildPath(i))
        discard cellPath.pop

        if i == centerIndex:
          # echo "center ", cellPath, ", ", path
          centerNewLine = onNewLine
          ctx.centerNoSpaceLeft = noSpaceLeft
          if not c.shouldBeOnNewLine and ctx.forwardData.lines.len == 0:
            # echo "join lines for ", c, "     ", cell
            ctx.joinLines = true

        if i == centerIndex and updateContext.targetNode.isNil:
          # echo "set target ", cellPath, ", ", path
          updateContext.targetNode = ctx.tempNode.last
          updateContext.targetCell = c
          when defined(uiNodeDebugData):
            updateContext.targetNode.aDebugData.css.add "border: 1px solid red;"
            updateContext.targetNode.aDebugData.metaData["target"] = newJBool(true)

        if i == centerIndex and path.len == 1:
          centerNewLine = onNewLine
          ctx.containsCenter = true

          ctx.forwardData.currentPos = updateContext.targetCellPosition
          ctx.backwardData.currentPos = updateContext.targetCellPosition

      finally:
        ctx.prevNoSpaceRight = false
        if c.style.isNotNil:
          ctx.prevNoSpaceRight = c.style.noSpaceRight
        if NoSpaceRight in c.flags:
          ctx.prevNoSpaceRight = true

      # builder.panel(&{DrawText, SizeToContentX, SizeToContentY}, text = fmt"{myCtx.parentNode.h}, {ctx.remainingHeightDown}, {ctx.remainingHeightUp}", textColor = color(0, 1, 0))

  # backwards
  if adjustedCenterIndex > 0:
    # echo "go backward"
    # debugf"center no space left {centerNoSpaceLeft}"

    ctx.goBackward()

    if ctx.containsCenter and ctx.isCurrentLineEmpty:
      ctx.prevNoSpaceRight = ctx.centerNoSpaceLeft

    if centerNewLine:
      ctx.newLine()

    for i in countdown(adjustedCenterIndex - 1, 0):
      if updateContext.targetCellPosition.y - ctx.backwardData.currentPos.y > ctx.remainingHeightUp:
        # debugf"reached top {cell}"
        break

      ctx.goBackward()

      let c = cell.children[i]
      # echo "up ", i, ", ", ctx.remainingHeightUp, ", ", c, "        ", cell
      # c.logc fmt"up {i}, {ctx.remainingHeightUp}, {c}        {cell}"

      if c.isVisible.isNotNil and not c.isVisible(c.node):
        continue

      var onNewLine = vertical

      var spaceLeft = not ctx.prevNoSpaceRight
      if c.style.isNotNil:
        if c.style.noSpaceRight:
          spaceLeft = false
      if NoSpaceRight in c.flags:
        spaceLeft = false
      if OnNewLine in c.flags:
        onNewLine = true

      if vertical:
        spaceLeft = false

      try:
        cellPath.add i
        c.createCellUI(builder, app, ctx, updateContext, spaceLeft, @[int.high], cursorFirst.getChildPath(i), cursorLast.getChildPath(i))
        discard cellPath.pop
      finally:
        ctx.prevNoSpaceRight = false
        if c.style.isNotNil:
          ctx.prevNoSpaceRight = c.style.noSpaceLeft
        if NoSpaceLeft in c.flags:
          ctx.prevNoSpaceRight = true

      if onNewLine:
        ctx.newLine()

      lastNewLine = onNewLine

proc updateTargetPath(updateContext: UpdateContext, root: UINode, cell: Cell, forward: bool, targetPath: openArray[int], currentPath: seq[int]): Option[(float32, seq[int])] =
  if cell of CollectionCell and cell.CollectionCell.children.len > 0:
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
    if bounds.y > cellGenerationBuffer + targetCellBuffer and bounds.yh < root.h - cellGenerationBuffer - targetCellBuffer:
      return (bounds.y, currentPath).some

proc pathAfter(a, b: openArray[int]): bool =
  for i in 0..min(a.high, b.high):
    if a[i] != b[i]:
      return a[i] > b[i]
  return a.len > b.len

proc createNodeUI(self: ModelDocumentEditor, builder: UINodeBuilder, app: App, container: UINode, updateContext: UpdateContext, remainingHeightUp: float, remainingHeightDown: float, node: AstNode, targetCellPath: seq[int], scrollOffset: float) =
  let cell = updateContext.nodeCellMap.cell(node)
  if cell.isNil:
    return

  # debugf"render: {targetCellPath}:{self.scrollOffset}"
  # echo fmt"scroll offset {scrollOffset}"
  try:
    let myCtx = newCellLayoutContext(builder, updateContext, Direction.Forwards, true)
    defer:
      myCtx.finish()

    myCtx.remainingHeightUp = remainingHeightUp
    myCtx.remainingHeightDown = remainingHeightDown

    var cursorFirst = self.selection.first.rootPath
    var cursorLast = self.selection.last.rootPath
    if cursorFirst.path.pathAfter(cursorLast.path):
      swap(cursorFirst, cursorLast)

    # debugf"target cell: {targetCellPath}"
    cell.createCellUI(builder, app, myCtx, updateContext, false, targetCellPath, cursorFirst.path, cursorLast.path)
    if not (cell of CollectionCell):
      updateContext.targetNode = myCtx.parentNode
      updateContext.targetCell = cell

  except Defect:
    log lvlError, fmt"failed to creat UI nodes {getCurrentExceptionMsg()}"

  if updateContext.targetNodeOld != updateContext.targetNode:
    if updateContext.targetNodeOld.isNotNil:
      updateContext.targetNodeOld.contentDirty = true
    if updateContext.targetNode.isNotNil:
      updateContext.targetNode.contentDirty = true

  updateContext.targetNodeOld = updateContext.targetNode

  # move the container position so the target cell is at the desired scroll offset
  if updateContext.targetNode.isNotNil:
    var bounds = updateContext.targetNode.bounds.transformRect(updateContext.targetNode.parent, container.parent)
    # echo fmt"1 target node {bounds}: {updateContext.targetNode.dump}"
    # echo container.boundsRaw.y, " -> ", container.boundsRaw.y + (scrollOffset - bounds.y)
    # debugf"update scrolled node y: {container.boundsRaw.y} -> {(container.boundsRaw.y + (scrollOffset - bounds.y))}"
    container.rawY = container.boundsRaw.y + (scrollOffset - bounds.y)
    # echo fmt"2 target node {bounds}: {updateContext.targetNode.dump}"

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

    onClickAny btn:
      self.app.tryActivateEditor(self)

    if dirty or app.platform.redrawEverything or not builder.retain():
      var header: UINode

      self.cellWidgetContext.cellToWidget = initTable[CellId, UINode](self.cellWidgetContext.cellToWidget.len)
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
                self.cellWidgetContext.selection = self.selection
                self.cellWidgetContext.scrolledNode = scrolledNode
                self.cellWidgetContext.targetCellPosition = vec2(0, self.scrollOffset)
                self.cellWidgetContext.handleClick = proc(node: UINode, cell: Cell, cellPath: seq[int], cursor: CellCursor, drag: bool) =
                  if node.isNotNil:
                    let bounds = node.bounds.transformRect(node.parent, scrolledNode.parent)
                    self.targetCellPath = cellPath
                    # debugf"click: {cellPath}"
                    # debugf"click: {self.scrollOffset} -> {bounds.y} | {cell.dump} | {node.dump}"
                    self.scrollOffset = bounds.y

                  if self.active or not drag:
                    self.updateSelection(cursor, drag)
                    self.app.tryActivateEditor(self)
                    self.markDirty()

                self.cellWidgetContext.setCursor = proc(cell: Cell, offset: int, drag: bool) =
                  if self.active or not drag:
                    self.updateSelection(self.nodeCellMap.toCursor(cell, offset), drag)
                    self.updateScrollOffset()
                    self.app.tryActivateEditor(self)

                # debugf"render: {self.targetCellPath}:{self.scrollOffset}"
                # echo fmt"scroll offset {self.scrollOffset}"
                try:
                  let myCtx = newCellLayoutContext(builder, self.cellWidgetContext, Direction.Forwards, true)
                  defer:
                    myCtx.finish()

                  myCtx.remainingHeightUp = self.scrollOffset - cellGenerationBuffer
                  myCtx.remainingHeightDown = (h - self.scrollOffset) - cellGenerationBuffer

                  var cursorFirst = self.selection.first.rootPath
                  var cursorLast = self.selection.last.rootPath
                  if cursorFirst.path.pathAfter(cursorLast.path):
                    swap(cursorFirst, cursorLast)

                  # debugf"target cell: {self.targetCellPath}"
                  cell.createCellUI(builder, app, myCtx, self.cellWidgetContext, false, self.targetCellPath, cursorFirst.path, cursorLast.path)

                except Defect:
                  log lvlError, fmt"failed to creat UI nodes {getCurrentExceptionMsg()}"

                if self.cellWidgetContext.targetNodeOld != self.cellWidgetContext.targetNode:
                  if self.cellWidgetContext.targetNodeOld.isNotNil:
                    self.cellWidgetContext.targetNodeOld.contentDirty = true
                  if self.cellWidgetContext.targetNode.isNotNil:
                    self.cellWidgetContext.targetNode.contentDirty = true

                self.cellWidgetContext.targetNodeOld = self.cellWidgetContext.targetNode

                # move the container position so the target cell is at the desired scroll offset
                if self.cellWidgetContext.targetNode.isNotNil:
                  var bounds = self.cellWidgetContext.targetNode.bounds.transformRect(self.cellWidgetContext.targetNode.parent, scrolledNode.parent)
                  # echo fmt"1 target node {bounds}: {self.cellWidgetContext.targetNode.dump}"
                  # echo scrolledNode.boundsRaw.y, " -> ", scrolledNode.boundsRaw.y + (self.scrollOffset - bounds.y)
                  # debugf"update scrolled node y: {scrolledNode.boundsRaw.y} -> {(scrolledNode.boundsRaw.y + (self.scrollOffset - bounds.y))}"
                  scrolledNode.rawY = scrolledNode.boundsRaw.y + (self.scrollOffset - bounds.y)
                  # echo fmt"2 target node {bounds}: {self.cellWidgetContext.targetNode.dump}"

                # update targetCellPath and scrollOffset to visible cell if currently outside of visible area
                if self.scrollOffset < cellGenerationBuffer + targetCellBuffer or self.scrollOffset >= h - cellGenerationBuffer - targetCellBuffer:
                  let forward = self.scrollOffset < cellGenerationBuffer + targetCellBuffer
                  if self.cellWidgetContext.updateTargetPath(scrolledNode.parent, cell, forward, self.targetCellPath, @[]).getSome(path):
                    # echo "update path ", path, " (was ", targetCellPath, ")"
                    # debugf"update target cell path: {self.targetCellPath}:{self.scrollOffset} -> {path[0]}:{path[1]}"
                    self.targetCellPath = path[1]
                    self.scrollOffset = path[0]

          # cursor
          proc drawCursor(cursor: CellCursor, thick: bool, cursorColor: Color, id: int32): Option[UINode] =
            if cursor.getTargetCell(true).getSome(targetCell) and self.cellWidgetContext.cellToWidget.contains(targetCell.id):
              let node = self.cellWidgetContext.cellToWidget[targetCell.id]
              # debugf"cursor {self.cursor} at {targetCell.dump}, {node.dump}"

              var bounds = rect(cursor.index.float * builder.charWidth, 0, 0, 0).transformRect(node, overlapPanel)
              let lx = node.lx + cursor.index.float * builder.charWidth

              if thick:
                let text = targetCell.getText
                let index = cursor.index.clamp(0, text.runeLen.int + 1).RuneIndex
                let ch = if index < text.runeLen.RuneIndex:
                  text[index..index]
                elif self.getNextCellInLine(targetCell).isNotNil(nextCell) and self.cellWidgetContext.cellToWidget.contains(nextCell.id):
                  let nextNode = self.cellWidgetContext.cellToWidget[nextCell.id]
                  let nextText = nextCell.getText()
                  if abs(nextNode.lx - lx) < 1 and nextText.len > 0:
                    nextText[0..0]
                  else:
                    " "
                else:
                  " "

                builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, SnapInitialBounds}, x = bounds.x, y = bounds.y, w = builder.charWidth, h = builder.textHeight, backgroundColor = textColor, userId = newSecondaryId(self.cursorsId, id)):
                  builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = backgroundColor, text = ch)
              else:
                builder.panel(&{UINodeFlag.FillBackground, AnimatePosition, SnapInitialBounds}, x = bounds.x, y = bounds.y, w = max(builder.charWidth * 0.2, 1), h = builder.textHeight, backgroundColor = cursorColor, userId = newSecondaryId(self.cursorsId, id))

              return node.some

          if self.cursorVisible and self.document.model.rootNodes.len > 0:
            if drawCursor(self.selection.last, self.isThickCursor, textColor, 0).getSome(node):
              self.lastCursorLocationBounds = rect(self.selection.last.index.float * builder.charWidth, 0, builder.charWidth, builder.textHeight).transformRect(node, builder.root).some

              let typ = self.document.ctx.computeType(self.selection.last.node).catch:
                log lvlError, fmt"failed to compute type {getCurrentExceptionMsg()}"
                nil
              let value = self.document.ctx.getValue(self.selection.last.node).catch:
                log lvlError, fmt"failed to compute value {getCurrentExceptionMsg()}"
                nil

              var scrollOffset = node.transformBounds(overlapPanel).y

              if typ.isNotNil or value.isNotNil:
                builder.panel(&{FillX, SizeToContentY, LayoutVertical}, y = scrollOffset):
                  # builder.panel(&{FillY}, pivot = vec2(1, 0), w = builder.charWidth)

                  if typ.isNotNil:
                    builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse}):
                      builder.panel(&{FillY}, pivot = vec2(1, 0), w = builder.charWidth)
                      builder.panel(&{SizeToContentX, SizeToContentY, LayoutVertical}, pivot = vec2(1, 0)):
                        builder.panel(&{FillX, SizeToContentY, DrawText, TextAlignHorizontalRight}, text = "Type", textColor = textColor)
                        builder.panel(&{SizeToContentX, SizeToContentY, DrawBorder}, borderColor = textColor):
                          let updateContext = UpdateContext(
                            nodeCellMap: self.detailsNodeCellMap,
                            cellToWidget: initTable[CellId, UINode](),
                            targetCellPosition: vec2(0, 0),
                            handleClick: proc(node: UINode, cell: Cell, path: seq[int], cursor: CellCursor, drag: bool) = discard,
                            setCursor: proc(cell: Cell, offset: int, drag: bool) = discard,
                          )
                          self.createNodeUI(builder, app, currentNode, updateContext, remainingHeightUp=0, remainingHeightDown=h, typ, @[0], 0)

                  if value.isNotNil:
                    if typ.isNotNil:
                      # builder.panel(&{FillY}, pivot = vec2(1, 0), w = builder.charWidth)
                      builder.panel(&{FillX}, h = builder.textHeight)

                    builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse}):
                      builder.panel(&{FillY}, pivot = vec2(1, 0), w = builder.charWidth)

                      builder.panel(&{SizeToContentX, SizeToContentY, LayoutVertical}, pivot = vec2(1, 0)):
                        builder.panel(&{FillX, SizeToContentY, DrawText, TextAlignHorizontalRight}, text = "Value", textColor = textColor)
                        builder.panel(&{SizeToContentX, SizeToContentY, DrawBorder}, borderColor = textColor):
                          let updateContext = UpdateContext(
                            nodeCellMap: self.detailsNodeCellMap,
                            cellToWidget: initTable[CellId, UINode](),
                            targetCellPosition: vec2(0, 0),
                            handleClick: proc(node: UINode, cell: Cell, path: seq[int], cursor: CellCursor, drag: bool) = discard,
                            setCursor: proc(cell: Cell, offset: int, drag: bool) = discard,
                          )
                          self.createNodeUI(builder, app, currentNode, updateContext, remainingHeightUp=0, remainingHeightDown=h, value, @[0], 0)

            if not self.selection.isEmpty:
              let cursorColor = textColor.darken(0.2)
              discard drawCursor(self.selection.first, not app.platform.supportsThinCursor, cursorColor, 1)

        # echo builder.currentChild.dump(true)

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))

method createUI*(self: ModelLanguageSelectorItem, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.name, textColor = textColor)

method createUI*(self: ModelImportSelectorItem, builder: UINodeBuilder, app: App): seq[proc() {.closure.}] =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.name, textColor = textColor)