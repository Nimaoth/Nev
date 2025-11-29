import std/[strutils, sequtils, sugar, strformat, tables, json]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as sca import nil
import misc/[util, custom_logger, custom_unicode, rope_utils, custom_async, myjsonutils]
import service
import text/[wrap_map, display_map]
import nimsumtree/[rope]
import lisp

{.push gcsafe, raises: [].}

logCategory "moves"

type
  MoveImpl* = proc(rope: Rope, move: string, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.gcsafe, raises: [].}
  MoveDatabase* = ref object of Service
    moves: Table[string, MoveImpl]
    env: Env
    debugMoves: bool

func serviceName*(_: typedesc[MoveDatabase]): string = "MoveDatabase"

addBuiltinService(MoveDatabase)

method init*(self: MoveDatabase): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.env = baseEnv()
  return ok()

proc toggleDebugMoves*(self: MoveDatabase) =
  self.debugMoves = not self.debugMoves

proc vimMotionWord*(text: Rope, cursor: Cursor, inclusive: bool): Selection =
  const AlphaNumeric = {'A'..'Z', 'a'..'z', '0'..'9', '_'}

  var line = text.getLine(cursor.line)
  if line.len == 0:
    return (cursor.line, 0).toSelection

  let c = line.charAt(cursor.column.clamp(0, line.len - 1))
  if c in Whitespace:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, inclusive, (c) => c in Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  elif c in AlphaNumeric:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, inclusive, (c) => c in AlphaNumeric)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  else:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, inclusive, (c) => c notin Whitespace and c notin AlphaNumeric)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

type VimWordCharCategory {.pure.} = enum Word, Whitespace, Other

proc vimWordCharCategory*(c: Rune): VimWordCharCategory =
  if c.int < 128:
    const AlphaNumeric = {'A'..'Z', 'a'..'z', '0'..'9', '_'}
    if c.char in Whitespace:
      return VimWordCharCategory.Whitespace
    if c.char in AlphaNumeric:
      return VimWordCharCategory.Word
    return VimWordCharCategory.Other
  if c.isWhitespace:
    return VimWordCharCategory.Whitespace
  if c.isAlpha:
    return VimWordCharCategory.Word
  return VimWordCharCategory.Other

proc vimMotionWordBack*(text: Rope, cursor: Cursor, inclusive: bool): Selection =
  if cursor.column == 0:
    return cursor.toSelection

  let prevCursor = text.clipPoint(point(cursor.line, cursor.column - 1), Left).toCursor
  let current = text.runeAt(cursor.toPoint)
  let prev = text.runeAt(prevCursor.toPoint)
  if current.vimWordCharCategory == prev.vimWordCharCategory:
    return vimMotionWord(text, cursor, inclusive)
  return vimMotionWord(text, prevCursor, inclusive)

proc vimMotionWordBig*(text: Rope, cursor: Cursor, inclusive: bool): Selection =
  var line = text.getLine(cursor.line)
  if line.len == 0:
    return (cursor.line, 0).toSelection

  let c = line.charAt(cursor.column.clamp(0, line.len - 1))
  if c in Whitespace:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, inclusive, (c) => c in Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  else:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, inclusive, (c) => c notin Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

proc findNext*(text: Rope, cursor: Cursor, target: Rune): Cursor =
  var c = text.cursorT(cursor.toPoint)
  c.seekNextRune()
  while not c.atEnd and c.currentRune != target:
    c.seekNextRune()
  return c.position.toCursor

proc clampCursor*(text: Rope, cursor: Cursor, includeAfter: bool = true): Cursor =
  var cursor = cursor
  cursor.line = clamp(cursor.line, 0, text.lines - 1)

  var res = text.clipPoint(cursor.toPoint, Bias.Left).toCursor
  var c = text.cursorT(res.toPoint)
  if not includeAfter and c.currentRune == '\n'.Rune and res.column > 0:
    c.seekPrevRune()
    res = c.position.toCursor
  return res

