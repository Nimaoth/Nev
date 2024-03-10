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

import std/[parseopt, options, macros]
import misc/[custom_logger]
import compilation_config, scripting_api, app_options

when enableGui:
  static:
    echo "GUI backend enabled"

when enableTerminal:
  static:
    echo "Terminal backend enabled"

logCategory "main"

var backend: Option[Backend] = if enableGui: Backend.Gui.some
elif enableTerminal: Backend.Terminal.some
else: Backend.none

var logToFile = false
var opts = AppOptions()

block: ## Parse command line options
  var optParser = initOptParser("")
  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      opts.fileToOpen = key.some

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

      of "no-nimscript", "n":
        opts.disableNimScriptPlugins = true

      of "no-wasm", "w":
        opts.disableWasmPlugins = true

      of "no-opts", "o":
        opts.dontRestoreOptions = true

      of "no-config", "c":
        opts.dontRestoreConfig = true

      of "no-config-opts":
        opts.dontRestoreConfig = true
        opts.dontRestoreOptions = true

      of "clean":
        opts.dontRestoreConfig = true
        opts.dontRestoreOptions = true
        opts.disableNimScriptPlugins = true
        opts.disableWasmPlugins = true

      of "session", "s":
        opts.sessionOverride = val.some

    of cmdEnd: assert(false) # cannot happen

if backend.isNone:
  echo "Error: No backend selected"
  quit(0)

assert backend.isSome

block: ## Enable loggers
  if backend.get == Terminal or logToFile or defined(forceLogToFile):
    logger.enableFileLogger()

  when defined(allowConsoleLogger):
    if backend.get != Terminal:
      logger.enableConsoleLogger()

import std/[strformat]
import misc/[util, timer, custom_async]
import platform/platform
import ui/widget_builders
import text/language/language_server
import app

when enableTerminal:
  import platform/terminal_platform

when enableGui:
  import platform/[gui_platform, tui]

  if backend.get == Gui:
    let trueColorSupport = myEnableTrueColors()
    log lvlInfo, fmt"True colors: {trueColorSupport}"

# Do this after every import
# Don't remove those imports, they are needed by createNimScriptContextConstructorAndGenerateBindings
import std/[macrocache]
import ast/model_document
import text/text_editor
import text/language/lsp_client
import selector_popup
when not defined(js):
  import wasm3, wasm3/[wasm3c, wasmconversions]

createNimScriptContextConstructorAndGenerateBindings()

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

import ui/node

var renderedLastFrame = false

proc runApp(): Future[void] {.async.} =
  var ed = await newEditor(backend.get, rend, opts)

  addTimer 2, false, proc(fd: AsyncFD): bool =
    return false

  var frameIndex = 0
  var frameTime = 0.0

  let minPollPerFrameMs = 1.0
  let maxPollPerFrameMs = 5.0
  var pollBudgetMs = 0.0
  while not ed.closeRequested:
    defer:
      inc frameIndex

    let totalTimer = startTimer()

    # handle events
    let eventTimer = startTimer()
    let eventCounter = rend.processEvents()
    let eventTime = eventTimer.elapsed.ms

    var updateTime, renderTime: float
    block:
      let delta = ed.frameTimer.elapsed.ms
      ed.frameTimer = startTimer()

      let updateTimer = startTimer()

      rend.builder.frameTime = delta

      when enableGui:
        let size = if rend of GuiPlatform and rend.GuiPlatform.showDrawnNodes: rend.size * vec2(0.5, 1) else: rend.size
      else:
        let size = rend.size

      var rerender = false
      if size != rend.builder.root.boundsActual.wh or rend.requestedRender:
        rend.requestedRender = false
        rend.builder.beginFrame(size)
        ed.updateWidgetTree(frameIndex)
        rend.builder.endFrame()
        rerender = true
      elif rend.builder.animatingNodes.len > 0:
        rend.builder.frameIndex.inc
        rend.builder.postProcessNodes()
        rerender = true

      updateTime = updateTimer.elapsed.ms

      renderedLastFrame = rerender

      if rerender:
        let renderTimer = startTimer()
        rend.render()
        renderTime = renderTimer.elapsed.ms

      frameTime = ed.frameTimer.elapsed.ms

    logger.flush()

    let pollTimer = startTimer()
    if false:
      while pollTimer.elapsed.ms < 8:
        poll(2)
    else:
      try:
        pollBudgetMs += clamp(15 - totalTimer.elapsed.ms, minPollPerFrameMs, maxPollPerFrameMs)
        var totalPollTime = 0.0
        while pollBudgetMs > maxPollPerFrameMs:
          let start = startTimer()
          poll(maxPollPerFrameMs.int)
          pollBudgetMs -= start.elapsed.ms
          totalPollTime = totalPollTime + start.elapsed.ms
      except CatchableError:
        # log(lvlError, fmt"Failed to poll async dispatcher: {getCurrentExceptionMsg()}: {getCurrentException().getStackTrace()}")
        discard
    let pollTime = pollTimer.elapsed.ms

    # let timeToSleep = 8 - totalTimer.elapsed.ms
    # if timeToSleep > 1:
    #   # debugf"sleep for {timeToSleep.int}ms"
    #   sleep(timeToSleep.int)

    let totalTime = totalTimer.elapsed.ms
    if (eventCounter > 0 and totalTime > 15) or totalTime > 20:
      log(lvlDebug, fmt"Total: {totalTime:>5.2f}, Poll: {pollTime:>5.2f}ms, Event: {eventTime:>5.2f}ms, Frame: {frameTime:>5.2f}ms (u: {updateTime:>5.2f}ms, r: {renderTime:>5.2f}ms)")
      discard

    # log(lvlDebug, fmt"Total: {totalTime:>5.2}, Frame: {frameTime:>5.2}ms ({layoutTime:>5.2}ms, {updateTime:>5.2}ms, {renderTime:>5.2}ms), Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms")

    logger.flush()

  log lvlInfo, "Shutting down editor"
  ed.shutdown()
  log lvlInfo, "Shutting down platform"
  rend.deinit()

waitFor runApp()

when enableGui:
  if backend.get == Gui:
    myDisableTrueColors()