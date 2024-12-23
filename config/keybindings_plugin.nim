import plugin_runtime
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize"
  return true

import default_config

import keybindings_normal
import keybindings_vim
import keybindings_helix

proc loadConfiguredKeybindings*() {.expose("load-configured-keybindings").} =
  let keybindings = getOption("keybindings.preset", "")
  let reapplyApp = getOption("keybindings.reapply-app", false)
  let reapplyHome = getOption("keybindings.reapply-home", true)
  let reapplyWorkspace = getOption("keybindings.reapply-workspace", true)
  infof"loadConfiguredKeybindings {keybindings}"
  case keybindings
  of "vim":
    loadDefaultKeybindings(true)
    loadVimKeybindings()
  of "helix":
    loadDefaultKeybindings(true)
    loadHelixKeybindings()
  of "vscode":
    loadDefaultKeybindings(true)
    loadVSCodeKeybindings()

  when enableAst:
    loadModelKeybindings()

  reapplyConfigKeybindings(reapplyApp, reapplyHome, reapplyWorkspace)

if getBackend() == Terminal:
  # Disable animations in terminal because they don't look great
  changeAnimationSpeed 10000

when defined(wasm):
  include plugin_runtime_impl
