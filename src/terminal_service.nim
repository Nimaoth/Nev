import std/[os, streams, strutils, sequtils, strformat, typedthreads, tables, json, colors, hashes, base64, algorithm, sets, macros, bitops, deques]
import vmath
import chroma, pixie, pixie/fileformats/png
import nimsumtree/[rope, arc]
import misc/[custom_logger, util, custom_unicode, custom_async, event, timer, disposable_ref, myjsonutils, render_command, embed_source, async_process]
import dispatch_tables, config_provider, events, view, layout, service, platform_service, selector_popup, vfs_service, vfs, theme
import scripting/expose
import platform/[tui, platform]
import finder/[finder, previewer]
import vterm, input, input_api, register, command_service, channel
import scripting_api as api except DocumentEditor, TextDocumentEditor, AstDocumentEditor, ModelDocumentEditor, Popup, SelectorPopup
import compilation_config

when defined(enableLibssh):
  static:
    hint("Build with libssh2")
  import libssh2, ssh

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

  # From a random commit on windows terminal:
  # https://github.com/microsoft/terminal/pull/11264/files#diff-ce403215b7defc6a499585a9cc996313c135c647ceffec2bdecfbbb2f29ff537
  const PSEUDOCONSOLE_RESIZE_QUIRK = 2
  const PSEUDOCONSOLE_WIN32_INPUT_MODE = 4
  const PSEUDOCONSOLE_PASSTHROUGH_MODE = 8

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
  of input.MouseButton.Middle: return 2
  of input.MouseButton.Right: return 3
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
    noKitty: bool
    case kind: InputEventKind
    of InputEventKind.Text, InputEventKind.Paste:
      text: string
    of InputEventKind.Key:
      input: int64
      action: InputAction

    of InputEventKind.MouseMove:
      discard
    of InputEventKind.MouseClick:
      button: input.MouseButton
      pressed: bool
    of InputEventKind.Scroll:
      deltaY: int
    of InputEventKind.Size:
      # also use row, col
      cellPixelWidth: int
      cellPixelHeight: int
    of InputEventKind.Terminate:
      discard
    of InputEventKind.RequestRope:
      rope: pointer # ptr Rope, but Nim complains about destructors?
    of InputEventKind.SetColorPalette:
      colors: seq[tuple[r, g, b: uint8]]
    of InputEventKind.EnableLog:
      enableLog: bool

  Sixel* = object
    colors*: seq[chroma.Color]
    width*: int
    height*: int
    px*: int
    py*: int
    pos*: tuple[line, column: int]
    contentHash*: Hash

  PlacedImage* = object
    sx*, sy*, sw*, sh*: int
    cx*, cy*, cw*, ch*: int
    z*: int
    offsetX*: int
    offsetY*: int
    effectiveNumRows*: int
    effectiveNumCols*: int
    imageId*: int
    textureId*: TextureId

  CursorShape* {.pure.} = enum Block, Underline, BarLeft
  OutputEventKind {.pure.} = enum TerminalBuffer, Size, Cursor, CursorVisible, CursorShape, CursorBlink, Terminated, Rope, Scroll, Log
  OutputEvent = object
    case kind: OutputEventKind
    of OutputEventKind.TerminalBuffer:
      buffer: TerminalBuffer
      sixels: Table[(int, int), Sixel]
      placements*: seq[PlacedImage]
    of OutputEventKind.Size:
      width: int
      height: int
      pixelWidth: int
      pixelHeight: int
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
    inputEventSignal: ThreadSignalPtr # used to signal input events when using channels. todo: use for native terminal aswell
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

  SixelState = object
    active: bool
    colors: seq[chroma.Color]
    palette: array[256, chroma.Color] = default(array[256, chroma.Color])
    i: int =  0
    x: int =  0
    y: int =  0
    width: int = 0
    height: int = 0
    sizeFixed: bool  = false
    px: int = 0
    py: int = 0
    currentColor: int = 1
    iter: iterator(s: ptr TerminalThreadState): int {.gcsafe, raises: [].}
    frag: VTermStringFragment
    pos*: tuple[line, column: int]

  KittyState = object
    active: bool
    colors: seq[chroma.Color]
    iter: iterator(s: ptr TerminalThreadState) {.gcsafe, raises: [].}
    frag: VTermStringFragment
    pos*: tuple[line, column: int]
    pathPrefix: string
    images*: Table[int, tuple[width, height: int, textureId: TextureId]]
    placements*: Table[(int, int), PlacedImage]

  KittyKeyboardState = enum
    DisambiguateEscapeCodes
    ReportEventTypes
    ReportAlternateKeys
    ReportAllKeysAsEscapeCodes
    ReportAssociatedText

  TerminalThreadState = object
    vtermInternal: pointer
    screenInternal: pointer
    inputChannel: ptr system.Channel[InputEvent]
    outputChannel: ptr system.Channel[OutputEvent]
    useChannels: bool
    readChannel: Arc[BaseChannel]
    writeChannel: Arc[BaseChannel]
    width: int
    height: int
    cellPixelWidth: int
    cellPixelHeight: int
    pixelWidth: int
    pixelHeight: int
    scrollY: int = 0
    cursor: tuple[row, col: int, visible: bool, blink: bool] = (0, 0, true, true)
    scrollbackBuffer: Deque[seq[VTermScreenCell]]
    scrollbackLines: int
    dirty: bool = false # When true send updated terminal buffer to main thread
    terminateRequested: bool = false
    processTerminated: bool = false
    autoRunCommand: string
    enableLog: bool = false
    sixel: SixelState
    kitty: KittyState
    sixels: Table[(int, int), Sixel]
    alternateScreen: bool
    kittyKeyboardMain: seq[set[KittyKeyboardState]]
    kittyKeyboardAlternate: seq[set[KittyKeyboardState]]
    outputBuffer: string
    handles: OsHandles
    sizeRequested: bool # Whether the size was requested use CSI 14/15/16/18 t
    processStdoutBuffer: string
    when defined(windows):
      outputOverlapped: OVERLAPPED
      waitingForOvelapped: bool

  Terminal* = ref object
    id*: int
    group*: string
    command*: string
    thread: Thread[TerminalThreadState]
    inputChannel: ptr system.Channel[InputEvent]
    outputChannel: ptr system.Channel[OutputEvent]
    terminalBuffer*: TerminalBuffer # The latest terminalBuffer received from the terminal thread
    sixels*: seq[tuple[contentHash: Hash, row, col: int, px, py: int, width, height: int]]
    images*: seq[PlacedImage]
    cursor*: tuple[row, col: int, visible: bool, shape: CursorShape, blink: bool] = (0, 0, true, CursorShape.Block, true)
    width*: int # The latest width received from the terminal thread. Might not match 'terminalBuffer' size.
    height*: int # The latest height received from the terminal thread. Might not match 'terminalBuffer' size.
    pixelWidth*: int # The latest pixel width received from the terminal thread. Might not match current view size.
    pixelHeight*: int # The latest pixel height received from the terminal thread. Might not match current view size.
    scrollY: int
    exitCode*: Option[int]
    autoRunCommand: string
    createPty: bool = false
    kittyPathPrefix: string
    threadTerminated: bool = false

    # Events
    lastUpdateTime: timer.Timer
    lastEventTime: timer.Timer
    onTerminated: Event[Option[int]]
    onRope: Event[ptr Rope]
    onUpdated: Event[void]

    useChannels: bool
    handles: OsHandles

    ssh*: Option[SshOptions]
    when defined(enableLibssh):
      sshChannel: SSHChannel
      sshClient: SSHClient

  TerminalView* = ref object of View
    terminals*: TerminalService
    eventHandlers: Table[string, EventHandler]
    modeEventHandler: EventHandler
    mode*: string
    size*: tuple[width, height, cellPixelWidth, cellPixelHeight: int] # Current size of the view in cells. Might not match 'terminal.width' and 'terminal.height'
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
    mPlatform: Platform

    terminals*: Table[int, TerminalView]
    activeView: TerminalView
    sixelTextures*: Table[Hash, TextureId]

proc createTerminalView(self: TerminalService, command: string, options: CreateTerminalOptions, id: Id = idNone()): TerminalView

proc vterm(state: TerminalThreadState): ptr VTerm = cast[ptr VTerm](state.vtermInternal)
proc screen(state: TerminalThreadState): ptr VTermScreen = cast[ptr VTermScreen](state.screenInternal)

proc platform(self: TerminalService): Platform =
  if self.mPlatform == nil:
    self.mPlatform = self.services.getService(PlatformService).get.platform
  return self.mPlatform

proc createRope*(state: var TerminalThreadState, scrollback: bool = true): Rope =
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

proc createTerminalBuffer*(state: var TerminalThreadState): TerminalBuffer =
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

proc createTexture(self: TerminalService, sixel: sink Sixel) =
  try:
    # debugf"cache sixel {sixel.contentHash} {sixel.width}x{sixel.height}"
    var colors = newSeq[chroma.Color]()
    swap(colors, sixel.colors)
    let textureId = createTexture(sixel.width, sixel.height, colors.ensureMove)
    self.sixelTextures[sixel.contentHash] = textureId
  except PixieError as e:
    log lvlError, &"Failed to create image for sixel: {e.msg}"

proc cleanupUnusedSixels(self: TerminalService) {.async.} =
  while true:
    var unusedSixels = self.sixelTextures
    for view in self.terminals.values:
      for s in view.terminal.sixels:
        unusedSixels.del(s.contentHash)

    for key, id in unusedSixels:
      # debugf"delete unused sixel {key}, {id.int}"
      deleteTexture(id)
      self.sixelTextures.del(key)

    catch sleepAsync(1000.milliseconds).await:
      discard

