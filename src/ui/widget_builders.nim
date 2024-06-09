import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils]
import ui/node
import platform/platform
import ui/[widget_builders_base, widget_builder_text_document, widget_builder_selector_popup,
  widget_builder_debugger]
import app, document_editor, theme, compilation_config, view

when enableAst:
  import ui/[widget_builder_model_document]

logCategory "widget_builder"

proc updateWidgetTree*(self: App, frameIndex: int) =
  # self.platform.builder.buildUINodes()

  var headerColor = if self.commandLineMode: self.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: self.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1

  var rootFlags = &{FillX, FillY, OverlappingChildren, MaskContent}
  let builder = self.platform.builder
  builder.panel(rootFlags, backgroundColor = color(0, 0, 0)): # fullscreen overlay

    var overlays: seq[proc() {.closure.}]

    builder.panel(&{FillX, FillY, LayoutVerticalReverse}): # main panel
      builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse, FillBackground}, backgroundColor = headerColor, pivot = vec2(0, 1)): # status bar
        let textColor = self.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

        let maxViews = getOption[int](self, "editor.maxViews", int.high)
        let maximizedText = if self.maximizeView:
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
          let wasActive = self.getCommandLineTextEditor.active
          self.getCommandLineTextEditor.active = self.commandLineMode
          if self.getCommandLineTextEditor.active != wasActive:
            self.getCommandLineTextEditor.markDirty(notify=false)
          overlays.add self.getCommandLineTextEditor.createUI(builder, self)

      builder.panel(&{FillX, FillY}, pivot = vec2(0, 1)): # main panel
        let overlay = currentNode

        if self.maximizeView:
          let view {.cursor.} = self.views[self.currentView]
          let wasActive = view.active
          if not self.commandLineMode:
            view.activate()
          else:
            view.deactivate()
          if view.active != wasActive:
            view.markDirty(notify=false)

          let bounds = overlay.bounds
          builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
            overlays.add view.createUI(builder, self)

        else:
          let rects = self.layout.layoutViews(self.layout_props, rect(0, 0, 1, 1), self.views.len)
          for i, view in self.views:
            let xy = rects[i].xy * overlay.bounds.wh
            let xwyh = rects[i].xwyh * overlay.bounds.wh
            let bounds = rect(xy, xwyh - xy)

            let wasActive = view.active
            if (self.currentView == i) and not self.commandLineMode:
              view.activate()
            else:
              view.deactivate()

            if view.active != wasActive:
              view.markDirty(notify=false)

            builder.panel(0.UINodeFlags, x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h):
              overlays.add view.createUI(builder, self)

    # popups
    for i, popup in self.popups:
      overlays.add popup.createUI(builder, self)

    for overlay in overlays:
      overlay()
