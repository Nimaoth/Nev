import std/[os, streams, strutils, sequtils, strformat, typedthreads, tables, json, colors]
import vmath
import chroma
import nimsumtree/[rope]
import misc/[custom_logger, util, custom_unicode, custom_async, event, timer, disposable_ref, myjsonutils]
import dispatch_tables, config_provider, events, view, layout, service, platform_service, selector_popup, vfs_service, vfs, theme
import scripting/expose
import platform/[tui, platform]
import finder/[finder, previewer]
import vterm, input, input_api, register, command_service
import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup

from scripting_api import RunInTerminalOptions, CreateTerminalOptions

from std/terminal import Style

const bufferSize = 10 * 1024 * 1024

logCategory "terminal-service"

{.push gcsafe.}
{.push raises: [].}

when defined(windows):
  import winim/lean
  type HPCON* = HANDLE

  const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: DWORD = 131094
  const PIPE_ACCESS_INBOUND = 0x1
  const PIPE_TYPE_BYTE = 0x0
  const PIPE_WAIT = 0x0
  const FILE_FLAG_OVERLAPPED = 0x40000000

  proc CreatePseudoConsole*(size: wincon.COORD, hInput: HANDLE, hOutput: HANDLE, dwFlags: DWORD, phPC: ptr HPCON): HRESULT {.winapi, stdcall, dynlib: "kernel32", importc.}
  proc ClosePseudoConsole*(hPC: HPCON) {.winapi, stdcall, dynlib: "kernel32", importc.}
  proc ResizePseudoConsole*(phPC: HPCON, size: wincon.COORD): HRESULT {.winapi, stdcall, dynlib: "kernel32", importc.}

else:
  import posix/posix except Id
  import posix/termios

  {.passL: "-lutil".}

  proc openpty*(amaster: ptr cint, aslave: ptr cint, name: cstring, termp: ptr Termios, winp: ptr IOctl_WinSize): int {.importc, header: "<pty.h>", sideEffect.}
  proc ptsname*(fd: cint): cstring {.importc, header: "<pty.h>", sideEffect.}
  proc login_tty*(fd: cint): cint {.importc, header: "<utmp.h>", sideEffect.}
  proc eventfd(count: cuint, flags: cint): cint {.cdecl, importc: "eventfd", header: "<sys/eventfd.h>".}

  const platformHeaders = """#include <sys/select.h>
                             #include <sys/time.h>
                             #include <sys/types.h>
                             #include <unistd.h>"""

  var EFD_NONBLOCK {.importc: "EFD_NONBLOCK", header: "<sys/eventfd.h>".}: cint
  var TIOCSWINSZ {.importc: "TIOCSWINSZ", header: "<termios.h>".}: culong

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

when defined(windows):
  proc prepareStartupInformation*(hpc: HPCON): STARTUPINFOEX {.raises: [OSError].} =
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
  ## Input mode to activate when creating a new terminal, if no mode is specified otherwise.
  declare defaultMode, string, ""

  ## Input mode which is always active while a terminal view is active.
  declare baseMode, string, "terminal"

  ## After how many milliseconds of no data received from a terminal it is considered idle, and can be reused
  ## for running more commands.
  declare idleThreshold, int, 500

