import std/[strformat, tables, sugar, sequtils]
import util, editor, document_editor, ast_document, ast, node_layout, compiler, text_document, custom_logger, widgets, platform, theme, timer
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

proc createPartWidget(text: string, startOffset: float, width: float, color: Color, frameIndex: int): WText

proc updateBaseIndexAndScrollOffset(self: AstDocumentEditor, app: Editor, contentPanel: WPanel) =
  let totalLineHeight = app.platform.totalLineHeight
  self.previousBaseIndex = self.previousBaseIndex.clamp(0..self.document.rootNode.len)

  let selectedNodeId = self.node.id

  var replacements = initTable[Id, VisualNode]()

  let indent = getOption[float32](app, "ast.indent", 20)
  let inlineBlocks = getOption[bool](app, "ast.inline-blocks", false)
  let verticalDivision = getOption[bool](app, "ast.vertical-division", false)

  # Adjust scroll offset and base index so that the first node on screen is the base
  while self.scrollOffset < 0 and self.previousBaseIndex + 1 < self.document.rootNode.len:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: self.document.rootNode[self.previousBaseIndex], selectedNode: selectedNodeId, replacements: replacements, revision: config.revision, measureText: (t) => self.editor.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
    let layout = ctx.computeNodeLayout(input)

    if self.scrollOffset + layout.bounds.h + totalLineHeight >= contentPanel.lastBounds.h:
      break

    self.previousBaseIndex += 1
    self.scrollOffset += layout.bounds.h + totalLineHeight

  # Adjust scroll offset and base index so that the first node on screen is the base
  while self.scrollOffset > contentPanel.lastBounds.h and self.previousBaseIndex > 0:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: self.document.rootNode[self.previousBaseIndex - 1], selectedNode: selectedNodeId, replacements: replacements, revision: config.revision, measureText: (t) => self.editor.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
    let layout = ctx.computeNodeLayout(input)

    if self.scrollOffset - layout.bounds.h <= 0:
      break

    self.previousBaseIndex -= 1
    self.scrollOffset -= layout.bounds.h + totalLineHeight

proc renderVisualNode*(self: AstDocumentEditor, app: Editor, node: VisualNode, selected: AstNode, bounds: Rect, offset: Vec2, widget: WPanel, frameIndex: int) =
  let charWidth = app.platform.charWidth

  # echo "renderVisualNode ", node

  var panel = WPanel(left: node.bounds.x, right: node.bounds.xw, top: node.bounds.y, bottom: node.bounds.yh)
  widget.children.add panel

  if node.background.getSome(colors):
    let color = app.theme.anyColor(colors, rgb(255, 255, 255))
    panel.backgroundColor = color
    panel.fillBackground = true

  if node.text.len > 0:
    let color = app.theme.anyColor(node.colors, rgb(255, 255, 255))
    var style = app.theme.tokenFontStyle(node.colors)
    if node.styleOverride.getSome(override):
      style.incl override

    let text = if app.getFlag("ast.render-vnode-depth", false): $node.depth else: node.text
    # let image = renderCtx.computeRenderedText(text, font, node.fontSize)
    # renderCtx.boxy.drawImage(image, bounds.xy, color)

    var textWidget = createPartWidget(text, node.bounds.x, text.len.float * charWidth, color, frameIndex)
    textWidget.style.fontStyle = style
    textWidget.top = node.bounds.y
    textWidget.bottom = node.bounds.yh
    widget.children.add textWidget

    # if Underline in style:
    #   renderCtx.boxy.fillRect(bounds.splitHInv(2.relative)[1], color)

  if node.children.len > 0:
    for child in node.children:
      self.renderVisualNode(app, child, selected, bounds, offset, panel, frameIndex)

  # Draw outline around node if it refers to the selected node or the same thing the selected node refers to
  if node.node != nil and (self.node.id == node.node.reff or (self.node.reff == node.node.reff and node.node.reff != null)):
    panel.fillBackground = true
    panel.allowAlpha = true
    panel.drawBorder = true
    panel.backgroundColor = app.theme.color("inputValidation.infoBorder", rgb(175, 175, 255)).withAlpha(0.1)
    panel.foregroundColor = app.theme.color("inputValidation.infoBorder", rgb(175, 175, 255))

  # Draw outline around node it is being refered to by the selected node
  elif node.node != nil and self.node.reff == node.node.id:
    panel.fillBackground = true
    panel.allowAlpha = true
    panel.drawBorder = true
    panel.backgroundColor = app.theme.color("inputValidation.warningBorder", rgb(175, 255, 200)).withAlpha(0.1)
    panel.foregroundColor = app.theme.color("inputValidation.warningBorder", rgb(175, 255, 200))

proc renderBlockIndent(editor: AstDocumentEditor, app: Editor, layout: NodeLayout, node: AstNode, offset: Vec2, widget: WPanel) =
  let indentLineWidth = getOption[float32](app, "ast.indent-line-width", 1)
  let indentLineAlpha = getOption[float32](app, "ast.indent-line-alpha", 1)

  if indentLineWidth <= 0:
    return

  for (_, child) in node.nextPreOrder:
    if child.kind == NodeList and layout.nodeToVisualNode.contains(child.id):
      let visualRange = layout.nodeToVisualNode[child.id]
      let bounds = visualRange.absoluteBounds
      let indent = (visualRange.parent[visualRange.first].indent - 1) mod 6 + 1
      let color = app.theme.color(@[fmt"editorBracketHighlight.foreground{indent}", "editor.foreground"]).withAlpha(indentLineAlpha)

      var panel = WPanel(left: bounds.x, right: bounds.x + indentLineWidth, top: bounds.y, bottom: bounds.yh,
        fillBackground: true, allowAlpha: true,
        backgroundColor: color)
      widget.children.insert(panel, 0)

