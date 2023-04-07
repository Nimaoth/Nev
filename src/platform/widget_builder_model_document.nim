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
  widget.children.add textWidget

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
    widget.children.add textWidget

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
    widget.children.add textWidget

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
    widget.children.add textWidget

    for c in role.nodes:
      var childPanel = WPanel(left: 20 + text.len.float * charWidth, top: y, bottom: y, anchor: (vec2(0, 0), vec2(1, 0)), sizeToContent: true, drawBorder: true, foregroundColor: textColor)
      createRawAstWidget(c, app, childPanel, frameIndex)
      childPanel.layoutWidget(rect(20 + text.len.float * charWidth, y, 0, 0), frameIndex, app.platform.layoutOptions)
      widget.children.add childPanel

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
  prevNoSpaceRight: bool

proc newCellLayoutContext(widget: WWidget): CellLayoutContext =
  new result
  result.parentWidget = widget.getOrCreate(WPanel)
  result.parentWidget.sizeToContent = true
  result.parentWidget.layout = WPanelLayout(kind: Vertical)
  result.lineWidget = result.parentWidget.getOrCreate(result.currentLine, WPanel)
  result.lineWidget.sizeToContent = true
  result.lineWidget.layout = WPanelLayout(kind: Horizontal)
  result.currentLineEmpty = true

proc isCurrentLineEmpty(self: CellLayoutContext): bool = self.currentLineEmpty

proc getReusableWidget(self: CellLayoutContext): WWidget =
  if self.indexInLine < self.lineWidget.children.len:
    return self.lineWidget.children[self.indexInLine]
  else:
    return nil

proc indent(self: CellLayoutContext) =
  if self.currentIndent == 0 or self.indexInLine > 0:
    return
  let indentWidget = self.lineWidget.getOrCreate(self.indexInLine, WText)
  indentWidget.sizeToContent = true
  indentWidget.text = "    ".repeat(self.currentIndent)
  inc self.indexInLine

proc addSpace(self: CellLayoutContext) =
  if self.currentLineEmpty:
    return
  let indentWidget = self.lineWidget.getOrCreate(self.indexInLine, WText)
  indentWidget.sizeToContent = true
  indentWidget.text = " "
  inc self.indexInLine

proc newLine(self: CellLayoutContext) =
  if self.lineWidget.isNotNil:
    self.lineWidget.truncate(self.indexInLine)
    self.parentWidget[self.currentLine] = self.lineWidget
    inc self.currentLine
  self.lineWidget = self.parentWidget.getOrCreate(self.currentLine, WPanel)
  self.lineWidget.sizeToContent = true
  self.lineWidget.layout = WPanelLayout(kind: Horizontal)
  self.indexInLine = 0
  self.currentLineEmpty = true

  self.indent()

proc addWidget(self: CellLayoutContext, widget: WWidget, spaceLeft: bool) =
  self.lineWidget[self.indexInLine] = nil
  if spaceLeft:
    self.addSpace()
  self.lineWidget[self.indexInLine] = widget
  inc self.indexInLine
  self.currentLineEmpty = false

proc finish(self: CellLayoutContext): WWidget =
  if self.lineWidget.children.len > 0:
    self.parentWidget[self.currentLine] = self.lineWidget
    inc self.currentLine

  self.parentWidget.truncate(self.currentLine)

  return self.parentWidget

method updateWidget*(cell: Cell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext): WWidget {.base.} = widget

