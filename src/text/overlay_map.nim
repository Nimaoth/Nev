import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm]
import nimsumtree/[rope, sumtree, buffer, clock, static_array]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import text/diff
import syntax_map
from scripting_api import Selection

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

var debugOverlayMap* = false

template log(msg: untyped) =
  when false:
    if debugOverlayMap:
      echo msg

{.push gcsafe.}
{.push raises: [].}

type OverlayPoint* {.borrow: `.`.} = distinct Point
func overlayPoint*(row: Natural = 0, column: Natural = 0): OverlayPoint = Point(row: row.uint32, column: column.uint32).OverlayPoint
func `$`*(a: OverlayPoint): string {.borrow.}
func `<`*(a: OverlayPoint, b: OverlayPoint): bool {.borrow.}
func `<=`*(a: OverlayPoint, b: OverlayPoint): bool {.borrow.}
func `==`*(a: OverlayPoint, b: OverlayPoint): bool {.borrow.}
func `+`*(a: OverlayPoint, b: OverlayPoint): OverlayPoint {.borrow.}
func `+`*(point: OverlayPoint, diff: PointDiff): OverlayPoint {.borrow.}
func `+=`*(a: var OverlayPoint, b: OverlayPoint) {.borrow.}
func `+=`*(point: var OverlayPoint, diff: PointDiff) {.borrow.}
func `-`*(a: OverlayPoint, b: OverlayPoint): PointDiff {.borrow.}
func dec*(a: var OverlayPoint): OverlayPoint {.borrow.}
func pred*(a: OverlayPoint): OverlayPoint {.borrow.}
func clone*(a: OverlayPoint): OverlayPoint {.borrow.}
func cmp*(a: OverlayPoint, b: OverlayPoint): int {.borrow.}
func clamp*(p: OverlayPoint, r: Range[OverlayPoint]): OverlayPoint = min(max(p, r.a), r.b)
converter toOverlayPoint*(diff: PointDiff): OverlayPoint = diff.toPoint.OverlayPoint

type
  OverlayMapChunkKind* {.pure.} = enum
    Empty
    String
    Rope
    # DisplayMap

  OverlayMapChunk* = object
    id*: int
    src*: Point
    srcBytes*: int
    dst*: OverlayPoint
    dstBytes*: int
    case kind*: OverlayMapChunkKind
    of OverlayMapChunkKind.Empty: discard
    of OverlayMapChunkKind.String:
      text*: string
      scope*: string
    of OverlayMapChunkKind.Rope:
      r: RopeSlice[Point]

  OverlayMapChunkSummary* = object
    src*: Point # 8 bytes
    dst*: OverlayPoint # 8 bytes
    srcBytes*: int # 8 bytes, todo: 4 bytes
    dstBytes*: int # 8 bytes, todo: 4 bytes
    idCounts*: Array[uint16, 16] # 32 bytes

  OverlayMapChunkSrc* = distinct Point
  OverlayMapChunkDst* = distinct OverlayPoint
  OverlayMapChunkIdCount* = distinct int

# Make OverlayMapChunk an Item
func clone*(self: OverlayMapChunk): OverlayMapChunk =
  case self.kind
  of OverlayMapChunkKind.Empty: OverlayMapChunk(kind: OverlayMapChunkKind.Empty, id: self.id, src: self.src, dst: self.dst, srcBytes: self.srcBytes, dstBytes: self.dstBytes)
  of OverlayMapChunkKind.String: OverlayMapChunk(kind: OverlayMapChunkKind.String, id: self.id, src: self.src, dst: self.dst, srcBytes: self.srcBytes, dstBytes: self.dstBytes, text: self.text, scope: self.scope)
  of OverlayMapChunkKind.Rope: OverlayMapChunk(kind: OverlayMapChunkKind.Rope, id: self.id, src: self.src, dst: self.dst, srcBytes: self.srcBytes, dstBytes: self.dstBytes, r: self.r.clone())

func summary*(self: OverlayMapChunk): OverlayMapChunkSummary =
  var idCounts: Array[uint16, 16]
  idCounts.len = self.id.int + 1
  idCounts[self.id] = 1
  OverlayMapChunkSummary(
    src: self.src,
    srcBytes: self.srcBytes,
    dst: self.dst,
    dstBytes: self.dstBytes,
    idCounts: idCounts,
  )

