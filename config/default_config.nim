import absytree_runtime
import std/[json]
import misc/[timer]

import languages

# Only when compiled to wasm.
# Delete if you want
proc loadDefaultOptions*() =
  infof "Loading default options.nim"

  setOption "editor.restore-open-workspaces", true
  setOption "editor.restore-open-editors", true
  setOption "editor.frame-time-smoothing", 0.8

  setOption "editor.text.auto-start-language-server", true

  info fmt"Backend: {getBackend()}"
  case getBackend()
  of Terminal:
    setOption "text.scroll-speed", 3
    setOption "text.cursor-margin", 0.5
    setOption "text.cursor-margin-relative", true
    setOption "ast.scroll-speed", 1
    setOption "ast.indent", 2
    setOption "ast.indent-line-width", 2
    setOption "ast.indent-line-alpha", 0.2
    setOption "ast.inline-blocks", false
    setOption "ast.vertical-division", false
    setOption "model.scroll-speed", 1

  of Gui:
    setOption "text.scroll-speed", 50
    setOption "text.cursor-margin", 0.5
    setOption "text.cursor-margin-relative", true
    setOption "ast.scroll-speed", 50
    setOption "ast.indent", 20
    setOption "ast.indent-line-width", 2
    setOption "ast.indent-line-alpha", 1
    setOption "ast.inline-blocks", true
    setOption "ast.vertical-division", true
    setOption "model.scroll-speed", 50

  of Browser:
    setOption "text.scroll-speed", 50
    setOption "text.cursor-margin", 0.5
    setOption "text.cursor-margin-relative", true
    setOption "ast.scroll-speed", 50
    setOption "ast.indent", 20
    setOption "ast.indent-line-width", 2
    setOption "ast.indent-line-alpha", 1
    setOption "ast.inline-blocks", true
    setOption "ast.vertical-division", true
    setOption "model.scroll-speed", 50
    addCommand "editor", "<C-r>", "do-nothing"

  loadTheme "tokyo-night-color-theme"

