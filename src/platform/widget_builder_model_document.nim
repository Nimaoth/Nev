import std/[strformat, tables, sugar, sequtils]
import util, editor, document_editor, ast_document2, text_document, custom_logger, widgets, platform, theme, timer, widget_builder_text_document
import widget_builders_base
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor
import vmath, bumpy, chroma
import ast/[types]

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

  for role in node.children2.mitems:
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
  contentPanel.children.setLen 0

  self.updateBaseIndexAndScrollOffset(app, contentPanel)

  var rendered = 0

  for node in self.document.model.rootNodes:
    createRawAstWidget(node, app, contentPanel, frameIndex)

  let indent = getOption[float32](app, "ast.indent", 20)
  let inlineBlocks = getOption[bool](app, "ast.inline-blocks", false)
  let verticalDivision = getOption[bool](app, "ast.vertical-division", false)

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  self.lastContentBounds = contentPanel.lastBounds

  # debugf"rerender {rendered} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"
