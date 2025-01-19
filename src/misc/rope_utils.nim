import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm]
import nimsumtree/[rope, sumtree, buffer, clock]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import custom_async, custom_unicode, util, text/custom_treesitter, regex, timer, event
import text/diff

export Bias

{.push gcsafe.}
{.push raises: [].}

var debugMapUpdates* = true
var debugChunkIterators* = false

template logMapUpdate*(msg: untyped) =
  when false:
    if debugMapUpdates:
      echo msg

template logChunkIter*(msg: untyped) =
  when false:
    if debugChunkIterators:
      echo msg

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
    # debugEcho &"lineRange {line} -> {lineRange}"
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

proc findAllBounds*(str: string, line: int, regex: Regex): seq[Selection] =
  var start = 0
  while start < str.len:
    let bounds = str.findBounds(regex, start)
    if bounds.first == -1:
      break
    result.add ((line, bounds.first), (line, bounds.last + 1))
    start = bounds.last + 1

proc findAll*(rope: Rope, searchQuery: string, res: var seq[Range[Point]]) =
  try:
    let r = re(searchQuery)
    for line in 0..rope.summary.lines.row.int:
      let lineRange = rope.lineRange(line, int)
      let selections = ($rope.slice(lineRange)).findAllBounds(line, r)
      for s in selections:
        res.add s.first.toPoint...s.last.toPoint
  except RegexError:
    discard

proc findAll*(rope: Rope, searchQuery: string): seq[Range[Point]] =
  findAll(rope, searchQuery, result)

proc findAllThread(args: tuple[rope: ptr Rope, query: string, res: ptr seq[Range[Point]]]) =
  findAll(args.rope[].clone(), args.query, args.res[])

proc findAllAsync*(rope: sink Rope, searchQuery: string): Future[seq[Range[Point]]] {.async.} =
  ## Returns `some(index)` if the string contains invalid utf8 at `index`
  var res = newSeq[Range[Point]]()
  var rope = rope.move
  await spawnAsync(findAllThread, (rope.addr, searchQuery, res.addr))
  return res
  # ababa

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

proc binarySearchRange*[T, K](a: openArray[T], key: K, bias: Bias,
                         cmp: proc (x: T, y: K): int {.closure.}): (bool, int) {.effectsOf: cmp.} =
  ## Binary search for `key` in `a`. Return the index of `key` and whether is was found
  ## Assumes that `a` is sorted according to `cmp`.
  ##
  ## `cmp` is the comparator function to use, the expected return values are
  ## the same as those of system.cmp.
  runnableExamples:
    assert binarySearchRange(["a", "b", "c", "d"], "d", system.cmp[string]) == 3
    assert binarySearchRange(["a", "b", "c", "d"], "c", system.cmp[string]) == 2
  let len = a.len

  if len == 0:
    return (false, 0)

  if len == 1:
    if cmp(a[0], key) == 0:
      return (true, 0)
    else:
      return (false, 0)

  result = (true, 0)

  var idx = 0
  if (len and (len - 1)) == 0:
    # when `len` is a power of 2, a faster shr can be used.
    var step = len shr 1
    var cmpRes: int
    while step > 0:
      let i = idx or step
      cmpRes = cmp(a[i], key)
      if cmpRes == 0:
        if bias == Bias.Right and i + 1 < len and cmp(a[i + 1], key) == 0:
          return (true, i + 1)
        if bias == Bias.Left and i - 1 >= 0 and cmp(a[i - 1], key) == 0:
          return (true, i - 1)
        return (true, i)

      if cmpRes < 0:
        idx = i
      step = step shr 1

    let final = cmp(a[idx], key)
    result[0] = final == 0
    if final < 0 and bias == Bias.Right:
      idx = min(idx + 1, len - 1)
    elif final > 0 and bias == Bias.Left:
      idx = max(idx - 1, 0)
  else:
    var b = len
    var cmpRes: int
    while idx < b:
      var mid = (idx + b) shr 1
      cmpRes = cmp(a[mid], key)
      if cmpRes == 0:
        if bias == Bias.Right and mid + 1 < len and cmp(a[mid + 1], key) == 0:
          return (true, mid + 1)
        if bias == Bias.Left and mid - 1 >= 0 and cmp(a[mid - 1], key) == 0:
          return (true, mid - 1)
        return (true, mid)

      if cmpRes < 0:
        idx = mid + 1
      else:
        b = mid

    if idx >= len:
      result[0] = false
      if bias == Bias.Left:
        idx = max(idx - 1, 0)

    else:
      let final = cmp(a[idx], key)
      result[0] = final == 0
      if final < 0 and bias == Bias.Right:
        idx = min(idx + 1, len - 1)
      elif final > 0 and bias == Bias.Left:
        idx = max(idx - 1, 0)

  result[1] = idx


