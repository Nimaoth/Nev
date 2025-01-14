import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm]
import nimsumtree/[rope, sumtree, buffer, clock]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import text/diff
from scripting_api import Selection

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

var debugWrapMap* = false

template log(msg: untyped) =
  when false:
    if debugWrapMap:
      echo msg

{.push gcsafe.}
{.push raises: [].}

type WrapPoint* {.borrow: `.`.} = distinct Point
func wrapPoint*(row: Natural = 0, column: Natural = 0): WrapPoint = Point(row: row.uint32, column: column.uint32).WrapPoint
func `$`*(a: WrapPoint): string {.borrow.}
func `<`*(a: WrapPoint, b: WrapPoint): bool {.borrow.}
func `<=`*(a: WrapPoint, b: WrapPoint): bool {.borrow.}
func `+`*(a: WrapPoint, b: WrapPoint): WrapPoint {.borrow.}
func `+`*(point: WrapPoint, diff: PointDiff): WrapPoint {.borrow.}
func `+=`*(a: var WrapPoint, b: WrapPoint) {.borrow.}
func `+=`*(point: var WrapPoint, diff: PointDiff) {.borrow.}
func `-`*(a: WrapPoint, b: WrapPoint): PointDiff {.borrow.}
func dec*(a: var WrapPoint): WrapPoint {.borrow.}
func pred*(a: WrapPoint): WrapPoint {.borrow.}
func clone*(a: WrapPoint): WrapPoint {.borrow.}
func cmp*(a: WrapPoint, b: WrapPoint): int {.borrow.}
func clamp*(p: WrapPoint, r: Range[WrapPoint]): WrapPoint = min(max(p, r.a), r.b)
converter toWrapPoint*(diff: PointDiff): WrapPoint = diff.toPoint.WrapPoint

type
  WrapMapChunk* = object
    src*: Point
    dst*: WrapPoint

  WrapMapChunkSummary* = object
    src*: Point
    dst*: WrapPoint

  WrapMapChunkSrc* = distinct Point
  WrapMapChunkDst* = distinct WrapPoint

# Make WrapMapChunk an Item
func clone*(self: WrapMapChunk): WrapMapChunk = self

func summary*(self: WrapMapChunk): WrapMapChunkSummary = WrapMapChunkSummary(src: self.src, dst: self.dst)

func fromSummary*[C](_: typedesc[WrapMapChunkSummary], self: WrapMapChunkSummary, cx: C): WrapMapChunkSummary = self

# Make WrapMapChunkSummary a Summary
func addSummary*[C](self: var WrapMapChunkSummary, b: WrapMapChunkSummary, cx: C) =
  self.src += b.src
  self.dst += b.dst

# Make WrapMapChunkDst a Dimension
func cmp*[C](a: WrapMapChunkDst, b: WrapMapChunkSummary, cx: C): int = cmp(a.WrapPoint, b.dst)

# Make WrapMapChunkSrc a Dimension
func cmp*[C](a: WrapMapChunkSrc, b: WrapMapChunkSummary, cx: C): int = cmp(a.Point, b.src)

type
  WrapChunk* = object
    styledChunk*: StyledChunk
    wrapPoint*: WrapPoint

  #
  # (0, 0)...(0, 10) -> (0, 0)...(0, 10)
  # (0, 10)...(0, 15) -> (1, 0)...(1, 5)
  # (1, 0)...(1, 10) -> (2, 0)...(2, 10)
  # -------------------
  # aaaaaaaaaabbbbb
  # aaaaaaaaaa
  # -------------------
  # aaaaaaaaaa
  # bbbbb
  # aaaaaaaaaa
  # -------------------
  #
  WrapMapChunkCursor* = sumtree.Cursor[WrapMapChunk, WrapMapChunkSummary]

  WrapMapSnapshot* = object
    map*: SumTree[WrapMapChunk]
    buffer*: BufferSnapshot
    interpolated*: bool = true

  WrapMap* = ref object
    snapshot*: WrapMapSnapshot
    wrapWidth*: int
    wrappedIndent*: int = 4
    pendingEdits: seq[tuple[buffer: BufferSnapshot, patch: Patch[Point]]]
    updatingAsync: bool
    onUpdated*: Event[tuple[map: WrapMap, old: WrapMapSnapshot]]

  WrappedChunkIterator* = object
    chunks*: StyledChunkIterator
    styledChunk: Option[StyledChunk]
    wrapChunk*: Option[WrapChunk]
    wrapMap* {.cursor.}: WrapMapSnapshot
    wrapMapCursor: WrapMapChunkCursor
    wrapPoint*: WrapPoint
    localOffset: int
    atEnd*: bool

