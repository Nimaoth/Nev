import std/[tables, strutils, options, sets]
import platform, util, platform/filesystem, timer
import custom_logger, input, event, monitors, lrucache, id, rect_utils, theme
import chroma, vmath, windy, boxy, boxy/textures, opengl, pixie/[contexts, fonts]
import ui/node

export platform

type
  GuiPlatform* = ref object of Platform
    window: Window
    ctx*: Context
    boxy: Boxy
    boxy2: Boxy
    currentModifiers: Modifiers
    currentMouseButtons: set[MouseButton]
    eventCounter: int

    fontRegular: string
    fontBold*: string
    fontItalic*: string
    fontBoldItalic*: string

    lastSize: Vec2
    renderedSomethingLastFrame: bool

    lastFontSize: float
    mLineHeight: float
    mLineDistance: float
    mCharWidth: float
    mCharGap: float

    framebufferId: GLuint
    framebuffer: Texture

    typefaces: Table[string, Typeface]

    cachedImages: LruCache[string, string]

    lastEvent: Option[(int64, Modifiers)]

    drawnNodes: seq[UINode]

proc toInput(rune: Rune): int64
proc toInput(button: Button): int64
proc centerWindowOnMonitor(window: Window, monitor: int)
proc getFont*(self: GuiPlatform, font: string, fontSize: float32): Font
proc getFont*(self: GuiPlatform, fontSize: float32, style: set[FontStyle]): Font
proc getFont*(self: GuiPlatform, fontSize: float32, flags: UINodeFlags): Font

method init*(self: GuiPlatform) =
  self.cachedImages = newLruCache[string, string](1000, true)
  self.window = newWindow("Absytree", ivec2(2000, 1000), vsync=false)
  self.window.runeInputEnabled = true
  self.supportsThinCursor = true

  self.builder = newNodeBuilder()
  self.builder.useInvalidation = true

  # self.window.centerWindowOnMonitor(1)
  # self.window.maximized = true
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
  self.ctx.textBaseline = TopBaseline

  self.fontRegular = "fonts/DejaVuSansMono.ttf"
  self.fontBold = "fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "fonts/DejaVuSansMono-BoldOblique.ttf"

  self.boxy.setTargetFramebuffer self.framebufferId

  # This sets the font size of self.ctx and recalculates the char width
  self.fontSize = 20

  self.layoutOptions.getTextBounds = proc(text: string, fontSizeIncreasePercent: float = 0): Vec2 =
    let font = self.getFont(self.ctx.font, self.ctx.fontSize * (1 + fontSizeIncreasePercent))
    if text.len == 0:
      let arrangement = font.typeset(" ")
      result = vec2(0, arrangement.layoutBounds().y)
    else:
      let arrangement = font.typeset(text)
      result = arrangement.layoutBounds()

  self.window.onFocusChange = proc() =
    inc self.eventCounter
    self.currentModifiers = {}
    self.currentMouseButtons = {}

  self.window.onRune = proc(rune: Rune) =
    inc self.eventCounter
    if rune.int32 in char.low.ord .. char.high.ord:
      case rune.char
      of ' ': return
      of 8.char: return # backspace
      of 127.char: return # delete
      else: discard

    # debugf"rune {rune.int} '{rune}' {inputToString(rune.toInput, self.currentModifiers)}"
    if self.lastEvent.isSome:
      self.lastEvent = (int64, Modifiers).none

    self.onRune.invoke (rune.toInput, self.currentModifiers)

  self.window.onScroll = proc() =
    inc self.eventCounter
    if not self.builder.handleMouseScroll(self.window.mousePos.vec2, self.window.scrollDelta, {}):
      self.onScroll.invoke (self.window.mousePos.vec2, self.window.scrollDelta, {})

  self.window.onMouseMove = proc() =
    inc self.eventCounter
    if not self.builder.handleMouseMoved(self.window.mousePos.vec2, self.currentMouseButtons):
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

    # debugf"button {button} {inputToString(button.toInput, self.currentModifiers)}"

    if self.lastEvent.getSome(event):
      if not self.builder.handleKeyPressed(event[0], event[1]):
        self.onKeyPress.invoke event
      self.lastEvent = (int64, Modifiers).none

    case button
    of  MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
      self.currentMouseButtons.incl button.toMouseButton
      if not self.builder.handleMousePressed(button.toMouseButton, self.currentModifiers, self.window.mousePos.vec2):
        self.onMousePress.invoke (button.toMouseButton, self.currentModifiers, self.window.mousePos.vec2)
    of KeyLeftShift, KeyRightShift: self.currentModifiers = self.currentModifiers + {Shift}
    of KeyLeftControl, KeyRightControl: self.currentModifiers = self.currentModifiers + {Control}
    of KeyLeftAlt, KeyRightAlt: self.currentModifiers = self.currentModifiers + {Alt}
    # of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers + {Super}
    else:
      self.lastEvent = (button.toInput, self.currentModifiers).some

  self.window.onButtonRelease = proc(button: Button) =
    inc self.eventCounter

    if self.lastEvent.getSome(event):
      if not self.builder.handleKeyPressed(event[0], event[1]):
        self.onKeyPress.invoke event
      self.lastEvent = (int64, Modifiers).none

    case button
    of  MouseLeft, MouseRight, MouseMiddle, MouseButton4, MouseButton5, DoubleClick, TripleClick, QuadrupleClick:
      self.currentMouseButtons.excl button.toMouseButton
      if not self.builder.handleMouseReleased(button.toMouseButton, self.currentModifiers, self.window.mousePos.vec2):
        self.onMouseRelease.invoke (button.toMouseButton, self.currentModifiers, self.window.mousePos.vec2)
    of KeyLeftShift, KeyRightShift: self.currentModifiers = self.currentModifiers - {Shift}
    of KeyLeftControl, KeyRightControl: self.currentModifiers = self.currentModifiers - {Control}
    of KeyLeftAlt, KeyRightAlt: self.currentModifiers = self.currentModifiers - {Alt}
    # of KeyLeftSuper, KeyRightSuper: currentModifiers = currentModifiers - {Super}
    else:
      if not self.builder.handleKeyPressed(button.toInput, self.currentModifiers):
        self.onKeyRelease.invoke (button.toInput, self.currentModifiers)

