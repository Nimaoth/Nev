import std/[macros, options, unicode]
import results

import wit_guest

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../scripting/plugin_api.wit", "plugin_api_guest.nim"
else:
  static: hint("Using cached plugin_api.wit (plugin_api_guest.nim)")
  include plugin_api_guest

proc emscripten_notify_memory_growth*(a: int32) {.exportc.} =
  discard

echo "global stuff"

proc NimMain() {.importc.}
proc emscripten_stack_init() {.importc.}

proc plugin_main*() =
  emscripten_stack_init()
  NimMain()

proc initPlugin() =
  plugin_main()
  echo "[guest] initPlugin"
  echo getSelection()
