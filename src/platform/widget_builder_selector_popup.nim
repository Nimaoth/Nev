import util, app, selector_popup, custom_logger, widgets, platform, theme, widget_builders_base
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

method updateWidget*(self: FileSelectorItem, app: App, widget: WPanel, frameIndex: int) =
  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var text = if widget.len == 0:
    var text = WText(anchor: (vec2(0, 0), vec2(1, 1)), lastHierarchyChange: frameIndex)
    widget.add text
    text
  else:
    widget[0].WText

  text.text = self.path
  text.updateForegroundColor(textColor, frameIndex)
  text.updateLastHierarchyChangeFromChildren()

method updateWidget*(self: TextSymbolSelectorItem, app: App, widget: WPanel, frameIndex: int) =
  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))
  let scopeColor = app.theme.tokenColor("string", rgb(175, 255, 175))
  let charWidth = app.platform.charWidth

  var (nameText, typeText) = if widget.len == 0:
    var nameText = WText(anchor: (vec2(0, 0), vec2(0, 0)), right: self.symbol.name.len.float * charWidth, lastHierarchyChange: frameIndex)
    var typeText = WText(anchor: (vec2(1, 0), vec2(1, 1)), left: -($self.symbol.symbolType).len.float * charWidth, pivot: vec2(0, 0), lastHierarchyChange: frameIndex)
    widget.add nameText
    widget.add typeText
    (nameText, typeText)
  else:
    (widget[0].WText, widget[1].WText)

  nameText.text = self.symbol.name
  nameText.right = self.symbol.name.len.float * charWidth
  nameText.updateForegroundColor(textColor, frameIndex)
  nameText.updateLastHierarchyChangeFromChildren()

  typeText.text = $self.symbol.symbolType
  typeText.right = -($self.symbol.symbolType).len.float * charWidth
  typeText.updateForegroundColor(scopeColor, frameIndex)
  typeText.updateLastHierarchyChangeFromChildren()

method updateWidget*(self: ThemeSelectorItem, app: App, widget: WPanel, frameIndex: int) =
  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

  var text = if widget.len == 0:
    var text = WText(anchor: (vec2(0, 0), vec2(1, 1)), lastHierarchyChange: frameIndex)
    widget.add text
    text
  else:
    widget[0].WText

  text.text = self.path
  text.updateForegroundColor(textColor, frameIndex)
  text.updateLastHierarchyChangeFromChildren()

method updateWidget*(self: SelectorPopup, app: App, widget: WPanel, completionsPanel: WPanel, frameIndex: int) =
  let totalLineHeight = app.platform.totalLineHeight

  var headerPanel: WPanel
  var contentPanel: WPanel
  if widget.len == 0:
    headerPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 0)), bottom: totalLineHeight, lastHierarchyChange: frameIndex, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    widget.add(headerPanel)

    contentPanel = WPanel(anchor: (vec2(0, 0), vec2(1, 1)), top: totalLineHeight, lastHierarchyChange: frameIndex, flags: &{FillBackground}, backgroundColor: color(0, 0, 0))
    contentPanel.maskContent = true
    widget.add(contentPanel)

    headerPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
    contentPanel.layoutWidget(widget.lastBounds, frameIndex, app.platform.layoutOptions)
  else:
    headerPanel = widget[0].WPanel
    contentPanel = widget[1].WPanel

  self.textEditor.updateWidget(app, headerPanel, completionsPanel, frameIndex)
  headerPanel.updateLastHierarchyChangeFromChildren frameIndex

  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.updateBackgroundColor(app.theme.color("panel.background", rgb(25, 25, 25)), frameIndex)
  self.lastContentBounds = contentPanel.lastBounds

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

  while contentPanel.len > numRenderedItems:
    discard contentPanel.pop

  while contentPanel.len < numRenderedItems:
    contentPanel.add WPanel(anchor: (vec2(0, 0), vec2(1, 0)))

  let selectionColor = app.theme.color("list.activeSelectionBackground", rgb(200, 200, 200))

  var top = 0.0
  var widgetIndex = 0
  for completionIndex in self.scrollOffset..lastRenderedIndex:
    defer: inc widgetIndex
    var lineWidget = contentPanel[widgetIndex].WPanel
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
