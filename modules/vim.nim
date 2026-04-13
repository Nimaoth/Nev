#use command_component, snippet_component, search_component
import platform/platform

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import std/[strformat, json, tables, macros, genasts, streams, sequtils, sets, colors, algorithm, unicode, sugar]
  import misc/[util, custom_unicode, myjsonutils, id, wrap, custom_regex, rope_utils, custom_async, custom_logger]
  import nimsumtree/[buffer, rope, clock, arc]
  import scripting_api
  import input_api
  import service, config_provider, layout
  import document_editor, document, text_editor_component, text_component, move_component, command_component, snippet_component
  import config_component, command_service, search_component, decoration_component
  import register

  logCategory "vim"

  type TextEditor = object
    editor: DocumentEditor
    edit: TextEditorComponent

  proc initTextEditor(editor: DocumentEditor): TextEditor =
    TextEditor(
      editor: editor,
      edit: editor.getTextEditorComponent().get,
    )

  proc fromJsonHook*(val: var TextEditor, jsonNode: JsonNode, opt = Joptions()) {.raises: [ValueError].} =
    if jsonNode.kind == JInt:
      let editor = getServiceChecked(DocumentEditorService).getEditor(jsonNode.getInt.EditorIdNew)
      if editor.isSome:
        val = initTextEditor(editor.get)
        return
      raise newException(ValueError, &"Invalid editor id '{jsonNode}' for TextEditor")
    raise newException(ValueError, &"Failed to convert '{jsonNode}' to TextEditor")

  proc commands(self: TextEditor): CommandComponent =
    self.editor.getCommandComponent().get

  proc moves(self: TextEditor): MoveComponent =
    self.editor.getMoveComponent().get

  proc last*[T](list: seq[T]): lent T =
    assert list.len > 0
    return list[list.len - 1]

  proc `==`*[T](a, b: seq[T]): bool =
    if a.len != b.len:
      return false
    return equalMem(a.data, b.data, a.len)

  proc `==`*(a, b: string): bool =
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
    marks: Table[string, seq[(Anchor, Anchor)]]
    unresolvedMarks: Table[string, seq[Selection]]

  var editorStates: Table[EditorId, EditorVimState]

  const editorContext = "editor.text"

  type IdentifierCase = enum Camel, Pascal, Kebab, Snake, ScreamingSnake

  proc startRecordingKeys*(register: string) = getServiceChecked(Registers).startRecordingKeys(register)
  proc stopRecordingKeys*(register: string) = getServiceChecked(Registers).stopRecordingKeys(register)
  proc startRecordingCommands*(register: string) = getServiceChecked(Registers).startRecordingCommands(register)
  proc stopRecordingCommands*(register: string) = getServiceChecked(Registers).stopRecordingCommands(register)
  proc isReplayingCommands*(): bool = getServiceChecked(Registers).isReplayingCommands()
  proc isReplayingKeys*(): bool = getServiceChecked(Registers).isReplayingKeys()
  proc isRecordingCommands*(register: string): bool = getServiceChecked(Registers).isRecordingCommands(register)

  proc getSetting*[T](name: string, default: T): T = getServiceChecked(ConfigService).runtime.get(name, default)
  proc setSetting*[T](name: string, value: T) = getServiceChecked(ConfigService).runtime.set(name, value)

  proc getSetting*[T](editor: TextEditor, name: string, default: T): T = editor.editor.getConfigComponent().get.get(name, default)
  proc setSetting*[T](editor: TextEditor, name: string, value: T) = editor.editor.getConfigComponent().get.set(name, value)

  proc setRegisterText(text: string, register: string = "") {.inline.} = getServiceChecked(Registers).setRegisterText(text, register)
  proc getRegisterText(register: string): string =
    var res: Register
    discard getServiceChecked(Registers).getRegisterAsync(register, res.addr).waitFor()
    case res.kind
    of RegisterKind.Text:
      res.text
    of RegisterKind.Rope:
      $res.rope

  proc id(editor: TextEditor): EditorId =
    editor.editor.id.uint64

  proc setSelection(editor: TextEditor, selection: Selection) =
    editor.edit.selection = selection.toRange

  proc `selection=`(editor: TextEditor, selection: Selection) =
    editor.edit.selection = selection.toRange

  proc setSelections(editor: TextEditor, selections: sink seq[Selection]) =
    editor.edit.selections = selections.mapIt(it.toRange)

  proc `selections=`(editor: TextEditor, selections: sink seq[Selection]) =
    editor.edit.selections = selections.mapIt(it.toRange)

  proc getSelection(editor: TextEditor): Selection =
    return editor.edit.selection.toSelection

  proc selection(editor: TextEditor): Selection =
    return editor.edit.selection.toSelection

  proc getSelections(editor: TextEditor): seq[Selection] =
    return editor.edit.selections.mapIt(it.toSelection)

  proc selections(editor: TextEditor): seq[Selection] =
    return editor.edit.selections.mapIt(it.toSelection)

  proc lineLength(editor: TextEditor, line: int): int =
    if editor.editor.currentDocument.isNotNil:
      return editor.editor.currentDocument.getTextComponent().get.content.lineLen(line)
    return 0

  proc lineCount(editor: TextEditor): int =
    if editor.editor.currentDocument.isNotNil:
      return editor.editor.currentDocument.getTextComponent().get.content.lines
    return 1

  proc command(editor: TextEditor, command: string, args: string): string =
    editor.commands.executeCommand(command & " " & args)
    return ""

  proc mode(editor: TextEditor): string =
    let modes = editor.editor.getConfigComponent().get.get("text.modes", seq[string])
    if modes.len > 0:
      return modes.last
    return ""

  proc modes(editor: TextEditor): seq[string] =
    editor.editor.getConfigComponent().get.get("text.modes", seq[string])

  proc setMode(editor: TextEditor, mode: string) =
    discard editor.command("set-mode", $mode.toJson)

  proc getUsage(editor: TextEditor): string =
    if editor.editor.currentDocument.isNotNil:
      return editor.editor.currentDocument.usage
    return ""

  proc getRevision(editor: TextEditor): int =
    if editor.editor.currentDocument.isNotNil:
      return editor.editor.currentDocument.getTextComponent().get.buffer.ownVersion.int
    return 0

  proc updateTargetColumn(editor: TextEditor) =
    editor.edit.updateTargetColumn(editor.edit.selection.b)

  proc scrollToCursor(editor: TextEditor, behaviour = ScrollBehaviour.none, offset: float = 0.5) =
    if behaviour == ScrollBehaviour.CenterAlways.some:
      editor.edit.scrollToCursor(editor.selection.last.toPoint, center = true)
    elif behaviour == ScrollBehaviour.CenterOffscreen.some:
      editor.edit.scrollToCursor(editor.selection.last.toPoint, centerOffscreen = true)
    else:
      editor.edit.scrollToCursor(editor.selection.last.toPoint)

  proc centerCursor(editor: TextEditor) =
    discard editor.command("center-cursor", "")

  proc setCursorScrollOffset(editor: TextEditor, cursor: Cursor, offset: float) =
    editor.edit.setCursorScrollOffset(cursor.toPoint, offset)

  proc undo(editor: TextEditor, checkpoint: string = "") =
    discard editor.command("undo", "")

  proc redo(editor: TextEditor, checkpoint: string = "") =
    discard editor.command("redo", "")

  let copyHighlightId = newId()

  proc highlightTempAsync(editor: TextEditor, ranges: seq[Range[Point]]) {.async.} =
    if editor.editor.getDecorationComponent().getSome(decos):
      for range in ranges:
        decos.addCustomHighlight(copyHighlightId, range, "editor.findMatchBackground")
      try:
        await sleepAsync(150.milliseconds)
      except CatchableError:
        discard
      decos.clearCustomHighlights(copyHighlightId)

  proc highlightTemp(editor: TextEditor, ranges: seq[Range[Point]]) =
    if editor.editor.getConfigComponent().get.get("ui.highlight-yank", true):
      asyncSpawn editor.highlightTempAsync(ranges)

  proc copy(editor: TextEditor, register: string = "", inclusiveEnd: bool, highlight: bool = false) =
    if highlight:
      let selections = if inclusiveEnd:
        editor.moves.applyMove(editor.edit.selections, "(column 1) (join)", wrap = false)
      else:
        editor.edit.selections
      editor.highlightTemp(selections)
    discard editor.command("copy", &"{register.toJson} {inclusiveEnd}")

  proc paste(editor: TextEditor, selections: sink seq[Selection], register: string = "", inclusiveEnd: bool) =
    discard editor.command("paste-at", &"{selections.toJson} {register.toJson} {inclusiveEnd}")

  proc insertText(editor: TextEditor, text: string, autoIndent: bool) =
    discard editor.command("insert-text", &"{text.toJson} {autoIndent}")

  proc getVisibleLineCount(editor: TextEditor): int =
    let r = editor.edit.visibleTextRange()
    return r.b.row.int - r.a.row.int

  proc autoShowCompletions(editor: TextEditor) =
    discard editor.command("auto-show-completions", "")

  proc hideCompletions(editor: TextEditor) =
    discard editor.command("hide-completions", "")

  proc getCommandCount(editor: TextEditor): int =
    return editor.editor.getCommandComponent().get.getCommandCount()

  proc evaluateExpressions(editor: TextEditor, selections: sink seq[Selection], inclusiveEnd: bool = false, prefix = "", suffix = "", addSelectionIndex = false) =
    discard editor.command("evaluate-expressions", &"{selections.toJson} {inclusiveEnd} {prefix.toJson} {suffix.toJson} {addSelectionIndex}")

  proc createAnchors(editor: TextEditor, selections: sink seq[Selection]): seq[(Anchor, Anchor)] =
    if editor.editor.currentDocument.isNotNil:
      let snapshot {.cursor.} = editor.editor.currentDocument.getTextComponent().get.buffer.snapshot()
      return selections.mapIt (snapshot.anchorAfter(it.first.toPoint), snapshot.anchorBefore(it.last.toPoint))
    return @[]

  proc resolveAnchors(editor: TextEditor, anchors: sink seq[(Anchor, Anchor)]): seq[Selection] =
    if editor.editor.currentDocument.isNotNil:
      let snapshot {.cursor.} = editor.editor.currentDocument.getTextComponent().get.buffer.snapshot()
      return anchors.mapIt (it[0].summaryOpt(Point, snapshot).get(Point()), it[1].summaryOpt(Point, snapshot).get(Point())).toSelection
    return @[]

  proc runCommand(command: string, args: string = ""): string =
    getServiceChecked(CommandService).executeCommand(command & " " & args).get("")

  proc activeTextEditor*(includeCommandLine = false, includePopups = false): Option[TextEditor] =
    if getServiceChecked(LayoutService).getActiveEditor(includeCommandLine, includePopups).getSome(editor):
      return initTextEditor(editor).some
    return TextEditor.none

  proc addNextCheckpoint(editor: TextEditor, checkpoint: string) =
    editor.edit.startTransaction()

  proc edit(editor: TextEditor, selections: sink seq[Selection], texts: seq[string], inclusive = false): seq[Selection] =
    let ranges = selections.mapIt(it.toRange)
    editor.edit.edit(ranges, editor.edit.selections, texts, inclusiveEnd = inclusive).mapIt(it.toSelection)

  proc edit(editor: TextEditor, selections: sink seq[Selection], oldSelections: sink seq[Selection], texts: seq[string], inclusive = false): seq[Selection] =
    let ranges = selections.mapIt(it.toRange)
    let oldRanges = oldSelections.mapIt(it.toRange)
    editor.edit.edit(ranges, oldRanges, texts, inclusiveEnd = inclusive).mapIt(it.toSelection)

  proc content(editor: TextEditor): Rope =
    if editor.editor.currentDocument.isNotNil:
      return editor.editor.currentDocument.getTextComponent().get.content
    return Rope.new("")

  proc applyMove(editor: TextEditor, selection: Selection, move: string, count = 0, wrap = true, includeEol = true): Selection =
    return editor.moves.applyMove(selection.toRange, move, count, includeEol, wrap).toSelection

  proc applyMove(editor: TextEditor, cursor: Cursor, move: string, count = 0, wrap = true, includeEol = true): Selection =
    return editor.moves.applyMove(cursor.toSelection.toRange, move, count, includeEol, wrap).toSelection

  proc multiMove(editor: TextEditor, selections: sink seq[Selection], move: string, count = 0, wrap = true, includeEol = true): seq[Selection] =
    return editor.moves.applyMove(selections.mapIt(it.toRange), move, count, includeEol, wrap).mapIt(it.toSelection)

  proc setSearchQuery(editor: TextEditor, query: string, escapeRegex: bool, prefix: string = "", suffix: string = ""): bool =
    return editor.editor.getSearchComponent().get.setSearchQuery(query, escapeRegex, prefix, suffix)

  proc setSearchQueryFromMove(editor: TextEditor, move: string, count: int, prefix: string, suffix: string): Selection =
    let selection = editor.applyMove(editor.selection.last, move, count)
    let searchText = $editor.content[selection.toRange]
    discard editor.setSearchQuery(searchText, escapeRegex=true, prefix, suffix)
    return selection

  proc getSearchQuery(editor: TextEditor): string =
    return editor.editor.getSearchComponent().get.getSearchQuery()

  proc openSearchBar(editor: TextEditor, query: string, scrollToPreview: bool, selectResult: bool) =
    editor.editor.getSearchComponent().get.openSearchBar(query, scrollToPreview, selectResult)

  proc moveCursorColumn(editor: TextEditor, amount: int, wrap: bool = false, includeEol: bool = true) =
    editor.setSelections editor.multiMove(editor.selections, "column", 1, wrap, includeEol).mapIt(it.last.toSelection)

  proc moveCursorColumn(editor: TextEditor, selections: seq[Selection], amount: int, wrap = false, includeEol = true): seq[Selection] =
    editor.multiMove(selections, "column", 1, wrap, includeEol).mapIt(it.last.toSelection)

  proc moveCursorLine(editor: TextEditor, amount: int, includeEol: bool = true) =
    editor.setSelections editor.multiMove(editor.selections, "line-down", amount, false, includeEol).mapIt(it.last.toSelection)

  proc sliceSelection(rope: Rope, selection: Selection, inclusive = false): RopeSlice[Point] =
    let selection = if inclusive:
      (selection.first, rope.clipPoint(point(selection.last.line, selection.last.column + 1), Bias.Right).toCursor)
    else:
      selection
    rope[selection.toRange]

  proc slice(rope: Rope, a, b: int): RopeSlice[Point] =
    rope[rope.offsetToPoint(a)...rope.offsetToPoint(b)]

  proc slice(rope: RopeSlice[Point], a, b: int): RopeSlice[Point] =
    let sliceByteStart = rope.rope.pointToOffset(rope.range.a)
    let pointA = (rope.rope.offsetToPoint(sliceByteStart + a) - rope.range.a).toPoint
    let pointB = (rope.rope.offsetToPoint(sliceByteStart + b) - rope.range.a).toPoint
    rope[pointA...pointB]

  proc recordCurrentCommand(editor: TextEditor, registers: seq[string] = @[]) = editor.commands.recordCurrentCommand(registers)

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

  var vimCommands: seq[Command] = newSeqOfCap[Command](100)
  proc defineCommand(name: string, active: bool, docs: string, params: seq[(string, string)], returnType: string, context: string,
      impl: proc(data: uint64, argsString: string): string {.cdecl, raises: [CatchableError].}) =
    let vimCommands = ({.gcsafe.}: vimCommands.addr)
    vimCommands[].add Command(
      namespace: "",
      name: "vim." & name,
      description: docs,
      parameters: params,
      returnType: returnType,
      signature: "",
      execute: proc(args: string): string {.gcsafe, raises: [CatchableError].} =
        try:
          if active:
            let layout = getServiceChecked(LayoutService)
            let activeEditor = layout.getActiveEditor()
            if activeEditor.isSome:
              {.gcsafe.}:
                return impl(activeEditor.get.id.uint64, args)
          else:
            {.gcsafe.}:
              return impl(0, args)
        except CatchableError:
          discard
    )

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
        defineCommand(name,
          active = inActive,
          docs = documentationStr,
          params = @[],
          returnType = inReturnType,
          context = inContext):
          proc(editor: uint64, argsString: string): string {.cdecl.} =
            var args = newJArray()
            try:
              if inActive:
                args.add(editor.toJson)
              for a in newStringStream($argsString).parseJsonFragments():
                args.add a
              let res = jsonWrapperName(args)
              return $res
            except CatchableError as e:
              log lvlError, "Failed to run command '" & name & "': " & e.msg

            return ""

    else:
      return genAst(name, jsonWrapper, jsonWrapperName, documentationStr, inParams = params, inReturnType = returnType, inAactive = active, inContext = context):
        jsonWrapper
        defineCommand(name,
          active = inActive,
          docs = documentationStr,
          params = @[],
          returnType = inReturnType,
          context = inContext):
          proc(editor: uint64, args: string): string {.cdecl.} =
            var args = newJArray()
            try:
              if inActive:
                args.add(editor.toJson)
              for a in newStringStream($argsString).parseJsonFragments():
                args.add a
              let res = jsonWrapperName(args)
              return $res
            except CatchableError as e:
              log lvlError, "Failed to run command '" & name & "': " & e.msg

            return ""

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
      setRegisterText("", ".")
      editor.recordCurrentCommand(@["."])

  proc startRecordingCurrentCommandInPeriodMacro(editor: TextEditor) =
    if not isReplayingCommands() and editor.shouldRecortImplicitPeriodMacro():
      startRecordingCommands(".-temp")
      setRegisterText("", ".-temp")
      editor.recordCurrentCommand(@[".-temp"])
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
    editor.setSelections editor.selections.mapIt (if it.isBackwards:
        ((it.first.line, editor.lineLength(it.first.line)), (it.last.line, 0))
      else:
        ((it.first.line, 0), (it.last.line, editor.lineLength(it.last.line)))
        )

  proc normalMode(editor: TextEditor) {.exposeActive(editorContext).} =
    ## Exit to normal mode and clear things
    if editor.mode == "vim.normal":
      discard editor.command("hide-signature-help", "")
      editor.setSelection editor.getSelection.last.toSelection
      editor.editor.getSnippetComponent().get.clearTabStops()
    editor.setMode("vim.normal")
    editor.edit.endTransaction()

  proc visualMode(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setMode "vim.visual"

  proc visualLineMode(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setMode "vim.visual-line"
    editor.selectLine()

  proc getFlag(str: var string, flag: string): bool =
    result = str.find(flag) != -1
    str = str.replace(flag, "")

  proc applyVimMove(editor: TextEditor, move: string, suffix: string, count: int = 0): tuple[updateTargetColumn: bool, inclusive: Option[bool]] =
    result.updateTargetColumn = true
    var adjustedMove = move
    if getFlag(adjustedMove, ";inclusive"):
      result.inclusive = true.some
    elif getFlag(adjustedMove, ";exclusive"):
      result.inclusive = false.some
    if getFlag(adjustedMove, ";dont-update-target-column"):
      result.updateTargetColumn = false
    if move.startsWith("("):
      adjustedMove = adjustedMove & " " &  suffix
      editor.setSelections editor.multiMove(editor.selections, adjustedMove, count, wrap=false, includeEol=editor.vimState.cursorIncludeEol)

    else:
      # log lvlWarn, &"applyVimMove old '{move}'"
      let (action, arg) = adjustedMove.parseAction
      for i in 0..<max(count, 1):
        discard editor.command(action, arg)

  proc selectLast(editor: TextEditor, move: string, count: int = 0) {.exposeActive(editorContext).} =
    let res = editor.applyVimMove(move, "(end)", count)
    if not move.startsWith("("):
      editor.setSelections editor.selections.mapIt(it.last.toSelection)

    if res.updateTargetColumn:
      editor.updateTargetColumn()
    if editor.vimState.selectLines:
      editor.selectLine()
    editor.scrollToCursor()
    editor.vimState.deleteInclusiveEnd = true

  proc select(editor: TextEditor, move: string, count: int = 1) {.exposeActive(editorContext).} =
    let res = editor.applyVimMove(move, "(join)", count)
    if res.updateTargetColumn:
      editor.updateTargetColumn()
    if editor.vimState.selectLines:
      editor.selectLine()
    editor.scrollToCursor()

  proc undo(editor: TextEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext).} =
    if enterNormalModeBefore:
      editor.setMode "vim.normal"

    editor.undo(editor.vimState.currentUndoCheckpoint)
    if enterNormalModeBefore:
      if not editor.selections.allEmpty:
        editor.setMode "vim.visual"
      else:
        editor.setMode "vim.normal"

  proc redo(editor: TextEditor, enterNormalModeBefore: bool) {.exposeActive(editorContext).} =
    if enterNormalModeBefore:
      editor.setMode "vim.normal"

    editor.redo(editor.vimState.currentUndoCheckpoint)
    if enterNormalModeBefore:
      if not editor.selections.allEmpty:
        editor.setMode "vim.visual"
      else:
        editor.setMode "vim.normal"

  proc copySelection(editor: TextEditor, register: string = "", inclusive: bool = true, highlight: bool = false): seq[Selection] =
    ## Copies the selected text
    ## If line selection mode is enabled then it also extends the selection so that deleting it will also delete the line itself
    yankedLines = editor.vimState.selectLines
    editor.copy(register, inclusiveEnd=inclusive, highlight)
    let selections = editor.selections
    if editor.vimState.selectLines:
      editor.setSelections editor.selections.mapIt (
        if it.isBackwards:
          if it.last.line > 0:
            (it.first, editor.applyMove(it.last, "column", -1).last)
          elif it.first.line + 1 < editor.lineCount:
            (editor.applyMove(it.first, "column", 1).last, it.last)
          else:
            it
        else:
          if it.first.line > 0:
            (editor.applyMove(it.first, "column", -1).last, it.last)
          elif it.last.line + 1 < editor.lineCount:
            (it.first, editor.applyMove(it.last, "column", 1).last)
          else:
            it
      )

    return selections.mapIt(it.normalized.first.toSelection)

  proc deleteSelection(editor: TextEditor, forceInclusiveEnd: bool, oldSelections: Option[seq[Selection]] = seq[Selection].none, forceExclusive: bool = false) {.exposeActive(editorContext).} =
    var inclusive = (not editor.vimState.selectLines) and (editor.vimState.deleteInclusiveEnd or forceInclusiveEnd)
    if forceExclusive:
      inclusive = false
    let newSelections = editor.copySelection(getVimDefaultRegister(), inclusive)
    let selectionsToDelete = editor.selections
    let oldSelections = oldSelections.get(editor.selections)
    editor.edit.withTransaction:
      editor.setSelections editor.edit(selectionsToDelete, oldSelections, @[""], inclusive = inclusive)
    editor.scrollToCursor()
    editor.vimState.deleteInclusiveEnd = true
    editor.setMode "vim.normal"

  proc changeSelection*(editor: TextEditor, forceInclusiveEnd: bool, oldSelections: Option[seq[Selection]] = seq[Selection].none, forceExclusive: bool = false) {.exposeActive(editorContext).} =
    var inclusive = editor.vimState.deleteInclusiveEnd or forceInclusiveEnd
    if forceExclusive:
      inclusive = false
    let newSelections = editor.copySelection(getVimDefaultRegister(), inclusive)
    let selectionsToDelete = editor.selections
    let oldSelections = oldSelections.get(editor.selections)
    editor.setMode "vim.insert"
    editor.edit.withTransaction:
      editor.setSelections editor.edit(selectionsToDelete, oldSelections, @[""], inclusive = inclusive)
    editor.scrollToCursor()
    editor.vimState.deleteInclusiveEnd = true

  proc yankSelection*(editor: TextEditor, inclusive: bool = true) {.exposeActive(editorContext).} =
    let selections = editor.copySelection(getVimDefaultRegister(), inclusive, highlight = true)
    editor.setSelections selections
    editor.setMode "vim.normal"

  proc yankSelectionClipboard*(editor: TextEditor, inclusive: bool = true) {.exposeActive(editorContext).} =
    let selections = editor.copySelection(inclusive = inclusive, highlight = true)
    editor.setSelections selections
    editor.setMode "vim.normal"

  template mergeSelections*(a, b: seq[Selection], body: untyped): seq[Selection] =
    let aa = a
    let bb = b
    collect(newSeq):
      for i in 0..min(aa.high, bb.high):
        let it1 {.inject.} = aa[i]
        let it2 {.inject.} = bb[i]
        body

  proc replace(editor: TextEditor, input: string) {.exposeActive(editorContext).} =
    let content = editor.content
    # debugf"replace '{input}'"
    # let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, "column", 1, true, true)):
      # (it1.first, it2.last).toSelection
    let selections = editor.selections

    let texts = selections.mapIt(block:
      let selection = it
      let selectedText = content.sliceSelection(selection, inclusive=true)
      var newText = newStringOfCap(selectedText.bytes.int * input.len.int)
      var lastIndex = 0
      var index = selectedText.find("\n", 0)
      if index == -1:
        newText.add input.repeat(selectedText.runeLen)
      else:
        while index != -1:
          let lineLen = selectedText.slice(lastIndex, index).runeLen - 1
          newText.add input.repeat(lineLen)
          newText.add "\n"
          lastIndex = index.int + 1
          index = selectedText.find("\n", index + 1)

        let lineLen = selectedText.slice(lastIndex, selectedText.bytes.int - 1).runeLen
        newText.add input.repeat(lineLen)

      newText
    )

    editor.addNextCheckpoint "insert"
    editor.setSelections editor.edit(editor.selections, texts, inclusive=true).mapIt(it.first.toSelection)
    editor.normalMode()

  proc selectMove(editor: TextEditor, move: string, count: int = 0) {.exposeActive(editorContext).} =
    # debugf"selectMove {move}"
    let res = editor.applyVimMove(move, "(merge)", count)
    if res.updateTargetColumn:
      editor.updateTargetColumn()
    editor.scrollToCursor()

  proc deleteMove(editor: TextEditor, move: string, count: int = 0) {.exposeActive(editorContext).} =
    let oldSelections = editor.selections
    let res = editor.applyVimMove(move, "(merge)", count)
    let inclusive = res.inclusive.get(true)
    editor.deleteSelection(inclusive, oldSelections=oldSelections.some, forceExclusive = not inclusive)
    if res.updateTargetColumn:
      editor.updateTargetColumn()
    editor.recordCurrentCommandInPeriodMacro() # todo: why this?

  proc changeMove(editor: TextEditor, move: string, count: int = 0) {.exposeActive(editorContext).} =
    let oldSelections = editor.selections
    let res = editor.applyVimMove(move, "(merge)", count)
    let inclusive = res.inclusive.get(true)
    editor.changeSelection(inclusive, oldSelections=oldSelections.some, forceExclusive = not inclusive)
    if res.updateTargetColumn:
      editor.updateTargetColumn()
    editor.recordCurrentCommandInPeriodMacro() # todo: why this?
    if not isReplayingCommands():
      editor.recordCurrentCommand(@[".-temp"])

  proc yankMove(editor: TextEditor, move: string, count: int = 0) {.exposeActive(editorContext).} =
    let res = editor.applyVimMove(move, "(merge)", count)
    let inclusive = res.inclusive.get(true)
    editor.yankSelection(inclusive)

  proc vimClamp*(editor: TextEditor, cursor: Cursor): Cursor =
    var lineLen = editor.lineLength(cursor.line)
    if not editor.vimState.cursorIncludeEol and lineLen > 0: lineLen.dec
    result = (cursor.line, min(cursor.column, lineLen))

  iterator iterateTextObjects*(editor: TextEditor, cursor: Cursor, move: string, backwards: bool = false): Selection =
    var selection = editor.applyMove(cursor, move, 0)
    # debugf"iterateTextObjects({cursor}, {move}, {backwards}), selection: {selection}"
    yield selection
    while true:
      let lastSelection = selection
      if not backwards and selection.last.column >= editor.lineLength(selection.last.line) - 1:
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
    # debugf"selectTextObject({textObject}, {textObjectRange}, {count})"

    editor.setSelections editor.selections.mapIt(block:
        var res = it.last
        var resultSelection = it
        # debugf"-> {resultSelection}"

        for i, selection in enumerateTextObjects(editor, res, textObject, false):
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
    # debugf"selectSurrounding({textObject}, {textObjectRange}, {count})"

    let selections = editor.selections
    let newSelections = mergeSelections(selections, editor.multiMove(selections, textObject, count, wrap = false, includeEol = editor.vimState.cursorIncludeEol)):
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
    let which = getSetting[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
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

            if selection.first.column >= editor.lineLength(selection.first.line) or text.charAt(selection.first.toPoint) notin Whitespace:
              res = cursor
              break
        # echo res, ", ", it, ", ", which
        res.toSelection(it, which)
      )

    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc applyMove(editor: TextEditor, selections: openArray[Selection], move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1, which: Option[SelectionCursor] = SelectionCursor.none): seq[Selection] =
    ## Applies the given move `count` times and returns the resulting selections
    ## `allowEmpty` If true then the move can stop on empty lines
    ## `backwards` Move backwards
    ## `count` How often to apply the move
    ## `which` How to assemble the final selection from the input and the move. If not set uses `editor.text.cursor.movement`

    # debugf"applyMove '{move}' {count} {backwards} {allowEmpty}"
    let text = editor.content
    let which = which.get(getSetting[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both))
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
                text.charAt(selection.last.toPoint) notin Whitespace:
              res = cursor
              break
            if backwards and selection.last.column == editor.lineLength(selection.last.line):
              res = cursor
              break
        res.toSelection(it, which)
      )

  proc moveSelectionEnd(editor: TextEditor, move: string, backwards: bool = false, allowEmpty: bool = false, count: int = 1) {.exposeActive(editorContext).} =

    editor.setSelections editor.applyMove(editor.selections, move, backwards, allowEmpty, count)
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc moveParagraph(editor: TextEditor, backwards: bool, count: int = 1) {.exposeActive(editorContext).} =
    let which = getSetting[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.setSelections editor.selections.mapIt(block:
        var res = it.last
        for k in 0..<max(1, count):
          for i, selection in enumerateTextObjects(editor, res, "vim.paragraph-inner", backwards):
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
    editor.copy("", inclusiveEnd = false)
    if editor.mode != "vim.insert":
      editor.addNextCheckpoint "insert"
    let selections = editor.multiMove(editor.getSelections, "(column -1) (join)")
    editor.setSelections editor.edit(selections, @[""], inclusive=false)
    discard editor.command("auto-show-signature-help", "\"\"")

  proc deleteRight*(editor: TextEditor) {.exposeActive(editorContext).} =
    yankedLines = editor.vimState.selectLines
    editor.copy("", inclusiveEnd = false)
    if editor.mode != "vim.insert":
      editor.addNextCheckpoint "insert"
    let selections = editor.getSelections
    editor.setSelections editor.edit(selections, @[""], inclusive=true)

  proc moveCursorPage(editor: TextEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext).} =
    ## Direction 100 means 100% of window height downwards -100 is upwards, 50 would be 50%
    editor.setSelections editor.multiMove(editor.selections, "page", direction * max(count, 1), true, includeEol = editor.vimState.cursorIncludeEol)
    let nextScrollBehaviour = if center: CenterAlways.some else: ScrollBehaviour.none
    editor.scrollToCursor(behaviour = nextScrollBehaviour, 0.5)
    if editor.vimState.selectLines:
      editor.selectLine()

  proc moveCursorVisualPage(editor: TextEditor, direction: int, count: int = 1, center: bool = false) {.exposeActive(editorContext).} =
    ## Direction 100 means 100% of window height downwards -100 is upwards, 50 would be 50%
    if editor.vimState.selectLines:
      editor.setSelections editor.multiMove(editor.selections, "page", direction * max(count, 1), true, includeEol = editor.vimState.cursorIncludeEol)
    else:
      editor.setSelections editor.multiMove(editor.selections, "visual-page", direction * max(count, 1), true, includeEol = editor.vimState.cursorIncludeEol)
    editor.scrollToCursor(behaviour = ScrollBehaviour.none, 0.5)
    if editor.vimState.selectLines:
      editor.selectLine()

  func toSelection*(cursor: Cursor, default: Selection, which: SelectionCursor): Selection =
    case which
    of Config: return default
    of Both: return (cursor, cursor)
    of First: return (cursor, default.last)
    of Last: return (default.first, cursor)
    of LastToFirst: return (default.last, cursor)

  proc moveFirst(editor: TextEditor, move: string) {.exposeActive(editorContext).} =
    let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.setSelections editor.selections.mapIt(
      editor.applyMove(it.last, move, 1, wrap = true, includeEol = editor.vimState.cursorIncludeEol).first.toSelection(it, cursorSelector)
    )

    if editor.vimState.selectLines:
      editor.selectLine()
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc moveLast(editor: TextEditor, move: string, count: int = 1, wrap: bool = false) {.exposeActive(editorContext).} =
    let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    # debugf"moveLast '{move}', {editor.vimState.cursorIncludeEol}"
    editor.setSelections editor.selections.mapIt(
      editor.applyMove(it.last, move, 1, wrap = wrap, includeEol = editor.vimState.cursorIncludeEol).last.toSelection(it, cursorSelector)
    )

    if editor.vimState.selectLines:
      editor.selectLine()
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc move(editor: TextEditor, move: string, direction: int = 1, wrap: bool = false) {.exposeActive(editorContext).} =
    var move = move
    if not move.startsWith("("):
      move = "(" & move & ")"
    let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    if cursorSelector == Last:
      move.add " (join)"
    editor.setSelections editor.multiMove(editor.selections, move, direction, wrap, includeEol = editor.vimState.cursorIncludeEol)

    if editor.vimState.selectLines:
      editor.selectLine()
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc moveDirection(editor: TextEditor, move: string, direction: int) {.exposeActive(editorContext).} =
    var move = move
    if not move.startsWith("("):
      move = "(" & move & ")"
    let cursorSelector = editor.getSetting(editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    if cursorSelector == Last:
      move.add " (join)"
    editor.setSelections editor.multiMove(editor.selections, move, direction, false, includeEol = editor.vimState.cursorIncludeEol)

    if editor.vimState.selectLines:
      editor.selectLine()
    editor.scrollToCursor()

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

    editor.addNextCheckpoint "insert"

    var selections = editor.getSelections

    if yankedLines and $editor.mode == "vim.normal":
      selections = editor.multiMove(selections, "line", 1, wrap = false, includeEol = true).mapIt(it.last.toSelection)
      selections = editor.edit(selections, @["\n"], inclusive=false).mapIt(it.last.toSelection)
    elif pasteRight:
      selections = editor.multiMove(selections, "column", 1, false, true).mapIt(it.last.toSelection)

    editor.setMode "vim.normal"
    editor.paste selections, register, inclusiveEnd=inclusiveEnd

  proc toggleCase(editor: TextEditor, moveCursorRight: bool) {.exposeActive(editorContext).} =
    var editTexts: seq[string]

    let content = editor.content
    for s in editor.selections:
      let text = $content.sliceSelection(s, inclusive=true)
      var newText = newStringOfCap(text.len)
      for r in text.runes:
        if r.isLower:
          newText.add $r.toUpper
        else:
          newText.add $r.toLower
      editTexts.add newText

    editor.addNextCheckpoint "insert"
    let oldSelections = editor.selections
    discard editor.edit(editor.selections, editTexts, inclusive=true)
    editor.setSelections oldSelections.mapIt(it.first.toSelection)

    editor.setMode "vim.normal"

    if moveCursorRight:
      editor.moveCursorColumn(1, wrap=false, includeEol=editor.vimState.cursorIncludeEol)
      editor.updateTargetColumn()

  # todo
  # proc vimCloseCurrentViewOrQuit() {.exposeActive(editorContext, "vim-close-current-view-or-quit").} =
  #   let openEditors = getNumVisibleViews() + getNumHiddenViews()
  #   if openEditors == 1:
  #     plugin_runtime.quit()
  #   else:
  #     closeActiveView()

  proc indent(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.edit.withTransaction:
      discard editor.command("indent", "")

  proc unindent(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.edit.withTransaction:
      discard editor.command("unindent", "")

  proc selectPrev(editor: TextEditor) {.exposeActive(editorContext).} =
    discard editor.command("select-prev", "")
    for s in editor.getSelections:
      if not s.isEmpty:
        if $editor.mode != "vim.visual":
          editor.visualMode()
        return
    if $editor.mode != "vim.normal":
      editor.normalMode()

  proc selectNext(editor: TextEditor) {.exposeActive(editorContext).} =
    discard editor.command("select-next", "")
    for s in editor.getSelections:
      if not s.isEmpty:
        if $editor.mode != "vim.visual":
          editor.visualMode()
        return
    if $editor.mode != "vim.normal":
      editor.normalMode()

  proc addCursorAbove(editor: TextEditor) {.exposeActive(editorContext).} =
    var selections = editor.getSelections
    let newSelections = editor.multiMove(@[selections.last], "line-up", 0, wrap=false, includeEol=false).mapIt(it.last.toSelection)
    selections.add newSelections
    editor.setSelections selections
    editor.scrollToCursor()

  proc addCursorBelow(editor: TextEditor) {.exposeActive(editorContext).} =
    var selections = editor.getSelections
    let newSelections = editor.multiMove(@[selections.last], "line-down", 0, wrap=false, includeEol=false).mapIt(it.last.toSelection)
    selections.add newSelections
    editor.setSelections selections
    editor.scrollToCursor()

  proc enter(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint "insert"
    editor.insertText "\n", autoIndent=true

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
    let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, "line", 1, wrap = false, includeEol = true)):
      (it1.last, it2.last)
    editor.setSelections selections
    editor.deleteSelection(true, oldSelections=some(@oldSelections))
    editor.vimState.selectLines = false

  proc changeToLineEnd(editor: TextEditor) {.exposeActive(editorContext).} =
    let oldSelections = editor.getSelections
    let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, "line", 1, wrap = false, includeEol = true)):
      (it1.last, it2.last)
    editor.setSelections selections
    editor.changeSelection(true, oldSelections=some(@oldSelections))
    editor.vimState.selectLines = false

  proc yankToLineEnd(editor: TextEditor) {.exposeActive(editorContext).} =
    let selections = mergeSelections(editor.selections, editor.multiMove(editor.selections, "line", 1, wrap = false, includeEol = true)):
      (it1.last, it2.last)
    editor.setSelections selections
    editor.yankSelection()

  proc moveFileStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    let which = getSetting[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    editor.setSelection (count - 1, 0).toSelection(editor.getSelection, which)
    editor.moveFirst "line-no-indent"
    editor.scrollToCursor()

  proc moveFileEnd(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    let line = if count == 0: editor.content.lines.int - 1 else: count - 1
    let which = getSetting[SelectionCursor](editor.getContextWithMode("editor.text.cursor.movement"), SelectionCursor.Both)
    var newSelection = (line, 0).toSelection(editor.getSelection, which)
    if newSelection == editor.getSelection:
      let lineLen = editor.lineLength(line.int32).int
      editor.setSelection (line, lineLen).toSelection(editor.getSelection, which)
    else:
      editor.setSelection newSelection
      editor.moveFirst "line-no-indent"
    editor.scrollToCursor()

  proc scrollLineToTopAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    if editor.getCommandCount != 0:
      editor.setSelection (editor.getCommandCount.int, 0).toSelection
    editor.setSelections editor.multiMove(editor.selections, "line-no-indent", 1, wrap = false, includeEol = editor.vimState.cursorIncludeEol).mapIt(it.first.toSelection)
    editor.setCursorScrollOffset editor.selections.last.last, getVimLineMargin()

  proc scrollLineToTop(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    if editor.getCommandCount != 0:
      editor.setSelection (editor.getCommandCount, editor.selections.last.last.column).toSelection
    editor.setCursorScrollOffset editor.selections.last.last, getVimLineMargin()

  proc centerLineAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    if editor.getCommandCount != 0:
      editor.setSelection (editor.getCommandCount.int, 0).toSelection
    editor.setSelections editor.multiMove(editor.selections, "line-no-indent", 1, wrap = false, includeEol = editor.vimState.cursorIncludeEol).mapIt(it.first.toSelection)
    editor.scrollToCursor(ScrollBehaviour.CenterAlways.some, 0.5)

  proc centerLine(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    editor.scrollToCursor(ScrollBehaviour.CenterAlways.some, 0.5)

  proc scrollLineToBottomAndMoveLineStart(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    if editor.getCommandCount != 0:
      editor.setSelection (editor.getCommandCount.int, 0).toSelection
    editor.setSelections editor.multiMove(editor.selections, "line-no-indent", 1, wrap = false, includeEol = editor.vimState.cursorIncludeEol).mapIt(it.first.toSelection)
    editor.setCursorScrollOffset editor.selections.last.last, (editor.getVisibleLineCount().float - getVimLineMargin())

  proc scrollLineToBottom(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    if editor.getCommandCount != 0:
      editor.setSelection (editor.getCommandCount, editor.selections.last.last.column).toSelection
    editor.setCursorScrollOffset editor.selections.last.last, (editor.getVisibleLineCount().float - getVimLineMargin())

  proc insertMode(editor: TextEditor, move: string = "") {.exposeActive(editorContext).} =
    # debugf"insertMode '{move}'"
    editor.setMode "vim.insert"
    editor.addNextCheckpoint "insert"
    case move
    of "right":
      editor.setSelections editor.multiMove(editor.selections, "column", 1, wrap = false, includeEol = true).mapIt(it.last.toSelection)
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

  proc insertLineBelow(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setSelections editor.multiMove(editor.getSelections, "line", 0, wrap=false, includeEol=true).mapIt(it.last.toSelection)
    editor.addNextCheckpoint "insert"
    editor.insertText "\n", autoIndent=true
    editor.setMode "vim.insert"

  proc insertLineAbove(editor: TextEditor, move: string = "") {.exposeActive(editorContext).} =
    editor.setSelections editor.multiMove(editor.getSelections, "line", 0, wrap=false, includeEol=true).mapIt(it.first.toSelection)
    editor.addNextCheckpoint "insert"
    editor.insertText "\n", autoIndent=false
    editor.moveDirection("line-up", 1)
    editor.setMode "vim.insert"

  proc setSearchQueryFromWord(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setSelection editor.setSearchQueryFromMove("word", 1, prefix=r"\b", suffix=r"\b").first.toSelection

  proc setSearchQueryFromSelection(editor: TextEditor) {.exposeActive(editorContext).} =
    let content = editor.content.sliceSelection(editor.getSelection, inclusive=true)
    discard editor.setSearchQuery($content, escapeRegex=true, prefix="", suffix="")
    editor.setSelection editor.getSelection.first.toSelection
    editor.normalMode()

  proc openSearchBar(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.openSearchBar("", scrollToPreview=true, selectResult=true)

  proc exitCommandLine() {.command.} =
    if activeTextEditor(includeCommandLine = true).getSome(editor):
      let mode = $editor.mode
      if mode == "vim.normal":
        discard runCommand("exit-command-line", "")
        return

      editor.setMode("vim.normal")

  proc exitPopup() {.command.} =
    if activeTextEditor(includePopups = true).getSome(editor) and $editor.mode != "vim.normal":
      editor.setMode("vim.normal")
      return

    discard runCommand("close-active-view", "")

  proc selectWordOrAddCursor(editor: TextEditor) {.exposeActive(editorContext).} =
    let selections = editor.selections
    if selections.len == 1:
      var selection = editor.setSearchQueryFromMove("(word)", 1, prefix=r"\b", suffix=r"\b")
      editor.setSelection editor.multiMove(@[selection], "(inclusive)").last
    else:
      let next = editor.multiMove(@[selections.last], "(next-search-result) (inclusive)", 0, wrap = true, includeEol=false).last
      let newSelections = @selections & next
      editor.setSelections newSelections
      editor.scrollToCursor()
      editor.updateTargetColumn()

    editor.setMode("vim.visual")

  proc moveLastSelectionToNextSearchResult(editor: TextEditor) {.exposeActive(editorContext).} =
    let selections = editor.selections
    if selections.len == 1:
      var selection = editor.setSearchQueryFromMove("(word)", 1, prefix=r"\b", suffix=r"\b")
      editor.setSelection editor.multiMove(@[selection], "(inclusive)").last
      editor.setSelection selection
    else:
      let next = editor.multiMove(@[selections.last], "(next-search-result) (inclusive)", 0, wrap = true, includeEol=false).last
      let newSelections = selections[0..^2] & next
      editor.setSelections newSelections
      editor.scrollToCursor()
      editor.updateTargetColumn()

    editor.setMode("vim.visual")

  proc setSearchQueryOrAddCursor(editor: TextEditor) {.exposeActive(editorContext).} =
    let selections = editor.selections
    # debugf"setSearchQueryOrAddCursor {selections}, {selections.last}"
    if selections.len == 1:
      let selectedText = $editor.content.sliceSelection(selections.last, inclusive=true)
      let textEscaped = selectedText.escapeRegex
      let currentSearchQuery = editor.getSearchQuery()
      # debugf"{selectedText.bytes}, '{selectedText.text}' -> '{textEscaped}' -> '{currentSearchQuery}'"
      if textEscaped != currentSearchQuery and r"\b" & textEscaped & r"\b" != currentSearchQuery:
        if editor.setSearchQuery(selectedText, escapeRegex=true, prefix="", suffix=""):
          return

    let next = editor.multiMove(@[selections.last], "(next-search-result) (inclusive)", 0, wrap = true, includeEol=false).last
    if next == selections[0]:
      return
    let newSelections = @selections & next
    editor.setSelections newSelections
    editor.scrollToCursor()
    editor.updateTargetColumn()

  # todo
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
  #         for name, selections in editor.vimState.unresolvedMarks:
  #           marks[name] = selections

  #         if marks.len > 0:
  #           states[filename] = %*{
  #             "marks": marks.toJson,
  #           }

  #     setSessionData("vim.states", states)
  #   except:
  #     debugf"Failed to save vim editor states"

  proc resolveMarks(editor: TextEditor) =
    let unresolvedMarks = editor.vimState.unresolvedMarks
    for name, selections in unresolvedMarks:
      let anchors = editor.createAnchors(selections)
      if anchors.len > 0:
        editor.vimState.marks[name] = anchors
        editor.vimState.unresolvedMarks.del(name)

  proc addMark(editor: TextEditor, name: string) {.exposeActive(editorContext).} =
    editor.resolveMarks()
    editor.vimState.marks[name] = editor.createAnchors(editor.selections)

  proc gotoMark(editor: TextEditor, name: string) {.exposeActive(editorContext).} =
    editor.resolveMarks()

    if name in editor.vimState.marks:
      let newSelections = editor.resolveAnchors(editor.vimState.marks[name])
      if newSelections.len == 0:
        return

      case $editor.mode
      of "vim.visual", "vim.visual-line":
        let oldSelections = editor.selections
        if newSelections.len == oldSelections.len:
          editor.setSelections collect(block:
            for i in 0..newSelections.high:
              oldSelections[i] or newSelections[i]
          )
        else:
          editor.setSelections newSelections
      else:
        editor.setSelections newSelections

      editor.updateTargetColumn()
      editor.centerCursor()

  proc deleteWordBack(editor: TextEditor) {.exposeActive(editorContext).} =
    let wordSelections = editor.multiMove(editor.selections, "vim.word-back", 1, wrap = false, includeEol = true)
    let selectionsToDelete = mergeSelections(wordSelections, editor.selections, (it1.first, it2.last))
    editor.setSelections editor.edit(selectionsToDelete, @[""], inclusive = false)
    editor.autoShowCompletions()

  proc deleteLineBack(editor: TextEditor) {.exposeActive(editorContext).} =
    let lineSelections = editor.selections.mapIt ((it.last.line.int, 0), it.last)
    editor.setSelections editor.edit(lineSelections, @[""], inclusive = false)
    editor.autoShowCompletions()

  proc includeSelectionEnd*(self: TextEditor, res: Selection, includeAfter: bool = true): Selection =
    result = res
    if not includeAfter:
      result = (res.first, self.applyMove(res.last, "column", -1, wrap = false, includeEol = true).last)

  proc surround(editor: TextEditor, text: string) {.exposeActive(editorContext).} =
    let (left, right) = case text
    of "(", ")": ("(", ")")
    of "{", "}": ("{", "}")
    of "[", "]": ("[", "]")
    of "<", ">": ("<", ">")
    else:
      let text = text
      (text, text)

    let selections = editor.selections.mapIt(it.normalized)
    let rightCursors = editor.multiMove(selections, "column", 1, wrap = false, includeEol = true)

    var insertSelections = newSeq[Selection](selections.len * 2)
    var insertTexts = newSeq[string](selections.len * 2)
    for i, s in selections:
      insertSelections[i * 2 + 0] = s.first.toSelection
      insertSelections[i * 2 + 1] = rightCursors[i].last.toSelection
      insertTexts[i * 2 + 0] = left
      insertTexts[i * 2 + 1] = right

    editor.addNextCheckpoint "insert"
    let newSelections = editor.edit(insertSelections, insertTexts, inclusive = false)
    if newSelections.len mod 2 != 0:
      return

    let newSelectionsInclusive = collect:
      for i in 0..<newSelections.len div 2:
        editor.includeSelectionEnd((newSelections[i * 2].first, newSelections[i * 2 + 1].last), false)
    editor.setSelections newSelectionsInclusive

  proc startMacro(editor: TextEditor, name: string) {.exposeActive(editorContext).} =
    if isReplayingCommands() or isRecordingCommands(getCurrentMacroRegister()):
      return
    setSetting("editor.current-macro-register", name)
    setRegisterText("", name)
    startRecordingCommands(name)

  proc playMacro(editor: TextEditor, name: string) {.exposeActive(editorContext).} =
    let register = if name == "@":
      getCurrentMacroRegister()
    else:
      name

    discard runCommand("replay-commands", &"\"{register}\"")

  proc stopMacro(editor: TextEditor) {.exposeActive(editorContext).} =
    if isReplayingCommands():
      return
    let register = getCurrentMacroRegister()
    if isReplayingCommands() or not isRecordingCommands(register):
      return
    stopRecordingCommands(register)

  proc invertSelections(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setSelections editor.selections.mapIt((it.last, it.first))
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc invertLineSelections(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setSelections editor.selections.mapIt((it.last, it.first))
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc reverseSelections(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.setSelections editor.selections.reversed()
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc joinLines(editor: TextEditor, reduceSpace: bool) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint "insert"
    let content = editor.content
    if reduceSpace:
      var insertTexts: seq[string]
      let selectionsToDelete = editor.selections.mapIt(block:
        let lineLen = content.lineLen(it.last.line).int
        if lineLen == 0 or content.charAt(point(it.last.line.int, lineLen - 1)) == ' ':
          insertTexts.add ""
        else:
          insertTexts.add " "
        var nextLineIndent = editor.applyMove((it.last.line.int + 1, 0).toSelection, "line-no-indent", 0, wrap=false, includeEol=true)
        ((it.last.line.int, lineLen), (it.last.line + 1, nextLineIndent.first.column))
      )
      editor.setSelections editor.edit(selectionsToDelete, insertTexts, inclusive=false).mapIt(it.first.toSelection)
    else:
      let selectionsToDelete = editor.selections.mapIt(block:
        let lineLen = content.lineLen(it.last.line).int
        ((it.last.line.int, lineLen), (it.last.line.int + 1, 0))
      )
      editor.setSelections editor.edit(selectionsToDelete, @[""], inclusive=false).mapIt(it.first.toSelection)

  proc sortLines(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint "insert"
    let content = editor.content
    var insertTexts: seq[string]
    for it in editor.selections:
      let text = $content.sliceSelection(it.normalized, inclusive=false)
      let endsWithNl = text.endsWith("\n")
      let nl = if endsWithNl: "\n" else: ""
      var lines = text.splitLines()
      lines.sort()
      insertTexts.add lines.join("\n") & nl
    editor.setSelections editor.edit(editor.selections, insertTexts, inclusive=false)

  proc moveToColumn(editor: TextEditor, count: int = 1) {.exposeActive(editorContext).} =
    editor.setSelections editor.selections.mapIt((it.last.line.int, count).toSelection)
    editor.scrollToCursor()
    editor.updateTargetColumn()

  # todo
  # proc vimAddNextSameNodeToSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-add-next-same-node-to-selection").} =
  #   if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
  #     editor.setSelections editor.selections & selection
  #     editor.scrollToCursor()
  #     editor.updateTargetColumn()

  # proc vimMoveSelectionToNextSameNode(editor: TextEditor) {.exposeActive(editorContext, "vim-move-selection-to-next-same-node").} =
  #   if editor.getNextNodeWithSameType(editor.selection, includeAfter=false).getSome(selection):
  #     editor.setSelections editor.selections[0..^2] & selection
  #     editor.scrollToCursor()
  #     editor.updateTargetColumn()

  # proc vimAddNextSiblingToSelection(editor: TextEditor) {.exposeActive(editorContext, "vim-add-next-sibling-to-selection").} =
  #   if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
  #     editor.setSelections editor.selections & selection
  #     editor.scrollToCursor()
  #     editor.updateTargetColumn()

  # proc vimMoveSelectionToNextSibling(editor: TextEditor) {.exposeActive(editorContext, "vim-move-selection-to-next-sibling").} =
  #   if editor.getNextNamedSiblingNodeSelection(editor.selection, includeAfter=false).getSome(selection):
  #     editor.setSelections editor.selections[0..^2] & selection
  #     editor.scrollToCursor()
  #     editor.updateTargetColumn()

  proc growSelection(editor: TextEditor, amount: int = 1) {.exposeActive(editorContext).} =
    editor.setSelections editor.multiMove(editor.selections, "grow", amount, wrap = true, includeEol = true)
    editor.scrollToCursor()
    editor.updateTargetColumn()

  proc evaluateSelection(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, prefix = "", suffix = "", addSelectionIndex = false)

  proc incrementSelection(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, prefix = "", suffix = "+1", addSelectionIndex = false)

  proc decrementSelection(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, prefix = "", suffix = "-1", addSelectionIndex = false)

  proc incrementSelectionByIndex(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.evaluateExpressions(editor.selections, true, prefix = "", suffix = "", addSelectionIndex = true)

  proc increment(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.setSelections editor.multiMove(editor.selections, "number", 1, wrap = false, includeEol = true)
    editor.evaluateExpressions(editor.selections, false, prefix = "", suffix = "+1", addSelectionIndex = false)
    editor.setSelections editor.multiMove(editor.selections, "column", -1, wrap = false, includeEol = true).mapIt(it.last.toSelection)

  proc decrement(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.setSelections editor.multiMove(editor.selections, "number", 1, wrap = false, includeEol = true)
    editor.evaluateExpressions(editor.selections, false, prefix = "", suffix = "-1", addSelectionIndex = false)
    editor.setSelections editor.multiMove(editor.selections, "column", -1, wrap = false, includeEol = true).mapIt(it.last.toSelection)

  proc incrementByIndex(editor: TextEditor) {.exposeActive(editorContext).} =
    editor.addNextCheckpoint("insert")
    editor.setSelections editor.multiMove(editor.selections, "number", 1, wrap = false, includeEol = true)
    editor.evaluateExpressions(editor.selections, false, prefix = "", suffix = "", addSelectionIndex = true)
    editor.setSelections editor.multiMove(editor.selections, "column", -1, wrap = false, includeEol = true).mapIt(it.last.toSelection)

  proc replaceInputHandler(editor: TextEditor, input: string) {.exposeActive(editorContext).} =
    editor.replace(input)

  # todo
  # proc vimInsertRegisterInputHandler(editor: TextEditor, input: string) {.exposeActive(editorContext, "vim-insert-register-input-handler").} =
  #   editor.vimPaste register=input, inclusiveEnd=true
  #   editor.setMode "vim.insert"

  proc modeChangedHandler(editor: TextEditor, oldModes: seq[string], newModes: seq[string]) {.exposeActive(editorContext).} =
    let oldMode = if oldModes.len > 0:
      oldModes[0]
    else:
      ""

    if newModes.len == 0:
      return

    let newMode = newModes[0]

    if not editor.modes().contains("vim"):
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
      "vim.replace",
    ].toHashSet

    # debugf"vim: handle mode change {oldMode} -> {newMode}"
    if newMode == "vim.normal":
      if not isReplayingCommands() and isRecordingCommands(".-temp"):
        stopRecordingCommands(".-temp")

        if editor.getRevision > editor.vimState.revisionBeforeImplicitInsertMacro:
          debugf"Record implicit macro because document was modified"
          let text = getRegisterText(".-temp")
          setRegisterText(text, ".")
    else:
      if oldMode == "vim.normal" and newMode in recordModes:
        editor.startRecordingCurrentCommandInPeriodMacro()

    editor.vimState.selectLines = newMode == "vim.visual-line"
    editor.vimState.cursorIncludeEol = newMode == "vim.insert"
    editor.vimState.currentUndoCheckpoint = if newMode == "vim.insert": "word" else: "insert"

    case newMode
    of "vim.normal":
      editor.setSetting "text.inclusive-selection", false
      editor.setSelections editor.selections.mapIt(editor.vimClamp(it.last).toSelection)
      editor.hideCompletions()

    of "vim.insert":
      editor.setSetting "text.inclusive-selection", false

    of "vim.visual":
      editor.setSetting "text.inclusive-selection", true

    of "vim.visual-line":
      editor.setSetting "text.inclusive-selection", false

    else:
      editor.setSetting "text.inclusive-selection", false

  proc init_module_vim*() {.cdecl, exportc, dynlib.} =
    let commandService = getServiceChecked(CommandService)
    for c in vimCommands:
      discard commandService.registerCommand(c)
