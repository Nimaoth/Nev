import std/[strformat, terminal, typetraits, enumutils, strutils, sets, enumerate, typedthreads, parseutils]
import std/colors as stdcolors
import vmath
import chroma as chroma
import misc/[custom_logger, rect_utils, event, timer, custom_unicode, custom_async]
import tui, input, ui/node
import platform, app_options, terminal_input

when defined(windows):
  import winlean
else:
  from posix import read
  import std/envvars

export platform

logCategory "terminal-platform"

# Mouse
# https://de.wikipedia.org/wiki/ANSI-Escapesequenz
# https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-Extended-coordinates
const
  CSI = 0x1B.chr & 0x5B.chr
  SET_BTN_EVENT_MOUSE = "1002"
  SET_ANY_EVENT_MOUSE = "1003"
  SET_SGR_EXT_MODE_MOUSE = "1006"
  # SET_URXVT_EXT_MODE_MOUSE = "1015"
  ENABLE = "h"
  DISABLE = "l"
  MouseTrackAny = fmt"{CSI}?{SET_BTN_EVENT_MOUSE}{ENABLE}{CSI}?{SET_ANY_EVENT_MOUSE}{ENABLE}{CSI}?{SET_SGR_EXT_MODE_MOUSE}{ENABLE}"
  DisableMouseTrackAny = fmt"{CSI}?{SET_BTN_EVENT_MOUSE}{DISABLE}{CSI}?{SET_ANY_EVENT_MOUSE}{DISABLE}{CSI}?{SET_SGR_EXT_MODE_MOUSE}{DISABLE}"

when defined(linux):
  const
    XtermColor    = "xterm-color"
    Xterm256Color = "xterm-256color"


type
  TerminalPlatform* = ref object of Platform
    buffer: TerminalBuffer
    borderBuffer: BoxBuffer
    trueColorSupport*: bool
    mouseButtons: set[input.MouseButton]
    masks: seq[Rect]
    cursor: tuple[row: int, col: int, visible: bool, shape: UINodeFlags]
    noPty: bool
    noUI: bool
    readInputOnThread: bool

    doubleClickTimer: Timer
    doubleClickCounter: int
    doubleClickTime: float

    inputParser: TerminalInputParser
    useKittyKeyboard: bool
    kittyKeyboardFlags: int = 0b1001

    gridSize: IVec2
    pixelSize: IVec2
    cellPixelSize: IVec2

    fontInfo: FontInfo

proc enterFullScreen() =
  ## Enters full-screen mode (clears the terminal).
  when defined(windows):
    stdout.write "\e[?47h\e[?1049h" # use alternate screen
  elif defined(posix):
    case getEnv("TERM"):
    of XtermColor:
      stdout.write "\e7\e[?47h"
    of Xterm256Color:
      stdout.write "\e[?1049h"
    else:
      eraseScreen()
  else:
    eraseScreen()

proc exitFullScreen() =
  ## Exits full-screen mode (restores the previous contents of the terminal).
  when defined(windows):
    stdout.write "\e?47l\e[?1049l"
  elif defined(posix):
    case getEnv("TERM"):
    of XtermColor:
      stdout.write "\e[2J\e[?47l\e8"
    of Xterm256Color:
      stdout.write "\e[?1049l"
    else:
      eraseScreen()
  else:
    eraseScreen()
    setCursorPos(0, 0)

proc exitProc() {.noconv.} =
  stdout.write("\e[<u") # todo: only if enabled
  stdout.write(DisableMouseTrackAny)
  exitFullScreen()
  consoleDeinit()
  stdout.write(tui.ansiResetCode)
  showCursor()
  quit(0)

proc toStdColor(color: tui.ForegroundColor): stdcolors.Color =
  return case color
  of fgRed: stdcolors.rgb(255, 0, 0)
  of fgGreen: stdcolors.rgb(0, 255, 0)
  of fgYellow: stdcolors.rgb(255, 255, 0)
  of fgBlue: stdcolors.rgb(0, 0, 255)
  of fgMagenta: stdcolors.rgb(255, 0, 255)
  of fgCyan: stdcolors.rgb(0, 255, 255)
  of fgWhite: stdcolors.rgb(255, 255, 255)
  else: stdcolors.rgb(0, 0, 0)

proc toStdColor(color: tui.BackgroundColor): stdcolors.Color =
  return case color
  of bgRed: stdcolors.rgb(255, 0, 0)
  of bgGreen: stdcolors.rgb(0, 255, 0)
  of bgYellow: stdcolors.rgb(255, 255, 0)
  of bgBlue: stdcolors.rgb(0, 0, 255)
  of bgMagenta: stdcolors.rgb(255, 0, 255)
  of bgCyan: stdcolors.rgb(0, 255, 255)
  of bgWhite: stdcolors.rgb(255, 255, 255)
  else: stdcolors.rgb(0, 0, 0)

proc getClosestColor[T: HoleyEnum](r, g, b: int, default: T): T =
  var minDistance = 10000000.0
  result = default
  {.push warning[HoleEnumConv]:off.}
  for fg in enumutils.items(T):
    let fgStd = fg.toStdColor
    let uiae = fgStd.extractRGB
    let distance = sqrt((r - uiae.r).float.pow(2) + (g - uiae.g).float.pow(2) + (b - uiae.b).float.pow(2))
    if distance < minDistance:
      minDistance = distance
      result = fg
  {.pop.}

