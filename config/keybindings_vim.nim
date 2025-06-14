import std/[strutils, macros, genasts, sequtils, sets, algorithm]
import plugin_runtime, keybindings_normal
import misc/[timer, util, myjsonutils, custom_unicode, id, regex]
import input_api

embedSource()

infof"import vim keybindings"

var yankedLines: bool = false ## Whether the last thing we yanked was in a line mode

type EditorVimState = object
  ## Contains state which can vary per editor
  selectLines: bool = false ## Whether entire lines should be selected (e.g. in visual-line mode/when using dd)
  deleteInclusiveEnd: bool = true ## Whether the next time we delete some the selection end should be inclusive
  cursorIncludeEol: bool = false ## Whether the cursor can be after the last character in a line (e.g. in insert mode)
  currentUndoCheckpoint: string = "insert" ## Which checkpoint to undo to (depends on mode)
  revisionBeforeImplicitInsertMacro: int
  marks: Table[string, seq[(Anchor, Anchor)]]

var editorStates: Table[EditorId, EditorVimState]
var vimMotionNextMode = initTable[EditorId, string]()

const editorContext = "editor.text"

proc vimState(editor: TextDocumentEditor): var EditorVimState =
  if not editorStates.contains(editor.id):
    editorStates[editor.id] = EditorVimState()
  return editorStates[editor.id]

proc shouldRecortImplicitPeriodMacro(editor: TextDocumentEditor): bool =
  case editor.getUsage()
  of "command-line", "search-bar":
    return false
  else:
    return true

proc recordCurrentCommandInPeriodMacro(editor: TextDocumentEditor) =
  if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
    setRegisterText("", ".")
    editor.recordCurrentCommand(@["."])

proc startRecordingCurrentCommandInPeriodMacro(editor: TextDocumentEditor) =
  if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
    startRecordingCommands(".-temp")
    setRegisterText("", ".-temp")
    editor.recordCurrentCommand(@[".-temp"])
    editor.vimState.revisionBeforeImplicitInsertMacro = editor.getRevision

type VimTextObjectRange* = enum Inner, Outer, CurrentToEnd

macro addSubCommandWithCount*(mode: string, sub: string, keys: string, move: string, args: varargs[untyped]) =
  let (stmts, str) = bindArgs(args)
  return genAst(stmts, mode, keys, move, str, sub):
    stmts
    addCommandScript(getContextWithMode("editor.text", mode) & "#" & sub, "", keysPrefix & "<?-count>" & keys, move, str & " <#" & sub & ".count>", source = currentSourceLocation(-2))

proc addSubCommandWithCount*(mode: string, sub: string, keys: string, action: proc(editor: TextDocumentEditor, count: int): void, source = currentSourceLocation()) =
  addCommand getContextWithMode("editor.text", mode) & "#" & sub, "<?-count>" & keys, "<#" & sub & ".count>", action, source

template addSubCommandWithCountBlock*(mode: string, sub: string, keys: string, body: untyped): untyped =
  let p = proc(editor: TextDocumentEditor, count: int): void =
    let editor {.inject.} = editor
    let count {.inject.} = count
    body
  addSubCommandWithCount mode, sub, keys, p, currentSourceLocation(-2)

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

proc getCurrentMacroRegister*(): string = getOption("editor.current-macro-register", "")

proc getEnclosing(line: string, column: int, predicate: proc(c: char): bool): (int, int) =
  var startColumn = column
  var endColumn = column
  while endColumn < line.high and predicate(line[endColumn + 1]):
    inc endColumn
  while startColumn > 0 and predicate(line[startColumn - 1]):
    dec startColumn
  return (startColumn, endColumn)

proc vimHandleSelectWorld(editor: TextDocumentEditor, cursor: Cursor, mode: string) {.exposeActive(editorContext, "vim-handle-select-word").} =
  editor.setSelection(cursor.toSelection)
  editor.setMode(mode)

