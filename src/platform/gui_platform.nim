import std/[tables, strutils, options, sets, os, strformat, sugar, locks]
import chroma, vmath, windy, boxy, boxy/textures, opengl, pixie/[contexts, fonts]
import misc/[custom_logger, util, event, id, rect_utils, custom_async, timer, generational_seq]
import ui/node
import platform
import input, monitors, lrucache, theme, compilation_config, vfs, app_options

export platform

{.push raises: [].}
{.push gcsafe.}

logCategory "gui-platform"

const logDeletedImageCount = false

type
  GuiPlatform* = ref object of Platform
    window: Window
    ctx*: Context
    boxy: Boxy
    currentModifiers: Modifiers
    currentMouseButtons: set[MouseButton]

    fontRegular: string
    fontBold*: string
    fontItalic*: string
    fontBoldItalic*: string

    fallbackFonts*: seq[string]

    lastSize: Vec2
    renderedSomethingLastFrame: bool

    lastFontSize: float
    mLineHeight: float
    mLineDistance: float = 1
    mCharWidth: float
    mCharGap: float

    framebufferId: GLuint
    framebuffer: Texture

    textures: Table[string, Texture]

    typefaces: Table[string, Typeface]
    glyphCache: LruCache[(Rune, UINodeFlags), string]
    asciiGlyphCache: array[128, string]

    lastEvent: Option[(int64, Modifiers, Button)]

    drawnNodes: seq[UINode]

    vsync: bool

proc toInput(rune: Rune): int64
proc toInput(button: Button): int64
proc centerWindowOnMonitor*(window: Window, monitor: int)
proc getFont*(self: GuiPlatform, font: string, fontSize: float32): Font
proc getFont*(self: GuiPlatform, fontSize: float32, style: set[FontStyle]): Font
proc getFont*(self: GuiPlatform, fontSize: float32, flags: UINodeFlags): Font

method moveToMonitor*(self: GuiPlatform, index: int) {.gcsafe, raises: [].} =
  centerWindowOnMonitor(self.window, index)

method getStatisticsString*(self: GuiPlatform): string =
  result.add &"Typefaces: {self.typefaces.len}\n"
  result.add &"Glyph Cache: {self.glyphCache.len}\n"
  result.add &"Drawn Nodes: {self.drawnNodes.len}\n"

{.pop.} # gcsafe


var gTextures: GenerationalSeq[Texture, TextureId]
reserveTextureImpl = proc(): TextureId {.gcsafe, raises: [].} =
  {.gcsafe.}:
    return gTextures.add(nil)

