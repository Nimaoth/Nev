import std/[options, strutils, atomics, strformat, tables]
import nimsumtree/[rope, sumtree, buffer, clock, static_array]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import syntax_map

var debugOverlayMap* = false

{.push gcsafe.}
{.push raises: [].}

const debugOverlayMapUpdates* = false
var debugOverlayMapUpdatesRT* = true

template logOverlayMapUpdate*(msg: untyped) =
  when debugAllMapUpdates or debugOverlayMapUpdates:
    if debugAllMapUpdatesRT or debugOverlayMapUpdatesRT:
      debugEcho msg

type InputMapSnapshot = BufferSnapshot
type InputChunkIterator = StyledChunkIterator
type InputChunk = StyledChunk
type InputPoint = Point
proc inputPoint(row: Natural = 0, column: Natural = 0): InputPoint {.inline.} = point(row, column)
proc toInputPoint(d: PointDiff): InputPoint {.inline.} = d.toPoint

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
    bias*: Bias
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
  of OverlayMapChunkKind.Empty: OverlayMapChunk(kind: OverlayMapChunkKind.Empty, id: self.id, src: self.src, dst: self.dst, srcBytes: self.srcBytes, dstBytes: self.dstBytes, bias: self.bias)
  of OverlayMapChunkKind.String: OverlayMapChunk(kind: OverlayMapChunkKind.String, id: self.id, src: self.src, dst: self.dst, srcBytes: self.srcBytes, dstBytes: self.dstBytes, text: self.text, scope: self.scope, bias: self.bias)
  of OverlayMapChunkKind.Rope: OverlayMapChunk(kind: OverlayMapChunkKind.Rope, id: self.id, src: self.src, dst: self.dst, srcBytes: self.srcBytes, dstBytes: self.dstBytes, r: self.r.clone(), bias: self.bias)

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
      result.add &"  {i} #{item.id}: {item.src} -> {item.dst}  {item.srcBytes} -> {item.dstBytes}   |   {r} -> {rd}  {b} -> {bd}  {item.kind}  {item.bias}"
      if item.kind == OverlayMapChunkKind.String:
        result.add "  '"
        result.add item.text
        result.add "'"
      result.add "\n"
      inc i

proc iter*(overlay {.byref.}: OverlayMapSnapshot): OverlayChunkIterator =
  # debugEcho &"OverlayMapSnapshot.iter {overlay}"
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

