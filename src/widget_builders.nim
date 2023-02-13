import std/[strformat, tables, sequtils, algorithm]
import util, input, editor, text_document, custom_logger, rendering/widgets, rendering/renderer, timer, rect_utils
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, colors

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

  var headerPanel: WPanel
  var contentPanel: WPanel
  if widget.children.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, bottom: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: false)
    headerPanel.children.add(WText(text: "", sizeToContent: true, anchor: (vec2(0, 0), vec2(0, 1)), lastHierarchyChange: frameIndex, foregroundColor: rgb(0, 255, 0)))
    headerPanel.children.add(WText(text: "", sizeToContent: true, anchor: (vec2(1, 0), vec2(1, 1)), pivot: vec2(1, 0), lastHierarchyChange: frameIndex, foregroundColor: rgb(0, 0, 255)))
    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, drawBorder: true)
    widget.children.add(headerPanel)
    widget.children.add(contentPanel)
  else:
    headerPanel = widget.children[0].WPanel
    contentPanel = widget.children[1].WPanel

  # Update header
  if self.renderHeader:
    headerPanel.bottom = totalLineHeight
    contentPanel.top = totalLineHeight

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPanel.children[0].WText.text = fmt" {mode} - {self.document.filename} "
    headerPanel.children[0].right = headerPanel.children[0].WText.text.len.float * charWidth
    headerPanel.children[0].lastHierarchyChange = frameIndex
    headerPanel.children[1].WText.text = fmt" {self.selection} - {self.id} "
    headerPanel.children[1].right = headerPanel.children[1].WText.text.len.float * charWidth
    headerPanel.children[1].lastHierarchyChange = frameIndex

    headerPanel.updateLastHierarchyChangeFromChildren()
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  if not (contentPanel.changed(frameIndex) or self.dirty):
    return false

  self.dirty = false

  # either layout or content changed, update the lines
  debugf"rerender lines for {self.document.filename}"
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
      return not down
    if top + totalLineHeight <= 0:
      return down

    var styledText = self.document.getStyledText(i)

    var lineWidget = WHorizontalList(anchor: (vec2(0, 0), vec2(1, 0)), left: 1, right: -1, top: top, bottom: top + totalLineHeight, lastHierarchyChange: frameIndex)

    var startOffset = 0.0
    for partIndex, part in styledText.parts:
      let width = part.text.len.float * charWidth
      var partWidget = WText(text: part.text, anchor: (vec2(0, 0), vec2(0, 1)), left: startOffset, right: startOffset + width, foregroundColor: rgb(255, 255, 255), lastHierarchyChange: frameIndex)
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
  contentPanel.layoutWidget(widget.lastBounds, frameIndex)

  self.lastContentBounds = widget.lastBounds

  debugf"rerender lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

  return true

var commandLineWidget: WText
var mainPanel: WPanel
var widgetsPerEditor = initTable[EditorId, WPanel]()

proc updateWidgetTree*(self: Editor, frameIndex: int): bool =
  if self.widget.isNil:
    var panel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))
    self.widget = panel
    mainPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), bottom: -self.rend.totalLineHeight - 1, right: -1, foregroundColor: rgb(255, 0, 0))
    panel.children.add(mainPanel)
    commandLineWidget = WText(text: "command line", anchor: (vec2(0, 1), vec2(1, 1)), top: -self.rend.totalLineHeight, foregroundColor: rgb(255, 0, 255))
    panel.children.add(commandLineWidget)
    result = true

  let currentViewWidgets = mainPanel.children
  mainPanel.children.setLen 0

  let rects = self.layout.layoutViews(self.layout_props, rect(0, 0, 1, 1), self.views.len)
  for i, view in self.views:
    var widget = if widgetsPerEditor.contains(view.editor.id): widgetsPerEditor[view.editor.id] else: WPanel()
    widgetsPerEditor[view.editor.id] = widget
    if i < rects.len:
      widget.anchor = (rects[i].xy, rects[i].xwyh)
      widget.right = -1
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

  self.widget.layoutWidget(self.lastBounds, frameIndex)
  return false