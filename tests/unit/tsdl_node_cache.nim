discard """
  action: "run"
  cmd: "nim $target --cc:clang --passC:-Wno-incompatible-function-pointer-types -d:nuiNoHarfbuzz --path:deps/nuigi/vendor/nimfreetype --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/sdl_platform/sdl_platform

import std/unittest
import nuigi/widgets/collapsing_header
import layout/layout
import view
import service, platform, event_service, move_database, vfs_service, workspace, command_service

gServices = Services()
gServices.addBuiltinServices()
gServices.getServiceChecked(PlatformService).setPlatform(Platform())
init_module_command_service()
init_module_vfs_service()
init_module_workspace()
init_module_event_service()
init_module_move_database()
gServices.waitForServices()

proc measureSdlCacheText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

proc renderSettings(platform: SdlPlatform, settings: View) =
  discard platform.nui.beginUiFrame(1600, 1000,
    UiInputSnapshot(mouse: nuiMath.vec2(1500, 900)))
  settings.render(platform.nui)
  platform.nui.endUiFrame(buildMeshRenderCommands = false)

suite "SDL subtree texture caching":
  test "settings checkbox toggles the builder caching flag":
    let platform = newSdlPlatform().SdlPlatform
    platform.nui = newBuilder(measureSdlCacheText)
    let settings = newPlatformSettingsView(platform, LayoutService())
    platform.renderSettings(settings)
    var labelId = noneNodeId()
    for index in 0 ..< platform.nui.frame.nodes.len:
      if platform.nui.nodeText(index).text == "Node Caching".uiString:
        labelId = platform.nui.frame.nodes[index].id
    require labelId != noneNodeId()
    var checkboxId = noneNodeId()
    for index in 0 ..< platform.nui.frame.nodes.len:
      let node = platform.nui.frame.nodes[index]
      if node.semanticsIndex > 0:
        let semantics = platform.nui.frame.semantics[int(node.semanticsIndex) - 1]
        if semantics.role == SemanticCheckBox and semantics.labelledBy == labelId:
          checkboxId = node.id
    require checkboxId != noneNodeId()
    check platform.nui.cachingEnabled
    platform.nui.enqueueSemanticRequest(
      UiSemanticRequest(target: checkboxId, action: SemanticActivate))
    platform.renderSettings(settings)
    check not platform.nui.cachingEnabled
    platform.nui.enqueueSemanticRequest(
      UiSemanticRequest(target: checkboxId, action: SemanticActivate))
    platform.renderSettings(settings)
    check platform.nui.cachingEnabled

  test "cache capture restores targets, composites alpha, and keeps chevrons stationary":
    require sdl3.init(INIT_VIDEO)
    defer: sdl3.quit()
    let window = createWindow("cache-test", 64, 64, WINDOW_HIDDEN)
    require window != nil
    defer: destroyWindow(window)
    let renderer = createRenderer(window, "software")
    require renderer != nil
    defer: destroyRenderer(renderer)
    require renderer.setRenderDrawBlendMode(BLENDMODE_BLEND)
    let frameTarget = createTexture(renderer, PIXELFORMAT_RGBA32,
      TEXTUREACCESS_TARGET, 64, 64)
    require frameTarget != nil
    defer: destroyTexture(frameTarget)
    let platform = SdlPlatform(renderer: renderer)
    for mesh in [false, true]:
      platform.nui = newBuilder(measureSdlCacheText)
      platform.nui.createCacheTextureFn = createNuiCacheTexture
      platform.nui.freeCacheTextureFn = freeNuiCacheTexture
      platform.nui.cacheTextureUserData = cast[pointer](platform)
      var rootId: UiNodeId
      for frame in 0 ..< 3:
        discard platform.nui.beginUiFrame(64, 64)
        platform.nui.node:
          discard platform.nui.size(20, 20).position(10, 10)
            .fillBackground().backgroundColor(rgba(1.0, 0.0, 0.0, 0.5))
          rootId = platform.nui.currentNode.id
          let hit = platform.nui.reuseCachedNode(dirty = frame == 2)
          check hit == (frame == 1)
          if not hit:
            platform.nui.node:
              discard platform.nui.size(1, 1)
        platform.nui.endUiFrame(buildMeshRenderCommands = mesh)
        let rootIndex = platform.nui.currentNodeIndex(rootId)
        check UseCachedTexture in platform.nui.frame.nodes[rootIndex].flags
        require renderer.setRenderTarget(frameTarget)
        require renderer.setRenderDrawColor(0, 0, 0, 255)
        require renderer.renderClear()
        platform.renderNuiCommands()
        check renderer.getRenderTarget() == frameTarget
        let pixels = renderer.renderReadPixels(nil)
        require pixels != nil
        var r, g, b, a: uint8
        require pixels.readSurfacePixel(15, 15, r, g, b, a)
        check r.int in 126 .. 129
        check g == 0 and b == 0 and a == 255
        require pixels.readSurfacePixel(40, 15, r, g, b, a)
        check r == 0 and g == 0 and b == 0 and a == 255
        destroySurface(pixels)
      platform.nui.clearWidgetCaches()
    for mesh in [false, true]:
      platform.nui = newBuilder(measureSdlCacheText)
      platform.nui.createCacheTextureFn = createNuiCacheTexture
      platform.nui.freeCacheTextureFn = freeNuiCacheTexture
      platform.nui.cacheTextureUserData = cast[pointer](platform)
      var expanded = false
      platform.nui.themeTextStyle(UiStyleIndexHeaderText)[].textColor = rgba(1, 1, 1, 1)
      platform.nui.themeStyle(UiStyleIndexHeader)[].fillColor = rgba(0, 0, 0, 1)
      var reference: seq[uint32]
      var hits = 0
      var captures = 0
      for frame in 0 ..< 16:
        platform.nui.cachingEnabled = frame mod 4 != 3
        discard platform.nui.beginUiFrame(64, 64)
        var rootIndex = -1
        platform.nui.node:
          rootIndex = platform.nui.currentNodeIndex
          discard platform.nui.size(40, 30).position(10, 10)
          if platform.nui.reuseCachedNode(dirty = frame mod 4 == 2):
            inc hits
          else:
            platform.nui.collapsingHeader("Changes", expanded):
              discard
        platform.nui.endUiFrame(buildMeshRenderCommands = mesh)
        if UseCachedTexture in platform.nui.frame.nodes[rootIndex].flags:
          inc captures
        require renderer.setRenderTarget(frameTarget)
        require renderer.setRenderDrawColor(0, 0, 0, 255)
        require renderer.renderClear()
        platform.renderNuiCommands()
        let pixels = renderer.renderReadPixels(nil)
        require pixels != nil
        var snapshot: seq[uint32]
        var visible = 0
        # Compare the icon, not the header background or text.
        for y in 13 ..< 27:
          for x in 13 ..< 27:
            var r, g, b, a: uint8
            require pixels.readSurfacePixel(x.cint, y.cint, r, g, b, a)
            snapshot.add (r.uint32 shl 16) or (g.uint32 shl 8) or b.uint32
            if r > 128 and g > 128 and b > 128:
              inc visible
        require visible > 0
        if frame == 0:
          reference = snapshot
        else:
          check snapshot == reference
        destroySurface(pixels)
      check hits > 0
      check captures > 0
      platform.nui.clearWidgetCaches()
    require renderer.setRenderTarget(nil)
