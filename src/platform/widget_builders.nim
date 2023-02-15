import std/[strformat, tables]
import editor, custom_logger, document_editor, widgets, platform, timer, rect_utils, theme, widget_builders_base, widget_builder_text_document
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

var frameTimeSmooth: float = 0
proc updateStatusBar*(self: Editor, frameIndex: int, statusBarWidget: WWidget) =
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

var commandLineWidget: WText
var mainStack: WStack
var mainPanel: WPanel
var widgetsPerEditor = initTable[EditorId, WPanel]()

proc updateWidgetTree*(self: Editor, frameIndex: int) =
  if self.widget.isNil:
    var panel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))
    self.widget = panel

    mainStack = WStack(anchor: (vec2(0, 0), vec2(1, 1)), bottom: -self.platform.totalLineHeight - 1, right: -1, logLayout: false)
    panel.children.add(mainStack)

    mainPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), foregroundColor: color(1, 0, 0))
    mainStack.children.add(mainPanel)

    commandLineWidget = WText(text: "command line", anchor: (vec2(0, 1), vec2(1, 1)), top: -self.platform.totalLineHeight, fillBackground: true, backgroundColor: color(0, 0, 0), foregroundColor: color(1, 0, 1))
    # panel.children.add(commandLineWidget)

    self.widget.layoutWidget(rect(vec2(0, 0), self.platform.size), frameIndex, self.platform.layoutOptions)

  # views
  mainPanel.children.setLen 0
  let rects = self.layout.layoutViews(self.layout_props, rect(0, 0, 1, 1), self.views.len)
  for i, view in self.views:
    var widget: WPanel
    var isNew = false
    if widgetsPerEditor.contains(view.editor.id):
      widget = widgetsPerEditor[view.editor.id]
    else:
      widget = WPanel(lastHierarchyChange: frameIndex)
      widgetsPerEditor[view.editor.id] = widget
      isNew = true

    if i < rects.len:
      widget.anchor = (rects[i].xy, rects[i].xwyh)
      widget.right = -1

      # If we newly created this widget then perform one layout first so that the bounds are know for updateWidget
      if isNew:
        widget.layoutWidget(self.widget.lastBounds, frameIndex, self.platform.layoutOptions)

      mainPanel.children.add widget
      view.editor.active = self.currentView == i
      view.editor.updateWidget(self, widget, frameIndex)
      mainPanel.lastHierarchyChange = max(mainPanel.lastHierarchyChange, widget.lastHierarchyChange)

  mainStack.lastHierarchyChange = max(mainStack.lastHierarchyChange, mainPanel.lastHierarchyChange)

  # popups
  let lastPopups: seq[WWidget] = mainStack.children[1..^1]
  mainStack.children.setLen 1
  for i, popup in self.popups:
    var widget: WPanel
    var isNew = false
    if widgetsPerEditor.contains(popup.id):
      widget = widgetsPerEditor[popup.id]
    else:
      widget = WPanel(backgroundColor: color(1, 0, 1), fillBackground: true, lastHierarchyChange: frameIndex, logLayout: true)
      widgetsPerEditor[popup.id] = widget
      isNew = true

    widget.anchor = (vec2(0.25, 0.25), vec2(0.75, 0.75))

    # If we newly created this widget then perform one layout first so that the bounds are know for updateWidget
    if isNew:
      widget.layoutWidget(self.widget.lastBounds, frameIndex, self.platform.layoutOptions)

    mainStack.children.add widget
    # view.editor.updateWidget(self, widget, frameIndex)
    mainStack.lastHierarchyChange = max(mainStack.lastHierarchyChange, widget.lastHierarchyChange)

  for p in lastPopups:
    if mainStack.children.contains(p):
      continue
    for c in mainStack.children:
      c.invalidate(frameIndex, p.lastBounds)

  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, mainStack.lastHierarchyChange)
  mainStack.updateInvalidationFromChildren(currentIndex = -1, recurse = false)
  self.widget.updateInvalidationFromChildren(currentIndex = -1, recurse = false)

  # Status bar
  self.updateStatusBar(frameIndex, commandLineWidget)
  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, commandLineWidget.lastHierarchyChange)

proc layoutWidgetTree*(self: Editor, size: Vec2, frameIndex: int) =
  self.lastBounds = rect(vec2(0, 0), size)
  if self.widget.isNil:
    return

  self.widget.layoutWidget(self.lastBounds, frameIndex, self.platform.layoutOptions)