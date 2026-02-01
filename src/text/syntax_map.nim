import std/[options, strformat, tables, algorithm]
import nimsumtree/[rope, sumtree, buffer, clock]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[custom_async, custom_unicode, util, regex, timer, rope_utils, arena, array_view]
import text/diff, text/[custom_treesitter, treesitter_type_conv]
from language/lsp_types import nil
import theme
import chroma

{.push gcsafe.}
{.push raises: [].}

type
  RopeChunk* = object
    data*: ptr UncheckedArray[char]
    len*: int
    dataOriginal*: ptr UncheckedArray[char]
    lenOriginal*: int
    point*: Point
    external*: bool

  ChunkIterator* = object
    rope: Rope
    cursor: sumtree.Cursor[rope.Chunk, (Point, int)]
    localOffset*: int
    point*: Point
    returnedLastChunk: bool = false

  RopeChunksState* = object
    seekPoint: Option[Point]
    nextPoint: Point

  # New version of the chunk iterator based on nim iterator instead of manual state management
  ChunkIterator2* = object
    rope: Rope
    iter: iterator(rope: Rope, state: var RopeChunksState): RopeChunk {.gcsafe, raises: [].}
    state: RopeChunksState
    done: bool

type
  StyledChunkUnderline* = object
    color*: Color # todo: dont use string to avoid allocation on copying

  StyledChunk* = object
    chunk*: RopeChunk
    drawWhitespace*: bool = true
    underline*: Option[StyledChunkUnderline]
    color*: Color
    fontStyle*: set[FontStyle]
    fontScale*: float = 1.0

  Highlighter* = object
    query*: TSQuery
    tree*: TsTree
    rainbowParens*: bool

  Highlight = tuple[range: Range[Point], color: Color, fontStyle: set[FontStyle], fontScale: float, priority: int]

  DiagnosticEndPoint* = object
    severity*: lsp_types.DiagnosticSeverity
    start*: bool
    point*: Point

  StyledChunkIterator* = object
    chunks*: ChunkIterator2
    chunk: Option[RopeChunk]
    localOffset: int
    atEnd: bool
    highlighter*: Option[Highlighter]
    theme*: Theme
    highlights: seq[Highlight]
    highlightsIndex: int = -1
    diagnosticEndPoints*: seq[DiagnosticEndPoint]
    diagnosticIndex*: int
    matches: seq[TSQueryMatch]
    predicates: seq[TSPredicateResult]
    defaultColor: Color
    errorDepth: int
    warnDepth: int
    infoDepth: int
    hintDepth: int
    errorColor: Color
    warningColor: Color
    infoColor: Color
    hintColor: Color
    arena: Arena
    parenColors: seq[Color]
    depthOffset: int
    currentNode: TSNode

func high*(_: typedesc[Point]): Point = Point(row: uint32.high, column: uint32.high)

func endPoint*(self: RopeChunk): Point = Point(row: self.point.row, column: self.point.column + self.len.uint32)

func `$`*(chunk: RopeChunk): string =
  proc escape(c: char): string =
    if c == '\n':
      return "\\n"
    return $c
  result = newStringOfCap(chunk.len)
  for i in 0..<chunk.len:
    result.add chunk.data[i].escape
  if chunk.data != chunk.dataOriginal:
    var str = newStringOfCap(chunk.lenOriginal)
    for i in 0..<chunk.lenOriginal:
      str.add chunk.dataOriginal[i].escape
    result = &"RC({chunk.point}...{chunk.endPoint}, '{result}', '{str}', {chunk.external})"
  else:
    result = &"RC({chunk.point}...{chunk.endPoint}, '{result}', {chunk.external})"

func `[]`*(self: RopeChunk, range: Range[int]): RopeChunk =
  assert range.a >= 0 and range.a <= self.len
  assert range.b >= 0 and range.b <= self.len
  assert range.b >= range.a
  return RopeChunk(
    data: cast[ptr UncheckedArray[char]](self.data[range.a].addr),
    len: range.len,
    dataOriginal: cast[ptr UncheckedArray[char]](self.dataOriginal[range.a].addr),
    lenOriginal: range.len,
    external: self.external,
    point: Point(row: self.point.row, column: self.point.column + range.a.uint32),
  )