type
  RopeChunk* = object
    data*: ptr UncheckedArray[char]
    len*: int
    point*: Point
    external*: bool

  ChunkIterator* = object
    rope: Rope
    cursor: sumtree.Cursor[rope.Chunk, (Point, int)]
    localOffset*: int
    point*: Point
    returnedLastChunk: bool = false

func endPoint*(self: RopeChunk): Point = Point(row: self.point.row, column: self.point.column + self.len.uint32)

func `$`*(chunk: RopeChunk): string =
  result = newString(chunk.len)
  for i in 0..<chunk.len:
    result[i] = chunk.data[i]
  result = &"RC({chunk.point}...{chunk.endPoint}, '{result}')"

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

proc init*(_: typedesc[ChunkIterator], rope: var Rope): ChunkIterator =
  result.rope = rope.clone()
  result.cursor = rope.tree.initCursor((Point, int))

proc seekLine*(self: var ChunkIterator, line: int) =
  let point = Point(row: line.uint32)
  assert point >= self.cursor.startPos[0]
  discard self.cursor.seekForward(point, Bias.Right, ())
  self.point = point
  self.localOffset = self.rope.pointToOffset(point) - self.cursor.startPos[1]
  assert self.localOffset >= 0

proc seek*(self: var ChunkIterator, point: Point) =
  assert point >= self.cursor.startPos[0]
  # echo &"ChunkIterator.seek {self.cursor.startPos[0]} -> {point}"
  discard self.cursor.seekForward(point, Bias.Right, ())
  self.point = point
  self.localOffset = self.rope.pointToOffset(point) - self.cursor.startPos[1]
  assert self.localOffset >= 0

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

    if self.cursor.item.isSome and self.cursor.startPos[1] < self.rope.summary.bytes:
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
        assert self.localOffset >= 0

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

      let sliceRange = self.localOffset...min(self.cursor.endPos[1] - self.cursor.startPos[1], maxEndIndex)
      self.localOffset = sliceRange.b
      assert self.localOffset >= 0
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
    drawWhitespace*: bool = true

  Highlighter* = object
    query*: TSQuery
    tree*: TsTree

  Highlight = tuple[range: Range[Point], scope: string, priority: int]

  DisplayPoint* {.borrow: `.`.} = distinct Point

  StyledChunkIterator* = object
    chunks*: ChunkIterator
    chunk: Option[RopeChunk]
    localOffset: int
    atEnd: bool
    highlighter*: Option[Highlighter]
    highlights: seq[Highlight]
    highlightsIndex: int = -1

func displayPoint*(row: Natural = 0, column: Natural = 0): DisplayPoint = Point(row: row.uint32, column: column.uint32).DisplayPoint
func `$`*(a: DisplayPoint): string {.borrow.}
func `<`*(a: DisplayPoint, b: DisplayPoint): bool {.borrow.}
func `<=`*(a: DisplayPoint, b: DisplayPoint): bool {.borrow.}
func `+`*(a: DisplayPoint, b: DisplayPoint): DisplayPoint {.borrow.}
func `+`*(point: DisplayPoint, diff: PointDiff): DisplayPoint {.borrow.}
func `+=`*(a: var DisplayPoint, b: DisplayPoint) {.borrow.}
func `+=`*(point: var DisplayPoint, diff: PointDiff) {.borrow.}
func `-`*(a: DisplayPoint, b: DisplayPoint): PointDiff {.borrow.}
func dec*(a: var DisplayPoint): DisplayPoint {.borrow.}
func pred*(a: DisplayPoint): DisplayPoint {.borrow.}
func clone*(a: DisplayPoint): DisplayPoint {.borrow.}
func cmp*(a: DisplayPoint, b: DisplayPoint): int {.borrow.}
func clamp*(p: DisplayPoint, r: Range[DisplayPoint]): DisplayPoint = min(max(p, r.a), r.b)
converter toDisplayPoint*(diff: PointDiff): DisplayPoint = diff.toPoint.DisplayPoint

proc init*(_: typedesc[StyledChunkIterator], rope: var Rope): StyledChunkIterator =
  result.chunks = ChunkIterator.init(rope)