method init*(self: GuiPlatform, options: AppOptions) =
  try:
    self.glyphCache = newLruCache[(Rune, UINodeFlags), string](5000, true)
    self.window = newWindow(appName.capitalizeAscii, ivec2(2000, 1000), vsync=true)
    self.window.runeInputEnabled = true
    self.supportsThinCursor = true
    self.focused = self.window.focused
    self.vsync = true

    try:
      let icon = readImage("res/icon.png")
      self.window.icon = icon
    except:
      discard

    # Use virtual key codes so that we can take into account the keyboard language
    # and the behaviour is more consistent with the browser/terminal.
    # todo: is this necessary on linux?
    when defined(windows):
      log lvlInfo, "Using virtual key codes instead of scan codes"
      self.window.useVirtualKeyCodes = true

    self.builder = newNodeBuilder()
    self.builder.useInvalidation = true

    if options.monitor.getSome(index):
      when defined(windows):
        self.window.centerWindowOnMonitor(index)
      else:
        log lvlWarn, &"Opening window on specific monitor not implemented on this platform yet."

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
    self.ctx = newContext(1, 1)
    self.ctx.fillStyle = rgb(255, 255, 255)
    self.ctx.strokeStyle = rgb(255, 255, 255)
    self.ctx.font = "app://fonts/DejaVuSansMono.ttf"
    self.ctx.textBaseline = TopBaseline

    self.fontRegular = "app://fonts/DejaVuSansMono.ttf"
    self.fontBold = "app://fonts/DejaVuSansMono-Bold.ttf"
    self.fontItalic = "app://fonts/DejaVuSansMono-Oblique.ttf"
    self.fontBoldItalic = "app://fonts/DejaVuSansMono-BoldOblique.ttf"

    self.fallbackFonts.add "app://fonts/Noto_Sans_Symbols_2/NotoSansSymbols2-Regular.ttf"
    self.fallbackFonts.add "app://fonts/NotoEmoji/NotoEmoji.otf"

    self.boxy.setTargetFramebuffer self.framebufferId

    # This sets the font size of self.ctx and recalculates the char width
    self.fontSize = 16

    self.layoutOptions.getTextBounds = proc(text: string, fontSizeIncreasePercent: float = 0): Vec2 =
      let font = self.getFont(self.ctx.font, self.ctx.fontSize * (1 + fontSizeIncreasePercent))
      if text.len == 0:
        let arrangement = font.typeset(" ")
        result = vec2(0, arrangement.layoutBounds().y)
      else:
        let arrangement = font.typeset(text, snapToPixel = false)
        result = arrangement.layoutBounds()

    self.builder.textWidthImpl = proc(node: UINode): float32 =
      let font = self.getFont(self.ctx.fontSize, node.flags)
      let arrangement = font.typeset(node.text, snapToPixel = false)
      result = arrangement.layoutBounds().x

    self.builder.textWidthStringImpl = proc(text: string): float32 =
      let font = self.getFont(self.ctx.fontSize, 0.UINodeFlags)
      let arrangement = font.typeset(text, snapToPixel = false)
      result = arrangement.layoutBounds().x

    self.builder.textBoundsImpl = proc(node: UINode): Vec2 =
      let font = self.getFont(self.ctx.fontSize, node.flags)
      let arrangement = font.typeset(node.text, bounds = node.bounds.wh, wrap = TextWrap in node.flags, snapToPixel = false)
      result = arrangement.layoutBounds()

    self.window.onFocusChange = proc() =
      inc self.eventCounter
      self.currentModifiers = {}
      self.currentMouseButtons = {}
      self.lastEvent = (int64, Modifiers, Button).none
      self.onFocusChanged.invoke self.window.focused
      self.focused = self.window.focused

    self.window.onRune = proc(rune: Rune) =
      inc self.eventCounter
      if rune.int32 in char.low.ord .. char.high.ord:
        case rune.char
        of ' ': return
        of 8.char: return # backspace
        of 9.char: return # tab
        of 13.char: return # enter
        of 127.char: return # delete
        else: discard

      # debugf"rune {rune.int} '{rune}' {inputToString(rune.toInput, self.currentModifiers)}"
      if self.lastEvent.isSome:
        self.lastEvent = (int64, Modifiers, Button).none

      self.onRune.invoke (rune.toInput, self.currentModifiers)

    self.window.onScroll = proc() =
      inc self.eventCounter
      if not self.builder.handleMouseScroll(self.window.mousePos.vec2, self.window.scrollDelta, self.currentModifiers):
        self.onScroll.invoke (self.window.mousePos.vec2, self.window.scrollDelta, self.currentModifiers)

    self.window.onMouseMove = proc() =
      # inc self.eventCounter
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

      if self.lastEvent.getSome(event):
        # debugf"button last event k: {event[2]}, input: {inputToString(event[0], event[1])}"
        if not self.builder.handleKeyPressed(event[0], event[1]):
          self.onKeyPress.invoke (event[0], event[1])
        self.lastEvent = (int64, Modifiers, Button).none

      # debugf"button k: {button}, input: {inputToString(button.toInput, self.currentModifiers)}"

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
        # debugf"last event k: {button}, input: {inputToString(button.toInput, self.currentModifiers)}"
        self.lastEvent = (button.toInput, self.currentModifiers, button).some

    self.window.onButtonRelease = proc(button: Button) =
      inc self.eventCounter

      if self.lastEvent.getSome(event):
        # debugf"button release last event k: {event[2]}, input: {inputToString(event[0], event[1])}"
        if not self.builder.handleKeyPressed(event[0], event[1]):
          self.onKeyPress.invoke (event[0], event[1])
        self.lastEvent = (int64, Modifiers, Button).none

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
        if not self.builder.handleKeyReleased(button.toInput, self.currentModifiers):
          self.onKeyRelease.invoke (button.toInput, self.currentModifiers)
  except:
    log lvlError, &"Failed to create gui platform: {getCurrentExceptionMsg()}"
    quit(0)

