import boxy, opengl, times, windy
import winim/lean

let window = newWindow("Windy + Boxy", ivec2(1280, 800))

proc centerWindowOnMonitor(window: Window, monitor: int) =
  type MonitorSizeHelper = object
    index: int
    targetIndex: int
    rect: windef.RECT

  proc enumMonitor(monitor: HMONITOR, hdc: HDC, rect: LPRECT, data: LPARAM): WINBOOL {.stdcall.} =
    let helper = cast[ptr MonitorSizeHelper](data)
    if helper.index == helper.targetIndex:
      helper.rect = rect[]
      return 0

    inc helper.index
    return 1

  var helper = MonitorSizeHelper(index: 0, targetIndex: monitor, rect: windef.RECT(left: 0, right: 1920, top: 0, bottom: 1080))
  EnumDisplayMonitors(0, nil, enumMonitor, cast[LPARAM](addr helper))

  let left = float(helper.rect.left)
  let right = float(helper.rect.right)
  let top = float(helper.rect.top)
  let bottom = float(helper.rect.bottom)

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
  var font = newFont(typeface)
  font.size = size
  font.paint = color
  let
    arrangement = typeset(@[newSpan(text, font)], bounds = vec2(1280, 800))
    globalBounds = arrangement.computeBounds(transform).snapToPixels()
    textImage = newImage(globalBounds.w.int, globalBounds.h.int)
    imageSpace = translate(-globalBounds.xy) * transform
  textImage.fillText(arrangement, imageSpace)

  bxy.addImage(imageKey, textImage)
  bxy.drawImage(imageKey, globalBounds.xy)

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

  # End this frame, flushing the draw commands.
  bxy.endFrame()
  # Swap buffers displaying the new Boxy frame.
  window.swapBuffers()

while not window.closeRequested:
  pollEvents()