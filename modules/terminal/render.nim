import std/[options, tables, strutils]
import vmath, bumpy, chroma
import pixie
import misc/[util, custom_logger, custom_unicode]
import platform/[tui]
import ui/[widget_builders_base]
import theme, view, dynamic_view, config_provider
import types, types_impl

from std/colors as colors import nil

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "terminal-render"

proc toRgbaFast*(c: Color): ColorRGBA {.inline.} =
  ## Convert Color to ColorRGBA
  result.r = (c.r * 255 + 0.5).uint8
  result.g = (c.g * 255 + 0.5).uint8
  result.b = (c.b * 255 + 0.5).uint8
  result.a = (c.a * 255 + 0.5).uint8

proc drawImages(self: TerminalView, builder: UINodeBuilder, renderCommands: var RenderCommands, zRange: Slice[int]) =
  buildCommands(renderCommands):
    for s in self.terminal.images:
      if s.z > zRange.b:
        break
      if s.z < zRange.a:
        continue
      var bounds = rect(0, 0, 0, 0)
      # todo: parent
      bounds.x = s.cx.float * builder.charWidth + s.offsetX.float
      bounds.y = s.cy.float * builder.textHeight + s.offsetY.float
      if s.ch > 0:
        bounds.h = s.ch.float * builder.textHeight
        if s.cw > 0:
          bounds.w = s.cw.float * builder.charWidth
        else:
          bounds.w = bounds.h * s.sw.float / s.sh.float
      else:
        if s.cw > 0:
          bounds.w = s.cw.float * builder.charWidth
        else:
          bounds.w = s.sw.float
        bounds.h = bounds.w * s.sh.float / s.sw.float

      # echo &"render image {s.textureId.int} {bounds}, cell size: {builder.charWidth}x{builder.lineHeight}"
      drawImage(bounds, s.textureId)

