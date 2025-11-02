# Copy of https://github.com/johnnovak/illwill
#
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                     Version 2, December 2004
#
#  Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
#
#  Everyone is permitted to copy and distribute verbatim or modified
#  copies of this license document, and changing it is allowed as long
#  as the name is changed.
#
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#    TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#   0. You just DO WHAT THE FUCK YOU WANT TO.

## :Authors: John Novak
##
## This is a *curses* inspired simple terminal library that aims to make
## writing cross-platform text mode applications easier. The main features are:
##
## * Non-blocking keyboard input
## * Support for key combinations and special keys available in the standard
##   Windows Console (`cmd.exe`) and most common POSIX terminals
## * Virtual terminal buffers with double-buffering support (only
##   display changes from the previous frame and minimise the number of
##   attribute changes to reduce CPU usage)
## * Simple graphics using UTF-8 box drawing symbols
## * Full-screen support with restoring the contents of the terminal after
##   exit (restoring works only on POSIX)
## * Basic suspend/continue (`SIGTSTP`, `SIGCONT`) support on POSIX
## * Basic mouse support.
##
## The module depends only on the standard `terminal
## <https://nim-lang.org/docs/terminal.html>`_ module. However, you
## should not use any terminal functions directly, neither should you use
## `echo`, `write` or other similar functions for output. You should **only**
## use the interface provided by the module to interact with the terminal.
##
## The following symbols are exported from the terminal_ module (these are
## safe to use):
##
## * `terminalWidth() <https://nim-lang.org/docs/terminal.html#terminalWidth>`_
## * `terminalHeight() <https://nim-lang.org/docs/terminal.html#terminalHeight>`_
## * `terminalSize() <https://nim-lang.org/docs/terminal.html#terminalSize>`_
## * `hideCursor() <https://nim-lang.org/docs/terminal.html#hideCursor.t>`_
## * `showCursor() <https://nim-lang.org/docs/terminal.html#showCursor.t>`_
## * `Style <https://nim-lang.org/docs/terminal.html#Style>`_
##

import macros, terminal, unicode, colors
import misc/[custom_logger]

when defined(posix):
  import os

logCategory "tui"

export terminal.terminalWidth
export terminal.terminalHeight
export terminal.terminalSize
export terminal.hideCursor
export terminal.showCursor
export terminal.Style

const
  fgPrefix = "\e[38;2;"
  bgPrefix = "\e[48;2;"
  stylePrefix = "\e["
  ansiResetCode* = "\e[0m"

type
  ForegroundColor* = enum   ## Foreground colors
    fgNone = 0,             ## default
    fgBlack = 30,           ## black
    fgRed,                  ## red
    fgGreen,                ## green
    fgYellow,               ## yellow
    fgBlue,                 ## blue
    fgMagenta,              ## magenta
    fgCyan,                 ## cyan
    fgWhite                 ## white
    fgRGB                   ## Use fgColor

  BackgroundColor* = enum   ## Background colors
    bgNone = 0,             ## default (transparent)
    bgBlack = 40,           ## black
    bgRed,                  ## red
    bgGreen,                ## green
    bgYellow,               ## yellow
    bgBlue,                 ## blue
    bgMagenta,              ## magenta
    bgCyan,                 ## cyan
    bgWhite                 ## white
    bgRGB                   ## Use bgColor

  IllwillError* = object of CatchableError

var gIllwillInitialised* = false
var gFullScreen* = false
var gFullRedrawNextFrame = false

when defined(windows):
  import winlean

  proc getConsoleMode(hConsoleHandle: Handle, dwMode: ptr DWORD): WINBOOL {.
      stdcall, dynlib: "kernel32", importc: "GetConsoleMode".}

  proc setConsoleMode(hConsoleHandle: Handle, dwMode: DWORD): WINBOOL {.
      stdcall, dynlib: "kernel32", importc: "SetConsoleMode".}

  const
    ENABLE_WRAP_AT_EOL_OUTPUT   = 0x0002

  var gOldConsoleModeInput: DWORD
  var gOldConsoleMode: DWORD

  proc consoleInit*() =
    discard getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), gOldConsoleMode.addr)
    discard getConsoleMode(getStdHandle(STD_INPUT_HANDLE), gOldConsoleModeInput.addr)
    if gFullScreen:
      if getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), gOldConsoleMode.addr) != 0:
        var mode = gOldConsoleMode and (not ENABLE_WRAP_AT_EOL_OUTPUT)
        discard setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode)
    else:
      discard getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), gOldConsoleMode.addr)

  proc consoleDeinit*() =
    if gOldConsoleMode != 0:
      discard setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), gOldConsoleMode)
    if gOldConsoleModeInput != 0:
      discard setConsoleMode(getStdHandle(STD_INPUT_HANDLE), gOldConsoleModeInput)

else:  # OS X & Linux
  import posix, tables, termios
  import strutils

  proc kbhit*(): cint =
    var tv: Timeval
    tv.tv_sec = Time(0)
    tv.tv_usec = 0

    var fds: TFdSet
    FD_ZERO(fds)
    FD_SET(STDIN_FILENO, fds)
    discard select(STDIN_FILENO+1, fds.addr, nil, nil, tv.addr)
    return FD_ISSET(STDIN_FILENO, fds)

  proc consoleInit*()
  proc consoleDeinit*()

  # Adapted from:
  # https://ftp.gnu.org/old-gnu/Manuals/glibc-2.2.3/html_chapter/libc_24.html#SEC499
  proc SIGTSTP_handler(sig: cint) {.noconv.} =
    signal(SIGTSTP, SIG_DFL)
    # XXX why don't the below 3 lines seem to have any effect?
    resetAttributes()
    showCursor()
    consoleDeinit()
    discard posix.raise(SIGTSTP)

  proc SIGCONT_handler(sig: cint) {.noconv.} =
    signal(SIGCONT, SIGCONT_handler)
    signal(SIGTSTP, SIGTSTP_handler)

    gFullRedrawNextFrame = true
    consoleInit()
    hideCursor()

  proc installSignalHandlers() =
    signal(SIGCONT, SIGCONT_handler)
    signal(SIGTSTP, SIGTSTP_handler)

  proc nonblock(enabled: bool) =
    var ttyState: Termios

    # get the terminal state
    discard tcGetAttr(STDIN_FILENO, ttyState.addr)

    if enabled:
      # turn off canonical mode & echo
      ttyState.c_lflag = ttyState.c_lflag and not Cflag(ICANON or ECHO)

      # minimum of number input read
      ttyState.c_cc[VMIN] = 0.cuchar

    else:
      # turn on canonical mode & echo
      ttyState.c_lflag = ttyState.c_lflag or ICANON or ECHO

    # set the terminal attributes.
    discard tcSetAttr(STDIN_FILENO, TCSANOW, ttyState.addr)

  proc consoleInit() =
    nonblock(true)
    installSignalHandlers()

  proc consoleDeinit() =
    nonblock(false)

