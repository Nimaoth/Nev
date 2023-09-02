import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, random, tables, sets, strmisc]
import src/macro_utils, src/util, src/id
import boxy, boxy/textures, pixie, windy, vmath, rect_utils, opengl, timer, lrucache, ui/node
import custom_logger
import test_lib

logger.enableConsoleLogger()
logCategory "test", true

var logRoot = false
var logFrameTime = false
var showDrawnNodes = true

var advanceFrame = false
var invalidateOverlapping* = true

proc getFont*(font: string, fontSize: float32): Font =
  let typeface = readTypeface(font)

  result = newFont(typeface)
  result.paint.color = color(1, 1, 1)
  result.size = fontSize

var builder = newNodeBuilder()
builder.useInvalidation = true

let font = getFont("fonts/FiraCode-Regular.ttf", 17)
let bounds = font.typeset(repeat("#", 100)).layoutBounds()

builder.charWidth = bounds.x / 100.0
builder.lineHeight = bounds.y - 3
builder.lineGap = 6

var framebufferId: GLuint
var framebuffer: Texture

var window = newWindow("", ivec2(1680, 1080), WindowStyle.DecoratedResizable, vsync=false)
makeContextCurrent(window)
loadExtensions()
enableAutoGLerrorCheck(false)

var bxy = newBoxy()

framebuffer = Texture()
framebuffer.width = window.size.x
framebuffer.height = window.size.y
framebuffer.componentType = GL_UNSIGNED_BYTE
framebuffer.format = GL_RGBA
framebuffer.internalFormat = GL_RGBA8
framebuffer.minFilter = minLinear
framebuffer.magFilter = magLinear
bindTextureData(framebuffer, nil)

glGenFramebuffers(1, framebufferId.addr)
glBindFramebuffer(GL_FRAMEBUFFER, framebufferId)
glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, framebuffer.textureId, 0)
glBindFramebuffer(GL_FRAMEBUFFER, 0)
bxy.setTargetFramebuffer framebufferId

var drawnNodes: seq[UINode] = @[]

var cachedImages: LruCache[string, string] = newLruCache[string, string](1000, true)

proc strokeRect*(boxy: Boxy, rect: Rect, color: Color, thickness: float = 1, offset: float = 0) =
  let rect = rect.grow(vec2(thickness * offset, thickness * offset))
  boxy.drawRect(rect.splitV(thickness.relative)[0].shrink(vec2(0, thickness)), color)
  boxy.drawRect(rect.splitVInv(thickness.relative)[1].shrink(vec2(0, thickness)), color)
  boxy.drawRect(rect.splitH(thickness.relative)[0], color)
  boxy.drawRect(rect.splitHInv(thickness.relative)[1], color)

proc drawNode(builder: UINodeBuilder, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) =
  var nodePos = offset
  nodePos.x += node.boundsActual.x
  nodePos.y += node.boundsActual.y

  var force = force

  if invalidateOverlapping and not force and node.lastChange < builder.frameIndex:
    return

  if node.flags.any &{FillBackground, DrawBorder, DrawText}:
    drawnNodes.add node

  if node.flags.any &{FillBackground, DrawText}:
    force = true

  debug "draw ", node.dump

  node.lx = nodePos.x
  node.ly = nodePos.y
  node.lw = node.boundsActual.w
  node.lh = node.boundsActual.h
  let bounds = rect(nodePos.x, nodePos.y, node.boundsActual.w, node.boundsActual.h)

  if FillBackground in node.flags:
    bxy.drawRect(bounds, node.backgroundColor)

  # Mask the rest of the rendering is this function to the contentBounds
  if MaskContent in node.flags:
    bxy.pushLayer()
  defer:
    if MaskContent in node.flags:
      bxy.pushLayer()
      bxy.drawRect(bounds, color(1, 0, 0, 1))
      bxy.popLayer(blendMode = MaskBlend)
      bxy.popLayer()

  if DrawText in node.flags:
    let key = node.text
    var imageId: string
    if cachedImages.contains(key):
      imageId = cachedImages[key]
    else:
      imageId = $newId()
      cachedImages[key] = imageId

      const wrap = false
      let wrapBounds = if wrap: vec2(node.boundsActual.w, node.boundsActual.h) else: vec2(0, 0)
      let arrangement = font.typeset(node.text, bounds=wrapBounds)
      var bounds = arrangement.layoutBounds()
      if bounds.x == 0:
        bounds.x = 1
      if bounds.y == 0:
        bounds.y = builder.textHeight

      var image = newImage(bounds.x.int, bounds.y.int)
      image.fillText(arrangement)
      bxy.addImage(imageId, image, false)

    let pos = vec2(nodePos.x.floor, nodePos.y.floor)
    bxy.drawImage(imageId, pos, node.textColor)

  for _, c in node.children:
    builder.drawNode(c, nodePos, force)

  if DrawBorder in node.flags:
    bxy.strokeRect(bounds, node.borderColor)

