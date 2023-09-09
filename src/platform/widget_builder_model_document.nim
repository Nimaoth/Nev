import std/[strformat, tables, sugar, strutils]
import util, app, document_editor, model_document, text/text_document, custom_logger, widgets, platform, theme, widget_builder_text_document
import widget_builders_base
import vmath, bumpy, chroma
import ast/[types, cells]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)


proc updateBaseIndexAndScrollOffset(self: ModelDocumentEditor, app: App, contentPanel: WPanel) =
  # let totalLineHeight = app.platform.totalLineHeight
  discard

type CellLayoutContext = ref object
  currentLine: int
  indexInLine: int
  currentIndent: int
  parentWidget: WPanel
  lineWidget: WPanel
  currentLineEmpty: bool
  hasIndent: bool
  prevNoSpaceRight: bool
  layoutOptions: WLayoutOptions
  indentText: string

proc newCellLayoutContext(widget: WWidget): CellLayoutContext =
  new result
  result.parentWidget = widget.getOrCreate(WPanel)
  result.parentWidget.anchor = (vec2(), vec2())
  result.parentWidget.left = 0
  result.parentWidget.right = 0
  result.parentWidget.top = 0
  result.parentWidget.bottom = 0

  result.lineWidget = result.parentWidget.getOrCreate(result.currentLine, WPanel)
  result.lineWidget.anchor = (vec2(), vec2())
  result.lineWidget.left = 0
  result.lineWidget.right = 0
  result.lineWidget.top = 0
  result.lineWidget.bottom = 0

  result.indentText = "  "

  result.currentLineEmpty = true

proc isCurrentLineEmpty(self: CellLayoutContext): bool = self.currentLineEmpty

proc getCurrentYOffset(self: CellLayoutContext): float =
  return if self.currentLine in 1..self.parentWidget.high: self.parentWidget[self.currentLine - 1].bottom else: 0

proc getReusableWidget(self: CellLayoutContext): WWidget =
  if self.indexInLine < self.lineWidget.len:
    return self.lineWidget[self.indexInLine]
  else:
    return nil

proc updateCurrentIndent(self: CellLayoutContext) =
  if self.hasIndent and self.lineWidget.children.len == 0:
    let size = self.layoutOptions.getTextBounds self.indentText.repeat(self.currentIndent)
    self.lineWidget.right = size.x

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
  if self.currentLineEmpty:
    return

  let size = self.layoutOptions.getTextBounds " "
  self.lineWidget.right += size.x

proc newLine(self: CellLayoutContext) =
  if self.lineWidget.isNotNil:
    self.lineWidget.truncate(self.indexInLine)
    self.parentWidget[self.currentLine] = self.lineWidget
    self.parentWidget.right = max(self.parentWidget.right, self.lineWidget.right)
    self.parentWidget.bottom = max(self.parentWidget.bottom, self.lineWidget.bottom)
    inc self.currentLine


  self.lineWidget = self.parentWidget.getOrCreate(self.currentLine, WPanel)
  self.indexInLine = 0
  self.currentLineEmpty = true

  self.lineWidget.left = 0
  self.lineWidget.right = 0
  self.lineWidget.top = self.getCurrentYOffset
  self.lineWidget.bottom = self.lineWidget.top

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
  self.currentLineEmpty = false

proc finish(self: CellLayoutContext): WWidget =
  if self.lineWidget.len > 0:
    self.parentWidget[self.currentLine] = self.lineWidget
    self.parentWidget.right = max(self.parentWidget.right, self.lineWidget.right)
    self.parentWidget.bottom = max(self.parentWidget.bottom, self.lineWidget.bottom)
    inc self.currentLine

  self.parentWidget.truncate(self.currentLine)

  return self.parentWidget

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

proc setBackgroundColor(app: App, cell: Cell, widget: WWidget) =
  let defaultColor = if cell.backgroundColor.a != 0: cell.backgroundColor else: color(0, 0, 0, 0)
  let backgroundColor = if cell.themeBackgroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeBackgroundColors, defaultColor)
  widget.backgroundColor = backgroundColor
  widget.fillBackground = backgroundColor.a != 0
  widget.allowAlpha = true

