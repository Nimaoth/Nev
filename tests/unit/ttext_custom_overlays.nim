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

import std/[sequtils, unittest]
import nuigi/core/vecmath as nuiMath
import text_component
import misc/[event, jsonex]

proc measureOverlayTestText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 10, 20)

type OverlayFixture = object
  builder: UiBuilder
  editor: TextDocumentEditor
  storage: TextDocumentEditorNuiStorage
  rowIndex: int

proc newOverlayFixture(): OverlayFixture =
  result.builder = newBuilder(measureOverlayTestText)
  let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
  document.textComponent.buffer = initBuffer(content = "abc")
  let displayMap = DisplayMap.new()
  displayMap.setBuffer(document.textComponent.buffer.snapshot.clone())
  result.editor = TextDocumentEditor(document: document, displayMap: displayMap,
    config: ConfigStore.new("overlay-test", "", nil, newJexObject()),
    decorations: newDecorationComponent(displayMap))
  result.storage = TextDocumentEditorNuiStorage(
    editor: result.editor, arena: initArena(), lineHeight: 20,
    charWidth: 10, itemHeightHint: 20, cursorDisplayLine: -1,
    lineNumbers: LineNumbers.None, displayLineCount: result.editor.numDisplayLines)

proc addTestOverlay(fixture: var OverlayFixture,
    location: overlay_map.OverlayRenderLocation, height: float32): CustomRendererId =
  let renderer = proc(id: int, size: vmath.Vec2, localOffset: int,
      builder: var UiBuilder): vmath.Vec2 {.gcsafe, raises: [].} =
    builder.node:
      discard builder.size(size.x, height)
    return vmath.vec2(size.x, height)
  result = fixture.editor.decorations.addCustomRenderer(renderer)
  let overlayMap = fixture.editor.displayMap.overlay
  let overlayId = overlayMap.allocateId().get
  let oldSnapshot = overlayMap.snapshot.clone()
  let patch = overlayMap.snapshot.addOverlay(point(0, 0)...point(0, 0),
    " ", overlayId, renderId = result.uint64.int, location = location)
  overlayMap.onUpdated.invoke((overlayMap, oldSnapshot, patch, @[overlayId]))

proc render(fixture: var OverlayFixture, renderDiff = false) =
  fixture.storage.chunkIndex.setLen(0)
  createNuiIter(fixture.editor, fixture.storage, fixture.builder)
  fixture.storage.textIter.seekLine(0)
  discard fixture.storage.textIter.next()
  if renderDiff:
    createNuiDiffIter(fixture.editor, fixture.storage, fixture.builder)
  discard fixture.builder.beginUiFrame(200, 200)
  fixture.builder.node:
    discard fixture.builder.size(200, 200)
    var lineHeight = 20.0'f32
    if renderDiff:
      fixture.builder.nodeStorage(fixture.builder.currentNode, fixture.storage)
      let root = fixture.builder.currentNodeIndex
      fixture.builder.layoutHorizontal:
        discard fixture.builder.fillX().fitY()
        fixture.builder.node:
          discard fixture.builder.width(100).fitY()
          fixture.builder.buildTextDiffLineNui(0, root)
        fixture.builder.node:
          discard fixture.builder.width(100).fitY()
          fixture.builder.buildInteractiveTextLineNui(
            0, fixture.storage, fixture.editor, lineHeight)
      fixture.rowIndex = fixture.builder.firstChildIndex(root)
    else:
      fixture.builder.buildInteractiveTextLineNui(
        0, fixture.storage, fixture.editor, lineHeight)
      fixture.rowIndex = fixture.builder.lastNodeIndex
  fixture.builder.endUiFrame(buildRenderCommands = false)