proc checkInit() =
  if not gIllwillInitialised:
    raise newException(IllwillError, "Illwill not initialised")

type
  TerminalChar* = object
    ## Represents a character in the terminal buffer, including color and
    ## style information.
    ##
    ## If `forceWrite` is set to `true`, the character is always output even
    ## when double buffering is enabled (this is a hack to achieve better
    ## continuity of horizontal lines when using UTF-8 box drawing symbols in
    ## the Windows Console).
    ch*: Rune
    fg*: ForegroundColor
    fgColor*: Color
    bg*: BackgroundColor
    bgColor*: Color
    style*: set[Style]
    forceWrite*: bool
    previousWideGlyph*: bool

  TerminalBuffer* = object
    ## A virtual terminal buffer of a fixed width and height. It remembers the
    ## current color and style settings and the current cursor position.
    ##
    ## Write to the terminal buffer with `TerminalBuffer.write()` or access
    ## the character buffer directly with the index operators.
    ##
    ## Example:
    ##
    ## .. code-block::
    ##   import illwill, unicode
    ##
    ##   # Initialise the console in non-fullscreen mode
    ##   illwillInit(fullscreen=false)
    ##
    ##   # Create a new terminal buffer
    ##   var tb = newTerminalBuffer(terminalWidth(), terminalHeight())
    ##
    ##   # Write the character "X" at position (5,5) then read it back
    ##   tb[5,5] = TerminalChar(ch: "X".runeAt(0), fg: fgYellow, bg: bgNone, style: {})
    ##   let ch = tb[5,5]
    ##
    ##   # Write "foo" at position (10,10) in bright red
    ##   tb.setForegroundColor(fgRed, bright=true)
    ##   tb.setCursorPos(10, 10)
    ##   tb.write("foo")
    ##
    ##   # Write "bar" at position (15,12) in bright red, without changing
    ##   # the current cursor position
    ##   tb.write(15, 12, "bar")
    ##
    ##   tb.write(0, 20, "Normal ", fgYellow, "ESC", fgWhite,
    ##                   " or ", fgYellow, "Q", fgWhite, " to quit")
    ##
    ##   # Output the contents of the buffer to the terminal
    ##   tb.display()
    ##
    ##   # Clean up
    ##   illwillDeinit()
    ##
    width: int
    height: int
    buf: seq[TerminalChar]
    currBg: BackgroundColor
    currBgColor: Color
    currBgAlpha: float
    currFg: ForegroundColor
    currFgColor: Color
    currStyle: set[Style]
    currX: Natural
    currY: Natural

proc `[]=`*(tb: var TerminalBuffer, x, y: Natural, ch: TerminalChar) =
  ## Index operator to write a character into the terminal buffer at the
  ## specified location. Does nothing if the location is outside of the
  ## extents of the terminal buffer.
  if x < tb.width and y < tb.height:
    tb.buf[tb.width * y + x] = ch

proc `[]`*(tb: TerminalBuffer, x, y: Natural): TerminalChar =
  ## Index operator to read a character from the terminal buffer at the
  ## specified location. Returns nil if the location is outside of the extents
  ## of the terminal buffer.
  if x < tb.width and y < tb.height:
    result = tb.buf[tb.width * y + x]


proc fill*(tb: var TerminalBuffer, x1, y1, x2, y2: int, ch: string = " ") =
  ## Fills a rectangular area with the `ch` character using the current text
  ## attributes. The rectangle is clipped to the extends of the terminal
  ## buffer and the call can never fail.
  if x1 < tb.width and y1 < tb.height:
    let
      c = TerminalChar(ch: ch.runeAt(0), fg: tb.currFg, bg: tb.currBg, fgColor: tb.currFgColor, bgColor: tb.currBgColor, style: tb.currStyle)

      xs = clamp(x1, 0, tb.width-1)
      ys = clamp(y1, 0, tb.width-1)
      xe = clamp(x2, 0, tb.width-1)
      ye = clamp(y2, 0, tb.height-1)

    for y in ys..ye:
      for x in xs..xe:
        tb[x, y] = c

func blend(a, b: Color, alpha: float): Color =
  let (r1, g1, b1) = a.extractRGB()
  let (r2, g2, b2) = b.extractRGB()
  let r = (r1.float * alpha + r2.float * (1 - alpha)).clamp(0, 255).int
  let g = (g1.float * alpha + g2.float * (1 - alpha)).clamp(0, 255).int
  let b = (b1.float * alpha + b2.float * (1 - alpha)).clamp(0, 255).int
  result = rgb(r, g, b)

proc fillBackground*(tb: var TerminalBuffer, x1, y1, x2, y2: int) =
  ## Fills a rectangular area with the `ch` character using the current text
  ## attributes. The rectangle is clipped to the extends of the terminal
  ## buffer and the call can never fail.
  if x1 < tb.width and y1 < tb.height:
    let
      xs = clamp(x1, 0, tb.width-1)
      ys = clamp(y1, 0, tb.width-1)
      xe = clamp(x2, 0, tb.width-1)
      ye = clamp(y2, 0, tb.height-1)

    for y in ys..ye:
      if xs > 0 and tb[xs, y].previousWideGlyph:
        # Current cell is after a wide unicode char, so also override the prev cell with space
        var prevCell = tb[xs - 1, y]
        prevCell.ch = ' '.Rune
        tb[xs - 1, y] = prevCell

      for x in xs..xe:
        var c = tb[x, y]
        if tb.currBgAlpha == 1 or c.ch.int == 0:
          c.ch = ' '.Rune
        c.bg = tb.currBg
        c.bgColor = blend(tb.currBgColor, c.bgColor, tb.currBgAlpha)
        c.previousWideGlyph = false
        tb[x, y] = c

      if xe + 1 < tb.width and tb[xe + 1, y].previousWideGlyph:
        # Current cell is a wide unicode char, so also override the next cell with space
        var nextCell = tb[xe + 1, y]
        nextCell.ch = ' '.Rune
        nextCell.previousWideGlyph = false
        tb[xe + 1, y] = nextCell

