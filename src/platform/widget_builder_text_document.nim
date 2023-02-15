import std/[strformat]
import util, editor, document_editor, text_document, custom_logger, widgets, platform, timer, theme
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import vmath, bumpy, chroma

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

method updateWidget*(self: TextDocumentEditor, app: Editor, widget: WPanel, frameIndex: int) =
  let lineHeight = app.platform.lineHeight
  let totalLineHeight = app.platform.totalLineHeight
  let charWidth = app.platform.charWidth

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

    let mode = if self.currentMode.len == 0: "normal" else: self.currentMode
    headerPart1Text.text = fmt" {mode} - {self.document.filename} "
    headerPart2Text.text = fmt" {self.selection} - {self.id} "

    headerPanel.updateLastHierarchyChangeFromChildren frameIndex
  else:
    headerPanel.bottom = 0
    contentPanel.top = 0

  widget.lastHierarchyChange = max(widget.lastHierarchyChange, headerPanel.lastHierarchyChange)

  contentPanel.updateBackgroundColor(
    if self.active: app.theme.color("editor.background", rgb(25, 25, 40)) else: app.theme.color("editor.background", rgb(25, 25, 25)) * 0.75,
    frameIndex)

  if not (contentPanel.changed(frameIndex) or self.dirty):
    return

  self.dirty = false

  # either layout or content changed, update the lines
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

  let textColor = app.theme.color("editor.foreground", rgb(225, 200, 200))

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
      let color = if part.scope.len == 0: textColor else: app.theme.tokenColor(part.scope, rgb(255, 200, 200))
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

  self.lastContentBounds = widget.lastBounds

  debugf"rerender {contentPanel.children.len} lines for {self.document.filename} took {timer.elapsed.ms:>5.2}ms"

