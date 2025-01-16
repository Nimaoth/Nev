import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm]
import nimsumtree/[rope, buffer, clock]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import diff, wrap_map
from scripting_api import Selection
import nimsumtree/sumtree except mapIt

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

var debugDiffMap* = false

template log(msg: untyped) =
  when false:
    if debugDiffMap:
      echo msg

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
    wrapChunk*: WrapChunk
    diffPoint*: DiffPoint

func point*(self: DiffChunk): Point = self.wrapChunk.point
func endPoint*(self: DiffChunk): Point = self.wrapChunk.endPoint
func diffEndPoint*(self: DiffChunk): DiffPoint = diffPoint(self.diffPoint.row, self.diffPoint.column + self.wrapChunk.len.uint32)
func len*(self: DiffChunk): int = self.wrapChunk.len
func `$`*(self: DiffChunk): string = $self.wrapChunk
template toOpenArray*(self: DiffChunk): openArray[char] = self.wrapChunk.toOpenArray
template scope*(self: DiffChunk): string = self.wrapChunk.scope

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
    wrapMap*: WrapMapSnapshot
    otherWrapMap*: WrapMapSnapshot
    mappings*: Option[seq[LineMapping]] # todo: this is not thread safe
    reverse*: bool

  DiffMap* = ref object
    snapshot*: DiffMapSnapshot
    # pendingEdits: seq[tuple[buffer: WrapMapSnapshot, patch: Patch[Point]]]
    updatingAsync: bool
    onUpdated*: Event[tuple[map: DiffMap, old: DiffMapSnapshot]]

  DiffChunkIterator* = object
    wrapChunks*: WrappedChunkIterator
    diffChunk*: Option[DiffChunk]
    diffMap* {.cursor.}: DiffMapSnapshot
    diffMapCursor: DiffMapChunkCursor
    diffPoint*: DiffPoint
    atEnd*: bool

func clone*(self: DiffMapSnapshot): DiffMapSnapshot =
  var otherWrapMap: WrapMapSnapshot
  if not self.otherWrapMap.map.isNil:
    otherWrapMap = self.otherWrapMap.clone()
  DiffMapSnapshot(map: self.map.clone(), wrapMap: self.wrapMap.clone(), otherWrapMap: otherWrapMap, mappings: self.mappings, reverse: self.reverse)

proc new*(_: typedesc[DiffMap]): DiffMap =
  result = DiffMap(snapshot: DiffMapSnapshot(map: SumTree[DiffMapChunk].new([DiffMapChunk()])))

proc init*(_: typedesc[DiffChunkIterator], rope: var RopeSlice[int], wrapMap: var WrapMap, diffMap: var DiffMap): DiffChunkIterator =
  result = DiffChunkIterator(
    wrapChunks: WrappedChunkIterator.init(rope, wrapMap),
    diffMap: diffMap.snapshot.clone(),
    diffMapCursor: diffMap.snapshot.map.initCursor(DiffMapChunkSummary),
  )

func point*(self: DiffChunkIterator): Point = self.wrapChunks.point

func isNil*(self: DiffMapSnapshot): bool = self.map.isNil

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

proc toDiffPoint*(self: DiffMapChunkCursor, point: WrapPoint): DiffPoint =
  assert point.row in self.startPos.src...self.endPos.src
  # if self.startPos.dst == self.endPos.dst:
  #   return diffPoint(self.startPos.dst)
  # let point2 = point.row.clamp(self.startPos.src...self.endPos.src)
  let offset = point - wrapPoint(self.startPos.src)
  return (diffPoint(self.startPos.dst) + offset.toDiffPoint)