proc handleBufferOutputEvent(self: TerminalService, terminal: Terminal, event: var OutputEvent) =
  # Swap to avoid expensive copies, and because ensureMove doesn't work for fields
  swap terminal.terminalBuffer, event.buffer
  terminal.sixels.setLen(0)
  for pos, s in event.sixels.mpairs:
    let h = s.contentHash
    terminal.sixels.add (h, pos[0], pos[1], s.px, s.py, s.width, s.height)
    if h notin self.sixelTextures:
      var temp = Sixel()
      swap(temp, s)
      self.createTexture(temp.ensureMove)
  swap(terminal.images, event.placements)

proc handleOutputChannel(self: TerminalService, terminal: Terminal) {.async.} =
  while not terminal.threadTerminated:
    var updated = false
    while terminal.outputChannel[].peek() > 0:
      var event = terminal.outputChannel[].recv()
      case event.kind
      of OutputEventKind.TerminalBuffer:
        # debugf"time since last input: {terminal.lastEventTime.elapsed.ms}"
        self.handleBufferOutputEvent(terminal, event)
      of OutputEventKind.Size:
        terminal.width = event.width
        terminal.height = event.height
        terminal.pixelWidth = event.pixelWidth
        terminal.pixelHeight = event.pixelHeight

        when defined(enableLibssh):
          if terminal.ssh.isSome:
            sshAsyncWait "update terminal size":
              terminal.sshChannel.impl.channel_request_pty_size_ex(event.width, event.height, event.pixelWidth, event.pixelHeight)
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
    let state = cast[ptr TerminalThreadState](user)
    # echo "send input ", s.toOpenArray(0, len.int - 1)
    if state.useChannels:
      discard
      try:
        state.writeChannel.write(s.toOpenArray(0, len.int - 1))
      except IOError as e:
        echo "Failed to write data to channel: ", e.msg
    else:
      when defined(windows):
        var bytesWritten: int32
        if WriteFile(state[].handles.inputWriteHandle, s[0].addr, len.cint, bytesWritten.addr, nil) == 0:
          echo "Failed to write data to shell: ", newOSError(osLastError()).msg
        if bytesWritten.int < len.int:
          echo "--------------------------------------------"
          echo "failed to write all bytes to shell"
      else:
        discard write(state.handles.masterFd, s[0].addr, len.int)

proc flushOutput(s: var TerminalThreadState) =
  if s.outputBuffer.len > 0:
    handleOutput(cast[cstring](s.outputBuffer[0].addr), s.outputBuffer.len.csize_t, s.addr)
    s.outputBuffer.setLen(0)

proc sendOutput(s: var TerminalThreadState, raw: openArray[char]) =
  if raw.len == 0:
    return
  if s.outputBuffer.len > 0:
    handleOutput(cast[cstring](s.outputBuffer[0].addr), s.outputBuffer.len.csize_t, s.addr)
    s.outputBuffer.setLen(0)

  handleOutput(cast[cstring](raw[0].addr), raw.len.csize_t, s.addr)

proc sendOutput(s: ptr TerminalThreadState, raw: openArray[char]) =
  s[].sendOutput(raw)

proc sendOutputBuffered(s: var TerminalThreadState, raw: openArray[char]) =
  if raw.len == 0:
    return
  let oldLen = s.outputBuffer.len
  s.outputBuffer.setLen(oldLen + raw.len)
  copyMem(s.outputBuffer[oldLen].addr, raw[0].addr, raw.len)

proc kittyKeyboardFlags(state: var TerminalThreadState): set[KittyKeyboardState] =
  if state.alternateScreen:
    if state.kittyKeyboardAlternate.len > 0:
      return state.kittyKeyboardAlternate.last
    return {}
  else:
    if state.kittyKeyboardMain.len > 0:
      return state.kittyKeyboardMain.last
    return {}

type
  KittyEncodingData = object
    key: uint32
    shiftedKey: uint32
    alternateKey: uint32
    addAlternates: bool
    hasMods: bool
    addActions: bool
    addText: bool
    encodedMods: string
    text: string
    action: InputAction

proc inputToKittyKey(input: int): (uint32, char) =
  case input
  of INPUT_ENTER: (13, 'u')
  of INPUT_ESCAPE: (27, 'u')
  of INPUT_BACKSPACE: (127, 'u')
  of INPUT_SPACE: (' '.uint32, 'u')
  of INPUT_DELETE: (3, '~')
  of INPUT_TAB: (9, 'u')
  of INPUT_LEFT: (1, 'D')
  of INPUT_RIGHT: (1, 'C')
  of INPUT_UP: (1, 'A')
  of INPUT_DOWN: (1, 'B')
  of INPUT_HOME: (1, 'H')
  of INPUT_END: (1, 'F')
  of INPUT_PAGE_UP: (5, '~')
  of INPUT_PAGE_DOWN: (6, '~')
  of INPUT_F1: (1, 'P')
  of INPUT_F2: (1, 'Q')
  of INPUT_F3: (13, '~')
  of INPUT_F4: (1, 'S')
  of INPUT_F5: (15, '~')
  of INPUT_F6: (17, '~')
  of INPUT_F7: (18, '~')
  of INPUT_F8: (19, '~')
  of INPUT_F9: (20, '~')
  of INPUT_F10: (21, '~')
  of INPUT_F11: (23, '~')
  of INPUT_F12: (24, '~')
  else:
    (input.uint32, 'u')

proc serialize(state: var TerminalThreadState, data: KittyEncodingData, csiTrailer: char) =
  # echo &"serialize {data}"
  var buffer = "\e["
  let secondUsed = data.hasMods or data.addActions
  let thirdUsed = data.addText

  if data.key != 1 or data.addAlternates or secondUsed or thirdUsed:
    buffer.add $data.key

  if data.addAlternates:
    buffer.add ":"
    if data.shiftedKey != 0:
      buffer.add $data.shiftedKey
    if data.alternateKey != 0:
      buffer.add ":"
      buffer.add $data.alternateKey

  if secondUsed or thirdUsed:
    buffer.add ";"
    if secondUsed:
      buffer.add data.encodedMods
    if data.addActions:
      buffer.add ":"
      buffer.add $(data.action.int + 1)

  if thirdUsed:
    for i, r in data.text:
      if i == 0:
        buffer.add ";"
      else:
        buffer.add ":"

      buffer.add $r.int

  buffer.add csiTrailer
  state.sendOutputBuffered(buffer)

proc encodeLegacyFunctionalKeyWithMods(state: var TerminalThreadState, event: InputEvent): bool =
  var prefix = ""
  if Alt in event.modifiers:
    prefix = "\x1b"
  case event.input
  of INPUT_ENTER:
    state.sendOutputBuffered(prefix)
    state.sendOutputBuffered("\x0d")
    return true
  of INPUT_ESCAPE:
    state.sendOutputBuffered(prefix)
    state.sendOutputBuffered("\x1b")
    return true
  of INPUT_BACKSPACE:
    state.sendOutputBuffered(prefix)
    if Control in event.modifiers:
      state.sendOutputBuffered("\x08")
    else:
      state.sendOutputBuffered("\x7f")
    return true
  of INPUT_TAB:
    if Shift in event.modifiers:
      if Alt in event.modifiers:
        state.sendOutputBuffered("\x1b")
      state.sendOutputBuffered("\x1b[Z")
    else:
      state.sendOutputBuffered(prefix)
      state.sendOutputBuffered("\t")
    return true
  else:
    return false

proc encodeKittyKey(state: var TerminalThreadState, event: InputEvent) =
  let kittyKeyboardFlags = state.kittyKeyboardFlags
  let reportText = ReportAllKeysAsEscapeCodes in kittyKeyboardFlags
  let sendTextStandalone = not reportText

  var input = event.input
  var modifiers = event.modifiers
  let text = if event.input > 0:
    if modifiers == {} and event.input.Rune.isUpper:
      input = event.input.Rune.toLower.int
      modifiers.incl Shift
      $event.input.Rune
    elif modifiers == {}:
      $event.input.Rune
    elif modifiers == {Shift} and event.input.Rune.isUpper:
      input = event.input.Rune.toLower.int
      $event.input.Rune
    elif modifiers == {Shift}:
      $event.input.Rune
    else:
      ""
  else:
    if modifiers == {}:
      case event.input
      of INPUT_TAB:
        "\t"
      of INPUT_SPACE:
        " "
      of INPUT_BACKSPACE:
        "\x7f"
      of INPUT_ENTER:
        "\r"
      else:
        ""
    else:
      ""

  # echo &"encodeKittyKey text: '{text}', "
  if sendTextStandalone and text.len > 0 and event.action in {InputAction.Press, Repeat}:
    # echo &"sendTextStandalone '{text}'"
    state.sendOutputBuffered(text)
    return

  var (key, csiSuffix) = inputToKittyKey(event.input)
  var shiftedKey = event.input.uint32
  var alternateKey = 0.uint32
  if event.input > 0 and event.input.Rune.isUpper:
    shiftedKey = event.input.uint32
    key = event.input.Rune.toLower.uint32

  var data = KittyEncodingData(
    key: key,
    addActions: ReportEventTypes in kittyKeyboardFlags and event.action != Press,
    hasMods: modifiers != {},
    addAlternates: ReportAlternateKeys in kittyKeyboardFlags and ((Shift in modifiers) and shiftedKey > 0 or alternateKey > 0), # ...,
    addText: ReportAssociatedText in kittyKeyboardFlags and text.len > 0,
    text: text,
    action: Press,
  )
  if data.addAlternates:
    if Shift in modifiers:
      data.shiftedKey = shiftedKey
    data.alternateKey = alternateKey
  var mods = 0
  if Shift in modifiers:
    mods = mods or 0x1
  if Alt in modifiers:
    mods = mods or 0x2
  if Control in modifiers:
    mods = mods or 0x4
  if Super in modifiers:
    mods = mods or 0x8

  data.encodedMods = $(mods + 1)
  let simpleEncodingOk = not data.addActions and not data.addAlternates and not data.addText
  # todo
  # if simpleEncodingOk:
  #   if not data.hasMods:
  #     state.vterm.uniChar(' '.uint32, modifiers.toVtermModifiers)
  #   else:
  #     state.serialize(data, csiSuffix)
  # else:
  state.serialize(data, csiSuffix)

