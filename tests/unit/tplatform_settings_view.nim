discard """
  action: "run"
  cmd: "nim $target --cc:clang --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/layout/layout
import std/unittest
import nuigi
import nuigi/widgets
import nuigi/core/vecmath as nuiMath
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

proc measureSettingsText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

type SettingsFixture = object
  platform: Platform
  layout: LayoutServiceImpl
  settings: PlatformSettingsView
  builds: ref int

proc newSettingsFixture(backend: UiBackendType): SettingsFixture =
  result.builds = new(int)
  let builds = result.builds
  result.platform = Platform(nui: newBuilder(measureSettingsText))
  result.platform.nui.backendType = backend
  result.platform.buildSettingsImpl = proc(self: Platform, builder: var UiBuilder) =
    inc builds[]
    builder.node:
      discard builder.fillX().fitY().text("Live metric " & $builds[])
  result.layout = LayoutServiceImpl(platform: result.platform,
    layout: HorizontalLayout(saveLayoutImpl: autoLayoutSaveLayout,
      activeLeafViewImpl: layoutActiveLeafView, kindImpl: proc(view: View): string = "horizontal"),
    editors: DocumentEditorService())
  result.settings = newPlatformSettingsView(result.platform, result.layout)
  let settings = result.settings
  result.layout.addViewFactory "platform-settings", proc(config: JsonNode): View = settings
  result.layout.registerView(settings)

proc render(f: var SettingsFixture, input = UiInputSnapshot()) =
  discard f.platform.nui.beginUiFrame(800, 600, input)
  f.settings.render(f.platform.nui)
  f.platform.nui.endUiFrame(buildMeshRenderCommands = false)

proc findText(builder: UiBuilder, value: string): int =
  for index in 0..<builder.frame.nodes.len:
    if builder.nodeText(index).text == value.uiString:
      return index
  -1

proc restoreLayout(layout: LayoutServiceImpl, state: JsonNode): View {.raises: [ValueError].} =
  createLayout(state, createView = proc(config: JsonNode): View =
    layout.getOrCreateView(config))

proc capturePicker(layout: LayoutServiceImpl): ref SelectorPopupBuilder =
  let captured = new(SelectorPopupBuilder)
  layout.pushSelectorPopupImpl = proc(self: LayoutService, builder: SelectorPopupBuilder): ISelectorPopup =
    captured[] = builder
  layout.chooseOpen()
  captured

proc pickerItems(builder: SelectorPopupBuilder): seq[FinderItem] =
  let items = new(seq[FinderItem])
  let source = builder.finder.get.source
  let subscription = source.onItemsChanged.subscribe proc(list: ItemList) =
    for item in list.items:
      items[].add item
  source.setQuery("")
  source.onItemsChanged.unsubscribe(subscription)
  items[]

proc selectedItem(item: FinderItem): ISelectorPopup =
  ISelectorPopup(getSelectedItem: proc(): Option[FinderItem] = item.some)

suite "Platform settings view":
  test "registered view opens, hides, reopens and closes using normal layout actions":
    var f = newSettingsFixture(UiBackendType.Graphical)
    check not f.layout.isViewVisible(f.settings)
    f.layout.openPlatformSettings()
    check f.layout.isViewVisible(f.settings)
    check f.layout.allViews.len == 1
    f.layout.openPlatformSettings()
    check f.layout.allViews.len == 1
    f.layout.closeView(f.settings, keepHidden = true, restoreHidden = false)
    check not f.layout.isViewVisible(f.settings)
    f.layout.openPlatformSettings()
    check f.layout.isViewVisible(f.settings)
    f.layout.closeView(f.settings, restoreHidden = false)
    check not f.layout.isViewVisible(f.settings)
    f.layout.openPlatformSettings()
    check f.layout.isViewVisible(f.settings)
    check f.layout.allViews.len == 1

  test "view identity and layout/session data restore the singleton":
    var f = newSettingsFixture(UiBackendType.Graphical)
    check f.settings.kind == "platform-settings"
    check f.settings.display == "Platform Settings"
    check f.settings.copy() == f.settings
    let saved = f.settings.saveLayout(initHashSet[Id]())
    check saved["kind"].getStr == "platform-settings"
    check f.settings.saveState() == saved
    check f.layout.getOrCreateView(saved) == f.settings
    f.layout.addView(f.settings)
    let layoutState = f.layout.layout.saveLayout(initHashSet[Id]())
    let restored = restoreLayout(f.layout, layoutState)
    require restored != nil
    check restored.activeLeafView() == f.settings

  test "open action uses the small-left slot when the layout provides one":
    var f = newSettingsFixture(UiBackendType.Graphical)
    let other = View()
    f.layout.addView(other)
    f.layout.layout.slots["small-left"] = "+"
    f.layout.openPlatformSettings()
    check f.layout.isViewVisible(f.settings)
    check f.layout.isViewVisible(other)
    check f.layout.layout.children.len == 2

  test "open-view picker lists settings, opens it and closes it without editor previews":
    var f = newSettingsFixture(UiBackendType.Graphical)
    let picker = capturePicker(f.layout)
    let items = picker[].pickerItems()
    require items.len == 1
    let item = items[0]
    check item.filterText == "Platform Settings"
    check item.data == "view:" & $f.settings.id2
    picker.previewer.get.previewItem(item, nil)
    check picker.handleItemConfirmed(ISelectorPopup(), item)
    check f.layout.isViewVisible(f.settings)
    check picker.customActions["close-selected"](selectedItem(item), newJNull())
    check not f.layout.isViewVisible(f.settings)
    picker.finder.get.deinit()

  test "both backends use view panels, update live content and show hide/close actions":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      var f = newSettingsFixture(backend)
      f.settings.active = true
      f.settings.markDirty()
      f.render()
      check not f.settings.dirty
      require f.platform.nui.findText("Platform Settings") >= 0
      check f.platform.nui.findText("Live metric 1") >= 0
      let title = f.platform.nui.findText("Platform Settings")
      let mouse = f.platform.nui.absoluteNodePos(title) + nuiMath.vec2(1, 1)
      f.render(UiInputSnapshot(mouse: mouse))
      f.render(UiInputSnapshot(mouse: mouse))
      check f.builds[] == 3
      check f.platform.nui.findText("Live metric 3") >= 0
      check f.platform.nui.findText("-") >= 0
      check f.platform.nui.findText("x") >= 0