type
  InputEventKind {.pure.} = enum
    Text
    Key
    MouseMove
    MouseClick
    Scroll
    Size
    Terminate
    RequestRope
    SetColorPalette
    Paste
    EnableLog

  InputEvent = object
    modifiers: Modifiers
    row: int
    col: int
    case kind: InputEventKind
    of InputEventKind.Text, InputEventKind.Paste:
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
    of InputEventKind.SetColorPalette:
      colors: seq[tuple[r, g, b: uint8]]
    of InputEventKind.EnableLog:
      enableLog: bool

  CursorShape* {.pure.} = enum Block, Underline, BarLeft
  OutputEventKind {.pure.} = enum TerminalBuffer, Size, Cursor, CursorVisible, CursorShape, CursorBlink, Terminated, Rope, Scroll, Log
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
    of OutputEventKind.CursorBlink:
      cursorBlink: bool
    of OutputEventKind.CursorShape:
      shape: CursorShape
    of OutputEventKind.Terminated:
      exitCode: Option[int]
    of OutputEventKind.Rope:
      rope: pointer # ptr Rope, but Nim complains about destructors?
    of OutputEventKind.Scroll:
      deltaY: int
      scrollY: int
    of OutputEventKind.Log:
      level: Level
      msg: string

  OsHandles = object
    when defined(windows):
      hpcon: HPCON
      inputWriteHandle: HANDLE
      outputReadHandle: HANDLE
      inputWriteEvent: HANDLE
      outputReadEvent: HANDLE
      processInfo: PROCESS_INFORMATION
      startupInfo: STARTUPINFOEX
    else:
      masterFd: cint
      slaveFd: cint
      inputWriteEventFd: cint
      childPid: Pid

  ThreadState = object
    vterm: ptr VTerm
    screen: ptr VTermScreen
    inputChannel: ptr Channel[InputEvent]
    outputChannel: ptr Channel[OutputEvent]
    width: int
    height: int
    scrollY: int = 0
    cursor: tuple[row, col: int, visible: bool, blink: bool] = (0, 0, true, true)
    scrollbackBuffer: seq[seq[VTermScreenCell]]
    dirty: bool = false # When true send updated terminal buffer to main thread
    terminateRequested: bool = false
    processTerminated: bool = false
    autoRunCommand: string
    enableLog: bool = false

    handles: OsHandles
    when defined(windows):
      outputOverlapped: OVERLAPPED
      waitingForOvelapped: bool

  Terminal* = ref object
    id*: int
    group*: string
    command*: string
    thread: Thread[ThreadState]
    inputChannel: ptr Channel[InputEvent]
    outputChannel: ptr Channel[OutputEvent]
    terminalBuffer*: TerminalBuffer
    cursor*: tuple[row, col: int, visible: bool, shape: CursorShape, blink: bool] = (0, 0, true, CursorShape.Block, true)
    scrollY: int
    exitCode*: Option[int]
    autoRunCommand: string
    threadTerminated: bool = false

    # Events
    lastUpdateTime: timer.Timer
    onTerminated: Event[Option[int]]
    onRope: Event[ptr Rope]
    onUpdated: Event[void]

    handles: OsHandles

  TerminalView* = ref object of View
    terminals*: TerminalService
    eventHandlers: Table[string, EventHandler]
    modeEventHandler: EventHandler
    mode*: string
    size*: tuple[width, height: int]
    terminal*: Terminal
    closeOnTerminate: bool
    slot: string
    open: bool = true

  TerminalService* = ref object of Service
    events: EventHandlerService
    config: ConfigService
    layout*: LayoutService
    themes: ThemeService
    registers: Registers
    commands: CommandService
    idCounter: int = 0
    settings: TerminalSettings

    terminals*: Table[int, TerminalView]
    activeView: TerminalView

proc createTerminalView(self: TerminalService, command: string, options: CreateTerminalOptions, id: Id = idNone()): TerminalView

proc createRope*(state: var ThreadState, scrollback: bool = true): Rope =
  var cell: VTermScreenCell
  var rope = Rope.new()

  var line = ""
  if scrollback:
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
    var prevOverlap = 1
    for col in 0..<state.width:
      dec prevOverlap
      if prevOverlap > 0:
        continue

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
      prevOverlap = cell.width.int

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
    var prevOverlap = 1
    for col in 0..<state.width:
      dec prevOverlap

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

        assert scrollbackIndex < state.scrollbackBuffer.len

        if col >= state.scrollbackBuffer[scrollbackIndex].len:
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
      if prevOverlap > 0:
        c.previousWideGlyph = true

      if cell.attrs.bold != 0: c.style.incl(terminal.Style.styleBlink)
      if cell.attrs.italic != 0: c.style.incl(terminal.Style.styleItalic)
      if cell.attrs.underline != 0: c.style.incl(terminal.Style.styleUnderscore)
      # if cell.attrs.blink != 0: c.style.incl(terminal.Style.styleBlink) # todo
      if cell.attrs.reverse != 0: c.style.incl(terminal.Style.styleReverse)
      if cell.attrs.conceal != 0: c.style.incl(terminal.Style.styleHidden)
      if cell.attrs.strike != 0: c.style.incl(terminal.Style.styleStrikethrough)
      if cell.attrs.dim != 0: c.style.incl(terminal.Style.styleDim)

      if cell.fg.isDefaultFg:
        c.fg = fgNone
        c.fgColor = colors.rgb(0, 0, 0)
      elif cell.fg.isRGB:
        c.fg = fgRGB
        c.fgColor = colors.rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)
      elif cell.fg.isIndexed:
        c.fg = fgRGB
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
        state.screen.convertColorToRgb(cell.bg.addr)
        c.bgColor = colors.rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)

      result[col, scrolledRow] = c
      prevOverlap = cell.width.int

