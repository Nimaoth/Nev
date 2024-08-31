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

import std/[parseopt, options, macros, strutils, os, terminal]
import misc/[custom_logger, util]
import compilation_config, scripting_api, app_options

proc tryAttach(opts: AppOptions, processId: int)

when enableGui:
  static:
    echo "GUI backend enabled"

when enableTerminal:
  static:
    echo "Terminal backend enabled"

logCategory "main"

when defined(windows):
  import winim

proc ownsConsole*(): bool =
  when defined(windows):
    let consoleWnd = GetConsoleWindow()
    var dwProcessId: DWORD
    GetWindowThreadProcessId(consoleWnd, dwProcessId.addr)
    return GetCurrentProcessId() == dwProcessId
  else:
    # todo
    return true

var backend: Option[Backend] = if enableGui: Backend.Gui.some
elif enableTerminal: Backend.Terminal.some
else: Backend.none

var logToFile = false
var logToConsole = true
var disableLogging = false
var opts = AppOptions()

const helpText = """
    ast [options] [file]

Options:
  -g, --gui              Launch gui version (if available)
  -t, --terminal         Launch terminal version (if available)
  -p, --setting          Set value of settings (multiple can be set)
  -r, --early-command    Run command after all basic initialization is done
  -R, --late-command     Run command after all initialization is done
  -f, --log-to-file      Enable file logger
  -k, --log-to-console   Enable console logger
  -l, --no-log           Disable logging
  -n, --no-nimscript     Don't load nimscript file from user directory
  -w, --no-wasm          Don't load wasm plugins
  -c, --no-config        Don't load json config files.
  -s, --session          Load a specific session.
  --attach               Open the passed files in an existing instance if it already exists.
  --clean                Don't load any configs/sessions/plugins

Examples:
  ast                                              Open .absytree-session if it exists
  ast test.txt                                     Open test.txt, don't open any session
  ast -s:my-session.abystree-session               Open session my-session.absytree-session
  ast -p:ui.background.transparent=true            Set setting
  ast "-r:.lsp-log-verbose true"                   Enable debug logging for LSP immediately
"""

block: ## Parse command line options
  var optParser = initOptParser("")
  var attach = bool.none
  var attachProcessId = 0

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      opts.fileToOpen = key.some

    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h":
        echo helpText
        quit(0)

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

      of "setting", "p":
        opts.settings.add val

      of "early-command", "r":
        opts.earlyCommands.add val

      of "late-command", "R":
        opts.lateCommands.add val

      of "log-to-file", "f":
        logToFile = val.parseBool.catch(true)

      of "log-to-console", "k":
        logToConsole = val.parseBool.catch(true)

      of "no-log", "l":
        disableLogging = true

      of "no-nimscript", "n":
        opts.disableNimScriptPlugins = true

      of "no-wasm", "w":
        opts.disableWasmPlugins = true

      of "no-config", "c":
        opts.dontRestoreConfig = true

      of "clean":
        opts.dontRestoreConfig = true
        opts.disableNimScriptPlugins = true
        opts.disableWasmPlugins = true

      of "no-attach":
        attach = false.some

      of "attach":
        attach = true.some
        attachProcessId = val.parseInt.catch:
          echo "Expected integer for process id: --attach:1234"
          quit(1)

      of "session", "s":
        opts.sessionOverride = val.some

    of cmdEnd: assert(false) # cannot happen

  if attach.getSome(attach):
    if attach:
      tryAttach(opts, attachProcessId)
  else:
    if not stdout.isatty() or ownsConsole():
      tryAttach(opts, 0)

if backend.isNone:
  echo "Error: No backend selected"
  quit(0)

assert backend.isSome

if not disableLogging: ## Enable loggers
  if backend.get == Terminal or logToFile or defined(forceLogToFile):
    logger.enableFileLogger()

  when defined(allowConsoleLogger):
    if backend.get != Terminal and logToConsole:
      logger.enableConsoleLogger()

import std/[strformat]
import misc/[util, timer, custom_async]
import platform/platform
import ui/widget_builders
import text/language/language_server
import app

import asynctools/asyncipc

