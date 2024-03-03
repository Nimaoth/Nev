import std/[tables, strutils, options, sets]
import chroma, vmath, pixie/[contexts, fonts]
import misc/[custom_logger, util, event, id, rect_utils]
import ui/node
import platform, platform/filesystem
import input, theme

export platform

logCategory "gui-platform"

type
  ExternCPlatform* = ref object of Platform
    ctx*: Context
    currentModifiers: Modifiers
    currentMouseButtons: set[MouseButton]
    eventCounter: int

    fontRegular: string
    fontBold*: string
    fontItalic*: string
    fontBoldItalic*: string

    mSize: Vec2
    lastSize: Vec2
    renderedSomethingLastFrame: bool

    lastFontSize: float
    mLineHeight: float
    mLineDistance: float = 2
    mCharWidth: float
    mCharGap: float

    typefaces: Table[string, Typeface]

    drawnNodes: seq[UINode]

    drawRect: DrawRectFn
    drawText: DrawTextFn
    pushClipRect: PushClipRectFn
    popClipRect: PopClipRectFn

  DrawRectFn* = proc(x, y, width, height, r, g, b, a: float32) {.cdecl.}
  DrawTextFn* = proc(x, y, r, g, b, a: float32, text: cstring) {.cdecl.}
  PushClipRectFn* = proc(x, y, width, height: float32) {.cdecl.}
  PopClipRectFn* = proc() {.cdecl.}

proc getFont*(self: ExternCPlatform, font: string, fontSize: float32): Font
proc getFont*(self: ExternCPlatform, fontSize: float32, style: set[FontStyle]): Font
proc getFont*(self: ExternCPlatform, fontSize: float32, flags: UINodeFlags): Font

method init*(self: ExternCPlatform) =
  self.supportsThinCursor = true

  self.builder = newNodeBuilder()
  self.builder.useInvalidation = true

  self.ctx = newContext(1, 1)
  self.ctx.fillStyle = rgb(255, 255, 255)
  self.ctx.strokeStyle = rgb(255, 255, 255)
  self.ctx.font = "fonts/DejaVuSansMono.ttf"
  self.ctx.textBaseline = TopBaseline

  self.fontRegular = "fonts/DejaVuSansMono.ttf"
  self.fontBold = "fonts/DejaVuSansMono-Bold.ttf"
  self.fontItalic = "fonts/DejaVuSansMono-Oblique.ttf"
  self.fontBoldItalic = "fonts/DejaVuSansMono-BoldOblique.ttf"

  # This sets the font size of self.ctx and recalculates the char width
  self.fontSize = 16

  self.layoutOptions.getTextBounds = proc(text: string, fontSizeIncreasePercent: float = 0): Vec2 =
    let font = self.getFont(self.ctx.font, self.ctx.fontSize * (1 + fontSizeIncreasePercent))
    if text.len == 0:
      let arrangement = font.typeset(" ")
      result = vec2(0, arrangement.layoutBounds().y)
    else:
      let arrangement = font.typeset(text)
      result = arrangement.layoutBounds()

method deinit*(self: ExternCPlatform) =
  discard

method requestRender*(self: ExternCPlatform, redrawEverything = false) =
  self.requestedRender = true
  self.redrawEverything = self.redrawEverything or redrawEverything

proc getFont*(self: ExternCPlatform, font: string, fontSize: float32): Font =
  if font == "":
    # todo
    discard

  if font notin self.typefaces:
    self.typefaces[font] = readTypeface(fs.getApplicationFilePath(font))

  result = newFont(self.typefaces.getOrDefault(font, nil))
  result.paint.color = color(1, 1, 1)
  result.size = fontSize

proc getFont*(self: ExternCPlatform, fontSize: float32, style: set[FontStyle]): Font =
  if Italic in style and Bold in style:
    return self.getFont(self.fontBoldItalic, fontSize)
  if Italic in style:
    return self.getFont(self.fontItalic, fontSize)
  if Bold in style:
    return self.getFont(self.fontBold, fontSize)
  return self.getFont(self.fontRegular, fontSize)

proc getFont*(self: ExternCPlatform, fontSize: float32, flags: UINodeFlags): Font =
  if TextItalic in flags and TextBold in flags:
    return self.getFont(self.fontBoldItalic, fontSize)
  if TextItalic in flags:
    return self.getFont(self.fontItalic, fontSize)
  if TextBold in flags:
    return self.getFont(self.fontBold, fontSize)
  return self.getFont(self.fontRegular, fontSize)

method size*(self: ExternCPlatform): Vec2 = self.mSize
proc `size=`*(self: ExternCPlatform, size: Vec2) = self.mSize = size

