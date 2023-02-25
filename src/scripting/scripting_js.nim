when not defined(js):
  {.error: "scripting_js.nim does not work in non-js backend. Use scripting_nim.nim instead.".}

import std/[macros, os, macrocache, strutils]
import custom_logger, scripting_base, expose, compilation_config, platform/filesystem

export scripting_base

type ScriptContextJs* = ref object of ScriptContext
  discard

macro invoke*(self: ScriptContext; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

proc loadScriptJs(url: cstring) {.importjs: "loadScript(#)".}

method init*(self: ScriptContextJs, path: string) =
  # loadScriptJs("config.js")
  # debugf"load script from {path}"
  # loadScriptJs(path.cstring)

  const configFilePath = "config.js"

  let config = fs.loadApplicationFile(configFilePath)

  proc evalJs(str: cstring) {.importjs("eval(#)").}
  proc confirmJs(msg: cstring): bool {.importjs("confirm(#)").}
  proc hasLocalStorage(key: cstring): bool {.importjs("(window.localStorage.getItem(#) !== null)").}
  let contentStrict = "\"use strict\";\n" & config
  echo contentStrict

  let allowEval = not hasLocalStorage(configFilePath) or confirmJs("You are about to eval() some javascript (config.js). Look in the console to see what's in there.")

  if allowEval:
    evalJs(contentStrict.cstring)
  else:
    logger.log(lvlWarn, fmt"Did not load config file because user declined.")

method reload*(self: ScriptContextJs) = discard
