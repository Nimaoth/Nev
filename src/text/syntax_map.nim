import std/[options, strformat, tables, algorithm, os, sugar]
import nimsumtree/[rope, sumtree, buffer, clock]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil
import misc/[custom_async, custom_unicode, util, regex, timer, rope_utils, arena, array_view, array_table, event, array_set]
import text/diff, text/[custom_treesitter, treesitter_type_conv]
from language/lsp_types import nil
import theme
import chroma
import malebolgia

{.push warning[Deprecated]:off.}
import std/[threadpool]
{.pop.}

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
  SyntaxLayer* = object
    language*: string
    tree*: TSTree
    ranges*: seq[TSRange]
    depth*: int
    highlightQuery*: TSQuery
    injectionQuery*: TSQuery

  SyntaxLayerRef* = object
    index*: int
    depth*: int
    bytes*: int
    lines*: Point
    startByte*: int
    endByte*: int

  SyntaxLayerRefSummary* = object
    index*: int
    depth: int
    bytes*: int
    lines*: Point

proc `=copy`*(a: var SyntaxLayer, b: SyntaxLayer) =
  if a.addr == b.addr:
    return
  a.language = b.language
  a.ranges = b.ranges
  a.depth = b.depth
  a.highlightQuery = b.highlightQuery
  a.injectionQuery = b.injectionQuery
  if not a.tree.isNil:
    a.tree.delete()
  if not b.tree.isNil:
    a.tree = b.tree.clone()
  else:
    a.tree = TSTree()

proc `=destroy`*(layer: SyntaxLayer) {.raises: [].} =
  {.gcsafe.}:
    `=destroy`(layer.language)
    `=destroy`(layer.ranges)
  if not layer.tree.isNil:
    layer.tree.delete()

func clone*(self: SyntaxLayerRef): SyntaxLayerRef = self

func summary*(self: SyntaxLayerRef): SyntaxLayerRefSummary =
  SyntaxLayerRefSummary(index: self.index, depth: self.depth, bytes: self.bytes, lines: self.lines)

func fromSummary*[C](_: typedesc[SyntaxLayerRefSummary], s: SyntaxLayerRefSummary, cx: C): SyntaxLayerRefSummary = s

func addSummary*[C](self: var SyntaxLayerRefSummary, b: SyntaxLayerRefSummary, cx: C) =
  self.bytes += b.bytes
  self.lines += b.lines
  self.index = max(self.index, b.index)
  self.depth = max(self.depth, b.depth)

type
  SyntaxMapSnapshot* = object
    rope*: Rope
    layers*: seq[SyntaxLayer]
    layerIndex*: SumTree[SyntaxLayerRef]

  LayerIterator* = object
    layers: seq[tuple[cursor: sumtree.Cursor[SyntaxLayerRef, SyntaxLayerRefSummary], start: int]]

  Depth* = distinct int

proc cmp*[C](a: Depth, b: SyntaxLayerRefSummary, cx: C): int {.inline.} = cmp(a.int, b.depth)
proc cmp*[C](a: int, b: SyntaxLayerRefSummary, cx: C): int {.inline.} = cmp(a, b.bytes)

proc `$`*(self: SyntaxMapSnapshot): string =
  if self.rope.tree.isNil or self.layerIndex.isNil:
    return "SyntaxMapSnapshot(nil)"

  result = &"SyntaxMapSnapshot(rope.len={self.rope.len}, layers={self.layers.len})\n"
  # for i, layer in self.layers:
  #   let rangeStr = if layer.ranges.len == 0:
  #     "[]"
  #   elif layer.ranges.len == 1:
  #     let r = layer.ranges[0]
  #     &"[{r.first.row}:{r.first.column}-{r.last.row}:{r.last.column} bytes={r.startByte}..{r.endByte}]"
  #   else:
  #     var s = "["
  #     for j, r in layer.ranges:
  #       if j > 0: s.add ", "
  #       s.add &"{r.first.row}:{r.first.column}-{r.last.row}:{r.last.column} bytes={r.startByte}..{r.endByte}"
  #     s.add "]"
  #     s
  #   let langId = layer.language
  #   let treeStr = if layer.tree.isNil: "nil" else: "ok"
  #   let hqStr = if layer.highlightQuery.isNil: "nil" else: "ok"
  #   let iqStr = if layer.injectionQuery.isNil: "nil" else: "ok"
  #   result.add &"  [{i}] depth={layer.depth} lang={langId} tree={treeStr} hq={hqStr} iq={iqStr} ranges={rangeStr}\n"

  # var cursor = self.layerIndex.initCursor(SyntaxLayerRefSummary)
  # cursor.next()
  # var i = 0
  # while cursor.item.getSome(item):
  #   let layer {.cursor.} = self.layers[item.index]
  #   result.add &"  [{i}] layer={item.index} depth={item.depth} lang={layer.language} bytes={item.bytes} lines={item.lines}\n"
  #   cursor.next()
  #   inc i