# Characters which are displayed two cells wide in the terminal but only take up one character in the terminals grid
# For those we take up two cells internally, but don't write the second cell to the terminal
const narrowWide = """
⌚⌛⏩⏪⏫⏬⏰⏳◽◾☔☕♈♉♊♋♌♍♎♏♐♑♒♓♿⚓⚡⚪⚫⚽⚾⛄⛅⛎⛔⛪⛲⛳⛵⛺⛽✅✊✋✨❌❎❓❔❕
❗➕➖➗➰➿⬛⬜⭐⭕〰〽㊗㊙🀄🃏🆎🆑🆒🆓🆔🆕🆖🆗🆘🆙🆚🈁🈂🈚🈯🈲🈳🈴🈵🈶🈷🈸🈹🈺🉐🉑🌀🌁🌂🌃🌄🌅🌆🌇
🌈🌈🌉🌊🌋🌌🌍🌎🌏🌐🌑🌒🌓🌔🌕🌖🌗🌘🌙🌚🌛🌜🌝🌞🌟🌠🌭🌮🌯🌰🌱🌲🌳🌴🌵🌷🌸🌹🌺🌻🌼🌽🌾🌿🍀🍁🍂🍃🍄🍅
🍆🍇🍈🍉🍊🍋🍌🍍🍎🍏🍐🍑🍒🍓🍔🍕🍖🍗🍘🍙🍚🍛🍜🍝🍞🍟🍠🍡🍢🍣🍤🍤🍥🍦🍧🍨🍩🍪🍫🍬🍭🍮🍯🍰🍱🍲🍳🍴🍵🍶
🍷🍸🍹🍺🍻🍼🍾🍿🎀🎁🎂🎃🎄🎅🎆🎇🎈🎉🎊🎋🎌🎍🎎🎏🎐🎑🎒🎓🎠🎡🎢🎣🎤🎥🎦🎧🎨🎩🎪🎫🎬🎭🎮🎯🎰🎱🎲🎳🎴🎵
🎶🎷🎸🎹🎺🎻🎼🎽🎾🎿🏀🏁🏂🏃🏄🏅🏆🏇🏈🏉🏊🏏🏐🏑🏒🏓🏠🏡🏢🏣🏤🏥🏦🏧🏨🏩🏪🏫🏬🏭🏮🏯🏰🏴🏸🏸🏹🏺🏻🏼
🏽🏾🏿🐀🐁🐂🐃🐄🐅🐆🐇🐈🐉🐊🐋🐌🐍🐎🐏🐐🐑🐒🐓🐔🐕🐖🐗🐘🐙🐚🐛🐜🐝🐞🐟🐠🐡🐢🐣🐤🐥🐦🐧🐨🐩🐪🐫🐬🐭🐮
🐯🐰🐱🐲🐳🐴🐵🐶🐷🐸🐹🐺🐻🐼🐽🐾👀👂👃👄👅👆👇👈👉👊👋👌👍👎👏👐👑👒👓👔👕👖👗👘👙👚👛👜👝👞👟👠👡👢
👣👤👥👦👧👨👩👪👫👬👭👮👯👰👱👲👳👴👵👶👷👸👹👺👻👼👽👾👿💀💁💂💃💄💅💆💇💈💉💊💋💌💍💎💏💐💑💒💓💔
💕💖💗💘💙💚💛💜💝💞💟💠💡💢💣💤💥💦💧💨💩💪💫💬💭💮💯💰💱💲💳💴💵💶💷💸💹💺💻💼💽💾💿📀📁📂📃📄📅📆
📇📈📉📊📋📌📍📎📏📐📑📒📓📔📕📖📖📗📘📙📚📛📜📝📞📟📠📡📢📣📤📥📦📧📨📩📪📫📬📭📮📯📰📱📲📳📴📵📶📷
📸📹📺📻📼📿🔀🔁🔂🔂🔃🔄🔅🔆🔇🔈🔉🔊🔊🔋🔌🔍🔎🔏🔐🔑🔒🔓🔔🔕🔖🔗🔘🔙🔚🔛🔜🔝🔞🔟🔠🔡🔢🔣🔤🔥🔦🔧🔨🔩
🔪🔫🔫🔬🔭🔮🔯🔰🔱🔲🔳🔴🔵🔶🔷🔸🔹🔺🔻🔼🔽🕋🕌🕍🕎🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛🕜🕝🕞🕟🕠🕡🕢🕣🕤🕥🕦🕧🕺
🖕🖖🖤🗻🗼🗽🗾🗿😀😁😂😃😄😅😆😇😈😉😊😋😌😍😎😏😐😑😒😓😔😕😖😗😘😙😚😛😜😝😞😟😠😡😢😣😤😥😦😧😨😩
😪😫😬😭😮😯😰😱😲😳😴😵😶😷😸😹😺😻😼😽😾😿🙀🙁🙂🙃🙄🙄🙅🙆🙇🙈🙉🙊🙋🙌🙍🙎🙏🚀🚁🚁🚂🚃🚄🚅🚆🚇🚈🚉
🚊🚋🚌🚍🚎🚏🚐🚑🚒🚓🚔🚕🚖🚗🚘🚙🚚🚛🚜🚝🚞🚟🚠🚡🚢🚣🚤🚥🚦🚧🚨🚩🚪🚫🚬🚭🚮🚯🚰🚱🚲🚳🚳🚴🚵🚶🚷🚸🚹🚺
🚻🚼🚽🚾🚿🛀🛁🛂🛃🛄🛅🛌🛐🛑🛒🛕🛖🛗🛝🛞🛟🛫🛬🛴🛵🛶🛷🛸🛹🛺🛻🛼🟠🟡🟢🟣🟤🟥🟦🟧🟨🟩🟪🟫🟰🤌🤍🤎🤏🤐
🤑🤒🤓🤔🤕🤖🤗🤘🤙🤚🤛🤜🤝🤞🤟🤠🤡🤢🤣🤤🤥🤦🤧🤨🤩🤪🤫🤬🤭🤮🤯🤰🤱🤲🤳🤴🤵🤶🤷🤸🤹🤺🤼🤽🤾🤿🥀🥁🥂🥃
🥄🥅🥇🥈🥉🥊🥋🥌🥍🥎🥏🥐🥑🥒🥓🥔🥕🥖🥗🥘🥙🥚🥛🥜🥝🥞🥟🥠🥡🥢🥣🥤🥥🥦🥧🥨🥩🥪🥫🥬🥭🥮🥯🥰🥰🥱🥲🥳🥴🥵
🥶🥷🥸🥹🥺🥻🥼🥽🥾🥿🦀🦁🦂🦃🦄🦅🦅🦆🦇🦈🦉🦊🦋🦌🦍🦎🦏🦐🦑🦒🦒🦓🦔🦕🦖🦗🦘🦙🦚🦛🦜🦝🦞🦟🦠🦡🦢🦣🦤🦥
🦦🦧🦨🦩🦪🦫🦬🦬🦭🦮🦯🦰🦱🦲🦳🦴🦵🦶🦶🦷🦸🦹🦺🦻🦼🦽🦾🦿🧀🧁🧂🧃🧄🧅🧆🧇🧈🧉🧊🧋🧌🧍🧎🧏🧐🧑🧒🧓🧔🧕
🧖🧗🧘🧙🧚🧚🧛🧜🧝🧞🧟🧠🧡🧢🧣🧤🧤🧥🧦🧧🧨🧩🧪🧫🧬🧭🧮🧯🧰🧱🧲🧳🧴🧵🧶🧷🧸🧹🧺🧻🧼🧽🧾🧿🩰🩱🩲🩳🩴🩸
🩹🩺🩻🩼🪀🪁🪂🪃🪄🪅🪆🪐🪑🪒🪓🪔🪕🪖🪗🪘🪙🪚🪛🪜🪝🪞🪟🪠🪡🪢🪣🪤🪥🪦🪧🪨🪩🪪🪫🪬🪰🪱🪲🪳🪴🪵🪶🪷🪸🪹
🪺🫀🫁🫂🫃🫄🫅🫐🫑🫒🫓🫔🫕🫖🫗🫘🫙🫠🫡🫢🫣🫤🫥🫦🫧🫰🫱🫲🫳🫴🫵🫶
🇦🇧🇨🇩🇪🇫🇬🇭🇮🇯🇰🇱🇲🇳🇴🇵🇶🇷🇸🇹🇺🇻🇼🇽🇾🇿
""".replace("\n", "")

