import std/[options, tables, sugar]
import nimsumtree/[rope, buffer, clock]
import misc/[custom_async, custom_unicode, util, event, rope_utils]
import syntax_map, overlay_map, tab_map, wrap_map, diff_map
from scripting_api import Selection
import nimsumtree/sumtree except mapIt

var debugDisplayMap* = false

{.push gcsafe.}
{.push raises: [].}

type
  DisplayPoint* {.borrow: `.`.} = distinct Point

  DisplayChunk* = object
    diffChunk*: DiffChunk
    displayPoint*: DisplayPoint

func displayPoint*(row: Natural = 0, column: Natural = 0): DisplayPoint = Point(row: row.uint32, column: column.uint32).DisplayPoint
func `$`*(a: DisplayPoint): string {.borrow.}
func `<`*(a: DisplayPoint, b: DisplayPoint): bool {.borrow.}
func `<=`*(a: DisplayPoint, b: DisplayPoint): bool {.borrow.}
func `==`*(a: DisplayPoint, b: DisplayPoint): bool {.borrow.}
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

func point*(self: DisplayChunk): Point {.inline.} = self.diffChunk.point
func endPoint*(self: DisplayChunk): Point {.inline.} = self.diffChunk.endPoint
func displayEndPoint*(self: DisplayChunk): DisplayPoint {.inline.} = displayPoint(self.displayPoint.row, self.displayPoint.column + self.diffChunk.len.uint32)
func endDisplayPoint*(self: DisplayChunk): DisplayPoint {.inline.} = displayPoint(self.displayPoint.row, self.displayPoint.column + self.diffChunk.len.uint32)
func len*(self: DisplayChunk): int {.inline.} = self.diffChunk.len
func `$`*(self: DisplayChunk): string {.inline.} = $self.diffChunk
template toOpenArray*(self: DisplayChunk): openArray[char] = self.diffChunk.toOpenArray
template scope*(self: DisplayChunk): string = self.diffChunk.scope

proc split*(self: DisplayChunk, index: int): tuple[prefix: DisplayChunk, suffix: DisplayChunk] =
  let (prefix, suffix) = self.diffChunk.split(index)
  (
    DisplayChunk(diffChunk: prefix, displayPoint: self.displayPoint),
    DisplayChunk(diffChunk: suffix, displayPoint: displayPoint(self.displayPoint.row, self.displayPoint.column + index.uint32)),
  )

type
  DisplayMapSnapshot* = object
    buffer*: BufferSnapshot
    overlay*: OverlayMapSnapshot
    tabMap*: TabMapSnapshot
    wrapMap*: WrapMapSnapshot
    diffMap*: DiffMapSnapshot

  DisplayMap* = ref object
    overlay*: OverlayMap
    tabMap*: TabMap
    wrapMap*: WrapMap
    diffMap*: DiffMap
    onUpdated*: Event[tuple[map: DisplayMap]]

  DisplayChunkIterator* = object
    diffChunks*: DiffChunkIterator
    bufferedChunk: Option[DisplayChunk]
    displayChunk*: Option[DisplayChunk]
    displayPoint*: DisplayPoint
    atEnd*: bool
    indentGuideColumn*: Option[int]
    insideIndent: bool = true
    bar: string = "|"

func clone*(self: DisplayMapSnapshot): DisplayMapSnapshot =
  DisplayMapSnapshot(
    overlay: self.overlay.clone(),
    tabMap: self.tabMap.clone(),
    wrapMap: self.wrapMap.clone(),
    diffMap: self.diffMap.clone(),
  )

proc handleOverlayMapUpdated(self: DisplayMap, overlay: OverlayMap, old: OverlayMapSnapshot, patch: Patch[OverlayPoint])
proc handleTabMapUpdated(self: DisplayMap, tabMap: TabMap, old: TabMapSnapshot, patch: Patch[TabPoint])
proc handleWrapMapUpdated(self: DisplayMap, wrapMap: WrapMap, old: WrapMapSnapshot)
proc handleDiffMapUpdated(self: DisplayMap, diffMap: DiffMap, old: DiffMapSnapshot)

