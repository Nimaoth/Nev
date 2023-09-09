import std/[strformat, tables, sugar]
import util, app, app_interface, config_provider, document_editor, ast_document, ast, node_layout, compiler, text/text_document, custom_logger, widgets, platform, theme, widget_builder_text_document
import widget_builders_base
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

func withAlpha(color: Color, alpha: float32): Color = color(color.r, color.g, color.b, alpha)

method updateWidget*(self: AstSymbolSelectorItem, app: App, widget: WPanel, frameIndex: int) =
  let charWidth = app.platform.charWidth
  let totalLineHeight = app.platform.totalLineHeight

  widget.setLen 0

  var name = ""
  var typ = ""
  var nameColors = @[""]
  var typeColors = "storage.type"
  case self.completion.kind
  of SymbolCompletion:
    if ctx.getSymbol(self.completion.id).getSome(sym):
      name = sym.name
      typ = $ctx.computeSymbolType(sym)
      nameColors = ctx.getColorForSymbol(sym)

  else:
    return

  let nameColor = app.theme.tokenColor(nameColors, color(255/255, 255/255, 255/255))
  let nameWidget = createPartWidget(name, 0.0, name.len.float * charWidth, totalLineHeight, nameColor, frameIndex)
  widget.add(nameWidget)

  let typeColor = app.theme.tokenColor(typeColors, color(255/255, 255/255, 255/255))
  var typeWidget = createPartWidget(typ, -typ.len.float * charWidth, 0, totalLineHeight, typeColor, frameIndex)
  typeWidget.anchor.min.x = 1
  typeWidget.anchor.max.x = 1
  widget.add(typeWidget)

proc updateBaseIndexAndScrollOffset(self: AstDocumentEditor, app: App, contentPanel: WPanel) =
  let totalLineHeight = app.platform.totalLineHeight
  self.previousBaseIndex = self.previousBaseIndex.clamp(0..self.document.rootNode.len)

  let selectedNodeId = self.node.id

  var replacements = initTable[Id, VisualNode]()

  let indent = getOption[float32](app, "ast.indent", 20)
  let inlineBlocks = getOption[bool](app, "ast.inline-blocks", false)
  let verticalDivision = getOption[bool](app, "ast.vertical-division", false)

  # Adjust scroll offset and base index so that the first node on screen is the base
  while self.scrollOffset < 0 and self.previousBaseIndex + 1 < self.document.rootNode.len:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: self.document.rootNode[self.previousBaseIndex], selectedNode: selectedNodeId, replacements: replacements, revision: config.revision, measureText: (t) => self.app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
    let layout = ctx.computeNodeLayout(input)

    if self.scrollOffset + layout.bounds.h + totalLineHeight >= contentPanel.lastBounds.h:
      break

    self.previousBaseIndex += 1
    self.scrollOffset += layout.bounds.h + totalLineHeight

  # Adjust scroll offset and base index so that the first node on screen is the base
  while self.scrollOffset > contentPanel.lastBounds.h and self.previousBaseIndex > 0:
    let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: self.document.rootNode[self.previousBaseIndex - 1], selectedNode: selectedNodeId, replacements: replacements, revision: config.revision, measureText: (t) => self.app.platform.measureText(t), indent: indent, renderDivisionVertically: verticalDivision, inlineBlocks: inlineBlocks)
    let layout = ctx.computeNodeLayout(input)

    if self.scrollOffset - layout.bounds.h <= 0:
      break

    self.previousBaseIndex -= 1
    self.scrollOffset -= layout.bounds.h + totalLineHeight

