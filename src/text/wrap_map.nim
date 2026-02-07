import std/[options, atomics, strformat, tables]
import nimsumtree/[rope, sumtree, buffer, clock]
import misc/[custom_async, custom_unicode, util, timer, event, rope_utils]
import syntax_map, overlay_map, tab_map, theme

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

type InputMapSnapshot = TabMapSnapshot
type InputChunkIterator = TabChunkIterator
type InputChunk = TabChunk
type InputPoint = TabPoint
proc inputPoint(row: Natural = 0, column: Natural = 0): InputPoint {.inline.} = tabPoint(row, column)
proc toInputPoint(d: PointDiff): InputPoint {.inline.} = d.toTabPoint

type WrapPoint* {.borrow: `.`.} = distinct Point
func wrapPoint*(row: Natural = 0, column: Natural = 0): WrapPoint = Point(row: row.uint32, column: column.uint32).WrapPoint
func `$`*(a: WrapPoint): string {.borrow.}
func `<`*(a: WrapPoint, b: WrapPoint): bool {.borrow.}
func `==`*(a: WrapPoint, b: WrapPoint): bool {.borrow.}
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
    src*: InputPoint
    dst*: WrapPoint

  WrapMapChunkSummary* = object
    src*: InputPoint
    dst*: WrapPoint

  WrapMapChunkSrc* = distinct InputPoint
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
func cmp*[C](a: WrapMapChunkSrc, b: WrapMapChunkSummary, cx: C): int = cmp(a.InputPoint, b.src)

type
  WrapChunk* = object
    inputChunk*: InputChunk
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
    input*: InputMapSnapshot
    interpolated*: bool = true
    wrappedIndent*: int = 4
    version*: int
    wrapAtTabs*: bool = false

  WrapMap* = ref object
    snapshot*: WrapMapSnapshot
    wrapWidth*: int
    wrappedIndent*: int = 4
    pendingEdits: seq[tuple[input: InputMapSnapshot, patch: Patch[InputPoint]]]
    updatingAsync: bool
    onUpdated*: Event[tuple[map: WrapMap, old: WrapMapSnapshot]]

  WrapChunkIterator* = object
    inputChunks*: InputChunkIterator
    inputChunk: Option[InputChunk]
    wrapChunk*: Option[WrapChunk]
    wrapMap* {.cursor.}: WrapMapSnapshot
    wrapMapCursor: WrapMapChunkCursor
    wrapPoint*: WrapPoint
    localOffset: int
    atEnd*: bool
    callCount: int

func buffer*(self: WrapMapSnapshot): lent BufferSnapshot = self.input.buffer

func clone*(self: WrapMapSnapshot): WrapMapSnapshot =
  WrapMapSnapshot(map: self.map.clone(), input: self.input.clone(), interpolated: self.interpolated, version: self.version)

proc new*(_: typedesc[WrapMap]): WrapMap =
  result = WrapMap(snapshot: WrapMapSnapshot(map: SumTree[WrapMapChunk].new([WrapMapChunk()])))

proc iter*(wrapMap: var WrapMapSnapshot, highlighter: Option[Highlighter] = Highlighter.none, theme: Theme = nil): WrapChunkIterator =
  result = WrapChunkIterator(
    inputChunks: wrapMap.input.iter(highlighter, theme),
    wrapMap: wrapMap.clone(),
    wrapMapCursor: wrapMap.map.initCursor(WrapMapChunkSummary),
  )

func point*(self: WrapChunkIterator): Point {.inline.} = self.inputChunks.point
template styledChunk*(self: WrapChunk): StyledChunk = self.inputChunk.styledChunk
func styledChunks*(self: var WrapChunkIterator): var StyledChunkIterator {.inline.} = self.inputChunks.styledChunks
func styledChunks*(self: WrapChunkIterator): StyledChunkIterator {.inline.} = self.inputChunks.styledChunks
func point*(self: WrapChunk): Point = self.inputChunk.point
func endPoint*(self: WrapChunk): Point = self.inputChunk.endPoint
func wrapEndPoint*(self: WrapChunk): WrapPoint = wrapPoint(self.wrapPoint.row, self.wrapPoint.column + self.inputChunk.len.uint32)
func endWrapPoint*(self: WrapChunk): WrapPoint = wrapPoint(self.wrapPoint.row, self.wrapPoint.column + self.inputChunk.len.uint32)
func len*(self: WrapChunk): int = self.inputChunk.len
func `$`*(self: WrapChunk): string = &"WC({self.wrapPoint}...{self.endWrapPoint}, {self.inputChunk})"
template toOpenArray*(self: WrapChunk): openArray[char] = self.inputChunk.toOpenArray
template scope*(self: WrapChunk): string = self.inputChunk.scope

