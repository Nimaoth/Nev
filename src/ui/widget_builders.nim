import std/[sugar, os, strutils, sets]
import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils, jsonex]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_builder_text_document, widget_builder_selector_popup, widget_library]
import document_editor, theme, compilation_config, view, layout, config_provider, command_service, toast, document_editor_render
import text/text_editor
import render_view, dynamic_view
from scripting_api import nil
import vcs/vcs, service

when enableAst:
  import ui/[widget_builder_model_document]

{.push gcsafe.}
{.push raises: [].}

logCategory "widget_builder"

type BorderFlags = object
  left: bool
  right: bool
  top: bool
  bottom: bool

renderEditorImpl = proc(self: DocumentEditor, builder: UINodeBuilder): seq[document_editor_render.OverlayRenderFunc] =
  self.createUI(builder)

proc none(_: typedesc[BorderFlags]): BorderFlags = BorderFlags()

var borderFlagStack = newSeq[BorderFlags]()

proc resetBorderFlags() {.gcsafe.} =
  {.gcsafe.}:
    borderFlagStack = @[BorderFlags.none()]

method createUI*(self: DynamicView, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.render != nil:
    return self.render(builder)
  else:
    self.resetDirty()
  return @[]

method createUI*(self: EditorView, builder: UINodeBuilder): seq[OverlayFunction] =
  self.resetDirty()
  self.editor.createUI(builder)

method createUI*(self: RenderView, builder: UINodeBuilder): seq[OverlayFunction] =
  builder.panel(&{FillX, FillY, FillBackground, MaskContent}, backgroundColor = color(0, 0, 0)):
    onClickAny btn:
      self.layout.tryActivateView(self)
      self.mouseStates.incl(btn.int64)

    self.bounds = currentNode.boundsAbsolute
    self.render()
    currentNode.renderCommands = self.commands
    currentNode.markDirty(builder)

  self.resetDirty()

method createUI*(self: HorizontalLayout, builder: UINodeBuilder): seq[OverlayFunction] =
  self.resetDirty()

  builder.panel(&{FillX, FillY}, tag = "horizontal"):
    if self.children.len == 0:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))
      return

    if self.maximize:
      builder.panel(&{FillX, FillY}):
        result.add self.children[self.activeIndex].createUI(builder)
      return

    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = rect.splitV(ratio.percent)
      rect = remaining
      rects.add view_rect

    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
    let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

    for i, c in self.children:
      var xy = (rects[i].xy * builder.currentParent.bounds.wh).floor()
      if i > 0:
        builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x, y = -1, w = 1, h = builder.currentParent.bounds.h + 2, border = border(1, 0, 0, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
        builder.currentChild.markDirty(builder)
        xy.x += 1

      let xwyh = (rects[i].xwyh * builder.currentParent.bounds.wh).floor()
      let bounds = rect(xy, xwyh - xy)

      if c != nil:
        builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "hori-slot"):
          if bounds.w > 0 and bounds.h > 0:
            result.add c.createUI(builder)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: VerticalLayout, builder: UINodeBuilder): seq[OverlayFunction] =
  self.resetDirty()

  builder.panel(&{FillX, FillY}, tag = "vertical"):

    if self.children.len == 0:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))
      return

    if self.maximize:
      builder.panel(&{FillX, FillY}):
        result.add self.children[self.activeIndex].createUI(builder)
      return

    var rects = newSeq[Rect]()
    var rect = rect(0, 0, 1, 1)
    for i, c in self.children:
      let ratio = if i == 0 and self.children.len > 1:
        self.getSplitRatio(i)
      elif i == self.children.len - 1:
        1.0
      else:
        self.getSplitRatio(i)
      let (view_rect, remaining) = rect.splitH(ratio.percent)
      rect = remaining
      rects.add view_rect

    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
    let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

    for i, c in self.children:
      var xy = (rects[i].xy * builder.currentParent.bounds.wh).floor()
      if i > 0:
        builder.panel(&{DrawBorder, DrawBorderTerminal}, x = -1, y = xy.y, w = builder.currentParent.bounds.w + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
        builder.currentChild.markDirty(builder)
        xy.y += 1

      let xwyh = (rects[i].xwyh * builder.currentParent.bounds.wh).floor()
      let bounds = rect(xy, xwyh - xy)

      if c != nil:
        builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "vert-slot"):
          if bounds.w > 0 and bounds.h > 0:
            result.add c.createUI(builder)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: AlternatingLayout, builder: UINodeBuilder): seq[OverlayFunction] =
  self.resetDirty()
  if self.children.len == 0:
    builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))
    return

  if self.maximize:
    builder.panel(&{FillX, FillY}):
      result.add self.children[self.activeIndex].createUI(builder)
    return

  var rects = newSeq[Rect]()
  var rect = rect(0, 0, 1, 1)
  for i, c in self.children:
    let ratio = if i == 0 and self.children.len > 1:
      self.getSplitRatio(i)
    elif i == self.children.len - 1:
      1.0
    else:
      self.getSplitRatio(i)
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
      builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "alt-slot"):
        if bounds.w > 0 and bounds.h > 0:
          result.add c.createUI(builder)
    else:
      builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