proc renderVisualNode*(self: AstDocumentEditor, app: App, node: VisualNode, selected: AstNode, bounds: Rect, offset: Vec2, widget: WPanel, frameIndex: int) =
  let charWidth = app.platform.charWidth

  # echo "renderVisualNode ", node

  if not node.widgetTemplate.isNil:
    var nodeWidget = node.widgetTemplate
    if node.cloneWidget:
      nodeWidget = nodeWidget.clone()

    nodeWidget.left = node.bounds.x
    nodeWidget.top = node.bounds.y
    nodeWidget.right = node.bounds.xw
    nodeWidget.bottom = node.bounds.yh
    widget.add nodeWidget
    return

  var panel = WPanel(left: node.bounds.x, right: node.bounds.xw, top: node.bounds.y, bottom: node.bounds.yh)
  widget.add panel

  if node.background.getSome(colors):
    let color = app.theme.anyColor(colors, color(255/255, 255/255, 255/255))
    panel.backgroundColor = color
    panel.fillBackground = true

  if node.text.len > 0:
    let color = app.theme.anyColor(node.colors, color(255/255, 255/255, 255/255))
    var style = app.theme.tokenFontStyle(node.colors)
    if node.styleOverride.getSome(override):
      style.incl override

    # let text = if app.getFlag("ast.render-vnode-depth", false): $node.depth else: node.text
    # let image = renderCtx.computeRenderedText(text, font, node.fontSize)
    # renderCtx.boxy.drawImage(image, bounds.xy, color)

    var textWidget = createPartWidget(node.text, node.bounds.x, node.text.len.float * charWidth, app.platform.totalLineHeight, color, frameIndex)
    textWidget.style.fontStyle = style
    textWidget.top = node.bounds.y
    textWidget.bottom = node.bounds.yh
    widget.add textWidget

    # @todo(ni)
    # if Underline in style:
    #   renderCtx.boxy.fillRect(bounds.splitHInv(2.relative)[1], color)

  if node.len > 0:
    for child in node.children:
      self.renderVisualNode(app, child, selected, bounds, offset, panel, frameIndex)

  # Draw outline around node if it refers to the selected node or the same thing the selected node refers to
  if node.node != nil and (self.node.id == node.node.reff or (self.node.reff == node.node.reff and node.node.reff != null)):
    panel.fillBackground = true
    panel.allowAlpha = true
    panel.drawBorder = true
    panel.backgroundColor = app.theme.color("foreground", color(175/255, 175/255, 255/255)).withAlpha(0.25)
    panel.foregroundColor = app.theme.color("foreground", color(175/255, 175/255, 255/255))

  # Draw outline around node it is being refered to by the selected node
  elif node.node != nil and self.node.reff == node.node.id:
    panel.fillBackground = true
    panel.allowAlpha = true
    panel.drawBorder = true
    panel.backgroundColor = app.theme.color("inputValidation.infoBorder", color(175/255, 255/255, 200/255)).withAlpha(0.25)
    panel.foregroundColor = app.theme.color("inputValidation.infoBorder", color(175/255, 255/255, 200/255))

proc renderBlockIndent(editor: AstDocumentEditor, app: App, layout: NodeLayout, node: AstNode, offset: Vec2, widget: WPanel) =
  let indentLineWidth = editor.configProvider.getValue("ast.indent-line-width", 1.0)
  let indentLineAlpha = editor.configProvider.getValue("ast.indent-line-alpha", 1.0)

  if indentLineWidth <= 0:
    return

  for (_, child) in node.nextPreOrder:
    if child.kind == NodeList and layout.nodeToVisualNode.contains(child.id):
      let visualRange = layout.nodeToVisualNode[child.id]
      let bounds = visualRange.absoluteBounds
      let indent = (visualRange.parent[visualRange.first].indent - 1) mod 6 + 1
      let color = app.theme.color(@[fmt"editorBracketHighlight.foreground{indent}", "editor.foreground"]).withAlpha(indentLineAlpha)

      var panel = WPanel(left: bounds.x, right: bounds.x + indentLineWidth, top: bounds.y, bottom: bounds.yh,
        flags: &{FillBackground, AllowAlpha},
        backgroundColor: color)
      widget.insert(0, panel)