proc toOverlayRange*(self: OverlayMapSnapshot, range: Range[Point], bias: Bias = Bias.Right): Range[OverlayPoint] =
  var c = self.map.initCursor(OverlayMapChunkSummary)
  discard c.seek(range.a.OverlayMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.src == Point():
    c.next()

  result.a = c.toOverlayPoint(range.a)
  if range.b > c.endPos.src:
    discard c.seek(range.b.OverlayMapChunkSrc, Bias.Right, ())
    if c.item.getSome(item) and item.src == Point():
      c.next()

  result.b = c.toOverlayPoint(range.b)

proc toOverlayPoint*(self: OverlayMap, point: Point, bias: Bias = Bias.Right): OverlayPoint =
  self.snapshot.toOverlayPoint(point, bias)

proc toPoint*(self: OverlayMapChunkCursor, point: OverlayPoint): Point =
  let point = point.clamp(self.startPos.dst...self.endPos.dst)
  let offset = point - self.startPos.dst
  # debugEcho &"toPoint {point}, {self.startPos}, {self.endPos} -> offset {offset}, {self.startPos.src + offset.toPoint}"
  return (self.startPos.src + offset.toPoint).clamp(self.startPos.src...self.endPos.src)

proc toPoint*(self: OverlayMapSnapshot, point: OverlayPoint, bias: Bias = Bias.Right): Point =
  var c = self.map.initCursor(OverlayMapChunkSummary)
  discard c.seek(point.OverlayMapChunkDst, bias, ())
  return c.toPoint(point)

proc toPoint*(self: OverlayMap, point: OverlayPoint, bias: Bias = Bias.Right): Point =
  self.snapshot.toPoint(point, bias)

proc toOverlayBytes*(self: OverlayMapChunkCursor, overlay: OverlayMapSnapshot, overlayPoint: OverlayPoint): int =
  if self.item.isNone:
    # debugEcho &"toOverlayBytes {overlayPoint}\n{overlay}"
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
  logOverlayMapUpdate &"OverlayMap.setBuffer {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}"
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
    debugEcho &"--------------------------------\n-------------------------------\nInvalid overlay map {self.buffer.remoteId}{self.buffer.version}, endpos {endPos} != {self.buffer.visibleText.summary.lines}\n{self}\n---------------------------------------"
    return

  if self.map.summary.src != self.buffer.visibleText.summary.lines:
    debugEcho &"--------------------------------\n-------------------------------\nInvalid overlay map {self.buffer.remoteId}{self.buffer.version}, summary {self.map.summary.src} != {self.buffer.visibleText.summary.lines}\n{self}\n---------------------------------------"
    return


proc clear*(self: var OverlayMapSnapshot, id: int = -1): Patch[OverlayPoint]

proc clamp[T](self: T, other: Range[T]): T = max(min(self, other.b), other.a)
proc clamp[T](self: Range[T], other: Range[T]): Range[T] = self.a.clamp(other)...self.b.clamp(other)

# Instantiating Edit[T] directly doesn't work, because sumtree also exports an Edit[T] type and even if I use buffer.Edit[:T], the compiler tries to instantiate sumtree.Edit[T] aswell
# which fails for int because sumtree.Edit has some additional requirements. Maybe adding a concept would help?
type BufferByteEdit = typeof(Patch[int]().edits[0])
proc editImpl(self: var OverlayMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point], byteEditAbsolute: BufferByteEdit, version: int, old: OverlayMapSnapshot): Patch[OverlayPoint] =
  template logEdit(msg: untyped) =
    if false:
      debugEcho msg

  var delete = false

  var newMap = SumTree[OverlayMapChunk].new()
  var c = self.map.initCursor(OverlayMapChunkSummary)
  var currentChunk = OverlayMapChunk()

  logOverlayMapUpdate &"OverlayMapSnapshot.edit {self.buffer.remoteId}@{self.buffer.version} -> {buffer.remoteId}@{buffer.version} | {patch}, {byteEditAbsolute}"
  logEdit &"  old overlay map: {self}"

  # todo: for now this is called with only one edit as this loop doesn't work for multiple edits at one
  assert patch.edits.len == 1
  for i, editAbsolute in patch.edits:
    # The old range in edits in a patch is a in the space of the old version of the buffer.
    # For this algorithm we want the old range to take into account previous edits (as if the previous edits
    # had already been applied, which the new range does)
    let e = initEdit(
      old = editAbsolute.new.a...(editAbsolute.new.a + (editAbsolute.old.b - editAbsolute.old.a).toPoint),
      new = editAbsolute.new,
    )

    let insert = e.new.b > e.new.a
    delete = e.old.b > e.old.a

    # let byteEditAbsolute = bytePatch.edits[i]
    let byteEdit = initEdit(
      old = byteEditAbsolute.new.a...(byteEditAbsolute.new.a + (byteEditAbsolute.old.b - byteEditAbsolute.old.a)),
      new = byteEditAbsolute.new,
    )

    newMap.append c.slice(e.old.a.OverlayMapChunkSrc, Bias.Left, ())
    logEdit &"overlay edit: {initEdit(old.toOverlayRange(editAbsolute.old), old.toOverlayRange(editAbsolute.new))}"
    logEdit &"rope edit: {initEdit(e.old.a.OverlayPoint...e.old.b.OverlayPoint, e.new.a.OverlayPoint...e.new.b.OverlayPoint)}"

    if c.item.isNone:
      logEdit &"Reached end 1"
      continue

    # Skip over left aligned overlays at the current position
    while true:
      let nextItem = c.nextItem()
      let nextItemEmpty = nextItem.mapIt(it.kind == Empty).get(false)
      let beforeEnd = c.endPos.src < self.map.summary.src or nextItemEmpty
      let editAtEndOfChunk = e.old.a == c.endPos.src
      let currentNonEmptyOrNextNonEmptyLeftBiased = (c.item.get[].kind != Empty) or (nextItem.getSome(item) and item[].kind != Empty and item[].bias == Bias.Left)
      if beforeEnd and editAtEndOfChunk and currentNonEmptyOrNextNonEmptyLeftBiased:
        logEdit &"Overlay biased left, at border {e}, {c.endPos}"
        logEdit &"-> chunk {c.item.get[]}"
        newMap.add c.item.get[]
        c.next()
      else:
        break

    if c.item.isNone:
      logEdit &"Reached end 2"
      continue

    var overlayEdit = initEdit(old.toOverlayRange(editAbsolute.old), old.toOverlayRange(editAbsolute.new))
    logEdit &"initial overlay edit: {overlayEdit}"
    overlayEdit.new.b = overlayEdit.new.a + (e.new.b - e.new.a).toOverlayPoint
    logEdit &"  -> {overlayEdit}"

    let editClamped = (old: e.old.clamp(c.startPos.src...c.endPos.src), new: e.new.clamp(c.startPos.src...c.endPos.src))
    let byteEditClamped = (old: byteEdit.old.clamp(c.startPos.srcBytes...c.endPos.srcBytes), new: byteEdit.new.clamp(c.startPos.srcBytes...c.endPos.srcBytes))
    let editClampedRel = (
      old: (editClamped.old.a - c.startPos.src).toPoint...(editClamped.old.b - c.startPos.src).toPoint,
      new: (editClamped.new.a - c.startPos.src).toPoint...(editClamped.new.b - c.startPos.src).toPoint)
    let editRel = (
      old: (e.old.a - c.startPos.src).toPoint...(e.old.b - c.startPos.src).toPoint,
      new: (e.new.a - c.startPos.src).toPoint...(e.new.b - c.startPos.src).toPoint)

    logEdit &"  clamped: {editClamped}, {byteEditClamped}, rel: {editClampedRel}"
    logEdit &"  rel: {editRel}"

    var chunk = c.item.get[]
    logEdit &"  current chunk: {chunk}"
    logEdit &"  current range: {c.startPos}...{c.endPos}"

    if delete:
      logEdit &"delete {e}, {chunk}, {c.startPos}...{c.endPos}"
      if chunk.kind == Empty:
        chunk.src += editClampedRel.old.a - editClampedRel.old.b
        chunk.srcBytes += byteEditClamped.old.a - byteEditClamped.old.b
        chunk.dst += editClampedRel.old.a - editClampedRel.old.b
        chunk.dstBytes += byteEditClamped.old.a - byteEditClamped.old.b
        logEdit &"  -> {chunk}"

      elif chunk.kind == OverlayMapChunkKind.String:
        chunk.src += editClampedRel.old.a - editClampedRel.old.b
        chunk.srcBytes += byteEditClamped.old.a - byteEditClamped.old.b
        logEdit &"  -> {chunk}"

        let diff = editClampedRel.old.b - editClampedRel.old.a
        logEdit &"delete inside overlay, overlayEdit: {overlayEdit}, diff: {diff} ->"
        overlayEdit.old.a += diff
        overlayEdit.new.a = c.endPos.dst
        overlayEdit.new.b = c.endPos.dst
        logEdit &"  -> {overlayEdit}"

      else:
        echo &"+++++++++++++++++++++++++++++++++++++ todo: delete {chunk.kind}"

    if insert:
      logEdit &"insert {e}, {chunk}, {c.startPos}...{c.endPos}"
      if chunk.kind == Empty:
        chunk.src += (editRel.new.b - editRel.new.a)
        chunk.srcBytes += byteEdit.new.b - byteEdit.new.a
        chunk.dst += (editRel.new.b - editRel.new.a)
        chunk.dstBytes += byteEdit.new.b - byteEdit.new.a
        logEdit &"  -> {chunk}"

      elif chunk.kind == OverlayMapChunkKind.String:
        chunk.src += (editRel.new.b - editRel.new.a)
        chunk.srcBytes += byteEdit.new.b - byteEdit.new.a
        logEdit &"  -> {chunk}"

        let diff = editClampedRel.new.b - editClampedRel.new.a
        logEdit &"insert inside overlay, overlayEdit: {overlayEdit}, diff: {diff} ->"
        # todo: This seems to work for now, but old.a should not be directly compared to c.endPos.dst because old.a doesn't take into account previous edits, while c.endPos.dst does.
        # Probably need more test cases for this. Compare with how it's done when deleting (see above)
        overlayEdit.old.a = min(c.endPos.dst, overlayEdit.old.b)
        overlayEdit.new.a = c.endPos.dst
        overlayEdit.new.b = c.endPos.dst
        logEdit &"  -> {overlayEdit}"

      else:
        echo &"+++++++++++++++++++++++++++++++++++++ todo: insert {chunk.kind}"

    # if we delete past the end of the current chunk, we need to delete everything in between and part of the last chunk
    if delete and e.old.b > c.endPos.src:
      logEdit &"seek forward {e.old.b} > {c.endPos.src}"
      logEdit &"-> chunk {chunk}"
      if chunk.src == inputPoint() and chunk.dst == overlayPoint() and chunk.srcBytes == 0 and chunk.dstBytes == 0 and not (newMap.summary.srcBytes == buffer.visibleText.summary.bytes):
        discard
      else:
        newMap.add chunk

      discard c.seekForward(e.old.b.OverlayMapChunkSrc, Bias.Right, ())
      if c.item.getSome(it):
        chunk = it[]
        logEdit &"delete to {chunk}, {c.startPos}...{c.endPos}"

        let editClamped = (old: e.old.clamp(c.startPos.src...c.endPos.src), new: e.new.clamp(c.startPos.src...c.endPos.src))
        let byteEditClamped = (old: byteEdit.old.clamp(c.startPos.srcBytes...c.endPos.srcBytes), new: byteEdit.new.clamp(c.startPos.srcBytes...c.endPos.srcBytes))
        let editClampedRel = (
          old: (editClamped.old.a - c.startPos.src).toPoint...(editClamped.old.b - c.startPos.src).toPoint,
          new: (editClamped.new.a - c.startPos.src).toPoint...(editClamped.new.b - c.startPos.src).toPoint)

        if chunk.kind == Empty:
          chunk.src += editClampedRel.old.a - editClampedRel.old.b
          chunk.srcBytes += byteEditClamped.old.a - byteEditClamped.old.b
          chunk.dst += editClampedRel.old.a - editClampedRel.old.b
          chunk.dstBytes += byteEditClamped.old.a - byteEditClamped.old.b
          logEdit &"  -> {chunk}"

        elif chunk.kind == OverlayMapChunkKind.String:
          chunk.src += editClampedRel.old.a - editClampedRel.old.b
          chunk.srcBytes += byteEditClamped.old.a - byteEditClamped.old.b
          logEdit &"  -> {chunk}"

          let diff = editClampedRel.old.a - editClampedRel.old.b
          logEdit &"delete2 inside overlay, diff: {diff}, overlayEdit: {overlayEdit} ->"
          overlayEdit.old.b = overlayEdit.old.b + diff
          logEdit &"  -> {overlayEdit}"

        else:
          echo &"+++++++++++++++++++++++++++++++++++++ todo: delete to {chunk.kind}"

      else:
        if overlayEdit.old.b > overlayEdit.old.a or overlayEdit.new.b > overlayEdit.new.a:
          result.edits.add overlayEdit
        continue

    if overlayEdit.old.b > overlayEdit.old.a or overlayEdit.new.b > overlayEdit.new.a:
      result.edits.add overlayEdit

    logEdit &"-> chunk {chunk}"
    if chunk.src == inputPoint() and chunk.dst == overlayPoint() and chunk.srcBytes == 0 and chunk.dstBytes == 0 and not (newMap.summary.srcBytes == buffer.visibleText.summary.bytes):
      discard
    else:
      newMap.add chunk

    c.next()

  newMap.append c.suffix()
  logEdit &"  patch: {result}"

  if newMap.isEmpty:
    logEdit &"Empty map, add default"
    let endOffset = buffer.visibleText.summary.bytes
    let endPoint = buffer.visibleText.summary.lines
    let chunk = OverlayMapChunk(src: endPoint, dst: endPoint.OverlayPoint, srcBytes: endOffset, dstBytes: endOffset)
    logEdit &"-> chunk {chunk}"
    newMap.add chunk

  self = OverlayMapSnapshot(
    map: newMap,
    buffer: buffer.clone(),
    version: version,
  )
  logEdit &"  overlay map: {self}"