proc randomColor(node: UINode, a: float32): Color =
  let h = node.id.hash
  result.r = (((h shr 0) and 0xff).float32 / 255.0).sqrt
  result.g = (((h shr 8) and 0xff).float32 / 255.0).sqrt
  result.b = (((h shr 16) and 0xff).float32 / 255.0).sqrt
  result.a = a

proc renderNewFrame(builder: UINodeBuilder, force: bool): bool =
  # let buildTime = startTimer()
  result = false

  var force = force

  let size = if showDrawnNodes: window.size.vec2 * vec2(0.5, 1) else: window.size.vec2

  if advanceFrame:
    builder.beginFrame(size)
    builder.buildUINodes()
    builder.endFrame()
    result = true
  elif builder.animatingNodes.len > 0:
    builder.frameIndex.inc
    builder.postProcessNodes()
    result = true

  if builder.root.lastSizeChange == builder.frameIndex:
    force = true

  # echo "[build] ", buildTime.elapsed.ms, "ms"

  drawnNodes.setLen 0

  let drawTime = startTimer()
  if result:
    if logRoot:
      echo "frame ", builder.frameIndex
      echo builder.root.dump(true)

    builder.drawNode(builder.root, force = force)
  # echo "[draw] ", drawTime.elapsed.ms, "ms (", drawnNodes.len, " nodes)"

  if showDrawnNodes and result:
    bxy.pushLayer()
    defer:
      bxy.pushLayer()
      bxy.drawRect(rect(size.x, 0, size.x, size.y), color(1, 0, 0, 1))
      bxy.popLayer(blendMode = MaskBlend)
      bxy.popLayer()

    bxy.drawRect(rect(size.x, 0, size.x, size.y), color(0, 0, 0))

    for node in drawnNodes:
      let c = node.randomColor(0.3)
      bxy.drawRect(rect(node.lx + size.x, node.ly, node.lw, node.lh), c)

      if DrawBorder in node.flags:
        bxy.strokeRect(rect(node.lx + size.x, node.ly, node.lw, node.lh), color(c.r, c.g, c.b, 0.5), 5, offset = 0.5)

proc toMouseButton(button: Button): MouseButton =
  result = case button:
    of MouseLeft: MouseButton.Left
    of MouseMiddle: MouseButton.Middle
    of MouseRight: MouseButton.Right
    of DoubleClick: MouseButton.DoubleClick
    of TripleClick: MouseButton.TripleClick
    else: MouseButton.Unknown

window.onMouseMove = proc() =
  var mouseButtons: set[MouseButton]
  for button in set[Button](window.buttonDown):
    mouseButtons.incl button.toMouseButton

  advanceFrame = builder.handleMouseMoved(window.mousePos.vec2, mouseButtons) or advanceFrame

window.onButtonRelease = proc(button: Button) =
  case button
  of MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
    builder.handleMouseReleased(button.toMouseButton, window.mousePos.vec2)
    return
  else:
    return

  advanceFrame = true