proc split*(self: WrapChunk, index: int): tuple[prefix: WrapChunk, suffix: WrapChunk] =
  let (prefix, suffix) = self.inputChunk.split(index)
  (
    WrapChunk(inputChunk: prefix, wrapPoint: self.wrapPoint),
    WrapChunk(inputChunk: suffix, wrapPoint: wrapPoint(self.wrapPoint.row, self.wrapPoint.column + index.uint32)),
  )

func isNil*(self: WrapMapSnapshot): bool = self.map.isNil

func endWrapPoint*(self: WrapMapSnapshot): WrapPoint = self.map.summary.dst
func endWrapPoint*(self: WrapMap): WrapPoint = self.snapshot.map.summary.dst

proc desc*(self: WrapMapSnapshot): string =
  &"WrapMapSnapshot(@{self.version}, {self.map.summary}, {self.interpolated}, {self.input.desc})"

proc `$`*(self: WrapMapSnapshot): string =
  result.add self.desc
  result.add "\n"
  var c = self.map.initCursor(WrapMapChunkSummary)
  var i = 0
  while not c.atEnd:
    c.next()
    if c.item.getSome(item):
      let r = c.startPos.src...c.endPos.src
      let rd = c.startPos.dst...c.endPos.dst
      if item.src != inputPoint() or true:
        result.add &"  {i}: {item.src} -> {item.dst}   |   {r} -> {rd}\n"
        inc i

proc toWrapPoint*(self: WrapMapChunkCursor, point: InputPoint): WrapPoint =
  let point2 = point.clamp(self.startPos.src...self.endPos.src)
  let offset = point2 - self.startPos.src
  return (self.startPos.dst + offset.toWrapPoint)

proc toWrapPointNoClamp*(self: WrapMapChunkCursor, point: InputPoint): WrapPoint =
  var c = self
  discard c.seek(point.WrapMapChunkSrc, Bias.Right, ())
  if c.item.getSome(item) and item.src == inputPoint():
    c.next()
  let point2 = point.clamp(c.startPos.src...c.endPos.src)
  let offset = point2 - c.startPos.src
  return (c.startPos.dst + offset.toWrapPoint)

proc toWrapPoint*(self: WrapMapSnapshot, point: InputPoint, bias: Bias = Bias.Right): WrapPoint =
  var c = self.map.initCursor(WrapMapChunkSummary)
  discard c.seek(point.WrapMapChunkSrc, bias, ())
  if c.item.getSome(item) and item.src == inputPoint():
    c.next()

  return c.toWrapPoint(point)

proc toWrapPoint*(self: WrapMapSnapshot, point: Point, bias: Bias = Bias.Right): WrapPoint =
  self.toWrapPoint(self.input.toOutputPoint(point, bias), bias)

proc toWrapPoint*(self: WrapMap, point: InputPoint, bias: Bias = Bias.Right): WrapPoint =
  self.snapshot.toWrapPoint(point, bias)

proc toInputPoint*(self: WrapMapChunkCursor, point: WrapPoint): InputPoint =
  let point = point.clamp(self.startPos.dst...self.endPos.dst)
  let offset = point - self.startPos.dst
  return self.startPos.src + offset.toInputPoint

proc toInputPoint*(self: WrapMapSnapshot, point: WrapPoint, bias: Bias = Bias.Left): InputPoint =
  var c = self.map.initCursor(WrapMapChunkSummary)
  discard c.seek(point.WrapMapChunkDst, bias, ())
  if c.item.getSome(item) and item.src == inputPoint():
    c.next()

  return c.toInputPoint(point)

proc toInputPoint*(self: WrapMap, point: WrapPoint, bias: Bias = Bias.Right): InputPoint =
  self.snapshot.toInputPoint(point, bias)

proc lineLen*(self: WrapMapSnapshot, line: int): int =
  return self.toWrapPoint(self.input.lineRange(line).b).column.int

proc lineRange*(self: WrapMapSnapshot, line: int): Range[WrapPoint] =
  return wrapPoint(line, 0)...wrapPoint(line, self.lineLen(line))

