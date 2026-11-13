discard """
  action: "run"
  cmd: "nim $target --cc:clang --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/terminal_platform/terminal_platform
import std/unittest
import nuigi/core/vecmath as nuiMath
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

proc measureSettingsText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32, 1)

proc renderSettings(platform: TerminalPlatform, settings: View) =
  discard platform.nui.beginUiFrame(80, 40)
  settings.render(platform.nui)
  platform.nui.endUiFrame(buildMeshRenderCommands = false)

proc hasText(platform: TerminalPlatform, value: string): bool =
  for index in 0..<platform.nui.frame.nodes.len:
    if platform.nui.nodeText(index).text == value.uiString:
      return true

proc checkbox(platform: TerminalPlatform, label: string): UiNodeId =
  for index in 0..<platform.nui.frame.nodes.len:
    if platform.nui.nodeText(index).text == label.uiString:
      let parent = platform.nui.frame.nodes[platform.nui.frame.nodes[index].parent]
      if parent.semanticsIndex > 0:
        let semantics = platform.nui.frame.semantics[int(parent.semanticsIndex) - 1]
        if semantics.role == SemanticCheckBox:
          return parent.id
  noneNodeId()

suite "Terminal platform settings content":
  test "view retains terminal controls and live metrics without renderer-only settings":
    let platform = newTerminalPlatform().TerminalPlatform
    platform.nui = newBuilder(measureSettingsText)
    platform.nui.backendType = UiBackendType.Terminal
    platform.fps = 60
    platform.frameTimeMs = 16.7
    platform.processingTimeMs = 2.5
    platform.settings.escapeTimeoutMs = DefaultEscapeTimeoutMs.float32
    let settings = newPlatformSettingsView(platform, LayoutService())
    platform.renderSettings(settings)
    check platform.hasText("Platform Settings")
    check platform.hasText("FPS: " & formatFloat(60.0, ffDecimal, 0))
    check platform.hasText("Total frame: 16.7 ms")
    check platform.hasText("Processing: 2.5 ms")
    check platform.hasText("Escape timeout (ms)")
    check not platform.hasText("VSync")
    for label in ["Render on demand", "Demo", "Debug panel", "Record mouse events"]:
      let id = platform.checkbox(label)
      require id != noneNodeId()
      platform.nui.enqueueSemanticRequest(
        UiSemanticRequest(target: id, action: SemanticActivate))
      platform.renderSettings(settings)
    check platform.settings.renderOnDemand
    check platform.settings.showDemoWindow
    check platform.settings.showDebugPanel
    check platform.settings.recordMouseEvents
    platform.fps = 42
    platform.renderSettings(settings)
    check platform.hasText("FPS: " & formatFloat(42.0, ffDecimal, 0))
