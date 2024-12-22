import std/[strformat, terminal, typetraits, enumutils, strutils, sets]
import std/colors as stdcolors
import vmath
import chroma as chroma
import misc/[custom_logger, rect_utils, event, timer, custom_unicode]
import tui, input, ui/node
import platform

export platform

logCategory "terminal-platform"

type
  TerminalPlatform* = ref object of Platform
    buffer: TerminalBuffer
    trueColorSupport*: bool
    mouseButtons: set[input.MouseButton]
    masks: seq[Rect]

    doubleClickTimer: Timer
    doubleClickCounter: int
    doubleClickTime: float

proc exitProc() {.noconv.} =
  resetAttributes()
  myDisableTrueColors()
  illwillDeinit()
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

proc runeProps(r: Rune): tuple[selectionWidth: int, displayWidth: int] {.gcsafe.} =
  if r.int <= 127:
    return (1, 1)

  {.gcsafe.}:
    if r in narrowWideSet:
      return (2, 2)
    if r in wideNarrowSet:
      return (1, 2)

  return (1, 1)

method init*(self: TerminalPlatform) =
  try:
    illwillInit(fullscreen=true, mouse=true)
    setControlCHook(exitProc)
    hideCursor()

    self.builder = newNodeBuilder()
    self.builder.useInvalidation = true
    self.builder.charWidth = 1
    self.builder.lineHeight = 1
    self.builder.lineGap = 0

    self.supportsThinCursor = false
    self.doubleClickTime = 0.35

    self.focused = true

    if myEnableTrueColors():
      log(lvlInfo, "Enable true color support")
      self.trueColorSupport = true
    else:
      when not defined(posix):
        log(lvlError, "Failed to enable true color support")
      else:
        log(lvlInfo, "Enable true color support")
        self.trueColorSupport = true

    self.layoutOptions.getTextBounds = proc(text: string, fontSizeIncreasePercent: float = 0): Vec2 =
      result.x = text.len.float
      result.y = 1

    self.buffer = newTerminalBuffer(terminalWidth(), terminalHeight())
    self.redrawEverything = true

    self.builder.textWidthImpl = proc(node: UINode): float32 {.gcsafe, raises: [].} =
      for r in node.text.runes:
        result += r.runeProps.displayWidth.float32

    self.builder.textWidthStringImpl = proc(text: string): float32 {.gcsafe, raises: [].} =
      for r in text.runes:
        result += r.runeProps.displayWidth.float32
  except:
    discard

method deinit*(self: TerminalPlatform) =
  try:
    resetAttributes()
    myDisableTrueColors()
    illwillDeinit()
    showCursor()
  except:
    discard

method requestRender*(self: TerminalPlatform, redrawEverything = false) =
  self.requestedRender = true
  self.redrawEverything = self.redrawEverything or redrawEverything

method size*(self: TerminalPlatform): Vec2 = vec2(self.buffer.width.float, self.buffer.height.float)

method sizeChanged*(self: TerminalPlatform): bool =
  let (w, h) = (terminalWidth(), terminalHeight())
  return self.buffer.width != w or self.buffer.height != h

method fontSize*(self: TerminalPlatform): float = 1
method lineDistance*(self: TerminalPlatform): float = 0
method lineHeight*(self: TerminalPlatform): float = 1
method charWidth*(self: TerminalPlatform): float = 1
method charGap*(self: TerminalPlatform): float = 0
method measureText*(self: TerminalPlatform, text: string): Vec2 = vec2(text.len.float, 1)

proc pushMask(self: TerminalPlatform, mask: Rect) =
  let maskedMask = if self.masks.len > 0:
    self.masks[self.masks.high] and mask
  else:
    mask
  self.masks.add maskedMask

proc popMask(self: TerminalPlatform) =
  assert self.masks.len > 0
  discard self.masks.pop()

