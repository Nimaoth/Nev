import std/[options, strutils, strformat, enumerate]
import nimsumtree/[rope, sumtree, buffer, clock]
import misc/[custom_async, custom_unicode, util, event, rope_utils]
import syntax_map, overlay_map
import chroma, theme

var debugTabMap* = false

{.push gcsafe.}
{.push raises: [].}

type InputMapSnapshot = OverlayMapSnapshot
type InputChunkIterator = OverlayChunkIterator
type InputChunk = OverlayChunk
type InputPoint = OverlayPoint
proc inputPoint(row: Natural = 0, column: Natural = 0): InputPoint {.inline.} = overlayPoint(row, column)

type TabPoint* {.borrow: `.`.} = distinct Point
func tabPoint*(row: Natural = 0, column: Natural = 0): TabPoint = Point(row: row.uint32, column: column.uint32).TabPoint
func `$`*(a: TabPoint): string {.borrow.}
func `<`*(a: TabPoint, b: TabPoint): bool {.borrow.}
func `==`*(a: TabPoint, b: TabPoint): bool {.borrow.}
func `<=`*(a: TabPoint, b: TabPoint): bool {.borrow.}
func `+`*(a: TabPoint, b: TabPoint): TabPoint {.borrow.}
func `+`*(point: TabPoint, diff: PointDiff): TabPoint {.borrow.}
func `+=`*(a: var TabPoint, b: TabPoint) {.borrow.}
func `+=`*(point: var TabPoint, diff: PointDiff) {.borrow.}
func `-`*(a: TabPoint, b: TabPoint): PointDiff {.borrow.}
func dec*(a: var TabPoint): TabPoint {.borrow.}
func pred*(a: TabPoint): TabPoint {.borrow.}
func clone*(a: TabPoint): TabPoint {.borrow.}
func cmp*(a: TabPoint, b: TabPoint): int {.borrow.}
func clamp*(p: TabPoint, r: Range[TabPoint]): TabPoint = min(max(p, r.a), r.b)
converter toTabPoint*(diff: PointDiff): TabPoint = diff.toPoint.TabPoint

type
  TabChunk* = object
    inputChunk*: InputChunk
    tabPoint*: TabPoint
    wasTab*: bool

  TabMapSnapshot* = object
    version*: int
    input*: InputMapSnapshot
    tabWidth*: int = 4
    maxExpansionColumn: int = 64

  TabMap* = ref object
    snapshot*: TabMapSnapshot
    onUpdated*: Event[tuple[map: TabMap, old: TabMapSnapshot, patch: Patch[TabPoint]]]

  TabChunkIterator* = object
    inputChunks*: InputChunkIterator
    tabMap* {.cursor.}: TabMapSnapshot
    tabChunk*: Option[TabChunk]
    tabPoint*: TabPoint
    tabTexts: string
    column*: int
    outputColumn*: int
    inputColumn*: int
    maxExpansionColumn: int
    insideLeadingTab: bool
    atEnd*: bool
    tabColor: Color

func toTabPoint*(self: TabMapSnapshot, point: InputPoint): TabPoint
proc toInputPointEx*(self: TabMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): tuple[inputPoint: InputPoint, expandedChars: int, toNextStop: int]

func buffer*(self: TabMapSnapshot): lent BufferSnapshot = self.input.buffer

func clone*(self: TabMapSnapshot): TabMapSnapshot =
  TabMapSnapshot(input: self.input.clone(), tabWidth: self.tabWidth, maxExpansionColumn: self.maxExpansionColumn, version: self.version)

proc new*(_: typedesc[TabMap]): TabMap =
  result = TabMap(snapshot: TabMapSnapshot())

