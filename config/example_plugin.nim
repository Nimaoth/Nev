# This needs to imported to access the editor API.
# It can be imported in any file that's part of the plugin, not just the main file like `absytree_runtime_impl`
import absytree_runtime

# You can import the Nim std lib and other libraries, as long as what you import can be compiled to wasm
# and doesn't rely on currently unsupported WASI APIs.
import std/[strutils, unicode]

proc postInitialize*(): bool {.wasmexport.} =
  # Called after all top level code has been executed
  return true

# Check if you're running the terminal/gui/browser with `getBackend()`
if getBackend() == Terminal:
  # Disable animations in terminal because they don't look great
  changeAnimationSpeed 10000

# Change settings with setOption
setOption "editor.text.triple-click-command", "extend-select-move"

# Get settings with getOption
let transparent = getOption[bool]("ui.background.transparent")
infof"transparent: {transparent}"

# Expose functions as commands using the `expose` pragma, so they can be called from other plugins
# or bound to keys
proc customCommand1(arg1: string, arg2: int) {.expose("custom-command-1").} =
  infof"customCommand1: {arg1}, {arg2}"

proc customCommand2(editor: TextDocumentEditor, arg1: string, arg2: int) {.expose("custom-command-2").} =
  infof"customCommand2: {editor}, {arg1}, {arg2}"

# Create keybindings
addCommand "editor", "<C-a>", "custom-command-1", "hello", 13
addCommand "editor.text", "<C-b>", "custom-command-2", "world", 42
addTextCommand "", "<C-c>", "copy" # addTextCommand "xyz" is equivalent to addCommand "editor.text.xyz"

# These handle* functions will be removed in the future. They have to be declared, but don't use them.
# To create custom commands see the function with {.expose.} below
proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handlePopupAction*(popup: EditorId, action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handleDocumentEditorAction*(id: EditorId, action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} = return false
proc handleModelEditorAction*(editor: ModelDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} = return false

# This is required for the main file of the plugin. If you use NimScript this is not required.
when defined(wasm): include absytree_runtime_impl