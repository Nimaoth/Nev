import std/[strutils]
import vmath, bumpy, chroma
import misc/[custom_logger, rect_utils, jsonex, util]
import platform
import document_editor, theme, layout/layout, config_provider, command_line, toast
import core_settings
import popup, view
import status_line
from scripting_api import nil
import vcs, service

{.push gcsafe.}
{.push raises: [].}

logCategory "widget_builder"

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

    # NUI-GAP: old which-key panel is FillX/SizeToContentY at mainBounds.h with
    # headerColor bg + charWidth padding and updateSizeToContent/rawY placement;
    # new anchors above the status bar with fixed Header style + padding 6 (see §24).
    nui.tableLayout(columns, 8, 0):
      discard nui.anchors(0, 1, 1, 1)
        .offsets(8, -(statusBarHeight) - 8, -8, -(statusBarHeight) - 8)
        .pivotY(1).finishAnchors()
        .fitY().styleIndex(UiStyleIndexHeader).fillBackground()
        .backendPadding(6).maskChildren().noHover()

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

      # NUI-GAP (toasts, see §24): old Box uses 30%-width bordered panel
      # (panel.border/headerColor, charWidth padding, i>0 separators), width-
      # proportional slide animation with requestRender; new uses Tooltip +
      # accent border, fixed padding 8/gap 4 and 96px spacer slide. Old Minimal
      # uses BlendAlpha age-faded bg + charWidth-measured truncation + half-line
      # gaps; new fades accent text only and truncates at fixed 200 chars.
      case toastStyle
      of core_settings.ToastStyle.Box:
        nui.layoutVerticalReverse("nui-toast-box-stack"):
          discard nui.anchors(0.7, 0, 1, 0).offsets(8, 8, -8, 8)
            .finishAnchors().backendGap(6).fitY()

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
                  .fillBackground().backendBorderWidth(1)
                  .borderColor(accentColor).backendPadding(8, 1).backendGap(4)
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
            .pivotY(1).finishAnchors().backendGap(6).fitY()

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
                .fillBackground().backendPadding(4, 1).backendGap(4)
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
      # NUI-GAP: old status bar switches tab.active/inactiveBackground on
      # commandLineMode, separates sections with " | " via section() helper and
      # supports fg/bg theme overloads; new uses fixed Header style + gap(8) and
      # DefaultText only (see §24).
      nui.layoutHorizontalReverse("nui-status-line"):
        discard nui.fillX().fitY().fillBackground().styleIndex(UiStyleIndexHeader).backendPadding(4).backendGap(8)
        # Left side: status sections from config
        nui.layoutHorizontal("nui-status-left"):
          discard nui.fit().backendGap(8)
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
          discard nui.fitY().fillX().backendGap(8)
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
              # Embedded editor: sizes to its content via the text editor fitY
              # mode (single line); no fixed height pin.
              # NUI-GAP: old command line uses pushMaxBounds(0.75/0.5) + a separate
              # commandLineOverlays layer flushed last (and warns on nil); new is
              # embedded in nui-status-right and silently skips nil (see §24).
              nui.node("nui-commandline"):
                discard nui.fillX().fitY().maskChildren()
                commands.commandLineEditor.renderNui(nui)
      statusBarHeight = nui.lastNode.size.y
      let h = nui.currentNode.size.y - statusBarHeight
      # Main area – renders layout via NUI
      # layoutVertical already creates a node, so we use it directly for the container (no extra nui.node wrapper)
      nui.layoutVertical("nui-main"):
        discard nui.fillX().height(h).fillBackground().styleIndex(UiStyleIndexPanel).backendPadding(0).backendGap(0)
        layout.renderNui(nui)

    # NUI-GAP: old popups render via OverlayFunction seq with FlushBorders panels
    # flushed per popup; new renders popup.render(nui) directly with no
    # FlushBorders/overlay layering (see §24).
    for popup in layout.popups:
      if popup != nil:
        popup.render(nui)

    self.renderNextPossibleInputsNui(nui, statusBarHeight)
    self.renderToastsNui(nui)

{.push gcsafe.}
{.push raises: [].}

proc updateWidgetTree*(self: App, frameIndex: int) =
  {.cast(gcsafe).}:
    try:
      var plat = getServiceChecked(PlatformService).platform
      self.updateWidgetTreeNui(plat.nui, frameIndex)
    except:
      discard