func fromSummary*[C](_: typedesc[OverlayMapChunkSummary], self: OverlayMapChunkSummary, cx: C): OverlayMapChunkSummary = self

# Make OverlayMapChunkSummary a Summary
func addSummary*[C](self: var OverlayMapChunkSummary, b: OverlayMapChunkSummary, cx: C) =
  self.src += b.src
  self.srcBytes += b.srcBytes
  self.dst += b.dst
  self.dstBytes += b.dstBytes
  self.idCounts.len = max(self.idCounts.len, b.idCounts.len)
  for i in 0..<b.idCounts.len:
    self.idCounts[i] += b.idCounts[i]

# Make OverlayMapChunkDst a Dimension
func cmp*[C](a: OverlayMapChunkDst, b: OverlayMapChunkSummary, cx: C): int = cmp(a.OverlayPoint, b.dst)

# Make OverlayMapChunkSrc a Dimension
func cmp*[C](a: OverlayMapChunkSrc, b: OverlayMapChunkSummary, cx: C): int = cmp(a.Point, b.src)

# Make OverlayMapChunkIdCount a Dimension
func cmp*(a: OverlayMapChunkIdCount, b: OverlayMapChunkSummary, cx: int): int =
  if cx >= b.idCounts.len:
    return cmp(a.int, 0)
  cmp(a.int, b.idCounts[cx].int)

type
  OverlayChunk* = object
    styledChunk*: StyledChunk
    overlayPoint*: OverlayPoint

  OverlayMapChunkCursor* = sumtree.Cursor[OverlayMapChunk, OverlayMapChunkSummary]

  OverlayMapSnapshot* = object
    map*: SumTree[OverlayMapChunk]
    buffer*: BufferSnapshot
    version*: int

  OverlayMap* = ref object
    snapshot*: OverlayMapSnapshot
    onUpdated*: Event[tuple[map: OverlayMap, old: OverlayMapSnapshot, patch: Patch[OverlayPoint]]]

  OverlayChunkIterator* = object
    styledChunks*: StyledChunkIterator
    styledChunk: Option[StyledChunk]
    overlayChunk: Option[OverlayChunk]
    overlayMap {.cursor.}: OverlayMapSnapshot
    overlayMapCursor: OverlayMapChunkCursor
    overlayPoint*: OverlayPoint
    localOffset: int
    atEnd*: bool

    subIterKind: OverlayMapChunkKind
    stringOffset: int
    stringRuneOffset: int
    stringLine: int
    ropeIter: ChunkIterator

func clone*(self: OverlayMapSnapshot): OverlayMapSnapshot =
  OverlayMapSnapshot(map: self.map.clone(), buffer: self.buffer.clone(), version: self.version)

proc new*(_: typedesc[OverlayMap]): OverlayMap =
  result = OverlayMap(snapshot: OverlayMapSnapshot(map: SumTree[OverlayMapChunk].new([OverlayMapChunk()])))

proc desc*(self: OverlayMapSnapshot): string =
  &"OverlayMap(@{self.version}, {self.map.summary}, {self.buffer.remoteId}@{self.buffer.version})"

proc `$`*(self: OverlayMapSnapshot): string =
  result.add self.desc
  result.add "\n"
  var c = self.map.initCursor(OverlayMapChunkSummary)
  var i = 0
  while not c.atEnd:
    c.next()
    if c.item.getSome(item):
      let r = c.startPos.src...c.endPos.src
      let rd = c.startPos.dst...c.endPos.dst
      let b = c.startPos.srcBytes...c.endPos.srcBytes
      let bd = c.startPos.dstBytes...c.endPos.dstBytes
      if item.src != Point() or true:
        result.add &"  {i} #{item.id}: {item.src} -> {item.dst}  {item.srcBytes} -> {item.dstBytes}   |   {r} -> {rd}  {b} -> {bd}  {item.kind}\n"
        inc i

proc iter*(overlay {.byref.}: OverlayMapSnapshot): OverlayChunkIterator =
  # echo &"OverlayMapSnapshot.iter {overlay}"
  result = OverlayChunkIterator(
    styledChunks: StyledChunkIterator.init(overlay.buffer.visibleText),
    overlayMap: overlay.clone(),
    overlayMapCursor: overlay.map.initCursor(OverlayMapChunkSummary),
  )

