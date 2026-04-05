import std/[locks]
import vmath, chroma
import ui/node
import misc/[event, timer]
import input, vfs, app_options, scripting_api, pixie

export input, event

type
  RequestRenderImpl* = proc(self: Platform, redrawEverything: bool) {.gcsafe, raises: [].}
  RenderImpl* = proc(self: Platform, rerender: bool) {.gcsafe, raises: [].}
  SizeChangedImpl* = proc(self: Platform): bool {.gcsafe, raises: [].}
  SizeImpl* = proc(self: Platform): Vec2 {.gcsafe, raises: [].}
  InitImpl* = proc(self: Platform, options: AppOptions) {.raises: [].}
  DeinitImpl* = proc(self: Platform) {.raises: [].}
  ProcessEventsImpl* = proc(self: Platform): int {.gcsafe, raises: [].}
  FontSizeSetImpl* = proc(self: Platform, fontSize: float) {.gcsafe, raises: [].}
  LineDistanceSetImpl* = proc(self: Platform, lineDistance: float) {.gcsafe, raises: [].}
  SetFontImpl* = proc(self: Platform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) {.gcsafe, raises: [].}
  GetFontInfoImpl* = proc(self: Platform, fontSize: float, flags: UINodeFlags): ptr FontInfo {.gcsafe, raises: [].}
  FontSizeImpl* = proc(self: Platform): float {.gcsafe, raises: [].}
  LineDistanceImpl* = proc(self: Platform): float {.gcsafe, raises: [].}
  LineHeightImpl* = proc(self: Platform): float {.gcsafe, raises: [].}
  CharWidthImpl* = proc(self: Platform): float {.gcsafe, raises: [].}
  CharGapImpl* = proc(self: Platform): float {.gcsafe, raises: [].}
  MeasureTextImpl* = proc(self: Platform, text: string): Vec2 {.gcsafe, raises: [].}
  PreventDefaultImpl* = proc(self: Platform) {.gcsafe, raises: [].}
  GetStatisticsStringImpl* = proc(self: Platform): string {.gcsafe, raises: [].}
  LayoutTextImpl* = proc(self: Platform, text: string): seq[Rect] {.gcsafe, raises: [].}
  SetVsyncImpl* = proc(self: Platform, enabled: bool) {.gcsafe, raises: [].}
  MoveToMonitorImpl* = proc(self: Platform, index: int) {.gcsafe, raises: [].}
  CreateTextureImpl* = proc(self: Platform, image: Image): TextureId {.gcsafe, raises: [].}
  FocusWindowImpl* = proc(self: Platform) {.gcsafe, raises: [].}

  WLayoutOptions* = object
    getTextBounds*: proc(text: string, fontSizeIncreasePercent: float = 0): Vec2
  Platform* = ref object of RootObj
    builder*: UINodeBuilder
    redrawEverything*: bool
    requestedRender*: bool
    showDrawnNodes*: bool = false
    supportsThinCursor*: bool
    focused*: bool
    deltaTime*: float
    eventCounter*: int
    onResize*: Event[void]
    onKeyPress*: Event[tuple[input: int64, modifiers: Modifiers]]
    onKeyRelease*: Event[tuple[input: int64, modifiers: Modifiers]]
    onRune*: Event[tuple[input: int64, modifiers: Modifiers]]
    onModifiersChanged*: Event[tuple[old: Modifiers, new: Modifiers]]
    onMousePress*: Event[tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]]
    onMouseRelease*: Event[tuple[button: MouseButton, modifiers: Modifiers, pos: Vec2]]
    onMouseMove*: Event[tuple[pos: Vec2, delta: Vec2, modifiers: Modifiers, buttons: set[MouseButton]]]
    onScroll*: Event[tuple[pos: Vec2, scroll: Vec2, modifiers: Modifiers]]
    onCloseRequested*: Event[void]
    onDropFile*: Event[tuple[path: string, content: string]]
    onFocusChanged*: Event[bool]
    onPreRender*: Event[Platform]
    layoutOptions*: WLayoutOptions
    logNextFrameTime*: bool
    lastEventTime*: Timer
    vfs*: VFS
    backend*: Backend
    currentModifiers*: Modifiers

  DynamicPlatform* = ref object of Platform
    requestRenderImpl*: RequestRenderImpl
    renderImpl*: RenderImpl
    sizeChangedImpl*: SizeChangedImpl
    sizeImpl*: SizeImpl
    initImpl*: InitImpl
    deinitImpl*: DeinitImpl
    processEventsImpl*: ProcessEventsImpl
    fontSizeSetImpl*: FontSizeSetImpl
    lineDistanceSetImpl*: LineDistanceSetImpl
    setFontImpl*: SetFontImpl
    getFontInfoImpl*: GetFontInfoImpl
    fontSizeImpl*: FontSizeImpl
    lineDistanceImpl*: LineDistanceImpl
    lineHeightImpl*: LineHeightImpl
    charWidthImpl*: CharWidthImpl
    charGapImpl*: CharGapImpl
    measureTextImpl*: MeasureTextImpl
    preventDefaultImpl*: PreventDefaultImpl
    getStatisticsStringImpl*: GetStatisticsStringImpl
    layoutTextImpl*: LayoutTextImpl
    setVsyncImpl*: SetVsyncImpl
    moveToMonitorImpl*: MoveToMonitorImpl
    createTextureImpl*: CreateTextureImpl
    focusWindowImpl*: FocusWindowImpl