proc moveCursorColumn(text: Rope, cursor: Cursor, offset: int, wrap: bool = true, includeEol: bool = true): Cursor =
  var cursor = cursor

  if cursor.line notin 0..<text.lines:
    return cursor

  var c = text.cursorT(cursor.toPoint)
  var lastIndex = text.lastValidIndex(cursor.line, includeEol)

  if offset > 0:
    for i in 0..<offset:
      if cursor.column >= lastIndex:
        if not wrap:
          break
        if cursor.line < text.lines - 1:
          cursor.line = cursor.line + 1
          cursor.column = 0
          lastIndex = text.lastValidIndex(cursor.line, includeEol)
          c.seekForward(point(cursor.line, 0))
          continue
        else:
          cursor.column = lastIndex
          break

      c.seekNextRune()
      cursor = c.position.toCursor

  elif offset < 0:
    for i in 0..<(-offset):
      if cursor.column == 0:
        if not wrap:
          break
        if cursor.line > 0:
          cursor.line = cursor.line - 1
          lastIndex = text.lastValidIndex(cursor.line, includeEol)
          c.seekPrevRune()
          if not includeEol:
            c.seekPrevRune()
          cursor.column = lastIndex
          continue
        else:
          cursor.column = 0
          break

      c.seekPrevRune()
      cursor = c.position.toCursor

  return text.clampCursor(cursor, includeEol)

proc findSurroundStart*(rope: Rope, cursor: Cursor, c0: char, c1: char, depth: int = 1): Option[Cursor] =
  var depth = depth
  var res = cursor

  # todo: use RopeCursor
  while res.line >= 0:
    let line = rope.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column >= 0:
      let c = line.charAt(res.column)
      # debugf"findSurroundStart: {res} -> {depth}, '{c}'"
      if c == c1 and (depth < 1 or c0 != c1):
        inc depth
        if depth == 0:
          return res.some
      elif c == c0:
        dec depth
        if depth == 0:
          return res.some
      dec res.column

    if res.line == 0:
      return Cursor.none

    res = (res.line - 1, rope.lineLen(res.line - 1) - 1)

  return Cursor.none

proc findSurroundEnd*(rope: Rope, cursor: Cursor, c0: char, c1: char, depth: int = 1): Option[Cursor] =
  let lineCount = rope.lines
  var depth = depth
  var res = cursor

  # todo: use RopeCursor
  while res.line < lineCount:
    let line = rope.getLine(res.line)
    res.column = min(res.column, line.len - 1)
    while line.len > 0 and res.column < line.len:
      let c = line.charAt(res.column)
      # echo &"findSurroundEnd: {res} -> {depth}, '{c}'"
      if c == c0 and (depth < 1 or c0 != c1):
        inc depth
        if depth == 0:
          return res.some
      elif c == c1:
        dec depth
        if depth == 0:
          return res.some
      inc res.column

    if res.line == lineCount - 1:
      return Cursor.none

    res = (res.line + 1, 0)

  return Cursor.none

proc getSurrounding*(rope: Rope, selection: Selection, c0: char, c1: char, inside: bool): Selection =
  if selection.isBackwards:
    return rope.getSurrounding(selection.reverse, c0, c1, inside).reverse
  result = selection
  while true:
    let lastChar = rope.charAt(result.last.toPoint)
    let (startDepth, endDepth) = if lastChar == c0:
      (1, 0)
    elif lastChar == c1:
      (0, 1)
    else:
      (1, 1)

    if rope.findSurroundStart(result.first, c0, c1, startDepth).getSome(opening) and rope.findSurroundEnd(result.last, c0, c1, endDepth).getSome(closing):
      result = (opening, closing)
      if inside:
        result.first = rope.moveCursorColumn(result.first, 1)
        result.last = rope.moveCursorColumn(result.last, -1)
      return

    if rope.findSurroundEnd(result.first, c0, c1, -1).getSome(opening) and rope.findSurroundEnd(opening, c0, c1, 0).getSome(closing):
      result = (opening, closing)
      if inside:
        result.first = rope.moveCursorColumn(result.first, 1)
        result.last = rope.moveCursorColumn(result.last, -1)
      return
    else:
      return