proc clear*(tb: var TerminalBuffer, ch: string = " ") =
  ## Clears the contents of the terminal buffer with the `ch` character using
  ## the `fgNone` and `bgNone` attributes.
  tb.fill(0, 0, tb.width-1, tb.height-1, ch)

proc initTerminalBuffer*(tb: var TerminalBuffer, width, height: Natural) =
  ## Initializes a new terminal buffer object of a fixed `width` and `height`.
  tb.width = width
  tb.height = height
  newSeq(tb.buf, width * height)
  tb.currBg = bgNone
  tb.currFg = fgNone
  tb.currStyle = {}

proc newTerminalBuffer*(width, height: Natural): ref TerminalBuffer =
  ## Creates a new terminal buffer of a fixed `width` and `height`.
  var tb = new TerminalBuffer
  tb[].initTerminalBuffer(width, height)
  tb[].clear()
  result = tb

func width*(tb: TerminalBuffer): Natural =
  ## Returns the width of the terminal buffer.
  result = tb.width

func height*(tb: TerminalBuffer): Natural =
  ## Returns the height of the terminal buffer.
  result = tb.height


proc copyFrom*(tb: var TerminalBuffer,
               src: TerminalBuffer, srcX, srcY, width, height: Natural,
               destX, destY: Natural) =
  ## Copies the contents of the `src` terminal buffer into this one.
  ## A rectangular area of dimension `width` and `height` is copied from
  ## the position `srcX` and `srcY` in the source buffer to the position
  ## `destX` and `destY` in this buffer.
  ##
  ## If the extents of the area to be copied lie outside the extents of the
  ## buffers, the copied area will be clipped to the available area (in other
  ## words, the call can never fail; in the worst case it just copies
  ## nothing).
  let
    srcWidth = max(src.width - srcX, 0)
    srcHeight = max(src.height - srcY, 0)
    destWidth = max(tb.width - destX, 0)
    destHeight = max(tb.height - destY, 0)
    w = min(min(srcWidth, destWidth), width)
    h = min(min(srcHeight, destHeight), height)

  for yOffs in 0..<h:
    for xOffs in 0..<w:
      tb[xOffs + destX, yOffs + destY] = src[xOffs + srcX, yOffs + srcY]


proc copyFrom*(tb: var TerminalBuffer, src: TerminalBuffer) =
  ## Copies the full contents of the `src` terminal buffer into this one.
  ##
  ## If the extents of the source buffer is greater than the extents of the
  ## destination buffer, the copied area is clipped to the destination area.
  tb.copyFrom(src, 0, 0, src.width, src.height, 0, 0)

proc newTerminalBufferFrom*(src: TerminalBuffer): ref TerminalBuffer =
  ## Creates a new terminal buffer with the dimensions of the `src` buffer and
  ## copies its contents into the new buffer.
  var tb = new TerminalBuffer
  tb[].initTerminalBuffer(src.width, src.height)
  tb[].copyFrom(src)
  result = tb

proc setCursorPos*(tb: var TerminalBuffer, x, y: Natural) =
  ## Sets the current cursor position.
  tb.currX = x
  tb.currY = y

proc setCursorXPos*(tb: var TerminalBuffer, x: Natural) =
  ## Sets the current x cursor position.
  tb.currX = x

proc setCursorYPos*(tb: var TerminalBuffer, y: Natural) =
  ## Sets the current y cursor position.
  tb.currY = y

proc setBackgroundColor*(tb: var TerminalBuffer, bg: BackgroundColor) =
  ## Sets the current background color.
  tb.currBg = bg
  tb.currBgAlpha = 1

proc setForegroundColor*(tb: var TerminalBuffer, fg: ForegroundColor,
                         bright: bool = false) =
  ## Sets the current foreground color and the bright style flag.
  if bright:
    incl(tb.currStyle, styleBright)
  else:
    excl(tb.currStyle, styleBright)
  tb.currFg = fg

proc setForegroundColor*(tb: var TerminalBuffer, fg: Color) =
  ## Sets the current foreground color and the bright style flag.
  tb.currFg = fgRGB
  tb.currFgColor = fg

proc setBackgroundColor*(tb: var TerminalBuffer, bg: Color, alpha: float = 1) =
  ## Sets the current foreground color and the bright style flag.
  if alpha == 0:
    # debugf"setting background color to none"
    tb.currBg = bgNone
  else:
    tb.currBg = bgRGB
    tb.currBgColor = bg
    tb.currBgAlpha = alpha

proc setTrueForegroundColor*(color: Color) =
  ## Sets the terminal's foreground true color.
  stdout.write(ansiForegroundColorCode(color))

proc setTrueBackgroundColor*(color: Color) =
  ## Sets the terminal's background true color.
  stdout.write(ansiBackgroundColorCode(color))

when defined(windows):
  const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
  const ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200
  const ENABLE_LINE_INPUT = 0x0002
  const ENABLE_ECHO_INPUT = 0x0004

proc enableVirtualTerminalInput*() =
  ## Enables true color.
  when defined(windows):
    var mode: DWORD = 0
    if getConsoleMode(getStdHandle(STD_INPUT_HANDLE), addr(mode)) != 0:
      mode = (mode or ENABLE_VIRTUAL_TERMINAL_INPUT) and not (ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT)
      discard setConsoleMode(getStdHandle(STD_INPUT_HANDLE), mode) != 0

proc disableVirtualTerminalInput*() =
  ## Disables true color.
  when defined(windows):
    var mode: DWORD = 0
    if getConsoleMode(getStdHandle(STD_INPUT_HANDLE), addr(mode)) != 0:
      mode = (mode and not ENABLE_VIRTUAL_TERMINAL_INPUT) or ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT
      discard setConsoleMode(getStdHandle(STD_INPUT_HANDLE), mode)

