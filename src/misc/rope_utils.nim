import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm]
import nimsumtree/[rope, sumtree]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import custom_async, custom_unicode, util, text/custom_treesitter, regex
import text/diff

{.push gcsafe.}
{.push raises: [].}

func toPoint*(cursor: api.Cursor): Point = Point.init(max(cursor.line, 0), max(cursor.column, 0))
func toPointRange*(selection: Selection): tuple[first, last: Point] = (selection.first.toPoint, selection.last.toPoint)
func toRange*(selection: Selection): Range[Point] = selection.first.toPoint...selection.last.toPoint
func toCursor*(point: Point): api.Cursor = (point.row.int, point.column.int)
func toSelection*(self: (Point, Point)): Selection = (self[0].toCursor, self[1].toCursor)
func toSelection*(self: Range[Point]): Selection = (self.a.toCursor, self.b.toCursor)

proc createRopeThread(args: tuple[str: ptr string, rope: ptr Rope, errorIndex: ptr int]) =
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

type DiffRopesData = object
  rc: Atomic[int]
  a: Rope
  b: Rope
  diff: ptr RopeDiff[int]
  cancel: Atomic[bool]
  threadDone: Atomic[bool]

proc diffRopeThread(data: ptr DiffRopesData) =
  defer:
    if data[].rc.fetchSub(1, moRelease) == 1:
      fence(moAcquire)
      try:
        `=destroy`(data[])
        `=wasMoved`(data[])
      except:
        discard
      freeShared(data)

  discard data[].rc.fetchAdd(1, moRelaxed)

  var a = data.a.clone()
  var b = data.b.clone()
  var d = diff(a, b, data.cancel.addr)
  if not data.cancel.load:
    data.diff[] = d.ensureMove
  data.threadDone.store(true)

proc diffRopeAsync*(a, b: sink Rope, res: ptr RopeDiff[int]): Future[void] {.async.} =
  ## Returns `some(index)` if the string contains invalid utf8 at `index`
  let data = createShared(DiffRopesData)
  data.rc.store(1)
  data.a = a.clone()
  data.b = b.clone()
  data.diff = res
  data.cancel.store(false)
  data.threadDone.store(false)

  defer:
    if data[].rc.fetchSub(1, moRelease) == 1:
      fence(moAcquire)
      try:
        {.gcsafe.}:
          `=destroy`(data[])
          `=wasMoved`(data[])
      except:
        discard
      freeShared(data)

  try:
    await spawnAsync(diffRopeThread, data)
  except CancelledError as e:
    data.cancel.store(true)
    raise e

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


type
  RopeChunk* = object
    data*: ptr UncheckedArray[char]
    len*: int
    point*: Point

  ChunkIterator* = object
    rope: RopeSlice[int]
    cursor: sumtree.Cursor[rope.Chunk, (Point, int)]
    range: Range[int]
    localOffset*: int
    point*: Point
    returnedLastChunk: bool = false

func `$`*(chunk: RopeChunk): string =
  result = newString(chunk.len)
  for i in 0..<chunk.len:
    result[i] = chunk.data[i]

func `[]`*(self: RopeChunk, range: Range[int]): RopeChunk =
  assert range.a >= 0 and range.a <= self.len
  assert range.b >= 0 and range.b <= self.len
  assert range.b >= range.a
  return RopeChunk(
    data: cast[ptr UncheckedArray[char]](self.data[range.a].addr),
    len: range.len,
    point: Point(row: self.point.row, column: self.point.column + range.a.uint32)
  )

template toOpenArray*(self: RopeChunk): openArray[char] = self.data.toOpenArray(0, self.len - 1)
func endPoint*(self: RopeChunk): Point = Point(row: self.point.row, column: self.point.column + self.len.uint32)

proc init*(_: typedesc[ChunkIterator], rope: var RopeSlice[int]): ChunkIterator =
  result.rope = rope.clone()
  result.range = rope.rope.toOffset(rope.range.a)...rope.rope.toOffset(rope.range.b)
  result.cursor = rope.rope.tree.initCursor((Point, int))
  discard result.cursor.seekForward(result.range.a, Bias.Right, ())
  result.point = rope.rope.offsetToPoint(rope.range.a)

proc seekLine*(self: var ChunkIterator, line: int) =
  let point = Point(row: line.uint32)
  discard self.cursor.seekForward(point, Bias.Right, ())
  self.point = point
  self.localOffset = self.rope.rope.pointToOffset(point) - self.cursor.startPos[1]
  # echo &"seekLine {line} -> {self.point}, {self.localOffset}"

