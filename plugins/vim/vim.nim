# import std/[strutils, macros, genasts, sequtils, sets, algorithm, jsonutils]
import std/[strformat, json, jsonutils, strutils, tables, macros, genasts, streams, sequtils, sets, os, terminal, colors, algorithm, unicode]
import results
import util, custom_unicode, myjsonutils, id, wrap, sugar, custom_regex
# import input_api
import api
from "../../src/scripting_api.nim" as sca import nil
import "../../src/input_api.nim"

proc last*[T](list: WitList[T]): lent T =
  assert list.len > 0
  return list[list.len - 1]

proc `==`*[T](a, b: WitList[T]): bool =
  if a.len != b.len:
    return false
  return equalMem(a.data, b.data, a.len)

proc `==`*(a, b: WitString): bool =
  if a.len != b.len:
    return false
  return equalMem(a.data, b.data, a.len)

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

proc moveCursorColumn(editor: TextEditor, amount: int, wrap: bool = false, includeEol: bool = true) =
  editor.setSelections editor.multiMove(editor.selections, ws"column", 1, wrap, includeEol).mapIt(it.last.toSelection).stackWitList()

proc moveCursorColumn(editor: TextEditor, selections: WitList[Selection], amount: int, wrap: bool = false, includeEol: bool = true): WitList[Selection] =
  editor.multiMove(selections, ws"column", 1, wrap, includeEol).mapIt(it.last.toSelection).stackWitList()

proc moveCursorLine(editor: TextEditor, amount: int, includeEol: bool = true) =
  editor.setSelections editor.multiMove(editor.selections, ws"line-down", amount, false, includeEol).mapIt(it.last.toSelection).stackWitList()

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

macro command*(fun: typed): untyped =
  let name = fun.name.repr.splitCase.parts.joinCase(Kebab)
  return exposeImpl(newLit(""), name, fun, active=false)

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

proc normalMode(editor: TextEditor) {.exposeActive(editorContext).} =
  ## Exit to normal mode and clear things
  if $editor.mode == "vim-new.normal":
    editor.setSelection editor.getSelection.last.toSelection
    editor.clearTabStops()
  editor.setMode("vim-new.normal")

