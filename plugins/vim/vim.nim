# import std/[strutils, macros, genasts, sequtils, sets, algorithm, jsonutils]
import std/[strformat, json, jsonutils, strutils, tables, macros, genasts, streams, sequtils, sets, os, terminal, colors]
import results
import util, custom_unicode, myjsonutils, id, regex, wrap, sugar
# import input_api
import api
from "../../src/scripting_api.nim" as sca import nil
import "../../src/input_api.nim"

type LogLevel = enum lvlInfo, lvlNotice, lvlDebug, lvlWarn, lvlError

proc log(level: LogLevel, str: string) =
  let color = case level
  of lvlDebug: rgb(100, 100, 200)
  of lvlInfo: rgb(200, 200, 200)
  of lvlNotice: rgb(200, 255, 255)
  of lvlWarn: rgb(200, 200, 100)
  of lvlError: rgb(255, 150, 150)
  # of lvlFatal: rgb(255, 0, 0)
  else: rgb(255, 255, 255)
  try:
    {.gcsafe.}:
      stdout.write(ansiForegroundColorCode(color))
      stdout.write("[vim] ")
      stdout.write(str)
      stdout.write("\r\n")
  except IOError:
    discard

template debugf*(x: static string) =
  log lvlDebug, fmt(x)

var yankedLines: bool = false ## Whether the last thing we yanked was in a line mode

type EditorVimState = object
  ## Contains state which can vary per editor
  selectLines: bool = false ## Whether entire lines should be selected (e.g. in visual-line mode/when using dd)
  deleteInclusiveEnd: bool = true ## Whether the next time we delete some the selection end should be inclusive
  cursorIncludeEol: bool = false ## Whether the cursor can be after the last character in a line (e.g. in insert mode)
  currentUndoCheckpoint: string = "insert" ## Which checkpoint to undo to (depends on mode)
  revisionBeforeImplicitInsertMacro: int
  marks: Table[string, seq[(sca.Anchor, sca.Anchor)]]
  unresolveMarks: Table[string, seq[sca.Selection]]

var editorStates: Table[sca.EditorId, EditorVimState]

const editorContext = "editor.text"


type IdentifierCase = enum Camel, Pascal, Kebab, Snake, ScreamingSnake

proc splitCase(s: string): tuple[cas: IdentifierCase, parts: seq[string]] =
  if s == "":
    return (IdentifierCase.Camel, @[])

  if s.find('_') != -1:
    result.cas = IdentifierCase.Snake
    result.parts = s.split('_').mapIt(custom_unicode.toLower(it))
    for r in s.runes:
      if r != '_'.Rune and not r.isLower:
        result.cas = IdentifierCase.ScreamingSnake
        break

  elif s.find('-') != -1:
    result.cas = IdentifierCase.Kebab
    result.parts = s.split('-').mapIt(custom_unicode.toLower(it))
  else:
    if s[0].isUpperAscii:
      result.cas = IdentifierCase.Pascal
    else:
      result.cas = IdentifierCase.Camel

    result.parts.add ""
    for r in s.runes:
      if not r.isLower and result.parts.last.len > 0:
        result.parts.add ""
      result.parts.last.add(custom_unicode.toLower(r))

proc joinCase(parts: seq[string], cas: IdentifierCase): string =
  assert parts.len > 0
  case cas
  of IdentifierCase.Camel:
    parts[0] & parts[1..^1].mapIt(it.capitalize).join("")
  of IdentifierCase.Pascal:
    parts.mapIt(it.capitalize).join("")
  of IdentifierCase.Kebab:
    parts.join("-")
  of IdentifierCase.Snake:
    parts.join("_")
  of IdentifierCase.ScreamingSnake:
    parts.mapIt(custom_unicode.toUpper(it)).join("_")

proc cycleCase(s: string): string =
  if s.len == 0:
    return s
  let (cas, parts) = s.splitCase()
  let nextCase = if cas == IdentifierCase.high:
    IdentifierCase.low
  else:
    cas.succ
  return parts.joinCase(nextCase)

proc exposeImpl*(context: NimNode, name: string, fun: NimNode, active: bool): NimNode =
  # defer:
  #   echo result.repr

  let def = if fun.kind == nnkProcDef: fun else: fun.getImpl
  if def.kind != nnkProcDef:
    error("expose can only be used on proc definitions", fun)

  let signature = def.copy
  signature[6] = newEmptyNode()

  let signatureUntyped = parseExpr(signature.repr)
  let jsonWrapperName = (def.name.repr & "Json").ident
  let jsonWrapper = createJsonWrapper(signatureUntyped, jsonWrapperName)

  let documentation = def.getDocumentation()
  let documentationStr = documentation.map((it) => it.strVal).get("").newLit

  let returnType = if def[3][0].kind == nnkEmpty: "" else: def[3][0].repr
  var params: seq[(string, string)] = @[]
  for param in def[3][1..^1]:
    params.add (param[0].repr, param[1].repr)

  if def == fun:
    return genAst(name, def, jsonWrapper, jsonWrapperName, documentationStr, inParams = params, inReturnType = returnType, inActive = active, inContext = context):
      def
      jsonWrapper
      defineCommand(ws(name),
        active = inActive,
        docs = ws(documentationStr),
        params = wl[(WitString, WitString)](nil, 0),
        returnType = ws(inReturnType),
        context = ws(inContext),
        data = 0):
        proc(data: uint32, argsString: WitString): WitString {.cdecl.} =
          var args = newJArray()
          try:
            for a in newStringStream($argsString).parseJsonFragments():
              args.add a
            let res = jsonWrapperName(args)
            return stackWitString($res)
          except CatchableError as e:
            log lvlError, "Failed to run command '" & name & "': " & e.msg

          return ws""

  else:
    return genAst(name, jsonWrapper, jsonWrapperName, documentationStr, inParams = params, inReturnType = returnType, inAactive = active, inContext = context):
      jsonWrapper
      defineCommand(stackWitString(name),
        active = inActive,
        docs = ws(documentationStr),
        params = wl[(WitString, WitString)](nil, 0),
        returnType = ws(inReturnType),
        context = ws(inContext),
        data = 0):
        proc(data: uint32, args: WitString): WitString {.cdecl.} =
          var args = newJArray()
          try:
            for a in newStringStream($argsString).parseJsonFragments():
              args.add a
            let res = jsonWrapperName(args)
            return stackWitString($res)
          except CatchableError as e:
            log lvlError, "Failed to run command '" & name & "': " & e.msg

          return ws""

macro expose*(name: string, fun: typed): untyped =
  return exposeImpl(newLit"script", name.repr, fun, active=false)

macro expose*(context, string: string, fun: typed): untyped =
  let name = fun.name.repr.splitCase.parts.joinCase(Kebab)
  return exposeImpl(context, name, fun, active=false)

macro exposeActive*(context: string, fun: typed): untyped =
  let name = fun.name.repr.splitCase.parts.joinCase(Kebab)
  return exposeImpl(context, name, fun, active=true)

macro callJson*(fun: typed, args: JsonNode): JsonNode =
  ## Calls a function with a json object as argument, converting the json object to nim types
  let jsonWrapperName = genSym(nskProc, "jsonWrapper")
  let jsonWrapper = createJsonWrapper(fun, fun.getType, jsonWrapperName)
  jsonWrapper.addPragma("closure".ident)
  return genAst(jsonWrapper, jsonWrapperName, args):
    block:
      jsonWrapper
      jsonWrapperName(args)

proc vimState(editor: TextEditor): var EditorVimState =
  if not editorStates.contains(editor.id):
    editorStates[editor.id] = EditorVimState()
  return editorStates[editor.id]

proc getContextWithMode(self: TextEditor, context: string): string =
  ## Appends the current mode to context
  return context & "." & $self.mode

proc shouldRecortImplicitPeriodMacro(editor: TextEditor): bool =
  case $editor.getUsage()
  of "command-line", "search-bar":
    return false
  else:
    return true

proc recordCurrentCommandInPeriodMacro(editor: TextEditor) =
  if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
    setRegisterText(ws"", ws".")
    editor.recordCurrentCommand(@@[ws"."])

