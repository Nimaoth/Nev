include abs
import std/[strutils, sugar, streams]

proc loadNormalBindings*()
proc loadVimBindings*()
proc loadHelixBindings*()

include keybindings_vim
include keybindings_helix
include keybindings_normal

# {.line: ("config.nims", 4).}

proc handleAction*(action: string, arg: string): bool =
  log "[script] ", action, ", ", arg

  case action
  of "set-max-loop-iterations":
    setOption("ast.max-loop-iterations", arg.parseInt)

  of "command-line":
    commandLine(arg)
    if getActiveEditor().isTextEditor(editor):
      editor.setMode "insert"

  else: return false

  return true

proc handlePopupAction*(popup: PopupId, action: string, arg: string): bool =
  case action:
  of "home":
    for i in 0..<3:
      popup.runAction "prev"
  of "end":
    for i in 0..<3:
      popup.runAction "next"

  else: return false

  return true

proc handleDocumentEditorAction(id: EditorId, action: string, args: JsonNode): bool =
  return false

func charCategory(c: char): int =
  if c.isAlphaNumeric or c == '_': return 0
  if c == ' ' or c == '\t': return 1
  return 2

proc cursor(selection: Selection, which: SelectionCursor): Cursor =
  case which
  of Config:
    if getActiveEditor().isTextEditor(editor):
      return selection.cursor(getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
    else:
      log "[script] [error] Failed to get cursor from selection using config."
      return selection.last
  of Both:
    return selection.last
  of First:
    return selection.first
  of Last, LastToFirst:
    return selection.last


proc findWordBoundary(editor: TextDocumentEditor, cursor: Cursor): Selection =
  let line = editor.getLine cursor.line
  result = cursor.toSelection

  # Search to the left
  while result.first.column > 0 and result.first.column <= line.len:
    result.first.column -= 1
    if result.first.column > 0:
      let leftCategory = line[result.first.column - 1].charCategory
      let rightCategory = line[result.first.column].charCategory
      if leftCategory != rightCategory:
        break

  # Search to the right
  while result.last.column >= 0 and result.last.column < line.len:
    result.last.column += 1
    if result.last.column < line.len:
      let leftCategory = line[result.last.column - 1].charCategory
      let rightCategory = line[result.last.column].charCategory
      if leftCategory != rightCategory:
        break

proc getSelectionForMove(editor: TextDocumentEditor, cursor: Cursor, move: string, count: int = 0): Selection =
  case move
  of "word":
    result = editor.findWordBoundary(cursor)
    for _ in 1..<count:
      result = result or editor.findWordBoundary(result.last) or editor.findWordBoundary(result.first)

  of "word-line":
    let line = editor.getLine cursor.line
    result = editor.findWordBoundary(cursor)
    if cursor.column == 0 and cursor.line > 0:
      result.first = (cursor.line - 1, editor.getLine(cursor.line - 1).len)
    if cursor.column == line.len and cursor.line < editor.getLineCount - 1:
      result.last = (cursor.line + 1, 0)

    for _ in 1..<count:
      result = result or editor.findWordBoundary(result.last) or editor.findWordBoundary(result.first)
      let line = editor.getLine result.last.line
      if result.first.column == 0 and result.first.line > 0:
        result.first = (result.first.line - 1, editor.getLine(result.first.line - 1).len)
      if result.last.column == line.len and result.last.line < editor.getLineCount - 1:
        result.last = (result.last.line + 1, 0)

  of "word-back":
    return editor.getSelectionForMove(cursor, "word", count).reverse

  of "word-line-back":
    return editor.getSelectionForMove(cursor, "word-line", count).reverse

  of "line":
    result = ((cursor.line, 0), (cursor.line, editor.getLine(cursor.line).len))

  of "line-next":
    result = ((cursor.line, 0), (cursor.line, editor.getLine(cursor.line).len))
    if result.last.line + 1 < editor.getLineCount:
      result.last = (result.last.line + 1, 0)
    for _ in 1..<count:
      result = result or ((result.last.line, 0), (result.last.line, editor.getLine(result.last.line).len))
      if result.last.line + 1 < editor.getLineCount:
        result.last = (result.last.line + 1, 0)

  of "file":
    result.first = (0, 0)
    let line = editor.getLineCount - 1
    result.last = (line, editor.getLine(line).len)

  else:
    if move.startsWith("move-to "):
      let str = move[8..^1]
      let line = editor.getLine cursor.line
      result = cursor.toSelection
      let index = line.find(str, cursor.column)
      if index >= 0:
        result.last = (cursor.line, index + 1)
      for _ in 1..<count:
        let index = line.find(str, result.last.column)
        if index >= 0:
          result.last = (result.last.line, index + 1)

    elif move.startsWith("move-before "):
      let str = move[12..^1]
      let line = editor.getLine cursor.line
      result = cursor.toSelection
      let index = line.find(str, cursor.column + 1)
      if index >= 0:
        result.last = (cursor.line, index)
      for _ in 1..<count:
        let index = line.find(str, result.last.column + 1)
        if index >= 0:
          result.last = (result.last.line, index)
    else:
      result = cursor.toSelection
      log fmt"[error] Unknown move '{move}'"

proc handleTextEditorAction(editor: TextDocumentEditor, action: string, args: JsonNode): bool =
  # echo "handleTextEditorAction ", action, ", ", args

  case action
  of "set-move":
    setOption[int]("text.move-count", editor.getCommandCount)
    editor.setMode getOption[string]("text.move-next-mode")
    editor.setCommandCount getOption[int]("text.move-command-count")
    discard editor.runAction(getOption[string]("text.move-action"), args)
    setOption[string]("text.move-action", "")

  of "delete-move":
    let arg = args[0].str
    let which = if args.len < 2: Config else: parseEnum[SelectionCursor](args[1].str, Config)
    let count = getOption[int]("text.move-count")
    let inside = editor.getFlag("move-inside")

    # echo fmt"delete-move {arg}, {which}, {count}, {inside}"

    var selection = editor.getSelectionForMove(editor.selection.last, arg, count)
    if not inside:
      selection.first = editor.selection.last
    editor.selection = editor.delete(selection).toSelection
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  of "select-move":
    let arg = args[0].str
    let count = getOption[int]("text.move-count")
    editor.selection = editor.getSelectionForMove(editor.selection.last, arg, count)
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  of "change-move":
    let arg = args[0].str
    let count = getOption[int]("text.move-count")
    let inside = editor.getFlag("move-inside")
    var selection = editor.getSelectionForMove(editor.selection.last, arg, count)
    if not inside:
      selection.first = editor.selection.last
    editor.selection = editor.delete(selection).toSelection
    editor.scrollToCursor(Last)
    editor.updateTargetColumn(Last)

  of "move-last":
    let arg = args[0].str
    let which = if args.len < 2: Config else: parseEnum[SelectionCursor](args[1].str, Config)
    let selection = editor.selection
    let targetRange = editor.getSelectionForMove(selection.cursor(which), arg)

    case which
    of Config:
      editor.selection = targetRange.last.toSelection(selection, getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
    else:
      editor.selection = targetRange.last.toSelection(selection, which)
    editor.scrollToCursor(which)
    editor.updateTargetColumn(which)

  of "move-first":
    let arg = args[0].str
    let which = if args.len < 2: Config else: parseEnum[SelectionCursor](args[1].str, Config)
    let selection = editor.selection
    let targetRange = editor.getSelectionForMove(selection.cursor(which), arg)

    case which
    of Config:
      editor.selection = targetRange.first.toSelection(selection, getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
    else:
      editor.selection = targetRange.first.toSelection(selection, which)
    editor.scrollToCursor(which)
    editor.updateTargetColumn(which)

  else: return false
  return true

proc handleAstEditorAction(editor: AstDocumentEditor, action: string, args: JsonNode): bool =
  case action

  else: return false
  return true

proc postInitialize*() =
  log "[script] postInitialize()"

  # openFile "temp/test.rs"
  openFile "temp/test.nim"
  # openFile "src/absytree.nim"
  setLayout "fibonacci"
  changeLayoutProp("main-split", -0.2)

clearCommands "editor"
clearCommands "editor.ast"
clearCommands "editor.ast.completion"
clearCommands "editor.ast.goto"
clearCommands "editor.ast.goto"
clearCommands "commandLine"
clearCommands "popup.selector"

addCommand "editor", "<C-x><C-x>", "quit"
addCommand "editor", "<CAS-r>", "reload-config"

setOption "ast.scroll-speed", 60
setOption "editor.text.lsp.zig.path", "zls"

addCommand "editor", "<SPACE>tt", proc() =
  setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") * 2, 1, 1000000))
  echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

addCommand "editor", "<SPACE>tr", proc() =
  setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") div 2, 1, 1000000))
  echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

addCommand "editor", "<C-SPACE>ft", "toggle-flag", "editor.log-frame-time"
# addCommand "editor", "<C-SPACE>pp", proc() =
  # toggleFlag "editor.poll"
  # echo "-> ", getFlag("editor.poll")
addCommand "editor", "<C-SPACE>td", "toggle-flag", "ast.render-vnode-depth"
addCommand "editor", "<C-SPACE>l", "toggle-flag", "logging"
addCommand "editor", "<C-SPACE>fs", "toggle-flag", "render-selected-value"
addCommand "editor", "<C-SPACE>fr", "toggle-flag", "log-render-duration"
addCommand "editor", "<C-SPACE>fd", "toggle-flag", "render-debug-info"
addCommand "editor", "<C-SPACE>fo", "toggle-flag", "render-execution-output"
addCommand "editor", "<C-SPACE>fg", "toggle-flag", "text.print-scopes"
addCommand "editor", "<C-SPACE>fm", "toggle-flag", "text.print-matches"
addCommand "editor", "<C-SPACE>fh", "toggle-flag", "text.show-node-highlight"
addCommand "editor", "<C-5>", proc() =
  setOption("text.node-highlight-parent-index", clamp(getOption[int]("text.node-highlight-parent-index") - 1, 0, 100000))
  echo "text.node-highlight-parent-index: ", getOption[int]("text.node-highlight-parent-index")
addCommand "editor", "<C-6>", proc() =
  setOption("text.node-highlight-parent-index", clamp(getOption[int]("text.node-highlight-parent-index") + 1, 0, 100000))
  echo "text.node-highlight-parent-index: ", getOption[int]("text.node-highlight-parent-index")
addCommand "editor", "<C-2>", proc() =
  setOption("text.node-highlight-sibling-index", clamp(getOption[int]("text.node-highlight-sibling-index") - 1, -100000, 100000))
  echo "text.node-highlight-sibling-index: ", getOption[int]("text.node-highlight-sibling-index")
addCommand "editor", "<C-3>", proc() =
  setOption("text.node-highlight-sibling-index", clamp(getOption[int]("text.node-highlight-sibling-index") + 1, -100000, 100000))
  echo "text.node-highlight-sibling-index: ", getOption[int]("text.node-highlight-sibling-index")

addCommand "editor", "<C-u>", "set-mode", "test-mode"
setConsumeAllInput "editor.test-mode", true
addCommand "editor.test-mode", "<ESCAPE>", "set-mode", ""
addCommand "editor.test-mode", "-","change-font-size", -1
addCommand "editor.test-mode", "+","change-font-size", +1

addCommand "editor", "<C-i>", "set-mode", "test-mode2"
setOption "editor.custom-mode-on-top", false
addCommand "editor.test-mode2", "<ESCAPE>", "set-mode", ""
addCommand "editor.test-mode2", "s","change-font-size", -1
addCommand "editor.test-mode2", "d","change-font-size", +1

addCommand "editor", "<SPACE>ff", "log-options"
addCommand "editor", "<ESCAPE>", "escape"
addCommand "editor", "<C-l><C-h>", "change-font-size", -1
addCommand "editor", "<C-l><C-f>", "change-font-size", 1
# addCommand "editor", "<C-g>", "toggle-status-bar-location"
addCommand "editor", "<C-l><C-n>", "set-layout", "horizontal"
addCommand "editor", "<C-l><C-r>", "set-layout", "vertical"
addCommand "editor", "<C-l><C-t>", "set-layout", "fibonacci"
addCommand "editor", "<CA-h>", "change-layout-prop", "main-split", -0.05
addCommand "editor", "<CA-f>", "change-layout-prop", "main-split", 0.05
addCommand "editor", "<CA-v>", "create-view"
addCommand "editor", "<CA-a>", "create-keybind-autocomplete-view"
addCommand "editor", "<CA-x>", "close-current-view"
addCommand "editor", "<CA-n>", "prev-view"
addCommand "editor", "<CA-t>", "next-view"
addCommand "editor", "<CS-n>", "move-current-view-prev"
addCommand "editor", "<CS-t>", "move-current-view-next"
addCommand "editor", "<CA-r>", "move-current-view-to-top"
addCommand "editor", "<C-s>", "write-file"
addCommand "editor", "<CS-r>", "load-file"
addCommand "editor", "<C-p>", "command-line"
addCommand "editor", "<C-l>tt", "choose-theme"
addCommand "editor", "<C-g>f", "choose-file", "new"

addCommand "editor", "<C-b>n", () => loadNormalBindings()
addCommand "editor", "<C-b>v", () => loadVimBindings()
addCommand "editor", "<C-b>h", () => loadHelixBindings()

addCommand "commandLine", "<ESCAPE>", "exit-command-line"
addCommand "commandLine", "<ENTER>", "execute-command-line"

addCommand "popup.selector", "<ENTER>", "accept"
addCommand "popup.selector", "<TAB>", "accept"
addCommand "popup.selector", "<ESCAPE>", "cancel"
addCommand "popup.selector", "<UP>", "prev"
addCommand "popup.selector", "<DOWN>", "next"
addCommand "popup.selector", "<HOME>", "home"
addCommand "popup.selector", "<END>", "end"

# loadHelixBindings()
loadVimBindings()

# addCommand "editor.ast", "<A-LEFT>", "move-cursor", "-1"
addAstCommand "<A-LEFT>": editor.moveCursor(-1)
addCommand "editor.ast", "<A-RIGHT>", "move-cursor", 1
addCommand "editor.ast", "<A-UP>", "move-cursor-up"
addCommand "editor.ast", "<A-DOWN>", "move-cursor-down"
addCommand "editor.ast", "<HOME>", "cursor.home"
addCommand "editor.ast", "<END>", "cursor.end"
addCommand "editor.ast", "<UP>", "move-cursor-prev-line"
addCommand "editor.ast", "<DOWN>", "move-cursor-next-line"
addCommand "editor.ast", "<LEFT>", "move-cursor-prev"
addCommand "editor.ast", "<RIGHT>", "move-cursor-next"
addCommand "editor.ast", "n", "move-cursor-prev"
addCommand "editor.ast", "t", "move-cursor-next"
addCommand "editor.ast", "<S-LEFT>", "cursor.left", "last"
addCommand "editor.ast", "<S-RIGHT>", "cursor.right", "last"
addCommand "editor.ast", "<S-UP>", "cursor.up", "last"
addCommand "editor.ast", "<S-DOWN>", "cursor.down", "last"
addCommand "editor.ast", "<S-HOME>", "cursor.home", "last"
addCommand "editor.ast", "<S-END>", "cursor.end", "last"
addCommand "editor.ast", "<BACKSPACE>", "backspace"
addCommand "editor.ast", "<DELETE>", "delete"
addCommand "editor.ast", "<TAB>", "edit-next-empty"
addCommand "editor.ast", "<S-TAB>", "edit-prev-empty"
addCommand "editor.ast", "<A-f>", "select-containing", "function"
addCommand "editor.ast", "<A-c>", "select-containing", "const-decl"
addCommand "editor.ast", "<A-n>", "select-containing", "node-list"
addCommand "editor.ast", "<A-i>", "select-containing", "if"
addCommand "editor.ast", "<A-l>", "select-containing", "line"
addCommand "editor.ast", "e", "rename"
addCommand "editor.ast", "AE", "insert-after", "empty"
addCommand "editor.ast", "AP", "insert-after", "deleted"
addCommand "editor.ast", "ae", "insert-after-smart", "empty"
addCommand "editor.ast", "ap", "insert-after-smart", "deleted"
addCommand "editor.ast", "IE", "insert-before", "empty"
addCommand "editor.ast", "IP", "insert-before", "deleted"
addCommand "editor.ast", "ie", "insert-before-smart", "empty"
addCommand "editor.ast", "ip", "insert-before-smart", "deleted"
addCommand "editor.ast", "ke", "insert-child", "empty"
addCommand "editor.ast", "kp", "insert-child", "deleted"
addCommand "editor.ast", "s", "replace", "empty"
addCommand "editor.ast", "re", "replace", "empty"
addCommand "editor.ast", "rn", "replace", "number-literal"
addCommand "editor.ast", "rf", "replace", "call-func"
addCommand "editor.ast", "rp", "replace", "deleted"
addCommand "editor.ast", "rr", "replace-parent"
addCommand "editor.ast", "gd", "goto", "definition"
addCommand "editor.ast", "gp", "goto", "prev-usage"
addCommand "editor.ast", "gn", "goto", "next-usage"
addCommand "editor.ast", "GE", "goto", "prev-error"
addCommand "editor.ast", "ge", "goto", "next-error"
addCommand "editor.ast", "gs", "goto", "symbol"
addCommand "editor.ast", "<F12>", "goto", "next-error-diagnostic"
addCommand "editor.ast", "<S-F12>", "goto", "prev-error-diagnostic"
addCommand "editor.ast", "<F5>", "run-selected-function"
addCommand "editor.ast", "\"", "replace-empty", "\""
addCommand "editor.ast", "'", "replace-empty", "\""
addCommand "editor.ast", "+", "wrap", "+"
addCommand "editor.ast", "-", "wrap", "-"
addCommand "editor.ast", "*", "wrap", "*"
addCommand "editor.ast", "/", "wrap", "/"
addCommand "editor.ast", "%", "wrap", "%"
addCommand "editor.ast", "(", "wrap", "call-func"
addCommand "editor.ast", ")", "wrap", "call-arg"
addCommand "editor.ast", "{", "wrap", "{"
addCommand "editor.ast", "=<ENTER>", "wrap", "="
addCommand "editor.ast", "==", "wrap", "=="
addCommand "editor.ast", "!=", "wrap", "!="
addCommand "editor.ast", "\\<\\>", "wrap", "<>"
addCommand "editor.ast", "\\<=", "wrap", "<="
addCommand "editor.ast", "\\>=", "wrap", ">="
addCommand "editor.ast", "\\<<ENTER>", "wrap", "<"
addCommand "editor.ast", "\\><ENTER>", "wrap", ">"
addCommand "editor.ast", "<SPACE>and", "wrap", "and"
addCommand "editor.ast", "<SPACE>or", "wrap", "or"
addCommand "editor.ast", "vc", "wrap", "const-decl"
addCommand "editor.ast", "vl", "wrap", "let-decl"
addCommand "editor.ast", "vv", "wrap", "var-decl"
addCommand "editor.ast", "d", "delete-selected"
addCommand "editor.ast", "y", "copy-selected"
addCommand "editor.ast", "u", "undo"
addCommand "editor.ast", "U", "redo"
addCommand "editor.ast", "<C-d>", "scroll", -150
addCommand "editor.ast", "<C-u>", "scroll", 150
addCommand "editor.ast", "<PAGE_DOWN>", "scroll", -450
addCommand "editor.ast", "<PAGE_UP>", "scroll", 450
addCommand "editor.ast", "<C-f>", "select-center-node"
addCommand "editor.ast", "<C-r>", "select-prev"
addCommand "editor.ast", "<C-t>", "select-next"
addCommand "editor.ast", "<C-LEFT>", "select-prev"
addCommand "editor.ast", "<C-RIGHT>", "select-next"
addCommand "editor.ast", "<SPACE>dc", "dump-context"
addCommand "editor.ast", "<CA-DOWN>", "scroll-output", "-5"
addCommand "editor.ast", "<CA-UP>", "scroll-output", "5"
addCommand "editor.ast", "<CA-HOME>", "scroll-output", "home"
addCommand "editor.ast", "<CA-END>", "scroll-output", "end"
addCommand "editor.ast", ".", "run-last-command", "edit"
addCommand "editor.ast", ",", "run-last-command", "move"
addCommand "editor.ast", ";", "run-last-command"
addCommand "editor.ast", "<A-t>", "move-node-to-next-space"
addCommand "editor.ast", "<A-n>", "move-node-to-prev-space"
addCommand "editor.ast", "<C-a>", "set-mode", "uiae"

addCommand "editor.text", "<C-SPACE>ts", "reload-treesitter"

setConsumeAllInput "editor.ast.uiae", true
addCommand "editor.ast.uiae", "<ESCAPE>", "set-mode", ""
addCommand "editor.ast.uiae", "a", "scroll", 50

addCommand "editor.ast.completion", "<ENTER>", "finish-edit", true
addCommand "editor.ast.completion", "<ESCAPE>", "finish-edit", false
addCommand "editor.ast.completion", "<UP>", "select-prev-completion"
addCommand "editor.ast.completion", "<DOWN>", "select-next-completion"
addCommand "editor.ast.completion", "<TAB>", "apply-selected-completion"
addCommand "editor.ast.completion", "<C-TAB>", "cancel-and-next-completion"
addCommand "editor.ast.completion", "<CS-TAB>", "cancel-and-prev-completion"
addCommand "editor.ast.completion", "<A-d>", "cancel-and-delete"
addCommand "editor.ast.completion", "<A-t>", "move-empty-to-next-space"
addCommand "editor.ast.completion", "<A-n>", "move-empty-to-prev-space"

addCommand "editor.ast.goto", "<ENTER>", "accept"
addCommand "editor.ast.goto", "<TAB>", "accept"
addCommand "editor.ast.goto", "<ESCAPE>", "cancel"
addCommand "editor.ast.goto", "<UP>", "prev"
addCommand "editor.ast.goto", "<DOWN>", "next"
addCommand "editor.ast.goto", "<HOME>", "home"
addCommand "editor.ast.goto", "<END>", "end"