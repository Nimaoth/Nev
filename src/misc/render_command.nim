import std/[macros, genasts, tables, sets, hashes]
import fusion/matching
import chroma, vmath
import macro_utils, util, custom_unicode, rect_utils, binary_encoder

export util, chroma, vmath, rect_utils

defineBitFlagSized(uint64):
  type UINodeFlag* = enum
    SizeToContentX = 0
    SizeToContentY
    FillX
    FillY
    DrawBorder
    DrawBorderTerminal
    FlushBorders
    FillBackground
    LogLayout
    AllowAlpha
    MaskContent
    DrawText
    TextMultiLine
    TextItalic
    TextBold
    TextWrap
    TextUndercurl
    TextAlignHorizontalLeft
    TextAlignHorizontalCenter
    TextAlignHorizontalRight
    TextAlignVerticalTop
    TextAlignVerticalCenter
    TextAlignVerticalBottom
    TextDrawSpaces
    LayoutVertical
    LayoutVerticalReverse
    LayoutHorizontal
    LayoutHorizontalReverse
    OverlappingChildren
    MouseHover
    AnimateBounds
    AnimatePosition
    AnimateSize
    SnapInitialBounds
    AutoPivotChildren
    IgnoreBoundsForSizeToContent
    CursorBlock
    CursorBar
    CursorUnderline
    CursorBlinking
    DrawChildrenReverse

type
  RenderCommandKind* {.pure.} = enum
    Rect
    FilledRect
    Image
    Text
    TextRaw
    ScissorStart
    ScissorEnd
    TransformStart
    TransformEnd

  TextureId* = distinct uint64

  RenderCommand* = object
    bounds*: Rect # 16
    color*: Color # 16
    flags*: UINodeFlags # 8
    underlineColor*: Color
    fontScale*: float32 = 1.0
    case kind*: RenderCommandKind # 1
    of RenderCommandKind.Text:
      textOffset*: uint32
      textLen*: uint32
      arrangementIndex*: uint32 = uint32.high
    of RenderCommandKind.TextRaw:
      data*: ptr UncheckedArray[char]
      len*: int
    of RenderCommandKind.Image:
      textureId*: TextureId
      uv0*: Vec2
      uv1*: Vec2
    else:
      discard

  Arrangement* = object
    runes*: seq[Rune]          ## The positions of the glyphs for each rune.
    positions*: seq[Vec2]      ## The positions of the glyphs for each rune.
    selectionRects*: seq[Rect] ## The selection rects for each glyph.

  RenderCommandArrangement* = object
    lines*: Slice[int]
    spans*: Slice[int]
    fonts*: Slice[int]
    runes*: Slice[int]
    positions*: Slice[int]
    selectionRects*: Slice[int]

  RenderCommands* = object
    strings*: string
    arrangement*: Arrangement
    arrangements*: seq[RenderCommandArrangement]
    commands*: seq[RenderCommand]
    spacesColor*: Color
    space*: Rune = ' '.Rune
    raw*: seq[byte]

  FontInfo* = object
    advance*: proc(r: Rune): float {.gcsafe, raises: [].}
    kerningAdjustment*: proc(left: Rune, right: Rune): float {.gcsafe, raises: [].}
    ascent*: float
    lineHeight*: float
    lineGap*: float
    scale*: float

proc `==`*(a, b: TextureId): bool {.borrow.}
proc hash*(vr: TextureId): Hash {.borrow.}
proc `$`*(vr: TextureId): string {.borrow.}

proc write*(self: var BinaryEncoder, flags: UINodeFlags) =
  self.writeLEB128(uint64, flags.uint64)

proc read*(self: var BinaryDecoder, _: typedesc[UINodeFlags]): UINodeFlags =
  return self.readLEB128(uint64).UINodeFlags

proc write*(self: var BinaryEncoder, textureId: TextureId) =
  self.writeLEB128(uint64, textureId.uint64)

proc read*(self: var BinaryDecoder, _: typedesc[TextureId]): TextureId =
  return self.readLEB128(uint64).TextureId

proc write*(self: var BinaryEncoder, bounds: Rect) =
  self.write(bounds.x)
  self.write(bounds.y)
  self.write(bounds.w)
  self.write(bounds.h)