import app
method createUI*(self: TabLayout, builder: UINodeBuilder): seq[OverlayFunction] =
  let app = ({.gcsafe.}: gEditor)

  self.resetDirty()
  let activeTabColor = builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255))
  let inactiveTabColor = builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
  let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

  let width = app.uiSettings.tabHeaderWidth.get()
  let hideTabBarWhenSingle = app.uiSettings.hideTabBarWhenSingle.get()

  let index = self.activeIndex.clamp(0, self.children.high)
  builder.panel(&{FillX, FillY, LayoutVertical}, tag = "tab"):
    # tabs
    if not hideTabBarWhenSingle or self.children.len > 1:
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
                # app.requestRender() # todo

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

      let w = currentNode.w
      builder.panel(&{DrawBorder, DrawBorderTerminal}, x = -1, w = w + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")

    builder.panel(&{FillX, FillY, MaskContent}, tag = "tab-slot"):
      if index in 0..self.children.high:
        result.add self.children[index].createUI(builder)
      else:
        builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

method createUI*(self: CenterLayout, builder: UINodeBuilder): seq[OverlayFunction] =
  self.resetDirty()

  var rects: array[5, Rect]
  var remaining = rect(0, 0, 1, 1)
  if self.left != nil:
    (rects[0], remaining) = remaining.splitV(self.splitRatios[0].percent)
  if self.right != nil:
    (remaining, rects[1]) = remaining.splitV(self.splitRatios[1].percent)
  if self.top != nil:
    (rects[2], remaining) = remaining.splitH(self.splitRatios[2].percent)
  if self.bottom != nil:
    (remaining, rects[3]) = remaining.splitH(self.splitRatios[3].percent)

  rects[4] = remaining

  let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
  let backgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))

  builder.panel(&{FillX, FillY}, tag = "center"):
    for i, c in self.children:
      if c != nil:
        var xy = (rects[i].xy * builder.currentParent.bounds.wh).floor()
        var xwyh = (rects[i].xwyh * builder.currentParent.bounds.wh).floor()
        if i == 0:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xwyh.x - 1, y = -1, w = 1, h = builder.currentParent.bounds.h + 1, border = border(1, 0, 0, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xwyh.x -= 1
        elif i == 1:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x, y = -1, w = 1, h = builder.currentParent.bounds.h + 1, border = border(1, 0, 0, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xy.x += 1
        elif i == 2:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x - 1, y = xwyh.y - 1, w = xwyh.x - xy.x + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xwyh.y -= 1
        elif i == 3:
          builder.panel(&{DrawBorder, DrawBorderTerminal}, x = xy.x - 1, y = xy.y, w = xwyh.x - xy.x + 2, h = 1, border = border(0, 0, 1, 0), borderColor = borderColor, backgroundColor = backgroundColor, tag = "separator")
          builder.currentChild.markDirty(builder)
          xy.y += 1

        let bounds = rect(xy, xwyh - xy)
        builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, tag = "center-slot"):
          if bounds.w > 0 and bounds.h > 0:
            result.add c.createUI(builder)

    if self.center == nil:
      let xy = remaining.xy * builder.currentParent.bounds.wh
      let xwyh = remaining.xwyh * builder.currentParent.bounds.wh
      let bounds = rect(xy, xwyh - xy)
      builder.panel(&{FillBackground}, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h, backgroundColor = color(0, 0, 0))

proc flushOverlays(builder: UINodeBuilder, overlays: var seq[OverlayFunction]) =
  for overlay in overlays:
    overlay()
    builder.panel(&{FlushBorders})
  overlays.setLen(0)

proc updateWidgetTree*(self: App, frameIndex: int) =
  self.platform.builder.theme = self.themes.theme

  var headerColor = if self.commands.commandLineMode: self.themes.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: self.themes.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1
  let textColor = self.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

  let newActiveView = self.layout.layout.activeLeafView()
  if newActiveView != self.layout.activeView and newActiveView != nil:
    if self.layout.activeView != nil:
      self.layout.activeView.deactivate()
    newActiveView.activate()
    self.layout.activeView = newActiveView
    newActiveView.markDirty(notify=false)

  resetBorderFlags()

  var rootFlags = &{FillX, FillY, OverlappingChildren, MaskContent}
  let builder = self.platform.builder
  builder.panel(rootFlags): # fullscreen overlay

    let rootBounds = currentNode.bounds
    self.preRender(currentNode.bounds)

    var overlays: seq[OverlayFunction]
    var commandLineOverlays: seq[OverlayFunction]
    var mainBounds: Rect

    builder.panel(&{FillX, FillY, LayoutVerticalReverse, DrawChildrenReverse}): # main panel

      # todo: handle self.statusBarOnTop
      builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse, FillBackground}, backgroundColor = headerColor, pivot = vec2(0, 1)): # status bar
        var i = 0

        proc section(text: string, foreground: Color, background: Color, extraFlags: UINodeFlags) =
          var flags = &{SizeToContentX, SizeToContentY, DrawText} + extraFlags
          if i > 0:
            builder.panel(flags, textColor = foreground, backgroundColor = background, text = " | ")
          builder.panel(flags, textColor = foreground, backgroundColor = background, text = text)
          inc i

        proc section(text: string, foreground: Option[string] = string.none, background: Option[string] = string.none) =
          var extraFlags = 0.UINodeFlags
          if background.isSome:
            extraFlags.incl FillBackground
          let foreground = foreground.mapIt(self.themes.theme.color(it, textColor))
          let background = background.mapIt(self.themes.theme.color(it, headerColor))
          section(text, foreground.get(textColor), background.get(headerColor), extraFlags)

        builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}, pivot = vec2(1, 0)):

          for s in self.uiSettings.statusLine.get():
            case s.kind
            of JString:
              case s.getStr
              of "mode":
                let modes = if self.layout.getActiveEditor().getSome(editor) and editor of TextDocumentEditor:
                  let modes = editor.TextDocumentEditor.settings.modes.get()
                  "[" & modes.join(", ") & "]"
                else:
                  ""
                section(modes)

              of "vcs.status":
                let vcss: VCSService = self.services.getServiceChecked(VCSService)
                for vcs in vcss.getAllVersionControlSystems():
                  section(&"[git: {vcs.status}]")
                  break

              of "layout":
                let layout = self.layout.layout.activeLeafLayout()
                let maximizedText = if self.layout.maximizeView:
                  "Fullscreen"
                elif layout != nil:
                  let maxText = if layout.maxChildren == int.high: "∞" else: $layout.maxChildren
                  if layout.maximize:
                    fmt"Max 1/{maxText}"
                  else:
                    fmt"{layout.children.len}/{maxText}"
                else:
                  ""
                section(&"[Layout {self.layout.layoutName} - {layout.desc} - {maximizedText}]")

              of "layout.min":
                let layout = self.layout.layout.activeLeafLayout()
                let maximizedText = if self.layout.maximizeView:
                  "Fullscreen"
                elif layout != nil:
                  let maxText = if layout.maxChildren == int.high: "∞" else: $layout.maxChildren
                  if layout.maximize:
                    fmt"Max 1/{maxText}"
                  else:
                    fmt"{layout.children.len}/{maxText}"
                else:
                  ""
                section(&"[{maximizedText}]")

              of "global-mode":
                let modeText = if self.currentMode.len == 0: "[No Mode]" else: self.currentMode
                section(modeText)

              of "session":
                let sessionText = if self.sessionFile.len == 0: "[No Session]" else: fmt"[{self.sessionFile}]"
                section(sessionText)

              else:
                discard

            else:
              discard

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
          commandLineOverlays.add self.commands.commandLineEditor.createUI(builder)

      builder.panel(&{FlushBorders})

      builder.panel(&{FillX, FillY, FlushBorders, MaskContent}, pivot = vec2(0, 1), tag = "main"): # main panel
        mainBounds = currentNode.bounds
        let overlay = currentNode

        if self.layout.maximizeView:
          let bounds = overlay.bounds
          builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
            let view = self.layout.layout.activeLeafView()
            if view != nil:
              overlays.add view.createUI(builder)
            else:
              builder.panel(&{FillX, FillY, FillBackground}, backgroundColor = color(0, 0, 0))

        else:
          overlays.add self.layout.layout.createUI(builder)

    builder.panel(&{FlushBorders})
    builder.flushOverlays(overlays)

    # popups
    for i, popup in self.layout.popups:
      overlays.add popup.createUI(builder)
      builder.panel(&{FlushBorders})
      builder.flushOverlays(overlays)

    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
    let textColor = self.themes.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
    var padding = (builder.charWidth * 0.75).floor
    if self.platform.backend == scripting_api.Terminal:
      padding = 0

    let toastWidth = floor(currentNode.w * 0.3)
    let toastMaxTime = self.uiSettings.toastDuration.get().float64 * 0.001
    let animateToasts = self.uiSettings.toastAnimation.get()
    builder.panel(&{LayoutVerticalReverse}, x = floor(currentNode.w * 0.7), y = mainBounds.y, w = toastWidth, h = mainBounds.h, border = border(builder.defaultBorderWidth), tag = "toasts"):
      for i in countdown(self.toast.toasts.high, 0):
        let toast {.cursor.} = self.toast.toasts[i]
        let color = self.themes.theme.tokenColor(toast.color, textColor)

        var xOffset = 0.0
        if animateToasts:
          let fadeOutTime = 0.175 / max(toastMaxTime, 1)
          let t = clamp((toast.progress - (1 - fadeOutTime)) / fadeOutTime, 0, 1)
          xOffset = toastWidth * t * t
          if xOffset > 0:
            self.platform.requestRender(true)

        builder.panel(&{FillX, SizeToContentY, LayoutVertical, FillBackground, DrawBorder, DrawBorderTerminal}, border = border(1), pivot = vec2(0, 1), backgroundColor = headerColor, borderColor = borderColor, tag = "toast"):
          currentNode.rawX = currentNode.boundsRaw.x + xOffset
          builder.panel(&{FillX, SizeToContentY, LayoutVertical}, border = border(padding)):
            if padding > 0: builder.panel(&{FillX}, h = padding)
            let contentWidth = currentNode.w - currentNode.border.left - currentNode.border.right
            builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.title, textColor = color)
            if padding > 0: builder.panel(&{FillX}, h = padding)
            builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.message, textColor = textColor)
            if padding > 0: builder.panel(&{FillX}, h = padding)
            builder.panel(&{DrawBorder, DrawBorderTerminal}, border = border(0, 0, builder.defaultBorderWidth, 0), w = (contentWidth - 2) * (1 - toast.progress), h = builder.defaultBorderWidth, borderColor = color, backgroundColor = headerColor, tag = "progress bar")

            if padding > 0: builder.panel(&{FillX}, h = padding)

        builder.updateSizeToContent(builder.currentChild)
        if i > 0:
          builder.panel(&{FillX}, h = builder.defaultBorderWidth, pivot = vec2(0, 1))

    builder.panel(&{FlushBorders})

    builder.flushOverlays(overlays)
    builder.flushOverlays(commandLineOverlays)

    if self.showNextPossibleInputs:
      let inputLines = self.uiSettings.whichKeyHeight.get()
      let continuesTextColor = self.themes.theme.tokenColor("keyword", color(225/255, 200/255, 200/255))
      let keysTextColor = self.themes.theme.tokenColor("number", color(225/255, 200/255, 200/255))
      builder.panel(&{FillX, SizeToContentY}, y = mainBounds.h):
        # let height = (inputLines + padding * 2).float * builder.textHeight
        builder.renderCommandKeys(self.nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, inputLines, mainBounds, padding = 1)
      builder.updateSizeToContent(builder.currentChild)
      builder.currentChild.rawY = mainBounds.h - builder.currentChild.bounds.h