# Characters which only take up one cell
const narrowNarrow = "*123456789©®‼⁉™↔↕↖↗↘↙↪▪▫▶◀◻◼☺♀♂♠♣♥♦⤴⤵⬅⬆⬇󾠫"

# Characters which take up one cell in the terminal but are rendered as two cells, therefor overlapping
# with the cell on the right.
# For these we take up two cells in the internal buffer, the second just being a space with the same attributes
# as the actual char. Therefore when rendered in the terminal the emoji overlaps with the space on the right
# and looks nice.
const wideNarrow = """
ℹ⌨⏏⏭⏮⏯⏱⏲⏸⏹⏺☀☁☂☃☄☎☑☘☝☠☢☣☦☪☮☯☸☹♟♨♻♾⚒⚔⚕⚖⚗⚙⚛⚜⚠⚧⚰⚱⛈⛏⛑⛓⛩
⛰⛱⛴⛷⛸⛹✂✈✉✌✍✏✒✔✖✝✡✳✴❄❇❣❤➡🅰🅱🅾🅿🌡🌤🌥🌦🌧🌨🌩🌪🌫🌬🌶🍽🎖🎗🎗🎙🎚🎛🎞🎟🏋🏌
🏍🏎🏔🏕🏖🏗🏘🏙🏚🏛🏜🏝🏞🏟🏳🏵🏷🐿👁👁📽🕉🕊🕯🕰🕳🕴🕵🕶🕷🕸🕹🖇🖊🖋🖌🖍🖐🖥🖨🖱🖲🖼🗂🗃🗄🗑🗒🗓🗜
🗝🗞🗡🗣🗨🗯🗳🗺🛋🛍🛎🛏🛠🛡🛢🛣🛤🛥🛩🛰🛳🗀
""".replace("\n", "")

var narrowWideSet = initHashSet[Rune]()
for r in narrowWide.runes:
  narrowWideSet.incl r

var narrowNarrowSet = initHashSet[Rune]()
for r in narrowNarrow.runes:
  narrowNarrowSet.incl r

var wideNarrowSet = initHashSet[Rune]()
for r in wideNarrow.runes:
  wideNarrowSet.incl r

proc nextWrapBoundary(str: openArray[char], start: int, maxLen: RuneCount): (int, RuneCount) {.gcsafe.}