func clone*(self: WrapMapSnapshot): WrapMapSnapshot =
  WrapMapSnapshot(map: self.map.clone(), buffer: self.buffer.clone(), interpolated: self.interpolated)

proc new*(_: typedesc[WrapMap]): WrapMap =
  result = WrapMap(snapshot: WrapMapSnapshot(map: SumTree[WrapMapChunk].new([WrapMapChunk()])))

proc init*(_: typedesc[WrappedChunkIterator], rope: var RopeSlice[int], wrapMap: var WrapMap): WrappedChunkIterator =
  result = WrappedChunkIterator(
    chunks: StyledChunkIterator.init(rope),
    wrapMap: wrapMap.snapshot.clone(),
    wrapMapCursor: wrapMap.snapshot.map.initCursor(WrapMapChunkSummary),
  )

func point*(self: WrappedChunkIterator): Point = self.chunks.point
func point*(self: WrapChunk): Point = self.styledChunk.point
func endPoint*(self: WrapChunk): Point = self.styledChunk.endPoint
func wrapEndPoint*(self: WrapChunk): WrapPoint = wrapPoint(self.wrapPoint.row, self.wrapPoint.column + self.styledChunk.len.uint32)
func len*(self: WrapChunk): int = self.styledChunk.len
func `$`*(self: WrapChunk): string = $self.styledChunk
template toOpenArray*(self: WrapChunk): openArray[char] = self.styledChunk.toOpenArray
template scope*(self: WrapChunk): string = self.styledChunk.scope

func isNil*(self: WrapMapSnapshot): bool = self.map.isNil

func endWrapPoint*(self: WrapMapSnapshot): WrapPoint = self.map.summary.dst

proc `$`*(self: WrapMapSnapshot): string =
  result.add "wrap map\n"
  var c = self.map.initCursor(WrapMapChunkSummary)
  var i = 0
  while not c.atEnd:
    c.next()
    if c.item.getSome(item):
      let r = c.startPos.src...c.endPos.src
      let rd = c.startPos.dst...c.endPos.dst
      if item.src != Point() or true:
        result.add &"  {i}: {item.src} -> {item.dst}   |   {r} -> {rd}\n"
        inc i

proc toWrapPoint*(self: WrapMapChunkCursor, point: Point): WrapPoint =
  let point2 = point.clamp(self.startPos.src...self.endPos.src)
  let offset = point2 - self.startPos.src
  return (self.startPos.dst + offset.toWrapPoint)

