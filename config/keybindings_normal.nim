import plugin_runtime
import misc/[event, id, timer]

{.used.}

proc setModeChangedHandler*(handler: proc(editor: TextDocumentEditor, oldMode: string, newMode: string)) =
  let modeChangedHandler = getOption("editor.text.mode-changed-handler", "")
  if modeChangedHandler != "":
    onEditorModeChanged.unsubscribe(parseId(modeChangedHandler))
  let id = onEditorModeChanged.subscribe proc(arg: auto) =
    # infof"onEditorModeChanged: {arg.editor}, {arg.oldMode}, {arg.newMode}"
    if arg.editor.isTextEditor(editor) and not editor.isRunningSavedCommands:
      handler(editor, arg.oldMode, arg.newMode)
  setOption("editor.text.mode-changed-handler", $id)


proc loadStandardKeybindings() =
  addCommand "editor", "<C-s>", "write-file"

  addTextCommand "", "<LEFT>", "move-cursor-column", -1
  addTextCommand "", "<RIGHT>", "move-cursor-column", 1
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
  addTextCommand "", "<C-z>", "undo"
  addTextCommand "", "<C-y>", "redo"
  addTextCommand "", "<C-c>", "copy"
  addTextCommand "", "<C-v>", "paste"
  addTextCommand "", "<BACKSPACE>", "delete-left"
  addTextCommand "", "<C-BACKSPACE>", "delete-move", "word-line-back"
  addTextCommand "", "<DELETE>", "delete-right"
  addTextCommand "", "<C-DELETE>", "delete-move", "word-line"
  addTextCommand "", "<ENTER>", "insert-text", "\n"
  addTextCommand "", "<SPACE>", "insert-text", " "
  addTextCommand "", "<TAB>", "insert-indent"

  addTextCommandBlock "", "<PAGE_UP>": editor.moveCursorLine(-editor.screenLineCount div 2, wrap=false)
  addTextCommandBlock "", "<PAGE_DOWN>": editor.moveCursorLine(editor.screenLineCount div 2, wrap=false)

  addTextCommandBlockDesc "", "<ESCAPE>", "Clear selection and tab stops":
    editor.selection = editor.selection
    editor.clearTabStops()

proc loadStandardSelectorPopupKeybindings() =
  addCommand "popup.selector", "<ENTER>", "accept"
  addCommand "popup.selector", "<C-y>", "accept"
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

  addCommand "popup.selector.open", "<C-x>", "close-selected"

  addCommand "popup.selector.git", "<C-a>", "stage-selected"
  addCommand "popup.selector.git", "<C-u>", "unstage-selected"
  addCommand "popup.selector.git", "<C-r>", "revert-selected"

  addCommand "popup.selector.file-explorer", "<C-UP>", "go-up"
  addCommand "popup.selector.file-explorer", "<C-r>", "go-up"

