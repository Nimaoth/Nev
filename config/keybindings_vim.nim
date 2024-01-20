import std/[strutils, setutils, parseutils, macros, genasts]
import absytree_runtime, keybindings_normal
import misc/[timer, util, myjsonutils]


infof"import vim keybindings"

var vimMotionNextMode = initTable[EditorId, string]()

type VimTextObjectRange* = enum Inner, Outer, CurrentToEnd

macro addMoveCommandWithCount*(mode: string, keys: string, move: string, args: varargs[untyped]) =
  let (stmts, str) = bindArgs(args)
  return genAst(stmts, mode, keys, move, str):
    stmts
    addCommandScript(getContextWithMode("editor.text", mode) & "#move", "", keysPrefix & "<?-count>" & keys, move, str & " <#move.count>")

proc addMoveCommandWithCount*(mode: string, keys: string, action: proc(editor: TextDocumentEditor, count: int): void) =
  addCommand getContextWithMode("editor.text", mode) & "#move", "<?-count>" & keys, "<#move.count>", action

template addMoveCommandWithCountBlock*(mode: string, keys: string, body: untyped): untyped =
  addMoveCommandWithCount mode, keys, proc(editor: TextDocumentEditor, count: int): void =
    let editor {.inject.} = editor
    let count {.inject.} = count
    body

template addMoveCommand*(mode: string, keys: string, move: string, args: varargs[untyped]) =
  addTextCommand mode & "#move", keys, move, args

template addMoveCommandBlock*(mode: string, keys: string, body: untyped): untyped =
  addTextCommandBlock mode & "#move", keys:
    body

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

proc vimSelectLast(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-select-last").} =
  infof"vimSelectLast '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.selections = editor.selections.mapIt(it.last.toSelection)

proc vimDeleteSelection(editor: TextDocumentEditor) {.expose("vim-delete-selection").} =
  editor.copy()
  let selections = editor.selections
  editor.selections = editor.selections.mapIt(it.normalized.first.toSelection)
  discard editor.delete(selections)
  editor.setMode "normal"

proc vimChangeSelection*(editor: TextDocumentEditor) {.expose("vim-change-selection").} =
  editor.copy()
  let selections = editor.selections
  editor.selections = editor.selections.mapIt(it.normalized.first.toSelection)
  discard editor.delete(selections)
  editor.setMode "insert"

proc vimYankSelection*(editor: TextDocumentEditor) {.expose("vim-yank-selection").} =
  editor.copy()
  editor.selections = editor.selections.mapIt(it.normalized.first.toSelection)
  editor.setMode "normal"

proc vimSelectMove(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-select-move").} =
  infof"vimSelectMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)

proc vimDeleteMove(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-delete-move").} =
  infof"vimDeleteMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.vimDeleteSelection()

proc vimChangeMove(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-change-move").} =
  infof"vimChangeMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.vimChangeSelection()

proc vimYankMove(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-yank-move").} =
  infof"vimYankMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.vimYankSelection()

proc vimFinishMotion(editor: TextDocumentEditor) =
  let command = getOption[string]("editor.text.vim-motion-action")
  let commandCount = editor.getCommandCount
  # let commandCount = getOption[int]("text.command-count", 1)
  # infof"finish motion {moveCommandCount}, {commandCount} {command}"
  if commandCount > 1:
    return

  # infof"vimFinishMotion '{command}'"
  if command.len > 0:
    var args = newJArray()
    # args.add newJString("move-before " & input)
    discard editor.runAction(command, args)
    setOption("editor.text.vim-motion-action", "")

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

proc vimMoveTo*(editor: TextDocumentEditor, target: string, before: bool, count: int = 1) {.expose("vim-move-to").} =
  infof"vimMoveTo '{target}' {before}"
  let target = if target.len == 1:
    target
  elif target == "<SPACE>":
    " "
  else:
    return

  for _ in 0..<max(1, count):
    editor.moveCursorTo(target)
  if not before:
    editor.moveCursorColumn(1)

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

proc vimSelectTextObject(editor: TextDocumentEditor, textObject: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.expose("vim-select-text-object").} =
  infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count})"

  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      var resultSelection = it
      infof"-> {resultSelection}"

      for i, selection in enumerateTextObjects(editor, res, textObject, backwards):
        if i == max(count, 1):
          break
        infof"{i}: {res} -> {selection}"
        resultSelection = resultSelection or selection

      infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count}): {resultSelection}"
      if backwards:
        resultSelection.reverse
      else:
        resultSelection
    )

  editor.scrollToCursor(Last)

