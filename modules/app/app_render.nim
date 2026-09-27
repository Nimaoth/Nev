import std/[strutils]
import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils, jsonex]
import ui/node
import platform
import ui/[widget_library]
import document_editor, theme, layout/layout, config_provider, command_line, toast
import core_settings
import popup, view
import status_line
from scripting_api import nil
import vcs, service

{.push gcsafe.}
{.push raises: [].}

logCategory "widget_builder"

type BorderFlags = object
  left: bool
  right: bool
  top: bool
  bottom: bool

proc none(_: typedesc[BorderFlags]): BorderFlags = BorderFlags()

var borderFlagStack = newSeq[BorderFlags]()

proc resetBorderFlags() {.gcsafe.} =
  {.gcsafe.}:
    borderFlagStack = @[BorderFlags.none()]

proc flushOverlays(builder: UINodeBuilder, overlays: var seq[OverlayFunction]) =
  for overlay in overlays:
    overlay()
    builder.panel(&{FlushBorders})
  overlays.setLen(0)

import app
from nuigi import UiBuilder, UiColor, UiBackendType, rgba, fillX, fillY, fitY, fit, height,
  backgroundColor, borderColor, borderWidth, padding, gap, text, textColor,
  wrapText, node, layoutVertical, layoutHorizontal, layoutVerticalReverse,
  layoutHorizontalReverse, fillBackground, styleIndex, textStyleIndex,
  anchors, anchorsX, offsets, pivotY, finishAnchors, noHover, size,
  pushId, popId, themeStyle, maskChildren, UiStyleIndex, UiTextStyleIndex
from nuigi/widgets import TableColumn, tableLayout, tableColumnFit,
  tableColumnFill

proc toUiColorNui(c: chroma.Color): UiColor =
  rgba(c.r.float32, c.g.float32, c.b.float32, c.a.float32)

proc renderNextPossibleInputsNui(
    self: App, nui: var UiBuilder, statusBarHeight: float32) {.raises: [Exception].} =
  {.cast(gcsafe).}:
    if not self.showNextPossibleInputs or self.nextPossibleInputs.len == 0:
      return

    let inputLines = min(
      self.nextPossibleInputs.len,
      max(0, self.config.runtime.getUiWhichKeyHeight()))
    if inputLines == 0:
      return

    let themes = getServiceChecked(ThemeService)
    let defaultColor = themes.theme.color(
      "editor.foreground", color(225 / 255, 200 / 255, 200 / 255))
    let defaultUiColor = toUiColorNui(defaultColor)
    let keyColor = toUiColorNui(
      themes.theme.tokenColor("number", defaultColor))
    let continuesColor = toUiColorNui(
      themes.theme.tokenColor("keyword", defaultColor))
    let columnCount =
      (self.nextPossibleInputs.len + inputLines - 1) div inputLines

    var columns = newSeqOfCap[TableColumn](columnCount * 2)
    for column in 0 ..< columnCount:
      columns.add tableColumnFit()
      columns.add tableColumnFill()

    nui.tableLayout(columns, 8, 0):
      discard nui.anchors(0, 1, 1, 1)
        .offsets(8, -(statusBarHeight) - 8, -8, -(statusBarHeight) - 8)
        .pivotY(1).finishAnchors()
        .fitY().styleIndex(UiStyleIndexHeader).fillBackground()
        .padding(6).maskChildren().noHover()

      for row in 0 ..< inputLines:
        for column in 0 ..< columnCount:
          let index = column * inputLines + row
          if index < self.nextPossibleInputs.len:
            let item = self.nextPossibleInputs[index]
            nui.pushId(index.uint64)
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText))
                .textColor(keyColor).text(item.input)
            nui.node:
              discard nui.fit().maskChildren()
                .textStyleIndex(int(UiStyleIndexDefaultText))
                .textColor(if item.continues: continuesColor else: defaultUiColor)
                .text(item.description)
            nui.popId()
          else:
            nui.node:
              discard nui.fit()
            nui.node:
              discard nui.fillX().fitY()