proc myEnableTrueColors*(): bool =
  ## Enables true color.
  result = false
  when defined(windows):
    var mode: DWORD = 0
    if getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), addr(mode)) != 0:
      mode = mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING
      result = setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode) != 0
  else:
    result = getEnv("COLORTERM").toLowerAscii() in ["truecolor", "24bit"]

proc myDisableTrueColors*() =
  ## Disables true color.
  when defined(windows):
    var mode: DWORD = 0
    if getConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), addr(mode)) != 0:
      mode = mode and not ENABLE_VIRTUAL_TERMINAL_PROCESSING
      discard setConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode)

proc setStyle*(tb: var TerminalBuffer, style: set[Style]) =
  ## Sets the current style flags.
  tb.currStyle = style

func getCursorPos*(tb: TerminalBuffer): tuple[x: Natural, y: Natural] =
  ## Returns the current cursor position.
  result = (tb.currX, tb.currY)

func getCursorXPos*(tb: TerminalBuffer): Natural =
  ## Returns the current x cursor position.
  result = tb.currX

func getCursorYPos*(tb: TerminalBuffer): Natural =
  ## Returns the current y cursor position.
  result = tb.currY

func getBackgroundColor*(tb: var TerminalBuffer): BackgroundColor =
  ## Returns the current background color.
  result = tb.currBg

func getForegroundColor*(tb: var TerminalBuffer): ForegroundColor =
  ## Returns the current foreground color.
  result = tb.currFg

func getStyle*(tb: var TerminalBuffer): set[Style] =
  ## Returns the current style flags.
  result = tb.currStyle

proc resetAttributes*(tb: var TerminalBuffer) =
  ## Resets the current text attributes to `bgNone`, `fgWhite` and clears
  ## all style flags.
  tb.setBackgroundColor(bgNone)
  tb.setForegroundColor(fgWhite)
  tb.setStyle({})

proc write*(tb: var TerminalBuffer, x, y: int, s: string) =
  ## Writes `s` into the terminal buffer at the specified position using
  ## the current text attributes. Lines do not wrap and attempting to write
  ## outside the extents of the buffer will not raise an error; the output
  ## will be just cropped to the extents of the buffer.
  if y < 0 or y >= tb.height:
    return
  var currX = x
  for ch in runes(s):
    var c = TerminalChar(ch: ch, fg: tb.currFg, bg: tb.currBg, fgColor: tb.currFgColor, bgColor: tb.currBgColor, style: tb.currStyle)
    if currX >= 0 and currX < tb.width:
      if c.fg == fgNone:
        c.fg = tb[currX, y].fg
        c.fgColor = tb[currX, y].fgColor
      if c.bg == bgNone:
        c.bg = tb[currX, y].bg
        c.bgColor = tb[currX, y].bgColor
      tb[currX, y] = c
    inc(currX)
  tb.currX = clamp(currX, 0, tb.width-1)
  tb.currY = y

proc writeRune*(tb: var TerminalBuffer, x, y: int, ch: Rune, width: int, additionalWidth: int, italic: bool) =
  ## Writes `ch` into the terminal buffer at the specified position using
  ## the current text attributes.
  ## `width` is the amount of cells `ch` occupies, `additionalWidth` is the number of spaces that should be
  ## inserted after `ch`.
  ## Lines do not wrap and attempting to write
  ## outside the extents of the buffer will not raise an error; the output
  ## will be just cropped to the extents of the buffer.
  if y < 0 or y >= tb.height:
    return

  var c = TerminalChar(ch: ch, fg: tb.currFg, bg: tb.currBg, fgColor: tb.currFgColor, bgColor: tb.currBgColor, style: tb.currStyle)
  if italic:
    c.style.incl styleItalic
  if x >= 0 and x < tb.width:
    if x > 0 and tb[x, y].previousWideGlyph:
      # Current cell is after a wide unicode char, so also override the prev cell with space
      var prevCell = tb[x - 1, y]
      prevCell.ch = ' '.Rune
      tb[x - 1, y] = prevCell

    if c.fg == fgNone:
      c.fg = tb[x, y].fg
      c.fgColor = tb[x, y].fgColor
    if c.bg == bgNone:
      c.bg = tb[x, y].bg
      c.bgColor = tb[x, y].bgColor
    tb[x, y] = c

    var xEnd = x

    # Set (`width` - 1) cells after the current one to space
    for x2 in (x + 1)..<min(tb.width, x + width):
      var c = c
      c.ch = 0.Rune
      c.previousWideGlyph = true
      tb[x2, y] = c
      xEnd = max(x2, xEnd)

    # Set `additionalWidth` cells after the current one to space
    for x2 in (x + 1)..<min(tb.width, x + additionalWidth + 1):
      var c = c
      c.ch = ' '.Rune
      c.previousWideGlyph = true
      tb[x2, y] = c
      xEnd = max(x2, xEnd)

    if xEnd + 1 < tb.width and tb[xEnd + 1, y].previousWideGlyph:
      # Current cell is a wide unicode char, so also override the next cell with space
      var nextCell = tb[xEnd + 1, y]
      nextCell.ch = ' '.Rune
      nextCell.previousWideGlyph = false
      tb[xEnd + 1, y] = nextCell

  tb.currX = clamp(x + 2, 0, tb.width-1)
  tb.currY = y

proc write*(tb: var TerminalBuffer, s: string) =
  ## Writes `s` into the terminal buffer at the current cursor position using
  ## the current text attributes.
  write(tb, tb.currX, tb.currY, s)

var
  gPrevTerminalBuffer {.threadvar.}: ref TerminalBuffer
  gCurrBg {.threadvar.}: BackgroundColor
  gCurrBgColor {.threadvar.}: Color
  gCurrFg {.threadvar.}: ForegroundColor
  gCurrFgColor {.threadvar.}: Color
  gCurrStyle {.threadvar.}: set[Style]

