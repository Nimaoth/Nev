import absytree_runtime
import std/[json]
import misc/[timer]

proc loadDefaultKeybindings*(clearExisting: bool = false) {.expose("load-default-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadDefaultKeybindings: {t.elapsed.ms} ms"

  info "Applying default keybindings"

  if clearExisting:
    clearCommands "editor"
    clearCommands "editor.model.completion"
    clearCommands "editor.model.goto"
    clearCommands "command-line-low"
    clearCommands "command-line-high"
    clearCommands "popup.selector"

  setLeaders @["<SPACE>", "<C-b>"]

  addCommand "editor", "<C-x><C-x>", "quit"
  addCommand "editor", "<CAS-r>", "reload-plugin"

  addCommand "editor", "<LEADER><*-T>1", "load-theme", "synthwave-color-theme"
  addCommand "editor", "<LEADER><*-T>2", "load-theme", "tokyo-night-storm-color-theme"

  addCommand "editor", "<LEADER>ft", "toggle-flag", "editor.log-frame-time"
  # addCommand "editor", "<C-SPACE>pp", proc() =
    # toggleFlag "editor.poll"
    # echo "-> ", getFlag("editor.poll")
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
    addCommand "editor", "x", "close-current-view", keepHidden=true, restoreHidden=false
    addCommand "editor", "X", "close-current-view", keepHidden=false, restoreHidden=true
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
  addCommand "editor", "<LEADER>gd", "choose-open-document"
  addCommand "editor", "<LEADER>gl", "choose-location", "new"
  addCommand "editor", "<LEADER>gg", "choose-git-active-files", false
  addCommand "editor", "<LEADER>GG", "choose-git-active-files", true
  addCommand "editor", "<LEADER>ge", "explore-files"
  addCommand "editor", "<LEADER>gw", "explore-workspace-primary"
  addCommand "editor", "<LEADER>gu", "explore-user-config-dir"
  addCommand "editor", "<LEADER>ga", "explore-app-config-dir"
  addCommand "editor", "<LEADER>gs", "search-global-interactive"
  addCommandBlock "editor", "<LEADER>log":
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

  addCommand "editor", "<LEADER>lf", "load-file"
  addCommand "editor", "<LEADER>sf", "write-file"
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
  addCommand "popup.selector", "<C-u>", "prev", 5
  addCommand "popup.selector", "<C-d>", "next", 5
  addCommand "popup.selector", "<TAB>", "toggle-focus-preview"
  addCommand "popup.selector.preview", "<TAB>", "toggle-focus-preview"
  addCommandBlock "popup.selector", "<C-l>":
    setLocationListFromCurrentPopup()

  addCommand "editor", "<C-n>", "goto-prev-location"
  addCommand "editor", "<C-t>", "goto-next-location"

  addCommand "popup.selector.open", "<C-x>", "close-selected"

  addCommand "popup.selector.git", "<C-a>", "stage-selected"
  addCommand "popup.selector.git", "<C-u>", "unstage-selected"
  addCommand "popup.selector.git", "<C-r>", "revert-selected"
  addCommand "popup.selector.file-explorer", "<C-UP>", "go-up"
  addCommand "popup.selector.file-explorer", "<C-r>", "go-up"

  addCommandBlock "editor", "<LEADER>al":
    runLastConfiguration()
    showDebuggerView()

  addCommandBlock "editor", "<LEADER>av":
    chooseRunConfiguration()
    showDebuggerView()

  addCommandBlock "editor", "<LEADER>ab":
    if getActiveEditor().isTextEditor editor:
      addBreakpoint(editor.id, editor.selection.last.line)

  addCommand "editor", "<LEADER>ac", "continue-execution"
  addCommand "editor", "<LEADER>ar", "step-over"
  addCommand "editor", "<LEADER>at", "step-in"
  addCommand "editor", "<LEADER>an", "step-out"
  addCommand "editor", "<LEADER>ae", "edit-breakpoints"
  addCommand "editor", "<LEADER>am", "toggle-breakpoints-enabled"

  addCommand "popup.selector.breakpoints", "<C-x>", "delete-breakpoint"
  addCommand "popup.selector.breakpoints", "<C-e>", "toggle-breakpoint-enabled"
  addCommand "popup.selector.breakpoints", "<C-o>", "toggle-all-breakpoints-enabled"

  addCommand "editor", "<LEADER>gb", "show-debugger-view"

  addCommand "debugger", "<C-k>", "prev-debugger-view"
  addCommand "debugger", "<C-h>", "next-debugger-view"

  addCommand "debugger.variables", "<UP>", "prev-variable"
  addCommand "debugger.variables", "<C-p>", "prev-variable"
  addCommand "debugger.variables", "<DOWN>", "next-variable"
  addCommand "debugger.variables", "<C-n>", "next-variable"
  addCommand "debugger.variables", "<RIGHT>", "expand-variable"
  addCommand "debugger.variables", "<C-y>", "expand-variable"
  addCommand "debugger.variables", "<LEFT>", "collapse-variable"
  addCommand "debugger.variables", "<HOME>", "select-first-variable"
  addCommand "debugger.variables", "<END>", "select-last-variable"

  addCommand "debugger.threads", "<UP>", "prev-thread"
  addCommand "debugger.threads", "<C-p>", "prev-thread"
  addCommand "debugger.threads", "<DOWN>", "next-thread"
  addCommand "debugger.threads", "<C-n>", "next-thread"
  addCommand "debugger.threads", "<C-y>", "set-debugger-view", "StackTrace"

  addCommand "debugger.stacktrace", "<UP>", "prev-stack-frame"
  addCommand "debugger.stacktrace", "<C-p>", "prev-stack-frame"
  addCommand "debugger.stacktrace", "<DOWN>", "next-stack-frame"
  addCommand "debugger.stacktrace", "<C-n>", "next-stack-frame"
  addCommand "debugger.stacktrace", "<ENTER>", "open-file-for-current-frame"
  addCommand "debugger.stacktrace", "<C-y>", "open-file-for-current-frame"

  addCommandBlock "debugger", "<C-u>":
    for i in 0..10:
      prevVariable()

  addCommandBlock "debugger", "<C-d>":
    for i in 0..10:
      nextVariable()

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

