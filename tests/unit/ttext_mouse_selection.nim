discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
  matrix: ""
"""

include ../../modules/text/widget_builder_text_document
{.pop.}
{.pop.}
{.pop.}
{.pop.}

import std/unittest
import nuigi/core/vecmath as nuiMath
import text_component, text_editor_component
import misc/jsonex

proc measureMouseTestText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.runeLen.int.float32 * 10.0'f32, 20.0'f32)

suite "Text builder theme colors":
  test "plain text and diagnostic underlines use builder overrides":
    var builder = newBuilder(measureMouseTestText)
    let theme = Theme()
    theme.colors["editor.foreground"] = color(1, 0, 0)
    theme.colors["default-text.foreground"] = color(0.2, 0.3, 0.4)
    theme.colors["error-text.foreground"] = color(0.9, 0.1, 0.2)
    theme.colors["warning-text.foreground"] = color(0.8, 0.7, 0.1)
    theme.colors["info-text.foreground"] = color(0.1, 0.5, 0.8)
    theme.colors["hint-text.foreground"] = color(0.4, 0.7, 0.6)
    builder.syncThemeStyles(theme)
    let rope = Rope.new("abc")
    var arena = initArena()
    for (severity, index) in [
        (language_server.DiagnosticSeverity.Error, UiStyleIndexErrorText),
        (language_server.DiagnosticSeverity.Warning, UiStyleIndexWarningText),
        (language_server.DiagnosticSeverity.Information, UiStyleIndexInfoText),
        (language_server.DiagnosticSeverity.Hint, UiStyleIndexHintText)]:
      var iter = StyledChunkIterator.init(rope, arena.addr, theme = theme)
      iter.setThemeStyles(builder)
      iter.diagnosticEndPoints = @[
        DiagnosticEndPoint(severity: severity, point: point(0, 0), start: true),
        DiagnosticEndPoint(severity: severity, point: point(0, 3), start: false)]
      let chunk = iter.next()
      require chunk.isSome
      check chunk.get.color == color(0.2, 0.3, 0.4)
      require chunk.get.underline.isSome
      check chunk.get.underline.get.color == builder.themeTextStyle(index)[].textColor.toColor
      check builder.nuiDiagnosticColor(severity.some) == builder.themeTextStyle(index)[].textColor

suite "Text mouse selection":
  var builder = newBuilder(measureMouseTestText)

  test "thin cursor retains midpoint selection":
    let entry = TextChunkIndexEntry(displayEndPoint: displayPoint(0, 2))
    let style = UiNodeText(text: "ab".uiString)
    check builder.nuiByteOffsetAtX(entry, "ab", 4, style, false) == 0
    check builder.nuiByteOffsetAtX(entry, "ab", 5, style, false) == 1
    check builder.nuiByteOffsetAtX(entry, "ab", 9, style, false) == 1
    check builder.nuiByteOffsetAtX(entry, "ab", 15, style, false) == 2

  test "thick cursor selects the entire clicked cell":
    let entry = TextChunkIndexEntry(displayEndPoint: displayPoint(0, 2))
    let style = UiNodeText(text: "ab".uiString)
    for x in [1.0'f32, 5, 9]:
      check builder.nuiByteOffsetAtX(entry, "ab", x, style, true) == 0
    for x in [10.0'f32, 15, 19]:
      check builder.nuiByteOffsetAtX(entry, "ab", x, style, true) == 1
    check builder.nuiByteOffsetAtX(entry, "ab", 20, style, true) == 2

  test "replacement whitespace returns original offsets in both cursor modes":
    let text = "\xC2\xB7\xC2\xB7"
    let entry = TextChunkIndexEntry(displayEndPoint: displayPoint(0, 2), replacementGlyphLen: 2)
    let style = UiNodeText(text: text.uiString)
    check builder.nuiByteOffsetAtX(entry, text, 9, style, false) == 1
    check builder.nuiByteOffsetAtX(entry, text, 9, style, true) == 0
    check builder.nuiByteOffsetAtX(entry, text, 19, style, true) == 1
    check builder.nuiByteOffsetAtX(entry, text, 20, style, true) == 2

  test "empty line placeholder returns zero":
    let entry = TextChunkIndexEntry(displayPoint: displayPoint(1, 0),
      displayEndPoint: displayPoint(1, 0))
    let style = UiNodeText(text: " ".uiString)
    check builder.nuiByteOffsetAtX(entry, " ", 20, style, true) == 0

  test "click count dispatch matches legacy mouse buttons":
    check nuiMouseSelectionButton(0) == MouseButton.Left
    check nuiMouseSelectionButton(1) == MouseButton.Left
    check nuiMouseSelectionButton(2) == MouseButton.DoubleClick
    check nuiMouseSelectionButton(3) == MouseButton.TripleClick
    check nuiMouseSelectionButton(4) == MouseButton.TripleClick

  test "drag keeps the initial anchor in both directions":
    let start = (1, 3).toSelection
    check nuiMouseDragSelection(start, (2, 5)) == ((1, 3), (2, 5))
    check nuiMouseDragSelection(start, (0, 1)) == ((1, 3), (0, 1))
    check nuiMouseDragSelection(start, (1, 3)) == start

  test "range drag chooses the legacy opposite edge":
    check nuiMouseDragSelection(((0, 2), (0, 5)), (0, 1)) == ((0, 5), (0, 1))
    check nuiMouseDragSelection(((0, 2), (0, 5)), (0, 8)) == ((0, 2), (0, 8))
    check nuiMouseDragSelection(((0, 5), (0, 2)), (0, 1)) == ((0, 5), (0, 1))
    check nuiMouseDragSelection(((0, 5), (0, 2)), (0, 8)) == ((0, 2), (0, 8))

  test "hit-testing crosses chunks and rows and clamps outside":
    builder.frame.nodes.setLen(0)
    let storage = TextDocumentEditorNuiStorage()
    for geometry in [(10.0'f32, 0.0'f32, 20.0'f32),
        (30.0'f32, 0.0'f32, 20.0'f32),
        (10.0'f32, 20.0'f32, 10.0'f32),
        (10.0'f32, 40.0'f32, 30.0'f32)]:
      let index = builder.frame.nodes.len
      builder.frame.nodes.add nuigi.UiNode(parent: -1,
        pos: nuiMath.vec2(geometry[0], geometry[1]),
        size: nuiMath.vec2(geometry[2], 20))
      storage.chunkIndex.add TextChunkIndexEntry(nodeIndex: index)
    for hit in [(15.0'f32, 10.0'f32, 0), (35.0'f32, 10.0'f32, 1),
        (30.0'f32, 10.0'f32, 1), (100.0'f32, 10.0'f32, 1),
        (-10.0'f32, 10.0'f32, 0), (15.0'f32, 20.0'f32, 2),
        (15.0'f32, 45.0'f32, 3), (15.0'f32, -20.0'f32, 0),
        (100.0'f32, 100.0'f32, 3)]:
      builder.frameCtx.input.mouse = nuiMath.vec2(hit[0], hit[1])
      check builder.nuiMouseChunkIndex(storage) == hit[2]

type MouseSelectionFixture = object
  builder: UiBuilder
  editor: TextDocumentEditor
  storage: TextDocumentEditorNuiStorage
  commands: ref seq[string]

proc newMouseSelectionFixture(content = "abc\nxyz"): MouseSelectionFixture =
  result.builder = newBuilder(measureMouseTestText)
  let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
  document.textComponent.buffer = initBuffer(content = content)
  let displayMap = DisplayMap.new()
  displayMap.setBuffer(document.textComponent.buffer.snapshot.clone())
  let editor = TextDocumentEditor(document: document, displayMap: displayMap,
    platform: Platform(supportsThinCursor: true), layout: LayoutServiceImpl(),
    config: ConfigStore.new("mouse-test", "", nil, newJexObject()),
    textEditorComponent: newTextEditorComponent(document))
  editor.textEditorComponent.displayMap = displayMap
  editor.addComponent(editor.textEditorComponent)
  editor.decorations = newDecorationComponent(displayMap)
  editor.disableScrolling = true
  editor.config.setTextSingleClickCommand("single")
  editor.config.setTextSingleClickCommandArgs(newJArray())
  editor.config.setTextControlClickCommand("control")
  editor.config.setTextControlClickCommandArgs(newJArray())
  editor.config.setTextDoubleClickCommand("double")
  editor.config.setTextDoubleClickCommandArgs(newJArray())
  editor.config.setTextTripleClickCommand("triple")
  editor.config.setTextTripleClickCommandArgs(newJArray())
  let commands = new(seq[string])
  editor.handleActionImpl = proc(self: DocumentEditor, action, args: string,
      record: bool): Option[JsonNode] {.gcsafe, raises: [].} =
    commands[].add action
    return JsonNode.none
  result.editor = editor
  result.commands = commands

proc textListFrame(fixture: var MouseSelectionFixture, editorHeight: float32,
    fitContentY = false) =
  var b = fixture.builder.addr
  discard b[].beginUiFrame(200, editorHeight)
  b[].node("text-list-test-root"):
    discard b[].width(200)
    if fitContentY:
      discard b[].fitY()
    else:
      discard b[].height(editorHeight)
    b[].nodeStorageParent()
    let rootIndex = b[].currentNodeIndex
    let storage = b[].getOrCreateTextEditorNuiStorage(b[].currentNode)
    fixture.storage = storage
    storage.editor = fixture.editor
    if not storage.arena.isValid:
      storage.arena = initArena()
    storage.lineHeight = 20
    storage.charWidth = 10
    storage.itemHeightHint = 20
    storage.cursorDisplayLine = -1
    storage.chunkIndex.setLen(0)
    createNuiIter(fixture.editor, storage, b[])
    b[].node("text-list-test-body"):
      discard b[].fillX()
      if fitContentY:
        discard b[].fitY()
      else:
        discard b[].fillY()
      discard b[].buildTextLinesListNui(rootIndex, fixture.editor.numDisplayLines, fitContentY)
    b[].node("text-list-test-highlights"):
      discard b[].noHover().deferBuild(buildTextHighlightsNui, rootIndex)
  b[].endUiFrame(buildMeshRenderCommands = false)

proc textListRowIndexes(fixture: MouseSelectionFixture): seq[int] =
  let viewportIndex = fixture.builder.firstChildIndex(fixture.storage.textListNodeIndex)
  for childIndex in fixture.builder.children(viewportIndex):
    result.add childIndex

suite "Text virtual list trailing space":
  test "non-fit editor appends one blank row with editor height minus five lines":
    var fixture = newMouseSelectionFixture()
    fixture.textListFrame(300)
    let rows = fixture.textListRowIndexes()
    check rows.len == 3
    check fixture.storage.chunkIndex.len == 2
    if rows.len == 3:
      let row = fixture.builder.frame.nodes[rows[^1]]
      check row.size.y == 200
      check FitY notin row.flags
      check row.textIndex == 0
      check fixture.builder.firstChildIndex(rows[^1]) == -1
    check fixture.editor.textEditorComponent.nuiVisibleDisplayRange.get == (0, 1)

  test "fit editor contains only its text rows":
    var fixture = newMouseSelectionFixture()
    fixture.textListFrame(300, fitContentY = true)
    check fixture.textListRowIndexes().len == 2
    check fixture.storage.chunkIndex.len == 2
    check fixture.storage.listStorage.estimatedTotalHeight(2, 20) == 40

  test "blank row height tracks editor resizing and never becomes negative":
    var fixture = newMouseSelectionFixture()
    for editorHeight in [300.0'f32, 400.0'f32, 60.0'f32]:
      fixture.textListFrame(editorHeight)
      let rows = fixture.textListRowIndexes()
      check rows.len == 3
      if rows.len == 3:
        check fixture.builder.frame.nodes[rows[^1]].size.y ==
          max(0.0'f32, editorHeight - 100.0'f32)

  test "switching to fit mode removes the cached blank row":
    var fixture = newMouseSelectionFixture()
    fixture.textListFrame(300)
    fixture.textListFrame(300, fitContentY = true)
    check fixture.textListRowIndexes().len == 2
    check fixture.storage.listStorage.estimatedTotalHeight(2, 20) == 40

  test "blank row adds scroll range without reporting an extra text line":
    var fixture = newMouseSelectionFixture(
      "abc\nabc\nabc\nabc\nabc\nabc\nabc\nabc\nabc\nabc")
    check fixture.editor.numDisplayLines == 10
    fixture.textListFrame(300)
    check fixture.storage.listStorage.estimatedTotalHeight(11, 20) == 400
    fixture.storage.listStorage.scrollOffsetY = 100
    fixture.textListFrame(300)
    check fixture.storage.listStorage.scrollOffsetY == 100
    check fixture.storage.chunkIndex.len == 5
    check fixture.editor.textEditorComponent.nuiVisibleDisplayRange.get == (5, 9)

  test "offscreen spacer height is cached without being rendered":
    var fixture = newMouseSelectionFixture("abc\n".repeat(100) & "abc")
    for editorHeight in [300.0'f32, 400.0'f32, 60.0'f32]:
      fixture.textListFrame(editorHeight)
      let list = fixture.storage.listStorage
      check list.heights[^1].itemIndex == 101
      check list.heights[^1].height == max(0.0'f32, editorHeight - 100)
      check list.itemHeight(101) == max(0.0'f32, editorHeight - 100)
      check list.estimatedTotalHeight(102, 20) ==
        2020 + max(0.0'f32, editorHeight - 100)
      for rowIndex in fixture.textListRowIndexes():
        check fixture.builder.frame.nodes[rowIndex].size.y == 20

  test "changing line count does not retain the old spacer as a text height":
    var fixture = newMouseSelectionFixture("abc\n".repeat(100) & "abc")
    fixture.textListFrame(300)
    fixture.storage.chunkIndex.setLen(0)
    createNuiIter(fixture.editor, fixture.storage, fixture.builder)
    discard fixture.builder.beginUiFrame(200, 300)
    fixture.builder.node("text-list-test-root"):
      discard fixture.builder.width(200).height(300)
      fixture.builder.nodeStorageParent()
      let rootIndex = fixture.builder.currentNodeIndex
      fixture.builder.node("text-list-test-body"):
        discard fixture.builder.fillX().fillY()
        let list = fixture.builder.buildTextLinesListNui(rootIndex, 102, false)
        check list.itemHeight(101) == 20
        check list.itemHeight(102) == 200
        check list.estimatedTotalHeight(103, 20) == 2240
    fixture.builder.endUiFrame(buildMeshRenderCommands = false)

suite "Text scrollbar marker positioning":
  test "marker position and height include the trailing blank row":
    var fixture = newMouseSelectionFixture(
      "abc\nabc\nabc\nabc\nabc\nabc\nabc\nabc\nabc\nabc")
    fixture.textListFrame(300)
    let span = fixture.storage.nuiTextScrollbarSpan(5, 7, 300)
    check abs(span.yFrac - 0.25'f32) < 0.0001'f32
    check abs(span.hFrac - 0.10'f32) < 0.0001'f32
    let endSpan = fixture.storage.nuiTextScrollbarSpan(9, 10, 300)
    check abs(endSpan.yFrac + endSpan.hFrac - 0.5'f32) < 0.0001'f32

  test "unbuilt spacer and stale cached spacer use the current editor height":
    var fixture = newMouseSelectionFixture(
      "abc\nabc\nabc\nabc\nabc\nabc\nabc\nabc\nabc\nabc")
    fixture.textListFrame(100)
    check fixture.storage.listStorage.heights[^1].itemIndex ==
      fixture.storage.displayLineCount
    check fixture.storage.listStorage.heights[^1].height == 0
    let unbuilt = fixture.storage.nuiTextScrollbarSpan(5, 7, 300)
    check abs(unbuilt.yFrac - 0.25'f32) < 0.0001'f32
    check abs(unbuilt.hFrac - 0.10'f32) < 0.0001'f32
    fixture.textListFrame(300)
    let resized = fixture.storage.nuiTextScrollbarSpan(5, 7, 400)
    check abs(resized.yFrac - 0.20'f32) < 0.0001'f32
    check abs(resized.hFrac - 0.08'f32) < 0.0001'f32

  test "short and fit editors do not add trailing space to marker fractions":
    var fixture = newMouseSelectionFixture()
    fixture.textListFrame(60)
    let shortSpan = fixture.storage.nuiTextScrollbarSpan(1, 2, 60)
    check shortSpan.yFrac == 0.5'f32
    check shortSpan.hFrac == 0.5'f32
    fixture.textListFrame(300, fitContentY = true)
    let fitSpan = fixture.storage.nuiTextScrollbarSpan(1, 2, 300)
    check fitSpan.yFrac == 0.5'f32
    check fitSpan.hFrac == 0.5'f32

  test "marker spans follow measured variable row heights":
    var fixture = newMouseSelectionFixture()
    fixture.textListFrame(300)
    fixture.storage.listStorage.heights = @[
      UiDynamicVirtualListHeight(itemIndex: 0, height: 40),
      UiDynamicVirtualListHeight(itemIndex: 1, height: 20)]
    fixture.storage.listStorage.updateMeasuredHeightTotal()
    let span = fixture.storage.nuiTextScrollbarSpan(1, 2, 300)
    check abs(span.yFrac - 40.0'f32 / 260.0'f32) < 0.0001'f32
    check abs(span.hFrac - 20.0'f32 / 260.0'f32) < 0.0001'f32

proc frame(fixture: var MouseSelectionFixture, input: UiInputSnapshot,
    renderCursor = false, textOffsetX = 10.0'f32) =
  var b = fixture.builder.addr
  discard b[].beginUiFrame(200, 100, input)
  b[].node("mouse-test-root"):
    discard b[].fillX().fillY()
    b[].nodeStorageParent()
    let rootIndex = b[].currentNodeIndex
    let storage = b[].getOrCreateTextEditorNuiStorage(b[].currentNode)
    storage.editor = fixture.editor
    storage.chunkIndex.setLen(0)
    fixture.storage = storage
    b[].node("mouse-test-list"):
      discard b[].fillX().fillY()
      if storage.renderDiff:
        discard b[].fillX(false).position(storage.diffSplitWidth, 0)
          .width(200 - storage.diffSplitWidth)
      storage.textListNodeIndex = b[].currentNodeIndex
      for row, text in ["abc", "xyz"]:
        b[].node(row.uint64):
          let index = b[].currentNodeIndex
          discard b[].position(textOffsetX, row.float32 * 20).fit()
            .textStyleIndex(int(UiStyleIndexDefaultText)).text(text)
          storage.chunkIndex.add TextChunkIndexEntry(nodeIndex: index,
            point: point(row, 0), endPoint: point(row, 3),
            displayPoint: displayPoint(row, 0), displayEndPoint: displayPoint(row, 3),
            posX: textOffsetX, posY: row.float32 * 20)
      b[].node("scrollbar"):
        discard b[].position(190, 0).size(10, 100)
        storage.listStorage = UiDynamicVirtualListStorage(
          scrollbarTrackIndex: b[].currentNodeIndex,
          horizontalScrollbarTrackIndex: -1, horizontalScrollbarThumbIndex: -1,
          viewportWidth: if storage.renderDiff: 100 else: 200, viewportHeight: 100)
    b[].node("mouse-test-input"):
      discard b[].noHover().deferBuild(buildTextMouseSelectionNui, rootIndex)
    if renderCursor:
      storage.theme = Theme()
      storage.charWidth = 10
      storage.lineHeight = 20
      b[].node("mouse-test-cursor"):
        discard b[].fillX().fillY().noHover()
        discard b[].deferBuild(buildTextCursorNui, rootIndex)
  b[].endUiFrame(buildMeshRenderCommands = false)

suite "Text mouse selection gestures":
  test "same-frame press and release detects successive clicks":
    for thick in [false, true]:
      var fixture = newMouseSelectionFixture()
      fixture.editor.platform.supportsThinCursor = not thick
      let mouse = nuiMath.vec2(if thick: 25.0'f32 else: 21.0'f32, 10)
      fixture.frame(UiInputSnapshot(mouse: mouse), renderCursor = true)
      for count in 1'u8..3'u8:
        fixture.frame(UiInputSnapshot(mouse: mouse, mousePressed: {MouseLeft},
          mouseReleased: {MouseLeft}, mouseClickCount: count), renderCursor = true)
        fixture.builder.flushNextFrameActions()
        check not fixture.storage.mouseSelecting
      check fixture.commands[] == @["single", "double", "triple"]

  test "successive clicks pass through thin and thick cursor overlays":
    for thick in [false, true]:
      var fixture = newMouseSelectionFixture()
      fixture.editor.platform.supportsThinCursor = not thick
      let mouse = nuiMath.vec2(if thick: 25.0'f32 else: 21.0'f32, 10)
      fixture.frame(UiInputSnapshot(mouse: mouse), renderCursor = true)
      for count in 1'u8..3'u8:
        fixture.frame(UiInputSnapshot(mouse: mouse, mousePressed: {MouseLeft},
          mouseDown: {MouseLeft}, mouseClickCount: count), renderCursor = true)
        fixture.builder.flushNextFrameActions()
        fixture.frame(UiInputSnapshot(mouse: mouse, mouseReleased: {MouseLeft}),
          renderCursor = true)
        fixture.builder.flushNextFrameActions()
      check fixture.commands[] == @["single", "double", "triple"]

  test "press drag release captures across rows and ends on release":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}, mouseClickCount: 1))
    fixture.builder.flushNextFrameActions()
    check fixture.storage.mouseSelecting
    check fixture.editor.selection == (0, 1).toSelection
    check fixture.commands[] == @["single"]
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(25, 30),
      mouseDown: {MouseLeft}, mouseDelta: nuiMath.vec2(10, 20)))
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == ((0, 1), (1, 2))
    check fixture.commands[] == @["single", "single"]
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(35, 30),
      mouseDelta: nuiMath.vec2(10, 0), mouseReleased: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == ((0, 1), (1, 3))
    check not fixture.storage.mouseSelecting
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == ((0, 1), (1, 3))

  test "double and triple click commands are reused during dragging":
    for (count, command) in [(2'u8, "double"), (3'u8, "triple")]:
      var fixture = newMouseSelectionFixture()
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
        mousePressed: {MouseLeft}, mouseDown: {MouseLeft}, mouseClickCount: 1))
      fixture.builder.flushNextFrameActions()
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10), mouseReleased: {MouseLeft}))
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
        mousePressed: {MouseLeft}, mouseDown: {MouseLeft}, mouseClickCount: count))
      fixture.builder.flushNextFrameActions()
      check fixture.commands[] == @["single", command]
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(25, 30),
        mouseDelta: nuiMath.vec2(10, 20), mouseDown: {MouseLeft}))
      fixture.builder.flushNextFrameActions()
      check fixture.commands[] == @["single", command, command]

  test "multiclick threshold is an inclusive two-pixel radius":
    for (dx, dy, command) in [(2.0'f32, 0.0'f32, "double"),
        (0.0'f32, 2.0'f32, "double"), (1.0'f32, 1.0'f32, "double"),
        (2.01'f32, 0.0'f32, "single"), (0.0'f32, 2.01'f32, "single"),
        (1.5'f32, 1.5'f32, "single")]:
      var fixture = newMouseSelectionFixture()
      let first = nuiMath.vec2(15, 10)
      let second = nuiMath.vec2(15 + dx, 10 + dy)
      fixture.frame(UiInputSnapshot(mouse: first))
      fixture.frame(UiInputSnapshot(mouse: first, mousePressed: {MouseLeft},
        mouseDown: {MouseLeft}, mouseClickCount: 1))
      fixture.builder.flushNextFrameActions()
      fixture.frame(UiInputSnapshot(mouse: first, mouseReleased: {MouseLeft}))
      fixture.frame(UiInputSnapshot(mouse: second, mousePressed: {MouseLeft},
        mouseDown: {MouseLeft}, mouseClickCount: 2))
      fixture.builder.flushNextFrameActions()
      check fixture.commands[] == @["single", command]

  test "triple-click distance is measured from the first click":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    for (count, x) in [(1'u8, 15.0'f32), (2'u8, 16.5'f32), (3'u8, 18.0'f32)]:
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(x, 10),
        mousePressed: {MouseLeft}, mouseDown: {MouseLeft}, mouseClickCount: count))
      fixture.builder.flushNextFrameActions()
      fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(x, 10), mouseReleased: {MouseLeft}))
    check fixture.commands[] == @["single", "double", "single"]

  test "moving away and returning invalidates multiclicks until a new first click":
    var fixture = newMouseSelectionFixture()
    let mouse = nuiMath.vec2(15, 10)
    fixture.frame(UiInputSnapshot(mouse: mouse))
    fixture.frame(UiInputSnapshot(mouse: mouse, mousePressed: {MouseLeft},
      mouseDown: {MouseLeft}, mouseClickCount: 1))
    fixture.builder.flushNextFrameActions()
    fixture.frame(UiInputSnapshot(mouse: mouse, mouseReleased: {MouseLeft}))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(18, 10)))
    fixture.frame(UiInputSnapshot(mouse: mouse))
    for count in [2'u8, 3'u8, 1'u8, 2'u8]:
      fixture.frame(UiInputSnapshot(mouse: mouse, mousePressed: {MouseLeft},
        mouseDown: {MouseLeft}, mouseClickCount: count))
      fixture.builder.flushNextFrameActions()
      fixture.frame(UiInputSnapshot(mouse: mouse, mouseReleased: {MouseLeft}))
    check fixture.commands[] == @["single", "single", "single", "single", "double"]

  test "multiclick without a first click in this editor acts as a single click":
    var fixture = newMouseSelectionFixture()
    let mouse = nuiMath.vec2(15, 10)
    fixture.frame(UiInputSnapshot(mouse: mouse))
    fixture.frame(UiInputSnapshot(mouse: mouse, mousePressed: {MouseLeft},
      mouseDown: {MouseLeft}, mouseClickCount: 2))
    fixture.builder.flushNextFrameActions()
    check fixture.commands[] == @["single"]

  test "control-only click runs its configured command":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}, modsDown: {ModControl}))
    fixture.builder.flushNextFrameActions()
    check fixture.commands[] == @["control"]

  test "scrollbar presses do not start selection":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(195, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(195, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check not fixture.storage.mouseSelecting
    check fixture.commands[].len == 0

  test "stationary held mouse does not re-run click commands":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10), mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check fixture.commands[] == @["single"]

  test "layout movement under a stationary held mouse does not drag":
    var fixture = newMouseSelectionFixture()
    let mouse = nuiMath.vec2(25, 10)
    fixture.frame(UiInputSnapshot(mouse: mouse))
    fixture.frame(UiInputSnapshot(mouse: mouse, mousePressed: {MouseLeft},
      mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == (0, 2).toSelection
    fixture.frame(UiInputSnapshot(mouse: mouse, mouseDown: {MouseLeft}), textOffsetX = 15)
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == (0, 2).toSelection
    check fixture.commands[] == @["single"]
    fixture.frame(UiInputSnapshot(mouse: mouse, mouseReleased: {MouseLeft}), textOffsetX = 15)
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == (0, 2).toSelection
    check not fixture.storage.mouseSelecting
    check fixture.commands[] == @["single"]

  test "drag capture continues outside the editor bounds":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(230, 150),
      mouseDelta: nuiMath.vec2(215, 140), mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check fixture.editor.selection == ((0, 1), (1, 3))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(230, 150), mouseReleased: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check not fixture.storage.mouseSelecting

  test "read-only diff pane does not start text selection":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.storage.renderDiff = true
    fixture.storage.diffSplitWidth = 100
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check not fixture.storage.mouseSelecting
    check fixture.commands[].len == 0
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(115, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(115, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.builder.flushNextFrameActions()
    check fixture.storage.mouseSelecting
    check fixture.commands[].len == 1

  test "queued click does not apply after switching documents":
    var fixture = newMouseSelectionFixture()
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10)))
    fixture.frame(UiInputSnapshot(mouse: nuiMath.vec2(15, 10),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.editor.document = TextDocument(isInitialized: true)
    fixture.builder.flushNextFrameActions()
    check fixture.commands[].len == 0