proc runeProps(r: Rune): tuple[selectionWidth: int, displayWidth: int] {.gcsafe.} =
  if r.int <= 127:
    return (1, 1)

  {.gcsafe.}:
    if r in narrowWideSet:
      return (2, 2)
    if r in wideNarrowSet:
      return (1, 2)

  return (1, 1)

proc getTerminalSize(self: TerminalPlatform): IVec2 =
  if self.noPty:
    return self.gridSize
  else:
    return ivec2(terminalWidth().int32, terminalHeight().int32)

type ThreadState = object
  a: int

var thread: Thread[ptr ThreadState]
var state = ThreadState(
)
var chan: Channel[char]
chan.open()
var stdinEvent = ThreadSignalPtr.new().value

proc threadFunc(state: ptr ThreadState) {.thread.} =
  while true:
    var str = stdin.readChar()
    chan.send(str)
    discard stdinEvent.fireSync()

method init*(self: TerminalPlatform, options: AppOptions) =
  try:
    self.noPty = options.noPty
    self.noUI = options.noUI

    self.inputParser.enableEscapeTimeout = true
    self.inputParser.escapeTimeout = 32

    self.fontInfo = FontInfo(
      ascent: 0,
      lineHeight: 1,
      lineGap: 0,
      scale: 1,
      advance: proc(rune: Rune): float = 1
    )

    when defined(windows):
      self.readInputOnThread = true
    if self.noPty:
      self.readInputOnThread = true

    self.gridSize = ivec2(80, 50)
    self.cellPixelSize = ivec2(10, 20)
    self.pixelSize = self.gridSize * self.cellPixelSize

    var useKitty = true

    if options.kittyKeyboardFlags != "":
      try:
        var flags: int = 0
        discard options.kittyKeyboardFlags.parseBin(flags)
        self.kittyKeyboardFlags = flags
        useKitty = flags != 0
      except CatchableError as e:
        log lvlError, &"Failed to parse kitty keyboard flags: {e.msg}"

    if not options.noPty:
      if myEnableTrueColors():
        log(lvlInfo, "Enable true color support")
        self.trueColorSupport = true
      else:
        when defined(posix):
          log(lvlInfo, "Enable true color support")
          self.trueColorSupport = true
    else:
      self.trueColorSupport = true

    when defined(windows):
      enableVirtualTerminalInput()

    gIllwillInitialised = true
    gFullScreen = true

    enterFullScreen()

    if useKitty:
      log lvlInfo, &"Query kitty keyboard protol with flags {self.kittyKeyboardFlags.toBin(5)}"
      stdout.write("\e[?u") # query kitty keyboard protocol support

    stdout.write(tui.ansiResetCode)
    stdout.write(MouseTrackAny)

    if options.noPty:
      stdout.write "\e[2J" # clear
      stdout.write "\e[18t" # request grid size

    else:
      consoleInit()
      setControlCHook(exitProc)

    stdout.write "\e[?25l"  # hide cursor

    self.builder = newNodeBuilder()
    self.builder.useInvalidation = true
    self.builder.charWidth = 1
    self.builder.lineHeight = 1
    self.builder.lineGap = 0
    self.builder.defaultBorderWidth = 1
    self.builder.supportsFontScale = false

    self.supportsThinCursor = false
    self.doubleClickTime = 0.35

    self.focused = true

    if self.readInputOnThread:
      try:
        thread.createThread(threadFunc, state.addr)
      except CatchableError:
        discard

    self.layoutOptions.getTextBounds = proc(text: string, fontSizeIncreasePercent: float = 0): Vec2 =
      result.x = text.len.float
      result.y = 1

    let terminalSize = self.getTerminalSize()
    self.buffer.initTerminalBuffer(terminalSize.x, terminalSize.y)
    self.buffer.clear()
    self.borderBuffer = newBoxBuffer(terminalSize.x, terminalSize.y)
    self.redrawEverything = true

    self.builder.textWidthImpl = proc(node: UINode): float32 {.gcsafe, raises: [].} =
      var currentWidth = 0.float32
      for r in node.text.runes:
        if r == '\n'.Rune:
          result = max(result, currentWidth)
          currentWidth = 0
        else:
          currentWidth += r.runeProps.displayWidth.float32
      result = max(result, currentWidth)

    self.builder.textWidthStringImpl = proc(text: string): float32 {.gcsafe, raises: [].} =
      var currentWidth = 0.float32
      for r in text.runes:
        if r == '\n'.Rune:
          result = max(result, currentWidth)
          currentWidth = 0
        else:
          currentWidth += r.runeProps.displayWidth.float32
      result = max(result, currentWidth)

    self.builder.textBoundsImpl = proc(node: UINode): Vec2 {.gcsafe, raises: [].} =
      try:
        let lineLen = round(node.bounds.w).RuneCount
        let wrap = TextWrap in node.flags
        var yOffset = 0.0
        for line in node.text.splitLines:
          let runeLen = line.runeLen
          if wrap and runeLen > lineLen:
            var startByte = 0
            var startRune = 0.RuneIndex

            while startByte < line.len:
              var endByte = startByte
              var endRune = startRune
              var currentRuneLen = 0.RuneCount

              while true:
                let (bytes, runes) = line.nextWrapBoundary(endByte, lineLen - currentRuneLen)
                if currentRuneLen + runes >= lineLen.RuneIndex or bytes == 0:
                  break

                endByte += bytes
                endRune += runes
                currentRuneLen += runes

              if startByte >= line.len or endByte > line.len:
                break

              yOffset += 1

              if startByte == endByte:
                break

              startByte = endByte
              startRune = endRune

          else:
            yOffset += 1
        return vec2(node.bounds.w, yOffset)
      except:
        return vec2(1, 1)

  except:
    discard

  stdout.flushFile()