func point*(self: TabChunkIterator): Point {.inline.} = self.inputChunks.point
template styledChunk*(self: TabChunk): StyledChunk = self.inputChunk.styledChunk
func styledChunk*(self: var TabChunk): var StyledChunk {.inline.} = self.inputChunk.styledChunk
func chunk*(self: var TabChunk): var RopeChunk = self.styledChunk.chunk
func chunk*(self: TabChunk): RopeChunk = self.styledChunk.chunk
func styledChunks*(self: var TabChunkIterator): var StyledChunkIterator {.inline.} = self.inputChunks.styledChunks
func styledChunks*(self: TabChunkIterator): StyledChunkIterator {.inline.} = self.inputChunks.styledChunks
func point*(self: TabChunk): Point = self.inputChunk.point
func endPoint*(self: TabChunk): Point = self.inputChunk.endPoint
func tabEndPoint*(self: TabChunk): TabPoint = tabPoint(self.tabPoint.row, self.tabPoint.column + self.inputChunk.len.uint32)
func endTabPoint*(self: TabChunk): TabPoint = tabPoint(self.tabPoint.row, self.tabPoint.column + self.inputChunk.len.uint32)
func len*(self: TabChunk): int = self.inputChunk.len
func `$`*(self: TabChunk): string = &"TC({self.tabPoint}...{self.endTabPoint}, {self.inputChunk})"
template toOpenArray*(self: TabChunk): openArray[char] = self.inputChunk.toOpenArray

proc split*(self: TabChunk, index: int): tuple[prefix: TabChunk, suffix: TabChunk] =
  let (prefix, suffix) = self.inputChunk.split(index)
  (
    TabChunk(inputChunk: prefix, wasTab: self.wasTab, tabPoint: self.tabPoint),
    TabChunk(inputChunk: suffix, wasTab: self.wasTab, tabPoint: tabPoint(self.tabPoint.row, self.tabPoint.column + index.uint32)),
  )

proc `[]`*(self: TabChunk, r: Range[int]): TabChunk =
  TabChunk(inputChunk: self.inputChunk[r], wasTab: self.wasTab, tabPoint: tabPoint(self.tabPoint.row, self.tabPoint.column + r.a.uint32))

func isNil*(self: TabMapSnapshot): bool = false

func endTabPoint*(self: TabMapSnapshot): TabPoint = self.toTabPoint(self.input.endOutputPoint)
func endTabPoint*(self: TabMap): TabPoint = self.snapshot.endTabPoint

proc lineLen*(self: TabMapSnapshot, line: int): int =
  return self.toTabPoint(inputPoint(line, self.input.lineLen(line))).column.int

proc desc*(self: TabMapSnapshot): string =
  &"TabMapSnapshot(@{self.version}, {self.tabWidth}, {self.input.desc})"

proc `$`*(self: TabMapSnapshot): string =
  result.add self.desc

proc iter*(self {.byref.}: TabMapSnapshot, highlighter: Option[Highlighter] = Highlighter.none): TabChunkIterator =
  let r = tabPoint(0, 0)...self.endTabPoint # todo: pass as parameter
  var (_, _, toNextStop) = self.toInputPointEx(r.a)
  if r.a + tabPoint(0, toNextStop) > r.b:
    toNextStop = r.b.column.int - r.a.column.int
  result = TabChunkIterator(
    inputChunks: self.input.iter(highlighter),
    tabMap: self.clone(),
    maxExpansionColumn: self.maxExpansionColumn,
    insideLeadingTab: toNextStop > 0,
    tabTexts: "|" & " ".repeat(self.tabWidth - 1),
    tabColor: color(1, 1, 1),
  )
  if highlighter.isSome:
    result.tabColor = highlighter.get.theme.tokenColor(["tab", "comment"], color(1, 1, 1))

func expandTabs*(self: TabMapSnapshot, chunks: var InputChunkIterator, column: int): int =
  if self.buffer.visibleText.summary.tabs == 0:
    return column

  var expandedChars = 0
  var expandedBytes = 0
  var collapsedBytes = 0
  let endColumn = min(column, self.maxExpansionColumn)

  # chunks.next() should only have side effects when using a highlighter, which we don't for this
  {.cast(noSideEffect).}:
    block outer:
      while chunks.next().getSome(chunk):
        for c in chunk.toOpenArray.runes:
          if collapsedBytes >= endColumn:
            break outer

          if c == '\t'.Rune:
            let tabLen = self.tabWidth - expandedChars mod self.tabWidth
            expandedBytes += tabLen
            expandedChars += tabLen
          else:
            expandedBytes += c.size
            expandedChars += 1

          collapsedBytes += c.size

  result = expandedBytes + column - collapsedBytes
  # debugEcho &"expandTabs {column} -> chars: {expandedChars}, bytes: {expandedBytes}, collapsedBytes: {collapsedBytes} -> {result}"
  # result = column

