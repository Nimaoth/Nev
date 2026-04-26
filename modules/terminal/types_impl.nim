import command_service
import std/[os, typedthreads, tables, hashes, macros, deques, genasts]
import misc/[custom_logger, util, custom_unicode, custom_async, event, timer, myjsonutils, render_command]
import ui/node
import platform/[tui]
import nimsumtree/[rope, arc]
import dynamic_view, events, config_provider, layout/layout, theme, vterm, input, input_api, channel, register
from scripting_api import SshOptions, RunInTerminalOptions, CreateTerminalOptions
import types

when defined(enableLibssh):
  static:
    hint("Build with libssh2")
  import ssh

logCategory "terminal"

{.push gcsafe.}
{.push raises: [].}

when defined(windows):
  import winim/lean
  type HPCON* = HANDLE

  const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: DWORD = 131094

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
  InputEventKind* {.pure.} = enum
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

  InputEvent* = object
    modifiers*: Modifiers
    row*: int
    col*: int
    noKitty*: bool
    case kind*: InputEventKind
    of InputEventKind.Text, InputEventKind.Paste:
      text*: string
    of InputEventKind.Key:
      input*: int64
      action*: InputAction

    of InputEventKind.MouseMove:
      discard
    of InputEventKind.MouseClick:
      button*: input.MouseButton
      pressed*: bool
    of InputEventKind.Scroll:
      deltaY*: int
    of InputEventKind.Size:
      # also use row, col
      cellPixelWidth*: int
      cellPixelHeight*: int
    of InputEventKind.Terminate:
      discard
    of InputEventKind.RequestRope:
      rope*: pointer # ptr Rope, but Nim complains about destructors?
    of InputEventKind.SetColorPalette:
      colors*: seq[tuple[r, g, b: uint8]]
    of InputEventKind.EnableLog:
      enableLog*: bool

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
  OutputEventKind* {.pure.} = enum TerminalBuffer, Size, Cursor, CursorVisible, CursorShape, CursorBlink, Terminated, Rope, Scroll, Log
  OutputEvent* = object
    case kind*: OutputEventKind
    of OutputEventKind.TerminalBuffer:
      buffer*: TerminalBuffer
      sixels*: Table[(int, int), Sixel]
      placements*: seq[PlacedImage]
      relativeScroll*: float
      scrollHeight*: float
    of OutputEventKind.Size:
      width*: int
      height*: int
      pixelWidth*: int
      pixelHeight*: int
    of OutputEventKind.Cursor:
      row*: int
      col*: int
    of OutputEventKind.CursorVisible:
      visible*: bool
    of OutputEventKind.CursorBlink:
      cursorBlink*: bool
    of OutputEventKind.CursorShape:
      shape*: CursorShape
    of OutputEventKind.Terminated:
      exitCode*: Option[int]
    of OutputEventKind.Rope:
      rope*: pointer # ptr Rope, but Nim complains about destructors?
    of OutputEventKind.Scroll:
      deltaY*: int
      scrollY*: int
    of OutputEventKind.Log:
      level*: Level
      msg*: string

  OsHandles* = object
    inputEventSignal*: ThreadSignalPtr # used to signal input events when using channels. todo: use for native terminal aswell
    when defined(windows):
      hpcon*: HPCON
      inputWriteHandle*: HANDLE
      outputReadHandle*: HANDLE
      inputWriteEvent*: HANDLE
      outputReadEvent*: HANDLE
      processInfo*: PROCESS_INFORMATION
      startupInfo*: STARTUPINFOEX
    else:
      masterFd*: cint
      slaveFd*: cint
      inputWriteEventFd*: cint
      childPid*: Pid

  SixelState* = object
    active*: bool
    colors*: seq[chroma.Color]
    palette*: array[256, chroma.Color] = default(array[256, chroma.Color])
    i*: int =  0
    x*: int =  0
    y*: int =  0
    width*: int = 0
    height*: int = 0
    sizeFixed*: bool  = false
    px*: int = 0
    py*: int = 0
    currentColor*: int = 1
    iter*: iterator(s: ptr TerminalThreadState): int {.gcsafe, raises: [].}
    frag*: VTermStringFragment
    pos*: tuple[line, column: int]

  KittyState* = object
    active*: bool
    colors*: seq[chroma.Color]
    iter*: iterator(s: ptr TerminalThreadState) {.gcsafe, raises: [].}
    frag*: VTermStringFragment
    pos*: tuple[line, column: int]
    pathPrefix*: string
    images*: Table[int, tuple[width, height: int, textureId: TextureId]]
    placements*: Table[(int, int), PlacedImage]

  KittyKeyboardState* = enum
    DisambiguateEscapeCodes
    ReportEventTypes
    ReportAlternateKeys
    ReportAllKeysAsEscapeCodes
    ReportAssociatedText

  TerminalThreadState* = object
    vtermInternal*: pointer
    screenInternal*: pointer
    inputChannel*: ptr system.Channel[InputEvent]
    outputChannel*: ptr system.Channel[OutputEvent]
    useChannels*: bool
    readChannel*: Arc[BaseChannel]
    writeChannel*: Arc[BaseChannel]
    width*: int
    height*: int
    cellPixelWidth*: int
    cellPixelHeight*: int
    pixelWidth*: int
    pixelHeight*: int
    scrollY*: int = 0
    cursor*: tuple[row, col: int, visible: bool, blink: bool] = (0, 0, true, true)
    scrollbackBuffer*: Deque[seq[VTermScreenCell]]
    scrollbackLines*: int
    dirty*: bool = false # When true send updated terminal buffer to main thread
    terminateRequested*: bool = false
    processTerminated*: bool = false
    autoRunCommand*: string
    enableLog*: bool = false
    sixel*: SixelState
    kitty*: KittyState
    sixels*: Table[(int, int), Sixel]
    alternateScreen*: bool
    kittyKeyboardMain*: seq[set[KittyKeyboardState]]
    kittyKeyboardAlternate*: seq[set[KittyKeyboardState]]
    outputBuffer*: string
    handles*: OsHandles
    sizeRequested*: bool # Whether the size was requested use CSI 14/15/16/18 t
    processStdoutBuffer*: string
    when defined(windows):
      outputOverlapped*: OVERLAPPED
      waitingForOvelapped*: bool

  Terminal* = ref object
    id*: int
    group*: string
    command*: string
    thread*: Thread[TerminalThreadState]
    inputChannel*: ptr system.Channel[InputEvent]
    outputChannel*: ptr system.Channel[OutputEvent]
    terminalBuffer*: TerminalBuffer # The latest terminalBuffer received from the terminal thread
    sixels*: seq[tuple[contentHash: Hash, row, col: int, px, py: int, width, height: int]]
    images*: seq[PlacedImage]
    cursor*: tuple[row, col: int, visible: bool, shape: CursorShape, blink: bool] = (0, 0, true, CursorShape.Block, true)
    width*: int # The latest width received from the terminal thread. Might not match 'terminalBuffer' size.
    height*: int # The latest height received from the terminal thread. Might not match 'terminalBuffer' size.
    pixelWidth*: int # The latest pixel width received from the terminal thread. Might not match current view size.
    pixelHeight*: int # The latest pixel height received from the terminal thread. Might not match current view size.
    scrollY*: int
    exitCode*: Option[int]
    autoRunCommand*: string
    createPty*: bool = false
    kittyPathPrefix*: string
    threadTerminated*: bool = false
    relativeScroll*: float
    scrollHeight*: float

    # Events
    lastUpdateTime*: timer.Timer
    lastEventTime*: timer.Timer
    onTerminated*: Event[Option[int]]
    onRope*: Event[ptr Rope]
    onUpdated*: Event[void]

    useChannels*: bool
    handles*: OsHandles

    ssh*: Option[SshOptions]
    when defined(enableLibssh):
      sshChannel*: SSHChannel
      sshClient*: SSHClient

  TerminalView* = ref object of DynamicView
    terminals*: TerminalServiceImpl
    eventHandlers*: Table[string, EventHandler]
    modeEventHandler*: EventHandler
    mode*: string
    size*: tuple[width, height, cellPixelWidth, cellPixelHeight: int] # Current size of the view in cells. Might not match 'terminal.width' and 'terminal.height'
    terminal*: Terminal
    closeOnTerminate*: bool
    slot*: string
    open*: bool = true
    onClick*: proc (view: TerminalView, button: input.MouseButton, pressed: bool, modifiers: Modifiers, col: int, row: int) {.gcsafe, raises: [].}
    onScroll*: proc(view: TerminalView, deltaY: int, modifiers: Modifiers) {.gcsafe, raises: [].}
    onDrag*: proc(view: TerminalView, button: input.MouseButton, col: int, row: int, modifiers: Modifiers) {.gcsafe, raises: [].}
    onMove*: proc(view: TerminalView, col: int, row: int) {.gcsafe, raises: [].}
    isInPreview*: bool = false

  TerminalServiceImpl* = ref object of TerminalService
    events*: EventHandlerService
    config*: ConfigService
    layout*: LayoutService
    themes*: ThemeService
    registers*: Registers
    commands*: CommandService
    idCounter*: int = 0
    settings*: TerminalSettings
    # mPlatform*: Platform

    terminals*: Table[int, TerminalView]
    activeView*: TerminalView
    sixelTextures*: Table[Hash, TextureId]

proc scrollbackBufferLen*(self: TerminalThreadState): int =
  if self.alternateScreen:
    return 0
  return self.scrollbackBuffer.len

proc scrollbackBufferLen*(self: ptr TerminalThreadState): int =
  if self.alternateScreen:
    return 0
  return self.scrollbackBuffer.len
