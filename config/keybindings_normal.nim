import absytree_runtime

proc loadNormalBindings*() =
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
  addTextCommand "", "<SPACE>", "insert-text", " "
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
  addTextCommand "", "\\>", "indent"
  addTextCommand "", "\\<", "unindent"
  addTextCommand "", "<C-k><C-c>", "toggle-line-comment"
  addTextCommand "", "<C-i>", "center-cursor"

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