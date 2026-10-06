import std/[strformat, tables, strutils, math, options, json, algorithm, os]
import vmath, bumpy, chroma
import misc/[util, custom_logger, custom_unicode, myjsonutils, rope_utils, timer, generational_seq, render_command, arena, array_view, diff]
import text/text_editor
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import platform
import document_editor, theme, config_provider, layout/layout, service
import core_settings
import language_server
import text/[syntax_map, overlay_map, wrap_map, diff_map, display_map]
import view, treesitter/treesitter
import treesitter_component, decoration_component, hover_component, contextline_component
import text_editor_component
import app/theme_styles

import nuigi
import nuigi/debug/profiler
import nuigi/widgets
import nuigi/widgets/dynamic_virtuallist
import nuigi/widgets/list_table
import nuigi/text/graphemes
from nuigi/core/arena import allocRaw

import nimsumtree/[buffer, rope]

# Mark this entire file as used, otherwise we get warnings when importing it but only calling a method
{.used.}

{.push gcsafe.}
{.push raises: [].}
{.push stacktrace:off.}
{.push linetrace:off.}

logCategory "widget_builder_text"

proc `*`(c: Color, v: Color): Color {.inline.} =
  ## Multiply color by a value.
  result.r = c.r * v.r
  result.g = c.g * v.g
  result.b = c.b * v.b
  result.a = c.a * v.a

proc setThemeStyles(iter: var StyledChunkIterator, b: UiBuilder) =
  var rainbow: seq[Color]
  for index in UiStyleIndexRainbow0Text .. UiStyleIndexRainbow9Text:
    let c = b.themeTextStyle(index)[].textColor.toColor
    if c == color(0, 0, 0, 0):
      break
    rainbow.add c
  iter.setThemeColors(
    b.themeTextStyle(UiStyleIndexDefaultText)[].textColor.toColor,
    b.themeTextStyle(UiStyleIndexErrorText)[].textColor.toColor,
    b.themeTextStyle(UiStyleIndexWarningText)[].textColor.toColor,
    b.themeTextStyle(UiStyleIndexInfoText)[].textColor.toColor,
    b.themeTextStyle(UiStyleIndexHintText)[].textColor.toColor, rainbow)

const textLineHeightHint* = 18.0'f32

type TextChunkIndexEntry* = object
  ## Rendered-chunk index entry, mirrors legacy ChunkBounds
  ## (widget_builder_text_document.nim:33): UI node index of the chunk text node
  ## (current frame), chunk start points, and top-left px relative to the virtual
  ## list body (viewport-relative, like legacy scroll item bounds). Plain float
  ## coords (not Vec2) to avoid the vmath/vecmath Vec2 clash; x is a monospace
  ## estimate accumulated from the line indent, y replicates the virtual list's
  ## itemTop minus its scroll offset.
  nodeIndex*: int
  displayPoint*: DisplayPoint
  displayEndPoint*: DisplayPoint
  point*: Point
  endPoint*: Point
  replacementGlyphLen*: int
  posX*: float32
  posY*: float32

proc renderedByteOffset(entry: TextChunkIndexEntry, renderedText: string, originalByteOffset: int): int =
  # Replacement chunks contain ASCII spaces, one rendered rune per source byte.
  if entry.replacementGlyphLen > 0:
    return originalByteOffset.clamp(0, renderedText.len div entry.replacementGlyphLen) * entry.replacementGlyphLen
  return originalByteOffset.clamp(0, renderedText.len)

type TextDocumentEditorNuiStorage* = ref object of UiNodeStorageData
  editor*: TextDocumentEditor
  theme*: Theme
  arena*: Arena
  useHighlight*: bool
  rainbowParens*: bool
  indentGuide*: bool
  whitespaceChar*: string
  whitespaceColor*: Color
  lineNumbers*: LineNumbers
  cursorLine*: int
  cursorDisplayLine*: int
  diagnosticsLocation*: core_settings.DiagnosticsLocation
  signColumnShow*: core_settings.SignColumnShowKind
  signColumnWidth*: int
  signColumnMenuOpen*: bool
  signColumnMenuX*: float32
  signColumnMenuY*: float32
  charWidth*: float32
  lineHeight*: float32
  lineGap*: float32
  gutterWidthPx*: float32
  signColumnWidthPx*: float32
  chunkIndex*: seq[TextChunkIndexEntry]
  textListNodeIndex*: int
  mouseSelecting*: bool
  mouseSelectionCursor*: Cursor
  multiClickOriginX*: float32
  multiClickOriginY*: float32
  multiClickValid*: bool
  highlightCommands*: seq[UiRenderCommand]
  listStorage*: UiDynamicVirtualListStorage
  diffListStorage*: UiDynamicVirtualListStorage
  diffListNodeIndex*: int
  widthDocument: TextDocument
  widthRevision: int
  diffWidthDocument: TextDocument
  diffWidthRevision: int
  fitContentY*: bool
  displayLineCount*: int
  itemHeightHint*: float32
  textIter*: DisplayChunkIterator
  iterNextRow*: int
  # The old and current documents have separate, synchronized virtual lists.
  renderDiff*: bool
  diffTextIter*: DisplayChunkIterator
  diffIterNextRow*: int
  baseBackground*: Color
  insertedLineBg*: Color
  deletedLineBg*: Color
  changedLineBg*: Color
  insertedTextBg*: Color
  deletedTextBg*: Color
  changedTextBg*: Color
  highlightInlineChanges*: bool
  diffSplitWidth*: float32

type TextContextChunk = object
  text: string
  color: UiColor
  underlineColor: UiColor
  textFlags: UiTextFlags
  fontSize: float32
  width: float32

type TextContextLine = object
  chunks: seq[TextContextChunk]
  width: float32

proc getOrCreateTextEditorNuiStorage(b: var UiBuilder, node: auto): TextDocumentEditorNuiStorage =
  let existing = b.nodeStorageGet(node)
  if existing != nil:
    return cast[TextDocumentEditorNuiStorage](existing)
  var storage = TextDocumentEditorNuiStorage()
  b.nodeStorage(node, storage)
  return storage

proc nuiChunkTextFlags(fontStyle: set[FontStyle], hasUnderline: bool): UiTextFlags =
  if Italic in fontStyle:
    result.incl UiTextFlag.Italic
  if Bold in fontStyle:
    result.incl UiTextFlag.Bold
  if Underline in fontStyle or hasUnderline:
    result.incl UiTextFlag.Underline

proc collectTextContextLineNui(b: var UiBuilder,
    storage: TextDocumentEditorNuiStorage, self: TextDocumentEditor,
    start: DisplayPoint, endColumn = -1): TextContextLine {.nimcall, gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      let arenaCheckpoint = storage.arena.checkpoint()
      defer:
        storage.arena.restoreCheckpoint(arenaCheckpoint)
      var highlighter = Highlighter.none
      if storage.useHighlight and storage.theme != nil:
        let sm = self.document.treesitterComponent.syntaxMap
        if sm.snapshot.layers.len > 0:
          highlighter = Highlighter.init(sm, storage.rainbowParens).some
      self.displayMap.setWhitespaceRendering(storage.whitespaceChar, storage.whitespaceColor)
      var iter = self.displayMap.iter(storage.arena.addr, highlighter, storage.theme)
      iter.styledChunks.setThemeStyles(b)
      if start.column == 0:
        iter.seekLine(start.row.int)
      else:
        iter.seek(start)
      discard iter.next()
      let baseStyle = b.themeTextStyle(int(UiStyleIndexDefaultText))[]
      while iter.displayChunk.isSome:
        let chunk = iter.displayChunk.get
        if chunk.displayPoint.row != start.row:
          break
        if endColumn >= 0 and chunk.displayPoint.column.int >= endColumn:
          break
        discard iter.next()
        if chunk.len == 0:
          continue
        var text = newStringOfCap(chunk.len)
        for c in chunk.toOpenArray:
          text.add c
        let styled = chunk.styledChunk
        let fontSize = baseStyle.fontSize * styled.fontScale.float32
        var measureStyle = baseStyle
        measureStyle.text = text.uiString
        measureStyle.fontSize = fontSize
        let width = b.measuredTextSize(measureStyle.addr).x
        let textColor = rgba(styled.color.r.float32, styled.color.g.float32,
          styled.color.b.float32, styled.color.a.float32)
        let underlineColor = if styled.underline.getSome(underline):
          rgba(underline.color.r.float32, underline.color.g.float32,
            underline.color.b.float32, underline.color.a.float32)
        else:
          textColor
        result.chunks.add TextContextChunk(
          text: text,
          color: textColor,
          underlineColor: underlineColor,
          textFlags: nuiChunkTextFlags(styled.fontStyle, styled.underline.isSome),
          fontSize: fontSize,
          width: width)
        result.width += width
    except:
      discard

proc contextLineNumberNui(storage: TextDocumentEditorNuiStorage, line: int): string =
  if storage.lineNumbers == LineNumbers.None:
    return ""
  let number = if storage.cursorLine == line or storage.lineNumbers == LineNumbers.Absolute:
      line + 1
    elif storage.lineNumbers == LineNumbers.Relative:
      abs((line + 1) - storage.cursorLine)
    else:
      -1
  if number >= 0: $number else: ""

proc contextSignGutterWidthNui(storage: TextDocumentEditorNuiStorage): float32 =
  if storage.signColumnShow in {core_settings.SignColumnShowKind.Number,
      core_settings.SignColumnShowKind.No}:
    0.0'f32
  else:
    storage.signColumnWidthPx

proc buildTextContextChunksNui(b: var UiBuilder,
    chunks: openArray[TextContextChunk]) =
  for chunk in chunks:
    b.node:
      discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText))
        .textColor(chunk.color).textFlags(chunk.textFlags)
        .underlineColor(chunk.underlineColor).underlineThickness(2)
        .fontSize(chunk.fontSize).text(chunk.text)

proc buildTextContextGutterNui(b: var UiBuilder,
    storage: TextDocumentEditorNuiStorage, number: string,
    includeGutter = true) =
  if not includeGutter:
    return
  let signWidth = storage.contextSignGutterWidthNui
  let numberWidth = if storage.lineNumbers == LineNumbers.None: 0.0'f32
    else: storage.gutterWidthPx
  if signWidth > 0.0'f32:
    b.node:
      discard b.width(signWidth).height(storage.lineHeight)
  if numberWidth > 0.0'f32:
    b.layoutHorizontalReverse:
      discard b.width(numberWidth).height(storage.lineHeight)
      if number.len > 0:
        b.node:
          discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(number)