suite "Text custom overlay collection and ordering":
  test "plain rows do not add an above container":
    var fixture = newOverlayFixture()
    fixture.render()
    let children = toSeq(fixture.builder.children(fixture.rowIndex))
    check children.len == 1
    check fixture.builder.frame.nodes[children[0]].pos.y == 0
    check fixture.builder.frame.nodes[fixture.rowIndex].size.y == 20

  test "below-only rows retain text as the first child":
    var fixture = newOverlayFixture()
    discard fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Below, 30)
    fixture.render()
    let children = toSeq(fixture.builder.children(fixture.rowIndex))
    require children.len == 2
    check children[0] < children[1]
    check fixture.builder.frame.nodes[children[0]].pos.y == 0
    check fixture.builder.frame.nodes[children[1]].pos.y == 20
    check fixture.builder.frame.nodes[fixture.rowIndex].size.y == 50

  test "nonzero line gap adds a spacer below text":
    var fixture = newOverlayFixture()
    fixture.storage.lineGap = 5
    fixture.render()
    let children = toSeq(fixture.builder.children(fixture.rowIndex))
    require children.len == 2
    check fixture.builder.frame.nodes[children[0]].pos.y == 0
    check fixture.builder.frame.nodes[children[0]].size.y == 20
    check fixture.builder.frame.nodes[children[1]].pos.y == 20
    check fixture.builder.frame.nodes[children[1]].size.y == 5
    check fixture.builder.frame.nodes[fixture.rowIndex].size.y == 25

  test "line gap preserves above ordering and separates below overlays":
    var fixture = newOverlayFixture()
    fixture.storage.lineGap = 5
    discard fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Above, 30)
    discard fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Below, 25)
    fixture.render()
    let children = toSeq(fixture.builder.children(fixture.rowIndex))
    require children.len == 4
    check fixture.builder.frame.nodes[children[0]].pos.y == 0
    check fixture.builder.frame.nodes[children[1]].pos.y == 30
    check fixture.builder.frame.nodes[children[2]].pos.y == 50
    check fixture.builder.frame.nodes[children[2]].size.y == 5
    check fixture.builder.frame.nodes[children[3]].pos.y == 55
    check fixture.builder.frame.nodes[fixture.rowIndex].size.y == 80
    for entry in fixture.storage.chunkIndex:
      check fixture.builder.absoluteNodePos(entry.nodeIndex).y == 30

  test "both diff panes include exactly one line-gap spacer":
    for gap in [0.0'f32, 5.0'f32]:
      var fixture = newOverlayFixture()
      fixture.storage.lineGap = gap
      fixture.storage.diffSplitWidth = 100
      fixture.editor.diffDocument = fixture.editor.document
      fixture.editor.diffDisplayMap = DisplayMap.new()
      fixture.editor.diffDisplayMap.setBuffer(
        fixture.editor.document.textComponent.buffer.snapshot.clone())
      fixture.render(renderDiff = true)
      let panes = toSeq(fixture.builder.children(fixture.rowIndex))
      require panes.len == 2
      let leftContainer = toSeq(fixture.builder.children(panes[0]))
      require leftContainer.len == 1
      let leftRows = toSeq(fixture.builder.children(
        fixture.builder.firstChildIndex(leftContainer[0])))
      let rightContainer = toSeq(fixture.builder.children(panes[1]))
      require rightContainer.len == 1
      let rightRows = toSeq(fixture.builder.children(rightContainer[0]))
      for rows in [leftRows, rightRows]:
        require rows.len == (if gap == 0: 1 else: 2)
        if gap != 0:
          check fixture.builder.frame.nodes[rows[1]].pos.y == 20
          check fixture.builder.frame.nodes[rows[1]].size.y == gap
      check fixture.builder.frame.nodes[fixture.rowIndex].size.y == 20 + gap

  test "above container is built after text but ordered and positioned before it":
    var fixture = newOverlayFixture()
    discard fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Above, 30)
    discard fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Above, 40)
    discard fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Below, 25)
    fixture.render()
    let children = toSeq(fixture.builder.children(fixture.rowIndex))
    require children.len == 3
    check children[0] > children[1]
    check fixture.builder.childCount(children[0]) == 2
    check fixture.builder.frame.nodes[children[0]].pos.y == 0
    check fixture.builder.frame.nodes[children[1]].pos.y == 70
    check fixture.builder.frame.nodes[children[2]].pos.y == 90
    check fixture.builder.frame.nodes[fixture.rowIndex].size.y == 115
    for entry in fixture.storage.chunkIndex:
      check fixture.builder.absoluteNodePos(entry.nodeIndex).y == 70

  test "removed above renderers do not create or reorder a container":
    var fixture = newOverlayFixture()
    let id = fixture.addTestOverlay(overlay_map.OverlayRenderLocation.Above, 30)
    fixture.editor.decorations.removeCustomRenderer(id)
    fixture.render()
    let children = toSeq(fixture.builder.children(fixture.rowIndex))
    check children.len == 1
    check fixture.builder.frame.nodes[children[0]].pos.y == 0
