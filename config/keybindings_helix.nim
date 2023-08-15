import absytree_runtime, keybindings_normal

proc loadHelixKeybindings*() {.scriptActionWasmNims("load-helix-keybindings").} =
  loadNormalKeybindings()

  info "Applying Helix keybindings"

  # clearCommands("editor.text")
  # for id in getAllEditors():
  #   if id.isTextEditor(editor):
  #     editor.setMode("")

  # Normal mode
  setHandleInputs "editor.text", false
  setOption "editor.text.cursor.movement.", "last-to-first"
  setOption "editor.text.cursor.wide.", true

  addTextCommand "", "x", "delete-right"
  addTextCommand "", "<C-l>", "select-line-current"
  addTextCommand "", "miw", "select-inside-current"
  addTextCommand "", "u", "undo"
  addTextCommand "", "U", "redo"
  addTextCommand "", "i", "set-mode", "insert"
  addTextCommand "", "v", "set-mode", "visual"
  addTextCommand "", "m", "set-mode", "match"
  addTextCommand "", "dl", "delete-move", "line-next"
  addTextCommand "", "b", "move-first", "word-line"
  addTextCommand "", "w", "move-last", "word-line"
  addTextCommand "", "e", "move-last", "word-line"
  addTextCommand "", "<HOME>", "move-first", "line"
  addTextCommand "", "<END>", "move-last", "line"

  addTextCommandBlock "", "di":
    editor.setMode("move")
    setOption("text.move-action", "delete-move")
    setOption("text.move-next-mode", "")
  addTextCommandBlock "", "c":
    editor.setMode("move")
    setOption("text.move-action", "change-move")
    setOption("text.move-next-mode", "")
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

  # Match mode
  setHandleInputs "editor.text.move", false
  setOption "editor.text.cursor.movement.match", "both"
  setOption "editor.text.cursor.wide.match", true
  addTextCommandBlock "match", "i":
    editor.setMode("move")
    setOption("text.move-action", "select-move")
    setOption("text.move-next-mode", "")

  # Move mode
  setHandleInputs "editor.text.move", false
  setOption "editor.text.cursor.movement.move", "both"
  setOption "editor.text.cursor.wide.move", true
  addTextCommand "move", "w", "set-move", "word"
  addTextCommand "move", "W", "set-move", "word-line"
  addTextCommand "move", "p", "set-move", "paragraph"
  addTextCommand "move", "l", "set-move", "line"
  addTextCommand "move", "L", "set-move", "line-next"
  addTextCommand "move", "\"", "set-move", "\""
  addTextCommand "move", "'", "set-move", "'"
  addTextCommand "move", "(", "set-move", "("
  addTextCommand "move", ")", "set-move", "("
  addTextCommand "move", "[", "set-move", "["
  addTextCommand "move", "]", "set-move", "["
  addTextCommand "move", "}", "set-move", "}"
  addTextCommand "move", "}", "set-move", "}"

  # Insert mode
  setHandleInputs "editor.text.insert", true
  setOption "editor.text.cursor.wide.insert", false
  setOption "editor.text.cursor.movement.visual", "both"
  addTextCommand "insert", "<ENTER>", "insert-text", "\n"
  addTextCommand "insert", "<SPACE>", "insert-text", " "

  # Visual mode
  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.insert", true
  setOption "editor.text.cursor.movement.visual", "last"
  addTextCommand "visual", "v", "set-mode", ""
  addTextCommandBlock "visual", "i":
    editor.setMode("move")
    setOption("text.move-action", "select-move")
    setOption("text.move-next-mode", "visual")