proc new*(_: typedesc[DisplayMap]): DisplayMap =
  result = DisplayMap(
    overlay: OverlayMap.new(),
    tabMap: TabMap.new(),
    wrapMap: WrapMap.new(),
    diffMap: DiffMap.new(),
  )
  let self = result
  discard result.overlay.onUpdated.subscribe (a: (OverlayMap, OverlayMapSnapshot, Patch[OverlayPoint])) => self.handleOverlayMapUpdated(a[0], a[1], a[2])
  discard result.tabMap.onUpdated.subscribe (a: (TabMap, TabMapSnapshot, Patch[TabPoint])) => self.handleTabMapUpdated(a[0], a[1], a[2])
  discard result.wrapMap.onUpdated.subscribe (a: (WrapMap, WrapMapSnapshot)) => self.handleWrapMapUpdated(a[0], a[1])
  discard result.diffMap.onUpdated.subscribe (a: (DiffMap, DiffMapSnapshot)) => self.handleDiffMapUpdated(a[0], a[1])

proc iter*(displayMap: var DisplayMap): DisplayChunkIterator =
  result = DisplayChunkIterator(
    diffChunks: displayMap.diffMap.snapshot.iter(),
  )

func remoteId*(self: DisplayMap): BufferId = self.wrapMap.snapshot.buffer.remoteId
func buffer*(self: DisplayMap): lent BufferSnapshot = self.wrapMap.snapshot.buffer
func point*(self: DisplayChunkIterator): Point = self.diffChunks.point
template styledChunk*(self: DisplayChunk): StyledChunk = self.diffChunk.styledChunk
func styledChunks*(self: var DisplayChunkIterator): var StyledChunkIterator {.inline.} = self.diffChunks.styledChunks
func styledChunks*(self: DisplayChunkIterator): StyledChunkIterator {.inline.} = self.diffChunks.styledChunks

func isNil*(self: DisplayMapSnapshot): bool = self.wrapMap.isNil

proc `$`*(self: DisplayMapSnapshot): string =
  result.add "display map\n"
  result.add ($self.overlay).indent(2)
  result.add ($self.wrapMap).indent(2)
  result.add ($self.diffMap).indent(2)

proc toDisplayPoint*(self: DisplayMapSnapshot, point: Point, bias: Bias = Bias.Right): DisplayPoint =
  let wrapPoint = self.wrapMap.toWrapPoint(point, bias)
  return self.diffMap.toDiffPoint(wrapPoint, bias).DisplayPoint

proc toDisplayPoint*(self: DisplayMap, point: Point, bias: Bias = Bias.Right): DisplayPoint =
  let wrapPoint = self.wrapMap.snapshot.toWrapPoint(point, bias)
  return self.diffMap.snapshot.toDiffPoint(wrapPoint, bias).DisplayPoint

proc toWrapPoint*(self: DisplayMap, point: Point, bias: Bias = Bias.Right): WrapPoint =
  self.wrapMap.snapshot.toWrapPoint(point, bias)

proc toPoint*(self: DisplayMapSnapshot, point: DisplayPoint, bias: Bias = Bias.Right): Point =
  let wrapPoint = self.diffMap.toWrapPoint(point.DiffPoint, bias)
  let tabPoint = self.wrapMap.toTabPoint(wrapPoint, bias)
  let overlayPoint = self.tabMap.toOverlayPoint(tabPoint, bias)
  result = self.overlay.toPoint(overlayPoint, bias)

proc toPoint*(self: DisplayMap, point: DisplayPoint, bias: Bias = Bias.Right): Point =
  let wrapPoint = self.diffMap.snapshot.toWrapPoint(point.DiffPoint, bias)
  let tabPoint = self.wrapMap.snapshot.toTabPoint(wrapPoint, bias)
  let overlayPoint = self.tabMap.toOverlayPoint(tabPoint, bias)
  result = self.overlay.toPoint(overlayPoint, bias)

proc toPoint*(self: DisplayMap, point: WrapPoint, bias: Bias = Bias.Right): Point =
  let tabPoint = self.wrapMap.toTabPoint(point, bias)
  let overlayPoint = self.tabMap.toOverlayPoint(tabPoint, bias)
  result = self.overlay.toPoint(overlayPoint, bias)