method deinit*(self: GuiPlatform) =
  self.window.close()

{.push gcsafe.}

method requestRender*(self: GuiPlatform, redrawEverything = false) =
  self.requestedRender = true
  self.redrawEverything = self.redrawEverything or redrawEverything

proc readTypeface(vfs: VFS, filePath: string): Typeface {.raises: [IOError].} =
  try:
    result =
      case splitFile(filePath).ext.toLowerAscii():
        of ".ttf":
          parseTtf(vfs.read(filePath, {Binary}).waitFor)
        of ".otf":
          parseOtf(vfs.read(filePath, {Binary}).waitFor)
        of ".svg":
          parseSvgFont(vfs.read(filePath, {Binary}).waitFor)
        else:
          raise newException(IOError, "Unsupported font format")
  except Exception as e:
    raise newException(IOError, &"Failed to load typeface '{filePath}': " & e.msg, e)

  result.filePath = filePath

proc getTypeface*(self: GuiPlatform, font: string): Typeface =
  if font notin self.typefaces:
    var typeface: Typeface = nil
    try:
      log lvlInfo, &"Reading font '{font}'"
      typeface = self.vfs.readTypeface(font)
      self.typefaces[font] = typeface

      for fallbackFont in self.fallbackFonts:
        try:
          log lvlInfo, &"Reading fallback font '{fallbackFont}'"
          let fallback = self.vfs.readTypeface(fallbackFont)
          if fallback.isNotNil:
            typeface.fallbacks.add fallback
        except IOError as e:
          log lvlError, &"Failed to load fallback font '{fallbackFont}': {e.msg}"

    except IOError as e:
      log lvlError, &"Failed to load typeface '{font}': {e.msg}"
      return nil

  result = self.typefaces[font]

proc getFont*(self: GuiPlatform, font: string, fontSize: float32): Font =
  assert font != ""

  let typeface = self.getTypeface(font)
  result = newFont(typeface)
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

proc getTypeface*(self: GuiPlatform, flags: UINodeFlags): Typeface =
  if TextItalic in flags and TextBold in flags:
    return self.getTypeface(self.fontBoldItalic)
  if TextItalic in flags:
    return self.getTypeface(self.fontItalic)
  if TextBold in flags:
    return self.getTypeface(self.fontBold)
  return self.getTypeface(self.fontRegular)

method getFontInfo*(self: GuiPlatform, fontSize: float, flags: UINodeFlags): FontInfo {.gcsafe, raises: [].} =
  let typeface = self.getTypeface(flags)
  let fontScale = fontSize / typeface.scale
  let lineHeight = round((typeface.ascent - typeface.descent + typeface.lineGap) * fontScale)

  # todo
  # proc kerningAdjustment(left, right: Rune): float =
  #   return typeface.getKerningAdjustment(left, right)

  proc advance (rune: Rune): float =
    typeface.getAdvance(rune)

  FontInfo(
    ascent: typeface.ascent,
    lineHeight: lineHeight,
    lineGap: typeface.lineGap,
    scale: fontScale,
    # kerningAdjustment: kerningAdjustment,
    advance: advance,
  )

method size*(self: GuiPlatform): Vec2 =
  try:
    let size = self.window.size
    return vec2(size.x.float, size.y.float)
  except:
    return vec2(1, 1)

method sizeChanged*(self: GuiPlatform): bool =
  let s = self.size
  return s.x != self.lastSize.x or s.y != self.lastSize.y