func point*(self: OverlayChunkIterator): Point = self.styledChunks.point
func chunk*(self: var OverlayChunk): var RopeChunk = self.styledChunk.chunk
func chunk*(self: OverlayChunk): RopeChunk = self.styledChunk.chunk
func point*(self: OverlayChunk): Point = self.styledChunk.point
func endPoint*(self: OverlayChunk): Point = self.styledChunk.endPoint
func endOverlayPoint*(self: OverlayChunk): OverlayPoint = overlayPoint(self.overlayPoint.row, self.overlayPoint.column + self.styledChunk.len.uint32)
func len*(self: OverlayChunk): int = self.styledChunk.len
func `$`*(self: OverlayChunk): string = &"OC({self.overlayPoint}...{self.endOverlayPoint}, {self.styledChunk})"
template toOpenArray*(self: OverlayChunk): openArray[char] = self.styledChunk.toOpenArray
template scope*(self: OverlayChunk): string = self.styledChunk.scope

func isNil*(self: OverlayMapSnapshot): bool = self.map.isNil

func endOverlayPoint*(self: OverlayMapSnapshot): OverlayPoint = self.map.summary.dst

proc toOverlayPoint*(self: OverlayMapChunkCursor, point: Point): OverlayPoint =
  let point2 = point.clamp(self.startPos.src...self.endPos.src)
  let offset = point2 - self.startPos.src
  return (self.startPos.dst + offset.toOverlayPoint).clamp(self.startPos.dst...self.endPos.dst)

proc toOverlayBytes*(self: OverlayMapChunkCursor, bytes: int): int =
  let bytes2 = bytes.clamp(self.startPos.srcBytes, self.endPos.srcBytes)
  let offset = bytes2 - self.startPos.srcBytes
  return (self.startPos.dstBytes + offset).clamp(self.startPos.dstBytes, self.endPos.dstBytes)