proc visualLineMode(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setMode "vim-new.visual-line"
  editor.selectLine()

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

template mergeSelections*(a, b: WitList[Selection], body: untyped): seq[Selection] =
  let aa = a
  let bb = b
  collect(newSeq):
    for i in 0..min(aa.high, bb.high):
      let it1 {.inject.} = aa[i]
      let it2 {.inject.} = bb[i]
      body

proc vimReplace(editor: TextEditor, input: string) {.exposeActive(editorContext).} =
  let content = editor.content
  debugf"vimReplace '{input}'"
  # let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, ws"column", 1, true, true)):
    # (it1.first, it2.last).toSelection
  let selections = editor.selections

  debugf"{selections}"
  let texts = selections.mapIt(block:
    let selection = it
    debugf"slice selection {selection}"
    let selectedText = content.sliceSelection(selection, inclusive=true)
    debugf"'{selectedText.text}'"
    var newText = newStringOfCap(selectedText.bytes.int * input.len.int)
    var lastIndex = 0
    var index = selectedText.find(ws"\n", 0)
    debugf"nl: {index}, {selectedText.runes.int}"
    if index.isNone:
      newText.add input.repeat(selectedText.runes.int)
    else:
      while index.isSome:
        let lineLen = selectedText.slice(lastIndex, index.get).runes.int - 1
        newText.add input.repeat(lineLen)
        newText.add "\n"
        lastIndex = index.get.int + 1
        index = selectedText.find(ws"\n", index.get + 1)

      let lineLen = selectedText.slice(lastIndex, selectedText.bytes.int - 1).runes.int
      newText.add input.repeat(lineLen)
    debugf"'{newText}'"

    stackWitString(newText)
  )

  debugf"replace {editor.selections} with '{input}' -> {texts}"

  editor.addNextCheckpoint ws"insert"
  editor.setSelections editor.edit(editor.selections, @@texts, inclusive=true).mapIt(it.first.toSelection)
  editor.normalMode()

proc selectMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
  debugf"selectMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    log lvlDebug, $editor.command(action.ws, arg.ws)
  editor.updateTargetColumn()

proc deleteMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
  debugf"vimDeleteMove '{move}' {count}"
  let oldSelections = @(editor.selections)
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    discard editor.command(action.ws, arg.ws)
  editor.deleteSelection(false, oldSelections=oldSelections.some)
  editor.recordCurrentCommandInPeriodMacro()

proc changeMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
  debugf"vimChangeMove '{move}' {count}"
  let oldSelections = @(editor.selections)
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    discard editor.command(action.ws, arg.ws)
  editor.changeSelection(false, oldSelections=oldSelections.some)

proc yankMove(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
  debugf"vimYankMove '{move}' {count}"
  let (action, arg) = move.parseAction
  for i in 0..<max(count, 1):
    discard editor.command(action.ws, arg.ws)
  editor.yankSelection()

proc moveTo*(editor: TextEditor, target: string, before: bool, count: int = 1) {.exposeActive(editorContext).} =
  debugf"vimMoveTo '{target}' {before} {count}"

  proc parseTarget(target: string): string =
    if target.len == 1:
      return target

    if target.parseFirstInput().getSome(res):
      if res.inputCode.a == INPUT_SPACE:
        return " "
      elif res.inputCode.a <= int32.high:
        return $Rune(res.inputCode.a)
    else:
      log lvlError, &" -> failed to parse key: {target}"

  let key = parseTarget(target)
  var s = editor.getSelections

  for _ in 0..<max(1, count):
    s = editor.multiMove(s, stackWitString("move-to " & key), 1, true, true)
  if before:
    s = editor.multiMove(s, ws"column", -1, true, true)

  editor.setSelections s
  editor.updateTargetColumn()

proc vimClamp*(editor: TextEditor, cursor: Cursor): Cursor =
  var lineLen = editor.lineLength(cursor.line)
  if not editor.vimState.cursorIncludeEol and lineLen > 0: lineLen.dec
  result = (cursor.line, min(cursor.column, lineLen))

proc vimMotionParagraphInner*(data: uint32, text: sink Rope, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.cdecl.} =
  debugf"vimMotionParagraphInner {data}, {selections}, {count}, {includeEol}"
  selections.mapIt:
    let isEmpty = text.lineLength(it.last.line) == 0

    var res = ((it.last.line.int, 0).toCursor, it.last).toSelection
    while res.first.line - 1 >= 0 and (text.lineLength(res.first.line - 1) == 0) == isEmpty:
      dec res.first.line
    while res.last.line + 1 < text.lines and (text.lineLength(res.last.line + 1) == 0) == isEmpty:
      inc res.last.line

    res.last.column = text.lineLength(res.last.line).int32
    res

proc vimMotionParagraphOuter*(data: uint32, text: sink Rope, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.cdecl.} =
  result = vimMotionParagraphInner(data, text, selections, count, includeEol)
  # todo
  # if result.last.line + 1 < editor.lineCount:
  #   result = result or vimMotionParagraphInner(data, text, (result.last.line.int + 1, 0).toCursor, 1, includeEol)

addCustomTextMove "vim-paragraph-inner", vimMotionParagraphInner
addCustomTextMove "vim-paragraph-outer", vimMotionParagraphOuter

iterator iterateTextObjects*(editor: TextEditor, cursor: Cursor, move: string, backwards: bool = false): Selection =
  var selection = editor.applyMove(cursor, move, 0)
  # debugf"iterateTextObjects({cursor}, {move}, {backwards}), selection: {selection}"
  yield selection
  while true:
    let lastSelection = selection
    if not backwards and selection.last.column == editor.lineLength(selection.last.line):
      if selection.last.line == editor.lineCount - 1:
        break
      selection = (selection.last.line.int + 1, 0).toSelection
    elif backwards and selection.first.column == 0:
      if selection.first.line == 0:
        break
      selection = (selection.first.line - 1, editor.lineLength(selection.first.line - 1)).toSelection
      if selection.first.column == 0:
        yield selection
        continue

    let nextCursor = if backwards: (selection.first.line, selection.first.column - 1) else: (selection.last.line, selection.last.column + 1)
    let newSelection = editor.applyMove(nextCursor, move, 0)
    # debugf"iterateTextObjects({cursor}, {move}, {backwards}) nextCursor: {nextCursor}, newSelection: {newSelection}"
    if newSelection == lastSelection:
      break

    selection = newSelection
    yield selection

iterator enumerateTextObjects*(editor: TextEditor, cursor: Cursor, move: string, backwards: bool = false): (int, Selection) =
  var i = 0
  for selection in iterateTextObjects(editor, cursor, move, backwards):
    yield (i, selection)
    inc i

proc selectTextObject(editor: TextEditor, textObject: string, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.exposeActive(editorContext).} =
  debugf"selectTextObject({textObject}, {textObjectRange}, {count})"

  editor.setSelections editor.selections.mapIt(block:
      var res = it.last
      var resultSelection = it
      # debugf"-> {resultSelection}"

      for i, selection in enumerateTextObjects(editor, res, textObject, false):
        debugf"{i}: {res} -> {selection}"
        resultSelection = resultSelection or selection
        if i == max(count, 1) - 1:
          break

      # debugf"selectTextObject({textObject}, {textObjectRange}, {count}): {resultSelection}"
      if it.isBackwards:
        resultSelection.reverse
      else:
        resultSelection
    )

  editor.scrollToCursor()
  editor.updateTargetColumn()

proc selectSurrounding(editor: TextEditor, textObject: string, count: int = 1, textObjectRange: VimTextObjectRange = Inner) {.exposeActive(editorContext).} =
  debugf"selectSurrounding({textObject}, {textObjectRange}, {count})"

  let selections = editor.selections
  let newSelections = mergeSelections(selections, editor.multiMove(selections, ws(textObject), count, wrap = false, includeEol = editor.vimState.cursorIncludeEol)):
    if it1.isBackwards:
      it2.reverse
    else:
      it2
  editor.setSelections newSelections

  editor.scrollToCursor()
  editor.updateTargetColumn()

proc moveSelectionNext(editor: TextEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext).} =
  # debugf"moveSelectionNext '{move}' {count} {backwards} {allowEmpty}"
  let text = editor.content
  editor.vimState.deleteInclusiveEnd = false
  let which = getSetting[sca.SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  editor.setSelections editor.selections.mapIt(block:
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

          if selection.first.column >= editor.lineLength(selection.first.line) or text.charAt(selection.first) notin Whitespace:
            res = cursor
            break
      # echo res, ", ", it, ", ", which
      res.toSelection(it, which)
    )

  editor.scrollToCursor()
  editor.updateTargetColumn()

proc applyMove(editor: TextEditor, selections: openArray[Selection], move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, which: Option[sca.SelectionCursor] = sca.SelectionCursor.none): seq[Selection] =
  ## Applies the given move `count` times and returns the resulting selections
  ## `allowEmpty` If true then the move can stop on empty lines
  ## `backwards` Move backwards
  ## `count` How often to apply the move
  ## `which` How to assemble the final selection from the input and the move. If not set uses `editor.text.cursor.movement`

  debugf"moveSelectionEnd '{move}' {count} {backwards} {allowEmpty}"
  let text = editor.content
  let which = which.get(getSetting[sca.SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both))
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
              text.charAt(selection.last) notin Whitespace:
            res = cursor
            break
          if backwards and selection.last.column == editor.lineLength(selection.last.line):
            res = cursor
            break
      res.toSelection(it, which)
    )

proc moveSelectionEnd(editor: TextEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext).} =

  editor.setSelections editor.applyMove(editor.selections.toOpenArray, move, backwards, allowEmpty, count)
  editor.scrollToCursor()
  editor.updateTargetColumn()

