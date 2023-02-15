import custom_logger

logger.enableFileLogger()
logger.enableConsoleLogger()

import boxy, opengl, windy
import monitors
import input, editor, editor_render
import std/[asyncdispatch, strformat]
from scripting_api import Backend

let window = newWindow("Absytree", ivec2(1280, 800))
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

proc toInput(rune: Rune): int64 =
  return rune.int64

proc toInput(button: Button): int64 =
  return case button
  of KeyEnter: INPUT_ENTER
  of KeyEscape: INPUT_ESCAPE
  of KeyBackspace: INPUT_BACKSPACE
  of KeySpace: INPUT_SPACE
  of KeyDelete: INPUT_DELETE
  of KeyTab: INPUT_TAB
  of KeyLeft: INPUT_LEFT
  of KeyRight: INPUT_RIGHT
  of KeyUp: INPUT_UP
  of KeyDown: INPUT_DOWN
  of KeyHome: INPUT_HOME
  of KeyEnd: INPUT_END
  of KeyPageUp: INPUT_PAGE_UP
  of KeyPageDown: INPUT_PAGE_DOWN
  of KeyA..KeyZ: ord(button) - ord(KeyA) + ord('a')
  of Key0..Key9: ord(button) - ord(Key0) + ord('0')
  of Numpad0..Numpad9: ord(button) - ord(Numpad0) + ord('0')
  of KeyF1..KeyF12: INPUT_F1 - (ord(button) - ord(KeyF1))
  of NumpadAdd: ord '+'
  of NumpadSubtract: ord '-'
  of NumpadMultiply: ord '*'
  of NumpadDivide: ord '/'
  else: 0

window.centerWindowOnMonitor(1)
window.maximized = true

makeContextCurrent(window)
loadExtensions()
enableAutoGLerrorCheck(false)

let bxy = newBoxy()

var ed = newEditor(window, bxy, Gui, nil)

# Load the images.
# bxy.addImage("bg", readImage("examples/data/bg.png"))

# Called when it is time to draw a new frame.
window.onFrame = proc() =
  try:
    # if getOption[bool](ed, "editor.poll"):
    poll(2)
  except CatchableError:
    echo fmt"[async] Failed to poll async dispatcher: {getCurrentExceptionMsg()}"
    echo getCurrentException().getStackTrace()
    discard

  # Clear the screen and begin a new frame.
  bxy.beginFrame(window.size)
  ed.boxy2.beginFrame(window.size)

  # Draw the bg.
  # bxy.drawImage("bg", rect = rect(vec2(0, 0), window.size.vec2))

  ed.render()

  # End this frame, flushing the draw commands.
  bxy.endFrame()
  ed.boxy2.endFrame()

  # Swap buffers displaying the new Boxy frame.
  window.swapBuffers()

var currentModifiers: Modifiers = {}
var currentMouseButtons: set[MouseButton] = {}

window.onFocusChange = proc() =
  currentModifiers = {}
  currentMouseButtons = {}

window.onRune = proc(rune: Rune) =
  if rune.int32 in char.low.ord .. char.high.ord:
    case rune.char
    of ' ': return
    else: discard

  ed.handleRune(rune.toInput, currentModifiers)

window.onScroll = proc() =
  ed.handleScroll(window.scrollDelta, window.mousePos.vec2, {})

window.onMouseMove = proc() =
  ed.handleMouseMove(window.mousePos.vec2, window.mouseDelta.vec2, {}, currentMouseButtons)

proc toMouseButton(button: Button): MouseButton =
  result = case button:
    of MouseLeft: MouseButton.Left
    of MouseMiddle: MouseButton.Middle
    of MouseRight: MouseButton.Right
    of DoubleClick: MouseButton.DoubleClick
    of TripleClick: MouseButton.TripleClick
    else: MouseButton.Unknown

window.onButtonPress = proc(button: Button) =
  # If the key event would also generate a char afterwards then ignore it, except for some special keys
  if isNextMsgChar():
    case button:
    of KeySpace, KeyEnter: discard
    else: return

  case button
  of  MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
    currentMouseButtons.incl button.toMouseButton
    ed.handleMousePress(button.toMouseButton, currentModifiers, window.mousePos.vec2)
  of KeyLeftShift, KeyRightShift: currentModifiers = currentModifiers + {Shift}
  of KeyLeftControl, KeyRightControl: currentModifiers = currentModifiers + {Control}
  of KeyLeftAlt, KeyRightAlt: currentModifiers = currentModifiers + {Alt}
  # of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers + {Super}
  else:
    ed.handleKeyPress(button.toInput, currentModifiers)

window.onButtonRelease = proc(button: Button) =
  case button
  of  MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
    currentMouseButtons.excl button.toMouseButton
    ed.handleMouseRelease(button.toMouseButton, currentModifiers, window.mousePos.vec2)
  of KeyLeftShift, KeyRightShift: currentModifiers = currentModifiers - {Shift}
  of KeyLeftControl, KeyRightControl: currentModifiers = currentModifiers - {Control}
  of KeyLeftAlt, KeyRightAlt: currentModifiers = currentModifiers - {Alt}
  # of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers - {Super}
  else:
    ed.handleKeyRelease(button.toInput, currentModifiers)

addTimer 1000, false, proc(fd: AsyncFD): bool =
  return false

while not ed.closeRequested and not window.closeRequested:
  pollEvents()

ed.shutdown()
