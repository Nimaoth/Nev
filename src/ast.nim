import std/[strformat, bitops, strutils, tables, algorithm, math]
import boxy, opengl, times, windy
import monitors
import sugar
import input

let window = newWindow("Windy + Boxy", ivec2(1280, 800))
window.runeInputEnabled = true

proc centerWindowOnMonitor(window: Window, monitor: int) =
  let monitorPos = getMonitorRect(monitor)

  let left = float(monitorPos.left)
  let right = float(monitorPos.right)
  let top = float(monitorPos.top)
  let bottom = float(monitorPos.bottom)

  let windowWidth = float(window.size.x)
  let windowHeight = float(window.size.y)
  let monitorWidth = right - left
  let monitorHeight = bottom - top
  window.pos = ivec2(int32(left + (monitorWidth - windowWidth) / 2),
                     int32(top + (monitorHeight - windowHeight) / 2))

window.centerWindowOnMonitor(2)

makeContextCurrent(window)

loadExtensions()

let bxy = newBoxy()

# Load the images.
# bxy.addImage("bg", readImage("examples/data/bg.png"))

let typeface = readTypeface("fonts/FiraCode-Regular.ttf")

proc drawText(
  bxy: Boxy,
  imageKey: string,
  transform: Mat3,
  typeface: Typeface,
  text: string,
  size: float32,
  color: Color
) =
  if text == "":
    return
  var font = newFont(typeface)
  font.size = size
  font.paint = color
  let
    arrangement = typeset(@[newSpan(text, font)], bounds = vec2(1280, 800))
    globalBounds = arrangement.computeBounds(transform).snapToPixels()

  if globalBounds.w.int == 0 or globalBounds.h.int == 0:
    return

  let
    textImage = newImage(globalBounds.w.int, globalBounds.h.int)
    imageSpace = translate(-globalBounds.xy) * transform
  textImage.fillText(arrangement, imageSpace)

  bxy.addImage(imageKey, textImage)
  bxy.drawImage(imageKey, globalBounds.xy)

var inputBuffer = ""

# Called when it is time to draw a new frame.
window.onFrame = proc() =
  # Clear the screen and begin a new frame.
  bxy.beginFrame(window.size)

  # Draw the bg.
  # bxy.drawImage("bg", rect = rect(vec2(0, 0), window.size.vec2))

  bxy.drawText(
    "main-image",
    translate(vec2(100, 100)),
    typeface,
    "Current time:",
    80,
    color(1, 1, 1, 1)
  )

  bxy.drawText(
    "main-image2",
    translate(vec2(100, 200)),
    typeface,
    now().format("hh:mm:ss"),
    80,
    color(1, 1, 1, 1)
  )

  bxy.drawText(
    "main-image3",
    translate(vec2(100, 300)),
    typeface,
    inputBuffer,
    80,
    color(1, 1, 1, 1)
  )

  # End this frame, flushing the draw commands.
  bxy.endFrame()
  # Swap buffers displaying the new Boxy frame.
  window.swapBuffers()

var commands: seq[(string, string)] = @[]
for c in 'a'..'z':
  commands.add ($c, $c)
  commands.add ($c.toUpperAscii, $c.toUpperAscii)
for c in '0'..'9':
  commands.add ($c, $c)
commands.add ("ä", "ä")
commands.add ("Ä", "Ä")
commands.add ("ö", "ö")
commands.add ("Ö", "Ö")
commands.add ("ü", "ü")
commands.add ("Ü", "Ü")
commands.add ("<SPACE>", " ")
commands.add ("<ENTER>", "\n")
commands.add ("<BACKSPACE>", "backspace")
commands.add ("<DELETE>", "delete")
commands.add ("<ESCAPE>", "escape")
commands.add ("<C-x>", "quit")
commands.add ("<C-x>", "quit")
var dfa = buildDFA(commands)
dfa.dump(0, 0, {})
var state = 0

proc toInput(rune: Rune): int64 =
  return rune.int64

proc toInput(button: Button): int64 =
  return case button
  of KeyEnter: INPUT_ENTER
  of KeyEscape: INPUT_ESCAPE
  of KeyBackspace: INPUT_BACKSPACE
  of KeySpace: INPUT_SPACE
  of KeyDelete: INPUT_DELETE
  of KeyA..KeyZ: ord(button) - ord(KeyA) + ord('a')
  of Key0..Key9: ord(button) - ord(Key0) + ord('0')
  of Numpad0..Numpad9: ord(button) - ord(Numpad0) + ord('0')
  of NumpadAdd: ord '+'
  of NumpadSubtract: ord '-'
  of NumpadMultiply: ord '*'
  of NumpadDivide: ord '/'
  else: 0

var currentModifiers: Modifiers = {}

proc getCurrentModifiers(): Modifiers =
  if window.buttonDown[KeyLeftShift] or window.buttonDown[KeyRightShift]:
    result = result + {Shift}
  if window.buttonDown[KeyLeftControl] or window.buttonDown[KeyRightControl]:
    result = result + {Control}
  if window.buttonDown[KeyLeftAlt] or window.buttonDown[KeyRightAlt]:
    result = result + {Alt}
  if window.buttonDown[KeyLeftSuper] or window.buttonDown[KeyRightSuper]:
    result = result + {Super}

proc handleTerminalState(state: int) =
  let action = dfa.getAction(state)
  case action
  of "quit":
    window.closeRequested = true
  of "backspace":
    if inputBuffer.len > 0:
      inputBuffer = inputBuffer[0..<inputBuffer.len-1]
  else:
    let runes = action.toRunes
    if runes.len == 1:
      inputBuffer.add runes[0]
    else:
      echo "Action: '", action, "'"

window.onFocusChange = proc() =
  echo "onFocusChange ", window.focused
  currentModifiers = {}

window.onRune = proc(rune: Rune) =
  if rune.int32 in char.low.ord .. char.high.ord:
    case rune.char
    of ' ': return
    else: discard

  let input = rune.toInput()
  if input != 0:
    let modifiers = if rune.int64.isAscii and rune.char.isAlphaNumeric: currentModifiers else: {}

    state = dfa.step(state, input, modifiers)
    if state == 0:
      echo "Invalid input: ", inputToString(input, modifiers)

    if dfa.isTerminal(state):
      handleTerminalState(state)
      state = 0

window.onButtonPress = proc(button: Button) =
  # If the key event would also generate a char afterwards then ignore it, except for some special keys
  if isNextMsgChar():
    case button:
    of KeySpace, KeyEnter: discard
    else: return

  case button
  of KeyLeftShift, KeyRightShift: currentModifiers = currentModifiers + {Shift}
  of KeyLeftControl, KeyRightControl: currentModifiers = currentModifiers + {Control}
  of KeyLeftAlt, KeyRightAlt: currentModifiers = currentModifiers + {Alt}
  of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers + {Super}
  else:
    let input = button.toInput()
    if input != 0:
      state = dfa.step(state, input, currentModifiers)
      if state == 0:
        echo "Invalid input: ", inputToString(input, currentModifiers)


      if dfa.isTerminal(state):
        handleTerminalState(state)
        state = 0
    else:
      echo "Unknown button: ", button

window.onButtonRelease = proc(button: Button) =
  case button
  of KeyLeftShift, KeyRightShift: currentModifiers = currentModifiers - {Shift}
  of KeyLeftControl, KeyRightControl: currentModifiers = currentModifiers - {Control}
  of KeyLeftAlt, KeyRightAlt: currentModifiers = currentModifiers - {Alt}
  of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers - {Super}
  else:
    discard

while not window.closeRequested:
  pollEvents()