template toOpenArray*(self: RopeChunk): openArray[char] = self.data.toOpenArray(0, self.len - 1)
template toOpenArrayOriginal*(self: RopeChunk): openArray[char] = self.dataOriginal.toOpenArray(0, self.lenOriginal - 1)

proc split*(self: RopeChunk, index: int): tuple[prefix: RopeChunk, suffix: RopeChunk] =
  if self.data == self.dataOriginal:
    (
      RopeChunk(
        data: self.data,
        len: index,
        dataOriginal: self.dataOriginal,
        lenOriginal: index,
        external: self.external,
        point: self.point,
      ),
      RopeChunk(
        data: cast[ptr UncheckedArray[char]](self.data[index].addr),
        len: self.len - index,
        dataOriginal: cast[ptr UncheckedArray[char]](self.dataOriginal[index].addr),
        lenOriginal: self.lenOriginal - index,
        external: self.external,
        point: point(self.point.row, self.point.column + index.uint32),
      ),
    )
  else:
    let runeOffset = self.data.toOpenArray(0, self.len - 1).offsetToCount(index).int
    let indexOriginal = self.dataOriginal.toOpenArray(0, self.lenOriginal - 1).countToOffset(runeOffset.Count)
    (
      RopeChunk(
        data: self.data,
        len: index,
        dataOriginal: self.dataOriginal,
        lenOriginal: indexOriginal,
        external: self.external,
        point: self.point,
      ),
      RopeChunk(
        data: cast[ptr UncheckedArray[char]](self.data[index].addr),
        len: self.len - index,
        dataOriginal: cast[ptr UncheckedArray[char]](self.dataOriginal[indexOriginal].addr),
        lenOriginal: self.lenOriginal - indexOriginal,
        external: self.external,
        point: point(self.point.row, self.point.column + index.uint32),
      ),
    )

proc split*(self: StyledChunk, index: int): tuple[prefix: StyledChunk, suffix: StyledChunk] =
  let (prefix, suffix) = self.chunk.split(index)
  (
    StyledChunk(chunk: prefix, color: self.color, fontStyle: self.fontStyle, drawWhitespace: self.drawWhitespace, underline: self.underline, fontScale: self.fontScale),
    StyledChunk(chunk: suffix, color: self.color, fontStyle: self.fontStyle, drawWhitespace: self.drawWhitespace, underline: self.underline, fontScale: self.fontScale),
  )

proc `[]`*(self: StyledChunk, r: Range[int]): StyledChunk =
  StyledChunk(chunk: self.chunk[r], color: self.color, fontStyle: self.fontStyle, drawWhitespace: self.drawWhitespace, underline: self.underline, fontScale: self.fontScale)

proc init*(_: typedesc[ChunkIterator], rope {.byref.}: Rope): ChunkIterator =
  result.rope = rope.clone()
  result.cursor = rope.tree.initCursor((Point, int))

proc chunkIter*(rope {.byref.}: Rope): ChunkIterator =
  result.rope = rope.clone()
  result.cursor = rope.tree.initCursor((Point, int))

proc seek*(self: var ChunkIterator, point: Point) =
  assert point >= self.cursor.startPos[0]
  # debugEcho &"ChunkIterator.seek {self.cursor.startPos[0]} -> {point}"
  discard self.cursor.seekForward(point, Bias.Right, ())
  self.point = point
  let localPointOffset = (point - self.cursor.startPos[0]).toPoint
  if self.cursor.item.getSome(item):
    let localOffset = item[].pointToOffset(localPointOffset)
    self.localOffset = localOffset
  else:
    self.localOffset = self.rope.pointToOffset(point) - self.cursor.startPos[1]
  assert self.localOffset >= 0

proc seekLine*(self: var ChunkIterator, line: int) =
  self.seek(point(line, 0))