proc collapseTabs*(self: TabMapSnapshot, chunks: var InputChunkIterator, column: int, bias: Bias): tuple[collapsedBytes: int, expandedChars: int, toNextStop: int] =
  if self.buffer.visibleText.summary.tabs == 0:
    return (column, column, 0)

  var expandedBytes = 0
  var expandedChars = 0
  var collapsedBytes = 0
  # chunks.next() should only have side effects when using a highlighter, which we don't for this
  {.cast(noSideEffect).}:
    block outer:
      while chunks.next().getSome(chunk):
        for c in chunk.toOpenArray.runes:
          if expandedBytes >= column or collapsedBytes >= self.maxExpansionColumn:
            break outer

          if c == '\t'.Rune:
            let tabLen = self.tabWidth - expandedChars mod self.tabWidth
            expandedBytes += tabLen
            expandedChars += tabLen
            if expandedBytes > column:
              expandedChars -= expandedBytes - column
              result = case bias
              of Bias.Left: (collapsedBytes, expandedChars, expandedBytes - column)
              of Bias.Right: (collapsedBytes + 1, expandedChars, 0)
              return
          else:
            expandedBytes += c.size
            expandedChars += 1

          if expandedBytes > column and bias == Bias.Left:
            expandedChars -= 1
            break outer

          collapsedBytes += c.size

  result = (collapsedBytes + max(column - expandedBytes, 0), expandedChars, 0)

func toTabPoint*(self: TabMapSnapshot, point: InputPoint): TabPoint =
  if self.buffer.visibleText.summary.tabs == 0:
    return point.TabPoint
  else:
    var chunks = self.input.iter()
    chunks.seekLine(point.row.int)
    let expanded = self.expandTabs(chunks, point.column.int)
    return tabPoint(point.row.int, expanded)

proc toTabPoint*(self: TabMapSnapshot, point: Point, bias: Bias = Bias.Right): TabPoint =
  self.toTabPoint(self.input.toOutputPoint(point, bias))

proc toTabPoint*(self: TabMap, point: InputPoint, bias: Bias = Bias.Right): TabPoint =
  self.snapshot.toTabPoint(point)

proc toInputPoint*(self: TabMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): InputPoint =
  if self.buffer.visibleText.summary.tabs == 0:
    return point.InputPoint
  else:
    var chunks = self.input.iter()
    chunks.seekLine(point.row.int)
    let (collapsedBytes, _, _) = self.collapseTabs(chunks, point.column.int, bias)
    return inputPoint(point.row.int, collapsedBytes)

proc toInputPointEx*(self: TabMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): tuple[inputPoint: InputPoint, expandedChars: int, toNextStop: int] =
  var chunks = self.input.iter()
  chunks.seekLine(point.row.int)
  let (collapsedBytes, expandedChars, toNextStop) = self.collapseTabs(chunks, point.column.int, bias)
  return (inputPoint(point.row.int, collapsedBytes), expandedChars, toNextStop)

proc toInputPoint*(self: TabMap, point: TabPoint, bias: Bias = Bias.Right): InputPoint =
  self.snapshot.toInputPoint(point, bias)

proc toTabBytes*(self: TabMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): int =
  let inputPoint = self.toInputPoint(point)
  let columnDiff = point.column.int - inputPoint.column.int
  let inputBytes = self.input.toOutputBytes(inputPoint, bias)
  # echo &"toTabBytes {point} ({bias}) -> {inputPoint} -> {columnDiff} + {inputBytes} = {inputBytes + columnDiff}"
  return inputBytes + columnDiff

proc lineLength*(self: TabMapSnapshot, point: TabPoint): int =
  let inputPoint = self.toInputPoint(point)
  echo &"Tab.lineLength {point} -> {inputPoint}"
  let subLen = self.input.lineLength(inputPoint)
  echo &"Tab.lineLength -> {subLen}"
  return subLen

proc setInput*(self: TabMap, input: sink InputMapSnapshot) =
  # logMapUpdate &"TabMap.setInput {self.snapshot.desc} -> {input.desc}"
  if self.snapshot.buffer.remoteId == input.buffer.remoteId and self.snapshot.buffer.version == input.buffer.version and self.snapshot.input.version == input.version:
    return

  self.snapshot = TabMapSnapshot(
    tabWidth: self.snapshot.tabWidth,
    input: input.ensureMove,
  )