proc layerIterator(self {.byref.}: SyntaxMapSnapshot): LayerIterator =
  let maxDepth = self.layerIndex.summary.depth
  var layers = collect:
    for i in 0..maxDepth:
      # important: make a local variable for the cursor first, otherwise we access invalid memory because initCursor doesn't initialize the
      # result and collect doesn't either
      var cursor = self.layerIndex.initCursor(SyntaxLayerRefSummary)
      (cursor: cursor, start: i * self.rope.len)
  for i, layer in layers.mpairs:
    discard layer.cursor.seek((i - 1).Depth, Bias.Right, ())
  return LayerIterator(layers: layers)

proc seek(self: var LayerIterator, offset: int) =
  for i, layer in self.layers.mpairs:
    discard layer.cursor.seek(layer.start + offset, Bias.Right, ())

proc layersOverlapping*(self: var LayerIterator, range: Range[int]): seq[int] =
  for layer in self.layers.mitems:
    discard layer.cursor.seekForward(layer.start + range.a, Bias.Right, ())
    if layer.cursor.item.getSome(item) and (item.depth == 0 or item.index > 0):
      result.add item.index
    while layer.start + range.b > layer.cursor.endPos.bytes and not layer.cursor.atEnd:
      layer.cursor.next()
      if layer.cursor.item.getSome(item) and (item.depth == 0 or item.index > 0):
        result.add item.index

type
  SyntaxMap* = ref object
    language*: TSLanguage
    highlightQuery*: TSQuery
    injectionQuery*: TSQuery
    currentContentFailedToParse*: bool
    isParsingAsync*: bool
    changes*: seq[tuple[edit: TSInputEdit, rope: Rope]]
    changesAsync*: seq[tuple[edit: TSInputEdit, rope: Rope]]
    onParsed*: Event[void]
    currentSnapshot: SyntaxMapSnapshot
    maxInjectionDepth*: int = 3
    loadInjectionLanguage*: proc(languageName: string) {.gcsafe, raises: [].}

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
    snapshot*: ptr SyntaxMapSnapshot
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
    regexCache: ArrayTable[cstring, Regex]
    layerIterator: LayerIterator
    treeCursor: Option[TSTreeCursor]

  InjectionJob = object
    languageName: string
    ranges: seq[TSRange]

proc reparse*(self: SyntaxMap)

func high*(_: typedesc[Point]): Point = Point(row: uint32.high, column: uint32.high)

proc newSyntaxMap*(): SyntaxMap =
  SyntaxMap()

proc buildLayerIndex*(layers: openArray[SyntaxLayer], text: Rope): SumTree[SyntaxLayerRef] =
  result = SumTree[SyntaxLayerRef].new()
  if layers.len == 0:
    return

  template ensure(cond: untyped): untyped =
    if not cond:
      echo astToStr(cond), ": Failed"
      echo text.len, ", ", text.endPoint
      for i, l in layers:
        echo "  layer ", i, ": ", l.ranges
      writeStackTrace()

  # echo &"buildLayerIndex {layers.len}"
  var layerStartByte = 0
  var lastLayerDepth = 0
  var lastPoint = point(0, 0)
  var lastByte = 0
  for i, layer in layers:
    # echo &"  [{i}] layerStart={layerStartByte} lastDepth={lastLayerDepth} last={lastPoint} {lastByte} layer={layer}"
    if layer.depth > lastLayerDepth:
      if lastByte < text.len:
        ensure text.endPoint >= lastPoint
        result.add(SyntaxLayerRef(
          index: 0,
          depth: lastLayerDepth,
          bytes: text.len - lastByte,
          lines: max(text.endPoint, lastPoint) - lastPoint,
        ), ())

      lastLayerDepth = layer.depth
      layerStartByte = lastByte
      lastPoint = point(0, 0)
      lastByte = 0

    let startByte = if layer.ranges.len > 0: layer.ranges[0].startByte else: 0
    let endByte = if layer.ranges.len > 0: layer.ranges[^1].endByte else: 0
    let startPoint = if layer.ranges.len > 0: layer.ranges[0].first.toPoint else: point(0, 0)
    let endPoint = if layer.ranges.len > 0: layer.ranges[^1].last.toPoint else: point(0, 0)
    if startByte > lastByte:
      ensure startPoint >= lastPoint
      ensure endPoint >= startPoint
      result.add(SyntaxLayerRef(
        index: 0,
        depth: layer.depth,
        bytes: startByte - lastByte,
        lines: max(startPoint, lastPoint) - lastPoint,
      ), ())
      lastByte = startByte
      lastPoint = startPoint

    ensure endPoint >= startPoint
    result.add(SyntaxLayerRef(
      index: i,
      depth: layer.depth,
      bytes: endByte - startByte,
      lines: max(endPoint, startPoint) - startPoint,
    ), ())
    lastByte = endByte
    lastPoint = endPoint

  if lastByte < text.len:
    ensure text.endPoint >= lastPoint
    result.add(SyntaxLayerRef(
      index: 0,
      depth: lastLayerDepth,
      bytes: text.len - lastByte,
      lines: max(text.endPoint, lastPoint) - lastPoint,
    ), ())

