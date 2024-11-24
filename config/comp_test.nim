import wit_guest

when defined(witRebuild):
  static: echo "Rebuilding plugin_api.wit"
  importWit "../scripting/plugin_api.wit", "plugin_api_guest.nim"
else:
  static: echo "Using cached plugin_api.wit (plugin_api_guest.nim)"
  include plugin_api_guest

proc emscripten_notify_memory_growth*(a: int32) {.exportc.} =
  echo "emscripten_notify_memory_growth"

proc emscripten_stack_init() {.importc.}

proc NimMain() {.importc.}

echo "global stuff"

proc initPlugin() =
  emscripten_stack_init()
  NimMain()

  echo "[guest] initPlugin"
  echo getSelection()

  let r = newRope(ws"hello, what is going on today?")
  echo r.slice(4, 14).debug()
  echo r.slice(4, 14).text()

  let r2 = getCurrentEditorRope()
  let s = getSelection()
  echo r2.slice(s.first.column, s.last.column).debug()
  echo r2.slice(s.first.column, s.last.column).text()

  bindKeys(ws"editor.text", ws"", ws"<C-a>", ws"uiaeuiae", ws"1", ws"MOVE THE CURSOR", (ws"comp_test.nim", 0.int32, 0.int32))

proc handleCommand(name: WitString; arg: WitString): WitString =
  echo "handleCommand ", name, ", ", arg

  case $name:
  of "uiaeuiae":
    runCommand(ws"next-view", ws"")

  else:
    discard

  return ws""
