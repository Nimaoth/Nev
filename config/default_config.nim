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

  addCommandDescription "popup.selector.file-explorer", "<C-g>", "File operations"
  addCommandDescription "popup.selector", "<C-k>", "Scoring"
  addCommandDescription "popup.selector.git", "<C-q>", "Revert"

  # debugger stuff
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

proc exampleScriptAction*(a: int, b: string): string {.expose("example-script-action").} =
  ## Test documentation stuff
  infof "exampleScriptAction called with {a}, {b}"
  return b & $a

