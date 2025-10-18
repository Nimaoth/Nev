import std/[strutils, sequtils, sugar, options, json, strformat, tables, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as sca import nil
import misc/[util, custom_logger, custom_unicode, myjsonutils, regex, rope_utils, rope_regex, custom_async]
import text/custom_treesitter, text/indent
import config_provider, service
import text/[overlay_map, tab_map, wrap_map, diff_map, display_map]
import nimsumtree/[rope]

{.push gcsafe, raises: [].}

logCategory "moves"

type
  MoveImpl* = proc(rope: Rope, move: string, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.gcsafe, raises: [].}
  MoveDatabase* = ref object of Service
    moves: Table[string, MoveImpl]

func serviceName*(_: typedesc[MoveDatabase]): string = "MoveDatabase"

addBuiltinService(MoveDatabase)

method init*(self: MoveDatabase): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  return ok()

proc vimMotionWord*(text: Rope, cursor: Cursor): Selection =
  const AlphaNumeric = {'A'..'Z', 'a'..'z', '0'..'9', '_'}

  var line = text.getLine(cursor.line)
  if line.len == 0:
    return (cursor.line, 0).toSelection

  let c = line.charAt(cursor.column.clamp(0, line.len - 1))
  if c in Whitespace:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c in Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  elif c in AlphaNumeric:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c in AlphaNumeric)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  else:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c notin Whitespace and c notin AlphaNumeric)
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

proc vimMotionWordBack*(text: Rope, cursor: Cursor): Selection =
  if cursor.column == 0:
    return cursor.toSelection

  let prevCursor = text.clipPoint(point(cursor.line, cursor.column - 1), Left).toCursor
  let current = text.runeAt(cursor.toPoint)
  let prev = text.runeAt(prevCursor.toPoint)
  if current.vimWordCharCategory == prev.vimWordCharCategory:
    return vimMotionWord(text, cursor)
  return vimMotionWord(text, prevCursor)

proc vimMotionWordBig*(text: Rope, cursor: Cursor): Selection =
  var line = text.getLine(cursor.line)
  if line.len == 0:
    return (cursor.line, 0).toSelection

  let c = line.charAt(cursor.column.clamp(0, line.len - 1))
  if c in Whitespace:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c in Whitespace)
    return ((cursor.line, startColumn), (cursor.line, endColumn))

  else:
    let (startColumn, endColumn) = line.getEnclosing(cursor.column, (c) => c notin Whitespace)
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

proc applyMove*(self: MoveDatabase, displayMap: DisplayMap, move: string, selections: openArray[Selection], count: int = 0, includeEol: bool = true): seq[Selection] =
  debugf"applyMove '{move}', {selections}, {count}, {includeEol}"

  let rope {.cursor.} = displayMap.buffer.visibleText

  if move in self.moves:
    let impl = self.moves[move]
    return impl(rope, move, selections, count, includeEol)

  case move
  # of "word":
  #   result = self.findWordBoundary(cursor)
  #   for _ in 1..<count:
  #     result = result or self.findWordBoundary(result.last) or self.findWordBoundary(result.first)

  of "vim.word":
    result = selections.mapIt(vimMotionWord(rope, it.last))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWord(rope, s.last) or vimMotionWord(rope, s.first)

  of "vim.word-back":
    result = selections.mapIt(vimMotionWordBack(rope, it.last))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWordBack(rope, s.first)

  of "vim.WORD":
    result = selections.mapIt(vimMotionWordBig(rope, it.last))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWordBig(rope, s.last) or vimMotionWordBig(rope, s.first)

  of "vim.word-inner":
    result = selections.mapIt(vimMotionWord(rope, it.last))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWord(rope, s.last) or vimMotionWord(rope, s.first)

  of "vim.WORD-inner":
    result = selections.mapIt(vimMotionWordBig(rope, it.last))
    for _ in 1..<count:
      for s in result.mitems:
        s = s or vimMotionWordBig(rope, s.last) or vimMotionWordBig(rope, s.first)

  # of "word-line":
  #   # todo: use RopeCursor
  #   let line = self.document.getLine cursor.line
  #   result = self.findWordBoundary(cursor)
  #   if cursor.column == 0 and cursor.line > 0:
  #     result.first = (cursor.line - 1, self.document.lineLength(cursor.line - 1))
  #   if cursor.column == line.len and cursor.line < self.document.numLines - 1:
  #     result.last = (cursor.line + 1, 0)

  #   for _ in 1..<count:
  #     result = result or self.findWordBoundary(result.last) or self.findWordBoundary(result.first)
  #     let line = self.document.getLine result.last.line
  #     if result.first.column == 0 and result.first.line > 0:
  #       result.first = (result.first.line - 1, self.document.lineLength(result.first.line - 1))
  #     if result.last.column == line.len and result.last.line < self.document.numLines - 1:
  #       result.last = (result.last.line + 1, 0)

  # of "word-back":
  #   return self.getSelectionForMove((cursor.line, max(0, cursor.column - 1)), "word", count).reverse

  # of "word-line-back":
  #   return self.getSelectionForMove((cursor.line, max(0, cursor.column - 1)), "word-line", count).reverse

  # of "number":
  #   var r = cursor.toPoint...cursor.toPoint
  #   var c = self.document.rope.cursorT(cursor.toPoint)
  #   while c.currentChar in {'0'..'9'}:
  #     c.seekNextRune()
  #     r.b = c.position

  #   if r.a.column > 0:
  #     c = self.document.rope.cursorT(cursor.toPoint)
  #     while c.position.column > 0:
  #       c.seekPrevRune()
  #       if c.currentChar == '-':
  #         r.a = c.position
  #         break

  #       if c.currentChar notin {'0'..'9'}:
  #         c.seekNextRune()
  #         break
  #       r.a = c.position

  #   return r.toSelection

  # of "line-back":
  #   let first = if cursor.line > 0 and cursor.column == 0:
  #     (cursor.line - 1, self.document.lineLength(cursor.line - 1))
  #   else:
  #     (cursor.line, 0)
  #   result = (first, (cursor.line, self.document.lineLength(cursor.line)))

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

  # of "file":
  #   result.first = (0, 0)
  #   let line = self.document.numLines - 1
  #   result.last = (line, self.document.lineLength(line))

  of "column":
    return selections.mapIt((it.first, rope.moveCursorColumn(it.last, count, includeEol)))

  # of "prev-find-result":
  #   result = self.getPrevFindResult(cursor, count)

  # of "next-find-result":
  #   result = self.getNextFindResult(cursor, count)

  # of "\"":
  #   result = self.getSelectionInPair(cursor, '"')

  # of "'":
  #   result = self.getSelectionInPair(cursor, '\'')

  # of "(", ")":
  #   result = self.getSelectionInPairNested(cursor, '(', ')')

  # of "{", "}":
  #   result = self.getSelectionInPairNested(cursor, '{', '}')

  # of "[", "]":
  #   result = self.getSelectionInPairNested(cursor, '[', ']')

  else:
    if move.startsWith("move-to "):
      let c = move["move-to ".len..^1]
      if c.len > 0:
        let r = c.runeAt(0)
        return selections.mapIt((it.first, rope.findNext(it.last, r)))

    else:
      log lvlError, &"Unknown move '{move}'"
      return @selections

proc registerMove*(self: MoveDatabase, move: string, impl: MoveImpl) =
  self.moves[move] = impl