proc setAttribs(buffer: var string, c: TerminalChar) =
  if c.bg == bgNone or c.fg == fgNone or c.style == {}:
    buffer.add ansiResetCode
    gCurrBg = bgNone
    gCurrFg = fgNone
    gCurrStyle = {}

  if c.bg != gCurrBg or c.bgColor != gCurrBgColor:
    gCurrBg = c.bg
    gCurrBgColor = c.bgColor

    case gCurrBg
    of bgNone: discard
    of bgRGB:
      let rgb = c.bgColor.extractRGB
      buffer.add bgPrefix
      buffer.add $rgb.r
      buffer.add ";"
      buffer.add $rgb.g
      buffer.add ";"
      buffer.add $rgb.b
      buffer.add "m"

    else: discard

  if c.fg != gCurrFg or c.fgColor != gCurrFgColor:
    gCurrFg = c.fg
    gCurrFgColor = c.fgColor
    case gCurrFg
    of fgNone: discard
    of fgRGB:
      let rgb = c.fgColor.extractRGB
      buffer.add fgPrefix
      buffer.add $rgb.r
      buffer.add ";"
      buffer.add $rgb.g
      buffer.add ";"
      buffer.add $rgb.b
      buffer.add "m"

    else: discard

  if c.style != gCurrStyle:
    gCurrStyle = c.style
    for s in gCurrStyle:
      buffer.add stylePrefix
      buffer.add $s.int
      buffer.add "m"

var displayBuffer = ""

proc flushDisplayBuffer() =
  if displayBuffer.len > 0:
    stdout.write displayBuffer
    displayBuffer.setLen 0

proc setPos(buffer: var string, x: int, y: int) =
  buffer.add "\e["
  buffer.add $(y + 1)
  buffer.add ";"
  buffer.add $(x + 1)
  buffer.add "f"

proc displayFull*(tb: TerminalBuffer) =
  for y in 0..<tb.height:
    displayBuffer.setPos(0, y)

    var additionalSpaces = 0
    for x in 0..<tb.width:
      let c {.cursor.} = tb[x,y]
      if c.ch == 0.Rune:
        inc additionalSpaces
        continue

      if c.bg != gCurrBg or c.fg != gCurrFg or c.bgColor != gCurrBgColor or c.fgColor != gCurrFgColor or c.style != gCurrStyle:
        displayBuffer.setAttribs(c)

      displayBuffer.add $c.ch

    when defined(windows):
      # For some reason windows terminal doesn't update the cells at the end if there's a bunch of unicode in the line
      # Adding a bunch of whitespace at the end fixes it.
      # I don't know if this also happens in other terminals.
      displayBuffer.add "                                                                   "
      displayBuffer.add ' '.Rune.repeat(additionalSpaces)

  flushDisplayBuffer()
  stdout.flushFile()

proc displayDiff(tb: TerminalBuffer) =
  var bufXPos, bufYPos: int

  bufXPos = -1
  bufYPos = -1

  for y in 0..<tb.height:
    var containsWideGlyph = false
    var anyChanged = false

    # Force redraw the entire line if the line contains or used to contain wide glyphs,
    # and anything in the line changed.
    # This is because terminals/terminal multiplexers can't deal or deal differently with wide glyphs
    # in the case of partial updates.
    for x in 0..<tb.width:
      if x + 1 < tb.width:
        if tb[x + 1, y].previousWideGlyph or gPrevTerminalBuffer[][x + 1, y].previousWideGlyph:
          containsWideGlyph = true
      if tb[x, y] != gPrevTerminalBuffer[][x, y]:
        anyChanged = true
      if containsWideGlyph and anyChanged:
        break

    let force = containsWideGlyph and anyChanged

    var additionalSpaces = 0
    if force:
      displayBuffer.setPos(0, y)
      for x in 0..<tb.width:
        let c {.cursor.} = tb[x,y]
        defer:
          gPrevTerminalBuffer[][x, y] = c

        if c.ch == 0.Rune:
          inc additionalSpaces
          continue

        if c.bg != gCurrBg or c.fg != gCurrFg or c.bgColor != gCurrBgColor or c.fgColor != gCurrFgColor or c.style != gCurrStyle:
          displayBuffer.setAttribs(c)

        displayBuffer.add c.ch

      when defined(windows):
        # For some reason windows terminal doesn't update the cells at the end if there's a bunch of unicode in the line
        # Adding a bunch of whitespace at the end fixes it.
        # I don't know if this also happens in other terminals.
        displayBuffer.add "                                                                   "
        displayBuffer.add ' '.Rune.repeat(additionalSpaces)

    else:
      for x in 0..<tb.width:
        let c {.cursor.} = tb[x, y]
        defer:
          gPrevTerminalBuffer[][x, y] = c

        if c.ch == 0.Rune:
          inc additionalSpaces
          continue

        if c == gPrevTerminalBuffer[][x, y]:
          continue

        if y != bufYPos or x != bufXPos:
          bufXPos = x
          bufYPos = y
          displayBuffer.setPos(x, y)
          displayBuffer.setAttribs(c)

        if c.bg != gCurrBg or c.fg != gCurrFg or c.bgColor != gCurrBgColor or c.fgColor != gCurrFgColor or c.style != gCurrStyle:
          displayBuffer.setAttribs(c)

        displayBuffer.add c.ch
        inc bufXPos

  flushDisplayBuffer()
  stdout.flushFile()

var gDoubleBufferingEnabled = true

proc setDoubleBuffering*(enabled: bool) =
  ## Enables or disables double buffering (enabled by default).
  gDoubleBufferingEnabled = enabled
  gPrevTerminalBuffer = nil

proc hasDoubleBuffering*(): bool =
  ## Returns `true` if double buffering is enabled.
  ##
  ## If the module is not intialised, `IllwillError` is raised.
  checkInit()
  result = gDoubleBufferingEnabled

proc display*(tb: TerminalBuffer) =
  ## Outputs the contents of the terminal buffer to the actual terminal.
  ##
  ## If the module is not intialised, `IllwillError` is raised.
  checkInit()
  if not gFullRedrawNextFrame and gDoubleBufferingEnabled:
    if gPrevTerminalBuffer == nil:
      displayFull(tb)
      gPrevTerminalBuffer = newTerminalBufferFrom(tb)
    else:
      if tb.width == gPrevTerminalBuffer.width and
         tb.height == gPrevTerminalBuffer.height:
        displayDiff(tb)
      else:
        displayFull(tb)
        gPrevTerminalBuffer = newTerminalBufferFrom(tb)
    flushFile(stdout)
  else:
    displayFull(tb)
    flushFile(stdout)
    gFullRedrawNextFrame = false