proc startRecordingCurrentCommandInPeriodMacro(editor: TextEditor) =
  if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
    startRecordingCommands(ws".-temp")
    setRegisterText(ws"", ws".-temp")
    editor.recordCurrentCommand(@@[ws".-temp"])
    editor.vimState.revisionBeforeImplicitInsertMacro = editor.getRevision

type VimTextObjectRange* = enum Inner, Outer, CurrentToEnd

proc getVimLineMargin*(): float = getSetting("editor.text.vim.line-margin", 5.float)
proc getVimClipboard*(): string = getSetting("editor.text.vim.clipboard", "")
proc getVimDefaultRegister*(): string =
  case getVimClipboard():
  of "unnamed": return "*"
  of "unnamedplus": return "+"
  else: return "\""

proc getCurrentMacroRegister*(): string = getSetting("editor.current-macro-register", "")

proc getEnclosing(line: string, column: int, predicate: proc(c: char): bool): (int, int) =
  var startColumn = column
  var endColumn = column
  while endColumn < line.high and predicate(line[endColumn + 1]):
    inc endColumn
  while startColumn > 0 and predicate(line[startColumn - 1]):
    dec startColumn
  return (startColumn, endColumn)

proc handleSelectWord(editor: TextEditor, cursor: Cursor) {.exposeActive(editorContext).} =
  editor.setSelection(cursor.toSelection)

