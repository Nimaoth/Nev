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
      # text*: string #
      textOffset*: uint32
      textLen*: uint32
    else:
      discard

  RenderCommandArrangement = object
    linesRange: Slice[int]
    spansRange: Slice[int]
    fontsRange: Slice[int]
    runesRange: Slice[int]
    positionsRange: Slice[int]
    selectionRectsRange: Slice[int]

  RenderCommands* = object
    strings*: string
    arrangement*: Arrangement
    arrangements*: seq[RenderCommandArrangement]
    commands*: seq[RenderCommand]
    spacesColor*: Color

proc typeset*(self: var RenderCommands, font: Font, text: string, bounds = vec2(0, 0), hAlign = LeftAlign, vAlign = TopAlign, wrap = true, snapToPixel = true,
    ): RenderCommandArrangement =
  result.linesRange.a = self.arrangement.lines.len
  result.spansRange.a = self.arrangement.spans.len
  result.fontsRange.a = self.arrangement.fonts.len
  result.runesRange.a = self.arrangement.runes.len
  result.positionsRange.a = self.arrangement.positions.len
  result.selectionRectsRange.a = self.arrangement.selectionRects.len
  typeset(self.arrangement, [newSpan(text, font)], bounds, hAlign, vAlign, wrap, snapToPixel)
  result.linesRange.b = self.arrangement.lines.high
  result.spansRange.b = self.arrangement.spans.high
  result.fontsRange.b = self.arrangement.fonts.high
  result.runesRange.b = self.arrangement.runes.high
  result.positionsRange.b = self.arrangement.positions.high
  result.selectionRectsRange.b = self.arrangement.selectionRects.high

proc clear*(self: var RenderCommands) =
  self.strings.setLen(0)
  self.commands.setLen(0)

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
      renderCommands.commands.add(RenderCommand(kind: RenderCommandKind.Text, textOffset: offset, textLen: len, bounds: inBounds, color: inColor, flags: inFlags))
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
