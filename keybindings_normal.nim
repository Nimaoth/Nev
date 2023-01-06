
proc loadNormalBindings*() =
  echo "Applying normal keybindings"

  clearCommands("editor.text")
  for id in getAllEditors():
    if id.isTextEditor(editor):
      editor.setMode("")

  setHandleInputs "editor.text", true
  setOption "editor.text.cursor.movement.", "both"
  setOption "editor.text.cursor.wide.", false

  addCommand "editor.text", "<LEFT>", "move-cursor-column", -1
  addCommand "editor.text", "<RIGHT>", "move-cursor-column", 1
  addCommand "editor.text", "<C-d>", "delete-move", "line-next"
  addCommand "editor.text", "<C-LEFT>", "move-first", "word-line"
  addCommand "editor.text", "<C-RIGHT>", "move-last", "word-line"
  addCommand "editor.text", "<HOME>", "move-first", "line"
  addCommand "editor.text", "<END>", "move-last", "line"
  addCommand "editor.text", "<C-UP>", "scroll-text", 20
  addCommand "editor.text", "<C-DOWN>", "scroll-text", -20
  addCommand "editor.text", "<CS-LEFT>", "move-first", "word-line", "last"
  addCommand "editor.text", "<CS-RIGHT>", "move-last", "word-line", "last"
  addCommand "editor.text", "<UP>", "move-cursor-line", -1
  addCommand "editor.text", "<DOWN>", "move-cursor-line", 1
  addCommand "editor.text", "<C-HOME>", "move-first", "file"
  addCommand "editor.text", "<C-END>", "move-last", "file"
  addCommand "editor.text", "<CS-HOME>", "move-first", "file", "last"
  addCommand "editor.text", "<CS-END>", "move-last", "file", "last"
  addCommand "editor.text", "<S-LEFT>", "move-cursor-column", -1, "last"
  addCommand "editor.text", "<S-RIGHT>", "move-cursor-column", 1, "last"
  addCommand "editor.text", "<S-UP>", "move-cursor-line", -1, "last"
  addCommand "editor.text", "<S-DOWN>", "move-cursor-line", 1, "last"
  addCommand "editor.text", "<S-HOME>", "move-first", "line", "last"
  addCommand "editor.text", "<S-END>", "move-last", "line", "last"
  addCommand "editor.text", "<BACKSPACE>", "delete-left"
  addCommand "editor.text", "<DELETE>", "delete-right"
  addCommand "editor.text", "<ENTER>", "insert-text", "\n"
  addCommand "editor.text", "<SPACE>", "insert-text", " "
  addCommand "editor.text", "<C-l>", "select-line-current"
  addCommand "editor.text", "<A-UP>", "select-parent-current-ts"
  addCommand "editor.text", "<C-r>", "select-prev"
  addCommand "editor.text", "<C-t>", "select-next"
  addCommand "editor.text", "<C-n>", "invert-selection"
  addCommand "editor.text", "<C-y>", "undo"
  addCommand "editor.text", "<C-z>", "redo"

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