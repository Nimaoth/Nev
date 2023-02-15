import std/[strformat, tables]
import editor, custom_logger, widgets, platform, timer, rect_utils, theme, widget_builders_base, widget_builder_text_document
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
var mainPanel: WPanel
var widgetsPerEditor = initTable[EditorId, WPanel]()

proc updateWidgetTree*(self: Editor, frameIndex: int) =
  if self.widget.isNil:
    var panel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))
    self.widget = panel
    mainPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), bottom: -self.platform.totalLineHeight - 1, right: -1, foregroundColor: color(1, 0, 0))
    panel.children.add(mainPanel)
    commandLineWidget = WText(text: "command line", anchor: (vec2(0, 1), vec2(1, 1)), top: -self.platform.totalLineHeight, fillBackground: true, backgroundColor: color(0, 0, 0), foregroundColor: color(1, 0, 1))
    # panel.children.add(commandLineWidget)

    self.widget.layoutWidget(rect(vec2(0, 0), self.platform.size), frameIndex, self.platform.layoutOptions)

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
        widget.layoutWidget(self.widget.lastBounds, frameIndex, self.platform.layoutOptions)

      mainPanel.children.add widget
      view.editor.updateWidget(self, widget, frameIndex)
      mainPanel.lastHierarchyChange = max(mainPanel.lastHierarchyChange, widget.lastHierarchyChange)

  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, mainPanel.lastHierarchyChange)

  # Status bar
  self.updateStatusBar(frameIndex, commandLineWidget)
  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, commandLineWidget.lastHierarchyChange)

proc layoutWidgetTree*(self: Editor, size: Vec2, frameIndex: int) =
  self.lastBounds = rect(vec2(0, 0), size)
  if self.widget.isNil:
    return

  self.widget.layoutWidget(self.lastBounds, frameIndex, self.platform.layoutOptions)