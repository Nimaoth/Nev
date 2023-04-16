import std/[strformat, tables, sugar, sequtils, strutils]
import util, editor, document_editor, ast_document2, text_document, custom_logger, widgets, platform, theme, timer, widget_builder_text_document
import widget_builders_base
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor
import vmath, bumpy, chroma
import ast/[types, cells]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

proc createRawAstWidget*(node: AstNode, app: Editor, widget: WPanel, frameIndex: int) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let class = node.nodeClass

  var text = ""

  if class.isNil:
    text.add $node.class
  else:
    text.add class.name

  text.add "(id: " & $node.id & ")"

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  var textWidget = createPartWidget(text, 0, text.len.float * charWidth, totalLineHeight, textColor, frameIndex)
  widget.add textWidget

  var y = totalLineHeight

  for role in node.properties.mitems:
    var text = ""
    if class.isNotNil and class.propertyDescription(role.role).getSome(desc):
      text.add desc.role
    else:
      text.add $role.role
    text.add ": "
    text.add $role.value

    var textWidget = createPartWidget(text, 20, text.len.float * charWidth, totalLineHeight, textColor, frameIndex)
    textWidget.top = y
    textWidget.bottom = textWidget.top + totalLineHeight
    widget.add textWidget

    y = textWidget.bottom

  for role in node.references.mitems:
    var text = ""
    if class.isNotNil and class.nodeReferenceDescription(role.role).getSome(desc):
      text.add desc.role
    else:
      text.add $role.role
    text.add ": "
    text.add $role.node

    var textWidget = createPartWidget(text, 20, text.len.float * charWidth, totalLineHeight, textColor, frameIndex)
    textWidget.top = y
    textWidget.bottom = textWidget.top + totalLineHeight
    widget.add textWidget

    y = textWidget.bottom

  for role in node.childLists.mitems:
    var text = ""
    if class.isNotNil and class.nodeChildDescription(role.role).getSome(desc):
      text.add desc.role
    else:
      text.add $role.role
    text.add ": "

    var textWidget = createPartWidget(text, 20, text.len.float * charWidth, totalLineHeight, textColor, frameIndex)
    textWidget.top = y
    textWidget.bottom = textWidget.top + totalLineHeight
    widget.add textWidget

    for c in role.nodes:
      var childPanel = WPanel(left: 20 + text.len.float * charWidth, top: y, bottom: y, anchor: (vec2(0, 0), vec2(1, 0)), sizeToContent: true, drawBorder: true, foregroundColor: textColor)
      createRawAstWidget(c, app, childPanel, frameIndex)
      childPanel.layoutWidget(rect(20 + text.len.float * charWidth, y, 0, 0), frameIndex, app.platform.layoutOptions)
      widget.add childPanel

      y += childPanel.lastBounds.h + 2

proc updateBaseIndexAndScrollOffset(self: ModelDocumentEditor, app: Editor, contentPanel: WPanel) =
  let totalLineHeight = app.platform.totalLineHeight
  # self.previousBaseIndex = self.previousBaseIndex.clamp(0..self.document.rootNode.len)

  # let selectedNodeId = self.node.id

  # var replacements = initTable[Id, VisualNode]()

  # let indent = getOption[float32](app, "ast.indent", 20)
  # let inlineBlocks = getOption[bool](app, "ast.inline-blocks", false)
  # let verticalDivision = getOption[bool](app, "ast.vertical-division", false)

  # # Adjust scroll offset and base index so that the first node on screen is the base
  # while self.scrollOffset < 0 and self.previousBaseIndex + 1 < self.document.rootNode.len:
  #   let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: self.document.rootNode[self.previousBaseIndex], selectedNode: selectedNodeId, replacements: replacements, revision: config.revision, measureText: (t) => self.editor.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
  #   let layout = ctx.computeNodeLayout(input)

  #   if self.scrollOffset + layout.bounds.h + totalLineHeight >= contentPanel.lastBounds.h:
  #     break

  #   self.previousBaseIndex += 1
  #   self.scrollOffset += layout.bounds.h + totalLineHeight

  # # Adjust scroll offset and base index so that the first node on screen is the base
  # while self.scrollOffset > contentPanel.lastBounds.h and self.previousBaseIndex > 0:
  #   let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: self.document.rootNode[self.previousBaseIndex - 1], selectedNode: selectedNodeId, replacements: replacements, revision: config.revision, measureText: (t) => self.editor.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
  #   let layout = ctx.computeNodeLayout(input)

  #   if self.scrollOffset - layout.bounds.h <= 0:
  #     break

  #   self.previousBaseIndex -= 1
  #   self.scrollOffset -= layout.bounds.h + totalLineHeight

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
  # result.parentWidget.sizeToContent = true
  # result.parentWidget.layout = WPanelLayout(kind: Vertical)

  result.lineWidget = result.parentWidget.getOrCreate(result.currentLine, WPanel)
  result.lineWidget.anchor = (vec2(), vec2())
  # result.lineWidget.sizeToContent = true
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
  if self.hasIndent and self.lineWidget.children.len == 1:
    let indentWidget = self.lineWidget.children[0].WText
    indentWidget.text = self.indentText.repeat(self.currentIndent)
    let size = self.layoutOptions.getTextBounds indentWidget.text
    indentWidget.right = indentWidget.left + size.x
    indentWidget.bottom = size.y

    self.lineWidget.right = indentWidget.right
    self.lineWidget.bottom = max(self.lineWidget.bottom, self.lineWidget.top + size.y)

