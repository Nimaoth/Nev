import std/[tables]
import app, custom_logger, document_editor, widgets, platform, rect_utils, theme
import widget_builders_base, widget_builder_ast_document, widget_builder_text_document, widget_builder_selector_popup, widget_builder_model_document
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

proc updateStatusBar*(self: App, frameIndex: int, statusBarWidget: WPanel, completionsPanel: WPanel) =
  var statusWidget: WText
  var commandLineWidget: WPanel
  if statusBarWidget.len == 0:
    statusWidget = WText(anchor: (vec2(0, 0), vec2(1, 0.5)), lastHierarchyChange: frameIndex)
    statusBarWidget.add statusWidget

    commandLineWidget = WPanel(anchor: (vec2(0, 0.5), vec2(1, 1)), lastHierarchyChange: frameIndex)
    statusBarWidget.add commandLineWidget

    statusWidget.layoutWidget(statusBarWidget.lastBounds, frameIndex, self.platform.layoutOptions)
    commandLineWidget.layoutWidget(statusBarWidget.lastBounds, frameIndex, self.platform.layoutOptions)
  else:
    statusWidget = statusBarWidget[0].WText
    commandLineWidget = statusBarWidget[1].WPanel

  let textColor = self.theme.color("editor.foreground", rgb(225, 200, 200))

  statusWidget.text = if self.currentMode.len == 0: "normal" else: self.currentMode
  statusWidget.updateForegroundColor(textColor, frameIndex)
  statusWidget.updateLastHierarchyChangeFromChildren frameIndex
  statusBarWidget.lastHierarchyChange = max(statusBarWidget.lastHierarchyChange, statusWidget.lastHierarchyChange)

  self.getCommandLineTextEditor.active = self.commandLineMode
  self.getCommandLineTextEditor.updateWidget(self, commandLineWidget, completionsPanel, frameIndex)
  statusBarWidget.lastHierarchyChange = max(statusBarWidget.lastHierarchyChange, commandLineWidget.lastHierarchyChange)

var commandLineWidget: WPanel
var mainStack: WStack
var viewPanel: WPanel
var mainPanel: WPanel
var completionsPanel: WPanel
var widgetsPerEditor = initTable[EditorId, WPanel]()

proc updateWidgetTree*(self: App, frameIndex: int) =
  if self.widget.isNil:
    mainStack = WStack(anchor: (vec2(0, 0), vec2(1, 1)), right: -1)
    self.widget = mainStack

    mainPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))
    mainStack.children.add(mainPanel)

    completionsPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)))

    viewPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), bottom: -2 * self.platform.totalLineHeight)
    mainPanel.add(viewPanel)

    commandLineWidget = WPanel(anchor: (vec2(0, 1), vec2(1, 1)), top: -2 * self.platform.totalLineHeight, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    mainPanel.add(commandLineWidget)

    self.widget.layoutWidget(rect(vec2(0, 0), self.platform.size), frameIndex, self.platform.layoutOptions)

  completionsPanel.layoutWidget(mainStack.lastBounds, frameIndex, self.platform.layoutOptions)

  # views
  let previousChildren = viewPanel.children[0..^1]
  viewPanel.setLen 0

  let rects = self.layout.layoutViews(self.layout_props, rect(0, 0, 1, 1), self.views.len)
  for i, view in self.views:
    var widget: WPanel
    if widgetsPerEditor.contains(view.editor.id):
      widget = widgetsPerEditor[view.editor.id]
    else:
      widget = WPanel(lastHierarchyChange: frameIndex)
      widgetsPerEditor[view.editor.id] = widget

    if i < rects.len:
      widget.anchor = (rects[i].xy, rects[i].xwyh)

      if viewPanel.children.len > previousChildren.high or widget.WWidget != previousChildren[viewPanel.children.len]:
        view.editor.markDirty(notify=false)

      widget.layoutWidget(viewPanel.lastBounds, frameIndex, self.platform.layoutOptions)

      viewPanel.add widget

      let wasActive = view.editor.active
      view.editor.active = self.currentView == i
      if view.editor.active != wasActive:
        view.editor.markDirty(notify=false)

      view.editor.updateWidget(self, widget, completionsPanel, frameIndex)
      viewPanel.lastHierarchyChange = max(viewPanel.lastHierarchyChange, widget.lastHierarchyChange)

  mainPanel.lastHierarchyChange = max(mainPanel.lastHierarchyChange, viewPanel.lastHierarchyChange)

  if mainStack.children[mainStack.children.high] == completionsPanel:
    discard mainStack.children.pop()

  # popups
  let lastPopups: seq[WWidget] = mainStack.children[1..^1]
  mainStack.children.setLen 1
  for i, popup in self.popups:
    var widget: WPanel
    if widgetsPerEditor.contains(popup.id):
      widget = widgetsPerEditor[popup.id]
    else:
      widget = WPanel(backgroundColor: color(1, 0, 1), flags: &{FillBackground}, lastHierarchyChange: frameIndex)
      widgetsPerEditor[popup.id] = widget

    widget.anchor = (vec2(0.25, 0.25), vec2(0.75, 0.75))

    widget.layoutWidget(mainStack.lastBounds, frameIndex, self.platform.layoutOptions)

    mainStack.children.add widget
    popup.updateWidget(self, widget, completionsPanel, frameIndex)
    mainStack.lastHierarchyChange = max(mainStack.lastHierarchyChange, widget.lastHierarchyChange)

  self.updateStatusBar(frameIndex, commandLineWidget, completionsPanel)
  mainPanel.updateLastHierarchyChange commandLineWidget.lastHierarchyChange

  if completionsPanel.children.len > 0:
    mainStack.children.add completionsPanel
    mainStack.updateLastHierarchyChange completionsPanel.lastHierarchyChange

  mainStack.updateLastHierarchyChange mainPanel.lastHierarchyChange

  # invalidate the bounds of all popups which existed in the previous frame but don't exist anymore
  for p in lastPopups:
    if mainStack.children.contains(p):
      continue
    for c in mainStack.children:
      c.invalidate(frameIndex, p.lastBounds)

  mainStack.updateInvalidationFromChildren(currentIndex = -1, recurse = false)

  # Status bar
  self.widget.lastHierarchyChange = max(self.widget.lastHierarchyChange, commandLineWidget.lastHierarchyChange)

proc layoutWidgetTree*(self: App, size: Vec2, frameIndex: int) =
  self.lastBounds = rect(vec2(0, 0), size)
  if self.widget.isNil:
    return

  self.widget.layoutWidget(self.lastBounds, frameIndex, self.platform.layoutOptions)