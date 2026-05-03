import std/[sugar, os, strutils, sets]
import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils, jsonex]
import ui/node
import platform/platform, platform_service
import ui/[widget_builder_selector_popup, widget_library]
import document_editor, theme, view, layout/layout, config_provider, command_line, toast, document_editor_render
import popup
import render_view, dynamic_view, status_line
from scripting_api import nil
import vcs/vcs, service

{.push gcsafe.}
{.push raises: [].}

logCategory "widget_builder"

type BorderFlags = object
  left: bool
  right: bool
  top: bool
  bottom: bool

renderEditorImpl = proc(self: DocumentEditor, builder: UINodeBuilder): seq[document_editor_render.OverlayRenderFunc] =
  self.render(builder)

proc none(_: typedesc[BorderFlags]): BorderFlags = BorderFlags()

var borderFlagStack = newSeq[BorderFlags]()

proc resetBorderFlags() {.gcsafe.} =
  {.gcsafe.}:
    borderFlagStack = @[BorderFlags.none()]

method createUI*(self: DynamicView, builder: UINodeBuilder): seq[OverlayFunction] =
  if self.renderImpl != nil:
    return self.renderImpl(self, builder)
  else:
    self.resetDirty()
  return @[]

method createUI*(self: EditorView, builder: UINodeBuilder): seq[OverlayFunction] =
  assert self.editor.renderImpl != nil
  return self.editor.renderImpl(self.editor, builder)

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

proc flushOverlays(builder: UINodeBuilder, overlays: var seq[OverlayFunction]) =
  for overlay in overlays:
    overlay()
    builder.panel(&{FlushBorders})
  overlays.setLen(0)

import app

