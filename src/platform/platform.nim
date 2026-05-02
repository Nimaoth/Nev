import std/[locks, options]
import vmath, chroma
import ui/node
import misc/[event, timer, custom_async]
import nimsumtree/[arc]
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
  FocusWindowImpl* = proc(self: Platform) {.gcsafe, raises: [].}
  SetClipboardTextImpl* = proc(self: Platform, str: string) {.gcsafe, raises: [].}
  GetClipboardTextImpl* = proc(self: Platform): Future[Option[string]] {.gcsafe, async: (raises: []).}

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
    vfs*: Arc[VFS2]
    backend*: Backend
    currentModifiers*: Modifiers

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
    focusWindowImpl*: FocusWindowImpl
    setClipboardTextImpl*: SetClipboardTextImpl
    getClipboardTextImpl*: GetClipboardTextImpl

proc requestRender*(self: Platform, redrawEverything = false) =
  if self.requestRenderImpl != nil:
    self.requestRenderImpl(self, redrawEverything)
  else:
    self.requestedRender = true
    self.redrawEverything = self.redrawEverything or redrawEverything

proc render*(self: Platform, rerender: bool) =
  if self.renderImpl != nil:
    self.renderImpl(self, rerender)

proc sizeChanged*(self: Platform): bool =
  if self.sizeChangedImpl != nil:
    return self.sizeChangedImpl(self)

proc size*(self: Platform): Vec2 =
  if self.sizeImpl != nil:
    return self.sizeImpl(self)

proc init*(self: Platform, options: AppOptions) =
  if self.initImpl != nil:
    self.initImpl(self, options)

proc deinit*(self: Platform) =
  if self.deinitImpl != nil:
    self.deinitImpl(self)

proc processEvents*(self: Platform): int =
  if self.processEventsImpl != nil:
    return self.processEventsImpl(self)

proc `fontSize=`*(self: Platform, fontSize: float) =
  if self.fontSizeSetImpl != nil:
    self.fontSizeSetImpl(self, fontSize)

proc `lineDistance=`*(self: Platform, lineDistance: float) =
  if self.lineDistanceSetImpl != nil:
    self.lineDistanceSetImpl(self, lineDistance)

proc setFont*(self: Platform, fontRegular: string, fontBold: string, fontItalic: string, fontBoldItalic: string, fallbackFonts: seq[string]) =
  if self.setFontImpl != nil:
    self.setFontImpl(self, fontRegular, fontBold, fontItalic, fontBoldItalic, fallbackFonts)

proc getFontInfo*(self: Platform, fontSize: float, flags: UINodeFlags): ptr FontInfo =
  if self.getFontInfoImpl != nil:
    return self.getFontInfoImpl(self, fontSize, flags)

proc fontSize*(self: Platform): float =
  if self.fontSizeImpl != nil:
    return self.fontSizeImpl(self)

proc lineDistance*(self: Platform): float =
  if self.lineDistanceImpl != nil:
    return self.lineDistanceImpl(self)

proc lineHeight*(self: Platform): float =
  if self.lineHeightImpl != nil:
    return self.lineHeightImpl(self)

proc charWidth*(self: Platform): float =
  if self.charWidthImpl != nil:
    return self.charWidthImpl(self)

proc charGap*(self: Platform): float =
  if self.charGapImpl != nil:
    return self.charGapImpl(self)

proc measureText*(self: Platform, text: string): Vec2 =
  if self.measureTextImpl != nil:
    return self.measureTextImpl(self, text)

proc preventDefault*(self: Platform) =
  if self.preventDefaultImpl != nil:
    self.preventDefaultImpl(self)

proc getStatisticsString*(self: Platform): string =
  if self.getStatisticsStringImpl != nil:
    return self.getStatisticsStringImpl(self)

proc layoutText*(self: Platform, text: string): seq[Rect] =
  if self.layoutTextImpl != nil:
    return self.layoutTextImpl(self, text)

proc setVsync*(self: Platform, enabled: bool) =
  if self.setVsyncImpl != nil:
    self.setVsyncImpl(self, enabled)

proc moveToMonitor*(self: Platform, index: int) =
  if self.moveToMonitorImpl != nil:
    self.moveToMonitorImpl(self, index)

proc focusWindow*(self: Platform) =
  if self.focusWindowImpl != nil:
    self.focusWindowImpl(self)

proc setClipboardText*(self: Platform, str: string) =
  if self.setClipboardTextImpl != nil:
    self.setClipboardTextImpl(self, str)

proc getClipboardText*(self: Platform): Future[Option[string]] {.async.} =
  if self.getClipboardTextImpl != nil:
    return self.getClipboardTextImpl(self).await
  return string.none

include dynlib_export

var texturesToUpload {.apprtlvar.}: seq[tuple[id: TextureId, width: int, height: int, data: seq[chroma.ColorRGBX], dynamic: bool]]
var texturesToDelete {.apprtlvar.}: seq[TextureId]
var texturesLock* {.apprtlvar.}: Lock
var reserveTextureImpl* {.apprtlvar.}: proc(): TextureId {.gcsafe, raises: [].}

when implModule:
  texturesLock.initLock()

proc takeTexturesToUpload*(): seq[tuple[id: TextureId, width: int, height: int, data: seq[chroma.ColorRGBX], dynamic: bool]] =
  {.gcsafe.}:
    withLock(texturesLock):
      swap(result, texturesToUpload)

proc takeTexturesToDelete*(): seq[TextureId] =
  {.gcsafe.}:
    withLock(texturesLock):
      swap(result, texturesToDelete)

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

proc totalLineHeight*(self: Platform): float = self.lineHeight + self.lineDistance

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