proc toWrapPointNoClamp*(self: WrapMapChunkCursor, point: Point): WrapPoint =
  var c = self
  discard c.seek(point.WrapMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.src == Point():
    c.next()
  let point2 = point.clamp(c.startPos.src...c.endPos.src)
  let offset = point2 - c.startPos.src
  return (c.startPos.dst + offset.toWrapPoint)

proc toWrapPoint*(self: WrapMapSnapshot, point: Point, bias: Bias = Bias.Right): WrapPoint =
  var c = self.map.initCursor(WrapMapChunkSummary)
  discard c.seek(point.WrapMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.src == Point():
    c.next()

  return c.toWrapPoint(point)

proc toWrapPoint*(self: WrapMap, point: Point, bias: Bias = Bias.Right): WrapPoint =
  self.snapshot.toWrapPoint(point, bias)

proc toPoint*(self: WrapMapChunkCursor, point: WrapPoint): Point =
  let point = point.clamp(self.startPos.dst...self.endPos.dst)
  let offset = point - self.startPos.dst
  # echo &"toPoint {point}, {self.startPos}, {self.endPos} -> offset {offset}, {self.startPos.src + offset.toPoint}"
  return self.startPos.src + offset.toPoint

proc toPoint*(self: WrapMapSnapshot, point: WrapPoint, bias: Bias = Bias.Right): Point =
  var c = self.map.initCursor(WrapMapChunkSummary)
  discard c.seek(point.WrapMapChunkDst, Bias.Left, ())
  if c.item.getSome(item) and item.src == Point():
    c.next()

  return c.toPoint(point)

proc toPoint*(self: WrapMap, point: WrapPoint, bias: Bias = Bias.Right): Point =
  self.snapshot.toPoint(point, bias)

proc setBuffer*(self: WrapMap, buffer: sink BufferSnapshot) =
  # echo &"WrapMap.setBuffer {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}"
  # self.wrapWidth = 0
  if self.snapshot.buffer.remoteId == buffer.remoteId and self.snapshot.buffer.version == buffer.version:
    return

  self.wrapWidth = 0
  let endPoint = buffer.visibleText.summary.lines
  self.snapshot = WrapMapSnapshot(
    map: SumTree[WrapMapChunk].new([WrapMapChunk(src: endPoint, dst: endPoint.WrapPoint)]),
    buffer: buffer.ensureMove,
  )
  self.pendingEdits.setLen(0)

proc validate*(self: WrapMapSnapshot) =
  # log &"validate {self.buffer.remoteId}{self.buffer.version}"
  var c = self.map.initCursor(WrapMapChunkSummary)
  var endPos = Point()
  c.next()
  while c.item.getSome(_):
    endPos = c.endPos.src
    c.next()

  if endPos != self.buffer.visibleText.summary.lines:
    echo &"--------------------------------\n-------------------------------\nInvalid wrap map {self.buffer.remoteId}{self.buffer.version}, endpos {endPos} != {self.buffer.visibleText.summary.lines}\n{self}\n---------------------------------------"
    return

  if self.map.summary.src != self.buffer.visibleText.summary.lines:
    echo &"--------------------------------\n-------------------------------\nInvalid wrap map {self.buffer.remoteId}{self.buffer.version}, summary {self.map.summary.src} != {self.buffer.visibleText.summary.lines}\n{self}\n---------------------------------------"
    return

proc editImpl(self: var WrapMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]) =
  # assert patch.edits.len == 1
  # if self.buffer.remoteId == buffer.remoteId and self.buffer.version == buffer.version:
  #   return

  # var t = startTimer()
  # defer:
  #   let e = t.elapsed.ms
  #   log &"interpolate wrap map took {e} ms"

  log &"============\nedit {patch}\n  {self}"
  # let p2 = patch.decompose()

  var newMap = SumTree[WrapMapChunk].new()

  var c = self.map.initCursor(WrapMapChunkSummary)
  var currentRange = Point()...Point()
  var currentChunk = WrapMapChunk()
  for e in patch.edits:
    # e[i].new takes into account any edits < i
    # eu[i].new is as if it was the only edit (i.e. eu[i].old.a == eu[i].new.a)
    var eu = e
    eu.new.a = eu.old.a
    eu.new.b = eu.new.a + (e.new.b - e.new.a).toPoint

    while true:
      log &"edit edit: {e}|{eu}, currentChunk: {currentChunk}, newMap: {newMap.toSeq}"
      if not c.didSeek or eu.old.a >= c.endPos.src:
        if currentRange != Point()...Point():
          log &"  add current chunk {currentChunk}"
          # todo: only add when not empty
          newMap.add currentChunk
          c.next()

        let bias = if eu.old.a < self.map.summary.src:
          Bias.Right
        else:
          Bias.Left
        newMap.append c.slice(eu.old.a.WrapMapChunkSrc, bias)

      if c.item.isNone:
        log &"================== item is none, {c.startPos}, {c.endPos}"
        break

      if c.item.getSome(item) and item.src == Point() and self.map.summary.src > Point():
        log &"================== skip {item[]}, {c.startPos} -> {c.endPos}"
        newMap.add item[]
        c.next()

      if c.startPos.src...c.endPos.src != currentRange:
        currentChunk = c.item.get[]
        currentRange = c.startPos.src...c.endPos.src
        log &"  reset current chunk to {currentChunk}, {currentRange}"

      let item = c.item.get
      let map = (
        src: c.startPos.src...c.endPos.src,
        dst: c.startPos.dst...c.endPos.dst)
      log &"  map {map}"

      let insert = eu.new.b > eu.old.b

      let edit = if insert:
        (
          old: eu.old.a.clamp(map.src)...eu.old.b.clamp(map.src),
          new: eu.new.a.clamp(map.src)...eu.new.b,
        )
      else:
        (
          old: eu.old.a.clamp(map.src)...eu.old.b.clamp(map.src),
          new: eu.new.a.clamp(map.src)...eu.new.b.clamp(map.src),
        )

      let displayEdit = (
        old: c.toWrapPoint(eu.old.a)...c.toWrapPoint(eu.old.b),
        # new: c.toWrapPoint(eu.new.a)...c.toWrapPointNoClamp(eu.new.b))
        new: c.toWrapPoint(eu.new.a)...(c.toWrapPoint(eu.new.a) + (eu.new.b - eu.new.a).toWrapPoint))
      let displayEdit2 = (
        old: c.toWrapPoint(edit.old.a)...c.toWrapPoint(edit.old.b),
        new: c.toWrapPoint(edit.new.a)...c.toWrapPointNoClamp(edit.new.b))

      log &"      edit: {edit} -> displayEdit: {displayEdit}"

      let editRelative = (
        old: (edit.old.a - map.src.a)...(edit.old.b - map.src.a),
        new: (edit.new.a - map.src.a)...(edit.new.b - map.src.a))

      let displayEditRelative = (
        old: (displayEdit.old.a - map.dst.a)...(displayEdit.old.b - map.dst.a),
        new: (displayEdit.new.a - map.dst.a)...(displayEdit.new.b - map.dst.a))

      log &"      rel:  {editRelative} -> {displayEditRelative}"

      let editDiff = editRelative.new.b - editRelative.old.b
      let displayEditDiff = displayEditRelative.new.b - displayEditRelative.old.b

      log &"      diff: {editDiff} -> {displayEditDiff}"

      let prevChunk = currentChunk
      currentChunk.src += editDiff
      currentChunk.dst += displayEditDiff
      log &"      chunk: {prevChunk} -> {currentChunk}"

      if eu.old.b > map.src.b:
        let bias = if eu.old.b < self.map.summary.src:
          Bias.Right
        else:
          Bias.Left

        log &"  add2 current chunk {currentChunk}"
        # todo: only add when not empty
        newMap.add currentChunk
        discard c.seekForward(eu.old.b.WrapMapChunkSrc, bias, ())
        log &"  seek {eu.old.b} -> {eu.old.b} >= {c.endPos.src}"
      else:
        break

  if newMap.isEmpty or currentRange != Point()...Point():
    log &"  add final current chunk {currentChunk}"
    newMap.add currentChunk
    c.next()

  newMap.append c.suffix()

  self = WrapMapSnapshot(map: newMap.ensureMove, buffer: buffer.ensureMove)
  log &"{self}"
  # self.validate()

proc edit*(self: var WrapMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]) =
  if self.buffer.remoteId == buffer.remoteId and self.buffer.version == buffer.version:
    return
  # var t = startTimer()
  # defer:
  #   let e = t.elapsed.ms
  #   echo &"interpolate wrap map took {e} ms"

  var p = Patch[Point]()
  p.edits.setLen(1)
  for edit in patch.edits:
    var newEdit = edit
    newEdit.old.a = newEdit.new.a
    newEdit.old.b = newEdit.old.a + (edit.old.b - edit.old.a).toPoint
    p.edits[0] = newEdit
    self.editImpl(buffer.clone(), p)
  # self.validate()