proc layersOverlapping*(self: SyntaxMapSnapshot, range: Range[int]): seq[int] =
  # todo: seek to beginning of each depth, then to byte index to find overlaps more efficiently
  var cursor = self.layerIndex.initCursor(SyntaxLayerRefSummary)
  cursor.next()
  var layerStart = 0
  var lastLayerDepth = 0
  while cursor.item.getSome(item):
    if item.depth > lastLayerDepth:
      layerStart = cursor.startPos.bytes
      lastLayerDepth = item.depth
    let itemRange = (cursor.startPos.bytes - layerStart)...(cursor.endPos.bytes - layerStart)
    if item.depth > 0 and item.index == 0:
      cursor.next()
      continue
    if range.a <= itemRange.b and range.b >= itemRange.a:
      result.add item.index
    cursor.next()

proc treesOverlapping*(self: SyntaxMapSnapshot, range: Range[int]): seq[TSTree] =
  for layer in self.layersOverlapping(range):
    result.add self.layers[layer].tree

proc clear*(self: SyntaxMap) =
  self.language = nil
  self.highlightQuery = nil
  self.injectionQuery = nil
  self.currentContentFailedToParse = false
  self.changes.setLen(0)
  self.changesAsync.setLen(0)
  self.currentSnapshot = SyntaxMapSnapshot()

proc resetTree*(self: SyntaxMap, rope: sink Rope) =
  ## Reset the parse state but keep the language and query (for when buffer content changes).
  self.currentContentFailedToParse = false
  self.changes.setLen(0)
  self.changesAsync.setLen(0)
  self.currentSnapshot = SyntaxMapSnapshot(rope: rope)

proc applyEditToRange(r: var TSRange, edit: TSInputEdit) =
  let delta = edit.newEndIndex - edit.oldEndIndex
  let pointDelta = edit.newEndPosition.toPoint - edit.oldEndPosition.toPoint
  if r.endByte <= edit.startIndex:
    discard
  elif r.startByte >= edit.oldEndIndex:
    r.startByte += delta
    r.endByte += delta
    r.first = (r.first.toPoint + pointDelta).tsPoint
    r.last = (r.last.toPoint + pointDelta).tsPoint
  else:
    r.startByte = min(r.startByte, edit.startIndex)
    r.endByte = max(r.startByte, r.endByte + delta)
    r.first = min(r.first.toPoint, edit.startPosition.toPoint).tsPoint
    r.last = max(r.first.toPoint, r.last.toPoint + pointDelta).tsPoint

proc applyEdits*(self: SyntaxMap) =
  for change in self.changes:
    for layer in self.currentSnapshot.layers.mitems:
      if layer.tree.isNotNil:
        discard layer.tree.edit(change.edit)
      for r in layer.ranges.mitems:
        applyEditToRange(r, change.edit)
    self.currentSnapshot.rope = change.rope
  if self.changes.len > 0:
    self.currentSnapshot.layerIndex = buildLayerIndex(self.currentSnapshot.layers, self.currentSnapshot.rope)
  # echo "============ NEW SNAPSHOT FROM INTERPOLATE\n", self.currentSnapshot
  self.changes.setLen(0)

proc addEdit*(self: SyntaxMap, edit: TSInputEdit, rope: Rope) =
  if self.isParsingAsync:
    self.changesAsync.add (edit, rope)
  else:
    self.changes.add (edit, rope)

proc snapshot*(self: SyntaxMap): lent SyntaxMapSnapshot =
  if not self.language.isNil:
    if self.changes.len > 0 or self.currentSnapshot.layers.len == 0:
      self.applyEdits()
      self.reparse()
  result = self.currentSnapshot

proc tsTree*(self: SyntaxMap): TSTree =
  if not self.language.isNil:
    if self.changes.len > 0 or self.currentSnapshot.layers.len == 0:
      self.applyEdits()
      self.reparse()
  let s {.cursor.} = self.currentSnapshot
  if s.layers.len > 0: s.layers[0].tree else: TSTree()

proc setLanguage*(self: SyntaxMap, language: TSLanguage, highlightQuery: TSQuery,
                  injectionQuery: TSQuery, rope: sink Rope) =
  self.language = language
  self.highlightQuery = highlightQuery
  self.injectionQuery = injectionQuery
  self.currentContentFailedToParse = false
  self.currentSnapshot = SyntaxMapSnapshot(rope: rope)
  self.changes.setLen(0)
  self.changesAsync.setLen(0)

