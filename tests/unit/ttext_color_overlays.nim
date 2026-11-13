discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import text/text_editor {.all.}
import config_provider, core_settings, text_component, treesitter_component, text_editor_component, vfs
import decoration_component, text/display_map
import misc/[jsonex, util, generational_seq]
import nimsumtree/[buffer, rope]
import std/[unittest, importutils, options]
import chronos
import nuigi
import nuigi/core/vecmath as nuiMath
import nuigi/widgets/colorpicker

privateAccess(TextDocumentEditor)
privateAccess(ColorOverlay)

proc measureColorText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 10, 20)

type ColorFixture = object
  editor: TextDocumentEditor
  builder: UiBuilder
  entries: seq[ColorOverlay]
  swatchIds: seq[UiNodeId]

proc newColorFixture(): ColorFixture =
  let config = ConfigStore.new("color-test", "", nil, newJexObject())
  let document = TextDocument(isInitialized: true, config: config,
    textComponent: newTextComponent(), treesitterComponent: newTreesitterComponent(default(VFS)))
  document.textComponent.buffer = initBuffer(content = "#ff0000 #0000ff")
  result.editor = TextDocumentEditor(document: document,
    config: config, textEditorComponent: newTextEditorComponent(document),
    displayMap: DisplayMap.new())
  result.editor.displayMap.setBuffer(document.buffer.snapshot.clone())
  result.editor.decorations = newDecorationComponent(result.editor.displayMap)
  result.builder = newBuilder(measureColorText)
  let snapshot = document.buffer.snapshot.clone()
  for start in [0, 8]:
    let original = $document.rope.slice(start...start + 7)
    result.entries.add ColorOverlay(document: document, original: original,
      kind: Hex, value: parseOverlayColor(original, Hex),
      first: snapshot.anchorAfter(point(0, start)),
      last: snapshot.anchorBefore(point(0, start + 7)))

proc render(fixture: var ColorFixture, activate = -1, escape = false,
    reverse = false, changeSv = false) =
  var mouse = nuiMath.vec2(0, 0)
  var svId = noneNodeId()
  if changeSv:
    let svIndex = fixture.editor.colorPickerStorage.svIdx
    mouse = fixture.builder.absoluteNodePos(svIndex) +
      fixture.builder.frame.nodes[svIndex].size * 0.5'f32
    svId = fixture.builder.frame.nodes[svIndex].id
  discard fixture.builder.beginUiFrame(500, 500,
    input = UiInputSnapshot(mouse: mouse, keysPressed: if escape: {KeyEscape} else: {}))
  if activate >= 0:
    fixture.builder.previousOutput.clickedId = fixture.swatchIds[activate]
  if changeSv:
    fixture.builder.previousOutput.clickedId = svId
  fixture.swatchIds.setLen(fixture.entries.len)
  for i in 0..<fixture.entries.len:
    let index = if reverse: fixture.entries.high - i else: i
    fixture.builder.node("color-" & $index):
      let swatchIndex = fixture.builder.frame.nodes.len
      discard fixture.editor.renderColorOverlay(fixture.entries[index], fixture.builder)
      fixture.swatchIds[index] = fixture.builder.frame.nodes[swatchIndex].id
  fixture.builder.endUiFrame(buildRenderCommands = false)

proc popupCount(fixture: ColorFixture): int =
  for node in fixture.builder.frame.nodes:
    if node.debugName == "color-picker-popup":
      inc result

proc runDeferred(fixture: var ColorFixture) =
  discard fixture.builder.beginUiFrame(500, 500)
  fixture.builder.endUiFrame(buildRenderCommands = false)

