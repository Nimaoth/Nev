import std/[strformat, json, jsonutils]
import wit_guest

import scripting/binary_encoder
import ui/render_command

when defined(witRebuild):
  static: echo "Rebuilding plugin_api.wit"
  importWit "../scripting":
    world = "plugin"
    cacheFile = "plugin_api_guest.nim"
else:
  static: echo "Using cached plugin_api.wit (plugin_api_guest.nim)"
  include plugin_api_guest

proc emscripten_notify_memory_growth*(a: int32) {.exportc.} =
  echo "emscripten_notify_memory_growth"

proc emscripten_stack_init() {.importc.}

proc NimMain() {.importc.}

proc handleViewRender(view: View): void {.cdecl.}

# proc addCallback(a: proc(x: int): int) {.importc.}

echo "global stuff"
var views: seq[View] = @[]

proc handleModeChanged(fun: uint32, old: WitString; new: WitString) =
  echo &"[guest] handleModeChanged {old} -> {new}"
  let fun = cast[proc(old: WitString, new: WitString) {.cdecl.}](fun)
  fun(old, new)

proc handleModeChanged(fun: uint32) =
  echo "[guest] handleModeChanged"
  let fun = cast[proc(old: WitString, new: WitString) {.cdecl.}](fun)
  fun(ws"uiae", ws"xvlc")

proc addModeChangedHandler(fun: proc(old: WitString, new: WitString) {.cdecl.}) =
  discard addModeChangedHandler(cast[uint32](fun))

proc initPlugin() =
  emscripten_stack_init()
  NimMain()

  echo "[guest] initPlugin"

  let view = create()
  view.setRenderCallback(cast[uint32](handleViewRender), 123)
  view.setRenderInterval(500)
  views.add(view)

  addModeChangedHandler proc(old: WitString, new: WitString) {.cdecl.} =
    echo &"[guest] mode changed handler {old} -> {new}"

  # echo "[guest] addCallback"
  # addCallback proc(x: int): int =
  #   echo "[guest] inside callback 1"
  #   return x + 1

  # addCallback proc(x: int): int =
  #   echo "[guest] inside callback 2"
  #   return x + 2

  echo getSelection()

  let r = newRope(ws"hello, what is going on today?")
  echo r.slice(4, 14).debug()
  echo r.slice(4, 14).text()

  let r2 = getCurrentEditorRope()
  let s = getSelection()
  echo r2.slice(s.first.column, s.last.column).debug()
  echo r2.slice(s.first.column, s.last.column).text()

  bindKeys(ws"editor.text", ws"", ws"<C-a>", ws"uiaeuiae", ws"1", ws"MOVE THE CURSOR", (ws"comp_test.nim", 0.int32, 0.int32))

proc stackWitString*(arr: openArray[char]): WitString =
  if arr.len == 0:
    return WitString()
  let p = cast[ptr UncheckedArray[char]](stackAlloc(arr.len, 1))
  for i in 0..<arr.len:
    p[i] = arr[i]
  result = ws(p, arr.len)

proc stackWitString*(str: string): WitString =
  stackWitString(str.toOpenArray(0, str.high))

proc stackWitList*[T](arr: openArray[T]): WitList[T] =
  if arr.len == 0:
    return WitList[T]()
  let p = cast[ptr UncheckedArray[T]](stackAlloc(sizeof(T) * arr.len, sizeof(T)))
  for i in 0..<arr.len:
    p[i] = arr[i]
  result = wl[T](p, arr.len)

var renderCommandEncoder: BinaryEncoder

proc handleViewRenderCallback(id: int32; fun: uint32; data: uint32): void =
  # echo &"[guest] handleViewRenderCallback {id}, {fun}, {data}"
  let fun = cast[proc(view: View) {.cdecl.}](fun)
  fun(views[0])

proc getSetting(name: string, T: typedesc): T =
  try:
    return getSettingRaw(name).parseJson().jsonTo(T)
  except:
    return T.default

proc getSetting[T](name: string, def: T): T =
  try:
    return ($getSettingRaw(ws(name))).parseJson().jsonTo(T)
  except:
    return def

var num = 1
proc handleViewRender(view: View): void {.cdecl.} =
  # echo &"[guest] handleViewRender"

  try:
    let version = apiVersion()
    let target = getSetting("test.num-squares", 50)
    inc num
    if num > target:
      num = 1

    # num = target

    let size = view.size
    # echo &"[guest] size: {size}"

    const s = 20.0
    renderCommandEncoder.buffer.setLen(0)
    buildCommands(renderCommandEncoder):
      for y in 0..<num:
        for x in 0..<num:
          fillRect(rect(x.float * s, y.float * s, s, s), color(x.float / num.float, y.float / num.float, 0, 1))

      drawText("version " & $version, rect(100, 100, 0, 0), color(0.5, 0.5, 1, 1), 0.UINodeFlags)

    # view.setRenderCommandsRaw(cast[uint32](renderCommandEncoder.buffer[0].addr), renderCommandEncoder.buffer.len.uint32)
    view.setRenderCommands(@@(renderCommandEncoder.buffer.toOpenArray(0, renderCommandEncoder.buffer.high)))

    let interval = getSetting("test.render-interval", 500)
    view.setRenderInterval(interval)
  except Exception as e:
    echo &"[guest] Failed to render: {e.msg}\n{e.getStackTrace()}"

proc handleCommand(name: WitString; arg: WitString): WitString =
  echo "[guest] handleCommand ", name, ", ", arg

  case $name:
  of "uiaeuiae":
    runCommand(ws"next-view", ws"")

  # of "render":
  #   submitRenderCommands(1, 0, 123)

  else:
    discard

  return stackWitString ($name & "-" & $arg)