proc edit*(self: var OverlayMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]): Patch[OverlayPoint] =
  if self.buffer.remoteId == buffer.remoteId and self.buffer.version == buffer.version:
    return

  let version = self.version + 1
  let old = self.clone()

  let bytePatch = patch.convert(int, self.buffer.visibleText, buffer.visibleText)
  var p = Patch[Point]()
  p.edits.setLen(1)
  for i, edit in patch.edits:
    p.edits[0] = edit
    # todo: composed correctly?
    result.edits.add self.editImpl(buffer.clone(), p, bytePatch.edits[i], version, old).edits

  self.validate()

proc edit*(self: OverlayMap, buffer: sink BufferSnapshot, patch: Patch[Point]): Patch[OverlayPoint] =
  self.snapshot.edit(buffer, patch)

proc update*(self: var OverlayMapSnapshot, buffer: sink BufferSnapshot) =
  logOverlayMapUpdate &"OverlayMapSnapshot.updateBuffer {self.desc} -> {buffer.remoteId}@{buffer.version}"

proc update*(self: OverlayMap, buffer: sink BufferSnapshot, force: bool = false) =
  logOverlayMapUpdate &"OverlayMap.updateBuffer {self.snapshot.desc} -> {buffer.remoteId}@{buffer.version}, force = {force}"
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

