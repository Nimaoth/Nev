import util, app, selector_popup, custom_logger, widgets, platform, theme, widget_builders_base
import vmath, bumpy, chroma
import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

method updateWidget*(self: FileSelectorItem, app: App, widget: WPanel, frameIndex: int) =
  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

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
  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  let scopeColor = app.theme.tokenColor("string", color(175/255, 255/255, 175/255))
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
  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

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

  contentPanel.updateBackgroundColor(app.theme.color("panel.background", color(25/255, 25/255, 25/255)), frameIndex)
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

  let selectionColor = app.theme.color("list.activeSelectionBackground", color(200/255, 200/255, 200/255))

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

method createUI*(self: FileSelectorItem, builder: UINodeBuilder, app: App) =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.path, textColor = textColor)

method createUI*(self: TextSymbolSelectorItem, builder: UINodeBuilder, app: App) =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  let scopeColor = app.theme.tokenColor("string", color(175/255, 255/255, 175/255))

  builder.panel(&{FillX, SizeToContentY}):
    builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.symbol.name, textColor = textColor)
    builder.panel(&{FillX, SizeToContentY, DrawText}, text = $self.symbol.symbolType, textColor = scopeColor)
    # typeText.right = -($self.symbol.symbolType).len.float * charWidth

method createUI*(self: ThemeSelectorItem, builder: UINodeBuilder, app: App) =
  let textColor = app.theme.color("editor.foreground", color(0.9, 0.8, 0.8))
  builder.panel(&{FillX, SizeToContentY, DrawText}, text = self.path, textColor = textColor)

method createUI*(self: SelectorPopup, builder: UINodeBuilder, app: App) =
  let dirty = self.dirty
  self.resetDirty()

  var flags = &{UINodeFlag.MaskContent, OverlappingChildren}
  var flagsInner = &{LayoutVertical}

  let sizeToContentX = false
  let sizeToContentY = true
  if sizeToContentX:
    flags.incl SizeToContentX
    flagsInner.incl SizeToContentX
  else:
    flags.incl FillX
    flagsInner.incl FillX

  if sizeToContentY:
    flags.incl SizeToContentY
    flagsInner.incl SizeToContentY
  else:
    flags.incl FillY
    flagsInner.incl FillY

  let bounds = builder.currentParent.boundsActual.shrink(absolute(0.25 * builder.currentParent.boundsActual.w), absolute(0.25 * builder.currentParent.boundsActual.h))
  builder.panel(&{SizeToContentY}, x = bounds.x, y = bounds.y, w = bounds.w, userId = self.userId):
    builder.panel(flags): #, userId = id):
      let totalLineHeight = app.platform.totalLineHeight
      let maxLineCount = if sizeToContentY:
        30
      else:
        floor(currentNode.boundsActual.h / totalLineHeight).int

      let targetNumRenderedItems = min(maxLineCount, self.completions.len)
      var lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

      if self.selected < self.scrollOffset:
        self.scrollOffset = self.selected
        lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

      if self.selected > lastRenderedIndex:
        self.scrollOffset = max(self.selected - targetNumRenderedItems + 1, 0)
        lastRenderedIndex = min(self.scrollOffset + targetNumRenderedItems - 1, self.completions.high)

      let numRenderedItems = max(lastRenderedIndex - self.scrollOffset + 1, 0)

      let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255)).withAlpha(1)
      let backgroundColor = app.theme.color("panel.background", color(0.1, 0.1, 0.1)).withAlpha(1)
      let selectionColor = app.theme.color("list.activeSelectionBackground", color(0.8, 0.8, 0.8)).withAlpha(1)

      block:
        builder.panel(flagsInner):
          builder.panel(&{FillX, SizeToContentY}):
            self.textEditor.createUI(builder, app)

          var top = 0.0
          var widgetIndex = 0
          for completionIndex in self.scrollOffset..lastRenderedIndex:
            defer: inc widgetIndex

            let backgroundColor = if completionIndex == self.selected:
              selectionColor
            else:
              backgroundColor

            builder.panel(&{FillX, SizeToContentY, FillBackground}, backgroundColor = backgroundColor):
              self.completions[completionIndex].createUI(builder, app)

          # builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = backgroundColor)