proc moveParagraph(editor: TextEditor, backwards: bool, count: int = 1) {.exposeActive(editorContext).} =
  let which = getSetting[sca.SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  editor.setSelections editor.selections.mapIt(block:
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
    editor.selectLine()

  editor.scrollToCursor()
  editor.updateTargetColumn()

proc deleteLeft*(editor: TextEditor) {.exposeActive(editorContext).} =
  yankedLines = editor.vimState.selectLines
  editor.copy(ws"", inclusiveEnd = false)
  editor.addNextCheckpoint ws"insert"
  let selections = editor.multiMove(editor.getSelections, ws"column", -1, wrap = false, includeEol = true)
  editor.setSelections editor.edit(selections, @@[ws""], inclusive=editor.vimState.cursorIncludeEol)

proc deleteRight*(editor: TextEditor) {.exposeActive(editorContext).} =
  yankedLines = editor.vimState.selectLines
  editor.copy(ws"", inclusiveEnd = false)
  editor.addNextCheckpoint ws"insert"
  let selections = editor.getSelections
  editor.setSelections editor.edit(selections, @@[ws""], inclusive=true)

proc moveCursorPage(editor: TextEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext).} =
  ## Direction 100 means 100% of window height downwards -100 is upwards, 50 would be 50%
  editor.setSelections editor.multiMove(editor.selections, ws"page", direction * max(count, 1), true, includeEol = editor.vimState.cursorIncludeEol)
  let nextScrollBehaviour = if center: CenterAlways.some else: ScrollBehaviour.none
  editor.scrollToCursor(behaviour = nextScrollBehaviour, 0.5)
  editor.setNextSnapBehaviour(Never)
  if editor.vimState.selectLines:
    editor.selectLine()

proc moveCursorVisualPage(editor: TextEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext).} =
  ## Direction 100 means 100% of window height downwards -100 is upwards, 50 would be 50%
  if editor.vimState.selectLines:
    editor.setSelections editor.multiMove(editor.selections, ws"page", direction * max(count, 1), true, includeEol = editor.vimState.cursorIncludeEol)
  else:
    editor.setSelections editor.multiMove(editor.selections, ws"visual-page", direction * max(count, 1), true, includeEol = editor.vimState.cursorIncludeEol)
  # todo
  # let defaultScrollBehaviour = editor.getDefaultScrollBehaviour
  # let defaultCenter = defaultScrollBehaviour in {CenterAlways, CenterOffscreen}
  # let nextScrollBehaviour = if center and defaultCenter: CenterAlways.some else: ScrollBehaviour.none
  let nextScrollBehaviour = ScrollBehaviour.none
  editor.scrollToCursor(behaviour = nextScrollBehaviour, 0.5)
  editor.setNextSnapBehaviour(Never)
  if editor.vimState.selectLines:
    editor.selectLine()

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