method requestRender*(self: Platform, redrawEverything = false) {.base, gcsafe, raises: [].} = discard
method render*(self: Platform, rerender: bool) {.base, gcsafe, raises: [].} = discard
method sizeChanged*(self: Platform): bool {.base, gcsafe, raises: [].} = discard
method size*(self: Platform): Vec2 {.base, gcsafe, raises: [].} = discard
method init*(self: Platform, options: AppOptions) {.base, raises: [].} = discard
method deinit*(self: Platform) {.base, raises: [].} = discard
method processEvents*(self: Platform): int {.base, gcsafe, raises: [].} = discard
method `fontSize=`*(self: Platform, fontSize: float) {.base, gcsafe, raises: [].} = discard
method `lineDistance=`*(self: Platform, lineDistance: float) {.base, gcsafe, raises: [].} = discard
method setFont*(self: Platform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) {.base, gcsafe, raises: [].} = discard
method getFontInfo*(self: Platform, fontSize: float, flags: UINodeFlags): ptr FontInfo {.base, gcsafe, raises: [].} = discard
method fontSize*(self: Platform): float {.base, gcsafe, raises: [].} = discard
method lineDistance*(self: Platform): float {.base, gcsafe, raises: [].} = discard
method lineHeight*(self: Platform): float {.base, gcsafe, raises: [].} = discard
method charWidth*(self: Platform): float {.base, gcsafe, raises: [].} = discard
method charGap*(self: Platform): float {.base, gcsafe, raises: [].} = discard
method measureText*(self: Platform, text: string): Vec2 {.base, gcsafe, raises: [].} = discard
method preventDefault*(self: Platform) {.base, gcsafe, raises: [].} = discard
method getStatisticsString*(self: Platform): string {.base, gcsafe, raises: [].} = discard
method layoutText*(self: Platform, text: string): seq[Rect] {.base, gcsafe, raises: [].} = discard
method setVsync*(self: Platform, enabled: bool) {.base, gcsafe, raises: [].} = discard
method moveToMonitor*(self: Platform, index: int) {.base, gcsafe, raises: [].} = discard
method createTexture*(self: Platform, image: Image): TextureId {.base, gcsafe, raises: [].} = discard
method focusWindow*(self: Platform) {.base, gcsafe, raises: [].} = discard

method requestRender*(self: DynamicPlatform, redrawEverything = false) =
  if self.requestRenderImpl != nil:
    self.requestRenderImpl(self, redrawEverything)
  else:
    self.requestedRender = true
    self.redrawEverything = self.redrawEverything or redrawEverything

method render*(self: DynamicPlatform, rerender: bool) =
  if self.renderImpl != nil:
    self.renderImpl(self, rerender)

method sizeChanged*(self: DynamicPlatform): bool =
  if self.sizeChangedImpl != nil:
    return self.sizeChangedImpl(self)

method size*(self: DynamicPlatform): Vec2 =
  if self.sizeImpl != nil:
    return self.sizeImpl(self)

method init*(self: DynamicPlatform, options: AppOptions) =
  if self.initImpl != nil:
    self.initImpl(self, options)

method deinit*(self: DynamicPlatform) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

method processEvents*(self: DynamicPlatform): int =
  if self.processEventsImpl != nil:
    return self.processEventsImpl(self)

method `fontSize=`*(self: DynamicPlatform, fontSize: float) =
  if self.fontSizeSetImpl != nil:
    self.fontSizeSetImpl(self, fontSize)

method `lineDistance=`*(self: DynamicPlatform, lineDistance: float) =
  if self.lineDistanceSetImpl != nil:
    self.lineDistanceSetImpl(self, lineDistance)