proc selectLine(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setSelections stackWitList(editor.selections.mapIt (if it.isBackwards:
      Selection(first: Cursor(line: it.first.line, column: editor.lineLength(it.first.line)), last: Cursor(line: it.last.line, column: 0))
    else:
      Selection(first: Cursor(line: it.first.line, column: 0), last: Cursor(line: it.last.line, column: editor.lineLength(it.last.line)))
      ))

proc selectLast(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    discard editor.command(ws(action), ws(arg))
  editor.setSelections editor.selections.mapIt(it.last.toSelection)
  editor.vimState.deleteInclusiveEnd = true

proc select(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    discard editor.command(ws(action), ws(arg))

proc undo(editor: TextEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext).} =
  if enterNormalModeBefore:
    editor.setMode "vim-new.normal"

  editor.undo(editor.vimState.currentUndoCheckpoint.ws)
  if enterNormalModeBefore:
    if not editor.selections.toOpenArray().allEmpty:
      editor.setMode "vim-new.visual"
    else:
      editor.setMode "vim-new.normal"

proc redo(editor: TextEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext).} =
  if enterNormalModeBefore:
    editor.setMode "vim-new.normal"

  editor.redo(editor.vimState.currentUndoCheckpoint.ws)
  if enterNormalModeBefore:
    if not editor.selections.toOpenArray().allEmpty:
      editor.setMode "vim-new.visual"
    else:
      editor.setMode "vim-new.normal"

proc copySelection(editor: TextEditor, register: string = ""): seq[Selection] =
  ## Copies the selected text
  ## If line selection mode is enabled then it also extends the selection so that deleting it will also delete the line itself
  yankedLines = editor.vimState.selectLines
  editor.copy(register.ws, inclusiveEnd=true)
  let selections = editor.selections
  if editor.vimState.selectLines:
    editor.setSelections editor.selections.mapIt (
      if it.isBackwards:
        if it.last.line > 0:
          (it.first, editor.applyMove(it.last, "column", -1).last).toSelection
        elif it.first.line + 1 < editor.lineCount:
          (editor.applyMove(it.first, "column", 1).last, it.last).toSelection
        else:
          it
      else:
        if it.first.line > 0:
          (editor.applyMove(it.first, "column", -1).last, it.last).toSelection
        elif it.last.line + 1 < editor.lineCount:
          (it.first, editor.applyMove(it.last, "column", 1).last).toSelection
        else:
          it
    )

  return selections.mapIt(it.normalized.first.toSelection)

proc deleteSelection(editor: TextEditor, forceInclusiveEnd: bool, oldSelections: Option[seq[Selection]] = seq[Selection].none) {.exposeActive(editorContext).} =
  let newSelections = editor.copySelection(getVimDefaultRegister())
  let selectionsToDelete = editor.selections
  if oldSelections.isSome:
    editor.setSelections oldSelections.get
  editor.addNextCheckpoint(ws"insert")
  let inclusiveEnd = (not editor.vimState.selectLines) and (editor.vimState.deleteInclusiveEnd or forceInclusiveEnd)
  editor.setSelections editor.edit(selectionsToDelete, @@[ws""], inclusive = inclusiveEnd)
  editor.scrollToCursor()
  editor.updateTargetColumn()
  editor.vimState.deleteInclusiveEnd = true
  editor.setMode "vim-new.normal"

proc changeSelection*(editor: TextEditor, forceInclusiveEnd: bool, oldSelections: Option[seq[Selection]] = seq[Selection].none) {.exposeActive(editorContext).} =
  let newSelections = editor.copySelection(getVimDefaultRegister())
  let selectionsToDelete = editor.selections
  if oldSelections.isSome:
    editor.setSelections oldSelections.get
  editor.addNextCheckpoint(ws"insert")
  let inclusive = editor.vimState.deleteInclusiveEnd or forceInclusiveEnd
  editor.setSelections editor.edit(selectionsToDelete, @@[ws""], inclusive = inclusive)
  editor.scrollToCursor()
  editor.updateTargetColumn()
  editor.vimState.deleteInclusiveEnd = true
  editor.setMode "vim-new.insert"

proc yankSelection*(editor: TextEditor) {.exposeActive(editorContext).} =
  let selections = editor.copySelection(getVimDefaultRegister())
  editor.setSelections selections
  editor.setMode "vim-new.normal"

proc yankSelectionClipboard*(editor: TextEditor) {.exposeActive(editorContext).} =
  let selections = editor.copySelection()
  editor.setSelections selections
  editor.setMode "vim-new.normal"

# proc vimReplace(editor: TextEditor, input: string) {.exposeActive(editorContext, "vim-replace").} =
#   let texts = editor.selections.mapIt(block:
#     let selection = it
#     let text = editor.getText(selection, inclusiveEnd=true)
#     var newText = newStringOfCap(text.runeLen.int * input.runeLen.int)
#     var lastIndex = 0
#     var index = text.find('\n')
#     if index == -1:
#       newText.add input.repeat(text.runeLen.int)
#     else:
#       while index != -1:
#         let lineLen = text.toOpenArray(lastIndex, index).runeLen.int - 1
#         newText.add input.repeat(lineLen)
#         newText.add "\n"
#         lastIndex = index + 1
#         index = text.find('\n', index + 1)

#       let lineLen = text.toOpenArray(lastIndex, text.high).runeLen.int
#       newText.add input.repeat(lineLen)

#     newText
#   )

#   # infof"replace {editor.selections} with '{input}' -> {texts}"

#   editor.addNextCheckpoint "insert"
#   editor.setSelections editor.edit(editor.selections, texts, inclusiveEnd=true).mapIt(it.first.toSelection)
#   editor.setMode "vim-new.normal"

# proc vimSelectMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-select-move").} =
#   # infof"vimSelectMove '{move}' {count}"
#   let (action, arg) = move.parseAction
#   for i in 0..<max(count, 1):
#     editor.runAction(action, arg)
#   editor.updateTargetColumn()

# proc vimDeleteMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-delete-move").} =
#   # infof"vimDeleteMove '{move}' {count}"
#   let oldSelections = editor.selections
#   let (action, arg) = move.parseAction
#   for i in 0..<max(count, 1):
#     editor.runAction(action, arg)
#   editor.vimDeleteSelection(false, oldSelections=oldSelections.some)

#   editor.recordCurrentCommandInPeriodMacro()

# proc vimChangeMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-change-move").} =
#   # infof"vimChangeMove '{move}' {count}"
#   let oldSelections = editor.selections
#   let (action, arg) = move.parseAction
#   for i in 0..<max(count, 1):
#     editor.runAction(action, arg)
#   editor.vimChangeSelection(false, oldSelections=oldSelections.some)

# proc vimYankMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext, "vim-yank-move").} =
#   # infof"vimYankMove '{move}' {count}"
#   let (action, arg) = move.parseAction
#   for i in 0..<max(count, 1):
#     editor.runAction(action, arg)
#   editor.vimYankSelection()

# proc vimMoveTo*(editor: TextEditor, target: string, before: bool, count: int = 1) {.exposeActive(editorContext, "vim-move-to").} =
#   # infof"vimMoveTo '{target}' {before}"

#   proc parseTarget(target: string): string =
#     if target.len == 1:
#       return target

#     if target.parseFirstInput().getSome(res):
#       if res.inputCode.a == INPUT_SPACE:
#         return " "
#       elif res.inputCode.a <= int32.high:
#         return $Rune(res.inputCode.a)
#     else:
#       infof" -> failed to parse key: {target}"

#   let key = parseTarget(target)

#   for _ in 0..<max(1, count):
#     editor.moveCursorTo(key)
#   if before:
#     editor.moveCursorColumn(-1)
#   editor.updateTargetColumn()

proc vimClamp*(editor: TextEditor, cursor: Cursor): Cursor =
  var lineLen = editor.lineLength(cursor.line)
  if not editor.vimState.cursorIncludeEol and lineLen > 0: lineLen.dec
  result = (cursor.line, min(cursor.column, lineLen))

# proc vimMotionLine*(editor: TextEditor, cursor: Cursor, count: int): Selection =
#   var lineLen = editor.lineLength(cursor.line)
#   if not editor.vimState.cursorIncludeEol and lineLen > 0: lineLen.dec
#   result = ((cursor.line, 0), (cursor.line, lineLen))

# proc vimMotionVisualLine*(editor: TextEditor, cursor: Cursor, count: int): Selection =
#   var lineLen = editor.lineLength(cursor.line)
#   result = editor.getSelectionForMove(cursor, "visual-line", count)
#   if not editor.vimState.cursorIncludeEol and result.last.column > result.first.column:
#     result.last.column.dec
#   elif result.last.column < lineLen: # This is the case if we're not in the last visual sub line
#     result.last.column.dec

# proc vimMotionParagraphInner*(editor: TextEditor, cursor: Cursor, count: int): Selection =
#   let isEmpty = editor.lineLength(cursor.line) == 0

#   result = ((cursor.line, 0), cursor)
#   while result.first.line - 1 >= 0 and (editor.lineLength(result.first.line - 1) == 0) == isEmpty:
#     dec result.first.line
#   while result.last.line + 1 < editor.lineCount and (editor.lineLength(result.last.line + 1) == 0) == isEmpty:
#     inc result.last.line

#   result.last.column = editor.lineLength(result.last.line)

# proc vimMotionParagraphOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection =
#   result = editor.vimMotionParagraphInner(cursor, count)
#   if result.last.line + 1 < editor.lineCount:
#     result = result or editor.vimMotionParagraphInner((result.last.line + 1, 0), 1)

proc vimMotionWordOuter(data: uint32, text: sink Rope, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.cdecl, raises: [].} =
# proc vimMotionWordOuter*(rope: sink Rope, cursor: Cursor, count: int): Selection =
  result = vimMotionWord(editor, cursor, count)
  if result.last.column < editor.lineLength(result.last.line) and editor.getChar(result.last) in Whitespace:
    result.last = editor.vimMotionWord(result.last, 1).last

# proc vimMotionWordBigOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection =
#   result = vimMotionWordBig(editor, cursor, count)
#   if result.last.column < editor.lineLength(result.last.line) and editor.getChar(result.last) in Whitespace:
#     result.last = editor.vimMotionWordBig(result.last, 1).last

# proc charAt*(editor: TextEditor, cursor: Cursor): char =
#   let res = editor.getText(cursor.toSelection, inclusiveEnd=true)
#   if res.len > 0:
#     return res[0]
#   else:
#     return '\0'

# proc vimMotionSurround*(editor: TextEditor, cursor: Cursor, count: int, c0: char, c1: char, inside: bool): Selection =
#   result = cursor.toSelection
#   # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}"
#   while true:
#     let lastChar = editor.charAt(result.last)
#     let (startDepth, endDepth) = if lastChar == c0:
#       (1, 0)
#     elif lastChar == c1:
#       (0, 1)
#     else:
#       (1, 1)

#     # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}: try find around: {startDepth}, {endDepth}"
#     if editor.findSurroundStart(result.first, count, c0, c1, startDepth).getSome(opening) and editor.findSurroundEnd(result.last, count, c0, c1, endDepth).getSome(closing):
#       result = (opening, closing)
#       # infof"vimMotionSurround: found inside {result}"
#       if inside:
#         result.first = editor.doMoveCursorColumn(result.first, 1)
#         result.last = editor.doMoveCursorColumn(result.last, -1)
#       return

#     # infof"vimMotionSurround: {cursor}, {count}, {c0}, {c1}, {inside}: try find ahead: {startDepth}, {endDepth}"
#     if editor.findSurroundEnd(result.first, count, c0, c1, -1).getSome(opening) and editor.findSurroundEnd(opening, count, c0, c1, 0).getSome(closing):
#       result = (opening, closing)
#       # infof"vimMotionSurround: found ahead {result}"
#       if inside:
#         result.first = editor.doMoveCursorColumn(result.first, 1)
#         result.last = editor.doMoveCursorColumn(result.last, -1)
#       return
#     else:
#       # infof"vimMotionSurround: found nothing {result}"
#       return

# proc vimMoveToMatching(editor: TextEditor) {.exposeActive(editorContext, "vim-move-to-matching").} =
#   # todo: pass as parameter
#   let which = if editor.mode == "vim-new.visual" or editor.mode == "vim-new.visual-line":
#     SelectionCursor.Last
#   else:
#     SelectionCursor.Both

#   editor.setSelections editor.selections.mapIt(block:
#     let c = editor.charAt(it.last)
#     let (open, close, last) = case c
#       of '(': ('(', ')', true)
#       of '{': ('{', '}', true)
#       of '[': ('[', ']', true)
#       of '<': ('<', '>', true)
#       of ')': ('(', ')', false)
#       of '}': ('{', '}', false)
#       of ']': ('[', ']', false)
#       of '>': ('<', '>', false)
#       of '"': ('"', '"', true)
#       of '\'': ('\'', '\'', true)
#       else: return

#     let selection = editor.vimMotionSurround(it.last, 0, open, close, false)

#     if last:
#       selection.last.toSelection(it, which)
#     else:
#       selection.first.toSelection(it, which)
#   )

#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimMotionSurroundBracesInner*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '{', '}', true)
# proc vimMotionSurroundBracesOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '{', '}', false)
# proc vimMotionSurroundParensInner*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '(', ')', true)
# proc vimMotionSurroundParensOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '(', ')', false)
# proc vimMotionSurroundBracketsInner*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '[', ']', true)
# proc vimMotionSurroundBracketsOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '[', ']', false)
# proc vimMotionSurroundAngleInner*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '<', '>', true)
# proc vimMotionSurroundAngleOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '<', '>', false)
# proc vimMotionSurroundDoubleQuotesInner*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '"', '"', true)
# proc vimMotionSurroundDoubleQuotesOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '"', '"', false)
# proc vimMotionSurroundSingleQuotesInner*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '\'', '\'', true)
# proc vimMotionSurroundSingleQuotesOuter*(editor: TextEditor, cursor: Cursor, count: int): Selection = vimMotionSurround(editor, cursor, count, '\'', '\'', false)

# # todo
# addCustomTextMove "vim-line", vimMotionLine
# addCustomTextMove "vim-visual-line", vimMotionVisualLine
addCustomTextMove "vim-word-outer", vimMotionWordOuter
# addCustomTextMove "vim-WORD-outer", vimMotionWordBigOuter
# addCustomTextMove "vim-paragraph-inner", vimMotionParagraphInner
# addCustomTextMove "vim-paragraph-outer", vimMotionParagraphOuter
# addCustomTextMove "vim-surround-{-inner", vimMotionSurroundBracesInner
# addCustomTextMove "vim-surround-{-outer", vimMotionSurroundBracesOuter
# addCustomTextMove "vim-surround-(-inner", vimMotionSurroundParensInner
# addCustomTextMove "vim-surround-(-outer", vimMotionSurroundParensOuter
# addCustomTextMove "vim-surround-[-inner", vimMotionSurroundBracketsInner
# addCustomTextMove "vim-surround-[-outer", vimMotionSurroundBracketsOuter
# addCustomTextMove "vim-surround-angle-inner", vimMotionSurroundAngleInner
# addCustomTextMove "vim-surround-angle-outer", vimMotionSurroundAngleOuter
# addCustomTextMove "vim-surround-\"-inner", vimMotionSurroundDoubleQuotesInner
# addCustomTextMove "vim-surround-\"-outer", vimMotionSurroundDoubleQuotesOuter
# addCustomTextMove "vim-surround-'-inner", vimMotionSurroundSingleQuotesInner
# addCustomTextMove "vim-surround-'-outer", vimMotionSurroundSingleQuotesOuter

# iterator iterateTextObjects*(editor: TextEditor, cursor: Cursor, move: string, backwards: bool = false): Selection =
#   var selection = editor.getSelectionForMove(cursor, move, 0)
#   # infof"iterateTextObjects({cursor}, {move}, {backwards}), selection: {selection}"
#   yield selection
#   while true:
#     let lastSelection = selection
#     if not backwards and selection.last.column == editor.lineLength(selection.last.line):
#       if selection.last.line == editor.lineCount - 1:
#         break
#       selection = (selection.last.line + 1, 0).toSelection
#     elif backwards and selection.first.column == 0:
#       if selection.first.line == 0:
#         break
#       selection = (selection.first.line - 1, editor.lineLength(selection.first.line - 1)).toSelection
#       if selection.first.column == 0:
#         yield selection
#         continue

#     let nextCursor = if backwards: (selection.first.line, selection.first.column - 1) else: (selection.last.line, selection.last.column + 1)
#     let newSelection = editor.getSelectionForMove(nextCursor, move, 0)
#     # infof"iterateTextObjects({cursor}, {move}, {backwards}) nextCursor: {nextCursor}, newSelection: {newSelection}"
#     if newSelection == lastSelection:
#       break

#     selection = newSelection
#     yield selection

# iterator enumerateTextObjects*(editor: TextEditor, cursor: Cursor, move: string, backwards: bool = false): (int, Selection) =
#   var i = 0
#   for selection in iterateTextObjects(editor, cursor, move, backwards):
#     yield (i, selection)
#     inc i

# proc vimSelectTextObject(editor: TextEditor, textObject: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.exposeActive(editorContext, "vim-select-text-object").} =
#   # infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count})"

#   editor.setSelections editor.selections.mapIt(block:
#       var res = it.last
#       var resultSelection = it
#       # infof"-> {resultSelection}"

#       for i, selection in enumerateTextObjects(editor, res, textObject, backwards):
#         # infof"{i}: {res} -> {selection}"
#         resultSelection = resultSelection or selection
#         if i == max(count, 1) - 1:
#           break

#       # infof"vimSelectTextObject({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count}): {resultSelection}"
#       if it.isBackwards:
#         resultSelection.reverse
#       else:
#         resultSelection
#     )

#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimSelectSurrounding(editor: TextEditor, textObject: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.exposeActive(editorContext, "vim-select-surrounding").} =
#   # infof"vimSelectSurrounding({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count})"

#   editor.setSelections editor.selections.mapIt(block:
#       let resultSelection = editor.getSelectionForMove(it.last, textObject, count)
#       # infof"vimSelectSurrounding({textObject}, {textObjectRange}, {backwards}, {allowEmpty}, {count}): {resultSelection}"
#       if it.isBackwards:
#         resultSelection.reverse
#       else:
#         resultSelection
#     )

#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc moveSelectionNext(editor: TextEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext, "move-selection-next").} =
#   # infof"moveSelectionNext '{move}' {count} {backwards} {allowEmpty}"
#   editor.vimState.deleteInclusiveEnd = false
#   let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
#   editor.setSelections editor.selections.mapIt(block:
#       var res = it.last
#       for k in 0..<max(1, count):
#         for i, selection in enumerateTextObjects(editor, res, move, backwards):
#           if i == 0: continue
#           let cursor = if backwards: selection.last else: selection.first
#           # echo i, ", ", selection, ", ", cursor, ", ", it
#           if cursor == it.last:
#             continue
#           if editor.lineLength(selection.first.line) == 0:
#             if allowEmpty:
#               res = cursor
#               break
#             else:
#               continue

#           if selection.first.column >= editor.lineLength(selection.first.line) or editor.getChar(selection.first) notin Whitespace:
#             res = cursor
#             break
#       # echo res, ", ", it, ", ", which
#       res.toSelection(it, which)
#     )

#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc applyMove(editor: TextEditor, selections: seq[Selection], move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, which: Option[SelectionCursor] = SelectionCursor.none): seq[Selection] =
#   ## Applies the given move `count` times and returns the resulting selections
#   ## `allowEmpty` If true then the move can stop on empty lines
#   ## `backwards` Move backwards
#   ## `count` How often to apply the move
#   ## `which` How to assemble the final selection from the input and the move. If not set uses `editor.text.cursor.movement`

#   # infof"moveSelectionEnd '{move}' {count} {backwards} {allowEmpty}"
#   let which = which.get(getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both))
#   return selections.mapIt(block:
#       var res = it.last
#       for k in 0..<max(1, count):
#         for i, selection in enumerateTextObjects(editor, res, move, backwards):
#           let cursor = if backwards: selection.first else: selection.last
#           if cursor == it.last:
#             continue
#           if editor.lineLength(selection.last.line) == 0:
#             if allowEmpty:
#               res = cursor
#               break
#             else:
#               continue
#           if selection.last.column < editor.lineLength(selection.last.line) and
#               editor.getChar(selection.last) notin Whitespace:
#             res = cursor
#             break
#           if backwards and selection.last.column == editor.lineLength(selection.last.line):
#             res = cursor
#             break
#       res.toSelection(it, which)
#     )

# proc moveSelectionEnd(editor: TextEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext, "move-selection-end").} =

#   editor.setSelections editor.applyMove(editor.selections, move, backwards, allowEmpty, count)
#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc moveParagraph(editor: TextEditor, backwards: bool, count: int = 1) {.exposeActive(editorContext, "move-paragraph").} =
#   let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
#   editor.setSelections editor.selections.mapIt(block:
#       var res = it.last
#       for k in 0..<max(1, count):
#         for i, selection in enumerateTextObjects(editor, res, "vim-paragraph-inner", backwards):
#           if i == 0: continue
#           let cursor = if backwards: selection.last else: selection.first
#           if editor.lineLength(cursor.line) == 0:
#             res = cursor
#             break

#       res.toSelection(it, which)
#     )

#   if editor.vimState.selectLines:
#     editor.selectLine()

#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimDeleteLeft*(editor: TextEditor) =
#   yankedLines = editor.vimState.selectLines
#   editor.copy()
#   editor.addNextCheckpoint "insert"
#   editor.deleteLeft()

# proc vimDeleteRight*(editor: TextEditor) =
#   yankedLines = editor.vimState.selectLines
#   editor.copy()
#   editor.addNextCheckpoint "insert"
#   editor.deleteRight(includeAfter=editor.vimState.cursorIncludeEol)

# exposeActive editorContext, "vim-delete-left", vimDeleteLeft
# exposeActive editorContext, "vim-delete-right", vimDeleteRight

# proc vimMoveCursorPage(editor: TextEditor, direction: float, count: int = 1, center: bool = false) {.exposeActive(editorContext, "vim-move-cursor-page").} =
#   editor.moveCursorPage(direction * max(count, 1).float, includeAfter=editor.vimState.cursorIncludeEol)
#   let nextScrollBehaviour = if center: CenterAlways.some else: ScrollBehaviour.none
#   editor.scrollToCursor(scrollBehaviour = nextScrollBehaviour)
#   editor.setNextSnapBehaviour(Never)
#   if editor.vimState.selectLines:
#     editor.selectLine()

# proc vimMoveCursorVisualPage(editor: TextEditor, direction: float, count: int = 1, center: bool = false) {.exposeActive(editorContext, "vim-move-cursor-visual-page").} =
#   if editor.vimState.selectLines:
#     editor.moveCursorPage(direction * max(count, 1).float, includeAfter=editor.vimState.cursorIncludeEol)
#   else:
#     editor.moveCursorVisualPage(direction * max(count, 1).float, includeAfter=editor.vimState.cursorIncludeEol)
#   let defaultScrollBehaviour = editor.getDefaultScrollBehaviour
#   let defaultCenter = defaultScrollBehaviour in {CenterAlways, CenterOffscreen}
#   let nextScrollBehaviour = if center and defaultCenter: CenterAlways.some else: ScrollBehaviour.none
#   editor.scrollToCursor(scrollBehaviour = nextScrollBehaviour)
#   editor.setNextSnapBehaviour(Never)
#   if editor.vimState.selectLines:
#     editor.selectLine()

func toSelection*(cursor: Cursor, default: Selection, which: sca.SelectionCursor): Selection =
  case which
  of sca.Config: return default
  of sca.Both: return (cursor, cursor).toSelection
  of sca.First: return (cursor, default.last).toSelection
  of sca.Last: return (default.first, cursor).toSelection
  of sca.LastToFirst: return (default.last, cursor).toSelection

proc moveFirst(editor: TextEditor, move: string) {.exposeActive(editorContext).} =
  let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  editor.setSelections editor.selections.mapIt(
    editor.applyMove(it.last, move, 1, wrap = true, includeEol = editor.vimState.cursorIncludeEol).first.toSelection(it, cursorSelector)
  )

  if editor.vimState.selectLines:
    editor.selectLine()
  editor.scrollToCursor()
  editor.updateTargetColumn()

proc moveLast(editor: TextEditor, move: string, count: int = 1, wrap: bool = false) {.exposeActive(editorContext).} =
  let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  debugf"moveLast '{move}', {editor.vimState.cursorIncludeEol}"
  editor.setSelections editor.selections.mapIt(
    editor.applyMove(it.last, move, 1, wrap = wrap, includeEol = editor.vimState.cursorIncludeEol).last.toSelection(it, cursorSelector)
  )

  if editor.vimState.selectLines:
    editor.selectLine()
  editor.scrollToCursor()
  editor.updateTargetColumn()

proc moveDirection(editor: TextEditor, move: string, direction: int, count: int = 1, wrap: bool = false, updateTargetColumn: bool = true) {.exposeActive(editorContext).} =
  let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  debugf"moveDirection '{move}', dir: {direction}, count: {count}, includeEol: {editor.vimState.cursorIncludeEol}"
  editor.setSelections editor.multiMove(editor.selections, move.ws, direction * max(count, 1), wrap, includeEol = editor.vimState.cursorIncludeEol)
  # editor.setSelections editor.selections.mapIt(
  #   editor.applyMove(it.last, move, direction * max(count, 1), wrap = wrap, includeEol = editor.vimState.cursorIncludeEol).last.toSelection(it, cursorSelector)
  # )

  if editor.vimState.selectLines:
    editor.selectLine()
  editor.scrollToCursor()
  if updateTargetColumn:
    editor.updateTargetColumn()

# proc vimMoveToEndOfLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-end-of-line").} =
#   # infof"vimMoveToEndOfLine {count}"
#   let count = max(1, count)
#   if count > 1:
#     editor.moveCursorLine(count - 1)
#   editor.moveLast("vim-line")
#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimMoveToEndOfVisualLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-end-of-visual-line").} =
#   # infof"vimMoveToEndOfLine {count}"
#   let count = max(1, count)
#   if count > 1:
#     editor.moveCursorLine(count - 1)
#   editor.moveLast("vim-visual-line")
#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimMoveCursorLineFirstChar(editor: TextEditor, direction: int, count: int = 1) {.exposeActive(editorContext, "vim-move-cursor-line-first-char").} =
#   editor.moveCursorLine(direction * max(count, 1))
#   editor.moveFirst "line-no-indent"
#   editor.updateTargetColumn()

# proc vimMoveToStartOfLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-start-of-line").} =
#   # infof"vimMoveToStartOfLine {count}"
#   let count = max(1, count)
#   if count > 1:
#     editor.moveCursorLine(count - 1)
#   editor.moveFirst "line-no-indent"
#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimPaste(editor: TextEditor, pasteRight: bool = false, inclusiveEnd: bool = false, register: string = "") {.exposeActive(editorContext, "vim-paste").} =
#   # infof"vimPaste {register}, lines: {yankedLines}"
#   let register = if register == "vim-default-register":
#     getVimDefaultRegister()
#   else:
#     register

#   editor.addNextCheckpoint "insert"

#   let selectionsToDelete = editor.selections
#   editor.setSelections editor.delete(selectionsToDelete, inclusiveEnd=false)

#   if yankedLines:
#     # todo: pass bool as parameter
#     if editor.mode != "vim-new.visual-line":
#       editor.moveLast "line", Both
#       editor.insertText "\n", autoIndent=false

#   if pasteRight:
#     editor.setSelections editor.selections.mapIt(editor.doMoveCursorColumn(it.last, 1, wrap=false).toSelection)

#   editor.setMode "vim-new.normal"
#   editor.paste register, inclusiveEnd=inclusiveEnd

# proc vimToggleCase(editor: TextEditor, moveCursorRight: bool) {.exposeActive(editorContext, "vim-toggle-case").} =
#   var editTexts: seq[string]

#   for s in editor.selections:
#     let text = editor.getText(s, inclusiveEnd=true)
#     var newText = ""
#     for r in text.runes:
#       if r.isLower:
#         newText.add $r.toUpper
#       else:
#         newText.add $r.toLower
#     editTexts.add newText

#   editor.addNextCheckpoint "insert"
#   let oldSelections = editor.selections
#   discard editor.edit(editor.selections, editTexts, inclusiveEnd=true)
#   editor.setSelections oldSelections.mapIt(it.first.toSelection)

#   editor.setMode "vim-new.normal"

#   if moveCursorRight:
#     editor.moveCursorColumn(1, Both, wrap=false,
#       includeAfter=editor.vimState.cursorIncludeEol)
#     editor.updateTargetColumn()

# proc vimCloseCurrentViewOrQuit() {.exposeActive(editorContext, "vim-close-current-view-or-quit").} =
#   let openEditors = getNumVisibleViews() + getNumHiddenViews()
#   if openEditors == 1:
#     plugin_runtime.quit()
#   else:
#     closeActiveView()

# proc vimIndent(editor: TextEditor) {.exposeActive(editorContext, "vim-indent").} =
#   editor.addNextCheckpoint "insert"
#   editor.indent()

# proc vimUnindent(editor: TextEditor) {.exposeActive(editorContext, "vim-unindent").} =
#   editor.addNextCheckpoint "insert"
#   editor.unindent()

# proc vimAddCursorAbove(editor: TextEditor) {.exposeActive(editorContext, "vim-add-cursor-above").} =
#   editor.addCursorAbove()
#   editor.scrollToCursor()

# proc vimAddCursorBelow(editor: TextEditor) {.exposeActive(editorContext, "vim-add-cursor-below").} =
#   editor.addCursorBelow()
#   editor.scrollToCursor()

# proc vimEnter(editor: TextEditor) {.exposeActive(editorContext, "vim-enter").} =
#   editor.addNextCheckpoint "insert"
#   editor.insertText("\n")

proc normalMode(editor: TextEditor) {.exposeActive(editorContext).} =
  ## Exit to normal mode and clear things
  if $editor.mode == "vim-new.normal":
    editor.setSelection editor.getSelection.last.toSelection
    editor.clearTabStops()
  editor.setMode("vim-new.normal")

proc visualLineMode(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setMode "vim-new.visual-line"
  editor.selectLine()

# proc vimYankLine(editor: TextEditor) {.exposeActive(editorContext, "vim-yank-line").} =
#   editor.vimState.selectLines = true
#   editor.selectLine()
#   editor.vimYankSelection()
#   editor.vimState.selectLines = false

# proc vimDeleteLine(editor: TextEditor) {.exposeActive(editorContext, "vim-delete-line").} =
#   editor.vimState.selectLines = true
#   let oldSelections = editor.selections
#   editor.selectLine()
#   editor.vimDeleteSelection(true, oldSelections=oldSelections.some)
#   editor.vimState.selectLines = false

# proc vimChangeLine(editor: TextEditor) {.exposeActive(editorContext, "vim-change-line").} =
#   let oldSelections = editor.selections
#   editor.selectLine()
#   editor.vimChangeSelection(true, oldSelections=oldSelections.some)

# proc vimDeleteToLineEnd(editor: TextEditor) {.exposeActive(editorContext, "vim-delete-to-line-end").} =
#   let oldSelections = editor.selections
#   editor.setSelections editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
#   editor.vimDeleteSelection(true, oldSelections=oldSelections.some)
#   editor.vimState.selectLines = false

# proc vimChangeToLineEnd(editor: TextEditor) {.exposeActive(editorContext, "vim-change-to-line-end").} =
#   let oldSelections = editor.selections
#   editor.setSelections editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
#   editor.vimChangeSelection(true, oldSelections=oldSelections.some)
#   editor.vimState.selectLines = false

# proc vimYankToLineEnd(editor: TextEditor) {.exposeActive(editorContext, "vim-yank-to-line-end").} =
#   editor.setSelections editor.selections.mapIt (it.last, editor.vimMotionLine(it.last, 0).last)
#   editor.vimYankSelection()
#   editor.vimState.selectLines = false

# proc vimMoveFileStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-file-start").} =
#   let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
#   editor.setSelection (count - 1, 0).toSelection(editor.selection, which)
#   editor.moveFirst "line-no-indent"
#   editor.scrollToCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimMoveFileEnd(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-file-end").} =
#   let line = if count == 0: editor.lineCount - 1 else: count - 1
#   let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
#   var newSelection = (line, 0).toSelection(editor.selection, which)
#   if newSelection == editor.selection:
#     let lineLen = editor.lineLength(line)
#     editor.setSelection (line, lineLen).toSelection(editor.selection, which)
#   else:
#     editor.setSelection newSelection
#     editor.moveFirst "line-no-indent"
#   editor.scrollToCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimMoveToMatchingOrFileOffset(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-matching-or-file-offset").} =
#   if count == 0:
#     editor.vimMoveToMatching()
#   else:
#     let line = clamp((count * editor.lineCount) div 100, 0, editor.lineCount - 1)
#     let which = getOption[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
#     editor.setSelection (line, 0).toSelection(editor.selection, which)
#     editor.moveFirst "line-no-indent"
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimScrollLineToTopAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-top-and-move-line-start").} =
#   if editor.getCommandCount != 0:
#     editor.setSelection (editor.getCommandCount, 0).toSelection
#   editor.moveFirst "line-no-indent"
#   editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

# proc vimScrollLineToTop(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-top").} =
#   if editor.getCommandCount != 0:
#     editor.setSelection (editor.getCommandCount, editor.selection.last.column).toSelection
#   editor.setCursorScrollOffset getVimLineMargin() * platformTotalLineHeight()

# proc vimCenterLineAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-center-line-and-move-line-start").} =
#   if editor.getCommandCount != 0:
#     editor.setSelection (editor.getCommandCount, 0).toSelection
#   editor.moveFirst "line-no-indent"
#   editor.centerCursor()

# proc vimCenterLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-center-line").} =
#   if editor.getCommandCount != 0:
#     editor.setSelection (editor.getCommandCount, editor.selection.last.column).toSelection
#   editor.centerCursor()

# proc vimScrollLineToBottomAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-bottom-and-move-line-start").} =
#   if editor.getCommandCount != 0:
#     editor.setSelection (editor.getCommandCount, 0).toSelection
#   editor.moveFirst "line-no-indent"
#   editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

# proc vimScrollLineToBottom(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-scroll-line-to-bottom").} =
#   if editor.getCommandCount != 0:
#     editor.setSelection (editor.getCommandCount, editor.selection.last.column).toSelection
#   editor.setCursorScrollOffset (editor.screenLineCount.float - getVimLineMargin()) * platformTotalLineHeight()

proc insertMode(editor: TextEditor, move: string = "") {.exposeActive(editorContext).} =
  # debugf"insertMode '{move}'"
  case move
  of "right":
    editor.setSelections editor.selections.mapIt(editor.applyMove(it.last, "column", 1))
  of "line-end":
    editor.setSelections editor.selections.mapIt(editor.applyMove(it.last, "line", 1).last.toSelection)
  of "line-no-indent":
    editor.setSelections editor.selections.mapIt(editor.applyMove(it.last, "line-no-indent", 1).first.toSelection)
  of "first":
    editor.setSelections editor.selections.mapIt(it.normalized.first.toSelection)
  of "line-start":
    editor.setSelections editor.selections.mapIt(editor.applyMove(it.last, "line", 1).first.toSelection)
  else:
    discard
  editor.setMode "vim-new.insert"
  editor.addNextCheckpoint ws"insert"

# proc vimInsertLineBelow(editor: TextEditor) {.exposeActive(editorContext, "vim-insert-line-below").} =
#   editor.moveLast "line", Both
#   editor.addNextCheckpoint "insert"
#   editor.insertText "\n"
#   editor.setMode "vim-new.insert"

# proc vimInsertLineAbove(editor: TextEditor, move: string = "") {.exposeActive(editorContext, "vim-insert-line-above").} =
#   editor.moveFirst "line", Both
#   editor.addNextCheckpoint "insert"
#   editor.insertText "\n", autoIndent=false
#   editor.vimMoveCursorLine -1
#   editor.setMode "vim-new.insert"

# proc vimSetSearchQueryFromWord(editor: TextEditor) {.exposeActive(editorContext, "vim-set-search-query-from-word").} =
#   editor.setSelection editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b").first.toSelection

# proc vimSetSearchQueryFromSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-set-search-query-from-selection").} =
#   discard editor.setSearchQuery(editor.getText(editor.selection, inclusiveEnd=true), escapeRegex=true)
#   editor.setSelection editor.selection.first.toSelection
#   editor.setMode("vim-new.normal")

# proc vimNextSearchResult(editor: TextEditor) {.exposeActive(editorContext, "vim-next-search-result").} =
#   editor.setSelection editor.getNextFindResult(editor.selection.last).first.toSelection
#   editor.scrollToCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)
#   editor.updateTargetColumn()

# proc vimPrevSearchResult(editor: TextEditor) {.exposeActive(editorContext, "vim-prev-search-result").} =
#   editor.setSelection editor.getPrevFindResult(editor.selection.last).first.toSelection
#   editor.scrollToCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)
#   editor.updateTargetColumn()

# proc vimOpenSearchBar(editor: TextEditor) {.exposeActive(editorContext, "vim-open-search-bar").} =
#   editor.openSearchBar()
#   if getActiveEditor().isTextEditor(editor):
#     editor.setMode("vim-new.insert")

# proc vimExitCommandLine() {.expose("vim-exit-command-line").} =
#   if getActiveEditor().isTextEditor(editor):
#     if editor.mode == "vim-new.normal":
#       exitCommandLine()
#       return

#     editor.setMode("vim-new.normal")

# proc vimExitPopup() {.expose("vim-exit-popup").} =
#   if getActiveEditor().isTextEditor(editor):
#     if editor.mode == "vim-new.normal":
#       if getActivePopup().isSelectorPopup(popup):
#         popup.cancel()
#       return

#     editor.setMode("vim-new.normal")

# proc vimSelectWordOrAddCursor(editor: TextEditor) {.exposeActive(editorContext, "vim-select-word-or-add-cursor").} =
#   if editor.selections.len == 1:
#     var selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b")
#     selection.last.column -= 1
#     editor.setSelection selection
#   else:
#     let next = editor.getNextFindResult(editor.selection.last, includeAfter=false)
#     editor.setSelections editor.selections & next
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)
#     editor.updateTargetColumn()

#   editor.setMode("vim-new.visual")

# proc vimMoveLastSelectionToNextSearchResult(editor: TextEditor) {.exposeActive(editorContext, "vim-move-last-selection-to-next-search-result").} =
#   if editor.selections.len == 1:
#     var selection = editor.setSearchQueryFromMove("word", prefix=r"\b", suffix=r"\b")
#     selection.last.column -= 1
#     editor.setSelection selection
#   else:
#     let next = editor.getNextFindResult(editor.selection.last, includeAfter=false)
#     editor.setSelections editor.selections[0..^2] & next
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)
#     editor.updateTargetColumn()

