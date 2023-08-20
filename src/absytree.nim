when defined(js):
  {.error: "absytree_terminal.nim does not work in js backend. Use absytree_js.nim instead.".}

when defined(windows):
  static:
    echo "Compiling for windows"
elif defined(linux):
  static:
    echo "Compiling for linux"
elif defined(posix):
  static:
    echo "Compiling for posix"
else:
  static:
    echo "Compiling for unknown"

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
  if backend.get == Terminal or logToFile or defined(forceLogToFile):
    logger.enableFileLogger()
  if backend.get != Terminal:
    logger.enableConsoleLogger()

import std/[strformat]
import util, app, timer, platform/widget_builders, platform/platform, custom_async
import language/language_server

when enableTerminal:
  import platform/terminal_platform

when enableGui:
  import platform/gui_platform

# Initialize renderer
var rend: Platform = nil
case backend.get
of Terminal:
  when enableTerminal:
    log(lvlInfo, "Creating terminal renderer")
    rend = new TerminalPlatform
  else:
    echo "[error] Terminal backend not available in this build"
    quit(1)

of Gui:
  when enableGui:
    log(lvlInfo, "Creating GUI renderer")
    rend = new GuiPlatform
  else:
    echo "[error] GUI backend not available in this build"
    quit(1)

else:
    echo "[error] This should not happen"
    quit(1)


rend.init()

proc runApp(): Future[void] {.async.} =
  var ed = await newEditor(backend.get, rend)

  addTimer 1000, false, proc(fd: AsyncFD): bool =
    return false

  var frameIndex = 0
  var frameTime = 0.0

  let minPollPerFrameMs = 1.0
  let maxPollPerFrameMs = 10.0
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
    if false:
      while pollTimer.elapsed.ms < 8:
        poll(2)
    else:
      try:
        pollBudgetMs += max(minPollPerFrameMs, maxPollPerFrameMs - totalTimer.elapsed.ms)
        while pollBudgetMs > maxPollPerFrameMs:
          let start = startTimer()
          poll(maxPollPerFrameMs.int)
          pollBudgetMs -= start.elapsed.ms
      except CatchableError:
        # log(lvlError, fmt"[async] Failed to poll async dispatcher: {getCurrentExceptionMsg()}: {getCurrentException().getStackTrace()}")
        discard
    let pollTime = pollTimer.elapsed.ms

    let timeToSleep = 8 - totalTimer.elapsed.ms
    if timeToSleep > 1:
      # debugf"sleep for {timeToSleep.int}ms"
      sleep(timeToSleep.int)

    let totalTime = totalTimer.elapsed.ms
    if eventCounter > 0 and totalTime > 20:
      log(lvlDebug, fmt"Total: {totalTime:>5.2}, Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms, Frame: {frameTime:>5.2}ms (u: {updateTime:>5.2}ms, l: {layoutTime:>5.2}ms, r: {renderTime:>5.2}ms)")
      discard

    # log(lvlDebug, fmt"Total: {totalTime:>5.2}, Frame: {frameTime:>5.2}ms ({layoutTime:>5.2}ms, {updateTime:>5.2}ms, {renderTime:>5.2}ms), Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms")

    logger.flush()

  ed.shutdown()
  rend.deinit()

waitFor runApp()