proc fullDocRange(rope: Rope): TSRange =
  let endPt = rope.summary.lines
  TSRange(
    first: TSPoint(row: 0, column: 0),
    last: TSPoint(row: endPt.row.int, column: endPt.column.int),
    startByte: 0,
    endByte: rope.len,
  )

proc readNodeText(rope: Rope, node: TSNode): string =
  let startByte = node.startByte
  let endByte = node.endByte
  if endByte <= startByte: return ""
  result = newStringOfCap(endByte - startByte)
  for chunk in rope.iterateChunks(startByte...endByte):
    for c in chunk.chars:
      result.add c

proc clipRangesToParent(ranges: seq[TSRange], parent: seq[TSRange]): seq[TSRange] =
  for r in ranges:
    for p in parent:
      if r.endByte <= p.startByte or r.startByte >= p.endByte:
        continue
      result.add TSRange(
        first: if r.startByte < p.startByte: p.first else: r.first,
        last: if r.endByte > p.endByte: p.last else: r.last,
        startByte: max(r.startByte, p.startByte),
        endByte: min(r.endByte, p.endByte),
      )

proc findExistingLayerTree(self: SyntaxMapSnapshot, language: string,
                            ranges: seq[TSRange]): TSTree =
  for layer in self.layers:
    if layer.language == language and layer.ranges.len > 0 and
        ranges.len > 0 and layer.ranges[0].startByte == ranges[0].startByte:
      return layer.tree
  return TSTree()

proc parseTreesitter(parser: TSParser, oldTree: TSTree, text: sink Rope): TSTree =
  var ropeCursor = text.cursor()
  let newTree = parser.parseCallback(oldTree):
    proc(byteIndex: int, cursor: api.Cursor): (ptr char, int) =
      if byteIndex < ropeCursor.offset:
        ropeCursor.resetCursor()

      assert not ropeCursor.rope.tree.isNil
      ropeCursor.seekForward(byteIndex)
      if ropeCursor.chunk.getSome(chunk):
        let byteIndexRel = byteIndex - ropeCursor.chunkStartPos
        return (chunk.chars[byteIndexRel].addr, chunk.chars.len - byteIndexRel)

      return (nil, 0)

  return newTree

proc collectInjections(
    tree: TSTree,
    query: TSQuery,
    rope: Rope,
    parentRanges: seq[TSRange],
    arena: var Arena,
): seq[InjectionJob] =
  var combinedGroups: Table[string, seq[TSRange]]

  let rootNode = tree.root
  let fullRange = TSRange(
    first: rootNode.startPoint, last: rootNode.endPoint,
    startByte: rootNode.startByte, endByte: rootNode.endByte,
  )

  for match in query.matches(rootNode, fullRange, arena):
    var langName = ""
    var contentRanges: seq[TSRange]
    var isCombined = false

    for capture in match.captures:
      if capture.name == "injection.language":
        langName = readNodeText(rope, capture.node)
      elif capture.name == "injection.content":
        contentRanges.add capture.node.getRange()

    let preds = query.predicatesForPattern(match.pattern, arena)
    for pred in preds:
      if pred.operator == "set!":
        for op in pred.operands:
          if $op.name == "injection.language":
            langName = $op.`type`
          if $op.name == "injection.combined":
            isCombined = true

    if langName.len == 0 or contentRanges.len == 0:
      continue

    let clipped = clipRangesToParent(contentRanges, parentRanges)
    if clipped.len == 0:
      continue

    if isCombined:
      combinedGroups.mgetOrPut(langName, @[]).add clipped
    else:
      for r in clipped:
        result.add InjectionJob(languageName: langName, ranges: @[r])

  for lang, ranges in combinedGroups:
    var merged = ranges
    merged.sort(proc(a, b: TSRange): int = cmp(a.startByte, b.startByte))
    result.add InjectionJob(languageName: lang, ranges: merged)

type ParseArgs = object
  rootLanguage: TSLanguageSnapshot
  oldTree: TSTree
  text: Rope
  res: ptr SyntaxMapSnapshot
  requestedLanguages: ptr seq[string]
  highlightQuery: TSQuery
  injectionQuery: TSQuery

# BFS injection discovery
type LayerJob = object
  language: TSLanguageSnapshot
  tree: TSTree
  ranges: seq[TSRange]
  depth: int
  highlightQuery: TSQuery
  injectionQuery: TSQuery
  requestedLanguage: string

