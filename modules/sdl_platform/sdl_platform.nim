#use theme
import platform
import compilation_config

const currentSourcePath2 = currentSourcePath()
include module_base

proc newSdlPlatform*(): Platform {.rtl, raises: [].}

when implModule and defined(sdlPlatform):
  import std/[options, strformat, strutils, unicode, tables, hashes, os, math]
  import vmath as nevMath except Vec2, vec2, IVec2, ivec2, Vec3, Vec4, Mat4
  import chroma
  import nuigi/core/vecmath as nuiMath
  import misc/[custom_logger, util, event, timer, custom_async, custom_unicode]
  import ui/node as unode
  from ui/node import FontInfo, UIBorder, UINodeFlag, UINodeFlags
  import app_options, vfs, vfs_service, service

  import nuigi/backend/sdl3/sdl3
  import nuigi
  import nuigi/core/[timer as nuiTimer, array_view, arena]
  import nuigi/text/fonts
  import nuigi/rendering/mesh
  import nuigi/widgets, nuigi/widgets/[windows, plot]
  import nuigi/debug/[debug_panel, profiler, profiler_ui]
  import nuigi/styling/theme_editor
  import nuigi/demo/demo_window

  include nuigi/util/compat2

  {.push gcsafe.}
  {.push raises: [].}

  logCategory "sdl-platform"

  const PlotHistoryLen = 256
  const defaultAntialiasMeshWidth = 0.0'f32

  type
    SdlInputAccum = object
      frameIndex: uint64
      mouse: nuiMath.Vec2
      mouseDelta: nuiMath.Vec2
      wheel: nuiMath.Vec2
      mouseDown: UiMouseButtons
      mousePressed: UiMouseButtons
      mouseClickCount: uint8
      mouseReleased: UiMouseButtons
      keysDown: UiKeys
      keysPressed: UiKeys
      keysReleased: UiKeys
      keysRepeated: UiKeys
      modsDown: UiModifiers
      textInput: string

    SdlSettings = object
      msaaSelected*: int
      sampleCount*: GPUSampleCount
      fontSelected*: int
      antialiasMeshWidth*: float32
      renderOnDemand*: bool
      showDemoWindow*: bool
      showSettingsWindow*: bool
      showDebugPanel*: bool
      showDebugPanel2*: bool
      showThemeEditor*: bool
      showProfiler*: bool

    SdlPlatform* = ref object of Platform
      window: Window
      renderer: Renderer
      running*: bool
      winW*: cint
      winH*: cint
      vsync*: bool
      fontSizeVal*: float
      lineDistanceVal*: float
      lineHeightVal*: float
      charWidthVal*: float
      charGapVal*: float
      fontInfoVal: FontInfo
      currentMouseButtons*: set[MouseButton]

      # Nuigi state – all demo globals moved onto the platform
      nui: UiBuilder
      nuiInitialized: bool
      fontRender: FontRender
      fontAtlasTexture: Texture
      debugPanel: DebugPanel
      debugPanel2: DebugPanel
      themeEditor: ThemeEditor
      inputAccum: SdlInputAccum
      hadInput: bool
      redrawingUi: bool
      lastTime: float
      fps: float
      plotHistory: array[3, array[PlotHistoryLen, float32]]
      plotWrite: int
      plotCount: int
      fpsVal: float
      frameVal: float
      tickVal: float
      testFont: FontId
      settings: SdlSettings
      customMaterial: MaterialId

  # Active platform for callbacks that cannot capture (measureText etc.) – stored as pointer to stay gcsafe
  var gActiveNuiPlatform: SdlPlatform = nil

  proc activePlatform(): SdlPlatform {.inline, gcsafe.} =
    gcsafeb:
      gActiveNuiPlatform

  proc setActivePlatform(self: SdlPlatform) {.inline, gcsafe.} =
    gcsafeb:
      gActiveNuiPlatform = self

  func intersectRect(a, b: sdl3.Rect): sdl3.Rect =
    let x1 = max(a.x, b.x)
    let y1 = max(a.y, b.y)
    let x2 = min(a.x + a.w, b.x + b.w)
    let y2 = min(a.y + a.h, b.y + b.h)
    sdl3.Rect(x: x1, y: y1, w: max(0, x2 - x1), h: max(0, y2 - y1))

  func toUiColor(c: chroma.Color): UiColor =
    rgba(c.r.float32, c.g.float32, c.b.float32, c.a.float32)

  # ---------- helpers for fonts / plot ----------
  proc uiSdlArrangeText(text: openArray[char], fontId: FontId, fontSize: float32, maxWidth: float32): UiTextArrangement {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if activePlatform() != nil:
        return activePlatform().fontRender.arrangeText(text, fontSize, fontId, maxWidth)
    var fr: FontRender
    return fr.arrangeText(text, fontSize, fontId, maxWidth)

  proc uiSdlBuildTextMesh(arrangement: UiTextArrangement, pos, screenOffset: nuiMath.Vec2,
      color: UiColor, transform: UiAffine2): tuple[data: nil ptr UncheckedArray[UiVertex], count: int] {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if activePlatform() != nil:
        let mesh = activePlatform().fontRender.buildTextMesh(arrangement, pos, screenOffset, color, transform)
        return (cast[nil ptr UncheckedArray[UiVertex]](mesh.data), mesh.count)
    return (nil, 0)

  proc themeEditorListFonts(): seq[(string, UiFontId)] {.raises: [], gcsafe.} =
    gcsafeb:
      if activePlatform() == nil:
        return @[]
      let faces = activePlatform().fontRender.listFontFaces()
      var resultSeq: seq[(string, UiFontId)] = @[]
      resultSeq.setLen(faces.len)
      for i in 0 ..< faces.len:
        resultSeq[i] = (faces[i][0], UiFontId(faces[i][1]))
      return resultSeq

  proc themeEditorResolveFont(name: string): UiFontId {.raises: [], gcsafe.} =
    gcsafeb:
      if activePlatform() == nil:
        return 0'i16
      let faces = activePlatform().fontRender.listFontFaces()
      for i in 0 ..< faces.len:
        if faces[i][0] == name:
          return UiFontId(faces[i][1])
      return 0'i16

  proc plotHistoryFn(x: float32, userData: int): float32 {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      if activePlatform() == nil:
        return 0
      let self = activePlatform()
      let count = self.plotCount
      let i = clamp(x, 0, count.float32 - 1).int32
      if i < 0 or i >= count:
        return 0.0'f32
      let actualIdx = (self.plotWrite + (PlotHistoryLen - count) + i) mod PlotHistoryLen
      return self.plotHistory[userData][actualIdx]

  func toUiMouseButton(button: uint8): UiMouseButton =
    case button
    of 1: MouseLeft
    of 2: MouseMiddle
    of 3: MouseRight
    else: MouseLeft

  func toUiModifiers(m: Keymod): UiModifiers =
    let mm = m.uint32
    result = {}
    if (mm and KMOD_SHIFT) != 0: result.incl ModShift
    if (mm and KMOD_CTRL) != 0: result.incl ModControl
    if (mm and KMOD_ALT) != 0: result.incl ModAlt
    if (mm and KMOD_GUI) != 0: result.incl ModSuper

  func toUiKey(key: Keycode): tuple[found: bool, uiKey: UiKey] =
    case key
    of uint32(SDLK_A)..uint32(SDLK_Z):
      (true, UiKey(ord(KeyA) + int(key - uint32(SDLK_A))))
    of uint32(SDLK_0)..uint32(SDLK_9):
      (true, UiKey(ord(Key0) + int(key - uint32(SDLK_0))))
    of uint32(SDLK_SPACE): (true, KeySpace)
    of uint32(SDLK_RETURN): (true, KeyEnter)
    of uint32(SDLK_ESCAPE): (true, KeyEscape)
    of uint32(SDLK_BACKSPACE): (true, KeyBackspace)
    of uint32(SDLK_TAB): (true, KeyTab)
    of uint32(SDLK_LEFT): (true, KeyLeft)
    of uint32(SDLK_RIGHT): (true, KeyRight)
    of uint32(SDLK_UP): (true, KeyUp)
    of uint32(SDLK_DOWN): (true, KeyDown)
    of uint32(SDLK_F1)..uint32(SDLK_F12):
      (true, UiKey(ord(KeyF1) + int(key - uint32(SDLK_F1))))
    of uint32(SDLK_DELETE): (true, KeyDelete)
    of uint32(SDLK_HOME): (true, KeyHome)
    of uint32(SDLK_END): (true, KeyEnd)
    of uint32(SDLK_PAGEUP): (true, KeyPageUp)
    of uint32(SDLK_PAGEDOWN): (true, KeyPageDown)
    of uint32(SDLK_LSHIFT): (true, KeyShiftLeft)
    of uint32(SDLK_RSHIFT): (true, KeyShiftRight)
    of uint32(SDLK_LCTRL): (true, KeyControlLeft)
    of uint32(SDLK_RCTRL): (true, KeyControlRight)
    of uint32(SDLK_LALT): (true, KeyAltLeft)
    of uint32(SDLK_RALT): (true, KeyAltRight)
    of uint32(SDLK_LGUI): (true, KeySuperLeft)
    of uint32(SDLK_RGUI): (true, KeySuperRight)
    of uint32(SDLK_CAPSLOCK): (true, KeyCapsLock)
    of uint32(SDLK_SCROLLLOCK): (true, KeyScrollLock)
    of uint32(SDLK_NUMLOCKCLEAR): (true, KeyNumLock)
    of uint32(SDLK_INSERT): (true, KeyInsert)
    of uint32(SDLK_PAUSE): (true, KeyPause)
    of uint32(SDLK_MENU): (true, KeyMenu)
    of uint32(SDLK_SEMICOLON): (true, KeySemicolon)
    of uint32(SDLK_APOSTROPHE): (true, KeyApostrophe)
    of uint32(SDLK_COMMA): (true, KeyComma)
    of uint32(SDLK_MINUS): (true, KeyMinus)
    of uint32(SDLK_PERIOD): (true, KeyPeriod)
    of uint32(SDLK_SLASH): (true, KeySlash)
    of uint32(SDLK_BACKSLASH): (true, KeyBackslash)
    of uint32(SDLK_LEFTBRACKET): (true, KeyLeftBracket)
    of uint32(SDLK_RIGHTBRACKET): (true, KeyRightBracket)
    of uint32(SDLK_GRAVE): (true, KeyGrave)
    of uint32(SDLK_KP_1)..uint32(SDLK_KP_9):
      (true, UiKey(ord(KeyKp1) + int(key - uint32(SDLK_KP_1))))
    of uint32(SDLK_KP_0): (true, KeyKp0)
    of uint32(SDLK_KP_DIVIDE): (true, KeyKpDivide)
    of uint32(SDLK_KP_MULTIPLY): (true, KeyKpMultiply)
    of uint32(SDLK_KP_MINUS): (true, KeyKpSubtract)
    of uint32(SDLK_KP_PLUS): (true, KeyKpAdd)
    of uint32(SDLK_KP_PERIOD): (true, KeyKpDecimal)
    of uint32(SDLK_KP_ENTER): (true, KeyKpEnter)
    else: (false, default(UiKey))

  func toPlatformModifiers(m: Keymod): Modifiers =
    let mm = m.uint32
    result = {}
    if (mm and KMOD_SHIFT) != 0: result.incl Shift
    if (mm and KMOD_CTRL) != 0: result.incl Control
    if (mm and KMOD_ALT) != 0: result.incl Alt
    if (mm and KMOD_GUI) != 0: result.incl Super

  func toPlatformMouseButton(button: uint8): MouseButton =
    case button
    of 1: MouseButton.Left
    of 2: MouseButton.Middle
    of 3: MouseButton.Right
    else: MouseButton.Unknown

  proc sdlKeyToInput(key: Keycode): int64 =
    case key
    of SDLK_RETURN, SDLK_KP_ENTER: INPUT_ENTER
    of SDLK_ESCAPE: INPUT_ESCAPE
    of SDLK_BACKSPACE: INPUT_BACKSPACE
    of SDLK_SPACE: INPUT_SPACE
    of SDLK_DELETE: INPUT_DELETE
    of SDLK_TAB: INPUT_TAB
    of SDLK_LEFT: INPUT_LEFT
    of SDLK_RIGHT: INPUT_RIGHT
    of SDLK_UP: INPUT_UP
    of SDLK_DOWN: INPUT_DOWN
    of SDLK_HOME: INPUT_HOME
    of SDLK_END: INPUT_END
    of SDLK_PAGEUP: INPUT_PAGE_UP
    of SDLK_PAGEDOWN: INPUT_PAGE_DOWN
    of SDLK_F1: INPUT_F1
    of SDLK_F2: INPUT_F1 - 1
    of SDLK_F3: INPUT_F1 - 2
    of SDLK_F4: INPUT_F1 - 3
    of SDLK_F5: INPUT_F1 - 4
    of SDLK_F6: INPUT_F1 - 5
    of SDLK_F7: INPUT_F1 - 6
    of SDLK_F8: INPUT_F1 - 7
    of SDLK_F9: INPUT_F1 - 8
    of SDLK_F10: INPUT_F1 - 9
    of SDLK_F11: INPUT_F1 - 10
    of SDLK_F12: INPUT_F1 - 11
    of SDLK_A..SDLK_Z: int64(ord('a') + int(key - SDLK_A))
    of SDLK_0..SDLK_9: int64(ord('0') + int(key - SDLK_0))
    of SDLK_KP_0: int64(ord('0'))
    of SDLK_KP_1..SDLK_KP_9: int64(ord('1') + int(key - SDLK_KP_1))
    of SDLK_KP_DIVIDE: int64(ord('/'))
    of SDLK_KP_MULTIPLY: int64(ord('*'))
    of SDLK_KP_MINUS: int64(ord('-'))
    of SDLK_KP_PLUS: int64(ord('+'))
    of SDLK_KP_PERIOD: int64(ord('.'))
    of SDLK_GRAVE: int64(ord('`'))
    of SDLK_MINUS: int64(ord('-'))
    of SDLK_EQUALS: int64(ord('='))
    of SDLK_LEFTBRACKET: int64(ord('['))
    of SDLK_RIGHTBRACKET: int64(ord(']'))
    of SDLK_BACKSLASH: int64(ord('\\'))
    of SDLK_SEMICOLON: int64(ord(';'))
    of SDLK_APOSTROPHE: int64(ord('\''))
    of SDLK_COMMA: int64(ord(','))
    of SDLK_PERIOD: int64(ord('.'))
    of SDLK_SLASH: int64(ord('/'))
    else: 0

  proc getStatisticsStringSdlPlatform(self: SdlPlatform): string =
    result = &"Window: {self.winW}x{self.winH}\n"
    result.add &"VSync: {self.vsync}\n"
    result.add &"Nui nodes: {self.nui.frame.nodes.len}\n"

  proc sizeSdlPlatform(self: SdlPlatform): nevMath.Vec2 =
    try:
      if self.window != nil:
        var w, h: cint = 0
        discard sdl3.getWindowSize(self.window, w, h)
        if w > 0 and h > 0:
          self.winW = w
          self.winH = h
          return nevMath.vec2(w.float, h.float)
      return nevMath.vec2(self.winW.float, self.winH.float)
    except:
      return nevMath.vec2(self.winW.float, self.winH.float)

  proc sizeChangedSdlPlatform(self: SdlPlatform): bool =
    try:
      if self.window != nil:
        var w, h: cint = 0
        if sdl3.getWindowSize(self.window, w, h) and w > 0 and h > 0:
          return w != self.winW or h != self.winH
      return false
    except:
      return false

  proc requestRenderSdlPlatform(self: SdlPlatform, redrawEverything: bool) =
    self.requestedRender = true
    self.redrawEverything = self.redrawEverything or redrawEverything

  var sdlExposeWatchInstalled {.global.}: bool = false

  proc sdlExposeWatch(userdata: pointer, event: ptr sdl3.Event): bool {.cdecl, gcsafe.} =
    if event == nil:
      return true
    if event[].`type` != sdl3.EVENT_WINDOW_EXPOSED:
      return true
    let self = cast[SdlPlatform](userdata)
    if self == nil or self.window == nil:
      return true
    if sdl3.getWindowFromEvent(event) != self.window:
      return true
    try:
      self.onResize.invoke()
      self.requestRenderSdlPlatform(true)
    except:
      discard
    return true

  # ----- plot helpers on platform -----
  proc plotMetricMax(self: SdlPlatform, metric: int): float32 =
    result = 1.0'f32
    for i in 0 ..< self.plotCount:
      let idx = (self.plotWrite + (PlotHistoryLen - self.plotCount) + i) mod PlotHistoryLen
      result = max(result, self.plotHistory[metric][idx])

  proc plotMetricAvg(self: SdlPlatform, metric: int, samples = 10): float32 =
    let n = min(samples, self.plotCount)
    if n == 0:
      return 0.0'f32
    var sum = 0.0'f32
    for i in 0 ..< n:
      let idx = (self.plotWrite - 1 - i + PlotHistoryLen) mod PlotHistoryLen
      sum += self.plotHistory[metric][idx]
    return sum / n.float32

  proc pushPlotHistory(self: SdlPlatform) =
    self.plotHistory[0][self.plotWrite] = self.fpsVal.float32
    self.plotHistory[1][self.plotWrite] = self.frameVal.float32
    self.plotHistory[2][self.plotWrite] = self.tickVal.float32
    self.plotWrite = (self.plotWrite + 1) mod PlotHistoryLen
    if self.plotCount < PlotHistoryLen:
      self.plotCount += 1

  proc finishFrameMetrics(self: SdlPlatform, dt: float64, tickStart: float32) =
    let tickDt = (nuiTimer.getTicksNS().float64 / NS_PER_MS.float64).float32 - tickStart
    self.fpsVal = self.fps
    self.frameVal = dt * 1000
    self.tickVal = tickDt
    self.pushPlotHistory()

  # ----- nui init -----
  proc ensureNuiInitialized(self: SdlPlatform) {.raises: [Exception].} =
    if self.nuiInitialized:
      return
    setActivePlatform(self)
    proc openUrl(url: string): bool {.nimcall, raises: [].} =
      var urlCopy = url
      openURL(toCString(urlCopy))
    proc readClipboard(): string {.nimcall, raises: [].} =
      result = ""
      let clipboardText = sdl3.getClipboardText()
      if clipboardText != nil:
        result = $clipboardText
        sdl3.sdlFree(clipboardText)
    proc writeClipboard(text: string): bool {.nimcall, raises: [].} =
      var textCopy = text
      sdl3.setClipboardText(toCString(textCopy))

    self.nui = newBuilder(uiSdlArrangeText, uiSdlBuildTextMesh,
      antialiasMeshWidth = self.settings.antialiasMeshWidth)
    self.nui.openUrlFn = openUrl
    self.nui.readClipboardFn = readClipboard
    self.nui.writeClipboardFn = writeClipboard
    discard self.nui.addThemeTextStyle UiNodeText(
      text: "hello world".uiString,
      fontId: self.testFont,
      fontSize: 16,
    )
    self.nuiInitialized = true
    self.themeEditor.listFonts = themeEditorListFonts
    self.themeEditor.resolveFont = themeEditorResolveFont

  proc syncSdlTextInput(self: SdlPlatform) {.raises: [Exception].} =
    if self.nui.textInputRequest.active:
      if not self.window.textInputActive():
        discard self.window.startTextInput()
      var rect = sdl3.Rect(
        x: floor(self.nui.textInputRequest.rectPos.x).cint,
        y: floor(self.nui.textInputRequest.rectPos.y).cint,
        w: max(1.0'f32, ceil(self.nui.textInputRequest.rectSize.x)).cint,
        h: max(1.0'f32, ceil(self.nui.textInputRequest.rectSize.y)).cint,
      )
      discard self.window.setTextInputArea(rect.addr,
        max(0.0'f32, round(self.nui.textInputRequest.cursorOffset)).cint)
    elif self.window.textInputActive():
      discard self.window.stopTextInput()

  proc syncFontAtlas(self: SdlPlatform) {.raises: [Exception].} =
    if self.fontAtlasTexture == nil:
      self.fontAtlasTexture = createTexture(self.renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STATIC,
        self.fontRender.fontAtlasWidth.cint, self.fontRender.fontAtlasHeight.cint)
      if self.fontAtlasTexture != nil:
        discard self.fontAtlasTexture.setTextureBlendMode(BLENDMODE_BLEND)
    if self.fontRender.fontAtlasNeedsReset:
      let shouldGrow = self.fontRender.fontAtlasNeedsResize and self.fontRender.canGrowFontAtlas()
      if not shouldGrow:
        self.fontRender.resetFontAtlas(false)
      else:
        let nextSize = self.fontRender.nextFontAtlasSize()
        if self.fontAtlasTexture != nil:
          destroyTexture(self.fontAtlasTexture)
        self.fontAtlasTexture = createTexture(self.renderer, PIXELFORMAT_RGBA32, TEXTUREACCESS_STATIC,
          nextSize.width.cint, nextSize.height.cint)
        if self.fontAtlasTexture != nil:
          discard self.fontAtlasTexture.setTextureBlendMode(BLENDMODE_BLEND)
        self.fontRender.resetFontAtlas(true)
    if self.fontRender.fontAtlasDirty and self.fontAtlasTexture != nil:
      let dirtyX = self.fontRender.fontAtlasDirtyMinX
      let dirtyY = self.fontRender.fontAtlasDirtyMinY
      let dirtyWidth = self.fontRender.fontAtlasDirtyMaxX - dirtyX
      let dirtyHeight = self.fontRender.fontAtlasDirtyMaxY - dirtyY
      if dirtyWidth > 0 and dirtyHeight > 0:
        var rect = sdl3.Rect(x: dirtyX.cint, y: dirtyY.cint, w: dirtyWidth.cint, h: dirtyHeight.cint)
        let srcOffset = (dirtyY * self.fontRender.fontAtlasWidth + dirtyX) * 4
        if srcOffset + dirtyWidth * dirtyHeight * 4 <= self.fontRender.fontAtlasPixels.len:
          discard updateTexture(self.fontAtlasTexture, rect.addr,
            cast[ptr UncheckedArray[uint8]](self.fontRender.fontAtlasPixels[srcOffset].addr),
            (self.fontRender.fontAtlasWidth * 4).cint)
      self.fontRender.clearFontAtlasDirty()
    self.nui.fontAtlasImageId = cast[UiImageId](self.fontAtlasTexture)

  proc beginNuiInputFrame(self: SdlPlatform) =
    self.inputAccum.frameIndex += 1
    self.inputAccum.mousePressed = {}
    self.inputAccum.mouseClickCount = 0
    self.inputAccum.mouseReleased = {}
    self.inputAccum.mouseDelta = nuiMath.vec2(0, 0)
    self.inputAccum.wheel = nuiMath.vec2(0, 0)
    self.inputAccum.keysPressed = {}
    self.inputAccum.keysReleased = {}
    self.inputAccum.keysRepeated = {}
    self.inputAccum.textInput.setLen(0)
    self.hadInput = false

  proc makeInputSnapshot(self: SdlPlatform): UiInputSnapshot =
    result = UiInputSnapshot(
      frameIndex: self.inputAccum.frameIndex,
      mouse: self.inputAccum.mouse,
      mouseDelta: self.inputAccum.mouseDelta,
      wheel: self.inputAccum.wheel,
      mouseDown: self.inputAccum.mouseDown,
      mousePressed: self.inputAccum.mousePressed,
      mouseClickCount: self.inputAccum.mouseClickCount,
      mouseReleased: self.inputAccum.mouseReleased,
      keysDown: self.inputAccum.keysDown,
      keysPressed: self.inputAccum.keysPressed,
      keysReleased: self.inputAccum.keysReleased,
      keysRepeated: self.inputAccum.keysRepeated,
      modsDown: self.inputAccum.modsDown,
      textInput: self.inputAccum.textInput,
    )

  proc accumulateNuiInput(self: SdlPlatform, ev: var sdl3.Event) =
    case ev.`type`
    of EVENT_MOUSE_MOTION:
      self.inputAccum.mouse = nuiMath.vec2(ev.motion.x, ev.motion.y)
      self.inputAccum.mouseDelta.x += ev.motion.xrel
      self.inputAccum.mouseDelta.y += ev.motion.yrel
      self.hadInput = true
    of EVENT_MOUSE_BUTTON_DOWN:
      let mb = toUiMouseButton(ev.button.button)
      self.inputAccum.mouseDown.incl mb
      self.inputAccum.mousePressed.incl mb
      if mb == MouseLeft:
        self.inputAccum.mouseClickCount = ev.button.clicks
      self.inputAccum.mouse = nuiMath.vec2(ev.button.x, ev.button.y)
      self.hadInput = true
    of EVENT_MOUSE_BUTTON_UP:
      let mb = toUiMouseButton(ev.button.button)
      self.inputAccum.mouseDown.excl mb
      self.inputAccum.mouseReleased.incl mb
      self.inputAccum.mouse = nuiMath.vec2(ev.button.x, ev.button.y)
      self.hadInput = true
    of EVENT_MOUSE_WHEEL:
      self.inputAccum.wheel.x += ev.wheel.x
      self.inputAccum.wheel.y += ev.wheel.y
      self.hadInput = true
    of EVENT_KEY_DOWN:
      let (found, uk) = ev.key.key.toUiKey()
      if found:
        self.inputAccum.keysDown.incl uk
        if ev.key.repeat:
          self.inputAccum.keysRepeated.incl uk
        else:
          self.inputAccum.keysPressed.incl uk
        self.inputAccum.modsDown = toUiModifiers(ev.key.`mod`)
        self.hadInput = true
    of EVENT_KEY_UP:
      let (found, uk) = ev.key.key.toUiKey()
      if found:
        self.inputAccum.keysDown.excl uk
        self.inputAccum.keysReleased.incl uk
      self.inputAccum.modsDown = toUiModifiers(ev.key.`mod`)
      self.hadInput = true
    of EVENT_TEXT_INPUT:
      if ev.text.text != nil:
        self.inputAccum.textInput.add($ev.text.text)
        self.hadInput = true
    else:
      discard

  {.pop: raises.}
  {.pop: gcsafe.}
  # ----- settings window helpers (platform-owned) -----
  proc buildSettingsMetricRow(self: SdlPlatform, b: var UiBuilder, prefix: string, metric: int, maxY: float32, precision: int) {.raises: [Exception].} =
    try:
      b.layoutHorizontal:
        discard b.fit().gap(8).padding(2)
        let display = prefix & ": " & formatFloat(self.plotMetricAvg(metric, 50).float64, ffDecimal, precision)
        b.node:
          let plotSize = nuiMath.vec2(100.0'f32, 50.0'f32)
          discard b.size(plotSize).backgroundColor(b.themeStyle(UiStyleIndexStage)[].fillColor)
          let nodeIdx = b.currentNodeIndex()
          let nodeAbs = b.absoluteNodePos(nodeIdx)
          let style = b.nodeStyle(b.currentNode)
          let contentPos = nodeAbs + nuiMath.vec2(style.paddingX, style.paddingY)
          let contentSize = plotSize - nuiMath.vec2(style.paddingX * 2.0'f32, style.paddingY * 2.0'f32)
          if contentSize.x > 0 and contentSize.y > 0:
            try:
              let count = max(1, self.plotCount)
              var series = array[1, PlotSeries].default
              series[0] = PlotSeries(
                fn: plotHistoryFn,
                userData: metric,
                label: uiString(prefix),
                lineColor: rgba(0.35'f32, 0.55'f32, 0.95'f32, 1.0'f32),
                fillTopColor: rgba(0.35'f32, 0.55'f32, 0.95'f32, 0.25'f32),
                fillBottomColor: rgba(0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32),
              )
              let commands = buildPlotVertices(
                b,
                contentPos,
                contentSize,
                nuiMath.vec2(0.0'f32, count.float32 - 1.0'f32),
                nuiMath.vec2(0.0'f32, max(maxY, self.plotMetricMax(metric) * 1.1'f32)),
                series.toOpenArray(0, 0),
                resolution = min(self.plotCount, 100),
                lineThickness = 1.5'f32,
                mousePos = b.frameCtx.input.mouse,
              )
              discard b.customRenderCommands(commands)
            except:
              discard
        b.node:
          discard b.fit().padding(10).fontId(self.testFont).text(display).alignCenter()
    except:
      discard

  proc buildSettingsWindow(self: SdlPlatform, b: var UiBuilder) {.raises: [Exception].} =
    b.window("Settings", 0.0, 0.0, 420.0, 640.0):
      b.scrollBox():
        discard b.sizeToParentX().fitY()
        b.layoutVertical:
          discard b.fillX().fitY().padding(12).gap(12)

          b.node():
            discard b.fillX().fitY().padding(2)
            discard b.backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
            discard b.copyTextStyleIndex(UiStyleIndexHeadingText)
            discard b.text("Performance")

          self.buildSettingsMetricRow(b, "FPS", metric = 0, maxY = 120, precision = 0)
          self.buildSettingsMetricRow(b, "Frame", metric = 1, maxY = 8,  precision = 1)
          self.buildSettingsMetricRow(b, "Tick", metric = 2, maxY = 8,  precision = 1)

          b.node():
            discard b.fillX().fitY().padding(2)
            discard b.backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
            discard b.copyTextStyleIndex(UiStyleIndexHeadingText)
            discard b.text("Rendering")

          b.tableLayout([tableColumnFit(), tableColumnFill()], 14, 10):
            discard b.fillX().fitY()
            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Mesh AA Width")
            var antialias = self.nui.antialiasMeshWidth
            discard b.dragFloat(antialias, defaultAntialiasMeshWidth, 0.0'f32, 4.0'f32)
            self.nui.antialiasMeshWidth = antialias
            self.settings.antialiasMeshWidth = antialias

            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Render On Demand")
            discard b.checkbox("", self.settings.renderOnDemand)

            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Profiler Overlay")
            var profilerOn = self.settings.showProfiler
            discard b.checkbox("", profilerOn)
            self.settings.showProfiler = profilerOn
            gShowNuiProfiler = profilerOn

            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Demo")
            discard b.checkbox("", self.settings.showDemoWindow)

            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Theme Editor")
            var x = self.nui.showThemeEditor
            discard b.checkbox("", x)
            self.nui.showThemeEditor = x
            self.settings.showThemeEditor = x

            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Debug Panel")
            x = self.nui.showDebugPanel
            discard b.checkbox("", x)
            self.nui.showDebugPanel = x
            self.settings.showDebugPanel = x

            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Debug Panel 2")
            x = self.nui.showDebugPanel2
            discard b.checkbox("", x)
            self.nui.showDebugPanel2 = x
            self.settings.showDebugPanel2 = x
            self.settings.showProfiler = gShowNuiProfiler

          b.node():
            discard b.fillX().fitY().padding(2)
            discard b.backgroundColor(b.themeStyle(UiStyleIndexHeader)[].fillColor)
            discard b.copyTextStyleIndex(UiStyleIndexHeadingText)
            discard b.text("Text")

          b.tableLayout([tableColumnFit(), tableColumnFill()], 14, 10):
            discard b.fit()
            b.node():
              discard b.fit()
              discard b.copyTextStyleIndex(UiStyleIndexLabelText)
              discard b.text("Font Hinting")
            if b.dropdown(["Subpixel", "Pixel snapped", "Fractional"], self.settings.fontSelected):
              case self.settings.fontSelected
              of 0: self.fontRender.flags = {FontRenderFlag.SubpixelPhasing, FontRenderFlag.PixelSnapping}
              of 1: self.fontRender.flags = {FontRenderFlag.PixelSnapping}
              else: self.fontRender.flags = {}

  proc handleLegacyRenderCommand(
    cmd: unode.RenderCommand,
    renderCommands: ptr unode.RenderCommands,
    b: var UiBuilder,
    renderCmds: var ArrayView[UiRenderCommand],
    offsets: var seq[nuiMath.Vec2],
    curOffset: var nuiMath.Vec2
  ) {.gcsafe, raises: [].} =
    case cmd.kind
    of unode.RenderCommandKind.Rect:
      renderCmds.add UiRenderCommand(kind: CmdRectStroke, pos: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset, size: nuiMath.vec2(cmd.bounds.w.float32, cmd.bounds.h.float32), color: toUiColor(cmd.color), thickness: 1)
    of unode.RenderCommandKind.FilledRect:
      renderCmds.add UiRenderCommand(kind: CmdRectFill, pos: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset, size: nuiMath.vec2(cmd.bounds.w.float32, cmd.bounds.h.float32), color: toUiColor(cmd.color))
    of unode.RenderCommandKind.TextRaw:
      if cmd.len > 0 and cmd.data != nil:
        var txt = newString(cmd.len)
        copyMem(txt[0].addr, cmd.data, cmd.len)
        let textIdx = block:
          let idx = b.frame.texts.len
          b.frame.texts.add UiNodeText(text: txt.uiString, fontSize: 16, textColor: toUiColor(cmd.color))
          (idx + 1).uint16
        renderCmds.add UiRenderCommand(kind: CmdText, pos: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset, color: toUiColor(cmd.color), textIndex: textIdx)
    of unode.RenderCommandKind.Text:
      if cmd.arrangementIndex == uint32.high:
        if cmd.textLen > 0 and renderCommands != nil:
          let txt = renderCommands.strings[cmd.textOffset.int ..< cmd.textOffset.int + cmd.textLen.int]
          let textIdx = block:
            let idx = b.frame.texts.len
            b.frame.texts.add UiNodeText(text: txt.uiString, fontSize: 16 * max(0.1'f32, cmd.fontScale.float32), textColor: toUiColor(cmd.color))
            (idx + 1).uint16
          renderCmds.add UiRenderCommand(kind: CmdText, pos: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset, color: toUiColor(cmd.color), textIndex: textIdx)
      else:
        if renderCommands != nil and cmd.arrangementIndex.int < renderCommands.arrangements.len:
          let indices = renderCommands.arrangements[cmd.arrangementIndex]
          let arrangement = renderCommands.arrangement
          let basePos = nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset
          let baseColor = toUiColor(cmd.color)
          let underlineCol = toUiColor(cmd.underlineColor)
          let fontScale = max(0.1'f32, cmd.fontScale.float32)
          var txt = newStringOfCap(max(0, indices.runes.b - indices.runes.a + 1) * 4 + 4)
          for i in indices.runes:
            if i < 0 or i >= arrangement.runes.len: continue
            var rune = arrangement.runes[i]
            if rune == ' '.Rune and unode.TextDrawSpaces in cmd.flags:
              rune = renderCommands.space
            if rune.int32 < 32 and rune != ' '.Rune and rune != renderCommands.space:
              continue
            txt.add($rune)
          if txt.len > 0:
            let textIdx = block:
              let idx = b.frame.texts.len
              b.frame.texts.add UiNodeText(text: txt.uiString, fontSize: 16 * fontScale, textColor: baseColor)
              (idx + 1).uint16
            # echo basePos, " ", txt
            renderCmds.add UiRenderCommand(kind: CmdText, pos: basePos, color: baseColor, textIndex: textIdx)
          if unode.TextUndercurl in cmd.flags:
            renderCmds.add UiRenderCommand(kind: CmdRectFill, pos: basePos + nuiMath.vec2(0, cmd.bounds.h.float32 - 2), size: nuiMath.vec2(cmd.bounds.w.float32, 2), color: underlineCol)
    of unode.RenderCommandKind.Image:
      let imgId = UiImageId(cast[uint64](cmd.textureId))
      renderCmds.add UiRenderCommand(kind: CmdImage, pos: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset, size: nuiMath.vec2(cmd.bounds.w.float32, cmd.bounds.h.float32), color: toUiColor(cmd.color), imageId: imgId, uv0: nuiMath.vec2(cmd.uv0.x, cmd.uv0.y), uv1: nuiMath.vec2(cmd.uv1.x, cmd.uv1.y))
    of unode.RenderCommandKind.ScissorStart:
      renderCmds.add UiRenderCommand(kind: CmdClipPush, pos: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32) + curOffset, size: nuiMath.vec2(cmd.bounds.w.float32, cmd.bounds.h.float32))
    of unode.RenderCommandKind.ScissorEnd:
      renderCmds.add UiRenderCommand(kind: CmdClipPop)
    of unode.RenderCommandKind.TransformStart:
      offsets.add curOffset
      curOffset = curOffset + nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32)
      renderCmds.add UiRenderCommand(kind: CmdTransformPush, offset: nuiMath.vec2(cmd.bounds.x.float32, cmd.bounds.y.float32))
    of unode.RenderCommandKind.TransformEnd:
      if offsets.len > 0:
        curOffset = offsets.pop()
      renderCmds.add UiRenderCommand(kind: CmdTransformPop)
    else:
      discard

  proc convertLegacyNodes(self: SdlPlatform, b: var UiBuilder, n: unode.UINode, offset: nuiMath.Vec2) {.raises: [Exception].} =
    let nodePos = nuiMath.vec2(n.boundsActual.x.float32, n.boundsActual.y.float32)
    let nodeSize = nuiMath.vec2(n.boundsActual.w.float32, n.boundsActual.h.float32)
    let idStr = $n.id
    b.node(idStr):
      discard b.position(nodePos)
      discard b.size(nodeSize)
      if unode.FillBackground in n.flags:
        discard b.backgroundColor(toUiColor(n.backgroundColor))
      if unode.DrawBorder in n.flags and n.border != UIBorder():
        discard b.borderWidths(n.border.left.float32, n.border.top.float32, n.border.right.float32, n.border.bottom.float32)
        discard b.borderColor(toUiColor(n.borderColor))
      if unode.DrawText in n.flags and n.text.len > 0:
        discard b.text(n.text)
        discard b.textColor(toUiColor(n.textColor))
      if unode.MaskContent in n.flags:
        b.maskChildren()
      var totalCmds = n.renderCommands.commands.len
      for _ in n.renderCommands.decodeRenderCommands: inc totalCmds
      for list in n.renderCommandList:
        if list != nil:
          totalCmds += list.commands.len
          for _ in list[].decodeRenderCommands: inc totalCmds
      var renderCmds = b.frame.arena[].allocEmptyArray(max(1, totalCmds * 10 + 64), UiRenderCommand)
      var offsets: seq[nuiMath.Vec2]
      var curOffset = nodePos * 0 + offset * 0
      for cmd in n.renderCommands.commands:
        handleLegacyRenderCommand(cmd, n.renderCommands.addr, b, renderCmds, offsets, curOffset)
      for cmd in n.renderCommands.decodeRenderCommands:
        handleLegacyRenderCommand(cmd, n.renderCommands.addr, b, renderCmds, offsets, curOffset)
      for list in n.renderCommandList:
        if list != nil:
          for cmd in list.commands:
            handleLegacyRenderCommand(cmd, list[].addr, b, renderCmds, offsets, curOffset)
          for cmd in list[].decodeRenderCommands:
            handleLegacyRenderCommand(cmd, list[].addr, b, renderCmds, offsets, curOffset)
      if renderCmds.len > 0:
        discard b.customRenderCommands(renderCmds)
      for _, child in n.children:
        self.convertLegacyNodes(b, child, nodePos + offset)

  proc buildNuiUi(self: SdlPlatform) {.raises: [Exception].} =
    var b = self.nui.addr
    # Legacy Nev nodes – absolute positioned under a screen-covering custom root
    block:
      let vpW = if self.nui.frame.nodes.len > 0: self.nui.frame.nodes[0].size.x else: self.winW.float32
      let vpH = if self.nui.frame.nodes.len > 0: self.nui.frame.nodes[0].size.y else: self.winH.float32
      let rootW = if vpW > 0: vpW else: self.winW.float32
      let rootH = if vpH > 0: vpH else: self.winH.float32
      self.nui.node("nev-legacy-root"):
        discard self.nui.position(nuiMath.vec2(0, 0))
        discard self.nui.size(rootW, rootH)
        if self.builder != nil:
          for _, child in self.builder.root.children:
            self.convertLegacyNodes(self.nui, child, nuiMath.vec2(0, 0))

    self.nui.node("windows"):
      discard self.nui.fillX().fillY()
      self.nui.windowSpace()
    self.nui.node("overlays"):
      discard self.nui.fillX().fillY().noHover()
      self.nui.overlays = self.nui.currentNode.id

    if self.settings.showSettingsWindow:
      self.buildSettingsWindow(self.nui)

    if self.settings.showDemoWindow:
      self.nui.window("Demo", 400.0, 100.0, 800.0, 900.0):
        self.nui.buildDemoUi()

    if self.settings.showProfiler:
      self.nui.window("Profiler", 1200.0, 100.0, 700.0, 1000.0):
        self.nui.buildNuiProfiler()
      # keep global in sync for any external profiler code
      gShowNuiProfiler = self.settings.showProfiler

    if self.nui.showThemeEditor:
      var f = self.nui.defaultText.fontSize
      self.nui.defaultText.fontSize = 16
      discard self.nui.themeEditor(self.themeEditor)
      self.nui.defaultText.fontSize = f

    if self.nui.showDebugPanel:
      let viewportW = self.nui.frame.nodes[0].size.x
      let viewportH = self.nui.frame.nodes[0].size.y
      let debugPanelX = viewportW * (if self.nui.showDebugPanel2: 0.4'f32 else: 0.6'f32)
      let debugPanelWidth = viewportW * (if self.nui.showDebugPanel2: 0.3'f32 else: 0.4'f32)
      self.nui.window("Debug Panel", debugPanelX, 0.0'f32, debugPanelWidth, viewportH):
        discard self.nui.debugPanel(self.debugPanel)
        self.nui.flushDeferredNodes()
      if self.nui.showDebugPanel2:
        self.nui.window("Debug Panel 2", viewportW * 0.7'f32, 0.0'f32, viewportW * 0.3'f32, viewportH):
          discard self.nui.debugPanel(self.debugPanel2)

    block:
      self.nui.keepAlive(themeEditorId)
      self.nui.keepAlive("Examples".hashChars.UiNodeId)

  proc renderNui(self: SdlPlatform, outputWidth, outputHeight: int) {.raises: [Exception].} =
    # Renderer path (wasm-like) – uses SDL Renderer, not GPU
    self.nui.endUiFrame(buildMeshRenderCommands = true)
    self.syncSdlTextInput()
    self.syncFontAtlas()
    discard self.renderer.setRenderDrawColorFloat(0, 0, 0, 1)
    discard self.renderer.renderClear()
    # render nuigi commands via SDL Renderer
    let frameOut = self.nui.frameOutput
    # inline renderNewUiRenderer logic using self.renderer and self.nui
    block:
      proc drawRawVertices(renderer: Renderer, texture: nil Texture, first: ptr UiVertex, count: int) =
        if count <= 0: return
        let xy = cast[ptr cfloat](first)
        let color = cast[ptr FColor](cast[uint](first) + 16)
        let uv = cast[ptr cfloat](cast[uint](first) + 8)
        let stride = cint(sizeof(UiVertex))
        discard renderer.renderGeometryRaw(texture, xy, stride, color, stride, uv, stride, cint(count), nil, 0, 0)
      proc renderFilled(renderer: Renderer, transform: UiAffine2, pos, size: nuiMath.Vec2, color: UiColor, texture: nil Texture = nil) =
        if size.x <= 0 or size.y <= 0: return
        let p0 = transform.transformPoint2(pos)
        let p1 = transform.transformPoint2(pos + nuiMath.vec2(size.x, 0))
        let p2 = transform.transformPoint2(pos + size)
        let p3 = transform.transformPoint2(pos + nuiMath.vec2(0, size.y))
        var verts = [
          UiVertex(pos: p0, uv: nuiMath.vec2(0,0), color: color),
          UiVertex(pos: p1, uv: nuiMath.vec2(1,0), color: color),
          UiVertex(pos: p2, uv: nuiMath.vec2(1,1), color: color),
          UiVertex(pos: p0, uv: nuiMath.vec2(0,0), color: color),
          UiVertex(pos: p2, uv: nuiMath.vec2(1,1), color: color),
          UiVertex(pos: p3, uv: nuiMath.vec2(0,1), color: color),
        ]
        drawRawVertices(renderer, texture, verts[0].addr, 6)

      var transformStack: seq[UiAffine2] = @[identityAffine2()]
      var clipStack: seq[sdl3.Rect] = @[]
      for cmd in frameOut.commands:
        let transform = transformStack[^1]
        case cmd.kind
        of CmdTransformPush:
          transformStack.add applyNodeRenderTransform(transform, cmd.pivot, cmd.offset, cmd.rotation, cmd.scale)
        of CmdTransformPop:
          if transformStack.len > 1: discard transformStack.pop()
        of CmdRectFill:
          discard self.renderer.setRenderDrawColorFloat(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
          renderFilled(self.renderer, transform, cmd.pos, cmd.size, cmd.color)
        of CmdRawVertices:
          if cmd.vertexData != nil and cmd.vertexCount > 0:
            var texture: nil Texture = nil
            if cmd.imageId.uint64 == 1:
              texture = self.fontAtlasTexture
            else:
              texture = cast[Texture](cmd.imageId)
            drawRawVertices(self.renderer, texture, cast[ptr UiVertex](cmd.vertexData), cmd.vertexCount)
        of CmdRectStroke:
          discard self.renderer.setRenderDrawColorFloat(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
          let thickness = min(max(1.0'f32, cmd.thickness), min(cmd.size.x, cmd.size.y) * 0.5'f32)
          if thickness > 0:
            let innerH = max(0.0'f32, cmd.size.y - thickness * 2.0'f32)
            renderFilled(self.renderer, transform, cmd.pos, nuiMath.vec2(cmd.size.x, thickness), cmd.color)
            renderFilled(self.renderer, transform, nuiMath.vec2(cmd.pos.x, cmd.pos.y + cmd.size.y - thickness), nuiMath.vec2(cmd.size.x, thickness), cmd.color)
            renderFilled(self.renderer, transform, nuiMath.vec2(cmd.pos.x, cmd.pos.y + thickness), nuiMath.vec2(thickness, innerH), cmd.color)
            renderFilled(self.renderer, transform, nuiMath.vec2(cmd.pos.x + cmd.size.x - thickness, cmd.pos.y + thickness), nuiMath.vec2(thickness, innerH), cmd.color)
        of CmdText:
          var text: ptr UiNodeText = nil
          if cmd.textIndex > 0 and self.nui.frame.texts[cmd.textIndex - 1].text.len > 0:
            text = self.nui.frame.texts[cmd.textIndex - 1].addr
          if text != nil:
            let arrangement = self.nui.getTextArrangement(text, -1)
            if self.nui.buildTextMesh != nil:
              let (vertexData, vertexCount) = self.nui.buildTextMesh(arrangement[], cmd.pos, nuiMath.vec2(0,0), text.textColor, transform)
              if vertexData != nil and vertexCount > 0:
                drawRawVertices(self.renderer, self.fontAtlasTexture, cast[ptr UiVertex](vertexData), vertexCount)
        of CmdClipPush:
          let tr = transformedRectAabb(transform, cmd.pos, cmd.size)
          var clipRect = sdl3.Rect(x: floor(tr.pos.x).cint, y: floor(tr.pos.y).cint, w: max(0.0'f32, ceil(tr.size.x)).cint, h: max(0.0'f32, ceil(tr.size.y)).cint)
          if clipStack.len > 0:
            clipRect = intersectRect(clipStack[^1], clipRect)
          clipStack.add clipRect
          discard self.renderer.setRenderClipRect(clipRect)
        of CmdClipPop:
          if clipStack.len > 0: discard clipStack.pop()
          if clipStack.len > 0: discard self.renderer.setRenderClipRect(clipStack[^1])
          else: discard self.renderer.setRenderClipRect(nil)
        of CmdLine:
          let p0 = transform.transformPoint2(cmd.pos)
          let p1 = transform.transformPoint2(cmd.pos2)
          let dx = p1.x - p0.x
          let dy = p1.y - p0.y
          let len = sqrt(dx*dx + dy*dy)
          let nx = if len > 0: -dy / len * cmd.thickness * 0.5'f32 else: 0
          let ny = if len > 0: dx / len * cmd.thickness * 0.5'f32 else: 0
          var verts = [
            UiVertex(pos: nuiMath.vec2(p0.x + nx, p0.y + ny), uv: nuiMath.vec2(0,0), color: cmd.color),
            UiVertex(pos: nuiMath.vec2(p1.x + nx, p1.y + ny), uv: nuiMath.vec2(1,0), color: cmd.color),
            UiVertex(pos: nuiMath.vec2(p1.x - nx, p1.y - ny), uv: nuiMath.vec2(1,1), color: cmd.color),
            UiVertex(pos: nuiMath.vec2(p0.x + nx, p0.y + ny), uv: nuiMath.vec2(0,0), color: cmd.color),
            UiVertex(pos: nuiMath.vec2(p1.x - nx, p1.y - ny), uv: nuiMath.vec2(1,1), color: cmd.color),
            UiVertex(pos: nuiMath.vec2(p0.x - nx, p0.y - ny), uv: nuiMath.vec2(0,1), color: cmd.color),
          ]
          drawRawVertices(self.renderer, nil, verts[0].addr, 6)
        of CmdImage:
          var texture: nil Texture = nil
          if cmd.imageId.uint64 == 1: texture = self.fontAtlasTexture
          else: texture = cast[Texture](cmd.imageId)
          renderFilled(self.renderer, transform, cmd.pos, cmd.size, cmd.color, texture)
        else: discard

  proc initSdlPlatform(self: SdlPlatform, options: AppOptions) {.gcsafe, raises: [].} =
    log lvlInfo, "Init SDL platform (nuigi/sdl3)"
    try:
      self.vfs = getServiceChecked(VFSService).vfs

      if not sdl3.init(INIT_VIDEO or INIT_EVENTS):
        log lvlError, &"SDL_Init failed: {sdl3.getError()}"
        quit(1)

      const initialW = 1280.cint
      const initialH = 720.cint
      self.winW = initialW
      self.winH = initialH
      self.vsync = true

      self.window = sdl3.createWindow("nev - SDL", initialW, initialH, WINDOW_RESIZABLE)
      if self.window == nil:
        log lvlError, &"SDL_CreateWindow failed: {sdl3.getError()}"
        quit(1)

      discard setCurrentThreadPriority(THREAD_PRIORITY_TIME_CRITICAL)

      self.renderer = sdl3.createRenderer(self.window, nil)
      if self.renderer == nil:
        log lvlWarn, &"SDL_CreateRenderer failed: {sdl3.getError()}, continuing without renderer"
      else:
        discard self.renderer.setRenderDrawBlendMode(BLENDMODE_BLEND)
        discard self.renderer.setRenderDrawColor(30, 30, 46, 255)
        discard self.renderer.renderClear()
        discard self.renderer.renderPresent()

      self.builder = unode.newNodeBuilder()
      self.builder.useInvalidation = true
      self.builder.defaultBorderWidth = 1

      self.fontSizeVal = 16
      self.lineDistanceVal = 1
      self.lineHeightVal = 18
      self.charWidthVal = 8
      self.charGapVal = 0
      self.builder.charWidth = self.charWidthVal
      self.builder.lineHeight = self.lineHeightVal
      self.builder.lineGap = self.lineDistanceVal

      proc runeAdvance(r: Rune): float {.gcsafe, raises: [].} = 8.0
      self.fontInfoVal = FontInfo(
        ascent: 14,
        lineHeight: self.lineHeightVal,
        lineGap: self.lineDistanceVal,
        scale: 1.0,
        advance: runeAdvance,
      )
      self.builder.textWidthImpl = proc(node: unode.UINode): float32 {.gcsafe, raises: [].} = node.text.len.float32 * 8
      self.builder.textWidthStringImpl = proc(text: string): float32 {.gcsafe, raises: [].} = text.len.float32 * 8
      self.builder.textBoundsImpl = proc(node: unode.UINode): nevMath.Vec2 {.gcsafe, raises: [].} = nevMath.vec2(node.text.len.float32 * 8, 18)

      self.supportsThinCursor = true
      self.focused = true
      self.running = true

      # Platform-owned settings (no globals)
      self.settings = SdlSettings(
        msaaSelected: 3,
        sampleCount: GPU_SAMPLECOUNT_8,
        fontSelected: 0,
        antialiasMeshWidth: defaultAntialiasMeshWidth,
        renderOnDemand: true,
        showDemoWindow: true,
        showSettingsWindow: true,
        showDebugPanel: false,
        showDebugPanel2: false,
        showThemeEditor: false,
        showProfiler: false,
      )
      self.debugPanel = DebugPanel()
      self.debugPanel2 = DebugPanel()
      self.themeEditor = ThemeEditor()
      self.lastTime = nuiTimer.getTicksNS().float64 / NS_PER_SECOND.float64
      self.fps = 60.0
      self.testFont = 0

      # FontRender init – use Texture path (renderer)
      discard self.fontRender.init({FontRenderFlag.PixelSnapping}, glyphPackingBudgetNs = 100_000_000'u64)
      # Try system fonts + demo fonts from nuigi assets
      discard self.fontRender.addSystemDefaultFonts()
      let demoFontPath = "fonts/DejaVuSansMono.ttf"
      if fileExists(demoFontPath):
        self.testFont = self.fontRender.addFontFace(demoFontPath)
        discard self.fontRender.addFontFace("fonts/DejaVuSansMono-Bold.ttf")
        discard self.fontRender.addFontFace("fonts/DejaVuSansMono-Oblique.ttf")
      if self.testFont == 0:
        self.testFont = 0

      {.cast(gcsafe).}:
        setActivePlatform(self)
        self.ensureNuiInitialized()
      # Sync theme editor fonts
      self.themeEditor.listFonts = themeEditorListFonts
      self.themeEditor.resolveFont = themeEditorResolveFont

      if not sdlExposeWatchInstalled:
        # discard sdl3.addEventWatch(sdlExposeWatch, cast[pointer](self))
        sdlExposeWatchInstalled = true

      log lvlInfo, &"SDL window created {initialW}x{initialH} with nuigi"

      if options.monitor.getSome(idx):
        log lvlWarn, &"Monitor selection ({idx}) not yet implemented for SDL backend"

    except CatchableError as e:
      log lvlError, &"Failed to create SDL platform: {e.msg}"
      quit(1)
    except:
      log lvlError, &"Failed to create SDL platform: {getCurrentExceptionMsg()}"
      quit(1)

  proc deinitSdlPlatform(self: SdlPlatform) =
    try:
      if sdlExposeWatchInstalled:
        sdl3.removeEventWatch(sdlExposeWatch, cast[pointer](self))
        sdlExposeWatchInstalled = false
      if self.fontAtlasTexture != nil:
        destroyTexture(self.fontAtlasTexture)
        self.fontAtlasTexture = nil
      if self.renderer != nil:
        sdl3.destroyRenderer(self.renderer)
        self.renderer = nil
      if self.window != nil:
        sdl3.destroyWindow(self.window)
        self.window = nil
      sdl3.quit()
      if gActiveNuiPlatform == self:
        gActiveNuiPlatform = nil
      log lvlInfo, "SDL platform deinit done"
    except:
      discard

  proc setTitleSdlPlatform(self: SdlPlatform, title: string) =
    try:
      if self.window != nil:
        var t = title
        discard sdl3.setWindowTitle(self.window, t.cstring)
    except:
      discard

  proc processEventsSdlPlatform(self: SdlPlatform): int {.gcsafe, raises: [].} =
    self.eventCounter = 0
    try:
      # Reset per-frame input for nuigi
      self.beginNuiInputFrame()
      var ev: sdl3.Event
      while sdl3.pollEvent(ev):
        inc self.eventCounter
        # Feed to nuigi first (handles gamepad + ui input)
        self.accumulateNuiInput(ev)
        case ev.`type`
        of sdl3.EVENT_QUIT:
          self.onCloseRequested.invoke()
        of sdl3.EVENT_WINDOW_CLOSE_REQUESTED:
          when compiles(ev.window.windowID):
            if self.window != nil and ev.window.windowID == sdl3.getWindowID(self.window):
              self.onCloseRequested.invoke()
            elif self.window == nil:
              self.onCloseRequested.invoke()
          else:
            self.onCloseRequested.invoke()
        of sdl3.EVENT_WINDOW_RESIZED, sdl3.EVENT_WINDOW_PIXEL_SIZE_CHANGED,
           sdl3.EVENT_WINDOW_EXPOSED, sdl3.EVENT_WINDOW_SHOWN,
           sdl3.EVENT_WINDOW_DISPLAY_SCALE_CHANGED, sdl3.EVENT_WINDOW_DISPLAY_CHANGED,
           sdl3.EVENT_WINDOW_MAXIMIZED, sdl3.EVENT_WINDOW_RESTORED:
          var w, h: cint = 0
          if self.window != nil:
            discard sdl3.getWindowSize(self.window, w, h)
            if w > 0 and h > 0:
              self.winW = w
              self.winH = h
          self.onResize.invoke()
          self.requestRenderSdlPlatform(true)
        of sdl3.EVENT_WINDOW_FOCUS_GAINED:
          self.focused = true
          self.onFocusChanged.invoke(true)
        of sdl3.EVENT_WINDOW_FOCUS_LOST:
          self.focused = false
          self.currentMouseButtons = {}
          self.setMods({})
          self.onFocusChanged.invoke(false)
        of sdl3.EVENT_MOUSE_MOTION:
          let pos = nevMath.vec2(ev.motion.x.float, ev.motion.y.float)
          let delta = nevMath.vec2(ev.motion.xrel.float, ev.motion.yrel.float)
          if not self.builder.handleMouseMoved(pos, self.currentMouseButtons, self.currentModifiers):
            self.onMouseMove.invoke((pos, delta, self.currentModifiers, self.currentMouseButtons))
        of sdl3.EVENT_MOUSE_BUTTON_DOWN:
          var button = toPlatformMouseButton(ev.button.button)
          if ev.button.clicks == 2:
            button = MouseButton.DoubleClick
          elif ev.button.clicks == 3:
            button = MouseButton.TripleClick
          if button in {MouseButton.Left, MouseButton.Middle, MouseButton.Right}:
            self.currentMouseButtons.incl button
          elif button in {MouseButton.DoubleClick, MouseButton.TripleClick}:
            # also track as Left for compatibility, but keep distinct button for event
            discard
          let pos = nevMath.vec2(ev.button.x.float, ev.button.y.float)
          # if not self.builder.handleMousePressed(button, self.currentModifiers, pos):
          #   self.onMousePress.invoke((button, self.currentModifiers, pos))
        of sdl3.EVENT_MOUSE_BUTTON_UP:
          var button = toPlatformMouseButton(ev.button.button)
          if ev.button.clicks == 2:
            button = MouseButton.DoubleClick
          elif ev.button.clicks == 3:
            button = MouseButton.TripleClick
          if button in {MouseButton.Left, MouseButton.Middle, MouseButton.Right}:
            self.currentMouseButtons.excl button
          let pos = nevMath.vec2(ev.button.x.float, ev.button.y.float)
          # if not self.builder.handleMouseReleased(button, self.currentModifiers, pos):
          #   self.onMouseRelease.invoke((button, self.currentModifiers, pos))
        of sdl3.EVENT_MOUSE_WHEEL:
          let pos = nevMath.vec2(ev.wheel.mouse_x.float, ev.wheel.mouse_y.float)
          let scroll = nevMath.vec2(ev.wheel.x.float, ev.wheel.y.float)
          if scroll.x != 0 or scroll.y != 0:
            if not self.builder.handleMouseScroll(pos, scroll, self.currentModifiers):
              self.onScroll.invoke((pos, scroll, self.currentModifiers))
        of sdl3.EVENT_KEY_DOWN:
          let mods = toPlatformModifiers(ev.key.`mod`)
          self.setMods(mods)
          let input = sdlKeyToInput(ev.key.key)
          if input != 0:
            if not self.builder.handleKeyPressed(input, mods):
              self.onKeyPress.invoke((input, mods))
        of sdl3.EVENT_KEY_UP:
          let mods = toPlatformModifiers(ev.key.`mod`)
          self.setMods(mods)
          let input = sdlKeyToInput(ev.key.key)
          if input != 0:
            if not self.builder.handleKeyReleased(input, mods):
              self.onKeyRelease.invoke((input, mods))
        of sdl3.EVENT_TEXT_INPUT:
          if ev.text.text != nil:
            let text = $ev.text.text
            for r in text.runes:
              if r.int32 in char.low.ord .. char.high.ord:
                case r.char
                of ' ': continue
                of 8.char: continue
                of 9.char: continue
                of 13.char: continue
                of 127.char: continue
                else: discard
              self.onRune.invoke((r.int64, self.currentModifiers))
        of sdl3.EVENT_DROP_FILE:
          if ev.drop.data != nil:
            let path = $ev.drop.data
            self.onDropFile.invoke((path, ""))
        else:
          discard
      if self.eventCounter > 0:
        inc self.eventCounter
      return self.eventCounter
    except:
      return self.eventCounter

  proc renderSdlPlatform(self: SdlPlatform, rerender: bool) {.gcsafe, raises: [].} =
    try:
      if self.renderer == nil or self.window == nil:
        return
      setActivePlatform(self)
      {.cast(gcsafe).}:
        self.ensureNuiInitialized()

      # Timing like demo
      let now = nuiTimer.getTicksNS().float64 / NS_PER_SECOND.float64
      var dt = now - self.lastTime
      if dt < 0: dt = 0.016
      self.lastTime = now
      if dt != 0:
        self.fps = mix(self.fps, 1.0 / dt, 0.5)
      let tickStart = (nuiTimer.getTicksNS().float64 / NS_PER_MS.float64).float32

      # Decide if we should render (respect renderOnDemand)
      let shouldRender = self.nui.shouldRender(self.hadInput)
      if self.settings.renderOnDemand and not shouldRender and not rerender:
        return

      if self.redrawingUi:
        return
      self.redrawingUi = true
      defer: self.redrawingUi = false

      var outputWidth, outputHeight: cint = 0
      discard self.window.getWindowSize(outputWidth, outputHeight)
      if outputWidth <= 0 or outputHeight <= 0:
        return

      # Update antialias from settings
      self.nui.antialiasMeshWidth = self.settings.antialiasMeshWidth

      # Refresh fonts map for theme editor
      let faces = self.fontRender.listFontFaces()
      self.nui.fonts.clear()
      for (name, id) in faces:
        self.nui.fonts[name] = id

      {.cast(gcsafe).}:
        discard self.nui.beginUiFrame(outputWidth.float32, outputHeight.float32, self.makeInputSnapshot())
        self.buildNuiUi()
        self.renderNui(outputWidth.int, outputHeight.int)
      self.finishFrameMetrics(dt, tickStart)
      discard self.renderer.renderPresent()
      self.hadInput = false
    except CatchableError as e:
      log lvlError, &"SDL render failed: {e.msg}"
    except:
      discard

  {.push gcsafe.}
  {.push raises: [].}

  proc fontSizeSetSdlPlatform(self: SdlPlatform, fontSize: float) =
    self.fontSizeVal = fontSize
    self.fontInfoVal.lineHeight = self.lineHeightVal
    self.builder.charWidth = self.charWidthVal

  proc lineDistanceSetSdlPlatform(self: SdlPlatform, lineDistance: float) =
    self.lineDistanceVal = lineDistance
    self.builder.lineGap = lineDistance

  proc setFontSdlPlatform(self: SdlPlatform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) =
    discard

  proc getFontInfoSdlPlatform(self: SdlPlatform, fontSize: float, flags: UINodeFlags): ptr FontInfo {.gcsafe, raises: [].} =
    self.fontInfoVal.addr

  proc fontSizeSdlPlatform(self: SdlPlatform): float = self.fontSizeVal
  proc lineDistanceSdlPlatform(self: SdlPlatform): float = self.lineDistanceVal
  proc lineHeightSdlPlatform(self: SdlPlatform): float = self.lineHeightVal
  proc charWidthSdlPlatform(self: SdlPlatform): float = self.charWidthVal
  proc charGapSdlPlatform(self: SdlPlatform): float = self.charGapVal

  proc setVsyncSdlPlatform(self: SdlPlatform, enabled: bool) {.gcsafe, raises: [].} =
    self.vsync = enabled

  proc moveToMonitorSdlPlatform(self: SdlPlatform, index: int) {.gcsafe, raises: [].} =
    discard

  proc focusWindowSdlPlatform(self: SdlPlatform) {.gcsafe, raises: [].} =
    discard

  proc setClipboardTextSdlPlatform(self: SdlPlatform, str: string) {.gcsafe, raises: [].} =
    try:
      var s = str
      discard sdl3.setClipboardText(s.cstring)
    except:
      discard

  proc getClipboardTextSdlPlatform(self: SdlPlatform): Future[Option[string]] {.async: (raises: []).} =
    try:
      let c = sdl3.getClipboardText()
      if c != nil and c[0] != '\0':
        let s = $c
        sdl3.sdlFree(cast[pointer](c))
        return s.replace("\r", "").some
      if c != nil:
        sdl3.sdlFree(cast[pointer](c))
      return string.none
    except:
      return string.none

  {.pop: raises.}
  {.pop: gcsafe.}

  proc newSdlPlatform*(): Platform {.raises: [].} =
    var res = SdlPlatform()
    res.requestRenderImpl = proc(self: Platform, redrawEverything = false) = self.SdlPlatform.requestRenderSdlPlatform(redrawEverything)
    res.renderImpl = proc(self: Platform, rerender: bool) = self.SdlPlatform.renderSdlPlatform(rerender)
    res.sizeChangedImpl = proc(self: Platform): bool = self.SdlPlatform.sizeChangedSdlPlatform()
    res.sizeImpl = proc(self: Platform): nevMath.Vec2 = self.SdlPlatform.sizeSdlPlatform()
    res.initImpl = proc(self: Platform, options: AppOptions) = self.SdlPlatform.initSdlPlatform(options)
    res.deinitImpl = proc(self: Platform) = self.SdlPlatform.deinitSdlPlatform()
    res.processEventsImpl = proc(self: Platform): int = self.SdlPlatform.processEventsSdlPlatform()
    res.fontSizeSetImpl = proc(self: Platform, fontSize: float) = self.SdlPlatform.fontSizeSetSdlPlatform(fontSize)
    res.lineDistanceSetImpl = proc(self: Platform, lineDistance: float) = self.SdlPlatform.lineDistanceSetSdlPlatform(lineDistance)
    res.setFontImpl = proc(self: Platform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) = self.SdlPlatform.setFontSdlPlatform(fontRegular, fontBold, fontItalic, fontBoldItalic, fallbackFonts)
    res.getFontInfoImpl = proc(self: Platform, fontSize: float, flags: UINodeFlags): ptr FontInfo = self.SdlPlatform.getFontInfoSdlPlatform(fontSize, flags)
    res.fontSizeImpl = proc(self: Platform): float = self.SdlPlatform.fontSizeSdlPlatform()
    res.lineDistanceImpl = proc(self: Platform): float = self.SdlPlatform.lineDistanceSdlPlatform()
    res.lineHeightImpl = proc(self: Platform): float = self.SdlPlatform.lineHeightSdlPlatform()
    res.charWidthImpl = proc(self: Platform): float = self.SdlPlatform.charWidthSdlPlatform()
    res.charGapImpl = proc(self: Platform): float = self.SdlPlatform.charGapSdlPlatform()
    res.getStatisticsStringImpl = proc(self: Platform): string = self.SdlPlatform.getStatisticsStringSdlPlatform()
    res.setVsyncImpl = proc(self: Platform, enabled: bool) = self.SdlPlatform.setVsyncSdlPlatform(enabled)
    res.moveToMonitorImpl = proc(self: Platform, index: int) = self.SdlPlatform.moveToMonitorSdlPlatform(index)
    res.focusWindowImpl = proc(self: Platform) = self.SdlPlatform.focusWindowSdlPlatform()
    res.setClipboardTextImpl = proc(self: Platform, str: string) = self.SdlPlatform.setClipboardTextSdlPlatform(str)
    res.getClipboardTextImpl = proc(self: Platform): Future[Option[string]] {.async: (raises: [])} = self.SdlPlatform.getClipboardTextSdlPlatform().await
    res.setTitleImpl = proc(self: Platform, title: string) = self.SdlPlatform.setTitleSdlPlatform(title)
    return res

  proc init_module_sdl_platform*() {.cdecl, exportc, dynlib.} =
    discard

elif implModule:
  proc init_module_sdl_platform*() {.cdecl, exportc, dynlib.} =
    discard
  proc newSdlPlatform*(): Platform {.raises: [].} =
    assert false
    nil
else:
  proc init_module_sdl_platform*() {.cdecl, exportc, dynlib.} =
    discard
