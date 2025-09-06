import std/[strutils, macros, genasts, sequtils, sets, algorithm, jsonutils]
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
  unresolveMarks: Table[string, seq[Selection]]

var editorStates: Table[EditorId, EditorVimState]

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

proc vimHandleSelectWord(editor: TextDocumentEditor, cursor: Cursor) {.exposeActive(editorContext, "vim-handle-select-word").} =
  editor.setSelection(cursor.toSelection)

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
    editor.setMode "vim.normal"

  editor.undo(editor.vimState.currentUndoCheckpoint)
  if enterNormalModeBefore:
    if not editor.selections.allEmpty:
      editor.setMode "vim.visual"
    else:
      editor.setMode "vim.normal"

proc vimRedo(editor: TextDocumentEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext, "vim-redo").} =
  if enterNormalModeBefore:
    editor.setMode "vim.normal"

  editor.redo(editor.vimState.currentUndoCheckpoint)
  if enterNormalModeBefore:
    if not editor.selections.allEmpty:
      editor.setMode "vim.visual"
    else:
      editor.setMode "vim.normal"

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
  editor.updateTargetColumn()
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
  editor.setMode "vim.normal"

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
  editor.setMode "vim.insert"

proc vimYankSelection*(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-yank-selection").} =
  let selections = editor.copySelection(getVimDefaultRegister())
  editor.selections = selections
  editor.setMode "vim.normal"

proc vimYankSelectionClipboard*(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-yank-selection-clipboard").} =
  let selections = editor.copySelection()
  editor.selections = selections
  editor.setMode "vim.normal"

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
  editor.setMode "vim.normal"

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
  # todo: pass as parameter
  let which = if editor.mode == "vim.visual" or editor.mode == "vim.visual-line":
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
exposeActive editorContext, "vim-delete-right", vimDeleteRight

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

proc vimMoveCursorPage(editor: TextDocumentEditor, direction: float, count: int = 1, center: bool = false) {.exposeActive(editorContext, "vim-move-cursor-page").} =
  editor.moveCursorPage(direction * max(count, 1).float, includeAfter=editor.vimState.cursorIncludeEol)
  let nextScrollBehaviour = if center: CenterAlways.some else: ScrollBehaviour.none
  editor.scrollToCursor(Last, scrollBehaviour = nextScrollBehaviour)
  editor.setNextSnapBehaviour(Never)
  if editor.vimState.selectLines:
    editor.vimSelectLine()

proc vimMoveCursorVisualPage(editor: TextDocumentEditor, direction: float, count: int = 1, center: bool = false) {.exposeActive(editorContext, "vim-move-cursor-visual-page").} =
  if editor.vimState.selectLines:
    editor.moveCursorPage(direction * max(count, 1).float, includeAfter=editor.vimState.cursorIncludeEol)
  else:
    editor.moveCursorVisualPage(direction * max(count, 1).float, includeAfter=editor.vimState.cursorIncludeEol)
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

proc vimMoveToEndOfLine(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-end-of-line").} =
  # infof"vimMoveToEndOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveLast("vim-line")
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimMoveToEndOfVisualLine(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-end-of-visual-line").} =
  # infof"vimMoveToEndOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveLast("vim-visual-line")
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimMoveCursorLineFirstChar(editor: TextDocumentEditor, direction: int, count: int = 1) {.exposeActive(editorContext, "vim-move-cursor-line-first-char").} =
  editor.moveCursorLine(direction * max(count, 1))
  editor.moveFirst "line-no-indent"
  editor.updateTargetColumn()

proc vimMoveToStartOfLine(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-start-of-line").} =
  # infof"vimMoveToStartOfLine {count}"
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveFirst "line-no-indent"
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimPaste(editor: TextDocumentEditor, pasteRight: bool = false, inclusiveEnd: bool = false, register: string = "") {.exposeActive(editorContext, "vim-paste").} =
  # infof"vimPaste {register}, lines: {yankedLines}"
  let register = if register == "vim-default-register":
    getVimDefaultRegister()
  else:
    register

  editor.addNextCheckpoint "insert"

  let selectionsToDelete = editor.selections
  editor.selections = editor.delete(selectionsToDelete, inclusiveEnd=false)

  if yankedLines:
    # todo: pass bool as parameter
    if editor.mode != "vim.visual-line":
      editor.moveLast "line", Both
      editor.insertText "\n", autoIndent=false

  if pasteRight:
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)

  editor.setMode "vim.normal"
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

  editor.setMode "vim.normal"

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

proc vimEnter(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-enter").} =
  editor.addNextCheckpoint "insert"
  editor.insertText("\n")

proc vimNormalMode(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-normal-mode").} =
  ## Exit to normal mode and clear things
  if editor.mode == "vim.normal":
    # editor.selection = editor.selection.last.toSelection
    editor.setSelection(editor.selection.last.toSelection, addToHistory = true.some)
    editor.clearTabStops()
  editor.setMode("vim.normal")

proc vimVisualLineMode(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-visual-line-mode").} =
  editor.setMode "vim.visual-line"
  editor.vimSelectLine()

proc vimYankLine(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-yank-line").} =
  editor.vimState.selectLines = true
  editor.vimSelectLine()
  editor.vimYankSelection()
  editor.vimState.selectLines = false

proc vimDeleteLine(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-delete-line").} =
  editor.vimState.selectLines = true
  let oldSelections = editor.selections
  editor.vimSelectLine()
  editor.vimDeleteSelection(true, oldSelections=oldSelections.some)
  editor.vimState.selectLines = false

proc vimChangeLine(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-change-line").} =
  let oldSelections = editor.selections
  editor.vimSelectLine()
  editor.vimChangeSelection(true, oldSelections=oldSelections.some)

proc vimDeleteToLineEnd(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-delete-to-line-end").} =
  let oldSelections = editor.selections
  editor.selections = editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
  editor.vimDeleteSelection(true, oldSelections=oldSelections.some)
  editor.vimState.selectLines = false

proc vimChangeToLineEnd(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-change-to-line-end").} =
  let oldSelections = editor.selections
  editor.selections = editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
  editor.vimChangeSelection(true, oldSelections=oldSelections.some)
  editor.vimState.selectLines = false

proc vimYankToLineEnd(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-yank-to-line-end").} =
  editor.selections = editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
  editor.vimYankSelection()
  editor.vimState.selectLines = false

proc vimMoveFileStart(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-file-start").} =
  let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
  editor.selection = (count - 1, 0).toSelection(editor.selection, which)
  editor.moveFirst "line-no-indent"
  editor.scrollToCursor Last
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimMoveFileEnd(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-file-end").} =
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

proc vimMoveToMatchingOrFileOffset(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-matching-or-file-offset").} =
  if count == 0:
    editor.vimMoveToMatching()
  else:
    let line = clamp((count * editor.lineCount) div 100, 0, editor.lineCount - 1)
    let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.selection = (line, 0).toSelection(editor.selection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimScrollLineToTopAndMoveLineStart(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-top-and-move-line-start").} =
  if editor.getCommandCount != 0:
    editor.selection = (editor.getCommandCount, 0).toSelection
  editor.moveFirst "line-no-indent"
  editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

proc vimScrollLineToTop(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-top").} =
  if editor.getCommandCount != 0:
    editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
  editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

proc vimCenterLineAndMoveLineStart(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-center-line-and-move-line-start").} =
  if editor.getCommandCount != 0:
    editor.selection = (editor.getCommandCount, 0).toSelection
  editor.moveFirst "line-no-indent"
  editor.centerCursor()

proc vimCenterLine(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-center-line").} =
  if editor.getCommandCount != 0:
    editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
  editor.centerCursor()

proc vimScrollLineToBottomAndMoveLineStart(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-bottom-and-move-line-start").} =
  if editor.getCommandCount != 0:
    editor.selection = (editor.getCommandCount, 0).toSelection
  editor.moveFirst "line-no-indent"
  editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

proc vimScrollLineToBottom(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-bottom").} =
  if editor.getCommandCount != 0:
    editor.selection = (editor.getCommandCount, editor.selection.last.column).toSelection
  editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

proc vimInsertMode(editor: TextDocumentEditor, move: string = "") {.exposeActive(editorContext, "vim-insert-mode").} =
  case move
  of "right":
    editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)
  of "line-end":
    editor.moveLast "line", Both
  of "line-no-indent":
    editor.moveFirst "line-no-indent", Both
  of "first":
    editor.selections = editor.selections.mapIt(it.normalized.first.toSelection)
  of "line-start":
    editor.moveFirst "line", Both
  else:
    discard
  editor.setMode "vim.insert"
  editor.addNextCheckpoint "insert"

proc vimInsertLineBelow(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-insert-line-below").} =
  editor.moveLast "line", Both
  editor.addNextCheckpoint "insert"
  editor.insertText "\n"
  editor.setMode "vim.insert"

proc vimInsertLineAbove(editor: TextDocumentEditor, move: string = "") {.exposeActive(editorContext, "vim-insert-line-above").} =
  editor.moveFirst "line", Both
  editor.addNextCheckpoint "insert"
  editor.insertText "\n", autoIndent=false
  editor.vimMoveCursorLine -1
  editor.setMode "vim.insert"

proc vimSetSearchQueryFromWord(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-set-search-query-from-word").} =
  editor.selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b").first.toSelection

proc vimSetSearchQueryFromSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-set-search-query-from-selection").} =
  discard editor.setSearchQuery(editor.getText(editor.selection, inclusiveEnd=true), escapeRegex=true)
  editor.selection = editor.selection.first.toSelection
  editor.setMode("vim.normal")

proc vimNextSearchResult(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-next-search-result").} =
  editor.selection = editor.getNextFindResult(editor.selection.last).first.toSelection
  editor.scrollToCursor Last
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc vimPrevSearchResult(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-prev-search-result").} =
  editor.selection = editor.getPrevFindResult(editor.selection.last).first.toSelection
  editor.scrollToCursor Last
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc vimOpenSearchBar(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-open-search-bar").} =
  editor.openSearchBar()
  if getActiveEditor().isTextEditor(editor):
    editor.setMode("vim.insert")

proc vimExitCommandLine() {.expose("vim-exit-command-line").} =
  if getActiveEditor().isTextEditor(editor):
    if editor.mode == "vim.normal":
      exitCommandLine()
      return

    editor.setMode("vim.normal")

proc vimExitPopup() {.expose("vim-exit-popup").} =
  if getActiveEditor().isTextEditor(editor):
    if editor.mode == "vim.normal":
      if getActivePopup().isSelectorPopup(popup):
        popup.cancel()
      return

    editor.setMode("vim.normal")

proc vimSelectWordOrAddCursor(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-select-word-or-add-cursor").} =
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

  editor.setMode("vim.visual")

proc vimMoveLastSelectionToNextSearchResult(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-move-last-selection-to-next-search-result").} =
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

  editor.setMode("vim.visual")

proc vimSetSearchQueryOrAddCursor(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-set-search-query-or-add-cursor").} =
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

proc vimSaveState() {.expose("vim-save-state").} =
  try:
    var states = initTable[string, JsonNode]()

    for id, state in editorStates:
      if id.isTextEditor(editor):
        let filename = editor.getFileName()
        if filename == "":
          continue

        var marks = initTable[string, seq[Selection]]()
        for name, anchors in editor.vimState.marks:
          let selections = editor.resolveAnchors(anchors)
          marks[name] = selections
        for name, selections in editor.vimState.unresolveMarks:
          marks[name] = selections

        if marks.len > 0:
          states[filename] = %*{
            "marks": marks.toJson,
          }

    setSessionData("vim.states", states)
  except:
    infof"Failed to save vim editor states"

proc resolveMarks(editor: TextDocumentEditor) =
  let unresolveMarks = editor.vimState.unresolveMarks
  for name, selections in unresolveMarks:
    let anchors = editor.createAnchors(selections)
    if anchors.len > 0:
      editor.vimState.marks[name] = anchors
      editor.vimState.unresolveMarks.del(name)

proc vimAddMark(editor: TextDocumentEditor, name: string) {.exposeActive(editorContext, "vim-add-mark").} =
  editor.resolveMarks()
  editor.vimState.marks[name] = editor.createAnchors(editor.selections)

proc vimGotoMark(editor: TextDocumentEditor, name: string) {.exposeActive(editorContext, "vim-goto-mark").} =
  editor.resolveMarks()

  if name in editor.vimState.marks:
    let newSelections = editor.resolveAnchors(editor.vimState.marks[name])
    if newSelections.len == 0:
      return

    case editor.mode
    of "vim.visual", "vim.visual-line":
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

proc vimDeleteWordBack(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-delete-word-back").} =
  let selections = editor.applyMove(editor.selections, "vim-word", true, true, 1, which = SelectionCursor.Last.some)
  editor.selections = editor.delete(selections)
  editor.autoShowCompletions()

proc vimDeleteLineBack(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-delete-line-back").} =
  let selections = editor.applyMove(editor.selections, "vim-line", true, true, 1, which = SelectionCursor.Last.some)
  editor.selections = editor.delete(selections)
  editor.autoShowCompletions()

proc vimSurround(editor: TextDocumentEditor, text: string) {.exposeActive(editorContext, "vim-surround").} =
  let (left, right) = case text
  of "(", ")": ("(", ")")
  of "{", "}": ("{", "}")
  of "[", "]": ("[", "]")
  of "<", ">": ("<", ">")
  else:
    (text, text)

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

proc vimToggleLineComment(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-toggle-line-comment").} =
  editor.addNextCheckpoint "insert"
  editor.toggleLineComment()

proc vimStartMacro(editor: TextDocumentEditor, name: string) {.exposeActive(editorContext, "vim-start-macro").} =
  if isReplayingCommands() or isRecordingCommands(getCurrentMacroRegister()):
    return
  setOption("editor.current-macro-register", name)
  setRegisterText("", name)
  startRecordingCommands(name)

proc vimPlayMacro(editor: TextDocumentEditor, name: string) {.exposeActive(editorContext, "vim-play-macro").} =
  let register = if name == "@":
    getCurrentMacroRegister()
  else:
    name

  replayCommands(register)

proc vimStopMacro(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-stop-macro").} =
  if isReplayingCommands() or not isRecordingCommands(getCurrentMacroRegister()):
    return
  stopRecordingCommands(getCurrentMacroRegister())

proc vimInvertSelections(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-invert-selections").} =
  editor.selections = editor.selections.mapIt((it.last, it.first))
  editor.scrollToCursor Last
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimInvertLineSelections(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-invert-line-selections").} =
  editor.selections = editor.selections.mapIt((it.last, it.first))
  editor.scrollToCursor Last
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimReverseSelections(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-reverse-selections").} =
  editor.selections = editor.selections.reversed()
  editor.scrollToCursor Last
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimJoinLines(editor: TextDocumentEditor, reduceSpace: bool) {.exposeActive(editorContext, "vim-join-lines").} =
  editor.addNextCheckpoint "insert"
  if reduceSpace:
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
  else:
    let selectionsToDelete = editor.selections.mapIt(block:
      let lineLen = editor.lineLength(it.last.line)
      ((it.last.line, lineLen), (it.last.line + 1, 0))
    )
    editor.selections = editor.delete(selectionsToDelete, inclusiveEnd=false).mapIt(it.first.toSelection)

proc vimMoveToColumn(editor: TextDocumentEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-column").} =
  editor.selections = editor.selections.mapIt((it.last.line, count).toSelection)
  editor.scrollToCursor Last
  editor.updateTargetColumn()

proc vimAddNextSameNodeToSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-add-next-same-node-to-selection").} =
  if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
    editor.selections = editor.selections & selection
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

proc vimMoveSelectionToNextSameNode(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-move-selection-to-next-same-node").} =
  if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
    editor.selections = editor.selections[0..^2] & selection
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

proc vimAddNextSiblingToSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-add-next-sibling-to-selection").} =
  if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
    editor.selections = editor.selections & selection
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

proc vimMoveSelectionToNextSibling(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-move-selection-to-next-sibling").} =
  if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
    editor.selections = editor.selections[0..^2] & selection
    editor.scrollToCursor Last
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

proc vimShrinkSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-shrink-selection").} =
  editor.selections = editor.selections.mapIt(block:
    if it.first.line == it.last.line and abs(it.first.column - it.last.column) < 2:
      it
    else:
      (editor.doMoveCursorColumn(it.first, 1), editor.doMoveCursorColumn(it.last, -1))
  )
  editor.scrollToCursor Last
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc vimEvaluateSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-evaluate-selection").} =
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, true)

proc vimIncrementSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-increment-selection").} =
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, true, suffix = "+1")

proc vimDecrementSelection(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-decrement-selection").} =
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, true, suffix = "-1")

proc vimIncrementSelectionByIndex(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-increment-selection-by-index").} =
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, true, addSelectionIndex = true)

proc vimIncrement(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-increment").} =
  editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, false, suffix = "+1")
  editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

proc vimDecrement(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-decrement").} =
  editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, false, suffix = "-1")
  editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

proc vimIncrementByIndex(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-increment-by-index").} =
  editor.selections = editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
  editor.addNextCheckpoint("insert")
  editor.evaluateExpressions(editor.selections, false, addSelectionIndex = true)
  editor.selections = editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

proc vimGotoNextDiagnostic(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-goto-next-diagnostic").} =
  let severity = getOption("text.jump-diagnostic-severity", 1)
  editor.selection = editor.getNextDiagnostic(editor.selection.last, severity).first.toSelection
  editor.scrollToCursor Last
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimGotoPrevDiagnostic(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-goto-prev-diagnostic").} =
  let severity = getOption("text.jump-diagnostic-severity", 1)
  editor.selection = editor.getPrevDiagnostic(editor.selection.last, severity).first.toSelection
  editor.scrollToCursor Last
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimGotoNextChange(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-goto-next-change").} =
  editor.selection = editor.getNextChange(editor.selection.last).first.toSelection
  editor.scrollToCursor Last
  editor.centerCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimGotoPrevChange(editor: TextDocumentEditor) {.exposeActive(editorContext, "vim-goto-prev-change").} =
  editor.selection = editor.getPrevChange(editor.selection.last).first.toSelection
  editor.scrollToCursor Last
  editor.centerCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc vimReplaceInputHandler(editor: TextDocumentEditor, input: string) {.exposeActive(editorContext, "vim-replace-input-handler").} =
  editor.vimReplace(input)

proc vimInsertRegisterInputHandler(editor: TextDocumentEditor, input: string) {.exposeActive(editorContext, "vim-insert-register-input-handler").} =
  editor.vimPaste register=input, inclusiveEnd=true
  editor.setMode "vim.insert"

proc vimModeChangedHandler(editor: TextDocumentEditor, oldModes: seq[string], newModes: seq[string]) {.exposeActive(editorContext, "vim-mode-changed-handler").} =
  # echo &"vimModeChangedHandler {editor.getFileName()}, {oldModes} -> {newModes}"

  let oldMode = if oldModes.len > 0:
    oldModes[0]
  else:
    ""

  if newModes.len == 0:
    return

  let newMode = newModes[0]

  if not editor.getCurrentEventHandlers().contains("vim"):
    return

  if newMode == "":
    editor.setMode "vim.normal"
    return

  if not newMode.startsWith("vim"):
    return

  let recordModes = [
    "vim.visual",
    "vim.visual-line",
    "vim.insert",
  ].toHashSet

  # infof"vim: handle mode change {oldMode} -> {newMode}"
  if newMode == "vim.normal":
    if not isReplayingCommands() and isRecordingCommands(".-temp"):
      stopRecordingCommands(".-temp")

      if editor.getRevision > editor.vimState.revisionBeforeImplicitInsertMacro:
        infof"Record implicit macro because document was modified"
        let text = getRegisterText(".-temp")
        setRegisterText(text, ".")
      # else:
      #   infof"Don't record implicit macro because nothing was modified"
  else:
    if oldMode == "vim.normal" and newMode in recordModes:
      editor.startRecordingCurrentCommandInPeriodMacro()

    editor.clearCurrentCommandHistory(retainLast=true)

  editor.vimState.selectLines = newMode == "vim.visual-line"
  editor.vimState.cursorIncludeEol = newMode == "vim.insert"
  editor.vimState.currentUndoCheckpoint = if newMode == "vim.insert": "word" else: "insert"

  case newMode
  of "vim.normal":
    editor.setConfig "text.inclusive-selection", false
    editor.selections = editor.selections.mapIt(editor.vimClamp(it.last).toSelection)
    editor.saveCurrentCommandHistory()
    editor.hideCompletions()

  of "vim.insert":
    editor.setConfig "text.inclusive-selection", false

  of "vim.visual":
    editor.setConfig "text.inclusive-selection", true

  of "vim.visual-line":
    editor.setConfig "text.inclusive-selection", false

  else:
    editor.setConfig "text.inclusive-selection", false

proc loadVimKeybindings*() {.expose("load-vim-keybindings").} =
  let afterRestoreSessionHandle = addCallback proc(args: JsonNode): JsonNode =
    let states = getSessionData[Table[string, JsonNode]]("vim.states")
    for id in getAllEditors():
      if id.isTextEditor(editor):
        try:
          let filename = editor.getFileName()
          if states.hasKey(filename):
            let editorState = states[filename]
            if editorState.hasKey("marks"):
              let marks = editorState["marks"].jsonTo(Table[string, seq[Selection]])
              for name, selections in marks:
                editor.vimState.unresolveMarks[name] = selections
        except:
          infof"Failed to restore marks for {editor}"
  scriptSetCallback("after-restore-session", afterRestoreSessionHandle)

  let beforeSaveAppStateHandle = addCallback proc(args: JsonNode): JsonNode =
    vimSaveState()
  scriptSetCallback("before-save-app-state", beforeSaveAppStateHandle)