proc updateCharWidth*(self: GuiPlatform) =
  let font = self.getFont(self.ctx.font, self.ctx.fontSize)
  let bounds = font.typeset(repeat("#_", 50), snapToPixel = false).layoutBounds()
  let boundsSingle = font.typeset("#_", snapToPixel = false).layoutBounds()
  self.mCharWidth = bounds.x / 100
  self.mCharGap = (bounds.x / 100) - boundsSingle.x / 2
  self.mLineHeight = bounds.y

  self.builder.charWidth = self.mCharWidth
  self.builder.lineHeight = self.mLineHeight
  self.builder.lineGap = self.mLineDistance

method setFont*(self: GuiPlatform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) =
  log lvlInfo, fmt"Update font: {fontRegular}, {fontBold}, {fontItalic}, {fontBoldItalic}, fallbacks: {fallbackFonts}"
  self.ctx.font = fontRegular
  self.fontRegular = fontRegular
  self.fontBold = fontBold
  self.fontItalic = fontItalic
  self.fontBoldItalic = fontBoldItalic
  self.fallbackFonts = fallbackFonts
  self.typefaces.clear()
  self.updateCharWidth()

  try:
    for image in self.glyphCache.removedKeys:
      self.boxy.removeImage($image)

    for (_, image) in self.glyphCache.pairs:
      self.boxy.removeImage(image)

    for image in self.asciiGlyphCache.mitems:
      if image.len > 0:
        self.boxy.removeImage(image)
      image.setLen(0)
  except:
    discard

  self.glyphCache.clearRemovedKeys()
  self.glyphCache.clear()

method `fontSize=`*(self: GuiPlatform, fontSize: float) =
  self.ctx.fontSize = fontSize
  self.updateCharWidth()

method `lineDistance=`*(self: GuiPlatform, lineDistance: float) =
  self.mLineDistance = lineDistance
  self.updateCharWidth()

method fontSize*(self: GuiPlatform): float = self.ctx.fontSize
method lineDistance*(self: GuiPlatform): float = self.mLineDistance
method lineHeight*(self: GuiPlatform): float = self.mLineHeight
method charWidth*(self: GuiPlatform): float = self.mCharWidth
method charGap*(self: GuiPlatform): float = self.mCharGap

method measureText*(self: GuiPlatform, text: string): Vec2 = self.getFont(self.ctx.font, self.ctx.fontSize).typeset(text, snapToPixel = false).layoutBounds()
method layoutText*(self: GuiPlatform, text: string): seq[Rect] = self.getFont(self.ctx.font, self.ctx.fontSize).typeset(text).selectionRects

method setVsync*(self: GuiPlatform, enabled: bool) {.gcsafe, raises: [].} =
  try:
    self.vsync = enabled
    {.gcsafe.}:
      self.window.vsync = enabled
  except WindyError as e:
    log lvlError, &"Failed to change vsync to {enabled}: {e.msg}"

method processEvents*(self: GuiPlatform): int =
  self.eventCounter = 0
  try:
    {.gcsafe.}:
      pollEvents()
  except:
    discard

  if self.lastEvent.getSome(event):
    # debugf"process last event k: {event[2]}, input: {inputToString(event[0], event[1])}"
    if not self.builder.handleKeyPressed(event[0], event[1]):
      self.onKeyPress.invoke (event[0], event[1])
    self.lastEvent = (int64, Modifiers, Button).none

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

proc centerWindowOnMonitor*(window: Window, monitor: int) =
  let monitorPos = getMonitorRect(monitor)

  let left = float(monitorPos.left)
  let right = float(monitorPos.right)
  let top = float(monitorPos.top)
  let bottom = float(monitorPos.bottom)

  let windowWidth = float(window.size.x)
  let windowHeight = float(window.size.y)
  let monitorWidth = right - left
  let monitorHeight = bottom - top
  {.gcsafe.}:
    window.pos = ivec2(int32(left + (monitorWidth - windowWidth) / 2),
                       int32(top + (monitorHeight - windowHeight) / 2))

