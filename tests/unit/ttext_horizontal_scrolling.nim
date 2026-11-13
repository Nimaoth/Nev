discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/text/widget_builder_text_document
{.pop.}
{.pop.}
{.pop.}
{.pop.}

import std/unittest
import nuigi/core/vecmath as nuiMath
import text_component, text_editor_component
import nimsumtree/sumtree
import misc/jsonex
import misc/event

proc measureScrollTestText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.runeLen.int.float32 * 10.0'f32, 20.0'f32)

type HorizontalTextFixture = object
  builder: UiBuilder
  editor: TextDocumentEditor
  storage: TextDocumentEditorNuiStorage
  highlightNodeIndex: int

proc newHorizontalTextFixture(content: string): HorizontalTextFixture =
  result.builder = newBuilder(measureScrollTestText)
  let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
  document.textComponent.buffer = initBuffer(content = content)
  let displayMap = DisplayMap.new()
  displayMap.setBuffer(document.textComponent.buffer.snapshot.clone())
  result.editor = TextDocumentEditor(document: document, displayMap: displayMap,
    platform: Platform(supportsThinCursor: true),
    config: ConfigStore.new("horizontal-test", "", nil, newJexObject()),
    textEditorComponent: newTextEditorComponent(document))
  result.editor.textEditorComponent.displayMap = displayMap
  result.editor.addComponent(result.editor.textEditorComponent)
  result.editor.decorations = newDecorationComponent(displayMap)
  result.editor.config.setTextWrapLines(false)

proc renderFrame(fixture: var HorizontalTextFixture, fitContentY = false,
    heightHint = 20.0'f32, restoreAnchor = false, consumeVerticalRequest = false,
    input = default(UiInputSnapshot)) =
  var b = fixture.builder.addr
  discard b[].beginUiFrame(200, 100, input)
  b[].node("horizontal-text-root"):
    discard b[].width(200)
    if fitContentY:
      discard b[].fitY()
    else:
      discard b[].height(100)
    b[].nodeStorageParent()
    let rootIndex = b[].currentNodeIndex
    let storage = b[].getOrCreateTextEditorNuiStorage(b[].currentNode)
    fixture.storage = storage
    storage.editor = fixture.editor
    if not storage.arena.isValid:
      storage.arena = initArena()
    storage.lineHeight = 20
    storage.charWidth = 10
    storage.itemHeightHint = heightHint
    storage.lineNumbers = LineNumbers.None
    storage.cursorDisplayLine = -1
    storage.whitespaceChar = "."
    storage.chunkIndex.setLen(0)
    createNuiIter(fixture.editor, storage, b[])
    storage.renderDiff = fixture.editor.diffDocument != nil and fixture.editor.diffChanges.isSome
    if storage.renderDiff:
      storage.diffSplitWidth = 100
      createNuiDiffIter(fixture.editor, storage, b[])
    b[].node("horizontal-text-body"):
      discard b[].fillX()
      if fitContentY:
        discard b[].fitY()
      else:
        discard b[].fillY()
      discard b[].buildTextLinesListNui(rootIndex, fixture.editor.numDisplayLines, fitContentY)
      if restoreAnchor:
        fixture.editor.restoreScrollAnchorNui(storage)
        storage.cacheTextTrailingSpaceHeight(100)
      if consumeVerticalRequest:
        let tec = fixture.editor.textEditorComponent
        if tec.nuiPendingScrollTo.isSome:
          let request = tec.nuiPendingScrollTo.get
          let row = fixture.editor.displayMap.toDisplayPoint(request.point).row.int
          if storage.listStorage.scrollToItem(row, storage.listStorage.viewportHeight,
              7.5, request.center, request.centerOffscreen):
            tec.nuiPendingScrollTo = none(tuple[point: Point, center: bool, centerOffscreen: bool, snap: bool])
    b[].node("horizontal-text-highlights"):
      fixture.highlightNodeIndex = b[].currentNodeIndex
      discard b[].noHover().deferBuild(buildTextHighlightsNui, rootIndex)
  b[].endUiFrame(buildRenderCommands = false)