method sizeChanged*(self: ExternCPlatform): bool =
  let s = self.size
  return s.x != self.lastSize.x or s.y != self.lastSize.y

proc updateCharWidth*(self: ExternCPlatform) =
  let font = self.getFont(self.ctx.font, self.ctx.fontSize)
  let bounds = font.typeset(repeat("#", 100)).layoutBounds()
  let boundsSingle = font.typeset("#").layoutBounds()
  self.mCharWidth = bounds.x / 100
  self.mCharGap = (bounds.x / 100) - boundsSingle.x
  self.mLineHeight = bounds.y

  self.builder.charWidth = bounds.x / 100.0
  self.builder.lineHeight = bounds.y - 3
  self.builder.lineGap = self.mLineDistance

method `fontSize=`*(self: ExternCPlatform, fontSize: float) =
  self.ctx.fontSize = fontSize
  self.updateCharWidth()

method `lineDistance=`*(self: ExternCPlatform, lineDistance: float) = self.mLineDistance = lineDistance
method fontSize*(self: ExternCPlatform): float = self.ctx.fontSize
method lineDistance*(self: ExternCPlatform): float = self.mLineDistance
method lineHeight*(self: ExternCPlatform): float = self.mLineHeight
method charWidth*(self: ExternCPlatform): float = self.mCharWidth
method charGap*(self: ExternCPlatform): float = self.mCharGap

method measureText*(self: ExternCPlatform, text: string): Vec2 = self.getFont(self.ctx.font, self.ctx.fontSize).typeset(text).layoutBounds()

method processEvents*(self: ExternCPlatform): int =
  self.eventCounter = 0
  return self.eventCounter

proc drawNode(builder: UINodeBuilder, platform: ExternCPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false)

proc setRenderFunctions*(self: ExternCPlatform, drawRect: DrawRectFn, drawText: DrawTextFn, pushClipRect: PushClipRectFn, popClipRect: PopClipRectFn) =
  self.drawRect = drawRect
  self.drawText = drawText
  self.pushClipRect = pushClipRect
  self.popClipRect = popClipRect

method render*(self: ExternCPlatform) =
  # Clear the screen and begin a new frame.
  # debugf"render: font size: {self.ctx.fontSize}, char width: {self.mCharWidth}, line height: {self.mLineHeight}, line distance: {self.mLineDistance}"

  if self.drawRect.isNil:
    return

  if self.ctx.fontSize != self.lastFontSize:
    self.lastFontSize = self.ctx.fontSize

  self.redrawEverything = true

  self.drawnNodes.setLen 0

  var renderedSomething = true
  self.builder.drawNode(self, self.builder.root, force = self.redrawEverything)

  self.renderedSomethingLastFrame = renderedSomething;
  self.redrawEverything = false
  self.lastSize = self.size

proc drawNode(builder: UINodeBuilder, platform: ExternCPlatform, node: UINode, offset: Vec2 = vec2(0, 0), force: bool = false) =
  var nodePos = offset
  nodePos.x += node.boundsActual.x
  nodePos.y += node.boundsActual.y

  var force = force

  if builder.useInvalidation and not force and node.lastChange < builder.frameIndex:
    return

  node.lastRenderTime = builder.frameIndex

  # if node.flags.any &{UINodeFlag.FillBackground, DrawBorder, DrawText}:
  #   platform.drawnNodes.add node

  if node.flags.any &{UINodeFlag.FillBackground, DrawText}:
    force = true

  node.lx = nodePos.x
  node.ly = nodePos.y
  node.lw = node.boundsActual.w
  node.lh = node.boundsActual.h
  let bounds = rect(nodePos.x, nodePos.y, node.boundsActual.w, node.boundsActual.h)

  if FillBackground in node.flags:
    platform.drawRect(bounds.x, bounds.y, bounds.w, bounds.h, node.backgroundColor.r, node.backgroundColor.g, node.backgroundColor.b, node.backgroundColor.a)

  # Mask the rest of the rendering is this function to the contentBounds
  if MaskContent in node.flags:
    platform.pushClipRect(bounds.x, bounds.y, bounds.w, bounds.h)
  defer:
    if MaskContent in node.flags:
      platform.popClipRect()

  if DrawText in node.flags:
    # todo: flags
    platform.drawText(nodePos.x.floor, nodePos.y.floor, node.textColor.r, node.textColor.g, node.textColor.b, node.textColor.a, node.text.cstring)

  for _, c in node.children:
    builder.drawNode(platform, c, nodePos, force)

  # if DrawBorder in node.flags:
  #   platform.boxy.strokeRect(bounds, node.borderColor)