proc renderToastsNui(self: App, nui: var UiBuilder) {.raises: [Exception].} =
  {.cast(gcsafe).}:
    let toastService = getServiceChecked(ToastService)
    let toastCount = min(
      toastService.toasts.len,
      max(0, self.config.runtime.getUiToastMax()))
    if toastCount == 0:
      return

    let themes = getServiceChecked(ThemeService)
    let defaultTextColor = themes.theme.color(
      "editor.foreground", color(225 / 255, 200 / 255, 200 / 255))
    let toastStyle = self.config.runtime.getUiToastStyle()
    let toastMaxTime = self.config.runtime.getUiToastDuration().float64 * 0.001
    let animateToasts = self.config.runtime.getUiToastAnimation()

    nui.node("nui-toast-overlay"):
      discard nui.anchors(0, 0, 1, 1).offsets(0, 0, 0, 0)
        .finishAnchors().noHover()

      case toastStyle
      of core_settings.ToastStyle.Box:
        nui.layoutVerticalReverse("nui-toast-box-stack"):
          discard nui.anchors(0.7, 0, 1, 0).offsets(8, 8, -8, 8)
            .finishAnchors().gap(6).fitY()

          for index in 0 ..< toastCount:
            let toast = toastService.toasts[toastService.toasts.high - index]
            let accentColor = toUiColorNui(
              themes.theme.tokenColor(toast.color, defaultTextColor))
            var slideOffset = 0.0'f32
            if animateToasts:
              let fadeOutTime = 0.175 / max(toastMaxTime, 1.0)
              let fadeProgress = clamp(
                (toast.progress - (1.0 - fadeOutTime)) / fadeOutTime,
                0.0, 1.0)
              slideOffset = 96.0'f32 * (fadeProgress * fadeProgress).float32

            nui.pushId(index.uint64)
            nui.layoutHorizontalReverse:
              discard nui.fillX().fitY()
              if slideOffset > 0:
                nui.node:
                  discard nui.size(slideOffset, 1)
              nui.layoutVertical("nui-toast-box"):
                discard nui.fillX().fitY().styleIndex(UiStyleIndexTooltip)
                  .fillBackground().borderWidth(1)
                  .borderColor(accentColor).padding(8).gap(4)
                nui.node:
                  discard nui.fillX().fitY()
                    .textStyleIndex(int(UiStyleIndexHeaderText))
                    .textColor(accentColor).text(toast.title)
                nui.node:
                  let message = if toast.message.len > 200:
                    toast.message[0 ..< 200]
                  else:
                    toast.message
                  discard nui.fillX().fitY().wrapText()
                    .textStyleIndex(int(UiStyleIndexDefaultText))
                    .text(message)
                nui.node:
                  discard nui.fillX().height(2)
                    .backgroundColor(nui.themeStyle(UiStyleIndexPanel)[].borderColor)
                    .fillBackground()
                  nui.node:
                    discard nui.anchorsX(0, max(
                      0.0, 1.0 - toast.progress).float32)
                      .offsets(0, 0, 0, 0).finishAnchors().height(2)
                      .backgroundColor(accentColor).fillBackground()
            nui.popId()

      of core_settings.ToastStyle.Minimal:
        nui.layoutVerticalReverse("nui-toast-minimal-stack"):
          discard nui.anchors(0, 1, 1, 1).offsets(40, -20, -40, -20)
            .pivotY(1).finishAnchors().gap(6).fitY()

          for index in 0 ..< toastCount:
            let toast = toastService.toasts[toastService.toasts.high - index]
            var accentColor = toUiColorNui(
              themes.theme.tokenColor(toast.color, defaultTextColor))
            accentColor.a *= (toastCount - index).float32 / toastCount.float32
            let newlineIndex = toast.message.find('\n')
            let messageEnd = min(
              if newlineIndex >= 0: newlineIndex else: toast.message.len,
              min(toast.message.len, 200))
            let message = toast.message[0 ..< messageEnd]

            nui.pushId(index.uint64)
            nui.layoutHorizontal("nui-toast-minimal"):
              discard nui.fit().styleIndex(UiStyleIndexTooltip)
                .fillBackground().padding(4).gap(4)
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexHeaderText))
                  .textColor(accentColor).text(toast.title)
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexMutedText))
                  .text("-")
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText))
                  .text(message)
            nui.popId()