proc handleInputEvents(state: var TerminalThreadState) =
  while state.inputChannel[].peek() > 0:
    try:
      let event = state.inputChannel[].recv()
      case event.kind
      of InputEventKind.Text:
        let kittyKeyboardFlags = state.kittyKeyboardFlags
        if kittyKeyboardFlags == {} or event.noKitty:
          for r in event.text.runes:
            state.vterm.uniChar(r.uint32, event.modifiers.toVtermModifiers)
        else:
          for r in event.text.runes:
            state.encodeKittyKey(InputEvent(kind: InputEventKind.Key, modifiers: event.modifiers, input: r.int64, action: Press))
          state.flushOutput()

      of InputEventKind.Paste:
        state.vterm.startPaste()
        handleOutput(event.text.cstring, event.text.len.csize_t, state.addr)
        state.vterm.endPaste()

      of InputEventKind.Key:
        let kittyKeyboardFlags = state.kittyKeyboardFlags
        if kittyKeyboardFlags == {} or event.noKitty:
          if event.input > 0:
            state.vterm.uniChar(event.input.uint32, event.modifiers.toVtermModifiers)
          elif event.input < 0:
            case event.input
            of INPUT_SPACE:
              state.vterm.uniChar(' '.uint32, event.modifiers.toVtermModifiers)
            else:
              state.vterm.key(event.input.inputToVtermKey, event.modifiers.toVtermModifiers)
        else:
          state.encodeKittyKey(event)
          state.flushOutput()

      of InputEventKind.MouseMove:
        state.vterm.mouseMove(event.row.cint, event.col.cint, event.modifiers.toVtermModifiers)

      of InputEventKind.MouseClick:
        if event.button in {input.MouseButton.Left, input.MouseButton.Middle, input.MouseButton.Right}: # todo: other buttons. DoubleClick would currently be interpreted as scroll
          state.vterm.mouseButton(event.button.toVtermButton, event.pressed, event.modifiers.toVtermModifiers)

      of InputEventKind.Scroll:
        let mouseFlags = state.vterm.getMouseFlags().int
        if mouseFlags != 0 or state.alternateScreen:
          if event.deltaY > 0:
            state.vterm.mouseButton(4, true, event.modifiers.toVtermModifiers)
          else:
            state.vterm.mouseButton(5, true, event.modifiers.toVtermModifiers)

        if mouseFlags == 0 and not state.alternateScreen:
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
          state.cellPixelWidth = event.cellPixelWidth
          state.cellPixelHeight = event.cellPixelHeight
          state.pixelWidth = event.cellPixelWidth * state.width
          state.pixelHeight = event.cellPixelHeight * state.height
          state.vterm.setSize(state.height.cint, state.width.cint)
          state.screen.flushDamage()

          if state.sizeRequested:
            state.sendOutput(&"\e[8;{state.height};{state.width}t")
            state.sendOutput(&"\e[5;{state.cellPixelHeight};{state.cellPixelWidth}t")

          if not state.useChannels:
            when defined(windows):
              ResizePseudoConsole(state.handles.hpcon, wincon.COORD(X: state.width.SHORT, Y: state.height.SHORT))
            else:
              var winp: IOctl_WinSize = IOctl_WinSize(ws_row: state.height.cushort, ws_col: state.width.cushort, ws_xpixel: 500.cushort, ws_ypixel: 500.cushort)
              discard termios.ioctl(state.handles.masterFd, TIOCSWINSZ, winp.addr)
          else:
            let msg = ""
            handleOutput(msg.cstring, msg.len.csize_t, state.addr)

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

proc handleProcessOutput(state: var TerminalThreadState, buffer: var string) {.raises: [OSError].} =
  if state.useChannels:
    try:
      buffer.setLen(state.readChannel.flushRead())
      if buffer.len > 0:
        let read = state.readChannel.read(cast[ptr UncheckedArray[uint8]](buffer[0].addr).toOpenArray(0, buffer.high))
        buffer.setLen(read)

        # echo buffer.toOpenArray(0, read.int - 1)
        let written = state.vterm.writeInput(buffer.cstring, read.csize_t).int
        if written != read:
          echo "fix me: vterm.nim.terminalThread vterm.writeInput"
          assert written == read, "fix me: vterm.nim.terminalThread vterm.writeInput"

        state.screen.flushDamage()
        state.dirty = true
    except IOError as e:
      discard
  else:
    when defined(windows):
      template handleData(data: untyped, bytesToWrite: int): untyped =
        # echo data.toOpenArray(0, bytesToWrite - 1)
        if bytesToWrite > 0:
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
        # echo buffer.toOpenArray(0, n.int - 1)
        let written = state.vterm.writeInput(buffer.cstring, n.csize_t).int
        if written != n:
          echo "fix me: vterm.nim.terminalThread vterm.writeInput"
          assert written == n, "fix me: vterm.nim.terminalThread vterm.writeInput"

        state.screen.flushDamage()
        state.dirty = true
      elif n == 0:
        state.processTerminated = true

proc log*(state: TerminalThreadState, str: string) =
  if state.enableLog:
    state.outputChannel[].send OutputEvent(kind: OutputEventKind.Log, level: lvlDebug, msg: str)

proc log*(state: ptr TerminalThreadState, str: string) =
  if state.enableLog:
    state[].outputChannel[].send OutputEvent(kind: OutputEventKind.Log, level: lvlDebug, msg: str)

proc moveCursor(s: ptr TerminalThreadState, cols: int, rows: int) {.gcsafe, raises: [].} =
  s[].vterm.state.moveCursor(cols.cint, rows.cint)

proc resizeSixel(s: ptr TerminalThreadState, w: int, h: int) =
  if s.sixel.sizeFixed:
    return

  assert w >= s.sixel.width and h >= s.sixel.height
  assert w > s.sixel.width or h > s.sixel.height

  if w == s.sixel.width:
    # echo "quick resize, only s.sixel.height changed"
    s.sixel.colors.setLen(w * h)
  else:
    # echo "slow resize, s.sixel.width changed"
    var colorsNew = newSeq[chroma.Color](w * h)
    for y in 0..<s.sixel.height:
      for x in 0..<s.sixel.width:
        colorsNew[x + y * w] = s.sixel.colors[x + y * s.sixel.width]
    swap s.sixel.colors, colorsNew

  s.sixel.width = w
  s.sixel.height = h

