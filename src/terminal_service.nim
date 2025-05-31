import std/[os, streams, strutils, sequtils, strformat, typedthreads, tables, json, colors, atomics]
import vmath
import chroma
import winim/lean
import nimsumtree/[arc, rope]
import misc/[async_process, custom_logger, util, custom_unicode, custom_async, event, timer, disposable_ref]
import dispatch_tables, config_provider, events, view, layout, service, platform_service, selector_popup, vfs_service, vfs, theme
import scripting/expose
import platform/[tui, platform]
import finder/[finder, previewer]
import vterm, input, input_api
import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup

from std/terminal import Style

const bufferSize = 10 * 1024 * 1024

logCategory "terminal-service"

type HPCON* = HANDLE

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: DWORD = 131094

const PIPE_ACCESS_DUPLEX = 0x3
const PIPE_ACCESS_INBOUND = 0x1
const PIPE_ACCESS_OUTBOUND = 0x2

const PIPE_TYPE_BYTE = 0x0
const PIPE_TYPE_MESSAGE = 0x4

const PIPE_READMODE_BYTE = 0x0
const PIPE_READMODE_MESSAGE = 0x2

const PIPE_WAIT = 0x0

const FILE_FLAG_FIRST_PIPE_INSTANCE = 0x00080000
const FILE_FLAG_WRITE_THROUGH = 0x80000000
const FILE_FLAG_OVERLAPPED = 0x40000000

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
  of input.MouseButton.Left: return 1
  of input.MouseButton.Right: return 2
  of input.MouseButton.Middle: return 3
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

declareSettings TerminalSettings, "terminal":
  ## Mode to enter when creating a new terminal, if no mode is specified otherwise.
  declare defaultMode, string, "normal"

  ## After how many milliseconds of no data received from a terminal it is considered idle, and can be reused
  ## for running more commands.
  declare idleThreshold, int, 500

type
  InputEventKind {.pure.} = enum Text, Key, MouseMove, MouseClick, Scroll, Size, Terminate, RequestRope, SetColorPalette
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
    of InputEventKind.Terminate:
      discard
    of InputEventKind.RequestRope:
      rope: pointer # ptr Rope, but Nim complains about destructors?
    of SetColorPalette:
      colors: seq[tuple[r, g, b: uint8]]

  CursorShape* {.pure.} = enum Block, Underline, BarLeft
  OutputEventKind {.pure.} = enum TerminalBuffer, Size, Cursor, CursorVisible, CursorShape, Terminated, Rope, Scroll
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
    of OutputEventKind.CursorVisible:
      visible: bool
    of OutputEventKind.CursorShape:
      shape: CursorShape
    of OutputEventKind.Terminated:
      exitCode: int
    of OutputEventKind.Rope:
      rope: pointer # ptr Rope, but Nim complains about destructors?
    of OutputEventKind.Scroll:
      deltaY: int
      scrollY: int

  ThreadState = object
    vterm: ptr VTerm
    screen: ptr VTermScreen
    inputChannel: ptr Channel[InputEvent]
    outputChannel: ptr Channel[OutputEvent]
    width: int
    height: int
    scrollY: int = 0
    cursor: tuple[row, col: int, visible: bool]
    scrollbackBuffer: seq[seq[VTermScreenCell]]
    dirty: bool = false # When true send updated terminal buffer to main thread
    terminateRequested: bool = false
    processTerminated: bool = false
    autoRunCommand: string

    # Windows specific stuff
    hpcon: HPCON
    inputWriteHandle: HANDLE
    outputReadHandle: HANDLE
    inputWriteEvent: HANDLE
    outputReadEvent: HANDLE
    waitingForOvelapped: bool
    outputOverlapped: OVERLAPPED
    processInfo: PROCESS_INFORMATION

  Terminal* = ref object
    id*: int
    group*: string
    command*: string
    vterm: ptr VTerm
    screen: ptr VTermScreen
    thread: Thread[ThreadState]
    inputChannel: ptr Channel[InputEvent] # todo: free this
    outputChannel: ptr Channel[OutputEvent] # todo: free this
    terminalBuffer*: TerminalBuffer
    cursor*: tuple[row, col: int, visible: bool, shape: CursorShape]
    scrollY: int
    exitCode*: Option[int]
    autoRunCommand: string

    # Events
    lastUpdateTime: Timer
    onTerminated: Event[int]
    onRope: Event[ptr Rope]
    onUpdated: Event[void]

    # Windows specific stuff
    hpcon: HPCON
    inputWriteHandle: HANDLE
    outputReadHandle: HANDLE
    inputWriteEvent: HANDLE
    processInfo: PROCESS_INFORMATION

  TerminalView* = ref object of View
    terminals: TerminalService
    eventHandler: EventHandler
    modeEventHandler: EventHandler
    mode*: string
    size*: tuple[width, height: int]
    terminal*: Terminal
    closeOnTerminate: bool
    open: bool = true

  TerminalService* = ref object of Service
    events: EventHandlerService
    config: ConfigService
    layout: LayoutService
    themes: ThemeService
    idCounter: int = 0
    settings: TerminalSettings

    terminals*: Table[int, TerminalView]
    activeView: TerminalView

