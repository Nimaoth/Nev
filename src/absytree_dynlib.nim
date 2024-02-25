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

import std/[parseopt, options, macros, tables]
import misc/[custom_logger]
import compilation_config, scripting_api, app_options

type UeLog = proc(level: int32, message: cstring) {.cdecl.}

logCategory "main"

logger.enableFileLogger()

type ExternLogger = ref object of Logger
  discard

var ueLogFn: UeLog = nil
method log*(logger: ExternLogger, level: Level, args: varargs[string, `$`]) =
  if not ueLogFn.isNil:
    let ueLevel: int32 = level.int32
    let ln = substituteLog("", level, args)
    {.gcsafe.}:
      ueLogFn(ueLevel, ln.cstring)
  else:
    let ln = substituteLog(defaultFmtStr, level, args)
    echo ln

var externLogger = ExternLogger()
logger.setConsoleLogger(externLogger)

import std/[strformat]
import vmath
import misc/[util, timer, custom_async]
import platform/platform
import ui/widget_builders
import text/language/language_server
import app

import platform/[platform_externc, filesystem]

# Do this after every import
# Don't remove those imports, they are needed by createNimScriptContextConstructorAndGenerateBindings
import std/[macrocache]
import ast/model_document
import text/text_editor
import text/language/lsp_client
import selector_popup
import wasm3, wasm3/[wasm3c, wasmconversions]
import ui/node
import clipboard

createNimScriptContextConstructorAndGenerateBindings()

type OnAppCreated = proc(app: ptr AppObject, userData: pointer) {.cdecl.}

var rend: ExternCPlatform = nil
var gApp: App = nil

proc runApp(onAppCreated: OnAppCreated, userData: pointer): Future[void] {.async.} =
  echo "Creating platform..."
  rend = new ExternCPlatform
  rend.init()

  echo "Creating app..."
  var opts = AppOptions(disableNimScriptPlugins: true)
  gApp = await newEditor(Backend.Gui, rend, opts)
  onAppCreated(gApp[].addr, userData)

proc shutdown() =
  destroyClipboard()

  if gApp.isNotNil:
    log lvlInfo, "Shutting down editor"
    gApp.shutdown()
    gApp = nil

  if rend.isNotNil:
    log lvlInfo, "Shutting down platform"
    rend.deinit()
    rend = nil

proc NimMain() {.cdecl, importc.}

proc absytree_init(userData: pointer, onAppCreated: OnAppCreated, ueLog: UeLog) {.exportc, dynlib, cdecl.} =
  NimMain()
  ueLogFn = ueLog
  echo "Initializing Absytree..."
  fs.init("D:/Absytree")
  waitFor runApp(onAppCreated, userData)

proc absytree_poll(timeoutMs: int32) {.exportc, dynlib, cdecl.} =
  try:
    poll(timeoutMs.int)
  except ValueError:
    discard

proc absytree_shutdown() {.exportc, dynlib, cdecl.} =
  echo "Shutting down Absytree..."
  shutdown()

  when isFutureLoggingEnabled:
    while hasPendingOperations():
      debugf"Futures in progress:"
      debugf"----------------------------"
      for (info, x) in getFuturesInProgress().pairs:
        debugf"{info.fromProc}: {info.stackTrace}"
      debugf"----------------------------"
      drain(100)

  else:
    drain(10000)
  GC_FullCollect()

proc absytree_input_keys*(self: ptr AppObject, input: cstring) {.exportc, dynlib, cdecl.} =
  echo cast[int](gApp[].addr), ", ", cast[int](self.pointer)
  if gApp.isNotNil:
    gApp.inputKeys($input)
  # self[].inputKeys($input)

proc absytree_key_down*(input: int64, modBits: int32): bool {.exportc, dynlib, cdecl.} =
  if gApp.isNotNil:
    let mods = cast[Modifiers](modBits)
    gApp.handleKeyPress(input, mods)
    return true

proc absytree_key_up*(input: int64, modBits: int32): bool {.exportc, dynlib, cdecl.} =
  if gApp.isNotNil:
    let mods = cast[Modifiers](modBits)
    gApp.handleKeyRelease(input, mods)
    return true

proc absytree_mouse_down*(input: int64, modBits: int32, x, y: float32): bool {.exportc, dynlib, cdecl.} =
  if gApp.isNotNil:
    let mods = cast[Modifiers](modBits)
    return rend.builder.handleMousePressed(input.MouseButton, mods, vec2(x, y))
  return false

proc absytree_mouse_up*(input: int64, modBits: int32, x, y: float32): bool {.exportc, dynlib, cdecl.} =
  if gApp.isNotNil:
    let mods = cast[Modifiers](modBits)
    return rend.builder.handleMouseReleased(input.MouseButton, mods, vec2(x, y))
  return false

proc absytree_mouse_moved*(input: int64, x, y: float32): bool {.exportc, dynlib, cdecl.} =
  if gApp.isNotNil:
    let inputs: set[MouseButton] = if input < 0: {} else: {input.MouseButton}
    return rend.builder.handleMouseMoved(vec2(x, y), inputs)
  return false

proc absytree_mouse_scroll*(input: int64, modBits: int32, x, y: float32): bool {.exportc, dynlib, cdecl.} =
  if gApp.isNotNil:
    let mods = cast[Modifiers](modBits)
    return rend.builder.handleMouseScroll(vec2(x, y), vec2(0, input.float32), mods)
  return false

proc absytree_render*(width: float32, height: float32) {.exportc, dynlib, cdecl.} =
  if gApp.isNil:
    return

  var updateTime, renderTime: float
  block:
    let delta = gApp.frameTimer.elapsed.ms
    gApp.frameTimer = startTimer()

    let updateTimer = startTimer()

    rend.builder.frameTime = delta

    rend.size = vec2(width, height)
    let size = rend.size

    var rerender = false
    if size != rend.builder.root.boundsActual.wh or rend.requestedRender:
      rend.requestedRender = false
      rend.builder.beginFrame(size)
      gApp.updateWidgetTree(rend.builder.frameIndex)
      rend.builder.endFrame()
      rerender = true
    elif rend.builder.animatingNodes.len > 0:
      rend.builder.frameIndex.inc
      rend.builder.postProcessNodes()
      rerender = true

    updateTime = updateTimer.elapsed.ms

    let renderTimer = startTimer()
    rend.render()
    renderTime = renderTimer.elapsed.ms

    let frameTime = gApp.frameTimer.elapsed.ms
    if rerender and frameTime > 5:
      debugf"Update: {updateTime}ms, Render: {renderTime}ms, Frame: {frameTime}ms"