#   editor.setMode("vim-new.visual")

# proc vimSetSearchQueryOrAddCursor(editor: TextEditor) {.exposeActive(editorContext, "vim-set-search-query-or-add-cursor").} =
#   if editor.selections.len == 1:
#     let text = editor.getText(editor.selection, inclusiveEnd=true)
#     let textEscaped = text.escapeRegex
#     let currentSearchQuery = editor.getSearchQuery()
#     # infof"'{text}' -> '{textEscaped}' -> '{currentSearchQuery}'"
#     if textEscaped != currentSearchQuery and r"\b" & textEscaped & r"\b" != currentSearchQuery:
#       if editor.setSearchQuery(text, escapeRegex=true):
#         return

#   let next = editor.getNextFindResult(editor.selection.last, includeAfter=false)
#   editor.setSelections editor.selections & next
#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimSaveState() {.expose("vim-save-state").} =
#   try:
#     var states = initTable[string, JsonNode]()

#     for id, state in editorStates:
#       if id.isTextEditor(editor):
#         let filename = editor.getFileName()
#         if filename == "":
#           continue

#         var marks = initTable[string, seq[Selection]]()
#         for name, anchors in editor.vimState.marks:
#           let selections = editor.resolveAnchors(anchors)
#           marks[name] = selections
#         for name, selections in editor.vimState.unresolveMarks:
#           marks[name] = selections

