when not defined(js):
  {.error: "scripting_js.nim does not work in non-js backend. Use scripting_nim.nim instead.".}

import std/[macros, os, macrocache, strutils, dom]
import custom_logger, custom_async, scripting_base, expose, compilation_config, platform/filesystem

export scripting_base

type ScriptContextJs* = ref object of ScriptContext
  discard

macro invoke*(self: ScriptContext; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

proc loadScriptJs(url: cstring): Future[Element] {.importjs: "loadScript(#)".}
proc loadScriptContentJs(content: cstring): Future[Element] {.importjs: "loadScriptContent(#)".}
proc evalJs(str: cstring) {.importjs("eval(#)").}
proc confirmJs(msg: cstring): bool {.importjs("confirm(#)").}
proc hasLocalStorage(key: cstring): bool {.importjs("(window.localStorage.getItem(#) !== null)").}

proc initAsync(self: ScriptContextJs): Future[void] {.async.} =
  discard await loadScriptJs("scripting_runtime.js")

  const configFilePath = "config.js"
  if hasLocalStorage(configFilePath):
    let config = fs.loadApplicationFile(configFilePath)

    let contentStrict = "\"use strict\";\n" & config
    echo contentStrict

    let allowEval = confirmJs("You are about to eval() some javascript (config.js). Look in the console to see what's in there.")

    if allowEval:
      # evalJs(contentStrict.cstring)
      discard await loadScriptContentJs(config.cstring)
    else:
      logger.log(lvlWarn, fmt"Did not load config file because user declined.")
  else:
    discard await loadScriptJs("config.js")

method init*(self: ScriptContextJs, path: string) =
  asyncCheck self.initAsync()

method reload*(self: ScriptContextJs) = discard