func endDisplayPoint*(self: DisplayMapSnapshot): DisplayPoint {.inline.} = self.diffMap.endDiffPoint.DisplayPoint
func endDisplayPoint*(self: DisplayMap): DisplayPoint {.inline.} = self.diffMap.endDiffPoint.DisplayPoint

proc handleOverlayMapUpdated(self: DisplayMap, overlay: OverlayMap, old: OverlayMapSnapshot, patch: Patch[OverlayPoint]) =
  assert overlay == self.overlay
  if self.overlay.snapshot.buffer.remoteId != old.buffer.remoteId:
    assert false
    return

  logMapUpdate &"DisplayMap.handleOverlayMapUpdated, {patch}\n {self.overlay.snapshot}"
  let tabPatch = self.tabMap.edit(overlay.snapshot.clone(), patch)
  let wrapPatch = self.wrapMap.edit(self.tabMap.snapshot.clone(), tabPatch)
  self.diffMap.edit(self.wrapMap.snapshot.clone(), wrapPatch)
  self.tabMap.update(self.overlay.snapshot.clone(), force = true)
  self.wrapMap.update(self.tabMap.snapshot.clone(), force = true)
  self.diffMap.update(self.wrapMap.snapshot.clone(), force = true)
  self.onUpdated.invoke (self,)

proc handleTabMapUpdated(self: DisplayMap, tabMap: TabMap, old: TabMapSnapshot, patch: Patch[TabPoint]) =
  assert tabMap == self.tabMap
  if self.tabMap.snapshot.buffer.remoteId != old.buffer.remoteId:
    assert false
    return

  logMapUpdate &"DisplayMap.handleTabMapUpdated, {patch}\n {self.tabMap.snapshot}"
  let wrapPatch = self.wrapMap.edit(tabMap.snapshot.clone(), patch)
  self.diffMap.edit(self.wrapMap.snapshot.clone(), wrapPatch)
  self.tabMap.update(self.overlay.snapshot.clone(), force = true)
  self.wrapMap.update(self.tabMap.snapshot.clone(), force = true)
  self.diffMap.update(self.wrapMap.snapshot.clone(), force = true)
  self.onUpdated.invoke (self,)

proc handleWrapMapUpdated(self: DisplayMap, wrapMap: WrapMap, old: WrapMapSnapshot) =
  assert wrapMap == self.wrapMap
  if self.wrapMap.snapshot.buffer.remoteId != old.buffer.remoteId:
    assert false
    return

  logMapUpdate &"DisplayMap.handleWrapMapUpdated {wrapMap.snapshot.desc}"
  self.diffMap.update(self.wrapMap.snapshot.clone())
  self.onUpdated.invoke (self,)

proc handleDiffMapUpdated(self: DisplayMap, diffMap: DiffMap, old: DiffMapSnapshot) =
  assert diffMap == self.diffMap

  logMapUpdate &"DisplayMap.handleDiffMapUpdated {self.diffMap.snapshot}"
  self.onUpdated.invoke (self,)

proc setBuffer*(self: DisplayMap, buffer: sink BufferSnapshot) =
  logMapUpdate &"DisplayMap.setBuffer {self.remoteId}@{self.wrapMap.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}"
  self.overlay.setBuffer(buffer)
  self.tabMap.setInput(self.overlay.snapshot.clone())
  self.wrapMap.setInput(self.tabMap.snapshot.clone())
  self.diffMap.setInput(self.wrapMap.snapshot.clone())

proc validate*(self: DisplayMapSnapshot) =
  self.overlay.validate()
  self.tabMap.validate()
  self.wrapMap.validate()
  self.diffMap.validate()

proc edit*(self: var DisplayMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]) =
  let overlayPatch = self.overlay.edit(buffer.clone(), patch)
  let tabPatch = self.tabMap.edit(self.overlay.clone(), overlayPatch)
  let wrapPatch = self.wrapMap.edit(self.tabMap.clone(), tabPatch)
  self.diffMap.edit(self.wrapMap.clone(), wrapPatch)

