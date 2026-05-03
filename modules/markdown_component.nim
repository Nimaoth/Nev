#use command_component snippet_component text_editor_component treesitter_component
const currentSourcePath2 = currentSourcePath()
include module_base

# Implementation
when implModule:
  import std/[options]
  import std/[tables, sets, sequtils, algorithm]
  import chroma
  import nimsumtree/[buffer, sumtree, rope]
  import misc/[util, custom_logger, rope_utils, delayed_task, custom_async, arena, array_view, id]
  import misc/[event, render_command]
  import text/[syntax_map, treesitter_types, treesitter_type_conv, custom_treesitter, snippet]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import service, event_service, document_editor, document, decoration_component, treesitter_component
  import text_component, language_component, text_editor_component, command_component, move_component
  import snippet_component, config_component, platform_service, component, config_provider

  {.push warning[Deprecated]:off.}
  import std/[threadpool]
  {.pop.}

  logCategory "decoration-component"

  let MarkdownComponentId = componentGenerateTypeId()

  type MarkdownComponent* = ref object of Component
    updateTask: DelayedTask
    updateDelimitersTask: DelayedTask
    updateHeadersTask: DelayedTask
    documentChangedHandle: Id
    editHandle: Id
    languageChangedHandle: Id
    parsedHandle: Id
    currentLines: HashSet[int]
    isUpdatingDelimiterHiding: bool = false
    updateDelimiterRequestNum: int = 0
    queries: Table[string, Option[TSQuery]]
    headerMarkerRendererId: CustomRendererId
    tableOverlayId: Option[int]
    delimiterOverlayId: Option[int]
    headerOverlayId: Option[int]

  type MarkdownOverlayArgs = object
    syntaxMap: SyntaxMapSnapshot
    fullRange: TSRange
    languageId: string
    currentLines: HashSet[int]
    query: TSQuery

  proc isEnabled(self: MarkdownComponent): bool =
    let editor = self.owner.DocumentEditor
    let config = editor.getConfigComponent().getOr:
      return false
    return config.get("markdown.enabled", true)

  proc query(self: MarkdownComponent, language: string, name: string, text: string): Future[Option[TSQuery]] {.async.} =
    let language = getLoadedLanguage(language)
    if language.isNil:
      return TSQuery.none
    if name in self.queries:
      return self.queries[name]
    let res = await language.query(name, text)
    self.queries[name] = res
    return res

  proc collectDelimiterOverlaysThread(args: MarkdownOverlayArgs): seq[Range[Point]] =
    template checkRes(b: untyped): untyped =
      if not b:
        continue

    proc isDelimiterNode(node: TSNode): bool =
      let nodeType = node.nodeType
      if nodeType.contains("delimiter"):
        return true
      return false

    var arena = initArena(128 * 1024)
    var cursor = args.syntaxMap.layerIndex.initCursor(SyntaxLayerRefSummary)
    cursor.next()
    while cursor.item.getSome(item):
      defer:
        cursor.next()
      if item.depth > 0 and item.index == 0:
        continue
      let layer {.cursor.} = args.syntaxMap.layers[item.index]
      if layer.language != args.languageId:
        continue

      arena.restoreCheckpoint(0)

      for match in args.query.matches(layer.tree.root, args.fullRange, arena):
        for capture in match.captures:
          capture.node.withTreeCursor(c):
            checkRes c.gotoFirstChild()
            var delimiterRanges: seq[Range[Point]] = @[]

            while true:
              let child = c.currentNode
              if child.isDelimiterNode:
                let r = child.getRange.toRange
                if r.a != r.b:
                  delimiterRanges.add(r)
              if not c.gotoNextSibling():
                break

            if delimiterRanges.len == 0:
              continue

            var mergedDelimiterRanges: seq[Range[Point]] = @[]
            for r in delimiterRanges:
              if mergedDelimiterRanges.len == 0:
                mergedDelimiterRanges.add(r)
              elif mergedDelimiterRanges[^1].b == r.a:
                mergedDelimiterRanges[^1].b = r.b
              else:
                mergedDelimiterRanges.add(r)

            if mergedDelimiterRanges.len == 0:
              continue

            let firstDelimiter = mergedDelimiterRanges[0]
            if firstDelimiter.a.row.int in args.currentLines:
              continue
            result.add(firstDelimiter)

            if mergedDelimiterRanges.len >= 2:
              let lastDelimiter = mergedDelimiterRanges[^1]
              if lastDelimiter != firstDelimiter:
                result.add(lastDelimiter)
    result.sort proc(a, b: Range[Point]): int = cmp(a.a, b.a)

  proc getMarkdownComponent*(self: ComponentOwner): Option[MarkdownComponent] {.gcsafe, raises: [].} =
    return self.getComponent(MarkdownComponentId).mapIt(it.MarkdownComponent)

  proc updateTablesAsync(self: MarkdownComponent): Future[void] {.async.} =
    if self.owner == nil or self.tableOverlayId.isNone:
      return
    let editor = self.owner.DocumentEditor
    if editor.currentDocument.isNil:
      return
    let decorations = editor.getDecorationComponent().getOr:
      return
    let treesitter = editor.currentDocument.getTreesitterComponent().getOr:
      return

    if not self.isEnabled:
      if self.tableOverlayId.isSome:
        decorations.clearOverlays(self.tableOverlayId.get)
      return

    let text = editor.currentDocument.getTextComponent().getOr:
      return

    let content = text.content
    let fullRange = (point(0, 0)...content.endPoint).tsRange

    template checkRes(b: untyped): untyped =
      if not b:
        return

    let tableQuery = await self.query("markdown", "markdown_table", "(pipe_table) @table")
    if tableQuery.isNone or self.owner.isNil or editor.isNil or editor.currentDocument.isNil:
      return

    let syntaxMap = treesitter.syntaxMap.snapshot
    if syntaxMap.layerIndex.isNil:
      return

    let edit = editor.getTextEditorComponent().getOr:
      return

    var overlaysToAdd: seq[OverlayDef] = @[]

    var cursor = syntaxMap.layerIndex.initCursor(SyntaxLayerRefSummary)
    cursor.next()
    while cursor.item.getSome(item):
      defer:
        cursor.next()
      if item.depth > 0 and item.index == 0:
        continue
      let layer {.cursor.} = syntaxMap.layers[item.index]
      if layer.language != "markdown":
        continue

      var arena = initArena(16 * 1024)
      for match in tableQuery.get.matches(layer.tree.root, fullRange, arena):
        for capture in match.captures:
          capture.node.withTreeCursor(c):
            var node = c.currentNode
            checkRes c.gotoFirstChild()

            type Cell = object
              node: TSNode
              width: int
              text: string
              range: Range[Point]
              isDelimiter: bool

            var rows: seq[seq[Cell]] = @[]
            var maxWidths: seq[int] = @[]

            while true:
              node = c.currentNode

              proc parseRow(c: var TSTreeCursor, offset: int, isDelimiter: bool): seq[Cell] =
                var cellStartColumn = 0
                if c.gotoFirstChild():
                  defer:
                    discard c.gotoParent()
                  while true:
                    let node = c.currentNode
                    let r = node.getRange.toRange
                    var extraOffset = 0
                    if isDelimiter:
                      let nextChar = content.charAt(r.b)
                      if nextChar == '|':
                        extraOffset = 1
                    if node.isNamed:
                      let displayRange = edit.toDisplayPoint(r.a, Bias.Right)...edit.toDisplayPoint(r.b, Bias.Left)
                      result.add Cell(node: node, width: displayRange.b.column.int - cellStartColumn + offset - extraOffset, text: $content[r], range: r, isDelimiter: isDelimiter)
                    else:
                      cellStartColumn = edit.toDisplayPoint(r.b).column.int
                    if not c.gotoNextSibling():
                      break

              case node.nodeType
              of "pipe_table_header":
                rows.add c.parseRow(0, false)
              of "pipe_table_delimiter_row":
                rows.add c.parseRow(1, true)
              of "pipe_table_row":
                rows.add c.parseRow(0, false)
              else:
                discard

              if not c.gotoNextSibling():
                break

            for column in 0..int.high:
              var maxWidth = -1
              for row in rows:
                if column >= row.len:
                  continue
                maxWidth = max(maxWidth, row[column].width)
              if maxWidth < 0:
                break
              maxWidths.add(maxWidth)

            let endPoint = text.content.endPoint
            for row in rows.mitems:
              for i, cell in row:
                if i >= maxWidths.len or cell.range.b > endPoint:
                  continue
                let overlayWidth = maxWidths[i] - cell.width
                if overlayWidth > 0:
                  let ch = if cell.isDelimiter: "-" else: " "
                  let text = ch.repeat(overlayWidth)
                  overlaysToAdd.add (cell.range.b...cell.range.b, text, "comment", Bias.Right, 0, OverlayRenderLocation.Inline)
    if overlaysToAdd.len > 0:
      decorations.addOverlays(self.tableOverlayId.get, replace = true, overlaysToAdd)

  proc updateCursorLines(self: MarkdownComponent): bool =
    let editor = self.owner.DocumentEditor
    if editor.currentDocument.isNil:
      return false
    let config = editor.getConfigComponent().getOr:
      return false

    let modes = config.get("text.modes", seq[string])
    let disableOnCursorLines = config.get("markdown.disable-on-cursor-lines-modes", seq[string])
    if modes.toHashSet.disjoint(disableOnCursorLines.toHashSet):
      result = self.currentLines.len > 0
      self.currentLines.clear()
      return

    let edit = editor.getTextEditorComponent().getOr:
      return false
    var newCurrentLines = initHashSet[int]()
    for c in edit.selections:
      newCurrentLines.incl c.a.row.int
      newCurrentLines.incl c.b.row.int
    if newCurrentLines != self.currentLines:
      self.currentLines = newCurrentLines
      return true
    return false

  proc updateDelimiterHidingAsync(self: MarkdownComponent): Future[void] {.async.} =
    if self.delimiterOverlayId.isNone:
      return

    inc self.updateDelimiterRequestNum
    if self.isUpdatingDelimiterHiding:
      return
    self.isUpdatingDelimiterHiding = true
    defer:
      self.isUpdatingDelimiterHiding = false

    var lastUpdateDelimiterRequestNum = self.updateDelimiterRequestNum
    let editor = self.owner.DocumentEditor
    if editor.currentDocument.isNil:
      return
    let decorations = editor.getDecorationComponent().getOr:
      return

    if not self.isEnabled:
      if self.delimiterOverlayId.isSome:
        decorations.clearOverlays(self.delimiterOverlayId.get)
      return

    let treesitter = editor.currentDocument.getTreesitterComponent().getOr:
      return

    let text = editor.currentDocument.getTextComponent().getOr:
      return

    let emphQuery = await self.query("markdown_inline", "markdown_emphasis", "[(emphasis) (strong_emphasis) (code_span) (strikethrough)] @emph")
    if emphQuery.isNone or self.owner.isNil or editor.isNil or editor.currentDocument.isNil:
      return

    while true:
      let content = text.content
      let fullRange = (point(0, 0)...content.endPoint).tsRange

      let syntaxMap = treesitter.syntaxMap.snapshot
      if syntaxMap.layerIndex.isNil:
        return

      var overlays: seq[Range[Point]] = @[]
      block:
        let overlaysFlowVar = threadpool.spawn collectDelimiterOverlaysThread(MarkdownOverlayArgs(
          syntaxMap: syntaxMap,
          fullRange: fullRange,
          languageId: "markdown_inline",
          currentLines: self.currentLines,
          query: emphQuery.get,
        ))
        while not overlaysFlowVar.isReady:
          await sleepAsync(1.milliseconds)

        # if syntaxMap.buffer.remoteId != snapshot.buffer.remoteId or syntaxMap.buffer.version != snapshot.buffer.version:
        #   # debugEcho &"dismiss, {self.pendingOperations} new ops"
        #   continue

        overlays = ^overlaysFlowVar

      block:
        let endPoint = text.content.endPoint
        var visibleOverlays = newSeqOfCap[OverlayDef](overlays.len)
        for overlayRange in overlays:
          if overlayRange.a.row.int in self.currentLines or overlayRange.a > endPoint:
            continue
          visibleOverlays.add (overlayRange, "", "comment", Bias.Right, 0, OverlayRenderLocation.Inline)
        decorations.addOverlays(self.delimiterOverlayId.get, replace = true, visibleOverlays)
        asyncSpawn self.updateTablesAsync()

      lastUpdateDelimiterRequestNum = self.updateDelimiterRequestNum
      break

  proc collectHeaderOverlaysThread(args: MarkdownOverlayArgs): seq[Range[Point]] =
    var arena = initArena(128 * 1024)
    var cursor = args.syntaxMap.layerIndex.initCursor(SyntaxLayerRefSummary)
    cursor.next()
    while cursor.item.getSome(item):
      defer:
        cursor.next()
      if item.depth > 0 and item.index == 0:
        continue
      let layer {.cursor.} = args.syntaxMap.layers[item.index]
      if layer.language != args.languageId:
        continue

      arena.restoreCheckpoint(0)

      for match in args.query.matches(layer.tree.root, args.fullRange, arena):
        for capture in match.captures:
          let r = capture.node.getRange.toRange
          if r.a != r.b:
            result.add(r.a...point(r.b.row, r.b.column + 1))

  proc updateHeaderHidingAsync(self: MarkdownComponent): Future[void] {.async.} =
    if self.headerOverlayId.isNone:
      return
    let editor = self.owner.DocumentEditor
    if editor.currentDocument.isNil:
      return
    let decorations = editor.getDecorationComponent().getOr:
      return

    if not self.isEnabled:
      if self.headerOverlayId.isSome:
        decorations.clearOverlays(self.headerOverlayId.get)
      return

    let treesitter = editor.currentDocument.getTreesitterComponent().getOr:
      return

    let text = editor.currentDocument.getTextComponent().getOr:
      return

    let headerQuery = await self.query("markdown", "markdown_header", "[(atx_h1_marker) (atx_h2_marker) (atx_h3_marker) (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)] @marker")
    if headerQuery.isNone or self.owner.isNil or editor.isNil or editor.currentDocument.isNil:
      return

    let content = text.content
    let fullRange = (point(0, 0)...content.endPoint).tsRange

    let syntaxMap = treesitter.syntaxMap.snapshot
    if syntaxMap.layerIndex.isNil:
      return

    var overlays: seq[Range[Point]] = @[]
    let overlaysFlowVar = threadpool.spawn collectHeaderOverlaysThread(MarkdownOverlayArgs(
      syntaxMap: syntaxMap,
      fullRange: fullRange,
      languageId: "markdown",
      currentLines: self.currentLines,
      query: headerQuery.get,
    ))
    while not overlaysFlowVar.isReady:
      await sleepAsync(1.milliseconds)

    overlays = ^overlaysFlowVar

    let endPoint = text.content.endPoint
    var visibleOverlays = newSeqOfCap[OverlayDef](overlays.len)
    for overlayRange in overlays:
      if overlayRange.a.row.int in self.currentLines or overlayRange.a > endPoint:
        continue
      visibleOverlays.add (overlayRange, "", "comment", Bias.Left, self.headerMarkerRendererId.uint64.int, OverlayRenderLocation.Below)
    decorations.addOverlays(self.headerOverlayId.get, replace = true, visibleOverlays)

  proc toggleStyle*(self: MarkdownComponent, nodeType: string, delimiters: openArray[string]) =
    let editor = self.owner.DocumentEditor
    if editor.currentDocument.isNil:
      return
    let moves = editor.currentDocument.getMoveComponent().getOr:
      return
    let text = editor.currentDocument.getTextComponent().getOr:
      return
    let edit = editor.getTextEditorComponent().getOr:
      return
    let treesitter = editor.currentDocument.getTreesitterComponent().getOr:
      return

    let content = text.content
    let syntaxMap = treesitter.syntaxMap.snapshot
    var editSelections: seq[Range[Point]] = @[]
    var oldSelections: seq[Range[Point]] = @[]
    var editTexts: seq[string] = @[]
    var cursorEditStarts: seq[int] = @[]
    var relRanges: seq[Range[Point]] = @[]
    var newSelections: seq[Range[Point]] = @[]

    proc delimitersForNodeType(styleType: string): seq[string] =
      case styleType
      of "strong_emphasis":
        @["**", "__"]
      of "emphasis":
        @["*", "_"]
      of "code_span":
        @["`"]
      of "strikethrough":
        @["~"]
      else:
        @[]

    for sel in edit.selections:
      let normalized = sel.normalized
      var workRange = normalized
      if normalized.a == normalized.b:
        let cursor = normalized.a
        let row = cursor.row.int
        let col = cursor.column.int
        let lineLen = content.lineLen(row)

        var leftText = ""
        if col > 0:
          let leftPoint = point(row, col - 1)
          leftText = text.content(leftPoint...leftPoint, inclusiveEnd = true)

        var rightText = ""
        if col < lineLen:
          rightText = text.content(cursor...cursor, inclusiveEnd = true)

        let leftIsWhitespaceOrEmpty = leftText.len == 0 or leftText[0] in Whitespace
        let rightIsWhitespaceOrEmpty = rightText.len == 0 or rightText[0] in Whitespace
        if not (leftIsWhitespaceOrEmpty and rightIsWhitespaceOrEmpty):
          workRange = moves.applyMove(normalized, "language-word")

      let byteStart = content.toOffset(workRange.a)
      let byteEnd = content.toOffset(workRange.b)

      var styleNode: Option[TSNode]
      var styleNodeType = ""
      for tree in syntaxMap.treesOverlapping(byteStart...byteEnd):
        if styleNode.isSome:
          break
        var node = tree.root.descendantForRange(workRange.tsRange)
        while not node.isNull:
          let currentType = node.nodeType
          if currentType == "emphasis" or currentType == "strong_emphasis" or currentType == "code_span" or currentType == "strikethrough":
            styleNode = node.some
            styleNodeType = currentType
            break
          let p = node.parent
          if p.isNull:
            break
          node = p

      if styleNode.isSome:
        let emNode = styleNode.get
        let nodeRange = emNode.getRange.toRange
        let nodeText = text.content(nodeRange)
        let existingDelims = delimitersForNodeType(styleNodeType)
        if existingDelims.len == 0:
          continue

        var actualDelim = existingDelims[0]
        for d in existingDelims:
          if nodeText.startsWith(d):
            actualDelim = d
            break

        let targetDelim = delimiters[0]
        let dLen = actualDelim.len
        let openStart = nodeRange.a
        let openEnd = point(nodeRange.a.row.int, nodeRange.a.column.int + dLen)
        let closeStart = point(nodeRange.b.row.int, nodeRange.b.column.int - dLen)
        let closeEnd = nodeRange.b

        cursorEditStarts.add(editSelections.len)
        editSelections.add openStart...openEnd
        editSelections.add closeStart...closeEnd
        oldSelections.add openStart...openEnd
        oldSelections.add closeStart...closeEnd

        if styleNodeType == nodeType:
          # Same style: remove delimiters
          relRanges.add(((sel.a - workRange.a).toPoint...(sel.b - workRange.a).toPoint))
          editTexts.add ""
          editTexts.add ""
        else:
          # Different style: convert old style delimiters to target delimiters
          relRanges.add(((sel.a - workRange.a).toPoint...(sel.b - workRange.a).toPoint) + point(0, targetDelim.len))
          editTexts.add targetDelim
          editTexts.add targetDelim

      elif workRange.a == workRange.b:
        # Wrap the word or selection with delimiters
        cursorEditStarts.add(editSelections.len)
        relRanges.add(((sel.a - workRange.a).toPoint...(sel.b - workRange.a).toPoint) + point(0, delimiters[0].len))
        editSelections.add workRange
        oldSelections.add workRange
        editTexts.add delimiters[0] & delimiters[0]

      else:
        # Wrap the word or selection with delimiters
        cursorEditStarts.add(editSelections.len)
        relRanges.add(((sel.a - workRange.a).toPoint...(sel.b - workRange.a).toPoint) + point(0, delimiters[0].len))
        editSelections.add workRange.a...workRange.a
        editSelections.add workRange.b...workRange.b
        oldSelections.add workRange.a...workRange.a
        oldSelections.add workRange.b...workRange.b
        editTexts.add delimiters[0]
        editTexts.add delimiters[0]

    if editSelections.len == 0:
      return

    let newRanges = text.edit(editSelections, oldSelections, editTexts, checkpoint = "insert")
    var tabStopSelections: Selections = @[]
    var tabStopPoints: seq[Point] = @[]
    for i, startIndex in cursorEditStarts:
      let endIndex = if i + 1 < cursorEditStarts.len:
        cursorEditStarts[i + 1]
      else:
        newRanges.len
      newSelections.add(newRanges[startIndex].a + relRanges[i])
      if startIndex + 1 < endIndex:
        let tabStopPoint = newRanges[startIndex + 1].b
        tabStopPoints.add tabStopPoint
        tabStopSelections.add tabStopPoint.toCursor.toSelection
      else:
        let tabStopPoint = newRanges[startIndex].b
        tabStopPoints.add tabStopPoint
        tabStopSelections.add tabStopPoint.toCursor.toSelection

    if newSelections.len > 0:
      edit.selections = newSelections

    if tabStopPoints.len > 0 and editor.getSnippetComponent().getSome(snippetComponent):
      if not editor.currentDocument.requiresLoad:
        let snapshot {.cursor.} = text.buffer.snapshot
        var snippetData = SnippetData(
          currentTabStop: 0,
          highestTabStop: 0,
          tabStops: initTable[int, Selections](),
          tabStopAnchors: initTable[int, seq[(Anchor, Anchor)]](),
        )
        snippetData.tabStops[0] = tabStopSelections
        snippetData.tabStopAnchors[0] = tabStopPoints.mapIt((snapshot.anchorAfter(it), snapshot.anchorBefore(it)))
        snippetComponent.currentSnippetData = snippetData.some

  proc toggleBold*(self: MarkdownComponent) {.async.} =
    self.toggleStyle("strong_emphasis", ["**", "__"])

  proc toggleItalic*(self: MarkdownComponent) {.async.} =
    self.toggleStyle("emphasis", ["*", "_"])

  proc toggleCode*(self: MarkdownComponent) {.async.} =
    self.toggleStyle("code_span", ["`"])

  proc toggleStrikethrough*(self: MarkdownComponent) {.async.} =
    self.toggleStyle("strikethrough", ["~"])

  proc updateTables(self: MarkdownComponent) =
    asyncSpawn self.updateTablesAsync()

  proc handleDocumentChanged(self: MarkdownComponent, old: Document, new: Document) =
    if old != nil:
      if self.editHandle != idNone() and old.getTextComponent().getSome(text):
        text.onEdit.unsubscribe(self.editHandle)
        self.editHandle = idNone()
      if self.languageChangedHandle != idNone() and old.getLanguageComponent().getSome(language):
        language.onLanguageChanged.unsubscribe(self.languageChangedHandle)
        self.languageChangedHandle = idNone()
      if self.parsedHandle != idNone() and old.getTreesitterComponent().getSome(treesitter):
        treesitter.syntaxMap.onParsed.unsubscribe(self.parsedHandle)
        self.parsedHandle = idNone()
    if new.isNil:
      return
    let text = new.getTextComponent().getOr:
      return
    let language = new.getLanguageComponent().getOr:
      return
    let treesitter = new.getTreesitterComponent().getOr:
      return
    self.editHandle = text.onEdit.subscribe proc(args: tuple[oldText: Rope, patch: Patch[Point]]) =
      if self.updateTask.isNotNil:
        self.updateTask.schedule()
      if self.updateDelimitersTask.isNotNil:
        self.updateDelimitersTask.schedule()
      if self.updateHeadersTask.isNotNil:
        self.updateHeadersTask.schedule()
    self.languageChangedHandle = language.onLanguageChanged.subscribe proc(l: LanguageComponent) =
      if self.updateTask.isNotNil:
        self.updateTask.schedule()
      if self.updateDelimitersTask.isNotNil:
        self.updateDelimitersTask.schedule()
      if self.updateHeadersTask.isNotNil:
        self.updateHeadersTask.schedule()
    self.parsedHandle = treesitter.syntaxMap.onParsed.subscribe proc() =
      if self.updateTask.isNotNil:
        self.updateTask.schedule()
      if self.updateDelimitersTask.isNotNil:
        self.updateDelimitersTask.schedule()
      if self.updateHeadersTask.isNotNil:
        self.updateHeadersTask.schedule()
    if self.updateTask.isNotNil:
      self.updateTask.schedule()
    if self.updateDelimitersTask.isNotNil:
      self.updateDelimitersTask.schedule()
    if self.updateHeadersTask.isNotNil:
      self.updateHeadersTask.schedule()

  proc newMarkdownComponent*(editor: DocumentEditor): MarkdownComponent =
    var res = MarkdownComponent(
      typeId: MarkdownComponentId,
    )

    res.deinitializeImpl = proc(self: Component) =
      let self = self.MarkdownComponent
      if editor.getDecorationComponent().getSome(decorations):
        if self.tableOverlayId.isSome:
          decorations.releaseOverlayId(self.tableOverlayId.get)
        if self.delimiterOverlayId.isSome:
          decorations.releaseOverlayId(self.delimiterOverlayId.get)
        if self.headerOverlayId.isSome:
          decorations.releaseOverlayId(self.headerOverlayId.get)

    if editor.getDecorationComponent().getSome(decorations):
      res.tableOverlayId = decorations.allocateOverlayId()
      res.delimiterOverlayId = decorations.allocateOverlayId()
      res.headerOverlayId = decorations.allocateOverlayId()

      let platform = getServices().getService(PlatformService)
      if platform.isSome and platform.get.platform.backend == Backend.Gui:
        res.headerMarkerRendererId = decorations.addCustomRenderer proc(id: int, size: Vec2, localOffset: int, commands: var RenderCommands): Vec2 =
          commands.fillRect(rect(5, -2, size.x - 10, 1), color(0.7, 0.7, 0.7, 0.2))
          return vec2(size.x, 0)

    res.updateTask = startDelayedPaused(1, false):
      res.updateTables()

    res.updateDelimitersTask = startDelayedPaused(1, false):
      asyncSpawn res.updateDelimiterHidingAsync()

    res.updateHeadersTask = startDelayedPaused(1, false):
      asyncSpawn res.updateHeaderHidingAsync()

    if editor.getConfigComponent().getSome(config):
      discard config.config.onConfigChanged.subscribe proc(key: string) =
        if key == "text.modes":
          if res.updateCursorLines():
            asyncSpawn res.updateDelimiterHidingAsync()
            if res.updateHeadersTask.isNotNil:
              res.updateHeadersTask.schedule()
        if key == "" or key == "markdown" or key == "markdown.enabled":
          asyncSpawn res.updateDelimiterHidingAsync()
          if res.updateHeadersTask.isNotNil:
            res.updateHeadersTask.schedule()
          if res.updateTask.isNotNil:
            res.updateTask.schedule()

    if editor.getTextEditorComponent().getSome(edit):
      discard edit.onSelectionsChanged2.subscribe proc(arg: tuple[editor: TextEditorComponent, old: seq[Range[Point]]]) =
        if res.updateCursorLines():
          asyncSpawn res.updateDelimiterHidingAsync()
          if res.updateHeadersTask.isNotNil:
            res.updateHeadersTask.schedule()
      discard edit.onOverlaysChanged.subscribe proc(args: tuple[ids: seq[int]]) =
        if -1 in args.ids or res.tableOverlayId.isNone or res.tableOverlayId.get notin args.ids:
          if res.updateTask.isNotNil:
            res.updateTask.schedule()

    res.documentChangedHandle = editor.onDocumentChanged.subscribe proc(arg: auto) {.closure, gcsafe, raises: [].} = res.handleDocumentChanged(arg.old, editor.currentDocument)
    if editor.currentDocument.isNotNil:
      res.handleDocumentChanged(nil, editor.currentDocument)

    let commands = editor.getCommandComponent().get
    commands.registerCommand "markdown.toggle-bold", res, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
      let self = handler.MarkdownComponent
      asyncSpawn self.toggleBold()

    commands.registerCommand "markdown.toggle-italic", res, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
      let self = handler.MarkdownComponent
      asyncSpawn self.toggleItalic()

    commands.registerCommand "markdown.toggle-code", res, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
      let self = handler.MarkdownComponent
      asyncSpawn self.toggleCode()

    commands.registerCommand "markdown.toggle-strikethrough", res, proc(handler: RootRef, args: string): string {.gcsafe, raises: [].} =
      let self = handler.MarkdownComponent
      asyncSpawn self.toggleStrikethrough()
    return res

  proc init_module_markdown_component*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_markdown_component: no services found"
      return

    let events = services.getService(EventService)
    let documents = services.getService(DocumentEditorService).get

    proc handleEditorRegistered(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.EditorIdNew
        if documents.getEditor(id).getSome(editor):
          let doc = editor.getEditorDocument()
          let config = doc.getConfigComponent().getOr:
            return
          let language = doc.getLanguageComponent().getOr:
            return
          let languages = config.get("markdown.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            let md = editor.getMarkdownComponent()
            if md.isNone:
              editor.addComponent(newMarkdownComponent(editor))
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"
    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)