proc clear*(self: var OverlayMapSnapshot, id: int = -1): Patch[OverlayPoint] =
  logOverlayMapUpdate &"OverlayMap.clear {id}, {self.desc}"
  var newMap = SumTree[OverlayMapChunk].new()
  var patch: Patch[OverlayPoint]

  if id == -1:
    let endPoint = self.buffer.visibleText.summary.lines
    let endOffset = self.buffer.visibleText.summary.bytes
    newMap.add OverlayMapChunk(src: endPoint, dst: endPoint.OverlayPoint, srcBytes: endOffset, dstBytes: endOffset)

    var c = self.map.initCursor(OverlayMapChunkSummary)
    c.next()
    while c.item.getSome(item):
      if item.kind != OverlayMapChunkKind.Empty:
        patch.add initEdit(c.startPos.dst...c.endPos.dst, c.startPos.src.OverlayPoint...c.endPos.src.OverlayPoint)
      c.next()

  else:
    var c = self.map.initCursor(OverlayMapChunkSummary)
    let totalCount = if id < self.map.summary.idCounts.len:
      self.map.summary.idCounts[id].int
    else:
      0

    var lastEmpty = false
    for i in 0..<totalCount:
      let s = c.slice(i.OverlayMapChunkIdCount, Bias.Right, id)
      if not s.isEmpty:
        newMap.append s
        lastEmpty = false

      if c.item.getSome(item):
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

      else:
        debugEcho &"  aaaaaaaaaa {c.startPos}...{c.endPos}"

    newMap.append c.suffix()

  self = OverlayMapSnapshot(
    map: newMap,
    buffer: self.buffer.clone(),
    version: self.version + 1,
  )

  return patch