proc flushEdits(self: WrapMap) =
  # var t = startTimer()
  # defer:
  #   let e = t.elapsed.ms
  #   echo &"flush edits wrap map took {e} ms"

  var firstI = 0
  for i in 0..self.pendingEdits.high:
    if self.pendingEdits[i].buffer.version.changedSince(self.snapshot.buffer.version):
      self.snapshot.edit(self.pendingEdits[i].buffer.clone(), self.pendingEdits[i].patch)
    else:
      firstI = i + 1
  # self.pendingEdits = self.pendingEdits[firstI..^1]

proc edit*(self: WrapMap, buffer: sink BufferSnapshot, edits: openArray[tuple[old, new: Selection]]) =
  var patch = Patch[Point]()
  for e in edits:
    patch.add initEdit(e.old.first.toPoint...e.old.last.toPoint, e.new.first.toPoint...e.new.last.toPoint)
  self.pendingEdits.add (buffer.ensureMove, patch)
  self.flushEdits()

proc update*(self: var WrapMapSnapshot, buffer: sink BufferSnapshot, wrapWidth: int, wrappedIndent: int) =
  # todo: Take in a patch and only recalculate line wrapping for changed lines.
  # Right now it takes around 30s to update the wrap map for a 1Gb file, with this change
  # the initial update would still take this long but incremental updates would be way faster.
  # To reduce the initial update time we could just not run the line wrapping for the entire file at first,
  # and then only trigger line wrapping for lines being rendered by calling update with a patch which covers
  # the lines to be rendered but doesn't change the length (so basically just a replace patch).

  # var t = startTimer()
  # defer:
  #   let e = t.elapsed.ms
  #   if e > 100:
  #     echo &"update wrap map took {e} ms"

  # echo &"++++++++ start wrap map update for {b.remoteId} at {b.version}"

  if wrapWidth == 0:
    let endPoint = buffer.visibleText.summary.lines
    self = WrapMapSnapshot(
      map: SumTree[WrapMapChunk].new([WrapMapChunk(src: endPoint, dst: endPoint.WrapPoint)]),
      buffer: buffer.ensureMove)
    log &"{self}"
    return

  let wrappedIndent = min(wrappedIndent, wrapWidth - 1)

  let b = buffer.clone()
  let numLines = buffer.visibleText.lines

  var currentRange = Point()...Point()
  var currentDisplayRange = wrapPoint()...wrapPoint()
  var indent = 0

  var newMap = SumTree[WrapMapChunk].new()
  while currentRange.b.row.int < numLines:
    let lineLen = buffer.visibleText.lineLen(currentRange.b.row.int)

    var i = 0
    while i + wrapWidth - indent < lineLen:
      let endI = min(i + wrapWidth - indent, lineLen)
      currentRange.b.column = endI.uint32
      currentDisplayRange.b.column = (endI - i + indent).uint32
      newMap.add(WrapMapChunk(
          src: (currentRange.b - currentRange.a).toPoint,
          dst: (currentDisplayRange.b - currentDisplayRange.a).toWrapPoint,
        ), ())

      newMap.add(WrapMapChunk(src: Point(), dst: wrapPoint(1, wrappedIndent)), ())
      indent = wrappedIndent
      currentRange = currentRange.b...currentRange.b
      currentDisplayRange = wrapPoint(currentDisplayRange.b.row + 1, indent.uint32)...wrapPoint(currentDisplayRange.b.row + 1, indent.uint32)
      i = endI

    if currentRange.b.row.int == numLines - 1:
      currentRange.b.column = lineLen.uint32
      currentDisplayRange.b.column += (currentRange.b - currentRange.a).toPoint.column
      # log &"last range: {currentRange} -> {currentDisplayRange}    | {(currentRange.b - currentRange.a).toPoint}"
      break

    currentRange.b = Point(row: currentRange.b.row + 1)
    currentDisplayRange.b = wrapPoint(currentDisplayRange.b.row + 1)
    indent = 0

  newMap.add(WrapMapChunk(
      src: (currentRange.b - currentRange.a).toPoint,
      dst: (currentDisplayRange.b - currentDisplayRange.a).toWrapPoint,
    ), ())

  self = WrapMapSnapshot(map: newMap.ensureMove, buffer: buffer.ensureMove, interpolated: false)
  # self.validate()

