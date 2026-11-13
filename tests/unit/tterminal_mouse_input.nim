discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
  matrix: ""
"""

include ../../modules/terminal/render
import std/unittest

type
  TerminalMouseEvent = object
    kind: string
    button: input_api.MouseButton
    col, row, deltaY: int
    modifiers: input_api.Modifiers
  TerminalInputFixture = object
    builder: UiBuilder
    storage: TerminalInputNuiStorage
    events: ref seq[TerminalMouseEvent]

proc measureTerminalTestText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 10, 20)

proc inputFrame(fixture: var TerminalInputFixture, input = UiInputSnapshot()) =
  var b = fixture.builder.addr
  discard b[].beginUiFrame(200, 200, input)
  b[].node("terminal-test-body"):
    discard b[].position(20, 40).size(100, 80).padding(0).scrollable()
    b[].nodeStorage(b[].currentNode, fixture.storage)
    discard b[].deferBuild(handleTerminalInputNui)
  b[].endUiFrame(buildMeshRenderCommands = false)

proc newTerminalInputFixture(): TerminalInputFixture =
  result.builder = newBuilder(measureTerminalTestText)
  result.events = new(seq[TerminalMouseEvent])
  let events = result.events
  let view = TerminalView(terminal: Terminal())
  view.onClick = proc(view: TerminalView, button: input_api.MouseButton,
      pressed: bool, modifiers: input_api.Modifiers, col, row: int) {.gcsafe, raises: [].} =
    events[].add TerminalMouseEvent(kind: if pressed: "press" else: "release",
      button: button, col: col, row: row, modifiers: modifiers)
  view.onDrag = proc(view: TerminalView, button: input_api.MouseButton,
      col, row: int, modifiers: input_api.Modifiers) {.gcsafe, raises: [].} =
    events[].add TerminalMouseEvent(kind: "drag", button: button,
      col: col, row: row, modifiers: modifiers)
  view.onMove = proc(view: TerminalView, col, row: int) {.gcsafe, raises: [].} =
    events[].add TerminalMouseEvent(kind: "move", col: col, row: row)
  view.onScroll = proc(view: TerminalView, deltaY: int,
      modifiers: input_api.Modifiers) {.gcsafe, raises: [].} =
    events[].add TerminalMouseEvent(kind: "scroll", deltaY: deltaY, modifiers: modifiers)
  result.storage = TerminalInputNuiStorage(view: view, cellWidth: 10, cellHeight: 20)
  result.inputFrame()

suite "Terminal NUI mouse input":
  test "all buttons forward presses and releases with local cells and modifiers":
    for button in UiMouseButton:
      var fixture = newTerminalInputFixture()
      fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
        mousePressed: {button}, mouseDown: {button},
        modsDown: {ModShift, ModControl, ModAlt, ModSuper}))
      fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
        mouseReleased: {button}))
      check fixture.events[] == @[
        TerminalMouseEvent(kind: "press", button: terminalMouseButton(button),
          col: 2, row: 1, modifiers: {input_api.Shift, input_api.Control,
            input_api.Alt, input_api.Super}),
        TerminalMouseEvent(kind: "release", button: terminalMouseButton(button),
          col: 2, row: 1)]
      check fixture.storage.pressedButtons == {}

  test "all buttons capture drag and release outside the terminal":
    for button in UiMouseButton:
      var fixture = newTerminalInputFixture()
      fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
        mousePressed: {button}, mouseDown: {button}))
      fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(155, 135),
        mouseDelta: nuiMath.vec2(110, 60), mouseDown: {button}, modsDown: {ModAlt}))
      fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(165, 155),
        mouseDelta: nuiMath.vec2(10, 20), mouseReleased: {button}))
      check fixture.events[] == @[
        TerminalMouseEvent(kind: "press", button: terminalMouseButton(button), col: 2, row: 1),
        TerminalMouseEvent(kind: "drag", button: terminalMouseButton(button),
          col: 13, row: 4, modifiers: {input_api.Alt}),
        TerminalMouseEvent(kind: "drag", button: terminalMouseButton(button), col: 14, row: 5),
        TerminalMouseEvent(kind: "release", button: terminalMouseButton(button), col: 14, row: 5)]
      check fixture.storage.pressedButtons == {}
      fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(175, 155),
        mouseDelta: nuiMath.vec2(10, 0)))
      check fixture.events[].len == 4

  test "press outside does not start a drag when entering the terminal":
    var fixture = newTerminalInputFixture()
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(150, 150),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mouseDelta: nuiMath.vec2(-105, -75), mouseDown: {MouseLeft}))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mouseReleased: {MouseLeft}))
    check fixture.events[].len == 0

  test "same-frame press and release are both delivered without a drag":
    var fixture = newTerminalInputFixture()
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mouseDelta: nuiMath.vec2(45, 75),
      mousePressed: {MouseLeft}, mouseReleased: {MouseLeft}))
    check fixture.events[] == @[
      TerminalMouseEvent(kind: "press", button: input_api.MouseButton.Left, col: 2, row: 1),
      TerminalMouseEvent(kind: "release", button: input_api.MouseButton.Left, col: 2, row: 1)]
    check fixture.storage.pressedButtons == {}

  test "stationary held button does not repeat press or drag":
    var fixture = newTerminalInputFixture()
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mouseDown: {MouseLeft}))
    check fixture.events[].len == 1

  test "hit-testing uses fractional render metrics without rounding to pixels":
    var fixture = newTerminalInputFixture()
    fixture.storage.cellWidth = 7.5
    fixture.storage.cellHeight = 17.5
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(42, 74),
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    check fixture.events[] == @[
      TerminalMouseEvent(kind: "press", button: input_api.MouseButton.Left, col: 2, row: 1)]

  test "each pressed button retains independent capture":
    var fixture = newTerminalInputFixture()
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mousePressed: {MouseLeft, MouseRight}, mouseDown: {MouseLeft, MouseRight}))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mouseReleased: {MouseLeft}, mouseDown: {MouseRight}))
    check fixture.storage.pressedButtons == {MouseRight}
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(55, 95),
      mouseDelta: nuiMath.vec2(10, 20), mouseDown: {MouseRight}))
    check fixture.events[] == @[
      TerminalMouseEvent(kind: "press", button: input_api.MouseButton.Left, col: 2, row: 1),
      TerminalMouseEvent(kind: "press", button: input_api.MouseButton.Right, col: 2, row: 1),
      TerminalMouseEvent(kind: "release", button: input_api.MouseButton.Left, col: 2, row: 1),
      TerminalMouseEvent(kind: "drag", button: input_api.MouseButton.Right, col: 3, row: 2)]

  test "hover movement forwards only within the terminal":
    var fixture = newTerminalInputFixture()
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      mouseDelta: nuiMath.vec2(45, 75)))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(150, 150),
      mouseDelta: nuiMath.vec2(105, 75)))
    check fixture.events[] == @[TerminalMouseEvent(kind: "move", col: 2, row: 1)]

  test "wheel scrolling retains targeting direction and modifiers":
    var fixture = newTerminalInputFixture()
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      wheel: nuiMath.vec2(0, 3), modsDown: {ModControl}))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(45, 75),
      wheel: nuiMath.vec2(0, -2), modsDown: {ModShift}))
    fixture.inputFrame(UiInputSnapshot(mouse: nuiMath.vec2(150, 150),
      wheel: nuiMath.vec2(0, 4)))
    check fixture.events[] == @[
      TerminalMouseEvent(kind: "scroll", deltaY: 3, modifiers: {input_api.Control}),
      TerminalMouseEvent(kind: "scroll", deltaY: -2, modifiers: {input_api.Shift})]
