import std/[strutils, setutils]
import absytree_runtime, keybindings_normal
import misc/[timer]

proc getVimLineMargin*(): float = getOption[float]("editor.text.vim.line-margin", 5)
proc getVimClipboard*(): string = getOption[string]("editor.text.vim.clipboard", "")
proc getVimDefaultRegister*(): string =
  case getVimClipboard():
  of "unnamed": return "*"
  of "unnamedplus": return "+"
  else: return "\""

proc getEnclosing(line: string, column: int, predicate: proc(c: char): bool): (int, int) =
  var startColumn = column
  var endColumn = column
  while endColumn < line.len and predicate(line[endColumn]):
    inc endColumn
  while startColumn > 0 and predicate(line[startColumn - 1]):
    dec startColumn
  return (startColumn, endColumn)

proc vimMotionWord*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  const AlphaNumeric = {'A'..'Z', 'a'..'z', '0'..'9', '_'}

  var line = editor.getLine(cursor.line)
  if line.len == 0:
    return (cursor.line, 0).toSelection

  var c = line[cursor.column.clamp(0, line.high)]
  if c in Whitespace:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c in Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  elif c in AlphaNumeric:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c in AlphaNumeric)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  else:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c notin Whitespace and c notin AlphaNumeric)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

proc vimMotionWordBig*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  var line = editor.getLine(cursor.line)
  if line.len == 0:
    return (cursor.line, 0).toSelection

  var c = line[cursor.column.clamp(0, line.high)]
  if c in Whitespace:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c in Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  else:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c notin Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

proc vimMotionParagraphInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  if editor.lineLength(cursor.line) == 0:
    return cursor.toSelection

  result = ((cursor.line, 0), cursor)
  while result.first.line - 1 >= 0 and editor.lineLength(result.first.line - 1) > 0:
    dec result.first.line
  while result.last.line + 1 < editor.lineCount and editor.lineLength(result.last.line + 1) > 0:
    inc result.last.line
    result.last.column = editor.lineLength(result.last.line)

proc vimMotionParagraphOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  if editor.lineLength(cursor.line) == 0:
    return cursor.toSelection

  result = ((cursor.line, 0), cursor)
  while result.first.line - 1 >= 0 and editor.lineLength(result.first.line - 1) > 0:
    dec result.first.line
  while result.last.line + 1 < editor.lineCount and editor.lineLength(result.last.line) > 0:
    inc result.last.line
    result.last.column = editor.lineLength(result.last.line)

iterator iterateTextObjects(editor: TextDocumentEditor, cursor: Cursor, move: string, backwards: bool = false): Selection =
  var selection = editor.getSelectionForMove(cursor, move, 0)
  yield selection
  while true:
    let lastSelection = selection
    if not backwards and selection.last.column == editor.lineLength(selection.last.line):
      if selection.last.line == editor.lineCount - 1:
        break
      selection = (selection.last.line + 1, 0).toSelection
    elif backwards and selection.first.column == 0:
      if selection.first.line == 0:
        break
      selection = (selection.first.line - 1, editor.lineLength(selection.first.line - 1)).toSelection
      if selection.first.column == 0:
        yield selection
        continue

    let nextCursor = if backwards: (selection.first.line, selection.first.column - 1) else: selection.last
    let newSelection = editor.getSelectionForMove(nextCursor, move, 0)
    if newSelection == lastSelection:
      break

    selection = newSelection
    yield selection

iterator enumerateTextObjects(editor: TextDocumentEditor, cursor: Cursor, move: string, backwards: bool = false): (int, Selection) =
  var i = 0
  for selection in iterateTextObjects(editor, cursor, move, backwards):
    yield (i, selection)
    inc i

proc moveSelectionNext(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false) =
  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      for i, selection in enumerateTextObjects(editor, res, move, backwards):
        if i == 0: continue
        let cursor = if backwards: selection.last else: selection.first
        if cursor == it.last:
          continue
        if editor.lineLength(selection.first.line) == 0:
          if allowEmpty:
            res = cursor
            break
          else:
            continue

        if editor.getLine(selection.first.line)[selection.first.column] notin Whitespace:
          res = cursor
          break
      res.toSelection
    )

