import std/[options, atomics, strformat, tables]
import nimsumtree/[rope, buffer, clock]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import diff, syntax_map, overlay_map, wrap_map
import nimsumtree/sumtree except mapIt

type InputMapSnapshot = WrapMapSnapshot
type InputChunkIterator = WrapChunkIterator
type InputChunk = WrapChunk
type InputPoint = WrapPoint
proc inputPoint(row: Natural = 0, column: Natural = 0): InputPoint {.inline.} = wrapPoint(row, column)
proc toInputPoint(d: PointDiff): InputPoint {.inline.} = d.toWrapPoint

var debugDiffMap* = false

{.push gcsafe.}
{.push raises: [].}

type DiffPoint* {.borrow: `.`.} = distinct Point
func diffPoint*(row: Natural = 0, column: Natural = 0): DiffPoint = Point(row: row.uint32, column: column.uint32).DiffPoint
func `$`*(a: DiffPoint): string {.borrow.}
func `<`*(a: DiffPoint, b: DiffPoint): bool {.borrow.}
func `<=`*(a: DiffPoint, b: DiffPoint): bool {.borrow.}
func `+`*(a: DiffPoint, b: DiffPoint): DiffPoint {.borrow.}
func `+`*(point: DiffPoint, diff: PointDiff): DiffPoint {.borrow.}
func `+=`*(a: var DiffPoint, b: DiffPoint) {.borrow.}
func `+=`*(point: var DiffPoint, diff: PointDiff) {.borrow.}
func `-`*(a: DiffPoint, b: DiffPoint): PointDiff {.borrow.}
func dec*(a: var DiffPoint): DiffPoint {.borrow.}
func pred*(a: DiffPoint): DiffPoint {.borrow.}
func clone*(a: DiffPoint): DiffPoint {.borrow.}
func cmp*(a: DiffPoint, b: DiffPoint): int {.borrow.}
func clamp*(p: DiffPoint, r: Range[DiffPoint]): DiffPoint = min(max(p, r.a), r.b)
converter toDiffPoint*(diff: PointDiff): DiffPoint = diff.toPoint.DiffPoint

type
  DiffChunk* = object
    inputChunk*: InputChunk
    diffPoint*: DiffPoint

func point*(self: DiffChunk): Point {.inline.} = self.inputChunk.point
func endPoint*(self: DiffChunk): Point {.inline.} = self.inputChunk.endPoint
func diffEndPoint*(self: DiffChunk): DiffPoint {.inline.} = diffPoint(self.diffPoint.row, self.diffPoint.column + self.inputChunk.len.uint32)
func endDiffPoint*(self: DiffChunk): DiffPoint {.inline.} = diffPoint(self.diffPoint.row, self.diffPoint.column + self.inputChunk.len.uint32)
func len*(self: DiffChunk): int {.inline.} = self.inputChunk.len
func `$`*(self: DiffChunk): string {.inline.} = &"DC({self.diffPoint}...{self.endDiffPoint}, {self.inputChunk})"
template toOpenArray*(self: DiffChunk): openArray[char] = self.inputChunk.toOpenArray
template scope*(self: DiffChunk): string = self.inputChunk.scope

proc split*(self: DiffChunk, index: int): tuple[prefix: DiffChunk, suffix: DiffChunk] =
  let (prefix, suffix) = self.inputChunk.split(index)
  (
    DiffChunk(inputChunk: prefix, diffPoint: self.diffPoint),
    DiffChunk(inputChunk: suffix, diffPoint: diffPoint(self.diffPoint.row, self.diffPoint.column + index.uint32)),
  )

type
  DiffMapChunk* = object
    summary*: DiffMapChunkSummary

  DiffMapChunkSummary* = object
    src*: uint32
    dst*: uint32

  DiffMapChunkSrc* = distinct uint32
  DiffMapChunkDst* = distinct uint32

# Make DiffMapChunk an Item
func clone*(self: DiffMapChunk): DiffMapChunk = self

func summary*(self: DiffMapChunk): DiffMapChunkSummary = self.summary

func fromSummary*[C](_: typedesc[DiffMapChunkSummary], self: DiffMapChunkSummary, cx: C): DiffMapChunkSummary = self

# Make DiffMapChunkSummary a Summary
func addSummary*[C](self: var DiffMapChunkSummary, b: DiffMapChunkSummary, cx: C) =
  self.src += b.src
  self.dst += b.dst

