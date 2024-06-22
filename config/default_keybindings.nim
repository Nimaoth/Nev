import absytree_runtime
import std/[strutils, unicode]

proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} =
  when not defined(wasm):
    return false

  # infof "handleAction: {action}, {args}"

  case action
  of "set-search-query":
    if getActiveEditor().isTextEditor(editor):
      editor.setSearchQuery args[0].getStr
    return true

  of "do-nothing":
    echo "do nothing"
    return true

  else: return false

proc handlePopupAction*(popup: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
  when not defined(wasm):
    return false

  # infof "handlePopupAction: {action}, {args}"

  case action:
  of "prev-x":
    for i in 0..<10:
      popup.runAction "prev"
    return true
  of "next-x":
    for i in 0..<10:
      popup.runAction "next"
    return true

  else: return false

proc handleDocumentEditorAction*(id: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

proc handleModelEditorAction*(editor: ModelDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  return false

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