proc tryAttach(opts: AppOptions, processId: int) =
  if processId == 0:
    # todo: find process by name
    # return
    discard

  let ipcName = "absytree-" & $processId
  let writeHandle = open(ipcName, sideWriter).catch:
    if processId == 0:
      echo &"No existing editor, open new"
      return
    else:
      echo &"No existing editor with process id {processId}"
      quit(0)

  defer: writeHandle.close()

  proc send(msg: string) =
    echo "Send ", msg
    waitFor writeHandle.write(cast[pointer](msg[0].addr), msg.len)

  # todo: instead of sending -p:... etc, translate the settings to set-option command syntax,
  # pass the commands through as is and traslate fileToOpen to corresponding command.
  for setting in opts.settings:
    send("-p:" & setting)

  for command in opts.earlyCommands:
    send("-r:" & command)

  for command in opts.lateCommands:
    send("-R:" & command)

  if opts.fileToOpen.getSome(file):
    send(file)

  quit(0)

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
when enableAst:
  import ast/model_document
import text/text_editor
import text/language/lsp_client
import text/language/debugger
import selector_popup
import scripting/scripting_base
import wasm3, wasm3/[wasm3c, wasmconversions]

createNimScriptContextConstructorAndGenerateBindings()
static:
  generateScriptingApiPerModule()

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

  var frameIndex = 0
  var frameTime = 0.0

  var lastEvent = startTimer()

  let maxPollPerFrameMs = 5.0
  while not ed.closeRequested:
    defer:
      inc frameIndex

    let totalTimer = startTimer()

    # handle events
    let eventTimer = startTimer()
    gAsyncFrameTimer = startTimer()
    let eventCounter = rend.processEvents()
    let eventTime = eventTimer.elapsed.ms

    if eventCounter > 0:
      lastEvent = startTimer()

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

    if frameIndex == 0:
      log lvlInfo, "First render done"

    logger.flush()

    let pollTimer = startTimer()
    gAsyncFrameTimer = startTimer()
    try:
      let start = startTimer()
      var tries = 50
      while tries > 0 and start.elapsed.ms < maxPollPerFrameMs and hasPendingOperations():
        dec tries
        poll(0)

    except CatchableError:
      discard

    let pollTime = pollTimer.elapsed.ms

    var outlierTime = 20.0

    let frameSoFar = totalTimer.elapsed.ms
    if lastEvent.elapsed.ms > 60000 and frameSoFar < 10:
      sleep(30 - frameSoFar.int)
      outlierTime += 30
    elif lastEvent.elapsed.ms > 1000 and frameSoFar < 10:
      sleep(15 - frameSoFar.int)
      outlierTime += 15
    elif backend.get == Terminal and frameSoFar < 5:
      sleep(5 - frameSoFar.int)
      outlierTime += 5

    let totalTime = totalTimer.elapsed.ms
    if not ed.disableLogFrameTime and
        (eventCounter > 0 or totalTime > outlierTime or ed.logNextFrameTime):
      log(lvlDebug, fmt"Total: {totalTime:>5.2f}, Poll: {pollTime:>5.2f}ms, Event: {eventTime:>5.2f}ms, Frame: {frameTime:>5.2f}ms (u: {updateTime:>5.2f}ms, r: {renderTime:>5.2f}ms)")
    ed.logNextFrameTime = false

    # log(lvlDebug, fmt"Total: {totalTime:>5.2}, Frame: {frameTime:>5.2}ms ({layoutTime:>5.2}ms, {updateTime:>5.2}ms, {renderTime:>5.2}ms), Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms")

    logger.flush()

  log lvlInfo, "Shutting down editor"
  ed.shutdown()
  log lvlInfo, "Shutting down platform"
  rend.deinit()

when defined(enableSysFatalStackTrace) and not defined(wasm):
  proc writeStackTrace2*() {.exportc: "writeStackTrace2", used.} =
    writeStackTrace()

  if false:
    writeStackTrace2()

waitFor runApp()

when enableGui:
  if backend.get == Gui:
    myDisableTrueColors()

when defined(windows) and copyWasmtimeDll:
  import std/[os, compilesettings]
  import wasmh

  static:
    const dllIn = wasmDir / "target/release/wasmtime.dll"
    const dllOut = querySetting(SingleValueSetting.outDir) / "wasmtime.dll"
    echo "[absytree.nim] run tools/copy_wasmtime_dll.nims"
    echo staticExec &"nim \"-d:inDir={dllIn}\" \"-d:outDir={dllOut}\" --hints:off --skipUserCfg --skipProjCfg --skipParentCfg ../tools/copy_wasmtime_dll.nims"