proc handleOutputChannel(self: TerminalService, terminal: Terminal) {.async.} =
  while not terminal.threadTerminated:
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
      of OutputEventKind.CursorBlink:
        terminal.cursor.blink = event.cursorBlink
      of OutputEventKind.CursorShape:
        terminal.cursor.shape = event.shape
      of OutputEventKind.Terminated:
        terminal.exitCode = event.exitCode
        terminal.threadTerminated = true
        terminal.onTerminated.invoke(event.exitCode)
        break
      of OutputEventKind.Rope:
        let rope = cast[ptr Rope](event.rope)
        terminal.onRope.invoke(rope)
      of OutputEventKind.Scroll:
        terminal.scrollY = event.scrollY
      of OutputEventKind.Log:
        log event.level, &"[{terminal.id}][thread] {event.msg}"

      updated = true

    if updated:
      terminal.lastUpdateTime = startTimer()
      terminal.onUpdated.invoke()

    # todo: use async signals
    await sleepAsync(10.milliseconds)

proc handleOutput(s: cstring; len: csize_t; user: pointer) {.cdecl.} =
  if len > 0:
    let state = cast[ptr ThreadState](user)
    when defined(windows):
      var bytesWritten: int32
      if WriteFile(state[].handles.inputWriteHandle, s[0].addr, len.cint, bytesWritten.addr, nil) == 0:
        echo "Failed to write data to shell: ", newOSError(osLastError()).msg
      if bytesWritten.int < len.int:
        echo "--------------------------------------------"
        echo "failed to write all bytes to shell"
    else:
      discard write(state.handles.masterFd, s[0].addr, len.int)

proc handleInputEvents(state: var ThreadState) =
  while state.inputChannel[].peek() > 0:
    try:
      let event = state.inputChannel[].recv()
      case event.kind
      of InputEventKind.Text:
        for r in event.text.runes:
          state.vterm.uniChar(r.uint32, event.modifiers.toVtermModifiers)

      of InputEventKind.Paste:
        state.vterm.startPaste()
        handleOutput(event.text.cstring, event.text.len.csize_t, state.addr)
        state.vterm.endPaste()

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
        let prevScrollY = state.scrollY
        state.scrollY += event.deltaY
        state.scrollY = state.scrollY.clamp(0, state.scrollbackBuffer.len)
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: state.cursor.row + state.scrollY, col: state.cursor.col)
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Scroll, scrollY: state.scrollY, deltaY: state.scrollY - prevScrollY)
        state.dirty = true

      of InputEventKind.Size:
        if event.col != 0 and event.row != 0:
          state.width = event.col
          state.height = event.row
          state.vterm.setSize(state.height.cint, state.width.cint)
          state.screen.flushDamage()

          when defined(windows):
            ResizePseudoConsole(state.handles.hpcon, wincon.COORD(X: state.width.SHORT, Y: state.height.SHORT))
          else:
            var winp: IOctl_WinSize = IOctl_WinSize(ws_row: state.height.cushort, ws_col: state.width.cushort, ws_xpixel: 500.cushort, ws_ypixel: 500.cushort)
            discard termios.ioctl(state.handles.masterFd, TIOCSWINSZ, winp.addr)

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

      of InputEventKind.EnableLog:
        state.enableLog = event.enableLog

    except:
      echo &"Failed to send input: {getCurrentExceptionMsg()}"

proc handleProcessOutput(state: var ThreadState, buffer: var string) {.raises: [OSError].} =
  when defined(windows):
    template handleData(data: untyped, bytesToWrite: int): untyped =
      let written = state.vterm.writeInput(data, bytesToWrite.csize_t).int
      if written != bytesToWrite:
        echo "fix me: vterm.nim.terminalThread vterm.writeInput"
        assert written == bytesToWrite, "fix me: vterm.nim.terminalThread vterm.writeInput"

      state.screen.flushDamage()
      state.dirty = true

    var bytesRead: DWORD = 0
    if state.waitingForOvelapped:
      if GetOverlappedResult(state.handles.outputReadHandle, state.outputOverlapped.addr, bytesRead.addr, 0) != 0:
        state.waitingForOvelapped = false
        handleData(buffer.cstring, bytesRead.int)

      else:
        let error = osLastError()
        case error.int32
        of ERROR_HANDLE_EOF:
          state.waitingForOvelapped = false
          return

        of ERROR_IO_INCOMPLETE:
          state.waitingForOvelapped = true
          return

        else:
          raiseOSError(error)

    buffer.setLen(bufferSize)
    state.outputOverlapped.hEvent = state.handles.outputReadEvent
    if ReadFile(state.handles.outputReadHandle, buffer[0].addr, buffer.len.DWORD, bytesRead.addr, state.outputOverlapped.addr) != 0:
      handleData(buffer.cstring, bytesRead.int)
      state.waitingForOvelapped = false
      return

    let error = osLastError()
    case error.int32
    of ERROR_HANDLE_EOF:
      state.waitingForOvelapped = false
      return

    of ERROR_IO_PENDING:
      state.waitingForOvelapped = true
      return

    else:
      raiseOSError(error)

  else:
    buffer.setLen(bufferSize)
    let n = read(state.handles.masterFd, buffer[0].addr, buffer.len)
    if n > 0:
      let written = state.vterm.writeInput(buffer.cstring, n.csize_t).int
      if written != n:
        echo "fix me: vterm.nim.terminalThread vterm.writeInput"
        assert written == n, "fix me: vterm.nim.terminalThread vterm.writeInput"

      state.screen.flushDamage()
      state.dirty = true
    elif n == 0:
      state.processTerminated = true