window.onButtonPress = proc(button: Button) =
  # echo "pressed ", button

  var tempCursor = test_lib.cursor

  case button
  of MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
    builder.handleMousePressed(button.toMouseButton, window.mousePos.vec2)

  of Button.KeyX:
    window.closeRequested = true
    return
  of Button.KeyV:
    invalidateOverlapping = not invalidateOverlapping
  of Button.KeyL:
    showDrawnNodes = not showDrawnNodes
  of Button.KeyW:
    retainMainText = not retainMainText
  of Button.KeyU:
    logRoot = not logRoot
  of Button.KeyI:
    logFrameTime = not logFrameTime
  of Button.KeyA:
    logInvalidationRects = not logInvalidationRects
  of Button.KeyE:
    logPanel = not logPanel

  of Button.Key1:
    showPopup1 = not showPopup1

  of Button.Key2:
    showPopup2 = not showPopup2

  of Button.KeyF7:
    builder.animationSpeedModifier /= 2
    echo "anim speed: ", builder.animationSpeedModifier

  of Button.KeyF8:
    builder.animationSpeedModifier *= 2
    echo "anim speed: ", builder.animationSpeedModifier

  of Button.KeyUp:
    tempCursor[0] = max(0, tempCursor[0] - 1)
    tempCursor[1] = tempCursor[1].clamp(0, testText[tempCursor[0]].len)
    mainTextChanged = true
  of Button.KeyDown:
    tempCursor[0] = min(testText.high, tempCursor[0] + 1)
    tempCursor[1] = tempCursor[1].clamp(0, testText[tempCursor[0]].len)
    mainTextChanged = true

  of Button.KeyLeft:
    tempCursor[1] = max(0, tempCursor[1] - 1)
    mainTextChanged = true
  of Button.KeyRight:
    tempCursor[1] = min(testText[tempCursor[0]].len, tempCursor[1] + 1)
    mainTextChanged = true

  of Button.KeyHome:
    tempCursor[1] = 0
    mainTextChanged = true
  of Button.KeyEnd:
    tempCursor[1] = testText[tempCursor[0]].len
    mainTextChanged = true

  else:
    discard

  test_lib.cursor = tempCursor
  advanceFrame = true

advanceFrame = true
mainTextChanged = true

var frameTimer = startTimer()
while not window.closeRequested:
  let delta = frameTimer.elapsed.ms
  frameTimer = startTimer()

  pollEvents()

  var force = false

  if framebuffer.width != window.size.x.int32 or framebuffer.height != window.size.y.int32:
    framebuffer.width = window.size.x.int32
    framebuffer.height = window.size.y.int32
    bindTextureData(framebuffer, nil)
    advanceFrame = true
    force = true

  bxy.beginFrame(window.size, clearFrame=false)

  for image in cachedImages.removedKeys:
    bxy.removeImage(image)
  cachedImages.clearRemovedKeys()

  builder.frameTime = delta

  let tAdvanceFrame = startTimer()
  let drewSomething = builder.renderNewFrame(force)
  let msAdvanceFrame = tAdvanceFrame.elapsed.ms

  bxy.endFrame()

  if drewSomething:
    if logFrameTime:
      echo fmt"[frame {builder.frameIndex}] nodes: {drawnNodes.len:>4}, advance: {msAdvanceFrame:<5.3}, total: {frameTimer.elapsed.ms:<5.3}, last: {delta:<5.3}"

    glBindFramebuffer(GL_READ_FRAMEBUFFER, framebufferId)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
    glBlitFramebuffer(
      0, 0, framebuffer.width.GLint, framebuffer.height.GLint,
      0, 0, window.size.x.GLint, window.size.y.GLint,
      GL_COLOR_BUFFER_BIT, GL_NEAREST.GLenum)

    window.swapBuffers()

    # if frameTimer.elapsed.ms < 5:
    #   sleep(3)

  else:
    sleep(3)

  advanceFrame = false
  mainTextChanged = false

window.close()