proc toOverlayPoint*(self: OverlayMapSnapshot, point: Point, bias: Bias = Bias.Right): OverlayPoint =
  var c = self.map.initCursor(OverlayMapChunkSummary)
  discard c.seek(point.OverlayMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.src == Point():
    c.next()

  return c.toOverlayPoint(point)

proc toOverlayPoint*(self: OverlayMap, point: Point, bias: Bias = Bias.Right): OverlayPoint =
  self.snapshot.toOverlayPoint(point, bias)

proc toPoint*(self: OverlayMapChunkCursor, point: OverlayPoint): Point =
  let point = point.clamp(self.startPos.dst...self.endPos.dst)
  let offset = point - self.startPos.dst
  # echo &"toPoint {point}, {self.startPos}, {self.endPos} -> offset {offset}, {self.startPos.src + offset.toPoint}"
  return (self.startPos.src + offset.toPoint).clamp(self.startPos.src...self.endPos.src)

proc toPoint*(self: OverlayMapSnapshot, point: OverlayPoint, bias: Bias = Bias.Right): Point =
  var c = self.map.initCursor(OverlayMapChunkSummary)
  discard c.seek(point.OverlayMapChunkDst, bias, ())
  return c.toPoint(point)

proc toPoint*(self: OverlayMap, point: OverlayPoint, bias: Bias = Bias.Right): Point =
  self.snapshot.toPoint(point, bias)

proc toOverlayBytes*(self: OverlayMapChunkCursor, overlay: OverlayMapSnapshot, overlayPoint: OverlayPoint): int =
  if self.item.isNone:
    # echo &"toOverlayBytes {overlayPoint}\n{overlay}"
    return self.endPos.dstBytes
  let item = self.item.get
  let offset = case item.kind
  of OverlayMapChunkKind.Empty:
    let point = self.toPoint(overlayPoint)
    let bytes = overlay.buffer.visibleText.pointToOffset(point)
    let offset = bytes - self.startPos.srcBytes
    offset

  of OverlayMapChunkKind.String:
    let localPoint = (overlayPoint - self.startPos.dst).toPoint
    let offset = item.text.toOpenArray(0, item.text.high).pointToOffset(localPoint)
    offset

  of OverlayMapChunkKind.Rope:
    0

  return (self.startPos.dstBytes + offset).clamp(self.startPos.dstBytes, self.endPos.dstBytes)

proc toOverlayBytes*(self: OverlayMapSnapshot, overlayPoint: OverlayPoint, bias: Bias = Bias.Right): int =
  var c = self.map.initCursor(OverlayMapChunkSummary)
  discard c.seek(overlayPoint.OverlayMapChunkDst, bias, ())
  return c.toOverlayBytes(self, overlayPoint)

proc lineLen*(self: OverlayMapSnapshot, line: int): int =
  let startOffset = self.toOverlayBytes(overlayPoint(line))
  if line == self.endOverlayPoint.row.int:
    return self.map.summary.dstBytes - startOffset
  let endOffset = self.toOverlayBytes(overlayPoint(line + 1)) - 1
  assert endOffset >= startOffset
  return endOffset - startOffset

proc lineRange*(self: OverlayMapSnapshot, line: int): Range[OverlayPoint] =
  return overlayPoint(line, 0)...overlayPoint(line, self.lineLen(line))

proc setBuffer*(self: OverlayMap, buffer: sink BufferSnapshot) =
  # logMapUpdate &"OverlayMap.setBuffer {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}"
  if self.snapshot.buffer.remoteId == buffer.remoteId and self.snapshot.buffer.version == buffer.version:
    return

  let endOffset = buffer.visibleText.summary.bytes
  let endPoint = buffer.visibleText.summary.lines
  self.snapshot = OverlayMapSnapshot(
    map: SumTree[OverlayMapChunk].new([OverlayMapChunk(src: endPoint, dst: endPoint.OverlayPoint, srcBytes: endOffset, dstBytes: endOffset)]),
    buffer: buffer.ensureMove,
  )

proc validate*(self: OverlayMapSnapshot) =
  # log &"validate {self.buffer.remoteId}{self.buffer.version}"
  var c = self.map.initCursor(OverlayMapChunkSummary)
  var endPos = Point()
  c.next()
  while c.item.getSome(_):
    endPos = c.endPos.src
    c.next()

  if endPos != self.buffer.visibleText.summary.lines:
    echo &"--------------------------------\n-------------------------------\nInvalid overlay map {self.buffer.remoteId}{self.buffer.version}, endpos {endPos} != {self.buffer.visibleText.summary.lines}\n{self}\n---------------------------------------"
    return

  if self.map.summary.src != self.buffer.visibleText.summary.lines:
    echo &"--------------------------------\n-------------------------------\nInvalid overlay map {self.buffer.remoteId}{self.buffer.version}, summary {self.map.summary.src} != {self.buffer.visibleText.summary.lines}\n{self}\n---------------------------------------"
    return


proc edit*(self: var OverlayMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]): Patch[OverlayPoint] =
  if self.buffer.remoteId == buffer.remoteId and self.buffer.version == buffer.version:
    return

  logMapUpdate &"OverlayMapSnapshot.edit {self.buffer.remoteId}@{self.buffer.version} -> {buffer.remoteId}@{buffer.version} | {patch}"

  # todo
  # var c = self.map.initCursor(OverlayMapChunkSummary)
  for e in patch.edits:
  #   discard c.seek(e.old.a.OverlayMapChunkSrc, Bias.Right, ())
  #   # todo: translate Point to OverlayPoint properly
    result.add initEdit(e.old.a.OverlayPoint...e.old.b.OverlayPoint, e.new.a.OverlayPoint...e.new.b.OverlayPoint)
  #   let oldAOverlay = c.toOverlayPoint(e.old.a)
  #   discard c.seek(e.old.b.OverlayMapChunkSrc, Bias.Right, ())
  #   let oldBOverlay = c.toOverlayPoint(e.old.b)
  #   # if c.item.getSome(item) and item.src == Point():
  #   #   c.next()

  let endPoint = buffer.visibleText.summary.lines
  let endOffset = buffer.visibleText.summary.bytes
  self = OverlayMapSnapshot(
    map: SumTree[OverlayMapChunk].new([OverlayMapChunk(src: endPoint, dst: endPoint.OverlayPoint, srcBytes: endOffset, dstBytes: endOffset)]),
    buffer: buffer.clone(),
    version: self.version + 1,
  )

proc edit*(self: OverlayMap, buffer: sink BufferSnapshot, patch: Patch[Point]): Patch[OverlayPoint] =
  self.snapshot.edit(buffer, patch)

proc update*(self: var OverlayMapSnapshot, buffer: sink BufferSnapshot) =
  discard

proc updateThread(self: ptr OverlayMapSnapshot, buffer: ptr BufferSnapshot): int =
  self[].update(buffer[].clone())