proc addHeightOverlay(fixture: var HorizontalTextFixture, overlayHeight: ref float32,
    row = 7) =
  let renderId = fixture.editor.decorations.addCustomRenderer(
    proc(id: int, size: vmath.Vec2, localOffset: int,
        builder: var UiBuilder): vmath.Vec2 {.gcsafe, raises: [].} =
      builder.node:
        discard builder.size(size.x, overlayHeight[])
      return vmath.vec2(size.x, overlayHeight[]))
  let overlays = fixture.editor.displayMap.overlay
  let overlayId = overlays.allocateId().get
  let oldSnapshot = overlays.snapshot.clone()
  let patch = overlays.snapshot.addOverlay(point(row, 0)...point(row, 0),
    " ", overlayId, renderId = renderId.uint64.int,
    location = overlay_map.OverlayRenderLocation.Below)
  overlays.onUpdated.invoke((overlays, oldSnapshot, patch, @[overlayId]))

proc enableDiff(fixture: var HorizontalTextFixture, content: string) =
  let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
  document.textComponent.buffer = initBuffer(content = content)
  fixture.editor.diffDocument = document
  fixture.editor.diffDisplayMap = DisplayMap.new()
  fixture.editor.diffDisplayMap.setBuffer(document.buffer.snapshot.clone())
  fixture.editor.diffChanges = newSeq[LineMapping]().some

proc checkDiffLists(fixture: var HorizontalTextFixture) =
  let storage = fixture.storage
  let current = storage.listStorage
  let old = storage.diffListStorage
  check current != old
  check current.scrollOffsetY == old.scrollOffsetY
  check current.scrollOffsetX == old.scrollOffsetX
  check current.heights == old.heights
  check current.viewportHeight == old.viewportHeight
  check current.maxItemWidth == old.maxItemWidth
  let currentViewport = fixture.builder.firstChildIndex(storage.textListNodeIndex)
  let oldViewport = fixture.builder.firstChildIndex(storage.diffListNodeIndex)
  var currentRows: seq[int]
  var oldRows: seq[int]
  for row in fixture.builder.children(currentViewport): currentRows.add row
  for row in fixture.builder.children(oldViewport): oldRows.add row
  check currentRows.len == oldRows.len
  for i in 0..<min(currentRows.len, oldRows.len):
    let currentRow = fixture.builder.frame.nodes[currentRows[i]]
    let oldRow = fixture.builder.frame.nodes[oldRows[i]]
    check currentRow.pos == oldRow.pos
    check currentRow.size.y == oldRow.size.y