proc increaseIndent(self: CellLayoutContext) =
  inc self.currentIndent
  self.updateCurrentIndent()

proc decreaseIndent(self: CellLayoutContext) =
  dec self.currentIndent
  self.updateCurrentIndent()

proc indent(self: CellLayoutContext) =
  if self.currentIndent == 0 or self.indexInLine > 0:
    return

  self.hasIndent = true
  let indentWidget = self.lineWidget.getOrCreate(self.indexInLine, WText)
  indentWidget.left = self.lineWidget.right
  indentWidget.top = 0

  self.updateCurrentIndent()

  inc self.indexInLine

proc addSpace(self: CellLayoutContext) =
  if self.currentLineEmpty:
    return
  let indentWidget = self.lineWidget.getOrCreate(self.indexInLine, WText)
  # indentWidget.sizeToContent = true
  indentWidget.text = " "

  let size = self.layoutOptions.getTextBounds indentWidget.text
  indentWidget.left = self.lineWidget.right
  indentWidget.right = indentWidget.left + size.x
  indentWidget.top = 0
  indentWidget.bottom = size.y

  self.lineWidget.right = indentWidget.right
  self.lineWidget.bottom = max(self.lineWidget.bottom, self.lineWidget.top + size.y)

  inc self.indexInLine

proc newLine(self: CellLayoutContext) =
  if self.lineWidget.isNotNil:
    self.lineWidget.truncate(self.indexInLine)
    self.parentWidget[self.currentLine] = self.lineWidget
    self.parentWidget.right = max(self.parentWidget.right, self.lineWidget.right)
    self.parentWidget.bottom = max(self.parentWidget.bottom, self.lineWidget.bottom)
    inc self.currentLine


  self.lineWidget = self.parentWidget.getOrCreate(self.currentLine, WPanel)
  # self.lineWidget.sizeToContent = true
  # self.lineWidget.layout = WPanelLayout(kind: Horizontal)
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

