import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm, sugar]
import nimsumtree/[rope, buffer, clock]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import overlay_map, wrap_map, diff_map
from scripting_api import Selection
import nimsumtree/sumtree except mapIt

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

var debugDisplayMap* = false

template log(msg: untyped) =
  when false:
    if debugDisplayMap:
      echo msg

{.push gcsafe.}
{.push raises: [].}

type
  DisplayChunk* = object
    diffChunk*: DiffChunk
    displayPoint*: DisplayPoint

func point*(self: DisplayChunk): Point = self.diffChunk.point
func endPoint*(self: DisplayChunk): Point = self.diffChunk.endPoint
func displayEndPoint*(self: DisplayChunk): DisplayPoint = displayPoint(self.displayPoint.row, self.displayPoint.column + self.diffChunk.len.uint32)
func endDisplayPoint*(self: DisplayChunk): DisplayPoint = displayPoint(self.displayPoint.row, self.displayPoint.column + self.diffChunk.len.uint32)
func len*(self: DisplayChunk): int = self.diffChunk.len
func `$`*(self: DisplayChunk): string = $self.diffChunk
template toOpenArray*(self: DisplayChunk): openArray[char] = self.diffChunk.toOpenArray
template scope*(self: DisplayChunk): string = self.diffChunk.scope

type
  DisplayMapSnapshot* = object
    buffer*: BufferSnapshot
    overlay*: OverlayMapSnapshot
    wrapMap*: WrapMapSnapshot
    diffMap*: DiffMapSnapshot

  DisplayMap* = ref object
    overlay*: OverlayMap
    wrapMap*: WrapMap
    diffMap*: DiffMap
    onUpdated*: Event[tuple[map: DisplayMap]]

  DisplayChunkIterator* = object
    diffChunks*: DiffChunkIterator
    displayChunk*: Option[DisplayChunk]
    displayPoint*: DisplayPoint
    atEnd*: bool

func clone*(self: DisplayMapSnapshot): DisplayMapSnapshot =
  DisplayMapSnapshot(
    overlay: self.overlay.clone(),
    wrapMap: self.wrapMap.clone(),
    diffMap: self.diffMap.clone(),
  )

proc handleOverlayMapUpdated(self: DisplayMap, overlay: OverlayMap, old: OverlayMapSnapshot, patch: Patch[OverlayPoint])
proc handleWrapMapUpdated(self: DisplayMap, wrapMap: WrapMap, old: WrapMapSnapshot)
proc handleDiffMapUpdated(self: DisplayMap, diffMap: DiffMap, old: DiffMapSnapshot)

proc new*(_: typedesc[DisplayMap]): DisplayMap =
  result = DisplayMap(
    overlay: OverlayMap.new(),
    wrapMap: WrapMap.new(),
    diffMap: DiffMap.new(),
  )
  let self = result
  discard result.overlay.onUpdated.subscribe (a: (OverlayMap, OverlayMapSnapshot, Patch[OverlayPoint])) => self.handleOverlayMapUpdated(a[0], a[1], a[2])
  discard result.wrapMap.onUpdated.subscribe (a: (WrapMap, WrapMapSnapshot)) => self.handleWrapMapUpdated(a[0], a[1])
  discard result.diffMap.onUpdated.subscribe (a: (DiffMap, DiffMapSnapshot)) => self.handleDiffMapUpdated(a[0], a[1])

proc iter*(displayMap: var DisplayMap): DisplayChunkIterator =
  result = DisplayChunkIterator(
    diffChunks: displayMap.diffMap.snapshot.iter(),
  )

func remoteId*(self: DisplayMap): BufferId = self.wrapMap.snapshot.buffer.remoteId
func point*(self: DisplayChunkIterator): Point = self.diffChunks.point
func styledChunk*(self: DisplayChunk): StyledChunk {.inline.} = self.diffChunk.styledChunk
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
  let overlayPoint = self.wrapMap.toOverlayPoint(wrapPoint, bias)
  result = self.overlay.toPoint(overlayPoint, bias)

proc toPoint*(self: DisplayMap, point: DisplayPoint, bias: Bias = Bias.Right): Point =
  let wrapPoint = self.diffMap.snapshot.toWrapPoint(point.DiffPoint, bias)
  let overlayPoint = self.wrapMap.snapshot.toOverlayPoint(wrapPoint, bias)
  result = self.overlay.toPoint(overlayPoint, bias)

