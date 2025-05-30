import std/[os, streams, strutils, sequtils, strformat, typedthreads, tables, json, colors]
# import std/winlean
import winim/lean
import nimsumtree/arc
import misc/[async_process, custom_logger, util, custom_unicode, custom_async, event, timer]
import dispatch_tables, config_provider, events, view, layout, service, platform_service
import scripting/expose
import platform/[tui, platform]
import vterm

logCategory "terminal-service"

type HPCON* = HANDLE

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: DWORD = 131094

proc CreatePseudoConsole*(size: wincon.COORD, hInput: HANDLE, hOutput: HANDLE, dwFlags: DWORD, phPC: ptr HPCON): HRESULT {.winapi, stdcall, dynlib: "kernel32", importc.}
proc ClosePseudoConsole*(hPC: HPCON) {.winapi, stdcall, dynlib: "kernel32", importc.}
proc ResizePseudoConsole*(phPC: HPCON, size: wincon.COORD): HRESULT {.winapi, stdcall, dynlib: "kernel32", importc.}

proc inputToVtermKey(input: int64): VTermKey =
  return case input
  of INPUT_ENTER: VTERM_KEY_ENTER
  of INPUT_ESCAPE: VTERM_KEY_ESCAPE
  of INPUT_BACKSPACE: VTERM_KEY_BACKSPACE
  of INPUT_DELETE: VTERM_KEY_DEL
  of INPUT_TAB: VTERM_KEY_TAB
  of INPUT_LEFT: VTERM_KEY_LEFT
  of INPUT_RIGHT: VTERM_KEY_RIGHT
  of INPUT_UP: VTERM_KEY_UP
  of INPUT_DOWN: VTERM_KEY_DOWN
  of INPUT_HOME: VTERM_KEY_HOME
  of INPUT_END: VTERM_KEY_END
  of INPUT_PAGE_UP: VTERM_KEY_PAGEUP
  of INPUT_PAGE_DOWN: VTERM_KEY_PAGEDOWN
  of INPUT_F1: VTERM_KEY_FUNCTION_1
  of INPUT_F2: VTERM_KEY_FUNCTION_2
  of INPUT_F3: VTERM_KEY_FUNCTION_3
  of INPUT_F4: VTERM_KEY_FUNCTION_4
  of INPUT_F5: VTERM_KEY_FUNCTION_5
  of INPUT_F6: VTERM_KEY_FUNCTION_6
  of INPUT_F7: VTERM_KEY_FUNCTION_7
  of INPUT_F8: VTERM_KEY_FUNCTION_8
  of INPUT_F9: VTERM_KEY_FUNCTION_9
  of INPUT_F10: VTERM_KEY_FUNCTION_10
  of INPUT_F11: VTERM_KEY_FUNCTION_11
  of INPUT_F12: VTERM_KEY_FUNCTION_12
  else: VTERM_KEY_NONE

proc toVtermModifiers(modifiers: Modifiers): uint32 =
  if Modifier.Shift in modifiers:
    result = result or VTERM_MOD_SHIFT.ord.uint32
  if Modifier.Control in modifiers:
    result = result or VTERM_MOD_CTRL.ord.uint32
  if Modifier.Alt in modifiers:
    result = result or VTERM_MOD_ALT.ord.uint32

proc toVtermButton(button: input.MouseButton): cint =
  # todo: figure out what to do here and handle other mouse buttons
  case button
  of Left: return 1
  of Right: return 2
  of Middle: return 3
  else: return 4

proc prepareStartupInformation*(hpc: HPCON): STARTUPINFOEX =
  ZeroMemory(addr(result), sizeof((result)))
  result.StartupInfo.cb = sizeof((STARTUPINFOEX)).DWORD

  var bytesRequired: SIZE_T
  InitializeProcThreadAttributeList(nil, 1, 0, addr(bytesRequired))

  result.lpAttributeList = cast[PPROC_THREAD_ATTRIBUTE_LIST](HeapAlloc(GetProcessHeap(), 0, bytesRequired))

  if result.lpAttributeList == nil:
    raiseOSError(14.OSErrorCode)

  if InitializeProcThreadAttributeList(result.lpAttributeList, 1, 0, addr(bytesRequired)) == 0:
    HeapFree(GetProcessHeap(), 0, result.lpAttributeList)
    raiseOSError(osLastError())

  if UpdateProcThreadAttribute(result.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, cast[LPVOID](hpc),
                                 sizeof((hpc)), nil, nil) == 0:
    HeapFree(GetProcessHeap(), 0, result.lpAttributeList)
    raiseOSError(osLastError())

