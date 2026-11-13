discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[options, unittest]
import platform, view_panel, document_editor
import nuigi
import nuigi/core/vecmath as nuiMath

proc measureCacheText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

proc createCache(context: pointer, width, height: int): UiImageId
    {.nimcall, gcsafe, raises: [].} =
  UiImageId(1)

proc freeCache(context: pointer, image: UiImageId) {.nimcall, gcsafe, raises: [].} =
  discard

type CacheFixture = object
  builder: UiBuilder
  editor: DocumentEditor
  headers, bodies, deferred: int
  rootId, textId: UiNodeId
  animate: bool

proc countDeferred(b: var UiBuilder, nodeIndex, userData: int)
    {.nimcall, gcsafe, raises: [].} =
  let fixture = cast[ptr CacheFixture](userData)
  inc fixture.deferred
  if fixture.animate:
    b.anythingAnimating = true

proc newCacheFixture(backend = UiBackendType.Graphical, callbacks = true): CacheFixture =
  result.builder = newBuilder(measureCacheText)
  result.builder.backendType = backend
  if callbacks:
    result.builder.createCacheTextureFn = createCache
    result.builder.freeCacheTextureFn = freeCache
  result.editor = DocumentEditor()

proc render(f: var CacheFixture,
    input = UiInputSnapshot(mouse: nuiMath.vec2(900, 700)),
    width = 800.0'f32, active = false, showHeader = true, fitContentY = false,
    actions = false, cornerRadius = 8.0'f32, contentPadding = 4.0'f32,
    headerCornerRadius = 7.0'f32, contentCornerRadius = 8.0'f32,
    headerPadding = 6.0'f32, headerGap = 4.0'f32,
    headerContentGap = 4.0'f32, headerActionsGap = 4.0'f32) =
  var b = f.builder.addr
  discard b[].beginUiFrame(1000, 800, input)
  b[].node:
    discard b[].size(width, 600)
    let dirty = f.editor.dirty
    f.editor.resetDirty()
    var options = ViewPanelOptions(cacheSubtree: true, cacheDirty: dirty,
      fitContentY: fitContentY, cornerRadius: cornerRadius,
      contentPadding: contentPadding, headerCornerRadius: some(headerCornerRadius),
      contentCornerRadius: some(contentCornerRadius), headerPadding: headerPadding,
      headerGap: headerGap, headerContentGap: headerContentGap,
      headerActionsGap: headerActionsGap)
    if actions:
      let editor = f.editor
      options.onClose = proc(keepHidden: bool) {.gcsafe, raises: [].} =
        editor.markDirty()
    b[].viewPanel("text-root", active, showHeader, options):
      inc f.headers
      b[].node:
        discard b[].fit().text("Header")
    do:
      inc f.bodies
      f.rootId = b[].currentParent.id
      b[].node:
        f.textId = b[].currentNode.id
        discard b[].fit().text("Text")
      b[].node:
        discard b[].size(0, 0).position(0, 0).noHover()
          .deferBuild(countDeferred, cast[int](f.addr))
    b[].node:
      discard b[].size(1, 1).text("Sibling")
  b[].endUiFrame(buildMeshRenderCommands = false)

proc cached(f: CacheFixture): bool =
  let index = f.builder.currentNodeIndex(f.rootId)
  index >= 0 and {UseCachedTexture, CopiedFromPreviousFrame} <=
    f.builder.frame.nodes[index].flags

