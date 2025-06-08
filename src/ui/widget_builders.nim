import std/[sugar, os]
import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_builder_text_document, widget_builder_selector_popup,
  widget_builder_debugger, widget_builder_terminal, widget_library]
import app, document_editor, theme, compilation_config, view, layout, config_provider, command_service, toast
import terminal_service

when enableAst:
  import ui/[widget_builder_model_document]

{.push gcsafe.}
{.push raises: [].}

logCategory "widget_builder"

method createUI*(self: EditorView, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()
  self.editor.createUI(builder, app)

method createUI*(self: HorizontalLayout, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()
  let mainSplit = 0.5
  var rects = newSeq[Rect]()
  var rect = rect(0, 0, 1, 1)
  for i, c in self.children:
    let ratio = if i == 0 and self.children.len > 1:
      mainSplit
    else:
      1.0 / (self.children.len - i).float32
    let (view_rect, remaining) = rect.splitV(ratio.percent)
    rect = remaining
    rects.add view_rect

  for i, c in self.children:
    if c != nil:
      let xy = rects[i].xy * builder.currentParent.bounds.wh
      let xwyh = rects[i].xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
        result.add c.createUI(builder, app)
    else:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

  if self.children.len == 0:
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: VerticalLayout, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()
  let mainSplit = 0.5
  var rects = newSeq[Rect]()
  var rect = rect(0, 0, 1, 1)
  for i, c in self.children:
    let ratio = if i == 0 and self.children.len > 1:
      mainSplit
    else:
      1.0 / (self.children.len - i).float32
    let (view_rect, remaining) = rect.splitH(ratio.percent)
    rect = remaining
    rects.add view_rect

  for i, c in self.children:
    if c != nil:
      let xy = rects[i].xy * builder.currentParent.bounds.wh
      let xwyh = rects[i].xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
        result.add c.createUI(builder, app)
    else:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

  if self.children.len == 0:
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: AlternatingLayout, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()
  let mainSplit = 0.5
  var rects = newSeq[Rect]()
  var rect = rect(0, 0, 1, 1)
  for i, c in self.children:
    let ratio = if i == 0 and self.children.len > 1:
      mainSplit
    elif i == self.children.len - 1:
      1.0
    else:
      0.5
    let (view_rect, remaining) = if i mod 2 == 0:
      rect.splitV(ratio.percent)
    else:
      rect.splitH(ratio.percent)
    rect = remaining
    rects.add view_rect

  for i, c in self.children:
    if c != nil:
      let xy = rects[i].xy * builder.currentParent.bounds.wh
      let xwyh = rects[i].xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
        result.add c.createUI(builder, app)
    else:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

  if self.children.len == 0:
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: TabLayout, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()
  let activeTabColor = app.themes.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
  let inactiveTabColor = app.themes.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  let textColor = app.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

  let width = app.uiSettings.tabHeaderWidth.get()

  let index = self.activeIndex.clamp(0, self.children.high)
  builder.panel(&{FillX, FillY, LayoutVertical}):
    # tabs
    builder.panel(&{FillX, LayoutHorizontal, FillBackground}, h = builder.textHeight, backgroundColor = inactiveTabColor):
      builder.panel(&{SizeToContentX, FillY, DrawText}, text = "| ", textColor = textColor)
      for i, c in self.children:
        let i = i
        if i > 0:
          builder.panel(&{SizeToContentX, FillY, DrawText}, text = " | ", textColor = textColor)

        let backgroundColor = if i == index:
          activeTabColor
        else:
          inactiveTabColor

        builder.panel(&{SizeToContentX, FillY, LayoutHorizontal, FillBackground}, backgroundColor = backgroundColor):
          capture i:
            onClickAny btn:
              self.activeIndex = i
              app.requestRender()

          let leaf = c.activeLeafView()
          let desc = if leaf != nil:
            leaf.display()
          else:
            "-"

          let headLen = desc.splitPath.head.len
          var highlightIndices = newSeq[int]()
          for i in (headLen + 1)..desc.high:
            highlightIndices.add(i)
          discard builder.highlightedText(desc, highlightIndices, textColor.darken(0.2), textColor, width)

      builder.panel(&{SizeToContentX, FillY, DrawText}, text = " |", textColor = textColor)

    builder.panel(&{FillX, FillY}):
      if index in 0..self.children.high:
        result.add self.children[index].createUI(builder, app)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: MainLayout, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()

  var rects: array[5, Rect]
  var remaining = rect(0, 0, 1, 1)
  if self.left != nil:
    (rects[0], remaining) = remaining.splitV(0.20.percent)
  if self.right != nil:
    (remaining, rects[1]) = remaining.splitV(0.70.percent)
  if self.top != nil:
    (rects[2], remaining) = remaining.splitH(0.25.percent)
  if self.bottom != nil:
    (remaining, rects[3]) = remaining.splitH(0.66.percent)

  rects[4] = remaining

  for i, c in self.children:
    if c != nil:
      let xy = rects[i].xy * builder.currentParent.bounds.wh
      let xwyh = rects[i].xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
        result.add c.createUI(builder, app)

  if self.center == nil:
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

proc updateWidgetTree*(self: App, frameIndex: int) =
  # self.platform.builder.buildUINodes()

  var headerColor = if self.commands.commandLineMode: self.themes.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: self.themes.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1

  self.layout.preRender()

  let newActiveView = self.layout.layout.activeLeafView()
  if newActiveView != self.layout.activeView and newActiveView != nil:
    if self.layout.activeView != nil:
      self.layout.activeView.deactivate()
    newActiveView.activate()
    self.layout.activeView = newActiveView
    newActiveView.markDirty(notify=false)

  var rootFlags = &{FillX, FillY, OverlappingChildren, MaskContent}
  let builder = self.platform.builder
  builder.panel(rootFlags): # fullscreen overlay

    let rootBounds = currentNode.bounds
    self.preRender(currentNode.bounds)

    var overlays: seq[OverlayFunction]
    var mainBounds: Rect

    builder.panel(&{FillX, FillY, LayoutVerticalReverse}): # main panel
      builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse, FillBackground}, backgroundColor = headerColor, pivot = vec2(0, 1)): # status bar
        let textColor = self.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

        let maxViews = self.uiSettings.maxViews.get()
        let maximizedText = if self.layout.maximizeView:
          "[Fullscreen]"
        elif maxViews == int.high:
          fmt"[Max: ∞]"
        else:
          fmt"[Max: {maxViews}]"

        let modeText = if self.currentMode.len == 0: "[No Mode]" else: self.currentMode
        let sessionText = if self.sessionFile.len == 0: "[No Session]" else: fmt"[Session: {self.sessionFile}]"
        let text = fmt"{maximizedText} | {modeText} | {sessionText}"

        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = text, textColor = textColor, pivot = vec2(1, 0))
        builder.panel(&{}, w = builder.charWidth)
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = self.inputHistory, textColor = textColor, pivot = vec2(1, 0))

        builder.panel(&{FillX, SizeToContentY}, pivot = vec2(1, 0)):
          let wasActive = self.commands.commandLineEditor.active
          self.commands.commandLineEditor.active = self.commands.commandLineMode
          if self.commands.commandLineEditor.active != wasActive:
            self.commands.commandLineEditor.markDirty(notify=false)

          builder.pushMaxBounds(rootBounds.wh * vec2(0.75, 0.5))
          defer:
            builder.popMaxBounds()
          overlays.add self.commands.commandLineEditor.createUI(builder, self)

      builder.panel(&{FillX, FillY}, pivot = vec2(0, 1)): # main panel
        mainBounds = currentNode.bounds
        let overlay = currentNode

        if self.layout.maximizeView:
          let bounds = overlay.bounds
          builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
            let view = self.layout.layout.activeLeafView()
            if view != nil:
              overlays.add view.createUI(builder, self)
            else:
              builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

        else:
          overlays.add self.layout.layout.createUI(builder, self)

    # popups
    for i, popup in self.layout.popups:
      overlays.add popup.createUI(builder, self)

    let textColor = self.themes.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
    let paddingX = builder.charWidth
    let paddingY = builder.charWidth
    builder.panel(&{FillX, LayoutVerticalReverse}, x = currentNode.w * 0.7, y = mainBounds.y + paddingY, h = mainBounds.h - paddingY * 2):
      for i in countdown(self.toast.toasts.high, 0):
        let toast {.cursor.} = self.toast.toasts[i]
        let color = self.themes.theme.tokenColor(toast.color, textColor)
        builder.panel(&{SizeToContentY, LayoutVertical, FillBackground}, pivot = vec2(0, 1), w = currentNode.w - paddingX, backgroundColor = headerColor):
          builder.panel(&{FillX}, h = paddingY)
          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, x = paddingX, text = toast.title, textColor = color)
          builder.panel(&{FillX}, h = paddingY)
          builder.panel(&{SizeToContentY, DrawText, TextWrap}, x = paddingX, w = currentNode.w - paddingX * 2, text = toast.message, textColor = textColor)
          builder.panel(&{FillX}, h = paddingY)
          builder.panel(&{FillBackground}, x = paddingX, w = (currentNode.w - paddingX * 2) * (1 - toast.progress), h = max(0.1 * builder.textHeight, 1), backgroundColor = color)
          builder.panel(&{FillX}, h = paddingY)

        if i > 0:
          builder.panel(&{FillX}, h = paddingY)

    for overlay in overlays:
      overlay()

    if self.showNextPossibleInputs:
      let inputLines = self.uiSettings.whichKeyHeight.get()
      let continuesTextColor = self.themes.theme.tokenColor("keyword", color(225/255, 200/255, 200/255))
      let keysTextColor = self.themes.theme.tokenColor("number", color(225/255, 200/255, 200/255))
      builder.renderCommandKeys(self.nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, inputLines, mainBounds)