proc drawNode(builder: UINodeBuilder, platform: GuiPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false)

proc strokeRect*(boxy: Boxy, rect: Rect, color: Color, thickness: float = 1, offset: float = 0) =
  try:
    let rect = rect.grow(vec2(thickness * offset, thickness * offset))
    boxy.drawRect(rect.splitV(thickness.relative)[0].shrink(vec2(0, thickness)), color)
    boxy.drawRect(rect.splitVInv(thickness.relative)[1].shrink(vec2(0, thickness)), color)
    boxy.drawRect(rect.splitH(thickness.relative)[0], color)
    boxy.drawRect(rect.splitHInv(thickness.relative)[1], color)
  except GLerror, Exception:
    discard

proc randomColor(node: UINode, a: float32): Color =
  let h = node.id.hash
  result.r = (((h shr 0) and 0xff).float32 / 255.0).sqrt
  result.g = (((h shr 8) and 0xff).float32 / 255.0).sqrt
  result.b = (((h shr 16) and 0xff).float32 / 255.0).sqrt
  result.a = a

proc toRgbaFast(c: colortypes.Color): ColorRGBA {.inline.} =
  ## Convert Color to ColorRGBA
  result.r = (c.r * 255 + 0.5).uint8
  result.g = (c.g * 255 + 0.5).uint8
  result.b = (c.b * 255 + 0.5).uint8
  result.a = (c.a * 255 + 0.5).uint8

proc updateTextures(self: GuiPlatform) =
  var texturesToUpload = takeTexturesToUpload()
  var texturesToDelete = takeTexturesToDelete()

  withLock(texturesLock):
    let textures = ({.gcsafe.}: gTextures.addr)
    for tex in texturesToUpload:
      try:
        if tex.id in textures[]:
          let image = newImage(tex.width, tex.height)
          for y in 0..<tex.height:
            for x in 0..<tex.width:
              image.data[x + y * tex.width] = tex.data[x + y * tex.width].toRgbaFast()
          let texture = newTexture(image)
          textures[].set(tex.id, texture)
      except CatchableError as e:
        log lvlError, &"Failed to create texture: {e.msg}"
      except GLerror as e:
        log lvlError, &"Failed to create texture: {e.msg}"
    for texId in texturesToDelete:
      try:
        if textures[].tryGet(texId).getSome(texture):
          if texture.textureId != 0:
            glDeleteTextures(1, texture.textureId.addr)
          textures[].del(texId)
      except CatchableError as e:
        log lvlError, &"Failed to create texture: {e.msg}"
      except GLerror as e:
        log lvlError, &"Failed to create texture: {e.msg}"

    if texturesToDelete.len > 30:
      echo &"{textures[].len} active ----------------"

method render*(self: GuiPlatform, rerender: bool) =
  try:
    self.updateTextures()

    if rerender:
      if self.framebuffer.width != self.size.x.int32 or self.framebuffer.height != self.size.y.int32:
        self.framebuffer.width = self.size.x.int32
        self.framebuffer.height = self.size.y.int32
        bindTextureData(self.framebuffer, nil)
        self.redrawEverything = true

      # Clear the screen and begin a new frame.
      self.boxy.beginFrame(self.window.size, clearFrame=false)

      var count = 0
      for image in self.glyphCache.removedKeys:
        self.boxy.removeImage($image)
        inc count

      if logDeletedImageCount and count > 0:
        log lvlInfo, fmt"Cleared {count} images from cache"

      self.glyphCache.clearRemovedKeys()

      if self.ctx.fontSize != self.lastFontSize:
        self.lastFontSize = self.ctx.fontSize
        for (_, image) in self.glyphCache.pairs:
          self.boxy.removeImage(image)
        self.glyphCache.clear()
        for image in self.asciiGlyphCache.mitems:
          if image.len > 0:
            self.boxy.removeImage(image)
          image.setLen(0)

      if self.builder.root.lastSizeChange == self.builder.frameIndex:
        self.redrawEverything = true

      self.drawnNodes.setLen 0
      defer:
        self.drawnNodes.setLen 0

      withLock(texturesLock):
        self.builder.drawNode(self, self.builder.root, force = self.redrawEverything)

      if self.showDrawnNodes:
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

      self.redrawEverything = false
      self.lastSize = self.size

    if rerender or self.renderedSomethingLastFrame:
      glBindFramebuffer(GL_READ_FRAMEBUFFER, self.framebufferId)
      glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
      glBlitFramebuffer(
        0, 0, self.framebuffer.width.GLint, self.framebuffer.height.GLint,
        0, 0, self.window.size.x.GLint, self.window.size.y.GLint,
        GL_COLOR_BUFFER_BIT, GL_NEAREST.GLenum)

    if rerender or self.renderedSomethingLastFrame or self.vsync:
      self.window.swapBuffers()

    self.renderedSomethingLastFrame = rerender
  except:
    discard

