import std/[strutils, setutils, parseutils, macros, genasts]
import absytree_runtime, keybindings_normal
import misc/[timer, util, myjsonutils]


infof"import vim keybindings"

var vimMotionNextMode = initTable[EditorId, string]()
var yankedLines: bool = false
var selectLines: bool = false

type VimTextObjectRange* = enum Inner, Outer, CurrentToEnd

macro addSubCommandWithCount*(mode: string, sub: string, keys: string, move: string, args: varargs[untyped]) =
  let (stmts, str) = bindArgs(args)
  return genAst(stmts, mode, keys, move, str, sub):
    stmts
    addCommandScript(getContextWithMode("editor.text", mode) & "#" & sub, "", keysPrefix & "<?-count>" & keys, move, str & " <#" & sub & ".count>")

proc addSubCommandWithCount*(mode: string, sub: string, keys: string, action: proc(editor: TextDocumentEditor, count: int): void) =
  addCommand getContextWithMode("editor.text", mode) & "#" & sub, "<?-count>" & keys, "<#" & sub & ".count>", action

template addSubCommandWithCountBlock*(mode: string, sub: string, keys: string, body: untyped): untyped =
  addSubCommandWithCount mode, sub, keys, proc(editor: TextDocumentEditor, count: int): void =
    let editor {.inject.} = editor
    let count {.inject.} = count
    body

template addSubCommand*(mode: string, sub: string, keys: string, move: string, args: varargs[untyped]) =
  addTextCommand mode & "#" & sub, keys, move, args

template addMoveCommandBlock*(mode: string, sub: string, keys: string, body: untyped): untyped =
  addTextCommandBlock mode & "#" & sub, keys:
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
  while endColumn < line.high and predicate(line[endColumn + 1]):
    inc endColumn
  while startColumn > 0 and predicate(line[startColumn - 1]):
    dec startColumn
  return (startColumn, endColumn)

proc vimSelectLine(editor: TextDocumentEditor) {.expose("vim-select-line").} =
  editor.selections = editor.selections.mapIt (if it.isBackwards:
      ((it.first.line, editor.lineLength(it.first.line)), (it.last.line, 0))
    else:
      ((it.first.line, 0), (it.last.line, editor.lineLength(it.last.line))))

proc vimSelectLastCursor(editor: TextDocumentEditor) {.expose("vim-select-last-cursor").} =
  # infof"vimSelectLastCursor"
  editor.selections = editor.selections.mapIt(it.last.toSelection)

