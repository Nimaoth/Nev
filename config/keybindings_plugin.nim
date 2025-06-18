import plugin_runtime
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize"
  return true

import default_config

import keybindings_vim
import keybindings_normal

proc loadConfiguredKeybindings*() {.expose("load-configured-keybindings").} =
  let keybindings = getOption("keybindings.preset", "")
  let reapplyApp = getOption("keybindings.reapply-app", true)
  let reapplyHome = getOption("keybindings.reapply-home", true)
  let reapplyWorkspace = getOption("keybindings.reapply-workspace", true)
  infof"loadConfiguredKeybindings {keybindings}"

  clearCommands "editor"
  clearCommands "editor.text"
  clearCommands "editor.text.completion"
  clearCommands "editor.model.completion"
  clearCommands "editor.model.goto"
  clearCommands "command-line-low"
  clearCommands "command-line-high"
  clearCommands "popup.selector"
  reapplyConfigKeybindings(reapplyApp, false, false, wait = true)

  case keybindings
  of "vim":
    loadVimKeybindings()
  of "vscode":
    loadVSCodeKeybindings()

  when enableAst:
    loadModelKeybindings()

  reapplyConfigKeybindings(false, reapplyHome, reapplyWorkspace)

if getBackend() == Terminal:
  # Disable animations in terminal because they don't look great
  changeAnimationSpeed 10000

when defined(wasm):
  include plugin_runtime_impl