var solidPaint = newPaint(SolidPaint)
proc drawText(platform: GuiPlatform, text: string, pos: Vec2, bounds: Rect, color: Color, spaceColor: Color, flags: UINodeFlags, underlineColor: Color = color(1, 1, 1), spaceRune: Rune = ' '.Rune) =
  let wrap = TextWrap in flags
  let wrapBounds = if flags.any(&{TextWrap, TextAlignHorizontalLeft, TextAlignHorizontalCenter, TextAlignHorizontalRight, TextAlignVerticalTop, TextAlignVerticalCenter, TextAlignVerticalBottom}):
    vec2(bounds.w, bounds.h)
  else:
    vec2(0, 0)

  let hAlign = if TextAlignHorizontalLeft in flags:
    HorizontalAlignment.LeftAlign
  elif TextAlignHorizontalCenter in flags:
    HorizontalAlignment.CenterAlign
  elif TextAlignHorizontalRight in flags:
    HorizontalAlignment.RightAlign
  else:
    HorizontalAlignment.LeftAlign

  let vAlign = if TextAlignVerticalTop in flags:
    VerticalAlignment.TopAlign
  elif TextAlignVerticalCenter in flags:
    VerticalAlignment.MiddleAlign
  elif TextAlignVerticalBottom in flags:
    VerticalAlignment.BottomAlign
  else:
    VerticalAlignment.TopAlign

  let textFlags = flags * &{TextItalic, TextBold}

  proc tintRune(r: Rune): bool =
    return true

  # todo: convert typeset to not use strings to avoid copying
  try:
    let font = platform.getFont(platform.ctx.fontSize, flags)

    let arrangement = font.typeset(text, bounds=wrapBounds, hAlign=hAlign, vAlign=vAlign, wrap=wrap, snapToPixel = false)
    template drawRune(i: int, rune: Rune, inColor: Color): untyped =
      let color = if tintRune(rune):
        inColor
      else:
        color(1, 1, 1)

      if rune.int < platform.asciiGlyphCache.len and textFlags == 0.UINodeFlags:
        if platform.asciiGlyphCache[rune.int].len == 0:
          var path = font.typeface.getGlyphPath(rune)
          let rect = arrangement.selectionRects[i]
          path.transform(translate(arrangement.positions[i] - rect.xy) * scale(vec2(font.scale)))
          var image = newImage(rect.w.ceil.int, rect.h.ceil.int)
          for paint in font.paints:
            image.fillPath(path, paint)
          platform.boxy.addImage($rune, image, genMipmaps=false)
          platform.asciiGlyphCache[rune.int] = $rune

        let pos = (vec2(pos.x, pos.y) + arrangement.selectionRects[i].xy).round
        platform.boxy.drawImage(platform.asciiGlyphCache[rune.int], pos, color)

      else:
        let key = (rune, textFlags)
        if not platform.glyphCache.contains(key):
          var path = font.typeface.getGlyphPath(rune)
          let rect = arrangement.selectionRects[i]
          path.transform(translate(arrangement.positions[i] - rect.xy) * scale(vec2(font.scale)))
          var image = newImage(rect.w.ceil.int, rect.h.ceil.int)
          for paint in font.paints:
            image.fillPath(path, paint)
          platform.boxy.addImage($key, image, genMipmaps=false)
          platform.glyphCache[key] = $key

        let pos = (vec2(pos.x, pos.y) + arrangement.selectionRects[i].xy).round
        platform.boxy.drawImage($key, pos, color)

    if TextDrawSpaces in flags:
      for i, rune in arrangement.runes:
        let (rune, color) = if rune == ' '.Rune: (spaceRune, spaceColor) else: (rune, color)
        drawRune(i, rune, color)
    else:
      for i, rune in arrangement.runes:
        drawRune(i, rune, color)

    if TextUndercurl in flags:
      platform.boxy.drawRect(rect(pos.x, pos.y + bounds.h - 2, bounds.w, 2), underlineColor)

  except GLerror, Exception:
    discard