proc toWrapBytes*(self: WrapMapSnapshot, point: WrapPoint, bias: Bias = Bias.Right): int =
  let inputPoint = self.toInputPoint(point)
  let columnDiff = point.column.int - inputPoint.column.int
  let lineDiff = point.row.int - inputPoint.row.int
  if columnDiff != 0 and point.column.int < self.wrappedIndent:
    # The wrap point is on a wrapped line
    let wrappedIndentBytes = (lineDiff - 1) * self.wrappedIndent
    let inputBytes = self.input.toOutputBytes(inputPoint, bias)
    return inputBytes + lineDiff + wrappedIndentBytes + point.column.int
  else:
    let wrappedIndentBytes = lineDiff * self.wrappedIndent
    let inputBytes = self.input.toOutputBytes(inputPoint, bias)
    return inputBytes + lineDiff + wrappedIndentBytes

proc validate*(self: WrapMapSnapshot) =
  var c = self.map.initCursor(WrapMapChunkSummary)
  var endPos = inputPoint()
  c.next()
  while c.item.getSome(_):
    endPos = c.endPos.src
    c.next()

  if endPos != self.input.endOutputPoint:
    echo &"--------------------------------\n-------------------------------\nInvalid wrap map {self.desc}, endpos {endPos} != {self.input.endOutputPoint}\n{self}\n---------------------------------------"
    return

  if self.map.summary.src != self.input.endOutputPoint:
    echo &"--------------------------------\n-------------------------------\nInvalid wrap map {self.desc}, summary {self.map.summary.src} != {self.input.endOutputPoint}\n{self}\n---------------------------------------"
    return

proc editImpl(self: var WrapMapSnapshot, input: sink InputMapSnapshot, patch: Patch[InputPoint]): Patch[WrapPoint] =
  logMapUpdate &"WrapMapSnapshot.editImpl {self.desc} -> {input.desc} | {patch}"

  if self.map.summary == WrapMapChunkSummary():
    let endPoint = input.endOutputPoint
    self = WrapMapSnapshot(
      map: SumTree[WrapMapChunk].new([WrapMapChunk(src: endPoint, dst: endPoint.WrapPoint)]),
      input: input.ensureMove,
      interpolated: false,
      version: self.version + 1)
    for e in patch.edits:
      result.add initEdit(e.old.a.WrapPoint...e.old.b.WrapPoint, e.new.a.WrapPoint...e.new.b.WrapPoint)
    return

  log &"============\nedit {patch}\n  {self}"

  var newMap = SumTree[WrapMapChunk].new()

  var c = self.map.initCursor(WrapMapChunkSummary)
  var currentRange = inputPoint()...inputPoint()
  var currentChunk = WrapMapChunk()
  for e in patch.edits:
    # e[i].new takes into account any edits < i
    # eu[i].new is as if it was the only edit (i.e. eu[i].old.a == eu[i].new.a)
    var eu = e
    eu.new.a = eu.old.a
    eu.new.b = eu.new.a + (e.new.b - e.new.a).toInputPoint

    while true:
      log &"edit edit: {e}|{eu}, currentChunk: {currentChunk}, newMap: {newMap.toSeq}"
      if not c.didSeek or eu.old.a >= c.endPos.src:
        if currentRange != inputPoint()...inputPoint():
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

      if c.item.getSome(item) and item.src == inputPoint() and self.map.summary.src > inputPoint():
        log &"================== skip {item[]}, {c.startPos} -> {c.endPos}"
        newMap.add item[]
        c.next()

      if c.startPos.src...c.endPos.src != currentRange:
        currentChunk = c.item.get[]
        currentRange = c.startPos.src...c.endPos.src
        log &"  reset current chunk to {currentChunk}, {currentRange}"

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
        new: c.toWrapPoint(eu.new.a)...(c.toWrapPoint(eu.new.a) + (eu.new.b - eu.new.a).toWrapPoint))

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

      currentChunk.src += editDiff
      currentChunk.dst += displayEditDiff

      if eu.old.b > map.src.b:
        let bias = if eu.old.b < self.map.summary.src:
          Bias.Right
        else:
          Bias.Left

        log &"  add2 current chunk {currentChunk}"
        # todo: only add when not empty
        newMap.add currentChunk
        newMap.add(WrapMapChunk(src: inputPoint(), dst: wrapPoint(1, self.wrappedIndent)), ())
        discard c.seekForward(eu.old.b.WrapMapChunkSrc, bias, ())
        log &"  seek {eu.old.b} -> {eu.old.b} >= {c.endPos.src}"
      else:
        break

  if newMap.isEmpty or currentRange != inputPoint()...inputPoint():
    log &"  add final current chunk {currentChunk}"
    newMap.add currentChunk
    c.next()

  newMap.append c.suffix()

  logMapUpdate &"  WrapMapSnapshot.editImpl summary {self.map.summary} -> {newMap.summary}"
  self = WrapMapSnapshot(map: newMap.ensureMove, input: input.ensureMove, version: self.version + 1)
  log &"{self}"
  # self.validate()