type BoxChar = int

const
  LEFT   = 0x01
  RIGHT  = 0x02
  UP     = 0x04
  DOWN   = 0x08
  H_DBL  = 0x10
  V_DBL  = 0x20

  HORIZ = LEFT or RIGHT
  VERT  = UP or DOWN

var gBoxCharsUnicode {.threadvar.}: array[64, string]

gBoxCharsUnicode[0] = " "

gBoxCharsUnicode[   0 or  0 or     0 or    0] = " "
gBoxCharsUnicode[   0 or  0 or     0 or LEFT] = "─"
gBoxCharsUnicode[   0 or  0 or RIGHT or    0] = "─"
gBoxCharsUnicode[   0 or  0 or RIGHT or LEFT] = "─"
gBoxCharsUnicode[   0 or UP or     0 or    0] = "│"
gBoxCharsUnicode[   0 or UP or     0 or LEFT] = "┘"
gBoxCharsUnicode[   0 or UP or RIGHT or    0] = "└"
gBoxCharsUnicode[   0 or UP or RIGHT or LEFT] = "┴"
gBoxCharsUnicode[DOWN or  0 or     0 or    0] = "│"
gBoxCharsUnicode[DOWN or  0 or     0 or LEFT] = "┐"
gBoxCharsUnicode[DOWN or  0 or RIGHT or    0] = "┌"
gBoxCharsUnicode[DOWN or  0 or RIGHT or LEFT] = "┬"
gBoxCharsUnicode[DOWN or UP or     0 or    0] = "│"
gBoxCharsUnicode[DOWN or UP or     0 or LEFT] = "┤"
gBoxCharsUnicode[DOWN or UP or RIGHT or    0] = "├"
gBoxCharsUnicode[DOWN or UP or RIGHT or LEFT] = "┼"

gBoxCharsUnicode[H_DBL or    0 or  0 or     0 or    0] = " "
gBoxCharsUnicode[H_DBL or    0 or  0 or     0 or LEFT] = "═"
gBoxCharsUnicode[H_DBL or    0 or  0 or RIGHT or    0] = "═"
gBoxCharsUnicode[H_DBL or    0 or  0 or RIGHT or LEFT] = "═"
gBoxCharsUnicode[H_DBL or    0 or UP or     0 or    0] = "│"
gBoxCharsUnicode[H_DBL or    0 or UP or     0 or LEFT] = "╛"
gBoxCharsUnicode[H_DBL or    0 or UP or RIGHT or    0] = "╘"
gBoxCharsUnicode[H_DBL or    0 or UP or RIGHT or LEFT] = "╧"
gBoxCharsUnicode[H_DBL or DOWN or  0 or     0 or    0] = "│"
gBoxCharsUnicode[H_DBL or DOWN or  0 or     0 or LEFT] = "╕"
gBoxCharsUnicode[H_DBL or DOWN or  0 or RIGHT or    0] = "╒"
gBoxCharsUnicode[H_DBL or DOWN or  0 or RIGHT or LEFT] = "╤"
gBoxCharsUnicode[H_DBL or DOWN or UP or     0 or    0] = "│"
gBoxCharsUnicode[H_DBL or DOWN or UP or     0 or LEFT] = "╡"
gBoxCharsUnicode[H_DBL or DOWN or UP or RIGHT or    0] = "╞"
gBoxCharsUnicode[H_DBL or DOWN or UP or RIGHT or LEFT] = "╪"

gBoxCharsUnicode[V_DBL or    0 or  0 or     0 or    0] = " "
gBoxCharsUnicode[V_DBL or    0 or  0 or     0 or LEFT] = "─"
gBoxCharsUnicode[V_DBL or    0 or  0 or RIGHT or    0] = "─"
gBoxCharsUnicode[V_DBL or    0 or  0 or RIGHT or LEFT] = "─"
gBoxCharsUnicode[V_DBL or    0 or UP or     0 or    0] = "║"
gBoxCharsUnicode[V_DBL or    0 or UP or     0 or LEFT] = "╜"
gBoxCharsUnicode[V_DBL or    0 or UP or RIGHT or    0] = "╙"
gBoxCharsUnicode[V_DBL or    0 or UP or RIGHT or LEFT] = "╨"
gBoxCharsUnicode[V_DBL or DOWN or  0 or     0 or    0] = "║"
gBoxCharsUnicode[V_DBL or DOWN or  0 or     0 or LEFT] = "╖"
gBoxCharsUnicode[V_DBL or DOWN or  0 or RIGHT or    0] = "╓"
gBoxCharsUnicode[V_DBL or DOWN or  0 or RIGHT or LEFT] = "╥"
gBoxCharsUnicode[V_DBL or DOWN or UP or     0 or    0] = "║"
gBoxCharsUnicode[V_DBL or DOWN or UP or     0 or LEFT] = "╢"
gBoxCharsUnicode[V_DBL or DOWN or UP or RIGHT or    0] = "╟"
gBoxCharsUnicode[V_DBL or DOWN or UP or RIGHT or LEFT] = "╫"

gBoxCharsUnicode[H_DBL or V_DBL or    0 or  0 or     0 or    0] = " "
gBoxCharsUnicode[H_DBL or V_DBL or    0 or  0 or     0 or LEFT] = "═"
gBoxCharsUnicode[H_DBL or V_DBL or    0 or  0 or RIGHT or    0] = "═"
gBoxCharsUnicode[H_DBL or V_DBL or    0 or  0 or RIGHT or LEFT] = "═"
gBoxCharsUnicode[H_DBL or V_DBL or    0 or UP or     0 or    0] = "║"
gBoxCharsUnicode[H_DBL or V_DBL or    0 or UP or     0 or LEFT] = "╝"
gBoxCharsUnicode[H_DBL or V_DBL or    0 or UP or RIGHT or    0] = "╚"
gBoxCharsUnicode[H_DBL or V_DBL or    0 or UP or RIGHT or LEFT] = "╩"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or  0 or     0 or    0] = "║"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or  0 or     0 or LEFT] = "╗"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or  0 or RIGHT or    0] = "╔"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or  0 or RIGHT or LEFT] = "╦"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or UP or     0 or    0] = "║"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or UP or     0 or LEFT] = "╣"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or UP or RIGHT or    0] = "╠"
gBoxCharsUnicode[H_DBL or V_DBL or DOWN or UP or RIGHT or LEFT] = "╬"

