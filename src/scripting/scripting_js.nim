when not defined(js):
  {.error: "scripting_js.nim does not work in non-js backend. Use scripting_nim.nim instead.".}

import std/[macros, os, macrocache, strutils]
import custom_logger, scripting_base, expose, compilation_config

export scripting_base

type ScriptContextJs* = ref object of ScriptContext
  discard

macro invoke*(self: ScriptContext; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

proc loadScriptJs(url: cstring) {.importjs: "loadScript(#)".}

method init*(self: ScriptContextJs, path: string) =
  loadScriptJs("config.js")
  # debugf"load script from {path}"
  # loadScriptJs(path.cstring)

method reload*(self: ScriptContextJs) = discard