method deinit*(self: GuiPlatform) =
  self.window.close()

method requestRender*(self: GuiPlatform, redrawEverything = false) =
  self.requestedRender = true
  self.redrawEverything = self.redrawEverything or redrawEverything

proc getFont*(self: GuiPlatform, font: string, fontSize: float32): Font =
  if font == "":
    raise newException(PixieError, "No font has been set on this Context")

  if font notin self.typefaces:
    self.typefaces[font] = readTypeface(fs.getApplicationFilePath(font))

  result = newFont(self.typefaces.getOrDefault(font, nil))
  result.paint.color = color(1, 1, 1)
  result.size = fontSize

proc getFont*(self: GuiPlatform, fontSize: float32, style: set[FontStyle]): Font =
  if Italic in style and Bold in style:
    return self.getFont(self.fontBoldItalic, fontSize)
  if Italic in style:
    return self.getFont(self.fontItalic, fontSize)
  if Bold in style:
    return self.getFont(self.fontBold, fontSize)
  return self.getFont(self.fontRegular, fontSize)

proc getFont*(self: GuiPlatform, fontSize: float32, flags: UINodeFlags): Font =
  if TextItalic in flags and TextBold in flags:
    return self.getFont(self.fontBoldItalic, fontSize)
  if TextItalic in flags:
    return self.getFont(self.fontItalic, fontSize)
  if TextBold in flags:
    return self.getFont(self.fontBold, fontSize)
  return self.getFont(self.fontRegular, fontSize)


method size*(self: GuiPlatform): Vec2 =
  let size = self.window.size
  return vec2(size.x.float, size.y.float)

method sizeChanged*(self: GuiPlatform): bool =
  let s = self.size
  return s.x != self.lastSize.x or s.y != self.lastSize.y

