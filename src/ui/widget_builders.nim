import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_builder_text_document, widget_builder_selector_popup,
  widget_builder_debugger, widget_builder_terminal, widget_library]
import app, document_editor, theme, compilation_config, view, layout, config_provider, command_service, toast

when enableAst:
  import ui/[widget_builder_model_document]

{.push gcsafe.}
{.push raises: [].}

logCategory "widget_builder"

method createUI*(self: EditorView, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  self.resetDirty()
  self.editor.createUI(builder, app)

proc updateWidgetTree*(self: App, frameIndex: int) =
  # self.platform.builder.buildUINodes()

  var headerColor = if self.commands.commandLineMode: self.themes.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: self.themes.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1

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
          let view {.cursor.} = self.layout.views[self.layout.currentView]
          let wasActive = view.active
          if not self.commands.commandLineMode:
            view.activate()
          else:
            view.deactivate()
          if view.active != wasActive:
            view.markDirty(notify=false)

          let bounds = overlay.bounds
          builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
            overlays.add view.createUI(builder, self)

        else:
          let rects = self.layout.layout.layoutViews(self.layout.layout_props, rect(0, 0, 1, 1), self.layout.views.len)
          for i, view in self.layout.views:
            let xy = rects[i].xy * overlay.bounds.wh
            let xwyh = rects[i].xwyh * overlay.bounds.wh
            let bounds = rect(xy, xwyh - xy)

            let wasActive = view.active
            if (self.layout.currentView == i) and not self.commands.commandLineMode:
              view.activate()
            else:
              view.deactivate()

            if view.active != wasActive:
              view.markDirty(notify=false)

            builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
              overlays.add view.createUI(builder, self)

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
