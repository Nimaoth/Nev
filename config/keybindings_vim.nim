import std/[strutils, setutils]
import absytree_runtime, keybindings_normal
import misc/[timer]


infof"import vim keybindings"

var vimMotionNextMode = initTable[EditorId, string]()

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

proc vimSelectLastCursor(editor: TextDocumentEditor) {.expose("vim-select-last-cursor").} =
  # infof"vimSelectLastCursor"
  editor.selections = editor.selections.mapIt(it.last.toSelection)

proc vimDeleteSelection(editor: TextDocumentEditor) {.expose("vim-delete-selection").} =
  # infof"vimDeleteSelection"
  editor.copy()
  let selections = editor.selections
  editor.selections = editor.selections.mapIt(it.first.toSelection)
  discard editor.delete(selections)

proc vimChangeMove*(editor: TextDocumentEditor) {.expose("vim-change-selection").} =
  # infof"vimChangeSelection"
  editor.copy()
  let selections = editor.selections
  editor.selections = editor.selections.mapIt(it.first.toSelection)
  discard editor.delete(selections)

proc vimYankMove*(editor: TextDocumentEditor) {.expose("vim-yank-selection").} =
  # infof"vimYankSelection"
  editor.copy()
  editor.selections = editor.selections.mapIt(it.first.toSelection)

proc vimFinishMotion(editor: TextDocumentEditor) =
  let command = getOption[string]("editor.text.vim-motion-action")
  # infof"vimFinishMotion '{command}'"
  if command.len > 0:
    discard editor.runAction(command, newJArray())

  let nextMode = vimMotionNextMode.getOrDefault(editor.id, "normal")
  editor.setMode nextMode

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
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
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
      res.toSelection(it, which)
    )

  editor.vimFinishMotion()
  editor.scrollToCursor(Last)

proc moveSelectionEnd(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false) =
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
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
      res.toSelection(it, which)
    )

  editor.vimFinishMotion()
  editor.scrollToCursor(Last)

# todo
addCustomTextMove "vim-word", vimMotionWord
addCustomTextMove "vim-WORD", vimMotionWordBig
addCustomTextMove "vim-paragraph-inner", vimMotionParagraphInner
addCustomTextMove "vim-paragraph-outer", vimMotionParagraphOuter

proc vimDeleteLeft*(editor: TextDocumentEditor) =
  editor.copy()
  editor.deleteLeft()

proc vimDeleteRight*(editor: TextDocumentEditor) =
  editor.copy()
  editor.deleteRight()

expose "vim-delete-left", vimDeleteLeft

proc vimDeleteMove*(editor: TextDocumentEditor, move: string, inside: bool = false, which: SelectionCursor = SelectionCursor.Config, all: bool = true) {.expose("vim-delete-move").} =
  infof"vimDeleteMove: {move} {inside} {which} {all}"
  editor.copy()
  editor.deleteMove(move, inside, which, all)

proc vimMoveCursorColumn(editor: TextDocumentEditor, count: int) {.expose("vim-move-cursor-column").} =
  editor.moveCursorColumn(count)
  editor.vimFinishMotion()

proc vimMoveCursorLine(editor: TextDocumentEditor, count: int) {.expose("vim-move-cursor-line").} =
  editor.moveCursorLine(count)
  editor.vimFinishMotion()

proc vimMoveFirst(editor: TextDocumentEditor, move: string) {.expose("vim-move-first").} =
  editor.moveFirst(move)
  editor.vimFinishMotion()

proc vimMoveLast(editor: TextDocumentEditor, move: string) {.expose("vim-move-last").} =
  editor.moveLast(move)
  editor.vimFinishMotion()

proc vimMoveToEndOfLine(editor: TextDocumentEditor) =
  let count = editor.getCommandCount
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveLast("line")
  editor.setCommandCount 0
  editor.vimFinishMotion()
  editor.scrollToCursor Last

proc vimMoveCursorLineFirstChar(editor: TextDocumentEditor, direction: int) =
  editor.moveCursorLine(direction)
  editor.moveFirst "line-no-indent"
  editor.vimFinishMotion()