proc renderVisualNodeLayout*(self: AstDocumentEditor, app: App, node: AstNode, bounds: Rect, layout: NodeLayout, offset: Vec2, contentWidget: WPanel, frameIndex: int) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  self.lastLayouts.add (layout, offset)

  var widget = WPanel(left: layout.bounds.x, right: layout.bounds.xw, top: layout.bounds.y + offset.y, bottom: layout.bounds.yh + offset.y)
  # echo "renderVisualNodeLayout ", widget.top
  for line in layout.root.children:
    self.renderVisualNode(app, line, self.node, bounds, offset, widget, frameIndex)
  contentWidget.add widget

  # Draw diagnostics
  let errorColor = app.theme.color("editorError.foreground", color(255/255, 0/255, 0/255))
  for (id, visualRange) in layout.nodeToVisualNode.pairs:
    if ctx.diagnosticsPerNode.contains(id):
      var foundErrors = false
      let bounds = visualRange.absoluteBounds + offset
      var last = rect(bounds.xy, vec2())
      for diagnostics in ctx.diagnosticsPerNode[id].queries.values:
        for diagnostic in diagnostics:
          var panel = WText(text: diagnostic.message,
            left: -diagnostic.message.len.float * charWidth, right: 0, top: last.yh, bottom: last.yh + totalLineHeight,
            anchor: (vec2(1, 0), vec2(1, 0)), flags: &{SizeToContent}, foregroundColor: errorColor)
          contentWidget.add panel
          foundErrors = true
      if foundErrors:
        var panel = WPanel(left: bounds.x, right: bounds.xw, top: bounds.y, bottom: bounds.yh,
          flags: &{AllowAlpha, FillBackground, DrawBorder}, backgroundColor: errorColor.withAlpha(0.25), foregroundColor: errorColor)
        contentWidget.add panel

  # Render outline for selected node
  if layout.nodeToVisualNode.contains(self.node.id):
    let visualRange = layout.nodeToVisualNode[self.node.id]
    let bounds = visualRange.absoluteBounds

    var panel = WPanel(left: bounds.x, right: bounds.xw, top: bounds.y, bottom: bounds.yh,
      flags: &{AllowAlpha, FillBackground, DrawBorder},
      backgroundColor: app.theme.color("inputValidation.warningBorder", color(1, 1, 1)).withAlpha(0.25),
      foregroundColor: app.theme.color("inputValidation.warningBorder", color(255/255, 255/255, 255/255)))
    widget.add panel
    # renderCtx.boxy.strokeRect(bounds, app.theme.color("foreground", color(255/255, 255/255, 255/255)), 2)

    # let value = ctx.getValue(self.node)
    # let typ = ctx.computeType(self.node)

    # let parentBounds = visualRange.parent.absoluteBounds

    # var last = rect(vec2(contentBounds.xw - 25, parentBounds.y + offset.y), vec2())
    # last = renderCtx.drawText(last.xy, $typ, app.theme.tokenColor("storage.type", color(255/255, 255/255, 255/255)), pivot = vec2(1, 0))

    # if value.getSome(value) and value.kind != vkVoid and value.kind != vkBuiltinFunction and value.kind != vkAstFunction and value.kind != vkError:
    #   last = renderCtx.drawText(last.xy, " : ", app.theme.tokenColor("punctuation", color(255/255, 255/255, 255/255)), pivot = vec2(1, 0))
    #   last = renderCtx.drawText(last.xy, $value, app.theme.tokenColor("string", color(255/255, 255/255, 255/255)), pivot = vec2(1, 0))

  self.renderBlockIndent(app, layout, node, offset, widget)

