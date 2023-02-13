import std/[os, strutils, strformat]
import renderer, widgets
import ../custom_logger, ../rect_utils, ../input, ../event, ../monitors, ../lru_cache
import vmath, windy, boxy, boxy/textures, opengl

import chroma as chroma
import colors as stdcolors

export renderer, widgets

type
  GuiRenderer* = ref object of Renderer
    window: Window
    ctx*: Context
    boxy: Boxy
    boxy2: Boxy
    currentModifiers: Modifiers
    currentMouseButtons: set[MouseButton]
    eventCounter: int

    lastSize: Vec2

    mLineDistance: float
    mCharWidth: float

    framebufferId: GLuint
    framebuffer: Texture

proc toInput(rune: Rune): int64
proc toInput(button: Button): int64
proc centerWindowOnMonitor(window: Window, monitor: int)

method init*(self: GuiRenderer) =
  self.window = newWindow("Absytree", ivec2(1280, 800), vsync=true)
  self.window.runeInputEnabled = true

  self.window.centerWindowOnMonitor(1)
  self.window.maximized = true
  makeContextCurrent(self.window)
  loadExtensions()

  # @todo
  enableAutoGLerrorCheck(false)

  self.framebuffer = Texture()
  self.framebuffer.width = self.size.x.int32
  self.framebuffer.height = self.size.y.int32
  self.framebuffer.componentType = GL_UNSIGNED_BYTE
  self.framebuffer.format = GL_RGBA
  self.framebuffer.internalFormat = GL_RGBA8
  self.framebuffer.minFilter = minLinear
  self.framebuffer.magFilter = magLinear
  bindTextureData(self.framebuffer, nil)

  glGenFramebuffers(1, self.framebufferId.addr)
  glBindFramebuffer(GL_FRAMEBUFFER, self.framebufferId)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.framebuffer.textureId, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

  self.boxy = newBoxy()
  self.boxy2 = newBoxy()
  self.ctx = newContext(1, 1)
  self.ctx.fillStyle = rgb(255, 255, 255)
  self.ctx.strokeStyle = rgb(255, 255, 255)
  self.ctx.font = "fonts/DejaVuSansMono.ttf"
  self.ctx.fontSize = 20
  self.ctx.textBaseline = TopBaseline

  self.window.onFocusChange = proc() =
    inc self.eventCounter
    self.currentModifiers = {}
    self.currentMouseButtons = {}

  self.window.onRune = proc(rune: Rune) =
    inc self.eventCounter
    if rune.int32 in char.low.ord .. char.high.ord:
      case rune.char
      of ' ': return
      else: discard

    self.onRune.invoke (rune.toInput, self.currentModifiers)

  self.window.onScroll = proc() =
    inc self.eventCounter
    self.onScroll.invoke (self.window.mousePos.vec2, self.window.scrollDelta, {})

  self.window.onMouseMove = proc() =
    inc self.eventCounter
    self.onMouseMove.invoke (self.window.mousePos.vec2, self.window.mouseDelta.vec2, {}, self.currentMouseButtons)

  proc toMouseButton(button: Button): MouseButton =
    inc self.eventCounter
    result = case button:
      of MouseLeft: MouseButton.Left
      of MouseMiddle: MouseButton.Middle
      of MouseRight: MouseButton.Right
      of DoubleClick: MouseButton.DoubleClick
      of TripleClick: MouseButton.TripleClick
      else: MouseButton.Unknown

  self.window.onButtonPress = proc(button: Button) =
    inc self.eventCounter
    # If the key event would also generate a char afterwards then ignore it, except for some special keys
    if isNextMsgChar():
      case button:
      of KeySpace, KeyEnter: discard
      else: return

    case button
    of  MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
      self.currentMouseButtons.incl button.toMouseButton
      self.onMousePress.invoke (button.toMouseButton, self.currentModifiers, self.window.mousePos.vec2)
    of KeyLeftShift, KeyRightShift: self.currentModifiers = self.currentModifiers + {Shift}
    of KeyLeftControl, KeyRightControl: self.currentModifiers = self.currentModifiers + {Control}
    of KeyLeftAlt, KeyRightAlt: self.currentModifiers = self.currentModifiers + {Alt}
    # of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers + {Super}
    else:
      self.onKeyPress.invoke (button.toInput, self.currentModifiers)

  self.window.onButtonRelease = proc(button: Button) =
    inc self.eventCounter
    case button
    of  MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
      self.currentMouseButtons.excl button.toMouseButton
      self.onMouseRelease.invoke (button.toMouseButton, self.currentModifiers, self.window.mousePos.vec2)
    of KeyLeftShift, KeyRightShift: self.currentModifiers = self.currentModifiers - {Shift}
    of KeyLeftControl, KeyRightControl: self.currentModifiers = self.currentModifiers - {Control}
    of KeyLeftAlt, KeyRightAlt: self.currentModifiers = self.currentModifiers - {Alt}
    # of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers - {Super}
    else:
      self.onKeyRelease.invoke (button.toInput, self.currentModifiers)