method setFont*(self: DynamicPlatform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) =
  if self.setFontImpl != nil:
    self.setFontImpl(self, fontRegular, fontBold, fontItalic, fontBoldItalic, fallbackFonts)

method getFontInfo*(self: DynamicPlatform, fontSize: float, flags: UINodeFlags): ptr FontInfo =
  if self.getFontInfoImpl != nil:
    return self.getFontInfoImpl(self, fontSize, flags)

method fontSize*(self: DynamicPlatform): float =
  if self.fontSizeImpl != nil:
    return self.fontSizeImpl(self)

method lineDistance*(self: DynamicPlatform): float =
  if self.lineDistanceImpl != nil:
    return self.lineDistanceImpl(self)

method lineHeight*(self: DynamicPlatform): float =
  if self.lineHeightImpl != nil:
    return self.lineHeightImpl(self)

method charWidth*(self: DynamicPlatform): float =
  if self.charWidthImpl != nil:
    return self.charWidthImpl(self)

method charGap*(self: DynamicPlatform): float =
  if self.charGapImpl != nil:
    return self.charGapImpl(self)

method measureText*(self: DynamicPlatform, text: string): Vec2 =
  if self.measureTextImpl != nil:
    return self.measureTextImpl(self, text)

method preventDefault*(self: DynamicPlatform) =
  if self.preventDefaultImpl != nil:
    self.preventDefaultImpl(self)

method getStatisticsString*(self: DynamicPlatform): string =
  if self.getStatisticsStringImpl != nil:
    return self.getStatisticsStringImpl(self)

method layoutText*(self: DynamicPlatform, text: string): seq[Rect] =
  if self.layoutTextImpl != nil:
    return self.layoutTextImpl(self, text)

method setVsync*(self: DynamicPlatform, enabled: bool) =
  if self.setVsyncImpl != nil:
    self.setVsyncImpl(self, enabled)

method moveToMonitor*(self: DynamicPlatform, index: int) =
  if self.moveToMonitorImpl != nil:
    self.moveToMonitorImpl(self, index)

method createTexture*(self: DynamicPlatform, image: Image): TextureId =
  if self.createTextureImpl != nil:
    return self.createTextureImpl(self, image)

method focusWindow*(self: DynamicPlatform) =
  if self.focusWindowImpl != nil:
    self.focusWindowImpl(self)

var texturesToUpload: seq[tuple[id: TextureId, width: int, height: int, data: seq[chroma.ColorRGBX], dynamic: bool]]
var texturesToDelete: seq[TextureId]
var texturesLock*: Lock
texturesLock.initLock()

proc takeTexturesToUpload*(): seq[tuple[id: TextureId, width: int, height: int, data: seq[chroma.ColorRGBX], dynamic: bool]] =
  {.gcsafe.}:
    withLock(texturesLock):
      swap(result, texturesToUpload)

proc takeTexturesToDelete*(): seq[TextureId] =
  {.gcsafe.}:
    withLock(texturesLock):
      swap(result, texturesToDelete)

var reserveTextureImpl*: proc(): TextureId {.gcsafe, raises: [].}
proc createTexture*(width: int, height: int, data: sink seq[chroma.ColorRGBX], dynamic: bool = false): TextureId =
  {.gcsafe.}:
    withLock(texturesLock):
      if reserveTextureImpl == nil:
        return 0.TextureId
      let id = reserveTextureImpl()
      texturesToUpload.add((id, width, height, data, dynamic))
      return id

proc updateTexture*(id: TextureId, width: int, height: int, data: sink seq[chroma.ColorRGBX]) =
  {.gcsafe.}:
    withLock(texturesLock):
      texturesToUpload.add((id, width, height, data, true))

proc deleteTexture*(id: TextureId) =
  {.gcsafe.}:
    withLock(texturesLock):
      if reserveTextureImpl == nil:
        return
      texturesToDelete.add(id)

func totalLineHeight*(self: Platform): float = self.lineHeight + self.lineDistance

proc totalBounds*(bounds: openArray[Rect]): Vec2 {.raises: [].} =
  for i in 0 ..< bounds.len:
    let rect = bounds[i]
    result.x = max(result.x, rect.x + rect.w)
    result.y = max(result.y, rect.y + rect.h)

proc setMods*(self: Platform, newMods: Modifiers) =
  let oldMods = self.currentModifiers
  self.currentModifiers = newMods
  if oldMods != newMods:
    self.onModifiersChanged.invoke (oldMods, newMods)
