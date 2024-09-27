import std/[options, strutils]
import nimsumtree/[rope, sumtree]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import custom_async, custom_unicode, util

{.push gcsafe.}
{.push raises: [].}

func toPoint*(cursor: api.Cursor): Point = Point.init(cursor.line, cursor.column)
func toPointRange*(selection: Selection): tuple[first, last: Point] = (selection.first.toPoint, selection.last.toPoint)
func toRange*(selection: Selection): Range[Point] = selection.first.toPoint...selection.last.toPoint
func toCursor*(point: Point): api.Cursor = (point.row.int, point.column.int)
func toSelection*(self: (Point, Point)): Selection = (self[0].toCursor, self[1].toCursor)
func toSelection*(self: Range[Point]): Selection = (self.a.toCursor, self.b.toCursor)

proc createRopeThread(args: tuple[str: ptr string, rope: ptr Rope, errorIndex: ptr int]) {.gcsafe.} =
  template content: openArray[char] = args.str[].toOpenArray(0, args.str[].high)
  let invalidUtf8Index = content.validateUtf8
  if invalidUtf8Index >= 0:
    args.errorIndex[] = invalidUtf8Index
    return

  var index = 0
  const utf8_bom = "\xEF\xBB\xBF"
  if args.str[].len >= 3 and content[0..<3] == utf8_bom.toOpenArray(0, utf8_bom.high):
    index = 3

  args.rope[] = Rope.new(content[index..^1])
  args.errorIndex[] = -1
  return

proc createRopeAsync*(str: ptr string, rope: ptr Rope): Future[Option[int]] {.async.} =
  ## Returns `some(index)` if the string contains invalid utf8 at `index`
  var errorIndex = -1
  await spawnAsync(createRopeThread, (str, rope, errorIndex.addr))
  if errorIndex != -1:
    return errorIndex.some
  return int.none

######################################################################### Rope api only, maybe move to rope library later

func toCharsInLine*[D](self: Rope, position: D): Count =
  let point = self.convert(position, Point)
  if point.row.int notin 0..<self.lines:
    return 0.Count

  var c = self.cursorT(Point.init(point.row, 0))
  return c.summary(Count, point)

func toOffsetInLine*(self: Rope, line: int, count: Count): int =
  if line notin 0..<self.lines:
    return 0

  var c = self.cursorT(Point.init(0, 0))
  let totalCount = c.summary(Count, Point.init(line, 0))
  let offset = self.countToOffset(totalCount + count)
  return offset - c.offset

func lineRange*(self: Rope, line: int, includeLineEnd: bool = true): Range[int] =
  ## Returns a the range of the given line. If `includeLineEnd` is true then the end of the range will
  ## be the index of the newline character (used for a selection with an _exclusive_ end cursor),
  ## if `includeLineEnd` is false and the line is not empty then the end of the range will be before the last character
  ## (used for a selection with an _inclusive_ end cursor).

  if line in 0..<self.lines:
    var lineRange = self.lineRange(line, int)
    if not includeLineEnd and lineRange.a < lineRange.b:
      lineRange.b = self.validateOffset(lineRange.b.pred(), Bias.Left)

    return lineRange

  return 0...0

func indentRange*(self: RopeSlice, line: int, D: typedesc): Range[D] =
  if line < 0 or line >= self.lines:
    return D.default...D.default

  var c = self.cursor(Point.init(line, 0))
  result.a = self.convert(c.position, D)
  while not c.atEnd:
    let r = c.currentRune
    if not r.isWhitespace or r == '\n'.Rune:
      break
    c.seekNextRune()
  result.b = self.convert(c.position, D)

func indentedRange*(self: RopeSlice, line: int, D: typedesc = int): Range[D] =
  if line < 0 or line >= self.lines:
    return D.default...D.default

  var c = self.cursor(Point.init(line, 0))
  while not c.atEnd:
    let r = c.currentRune
    if not r.isWhitespace or r == '\n'.Rune:
      break
    c.seekNextRune()

  result.a = self.convert(c.position, D)

  c.seekForward(Point.init(line + 1, 0))
  result.b = self.convert(c.position, D)

  if c.currentRune == '\n'.Rune and result.b > result.a:
    c.seekPrevRune()
    result.b = self.convert(c.position, D)

func isEmptyOrWhitespace*[D](self: RopeSlice[D]): bool =
  if self.len == 0:
    return true
  for slice in self.iterateChunks:
    for c in slice.chars.runes:
      if not c.isWhitespace:
        return false

  return true

######################################################################### Internal api wrappers

func runeIndexInLine*(self: Rope, cursor: api.Cursor): RuneIndex =
  return self.toCharsInLine(cursor.toPoint).int.RuneIndex

func byteOffsetInLine*(self: Rope, line: int, index: RuneIndex): int =
  return self.toOffsetInLine(line, index.int.Count)

func lastValidIndex*(self: Rope, line: int, includeLineEnd: bool = true): int =
  return self.lineRange(line, includeLineEnd).len

func indentBytes*(self: Rope, line: int): int =
  ## Returns the length of the indentation of the given line in bytes
  return self.indentRange(line, int).len

func indentRunes*(self: Rope, line: int): RuneIndex =
  ## Returns the length of the indentation of the given line in runes
  return self.indentRange(line, Count).len.int.RuneIndex

func firstNonWhitespace*(self: RopeSlice): int =
  ## Byte offset of the first non whitespace character
  return self.indentRange(0, int).len

func runeIndex*(self: RopeSlice, offset: int): RuneIndex =
  ## Convert byte offset to rune index
  return self.convert(offset, Count).RuneIndex

proc lineStartsWith*(self: Rope, line: int, text: string, ignoreWhitespace: bool): bool =
  let lineRange = if ignoreWhitespace:
    self.indentedRange(line, int)
  else:
    self.lineRange(line, int)

  let lineSlice = self.slice(lineRange)
  return lineSlice.startsWith(text)
