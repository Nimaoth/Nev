import absytree_runtime
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize"
  return true

import default_config

import keybindings_vim
import keybindings_normal

proc loadConfiguredKeybindings*() {.expose("load-configured-keybindings").} =
  let keybindings = getOption("keybindings", "")
  infof"loadConfiguredKeybindings {keybindings}"
  case keybindings
  of "vim":
    loadDefaultKeybindings(true)
    loadVimKeybindings()
  of "vscode":
    loadDefaultKeybindings(true)
    loadVSCodeKeybindings()

if getBackend() == Terminal:
  # Disable animations in terminal because they don't look great
  changeAnimationSpeed 10000

when defined(wasm):
  include absytree_runtime_impl
