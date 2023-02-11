import std/[asyncdispatch, strformat]
import util, input, editor, text_document, rendering/terminal_renderer, tui, custom_logger, timer, widget_builders
import windy, print

var renderer = new TerminalRenderer
renderer.init()

var ed = newEditor(nil, nil, "terminal")

addTimer 1000, false, proc(fd: AsyncFD): bool =
  return false

var currentModifiers: Modifiers = {}

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

var frameIndex = 0
var frameTime = 0.0
var forceRenderCounter = 0
while not ed.closeRequested:
  defer:
    inc frameIndex

  let pollTimer = startTimer()
  try:
    poll(2)
  except CatchableError:
    # logger.log(lvlError, fmt"[async] Failed to poll async dispatcher: {getCurrentExceptionMsg()}: {getCurrentException().getStackTrace()}")
    discard
  let pollTime = pollTimer.elapsed.ms

  # handle events
  let eventTimer = startTimer()
  var eventCounter = 0
  while true:
    let key = getKey()
    if key == None:
      break

    inc eventCounter

    if key == Mouse:
      let mouseInfo = getMouse()
      let pos = vec2(mouseInfo.x.float, mouseInfo.y.float)
      let button: Button = case mouseInfo.button
      of mbNone: Button.ButtonUnknown
      of mbLeft: Button.MouseLeft
      of mbMiddle: Button.MouseMiddle
      of mbRight: Button.MouseRight
      else: Button.ButtonUnknown

      var modifiers: Modifiers = {}
      if mouseInfo.ctrl:
        modifiers.incl Modifier.Control
      if mouseInfo.shift:
        modifiers.incl Modifier.Shift

      if mouseInfo.scroll:
        let scroll = if mouseInfo.scrollDir == ScrollDirection.sdDown: -1.0 else: 1.0
        logger.log(lvlInfo, fmt"scroll: {scroll} at {pos}")
        ed.handleScroll(vec2(0, scroll), pos)
      elif mouseInfo.move:
        logger.log(lvlInfo, fmt"move to {pos}")
        ed.handleMouseMove(pos, vec2(0, 0))
      else:
        logger.log(lvlInfo, fmt"{mouseInfo.action} {button} at {pos}")
        case mouseInfo.action
        of mbaPressed:
          ed.handleMousePress(button, modifiers, pos)
          discard
        of mbaReleased:
          ed.handleMouseRelease(button, modifiers, pos)
          discard
        else:
          discard

    else:
      var modifiers: Modifiers = {}
      let button = key.toInput(modifiers)
      logger.log(lvlInfo, fmt"{key} -> {inputToString(button, modifiers)}")
      ed.handleKeyPress(button, modifiers)
      discard

    if key == Key.CtrlQ:
      ed.quit()

  let eventTime = eventTimer.elapsed.ms

  if eventCounter > 0:
    logger.log(lvlInfo, fmt"Handled {eventCounter} events in {eventTime:>5.2}ms")

  var w = WPanel()
  w.children.add(WText(text: fmt"Frame: {frameTime:>5.2}ms, Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms         "))
  # if ed.getEditorForId(getActiveEditor()).getSome(editor) and editor of TextDocumentEditor:
  #   for line in editor.TextDocumentEditor.document.lines:
  #     w.children.add(WText(text: line))

  block:
    ed.frameTimer = startTimer()

    let layoutChanged = if forceRenderCounter > 0 or renderer.sizeChanged:
      ed.layoutWidgetTree(renderer.size, frameIndex)
    else:
      false
    let widgetsChanged = ed.updateWidgetTree(frameIndex)
    # let layoutChanged = if widgetsChanged or renderer.sizeChanged or forceRenderCounter > 0:
    #   ed.layoutWidgetTree(renderer.size, frameIndex)
    # else:
    #   false

    if widgetsChanged or layoutChanged or renderer.sizeChanged:
      forceRenderCounter = 2

    renderer.redrawEverything = forceRenderCounter > 0
    renderer.render(ed.widget)
    dec forceRenderCounter
    frameTime = ed.frameTimer.elapsed.ms
    # if getOption[bool](ed, "editor.log-frame-time"):
    #   logger.log(lvlInfo, fmt"Frame: {ed.frameTimer.elapsed.ms:>5.2}ms")

  logger.flush()

  # sleep(10)

ed.shutdown()
renderer.deinit()