proc drawText(platform: GuiPlatform, text: string, arrangement: render_command.Arrangement, indices: RenderCommandArrangement, pos: Vec2, bounds: Rect, color: Color, spaceColor: Color, flags: UINodeFlags, underlineColor: Color = color(1, 1, 1), spaceRune: Rune = ' '.Rune) =
  let wrap = TextWrap in flags
  let wrapBounds = if flags.any(&{TextWrap, TextAlignHorizontalLeft, TextAlignHorizontalCenter, TextAlignHorizontalRight, TextAlignVerticalTop, TextAlignVerticalCenter, TextAlignVerticalBottom}):
    vec2(bounds.w, bounds.h)
  else:
    vec2(0, 0)

  let hAlign = if TextAlignHorizontalLeft in flags:
    HorizontalAlignment.LeftAlign
  elif TextAlignHorizontalCenter in flags:
    HorizontalAlignment.CenterAlign
  elif TextAlignHorizontalRight in flags:
    HorizontalAlignment.RightAlign
  else:
    HorizontalAlignment.LeftAlign

  let vAlign = if TextAlignVerticalTop in flags:
    VerticalAlignment.TopAlign
  elif TextAlignVerticalCenter in flags:
    VerticalAlignment.MiddleAlign
  elif TextAlignVerticalBottom in flags:
    VerticalAlignment.BottomAlign
  else:
    VerticalAlignment.TopAlign

  let textFlags = flags * &{TextItalic, TextBold}

  proc tintRune(r: Rune): bool =
    return true

  # todo: convert typeset to not use strings to avoid copying
  try:
    let font = platform.getFont(platform.ctx.fontSize, flags)
    let typeface = platform.getTypeface(flags)
    let fontScale = platform.ctx.fontSize / typeface.scale
    let solidPaint = ({.cast(gcsafe).}: solidPaint)
    solidPaint.color = color(1, 1, 1)
    template drawRune(i: int, rune: Rune, inColor: Color): untyped =
      let color = if tintRune(rune):
        inColor
      else:
        color(1, 1, 1)
      let key = (rune, textFlags)
      if not platform.glyphCache.contains(key):
        var path = typeface.getGlyphPath(rune)
        let rect = arrangement.selectionRects[i]
        path.transform(translate(arrangement.positions[i] - rect.xy) * scale(vec2(fontScale)))
        var image = newImage(rect.w.ceil.int, rect.h.ceil.int)
        image.fillPath(path, solidPaint)
        platform.boxy.addImage($key, image, genMipmaps=false)
        platform.glyphCache[key] = $key

      let pos = (vec2(pos.x, pos.y) + arrangement.selectionRects[i].xy).round
      platform.boxy.drawImage($key, pos, color)

    if TextDrawSpaces in flags:
      for i in indices.runes:
        let rune = arrangement.runes[i]
        let (rune2, color) = if rune == ' '.Rune: (spaceRune, spaceColor) else: (rune, color)
        drawRune(i, rune2, color)
    else:
      for i in indices.runes:
        let rune = arrangement.runes[i]
        drawRune(i, rune, color)

    if TextUndercurl in flags:
      platform.boxy.drawRect(rect(pos.x, pos.y + bounds.h - 2, bounds.w, 2), underlineColor)

  except GLerror, Exception:
    discard