proc validate*(self: TabMapSnapshot) =
  # log &"validate {self.buffer.remoteId}{self.buffer.version}"
  discard

proc edit*(self: var TabMapSnapshot, input: sink InputMapSnapshot, patch: Patch[InputPoint]): Patch[TabPoint] =
  if self.buffer.remoteId == input.buffer.remoteId and self.buffer.version == input.buffer.version and self.input.version == input.version:
    return

  logMapUpdate &"TabMapSnapshot.edit {self.desc} -> {input.desc} | {patch}"

  let old = self.clone()

  # self.input = input.ensureMove
  self.input = input.clone()
  self.version.inc

  for e in patch.edits:
    # todo: an insert might lead to a delete after if there is a \t somewhere after the edit
    let old = old.toTabPoint(e.old.a)...old.toTabPoint(e.old.b)
    let new = self.toTabPoint(e.new.a)...self.toTabPoint(e.new.b)
    # let old = tabPoint(e.old.a.row, 0)...tabPoint(e.old.b.row.int, old.lineLen(e.old.b.row.int))
    # let new = tabPoint(e.new.a.row, 0)...tabPoint(e.new.b.row.int, self.lineLen(e.new.b.row.int))
    result.add initEdit(old, new)
    # echo &"TabMapSnapshot.edit {self.desc} -> {input.desc}\n  {patch}\n  {old} -> {new}"

proc edit*(self: TabMap, input: sink InputMapSnapshot, patch: Patch[InputPoint]): Patch[TabPoint] =
  logMapUpdate &"TabMap.edit {self.snapshot.desc} -> {input.desc} | {patch}"
  self.snapshot.edit(input, patch)

proc setTabWidth*(self: TabMap, tabWidth: int) =
  if tabWidth == self.snapshot.tabWidth:
    return

  logMapUpdate &"TabMap.setWrapWidth {self.snapshot.desc} -> {tabWidth}"

  let old = self.snapshot.clone()
  self.snapshot = TabMapSnapshot(
    version: self.snapshot.version + 1,
    input: self.snapshot.input.clone(),
    tabWidth: tabWidth,
    maxExpansionColumn: self.snapshot.maxExpansionColumn,
  )

  # todo
  let patch = initPatch([initEdit(tabPoint(0, 0)...old.endTabPoint, tabPoint(0, 0)...self.snapshot.endTabPoint)])
  self.onUpdated.invoke (self, old, patch)

proc update*(self: TabMap, input: sink InputMapSnapshot, force: bool = false) =
  if not force and self.snapshot.buffer.remoteId == input.buffer.remoteId and self.snapshot.buffer.version == input.buffer.version and self.snapshot.input.version == input.version:
    return

  logMapUpdate &"TabMap.update {self.snapshot.desc} -> {input.desc}, force = {force}"

  self.snapshot = TabMapSnapshot(
    version: self.snapshot.version + 1,
    input: input.ensureMove,
    tabWidth: self.snapshot.tabWidth,
    maxExpansionColumn: self.snapshot.maxExpansionColumn,
  )

proc seek*(self: var TabChunkIterator, point: Point) =
  # echo &"TabChunkIterator.seek {self.point} -> {point}"
  self.inputChunks.seek(point)
  let tabPoint = self.tabMap.toTabPoint(self.inputChunks.outputPoint)
  self.tabPoint = tabPoint
  self.inputColumn = point.column.int
  self.outputColumn = tabPoint.column.int
  self.column = tabPoint.column.int # todo
  self.tabChunk = TabChunk.none

proc seek*(self: var TabChunkIterator, tabPoint: TabPoint) =
  # echo &"TabChunkIterator.seek {self.tabPoint} -> {tabPoint}"
  assert tabPoint >= self.tabPoint
  self.tabPoint = tabPoint
  let inputPoint = self.tabMap.toInputPoint(self.tabPoint)
  self.inputColumn = inputPoint.column.int
  self.outputColumn = tabPoint.column.int
  self.column = tabPoint.column.int # todo
  self.inputChunks.seek(inputPoint)
  self.tabChunk = TabChunk.none
  # echo &"  {self.inputColumn}, {self.outputColumn}, {self.column}"