func next*(self: var ChunkIterator): Option[RopeChunk] =
  while true:
    if self.cursor.atEnd:
      if not self.returnedLastChunk:
        self.returnedLastChunk = true
        return RopeChunk(data: nil, len: 0, point: self.point).some
      return

    if self.cursor.item.isNone or self.localOffset >= self.cursor.item.get.chars.len:
      self.cursor.next(())
      self.localOffset = 0

    if self.cursor.item.isSome and self.cursor.startPos[1] < self.rope.summary.bytes:
      let chunk: ptr Chunk = self.cursor.item.get
      while self.localOffset < chunk.chars.len and chunk.chars[self.localOffset] == '\n':
        if self.point.column == 0:
          result = RopeChunk(
            data: cast[ptr UncheckedArray[char]](chunk.chars[self.localOffset].addr),
            len: 0,
            dataOriginal: cast[ptr UncheckedArray[char]](chunk.chars[self.localOffset].addr),
            lenOriginal: 0,
            point: self.point,
          ).some
        self.point.row += 1
        self.point.column = 0
        self.localOffset += 1
        assert self.localOffset >= 0

        if result.isSome:
          return

      assert self.localOffset <= chunk.chars.len
      if self.localOffset == chunk.chars.len:
        continue

      var maxEndIndex = self.localOffset
      while maxEndIndex < chunk.chars.len:
        case chunk.chars[maxEndIndex]
        of '\t', '\n', '(', ')', '{', '}', '[', ']':
          inc maxEndIndex
          break
        else:
          inc maxEndIndex

      assert maxEndIndex >= self.localOffset

      let point = self.point

      let sliceRange = self.localOffset...min(self.cursor.endPos[1] - self.cursor.startPos[1], maxEndIndex)
      self.localOffset = sliceRange.b
      assert self.localOffset >= 0
      self.point.column += sliceRange.len.uint32

      assert sliceRange.a in 0..chunk.chars.len
      assert sliceRange.b in 0..chunk.chars.len
      assert sliceRange.len >= 0
      if sliceRange.len > 0:
        result = RopeChunk(
          data: cast[ptr UncheckedArray[char]](chunk.chars[sliceRange.a].addr),
          len: sliceRange.len,
          dataOriginal: cast[ptr UncheckedArray[char]](chunk.chars[sliceRange.a].addr),
          lenOriginal: sliceRange.len,
          point: point,
        ).some
        return

iterator ropeChunks*(rope: Rope, state: var RopeChunksState): RopeChunk =
  var cursor = rope.tree.initCursor((Point, int))
  var chunkOriginal = RopeChunk()
  var chunk = RopeChunk()

  # Handle empty rope case
  if rope.len == 0:
    yield chunk

  while true:
    if state.seekPoint.getSome(point):
      if point < chunk.point:
        cursor.resetCursor()
      discard cursor.seekForward(point, Bias.Right, ())
    else:
      cursor.next()

    if cursor.item.isNone:
      yield RopeChunk(data: nil, len: 0, point: cursor.startPos[0])
      break

    let inputChunk: ptr Chunk = cursor.item.get
    chunkOriginal = RopeChunk(
      data: cast[ptr UncheckedArray[char]](inputChunk.chars[0].addr),
      len: inputChunk.chars.len,
      dataOriginal: cast[ptr UncheckedArray[char]](inputChunk.chars[0].addr),
      lenOriginal: inputChunk.chars.len,
      point: cursor.startPos[0],
    )
    chunk = chunkOriginal

    var i = 0
    var start = 0

    template updateChunk(nextChunk: RopeChunk, nextI: int, nextPointState: Point): untyped =
      chunk = nextChunk
      chunk.point = nextPointState
      i = nextI
      start = i
      state.nextPoint = nextPointState

    template yieldChunk(c: RopeChunk, nextChunk: RopeChunk, nextI: int): untyped =
      let c2 = nextChunk
      updateChunk(c2, nextI, c2.point)
      yield c
      continue

    if state.seekPoint.getSome(point):
      assert point >= cursor.startPos[0]
      assert point <= cursor.endPos[0]
      let localOffset = inputChunk[].pointToOffset(point - cursor.startPos[0])
      updateChunk chunkOriginal.split(localOffset)[1], localOffset, point
      state.seekPoint = Point.none

    # Iterate the chunk to find and split at \t and \n
    while i < inputChunk.chars.len:
      # Handle seeking
      if state.seekPoint.getSome(point):
        if point >= cursor.startPos[0] and point < cursor.endPos[0]:
          # Seek forward but in same chunk
          let localOffset = inputChunk[].pointToOffset(point - cursor.startPos[0])
          updateChunk chunkOriginal.split(localOffset)[1], localOffset, point
          state.seekPoint = Point.none

        else:
          # seek after current chunk, handled by outside loop
          break

      # Handle current char
      let c = inputChunk.chars[i]
      if c in {'\t', '(', ')', '{', '}', '[', ']'}:
        if i > start:
          let (prefix, suffix) = chunk.split(i - start)
          yieldChunk prefix, suffix, i
        else:
          let (tab, suffix) = chunk.split(1)
          yieldChunk tab, suffix, i + 1
      elif c == '\n':
        let (prefix, suffix) = chunk.split(i - start)
        var (_, suffix2) = suffix.split(1)
        suffix2.point += point(1, 0)
        yieldChunk prefix, suffix2, i + 1
      else:
        inc i

    if state.seekPoint.isSome:
      continue

    # Yield last non-empty chunk or empty chunk for empty line
    if chunk.len > 0 or chunk.point.column == 0:
      state.nextPoint = chunk.endPoint
      yield chunk