proc updateThread(self: ptr WrapMapSnapshot, buffer: ptr BufferSnapshot, wrapWidth: int, wrappedIndent: int): int =
  self[].update(buffer[].clone(), wrapWidth, wrappedIndent)

proc updateAsync(self: WrapMap) {.async.} =
  if self.updatingAsync: return
  self.updatingAsync = true
  defer: self.updatingAsync = false

  var b = self.snapshot.buffer.clone()

  while true:
    var snapshot = self.snapshot.clone()
    # echo &"spawn update thread for {snapshot.buffer.remoteId} at {snapshot.buffer.version}"
    let wrapWidth = self.wrapWidth
    let wrappedIndent = self.wrappedIndent
    let flowVar = spawn updateThread(snapshot.addr, b.addr, wrapWidth, wrappedIndent)
    var i = 0
    while not flowVar.isReady:
      let sleepTime = if i < 5: 1 else: 10
      await sleepAsync(sleepTime.milliseconds)
      inc i

    if self.snapshot.buffer.remoteId != snapshot.buffer.remoteId or wrapWidth != self.wrapWidth or wrappedIndent != self.wrappedIndent:
      b = self.snapshot.buffer.clone()
      continue

    # echo &"finished thread for {snapshot.buffer.remoteId} at {snapshot.buffer.version}, current {self.snapshot.buffer.version}"
    block:
      # var t = startTimer()
      # defer:
      #   let e = t.elapsed.ms
      #   echo &"update: flush edits wrap map took {e} ms"
      for i in 0..self.pendingEdits.high:
        if self.pendingEdits[i].buffer.version.changedSince(snapshot.buffer.version):
          # echo &"interpolate {snapshot.buffer.version} -> {self.pendingEdits[i].buffer.version}"
          snapshot.edit(self.pendingEdits[i].buffer.clone(), self.pendingEdits[i].patch)
    snapshot.validate()

    let oldSnapshot = self.snapshot.clone()
    self.snapshot = snapshot.clone()
    # echo &"done {self.snapshot.interpolated}"
    if not self.snapshot.interpolated:
      # echo self.snapshot
      self.pendingEdits.setLen(0)
      # echo &"WrapMap.onUpdated {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version}"
      self.onUpdated.invoke((self, oldSnapshot))
      return

    b = self.snapshot.buffer.clone()