proc moveCursorVisualLine(displayMap: DisplayMap, cursor: Cursor, offset: int, wrap: bool = false, includeAfter: bool = false, targetColumn: int): Cursor =
  let rope {.cursor.} = displayMap.buffer.visibleText
  let wrapPointOld = displayMap.toWrapPoint(cursor.toPoint)
  let endWrapPoint = displayMap.wrapMap.endWrapPoint
  let wrapPoint = wrapPoint(max(wrapPointOld.row.int + offset, 0), targetColumn).clamp(wrapPoint()...endWrapPoint)
  let newCursor = displayMap.toPoint(wrapPoint, if offset < 0: Bias.Left else: Bias.Right).toCursor
  if offset < 0 and newCursor.line > 0 and newCursor.line == cursor.line and displayMap.toWrapPoint(newCursor.toPoint).row == wrapPointOld.row:
    let newCursor2 = point(cursor.line - 1, rope.lineLen(cursor.line - 1))
    let displayPoint = displayMap.toDisplayPoint(newCursor2)
    let displayPoint2 = displayPoint(displayPoint.row, targetColumn.uint32)
    let point = displayMap.toPoint(displayPoint2)

    # echo &"moveCursorVisualLine {cursor}, {offset} -> {newCursor2} -> {displayPoint} -> {displayPoint2} -> {point}"
    return point.toCursor
  elif offset > 0:
    # go to wrap point and back to point one more time because if we land inside of e.g an overlay then the position will
    # be clamped which can screw up the target column we set before, so we need to calculate the target column again.
    let wrapPoint2 = wrapPoint(displayMap.toWrapPoint(newCursor.toPoint).row, targetColumn).clamp(wrapPoint()...endWrapPoint)
    let newCursor2 = displayMap.toPoint(wrapPoint2, if offset < 0: Bias.Left else: Bias.Right).toCursor

    # echo &"moveCursorVisualLine {cursor}, {offset} -> {newCursor}, wp: {wrapPointOld} -> {wrapPoint} -> {displayMap.toWrapPoint(newCursor.toPoint)}, {wrapPoint2} -> {newCursor2}"
    if newCursor2.line >= rope.lines:
      return cursor
    return rope.clampCursor(newCursor2, includeAfter)

  if newCursor.line >= rope.lines:
    return cursor
  return rope.clampCursor(newCursor, includeAfter)

proc moveCursorLine(text: Rope, displayMap: DisplayMap, cursor: Cursor, offset: int, targetColumn: int, wrap: bool, includeEol: bool): Cursor =
  var cursor = cursor
  let line = cursor.line + offset
  if line < 0:
    cursor = (0, cursor.column)
  elif line >= text.lines:
    cursor = (text.lines - 1, cursor.column)
  else:
    cursor.line = line
    let wrapPoint = displayMap.toWrapPoint(Point.init(line, 0))
    cursor.column = displayMap.toPoint(wrapPoint(wrapPoint.row.int, targetColumn)).column.int
  return text.clampCursor(cursor, includeEol)

type MoveFunction* = proc(move: string, selections: openArray[Selection], count: int): seq[Selection] {.gcsafe, raises: [].}

proc getCount(env: Env): int =
  let val = env["count"]
  if val != nil:
    case val.kind
    of Number:
      if val.num.int == 0:
        return 1
      else:
        return val.num.int
    else:
      log lvlError, "Can't convert env.count (" & $val & ") to type int"

  return 1