proc edit*(self: DisplayMap, buffer: sink BufferSnapshot, edits: openArray[tuple[old, new: Selection]]) =
  var patch = Patch[Point]()
  for e in edits:
    patch.add initEdit(e.old.first.toPoint...e.old.last.toPoint, e.new.first.toPoint...e.new.last.toPoint)

  let overlayPatch = self.overlay.edit(buffer.clone(), patch)
  let tabPatch = self.tabMap.edit(self.overlay.snapshot.clone(), overlayPatch)
  let wrapPatch = self.wrapMap.edit(self.tabMap.snapshot.clone(), tabPatch)
  self.diffMap.edit(self.wrapMap.snapshot.clone(), wrapPatch)

proc update*(self: DisplayMap, wrapWidth: int, force: bool = false) =
  self.wrapMap.update(wrapWidth, force)

proc setTabWidth*(self: DisplayMap, tabWidth: int, force: bool = false) =
  if tabWidth == self.tabMap.snapshot.tabWidth:
    return
  self.tabMap.setTabWidth(tabWidth)
  self.wrapMap.clear()
  self.diffMap.clear()
  self.onUpdated.invoke (self,)

proc seek*(self: var DisplayChunkIterator, displayPoint: DisplayPoint) =
  self.diffChunks.seek(displayPoint.DiffPoint)
  self.displayChunk = DisplayChunk.none
  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint

proc seek*(self: var DisplayChunkIterator, point: Point) =
  self.diffChunks.seek(point)
  self.displayChunk = DisplayChunk.none
  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint
  self.bufferedChunk = DisplayChunk.none
  self.insideIndent = true

proc seekLine*(self: var DisplayChunkIterator, line: int) =
  self.diffChunks.seekLine(line)
  self.displayChunk = DisplayChunk.none
  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint
  self.bufferedChunk = DisplayChunk.none
  self.insideIndent = true

proc next*(self: var DisplayChunkIterator): Option[DisplayChunk] =
  if self.atEnd:
    self.displayChunk = DisplayChunk.none
    return

  let oldDisplayChunk = self.displayChunk
  self.displayChunk = if self.bufferedChunk.isSome:
    self.bufferedChunk.take().some
  else:
    self.diffChunks.next().mapIt(DisplayChunk(diffChunk: it, displayPoint: it.diffPoint.DisplayPoint))

  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint

  if self.indentGuideColumn.isSome and self.displayChunk.isSome and oldDisplayChunk.isSome and oldDisplayChunk.get.point.row < self.displayChunk.get.point.row:
      self.insideIndent = true

  if self.insideIndent and self.indentGuideColumn.getSome(indentGuideColumn) and self.displayChunk.getSome(chunk) and not chunk.diffChunk.wrapChunk.tabChunk.wasTab:
    var maxEnd = 0
    while maxEnd < chunk.len:
      if chunk.toOpenArray()[maxEnd] notin Whitespace:
        break
      inc maxEnd

    if chunk.endPoint.column.int <= indentGuideColumn:
      if maxEnd < chunk.len:
        self.insideIndent = false
      self.atEnd = self.diffChunks.atEnd
      return self.displayChunk
    elif chunk.point.column.int > indentGuideColumn:
      self.atEnd = self.diffChunks.atEnd
      self.insideIndent = false
      return self.displayChunk
    elif indentGuideColumn >= chunk.point.column.int + maxEnd:
      # after first non whitespace
      self.atEnd = self.diffChunks.atEnd
      self.insideIndent = false
      return self.displayChunk
    elif chunk.point.column.int == indentGuideColumn:
      let suffix = chunk.split(1).suffix
      if suffix.len > 0:
        self.bufferedChunk = suffix.some
      self.displayChunk.get.styledChunk.chunk.len = 1
      self.displayChunk.get.styledChunk.chunk.data = cast[ptr UncheckedArray[char]](self.bar[0].addr)
      self.displayChunk.get.styledChunk.scope = "comment"
      return self.displayChunk
    else:
      let (prefix, suffix) = chunk.split(indentGuideColumn - chunk.point.column.int)
      if suffix.len > 0:
        self.bufferedChunk = suffix.some
      self.displayChunk = prefix.some
      return self.displayChunk

  self.atEnd = self.diffChunks.atEnd
  return self.displayChunk

template outputPoint*(self: DisplayChunk): DisplayPoint = self.displayPoint
template endOutputPoint*(self: DisplayChunk): DisplayPoint = self.endDisplayPoint
template endOutputPoint*(self: DisplayMapSnapshot): DisplayPoint = self.endDisplayPoint
