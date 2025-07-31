import std/[strformat]
import wit_guest

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

proc addCallback(a: proc(x: int): int) {.importc.}

echo "global stuff"

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

  addModeChangedHandler proc(old: WitString, new: WitString) {.cdecl.} =
    echo &"[guest] mode changed handler {old} -> {new}"

  echo "[guest] addCallback"
  addCallback proc(x: int): int =
    echo "[guest] inside callback 1"
    return x + 1

  addCallback proc(x: int): int =
    echo "[guest] inside callback 2"
    return x + 2

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

proc handleCommand(name: WitString; arg: WitString): WitString =
  echo "handleCommand ", name, ", ", arg

  case $name:
  of "uiaeuiae":
    runCommand(ws"next-view", ws"")

  else:
    discard

  return stackWitString ($name & " " & $arg)
