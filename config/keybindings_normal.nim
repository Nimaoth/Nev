import plugin_runtime
import misc/[event, id, timer]

{.used.}

proc setModeChangedHandler*(handler: proc(editor: TextDocumentEditor, oldMode: string, newMode: string) {.gcsafe, raises: [].}) =
  let modeChangedHandler = getOption("editor.text.mode-changed-handler", "")
  if modeChangedHandler != "":
    onEditorModeChanged.unsubscribe(parseId(modeChangedHandler))
  let id = onEditorModeChanged.subscribe proc(arg: auto) {.gcsafe, raises: [].} =
    # infof"onEditorModeChanged: {arg.editor}, {arg.oldMode}, {arg.newMode}"
    if arg.editor.isTextEditor(editor) and not editor.isRunningSavedCommands:
      handler(editor, arg.oldMode, arg.newMode)
  setOption("editor.text.mode-changed-handler", $id)

proc addModeChangedHandler*(id: var Id, handler: proc(editor: TextDocumentEditor, oldMode: string, newMode: string) {.gcsafe, raises: [].}) =
  if id != idNone():
    onEditorModeChanged.unsubscribe(id)
  id = onEditorModeChanged.subscribe proc(arg: auto) {.gcsafe, raises: [].} =
    # infof"onEditorModeChanged: {arg.editor}, {arg.oldMode}, {arg.newMode}"
    if arg.editor.isTextEditor(editor) and not editor.isRunningSavedCommands:
      handler(editor, arg.oldMode, arg.newMode)

proc vscodeEscape(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-escape").} =
  editor.selection = editor.selection.last.toSelection
  editor.clearTabStops()

proc loadModelKeybindings*() {.expose("load-model-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadModelKeybindings: {t.elapsed.ms} ms"

  info "Applying model keybindings"

  # setHandleInputs "editor.model", true
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

  addCommand "editor.model", "<LEADER>er", "run-selected-function"
  addCommand "editor.model", "<LEADER>ed", "toggle-use-default-cell-builder"
  addCommand "editor.model", "<LEADER>ec", "compile-language"

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

proc vscodeSelectNextDiagnostic(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-select-next-diagnostic").} =
  editor.selection = editor.getNextDiagnostic(editor.selection.last, 1).first.toSelection
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vscodeSelectPrevDiagnostic(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-select-prev-diagnostic").} =
  editor.selection = editor.getPrevDiagnostic(editor.selection.last, 1).first.toSelection
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vscodeSearch(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-search").} =
  commandLine(".set-search-query \\")
  if getActiveEditor().isTextEditor(editor):
    var arr = newJArray()
    arr.add newJString("file")
    discard editor.runAction("move-last", arr)
    editor.setMode("insert")

proc vscodeSelectNextFindResult(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-select-next-find-result").} =
  editor.selection = editor.getNextFindResult(editor.selection.last).first.toSelection
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vscodeSelectPrevFindResult(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-select-prev-find-result").} =
  editor.selection = editor.getPrevFindResult(editor.selection.last).first.toSelection
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vscodeAddNextFindResultToSelection(editor: TextDocumentEditor) {.exposeActive("editor.text", "vscode-add-next-find-result-to-selection").} =
  if editor.selections.len == 1 and editor.selection.isEmpty:
    let selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b")
    editor.selection = selection
  else:
    let next = editor.getNextFindResult(editor.selection.last, includeAfter=true)
    editor.selections = editor.selections & next
    editor.scrollToCursor Last
    editor.updateTargetColumn()
