import std/[strformat, tables, sugar, strutils]
import util, app, document_editor, model_document, text/text_document, custom_logger, widgets, platform, theme, widget_builder_text_document, config_provider
import widget_builders_base, widget_library, ui/node
import vmath, bumpy, chroma
import ast/[types, cells]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

proc updateBaseIndexAndScrollOffset(self: ModelDocumentEditor, app: App, contentPanel: WPanel) =
  # let totalLineHeight = app.platform.totalLineHeight
  discard

type CellLayoutContext = ref object
  builder: UINodeBuilder
  currentLine: int
  indexInLine: int
  currentIndent: int
  # parentWidget: WPanel
  lineWidget: WPanel
  parentNode: UINode
  lineNode: UINode
  indentNode: UINode
  hasIndent: bool
  prevNoSpaceRight: bool
  layoutOptions: WLayoutOptions
  indentText: string

proc newCellLayoutContext(builder: UINodeBuilder, widget: WWidget): CellLayoutContext =
  new result

  var noneId = noneUserId()

  result.builder = builder
  result.parentNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutVertical}, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)

  result.lineNode = builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutHorizontal}, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
  builder.panel(&{FillY}):
    result.indentNode = currentNode

  result.indentText = "  "

proc isCurrentLineEmpty(self: CellLayoutContext): bool =
  return self.builder.currentChild == self.indentNode

proc updateCurrentIndent(self: CellLayoutContext) =
  if self.hasIndent and self.isCurrentLineEmpty():
    let size = self.layoutOptions.getTextBounds self.indentText.repeat(self.currentIndent)
    self.indentNode.w = size.x

proc increaseIndent(self: CellLayoutContext) =
  inc self.currentIndent
  self.updateCurrentIndent()

proc decreaseIndent(self: CellLayoutContext) =
  if self.currentIndent == 0:
    return
  dec self.currentIndent
  self.updateCurrentIndent()

proc indent(self: CellLayoutContext) =
  if self.currentIndent == 0 or self.indexInLine > 0:
    return

  self.hasIndent = true
  self.updateCurrentIndent()

proc addSpace(self: CellLayoutContext) =
  if self.isCurrentLineEmpty:
    return

  let size = self.layoutOptions.getTextBounds " "
  self.builder.panel(&{FillY}, w = size.x)

proc newLine(self: CellLayoutContext) =
  inc self.currentLine

  self.builder.finishNode(self.lineNode)

  var noneId = noneUserId()
  self.lineNode = self.builder.prepareNode(&{SizeToContentX, SizeToContentY, LayoutHorizontal}, string.none, float32.none, float32.none, float32.none, float32.none, Vec2.none, noneId, UINodeFlags.none)
  self.builder.panel(&{FillY}):
    self.indentNode = currentNode

  self.indexInLine = 0

  self.hasIndent = false

  self.indent()

proc addWidget(self: CellLayoutContext, widget: WWidget, spaceLeft: bool) =
  let width = widget.right
  let height = widget.bottom

  self.lineWidget[self.indexInLine] = nil
  if spaceLeft:
    self.addSpace()

  widget.left = self.lineWidget.right
  widget.right = widget.left + width
  widget.top = 0
  widget.bottom = height

  self.lineWidget.right = widget.right
  self.lineWidget.bottom = max(self.lineWidget.bottom, self.lineWidget.top + height)

  self.lineWidget[self.indexInLine] = widget
  inc self.indexInLine

proc finish(self: CellLayoutContext) =
  self.builder.finishNode(self.lineNode)
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