{.pop raises.}
{.pop gcsafe.}

proc updateWidgetTreeNui*(self: App, nui: var UiBuilder, frameIndex: int) {.raises: [Exception].} =
  ## New version using nuigi builder – builds a status line and stubs the rest of the UI.
  {.cast(gcsafe).}:
    let commands = getServiceChecked(CommandLineService)
    let layout = getServiceChecked(LayoutService)
    let runtimeConfig = self.config.runtime

    let statusLine = getServiceChecked(StatusLineService)
    var statusBarHeight = 0.0'f32

    # Stub: create a top-level nuigi container for the new UI.
    # This is built between plat.beginNuiFrame() and plat.endNuiFrame() (desktop_main).
    nui.layoutVerticalReverse("nui-app-root"):
      discard nui.fillX().fillY()
      # Status bar – built with nuigi, mimics old builder's status line
      # layoutHorizontalReverse already creates its own node, so we use it directly as the status bar container
      nui.layoutHorizontalReverse("nui-status-line"):
        discard nui.fillX().fitY().fillBackground().styleIndex(UiStyleIndexHeader).padding(4).gap(8)
        # Left side: status sections from config
        nui.layoutHorizontal("nui-status-left"):
          discard nui.fit().gap(8)
          for s in runtimeConfig.getUiStatusLine():
            case s.kind
            of JString:
              case s.getStr
              of "mode":
                let modes = if layout.getActiveEditor().getSome(editor):
                  let m = editor.config.get("text.modes", seq[string])
                  "[" & m.join(", ") & "]"
                else:
                  ""
                if modes.len > 0:
                  nui.node:
                    discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(modes)
              of "vcs.status":
                let vcss: VCSService = getServiceChecked(VCSService)
                for vcs in vcss.versionControlSystems:
                  nui.node:
                    discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text("[" & vcs.name & ": " & vcs.status & "]")
                  break
              of "global-mode":
                let modeText = if self.currentMode.len == 0: "[No Mode]" else: self.currentMode
                nui.node:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(modeText)
              of "session":
                let sessionText = if self.sessionFile.len == 0: "[No Session]" else: "[" & self.sessionFile & "]"
                nui.node:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(sessionText)
              else:
                if statusLine.getRendererNui(s.getStr).getSome(rendererNui):
                  rendererNui(nui)
                else:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text("[unknown renderer " & s.getStr & "]")
            else:
              discard

        # Center / right: input history and command line editor
        nui.layoutHorizontal("nui-status-right"):
          discard nui.fitY().fillX().gap(8)
          if self.inputHistory.len > 0:
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(self.inputHistory)
          if commands.commandLineEditor != nil:
            let wasActive = commands.commandLineEditor.active
            commands.commandLineEditor.active = commands.commandLineMode
            if commands.commandLineEditor.active != wasActive:
              commands.commandLineEditor.markDirty(notify=false)
            if commands.commandLineMode:
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(":")
              # Embedded editor: its NUI root (text-root) uses fillX/fillY, so
              # constrain it in an explicit-height masked container like
              # selector-popup-search / git-ui-commit-editor.
              nui.node("nui-commandline"):
                let cmdH = if nui.backendType == UiBackendType.Terminal: 1.0'f32 else: 24.0'f32
                discard nui.fillX().height(cmdH).maskChildren()
                commands.commandLineEditor.renderNui(nui)
      statusBarHeight = nui.lastNode.size.y
      let h = nui.currentNode.size.y - statusBarHeight
      # Main area – renders layout via NUI
      # layoutVertical already creates a node, so we use it directly for the container (no extra nui.node wrapper)
      nui.layoutVertical("nui-main-stub"):
        discard nui.fillX().height(h).fillBackground().styleIndex(UiStyleIndexPanel).padding(4).gap(4)
        layout.renderNui(nui)

    for popup in layout.popups:
      if popup != nil:
        popup.render(nui)

    self.renderNextPossibleInputsNui(nui, statusBarHeight)
    self.renderToastsNui(nui)