proc createRope*(state: var ThreadState): Rope =
  var cell: VTermScreenCell
  var rope = Rope.new()

  var line = ""
  for cells in state.scrollbackBuffer.mitems:
    line.setLen(0)
    for cell in cells:
      var r = 0.Rune
      if cell.chars[0] <= Rune.high.uint32:
        r = cell.chars[0].Rune

      if r != 0.Rune:
        line.add $r
      else:
        line.add " "

    var endIndex = line.high
    while endIndex >= 0 and line[endIndex] in Whitespace:
      dec endIndex
    rope.add line.toOpenArray(0, endIndex)
    rope.add "\n"

  for row in 0..<state.height:
    line.setLen(0)
    for col in 0..<state.width:
      var pos: VTermPos
      pos.row = row.cint
      pos.col = col.cint
      if state.screen.getCell(pos, addr(cell)) == 0:
        continue

      var r = 0.Rune
      if cell.chars[0] <= Rune.high.uint32:
        r = cell.chars[0].Rune

      if r != 0.Rune:
        line.add $r
      else:
        line.add " "

    var endIndex = line.high
    while endIndex >= 0 and line[endIndex] in Whitespace:
      dec endIndex
    rope.add line.toOpenArray(0, endIndex)
    rope.add "\n"

  return rope

proc createTerminalBuffer*(state: var ThreadState): TerminalBuffer =
  result.initTerminalBuffer(state.width, state.height)
  var cell: VTermScreenCell
  var pos: VTermPos
  for scrolledRow in 0..<state.height:
    var col: cint = 0
    for col in 0..<state.width:
      let actualRow = scrolledRow - state.scrollY
      if actualRow >= 0 and actualRow < state.height:
        pos.row = actualRow.cint
        pos.col = col.cint
        if state.screen.getCell(pos, addr(cell)) == 0:
          continue
      elif actualRow < 0:
        let scrollbackIndex = state.scrollbackBuffer.len + actualRow
        if scrollbackIndex < 0:
          continue

        cell = state.scrollbackBuffer[scrollbackIndex][col]

      var r = 0.Rune
      if cell.chars[0] <= Rune.high.uint32:
        r = cell.chars[0].Rune

      var c = TerminalChar(
        ch: r,
        fg: fgNone,
        bg: bgNone,
      )

      if cell.attrs.bold != 0: c.style.incl(terminal.Style.styleBlink)
      if cell.attrs.italic != 0: c.style.incl(terminal.Style.styleItalic)
      if cell.attrs.underline != 0: c.style.incl(terminal.Style.styleUnderscore)
      # if cell.attrs.blink != 0: c.style.incl(terminal.Style.styleBlink) # todo
      if cell.attrs.reverse != 0: c.style.incl(terminal.Style.styleReverse)
      if cell.attrs.conceal != 0: c.style.incl(terminal.Style.styleHidden)
      if cell.attrs.strike != 0: c.style.incl(terminal.Style.styleStrikethrough)
      if cell.attrs.dim != 0: c.style.incl(terminal.Style.styleDim)

      let fg = cell.fg
      if cell.fg.isDefaultFg:
        c.fg = fgNone
        c.fgColor = colors.rgb(0, 0, 0)
      elif cell.fg.isRGB:
        c.fg = fgRGB
        c.fgColor = colors.rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)
      elif cell.fg.isIndexed:
        c.fg = fgRGB
        let idx = cell.fg.indexed.idx
        state.screen.convertColorToRgb(cell.fg.addr)
        c.fgColor = colors.rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)

      if cell.bg.isDefaultBg:
        c.bg = bgNone
        c.bgColor = colors.rgb(0, 0, 0)
      elif cell.bg.isRGB:
        c.bg = bgRGB
        c.bgColor = colors.rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)
      elif cell.bg.isIndexed:
        c.bg = bgRGB
        let idx = cell.bg.indexed.idx
        state.screen.convertColorToRgb(cell.bg.addr)
        c.bgColor = colors.rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)

      result[col, scrolledRow] = c

