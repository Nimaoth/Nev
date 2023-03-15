import std/[strformat, terminal, typetraits, enumutils]
import platform, widgets
import tui, custom_logger, rect_utils, input, event
import vmath
import chroma as chroma
import std/colors as stdcolors

export platform, widgets

type
  TerminalPlatform* = ref object of Platform
    buffer: TerminalBuffer
    trueColorSupport*: bool
    mouseButtons: set[input.MouseButton]
    masks: seq[Rect]

proc exitProc() {.noconv.} =
  resetAttributes()
  myDisableTrueColors()
  illwillDeinit()
  showCursor()
  quit(0)

proc toStdColor(color: tui.ForegroundColor): stdcolors.Color =
  return case color
  of fgRed: stdcolors.rgb(255, 0, 0)
  of fgGreen: stdcolors.rgb(0, 255, 0)
  of fgYellow: stdcolors.rgb(255, 255, 0)
  of fgBlue: stdcolors.rgb(0, 0, 255)
  of fgMagenta: stdcolors.rgb(255, 0, 255)
  of fgCyan: stdcolors.rgb(0, 255, 255)
  of fgWhite: stdcolors.rgb(255, 255, 255)
  else: stdcolors.rgb(0, 0, 0)

proc toStdColor(color: tui.BackgroundColor): stdcolors.Color =
  return case color
  of bgRed: stdcolors.rgb(255, 0, 0)
  of bgGreen: stdcolors.rgb(0, 255, 0)
  of bgYellow: stdcolors.rgb(255, 255, 0)
  of bgBlue: stdcolors.rgb(0, 0, 255)
  of bgMagenta: stdcolors.rgb(255, 0, 255)
  of bgCyan: stdcolors.rgb(0, 255, 255)
  of bgWhite: stdcolors.rgb(255, 255, 255)
  else: stdcolors.rgb(0, 0, 0)

proc getClosestColor[T: HoleyEnum](r, g, b: int, default: T): T =
  var minDistance = 10000000.0
  result = default
  {.push warning[HoleEnumConv]:off.}
  for fg in enumutils.items(T):
    let fgStd = fg.toStdColor
    let uiae = fgStd.extractRGB
    let distance = sqrt((r - uiae.r).float.pow(2) + (g - uiae.g).float.pow(2) + (b - uiae.b).float.pow(2))
    if distance < minDistance:
      minDistance = distance
      result = fg
  {.pop.}

method init*(self: TerminalPlatform) =
  illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitProc)
  hideCursor()

  if myEnableTrueColors():
    logger.log(lvlInfo, "Enable true color support")
    self.trueColorSupport = true

  self.layoutOptions.getTextBounds = proc(text: string): Vec2 =
    result.x = text.len.float
    result.y = 1

  self.buffer = newTerminalBuffer(terminalWidth(), terminalHeight())
  self.redrawEverything = true

method deinit*(self: TerminalPlatform) =
  resetAttributes()
  myDisableTrueColors()
  illwillDeinit()
  showCursor()

method requestRender*(self: TerminalPlatform, redrawEverything = false) =
  self.redrawEverything = self.redrawEverything or redrawEverything

method size*(self: TerminalPlatform): Vec2 = vec2(self.buffer.width.float, self.buffer.height.float)

method sizeChanged*(self: TerminalPlatform): bool =
  let (w, h) = (terminalWidth(), terminalHeight())
  return self.buffer.width != w or self.buffer.height != h

method fontSize*(self: TerminalPlatform): float = 1
method lineDistance*(self: TerminalPlatform): float = 0
method lineHeight*(self: TerminalPlatform): float = 1
method charWidth*(self: TerminalPlatform): float = 1
method measureText*(self: TerminalPlatform, text: string): Vec2 = vec2(text.len.float, 1)

proc pushMask(self: TerminalPlatform, mask: Rect) =
  self.masks.add mask

proc popMask(self: TerminalPlatform) =
  assert self.masks.len > 0
  discard self.masks.pop()

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
  of Key.F1..Key.F12: INPUT_F1 - (ord(key) - ord(Key.F1))
  # of Numpad0..Numpad9: ord(key) - ord(Numpad0) + ord('0')
  # of NumpadAdd: ord '+'
  # of NumpadSubtract: ord '-'
  # of NumpadMultiply: ord '*'
  # of NumpadDivide: ord '/'
  else: 0

method processEvents*(self: TerminalPlatform): int =
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
      self.onKeyPress.invoke (button, modifiers)
      discard

  return eventCounter

proc toStdColor(color: chroma.Color): stdcolors.Color =
  let rgb = color.asRgb
  return stdcolors.rgb(rgb.r, rgb.g, rgb.b)