proc updateCharWidth*(self: GuiPlatform) =
  let font = self.getFont(self.ctx.font, self.ctx.fontSize)
  let bounds = font.typeset(repeat("#", 100)).layoutBounds()
  let boundsSingle = font.typeset("#").layoutBounds()
  self.mCharWidth = bounds.x / 100
  self.mCharGap = (bounds.x / 100) - boundsSingle.x
  self.mLineHeight = bounds.y

  self.builder.charWidth = bounds.x / 100.0
  self.builder.lineHeight = bounds.y - 3
  self.builder.lineGap = 6

method `fontSize=`*(self: GuiPlatform, fontSize: float) =
  self.ctx.fontSize = fontSize
  self.updateCharWidth()

method `lineDistance=`*(self: GuiPlatform, lineDistance: float) = self.mLineDistance = lineDistance
method fontSize*(self: GuiPlatform): float = self.ctx.fontSize
method lineDistance*(self: GuiPlatform): float = self.mLineDistance
method lineHeight*(self: GuiPlatform): float = self.mLineHeight
method charWidth*(self: GuiPlatform): float = self.mCharWidth
method charGap*(self: GuiPlatform): float = self.mCharGap

method measureText*(self: GuiPlatform, text: string): Vec2 = self.getFont(self.ctx.font, self.ctx.fontSize).typeset(text).layoutBounds()

method processEvents*(self: GuiPlatform): int =
  self.eventCounter = 0
  pollEvents()

  if self.lastEvent.getSome(event):
    if not self.builder.handleKeyPressed(event[0], event[1]):
      self.onKeyPress.invoke event
    self.lastEvent = (int64, Modifiers).none

  if self.window.closeRequested:
    inc self.eventCounter
    self.onCloseRequested.invoke()

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

proc drawNode(builder: UINodeBuilder, platform: GuiPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false)

proc strokeRect*(boxy: Boxy, rect: Rect, color: Color, thickness: float = 1, offset: float = 0) =
  let rect = rect.grow(vec2(thickness * offset, thickness * offset))
  boxy.drawRect(rect.splitV(thickness.relative)[0].shrink(vec2(0, thickness)), color)
  boxy.drawRect(rect.splitVInv(thickness.relative)[1].shrink(vec2(0, thickness)), color)
  boxy.drawRect(rect.splitH(thickness.relative)[0], color)
  boxy.drawRect(rect.splitHInv(thickness.relative)[1], color)

proc randomColor(node: UINode, a: float32): Color =
  let h = node.id.hash
  result.r = (((h shr 0) and 0xff).float32 / 255.0).sqrt
  result.g = (((h shr 8) and 0xff).float32 / 255.0).sqrt
  result.b = (((h shr 16) and 0xff).float32 / 255.0).sqrt
  result.a = a

