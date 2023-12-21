import absytree_runtime
import misc/[event, id]

proc setModeChangedHandler*(handler: proc(editor: TextDocumentEditor, oldMode: string, newMode: string)) =
  let modeChangedHandler = getOption("editor.text.mode-changed-handler", "")
  if modeChangedHandler != "":
    onEditorModeChanged.unsubscribe(parseId(modeChangedHandler))
  let id = onEditorModeChanged.subscribe proc(arg: auto) =
    if arg.editor.isTextEditor(editor) and not editor.isRunningSavedCommands:
      handler(editor, arg.oldMode, arg.newMode)
  setOption("editor.text.mode-changed-handler", $id)

proc loadNormalKeybindings*() {.scriptActionWasmNims("load-normal-keybindings").} =
  info "Applying normal keybindings"

  clearCommands("editor.text")
  for id in getAllEditors():
    if id.isTextEditor(editor):
      editor.setMode("")

  setHandleInputs "editor.text", true
  setOption "editor.text.cursor.movement.", "both"
  setOption "editor.text.cursor.wide.", false

  addTextCommand "", "<LEFT>", "move-cursor-column", -1
  addTextCommand "", "<RIGHT>", "move-cursor-column", 1
  addTextCommand "", "<C-d>", "delete-move", "line-next"
  addTextCommand "", "<C-LEFT>", "move-last", "word-line-back"
  addTextCommand "", "<C-RIGHT>", "move-last", "word-line"
  addTextCommand "", "<HOME>", "move-first", "line"
  addTextCommand "", "<END>", "move-last", "line"
  addTextCommand "", "<C-UP>", "scroll-text", 20
  addTextCommand "", "<C-DOWN>", "scroll-text", -20
  addTextCommand "", "<CS-LEFT>", "move-last", "word-line-back", "last"
  addTextCommand "", "<CS-RIGHT>", "move-last", "word-line", "last"
  addTextCommand "", "<UP>", "move-cursor-line", -1
  addTextCommand "", "<DOWN>", "move-cursor-line", 1
  addTextCommand "", "<C-HOME>", "move-first", "file"
  addTextCommand "", "<C-END>", "move-last", "file"
  addTextCommand "", "<CS-HOME>", "move-first", "file", "last"
  addTextCommand "", "<CS-END>", "move-last", "file", "last"
  addTextCommand "", "<S-LEFT>", "move-cursor-column", -1, "last"
  addTextCommand "", "<S-RIGHT>", "move-cursor-column", 1, "last"
  addTextCommand "", "<S-UP>", "move-cursor-line", -1, "last"
  addTextCommand "", "<S-DOWN>", "move-cursor-line", 1, "last"
  addTextCommand "", "<S-HOME>", "move-first", "line", "last"
  addTextCommand "", "<S-END>", "move-last", "line", "last"
  addTextCommand "", "<CA-d>", "duplicate-last-selection"
  addTextCommand "", "<CA-UP>", "add-cursor-above"
  addTextCommand "", "<CA-DOWN>", "add-cursor-below"
  addTextCommand "", "<BACKSPACE>", "delete-left"
  addTextCommand "", "<C-BACKSPACE>", "delete-move", "word-line-back"
  addTextCommand "", "<DELETE>", "delete-right"
  addTextCommand "", "<C-DELETE>", "delete-move", "word-line"
  addTextCommand "", "<ENTER>", "insert-text", "\n"
  addTextCommand "insert", "<SPACE>", "insert-text", " "
  addTextCommand "", "<C-l>", "select-line-current"
  addTextCommand "", "<A-UP>", "select-parent-current-ts"
  addTextCommand "", "<C-r>", "select-prev"
  addTextCommand "", "<C-m>", "select-next"
  addTextCommand "", "<C-t>", "select-next"
  addTextCommand "", "<C-n>", "invert-selection"
  addTextCommand "", "<C-y>", "undo"
  addTextCommand "", "<C-z>", "redo"
  addTextCommand "", "<C-c>", "copy"
  addTextCommand "", "<C-v>", "paste"
  addTextCommand "", "<TAB>", "indent"
  addTextCommand "", "<S-TAB>", "unindent"
  addTextCommand "", "<C-k><C-c>", "toggle-line-comment"
  addTextCommand "", "<C-i>", "center-cursor"
  addTextCommand "", "<C-g>", "enter-choose-cursor-mode", "set-selection"

  addTextCommand "", "<C-e>", "addNextFindResultToSelection"
  addTextCommand "", "<C-E>", "addPrevFindResultToSelection"
  addTextCommand "", "<A-e>", "setAllFindResultToSelection"

  addTextCommand "", "<C-l>", "select-line-current"
  addTextCommand "", "miw", "select-inside-current"

  addTextCommandBlock "", "<C-f>":
    commandLine("set-search-query \\")
    if getActiveEditor().isTextEditor(editor):
      var arr = newJArray()
      arr.add newJString("file")
      discard editor.runAction("move-last", arr)
      editor.setMode("insert")

  addCommand "editor.text", "<C-8>", () => setOption("text.line-distance", getOption[float32]("text.line-distance") - 1)
  addCommand "editor.text", "<C-9>", () => setOption("text.line-distance", getOption[float32]("text.line-distance") + 1)

  addTextCommandBlock "", "<ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection
  addTextCommandBlock "", "<S-ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection

  addCommand "editor.text.completion", "<ESCAPE>", "hide-completions"
  addCommand "editor.text.completion", "<UP>", "select-prev-completion"
  addCommand "editor.text.completion", "<DOWN>", "select-next-completion"
  addCommand "editor.text.completion", "<TAB>", "apply-selected-completion"


  # lsp
  addTextCommand "", "gd", "goto-definition"
  addTextCommand "", "gs", "goto-symbol"
  addTextCommand "", "<C-SPACE>", "get-completions"

  block: # model
    setHandleInputs "editor.model", true
    setOption "editor.model.cursor.wide.", false

    addCommand("editor.model", "<LEFT>", "move-cursor-left-line")
    addCommand("editor.model", "<RIGHT>", "move-cursor-right-line")
    addCommand("editor.model", "<UP>", "move-cursor-up")
    addCommand("editor.model", "<DOWN>", "move-cursor-down")
    addCommand("editor.model", "<A-LEFT>", "select-prev-neighbor")
    addCommand("editor.model", "<A-RIGHT>", "select-next-neighbor")
    addCommand("editor.model", "<SA-LEFT>", "select-prev-neighbor", true)
    addCommand("editor.model", "<SA-RIGHT>", "select-next-neighbor", true)
    addCommand("editor.model", "<A-UP>", "select-node")
    addCommand("editor.model", "<A-DOWN>", "select-prev")
    addCommand("editor.model", "<C-LEFT>", "move-cursor-left-cell")
    addCommand("editor.model", "<C-RIGHT>", "move-cursor-right-cell")
    addCommand("editor.model", "<HOME>", "move-cursor-line-start")
    addCommand("editor.model", "<END>", "move-cursor-line-end")
    addCommand("editor.model", "<A-HOME>", "move-cursor-line-start-inline")
    addCommand("editor.model", "<A-END>", "move-cursor-line-end-inline")
    addCommand("editor.model", "<C-UP>", "scroll-lines", 1)
    addCommand("editor.model", "<C-DOWN>", "scroll-lines", -1)

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

    addCommand("editor.model", "<C-c>", "copy-node")
    addCommand("editor.model", "<C-v>", "paste-node")

    addCommand("editor.model", "<C-i>", "invert-selection")
    addModelCommand "", "<C-r>", "select-prev"
    addModelCommand "", "<C-m>", "select-next"
    addModelCommand "", "<C-t>", "select-next"

    addModelCommand "", "<C-g>g", "find-declaration", false
    addModelCommand "", "<C-g>G", "find-declaration", true

    addModelCommand "", "<*C-g>c", "goto-next-node-of-class", "ConstDecl"
    addModelCommand "", "<*C-g>C", "goto-prev-node-of-class", "ConstDecl"
    addModelCommand "", "<*C-g>l", "goto-next-node-of-class", "LetDecl"
    addModelCommand "", "<*C-g>L", "goto-prev-node-of-class", "LetDecl"
    addModelCommand "", "<*C-g>v", "goto-next-node-of-class", "VarDecl"
    addModelCommand "", "<*C-g>V", "goto-prev-node-of-class", "VarDecl"
    addModelCommand "", "<*C-g>f", "goto-next-node-of-class", "FunctionDefinition"
    addModelCommand "", "<*C-g>F", "goto-prev-node-of-class", "FunctionDefinition"
    addModelCommand "", "<*C-g>p", "goto-next-node-of-class", "ParameterDecl"
    addModelCommand "", "<*C-g>P", "goto-prev-node-of-class", "ParameterDecl"
    addModelCommand "", "<*C-g>i", "goto-next-node-of-class", "ThenCase"
    addModelCommand "", "<*C-g>I", "goto-prev-node-of-class", "ThenCase"
    addModelCommand "", "<*C-g>o", "goto-next-node-of-class", "ForLoop"
    addModelCommand "", "<*C-g>O", "goto-prev-node-of-class", "ForLoop"
    addModelCommand "", "<*C-g>w", "goto-next-node-of-class", "WhileExpression"
    addModelCommand "", "<*C-g>W", "goto-prev-node-of-class", "WhileExpression"
    addModelCommand "", "<*C-g>r", "goto-next-reference"
    addModelCommand "", "<*C-g>R", "goto-prev-reference"
    addModelCommand "", "<*C-g>e", "goto-next-invalid-node"
    addModelCommand "", "<*C-g>E", "goto-prev-invalid-node"

    addCommand "editor.model", "<BACKSPACE>", "replace-left"
    addCommand "editor.model", "<DELETE>", "replace-right"
    addCommand "editor.model", "<C-BACKSPACE>", "delete-left"
    addCommand "editor.model", "<C-DELETE>", "delete-right"
    addCommand "editor.model", "<ENTER>", "create-new-node"
    addCommand "editor.model", "<TAB>", "select-next-placeholder"
    addCommand "editor.model", "<S-TAB>", "select-prev-placeholder"

    addCommand "editor.model", "<C-SPACE>", "show-completions"

    addCommand "editor.model", "<LEADER>mr", "run-selected-function"
    addCommand "editor.model", "<LEADER>md", "toggle-use-default-cell-builder"
    addCommand "editor.model", "<LEADER>mc", "compile-language"

    addCommand "editor.model", "gd", "goto-definition"
    addCommand "editor.model", "gp", "goto-prev-reference"
    addCommand "editor.model", "gn", "goto-next-reference"
    addCommand "editor.model", "tt", "toggle-bool-cell"

    addCommand "editor.model.completion", "<ESCAPE>", "hide-completions"
    addCommand "editor.model.completion", "<UP>", "select-prev-completion"
    addCommand "editor.model.completion", "<DOWN>", "select-next-completion"
    addCommand "editor.model.completion", "<C-SPACE>", "move-cursor-start"
    addCommand "editor.model.completion", "<TAB>", "apply-selected-completion"
    addCommand "editor.model.completion", "<ENTER>", "apply-selected-completion"

    addCommand "editor.model.goto", "<END>", "end"