suite "Text horizontal scrolling":
  test "diff lists synchronize both axes from wheel input in either pane":
    var fixture = newHorizontalTextFixture(("x".repeat(100) & "\n").repeat(100))
    fixture.enableDiff("old\n".repeat(100))
    fixture.renderFrame()
    check fixture.storage.listStorage.viewportWidth == 90
    let highlights = fixture.builder.frame.nodes[fixture.highlightNodeIndex]
    check highlights.pos.x == 100
    check highlights.size.x == 90
    check highlights.size.y == 90
    for x in [25.0'f32, 125.0'f32]:
      fixture.renderFrame(input = UiInputSnapshot(mouse: nuiMath.vec2(x, 10)))
      let beforeX = fixture.storage.listStorage.scrollOffsetX
      fixture.renderFrame(input = UiInputSnapshot(mouse: nuiMath.vec2(x, 10),
        wheel: nuiMath.vec2(-1, 0)))
      check fixture.storage.listStorage.scrollOffsetX > beforeX
      fixture.checkDiffLists()
      let beforeY = fixture.storage.listStorage.scrollOffsetY
      fixture.renderFrame(input = UiInputSnapshot(mouse: nuiMath.vec2(x, 10),
        wheel: nuiMath.vec2(0, -1)))
      check fixture.storage.listStorage.scrollOffsetY > beforeY
      fixture.checkDiffLists()
      for frame in 0..<30:
        fixture.renderFrame()
        fixture.checkDiffLists()

  test "diff rows share dynamic overlay heights and shrink without losing alignment":
    for wrap in [false, true]:
      var fixture = newHorizontalTextFixture("abc\n".repeat(100))
      fixture.enableDiff(("x".repeat(100) & "\n").repeat(100))
      fixture.editor.config.setTextWrapLines(wrap)
      let overlayHeight = new(float32)
      fixture.addHeightOverlay(overlayHeight, row = 1)
      for height in [40.0'f32, 0.0'f32, 20.0'f32, 0.0'f32]:
        overlayHeight[] = height
        fixture.renderFrame()
        fixture.checkDiffLists()
        check fixture.storage.listStorage.itemHeight(1) == 20 + height
      fixture.storage.listStorage.scrollByY(160)
      fixture.storage.listStorage.scrollByX(200)
      fixture.renderFrame()
      fixture.checkDiffLists()

  test "scrollbar dragging in either diff pane updates both offsets":
    var fixture = newHorizontalTextFixture(("x".repeat(100) & "\n").repeat(100))
    fixture.enableDiff("old\n".repeat(100))
    fixture.renderFrame()
    for useOld in [false, true]:
      for horizontal in [false, true]:
        let list = if useOld: fixture.storage.diffListStorage else: fixture.storage.listStorage
        let track = if horizontal: list.horizontalScrollbarTrackIndex else: list.scrollbarTrackIndex
        let thumb = if horizontal: list.horizontalScrollbarThumbIndex else: list.scrollbarThumbIndex
        let thumbNode = fixture.builder.frame.nodes[thumb]
        let trackPos = fixture.builder.absoluteNodePos(track)
        let mouse = trackPos + thumbNode.pos + nuiMath.vec2(2, 2)
        fixture.renderFrame(input = UiInputSnapshot(mouse: mouse))
        fixture.renderFrame(input = UiInputSnapshot(mouse: mouse,
          mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
        let before = if horizontal: list.scrollOffsetX else: list.scrollOffsetY
        let delta = if horizontal: nuiMath.vec2(10, 0) else: nuiMath.vec2(0, 10)
        fixture.renderFrame(input = UiInputSnapshot(mouse: mouse + delta,
          mouseDelta: delta, mouseDown: {MouseLeft}))
        let after = if horizontal: list.scrollOffsetX else: list.scrollOffsetY
        check after > before
        fixture.checkDiffLists()
        fixture.renderFrame(input = UiInputSnapshot(mouse: mouse + delta,
          mouseReleased: {MouseLeft}))
        fixture.checkDiffLists()

  test "diff width is shared and resets when the old document changes":
    var fixture = newHorizontalTextFixture("abc\nabc")
    fixture.enableDiff("x".repeat(100) & "\nold")
    fixture.renderFrame()
    check fixture.storage.listStorage.maxItemWidth == 1000
    fixture.storage.listStorage.scrollByX(2000)
    fixture.renderFrame()
    fixture.checkDiffLists()
    check fixture.storage.listStorage.scrollOffsetX == 910
    fixture.enableDiff("old\nold")
    fixture.renderFrame()
    fixture.checkDiffLists()
    check fixture.storage.listStorage.maxItemWidth == 30
    check fixture.storage.listStorage.scrollOffsetX == 0
    check fixture.storage.listStorage.viewportHeight == 100

  test "fit-height diff panes have separate lists with matching content heights":
    var fixture = newHorizontalTextFixture("abc\nabc")
    fixture.enableDiff("old\nold")
    fixture.renderFrame(fitContentY = true)
    fixture.checkDiffLists()
    check fixture.storage.listStorage.viewportHeight == 40
    check fixture.storage.listStorage.visibleItemRange() == (first: 0, last: 1)

  test "transient inlay removal fills the viewport on the edit frame":
    for wrap in [false, true]:
      var fixture = newHorizontalTextFixture("abc\n".repeat(100))
      fixture.editor.config.setTextWrapLines(wrap)
      let tec = fixture.editor.textEditorComponent
      tec.selection = point(8, 1)
      let overlayHeight = new(float32)
      overlayHeight[] = 20
      for row in 0..<20:
        if row mod 2 == 1:
          fixture.addHeightOverlay(overlayHeight, row)
      fixture.renderFrame(heightHint = 19, restoreAnchor = true)
      let list = fixture.storage.listStorage
      for settle in 0..<2:
        list.scrollOffsetY = list.itemTop(8) - 39
        fixture.renderFrame(heightHint = 19, restoreAnchor = true)
      for edit in 0..<6:
        overlayHeight[] = 0
        let p = point(8, edit + 1)
        discard fixture.editor.document.textComponent.buffer.edit([(p...p, "x")])
        fixture.editor.document.revision.inc
        fixture.editor.displayMap.setBuffer(fixture.editor.document.buffer.snapshot.clone())
        tec.selection = point(8, edit + 2)
        tec.requestNuiScrollTo(point(8, edit + 2))
        for height in [0.0'f32, 20.0'f32]:
          overlayHeight[] = height
          fixture.renderFrame(heightHint = 19, restoreAnchor = true, consumeVerticalRequest = true)
          var renderedBottom = 0.0'f32
          let viewport = fixture.builder.firstChildIndex(fixture.storage.textListNodeIndex)
          for rowIdx in fixture.builder.children(viewport):
            let node = fixture.builder.frame.nodes[rowIdx]
            renderedBottom = max(renderedBottom, node.pos.y + node.size.y)
          check renderedBottom >= list.viewportHeight

  test "delayed overlay height changes preserve the cursor without a map version change":
    for wrap in [false, true]:
      var fixture = newHorizontalTextFixture("abc\n".repeat(100))
      fixture.editor.config.setTextWrapLines(wrap)
      let tec = fixture.editor.textEditorComponent
      tec.selection = point(8, 1)
      let overlayHeight = new(float32)
      overlayHeight[] = 1
      fixture.addHeightOverlay(overlayHeight)
      fixture.renderFrame(restoreAnchor = true)
      let list = fixture.storage.listStorage
      list.scrollOffsetY = list.itemTop(8) - 40
      fixture.renderFrame(restoreAnchor = true)
      list.scrollOffsetY = list.itemTop(8) - 40
      fixture.renderFrame(restoreAnchor = true)
      let version = fixture.editor.displayMap.version
      let initialPixelOffset = tec.scrollAnchor.pixelOffset
      for edit in 0..<6:
        overlayHeight[] = 0
        tec.requestNuiScrollTo(point(8, 1))
        fixture.renderFrame(restoreAnchor = true, consumeVerticalRequest = true)
        check fixture.editor.displayMap.version == version
        check tec.scrollAnchor.pixelOffset == initialPixelOffset
        overlayHeight[] = 1
        fixture.renderFrame(restoreAnchor = true, consumeVerticalRequest = true)
        check tec.scrollAnchor.pixelOffset == initialPixelOffset

  test "measurement anchoring does not undo manual vertical scrolling":
    var fixture = newHorizontalTextFixture("abc\n".repeat(100))
    let tec = fixture.editor.textEditorComponent
    tec.selection = point(8, 1)
    fixture.renderFrame(restoreAnchor = true)
    let list = fixture.storage.listStorage
    for settle in 0..<2:
      list.scrollOffsetY = list.itemTop(8) - 40
      fixture.renderFrame(restoreAnchor = true)
    let initialPixelOffset = tec.scrollAnchor.pixelOffset
    list.scrollByY(10)
    fixture.renderFrame(restoreAnchor = true)
    check tec.scrollAnchor.pixelOffset == initialPixelOffset - 10
    fixture.renderFrame(restoreAnchor = true)
    check tec.scrollAnchor.pixelOffset == initialPixelOffset - 10

  test "typing near the cursor margin uses measured height for vertical visibility":
    for wrap in [false, true]:
      var fixture = newHorizontalTextFixture("abc\n".repeat(100))
      fixture.editor.config.setTextWrapLines(wrap)
      let tec = fixture.editor.textEditorComponent
      tec.selection = point(8, 1)
      fixture.renderFrame(heightHint = 21, restoreAnchor = true)
      let list = fixture.storage.listStorage
      list.scrollOffsetY = list.itemTop(8) - 72
      fixture.renderFrame(heightHint = 21, restoreAnchor = true)
      list.scrollOffsetY = list.itemTop(8) - 72
      fixture.renderFrame(heightHint = 21, restoreAnchor = true)
      let initialPixelOffset = tec.scrollAnchor.pixelOffset
      check initialPixelOffset == 72
      for column in 1..6:
        let p = point(8, column)
        discard fixture.editor.document.textComponent.buffer.edit([(p...p, "x")])
        fixture.editor.document.revision.inc
        fixture.editor.displayMap.setBuffer(fixture.editor.document.buffer.snapshot.clone())
        tec.selection = point(8, column + 1)
        tec.requestNuiScrollTo(point(8, column + 1))
        fixture.renderFrame(heightHint = 21, restoreAnchor = true, consumeVerticalRequest = true)
        check tec.scrollAnchor.pixelOffset == initialPixelOffset

  test "typing preserves the cursor row position when measured heights differ from hints":
    for wrap in [false, true]:
      for hint in [18.0'f32, 24.0'f32]:
        var fixture = newHorizontalTextFixture("abc\n".repeat(100))
        fixture.editor.config.setTextWrapLines(wrap)
        fixture.editor.textEditorComponent.selection = point(8, 1)
        fixture.renderFrame(heightHint = hint, restoreAnchor = true)
        let list = fixture.storage.listStorage
        list.scrollOffsetY = 120
        fixture.renderFrame(heightHint = hint, restoreAnchor = true)
        let tec = fixture.editor.textEditorComponent
        let initialPixelOffset = tec.scrollAnchor.pixelOffset
        for column in 1..6:
          let p = point(8, column)
          discard fixture.editor.document.textComponent.buffer.edit([(p...p, "x")])
          fixture.editor.document.revision.inc
          fixture.editor.displayMap.setBuffer(fixture.editor.document.buffer.snapshot.clone())
          tec.selection = point(8, column + 1)
          tec.requestNuiScrollTo(point(8, column + 1))
          fixture.renderFrame(heightHint = hint, restoreAnchor = true)
          check tec.scrollAnchor.pixelOffset == initialPixelOffset
          let viewportIndex = fixture.builder.firstChildIndex(fixture.storage.textListNodeIndex)
          let viewportY = fixture.builder.absoluteNodePos(viewportIndex).y
          for entry in fixture.storage.chunkIndex:
            check entry.posY == fixture.builder.absoluteNodePos(entry.nodeIndex).y - viewportY

  test "cursor requests scroll right and left in the same frame":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.renderFrame()
    let tec = fixture.editor.textEditorComponent
    let list = fixture.storage.listStorage
    tec.requestNuiScrollTo(point(0, 80))
    fixture.renderFrame()
    check list.scrollOffsetX == 612
    check tec.nuiPendingScrollToX.isNone
    let anchor = fixture.builder.nuiPopupAnchor(fixture.storage, point(0, 80))
    check anchor.found
    check anchor.cx == 188
    let viewportIndex = fixture.builder.firstChildIndex(fixture.storage.textListNodeIndex)
    for rowIndex in fixture.builder.children(viewportIndex):
      check fixture.builder.frame.nodes[rowIndex].pos.x == -612
    let thumb = fixture.builder.frame.nodes[list.horizontalScrollbarThumbIndex]
    check thumb.pos.x > 0
    tec.requestNuiScrollTo(point(0, 2))
    fixture.renderFrame()
    check list.scrollOffsetX == 20
    tec.requestNuiScrollTo(point(0, 0))
    fixture.renderFrame()
    check list.scrollOffsetX == 0

  test "visible cursors and manual scrolling do not cause extra movement":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.renderFrame()
    let tec = fixture.editor.textEditorComponent
    let list = fixture.storage.listStorage
    list.scrollByX(400)
    fixture.renderFrame()
    tec.requestNuiScrollTo(point(0, 45))
    fixture.renderFrame()
    check list.scrollOffsetX == 400
    list.scrollByX(100)
    fixture.renderFrame()
    check list.scrollOffsetX == 500
    fixture.renderFrame()
    check list.scrollOffsetX == 500

  test "line-end cursors reserve their width without resetting measured text":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.editor.platform.supportsThinCursor = false
    fixture.editor.textEditorComponent.requestNuiScrollTo(point(0, 100))
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    check list.maxItemWidth == 1010
    check list.scrollOffsetX == 820
    fixture.editor.textEditorComponent.requestNuiScrollTo(point(0, 1))
    fixture.renderFrame()
    check list.maxItemWidth == 1010
    check list.scrollOffsetX == 10

  test "cursor following measures UTF-8 glyphs rather than byte columns":
    var fixture = newHorizontalTextFixture("\xC3\xA9".repeat(50))
    fixture.editor.textEditorComponent.requestNuiScrollTo(point(0, 80))
    fixture.renderFrame()
    check fixture.storage.listStorage.maxItemWidth == 500
    check fixture.storage.listStorage.scrollOffsetX == 212
    let anchor = fixture.builder.nuiPopupAnchor(fixture.storage, point(0, 80))
    check anchor.found
    check anchor.cx == 188

  test "diff cursor requests include the right pane offset":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.editor.diffDocument = fixture.editor.document
    fixture.editor.diffDisplayMap = DisplayMap.new()
    fixture.editor.diffDisplayMap.setBuffer(fixture.editor.document.buffer.snapshot.clone())
    fixture.editor.diffChanges = newSeq[LineMapping]().some
    fixture.editor.textEditorComponent.requestNuiScrollTo(point(0, 60))
    fixture.renderFrame()
    check fixture.storage.listStorage.scrollOffsetX == 512
    let anchor = fixture.builder.nuiPopupAnchor(fixture.storage, point(0, 60),
      fixture.storage.diffSplitWidth)
    check anchor.found
    check anchor.cx == 188

  test "first fit frame resolves cursor requests using the full viewport":
    var fixture = newHorizontalTextFixture("x".repeat(20))
    let tec = fixture.editor.textEditorComponent
    tec.requestNuiScrollTo(point(0, 20))
    fixture.renderFrame(fitContentY = true)
    let list = fixture.storage.listStorage
    check list.viewportWidth == 200
    check list.viewportHeight == 20
    check list.maxItemWidth == 202
    check list.scrollOffsetX == 2
    check tec.nuiPendingScrollToX.isNone

  test "wrapped and disabled scrolling discard cursor follow requests":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    let tec = fixture.editor.textEditorComponent
    list.scrollByX(300)
    fixture.editor.disableScrolling = true
    tec.requestNuiScrollTo(point(0, 80))
    fixture.renderFrame()
    check list.scrollOffsetX == 300
    check tec.nuiPendingScrollToX.isNone
    fixture.editor.disableScrolling = false
    fixture.editor.config.setTextWrapLines(true)
    tec.requestNuiScrollTo(point(0, 80))
    fixture.renderFrame()
    check list.scrollOffsetX == 0
    check tec.nuiPendingScrollToX.isNone
    fixture.editor.config.setTextWrapLines(false)
    fixture.renderFrame()
    check list.scrollOffsetX == 0

  test "offscreen cursor requests wait until their row is rendered":
    var fixture = newHorizontalTextFixture("abc\n".repeat(10) & "x".repeat(100))
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    let tec = fixture.editor.textEditorComponent
    tec.requestNuiScrollTo(point(10, 80))
    fixture.renderFrame()
    check tec.nuiPendingScrollToX.isSome
    check list.scrollOffsetX == 0
    discard list.scrollToItem(10, list.viewportHeight, 0, false, false)
    fixture.renderFrame()
    check tec.nuiPendingScrollToX.isNone
    check list.scrollOffsetX == 612

  test "absolute-row scroll requests also follow the target column":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.editor.textEditorComponent.requestNuiScrollToY(point(0, 80), 0)
    fixture.renderFrame()
    check fixture.storage.listStorage.scrollOffsetX == 612

  test "terminal cursor following keeps the caret inside a cell-aligned viewport":
    var fixture = newHorizontalTextFixture("x".repeat(300))
    fixture.builder.backendType = UiBackendType.Terminal
    fixture.editor.textEditorComponent.requestNuiScrollTo(point(0, 300))
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    let anchor = fixture.builder.nuiPopupAnchor(fixture.storage, point(0, 300))
    check anchor.found
    check list.scrollOffsetX > 0
    check list.scrollOffsetX == floor(list.scrollOffsetX)
    check anchor.cx >= 0
    check anchor.cx + 1 <= list.viewportWidth

  test "suppressed cursor requests leave horizontal position untouched":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.renderFrame()
    let tec = fixture.editor.textEditorComponent
    tec.suppressScrollRequests.inc
    tec.requestNuiScrollTo(point(0, 80))
    tec.suppressScrollRequests.dec
    fixture.renderFrame()
    check tec.nuiPendingScrollToX.isNone
    check fixture.storage.listStorage.scrollOffsetX == 0

  test "width survives vertical scrolling and resets on text revision":
    var fixture = newHorizontalTextFixture("x".repeat(100) & "\n" & "abc\n".repeat(100))
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    check list.maxItemWidth == 1000
    list.scrollOffsetY = 200
    list.scrollByX(100)
    fixture.renderFrame()
    check list.maxItemWidth == 1000
    check list.scrollOffsetX == 100
    check fixture.storage.chunkIndex[0].point.row.int > 0
    fixture.editor.document.textComponent.buffer = initBuffer(content = "abc\n".repeat(101))
    fixture.editor.document.revision.inc
    fixture.editor.displayMap.setBuffer(fixture.editor.document.buffer.snapshot.clone())
    fixture.renderFrame()
    check list.maxItemWidth == 30
    check list.scrollOffsetX == 0

  test "wrapped editor never scrolls horizontally":
    var fixture = newHorizontalTextFixture("x".repeat(100))
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    list.scrollByX(100)
    fixture.editor.config.setTextWrapLines(true)
    fixture.renderFrame()
    check list.scrollOffsetX == 0
    check list.horizontalScrollbarTrackIndex == -1
    check list.viewportHeight == 100

  test "overlay rows follow final vertical bounds when horizontal bar disappears":
    var fixture = newHorizontalTextFixture("x".repeat(100) & "\n" & "abc\n".repeat(8) & "abc")
    fixture.renderFrame()
    let list = fixture.storage.listStorage
    list.scrollOffsetY = 110
    fixture.renderFrame()
    fixture.editor.document.textComponent.buffer = initBuffer(content = "abc\n".repeat(9) & "abc")
    fixture.editor.document.revision.inc
    fixture.editor.displayMap.setBuffer(fixture.editor.document.buffer.snapshot.clone())
    fixture.renderFrame()
    check list.viewportHeight == 100
    check list.scrollOffsetY == 100
    let viewportIndex = fixture.builder.firstChildIndex(fixture.storage.textListNodeIndex)
    let viewportY = fixture.builder.absoluteNodePos(viewportIndex).y
    for entry in fixture.storage.chunkIndex:
      check entry.posY == fixture.builder.absoluteNodePos(entry.nodeIndex).y - viewportY

  test "entire long lines render beyond the old chunk cutoff":
    var fixture = newHorizontalTextFixture("x ".repeat(600))
    fixture.renderFrame()
    check fixture.storage.chunkIndex.len > 500
    check fixture.storage.listStorage.maxItemWidth == 12000
    check fixture.storage.chunkIndex[^1].endPoint.column.int == 1200
    fixture.storage.listStorage.scrollByX(11000)
    fixture.renderFrame()
    check fixture.storage.listStorage.scrollOffsetX == 11000
    check fixture.storage.chunkIndex[^1].endPoint.column.int == 1200
