discard """
  action: "run"
  cmd: "nim $target -d:nuiDebug --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

include ../../modules/terminal/render
import std/[unittest, deques]
import terminal/vterm, terminal/terminal as terminalModule
import misc/[custom_async, channel]
import config_store
from scripting_api import SshOptions
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

proc measureTerminalListText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 10, 20)

proc terminalListFrame(view: TerminalView, b: var UiBuilder,
    input = UiInputSnapshot()): TerminalInputNuiStorage =
  discard b.beginUiFrame(200, 180, input)
  var width, height, cellWidth, cellHeight: int
  view.renderTerminalNui(b, width, height, cellWidth, cellHeight)
  b.endUiFrame(buildMeshRenderCommands = false)
  for i in 0..<b.frame.nodes.len:
    let storage = b.nodeStorageGet(b.frame.nodes[i].addr)
    if storage != nil and storage of TerminalInputNuiStorage:
      return cast[TerminalInputNuiStorage](storage)

proc newTerminalListView(): TerminalView =
  TerminalView(terminal: Terminal(width: 10, height: 4, historyLength: 1000,
      cursor: (0, 0, false, CursorShape.Block, false)),
    terminals: TerminalServiceImpl(themes: ThemeService(theme: Theme())))

proc hasTerminalText(b: UiBuilder, text: string): bool =
  for t in b.frame.texts:
    if t.text == text.uiString:
      return true

proc cacheRows(terminal: Terminal, first, count: int, text: string) =
  terminal.bufferFirstRow = first
  terminal.terminalBuffer.initTerminalBuffer(terminal.width, count)
  for row in 0..<count:
    var cell = TerminalChar(fg: fgNone, bg: bgNone)
    cell.appendChsFromRune(text[0].Rune, false)
    terminal.terminalBuffer[0, row] = cell

proc captureWheel(view: TerminalView): ref seq[int] =
  result = new(seq[int])
  let events = result
  view.onScroll = proc(view: TerminalView, delta: int,
      modifiers: input_api.Modifiers) {.gcsafe, raises: [].} =
    events[].add delta

proc captureClicks(view: TerminalView): ref seq[(int, int)] =
  result = new(seq[(int, int)])
  let events = result
  view.onClick = proc(view: TerminalView, button: input_api.MouseButton,
      pressed: bool, modifiers: input_api.Modifiers, col, row: int) {.gcsafe, raises: [].} =
    if pressed:
      events[].add (col, row)

suite "Terminal active view styles":
  test "active surfaces and headers select theme slots without tinting":
    let view = newTerminalListView()
    var builder = newBuilder(measureTerminalListText)
    let activePanelColor = rgba(0.6, 0.4, 0.2, 0.8)
    let activeHeaderColor = rgba(0.2, 0.4, 0.6, 0.7)
    builder.themeStyle(UiStyleIndexPanelActive)[].fillColor = activePanelColor
    builder.themeStyle(UiStyleIndexHeaderActive)[].fillColor = activeHeaderColor
    for active in [false, true, false]:
      view.active = active
      discard view.terminalListFrame(builder)
      var surfaces, headers: int
      for i, node in builder.frame.nodes:
        if node.debugName in ["terminal-root", "terminal-body"]:
          let index = if active: UiStyleIndexPanelActive else: UiStyleIndexPanel
          check builder.nodeStyle(i)[].fillColor == builder.themeStyle(index)[].fillColor
          check builder.nodeStyle(i)[].borderColor == builder.themeStyle(index)[].borderColor
          inc surfaces
        elif node.debugName == "terminal-root-header":
          let index = if active: UiStyleIndexHeaderActive else: UiStyleIndexHeader
          check builder.nodeStyle(i)[].fillColor == builder.themeStyle(index)[].fillColor
          check builder.nodeStyle(i)[].borderColor == builder.themeStyle(index)[].borderColor
          inc headers
      check surfaces == 2
      check headers == 1

suite "Terminal worker row window":
  test "conversion combines worker history and live screen at absolute row indexes":
    let vt = VTerm.new(2, 2)
    require vt != nil
    defer: vt.free()
    vt.setUtf8(1)
    vt.screen.reset(1)
    var state = TerminalThreadState(width: 2, height: 2, vtermInternal: vt,
      screenInternal: vt.screen, viewportFirst: 1, viewportLast: 1,
      viewportFollowTail: false)
    state.scrollbackBuffer = initDeque[seq[VTermScreenCell]]()
    for letter in ['A', 'B', 'C', 'D', 'E']:
      var cell: VTermScreenCell
      cell.chars[0] = letter.uint32
      state.scrollbackBuffer.addLast(@[cell])
    let text = "X\r\nY"
    discard vt.writeInput(text.cstring, text.len.csize_t)
    var buffer = terminalModule.createTerminalBuffer(state)
    check state.terminalRowWindow() == (0, 4)
    check buffer.width == 2
    check buffer.height == 4
    for row in 0..<4:
      var rendered = ""
      buffer[0, row].writeCharsTo(rendered)
      check rendered == $char(ord('A') + row)
      check buffer[1, row].isEmpty
    state.viewportFollowTail = true
    state.viewportRows = 2
    buffer = terminalModule.createTerminalBuffer(state)
    check state.terminalRowWindow() == (3, 7)
    for row, letter in ['D', 'E', 'X', 'Y']:
      var rendered = ""
      buffer[0, row].writeCharsTo(rendered)
      check rendered == $letter

  test "history plus screen form one absolute row space with bounded prefetch":
    var state = TerminalThreadState(width: 10, height: 4,
      viewportFirst: 500, viewportLast: 505, viewportFollowTail: false)
    state.scrollbackBuffer = initDeque[seq[VTermScreenCell]]()
    for i in 0..<1000:
      state.scrollbackBuffer.addLast(@[])
    check state.terminalRowWindow() == (494, 512)
    state.viewportFirst = 0
    state.viewportLast = 3
    check state.terminalRowWindow() == (0, 8)
    state.viewportFollowTail = true
    state.viewportRows = 4
    check state.terminalRowWindow() == (996, 1004)

  test "alternate screen excludes history and stale requests are clamped":
    var state = TerminalThreadState(width: 10, height: 4,
      viewportFirst: 500, viewportLast: 503, viewportFollowTail: false,
      alternateScreen: true)
    state.scrollbackBuffer = initDeque[seq[VTermScreenCell]]()
    for i in 0..<1000:
      state.scrollbackBuffer.addLast(@[])
    check state.scrollbackBufferLen == 0
    check state.terminalRowWindow() == (0, 4)

  test "evicted history remaps old viewport requests":
    var state = TerminalThreadState(width: 10, height: 4,
      viewportFirst: 20, viewportLast: 23, viewportFollowTail: false,
      historyStart: 10, viewportHistoryStart: 7)
    state.scrollbackBuffer = initDeque[seq[VTermScreenCell]]()
    for i in 0..<100:
      state.scrollbackBuffer.addLast(@[])
    check state.terminalRowWindow() == (13, 25)

suite "Terminal dynamic virtual list":
  test "uncached rows retain cell height without drawing text":
    let view = newTerminalListView()
    var b = newBuilder(measureTerminalListText)
    let storage = view.terminalListFrame(b)
    check storage != nil
    check storage.list.estimatedTotalHeight(1004, 20) == 20080
    check storage.list.heights.len < 20
    for sample in storage.list.heights:
      check sample.height == 20
    check not b.hasTerminalText("A")

suite "Terminal asynchronous worker":
  when defined(windows):
    test "exited native processes keep serving viewport requests":
      let service = TerminalServiceImpl(config: ConfigService(
        runtime: ConfigStore.new("terminal-test", "")))
      let terminal = service.createTerminal(12, 4,
        "cmd.exe /d /c exit 0",
        ssh = SshOptions.none)
      defer: waitFor terminal.terminate().wait(3.seconds)
      terminal.sendEvent(InputEvent(kind: InputEventKind.Viewport,
        firstRow: 0, lastRow: 3, viewportRows: 4, followTail: true))
      for i in 0..<1000:
        if terminal.exitCode.isSome:
          break
        waitFor sleepAsync(5.milliseconds)
      require terminal.exitCode.isSome
      check not terminal.threadTerminated
      terminal.sendEvent(InputEvent(kind: InputEventKind.Size,
        row: 5, col: 13, cellPixelWidth: 10, cellPixelHeight: 20))
      terminal.sendEvent(InputEvent(kind: InputEventKind.Viewport,
        firstRow: 0, lastRow: 3, viewportRows: 4,
        historyStart: terminal.historyStart, followTail: false))
      for i in 0..<200:
        if terminal.bufferFirstRow == 0 and terminal.terminalBuffer.height == 5:
          break
        waitFor sleepAsync(5.milliseconds)
      check terminal.bufferFirstRow == 0
      check terminal.terminalBuffer.height == 5
      check terminal.terminalBuffer.width == 13

  test "viewport requests fetch uncached history without new process output":
    let service = TerminalServiceImpl()
    let stdin = newInMemoryChannel()
    let stdout = newInMemoryChannel()
    let terminal = service.createTerminal(8, 4, stdin, stdout)
    defer:
      waitFor terminal.terminate().wait(2.seconds)
    var text = ""
    for i in 0..<100:
      text.add "L" & $i & "\r\n"
    stdout.write(text)
    for i in 0..<200:
      if terminal.historyLength > 80:
        break
      waitFor sleepAsync(5.milliseconds)
    require terminal.historyLength > 80
    terminal.sendEvent(InputEvent(kind: InputEventKind.Viewport,
      firstRow: 0, lastRow: 3, scrollOffset: 0, viewportRows: 4,
      historyStart: terminal.historyStart, followTail: false))
    for i in 0..<200:
      if terminal.bufferFirstRow == 0 and terminal.terminalBuffer.height == 8:
        break
      waitFor sleepAsync(5.milliseconds)
    check terminal.bufferFirstRow == 0
    check terminal.terminalBuffer.height == 8
    var rendered = ""
    for col in 0..<2:
      terminal.terminalBuffer[col, 0].writeCharsTo(rendered)
    check rendered == "L0"

suite "Terminal cached row rendering":
  test "list wheel scrolling stays local and application mouse tracking gets wheel events":
    let view = newTerminalListView()
    let wheelEvents = view.captureWheel()
    var b = newBuilder(measureTerminalListText)
    let storage = view.terminalListFrame(b)
    let mouse = nuiMath.vec2(10, 80)
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse))
    let oldOffset = storage.list.scrollOffsetY
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse,
      wheel: nuiMath.vec2(0, 1)))
    for i in 0..<20:
      discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse))
    check storage.list.scrollOffsetY < oldOffset
    check wheelEvents[].len == 0
    view.terminal.mouseTracking = true
    let trackedOffset = storage.list.scrollOffsetY
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse,
      wheel: nuiMath.vec2(0, 2)))
    check wheelEvents[] == @[2]
    check storage.list.scrollOffsetY == trackedOffset

  test "terminal cells receive clicks through list children but scrollbars do not":
    let view = newTerminalListView()
    let clicks = view.captureClicks()
    var b = newBuilder(measureTerminalListText)
    let storage = view.terminalListFrame(b)
    let mouse = nuiMath.vec2(15, 80)
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse))
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse,
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    check clicks[].len == 1
    check clicks[][0][0] == 1
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: mouse,
      mouseReleased: {MouseLeft}))
    let scrollbarPos = b.absoluteNodePos(storage.list.scrollbarTrackIndex) + nuiMath.vec2(5, 10)
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: scrollbarPos))
    discard view.terminalListFrame(b, UiInputSnapshot(mouse: scrollbarPos,
      mousePressed: {MouseLeft}, mouseDown: {MouseLeft}))
    check clicks[].len == 1

  test "cached rows render on arrival and scrolling into a cache miss stays blank":
    let view = newTerminalListView()
    var b = newBuilder(measureTerminalListText)
    discard view.terminalListFrame(b)
    view.terminal.cacheRows(1000, 4, "A")
    let storage = view.terminalListFrame(b)
    check b.hasTerminalText("A")
    storage.followTail = false
    storage.list.scrollByY(-10000)
    discard view.terminalListFrame(b)
    check not b.hasTerminalText("A")
    let visible = storage.list.visibleItemRange()
    view.terminal.cacheRows(visible.first, visible.last - visible.first + 1, "B")
    discard view.terminalListFrame(b)
    check b.hasTerminalText("B")

  test "tail follows output but a history viewport is preserved through eviction":
    let view = newTerminalListView()
    var b = newBuilder(measureTerminalListText)
    let storage = view.terminalListFrame(b)
    let oldOffset = storage.list.scrollOffsetY
    view.terminal.historyLength += 5
    discard view.terminalListFrame(b)
    check storage.list.scrollOffsetY == oldOffset + 100
    storage.followTail = false
    storage.list.scrollByY(-10000)
    discard view.terminalListFrame(b)
    let anchoredOffset = storage.list.scrollOffsetY
    view.terminal.historyStart += 3
    discard view.terminalListFrame(b)
    check storage.list.scrollOffsetY == anchoredOffset - 60

  test "viewport messages are asynchronous and identical idle requests are suppressed":
    let view = newTerminalListView()
    view.terminal.inputChannel = cast[ptr system.Channel[InputEvent]](
      allocShared0(sizeof(system.Channel[InputEvent])))
    view.terminal.inputChannel[].open()
    view.terminal.handles.inputEventSignal = ThreadSignalPtr.new().value
    defer:
      view.terminal.inputChannel[].close()
      deallocShared(view.terminal.inputChannel)
      discard view.terminal.handles.inputEventSignal.close()
    var b = newBuilder(measureTerminalListText)
    let storage = view.terminalListFrame(b)
    check view.terminal.inputChannel[].peek() == 1
    let event = view.terminal.inputChannel[].recv()
    check event.kind == InputEventKind.Viewport
    check (event.firstRow, event.lastRow) == storage.list.visibleItemRange()
    check event.scrollOffset == storage.list.scrollOffsetY / 20
    check event.viewportRows == storage.list.viewportHeight / 20
    check event.followTail
    discard view.terminalListFrame(b)
    check view.terminal.inputChannel[].peek() == 0
    storage.followTail = false
    storage.list.scrollByY(-10000)
    discard view.terminalListFrame(b)
    check view.terminal.inputChannel[].peek() == 1
    let scrolled = view.terminal.inputChannel[].recv()
    check not scrolled.followTail
    check scrolled.firstRow < event.firstRow
    check not b.hasTerminalText("A")