proc clear*(self: OverlayMap, id: int = -1) =
  let old = self.snapshot.clone()
  let patch = self.snapshot.clear(id)
  self.onUpdated.invoke (self, old, patch)

proc addOverlay*(self: OverlayMap, range: Range[Point], text: string, id: int, scope: string = "", bias: Bias = Bias.Left) =
  logOverlayMapUpdate &"OverlayMap.add {range}, '{text}', {id}, '{scope}', bias, {self.snapshot.desc}"

  template log(msg: untyped) =
    when false:
      debugEcho msg


  log &"OverlayMap.addOverlay {range}, '{text}'\n{self.snapshot}"
  let newSummary = TextSummary.init(text)
  var newMap = SumTree[OverlayMapChunk].new()

  var patch: Patch[OverlayPoint]

  let byteRange = self.snapshot.buffer.visibleText.pointToOffset(range.a)...self.snapshot.buffer.visibleText.pointToOffset(range.b)

  var c = self.snapshot.map.initCursor(OverlayMapChunkSummary)
  newMap.append c.slice(range.a.OverlayMapChunkSrc, Bias.Left)
  # Skip over left aligned overlays at the current position
  while c.endPos.src < self.snapshot.map.summary.src and range.a == c.endPos.src and (
    (c.item.get[].kind != Empty and c.item.get[].bias == Bias.Left) or (c.nextItem().getSome(item) and item[].kind != Empty and item[].bias == Bias.Left)):
    log &"Overlay biased left, at border {range}, {c.endPos}"
    log &"-> chunk {c.item.get[]}"
    newMap.add c.item.get[]
    c.next()

  let currentEmpty = c.startPos.src == c.endPos.src

  log &"  current: {newMap.summary}, current: {c.startPos}...{c.endPos}"
  if range.a > c.startPos.src or (currentEmpty and bias == Bias.Right):
    if c.item.getSome(item):
      if item.kind == OverlayMapChunkKind.String:
        discard # todo
      else:
        let newRange = (range.a - c.startPos.src).toPoint
        let newByteRange = byteRange.a - c.startPos.srcBytes
        log &"  add start of overlappin chunk {newRange}"
        newMap.add OverlayMapChunk(src: newRange, dst: newRange.OverlayPoint, srcBytes: newByteRange, dstBytes: newByteRange)

  newMap.add OverlayMapChunk(id: id, src: range.len, dst: newSummary.lines.OverlayPoint, srcBytes: byteRange.len, dstBytes: newSummary.bytes, kind: OverlayMapChunkKind.String, text: text, scope: scope, bias: bias)

  let overlayRangeOld = self.toOverlayPoint(range.a)...self.toOverlayPoint(range.b)
  let overlayRangeNew = overlayRangeOld.a...(overlayRangeOld.a + newSummary.lines.OverlayPoint)
  patch.add initEdit(overlayRangeOld, overlayRangeNew)

  if range.b < c.endPos.src or (currentEmpty and bias == Bias.Left):
    if c.item.getSome(item):
      if item.kind == OverlayMapChunkKind.String:
        discard # todo
      else:
        let newRange = (c.endPos.src - range.b).toPoint
        let newByteRange = c.endPos.srcBytes - byteRange.b
        log &"  add end of overlappin chunk {newRange}"
        newMap.add OverlayMapChunk(src: newRange, dst: newRange.OverlayPoint, srcBytes: newByteRange, dstBytes: newByteRange)

  c.next()
  newMap.append c.suffix()
  let newSnapshot = OverlayMapSnapshot(
    map: newMap,
    buffer: self.snapshot.buffer.clone(),
    version: self.snapshot.version + 1,
  )
  # log newSnapshot
  let old = self.snapshot.clone()
  self.snapshot = newSnapshot
  self.onUpdated.invoke (self, old, patch)