proc read*(self: var BinaryDecoder, _: typedesc[Rect]): Rect =
  return rect(self.read(float32), self.read(float32), self.read(float32), self.read(float32))

proc write*(self: var BinaryEncoder, vec: Vec2) =
  self.write(vec.x)
  self.write(vec.y)

proc read*(self: var BinaryDecoder, _: typedesc[Vec2]): Vec2 =
  return vec2(self.read(float32), self.read(float32))

proc write*(self: var BinaryEncoder, color: Color) =
  self.write(color.r)
  self.write(color.g)
  self.write(color.b)
  self.write(color.a)

proc read*(self: var BinaryDecoder, _: typedesc[Color]): Color =
  return color(self.read(float32), self.read(float32), self.read(float32), self.read(float32))

proc write*(self: var BinaryEncoder, command: RenderCommand) =
  self.write(command.kind.uint8 + 1.uint8)
  case command.kind
  of RenderCommandKind.Rect:
    self.write(command.bounds)
    self.write(command.color)
    self.write(command.flags)
  of RenderCommandKind.FilledRect:
    self.write(command.bounds)
    self.write(command.color)
    self.write(command.flags)
  of RenderCommandKind.Image:
    self.write(command.bounds)
    self.write(command.uv0)
    self.write(command.uv1)
    self.write(command.color)
    self.write(command.textureId)
    self.write(command.flags)
  of RenderCommandKind.TextRaw:
    self.write(command.bounds)
    self.write(command.color)
    self.write(command.flags)
    self.write(command.data.toOpenArray(0, command.len - 1))
  of RenderCommandKind.Text:
    # todo
    self.write(command.bounds)
  of RenderCommandKind.ScissorStart:
    self.write(command.bounds)
  of RenderCommandKind.ScissorEnd:
    discard
  of RenderCommandKind.TransformStart:
    self.write(command.bounds.xy)
  of RenderCommandKind.TransformEnd:
    discard

iterator decodeRenderCommands*(self: var BinaryDecoder): RenderCommand =
  while self.pos < self.len:
    let tag = self.read(uint8)
    if tag == 0 or (tag - 1) notin RenderCommandKind.low.uint8..RenderCommandKind.high.uint8:
      continue
    case (tag - 1).RenderCommandKind
    of RenderCommandKind.Rect:
      let bounds = self.read(Rect)
      let color = self.read(Color)
      let flags = self.read(UINodeFlags)
      yield RenderCommand(kind: RenderCommandKind.Rect, bounds: bounds, color: color, flags: flags)
    of RenderCommandKind.FilledRect:
      let bounds = self.read(Rect)
      let color = self.read(Color)
      let flags = self.read(UINodeFlags)
      yield RenderCommand(kind: RenderCommandKind.FilledRect, bounds: bounds, color: color, flags: flags)
    of RenderCommandKind.Image:
      let bounds = self.read(Rect)
      let uv0 = self.read(Vec2)
      let uv1 = self.read(Vec2)
      let color = self.read(Color)
      let textureId = self.read(TextureId)
      let flags = self.read(UINodeFlags)
      yield RenderCommand(kind: RenderCommandKind.Image, bounds: bounds, color: color, flags: flags, textureId: textureId, uv0: uv0, uv1: uv1)
    of RenderCommandKind.TextRaw:
      let bounds = self.read(Rect)
      let color = self.read(Color)
      let flags = self.read(UINodeFlags)
      let (data, len) = self.readArray(char)
      yield RenderCommand(kind: RenderCommandKind.TextRaw, bounds: bounds, color: color, flags: flags, data: data, len: len)
    of RenderCommandKind.Text:
      # todo
      discard
    of RenderCommandKind.ScissorStart:
      let bounds = self.read(Rect)
      yield RenderCommand(kind: RenderCommandKind.ScissorStart, bounds: bounds)
    of RenderCommandKind.ScissorEnd:
      yield RenderCommand(kind: RenderCommandKind.ScissorEnd)
    of RenderCommandKind.TransformStart:
      let offset = self.read(Vec2)
      yield RenderCommand(kind: RenderCommandKind.TransformStart, bounds: rect(offset, vec2(0, 0)))
    of RenderCommandKind.TransformEnd:
      yield RenderCommand(kind: RenderCommandKind.TransformEnd)

  # yield RenderCommand(kind: TextRaw, data: nil, len: 0)