proc toUTF8String(c: BoxChar): string = gBoxCharsUnicode[c]

type BoxBuffer* = ref object
  ## Box buffers are used to store the results of multiple consecutive box
  ## drawing calls. The idea is that when you draw a series of lines and
  ## rectangles into the buffer, the overlapping lines will get automatically
  ## connected by placing the appropriate UTF-8 symbols at the corner and
  ## junction points. The results can then be written to a terminal buffer.
  width: Natural
  height: Natural
  buf: seq[BoxChar]

proc newBoxBuffer*(width, height: Natural): BoxBuffer =
  ## Creates a new box buffer of a fixed `width` and `height`.
  result = new BoxBuffer
  result.width = width
  result.height = height
  newSeq(result.buf, width * height)

func width*(bb: BoxBuffer): Natural =
  ## Returns the width of the box buffer.
  result = bb.width

func height*(bb: BoxBuffer): Natural =
  ## Returns the height of the box buffer.
  result = bb.height

proc `[]=`(bb: var BoxBuffer, x, y: Natural, c: BoxChar) =
  if x < bb.width and y < bb.height:
    bb.buf[bb.width * y + x] = c

func `[]`(bb: BoxBuffer, x, y: Natural): BoxChar =
  if x < bb.width and y < bb.height:
    result = bb.buf[bb.width * y + x]

proc copyFrom*(bb: var BoxBuffer,
               src: BoxBuffer, srcX, srcY, width, height: Natural,
               destX, destY: Natural) =
  ## Copies the contents of the `src` box buffer into this one.
  ## A rectangular area of dimension `width` and `height` is copied from
  ## the position `srcX` and `srcY` in the source buffer to the position
  ## `destX` and `destY` in this buffer.
  ##
  ## If the extents of the area to be copied lie outside the extents of the
  ## buffers, the copied area will be clipped to the available area (in other
  ## words, the call can never fail; in the worst case it just copies
  ## nothing).
  let
    srcWidth = max(src.width - srcX, 0)
    srcHeight = max(src.height - srcY, 0)
    destWidth = max(bb.width - destX, 0)
    destHeight = max(bb.height - destY, 0)
    w = min(min(srcWidth, destWidth), width)
    h = min(min(srcHeight, destHeight), height)

  for yOffs in 0..<h:
    for xOffs in 0..<w:
      bb[xOffs + destX, yOffs + destY] = src[xOffs + srcX, yOffs + srcY]


proc copyFrom*(bb: var BoxBuffer, src: BoxBuffer) =
  ## Copies the full contents of the `src` box buffer into this one.
  ##
  ## If the extents of the source buffer is greater than the extents of the
  ## destination buffer, the copied area is clipped to the destination area.
  bb.copyFrom(src, 0, 0, src.width, src.height, 0, 0)

proc newBoxBufferFrom*(src: BoxBuffer): BoxBuffer =
  ## Creates a new box buffer with the dimensions of the `src` buffer and
  ## copies its contents into the new buffer.
  var bb = new BoxBuffer
  bb.copyFrom(src)
  result = bb

proc drawHorizLine*(bb: var BoxBuffer, x1, x2, y: int,
                    doubleStyle: bool = false, connect: bool = true) =
  ## Draws a horizontal line into the box buffer. Set `doubleStyle` to `true`
  ## to draw double lines. Set `connect` to `true` to connect overlapping
  ## lines.
  if y < 0 or y >= bb.height: return
  var xStart = x1
  var xEnd = x2
  if xStart > xEnd: swap(xStart, xEnd)
  if xStart >= bb.width: return

  xStart = clamp(xStart, 0, bb.width-1)
  xEnd = clamp(xEnd, 0, bb.width-1)
  if connect:
    for x in xStart..xEnd:
      var c = bb[x,y]
      var h: int
      if x == xStart:
        h = if (c and LEFT) > 0: HORIZ else: RIGHT
      elif x == xEnd:
        h = if (c and RIGHT) > 0: HORIZ else: LEFT
      else:
        h = HORIZ
      if doubleStyle: h = h or H_DBL
      bb[x,y] = c or h
  else:
    for x in xStart..xEnd:
      var h = HORIZ
      if doubleStyle: h = h or H_DBL
      bb[x,y] = h


proc drawVertLine*(bb: var BoxBuffer, x, y1, y2: int,
                   doubleStyle: bool = false, connect: bool = true) =
  ## Draws a vertical line into the box buffer. Set `doubleStyle` to `true` to
  ## draw double lines. Set `connect` to `true` to connect overlapping lines.
  if x < 0 or x >= bb.width: return
  var yStart = y1
  var yEnd = y2
  if yStart > yEnd: swap(yStart, yEnd)
  if yStart >= bb.height: return

  yStart = clamp(yStart, 0, bb.height-1)
  yEnd = clamp(yEnd, 0, bb.height-1)
  if connect:
    for y in yStart..yEnd:
      var c = bb[x,y]
      var v: int
      if y == yStart:
        v = if (c and UP) > 0: VERT else: DOWN
      elif y == yEnd:
        v = if (c and DOWN) > 0: VERT else: UP
      else:
        v = VERT
      if doubleStyle: v = v or V_DBL
      bb[x,y] = c or v
  else:
    for y in yStart..yEnd:
      var v = VERT
      if doubleStyle: v = v or V_DBL
      bb[x,y] = v


