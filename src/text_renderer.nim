import boxy, pixie/fonts, vmath
import compiler, id
import lrucache

const textExtraHeight* = 10.0

proc computeRenderedTextImpl2*(ctx: compiler.Context, input: RenderTextInput): string =
  if ctx.queryCacheRenderedText.contains(input):
    let oldImageId = ctx.queryCacheRenderedText[input]
    input.renderCtx.boxy.removeImage(oldImageId)

  let font = input.renderCtx.getFont(input.font, input.fontSize)
  let arrangement = font.typeset(input.text, bounds=input.bounds)
  var bounds = arrangement.layoutBounds()
  if bounds.x == 0:
    bounds.x = 1
  if bounds.y == 0:
    bounds.y = input.lineHeight
  bounds.y += textExtraHeight

  var image = newImage(bounds.x.int, bounds.y.int)
  image.fillText(arrangement)

  let imageId = if input.imageId.len > 0: input.imageId else: $newId()
  input.renderCtx.boxy.addImage(imageId, image, false)
  return imageId