iterator parseSixelData(s: ptr TerminalThreadState): int {.closure, gcsafe, raises: [].} =
  # echo &"handle sixel"
  # echo "============="
  # if s.sixel.frag.len.int > 0:
  #   echo s.sixel.frag
  # echo "============="

  template resetState() =
    s.sixel.x = 0
    s.sixel.y = 0
    s.sixel.px = 0
    s.sixel.py = 0
    s.sixel.width = 0
    s.sixel.height = 0
    s.sixel.sizeFixed = false
    s.sixel.currentColor = 1
    s.sixel.colors = newSeq[chroma.Color](0)
    s.sixel.pos = (s.cursor.row, s.cursor.col)
    for i in 0..s.sixel.palette.high:
      s.sixel.palette[i] = color(0, 0, 0, 1)
    s.sixel.palette[1] = color(1, 1, 1, 1)

  resetState()
  s.sixel.active = true

  template waitForData(): untyped =
    if s.sixel.i >= s.sixel.frag.len.int and s.sixel.frag.final:
      break
    while s.sixel.i >= s.sixel.frag.len.int:
      # echo &"wait for more data {s.sixel.i} at {s.sixel.x}, {s.sixel.y}, {currentSourceLocation(-2)}"
      yield 5
      # echo "============="
      # if s.sixel.frag.len.int > 0:
      #   echo s.sixel.frag
      # echo "============="

  try:
    var buffer = newString(0)

    s.sixel.i = 0
    while s.sixel.i < s.sixel.frag.len.int:
      template parseInt(): int =
        waitForData()
        while s.sixel.i < s.sixel.frag.len.int and s.sixel.frag.str[s.sixel.i] in {'0'..'9'}:
          buffer.add s.sixel.frag.str[s.sixel.i]
          inc s.sixel.i
          waitForData()
        let num = if buffer.len == 0:
          0
        else:
          buffer.parseInt()
        buffer.setLen(0)
        num

      let c = s.sixel.frag.str[s.sixel.i]
      case c
      of '"':
        inc s.sixel.i
        s.sixel.px = parseInt()
        inc s.sixel.i
        s.sixel.py = parseInt()
        inc s.sixel.i
        s.sixel.width = parseInt()
        inc s.sixel.i
        s.sixel.height = parseInt()
        s.sixel.colors.setLen(s.sixel.width * s.sixel.height)
        s.sixel.sizeFixed = true

      of '#':
        inc s.sixel.i
        s.sixel.currentColor = parseInt()
        if s.sixel.i < s.sixel.frag.len.int and s.sixel.frag.str[s.sixel.i] == ';':
          inc s.sixel.i
          let format = parseInt()
          inc s.sixel.i
          let x = parseInt()
          inc s.sixel.i
          let y = parseInt()
          inc s.sixel.i
          let z = parseInt()
          # echo &"# {s.sixel.currentColor}, {format}, ({x} {y} {z})"

          if format == 1:
            # todo: HLS
            discard
          elif format == 2:
            # RGB
            s.sixel.palette[s.sixel.currentColor].r = x / 100
            s.sixel.palette[s.sixel.currentColor].g = y / 100
            s.sixel.palette[s.sixel.currentColor].b = z / 100
          else:
            echo "Invalid format ", format

      of '$':
        s.sixel.x = 0
        inc s.sixel.i

      of '-':
        s.sixel.x = 0
        s.sixel.y += 6
        if s.sixel.y >= s.sixel.height:
          s.resizeSixel(s.sixel.width, s.sixel.y + 1)
        inc s.sixel.i

        if s.sixel.y >= s.sixel.height:
          break

      of '!':
        inc s.sixel.i
        let num = parseInt()
        waitForData()
        if s.sixel.i < s.sixel.frag.len.int:
          let ch = s.sixel.frag.str[s.sixel.i]

          let code = ch.int - 63
          if code in 0..63:
            if s.sixel.x + num > s.sixel.width:
              s.resizeSixel(s.sixel.x + num, s.sixel.height)
            for k in 0..<max(num, 1):
              if s.sixel.x < s.sixel.width:
                for bit in 0..5:
                  if (code and (1 shl bit)) != 0:
                    let yy = s.sixel.y + bit
                    if yy < s.sixel.height:
                      s.sixel.colors[s.sixel.x + yy * s.sixel.width] = s.sixel.palette[s.sixel.currentColor]
              inc s.sixel.x

          else:
            echo "invalid char '", ch, "' ", code

          inc s.sixel.i

      of '\x1b':
        inc s.sixel.i
        if s.sixel.i + 1 < s.sixel.frag.len.int and s.sixel.frag.str[s.sixel.i + 1] == '\\':
          inc s.sixel.i
          break

      else:
        let code = c.int - 63
        if code in 0..63:
          if s.sixel.x >= s.sixel.width:
            s.resizeSixel(s.sixel.x + 1, s.sixel.height)
          if s.sixel.x < s.sixel.width:
            for bit in 0..5:
              if (code and (1 shl bit)) != 0:
                let yy = s.sixel.y + bit
                if yy < s.sixel.height:
                  s.sixel.colors[s.sixel.x + yy * s.sixel.width] = s.sixel.palette[s.sixel.currentColor]
          inc s.sixel.x
        else:
          echo "invalid char '", c, "' ", code

        inc s.sixel.i

      waitForData()

    s.sixels[s.sixel.pos] = Sixel(
      colors: s.sixel.colors,
      width: s.sixel.width,
      height: s.sixel.height,
      px: s.sixel.px,
      py: s.sixel.py,
      pos: s.sixel.pos,
      contentHash: s.sixel.colors.hash(),
    )
    if s.cellPixelWidth != 0 and s.cellPixelHeight != 0:
      let effectiveNumCols = (s.sixel.width / s.cellPixelWidth).ceil.int
      let effectiveNumRows = (s.sixel.height / s.cellPixelHeight).ceil.int
      s.moveCursor(effectiveNumCols, 0)
      if effectiveNumRows > 0:
        s.moveCursor(0, effectiveNumRows - 1)
      # echo &"sixel {s.sixel.width}x{s.sixel.height}, {s.sixel.px}:{s.sixel.py}, {s.cursor.row}:{s.cursor.col}, {s.sixel.colors.hash}, effective: {effectiveNumCols}x{effectiveNumRows}"

  except CatchableError as e:
    echo &"Failed to parse sixel data at {s.sixel.i}: {e.msg}"

  s.sixel.active = false

proc handleDcsSixel(s: ptr TerminalThreadState, frag: VTermStringFragment) =
  if s.sixel.iter == nil or not s.sixel.active:
    s.sixel.iter = parseSixelData
  s.sixel.i = 0
  s.sixel.frag = frag
  discard s.sixel.iter(s)
  if finished(s.sixel.iter):
    s.sixel.iter = nil

template kittyDebugf*(x: static string) =
  when defined(debugKGP):
    echo fmt(x)

proc addImage(s: var KittyState, id: int, width, height: int, colors: var seq[chroma.Color]) =
  var tempColors = newSeq[chroma.Color]()
  swap(tempColors, colors)
  let textureId = createTexture(width, height, tempColors.ensureMove)
  kittyDebugf"Kitty.add image {id} {width}x{height}, {textureId.int}"
  s.images[id] = (width, height, textureId)

proc updateDestRect(placement: var PlacedImage, numCols: int, numRows: int, cell: Ivec2) =
  kittyDebugf"Kitty.updateDestRect placement {numCols}x{numRows}, {cell} {placement}"
  var numCols = numCols
  var numRows = numRows
  if numCols == 0:
    if numRows == 0:
      let t = placement.sw + placement.offsetX
      numCols = t div cell.x
      if t > numCols * cell.x:
        inc(numCols, 1)
    else:
      var heightPx: float = cell.y.float * numRows.float + placement.offsetY.float
      var widthPx: float = heightPx.float * placement.sw.float / placement.sh.float
      numCols = ceil(widthPx / cell.x.float).int
  if numRows == 0:
    if numCols == 0:
      let t = placement.sh + placement.offsetY
      numRows = t div cell.y
      if t > numRows * cell.y:
        inc(numRows, 1)
    else:
      var widthPx: float = cell.x.float * numCols.float + placement.offsetX.float
      var heightPx: float = widthPx * placement.sh.float / placement.sw.float.float
      numRows = ceil(heightPx / cell.y.float).int
  placement.effectiveNumRows = numRows
  placement.effectiveNumCols = numCols

proc addPlacement(s: var KittyState, id: int, placement: PlacedImage) =
  kittyDebugf"Kitty.add placement {id} {placement}"
  s.placements[(placement.imageId, id)] = placement

proc clear(s: var KittyState) =
  for image in s.images.values:
    deleteTexture(image.textureId)
  s.images.clear()
  s.placements.clear()

proc deleteImage(s: var KittyState, id: int) =
  kittyDebugf"Kitty.delete image {id}"
  s.images.withValue(id, image):
    deleteTexture(image.textureId)
    s.images.del(id)
    var placementsToRemove = newSeq[(int, int)]()
    for ids, p in s.placements:
      if p.imageId == id:
        placementsToRemove.add ids

    for ids in placementsToRemove:
      kittyDebugf"Kitty.delete placement {id}:{ids[1]}"
      s.placements.del(ids)

proc deletePlacement(s: var KittyState, imageId: int, pid: int, deleteImageWhenUnused: bool) =
  if (imageId, pid) in s.placements:
    kittyDebugf"Kitty.delete placement {imageId}:{pid}"
    let imageId = s.placements[(imageId, pid)].imageId
    s.placements.del((imageId, pid))

    if deleteImageWhenUnused:
      var imageStillUsed = false
      for ids, p in s.placements:
        if p.imageId == imageId:
          imageStillUsed = true
          break

      if not imageStillUsed:
        s.deleteImage(imageId)

proc deleteVisiblePlacements(s: var KittyState, deleteImageWhenUnused: bool) =
  var placementsToRemove = newSeq[(int, int)]()

  for ids, placement in s.placements:
    # todo: bounds checks
    placementsToRemove.add ids

  for ids in placementsToRemove:
    s.deletePlacement(ids[0], ids[1], deleteImageWhenUnused)