proc handleOutputChannel(self: TerminalService, terminal: Terminal) {.async.} =
  # todo: cancel when closed
  while true:
    await sleepAsync(10.milliseconds)

    var updated = false
    while terminal.outputChannel[].peek() > 0:
      let event = terminal.outputChannel[].recv()
      case event.kind
      of OutputEventKind.TerminalBuffer:
        terminal.terminalBuffer = event.buffer
      of OutputEventKind.Size:
        discard
      of OutputEventKind.Cursor:
        terminal.cursor.row = event.row
        terminal.cursor.col = event.col
      of OutputEventKind.CursorVisible:
        terminal.cursor.visible = event.visible
      of OutputEventKind.CursorShape:
        terminal.cursor.shape = event.shape
      of OutputEventKind.Terminated:
        terminal.exitCode = event.exitCode.some
        terminal.onTerminated.invoke(event.exitCode)
      of OutputEventKind.Rope:
        let rope = cast[ptr Rope](event.rope)
        terminal.onRope.invoke(rope)
      of OutputEventKind.Scroll:
        terminal.scrollY = event.scrollY

      updated = true

    if updated:
      terminal.lastUpdateTime = startTimer()
      terminal.onUpdated.invoke()

proc handleInputEvents(state: var ThreadState) =
  while state.inputChannel[].peek() > 0:
    let event = state.inputChannel[].recv()
    try:
      case event.kind
      of InputEventKind.Text:
        # echo "text ", event.text
        for r in event.text.runes:
          state.vterm.uniChar(r.uint32, event.modifiers.toVtermModifiers)
      of InputEventKind.Key:
        # echo "key ", inputToString(event.input, event.modifiers)
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
        let prevScrollY = state.scrollY
        state.scrollY += event.deltaY
        state.scrollY = state.scrollY.clamp(0, state.scrollbackBuffer.len)
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: state.cursor.row + state.scrollY, col: state.cursor.col)
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Scroll, scrollY: state.scrollY, deltaY: state.scrollY - prevScrollY)
        state.dirty = true

      of InputEventKind.Size:
        state.width = event.col
        state.height = event.row
        state.vterm.setSize(state.height.cint, state.width.cint)
        state.screen.flushDamage()
        ResizePseudoConsole(state.hpcon, wincon.COORD(X: state.width.SHORT, Y: state.height.SHORT))
        state.dirty = true

      of InputEventKind.Terminate:
        state.terminateRequested = true

      of InputEventKind.RequestRope:
        let rope = cast[ptr Rope](event.rope)
        rope[] = state.createRope()
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Rope, rope: event.rope)

      of InputEventKind.SetColorPalette:
        for i, c in event.colors:
          state.vterm.state.setPaletteColor(i, c)
        state.dirty = true

    except:
      echo &"Failed to send input: {getCurrentExceptionMsg()}"

proc handleProcessOutput(state: var ThreadState, buffer: var string) =
  template handleData(data: untyped, bytesToWrite: int): untyped =
    let written = state.vterm.writeInput(data, bytesToWrite.csize_t).int
    if written != bytesToWrite:
      echo "fix me: vterm.nim.terminalThread vterm.writeInput"
      assert written == bytesToWrite, "fix me: vterm.nim.terminalThread vterm.writeInput"

    state.screen.flushDamage()
    state.dirty = true

  var bytesRead: DWORD = 0
  if state.waitingForOvelapped:
    if GetOverlappedResult(state.outputReadHandle, state.outputOverlapped.addr, bytesRead.addr, 0) != 0:
      state.waitingForOvelapped = false
      # echo &"handleProcessOutput: {bytesRead}/{buffer.len} data received (GetOverlappedResult)"
      handleData(buffer.cstring, bytesRead.int)

    else:
      let error = osLastError()
      case error.int32
      of ERROR_HANDLE_EOF:
        # echo "handleProcessOutput: reached end of file (GetOverlappedResult)"
        state.waitingForOvelapped = false
        return

      of ERROR_IO_INCOMPLETE:
        # echo "handleProcessOutput: read pending (GetOverlappedResult)"
        state.waitingForOvelapped = true
        return

      else:
        raiseOSError(error)

  # var bytesAvailable: DWORD = 0
  # if PeekNamedPipe(state.outputReadHandle, nil, 0, nil, bytesAvailable.addr, nil) == 0:
  #   echo "Failed to peek named pipe", newOSError(osLastError()).msg

  # if bytesAvailable == 0:
  #   return

  buffer.setLen(bufferSize)
  state.outputOverlapped.hEvent = state.outputReadEvent
  if ReadFile(state.outputReadHandle, buffer[0].addr, buffer.len.DWORD, bytesRead.addr, state.outputOverlapped.addr) != 0:
    # echo &"handleProcessOutput: {bytesRead}/{buffer.len} data received immediately (ReadFile)"
    handleData(buffer.cstring, bytesRead.int)
    state.waitingForOvelapped = false
    return

  let error = osLastError()
  case error.int32
  of ERROR_HANDLE_EOF:
    # echo "handleProcessOutput: reached end of file (ReadFile)"
    state.waitingForOvelapped = false
    return

  of ERROR_IO_PENDING:
    # echo "handleProcessOutput: read pending (ReadFile)"
    state.waitingForOvelapped = true
    return

  else:
    raiseOSError(error)

