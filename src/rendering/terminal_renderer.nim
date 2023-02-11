import std/[os, strutils, strformat, terminal]
import renderer, widgets
import ../tui, ../custom_logger, ../rect_utils, ../input, ../event
import vmath, windy

export renderer, widgets

type
  TerminalRenderer* = ref object of Renderer
    buffer: TerminalBuffer
    trueColorSupport*: bool
    mouseButtons: set[input.MouseButton]

proc exitProc() {.noconv.} =
  disableTrueColors()

  illwillDeinit()
  showCursor()
  quit(0)

method init*(self: TerminalRenderer) =
  illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitProc)
  hideCursor()

  if isTrueColorSupported():
    logger.log(lvlInfo, "Enable true color support")
    self.trueColorSupport = true
    enableTrueColors()

  self.buffer = newTerminalBuffer(terminalWidth(), terminalHeight())
  self.redrawEverything = true

method deinit*(self: TerminalRenderer) =
  illwillDeinit()
  showCursor()

method size*(self: TerminalRenderer): Vec2 = vec2(self.buffer.width.float, self.buffer.height.float)

method sizeChanged*(self: TerminalRenderer): bool =
  let (w, h) = (terminalWidth(), terminalHeight())
  return self.buffer.width != w or self.buffer.height != h

proc toInput(key: Key, modifiers: var Modifiers): int64 =
  return case key
  of Key.Enter: INPUT_ENTER
  of Key.Escape: INPUT_ESCAPE
  of Key.Backspace: INPUT_BACKSPACE
  of Key.Space: INPUT_SPACE
  of Key.Delete: INPUT_DELETE
  of Key.Tab: INPUT_TAB
  of Key.Left: INPUT_LEFT
  of Key.Right: INPUT_RIGHT
  of Key.Up: INPUT_UP
  of Key.Down: INPUT_DOWN
  of Key.Home: INPUT_HOME
  of Key.End: INPUT_END
  of Key.PageUp: INPUT_PAGE_UP
  of Key.PageDown: INPUT_PAGE_DOWN
  of Key.A..Key.Z: ord(key) - ord(Key.A) + ord('a')
  of Key.ShiftA..Key.ShiftZ:
    modifiers.incl Modifier.Shift
    ord(key) - ord(Key.ShiftA) + ord('a')
  of Key.CtrlA..Key.CtrlH, Key.CtrlJ..Key.CtrlL, Key.CtrlN..Key.CtrlZ:
    modifiers.incl Modifier.Control
    ord(key) - ord(Key.CtrlA) + ord('a')
  of Key.Zero..Key.Nine: ord(key) - ord(Key.Zero) + ord('0')
  of Key.F1..Key.F12: INPUT_F1 - (ord(key) - ord(KeyF1))
  # of Numpad0..Numpad9: ord(key) - ord(Numpad0) + ord('0')
  # of NumpadAdd: ord '+'
  # of NumpadSubtract: ord '-'
  # of NumpadMultiply: ord '*'
  # of NumpadDivide: ord '/'
  else: 0

method processEvents*(self: TerminalRenderer): int =
  var eventCounter = 0
  while true:
    let key = getKey()
    if key == Key.None:
      break

    inc eventCounter

    if key == Mouse:
      let mouseInfo = getMouse()
      let pos = vec2(mouseInfo.x.float, mouseInfo.y.float)
      let button: input.MouseButton = case mouseInfo.button
      of mbLeft: input.MouseButton.Left
      of mbMiddle: input.MouseButton.Middle
      of mbRight: input.MouseButton.Right
      else: input.MouseButton.Unknown

      var modifiers: Modifiers = {}
      if mouseInfo.ctrl:
        modifiers.incl Modifier.Control
      if mouseInfo.shift:
        modifiers.incl Modifier.Shift

      if mouseInfo.scroll:
        let scroll = if mouseInfo.scrollDir == ScrollDirection.sdDown: -1.0 else: 1.0
        self.onScroll.invoke (pos, vec2(0, scroll), {})
      elif mouseInfo.move:
        # logger.log(lvlInfo, fmt"move to {pos}")
        self.onMouseMove.invoke (pos, vec2(0, 0), {}, self.mouseButtons)
      else:
        # logger.log(lvlInfo, fmt"{mouseInfo.action} {button} at {pos}")
        case mouseInfo.action
        of mbaPressed:
          self.onMousePress.invoke (button, modifiers, pos)
          self.mouseButtons.incl button
        of mbaReleased:
          self.onMouseRelease.invoke (button, modifiers, pos)
          self.mouseButtons.excl button
        else:
          discard

    else:
      var modifiers: Modifiers = {}
      let button = key.toInput(modifiers)
      # logger.log(lvlInfo, fmt"{key} -> {inputToString(button, modifiers)}")
      self.onKeyPress.invoke (button, modifiers)
      discard

  return eventCounter

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