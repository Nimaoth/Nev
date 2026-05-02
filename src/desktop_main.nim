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

import misc/[timer]
let startupTimer = startTimer()

import std/[parseopt, options, macros, strutils, os, strformat]
import misc/[custom_logger, util]
import compilation_config, scripting_api, app_options
import text/custom_treesitter

when enableGui:
  static:
    echo "GUI backend enabled"

when enableTerminal:
  static:
    echo "Terminal backend enabled"

logCategory "main"

when defined(windows):
  import winim/lean

  discard SetThreadPriority(GetCurrentThreadId(), THREAD_PRIORITY_HIGHEST)

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
const version = "0.5.1"

const helpText = &"""
    nev {version}  [options] [file]

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
  -e, --restore-session  Load the last session which was opened.
  --skip-user            Don't load config files or keybindings from the user home directory.
  --attach               Open the passed files in an existing instance if it already exists.
  --clean                Don't load any configs/sessions/plugins
  --ts-mem-tracking      Enable treesitter memory tracking (for debugging)
  --monitor:n            Open nev on the specified monitor (0, 1, ...). Windows only for now.

Examples:
  nev                                              Open .{appName}-session if it exists
  nev test.txt                                     Open test.txt, don't open any session
  nev -s:my-session.nev-session                    Open session my-session.{appName}-session
  nev -p:ui.background.transparent=true            Set setting
  nev "-r:.lsp-log-verbose true"                   Enable debug logging for LSP immediately
"""

import std/terminal
import command_server

block: ## Parse command line options
  var optParser = initOptParser("")
  var attach = bool.none
  var attachProcessId = 0

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      gAppOptions.fileToOpen = key.some

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
        gAppOptions.settings.add val

      of "early-command", "r":
        gAppOptions.earlyCommands.add val

      of "late-command", "R":
        gAppOptions.lateCommands.add val

      of "log-to-file", "f":
        logToFile = val.parseBool.catch(true)

      of "log-to-console", "k":
        logToConsole = val.parseBool.catch(true)

      of "no-log", "l":
        disableLogging = true

      of "no-nimscript", "n":
        gAppOptions.disableNimScriptPlugins = true

      of "no-wasm", "w":
        gAppOptions.disableWasmPlugins = true

      of "no-wasm-old", "W":
        gAppOptions.disableOldWasmPlugins = true

      of "no-config", "c":
        gAppOptions.dontRestoreConfig = true

      of "clean":
        gAppOptions.dontRestoreConfig = true
        gAppOptions.disableNimScriptPlugins = true
        gAppOptions.disableWasmPlugins = true
        gAppOptions.disableOldWasmPlugins = true

      of "skip-user":
        gAppOptions.skipUserSettings = true

      of "no-attach":
        attach = false.some

      of "restore-session", "e":
        gAppOptions.restoreLastSession = true

      of "attach":
        attach = true.some
        attachProcessId = val.parseInt.catch:
          echo "Expected integer for process id: --attach:1234"
          quit(1)

      of "session", "s":
        gAppOptions.sessionOverride = val.some

      of "nopty":
        gAppOptions.noPty = true

      of "noui":
        gAppOptions.noUI = true

      of "kittykey":
        gAppOptions.kittyKeyboardFlags = val

      of "monitor":
        gAppOptions.monitor = val.parseInt.some.catch:
          echo "Expected integer for monitor: --monitor:1"
          quit(1)

      of "int3":
        when defined(sysFatalInt3):
          enableSysFatalInt3 = true

      of "ts-mem-tracking":
        enableTreesitterMemoryTracking()

      of "version":
        echo version
        quit(1)

    of cmdEnd: assert(false) # cannot happen

  if attach.getSome(attach):
    if attach:
      tryAttach(gAppOptions, attachProcessId)
  elif gAppOptions.fileToOpen.isSome:
    if not stdout.isatty() or ownsConsole():
      tryAttach(gAppOptions, 0)

if backend.isNone:
  echo "Error: No backend selected"
  quit(0)

assert backend.isSome

if not disableLogging: ## Enable loggers
  if backend.get == Terminal or logToFile or defined(forceLogToFile):
    logger().enableFileLogger()

  when defined(allowConsoleLogger):
    if backend.get != Terminal and logToConsole:
      logger().enableConsoleLogger()

import misc/[custom_async]
import platform/[platform]
import ui/widget_builders
import app, platform_service

when enableTerminal:
  import "../modules/terminal_platform"/terminal_platform

when enableGui:
  import platform/[tui]
  import "../modules/gui_platform"/gui_platform

  if backend.get == Gui:
    let trueColorSupport = myEnableTrueColors()
    log lvlInfo, fmt"True colors: {trueColorSupport}"