method updateCellWidget*(cell: Cell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget {.base.} = widget

# proc updateSelections(self: ModelDocumentEditor, app: App, cell: Cell, cursor: Option[CellCursor], primary: bool, reverse: bool) =
#   let charWidth = app.platform.charWidth
#   let secondaryColor = app.theme.color("inputValidation.warningBorder", color(1, 1, 1)).withAlpha(0.25)
#   let primaryColor = app.theme.color("selection.background", color(1, 1, 1)).withAlpha(0.25)

#   if cell of CollectionCell:
#     let coll = cell.CollectionCell

#     var startIndex = if reverse: 1 else: 0
#     var endIndex = if reverse: coll.children.high else: coll.children.high - 1
#     var primaryIndex = if reverse: 0 else: coll.children.high
#     if cursor.getSome(cursor):
#       primaryIndex = cursor.lastIndex
#       if cursor.firstIndex < cursor.lastIndex:
#         startIndex = cursor.firstIndex
#         endIndex = cursor.lastIndex - 1
#       else:
#         startIndex = cursor.lastIndex + 1
#         endIndex = cursor.firstIndex

#     for i in startIndex..endIndex:
#       self.updateSelections(app, coll.children[i], CellCursor.none, false, reverse)

#     if coll.children.len > 0:
#       self.updateSelections(app, coll.children[primaryIndex], CellCursor.none, primary, reverse)

#   elif cursor.getSome(cursor):
#     let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id)
#     if widget.isNotNil:
#       widget.fillBackground = true
#       widget.allowAlpha = true
#       widget.backgroundColor = secondaryColor

#       var parent = widget.parent.WPanel
#       if parent.isNotNil:
#         var cursorWidget = WPanel(top: widget.top, bottom: widget.bottom, flags: &{FillBackground, AllowAlpha}, backgroundColor: primaryColor.withAlpha(1))

#         let text = cell.currentText
#         if text.len == 0:
#           cursorWidget.left = widget.left
#           cursorWidget.right = cursorWidget.left + 0.2 * charWidth
#         else:
#           let alpha1 = cursor.firstIndex.float / text.len.float
#           let alpha2 = cursor.lastIndex.float / text.len.float

#           if cursor.firstIndex != cursor.lastIndex:
#             var selectionWidget = WPanel(top: widget.top, bottom: widget.bottom, flags: &{FillBackground, AllowAlpha}, backgroundColor: primaryColor)
#             selectionWidget.left = widget.left * (1 - min(alpha1, alpha2)) + widget.right * min(alpha1, alpha2)
#             selectionWidget.right = widget.left * (1 - max(alpha1, alpha2)) + widget.right * max(alpha1, alpha2)
#             parent.add selectionWidget

#           cursorWidget.left = widget.left * (1 - alpha2) + widget.right * alpha2
#           cursorWidget.right = cursorWidget.left + 0.2 * charWidth

#         parent.add cursorWidget

#   else:
#     let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id)
#     if widget.isNotNil:
#       widget.fillBackground = true
#       widget.allowAlpha = true
#       widget.backgroundColor = if primary: primaryColor else: secondaryColor

# method updateWidget*(self: ModelDocumentEditor, app: App, widget: WPanel, completionsPanel: WPanel, frameIndex: int) =
#   if self.cursor.getTargetCell(false).getSome(cell):
#     self.updateSelections(app, cell, self.cursor.some, true, self.cursor.firstIndex > self.cursor.lastIndex)

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

method createCellUI*(cell: Cell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) {.base.} = discard

method createCellUI*(cell: ConstantCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId)
  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: PlaceholderCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId)
  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: AliasCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId)
  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: NodeReferenceCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  # updateContext.cellToWidget[cell.id] = widget
  if cell.child.isNil:
    let reference = cell.node.reference(cell.reference)
    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)

    if spaceLeft:
      ctx.addSpace()

    builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = $reference, textColor = textColor, userId = cell.id.newPrimaryId)

    # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent

  else:
    cell.child.createCellUI(builder, app, ctx, updateContext, spaceLeft)

  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: PropertyCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  if spaceLeft:
    ctx.addSpace()

  # updateContext.cellToWidget[cell.id] = widget
  let (text, color) = app.getTextAndColor(cell)
  builder.panel(&{SizeToContentX, SizeToContentY, FillY, DrawText}, text = text, textColor = color, userId = cell.id.newPrimaryId)
  # widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  # setBackgroundColor(app, cell, widget)

method createCellUI*(cell: CollectionCell, builder: UINodeBuilder, app: App, ctx: CellLayoutContext, updateContext: UpdateContext, spaceLeft: bool) =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return

  # debugf"updateCellWidget {cell.node}"

  let myCtx = if ctx.isNil or cell.inline:
    if spaceLeft and ctx.isNotNil:
      ctx.addSpace()

    newCellLayoutContext(builder, nil)
  else:
    ctx

  # updateContext.cellToWidget[cell.id] = myCtx.parentWidget

  myCtx.layoutOptions = app.platform.layoutOptions

  cell.fill()

  let vertical = cell.layout.kind == Vertical

  if cell.style.isNotNil and cell.style.indentChildren:
    myCtx.increaseIndent()
    myCtx.indent()

  defer:
    if cell.style.isNotNil and cell.style.indentChildren:
      myCtx.decreaseIndent()

  for i, c in cell.children:
    if myCtx.currentLine > 200:
      break

    if c.increaseIndentBefore:
      myCtx.increaseIndent()

    if c.decreaseIndentBefore:
      myCtx.decreaseIndent()

    if vertical and (i > 0 or not myCtx.isCurrentLineEmpty()):
      myCtx.newLine()

    var spaceLeft = not myCtx.prevNoSpaceRight
    if c.style.isNotNil:
      if c.style.onNewLine and not myCtx.isCurrentLineEmpty():
        myCtx.newLine()
      if c.style.noSpaceLeft:
        spaceLeft = false

    c.createCellUI(builder, app, myCtx, updateContext, spaceLeft)

    if c.increaseIndentAfter:
      myCtx.increaseIndent()

    if c.decreaseIndentAfter:
      myCtx.decreaseIndent()

    myCtx.prevNoSpaceRight = false
    if c.style.isNotNil:
      if c.style.addNewlineAfter:
        myCtx.newLine()
      myCtx.prevNoSpaceRight = c.style.noSpaceRight

  if myCtx != ctx:
    myCtx.finish()

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
  self.cellWidgetContext.cellToWidget = initTable[Id, WWidget](self.cellWidgetContext.cellToWidget.len)

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
              if not self.nodeToCell.contains(node.id):
                self.rebuildCells()

              if not self.nodeToCell.contains(node.id):
                continue

              # let cell = builder.buildCell(node)
              let cell = self.nodeToCell[node.id]
              if cell.isNil:
                continue

              cell.createCellUI(builder, app, nil, self.cellWidgetContext, false)

              inc i

            defer:
              self.lastBounds = currentNode.bounds

  if self.showCompletions and self.active:
    result.add proc() =
      self.createCompletions(builder, app, self.lastCursorLocationBounds.get(rect(100, 100, 10, 10)))