proc terminalThread(s: ThreadState) {.thread, nimcall.} =
  var state = s

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
      let state = cast[ptr ThreadState](user)
      state.cursor.row = pos.row.int
      state.cursor.col = pos.col.int
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: pos.row.int + state.scrollY, col: pos.col.int)
    ),
    settermprop: (proc(prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      case prop
      of VTERM_PROP_CURSORVISIBLE:
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorVisible, visible: val.boolean)

      of VTERM_PROP_CURSORSHAPE:
        let shape = case val.number
        of VTERM_PROP_CURSORSHAPE_BLOCK: CursorShape.Block
        of VTERM_PROP_CURSORSHAPE_UNDERLINE: CursorShape.Underline
        of VTERM_PROP_CURSORSHAPE_BAR_LEFT: CursorShape.BarLeft
        else: CursorShape.Block
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorShape, shape: shape)

      else:
        discard
    ),
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

  var selectionCallbacks = VTermSelectionCallbacks(
    set: (proc(mask: VTermSelectionMask; frag: VTermStringFragment; user: pointer): cint {.cdecl.} =
      # echo &"selection set {($frag.str)[0..<frag.len.int]}"
      discard
    ),
    query: (proc(mask: VTermSelectionMask; user: pointer): cint {.cdecl.} =
      # echo "selection query"
      discard
    ),
  )

  state.vterm.setOutputCallback(handleOutput, state.addr)
  state.vterm.screen.setCallbacks(callbacks.addr, state.addr)
  state.vterm.state.setSelectionCallbacks(selectionCallbacks.addr, state.addr, nil, 1024)

  if state.autoRunCommand.len > 0:
    for r in state.autoRunCommand.runes:
      state.vterm.uniChar(r.uint32, {}.toVtermModifiers)
    state.vterm.key(INPUT_ENTER.inputToVtermKey, {}.toVtermModifiers)

  var buffer = ""
  while true:
    var handles = [state.inputWriteEvent, state.outputReadEvent, state.processInfo.hProcess]
    let res = WaitForMultipleObjects(handles.len.DWORD, handles[0].addr, FALSE, INFINITE)
    if res == WAIT_FAILED:
      let error = osLastError()
      echo "failed: ", newOSError(error).msg, ", ", error.int
      discard
    elif res == WAIT_TIMEOUT:
      discard
    else:
      if res >= WAIT_ABANDONED_0:
        # let index = res - WAIT_ABANDONED_0
        discard
      elif res >= WAIT_OBJECT_0:
        let index = res - WAIT_OBJECT_0
        assert index >= 0 and index < 3

        if index == 2:
          # Process ended
          var exitCode: DWORD = 0
          discard GetExitCodeProcess(state.processInfo.hProcess, exitCode.addr)
          state.processTerminated = true
          state.outputChannel[].send OutputEvent(kind: OutputEventKind.Terminated, exitCode: exitCode.int)
          break

    state.handleProcessOutput(buffer)
    state.handleInputEvents()

    if state.dirty:
      state.dirty = false
      state.outputChannel[].send OutputEvent(
        kind: OutputEventKind.TerminalBuffer,
        buffer: state.createTerminalBuffer())

  # echo "============================================"
  # echo "terminal thread done"
  # echo "============================================"

proc sendEvent(self: Terminal, event: InputEvent) =
  self.inputChannel[].send(event)
  discard SetEvent(self.inputWriteEvent)

proc terminate*(self: Terminal) =
  log lvlInfo, &"Close terminal '{self.command}'"
  ClosePseudoConsole(self.hpcon)
  self.sendEvent(InputEvent(kind: InputEventKind.Terminate))