proc parseInjection(text: ptr Rope, inj: ptr InjectionJob, oldSnapshot: SyntaxMapSnapshot, depth: int, parser: TSParser): LayerJob =
  let injLang = getLoadedLanguageSnapshot(inj.languageName)

  if injLang.isNone:
    # echo &"parseTreesitterThreadLog: injection lang='{inj.languageName}' not loaded, requesting load"
    return LayerJob(
      depth: depth + 1,
      ranges: inj.ranges,
      requestedLanguage: inj.languageName,
    )

  # echo &"parseTreesitterThreadLog: parsing injection lang={inj.languageName} ranges={inj.ranges.len}"
  let existingTree = oldSnapshot.findExistingLayerTree(injLang.get.languageId, inj.ranges)
  let oldClone = if existingTree.isNotNil: existingTree.clone() else: TSTree()

  var injTree = TSTree()
  if not parser.setLanguage(injLang.get):
    # echo &"parseTreesitterThreadLog: failed to set injection language {inj.languageName}"
    oldClone.delete()
    return LayerJob(
      depth: depth + 1,
      ranges: inj.ranges,
    )

  parser.setIncludedRanges(inj.ranges)
  injTree = parseTreesitter(parser, oldClone, text[])
  oldClone.delete()
  parser.setIncludedRanges([])

  if injTree.isNil:
    # echo &"parseTreesitterThreadLog: injection parse failed for lang={inj.languageName}"
    return LayerJob(
      depth: depth + 1,
      ranges: inj.ranges,
    )

  var requestedLanguage = ""
  let hq = if "highlights" in injLang.get.queries:
    injLang.get.queries["highlights"].get(nil)
  else:
    requestedLanguage = inj.languageName
    nil
  let iq = if "injections" in injLang.get.queries:
    injLang.get.queries["injections"].get(nil)
  else:
    requestedLanguage = inj.languageName
    nil
  # echo &"parseTreesitterThreadLog: injection parse ok lang={inj.languageName} hq={not hq.isNil} iq={not iq.isNil}"

  return LayerJob(
    language: injLang.get,
    tree: injTree,
    ranges: inj.ranges,
    depth: depth + 1,
    highlightQuery: hq,
    injectionQuery: iq,
    requestedLanguage: requestedLanguage,
  )

proc parseInjections(args: ParseArgs, injections: seq[InjectionJob], outJobs: var seq[LayerJob], oldSnapshot: SyntaxMapSnapshot, depth: int) =
  try:
    var jobs = newSeq[LayerJob](injections.len)
    when false:
      proc parseInjectionHelper(chunkIndex: int, chunkSize: int, text: ptr Rope,
          injections: ptr seq[InjectionJob], oldSnapshot: SyntaxMapSnapshot, depth: int,
          parser: TSParser, jobs: ptr seq[LayerJob]) =
        for i in (chunkIndex * chunkSize)..<min((chunkIndex + 1) * chunkSize, injections[].len):
          jobs[][i] = parseInjection(text, injections[i].addr, oldSnapshot, depth, parser)

      let numChunks = min(injections.len, 10)
      var m = createMaster()
      let chunkSize = (injections.len / numChunks).ceil.int
      assert numChunks * chunkSize >= injections.len
      var parsers = getTsParsers(numChunks)
      m.awaitAll:
        for i in 0..<numChunks:
          m.spawn parseInjectionHelper(i, chunkSize, args.text.addr, injections.addr, oldSnapshot, depth, parsers[i], jobs.addr)
      returnParsers(parsers)
    else:
      withParser parser:
        for i in 0..injections.high:
          jobs[i] = parseInjection(args.text.addr, injections[i].addr, oldSnapshot, depth, parser)

    outJobs.add(jobs.ensureMove)
  except CatchableError:
    discard