proc edit*(self: var WrapMapSnapshot, input: sink InputMapSnapshot, patch: Patch[InputPoint]): Patch[WrapPoint] =
  if self.buffer.remoteId == input.buffer.remoteId and self.buffer.version == input.buffer.version and self.input.version == input.version:
    return

  var p = Patch[InputPoint]()
  p.edits.setLen(1)
  for edit in patch.edits:
    var newEdit = edit
    newEdit.old.a = newEdit.new.a
    newEdit.old.b = newEdit.old.a + (edit.old.b - edit.old.a).toInputPoint
    p.edits[0] = newEdit
      # todo: return val
    discard self.editImpl(input.clone(), p)

proc flushEdits(self: WrapMap) =
  var firstI = 0
  for i in 0..self.pendingEdits.high:
    if self.pendingEdits[i].input.version > self.snapshot.input.version:
      # todo: return val
      discard self.snapshot.edit(self.pendingEdits[i].input.clone(), self.pendingEdits[i].patch)
    else:
      firstI = i + 1

proc edit*(self: WrapMap, input: sink InputMapSnapshot, patch: Patch[InputPoint]): Patch[WrapPoint] =
  logMapUpdate &"WrapMap.edit {self.snapshot.desc} -> {input.desc} | {patch}"
  self.pendingEdits.add (input.ensureMove, patch)
  self.flushEdits()
  # todo: return val

proc update*(self: var WrapMapSnapshot, input: sink InputMapSnapshot, wrapWidth: int, wrappedIndent: int) =
  # todo: Take in a patch and only recalculate line wrapping for changed lines.
  # Right now it takes around 30s to update the wrap map for a 1Gb file, with this change
  # the initial update would still take this long but incremental updates would be way faster.
  # To reduce the initial update time we could just not run the line wrapping for the entire file at first,
  # and then only trigger line wrapping for lines being rendered by calling update with a patch which covers
  # the lines to be rendered but doesn't change the length (so basically just a replace patch).

  if wrapWidth == 0:
    let endPoint = input.endOutputPoint
    self = WrapMapSnapshot(
      map: SumTree[WrapMapChunk].new([WrapMapChunk(src: endPoint, dst: endPoint.WrapPoint)]),
      input: input.ensureMove,
      interpolated: false,
      version: self.version + 1)
    logMapUpdate &"WrapMap.upate identity {self.map.summary}"
    log &"{self}"
    return

  let wrappedIndent = min(wrappedIndent, wrapWidth - 1)
  self.wrappedIndent = wrappedIndent

  var currentRange = inputPoint()...inputPoint()
  var currentDisplayRange = wrapPoint()...wrapPoint()

  var iter = input.iter()
  var nextWrapColumn = wrapWidth

  var newMap = SumTree[WrapMapChunk].new()
  var lastInputPoint = inputPoint(0, 0)

  iter.seekLine(0)
  var lastWasTab = false
  while iter.next().getSome(chunk2):
    var chunk = chunk2
    if chunk.outputPoint.row > lastInputPoint.row:
      nextWrapColumn = wrapWidth
      currentRange.b += inputPoint(1, 0)
      currentDisplayRange.b += wrapPoint(1, 0)

    var indent = wrappedIndent
    if self.wrapAtTabs and chunk.wasTab and chunk.outputPoint.column > 0 and not lastWasTab:
      nextWrapColumn = chunk.outputPoint.column.int
      indent = 0

    lastInputPoint = chunk.endOutputPoint
    lastWasTab = chunk.wasTab

    while chunk.len > 0:
      if chunk.outputPoint.column.int >= nextWrapColumn:
        if currentDisplayRange.a != currentDisplayRange.b:
          newMap.add(WrapMapChunk(
              src: (currentRange.b - currentRange.a).toInputPoint,
              dst: (currentDisplayRange.b - currentDisplayRange.a).toWrapPoint,
            ), ())
        newMap.add(WrapMapChunk(src: inputPoint(), dst: wrapPoint(1, indent)), ())
        currentRange.b = inputPoint(0, chunk.outputPoint.column.int - nextWrapColumn)
        currentDisplayRange.b = wrapPoint(0, chunk.outputPoint.column.int - nextWrapColumn)
        nextWrapColumn += wrapWidth - indent

      if chunk.endOutputPoint.column.int <= nextWrapColumn:
        currentRange.b.column += chunk.len.uint32
        currentDisplayRange.b.column += chunk.len.uint32
        break

      else:
        assert chunk.outputPoint.column.int < nextWrapColumn
        let fontScale = chunk.inputChunk.styledChunk.fontScale
        let splitIndex = ((nextWrapColumn - chunk.outputPoint.column.int).float / fontScale).int
        let (prefix, suffix) = chunk.split(splitIndex)
        currentRange.b.column += prefix.len.uint32
        currentDisplayRange.b.column += prefix.len.uint32

        if currentDisplayRange.a != currentDisplayRange.b:
          newMap.add(WrapMapChunk(
              src: (currentRange.b - currentRange.a).toInputPoint,
              dst: (currentDisplayRange.b - currentDisplayRange.a).toWrapPoint,
            ), ())

        newMap.add(WrapMapChunk(src: inputPoint(), dst: wrapPoint(1, indent)), ())
        currentRange.b = inputPoint(0, 0)
        currentDisplayRange.b = wrapPoint(0, 0)
        nextWrapColumn += wrapWidth - indent
        chunk = suffix

  if currentDisplayRange.a != currentDisplayRange.b:
    newMap.add(WrapMapChunk(
        src: (currentRange.b - currentRange.a).toInputPoint,
        dst: (currentDisplayRange.b - currentDisplayRange.a).toWrapPoint,
      ), ())

  self = WrapMapSnapshot(map: newMap.ensureMove, input: input.ensureMove, interpolated: false, version: self.version + 1)
  self.validate()