iterator decodeRenderCommands*(self: RenderCommands): RenderCommand =
  var decoder = BinaryDecoder.init(self.raw.toOpenArray(0, self.raw.high))
  for c in decoder.decodeRenderCommands():
    yield c

proc typeset*(arrangement: var Arrangement, text: openArray[char], font: ptr FontInfo) {.raises: [].} =
  ## Lays out the character glyphs and returns the arrangement.
  ## Optional parameters:

  let initialY = round((font.ascent + font.lineGap / 2) * font.scale)
  var at: Vec2 = vec2(0, initialY)
  var lastRune = 0.Rune
  for rune in text.runes:
    if rune.uint32 < ' '.uint32:
      continue

    if not font.kerningAdjustment.isNil and lastRune != 0.Rune:
      let kerning = font.kerningAdjustment(lastRune, rune)
      arrangement.selectionRects.last.w += kerning * font.scale
      at.x += kerning * font.scale

    let advance = font.advance(rune) * font.scale
    arrangement.runes.add rune
    arrangement.positions.add at
    arrangement.selectionRects.add rect(at.x, 0, advance, font.lineHeight)
    at.x += advance

    lastRune = rune

proc typeset*(self: var RenderCommands, text: openArray[char], font: ptr FontInfo): int =
  var a: RenderCommandArrangement
  a.runes.a = self.arrangement.runes.len
  a.positions.a = self.arrangement.positions.len
  a.selectionRects.a = self.arrangement.selectionRects.len
  typeset(self.arrangement, text, font)
  a.runes.b = self.arrangement.runes.high
  a.positions.b = self.arrangement.positions.high
  a.selectionRects.b = self.arrangement.selectionRects.high
  self.arrangements.add(a)
  return self.arrangements.high

proc layoutBounds*(self: var RenderCommands, arrangementIndex: int): Vec2 {.raises: [].} =
  ## Computes the width and height of the arrangement in pixels.
  if self.arrangement.runes.len > 0:
    let indices {.cursor.} = self.arrangements[arrangementIndex]
    for i in indices.runes:
      if self.arrangement.runes[i] != '\n'.Rune:
        # Don't add width of a new line rune.
        let rect = self.arrangement.selectionRects[i]
        result.x = max(result.x, rect.x + rect.w)
    let finalRect = self.arrangement.selectionRects[^1]
    result.y = finalRect.y + finalRect.h
    if self.arrangement.runes[indices.runes.b] == '\n'.Rune:
      # If the text ends with a new line, we need add another line height.
      result.y += finalRect.h

proc clear*(self: var RenderCommands) =
  self.strings.setLen(0)
  self.commands.setLen(0)
  self.arrangements.setLen(0)
  self.arrangement.runes.setLen(0)
  self.arrangement.positions.setLen(0)
  self.arrangement.selectionRects.setLen(0)
  self.raw.setLen(0)

proc drawRect*(self: var BinaryEncoder, inBounds: Rect, inColor: Color) =
  self.write(RenderCommandKind.Rect.uint8 + 1.uint8)
  self.write(inBounds)
  self.write(inColor)
  self.write(0.UINodeFlags)
proc fillRect*(self: var BinaryEncoder, inBounds: Rect, inColor: Color) =
  self.write(RenderCommandKind.FilledRect.uint8 + 1.uint8)
  self.write(inBounds)
  self.write(inColor)
  self.write(0.UINodeFlags)
