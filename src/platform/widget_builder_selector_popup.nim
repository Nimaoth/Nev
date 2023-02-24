import std/[strformat, tables, sugar, sequtils]
import util, editor, selector_popup, custom_logger, widgets, platform, theme, widget_builders_base
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, SelectorPopup
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

method updateWidget*(self: SelectorItem, app: Editor, widget: WPanel, frameIndex: int) {.base.} = discard

method updateWidget*(self: FileSelectorItem, app: Editor, widget: WPanel, frameIndex: int) =
  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var text = if widget.children.len == 0:
    var text = WText(anchor: (vec2(0, 0), vec2(1, 1)), lastHierarchyChange: frameIndex)
    widget.children.add text
    text
  else:
    widget.children[0].WText

  text.text = self.path
  text.updateForegroundColor(textColor, frameIndex)
  text.updateLastHierarchyChangeFromChildren()

method updateWidget*(self: ThemeSelectorItem, app: Editor, widget: WPanel, frameIndex: int) =
  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var text = if widget.children.len == 0:
    var text = WText(anchor: (vec2(0, 0), vec2(1, 1)), lastHierarchyChange: frameIndex)
    widget.children.add text
    text
  else:
    widget.children[0].WText

  text.text = self.path
  text.updateForegroundColor(textColor, frameIndex)
  text.updateLastHierarchyChangeFromChildren()

method updateWidget*(self: SelectorPopup, app: Editor, widget: WPanel, frameIndex: int) =
  let lineHeight = app.platform.lineHeight
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var headerPanel: WPanel
  var contentPanel: WPanel
  if widget.children.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    widget.children.add(headerPanel)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, fillBackground: true, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.children.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
  else:
    headerPanel = widget.children[0].WPanel
    contentPanel = widget.children[1].WPanel

  self.textEditor.updateWidget(app, headerPanel, frameIndex)
  headerPanel.updateLastHierarchyChangeFromChildren frameIndex

  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.updateBackgroundColor(app.theme.color("panel.background", rgb(25, 25, 25)), frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty or app.platform.redrawEverything):
    return

  self.resetDirty()

  let maxLineCount = floor(widget.lastBounds.h / totalLineHeight).int
  let targetNumRenderedItems = min(maxLineCount, self.completions.len)
  var lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

  if self.selected < self.scrollOffset:
    self.scrollOffset = self.selected
    lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

  if self.selected > lastRenderedIndex:
    self.scrollOffset = max(self.selected - targetNumRenderedItems + 1, 0)
    lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

  let numRenderedItems = max(lastRenderedIndex - self.scrollOffset + 1, 0)

  while contentPanel.children.len > numRenderedItems:
    discard contentPanel.children.pop

  while contentPanel.children.len < numRenderedItems:
    contentPanel.children.add WPanel(anchor: (vec2(0, 0), vec2(1, 0)))

  let selectionColor = app.theme.color("list.activeSelectionBackground", rgb(200, 200, 200))

  var top = 0.0
  var widgetIndex = 0
  for completionIndex in self.scrollOffset..lastRenderedIndex:
    defer: inc widgetIndex
    var lineWidget = contentPanel.children[widgetIndex].WPanel
    lineWidget.top = top
    lineWidget.bottom = top + totalLineHeight
    lineWidget.lastHierarchyChange = frameIndex

    if completionIndex == self.selected:
      lineWidget.fillBackground = true
      lineWidget.updateBackgroundColor(selectionColor, frameIndex)
    else:
      lineWidget.fillBackground = false
      lineWidget.updateBackgroundColor(color(0, 0, 0), frameIndex)

    self.completions[completionIndex].updateWidget(app, lineWidget, frameIndex)
    top = lineWidget.bottom

  contentPanel.lastHierarchyChange = frameIndex
  widget.lastHierarchyChange = max(widget.lastHierarchyChange, contentPanel.lastHierarchyChange)
