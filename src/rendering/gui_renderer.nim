import std/[os, strutils, strformat]
import renderer, widgets
import ../custom_logger, ../rect_utils
import vmath

export renderer, widgets

type
  GuiRenderer* = ref object of Renderer
    discard

method init*(self: GuiRenderer) =
  discard

method deinit*(self: GuiRenderer) =
  discard

method size*(self: GuiRenderer): Vec2 = discard