proc moveSelectionNext(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.expose("move-selection-next").} =
  infof"moveSelectionNext '{move}' {count} {backwards} {allowEmpty}"
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      for k in 0..<max(1, count):
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
      echo res, ", ", it, ", ", which
      res.toSelection(it, which)
    )

  editor.scrollToCursor(Last)

proc moveSelectionEnd(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.expose("move-selection-end").} =
  infof"moveSelectionEnd '{move}' {count} {backwards} {allowEmpty}"
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      for k in 0..<max(1, count):
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

proc vimMoveCursorColumn(editor: TextDocumentEditor, direction: int, count: int = 1) {.expose("vim-move-cursor-column").} =
  editor.moveCursorColumn(direction * max(count, 1))

proc vimMoveCursorLine(editor: TextDocumentEditor, direction: int, count: int = 1) {.expose("vim-move-cursor-line").} =
  editor.moveCursorLine(direction * max(count, 1))

proc vimMoveFirst(editor: TextDocumentEditor, move: string) {.expose("vim-move-first").} =
  editor.moveFirst(move)

proc vimMoveLast(editor: TextDocumentEditor, move: string) {.expose("vim-move-last").} =
  editor.moveLast(move)

proc vimMoveToEndOfLine(editor: TextDocumentEditor, count: int = 1) =
  infof"vimMoveToEndOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveLast("line")
  editor.scrollToCursor Last

proc vimMoveCursorLineFirstChar(editor: TextDocumentEditor, direction: int, count: int = 1) =
  editor.moveCursorLine(direction * max(count, 1))
  editor.moveFirst "line-no-indent"