iterator parseKittyData(s: ptr TerminalThreadState) {.closure, gcsafe, raises: [].} =
  let t = startTimer()
  var i = 1
  var suppressOk = false
  var suppressFailure = false

  template waitForData(): untyped =
    if i >= s.kitty.frag.len.int and s.kitty.frag.final:
      break
    while i >= s.kitty.frag.len.int:
      yield
      i = 0

  template sendResponse(keys: untyped, body: untyped): untyped =
    let prefix = "\x1b_G"
    let suffix = "\x1b\\"
    s.sendOutput(prefix)
    keys
    s.sendOutput(";")
    body
    s.sendOutput(suffix)

  template sendOKResponse(keys: untyped): untyped =
    if not suppressOk:
      sendResponse(keys):
        s.sendOutput("OK")

  template sendErrResponse(err, keys: untyped): untyped =
    if not suppressFailure:
      sendResponse(keys):
        s.sendOutput(err)

  try:
    var numBuffer = newString(0)
    var buffer = newString(0)
    var format = 24
    var width = 1
    var height = 1
    var compression = '\0'
    var transmission = 'd'
    var chunked = false
    var id = 0
    var placementId = 0
    var imageNumber = 0
    var fileOffset = 0
    var fileSize = 0
    var action = 't'
    var toDelete = 'a'
    var placeX = 0
    var placeY = 0
    var placeZ = 0
    var placeW = 0
    var placeH = 0
    var pixelOffsetX = 0
    var pixelOffsetY = 0
    var cellWidth = 0
    var cellHeight = 0
    var cursorMovement = 0
    var unicodePlaceholder = 0
    var first = true
    var keys = ""

    while true:
      defer:
        first = false

      while i < s.kitty.frag.len.int:
        template parseInt(): int =
          waitForData()
          while i < s.kitty.frag.len.int and s.kitty.frag.str[i] in {'0'..'9'}:
            numBuffer.add s.kitty.frag.str[i]
            inc i
            waitForData()
          let num = if numBuffer.len == 0:
            0
          else:
            numBuffer.parseInt()
          numBuffer.setLen(0)
          num

        waitForData()
        let key = s.kitty.frag.str[i]
        i += 2

        waitForData()
        let charValue = s.kitty.frag.str[i]
        var intValue = 0
        if charValue in {'0'..'9'}:
          intValue = parseInt()
        else:
          inc i

        case key
        of 'q':
          if intValue == 1:
            suppressOk = true
          elif intValue == 2:
            suppressFailure = true
        of 'a':
          action = charValue

        # Keys for image transmission
        of 'f': format = intValue
        of 't': transmission = charValue
        of 's': width = intValue
        of 'v': height = intValue
        of 'S': fileSize = intValue
        of 'O': fileOffset = intValue
        of 'i':
          if not first:
            if id != intValue:
              kittyDebugf"got chunk for different id: {id} != {intValue}"
          id = intValue
        of 'I': imageNumber = intValue
        of 'p': placementId = intValue
        of 'o': compression = charValue
        of 'm': chunked = intValue != 0

        # Keys for image display
        of 'x': placeX = intValue
        of 'y': placeY = intValue
        of 'w': placeW = intValue
        of 'h': placeH = intValue
        of 'X': pixelOffsetX = intValue
        of 'Y': pixelOffsetY = intValue
        of 'c': cellWidth = intValue
        of 'r': cellHeight = intValue
        of 'C': cursorMovement = intValue
        of 'U': unicodePlaceholder = intValue
        of 'z': placeZ = intValue
        of 'P': kittyDebugf"todo: P"
        of 'Q': kittyDebugf"todo: Q"
        of 'H': kittyDebugf"todo: H"
        of 'V': kittyDebugf"todo: V"

        of 'd':
          toDelete = charValue

        else:
          kittyDebugf"Unknown kitty key '{key}'"

        if i >= s.kitty.frag.len.int and s.kitty.frag.final and not chunked:
          keys = s.kitty.frag.str.toOpenArray(0, i - 1).join("")
          break

        case s.kitty.frag.str[i]
        of ',':
          inc i
        of ';':
          if first:
            # keys = s.kitty.frag.str[0..<i] #.toOpenArray(0, i).join("")
            keys = s.kitty.frag.str.toOpenArray(0, i - 1).join("")
          inc i
          break
        else:
          inc i

        waitForData()

      # parse payload
      while i < s.kitty.frag.len.int:
        let oldLen = buffer.len
        let remaining = s.kitty.frag.len.int - i
        buffer.setLen(oldLen + remaining)
        copyMem(buffer[oldLen].addr, s.kitty.frag.str[i].addr, remaining)
        i = s.kitty.frag.len.int
        waitForData()

      if not chunked:
        break

      yield
      i = 1

    # kittyDebugf"[kitty] '{keys}', {buffer.len} payload bytes, action = {action}"
    var data = ""
    if buffer.len > 0:
      data = base64.decode(buffer)
      if action == 'q':
        kittyDebugf"payload '{buffer}' -> '{data}'"

    case transmission
    of 'd': discard
    of 'f':
      let path = s.kitty.pathPrefix & data
      # kittyDebugf"Read file '{path}'"
      try:
        data = readFile(path)
      except IOError as e:
        kittyDebugf"Failed to read file '{path}': {e.msg}"
        sendErrResponse("EBADF"):
          discard
        return
    of 't':
      let path = s.kitty.pathPrefix & data
      # kittyDebugf"Read temp file '{path}'"
      try:
        data = readFile(path)
        removeFile(path)
      except IOError as e:
        kittyDebugf"Failed to read file '{path}': {e.msg}"
        sendErrResponse("EBADF"):
          discard
        return
    of 's': kittyDebugf"not implemented: shared memory transmission"
    else:
      kittyDebugf"Unknown transmission method '{transmission}'"

    case action
    of 'a':
      kittyDebugf"control animation"
    of 'c':
      kittyDebugf"compose animation frames"

    of 'd':
      let deleteUnused = toDelete.isUpperAscii
      let toDeleteNorm = toDelete.toLowerAscii
      case toDeleteNorm
      of 'a':
        s.kitty.deleteVisiblePlacements(deleteUnused)
      of 'i':
        if placementId != 0:
          s.kitty.deletePlacement(id, placementId, deleteUnused)
        else:
          s.kitty.deleteImage(id)
        s.dirty = true
      of 'n': kittyDebugf"unhandled delete {toDelete}"
      of 'c': kittyDebugf"unhandled delete {toDelete}"
      of 'f': kittyDebugf"unhandled delete {toDelete}"
      of 'p': kittyDebugf"unhandled delete {toDelete}"
      of 'q': kittyDebugf"unhandled delete {toDelete}"
      of 'r': kittyDebugf"unhandled delete {toDelete}"
      of 'x': kittyDebugf"unhandled delete {toDelete}"
      of 'y': kittyDebugf"unhandled delete {toDelete}"
      of 'z': kittyDebugf"unhandled delete {toDelete}"
      else:
        kittyDebugf"Unknown delete method '{toDelete}'"

      # sendOKResponse:
      #   discard

    of 'f':
      kittyDebugf"transmit data for animation frames"
    of 'q':
      kittyDebugf"query terminal"

      sendOKResponse:
        discard

    of 't', 'T':
      var colors = newSeq[chroma.Color]()
      case format
      of 24:
        colors.setLen(width * height)
        let expectedLen = 3 * width * height
        if data.len != expectedLen:
          kittyDebugf"Expected {expectedLen} bytes, got {data.len}"
          sendErrResponse("ERROR"):
            discard
          return
        for y in 0..<height:
          for x in 0..<width:
            let r = data[(x + y * width) * 3 + 0].int
            let g = data[(x + y * width) * 3 + 1].int
            let b = data[(x + y * width) * 3 + 2].int
            colors[x + y * width] = color(r / 255, g / 255, b / 255, 1)
      of 32:
        colors.setLen(width * height)
        let expectedLen = 4 * width * height
        if data.len != expectedLen:
          kittyDebugf"Expected {expectedLen} bytes, got {data.len}"
          sendErrResponse("ERROR"):
            discard
          return
        for y in 0..<height:
          for x in 0..<width:
            let r = data[(x + y * width) * 4 + 0].int
            let g = data[(x + y * width) * 4 + 1].int
            let b = data[(x + y * width) * 4 + 2].int
            let a = data[(x + y * width) * 4 + 3].int
            colors[x + y * width] = color(r / 255, g / 255, b / 255, a / 255)
      of 100:
        let png = decodePng(data[0].addr, data.len)
        let image = newImage(png)
        width = image.width
        height = image.height
        colors.setLen(width * height)
        for y in 0..<height:
          for x in 0..<width:
            colors[x + y * width] = image.data[x + y * width].color
      else:
        kittyDebugf"Unknown format {format}"

      s.kitty.addImage(id, width, height, colors)

      if action == 'T':
        var placedImage = PlacedImage(
          sx: placeX,
          sy: placeY,
          sw: if placeW > 0: placeW else: width,
          sh: if placeH > 0: placeH else: height,
          z: placeZ,
          offsetX: pixelOffsetX,
          offsetY: pixelOffsetY,
          cx: s.cursor.col,
          cy: s.cursor.row,
          cw: cellWidth,
          ch: cellHeight,
          imageId: id,
        )
        placedImage.updateDestRect(placedImage.cw, placedImage.ch, ivec2(s.cellPixelWidth.int32, s.cellPixelHeight.int32))
        # todo
        # if cursorMovement == 0 and unicodePlaceholder == 0:
        #   s.moveCursor(placedImage.effectiveNumCols, 0)
        #   if placedImage.effectiveNumRows > 0:
        #     s.moveCursor(0, placedImage.effectiveNumRows - 1)

        s.kitty.addPlacement 0, placedImage
        s.dirty = true

        sendOKResponse:
          discard

    of 'p':
      var placedImage = PlacedImage(
        sx: placeX,
        sy: placeY,
        sw: if placeW > 0: placeW else: width,
        sh: if placeH > 0: placeH else: height,
        z: placeZ,
        offsetX: pixelOffsetX,
        offsetY: pixelOffsetY,
        cx: s.cursor.col,
        cy: s.cursor.row,
        cw: cellWidth,
        ch: cellHeight,
        imageId: id,
      )
      placedImage.updateDestRect(placedImage.cw, placedImage.ch, ivec2(s.cellPixelWidth.int32, s.cellPixelHeight.int32))
      # todo
      # if cursorMovement == 0 and unicodePlaceholder == 0:
      #   s.moveCursor(placedImage.effectiveNumCols, 0)
      #   if placedImage.effectiveNumRows > 0:
      #     s.moveCursor(0, placedImage.effectiveNumRows - 1)

      s.kitty.addPlacement placementId, placedImage
      s.dirty = true

    else:
      kittyDebugf"Unknown kitty action '{action}'"

    # kittyDebugf"Handled kitty request in {t.elapsed.ms}ms"
  except CatchableError as e:
    kittyDebugf"Failed to parse kitty data at {i}: {e.msg}"
    let msg = &"ERROR:{e.msg}"
    sendErrResponse(msg):
      discard