method deinit*(self: TerminalPlatform) =
  try:
    if self.useKittyKeyboard:
      stdout.write("\e[<u")
    stdout.write(DisableMouseTrackAny)
    exitFullScreen()
    consoleDeinit()
    stdout.write(tui.ansiResetCode)
    showCursor()
  except:
    discard

method requestRender*(self: TerminalPlatform, redrawEverything = false) =
  self.requestedRender = true
  self.redrawEverything = self.redrawEverything or redrawEverything

method size*(self: TerminalPlatform): Vec2 = vec2(self.buffer.width.float, self.buffer.height.float)

method sizeChanged*(self: TerminalPlatform): bool =
  let terminalSize = self.getTerminalSize()
  return self.buffer.width != terminalSize.x.int or self.buffer.height != terminalSize.y.int

method fontSize*(self: TerminalPlatform): float = 1
method lineDistance*(self: TerminalPlatform): float = 0
method lineHeight*(self: TerminalPlatform): float = 1
method charWidth*(self: TerminalPlatform): float = 1
method charGap*(self: TerminalPlatform): float = 0
method measureText*(self: TerminalPlatform, text: string): Vec2 = vec2(text.len.float, 1)
method layoutText*(self: TerminalPlatform, text: string): seq[Rect] =
  result = newSeqOfCap[Rect](text.len)
  for i, c in enumerate(text.runes):
    result.add rect(i.float, 0, 1, 1)

proc pushMask(self: TerminalPlatform, mask: Rect) =
  let maskedMask = if self.masks.len > 0:
    self.masks[self.masks.high] and mask
  else:
    mask
  self.masks.add maskedMask

proc popMask(self: TerminalPlatform) =
  assert self.masks.len > 0
  discard self.masks.pop()

method setVsync*(self: TerminalPlatform, enabled: bool) {.gcsafe, raises: [].} = discard

method getFontInfo*(self: TerminalPlatform, fontSize: float, flags: UINodeFlags): ptr FontInfo {.gcsafe, raises: [].} =
  self.fontInfo.addr

method processEvents*(self: TerminalPlatform): int {.gcsafe.} =
  try:
    var eventCounter = 0
    var buffer = ""

    if self.readInputOnThread:
      while true:
        let (ok, c) = chan.tryRecv()
        if not ok:
          break
        buffer.add c
    else:
      when defined(linux):
        buffer.setLen(100)
        var i = 0
        while kbhit() > 0 and i < buffer.len:
          var ret = read(0, buffer[i].addr, 1)
          if ret > 0:
            i += ret
          else:
            break
        buffer.setLen(i)
      else:
        # todo
        discard

    # if buffer.len > 0 and self.noUI:
    #   stdout.write &"> {buffer.toOpenArrayByte(0, buffer.high)}, {buffer.toOpenArray(0, buffer.high)}\r\n"
    for event in self.inputParser.parseInput(buffer.toOpenArray(0, buffer.high)):
      if self.noUI:
        stdout.write &"{event}\r\n"

      case event.kind
      of Text:
        if not self.noUI:
          for r in event.text.runes:
            if not self.builder.handleKeyPressed(r.int64, {}):
              self.onKeyPress.invoke (r.int64, {})
      of Key:
        var input = event.input
        if Shift in event.mods and input > 0:
          input = input.Rune.toUpper.int
        if not self.noUI:
          case event.action
          of Press, Repeat:
            if not self.builder.handleKeyPressed(input.int64, event.mods):
              self.onKeyPress.invoke (input.int64, event.mods)
          of Release:
            if not self.builder.handleKeyReleased(input.int64, event.mods):
              self.onKeyRelease.invoke (input.int64, event.mods)
        if self.noUI:
          if event.input == 'c'.int64 and event.mods == {Control}:
            exitProc()
            stdout.write &"exited\r\n"
            stdout.flushFile()
            quit(1)
      of Mouse:
        if not self.noUI:
          let pos = vec2(self.inputParser.mouseCol.float, self.inputParser.mouseRow.float)
          case event.mouse.action
          of Press, Repeat:
            self.mouseButtons.incl event.mouse.button
            if not self.builder.handleMousePressed(event.mouse.button, event.mouse.mods, pos):
              self.onMousePress.invoke (event.mouse.button, event.mouse.mods, pos)
          else:
            self.mouseButtons.excl event.mouse.button
            if not self.builder.handleMouseReleased(event.mouse.button, event.mouse.mods, pos):
              self.onMouseRelease.invoke (event.mouse.button, event.mouse.mods, pos)
      of MouseMove:
        if not self.noUI:
          let pos = vec2(self.inputParser.mouseCol.float, self.inputParser.mouseRow.float)
          if not self.builder.handleMouseMoved(pos, {}, event.move.mods):
            self.onMouseMove.invoke (pos, vec2(0, 0), event.move.mods, {})
      of MouseDrag:
        if not self.noUI:
          let pos = vec2(self.inputParser.mouseCol.float, self.inputParser.mouseRow.float)
          if not self.builder.handleMouseMoved(pos, {event.drag.button}, event.drag.mods):
            self.onMouseMove.invoke (pos, vec2(0, 0), event.drag.mods, {event.drag.button})
      of Scroll:
        if not self.noUI:
          let pos = vec2(self.inputParser.mouseCol.float, self.inputParser.mouseRow.float)
          if not self.builder.handleMouseScroll(pos, vec2(0, event.scroll.delta.float), event.scroll.mods):
            self.onScroll.invoke (pos, vec2(0, event.scroll.delta.float), event.scroll.mods)
      of GridSize:
        self.gridSize = ivec2(event.width.int32, event.height.int32)
        self.requestRender(true)
      of PixelSize:
        self.pixelSize = ivec2(event.width.int32, event.height.int32)
        self.requestRender(true)
      of CellPixelSize:
        self.cellPixelSize = ivec2(event.width.int32, event.height.int32)
        self.requestRender(true)
      of KittyKeyboardFlags:
        if self.noUI:
          stdout.write &"KittyKeyboardFlags: current: {event.flags.toBin(5)}, requested: {self.kittyKeyboardFlags.toBin(5)}\r\n"
        log lvlInfo, &"Enable kitty keyboard protol with flags {self.kittyKeyboardFlags.toBin(5)}"
        stdout.write(&"\e[>{self.kittyKeyboardFlags}u") # enable kitty keyboard protocol
        self.inputParser.enableEscapeTimeout = false
        self.useKittyKeyboard = true

      inc eventCounter
      inc self.eventCounter

    stdout.flushFile()

    let terminalSize = self.getTerminalSize()
    let sizeChanged = self.buffer.width != terminalSize.x.int or self.buffer.height != terminalSize.y.int
    if sizeChanged:
      self.requestRender(true)
    return eventCounter
  except:
    discard

