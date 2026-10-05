#use input_handler theme lisp
import platform, compilation_config

const currentSourcePath2 = currentSourcePath()
include module_base

proc newTerminalPlatform*(): Platform {.rtl, raises: [].}

when implModule and enableTerminal:
  import std/[parseutils, strutils, syncio, typedthreads, unicode]
  import vmath
  import misc/[custom_logger, timer]
  from misc/render_command import FontInfo, UINodeFlags
  import app_options, misc/input_api
  import nuigi
  import nuigi/backend/terminal/terminal
  import nuigi/debug/debug_panel
  import nuigi/demo/demo_window
  import nuigi/widgets
  import nuigi/widgets/windows

  logCategory "terminal-platform"

  const TerminalEventHistoryLimit = 256

  {.push gcsafe.}
  {.push raises: [].}

  type
    TerminalInputThreadState = object

    TerminalSettings = object
      renderOnDemand: bool
      escapeTimeoutMs: float32
      recordMouseEvents: bool
      showDemoWindow: bool
      showDebugPanel: bool

    TerminalPlatform* = ref object of Platform
      terminal: TerminalBackend
      input: UiInputSnapshot
      fontInfo: FontInfo
      noUI: bool
      readInputOnThread: bool
      settings: TerminalSettings
      fps: float
      frameTimeMs: float
      processingTimeMs: float
      eventHistory: seq[string]
      eventHistoryExpanded: bool
      eventHistoryScroll: float
      debugPanel: DebugPanel

  var inputThread: Thread[ptr TerminalInputThreadState]
  var inputThreadState: TerminalInputThreadState
  var inputChannel: Channel[char]
  var inputThreadStarted = false

  proc terminalInputThread(state: ptr TerminalInputThreadState) {.thread, raises: [].} =
    discard state
    while true:
      try:
        inputChannel.send(stdin.readChar())
      except:
        break

  proc startTerminalInputThread(): bool =
    if inputThreadStarted:
      return true
    inputChannel.open()
    try:
      inputThread.createThread(terminalInputThread, inputThreadState.addr)
      inputThreadStarted = true
      return true
    except CatchableError as error:
      inputChannel.close()
      log lvlError, "Failed to start terminal input thread: ", error.msg
      return false

  proc toPlatformModifiers(modifiers: UiModifiers): Modifiers =
    result = {}
    if ModControl in modifiers: result.incl Control
    if ModShift in modifiers: result.incl Shift
    if ModAlt in modifiers: result.incl Alt
    if ModSuper in modifiers: result.incl Super

  proc toPlatformMouseButton(button: UiMouseButton): MouseButton =
    case button
    of MouseLeft: MouseButton.Left
    of MouseMiddle: MouseButton.Middle
    of MouseRight: MouseButton.Right

  proc toPlatformInput(key: UiKey): int64 =
    case key
    of KeyA..KeyZ: int64(ord('a') + ord(key) - ord(KeyA))
    of Key0..Key9: int64(ord('0') + ord(key) - ord(Key0))
    of KeySpace: INPUT_SPACE
    of KeyEnter, KeyKpEnter: INPUT_ENTER
    of KeyEscape: INPUT_ESCAPE
    of KeyBackspace: INPUT_BACKSPACE
    of KeyTab: INPUT_TAB
    of KeyLeft: INPUT_LEFT
    of KeyRight: INPUT_RIGHT
    of KeyUp: INPUT_UP
    of KeyDown: INPUT_DOWN
    of KeyF1..KeyF12: int64(INPUT_F1 - (ord(key) - ord(KeyF1)))
    of KeyDelete: INPUT_DELETE
    of KeyHome: INPUT_HOME
    of KeyEnd: INPUT_END
    of KeyPageUp: INPUT_PAGE_UP
    of KeyPageDown: INPUT_PAGE_DOWN
    of KeyKp0..KeyKp9: int64(ord('0') + ord(key) - ord(KeyKp0))
    of KeyKpDivide: ord('/').int64
    of KeyKpMultiply: ord('*').int64
    of KeyKpSubtract, KeyMinus: ord('-').int64
    of KeyKpAdd: ord('+').int64
    of KeyKpDecimal, KeyPeriod: ord('.').int64
    of KeySemicolon: ord(';').int64
    of KeyApostrophe: ord('\'').int64
    of KeyComma: ord(',').int64
    of KeySlash: ord('/').int64
    of KeyBackslash: ord('\\').int64
    of KeyLeftBracket: ord('[').int64
    of KeyRightBracket: ord(']').int64
    of KeyGrave: ord('`').int64
    else: 0

  proc describeTerminalEvent(event: TerminalInputEvent): string =
    case event.kind
    of TerminalText:
      "text " & escape(event.text) & " " & $event.textMods
    of TerminalKey:
      "key " & $event.key & " " & $event.action & " " & $event.keyMods
    of TerminalMouseButton:
      "mouse " & $event.button & " " & $event.mouseAction & " " &
        $event.buttonX & "," & $event.buttonY & " " & $event.buttonMods
    of TerminalMouseMove:
      "move " & $event.moveX & "," & $event.moveY & " drag=" &
        $event.dragButton & " " & $event.moveMods
    of TerminalMouseWheel:
      "wheel " & $event.wheelDelta & " @ " & $event.wheelX & "," &
        $event.wheelY & " " & $event.wheelMods
    of TerminalGridSize:
      "grid " & $event.width & "x" & $event.height
    of TerminalPixelSize:
      "pixels " & $event.width & "x" & $event.height
    of TerminalCellPixelSize:
      "cell pixels " & $event.width & "x" & $event.height
    of TerminalKittyFlags:
      "kitty flags " & $event.kittyFlags

  proc recordTerminalEvents(self: TerminalPlatform) =
    for event in self.terminal.lastEvents:
      if not self.settings.recordMouseEvents and event.kind in {
          TerminalMouseButton, TerminalMouseMove, TerminalMouseWheel}:
        continue
      self.eventHistory.add event.describeTerminalEvent()
    let overflow = self.eventHistory.len - TerminalEventHistoryLimit
    if overflow > 0:
      for index in 0 ..< TerminalEventHistoryLimit:
        self.eventHistory[index] = self.eventHistory[index + overflow]
      self.eventHistory.setLen(TerminalEventHistoryLimit)

  proc buildTerminalEventHistoryItem(b: var UiBuilder, itemIndex: int,
      userData: int) {.nimcall, gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      let self = cast[TerminalPlatform](userData)
      if self == nil or itemIndex < 0 or itemIndex >= self.eventHistory.len:
        return
      let historyIndex = self.eventHistory.len - 1 - itemIndex
      discard b.fillX().height(1).textStyleIndex(int(UiStyleIndexLabelText))
        .text(self.eventHistory[historyIndex])

  proc configureTerminalTheme(builder: var UiBuilder) =
    builder.defaultText.fontSize = 1.0'f32
    for styleIndex in low(UiStyleIndex) .. high(UiStyleIndex):
      let style = builder.themeStyle(styleIndex)
      style.borderWidth = min(style.borderWidth, 1.0'f32)
      let borderPadding = if style.borderWidth > 0.0'f32: 1.0'f32 else: 0.0'f32
      style.paddingX = borderPadding
      style.paddingY = borderPadding
      style.cornerRadius = 0.0'f32
    for styleIndex in low(UiTextStyleIndex) .. high(UiTextStyleIndex):
      builder.themeTextStyle(styleIndex).fontSize = 1.0'f32

  proc initTerminalPlatform(self: TerminalPlatform, options: AppOptions) =
    try:
      self.noUI = options.noUI
      when defined(windows):
        self.readInputOnThread = true
      if options.noPty:
        self.readInputOnThread = true

      var kittyKeyboardFlags = DefaultKittyKeyboardFlags
      if options.kittyKeyboardFlags.len > 0:
        var parsedFlags = 0
        if options.kittyKeyboardFlags.parseBin(parsedFlags) ==
            options.kittyKeyboardFlags.len:
          kittyKeyboardFlags = parsedFlags
        else:
          log lvlError, "Invalid Kitty keyboard flags: ",
            options.kittyKeyboardFlags

      self.nui = newTerminalBuilder()
      self.nui.configureTerminalTheme()
      self.terminal.init(kittyKeyboardFlags)
      self.settings = TerminalSettings(
        renderOnDemand: true,
        escapeTimeoutMs: DefaultEscapeTimeoutMs.float32,
      )
      self.fps = 60.0
      self.eventHistoryExpanded = true
      self.debugPanel = DebugPanel()
      if self.readInputOnThread:
        self.readInputOnThread = startTerminalInputThread()
      self.input = self.terminal.input
      self.fontInfo = FontInfo(
        ascent: 0,
        lineHeight: 1,
        lineGap: 0,
        scale: 1,
        advance: proc(rune: Rune): float = max(1, rune.runeCellWidth).float,
      )
      self.supportsThinCursor = false
      self.focused = true
      self.redrawEverything = true
    except CatchableError as error:
      log lvlError, "Failed to initialize terminal backend: ", error.msg

  proc deinitTerminalPlatform(self: TerminalPlatform) =
    self.terminal.deinit()

  proc requestRenderTerminalPlatform(self: TerminalPlatform, redrawEverything: bool) =
    self.requestedRender = true
    self.redrawEverything = self.redrawEverything or redrawEverything

  proc sizeTerminalPlatform(self: TerminalPlatform): Vec2 =
    vec2(self.terminal.width.float, self.terminal.height.float)

  proc sizeChangedTerminalPlatform(self: TerminalPlatform): bool = false

  proc dispatchTerminalKeyEvents(self: TerminalPlatform) =
    var pendingInput = 0'i64
    var pendingModifiers: Modifiers = {}

    template dispatchPendingKeyPress() =
      if pendingInput != 0:
        self.onKeyPress.invoke((pendingInput, pendingModifiers))
        pendingInput = 0

    for event in self.terminal.lastEvents:
      case event.kind
      of TerminalText:
        let modifiers = event.textMods.toPlatformModifiers
        self.setMods(modifiers)
        var consumedPending = false
        for rune in event.text.runes:
          if rune.int32 in char.low.ord .. char.high.ord and
              rune.char in {' ', 8.char, 9.char, 13.char, 127.char}:
            continue
          if not consumedPending:
            pendingInput = 0
            consumedPending = true
          self.onRune.invoke((rune.int64, modifiers))
      of TerminalKey:
        let modifiers = event.keyMods.toPlatformModifiers
        self.setMods(modifiers)
        let input = event.key.toPlatformInput
        if input == 0:
          continue
        case event.action
        of InputRelease:
          dispatchPendingKeyPress()
          self.onKeyRelease.invoke((input, modifiers))
        of InputPress, InputRepeat:
          dispatchPendingKeyPress()
          if input < 0:
            self.onKeyPress.invoke((input, modifiers))
          else:
            pendingInput = input
            pendingModifiers = modifiers
      else:
        discard
    dispatchPendingKeyPress()

  proc processEventsTerminalPlatform(self: TerminalPlatform): int {.gcsafe, raises: [].} =
    try:
      let oldWidth = self.terminal.width
      let oldHeight = self.terminal.height
      if self.readInputOnThread:
        var inputBytes = ""
        while true:
          let (available, value) = inputChannel.tryRecv()
          if not available:
            break
          inputBytes.add value
        self.input = self.terminal.pollInput(inputBytes)
      else:
        self.input = self.terminal.pollInput()
      self.recordTerminalEvents()
      let modifiers = self.input.modsDown.toPlatformModifiers

      if not self.noUI:
        self.dispatchTerminalKeyEvents()
        self.setMods(modifiers)

        for button in self.input.mousePressed:
          var platformButton = button.toPlatformMouseButton
          if button == MouseLeft and self.input.mouseClickCount == 2:
            platformButton = MouseButton.DoubleClick
          elif button == MouseLeft and self.input.mouseClickCount >= 3:
            platformButton = MouseButton.TripleClick
          self.onMousePress.invoke((platformButton, modifiers,
            vec2(self.input.mouse.x.float, self.input.mouse.y.float)))
        for button in self.input.mouseReleased:
          self.onMouseRelease.invoke((button.toPlatformMouseButton, modifiers,
            vec2(self.input.mouse.x.float, self.input.mouse.y.float)))
        if self.input.mouseDelta.x != 0 or self.input.mouseDelta.y != 0:
          var buttons: set[MouseButton] = {}
          for button in self.input.mouseDown:
            buttons.incl button.toPlatformMouseButton
          self.onMouseMove.invoke((
            vec2(self.input.mouse.x.float, self.input.mouse.y.float),
            vec2(self.input.mouseDelta.x.float, self.input.mouseDelta.y.float),
            modifiers, buttons))
        if self.input.wheel.x != 0 or self.input.wheel.y != 0:
          self.onScroll.invoke((
            vec2(self.input.mouse.x.float, self.input.mouse.y.float),
            vec2(self.input.wheel.x.float, self.input.wheel.y.float), modifiers))
      else:
        self.setMods(modifiers)

      if oldWidth != self.terminal.width or oldHeight != self.terminal.height:
        self.onResize.invoke()
        self.requestRenderTerminalPlatform(true)

      self.eventCounter = if self.terminal.hadEvents: 1 else: 0
      return self.eventCounter
    except:
      return 0

  proc shouldRenderTerminalPlatform(self: TerminalPlatform): bool =
    not self.settings.renderOnDemand or
      self.nui.shouldRender(self.terminal.hadEvents)

  proc beginNuiFrameTerminalPlatform(self: TerminalPlatform) =
    discard self.nui.beginUiFrame(self.terminal.width.float32,
      self.terminal.height.float32, self.input)

    var base = 0
    self.nui.node("base"):
      discard self.nui.fillX().fillY().noHover()
      base = self.nui.currentNodeIndex
    self.nui.windowSpace()
    self.nui.node("overlays"):
      discard self.nui.fillX().fillY().noHover()
      self.nui.overlays = self.nui.currentNode.id
    discard self.nui.beginAttach(base)

  proc buildSettingsWindow(self: TerminalPlatform) =
    if self.terminal.width < 20 or self.terminal.height < 5:
      return
    let windowWidth = max(20, min(52, self.terminal.width)).float32
    let windowHeight = max(5, min(30, self.terminal.height)).float32
    self.nui.window("Settings", 0, 0, windowWidth, windowHeight):
      self.nui.scrollBox:
        discard self.nui.fillX().fitY()
        self.nui.layoutVertical:
          discard self.nui.fillX().fitY().padding(1).gap(1)

          self.nui.node:
            self.nui.debugName("settings-performance-heading")
            discard self.nui.fillX().fitY().fillBackground()
              .styleIndex(UiStyleIndexHeader)
              .textStyleIndex(int(UiStyleIndexHeadingText)).text("Performance")

          self.nui.node:
            self.nui.debugName("settings-fps-row")
            discard self.nui.fillX().fitY()
              .textStyleIndex(int(UiStyleIndexLabelText))
              .text("FPS: " & formatFloat(self.fps, ffDecimal, 0))
          self.nui.node:
            self.nui.debugName("settings-frame-time-row")
            discard self.nui.fillX().fitY()
              .textStyleIndex(int(UiStyleIndexLabelText))
              .text("Total frame: " &
                formatFloat(self.frameTimeMs, ffDecimal, 1) & " ms")
          self.nui.node:
            self.nui.debugName("settings-processing-time-row")
            discard self.nui.fillX().fitY()
              .textStyleIndex(int(UiStyleIndexLabelText))
              .text("Processing: " &
                formatFloat(self.processingTimeMs, ffDecimal, 1) & " ms")

          self.nui.node:
            self.nui.debugName("settings-rendering-heading")
            discard self.nui.fillX().fitY().fillBackground()
              .styleIndex(UiStyleIndexHeader)
              .textStyleIndex(int(UiStyleIndexHeadingText)).text("Rendering")

          discard self.nui.checkbox("Render on demand",
            self.settings.renderOnDemand)
          discard self.nui.checkbox("Demo",
            self.settings.showDemoWindow)
          discard self.nui.checkbox("Debug panel",
            self.settings.showDebugPanel)

          self.nui.node:
            self.nui.debugName("settings-input-heading")
            discard self.nui.fillX().fitY().fillBackground()
              .styleIndex(UiStyleIndexHeader)
              .textStyleIndex(int(UiStyleIndexHeadingText)).text("Input")

          discard self.nui.checkbox("Record mouse events",
            self.settings.recordMouseEvents)

          self.nui.tableLayout([tableColumnFit(), tableColumnFill()], 1, 1):
            discard self.nui.fillX().fitY()
            self.nui.node:
              self.nui.debugName("settings-escape-timeout-label")
              discard self.nui.fit().textStyleIndex(int(UiStyleIndexLabelText))
                .text("Escape timeout (ms)")
            if self.nui.dragFloat(self.settings.escapeTimeoutMs,
                DefaultEscapeTimeoutMs.float32, 0.0'f32, 1000.0'f32,
                trackWidth = 16.0'f32):
              self.settings.escapeTimeoutMs =
                round(self.settings.escapeTimeoutMs).float32
              self.terminal.setEscapeTimeout(
                self.settings.escapeTimeoutMs.int)

          self.nui.collapsingHeader("Terminal events (" & $self.eventHistory.len & ")",
              self.eventHistoryExpanded):
            self.nui.node:
              discard self.nui.fillX().height(10)
              self.nui.virtualList(self.eventHistoryScroll,
                self.eventHistory.len, 1.0'f32,
                buildTerminalEventHistoryItem, cast[int](self))

  proc buildToolWindows(self: TerminalPlatform) =
    let viewportWidth = self.terminal.width.float32
    let viewportHeight = self.terminal.height.float32
    if viewportWidth < 20 or viewportHeight < 5:
      return

    if self.settings.showDemoWindow:
      let demoWidth = min(80.0'f32, viewportWidth)
      let demoHeight = min(30.0'f32, viewportHeight)
      let demoX = max(0.0'f32, viewportWidth - demoWidth)
      self.nui.window("Demo", demoX, 0.0'f32, demoWidth, demoHeight):
        {.cast(gcsafe).}:
          try:
            self.nui.buildDemoUi()
          except:
            discard

    if self.settings.showDebugPanel:
      let debugWidth = min(60.0'f32, max(20.0'f32, viewportWidth * 0.5'f32))
      let debugX = max(0.0'f32, viewportWidth - debugWidth)
      self.nui.window("Debug Panel", debugX, 0.0'f32,
          debugWidth, viewportHeight):
        {.cast(gcsafe).}:
          try:
            discard self.nui.debugPanel(self.debugPanel)
            self.nui.flushDeferredNodes()
          except:
            discard

  proc endNuiFrameTerminalPlatform(self: TerminalPlatform) =
    self.nui.endAttach()
    self.buildSettingsWindow()
    self.buildToolWindows()
    self.nui.endUiFrame()

  proc finishFrameMetrics(self: TerminalPlatform, frameTimeMs,
      processingTimeMs: float) =
    if frameTimeMs > 0:
      self.fps = self.fps * 0.5 + 500.0 / frameTimeMs
    self.frameTimeMs = frameTimeMs
    self.processingTimeMs = processingTimeMs

  proc renderTerminalPlatform(self: TerminalPlatform, rerender: bool) =
    try:
      if rerender and not self.noUI:
        let processingTimeMs = self.frameTimer.elapsed.ms
        self.terminal.render(self.nui)
        self.finishFrameMetrics(self.frameTimer.elapsed.ms, processingTimeMs)
    except CatchableError as error:
      log lvlError, "Failed to render terminal UI: ", error.msg
    self.redrawEverything = false

  proc fontSizeTerminalPlatform(self: TerminalPlatform): float = 1
  proc lineDistanceTerminalPlatform(self: TerminalPlatform): float = 0
  proc lineHeightTerminalPlatform(self: TerminalPlatform): float = 1
  proc charWidthTerminalPlatform(self: TerminalPlatform): float = 1
  proc charGapTerminalPlatform(self: TerminalPlatform): float = 0

  proc setVsyncTerminalPlatform(self: TerminalPlatform, enabled: bool) {.gcsafe, raises: [].} =
    discard

  proc getFontInfoTerminalPlatform(self: TerminalPlatform, fontSize: float,
      flags: UINodeFlags): ptr FontInfo {.gcsafe, raises: [].} =
    self.fontInfo.addr

  proc newTerminalPlatform*(): Platform {.raises: [].} =
    var res = TerminalPlatform()
    res.initImpl = proc(self: Platform, options: AppOptions) =
      self.TerminalPlatform.initTerminalPlatform(options)
    res.deinitImpl = proc(self: Platform) =
      self.TerminalPlatform.deinitTerminalPlatform()
    res.requestRenderImpl = proc(self: Platform, redrawEverything: bool) =
      self.TerminalPlatform.requestRenderTerminalPlatform(redrawEverything)
    res.renderImpl = proc(self: Platform, rerender: bool) =
      self.TerminalPlatform.renderTerminalPlatform(rerender)
    res.sizeChangedImpl = proc(self: Platform): bool =
      self.TerminalPlatform.sizeChangedTerminalPlatform()
    res.sizeImpl = proc(self: Platform): Vec2 =
      self.TerminalPlatform.sizeTerminalPlatform()
    res.processEventsImpl = proc(self: Platform): int =
      self.TerminalPlatform.processEventsTerminalPlatform()
    res.fontSizeImpl = proc(self: Platform): float =
      self.TerminalPlatform.fontSizeTerminalPlatform()
    res.lineDistanceImpl = proc(self: Platform): float =
      self.TerminalPlatform.lineDistanceTerminalPlatform()
    res.lineHeightImpl = proc(self: Platform): float =
      self.TerminalPlatform.lineHeightTerminalPlatform()
    res.charWidthImpl = proc(self: Platform): float =
      self.TerminalPlatform.charWidthTerminalPlatform()
    res.charGapImpl = proc(self: Platform): float =
      self.TerminalPlatform.charGapTerminalPlatform()
    res.setVsyncImpl = proc(self: Platform, enabled: bool) =
      self.TerminalPlatform.setVsyncTerminalPlatform(enabled)
    res.getFontInfoImpl = proc(self: Platform, fontSize: float,
        flags: UINodeFlags): ptr FontInfo =
      self.TerminalPlatform.getFontInfoTerminalPlatform(fontSize, flags)
    res.shouldRenderImpl = proc(self: Platform): bool =
      self.TerminalPlatform.shouldRenderTerminalPlatform()
    res.beginNuiFrameImpl = proc(self: Platform) =
      self.TerminalPlatform.beginNuiFrameTerminalPlatform()
    res.endNuiFrameImpl = proc(self: Platform) =
      self.TerminalPlatform.endNuiFrameTerminalPlatform()
    return res

  proc init_module_terminal_platform*() {.cdecl, exportc, dynlib.} =
    discard

  {.pop: raises.}
  {.pop: gcsafe.}

elif implModule:
  proc init_module_terminal_platform*() {.cdecl, exportc, dynlib.} =
    discard
  proc newTerminalPlatform*(): Platform {.raises: [].} =
    assert false
    nil
else:
  proc init_module_terminal_platform*() {.cdecl, exportc, dynlib.} =
    discard