proc vimSelectLast(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-select-last").} =
  infof"vimSelectLast '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.selections = editor.selections.mapIt(it.last.toSelection)

proc vimSelect(editor: TextDocumentEditor, move: string, count: int = 1) {.expose("vim-select").} =
  infof"vimSelect '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)

proc extendSelectionToPreviousLine(editor: TextDocumentEditor) =
  let old = editor.selections
  editor.selections = editor.selections.mapIt (if it.isBackwards:
      (it.first, editor.doMoveCursorColumn(it.last, -1))
    else:
      (editor.doMoveCursorColumn(it.first, -1), it.last))

proc copySelection(editor: TextDocumentEditor): Selections =
  yankedLines = selectLines
  let selections = editor.selections

  if selectLines:
    editor.extendSelectionToPreviousLine()

  editor.copy(inclusiveEnd=true)
  return selections

proc vimDeleteSelection(editor: TextDocumentEditor) {.expose("vim-delete-selection").} =
  let selections = editor.copySelection()
  discard editor.delete(editor.selections, inclusiveEnd=true)
  editor.selections = selections.mapIt(it.normalized.first.toSelection)
  editor.setMode "normal"

proc vimChangeSelection*(editor: TextDocumentEditor) {.expose("vim-change-selection").} =
  let selections = editor.copySelection()
  discard editor.delete(editor.selections, inclusiveEnd=true)
  editor.selections = selections.mapIt(it.normalized.first.toSelection)
  editor.setMode "insert"

proc vimYankSelection*(editor: TextDocumentEditor) {.expose("vim-yank-selection").} =
  let selections = editor.copySelection()
  editor.selections = selections.mapIt(it.normalized.first.toSelection)
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

proc vimMoveTo*(editor: TextDocumentEditor, target: string, before: bool, count: int = 1) {.expose("vim-move-to").} =
  # infof"vimMoveTo '{target}' {before}"
  let target = if target.len == 1:
    target
  elif target == "<SPACE>":
    " "
  else:
    return

  for _ in 0..<max(1, count):
    editor.moveCursorTo(target)
  if before:
    editor.moveCursorColumn(-1)

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
  let isEmpty = editor.lineLength(cursor.line) == 0

  result = ((cursor.line, 0), cursor)
  while result.first.line - 1 >= 0 and (editor.lineLength(result.first.line - 1) == 0) == isEmpty:
    dec result.first.line
  while result.last.line + 1 < editor.lineCount and (editor.lineLength(result.last.line + 1) == 0) == isEmpty:
    inc result.last.line

  result.last.column = editor.lineLength(result.last.line)

proc vimMotionParagraphOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  result = editor.vimMotionParagraphInner(cursor, count)
  if result.last.line + 1 < editor.lineCount:
    result = result or editor.vimMotionParagraphInner((result.last.line + 1, 0), 1)

proc vimMotionWordOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  result = vimMotionWord(editor, cursor, count)
  if result.last.column < editor.lineLength(result.last.line) and editor.getLine(result.last.line)[result.last.column] in Whitespace:
    result.last = editor.vimMotionWord(result.last, 1).last

proc vimMotionWordBigOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  result = vimMotionWordBig(editor, cursor, count)
  if result.last.column < editor.lineLength(result.last.line) and editor.getLine(result.last.line)[result.last.column] in Whitespace:
    result.last = editor.vimMotionWordBig(result.last, 1).last

proc charAt*(editor: TextDocumentEditor, cursor: Cursor): char =
  let line = editor.getLine(cursor.line)
  if cursor.column < line.high:
    return line[cursor.column]
  else:
    return '\0'

proc vimMotionSurround*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char, inside: bool): Selection =
  result = cursor.toSelection
  # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}"
  while true:
    let firstChar = editor.charAt(result.first)
    let lastChar = editor.charAt(result.last)
    let (startDepth, endDepth) = if lastChar == c0:
      (1, 0)
    elif lastChar == c1:
      (0, 1)
    else:
      (1, 1)

    # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}: try find around: {startDepth}, {endDepth}"
    if editor.findSurroundStart(result.first, count, c0, c1, startDepth).getSome(opening) and editor.findSurroundEnd(result.last, count, c0, c1, endDepth).getSome(closing):
      result = (opening, closing)
      # infof"vimMotionSurround: found inside {result}"
      if inside:
        result.first = editor.doMoveCursorColumn(result.first, 1)
        result.last = editor.doMoveCursorColumn(result.last, -1)
      return

    # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}: try find ahead: {startDepth}, {endDepth}"
    if editor.findSurroundEnd(result.first, count, c0, c1, -1).getSome(opening) and editor.findSurroundEnd(opening, count, c0, c1, 0).getSome(closing):
      result = (opening, closing)
      # infof"vimMotionSurround: found ahead {result}"
      if inside:
        result.first = editor.doMoveCursorColumn(result.first, 1)
        result.last = editor.doMoveCursorColumn(result.last, -1)
      return
    else:
      # infof"vimMotionSurround: found nothing {result}"
      return

proc vimMotionSurroundBracesInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '{', '}', true)
proc vimMotionSurroundBracesOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '{', '}', false)
proc vimMotionSurroundParensInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '(', ')', true)
proc vimMotionSurroundParensOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '(', ')', false)
proc vimMotionSurroundBracketsInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '[', ']', true)
proc vimMotionSurroundBracketsOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '[', ']', false)
proc vimMotionSurroundAngleInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '<', '>', true)
proc vimMotionSurroundAngleOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '<', '>', false)
proc vimMotionSurroundDoubleQuotesInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '"', '"', true)
proc vimMotionSurroundDoubleQuotesOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '"', '"', false)
proc vimMotionSurroundSingleQuotesInner*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '\'', '\'', true)
proc vimMotionSurroundSingleQuotesOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '\'', '\'', false)