type
  FileHandleStream = ref object of StreamObj
    handle: Handle
    atTheEnd: bool

proc closeHandleCheck(handle: Handle) {.inline.} =
  if handle.CloseHandle() == 0:
    raiseOSError(osLastError())

proc fileClose[T: Handle | FileHandle](h: var T) {.inline.} =
  if h > 4:
    closeHandleCheck(h)
    h = INVALID_HANDLE_VALUE.T

proc hsClose(s: Stream) =
  FileHandleStream(s).handle.fileClose()

proc hsAtEnd(s: Stream): bool = return FileHandleStream(s).atTheEnd

proc hsReadData(s: Stream, buffer: pointer, bufLen: int): int =
  var s = FileHandleStream(s)
  if s.atTheEnd: return 0
  var br: int32
  var a = ReadFile(s.handle, buffer, bufLen.cint, addr br, nil)
  # TRUE and zero bytes returned (EOF).
  # TRUE and n (>0) bytes returned (good data).
  # FALSE and bytes returned undefined (system error).
  if a == 0 and br != 0: raiseOSError(osLastError())
  s.atTheEnd = br == 0 #< bufLen
  result = br

proc hsWriteData(s: Stream, buffer: pointer, bufLen: int) =
  var s = FileHandleStream(s)
  var bytesWritten: int32
  var a = WriteFile(s.handle, buffer, bufLen.cint,
                            addr bytesWritten, nil)
  if a == 0: raiseOSError(osLastError())

proc newFileHandleStream(handle: Handle): owned FileHandleStream =
  result = FileHandleStream(handle: handle, closeImpl: hsClose, atEndImpl: hsAtEnd,
    readDataImpl: hsReadData, writeDataImpl: hsWriteData)

type
  InputEventKind {.pure.} = enum Text, Key, MouseMove, MouseClick, Scroll, Size
  InputEvent = object
    modifiers: Modifiers
    row: int
    col: int
    case kind: InputEventKind
    of InputEventKind.Text:
      text: string
    of InputEventKind.Key:
      input: int64
    of InputEventKind.MouseMove:
      discard
    of InputEventKind.MouseClick:
      button: input.MouseButton
      pressed: bool
    of InputEventKind.Scroll:
      deltaY: int
    of InputEventKind.Size:
      discard # use row, col

  OutputEventKind {.pure.} = enum TerminalBuffer, Size, Cursor
  OutputEvent = object
    case kind: OutputEventKind
    of OutputEventKind.TerminalBuffer:
      buffer: TerminalBuffer
    of OutputEventKind.Size:
      width: int
      height: int
    of OutputEventKind.Cursor:
      row: int
      col: int
      visible: bool

  ThreadState = object
    vterm: ptr VTerm
    screen: ptr VTermScreen
    hpcon: HPCON
    inputWriteHandle: HANDLE
    outputReadHandle: HANDLE
    inputChannel: ptr Channel[InputEvent]
    outputChannel: ptr Channel[OutputEvent]
    width: int
    height: int
    scrollY: int = 0
    cursorVisible: bool
    scrollbackBuffer: seq[seq[VTermScreenCell]]

  Terminal* = ref object
    command: string
    hpcon: HPCON
    inputWriteHandle: HANDLE
    outputReadHandle: HANDLE
    vterm: ptr VTerm
    screen: ptr VTermScreen
    thread: Thread[ThreadState]
    inputChannel: ptr Channel[InputEvent] # todo: free this
    outputChannel: ptr Channel[OutputEvent] # todo: free this
    terminalBuffer*: TerminalBuffer
    cursor*: tuple[row, col: int, visible: bool]
    onUpdated: Event[void]