proc toStdColor(color: chroma.Color): stdcolors.Color =
  let rgb = color.asRgb
  return stdcolors.rgb(rgb.r, rgb.g, rgb.b)

proc drawNode(builder: UINodeBuilder, platform: TerminalPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) {.gcsafe.}

proc flushBorders(self: TerminalPlatform) =
  self.buffer.write(self.borderBuffer, writeStyle = false)
  self.borderBuffer.clear(0, 0, int.high, int.high)

method render*(self: TerminalPlatform, rerender: bool) {.gcsafe.} =
  try:
    let terminalSize = self.getTerminalSize()
    let sizeChanged = self.buffer.width != terminalSize.x.int or self.buffer.height != terminalSize.y.int
    if rerender or sizeChanged:
      if sizeChanged:
        log(lvlInfo, fmt"Terminal size changed from {self.buffer.width}x{self.buffer.height} to {terminalSize.x}x{terminalSize.y}, recreate buffer")
        self.buffer.initTerminalBuffer(terminalSize.x, terminalSize.y)
        self.buffer.clear()
        self.borderBuffer.resize(terminalSize.x, terminalSize.y)
        self.redrawEverything = true

      if self.builder.root.lastSizeChange == self.builder.frameIndex:
        self.redrawEverything = true

      self.cursor.visible = false
      self.builder.drawNode(self, self.builder.root, force = self.redrawEverything)
      self.buffer.write(self.borderBuffer, writeStyle = false)
      self.flushBorders()

      # This can fail if the terminal was resized during rendering, but in that case we'll just rerender next frame
      try:
        if not self.noUI:
          {.gcsafe.}:
            self.buffer.display()

        self.redrawEverything = false
      except CatchableError as e:
        log(lvlError, fmt"Failed to display buffer: {e.msg}")
        stdout.write fmt"Failed to display buffer: {e.msg}\r\n"
        self.redrawEverything = true

    stdout.flushFile()
  except:
    discard


proc setForegroundColor(self: TerminalPlatform, color: chroma.Color) =
  if self.trueColorSupport:
    self.buffer.setForegroundColor(color.toStdColor)
  else:
    let stdColor = color.toStdColor.extractRGB
    let fgColor = getClosestColor[tui.ForegroundColor](stdColor.r, stdColor.g, stdColor.b, tui.fgWhite)
    self.buffer.setForegroundColor(fgColor)

proc setBackgroundColor(self: TerminalPlatform, color: chroma.Color) =
  if self.trueColorSupport:
    self.buffer.setBackgroundColor(color.toStdColor, color.a)
  else:
    let stdColor = color.toStdColor.extractRGB
    let bgColor = getClosestColor[tui.BackgroundColor](stdColor.r, stdColor.g, stdColor.b, tui.bgBlack)
    self.buffer.setBackgroundColor(bgColor)

proc fillRect(self: TerminalPlatform, bounds: Rect, color: chroma.Color) =
  let mask = if self.masks.len > 0:
    self.masks[self.masks.high]
  else:
    rect(vec2(0, 0), self.size)

  let bounds = bounds and mask

  self.setBackgroundColor(color)
  self.buffer.fillBackground(bounds.x.int, bounds.y.int, bounds.xw.int - 1, bounds.yh.int - 1)
  self.buffer.setBackgroundColor(bgNone)
  self.borderBuffer.clear(bounds.x.int + 1, bounds.y.int + 1, bounds.xw.int - 1 - 1, bounds.yh.int - 1 - 1)

proc drawRect(self: TerminalPlatform, bounds: Rect, color: chroma.Color) =
  let mask = if self.masks.len > 0:
    self.masks[self.masks.high]
  else:
    rect(vec2(0, 0), self.size)

  let bounds = bounds and mask

  self.setForegroundColor(color)
  self.buffer.drawRect(bounds.x.int, bounds.y.int, bounds.xw.int - 1, bounds.yh.int - 1)