proc log(state: ThreadState, str: string) =
  if state.enableLog:
    state.outputChannel[].send OutputEvent(kind: OutputEventKind.Log, level: lvlDebug, msg: str)

proc log(state: ptr ThreadState, str: string) =
  if state.enableLog:
    state[].outputChannel[].send OutputEvent(kind: OutputEventKind.Log, level: lvlDebug, msg: str)

proc terminalThread(s: ThreadState) {.thread, nimcall.} =
  var state = s

  proc log(str: string) =
    if state.enableLog:
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Log, level: lvlDebug, msg: str)

  var callbacks = VTermScreenCallbacks(
    # damage: (proc(rect: VTermRect; user: pointer): cint {.cdecl.} = discard),
    # moverect: (proc(dest: VTermRect; src: VTermRect; user: pointer): cint {.cdecl.} = discard),
    movecursor: (proc(pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      state.cursor.row = pos.row.int
      state.cursor.col = pos.col.int
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: pos.row.int + state.scrollY, col: pos.col.int)
      # state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorVisible, visible: visible != 0)
    ),
    settermprop: (proc(prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      case prop
      of VTERM_PROP_CURSORVISIBLE:
        # log state, &"settermmprop VTERM_PROP_CURSORVISIBLE {val.boolean != 0}"
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorVisible, visible: val.boolean != 0)

      of VTERM_PROP_CURSORBLINK:
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorBlink, cursorBlink: val.boolean != 0)
      # of VTERM_PROP_ALTSCREEN:
        # log state, &"settermmprop VTERM_PROP_ALTSCREEN {val.boolean != 0}"

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
      state.scrollY = 0
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Scroll, scrollY: state.scrollY)
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
  var exitCode = int.none

  try:
    while true:
      when defined(windows):
        var handles = [state.handles.inputWriteEvent, state.handles.outputReadEvent, state.handles.processInfo.hProcess]
        let res = WaitForMultipleObjects(handles.len.DWORD, handles[0].addr, FALSE, INFINITE)
        if res == WAIT_FAILED:
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
              var exitCodeC: DWORD = 0
              discard GetExitCodeProcess(state.handles.processInfo.hProcess, exitCodeC.addr)
              exitCode = exitCodeC.int.some
              state.processTerminated = true
              break

        state.handleProcessOutput(buffer)
        state.handleInputEvents()

      else:
        var fds = [
          TPollfd(fd: state.handles.masterFd, events: POLLIN),
          TPollfd(fd: state.handles.inputWriteEventFd, events: POLLIN),
        ]

        let res = poll(fds[0].addr, fds.len.Tnfds, -1)
        if res < 0:
          break

        proc wifexited(status: cint): cint = {.emit: [result, " = WIFEXITED(", status, ");"].}
        proc wexitstatus(status: cint): cint = {.emit: [result, " = WEXITSTATUS(", status, ");"].}

        var status: cint
        let waitRes = waitpid(state.handles.childPid, status, WNOHANG)
        if waitRes == state.handles.childPid:
          state.processTerminated = true
          var exitCodeC: cint
          if wifexited(status) != 0:
            exitCodeC = wexitstatus(status)
          exitCode = exitCodeC.int.some
          break

        if (fds[0].revents and POLLIN) != 0:
          state.handleProcessOutput(buffer)
          if state.processTerminated:
            var exitCodeC: cint
            if wifexited(status) != 0:
              exitCodeC = wexitstatus(status)
            exitCode = exitCodeC.int.some
            break

        if (fds[1].revents and POLLIN) != 0:
          var b: uint64 = 0
          discard read(state.handles.inputWriteEventFd, b.addr, sizeof(typeof(b)))
          state.handleInputEvents()

      if state.terminateRequested:
        break

      if state.dirty:
        state.dirty = false
        state.outputChannel[].send OutputEvent(
          kind: OutputEventKind.TerminalBuffer,
          buffer: state.createTerminalBuffer())

  except OSError as e:
    log(&"terminal thread raised error: {e.msg}")

  # todo: on windows, could `buffer` still be in use by the overlapped read at this point?
  # If so we need to wait here, or cancel the read if possible.

  log(&"terminal thread done, exit code {exitCode}")
  state.outputChannel[].send OutputEvent(kind: OutputEventKind.Terminated, exitCode: exitCode)

