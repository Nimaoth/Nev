import absytree_runtime
import std/[strutils, sugar, sequtils, macros]

import keybindings_vim
import keybindings_helix
import keybindings_normal

proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} =
  infof "handleAction: {action}, {args}"

  case action
  of "set-max-loop-iterations":
    setOption("ast.max-loop-iterations", args[0].getInt)
    return true

  of "command-line":
    let str = if args.len > 0: args[0].getStr else: ""
    commandLine(str)
    if getActiveEditor().isTextEditor(editor):
      editor.setMode "insert"
    return true

  of "set-search-query":
    if getActiveEditor().isTextEditor(editor):
      editor.setSearchQuery args[0].getStr
    return true

  of "do-nothing":
    echo "do nothing"
    return true

  else: return false

proc handlePopupAction*(popup: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
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
  # infof "handleDocumentEditorAction: {action}, {args}"
  return false

proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  # infof "handleTextEditorAction: {action}, {args}"

  case action
  else: return false

proc handleModelEditorAction*(editor: ModelDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  # infof "handleModelEditorAction: {action}, {args}"

  case action
  else: return false

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize"
  return true

import default_config

loadDefaultOptions()
loadDefaultKeybindings()
loadVimKeybindings()