proc updateThread(self: ptr WrapMapSnapshot, input: ptr InputMapSnapshot, wrapWidth: int, wrappedIndent: int): int =
  self[].update(input[].clone(), wrapWidth, wrappedIndent)

# todo
# proc computeEdits(old: WrapMapSnapshot, new: WrapMapSnapshot, edits: Patch[InputPoint]): Patch[WrapPoint] =
#   var oldCursor = old.map.initCursor(WrapMapChunkSummary)
#   var newCursor = new.map.initCursor(WrapMapChunkSummary)
#   for edit in edits.edits:
#     var edit = edit
#     edit.old.a.column = 0
#     edit.old.b += inputPoint(1, 0)
#     edit.new.a.column = 0
#     edit.new.b += inputPoint(1, 0)

#     discard oldCursor.seek(edit.old.a.WrapMapChunkSrc, Bias.Right, ())
#     var oldStart = oldCursor.startPos.dst
#     oldStart += (edit.old.a - oldCursor.startPos.src).toWrapPoint

#     discard oldCursor.seek(edit.old.b.WrapMapChunkSrc, Bias.Right, ())
#     var oldEnd = oldCursor.startPos.dst
#     oldEnd += (edit.old.b - oldCursor.startPos.src).toWrapPoint

#     discard newCursor.seek(edit.new.a.WrapMapChunkSrc, Bias.Right, ())
#     var newStart = newCursor.startPos.dst
#     newStart += (edit.new.a - newCursor.startPos.src).toWrapPoint

#     discard newCursor.seek(edit.new.b.WrapMapChunkSrc, Bias.Right, ())
#     var newEnd = newCursor.startPos.dst
#     newEnd += (edit.new.b - newCursor.startPos.src).toWrapPoint

#     result.add initEdit(oldStart...oldEnd, newStart...newEnd)

#   # echo &"computeEdits {edits}\n  A: {old}\n  B: {new}\n  -> {result}"