method deinit*(self: GuiRenderer) =
  self.window.close()

method size*(self: GuiRenderer): Vec2 =
  let size = self.window.size
  return vec2(size.x.float, size.y.float)

method sizeChanged*(self: GuiRenderer): bool =
  let s = self.size
  return s.x != self.lastSize.x or s.y != self.lastSize.y

proc updateCharWidth*(self: GuiRenderer) =
  # let tempArrangement = config.font.typeset("#")
  # var tempBounds = tempArrangement.layoutBounds()
  # ed.renderCtx.lineHeight = tempBounds.y
  # ed.renderCtx.charWidth = tempBounds.x
  # @todo
  self.mCharWidth = self.fontSize / 2

method `fontSize=`*(self: GuiRenderer, fontSize: float) =
  self.ctx.fontSize = fontSize
  self.updateCharWidth()

method `lineDistance=`*(self: GuiRenderer, lineDistance: float) = self.mLineDistance = lineDistance
method fontSize*(self: GuiRenderer): float = self.ctx.fontSize
method lineDistance*(self: GuiRenderer): float = self.mLineDistance
method lineHeight*(self: GuiRenderer): float = self.fontSize
method charWidth*(self: GuiRenderer): float = self.mCharWidth

method processEvents*(self: GuiRenderer): int =
  self.eventCounter = 0
  pollEvents()
  return self.eventCounter

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

method renderWidget(self: WWidget, renderer: GuiRenderer, forceRedraw: bool, frameIndex: int) {.base.} = discard

proc toChromaColor(color: stdcolors.Color): chroma.Color =
  var r = color.int shr 16 and 0xff
  var g = color.int shr 8 and 0xff
  var b = color.int and 0xff
  return chroma.color(r.float / 255, g.float / 255, b.float / 255, 1)

method render*(self: GuiRenderer, widget: WWidget, frameIndex: int) =
  if self.framebuffer.width != self.size.x.int32 or self.framebuffer.height != self.size.y.int32:
    self.framebuffer.width = self.size.x.int32
    self.framebuffer.height = self.size.y.int32
    bindTextureData(self.framebuffer, nil)

  # Clear the screen and begin a new frame.
  self.boxy.beginFrame(self.window.size, clearFrame=false)
  # self.boxy2.beginFrame(self.window.size, clearFrame=false)

  # Draw the bg.
  # bxy.drawImage("bg", rect = rect(vec2(0, 0), window.size.vec2))

  if self.redrawEverything:
    widget.renderWidget(self, true, frameIndex)
  else:
    widget.renderWidget(self, false, frameIndex)

  # End this frame, flushing the draw commands.
  glBindFramebuffer(GL_FRAMEBUFFER, self.framebufferId)
  self.boxy.endFrame()
  glBindFramebuffer(GL_READ_FRAMEBUFFER, self.framebufferId)
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
  glBlitFramebuffer(
    0, 0, self.framebuffer.width.GLint, self.framebuffer.height.GLint,
    0, 0, self.window.size.x.GLint, self.window.size.y.GLint,
    GL_COLOR_BUFFER_BIT, GL_NEAREST.GLenum)

  # Swap buffers displaying the new Boxy frame.
  self.window.swapBuffers()
  self.redrawEverything = false

  self.lastSize = self.size