proc next*(self: var ChunkIterator): Option[RopeChunk] =
  while true:
    if self.cursor.atEnd:
      if not self.returnedLastChunk:
        self.returnedLastChunk = true
        return RopeChunk(data: nil, len: 0, point: self.point).some
      return

    if self.cursor.item.isNone or self.localOffset >= self.cursor.item.get.chars.len:
      self.cursor.next(())
      self.localOffset = 0

    if self.cursor.item.isSome and self.cursor.startPos[1] < self.range.b:
      let chunk: ptr Chunk = self.cursor.item.get
      while self.localOffset < chunk.chars.len and chunk.chars[self.localOffset] == '\n':
        if self.point.column == 0:
          result = RopeChunk(
            data: cast[ptr UncheckedArray[char]](chunk.chars[self.localOffset].addr),
            len: 0,
            point: self.point,
          ).some
        self.point.row += 1
        self.point.column = 0
        self.localOffset += 1

        if result.isSome:
          return

      assert self.localOffset <= chunk.chars.len
      if self.localOffset == chunk.chars.len:
        continue

      let nextNewLine = chunk.chars(self.localOffset, chunk.chars.len - 1).find('\n')
      var maxEndIndex = if nextNewLine == -1:
        chunk.chars.len
      else:
        self.localOffset + nextNewLine

      assert maxEndIndex >= self.localOffset

      let point = self.point

      var sliceRange = max(self.range.a - self.cursor.startPos[1], 0)...(min(self.range.b, self.cursor.endPos(())[1]) - self.cursor.startPos[1])
      sliceRange.a = max(sliceRange.a, self.localOffset)
      sliceRange.b = min(sliceRange.b, maxEndIndex)
      self.localOffset = sliceRange.b
      self.point.column += sliceRange.len.uint32

      assert sliceRange.a in 0..chunk.chars.len
      assert sliceRange.b in 0..chunk.chars.len
      assert sliceRange.len >= 0
      if sliceRange.len > 0:
        result = RopeChunk(
          data: cast[ptr UncheckedArray[char]](chunk.chars[sliceRange.a].addr),
          len: sliceRange.len,
          point: point,
        ).some
        return

type
  StyledChunk* = object
    chunk*: RopeChunk
    scope*: string

  Highlighter* = object
    query*: TSQuery
    tree*: TsTree

  Highlight = tuple[range: Range[Point], scope: string, priority: int]

  StyledChunkIterator* = object
    chunks*: ChunkIterator
    chunk: Option[RopeChunk]
    localOffset: int
    atEnd: bool
    highlighter*: Option[Highlighter]
    highlights: seq[Highlight]
    highlightsIndex: int = -1

proc init*(_: typedesc[StyledChunkIterator], rope: var RopeSlice[int]): StyledChunkIterator =
  result.chunks = ChunkIterator.init(rope)

func point*(self: StyledChunkIterator): Point = self.chunks.point
func point*(self: StyledChunk): Point = self.chunk.point
func len*(self: StyledChunk): int = self.chunk.len
func `$`*(self: StyledChunk): string = $self.chunk
template toOpenArray*(self: StyledChunk): openArray[char] = self.chunk.toOpenArray

proc seekLine*(self: var StyledChunkIterator, line: int) =
  self.chunks.seekLine(line)
  self.localOffset = 0
  self.highlights.setLen(0)
  self.highlightsIndex = -1
  self.chunk = RopeChunk.none

func contentString(self: var StyledChunkIterator, selection: Range[Point], byteRange: Range[int]): string =
  let currentChunk {.cursor.} = self.chunk.get
  if selection.a >= currentChunk.point and selection.b <= currentChunk.endPoint:
    let startIndex = selection.a.column - currentChunk.point.column
    let endIndex = selection.b.column - currentChunk.point.column
    return $currentChunk[startIndex.int...endIndex.int]
  else:
    result = newStringOfCap(selection.b.column - selection.a.column)
    for slice in self.chunks.rope.rope.iterateChunks(byteRange):
      for c in slice.chars:
        result.add c

proc addHighlight(highlights: var seq[Highlight], nextHighlight: sink Highlight) =
  if highlights.len > 0:
    assert highlights[^1].range.a <= nextHighlight.range.a

    if highlights[^1].range == nextHighlight.range.a...nextHighlight.range.b:
      if nextHighlight.priority > highlights[^1].priority:
        discard highlights.pop()
        highlights.add nextHighlight
      else:
        # Lower priority, ignore
        discard

    else:
      highlights.add nextHighlight

  elif highlights.len == 0 or nextHighlight != highlights[^1]:
    highlights.add nextHighlight

var regexes = initTable[string, Regex]()