proc createTerminal*(self: TerminalService, width: int, height: int, command: string, autoRunCommand: string = ""): Terminal =
  var
    inputReadHandle: HANDLE
    outputWriteHandle: HANDLE

  var
    outputReadHandle: HANDLE
    inputWriteHandle: HANDLE

  var sa: SECURITY_ATTRIBUTES
  sa.nLength = sizeof(sa).DWORD
  sa.lpSecurityDescriptor = nil
  sa.bInheritHandle = true
  if CreatePipe(addr(inputReadHandle), addr(inputWriteHandle), sa.addr, 0) == 0:
    raiseOSError(osLastError())

  let id = self.idCounter
  inc self.idCounter

  let processId = GetProcessID(GetCurrentProcess()).int
  let readPipeName = newWideCString(r"\\.\pipe\nev-terminal-" & $processId & "-" & $id)
  outputReadHandle = CreateNamedPipe(readPipeName, PIPE_ACCESS_INBOUND or FILE_FLAG_OVERLAPPED, PIPE_TYPE_BYTE or PIPE_WAIT, 1, bufferSize, bufferSize, 0, sa.addr)
  if outputReadHandle == INVALID_HANDLE_VALUE:
    raiseOSError(osLastError(), "Failed to create named pipe for terminal")

  outputWriteHandle = CreateFile(readPipeName, GENERIC_WRITE, 0, sa.addr, OPEN_EXISTING, 0, 0)
  if outputWriteHandle == INVALID_HANDLE_VALUE:
    raiseOSError(osLastError(), "Failed to open write end of terminal pipe")

  var hPC: HPCON
  if CreatePseudoConsole(wincon.COORD(X: width.SHORT, Y: height.SHORT), inputReadHandle, outputWriteHandle, 0, addr(hPC)) != S_OK:
    raiseOSError(osLastError(), "Failed to create pseude console")

  var siEx: STARTUPINFOEX = prepareStartupInformation(hPC)
  var pi: PROCESS_INFORMATION
  ZeroMemory(addr(pi), sizeof((pi)))

  let command = if command.len > 0:
    command
  else:
    self.config.runtime.get("terminal.shell", "powershell.exe")

  let cmd = newWideCString(command)
  if CreateProcessW(nil, cmd, nil, nil, FALSE, EXTENDED_STARTUPINFO_PRESENT, nil, nil, siEx.StartupInfo.addr, pi.addr) == 0:
    raiseOSError(osLastError(), "Failed to start sub process")

  CloseHandle(inputReadHandle)
  # CloseHandle(outputWriteHandle)

  let vterm = VTerm.new(height.cint, width.cint)
  if vterm == nil:
    raise newException(IOError, "Failed to init VTerm")

  vterm.setUtf8(1)

  let screen = vterm.screen()
  screen.reset(1)
  screen.setDamageMerge(VTERM_DAMAGE_SCROLL)

  result = Terminal(
    id: id,
    command: command,
    vterm: vterm,
    screen: screen,
    autoRunCommand: autoRunCommand,

    # Windows specific stuff
    hpcon: hPC,
    inputWriteHandle: inputWriteHandle,
    outputReadHandle: outputReadHandle,
    processInfo: pi,
  )

  proc createChannel[T](channel: var ptr[Channel[T]]) =
    channel = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
    channel[].open()

  result.inputChannel.createChannel()
  result.outputChannel.createChannel()

  result.terminalBuffer.initTerminalBuffer(width, height)
  asyncSpawn self.handleOutputChannel(result)

  let inputWriteEvent = CreateEvent(nil, FALSE, FALSE, nil)
  let outputReadEvent = CreateEvent(sa.addr, FALSE, FALSE, nil)
  result.inputWriteEvent = inputWriteEvent

  let threadState = ThreadState(
    vterm: vterm,
    screen: screen,
    hpcon: result.hpcon,
    inputWriteHandle: inputWriteHandle,
    outputReadHandle: outputReadHandle,
    inputWriteEvent: inputWriteEvent,
    outputReadEvent: outputReadEvent,
    inputChannel: result.inputChannel,
    outputChannel: result.outputChannel,
    processInfo: pi,
    width: width,
    height: height,
    cursor: (0, 0, true),
    autoRunCommand: autoRunCommand,
  )
  result.thread.createThread(terminalThread, threadState)

{.push gcsafe.}
{.push raises: [].}

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[JsonNode]

