import std/[os, strutils, strformat, terminal]
import renderer, widgets
import ../tui, ../custom_logger, ../rect_utils
import vmath

export renderer, widgets

type
  TerminalRenderer* = ref object of Renderer
    buffer: TerminalBuffer
    redrawEverything*: bool
    trueColorSupport*: bool

proc exitProc() {.noconv.} =
  disableTrueColors()

  illwillDeinit()
  showCursor()
  quit(0)

proc init*(self: TerminalRenderer) =
  illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitProc)
  hideCursor()

  if isTrueColorSupported():
    logger.log(lvlInfo, "Enable true color support")
    self.trueColorSupport = true
    enableTrueColors()

  self.buffer = newTerminalBuffer(terminalWidth(), terminalHeight())
  self.redrawEverything = true

proc deinit*(self: TerminalRenderer) =
  illwillDeinit()
  showCursor()

proc size*(self: TerminalRenderer): Vec2 = vec2(self.buffer.width.float, self.buffer.height.float)

method sizeChanged*(self: TerminalRenderer): bool =
  let (w, h) = (terminalWidth(), terminalHeight())
  return self.buffer.width != w or self.buffer.height != h

method renderWidget(self: WWidget, renderer: TerminalRenderer, forceRedraw: bool) {.base.} = discard

method render*(self: TerminalRenderer, widget: WWidget) =
  if self.sizeChanged:
    let (w, h) = (terminalWidth(), terminalHeight())
    logger.log(lvlInfo, fmt"Terminal size changed from {self.buffer.width}x{self.buffer.height} to {w}x{h}, recreate buffer")
    self.buffer = newTerminalBuffer(w, h)
    self.redrawEverything = true

  if self.redrawEverything:
    self.buffer.clear()
    widget.renderWidget(self, true)
  else:
    debugf"lol"
    widget.renderWidget(self, false)

  # This can fail if the terminal was resized during rendering, but in that case we'll just rerender next frame
  try:
    self.buffer.display()
    self.redrawEverything = false
  except CatchableError:
    logger.log(lvlError, fmt"[term-render] Failed to display buffer: {getCurrentExceptionMsg()}")
    self.redrawEverything = true

method renderWidget(self: WPanel, renderer: TerminalRenderer, forceRedraw: bool) =
  renderer.buffer.setForegroundColor(self.foregroundColor)
  renderer.buffer.setBackgroundColor(self.backgroundColor)
  if self.drawBorder:
    renderer.buffer.drawRect(self.lastBounds.x.int, self.lastBounds.y.int, self.lastBounds.xw.int, self.lastBounds.yh.int)
  # renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.lastBounds}")
  for c in self.children:
    c.renderWidget(renderer, forceRedraw)

method renderWidget(self: WVerticalList, renderer: TerminalRenderer, forceRedraw: bool) =
  renderer.buffer.setForegroundColor(self.foregroundColor)
  renderer.buffer.setBackgroundColor(self.backgroundColor)
  if self.drawBorder:
    renderer.buffer.drawRect(self.lastBounds.x.int, self.lastBounds.y.int, self.lastBounds.xw.int, self.lastBounds.yh.int)
  # renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.lastBounds}")
  for c in self.children:
    c.renderWidget(renderer, forceRedraw)

method renderWidget(self: WHorizontalList, renderer: TerminalRenderer, forceRedraw: bool) =
  renderer.buffer.setForegroundColor(self.foregroundColor)
  renderer.buffer.setBackgroundColor(self.backgroundColor)
  if self.drawBorder:
    # renderer.buffer.drawRect(self.lastBounds.x.int, self.lastBounds.y.int, self.lastBounds.xw.int, self.lastBounds.yh.int - 1)
    renderer.buffer.drawHorizLine(self.lastBounds.x.int, self.lastBounds.xw.int, self.lastBounds.y.int)
  # renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.lastBounds}")
  for c in self.children:
    c.renderWidget(renderer, forceRedraw)

method renderWidget(self: WText, renderer: TerminalRenderer, forceRedraw: bool) =
  renderer.buffer.setForegroundColor(self.foregroundColor)
  renderer.buffer.setBackgroundColor(self.backgroundColor)
  renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.text}")