proc sendEvent(self: Terminal, event: InputEvent) =
  if self.threadTerminated:
    return
  self.inputChannel[].send(event)
  when defined(windows):
    discard SetEvent(self.handles.inputWriteEvent)
  else:
    var b: uint64 = 1
    discard write(self.handles.inputWriteEventFd, b.addr, sizeof(typeof(b)))

proc terminate*(self: Terminal) {.async.} =
  log lvlInfo, &"Close terminal '{self.command}'"

  if not self.threadTerminated:
    self.sendEvent(InputEvent(kind: InputEventKind.Terminate))

  when defined(windows):
    ClosePseudoConsole(self.handles.hpcon)
  else:
    discard close(self.handles.masterFd)

  while not self.threadTerminated:
    # todo: use async signals
    await sleepAsync(10.milliseconds)

  when defined(windows):
    CloseHandle(self.handles.inputWriteEvent)
    CloseHandle(self.handles.outputReadEvent)
    CloseHandle(self.handles.inputWriteHandle)
    CloseHandle(self.handles.outputReadHandle)
    HeapFree(GetProcessHeap(), 0, self.handles.startupInfo.lpAttributeList)
  else:
    discard close(self.handles.inputWriteEventFd)

  self.inputChannel[].close()
  self.inputChannel.deallocShared()

  self.outputChannel[].close()
  self.outputChannel.deallocShared()

proc createTerminal*(self: TerminalService, width: int, height: int, command: string, autoRunCommand: string = ""): Terminal {.raises: [OSError, IOError, ResourceExhaustedError].} =
  let id = self.idCounter
  inc self.idCounter

  let command = if command.len > 0:
    command
  else:
    self.config.runtime.get("terminal.shell", "powershell.exe")

  when defined(windows):
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

    let cmd = newWideCString(command)
    if CreateProcessW(nil, cmd, nil, nil, FALSE, EXTENDED_STARTUPINFO_PRESENT, nil, nil, siEx.StartupInfo.addr, pi.addr) == 0:
      raiseOSError(osLastError(), "Failed to start sub process")

    CloseHandle(inputReadHandle)
    CloseHandle(outputWriteHandle)

    let inputWriteEvent = CreateEvent(nil, FALSE, FALSE, nil)
    let outputReadEvent = CreateEvent(sa.addr, FALSE, FALSE, nil)

    let handles = OsHandles(
      hpcon: hPC,
      inputWriteHandle: inputWriteHandle,
      outputReadHandle: outputReadHandle,
      inputWriteEvent: inputWriteEvent,
      outputReadEvent: outputReadEvent,
      processInfo: pi,
      startupInfo: siEx,
    )

  else: # not windows
    var master_fd: cint
    var slave_fd: cint
    var termp: Termios

    # mostly copied from neovim
    termp.c_iflag = Cflag(ICRNL or IXON) # or IUTF8
    termp.c_oflag = Cflag(OPOST or ONLCR or NL0 or BS0 or VT0 or FF0)
    termp.c_cflag = Cflag(CS8 or CREAD)
    termp.c_lflag = Cflag(ISIG or ICANON or IEXTEN or ECHO or ECHOE or ECHOK)
    termp.c_cc[VINTR] = (0x1f and 'C'.int).char
    termp.c_cc[VQUIT] = (0x1f and '\\'.int).char
    termp.c_cc[VERASE] = 0x7f.char
    termp.c_cc[VKILL] = (0x1f and 'U'.int).char
    termp.c_cc[VEOF] = (0x1f and 'D'.int).char
    termp.c_cc[VEOL] = 0.char
    # termp.c_cc[VEOL2] = 0.char
    termp.c_cc[VSTART] = (0x1f and 'Q'.int).char
    termp.c_cc[VSTOP] = (0x1f and 'S'.int).char
    termp.c_cc[VSUSP] = (0x1f and 'Z'.int).char
    # termp.c_cc[VREPRINT] = (0x1f and 'R'.int).char
    # termp.c_cc[VWERASE] = (0x1f and 'W'.int).char
    # termp.c_cc[VLNEXT] = (0x1f and 'V'.int).char
    termp.c_cc[VMIN] = 1.char
    termp.c_cc[VTIME] = 0.char

    var winp: IOctl_WinSize = IOctl_WinSize(ws_row: height.cushort, ws_col: width.cushort)
    if openpty(addr(master_fd), addr(slave_fd), nil, addr(termp), addr(winp)) == -1:
      raise newOSError(osLastError(), "openpty")

    let pid = fork()
    if pid < 0:
      raise newOSError(osLastError(), "fork")

    let inputWriteEventFd = eventfd(0, EFD_NONBLOCK)

    if pid == 0:
      discard login_tty(slave_fd)
      discard execlp("/bin/bash", "bash", nil)
      raise newOSError(osLastError(), "execlp")

    let handles = OsHandles(
      masterFd: master_fd,
      slaveFd: slave_fd,
      inputWriteEventFd: inputWriteEventFd,
      childPid: pid,
    )

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
    autoRunCommand: autoRunCommand,
    handles: handles,
  )

  proc createChannel[T](channel: var ptr[Channel[T]]) =
    channel = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
    channel[].open()

  result.inputChannel.createChannel()
  result.outputChannel.createChannel()

  result.terminalBuffer.initTerminalBuffer(width, height)
  asyncSpawn self.handleOutputChannel(result)

  var threadState = ThreadState(
    vterm: vterm,
    screen: screen,
    inputChannel: result.inputChannel,
    outputChannel: result.outputChannel,
    width: width,
    height: height,
    cursor: (0, 0, true, true),
    autoRunCommand: autoRunCommand,
    handles: handles,
  )

  result.thread.createThread(terminalThread, threadState)

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[string]
proc handleInput(self: TerminalService, view: TerminalView, text: string)
proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers)