proc update*(self: WrapMap, wrapWidth: int, force: bool = false) =
  if not force and self.wrapWidth == wrapWidth:
    return

  # echo &"WrapMap.updateWidth {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version}, {self.wrapWidth} -> {wrapWidth}, force = {force}"
  self.wrapWidth = wrapWidth
  asyncSpawn self.updateAsync()

proc update*(self: WrapMap, buffer: sink BufferSnapshot, force: bool = false) =
  # echo &"WrapMap.updateBuffer {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}, force = {force}"
  if not force and self.snapshot.buffer.remoteId == buffer.remoteId and self.snapshot.buffer.version == buffer.version:
    return

  self.snapshot.buffer = buffer.ensureMove
  asyncSpawn self.updateAsync()

proc seek*(self: var WrappedChunkIterator, wrapPoint: WrapPoint) =
  # echo &"WrappedChunkIterator.seek {self.wrapPoint} -> {wrapPoint}"
  assert wrapPoint >= self.wrapPoint
  self.wrapPoint = wrapPoint
  let point = self.wrapMap.toPoint(self.wrapPoint)
  self.chunks.seek(point)
  self.localOffset = 0
  self.styledChunk = StyledChunk.none
  self.wrapChunk = WrapChunk.none

proc seekLine*(self: var WrappedChunkIterator, line: int) =
  self.seek(wrapPoint(line))

proc next*(self: var WrappedChunkIterator): Option[WrapChunk] =
  if self.atEnd:
    self.wrapChunk = WrapChunk.none
    return

  template log(msg: untyped) =
    when false:
      if self.styledChunk.get.point.row == 209:
        echo msg

  if self.styledChunk.isNone or self.localOffset >= self.styledChunk.get.len:
    self.styledChunk = self.chunks.next()
    self.localOffset = 0
    if self.styledChunk.isNone:
      self.atEnd = true
      self.wrapChunk = WrapChunk.none
      return

  assert self.styledChunk.isSome
  var currentChunk = self.styledChunk.get
  let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)
  discard self.wrapMapCursor.seek(currentPoint.WrapMapChunkSrc, Bias.Right, ())
  if self.wrapMapCursor.item.getSome(item) and item.src == Point():
    self.wrapMapCursor.next()

  let oldWrapPoint = self.wrapPoint
  self.wrapPoint = self.wrapMapCursor.toWrapPoint(currentPoint)
  # echo &"WrappedChunkIterator.next: {oldWrapPoint} -> {self.wrapPoint}"

  let startOffset = self.localOffset
  let map = (
    src: self.wrapMapCursor.startPos.src...self.wrapMapCursor.endPos.src,
    dst: self.wrapMapCursor.startPos.dst...self.wrapMapCursor.endPos.dst)

  if currentChunk.endPoint <= map.src.b:
    self.localOffset = currentChunk.len
    currentChunk.chunk.data = cast[ptr UncheckedArray[char]](currentChunk.chunk.data[startOffset].addr)
    currentChunk.chunk.len = self.localOffset - startOffset
    currentChunk.chunk.point = currentPoint
    self.wrapChunk = WrapChunk(styledChunk: currentChunk, wrapPoint: self.wrapPoint).some

  else:
    self.localOffset = map.src.b.column.int - currentChunk.point.column.int
    currentChunk.chunk.data = cast[ptr UncheckedArray[char]](currentChunk.chunk.data[startOffset].addr)
    currentChunk.chunk.len = self.localOffset - startOffset
    currentChunk.chunk.point = currentPoint
    self.wrapChunk = WrapChunk(styledChunk: currentChunk, wrapPoint: self.wrapPoint).some

  return self.wrapChunk
