discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[options, unittest]
import core_settings, platform, view_panel
import nuigi
import nuigi/widgets
import nuigi/core/vecmath as nuiMath

proc measurePanelText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

proc findText(builder: UiBuilder, text: string): int =
  for i in 0 ..< builder.frame.nodes.len:
    if builder.nodeText(i).text == text.uiString:
      return i
  -1

proc renderPanel(builder: var UiBuilder, options = ViewPanelOptions(),
    input = UiInputSnapshot(), showHeader = true, custom = true) =
  discard builder.beginUiFrame(800, 600, input)
  if custom:
    builder.viewPanel("test-panel", false, showHeader, options):
      builder.node:
        discard builder.fit().text("Title")
    do:
      discard builder.button("Custom")
    do:
      builder.node:
        discard builder.fill().text("Body")
  else:
    builder.viewPanel("test-panel", false, showHeader, options):
      builder.node:
        discard builder.fit().text("Title")
    do:
      builder.node:
        discard builder.fill().text("Body")
  builder.endUiFrame(buildMeshRenderCommands = false)

proc checkPanelStyle(options: ViewPanelOptions) =
  var builder = newBuilder(measurePanelText)
  discard builder.beginUiFrame(800, 600)
  var contentIndex = -1
  builder.viewPanel("options-panel", false, true, options):
    discard
  do:
    contentIndex = builder.currentNodeIndex
  builder.endUiFrame(buildMeshRenderCommands = false)

  let rootIndex = int(builder.frame.nodes[contentIndex].parent)
  var headerIndex = -1
  for i in 0 ..< builder.frame.nodes.len:
    if i != contentIndex and builder.frame.nodes[i].parent == rootIndex.int32:
      headerIndex = i
      break
  var headerContentIndex = -1
  for i in 0 ..< builder.frame.nodes.len:
    if builder.frame.nodes[i].parent == headerIndex.int32:
      headerContentIndex = i
      break
  let rootStyle = builder.nodeStyle(rootIndex)
  let headerStyle = builder.nodeStyle(headerIndex)
  let headerContentStyle = builder.nodeStyle(headerContentIndex)
  let contentStyle = builder.nodeStyle(contentIndex)
  check rootStyle.cornerRadius == options.cornerRadius
  check rootStyle.paddingX == options.padding
  check rootStyle.paddingY == options.padding
  check builder.nodeGap(rootIndex) == options.gap
  check headerStyle.cornerRadii.topLeft ==
    options.headerCornerRadius.get(options.cornerRadius - options.padding)
  check headerStyle.cornerRadii.topRight ==
    options.headerCornerRadius.get(options.cornerRadius - options.padding)
  check headerStyle.paddingX == options.headerPadding
  check headerStyle.paddingY == options.headerPadding
  check builder.nodeGap(headerIndex) == options.headerGap
  check builder.nodeGap(headerContentIndex) == options.headerContentGap
  check contentStyle.cornerRadii.bottomRight ==
    options.contentCornerRadius.get(options.cornerRadius)
  check contentStyle.cornerRadii.bottomLeft ==
    options.contentCornerRadius.get(options.cornerRadius)
  check contentStyle.paddingX == options.contentPadding
  check contentStyle.paddingY == options.contentPadding

proc checkConfiguredPanelStyle(config: ConfigStore, withOptions = true) =
  var builder = newBuilder(measurePanelText)
  discard builder.beginUiFrame(800, 600)
  var contentIndex = -1
  if withOptions:
    builder.viewPanel("configured-panel", false, true, config, ViewPanelOptions()):
      discard
    do:
      contentIndex = builder.currentNodeIndex
  else:
    builder.viewPanel("configured-panel", false, true, config):
      discard
    do:
      contentIndex = builder.currentNodeIndex
  builder.endUiFrame(buildMeshRenderCommands = false)

  let rootIndex = int(builder.frame.nodes[contentIndex].parent)
  var headerIndex = -1
  for i in 0 ..< builder.frame.nodes.len:
    if i != contentIndex and builder.frame.nodes[i].parent == rootIndex.int32:
      headerIndex = i
      break
  var headerContentIndex = -1
  for i in 0 ..< builder.frame.nodes.len:
    if builder.frame.nodes[i].parent == headerIndex.int32:
      headerContentIndex = i
      break
  let rootStyle = builder.nodeStyle(rootIndex)
  let headerStyle = builder.nodeStyle(headerIndex)
  let contentStyle = builder.nodeStyle(contentIndex)
  check rootStyle.paddingX == 3
  check rootStyle.paddingY == 3
  check rootStyle.cornerRadius == 12
  check builder.nodeGap(rootIndex) == 2
  check headerStyle.cornerRadii.topLeft == 10
  check headerStyle.paddingX == 7
  check headerStyle.paddingY == 7
  check builder.nodeGap(headerIndex) == 6
  check builder.nodeGap(headerContentIndex) == 9
  check contentStyle.cornerRadii.bottomRight == 5
  check contentStyle.cornerRadii.bottomLeft == 5
  check contentStyle.paddingX == 8
  check contentStyle.paddingY == 8