method render*(self: GuiPlatform) =
  if self.framebuffer.width != self.size.x.int32 or self.framebuffer.height != self.size.y.int32:
    self.framebuffer.width = self.size.x.int32
    self.framebuffer.height = self.size.y.int32
    bindTextureData(self.framebuffer, nil)
    self.redrawEverything = true

  # Clear the screen and begin a new frame.
  self.boxy.beginFrame(self.window.size, clearFrame=false)

  for image in self.cachedImages.removedKeys:
    self.boxy.removeImage(image)
  self.cachedImages.clearRemovedKeys()

  if self.ctx.fontSize != self.lastFontSize:
    self.lastFontSize = self.ctx.fontSize
    for kv in self.cachedImages.pairs:
      self.boxy.removeImage(kv[0])
    self.cachedImages.clear()

  if self.builder.root.lastSizeChange == self.builder.frameIndex:
    self.redrawEverything = true

  self.drawnNodes.setLen 0

  var renderedSomething = true
  self.builder.drawNode(self, self.builder.root, force = self.redrawEverything)

  if self.showDrawnNodes and renderedSomething:
    let size = if self.showDrawnNodes: self.size * vec2(0.5, 1) else: self.size

    self.boxy.pushLayer()
    defer:
      self.boxy.pushLayer()
      self.boxy.drawRect(rect(size.x, 0, size.x, size.y), color(1, 0, 0, 1))
      self.boxy.popLayer(blendMode = MaskBlend)
      self.boxy.popLayer()

    self.boxy.drawRect(rect(size.x, 0, size.x, size.y), color(0, 0, 0))

    for node in self.drawnNodes:
      let c = node.randomColor(0.3)
      self.boxy.drawRect(rect(node.lx + size.x, node.ly, node.lw, node.lh), c)

      if DrawBorder in node.flags:
        self.boxy.strokeRect(rect(node.lx + size.x, node.ly, node.lw, node.lh), color(c.r, c.g, c.b, 0.5), 5, offset = 0.5)

  # End this frame, flushing the draw commands. Draw to framebuffer.
  self.boxy.endFrame()

  if renderedSomething:
    glBindFramebuffer(GL_READ_FRAMEBUFFER, self.framebufferId)
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
    glBlitFramebuffer(
      0, 0, self.framebuffer.width.GLint, self.framebuffer.height.GLint,
      0, 0, self.window.size.x.GLint, self.window.size.y.GLint,
      GL_COLOR_BUFFER_BIT, GL_NEAREST.GLenum)

    self.window.swapBuffers()

  self.renderedSomethingLastFrame = renderedSomething;
  self.redrawEverything = false
  self.lastSize = self.size

proc drawNode(builder: UINodeBuilder, platform: GuiPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) =
  var nodePos = offset
  nodePos.x += node.boundsActual.x
  nodePos.y += node.boundsActual.y

  var force = force

  if builder.useInvalidation and not force and node.lastChange < builder.frameIndex:
    return

  node.lastRenderTime = builder.frameIndex

  if node.flags.any &{UINodeFlag.FillBackground, DrawBorder, DrawText}:
    platform.drawnNodes.add node

  if node.flags.any &{UINodeFlag.FillBackground, DrawText}:
    force = true

  node.lx = nodePos.x
  node.ly = nodePos.y
  node.lw = node.boundsActual.w
  node.lh = node.boundsActual.h
  let bounds = rect(nodePos.x, nodePos.y, node.boundsActual.w, node.boundsActual.h)

  if FillBackground in node.flags:
    platform.boxy.drawRect(bounds, node.backgroundColor)

  # Mask the rest of the rendering is this function to the contentBounds
  if MaskContent in node.flags:
    platform.boxy.pushLayer()
  defer:
    if MaskContent in node.flags:
      platform.boxy.pushLayer()
      platform.boxy.drawRect(bounds, color(1, 0, 0, 1))
      platform.boxy.popLayer(blendMode = MaskBlend)
      platform.boxy.popLayer()

  if DrawText in node.flags:
    let key = node.text
    var imageId: string
    if platform.cachedImages.contains(key):
      imageId = platform.cachedImages[key]
    else:
      imageId = $newId()
      platform.cachedImages[key] = imageId

      # todo: font size scaling
      # let font = renderer.getFont(renderer.ctx.fontSize * (1 + self.fontSizeIncreasePercent), self.style.fontStyle)
      let font = platform.getFont(platform.ctx.fontSize, node.flags)

      let wrap = TextWrap in node.flags
      let wrapBounds = if wrap: vec2(node.boundsActual.w, node.boundsActual.h) else: vec2(0, 0)
      let arrangement = font.typeset(node.text, bounds=wrapBounds)
      var bounds = arrangement.layoutBounds()
      if bounds.x == 0:
        bounds.x = 1
      if bounds.y == 0:
        bounds.y = builder.textHeight

      var image = newImage(bounds.x.int, bounds.y.int)
      image.fillText(arrangement)
      platform.boxy.addImage(imageId, image, false)

    let pos = vec2(nodePos.x.floor, nodePos.y.floor)
    platform.boxy.drawImage(imageId, pos, node.textColor)

  for _, c in node.children:
    builder.drawNode(platform, c, nodePos, force)

  if DrawBorder in node.flags:
    platform.boxy.strokeRect(bounds, node.borderColor)