method renderWidget(self: WWidget, renderer: TerminalPlatform, forceRedraw: bool, frameIndex: int) {.base.} = discard

method render*(self: TerminalPlatform, widget: WWidget, frameIndex: int) =
  if self.sizeChanged:
    let (w, h) = (terminalWidth(), terminalHeight())
    logger.log(lvlInfo, fmt"Terminal size changed from {self.buffer.width}x{self.buffer.height} to {w}x{h}, recreate buffer")
    self.buffer = newTerminalBuffer(w, h)
    self.redrawEverything = true

  widget.renderWidget(self, self.redrawEverything, frameIndex)

  # This can fail if the terminal was resized during rendering, but in that case we'll just rerender next frame
  try:
    self.buffer.display()
    self.redrawEverything = false
  except CatchableError:
    logger.log(lvlError, fmt"[term-render] Failed to display buffer: {getCurrentExceptionMsg()}")
    self.redrawEverything = true

proc setForegroundColor(self: TerminalPlatform, color: chroma.Color) =
  if self.trueColorSupport:
    self.buffer.setForegroundColor(color.toStdColor)
  else:
    let stdColor = color.toStdColor.extractRGB
    let fgColor = getClosestColor[tui.ForegroundColor](stdColor.r, stdColor.g, stdColor.b, fgWhite)
    self.buffer.setForegroundColor(fgColor)

proc setBackgroundColor(self: TerminalPlatform, color: chroma.Color) =
  if self.trueColorSupport:
    self.buffer.setBackgroundColor(color.toStdColor, color.a)
  else:
    let stdColor = color.toStdColor.extractRGB
    let bgColor = getClosestColor[tui.BackgroundColor](stdColor.r, stdColor.g, stdColor.b, bgBlack)
    self.buffer.setBackgroundColor(bgColor)

proc fillRect(self: TerminalPlatform, bounds: Rect, color: chroma.Color) =
  let mask = if self.masks.len > 0:
    self.masks[self.masks.high]
  else:
    rect(vec2(0, 0), self.size)

  let bounds = bounds and mask

  self.setBackgroundColor(color)
  self.buffer.fillBackground(bounds.x.int, bounds.y.int, bounds.xw.int - 1, bounds.yh.int - 1)
  self.buffer.setBackgroundColor(bgNone)


method renderWidget(self: WPanel, renderer: TerminalPlatform, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange} fill background {self.children.len}"
    renderer.fillRect(self.lastBounds, self.getBackgroundColor)

  if self.maskContent:
    renderer.pushMask(self.lastBounds)
  defer:
    if self.maskContent:
      renderer.popMask()

  for c in self.children:
    c.renderWidget(renderer, forceRedraw or self.fillBackground, frameIndex)

method renderWidget(self: WStack, renderer: TerminalPlatform, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.fillRect(self.lastBounds, self.getBackgroundColor)

  for c in self.children:
    c.renderWidget(renderer, forceRedraw or self.fillBackground, frameIndex)

method renderWidget(self: WVerticalList, renderer: TerminalPlatform, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.fillRect(self.lastBounds, self.getBackgroundColor)

  for c in self.children:
    c.renderWidget(renderer, forceRedraw or self.fillBackground, frameIndex)

method renderWidget(self: WHorizontalList, renderer: TerminalPlatform, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.fillRect(self.lastBounds, self.getBackgroundColor)

  for c in self.children:
    c.renderWidget(renderer, forceRedraw or self.fillBackground, frameIndex)

proc writeText(self: TerminalPlatform, pos: Vec2, text: string) =
  let mask = if self.masks.len > 0:
    self.masks[self.masks.high]
  else:
    rect(vec2(0, 0), self.size)

  # Check if text outside vertically
  if pos.y < mask.y or pos.y >= mask.yh:
    return

  let cutoffLeft = max(mask.x - pos.x, 0).int
  let cutoffRight = max(pos.x + text.len.float * self.charWidth - mask.xw, 0).int

  if cutoffLeft >= text.len or cutoffRight >= text.len or text.len - cutoffLeft - cutoffRight <= 0:
    return

  self.buffer.write(pos.x.int + cutoffLeft.int, pos.y.int, text[cutoffLeft..^(cutoffRight + 1)])

method renderWidget(self: WText, renderer: TerminalPlatform, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and self.lastInvalidation < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.fillRect(self.lastBounds, self.getBackgroundColor)

  renderer.buffer.setBackgroundColor(bgNone)
  renderer.setForegroundColor(self.getForegroundColor)
  renderer.writeText(self.lastBounds.xy, self.text)

  self.lastRenderedText = self.text