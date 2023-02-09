import std/[os, strutils, strformat]
import renderer, widgets
import ../custom_logger
import illwill

export renderer, widgets

type
  TerminalRenderer* = ref object of Renderer
    buffer: TerminalBuffer
    redrawEverything*: bool

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

proc init*(self: TerminalRenderer) =
  illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitProc)
  hideCursor()

  self.buffer = newTerminalBuffer(terminalWidth(), terminalHeight())
  self.redrawEverything = true

proc deinit*(self: TerminalRenderer) =
  illwillDeinit()
  showCursor()

method renderWidget(self: WWidget, renderer: TerminalRenderer) {.base.} = discard

method render*(self: TerminalRenderer, widget: WWidget) =
  let (w, h) = (terminalWidth(), terminalHeight())
  if self.buffer.width != w or self.buffer.height != h:
    logger.log(lvlInfo, fmt"Terminal size changed from {self.buffer.width}x{self.buffer.height} to {w}x{h}, recreate buffer")
    self.buffer = newTerminalBuffer(w, h)
    self.redrawEverything = true

  # 3. Display some simple static UI that doesn't change from frame to frame.
  self.buffer.setForegroundColor(fgBlack, true)
  self.buffer.drawRect(0, 0, 40, 5)
  self.buffer.drawHorizLine(2, 38, 3, doubleStyle=true)

  self.buffer.write(2, 1, fgWhite, "Press any key to display its name")
  self.buffer.write(2, 2, "Press ", fgYellow, "ESC", fgWhite,
                " or ", fgYellow, "Q", fgWhite, " to quit")

  if self.redrawEverything:
    widget.renderWidget(self)

  self.buffer.display()

  self.redrawEverything = false

method renderWidget(self: WPanel, renderer: TerminalRenderer) =
  for c in self.children:
    c.renderWidget(renderer)

method renderWidget(self: WHorizontalList, renderer: TerminalRenderer) =
  for c in self.children:
    c.renderWidget(renderer)

method renderWidget(self: WText, renderer: TerminalRenderer) =
  # debugf "renderWidget {self.text}"
  renderer.buffer.write(0, 20, self.text)