# Make DiffMapChunkDst a Dimension
func cmp*[C](a: DiffMapChunkDst, b: DiffMapChunkSummary, cx: C): int = cmp(a.uint32, b.dst)

# Make DiffMapChunkSrc a Dimension
func cmp*[C](a: DiffMapChunkSrc, b: DiffMapChunkSummary, cx: C): int = cmp(a.uint32, b.src)

type
  DiffMapChunkCursor* = sumtree.Cursor[DiffMapChunk, DiffMapChunkSummary]

  DiffMapSnapshot* = object
    map*: SumTree[DiffMapChunk]
    version*: int
    input*: InputMapSnapshot
    otherInput*: InputMapSnapshot
    mappings*: Option[seq[LineMapping]] # todo: this is not thread safe
    reverse*: bool

  DiffMap* = ref object
    snapshot*: DiffMapSnapshot
    # pendingEdits: seq[tuple[buffer: InputMapSnapshot, patch: Patch[InputPoint]]]
    updatingAsync: bool
    onUpdated*: Event[tuple[map: DiffMap, old: DiffMapSnapshot]]

  DiffChunkIterator* = object
    inputChunks*: InputChunkIterator
    diffChunk*: Option[DiffChunk]
    diffMap* {.cursor.}: DiffMapSnapshot
    diffMapCursor: DiffMapChunkCursor
    diffPoint*: DiffPoint
    atEnd*: bool

func clone*(self: DiffMapSnapshot): DiffMapSnapshot =
  var otherInput: InputMapSnapshot
  if not self.otherInput.map.isNil:
    otherInput = self.otherInput.clone()
  DiffMapSnapshot(map: self.map.clone(), input: self.input.clone(), otherInput: otherInput, mappings: self.mappings, reverse: self.reverse, version: self.version)

proc new*(_: typedesc[DiffMap]): DiffMap =
  result = DiffMap(snapshot: DiffMapSnapshot(map: SumTree[DiffMapChunk].new([DiffMapChunk()])))

proc iter*(diffMap: var DiffMapSnapshot): DiffChunkIterator =
  result = DiffChunkIterator(
    inputChunks: diffMap.input.iter(),
    diffMap: diffMap.clone(),
    diffMapCursor: diffMap.map.initCursor(DiffMapChunkSummary),
  )

func point*(self: DiffChunkIterator): Point = self.inputChunks.point
template styledChunk*(self: DiffChunk): StyledChunk = self.inputChunk.styledChunk
func styledChunks*(self: var DiffChunkIterator): var StyledChunkIterator {.inline.} = self.inputChunks.styledChunks
func styledChunks*(self: DiffChunkIterator): StyledChunkIterator {.inline.} = self.inputChunks.styledChunks

func isNil*(self: DiffMapSnapshot): bool = self.map.isNil

proc desc*(self: DiffMapSnapshot): string =
  result = &"DiffMapSnapshot(@{self.version}, {self.map.summary}, {self.input.desc}"
  # if not self.otherInput.map.isNil:
  #   result.add &", {self.otherInput.desc}"
  result.add ")"

proc `$`*(self: DiffMapSnapshot): string =
  result.add "diff map\n"
  var c = self.map.initCursor(DiffMapChunkSummary)
  var i = 0
  while not c.atEnd:
    c.next()
    if c.item.getSome(item):
      let r = c.startPos.src...c.endPos.src
      let rd = c.startPos.dst...c.endPos.dst
      if item.summary.src != 0 or true:
        result.add &"  {i}: {item.summary.src} -> {item.summary.dst}   |   {r} -> {rd}\n"
        inc i

proc toDiffPoint*(self: DiffMapChunkCursor, point: InputPoint): DiffPoint =
  assert point.row in self.startPos.src...self.endPos.src
  # if self.startPos.dst == self.endPos.dst:
  #   return diffPoint(self.startPos.dst)
  # let point2 = point.row.clamp(self.startPos.src...self.endPos.src)
  let offset = point - inputPoint(self.startPos.src)
  return (diffPoint(self.startPos.dst) + offset.toDiffPoint)