proc renderCompletionList*(self: AstDocumentEditor, app: App, widget: WPanel, parentBounds: Rect, frameIndex: int, completions: openArray[Completion], selected: int, fill: bool, targetLine: Option[int],
    renderedItems: var seq[tuple[index: int, widget: WWidget]], previousBaseIndex: var int, scrollOffset: var float) =
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  renderedItems.setLen 0

  if completions.len == 0:
    return

  let maxRenderedCompletions = if fill:
    int(widget.lastBounds.h / totalLineHeight)
  else: 15

  let renderedCompletions = min(completions.len, maxRenderedCompletions)

  widget.bottom = widget.top + renderedCompletions.float * totalLineHeight
  widget.layoutWidget(parentBounds, frameIndex, app.platform.layoutOptions)
  updateBaseIndexAndScrollOffset(widget.lastBounds.h, previousBaseIndex, scrollOffset, completions.len, totalLineHeight, targetLine)

  var firstCompletion = previousBaseIndex
  block:
    var temp = scrollOffset
    while temp > 0 and firstCompletion > 0:
      temp -= totalLineHeight
      firstCompletion -= 1

  var entries: seq[tuple[name: string, typ: string, value: string, color1: seq[string], color2: string, color3: string, nameStyle: set[FontStyle]]] = @[]

  for i, com in completions[firstCompletion..completions.high]:
    case com.kind
    of SymbolCompletion:
      if ctx.getSymbol(com.id).getSome(sym):
        let typ = ctx.computeSymbolType(sym)
        var valueString = ""
        let value = ctx.computeSymbolValue(sym)
        if value.kind != vkError and value.kind != vkBuiltinFunction and value.kind != vkAstFunction and value.kind != vkVoid:
          valueString = $value
        let style = ctx.getStyleForSymbol(sym).get {}
        entries.add (sym.name, $typ, valueString, ctx.getColorForSymbol(sym), "storage.type", "string", style)

    of AstCompletion:
      entries.add (com.name, "snippet", $com.nodeKind, @["entity.name.label", "entity.name"], "storage", "string", {})

    if entries.len > renderedCompletions:
      break

  var maxNameLen = 10
  var maxTypeLen = 10
  var maxValueLen = 0
  for (name, typ, value, color1, color2, color3, _) in entries:
    maxNameLen = max(maxNameLen, name.len)
    maxTypeLen = max(maxTypeLen, typ.len)
    maxValueLen = max(maxValueLen, value.len)

  let sepWidth = charWidth * 3
  let nameWidth = charWidth * maxNameLen.float
  let typeWidth = charWidth * maxTypeLen.float
  let valueWidth = charWidth * maxValueLen.float
  var totalWidth = nameWidth + typeWidth + valueWidth + sepWidth * 2
  if fill and totalWidth < widget.lastBounds.w:
    totalWidth = widget.lastBounds.w

  widget.right = widget.left + totalWidth
  widget.bottom = widget.top + renderedCompletions.float * totalLineHeight

  let selectionColor = app.theme.color("list.activeSelectionBackground", color(200/255, 200/255, 200/255))
  let sepColor = app.theme.color("list.inactiveSelectionForeground", color(175/255, 175/255, 175/255))

  var newRenderedItems: seq[tuple[index: int, widget: WWidget]]

  proc renderLine(lineWidget: WPanel, i: int, down: bool, frameIndex: int): bool =

    if i == self.selectedCompletion:
      lineWidget.fillBackground = true
      lineWidget.backgroundColor = selectionColor

    let k = i - firstCompletion
    if k < 0 or k > entries.high:
      return false

    let entry = entries[k]

    let nameColor = app.theme.tokenColor(entry.color1, color(255/255, 255/255, 255/255))
    let nameWidget = createPartWidget(entry.name, 0.0, entry.name.len.float * charWidth, totalLineHeight, nameColor, frameIndex)
    nameWidget.style.fontStyle = entry.nameStyle
    lineWidget.add(nameWidget)

    var tempWidget = createPartWidget(" : ", nameWidth, 3 * charWidth, totalLineHeight, sepColor, frameIndex)
    lineWidget.add(tempWidget)

    let typeColor = app.theme.tokenColor(entry.color2, color(255/255, 255/255, 255/255))
    let typeWidget = createPartWidget(entry.typ, tempWidget.right, entry.typ.len.float * charWidth, totalLineHeight, typeColor, frameIndex)
    lineWidget.add(typeWidget)

    tempWidget = createPartWidget(" = ", typeWidget.left + typeWidth, 3 * charWidth, totalLineHeight, sepColor, frameIndex)
    lineWidget.add(tempWidget)

    if entry.value.len > 0:
      let valueColor = app.theme.tokenColor(entry.color3, color(255/255, 255/255, 255/255))
      var valueWidget = createPartWidget(entry.value, -entry.value.len.float * charWidth, 0, totalLineHeight, valueColor, frameIndex)
      valueWidget.anchor.min.x = 1
      valueWidget.anchor.max.x = 1
      lineWidget.add(valueWidget)

    newRenderedItems.add (i, lineWidget)

    return true

  app.createLinesInPanel(widget, previousBaseIndex, scrollOffset, completions.len, frameIndex, onlyRenderInBounds=true, renderLine)

  renderedItems.add newRenderedItems