proc handleApcKitty(s: ptr TerminalThreadState, frag: VTermStringFragment) =
  if s.kitty.iter == nil:
    s.kitty.iter = parseKittyData
  s.kitty.frag = frag
  s.kitty.iter(s)
  if finished(s.kitty.iter):
    s.kitty.iter = nil

proc handleKittyKeyboard(s: ptr TerminalThreadState, leader: char, args: openArray[clong], intermed: cstring) =
  let stack = if s.alternateScreen:
    s.kittyKeyboardAlternate.addr
  else:
    s.kittyKeyboardMain.addr

  case leader
  of '=':
    let mode = if args.len >= 2:
      args[1].int
    else:
      1

    let flagsInt = if args.len >= 1:
      args[0].int and 0x7f
    else:
      0
    let flags = cast[set[KittyKeyboardState]](flagsInt)

    if stack[].len == 0:
      stack[].add {}

    case mode
    of 1: stack[].last = flags
    of 2: stack[].last.incl flags
    of 3: stack[].last.excl flags
    else:
      echo &"Unknown mode {3}"

  of '>':
    let flagsInt = if args.len >= 1:
      args[0].int and 0x7f
    else:
      0

    let flags = cast[set[KittyKeyboardState]](flagsInt)
    stack[].add flags
    if stack[].len > 64:
      stack[].removeShift(0)
  of '<':
    let num = if args.len >= 1:
      args[0].int
    else:
      1

    for i in 0..<num:
      if stack[].len == 0:
        break
      discard stack[].pop()
  of '?':
    let flags = if stack[].len > 0:
      cast[int](stack[].last)
    else:
      0
    s.sendOutput(&"\e[?{flags}u")
  else:
    echo &"unsupported"

proc createPlacements(state: KittyState): seq[PlacedImage] =
  result = newSeqOfCap[PlacedImage](state.placements.len)
  for p in state.placements.values:
    if p.imageId in state.images:
      result.add p
      result.last.textureId = state.images[p.imageId].textureId

  result.sort proc(a, b: PlacedImage): int =
    if a.z != b.z:
      return cmp(a.z, b.z)
    return cmp(a.imageId, b.imageId)

