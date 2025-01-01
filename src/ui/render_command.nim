import std/[os, macros, genasts, strutils, sequtils, sugar, strformat, options, tables, sets]
import fusion/matching
import chroma, vmath
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

  RenderCommands* = object
    strings*: string
    commands*: seq[RenderCommand]

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
