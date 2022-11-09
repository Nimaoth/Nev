include abs
import std/[strutils, sugar, streams]

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

proc handleDocumentEditorAction(id: EditorId, action: string, arg: string): bool =
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

proc handleTextEditorAction(editor: TextDocumentEditor, action: string, arg: string): bool =
  var args = newJArray()
  for a in newStringStream(arg).parseJsonFragments():
    args.add a

  case action
  of "cursor.left-word":
    let which = if args.len == 0: Config else: parseEnum[SelectionCursor](args[0].str, Config)

    let selection = editor.selection
    var cursor = selection.cursor(which)
    let line = editor.getLine cursor.line

    if cursor.column == 0:
      if cursor.line > 0:
        let prevLine = editor.getLine cursor.line - 1
        cursor = (cursor.line - 1, prevLine.len)
    else:
      while cursor.column > 0 and cursor.column <= line.len:
        cursor.column -= 1
        if cursor.column > 0:
          let leftCategory = line[cursor.column - 1].charCategory
          let rightCategory = line[cursor.column].charCategory
          if leftCategory != rightCategory:
            break

    case which
    of Config:
      editor.selection = cursor.toSelection(selection, getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
      echo editor.getContextWithMode("editor.text.cursor.movement"), ", ", getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both)
    else:
      editor.selection = cursor.toSelection(selection, which)
    editor.scrollToCursor(which)
    editor.updateTargetColumn(which)

  of "cursor.right-word":
    let which = if args.len == 0: Config else: parseEnum[SelectionCursor](args[0].str, Config)

    let selection = editor.selection
    var cursor = selection.cursor(which)
    let line = editor.getLine cursor.line
    let lineCount = editor.getLineCount

    if cursor.column == line.len:
      if cursor.line + 1 < lineCount:
        cursor = (cursor.line + 1, 0)
    else:
      while cursor.column >= 0 and cursor.column < line.len:
        cursor.column += 1
        if cursor.column < line.len:
          let leftCategory = line[cursor.column - 1].charCategory
          let rightCategory = line[cursor.column].charCategory
          if leftCategory != rightCategory:
            break

    case which
    of Config:
      editor.selection = cursor.toSelection(selection, getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
    else:
      editor.selection = cursor.toSelection(selection, which)
    editor.scrollToCursor(which)
    editor.updateTargetColumn(which)

  of "cursor.file-start":
    let which = if args.len == 0: Config else: parseEnum[SelectionCursor](args[0].str, Config)
    let selection = editor.selection
    let cursor = (0, 0)
    case which
    of Config:
      editor.selection = cursor.toSelection(selection, getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
    else:
      editor.selection = cursor.toSelection(selection, which)
    editor.scrollToCursor(which)
    editor.updateTargetColumn(which)

  of "cursor.file-end":
    let which = if args.len == 0: Config else: parseEnum[SelectionCursor](args[0].str, Config)
    let selection = editor.selection
    let cursor = (editor.getLineCount - 1, 0)
    case which
    of Config:
      editor.selection = cursor.toSelection(selection, getOption(editor.getContextWithMode("editor.text.cursor.movement"), Both))
    else:
      editor.selection = cursor.toSelection(selection, which)
    editor.scrollToCursor(which)
    editor.updateTargetColumn(which)

  else: return false
  return true

proc handleAstEditorAction(editor: AstDocumentEditor, action: string, arg: string): bool =
  case action

  else: return false
  return true

proc postInitialize*() =
  log "[script] postInitialize()"

  openFile "temp/test.rs"
  # openFile "temp/test.nim"
  openFile "src/absytree.nim"
  setLayout "fibonacci"
  changeLayoutProp("main-split", -0.2)

template addTextCommand(mode: string, command: string, body: untyped): untyped =
  let context = if mode.len == 0: "editor.text" else: "editor.text." & mode
  addCommand context, command, proc() =
    let editor {.inject.} = TextDocumentEditor(id: getActiveEditor())
    body

template addAstCommand(command: string, body: untyped): untyped =
  addCommand "editor.ast", command, proc() =
    let editor {.inject.} = AstDocumentEditor(id: getActiveEditor())
    body

setOption "ast.scroll-speed", 60

addCommand "editor", "<SPACE>tt", proc() =
  setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") * 2, 1, 1000000))
  echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

addCommand "editor", "<SPACE>tr", proc() =
  setOption("ast.max-loop-iterations", clamp(getOption[int]("ast.max-loop-iterations") div 2, 1, 1000000))
  echo "ast.max-loop-iterations: ", getOption[int]("ast.max-loop-iterations")

addCommand "editor", "<SPACE>td", "toggle-flag", "ast.render-vnode-depth"
addCommand "editor", "<SPACE>l", "toggle-flag", "logging"
addCommand "editor", "<SPACE>fs", "toggle-flag", "render-selected-value"
addCommand "editor", "<SPACE>fr", "toggle-flag", "log-render-duration"
addCommand "editor", "<SPACE>fd", "toggle-flag", "render-debug-info"
addCommand "editor", "<SPACE>fo", "toggle-flag", "render-execution-output"
addCommand "editor", "<C-SPACE>fg", "toggle-flag", "text.print-scopes"
addCommand "editor", "<C-SPACE>fm", "toggle-flag", "text.print-matches"

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

addCommand "commandLine", "<ESCAPE>", "exit-command-line"
addCommand "commandLine", "<ENTER>", "execute-command-line"

addCommand "popup.selector", "<ENTER>", "accept"
addCommand "popup.selector", "<TAB>", "accept"
addCommand "popup.selector", "<ESCAPE>", "cancel"
addCommand "popup.selector", "<UP>", "prev"
addCommand "popup.selector", "<DOWN>", "next"
addCommand "popup.selector", "<HOME>", "home"
addCommand "popup.selector", "<END>", "end"

setHandleInputs "editor.text", false
setOption "editor.text.cursor.movement.", "both"
addCommand "editor.text", "<LEFT>", "move-cursor-column", -1
addCommand "editor.text", "<RIGHT>", "move-cursor-column", 1
addCommand "editor.text", "<C-LEFT>", "cursor.left-word"
addCommand "editor.text", "<C-RIGHT>", "cursor.right-word"
addCommand "editor.text", "b", "cursor.left-word"
addCommand "editor.text", "w", "cursor.right-word"
addCommand "editor.text", "<C-UP>", "scroll-text", 20
addCommand "editor.text", "<C-DOWN>", "scroll-text", -20
addCommand "editor.text", "<CS-LEFT>", "cursor.left-word", "last"
addCommand "editor.text", "<CS-RIGHT>", "cursor.right-word", "last"
addCommand "editor.text", "<UP>", "move-cursor-line", -1
addCommand "editor.text", "<DOWN>", "move-cursor-line", 1
addCommand "editor.text", "<HOME>", "move-cursor-home"
addCommand "editor.text", "<END>", "move-cursor-end"
addCommand "editor.text", "<C-HOME>", "cursor.file-start"
addCommand "editor.text", "<C-END>", "cursor.file-end"
addCommand "editor.text", "<CS-HOME>", "cursor.file-start", "last"
addCommand "editor.text", "<CS-END>", "cursor.file-end", "last"
addCommand "editor.text", "<S-LEFT>", "move-cursor-column", -1, "last"
addCommand "editor.text", "<S-RIGHT>", "move-cursor-column", 1, "last"
addCommand "editor.text", "<S-UP>", "move-cursor-line", -1, "last"
addCommand "editor.text", "<S-DOWN>", "move-cursor-line", 1, "last"
addCommand "editor.text", "<S-HOME>", "move-cursor-home", "last"
addCommand "editor.text", "<S-END>", "move-cursor-end", "last"
addCommand "editor.text", "<BACKSPACE>", "backspace"
addCommand "editor.text", "<DELETE>", "delete"
addCommand "editor.text", "<C-r>", "reload-treesitter"
addCommand "editor.text", "<C-8>", () => setOption("text.line-distance", getOption[float32]("text.line-distance") - 1)
addCommand "editor.text", "<C-9>", () => setOption("text.line-distance", getOption[float32]("text.line-distance") + 1)
addCommand "editor.text", "i", "set-mode", "insert"
addCommand "editor.text", "v", "set-mode", "visual"
addCommand "editor.text", "V", "set-mode", "visual-temp"
addTextCommand "", "<ESCAPE>":
  editor.setMode("")
  editor.selection = editor.selection.last.toSelection
addTextCommand "", "<S-ESCAPE>":
  editor.setMode("")
  editor.selection = editor.selection.last.toSelection

setHandleInputs "editor.text.insert", true
addCommand "editor.text.insert", "<ENTER>", "insert-text", "\n"
addCommand "editor.text.insert", "<SPACE>", "insert-text", " "

setHandleInputs "editor.text.visual", false
setOption "editor.text.cursor.movement.visual", "last"

setHandleInputs "editor.text.visual-temp", false
setOption "editor.text.cursor.movement.visual-temp", "last-to-first"

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