#         if marks.len > 0:
#           states[filename] = %*{
#             "marks": marks.toJson,
#           }

#     setSessionData("vim.states", states)
#   except:
#     infof"Failed to save vim editor states"

# proc resolveMarks(editor: TextEditor) =
#   let unresolveMarks = editor.vimState.unresolveMarks
#   for name, selections in unresolveMarks:
#     let anchors = editor.createAnchors(selections)
#     if anchors.len > 0:
#       editor.vimState.marks[name] = anchors
#       editor.vimState.unresolveMarks.del(name)

# proc vimAddMark(editor: TextEditor, name: string) {.exposeActive(editorContext, "vim-add-mark").} =
#   editor.resolveMarks()
#   editor.vimState.marks[name] = editor.createAnchors(editor.selections)

# proc vimGotoMark(editor: TextEditor, name: string) {.exposeActive(editorContext, "vim-goto-mark").} =
#   editor.resolveMarks()

#   if name in editor.vimState.marks:
#     let newSelections = editor.resolveAnchors(editor.vimState.marks[name])
#     if newSelections.len == 0:
#       return

#     case editor.mode
#     of "vim-new.visual", "vim-new.visual-line":
#       let oldSelections = editor.selections
#       if newSelections.len == oldSelections.len:
#         editor.setSelections collect:
#           for i in 0..newSelections.high:
#             oldSelections[i] or newSelections[i]
#       else:
#         editor.setSelections newSelections
#     else:
#       editor.setSelections newSelections