proc pointerAt(builder: UiBuilder, text: string): UiInputSnapshot =
  let index = builder.findText(text)
  doAssert index >= 0
  result.mouse = builder.absoluteNodePos(index) + nuiMath.vec2(1, 1)

type PanelActions = ref object
  calls: seq[bool]
  splits: seq[string]

proc actionOptions(actions: PanelActions): ViewPanelOptions =
  result.onClose = proc(keepHidden: bool) {.gcsafe, raises: [].} =
    actions.calls.add keepHidden
  result.onSplitVertical = proc() {.gcsafe, raises: [].} =
    actions.splits.add "vertical"
  result.onSplitHorizontal = proc() {.gcsafe, raises: [].} =
    actions.splits.add "horizontal"

suite "View panel header actions":
  test "header content masks overflowing children without masking actions":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      var builder = newBuilder(measurePanelText)
      builder.backendType = backend
      let options = actionOptions(PanelActions())
      var input = UiInputSnapshot(mouse: nuiMath.vec2(900, 700))
      for frame in 0 .. 1:
        discard builder.beginUiFrame(200, 200, input)
        builder.viewPanel("narrow-panel", false, true, options):
          builder.node:
            discard builder.fit().text("A header title that exceeds the available width")
        do:
          discard
        builder.endUiFrame(buildMeshRenderCommands = false)
        let title = builder.findText("A header title that exceeds the available width")
        let content = builder.frame.nodes[title].parent
        check MaskChildren in builder.frame.nodes[content].flags
        check builder.frame.nodes[title].size.x > builder.frame.nodes[content].size.x
        if frame == 0:
          input.mouse = builder.absoluteNodePos(title) + nuiMath.vec2(1, 1)
        else:
          let close = builder.findText("x")
          require close >= 0
          check builder.frame.nodes[close].parent != content

  test "panel geometry options preserve defaults and accept overrides":
    checkPanelStyle(ViewPanelOptions())
    checkPanelStyle(ViewPanelOptions(padding: 3, cornerRadius: 12,
      contentCornerRadius: some(5'f32)))
    checkPanelStyle(ViewPanelOptions(padding: 2, gap: 3, cornerRadius: 12,
      headerCornerRadius: some(10'f32), contentCornerRadius: some(5'f32),
      headerPadding: 2, headerGap: 3, headerContentGap: 5,
      contentPadding: 9))

  test "config overload applies view panel settings":
    let config = ConfigStore.new("test", "")
    config.setUiViewPanelPadding(3)
    config.setUiViewPanelGap(2)
    config.setUiViewPanelCornerRadius(12)
    config.setUiViewPanelHeaderCornerRadius(10)
    config.setUiViewPanelContentCornerRadius(5)
    config.setUiViewPanelHeaderPadding(7)
    config.setUiViewPanelHeaderGap(6)
    config.setUiViewPanelHeaderContentGap(9)
    config.setUiViewPanelContentPadding(8)
    checkConfiguredPanelStyle(config)
    checkConfiguredPanelStyle(config, withOptions = false)

  test "hover actions preserve header height and body position":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      for custom in [false, true]:
        var builder = newBuilder(measurePanelText)
        builder.backendType = backend
        let options = actionOptions(PanelActions())
        builder.renderPanel(options, custom = custom)
        let title = builder.findText("Title")
        let header = builder.frame.nodes[title].parent
        let headerRoot = builder.frame.nodes[header].parent
        let headerHeight = builder.frame.nodes[headerRoot].size.y
        let headerTop = builder.absoluteNodePos(headerRoot).y
        let bodyTop = builder.absoluteNodePos(builder.findText("Body")).y
        for label in ["Title", "x", "Body", "Title", "-"]:
          let input = builder.pointerAt(label)
          builder.renderPanel(options, input, custom = custom)
          let currentTitle = builder.findText("Title")
          let currentHeader = builder.frame.nodes[
            builder.frame.nodes[currentTitle].parent].parent
          check builder.frame.nodes[currentHeader].size.y == headerHeight
          check builder.absoluteNodePos(builder.findText("Body")).y == bodyTop
          for button in ["Custom", "|", "=", "-", "x"]:
            let index = builder.findText(button)
            if index >= 0:
              let top = builder.absoluteNodePos(index).y
              check top >= headerTop
              check top + builder.frame.nodes[index].size.y <= headerTop + headerHeight

  test "actions only appear while hovering the header including its children":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      var builder = newBuilder(measurePanelText)
      builder.backendType = backend
      let options = ViewPanelOptions(onClose: proc(keepHidden: bool) {.gcsafe, raises: [].} = discard)
      builder.renderPanel(options)
      check builder.findText("Custom") == -1
      check builder.findText("-") == -1
      check builder.findText("x") == -1
      builder.renderPanel(options, builder.pointerAt("Title"))
      check builder.findText("Custom") >= 0
      check builder.findText("-") >= 0
      check builder.findText("x") >= 0
      let customPos = builder.absoluteNodePos(builder.findText("Custom"))
      let hidePos = builder.absoluteNodePos(builder.findText("-"))
      let closePos = builder.absoluteNodePos(builder.findText("x"))
      check customPos.x < hidePos.x
      check hidePos.x < closePos.x
      check closePos.x > 700
      builder.renderPanel(options, builder.pointerAt("x"))
      check builder.findText("x") >= 0
      builder.renderPanel(options, builder.pointerAt("Body"))
      check builder.findText("Custom") == -1
      check builder.findText("-") == -1
      check builder.findText("x") == -1

  test "split buttons are optional and defer their respective actions":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      for label in ["|", "="]:
        let actions = PanelActions()
        var options = actionOptions(actions)
        if label == "|":
          options.onSplitHorizontal = nil
        else:
          options.onSplitVertical = nil
        var builder = newBuilder(measurePanelText)
        builder.backendType = backend
        builder.renderPanel(options, custom = false)
        check builder.findText(label) == -1
        builder.renderPanel(options, builder.pointerAt("Title"), custom = false)
        check builder.findText(label) >= 0
        check builder.findText(if label == "|": "=" else: "|") == -1
        var input = builder.pointerAt(label)
        input.mousePressed = {MouseLeft}
        input.mouseDown = {MouseLeft}
        builder.renderPanel(options, input, custom = false)
        input.mousePressed = {}
        input.mouseDown = {}
        input.mouseReleased = {MouseLeft}
        builder.renderPanel(options, input, custom = false)
        check actions.splits.len == 0
        builder.flushNextFrameActions()
        check actions.splits == @[if label == "|": "vertical" else: "horizontal"]

  test "hide and close defer their distinct actions":
    let actions = PanelActions()
    let options = actionOptions(actions)
    for label in ["-", "x"]:
      var builder = newBuilder(measurePanelText)
      builder.renderPanel(options, custom = false)
      builder.renderPanel(options, builder.pointerAt("Title"), custom = false)
      var input = builder.pointerAt(label)
      input.mousePressed = {MouseLeft}
      input.mouseDown = {MouseLeft}
      builder.renderPanel(options, input, custom = false)
      input.mousePressed = {}
      input.mouseDown = {}
      input.mouseReleased = {MouseLeft}
      let before = actions.calls.len
      builder.renderPanel(options, input, custom = false)
      check actions.calls.len == before
      builder.flushNextFrameActions()
      check actions.calls.len == before + 1
      check actions.calls[^1] == (label == "-")

  test "hidden headers omit header and all button code":
    var builder = newBuilder(measurePanelText)
    builder.renderPanel(showHeader = false)
    check builder.findText("Title") == -1
    check builder.findText("Custom") == -1
    check builder.findText("Body") >= 0

  test "overloads without options support both custom and default button code":
    var builder = newBuilder(measurePanelText)
    discard builder.beginUiFrame(800, 600)
    builder.viewPanel("plain", false, true):
      builder.node:
        discard builder.fit().text("Plain")
    do:
      discard
    builder.viewPanel("custom", true, true):
      builder.node:
        discard builder.fit().text("Custom header")
    do:
      discard builder.button("Extra")
    do:
      discard
    builder.endUiFrame(buildMeshRenderCommands = false)
    check builder.findText("Plain") >= 0
    check builder.findText("Custom header") >= 0