func point*(self: StyledChunkIterator): Point = self.chunks.point
func point*(self: StyledChunk): Point = self.chunk.point
func endPoint*(self: StyledChunk): Point = self.chunk.endPoint
func len*(self: StyledChunk): int = self.chunk.len
func `$`*(self: StyledChunk): string = &"SC({self.chunk}, {self.scope}, {self.drawWhitespace})"
template toOpenArray*(self: StyledChunk): openArray[char] = self.chunk.toOpenArray

proc seekLine*(self: var StyledChunkIterator, line: int) =
  self.chunks.seekLine(line)
  self.localOffset = 0
  self.highlights.setLen(0)
  self.highlightsIndex = -1
  self.chunk = RopeChunk.none

proc seek*(self: var StyledChunkIterator, point: Point) =
  self.chunks.seek(point)
  self.localOffset = 0 # todo: does this need to be != 0?
  self.highlights.setLen(0)
  self.highlightsIndex = -1
  self.chunk = RopeChunk.none

func contentString(self: var StyledChunkIterator, selection: Range[Point], byteRange: Range[int], maxLen: int): string =
  let currentChunk {.cursor.} = self.chunk.get
  if selection.a >= currentChunk.point and selection.b <= currentChunk.endPoint:
    let startIndex = selection.a.column - currentChunk.point.column
    let endIndex = selection.b.column - currentChunk.point.column
    return $currentChunk[startIndex.int...endIndex.int]
  else:
    result = newStringOfCap(min(selection.b.column.int - selection.a.column.int, maxLen))
    for slice in self.chunks.rope.iterateChunks(byteRange):
      for c in slice.chars:
        result.add c
        if result.len == maxLen:
          return

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

  # Max length of a node used for checking predicates like #match?
  # Nodes longer than that will not be highlighted correctly, but those should be very rare
  # and since it's just syntax highlighting this is not super critical,
  # and this way we avoid bad performance for some these cases.
  const maxPredicateCheckLen = 128

  # todo: escapes in nim strings might cause overlapping captures
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
          if nodeRange.a.row !=  nodeRange.b.row:
            matches = false

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

                let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
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

                let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                if nodeText.matchLen(regex, 0) == nodeText.len:
                  matches = false
                  break

              of "eq?":
                # @todo: second arg can be capture aswell
                let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                if nodeText != operand.`type`:
                  matches = false
                  break

              of "not-eq?":
                # @todo: second arg can be capture aswell
                let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
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
        assert self.localOffset >= 0
        currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
        currentChunk.len = self.localOffset - startOffset
        currentChunk.point.column += startOffset.uint32
        return StyledChunk(chunk: currentChunk).some
      elif currentPoint < nextHighlight.range.b:
        self.localOffset = min(currentChunk.len, nextHighlight.range.b.column.int - currentChunk.point.column.int)
        assert self.localOffset >= 0
        self.highlightsIndex = self.highlightsIndex + 1
        currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
        currentChunk.len = self.localOffset - startOffset
        currentChunk.point.column += startOffset.uint32
        return StyledChunk(chunk: currentChunk, scope: nextHighlight.scope).some
      else:
        self.highlightsIndex.inc

  self.localOffset = currentChunk.len
  assert self.localOffset >= 0
  currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
  currentChunk.len = self.localOffset - startOffset
  currentChunk.point.column += startOffset.uint32
  return StyledChunk(chunk: currentChunk).some

template defineCustomPoint*(name: untyped) =
  type name* {.borrow: `.`.} = distinct Point
  func diffPoint*(row: Natural = 0, column: Natural = 0): name = Point(row: row.uint32, column: column.uint32).name
  func `$`*(a: name): string {.borrow.}
  func `<`*(a: name, b: name): bool {.borrow.}
  func `<=`*(a: name, b: name): bool {.borrow.}
  func `+`*(a: name, b: name): name {.borrow.}
  func `+`*(point: name, diff: PointDiff): name {.borrow.}
  func `+=`*(a: var name, b: name) {.borrow.}
  func `+=`*(point: var name, diff: PointDiff) {.borrow.}
  func `-`*(a: name, b: name): PointDiff {.borrow.}
  func dec*(a: var name): name {.borrow.}
  func pred*(a: name): name {.borrow.}
  func clone*(a: name): name {.borrow.}
  func cmp*(a: name, b: name): int {.borrow.}
  func clamp*(p: name, r: Range[name]): name = min(max(p, r.a), r.b)
  converter toDiffPoint*(diff: PointDiff): name = diff.toPoint.name