{.push gcsafe.}
{.push raises: [].}

proc updateWidgetTree*(self: App, builder: UINodeBuilder, frameIndex: int) =
  # New builder path – build status line with nuigi and stub rest.
  # This is called while the nuigi frame is already begun (desktop_main surrounds render).
  let themes = getServiceChecked(ThemeService)
  let platform = getServiceChecked(PlatformService).platform
  let commands = getServiceChecked(CommandLineService)
  let layout = getServiceChecked(LayoutService)
  let toasts = getServiceChecked(ToastService)
  let runtimeConfig = self.config.runtime

  builder.theme = themes.theme

  var headerColor = if commands.commandLineMode: builder.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)) else: builder.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255))
  headerColor.a = 1
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))

  let statusLine = getServiceChecked(StatusLineService)

  # resetBorderFlags()

  # var rootFlags = &{FillX, FillY, OverlappingChildren, MaskContent}
  # builder.panel(rootFlags): # fullscreen overlay

  #   let rootBounds = currentNode.bounds
  #   self.preRender(currentNode.bounds)

  #   var overlays: seq[OverlayFunction]
  #   var commandLineOverlays: seq[OverlayFunction]
  #   var mainBounds: Rect

  #   builder.panel(&{FillX, FillY, LayoutVerticalReverse, DrawChildrenReverse}): # main panel

  #     # todo: handle self.statusBarOnTop
  #     builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse, FillBackground}, backgroundColor = headerColor, pivot = vec2(0, 1)): # status bar
  #       var i = 0

  #       proc section(text: string, foreground: Color, background: Color, extraFlags: UINodeFlags) =
  #         var flags = &{SizeToContentX, SizeToContentY, DrawText} + extraFlags
  #         if i > 0:
  #           builder.panel(flags, textColor = foreground, backgroundColor = background, text = " | ")
  #         builder.panel(flags, textColor = foreground, backgroundColor = background, text = text)
  #         inc i

  #       proc section(text: string, foreground: Option[string] = string.none, background: Option[string] = string.none) =
  #         var extraFlags = 0.UINodeFlags
  #         if background.isSome:
  #           extraFlags.incl FillBackground
  #         let foreground = foreground.mapIt(builder.theme.color(it, textColor))
  #         let background = background.mapIt(builder.theme.color(it, headerColor))
  #         section(text, foreground.get(textColor), background.get(headerColor), extraFlags)

  #       builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal}, pivot = vec2(1, 0)):

  #         for s in runtimeConfig.getUiStatusLine():
  #           case s.kind
  #           of JString:
  #             case s.getStr
  #             of "mode":
  #               let modes = if layout.getActiveEditor().getSome(editor):
  #                 let modes = editor.config.get("text.modes", seq[string])
  #                 "[" & modes.join(", ") & "]"
  #               else:
  #                 ""
  #               section(modes)

  #             of "vcs.status":
  #               let vcss: VCSService = getServiceChecked(VCSService)
  #               for vcs in vcss.versionControlSystems:
  #                 section(&"[{vcs.name}: {vcs.status}]")
  #                 break

  #             of "global-mode":
  #               let modeText = if self.currentMode.len == 0: "[No Mode]" else: self.currentMode
  #               section(modeText)

  #             of "session":
  #               let sessionText = if self.sessionFile.len == 0: "[No Session]" else: fmt"[{self.sessionFile}]"
  #               section(sessionText)

  #             else:
  #               if statusLine.getRenderer(s.getStr).getSome(renderer):
  #                 if i > 0:
  #                   builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = " | ")
  #                 overlays.add renderer(builder)
  #                 inc i

  #           else:
  #             discard

  #       builder.panel(&{}, w = builder.charWidth)
  #       builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = self.inputHistory, textColor = textColor, pivot = vec2(1, 0))

  #       builder.panel(&{FillX, SizeToContentY}, pivot = vec2(1, 0)):
  #         if commands.commandLineEditor != nil:
  #           let wasActive = commands.commandLineEditor.active
  #           commands.commandLineEditor.active = commands.commandLineMode
  #           if commands.commandLineEditor.active != wasActive:
  #             commands.commandLineEditor.markDirty(notify=false)

  #           builder.pushMaxBounds(rootBounds.wh * vec2(0.75, 0.5))
  #           defer:
  #             builder.popMaxBounds()
  #           commandLineOverlays.add commands.commandLineEditor.render(builder)
  #         else:
  #           log lvlWarn, &"No command line editor"

  #     builder.panel(&{FlushBorders})

  #     builder.panel(&{FillX, FillY, FlushBorders, MaskContent}, pivot = vec2(0, 1), tag = "main"): # main panel
  #       mainBounds = currentNode.bounds
  #       overlays.add layout.render(builder)

  #   builder.panel(&{FlushBorders})
  #   builder.flushOverlays(overlays)

  #   # popups
  #   for i, popup in layout.popups:
  #     overlays.add popup.render(builder)
  #     builder.panel(&{FlushBorders})
  #     builder.flushOverlays(overlays)

  #   let borderColor = builder.theme.color("panel.border", color(0, 0, 0))
  #   let textColor = builder.theme.color("editor.foreground", color(0.882, 0.784, 0.784))
  #   var padding = (builder.charWidth * 0.75).floor
  #   if platform.backend == scripting_api.Terminal:
  #     padding = 0

  #   if self.showNextPossibleInputs:
  #     let inputLines = runtimeConfig.getUiWhichKeyHeight()
  #     let continuesTextColor = builder.theme.tokenColor("keyword", color(225/255, 200/255, 200/255))
  #     let keysTextColor = builder.theme.tokenColor("number", color(225/255, 200/255, 200/255))
  #     builder.panel(&{FillX, SizeToContentY}, y = mainBounds.h):
  #       let numLines = min(self.nextPossibleInputs.len, inputLines)
  #       builder.renderCommandKeys(self.nextPossibleInputs, textColor, continuesTextColor, keysTextColor, headerColor, numLines, mainBounds, padding = 1)
  #     builder.updateSizeToContent(builder.currentChild)
  #     builder.currentChild.rawY = mainBounds.h - builder.currentChild.bounds.h

  #   let toastStyle = runtimeConfig.getUiToastStyle()
  #   let toastMaxTime = runtimeConfig.getUiToastDuration().float64 * 0.001
  #   let animateToasts = runtimeConfig.getUiToastAnimation()
  #   let maxToasts = runtimeConfig.getUiToastMax()
  #   case toastStyle
  #   of core_settings.ToastStyle.Box:
  #     let toastWidth = floor(currentNode.w * 0.3)
  #     builder.panel(&{LayoutVerticalReverse}, x = floor(currentNode.w * 0.7), y = mainBounds.y, w = toastWidth, h = mainBounds.h, border = border(builder.defaultBorderWidth), tag = "toasts"):
  #       let maxLen = 200
  #       for i in 0..<min(toasts.toasts.len, maxToasts):
  #         let toast {.cursor.} = toasts.toasts[toasts.toasts.high - i]
  #         let color = builder.theme.tokenColor(toast.color, textColor)

  #         var xOffset = 0.0
  #         if animateToasts:
  #           let fadeOutTime = 0.175 / max(toastMaxTime, 1)
  #           let t = clamp((toast.progress - (1 - fadeOutTime)) / fadeOutTime, 0, 1)
  #           xOffset = toastWidth * t * t
  #           if xOffset > 0:
  #             platform.requestRender(true)

  #         if i > 0:
  #           builder.panel(&{FillX}, h = builder.defaultBorderWidth, pivot = vec2(0, 1))
  #           builder.updateSizeToContent(builder.currentChild)

  #         builder.panel(&{FillX, SizeToContentY, LayoutVertical, FillBackground, DrawBorder, DrawBorderTerminal}, border = border(1), pivot = vec2(0, 1), backgroundColor = headerColor, borderColor = borderColor, tag = "toast"):
  #           currentNode.rawX = currentNode.boundsRaw.x + xOffset
  #           builder.panel(&{FillX, SizeToContentY, LayoutVertical}, border = border(padding)):
  #             if padding > 0: builder.panel(&{FillX}, h = padding)
  #             let contentWidth = currentNode.w - currentNode.border.left - currentNode.border.right
  #             builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.title, textColor = color)
  #             if padding > 0: builder.panel(&{FillX}, h = padding)
  #             let max = min(toast.message.len, maxLen)
  #             if max < toast.message.len:
  #               builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.message[0..<max], textColor = textColor)
  #             else:
  #               builder.panel(&{SizeToContentY, DrawText, TextWrap}, w = contentWidth, text = toast.message, textColor = textColor)
  #             if padding > 0: builder.panel(&{FillX}, h = padding)
  #             builder.panel(&{DrawBorder, DrawBorderTerminal}, border = border(0, 0, builder.defaultBorderWidth, 0), w = (contentWidth - 2) * (1 - toast.progress), h = builder.defaultBorderWidth, borderColor = color, backgroundColor = headerColor, tag = "progress bar")

  #             if padding > 0: builder.panel(&{FillX}, h = padding)

  #   of core_settings.ToastStyle.Minimal:
  #     let toastWidth = max(floor(currentNode.w - builder.charWidth * 10), 1)
  #     builder.panel(&{LayoutVerticalReverse}, x = builder.charWidth * 5, y = mainBounds.y - builder.textHeight * 2, w = toastWidth, h = mainBounds.h, tag = "toasts"):
  #       for i in 0..<min(toasts.toasts.len, maxToasts):
  #         let toast {.cursor.} = toasts.toasts[toasts.toasts.high - i]
  #         let color = builder.theme.tokenColor(toast.color, textColor)

  #         let a = (maxToasts.float - i.float) / maxToasts.float

  #         if i > 0:
  #           builder.panel(&{FillX}, h = floor(builder.textHeight * 0.5), pivot = vec2(0, 1))

  #         builder.panel(&{SizeToContentX, SizeToContentY, MaskContent, BlendAlpha}, backgroundColor = color(1, 1, 1, a), pivot = vec2(0, 1), tag = "toast"):
  #           builder.panel(&{SizeToContentX, SizeToContentY, LayoutHorizontal, FillBackground}, backgroundColor = headerColor):
  #             builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = toast.title, textColor = color)
  #             builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = " - ", textColor = textColor)
  #             let maxLen = ((toastWidth - builder.currentChild.bounds.xw) / builder.charWidth).int
  #             var nlIndex = toast.message.find("\n")
  #             if nlIndex == -1:
  #               nlIndex = toast.message.len
  #             let max = min(nlIndex, maxLen)
  #             if max < toast.message.len:
  #               builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = toast.message[0..<max], textColor = color)
  #             else:
  #               builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, text = toast.message, textColor = color)
  #     if toasts.toasts.len > 0:
  #       platform.requestRender(true)

  #   builder.panel(&{FlushBorders})

  #   builder.flushOverlays(overlays)
  #   builder.flushOverlays(commandLineOverlays)

  {.cast(gcsafe).}:
    try:
      var plat = getServiceChecked(PlatformService).platform
      self.updateWidgetTreeNui(plat.nui, frameIndex)
    except:
      discard