proc parseTreesitterThread(args: ParseArgs): bool =
  let oldSnapshot {.cursor.} = args.res[]

  # var t = startTimer()
  # defer:
  #   echo &"parseTreesitterThread took {t.elapsed.ms} ms"

  var rootTree = TSTree()
  withParser parser:
    if not parser.setLanguage(args.rootLanguage):
      return false

    parser.setIncludedRanges([])
    rootTree = parseTreesitter(parser, args.oldTree, args.text)
    if rootTree.isNil:
      return false

  var jobs: seq[LayerJob]
  jobs.add LayerJob(
    language: args.rootLanguage,
    tree: rootTree,
    ranges: @[fullDocRange(args.text)],
    depth: 0,
    highlightQuery: args.highlightQuery,
    injectionQuery: args.injectionQuery,
  )

  block:
    # var t = startTimer()
    # defer:
    #   echo &"processJobs took {t.elapsed.ms} ms"

    var i = 0
    while i < jobs.len:
      let job = jobs[i]
      inc i
      if job.tree.isNil or job.injectionQuery.isNil or job.depth >= 5:
        continue

      var arena = initArena(16 * 1024)
      let injections = collectInjections(job.tree, job.injectionQuery, args.text, job.ranges, arena)
      if injections.len > 0:
        parseInjections(args, injections, jobs, oldSnapshot, job.depth)

  jobs.sort(proc(a, b: LayerJob): int =
    if a.depth != b.depth: cmp(a.depth, b.depth)
    else: cmp(a.ranges[0].startByte, b.ranges[0].startByte))

  var newLayers: seq[SyntaxLayer]
  for job in jobs:
    if job.tree.isNil:
      if job.requestedLanguage != "":
        args.requestedLanguages[].incl(job.requestedLanguage)
      continue
    newLayers.add SyntaxLayer(
      language: job.language.languageId,
      tree: job.tree,
      ranges: job.ranges,
      depth: job.depth,
      highlightQuery: job.highlightQuery,
      injectionQuery: job.injectionQuery,
    )

  let layerIndex = buildLayerIndex(newLayers, args.text)

  var newSnapshot = SyntaxMapSnapshot(
    rope: args.text.clone(),
    layers: newLayers,
    layerIndex: layerIndex,
  )

  # var layers = @[
  #   SyntaxLayer(
  #     language: self.language.languageId,
  #     tree: rootTree.clone(),
  #     depth: 0,
  #     highlightQuery: self.highlightQuery,
  #     injectionQuery: self.injectionQuery,
  #   )
  # ]
  # var layerIndex = SumTree[SyntaxLayerRef].new()
  # layerIndex.add(SyntaxLayerRef(index: 0, depth: 0, bytes: rope.len, lines: rope.endPoint), ())
  # var s = SyntaxMapSnapshot(rope: rope, layers: layers, layerIndex: layerIndex)
  # echo s

  swap(newSnapshot, args.res[])
  return true

proc reparseAsync(self: SyntaxMap) {.async.} =
  self.isParsingAsync = true
  defer:
    self.isParsingAsync = false

  if self.language.isNil:
    return

  # echo &"reparseAsync lang={self.language.languageId} rope.len={self.currentSnapshot.rope.len}"

  if self.changes.len > 0:
    self.applyEdits()
  self.changesAsync.setLen(0)

  while true:
    if self.currentContentFailedToParse:
      return

    let oldLanguage = self.language
    let rope = self.currentSnapshot.rope

    # Parse root layer
    let hasOldRoot = self.currentSnapshot.layers.len > 0 and self.currentSnapshot.layers[0].tree.isNotNil
    # echo &"reparseAsync: parsing root layer lang={self.language.languageId} hasOldTree={hasOldRoot}"
    let oldRootTree: TSTree = if hasOldRoot:
      self.currentSnapshot.layers[0].tree.clone()
    else:
      TSTree()
    var newSnapshot = self.currentSnapshot
    var requestedLanguages: seq[string] = @[]
    let rootFlowVar = threadpool.spawn parseTreesitterThread(ParseArgs(
      rootLanguage: self.language.snapshot,
      oldTree: oldRootTree,
      text: rope,
      res: newSnapshot.addr,
      requestedLanguages: requestedLanguages.addr,
      highlightQuery: self.highlightQuery,
      injectionQuery: self.injectionQuery,
    ))
    while not rootFlowVar.isReady:
      await sleepAsync(1.milliseconds)

    let ok = ^rootFlowVar
    oldRootTree.delete()

    if self.language.isNil:
      return

    if self.loadInjectionLanguage != nil:
      for language in requestedLanguages:
        self.loadInjectionLanguage(language)

    if self.language != oldLanguage:
      # echo &"reparseAsync: language changed during parse, restarting"
      # rootTree.delete()
      self.changes.setLen(0)
      self.changesAsync.setLen(0)
      continue

    if not ok:
      # echo &"reparseAsync: root parse failed, marking as failed"
      self.currentContentFailedToParse = true
      return

    # echo &"reparseAsync: root parse ok, iq={not self.injectionQuery.isNil}"

    self.currentSnapshot = newSnapshot
    # echo "============ NEW SNAPSHOT FROM PARSE\n", self.currentSnapshot
    self.currentContentFailedToParse = false

    if self.changesAsync.len == 0:
      assert self.changes.len == 0
      self.onParsed.invoke()
      return

    self.currentContentFailedToParse = false
    for change in self.changesAsync:
      for layer in self.currentSnapshot.layers.mitems:
        if layer.tree.isNotNil:
          discard layer.tree.edit(change.edit)
        for r in layer.ranges.mitems:
          applyEditToRange(r, change.edit)
      self.currentSnapshot.rope = change.rope
    self.currentSnapshot.layerIndex = buildLayerIndex(self.currentSnapshot.layers, self.currentSnapshot.rope)
    # echo "============ NEW SNAPSHOT FROM INTERPOLATE\n", self.currentSnapshot
    self.changesAsync.setLen(0)
    self.changes.setLen(0)
    self.onParsed.invoke()