proc update*(self: OverlayMap, buffer: sink BufferSnapshot, force: bool = false) =
  logMapUpdate &"OverlayMap.updateBuffer {self.snapshot.desc} -> {buffer.remoteId}@{buffer.version}, force = {force}"
  if not force and self.snapshot.buffer.remoteId == buffer.remoteId and self.snapshot.buffer.version == buffer.version:
    return

  self.snapshot.buffer = buffer.ensureMove

  let endPoint = self.snapshot.buffer.visibleText.summary.lines
  let endOffset = self.snapshot.buffer.visibleText.summary.bytes
  self.snapshot = OverlayMapSnapshot(
    map: SumTree[OverlayMapChunk].new([OverlayMapChunk(src: endPoint, dst: endPoint.OverlayPoint, srcBytes: endOffset, dstBytes: endOffset)]),
    buffer: self.snapshot.buffer.clone(),
    version: self.snapshot.version + 1,
  )

proc clear*(self: OverlayMap, id: int = -1) =
  logMapUpdate &"OverlayMap.clear {id}, {self.snapshot.desc}"
  let old = self.snapshot.clone()
  var newMap = SumTree[OverlayMapChunk].new()
  var patch: Patch[OverlayPoint]

  if id == -1:
    let endPoint = self.snapshot.buffer.visibleText.summary.lines
    let endOffset = self.snapshot.buffer.visibleText.summary.bytes
    newMap.add OverlayMapChunk(src: endPoint, dst: endPoint.OverlayPoint, srcBytes: endOffset, dstBytes: endOffset)

    var c = old.map.initCursor(OverlayMapChunkSummary)
    c.next()
    while c.item.getSome(item):
      if item.kind != OverlayMapChunkKind.Empty:
        patch.add initEdit(c.startPos.dst...c.endPos.dst, c.startPos.src.OverlayPoint...c.endPos.src.OverlayPoint)
      c.next()
    # let fullPatch = initPatch([initEdit(overlayPoint(0, 0)...old.map.summary.dst, overlayPoint(0, 0)...endPoint.OverlayPoint)])

  else:
    var c = self.snapshot.map.initCursor(OverlayMapChunkSummary)
    let totalCount = if id < self.snapshot.map.summary.idCounts.len:
      self.snapshot.map.summary.idCounts[id].int
    else:
      0
    # echo &"clear {id} count {totalCount}"
    var lastEmpty = false
    for i in 0..<totalCount:
      let s = c.slice(i.OverlayMapChunkIdCount, Bias.Right, id)
      if not s.isEmpty:
        newMap.append s
        lastEmpty = false

      if c.item.getSome(item):
        # echo &"  {c.startPos}...{c.endPos}: {item[]}"

        var skipNext = false
        if lastEmpty or (c.prevItem.getSome(prevItem) and prevItem.kind == OverlayMapChunkKind.Empty):
          lastEmpty = true
          newMap.updateLast proc(chunk: var OverlayMapChunk) =
            chunk.src += item.src
            chunk.srcBytes += item.srcBytes
            chunk.dst += item.dst
            chunk.dstBytes += item.dstBytes

            if c.nextItem.getSome(nextItem) and nextItem.kind == OverlayMapChunkKind.Empty:
              chunk.src += nextItem.src
              chunk.srcBytes += nextItem.srcBytes
              chunk.dst += nextItem.dst
              chunk.dstBytes += nextItem.dstBytes
              skipNext = true

        elif item.src != point(0, 0):
          newMap.add OverlayMapChunk(src: item.src, dst: item.src.OverlayPoint, srcBytes: item.srcBytes, dstBytes: item.srcBytes)
          lastEmpty = item.kind == OverlayMapChunkKind.Empty

        patch.add initEdit(c.startPos.dst...c.endPos.dst, c.startPos.src.OverlayPoint...c.endPos.src.OverlayPoint)
        c.next()
        if skipNext:
          c.next()

      # else:
      #   echo &"  aaaaaaaaaa {c.startPos}...{c.endPos}"

    newMap.append c.suffix()

  self.snapshot = OverlayMapSnapshot(
    map: newMap,
    buffer: self.snapshot.buffer.clone(),
    version: self.snapshot.version + 1,
  )

  # echo patch
  # echo self.snapshot
  self.onUpdated.invoke (self, old, patch)