# todo
addCustomTextMove "vim-word", vimMotionWord
addCustomTextMove "vim-WORD", vimMotionWordBig
addCustomTextMove "vim-word-inner", vimMotionWord
addCustomTextMove "vim-WORD-inner", vimMotionWordBig
addCustomTextMove "vim-word-outer", vimMotionWordOuter
addCustomTextMove "vim-WORD-outer", vimMotionWordBigOuter
addCustomTextMove "vim-paragraph-inner", vimMotionParagraphInner
addCustomTextMove "vim-paragraph-outer", vimMotionParagraphOuter
addCustomTextMove "vim-surround-{-inner", vimMotionSurroundBracesInner
addCustomTextMove "vim-surround-{-outer", vimMotionSurroundBracesOuter
addCustomTextMove "vim-surround-(-inner", vimMotionSurroundParensInner
addCustomTextMove "vim-surround-(-outer", vimMotionSurroundParensOuter
addCustomTextMove "vim-surround-[-inner", vimMotionSurroundBracketsInner
addCustomTextMove "vim-surround-[-outer", vimMotionSurroundBracketsOuter
addCustomTextMove "vim-surround-<-inner", vimMotionSurroundAngleInner
addCustomTextMove "vim-surround-<-outer", vimMotionSurroundAngleOuter
addCustomTextMove "vim-surround-\"-inner", vimMotionSurroundDoubleQuotesInner
addCustomTextMove "vim-surround-\"-outer", vimMotionSurroundDoubleQuotesOuter
addCustomTextMove "vim-surround-'-inner", vimMotionSurroundSingleQuotesInner
addCustomTextMove "vim-surround-'-outer", vimMotionSurroundSingleQuotesOuter

iterator iterateTextObjects(editor: TextDocumentEditor, cursor: Cursor, move: string, backwards: bool = false): Selection =
  var selection = editor.getSelectionForMove(cursor, move, 0)
  # infof"iterateTextObjects({cursor}, {move}, {backwards}), selection: {selection}"
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

    let nextCursor = if backwards: (selection.first.line, selection.first.column - 1) else: (selection.last.line, selection.last.column + 1)
    # echo &"iterate text objects {move}, {cursor} get selection for move {nextCursor} {move}"
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
        infof"{i}: {res} -> {selection}"
        resultSelection = resultSelection or selection
        if i == max(count, 1) - 1:
          break

      infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count}): {resultSelection}"
      if it.isBackwards:
        resultSelection.reverse
      else:
        resultSelection
    )

  editor.scrollToCursor(Last)

proc vimSelectSurrounding(editor: TextDocumentEditor, textObject: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.expose("vim-select-surrounding").} =
  # infof"vimSelectSurrounding({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count})"

  editor.selections = editor.selections.mapIt(block:
      let resultSelection = editor.getSelectionForMove(it.last, textObject, count)
      # infof"vimSelectSurrounding({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count}): {resultSelection}"
      if it.isBackwards:
        resultSelection.reverse
      else:
        resultSelection
    )

  editor.scrollToCursor(Last)

proc moveSelectionNext(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.expose("move-selection-next").} =
  # infof"moveSelectionNext '{move}' {count} {backwards} {allowEmpty}"
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      for k in 0..<max(1, count):
        for i, selection in enumerateTextObjects(editor, res, move, backwards):
          if i == 0: continue
          let cursor = if backwards: selection.last else: selection.first
          # echo i, ", ", selection, ", ", cursor, ", ", it
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
      # echo res, ", ", it, ", ", which
      res.toSelection(it, which)
    )

  editor.scrollToCursor(Last)

proc moveSelectionEnd(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.expose("move-selection-end").} =
  # infof"moveSelectionEnd '{move}' {count} {backwards} {allowEmpty}"
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
          if selection.last.column < editor.lineLength(selection.last.line) and
              editor.getLine(selection.last.line)[selection.last.column] notin Whitespace:
            res = cursor
            break
      res.toSelection(it, which)
    )

  editor.scrollToCursor(Last)