proc reparse*(self: SyntaxMap) =
  if not self.isParsingAsync:
    asyncSpawn self.reparseAsync()

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
  if result.highlighter.isSome:
    result.layerIterator = result.highlighter.get.snapshot[].layerIterator
    if result.highlighter.get.snapshot[].layers.len > 0:
      result.treeCursor = initTreeCursor(result.highlighter.get.snapshot[].layers[0].tree.root).some

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
  self.layerIterator.seek(self.chunks.rope.toOffset(point))

proc seekLine*(self: var StyledChunkIterator, line: int) =
  self.seek(point(line, 0))

func contentString(self: var StyledChunkIterator, selection: Range[Point], byteRange: Range[int], maxLen: int): string =
  let currentChunk {.cursor.} = self.chunk.get
  if selection.a >= currentChunk.point and selection.b <= currentChunk.endPoint:
    let startIndex = selection.a.column - currentChunk.point.column
    let endIndex = selection.b.column - currentChunk.point.column
    result = newStringOfCap(endIndex.int - startIndex.int)
    for c in currentChunk.data.toOpenArray(startIndex.int, endIndex.int - 1):
      result.add c
  else:
    result = newStringOfCap(min(selection.b.column.int - selection.a.column.int, maxLen))
    for slice in self.chunks.rope.iterateChunks(byteRange):
      for c in slice.chars:
        result.add c
        if result.len == maxLen:
          return

proc `+`(a, b: Color): Color = color(a.r + b.r, a.g + b.g, a.b + b.b, a.a + b.a)

proc addHighlight(highlights: var seq[Highlight], nextHighlight: sink Highlight, defaultColor: Color) =
  ## Adds the new highlight into highlights, blending and splitting with overlapping highlights
  ## highlights: aaaaabbbbbb cccccdddddd
  ## next:         xxxxxxxxxxxx
  ## result:     aayyyyyyyyyyyycccdddddd

  ## highlights: aaaaabbbbbb cccccdddddd
  ## next:                          xxxxxxxxxxxx
  ## result:                        yyyyxxxxxxxx

  ## highlights: aaaaabbbbbb cccccdddddd
  ## next:                              xxxxxxxxxxxx
  ## result:     aaaaabbbbbb cccccddddddxxxxxxxxxxxx

  proc addSegment(outHighlights: var seq[Highlight], h: sink Highlight) =
    if h.range.a < h.range.b:
      outHighlights.add(h)

  proc blendOverBase(top: Highlight, r: Range[Point], baseColor: Color, baseStyle: set[FontStyle], baseScale: float): Highlight =
    result = top
    result.range = r
    result.fontScale = top.fontScale * baseScale
    result.fontStyle = top.fontStyle + baseStyle
    result.color = top.color * top.color.a + baseColor * (1 - top.color.a)

  if highlights.len > 0 and highlights[^1].range.b <= nextHighlight.range.a:
    highlights.add blendOverBase(nextHighlight, nextHighlight.range, defaultColor, {}, 1.0)
    return

  if nextHighlight.range.a >= nextHighlight.range.b:
    return

  var nextHighlight = nextHighlight
  var merged = newSeqOfCap[Highlight](highlights.len + 4)
  var cursor = nextHighlight.range.a

  for h in highlights.items:
    if h.range.b <= nextHighlight.range.a or h.range.a >= nextHighlight.range.b:
      # Once we pass the insertion range, flush any remaining part of the new highlight.
      if h.range.a >= nextHighlight.range.b and cursor < nextHighlight.range.b:
        merged.addSegment(blendOverBase(nextHighlight, cursor...nextHighlight.range.b, defaultColor, {}, 1.0))
        cursor = nextHighlight.range.b
      merged.addSegment(h)
      continue

    let overlapStart = max(h.range.a, nextHighlight.range.a)
    let overlapEnd = min(h.range.b, nextHighlight.range.b)

    if h.range.a < overlapStart:
      var left = h
      left.range.b = overlapStart
      merged.addSegment(left)

    if cursor < overlapStart:
      merged.addSegment(blendOverBase(nextHighlight, cursor...overlapStart, defaultColor, {}, 1.0))

    if overlapStart < overlapEnd:
      if h.priority > nextHighlight.priority:
        var keep = h
        keep.range = overlapStart...overlapEnd
        merged.addSegment(keep)
      else:
        merged.addSegment(blendOverBase(nextHighlight, overlapStart...overlapEnd, h.color, h.fontStyle, h.fontScale))
      cursor = max(cursor, overlapEnd)

    if h.range.b > overlapEnd:
      var right = h
      right.range.a = overlapEnd
      merged.addSegment(right)

  if cursor < nextHighlight.range.b:
    merged.addSegment(blendOverBase(nextHighlight, cursor...nextHighlight.range.b, defaultColor, {}, 1.0))

  highlights = merged