proc moveCursorLineFirstChar(editor: TextEditor, direction: int, count: int = 1) {.exposeActive(editorContext).} =
  let count = if count == 0: 1 else: count
  editor.moveCursorLine(direction * count)
  editor.moveFirst "line-no-indent"
  editor.updateTargetColumn()

proc moveToStartOfLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  let count = max(1, count)
  if count > 1:
    editor.moveCursorLine(count - 1)
  editor.moveFirst "line-no-indent"
  editor.scrollToCursor()
  editor.updateTargetColumn()

proc paste(editor: TextEditor, pasteRight: bool = false, inclusiveEnd: bool = false, register: string = "") {.exposeActive(editorContext).} =
  # debugf"vimPaste {register}, lines: {yankedLines}, pasteRight: {pasteRight}"
  let register = if register == "vim.default-register":
    getVimDefaultRegister()
  else:
    register

  editor.addNextCheckpoint ws"insert"

  var selections = editor.getSelections

  if yankedLines and $editor.mode == "vim-new.normal":
    selections = editor.multiMove(selections, ws"line", 1, wrap = false, includeEol = true).mapIt(it.last.toSelection).stackWitList()
    selections = editor.edit(selections, @@[ws("\n")], inclusive=false).mapIt(it.last.toSelection).stackWitList()
  elif pasteRight:
    selections = editor.multiMove(selections, ws"column", 1, false, true).mapIt(it.last.toSelection).stackWitList()

  editor.setMode "vim-new.normal"
  editor.paste selections, register.stackWitString, inclusiveEnd=inclusiveEnd

proc toggleCase(editor: TextEditor, moveCursorRight: bool) {.exposeActive(editorContext).} =
  var editTexts: seq[WitString]

  let content = editor.content
  for s in editor.selections:
    let text = content.sliceSelection(s, inclusive=true).text
    var newText = newStringOfCap(text.len)
    for r in text.toOpenArray.runes:
      if r.isLower:
        newText.add $r.toUpper
      else:
        newText.add $r.toLower
    editTexts.add newText.stackWitString()

  editor.addNextCheckpoint ws"insert"
  let oldSelections = editor.selections
  discard editor.edit(editor.selections, editTexts.stackWitList(), inclusive=true)
  editor.setSelections oldSelections.mapIt(it.first.toSelection).stackWitList()

  editor.setMode "vim-new.normal"

  if moveCursorRight:
    editor.moveCursorColumn(1, wrap=false, includeEol=editor.vimState.cursorIncludeEol)
    editor.updateTargetColumn()

# proc vimCloseCurrentViewOrQuit() {.exposeActive(editorContext, "vim-close-current-view-or-quit").} =
#   let openEditors = getNumVisibleViews() + getNumHiddenViews()
#   if openEditors == 1:
#     plugin_runtime.quit()
#   else:
#     closeActiveView()

proc indent(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint ws"insert"
  editor.indent(1)

proc unindent(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint ws"insert"
  editor.indent(-1)

proc addCursorAbove(editor: TextEditor) {.exposeActive(editorContext).} =
  var selections = @(editor.getSelections.toOpenArray)
  let newSelections = editor.multiMove(@@[selections.last], ws"line-up", 0, wrap=false, includeEol=false).mapIt(it.last.toSelection)
  selections.add newSelections
  editor.setSelections selections
  editor.scrollToCursor()

proc addCursorBelow(editor: TextEditor) {.exposeActive(editorContext).} =
  var selections = @(editor.getSelections.toOpenArray)
  let newSelections = editor.multiMove(@@[selections.last], ws"line-down", 0, wrap=false, includeEol=false).mapIt(it.last.toSelection)
  selections.add newSelections
  editor.setSelections selections
  editor.scrollToCursor()

proc enter(editor: TextEditor) {.exposeActive(editorContext).} =
  debugf"vim.enter"
  editor.addNextCheckpoint ws"insert"
  editor.insertText ws("\n"), autoIndent=true

proc yankLine(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.vimState.selectLines = true
  editor.selectLine()
  editor.yankSelection()
  editor.vimState.selectLines = false

proc deleteLine(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.vimState.selectLines = true
  let oldSelections = editor.getSelections
  editor.selectLine()
  editor.deleteSelection(true, oldSelections=some(@oldSelections))
  editor.vimState.selectLines = false

proc changeLine(editor: TextEditor) {.exposeActive(editorContext).} =
  let oldSelections = editor.getSelections
  editor.selectLine()
  editor.changeSelection(true, oldSelections=some(@oldSelections))

proc deleteToLineEnd(editor: TextEditor) {.exposeActive(editorContext).} =
  let oldSelections = editor.getSelections
  let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, ws"line", 1, wrap = false, includeEol = true)):
    (it1.last, it2.last).toSelection
  editor.setSelections selections
  editor.deleteSelection(true, oldSelections=some(@oldSelections))
  editor.vimState.selectLines = false

proc changeToLineEnd(editor: TextEditor) {.exposeActive(editorContext).} =
  let oldSelections = editor.getSelections
  let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, ws"line", 1, wrap = false, includeEol = true)):
    (it1.last, it2.last).toSelection
  editor.setSelections selections
  editor.changeSelection(true, oldSelections=some(@oldSelections))
  editor.vimState.selectLines = false

