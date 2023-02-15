import std/[parseopt, options, os]

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
import util, editor, timer, platform/widget_builders, platform/platform

when enableTerminal:
  import platform/terminal_platform

when enableGui:
  import platform/gui_platform

# Initialize renderer
var rend: Platform = nil
case backend.get
of Terminal:
  when enableTerminal:
    logger.log(lvlInfo, "Creating terminal renderer")
    rend = new TerminalPlatform
  else:
    echo "[error] Terminal backend not available in this build"
    quit(1)

of Gui:
  when enableGui:
    logger.log(lvlInfo, "Creating GUI renderer")
    rend = new GuiPlatform
  else:
    echo "[error] GUI backend not available in this build"
    quit(1)

rend.init()

var ed = newEditor(nil, nil, backend.get, rend)

addTimer 1000, false, proc(fd: AsyncFD): bool =
  return false

var frameIndex = 0
var frameTime = 0.0

let minPollPerFrameMs = 1.0
let maxPollPerFrameMs = 4.0
var pollBudgetMs = 0.0
while not ed.closeRequested:
  defer:
    inc frameIndex

  let totalTimer = startTimer()

  # handle events
  let eventTimer = startTimer()
  let eventCounter = rend.processEvents()
  let eventTime = eventTimer.elapsed.ms

  var layoutTime, updateTime, renderTime: float
  block:
    ed.frameTimer = startTimer()

    let updateTimer = startTimer()
    ed.updateWidgetTree(frameIndex)
    updateTime = updateTimer.elapsed.ms

    let layoutTimer = startTimer()
    ed.layoutWidgetTree(rend.size, frameIndex)
    layoutTime = layoutTimer.elapsed.ms

    let renderTimer = startTimer()
    rend.render(ed.widget, frameIndex)
    renderTime = renderTimer.elapsed.ms

    frameTime = ed.frameTimer.elapsed.ms

  logger.flush()

  let pollTimer = startTimer()
  try:
    pollBudgetMs += max(minPollPerFrameMs, maxPollPerFrameMs - totalTimer.elapsed.ms)
    if pollBudgetMs > maxPollPerFrameMs:
      poll(maxPollPerFrameMs.int)
      pollBudgetMs -= pollTimer.elapsed.ms
  except CatchableError:
    # logger.log(lvlError, fmt"[async] Failed to poll async dispatcher: {getCurrentExceptionMsg()}: {getCurrentException().getStackTrace()}")
    discard
  let pollTime = pollTimer.elapsed.ms

  let timeToSleep = 8 - totalTimer.elapsed.ms
  if timeToSleep > 1:
    # debugf"sleep for {timeToSleep.int}ms"
    sleep(timeToSleep.int)

  let totalTime = totalTimer.elapsed.ms
  if eventCounter > 0:
    logger.log(lvlInfo, fmt"Total: {totalTime:>5.2}, Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms, Frame: {frameTime:>5.2}ms (u: {updateTime:>5.2}ms, l: {layoutTime:>5.2}ms, r: {renderTime:>5.2}ms)")
    discard

  # logger.log(lvlInfo, fmt"Total: {totalTime:>5.2}, Frame: {frameTime:>5.2}ms ({layoutTime:>5.2}ms, {updateTime:>5.2}ms, {renderTime:>5.2}ms), Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms")

  logger.flush()

ed.shutdown()
rend.deinit()