proc addOverlay*(self: OverlayMap, range: Range[Point], text: string, id: int, scope: string = "") =
  # echo &"OverlayMap.addOverlay {range}, '{text}'\n{self.snapshot}"
  let newSummary = TextSummary.init(text)
  var newMap = SumTree[OverlayMapChunk].new()

  var patch: Patch[OverlayPoint]

  let byteRange = self.snapshot.buffer.visibleText.pointToOffset(range.a)...self.snapshot.buffer.visibleText.pointToOffset(range.b)

  var c = self.snapshot.map.initCursor(OverlayMapChunkSummary)
  newMap.append c.slice(range.a.OverlayMapChunkSrc, Bias.Right)

  # echo &"  current: {newMap.summary}, current: {c.startPos}...{c.endPos}"
  if range.a > c.startPos.src:
    if c.item.getSome(item):
      if item.kind == OverlayMapChunkKind.String:
        discard # todo
      else:
        let newRange = (range.a - c.startPos.src).toPoint
        let newByteRange = byteRange.a - c.startPos.srcBytes
        # echo &"  add start of overlappin chunk {newRange}"
        newMap.add OverlayMapChunk(src: newRange, dst: newRange.OverlayPoint, srcBytes: newByteRange, dstBytes: newByteRange)

  newMap.add OverlayMapChunk(id: id, src: range.len, dst: newSummary.lines.OverlayPoint, srcBytes: byteRange.len, dstBytes: newSummary.bytes, kind: OverlayMapChunkKind.String, text: text, scope: scope)

  let overlayRangeOld = self.toOverlayPoint(range.a)...self.toOverlayPoint(range.b)
  let overlayRangeNew = overlayRangeOld.a...(overlayRangeOld.a + newSummary.lines.OverlayPoint)
  patch.add initEdit(overlayRangeOld, overlayRangeNew)

  if range.b < c.endPos.src:
    if c.item.getSome(item):
      if item.kind == OverlayMapChunkKind.String:
        discard # todo
      else:
        let newRange = (c.endPos.src - range.b).toPoint
        let newByteRange = c.endPos.srcBytes - byteRange.b
        # echo &"  add end of overlappin chunk {newRange}"
        newMap.add OverlayMapChunk(src: newRange, dst: newRange.OverlayPoint, srcBytes: newByteRange, dstBytes: newByteRange)

  c.next()
  newMap.append c.suffix()
  let newSnapshot = OverlayMapSnapshot(
    map: newMap,
    buffer: self.snapshot.buffer.clone(),
    version: self.snapshot.version + 1,
  )
  # echo newSnapshot
  let old = self.snapshot.clone()
  self.snapshot = newSnapshot
  self.onUpdated.invoke (self, old, patch)

proc seek*(self: var OverlayChunkIterator, point: Point) =
  # echo &"OverlayChunkIterator.seek {self.overlayPoint} -> {overlayPoint}"
  self.styledChunks.seek(point)
  discard self.overlayMapCursor.seekForward(point.OverlayMapChunkSrc, Bias.Left, ())
  let overlayPoint = self.overlayMapCursor.toOverlayPoint(point)
  assert overlayPoint >= self.overlayPoint
  self.overlayPoint = overlayPoint
  self.localOffset = 0
  self.styledChunk = StyledChunk.none
  self.overlayChunk = OverlayChunk.none

proc seek*(self: var OverlayChunkIterator, overlayPoint: OverlayPoint) =
  # echo &"OverlayChunkIterator.seek {self.overlayPoint} -> {overlayPoint}"
  assert overlayPoint >= self.overlayPoint
  discard self.overlayMapCursor.seekForward(overlayPoint.OverlayMapChunkDst, Bias.Left, ())
  self.overlayPoint = overlayPoint
  let point = self.overlayMapCursor.toPoint(self.overlayPoint)
  self.styledChunks.seek(point)
  self.localOffset = 0
  self.styledChunk = StyledChunk.none
  self.overlayChunk = OverlayChunk.none

  if self.overlayMapCursor.endPos.src > self.overlayMapCursor.startPos.src and overlayPoint == self.overlayMapCursor.endPos.dst:
    # echo &"at end of {self.overlayMapCursor.startPos} -> {self.overlayMapCursor.endPos}"
    self.overlayMapCursor.next()
  if self.overlayMapCursor.item.getSome(item):
    case item.kind
    of OverlayMapChunkKind.Empty:
      self.subIterKind = OverlayMapChunkKind.Empty
    of OverlayMapChunkKind.String:
      self.subIterKind = OverlayMapChunkKind.String
      # self.stringLine = overlayPoint.row.int - self.overlayMapCursor.startPos.dst.row.int
      self.stringLine = 0 # todo
      self.stringOffset = item.text.toOpenArray(0, item.text.high).pointToOffset((overlayPoint - self.overlayMapCursor.startPos.dst).toPoint)
      self.stringRuneOffset = item.text.toOpenArray(0, item.text.high).pointToCount((overlayPoint - self.overlayMapCursor.startPos.dst).toPoint).int
      # echo &"OverlayChunkIterator.seek {overlayPoint} -> {self.stringLine}, {self.stringOffset}"
    of OverlayMapChunkKind.Rope:
      # todo
      self.subIterKind = OverlayMapChunkKind.Rope
      self.stringLine = 0 # todo
      self.stringOffset = 0 # todo
      self.stringRuneOffset = 0 # todo