proc toDiffPoint*(self: DiffMapSnapshot, point: WrapPoint, bias: Bias = Bias.Right): DiffPoint =
  var c = self.map.initCursor(DiffMapChunkSummary)
  discard c.seek(point.row.DiffMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.summary.src == 0:
    c.next()

  return c.toDiffPoint(point)

proc toDiffPoint*(self: DiffMapSnapshot, point: Point, bias: Bias = Bias.Right): DiffPoint =
  return self.toDiffPoint(self.wrapMap.toWrapPoint(point, bias))

proc toDiffPoint*(self: DiffMap, point: Point, bias: Bias = Bias.Right): DiffPoint =
  self.snapshot.toDiffPoint(point, bias)

proc toDiffPoint*(self: DiffMap, point: WrapPoint, bias: Bias = Bias.Right): DiffPoint =
  self.snapshot.toDiffPoint(point, bias)

proc toWrapPoint*(self: DiffMapChunkCursor, point: DiffPoint): WrapPoint =
  # let point = point.clamp(self.startPos.dst...self.endPos.dst)
  # let offset = point - self.startPos.dst
  # return self.startPos.src + offset.toPoint
  assert point.row in self.startPos.dst...self.endPos.dst
  if self.startPos.src == self.endPos.src:
    return wrapPoint(self.startPos.src)

  # let point2 = point.row.clamp(self.startPos.dst...self.endPos.dst)
  let offset = point - diffPoint(self.startPos.dst)
  # echo &"toWrapPoint {point}, {self.startPos}, {self.endPos} -> offset {offset}, {(wrapPoint(self.startPos.src) + offset.toWrapPoint)}"
  return (wrapPoint(self.startPos.src) + offset.toWrapPoint)

proc toWrapPoint*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Left): WrapPoint =
  var c = self.map.initCursor(DiffMapChunkSummary)
  discard c.seek(point.row.DiffMapChunkDst, bias, ())
  if c.item.getSome(item) and item.summary.dst == 0:
    c.next()

  return c.toWrapPoint(point)

proc isEmptySpace*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Right): bool =
  var c = self.map.initCursor(DiffMapChunkSummary)
  discard c.seek(point.row.DiffMapChunkDst, bias, ())
  if c.item.getSome(item) and item.summary.dst == 0:
    c.next()

  return c.startPos.src == c.endPos.src

proc toPoint*(self: DiffMapSnapshot, point: DiffPoint, bias: Bias = Bias.Right): Point =
  return self.wrapMap.toPoint(self.toWrapPoint(point, bias), bias)

proc toPoint*(self: DiffMap, point: DiffPoint, bias: Bias = Bias.Right): Point =
  self.snapshot.toPoint(point, bias)

proc toWrapPoint*(self: DiffMap, point: DiffPoint, bias: Bias = Bias.Right): WrapPoint =
  self.snapshot.toWrapPoint(point, bias)

proc createIdentityDiffMap(wrapMap: sink WrapMapSnapshot): DiffMapSnapshot =
  # echo &"createIdentityDiffMap {wrapMap.buffer.remoteId}, {wrapMap.map.summary}"
  let endPoint = wrapMap.buffer.visibleText.summary.lines
  let endWrapPoint = wrapMap.toWrapPoint(endPoint)

  return DiffMapSnapshot(
    map: SumTree[DiffMapChunk].new([DiffMapChunk(summary: DiffMapChunkSummary(src: endWrapPoint.row + 1, dst: endWrapPoint.row + 1))]),
    wrapMap: wrapMap.ensureMove,
  )

