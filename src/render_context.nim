import std/[tables]
import boxy, windy, pixie/[contexts, fonts], lrucache, chroma

type RenderContext* = ref object
  window*: Window
  boxy*: Boxy
  boxy2*: Boxy
  ctx*: Context
  typefaces: Table[string, Typeface]
  lineHeight*: float32
  charWidth*: float32
  cachedImages*: LruCache[string, string]

proc newRenderContext*(window: Window): RenderContext =
  new result
  result.cachedImages = newLruCache[string, string](1000, true)
  result.boxy = newBoxy()
  result.boxy2 = newBoxy()
  result.ctx = newContext(1, 1)
  result.ctx.fillStyle = rgb(255, 255, 255)
  result.ctx.strokeStyle = rgb(255, 255, 255)
  result.ctx.font = "fonts/DejaVuSansMono.ttf"
  result.ctx.fontSize = 20
  result.ctx.textBaseline = TopBaseline
  result.window = window

proc getFont*(ctx: RenderContext, font: string, fontSize: float32): Font =
  if font == "":
    raise newException(PixieError, "No font has been set on this Context")

  if font notin ctx.typefaces:
    ctx.typefaces[font] = readTypeface(font)

  result = newFont(ctx.typefaces.getOrDefault(font, nil))
  result.paint.color = color(1, 1, 1)
  result.size = fontSize

proc cleanupImages*(self: RenderContext) =
  for image in self.cachedImages.removedKeys:
    self.boxy.removeImage(image)
  self.cachedImages.clearRemovedKeys()