method updateWidget*(cell: ConstantCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  widget.sizeToContent = true
  widget.text = cell.text

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  widget.foregroundColor = textColor

method updateWidget*(cell: AliasCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  widget.sizeToContent = true

  let class = cell.node.nodeClass
  if class.isNotNil:
    widget.text = class.alias
  else:
    widget.text = $cell.node.class

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  widget.foregroundColor = textColor

method updateWidget*(cell: NodeReferenceCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WPanel: widget.WPanel else: WPanel()
  result = widget

  widget.sizeToContent = true

  if cell.child.isNil:
    var text = if widget.children.len > 0 and widget.children[0] of WText: widget.children[0].WText else: WText()
    text.sizeToContent = true

    let reference = cell.node.reference(cell.reference)
    text.text = $reference

    let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
    text.foregroundColor = textColor

    if 0 < widget.children.len:
      widget.children[0] = text
    else:
      widget.children.add text

  else:
    let oldWidget: WWidget = if 0 < widget.children.len: widget.children[0] else: nil
    let newWidget = cell.child.updateWidget(app, oldWidget, frameIndex, ctx)
    if newWidget.isNil:
      widget.children.setLen 0
      return

    if 0 < widget.children.len:
      widget.children[0] = newWidget
    else:
      widget.children.add newWidget

method updateWidget*(cell: PropertyCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  var widget = if widget.isNotNil and widget of WText: widget.WText else: WText()
  result = widget

  widget.sizeToContent = true
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

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  widget.foregroundColor = textColor

method updateWidget*(cell: CollectionCell, app: Editor, widget: WWidget, frameIndex: int, ctx: CellLayoutContext): WWidget =
  if cell.isVisible.isNotNil and not cell.isVisible(cell.node):
    return nil

  # debugf"updateWidget {cell.node}"

  let myCtx = if ctx.isNil or cell.inline:
    newCellLayoutContext(widget)
  else:
    ctx

  result = myCtx.parentWidget

  cell.fill()

  let vertical = cell.layout.kind == Vertical

  if cell.style.isNotNil and cell.style.indentChildren:
    inc myCtx.currentIndent

  defer:
    if cell.style.isNotNil and cell.style.indentChildren:
      dec myCtx.currentIndent

  for i, c in cell.children:
    if vertical and (i > 0 or not myCtx.isCurrentLineEmpty()):
      myCtx.newLine()

    var spaceLeft = not myCtx.prevNoSpaceRight
    if c.style.isNotNil:
      if c.style.onNewLine:
        myCtx.newLine()
      if c.style.noSpaceLeft:
        spaceLeft = false

    let oldWidget = myCtx.getReusableWidget()
    let newWidget = c.updateWidget(app, oldWidget, frameIndex, myCtx)
    if newWidget.isNotNil:
      myCtx.addWidget(newWidget, spaceLeft)

    myCtx.prevNoSpaceRight = false
    if c.style.isNotNil:
      if c.style.addNewlineAfter:
        myCtx.newLine()
      myCtx.prevNoSpaceRight = c.style.noSpaceRight

  if myCtx != ctx:
    return myCtx.finish()
  else:
    return nil

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
  if widget.children.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    widget.children.add(headerPanel)

    headerPart1Text = WText(text: "", sizeToContent: true, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.children.add(headerPart1Text)

    headerPart2Text = WText(text: "", sizeToContent: true, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: textColor)
    headerPanel.children.add(headerPart2Text)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.children.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
  else:
    headerPanel = widget.children[0].WPanel
    headerPart1Text = headerPanel.children[0].WText
    headerPart2Text = headerPanel.children[1].WText
    contentPanel = widget.children[1].WPanel

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
  # contentPanel.children.setLen 0

  self.updateBaseIndexAndScrollOffset(app, contentPanel)

  var rendered = 0

  # for node in self.document.model.rootNodes:
  #   createRawAstWidget(node, app, contentPanel, frameIndex)

  var builder = self.document.builder
  var lastY = self.scrollOffset

  var i = 0
  for node in self.document.model.rootNodes:
    let cell = builder.buildCell(node)
    if cell.isNil:
      continue

    # echo cell.dump()

    let oldWidget: WWidget = if i < contentPanel.children.len: contentPanel.children[i] else: nil
    let newWidget = cell.updateWidget(app, oldWidget, frameIndex, nil)
    if newWidget.isNil:
      if oldWidget.isNotNil:
        widget.children.del(i)
      continue

    newWidget.top = lastY

    if i < contentPanel.children.len:
      contentPanel.children[i] = newWidget
    else:
      contentPanel.children.add newWidget

    inc i

  let indent = getOption[float32](app, "ast.indent", 20)
  let inlineBlocks = getOption[bool](app, "ast.inline-blocks", false)
  let verticalDivision = getOption[bool](app, "ast.vertical-division", false)

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {rendered} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"