proc buildTextContextOverlayNui(b: var UiBuilder, nodeIdx: int,
    userData: int) {.nimcall, raises: [].} =
  {.cast(gcsafe).}:
    try:
      discard b.noHover().noChildHover()
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      let self = storage.editor
      if self.isNil or self.document.isNil or self.displayMap.isNil or
          storage.theme.isNil or self.contextLineComponent.isNil or
          storage.renderDiff or storage.listStorage.isNil or
          not self.config.getContextLinesEnabled():
        return
      let entries = self.contextLineComponent.getContextLines()
      if entries.len == 0:
        return
      let contextColor = b.themeStyle(UiStyleIndexContext)[].fillColor.toColor
      let contextUiColor = rgba(contextColor.r.float32, contextColor.g.float32,
        contextColor.b.float32, contextColor.a.float32)
      let gutterWidth = if storage.lineNumbers == LineNumbers.None: 0.0'f32
        else: storage.gutterWidthPx + storage.contextSignGutterWidthNui
      let style = self.config.getContextLinesStyle()

      if style != "breadcrumb":
        b.layoutVertical:
          b.debugName("text-context-lines")
          discard b.fillX().fitY().maskChildren()
          for entry in entries:
            let start = self.displayMap.toDisplayPoint(point(entry.line, 0))
            let line = b.collectTextContextLineNui(storage, self, start)
            let number = storage.contextLineNumberNui(entry.line)
            let rowWidth = max(line.width + gutterWidth, 1.0'f32)
            b.layoutHorizontal:
              b.debugName("text-context-line")
              discard b.width(rowWidth).height(storage.lineHeight)
                .fillBackground().backgroundColor(contextUiColor)
              b.buildTextContextGutterNui(storage, number)
              b.buildTextContextChunksNui(line.chunks)
      else:
        let separator = " " & self.config.getContextLinesSeparator() & " "
        let separatorColor = b.themeTextStyle(UiStyleIndexContextText)[].textColor.toColor
        let separatorUiColor = rgba(separatorColor.r.float32,
          separatorColor.g.float32, separatorColor.b.float32,
          separatorColor.a.float32)
        var separatorStyle = b.themeTextStyle(int(UiStyleIndexDefaultText))[]
        separatorStyle.text = separator.uiString
        let separatorWidth = b.measuredTextSize(separatorStyle.addr).x
        let padding = floor(storage.charWidth * 0.5'f32)
        let availableWidth = max(b.frame.nodes[nodeIdx].size.x, 1.0'f32)
        var breadcrumbLines = newSeq[TextContextLine](entries.len)
        for i, entry in entries:
          let start = self.displayMap.toDisplayPoint(entry.lineRange.a)
          breadcrumbLines[i] = b.collectTextContextLineNui(storage, self, start,
            start.column.int + 50)

        var rows: seq[seq[int]] = @[]
        var currentRow: seq[int] = @[]
        var currentWidth = 0.0'f32
        for i, line in breadcrumbLines:
          let numberWidth = if i == 0: gutterWidth else: 0.0'f32
          let entryWidth = line.width + numberWidth + padding * 2
          let nextWidth = currentWidth +
            (if currentRow.len > 0: separatorWidth else: 0.0'f32) + entryWidth
          if currentRow.len > 0 and nextWidth > availableWidth:
            rows.add currentRow
            currentRow = @[]
            currentWidth = gutterWidth
          if currentRow.len > 0:
            currentWidth += separatorWidth
          currentRow.add i
          currentWidth += entryWidth
        if currentRow.len > 0:
          rows.add currentRow

        let breadcrumbBackground = contextColor.darken(0.05)
        let breadcrumbBackgroundUi = rgba(breadcrumbBackground.r.float32,
          breadcrumbBackground.g.float32, breadcrumbBackground.b.float32,
          breadcrumbBackground.a.float32)
        b.layoutVertical:
          b.debugName("text-context-breadcrumbs")
          discard b.fillX().fitY().maskChildren()
            .fillBackground().backgroundColor(breadcrumbBackgroundUi)
          for rowIndex, row in rows:
            b.layoutHorizontal:
              b.debugName("text-context-breadcrumb-row")
              discard b.fillX().height(storage.lineHeight)
              if rowIndex > 0 and gutterWidth > 0.0'f32:
                b.node:
                  discard b.width(gutterWidth).height(storage.lineHeight)
              for column, entryIndex in row:
                if column > 0:
                  b.node:
                    discard b.fit().height(storage.lineHeight)
                      .textStyleIndex(int(UiStyleIndexDefaultText))
                      .textColor(separatorUiColor).text(separator)
                let number = if entryIndex == 0:
                    storage.contextLineNumberNui(entries[entryIndex].line)
                  else:
                    ""
                b.layoutHorizontal:
                  b.debugName("text-context-breadcrumb-entry")
                  discard b.fit().fillBackground().backgroundColor(contextUiColor)
                  b.node:
                    discard b.width(padding).height(storage.lineHeight)
                  b.buildTextContextGutterNui(storage, number, entryIndex == 0)
                  b.buildTextContextChunksNui(breadcrumbLines[entryIndex].chunks)
                  b.node:
                    discard b.width(padding).height(storage.lineHeight)
    except:
      discard

proc createNuiIter(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage, b: UiBuilder) =
  ## Fresh forward iterator for this frame, stored on the node storage and reused
  ## across lines (one construction per frame instead of per line).
  ## Display iterators are single-pass by design: no level clears atEnd/done on
  ## seek and lower levels assert forward-only seeks. That is safe here because
  ## the iterator is fresh every frame (theme/highlighter always current) and
  ## rows arrive in ascending order, so the frontier only ever moves forward
  ## (legacy createIter convention at widget_builder_text_document.nim:1375).
  var editor = self
  var highlighter = Highlighter.none
  if storage.useHighlight and storage.theme != nil:
    let sm = editor.document.treesitterComponent.syntaxMap
    if sm.snapshot.layers.len > 0:
      highlighter = Highlighter.init(sm, storage.rainbowParens).some
  editor.displayMap.setWhitespaceRendering(storage.whitespaceChar, storage.whitespaceColor)
  storage.textIter = editor.displayMap.iter(storage.arena.addr, highlighter, storage.theme)
  storage.textIter.styledChunks.setThemeStyles(b)
  storage.textIter.styledChunks.diagnosticEndPoints = editor.document.diagnosticEndPoints
  if storage.indentGuide:
    storage.textIter.indentGuideColumn =
      editor.document.rope.indentRunes(storage.cursorLine).int.some
  storage.iterNextRow = -1

proc createNuiDiffIter(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage, b: UiBuilder) =
  ## Fresh forward iterator over the diff (old) side for this frame, mirroring
  ## legacy createDiffIter (widget_builder_text_document.nim:1393).
  var editor = self
  var highlighter = Highlighter.none
  if storage.useHighlight and storage.theme != nil:
    try:
      if editor.diffDocument != nil:
        let sm = editor.diffDocument.treesitterComponent.syntaxMap
        if sm.snapshot.layers.len > 0:
          highlighter = Highlighter.init(sm, storage.rainbowParens).some
    except:
      discard
  try:
    editor.diffDisplayMap.setWhitespaceRendering(storage.whitespaceChar, storage.whitespaceColor)
    storage.diffTextIter = editor.diffDisplayMap.iter(storage.arena.addr, highlighter, storage.theme)
    storage.diffTextIter.styledChunks.setThemeStyles(b)
  except:
    discard
  storage.diffIterNextRow = -1

proc nuiDiffLineBackground(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage,
    itemIndex: int, isDiffSide: bool): tuple[bg: Color, hasBg: bool] {.nimcall, gcsafe, raises: [].} =
  ## Whole-line diff background for one side of a diff row, mirroring legacy
  ## drawDiffBackgrounds (widget_builder_text_document.nim:988). Main (right)
  ## side uses diffReverse=true, diff (left) side uses diffReverse=false.
  {.cast(gcsafe).}:
    try:
      if self.diffChanges.isNone:
        return (storage.baseBackground, false)
      let diffReverse = not isDiffSide
      let displayMap =
        if isDiffSide: self.diffDisplayMap
        else: self.displayMap
      let otherDisplayMap =
        if isDiffSide: self.displayMap
        else: self.diffDisplayMap
      if displayMap.isNil or otherDisplayMap.isNil:
        return (storage.baseBackground, false)
      let mappings = self.diffChanges.get
      var bg = storage.baseBackground
      var hasBg = false
      try:
        let line = displayMap.toPoint(displayPoint(itemIndex, 0)).row.int
        let diffRow = mappings.mapLine(line, diffReverse)
        if diffRow.getSome(d):
          if d.changed:
            bg = storage.changedLineBg
            hasBg = true
        else:
          bg = if diffReverse: storage.insertedLineBg else: storage.deletedLineBg
          hasBg = true
      except:
        discard
      # Gap darkening: when the other side has no counterpart for its line at
      # this display row, the aligned gap row is darkened (legacy second fill).
      try:
        let diffLine = otherDisplayMap.toPoint(displayPoint(itemIndex, 0)).row.int
        if mappings.mapLine(diffLine, not diffReverse).isNone:
          bg = storage.baseBackground.darken(0.03)
          hasBg = true
      except:
        discard
      return (bg, hasBg)
    except:
      return (storage.baseBackground, false)

proc nuiDiffChunkHighlight(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage,
    chunkPoint: Point, chunkEnd: Point, isDiffSide: bool): tuple[bg: Color, hasBg: bool] {.nimcall, gcsafe, raises: [].} =
  ## Precise inline diff highlight for one chunk, mirroring legacy
  ## drawPreciseDiffHighlights (widget_builder_text_document.nim:1011). Returns
  ## a single per-chunk background (changed wins over inserted/deleted tails);
  ## the legacy version draws sub-chunk rects, this is blockier by design (v1).
  ## Main (right) side uses reverse=false, diff (left) side uses reverse=true.
  {.cast(gcsafe).}:
    try:
      if not storage.highlightInlineChanges or self.diffChanges.isNone:
        return (storage.baseBackground, false)
      let displayMap =
        if isDiffSide: self.diffDisplayMap
        else: self.displayMap
      if displayMap.isNil:
        return (storage.baseBackground, false)
      let reverse = isDiffSide
      let chunkRange = chunkPoint...chunkEnd
      var foundInserted = false
      var foundDeleted = false
      for ropeDiff in displayMap.diffMap.snapshot.inlineMappings:
        if ropeDiff.diff.edits.len == 0:
          continue
        let mappingStart = ropeDiff.srcBase
        let mappingEnd =
          try: mappingStart + ropeDiff.diff.edits[^1].old.b
          except: mappingStart
        if mappingStart.row > chunkEnd.row:
          break
        if mappingEnd.row < chunkPoint.row:
          continue
        for edit in ropeDiff.diff.edits:
          let startPt = mappingStart + edit.old.a
          var deletedRangeRel: Point = edit.new.b - edit.new.a
          var insertedRangeRel: Point = edit.old.b - edit.old.a
          var changedRangeRel = min(deletedRangeRel, insertedRangeRel)
          var changedRange =
            try: startPt...(startPt + changedRangeRel)
            except: continue
          var insertedRange =
            try: changedRange.b...(startPt + insertedRangeRel)
            except: continue
          var deletedRange = changedRange.b...changedRange.b
          if reverse:
            swap deletedRange, insertedRange
            swap deletedRangeRel, insertedRangeRel
          # Changed range overlap
          if not (changedRange.b <= chunkRange.a or changedRange.a >= chunkRange.b):
            if changedRange.a != changedRange.b:
              return (storage.changedTextBg, true)
          if insertedRangeRel > deletedRangeRel:
            if not (insertedRange.b <= chunkRange.a or insertedRange.a >= chunkRange.b):
              if insertedRange.a != insertedRange.b:
                foundInserted = true
          elif insertedRangeRel < deletedRangeRel:
            if not (deletedRange.b <= chunkRange.a or deletedRange.a >= chunkRange.b):
              if deletedRange.a != deletedRange.b:
                foundDeleted = true
      if foundInserted:
        let c = if reverse: storage.deletedTextBg else: storage.insertedTextBg
        return (c, true)
      if foundDeleted:
        let c = if reverse: storage.insertedTextBg else: storage.deletedTextBg
        return (c, true)
      return (storage.baseBackground, false)
    except:
      return (storage.baseBackground, false)

proc nuiDiffDeletedSpanRows(self: TextDocumentEditor, sFirst, sLast: int): int {.nimcall, gcsafe, raises: [].} =
  ## Display-row span of a deleted source range for scrollbar markers. Deleted
  ## blocks have an empty target range, so their height comes from the source
  ## (old) side measured in diff display rows (wrapping included), mirroring
  ## how inserted blocks span target display rows. Falls back to the raw
  ## source line count.
  {.cast(gcsafe).}:
    try:
      if self.diffDisplayMap.isNil or self.diffDocument == nil:
        return max(sLast - sFirst, 0)
      let maxOld = max(self.diffDocument.numLines - 1, 0)
      let scFirst = clamp(sFirst, 0, maxOld)
      let scLast = clamp(sLast, scFirst, self.diffDocument.numLines)
      if scLast <= scFirst:
        return 0
      let sdFirst = self.diffDisplayMap.toDisplayPoint(point(scFirst, 0)).row.int
      let sdLast = self.diffDisplayMap.toDisplayPoint(point(scLast, 0)).row.int
      return max(sdLast - sdFirst, 0)
    except:
      return max(sLast - sFirst, 0)

proc nuiMeasuredPrefixWidth(b: var UiBuilder, text: string, byteCount: int,
    textStyle: UiNodeText): float32 {.nimcall, gcsafe, raises: [].} =
  ## Measured width of text[0 ..< byteCount] in the given style (mirrors
  ## textfield.measuredPrefixWidth, which is private to that widget).
  {.cast(gcsafe).}:
    try:
      if byteCount <= 0:
        return 0.0'f32
      var prefixStyle = textStyle
      prefixStyle.text = text[0 ..< byteCount].uiString
      return b.measuredTextSize(prefixStyle.addr).x
    except:
      return 0.0'f32

proc nuiByteOffsetAtX(b: var UiBuilder, chunk: TextChunkIndexEntry, text: string, pointerX: float32,
    textStyle: UiNodeText, thickCursor: bool): int {.nimcall, gcsafe, raises: [].} =
  ## Thin cursors select the nearest boundary; thick cursors select the clicked
  ## grapheme. Both return byte offsets in the original text.
  {.cast(gcsafe).}:
    try:
      if pointerX <= 0.0'f32 or text.len == 0:
        return 0
      var previousPosition = 0
      var position = text.nextGraphemeBoundary(0)
      while position <= text.len:
        let previousX = b.nuiMeasuredPrefixWidth(text, previousPosition, textStyle)
        let currentX = b.nuiMeasuredPrefixWidth(text, position, textStyle)
        let threshold = if thickCursor: currentX else: (previousX + currentX) * 0.5'f32
        if pointerX < threshold:
          let originalOffset = if chunk.replacementGlyphLen > 0:
              text.toOpenArray(0, text.high).runeIndex(previousPosition).int
            else:
              previousPosition
          return originalOffset
        if position == text.len:
          return int(chunk.displayEndPoint.column - chunk.displayPoint.column)
        previousPosition = position
        position = text.nextGraphemeBoundary(position)
      return int(chunk.displayEndPoint.column - chunk.displayPoint.column)
    except:
      log lvlError, "Failed to hit-test text: ", getCurrentExceptionMsg()
      return 0

proc nuiMouseChunkIndex(b: UiBuilder, storage: TextDocumentEditorNuiStorage): int =
  # Clamp drags outside the viewport to the first/last rendered row, using
  # laid-out nodes rather than estimated row heights.
  result = -1
  let mouse = b.frameCtx.input.mouse
  var bestDx = float32.high
  var bestDy = float32.high
  var bestX = float32.low
  var bestY = float32.low
  for i, entry in storage.chunkIndex:
    if entry.nodeIndex < 0 or entry.nodeIndex >= b.frame.nodes.len:
      continue
    let node = b.frame.nodes[entry.nodeIndex].addr
    let pos = b.absoluteNodePos(entry.nodeIndex)
    let dx = max(max(pos.x - mouse.x, mouse.x - pos.x - node.size.x), 0.0'f32)
    let dy = max(max(pos.y - mouse.y, mouse.y - pos.y - node.size.y), 0.0'f32)
    if dy < bestDy or (dy == bestDy and
        (pos.y > bestY and pos.y <= mouse.y or
          (pos.y == bestY and (dx < bestDx or
            (dx == bestDx and pos.x > bestX and pos.x <= mouse.x))))):
      result = i
      bestDx = dx
      bestDy = dy
      bestX = pos.x
      bestY = pos.y

proc nuiMouseSelectionButton(clickCount: uint8): MouseButton =
  if clickCount >= 3: MouseButton.TripleClick
  elif clickCount == 2: MouseButton.DoubleClick
  else: MouseButton.Left

proc nuiMouseDragSelection(start: Selection, newCursor: Cursor): Selection =
  let first = if (start.isBackwards and newCursor < start.first) or
      (not start.isBackwards and newCursor >= start.first):
      start.first
    else:
      start.last
  return (first, newCursor)

proc buildTextMouseSelectionNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      let self = storage.editor
      if self != nil and self.colorPickerStorage != nil and self.colorPickerStorage.open:
        if findNodeIndexById(b.frame.nodes, self.colorPickerStorage.ownerId) < 0:
          self.closeColorPicker(b)
      if self == nil or self.document == nil or not self.document.isInitialized:
        storage.mouseSelecting = false
        return
      let input = b.frameCtx.input
      if storage.multiClickValid:
        let dx = input.mouse.x - storage.multiClickOriginX
        let dy = input.mouse.y - storage.multiClickOriginY
        if dx * dx + dy * dy > 4.0'f32:
          storage.multiClickValid = false
      let wasSelecting = storage.mouseSelecting
      if MouseLeft notin input.mouseDown:
        storage.mouseSelecting = false
      if storage.textListNodeIndex < 0 or storage.textListNodeIndex >= b.frame.nodes.len:
        return
      var pressed = b.wasPressed(storage.textListNodeIndex, includeChildren = true)
      if self.colorPickerPressedFrame == input.frameIndex:
        pressed = false
      if storage.listStorage != nil and storage.listStorage.scrollbarTrackIndex >= 0:
        if b.wasPressed(storage.listStorage.scrollbarTrackIndex, includeChildren = true):
          pressed = false
      if storage.listStorage != nil and storage.listStorage.horizontalScrollbarTrackIndex >= 0:
        if b.wasPressed(storage.listStorage.horizontalScrollbarTrackIndex, includeChildren = true):
          pressed = false
      if storage.renderDiff:
        let listPos = b.absoluteNodePos(storage.textListNodeIndex)
        let listWidth = b.frame.nodes[storage.textListNodeIndex].size.x
        if input.mouse.x < listPos.x or input.mouse.x >= listPos.x + listWidth:
          pressed = false
      if MouseLeft in input.mousePressed and not pressed:
        storage.mouseSelecting = false
        storage.multiClickValid = false
        return
      let dragging = not pressed and wasSelecting and
        (input.mouseDelta.x != 0.0'f32 or input.mouseDelta.y != 0.0'f32) and
        (MouseLeft in input.mouseDown or MouseLeft in input.mouseReleased)
      if not pressed and not dragging:
        return

      let best = b.nuiMouseChunkIndex(storage)
      if best < 0:
        return
      let entry = storage.chunkIndex[best]
      let node = b.frame.nodes[entry.nodeIndex].addr
      let slot = int(node.textIndex)
      if slot <= 0 or slot > b.frame.texts.len:
        return
      let textStyle = b.frame.texts[slot - 1]
      let pos = b.absoluteNodePos(entry.nodeIndex)
      let off = b.nuiByteOffsetAtX(entry, textStyle.text.value, input.mouse.x - pos.x,
        textStyle, self.isThickCursor())
      let newCursor = self.document.clampCursor(entry.point.toCursor + (0, off))
      if dragging and newCursor == storage.mouseSelectionCursor:
        return
      storage.mouseSelectionCursor = newCursor
      if pressed:
        storage.mouseSelecting = MouseLeft in input.mouseDown
        if input.mouseClickCount <= 1:
          storage.multiClickOriginX = input.mouse.x
          storage.multiClickOriginY = input.mouse.y
          storage.multiClickValid = true
      let document = self.document
      let button = nuiMouseSelectionButton(
        if storage.multiClickValid: input.mouseClickCount else: 1'u8)
      let controlClick = input.modsDown == {ModControl}
      b.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} =
        if self.document != document or not document.isInitialized:
          return
        if pressed:
          self.layout.tryActivateEditor(self)
          self.lastPressedMouseButton = button
          self.selection = newCursor.toSelection
          self.dragStartSelection = self.selection
          case self.lastPressedMouseButton
          of MouseButton.DoubleClick:
            self.runDoubleClickCommand()
          of MouseButton.TripleClick:
            self.runTripleClickCommand()
          else:
            if controlClick:
              self.runControlClickCommand()
            else:
              self.runSingleClickCommand()
        else:
          self.selection = nuiMouseDragSelection(self.dragStartSelection, newCursor)
          self.runDragCommand()
        self.scrollToCursor(Last)
        self.updateTargetColumn(Last)
        self.markDirty())
    except:
      log lvlError, "Failed to handle text mouse selection: ", getCurrentExceptionMsg()

proc nuiArenaIntText(b: var UiBuilder, num: int): tuple[buf: ptr UncheckedArray[char], len: int] {.nimcall, gcsafe, raises: [].} =
  ## Decimal rendering of num into frame-arena chars for zero-alloc node text
  ## (text(openArray) borrows the view; the backing lives until end of frame).
  ## Returns a raw buf/len pair because openArray is not returnable from procs.
  {.cast(gcsafe).}:
    var buf: array[20, char]
    var len = 0
    var n = num
    var neg = false
    if n < 0:
      neg = true
      n = -n
    if n == 0:
      buf[0] = '0'
      len = 1
    else:
      while n > 0:
        buf[len] = chr(ord('0') + n mod 10)
        inc len
        n = n div 10
      if neg:
        buf[len] = '-'
        inc len
      for i in 0 ..< len div 2:
        let t = buf[i]
        buf[i] = buf[len - 1 - i]
        buf[len - 1 - i] = t
    let mem = b.frame.arena[].allocRaw(len, 1)
    copyMem(mem, buf[0].addr, len)
    return (cast[ptr UncheckedArray[char]](mem), len)

proc nuiDiagnosticColor(b: UiBuilder,
    severity: Option[language_server.DiagnosticSeverity]): UiColor {.nimcall, gcsafe, raises: [].} =
  let index = case severity.get(language_server.DiagnosticSeverity.Hint)
    of language_server.DiagnosticSeverity.Error: UiStyleIndexErrorText
    of language_server.DiagnosticSeverity.Warning: UiStyleIndexWarningText
    of language_server.DiagnosticSeverity.Information: UiStyleIndexInfoText
    of language_server.DiagnosticSeverity.Hint: UiStyleIndexHintText
  b.themeTextStyle(index)[].textColor

type TextCustomOverlayEntry = object
  renderId: int
  localOffset: int
  location: overlay_map.OverlayRenderLocation

proc getCustomOverlayRenderer(self: TextDocumentEditor, renderId: int): Option[CustomOverlayRenderer] =
  if self.decorations.isNil or renderId == 0:
    return none(CustomOverlayRenderer)
  return self.decorations.customOverlayRenderers.tryGet(renderId.CustomRendererId)

proc buildTextCustomOverlayInlineNui(b: var UiBuilder, self: TextDocumentEditor,
    overlay: OverlayChunk, positionX, chunkWidth, lineHeight: float32): Option[Vec2] =
  let renderer = self.getCustomOverlayRenderer(overlay.renderId)
  if renderer.isNone:
    return none(Vec2)

  var actualBounds = vec2(chunkWidth, lineHeight)
  b.node:
    discard b.position(positionX, 0).size(chunkWidth, lineHeight).finishAnchors()
    actualBounds = renderer.get()(
      overlay.renderId, vec2(chunkWidth, lineHeight), overlay.localOffset, b)
    discard b.size(max(chunkWidth, actualBounds.x), max(lineHeight, actualBounds.y))
  return actualBounds.some

proc buildInteractiveTextLineHorizontalNui(b: var UiBuilder, itemIndex: int,
    storage: TextDocumentEditorNuiStorage, self: TextDocumentEditor,
    lineH: var float32, customOverlays: var seq[TextCustomOverlayEntry],
    highlightInlineDiff = false) {.nimcall, gcsafe, raises: [].} =
  ## Shared main-document row used by normal rendering and the interactive
  ## right side of diff rendering. The caller positions the stored iterator.
  let lineNumbers = storage.lineNumbers
  let cursorLine = storage.cursorLine
  let numberGutterPx = if lineNumbers == LineNumbers.None: 0.0'f32 else: storage.gutterWidthPx
  let signGutterPx =
    if storage.signColumnShow == core_settings.SignColumnShowKind.Number or
        storage.signColumnShow == core_settings.SignColumnShowKind.No:
      0.0'f32
    else:
      storage.signColumnWidthPx
  var realLine = -1
  var firstDisplayRow = -1
  if storage.textIter.displayChunk.isSome:
    realLine = storage.textIter.displayChunk.get.point.row.int
    firstDisplayRow = self.displayMap.toDisplayPoint(point(realLine, 0)).row.int
  let firstRowOfRealLine = realLine >= 0 and firstDisplayRow == itemIndex
  let lineSigns =
    if firstRowOfRealLine: self.decorations.signs.getOrDefault(realLine)
    else: @[]
  let signsInNumberColumn =
    storage.signColumnShow == core_settings.SignColumnShowKind.Number and
    lineSigns.len > 0
  let signRenderWidthPx = if signsInNumberColumn: numberGutterPx else: signGutterPx

  var showNumber = false
  var numberBuf: ptr UncheckedArray[char]
  var numberLen = 0
  if lineNumbers != LineNumbers.None and realLine >= 0 and firstDisplayRow == itemIndex:
    var num = -1
    if cursorLine == realLine:
      num = realLine + 1
    elif lineNumbers == LineNumbers.Absolute:
      num = realLine + 1
    elif lineNumbers == LineNumbers.Relative:
      num = abs((realLine + 1) - cursorLine)
    if num >= 0:
      showNumber = true
      let t = b.nuiArenaIntText(num)
      numberBuf = t.buf
      numberLen = t.len
  if signsInNumberColumn:
    showNumber = false

  let baseFontSize = b.themeTextStyle(int(UiStyleIndexDefaultText))[].fontSize
  let isContinuation = realLine >= 0 and firstDisplayRow != itemIndex
  var indentPx = 0.0'f32
  if showNumber:
    indentPx = signGutterPx + numberGutterPx
  elif isContinuation:
    indentPx = signGutterPx + numberGutterPx
    var wrapIndentCols = 4
    if self.displayMap.wrapMap != nil:
      wrapIndentCols = self.displayMap.wrapMap.snapshot.wrappedIndent
    indentPx += wrapIndentCols.float32 * storage.charWidth
  else:
    indentPx = signRenderWidthPx

  var yLine = 0.0'f32
  if storage.listStorage != nil:
    var top = itemIndex.float32 * storage.itemHeightHint
    for sample in storage.listStorage.heights:
      if sample.itemIndex >= itemIndex:
        break
      top += sample.height - storage.itemHeightHint
    yLine = top - storage.listStorage.scrollOffsetY

  var xCursor = indentPx
  var gutterNodeIdx = -1
  let gutterWidthPx = signGutterPx + numberGutterPx
  b.layoutHorizontal:
    discard b.fillX().fitY()
    if gutterWidthPx > 0.0'f32:
      b.layoutHorizontal:
        gutterNodeIdx = b.currentNodeIndex
        discard b.width(gutterWidthPx).fitY()
        if signGutterPx > 0.0'f32 or signsInNumberColumn:
          b.layoutHorizontal:
            discard b.width(signRenderWidthPx).fitY()
            if signsInNumberColumn:
              b.node:
                discard b.width(storage.charWidth).fitY()
            var usedSignWidth = 0
            for sign in lineSigns:
              if usedSignWidth + sign.width > storage.signColumnWidth:
                break
              var signColor = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor.toColor
              if storage.theme != nil:
                if sign.color.len > 0:
                  signColor = storage.theme.tokenColor(sign.color, signColor)
              signColor = signColor * sign.tint
              b.node:
                discard b.width(sign.width.float32 * storage.charWidth).fitY()
                  .textStyleIndex(int(UiStyleIndexDefaultText))
                  .textColor(rgba(signColor.r.float32, signColor.g.float32,
                    signColor.b.float32, signColor.a.float32))
                  .text(sign.text)
              usedSignWidth += sign.width
        if showNumber:
          b.layoutHorizontalReverse:
            discard b.width(numberGutterPx).fitY()
            b.node:
              discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(toOpenArray(numberBuf, 0, numberLen - 1))
    if isContinuation:
      let wrapIndentPx = indentPx - signGutterPx - numberGutterPx
      b.node:
        discard b.width(wrapIndentPx).fitY()

    var hasChunks = false
    while storage.textIter.displayChunk.isSome:
      prof("chunk")
      let chunk = storage.textIter.displayChunk.get
      if chunk.displayPoint.row.int != itemIndex:
        break
      let styled = chunk.styledChunk
      let chunkColor = styled.color
      let chunkScale = styled.fontScale
      let chunkTextFlags = nuiChunkTextFlags(styled.fontStyle, styled.underline.isSome)
      var underlineUiColor = rgba(chunkColor.r.float32, chunkColor.g.float32, chunkColor.b.float32, chunkColor.a.float32)
      if styled.underline.getSome(underline):
        underlineUiColor = rgba(underline.color.r.float32, underline.color.g.float32,
          underline.color.b.float32, underline.color.a.float32)
      let chunkDisplayPoint = chunk.displayPoint
      let chunkDisplayEndPoint = chunk.endDisplayPoint
      let chunkPoint = chunk.point
      let chunkEndPoint = chunk.endPoint
      let customOverlay = chunk.diffChunk.inputChunk.inputChunk.inputChunk
      if customOverlay.renderId != 0 and
          customOverlay.location != overlay_map.OverlayRenderLocation.Inline:
        customOverlays.add TextCustomOverlayEntry(
          renderId: customOverlay.renderId,
          localOffset: customOverlay.localOffset,
          location: customOverlay.location)
      let replacementGlyphLen = if chunk.replacementText != nil:
          runeLenAt(chunk.toOpenArray, 0)
        else:
          0
      discard storage.textIter.next()
      if chunk.len == 0:
        if customOverlay.renderId != 0 and
            customOverlay.location == overlay_map.OverlayRenderLocation.Inline:
          let actualBounds = b.buildTextCustomOverlayInlineNui(
            self, customOverlay, xCursor, 0.0'f32, lineH)
          if actualBounds.isSome:
            lineH = max(lineH, actualBounds.get.y)
            xCursor += actualBounds.get.x
        continue
      hasChunks = true
      let uiColor = rgba(chunkColor.r.float32, chunkColor.g.float32, chunkColor.b.float32, chunkColor.a.float32)
      let entryX = xCursor
      var chunkNodeIdx = -1
      b.node:
        chunkNodeIdx = b.currentNodeIndex
        discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText))
        if highlightInlineDiff:
          let (hlBg, hasHl) = self.nuiDiffChunkHighlight(storage, chunkPoint, chunkEndPoint, false)
          if hasHl:
            discard b.fillBackground().backgroundColor(rgba(hlBg.r.float32, hlBg.g.float32, hlBg.b.float32, hlBg.a.float32))
        discard b.textColor(uiColor).textFlags(chunkTextFlags).underlineColor(underlineUiColor).underlineThickness(2)
          .fontSize(baseFontSize * chunkScale.float32).text(chunk.toOpenArray)
        xCursor += b.currentNode.size.x
      lineH = max(lineH, b.frame.nodes[chunkNodeIdx].size.y)
      storage.chunkIndex.add TextChunkIndexEntry(
        nodeIndex: chunkNodeIdx,
        displayPoint: chunkDisplayPoint,
        displayEndPoint: chunkDisplayEndPoint,
        point: chunkPoint,
        endPoint: chunkEndPoint,
        replacementGlyphLen: replacementGlyphLen,
        posX: entryX,
        posY: yLine)
      if customOverlay.renderId != 0 and
          customOverlay.location == overlay_map.OverlayRenderLocation.Inline:
        let chunkWidth = b.frame.nodes[chunkNodeIdx].size.x
        let actualBounds = b.buildTextCustomOverlayInlineNui(
          self, customOverlay, entryX, chunkWidth, lineH)
        if actualBounds.isSome:
          lineH = max(lineH, actualBounds.get.y)
          if actualBounds.get.x > chunkWidth:
            xCursor += actualBounds.get.x - chunkWidth

    storage.iterNextRow = itemIndex + 1
    if not hasChunks:
      var fallbackNodeIdx = -1
      b.node:
        fallbackNodeIdx = b.currentNodeIndex
        discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(" ")
      try:
        if itemIndex >= 0 and itemIndex < self.numDisplayLines:
          let emptyPoint = self.displayMap.toPoint(displayPoint(itemIndex, 0))
          storage.chunkIndex.add TextChunkIndexEntry(
            nodeIndex: fallbackNodeIdx,
            displayPoint: displayPoint(itemIndex, 0),
            displayEndPoint: displayPoint(itemIndex, 0),
            point: emptyPoint,
            endPoint: emptyPoint,
            posX: xCursor,
            posY: yLine)
      except:
        discard

    if firstRowOfRealLine:
      let renderBelow =
        storage.diagnosticsLocation == core_settings.DiagnosticsLocation.Below or
        (storage.diagnosticsLocation == core_settings.DiagnosticsLocation.LineEndOrBelow and
          realLine == cursorLine)
      var renderedInlineDiagnostic = false
      if not renderBelow:
        for diagnosticsData in self.document.diagnosticsPerLS.mitems:
          diagnosticsData.diagnosticsPerLine.withValue(realLine, lineDiagnostics):
            for diagnosticIndex in lineDiagnostics[]:
              if diagnosticIndex < 0 or diagnosticIndex >= diagnosticsData.currentDiagnostics.len:
                continue
              let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[diagnosticIndex]
              if renderedInlineDiagnostic or diagnostic.selection.first.line != realLine:
                continue
              let messageLimit = min(diagnostic.message.len, 500)
              var message = diagnostic.message[0 ..< messageLimit]
              if messageLimit < diagnostic.message.len:
                message.add "..."
              var lineMessageEnd = message.find('\n')
              if lineMessageEnd == -1:
                lineMessageEnd = message.len
              let availableChars = max(
                ((b.currentNode.size.x - xCursor) / storage.charWidth).int - 2, 0)
              let visibleMessageEnd = min(lineMessageEnd, availableChars)
              if visibleMessageEnd <= 0:
                continue
              var inlineMessage = " ■ " & message[0 ..< visibleMessageEnd]
              if visibleMessageEnd < diagnostic.message.len:
                inlineMessage.add "..."
              let diagnosticColor = b.nuiDiagnosticColor(diagnostic.severity)
              b.node:
                discard b.position(xCursor, 0).fit().textStyleIndex(int(UiStyleIndexDefaultText))
                  .textColor(diagnosticColor).text(inlineMessage)
              renderedInlineDiagnostic = true

    b.node:
      discard b.fillX().height(lineH)

    if gutterNodeIdx >= 0 and b.wasRightClicked(gutterNodeIdx, includeChildren = true):
      let mouse = b.frameCtx.input.mouse
      storage.signColumnMenuOpen = true
      storage.signColumnMenuX = mouse.x
      storage.signColumnMenuY = mouse.y

proc buildTextCustomOverlayRowNui(b: var UiBuilder, self: TextDocumentEditor,
    overlay: TextCustomOverlayEntry, gutterWidth, lineHeight: float32): float32 =
  let renderer = self.getCustomOverlayRenderer(overlay.renderId)
  if renderer.isNone:
    return 0.0'f32

  let width = max(b.currentNode.size.x - gutterWidth, 0.0'f32)
  var actualBounds = vec2(width, lineHeight)
  b.layoutHorizontal:
    discard b.fillX().fitY()
    if gutterWidth > 0.0'f32:
      b.node:
        discard b.width(gutterWidth).height(lineHeight)
    b.node:
      discard b.fillX().height(lineHeight)
      actualBounds = renderer.get()(
        overlay.renderId,
        vec2(width, lineHeight),
        overlay.localOffset,
        b)
      discard b.height(max(actualBounds.y, 0.0'f32))
  return actualBounds.y

proc buildInteractiveTextLineNui(b: var UiBuilder, itemIndex: int,
    storage: TextDocumentEditorNuiStorage, self: TextDocumentEditor,
    lineH: var float32, highlightInlineDiff = false) {.nimcall, gcsafe, raises: [].} =
  var realLine = -1
  var firstDisplayRow = -1
  if storage.textIter.displayChunk.isSome:
    realLine = storage.textIter.displayChunk.get.point.row.int
    firstDisplayRow = self.displayMap.toDisplayPoint(point(realLine, 0)).row.int
  let firstRowOfRealLine = realLine >= 0 and firstDisplayRow == itemIndex
  let renderBelow = storage.diagnosticsLocation == core_settings.DiagnosticsLocation.Below or
    (storage.diagnosticsLocation == core_settings.DiagnosticsLocation.LineEndOrBelow and
      realLine == storage.cursorLine)
  let renderBelowDiagnostics = firstRowOfRealLine and renderBelow

  var customOverlays: seq[TextCustomOverlayEntry]
  let customOverlayGutterWidth =
    (if storage.lineNumbers == LineNumbers.None: 0.0'f32 else: storage.gutterWidthPx) +
    storage.signColumnWidthPx
  b.layoutVertical:
    discard b.fillX().fitY()
    if itemIndex == storage.cursorDisplayLine:
      let highlight = storage.baseBackground.lighten(0.05)
      discard b.fillBackground().backgroundColor(rgba(highlight.r.float32,
        highlight.g.float32, highlight.b.float32, highlight.a.float32))
    b.buildInteractiveTextLineHorizontalNui(itemIndex, storage, self, lineH,
      customOverlays, highlightInlineDiff)
    let textLineIndex = b.lastNodeIndex
    var hasAboveOverlays = false
    for overlay in customOverlays:
      if overlay.location == overlay_map.OverlayRenderLocation.Above and
          self.getCustomOverlayRenderer(overlay.renderId).isSome:
        hasAboveOverlays = true
        break
    if hasAboveOverlays:
      b.layoutVertical:
        discard b.fillX().fitY()
        for overlay in customOverlays:
          if overlay.location == overlay_map.OverlayRenderLocation.Above:
            discard b.buildTextCustomOverlayRowNui(
              self, overlay, customOverlayGutterWidth, storage.lineHeight)
      let aboveIndex = b.lastNodeIndex
      # These are the only two children; changing the ring's tail reverses them.
      b.currentNode.lastChild = textLineIndex.int32
      b.frame.nodes[aboveIndex].nextSibling = textLineIndex.int32
      b.frame.nodes[textLineIndex].nextSibling = aboveIndex.int32
      swap(b.frame.nodes[textLineIndex].pos, b.frame.nodes[aboveIndex].pos)
      b.frame.nodes[textLineIndex].pos.y +=
        b.frame.nodes[aboveIndex].size.y - b.frame.nodes[textLineIndex].size.y
    if storage.lineGap != 0.0'f32:
      b.node:
        discard b.fillX().height(storage.lineGap)
    for overlay in customOverlays:
      if overlay.location == overlay_map.OverlayRenderLocation.Below:
        discard b.buildTextCustomOverlayRowNui(
          self, overlay, customOverlayGutterWidth, storage.lineHeight)
    if renderBelowDiagnostics:
      let gutterWidthPx =
        (if storage.lineNumbers == LineNumbers.None: 0.0'f32 else: storage.gutterWidthPx) +
        storage.signColumnWidthPx
      let rowWidth = b.currentNode.size.x
      var belowTextY = lineH + storage.lineGap
      for diagnosticsData in self.document.diagnosticsPerLS.mitems:
        diagnosticsData.diagnosticsPerLine.withValue(realLine, lineDiagnostics):
          for diagnosticIndex in lineDiagnostics[]:
            if diagnosticIndex < 0 or diagnosticIndex >= diagnosticsData.currentDiagnostics.len:
              continue
            let diagnostic {.cursor.} = diagnosticsData.currentDiagnostics[diagnosticIndex]
            let messageLimit = min(diagnostic.message.len, 500)
            var message = diagnostic.message[0 ..< messageLimit]
            if messageLimit < diagnostic.message.len:
              message.add "..."
            let diagnosticColor = b.nuiDiagnosticColor(diagnostic.severity)
            for messageLine in message.splitLines:
              var diagnosticNodeIdx = -1
              b.node:
                diagnosticNodeIdx = b.currentNodeIndex
                discard b.position(gutterWidthPx, belowTextY)
                  .width(max(rowWidth - gutterWidthPx, 1.0'f32))
                  .fitY().wrapText().finishAnchors()
                  .textStyleIndex(int(UiStyleIndexDefaultText))
                  .textColor(diagnosticColor)
                  .text("     ■ " & messageLine)
              belowTextY += b.frame.nodes[diagnosticNodeIdx].size.y
      lineH = max(lineH, belowTextY)

proc buildTextSignColumnMenuNui(b: var UiBuilder, nodeIdx: int,
    userData: int) {.nimcall, gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      let self = storage.editor
      if self.isNil or self.document.isNil or not storage.signColumnMenuOpen:
        return
      b.menu(storage.signColumnMenuOpen, storage.signColumnMenuX, storage.signColumnMenuY):
        if self.platform != nil and self.platform.lineDistanceSetImpl != nil:
          b.label("Line gap")
          var lineGap = self.platform.lineDistance.float32
          if b.dragFloat(lineGap, 1.0'f32, minValue = 0.0'f32):
            self.platform.lineDistance = lineGap.float
            self.platform.requestRender(true)
            self.markDirty()
        b.label("Diagnostic rendering")
        let selectedDiagnosticsLocation = self.config.getUiDiagnosticsLocation()
        if b.button(if selectedDiagnosticsLocation == core_settings.DiagnosticsLocation.LineEnd: "Line End *" else: "Line End"):
          self.config.setUiDiagnosticsLocation(core_settings.DiagnosticsLocation.LineEnd)
          storage.diagnosticsLocation = core_settings.DiagnosticsLocation.LineEnd
          storage.signColumnMenuOpen = false
          self.markDirty()
        if b.button(if selectedDiagnosticsLocation == core_settings.DiagnosticsLocation.Below: "Below *" else: "Below"):
          self.config.setUiDiagnosticsLocation(core_settings.DiagnosticsLocation.Below)
          storage.diagnosticsLocation = core_settings.DiagnosticsLocation.Below
          storage.signColumnMenuOpen = false
          self.markDirty()
        if b.button(if selectedDiagnosticsLocation == core_settings.DiagnosticsLocation.LineEndOrBelow: "Line End or Below *" else: "Line End or Below"):
          self.config.setUiDiagnosticsLocation(core_settings.DiagnosticsLocation.LineEndOrBelow)
          storage.diagnosticsLocation = core_settings.DiagnosticsLocation.LineEndOrBelow
          storage.signColumnMenuOpen = false
          self.markDirty()
        b.label("Context lines")
        let selectedContextLineMode = self.config.getContextLinesStyle()
        if b.button(if selectedContextLineMode == "lines": "Lines *" else: "Lines"):
          self.config.setContextLinesStyle("lines")
          storage.signColumnMenuOpen = false
          self.markDirty()
        if b.button(if selectedContextLineMode == "breadcrumb": "Breadcrumbs *" else: "Breadcrumbs"):
          self.config.setContextLinesStyle("breadcrumb")
          storage.signColumnMenuOpen = false
          self.markDirty()
        b.label("Sign column")
        # todo: use dropdown, but right now there's a bug clicking doesn't work
        let selectedMode = self.config.getTextSignsShow()
        if b.button(if selectedMode == core_settings.SignColumnShowKind.Auto: "Auto *" else: "Auto"):
          self.config.setTextSignsShow(core_settings.SignColumnShowKind.Auto)
          storage.signColumnShow = core_settings.SignColumnShowKind.Auto
          storage.signColumnMenuOpen = false
          self.markDirty()
        if b.button(if selectedMode == core_settings.SignColumnShowKind.Yes: "Yes *" else: "Yes"):
          self.config.setTextSignsShow(core_settings.SignColumnShowKind.Yes)
          storage.signColumnShow = core_settings.SignColumnShowKind.Yes
          storage.signColumnMenuOpen = false
          self.markDirty()
        if b.button(if selectedMode == core_settings.SignColumnShowKind.No: "No *" else: "No"):
          self.config.setTextSignsShow(core_settings.SignColumnShowKind.No)
          storage.signColumnShow = core_settings.SignColumnShowKind.No
          storage.signColumnMenuOpen = false
          self.markDirty()
        if b.button(if selectedMode == core_settings.SignColumnShowKind.Number: "Number *" else: "Number"):
          self.config.setTextSignsShow(core_settings.SignColumnShowKind.Number)
          storage.signColumnShow = core_settings.SignColumnShowKind.Number
          storage.signColumnMenuOpen = false
          self.markDirty()
    except:
      discard

proc nuiTextTrailingSpaceHeight(editorHeight, lineHeight: float32): float32 =
  max(0.0'f32, editorHeight - 5.0'f32 * lineHeight)

proc buildTextDiffLineNui(b: var UiBuilder, itemIndex: int,
    userData: int) {.nimcall, gcsafe, raises: [].} =
  discard b.fillX().fitY()
  {.cast(gcsafe).}:
    try:
      let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      let self = storage.editor
      if itemIndex == storage.displayLineCount:
        discard b.fitY(false).height(nuiTextTrailingSpaceHeight(
          b.frame.nodes[userData].size.y, storage.lineHeight))
        return
      if storage.diffIterNextRow != itemIndex:
        storage.diffTextIter.seekLine(itemIndex)
        discard storage.diffTextIter.next()
      let arenaCheckpoint = storage.arena.checkpoint()
      defer: storage.arena.restoreCheckpoint(arenaCheckpoint)
      let lineNumbers = storage.lineNumbers
      let cursorLine = storage.cursorLine
      # Cursor line mapped onto the diff side (legacy diffState.cursorLine at
      # widget_builder_text_document.nim:1478).
      var diffCursorLine = -1
      try:
        if self.diffChanges.isSome:
          let m = self.diffChanges.get.mapLine(cursorLine, true)
          if m.isSome:
            diffCursorLine = m.get.line
      except:
        discard
      # Real lines + first display rows for line numbers (legacy drawLineNumber).
      var realDiff = -1
      var firstDiff = -1
      if storage.diffTextIter.displayChunk.isSome:
        try:
          realDiff = storage.diffTextIter.displayChunk.get.point.row.int
          firstDiff = self.diffDisplayMap.toDisplayPoint(point(realDiff, 0)).row.int
        except:
          discard
      let baseFontSize = b.themeTextStyle(int(UiStyleIndexDefaultText))[].fontSize
      let gutterPx = storage.gutterWidthPx
      # Line-number digits per side (frame-arena, zero-alloc like single path).
      var showNumDiff = false
      var numBufDiff: ptr UncheckedArray[char]
      var numLenDiff = 0
      if lineNumbers != LineNumbers.None and realDiff >= 0 and firstDiff == itemIndex:
        var num = -1
        if diffCursorLine == realDiff:
          num = realDiff + 1
        elif lineNumbers == LineNumbers.Absolute:
          num = realDiff + 1
        elif lineNumbers == LineNumbers.Relative:
          num = abs((realDiff + 1) - diffCursorLine)
        if num >= 0:
          showNumDiff = true
          let t = b.nuiArenaIntText(num)
          numBufDiff = t.buf
          numLenDiff = t.len
      let isContDiff = realDiff >= 0 and firstDiff != itemIndex
      var indentDiff = 0.0'f32
      if showNumDiff:
        indentDiff = gutterPx
      elif isContDiff:
        indentDiff = gutterPx
        var wrapIndentCols = 4
        try:
          if self.diffDisplayMap.wrapMap != nil:
            wrapIndentCols = self.diffDisplayMap.wrapMap.snapshot.wrappedIndent
        except:
          discard
        indentDiff += wrapIndentCols.float32 * storage.charWidth
      # Whole-line backgrounds per side (legacy drawDiffBackgrounds).
      let (bgL, hasBgL) = self.nuiDiffLineBackground(storage, itemIndex, true)
      let bgLUi = rgba(bgL.r.float32, bgL.g.float32, bgL.b.float32, bgL.a.float32)
      b.node:
        discard b.fillX().fitY()
        b.layoutVertical:
          discard b.fillX().fitY()
          if hasBgL:
            discard b.fillBackground().backgroundColor(bgLUi)
          b.layoutHorizontal:
            discard b.fillX().fitY()
            if showNumDiff:
              b.layoutHorizontalReverse:
                discard b.width(gutterPx).fitY()
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(toOpenArray(numBufDiff, 0, numLenDiff - 1))
            elif isContDiff:
              b.node:
                discard b.width(indentDiff).fitY()
            var hasChunks = false
            while storage.diffTextIter.displayChunk.isSome:
              let chunk = storage.diffTextIter.displayChunk.get
              if chunk.displayPoint.row.int != itemIndex:
                break
              let styled = chunk.styledChunk
              let chunkColor = styled.color
              let chunkScale = styled.fontScale
              let chunkTextFlags = nuiChunkTextFlags(styled.fontStyle, styled.underline.isSome)
              var underlineUiColor = rgba(chunkColor.r.float32, chunkColor.g.float32, chunkColor.b.float32, chunkColor.a.float32)
              if styled.underline.getSome(underline):
                underlineUiColor = rgba(underline.color.r.float32, underline.color.g.float32,
                  underline.color.b.float32, underline.color.a.float32)
              let chunkPoint = chunk.point
              let chunkEndPoint = chunk.endPoint
              discard storage.diffTextIter.next()
              if chunk.len == 0:
                continue
              hasChunks = true
              let uiColor = rgba(chunkColor.r.float32, chunkColor.g.float32, chunkColor.b.float32, chunkColor.a.float32)
              let (hlBg, hasHl) = self.nuiDiffChunkHighlight(storage, chunkPoint, chunkEndPoint, true)
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText))
                if hasHl:
                  discard b.fillBackground().backgroundColor(rgba(hlBg.r.float32, hlBg.g.float32, hlBg.b.float32, hlBg.a.float32))
                discard b.textColor(uiColor).textFlags(chunkTextFlags).underlineColor(underlineUiColor).underlineThickness(2)
                  .fontSize(baseFontSize * chunkScale.float32).text(chunk.toOpenArray)
            if not hasChunks:
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(" ")
          if storage.lineGap != 0.0'f32:
            b.node:
              discard b.fillX().height(storage.lineGap)
      storage.diffIterNextRow = itemIndex + 1
    except CatchableError as e:
      log lvlError, "Failed to render diff line: ", e.msg

proc cacheTextTrailingSpaceHeight(storage: TextDocumentEditorNuiStorage,
    editorHeight: float32) =
  if storage.fitContentY:
    return
  let list = storage.listStorage
  while list.heights.len > 0 and list.heights[^1].itemIndex >= storage.displayLineCount:
    list.measuredHeightTotal -= list.heights[^1].height
    list.heights.setLen(list.heights.len - 1)
  let height = nuiTextTrailingSpaceHeight(editorHeight, storage.lineHeight)
  list.heights.add UiDynamicVirtualListHeight(
    itemIndex: storage.displayLineCount, height: height)
  list.measuredHeightTotal += height

proc nuiTextScrollbarSpan(storage: TextDocumentEditorNuiStorage,
    firstRow, endRow: int, editorHeight: float32): tuple[yFrac, hFrac: float32] =
  let list = storage.listStorage
  var totalHeight = list.itemTop(storage.displayLineCount)
  if not storage.fitContentY:
    # The spacer may not have been built yet, or its cached height may predate a resize.
    totalHeight += nuiTextTrailingSpaceHeight(editorHeight, storage.lineHeight)
  let firstY = list.itemTop(firstRow)
  let endY = list.itemTop(endRow)
  let denominator = max(1.0'f32, totalHeight)
  (firstY / denominator, (endY - firstY) / denominator)

proc nuiPopupAnchor(b: var UiBuilder, storage: TextDocumentEditorNuiStorage,
    p: Point, xOffset: float32 = 0.0'f32): tuple[cx: float32, cy: float32, found: bool] {.nimcall, gcsafe, raises: [].}

proc requestTextCursorVisibleXNui(b: var UiBuilder, itemIndex: int,
    storage: TextDocumentEditorNuiStorage) =
  let editor = storage.editor
  let tec = editor.textEditorComponent
  if tec == nil or tec.nuiPendingScrollToX.isNone:
    return
  if editor.config.getTextWrapLines() or editor.disableScrolling:
    tec.nuiPendingScrollToX = Point.none
    return
  let point = tec.nuiPendingScrollToX.get
  if editor.displayMap.toDisplayPoint(point).row.int != itemIndex:
    return
  let anchor = b.nuiPopupAnchor(storage, point)
  if not anchor.found:
    return
  let cursorX = anchor.cx + storage.listStorage.scrollOffsetX
  let cursorWidth =
    if b.backendType == UiBackendType.Terminal: 1.0'f32
    elif editor.isThickCursor(): storage.charWidth
    else: storage.charWidth * 0.2'f32
  storage.listStorage.requestHorizontalRangeVisible(cursorX, cursorX + cursorWidth)
  tec.nuiPendingScrollToX = Point.none

proc buildTextLineNui(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  discard b.fillX().fitY()
  {.cast(gcsafe).}:
    prof("buildTextLineNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      let viewportIndex = int(b.currentNode.parent)
      storage.listStorage = b.getOrCreateDynamicVirtualListStorage(b.frame.nodes[viewportIndex].addr)
      if itemIndex == storage.displayLineCount:
        discard b.fitY(false).height(nuiTextTrailingSpaceHeight(
          b.frame.nodes[userData].size.y, storage.lineHeight))
        return
      var self = storage.editor
      if self.isNil or self.displayMap.isNil or self.document.isNil:
        b.layoutHorizontal:
          discard b.fillX().fitY()
          b.node:
            discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text("")
        return
      # Stored iterator reused across lines (created once per frame in createUINui):
      # only seek when the frontier does not match; rows arrive ascending so the
      # frontier only moves forward, which keeps every level's forward-only seeks
      # and atEnd flags sound.
      if storage.iterNextRow != itemIndex:
        storage.textIter.seekLine(itemIndex)
        discard storage.textIter.next()
      let arenaCheckpoint = storage.arena.checkpoint()
      var lineH = storage.lineHeight
      if storage.renderDiff:
        let (bg, hasBg) = self.nuiDiffLineBackground(storage, itemIndex, false)
        if hasBg:
          discard b.fillBackground().backgroundColor(
            rgba(bg.r.float32, bg.g.float32, bg.b.float32, bg.a.float32))
      b.buildInteractiveTextLineNui(itemIndex, storage, self, lineH, storage.renderDiff)
      b.requestTextCursorVisibleXNui(itemIndex, storage)
      storage.arena.restoreCheckpoint(arenaCheckpoint)
    except:
      discard

proc buildTextLinesListNui(b: var UiBuilder, rootIndex, lineCount: int,
    fitContentY: bool): UiDynamicVirtualListStorage =
  let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[rootIndex].addr)
  if storage.listStorage != nil and not storage.fitContentY and
      storage.displayLineCount != lineCount:
    let list = storage.listStorage
    if list.heights.len > 0 and list.heights[^1].itemIndex == storage.displayLineCount:
      list.measuredHeightTotal -= list.heights[^1].height
      list.heights.setLen(list.heights.len - 1)
  storage.displayLineCount = lineCount
  storage.fitContentY = fitContentY
  let editor = storage.editor
  let revision = if editor.document != nil: editor.document.revision else: 0
  let diffRevision = if editor.diffDocument != nil: editor.diffDocument.revision else: 0
  if storage.widthDocument != editor.document or storage.widthRevision != revision or
      storage.diffWidthDocument != editor.diffDocument or storage.diffWidthRevision != diffRevision:
    storage.listStorage.clearMeasuredWidths()
    storage.diffListStorage.clearMeasuredWidths()
    storage.widthDocument = editor.document
    storage.widthRevision = revision
    storage.diffWidthDocument = editor.diffDocument
    storage.diffWidthRevision = diffRevision
  if storage.renderDiff:
    b.node("text-current-pane"):
      discard b.anchorsX(0.5, 1).finishAnchors()
      if fitContentY: discard b.fitY()
      else: discard b.fillY()
      storage.textListNodeIndex = b.frame.nodes.len
      result = b.dynamicVirtualList(lineCount + ord(not fitContentY),
        storage.itemHeightHint, buildTextLineNui, rootIndex,
        horizontalScroll = not editor.config.getTextWrapLines(), synchronized = true)
    b.node("text-diff-pane"):
      discard b.anchorsX(0, 0.5).finishAnchors()
      if fitContentY: discard b.fitY()
      else: discard b.fillY()
      storage.diffListNodeIndex = b.frame.nodes.len
      storage.diffListStorage = b.dynamicVirtualList(lineCount + ord(not fitContentY),
        storage.itemHeightHint, buildTextDiffLineNui, rootIndex,
        horizontalScroll = not editor.config.getTextWrapLines(), synchronizeWith = result)
  else:
    storage.textListNodeIndex = b.frame.nodes.len
    result = b.dynamicVirtualList(lineCount + ord(not fitContentY),
      storage.itemHeightHint, buildTextLineNui, rootIndex,
      horizontalScroll = not editor.config.getTextWrapLines())
  storage.listStorage = result
  storage.cacheTextTrailingSpaceHeight(b.frame.nodes[rootIndex].size.y)

proc isRealDisplayRow(displayMap: DisplayMap, row: int): bool =
  ## False for synthetic rows (diff gap rows) which don't start a buffer line
  ## segment of their own.
  try:
    displayMap.toDisplayPoint(displayMap.toPoint(displayPoint(row, 0))).row.int == row
  except:
    false

proc captureScrollAnchorNui(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage) =
  ## Remember which buffer position is shown where in the viewport, so the next
  ## frame can restore it after the display map changed (reload, rewrap, diff).
  let tec = self.textEditorComponent
  let listStorage = storage.listStorage
  let displayMap = self.displayMap
  if tec.isNil or listStorage.isNil or displayMap.isNil or storage.fitContentY:
    return
  try:
    let visible = listStorage.visibleItemRange()
    let lastRow = displayMap.endDisplayPoint.row.int
    if visible.last < visible.first:
      return
    let first = clamp(visible.first, 0, lastRow)
    let last = clamp(visible.last, first, lastRow)

    var row = -1
    # Prefer the cursor line so it stays put while the content around it changes.
    if self.selections.len > 0:
      let cursorRow = displayMap.toDisplayPoint(self.selection.last.toPoint).row.int
      if cursorRow >= first and cursorRow <= last:
        row = cursorRow
    if row < 0:
      for r in first..last:
        if listStorage.itemTop(r) >= listStorage.scrollOffsetY - 0.5'f32 and displayMap.isRealDisplayRow(r):
          row = r
          break
    if row < 0:
      row = first

    let point = displayMap.toPoint(displayPoint(row, 0))
    tec.scrollAnchor = TextScrollAnchor(
      valid: true,
      anchor: displayMap.buffer.anchorBefore(point),
      point: point,
      pixelOffset: listStorage.itemTop(row) - listStorage.scrollOffsetY,
      mapVersion: displayMap.version,
    )

    let endPoint = displayMap.toPoint(min(displayPoint(last + 1, 0), displayMap.endDisplayPoint))
    tec.nuiVisibleTextRange = (displayMap.toPoint(displayPoint(first, 0))...endPoint).some
  except:
    discard

proc restoreScrollAnchorNui(self: TextDocumentEditor, storage: TextDocumentEditorNuiStorage) =
  ## If the display map changed since the anchor was captured, rows were
  ## renumbered: drop cached row heights and move the scroll offset so the
  ## anchored buffer position is at the same pixel offset as before.
  let tec = self.textEditorComponent
  let listStorage = storage.listStorage
  let displayMap = self.displayMap
  if tec.isNil or listStorage.isNil or displayMap.isNil or storage.fitContentY:
    return
  if not tec.scrollAnchor.valid:
    return
  try:
    let version = displayMap.version
    if version == tec.scrollAnchor.mapVersion:
      # Renderer/diagnostic heights can change without renumbering display rows.
      listStorage.preserveItemAnchorAfterMeasurement(
        displayMap.toDisplayPoint(tec.scrollAnchor.point).row.int)
      return

    let buffer {.cursor.} = displayMap.buffer
    var point = tec.scrollAnchor.point
    var resolved = false
    if buffer.canResolve(tec.scrollAnchor.anchor):
      let p = tec.scrollAnchor.anchor.summaryOpt(Point, buffer, resolveDeleted = false)
      if p.isSome:
        point = p.get
        resolved = true
    if not resolved:
      point = buffer.visibleText.clipPoint(point, Bias.Left)

    let row = displayMap.toDisplayPoint(point).row.int
    listStorage.clearMeasuredHeights()
    let target = listStorage.itemTop(row) - tec.scrollAnchor.pixelOffset
    listStorage.shiftScrollOffset(target - listStorage.scrollOffsetY)
    listStorage.preserveItemAnchorAfterMeasurement(row)

    tec.scrollAnchor.point = point
    tec.scrollAnchor.anchor = buffer.anchorBefore(point)
    tec.scrollAnchor.mapVersion = version
  except:
    discard

proc appendTextHighlightNui(b: var UiBuilder, storage: TextDocumentEditorNuiStorage,
    selection: Selection, highlightColor: Color, drawEmpty: bool, xOffset: float32 = 0.0'f32) =
  let normalized = selection.normalized
  let selectionStart = normalized.first.toPoint
  let selectionEnd = normalized.last.toPoint
  let empty = normalized.isEmpty
  if empty and not drawEmpty:
    return

  let uiColor = rgba(highlightColor.r.float32, highlightColor.g.float32,
    highlightColor.b.float32, highlightColor.a.float32)
  var rects: seq[tuple[x, y, w, h: float32]] = @[]
  var terminalTextNodes: seq[int] = @[]
  for entry in storage.chunkIndex:
    if empty:
      if selectionStart < entry.point or selectionStart > entry.endPoint:
        continue
    elif entry.endPoint < selectionStart or entry.point >= selectionEnd:
      continue
    if entry.nodeIndex < 0 or entry.nodeIndex >= b.frame.nodes.len:
      continue
    let chunkNode = b.frame.nodes[entry.nodeIndex].addr
    let textSlot = int(chunkNode.textIndex)
    if textSlot <= 0 or textSlot > b.frame.texts.len:
      continue
    let nodeText = b.frame.texts[textSlot - 1]
    let chunkText = nodeText.text.value
    var firstByte = 0
    var lastByte = chunkText.len
    if selectionStart > entry.point and selectionStart.row == entry.point.row:
      firstByte = entry.renderedByteOffset(chunkText, selectionStart.column.int - entry.point.column.int)
    if selectionEnd < entry.endPoint and selectionEnd.row == entry.point.row:
      lastByte = entry.renderedByteOffset(chunkText, selectionEnd.column.int - entry.point.column.int)
    if lastByte < firstByte or (lastByte == firstByte and not empty):
      continue

    let firstX = b.nuiMeasuredPrefixWidth(chunkText, firstByte, nodeText)
    let lastX = b.nuiMeasuredPrefixWidth(chunkText, lastByte, nodeText)
    # In diff view the indexed (right pane) chunks are pane-relative; the
    # highlight layer spans both panes, so shift by half the layer width.
    var x = entry.posX + xOffset + firstX
    var y = entry.posY
    var w = max(lastX - firstX, ceil(storage.charWidth * 0.25'f32))
    var h = max(storage.lineHeight, chunkNode.size.y) + storage.lineGap
    if b.backendType == UiBackendType.Terminal:
      x = floor(x)
      y = floor(y)
      w = max(ceil(entry.posX + xOffset + lastX) - x, 1.0'f32)
      h = 1.0'f32
      if entry.nodeIndex notin terminalTextNodes:
        terminalTextNodes.add entry.nodeIndex
    if rects.len > 0 and rects[^1].y == y and rects[^1].h == h and
        abs((rects[^1].x + rects[^1].w) - x) < 0.1'f32:
      rects[^1].w += w
    else:
      rects.add (x, y, w, h)
    if empty:
      break

  for bounds in rects:
    var command = UiRenderCommand(kind: CmdRectFill, color: uiColor)
    command.pos.x = bounds.x
    command.pos.y = bounds.y
    command.size.x = bounds.w
    command.size.y = bounds.h
    storage.highlightCommands.add command

  # Terminal rectangle fills replace the glyph in each covered cell. Repaint
  # affected chunks after their background fills so selected text stays legible.
  if b.backendType == UiBackendType.Terminal:
    for entry in storage.chunkIndex:
      if entry.nodeIndex notin terminalTextNodes or entry.nodeIndex < 0 or
          entry.nodeIndex >= b.frame.nodes.len:
        continue
      let chunkNode = b.frame.nodes[entry.nodeIndex].addr
      if chunkNode.textIndex == 0:
        continue
      var command = UiRenderCommand(kind: CmdText, textIndex: chunkNode.textIndex)
      command.pos.x = floor(entry.posX + xOffset)
      command.pos.y = floor(entry.posY)
      storage.highlightCommands.add command

proc buildTextHighlightsNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, raises: [].} =
  ## Highlight backgrounds share one deferred command layer. The cursor layer is
  ## declared after this one, so cursors always paint on top.
  {.cast(gcsafe).}:
    prof("buildTextHighlightsNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      let storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      if storage.listStorage != nil and (storage.renderDiff or
          storage.listStorage.horizontalScrollbarTrackIndex >= 0):
        discard b.fillX(false).fillY(false).size(
          storage.listStorage.viewportWidth, storage.listStorage.viewportHeight).maskChildren()
        if storage.renderDiff:
          discard b.position(storage.diffSplitWidth, 0)
      if storage.listStorage != nil:
        let viewportIndex = b.firstChildIndex(storage.textListNodeIndex)
        let viewportY = b.absoluteNodePos(viewportIndex).y
        for entry in storage.chunkIndex.mitems:
          entry.posY = b.absoluteNodePos(entry.nodeIndex).y - viewportY
      let self = storage.editor
      if not self.isNil and self.textEditorComponent != nil and storage.listStorage != nil:
        let visibleRange = storage.listStorage.visibleItemRange()
        self.textEditorComponent.nuiVisibleDisplayRange =
          (visibleRange.first, min(visibleRange.last, storage.displayLineCount - 1)).some
        self.captureScrollAnchorNui(storage)
      if self.isNil or self.document.isNil or storage.theme.isNil or
          not self.document.isInitialized or storage.chunkIndex.len == 0:
        return

      storage.highlightCommands.setLen(0)
      # Chunk coordinates and this clipped layer are current-pane-relative.
      var diffXOffset = 0.0'f32
      if storage.listStorage != nil:
        diffXOffset -= storage.listStorage.scrollOffsetX
      for highlights in self.decorations.customHighlights.values:
        for highlight in highlights:
          let highlightColor = b.highlightStyleColor(highlight.color).toColor * highlight.tint
          b.appendTextHighlightNui(storage, highlight.selection, highlightColor, true, diffXOffset)

      let selectionColor = b.themeStyle(UiStyleIndexSelection)[].fillColor.toColor
      let inclusive = self.config.get("text.inclusive-selection", false)
      let thick = self.isThickCursor()
      for selection in self.selections:
        var selection = selection.normalized
        if thick and inclusive:
          selection.last.column += 1
        b.appendTextHighlightNui(storage, selection, selectionColor, false, diffXOffset)

      if storage.highlightCommands.len > 0:
        discard b.customRenderCommands(storage.highlightCommands)
    except:
      discard

proc buildTextCursorNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, raises: [].} =
  ## Cursor overlay, deferred after the virtual list (registered after it, so chunk
  ## index positions and node sizes are final). One rect per selection cursor plus
  ## rune inversion for block cursors (mirrors legacy drawCursors).
  {.cast(gcsafe).}:
    prof("buildTextCursorNui")
    try:
      discard b.noHover().noChildHover()
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if storage.listStorage != nil and (storage.renderDiff or
          storage.listStorage.horizontalScrollbarTrackIndex >= 0):
        discard b.fillX(false).fillY(false).size(
          storage.listStorage.viewportWidth, storage.listStorage.viewportHeight).maskChildren()
        if storage.renderDiff:
          discard b.position(storage.diffSplitWidth, 0)
      if self.isNil or self.displayMap.isNil or self.document.isNil or storage.theme.isNil:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0 or not self.cursorVisible:
        return
      # TODO(nui-text): cursor trail animation (cursorHistories + markDirty loop),
      # lastCursorLocationBounds / hover + signature-help anchors (§14).
      let cursorFg = b.themeTextStyle(UiStyleIndexCursorText)[].textColor.toColor
      let cursorBg = b.themeStyle(UiStyleIndexCursor)[].fillColor.toColor
      let fgUi = rgba(cursorFg.r.float32, cursorFg.g.float32, cursorFg.b.float32, cursorFg.a.float32)
      let bgUi = rgba(cursorBg.r.float32, cursorBg.g.float32, cursorBg.b.float32, cursorBg.a.float32)
      let charW = storage.charWidth
      let thick = self.isThickCursor()
      # Chunk coordinates and this clipped layer are current-pane-relative.
      var diffXOffset = 0.0'f32
      if storage.listStorage != nil:
        diffXOffset -= storage.listStorage.scrollOffsetX
      for s in self.selections:
        let p = s.last.toPoint
        # Last entry starting at/before the cursor on its row (entries are built in
        # display order, like legacy Bias.Left search; off-screen cursor → skip).
        var best = -1
        for i, e in storage.chunkIndex:
          if e.point.row.int != p.row.int:
            continue
          if e.point.column.int <= p.column.int:
            best = i
          else:
            break
        if best < 0:
          continue
        let e = storage.chunkIndex[best]
        if e.nodeIndex < 0 or e.nodeIndex >= b.frame.nodes.len:
          continue
        let entryNode = b.frame.nodes[e.nodeIndex].addr
        let textSlot = int(entryNode.textIndex)
        if textSlot <= 0 or textSlot > b.frame.texts.len:
          continue
        let nt = b.frame.texts[textSlot - 1].addr
        let nodeText = nt.text.value
        # Exact x via substring measurement with the chunk's own font (same shaper
        # that draws the node, so positions match what is rendered).
        let byteOff = e.renderedByteOffset(nodeText, p.column.int - e.point.column.int)
        var prefixW = 0.0'f32
        if byteOff > 0:
          var tmp = UiNodeText(text: nodeText[0 ..< byteOff].uiString, fontId: nt.fontId, fontSize: nt.fontSize)
          let arr = b.getTextArrangement(tmp.addr, -1)
          if arr != nil:
            prefixW = arr.size.x
        var cx = e.posX + diffXOffset + prefixW
        var cy = e.posY
        var ch = max(storage.lineHeight, entryNode.size.y) + storage.lineGap
        var cw = if thick: charW else: charW * 0.2'f32
        if b.backendType == UiBackendType.Terminal:
          cx = floor(cx)
          cy = floor(cy)
          ch = 1.0'f32
          cw = 1.0'f32
        b.node:
          discard b.position(cx, cy).size(cw, ch).fillBackground().backgroundColor(fgUi)
        if thick:
          let r = if e.replacementGlyphLen > 0 and byteOff < nodeText.len:
              nodeText.runeAt(byteOff)
            else:
              self.document.runeAt(s.last)
          if r != 0.Rune and r.int >= ' '.int:
            b.node:
              discard b.position(cx, cy).fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(bgUi).fontSize(nt.fontSize).text($r)
    except:
      discard

proc nuiPopupAnchor(b: var UiBuilder, storage: TextDocumentEditorNuiStorage,
    p: Point, xOffset: float32): tuple[cx: float32, cy: float32, found: bool] {.nimcall, gcsafe, raises: [].} =
  ## Viewport-relative anchor for a buffer point, mirroring the cursor lookup in
  ## buildTextCursorNui (last chunk entry starting at/before the point on its
  ## row, exact x via substring measurement with the chunk's own font).
  {.cast(gcsafe).}:
    try:
      var best = -1
      for i, e in storage.chunkIndex:
        if e.point.row.int != p.row.int:
          continue
        if e.point.column.int <= p.column.int:
          best = i
        else:
          break
      if best < 0:
        return (0.0'f32, 0.0'f32, false)
      let e = storage.chunkIndex[best]
      let scrollX = if storage.listStorage != nil: storage.listStorage.scrollOffsetX else: 0.0'f32
      if e.nodeIndex < 0 or e.nodeIndex >= b.frame.nodes.len:
        return (0.0'f32, 0.0'f32, false)
      let entryNode = b.frame.nodes[e.nodeIndex].addr
      let textSlot = int(entryNode.textIndex)
      if textSlot <= 0 or textSlot > b.frame.texts.len:
        return (e.posX + xOffset - scrollX, e.posY, true)
      let nt = b.frame.texts[textSlot - 1].addr
      let nodeText = nt.text.value
      let byteOff = e.renderedByteOffset(nodeText, p.column.int - e.point.column.int)
      var prefixW = 0.0'f32
      if byteOff > 0:
        var tmp = UiNodeText(text: nodeText[0 ..< byteOff].uiString, fontId: nt.fontId, fontSize: nt.fontSize)
        let arr = b.getTextArrangement(tmp.addr, -1)
        if arr != nil:
          prefixW = arr.size.x
      return (e.posX + xOffset + prefixW - scrollX, e.posY, true)
    except:
      return (0.0'f32, 0.0'f32, false)

proc nuiOverlayExtent(b: var UiBuilder, nodeIdx: int): tuple[w, h: float32] {.nimcall, gcsafe, raises: [].} =
  result = (1.0'f32, 1.0'f32)
  try:
    let overlayIdx = b.currentNodeIndex(b.overlays)
    if overlayIdx >= 0 and overlayIdx < b.frame.nodes.len:
      result.w = max(b.frame.nodes[overlayIdx].size.x, 1.0'f32)
      result.h = max(b.frame.nodes[overlayIdx].size.y, 1.0'f32)
    elif nodeIdx >= 0 and nodeIdx < b.frame.nodes.len:
      result.w = max(b.frame.nodes[nodeIdx].size.x, 1.0'f32)
      result.h = max(b.frame.nodes[nodeIdx].size.y, 1.0'f32)
  except:
    discard

proc nuiPopupPlacement(b: var UiBuilder, nodeIdx: int, anchorX, anchorY,
    lineHeight, desiredWidth, desiredHeight: float32): tuple[x, y, w, h: float32] {.nimcall, gcsafe, raises: [].} =
  let extent = b.nuiOverlayExtent(nodeIdx)
  result.w = min(max(desiredWidth, 1.0'f32), extent.w)
  result.h = min(max(desiredHeight, 1.0'f32), extent.h)
  result.x = anchorX
  result.y = anchorY + lineHeight
  try:
    let layerPos = b.absoluteNodePos(nodeIdx)
    result.x += layerPos.x
    result.y += layerPos.y
  except:
    discard
  if result.x + result.w > extent.w:
    result.x = extent.w - result.w
  if result.y + result.h > extent.h:
    var anchorAbsY = anchorY
    try:
      anchorAbsY += b.absoluteNodePos(nodeIdx).y
    except:
      discard
    let aboveY = anchorAbsY - result.h
    result.y = if aboveY >= 0.0'f32: aboveY else: extent.h - result.h
  result.x = max(result.x, 0.0'f32)
  result.y = max(result.y, 0.0'f32)
  if b.backendType == UiBackendType.Terminal:
    result.x = floor(result.x)
    result.y = floor(result.y)
    result.w = floor(result.w)
    result.h = floor(result.h)

proc buildCompletionRowNui(b: var UiBuilder, itemIndex: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Single completion row for the listTable popup (userData is the text-root
  ## node index, like buildTextLineNui). The deferred list build already wraps
  ## each item in a positioned node, so the current node IS the row: style it
  ## directly (full-row background) and emit one child node per cell
  ## (label + source/detail) – no horizontal wrapper, listTableColumnLayout
  ## aligns cells into columns across the rendered batch. Completion match
  ## colors are derived from the selected/unselected text style slots.
  # todo: reverse order
  discard b.fillX().fitY()
  {.cast(gcsafe).}:
    prof("buildCompletionRowNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil:
        return
      if itemIndex < 0 or itemIndex >= self.completionMatches.len:
        return
      let maxLabelLen = if b.backendType == UiBackendType.Terminal: 24 else: 30
      let maxTypeLen = if b.backendType == UiBackendType.Terminal: 22 else: 30
      let completion {.cursor.} = self.completions[self.completionMatches[itemIndex].index]
      let isSel = itemIndex == self.selectedCompletion
      discard b.fillBackground().styleIndex(if isSel: UiStyleIndexMenuItemHover else: UiStyleIndexMenuItem)
      let labelStyle = if isSel: UiStyleIndexMenuItemHoverText else: UiStyleIndexMenuItemText
      let label = if completion.item.label.len < maxLabelLen:
          completion.item.label
        else:
          completion.item.label[0..<(maxLabelLen - 3)] & "..."
      let matchIndices = self.getCompletionMatches(itemIndex)
      let labelColor = b.themeTextStyle(labelStyle)[].textColor
      let highlightColor = b.themeStyle(UiStyleIndexAccent)[].fillColor
      b.highlightedText(label, matchIndices, labelColor, highlightColor)
      let detail = if completion.item.detail.getSome(d):
          if d.len < maxTypeLen: d else: d[0..<(maxTypeLen - 3)] & "..."
        else:
          ""
      var detailText = completion.source & " " & detail
      if b.backendType == UiBackendType.Terminal and detailText.len > maxTypeLen:
        detailText = detailText[0..<(maxTypeLen - 3)] & "..."
      b.node:
        discard b.fit().textStyleIndex(int(UiStyleIndexMutedText)).text(detailText)
      if b.wasPressed(includeChildren = true):
        self.selectedCompletion = itemIndex
        self.markDirty()
    except:
      discard

proc buildTextCompletionsNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Completion popup, deferred after the virtual list so chunk-index anchors are
  ## final (mirrors legacy createCompletions at widget_builder_text_document:288).
  ## Rows render virtualized via listTable (nested deferred build, picked up by
  ## the flush loop in the same frame; columns Fit/Fit so source/detail aligns
  ## across the rendered batch); docs for the selected item render in
  ## a panel to the right of the list, same height (mirrors legacy x = listNode.xw).
  ## If the popup would overflow the layer below the cursor it flips above the
  ## cursor line (mirrors legacy createCompletions reverse/pivot and the
  ## dropdownPopupReposition clamp in nuigi/widgets.nim).
  ## The popup attaches to the overlay node (like dropdown-popup) so it paints
  ## above the editor layout and is not clipped by it: the layer-relative
  ## anchor is converted to absolute coords via absoluteNodePos and clamped
  ## against the overlay size.
  ## v1 parity note: fuzzy-match highlight not yet ported.
  {.cast(gcsafe).}:
    prof("buildTextCompletionsNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil:
        return
      if not self.showCompletions or not self.active or self.completionMatches.len == 0:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0:
        return
      let lineH = if storage.lineHeight > 0.0'f32: storage.lineHeight else: textLineHeightHint
      # In diff view the cursor lives in the right pane; shift the anchor by
      # the diff split width.
      var diffXOffset = 0.0'f32
      if storage.renderDiff:
        diffXOffset = storage.diffSplitWidth
      let anchor = b.nuiPopupAnchor(storage, self.selection.last.toPoint, diffXOffset)
      if not anchor.found:
        return
      const maxLabelLen = 30
      const numLinesToShow = 15
      const docsWidthChars = 75.0'f32
      let totalRows = self.completionMatches.len
      var docText = ""
      if self.selectedCompletion >= 0 and self.selectedCompletion < self.completionMatches.len:
        let sel = self.completions[self.completionMatches[self.selectedCompletion].index]
        if sel.item.label.len >= maxLabelLen:
          docText.add sel.item.label
          docText.add "\n"
        if sel.item.detail.getSome(detail):
          docText.add detail
        if sel.item.documentation.getSome(doc):
          if docText.len > 0:
            docText.add "\n\n"
          if doc.asString().getSome(docStr):
            docText.add docStr
          elif doc.asMarkupContent().getSome(markup):
            docText.add markup.value
      let charW = max(storage.charWidth, 1.0'f32)
      let extent = b.nuiOverlayExtent(nodeIdx)
      let terminal = b.backendType == UiBackendType.Terminal
      let visibleRows = min(totalRows, if terminal:
          min(numLinesToShow, max(extent.h.int - 2, 1))
        else:
          numLinesToShow)
      let popupH = if terminal: visibleRows.float32 + 2.0'f32
        else: visibleRows.float32 * lineH + 4.0'f32
      var listW = 340.0'f32
      var docsW = if docText.len > 0: docsWidthChars * charW else: 0.0'f32
      var popupW = listW + docsW
      if terminal:
        popupW = min(extent.w, 96.0'f32)
        let contentW = max(popupW - 2.0'f32, 1.0'f32)
        if docsW > 0.0'f32 and contentW >= 72.0'f32:
          listW = min(48.0'f32, floor(contentW * 0.55'f32))
          docsW = max(contentW - listW - 1.0'f32, 1.0'f32)
        else:
          listW = contentW
          docsW = 0.0'f32
      let placement = b.nuiPopupPlacement(nodeIdx, anchor.cx, anchor.cy,
        lineH, popupW, popupH)
      b.withParent(b.overlays):
        b.pushId(userData.uint64)
        b.node("text-completions-popup-overlay"):
          discard b.position(placement.x, placement.y).height(placement.h)
            .fillBackground().styleIndex(UiStyleIndexMenu).maskChildren()
          if terminal:
            discard b.width(placement.w)
          else:
            discard b.fitX()
          b.layoutHorizontal("text-completions-popup"):
            discard b.fitX().fillY().backendGap(2)
            b.node("text-completions-list"):
              discard b.width(listW).fillY().maskChildren()
              let listStorage = b.listTable(totalRows, lineH, [tableColumnFit(), tableColumnFit()], buildCompletionRowNui, userData)
              # Follow keyboard selection like legacy updateBaseIndexAndScrollOffset:
              # scrollToCompletion is set on selection change and consumed here.
              if self.scrollToCompletion.isSome:
                let target = self.scrollToCompletion.get
                if target >= 0 and target < totalRows:
                  discard listStorage.ensureItemVisible(target, b.currentNode.size.y, 0.0'f32)
                self.scrollToCompletion = none(int)
            if docsW > 0.0'f32:
              b.node("text-completions-docs"):
                discard b.width(docsW).fillY().fillBackground().styleIndex(UiStyleIndexTooltip).backendPadding(4, 1).wrapText().maskChildren().textStyleIndex(int(UiStyleIndexDefaultText)).text(docText)
        b.popId()
    except:
      discard

proc buildTextHoverNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Hover popup, deferred after the virtual list (mirrors legacy createHover at
  ## widget_builder_text_document:196). Anchored at the hover location from the
  ## chunk index; custom hover views render via View.renderNui, otherwise plain
  ## hover text lines. Popups attach to the global overlay and choose below or
  ## above the anchor based on available viewport space.
  {.cast(gcsafe).}:
    prof("buildTextHoverNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil or storage.theme.isNil:
        return
      if self.hoverComponent.isNil or not self.hoverComponent.showHover:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0:
        return
      let lineH = if storage.lineHeight > 0.0'f32: storage.lineHeight else: textLineHeightHint
      var diffXOffset = 0.0'f32
      if storage.renderDiff:
        diffXOffset = storage.diffSplitWidth
      let anchor = b.nuiPopupAnchor(storage, self.hoverComponent.hoverLocation, diffXOffset)
      if not anchor.found:
        return
      let bg = b.themeStyle(UiStyleIndexTooltip)[].fillColor.toColor
      let border = b.themeStyle(UiStyleIndexTooltip)[].borderColor.toColor
      let fg = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor.toColor
      let bgUi = rgba(bg.r.float32, bg.g.float32, bg.b.float32, bg.a.float32)
      let borderUi = rgba(border.r.float32, border.g.float32, border.b.float32, border.a.float32)
      let fgUi = rgba(fg.r.float32, fg.g.float32, fg.b.float32, fg.a.float32)
      let extent = b.nuiOverlayExtent(nodeIdx)
      let terminal = b.backendType == UiBackendType.Terminal
      let popupW = if terminal: min(72.0'f32, extent.w) else: 400.0'f32
      var textRows = max(self.hoverComponent.hoverText.countLines, 1)
      if terminal and self.hoverComponent.hoverText.len > 0:
        var hoverTextStyle = b.themeTextStyle(int(UiStyleIndexDefaultText))[]
        hoverTextStyle.text = self.hoverComponent.hoverText.uiString
        textRows = max(ceil(b.measuredTextSize(hoverTextStyle.addr,
          max(popupW - 2.0'f32, 1.0'f32)).y).int, 1)
      let desiredH = if terminal: min((textRows + 2).float32, extent.h)
        else: max(textRows.float32 * lineH + 14.0'f32, lineH + 14.0'f32)
      let placement = b.nuiPopupPlacement(nodeIdx, anchor.cx, anchor.cy,
        lineH, popupW, desiredH)
      b.withParent(b.overlays):
        b.pushId(userData.uint64)
        b.node("text-hover-popup-overlay"):
          discard b.position(placement.x, placement.y).width(placement.w).fitY()
            .maskChildren().fillBackground()
            .styleIndex(UiStyleIndexPanel).backgroundColor(bgUi)
            .borderColor(borderUi).backendBorderWidth(1.0'f32).backendPadding(6, 1)
          if terminal:
            discard b.maxHeight(placement.h)
          if self.hoverComponent.hoverView != nil:
            try:
              self.hoverComponent.hoverView.render(b)
            except:
              b.node:
                discard b.fillX().fitY().wrapText().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(fgUi).text("[hover view]")
          else:
            for line in self.hoverComponent.hoverText.splitLines:
              b.node:
                discard b.fillX().fitY().wrapText().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(fgUi).text(line)
          for overlay in self.hoverComponent.overlayViews:
            if overlay.isNil:
              continue
            try:
              overlay.render(b)
            except:
              discard
        b.popId()
    except:
      discard

proc buildTextSignatureHelpNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Signature-help popup, deferred after the virtual list (mirrors legacy
  ## createSignatureHelp at widget_builder_text_document:230). Inactive
  ## signatures render dimmed (capped like legacy), the active signature and its
  ## active parameter render highlighted. Popups attach to the global overlay
  ## and choose below or above the anchor; per-param text colors are content colors.
  {.cast(gcsafe).}:
    prof("buildTextSignatureHelpNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil or storage.theme.isNil:
        return
      if not self.showSignatureHelp:
        return
      if not self.document.isInitialized or storage.chunkIndex.len == 0:
        return
      let lineH = if storage.lineHeight > 0.0'f32: storage.lineHeight else: textLineHeightHint
      var diffXOffset = 0.0'f32
      if storage.renderDiff and nodeIdx >= 0 and nodeIdx < b.frame.nodes.len:
        try:
          diffXOffset = b.frame.nodes[nodeIdx].size.x * 0.5'f32
        except:
          discard
      let anchor = b.nuiPopupAnchor(storage, self.signatureHelpLocation.toPoint, diffXOffset)
      if not anchor.found:
        return
      let bg = b.themeStyle(UiStyleIndexTooltip)[].fillColor.toColor
      let border = b.themeStyle(UiStyleIndexTooltip)[].borderColor.toColor
      let fg = b.themeTextStyle(UiStyleIndexDefaultText)[].textColor.toColor
      let activeParamC = b.themeTextStyle(UiStyleIndexSignatureActiveParamText)[].textColor.toColor
      let activeSigC = b.themeTextStyle(UiStyleIndexSignatureActiveText)[].textColor.toColor
      let inactiveParamC = b.themeTextStyle(UiStyleIndexSignatureInactiveParamText)[].textColor.toColor
      let inactiveSigC = b.themeTextStyle(UiStyleIndexSignatureInactiveText)[].textColor.toColor
      let bgUi = rgba(bg.r.float32, bg.g.float32, bg.b.float32, bg.a.float32)
      let borderUi = rgba(border.r.float32, border.g.float32, border.b.float32, border.a.float32)
      let activeParamUi = rgba(activeParamC.r.float32, activeParamC.g.float32, activeParamC.b.float32, activeParamC.a.float32)
      let activeSigUi = rgba(activeSigC.r.float32, activeSigC.g.float32, activeSigC.b.float32, activeSigC.a.float32)
      let inactiveParamUi = rgba(inactiveParamC.r.float32, inactiveParamC.g.float32, inactiveParamC.b.float32, inactiveParamC.a.float32)
      let inactiveSigUi = rgba(inactiveSigC.r.float32, inactiveSigC.g.float32, inactiveSigC.b.float32, inactiveSigC.a.float32)
      let extent = b.nuiOverlayExtent(nodeIdx)
      let terminal = b.backendType == UiBackendType.Terminal
      let popupW = if terminal: min(78.0'f32, extent.w) else: 420.0'f32
      let signatureRows = min(max(self.signatures.len, 1), 7)
      let desiredH = if terminal: min((signatureRows + 2).float32, extent.h)
        else: signatureRows.float32 * lineH + 14.0'f32
      let placement = b.nuiPopupPlacement(nodeIdx, anchor.cx, anchor.cy,
        lineH, popupW, desiredH)
      b.withParent(b.overlays):
        b.pushId(userData.uint64)
        b.node("text-signature-popup-overlay"):
          discard b.position(placement.x, placement.y).width(placement.w).fitY()
            .maskChildren().fillBackground()
            .styleIndex(UiStyleIndexPanel).backgroundColor(bgUi)
            .borderColor(borderUi).backendBorderWidth(1.0'f32).backendPadding(6, 1)
          if terminal:
            discard b.maxHeight(placement.h)
          b.layoutVertical("text-signature-rows"):
            discard b.fillX().fitY().backendGap(2)
            var shown = 0
            for k, sig in self.signatures:
              if k == self.currentSignature:
                continue
              let activeParam = sig.activeParameter.get(self.currentSignatureParam)
              b.layoutHorizontal("signature-row"):
                discard b.fillX().fitY()
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(inactiveSigUi).text("(")
                for i, p in sig.parameters:
                  if i > 0:
                    b.node:
                      discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(inactiveSigUi).text(", ")
                  var paramStr = ""
                  if p.label.kind == JString:
                    paramStr = p.label.getStr
                  else:
                    paramStr = $p.label
                  let paramUi = if i == activeParam: inactiveParamUi else: inactiveSigUi
                  b.node:
                    discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(paramUi).text(paramStr)
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(inactiveSigUi).text(")")
              inc shown
              if shown > 5:
                break
            if self.currentSignature in 0..self.signatures.high:
              let sig = self.signatures[self.currentSignature]
              let activeParam = sig.activeParameter.get(self.currentSignatureParam)
              b.layoutHorizontal("signature-active-row"):
                discard b.fillX().fitY()
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text("(")
                for i, p in sig.parameters:
                  if i > 0:
                    b.node:
                      discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text(", ")
                  var paramStr = ""
                  if p.label.kind == JString:
                    paramStr = p.label.getStr
                  else:
                    paramStr = $p.label
                  let paramUi = if i == activeParam: activeParamUi else: activeSigUi
                  b.node:
                    discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(paramUi).text(paramStr)
                b.node:
                  discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text(")")
            if self.signatures.len == 0:
              b.node:
                discard b.fit().textStyleIndex(int(UiStyleIndexDefaultText)).textColor(activeSigUi).text("No signatures")
        b.popId()
    except:
      discard

proc buildTextDiffNavNui(b: var UiBuilder, nodeIdx: int, userData: int) {.nimcall, gcsafe, raises: [].} =
  ## Diff change navigation buttons, deferred overlay after the virtual list
  ## (mirrors legacy widget_builder_text_document.nim:1698). The legacy buttons
  ## sit middle-right; here they sit top-right (simpler anchor, same actions).
  {.cast(gcsafe).}:
    prof("buildTextDiffNavNui")
    try:
      if userData < 0 or userData >= b.frame.nodes.len:
        return
      var storage = b.getOrCreateTextEditorNuiStorage(b.frame.nodes[userData].addr)
      var self = storage.editor
      if self.isNil or self.document.isNil or self.diffChanges.isNone:
        return
      if not storage.renderDiff:
        return
      var showNav = false
      try:
        showNav = self.config.getUiRenderDiffNavigationButtons()
      except:
        discard
      # if not showNav:
      #   echo "4"
      #   return
      let cursorLine = self.selection.last.line
      var hasPrev = false
      var hasNext = false
      for mapping in self.diffChanges.get:
        if mapping.target.first < cursorLine:
          hasPrev = true
        if mapping.target.first > cursorLine:
          hasNext = true
          break
      if not hasPrev and not hasNext:
        return
      let btnBg = storage.baseBackground.darken(0.1)
      let btnBgUi = rgba(btnBg.r.float32, btnBg.g.float32, btnBg.b.float32, btnBg.a.float32)
      b.layoutVertical:
        discard b.anchors(0.5, 0.5, 0.5, 0.5).fit().finishAnchors()
        if hasPrev:
          var prevIdx = -1
          b.node:
            prevIdx = b.currentNodeIndex
            discard b.fit().backendPadding(4).fillBackground().backgroundColor(btnBgUi).textStyleIndex(int(UiStyleIndexDefaultText)).text("▲")
          block:
            let n = b.frame.nodes[prevIdx].addr
            if b.wasPressed(n.id, false, prevIdx):
              b.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} =
                self.selection = self.getPrevChange(self.selection.last)
                self.centerCursor(Last)
                self.markDirty())
        if hasNext:
          var nextIdx = -1
          b.node:
            nextIdx = b.currentNodeIndex
            discard b.fit().backendPadding(4).fillBackground().backgroundColor(btnBgUi).textStyleIndex(int(UiStyleIndexDefaultText)).text("▼")
          block:
            let n = b.frame.nodes[nextIdx].addr
            if b.wasPressed(n.id, false, nextIdx):
              b.enqueueNextFrame(proc() {.closure, gcsafe, raises: [].} =
                self.selection = self.getNextChange(self.selection.last)
                self.centerCursor(Last)
                self.markDirty())
    except:
      discard

proc createUINui*(self: TextDocumentEditor, nui: var UiBuilder) {.gcsafe, raises: [].} =
  # If the parent sizes to content (fitY, e.g. inside a note with fitY), the
  # whole editor fits its height: text-root/text-body use fitY so the dynamic
  # virtual list builds rows immediately and resolves its height up front.
  let fitContentY = FitY in nui.currentNode.flags
  # The virtual list always reserves its scrollbar track beside the viewport
  # (dynamic_virtuallist scrollbarWidth: 10px GUI, 1px terminal), so the wrap
  # width must exclude it or lines wrap under the scrollbar. In fit mode the
  # list takes the full width when everything fits (track collapses), so no
  # reservation is needed.
  let sbW = if fitContentY: 0.0'f32
            elif nui.backendType == UiBackendType.Terminal: 1.0'f32 else: 10.0'f32
  self.preRender(rect(0, 0, max(nui.currentNode.size.x - sbW, 0), nui.currentNode.size.y))

  let dirty = self.dirty

  {.cast(gcsafe).}:
    self.resetDirty()
    let panelStyle = if self.active: UiStyleIndexPanelActive else: UiStyleIndexPanel
    let headerStyle = if self.active: UiStyleIndexHeaderActive else: UiStyleIndexHeader
    let bgColor = nui.themeStyle(panelStyle)[].fillColor
    nui.layoutVertical("text-root"):
      discard nui.fillX().fillBackground().styleIndex(panelStyle).padding(0).backendGap(4)
      if fitContentY:
        discard nui.fitY()
      else:
        discard nui.fillY()
      nui.nodeStorageParent()
      nui.getOrCreateTextEditorNuiStorage(nui.currentNode).editor = self
      let rootIndex = nui.currentNodeIndex
      # Snapshot per-frame settings for the deferred line builder (buildTextLineNui
      # runs later and only sees the storage, not self).
      let storage = nui.getOrCreateTextEditorNuiStorage(nui.frame.nodes[rootIndex].addr)
      block:
        if not storage.arena.isValid:
          storage.arena = initArena()
        try:
          storage.theme = self.services.getServiceChecked(ThemeService).theme
        except:
          discard
        try:
          storage.useHighlight = self.config.getUiSyntaxHighlighting()
          storage.rainbowParens = self.config.getUiRainbowParentheses()
          storage.indentGuide = self.config.getUiIndentGuide()
          storage.whitespaceChar = self.config.getUiWhitespaceChar()
          storage.lineNumbers = self.config.getUiLineNumbers()
          storage.cursorLine = self.selection.last.line
          storage.diagnosticsLocation = self.config.getUiDiagnosticsLocation()
        except:
          discard
        try:
          let foreground = nui.themeTextStyle(UiStyleIndexDefaultText)[].textColor.toColor
          storage.whitespaceColor = if storage.theme != nil:
            storage.theme.tokenColor(self.config.getUiWhitespaceColor(), foreground)
          else:
            foreground
        except:
          storage.whitespaceColor = color(225/255, 200/255, 200/255)
        storage.cursorDisplayLine = -1
        try:
          if self.displayMap != nil:
            storage.cursorDisplayLine = self.displayMap.toDisplayPoint(
              self.selection.last.toPoint).row.int
        except:
          discard
        # Fresh chunk index every frame; the deferred line builder appends while
        # rendering (mirrors legacy per-frame chunkBounds).
        storage.chunkIndex.setLen(0)
        # Character metrics measured from the mono font like terminal/render.nim:479,
        # so the line-number gutter gets an explicit pixel width instead of spaces.
        var charW = 8.0'f32
        var charH = 16.0'f32
        if self.platform != nil:
          try:
            charW = self.platform.charWidth.float32
            charH = self.platform.lineHeight.float32
          except: discard
        try:
          let monoStyle = nui.themeTextStyle(UiStyleIndexDefaultMono)[]
          var tmpText = UiNodeText(text: "M".uiString, fontId: monoStyle.fontId, fontSize: monoStyle.fontSize.float32)
          let arr = nui.getTextArrangement(tmpText.addr, -1)
          if arr != nil:
            if arr.size.x > 0: charW = arr.size.x
            if arr.size.y > 0: charH = arr.size.y
        except:
          discard
        if charW <= 0: charW = 8.0'f32
        if charH <= 0: charH = 16.0'f32
        storage.charWidth = charW
        storage.lineHeight = charH
        let lineGap = if self.platform != nil:
            self.platform.lineDistance.float32
          else:
            0.0'f32
        if storage.lineGap != lineGap and storage.listStorage != nil:
          storage.listStorage.clearMeasuredHeights()
        storage.lineGap = lineGap
        storage.itemHeightHint = charH + storage.lineGap
        # Total line-number column width ahead of time (mirrors lineNumberBounds in
        # text_editor.nim:672: digits of the largest number + 1 padding, in pixels).
        var gutterPx = 0.0'f32
        try:
          case storage.lineNumbers
          of LineNumbers.Absolute:
            if self.document != nil:
              gutterPx = (($self.document.numLines).len + 1).float32 * charW
          of LineNumbers.Relative:
            gutterPx = (($99).len + 1).float32 * charW
          else: discard
        except:
          discard
        storage.gutterWidthPx = gutterPx
        try:
          storage.signColumnShow = self.config.getTextSignsShow()
          storage.signColumnWidth =
            if storage.signColumnShow == core_settings.SignColumnShowKind.Number:
              max((gutterPx / charW).int - 2, 0)
            else:
              self.requiredSignColumnWidth()
          storage.signColumnWidthPx = storage.signColumnWidth.float32 * charW
        except:
          storage.signColumnShow = core_settings.SignColumnShowKind.No
          storage.signColumnWidth = 0
          storage.signColumnWidthPx = 0.0'f32
        # Snapshot both diff iterators and their theme colors for the lists.
        storage.renderDiff = self.diffDocument != nil and
          self.diffDocument.isInitialized and self.diffChanges.isSome and
          self.diffDisplayMap != nil
        # UiColor -> chroma for the gap-darken fallback (legacy darken(0.03)).
        try:
          storage.baseBackground = color(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        except:
          storage.baseBackground = color(0.1, 0.1, 0.1)
        try:
          storage.highlightInlineChanges = self.config.getUiHighlightInlineChanges()
        except:
          storage.highlightInlineChanges = false
        storage.insertedLineBg = nui.themeStyle(UiStyleIndexDiffInsertedLine)[].fillColor.toColor
        storage.deletedLineBg = nui.themeStyle(UiStyleIndexDiffRemovedLine)[].fillColor.toColor
        storage.changedLineBg = nui.themeStyle(UiStyleIndexDiffChangedLine)[].fillColor.toColor
        storage.insertedTextBg = nui.themeStyle(UiStyleIndexDiffInsertedText)[].fillColor.toColor
        storage.deletedTextBg = nui.themeStyle(UiStyleIndexDiffRemovedText)[].fillColor.toColor
        storage.changedTextBg = nui.themeStyle(UiStyleIndexDiffChangedText)[].fillColor.toColor
        # Fresh forward iterator for this frame, reused across lines (one
        # construction per frame instead of per line).
        if self.document != nil and self.displayMap != nil:
          createNuiIter(self, storage, nui)
        if storage.renderDiff:
          createNuiDiffIter(self, storage, nui)
      # Header – replicates `createHeader` logic from widget_library (mode, dirty, file, dir + right side)
      if self.renderHeader:
        nui.layoutHorizontal("text-header"):
          discard nui.fillX().fitY().fillBackground().styleIndex(headerStyle).backendPadding(4).backendGap(8).cornerRadius(0)
          let modeText = if self.mode.len == 0: "-" else: self.mode
          let isDirty = if self.document != nil: self.document.lastSavedRevision != self.document.revision else: false
          let dirtyMarker = if isDirty: "*" else: ""
          let (directory, filename) = if self.document != nil: self.document.localizedPath.splitPath else: ("", "untitled")
          let leftText = " " & modeText & " - " & dirtyMarker & filename & " - " & directory & " "
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(leftText)
          # Spacer pushes right side to the end
          nui.layoutHorizontalReverse:
            discard nui.fillX().fitY()
            # Right side – mirrors `createHeader` onRight: customHeader, readOnly, staged, diff, rune, cursor positions
            let readOnlyText = if self.document != nil and self.document.readOnly: "-readonly- " else: ""
            let stagedText = if self.document != nil and self.document.staged: "-staged- " else: ""
            let renderDiff = self.diffDocument != nil and self.diffDocument.isInitialized and self.diffChanges.isSome
            let diffText = if renderDiff: "-diff- " else: ""
            let currentRune = if self.document != nil: self.document.runeAt(self.selection.last) else: 0.Rune
            let currentRuneText = if currentRune == 0.Rune: "\\0"
                                  elif currentRune == '\t'.Rune: "\\t"
                                  elif currentRune == '\n'.Rune: "\\n"
                                  else: $currentRune
            var currentRuneHexText = currentRune.int.toHex.strip(trailing=false, chars={'0'})
            if currentRuneHexText.len == 0: currentRuneHexText = "0"
            proc cursorString(cursor: Cursor): string =
              if self.document != nil and self.document.isInitialized:
                $cursor.line & ":" & $cursor.column
              else: ""
            let rightText = self.customHeader & " | " & readOnlyText & stagedText & diffText & "'" & currentRuneText & "' (U+" & currentRuneHexText & ") " & cursorString(self.selection.first) & "-" & cursorString(self.selection.last)
            nui.node:
              discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(rightText)
      # Body – lines via dynamic virtual list; each line is a horizontal node with one child node per chunk.
      # In fit mode the body uses fitY so the list sizes to its rows (immediate
      # build, no scrollbar when everything fits).
      nui.node("text-body"):
        discard nui.fillX()
        if fitContentY:
          discard nui.fitY()
        else:
          discard nui.fillY()
        var lineCount = 0
        try:
          if self.document != nil and self.displayMap != nil:
            lineCount = self.numDisplayLines
          # In diff view both sides share aligned display rows (diffMap gaps),
          # but take the max so a longer side is never clipped.
          if self.diffDocument != nil and self.diffDisplayMap != nil and
              self.diffChanges.isSome:
            try:
              let diffCount = self.diffDisplayMap.toDisplayPoint(
                self.diffDocument.rope.summary.lines).row.int + 1
              lineCount = max(lineCount, diffCount)
            except:
              discard
        except:
          lineCount = 0
        if lineCount <= 0:
          let path = if self.document != nil: self.document.filename
                     elif self.currentDocument != nil: self.currentDocument.filename
                     else: ""
          let displayPath = if path.len > 0: path else: "untitled"
          nui.node:
            discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(displayPath)
        else:
          # Calculate diff split width (half the viewport width) for overlay
          # offsets (highlights, cursors, popups).
          if storage.renderDiff:
            storage.diffSplitWidth = nui.currentNode.size.x * 0.5'f32
          # Keep the list storage so the deferred line builder can replicate
          # itemTop math for chunk index positions.
          discard nui.buildTextLinesListNui(rootIndex, lineCount, fitContentY)
          # Scrollbar change markers for the diff view. Buffer lines from
          # diffChanges are converted to display lines (the list rows) and
          # normalized by content height including the trailing spacer; the widget draws
          # them inside the scrollbar-background node via a deferred build.
          # Rebuilt every frame so stale markers never linger.
          block:
            prof("diff-scrollbar-markers")
            let editorStorage = nui.getOrCreateTextEditorNuiStorage(nui.frame.nodes[rootIndex].addr)
            let listStorage = editorStorage.listStorage
            if listStorage != nil:
              listStorage.scrollbarMarkers.setLen(0)
              if editorStorage.renderDiff and self.diffChanges.isSome and
                  self.displayMap != nil and lineCount > 0:
                try:
                  let maxLine = max(self.document.numLines - 1, 0)
                  for mapping in self.diffChanges.get:
                    let sFirst = mapping.source.first
                    let sLast = mapping.source.last
                    let sEmpty = sFirst == sLast
                    let tEmpty = mapping.target.first == mapping.target.last
                    if sEmpty and tEmpty:
                      continue
                    # Same kind classification as drawDiffBackgrounds: lines
                    # only in current are inserted, only in old are deleted,
                    # present in both are changed.
                    let kindBg =
                      if sEmpty: editorStorage.insertedTextBg
                      elif tEmpty: editorStorage.deletedTextBg
                      else: editorStorage.changedTextBg
                    # Target buffer range -> display rows (inclusive start,
                    # exclusive end). Deleted blocks have an empty target, so
                    # their height spans the deleted source lines, extending
                    # upward from the deletion point: the gap sits before the
                    # surviving line the deletion point maps to.
                    let cFirst = clamp(mapping.target.first, 0, maxLine)
                    let cLast = clamp(mapping.target.last, 0, self.document.numLines)
                    var dFirst = cFirst
                    var dEnd = cLast
                    try:
                      dFirst = self.displayMap.toDisplayPoint(point(cFirst, 0)).row.int
                      if cLast > cFirst:
                        dEnd = self.displayMap.toDisplayPoint(point(cLast, 0)).row.int
                      elif not sEmpty:
                        dEnd = dFirst
                        dFirst = dFirst - self.nuiDiffDeletedSpanRows(sFirst, sLast)
                      else:
                        dEnd = dFirst
                    except:
                      dFirst = cFirst
                      dEnd = cLast
                    dFirst = clamp(dFirst, 0, lineCount)
                    dEnd = clamp(dEnd, dFirst, lineCount)
                    let span = editorStorage.nuiTextScrollbarSpan(dFirst, dEnd,
                      nui.frame.nodes[rootIndex].size.y)
                    listStorage.scrollbarMarkers.add UiScrollbarMarker(
                      yFrac: span.yFrac,
                      hFrac: span.hFrac,
                      color: rgba(kindBg.r.float32, kindBg.g.float32, kindBg.b.float32, kindBg.a.float32))
                except:
                  discard
          # Restore the content scroll anchor if the display map changed, then
          # apply pending scroll requests stored by scrollTo*/scrollLines.
          # Request targets are buffer points, converted to rows with the
          # current display map. Consumed here so the deferred list build lays
          # out from the new offset this frame.
          # Requests are kept pending when the viewport height is still unknown.
          # Skipped in fit mode: all rows are visible, scroll range is zero.
          if not fitContentY:
            block:
              let editorStorage = nui.getOrCreateTextEditorNuiStorage(nui.frame.nodes[rootIndex].addr)
              let listStorage = editorStorage.listStorage
              let tec = self.textEditorComponent
              if listStorage != nil and tec != nil:
                self.restoreScrollAnchorNui(editorStorage)
                editorStorage.cacheTextTrailingSpaceHeight(nui.frame.nodes[rootIndex].size.y)
                var vpH = listStorage.viewportHeight
                if vpH <= 0.0'f32:
                  try:
                    vpH = nui.currentNode.size.y
                  except:
                    discard
                # Cursor margin mirrors the legacy path: relative fraction of the
                # viewport or margin-in-lines, clamped to the viewport.
                var marginPx = 0.0'f32
                try:
                  if not self.disableScrolling:
                    let lineH = if editorStorage.lineHeight > 0.0'f32: editorStorage.lineHeight else: textLineHeightHint
                    if self.config.getTextCursorMarginRelative():
                      marginPx = clamp(self.config.getTextCursorMargin(), 0.0, 1.0).float32 * 0.5'f32 * vpH
                    else:
                      marginPx = clamp(self.config.getTextCursorMargin().float32 * lineH, 0.0'f32, vpH * 0.5'f32 - lineH * 0.5'f32)
                except:
                  discard
                if marginPx < 0.0'f32:
                  marginPx = 0.0'f32
                if tec.nuiPendingScrollDeltaY != 0:
                  listStorage.scrollByY(tec.nuiPendingScrollDeltaY.float32)
                  tec.nuiPendingScrollDeltaY = 0
                if tec.nuiPendingScrollToY.isSome:
                  let t = tec.nuiPendingScrollToY.get
                  let row = self.displayMap.toDisplayPoint(t.point).row.int
                  if listStorage.scrollToItemAtOffset(row, t.yOffset.float32, vpH):
                    tec.nuiPendingScrollToY = none(tuple[point: Point, yOffset: float])
                elif tec.nuiPendingScrollTo.isSome:
                  let t = tec.nuiPendingScrollTo.get
                  let row = self.displayMap.toDisplayPoint(t.point).row.int
                  if listStorage.scrollToItem(row, vpH, marginPx, t.center, t.centerOffscreen):
                    tec.nuiPendingScrollTo = none(tuple[point: Point, center: bool, centerOffscreen: bool, snap: bool])
          nui.node("text-mouse-selection"):
            discard nui.noHover()
            discard nui.deferBuild(buildTextMouseSelectionNui, rootIndex)
          nui.node("text-highlight-layer"):
            discard nui.fillX().fillY().noHover()
            discard nui.deferBuild(buildTextHighlightsNui, rootIndex)
          if not storage.renderDiff and self.config.getContextLinesEnabled():
            nui.node("text-context-lines-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextContextOverlayNui, rootIndex)
          # Cursor overlay after the selection layer (paints on top); positions
          # resolve from the chunk index once the list is laid out.
          nui.node("text-cursor-layer"):
            discard nui.fillX().fillY().noHover()
            discard nui.deferBuild(buildTextCursorNui, rootIndex)
          # Diff change navigation (▲/▼) after cursors, before popups;
          # the builder itself gates on renderDiff + config + changes.
          nui.node("text-diff-nav-layer"):
            discard nui.fillX().fillY().noHover()
            discard nui.deferBuild(buildTextDiffNavNui, rootIndex)
          # Popup overlays after cursors (paint on top); anchors resolve from
          # the chunk index once the list is laid out (mirrors the legacy
          # OverlayFunctions at widget_builder_text_document:1877).
          if self.showCompletions and self.active:
            nui.node("text-completions-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextCompletionsNui, rootIndex)
          if self.hoverComponent != nil and self.hoverComponent.showHover:
            nui.node("text-hover-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextHoverNui, rootIndex)
          if self.showSignatureHelp:
            nui.node("text-signature-layer"):
              discard nui.fillX().fillY().noHover()
              discard nui.deferBuild(buildTextSignatureHelpNui, rootIndex)
          nui.node("text-sign-column-menu-layer"):
            discard nui.fillX().fillY().noHover()
            discard nui.deferBuild(buildTextSignColumnMenuNui, rootIndex)
