import std/[options, strutils, atomics, tables]
import nimsumtree/[rope, sumtree, buffer, clock]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import custom_async, custom_unicode, util, text/custom_treesitter, regex, timer
import text/diff

export Bias

{.push gcsafe.}
{.push raises: [].}

const debugAllMapUpdates* = false
var debugAllMapUpdatesRT* = true
var debugChunkIterators* = false

type BufferVersionId* = tuple[id: BufferId, version: Global]

template logMapUpdate*(msg: untyped) =
  when debugAllMapUpdates:
    if debugAllMapUpdatesRT:
      debugEcho msg

template logChunkIter*(msg: untyped) =
  when false:
    if debugChunkIterators:
      debugEcho msg

proc versionId*(self: Buffer): BufferVersionId =
  (self.remoteId, self.version)

proc versionId*(self: BufferSnapshot): BufferVersionId =
  (self.remoteId, self.version)

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

func validateOffset*[D](self: RopeSlice[D], offset: int, bias: Bias): int =
  let startOffset = self.rope.toOffset(self.range.a)
  return self.rope.validateOffset(startOffset + offset, bias) - startOffset

func lineRange*[D](self: RopeSlice[D], line: int, includeLineEnd: bool = true): Range[int] =
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

func getLine*(self: Rope, line: int, D: typedesc = int): RopeSlice[D] =
  if line notin 0..<self.lines:
    return Rope.new("").slice(D)

  let lineRange = self.lineRange(line, int)
  return self.slice(lineRange)

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

proc getEnclosing*(text: RopeSlice, column: int, inclusive: bool, predicate: proc(c: char): bool {.gcsafe, raises: [].}): (int, int) =
  var cf = text.cursor(column)
  var cb = cf.clone()
  while cf.offset < text.len:
    cf.seekNextRune()
    if cf.atEnd:
      if inclusive:
        cf.seekPrevRune()
      break
    if not predicate(cf.currentChar()):
      if inclusive:
        cf.seekPrevRune()
      break

  while cb.offset > 0:
    cb.seekPrevRune()
    if not predicate(cb.currentChar()):
      cb.seekNextRune()
      break
  return (cb.offset, cf.offset)

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

template defineCustomPoint*(name: untyped) =
  type name* {.borrow: `.`.} = distinct Point
  func diffPoint*(row: Natural = 0, column: Natural = 0): name = Point(row: row.uint32, column: column.uint32).name
  func `$`*(a: name): string {.borrow.}
  func `<`*(a: name, b: name): bool {.borrow.}
  func `<=`*(a: name, b: name): bool {.borrow.}
  func `==`*(a: name, b: name): bool {.borrow.}
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