proc seekLine*(self: var OverlayChunkIterator, line: int) =
  self.seek(overlayPoint(line))

proc next*(self: var OverlayChunkIterator): Option[OverlayChunk] =
  if self.atEnd:
    self.overlayChunk = OverlayChunk.none
    return

  # echo &"Overlay.next {self.overlayPoint}, {self.styledChunks.point}, {self.subIterKind}"
  # defer:
  #   echo &"  -> {result}"

  if self.subIterKind == OverlayMapChunkKind.Empty:
    if self.styledChunk.isNone or self.localOffset >= self.styledChunk.get.len:
      self.styledChunk = self.styledChunks.next()
      self.localOffset = 0
      if self.styledChunk.isNone:
        self.atEnd = true
        self.overlayChunk = OverlayChunk.none
        return

    assert self.styledChunk.isSome
    var currentChunk = self.styledChunk.get
    let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)
    if not self.overlayMapCursor.didSeek() or currentPoint > self.overlayMapCursor.endPos.src:
      discard self.overlayMapCursor.seekForward(currentPoint.OverlayMapChunkSrc, Bias.Left, ())

    if currentPoint == self.overlayMapCursor.endPos.src and self.overlayMapCursor.startPos.src != self.overlayMapCursor.endPos.src:
      self.overlayMapCursor.next()

    self.overlayPoint = self.overlayMapCursor.toOverlayPoint(currentPoint)

  let mappedPoint = self.overlayMapCursor.toPoint(self.overlayPoint)

  if self.overlayMapCursor.item.getSome(item):
    case item.kind
    of OverlayMapChunkKind.String:
      let (line, offset, runeOffset) = if self.subIterKind == OverlayMapChunkKind.String:
        (self.stringLine, self.stringOffset, self.stringRuneOffset)
      else:
        (0, 0, 0)

      let nl = item.text.find('\n', offset)
      let endOffset = if nl == -1:
        item.text.len
      else:
        nl

      let endRuneOffset = item.text.offsetToCount(endOffset).int

      var dataOriginal: ptr UncheckedArray[char] = nil
      var lenOriginal = 0
      # if self.styledChunk.getSome(styledChunk):
      #   let offsetOriginal = styledChunk.chunk.toOpenArrayOriginal.countToOffset(runeOffset.Count)
      #   let chunkOriginal = styledChunk.split(offsetOriginal).suffix.split(endOffset).prefix
      #   dataOriginal = chunkOriginal.chunk.dataOriginal
      #   lenOriginal = chunkOriginal.chunk.lenOriginal
      #   echo &"  {chunkOriginal}"

      let currentChunk = StyledChunk(
        chunk: RopeChunk(
          data: if offset < item.text.len:
            cast[ptr UncheckedArray[char]](item.text[offset].addr)
          else:
            nil,
          len: endOffset - offset,
          # dataOriginal: if offset < item.text.len:
          #   cast[ptr UncheckedArray[char]](item.text[offset].addr)
          # else:
          #   nil,
          # lenOriginal: endOffset - offset,
          dataOriginal: dataOriginal,
          lenOriginal: lenOriginal,
          point: mappedPoint + point(line, 0),
          external: true,
        ),
        scope: item.scope,
        drawWhitespace: false,
      )

      let overlayChunk = OverlayChunk(styledChunk: currentChunk, overlayPoint: self.overlayPoint)
      # echo "  ", overlayChunk

      if endOffset == item.text.len:
        self.subIterKind = OverlayMapChunkKind.Empty
        self.stringLine = 0
        self.stringOffset = 0
        self.stringRuneOffset = 0

        if self.overlayMapCursor.startPos.src == self.overlayMapCursor.endPos.src:
          # echo &"  next"
          self.overlayMapCursor.next()
        else:
          # echo &"  seek {self.overlayMapCursor.startPos.src} != {self.overlayMapCursor.endPos.src}"
          self.seek(self.overlayMapCursor.endPos.src)
          if self.overlayMapCursor.endPos.src > self.overlayMapCursor.startPos.src and self.overlayPoint == self.overlayMapCursor.endPos.dst:
            # echo &"at end of {self.overlayMapCursor.startPos} -> {self.overlayMapCursor.endPos}"
            # echo &"  and next, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}, {self.overlayPoint}"
            self.overlayMapCursor.next()

        if self.overlayMapCursor.item.getSome(item) and item.kind != OverlayMapChunkKind.Empty:
          # echo &"  Next chunk also string {item[]}, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}, {self.overlayPoint}"
          self.subIterKind = item.kind
      else:
        self.subIterKind = OverlayMapChunkKind.String
        self.overlayPoint += overlayPoint(1, 0)
        self.stringLine = line + 1
        self.stringOffset = endOffset + 1
        self.stringRuneOffset = endRuneOffset + 1

      self.overlayChunk = overlayChunk.some
      return self.overlayChunk

    of OverlayMapChunkKind.Rope:
      # todo
      discard

    else:
      discard

  var currentChunk = self.styledChunk.get
  let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)
  if self.overlayMapCursor.startPos.src == self.overlayMapCursor.endPos.src:
    if currentPoint < self.overlayMap.map.summary.src:
      # echo &"aaaaaaaaaaaaaaaaaaaa {currentPoint}, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}"
      assert false, &"aaaaaaaaaaaaaaaaaaaa {currentPoint}, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}"
      self.overlayMapCursor.next()
      self.overlayPoint = self.overlayMapCursor.toOverlayPoint(currentPoint)

  let startOffset = self.localOffset
  let map = (
    src: self.overlayMapCursor.startPos.src...self.overlayMapCursor.endPos.src,
    dst: self.overlayMapCursor.startPos.dst...self.overlayMapCursor.endPos.dst)

  if currentChunk.endPoint <= map.src.b:
    self.localOffset = currentChunk.len
    var newChunk = currentChunk.split(startOffset).suffix.split(self.localOffset - startOffset).prefix
    newChunk.chunk.point = mappedPoint
    self.overlayChunk = OverlayChunk(styledChunk: newChunk, overlayPoint: self.overlayPoint).some

  else:
    self.localOffset = map.src.b.column.int - currentChunk.point.column.int
    var newChunk = currentChunk.split(startOffset).suffix.split(self.localOffset - startOffset).prefix
    newChunk.chunk.point = mappedPoint
    self.overlayChunk = OverlayChunk(styledChunk: newChunk, overlayPoint: self.overlayPoint).some

  return self.overlayChunk