proc drawRect*(bb: var BoxBuffer, x1, y1, x2, y2: int,
               doubleStyle: bool = false, connect: bool = true) =
  ## Draws a rectangle into the box buffer. Set `doubleStyle` to `true` to
  ## draw double lines. Set `connect` to `true` to connect overlapping lines.
  if abs(x1-x2) < 1 or abs(y1-y2) < 1: return

  if connect:
    bb.drawHorizLine(x1, x2, y1, doubleStyle)
    bb.drawHorizLine(x1, x2, y2, doubleStyle)
    bb.drawVertLine(x1, y1, y2, doubleStyle)
    bb.drawVertLine(x2, y1, y2, doubleStyle)
  else:
    bb.drawHorizLine(x1+1, x2-1, y1, doubleStyle, connect = false)
    bb.drawHorizLine(x1+1, x2-1, y2, doubleStyle, connect = false)
    bb.drawVertLine(x1, y1+1, y2-1, doubleStyle, connect = false)
    bb.drawVertLine(x2, y1+1, y2-1, doubleStyle, connect = false)

    var c = RIGHT or DOWN
    if doubleStyle: c = c or V_DBL or H_DBL
    bb[x1,y1] = c

    c = LEFT or DOWN
    if doubleStyle: c = c or V_DBL or H_DBL
    bb[x2,y1] = c

    c = RIGHT or UP
    if doubleStyle: c = c or V_DBL or H_DBL
    bb[x1,y2] = c

    c = LEFT or UP
    if doubleStyle: c = c or V_DBL or H_DBL
    bb[x2,y2] = c


proc write*(tb: var TerminalBuffer, bb: var BoxBuffer) =
  ## Writes the contents of the box buffer into this terminal buffer with
  ## the current text attributes.
  let width = min(tb.width, bb.width)
  let height = min(tb.height, bb.height)
  var horizBoxCharCount: int
  var forceWrite: bool

  for y in 0..<height:
    horizBoxCharCount = 0
    forceWrite = false
    for x in 0..<width:
      let boxChar = bb[x,y]
      if boxChar > 0:
        if ((boxChar and LEFT) or (boxChar and RIGHT)) > 0:
          if horizBoxCharCount == 1:
            var prev = tb[x-1,y]
            prev.forceWrite = true
            tb[x-1,y] = prev
          if horizBoxCharCount >= 1:
            forceWrite = true
          inc(horizBoxCharCount)
        else:
          horizBoxCharCount = 0
          forceWrite = false

        var c = TerminalChar(ch: toUTF8String(boxChar).runeAt(0),
                             fg: tb.currFg, bg: tb[x, y].bg,
                             fgColor: tb.currFgColor, bgColor: tb[x, y].bgColor,
                             style: tb.currStyle, forceWrite: forceWrite)
        tb[x,y] = c


type
  TerminalCmd* = enum  ## commands that can be expressed as arguments
    resetStyle         ## reset attributes

template writeProcessArg(tb: var TerminalBuffer, s: string) =
  tb.write(s)

template writeProcessArg(tb: var TerminalBuffer, style: Style) =
  tb.setStyle({style})

template writeProcessArg(tb: var TerminalBuffer, style: set[Style]) =
  tb.setStyle(style)

template writeProcessArg(tb: var TerminalBuffer, color: ForegroundColor) =
  tb.setForegroundColor(color)

template writeProcessArg(tb: var TerminalBuffer, color: BackgroundColor) =
  tb.setBackgroundColor(color)

template writeProcessArg(tb: var TerminalBuffer, cmd: TerminalCmd) =
  when cmd == resetStyle:
    tb.resetAttributes()

macro write*(tb: var TerminalBuffer, args: varargs[typed]): untyped =
  ## Special version of `write` that allows to intersperse text literals with
  ## set attribute commands.
  ##
  ## Example:
  ##
  ## .. code-block::
  ##   import illwill
  ##
  ##   illwillInit(fullscreen=false)
  ##
  ##   var tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  ##
  ##   tb.setForegroundColor(fgGreen)
  ##   tb.setBackgroundColor(bgBlue)
  ##   tb.write(0, 10, "before")
  ##
  ##   tb.write(0, 11, "unchanged", resetStyle, fgYellow, "yellow", bgRed, "red bg",
  ##                   styleBlink, "blink", resetStyle, "reset")
  ##
  ##   tb.write(0, 12, "after")
  ##
  ##   tb.display()
  ##
  ##   illwillDeinit()
  ##
  ## This will output the following:
  ##
  ## * 1st row:
  ##   - `before` with blue background, green foreground and default style
  ## * 2nd row:
  ##   - `unchanged` with blue background, green foreground and default style
  ##   - `yellow` with default background, yellow foreground and default style
  ##   - `red bg` with red background, yellow foreground and default style
  ##   - `blink` with red background, yellow foreground and blink style (if
  ##     supported by the terminal)
  ##   - `reset` with the default background and foreground and default style
  ## * 3rd row:
  ##   - `after` with the default background and foreground and default style
  ##
  ##
  result = newNimNode(nnkStmtList)

  if args.len >= 3 and
     args[0].typeKind() == ntyInt and args[1].typeKind() == ntyInt:

    let x = args[0]
    let y = args[1]
    result.add(newCall(bindSym"setCursorPos", tb, x, y))
    for i in 2..<args.len:
      let item = args[i]
      result.add(newCall(bindSym"writeProcessArg", tb, item))
  else:
    for item in args.items:
      result.add(newCall(bindSym"writeProcessArg", tb, item))


proc drawHorizLine*(tb: var TerminalBuffer, x1, x2, y: int,
                    doubleStyle: bool = false) =
  ## Convenience method to draw a single horizontal line into a terminal
  ## buffer directly.
  var bb = newBoxBuffer(tb.width, tb.height)
  bb.drawHorizLine(x1, x2, y, doubleStyle)
  tb.write(bb)

proc drawVertLine*(tb: var TerminalBuffer, x, y1, y2: int,
                   doubleStyle: bool = false) =
  ## Convenience method to draw a single vertical line into a terminal buffer
  ## directly.
  var bb = newBoxBuffer(tb.width, tb.height)
  bb.drawVertLine(x, y1, y2, doubleStyle)
  tb.write(bb)

proc drawRect*(tb: var TerminalBuffer, x1, y1, x2, y2: int,
               doubleStyle: bool = false) =
  ## Convenience method to draw a rectangle into a terminal buffer directly.
  var bb = newBoxBuffer(tb.width, tb.height)
  bb.drawRect(x1, y1, x2, y2, doubleStyle)
  tb.write(bb)
