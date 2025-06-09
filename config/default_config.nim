import plugin_runtime
import std/[json]
import misc/[timer]

embedSource()

proc exploreRoot*() {.expose("explore-root").} =
  ## Open file explorer in the root of the VFS
  exploreFiles("")

proc exploreWorkspace*(index: int = 0) {.expose("explore-workspace").} =
  ## Open file explorer in the root of the first (nth) workspace (ws<index>://)
  exploreFiles(&"ws{index}://")

proc exploreUserConfig*() {.expose("explore-user-config").} =
  ## Open file explorer in the user config directory (home://.nev)
  exploreFiles("home://.nev")

proc exploreAppConfig*() {.expose("explore-app-config").} =
  ## Open file explorer in the app config directory (app://config)
  exploreFiles("app://config")

proc exploreWorkspaceConfig*() {.expose("explore-workspace-config").} =
  ## Open file explorer in the workspace config directory (ws0://.nev)
  exploreFiles("ws0://.nev")

proc exploreHelp*() {.expose("explore-help").} =
  ## Open file explorer in the documentation directory (app://docs)
  exploreFiles("app://docs")

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

  addCommand "editor", "<LEADER>ot", "toggle-flag", "editor.log-frame-time"
  addCommand "editor", "<LEADER>ol", "toggle-flag", "logging"
  addCommand "editor", "<LEADER>os", "toggle-flag", "render-selected-value"
  addCommand "editor", "<LEADER>or", "toggle-flag", "log-render-duration"
  addCommand "editor", "<LEADER>od", "toggle-flag", "render-debug-info"
  addCommand "editor", "<LEADER>oo", "toggle-flag", "render-execution-output"
  addCommand "editor", "<LEADER>og", "toggle-flag", "text.print-scopes"
  addCommand "editor", "<LEADER>om", "toggle-flag", "text.print-matches"
  addCommand "editor", "<LEADER>oh", "toggle-flag", "text.show-node-highlight"
  addCommand "editor", "<LEADER>ok", "toggle-flag", "ui.which-key-no-progress"
  addCommandBlockDesc "editor", "<C-5>", "":
    setOption("text.node-highlight-parent-index", clamp(getOption[int]("text.node-highlight-parent-index") - 1, 0, 100000))
    echo "text.node-highlight-parent-index: ", getOption[int]("text.node-highlight-parent-index")
  addCommandBlockDesc "editor", "<C-6>", "":
    setOption("text.node-highlight-parent-index", clamp(getOption[int]("text.node-highlight-parent-index") + 1, 0, 100000))
    echo "text.node-highlight-parent-index: ", getOption[int]("text.node-highlight-parent-index")
  addCommandBlockDesc "editor", "<C-2>", "":
    setOption("text.node-highlight-sibling-index", clamp(getOption[int]("text.node-highlight-sibling-index") - 1, -100000, 100000))
    echo "text.node-highlight-sibling-index: ", getOption[int]("text.node-highlight-sibling-index")
  addCommandBlockDesc "editor", "<C-3>", "":
    setOption("text.node-highlight-sibling-index", clamp(getOption[int]("text.node-highlight-sibling-index") + 1, -100000, 100000))

  # addCommand "editor", "<S-SPACE><*-l>", ""
  # addCommand "editor", "<LEADER>ff", "log-options"
  addCommand "editor", "<ESCAPE>", "escape"

  # Window stuff <LEADER>w
  withKeys "<LEADER>w", "<C-w>":
    addCommand "editor", "<*-f>-", "change-font-size", -1
    addCommand "editor", "<*-f>+", "change-font-size", 1
    addCommand "editor", "b", "toggle-status-bar-location"
    addCommand "editor", "1", "set-layout", "horizontal"
    addCommand "editor", "2", "set-layout", "vertical"
    addCommand "editor", "3", "set-layout", "fibonacci"
    addCommand "editor", "v", "create-view"
    addCommand "editor", "x", "close-current-view", keepHidden=true
    addCommand "editor", "h", "prev-view"
    addCommand "editor", "l", "next-view"
    addCommand "editor", "N", "move-current-view-prev"
    addCommand "editor", "H", "move-current-view-prev"
    addCommand "editor", "T", "move-current-view-next"
    addCommand "editor", "L", "move-current-view-next"
    addCommand "editor", "r", "move-current-view-to-top"
    addCommand "editor", "z", "open-previous-editor"
    addCommand "editor", "y", "open-next-editor"
    addCommand "editor", "s", "split-view"

  if getBackend() != Terminal:
    addCommand "editor", "<CA-v>", "create-view"
    addCommand "editor", "<CA-x>", "close-current-view", true
    addCommand "editor", "<CA-X>", "close-current-view", false
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
  addCommand "editor", "<LEADER>gf", "choose-file"
  addCommand "editor", "<LEADER>go", "choose-open"
  addCommand "editor", "<LEADER>gd", "choose-open-document"
  addCommand "editor", "<LEADER>gl", "choose-location"
  addCommand "editor", "<LEADER>gg", "choose-git-active-files", false
  addCommand "editor", "<LEADER>GG", "choose-git-active-files", true

  addCommand "editor", "<LEADER>ge", "explore-root"
  addCommand "editor", "<LEADER>gv", "explore-files", "", showVFS=true
  addCommand "editor", "<LEADER>gw", "explore-workspace"
  addCommand "editor", "<LEADER>gW", "explore-files", "ws0://".normalizePath
  addCommand "editor", "<LEADER>gu", "explore-user-config"
  addCommand "editor", "<LEADER>ga", "explore-app-config"
  addCommand "editor", "<LEADER>gh", "explore-help"

  addCommand "editor", "<LEADER>gp", "explore-current-file-directory"
  addCommand "editor", "<LEADER>gs", "search-global-interactive"
  addCommand "editor", "<LEADER>gk", "browse-keybinds"
  addCommand "editor", "<LEADER>gi", "browse-settings"
  addCommand "editor", "<LEADER>gn", "open-last-editor"
  addCommandBlockDesc "editor", "<LEADER>log", "Show log file":
    logs(scrollToBottom = true)
    nextView()

  addCommand "editor", "<LEADER>fl", "load-file"
  addCommand "editor", "<LEADER>fs", "write-file"

  addCommand "command-line-low", "<ESCAPE>", "exit-command-line"
  addCommand "command-line-low", "<ENTER>", "execute-command-line"
  addCommand "command-line-low", "<UP>", "select-previous-command-in-history"
  addCommand "command-line-low", "<DOWN>", "select-next-command-in-history"
  addCommand "command-line-results-low", "<ESCAPE>", "exit-command-line"

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
  addCommand "popup.selector", "<C-b>", "toggle-preview"
  addCommand "popup.selector", "<TAB>", "toggle-focus-preview"
  addCommand "popup.selector", "<C-k>s", "sort", "Toggle"
  addCommand "popup.selector", "<C-k>n", "normalize-scores", "Toggle"
  addCommand "popup.selector", "<C-k>f", "set-min-score", 0.0
  addCommand "popup.selector", "<C-k>F", "set-min-score", -1.0
  addCommand "popup.selector", "<C-k>+", "set-min-score", 0.2, add = true
  addCommand "popup.selector", "<C-k>-", "set-min-score", -0.2, add = true
  addCommand "popup.selector.preview", "<TAB>", "toggle-focus-preview"
  addCommandBlockDesc "popup.selector", "<C-l>", "Save location list":
    setLocationListFromCurrentPopup()

  addCommand "editor", "<C-n>", "goto-prev-location"
  addCommand "editor", "<C-t>", "goto-next-location"

  addCommand "popup.selector.open", "<C-x>", "close-selected"

  addCommand "popup.selector.git", "<C-a>", "stage-selected"
  addCommand "popup.selector.git", "<C-u>", "unstage-selected"
  addCommand "popup.selector.git", "<C-q>a", "revert-selected"

  addCommand "popup.selector.git", "<C-h>", "prev-change"
  addCommand "popup.selector.git", "<C-f>", "next-change"
  addCommand "popup.selector.git", "<C-s>", "stage-change"
  addCommand "popup.selector.git", "<C-q>h", "revert-change"
  addCommandDescription "popup.selector", "<C-k>", "Scoring"
  addCommandDescription "popup.selector.git", "<C-q>", "Revert"

  addCommand "popup.selector.file-explorer", "<C-UP>", "go-up"
  addCommand "popup.selector.file-explorer", "<C-r>", "go-up"
  addCommand "popup.selector.file-explorer", "<CS-y>", "enter-normalized"
  addCommand "popup.selector.file-explorer", "<C-a>", "add-workspace-folder"
  addCommand "popup.selector.file-explorer", "<C-x>", "remove-workspace-folder"
  addCommand "popup.selector.file-explorer", "<C-f>", "create-file"
  addCommand "popup.selector.file-explorer", "<C-g>f", "create-file"
  addCommand "popup.selector.file-explorer", "<C-g>d", "create-directory"
  addCommand "popup.selector.file-explorer", "<C-g>x", "delete-file-or-dir"
  addCommand "popup.selector.file-explorer", "<C-u>", "refresh"
  addCommandDescription "popup.selector.file-explorer", "<C-g>", "File operations"

  addCommand "popup.selector.settings", "<C-t>", "toggle-flag"
  addCommand "popup.selector.settings", "<C-s>", "update-setting"

  addCommandBlockDesc "editor", "<LEADER>al", "Run last configuration":
    runLastConfiguration()
    showDebuggerView()

  addCommandBlockDesc "editor", "<LEADER>av", "Choose run configuration":
    chooseRunConfiguration()
    showDebuggerView()

  addCommandBlockDesc "editor", "<LEADER>ab", "Toggle breakpoint":
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

  addCommandDescription "editor", "<LEADER>g", "Global pickers"
  addCommandDescription "editor.text", "<LEADER>g", "Document pickers"
  addCommandDescription "editor", "<LEADER>a", "Debugger"
  addCommandDescription "editor", "<LEADER>a", "Debugger"
  addCommandDescription "editor", "<LEADER>o", "Options"
  addCommandDescription "editor", "<LEADER>ff", "Rendering"
  addCommandDescription "editor", "<LEADER>w", "Window"
  addCommandDescription "editor", "<LEADER>wf", "Change font size"
  addCommandDescription "editor", "<LEADER>wk", "Split size ratio"
  addCommandDescription "editor", "<LEADER>r", "Run"
  addCommandDescription "editor", "<LEADER>f", "File"
  addCommandDescription "editor", "<LEADER>m", "Toggle fullscreen"

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

proc exampleScriptAction*(a: int, b: string): string {.expose("example-script-action").} =
  ## Test documentation stuff
  infof "exampleScriptAction called with {a}, {b}"
  return b & $a

