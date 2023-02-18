when not defined(js):
  {.error: "scripting_js.nim does not work in non-js backend. Use scripting_nim.nim instead.".}

import std/[os, macros]
import fusion/matching
import util, custom_logger, scripting_base

export scripting_base

type ScriptContextJs* = ref object of ScriptContext
  discard

macro invoke*(self: ScriptContext; pName: untyped;
    args: varargs[typed]; returnType: typedesc = void): untyped =
  result = quote do:
    default(`returnType`)