proc seekLine*(self: var TabChunkIterator, line: int) =
  self.seek(tabPoint(line))

proc next*(self: var TabChunkIterator): Option[TabChunk] =
  if self.tabChunk.isNone:
    if self.inputChunks.next().getSome(it):
      self.tabChunk = TabChunk(inputChunk: it, tabPoint: self.tabPoint).some
    else:
      return TabChunk.none

  elif self.tabChunk.get.toOpenArray.len == 0:
    if self.inputChunks.next().getSome(it):
      if it.outputPoint.row > self.tabChunk.get.inputChunk.outputPoint.row:
        self.tabChunk = TabChunk(inputChunk: it, tabPoint: it.outputPoint.TabPoint).some
        self.inputColumn = it.outputPoint.column.int
        self.outputColumn = self.inputColumn
        self.column = self.inputColumn
      else:
        self.tabChunk = TabChunk(inputChunk: it, tabPoint: tabPoint(self.tabChunk.get.tabPoint.row, self.outputColumn)).some

      if self.insideLeadingTab:
        self.tabChunk = self.tabChunk.get.split(1)[1].some
        self.insideLeadingTab = false
        self.inputColumn += 1

    else:
      return TabChunk.none

  for i, c in enumerate(self.tabChunk.get.toOpenArray.runes):
    case c
    of '\t'.Rune:
      if i > 0:
        var (prefix, suffix) = self.tabChunk.get.split(i)
        self.tabChunk = suffix.some
        return prefix.some
      else:
        var (prefix, suffix) = self.tabChunk.get.split(1)
        self.tabChunk = suffix.some

        let tabWidth = if self.inputColumn < self.maxExpansionColumn:
          self.tabMap.tabWidth
        else:
          1

        var len = tabWidth - self.column mod tabWidth
        let nextOutputColumn = self.outputColumn + len
        len = nextOutputColumn - self.outputColumn

        self.column += len
        self.inputColumn += 1
        self.outputColumn = nextOutputColumn

        prefix.chunk.data = cast[ptr UncheckedArray[char]](self.tabTexts[0].addr)
        prefix.chunk.len = len
        prefix.styledChunk.color = self.tabColor
        prefix.styledChunk.drawWhitespace = false
        prefix.wasTab = true

        self.tabChunk.get.tabPoint.column = self.outputColumn.uint32

        return prefix.some

    else:
      self.column += 1
      if not self.insideLeadingTab:
        self.inputColumn += c.size
      self.outputColumn += c.size

  result = self.tabChunk
  self.tabChunk.get.chunk.len = 0

#

func toOutputPoint*(self: TabMapSnapshot, point: OverlayPoint, bias: Bias = Bias.Right): TabPoint {.inline.} = self.toTabPoint(point)
func toOutputPoint*(self: TabMapSnapshot, point: Point, bias: Bias = Bias.Right): TabPoint {.inline.} = self.toTabPoint(point, bias)
proc toOutputBytes*(self: TabMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): int {.inline.} = self.toTabBytes(point, bias)
func `outputPoint=`*(self: var TabChunk, point: TabPoint) = self.tabPoint = point
template outputPoint*(self: TabChunk): TabPoint = self.tabPoint
template endOutputPoint*(self: TabChunk): TabPoint = self.endTabPoint
template endOutputPoint*(self: TabMapSnapshot): TabPoint = self.endTabPoint

func overlay*(self: TabMapSnapshot): lent OverlayMapSnapshot {.inline.} = self.input
func overlayChunks*(self: var TabChunkIterator): var OverlayChunkIterator {.inline.} = self.inputChunks
func overlayChunks*(self: TabChunkIterator): lent OverlayChunkIterator {.inline.} = self.inputChunks
func overlayChunk*(self: TabChunk): lent OverlayChunk {.inline.} = self.inputChunk
proc toOverlayPoint*(self: TabMapSnapshot, point: TabPoint, bias: Bias = Bias.Right): InputPoint {.inline.} = self.toInputPoint(point, bias)
proc toOverlayPoint*(self: TabMap, point: TabPoint, bias: Bias = Bias.Right): InputPoint {.inline.} = self.toInputPoint(point, bias)
func outputPoint*(self: TabChunkIterator): TabPoint = self.tabPoint
