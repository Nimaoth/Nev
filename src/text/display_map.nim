import std/[options, strutils, atomics, strformat, sequtils, tables, algorithm, sugar]
import nimsumtree/[rope, buffer, clock]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import wrap_map, diff_map
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
func len*(self: DisplayChunk): int = self.diffChunk.len
func `$`*(self: DisplayChunk): string = $self.diffChunk
template toOpenArray*(self: DisplayChunk): openArray[char] = self.diffChunk.toOpenArray
template scope*(self: DisplayChunk): string = self.diffChunk.scope

type
  DisplayMapSnapshot* = object
    buffer*: BufferSnapshot
    wrapMap*: WrapMapSnapshot
    diffMap*: DiffMapSnapshot

  DisplayMap* = ref object
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
    wrapMap: self.wrapMap.clone(),
    diffMap: self.diffMap.clone(),
  )

proc handleWrapMapUpdated(self: DisplayMap, wrapMap: WrapMap, old: WrapMapSnapshot)
proc handleDiffMapUpdated(self: DisplayMap, diffMap: DiffMap, old: DiffMapSnapshot)

proc new*(_: typedesc[DisplayMap]): DisplayMap =
  result = DisplayMap(
    wrapMap: WrapMap.new(),
    diffMap: DiffMap.new(),
  )
  let self = result
  discard result.wrapMap.onUpdated.subscribe (a: (WrapMap, WrapMapSnapshot)) => self.handleWrapMapUpdated(a[0], a[1])
  discard result.diffMap.onUpdated.subscribe (a: (DiffMap, DiffMapSnapshot)) => self.handleDiffMapUpdated(a[0], a[1])

proc init*(_: typedesc[DisplayChunkIterator], rope: var RopeSlice[int], displayMap: var DisplayMap): DisplayChunkIterator =
  result = DisplayChunkIterator(
    diffChunks: DiffChunkIterator.init(rope, displayMap.wrapMap, displayMap.diffMap),
  )

func point*(self: DisplayChunkIterator): Point = self.diffChunks.point
func remoteId*(self: DisplayMap): BufferId = self.wrapMap.snapshot.buffer.remoteId

func isNil*(self: DisplayMapSnapshot): bool = self.wrapMap.isNil

proc `$`*(self: DisplayMapSnapshot): string =
  result.add "display map\n"
  result.add ($self.wrapMap).indent(2)
  result.add ($self.diffMap).indent(2)

proc toDisplayPoint*(self: DisplayMapSnapshot, point: Point, bias: Bias = Bias.Right): DisplayPoint =
  let wrapPoint = self.wrapMap.toWrapPoint(point, bias)
  return self.diffMap.toDiffPoint(wrapPoint, bias).DisplayPoint

proc toDisplayPoint*(self: DisplayMap, point: Point, bias: Bias = Bias.Right): DisplayPoint =
  let wrapPoint = self.wrapMap.snapshot.toWrapPoint(point, bias)
  return self.diffMap.snapshot.toDiffPoint(wrapPoint, bias).DisplayPoint

proc toWrapPoint*(self: DisplayMap, point: Point, bias: Bias = Bias.Right): WrapPoint =
  self.wrapMap.toWrapPoint(point, bias)

proc toPoint*(self: DisplayMapSnapshot, point: DisplayPoint, bias: Bias = Bias.Right): Point =
  let wrapPoint = self.diffMap.toWrapPoint(point.DiffPoint, bias)
  return self.wrapMap.toPoint(wrapPoint, bias)

proc toPoint*(self: DisplayMap, point: DisplayPoint, bias: Bias = Bias.Right): Point =
  let wrapPoint = self.diffMap.snapshot.toWrapPoint(point.DiffPoint, bias)
  return self.wrapMap.snapshot.toPoint(wrapPoint, bias)

proc toPoint*(self: DisplayMap, point: WrapPoint, bias: Bias = Bias.Right): Point =
  return self.wrapMap.toPoint(point, bias)

proc handleWrapMapUpdated(self: DisplayMap, wrapMap: WrapMap, old: WrapMapSnapshot) =
  assert wrapMap == self.wrapMap
  if self.wrapMap.snapshot.buffer.remoteId != old.buffer.remoteId:
    assert false
    return

  # echo &"handleWrapMapUpdated {wrapMap.snapshot.buffer.remoteId}, {wrapMap.snapshot.map.summary}"
  self.diffMap.update(self.wrapMap.snapshot.clone())
  self.onUpdated.invoke (self,)

proc handleDiffMapUpdated(self: DisplayMap, diffMap: DiffMap, old: DiffMapSnapshot) =
  assert diffMap == self.diffMap

  # echo &"handleDiffMapUpdated {self.remoteId}, {diffMap.snapshot.map.summary}"
  self.onUpdated.invoke (self,)

proc setBuffer*(self: DisplayMap, buffer: sink BufferSnapshot) =
  # echo &"DisplayMap.setBuffer {self.remoteId}@{self.wrapMap.snapshot.buffer.version} -> {buffer.remoteId}@{buffer.version}"
  self.wrapMap.setBuffer(buffer.clone())
  self.diffMap.setWrapMap(self.wrapMap.snapshot.clone())

proc validate*(self: DisplayMapSnapshot) =
  self.wrapMap.validate()
  self.diffMap.validate()

proc edit*(self: var DisplayMapSnapshot, buffer: sink BufferSnapshot, patch: Patch[Point]) =
  self.wrapMap.edit(buffer, patch)
  self.diffMap.edit(self.wrapMap.clone(), patch)

proc edit*(self: DisplayMap, buffer: sink BufferSnapshot, edits: openArray[tuple[old, new: Selection]]) =
  self.wrapMap.edit(buffer, edits)
  self.diffMap.edit(self.wrapMap.snapshot.clone(), edits)

proc update*(self: DisplayMap, wrapWidth: int, force: bool = false) =
  # echo &"DisplayMap.update {self.remoteId}@{self.wrapMap.snapshot.buffer.version}: {wrapWidth}"
  self.wrapMap.update(wrapWidth, force)

proc update*(self: DisplayMap, buffer: sink BufferSnapshot, force: bool = false) =
  # echo &"DisplayMap.update {self.remoteId}@{self.wrapMap.snapshot.buffer.version}"
  self.wrapMap.update(buffer, force)

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
