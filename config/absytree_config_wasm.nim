import absytree_runtime
import std/[strutils, sugar, sequtils, macros]

import keybindings_vim
import keybindings_helix
import keybindings_normal

when defined(wasm):
  const env = "wasm"
else:
  const env = "nims"

proc handleAction*(action: string, args: JsonNode): bool {.wasmexport.} =
  # infof "{env}:handleAction: {action}, {args}"

  case action
  of "set-max-loop-iterations":
    setOption("ast.max-loop-iterations", args[0].getInt)

  of "command-line":
    let str = if args.len > 0: args[0].getStr else: ""
    commandLine(str)
    if getActiveEditor().isTextEditor(editor):
      editor.setMode "insert"

  of "set-search-query":
    if getActiveEditor().isTextEditor(editor):
      editor.setSearchQuery args[0].getStr

  else: return false

proc handlePopupAction*(popup: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
  infof "{env}:handlePopupAction: {action}, {args}"

  case action:
  of "home":
    for i in 0..<3:
      popup.runAction "prev"
  of "end":
    for i in 0..<3:
      popup.runAction "next"

  else: return false

proc handleDocumentEditorAction*(id: EditorId, action: string, args: JsonNode): bool {.wasmexport.} =
  # infof "{env}:handleDocumentEditorAction: {action}, {args}"
  return false

proc handleTextEditorAction*(editor: TextDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  # infof "{env}:handleTextEditorAction: {action}, {args}"

  case action
  else: return false

proc handleAstEditorAction*(editor: AstDocumentEditor, action: string, args: JsonNode): bool {.wasmexport.} =
  # infof "{env}:handleAstEditorAction: {action}, {args}"

  case action
  else: return false

proc postInitialize*(): bool {.wasmexport.} =
  infof "{env}: post initialize"

  # openFile "temp/test.rs"
  # openFile "temp/rust-test/src/main.rs"
  # openFile "temp/test.nim"
  # openFile "a.ast"
  # openFile "temp/test.zig"
  # openFile "src/absytree.nim"
  setLayout "fibonacci"
  changeLayoutProp("main-split", -0.2)
  return true

infof "{env}: Loading absytree_config_wasm.nim"

# openLocalWorkspace(".")
openAbsytreeServerWorkspace("http://localhost:3000")
# openGithubWorkspace("Nimaoth", "AbsytreeBrowser", "main")
# openGithubWorkspace("Nimaoth", "Absytree", "main")

clearCommands "editor"
clearCommands "editor.ast"
clearCommands "editor.ast.completion"
clearCommands "editor.ast.goto"
clearCommands "editor.ast.goto"
clearCommands "commandLine"
clearCommands "popup.selector"

addCommand "editor", "<C-x><C-x>", "quit"
addCommand "editor", "<CAS-r>", "reload-config"

setOption "editor.restore-open-editors", true
setOption "editor.frame-time-smoothing", 0.8

info fmt"Backend: {getBackend()}"
case getBackend()
of Terminal:
  setOption "text.scroll-speed", 1
  setOption "text.cursor-margin", 3
  setOption "ast.scroll-speed", 1
  setOption "ast.indent", 2
  setOption "ast.indent-line-width", 2
  setOption "ast.indent-line-alpha", 0.2
  setOption "ast.inline-blocks", false
  setOption "ast.vertical-division", false
  setOption "model.scroll-speed", 1
of Gui:
  setOption "text.scroll-speed", 23
  setOption "text.cursor-margin", 50
  setOption "ast.scroll-speed", 60
  setOption "ast.indent", 20
  setOption "ast.indent-line-width", 2
  setOption "ast.indent-line-alpha", 1
  setOption "ast.inline-blocks", true
  setOption "ast.vertical-division", true
  setOption "model.scroll-speed", 60
else:
  discard

addCommand "editor", "<S-SPACE><*-a>i", "toggle-flag", "ast.inline-blocks"
addCommand "editor", "<S-SPACE><*-a>d", "toggle-flag", "ast.vertical-division"

setOption "editor.text.lsp.zig.path", "zls"
setOption "editor.text.lsp.rust.path", "C:/Users/nimao/.vscode/extensions/rust-lang.rust-analyzer-0.3.1325-win32-x64/server/rust-analyzer.exe"
setOption "editor.text.treesitter.rust.dll", "D:/dev/Nim/nimtreesitter/treesitter_rust/treesitter_rust/rust.dll"
setOption "editor.text.treesitter.zig.dll", "D:/dev/Nim/nimtreesitter/treesitter_zig/treesitter_zig/zig.dll"
setOption "editor.text.treesitter.javascript.dll", "D:/dev/Nim/nimtreesitter/treesitter_javascript/treesitter_javascript/javascript.dll"
setOption "editor.text.treesitter.nim.dll", "D:/dev/Nim/nimtreesitter/treesitter_nim/treesitter_nim/nim.dll"
setOption "editor.text.treesitter.python.dll", "D:/dev/Nim/nimtreesitter/treesitter_python/treesitter_python/python.dll"

addCommand "editor", "<SPACE>tt", proc() =
  setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") * 2, 1, 1000000))
  echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

addCommand "editor", "<SPACE>tr", proc() =
  setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") div 2, 1, 1000000))
  echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

addCommand "editor", "<C-SPACE>ft", "toggle-flag", "editor.log-frame-time"
# addCommand "editor", "<C-SPACE>pp", proc() =
  # toggleFlag "editor.poll"
  # echo "-> ", getFlag("editor.poll")
addCommand "editor", "<C-SPACE>td", "toggle-flag", "ast.render-vnode-depth"
addCommand "editor", "<C-SPACE>l", "toggle-flag", "logging"
addCommand "editor", "<C-SPACE>fs", "toggle-flag", "render-selected-value"
addCommand "editor", "<C-SPACE>fr", "toggle-flag", "log-render-duration"
addCommand "editor", "<C-SPACE>fd", "toggle-flag", "render-debug-info"
addCommand "editor", "<C-SPACE>fo", "toggle-flag", "render-execution-output"
addCommand "editor", "<C-SPACE>fg", "toggle-flag", "text.print-scopes"
addCommand "editor", "<C-SPACE>fm", "toggle-flag", "text.print-matches"
addCommand "editor", "<C-SPACE>fh", "toggle-flag", "text.show-node-highlight"
addCommand "editor", "<C-5>", proc() =
  setOption("text.node-highlight-parent-index", clamp(getOption[int]("text.node-highlight-parent-index") - 1, 0, 100000))
  echo "text.node-highlight-parent-index: ", getOption[int]("text.node-highlight-parent-index")
addCommand "editor", "<C-6>", proc() =
  setOption("text.node-highlight-parent-index", clamp(getOption[int]("text.node-highlight-parent-index") + 1, 0, 100000))
  echo "text.node-highlight-parent-index: ", getOption[int]("text.node-highlight-parent-index")
addCommand "editor", "<C-2>", proc() =
  setOption("text.node-highlight-sibling-index", clamp(getOption[int]("text.node-highlight-sibling-index") - 1, -100000, 100000))
  echo "text.node-highlight-sibling-index: ", getOption[int]("text.node-highlight-sibling-index")
addCommand "editor", "<C-3>", proc() =
  setOption("text.node-highlight-sibling-index", clamp(getOption[int]("text.node-highlight-sibling-index") + 1, -100000, 100000))

addCommand "editor", "<C-u>", "set-mode", "test-mode"
setConsumeAllInput "editor.test-mode", true
addCommand "editor.test-mode", "<ESCAPE>", "set-mode", ""
addCommand "editor.test-mode", "-","change-font-size", -1
addCommand "editor.test-mode", "+","change-font-size", +1

addCommand "editor", "<C-i>", "set-mode", "test-mode2"
setOption "editor.custom-mode-on-top", false
addCommand "editor.test-mode2", "<ESCAPE>", "set-mode", ""
addCommand "editor.test-mode2", "s","change-font-size", -1
addCommand "editor.test-mode2", "d","change-font-size", +1

# addCommand "editor", "<S-SPACE><*-l>", ""
addCommand "editor", "<S-SPACE>ff", "log-options"
addCommand "editor", "<ESCAPE>", "escape"
addCommand "editor", "<S-SPACE><*-l>-", "change-font-size", -1
addCommand "editor", "<S-SPACE><*-l>+", "change-font-size", 1
# addCommand "editor", "<C-g>", "toggle-status-bar-location"
addCommand "editor", "<S-SPACE>l1", "set-layout", "horizontal"
addCommand "editor", "<S-SPACE>l2", "set-layout", "vertical"
addCommand "editor", "<S-SPACE>l3", "set-layout", "fibonacci"
addCommand "editor", "<CA-h>", "change-layout-prop", "main-split", -0.05
addCommand "editor", "<CA-f>", "change-layout-prop", "main-split", 0.05
addCommand "editor", "<CA-v>", "create-view"
addCommand "editor", "<CA-a>", "create-keybind-autocomplete-view"
addCommand "editor", "<CA-x>", "close-current-view"
addCommand "editor", "<CA-n>", "prev-view"
addCommand "editor", "<CA-t>", "next-view"
addCommand "editor", "<CS-n>", "move-current-view-prev"
addCommand "editor", "<CS-t>", "move-current-view-next"
addCommand "editor", "<CA-r>", "move-current-view-to-top"
addCommand "editor", "<C-s>", "write-file"
addCommand "editor", "<CS-r>", "load-file"
addCommand "editor", "<S-SPACE><S-SPACE>", "command-line"
addCommand "editor", "<S-SPACE>t", "choose-theme"
addCommand "editor", "<S-SPACE>f", "choose-file", "new"
addCommand "editor", "<C-o>", "choose-file", "new"

addCommandBlock "editor", "<S-SPACE>l<*-n>1":
  setOption("editor.text.line-numbers", LineNumbers.None)
  requestRender(true)

addCommandBlock "editor", "<S-SPACE>l<*-n>2":
  setOption("editor.text.line-numbers", LineNumbers.Absolute)
  requestRender(true)

addCommandBlock "editor", "<S-SPACE>l<*-n>3":
  setOption("editor.text.line-numbers", LineNumbers.Relative)
  requestRender(true)

addCommand "editor", "<S-SPACE>kn", () => loadNormalBindings()
addCommand "editor", "<S-SPACE>kv", () => loadVimBindings()
addCommand "editor", "<S-SPACE>kh", () => loadHelixBindings()

addCommand "editor", "<S-SPACE>CC", "clear-workspace-caches"

addCommand "commandLine", "<ESCAPE>", "exit-command-line"
addCommand "commandLine", "<ENTER>", "execute-command-line"

addCommand "popup.selector", "<ENTER>", "accept"
addCommand "popup.selector", "<TAB>", "accept"
addCommand "popup.selector", "<ESCAPE>", "cancel"
addCommand "popup.selector", "<UP>", "prev"
addCommand "popup.selector", "<DOWN>", "next"
addCommand "popup.selector", "<HOME>", "home"
addCommand "popup.selector", "<END>", "end"

# loadHelixBindings()
loadVimBindings()

# addCommand "editor.ast", "<A-LEFT>", "move-cursor", "-1"
addAstCommandBlock "", "<A-LEFT>": editor.moveCursor(-1)
addCommand "editor.ast", "<A-RIGHT>", "move-cursor", 1
addCommand "editor.ast", "<A-UP>", "move-cursor-up"
addCommand "editor.ast", "<A-DOWN>", "move-cursor-down"
addCommand "editor.ast", "<HOME>", "cursor.home"
addCommand "editor.ast", "<END>", "cursor.end"
addCommand "editor.ast", "<UP>", "move-cursor-prev-line"
addCommand "editor.ast", "<DOWN>", "move-cursor-next-line"
addCommand "editor.ast", "<LEFT>", "move-cursor-prev"
addCommand "editor.ast", "<RIGHT>", "move-cursor-next"
addCommand "editor.ast", "n", "move-cursor-prev"
addCommand "editor.ast", "t", "move-cursor-next"
addCommand "editor.ast", "<S-LEFT>", "cursor.left", "last"
addCommand "editor.ast", "<S-RIGHT>", "cursor.right", "last"
addCommand "editor.ast", "<S-UP>", "cursor.up", "last"
addCommand "editor.ast", "<S-DOWN>", "cursor.down", "last"
addCommand "editor.ast", "<S-HOME>", "cursor.home", "last"
addCommand "editor.ast", "<S-END>", "cursor.end", "last"
addCommand "editor.ast", "<BACKSPACE>", "backspace"
addCommand "editor.ast", "<DELETE>", "delete"
addCommand "editor.ast", "<TAB>", "edit-next-empty"
addCommand "editor.ast", "<S-TAB>", "edit-prev-empty"
addCommand "editor.ast", "<A-f>", "select-containing", "function"
addCommand "editor.ast", "<A-c>", "select-containing", "const-decl"
addCommand "editor.ast", "<A-n>", "select-containing", "node-list"
addCommand "editor.ast", "<A-i>", "select-containing", "if"
addCommand "editor.ast", "<A-l>", "select-containing", "line"
addCommand "editor.ast", "e", "rename"
addCommand "editor.ast", "AE", "insert-after", "empty"
addCommand "editor.ast", "AP", "insert-after", "deleted"
addCommand "editor.ast", "ae", "insert-after-smart", "empty"
addCommand "editor.ast", "ap", "insert-after-smart", "deleted"
addCommand "editor.ast", "IE", "insert-before", "empty"
addCommand "editor.ast", "IP", "insert-before", "deleted"
addCommand "editor.ast", "ie", "insert-before-smart", "empty"
addCommand "editor.ast", "ip", "insert-before-smart", "deleted"
addCommand "editor.ast", "ke", "insert-child", "empty"
addCommand "editor.ast", "kp", "insert-child", "deleted"
addCommand "editor.ast", "s", "replace", "empty"
addCommand "editor.ast", "re", "replace", "empty"
addCommand "editor.ast", "rn", "replace", "number-literal"
addCommand "editor.ast", "rf", "replace", "call-func"
addCommand "editor.ast", "rp", "replace", "deleted"
addCommand "editor.ast", "rr", "replace-parent"
addCommand "editor.ast", "gd", "goto", "definition"
addCommand "editor.ast", "gp", "goto", "prev-usage"
addCommand "editor.ast", "gn", "goto", "next-usage"
addCommand "editor.ast", "GE", "goto", "prev-error"
addCommand "editor.ast", "ge", "goto", "next-error"
addCommand "editor.ast", "gs", "goto", "symbol"
addCommand "editor.ast", "<F12>", "goto", "next-error-diagnostic"
addCommand "editor.ast", "<S-F12>", "goto", "prev-error-diagnostic"
addCommand "editor.ast", "R", "run-selected-function"
addCommand "editor.ast", "\"", "replace-empty", "\""
addCommand "editor.ast", "'", "replace-empty", "\""
addCommand "editor.ast", "+", "wrap", "+"
addCommand "editor.ast", "-", "wrap", "-"
addCommand "editor.ast", "*", "wrap", "*"
addCommand "editor.ast", "/", "wrap", "/"
addCommand "editor.ast", "%", "wrap", "%"
addCommand "editor.ast", "(", "wrap", "call-func"
addCommand "editor.ast", ")", "wrap", "call-arg"
addCommand "editor.ast", "{", "wrap", "{"
addCommand "editor.ast", "=<ENTER>", "wrap", "="
addCommand "editor.ast", "==", "wrap", "=="
addCommand "editor.ast", "!=", "wrap", "!="
addCommand "editor.ast", "\\<\\>", "wrap", "<>"
addCommand "editor.ast", "\\<=", "wrap", "<="
addCommand "editor.ast", "\\>=", "wrap", ">="
addCommand "editor.ast", "\\<<ENTER>", "wrap", "<"
addCommand "editor.ast", "\\><ENTER>", "wrap", ">"
addCommand "editor.ast", "<SPACE>and", "wrap", "and"
addCommand "editor.ast", "<SPACE>or", "wrap", "or"
addCommand "editor.ast", "vc", "wrap", "const-decl"
addCommand "editor.ast", "vl", "wrap", "let-decl"
addCommand "editor.ast", "vv", "wrap", "var-decl"
addCommand "editor.ast", "d", "delete-selected"
addCommand "editor.ast", "y", "copy-selected"
addCommand "editor.ast", "u", "undo"
addCommand "editor.ast", "U", "redo"
addCommand "editor.ast", "<C-d>", "scroll", -150
addCommand "editor.ast", "<C-u>", "scroll", 150
addCommand "editor.ast", "<PAGE_DOWN>", "scroll", -450
addCommand "editor.ast", "<PAGE_UP>", "scroll", 450
addCommand "editor.ast", "<C-f>", "select-center-node"
addCommand "editor.ast", "<C-r>", "select-prev"
addCommand "editor.ast", "<C-m>", "select-next"
addCommand "editor.ast", "<C-LEFT>", "select-prev"
addCommand "editor.ast", "<C-RIGHT>", "select-next"
addCommand "editor.ast", "<SPACE>dc", "dump-context"
addCommand "editor.ast", "<CA-DOWN>", "scroll-output", "-5"
addCommand "editor.ast", "<CA-UP>", "scroll-output", "5"
addCommand "editor.ast", "<CA-HOME>", "scroll-output", "home"
addCommand "editor.ast", "<CA-END>", "scroll-output", "end"
addCommand "editor.ast", ".", "run-last-command", "edit"
addCommand "editor.ast", ",", "run-last-command", "move"
addCommand "editor.ast", ";", "run-last-command"
addCommand "editor.ast", "<A-t>", "move-node-to-next-space"
addCommand "editor.ast", "<A-n>", "move-node-to-prev-space"
addCommand "editor.ast", "<C-a>", "set-mode", "uiae"

addCommand "editor.text", "<C-SPACE>ts", "reload-treesitter"

setConsumeAllInput "editor.ast.uiae", true
addCommand "editor.ast.uiae", "<ESCAPE>", "set-mode", ""
addCommand "editor.ast.uiae", "a", "scroll", 50

addCommand "editor.ast.completion", "<ENTER>", "finish-edit", true
addCommand "editor.ast.completion", "<ESCAPE>", "finish-edit", false
addCommand "editor.ast.completion", "<UP>", "select-prev-completion"
addCommand "editor.ast.completion", "<DOWN>", "select-next-completion"
addCommand "editor.ast.completion", "<TAB>", "apply-selected-completion"
addCommand "editor.ast.completion", "<C-TAB>", "cancel-and-next-completion"
addCommand "editor.ast.completion", "<CS-TAB>", "cancel-and-prev-completion"
addCommand "editor.ast.completion", "<A-d>", "cancel-and-delete"
addCommand "editor.ast.completion", "<A-t>", "move-empty-to-next-space"
addCommand "editor.ast.completion", "<A-n>", "move-empty-to-prev-space"

addCommand "editor.ast.goto", "<ENTER>", "accept"
addCommand "editor.ast.goto", "<TAB>", "accept"
addCommand "editor.ast.goto", "<ESCAPE>", "cancel"
addCommand "editor.ast.goto", "<UP>", "prev"
addCommand "editor.ast.goto", "<DOWN>", "next"
addCommand "editor.ast.goto", "<HOME>", "home"
addCommand "editor.ast.goto", "<END>", "end"

setHandleInputs("editor.model", true)
addCommand("editor.model", "<LEFT>", "move-cursor-left-line")
addCommand("editor.model", "<RIGHT>", "move-cursor-right-line")
addCommand("editor.model", "<A-LEFT>", "move-cursor-left")
addCommand("editor.model", "<A-RIGHT>", "move-cursor-right")
addCommand("editor.model", "<UP>", "move-cursor-up")
addCommand("editor.model", "<DOWN>", "move-cursor-down")
addCommand("editor.model", "<A-UP>", "select-node")
addCommand("editor.model", "<C-UP>", "select-parent-cell")
addCommand("editor.model", "<A-DOWN>", "move-cursor-down")
addCommand("editor.model", "<C-LEFT>", "move-cursor-left-cell")
addCommand("editor.model", "<C-RIGHT>", "move-cursor-right-cell")
addCommand("editor.model", "<HOME>", "move-cursor-line-start")
addCommand("editor.model", "<END>", "move-cursor-line-end")
addCommand("editor.model", "<A-HOME>", "move-cursor-line-start-inline")
addCommand("editor.model", "<A-END>", "move-cursor-line-end-inline")

addCommand("editor.model", "<S-LEFT>", "move-cursor-left-line", true)
addCommand("editor.model", "<S-RIGHT>", "move-cursor-right-line", true)
addCommand("editor.model", "<SA-LEFT>", "move-cursor-left", true)
addCommand("editor.model", "<SA-RIGHT>", "move-cursor-right", true)
addCommand("editor.model", "<S-UP>", "move-cursor-up", true)
addCommand("editor.model", "<S-DOWN>", "move-cursor-down", true)
addCommand("editor.model", "<SA-UP>", "move-cursor-up", true)
addCommand("editor.model", "<SA-DOWN>", "move-cursor-down", true)
addCommand("editor.model", "<SC-LEFT>", "move-cursor-left-cell", true)
addCommand("editor.model", "<SC-RIGHT>", "move-cursor-right-cell", true)
addCommand("editor.model", "<S-HOME>", "move-cursor-line-start", true)
addCommand("editor.model", "<S-END>", "move-cursor-line-end", true)
addCommand("editor.model", "<SA-HOME>", "move-cursor-line-start-inline", true)
addCommand("editor.model", "<SA-END>", "move-cursor-line-end-inline", true)

addCommand("editor.model", "<C-y>", "undo")
addCommand("editor.model", "<C-z>", "redo")
addCommand("editor.model", "<BACKSPACE>", "delete-left")
addCommand("editor.model", "<DELETE>", "delete-right")
addCommand("editor.model", "<SPACE>", "insert-text-at-cursor", " ")
addCommand("editor.model", "<ENTER>", "create-new-node")
addCommand("editor.model", "<TAB>", "select-next-placeholder")
addCommand("editor.model", "<S-TAB>", "select-prev-placeholder")

addCommand("editor.model", "<C-SPACE>", "show-completions")

addCommand("editor.model", "<CA-g>", "toggle-use-default-cell-builder")

addCommand("editor.model", "<S-SPACE>R", "run-selected-function")

addCommand("editor.model.completion", "<ENTER>", "finish-edit", true)
addCommand("editor.model.completion", "<ESCAPE>", "hide-completions")
addCommand("editor.model.completion", "<UP>", "select-prev-completion")
addCommand("editor.model.completion", "<DOWN>", "select-next-completion")
addCommand("editor.model.completion", "<C-SPACE>", "move-cursor-start")
addCommand("editor.model.completion", "<TAB>", "apply-selected-completion")

addCommand "editor.model.goto", "<END>", "end"

when defined(wasm):
  include absytree_runtime_impl