proc vimMoveToStartOfLine(editor: TextDocumentEditor, count: int = 1) =
  infof"vimMoveToStartOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveFirst "line-no-indent"
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
  setOption "editor.text.cursor.movement.normal", "last"
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

  addTextCommand "#count", "<-1-9><o-0-9>", ""
  addTextCommand "visual#count", "<-1-9><o-0-9>", ""
  addTextCommand "normal#count", "<-1-9><o-0-9>", ""

  addTextCommand "", "<move>", "vim-select-last <move>"
  addTextCommand "", "<?-count>d<move>", """vim-delete-move <move> <#count>"""
  addTextCommand "", "<?-count>c<move>", """vim-change-move <move> <#count>"""
  addTextCommand "", "<?-count>y<move>", """vim-yank-move <move> <#count>"""

  addTextCommand "", "<?-count>d<text_object>", """vim-delete-move <text_object> <#count>"""
  addTextCommand "", "<?-count>c<text_object>", """vim-change-move <text_object> <#count>"""
  addTextCommand "", "<?-count>y<text_object>", """vim-yank-move <text_object> <#count>"""

  addTextCommand "#text_object", "<?-count>iw", "vim-select-text-object \"vim-word\" false true <#text_object.count> \"Inner\""
  addTextCommand "#text_object", "<?-count>aw", "vim-select-text-object \"vim-word\" false true <#text_object.count> \"Outer\""

  addTextCommand "visual#text_object", "<?-count>iw", "vim-select-text-object \"vim-word\" false true <#text_object.count> \"Inner\""
  addTextCommand "visual#text_object", "<?-count>aw", "vim-select-text-object \"vim-word\" false true <#text_object.count> \"Outer\""

  addTextCommand "visual", "<?-count><text_object>", """vim-select-move <text_object> <#count>"""

  # Visual mode
  addTextCommandBlock "", "v":
    editor.setMode "visual"
    setOption "editor.text.vim-motion-action", ""
    vimMotionNextMode[editor.id] = "visual"

  addTextCommand "", "u", "undo"
  addTextCommand "", "U", "redo"
  addTextCommand "", "<C-r>", "redo"
  addTextCommand "", "p", "vim-paste"


  # Normal mode
  addCommand "editor", ":", "command-line"

  addTextCommandBlock "", "<C-e>": editor.setMode("normal")

  addTextCommandBlock "", "<C-e>": editor.setMode("normal")
  addTextCommandBlock "", "<ESCAPE>": editor.setMode("normal")

  # windowing
  proc defineWindowingCommands(prefix: string) =
    withKeys prefix:
      addCommand "editor", "h", "prev-view"
      addCommand "editor", "<C-h>", "prev-view"
      addCommand "editor", "<LEFT>", "prev-view"
      addCommand "editor", "l", "next-view"
      addCommand "editor", "<C-l>", "next-view"
      addCommand "editor", "<RIGHT>", "next-view"
      addCommand "editor", "w", "next-view"
      addCommand "editor", prefix, "next-view"
      addCommand "editor", "p", "open-previous-editor"
      addCommand "editor", "<C-p>", "open-previous-editor"
      addCommand "editor", "q", "close-current-editor", true
      addCommand "editor", "Q", "close-current-editor", false
      addCommand "editor", "<C-q>", "close-current-view"
      addCommand "editor", "c", "close-current-view"
      addCommand "editor", "o", "close-other-views"
      addCommand "editor", "<C-o>", "close-other-views"

      # not very vim like, but the windowing system works quite differently
      addCommand "editor", "H", "move-current-view-prev"
      addCommand "editor", "L", "move-current-view-next"
      addCommand "editor", "W", "move-current-view-to-top"

  # In the browser C-w closes the tab, so we use A-w instead
  if getBackend() == Browser:
    defineWindowingCommands "<A-w>"
  else:
    defineWindowingCommands "<C-w>"

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

  addMoveCommandWithCount "", "h", "vim-move-cursor-column", -1
  addMoveCommandWithCount "", "<LEFT>", "vim-move-cursor-column", -1
  addMoveCommandWithCount "", "<BACKSPACE>", "vim-move-cursor-column", -1

  addMoveCommandWithCount "", "l", "vim-move-cursor-column", 1
  addMoveCommandWithCount "", "<RIGHT>", "vim-move-cursor-column", 1
  addMoveCommandWithCount "", "<SPACE>", "vim-move-cursor-column", 1

  addMoveCommand "", "0", "vim-move-first", "line"
  addMoveCommand "", "<HOME>", "vim-move-first", "line"
  addMoveCommand "", "^", "vim-move-first", "line-no-indent"

  addMoveCommandWithCount "", "$", vimMoveToEndOfLine
  addMoveCommandWithCount "", "<S-$>", vimMoveToEndOfLine
  addMoveCommandWithCount "", "<END>", vimMoveToEndOfLine

  addMoveCommand "", "g0", "vim-move-first", "line"
  addMoveCommand "", "g^", "vim-move-first", "line-no-indent"

  addMoveCommandWithCount "", "g$", vimMoveToEndOfLine
  addMoveCommand "", "gm", "move-cursor-line-center"
  addMoveCommand "", "gM", "move-cursor-center"

  addMoveCommandWithCountBlock "", "|":
    editor.selections = editor.selections.mapIt((it.last.line, count).toSelection)
    editor.scrollToCursor Last

  # navigation (vertical)
  addMoveCommandWithCount "", "k", "vim-move-cursor-line", -1
  addMoveCommandWithCount "", "<UP>", "vim-move-cursor-line", -1
  addMoveCommandWithCount "", "<C-p>", "vim-move-cursor-line", -1

  addMoveCommandWithCount "", "j", "vim-move-cursor-line", 1
  addMoveCommandWithCount "", "<DOWN>", "vim-move-cursor-line", 1
  addMoveCommandWithCount "", "<ENTER>", "vim-move-cursor-line", 1
  addMoveCommandWithCount "", "<C-n>", "vim-move-cursor-line", 1
  addMoveCommandWithCount "", "<C-j>", "vim-move-cursor-line", 1

  addMoveCommandWithCountBlock "", "-": vimMoveCursorLineFirstChar(editor, -1, count)
  addMoveCommandWithCountBlock "", "+": vimMoveCursorLineFirstChar(editor, 1, count)

  addMoveCommandWithCountBlock "", "_": vimMoveToStartOfLine(editor, count)

  addMoveCommandWithCountBlock "", "gg":
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.selection = (count, 0).toSelection(editor.selection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last

  addMoveCommandWithCountBlock "", "G":
    let line = if count == 0: editor.lineCount - 1 else: count
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.selection = (line, 0).toSelection(editor.selection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last

  addMoveCommandWithCountBlock "", "<S-%>":
    infof"{count} %"
    if count == 0:
      # todo: find matching bracket
      discard
    else:
      let line = clamp((count * editor.lineCount) div 100, 0, editor.lineCount - 1)
      let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
      editor.selection = (line, 0).toSelection(editor.selection, which)
      editor.moveFirst "line-no-indent"
      editor.scrollToCursor Last

  addMoveCommandWithCount "", "k", "vim-move-cursor-line", -1
  addMoveCommandWithCount "", "j", "vim-move-cursor-line", 1
  addMoveCommandWithCount "", "gk", "vim-move-cursor-line", -1
  addMoveCommandWithCount "", "gj", "vim-move-cursor-line", 1

  # Scrolling
  addTextCommand "", "<C-e>", "scroll-lines", 1
  addMoveCommandWithCountBlock "", "<C-d>": editor.vimMoveCursorLine(editor.screenLineCount div 2, count)
  addMoveCommandWithCountBlock "", "<C-f>": editor.vimMoveCursorLine(editor.screenLineCount, count)
  addMoveCommandWithCountBlock "", "<S-DOWN>": editor.vimMoveCursorLine(editor.screenLineCount, count)
  addMoveCommandWithCountBlock "", "<PAGE_DOWN>": editor.vimMoveCursorLine(editor.screenLineCount, count)

  addTextCommand "", "<C-y>", "scroll-lines", -1
  addMoveCommandWithCountBlock "", "<C-u>": editor.vimMoveCursorLine(-editor.screenLineCount div 2, count)
  addMoveCommandWithCountBlock "", "<C-b>": editor.vimMoveCursorLine(-editor.screenLineCount, count)
  addMoveCommandWithCountBlock "", "<S-UP>": editor.vimMoveCursorLine(-editor.screenLineCount, count)
  addMoveCommandWithCountBlock "", "<PAGE_UP>": editor.vimMoveCursorLine(-editor.screenLineCount, count)

  addTextCommandBlock "", "z<ENTER>":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
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

  addMoveCommandWithCount "", "w", "move-selection-next \"vim-word\" false true"
  addMoveCommandWithCount "", "<S-RIGHT>", "move-selection-next \"vim-word\" false true"
  addMoveCommandWithCount "", "W", "move-selection-next \"vim-WORD\" false true"
  addMoveCommandWithCount "", "<C-RIGHT>", "move-selection-next \"vim-WORD\" false true"
  addMoveCommandWithCount "", "e", "move-selection-end \"vim-word\" false false"
  addMoveCommandWithCount "", "E", "move-selection-end \"vim-WORD\" false false"
  addMoveCommandWithCount "", "b", "move-selection-end \"vim-word\" true true"
  addMoveCommandWithCount "", "<S-LEFT>", "move-selection-end \"vim-word\" true true"
  addMoveCommandWithCount "", "B", "move-selection-end \"vim-WORD\" true true"
  addMoveCommandWithCount "", "<C-LEFT>", "move-selection-end \"vim-WORD\" true true"
  addMoveCommandWithCount "", "ge", "move-selection-next \"vim-word\" true false"
  addMoveCommandWithCount "", "gE", "move-selection-next \"vim-WORD\" true false"

  addMoveCommandWithCount "", "}", "move-selection-end \"vim-paragraph-outer\" false true"
  addMoveCommandWithCount "", "{", "move-selection-next \"vim-paragraph-outer\" true false"

  addMoveCommandWithCount "", "f<ANY>", "vim-move-to <move.ANY> false"
  addMoveCommandWithCount "", "t<ANY>", "vim-move-to <move.ANY> true"

  addTextCommandBlock "", "dd":
    yankedLines = true
    editor.selectMove("line-next", true, SelectionCursor.Last)
    editor.copy()
    let selections = editor.selections
    editor.selections = editor.selections.mapIt(it.first.toSelection)
    discard editor.delete(selections)

  addTextCommandBlock "", "cc":
    yankedLines = true
    editor.selectMove("line-next", true, SelectionCursor.Last)
    editor.copy()
    let selections = editor.selections
    editor.selections = editor.selections.mapIt(it.first.toSelection)
    discard editor.delete(selections)
    editor.setMode "insert"

  addTextCommandBlock "", "yy":
    yankedLines = true
    editor.selectMove("line-next", true, SelectionCursor.Last)
    editor.copy()
    editor.selections = editor.selections.mapIt(it.first.toSelection)

  # # Deleting text
  addTextCommand "", "x", vimDeleteRight
  addTextCommand "", "<DELETE>", vimDeleteRight
  addTextCommand "", "X", vimDeleteLeft

  # proc addTextExtraMotionCommands(mode: static[string]) =
  #   addTextCommandBlock mode, "iw":
  #     editor.selectMove("vim-word", true, SelectionCursor.Last)
  #     editor.vimFinishMotion()
  #   addTextCommandBlock mode, "iW":
  #     editor.selectMove("vim-WORD", true, SelectionCursor.Last)
  #     editor.vimFinishMotion()
  #   addTextCommandBlock mode, "ip":
  #     editor.selectMove("vim-paragraph-inner", true, SelectionCursor.Last)
  #     editor.vimFinishMotion()
  #   addTextCommandBlock mode, "ap":
  #     editor.selectMove("vim-paragraph-outer", true, SelectionCursor.Last)
  #     editor.vimFinishMotion()

  # addTextExtraMotionCommands "delete-move"
  # addTextExtraMotionCommands "change-move"
  # addTextExtraMotionCommands "yank-move"
  # addTextExtraMotionCommands "visual"

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

  addTextCommand "visual", "y", "vim-yank-selection"
  addTextCommand "visual", "d", "vim-delete-selection"
  addTextCommand "visual", "c", "vim-change-selection"
