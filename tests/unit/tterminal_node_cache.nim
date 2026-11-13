discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/terminal/render
import std/unittest
import platform, event_service, move_database, vfs_service, workspace, command_service

gServices = Services()
gServices.addBuiltinServices()
gServices.getServiceChecked(PlatformService).setPlatform(Platform())
init_module_command_service()
init_module_vfs_service()
init_module_workspace()
init_module_event_service()
init_module_move_database()
gServices.waitForServices()

proc measureCacheText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 10, 20)

proc createCache(context: pointer, width, height: int): UiImageId
    {.nimcall, gcsafe, raises: [].} =
  UiImageId(1)

proc freeCache(context: pointer, image: UiImageId) {.nimcall, gcsafe, raises: [].} =
  discard

type TerminalCacheFixture = object
  builder: UiBuilder
  view: TerminalView
  dimensions: tuple[width, height, cellWidth, cellHeight: int]
  rootIndex: int
  storage: TerminalInputNuiStorage

proc newTerminalCacheFixture(backend = UiBackendType.Graphical): TerminalCacheFixture =
  result.builder = newBuilder(measureCacheText)
  result.builder.backendType = backend
  result.builder.createCacheTextureFn = createCache
  result.builder.freeCacheTextureFn = freeCache
  result.view = TerminalView(terminal: Terminal(width: 10, height: 4,
    historyLength: 100, cursor: (0, 0, false, CursorShape.Block, false)))
  result.view.terminal.terminalBuffer.initTerminalBuffer(10, 104)
  var cell = TerminalChar(fg: fgNone, bg: bgNone)
  cell.appendChsFromRune('A'.Rune, false)
  for row in 0 ..< 104:
    result.view.terminal.terminalBuffer[0, row] = cell

proc render(f: var TerminalCacheFixture,
    input = UiInputSnapshot(mouse: nuiMath.vec2(500, 300)), width = 400.0'f32) =
  var b = f.builder.addr
  discard b[].beginUiFrame(600, 400, input)
  b[].node:
    discard b[].size(width, 250)
    f.rootIndex = b[].frame.nodes.len
    var w, h, cw, ch: int
    f.view.renderTerminalNui(b[], w, h, cw, ch)
    f.dimensions = (w, h, cw, ch)
  b[].endUiFrame(buildMeshRenderCommands = false)
  for index in 0 ..< b[].frame.nodes.len:
    let storage = b[].nodeStorageGet(b[].frame.nodes[index].addr)
    if storage != nil and storage of TerminalInputNuiStorage:
      f.storage = TerminalInputNuiStorage(storage)
      break

proc cached(f: TerminalCacheFixture): bool =
  {CopiedFromPreviousFrame, UseCachedTexture} <=
    f.builder.frame.nodes[f.rootIndex].flags

proc captureMoves(view: TerminalView): ref int =
  result = new(int)
  let moves = result
  view.onMove = proc(view: TerminalView, col, row: int) {.gcsafe, raises: [].} =
    inc moves[]

proc countingEditor(builds: ref int): DocumentEditor =
  result = DocumentEditor()
  result.renderNuiImpl = proc(self: DocumentEditor, b: var UiBuilder) {.gcsafe, raises: [].} =
    inc builds[]
    self.resetDirty()
    b.node:
      discard b.fill().text("Snapshot")

suite "Terminal whole-root cache":
  test "clean roots retain positive cell dimensions and dirty updates rebuild":
    var f = newTerminalCacheFixture()
    f.render()
    let dimensions = f.dimensions
    check dimensions.width > 0 and dimensions.height > 0
    check dimensions.cellWidth == 10 and dimensions.cellHeight == 20
    f.render()
    check f.cached
    check f.dimensions == dimensions
    f.view.markDirtyBase()
    f.view.terminal.command = "updated command"
    f.render()
    check not f.cached
    check not f.view.dirty
    var updated = false
    for text in f.builder.frame.texts:
      if text.text == "updated command".uiString:
        updated = true
    check updated
    f.render()
    check f.cached
    f.render(width = 300)
    check not f.cached
    check f.dimensions.width < dimensions.width
    f.builder.clearWidgetCaches()

  test "hover runs mouse handlers and wheel motion continues after hover exit":
    var f = newTerminalCacheFixture()
    let moves = captureMoves(f.view)
    f.render()
    f.render()
    check f.cached
    let bodyPos = f.builder.absoluteNodePos(
      f.builder.currentNodeIndex(f.builder.frame.nodes[f.rootIndex].id))
    var input = UiInputSnapshot(mouse: bodyPos + nuiMath.vec2(50, 100),
      mouseDelta: nuiMath.vec2(1, 0))
    f.render(input)
    check not f.cached
    check moves[] == 1
    input.wheel = nuiMath.vec2(0, 1)
    f.render(input)
    let before = f.storage.list.scrollOffsetY
    f.render()
    check not f.cached
    check f.storage.list.scrollOffsetY < before
    for frame in 0 ..< 60:
      f.render()
    check f.cached
    f.view.terminal.pendingScrollRows = -2
    f.render()
    check not f.cached
    check f.view.terminal.pendingScrollRows == 0
    f.builder.clearWidgetCaches()

  test "embedded editor dirty state invalidates the outer terminal cache":
    var f = newTerminalCacheFixture()
    let builds = new(int)
    let editor = countingEditor(builds)
    f.view.bufferEditor = editor
    f.render()
    f.render()
    check f.cached
    check builds[] == 1
    editor.markDirty()
    f.render()
    check not f.cached
    check builds[] == 2
    f.builder.clearWidgetCaches()

  test "terminal backends keep normal rendering and viewport dimensions":
    var f = newTerminalCacheFixture(UiBackendType.Terminal)
    f.render()
    let dimensions = f.dimensions
    f.render()
    check not f.cached
    check f.dimensions == dimensions