# Do this after every import
# Don't remove those imports, they are needed by generatePluginBindings
{.push warning[UnusedImport]:off.}
import plugin_service
import selector_popup, layout/layout, document_editor, session, events, register, selector_popup_builder_impl, vfs_service, toast
import language_server_dynamic
import scripting/expose
import config_provider, event_service
import vcs/vcs_api
import collab
import inlay_hint_component, treesitter_component # todo: make these modules
{.pop.}

import "../modules/stats"

defineSetAllDefaultSettings()

# Initialize renderer
var plat: Platform = nil
case backend.get
of Terminal:
  when enableTerminal:
    log(lvlInfo, "Creating terminal renderer")
    plat = newTerminalPlatform()
    plat.backend = Terminal
  else:
    echo "[error] Terminal backend not available in this build"
    quit(1)

of Gui:
  when enableGui:
    log(lvlInfo, "Creating GUI renderer")
    plat = newGuiPlatform()
    plat.backend = Gui
  else:
    echo "[error] GUI backend not available in this build"
    quit(1)

import ui/node

import chronos/config

const maxPollPerFrameMs = 2.5

proc pollFutures() =
  gAsyncFrameTimer = startTimer()
  try:
    let start = startTimer()
    var tries = 25

    let hasPendingOperations = when chronosFutureTracking:
      pendingFuturesCount() > 0
    else:
      true

    while tries > 0 and start.elapsed.ms < maxPollPerFrameMs and hasPendingOperations:
      dec tries
      poll()

  except CatchableError:
    discard

proc run(app: App, plat: Platform, backend: Backend, appOptions: AppOptions, frameIndex: var int) =
  var frameTime = 0.0

  plat.lastEventTime = startTimer()
  var renderedLastFrame = false

  let totalTime = startTimer()
  var lastTime = totalTime.elapsed.float

  var lowPowerMode = false

  var eventBus: EventService = app.services.getServiceChecked(EventService)
  while not app.closeRequested:
    defer:
      inc frameIndex

    let now = totalTime.elapsed.float
    plat.deltaTime = now - lastTime
    lastTime = now

    let totalTimer = startTimer()

    # handle events
    let eventTimer = startTimer()
    gAsyncFrameTimer = startTimer()
    let eventCounter = plat.processEvents()
    app.services.tick()
    let eventTime = eventTimer.elapsed.ms

    if eventCounter > 0:
      plat.lastEventTime = startTimer()

    var updateTime, renderTime: float
    block:
      let delta = app.frameTimer.elapsed.ms
      app.frameTimer = startTimer()

      let updateTimer = startTimer()

      plat.builder.frameTime = delta
      plat.onPreRender.invoke(plat)
      eventBus.emit(&"platform/prerender", "")

      let size = plat.size
      var rerender = false
      if size != plat.builder.root.boundsActual.wh or plat.requestedRender:
        plat.requestedRender = false
        plat.builder.beginFrame(size, plat.redrawEverything)
        try:
          app.updateWidgetTree(plat.builder, frameIndex)
          plat.builder.endFrame()
        except:
          discard
        rerender = true
      elif plat.builder.animatingNodes.len > 0:
        plat.builder.frameIndex.inc
        try:
          plat.builder.postProcessNodes()
        except:
          discard
        rerender = true

      updateTime = updateTimer.elapsed.ms

      renderedLastFrame = rerender

      if rerender or not lowPowerMode:
        let renderTimer = startTimer()
        plat.render(rerender)
        renderTime = renderTimer.elapsed.ms

      frameTime = app.frameTimer.elapsed.ms

    if frameIndex == 0:
      log lvlInfo, "First render done"

    if not app.firstRenderDone:
      if getServices().getService(StatsService).getSome(stats):
        stats.add("Startup Time", startupTimer.elapsed.ms.int, "ms")
    app.firstRenderDone = true

    {.gcsafe.}:
      logger().flush()

    let pollTimer = startTimer()
    pollFutures()

    let pollTime = pollTimer.elapsed.ms

    var outlierTime = 20.0

    let frameSoFar = totalTimer.elapsed.ms
    let terminalSleepThreshold = app.config.runtime.get("platform.terminal-sleep-threshold", 0)
    if plat.lastEventTime.elapsed.ms > app.config.runtime.get("platform.reduced-fps-2.delay", 60000.0) and frameSoFar < 10:
      let time = app.config.runtime.get("platform.reduced-fps-2.ms", 30)
      sleep(time - frameSoFar.int)
      outlierTime += time.float
      lowPowerMode = true
    elif plat.lastEventTime.elapsed.ms > app.config.runtime.get("platform.reduced-fps-1.delay", 5000.0) and frameSoFar < 10:
      let time = app.config.runtime.get("platform.reduced-fps-2.ms", 15)
      sleep(time - frameSoFar.int)
      outlierTime += time.float
      lowPowerMode = true
    elif backend == Terminal and frameSoFar < terminalSleepThreshold.float:
      sleep(terminalSleepThreshold - frameSoFar.int)
      outlierTime += terminalSleepThreshold.float
      lowPowerMode = false
    else:
      lowPowerMode = false

    let totalTime = totalTimer.elapsed.ms
    if not app.disableLogFrameTime and
        (eventCounter > 0 or totalTime > outlierTime or app.logNextFrameTime or plat.logNextFrameTime):
      log(lvlDebug, fmt"Total: {totalTime:>5.2f} ms, Poll: {pollTime:>5.2f} ms, Event: {eventTime:>5.2f} ms, Frame: {frameTime:>5.2f} ms (u: {updateTime:>5.2f} ms, r: {renderTime:>5.2f} ms)")
    app.logNextFrameTime = false
    plat.logNextFrameTime = false

    # log(lvlDebug, fmt"Total: {totalTime:>5.2}, Frame: {frameTime:>5.2}ms ({layoutTime:>5.2}ms, {updateTime:>5.2}ms, {renderTime:>5.2}ms), Poll: {pollTime:>5.2}ms, Event: {eventTime:>5.2}ms")

    {.gcsafe.}:
      logger().flush()