let mainThreadId = ({.cast(noSideEffect).}: getThreadId())

template log(msg: untyped) =
  when false:
    # let mainThreadId = ({.cast(noSideEffect).}: ({.gcsafe.}: mainThreadId))
    # let threadId = ({.cast(noSideEffect).}: getThreadId())
    # if threadId == mainThreadId:
    if true:
      debugEcho msg

var debugOverlayMapNext* = false
template logIter(msg: untyped) =
  when false:
    if ({.gcsafe.}: debugOverlayMapNext):
      debugEcho msg

proc setupSubIterAfterSeek(self: var OverlayChunkIterator) =
  # Bias to right if at end of non-empty chunk
  logIter &"setupSubIterAfterSeek: {self.overlayPoint} == {self.overlayMapCursor.endPos.dst}"
  if self.overlayMapCursor.endPos.src > self.overlayMapCursor.startPos.src and self.overlayPoint == self.overlayMapCursor.endPos.dst:
    logIter &"at end of {self.overlayMapCursor.startPos} -> {self.overlayMapCursor.endPos}"
    self.overlayMapCursor.next()

  if self.overlayMapCursor.item.getSome(item):
    case item.kind
    of OverlayMapChunkKind.Empty:
      self.subIterKind = OverlayMapChunkKind.Empty
    of OverlayMapChunkKind.String:
      self.subIterKind = OverlayMapChunkKind.String
      # self.stringLine = self.overlayPoint.row.int - self.overlayMapCursor.startPos.dst.row.int
      self.stringLine = 0 # todo
      self.stringOffset = item.text.toOpenArray(0, item.text.high).pointToOffset((self.overlayPoint - self.overlayMapCursor.startPos.dst).toPoint)
      self.stringRuneOffset = item.text.toOpenArray(0, item.text.high).pointToCount((self.overlayPoint - self.overlayMapCursor.startPos.dst).toPoint).int
      logIter &"OverlayChunkIterator.seek {self.overlayPoint} -> {self.stringLine}, {self.stringOffset}"
    of OverlayMapChunkKind.Rope:
      # todo
      self.subIterKind = OverlayMapChunkKind.Rope
      self.stringLine = 0 # todo
      self.stringOffset = 0 # todo
      self.stringRuneOffset = 0 # todo

