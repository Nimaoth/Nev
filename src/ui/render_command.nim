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

  RenderCommand* = object
    bounds*: Rect
    color*: Color
    flags*: UINodeFlags
    case kind*: RenderCommandKind
    of RenderCommandKind.Text:
      text*: string
    else:
      discard

template buildCommands*(body: untyped): seq[RenderCommand] =
  block:
    var commands = newSeq[RenderCommand]()
    template drawRect(inBounds: Rect, inColor: Color): untyped =
      commands.add(RenderCommand(kind: RenderCommandKind.Rect, bounds: inBounds, color: inColor))
    template fillRect(inBounds: Rect, inColor: Color): untyped =
      commands.add(RenderCommand(kind: RenderCommandKind.FilledRect, bounds: inBounds, color: inColor))
    template drawText(inText: string, inBounds: Rect, inColor: Color, inFlags: UINodeFlags): untyped =
      commands.add(RenderCommand(kind: RenderCommandKind.Text, text: inText, bounds: inBounds, color: inColor, flags: inFlags))
    body
    commands