import service
gServices.addBuiltinServices()

plat.vfs = gServices.getService(VFSService).get.vfs2
plat.init(gAppOptions)
gServices.getService(PlatformService).get.setPlatform(plat)
gServices.waitForServices()

import module_imports
when defined(useDynlib):
  import std/dynlib
  var modules: seq[(string, LibHandle)] = @[]
  proc loadModule(name: string) {.raises: [].} =
    try:
      let path = &"{getAppDir()}\\native_plugins\\{name}.dll"
      log lvlDebug, &"loadLib '{path}'"
      let lib = loadLib(path)
      if lib == nil:
        raise newException(OSError, &"Failed to load library '{path}'")
      modules.add (name, lib)
      let funcName = &"init_module_{name}"
      let init = cast[proc() {.cdecl.}](lib.symAddr(funcName.cstring))
      if init != nil:
        log lvlDebug, &"Init module '{name}'"
        init()
    except Exception as e:
      log lvlError, &"Failed to load module '{name}': {e.msg}"

  try:
    log lvlInfo, "Load dynamic modules"
    module_imports.loadModulesDynamically(loadModule)

    debugf"Finished loading modules"
  except OSError as e:
    log lvlError, &"Failed to load modules: {e.msg}"

else:
  log lvlInfo, "Load static modules"
  initModules()

import misc/event

proc main() =
  let app = newApp(backend.get, plat, gServices, gAppOptions)
  log lvlInfo, &"Finished creating app"
  asyncSpawn app.loadPlugins()

  var eventBus: EventService = app.services.getServiceChecked(EventService)
  var frameIndex = 0

  var p = plat
  discard plat.onResize.subscribe proc() {.gcsafe.} =
    p.onPreRender.invoke(p)
    eventBus.emit(&"platform/prerender", "")

    let size = p.size

    p.requestedRender = false
    p.builder.beginFrame(size)
    try:
      app.updateWidgetTree(p.builder, frameIndex)
      p.builder.endFrame()
    except:
      discard

    p.render(true)
    inc frameIndex
    pollFutures()

  run(app, plat, backend.get, gAppOptions, frameIndex)

  try:
    log lvlInfo, "Shutting down editor"
    app.shutdown()
    log lvlInfo, "Shutting down platform"
    plat.deinit()

    when defined(useDynlib):
      for (name, lib) in modules:
        let funcName = &"shutdown_module_{name}"
        let shutdown = cast[proc() {.cdecl.}](lib.symAddr(funcName.cstring))
        if shutdown != nil:
          shutdown()
    else:
      shutdownModules()

    # Give language server threads some time to deinit properly before force quitting.
    sleep(100)
    log lvlInfo, "All done"
  except:
    discard

main()

when defined(enableSysFatalStackTrace) and not defined(wasm):
  proc writeStackTrace2*() {.exportc: "writeStackTrace2", used.} =
    writeStackTrace()

  if false:
    writeStackTrace2()

when enableGui:
  if backend.get == Gui:
    myDisableTrueColors()

when defined(windows) and copyWasmtimeDll:
  import std/[compilesettings]
  import wasmtime

  static:
    when nimWasmtimeBuildDebug:
      const dllIn = wasmDir / "target/debug/wasmtime.dll"
    else:
      const dllIn = wasmDir / "target/release/wasmtime.dll"
    const dllOut = querySetting(SingleValueSetting.outDir) / "wasmtime.dll"
    echo "[desktop_main.nim] run tools/copy_wasmtime_dll.nims"
    echo staticExec &"nim \"-d:inDir={dllIn}\" \"-d:outDir={dllOut}\" --hints:off --skipUserCfg --skipProjCfg --skipParentCfg ../tools/copy_wasmtime_dll.nims"

printDispatchStats()
