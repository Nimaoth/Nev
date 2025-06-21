import plugin_runtime
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  return true

import keybindings_vim
import keybindings_normal

when defined(wasm):
  include plugin_runtime_impl