#     editor.updateTargetColumn()
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimDeleteWordBack(editor: TextEditor) {.exposeActive(editorContext, "vim-delete-word-back").} =
#   let selections = editor.applyMove(editor.selections, "vim-word", true, true, 1, which = SelectionCursor.Last.some)
#   editor.setSelections editor.delete(selections)
#   editor.autoShowCompletions()

# proc vimDeleteLineBack(editor: TextEditor) {.exposeActive(editorContext, "vim-delete-line-back").} =
#   let selections = editor.applyMove(editor.selections, "vim-line", true, true, 1, which = SelectionCursor.Last.some)
#   editor.setSelections editor.delete(selections)
#   editor.autoShowCompletions()

# proc vimSurround(editor: TextEditor, text: string) {.exposeActive(editorContext, "vim-surround").} =
#   let (left, right) = case text
#   of "(", ")": ("(", ")")
#   of "{", "}": ("{", "}")
#   of "[", "]": ("[", "]")
#   of "<", ">": ("<", ">")
#   else:
#     (text, text)

#   var insertSelections: seq[Selection] = @[]
#   var insertTexts: seq[string] = @[]
#   for s in editor.selections:
#     let s = s.normalized
#     insertSelections.add s.first.toSelection
#     insertSelections.add editor.doMoveCursorColumn(s.last, 1).toSelection
#     insertTexts.add left
#     insertTexts.add right