method close*(self: TerminalView) =
  if not self.open:
    return
  self.open = false
  self.terminals.terminals.del(self.terminal.id)
  asyncSpawn self.terminal.terminate()

method activate*(self: TerminalView) =
  if self.active:
    return
  self.active = true
  self.markDirty()

method deactivate*(self: TerminalView) =
  if not self.active:
    return
  self.active = false
  self.markDirty()

template withActiveView*(self: TerminalService, view: TerminalView, body: untyped): untyped =
  block:
    let prev = self.activeView
    defer:
      self.activeView = prev
    self.activeView = view
    body

proc getEventHandler(self: TerminalView, context: string): EventHandler =
  if context notin self.eventHandlers:
    var eventHandler: EventHandler
    assignEventHandler(eventHandler, self.terminals.events.getEventHandlerConfig(context)):
      onAction:
          if self.terminals.handleAction(self, action, arg).isSome:
            Handled
          else:
            Ignored

      onInput:
        self.terminals.handleInput(self, input)
        Handled

      onKey:
        self.terminals.handleKey(self, input, mods)
        Handled

    self.eventHandlers[context] = eventHandler
    return eventHandler

  return self.eventHandlers[context]

method getEventHandlers*(self: TerminalView, inject: Table[string, EventHandler]): seq[EventHandler] =
  result = @[self.getEventHandler(self.terminals.settings.baseMode.get())]
  if self.modeEventHandler != nil:
    result.add self.modeEventHandler

method desc*(self: TerminalView): string = &"TerminalView"
method kind*(self: TerminalView): string = "terminal"
method display*(self: TerminalView): string = &"term://{self.terminal.command} - {self.terminal.group}"
method saveState*(self: TerminalView): JsonNode =
  result = newJObject()
  result["kind"] = self.kind.toJson
  result["id"] = self.id.toJson
  result["command"] = self.terminal.command.toJson
  result["options"] = CreateTerminalOptions(
    group: self.terminal.group,
    autoRunCommand: self.terminal.autoRunCommand,
    mode: "".some,
    closeOnTerminate: self.closeOnTerminate,
    slot: self.slot,
    focus: false,
  ).toJson

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
  self.registers = self.services.getService(Registers).get
  self.commands = self.services.getService(CommandService).get
  discard self.themes.onThemeChanged.subscribe proc(theme: Theme) = self.handleThemeChanged(theme)

  self.settings = TerminalSettings.new(self.config.runtime)

  self.layout.addViewFactory "terminal", proc(config: JsonNode): View {.raises: [ValueError].} =
    type Config = object
      id: Id
      command: string
      options: CreateTerminalOptions
    var config = config.jsonTo(Config, Joptions(allowExtraKeys: true, allowMissingKeys: true))
    config.options.mode = self.settings.defaultMode.get().some
    return self.createTerminalView(config.command, config.options, id = config.id)

  return ok()