proc toDiffPoint*(self: DiffMapSnapshot, point: InputPoint, bias: Bias = Bias.Right): DiffPoint =
  var c = self.map.initCursor(DiffMapChunkSummary)
  discard c.seek(point.row.DiffMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.summary.src == 0:
    c.next()

  return c.toDiffPoint(point)

# proc toDiffPoint*(self: DiffMapSnapshot, point: Point, bias: Bias = Bias.Right): DiffPoint =
#   return self.toDiffPoint(self.input.toOutputPoint(point, bias))

# proc toDiffPoint*(self: DiffMap, point: Point, bias: Bias = Bias.Right): DiffPoint =
#   self.snapshot.toDiffPoint(point, bias)

proc toDiffPoint*(self: DiffMap, point: InputPoint, bias: Bias = Bias.Right): DiffPoint =
  self.snapshot.toDiffPoint(point, bias)

proc toInputPoint*(self: DiffMapChunkCursor, point: DiffPoint): InputPoint =
  assert point.row in self.startPos.dst...self.endPos.dst
  if self.startPos.src == self.endPos.src:
    return inputPoint(self.startPos.src)

  let offset = point - diffPoint(self.startPos.dst)
  return (inputPoint(self.startPos.src) + offset.toInputPoint)

proc toInputPoint*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Left): InputPoint =
  var c = self.map.initCursor(DiffMapChunkSummary)
  discard c.seek(point.row.DiffMapChunkDst, bias, ())
  if c.item.getSome(item) and item.summary.dst == 0:
    c.next()

  return c.toInputPoint(point)

proc isEmptySpace*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Right): bool =
  var c = self.map.initCursor(DiffMapChunkSummary)
  discard c.seek(point.row.DiffMapChunkDst, bias, ())
  if c.item.getSome(item) and item.summary.dst == 0:
    c.next()

  return c.startPos.src == c.endPos.src

# proc toPoint*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Right): Point =
#   return self.input.toPoint(self.toInputPoint(point, bias), bias)

# proc toPoint*(self: DiffMap, point: DiffPoint, bias: Bias = Bias.Right): Point =
#   self.snapshot.toPoint(point, bias)

proc toInputPoint*(self: DiffMap, point: DiffPoint, bias: Bias = Bias.Right): InputPoint =
  self.snapshot.toInputPoint(point, bias)

func endDiffPoint*(self: DiffMapSnapshot): DiffPoint {.inline.} = self.toDiffPoint(self.input.endOutputPoint)
func endDiffPoint*(self: DiffMap): DiffPoint {.inline.} = self.snapshot.endDiffPoint

proc createIdentityDiffMap(input: sink InputMapSnapshot): DiffMapSnapshot =
  logMapUpdate &"createIdentityDiffMap {input.buffer.remoteId}, input summary = {input.map.summary}"
  let endOutputPoint = input.endOutputPoint

  return DiffMapSnapshot(
    map: SumTree[DiffMapChunk].new([DiffMapChunk(summary: DiffMapChunkSummary(src: endOutputPoint.row + 1, dst: endOutputPoint.row + 1))]),
    input: input.ensureMove,
  )