#   editor.addNextCheckpoint "insert"
#   let newSelections = editor.insertMulti(insertSelections, insertTexts)
#   if newSelections.len mod 2 != 0:
#     return

#   editor.setSelections collect:
#     for i in 0..<newSelections.len div 2:
#       editor.includeSelectionEnd((newSelections[i * 2].first, newSelections[i * 2 + 1].last), false)

# proc vimToggleLineComment(editor: TextEditor) {.exposeActive(editorContext, "vim-toggle-line-comment").} =
#   editor.addNextCheckpoint "insert"
#   editor.toggleLineComment()

# proc vimStartMacro(editor: TextEditor, name: string) {.exposeActive(editorContext, "vim-start-macro").} =
#   if isReplayingCommands() or isRecordingCommands(getCurrentMacroRegister()):
#     return
#   setOption("editor.current-macro-register", name)
#   setRegisterText(ws"", name)
#   startRecordingCommands(name)

# proc vimPlayMacro(editor: TextEditor, name: string) {.exposeActive(editorContext, "vim-play-macro").} =
#   let register = if name == "@":
#     getCurrentMacroRegister()
#   else:
#     name

#   replayCommands(register)

# proc vimStopMacro(editor: TextEditor) {.exposeActive(editorContext, "vim-stop-macro").} =
#   if isReplayingCommands() or not isRecordingCommands(getCurrentMacroRegister()):
#     return
#   stopRecordingCommands(getCurrentMacroRegister())

# proc vimInvertSelections(editor: TextEditor) {.exposeActive(editorContext, "vim-invert-selections").} =
#   editor.setSelections editor.selections.mapIt((it.last, it.first))
#   editor.scrollToCursor()
#   editor.updateTargetColumn()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimInvertLineSelections(editor: TextEditor) {.exposeActive(editorContext, "vim-invert-line-selections").} =
#   editor.setSelections editor.selections.mapIt((it.last, it.first))
#   editor.scrollToCursor()
#   editor.updateTargetColumn()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimReverseSelections(editor: TextEditor) {.exposeActive(editorContext, "vim-reverse-selections").} =
#   editor.setSelections editor.selections.reversed()
#   editor.scrollToCursor()
#   editor.updateTargetColumn()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimJoinLines(editor: TextEditor, reduceSpace: bool) {.exposeActive(editorContext, "vim-join-lines").} =
#   editor.addNextCheckpoint "insert"
#   if reduceSpace:
#     var insertTexts: seq[string]
#     let selectionsToDelete = editor.selections.mapIt(block:
#       let lineLen = editor.lineLength(it.last.line)
#       if lineLen == 0 or editor.charAt((it.last.line, lineLen - 1)) == ' ':
#         insertTexts.add ""
#       else:
#         insertTexts.add " "
#       var nextLineIndent = editor.getSelectionForMove((it.last.line + 1, 0), "line-no-indent", 0)
#       ((it.last.line, lineLen), (it.last.line + 1, nextLineIndent.first.column))
#     )
#     editor.setSelections editor.edit(selectionsToDelete, insertTexts, inclusiveEnd=false).mapIt(it.first.toSelection)
#   else:
#     let selectionsToDelete = editor.selections.mapIt(block:
#       let lineLen = editor.lineLength(it.last.line)
#       ((it.last.line, lineLen), (it.last.line + 1, 0))
#     )
#     editor.setSelections editor.delete(selectionsToDelete, inclusiveEnd=false).mapIt(it.first.toSelection)