proc vimMoveToStartOfLine(editor: TextDocumentEditor) =
  let count = editor.getCommandCount
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveFirst "line-no-indent"
  editor.setCommandCount 0
  editor.vimFinishMotion()
  editor.scrollToCursor Last

var yankedLines: bool = false
proc vimPaste(editor: TextDocumentEditor, register: string = "") {.expose("vim-paste").} =
  if yankedLines:
    editor.moveLast "line"

  editor.paste register

proc loadVimKeybindings*() {.scriptActionWasmNims("load-vim-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadVimKeybindings: {t.elapsed.ms} ms"

  info "Applying Vim keybindings"

  clearCommands("editor.text")
  for id in getAllEditors():
    if id.isTextEditor(editor):
      editor.setMode("normal")

  setHandleInputs "editor.text", false
  setOption "editor.text.vim-motion-action", "vim-select-last-cursor"
  setOption "editor.text.cursor.movement.", "last"
  setOption "editor.text.cursor.wide.", true
  setOption "editor.text.default-mode", "normal"

  setModeChangedHandler proc(editor, oldMode, newMode: auto) =
    # infof"vim: handle mode change {oldMode} -> {newMode}"
    if newMode != "normal":
      editor.clearCurrentCommandHistory(retainLast=true)

    case newMode
    of "normal":
      setOption "editor.text.vim-motion-action", "vim-select-last-cursor"
      vimMotionNextMode[editor.id] = "normal"
      editor.selections = editor.selections.mapIt(it.last.toSelection)
      editor.saveCurrentCommandHistory()

    of "insert":
      setOption "editor.text.vim-motion-action", ""
      vimMotionNextMode[editor.id] = "insert"

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
  addCommand "editor", ":", "command-line"

  addTextCommandBlock "", "<C-e>": editor.setMode("normal")
  addTextCommandBlock "", "<ESCAPE>": editor.setMode("normal")

  # windowing
  addCommand "editor", "<C-w><RIGHT>", "prev-view"
  addCommand "editor", "<C-w>h", "prev-view"
  addCommand "editor", "<C-w><C-h>", "prev-view"
  addCommand "editor", "<C-w><LEFT>", "next-view"
  addCommand "editor", "<C-w>l", "next-view"
  addCommand "editor", "<C-w><C-l>", "next-view"
  addCommand "editor", "<C-w>w", "next-view"
  addCommand "editor", "<C-w><C-w>", "next-view"
  addCommand "editor", "<C-w>p", "open-previous-editor"
  addCommand "editor", "<C-w><C-p>", "open-previous-editor"
  addCommand "editor", "<C-w>q", "close-current-editor", true
  addCommand "editor", "<C-w>Q", "close-current-editor", false
  addCommand "editor", "<C-w><C-q>", "close-current-view"
  addCommand "editor", "<C-w>c", "close-current-view"
  addCommand "editor", "<C-w>o", "close-other-views"
  addCommand "editor", "<C-w><C-o>", "close-other-views"

  # not very vim like, but the windowing system works quite differently
  addCommand "editor", "<C-w>H", "move-current-view-prev"
  addCommand "editor", "<C-w>L", "move-current-view-next"
  addCommand "editor", "<C-w>W", "move-current-view-to-top"

  # completion
  addTextCommand "insert", "<C-p>", "get-completions"
  addTextCommand "insert", "<C-n>", "get-completions"
  addTextCommand "completion", "<ESCAPE>", "hide-completions"
  addTextCommand "completion", "<UP>", "select-prev-completion"
  addTextCommand "completion", "<C-p>", "select-prev-completion"
  addTextCommand "completion", "<DOWN>", "select-next-completion"
  addTextCommand "completion", "<C-n>", "select-next-completion"
  addTextCommand "completion", "<TAB>", "apply-selected-completion"
  addTextCommand "completion", "<ENTER>", "apply-selected-completion"

  # navigation (horizontal)

  addTextCommand "", "h", "vim-move-cursor-column", -1
  addTextCommand "", "<LEFT>", "vim-move-cursor-column", -1
  addTextCommand "", "<BACKSPACE>", "vim-move-cursor-column", -1

  addTextCommand "", "l", "vim-move-cursor-column", 1
  addTextCommand "", "<RIGHT>", "vim-move-cursor-column", 1
  addTextCommand "", "<SPACE>", "vim-move-cursor-column", 1

  # addTextCommand "", "0", "move-first", "line" # implemented above in number handling
  addTextCommand "", "<HOME>", "vim-move-first", "line"
  addTextCommand "", "^", "vim-move-first", "line-no-indent"

  addTextCommand "", "$", vimMoveToEndOfLine
  addTextCommand "", "<S-$>", vimMoveToEndOfLine
  addTextCommand "", "<END>", vimMoveToEndOfLine

  addTextCommand "", "g0", "vim-move-first", "line"
  addTextCommand "", "g^", "vim-move-first", "line-no-indent"

  addTextCommand "", "g$", vimMoveToEndOfLine
  addTextCommand "", "gm", "move-cursor-line-center"
  addTextCommand "", "gM", "move-cursor-center"

  addTextCommand "", "", "vim-move-last", "line"
  addTextCommand "", "<UP>", "vim-move-cursor-line", -1
  addTextCommand "", "<DOWN>", "vim-move-cursor-line", 1

  addTextCommandBlock "", "|":
    let count = editor.getCommandCount
    editor.selections = editor.selections.mapIt((it.last.line, count).toSelection)
    editor.setCommandCount 0
    editor.vimFinishMotion()
    editor.scrollToCursor Last

  # navigation (vertical)
  addTextCommand "", "k", "vim-move-cursor-line", -1
  addTextCommand "", "<UP>", "vim-move-cursor-line", -1
  addTextCommand "", "<C-p>", "vim-move-cursor-line", -1

  addTextCommand "", "j", "vim-move-cursor-line", 1
  addTextCommand "", "<DOWN>", "vim-move-cursor-line", 1
  addTextCommand "", "<ENTER>", "vim-move-cursor-line", 1
  addTextCommand "", "<C-n>", "vim-move-cursor-line", 1
  addTextCommand "", "<C-j>", "vim-move-cursor-line", 1

  addTextCommandBlock "", "-": vimMoveCursorLineFirstChar(editor, -1)
  addTextCommandBlock "", "+": vimMoveCursorLineFirstChar(editor, 1)

  addTextCommandBlock "", "_": vimMoveToStartOfLine(editor)
  addTextCommandBlock "", "G": vimMoveLast(editor, "file")

  addTextCommandBlock "", "gg":
    let count = editor.getCommandCount
    editor.selection = (count, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.setCommandCount 0
    editor.vimFinishMotion()
    editor.scrollToCursor Last

  addTextCommandBlock "", "G":
    let count = editor.getCommandCount
    let line = if count == 0: editor.lineCount - 1 else: count
    editor.selection = (line, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.setCommandCount 0
    editor.vimFinishMotion()
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
      editor.vimFinishMotion()
      editor.scrollToCursor Last

  addTextCommand "", "k", "vim-move-cursor-line", -1
  addTextCommand "", "j", "vim-move-cursor-line", 1
  addTextCommand "", "gk", "vim-move-cursor-line", -1
  addTextCommand "", "gj", "vim-move-cursor-line", 1

  # Scrolling
  addTextCommand "", "<C-e>", "scroll-lines", 1
  addTextCommandBlock "", "<C-d>": editor.vimMoveCursorLine(editor.screenLineCount div 2)
  addTextCommandBlock "", "<C-f>": editor.vimMoveCursorLine(editor.screenLineCount)
  addTextCommandBlock "", "<S-DOWN>": editor.vimMoveCursorLine(editor.screenLineCount)
  addTextCommandBlock "", "<PAGE_DOWN>": editor.vimMoveCursorLine(editor.screenLineCount)

  addTextCommand "", "<C-y>", "scroll-lines", -1
  addTextCommandBlock "", "<C-u>": editor.vimMoveCursorLine(-editor.screenLineCount div 2)
  addTextCommandBlock "", "<C-b>": editor.vimMoveCursorLine(-editor.screenLineCount)
  addTextCommandBlock "", "<S-UP>": editor.vimMoveCursorLine(-editor.screenLineCount)
  addTextCommandBlock "", "<PAGE_UP>": editor.vimMoveCursorLine(-editor.screenLineCount)

  addTextCommandBlock "", "z<ENTER>":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.vimFinishMotion()
    editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

  addTextCommandBlock "", "zt":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
      editor.vimFinishMotion()
    editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

  addTextCommandBlock "", "z.":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.vimFinishMotion()
    editor.centerCursor()

  addTextCommandBlock "", "zz":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
      editor.vimFinishMotion()
    editor.centerCursor()

  addTextCommandBlock "", "z-":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.vimFinishMotion()
    editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

  addTextCommandBlock "", "zb":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
      editor.vimFinishMotion()
    editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

  # Mode switches
  addTextCommandBlock "normal", "a":
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1).toSelection)
    editor.setMode "insert"
  addTextCommandBlock "", "A":
    editor.moveLast "line"
    editor.setMode "insert"
  addTextCommand "normal", "i", "set-mode", "insert"
  addTextCommandBlock "", "I":
    editor.moveFirst "line-no-indent"
    editor.setMode "insert"
  addTextCommandBlock "normal", "gI":
    editor.moveFirst "line"
    editor.setMode "insert"

  addTextCommandBlock "normal", "o":
    editor.moveLast "line"
    editor.insertText "\n"
    editor.setMode "insert"

  addTextCommandBlock "normal", "O":
    editor.moveFirst "line"
    editor.insertText "\n"
    editor.vimMoveCursorLine -1
    editor.setMode "insert"

  addTextCommand "", "<ESCAPE>", "set-mode", "normal"
  addTextCommand "", "<C-c>", "set-mode", "normal"

  # Text object motions
  addTextCommandBlock "", "w": editor.moveSelectionNext("vim-word", allowEmpty=true)
  addTextCommandBlock "", "<S-RIGHT>": editor.moveSelectionNext("vim-word", allowEmpty=true)
  addTextCommandBlock "", "W": editor.moveSelectionNext("vim-WORD", allowEmpty=true)
  addTextCommandBlock "", "<C-RIGHT>": editor.moveSelectionNext("vim-WORD", allowEmpty=true)
  addTextCommandBlock "", "e": editor.moveSelectionEnd("vim-word")
  addTextCommandBlock "", "E": editor.moveSelectionEnd("vim-WORD")
  addTextCommandBlock "", "b": editor.moveSelectionEnd("vim-word", backwards=true, allowEmpty=true)
  addTextCommandBlock "", "<S-LEFT>": editor.moveSelectionEnd("vim-word", backwards=true, allowEmpty=true)
  addTextCommandBlock "", "B": editor.moveSelectionEnd("vim-WORD", backwards=true, allowEmpty=true)
  addTextCommandBlock "", "<C-LEFT>": editor.moveSelectionEnd("vim-WORD", backwards=true, allowEmpty=true)
  addTextCommandBlock "", "ge": editor.moveSelectionNext("vim-word", backwards=true)
  addTextCommandBlock "", "gE": editor.moveSelectionNext("vim-WORD", backwards=true)

  addTextCommandBlock "", "}": editor.moveSelectionEnd("vim-paragraph-outer", allowEmpty=true)
  addTextCommandBlock "", "{": editor.moveSelectionNext("vim-paragraph-outer", backwards=true)

  # Deleting text
  addTextCommand "", "x", vimDeleteRight
  addTextCommand "", "<DELETE>", vimDeleteRight
  addTextCommand "", "X", vimDeleteLeft
  addTextCommandBlock "", "d":
    editor.setMode "delete-move"
    setOption "editor.text.vim-motion-action", "vim-delete-selection"
    vimMotionNextMode[editor.id] = "normal"

  addTextCommandBlock "", "c":
    editor.setMode "change-move"
    setOption "editor.text.vim-motion-action", "vim-change-selection"
    vimMotionNextMode[editor.id] = "insert"

  addTextCommandBlock "", "y":
    editor.setMode "yank-move"
    setOption "editor.text.vim-motion-action", "vim-yank-selection"
    vimMotionNextMode[editor.id] = "normal"

  # move mode
  setHandleInputs "editor.text.delete-move", false
  setOption "editor.text.cursor.wide.delete-move", true
  setOption "editor.text.cursor.movement.delete-move", "last"

  setHandleInputs "editor.text.change-move", false
  setOption "editor.text.cursor.wide.change-move", true
  setOption "editor.text.cursor.movement.change-move", "last"

  setHandleInputs "editor.text.yank-move", false
  setOption "editor.text.cursor.wide.yank-move", true
  setOption "editor.text.cursor.movement.yank-move", "last"

  proc addTextExtraMotionCommands(mode: static[string]) =
    addTextCommandBlock mode, "iw":
      editor.selectMove("vim-word", true, SelectionCursor.Last)
      editor.vimFinishMotion()
    addTextCommandBlock mode, "iW":
      editor.selectMove("vim-WORD", true, SelectionCursor.Last)
      editor.vimFinishMotion()
    addTextCommandBlock mode, "ip":
      editor.selectMove("vim-paragraph-inner", true, SelectionCursor.Last)
      editor.vimFinishMotion()
    addTextCommandBlock mode, "ap":
      editor.selectMove("vim-paragraph-outer", true, SelectionCursor.Last)
      editor.vimFinishMotion()

  addTextExtraMotionCommands "delete-move"
  addTextExtraMotionCommands "change-move"
  addTextExtraMotionCommands "yank-move"
  addTextExtraMotionCommands "visual"

  addTextCommandBlock "delete-move", "d":
    yankedLines = true
    editor.selectMove("line-prev", true, SelectionCursor.Last)
    editor.vimFinishMotion()

  addTextCommandBlock "change-move", "c":
    yankedLines = true
    editor.selectMove("line-prev", true, SelectionCursor.Last)
    editor.vimFinishMotion()

  addTextCommandBlock "yank-move", "y":
    yankedLines = true
    editor.selectMove("line-prev", true, SelectionCursor.Last)
    editor.vimFinishMotion()

  addTextCommand "", "u", "undo"
  addTextCommand "", "U", "redo"
  addTextCommand "", "<C-r>", "redo"
  addTextCommand "", "p", "vim-paste"

  # Insert mode
  setHandleInputs "editor.text.insert", true
  setOption "editor.text.cursor.wide.insert", false
  addTextCommand "insert", "<ENTER>", "insert-text", "\n"
  addTextCommand "insert", "<C-m>", "insert-text", "\n"
  addTextCommand "insert", "<C-j>", "insert-text", "\n"

  addTextCommand "insert", "<C-r>", "set-mode", "insert-register"
  setHandleInputs "editor.text.insert-register", true
  setTextInputHandler "insert-register", proc(editor: TextDocumentEditor, input: string): bool =
    editor.vimPaste input
    editor.setMode "insert"
    return true
  addTextCommandBlock "insert-register", "<SPACE>":
    editor.vimPaste getVimDefaultRegister()
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
  addTextCommandBlock "", "v":
    editor.setMode "visual"
    setOption "editor.text.vim-motion-action", ""
    vimMotionNextMode[editor.id] = "visual"

  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"

  addTextCommandBlock "visual", "y":
    editor.copy getVimDefaultRegister()
    editor.setMode "normal"
    editor.selections = editor.selections.mapIt(it.first.toSelection)

  addTextCommandBlock "visual", "d":
    editor.vimDeleteSelection()
    editor.setMode("normal")

  addTextCommandBlock "visual", "c":
    editor.vimDeleteSelection()
    editor.setMode("insert")