proc toInput(key: Key, modifiers: var Modifiers): int64 =
  return case key
  of Key.Enter: INPUT_ENTER
  of Key.Escape: INPUT_ESCAPE
  of Key.Backspace: INPUT_BACKSPACE
  of Key.Space: INPUT_SPACE
  of Key.Delete: INPUT_DELETE
  of Key.Tab: INPUT_TAB
  of Key.Left: INPUT_LEFT
  of Key.Right: INPUT_RIGHT
  of Key.Up: INPUT_UP
  of Key.Down: INPUT_DOWN
  of Key.Home: INPUT_HOME
  of Key.End: INPUT_END
  of Key.PageUp: INPUT_PAGE_UP
  of Key.PageDown: INPUT_PAGE_DOWN
  of Key.A..Key.Z: ord(key) - ord(Key.A) + ord('a')
  of Key.ShiftA..Key.ShiftZ:
    modifiers.incl Modifier.Shift
    ord(key) - ord(Key.ShiftA) + ord('A')
  of Key.CtrlA..Key.CtrlH, Key.CtrlJ..Key.CtrlL, Key.CtrlN..Key.CtrlZ:
    modifiers.incl Modifier.Control
    ord(key) - ord(Key.CtrlA) + ord('a')
  of Key.Zero..Key.Nine: ord(key) - ord(Key.Zero) + ord('0')
  of Key.F1..Key.F12: INPUT_F1 - (ord(key) - ord(Key.F1))

  of Key.ExclamationMark : '!'.int64
  of Key.DoubleQuote     : '"'.int64
  of Key.Hash            : '#'.int64
  of Key.Dollar          : '$'.int64
  of Key.Percent         : '%'.int64
  of Key.Ampersand       : '&'.int64
  of Key.SingleQuote     : '\''.int64
  of Key.LeftParen       : '('.int64
  of Key.RightParen      : ')'.int64
  of Key.Asterisk        : '*'.int64
  of Key.Plus            : '+'.int64
  of Key.Comma           : ','.int64
  of Key.Minus           : '-'.int64
  of Key.Dot             : '.'.int64
  of Key.Slash           : '/'.int64

  of Colon        : ':'.int64
  of Semicolon    : ';'.int64
  of LessThan     : '<'.int64
  of Equals       : '='.int64
  of GreaterThan  : '>'.int64
  of QuestionMark : '?'.int64
  of At           : '@'.int64

  of LeftBracket  : '['.int64
  of Backslash    : '\\'.int64
  of RightBracket : ']'.int64
  of Caret        : '^'.int64
  of Underscore   : '_'.int64
  of GraveAccent  : '`'.int64

  of LeftBrace  : '{'.int64
  of Pipe       : '|'.int64
  of RightBrace : '}'.int64
  of Tilde      : '~'.int64


  # of Numpad0..Numpad9: ord(key) - ord(Numpad0) + ord('0')
  # of NumpadAdd: ord '+'
  # of NumpadSubtract: ord '-'
  # of NumpadMultiply: ord '*'
  # of NumpadDivide: ord '/'
  else:
    log lvlError, fmt"Unknown input {key}"
    0

method processEvents*(self: TerminalPlatform): int {.gcsafe.} =
  try:
    var eventCounter = 0
    while true:
      let key = getKey()
      if key == Key.None:
        break

      inc eventCounter

      if key == Mouse:
        let mouseInfo = getMouse()
        let pos = vec2(mouseInfo.x.float, mouseInfo.y.float)
        let button: input.MouseButton = case mouseInfo.button
        of mbLeft: input.MouseButton.Left
        of mbMiddle: input.MouseButton.Middle
        of mbRight: input.MouseButton.Right
        else: input.MouseButton.Unknown

        var modifiers: Modifiers = {}
        if mouseInfo.ctrl:
          modifiers.incl Modifier.Control
        if mouseInfo.shift:
          modifiers.incl Modifier.Shift

        if mouseInfo.scroll:
          let scroll = if mouseInfo.scrollDir == ScrollDirection.sdDown: -1.0 else: 1.0

          if not self.builder.handleMouseScroll(pos, vec2(0, scroll), {}):
            self.onScroll.invoke (pos, vec2(0, scroll), {})
        elif mouseInfo.move:
          # log(lvlInfo, fmt"move to {pos}")
          if not self.builder.handleMouseMoved(pos, self.mouseButtons):
            self.onMouseMove.invoke (pos, vec2(0, 0), {}, self.mouseButtons)
        else:
          # log(lvlInfo, fmt"{mouseInfo.action} {button} at {pos}")
          case mouseInfo.action
          of mbaPressed:
            self.mouseButtons.incl button

            var events = @[button]

            if button == input.MouseButton.Left:
              if self.doubleClickTimer.elapsed.float < self.doubleClickTime:
                inc self.doubleClickCounter
                case self.doubleClickCounter
                of 1:
                  events.add input.MouseButton.DoubleClick
                of 2:
                  events.add input.MouseButton.TripleClick
                else:
                  self.doubleClickCounter = 0
              else:
                self.doubleClickCounter = 0

              self.doubleClickTimer = startTimer()
            else:
              self.doubleClickCounter = 0

            for event in events:
              if not self.builder.handleMousePressed(event, modifiers, pos):
                self.onMousePress.invoke (event, modifiers, pos)

          of mbaReleased:
            self.mouseButtons = {}
            if not self.builder.handleMouseReleased(button, modifiers, pos):
              self.onMouseRelease.invoke (button, modifiers, pos)
          else:
            discard

      else:
        var modifiers: Modifiers = {}
        let button = key.toInput(modifiers)
        # debugf"key press k: {key}, input: {inputToString(button, modifiers)}"
        if not self.builder.handleKeyPressed(button, modifiers):
          self.onKeyPress.invoke (button, modifiers)

    return eventCounter
  except:
    discard