proc renderCompletions*(self: AstDocumentEditor, app: App, widget: WPanel, frameIndex: int) =
  self.lastCompletionsWidget = nil

  if self.completions.len == 0:
    return

  let matchColor = app.theme.color("editor.findMatchBorder", color(150/255, 150/255, 220/255))
  let backgroundColor = app.theme.color("panel.background", color(30/255, 30/255, 30/255))
  let borderColor = app.theme.color("panel.border", color(255/255, 255/255, 255/255))

  # Render outline around all nodes which reference the selected symbol in the completion list
  for (layout, offset) in self.lastLayouts:
    let selectedCompletion = self.completions[self.selectedCompletion]
    if selectedCompletion.kind == SymbolCompletion and ctx.getSymbol(selectedCompletion.id).getSome(symbol) and symbol.kind == skAstNode and layout.nodeToVisualNode.contains(symbol.node.id):
      let selectedDeclRect = layout.nodeToVisualNode[symbol.node.id]
      let bounds = selectedDeclRect.absoluteBounds + offset
      var panel = WPanel(left: bounds.x, right: bounds.xw, top: bounds.y, bottom: bounds.yh,
        flags: &{AllowAlpha, FillBackground, DrawBorder},
        backgroundColor: matchColor.withAlpha(0.25),
        foregroundColor: matchColor)
      widget.add panel

  # Render completion window under the currently edited node
  for (layout, offset) in self.lastLayouts:
    if layout.nodeToVisualNode.contains(self.node.id):
      let visualRange = layout.nodeToVisualNode[self.node.id]
      let bounds = visualRange.absoluteBounds + offset
      let panel = WPanel(left: bounds.x, top: bounds.yh, right: bounds.x + 100, bottom: bounds.yh + 100, flags: &{FillBackground, DrawBorder, MaskContent}, backgroundColor: backgroundColor, foregroundColor: borderColor, maskContent: true)
      self.renderCompletionList(app, panel, widget.lastBounds, frameIndex, self.completions, self.selectedCompletion, false, self.scrollToCompletion, self.lastItems, self.completionsBaseIndex, self.completionsScrollOffset)
      self.lastCompletionsWidget = panel
      widget.add panel
      break

  self.scrollToCompletion = int.none

method updateWidget*(self: AstDocumentEditor, app: App, widget: WPanel, completionsPanel: WPanel, frameIndex: int) =
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

  let textEditorDirty = if self.textEditor.isNil: false else: self.textEditor.dirty
  if not (contentPanel.changed(frameIndex) or self.dirty or app.platform.redrawEverything or textEditorDirty):
    return

  self.resetDirty()

  # either layout or content changed, update the lines
  contentPanel.setLen 0

  self.updateBaseIndexAndScrollOffset(app, contentPanel)

  self.lastLayouts.setLen 0
  var rendered = 0

  var replacements = initTable[Id, VisualNode]()

  if not self.currentlyEditedNode.isNil or self.currentlyEditedSymbol != null:
    if self.textEditorWidget.isNil:
      self.textEditorWidget = WPanel(flags: &{SizeToContent})
    self.textEditor.active = true
    self.textEditor.markDirty()
    self.textEditor.updateWidget(app, self.textEditorWidget, completionsPanel, frameIndex)
    self.textEditorWidget.layoutWidget(rect(0, 0, 0, 0), frameIndex, app.platform.layoutOptions)
  else:
    self.textEditorWidget = nil

  if not isNil self.currentlyEditedNode:
    replacements[self.currentlyEditedNode.id] = VisualNode(id: newId(), bounds: self.textEditorWidget.lastBounds, widgetTemplate: self.textEditorWidget)
  elif self.currentlyEditedSymbol != null:
    replacements[self.currentlyEditedSymbol] = VisualNode(id: newId(), bounds: self.textEditorWidget.lastBounds, widgetTemplate: self.textEditorWidget)

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

  self.renderCompletions(app, contentPanel, frameIndex)

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {rendered} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"
