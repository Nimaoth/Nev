import std/[strformat, tables, sequtils, algorithm]
import util, input, editor, text_document, custom_logger, rendering/widgets, timer, rect_utils
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, colors

method updateWidget(self: DocumentEditor, widget: WPanel, frameIndex: int): bool {.base.} = discard

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

method updateWidget(self: TextDocumentEditor, widget: WPanel, frameIndex: int): bool =
  var headerPanel: WPanel
  var contentPanel: WPanel
  if widget.children.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, bottom: 1, lastHierarchyChange: frameIndex)
    headerPanel.children.add(WText(text: "", sizeToContent: true, lastHierarchyChange: frameIndex))
    headerPanel.children.add(WText(text: "", sizeToContent: true, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex))
    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: 1, lastHierarchyChange: frameIndex)
    widget.children.add(headerPanel)
    widget.children.add(contentPanel)
  else:
    headerPanel = widget.children[0].WPanel
    contentPanel = widget.children[1].WPanel

  # Update header
  if self.renderHeader:
    headerPanel.bottom = 1
    contentPanel.top = 1

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPanel.children[0].WText.text = fmt" {mode} - {self.document.filename} "
    headerPanel.children[0].lastHierarchyChange = frameIndex
    headerPanel.children[1].WText.text = fmt" {self.selection} - {self.id} "
    headerPanel.children[1].lastHierarchyChange = frameIndex
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  if not (widget.changed(frameIndex) or contentPanel.changed(frameIndex) or self.dirty):
    return false

  self.dirty = false

  # either layout or content changed, update the lines
  debugf"rerender lines for {self.document.filename}"
  contentPanel.children.setLen 0

  let lineHeight = 1.0
  let lineDistance = 0.0
  let totalLineHeight = lineHeight + lineDistance

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
      return not down
    if top + totalLineHeight <= 0:
      return down

    var styledText = self.document.getStyledText(i)

    var lineWidget = WHorizontalList(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, right: -1, top: top, bottom: top + lineHeight, lastHierarchyChange: frameIndex)

    var startIndex = 0
    for partIndex, part in styledText.parts:
      var partWidget = WText(text: part.text, sizeToContent: true)
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

  # Re-layout content
  contentPanel.layoutWidget(widget.lastBounds, frameIndex)

  self.lastContentBounds = widget.lastBounds

  return true

var commandLineWigdet: WText
var mainPanel: WPanel
var widgetsPerEditor = initTable[EditorId, WPanel]()

proc updateWidgetTree*(self: Editor, frameIndex: int): bool =
  if self.widget.isNil:
    var panel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))
    self.widget = panel
    mainPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), bottom: -2, right: -1, foregroundColor: rgb(255, 0, 255))
    panel.children.add(mainPanel)
    commandLineWigdet = WText(text: "command line", anchor: (vec2(0, 1), vec2(1, 1)), top: -1, foregroundColor: rgb(255, 0, 255))
    panel.children.add(commandLineWigdet)
    result = true

  let currentViewWidgets = mainPanel.children
  mainPanel.children.setLen 0

  let rects = self.layout.layoutViews(self.layout_props, rect(0, 0, 1, 1), self.views.len)
  for i, view in self.views:
    var widget = if widgetsPerEditor.contains(view.editor.id): widgetsPerEditor[view.editor.id] else: WPanel(drawBorder: true)
    widgetsPerEditor[view.editor.id] = widget
    if i < rects.len:
      widget.anchor = (rects[i].xy, rects[i].xwyh)
      widget.right = -1
      mainPanel.children.add widget
      result = view.editor.updateWidget(widget, frameIndex) or result

  result = self.updateStatusBar(frameIndex, commandLineWigdet) or result

proc layoutWidgetTree*(self: Editor, size: Vec2, frameIndex: int): bool =
  self.lastBounds = rect(vec2(0, 0), size)
  self.widget.layoutWidget(self.lastBounds, frameIndex)
  return false