proc drawBorder(self: TerminalPlatform, bounds: Rect, color: chroma.Color, border: UIBorder, backgroundColor: chroma.Color) =
  let mask = if self.masks.len > 0:
    self.masks[self.masks.high]
  else:
    rect(vec2(0, 0), self.size)

  var boundsMaskedV = bounds and rect(mask.x, float.low, mask.w, float.high)
  var boundsMaskedH = bounds and rect(float.low, mask.y, float.high, mask.h)

  self.setForegroundColor(color)
  self.setBackgroundColor(backgroundColor)
  if border.left > 0:
    self.fillRect(rect(bounds.x, bounds.y, 1, bounds.h), backgroundColor)
    self.buffer.drawVertLine(bounds.x.int, boundsMaskedH.y.int, boundsMaskedH.yh.int - 1)
    self.borderBuffer.drawVertLine(bounds.x.int, boundsMaskedH.y.int, boundsMaskedH.yh.int - 1)
  if border.right > 0:
    self.fillRect(rect(bounds.xw - 1, bounds.y, 1, bounds.h), backgroundColor)
    self.buffer.drawVertLine(bounds.xw.int - 1, boundsMaskedH.y.int, boundsMaskedH.yh.int - 1)
    self.borderBuffer.drawVertLine(bounds.xw.int - 1, boundsMaskedH.y.int, boundsMaskedH.yh.int - 1)
  if border.top > 0:
    self.fillRect(rect(bounds.x, bounds.y, bounds.w, 1), backgroundColor)
    self.buffer.drawHorizLine(boundsMaskedV.x.int, boundsMaskedV.xw.int - 1, bounds.y.int)
    self.borderBuffer.drawHorizLine(boundsMaskedV.x.int, boundsMaskedV.xw.int - 1, bounds.y.int)
  if border.bottom > 0:
    self.fillRect(rect(bounds.x, bounds.yh - 1, bounds.w, 1), backgroundColor)
    self.buffer.drawHorizLine(boundsMaskedV.x.int, boundsMaskedV.xw.int - 1, bounds.yh.int - 1)
    self.borderBuffer.drawHorizLine(boundsMaskedV.x.int, boundsMaskedV.xw.int - 1, bounds.yh.int - 1)

# proc drawRect(self: TerminalPlatform, bounds: Rect, color: chroma.Color) =
#   let mask = if self.masks.len > 0:
#     self.masks[self.masks.high]
#   else:
#     rect(vec2(0, 0), self.size)

#   let bounds = bounds and mask

#   self.setBackgroundColor(color)
#   self.buffer.drawRect(bounds.x.int, bounds.y.int, bounds.xw.int - 1, bounds.yh.int - 1)
#   self.buffer.setBackgroundColor(bgNone)

proc writeLine(self: TerminalPlatform, pos: Vec2, text: string, italic: bool) =
  let mask = if self.masks.len > 0:
    self.masks[self.masks.high]
  else:
    rect(vec2(0, 0), self.size)

  # Check if text outside vertically
  if pos.y < mask.y or pos.y >= mask.yh:
    return

  var x = pos.x.int
  for r in text.runes:
    let props = r.runeProps
    if x >= mask.x.int and x + props.displayWidth <= mask.xw.int:
      self.buffer.writeRune(x, pos.y.int, r, props.selectionWidth, props.displayWidth - props.selectionWidth, italic)
    x += props.displayWidth
    if x >= mask.xw.int:
      break

proc nextWrapBoundary(str: openArray[char], start: int, maxLen: RuneCount): (int, RuneCount) {.gcsafe.} =
  var len = 0.RuneCount
  var bytes = 0
  while start + bytes < str.len and len < maxLen:
    let rune = str.runeAt(start + bytes)
    if bytes > 0 and rune.isWhiteSpace:
      break
    inc len
    bytes += str.runeLenAt(start + bytes)

  return (bytes, len)

proc writeText(self: TerminalPlatform, pos: Vec2, text: string, color: chroma.Color, spaceColor: chroma.Color, spaceRune: Rune, wrap: bool, lineLen: RuneCount, italic: bool, flags: UINodeFlags) =
  var yOffset = 0.0

  let spaceText = $spaceRune

  self.setForegroundColor(color)
  for line in text.splitLines:
    let runeLen = line.runeLen

    if wrap and runeLen > lineLen:
      var startByte = 0
      var startRune = 0.RuneIndex

      while startByte < line.len:
        var endByte = startByte
        var endRune = startRune
        var currentRuneLen = 0.RuneCount

        while true:
          let (bytes, runes) = line.nextWrapBoundary(endByte, lineLen - currentRuneLen)
          if currentRuneLen + runes >= lineLen.RuneIndex or bytes == 0:
            break

          endByte += bytes
          endRune += runes
          currentRuneLen += runes

        if startByte >= line.len or endByte > line.len:
          break

        self.writeLine(pos + vec2(0, yOffset), line[startByte..<endByte], italic)

        yOffset += 1

        if startByte == endByte:
          break

        startByte = endByte
        startRune = endRune

    else:
      if TextDrawSpaces in flags:
        var start = 0
        var i = line.find(' ')
        if i == -1:
          self.writeLine(pos + vec2(0, yOffset), line, italic)
        else:
          while i != -1:
            self.writeLine(pos + vec2(start.float, yOffset), line[start..<i], italic)
            self.setForegroundColor(spaceColor)
            self.writeLine(pos + vec2(i.float, yOffset), spaceText, italic)
            self.setForegroundColor(color)
            start = i + 1
            i = line.find(' ', start)

          if start < line.len:
            self.writeLine(pos + vec2(start.float, yOffset), line[start..^1], italic)
      else:
        self.writeLine(pos + vec2(0, yOffset), line, italic)
      yOffset += 1