proc createDiffMap(input: sink InputMapSnapshot, mappings: openArray[LineMapping], otherInput: InputMapSnapshot, reverse: bool): DiffMapSnapshot =
  logMapUpdate &"createDiffMap {input.buffer.remoteId}@{input.buffer.version}, input summary = {input.map.summary} + {otherInput.buffer.remoteId}@{otherInput.buffer.version} {otherInput.map.summary}, reverse = {reverse}"
  # echo "  line mappings"
  # echo mappings.mapIt(&"    {it}").join("\n")
  assert not otherInput.map.isNil

  # var t = startTimer()
  # defer:
  #   let e = t.elapsed.ms
  #   echo &"createDiffMap took {e} ms"

  let endPoint = input.buffer.visibleText.summary.lines
  let otherEndPoint = otherInput.buffer.visibleText.summary.lines

  var newMap = SumTree[DiffMapChunk].new()
  var currentChunk = DiffMapChunk()

  template flushCurrentChunk(even: bool): untyped =
    if currentChunk.summary.src != 0 or currentChunk.summary.dst != 0:
      if even and currentChunk.summary.src == currentChunk.summary.dst:
        newMap.add(currentChunk)
        currentChunk = DiffMapChunk()
      elif not even and currentChunk.summary.src != currentChunk.summary.dst:
        newMap.add(currentChunk)
        currentChunk = DiffMapChunk()

  for i in 0..<input.buffer.visibleText.lines:
    let inputRange = input.toOutputPoint(point(i, 0))...input.toOutputPoint(point(i + 1, 0))
    let lines = if i == endPoint.row.int:
      inputRange.b.row - inputRange.a.row + 1
    else:
      inputRange.b.row - inputRange.a.row

    let diffLine = mappings.mapLine(i, reverse)
    let nextDiffLine = mappings.mapLine(i + 1, reverse)
    if diffLine.getSome(diffLine):
      let otherInputRange = otherInput.toOutputPoint(point(diffLine.line, 0))...otherInput.toOutputPoint(point(diffLine.line + 1, 0))
      let otherLines = if diffLine.line == otherEndPoint.row.int:
        otherInputRange.b.row - otherInputRange.a.row + 1
      else:
        otherInputRange.b.row - otherInputRange.a.row

      if lines < otherLines:
        flushCurrentChunk(even = false)
        currentChunk.summary.src += min(lines, otherLines)
        currentChunk.summary.dst += min(lines, otherLines)
        flushCurrentChunk(even = true)
        currentChunk.summary.dst += otherLines - lines
      elif lines == otherLines:
        flushCurrentChunk(even = false)
        currentChunk.summary.src += lines
        currentChunk.summary.dst += lines
      else:
        flushCurrentChunk(even = false)
        currentChunk.summary.src += lines
        currentChunk.summary.dst += lines

    else:
      flushCurrentChunk(even = false)
      currentChunk.summary.src += lines
      currentChunk.summary.dst += lines

    if i < endPoint.row.int and diffLine.getSome(diffLine) and nextDiffLine.getSome(nextDiffLine) and nextDiffLine.line - diffLine.line > 1:
      let otherInputRange = otherInput.toOutputPoint(point(diffLine.line + 1, 0))...otherInput.toOutputPoint(point(nextDiffLine.line, 0))
      let otherLines = otherInputRange.b.row - otherInputRange.a.row
      flushCurrentChunk(even = true)
      currentChunk.summary.dst += otherLines

  if currentChunk.summary.src != 0 or currentChunk.summary.dst != 0:
    newMap.add(currentChunk)

  result = DiffMapSnapshot(
    map: newMap,
    input: input.clone(),
    mappings: some(@mappings),
    otherInput: otherInput.clone(),
    reverse: reverse,
  )

  # echo result

proc setInput*(self: DiffMap, input: sink InputMapSnapshot) =
  if self.snapshot.input.buffer.remoteId == input.buffer.remoteId and self.snapshot.input.buffer.version == input.buffer.version:
    return
  # logMapUpdate &"DiffMap.setInput {self.snapshot.desc} -> {input.desc}"
  self.snapshot = createIdentityDiffMap(input.ensureMove)

proc validate*(self: DiffMapSnapshot) =
  discard

proc edit*(self: var DiffMapSnapshot, buffer: sink InputMapSnapshot, patch: Patch[InputPoint]) =
  discard

proc edit*(self: DiffMap, input: sink InputMapSnapshot, patch: Patch[InputPoint]) =
  # echo &"edit diff map, {self.snapshot.input.map.summary} -> {input.map.summary}, {patch}"
  if self.snapshot.mappings.isSome:
    self.snapshot = createDiffMap(input.ensureMove, self.snapshot.mappings.get, self.snapshot.otherInput, self.snapshot.reverse)
  else:
    self.snapshot = createIdentityDiffMap(input.ensureMove)

proc update*(self: var DiffMapSnapshot, input: sink InputMapSnapshot) =
  logMapUpdate &"DiffMapSnapshot.updateInput {self.desc} -> {input.desc}"
  if self.mappings.isSome:
    self = createDiffMap(input.ensureMove, self.mappings.get, self.otherInput, self.reverse)
  else:
    self = createIdentityDiffMap(input.ensureMove)

proc update*(self: var DiffMapSnapshot, mappings: Option[seq[LineMapping]], otherInput: InputMapSnapshot, reverse: bool) =
  logMapUpdate &"DiffMapSnapshot.updateLineMappings {self.desc} -> {otherInput.desc}"
  if mappings.isSome:
    self = createDiffMap(self.input.clone(), mappings.get, otherInput, reverse)
  else:
    self = createIdentityDiffMap(self.input.clone())

proc clear*(self: var DiffMapSnapshot) =
  self = createIdentityDiffMap(self.input.clone())