proc renderTerminal*(self: TerminalView, builder: UINodeBuilder, outWidth, outHeight, outCellWidth, outCellHeight: var int): seq[OverlayRenderFunc] =
  self.resetDirty()

  # debugf"renderTerminal"
  let config = self.terminals.config.runtime
  let uiSettings = UISettings.new(config)
  let inactiveBrightnessChange = -0.025 # uiSettings.background.inactiveBrightnessChange.get()
  var backgroundColor = if self.active:
    builder.theme.color("editor.background", color(25/255, 25/255, 40/255))
  else:
    builder.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)

  let transparentBackground = config.get("ui.background.transparent", false)
  let textColor = builder.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var activeBackgroundColor = builder.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1

  var cursorForegroundColor = builder.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = builder.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))

  if transparentBackground:
    backgroundColor.a = 0
    activeBackgroundColor.a = 0
  else:
    backgroundColor.a = 1
    activeBackgroundColor.a = 1

  let headerColor = if self.active:
    builder.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176)).withAlpha(1)
  else:
    builder.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176)).withAlpha(1).lighten(inactiveBrightnessChange)

  let imageScale = self.terminals.config.runtime.get("debug.image-scale", 1.0)

  var sizeFlags = builder.currentSizeFlags
  if self.mode == "normal":
    cursorForegroundColor = cursorForegroundColor.darken(0.3)
  let drawCursor = self.terminal.cursor.visible

  var res: seq[OverlayFunction] = @[]

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.id.newPrimaryId):
    builder.panel(&{LayoutVertical} + sizeFlags):
      # Header
      builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
          backgroundColor = headerColor):

        proc section(text: string, foreground: Color, background: Color, extraFlags: UINodeFlags) =
          var flags = &{SizeToContentX, SizeToContentY, DrawText} + extraFlags
          builder.panel(flags, textColor = foreground, backgroundColor = background, text = text)

        proc section(text: string, foreground: Option[string] = string.none, background: Option[string] = string.none) =
          var extraFlags = 0.UINodeFlags
          if background.isSome:
            extraFlags.incl FillBackground
          let foreground = foreground.mapIt(builder.theme.color(it, textColor))
          let background = background.mapIt(builder.theme.color(it, headerColor))
          section(text, foreground.get(textColor), background.get(headerColor), extraFlags)

        section("Terminal")

        if self.terminal != nil:
          if self.terminal.group != "":
            section(" - ")
            section(self.terminal.group,
              ["terminal.header.group.foreground", self.terminal.group].join(".").some,
              ["terminal.header.group.background", self.terminal.group].join(".").some)

        if self.mode != "":
          section(" - ")
          section(self.mode,
            ["terminal.header.mode.foreground", self.mode].join(".").some,
            ["terminal.header.mode.background", self.mode].join(".").some)

        if self.terminal != nil:
          if self.terminal.exitCode.getSome(exitCode):
            section(" - ")
            let foreground = if exitCode == 0: "terminal.header.exitCode.foreground.ok" else: "terminal.header.exitCode.foreground.fail"
            let background = if exitCode == 0: "terminal.header.exitCode.background.ok" else: "terminal.header.exitCode.background.fail"
            section($exitCode, foreground.some, background.some)

        section(" - ")

        if self.terminal != nil:
          if self.terminal.ssh.getSome(opts):
            let port = if opts.port.getSome(port): &":{port}" else: ""
            let address = opts.address.get("127.0.0.1")
            let desc = &"ssh {opts.username}@{address}{port}"
            section(desc, "terminal.header.command.foreground".some, "terminal.header.command.background".some)
          else:
            section(self.terminal.command, "terminal.header.command.foreground".some, "terminal.header.command.background".some)

      # Body
      builder.panel(sizeFlags + &{FillBackground, MouseHover}, backgroundColor = backgroundColor):
        onScroll:
          self.onScroll(self, delta.y.int, modifiers)
        currentNode.handlePressed = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
          # self.terminals.layout.tryActivateView(self) # todo
          let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
          self.onClick(self, btn, true, modifiers, cellPos.x.int, cellPos.y.int)
          return true

        currentNode.handleReleased = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
          let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
          self.onClick(self, btn, false, modifiers, cellPos.x.int, cellPos.y.int)
          return true
        currentNode.handleDrag = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2, d: Vec2): bool =
          let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
          self.onDrag(self, btn, cellPos.x.int, cellPos.y.int, modifiers)
          return true
        currentNode.handleHover = proc(node: UINode, pos: Vec2, modifiers: set[Modifier]): bool =
          let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
          self.onMove(self, cellPos.x.int, cellPos.y.int)
          return true

        let bounds = currentNode.bounds
        let cellWidth = (bounds.w / builder.charWidth).floor.int
        let cellHeight = (bounds.h / builder.textHeight).floor.int
        outWidth = cellWidth
        outHeight = cellHeight
        outCellWidth = builder.charWidth.floor.int
        outCellHeight = builder.textHeight.floor.int

        # todo: reuse those
        var backgroundRenderCommands = new(RenderCommands)
        var foregroundRenderCommands = new(RenderCommands)

        currentNode.renderCommands.clear()
        currentNode.renderCommandList = @[backgroundRenderCommands, foregroundRenderCommands]
        if self.terminal.isNotNil:
          let width = self.terminal.terminalBuffer.width
          let height = self.terminal.terminalBuffer.height

          buildCommands(backgroundRenderCommands[]):
            for s in self.terminal.sixels:
              self.terminals.sixelTextures.withValue(s.contentHash, textureId):
                let offset = vec2(s.col.float * builder.charWidth, s.row.float * builder.textHeight)
                let bounds = rect(offset.x, offset.y,
                  s.px.float * s.width.float * imageScale, s.py.float * s.height.float * imageScale)
                drawImage(bounds, textureId[])

          self.drawImages(builder, backgroundRenderCommands[], int.low ..< -1073741824)

          var buffer = ""
          for row in 0..<height:
            var lastCell: TerminalChar = self.terminal.terminalBuffer[0, row]
            buffer.setLen(0)
            var boundsAcc = rect(0, row.float * builder.textHeight, 0, builder.textHeight)

            var bg = lastCell.bg
            var bgColor = color(0, 0, 0)
            var fgColor = color(0, 0, 0)
            var runLen = 0

            var textFlags = 0.UINodeFlags

            template flush(draw: bool = true): untyped =
              if buffer.len > 0 and draw:
                if bg != bgNone:
                  buildCommands(backgroundRenderCommands[]):
                    fillRect(boundsAcc, bgColor)

                buildCommands(foregroundRenderCommands[]):
                  if styleStrikethrough in lastCell.style:
                    # todo: make this work in terminal platform
                    fillRect(rect(boundsAcc.x, boundsAcc.y + boundsAcc.h * 0.4, boundsAcc.w, boundsAcc.h * 0.1), fgColor)

                  if styleHidden notin lastCell.style and lastCell.ch.int != 0:
                    drawText(buffer, boundsAcc, fgColor, textFlags)

              textFlags = 0.UINodeFlags
              boundsAcc.x = boundsAcc.xw
              boundsAcc.w = builder.charWidth
              buffer.setLen(0)
              runLen = 0

            template `!=`(a, b: colors.Color): bool =
              not colors.`==`(a, b)

            for col in 0..<width:
              let cell {.cursor.} = self.terminal.terminalBuffer[col, row]
              defer:
                lastCell = cell

              if drawCursor and row == self.terminal.cursor.row and col == self.terminal.cursor.col:
                flush()
                let cellBounds = rect(col.float * builder.charWidth, row.float * builder.textHeight,
                  builder.charWidth, builder.textHeight)
                var cursorBounds = cellBounds
                case self.terminal.cursor.shape
                of CursorShape.Block:
                  fgColor = cursorBackgroundColor
                of CursorShape.Underline:
                  cursorBounds.y += cursorBounds.h * 0.9
                  cursorBounds.h *= 0.1
                of CursorShape.BarLeft:
                  cursorBounds.w *= 0.1

                buildCommands(foregroundRenderCommands[]):
                  fillRect(cursorBounds, cursorForegroundColor)
                  if cell.ch != 0.Rune and styleHidden notin cell.style:
                    drawText($cell.ch, cellBounds, fgColor, textFlags)

                continue

              elif drawCursor and row == self.terminal.cursor.row and col == self.terminal.cursor.col + 1:
                flush(false)
              elif cell.previousWideGlyph:
                flush()
                continue
              elif lastCell.previousWideGlyph:
                flush(false)
              elif (cell.ch.int != 0) != (lastCell.ch.int != 0):
                flush()
              elif cell.fg != lastCell.fg or cell.fgColor != lastCell.fgColor or cell.bg != lastCell.bg or cell.bgColor != lastCell.bgColor or cell.style != lastCell.style:
                flush()

              if cell.ch.int != 0:
                buffer.add $cell.ch
              else:
                buffer.add " "
              boundsAcc.w = (col + 1).float * builder.charWidth - boundsAcc.x
              inc runLen

              # Only calculate colors and style for the first cell in a run
              if runLen == 1:
                bg = cell.bg
                bgColor = color(0, 0, 0)

                case bg
                of bgNone: discard
                of bgBlack: bgColor = color(0, 0, 0)
                of bgRed: bgColor = color(1, 0, 0)
                of bgGreen: bgColor = color(0, 1, 0)
                of bgYellow: bgColor = color(1, 1, 0)
                of bgBlue: bgColor = color(0, 0, 1)
                of bgMagenta: bgColor = color(1, 0, 1)
                of bgCyan: bgColor = color(0, 1, 1)
                of bgWhite: bgColor = color(1, 1, 1)
                of bgRGB:
                  let (r, g, b) = colors.extractRGB(cell.bgColor)
                  bgColor = color(r.float / 255.0, g.float / 255.0, b.float / 255.0)

                fgColor = textColor

                case cell.fg
                of fgNone: fgColor = textColor
                of fgBlack: fgColor = color(0, 0, 0)
                of fgRed: fgColor = color(1, 0, 0)
                of fgGreen: fgColor = color(0, 1, 0)
                of fgYellow: fgColor = color(1, 1, 0)
                of fgBlue: fgColor = color(0, 0, 1)
                of fgMagenta: fgColor = color(1, 0, 1)
                of fgCyan: fgColor = color(0, 1, 1)
                of fgWhite: fgColor = color(1, 1, 1)
                of fgRGB:
                  let (r, g, b) = colors.extractRGB(cell.fgColor)
                  fgColor = color(r.float / 255.0, g.float / 255.0, b.float / 255.0)

                if styleReverse in cell.style:
                  case cell.fg
                  of fgNone:
                    bgColor = textColor
                  else:
                    bgColor = fgColor

                  bg = bgRGB
                  fgColor = cursorBackgroundColor

                if styleUnderscore in cell.style:
                  textFlags.incl TextUndercurl

                if styleItalic in cell.style:
                  textFlags.incl TextItalic

                if styleBlink in cell.style:
                  textFlags.incl TextBold

                if styleDim in cell.style:
                  fgColor = fgColor.darken(0.2)

            # Flush last part of the line
            flush()

          self.drawImages(builder, backgroundRenderCommands[], -1073741824..<0)
          self.drawImages(builder, foregroundRenderCommands[], 0..int.high)

        currentNode.markDirty(builder)

  res