method deinit*(self: TerminalService) =
  for term in self.terminals.values:
    term.close()

proc requestRender(self: TerminalService) =
  self.services.getService(PlatformService).get.platform.requestRender()

proc handleInput(self: TerminalService, view: TerminalView, text: string) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Text, text: text))

proc handlePaste(self: TerminalService, view: TerminalView, text: string) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Paste, text: text))

proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Key, input: input, modifiers: modifiers))

proc handleScroll*(view: TerminalView, deltaY: int, modifiers: Modifiers) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Scroll, deltaY: deltaY, modifiers: modifiers))

proc handleClick*(view: TerminalView, button: input.MouseButton, pressed: bool, modifiers: Modifiers, col: int, row: int) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.MouseClick, button: button, pressed: pressed, row: row, col: col, modifiers: modifiers))

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

proc createTerminalView(self: TerminalService, command: string, options: CreateTerminalOptions, id: Id = idNone()): TerminalView =
  try:
    let term = self.createTerminal(80, 50, command, options.autoRunCommand)
    term.group = options.group
    term.setTheme(self.themes.theme)

    let view = TerminalView(
      mId: id,
      terminals: self,
      terminal: term,
      closeOnTerminate: options.closeOnTerminate,
      slot: options.slot,
    )

    if options.mode.getSome(mode):
      view.mode = mode
    else:
      view.mode = self.settings.defaultMode.get()
    self.updateModeEventHandlers(view)

    discard term.onUpdated.subscribe proc() =
      self.services.getService(PlatformService).get.platform.requestRender()
      view.markDirty()

    discard term.onTerminated.subscribe proc(exitCode: Option[int]) =
      if not view.open:
        return
      log lvlInfo, &"Terminal process '{command}' terminated with exit code {exitCode}"
      view.mode = self.settings.defaultMode.get()
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

proc pasteAsync*(self: TerminalService, view: TerminalView, registerName: string): Future[void] {.async.} =
  log lvlInfo, fmt"paste register from '{registerName}'"

  var register: Register
  if not self.registers.getRegisterAsync(registerName, register.addr).await:
    return

  case register.kind
  of RegisterKind.Text:
    self.handlePaste(view, register.text)
  of RegisterKind.Rope:
    self.handlePaste(view, $register.rope) # todo: send the rope to the terminal thread instead of converting to string

proc setTerminalMode*(self: TerminalService, mode: string) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    view.setMode(mode)

proc escape*(self: TerminalService) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    view.setMode(self.settings.defaultMode.get())

proc createTerminal*(self: TerminalService, command: string = "", options: CreateTerminalOptions = CreateTerminalOptions()) {.expose("terminal").} =
  ## Opens a new terminal by running `command`.
  ## `command`                   Program name and arguments for the process. Usually a shell.
  ## `options.group`             An arbitrary string used to control reusing of terminals and is displayed on screen.
  ##                             Can be used to for example have a `scratch` group and a `build` group.
  ##                             The `build` group would be used for running build commands, the `scratch` group for
  ##                             random other tasks.
  ## `options.autoRunCommand`    Command to execute in the shell. This is passed to `command` through stdin,
  ##                             as if typed with the keyboard.
  ## `options.closeOnTerminate`  Close the terminal view automatically as soon as the connected process terminates.
  ## `options.mode`              Mode to set for the terminal view. Usually something like  "normal", "insert" or "".
  ## `options.slot`              Where to open the terminal view. Uses `default` slot if not specified.
  ## `options.focus`             Whether to focus the terminal view. `true` by default.
  log lvlInfo, &"createTerminal '{command}', {options}"
  self.layout.addView(self.createTerminalView(command, options), slot=options.slot, focus=options.focus)

proc isIdle(self: TerminalService, terminal: Terminal): bool =
  if not terminal.cursor.visible or terminal.cursor.col == 0:
    # Assuming that a shell never has an empty prompt and the cursor is visible when in the prompt
    return false
  let idleThreshold = self.settings.idleThreshold.get()
  return terminal.lastUpdateTime.elapsed.ms.int > idleThreshold