proc update*(self: DiffMap, input: sink InputMapSnapshot, force: bool = false) =
  logMapUpdate &"DiffMap.updateInput: {self.snapshot.desc} -> {input.desc}"
  let oldSnapshot = self.snapshot.clone()
  self.snapshot.update(input.ensureMove)
  self.onUpdated.invoke((self, oldSnapshot))

proc update*(self: DiffMap, mappings: Option[seq[LineMapping]], otherInput: InputMapSnapshot, reverse: bool, force: bool = false) =
  let oldSnapshot = self.snapshot.clone()
  self.snapshot.update(mappings, otherInput, reverse)
  self.onUpdated.invoke((self, oldSnapshot))

proc clear*(self: DiffMap) =
  self.snapshot.clear()

proc seek*(self: var DiffChunkIterator, point: Point) =
  logChunkIter &"DiffChunkIterator.seek {self.point} -> {point}"
  self.inputChunks.seek(point)
  discard self.diffMapCursor.seekForward(self.inputChunks.outputPoint.row.DiffMapChunkSrc, Bias.Right, ())
  if self.diffMapCursor.item.getSome(item) and item.summary.src == 0:
    self.diffMapCursor.next()

  self.diffPoint = self.diffMapCursor.toDiffPoint(self.inputChunks.outputPoint)
  self.atEnd = false
  self.diffChunk = DiffChunk.none

proc seek*(self: var DiffChunkIterator, diffPoint: DiffPoint) =
  logChunkIter &"DiffChunkIterator.seek {self.diffPoint} -> {diffPoint}"
  var endDiffPoint = self.diffMap.toDiffPoint(self.diffMap.input.endOutputPoint)
  # assert endDiffPoint < diffPoint(self.diffMap.map.summary.dst, 0)
  if diffPoint <= endDiffPoint:
    let inputPoint = self.diffMap.toInputPoint(diffPoint)
    self.inputChunks.seek(inputPoint)
    self.diffPoint = self.diffMap.toDiffPoint(inputPoint)
  else:
    self.atEnd = true

  self.diffChunk = DiffChunk.none

proc seekLine*(self: var DiffChunkIterator, line: int) =
  self.seek(diffPoint(line))

proc next*(self: var DiffChunkIterator): Option[DiffChunk] =
  if self.atEnd:
    self.diffChunk = DiffChunk.none
    return

  self.diffChunk = if self.inputChunks.next().getSome(it):
    discard self.diffMapCursor.seek(it.outputPoint.row.DiffMapChunkSrc, Bias.Right, ())
    if self.diffMapCursor.item.getSome(item) and item.summary.src == 0:
      self.diffMapCursor.next()
    let diffPoint = self.diffMapCursor.toDiffPoint(it.outputPoint)
    DiffChunk(inputChunk: it, diffPoint: diffPoint).some
  else:
    DiffChunk.none

  if self.diffChunk.isSome:
    self.diffPoint = self.diffChunk.get.diffEndPoint

  self.atEnd = self.inputChunks.atEnd

  return self.diffChunk

#

func toOutputPoint*(self: DiffMapSnapshot, point: WrapPoint, bias: Bias = Bias.Right): DiffPoint {.inline.} = self.toDiffPoint(point, bias)
func `outputPoint=`*(self: var DiffChunk, point: DiffPoint) = self.diffPoint = point
template outputPoint*(self: DiffChunk): DiffPoint = self.diffPoint
template endOutputPoint*(self: DiffChunk): DiffPoint = self.endDiffPoint
template endOutputPoint*(self: DiffMapSnapshot): DiffPoint = self.endDiffPoint

func wrap*(self: DiffMapSnapshot): lent WrapMapSnapshot {.inline.} = self.input
func wrapChunks*(self: var DiffChunkIterator): var WrapChunkIterator {.inline.} = self.inputChunks
func wrapChunks*(self: DiffChunkIterator): lent WrapChunkIterator {.inline.} = self.inputChunks
func wrapChunk*(self: DiffChunk): lent WrapChunk {.inline.} = self.inputChunk
proc toWrapPoint*(self: DiffMapChunkCursor, point: DiffPoint): InputPoint {.inline.} = self.toInputPoint(point)
proc toWrapPoint*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Right): InputPoint {.inline.} = self.toInputPoint(point, bias)
proc toWrapPoint*(self: DiffMap, point: DiffPoint, bias: Bias = Bias.Right): InputPoint {.inline.} = self.toInputPoint(point, bias)