proc createTerminalBuffer*(state: var ThreadState): TerminalBuffer =
  result.initTerminalBuffer(state.width, state.height)
  var cell: VTermScreenCell
  var pos: VTermPos
  for scrolledRow in 0..<state.height:
    var col: cint = 0
    for col in 0..<state.width:
      let actualRow = scrolledRow - state.scrollY
      if actualRow >= 0:
        pos.row = actualRow.cint
        pos.col = col.cint
        if state.screen.getCell(pos, addr(cell)) == 0:
          continue
      else:
        let scrollbackIndex = state.scrollbackBuffer.len + actualRow
        if scrollbackIndex < 0:
          continue

        cell = state.scrollbackBuffer[scrollbackIndex][col]

      var c = TerminalChar(
        ch: cell.chars[0].Rune,
        # ch: cell.schar.Rune,
        fg: fgNone,
        bg: bgNone,
        # style: set[Style],
        # forceWrite: bool,
        # previousWideGlyph bool,
      )
      let fg = cell.fg
      if cell.fg.isRGB:
        c.fg = fgRGB
        c.fgColor = rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)
      elif cell.fg.isIndexed:
        c.fg = fgRGB
        let idx = cell.fg.indexed.idx
        state.screen.convertColorToRgb(cell.fg.addr)
        c.fgColor = rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)

      if cell.bg.isRGB:
        c.bg = bgRGB
        c.bgColor = rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)
      elif cell.bg.isIndexed:
        c.bg = bgRGB
        let idx = cell.bg.indexed.idx
        state.screen.convertColorToRgb(cell.bg.addr)
        c.bgColor = rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)

      result[col, scrolledRow] = c

proc handleOutputChannel(self: Terminal) {.async.} =
  # todo: cancel when closed
  while true:
    await sleepAsync(10.milliseconds)

    var updated = false
    while self.outputChannel[].peek() > 0:
      let event = self.outputChannel[].recv()
      case event.kind
      of OutputEventKind.TerminalBuffer:
        self.terminalBuffer = event.buffer
      of OutputEventKind.Size:
        discard
      of OutputEventKind.Cursor:
        self.cursor = (event.row, event.col, event.visible)

      updated = true

    if updated:
      self.onUpdated.invoke()

proc handleInputEvents(state: var ThreadState, inputWriteStream: var FileHandleStream) =
  while state.inputChannel[].peek() > 0:
    let event = state.inputChannel[].recv()
    try:
      case event.kind
      of InputEventKind.Text:
        inputWriteStream.write(event.text)
      of InputEventKind.Key:
        if event.input > 0:
          state.vterm.uniChar(event.input.uint32, event.modifiers.toVtermModifiers)
        elif event.input < 0:
          case event.input
          of INPUT_SPACE:
            state.vterm.uniChar(' '.uint32, event.modifiers.toVtermModifiers)
          else:
            state.vterm.key(event.input.inputToVtermKey, event.modifiers.toVtermModifiers)

      of InputEventKind.MouseMove:
        state.vterm.mouseMove(event.row.cint, event.col.cint, event.modifiers.toVtermModifiers)

      of InputEventKind.MouseClick:
        state.vterm.mouseMove(event.row.cint, event.col.cint, event.modifiers.toVtermModifiers)
        state.vterm.mouseButton(event.button.toVtermButton, event.pressed, event.modifiers.toVtermModifiers)

      of InputEventKind.Scroll:
        state.scrollY += event.deltaY
        state.scrollY = max(state.scrollY, 0)
        state.outputChannel[].send OutputEvent(
          kind: OutputEventKind.TerminalBuffer,
          buffer: state.createTerminalBuffer())

      of InputEventKind.Size:
        state.width = event.col
        state.height = event.row
        state.vterm.setSize(state.height.cint, state.width.cint)
        state.screen.flushDamage()
        state.outputChannel[].send OutputEvent(
          kind: OutputEventKind.TerminalBuffer,
          buffer: state.createTerminalBuffer())
        ResizePseudoConsole(state.hpcon, wincon.COORD(X: state.width.SHORT, Y: state.height.SHORT))

    except:
      echo &"Failed to send input: {getCurrentExceptionMsg()}"