method updateCellWidget*(cell: Cell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget {.base.} = widget

method updateCellWidget*(cell: ConstantCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  # widget.sizeToContent = true
  let size = app.platform.layoutOptions.getTextBounds cell.text
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  widget.text = cell.getText()

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  widget.foregroundColor = textColor

method updateCellWidget*(cell: AliasCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  # widget.sizeToContent = true

  widget.text = cell.getText()

  let size = app.platform.layoutOptions.getTextBounds widget.text
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  widget.foregroundColor = textColor

method updateCellWidget*(cell: NodeReferenceCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WPanel: widget.WPanel else: WPanel()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  # widget.sizeToContent = true

  if cell.child.isNil:
    var text = if widget.len > 0 and widget[0] of WText: widget[0].WText else: WText()
    # text.sizeToContent = true

    let reference = cell.node.reference(cell.reference)
    text.text = $reference

    let size = app.platform.layoutOptions.getTextBounds text.text
    text.left = 0
    text.right = size.x
    text.top = 0
    text.bottom = size.y

    let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
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

method updateCellWidget*(cell: PropertyCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  updateContext.cellToWidget[cell.id] = widget

  # widget.sizeToContent = true
  let value = cell.node.property(cell.property)
  if value.getSome(value):
    case value.kind
    of String:
      widget.text = value.stringValue
    of Int:
      widget.text = $value.intValue
    of Bool:
      widget.text = $value.boolValue
  else:
    widget.text = "<empty>"

  let size = app.platform.layoutOptions.getTextBounds widget.text
  widget.left = 0
  widget.right = size.x
  widget.top = 0
  widget.bottom = size.y

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  widget.foregroundColor = textColor

method updateCellWidget*(cell: CollectionCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext, updateContext: UpdateContext): WWidget =
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

proc updateSelections(self: ModelDocumentEditor, app: Editor, cell: Cell, cursor: Option[CellCursor], primary: bool, reverse: bool) =
  let charWidth = app.platform.charWidth
  let secondaryColor = app.theme.color("inputValidation.warningBorder", color(1, 1, 1)).withAlpha(0.25)
  let primaryColor = app.theme.color("selection.background", color(1, 1, 1)).withAlpha(0.25)

  # debugf"updateSelections "

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

    # debugf"secondary {startIndex}..{endIndex}"
    for i in startIndex..endIndex:
      self.updateSelections(app, coll.children[i], CellCursor.none, false, reverse)

    # debugf"primary {primaryIndex}"
    self.updateSelections(app, coll.children[primaryIndex], CellCursor.none, primary, reverse)

  elif cursor.getSome(cursor):
    let widget = self.cellWidgetContext.cellToWidget.getOrDefault(cell.id)
    if widget.isNotNil:
      widget.fillBackground = true
      widget.allowAlpha = true
      widget.backgroundColor = secondaryColor

      var parent = widget.parent.WPanel
      if parent.isNotNil:
        var cursorWidget = WPanel(top: widget.top, bottom: widget.bottom, fillBackground: true, allowAlpha: true, backgroundColor: primaryColor.withAlpha(1))

        let text = cell.getText()
        if text.len == 0:
          cursorWidget.left = widget.left
          cursorWidget.right = cursorWidget.left + 0.2 * charWidth
        else:
          let alpha1 = cursor.firstIndex.float / text.len.float
          let alpha2 = cursor.lastIndex.float / text.len.float

          if cursor.firstIndex != cursor.lastIndex:
            var selectionWidget = WPanel(top: widget.top, bottom: widget.bottom, fillBackground: true, allowAlpha: true, backgroundColor: primaryColor)
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

method updateWidget*(self: ModelDocumentEditor, app: Editor, widget: WPanel, frameIndex: int) =
  let lineHeight = app.platform.lineHeight
  let totalLineHeight = app.platform.totalLineHeight
  let lineDistance = app.platform.lineDistance
  let charWidth = app.platform.charWidth

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var headerPanel: WPanel
  var headerPart1Text: WText
  var headerPart2Text: WText
  var contentPanel: WPanel
  if widget.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    widget.add(headerPanel)

    headerPart1Text = WText(text: "", sizeToContent: true, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.add(headerPart1Text)

    headerPart2Text = WText(text: "", sizeToContent: true, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.add(headerPart2Text)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
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

    let color = if self.active: app.theme.color("tab.activeBackground", rgb(45, 45, 60))
    else: app.theme.color("tab.inactiveBackground", rgb(45, 45, 45))
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
    if self.active: app.theme.color("editor.background", rgb(25, 25, 40)) else: app.theme.color("editor.background", rgb(25, 25, 25)) * 0.75,
    frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty or app.platform.redrawEverything):
    return

  self.resetDirty()

  # either layout or content changed, update the lines
  let timer = startTimer()
  contentPanel.setLen 0

  self.updateBaseIndexAndScrollOffset(app, contentPanel)

  var rendered = 0

  # for node in self.document.model.rootNodes:
  #   createRawAstWidget(node, app, contentPanel, frameIndex)

  var builder = self.document.builder
  var lastY = self.scrollOffset

  if self.cellWidgetContext.isNil:
    self.cellWidgetContext = UpdateContext()
  self.cellWidgetContext.cellToWidget.clear()

  # echo self.cursor.cell.line

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
        widget.del(i)
      continue

    newWidget.sizeToContent = true
    newWidget.top = lastY

    # echo newWidget

    if i < contentPanel.len:
      contentPanel[i] = newWidget
    else:
      contentPanel.add newWidget

    inc i

  if self.getCellForCursor(self.cursor, false).getSome(cell):
    self.updateSelections(app, cell, self.cursor.some, true, self.cursor.firstIndex > self.cursor.lastIndex)

  let indent = getOption[float32](app, "model.indent", 20)
  let inlineBlocks = getOption[bool](app, "model.inline-blocks", false)
  let verticalDivision = getOption[bool](app, "model.vertical-division", false)

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {rendered} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"