proc handleRenderCommand(platform: GuiPlatform, renderCommands: ptr RenderCommands, command: RenderCommand, nodePos: Vec2, spaceColor: Color, space: Rune, maskBounds: var seq[Rect]) {.inline, raises: [Exception].} =
  case command.kind
  of RenderCommandKind.Rect:
    platform.boxy.strokeRect(command.bounds + nodePos, command.color)
  of RenderCommandKind.Image:
    {.gcsafe.}:
      if gTextures.tryGet(command.textureId).getSome(tex):
        if tex != nil:
          let glTexId = tex.textureId
          platform.boxy.drawUvRect(nodePos + command.bounds.xy, nodePos + command.bounds.xy + command.bounds.wh, command.uv0, command.uv1, command.color, glTexId)

  of RenderCommandKind.FilledRect:
    platform.boxy.drawRect(command.bounds + nodePos, command.color)
  of RenderCommandKind.TextRaw:
    # todo: don't copy string data
    var text = newStringOfCap(command.len)
    text.setLen(command.len)
    copyMem(text[0].addr, command.data, command.len)
    platform.drawText(text, command.bounds.xy + nodePos, command.bounds + nodePos, command.color, spaceColor, command.flags, command.underlineColor, space)

  of RenderCommandKind.Text:
    # todo: don't copy string data
    assert renderCommands != nil
    let text = renderCommands.strings[command.textOffset..<command.textOffset + command.textLen]
    if command.arrangementIndex == uint32.high:
      platform.drawText(text, command.bounds.xy + nodePos, command.bounds + nodePos, command.color, spaceColor, command.flags, command.underlineColor, space)
    else:
      platform.drawText(text, renderCommands.arrangement, renderCommands.arrangements[command.arrangementIndex], command.bounds.xy + nodePos, command.bounds + nodePos, command.color, spaceColor, command.flags, command.underlineColor, space)
  of RenderCommandKind.ScissorStart:
    platform.boxy.pushLayer()
    maskBounds.add(command.bounds + nodePos)
  of RenderCommandKind.ScissorEnd:
    if maskBounds.len == 0:
      # log lvlError, &"Unbalanced ScisscorStart/End pairs"
      return
    let bounds = maskBounds.pop()
    platform.boxy.pushLayer()
    platform.boxy.drawRect(bounds, color(1, 0, 0, 1))
    platform.boxy.popLayer(blendMode = MaskBlend)
    platform.boxy.popLayer()

proc drawNode(builder: UINodeBuilder, platform: GuiPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) =
  try:
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
      platform.drawText(node.text, nodePos, node.boundsRaw, node.textColor, node.textColor, node.flags, node.underlineColor)

    for _, c in node.children:
      builder.drawNode(platform, c, nodePos, force)

    if DrawBorder in node.flags:
      platform.boxy.strokeRect(bounds, node.borderColor)

    var maskBounds: seq[Rect]
    for list in node.renderCommandList:
      for command in list.commands:
        handleRenderCommand(platform, list[].addr, command, nodePos, list.spacesColor, list.space, maskBounds)
      for command in list[].decodeRenderCommands:
        handleRenderCommand(platform, list[].addr, command, nodePos, node.textColor, list.space, maskBounds)
    for command in node.renderCommands.commands:
      handleRenderCommand(platform, node.renderCommands.addr, command, nodePos, node.renderCommands.spacesColor, node.renderCommands.space, maskBounds)
    for command in node.renderCommands.decodeRenderCommands:
      handleRenderCommand(platform, node.renderCommands.addr, command, nodePos, node.textColor, node.renderCommands.space, maskBounds)

  except GLerror, Exception:
    discard
