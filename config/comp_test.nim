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
