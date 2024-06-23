import absytree_runtime
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize"
  return true

import default_config

import keybindings_vim
import keybindings_vim_like
import keybindings_helix
import keybindings_normal
import languages

if getBackend() == Terminal:
  # Disable animations in terminal because they don't look great
  changeAnimationSpeed 10000

when defined(wasm):
  include absytree_runtime_impl
