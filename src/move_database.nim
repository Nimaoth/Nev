import std/[strutils, sequtils, sugar, options, json, strformat, tables, algorithm]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as sca import nil
import misc/[util, custom_logger, custom_unicode, myjsonutils, regex, rope_utils, rope_regex, custom_async]
import text/custom_treesitter, text/indent
import config_provider, service
# import text/[overlay_map, tab_map, wrap_map, diff_map, display_map]
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

proc applyMove*(self: MoveDatabase, rope: Rope, move: string, selections: openArray[Selection], count: int = 0, includeEol: bool = true): seq[Selection] =
  debugf"applyMove '{move}', {selections}, {count}, {includeEol}"

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

  # of "line":
  #   let lineLen = self.document.lineLength(cursor.line)
  #   result = ((cursor.line, 0), (cursor.line, lineLen))
  #   if not includeEol and result.last.column == lineLen:
  #     result.last = self.doMoveCursorColumn(result.last, -1, wrap = false)

  # of "visual-line":
  #   let lineLen = self.document.lineLength(cursor.line)
  #   let wrapPoint = self.displayMap.toWrapPoint(cursor.toPoint)
  #   let displayLineStart = wrapPoint(wrapPoint.row)
  #   let displayLineEnd = wrapPoint(wrapPoint.row + 1)
  #   result[0] = self.displayMap.toPoint(displayLineStart, Right).toCursor
  #   result[1] = self.displayMap.toPoint(displayLineEnd, Right).toCursor
  #   if result[1].column == 0:
  #     result[1].line -= 1
  #     result[1].column = self.document.lineLength(result[1].line)

  #   if not includeEol:
  #     if result.last.column == lineLen:
  #       result.last = self.doMoveCursorColumn(result.last, -1, wrap = false)
  #     elif result.last.column < self.document.lineLength(cursor.line): # This is the case if we're not in the last visual sub line
  #       result.last = self.doMoveCursorColumn(result.last, -1, wrap = false)

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

  # of "line-no-indent":
  #   let indent = self.document.rope.indentBytes(cursor.line)
  #   result = ((cursor.line, indent), (cursor.line, self.document.lineLength(cursor.line)))

  # of "file":
  #   result.first = (0, 0)
  #   let line = self.document.numLines - 1
  #   result.last = (line, self.document.lineLength(line))

  # of "column":
  #   result = self.doMoveCursorColumn(cursor, count, includeAfter = includeEol).toSelection

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
      discard
    #   # todo: use RopeCursor
    #   let str = move[8..^1]
    #   let line = self.document.getLine cursor.line
    #   result = cursor.toSelection
    #   let index = line.suffix(cursor.column).find(str)
    #   if index >= 0:
    #     result.last = (cursor.line, index + 1 + cursor.column)
    #   for _ in 1..<count:
    #     let index = line.suffix(result.last.column).find(str)
    #     if index >= 0:
    #       result.last = (result.last.line, index + 1 + result.last.column)

    # elif move.startsWith("move-before "):
    #   # todo: use RopeCursor
    #   let str = move[12..^1]
    #   let line = self.document.getLine cursor.line
    #   result = cursor.toSelection
    #   let index = line.suffix(cursor.column + 1).find(str)
    #   if index >= 0:
    #     result.last = (cursor.line, index + cursor.column + 1)
    #   for _ in 1..<count:
    #     let index = line.suffix(result.last.column + 1).find(str)
    #     if index >= 0:
    #       result.last = (result.last.line, index + result.last.column + 1)

    else:
      log lvlError, &"Unknown move '{move}'"
      return @selections

proc registerMove*(self: MoveDatabase, move: string, impl: MoveImpl) =
  self.moves[move] = impl
