import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, tables, sets]
import fusion/matching
import chroma, vmath, pixie/fonts
import misc/[macro_utils, util, id, custom_unicode, array_set, rect_utils, custom_logger]
import input

export util, id, input, chroma, vmath, rect_utils

defineBitFlagSized(uint64):
  type UINodeFlag* = enum
    SizeToContentX = 0
    SizeToContentY
    FillX
    FillY
    DrawBorder
    FillBackground
    LogLayout
    AllowAlpha
    MaskContent
    DrawText
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

type
  RenderCommandKind* {.pure.} = enum
    Rect
    FilledRect
    Text
    ScissorStart
    ScissorEnd

  RenderCommand* = object
    bounds*: Rect # 16
    color*: Color # 16
    flags*: UINodeFlags # 8
    case kind*: RenderCommandKind # 1
    of RenderCommandKind.Text:
      textOffset*: uint32
      textLen*: uint32
      arrangementIndex*: uint32 = uint32.high
    else:
      discard

  RenderCommandArrangement = object
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

proc typeset*(self: var RenderCommands, font: Font, text: string, bounds = vec2(0, 0), hAlign = LeftAlign, vAlign = TopAlign, wrap = true): int =
  if self.arrangement.isNil:
    self.arrangement = Arrangement()
  var a: RenderCommandArrangement
  a.lines.a = self.arrangement.lines.len
  a.spans.a = self.arrangement.spans.len
  a.fonts.a = self.arrangement.fonts.len
  a.runes.a = self.arrangement.runes.len
  a.positions.a = self.arrangement.positions.len
  a.selectionRects.a = self.arrangement.selectionRects.len
  typeset(self.arrangement, [newSpan(text, font)], bounds, hAlign, vAlign, wrap, snapToPixel = false)
  a.lines.b = self.arrangement.lines.high
  a.spans.b = self.arrangement.spans.high
  a.fonts.b = self.arrangement.fonts.high
  a.runes.b = self.arrangement.runes.high
  a.positions.b = self.arrangement.positions.high
  a.selectionRects.b = self.arrangement.selectionRects.high
  self.arrangements.add(a)
  return self.arrangements.high

proc layoutBounds*(self: var RenderCommands, arrangementIndex: int): Vec2 {.raises: [].} =
  ## Computes the width and height of the arrangement in pixels.
  if self.arrangement.isNil:
    return
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
  if self.arrangement != nil:
    self.arrangement.lines.setLen(0)
    self.arrangement.spans.setLen(0)
    self.arrangement.fonts.setLen(0)
    self.arrangement.runes.setLen(0)
    self.arrangement.positions.setLen(0)
    self.arrangement.selectionRects.setLen(0)

template buildCommands*(renderCommands: var RenderCommands, body: untyped) =
  block:
    template drawRect(inBounds: Rect, inColor: Color): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Rect, bounds: inBounds, color: inColor))
    template fillRect(inBounds: Rect, inColor: Color): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: inBounds, color: inColor))
    template drawText(inText: string, inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      let txt = inText
      let offset = renderCommands.strings.len.uint32
      renderCommands.strings.add txt
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: txt.len.uint32, bounds: inBounds, color: inColor, flags: inFlags))
    template drawText(inText: openArray[char], inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      let offset = renderCommands.strings.len.uint32
      for c in inText:
        renderCommands.strings.add c
      let len = renderCommands.strings.len.uint32 - offset
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: uint32.high))
    template drawText(inText: openArray[char], arrangementIndex: int, inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped {.used.} =
      let offset = renderCommands.strings.len.uint32
      for c in inText:
        renderCommands.strings.add c
      let len = renderCommands.strings.len.uint32 - offset
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags, arrangementIndex: arrangementIndex.uint32))
    template startScissor(inBounds: Rect): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.ScissorStart, bounds: inBounds))
    template endScissor(): untyped {.used.} =
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.ScissorEnd))

    body

template buildCommands*(body: untyped): RenderCommands =
  block:
    var commands = RenderCommands()
    buildCommands(commands, body)
    commands
