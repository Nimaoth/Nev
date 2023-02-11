import std/[parseopt, options]

import compilation_config, custom_logger, scripting_api

var backend: Option[Backend] = if enableGui: Backend.Gui.some
elif enableTerminal: Backend.Terminal.some
else: Backend.none

var logToFile = false

block: ## Parse command line options
  var optParser = initOptParser("")
  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      discard

    of cmdLongOption, cmdShortOption:
      case key
      of "gui", "g":
        when enableGui:
          backend = Backend.Gui.some
        else:
          echo "[error] GUI backend not available in this build"
          quit(1)

      of "terminal", "t":
        when enableTerminal:
          backend = Backend.Terminal.some
        else:
          echo "[error] Terminal backend not available in this build"
          quit(1)

      of "log-to-file", "f":
        logToFile = true

    of cmdEnd: assert(false) # cannot happen

if backend.isNone:
  echo "Error: No backend selected"
  quit(0)

assert backend.isSome

block: ## Enable loggers
  if backend.get == Terminal or logToFile:
    logger.enableFileLogger()
  if backend.get != Terminal:
    logger.enableConsoleLogger()

import std/[asyncdispatch, strformat]
import util, input, editor, text_document, tui, custom_logger, timer, widget_builders, rendering/renderer
import print

when enableTerminal:
  import rendering/terminal_renderer

when enableGui:
  import rendering/gui_renderer

# Initialize renderer
var rend: Renderer = nil
case backend.get
of Terminal:
  when enableTerminal:
    logger.log(lvlInfo, "Creating terminal renderer")
    rend = new TerminalRenderer
  else:
    echo "[error] Terminal backend not available in this build"
    quit(1)

of Gui:
  when enableGui:
    logger.log(lvlInfo, "Creating GUI renderer")
    rend = new GuiRenderer
  else:
    echo "[error] GUI backend not available in this build"
    quit(1)

rend.init()

var ed = newEditor(nil, nil, backend.get, rend)

addTimer 1000, false, proc(fd: AsyncFD): bool =
  return false

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
  let eventCounter = rend.processEvents()
  let eventTime = eventTimer.elapsed.ms

  if eventCounter > 0:
    logger.log(lvlInfo, fmt"Handled {eventCounter} events in {eventTime:>5.2}ms")

  block:
    ed.frameTimer = startTimer()

    let layoutChanged = if forceRenderCounter > 0 or rend.sizeChanged:
      ed.layoutWidgetTree(rend.size, frameIndex)
    else:
      false
    let widgetsChanged = ed.updateWidgetTree(frameIndex)

    if widgetsChanged or layoutChanged or rend.sizeChanged:
      forceRenderCounter = 2

    rend.redrawEverything = forceRenderCounter > 0
    rend.render(ed.widget)
    dec forceRenderCounter
    frameTime = ed.frameTimer.elapsed.ms

  if eventCounter > 0:
    logger.log(lvlInfo, fmt"Frame: {frameTime:>5.2}ms, Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms")

  logger.flush()

ed.shutdown()
rend.deinit()