proc applyMoveImpl(self: MoveDatabase, displayMap: DisplayMap, move: string, selections: openArray[Selection], fallback: MoveFunction, args: openArray[LispVal], env: Env): seq[Selection] =
  if self.debugMoves:
    debugf"applyMoveImpl '{move}' {args}, {env.env}"

  template getEnv(name: string, typ: untyped, default: untyped): untyped =
    block:
      let val = env[name]
      if val != nil:
        try:
          val.toJson().to(typ)
        except CatchableError as e:
          log lvlError, "In move '" & move & "': Failed to convert env." & name & " (" & $val & ") to typ " & $typ & ": " & e.msg
          default
      else:
        default

  template getArg(index: int, typ: untyped, default: untyped): untyped =
    block:
      if index < args.len:
        try:
          args[index].toJson().to(typ)
        except CatchableError as e:
          log lvlError, "In move '" & move & "': Failed to convert argument " & $index & " to typ " & $typ & ": " & e.msg
          default
      else:
        default

  var count = env.getCount()
  assert count != 0

  let targetColumn = getEnv("target-column", int, 0)
  let includeEol = getEnv("include-eol", bool, true)
  let wrap = getEnv("wrap", bool, true)

  let rope {.cursor.} = displayMap.buffer.visibleText

  if move in self.moves:
    let impl = self.moves[move]
    return impl(rope, move, selections, count, includeEol)

  case move
  of "vim.word":
    result = selections.mapIt(vimMotionWord(rope, it.last, false))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWord(rope, s.last, false) or vimMotionWord(rope, s.first, false)

  of "vim.word-back":
    result = selections.mapIt(vimMotionWordBack(rope, it.last, false))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWordBack(rope, s.first, false)

  of "vim.WORD":
    result = selections.mapIt(vimMotionWordBig(rope, it.last, false))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWordBig(rope, s.last, false) or vimMotionWordBig(rope, s.first, false)

  of "vim.word-inner":
    result = selections.mapIt(vimMotionWord(rope, it.last, false))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWord(rope, s.last, false) or vimMotionWord(rope, s.first, false)

  of "vim.WORD-inner":
    result = selections.mapIt(vimMotionWordBig(rope, it.last, false))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWordBig(rope, s.last, false) or vimMotionWordBig(rope, s.first, false)

  of "reverse":
    return selections.mapIt(it.reverse)

  of "norm":
    return selections.mapIt(it.normalized)

  of "word-line":
    return selections.mapIt:
      let cursor = it.last
      let line = rope.getLine cursor.line
      var res = vimMotionWord(rope, cursor, false)
      if cursor.column == 0 and cursor.line > 0:
        res.first = (cursor.line - 1, rope.lineLen(cursor.line - 1))
      if cursor.column == line.len and cursor.line < rope.lines - 1:
        res.last = (cursor.line + 1, 0)
      res

  of "word-line-back":
    return selections.mapIt:
      let cursor = it.last
      let line = rope.getLine cursor.line
      var res = vimMotionWordBack(rope, cursor, false)
      if cursor.column == 0 and cursor.line > 0:
        res.first = (cursor.line - 1, rope.lineLen(cursor.line - 1))
      if cursor.column == line.len and cursor.line < rope.lines - 1:
        res.last = (cursor.line + 1, 0)
      res

  # of "line-back":
  #   let first = if cursor.line > 0 and cursor.column == 0:
  #     (cursor.line - 1, self.document.lineLength(cursor.line - 1))
  #   else:
  #     (cursor.line, 0)
  #   result = (first, (cursor.line, self.document.lineLength(cursor.line)))

  of "line-num":
    return @[(getArg(0, int, 0), 0).toSelection]

  of "remove-empty":
    result = newSeqOfCap[Selection](selections.len)
    for s in selections:
      if not s.isEmpty:
        result.add s

  of "align", "align-right":
    var maxColumn = 0
    for s in selections:
      maxColumn = max(maxColumn, s.last.column)
    return selections.mapIt((it.last.line, min(rope.lineRange(it.last.line, includeEol).len, maxColumn)).toSelection)

  of "align-left":
    var minColumn = int.high
    for s in selections:
      minColumn = min(minColumn, s.last.column)
    return selections.mapIt((it.last.line, minColumn).toSelection)

  of "split":
    var total = 0
    for s in selections:
      total += (s.last.line - s.first.line).abs + 1
    result = newSeqOfCap[Selection](total)
    for s in selections:
      if s.first.line == s.last.line:
        result.add s
      elif s.isBackwards:
        result.add ((s.first.line, 0), s.first)
        for line in countdown(s.first.line - 1, s.last.line + 1):
          result.add ((line, 0), (line, rope.lineLen(line)))
        result.add (s.last, (s.last.line, rope.lineLen(s.last.line)))
      else:
        result.add (s.first, (s.first.line, rope.lineLen(s.first.line)))
        for line in (s.first.line + 1)..(s.last.line - 1):
          result.add ((line, 0), (line, rope.lineLen(line)))
        result.add ((s.last.line, 0), s.last)

  of "line-start":
    return selections.mapIt((it.last.line, 0).toSelection)

  of "line":
    return selections.mapIt(block:
      let lineLen = rope.lineLen(it.last.line)
      var res: Selection = ((it.last.line, 0), (it.last.line, lineLen))
      if not includeEol and res.last.column == lineLen:
        res.last = rope.moveCursorColumn(res.last, -1, wrap = false)
      res
    )

  of "visual-line":
    return selections.mapIt(block:
      let lineLen = rope.lineLen(it.last.line)
      let wrapPoint = displayMap.toWrapPoint(it.last.toPoint)
      let displayLineStart = wrapPoint(wrapPoint.row)
      let displayLineEnd = wrapPoint(wrapPoint.row + 1)
      var res: Selection = (
        displayMap.toPoint(displayLineStart, Right).toCursor,
        displayMap.toPoint(displayLineEnd, Right).toCursor,
      )
      if res[1].column == 0:
        res[1].line -= 1
        res[1].column = rope.lineLen(res[1].line)

      if not includeEol:
        if res.last.column == lineLen:
          res.last = rope.moveCursorColumn(res.last, -1, wrap = false)
        elif res.last.column < rope.lineLen(it.last.line): # This is the case if we're not in the last visual sub line
          res.last = rope.moveCursorColumn(res.last, -1, wrap = false)

      res
    )

  of "visual-line-up", "visual-line-down", "visual-page":
    var minLine = int.high
    var maxLine = int.low
    for s in selections:
      minLine = min(minLine, s.last.line)
      maxLine = max(maxLine, s.last.line)

    let direction = if move == "visual-line-down":
      count
    elif move == "visual-line-up":
      -count
    else:
      ((count * getEnv("screen-lines", int, 55)) div 100)

    proc doMoveCursor(numSelections: int, cursor: Cursor, offset: int, includeAfter: bool): Cursor =
      let targetColumn = if maxLine - minLine + 1 < numSelections:
        displayMap.toDisplayPoint(cursor.toPoint).column.int
      else:
        targetColumn
      moveCursorVisualLine(displayMap, cursor, offset, false, includeAfter, targetColumn)
    return selections.mapIt(doMoveCursor(selections.len, it.last, direction, includeEol).toSelection)

  # of "line-next":
  #   result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))
  #   if result.last.line + 1 < self.document.numLines:
  #     result.last = (result.last.line + 1, 0)
  #   for _ in 1..<count:
  #     result = result or (
  #       (result.last.line, 0),
  #       (result.last.line, self.document.lineLength(result.last.line))
  #     )
  #     if result.last.line + 1 < self.document.numLines:
  #       result.last = (result.last.line + 1, 0)

  # of "line-prev":
  #   result = ((cursor.line, 0), (cursor.line, self.document.lineLength(cursor.line)))
  #   if result.first.line > 0:
  #     result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))
  #   for _ in 1..<count:
  #     result = result or (Cursor (result.first.line, 0), result.first)
  #     if result.first.line > 0:
  #       result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))

  of "line-no-indent":
    result = selections.mapIt ((it.last.line, rope.indentBytes(it.last.line)), (it.last.line, rope.lineLen(it.last.line)))

  of "file":
    result = @[((0, 0), (rope.lines - 1, rope.lineLen(rope.lines - 1)))]

  of "column":
    let dir = getArg(0, int, 1)
    return selections.mapIt(rope.moveCursorColumn(it.last, count * dir, wrap, includeEol).toSelection)

  of "inclusive":
    return selections.mapIt(if it.isEmpty: it else: (it.first, rope.moveCursorColumn(it.last, -1, false, true)))

  of "line-up", "line-down":
    let direction = if move == "line-down": 1 else: -1
    # return selections.mapIt((it.last, moveCursorLine(rope, displayMap, it.last, direction * count, targetColumn, false, includeEol)))
    return selections.mapIt(moveCursorLine(rope, displayMap, it.last, direction * count, targetColumn, false, includeEol).toSelection)

  of "grow":
    let dir = getArg(0, int, 1) * count
    return selections.mapIt:
      if dir < 0 and it.first.line == it.last.line and abs(it.first.column - it.last.column) < 2:
        it
      else:
        (rope.moveCursorColumn(it.first, -dir, wrap, includeEol), rope.moveCursorColumn(it.last, dir, wrap, includeEol))

  of "number":
    result = selections.mapIt:
      var r = it.last.toPoint...it.last.toPoint
      var c = rope.cursorT(it.last.toPoint)
      while c.currentChar in {'0'..'9'}:
        c.seekNextRune()
        r.b = c.position

      if r.a.column > 0:
        c = rope.cursorT(it.last.toPoint)
        while c.position.column > 0:
          c.seekPrevRune()
          if c.currentChar == '-':
            r.a = c.position
            break

          if c.currentChar notin {'0'..'9'}:
            c.seekNextRune()
            break
          r.a = c.position

      r.toSelection

  of "target-column":
    return selections.mapIt(rope.clampCursor((it.last.line, targetColumn)).toSelection)

  of "surround":
    var c0 = getArg(0, string, "")
    var c1 = getArg(1, string, "")
    let inside = getArg(2, bool, false)
    if c0.len > 0 and c1.len > 0:
      result = selections.mapIt(rope.getSurrounding(it, c0[0], c1[0], inside))
    elif c0.len > 0:
      result = selections.mapIt(rope.getSurrounding(it, c0[0], c0[0], inside))
    else:
      result = selections.mapIt:
        let c = rope.charAt(it.last.toPoint)
        let (open, close, isOpen) = case c
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
        let selection = rope.getSurrounding(it, open, close, inside)
        if isOpen:
          selection
        else:
          selection.reverse

  of "move-to":
    let c = getArg(0, string, "")
    if c.len > 0:
      let r = c.runeAt(0)
      return selections.mapIt((it.first, rope.findNext(it.last, r)))
    return @selections

  else:
    if fallback != nil:
      return fallback(move, selections, count)
    log lvlError, &"Unknown move '{move}'"
    return @selections