proc fillRect*(self: var BinaryEncoder, inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
  self.write(RenderCommandKind.FilledRect.uint8 + 1.uint8)
  self.write(inBounds)
  self.write(inColor)
  self.write(inFlags)
proc drawText*(self: var BinaryEncoder, inText: string, inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
  let txt = inText
  self.write(RenderCommandKind.TextRaw.uint8 + 1.uint8)
  self.write(inBounds)
  self.write(inColor)
  self.write(inFlags)
  self.write(txt.toOpenArray(0, txt.high))
proc drawText*(self: var BinaryEncoder, inText: openArray[char], inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
  self.write(RenderCommandKind.TextRaw.uint8 + 1.uint8)
  self.write(inBounds)
  self.write(inColor)
  self.write(inFlags)
  self.write(inText)
# proc drawText*(self: var BinaryEncoder, inText: openArray[char], inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
#   let offset = renderCommands.strings.len.uint32
#   for c in inText:
#     renderCommands.strings.add c
#   let len = renderCommands.strings.len.uint32 - offset
#   renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: uint32.high))
# proc drawText*(self: var BinaryEncoder, inText: openArray[char], arrangementIndex: int, inBounds: Rect, inColor: Color, inFlags: UINodeFlags, inUnderlineColor: Color) =
#   let offset = renderCommands.strings.len.uint32
#   for c in inText:
#     renderCommands.strings.add c
#   let len = renderCommands.strings.len.uint32 - offset
#   renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: arrangementIndex.uint32, underlineColor: inUnderlineColor))
proc startScissor*(self: var BinaryEncoder, inBounds: Rect) =
  self.write(RenderCommandKind.ScissorStart.uint8 + 1.uint8)
  self.write(inBounds)
proc endScissor*(self: var BinaryEncoder) =
  self.write(RenderCommandKind.ScissorEnd.uint8 + 1.uint8)
proc startTransform*(self: var BinaryEncoder, offset: Vec2) =
  self.write(RenderCommandKind.TransformStart.uint8 + 1.uint8)
  self.write(offset)
proc endTransform*(self: var BinaryEncoder) =
  self.write(RenderCommandKind.TransformEnd.uint8 + 1.uint8)
proc drawImage*(self: var BinaryEncoder, inBounds: Rect, inTextureId: TextureId) =
  self.write(RenderCommandKind.Image.uint8 + 1)
  self.write(inBounds)
  self.write(vec2(0, 0))
  self.write(vec2(1, 1))
  self.write(color(1, 1, 1))
  self.write(inTextureId)
  self.write(0.UINodeFlags)
proc drawImage*(self: var BinaryEncoder, inBounds: Rect, inUV0: Vec2, inUV1: Vec2, inTextureId: TextureId) =
  self.write(RenderCommandKind.Image.uint8 + 1)
  self.write(inBounds)
  self.write(inUV0)
  self.write(inUV1)
  self.write(color(1, 1, 1))
  self.write(inTextureId)
  self.write(0.UINodeFlags)

proc drawRect*(renderCommands: var RenderCommands, inBounds: Rect, inColor: Color) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Rect, bounds: inBounds, color: inColor))
proc fillRect*(renderCommands: var RenderCommands, inBounds: Rect, inColor: Color) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: inBounds, color: inColor))
proc fillRect*(renderCommands: var RenderCommands, inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: inBounds, color: inColor, flags: inFlags))
proc drawImage*(renderCommands: var RenderCommands, inBounds: Rect, inTextureId: TextureId) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Image, bounds: inBounds, color: color(1, 1, 1), textureId: inTextureId, uv1: vec2(1, 1)))
proc drawImage*(renderCommands: var RenderCommands, inBounds: Rect, inUV0: Vec2, inUV1: Vec2, inTextureId: TextureId) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Image, bounds: inBounds, color: color(1, 1, 1), textureId: inTextureId, uv0: inUV0, uv1: inUV1))
proc drawText*(renderCommands: var RenderCommands, inText: string, inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
  let txt = inText
  let offset = renderCommands.strings.len.uint32
  renderCommands.strings.add txt
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: txt.len.uint32, bounds: inBounds, color: inColor, underlineColor: inColor, flags: inFlags))
proc drawText*(renderCommands: var RenderCommands, inText: openArray[char], inBounds: Rect, inColor: Color, inFlags: UINodeFlags) =
  let offset = renderCommands.strings.len.uint32
  for c in inText:
    renderCommands.strings.add c
  let len = renderCommands.strings.len.uint32 - offset
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: uint32.high))
proc drawText*(renderCommands: var RenderCommands, inText: openArray[char], arrangementIndex: int, inBounds: Rect, inColor: Color, inFlags: UINodeFlags, inUnderlineColor: Color) =
  let offset = renderCommands.strings.len.uint32
  for c in inText:
    renderCommands.strings.add c
  let len = renderCommands.strings.len.uint32 - offset
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: arrangementIndex.uint32, underlineColor: inUnderlineColor))
proc startScissor*(renderCommands: var RenderCommands, inBounds: Rect) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.ScissorStart, bounds: inBounds))
proc endScissor*(renderCommands: var RenderCommands) =
  renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.ScissorEnd))