proc handleCommand(builder: UINodeBuilder, platform: TerminalPlatform, renderCommands: ptr RenderCommands, command: RenderCommand, offsets: var seq[Vec2], offset: var Vec2) =
  const cursorFlags = &{CursorBlock, CursorBar, CursorUnderline, CursorBlinking}
  case command.kind
  of RenderCommandKind.Rect:
    platform.drawRect(command.bounds + offset, command.color)
  of RenderCommandKind.FilledRect:
    if command.flags * cursorFlags != 0.UINodeFlags:
      let pos = command.bounds + offset
      platform.cursor.shape = command.flags * cursorFlags
      platform.cursor.visible = true
      platform.cursor.col = pos.x.int
      platform.cursor.row = pos.y.int
    else:
      platform.fillRect(command.bounds + offset, command.color)
  of RenderCommandKind.Image:
    discard
  of RenderCommandKind.TextRaw:
    var text = newStringOfCap(command.len)
    if command.len > 0:
      text.setLen(command.len)
      copyMem(text[0].addr, command.data, command.len)
      platform.buffer.setBackgroundColor(bgNone)
      platform.writeText(command.bounds.xy + offset, text, command.color, renderCommands.spacesColor, renderCommands.space, TextWrap in command.flags, round(command.bounds.w).RuneCount, TextItalic in command.flags, command.flags)
  of RenderCommandKind.Text:
    # todo: don't copy string data
    let text = renderCommands.strings[command.textOffset..<command.textOffset + command.textLen]
    platform.buffer.setBackgroundColor(bgNone)
    platform.writeText(command.bounds.xy + offset, text, command.color, renderCommands.spacesColor, renderCommands.space, TextWrap in command.flags, round(command.bounds.w).RuneCount, TextItalic in command.flags, command.flags)
  of RenderCommandKind.ScissorStart:
    platform.pushMask(command.bounds + offset)
  of RenderCommandKind.ScissorEnd:
    platform.popMask()
  of RenderCommandKind.TransformStart:
    offsets.add offset
    offset += command.bounds.xy
  of RenderCommandKind.TransformEnd:
    if offsets.len > 0:
      offset = offsets.pop()

proc drawNode(builder: UINodeBuilder, platform: TerminalPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) =
  {.gcsafe.}:
    var nodePos = offset
    nodePos.x += node.boundsActual.x
    nodePos.y += node.boundsActual.y

    var force = force

    if builder.useInvalidation and not force and node.lastChange < builder.frameIndex:
      return

    node.lastRenderTime = builder.frameIndex

    if node.flags.any &{UINodeFlag.FillBackground, DrawText}:
      force = true

    node.lx = nodePos.x
    node.ly = nodePos.y
    node.lw = node.boundsActual.w
    node.lh = node.boundsActual.h
    let bounds = rect(nodePos.x, nodePos.y, node.boundsActual.w, node.boundsActual.h)

    const cursorFlags = &{CursorBlock, CursorBar, CursorUnderline, CursorBlinking}
    if FillBackground in node.flags:
      if node.flags * cursorFlags != 0.UINodeFlags:
        platform.cursor.shape = node.flags * cursorFlags
        platform.cursor.visible = true
        platform.cursor.col = bounds.x.int
        platform.cursor.row = bounds.y.int
      else:
        platform.fillRect(bounds, node.backgroundColor)

    # Mask the rest of the rendering is this function to the contentBounds
    if MaskContent in node.flags:
      platform.pushMask(bounds)
    defer:
      if MaskContent in node.flags:
        platform.popMask()

    if DrawText in node.flags:
      platform.buffer.setBackgroundColor(bgNone)
      platform.writeText(bounds.xy, node.text, node.textColor, node.textColor, ' '.Rune, TextWrap in node.flags, round(bounds.w).RuneCount, TextItalic in node.flags, node.flags)

    if DrawChildrenReverse in node.flags:
      for c in node.rchildren:
        builder.drawNode(platform, c, nodePos, force)
    else:
      for _, c in node.children:
        builder.drawNode(platform, c, nodePos, force)

    if FlushBorders in node.flags:
      platform.flushBorders()

    var offset = nodePos
    var offsets: seq[Vec2]
    for list in node.renderCommandList:
      offsets.setLen(0)
      offset = nodePos
      for command in list.commands:
        handleCommand(builder, platform, list[].addr, command, offsets, offset)

      offsets.setLen(0)
      offset = nodePos
      for command in list[].decodeRenderCommands:
        handleCommand(builder, platform, list[].addr, command, offsets, offset)

    offsets.setLen(0)
    offset = nodePos
    for command in node.renderCommands.commands:
      handleCommand(builder, platform, node.renderCommands.addr, command, offsets, offset)

    offsets.setLen(0)
    offset = nodePos
    for command in node.renderCommands.decodeRenderCommands:
      handleCommand(builder, platform, node.renderCommands.addr, command, offsets, offset)

    if DrawBorderTerminal in node.flags:
      platform.drawBorder(bounds, node.borderColor, node.border, node.backgroundColor)