proc toPoint*(self: DisplayMap, point: WrapPoint, bias: Bias = Bias.Right): Point =
  let overlayPoint = self.wrapMap.toOverlayPoint(point, bias)
  result = self.overlay.toPoint(overlayPoint, bias)

proc handleOverlayMapUpdated(self: DisplayMap, overlay: OverlayMap, old: OverlayMapSnapshot, patch: Patch[OverlayPoint]) =
  assert overlay == self.overlay
  if self.overlay.snapshot.buffer.remoteId != old.buffer.remoteId:
    assert false
    return

  logMapUpdate &"DisplayMap.handleOverlayMapUpdated, {patch}\n {self.overlay.snapshot}"
  let wrapPatch = self.wrapMap.edit(overlay.snapshot.clone(), patch)
  self.diffMap.edit(self.wrapMap.snapshot.clone(), wrapPatch)
  self.wrapMap.update(self.overlay.snapshot.clone(), force = true)
  self.diffMap.update(self.wrapMap.snapshot.clone(), force = true)
  self.onUpdated.invoke (self,)

proc handleWrapMapUpdated(self: DisplayMap, wrapMap: WrapMap, old: WrapMapSnapshot) =
  assert wrapMap == self.wrapMap
  if self.wrapMap.snapshot.buffer.remoteId != old.buffer.remoteId:
    assert false
    return

  logMapUpdate &"DisplayMap.handleWrapMapUpdated {wrapMap.snapshot.buffer.remoteId}@{self.wrapMap.snapshot.buffer.version}, wrap summary: {wrapMap.snapshot.map.summary}"
  self.diffMap.update(self.wrapMap.snapshot.clone())
  self.onUpdated.invoke (self,)

proc handleDiffMapUpdated(self: DisplayMap, diffMap: DiffMap, old: DiffMapSnapshot) =
  assert diffMap == self.diffMap

  logMapUpdate &"DisplayMap.handleDiffMapUpdated {self.remoteId}, {diffMap.snapshot.map.summary}"
  self.onUpdated.invoke (self,)

proc setBuffer*(self: DisplayMap, buffer: sink BufferSnapshot) =
  logMapUpdate &"DisplayMap.setBuffer {self.remoteId}@{self.wrapMap.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}"
  self.overlay.setBuffer(buffer)
  self.wrapMap.setInput(self.overlay.snapshot.clone())
  self.diffMap.setInput(self.wrapMap.snapshot.clone())

proc validate*(self: DisplayMapSnapshot) =
  self.overlay.validate()
  self.wrapMap.validate()
  self.diffMap.validate()

proc edit*(self: var DisplayMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]) =
  let overlayPatch = self.overlay.edit(buffer.clone(), patch)
  let wrapPatch = self.wrapMap.edit(self.overlay.clone(), overlayPatch)
  self.diffMap.edit(self.wrapMap.clone(), wrapPatch)

proc edit*(self: DisplayMap, buffer: sink BufferSnapshot, edits: openArray[tuple[old, new: Selection]]) =
  var patch = Patch[Point]()
  for e in edits:
    patch.add initEdit(e.old.first.toPoint...e.old.last.toPoint, e.new.first.toPoint...e.new.last.toPoint)

  let overlayPatch = self.overlay.edit(buffer.clone(), patch)
  let wrapPatch = self.wrapMap.edit(self.overlay.snapshot.clone(), overlayPatch)
  self.diffMap.edit(self.wrapMap.snapshot.clone(), wrapPatch)

proc update*(self: DisplayMap, wrapWidth: int, force: bool = false) =
  self.wrapMap.update(wrapWidth, force)

proc seek*(self: var DisplayChunkIterator, displayPoint: DisplayPoint) =
  self.diffChunks.seek(displayPoint.DiffPoint)
  self.displayChunk = DisplayChunk.none
  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint

proc seekLine*(self: var DisplayChunkIterator, line: int) =
  self.diffChunks.seekLine(line)
  self.displayChunk = DisplayChunk.none
  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint

proc next*(self: var DisplayChunkIterator): Option[DisplayChunk] =
  if self.atEnd:
    self.displayChunk = DisplayChunk.none
    return

  self.displayChunk = self.diffChunks.next().mapIt(DisplayChunk(diffChunk: it, displayPoint: it.diffPoint.DisplayPoint))
  self.displayPoint = self.diffChunks.diffPoint.DisplayPoint
  self.atEnd = self.diffChunks.atEnd

  return self.displayChunk