proc loadDefaultKeybindings*(clearExisting: bool = false) =
  let t = startTimer()
  defer:
    infof"loadDefaultKeybindings: {t.elapsed.ms} ms"

  info "Applying default keybindings"

  if clearExisting:
    clearCommands "editor"
    clearCommands "editor.ast"
    clearCommands "editor.ast.completion"
    clearCommands "editor.ast.goto"
    clearCommands "editor.model.completion"
    clearCommands "editor.model.goto"
    clearCommands "command-line-low"
    clearCommands "command-line-high"
    clearCommands "popup.selector"

  setLeaders @["<SPACE>", "<C-b>"]

  addCommand "editor", "<C-x><C-x>", "quit"
  addCommand "editor", "<CAS-r>", "reload-config"

  addCommand "editor", "<LEADER><*-T>1", "load-theme", "synthwave-color-theme"
  addCommand "editor", "<LEADER><*-T>2", "load-theme", "tokyo-night-storm-color-theme"

  addCommand "editor", "<LEADER><*-a>i", "toggle-flag", "ast.inline-blocks"
  addCommand "editor", "<LEADER><*-a>d", "toggle-flag", "ast.vertical-division"

  addCommand "editor", "<LEADER>tt", proc() =
    setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") * 2, 1, 1000000))
    echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

  addCommand "editor", "<LEADER>tr", proc() =
    setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") div 2, 1, 1000000))
    echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

  addCommand "editor", "<LEADER>ft", "toggle-flag", "editor.log-frame-time"
  # addCommand "editor", "<C-SPACE>pp", proc() =
    # toggleFlag "editor.poll"
    # echo "-> ", getFlag("editor.poll")
  addCommand "editor", "<LEADER>ftd", "toggle-flag", "ast.render-vnode-depth"
  addCommand "editor", "<LEADER>fl", "toggle-flag", "logging"
  addCommand "editor", "<LEADER>ffs", "toggle-flag", "render-selected-value"
  addCommand "editor", "<LEADER>ffr", "toggle-flag", "log-render-duration"
  addCommand "editor", "<LEADER>ffd", "toggle-flag", "render-debug-info"
  addCommand "editor", "<LEADER>ffo", "toggle-flag", "render-execution-output"
  addCommand "editor", "<LEADER>ffg", "toggle-flag", "text.print-scopes"
  addCommand "editor", "<LEADER>ffm", "toggle-flag", "text.print-matches"
  addCommand "editor", "<LEADER>ffh", "toggle-flag", "text.show-node-highlight"
  addCommand "editor", "<LEADER>iii", "toggleShowDrawnNodes"
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

  # addCommand "editor", "<S-SPACE><*-l>", ""
  addCommand "editor", "<LEADER>ff", "log-options"
  addCommand "editor", "<ESCAPE>", "escape"

  # Window stuff <LEADER>w
  withKeys "<LEADER>w", "<C-w>":
    addCommand "editor", "<*-F>-", "change-font-size", -1
    addCommand "editor", "<*-F>+", "change-font-size", 1
    addCommand "editor", "<*-A>-", "change-animation-speed", 1 / 1.5
    addCommand "editor", "<*-A>+", "change-animation-speed", 1.5
    addCommand "editor", "b", "toggle-status-bar-location"
    addCommand "editor", "1", "set-layout", "horizontal"
    addCommand "editor", "2", "set-layout", "vertical"
    addCommand "editor", "3", "set-layout", "fibonacci"
    addCommand "editor", "<*-l>n", "change-layout-prop", "main-split", -0.05
    addCommand "editor", "<*-l>t", "change-layout-prop", "main-split", 0.05
    addCommand "editor", "v", "create-view"
    addCommand "editor", "a", "create-keybind-autocomplete-view"
    addCommand "editor", "x", "close-current-view", true
    addCommand "editor", "X", "close-current-view", false
    addCommand "editor", "n", "prev-view"
    addCommand "editor", "t", "next-view"
    addCommand "editor", "N", "move-current-view-prev"
    addCommand "editor", "T", "move-current-view-next"
    addCommand "editor", "r", "move-current-view-to-top"
    addCommand "editor", "h", "open-previous-editor"
    addCommand "editor", "f", "open-next-editor"

  if getBackend() != Terminal:
    addCommand "editor", "<CA-v>", "create-view"
    addCommand "editor", "<CA-a>", "create-keybind-autocomplete-view"
    addCommand "editor", "<CA-x>", "close-current-view", true
    addCommand "editor", "<CA-X>", "close-current-view", false
    addCommand "editor", "<CA-n>", "prev-view"
    addCommand "editor", "<CA-t>", "next-view"
    addCommand "editor", "<CS-n>", "move-current-view-prev"
    addCommand "editor", "<CS-t>", "move-current-view-next"
    addCommand "editor", "<CA-r>", "move-current-view-to-top"
    addCommand "editor", "<CA-h>", "open-previous-editor"
    addCommand "editor", "<CA-f>", "open-next-editor"

  addCommand "editor", "<C-s>", "write-file"
  addCommand "editor", "<CS-r>", "load-file"
  addCommand "editor", "<CS-s>", "save-app-state"
  addCommand "editor", "<LEADER><LEADER>", "command-line"
  addCommand "editor", "<LEADER>gt", "choose-theme"
  addCommand "editor", "<LEADER>gf", "choose-file", "new"
  addCommand "editor", "<LEADER>go", "choose-open", "new"
  addCommand "editor", "<LEADER>gg", "choose-git-active-files", "new"
  addCommand "editor", "<LEADER>ge", "explore-files"
  addCommandBlock "editor", "<LEADER>gl":
    runAction "logs"
    if getActiveEditor().isTextEditor(ed):
      ed.moveLast("file")
    runAction "next-view"

  withKeys "<LEADER>s":
    addCommandBlock "editor", "l<*-n>1":
      setOption("editor.text.line-numbers", LineNumbers.None)
      requestRender(true)

    addCommandBlock "editor", "l<*-n>2":
      setOption("editor.text.line-numbers", LineNumbers.Absolute)
      requestRender(true)

    addCommandBlock "editor", "l<*-n>3":
      setOption("editor.text.line-numbers", LineNumbers.Relative)
      requestRender(true)

    addCommandBlock "editor", "dl": lspLogVerbose(true)
    addCommandBlock "editor", "dL": lspLogVerbose(false)

  addCommand "editor", "<LEADER>rlf", "load-file"
  addCommand "editor", "<LEADER>rwf", "write-file"
  addCommand "editor", "<LEADER>rSS", "write-file", "", true
  addCommand "editor", "<LEADER>rSA", "save-app-state"
  addCommand "editor", "<LEADER>rSC", "remove-from-local-storage"
  addCommand "editor", "<LEADER>rCC", "clear-workspace-caches"
  addCommand "editor", "<LEADER>rCC", "clear-workspace-caches"

  addCommand "command-line-low", "<ESCAPE>", "exit-command-line"
  addCommand "command-line-low", "<ENTER>", "execute-command-line"
  addCommand "command-line-low", "<UP>", "select-previous-command-in-history"
  addCommand "command-line-low", "<DOWN>", "select-next-command-in-history"

  addCommand "popup.selector", "<ENTER>", "accept"
  addCommand "popup.selector", "<C-y>", "accept"
  addCommand "popup.selector", "<TAB>", "accept"
  addCommand "popup.selector", "<ESCAPE>", "cancel"
  addCommand "popup.selector", "<UP>", "prev"
  addCommand "popup.selector", "<C-p>", "prev"
  addCommand "popup.selector", "<DOWN>", "next"
  addCommand "popup.selector", "<C-n>", "next"
  addCommand "popup.selector", "<C-u>", "prev-x"
  addCommand "popup.selector", "<C-d>", "next-x"

  addCommandBlock "popup.selector.open", "<C-x>":
    if getActivePopup().isSelectorPopup(popup):
      let item = popup.getSelectedItem()
      closeEditor(item["path"].getStr)
      popup.updateCompletions()

  addCommand "popup.selector.git", "<C-a>", "stage-selected"
  addCommand "popup.selector.git", "<C-u>", "unstage-selected"
  addCommand "popup.selector.git", "<C-r>", "revert-selected"
  addCommand "popup.selector.file-explorer", "<C-UP>", "go-up"

  # addCommand "editor.text", "<C-SPACE>ts", "reload-treesitter"

  # setHandleInputs("editor.model", true)
  # addCommand("editor.model", "<LEFT>", "move-cursor-left-line")
  # addCommand("editor.model", "<RIGHT>", "move-cursor-right-line")
  # addCommand("editor.model", "<A-LEFT>", "move-cursor-left")
  # addCommand("editor.model", "<A-RIGHT>", "move-cursor-right")
  # addCommand("editor.model", "<UP>", "move-cursor-up")
  # addCommand("editor.model", "<DOWN>", "move-cursor-down")
  # addCommand("editor.model", "<A-UP>", "select-node")
  # addCommand("editor.model", "<A-DOWN>", "move-cursor-down")
  # addCommand("editor.model", "<C-LEFT>", "move-cursor-left-cell")
  # addCommand("editor.model", "<C-RIGHT>", "move-cursor-right-cell")
  # addCommand("editor.model", "<HOME>", "move-cursor-line-start")
  # addCommand("editor.model", "<END>", "move-cursor-line-end")
  # addCommand("editor.model", "<A-HOME>", "move-cursor-line-start-inline")
  # addCommand("editor.model", "<A-END>", "move-cursor-line-end-inline")

  # addCommand("editor.model", "<S-LEFT>", "move-cursor-left-line", true)
  # addCommand("editor.model", "<S-RIGHT>", "move-cursor-right-line", true)
  # addCommand("editor.model", "<SA-LEFT>", "move-cursor-left", true)
  # addCommand("editor.model", "<SA-RIGHT>", "move-cursor-right", true)
  # addCommand("editor.model", "<S-UP>", "move-cursor-up", true)
  # addCommand("editor.model", "<S-DOWN>", "move-cursor-down", true)
  # addCommand("editor.model", "<SA-UP>", "move-cursor-up", true)
  # addCommand("editor.model", "<SA-DOWN>", "move-cursor-down", true)
  # addCommand("editor.model", "<SC-LEFT>", "move-cursor-left-cell", true)
  # addCommand("editor.model", "<SC-RIGHT>", "move-cursor-right-cell", true)
  # addCommand("editor.model", "<S-HOME>", "move-cursor-line-start", true)
  # addCommand("editor.model", "<S-END>", "move-cursor-line-end", true)
  # addCommand("editor.model", "<SA-HOME>", "move-cursor-line-start-inline", true)
  # addCommand("editor.model", "<SA-END>", "move-cursor-line-end-inline", true)

  # addCommand("editor.model", "<C-z>", "undo")
  # addCommand("editor.model", "<C-y>", "redo")
  # addCommand("editor.model", "<BACKSPACE>", "replace-left")
  # addCommand("editor.model", "<DELETE>", "replace-right")
  # addCommand("editor.model", "<SPACE>", "insert-text-at-cursor", " ")
  # addCommand("editor.model", "<ENTER>", "create-new-node")
  # addCommand("editor.model", "<TAB>", "select-next-placeholder")
  # addCommand("editor.model", "<S-TAB>", "select-prev-placeholder")

  # addCommand("editor.model", "<C-SPACE>", "show-completions")

  # addCommand("editor.model", "<LEADER>mr", "run-selected-function")
  # addCommand("editor.model", "<LEADER>md", "toggle-use-default-cell-builder")

  # addCommand("editor.model.completion", "<ENTER>", "finish-edit", true)
  # addCommand("editor.model.completion", "<ESCAPE>", "hide-completions")
  # addCommand("editor.model.completion", "<UP>", "select-prev-completion")
  # addCommand("editor.model.completion", "<DOWN>", "select-next-completion")
  # addCommand("editor.model.completion", "<C-SPACE>", "move-cursor-start")
  # addCommand("editor.model.completion", "<TAB>", "apply-selected-completion")

  # addCommand "editor.model.goto", "<END>", "end"

proc exampleScriptAction*(a: int, b: string): string {.scriptActionWasmNims("example-script-action").} =
  ## Test documentation stuff
  infof "exampleScriptAction called with {a}, {b}"
  return b & $a