proc createDiffMap(wrapMap: sink WrapMapSnapshot, mappings: openArray[LineMapping], otherWrapMap: WrapMapSnapshot, reverse: bool): DiffMapSnapshot =
  # echo &"createDiffMap {wrapMap.buffer.remoteId}@{wrapMap.buffer.version} {wrapMap.map.summary} + {otherWrapMap.buffer.remoteId}@{otherWrapMap.buffer.version} {otherWrapMap.map.summary}, reverse = {reverse}"
  # echo "  line mappings"
  # echo mappings.mapIt(&"    {it}").join("\n")
  assert not otherWrapMap.map.isNil

  # var t = startTimer()
  # defer:
  #   let e = t.elapsed.ms
  #   echo &"createDiffMap took {e} ms"

  let endPoint = wrapMap.buffer.visibleText.summary.lines
  let endWrapPoint = wrapMap.toWrapPoint(endPoint)
  let otherEndPoint = otherWrapMap.buffer.visibleText.summary.lines
  let otherEndWrapPoint = otherWrapMap.toWrapPoint(otherEndPoint)

  var newMap = SumTree[DiffMapChunk].new()
  var currentChunk = DiffMapChunk()

  template flushCurrentChunk(even: bool): untyped =
    if currentChunk.summary.src != 0 or currentChunk.summary.dst != 0:
      if even and currentChunk.summary.src == currentChunk.summary.dst:
      # echo &"  flush {i}->{diffLine.line}, {wrapRange} -> {otherWrapRange}, {lines} -> {otherLines}, {currentChunk}"
        newMap.add(currentChunk)
        currentChunk = DiffMapChunk()
      elif not even and currentChunk.summary.src != currentChunk.summary.dst:
        newMap.add(currentChunk)
        currentChunk = DiffMapChunk()

  for i in 0..<wrapMap.buffer.visibleText.lines:
    let wrapRange = wrapMap.toWrapPoint(point(i, 0))...wrapMap.toWrapPoint(point(i + 1, 0))
    let lines = if i == endPoint.row.int:
      wrapRange.b.row - wrapRange.a.row + 1
    else:
      wrapRange.b.row - wrapRange.a.row

    let diffLine = mappings.mapLine(i, reverse)
    let nextDiffLine = mappings.mapLine(i + 1, reverse)
    # echo &"wrapRange {i} = {wrapRange} -> {lines}, diff: {diffLine}, {nextDiffLine}, current: {currentChunk.summary}"
    if diffLine.getSome(diffLine):
      let otherWrapRange = otherWrapMap.toWrapPoint(point(diffLine.line, 0))...otherWrapMap.toWrapPoint(point(diffLine.line + 1, 0))
      let otherLines = if diffLine.line == otherEndPoint.row.int:
        otherWrapRange.b.row - otherWrapRange.a.row + 1
      else:
        otherWrapRange.b.row - otherWrapRange.a.row
      # echo &"  otherWrapRange {diffLine.line}, {diffLine.changed} = {otherWrapRange} -> {otherLines}"

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
      let otherWrapRange = otherWrapMap.toWrapPoint(point(diffLine.line + 1, 0))...otherWrapMap.toWrapPoint(point(nextDiffLine.line, 0))
      let otherLines = otherWrapRange.b.row - otherWrapRange.a.row
      # echo &" delete otherWrapRange {otherWrapRange} -> {otherLines}"
      flushCurrentChunk(even = true)
      currentChunk.summary.dst += otherLines

  if currentChunk.summary.src != 0 or currentChunk.summary.dst != 0:
    newMap.add(currentChunk)

  result = DiffMapSnapshot(
    map: newMap,
    wrapMap: wrapMap.clone(),
    mappings: some(@mappings),
    otherWrapMap: otherWrapMap.clone(),
    reverse: reverse,
  )

  # echo result

proc setWrapMap*(self: DiffMap, wrapMap: sink WrapMapSnapshot) =
  if self.snapshot.wrapMap.buffer.remoteId == wrapMap.buffer.remoteId and self.snapshot.wrapMap.buffer.version == wrapMap.buffer.version:
    return
  # let oldSnapshot = self.snapshot.clone()
  self.snapshot = createIdentityDiffMap(wrapMap.ensureMove)
  # echo &"DiffMap.onUpdated {self.snapshot.wrapMap.buffer.remoteId}@{self.snapshot.wrapMap.buffer.version}"
  # self.onUpdated.invoke((self, oldSnapshot))

proc validate*(self: DiffMapSnapshot) =
  discard

proc edit*(self: var DiffMapSnapshot, buffer: sink WrapMapSnapshot, patch: Patch[Point]) =
  discard

proc flushEdits(self: DiffMap) =
  discard

proc edit*(self: DiffMap, wrapMap: sink WrapMapSnapshot, patch: Patch[Point]) =
  # echo &"edit diff map, {self.snapshot.wrapMap.map.summary} -> {wrapMap.map.summary}, {patch}"
  if self.snapshot.mappings.isSome:
    self.snapshot = createDiffMap(wrapMap.ensureMove, self.snapshot.mappings.get, self.snapshot.otherWrapMap, self.snapshot.reverse)
  else:
    self.snapshot = createIdentityDiffMap(wrapMap.ensureMove)