suite "View panel subtree cache":
  test "fresh view-action closures do not invalidate an otherwise clean root":
    var f = newCacheFixture()
    f.render(actions = true)
    f.render(actions = true)
    check f.cached
    check f.headers == 1
    check f.bodies == 1
    f.builder.clearWidgetCaches()

  test "clean frames reuse the entire root and skip header body and deferred builders":
    var f = newCacheFixture()
    f.render()
    check not f.cached
    let textCount = f.builder.frame.nodes.len
    f.render()
    check f.cached
    check f.headers == 1
    check f.bodies == 1
    check f.deferred == 1
    check f.builder.frame.nodes.len == textCount
    let textIndex = f.builder.currentNodeIndex(f.textId)
    check f.builder.nodeText(textIndex).text == "Text".uiString
    check f.builder.stack.len == 0
    f.editor.markDirty()
    f.render()
    check not f.cached
    check f.headers == 2
    check f.bodies == 2
    check f.deferred == 2
    check not f.editor.dirty
    f.render()
    check f.cached
    f.builder.clearWidgetCaches()

  test "hover movement click drag release and hover exit rebuild before caching resumes":
    var f = newCacheFixture()
    f.render()
    f.render()
    check f.cached
    var input = UiInputSnapshot(mouse: nuiMath.vec2(10, 10))
    for frame in 0 ..< 3:
      f.render(input)
      check not f.cached
      input.mouse.x += 1
      input.mouseDelta.x = 1
    input.mousePressed = {MouseLeft}
    input.mouseDown = {MouseLeft}
    f.render(input)
    check not f.cached
    input.mouse = nuiMath.vec2(900, 700)
    input.mousePressed = {}
    f.render(input)
    check not f.cached
    input.mouseDown = {}
    input.mouseReleased = {MouseLeft}
    f.render(input)
    check not f.cached
    f.render()
    check f.cached
    f.render(UiInputSnapshot(mouse: nuiMath.vec2(10, 10)))
    f.render()
    check not f.cached
    f.render()
    check f.cached
    f.builder.clearWidgetCaches()

  test "animations continue after the mouse leaves until they settle":
    var f = newCacheFixture()
    f.animate = true
    f.render()
    f.render()
    f.render()
    check f.deferred == 3
    check not f.cached
    f.animate = false
    f.render()
    check not f.cached
    f.render()
    check f.cached
    f.builder.clearWidgetCaches()

  test "theme metrics size active state header visibility and fitting invalidate":
    var f = newCacheFixture()
    f.render()
    f.render()
    check f.cached
    f.builder.themeStyles[int(UiStyleIndexPanel)].fillColor = rgba(1, 0, 0, 1)
    f.render()
    check not f.cached
    f.render()
    check f.cached
    f.builder.themeTextStyles[int(UiStyleIndexDefaultText)].fontSize += 1
    f.render()
    check not f.cached
    f.render(width = 700)
    check not f.cached
    f.render(width = 700, active = true)
    check not f.cached
    f.render(width = 700, active = true, showHeader = false)
    check not f.cached
    f.render(width = 700, active = true, showHeader = false, fitContentY = true)
    check not f.cached
    f.render(width = 700, active = true, showHeader = false, fitContentY = true)
    check f.cached
    f.builder.clearWidgetCaches()

  test "panel geometry changes invalidate":
    var f = newCacheFixture()
    f.render()
    f.render()
    check f.cached
    f.render(cornerRadius = 10)
    check not f.cached
    f.render(cornerRadius = 10)
    check f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9)
    check not f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9)
    check f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9, contentCornerRadius = 6)
    check not f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9,
      contentCornerRadius = 6, headerPadding = 8)
    check not f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9,
      contentCornerRadius = 6, headerPadding = 8, headerGap = 7)
    check not f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9,
      contentCornerRadius = 6, headerPadding = 8, headerGap = 7,
      headerContentGap = 8)
    check not f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9,
      contentCornerRadius = 6, headerPadding = 8, headerGap = 7,
      headerContentGap = 8, headerActionsGap = 9)
    check not f.cached
    f.render(cornerRadius = 10, headerCornerRadius = 9,
      contentCornerRadius = 6, headerPadding = 8, headerGap = 7,
      headerContentGap = 8, headerActionsGap = 9, contentPadding = 8)
    check not f.cached
    f.builder.clearWidgetCaches()

  test "terminal and missing texture callbacks keep rebuilding normally":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      for callbacks in [false, true]:
        if backend == UiBackendType.Graphical and callbacks:
          continue
        var f = newCacheFixture(backend, callbacks)
        f.render()
        f.render()
        check not f.cached
        check f.headers == 2
        check f.bodies == 2
        check f.deferred == 2