proc vimSelectLine(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-select-line").} =
  editor.selections = editor.selections.mapIt (if it.isBackwards:
      ((it.first.line, editor.lineLength(it.first.line)), (it.last.line, 0))
    else:
      ((it.first.line, 0), (it.last.line, editor.lineLength(it.last.line))))

proc vimSelectLastCursor(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-select-last-cursor").} =
  # infof"vimSelectLastCursor"
  editor.selections = editor.selections.mapIt(it.last.toSelection)
  editor.updateTargetColumn()
  editor.setNextScrollBehaviour(ScrollToMargin)
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimSelectLast(editor: TextDocumentEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-select-last").} =
  # infof"vimSelectLast '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.selections = editor.selections.mapIt(it.last.toSelection)
  editor.vimState.deleteInclusiveEnd = true

proc vimSelect(editor: TextDocumentEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-select").} =
  # infof"vimSelect '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)

proc vimUndo(editor: TextDocumentEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext, "vim-undo").} =
  if enterNormalModeBefore:
    editor.setMode "normal"

  editor.undo(editor.vimState.currentUndoCheckpoint)
  if enterNormalModeBefore:
    if not editor.selections.allEmpty:
      editor.setMode "visual"
    else:
      editor.setMode "normal"

proc vimRedo(editor: TextDocumentEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext, "vim-redo").} =
  if enterNormalModeBefore:
    editor.setMode "normal"

  editor.redo(editor.vimState.currentUndoCheckpoint)
  if enterNormalModeBefore:
    if not editor.selections.allEmpty:
      editor.setMode "visual"
    else:
      editor.setMode "normal"

proc copySelection(editor: TextDocumentEditor, register: string = ""): Selections =
  ## Copies the selected text
  ## If line selection mode is enabled then it also extends the selection so that deleting it will also delete the line itself
  yankedLines = editor.vimState.selectLines
  editor.copy(register, inclusiveEnd=true)
  let selections = editor.selections
  if editor.vimState.selectLines:
    editor.selections = editor.selections.mapIt (
      if it.isBackwards:
        if it.last.line > 0:
          (it.first, editor.doMoveCursorColumn(it.last, -1))
        elif it.first.line + 1 < editor.lineCount:
          (editor.doMoveCursorColumn(it.first, 1), it.last)
        else:
          it
      else:
        if it.first.line > 0:
          (editor.doMoveCursorColumn(it.first, -1), it.last)
        elif it.last.line + 1 < editor.lineCount:
          (it.first, editor.doMoveCursorColumn(it.last, 1))
        else:
          it
    )

  return selections.mapIt(it.normalized.first.toSelection)

proc vimUpdateSelections(editor: TextDocumentEditor, selections: Selections) =
  if editor.vimState.selectLines:
    editor.selections = selections.mapIt editor.doMoveCursorLine(it.normalized.first, 1).toSelection

  else:
    editor.selections = selections
  editor.scrollToCursor Last

proc vimDeleteSelection(editor: TextDocumentEditor, forceInclusiveEnd: bool, oldSelections: Option[Selections] = Selections.none) {.exposeActive(editorContext, "vim-delete-selection").} =
  let newSelections = editor.copySelection(getVimDefaultRegister())
  let selectionsToDelete = editor.selections
  if oldSelections.isSome:
    editor.selections = oldSelections.get
  editor.addNextCheckpoint("insert")
  let inclusiveEnd = (not editor.vimState.selectLines) and (editor.vimState.deleteInclusiveEnd or forceInclusiveEnd)
  editor.vimUpdateSelections editor.delete(
    selectionsToDelete, inclusiveEnd=inclusiveEnd)
  editor.vimState.deleteInclusiveEnd = true
  editor.setMode "normal"

proc vimChangeSelection*(editor: TextDocumentEditor, forceInclusiveEnd: bool, oldSelections: Option[Selections] = Selections.none) {.exposeActive(editorContext, "vim-change-selection").} =
  let newSelections = editor.copySelection(getVimDefaultRegister())
  let selectionsToDelete = editor.selections
  if oldSelections.isSome:
    editor.selections = oldSelections.get
  editor.addNextCheckpoint("insert")
  # todo: figure out if we should check for selectLines here as well
  editor.vimUpdateSelections editor.delete(
    selectionsToDelete, inclusiveEnd=editor.vimState.deleteInclusiveEnd or forceInclusiveEnd)
  editor.vimState.deleteInclusiveEnd = true
  editor.setMode "insert"

proc vimYankSelection*(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-yank-selection").} =
  let selections = editor.copySelection(getVimDefaultRegister())
  editor.selections = selections
  editor.setMode "normal"

proc vimYankSelectionClipboard*(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-yank-selection-clipboard").} =
  let selections = editor.copySelection()
  editor.selections = selections
  editor.setMode "normal"

proc vimReplace(editor: TextDocumentEditor, input: string) {.exposeActive(editorContext, "vim-replace").} =
  let texts = editor.selections.mapIt(block:
    let selection = it
    let text = editor.getText(selection, inclusiveEnd=true)
    var newText = newStringOfCap(text.runeLen.int * input.runeLen.int)
    var lastIndex = 0
    var index = text.find('\n')
    if index == -1:
      newText.add input.repeat(text.runeLen.int)
    else:
      while index != -1:
        let lineLen = text.toOpenArray(lastIndex, index).runeLen.int - 1
        newText.add input.repeat(lineLen)
        newText.add "\n"
        lastIndex = index + 1
        index = text.find('\n', index + 1)

      let lineLen = text.toOpenArray(lastIndex, text.high).runeLen.int
      newText.add input.repeat(lineLen)

    newText
  )

  # infof"replace {editor.selections} with '{input}' -> {texts}"

  editor.addNextCheckpoint "insert"
  editor.selections = editor.edit(editor.selections, texts, inclusiveEnd=true).mapIt(it.first.toSelection)
  editor.setMode "normal"

proc vimSelectMove(editor: TextDocumentEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-select-move").} =
  # infof"vimSelectMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.updateTargetColumn()

proc vimDeleteMove(editor: TextDocumentEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-delete-move").} =
  # infof"vimDeleteMove '{move}' {count}"
  let oldSelections = editor.selections
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.vimDeleteSelection(false, oldSelections=oldSelections.some)

  editor.recordCurrentCommandInPeriodMacro()

proc vimChangeMove(editor: TextDocumentEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-change-move").} =
  # infof"vimChangeMove '{move}' {count}"
  let oldSelections = editor.selections
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.vimChangeSelection(false, oldSelections=oldSelections.some)

proc vimYankMove(editor: TextDocumentEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-yank-move").} =
  # infof"vimYankMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    editor.runAction(action, arg)
  editor.vimYankSelection()

proc vimFinishMotion(editor: TextDocumentEditor) =
  let command = getSessionData[string]("editor.text.vim-motion-action")
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
    setSessionData("editor.text.vim-motion-action", "")

  editor.updateTargetColumn()
  let nextMode = vimMotionNextMode.getOrDefault(editor.id, "normal")
  editor.setMode nextMode

proc vimMoveTo*(editor: TextDocumentEditor, target: string, before: bool, count: int = 1) {.exposeActive(editorContext, "vim-move-to").} =
  # infof"vimMoveTo '{target}' {before}"

  proc parseTarget(target: string): string =
    if target.len == 1:
      return target

    if target.parseFirstInput().getSome(res):
      if res.inputCode.a == INPUT_SPACE:
        return " "
      elif res.inputCode.a <= int32.high:
        return $Rune(res.inputCode.a)
    else:
      infof" -> failed to parse key: {target}"

  let key = parseTarget(target)

  for _ in 0..<max(1, count):
    editor.moveCursorTo(key)
  if before:
    editor.moveCursorColumn(-1)
  editor.updateTargetColumn()

proc vimClamp*(editor: TextDocumentEditor, cursor: Cursor): Cursor =
  var lineLen = editor.lineLength(cursor.line)
  if not editor.vimState.cursorIncludeEol and lineLen > 0: lineLen.dec
  result = (cursor.line, min(cursor.column, lineLen))

proc vimMotionLine*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  var lineLen = editor.lineLength(cursor.line)
  if not editor.vimState.cursorIncludeEol and lineLen > 0: lineLen.dec
  result = ((cursor.line, 0), (cursor.line, lineLen))

proc vimMotionVisualLine*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  var lineLen = editor.lineLength(cursor.line)
  result = editor.getSelectionForMove(cursor, "visual-line", count)
  if not editor.vimState.cursorIncludeEol and result.last.column > result.first.column:
    result.last.column.dec
  elif result.last.column < lineLen: # This is the case if we're not in the last visual sub line
    result.last.column.dec

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
  if result.last.column < editor.lineLength(result.last.line) and editor.getChar(result.last) in Whitespace:
    result.last = editor.vimMotionWord(result.last, 1).last

proc vimMotionWordBigOuter*(editor: TextDocumentEditor, cursor: Cursor, count: int): Selection =
  result = vimMotionWordBig(editor, cursor, count)
  if result.last.column < editor.lineLength(result.last.line) and editor.getChar(result.last) in Whitespace:
    result.last = editor.vimMotionWordBig(result.last, 1).last

proc charAt*(editor: TextDocumentEditor, cursor: Cursor): char =
  let res = editor.getText(cursor.toSelection, inclusiveEnd=true)
  if res.len > 0:
    return res[0]
  else:
    return '\0'

proc vimMotionSurround*(editor: TextDocumentEditor, cursor: Cursor, count: int, c0: char, c1: char, inside: bool): Selection =
  result = cursor.toSelection
  # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}"
  while true:
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

proc vimMoveToMatching(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-move-to-matching").} =
  let which = if editor.mode == "visual" or editor.mode == "visual-line":
    SelectionCursor.Last
  else:
    SelectionCursor.Both

  editor.selections = editor.selections.mapIt(block:
    let c = editor.charAt(it.last)
    let (open, close, last) = case c
      of '(': ('(', ')', true)
      of '{': ('{', '}', true)
      of '[': ('[', ']', true)
      of '<': ('<', '>', true)
      of ')': ('(', ')', false)
      of '}': ('{', '}', false)
      of ']': ('[', ']', false)
      of '>': ('<', '>', false)
      of '"': ('"', '"', true)
      of '\'': ('\'', '\'', true)
      else: return

    let selection = editor.vimMotionSurround(it.last, 0, open, close, false)

    if last:
      selection.last.toSelection(it, which)
    else:
      selection.first.toSelection(it, which)
  )

  editor.scrollToCursor Last
  editor.updateTargetColumn()

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
addCustomTextMove "vim-line", vimMotionLine
addCustomTextMove "vim-visual-line", vimMotionVisualLine
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
addCustomTextMove "vim-surround-angle-inner", vimMotionSurroundAngleInner
addCustomTextMove "vim-surround-angle-outer", vimMotionSurroundAngleOuter
addCustomTextMove "vim-surround-\"-inner", vimMotionSurroundDoubleQuotesInner
addCustomTextMove "vim-surround-\"-outer", vimMotionSurroundDoubleQuotesOuter
addCustomTextMove "vim-surround-'-inner", vimMotionSurroundSingleQuotesInner
addCustomTextMove "vim-surround-'-outer", vimMotionSurroundSingleQuotesOuter

iterator iterateTextObjects*(editor: TextDocumentEditor, cursor: Cursor, move: string, backwards: bool = false): Selection =
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
    let newSelection = editor.getSelectionForMove(nextCursor, move, 0)
    # infof"iterateTextObjects({cursor}, {move}, {backwards}) nextCursor: {nextCursor}, newSelection: {newSelection}"
    if newSelection == lastSelection:
      break

    selection = newSelection
    yield selection

iterator enumerateTextObjects*(editor: TextDocumentEditor, cursor: Cursor, move: string, backwards: bool = false): (int, Selection) =
  var i = 0
  for selection in iterateTextObjects(editor, cursor, move, backwards):
    yield (i, selection)
    inc i

proc vimSelectTextObject(editor: TextDocumentEditor, textObject: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.exposeActive(editorContext, "vim-select-text-object").} =
  # infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count})"

  editor.selections = editor.selections.mapIt(block:
      var res = it.last
      var resultSelection = it
      # infof"-> {resultSelection}"

      for i, selection in enumerateTextObjects(editor, res, textObject, backwards):
        # infof"{i}: {res} -> {selection}"
        resultSelection = resultSelection or selection
        if i == max(count, 1) - 1:
          break

      # infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count}): {resultSelection}"
      if it.isBackwards:
        resultSelection.reverse
      else:
        resultSelection
    )

  editor.scrollToCursor(Last)
  editor.updateTargetColumn()

proc vimSelectSurrounding(editor: TextDocumentEditor, textObject: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.exposeActive(editorContext, "vim-select-surrounding").} =
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
  editor.updateTargetColumn()

proc moveSelectionNext(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext, "move-selection-next").} =
  # infof"moveSelectionNext '{move}' {count} {backwards} {allowEmpty}"
  editor.vimState.deleteInclusiveEnd = false
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

          if selection.first.column >= editor.lineLength(selection.first.line) or editor.getChar(selection.first) notin Whitespace:
            res = cursor
            break
      # echo res, ", ", it, ", ", which
      res.toSelection(it, which)
    )

  editor.scrollToCursor(Last)
  editor.updateTargetColumn()

proc applyMove(editor: TextDocumentEditor, selections: seq[Selection], move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, which: Option[SelectionCursor] = SelectionCursor.none): seq[Selection] =
  ## Applies the given move `count` times and returns the resulting selections
  ## `allowEmpty` If true then the move can stop on empty lines
  ## `backwards` Move backwards
  ## `count` How often to apply the move
  ## `which` How to assemble the final selection from the input and the move. If not set uses `editor.text.cursor.movement`

  # infof"moveSelectionEnd '{move}' {count} {backwards} {allowEmpty}"
  let which = which.get(getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both))
  return selections.mapIt(block:
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
              editor.getChar(selection.last) notin Whitespace:
            res = cursor
            break
          if backwards and selection.last.column == editor.lineLength(selection.last.line):
            res = cursor
            break
      res.toSelection(it, which)
    )

proc moveSelectionEnd(editor: TextDocumentEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext, "move-selection-end").} =

  editor.selections = editor.applyMove(editor.selections, move, backwards, allowEmpty, count)
  editor.scrollToCursor(Last)
  editor.updateTargetColumn()

proc moveParagraph(editor: TextDocumentEditor, backwards: bool, count: int = 1) {.exposeActive(editorContext, "move-paragraph").} =
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

  if editor.vimState.selectLines:
    editor.vimSelectLine()

  editor.scrollToCursor(Last)
  editor.updateTargetColumn()

proc vimDeleteLeft*(editor: TextDocumentEditor) =
  yankedLines = editor.vimState.selectLines
  editor.copy()
  editor.addNextCheckpoint "insert"
  editor.deleteLeft()

proc vimDeleteRight*(editor: TextDocumentEditor) =
  yankedLines = editor.vimState.selectLines
  editor.copy()
  editor.addNextCheckpoint "insert"
  editor.deleteRight(includeAfter=editor.vimState.cursorIncludeEol)

exposeActive editorContext, "vim-delete-left", vimDeleteLeft

proc vimMoveCursorColumn(editor: TextDocumentEditor, direction: int, count: int = 1) {.exposeActive(editorContext, "vim-move-cursor-column").} =
  editor.moveCursorColumn(direction * max(count, 1), wrap=false, includeAfter=editor.vimState.cursorIncludeEol)
  if editor.vimState.selectLines:
    editor.vimSelectLine()
  editor.updateTargetColumn()

proc vimMoveCursorLine(editor: TextDocumentEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext, "vim-move-cursor-line").} =
  editor.moveCursorLine(direction * max(count, 1), includeAfter=editor.vimState.cursorIncludeEol)
  let nextScrollBehaviour = if center: CenterAlways.some else: ScrollBehaviour.none
  editor.scrollToCursor(Last, scrollBehaviour = nextScrollBehaviour)
  editor.setNextSnapBehaviour(Never)
  if editor.vimState.selectLines:
    editor.vimSelectLine()

proc vimMoveCursorVisualLine(editor: TextDocumentEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext, "vim-move-cursor-visual-line").} =
  if editor.vimState.selectLines:
    editor.moveCursorLine(direction * max(count, 1), includeAfter=editor.vimState.cursorIncludeEol)
  else:
    editor.moveCursorVisualLine(direction * max(count, 1), includeAfter=editor.vimState.cursorIncludeEol)
  let defaultScrollBehaviour = editor.getDefaultScrollBehaviour
  let defaultCenter = defaultScrollBehaviour in {CenterAlways, CenterOffscreen}
  let nextScrollBehaviour = if center and defaultCenter: CenterAlways.some else: ScrollBehaviour.none
  editor.scrollToCursor(Last, scrollBehaviour = nextScrollBehaviour)
  editor.setNextSnapBehaviour(Never)
  if editor.vimState.selectLines:
    editor.vimSelectLine()

proc vimMoveFirst(editor: TextDocumentEditor, move: string) {.exposeActive(editorContext, "vim-move-first").} =
  editor.moveFirst(move)
  if editor.vimState.selectLines:
    editor.vimSelectLine()
  editor.updateTargetColumn()

proc vimMoveLast(editor: TextDocumentEditor, move: string) {.exposeActive(editorContext, "vim-move-last").} =
  editor.moveLast(move)
  if editor.vimState.selectLines:
    editor.vimSelectLine()
  editor.updateTargetColumn()

proc vimMoveToEndOfLine(editor: TextDocumentEditor, count: int = 1) =
  # infof"vimMoveToEndOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveLast("vim-line")
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimMoveToEndOfVisualLine(editor: TextDocumentEditor, count: int = 1) =
  # infof"vimMoveToEndOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveLast("vim-visual-line")
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimMoveCursorLineFirstChar(editor: TextDocumentEditor, direction: int, count: int = 1) =
  editor.moveCursorLine(direction * max(count, 1))
  editor.moveFirst "line-no-indent"
  editor.updateTargetColumn()

proc vimMoveToStartOfLine(editor: TextDocumentEditor, count: int = 1) =
  # infof"vimMoveToStartOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveFirst "line-no-indent"
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimPaste(editor: TextDocumentEditor, pasteRight: bool = false, inclusiveEnd: bool = false, register: string = "") {.exposeActive(editorContext, "vim-paste").} =
  # infof"vimPaste {register}, lines: {yankedLines}"
  editor.addNextCheckpoint "insert"

  let selectionsToDelete = editor.selections
  editor.selections = editor.delete(selectionsToDelete, inclusiveEnd=false)

  if yankedLines:
    if editor.mode != "visual-line":
      editor.moveLast "line", Both
      editor.insertText "\n", autoIndent=false

  if pasteRight:
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)

  editor.setMode "normal"
  editor.paste register, inclusiveEnd=inclusiveEnd

proc vimToggleCase(editor: TextDocumentEditor, moveCursorRight: bool) {.exposeActive(editorContext, "vim-toggle-case").} =
  var editTexts: seq[string]

  for s in editor.selections:
    let text = editor.getText(s, inclusiveEnd=true)
    var newText = ""
    for r in text.runes:
      if r.isLower:
        newText.add $r.toUpper
      else:
        newText.add $r.toLower
    editTexts.add newText

  editor.addNextCheckpoint "insert"
  let oldSelections = editor.selections
  discard editor.edit(editor.selections, editTexts, inclusiveEnd=true)
  editor.selections = oldSelections.mapIt(it.first.toSelection)

  editor.setMode "normal"

  if moveCursorRight:
    editor.moveCursorColumn(1, Both, wrap=false,
      includeAfter=editor.vimState.cursorIncludeEol)
    editor.updateTargetColumn()

proc vimCloseCurrentViewOrQuit() {.exposeActive(editorContext, "vim-close-current-view-or-quit").} =
  let openEditors = getNumVisibleViews() + getNumHiddenViews()
  if openEditors == 1:
    plugin_runtime.quit()
  else:
    closeActiveView()

proc vimIndent(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-indent").} =
  editor.addNextCheckpoint "insert"
  editor.indent()

proc vimUnindent(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-unindent").} =
  editor.addNextCheckpoint "insert"
  editor.unindent()

proc vimAddCursorAbove(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-add-cursor-above").} =
  editor.addCursorAbove()
  editor.scrollToCursor(Last)

proc vimAddCursorBelow(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-add-cursor-below").} =
  editor.addCursorBelow()
  editor.scrollToCursor(Last)

var onModeChangedHandle: Id

proc loadVimKeybindings*() {.expose("load-vim-keybindings").} =
  let t = startTimer()
  defer:
    infof"loadVimKeybindings: {t.elapsed.ms} ms"

  info "Applying Vim keybindings"

  clearCommands("editor.text")
  clearCommands("editor.text.completion")
  for id in getAllEditors():
    if id.isTextEditor(editor):
      editor.setMode("normal")
      editor.setCustomHeader("vim")

  setHandleInputs "editor.text", false
  setSessionData "editor.text.vim-motion-action", "vim-select-last-cursor"
  setOption "editor.text.cursor.movement.", "last"
  setOption "editor.text.cursor.movement.normal", "last"
  setOption "editor.text.cursor.wide.", true
  setOption "text.default-mode", "normal"
  setOption "text.inclusive-selection", false

  setHandleInputs "editor.text.normal", false
  setOption "editor.text.cursor.wide.normal", true

  setHandleInputs "editor.text.insert", true
  setOption "editor.text.cursor.wide.insert", false

  setHandleInputs "editor.text.visual", false
  setOption "editor.text.cursor.wide.visual", true
  setOption "editor.text.cursor.movement.visual", "last"

  setHandleInputs "editor.text.visual-line", false
  setOption "editor.text.cursor.wide.visual-line", true
  setOption "editor.text.cursor.movement.visual-line", "last"

  setHandleInputs "terminal", false
  setHandleKeys "terminal", false

  setHandleInputs "terminal.normal", false
  setHandleKeys "terminal.normal", false

  setHandleInputs "terminal.insert", true
  setHandleKeys "terminal.insert", true

  addModeChangedHandler onModeChangedHandle, proc(editor, oldMode, newMode: auto) {.gcsafe, raises: [].} =
    if not editor.getCurrentEventHandlers().contains("editor.text"):
      return

    if newMode == "":
      editor.setMode "normal"
      return

    let recordModes = [
      "visual",
      "visual-line",
      "insert",
    ].toHashSet

    # infof"vim: handle mode change {oldMode} -> {newMode}"
    if newMode == "normal":
      if not isReplayingCommands() and isRecordingCommands(".-temp"):
        stopRecordingCommands(".-temp")

        if editor.getRevision > editor.vimState.revisionBeforeImplicitInsertMacro:
          infof"Record implicit macro because document was modified"
          let text = getRegisterText(".-temp")
          setRegisterText(text, ".")
        else:
          infof"Don't record implicit macro because nothing was modified"
    else:
      if oldMode == "normal" and newMode in recordModes:
        editor.startRecordingCurrentCommandInPeriodMacro()

      editor.clearCurrentCommandHistory(retainLast=true)

    editor.vimState.selectLines = newMode == "visual-line"
    editor.vimState.cursorIncludeEol = newMode == "insert"
    editor.vimState.currentUndoCheckpoint = if newMode == "insert": "word" else: "insert"

    case newMode
    of "normal":
      setSessionData "editor.text.vim-motion-action", "vim-select-last-cursor"
      setOption "text.inclusive-selection", false
      vimMotionNextMode[editor.id] = "normal"
      editor.selections = editor.selections.mapIt(editor.vimClamp(it.last).toSelection)
      editor.saveCurrentCommandHistory()
      editor.hideCompletions()

    of "insert":
      setOption "text.inclusive-selection", false
      setSessionData "editor.text.vim-motion-action", ""
      vimMotionNextMode[editor.id] = "insert"

    of "visual":
      setOption "text.inclusive-selection", true

    else:
      setOption "text.inclusive-selection", false

  addTextCommand "#count", "<-1-9><o-0-9>", ""
  addCommand "#count", "<-1-9><o-0-9>", ""

  # Normal mode
  addCommand "editor", ":", "command-line"

  addTextCommandBlockDesc "", "<C-e>", "exit to normal mode":
    editor.selection = editor.selection
    editor.setMode("normal")

  addTextCommandBlockDesc "", "<ESCAPE>", "exit to normal mode and clear things":
    if editor.mode == "normal":
      editor.selection = editor.selection
      editor.clearTabStops()
    editor.setMode("normal")

  addCommandBlockDesc "command-line-low", "<ESCAPE>", "exit to normal mode and clear things":
    if getActiveEditor().isTextEditor(editor):
      if editor.mode == "normal":
        exitCommandLine()
        return

      if editor.mode == "normal":
        editor.clearTabStops()
      editor.setMode("normal")

  addCommandBlockDesc "command-line-result-low", "<ESCAPE>", "exit to normal mode and clear things":
    if getActiveEditor().isTextEditor(editor):
      if editor.mode == "normal":
        exitCommandLine()
        return

      if editor.mode == "normal":
        editor.clearTabStops()
      editor.setMode("normal")

  addCommandBlockDesc "popup.selector", "<ESCAPE>", "Close":
    if getActiveEditor().isTextEditor(editor):
      if editor.mode == "normal":
        if getActivePopup().isSelectorPopup(popup):
          popup.cancel()
        return

      if editor.mode == "normal":
        editor.clearTabStops()
      editor.setMode("normal")

  addTextCommandBlockDesc "", ".", "replay commands": replayCommands(".")
  addCommand "editor.text.normal", "@<CHAR>", "<CHAR>", source = currentSourceLocation(), action = proc(editor: TextDocumentEditor, c: string) =
    let register = if c == "@":
      getOption("editor.current-macro-register", "")
    else:
      c

    replayCommands(register)

  addCommand "editor.text.normal", "q<CHAR>", "<CHAR>", source = currentSourceLocation(), action = proc(editor: TextDocumentEditor, c: string) =
    if isReplayingCommands() or isRecordingCommands(getCurrentMacroRegister()):
      return
    setOption("editor.current-macro-register", c)
    setRegisterText("", c)
    startRecordingCommands(c)

  addTextCommandBlockDesc "", "Q", "stop recording macro":
    if isReplayingCommands() or not isRecordingCommands(getCurrentMacroRegister()):
      return
    stopRecordingCommands(getCurrentMacroRegister())

  # windowing
  proc defineWindowingCommands(prefix: string) =
    withKeys prefix:
      addCommand "editor", "h", "focus-prev-view"
      addCommand "editor", "<C-h>", "focus-prev-view"
      addCommand "editor", "<LEFT>", "focus-prev-view"
      addCommand "editor", "l", "focus-next-view"
      addCommand "editor", "<C-l>", "focus-next-view"
      addCommand "editor", "<RIGHT>", "focus-next-view"
      addCommand "editor", "w", "focus-next-view"
      addCommand "editor", prefix, "focus-next-view"
      addCommand "editor", "p", "open-prev-view"
      addCommand "editor", "<C-p>", "open-prev-view"
      addCommand "editor", "q", "vim-close-current-view-or-quit"
      addCommand "editor", "<C-q>", "close-active-view"
      addCommand "editor", "c", "hide-active-view"
      addCommand "editor", "C", "close-active-view"
      addCommand "editor", "o", "close-other-views"
      addCommand "editor", "<C-o>", "close-other-views"

      # not very vim like, but the windowing system works quite differently
      addCommand "editor", "H", "move-active-view-prev"
      addCommand "editor", "L", "move-active-view-next"
      addCommand "editor", "W", "move-active-view-first"

  addCommand "editor", "<C-o>", "open-prev-view"

  # In the browser C-w closes the tab, so we use A-w instead
  if getBackend() == Browser:
    defineWindowingCommands "<A-w>"
    addCommand "editor", "<count><A-w>m", "set-max-views <#count> true"
  else:
    defineWindowingCommands "<C-w>"
    addCommand "editor", "<count><C-w>m", "set-max-views <#count> true"

  addCommandBlock "editor", "<LEADER>m":
    toggleMaximizeView()

  # completion
  addTextCommand "insert", "<C-p>", "get-completions"
  addTextCommand "insert", "<C-n>", "get-completions"
  addTextCommand "completion", "<C-p>", "select-prev-completion"
  addTextCommand "completion", "<C-n>", "select-next-completion"
  addTextCommand "completion", "<C-y>", "apply-selected-completion"
  addTextCommand "completion", "<TAB>", "apply-selected-completion"

  addTextCommand "", "<move>", "vim-select-last <move>"
  addTextCommand "", "<?-count>d<move>", """vim-delete-move <move> <#count>"""
  addTextCommand "", "<?-count>c<move>", """vim-change-move <move> <#count>"""
  addTextCommand "", "<?-count>y<move>", """vim-yank-move <move> <#count>"""

  addTextCommand "", "<?-count>d<text_object>", """vim-delete-move <text_object> <#count>"""
  addTextCommand "", "<?-count>c<text_object>", """vim-change-move <text_object> <#count>"""
  addTextCommand "", "<?-count>y<text_object>", """vim-yank-move <text_object> <#count>"""

  # navigation (horizontal)

  addSubCommandWithCount "", "move", "h", "vim-move-cursor-column", -1
  addSubCommandWithCount "", "move", "<LEFT>", "vim-move-cursor-column", -1

  addSubCommandWithCount "", "move", "l", "vim-move-cursor-column", 1
  addSubCommandWithCount "", "move", "<RIGHT>", "vim-move-cursor-column", 1

  addSubCommand "", "move", "0", "vim-move-first", "line"
  # addSubCommand "", "move", "<HOME>", "vim-move-first", "line"
  addSubCommand "", "move", "<HOME>", "vim-move-first", "visual-line"
  addSubCommand "", "move", "^", "vim-move-first", "line-no-indent"

  addSubCommandWithCount "", "move", "$", vimMoveToEndOfLine
  # addSubCommandWithCount "", "move", "<END>", vimMoveToEndOfLine
  addSubCommandWithCount "", "move", "<END>", vimMoveToEndOfVisualLine

  addSubCommand "", "move", "g0", "vim-move-first", "line"
  addSubCommand "", "move", "g^", "vim-move-first", "line-no-indent"

  addSubCommandWithCount "", "move", "g$", vimMoveToEndOfLine
  addSubCommand "", "move", "gm", "move-cursor-line-center"
  addSubCommand "", "move", "gM", "move-cursor-center"

  addSubCommandWithCountBlock "", "move", "|":
    editor.selections = editor.selections.mapIt((it.last.line, count).toSelection)
    editor.scrollToCursor Last
    editor.updateTargetColumn()

  # navigation (vertical)
  addSubCommandWithCount "", "move", "k", "vim-move-cursor-visual-line", -1
  addSubCommandWithCount "", "move", "<UP>", "vim-move-cursor-visual-line", -1

  addSubCommandWithCount "", "move", "j", "vim-move-cursor-visual-line", 1
  addSubCommandWithCount "", "move", "<DOWN>", "vim-move-cursor-visual-line", 1
  addSubCommandWithCount "", "move", "<C-j>", "vim-move-cursor-visual-line", 1

  addSubCommandWithCountBlock "", "move", "-": vimMoveCursorLineFirstChar(editor, -1, count)
  addSubCommandWithCountBlock "", "move", "+": vimMoveCursorLineFirstChar(editor, 1, count)

  addSubCommandWithCountBlock "", "move", "_": vimMoveToStartOfLine(editor, count)

  addSubCommandWithCountBlock "", "move", "gg":
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.selection = (count - 1, 0).toSelection(editor.selection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addSubCommandWithCountBlock "", "move", "G":
    let line = if count == 0: editor.lineCount - 1 else: count - 1
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    var newSelection = (line, 0).toSelection(editor.selection, which)
    if newSelection == editor.selection:
      let lineLen = editor.lineLength(line)
      editor.selection = (line, lineLen).toSelection(editor.selection, which)
    else:
      editor.selection = newSelection
      editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addSubCommandWithCountBlock "", "move", "%":
    if count == 0:
      editor.vimMoveToMatching()
    else:
      let line = clamp((count * editor.lineCount) div 100, 0, editor.lineCount - 1)
      let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
      editor.selection = (line, 0).toSelection(editor.selection, which)
      editor.moveFirst "line-no-indent"
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addSubCommandWithCount "", "move", "k", "vim-move-cursor-visual-line", -1
  addSubCommandWithCount "", "move", "j", "vim-move-cursor-visual-line", 1

  # search
  addTextCommandBlockDesc "", "*", "set search query to word":
    editor.selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b").first.toSelection
  addTextCommandBlockDesc "visual", "*", "set search query to selection":
    discard editor.setSearchQuery(editor.getText(editor.selection, inclusiveEnd=true), escapeRegex=true)
    editor.selection = editor.selection.first.toSelection
    editor.setMode("normal")
  addTextCommandBlockDesc "", "n", "go to next search result":
    editor.selection = editor.getNextFindResult(editor.selection.last).first.toSelection
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()
  addTextCommandBlockDesc "", "N", "go to previous search result":
    editor.selection = editor.getPrevFindResult(editor.selection.last).first.toSelection
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

  addTextCommandBlockDesc "", "/", "open search bar":
    editor.openSearchBar()
    if getActiveEditor().isTextEditor(editor):
      editor.setMode("insert")

  addTextCommandBlockDesc "", r"\\", "open global search bar":
    commandLine(r"search-global \")
    if getActiveEditor().isTextEditor(editor):
      var arr = newJArray()
      arr.add newJString("file")
      discard editor.runAction("move-last", arr)
      editor.setMode("insert")
      editor.updateTargetColumn()

  # Scrolling
  addTextCommand "", "<C-e>", "scroll-lines", -2
  addTextCommand "", "<CS-e>", "scroll-text-horizontal", -4
  addSubCommandWithCountBlock "", "move", "<C-d>": editor.vimMoveCursorVisualLine(editor.screenLineCount div 2, count, center=true)
  addSubCommandWithCountBlock "", "move", "<PAGE_DOWN>": editor.vimMoveCursorVisualLine(editor.screenLineCount, count, center=true)

  addTextCommand "", "<C-y>", "scroll-lines", 2
  addTextCommand "", "<CS-y>", "scroll-text-horizontal", 4
  addSubCommandWithCountBlock "", "move", "<C-u>": editor.vimMoveCursorVisualLine(-editor.screenLineCount div 2, count, center=true)
  addSubCommandWithCountBlock "", "move", "<PAGE_UP>": editor.vimMoveCursorVisualLine(-editor.screenLineCount, count, center=true)

  addTextCommandBlockDesc "", "z<ENTER>", "scroll line to top":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.vimFinishMotion()
    editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

  addTextCommandBlockDesc "", "zt", "scroll line to top":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
      editor.vimFinishMotion()
    editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

  addTextCommandBlockDesc "", "z.", "center line":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.vimFinishMotion()
    editor.centerCursor()

  addTextCommandBlockDesc "", "zz", "center line":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
      editor.vimFinishMotion()
    editor.centerCursor()

  addTextCommandBlockDesc "", "z-", "scroll line to bottom":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, 0).toSelection
    editor.moveFirst "line-no-indent"
    editor.vimFinishMotion()
    editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

  addTextCommandBlockDesc "", "zb", "scroll line to bottom":
    if editor.getCommandCount != 0:
      editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
      editor.vimFinishMotion()
    editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

  # Mode switches
  addTextCommandBlock "normal", "a":
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "", "A":
    editor.moveLast "line", Both
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "normal", "i":
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "", "I":
    editor.moveFirst "line-no-indent", Both
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"
  addTextCommandBlock "normal", "gI":
    editor.moveFirst "line", Both
    editor.setMode "insert"
    editor.addNextCheckpoint "insert"

  addTextCommandBlock "normal", "o":
    editor.moveLast "line", Both
    editor.addNextCheckpoint "insert"
    editor.insertText "\n"
    editor.setMode "insert"

  addTextCommandBlock "normal", "O":
    editor.moveFirst "line", Both
    editor.addNextCheckpoint "insert"
    editor.insertText "\n", autoIndent=false
    editor.vimMoveCursorLine -1
    editor.setMode "insert"

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
  addTextObjectCommand "", r"\<", "vim-surround-angle"
  addTextObjectCommand "", r"\>", "vim-surround-angle"
  addTextObjectCommand "", "\"", "vim-surround-\""
  addTextObjectCommand "", "'", "vim-surround-'"

  # marks
  addCommand "editor.text", "m<CHAR>", "<CHAR>", source = currentSourceLocation(), action = proc(editor: TextDocumentEditor, c: string) =
    editor.vimState.marks[c] = editor.createAnchors(editor.selections)

  addCommand "editor.text", "'<CHAR>", "<CHAR>", source = currentSourceLocation(), action = proc(editor: TextDocumentEditor, c: string) =
    if c in editor.vimState.marks:
      let newSelections = editor.resolveAnchors(editor.vimState.marks[c])
      case editor.mode
      of "visual", "visual-line":
        let oldSelections = editor.selections
        if newSelections.len == oldSelections.len:
          editor.selections = collect:
            for i in 0..newSelections.high:
              oldSelections[i] or newSelections[i]
        else:
          editor.selections = newSelections
      else:
        editor.selections = newSelections

      editor.updateTargetColumn()
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addTextCommandBlock "", "dd":
    editor.vimState.selectLines = true
    let oldSelections = editor.selections
    editor.vimSelectLine()
    editor.vimDeleteSelection(true, oldSelections=oldSelections.some)
    editor.vimState.selectLines = false

  addTextCommandBlock "", "cc":
    let oldSelections = editor.selections
    editor.vimSelectLine()
    editor.vimChangeSelection(true, oldSelections=oldSelections.some)

  addTextCommandBlock "", "yy":
    editor.vimState.selectLines = true
    editor.vimSelectLine()
    editor.vimYankSelection()
    editor.vimState.selectLines = false

  addTextCommandBlock "", "D":
    let oldSelections = editor.selections
    editor.selections = editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
    editor.vimDeleteSelection(true, oldSelections=oldSelections.some)
    editor.vimState.selectLines = false

  addTextCommandBlock "", "C":
    let oldSelections = editor.selections
    editor.selections = editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
    editor.vimChangeSelection(true, oldSelections=oldSelections.some)
    editor.vimState.selectLines = false

  addTextCommandBlock "", "Y":
    editor.selections = editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
    editor.vimYankSelection()
    editor.vimState.selectLines = false

  addTextCommand "", "~", "vim-toggle-case", true
  addTextCommand "visual", "~", "vim-toggle-case", false
  addTextCommand "visual-line", "~", "vim-toggle-case", false

  # replace
  addTextCommand "", "r", "set-mode", "replace"
  setHandleInputs "editor.text.replace", true
  setTextInputHandler "replace", proc(editor: TextDocumentEditor, input: string): bool =
    editor.vimReplace(input)
    return true

  addTextCommand "replace", "<SPACE>", "vim-replace", " "
  addTextCommand "replace", "<ESCAPE>", "set-mode", "normal"

  # Deleting text
  addTextCommand "", "x", vimDeleteRight, source = currentSourceLocation()
  addTextCommand "", "<DELETE>", vimDeleteRight, source = currentSourceLocation()
  addTextCommand "", "X", vimDeleteLeft, source = currentSourceLocation()

  addTextCommand "", "u", "vim-undo", enterNormalModeBefore=true
  addTextCommand "", "<C-r>", "vim-redo", enterNormalModeBefore=true
  addTextCommand "", "p", "vim-paste", pasteRight=true, inclusiveEnd=false, getVimDefaultRegister()
  addTextCommand "visual", "p", "vim-paste", pasteRight=false, inclusiveEnd=true, getVimDefaultRegister()
  addTextCommand "visual-line", "p", "vim-paste", pasteRight=false, inclusiveEnd=true, getVimDefaultRegister()
  addTextCommand "", "P", "vim-paste", pasteRight=true, inclusiveEnd=false
  addTextCommand "visual", "P", "vim-paste", pasteRight=false, inclusiveEnd=true
  addTextCommand "visual-line", "P", "vim-paste", pasteRight=false, inclusiveEnd=true

  addTextCommandBlock "", "<ENTER>":
    editor.addNextCheckpoint "insert"
    editor.insertText "\n"

  addTextCommand "", r"\>\>", "vim-indent"
  addTextCommand "", r"\<\<", "vim-unindent"

  addTextCommandBlock "normal", "s":
    editor.setMode "visual"
    editor.vimChangeSelection(true)

  addTextCommandBlock "normal", "J":
    editor.addNextCheckpoint "insert"
    var insertTexts: seq[string]
    let selectionsToDelete = editor.selections.mapIt(block:
      let lineLen = editor.lineLength(it.last.line)
      if lineLen == 0 or editor.charAt((it.last.line, lineLen - 1)) == ' ':
        insertTexts.add ""
      else:
        insertTexts.add " "
      var nextLineIndent = editor.getSelectionForMove((it.last.line + 1, 0), "line-no-indent", 0)
      ((it.last.line, lineLen), (it.last.line + 1, nextLineIndent.first.column))
    )
    editor.selections = editor.edit(selectionsToDelete, insertTexts, inclusiveEnd=false).mapIt(it.first.toSelection)

  addTextCommandBlock "normal", "gJ":
    editor.addNextCheckpoint "insert"
    let selectionsToDelete = editor.selections.mapIt(block:
      let lineLen = editor.lineLength(it.last.line)
      ((it.last.line, lineLen), (it.last.line + 1, 0))
    )
    editor.selections = editor.delete(selectionsToDelete, inclusiveEnd=false).mapIt(it.first.toSelection)

  # Insert mode
  addTextCommand "insert", "<C-r>", "set-mode", "insert-register"
  setHandleInputs "editor.text.insert-register", true
  setTextInputHandler "insert-register", proc(editor: TextDocumentEditor, input: string): bool =
    editor.vimPaste register=input, inclusiveEnd=true
    editor.setMode "insert"
    return true
  addTextCommandBlock "insert-register", "<SPACE>":
    editor.vimPaste register=getVimDefaultRegister(), inclusiveEnd=true
    editor.setMode "insert"
  addTextCommand "insert-register", "<ESCAPE>", "set-mode", "insert"

  addTextCommand "insert", "<SPACE>", "insert-text", " "
  addTextCommand "insert", "<BACKSPACE>", "delete-left"
  addTextCommand "insert", "<DELETE>", "delete-right"
  addTextCommandBlock "insert", "<C-w>":
    let selections = editor.applyMove(editor.selections, "vim-word", true, true, 1, which = SelectionCursor.Last.some)
    editor.selections = editor.delete(selections)
    editor.autoShowCompletions()

  addTextCommandBlock "insert", "<C-u>":
    let selections = editor.applyMove(editor.selections, "vim-line", true, true, 1, which = SelectionCursor.Last.some)
    editor.selections = editor.delete(selections)
    editor.autoShowCompletions()

  addTextCommand "insert", "<C-t>", "vim-indent"
  addTextCommand "insert", "<C-d>", "vim-unindent"

  # Visual mode
  addTextCommandBlock "", "v":
    editor.setMode "visual"
    setSessionData "editor.text.vim-motion-action", ""
    vimMotionNextMode[editor.id] = "visual"

  addTextCommand "visual", "<move>", "vim-select <move>"
  addTextCommand "visual", "y", "vim-yank-selection"
  addTextCommand "visual", "gy", "vim-yank-selection-clipboard"
  addTextCommand "visual", "d", "vim-delete-selection", true
  addTextCommand "visual", "c", "vim-change-selection", true
  addTextCommand "visual", "s", "vim-change-selection", true

  addTextCommandBlock "visual", "x":
    editor.vimDeleteRight()
    editor.setMode "normal"
  addTextCommandBlock "visual", "<DELETE>":
    editor.vimDeleteRight()
    editor.setMode "normal"
  addTextCommandBlock "visual", "X":
    editor.vimDeleteLeft()
    editor.setMode "normal"

  addTextCommand "visual", "<?-count><text_object>", """vim-select-move <text_object> <#count>"""

  addTextCommand "visual", r"\>", "vim-indent"
  addTextCommand "visual", r"\<", "vim-unindent"

  # Visual line mode
  addTextCommandBlock "", "V":
    editor.setMode "visual-line"
    editor.vimSelectLine()
    # setSessionData "editor.text.vim-motion-action", ""
    # vimMotionNextMode[editor.id] = "visual"

  addTextCommand "visual-line", "<move>", "vim-select <move>"
  addTextCommand "visual-line", "y", "vim-yank-selection"
  addTextCommand "visual-line", "gy", "vim-yank-selection-clipboard"
  addTextCommand "visual-line", "d", "vim-delete-selection", true
  addTextCommand "visual-line", "c", "vim-change-selection", true
  addTextCommand "visual-line", "s", "vim-change-selection", true

  addTextCommand "visual-line", "<?-count><text_object>", """vim-select-move <text_object> <#count>"""

  addTextCommand "visual-line", r"\>", "vim-indent"
  addTextCommand "visual-line", r"\<", "vim-unindent"

  # todo: not really vim keybindings
  addTextCommand "", "gd", "goto-definition"
  addTextCommand "", "gD", "goto-declaration"
  addTextCommand "", "gi", "goto-implementation"
  addTextCommand "", "gT", "goto-type-definition"
  addTextCommand "", "gs", "goto-symbol"
  addTextCommand "", "gw", "goto-workspace-symbol"
  addTextCommand "", "gr", "goto-references"
  addTextCommand "", "go", "switch-source-header"
  addTextCommand "", "ga", "select-code-action"
  addTextCommand "", "gR", "rename"
  addTextCommand "", "K", "show-hover-for-current"
  addTextCommand "", "H", "show-diagnostics-for-current"

  addTextCommand "", "<C-r>", "select-prev"
  addTextCommand "", "<C-m>", "select-next"
  addTextCommand "", "U", "vim-redo", enterNormalModeBefore=false
  addTextCommand "insert", "<C-z>", "vim-undo", enterNormalModeBefore=false
  addTextCommand "insert", "<C-r>", "vim-redo", enterNormalModeBefore=false

  addTextCommand "", "<CA-UP>", "vim-add-cursor-above"
  addTextCommand "", "<CA-DOWN>", "vim-add-cursor-below"
  addTextCommand "", "<C-h>", "vim-add-cursor-above"
  addTextCommand "", "<C-f>", "vim-add-cursor-below"

  addTextCommandBlock "", "L":
    if editor.selections.len == 1:
      var selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b")
      selection.last.column -= 1
      editor.selection = selection
    else:
      let next = editor.getNextFindResult(editor.selection.last, includeAfter=false)
      editor.selections = editor.selections & next
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)
      editor.updateTargetColumn()

    editor.setMode("visual")

  addTextCommandBlock "visual", "L":
    if editor.selections.len == 1:
      let text = editor.getText(editor.selection, inclusiveEnd=true)
      let textEscaped = text.escapeRegex
      let currentSearchQuery = editor.getSearchQuery()
      # infof"'{text}' -> '{textEscaped}' -> '{currentSearchQuery}'"
      if textEscaped != currentSearchQuery and r"\b" & textEscaped & r"\b" != currentSearchQuery:
        if editor.setSearchQuery(text, escapeRegex=true):
          return

    let next = editor.getNextFindResult(editor.selection.last, includeAfter=false)
    editor.selections = editor.selections & next
    editor.scrollToCursor Last
    editor.updateTargetColumn()

  addTextCommandBlock "", "H":
    if editor.selections.len == 1:
      var selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b")
      selection.last.column -= 1
      editor.selection = selection
    else:
      let next = editor.getNextFindResult(editor.selection.last, includeAfter=false)
      editor.selections = editor.selections[0..^2] & next
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)
      editor.updateTargetColumn()

    editor.setMode("visual")

  addTextCommandBlockDesc "visual", "gl", "Add next node of same type to selection":
    if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
      editor.selections = editor.selections & selection
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)
      editor.updateTargetColumn()

  addTextCommandBlockDesc "visual", "gh", "Move last selection to next node of same type":
    if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
      editor.selections = editor.selections[0..^2] & selection
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)
      editor.updateTargetColumn()

  addTextCommandBlockDesc "visual", "gs", "Add next sibling node to selection":
    if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
      editor.selections = editor.selections & selection
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)
      editor.updateTargetColumn()

  addTextCommandBlockDesc "visual", "gd", "Move last selection to next sibling node":
    if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
      editor.selections = editor.selections[0..^2] & selection
      editor.scrollToCursor Last
      editor.setNextSnapBehaviour(MinDistanceOffscreen)
      editor.updateTargetColumn()

  addCommand "editor.text.visual", "S<CHAR>", "<CHAR>", source = currentSourceLocation(), action = proc(editor: TextDocumentEditor, c: string) =
    let (left, right) = case c
    of "(", ")": ("(", ")")
    of "{", "}": ("{", "}")
    of "[", "]": ("[", "]")
    of "<", ">": ("<", ">")
    else:
      (c, c)

    var insertSelections: Selections = @[]
    var insertTexts: seq[string] = @[]
    for s in editor.selections:
      let s = s.normalized
      insertSelections.add s.first.toSelection
      insertSelections.add editor.doMoveCursorColumn(s.last, 1).toSelection
      insertTexts.add left
      insertTexts.add right

    editor.addNextCheckpoint "insert"
    let newSelections = editor.insertMulti(insertSelections, insertTexts)
    if newSelections.len mod 2 != 0:
      return

    editor.selections = collect:
      for i in 0..<newSelections.len div 2:
        editor.includeSelectionEnd((newSelections[i * 2].first, newSelections[i * 2 + 1].last), false)

  addTextCommandBlock "visual", "gi":
    editor.selections = editor.selections.mapIt(block:
      if it.first.line == it.last.line and abs(it.first.column - it.last.column) < 2:
        it
      else:
        (editor.doMoveCursorColumn(it.first, 1), editor.doMoveCursorColumn(it.last, -1))
    )
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

  addTextCommand "visual", "gp", "select-parent-current-ts", false

  addTextCommandBlock "visual", "gxx":
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true)
  addTextCommandBlock "visual", "gxf":
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, suffix = "+1")
  addTextCommandBlock "visual", "gxh":
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, suffix = "-1")
  addTextCommandBlock "visual", "gxc":
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, addSelectionIndex = true)

  addTextCommandBlock "normal", "gxf":
    editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, false, suffix = "+1")
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)
  addTextCommandBlock "normal", "gxh":
    editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, false, suffix = "-1")
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)
  addTextCommandBlock "normal", "gxc":
    editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, false, addSelectionIndex = true)
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

  addTextCommandBlock "insert", "<C-g><*-x>f":
    editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, false, suffix = "+1")
    editor.selections = editor.selections.mapIt(it.last.toSelection)
  addTextCommandBlock "insert", "<C-g><*-x>h":
    editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, false, suffix = "-1")
    editor.selections = editor.selections.mapIt(it.last.toSelection)
  addTextCommandBlock "insert", "<C-g><*-x>c":
    editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, false, addSelectionIndex = true)
    editor.selections = editor.selections.mapIt(it.last.toSelection)

  addTextCommandBlock "visual", "o":
    editor.selections = editor.selections.mapIt((it.last, it.first))
    editor.scrollToCursor Last
    editor.updateTargetColumn()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addTextCommandBlock "visual-line", "o":
    editor.selections = editor.selections.mapIt((it.last, it.first))
    editor.scrollToCursor Last
    editor.updateTargetColumn()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addTextCommandBlock "", "<C-g>o":
    editor.selections = editor.selections.reversed()
    editor.scrollToCursor Last
    editor.updateTargetColumn()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addTextCommand "", "<C-k><C-u>", "print-undo-history"
  addTextCommand "", "<C-UP>", "scroll-lines", -1
  addTextCommand "", "<C-DOWN>", "scroll-lines", 1

  addTextCommand "insert", "<TAB>", "insert-indent"

  addTextCommandBlock "", "<C-l>":
    if editor.hasTabStops():
      editor.selectNextTabStop()
  addTextCommandBlock "", "<C-v>":
    if editor.hasTabStops():
      editor.selectPrevTabStop()

  addTextCommandBlock "", "gc":
    editor.addNextCheckpoint "insert"
    editor.toggleLineComment()

  addTextCommand "", "<C-k><C-f>", "format"
  addTextCommand "", "<C-k><C-s>", "stage-file"
  addTextCommand "", "<C-k><C-a>", "clear-diagnostics"
  addTextCommand "", "<C-k><C-u>", "print-undo-history"
  addTextCommand "", "<C-k><C-d>", "print-treesitter-tree-under-cursor"
  addTextCommand "", "<C-k><C-t>", "reload-treesitter"
  addCommand "editor", "<C-k><C-e>", "toggle-flag", "editor.text.highlight-treesitter-errors"
  addCommand "editor", "<C-k><C-k>", "toggle-flag", "ui.new"
  addCommand "editor", "<C-k><C-r>", "reload-plugin"
  addCommand "editor", "<C-k><S-r>", "reload-config"
  addCommand "editor", "<C-k><CS-r>", "reload-state"

  addTextCommand "", "M", "enter-choose-cursor-mode", "vim-handle-select-word"

  addTextCommandBlockDesc "", "gt", "Goto next diagnostic":
    let severity = getOption("text.jump-diagnostic-severity", 1)
    editor.selection = editor.getNextDiagnostic(editor.selection.last, severity).first.toSelection
    editor.scrollToCursor Last
    editor.updateTargetColumn()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
  addTextCommandBlockDesc "", "gn", "Goto prev diagnostic":
    let severity = getOption("text.jump-diagnostic-severity", 1)
    editor.selection = editor.getPrevDiagnostic(editor.selection.last, severity).first.toSelection
    editor.scrollToCursor Last
    editor.updateTargetColumn()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

  addTextCommandBlockDesc "", "gf", "Goto next change":
    editor.selection = editor.getNextChange(editor.selection.last).first.toSelection
    editor.scrollToCursor Last
    editor.centerCursor()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
  addTextCommandBlockDesc "", "gh", "Goto prev change":
    editor.selection = editor.getPrevChange(editor.selection.last).first.toSelection
    editor.scrollToCursor Last
    editor.centerCursor()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
  addTextCommand "", "<LEADER>gx", "close-diff"
  addTextCommand "", "<LEADER>gc", "update-diff"
  addTextCommand "normal", "<LEADER>gy", "stage-selected", false
  addTextCommand "visual", "<LEADER>gy", "stage-selected", true
  addTextCommand "visual-line", "<LEADER>gy", "stage-selected", true
  addTextCommand "normal", "<LEADER>gr", "revert-selected", false
  addTextCommand "visual", "<LEADER>gr", "revert-selected", true
  addTextCommand "visual-line", "<LEADER>gr", "revert-selected", true
  addTextCommand "", "<LEADER>gl", "fuzzy-search-lines"
  addTextCommand "", "<LEADER>gL", "fuzzy-search-lines", minScore = 0.4, sort = false