method close*(self: TerminalView) =
  if not self.open:
    return
  self.open = false
  self.terminal.terminate()
  self.terminals.terminals.del(self.terminal.id)

method activate*(self: TerminalView) =
  if self.active:
    return
  self.active = true

method deactivate*(self: TerminalView) =
  if not self.active:
    return
  self.active = false

method getEventHandlers*(self: TerminalView, inject: Table[string, EventHandler]): seq[EventHandler] =
  result = @[self.eventHandler]
  if self.modeEventHandler != nil:
    result.add self.modeEventHandler

proc setTheme(self: Terminal, theme: Theme) =
  let colors1 = @[
    theme.color("terminal.ansiBlack", color(0.5, 0.5, 0.5)),
    theme.color("terminal.ansiRed", color(1.0, 0.5, 0.5)),
    theme.color("terminal.ansiGreen", color(0.5, 1.0, 0.5)),
    theme.color("terminal.ansiYellow", color(1.0, 1.0, 0.5)),
    theme.color("terminal.ansiBlue", color(0.5, 0.5, 1.0)),
    theme.color("terminal.ansiMagenta", color(1.0, 0.5, 1.0)),
    theme.color("terminal.ansiCyan", color(0.5, 1.0, 1.0)),
    theme.color("terminal.ansiWhite", color(1.0, 1.0, 1.0)),
    theme.color("terminal.ansiBrightBlack", color(0.7, 0.7, 0.7)),
    theme.color("terminal.ansiBrightRed", color(1.0, 0.7, 0.7)),
    theme.color("terminal.ansiBrightGreen", color(0.7, 1.0, 0.7)),
    theme.color("terminal.ansiBrightYellow", color(1.0, 1.0, 0.7)),
    theme.color("terminal.ansiBrightBlue", color(0.7, 0.7, 1.0)),
    theme.color("terminal.ansiBrightMagenta", color(1.0, 0.7, 1.0)),
    theme.color("terminal.ansiBrightCyan", color(0.7, 1.0, 1.0)),
    theme.color("terminal.ansiBrightWhite", color(1.0, 1.0, 1.0)),
  ]
  let colors2: seq[tuple[r, g, b: uint8]] = colors1.mapIt((
    r: (it.r * 255).int.clamp(0, 255).uint8,
    g: (it.g * 255).int.clamp(0, 255).uint8,
    b: (it.b * 255).int.clamp(0, 255).uint8,
  ))

  self.sendEvent(InputEvent(kind: InputEventKind.SetColorPalette, colors: colors2))

proc handleThemeChanged(self: TerminalService, theme: Theme) =
  for view in self.terminals.values:
    view.terminal.setTheme(theme)

func serviceName*(_: typedesc[TerminalService]): string = "TerminalService"
addBuiltinService(TerminalService, LayoutService, EventHandlerService, ConfigService, ThemeService)

method init*(self: TerminalService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"TerminalService.init"

  self.events = self.services.getService(EventHandlerService).get
  self.layout = self.services.getService(LayoutService).get
  self.config = self.services.getService(ConfigService).get
  self.themes = self.services.getService(ThemeService).get
  discard self.themes.onThemeChanged.subscribe proc(theme: Theme) = self.handleThemeChanged(theme)

  self.settings = TerminalSettings.new(self.config.runtime)

  return ok()

method deinit*(self: TerminalService) =
  for term in self.terminals.values:
    term.close()

proc requestRender(self: TerminalService) =
  self.services.getService(PlatformService).get.platform.requestRender()

template withActiveView*(self: TerminalService, view: TerminalView, body: untyped): untyped =
  block:
    let prev = self.activeView
    defer:
      self.activeView = prev
    self.activeView = view
    body

proc handleInput(self: TerminalService, view: TerminalView, input: string) =
  # debugf"handleInput '{input}'"
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Text, text: input))

proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers) =
  # debugf"handleKey '{inputToString(input, modifiers)}'"
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Key, input: input, modifiers: modifiers))

proc handleScroll*(view: TerminalView, deltaY: int, modifiers: Modifiers) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Scroll, deltaY: deltaY, modifiers: modifiers))

proc handleClick*(view: TerminalView, button: input.MouseButton, pressed: bool, modifiers: Modifiers, col: int, row: int) =
  # debugf"handleClick '{button}'"
  discard SetEvent(view.terminal.inputWriteEvent)

proc handleDrag*(view: TerminalView, button: input.MouseButton, col: int, row: int, modifiers: Modifiers) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.MouseMove, row: row, col: col, modifiers: modifiers))