proc moveParagraph(editor: TextDocumentEditor, backwards: bool, count: int = 1) {.expose("move-paragraph").} =
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      for k in 0..<max(1, count):
        for i, selection in enumerateTextObjects(editor, res, "vim-paragraph-inner", backwards):
          if i == 0: continue
          let cursor = if backwards: selection.last else: selection.first
          if editor.lineLength(cursor.line) == 0:
            res = cursor
            break

      res.toSelection(it, which)
    )

  if selectLines:
    editor.vimSelectLine()

  editor.scrollToCursor(Last)

proc vimDeleteLeft*(editor: TextDocumentEditor) =
  yankedLines = selectLines
  editor.copy()
  editor.deleteLeft()

proc vimDeleteRight*(editor: TextDocumentEditor) =
  yankedLines = selectLines
  editor.copy()
  editor.deleteRight()

expose "vim-delete-left", vimDeleteLeft

proc vimMoveCursorColumn(editor: TextDocumentEditor, direction: int, count: int = 1) {.expose("vim-move-cursor-column").} =
  editor.moveCursorColumn(direction * max(count, 1))
  if selectLines:
    editor.vimSelectLine()

proc vimMoveCursorLine(editor: TextDocumentEditor, direction: int, count: int = 1) {.expose("vim-move-cursor-line").} =
  editor.moveCursorLine(direction * max(count, 1))
  if selectLines:
    editor.vimSelectLine()

proc vimMoveFirst(editor: TextDocumentEditor, move: string) {.expose("vim-move-first").} =
  editor.moveFirst(move)
  if selectLines:
    editor.vimSelectLine()

proc vimMoveLast(editor: TextDocumentEditor, move: string) {.expose("vim-move-last").} =
  editor.moveLast(move)
  if selectLines:
    editor.vimSelectLine()

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

proc vimPaste(editor: TextDocumentEditor, register: string = "") {.expose("vim-paste").} =
  infof"vimPaste {register}, lines: {yankedLines}"
  if yankedLines:
    editor.moveLast "line", Both

  editor.paste register

