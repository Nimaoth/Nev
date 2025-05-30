import std/[strformat, options, tables]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform/[platform, tui]
import ui/[widget_builders_base, widget_library]
import app, theme, view
import text/text_editor
import config_provider, terminal_service

from std/colors as colors import nil

import ui/node

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

logCategory "widget_builder_terminal"

var uiUserId = newId()

method createUI*(self: TerminalView, builder: UINodeBuilder, app: App): seq[OverlayFunction] =
  let dirty = self.dirty
  self.dirty = false

  let uiSettings = UISettings.new(app.config.runtime)
  let inactiveBrightnessChange = uiSettings.background.inactiveBrightnessChange.get()
  var backgroundColor = if self.active:
    app.theme.color("editor.background", color(25/255, 25/255, 40/255))
  else:
    app.theme.color("editor.background", color(25/255, 25/255, 25/255)).lighten(inactiveBrightnessChange)

  let transparentBackground = app.config.runtime.get("ui.background.transparent", false)
  let textColor = app.theme.color("editor.foreground", color(225/255, 200/255, 200/255))
  let cursorColor = textColor
  var activeBackgroundColor = app.theme.color("editor.background", color(25/255, 25/255, 40/255))
  activeBackgroundColor.a = 1
  # let selectedBackgroundColor = app.theme.color("editorSuggestWidget.selectedBackground", color(0.6, 0.5, 0.2)).withAlpha(1)
  let selectedBackgroundColor = color(0.6, 0.4, 0.2) # todo

  if transparentBackground:
    backgroundColor.a = 0
    activeBackgroundColor.a = 0
  else:
    backgroundColor.a = 1
    activeBackgroundColor.a = 1

  let headerColor = app.theme.color("tab.inactiveBackground", color(45/255, 45/255, 45/255)).withAlpha(1)
  let activeHeaderColor = app.theme.color("tab.activeBackground", color(45/255, 45/255, 60/255)).withAlpha(1)

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

  var res: seq[OverlayFunction] = @[]

  builder.panel(&{UINodeFlag.MaskContent, OverlappingChildren} + sizeFlags, userId = uiUserId.newPrimaryId):
    # onClickAny btn:
    #   self.app.tryActivateEditor(self)

    if true or dirty or app.platform.redrawEverything or not builder.retain():
      builder.panel(&{LayoutVertical} + sizeFlags):
        # Header
        builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal},
            backgroundColor = headerColor):

          var text = &"Terminal - " & self.mode

          builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = textColor, text = text)

        # Body
        builder.panel(sizeFlags + &{FillBackground, MouseHover}, backgroundColor = backgroundColor):
          onScroll:
            self.handleScroll(delta.y.int, modifiers)
          currentNode.handlePressed = proc(node: UINode, btn: input.MouseButton, modifiers: set[Modifier], pos: Vec2): bool =
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

              for row in 0..<height:
                var line = ""
                for col in 0..<width:
                  let cell {.cursor.} = self.terminal.terminalBuffer[col, row]
                  if cell.ch != 0.Rune:
                    line.add $cell.ch
                  else:
                    line.add " "

                  let cellBounds = rect(
                    col.float * builder.charWidth, row.float * builder.textHeight, builder.charWidth, builder.textHeight)

                  var bgColor = color(0, 0, 0)

                  case cell.bg
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

                  if cell.bg != bgNone:
                    fillRect(cellBounds, bgColor)

                  var fgColor = textColor

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

                  if cell.ch != 0.Rune:
                    drawText($cell.ch, cellBounds, fgColor, &{TextDrawSpaces})

                # if line.len > 0:
                  # echo line
                  # drawText(line, rect(0, row.float * builder.textHeight, 1000, builder.textHeight), textColor, &{TextDrawSpaces})

              if self.mode != "normal" and self.terminal.cursor.visible:
                let cursorBounds = rect(
                  self.terminal.cursor.col.float * builder.charWidth, self.terminal.cursor.row.float * builder.textHeight,
                  builder.charWidth * 0.1, builder.textHeight)
                fillRect(cursorBounds, cursorColor)

          currentNode.markDirty(builder)

  res
