import std/[strformat, tables, sequtils, algorithm]
import util, input, editor, text_document, custom_logger, rendering/widgets, rendering/renderer, timer, rect_utils, theme
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

method updateWidget(self: DocumentEditor, app: Editor, widget: WPanel, frameIndex: int): bool {.base.} = discard

var frameTimeSmooth: float = 0
proc updateStatusBar*(self: Editor, frameIndex: int, statusBarWidget: WWidget): bool =
  # let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
  # discard self.renderCtx.drawText(statusBounds.xy, fmt"{mode}", self.theme.color("editor.foreground", rgb(225, 200, 200)))

  let frameTimeSmoothing = getOption[float](self, "editor.frame-time-smoothing", 0.1)
  let frameTime = self.frameTimer.elapsed.ms
  frameTimeSmooth = frameTimeSmoothing * frameTimeSmooth + (1 - frameTimeSmoothing) * frameTime
  let fps = int(1000 / frameTimeSmooth)
  let frameTimeStr = fmt"{frameTimeSmooth:>5.2}ms, {fps} FPS"
  # discard self.renderCtx.drawText(statusBounds.xwy, frameTimeStr, self.theme.color("editor.foreground", rgb(225, 200, 200)), pivot=vec2(1, 0))

  statusBarWidget.WText.text = frameTimeStr
  statusBarWidget.lastHierarchyChange = frameIndex

  # let text = self.getCommandLineTextEditor.document.contentString

  return true

method updateWidget(self: TextDocumentEditor, app: Editor, widget: WPanel, frameIndex: int): bool =
  let lineHeight = app.rend.lineHeight
  let lineDistance = app.rend.lineDistance
  let totalLineHeight = app.rend.totalLineHeight
  let charWidth = app.rend.charWidth

  self.lastContentBounds = widget.lastBounds

  var headerPanel: WPanel
  var headerPart1Text: WText
  var headerPart2Text: WText
  var contentPanel: WPanel
  if widget.children.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, bottom: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    widget.children.add(headerPanel)

    headerPart1Text = WText(text: "", sizeToContent: true, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: color(0, 1, 0))
    headerPanel.children.add(headerPart1Text)

    headerPart2Text = WText(text: "", sizeToContent: true, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: color(0, 0, 1))
    headerPanel.children.add(headerPart2Text)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.children.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.rend.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.rend.layoutOptions)
  else:
    headerPanel = widget.children[0].WPanel
    headerPart1Text = headerPanel.children[0].WText
    headerPart2Text = headerPanel.children[1].WText
    contentPanel = widget.children[1].WPanel

  # Update header
  if self.renderHeader:
    headerPanel.bottom = totalLineHeight
    contentPanel.top = totalLineHeight

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPart1Text.text = fmt" {mode} - {self.document.filename} "
    # headerPart1Text.lastHierarchyChange = frameIndex

    headerPart2Text.text = fmt" {self.selection} - {self.id} "
    # headerPart2Text.lastHierarchyChange = frameIndex

    # debugf"{frameIndex}, h1: {headerPart1Text.lastHierarchyChange}, {headerPart1Text.lastBoundsChange}, h2: {headerPart2Text.lastHierarchyChange}"
    headerPanel.updateLastHierarchyChangeFromChildren frameIndex
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  if not (contentPanel.changed(frameIndex) or self.dirty):
    return contentPanel.changed(frameIndex)

  self.dirty = false

  # either layout or content changed, update the lines
  # debugf"rerender lines for {self.document.filename}"
  let timer = startTimer()
  contentPanel.children.setLen 0

  block:
    self.previousBaseIndex = self.previousBaseIndex.clamp(0..self.document.lines.len)

    # Adjust scroll offset and base index so that the first node on screen is the base
    while self.scrollOffset < 0 and self.previousBaseIndex + 1 < self.document.lines.len:
      if self.scrollOffset + totalLineHeight >= contentPanel.lastBounds.h:
        break
      self.previousBaseIndex += 1
      self.scrollOffset += totalLineHeight

    # Adjust scroll offset and base index so that the first node on screen is the base
    while self.scrollOffset > contentPanel.lastBounds.h and self.previousBaseIndex > 0:
      if self.scrollOffset - lineHeight <= 0:
        break
      self.previousBaseIndex -= 1
      self.scrollOffset -= totalLineHeight

  # Update content
  proc renderLine(i: int, down: bool): bool =
    # Pixel coordinate of the top left corner of the entire line. Includes line number
    let top = (i - self.previousBaseIndex).float32 * totalLineHeight + self.scrollOffset

    # Bounds of the previous line part
    if top >= contentPanel.lastBounds.h:
      # debugf"abort renderLine top {top} >= h {contentPanel.lastBounds.h}"
      return not down
    if top + totalLineHeight <= 0:
      return down

    var styledText = self.document.getStyledText(i)

    var lineWidget = WHorizontalList(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, right: -1, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)

    var startOffset = 0.0
    for partIndex, part in styledText.parts:
      let width = part.text.len.float * charWidth
      let color = if part.scope.len == 0: color(225, 200, 200) else: app.theme.tokenColor(part.scope, color(0.9, 0.8, 0.8))
      var partWidget = WText(text: part.text, anchor: (vec2(0, 0), vec2(0, 1)), left: startOffset, right: startOffset + width, foregroundColor: color, lastHierarchyChange: frameIndex)
      startOffset += width

      lineWidget.children.add(partWidget)

    contentPanel.children.add lineWidget

    return true

  # Render all lines after base index
  for i in self.previousBaseIndex..self.document.lines.high:
    if not renderLine(i, true):
      break

  # Render all lines before base index
  for k in 1..self.previousBaseIndex:
    let i = self.previousBaseIndex - k
    if not renderLine(i, false):
      break

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)

  # Re-layout content
  # contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.rend.layoutOptions)

  self.lastContentBounds = widget.lastBounds

  debugf"rerender {contentPanel.children.len} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

  return true