proc updateModeEventHandlers(self: TerminalService, view: TerminalView) =
  if view.mode.len == 0:
    view.modeEventHandler = nil
  else:
    let config = self.events.getEventHandlerConfig("terminal." & view.mode)
    assignEventHandler(view.modeEventHandler, config):
      onAction:
        self.withActiveView(view):
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
      self.terminal.sendEvent(InputEvent(kind: InputEventKind.Size, row: height, col: width))

type CreateTerminalOptions* = object
  group*: string = ""
  autoRunCommand*: string = ""
  mode*: Option[string]
  closeOnTerminate*: bool = true

type RunInTerminalOptions* = object
  group*: string = ""
  mode*: Option[string]
  closeOnTerminate*: bool = true
  reuseExisting*: bool = true

proc createTerminalView(self: TerminalService, command: string, options: CreateTerminalOptions): TerminalView =
  try:
    let term = self.createTerminal(80, 50, command, options.autoRunCommand)
    term.group = options.group
    term.setTheme(self.themes.theme)

    let view = TerminalView(terminals: self, terminal: term, closeOnTerminate: options.closeOnTerminate)
    view.initView()

    assignEventHandler(view.eventHandler, self.events.getEventHandlerConfig("terminal")):
      onAction:
        self.withActiveView(view):
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

      if options.mode.getSome(mode):
        view.mode = mode
      else:
        view.mode = self.settings.defaultMode.get()
      self.updateModeEventHandlers(view)

    discard term.onUpdated.subscribe proc() =
      self.services.getService(PlatformService).get.platform.requestRender()
      view.markDirty()

    discard term.onTerminated.subscribe proc(exitCode: int) =
      if not view.open:
        return
      log lvlInfo, &"Terminal process '{command}' terminated with exit code {exitCode}"
      view.mode = "normal"
      self.updateModeEventHandlers(view)
      if view.closeOnTerminate:
        self.layout.closeView(view)
      view.markDirty()
      self.requestRender()

    self.terminals[term.id] = view

    return view
  except:
    log lvlError, &"Failed to create terminal: {getCurrentExceptionMsg()}"

proc getTerminalService*(): Option[TerminalService] =
  {.gcsafe.}:
    if gServices.isNil: return TerminalService.none
    return gServices.getService(TerminalService)

static:
  addInjector(TerminalService, getTerminalService)

proc getActiveView(self: TerminalService): Option[TerminalView] =
  if self.activeView != nil:
    return self.activeView.some
  if self.layout.tryGetCurrentView().getSome(v) and v of TerminalView:
    return v.TerminalView.some
  return TerminalView.none

proc setMode*(self: TerminalView, mode: string) =
  self.mode = mode
  self.markDirty()
  self.terminals.updateModeEventHandlers(self)
  self.terminals.requestRender()

proc setTerminalMode*(self: TerminalService, mode: string) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    view.setMode(mode)

proc createTerminal*(self: TerminalService, command: string = "", options: CreateTerminalOptions = CreateTerminalOptions()) {.expose("terminal").} =
  ## Opens a new terminal by running `command`.
  ## `command`:         Program name and arguments for the process. Usually a shell.
  ## `autoRunCommand`   Command to execute in the shell. This is passed to `command` through stdin, as if typed
  ##                    into a shell.
  ## `closeOnTerminate` Close the terminal when the process ends.
  self.layout.addView(self.createTerminalView(command, options))

proc isIdle(self: TerminalService, terminal: Terminal): bool =
  if not terminal.cursor.visible or terminal.cursor.col == 0:
    # Assuming that a shell never has an empty prompt and the cursor is visible when in the prompt
    return false
  let idleThreshold = self.settings.idleThreshold.get()
  return terminal.lastUpdateTime.elapsed.ms.int > idleThreshold

proc runInTerminal*(self: TerminalService, shell: string, command: string, options: RunInTerminalOptions = RunInTerminalOptions()) {.expose("terminal").} =
  let shellCommand = self.config.runtime.get("editor.shells." & shell & ".command", string.none)
  if shellCommand.isNone:
    log lvlError, &"Failed to run command in shell '{shell}': Unknown shell, configure in 'editor.shells.{shell}'"
    return
  if shellCommand.get == "":
    log lvlError, &"Failed to run command in shell '{shell}': Invalid configuration, empty 'editor.shells.{shell}.command'"
    return

  if options.reuseExisting:
    for view in self.terminals.values:
      if view.terminal.group == options.group and view.terminal.command == shellCommand.get and self.isIdle(view.terminal):
        if command.len > 0:
          self.handleInput(view, command)
          self.handleKey(view, INPUT_ENTER, {})
        view.handleScroll(-5000000, {})
        if options.mode.isSome:
          view.setMode(options.mode.get)
        self.layout.showView(view)
        return

  var options = options
  self.createTerminal(shellCommand.get, CreateTerminalOptions(
    group: options.group,
    autoRunCommand: command,
    mode: options.mode,
    closeOnTerminate: options.closeOnTerminate,
  ))