proc handleProcessOutput(state: var ThreadState) =
  var bytesAvailable: DWORD = 0
  if PeekNamedPipe(state.outputReadHandle, nil, 0, nil, bytesAvailable.addr, nil) == 0:
    echo "Failed to peek named pipe", newOSError(osLastError()).msg

  if bytesAvailable > 0:
    buffer.setLen(bytesAvailable)
    outputReadStream.readStr(buffer.len, buffer)
    let written = state.vterm.writeInput(buffer.cstring, buffer.len.csize_t).int
    if written != buffer.len:
      echo "fix me: vterm.nim.terminalThread vterm.writeInput"
      assert written == buffer.len, "fix me: vterm.nim.terminalThread vterm.writeInput"

    state.screen.flushDamage()
    state.outputChannel[].send OutputEvent(
      kind: OutputEventKind.TerminalBuffer,
      buffer: state.createTerminalBuffer())

proc terminalThread(s: ThreadState) {.thread, nimcall.} =
  var state = s

  var inputWriteStream = newFileHandleStream(FileHandle(state.inputWriteHandle))
  var outputReadStream = newFileHandleStream(FileHandle(state.outputReadHandle))

  proc handleOutput(s: cstring; len: csize_t; user: pointer) {.cdecl.} =
    var str = newSeq[uint8]()
    for i in 0..<len.int:
      str.add s[i].uint8

    if len > 0:
      let state = cast[ptr ThreadState](user)
      var bytesWritten: int32
      if WriteFile(state[].inputWriteHandle, s[0].addr, len.cint, bytesWritten.addr, nil) == 0:
        echo "Failed to write data to shell: ", newOSError(osLastError()).msg
      if bytesWritten.int < len.int:
        echo "--------------------------------------------"
        echo "failed to write all bytes to shell"

  var callbacks = VTermScreenCallbacks(
    # damage: (proc(rect: VTermRect; user: pointer): cint {.cdecl.} = discard),
    # moverect: (proc(dest: VTermRect; src: VTermRect; user: pointer): cint {.cdecl.} = discard),
    movecursor: (proc(pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.} =
      let visible = visible != 0
      let state = cast[ptr ThreadState](user)
      # echo &"movecursor {oldpos} -> {pos}, {visible}"
      if state.cursorVisible != visible or (visible and pos != oldpos):
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: pos.row.int, col: pos.col.int, visible: visible != 0)
      state.cursorVisible = visible
    ),
    # settermprop: (proc(prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.} = discard),
    # bell: (proc(user: pointer): cint {.cdecl.} = discard),
    resize: (proc(rows: cint; cols: cint; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Size, width: cols.int, height: rows.int)
    ),
    sb_pushline: (proc(cols: cint; cells: ptr UncheckedArray[VTermScreenCell]; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      var line = newSeq[VTermScreenCell](cols)
      for i in 0..<cols:
        line[i] = cells[i]

      state[].scrollbackBuffer.add(line)

      return 0 # return value is ignored
    ),
    sb_popline: (proc(cols: cint; cells: ptr UncheckedArray[VTermScreenCell]; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      if state[].scrollbackBuffer.len > 0:
        let line = state[].scrollbackBuffer.pop()
        for i in 0..<min(cols, line.len):
          cells[i] = line[i]
        return 1
      return 0
    ),
    sb_clear: (proc(user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      state[].scrollbackBuffer.setLen(0)
      return 1
    ),
  )

  state.vterm.setOutputCallback(handleOutput, state.addr)
  state.vterm.screen.setCallbacks(callbacks.addr, state.addr)

  var buffer = ""
  while not outputReadStream.atEnd:
    var timer = startTimer()
    state.handleProcessOutput()
    state.handleInputEvents(inputWriteStream)
    let elapsed = timer.elapsed.ms.int
    if elapsed < 2:
      sleep(0)

proc createTerminal*(width: int, height: int, command: string): Terminal =
  var
    inputReadSide: HANDLE
    outputWriteSide: HANDLE

  var
    outputReadSide: HANDLE
    inputWriteSide: HANDLE

  var sa: SECURITY_ATTRIBUTES
  sa.nLength = sizeof(sa).DWORD
  sa.lpSecurityDescriptor = nil
  sa.bInheritHandle = true
  if CreatePipe(addr(inputReadSide), addr(inputWriteSide), sa.addr, 10 * 1024 * 1024) == 0:
    raiseOSError(osLastError())

  if CreatePipe(addr(outputReadSide), addr(outputWriteSide), sa.addr, 10 * 1024 * 1024) == 0:
    raiseOSError(osLastError())

  var hPC: HPCON
  if CreatePseudoConsole(wincon.COORD(X: width.SHORT, Y: height.SHORT), inputReadSide, outputWriteSide, 0, addr(hPC)) != S_OK:
    raiseOSError(osLastError())

  var siEx: STARTUPINFOEX = prepareStartupInformation(hPC)
  var pi: PROCESS_INFORMATION
  ZeroMemory(addr(pi), sizeof((pi)))

  let cmd = newWideCString(command)
  if CreateProcessW(nil, cmd, nil, nil, FALSE, EXTENDED_STARTUPINFO_PRESENT, nil, nil, siEx.StartupInfo.addr, pi.addr) == 0:
    raiseOSError(osLastError())

  CloseHandle(inputReadSide)
  CloseHandle(outputWriteSide)

  let vterm = VTerm.new(height.cint, width.cint)
  if vterm == nil:
    raise newException(IOError, "Failed to init VTerm")

  vterm.setUtf8(1)

  let screen = vterm.screen()
  screen.reset(1)
  screen.setDamageMerge(VTERM_DAMAGE_SCROLL)

  result = Terminal(
    command: command,
    hpcon: hPC,
    inputWriteHandle: inputWriteSide,
    outputReadHandle: outputReadSide,
    vterm: vterm,
    screen: screen,
  )

  proc createChannel[T](channel: var ptr[Channel[T]]) =
    channel = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
    channel[].open()

  result.inputChannel.createChannel()
  result.outputChannel.createChannel()

  result.terminalBuffer.initTerminalBuffer(width, height)
  asyncSpawn result.handleOutputChannel()

  let threadState = ThreadState(
    vterm: vterm,
    screen: screen,
    hpcon: result.hpcon,
    inputWriteHandle: inputWriteSide,
    outputReadHandle: outputReadSide,
    inputChannel: result.inputChannel,
    outputChannel: result.outputChannel,
    width: width,
    height: height,
    cursorVisible: true,
  )
  result.thread.createThread(terminalThread, threadState)

proc terminate*(self: Terminal) =
  # echo &"terminate {self.command}"
  ClosePseudoConsole(self.hpcon)

{.push gcsafe.}
{.push raises: [].}

type
  TerminalService* = ref object of Service
    events: EventHandlerService
    config: ConfigService
    layout: LayoutService
    terminal: Terminal

  TerminalView* = ref object of View
    eventHandler: EventHandler
    modeEventHandler: EventHandler
    mode*: string
    size*: tuple[width, height: int]
    terminal*: Terminal

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[JsonNode]

method getEventHandlers*(self: TerminalView, inject: Table[string, EventHandler]): seq[EventHandler] =
  result = @[self.eventHandler]
  if self.modeEventHandler != nil:
    result.add self.modeEventHandler

func serviceName*(_: typedesc[TerminalService]): string = "TerminalService"
addBuiltinService(TerminalService, LayoutService, EventHandlerService, ConfigService)

method init*(self: TerminalService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"TerminalService.init"

  self.events = self.services.getService(EventHandlerService).get
  self.layout = self.services.getService(LayoutService).get
  self.config = self.services.getService(ConfigService).get

  return ok()

proc requestRender(self: TerminalService) =
  self.services.getService(PlatformService).get.platform.requestRender()

proc handleInput(self: TerminalService, view: TerminalView, input: string) =
  view.terminal.inputChannel[].send(InputEvent(kind: InputEventKind.Text, text: input))

proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers) =
  view.terminal.inputChannel[].send(InputEvent(kind: InputEventKind.Key, input: input, modifiers: modifiers))

proc handleScroll*(view: TerminalView, deltaY: int, modifiers: Modifiers) =
  view.terminal.inputChannel[].send(InputEvent(kind: InputEventKind.Scroll, deltaY: deltaY, modifiers: modifiers))

proc handleClick*(view: TerminalView, button: input.MouseButton, pressed: bool, modifiers: Modifiers, col: int, row: int) =
  view.terminal.inputChannel[].send(InputEvent(kind: InputEventKind.MouseClick, row: row, col: col, button: button, pressed: pressed, modifiers: modifiers))

proc handleDrag*(view: TerminalView, button: input.MouseButton, col: int, row: int, modifiers: Modifiers) =
  view.terminal.inputChannel[].send(InputEvent(kind: InputEventKind.MouseMove, row: row, col: col, modifiers: modifiers))

proc updateModeEventHandlers(self: TerminalService, view: TerminalView) =
  if view.mode.len == 0:
    view.modeEventHandler = nil
  else:
    let config = self.events.getEventHandlerConfig("terminal." & view.mode)
    assignEventHandler(view.modeEventHandler, config):
      onAction:
        if self.handleAction(view, action, arg).isSome:
          Handled
        else:
          Ignored

      onInput:
        self.handleInput(view, input)
        Handled

      onKey:
        self.handleKey(view, input, mods)
        Handled

proc setSize*(self: TerminalView, width: int, height: int) =
  if self.size != (width, height):
    self.size = (width, height)
    if self.terminal != nil:
      self.terminal.inputChannel[].send(InputEvent(kind: InputEventKind.Size, row: height, col: width))

proc createTerminalView(self: TerminalService): TerminalView =
  try:
    let shell = self.config.runtime.get("terminal.shell", "C:/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe")
    let term = createTerminal(80, 50, shell)
    let view = TerminalView(terminal: term)
    assignEventHandler(view.eventHandler, self.events.getEventHandlerConfig("terminal")):
      onAction:
        if self.handleAction(view, action, arg).isSome:
          Handled
        else:
          Ignored

      onInput:
        self.handleInput(view, input)
        Handled

      onKey:
        self.handleKey(view, input, mods)
        Handled

      view.mode = self.config.runtime.get("terminal.default-mode", "normal")
      self.updateModeEventHandlers(view)

    discard term.onUpdated.subscribe proc() =
      self.services.getService(PlatformService).get.platform.requestRender()

    self.terminal = term

    return view
  except:
    log lvlError, &"Failed to create terminal: {getCurrentExceptionMsg()}"

proc getTerminalService*(): Option[TerminalService] =
  {.gcsafe.}:
    if gServices.isNil: return TerminalService.none
    return gServices.getService(TerminalService)

static:
  addInjector(TerminalService, getTerminalService)

proc setTerminalMode*(self: TerminalService, mode: string) {.expose("terminal").} =
  if self.layout.tryGetCurrentView().getSome(v) and v of TerminalView:
    let view = v.TerminalView
    view.mode = mode
    self.updateModeEventHandlers(view)
    self.requestRender()

proc createTerminal*(self: TerminalService) {.expose("terminal").} =
  self.layout.addView(self.createTerminalView())

genDispatcher("terminal")
addGlobalDispatchTable "terminal", genDispatchTable("terminal")

proc handleActionInternal(self: TerminalService, view: TerminalView, action: string, args: JsonNode): Option[JsonNode] =
  # if self.plugins.invokeAnyCallback(action, args).isNotNil:
  #   return Handled

  try:
    if dispatch(action, args).getSome(res):
      return res.some
  except:
    let argsText = if args.isNil: "nil" else: $args
    log(lvlError, fmt"Failed to dispatch command '{action} {argsText}': {getCurrentExceptionMsg()}")
    return JsonNode.none

  log lvlError, fmt"Unknown command '{action}'"
  return JsonNode.none

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[JsonNode] =
  try:
    var args = newJArray()
    try:
      for a in newStringStream(arg).parseJsonFragments():
        args.add a

      return self.handleActionInternal(view, action, args)
    except CatchableError:
      log(lvlError, fmt"handleCommmand: {action}, Failed to parse args: '{arg}'")
      return JsonNode.none
  except:
    discard