proc vimCloseCurrentViewOrQuit() {.expose("vim-close-current-view-or-quit").} =
  let openEditors = getOpenEditors().len + getHiddenEditors().len
  if openEditors == 1:
    absytree_runtime.quit()
  else:
    closeCurrentView(keepHidden=false)

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
  setOption "editor.text.inclusive-selection", false

  setModeChangedHandler proc(editor, oldMode, newMode: auto) =
    # infof"vim: handle mode change {oldMode} -> {newMode}"
    if newMode == "normal":
      if not isReplayingCommands():
        stopRecordingCommands(".")
    else:
      if oldMode == "normal" and not isReplayingCommands():
        editor.recordCurrentCommand()
        setRegisterText("", ".")
        startRecordingCommands(".")
      editor.clearCurrentCommandHistory(retainLast=true)

    if newMode == "visual-line":
      selectLines = true
    else:
      selectLines = false

    case newMode
    of "normal":
      setOption "editor.text.vim-motion-action", "vim-select-last-cursor"
      setOption "editor.text.inclusive-selection", false
      vimMotionNextMode[editor.id] = "normal"
      editor.selections = editor.selections.mapIt(it.last.toSelection)
      editor.saveCurrentCommandHistory()

    of "insert":
      setOption "editor.text.inclusive-selection", false
      setOption "editor.text.vim-motion-action", ""
      vimMotionNextMode[editor.id] = "insert"

    of "visual":
      setOption "editor.text.inclusive-selection", true

    else:
      setOption "editor.text.inclusive-selection", false

  addTextCommand "#count", "<-1-9><o-0-9>", ""

  # Normal mode
  addCommand "editor", ":", "command-line"

  addTextCommandBlock "", "<C-e>": editor.setMode("normal")
  addTextCommandBlock "", "<ESCAPE>": editor.setMode("normal")

  addTextCommandBlock "", "s": replayCommands(".")
  addTextCommandBlock "", ".": replayCommands(".")

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
      addCommand "editor", "q", "vim-close-current-view-or-quit"
      addCommand "editor", "<C-q>", "close-current-view"
      addCommand "editor", "c", "close-current-view", true
      addCommand "editor", "C", "close-current-view", false
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

  #
  addTextCommand "normal", "<move>", "vim-select-last <move>"
  addTextCommand "", "<?-count>d<move>", """vim-delete-move <move> <#count>"""
  addTextCommand "", "<?-count>c<move>", """vim-change-move <move> <#count>"""
  addTextCommand "", "<?-count>y<move>", """vim-yank-move <move> <#count>"""

  addTextCommand "", "<?-count>d<text_object>", """vim-delete-move <text_object> <#count>"""
  addTextCommand "", "<?-count>c<text_object>", """vim-change-move <text_object> <#count>"""
  addTextCommand "", "<?-count>y<text_object>", """vim-yank-move <text_object> <#count>"""

  # navigation (horizontal)

  addSubCommandWithCount "", "move", "h", "vim-move-cursor-column", -1
  addSubCommandWithCount "", "move", "<LEFT>", "vim-move-cursor-column", -1

  # todo: this clashes with insert mode because it ises <move> and binds <BACKSPACE> directly
  # addSubCommandWithCount "", "move", "<BACKSPACE>", "vim-move-cursor-column", -1

  addSubCommandWithCount "", "move", "l", "vim-move-cursor-column", 1
  addSubCommandWithCount "", "move", "<RIGHT>", "vim-move-cursor-column", 1

  # todo: this clashes with insert mode because it ises <move> and binds <SPACE> directly
  # addSubCommandWithCount "", "move", "<SPACE>", "vim-move-cursor-column", 1

  addSubCommand "", "move", "0", "vim-move-first", "line"
  addSubCommand "", "move", "<HOME>", "vim-move-first", "line"
  addSubCommand "", "move", "^", "vim-move-first", "line-no-indent"

  addSubCommandWithCount "", "move", "$", vimMoveToEndOfLine
  addSubCommandWithCount "", "move", "<END>", vimMoveToEndOfLine

  addSubCommand "", "move", "g0", "vim-move-first", "line"
  addSubCommand "", "move", "g^", "vim-move-first", "line-no-indent"

  addSubCommandWithCount "", "move", "g$", vimMoveToEndOfLine
  addSubCommand "", "move", "gm", "move-cursor-line-center"
  addSubCommand "", "move", "gM", "move-cursor-center"

  addSubCommandWithCountBlock "", "move", "|":
    editor.selections = editor.selections.mapIt((it.last.line, count).toSelection)
    editor.scrollToCursor Last

  # navigation (vertical)
  addSubCommandWithCount "", "move", "k", "vim-move-cursor-line", -1
  addSubCommandWithCount "", "move", "<UP>", "vim-move-cursor-line", -1
  addSubCommandWithCount "", "move", "<C-p>", "vim-move-cursor-line", -1

  addSubCommandWithCount "", "move", "j", "vim-move-cursor-line", 1
  addSubCommandWithCount "", "move", "<DOWN>", "vim-move-cursor-line", 1
  # todo: this clashes with insert mode because it ises <move> and binds <ENTER> directly
  # addSubCommandWithCount "", "move", "<ENTER>", "vim-move-cursor-line", 1
  addSubCommandWithCount "", "move", "<C-n>", "vim-move-cursor-line", 1
  addSubCommandWithCount "", "move", "<C-j>", "vim-move-cursor-line", 1

  addSubCommandWithCountBlock "", "move", "-": vimMoveCursorLineFirstChar(editor, -1, count)
  addSubCommandWithCountBlock "", "move", "+": vimMoveCursorLineFirstChar(editor, 1, count)

  addSubCommandWithCountBlock "", "move", "_": vimMoveToStartOfLine(editor, count)

  addSubCommandWithCountBlock "", "move", "gg":
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.selection = (count, 0).toSelection(editor.selection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last

  addSubCommandWithCountBlock "", "move", "G":
    let line = if count == 0: editor.lineCount - 1 else: count
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.selection = (line, 0).toSelection(editor.selection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last

  addSubCommandWithCountBlock "", "move", "<S-%>":
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

  addSubCommandWithCount "", "move", "k", "vim-move-cursor-line", -1
  addSubCommandWithCount "", "move", "j", "vim-move-cursor-line", 1
  addSubCommandWithCount "", "move", "gk", "vim-move-cursor-line", -1
  addSubCommandWithCount "", "move", "gj", "vim-move-cursor-line", 1

  # search
  addTextCommandBlock "", "*": editor.setSearchQueryFromMove("word")
  addTextCommand "", "n", "select-move", "next-find-result", true
  addTextCommand "", "N", "select-move", "prev-find-result", true

  addTextCommandBlock "", "/":
    commandLine("set-search-query \\")
    if getActiveEditor().isTextEditor(editor):
      var arr = newJArray()
      arr.add newJString("file")
      discard editor.runAction("move-last", arr)
      editor.setMode("insert")

  # Scrolling
  addTextCommand "", "<C-e>", "scroll-lines", 1
  addSubCommandWithCountBlock "", "move", "<C-d>": editor.vimMoveCursorLine(editor.screenLineCount div 2, count)
  addSubCommandWithCountBlock "", "move", "<C-f>": editor.vimMoveCursorLine(editor.screenLineCount, count)
  addSubCommandWithCountBlock "", "move", "<S-DOWN>": editor.vimMoveCursorLine(editor.screenLineCount, count)
  addSubCommandWithCountBlock "", "move", "<PAGE_DOWN>": editor.vimMoveCursorLine(editor.screenLineCount, count)

  addTextCommand "", "<C-y>", "scroll-lines", -1
  addSubCommandWithCountBlock "", "move", "<C-u>": editor.vimMoveCursorLine(-editor.screenLineCount div 2, count)
  addSubCommandWithCountBlock "", "move", "<C-b>": editor.vimMoveCursorLine(-editor.screenLineCount, count)
  addSubCommandWithCountBlock "", "move", "<S-UP>": editor.vimMoveCursorLine(-editor.screenLineCount, count)
  addSubCommandWithCountBlock "", "move", "<PAGE_UP>": editor.vimMoveCursorLine(-editor.screenLineCount, count)

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
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)
    editor.setMode "insert"
  addTextCommandBlock "", "A":
    editor.moveLast "line", Both
    editor.setMode "insert"
  addTextCommandBlock "normal", "i":
    editor.setMode "insert"
  addTextCommandBlock "", "I":
    editor.moveFirst "line-no-indent", Both
    editor.setMode "insert"
  addTextCommandBlock "normal", "gI":
    editor.moveFirst "line", Both
    editor.setMode "insert"

  addTextCommandBlock "normal", "o":
    editor.moveLast "line", Both
    editor.insertText "\n"
    editor.setMode "insert"

  addTextCommandBlock "normal", "O":
    editor.moveFirst "line", Both
    editor.insertText "\n"
    editor.vimMoveCursorLine -1
    editor.setMode "insert"

  addTextCommand "", "<ESCAPE>", "set-mode", "normal"
  addTextCommand "", "<C-c>", "set-mode", "normal"

  # Text object motions
  addSubCommandWithCount "", "move", "w", "move-selection-next", "vim-word", false, true
  addSubCommandWithCount "", "move", "<S-RIGHT>", "move-selection-next", "vim-word", false, true
  addSubCommandWithCount "", "move", "W", "move-selection-next", "vim-WORD", false, true
  addSubCommandWithCount "", "move", "<C-RIGHT>", "move-selection-next", "vim-WORD", false, true
  addSubCommandWithCount "", "move", "e", "move-selection-end", "vim-word", false, false
  addSubCommandWithCount "", "move", "E", "move-selection-end", "vim-WORD", false, false
  addSubCommandWithCount "", "move", "b", "move-selection-end", "vim-word", true, true
  addSubCommandWithCount "", "move", "<S-LEFT>", "move-selection-end", "vim-word", true, true
  addSubCommandWithCount "", "move", "B", "move-selection-end", "vim-WORD", true, true
  addSubCommandWithCount "", "move", "<C-LEFT>", "move-selection-end", "vim-WORD", true, true
  addSubCommandWithCount "", "move", "ge", "move-selection-next", "vim-word", true, false
  addSubCommandWithCount "", "move", "gE", "move-selection-next", "vim-WORD", true, false
  addSubCommandWithCount "", "move", "}", "move-paragraph", false
  addSubCommandWithCount "", "move", "{", "move-paragraph", true
  addSubCommandWithCount "", "move", "f<ANY>", "vim-move-to <move.ANY>", false
  addSubCommandWithCount "", "move", "t<ANY>", "vim-move-to <move.ANY>", true

  addSubCommandWithCount "", "text_object", "iw", "vim-select-text-object", "vim-word-inner", false, true
  addSubCommandWithCount "", "text_object", "aw", "vim-select-text-object", "vim-word-outer", false, true
  addSubCommandWithCount "", "text_object", "iW", "vim-select-text-object", "vim-WORD-inner", false, true
  addSubCommandWithCount "", "text_object", "aW", "vim-select-text-object", "vim-WORD-outer", false, true
  addSubCommandWithCount "", "text_object", "ip", "vim-select-text-object", "vim-paragraph-inner", false, true
  addSubCommandWithCount "", "text_object", "ap", "vim-select-text-object", "vim-paragraph-outer", false, true

  proc addTextObjectCommand(context: string, keys: string, name: string) =
    addSubCommandWithCount context, "text_object", "i" & keys, "vim-select-surrounding", name & "-inner", false, true
    addSubCommandWithCount context, "text_object", "a" & keys, "vim-select-surrounding", name & "-outer", false, true

  addTextObjectCommand "", "{", "vim-surround-{"
  addTextObjectCommand "", "}", "vim-surround-{"
  addTextObjectCommand "", "(", "vim-surround-("
  addTextObjectCommand "", ")", "vim-surround-("
  addTextObjectCommand "", "[", "vim-surround-["
  addTextObjectCommand "", "]", "vim-surround-["
  addTextObjectCommand "", "\"", "vim-surround-\""
  addTextObjectCommand "", "'", "vim-surround-'"

  addTextCommandBlock "", "dd":
    selectLines = true
    editor.vimSelectLine()
    editor.vimDeleteSelection()
    selectLines = false

  addTextCommandBlock "", "cc":
    editor.vimSelectLine()
    editor.vimChangeSelection()

  addTextCommandBlock "", "yy":
    selectLines = true
    editor.vimSelectLine()
    editor.vimYankSelection()
    selectLines = false

  # # Deleting text
  addTextCommand "", "x", vimDeleteRight
  addTextCommand "", "<DELETE>", vimDeleteRight
  addTextCommand "", "X", vimDeleteLeft

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
  addTextCommand "insert", "<move>", "vim-select-last <move>"

  # Visual mode
  addTextCommandBlock "", "v":
    editor.setMode "visual"
    setOption "editor.text.vim-motion-action", ""
    vimMotionNextMode[editor.id] = "visual"

  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"

  addTextCommand "visual", "<move>", "vim-select <move>"
  addTextCommand "visual", "y", "vim-yank-selection"
  addTextCommand "visual", "d", "vim-delete-selection"
  addTextCommand "visual", "c", "vim-change-selection"
  addTextCommand "visual", "s", "vim-change-selection"

  addTextCommand "visual", "<?-count><text_object>", """vim-select-move <text_object> <#count>"""

  # Visual line mode
  addTextCommandBlock "", "V":
    editor.setMode "visual-line"
    editor.vimSelectLine()
    # setOption "editor.text.vim-motion-action", ""
    # vimMotionNextMode[editor.id] = "visual"
    selectLines = true

  setHandleInputs "editor.text.visual-line", false
  setOption "editor.text.cursor.wide.visual-line", true
  setOption "editor.text.cursor.movement.visual-line", "last"

  addTextCommand "visual-line", "<move>", "vim-select <move>"
  addTextCommand "visual-line", "y", "vim-yank-selection"
  addTextCommand "visual-line", "d", "vim-delete-selection"
  addTextCommand "visual-line", "c", "vim-change-selection"
  addTextCommand "visual-line", "s", "vim-change-selection"

  addTextCommand "visual-line", "<?-count><text_object>", """vim-select-move <text_object> <#count>"""
