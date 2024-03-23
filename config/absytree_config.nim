import absytree_runtime
import std/[strutils]

proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} =
  when not defined(wasm):
    return false

  # infof "handleAction: {action}, {args}"

  case action
  of "set-max-loop-iterations":
    setOption("ast.max-loop-iterations", args[0].getInt)
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
  when not defined(wasm):
    return false

  # infof "handleDocumentEditorAction: {action}, {args}"
  return false

proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  when not defined(wasm):
    return false

  # infof "handleTextEditorAction: {action}, {args}"

  case action
  else: return false

proc handleModelEditorAction*(editor: ModelDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  when not defined(wasm):
    return false

  # infof "handleModelEditorAction: {action}, {args}"

  case action
  else: return false

proc postInitialize*(): bool {.wasmexport.} =
  infof "post initialize"
  return true

import default_config

when defined(wasm):
  import keybindings_vim
  import keybindings_vim_like
  import keybindings_helix
  import keybindings_normal
  import languages

  loadDefaultOptions()
  loadDefaultKeybindings(true)
  loadModelKeybindings()
  loadVimKeybindings()
  # loadVimLikeKeybindings()

  loadLspConfigFromFile("config/lsp.json")
  loadSnippetsFromFile(".vscode/nim-snippets.code-snippets", "nim")

  # Triple click to selects a line
  setOption "editor.text.triple-click-command", "extend-select-move"
  setOption "editor.text.triple-click-command-args", %[%"line", %true]

  setOption "editor.text.whitespace.char", "·"
  # setOption "editor.text.whitespace.char", " "

  # Triple click selects a vim paragraph
  # setOption "editor.text.triple-click-command", "extend-select-move"
  # setOption "editor.text.triple-click-command-args", %[%"vim-paragraph-inner", %true]