# proc vimMoveToColumn(editor: TextEditor, count: int = 1) {.exposeActive(editorContext, "vim-move-to-column").} =
#   editor.setSelections editor.selections.mapIt((it.last.line, count).toSelection)
#   editor.scrollToCursor()
#   editor.updateTargetColumn()

# proc vimAddNextSameNodeToSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-add-next-same-node-to-selection").} =
#   if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
#     editor.setSelections editor.selections & selection
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)
#     editor.updateTargetColumn()

# proc vimMoveSelectionToNextSameNode(editor: TextEditor) {.exposeActive(editorContext, "vim-move-selection-to-next-same-node").} =
#   if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
#     editor.setSelections editor.selections[0..^2] & selection
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)
#     editor.updateTargetColumn()

# proc vimAddNextSiblingToSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-add-next-sibling-to-selection").} =
#   if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
#     editor.setSelections editor.selections & selection
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)
#     editor.updateTargetColumn()

# proc vimMoveSelectionToNextSibling(editor: TextEditor) {.exposeActive(editorContext, "vim-move-selection-to-next-sibling").} =
#   if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
#     editor.setSelections editor.selections[0..^2] & selection
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)
#     editor.updateTargetColumn()

# proc vimShrinkSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-shrink-selection").} =
#   editor.setSelections editor.selections.mapIt(block:
#     if it.first.line == it.last.line and abs(it.first.column - it.last.column) < 2:
#       it
#     else:
#       (editor.doMoveCursorColumn(it.first, 1), editor.doMoveCursorColumn(it.last, -1))
#   )
#   editor.scrollToCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)
#   editor.updateTargetColumn()

# proc vimEvaluateSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-evaluate-selection").} =
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, true)

# proc vimIncrementSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-increment-selection").} =
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, true, suffix = "+1")

# proc vimDecrementSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-decrement-selection").} =
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, true, suffix = "-1")

# proc vimIncrementSelectionByIndex(editor: TextEditor) {.exposeActive(editorContext, "vim-increment-selection-by-index").} =
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, true, addSelectionIndex = true)

# proc vimIncrement(editor: TextEditor) {.exposeActive(editorContext, "vim-increment").} =
#   editor.setSelections editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, false, suffix = "+1")
#   editor.setSelections editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

# proc vimDecrement(editor: TextEditor) {.exposeActive(editorContext, "vim-decrement").} =
#   editor.setSelections editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, false, suffix = "-1")
#   editor.setSelections editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

# proc vimIncrementByIndex(editor: TextEditor) {.exposeActive(editorContext, "vim-increment-by-index").} =
#   editor.setSelections editor.selections.mapIt(editor.getSelectionForMove(it.last, "number"))
#   editor.addNextCheckpoint("insert")
#   editor.evaluateExpressions(editor.selections, false, addSelectionIndex = true)
#   editor.setSelections editor.selections.mapIt(editor.doMoveCursorColumn(it.last, -1).toSelection)

# proc vimGotoNextDiagnostic(editor: TextEditor) {.exposeActive(editorContext, "vim-goto-next-diagnostic").} =
#   let severity = getOption("text.jump-diagnostic-severity", 1)
#   editor.setSelection editor.getNextDiagnostic(editor.selection.last, severity).first.toSelection
#   editor.scrollToCursor()
#   editor.updateTargetColumn()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimGotoPrevDiagnostic(editor: TextEditor) {.exposeActive(editorContext, "vim-goto-prev-diagnostic").} =
#   let severity = getOption("text.jump-diagnostic-severity", 1)
#   editor.setSelection editor.getPrevDiagnostic(editor.selection.last, severity).first.toSelection
#   editor.scrollToCursor()
#   editor.updateTargetColumn()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimGotoNextChange(editor: TextEditor) {.exposeActive(editorContext, "vim-goto-next-change").} =
#   editor.setSelection editor.getNextChange(editor.selection.last).first.toSelection
#   editor.scrollToCursor()
#   editor.centerCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimGotoPrevChange(editor: TextEditor) {.exposeActive(editorContext, "vim-goto-prev-change").} =
#   editor.setSelection editor.getPrevChange(editor.selection.last).first.toSelection
#   editor.scrollToCursor()
#   editor.centerCursor()
#   editor.setNextSnapBehaviour(MinDistanceOffscreen)

# proc vimReplaceInputHandler(editor: TextEditor, input: string) {.exposeActive(editorContext, "vim-replace-input-handler").} =
#   editor.vimReplace(input)

# proc vimInsertRegisterInputHandler(editor: TextEditor, input: string) {.exposeActive(editorContext, "vim-insert-register-input-handler").} =
#   editor.vimPaste register=input, inclusiveEnd=true
#   editor.setMode "vim-new.insert"

proc modeChangedHandler(editor: TextEditor, oldModes: seq[string], newModes: seq[string]) {.exposeActive(editorContext).} =
  # log lvlInfo, &"modeChangedHandler {editor}, {oldModes} -> {newModes}"

  let oldMode = if oldModes.len > 0:
    oldModes[0]
  else:
    ""

  if newModes.len == 0:
    return

  let newMode = newModes[0]

  if not editor.modes().toOpenArray.contains(ws"vim-new"):
    return

  if newMode == "":
    editor.setMode "vim-new.normal"
    return

  if not newMode.startsWith("vim"):
    return

  let recordModes = [
    "vim-new.visual",
    "vim-new.visual-line",
    "vim-new.insert",
  ].toHashSet

  # debugf"vim: handle mode change {oldMode} -> {newMode}"
  if newMode == "vim-new.normal":
    if not isReplayingCommands() and isRecordingCommands(ws".-temp"):
      stopRecordingCommands(ws".-temp")

      if editor.getRevision > editor.vimState.revisionBeforeImplicitInsertMacro:
        # debugf"Record implicit macro because document was modified"
        let text = getRegisterText(ws".-temp")
        setRegisterText(text, ws".")
  else:
    if oldMode == "vim-new.normal" and newMode in recordModes:
      editor.startRecordingCurrentCommandInPeriodMacro()

    editor.clearCurrentCommandHistory(retainLast=true)

  editor.vimState.selectLines = newMode == "vim-new.visual-line"
  editor.vimState.cursorIncludeEol = newMode == "vim-new.insert"
  editor.vimState.currentUndoCheckpoint = if newMode == "vim-new.insert": "word" else: "insert"

  case newMode
  of "vim-new.normal":
    editor.setSetting "text.inclusive-selection", false
    editor.setSelections editor.selections.mapIt(editor.vimClamp(it.last).toSelection)
    editor.saveCurrentCommandHistory()
    editor.hideCompletions()

  of "vim-new.insert":
    editor.setSetting "text.inclusive-selection", false

  of "vim-new.visual":
    editor.setSetting "text.inclusive-selection", true

  of "vim-new.visual-line":
    editor.setSetting "text.inclusive-selection", false

  else:
    editor.setSetting "text.inclusive-selection", false

# proc loadVimKeybindings*() {.expose("load-vim-keybindings").} =
#   let afterRestoreSessionHandle = addCallback proc(args: JsonNode): JsonNode =
#     let states = getSessionData[Table[string, JsonNode]]("vim.states")
#     for id in getAllEditors():
#       if id.isTextEditor(editor):
#         try:
#           let filename = editor.getFileName()
#           if states.hasKey(filename):
#             let editorState = states[filename]
#             if editorState.hasKey("marks"):
#               let marks = editorState["marks"].jsonTo(Table[string, seq[Selection]])
#               for name, selections in marks:
#                 editor.vimState.unresolveMarks[name] = selections
#         except:
#           infof"Failed to restore marks for {editor}"
#   scriptSetCallback("after-restore-session", afterRestoreSessionHandle)

#   let beforeSaveAppStateHandle = addCallback proc(args: JsonNode): JsonNode =
#     vimSaveState()
#   scriptSetCallback("before-save-app-state", beforeSaveAppStateHandle)