iterator ropeChunks*(rope: Rope): RopeChunk =
  var state = RopeChunksState()
  for chunk in ropeChunks(rope, state):
    yield chunk

iterator ropeChunksC*(rope: Rope, state: var RopeChunksState): RopeChunk {.closure.} =
  for chunk in ropeChunks(rope, state):
    yield chunk

proc init*(_: typedesc[ChunkIterator2], rope: sink Rope): ChunkIterator2 =
  result.rope = rope
  result.iter = ropeChunksC

proc seek*(self: var ChunkIterator2, point: Point) =
  self.state.seekPoint = point.some

proc next*(self: var ChunkIterator2): Option[RopeChunk] =
  if self.done:
    return RopeChunk.none

  let chunk = self.iter(self.rope, self.state)
  if finished(self.iter):
    self.done = true
    return RopeChunk.none

  return chunk.some

proc init*(_: typedesc[StyledChunkIterator], rope {.byref.}: Rope, highlighter: Option[Highlighter] = Highlighter.none, theme: Theme = nil): StyledChunkIterator =
  result.chunks = ChunkIterator2.init(rope.clone())
  result.defaultColor = color(1, 1, 1)
  result.highlighter = highlighter
  result.theme = theme
  # todo: reuse this arena every frame
  result.arena = initArena(16 * 1024)

  result.errorColor = result.defaultColor
  result.warningColor = result.defaultColor
  result.infoColor = result.defaultColor
  result.hintColor = result.defaultColor

  if theme != nil:
    result.defaultColor = theme.color("editor.foreground", color(1, 1, 1))
    result.errorColor = theme.tokenColor("error", result.defaultColor)
    result.warningColor = theme.tokenColor("warning", result.defaultColor)
    result.infoColor = theme.tokenColor("info", result.defaultColor)
    result.hintColor = theme.tokenColor("hint", result.defaultColor)

    if result.highlighter.isSome and result.highlighter.get.rainbowParens:
      for i in 0..10:
        let c = theme.color("rainbow" & $i, color(0, 0, 0, 0))
        if c == color(0, 0, 0, 0):
          break
        result.parenColors.add c

func point*(self: StyledChunkIterator): Point = self.chunks.state.nextPoint
func point*(self: StyledChunk): Point = self.chunk.point
func endPoint*(self: StyledChunk): Point = self.chunk.endPoint
func len*(self: StyledChunk): int = self.chunk.len
func `$`*(self: StyledChunk): string = &"SC({self.chunk}, {self.color}, {self.fontStyle}, {self.drawWhitespace})"
template toOpenArray*(self: StyledChunk): openArray[char] = self.chunk.toOpenArray