proc loadModelKeybindings*() {.scriptActionWasmNims("load-model-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadModelKeybindings: {t.elapsed.ms} ms"

  info "Applying model keybindings"

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

  addCommand("editor.model", "<C-z>", "undo")
  addCommand("editor.model", "<C-y>", "redo")

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

proc vscodeSelectLines(editor: TextDocumentEditor, selections: Selections): Selections =
  result = selections.mapIt (if it.isBackwards:
      ((it.first.line, editor.lineLength(it.first.line)), (it.last.line, 0))
    else:
      ((it.first.line, 0), (it.last.line, editor.lineLength(it.last.line))))

proc vscodeExtendForLineDeletion(editor: TextDocumentEditor, selections: Selections): Selections =
  result = selections.mapIt (
    if it.isBackwards:
      if it.last.line > 0:
        (it.first, editor.doMoveCursorColumn(it.last, -1))
      elif it.first.line + 1 < editor.lineCount:
        (editor.doMoveCursorColumn(it.first, 1), it.last)
      else:
        it
    else:
      if it.first.line > 0:
        (editor.doMoveCursorColumn(it.first, -1), it.last)
      elif it.last.line + 1 < editor.lineCount:
        (it.first, editor.doMoveCursorColumn(it.last, 1))
      else:
        it
  )

proc vscodeDeleteLine(editor: TextDocumentEditor) {.expose("vscode-delete-line").} =
  editor.addNextCheckpoint("word")
  let lineSelections = editor.vscodeExtendForLineDeletion(editor.vscodeSelectLines(editor.selections))
  editor.selections = editor.delete(lineSelections, inclusiveEnd=true).mapIt(
    editor.doMoveCursorLine(it.normalized.first, 1).toSelection
  )

proc vscodeTodo(editor: TextDocumentEditor, command: string) {.expose("vscode-todo").} =
  infof"command not implemented: '{command}'. Open an issue."

proc loadVSCodeKeybindings*() {.scriptActionWasmNims("load-vscode-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadVSCodeKeybindings: {t.elapsed.ms} ms"

  info "Applying vscode keybindings"

  clearCommands("editor.text")
  for id in getAllEditors():
    if id.isTextEditor(editor):
      editor.setMode("")

  setHandleInputs "editor.text", true
  setOption "editor.text.cursor.movement.", "both"
  setOption "editor.text.cursor.wide.", false

  loadStandardKeybindings()
  loadStandardSelectorPopupKeybindings()

  addCommand "editor", "<A-F4>", "quit"

  addCommand "editor", "<CS-p>", "command-line"
  addCommand "editor", "<F1>", "command-line"
  addCommand "editor", "<LEADER><LEADER>", "command-line"
  addCommand "editor", "<C-g>t", "choose-theme"
  addCommand "editor", "<C-g>f", "choose-file"
  addCommand "editor", "<C-p>", "choose-file"
  addCommand "editor", "<C-g>o", "choose-open"
  addCommand "editor", "<C-g>d", "choose-open-document"
  addCommand "editor", "<C-g>l", "choose-location"
  addCommand "editor", "<C-g>g", "choose-git-active-files", false
  addCommand "editor", "<C-g>h", "explore-help"
  addCommand "editor", "<C-g>e", "explore-files"
  addCommand "editor", "<C-g>w", "explore-workspace-primary"
  addCommand "editor", "<C-g>u", "explore-user-config-dir"
  addCommand "editor", "<C-g>a", "explore-app-config-dir"
  addCommand "editor", "<C-g>s", "search-global-interactive"
  addCommand "editor", "<CS-f>", "search-global-interactive"

  addTextCommand "", "<C-x>", "vscode-delete-line"

  addTextCommand "", "<A-UP>", "vscode-todo", "move-line-up"
  addTextCommand "", "<A-DOWN>", "vscode-todo", "move-line-down"
  addTextCommand "", "<SA-UP>", "vscode-todo", "copy-line-up"
  addTextCommand "", "<SA-DOWN>", "vscode-todo", "copy-line-down"
  addTextCommand "", "<CS-K>", "vscode-todo", "delete-line"

  addTextCommand "", "<C-ENTER>", "vscode-todo", "insert-line-below"
  addTextCommand "", "<CS-ENTER>", "vscode-todo", "insert-line-above"
  addTextCommand "", r"<CS-\>>", "vscode-todo", "jump-to-matching-bracket"
  addTextCommand "", "<CS-]>", "indent"
  addTextCommand "", "<CS-[>", "unindent"
  addTextCommand "", "<C-UP>", "scroll-lines", -1
  addTextCommand "", "<C-DOWN>", "scroll-lines", 1
  addTextCommand "", "<A-PAGE_UP>", "vscode-todo", "scroll-page-up"
  addTextCommand "", "<A-PAGE_DOWN>", "vscode-todo", "scroll-page-down"
  addTextCommand "", "<C-k><C-c>", "toggle-line-comment"

  addTextCommand "", "<CS-k>", "vscode-todo", "delete-line"

  addTextCommandBlock "", "<F8>":
    editor.selection = editor.getNextDiagnostic(editor.selection.last, 1).first.toSelection
    editor.scrollToCursor Last
    editor.updateTargetColumn()
  addTextCommandBlock "", "<S-F8>":
    editor.selection = editor.getPrevDiagnostic(editor.selection.last, 1).first.toSelection
    editor.scrollToCursor Last
    editor.updateTargetColumn()

  addTextCommand "", "<A-LEFT>", "open-previous-editor" # todo: jump list
  addTextCommand "", "<A-RIGHT>", "select-next" # todo: jump list
  addTextCommand "", "<C-u>", "select-prev" # todo: jump list

  addTextCommand "", "<C-l>", "select-line-current"

  addTextCommandBlock "", "<C-f>":
    commandLine(".set-search-query \\")
    if getActiveEditor().isTextEditor(editor):
      var arr = newJArray()
      arr.add newJString("file")
      discard editor.runAction("move-last", arr)
      editor.setMode("insert")

  addTextCommandBlock "", "<F3>":
    editor.selection = editor.getNextFindResult(editor.selection.last).first.toSelection
    editor.scrollToCursor Last
    editor.updateTargetColumn()

  addTextCommandBlock "", "<S-F3>":
    editor.selection = editor.getPrevFindResult(editor.selection.last).first.toSelection
    editor.scrollToCursor Last
    editor.updateTargetColumn()

  addTextCommand "", "<A-ENTER>", "set-all-find-result-to-selection"
  addTextCommandBlock "", "<C-d>":
    if editor.selections.len == 1 and editor.selection.isEmpty:
      let selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b")
      editor.selection = selection
    else:
      let next = editor.getNextFindResult(editor.selection.last, includeAfter=true)
      editor.selections = editor.selections & next
      editor.scrollToCursor Last
      editor.updateTargetColumn()

  addTextCommand "", "<C-k><C-d>", "vscode-todo", "move-selection-to-last-find-match"

  addTextCommand "", "<CA-UP>", "add-cursor-above"
  addTextCommand "", "<CA-DOWN>", "add-cursor-below"
  addTextCommand "", "<C-r>", "select-prev"

  addCommand "editor.text.completion", "<ESCAPE>", "hide-completions"
  addCommand "editor.text.completion", "<UP>", "select-prev-completion"
  addCommand "editor.text.completion", "<DOWN>", "select-next-completion"
  addCommand "editor.text.completion", "<TAB>", "apply-selected-completion"

  # lsp
  addTextCommand "", "<C-g><C-d>", "goto-definition"
  addTextCommand "", "<C-g><C-D>", "goto-declaration"
  addTextCommand "", "<C-g><C-i>", "goto-implementation"
  addTextCommand "", "<C-g><C-T>", "goto-type-definition"
  addTextCommand "", "<C-g><C-s>", "goto-symbol"
  addTextCommand "", "<C-g><C-w>", "goto-workspace-symbol"
  addTextCommand "", "<C-g><C-r>", "goto-references"
  addTextCommand "", "<C-g><C-o>", "switch-source-header"
  addTextCommand "", "<C-g><C-k>", "show-hover-for-current"
  addTextCommand "", "<C-g><C-h>", "show-diagnostics-for-current"

  addTextCommand "", "<C-SPACE>", "get-completions"
  addTextCommand "", "<F12>", "goto-definition"
  addTextCommand "", "<CS-o>", "goto-symbol"
  addTextCommand "", "<C-t>", "goto-workspace-symbol"
  addTextCommand "", "<S-F12>", "goto-references"
