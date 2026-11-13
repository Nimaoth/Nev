discard """
  action: "run"
  cmd: "nim $target --app:console --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/text/widget_builder_text_document
{.pop.}
{.pop.}
{.pop.}
{.pop.}

import std/[unittest, sequtils]
import nuigi/core/vecmath as nuiMath
import nuigi/core/array_view
import text_component
import misc/[event, jsonex]

proc measureCommandText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.runeLen.int.float32 * fontSize, fontSize * 2)
  result.ascent = fontSize

type CommandFixture = object
  builder: UiBuilder
  editor: TextDocumentEditor
  storage: TextDocumentEditorNuiStorage

proc newCommandFixture(content: string, split = false): CommandFixture =
  result.builder = newBuilder(measureCommandText)
  let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
  document.textComponent.buffer = initBuffer(content = content)
  let displayMap = DisplayMap.new()
  displayMap.setBuffer(document.buffer.snapshot.clone())
  result.editor = TextDocumentEditor(document: document, displayMap: displayMap,
    config: ConfigStore.new("render-command-test", "", nil, newJexObject()),
    decorations: newDecorationComponent(displayMap))
  result.storage = TextDocumentEditorNuiStorage(editor: result.editor,
    arena: initArena(), lineHeight: 20, charWidth: 10, itemHeightHint: 20,
    cursorDisplayLine: -1, lineNumbers: LineNumbers.None,
    displayLineCount: result.editor.numDisplayLines)
  if split:
    let overlay = displayMap.overlay
    let id = overlay.allocateId().get
    let old = overlay.snapshot.clone()
    let patch = overlay.snapshot.addOverlay(point(0, 1)...point(0, 1), "XY", id)
    overlay.onUpdated.invoke((overlay, old, patch, @[id]))

proc render(f: var CommandFixture, mesh = false, diff = false) =
  discard f.builder.beginUiFrame(300, 200)
  createNuiIter(f.editor, f.storage, f.builder)
  f.storage.textIter.seekLine(0)
  discard f.storage.textIter.next()
  f.storage.chunkIndex.setLen(0)
  f.builder.node:
    discard f.builder.size(300, 200)
    if diff:
      f.builder.nodeStorage(f.builder.currentNode, f.storage)
      let root = f.builder.currentNodeIndex
      f.editor.diffDocument = f.editor.document
      f.editor.diffDisplayMap = f.editor.displayMap
      createNuiDiffIter(f.editor, f.storage, f.builder)
      f.storage.diffIterNextRow = -1
      f.builder.buildTextDiffLineNui(0, root)
    else:
      var height = 20.0'f32
      f.builder.buildInteractiveTextLineNui(0, f.storage, f.editor, height)
  f.builder.endUiFrame(buildMeshRenderCommands = mesh)

suite "Text line rendering":
  test "multiple chunks retain independent text nodes and bounds":
    for mesh in [false, true]:
      var f = newCommandFixture("abc", split = true)
      f.render(mesh)
      require f.storage.chunkIndex.len >= 3
      var nodes: seq[int]
      var x = 0.0'f32
      for i, entry in f.storage.chunkIndex:
        check entry.nodeIndex notin nodes
        nodes.add entry.nodeIndex
        let node = f.builder.frame.nodes[entry.nodeIndex]
        check entry.posX == x
        check node.size.x > 0
        require node.textIndex > 0
        let text = f.builder.frame.texts[node.textIndex.int - 1]
        check text.text.value.len > 0
        f.builder.frameCtx.input.mouse =
          f.builder.absoluteNodePos(entry.nodeIndex) + nuiMath.vec2(node.size.x / 2, 5)
        check f.builder.nuiMouseChunkIndex(f.storage) == i
        let anchor = f.builder.nuiPopupAnchor(f.storage, entry.point)
        check anchor.found
        x += node.size.x
      if not mesh:
        check f.builder.frameOutput.commands.countIt(
          it.kind == CmdText and it.nodeIndex.int in nodes) == nodes.len

  test "highlights measure individual chunks and terminal repaint stays selective":
    var f = newCommandFixture("abc", split = true)
    f.render()
    let color = chroma.color(0, 0, 1, 1)
    f.builder.appendTextHighlightNui(f.storage,
      ((0, 2), (0, 3)), color, false)
    require f.storage.highlightCommands.len == 2
    for i in 0 ..< 2:
      let entry = f.storage.chunkIndex[i + 1]
      let width = f.builder.frame.nodes[entry.nodeIndex].size.x
      check f.storage.highlightCommands[i].pos.x == entry.posX + width / 2
      check f.storage.highlightCommands[i].size.x == width / 2
    f.storage.highlightCommands.setLen(0)
    f.builder.backendType = UiBackendType.Terminal
    f.builder.appendTextHighlightNui(f.storage,
      ((0, 2), (0, 3)), color, false)
    require f.storage.highlightCommands.len == 4
    for i in 0 ..< 2:
      check f.storage.highlightCommands[i + 2].kind == CmdText
      check f.storage.highlightCommands[i + 2].textIndex ==
        f.builder.frame.nodes[f.storage.chunkIndex[i + 1].nodeIndex].textIndex

  test "inline custom widgets keep their measured space between chunk nodes":
    var f = newCommandFixture("abc")
    let renderer = proc(id: int, size: vmath.Vec2, localOffset: int,
        builder: var UiBuilder): vmath.Vec2 {.gcsafe, raises: [].} =
      builder.node:
        discard builder.size(size.x + 30, 60)
      vmath.vec2(size.x + 30, 60)
    let renderId = f.editor.decorations.addCustomRenderer(renderer)
    let overlay = f.editor.displayMap.overlay
    let id = overlay.allocateId().get
    let old = overlay.snapshot.clone()
    let patch = overlay.snapshot.addOverlay(point(0, 1)...point(0, 1),
      "XY", id, renderId = renderId.uint64.int,
      location = overlay_map.OverlayRenderLocation.Inline)
    overlay.onUpdated.invoke((overlay, old, patch, @[id]))
    f.render()
    require f.storage.chunkIndex.len == 3
    let entries = f.storage.chunkIndex
    check entries[2].posX == entries[1].posX +
      f.builder.frame.nodes[entries[1].nodeIndex].size.x + 30
    let row = f.builder.frame.nodes[entries[0].nodeIndex].parent
    check f.builder.frame.nodes[row].size.y == 60

  test "empty lines keep an indexed placeholder text node":
    var f = newCommandFixture("")
    f.render()
    require f.storage.chunkIndex.len == 1
    let entry = f.storage.chunkIndex[0]
    let node = f.builder.frame.nodes[entry.nodeIndex]
    require node.textIndex > 0
    check f.builder.frame.texts[node.textIndex.int - 1].text.value == " "
    check entry.point == entry.endPoint

  test "read-only diff chunks retain separate text nodes":
    var f = newCommandFixture("abc", split = true)
    f.render(diff = true)
    var texts: seq[string]
    for i, node in f.builder.frame.nodes:
      if node.textIndex > 0:
        texts.add f.builder.nodeText(i).text.value
    check texts == @["a", "XY", "bc"]

  test "context chunk styles sizes and underlines survive rendering":
    var b = newBuilder(measureCommandText)
    discard b.beginUiFrame(200, 100)
    b.node:
      let color = rgba(1, 0, 0, 1)
      let underline = rgba(0, 1, 0, 1)
      b.buildTextContextChunksNui([
        TextContextChunk(text: "ab", color: color, fontSize: 24,
          textFlags: {UiTextFlag.Bold, UiTextFlag.Italic, UiTextFlag.Underline},
          underlineColor: underline)])
      let node = b.frame.nodes[b.lastNodeIndex]
      let text = b.frame.texts[node.textIndex.int - 1]
      check text.text.value == "ab"
      check text.fontSize == 24
      check text.textFlags == {UiTextFlag.Bold, UiTextFlag.Italic, UiTextFlag.Underline}
      check text.textColor == color
      check text.underlineColor == underline
      check node.size.x == 48
      check node.size.y == 48
    b.endUiFrame()

  test "context text retains independent chunk measurements":
    var b = newBuilder(measureCommandText)
    discard b.beginUiFrame(200, 100)
    b.layoutHorizontal:
      discard b.size(200, 100)
      let owner = b.currentNodeIndex
      b.buildTextContextChunksNui([
        TextContextChunk(text: "ab", fontSize: 16, color: rgba(1, 0, 0, 1)),
        TextContextChunk(text: "cd", fontSize: 24, color: rgba(0, 1, 0, 1))])
      let chunks = b.children(owner).toSeq
      require chunks.len == 2
      check b.frame.nodes[chunks[0]].size == nuiMath.vec2(32, 32)
      check b.frame.nodes[chunks[1]].size == nuiMath.vec2(48, 48)
    b.endUiFrame()