proc next*(self: var StyledChunkIterator): Option[StyledChunk] =
  var regexes = ({.gcsafe.}: regexes.addr)

  if self.atEnd:
    return

  template log(msg: untyped) =
    when false:
      if self.chunk.get.point.row == 209:
        echo msg

  if self.chunk.isNone or self.localOffset >= self.chunk.get.len:
    self.chunk = self.chunks.next()
    self.localOffset = 0
    self.highlightsIndex = -1
    self.highlights.setLen(0)
    if self.chunk.isNone:
      self.atEnd = true
      return

    let currentChunk = self.chunk.get
    if self.highlighter.isSome:
      let point = currentChunk.point
      let endPoint = currentChunk.endPoint
      let range = tsRange(tsPoint(point.row.int, point.column.int), tsPoint(endPoint.row.int, endPoint.column.int))
      var matches: seq[TSQueryMatch] = self.highlighter.get.query.matches(self.highlighter.get.tree.root, range)

      var requiresSort = false

      for match in matches:
        let predicates = self.highlighter.get.query.predicatesForPattern(match.pattern)
        for capture in match.captures:
          let node = capture.node
          let byteRange = node.startByte...node.endByte
          let nodeRange = node.startPoint.toCursor.toPoint...node.endPoint.toCursor.toPoint
          if nodeRange.b <= currentChunk.point or nodeRange.a >= currentChunk.endPoint:
            continue

          var matches = true
          for predicate in predicates:
            if not matches:
              break

            for operand in predicate.operands:
              if operand.name != capture.name:
                matches = false
                break

              case predicate.operator
              of "match?":
                if not regexes[].contains(operand.`type`):
                  try:
                    regexes[][operand.`type`] = re(operand.`type`)
                  except RegexError:
                    matches = false
                    break
                let regex {.cursor.} = regexes[][operand.`type`]

                let nodeText = self.contentString(nodeRange, byteRange)
                if nodeText.matchLen(regex, 0) != nodeText.len:
                  matches = false
                  break

              of "not-match?":
                if not regexes[].contains(operand.`type`):
                  try:
                    regexes[][operand.`type`] = re(operand.`type`)
                  except RegexError:
                    matches = false
                    break
                let regex {.cursor.} = regexes[][operand.`type`]

                let nodeText = self.contentString(nodeRange, byteRange)
                if nodeText.matchLen(regex, 0) == nodeText.len:
                  matches = false
                  break

              of "eq?":
                # @todo: second arg can be capture aswell
                let nodeText = self.contentString(nodeRange, byteRange)
                if nodeText != operand.`type`:
                  matches = false
                  break

              of "not-eq?":
                # @todo: second arg can be capture aswell
                let nodeText = self.contentString(nodeRange, byteRange)
                if nodeText == operand.`type`:
                  matches = false
                  break

              # of "any-of?":
              #   # todo
              #   log(lvlError, fmt"Unknown predicate '{predicate.name}'")

              else:
                discard

          if not matches:
            continue

          var nodeRangeClamped = nodeRange
          if nodeRangeClamped.a.row < currentChunk.point.row:
            nodeRangeClamped.a.row = currentChunk.point.row
            nodeRangeClamped.a.column = 0
          if nodeRangeClamped.b.row > currentChunk.point.row:
            nodeRangeClamped.b.row = currentChunk.point.row
            nodeRangeClamped.b.column = uint32.high

          var nextHighlight: Highlight = (nodeRangeClamped, capture.name, match.pattern)
          if self.highlights.len > 0 and nextHighlight.range.a < self.highlights[^1].range.a:
            requiresSort = true
            self.highlights.add(nextHighlight.ensureMove)
          else:
            self.highlights.addHighlight(nextHighlight.ensureMove)

      if requiresSort:
        var highlights = self.highlights
        highlights.sort(proc(a, b: Highlight): int = cmp(a.range.a, b.range.a))
        self.highlights.setLen(0)
        for nextHighlight in highlights.mitems:
          self.highlights.addHighlight(nextHighlight)

  assert self.chunk.isSome
  var currentChunk = self.chunk.get
  if currentChunk.len == 0:
    return StyledChunk(chunk: currentChunk).some

  assert currentChunk.data != nil
  let startOffset = self.localOffset
  let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)

  if self.highlights.len > 0:
    assert currentPoint.row == self.highlights[0].range.a.row
    while self.highlightsIndex + 1 < self.highlights.len:
      let nextHighlight {.cursor.} = self.highlights[self.highlightsIndex + 1]
      assert nextHighlight.range.a.row == currentChunk.point.row
      assert nextHighlight.range.a.row == nextHighlight.range.b.row
      if currentPoint < nextHighlight.range.a:
        self.localOffset = min(currentChunk.len, nextHighlight.range.a.column.int - currentChunk.point.column.int)
        currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
        currentChunk.len = self.localOffset - startOffset
        currentChunk.point.column += startOffset.uint32
        return StyledChunk(chunk: currentChunk).some
      elif currentPoint < nextHighlight.range.b:
        self.localOffset = min(currentChunk.len, nextHighlight.range.b.column.int - currentChunk.point.column.int)
        self.highlightsIndex = self.highlightsIndex + 1
        currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
        currentChunk.len = self.localOffset - startOffset
        currentChunk.point.column += startOffset.uint32
        return StyledChunk(chunk: currentChunk, scope: nextHighlight.scope).some
      else:
        self.highlightsIndex.inc

  self.localOffset = currentChunk.len
  currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
  currentChunk.len = self.localOffset - startOffset
  currentChunk.point.column += startOffset.uint32
  return StyledChunk(chunk: currentChunk).some