#

proc split*(self: OverlayChunk, index: int): tuple[prefix: OverlayChunk, suffix: OverlayChunk] =
  let (prefix, suffix) = self.styledChunk.split(index)
  (
    OverlayChunk(styledChunk: prefix, overlayPoint: self.overlayPoint),
    OverlayChunk(styledChunk: suffix, overlayPoint: overlayPoint(self.overlayPoint.row, self.overlayPoint.column + index.uint32)),
  )

proc `[]`*(self: OverlayChunk, r: Range[int]): OverlayChunk =
  OverlayChunk(styledChunk: self.styledChunk[r], overlayPoint: overlayPoint(self.overlayPoint.row, self.overlayPoint.column + r.a.uint32))

func toOutputPoint*(self: OverlayMapSnapshot, point: Point, bias: Bias): OverlayPoint {.inline.} = self.toOverlayPoint(point, bias)
func `outputPoint=`*(self: var OverlayChunk, point: OverlayPoint) = self.overlayPoint = point
template outputPoint*(self: OverlayChunk): OverlayPoint = self.overlayPoint
template endOutputPoint*(self: OverlayChunk): OverlayPoint = self.endOverlayPoint
template endOutputPoint*(self: OverlayMapSnapshot): OverlayPoint = self.endOverlayPoint
func outputPoint*(self: OverlayChunkIterator): OverlayPoint = self.overlayPoint