proc moveSelectionEnd(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false) =
  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      for i, selection in enumerateTextObjects(editor, res, move, backwards):
        let cursor = if backwards: selection.first else: selection.last
        if cursor == it.last:
          continue
        if editor.lineLength(selection.last.line) == 0:
          if allowEmpty:
            res = cursor
            break
          else:
            continue
        if editor.getLine(selection.last.line)[selection.last.column - 1] notin Whitespace:
          res = cursor
          break
      res.toSelection
    )

proc loadVimKeybindings*() {.scriptActionWasmNims("load-vim-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadVimKeybindings: {t.elapsed.ms} ms"

  info "Applying Vim keybindings"

  clearCommands("editor.text")
  # for id in getAllEditors():
  #   if id.isTextEditor(editor):
  #     editor.setMode("")

  setModeChangedHandler proc(editor, oldMode, newMode: auto) =
    if oldMode == "" and newMode != "":
      editor.clearCurrentCommandHistory(retainLast=true)
    elif oldMode != "" and newMode == "":
      editor.saveCurrentCommandHistory()

  for i in 0..9:
    capture i:
      proc updateCommandCountHelper(editor: TextDocumentEditor) =
        if i == 0 and editor.getCommandCount == 0:
          editor.moveFirst "line"
          editor.scrollToCursor Last
        else:
          editor.updateCommandCount i
          # echo "updateCommandCount ", editor.getCommandCount
          editor.setCommandCountRestore editor.getCommandCount
          editor.setCommandCount 0

      addTextCommand "", $i, updateCommandCountHelper

  # Normal mode
  setHandleInputs "editor.text", false
  setOption "editor.text.cursor.movement.", "both"
  setOption "editor.text.cursor.wide.", true

  addTextCommandBlock "", "<C-e>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection
  addTextCommandBlock "", "<ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection

  # navigation (horizontal)
  addTextCommand "", "h", "move-cursor-column", -1
  addTextCommand "", "<LEFT>", "move-cursor-column", -1
  addTextCommand "", "<BACKSPACE>", "move-cursor-column", -1

  addTextCommand "", "l", "move-cursor-column", 1
  addTextCommand "", "<RIGHT>", "move-cursor-column", 1
  addTextCommand "", "<SPACE>", "move-cursor-column", 1

  # addTextCommand "", "0", "move-first", "line" # implemented above in number handling
  addTextCommand "", "<HOME>", "move-first", "line"
  addTextCommand "", "^", "move-first", "line-no-indent"

  proc moveToEndOfLine(editor: TextDocumentEditor) =
    let count = editor.getCommandCount
    if count > 1:
      editor.moveCursorLine(count - 1)
    editor.moveLast("line")
    editor.setCommandCount 0
    editor.scrollToCursor Last

  addTextCommand "", "$", moveToEndOfLine
  addTextCommand "", "<S-$>", moveToEndOfLine
  addTextCommand "", "<END>", moveToEndOfLine

  addTextCommand "", "g0", "move-first", "line"
  addTextCommand "", "g^", "move-first", "line-no-indent"

  addTextCommand "", "g$", moveToEndOfLine
  addTextCommand "", "gm", "move-cursor-line-center"
  addTextCommand "", "gM", "move-cursor-center"

  addTextCommand "", "", "move-last", "line"
  addTextCommand "", "<UP>", "move-cursor-line", -1
  addTextCommand "", "<DOWN>", "move-cursor-line", 1

  addTextCommandBlock "", "|":
    let count = editor.getCommandCount
    editor.selections = editor.selections.mapIt((it.last.line, count).toSelection)
    editor.setCommandCount 0
    editor.scrollToCursor Last

  # navigation (vertical)
  addTextCommand "", "k", "move-cursor-line", -1
  addTextCommand "", "<UP>", "move-cursor-line", -1
  addTextCommand "", "<C-p>", "move-cursor-line", -1

  addTextCommand "", "j", "move-cursor-line", 1
  addTextCommand "", "<DOWN>", "move-cursor-line", 1
  addTextCommand "", "<ENTER>", "move-cursor-line", 1
  addTextCommand "", "<C-n>", "move-cursor-line", 1
  addTextCommand "", "<C-j>", "move-cursor-line", 1

  proc moveCursorLineFirstChar(editor: TextDocumentEditor, direction: int) =
    editor.moveCursorLine(direction)
    editor.moveFirst "line-no-indent"

  addTextCommandBlock "", "-": moveCursorLineFirstChar(editor, -1)
  addTextCommandBlock "", "+": moveCursorLineFirstChar(editor, 1)

  proc moveToStartOfLine(editor: TextDocumentEditor) =
    let count = editor.getCommandCount
    if count > 1:
      editor.moveCursorLine(count - 1)
    editor.moveFirst "line-no-indent"
    editor.setCommandCount 0
    editor.scrollToCursor Last

  addTextCommand "", "_", moveToStartOfLine
  addTextCommand "", "G", "move-last", "file"

  addTextCommandBlock "", "gg":
    let count = editor.getCommandCount
    editor.selection = (count, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.setCommandCount 0
    editor.scrollToCursor Last

  addTextCommandBlock "", "G":
    let count = editor.getCommandCount
    let line = if count == 0: editor.lineCount - 1 else: count
    editor.selection = (line, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.setCommandCount 0
    editor.scrollToCursor Last

  addTextCommandBlock "", "%":
    let count = editor.getCommandCount
    if count == 0:
      # todo: find matching bracket
      discard
    else:
      let line = clamp((count * editor.lineCount) div 100, 0, editor.lineCount - 1)
      editor.selection = (line, 0).toSelection
      editor.moveFirst "line-no-indent"
      editor.setCommandCount 0
      editor.scrollToCursor Last

  addTextCommand "", "k", "move-cursor-line", -1
  addTextCommand "", "j", "move-cursor-line", 1
  addTextCommand "", "gk", "move-cursor-line", -1
  addTextCommand "", "gj", "move-cursor-line", 1

  # Scrolling
  addTextCommand "", "<C-e>", "scroll-lines", 1
  addTextCommandBlock "", "<C-d>": editor.moveCursorLine(editor.screenLineCount div 2)
  addTextCommandBlock "", "<C-f>": editor.moveCursorLine(editor.screenLineCount)

  addTextCommand "", "<C-y>", "scroll-lines", -1
  addTextCommandBlock "", "<C-u>": editor.moveCursorLine(-editor.screenLineCount div 2)
  addTextCommandBlock "", "<C-b>": editor.moveCursorLine(-editor.screenLineCount)

  addTextCommandBlock "", "z<ENTER>":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

  addTextCommandBlock "", "zt":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
    editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

  addTextCommandBlock "", "z.":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.centerCursor()

  addTextCommandBlock "", "zz":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
    editor.centerCursor()

  addTextCommandBlock "", "z-":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

  addTextCommandBlock "", "zb":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
    editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

  # Mode switches
  addTextCommandBlock "", "a":
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1).toSelection)
    editor.setMode "insert"
  addTextCommandBlock "", "A":
    editor.moveLast "line"
    editor.setMode "insert"
  addTextCommand "", "i", "set-mode", "insert"
  addTextCommandBlock "", "I":
    editor.moveFirst "line-no-indent"
    editor.setMode "insert"
  addTextCommandBlock "", "gI":
    editor.moveFirst "line"
    editor.setMode "insert"

  addTextCommandBlock "", "o":
    editor.moveLast "line"
    editor.insertText "\n"
    editor.setMode "insert"

  addTextCommandBlock "", "O":
    editor.moveFirst "line"
    editor.insertText "\n"
    editor.moveCursorLine -1
    editor.setMode "insert"

  addTextCommand "", "<ESCAPE>", "set-mode", ""
  addTextCommand "", "<C-c>", "set-mode", ""

  # todo
  addCustomTextMove "vim-word", vimMotionWord
  addCustomTextMove "vim-WORD", vimMotionWordBig
  addCustomTextMove "vim-paragraph-inner", vimMotionParagraphInner
  addCustomTextMove "vim-paragraph-outer", vimMotionParagraphOuter

  # Text object motions
  addTextCommandBlock "", "w": editor.moveSelectionNext("vim-word", allowEmpty=true)
  addTextCommandBlock "", "W": editor.moveSelectionNext("vim-WORD", allowEmpty=true)
  addTextCommandBlock "", "e": editor.moveSelectionEnd("vim-word")
  addTextCommandBlock "", "E": editor.moveSelectionEnd("vim-WORD")
  addTextCommandBlock "", "b": editor.moveSelectionEnd("vim-word", backwards=true, allowEmpty=true)
  addTextCommandBlock "", "B": editor.moveSelectionEnd("vim-WORD", backwards=true, allowEmpty=true)
  addTextCommandBlock "", "ge": editor.moveSelectionNext("vim-word", backwards=true)
  addTextCommandBlock "", "gE": editor.moveSelectionNext("vim-WORD", backwards=true)

  addTextCommandBlock "", "}": editor.moveSelectionEnd("vim-paragraph-outer", allowEmpty=true)
  addTextCommandBlock "", "{": editor.moveSelectionNext("vim-paragraph-outer", backwards=true)

  # Insert mode
  setHandleInputs "editor.text.insert", true
  setOption "editor.text.cursor.wide.insert", false
  addTextCommand "insert", "<ENTER>", "insert-text", "\n"
  addTextCommand "insert", "<C-m>", "insert-text", "\n"
  addTextCommand "insert", "<C-j>", "insert-text", "\n"

  addTextCommand "insert", "<C-r>", "set-mode", "insert-register"
  setHandleInputs "editor.text.insert-register", true
  setTextInputHandler "insert-register", proc(editor: TextDocumentEditor, input: string): bool =
    editor.paste input
    editor.setMode "insert"
    return true
  addTextCommandBlock "insert-register", "<SPACE>":
    editor.paste getVimDefaultRegister()
    editor.setMode "insert"
  addTextCommand "insert-register", "<ESCAPE>", "set-mode", "insert"

  addTextCommand "insert", "<SPACE>", "insert-text", " "
  addTextCommand "insert", "<BACKSPACE>", "delete-left"
  addTextCommand "insert", "<C-h>", "delete-left"
  addTextCommand "insert", "<DELETE>", "delete-right"
  addTextCommandBlock "insert", "<C-w>":
    editor.deleteMove("word-line", inside=false, which=SelectionCursor.First)
  addTextCommandBlock "insert", "<C-u>":
    editor.deleteMove("line-back", inside=false, which=SelectionCursor.First)

  addTextCommand "insert", "<C-t>", "indent"
  addTextCommand "insert", "<C-d>", "unindent"

  # Visual mode
  addTextCommand "", "v", "set-mode", "visual"
  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"
  addTextCommandBlock "visual", "y":
    editor.copy getVimDefaultRegister()
    editor.setMode ""
    editor.selections = editor.selections.mapIt(it.first.toSelection)

proc loadVimLikeKeybindings*() {.scriptActionWasmNims("load-vim-like-keybindings").} =
  loadNormalKeybindings()

  let t = startTimer()
  defer:
    infof"loadVimLikeKeybindings: {t.elapsed.ms} ms"

  info "Applying Vim-like keybindings"

  # clearCommands("editor.text")
  # for id in getAllEditors():
  #   if id.isTextEditor(editor):
  #     editor.setMode("")

  setModeChangedHandler proc(editor, oldMode, newMode: auto) =
    if oldMode == "" and newMode != "":
      editor.clearCurrentCommandHistory(retainLast=true)
    elif oldMode != "" and newMode == "":
      editor.saveCurrentCommandHistory()

  # Normal mode
  setHandleInputs "editor.text", false
  setOption "editor.text.cursor.movement.", "both"
  setOption "editor.text.cursor.wide.", true

  # navigation
  addTextCommand "", "<C-d>", "move-cursor-line", 30
  addTextCommand "", "<C-u>", "move-cursor-line", -30

  addTextCommandBlock "", "gg":
    let count = editor.getCommandCount
    editor.selection = (count, 0).toSelection
    editor.setCommandCount 0
    editor.scrollToCursor Last

  addTextCommand "", "G", "move-last", "file"

  addTextCommand "", "n", "select-move", "next-find-result", true
  addTextCommand "", "N", "select-move", "prev-find-result", true

  addTextCommandBlock "", "*": editor.setSearchQueryFromMove("word")

  # editing
  addTextCommand "", "x", "delete-right"
  addTextCommand "", "u", "undo"
  addTextCommand "", "U", "redo"
  addTextCommand "", "p", "paste"

  addTextCommand "", "\\>", "indent"
  addTextCommand "", "\\<", "unindent"

  addTextCommand "", ".", "run-saved-commands"

  # mode switches
  addTextCommand "", "i", "set-mode", "insert"
  addTextCommandBlock "", "I":
    editor.moveFirst("line-no-indent")
    editor.setMode("insert")
  addTextCommandBlock "", "a":
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1).toSelection)
    editor.setMode("insert")
  addTextCommandBlock "", "A":
    editor.moveLast("line")
    editor.setMode("insert")

  addTextCommand "", "v", "set-mode", "visual"

  addTextCommandBlock "", "s":
    editor.selections = editor.delete(editor.selections)
    editor.setMode("insert")

  for i in 0..9:
    capture i:
      proc updateCommandCountHelper(editor: TextDocumentEditor) =
        editor.updateCommandCount i
        # echo "updateCommandCount ", editor.getCommandCount
        editor.setCommandCountRestore editor.getCommandCount
        editor.setCommandCount 0

      addTextCommand "", $i, updateCommandCountHelper

  addTextCommandBlock "", "d":
    editor.setMode "move"
    setOption "text.move-action", "delete-move"
    setOption "text.move-next-mode", ""
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  addTextCommand "", "D", "delete-move", "line"

  addTextCommandBlock "", "c":
    editor.setMode "move"
    setOption "text.move-action", "change-move"
    setOption "text.move-next-mode", "insert"
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  addTextCommandBlock "", "y":
    editor.setMode "move"
    setOption "text.move-action", "copy-move"
    setOption "text.move-next-mode", ""
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  addTextCommandBlock "", "f":
    setOption("text.move-next-mode", editor.mode)
    editor.setMode "move-to"
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  addTextCommandBlock "", "t":
    setOption("text.move-next-mode", editor.mode)
    editor.setMode "move-before"
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  addTextCommandBlock "", "D":
    editor.deleteMove("line")

  addTextCommandBlock "", "C":
    editor.deleteMove("line")
    editor.setMode("insert")

  addTextCommandBlock "", "Y":
    editor.selectMove("line")
    editor.copy()

  addTextCommand "", "dl", "delete-move", "line-next"
  addTextCommand "", "b", "move-last", "word-line-back"
  addTextCommand "", "w", "move-last", "word-line"
  addTextCommand "", "e", "move-last", "word-line"
  addTextCommand "", "<HOME>", "move-first", "line"
  addTextCommand "", "<END>", "move-last", "line"
  addTextCommandBlock "", "o":
    editor.moveCursorEnd()
    editor.insertText("\n")
    editor.setMode("insert")
  addTextCommandBlock "", "O":
    editor.moveCursorEnd()
    editor.insertText("\n")
  addTextCommandBlock "", "<C-e>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection
  addTextCommandBlock "", "<ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection
  addTextCommandBlock "", "<S-ESCAPE>":
    editor.setMode("")
    editor.selection = editor.selection.last.toSelection

  # move mode
  setHandleInputs "editor.text.move", false
  setOption "editor.text.cursor.wide.move", true
  setOption "editor.text.cursor.movement.move", "both"
  addTextCommand "move", "i", "set-mode", "move-inside"

  template addTextMoveCommand(keys: string, move: string): untyped =
    addTextCommand "move", keys, "apply-move", move, false
    addTextCommand "move-inside", keys, "apply-move", move, true

  addTextMoveCommand "w", "word-line"
  addTextMoveCommand "W", "word"
  addTextMoveCommand "b", "word-line-back"
  addTextMoveCommand "B", "word-back"
  addTextMoveCommand "p", "paragraph"
  addTextMoveCommand "F", "file"
  addTextMoveCommand "\"", "\""
  addTextMoveCommand "'", "'"
  addTextMoveCommand "(", "("
  addTextMoveCommand ")", "("
  addTextMoveCommand "[", "["
  addTextMoveCommand "]", "["
  addTextMoveCommand "}", "}"

  addTextCommand "move", "d", "apply-move", "line-next", true
  addTextCommand "move-inside", "d", "apply-move", "line-next", true
  addTextCommand "move", "y", "apply-move", "line-next", true
  addTextCommand "move-inside", "y", "apply-move", "line-next", true

  addTextCommandBlock "move", "f":
    editor.setMode "move-to"
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  addTextCommandBlock "move", "t":
    editor.setMode "move-before"
    setOption "text.move-command-count", editor.getCommandCount()
    editor.setCommandCount 0

  # move-to mode
  setHandleActions "editor.text.move-to", false
  setTextInputHandler "move-to", proc(editor: TextDocumentEditor, input: string): bool =
    editor.setMode getOption[string]("text.move-next-mode")
    if getOption[string]("text.move-action") != "":
      editor.setCommandCount getOption[int]("text.move-command-count")
      var args = newJArray()
      args.add newJString("move-to " & input)
      discard editor.runAction(getOption[string]("text.move-action"), args)
      setOption[string]("text.move-action", "")
    else:
      editor.moveCursorTo(input)
    return true
  setOption "editor.text.cursor.wide.move-to", true
  setOption "editor.text.cursor.movement.move-to", "both"

  # move-before mode
  setHandleActions "editor.text.move-before", false
  setTextInputHandler "move-before", proc(editor: TextDocumentEditor, input: string): bool =
    editor.setMode getOption[string]("text.move-next-mode")
    if getOption[string]("text.move-action") != "":
      editor.setCommandCount getOption[int]("text.move-command-count")
      var args = newJArray()
      args.add newJString("move-before " & input)
      discard editor.runAction(getOption[string]("text.move-action"), args)
      setOption[string]("text.move-action", "")
    else:
      editor.moveCursorBefore(input)
    return true
  setOption "editor.text.cursor.wide.move-before", true
  setOption "editor.text.cursor.movement.move-before", "both"

  # Insert mode
  setHandleInputs "editor.text.insert", true
  setOption "editor.text.cursor.wide.insert", false
  addTextCommand "insert", "<ENTER>", "insert-text", "\n"
  addTextCommand "insert", "<SPACE>", "insert-text", " "

  # Visual mode
  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"
  addTextCommand "visual", "y", "copy"

  addTextCommandBlock "visual", "i":
    editor.setMode("move-inside")
    setOption("text.move-action", "select-move")
    setOption("text.move-next-mode", "visual")

  addTextCommandBlock "visual", "d":
    editor.selections = editor.delete(editor.selections)
    editor.setMode("")
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  addTextCommandBlock "visual", "c":
    editor.selections = editor.delete(editor.selections)
    editor.setMode("insert")
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  addTextCommandBlock "visual", "d":
    editor.selections = editor.delete(editor.selections)
    editor.setMode("")
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  addTextCommandBlock "visual", "c":
    editor.selections = editor.delete(editor.selections)
    editor.setMode("insert")
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  block: # model
    setHandleInputs "editor.model", false
    setOption "editor.model.cursor.wide.", true

    addCommand("editor.model", "b", "move-cursor-left-cell")
    addCommand("editor.model", "w", "move-cursor-right-cell")
    addCommand("editor.model", "u", "undo")
    addCommand("editor.model", "U", "redo")
    addModelCommand "", "}", "goto-next-node-of-class", "EmptyLine"
    addModelCommand "", "{", "goto-prev-node-of-class", "EmptyLine"

    addModelCommandBlock "", "<C-e>":
      editor.setMode("")
      # editor.selection = editor.selection.last.toSelection
    addModelCommandBlock "", "<ESCAPE>":
      editor.setMode("")
      # editor.selection = editor.selection.last.toSelection
    addModelCommandBlock "", "<S-ESCAPE>":
      editor.setMode("")
      # editor.selection = editor.selection.last.toSelection

    addModelCommand "", "i", "set-mode", "insert"
    addModelCommandBlock "", "I":
      editor.moveCursorLineStart(false)
      editor.setMode("insert")
    addModelCommandBlock "", "a":
      # editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1).toSelection)
      editor.setMode("insert")
    addModelCommandBlock "", "A":
      editor.moveCursorLineEnd(false)
      editor.setMode("insert")

    # Insert mode
    setHandleInputs "editor.model.insert", true
    setOption "editor.model.cursor.wide.insert", false
    addModelCommand "insert", "<SPACE>", "insert-text-at-cursor", " "
