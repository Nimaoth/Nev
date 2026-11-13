discard """
  action: "run"
  cmd: "nim $target -d:nuiDebug --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/text/widget_builder_text_document
{.pop.}
{.pop.}
{.pop.}
{.pop.}

import std/[unittest, importutils, sequtils]
import nuigi/core/vecmath as nuiMath
import nuigi/core/array_view
import text_component, inlay_hint_component
import completion
import misc/jsonex

proc measureCachedText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.runeLen.int.float32 * 10, 20)

proc createTextCache(context: pointer, width, height: int): UiImageId
    {.nimcall, gcsafe, raises: [].} =
  UiImageId(1)

proc freeTextCache(context: pointer, image: UiImageId) {.nimcall, gcsafe, raises: [].} =
  discard

type TextCacheFixture = object
  builder: UiBuilder
  editor: TextDocumentEditor
  rootIndex: int
  storage: TextDocumentEditorNuiStorage

proc newTextCacheFixture(): TextCacheFixture =
  privateAccess(TextDocumentEditor)
  result.builder = newBuilder(measureCachedText)
  result.builder.createCacheTextureFn = createTextCache
  result.builder.freeCacheTextureFn = freeTextCache
  let document = TextDocument(isInitialized: true, textComponent: newTextComponent())
  document.textComponent.buffer = initBuffer(content = "abc\n".repeat(100))
  let displayMap = DisplayMap.new()
  displayMap.setBuffer(document.buffer.snapshot.clone())
  let services = Services()
  services.addService(ThemeService.serviceName, ThemeService(theme: Theme()))
  let editor = TextDocumentEditor(document: document, displayMap: displayMap,
    services: services, renderHeader: false,
    platform: Platform(supportsThinCursor: true,
      charWidthImpl: proc(self: Platform): float {.gcsafe, raises: [].} = 10,
      lineHeightImpl: proc(self: Platform): float {.gcsafe, raises: [].} = 20),
    config: ConfigStore.new("cache-test", "", nil, newJexObject()),
    textEditorComponent: newTextEditorComponent(document))
  editor.textEditorComponent.displayMap = displayMap
  editor.addComponent(editor.textEditorComponent)
  editor.decorations = newDecorationComponent(displayMap)
  editor.addComponent(editor.decorations)
  editor.inlayHints = newInlayHintComponent(displayMap)
  editor.addComponent(editor.inlayHints)
  editor.config.setTextWrapLines(false)
  editor.config.setUiSyntaxHighlighting(false)
  editor.config.setUiLineNumbers(LineNumbers.None)
  result.editor = editor

proc render(f: var TextCacheFixture,
    input = UiInputSnapshot(mouse: nuiMath.vec2(250, 150)), mesh = false) =
  var b = f.builder.addr
  discard b[].beginUiFrame(300, 200, input)
  b[].node("test-overlays"):
    discard b[].size(300, 200)
    b[].overlays = b[].currentNode.id
  b[].node:
    discard b[].size(200, 100)
    f.rootIndex = b[].frame.nodes.len
    f.editor.createUINui(b[])
  b[].endUiFrame(buildMeshRenderCommands = mesh)
  for index in 0 ..< b[].frame.nodes.len:
    let storage = b[].nodeStorageGet(b[].frame.nodes[index].addr)
    if storage != nil and storage of TextDocumentEditorNuiStorage:
      f.storage = TextDocumentEditorNuiStorage(storage)
      break

proc cached(f: TextCacheFixture): bool =
  {CopiedFromPreviousFrame, UseCachedTexture} <=
    f.builder.frame.nodes[f.rootIndex].flags

proc popupIndex(f: TextCacheFixture): int =
  for index, node in f.builder.frame.nodes:
    if node.debugName == "text-completions-popup-overlay":
      return index
  -1

proc cursorLayerIndex(f: TextCacheFixture): int =
  for index, node in f.builder.frame.nodes:
    if node.debugName == "text-cursor-layer":
      return index
  -1

proc enableCompletionPopup(f: var TextCacheFixture) =
  privateAccess(TextDocumentEditor)
  f.editor.active = true
  f.editor.showCompletions = true
  f.editor.completionsDirty = false
  f.editor.completions = @[Completion(item: CompletionItem(label: "cachedCompletion"))]
  f.editor.completionMatches = @[(index: 0, score: 0.0)]
  f.editor.completionMatchPositions[0] = @[]
  f.editor.markDirty()

suite "Text editor whole-root cache":
  test "completion popup stays visible during idle and continuous off-editor hover":
    var f = newTextCacheFixture()
    f.render()
    f.render()
    check f.cached
    f.enableCompletionPopup()
    f.render()
    require f.popupIndex >= 0
    check not f.cached
    for frame in 0 ..< 12:
      let index = f.popupIndex
      require index >= 0
      let pos = f.builder.absoluteNodePos(index)
      f.render(UiInputSnapshot(mouse: pos + nuiMath.vec2(220 + frame.float32, 10),
        mouseDelta: nuiMath.vec2(1, 0)))
      check f.popupIndex >= 0
      check not f.cached
      check f.builder.wasHovered(f.popupIndex, includeChildren = true)
    for frame in 0 ..< 3:
      f.render()
      check f.popupIndex >= 0
      check not f.cached
    f.editor.showCompletions = false
    f.editor.markDirty()
    f.render()
    check f.popupIndex == -1
    f.render()
    check f.cached
    f.builder.clearWidgetCaches()

suite "Text cursor rendering":
  test "cursor moves to selection and cache resumes on the next frame":
    for mesh in [false, true]:
      var f = newTextCacheFixture()
      f.render(mesh = mesh)
      f.render(mesh = mesh)
      check f.cached
      f.editor.textEditorComponent.setSelections(@[point(0, 3)...point(0, 3)])
      f.editor.markDirty()
      f.render(mesh = mesh)
      require f.cursorLayerIndex >= 0
      let layer = f.cursorLayerIndex
      let children = f.builder.children(layer).toSeq
      require children.len == 1
      let cursor = children[0]
      check f.builder.frame.nodes[cursor].pos.x == 30
      check not f.editor.dirty
      f.render(mesh = mesh)
      check f.cached
      check not f.builder.anythingAnimating
      f.builder.clearWidgetCaches()

  test "multiple block cursors retain independent positions and inverted glyphs":
    var f = newTextCacheFixture()
    f.editor.platform.supportsThinCursor = false
    f.editor.textEditorComponent.setSelections(@[
      point(0, 0)...point(0, 0), point(1, 0)...point(1, 0)])
    f.render()
    f.editor.textEditorComponent.setSelections(@[
      point(0, 2)...point(0, 2), point(1, 1)...point(1, 1)])
    f.editor.markDirty()
    f.render()
    let layer = f.cursorLayerIndex
    let children = f.builder.children(layer).toSeq
    require children.len == 4
    check f.builder.frame.nodes[children[0]].pos.x == 20
    check f.builder.frame.nodes[children[0]].size.x == 10
    check f.builder.frame.nodes[children[2]].pos.x == 10
    for child in [children[1], children[3]]:
      check f.builder.frame.nodes[child].textIndex > 0
    f.builder.clearWidgetCaches()

  test "cursor theme overrides preserve transparency and reset on switch":
    var f = newTextCacheFixture()
    f.render()
    f.storage.theme.colors["cursor-text.foreground"] = chroma.color(0, 1, 0, 0.5)
    f.builder.syncThemeStyles(f.storage.theme)
    f.editor.textEditorComponent.setSelections(@[point(0, 3)...point(0, 3)])
    f.editor.markDirty()
    f.render()
    let cursor = f.builder.children(f.cursorLayerIndex).toSeq[0]
    check f.builder.nodeStyle(cursor)[].fillColor == rgba(0.0, 1.0, 0.0, 0.5)
    f.storage.theme.colors.clear()
    f.builder.syncThemeStyles(f.storage.theme)
    f.editor.textEditorComponent.setSelections(@[point(0, 0)...point(0, 0)])
    f.editor.markDirty()
    f.render()
    let reset = f.builder.children(f.cursorLayerIndex).toSeq[0]
    let fg = f.builder.themeTextStyle(UiStyleIndexCursorText)[].textColor
    check f.builder.nodeStyle(reset)[].fillColor == fg
    f.builder.clearWidgetCaches()

  test "hidden and offscreen cursors do not render":
    for hidden in [false, true]:
      var f = newTextCacheFixture()
      f.render()
      f.editor.textEditorComponent.setSelections(@[point(0, 3)...point(0, 3)])
      f.editor.markDirty()
      f.render()
      require f.builder.childCount(f.cursorLayerIndex) == 1
      if hidden:
        f.editor.cursorVisible = false
      else:
        f.editor.textEditorComponent.setSelections(@[point(99, 0)...point(99, 0)])
      f.editor.markDirty()
      f.render()
      check f.builder.childCount(f.cursorLayerIndex) == 0
      check not f.builder.anythingAnimating
      f.builder.clearWidgetCaches()

suite "Text editor whole-root cache":
  test "clean root copies rendered text and dirty rebuild refreshes chunk indices":
    var f = newTextCacheFixture()
    f.render()
    require f.storage != nil
    require f.storage.chunkIndex.len > 0
    let chunkCount = f.storage.chunkIndex.len
    f.render()
    check f.cached
    check f.storage.chunkIndex.len == chunkCount
    f.editor.markDirty()
    f.render()
    check not f.cached
    check not f.editor.dirty
    require f.storage.chunkIndex.len > 0
    for entry in f.storage.chunkIndex:
      let node = f.builder.frame.nodes[entry.nodeIndex]
      require node.textIndex > 0
      check f.builder.frame.texts[node.textIndex.int - 1].text.value.len > 0
    f.render()
    check f.cached
    f.builder.clearWidgetCaches()

  test "hover and pending scroll rebuild and smooth scrolling continues off-root":
    var f = newTextCacheFixture()
    f.render()
    f.render()
    check f.cached
    f.render(UiInputSnapshot(mouse: nuiMath.vec2(50, 25)))
    check not f.cached
    f.render(UiInputSnapshot(mouse: nuiMath.vec2(50, 25),
      wheel: nuiMath.vec2(0, -1)))
    check not f.cached
    let before = f.storage.listStorage.scrollOffsetY
    f.render()
    check not f.cached
    check f.storage.listStorage.scrollOffsetY > before
    for i in 0 ..< 60:
      f.render()
    check f.cached
    f.editor.textEditorComponent.nuiPendingScrollDeltaY = 20
    f.render()
    check not f.cached
    check f.editor.textEditorComponent.nuiPendingScrollDeltaY == 0
    f.builder.clearWidgetCaches()
