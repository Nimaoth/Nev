import std/[tables]
import boxy, pixie/[contexts, fonts]

type RenderContext* = ref object
  boxy*: Boxy
  ctx*: Context
  typefaces: Table[string, Typeface]
  lineHeight*: float32
  charWidth*: float32

proc getFont*(ctx: RenderContext, font: string, fontSize: float32): Font =
  if font == "":
    raise newException(PixieError, "No font has been set on this Context")

  if font notin ctx.typefaces:
    ctx.typefaces[font] = readTypeface(font)

  result = newFont(ctx.typefaces.getOrDefault(font, nil))
  result.paint.color = color(1, 1, 1)
  result.size = fontSize

