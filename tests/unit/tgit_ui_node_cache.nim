discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/git_ui
import std/unittest
import nuigi/core/vecmath as nuiMath
import platform, event_service, move_database, vfs_service, workspace, command_service

proc measureCacheText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

proc createCache(context: pointer, width, height: int): UiImageId
    {.nimcall, gcsafe, raises: [].} =
  UiImageId(1)

proc freeCache(context: pointer, image: UiImageId) {.nimcall, gcsafe, raises: [].} =
  discard

type GitCacheFixture = object
  builder: UiBuilder
  view: GitUiView
  rootIndex: int

proc newGitCacheFixture(backend = UiBackendType.Graphical): GitCacheFixture =
  result.builder = newBuilder(measureCacheText)
  result.builder.backendType = backend
  result.builder.createCacheTextureFn = createCache
  result.builder.freeCacheTextureFn = freeCache
  let document = Document()
  let text = newTextComponent()
  text.buffer = initBuffer(content = "Commit message")
  document.addComponent(text)
  result.view = GitUiView(lastUpdate: 1, commitsFetched: true, commitDoc: document,
    themes: ThemeService(theme: Theme()))

proc render(f: var GitCacheFixture,
    input = UiInputSnapshot(mouse: nuiMath.vec2(900, 700))) =
  var b = f.builder.addr
  discard b[].beginUiFrame(1000, 800, input)
  b[].node:
    discard b[].size(800, 600)
    f.rootIndex = b[].frame.nodes.len
    f.view.renderGitUiNui(b[])
  b[].endUiFrame(buildMeshRenderCommands = false)

proc cached(f: GitCacheFixture): bool =
  {CopiedFromPreviousFrame, UseCachedTexture} <=
    f.builder.frame.nodes[f.rootIndex].flags

proc hasText(f: GitCacheFixture, value: string): bool =
  for text in f.builder.frame.texts:
    if text.text == value.uiString:
      return true

proc countingEditor(builds: ref int): DocumentEditor =
  result = DocumentEditor()
  result.renderNuiImpl = proc(self: DocumentEditor, b: var UiBuilder) {.gcsafe, raises: [].} =
    inc builds[]
    self.resetDirty()
    b.node:
      discard b.fill().text("Commit editor")

suite "Git UI whole-root cache":
  let previousServices = gServices
  setup:
    gServices = Services()
    gServices.addBuiltinServices()
    gServices.getServiceChecked(PlatformService).setPlatform(Platform())
    init_module_command_service()
    init_module_vfs_service()
    init_module_workspace()
    init_module_event_service()
    init_module_move_database()
    gServices.addService(LayoutService.serviceName, LayoutService())
    gServices.waitForServices()
  teardown:
    gServices = previousServices

  test "clean root reuses header and content and refresh messages invalidate":
    var f = newGitCacheFixture()
    f.render()
    check f.hasText("Git")
    check f.hasText("Commit message")
    f.render()
    check f.cached
    f.view.lastMessage = "Updated repository"
    f.view.vcsService = VCSService()
    waitFor f.view.refreshStatusAsync()
    f.render()
    check not f.cached
    check not f.view.dirty
    check f.hasText("Updated repository")
    f.render()
    check f.cached
    f.builder.clearWidgetCaches()

  test "hover and open actions menu rebuild rather than freezing interaction":
    var f = newGitCacheFixture()
    f.render()
    f.render()
    check f.cached
    f.render(UiInputSnapshot(mouse: nuiMath.vec2(50, 50),
      mouseDelta: nuiMath.vec2(1, 0)))
    check not f.cached
    f.render()
    check not f.cached
    f.render()
    check f.cached
    f.view.actionsMenuOpen = true
    f.render()
    check not f.cached
    f.render()
    check not f.cached
    f.view.actionsMenuOpen = false
    f.view.markDirty()
    for frame in 0 ..< 60:
      f.render()
    check f.cached
    f.builder.clearWidgetCaches()

  test "dirty embedded commit editor refreshes its enclosing root":
    var f = newGitCacheFixture()
    let builds = new(int)
    let editor = countingEditor(builds)
    f.view.editCommit = true
    f.view.commitEditor = editor
    f.render()
    f.render()
    check f.cached
    check builds[] == 1
    editor.markDirty()
    f.render()
    check not f.cached
    check builds[] == 2
    f.builder.clearWidgetCaches()

  test "terminal backends render normally without cache textures":
    var f = newGitCacheFixture(UiBackendType.Terminal)
    f.render()
    f.render()
    check not f.cached
    check f.hasText("Commit message")