proc scrollTerminal*(self: TerminalService, amount: int) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    view.handleScroll(amount, {})

proc sendTerminalInput*(self: TerminalService, input: string) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    for (inputCode, mods, _) in parseInputs(input):
      self.handleKey(view, inputCode.a, mods)

proc sendTerminalInputAndSetMode*(self: TerminalService, input: string, mode: string) {.expose("terminal").} =
  self.sendTerminalInput(input)
  self.setTerminalMode(mode)

# todo: I don't like this import
import text/text_editor

proc requestEditBuffer*(self: TerminalView) {.async.} =
  var rope: Rope = Rope.new()
  let ropePtr = rope.addr
  self.terminal.sendEvent(InputEvent(kind: InputEventKind.RequestRope, rope: ropePtr))

  var waiting = true
  let handle = self.terminal.onRope.subscribe proc(r: ptr Rope) =
    if r != ropePtr:
      return
    waiting = false

  while waiting:
    await sleepAsync(30.milliseconds)

  self.terminal.onRope.unsubscribe(handle)

  let path = &"ed://{self.terminal.id}.terminal-output"
  await self.terminals.services.getService(VFSService).get.vfs.write(path, rope)

  if self.terminals.layout.openFile(path).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    let numLines = rope.lines
    let height = self.size.height
    let scrollY = self.terminal.scrollY
    textEditor.targetSelection = (numLines - height div 2 - 1 - scrollY, 0).toSelection
    textEditor.uiSettings.lineNumbers.set(api.LineNumbers.None)
    textEditor.setNextSnapBehaviour(ScrollSnapBehaviour.Always)
    textEditor.centerCursor()

proc editTerminalBuffer*(self: TerminalService) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    asyncSpawn view.requestEditBuffer()

# todo: move dependencies of terminal_previewer out of this file into separate file
import terminal_previewer

proc selectTerminal*(self: TerminalService, preview: bool = true, scaleX: float = 0.8, scaleY: float = 0.8, previewScale: float = 0.6) {.expose("terminal").} =
  defer:
    self.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    let allViews = self.layout.hiddenViews
    var items = newSeq[FinderItem]()
    for i in countdown(allViews.high, 0):
      if allViews[i] of TerminalView:
        let view = allViews[i].TerminalView
        var name = view.terminal.command
        if view.terminal.autoRunCommand != "":
          name.add " -- "
          name.add view.terminal.autoRunCommand
        items.add FinderItem(
          displayName: name,
          filterText: name,
          data: $view.terminal.id,
          detail: view.terminal.exitCode.mapIt("-> " & $it).get(""),
        )

    return items

  let source = newSyncDataSource(getItems)
  var finder = newFinder(source, filterAndSort=true)
  finder.filterThreshold = float.low

  let previewer = if preview:
    newTerminalPreviewer(self.services, self).Previewer.toDisposableRef.some
  else:
    DisposableRef[Previewer].none

  var popup = newSelectorPopup(self.services, "terminals".some, finder.some, previewer)
  popup.scale.x = scaleX
  popup.scale.y = scaleY
  popup.previewScale = previewScale

  popup.handleItemConfirmed = proc(item: FinderItem): bool =
    let id = item.data.parseInt.catch:
      log lvlError, fmt"Failed to parse editor id from data '{item}'"
      return true

    if id in self.terminals:
      let view = self.terminals[id]
      self.layout.showView(view)
    return true

  popup.addCustomCommand "close-selected", proc(popup: SelectorPopup, args: JsonNode): bool =
    if popup.textEditor.isNil:
      return false

    let item = popup.getSelectedItem().getOr:
      return true

    let id = item.data.parseInt.catch:
      log lvlError, fmt"Failed to parse editor id from data '{item}'"
      return true

    if id in self.terminals:
      let view = self.terminals[id]
      self.layout.closeView(view)

    if popup.getNumItems() == 1:
      popup.pop()
    else:
      source.retrigger()
    return true

  self.layout.pushPopup popup

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
  # debugf"handleAction '{action} {arg}'"
  self.activeView = view
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