proc updateAsync(self: WrapMap) {.async.} =
  if self.updatingAsync: return
  self.updatingAsync = true
  defer: self.updatingAsync = false

  var b = self.snapshot.input.clone()

  while true:
    var snapshot = self.snapshot.clone()
    let wrapWidth = self.wrapWidth
    let wrappedIndent = self.wrappedIndent
    let flowVar = spawn updateThread(snapshot.addr, b.addr, wrapWidth, wrappedIndent)
    var i = 0
    while not flowVar.isReady:
      let sleepTime = if i < 5: 1 else: 10
      await sleepAsync(sleepTime.milliseconds)
      inc i

    if self.snapshot.buffer.remoteId != snapshot.buffer.remoteId or wrapWidth != self.wrapWidth or wrappedIndent != self.wrappedIndent or self.snapshot.input.version != b.version:
      b = self.snapshot.input.clone()
      continue

    block:
      for i in 0..self.pendingEdits.high:
        if self.pendingEdits[i].input.buffer.version.changedSince(snapshot.buffer.version):
          # todo: return val
          discard snapshot.edit(self.pendingEdits[i].input.clone(), self.pendingEdits[i].patch)
    snapshot.validate()

    let oldSnapshot = self.snapshot.clone()
    self.snapshot = snapshot.clone()
    logMapUpdate &"WrapMap.updatedAsync {self.snapshot.desc}"
    self.onUpdated.invoke((self, oldSnapshot))

    if not self.snapshot.interpolated:
      self.pendingEdits.setLen(0)
      return

    b = self.snapshot.input.clone()

proc clear*(self: var WrapMapSnapshot) =
  let endPoint = self.input.endOutputPoint
  self = WrapMapSnapshot(
    map: SumTree[WrapMapChunk].new([WrapMapChunk(src: endPoint, dst: endPoint.WrapPoint)]),
    input: self.input.clone(),
    interpolated: false,
    version: self.version + 1)

proc clear*(self: WrapMap) =
  let oldSnapshot = self.snapshot.clone()
  self.snapshot.clear()
  self.onUpdated.invoke((self, oldSnapshot))

proc setInput*(self: WrapMap, input: sink InputMapSnapshot) =
  # logMapUpdate &"WrapMap.setInput {self.snapshot.desc} -> {input.desc}"
  if self.snapshot.buffer.remoteId == input.buffer.remoteId and self.snapshot.buffer.version == input.buffer.version and self.snapshot.input.version == input.version:
    return

  let endPoint = input.endOutputPoint
  self.snapshot = WrapMapSnapshot(
    map: SumTree[WrapMapChunk].new([WrapMapChunk(src: endPoint, dst: endPoint.WrapPoint)]),
    input: input.ensureMove,
  )
  self.pendingEdits.setLen(0)
  if self.wrapWidth != 0:
    asyncSpawn self.updateAsync()

proc update*(self: WrapMap, wrapWidth: int, force: bool = false) =
  if not force and self.wrapWidth == wrapWidth:
    return

  logMapUpdate &"WrapMap.updateWidth {self.snapshot.desc}, {self.wrapWidth} -> {wrapWidth}, force = {force}"
  self.wrapWidth = wrapWidth
  if self.wrapWidth != 0:
    asyncSpawn self.updateAsync()
  else:
    self.clear()

proc update*(self: WrapMap, input: sink InputMapSnapshot, force: bool = false) =
  # logMapUpdate &"WrapMap.updateInput {self.snapshot.buffer.remoteId}@{self.snapshot.buffer.version} -> {input.buffer.remoteId}@{input.buffer.version}, {self.snapshot.input.map.summary} -> {input.map.summary}, force = {force}"
  if not force and self.snapshot.buffer.remoteId == input.buffer.remoteId and self.snapshot.buffer.version == input.buffer.version:
    return

  asyncSpawn self.updateAsync()

proc seek*(self: var WrapChunkIterator, wrapPoint: WrapPoint) =
  assert wrapPoint >= self.wrapPoint
  discard self.wrapMapCursor.seekForward(wrapPoint.WrapMapChunkDst, Bias.Right, ())
  if self.wrapMapCursor.item.getSome(item) and item.src == inputPoint():
    self.wrapMapCursor.next()
  self.wrapPoint = wrapPoint
  let inputPoint = self.wrapMapCursor.toInputPoint(self.wrapPoint)
  self.inputChunks.seek(inputPoint)
  self.localOffset = 0
  self.inputChunk = InputChunk.none
  self.wrapChunk = WrapChunk.none

