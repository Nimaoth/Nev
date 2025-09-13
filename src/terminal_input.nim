
import std/[strformat, options, strutils]
import misc/[custom_unicode, timer]
import input, input_api

export input, input_api

const INTERMED_MAX = 16
const CSI_ARGS_MAX = 16
const CSI_LEADER_MAX = 16

const CSI_ARG_FLAG_MORE*: int = (1'u32 shl 31).int
const CSI_ARG_MASK*: int = (not (1'u32 shl 31)).int
const CSI_ARG_MISSING*: int = ((1'u32 shl 31) - 1).int

type
  StringCsiState* = object
    leaderlen*: int
    leader*: array[CSI_LEADER_MAX, char]
    argi*: int
    args*: array[CSI_ARGS_MAX, int64]

  StringOscState* = object
    command*: int

  StringDcsState* = object
    commandlen*: int
    command*: array[CSI_LEADER_MAX, char]

type
  ParserState = enum
      Normal,
      CSILeader,
      CSIArgs,
      CSIIntermed,
      DCSCommand,
      # below here are the "string states"
      OSCCommand,
      OSC,
      DCS,
      APC,
      PM,
      SOS,

  TerminalInputParser* = object
    inEsc: bool = false # After \e
    inEscO: bool = false # After \eO
    inUtf8: bool = false # Middle of multi byte utf8 code point
    utf8Remaining: int = 0
    utf8Buffer: string
    state: ParserState
    csi: StringCsiState
    osc: StringOscState
    dcs: StringDcsState
    intermedlen: int
    intermed: array[INTERMED_MAX, char]
    string_initial: bool
    emit_nul: bool
    escTimer: Timer

    width: int
    height: int

    escapeTimeout*: int

type
  InputEventKind* = enum
    Text
    Key
    GridSize
    PixelSize
    CellPixelSize

  InputEvent* = object
    case kind*: InputEventKind
    of Text:
      text*: string
    of Key:
      input*: int
      mods*: Modifiers
      action*: InputAction
      inputName*: string
    of GridSize, PixelSize, CellPixelSize:
      width*: int
      height*: int

proc textEvent*(text: sink string): InputEvent = InputEvent(kind: Text, text: text.ensureMove)
proc keyEvent*(input: int, mods: Modifiers, action: InputAction): InputEvent = InputEvent(kind: Key, input: input, mods: mods, action: action, inputName: inputToString(input, mods))
proc gridSizeEvent*(width, height: int): InputEvent = InputEvent(kind: GridSize, width: width, height: height)
proc pixelSizeEvent*(width, height: int): InputEvent = InputEvent(kind: PixelSize, width: width, height: height)
proc cellPixelSizeEvent*(width, height: int): InputEvent = InputEvent(kind: CellPixelSize, width: width, height: height)

proc csiArgHasMore*(a: int64): bool = (a.int and CSI_ARG_FLAG_MORE) != 0
proc csiArg*(a: int64): int = a.int and CSI_ARG_MASK
proc csiArgIsMissing*(a: int64): bool = csiArg(a) == CSI_ARG_MISSING

proc csiArgOr*(a: int64, def: int): int =
  if csiArg(a) == CSI_ARG_MISSING: def else: csiArg(a)

proc csiArgCount*(a: int64): int =
  if csiArg(a) == CSI_ARG_MISSING or csiArg(a) == 0: 1 else: csiArg(a)

proc csiArg*(vt: TerminalInputParser, i: int, i1: int, default: int = 0): int =
  var index = 0
  var k = 0
  while index < vt.csi.argi and k < i:
    if vt.csi.args[index].csiArgHasMore():
      inc index
      continue
    inc index
    inc k

  if index + i1 < vt.csi.argi:
    let a = vt.csi.args[index + i1]
    if a.csiArgIsMissing():
      return default
    return a.csiArg()
  return default

proc csiArg*(vt: TerminalInputParser, i: int, default: int = 0): int =
  return vt.csiArg(i, 0, default)

proc isStringState(s: ParserState): bool = s >= OSCCommand
proc isIntermed*(c: char): bool =
  return c.int >= 0x20 and c.int <= 0x2f

iterator handleCsi(vt: var TerminalInputParser; command: char): InputEvent =
  let leader = if vt.csi.leaderlen > 0: vt.csi.leader[0].addr else: nil
  let args = vt.csi.args
  let argcount =  vt.csi.argi
  let intermed = if vt.intermedlen > 0: vt.intermed[0].addr else: nil
  # stdout.write &"handleCsi {command}, {argcount}\r\n"
  # for i in 0..<argcount:
  #   stdout.write &"  {args[i]}\r\n"
  # stdout.write &"CSI {leader}{intermed} {args.toOpenArray(0, argcount - 1)} {command}\r\n"

  proc parseModsAndAction(vt: TerminalInputParser): (Modifiers, InputAction) =
    result = ({}, Press)
    let mods = vt.csiArg(1) - 1
    if mods >= 0:
      if (mods and 0x1) != 0:
        result[0].incl Shift
      if (mods and 0x2) != 0:
        result[0].incl Alt
      if (mods and 0x4) != 0:
        result[0].incl Control
      if (mods and 0x8) != 0:
        result[0].incl Super
      # stdout.write &"{result[0]} "

    let action = vt.csiArg(1, 1, default = 1)
    case action
    of 1: result[1] = Press
    of 2: result[1] = Repeat
    of 3: result[1] = Release
    else: discard
    # stdout.write &"{result[1]} "

  proc logKey(name: string) =
    # stdout.write &"\e[38;2;200;50;50m{name}\e[0m\r\n"
    discard

  template yieldKey(name: untyped) =
    # stdout.write &"\e[38;2;200;50;50m{name}\e[0m\r\n"
    yield keyEvent(name, mods, action)

  case command
  of 't':
    case args[0]
    of 4:
      # pixel size
      yield pixelSizeEvent(args[2], args[1])
    of 5:
      # cell pixel size
      yield cellPixelSizeEvent(args[2], args[1])
    of 6:
      # pixel size
      yield pixelSizeEvent(args[2], args[1])
    of 8:
      # grid size
      yield gridSizeEvent(args[2], args[1])
    else:
      discard
  of 'u':
    let input = vt.csiArg(0)
    if input != 0:
      let (mods, action) = vt.parseModsAndAction()
      case input
      of 13: yieldKey INPUT_ENTER
      of 27: yieldKey INPUT_ESCAPE
      of 127: yieldKey INPUT_BACKSPACE
      of ' '.int: yieldKey INPUT_SPACE
      of 9: yieldKey INPUT_TAB
      else:
        yieldKey input

        # yieldKey INPUT_"NKNOWN {args[0]}"
  of 'A':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_UP
  of 'B':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_DOWN
  of 'C':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_RIGHT
  of 'D':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_LEFT
  of 'E':
    # todo: KP_BEGIN (keypad begin?)
    let (mods, action) = vt.parseModsAndAction()
    # yieldKey INPUT_LEFT
  of 'F':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_END
  of 'H':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_HOME
  of 'P':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_F1
  of 'Q':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_F2
  of 'S':
    let (mods, action) = vt.parseModsAndAction()
    yieldKey INPUT_F4
  of 'Z':
    var (mods, action) = vt.parseModsAndAction()
    mods.incl Shift
    yieldKey INPUT_TAB
  of '~':
    let (mods, action) = vt.parseModsAndAction()
    if argcount > 0:
      case args[0].int
      of 3: yieldKey INPUT_DELETE
      of 5: yieldKey INPUT_PAGE_UP
      of 6: yieldKey INPUT_PAGE_DOWN
      of 11: yieldKey INPUT_F1
      of 12: yieldKey INPUT_F2
      of 13: yieldKey INPUT_F3
      of 14: yieldKey INPUT_F4
      of 15: yieldKey INPUT_F5
      of 17: yieldKey INPUT_F6
      of 18: yieldKey INPUT_F7
      of 19: yieldKey INPUT_F8
      of 20: yieldKey INPUT_F9
      of 21: yieldKey INPUT_F10
      of 23: yieldKey INPUT_F11
      of 24: yieldKey INPUT_F12
      else:
        logKey &"UNKNOWN {args[0]}"
  else:
    discard

iterator handleControl(vt: var TerminalInputParser; command: char): InputEvent =
  if command == '\x8f':
    vt.inEscO = true

iterator parseInput*(vt: var TerminalInputParser, text: openArray[char]): InputEvent =
  var i = 0
  var stringStart = cast[ptr UncheckedArray[char]](text[0])
  var stringLen = 0

  template enterState(s: ParserState): untyped =
    vt.state = s
    stringStart = nil

  while i < text.len:
    defer:
      inc i
    var c1Allowed = false
    var c = text[i]

    # stdout.write &"{i}: '{c}' (0x{c.int.toHex}), {c1Allowed}, {vt.state}, {vt.inEsc}\r\n"
    var mods: Modifiers = {}

    template yieldKey(name: untyped) =
      yield keyEvent(name, mods, Press)

    if vt.inEscO: # state after \eO, check for \eOP, \eOQ, \eOR, \eOS which are F1, F2, F3 and F4
      vt.inEscO = false
      case c
      of 'P':
        yieldKey INPUT_F1
        continue
      of 'Q':
        yieldKey INPUT_F2
        continue
      of 'R':
        yieldKey INPUT_F3
        continue
      of 'S':
        yieldKey INPUT_F4
        continue
      else:
        discard

    template yieldControlKey(key: char) =
      if vt.inEsc:
        mods.incl Alt
      mods.incl Control
      vt.inEsc = false
      yieldKey key.int
      continue

    case c
    of '\x1b':
      if i == text.len - 1:
        if vt.inEsc:
          mods.incl Alt
        yieldKey INPUT_ESCAPE
        continue

      vt.state = Normal
      vt.inEsc = true

    of '\x7f':
      if vt.inEsc:
        mods.incl Alt
      vt.inEsc = false
      yieldKey INPUT_BACKSPACE
      continue
    of '\x08':
      if vt.inEsc:
        mods.incl Alt
      mods.incl Control
      vt.inEsc = false
      yieldKey INPUT_BACKSPACE
      continue
    of '\x09':
      if vt.inEsc:
        mods.incl Alt
      vt.inEsc = false
      yieldKey INPUT_TAB
      continue
    of '\x0d', '\x0a':
      if vt.inEsc:
        mods.incl Alt
      vt.inEsc = false
      yieldKey INPUT_ENTER
      continue

    of '\x01': yieldControlKey 'a'
    of '\x02': yieldControlKey 'b'
    of '\x03': yieldControlKey 'c'
    of '\x04': yieldControlKey 'd'
    of '\x05': yieldControlKey 'e'
    of '\x06': yieldControlKey 'f'
    of '\x07': yieldControlKey 'g'
    # of '\x08': yieldControlKey 'h' # handled above
    # of '\x09': yieldControlKey 'i' # handled above
    # of '\x0a': yieldControlKey 'j' # handled above
    of '\x0b': yieldControlKey 'k'
    of '\x0c': yieldControlKey 'l'
    # of '\x0d': yieldControlKey 'm' # handled above
    of '\x0e': yieldControlKey 'n'
    of '\x0f': yieldControlKey 'o'
    of '\x10': yieldControlKey 'p'
    of '\x11': yieldControlKey 'q'
    of '\x12': yieldControlKey 'r'
    of '\x13': yieldControlKey 's'
    of '\x14': yieldControlKey 't'
    of '\x15': yieldControlKey 'u'
    of '\x16': yieldControlKey 'v'
    of '\x17': yieldControlKey 'w'
    of '\x18': yieldControlKey 'x'
    of '\x19': yieldControlKey 'y'
    of '\x1A': yieldControlKey 'z'
    # of '\x1b': yieldControlKey '[' # handled above (ESC)
    of '\x1c': yieldControlKey '\\'
    of '\x1d': yieldControlKey ']'
    of '\x1e': yieldControlKey '~'
    of '\x1f': yieldControlKey '?'

    of '\x20':
      vt.inEsc = false
      yieldKey INPUT_SPACE
      continue

    else:
      discard

    if vt.inEsc:
      if vt.intermedLen == 0 and c.int >= 0x40 and c.int < 0x60 and (not vt.state.isStringState or c.int == 0x5c):
        c = (c.int + 0x40).char
        c1Allowed = true
        if stringLen > 0:
          stringLen -= 1
        vt.inEsc = false
      else:
        stringStart = nil
        vt.state = Normal

    if vt.state == CSILeader:
      if c.int >= 0x3c and c.int <= 0x3f:
        if vt.csi.leaderlen < CSI_LEADER_MAX - 1:
          vt.csi.leader[vt.csi.leaderlen] = c
          inc(vt.csi.leaderlen)
        continue
      vt.csi.leader[vt.csi.leaderlen] = 0.char
      vt.csi.argi = 0
      vt.csi.args[0] = CSI_ARG_MISSING
      vt.state = CSIArgs

    if vt.state == CSIArgs:
      if c >= '0' and c <= '9':
        if vt.csi.args[vt.csi.argi] == CSI_ARG_MISSING:
          vt.csi.args[vt.csi.argi] = 0
        vt.csi.args[vt.csi.argi] = vt.csi.args[vt.csi.argi] * 10
        inc(vt.csi.args[vt.csi.argi], c.int - '0'.int)
        continue
      if c == ':':
        vt.csi.args[vt.csi.argi] = vt.csi.args[vt.csi.argi] or CSI_ARG_FLAG_MORE
        c = ';'
      if c == ';':
        inc(vt.csi.argi)
        vt.csi.args[vt.csi.argi] = CSI_ARG_MISSING
        continue
      inc(vt.csi.argi)
      vt.intermedlen = 0
      vt.state = CSIIntermed

    if vt.state == CSIIntermed:
      if isIntermed(c):
        if vt.intermedlen < INTERMED_MAX - 1:
          vt.intermed[vt.intermedlen] = c
          inc(vt.intermedlen)
        continue
      elif c.int == 0x1b:
        ##  ESC in CSI cancels
      elif c.int >= 0x40 and c.int <= 0x7e:      ##  else was invalid CSI
        vt.intermed[vt.intermedlen] = 0.char
        for event in handleCsi(vt, c):
          yield event
      enterState(Normal)
      continue

    case vt.state
    of Normal:
      if vt.inEsc:
        if isIntermed(c):
          if vt.intermedlen < INTERMED_MAX - 1:
            vt.intermed[vt.intermedlen] = c
            inc(vt.intermedlen)
        elif c.int >= 0x30 and c.int < 0x7f:
          mods.incl Alt
          vt.inEsc = false
          yieldKey c.int
        continue

      if c1Allowed and c.int >= 0x80 and c.int < 0xa0:
        case c.int
        # of 0x90:                       ##  DCS
        #   vt.string_initial = true
        #   vt.dcs.commandlen = 0
        #   enterState(DCSCommand)
        # of 0x98:                       ##  SOS
        #   vt.string_initial = true
        #   enterState(SOS)
        #   string_start = bytes + pos + 1
        #   string_len = 0
        of 0x9b:                       ##  CSI
          vt.csi.leaderlen = 0
          enterState(CSILeader)
        # of 0x9d:                       ##  OSC
        #   vt.osc.command = -1
        #   vt.string_initial = true
        #   string_start = bytes + pos + 1
        #   enterState(OSCCommand)
        # of 0x9e:                       ##  PM
        #   vt.string_initial = true
        #   enterState(PM)
        #   string_start = bytes + pos + 1
        #   string_len = 0
        # of 0x9f:                       ##  APC
        #   vt.string_initial = true
        #   enterState(APC)
        #   string_start = bytes + pos + 1
        #   string_len = 0
        else:
          for event in handleControl(vt, c):
            yield event
      else:
        var
          k = i
          n = i + vt.utf8Remaining # beginning of next character
          result: Rune
        while k < text.len:
          let c = text[k]
          if c.int <= 127:
            vt.inUtf8 = false
            if c notin PrintableChars:
              break
            n = k + 1
            inc k
          else:
            if (c.int and 0b11000000) == 0b10000000:
              vt.inUtf8 = false
              n = k + 1
            elif (c.int and 0b11100000) == 0b11000000:
              vt.inUtf8 = true
              n = k + 2
            elif (c.int and 0b11110000) == 0b11100000:
              vt.inUtf8 = true
              n = k + 3
            elif (c.int and 0b11111000) == 0b11110000:
              vt.inUtf8 = true
              n = k + 4
            else:
              vt.inUtf8 = false
            inc k
        if k == i:
          inc k

        vt.utf8Remaining = n - k
        if k == text.len:
          if k < n:
            # in the middle of utf8, need more data
            vt.utf8Buffer.add text[i..<k].join("")
            break
          if vt.utf8Buffer.len > 0:
            yield textEvent(vt.utf8Buffer & text[i..<k].join(""))
            vt.utf8Buffer.setLen(0)
          else:
            yield textEvent(text[i..<k].join(""))
          vt.inUtf8 = false
          vt.utf8Remaining = 0
        else:
          if vt.utf8Buffer.len > 0:
            yield textEvent(vt.utf8Buffer & text[i..<k].join(""))
            vt.utf8Buffer.setLen(0)
          else:
            yield textEvent(text[i..<k].join(""))
          vt.inUtf8 = false
          vt.utf8Remaining = 0
        i = k - 1

    else:
      discard