proc yankToLineEnd(editor: TextEditor) {.exposeActive(editorContext).} =
  let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, ws"line", 1, wrap = false, includeEol = true)):
    (it1.last, it2.last).toSelection
  editor.setSelections selections
  editor.yankSelection()

proc moveFileStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  let which = getSetting[sca.SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  editor.setSelection (count - 1, 0).toSelection(editor.getSelection, which)
  editor.moveFirst "line-no-indent"
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc moveFileEnd(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  let line = if count == 0: editor.content.lines.int - 1 else: count - 1
  let which = getSetting[sca.SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
  var newSelection = (line, 0).toSelection(editor.getSelection, which)
  if newSelection == editor.getSelection:
    let lineLen = editor.lineLength(line.int32).int
    editor.setSelection (line, lineLen).toSelection(editor.getSelection, which)
  else:
    editor.setSelection newSelection
    editor.moveFirst "line-no-indent"
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc moveToMatching(editor: TextEditor) {.exposeActive(editorContext).} =
  # todo: pass as parameter
  let mode = $editor.mode
  let which = if mode == "vim-new.visual" or mode == "vim-new.visual-line":
    sca.SelectionCursor.Last
  else:
    sca.SelectionCursor.Both

  let content = editor.content

  editor.setSelections editor.selections.mapIt(block:
    let c = content.charAt(it.last)
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

    let selection = editor.applyMove(it, stackWitString(&"surround \"{open}\" \"{close}\" false"), 0, wrap=false, includeEol=true)[0]
    # let selection = editor.vimMotionSurround(it.last, 0, open, close, false)

    if last:
      selection.last.toSelection(it, which)
    else:
      selection.first.toSelection(it, which)
  ).stackWitList()

  editor.scrollToCursor()
  editor.updateTargetColumn()

proc moveToMatchingOrFileOffset(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  if count == 0:
    editor.moveToMatching()
  else:
    debugf"not implemented: moveToMatchingOrFileOffset {count}"
    # todo
#     let line = clamp((count * editor.lineCount) div 100, 0, editor.lineCount - 1)
#     let which = getSetting[sca.SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), sca.SelectionCursor.Both)
#     editor.setSelection (line, 0).toSelection(editor.selection, which)
#     editor.moveFirst "line-no-indent"
#     editor.scrollToCursor()
#     editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc scrollLineToTopAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  if editor.getCommandCount != 0:
    editor.setSelection (editor.getCommandCount.int, 0).toCursor.toSelection
  editor.setSelections editor.multiMove(editor.selections, ws"line-no-indent", 1, wrap = false, includeEol = editor.vimState.cursorIncludeEol).mapIt(it.first.toSelection).stackWitList()
  editor.setCursorScrollOffset editor.selections.last.last, getVimLineMargin()

proc scrollLineToTop(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  if editor.getCommandCount != 0:
    editor.setSelection (editor.getCommandCount, editor.selections.last.last.column).toSelection
  editor.setCursorScrollOffset editor.selections.last.last, getVimLineMargin()

proc centerLineAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  if editor.getCommandCount != 0:
    editor.setSelection (editor.getCommandCount.int, 0).toCursor.toSelection
  editor.setSelections editor.multiMove(editor.selections, ws"line-no-indent", 1, wrap = false, includeEol = editor.vimState.cursorIncludeEol).mapIt(it.first.toSelection).stackWitList()
  editor.scrollToCursor(ScrollBehaviour.CenterAlways.some, 0.5)

proc centerLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  editor.scrollToCursor(ScrollBehaviour.CenterAlways.some, 0.5)

proc scrollLineToBottomAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  if editor.getCommandCount != 0:
    editor.setSelection (editor.getCommandCount.int, 0).toCursor.toSelection
  editor.setSelections editor.multiMove(editor.selections, ws"line-no-indent", 1, wrap = false, includeEol = editor.vimState.cursorIncludeEol).mapIt(it.first.toSelection).stackWitList()
  editor.setCursorScrollOffset editor.selections.last.last, (editor.getVisibleLineCount().float - getVimLineMargin())

proc scrollLineToBottom(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  if editor.getCommandCount != 0:
    editor.setSelection (editor.getCommandCount, editor.selections.last.last.column).toSelection
  editor.setCursorScrollOffset editor.selections.last.last, (editor.getVisibleLineCount().float - getVimLineMargin())

proc insertMode(editor: TextEditor, move: string = "") {.exposeActive(editorContext).} =
  # debugf"insertMode '{move}'"
  case move
  of "right":
    editor.setSelections editor.multiMove(editor.selections, ws"column", 1, wrap = false, includeEol = true).mapIt(it.last.toSelection).stackWitList()
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

proc insertLineBelow(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setSelections editor.multiMove(editor.getSelections, ws"line", 0, wrap=false, includeEol=true).mapIt(it.last.toSelection)
  editor.addNextCheckpoint ws"insert"
  editor.insertText ws("\n"), autoIndent=true
  editor.setMode "vim-new.insert"

proc insertLineAbove(editor: TextEditor, move: string = "") {.exposeActive(editorContext).} =
  editor.setSelections editor.multiMove(editor.getSelections, ws"line", 0, wrap=false, includeEol=true).mapIt(it.first.toSelection)
  editor.addNextCheckpoint ws"insert"
  editor.insertText ws("\n"), autoIndent=false
  editor.moveDirection("line-up", 1, 1, false, false)
  editor.setMode "vim-new.insert"

proc setSearchQueryFromWord(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setSelection editor.setSearchQueryFromMove(ws"word", 1, prefix=ws(r"\b"), suffix=ws(r"\b")).first.toSelection

proc setSearchQueryFromSelection(editor: TextEditor) {.exposeActive(editorContext).} =
  let content = editor.content.sliceSelection(editor.getSelection, inclusive=true)
  discard editor.setSearchQuery(content.text, escapeRegex=true, prefix=ws"", suffix=ws"")
  editor.setSelection editor.getSelection.first.toSelection
  editor.normalMode()

proc nextSearchResult(editor: TextEditor, count: int = 0) {.exposeActive(editorContext).} =
  let selections = editor.getSelections
  let next = editor.multiMove(selections, ws"next-search-result", count, wrap = true, includeEol=false)
  let newSelections = mergeSelections(selections, next):
    (it1.first, it2.first).toSelection

  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc prevSearchResult(editor: TextEditor, count: int = 0) {.exposeActive(editorContext).} =
  let selections = editor.getSelections
  let prev = editor.multiMove(selections, ws"prev-search-result", count, wrap = true, includeEol=false)
  let newSelections = mergeSelections(selections, prev):
    (it1.first, it2.first).toSelection

  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc gotoNextChange(editor: TextEditor, count: int = 0) {.exposeActive(editorContext).} =
  let selections = editor.getSelections
  let next = editor.multiMove(selections, ws"next-change", count, wrap = true, includeEol=false)
  let newSelections = mergeSelections(selections, next):
    (it1.first, it2.first).toSelection

  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc gotoPrevChange(editor: TextEditor, count: int = 0) {.exposeActive(editorContext).} =
  let selections = editor.getSelections
  let prev = editor.multiMove(selections, ws"prev-change", count, wrap = true, includeEol=false)
  let newSelections = mergeSelections(selections, prev):
    (it1.first, it2.first).toSelection

  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc gotoNextDiagnostic(editor: TextEditor, count: int = 0) {.exposeActive(editorContext).} =
  let selections = editor.getSelections
  let next = editor.multiMove(selections, ws"next-diagnostic", count, wrap = true, includeEol=false)
  let newSelections = mergeSelections(selections, next):
    (it1.first, it2.first).toSelection

  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc gotoPrevDiagnostic(editor: TextEditor, count: int = 0) {.exposeActive(editorContext).} =
  let selections = editor.getSelections
  let prev = editor.multiMove(selections, ws"prev-diagnostic", count, wrap = true, includeEol=false)
  let newSelections = mergeSelections(selections, prev):
    (it1.first, it2.first).toSelection

  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc openSearchBar(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.openSearchBar(ws"", scrollToPreview=true, selectResult=true)

proc exitCommandLine() {.command.} =
  if activeTextEditor({IncludeCommandLine}).getSome(editor):
    if editor.mode == ws"vim-new.normal":
      discard runCommand(ws"exit-command-line", ws"")
      return

    editor.setMode("vim-new.normal")

proc exitPopup() {.command.} =
  if activeTextEditor({IncludePopups}).getSome(editor) and editor.mode != ws"vim-new.normal":
    editor.setMode("vim-new.normal")
    return

  discard runCommand(ws"close-active-view", ws"")

proc selectWordOrAddCursor(editor: TextEditor) {.exposeActive(editorContext).} =
  let selections = editor.selections
  if selections.len == 1:
    var selection = editor.setSearchQueryFromMove(ws"word", 1, prefix=ws(r"\b"), suffix=ws(r"\b"))
    selection.last.column -= 1
    editor.setSelection selection
  else:
    let next = editor.multiMove(@@[selections.last], ws"next-search-result", 0, wrap = true, includeEol=false).last
    let newSelections = @selections & next
    editor.setSelections @@newSelections
    editor.scrollToCursor()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

  editor.setMode("vim-new.visual")

proc moveLastSelectionToNextSearchResult(editor: TextEditor) {.exposeActive(editorContext).} =
  let selections = editor.selections
  if selections.len == 1:
    var selection = editor.setSearchQueryFromMove(ws"word", 1, prefix=ws(r"\b"), suffix=ws(r"\b"))
    selection.last.column -= 1
    editor.setSelection selection
  else:
    let next = editor.multiMove(@@[selections.last], ws"next-search-result", 0, wrap = true, includeEol=false).last
    let newSelections = selections.toOpenArray[0..^2] & next
    editor.setSelections @@newSelections
    editor.scrollToCursor()
    editor.setNextSnapBehaviour(MinDistanceOffscreen)
    editor.updateTargetColumn()

  editor.setMode("vim-new.visual")

proc setSearchQueryOrAddCursor(editor: TextEditor) {.exposeActive(editorContext).} =
  let selections = editor.selections
  debugf"setSearchQueryOrAddCursor {selections}, {selections.last}"
  if selections.len == 1:
    let selectedText = editor.content.sliceSelection(selections.last, inclusive=true)
    let textEscaped = ($selectedText.text).escapeRegex
    let currentSearchQuery = $editor.getSearchQuery()
    debugf"{selectedText.bytes}, '{selectedText.text}' -> '{textEscaped}' -> '{currentSearchQuery}'"
    if textEscaped != currentSearchQuery and r"\b" & textEscaped & r"\b" != currentSearchQuery:
      if editor.setSearchQuery(selectedText.text, escapeRegex=true, prefix=ws"", suffix=ws""):
        return

  let next = editor.multiMove(@@[selections.last], ws"next-search-result", 0, wrap = true, includeEol=false).last
  let newSelections = @selections & next
  editor.setSelections @@newSelections
  editor.scrollToCursor()
  editor.updateTargetColumn()

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
#     debugf"Failed to save vim editor states"

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

proc deleteWordBack(editor: TextEditor) {.exposeActive(editorContext).} =
  let wordSelections = editor.multiMove(editor.selections, ws"vim.word-back", 1, wrap = false, includeEol = true)
  let selectionsToDelete = mergeSelections(wordSelections, editor.selections, (it1.first, it2.last).toSelection)
  editor.setSelections editor.edit(selectionsToDelete.stackWitList(), @@[ws""], inclusive = false)
  editor.autoShowCompletions()

proc deleteLineBack(editor: TextEditor) {.exposeActive(editorContext).} =
  let lineSelections = editor.selections.mapIt ((it.last.line.int, 0).toCursor, it.last).toSelection
  editor.setSelections editor.edit(lineSelections.stackWitList(), @@[ws""], inclusive = false)
  editor.autoShowCompletions()

proc includeSelectionEnd*(self: TextEditor, res: Selection, includeAfter: bool = true): Selection =
  result = res
  if not includeAfter:
    result = (res.first, self.applyMove(res.last, "column", -1, wrap = false, includeEol = true).last).toSelection

proc surround(editor: TextEditor, text: string) {.exposeActive(editorContext).} =
  let (left, right) = case text
  of "(", ")": (ws"(", ws")")
  of "{", "}": (ws"{", ws"}")
  of "[", "]": (ws"[", ws"]")
  of "<", ">": (ws"<", ws">")
  else:
    let text = text.stackWitString()
    (text, text)

  let selections = editor.selections.mapIt(it.normalized).stackWitList()
  let rightCursors = editor.multiMove(selections, ws"column", 1, wrap = false, includeEol = true)

  var insertSelections = newSeq[Selection](selections.len * 2)
  var insertTexts = newSeq[WitString](selections.len * 2)
  for i, s in selections:
    insertSelections[i * 2 + 0] = s.first.toSelection
    insertSelections[i * 2 + 1] = rightCursors[i].last.toSelection
    insertTexts[i * 2 + 0] = left
    insertTexts[i * 2 + 1] = right

  editor.addNextCheckpoint ws"insert"
  let newSelections = editor.edit(insertSelections.stackWitList(), insertTexts.stackWitList(), inclusive = false)
  if newSelections.len mod 2 != 0:
    return

  let newSelectionsInclusive = collect:
    for i in 0..<newSelections.len div 2:
      editor.includeSelectionEnd((newSelections[i * 2].first, newSelections[i * 2 + 1].last), false)
  editor.setSelections newSelectionsInclusive.stackWitList()

proc toggleLineComment(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint ws"insert"
  text_editor.toggleLineComment(editor)

proc startMacro(editor: TextEditor, name: string) {.exposeActive(editorContext).} =
  if isReplayingCommands() or isRecordingCommands(getCurrentMacroRegister().stackWitString):
    return
  setSetting("editor.current-macro-register", name)
  let name = name.stackWitString
  setRegisterText(ws"", name)
  startRecordingCommands(name)

proc playMacro(editor: TextEditor, name: string) {.exposeActive(editorContext).} =
  let register = if name == "@":
    getCurrentMacroRegister()
  else:
    name

  let text = getRegisterText(register.stackWitString)
  replayCommands(register.stackWitString)

proc stopMacro(editor: TextEditor) {.exposeActive(editorContext).} =
  if isReplayingCommands():
    return
  let register = getCurrentMacroRegister().stackWitString
  if isReplayingCommands() or not isRecordingCommands(register):
    return
  stopRecordingCommands(register)

proc invertSelections(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setSelections editor.selections.mapIt((it.last, it.first).toSelection).stackWitList()
  editor.scrollToCursor()
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc invertLineSelections(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setSelections editor.selections.mapIt((it.last, it.first).toSelection).stackWitList()
  editor.scrollToCursor()
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc reverseSelections(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.setSelections editor.selections.toOpenArray.reversed().stackWitList()
  editor.scrollToCursor()
  editor.updateTargetColumn()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)

proc joinLines(editor: TextEditor, reduceSpace: bool) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint ws"insert"
  let content = editor.content
  if reduceSpace:
    var insertTexts: seq[WitString]
    let selectionsToDelete = editor.selections.mapIt(block:
      let lineLen = content.lineLength(it.last.line).int
      if lineLen == 0 or content.charAt((it.last.line.int, lineLen - 1).toCursor) == ' ':
        insertTexts.add ws""
      else:
        insertTexts.add ws" "
      var nextLineIndent = editor.applyMove((it.last.line.int + 1, 0).toSelection, ws"line-no-indent", 0, wrap=false, includeEol=true)
      ((it.last.line.int, lineLen).toCursor, (it.last.line + 1, nextLineIndent[0].first.column).toCursor).toSelection
    )
    editor.setSelections editor.edit(selectionsToDelete.stackWitList(), insertTexts.stackWitList(), inclusive=false).mapIt(it.first.toSelection).stackWitList()
  else:
    let selectionsToDelete = editor.selections.mapIt(block:
      let lineLen = content.lineLength(it.last.line).int
      ((it.last.line.int, lineLen).toCursor, (it.last.line.int + 1, 0).toCursor).toSelection
    )
    editor.setSelections editor.edit(selectionsToDelete.stackWitList(), @@[ws""], inclusive=false).mapIt(it.first.toSelection).stackWitList()

proc moveToColumn(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
  editor.setSelections editor.selections.mapIt((it.last.line.int, count).toSelection)
  editor.scrollToCursor()
  editor.updateTargetColumn()

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

proc growSelection(editor: TextEditor, amount: int = 1) {.exposeActive(editorContext).} =
  editor.setSelections editor.multiMove(editor.selections, ws"grow", amount, wrap = true, includeEol = true)
  editor.scrollToCursor()
  editor.setNextSnapBehaviour(MinDistanceOffscreen)
  editor.updateTargetColumn()

proc evaluateSelection(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.evaluateExpressions(editor.selections, true, prefix = ws"", suffix = ws"", addSelectionIndex = false)

proc incrementSelection(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.evaluateExpressions(editor.selections, true, prefix = ws"", suffix = ws"+1", addSelectionIndex = false)

proc decrementSelection(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.evaluateExpressions(editor.selections, true, prefix = ws"", suffix = ws"-1", addSelectionIndex = false)

proc incrementSelectionByIndex(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.evaluateExpressions(editor.selections, true, prefix = ws"", suffix = ws"", addSelectionIndex = true)

proc increment(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.setSelections editor.multiMove(editor.selections, ws"number", 1, wrap = false, includeEol = true)
  editor.evaluateExpressions(editor.selections, false, prefix = ws"", suffix = ws"+1", addSelectionIndex = false)
  editor.setSelections editor.multiMove(editor.selections, ws"column", -1, wrap = false, includeEol = true).mapIt(it.last.toSelection).stackWitList()

proc decrement(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.setSelections editor.multiMove(editor.selections, ws"number", 1, wrap = false, includeEol = true)
  editor.evaluateExpressions(editor.selections, false, prefix = ws"", suffix = ws"-1", addSelectionIndex = false)
  editor.setSelections editor.multiMove(editor.selections, ws"column", -1, wrap = false, includeEol = true).mapIt(it.last.toSelection).stackWitList()

proc incrementByIndex(editor: TextEditor) {.exposeActive(editorContext).} =
  editor.addNextCheckpoint(ws"insert")
  editor.setSelections editor.multiMove(editor.selections, ws"number", 1, wrap = false, includeEol = true)
  editor.evaluateExpressions(editor.selections, false, prefix = ws"", suffix = ws"", addSelectionIndex = true)
  editor.setSelections editor.multiMove(editor.selections, ws"column", -1, wrap = false, includeEol = true).mapIt(it.last.toSelection).stackWitList()

proc replaceInputHandler(editor: TextEditor, input: string) {.exposeActive(editorContext).} =
  editor.vimReplace(input)

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
#           debugf"Failed to restore marks for {editor}"
#   scriptSetCallback("after-restore-session", afterRestoreSessionHandle)

#   let beforeSaveAppStateHandle = addCallback proc(args: JsonNode): JsonNode =
#     vimSaveState()
#   scriptSetCallback("before-save-app-state", beforeSaveAppStateHandle)
