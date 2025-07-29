import std/[options, tables, strutils]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/[platform, tui]
import ui/[widget_builders_base]
import app, theme, view
import config_provider, terminal_service, terminal_previewer, layout

from std/colors as colors import nil

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_terminal"

method createUI*(self: TerminalPreviewer, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  if self.view != nil:
    result.add self.view.createUI(builder, app)

method createUI*(self: TerminalView, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  let dirty = self.dirty
  self.resetDirty()

  let uiSettings = UISettings.new(app.config.runtime)
  let inactiveBrightnessChange = uiSettings.background.inactiveBrightnessChange.get()
  var backgroundColor = if self.active:
    app.themes.theme.color("editor.background", color(25/255, 25/255, 40/255))
  else:
    app.themes.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)

  let transparentBackground = app.config.runtime.get("ui.background.transparent", false)
  let textColor = app.themes.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  var activeBackgroundColor = app.themes.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1

  var cursorForegroundColor = app.themes.theme.color(@["editorCursor.foreground", "foreground"], color(200/255, 200/255, 200/255))
  let cursorBackgroundColor = app.themes.theme.color(@["editorCursor.background", "background"], color(50/255, 50/255, 50/255))

  if transparentBackground:
    backgroundColor.a = 0
    activeBackgroundColor.a = 0
  else:
    backgroundColor.a = 1
    activeBackgroundColor.a = 1

  let headerColor = if self.active:
    app.themes.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176)).withAlpha(1)
  else:
    app.themes.theme.color("tab.inactiveBackground", color(0.176, 0.176, 0.176)).withAlpha(1).lighten(inactiveBrightnessChange)

  let sizeToContentX = SizeToContentX in builder.currentParent.flags
  let sizeToContentY = SizeToContentY in builder.currentParent.flags

  var sizeFlags = 0.UINodeFlags
  if sizeToContentX:
    sizeFlags.incl SizeToContentX
  else:
    sizeFlags.incl FillX

  if sizeToContentY:
    sizeFlags.incl SizeToContentY
  else:
    sizeFlags.incl FillY

  if self.mode == "normal":
    cursorForegroundColor = cursorForegroundColor.darken(0.3)
  let drawCursor = self.terminal.cursor.visible

  var res: seq[OverlayFunction] = @[]

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = self.id.newPrimaryId):

    if dirty or app.platform.redrawEverything or not builder.retain():
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
            let foreground = foreground.mapIt(app.themes.theme.color(it, textColor))
            let background = background.mapIt(app.themes.theme.color(it, headerColor))
            section(text, foreground.get(textColor), background.get(headerColor), extraFlags)

          section("Terminal")

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

          if self.terminal.exitCode.getSome(exitCode):
            section(" - ")
            let foreground = if exitCode == 0: "terminal.header.exitCode.foreground.ok" else: "terminal.header.exitCode.foreground.fail"
            let background = if exitCode == 0: "terminal.header.exitCode.background.ok" else: "terminal.header.exitCode.background.fail"
            section($exitCode, foreground.some, background.some)

          section(" - ")
          section(self.terminal.command, "terminal.header.command.foreground".some, "terminal.header.command.background".some)

        # Body
        builder.panel(sizeFlags + &{FillBackground, MouseHover}, backgroundColor = backgroundColor):
          onScroll:
            self.handleScroll(delta.y.int, modifiers)
          currentNode.handlePressed = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
            self.terminals.layout.tryActivateView(self)
            let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
            self.handleClick(btn, true, modifiers, cellPos.x.int, cellPos.y.int)
            return true
          currentNode.handleReleased = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
            let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
            self.handleClick(btn, false, modifiers, cellPos.x.int, cellPos.y.int)
            return true
          currentNode.handleDrag = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2, d: Vec2): bool =
            let cellPos = pos / vec2(builder.charWidth, builder.textHeight)
            self.handleDrag(btn, cellPos.x.int, cellPos.y.int, modifiers)
            return true

          let bounds = currentNode.bounds
          self.setSize((bounds.w / builder.charWidth).floor.int, (bounds.h / builder.textHeight).floor.int)

          currentNode.renderCommands.clear()
          buildCommands(currentNode.renderCommands):
            if self.terminal.isNotNil:
              let width = self.terminal.terminalBuffer.width
              let height = self.terminal.terminalBuffer.height

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
                      fillRect(boundsAcc, bgColor)

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

          currentNode.markDirty(builder)

  res