method updateCellWidget*(cell: Cell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget {.base.} = widget

method updateCellWidget*(cell: PlaceholderCell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  let (text, color) = app.getTextAndColor(cell)
  widget.text = text
  widget.foregroundColor = color

  widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  let size = app.platform.layoutOptions.getTextBounds(widget.text, widget.fontSizeIncreasePercent)
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  setBackgroundColor(app, cell, widget)

method updateCellWidget*(cell: ConstantCell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  let (text, color) = app.getTextAndColor(cell)
  widget.text = text
  widget.foregroundColor = color

  widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  let size = app.platform.layoutOptions.getTextBounds(widget.text, widget.fontSizeIncreasePercent)
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  setBackgroundColor(app, cell, widget)

method updateCellWidget*(cell: AliasCell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  let (text, color) = app.getTextAndColor(cell)
  widget.text = text
  widget.foregroundColor = color

  widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  let size = app.platform.layoutOptions.getTextBounds(widget.text, widget.fontSizeIncreasePercent)
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  setBackgroundColor(app, cell, widget)

method updateCellWidget*(cell: NodeReferenceCell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WPanel: widget.WPanel else: WPanel()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  if cell.child.isNil:
    var text = if widget.len > 0 and widget[0] of WText: widget[0].WText else: WText()

    let reference = cell.node.reference(cell.reference)
    text.text = $reference

    widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
    let size = app.platform.layoutOptions.getTextBounds(text.text, widget.fontSizeIncreasePercent)
    text.left = 0
    text.right = size.x
    text.top = 0
    text.bottom = size.y

    let defaultColor = if cell.foregroundColor.a != 0: cell.foregroundColor else: color(1, 1, 1)
    let textColor = if cell.themeForegroundColors.len == 0: defaultColor else: app.theme.anyColor(cell.themeForegroundColors, defaultColor)
    text.foregroundColor = textColor

    if 0 < widget.len:
      widget[0] = text
    else:
      widget.add text

    widget.left = 0
    widget.right = text.right
    widget.top = 0
    widget.bottom = text.bottom

  else:
    let oldWidget: WWidget = if 0 < widget.len: widget[0] else: nil
    let newWidget = cell.child.updateCellWidget(app, oldWidget, frameIndex, ctx, updateContext)
    if newWidget.isNil:
      widget.setLen 0
      return

    if 0 < widget.len:
      widget[0] = newWidget
    else:
      widget.add newWidget

    widget.left = 0
    widget.right = newWidget.right
    widget.top = 0
    widget.bottom = newWidget.bottom

  setBackgroundColor(app, cell, widget)

method updateCellWidget*(cell: PropertyCell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  let (text, color) = app.getTextAndColor(cell)
  widget.text = text
  widget.foregroundColor = color

  widget.fontSizeIncreasePercent = cell.fontSizeIncreasePercent
  let size = app.platform.layoutOptions.getTextBounds(widget.text, widget.fontSizeIncreasePercent)
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  setBackgroundColor(app, cell, widget)

method updateCellWidget*(cell: CollectionCell, app: App, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  # debugf"updateCellWidget {cell.node}"

  let myCtx = if ctx.isNil or cell.inline:
    newCellLayoutContext(widget)
  else:
    ctx

  updateContext.cellToWidget[cell.id] = myCtx.parentWidget

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
    # if myCtx.currentLine > 200:
    #   break

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

    let oldWidget = myCtx.getReusableWidget()
    let newWidget = c.updateCellWidget(app, oldWidget, frameIndex, myCtx, updateContext)
    if newWidget.isNotNil:
      myCtx.addWidget(newWidget, spaceLeft)

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
    return myCtx.finish()
  else:
    return nil

proc updateSelections(self: ModelDocumentEditor, app: App, cell: Cell, cursor: Option[CellCursor], primary: bool, reverse: bool) =
  let charWidth = app.platform.charWidth
  let secondaryColor = app.theme.color("inputValidation.warningBorder", color(1, 1, 1)).withAlpha(0.25)
  let primaryColor = app.theme.color("selection.background", color(1, 1, 1)).withAlpha(0.25)

  if cell of CollectionCell:
    let coll = cell.CollectionCell

    var startIndex = if reverse: 1 else: 0
    var endIndex = if reverse: coll.children.high else: coll.children.high - 1
    var primaryIndex = if reverse: 0 else: coll.children.high
    if cursor.getSome(cursor):
      primaryIndex = cursor.lastIndex
      if cursor.firstIndex < cursor.lastIndex:
        startIndex = cursor.firstIndex
        endIndex = cursor.lastIndex - 1
      else:
        startIndex = cursor.lastIndex + 1
        endIndex = cursor.firstIndex

    for i in startIndex..endIndex:
      self.updateSelections(app, coll.children[i], CellCursor.none, false, reverse)

    if coll.children.len > 0:
      self.updateSelections(app, coll.children[primaryIndex], CellCursor.none, primary, reverse)

  elif cursor.getSome(cursor):
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id)
    if widget.isNotNil:
      widget.fillBackground = true
      widget.allowAlpha = true
      widget.backgroundColor = secondaryColor

      var parent = widget.parent.WPanel
      if parent.isNotNil:
        var cursorWidget = WPanel(top: widget.top, bottom: widget.bottom, flags: &{FillBackground, AllowAlpha}, backgroundColor: primaryColor.withAlpha(1))

        let text = cell.currentText
        if text.len == 0:
          cursorWidget.left = widget.left
          cursorWidget.right = cursorWidget.left + 0.2 * charWidth
        else:
          let alpha1 = cursor.firstIndex.float / text.len.float
          let alpha2 = cursor.lastIndex.float / text.len.float

          if cursor.firstIndex != cursor.lastIndex:
            var selectionWidget = WPanel(top: widget.top, bottom: widget.bottom, flags: &{FillBackground, AllowAlpha}, backgroundColor: primaryColor)
            selectionWidget.left = widget.left * (1 - min(alpha1, alpha2)) + widget.right * min(alpha1, alpha2)
            selectionWidget.right = widget.left * (1 - max(alpha1, alpha2)) + widget.right * max(alpha1, alpha2)
            parent.add selectionWidget

          cursorWidget.left = widget.left * (1 - alpha2) + widget.right * alpha2
          cursorWidget.right = cursorWidget.left + 0.2 * charWidth

        parent.add cursorWidget

  else:
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id)
    if widget.isNotNil:
      widget.fillBackground = true
      widget.allowAlpha = true
      widget.backgroundColor = if primary: primaryColor else: secondaryColor

proc renderCompletions(self: ModelDocumentEditor, app: App, contentPanel: WPanel, cursorBounds: Rect, frameIndex: int) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let backgroundColor = app.theme.color("panel.background", color(30/255, 30/255, 30/255))
  let selectedBackgroundColor = app.theme.color("list.activeSelectionBackground", color(200/255, 200/255, 200/255))
  let nameColor = app.theme.tokenColor(@["entity.name.label", "entity.name"], color(255/255, 255/255, 255/255))
  let textColor = app.theme.color("list.inactiveSelectionForeground", color(175/255, 175/255, 175/255))
  let scopeColor = app.theme.color("string", color(175/255, 255/255, 175/255))

  var panel = WPanel(
    left: cursorBounds.x, top: cursorBounds.yh, right: cursorBounds.x + charWidth * 60.0, bottom: cursorBounds.yh + totalLineHeight * 20.0,
    flags: &{FillBackground}, backgroundColor: backgroundColor, lastHierarchyChange: frameIndex, maskContent: true)
  panel.layoutWidget(contentPanel.lastBounds, frameIndex, app.platform.layoutOptions)
  contentPanel.add(panel)

  self.lastCompletionsWidget = panel

  updateBaseIndexAndScrollOffset(panel.lastBounds.h, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, totalLineHeight, self.scrollToCompletion)
  self.scrollToCompletion = int.none

  self.lastItems.setLen 0

  proc renderLine(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool =
    # Pixel coordinate of the top left corner of the entire line. Includes line number
    if i == self.selectedCompletion:
      lineWidget.fillBackground = true
      lineWidget.backgroundColor = selectedBackgroundColor

    let completion = self.completions[i]
    let name = completion.name

    case completion.kind
    of ModelCompletionKind.SubstituteClass:
      let nameWidget = createPartWidget(name, 0, name.len.float * charWidth, totalLineHeight, textColor, frameIndex)
      lineWidget.add(nameWidget)

    of ModelCompletionKind.SubstituteReference:
      let nameWidget = createPartWidget(name, 0, name.len.float * charWidth, totalLineHeight, nameColor, frameIndex)
      lineWidget.add(nameWidget)

      let className = if completion.class.alias.len > 0: completion.class.alias else: completion.class.name

      var scopeWidget = createPartWidget(className, -className.len.float * charWidth, totalLineHeight, className.len.float * charWidth, scopeColor, frameIndex)
      scopeWidget.anchor.min.x = 1
      scopeWidget.anchor.max.x = 1
      lineWidget.add(scopeWidget)

    self.lastItems.add (i, lineWidget)

    return true

  app.createLinesInPanel(panel, self.completionsBaseIndex, self.completionsScrollOffset, self.completions.len, frameIndex, onlyRenderInBounds=true, renderLine)

method updateWidget*(self: ModelDocumentEditor, app: App, widget: WPanel, completionsPanel: WPanel, frameIndex: int) =
  let totalLineHeight = app.platform.totalLineHeight

  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

  var headerPanel: WPanel
  var headerPart1Text: WText
  var headerPart2Text: WText
  var contentPanel: WPanel
  if widget.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    widget.add(headerPanel)

    headerPart1Text = WText(text: "", flags: &{SizeToContent}, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.add(headerPart1Text)

    headerPart2Text = WText(text: "", flags: &{SizeToContent}, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.add(headerPart2Text)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
  else:
    headerPanel = widget[0].WPanel
    headerPart1Text = headerPanel[0].WText
    headerPart2Text = headerPanel[1].WText
    contentPanel = widget[1].WPanel

  # Update header
  if self.renderHeader:
    headerPanel.bottom = totalLineHeight
    contentPanel.top = totalLineHeight

    let color = if self.active: app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
    else: app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
    headerPanel.updateBackgroundColor(color, frameIndex)

    let workspaceName = self.document.workspace.map(wf => " - " & wf.name).get("")

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPart1Text.text = fmt" {mode} - {self.document.filename} {workspaceName} "
    headerPart2Text.text = fmt" {self.id} "

    headerPanel.updateLastHierarchyChangeFromChildren frameIndex
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  self.lastBounds = contentPanel.lastBounds
  self.lastContentBounds = widget.lastBounds
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.updateBackgroundColor(
    if self.active: app.theme.color("editor.background", color(25/255, 25/255, 40/255)) else: app.theme.color("editor.background", color(25/255, 25/255, 25/255)) * 0.75,
    frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty or app.platform.redrawEverything):
    return

  self.resetDirty()

  # either layout or content changed, update the lines
  contentPanel.setLen 0

  self.updateBaseIndexAndScrollOffset(app, contentPanel)

  var lastY = self.scrollOffset

  if self.cellWidgetContext.isNil:
    self.cellWidgetContext = UpdateContext()
  self.cellWidgetContext.cellToWidget = initTable[Id, WWidget](self.cellWidgetContext.cellToWidget.len)

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

    # echo cell.dump()

    let oldWidget: WWidget = if i < contentPanel.len: contentPanel[i] else: nil
    let newWidget = cell.updateCellWidget(app, oldWidget, frameIndex, nil, self.cellWidgetContext)
    if newWidget.isNil:
      if oldWidget.isNotNil:
        widget.delete i
      continue

    newWidget.sizeToContent = true
    newWidget.top = lastY

    # echo newWidget

    if i < contentPanel.len:
      contentPanel[i] = newWidget
    else:
      contentPanel.add newWidget


    newWidget.layoutWidget(contentPanel.lastBounds, frameIndex, app.platform.layoutOptions)

    inc i

  if self.cursor.getTargetCell(false).getSome(cell):
    self.updateSelections(app, cell, self.cursor.some, true, self.cursor.firstIndex > self.cursor.lastIndex)

  if self.showCompletions:
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(self.cursor.targetCell.id)
    self.renderCompletions(app, contentPanel, widget.lastBounds - contentPanel.lastBounds.xy, frameIndex)

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {rendered} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"