proc renderVisualNodeLayout*(self: AstDocumentEditor, app: Editor, node: AstNode, bounds: Rect, layout: NodeLayout, offset: Vec2, contentWidget: WPanel, frameIndex: int) =
  self.lastLayouts.add (layout, offset)

  var widget = WPanel(left: layout.bounds.x, right: layout.bounds.xw, top: layout.bounds.y + offset.y, bottom: layout.bounds.yh + offset.y)
  # echo "renderVisualNodeLayout ", widget.top
  for line in layout.root.children:
    self.renderVisualNode(app, line, self.node, bounds, offset, widget, frameIndex)
  contentWidget.children.add widget

  # Render outline for selected node
  if layout.nodeToVisualNode.contains(self.node.id):
    let visualRange = layout.nodeToVisualNode[self.node.id]
    let bounds = visualRange.absoluteBounds

    var panel = WPanel(left: bounds.x, right: bounds.xw, top: bounds.y, bottom: bounds.yh,
      fillBackground: true, drawBorder: true, allowAlpha: true,
      backgroundColor: app.theme.color("foreground", color(1, 1, 1)).withAlpha(0.1),
      foregroundColor: app.theme.color("foreground", rgb(255, 255, 255)))
    widget.children.insert(panel, 0)
    # renderCtx.boxy.strokeRect(bounds, app.theme.color("foreground", rgb(255, 255, 255)), 2)

    # let value = ctx.getValue(self.node)
    # let typ = ctx.computeType(self.node)

    # let parentBounds = visualRange.parent.absoluteBounds

    # var last = rect(vec2(contentBounds.xw - 25, parentBounds.y + offset.y), vec2())
    # last = renderCtx.drawText(last.xy, $typ, app.theme.tokenColor("storage.type", rgb(255, 255, 255)), pivot = vec2(1, 0))

    # if value.getSome(value) and value.kind != vkVoid and value.kind != vkBuiltinFunction and value.kind != vkAstFunction and value.kind != vkError:
    #   last = renderCtx.drawText(last.xy, " : ", app.theme.tokenColor("punctuation", rgb(255, 255, 255)), pivot = vec2(1, 0))
    #   last = renderCtx.drawText(last.xy, $value, app.theme.tokenColor("string", rgb(255, 255, 255)), pivot = vec2(1, 0))

  self.renderBlockIndent(app, layout, node, offset, widget)

method updateWidget*(self: AstDocumentEditor, app: Editor, widget: WPanel, frameIndex: int) =
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
  contentPanel.children.setLen 0

  self.updateBaseIndexAndScrollOffset(app, contentPanel)

  self.lastLayouts.setLen 0
  var rendered = 0

  var replacements = initTable[Id, VisualNode]()
  var selectedNode = self.node

  let indent = getOption[float32](app, "ast.indent", 20)
  let inlineBlocks = getOption[bool](app, "ast.inline-blocks", false)
  let verticalDivision = getOption[bool](app, "ast.vertical-division", false)

  var offset = vec2(0, self.scrollOffset)
  for i in self.previousBaseIndex..<self.document.rootNode.len:
    let node = self.document.rootNode[i]
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node, selectedNode: selectedNode.id, replacements: replacements, revision: config.revision, measureText: (t) => app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
    let layout = ctx.computeNodeLayout(input)
    if layout.bounds.y + offset.y > contentPanel.lastBounds.h:
      break

    self.renderVisualNodeLayout(app, node, contentPanel.lastBounds, layout, offset, contentPanel, frameIndex)
    # self.renderBlockIndent(app, layout, node, offset)
    offset.y += layout.bounds.h + totalLineHeight

    inc rendered

  offset = vec2(0, self.scrollOffset)
  for k in 1..self.previousBaseIndex:
    let i = self.previousBaseIndex - k
    let node = self.document.rootNode[i]
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: node, selectedNode: selectedNode.id, replacements: replacements, revision: config.revision, measureText: (t) => app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
    let layout = ctx.computeNodeLayout(input)
    if layout.bounds.yh + offset.y < 0:
      break

    offset.y -= layout.bounds.h + totalLineHeight
    self.renderVisualNodeLayout(app, node, contentPanel.lastBounds, layout, offset, contentPanel, frameIndex)
    # self.renderBlockIndent(app, layout, node, offset)

    inc rendered

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {rendered} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

when defined(js):
  # Optimized version for javascript backend
  proc createPartWidget(text: string, startOffset: float, width: float, color: Color, frameIndex: int): WText =
    new result
    {.emit: [result, ".text = ", text, ".slice(0);"] .} #"""
    {.emit: [result, ".anchor = {Field0: {x: 0, y: 0}, Field1: {x: 0, y: 1}};"] .} #"""
    {.emit: [result, ".left = ", startOffset, ";"] .} #"""
    {.emit: [result, ".right = ", startOffset, " + ", width, ";"] .} #"""
    {.emit: [result, ".frameIndex = ", frameIndex, ";"] .} #"""
    {.emit: [result, ".foregroundColor = ", color, ";"] .} #"""
    # """

else:
  proc createPartWidget(text: string, startOffset: float, width: float, color: Color, frameIndex: int): WText =
    result = WText(text: text, anchor: (vec2(0, 0), vec2(0, 1)), left: startOffset, right: startOffset + width, foregroundColor: color, lastHierarchyChange: frameIndex)