proc seek*(self: var OverlayChunkIterator, point: Point) =
  logIter &"OverlayChunkIterator.seekPoint1 {self.styledChunks.point} -> {point}"
  self.styledChunks.seek(point)
  discard self.overlayMapCursor.seekForward(point.OverlayMapChunkSrc, Bias.Left, ())
  let overlayPoint = self.overlayMapCursor.toOverlayPoint(point)
  logIter &"OverlayChunkIterator.seekPoint2 {self.overlayPoint} -> {overlayPoint}"
  assert overlayPoint >= self.overlayPoint
  self.overlayPoint = overlayPoint
  self.localOffset = 0
  self.styledChunk = StyledChunk.none
  self.overlayChunk = OverlayChunk.none
  self.setupSubIterAfterSeek()

proc seek*(self: var OverlayChunkIterator, overlayPoint: OverlayPoint) =
  logIter &"OverlayChunkIterator.seek {self.overlayPoint} -> {overlayPoint}"
  # if overlayPoint < self.overlayPoint:
  #   debugEcho
  assert overlayPoint >= self.overlayPoint
  discard self.overlayMapCursor.seekForward(overlayPoint.OverlayMapChunkDst, Bias.Left, ())
  self.overlayPoint = overlayPoint
  let point = self.overlayMapCursor.toPoint(self.overlayPoint)
  self.styledChunks.seek(point)
  self.localOffset = 0
  self.styledChunk = StyledChunk.none
  self.overlayChunk = OverlayChunk.none
  self.setupSubIterAfterSeek()

proc seekLine*(self: var OverlayChunkIterator, line: int) =
  self.seek(overlayPoint(line))