proc seek*(self: var WrapChunkIterator, point: Point) =
  self.inputChunks.seek(point)
  discard self.wrapMapCursor.seekForward(self.inputChunks.outputPoint.WrapMapChunkSrc, Bias.Right, ())
  if self.wrapMapCursor.item.getSome(item) and item.src == inputPoint():
    self.wrapMapCursor.next()
  let wrapPoint = self.wrapMapCursor.toWrapPoint(self.inputChunks.outputPoint)
  self.wrapPoint = wrapPoint
  self.localOffset = 0
  self.inputChunk = InputChunk.none
  self.wrapChunk = WrapChunk.none

proc seekLine*(self: var WrapChunkIterator, line: int) =
  self.seek(wrapPoint(line))

proc next*(self: var WrapChunkIterator): Option[WrapChunk] =
  if self.atEnd:
    self.wrapChunk = WrapChunk.none
    return

  if self.inputChunk.isNone or self.localOffset >= self.inputChunk.get.len:
    self.inputChunk = self.inputChunks.next()
    self.localOffset = 0
    if self.inputChunk.isNone:
      self.atEnd = true
      self.wrapChunk = WrapChunk.none
      return

  assert self.inputChunk.isSome
  let currentChunk = self.inputChunk.get
  let currentInputPoint = currentChunk.outputPoint + inputPoint(0, self.localOffset)
  discard self.wrapMapCursor.seek(currentInputPoint.WrapMapChunkSrc, Bias.Right, ())
  if self.wrapMapCursor.item.getSome(item) and item.src == inputPoint():
    self.wrapMapCursor.next()

  self.wrapPoint = self.wrapMapCursor.toWrapPoint(currentInputPoint)

  let startOffset = self.localOffset
  let map = (
    src: self.wrapMapCursor.startPos.src...self.wrapMapCursor.endPos.src,
    dst: self.wrapMapCursor.startPos.dst...self.wrapMapCursor.endPos.dst)

  if currentChunk.endOutputPoint <= map.src.b:
    self.localOffset = currentChunk.len
    assert self.localOffset >= 0
    var newChunk = currentChunk.split(startOffset).suffix.split(self.localOffset - startOffset).prefix
    newChunk.outputPoint = currentInputPoint
    self.wrapChunk = WrapChunk(inputChunk: newChunk, wrapPoint: self.wrapPoint).some

  else:
    self.localOffset = map.src.b.column.int - currentChunk.outputPoint.column.int
    if self.localOffset < 0:
      self.wrapChunk = WrapChunk(inputChunk: currentChunk, wrapPoint: self.wrapPoint).some
      return

    assert self.localOffset >= 0
    var newChunk = currentChunk.split(startOffset).suffix.split(self.localOffset - startOffset).prefix
    newChunk.outputPoint = currentInputPoint
    self.wrapChunk = WrapChunk(inputChunk: newChunk, wrapPoint: self.wrapPoint).some

  return self.wrapChunk

#

func toOutputPoint*(self: WrapMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): WrapPoint {.inline.} = self.toWrapPoint(point, bias)
func toOutputPoint*(self: WrapMapSnapshot, point: Point, bias: Bias = Bias.Right): WrapPoint {.inline.} = self.toWrapPoint(point, bias)
func `outputPoint=`*(self: var WrapChunk, point: WrapPoint) = self.wrapPoint = point
template outputPoint*(self: WrapChunk): WrapPoint = self.wrapPoint
template endOutputPoint*(self: WrapChunk): WrapPoint = self.endWrapPoint
template endOutputPoint*(self: WrapMapSnapshot): WrapPoint = self.endWrapPoint

func tabMap*(self: WrapMapSnapshot): lent TabMapSnapshot {.inline.} = self.input
func tabChunks*(self: var WrapChunkIterator): var TabChunkIterator {.inline.} = self.inputChunks
func tabChunks*(self: WrapChunkIterator): lent TabChunkIterator {.inline.} = self.inputChunks
func tabChunk*(self: WrapChunk): lent TabChunk {.inline.} = self.inputChunk
proc toTabPoint*(self: WrapMapChunkCursor, point: WrapPoint): InputPoint {.inline.} = self.toInputPoint(point)
proc toTabPoint*(self: WrapMapSnapshot, point: WrapPoint, bias: Bias = Bias.Right): InputPoint {.inline.} = self.toInputPoint(point, bias)
proc toTabPoint*(self: WrapMap, point: WrapPoint, bias: Bias = Bias.Right): InputPoint {.inline.} = self.toInputPoint(point, bias)
func outputPoint*(self: WrapChunkIterator): WrapPoint = self.wrapPoint