proc nextDiagnostic(self: var StyledChunkIterator) =
  if self.diagnosticIndex < self.diagnosticEndPoints.len:
    let change = if self.diagnosticEndPoints[self.diagnosticIndex].start: 1 else: -1
    case self.diagnosticEndPoints[self.diagnosticIndex].severity
    of lsp_types.DiagnosticSeverity.Error: self.errorDepth += change
    of lsp_types.DiagnosticSeverity.Warning: self.warnDepth += change
    of lsp_types.DiagnosticSeverity.Information: self.infoDepth += change
    of lsp_types.DiagnosticSeverity.Hint: self.hintDepth += change
    inc self.diagnosticIndex

proc seek*(self: var StyledChunkIterator, point: Point) =
  self.chunks.seek(point)
  self.localOffset = 0 # todo: does this need to be != 0?
  self.highlights.setLen(0)
  self.highlightsIndex = -1
  self.chunk = RopeChunk.none
  while self.diagnosticIndex < self.diagnosticEndPoints.len and point >= self.diagnosticEndPoints[self.diagnosticIndex].point:
    self.nextDiagnostic()

proc seekLine*(self: var StyledChunkIterator, line: int) =
  self.seek(point(line, 0))

func contentString(self: var StyledChunkIterator, selection: Range[Point], byteRange: Range[int], maxLen: int): string =
  let currentChunk {.cursor.} = self.chunk.get
  if selection.a >= currentChunk.point and selection.b <= currentChunk.endPoint:
    let startIndex = selection.a.column - currentChunk.point.column
    let endIndex = selection.b.column - currentChunk.point.column
    return $currentChunk[startIndex.int...endIndex.int]
  else:
    result = newStringOfCap(min(selection.b.column.int - selection.a.column.int, maxLen))
    for slice in self.chunks.rope.iterateChunks(byteRange):
      for c in slice.chars:
        result.add c
        if result.len == maxLen:
          return

proc addHighlight(highlights: var seq[Highlight], nextHighlight: sink Highlight) =
  if highlights.len > 0:
    assert highlights[^1].range.a <= nextHighlight.range.a

    if highlights[^1].range == nextHighlight.range.a...nextHighlight.range.b:
      if nextHighlight.priority > highlights[^1].priority:
        discard highlights.pop()
        highlights.add nextHighlight
      else:
        # Lower priority, ignore
        discard

    else:
      highlights.add nextHighlight

  elif highlights.len == 0 or nextHighlight != highlights[^1]:
    highlights.add nextHighlight

var regexes = initTable[string, Regex]()

proc depth(n: TSNode): int =
  var n = n
  while not n.parent.isNull:
    inc result
    n = n.parent