proc startTransform*(self: var RenderCommands, offset: Vec2) =
  self.commands.add(RenderCommand(kind: RenderCommandKind.TransformStart, bounds: rect(offset, vec2(0, 0))))
proc endTransform*(self: var RenderCommands) =
  self.commands.add(RenderCommand(kind: RenderCommandKind.TransformEnd))

template buildCommands*(renderCommands: var RenderCommands, body: untyped) =
  block:
    template drawRect(inBounds: Rect, inColor: Color): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Rect, bounds: inBounds, color: inColor))
    template fillRect(inBounds: Rect, inColor: Color): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: inBounds, color: inColor))
    template fillRect(inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: inBounds, color: inColor, flags: inFlags))
    template drawImage(inBounds: Rect, inTextureId: TextureId): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Image, bounds: inBounds, color: color(1, 1, 1), textureId: inTextureId, uv1: vec2(1, 1)))
    template drawImage(inBounds: Rect, inUV0: Vec2, inUV1: Vec2, inTextureId: TextureId): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Image, bounds: inBounds, color: color(1, 1, 1), textureId: inTextureId, uv0: inUV0, uv1: inUV1))
    template drawText(inText: openArray[char], inBounds: Rect, inColor: Color, inFlags: UINodeFlags, inFontScale: float = 1.0): untyped {.used.} =
      let offset = renderCommands.strings.len.uint32
      for c in inText:
        renderCommands.strings.add c
      let len = renderCommands.strings.len.uint32 - offset
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: uint32.high, fontScale: inFontScale))
    template drawText(inText: openArray[char], arrangementIndex: int, inBounds: Rect, inColor: Color, inFlags: UINodeFlags, inUnderlineColor: Color, inFontScale: float): untyped {.used.} =
      let offset = renderCommands.strings.len.uint32
      for c in inText:
        renderCommands.strings.add c
      let len = renderCommands.strings.len.uint32 - offset
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: arrangementIndex.uint32, underlineColor: inUnderlineColor, fontScale: inFontScale))
    template startScissor(inBounds: Rect): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.ScissorStart, bounds: inBounds))
    template endScissor(): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.ScissorEnd))

    body

template buildCommands*(self: var BinaryEncoder, body: untyped) =
  block:
    template drawRect(inBounds: Rect, inColor: Color): untyped {.used.} =
      self.write(RenderCommandKind.Rect.uint8 + 1.uint8)
      self.write(inBounds)
      self.write(inColor)
      self.write(0.UINodeFlags)
    template fillRect(inBounds: Rect, inColor: Color): untyped {.used.} =
      self.write(RenderCommandKind.FilledRect.uint8 + 1.uint8)
      self.write(inBounds)
      self.write(inColor)
      self.write(0.UINodeFlags)
    template fillRect(inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      self.write(RenderCommandKind.FilledRect.uint8 + 1.uint8)
      self.write(inBounds)
      self.write(inColor)
      self.write(inFlags)
    template drawText(inText: string, inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      let txt = inText
      self.write(RenderCommandKind.TextRaw.uint8 + 1.uint8)
      self.write(inBounds)
      self.write(inColor)
      self.write(inFlags)
      self.write(txt.toOpenArray(0, txt.high))
    template drawText(inText: openArray[char], inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      self.write(RenderCommandKind.TextRaw.uint8 + 1.uint8)
      self.write(inBounds)
      self.write(inColor)
      self.write(inFlags)
      self.write(inText)
    template startScissor(inBounds: Rect): untyped {.used.} =
      self.write(RenderCommandKind.ScissorStart.uint8 + 1.uint8)
      self.write(inBounds)
    template endScissor(): untyped {.used.} =
      self.write(RenderCommandKind.ScissorEnd.uint8 + 1.uint8)

    body

template buildCommands*(body: untyped): RenderCommands =
  block:
    var commands = RenderCommands()
    buildCommands(commands, body)
    commands
