
proc loadVimBindings*() =
  loadNormalBindings()

  echo "Applying Vim keybindings"

  # clearCommands("editor.text")
  # for id in getAllEditors():
  #   if id.isTextEditor(editor):
  #     editor.setMode("")

  # Normal mode
  setHandleInputs "editor.text", false
  setOption "editor.text.cursor.movement.", "both"
  setOption "editor.text.cursor.wide.", true

  addCommand "editor.text", "x", "delete-right"
  addCommand "editor.text", "<C-l>", "select-line-current"
  addCommand "editor.text", "miw", "select-inside-current"
  addCommand "editor.text", "u", "undo"
  addCommand "editor.text", "U", "redo"
  addCommand "editor.text", "i", "set-mode", "insert"
  addCommand "editor.text", "v", "set-mode", "visual"
  addCommand "editor.text", "V", "set-mode", "visual-temp"

  addTextCommandBlock "", "di":
    editor.setMode("move")
    setOption("text.move-action", "delete-move")
    setOption("text.move-next-mode", "")
  addTextCommandBlock "", "ci":
    editor.setMode("move")
    setOption("text.move-action", "change-move")
    setOption("text.move-next-mode", "insert")
  addCommand "editor.text", "dl", "delete-move", "line-next"
  addCommand "editor.text", "b", "move-first", "word-line"
  addCommand "editor.text", "w", "move-last", "word-line"
  addCommand "editor.text", "<HOME>", "move-first", "line"
  addCommand "editor.text", "<END>", "move-last", "line"
  addTextCommandBlock "", "o":
    editor.moveCursorEnd()
    editor.insertText("\n")
    editor.setMode("insert")
  addTextCommandBlock "", "O":
    editor.moveCursorEnd()
    editor.insertText("\n")
  addTextCommandBlock "", "<ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection
  addTextCommandBlock "", "<S-ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection

  # Move mode
  setHandleInputs "editor.text.move", false
  setOption "editor.text.cursor.wide.move", true
  setOption "editor.text.cursor.movement.move", "both"
  addCommand "editor.text.move", "w", "set-move", "word"
  addCommand "editor.text.move", "W", "set-move", "word-line"
  addCommand "editor.text.move", "p", "set-move", "paragraph"
  addCommand "editor.text.move", "l", "set-move", "line"
  addCommand "editor.text.move", "L", "set-move", "line-next"
  addCommand "editor.text.move", "f", "set-move", "file"
  addCommand "editor.text.move", "\"", "set-move", "\""
  addCommand "editor.text.move", "'", "set-move", "'"
  addCommand "editor.text.move", "(", "set-move", "("
  addCommand "editor.text.move", ")", "set-move", "("
  addCommand "editor.text.move", "[", "set-move", "["
  addCommand "editor.text.move", "]", "set-move", "["
  addCommand "editor.text.move", "}", "set-move", "}"
  addCommand "editor.text.move", "}", "set-move", "}"

  # Insert mode
  setHandleInputs "editor.text.insert", true
  setOption "editor.text.cursor.wide.insert", false
  addCommand "editor.text.insert", "<ENTER>", "insert-text", "\n"
  addCommand "editor.text.insert", "<SPACE>", "insert-text", " "

  # Visual mode
  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"
  addTextCommandBlock "visual", "i":
    editor.setMode("move")
    setOption("text.move-action", "select-move")
    setOption("text.move-next-mode", "visual")

  # Visual temp mode
  setHandleInputs "editor.text.visual-temp", false
  setOption "editor.text.cursor.wide.visual-temp", false
  setOption "editor.text.cursor.movement.visual-temp", "last-to-first"
  addTextCommandBlock "visual", "i":
    editor.setMode("move")
    setOption("text.move-action", "select-move")
    setOption("text.move-next-mode", "visual-temp")