proc terminalThread(s: TerminalThreadState) {.thread, nimcall.} =
  var state = s
  state.scrollbackLines = 16384
  state.scrollbackBuffer = initDeque[seq[VTermScreenCell]](state.scrollbackLines)

  proc log(str: string) =
    if state.enableLog:
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Log, level: lvlDebug, msg: str)

  var callbacks = VTermScreenCallbacks(
    damage: (proc(rect: VTermRect; user: pointer): cint {.cdecl.} =
      # echo &"damage: {rect}"
    ),
    erase: (proc(rect: VTermRect; user: pointer): cint {.cdecl.} =
      # echo "erase: {rect}"
      let state = cast[ptr TerminalThreadState](user)
      var keysToRemove = newSeq[(int, int)]()
      for key in state.sixels.keys:
        if key[0] in rect.start_row..rect.end_row and key[1] in rect.start_col..rect.end_col:
          keysToRemove.add key
      for key in keysToRemove:
        state.sixels.del key
      if keysToRemove.len > 0:
        state.outputChannel[].send OutputEvent(
          kind: OutputEventKind.TerminalBuffer,
          buffer: state[].createTerminalBuffer(),
          sixels: state.sixels,
          placements: state.kitty.createPlacements(),
        )
    ),
    movecursor: (proc(pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      state.cursor.row = pos.row.int
      state.cursor.col = pos.col.int
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: pos.row.int + state.scrollY, col: pos.col.int)
      # state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorVisible, visible: visible != 0)
    ),
    settermprop: (proc(prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      case prop
      of VTERM_PROP_ALTSCREEN:
        state.alternateScreen  = val.boolean != 0
      of VTERM_PROP_CURSORVISIBLE:
        # log state, &"settermmprop VTERM_PROP_CURSORVISIBLE {val.boolean != 0}"
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorVisible, visible: val.boolean != 0)

      of VTERM_PROP_CURSORBLINK:
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorBlink, cursorBlink: val.boolean != 0)

      of VTERM_PROP_CURSORSHAPE:
        let shape = case val.number
        of VTERM_PROP_CURSORSHAPE_BLOCK: CursorShape.Block
        of VTERM_PROP_CURSORSHAPE_UNDERLINE: CursorShape.Underline
        of VTERM_PROP_CURSORSHAPE_BAR_LEFT: CursorShape.BarLeft
        else: CursorShape.Block
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.CursorShape, shape: shape)

      else:
        discard
      return 1
    ),
    # bell: (proc(user: pointer): cint {.cdecl.} = discard),
    resize: (proc(rows: cint; cols: cint; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Size, width: cols.int, height: rows.int, pixelWidth: state.pixelWidth, pixelHeight: state.pixelHeight)
      if cols == state.width and rows.int == state.height:
        return
      # echo &"resize: clear sixels {state.width}x{state.height} -> {cols}x{rows}"
      state.kitty.clear()
      state.sixels.clear()
      state.dirty = true
    ),
    sb_pushline: (proc(cols: cint; cells: ptr UncheckedArray[VTermScreenCell]; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      var line = newSeq[VTermScreenCell](cols)
      for i in 0..<cols:
        line[i] = cells[i]
      while state.scrollbackBuffer.len >= state.scrollbackLines:
        state.scrollbackBuffer.popFirst()
      state.scrollbackBuffer.addLast(line)
      return 0 # return value is ignored
    ),
    sb_popline: (proc(cols: cint; cells: ptr UncheckedArray[VTermScreenCell]; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      if state.scrollbackBuffer.len > 0:
        let line = state.scrollbackBuffer.popLast()
        for i in 0..<min(cols, line.len):
          cells[i] = line[i]
        return 1
      return 0
    ),
    sb_clear: (proc(user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      # echo &"sb_clear: clear sixels"
      state.kitty.clear()
      state.sixels.clear()
      state.scrollbackBuffer.clear()
      state.scrollY = 0
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Scroll, scrollY: state.scrollY)
      state.dirty = true
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

  var parserCallbacks = VTermStateFallbacks(
    control: (proc(control: char; user: pointer): cint {.cdecl.} =
      # echo &"control '{control}'"
      return 1
    ),
    csi: (proc(leader: cstring; args: ptr UncheckedArray[clong]; argcount: cint; intermed: cstring; command: char; user: pointer): cint {.cdecl.} =
      let leaderChar = if leader.len > 0:
        leader[0]
      else:
        '\0'

      let state = cast[ptr TerminalThreadState](user)
      # echo &"csi '{leader}' '{intermed}', '{command}', {args.toOpenArray(0, argcount.int - 1)}"
      case command
      of 'u':
        state.handleKittyKeyboard(leaderChar, args.toOpenArray(0, argcount - 1), intermed)
      of 't':
        if argcount > 0:
          case args[0]
          of 14:
            # pixel size
            state.sizeRequested = true
            let width = state.pixelWidth
            let height = state.pixelHeight
            let msg = &"\e[4;{height};{width}t"
            handleOutput(msg.cstring, msg.len.csize_t, user)
          of 15:
            # cell pixel size
            state.sizeRequested = true
            let width = state.cellPixelWidth
            let height = state.cellPixelHeight
            let msg = &"\e[5;{height};{width}t"
            handleOutput(msg.cstring, msg.len.csize_t, user)
          of 16:
            # pixel size
            state.sizeRequested = true
            let width = state.pixelWidth
            let height = state.pixelHeight
            let msg = &"\e[6;{height};{width}t"
            handleOutput(msg.cstring, msg.len.csize_t, user)
          of 18:
            # grid size
            state.sizeRequested = true
            let msg = &"\e[8;{state.height};{state.width}t"
            handleOutput(msg.cstring, msg.len.csize_t, user)
          else:
            discard
      else:
        discard
      return 1
    ),
    osc: (proc(command: cint; frag: VTermStringFragment; user: pointer): cint {.cdecl.} =
      return 1
    ),
    dcs: (proc(command: cstring; commandlen: csize_t; frag: VTermStringFragment; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      let commandStr = newString(commandlen.int)
      copyMem(commandStr[0].addr, command[0].addr, commandlen.int)
      # echo &"dcs '{commandStr}', {frag}"
      if commandlen > 0 and command[commandlen - 1] == 'q':
        handleDcsSixel(state, frag)
        return 1
    ),
    apc: (proc(frag: VTermStringFragment; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      # echo &"apc '{frag}'"
      if frag.len.int > 0 and (frag.str[0] == 'G' or state.kitty.iter != nil):
        handleApcKitty(state, frag)
      return 1
    ),
    pm: (proc(frag: VTermStringFragment; user: pointer): cint {.cdecl.} =
      return 1
    ),
    sos: (proc(frag: VTermStringFragment; user: pointer): cint {.cdecl.} =
      return 1
    ),
    reset: (proc (hard: int; user: pointer): cint {.cdecl.} =
      let state = cast[ptr TerminalThreadState](user)
      # echo &"===================== reset: {hard}"
      if state.alternateScreen:
        state.kittyKeyboardAlternate.setLen(0)
      else:
        state.kittyKeyboardMain.setLen(0)
    ),
  )

  state.vterm.screen.setUnrecognisedFallbacks(parserCallbacks.addr, state.addr)

  state.vterm.setOutputCallback(handleOutput, state.addr)
  state.vterm.screen.setCallbacks(callbacks.addr, state.addr)
  state.vterm.state.setSelectionCallbacks(selectionCallbacks.addr, state.addr, nil, 1024)
  state.vterm.screen.enableAltscreen(1)

  if state.autoRunCommand.len > 0:
    for r in state.autoRunCommand.runes:
      state.vterm.uniChar(r.uint32, {}.toVtermModifiers)
    state.vterm.key(INPUT_ENTER.inputToVtermKey, {}.toVtermModifiers)

  var buffer = ""
  var exitCode = int.none

  proc handleInput(state: ptr TerminalThreadState) {.async.} =
    while not state.terminateRequested:
      await state.handles.inputEventSignal.wait()
      try:
        state[].handleInputEvents()
        if state.dirty:
          state.dirty = false
          state.outputChannel[].send OutputEvent(
            kind: OutputEventKind.TerminalBuffer,
            buffer: state[].createTerminalBuffer(),
            sixels: state.sixels,
            placements: state.kitty.createPlacements(),
          )
      except CatchableError as e:
        echo "async error handle input events ", e.msg
        discard

  proc handleOutput(state: ptr TerminalThreadState) {.async.} =
    while not state.terminateRequested:
      await state.readChannel.get.signal.wait()
      try:
        state[].handleProcessOutput(state.processStdoutBuffer)
        if state.dirty:
          state.dirty = false
          state.outputChannel[].send OutputEvent(
            kind: OutputEventKind.TerminalBuffer,
            buffer: state[].createTerminalBuffer(),
            sixels: state.sixels,
            placements: state.kitty.createPlacements(),
          )
      except CatchableError as e:
        echo "async error handle process output ", e.msg
        discard

  chronosDontSkipCallbacksAtStart = true
  if state.useChannels:
    asyncSpawn handleInput(state.addr)
    asyncSpawn handleOutput(state.addr)

  try:
    while true:
      if state.useChannels:
        try:
          let timeout = 1000000000
          poll(timeout)
        except AsyncError, CancelledError:
          # echo "async error ", getCurrentExceptionMsg()
          discard

      else:
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
          buffer: state.createTerminalBuffer(),
          sixels: state.sixels,
          placements: state.kitty.createPlacements(),
        )

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
  discard self.handles.inputEventSignal.fireSync()
  when defined(windows):
    discard SetEvent(self.handles.inputWriteEvent)
  else:
    var b: uint64 = 1
    discard write(self.handles.inputWriteEventFd, b.addr, sizeof(typeof(b)))

proc terminate*(self: Terminal) {.async.} =
  log lvlInfo, &"Close terminal '{self.command}'"

  if not self.threadTerminated:
    self.sendEvent(InputEvent(kind: InputEventKind.Terminate))

  if not self.useChannels:
    when defined(windows):
      ClosePseudoConsole(self.handles.hpcon)
    else:
      discard close(self.handles.masterFd)

  while not self.threadTerminated:
    # todo: use async signals
    await sleepAsync(10.milliseconds)

  when defined(enableLibssh):
    if self.ssh.isSome:
      self.sshChannel.close()
      self.sshChannel.free()
      self.sshClient.disconnect()

  discard self.handles.inputEventSignal.close()
  if not self.useChannels:
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

proc createTerminal*(self: TerminalService, width: int, height: int, writeChannel: Arc[BaseChannel], readChannel: Arc[BaseChannel], autoRunCommand: string = "", kittyPathPrefix: string = ""): Terminal {.raises: [OSError, IOError, ResourceExhaustedError].}

proc logErrors(process: AsyncProcess): Future[void] {.async.} =
  while true:
    let line = await process.recvErrorLine()
    log lvlError, "[stderr] ", line

when defined(enableLibssh):
  when defined(windows):
    from winlean import nil
    import chronos/transports/stream

  proc authPublicKey*(session: Session; username, privKey: string, pubKey = "", passphrase = ""): int {.raises: [IOError].} =
    let privKey = expandTilde(privKey)
    var pubKey = pubKey
    if pubKey.len > 0:
      pubKey = expandTilde(pubKey)

    while true:
      let rc = session.userauth_publickey_from_file(username, pubKey.cstring, privKey.cstring, passphrase)
      if rc == LIBSSH2_ERROR_EAGAIN:
        discard
      elif rc < 0:
        return rc
      else:
        break

    result = 0

  proc createSshSession(self: TerminalService, terminal: Terminal, stdin: Arc[BaseChannel], stdout: Arc[BaseChannel], command: string, args: seq[string] = @[], options: SshOptions): Future[void] {.async: (raises: []).} =
    try:
      log lvlInfo, &"Create ssh session {options}"
      discard libssh2.init(0)
      let ipAddress = options.address.get("127.0.0.1")
      let port = options.port.get(22)
      let addressess = resolveTAddress(ipAddress & ":" & $port)
      if addressess.len == 0:
        raise newException(IOError, &"Failed to resolve address '{ipAddress}:{port}'")

      let address = addressess[0]
      let transp = await connect(address, bufferSize = 1024 * 1024)
      let session = session_init()

      session_set_blocking(session, 0)
      var rc: int
      while true:
        when defined(windows):
          rc = session_handshake(session, winlean.SocketHandle(transp.fd))
        else:
          rc = session_handshake(session, posix.SocketHandle(transp.fd))
        if rc != LIBSSH2_ERROR_EAGAIN:
          break
      if rc != 0:
        raise newException(IOError, "SSH session handshake failed: " & $rc)

      # Authenticate. Try with empty password first, if that fails then prompt user for password.
      let vfs = self.services.getService(VFSService).get.vfs
      let privateKeyPath = vfs.localize(options.privateKeyPath)
      let publicKeyPath = vfs.localize(options.publicKeyPath)
      log lvlInfo, &"Authenticate ssh session '{options.username}@{address}' ({privateKeyPath}) with empty password"
      var authResult = session.authPublicKey(options.username, privateKeyPath, publicKeyPath, "")
      if authResult < 0:
        # If we failed to verify the public key with the empty password, prompt user for password.
        if authResult == LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED:
          let passphrase = if options.password.isSome:
            options.password
          else:
            await self.layout.promptString("Passphrase for " & options.username)
          if passphrase.isNone:
            log lvlInfo, &"Cancel authentication for ssh session '{options.username}@{address}' ({privateKeyPath})"
            return

          log lvlInfo, &"Authenticate ssh session '{options.username}@{address}' ({privateKeyPath}) with password"
          authResult = session.authPublicKey(options.username, privateKeyPath, publicKeyPath, passphrase.get(""))

        if authResult < 0:
          raise newException(IOError, &"Failed to authenticate ssh session '{options.username}@{address}': {authResult}")

      log lvlInfo, &"Authentication successfull for ssh session '{options.username}@{address}' ({privateKeyPath})"

      let sshClient = newSSHClient()
      sshClient.session = session
      let sshChannel = sshClient.initChannel()

      sshAsyncWait "request pty":
        var term = "xterm-256color"
        let width = terminal.width
        let height = terminal.height
        sshChannel.impl.channel_request_pty_ex(term.cstring, term.len.uint, nil, 0, width, height, terminal.pixelWidth, terminal.pixelHeight)

      sshAsyncWait "start shell":
        sshChannel.impl.channel_shell()

      proc forwardSshChannelToStdOutChannel(sshChannel: SSHChannel, chan: Arc[BaseChannel]) {.async: (raises: []).} =
        try:
          var buffer = newString(1024)
          while true:
            let rc = sshChannel.impl.channel_read(buffer[0].addr, buffer.len)
            if rc > 0:
              chan.write(buffer.toOpenArrayByte(0, rc - 1))
              discard chan.getMutUnsafe.signal.fireSync()
            elif rc == LIBSSH2_ERROR_EAGAIN:
              catch sleepAsync(1.milliseconds).await:
                discard
            else:
              break
        except CatchableError as e:
          echo "Failed to read output: ", e.msg

        # echo "=================== forwardSshChannelToStdOutChannel end"

      asyncSpawn forwardSshChannelToStdOutChannel(sshChannel, stdout)

      discard stdin.listen(proc(channel: var BaseChannel, closed: bool): ChannelListenResponse {.gcsafe, raises: [].} =
        try:
          let num = channel.peek
          if num > 0:
            var buff = newString(num)
            let read = channel.read(buff.toOpenArrayByte(0, buff.high))
            buff.setLen(read)

            var rc: int
            while true:
              rc = sshChannel.impl.channel_write(buff.cstring, buff.len)
              if rc != LIBSSH2_ERROR_EAGAIN:
                break
            if rc < 0:
              echo "Failed to write to ssh channel: ", rc
            rc = sshChannel.impl.channel_flush()
        except IOError as e:
          echo "Failed to read stdin: ", e.msg

        discard
      )

      sshAsyncWait "resize shell":
        let width = terminal.width
        let height = terminal.height
        sshChannel.impl.channel_request_pty_size_ex(width, height, terminal.pixelWidth, terminal.pixelHeight)

      terminal.ssh = options.some
      terminal.sshChannel = sshChannel
      terminal.sshClient = sshClient
    except CatchableError as e:
      log lvlError, &"Failed to create ssh connection: {e.msg}"

proc createTerminal*(self: TerminalService, width: int, height: int, command: string, args: seq[string] = @[], autoRunCommand: string = "", createPty: bool = true, kittyPathPrefix: string = "", ssh: Option[SshOptions]): Terminal {.raises: [OSError, IOError, ResourceExhaustedError, TransportError, CancelledError].} =
  if ssh.isSome:
    var stdin = newInMemoryChannel()
    var stdout = newInMemoryChannel()
    result = self.createTerminal(width, height, stdin, stdout, autoRunCommand, kittyPathPrefix)
    when defined(enableLibssh):
      asyncSpawn self.createSshSession(result, stdin, stdout, command, args, ssh.get)
    else:
      log lvlError, &"Direct ssh terminals not supported in this build. Use 'ssh' as a shell instead."
    return

  if not createPty:
    try:
      var process = startAsyncProcess(command, args, killOnExit = true, autoStart = false, errToOut = false)
      asyncSpawn process.logErrors()
      discard process.start()
      return self.createTerminal(width, height, process.stdin, process.stdout, autoRunCommand, kittyPathPrefix)
    except ValueError as e:
      log lvlError, &"Failed to start process {command}: {e.msg}"

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

    var flags: DWORD = 0
    if self.config.runtime.get("experimental.terminal.enablePassthrough", false):
      log lvlWarn, &"Enabling very experimental ContPTY passthrough mode."
      # From windows terminal: Enable passthrough mode. This doesn't seem to be in the current windows version yet though.
      flags = flags or PSEUDOCONSOLE_RESIZE_QUIRK
      flags = flags or PSEUDOCONSOLE_WIN32_INPUT_MODE
      flags = flags or PSEUDOCONSOLE_PASSTHROUGH_MODE

    var hPC: HPCON
    if CreatePseudoConsole(wincon.COORD(X: width.SHORT, Y: height.SHORT), inputReadHandle, outputWriteHandle, flags, addr(hPC)) != S_OK:
      raiseOSError(osLastError(), "Failed to create pseude console")

    var pi: PROCESS_INFORMATION
    ZeroMemory(addr(pi), sizeof((pi)))

    let cmd = newWideCString(command)
    var siEx: STARTUPINFOEX
    ZeroMemory(addr(siEx), sizeof((siEx)))
    siEx.StartupInfo.cb = sizeof((STARTUPINFOEX)).DWORD
    siEx = prepareStartupInformation(hPC)

    if CreateProcessW(nil, cmd, nil, nil, FALSE, EXTENDED_STARTUPINFO_PRESENT, nil, nil, siEx.StartupInfo.addr, pi.addr) == 0:
      raiseOSError(osLastError(), "Failed to start sub process")

    CloseHandle(inputReadHandle)
    CloseHandle(outputWriteHandle)

    let inputWriteEvent = CreateEvent(nil, FALSE, FALSE, nil)
    let outputReadEvent = CreateEvent(sa.addr, FALSE, FALSE, nil)

    if inputWriteEvent == INVALID_HANDLE_VALUE or outputReadEvent == INVALID_HANDLE_VALUE:
      raiseOSError(osLastError(), "Failed to create events")

    let handles = OsHandles(
      hpcon: hPC,
      inputWriteHandle: inputWriteHandle,
      outputReadHandle: outputReadHandle,
      inputEventSignal: ThreadSignalPtr.new().value,
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
      inputEventSignal: ThreadSignalPtr.new().value,
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
    createPty: createPty,
    kittyPathPrefix: kittyPathPrefix,
    width: width,
    height: height,
  )

  proc createChannel[T](channel: var ptr[system.Channel[T]]) =
    channel = cast[ptr system.Channel[T]](allocShared0(sizeof(system.Channel[T])))
    channel[].open()

  result.inputChannel.createChannel()
  result.outputChannel.createChannel()

  result.terminalBuffer.initTerminalBuffer(width, height)
  asyncSpawn self.handleOutputChannel(result)

  var threadState = TerminalThreadState(
    vtermInternal: vterm,
    screenInternal: screen,
    inputChannel: result.inputChannel,
    outputChannel: result.outputChannel,
    width: width,
    height: height,
    cursor: (0, 0, true, true),
    autoRunCommand: autoRunCommand,
    handles: handles,
    kitty: KittyState(
      pathPrefix: kittyPathPrefix,
    )
  )

  result.thread.createThread(terminalThread, threadState)

proc createTerminal*(self: TerminalService, width: int, height: int, writeChannel: Arc[BaseChannel], readChannel: Arc[BaseChannel], autoRunCommand: string = "", kittyPathPrefix: string = ""): Terminal {.raises: [OSError, IOError, ResourceExhaustedError].} =
  let id = self.idCounter
  inc self.idCounter

  let handles = OsHandles(
    inputEventSignal: ThreadSignalPtr.new().value,
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
    autoRunCommand: autoRunCommand,
    handles: handles,
    useChannels: true,
    kittyPathPrefix: kittyPathPrefix,
    width: width,
    height: height,
  )

  proc createChannel[T](channel: var ptr[system.Channel[T]]) =
    channel = cast[ptr system.Channel[T]](allocShared0(sizeof(system.Channel[T])))
    channel[].open()

  result.inputChannel.createChannel()
  result.outputChannel.createChannel()

  result.terminalBuffer.initTerminalBuffer(width, height)
  asyncSpawn self.handleOutputChannel(result)

  var threadState = TerminalThreadState(
    vtermInternal: vterm,
    screenInternal: screen,
    inputChannel: result.inputChannel,
    outputChannel: result.outputChannel,
    width: width,
    height: height,
    cursor: (0, 0, true, true),
    autoRunCommand: autoRunCommand,
    handles: handles,
    useChannels: true,
    writeChannel: writeChannel,
    readChannel: readChannel,
    kitty: KittyState(
      pathPrefix: kittyPathPrefix,
    )
  )

  result.thread.createThread(terminalThread, threadState)

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[string]
proc handleInput(self: TerminalService, view: TerminalView, text: string)
proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers, noKitty: bool = false)

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
  if self.terminal.useChannels and not self.terminal.ssh.isSome:
    return nil
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
    createPty: self.terminal.createPty,
    kittyPathPrefix: self.terminal.kittyPathPrefix,
    ssh: self.terminal.ssh,
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

  asyncSpawn self.cleanupUnusedSixels()

  return ok()

method deinit*(self: TerminalService) =
  for term in self.terminals.values:
    term.close()

proc requestRender(self: TerminalService) =
  self.platform.requestRender()

proc handleInput(self: TerminalService, view: TerminalView, text: string) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Text, text: text))
  view.terminal.lastEventTime = startTimer()

proc handlePaste(self: TerminalService, view: TerminalView, text: string) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Paste, text: text))
  view.terminal.lastEventTime = startTimer()

proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers, noKitty: bool = false) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Key, input: input, modifiers: modifiers, noKitty: noKitty))
  view.terminal.lastEventTime = startTimer()

proc handleScroll*(view: TerminalView, deltaY: int, modifiers: Modifiers) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.Scroll, deltaY: deltaY, modifiers: modifiers))
  view.terminal.lastEventTime = startTimer()

proc handleClick*(view: TerminalView, button: input.MouseButton, pressed: bool, modifiers: Modifiers, col: int, row: int) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.MouseClick, button: button, pressed: pressed, row: row, col: col, modifiers: modifiers))
  view.terminal.lastEventTime = startTimer()

proc handleDrag*(view: TerminalView, button: input.MouseButton, col: int, row: int, modifiers: Modifiers) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.MouseMove, row: row, col: col, modifiers: modifiers))
  view.terminal.lastEventTime = startTimer()

proc handleMove*(view: TerminalView, col: int, row: int) =
  view.terminal.sendEvent(InputEvent(kind: InputEventKind.MouseMove, row: row, col: col))
  view.terminal.lastEventTime = startTimer()

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

proc setSize*(self: TerminalView, width: int, height: int, cellPixelWidth: int, cellPixelHeight: int) =
  if self.size != (width, height, cellPixelWidth, cellPixelHeight):
    self.size = (width, height, cellPixelWidth, cellPixelHeight)
    if self.terminal != nil:
      self.terminal.sendEvent(InputEvent(kind: InputEventKind.Size, row: height, col: width, cellPixelWidth: cellPixelWidth, cellPixelHeight: cellPixelHeight))

proc createTerminalView(self: TerminalService, command: string, options: CreateTerminalOptions, id: Id = idNone()): TerminalView =
  try:
    let term = self.createTerminal(80, 50, command, options.args, options.autoRunCommand, options.createPty, options.kittyPathPrefix, options.ssh)
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
      self.platform.requestRender()
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

proc createTerminalView*(self: TerminalService, stdin: Arc[BaseChannel], stdout: Arc[BaseChannel], options: CreateTerminalOptions, id: Id = idNone()): TerminalView =
  try:
    let term = self.createTerminal(80, 50, stdin, stdout, options.autoRunCommand)
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
      self.platform.requestRender()
      view.markDirty()

    discard term.onTerminated.subscribe proc(exitCode: Option[int]) =
      if not view.open:
        return
      log lvlInfo, &"Terminal process '' terminated with exit code {exitCode}"
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
  let view = self.createTerminalView(command, options)
  if view != nil:
    self.layout.addView(view, slot=options.slot, focus=options.focus)

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
    createPty: options.createPty,
    kittyPathPrefix: options.kittyPathPrefix,
    ssh: options.ssh,
    args: options.args,
  ))
  if view == nil:
    return
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

proc sendTerminalInput*(self: TerminalService, input: string, noKitty: bool = false) {.expose("terminal").} =
  if self.getActiveView().getSome(view):
    for (inputCode, mods, _) in parseInputs(input):
      self.handleKey(view, inputCode.a, mods, noKitty)

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
        if view.terminal.ssh.getSome(opts):
          let port = if opts.port.getSome(port): &":{port}" else: ""
          let address = opts.address.get("127.0.0.1")
          name = &"ssh {opts.username}@{address}{port}"
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