proc applyMoveLisp(self: MoveDatabase, displayMap: DisplayMap, move: string, originalSelections: openArray[Selection], env: Env, fallback: MoveFunction): seq[Selection] =
  var env = env
  var baseEnv = self.env.createChild()
  env.parent = baseEnv
  try:
    if self.debugMoves:
      log lvlDebug, &"applyMoveLisp '{move}', {env.env}, {originalSelections}"

    let originalSelections = @originalSelections
    var lastSelections = originalSelections
    var selections = originalSelections

    var expr = move.parseLisp()

    type Selector = enum OriginalStart, OriginalEnd, LastStart, LastEnd, CurrentStart, CurrentEnd
    proc parseSelector(val: LispVal, default: Selector): Selector =
      if val.kind == Symbol:
        case val.sym
        of "orig-start": OriginalStart
        of "orig-end": OriginalEnd
        of "last-start": LastStart
        of "last-end": LastEnd
        of "curr-start": CurrentStart
        of "curr-end": CurrentEnd
        of ".": default
        else:
          log lvlError, &"Unknown cursor selector '{val.sym}'"
          default
      else:
        log lvlError, &"Failed to parse cursor selector '{val}'. Expected Symbol, got {val.kind}"
        default

    proc selectCursor(selector: Selector, i: int, default: Cursor): Cursor =
      case selector
      of OriginalStart:
        if i in 0..<originalSelections.len: originalSelections[i].first else: default
      of OriginalEnd:
        if i in 0..<originalSelections.len: originalSelections[i].last else: default
      of LastStart:
        if i in 0..<lastSelections.len: lastSelections[i].first else: default
      of LastEnd:
        if i in 0..<lastSelections.len: lastSelections[i].last else: default
      of CurrentStart:
        if i in 0..<selections.len: selections[i].first else: default
      of CurrentEnd:
        if i in 0..<selections.len: selections[i].last else: default

    var stack = newSeq[seq[Selection]]()

    baseEnv.onUndefinedSymbol = proc(_: Env, name: string): LispVal =
      template impl(body: untyped): untyped =
        newFunc(name, proc(args {.inject.}: seq[LispVal]): LispVal =
          lastSelections = selections
          body
          if self.debugMoves:
            log lvlDebug, "move '", name, "' ", $lastSelections, " -> ", selections
        )

      case name
      of "num-lines":
        newNumber(displayMap.buffer.visibleText.lines)
      of "num-bytes":
        newNumber(displayMap.buffer.visibleText.bytes)
      of "same?":
        newBool(selections == originalSelections)
      of "original":
        impl:
          selections = originalSelections
      of "push":
        newFunc(name, proc(args {.inject.}: seq[LispVal]): LispVal =
          stack.add selections
        )
      of "pop":
        impl:
          if stack.len > 0:
            selections = stack.pop()
      of "start", "first":
        impl:
          selections = selections.mapIt(it.first.toSelection)
      of "end", "last":
        impl:
          selections = selections.mapIt(it.last.toSelection)
      of "count*":
        newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
          if args.len == 0 or args[0].kind != Number:
            return newNil()
          var count = env.getCount()
          assert count != 0
          env["count"] = newNumber(count.float * args[0].num)
          return newNil()
        )
      of "merge":
        newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
          if selections.len > 0:
            for i in 0..<min(originalSelections.len, selections.len):
              if originalSelections[i].isBackwards:
                if selections[i].isBackwards:
                  let start = max(originalSelections[i].first, selections[i].first)
                  let endd = min(originalSelections[i].last, selections[i].last)
                  selections[i] = (start, endd)
                else:
                  let start = max(originalSelections[i].first, selections[i].last)
                  let endd = min(originalSelections[i].last, selections[i].first)
                  selections[i] = (start, endd)
              else:
                if selections[i].isBackwards:
                  let start = min(originalSelections[i].first, selections[i].last)
                  let endd = max(originalSelections[i].last, selections[i].first)
                  selections[i] = (start, endd)
                else:
                  let start = min(originalSelections[i].first, selections[i].first)
                  let endd = max(originalSelections[i].last, selections[i].last)
                  selections[i] = (start, endd)
        )
      of "join":
        newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
          let startSelector = if args.len > 0:
            parseSelector(args[0], OriginalStart)
          else:
            OriginalStart
          let endSelector = if args.len > 1:
            parseSelector(args[1], CurrentEnd)
          else:
            CurrentEnd

          if selections.len > 0:
            for i in 0..<selections.len:
              let start = selectCursor(startSelector, i, selections[i].last)
              let endd = selectCursor(endSelector, i, selections[i].last)
              selections[i] = (start, endd)
        )
      else:
        impl:
          selections = self.applyMoveImpl(displayMap, name, selections, fallback, args, env)

    discard expr.eval(env)
    return selections
  except CatchableError as e:
    log lvlError, &"Failed to apply move '{move}': {e.msg}"
    return @originalSelections
  finally:
    env.clear()
    baseEnv.clear()

proc applyMove*(self: MoveDatabase, displayMap: DisplayMap, move: string, selections: openArray[Selection], fallback: MoveFunction = nil, env: Env = Env()): seq[Selection] =
  if move.startsWith("("):
    return self.applyMoveLisp(displayMap, move, selections, env, fallback)
  return self.applyMoveLisp(displayMap, "(" & move & ")", selections, env, fallback)

proc registerMove*(self: MoveDatabase, move: string, impl: MoveImpl) =
  log lvlInfo, &"Register custom move '{move}'"
  self.moves[move] = impl