suite "Text color picker overlays":
  test "hex parsing and formatting preserve prefix case and alpha":
    check parseOverlayColor("#12345678", Hex).a == 120.0'f32 / 255
    check formatOverlayColor("#abcdef", Hex, rgba(1, 0, 0, 1)) == "#ff0000"
    check formatOverlayColor("ABCDEF80", Hex, rgba(0, 1, 0, 1)) == "00FF00FF"
    check formatOverlayColor("#ABCDEF", Hex, rgba(0, 1, 0, 0)) == "#00FF0000"

  test "float colors preserve separators and support alpha":
    check parseOverlayColor("rgba(255, 0, 0, 128)", Float255).a == 128.0'f32 / 255
    check formatOverlayColor("rgb(0.1, 0.2, 0.3)", Float1,
      rgba(1.0, 0.5, 0.0, 1.0)) == "rgb(1, 0.5, 0)"
    check formatOverlayColor("[ 1; 2; 3; 4 ]", Float255,
      rgba(1, 0, 1, 1)) == "[ 255; 0; 255; 255 ]"

  test "invalid colors are rejected":
    expect ValueError:
      discard parseOverlayColor("#12345", Hex)
    expect ValueError:
      discard parseOverlayColor("#xxxxxx", Hex)
    expect ValueError:
      discard parseOverlayColor("rgb(1, 2)", Float1)
    expect ValueError:
      discard parseOverlayColor("rgb(256, 0, 0)", Float255)

  test "the default storage API still opens and toggles closed":
    var fixture = newColorFixture()
    var value = rgba(1, 0, 0, 1)
    var swatchId = noneNodeId()
    for expectedPopups in [0, 1, 0]:
      discard fixture.builder.beginUiFrame(500, 500)
      fixture.builder.previousOutput.clickedId = swatchId
      fixture.builder.node("default-picker"):
        let index = fixture.builder.frame.nodes.len
        discard fixture.builder.colorPicker(value)
        swatchId = fixture.builder.frame.nodes[index].id
      fixture.builder.endUiFrame(buildRenderCommands = false)
      check fixture.popupCount() == expectedPopups

  test "all swatches share one storage and only one popup":
    var fixture = newColorFixture()
    fixture.render()
    let storage = fixture.editor.colorPickerStorage
    require storage != nil
    fixture.render(activate = 0)
    check fixture.editor.colorPickerStorage == storage
    check fixture.editor.editedColorOverlay == fixture.entries[0]
    check fixture.popupCount() == 1
    fixture.render(activate = 1)
    check fixture.editor.colorPickerStorage == storage
    check storage.ownerId == fixture.swatchIds[1]
    check fixture.editor.editedColorOverlay == fixture.entries[1]
    check fixture.popupCount() == 1
    fixture.render(activate = 0, reverse = true)
    check storage.ownerId == fixture.swatchIds[0]
    check fixture.popupCount() == 1

  test "closing commits on the next frame and not while open":
    var fixture = newColorFixture()
    fixture.render()
    fixture.render(activate = 0)
    fixture.editor.editedColor = rgba(0, 1, 0, 1)
    check $fixture.editor.document.rope == "#ff0000 #0000ff"
    fixture.render(escape = true)
    check fixture.editor.editedColorOverlay == nil
    check $fixture.editor.document.rope == "#ff0000 #0000ff"
    fixture.runDeferred()
    check $fixture.editor.document.rope == "#00ff00 #0000ff"
    discard fixture.editor.document.buffer.undo()
    check $fixture.editor.document.rope == "#ff0000 #0000ff"

  test "picker interactions update the editor color and commit on close":
    var fixture = newColorFixture()
    fixture.render()
    fixture.render(activate = 0)
    fixture.render(changeSv = true)
    check fixture.editor.editedColor.r == 0.5'f32
    check fixture.editor.editedColor.g == 0.25'f32
    check fixture.editor.editedColor.b == 0.25'f32
    check $fixture.editor.document.rope == "#ff0000 #0000ff"
    fixture.render(escape = true)
    fixture.runDeferred()
    check $fixture.editor.document.rope == "#7f3f3f #0000ff"

  test "switching swatches commits the old color without changing the new one":
    var fixture = newColorFixture()
    fixture.render()
    fixture.render(activate = 0)
    fixture.editor.editedColor = rgba(0, 1, 0, 1)
    fixture.render(activate = 1)
    fixture.runDeferred()
    check $fixture.editor.document.rope == "#00ff00 #0000ff"

  test "closing an unchanged color does not edit":
    var fixture = newColorFixture()
    fixture.render()
    fixture.render(activate = 0)
    fixture.render(escape = true)
    fixture.runDeferred()
    check fixture.editor.document.revision == 0

  test "anchored color edits follow preceding insertions":
    var fixture = newColorFixture()
    fixture.render()
    fixture.render(activate = 1)
    fixture.editor.editedColor = rgba(0, 1, 0, 1)
    discard fixture.editor.document.buffer.edit(@[(0...0, "prefix ")])
    fixture.editor.closeColorPicker(fixture.builder)
    fixture.runDeferred()
    check $fixture.editor.document.rope == "prefix #ff0000 #00ff00"

  test "read-only and stale source text are not replaced":
    for readOnly in [true, false]:
      var fixture = newColorFixture()
      fixture.render()
      fixture.render(activate = 0)
      fixture.editor.editedColor = rgba(0, 1, 0, 1)
      fixture.editor.document.readOnly = readOnly
      if not readOnly:
        discard fixture.editor.document.buffer.edit(@[(0...7, "#123456")])
      let before = $fixture.editor.document.rope
      fixture.editor.closeColorPicker(fixture.builder)
      fixture.runDeferred()
      check $fixture.editor.document.rope == before

  test "overlay refresh reuses renderers and disabling removes them":
    var fixture = newColorFixture()
    fixture.editor.config.setTextColorHighlightEnable(true)
    fixture.editor.config.set("text.color-highlight.regex", newJexString("#[0-9a-fA-F]{6}"))
    waitFor fixture.editor.updateColorOverlays()
    require fixture.editor.colorOverlays.len == 2
    let previous = fixture.editor.colorOverlays
    for entry in previous:
      check fixture.editor.decorations.customOverlayRenderers.tryGet(entry.rendererId).isSome
    fixture.entries = previous
    fixture.render()
    fixture.render(activate = 0)
    waitFor fixture.editor.updateColorOverlays()
    check fixture.editor.colorOverlays[0] == previous[0]
    check fixture.editor.colorOverlays[1] == previous[1]
    check fixture.editor.editedColorOverlay == previous[0]
    check fixture.editor.colorPickerStorage.open
    fixture.editor.config.setTextColorHighlightEnable(false)
    waitFor fixture.editor.updateColorOverlays()
    check fixture.editor.colorOverlays.len == 0
    check not fixture.editor.colorPickerStorage.open
    for entry in previous:
      check fixture.editor.decorations.customOverlayRenderers.tryGet(entry.rendererId).isNone