proc update*(self: var DiffMapSnapshot, wrapMap: sink WrapMapSnapshot) =
  # echo &"DiffMap.updateWrapMap {self.wrapMap.buffer.remoteId}@{self.wrapMap.buffer.version} -> {wrapMap.buffer.remoteId}@{wrapMap.buffer.version}"
  if self.mappings.isSome:
    self = createDiffMap(wrapMap.ensureMove, self.mappings.get, self.otherWrapMap, self.reverse)
  else:
    self = createIdentityDiffMap(wrapMap.ensureMove)

proc update*(self: var DiffMapSnapshot, mappings: Option[seq[LineMapping]], otherWrapMap: WrapMapSnapshot, reverse: bool) =
  # echo &"DiffMap.updateLineMappings {self.wrapMap.buffer.remoteId}@{self.wrapMap.buffer.version}: {self.otherWrapMap.buffer.remoteId}@{self.otherWrapMap.buffer.version} -> {otherWrapMap.buffer.remoteId}@{otherWrapMap.buffer.version}"
  if mappings.isSome:
    self = createDiffMap(self.wrapMap.clone(), mappings.get, otherWrapMap, reverse)
  else:
    self = createIdentityDiffMap(self.wrapMap.clone())

proc clear*(self: var DiffMapSnapshot) =
  self = createIdentityDiffMap(self.wrapMap.clone())

proc update*(self: DiffMap, buffer: sink WrapMapSnapshot, force: bool = false) =
  let oldSnapshot = self.snapshot.clone()
  self.snapshot.update(buffer.ensureMove)
  # echo &"DiffMap.onUpdated {self.snapshot.wrapMap.buffer.remoteId}@{self.snapshot.wrapMap.buffer.version}"
  self.onUpdated.invoke((self, oldSnapshot))

proc update*(self: DiffMap, mappings: Option[seq[LineMapping]], otherWrapMap: WrapMapSnapshot, reverse: bool, force: bool = false) =
  let oldSnapshot = self.snapshot.clone()
  self.snapshot.update(mappings, otherWrapMap, reverse)
  # echo &"DiffMap.onUpdated {self.snapshot.wrapMap.buffer.remoteId}@{self.snapshot.wrapMap.buffer.version}"
  self.onUpdated.invoke((self, oldSnapshot))

proc clear*(self: DiffMap) =
  let oldSnapshot = self.snapshot.clone()
  self.snapshot.clear()

proc seek*(self: var DiffChunkIterator, diffPoint: DiffPoint) =
  # echo &"DiffChunkIterator.seek {self.diffPoint} -> {diffPoint}"
  var endDiffPoint = self.diffMap.toDiffPoint(self.diffMap.wrapMap.endWrapPoint)
  assert endDiffPoint < diffPoint(self.diffMap.map.summary.dst, 0)
  if diffPoint <= endDiffPoint:
    let wrapPoint = self.diffMap.toWrapPoint(diffPoint)
    self.wrapChunks.seek(wrapPoint)
    self.diffPoint = self.diffMap.toDiffPoint(wrapPoint)
  else:
    self.atEnd = true

  self.diffChunk = DiffChunk.none

proc seekLine*(self: var DiffChunkIterator, line: int) =
  self.seek(diffPoint(line))

proc next*(self: var DiffChunkIterator): Option[DiffChunk] =
  if self.atEnd:
    self.diffChunk = DiffChunk.none
    return

  self.diffChunk = if self.wrapChunks.next().getSome(it):
    discard self.diffMapCursor.seek(it.wrapPoint.row.DiffMapChunkSrc, Bias.Right, ())
    if self.diffMapCursor.item.getSome(item) and item.summary.src == 0:
      self.diffMapCursor.next()
    let diffPoint = self.diffMapCursor.toDiffPoint(it.wrapPoint)
    DiffChunk(wrapChunk: it, diffPoint: diffPoint).some
  else:
    DiffChunk.none

  if self.diffChunk.isSome:
    let oldDiffPoint = self.diffPoint
    self.diffPoint = self.diffChunk.get.diffEndPoint
    # echo &"DiffChunkIterator.next: {oldDiffPoint} -> {self.diffPoint}"

  self.atEnd = self.wrapChunks.atEnd

  return self.diffChunk