proc next*(self: var StyledChunkIterator): Option[StyledChunk] =
  var regexes = ({.gcsafe.}: regexes.addr)

  if self.atEnd:
    return

  # Max length of a node used for checking predicates like #match?
  # Nodes longer than that will not be highlighted correctly, but those should be very rare
  # and since it's just syntax highlighting this is not super critical,
  # and this way we avoid bad performance for some these cases.
  const maxPredicateCheckLen = 128

  # todo: escapes in nim strings might cause overlapping captures
  if self.chunk.isNone or self.localOffset >= self.chunk.get.len:
    self.chunk = self.chunks.next()
    self.localOffset = 0
    self.highlightsIndex = -1
    self.highlights.setLen(0)
    if self.chunk.isNone:
      self.atEnd = true
      return

    let currentChunk = self.chunk.get
    if self.highlighter.isSome:
      if self.highlighter.get.rainbowParens and currentChunk.toOpenArray.len == 1 and currentChunk.toOpenArray[0] in {'(', ')', '{', '}', '[', ']'} and self.parenColors.len > 0:
        let n = self.highlighter.get.tree.root.descendantForRange((currentChunk.point...currentChunk.point).tsRange)
        if n != self.currentNode:
          self.depthOffset = 0
        else:
          if currentChunk.toOpenArray[0] in {')', '}', ']'}:
            dec self.depthOffset
            self.depthOffset = max(self.depthOffset, 0)
        let depth = n.depth + self.depthOffset
        let colorIndex = depth mod self.parenColors.len
        let color = self.parenColors[colorIndex]
        let r = currentChunk.point...point(currentChunk.point.row, currentChunk.point.column + 1)
        var nextHighlight: Highlight = (r, color, {Bold}, 1.0, 100)
        self.highlights.setLen(0)
        self.highlights.add(nextHighlight.ensureMove)
        self.currentNode = n
        if currentChunk.toOpenArray[0] in {'(', '{', '['}:
          inc self.depthOffset

      else:
        let point = currentChunk.point
        let endPoint = currentChunk.endPoint
        let range = tsRange(tsPoint(point.row.int, point.column.int), tsPoint(endPoint.row.int, endPoint.column.int))
        self.arena.restoreCheckpoint(0)

        var requiresSort = false
        for match in self.highlighter.get.query.matches(self.highlighter.get.tree.root, range, self.arena):
          let predicates = self.highlighter.get.query.predicatesForPattern(match.pattern, self.arena)
          for capture in match.captures:
            let node = capture.node
            # let byteRange = node.startByte...node.endByte
            let nodeRange = node.startPoint.toCursor.toPoint...node.endPoint.toCursor.toPoint
            if nodeRange.b <= currentChunk.point or nodeRange.a >= currentChunk.endPoint:
              continue

            var matches = true
            if nodeRange.a.row !=  nodeRange.b.row:
              matches = false

            for predicate in predicates:
              if not matches:
                break

              for operand in predicate.operands:
                if operand.name != capture.name:
                  matches = false
                  break

                case predicate.operator
                # of "match?":
                #   if not regexes[].contains(operand.`type`):
                #     try:
                #       regexes[][operand.`type`] = re(operand.`type`)
                #     except RegexError:
                #       matches = false
                #       break
                #   let regex {.cursor.} = regexes[][operand.`type`]

                #   let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                #   if nodeText.matchLen(regex, 0) != nodeText.len:
                #     matches = false
                #     break

                # of "not-match?":
                #   if not regexes[].contains(operand.`type`):
                #     try:
                #       regexes[][operand.`type`] = re(operand.`type`)
                #     except RegexError:
                #       matches = false
                #       break
                #   let regex {.cursor.} = regexes[][operand.`type`]

                #   let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                #   if nodeText.matchLen(regex, 0) == nodeText.len:
                #     matches = false
                #     break

                # of "eq?":
                #   # @todo: second arg can be capture aswell
                #   let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                #   if nodeText != operand.`type`:
                #     matches = false
                #     break

                # of "not-eq?":
                #   # @todo: second arg can be capture aswell
                #   let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                #   if nodeText == operand.`type`:
                #     matches = false
                #     break

                # of "any-of?":
                #   # todo
                #   log(lvlError, fmt"Unknown predicate '{predicate.name}'")

                else:
                  discard

            if not matches:
              continue

            var nodeRangeClamped = nodeRange
            if nodeRangeClamped.a.row < currentChunk.point.row:
              nodeRangeClamped.a.row = currentChunk.point.row
              nodeRangeClamped.a.column = 0
            if nodeRangeClamped.b.row > currentChunk.point.row:
              nodeRangeClamped.b.row = currentChunk.point.row
              nodeRangeClamped.b.column = uint32.high

            let color = self.theme.tokenColor(capture.name, self.defaultColor)
            let fontStyle = self.theme.tokenFontStyle(capture.name)
            let fontScale = self.theme.tokenFontScale(capture.name)
            var nextHighlight: Highlight = (nodeRangeClamped, color, fontStyle, fontScale, match.pattern)
            if self.highlights.len > 0 and nextHighlight.range.a < self.highlights[^1].range.a:
              requiresSort = true
              self.highlights.add(nextHighlight.ensureMove)
            else:
              self.highlights.addHighlight(nextHighlight.ensureMove)

        if requiresSort:
          var highlights = self.highlights
          highlights.sort(proc(a, b: Highlight): int = cmp(a.range.a, b.range.a))
          self.highlights.setLen(0)
          for nextHighlight in highlights.mitems:
            self.highlights.addHighlight(nextHighlight)

  assert self.chunk.isSome
  var currentChunk = self.chunk.get
  if currentChunk.len == 0:
    return StyledChunk(chunk: currentChunk).some

  assert currentChunk.data != nil
  let startOffset = self.localOffset
  let currentPoint = currentChunk.point + Point(column: self.localOffset.uint32)

  while self.diagnosticIndex < self.diagnosticEndPoints.len and currentPoint >= self.diagnosticEndPoints[self.diagnosticIndex].point:
    self.nextDiagnostic()

  let nextDiagnosticEndPoint = if self.diagnosticIndex < self.diagnosticEndPoints.len:
    self.diagnosticEndPoints[self.diagnosticIndex].point
  else:
    Point.high

  let underline = if self.errorDepth > 0:
    StyledChunkUnderline(color: self.errorColor).some
  elif self.warnDepth > 0:
    StyledChunkUnderline(color: self.warningColor).some
  elif self.infoDepth > 0:
    StyledChunkUnderline(color: self.infoColor).some
  elif self.hintDepth > 0:
    StyledChunkUnderline(color: self.hintColor).some
  else:
    StyledChunkUnderline.none

  assert nextDiagnosticEndPoint >= currentChunk.point
  let maxEndPoint = min(currentChunk.endPoint, nextDiagnosticEndPoint)
  let maxLocalOffset = min(currentChunk.len, maxEndPoint.column.int - currentChunk.point.column.int)

  if self.highlights.len > 0:
    assert currentPoint.row == self.highlights[0].range.a.row
    while self.highlightsIndex + 1 < self.highlights.len:
      let nextHighlight {.cursor.} = self.highlights[self.highlightsIndex + 1]
      assert nextHighlight.range.a.row == currentChunk.point.row
      assert nextHighlight.range.a.row == nextHighlight.range.b.row
      if currentPoint < nextHighlight.range.a:
        self.localOffset = min(maxLocalOffset, nextHighlight.range.a.column.int - currentChunk.point.column.int)
        assert self.localOffset >= 0
        currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
        currentChunk.len = self.localOffset - startOffset
        currentChunk.dataOriginal = cast[ptr UncheckedArray[char]](currentChunk.dataOriginal[startOffset].addr)
        currentChunk.lenOriginal = self.localOffset - startOffset
        currentChunk.point.column += startOffset.uint32
        return StyledChunk(chunk: currentChunk, underline: underline, color: self.defaultColor).some
      elif currentPoint < nextHighlight.range.b:
        self.localOffset = min(maxLocalOffset, nextHighlight.range.b.column.int - currentChunk.point.column.int)
        assert self.localOffset >= 0
        self.highlightsIndex = self.highlightsIndex + 1
        currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
        currentChunk.len = self.localOffset - startOffset
        currentChunk.dataOriginal = cast[ptr UncheckedArray[char]](currentChunk.dataOriginal[startOffset].addr)
        currentChunk.lenOriginal = self.localOffset - startOffset
        currentChunk.point.column += startOffset.uint32
        return StyledChunk(chunk: currentChunk, color: nextHighlight.color, fontStyle: nextHighlight.fontStyle, fontScale: nextHighlight.fontScale, underline: underline).some
      else:
        self.highlightsIndex.inc

  self.localOffset = maxLocalOffset
  assert self.localOffset >= 0
  currentChunk.data = cast[ptr UncheckedArray[char]](currentChunk.data[startOffset].addr)
  currentChunk.len = self.localOffset - startOffset
  currentChunk.dataOriginal = cast[ptr UncheckedArray[char]](currentChunk.dataOriginal[startOffset].addr)
  currentChunk.lenOriginal = self.localOffset - startOffset
  currentChunk.point.column += startOffset.uint32
  return StyledChunk(chunk: currentChunk, underline: underline, color: self.defaultColor).some

iterator chunks*[T](iter: var T): typeof(iter.next.get) =
  while iter.next().getSome(chunk):
    yield chunk

iterator styledChunks*(iter: var ChunkIterator): StyledChunk =
  for chunk in iter.rope.ropeChunks:
    yield StyledChunk(chunk: chunk)

iterator styledChunks*(iter: var StyledChunkIterator): StyledChunk =
  while iter.next().getSome(chunk):
    yield chunk

iterator styledChunks*[T](iter: var T): StyledChunk =
  for chunk in chunks(iter):
    var c = chunk.styledChunk
    c.chunk.point = chunk.outputPoint.Point
    yield c