proc next*(self: var StyledChunkIterator): Option[StyledChunk] =
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
    if self.highlighter.isSome and self.highlighter.get.snapshot.layers.len > 0:
      let h {.cursor.} = self.highlighter.get
      let snap {.cursor.} = h.snapshot[]

      # Rainbow parens: use root layer (index 0)
      let rootTree = snap.layers[0].tree
      if h.rainbowParens and rootTree.isNotNil and currentChunk.toOpenArray.len == 1 and currentChunk.toOpenArray[0] in {'(', ')', '{', '}', '[', ']'} and self.parenColors.len > 0 and self.treeCursor.isSome:
        self.treeCursor.get.seek(currentChunk.point.tsPoint)
        let n = self.treeCursor.get.currentNode
        if n != self.currentNode:
          self.depthOffset = 0
        else:
          if currentChunk.toOpenArray[0] in {')', '}', ']'}:
            dec self.depthOffset
            self.depthOffset = max(self.depthOffset, 0)

        let depth = self.treeCursor.get.currentDepth + self.depthOffset
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

        # Compute byte offset for overlap query
        let chunkStartByte = snap.rope.pointToOffset(point)
        let chunkEndByte = chunkStartByte + currentChunk.len

        var overlapping: seq[int] = self.layerIterator.layersOverlapping(chunkStartByte...chunkEndByte)
        # echo &"highlight chunk {currentChunk}"

        var requiresSort = false
        for layerIdx in overlapping:
          let layer {.cursor.} = snap.layers[layerIdx]
          if layer.tree.isNil or layer.highlightQuery.isNil: continue
          let highlightQuery = layer.highlightQuery

          for match in highlightQuery.matches(layer.tree.root, range, self.arena):
            let predicates = highlightQuery.predicatesForPattern(match.pattern, self.arena)
            for capture in match.captures:
              let node = capture.node
              let byteRange = node.startByte...node.endByte
              let nodeRange = node.startPoint.toCursor.toPoint...node.endPoint.toCursor.toPoint
              if nodeRange.b <= currentChunk.point or nodeRange.a >= currentChunk.endPoint:
                continue

              var matches = true
              if nodeRange.a.row == nodeRange.b.row:
                for predicate in predicates:
                  if not matches:
                    break

                  for operand in predicate.operands:
                    if operand.name != capture.name:
                      matches = false
                      break

                    case predicate.operator
                    of "match?":
                      let cachedRegex = self.regexCache.tryGet(operand.`type`)
                      var regex: Regex
                      if cachedRegex.isSome:
                        regex = cachedRegex.get
                      else:
                        try:
                          regex = re($operand.`type`)
                          self.regexCache[operand.`type`] = regex
                        except RegexError:
                          matches = false
                          break

                      let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                      if nodeText.matchLen(regex, 0) != nodeText.len:
                        matches = false
                        break

                    of "not-match?":
                      let cachedRegex = self.regexCache.tryGet(operand.`type`)
                      var regex: Regex
                      if cachedRegex.isSome:
                        regex = cachedRegex.get
                      else:
                        try:
                          regex = re($operand.`type`)
                          self.regexCache[operand.`type`] = regex
                        except RegexError:
                          matches = false
                          break

                      let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                      if nodeText.matchLen(regex, 0) == nodeText.len:
                        matches = false
                        break

                    of "eq?":
                      # @todo: second arg can be capture aswell
                      let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                      if nodeText.toOpenArray(0, nodeText.high) != operand.`type`.toOpenArray(0, operand.`type`.high):
                        matches = false
                        break

                    of "not-eq?":
                      # @todo: second arg can be capture aswell
                      let nodeText = self.contentString(nodeRange, byteRange, maxPredicateCheckLen)
                      if nodeText.toOpenArray(0, nodeText.high) == operand.`type`.toOpenArray(0, operand.`type`.high):
                        matches = false
                        break

                    # of "any-of?":
                    #   # todo
                    #   discard

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
              # if nodeRangeClamped.b >= currentChunk.endPoint:
              #   nodeRangeClamped.b.column = uint32.high

              let color = self.theme.tokenColor(capture.name, self.defaultColor)
              let fontStyle = self.theme.tokenFontStyle(capture.name)
              let fontScale = self.theme.tokenFontScale(capture.name)
              let priority = match.pattern + layer.depth * 10_000
              var nextHighlight: Highlight = (nodeRangeClamped, color, fontStyle, fontScale, priority)
              self.highlights.addHighlight(nextHighlight.ensureMove, self.defaultColor)

        if requiresSort:
          var highlights = self.highlights
          highlights.sort(proc(a, b: Highlight): int = cmp(a.range.a, b.range.a))
          self.highlights.setLen(0)
          for nextHighlight in highlights.mitems:
            self.highlights.addHighlight(nextHighlight, self.defaultColor)

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
