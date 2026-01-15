import std/[locks]
import vmath, chroma
import ui/node
import misc/[event, timer]
import input, vfs, app_options, scripting_api, pixie

export input, event

type
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