proc toStdColor(color: chroma.Color): stdcolors.Color =
  let rgb = color.asRgb
  return stdcolors.rgb(rgb.r, rgb.g, rgb.b)

proc drawNode(builder: UINodeBuilder, platform: TerminalPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) {.gcsafe.}

method render*(self: TerminalPlatform) {.gcsafe.} =
  try:
    if self.sizeChanged:
      let (w, h) = (terminalWidth(), terminalHeight())
      log(lvlInfo, fmt"Terminal size changed from {self.buffer.width}x{self.buffer.height} to {w}x{h}, recreate buffer")
      self.buffer = newTerminalBuffer(w, h)
      self.redrawEverything = true

    if self.builder.root.lastSizeChange == self.builder.frameIndex:
      self.redrawEverything = true

    self.builder.drawNode(self, self.builder.root, force = self.redrawEverything)

    # This can fail if the terminal was resized during rendering, but in that case we'll just rerender next frame
    try:
      {.gcsafe.}:
        self.buffer.display()
      self.redrawEverything = false
    except CatchableError:
      log(lvlError, fmt"Failed to display buffer: {getCurrentExceptionMsg()}")
      self.redrawEverything = true
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

proc nextWrapBoundary(str: openArray[char], start: int, maxLen: RuneCount): (int, RuneCount) =
  var len = 0.RuneCount
  var bytes = 0
  while start + bytes < str.len and len < maxLen:
    let rune = str.runeAt(start + bytes)
    if bytes > 0 and rune.isWhiteSpace:
      break
    inc len
    bytes += str.runeLenAt(start + bytes)

  return (bytes, len)

proc writeText(self: TerminalPlatform, pos: Vec2, text: string, wrap: bool, lineLen: RuneCount, italic: bool) =
  var yOffset = 0.0

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
      self.writeLine(pos + vec2(0, yOffset), line, italic)
      yOffset += 1

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

    if FillBackground in node.flags:
      platform.fillRect(bounds, node.backgroundColor)

    # Mask the rest of the rendering is this function to the contentBounds
    if MaskContent in node.flags:
      platform.pushMask(bounds)
    defer:
      if MaskContent in node.flags:
        platform.popMask()

    if DrawText in node.flags:
      platform.buffer.setBackgroundColor(bgNone)
      platform.setForegroundColor(node.textColor)
      platform.writeText(bounds.xy, node.text, TextWrap in node.flags, round(bounds.w).RuneCount, TextItalic in node.flags)

    for _, c in node.children:
      builder.drawNode(platform, c, nodePos, force)

    for command in node.renderCommands:
      case command.kind
      of RenderCommandKind.Rect:
        platform.fillRect(command.bounds + offset, command.color)
      of RenderCommandKind.FilledRect:
        platform.fillRect(command.bounds + offset, command.color)
      of RenderCommandKind.Text:
        platform.buffer.setBackgroundColor(bgNone)
        platform.setForegroundColor(command.color)
        platform.writeText(command.bounds.xy + offset, command.text, TextWrap in command.flags, round(command.bounds.w).RuneCount, TextItalic in command.flags)

    # if DrawBorder in node.flags:
    #   platform.drawRect(bounds, node.borderColor)