method renderWidget(self: WPanel, renderer: GuiRenderer, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.boxy.drawRect(self.lastBounds, self.backgroundColor.toChromaColor)

  for c in self.children:
    c.renderWidget(renderer, forceRedraw, frameIndex)

method renderWidget(self: WVerticalList, renderer: GuiRenderer, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.boxy.drawRect(self.lastBounds, self.backgroundColor.toChromaColor)

  # debugf"renderVerticalList {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
  # debugf"renderVerticalList {self.lastBounds}, {self.backgroundColor}, {self.foregroundColor}"
  # renderer.boxy.drawRect(self.lastBounds, self.foregroundColor.toChromaColor)
  # if self.drawBorder:
  #   renderer.buffer.drawRect(self.lastBounds.x.int, self.lastBounds.y.int, self.lastBounds.xw.int, self.lastBounds.yh.int)
  # renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.lastBounds}")
  for c in self.children:
    c.renderWidget(renderer, forceRedraw, frameIndex)

method renderWidget(self: WHorizontalList, renderer: GuiRenderer, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.boxy.drawRect(self.lastBounds, self.backgroundColor.toChromaColor)

  # debugf"renderHorizontalList {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
  # debugf"renderHorizontalList {self.lastBounds}, {self.backgroundColor}, {self.foregroundColor}"
  # renderer.boxy.drawRect(self.lastBounds, self.foregroundColor.toChromaColor)
  # if self.drawBorder:
  #   renderer.buffer.drawRect(self.lastBounds.x.int, self.lastBounds.y.int, self.lastBounds.xw.int, self.lastBounds.yh.int)
  # renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.lastBounds}")
  for c in self.children:
    c.renderWidget(renderer, forceRedraw, frameIndex)

method renderWidget(self: WText, renderer: GuiRenderer, forceRedraw: bool, frameIndex: int) =
  if self.lastHierarchyChange < frameIndex and self.lastBoundsChange < frameIndex and not forceRedraw:
    return

  if self.fillBackground:
    # debugf"renderWidget {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
    renderer.boxy.drawRect(self.lastBounds, self.backgroundColor.toChromaColor)

  # debugf"renderText {self.lastBounds}, {self.lastHierarchyChange}, {self.lastBoundsChange}"
  renderer.boxy.drawRect(self.lastBounds, self.foregroundColor.toChromaColor)
  # if self.drawBorder:
  #   renderer.buffer.drawRect(self.lastBounds.x.int, self.lastBounds.y.int, self.lastBounds.xw.int, self.lastBounds.yh.int)
  # renderer.buffer.write(self.lastBounds.x.int, self.lastBounds.y.int, fmt"{self.lastBounds}")

  # if renderer.queryCacheRenderedText.contains(input):
  #   let oldImageId = renderer.queryCacheRenderedText[input]
  #   renderer.boxy.removeImage(oldImageId)

  # let font = renderer.getFont(input.font, input.fontSize)
  # let arrangement = font.typeset(input.text, bounds=input.bounds)
  # var bounds = arrangement.layoutBounds()
  # if bounds.x == 0:
  #   bounds.x = 1
  # if bounds.y == 0:
  #   bounds.y = input.lineHeight
  # bounds.y += textExtraHeight

  # var image = newImage(bounds.x.int, bounds.y.int)
  # image.fillText(arrangement)

  # let imageId = if input.imageId.len > 0: input.imageId else: $newId()
  # renderer.boxy.addImage(imageId, image, false)
  # return imageId