proc updateWidgetTree*(self: App, builder: UINodeBuilder, frameIndex: int) =
  let themes = getServiceChecked(ThemeService)
  let platform = getServiceChecked(PlatformService).platform
  let commands = getServiceChecked(CommandLineService)
  let layout = getServiceChecked(LayoutService)
  let toasts = getServiceChecked(ToastService)

  builder.theme = themes.theme

  var headerColor = if commands.commandLineMode: builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

  let statusLine = getServiceChecked(StatusLineService)

  resetBorderFlags()

  var rootFlags = &{FillX, FillY, OverlappingChildren, MaskContent}
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
          let foreground = foreground.mapIt(builder.theme.color(it, textColor))
          let background = background.mapIt(builder.theme.color(it, headerColor))
          section(text, foreground.get(textColor), background.get(headerColor), extraFlags)

        builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}, pivot = vec2(1, 0)):

          for s in self.uiSettings.statusLine.get():
            case s.kind
            of JString:
              case s.getStr
              of "mode":
                let modes = if layout.getActiveEditor().getSome(editor):
                  let modes = editor.config.get("text.modes", seq[string])
                  "[" & modes.join(", ") & "]"
                else:
                  ""
                section(modes)

              of "vcs.status":
                let vcss: VCSService = getServiceChecked(VCSService)
                for vcs in vcss.getAllVersionControlSystems():
                  section(&"[{vcs.name}: {vcs.status}]")
                  break

              of "global-mode":
                let modeText = if self.currentMode.len == 0: "[No Mode]" else: self.currentMode
                section(modeText)

              of "session":
                let sessionText = if self.sessionFile.len == 0: "[No Session]" else: fmt"[{self.sessionFile}]"
                section(sessionText)

              else:
                if statusLine.getRenderer(s.getStr).getSome(renderer):
                  if i > 0:
                    builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = " | ")
                  overlays.add renderer(builder)
                  inc i

            else:
              discard

        builder.panel(&{}, w = builder.charWidth)
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = self.inputHistory, textColor = textColor, pivot = vec2(1, 0))

        builder.panel(&{FillX, SizeToContentY}, pivot = vec2(1, 0)):
          if commands.commandLineEditor != nil:
            let wasActive = commands.commandLineEditor.active
            commands.commandLineEditor.active = commands.commandLineMode
            if commands.commandLineEditor.active != wasActive:
              commands.commandLineEditor.markDirty(notify=false)

            builder.pushMaxBounds(rootBounds.wh * vec2(0.75, 0.5))
            defer:
              builder.popMaxBounds()
            commandLineOverlays.add commands.commandLineEditor.render(builder)
          else:
            log lvlWarn, &"No command line editor"

      builder.panel(&{FlushBorders})

      builder.panel(&{FillX, FillY, FlushBorders, MaskContent}, pivot = vec2(0, 1), tag = "main"): # main panel
        mainBounds = currentNode.bounds
        overlays.add layout.render(builder)

    builder.panel(&{FlushBorders})
    builder.flushOverlays(overlays)

    # popups
    for i, popup in layout.popups:
      overlays.add popup.createUI(builder)
      builder.panel(&{FlushBorders})
      builder.flushOverlays(overlays)

    let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
    let textColor = builder.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
    var padding = (builder.charWidth * 0.75).floor
    if platform.backend == scripting_api.Terminal:
      padding = 0

    if self.showNextPossibleInputs:
      let inputLines = self.uiSettings.whichKeyHeight.get()
      let continuesTextColor = builder.theme.tokenColor("keyword", color(225/255, 200/255, 200/255))
      let keysTextColor = builder.theme.tokenColor("number", color(225/255, 200/255, 200/255))
      builder.panel(&{FillX, SizeToContentY}, y = mainBounds.h):
        let numLines = min(self.nextPossibleInputs.len, inputLines)
        builder.renderCommandKeys(self.nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, numLines, mainBounds, padding = 1)
      builder.updateSizeToContent(builder.currentChild)
      builder.currentChild.rawY = mainBounds.h - builder.currentChild.bounds.h

    let toastStyle = self.uiSettings.toast.style.get()
    let toastMaxTime = self.uiSettings.toast.duration.get().float64 * 0.001
    let animateToasts = self.uiSettings.toast.animation.get()
    let maxToasts = self.uiSettings.toast.max.get()
    case toastStyle
    of Box:
      let toastWidth = floor(currentNode.w * 0.3)
      builder.panel(&{LayoutVerticalReverse}, x = floor(currentNode.w * 0.7), y = mainBounds.y, w = toastWidth, h = mainBounds.h, border = border(builder.defaultBorderWidth), tag = "toasts"):
        let maxLen = 200
        for i in 0..<min(toasts.toasts.len, maxToasts):
          let toast {.cursor.} = toasts.toasts[toasts.toasts.high - i]
          let color = builder.theme.tokenColor(toast.color, textColor)

          var xOffset = 0.0
          if animateToasts:
            let fadeOutTime = 0.175 / max(toastMaxTime, 1)
            let t = clamp((toast.progress - (1 - fadeOutTime)) / fadeOutTime, 0, 1)
            xOffset = toastWidth * t * t
            if xOffset > 0:
              platform.requestRender(true)

          if i > 0:
            builder.panel(&{FillX}, h = builder.defaultBorderWidth, pivot = vec2(0, 1))
            builder.updateSizeToContent(builder.currentChild)

          builder.panel(&{FillX, SizeToContentY, LayoutVertical, FillBackground, DrawBorder, DrawBorderTerminal}, border = border(1), pivot = vec2(0, 1), backgroundColor = headerColor, borderColor = borderColor, tag = "toast"):
            currentNode.rawX = currentNode.boundsRaw.x + xOffset
            builder.panel(&{FillX, SizeToContentY, LayoutVertical}, border = border(padding)):
              if padding > 0: builder.panel(&{FillX}, h = padding)
              let contentWidth = currentNode.w - currentNode.border.left - currentNode.border.right
              builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.title, textColor = color)
              if padding > 0: builder.panel(&{FillX}, h = padding)
              let max = min(toast.message.len, maxLen)
              if max < toast.message.len:
                builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.message[0..<max], textColor = textColor)
              else:
                builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.message, textColor = textColor)
              if padding > 0: builder.panel(&{FillX}, h = padding)
              builder.panel(&{DrawBorder, DrawBorderTerminal}, border = border(0, 0, builder.defaultBorderWidth, 0), w = (contentWidth - 2) * (1 - toast.progress), h = builder.defaultBorderWidth, borderColor = color, backgroundColor = headerColor, tag = "progress bar")

              if padding > 0: builder.panel(&{FillX}, h = padding)

    of Minimal:
      let toastWidth = max(floor(currentNode.w - builder.charWidth * 10), 1)
      builder.panel(&{LayoutVerticalReverse}, x = builder.charWidth * 5, y = mainBounds.y - builder.textHeight * 2, w = toastWidth, h = mainBounds.h, tag = "toasts"):
        for i in 0..<min(toasts.toasts.len, maxToasts):
          let toast {.cursor.} = toasts.toasts[toasts.toasts.high - i]
          let color = builder.theme.tokenColor(toast.color, textColor)

          let a = (maxToasts.float - i.float) / maxToasts.float

          if i > 0:
            builder.panel(&{FillX}, h = floor(builder.textHeight * 0.5), pivot = vec2(0, 1))

          builder.panel(&{SizeToContentX, SizeToContentY, MaskContent, BlendAlpha}, backgroundColor = color(1, 1, 1, a), pivot = vec2(0, 1), tag = "toast"):
            builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal, FillBackground}, backgroundColor = headerColor):
              builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = toast.title, textColor = color)
              builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = " - ", textColor = textColor)
              let maxLen = ((toastWidth - builder.currentChild.bounds.xw) / builder.charWidth).int
              var nlIndex = toast.message.find("\n")
              if nlIndex == -1:
                nlIndex = toast.message.len
              let max = min(nlIndex, maxLen)
              if max < toast.message.len:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = toast.message[0..<max], textColor = color)
              else:
                builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = toast.message, textColor = color)
      if toasts.toasts.len > 0:
        platform.requestRender(true)

    builder.panel(&{FlushBorders})

    builder.flushOverlays(overlays)
    builder.flushOverlays(commandLineOverlays)