proc runInTerminal*(self: TerminalService, shell: string, command: string, options: RunInTerminalOptions = RunInTerminalOptions()) {.expose("terminal").} =
  ## Run the given `command` in a terminal with the specified shell.
  ## `command` is executed in the shell by sending it as if typed using the keyboard, followed by `<ENTER>`.
  ## `shell`                     Name of the shell. If you pass e.g. `wsl` to this function then the shell which gets
  ##                             executed is configured in `editor.shells.wsl.command`.
  ## `options.reuseExisting`     Run the command in an existing terminal if one exists. If not a new one is created.
  ##                             An existing terminal is only used when it has a matching `group` and `shell`, and
  ##                             it is not busy running another command (detecting this is sometimes wrong).
  ## `options.group`             An arbitrary string used to control reusing of terminals and is displayed on screen.
  ##                             Can be used to for example have a `scratch` group and a `build` group.
  ##                             The `build` group would be used for running build commands, the `scratch` group for
  ##                             random other tasks.
  ## `options.closeOnTerminate`  Close the terminal view automatically as soon as the connected process terminates.
  ## `options.mode`              Mode to set for the terminal view. Usually something like  "normal", "insert" or "".
  ## `options.slot`              Where to open the terminal view. Uses `default` slot if not specified.
  ## `options.focus`             Whether to focus the terminal view. `true` by default.
  let shellCommand = self.config.runtime.get("editor.shells." & shell & ".command", string.none)
  if shellCommand.isNone:
    log lvlError, &"Failed to run command in shell '{shell}': Unknown shell, configure in 'editor.shells.{shell}'"
    return
  if shellCommand.get == "":
    log lvlError, &"Failed to run command in shell '{shell}': Invalid configuration, empty 'editor.shells.{shell}.command'"
    return

  log lvlInfo, &"runInTerminal '{shell}', '{command}', {options}"
  if options.reuseExisting:
    for view in self.terminals.values:
      if view.terminal.group == options.group and view.terminal.command == shellCommand.get and self.isIdle(view.terminal):
        if command.len > 0:
          self.handleInput(view, command)
          self.handleKey(view, INPUT_ENTER, {})
        view.handleScroll(-5000000, {})
        if options.mode.isSome:
          view.setMode(options.mode.get)
        self.layout.showView(view, slot = options.slot, focus = options.focus)
        return

  let view = self.createTerminalView(shellCommand.get, CreateTerminalOptions(
    group: options.group,
    autoRunCommand: options.autoRunCommand,
    mode: options.mode,
    closeOnTerminate: options.closeOnTerminate,
    slot: options.slot,
    focus: options.focus,
  ))
  if command.len > 0:
    self.handleInput(view, command)
    self.handleKey(view, INPUT_ENTER, {})
  self.layout.addView(view, slot=options.slot, focus=options.focus)

proc scrollTerminal*(self: TerminalService, amount: int) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    view.handleScroll(amount, {})

proc pasteTerminal*(self: TerminalService, register: string = "") {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    asyncSpawn self.pasteAsync(view, register)

proc enableTerminalDebugLog*(self: TerminalService, enable: bool) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    view.terminal.sendEvent(InputEvent(kind: InputEventKind.EnableLog, enableLog: enable))

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
    # todo: use async signals
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

proc selectTerminal*(self: TerminalService, preview: bool = true, scaleX: float = 0.9, scaleY: float = 0.9, previewScale: float = 0.6) {.expose("terminal").} =
  defer:
    self.requestRender()

  proc getItems(): seq[FinderItem] {.gcsafe, raises: [].} =
    let allViews = self.layout.getHiddenViews()
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
          details: @[view.terminal.exitCode.mapIt("-> " & $it).get(""), view.terminal.group, $view.terminal.id],
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
      self.layout.showView(view, view.slot)
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

proc handleActionInternal(self: TerminalService, view: TerminalView, action: string, args: JsonNode): Option[string] =
  # if self.plugins.invokeAnyCallback(action, args).isNotNil:
  #   return Handled

  try:
    if dispatch(action, args).getSome(res):
      return ($res).some
  except:
    let argsText = if args.isNil: "nil" else: $args
    log(lvlError, fmt"Failed to dispatch command '{action} {argsText}': {getCurrentExceptionMsg()}")
    return string.none

  log lvlError, fmt"Unknown command '{action}'"
  return string.none

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[string] =
  # debugf"handleAction '{action} {arg}'"
  self.withActiveView(view):
    let res = self.commands.executeCommand(action & " " & arg)
    if res.isSome:
      return res

    try:
      var args = newJArray()
      try:
        for a in newStringStream(arg).parseJsonFragments():
          args.add a

        return self.handleActionInternal(view, action, args)
      except CatchableError:
        log(lvlError, fmt"handleCommmand: {action}, Failed to parse args: '{arg}'")
        return string.none
    except:
      discard

  return string.none