proc next*(self: var OverlayChunkIterator): Option[OverlayChunk] =
  # let mainThreadId = ({.cast(noSideEffect).}: ({.gcsafe.}: mainThreadId))
  # let threadId = ({.cast(noSideEffect).}: getThreadId())
  if self.atEnd:
    self.overlayChunk = OverlayChunk.none
    return

  logIter &"Overlay.next {self.overlayPoint}, {self.styledChunks.point}, {self.subIterKind}, localOffset: {self.localOffset}"
  # defer:
  #   logIter &"  -> {result}"

  if self.subIterKind == OverlayMapChunkKind.Empty:
    if self.styledChunk.isNone or self.localOffset > self.styledChunk.get.len:
      self.styledChunk = self.styledChunks.next()
      self.localOffset = 0

    if self.styledChunk.getSome(currentChunk):
      let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)
      if not self.overlayMapCursor.didSeek() or currentPoint > self.overlayMapCursor.endPos.src:
        discard self.overlayMapCursor.seekForward(currentPoint.OverlayMapChunkSrc, Bias.Left, ())

      if currentPoint == self.overlayMapCursor.endPos.src and self.overlayMapCursor.startPos.src != self.overlayMapCursor.endPos.src:
        self.overlayMapCursor.next()

      logIter &"  OverlayChunkIterator.next1 {self.overlayPoint} -> {self.overlayMapCursor.toOverlayPoint(currentPoint)}"
      self.overlayPoint = self.overlayMapCursor.toOverlayPoint(currentPoint)

    elif self.overlayMapCursor.atEnd:
      self.atEnd = true
      self.overlayChunk = OverlayChunk.none
      return
    else:
      self.overlayMapCursor.next()
      if self.overlayMapCursor.atEnd:
        self.atEnd = true
        self.overlayChunk = OverlayChunk.none
        return

  let mappedPoint = self.overlayMapCursor.toPoint(self.overlayPoint)

  if self.overlayMapCursor.item.getSome(item):
    logIter &" Overlay.next cursor: {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos},   {item[]}"
    case item.kind
    of OverlayMapChunkKind.String:
      let (line, offset, runeOffset) = if self.subIterKind == OverlayMapChunkKind.String:
        (self.stringLine, self.stringOffset, self.stringRuneOffset)
      else:
        (0, 0, 0)

      logIter &"  String overlay: {line}, {offset}, {runeOffset}"

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
      #   logIter &"  {chunkOriginal}"

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
      logIter &"  overlay chunk {overlayChunk}, endOffset: {endOffset}, len: {item.text.len}"

      if endOffset == item.text.len:
        self.subIterKind = OverlayMapChunkKind.Empty
        self.stringLine = 0
        self.stringOffset = 0
        self.stringRuneOffset = 0
        # if self.styledChunk.isNone:
        #   self.atEnd = true

        if self.overlayMapCursor.startPos.src == self.overlayMapCursor.endPos.src:
          logIter &"  next"
          self.overlayMapCursor.next()
        else:
          logIter &"  seek {self.overlayMapCursor.startPos.src} != {self.overlayMapCursor.endPos.src}"
          let deletedRange: InputPoint = self.overlayMapCursor.endPos.src - self.overlayMapCursor.startPos.src
          let insertedRange: InputPoint = self.overlayMapCursor.endPos.dst - self.overlayMapCursor.startPos.dst
          if deletedRange >= insertedRange:
            self.seek(self.overlayMapCursor.endPos.src)
          else:
            self.seek(self.overlayMapCursor.endPos.dst)
          logIter &"  after seek {self.overlayMapCursor.startPos.src} <= {self.overlayMapCursor.endPos.src}, {self.overlayPoint}, {self.overlayMapCursor.endPos.dst}"
          if self.overlayMapCursor.endPos.src > self.overlayMapCursor.startPos.src and self.overlayPoint == self.overlayMapCursor.endPos.dst:
            logIter &"at end of {self.overlayMapCursor.startPos} -> {self.overlayMapCursor.endPos}"
            logIter &"  and next, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}, {self.overlayPoint}"
            self.overlayMapCursor.next()

        if self.overlayMapCursor.item.getSome(item) and item.kind != OverlayMapChunkKind.Empty:
          logIter &"  Next chunk also string {item[]}, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}, {self.overlayPoint}"
          self.subIterKind = item.kind
      else:
        self.subIterKind = OverlayMapChunkKind.String
        logIter &"  OverlayChunkIterator.next2 {self.overlayPoint} -> {self.overlayPoint + overlayPoint(1, 0)}"
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

  let currentChunk = self.styledChunk.get
  let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)
  logIter &"  currentChunk: {currentChunk}, currentPoint: {currentPoint}, {self.overlayMapCursor.startPos.src}, {self.overlayMapCursor.endPos.src}, local offset: {self.localOffset}"
  if self.overlayMapCursor.startPos.src == self.overlayMapCursor.endPos.src:
    if currentPoint < self.overlayMap.map.summary.src:
      # this should not happen
      echo &"ERROR {currentPoint}, {self.overlayMapCursor.startPos}...{self.overlayMapCursor.endPos}, {currentChunk}\n{self.overlayMap}"
      self.overlayMapCursor.next()
      echo &"  OverlayChunkIterator.next3 {self.overlayPoint} -> {self.overlayMapCursor.toOverlayPoint(currentPoint)}"
      self.overlayPoint = self.overlayMapCursor.toOverlayPoint(currentPoint)
      assert false

  let startOffset = self.localOffset
  let map = (
    src: self.overlayMapCursor.startPos.src...self.overlayMapCursor.endPos.src,
    dst: self.overlayMapCursor.startPos.dst...self.overlayMapCursor.endPos.dst)

  if currentChunk.endPoint <= map.src.b:
    logIter &"  current chunk ends before current mapping {currentChunk.endPoint} <= {map.src.b}, map: {map}"
    self.localOffset = currentChunk.len + 1
    var newChunk = currentChunk.split(startOffset).suffix.split(currentChunk.len - startOffset).prefix
    newChunk.chunk.point = mappedPoint
    self.overlayChunk = OverlayChunk(styledChunk: newChunk, overlayPoint: self.overlayPoint).some

  else:
    logIter &"  current mapping ends before current chunk {currentChunk.endPoint} > {map.src.b}, map: {map}"
    self.localOffset = map.src.b.column.int - currentChunk.point.column.int

    var newChunk = currentChunk.split(startOffset).suffix.split(self.localOffset - startOffset).prefix
    newChunk.chunk.point = mappedPoint
    self.overlayChunk = OverlayChunk(styledChunk: newChunk, overlayPoint: self.overlayPoint).some

    if self.localOffset == self.styledChunk.get.len:
      inc self.localOffset

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

proc renderString*(self: OverlayMapSnapshot): string =
  var iter = self.iter()
  iter.seekLine(0)
  var last = overlayPoint()
  var lastChunk = OverlayChunk()
  while iter.next().getSome(chunk):
    if chunk.len > 0 and chunk == lastChunk:
      echo &"!!!!!!!!!!! Detected endless loop in OverlayMapSnapshot.renderString"
      break
    lastChunk = chunk

    while chunk.overlayPoint.row > last.row:
      result.add "\n"
      last += overlayPoint(1, 0)
    for c in chunk.toOpenArray:
      result.add c