var commandLineWidget: WText
var mainPanel: WPanel
var widgetsPerEditor = initTable[EditorId, WPanel]()

proc updateWidgetTree*(self: Editor, frameIndex: int): bool =
  if self.widget.isNil:
    var panel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))
    self.widget = panel
    mainPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), bottom: -self.rend.totalLineHeight - 1, right: -1, foregroundColor: color(1, 0, 0))
    panel.children.add(mainPanel)
    commandLineWidget = WText(text: "command line", anchor: (vec2(0, 1), vec2(1, 1)), top: -self.rend.totalLineHeight, fillBackground: true, backgroundColor: color(0, 0, 0), foregroundColor: color(1, 0, 1))
    # panel.children.add(commandLineWidget)

    self.widget.layoutWidget(rect(vec2(0, 0), self.rend.size), frameIndex, self.rend.layoutOptions)
    result = true

  let currentViewWidgets = mainPanel.children
  mainPanel.children.setLen 0

  let rects = self.layout.layoutViews(self.layout_props, rect(0, 0, 1, 1), self.views.len)
  for i, view in self.views:
    var widget: WPanel
    var isNew = false
    if widgetsPerEditor.contains(view.editor.id):
      widget = widgetsPerEditor[view.editor.id]
    else:
      widget = WPanel()
      widgetsPerEditor[view.editor.id] = widget
      isNew = true

    if i < rects.len:
      widget.anchor = (rects[i].xy, rects[i].xwyh)
      widget.right = -1

      # If we newly created this widget then perform one layout first so that the bounds are know for updateWidget
      if isNew:
        widget.layoutWidget(self.widget.lastBounds, frameIndex, self.rend.layoutOptions)

      mainPanel.children.add widget
      result = view.editor.updateWidget(self, widget, frameIndex) or result
      mainPanel.lastHierarchyChange = max(mainPanel.lastHierarchyChange, widget.lastHierarchyChange)

  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, mainPanel.lastHierarchyChange)

  # Status bar
  result = self.updateStatusBar(frameIndex, commandLineWidget) or result
  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, commandLineWidget.lastHierarchyChange)

proc layoutWidgetTree*(self: Editor, size: Vec2, frameIndex: int): bool =
  self.lastBounds = rect(vec2(0, 0), size)
  if self.widget.isNil:
    return true

  self.widget.layoutWidget(self.lastBounds, frameIndex, self.rend.layoutOptions)
  return false