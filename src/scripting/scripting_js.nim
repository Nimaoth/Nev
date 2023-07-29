when not defined(js):
  {.error: "scripting_js.nim does not work in non-js backend. Use scripting_nim.nim instead.".}

import std/[macros, dom, json]
import custom_logger, custom_async, scripting_base, popup, document_editor
import platform/filesystem

export scripting_base

type ScriptContextJs* = ref object of ScriptContext
  discard

macro invoke*(self: ScriptContext; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

proc loadScriptJs(url: cstring): Future[Element] {.importjs: "jsLoadScript(#)".}
proc loadScriptContentJs(content: cstring): Future[Element] {.importjs: "jsLoadScriptContent(#)".}
# proc evalJs(str: cstring) {.importjs("eval(#)").}
proc confirmJs(msg: cstring): bool {.importjs("confirm(#)").}
proc hasLocalStorage(key: cstring): bool {.importjs("(window.localStorage.getItem(#) !== null)").}

proc initAsync(self: ScriptContextJs): Future[void] {.async.} =
  discard await loadScriptJs("./scripting_runtime.js")

  const configFilePath = "./config/absytree_config.js"
  if hasLocalStorage(configFilePath):
    let config = fs.loadApplicationFile(configFilePath)

    let contentStrict = "\"use strict\";\n" & config
    echo contentStrict

    let allowEval = confirmJs("You are about to eval() some javascript (./config/absytree_config.js). Look in the console to see what's in there.")

    if allowEval:
      # evalJs(contentStrict.cstring)
      discard await loadScriptContentJs(config.cstring)
    else:
      log(lvlWarn, fmt"Did not load config file because user declined.")
  else:
    discard await loadScriptJs("./config/absytree_config.js")

method init*(self: ScriptContextJs, path: string): Future[void] =
  return self.initAsync()

method reload*(self: ScriptContextJs) = discard

method handleUnknownPopupAction*(self: ScriptContextJs, popup: Popup, action: string, arg: JsonNode): bool =
  let action = action.cstring
  let arg = ($arg).cstring
  {.emit: ["return window.handleUnknownPopupAction ? window.handleUnknownPopupAction(", popup, ", ", action, ",  JSON.parse(", arg, ")) : false;"].}

method handleUnknownDocumentEditorAction*(self: ScriptContextJs, editor: DocumentEditor, action: string, arg: JsonNode): bool =
  let action = action.cstring
  let arg = ($arg).cstring
  {.emit: ["return window.handleUnknownDocumentEditorAction ? window.handleUnknownDocumentEditorAction(", editor, ", ", action, ", JSON.parse(", arg, ")) : false;"].}

method handleGlobalAction*(self: ScriptContextJs, action: string, arg: JsonNode): bool =
  let action = action.cstring
  let arg = ($arg).cstring
  {.emit: ["return window.handleGlobalAction ? window.handleGlobalAction(", action, ", JSON.parse(", arg, ")) : false;"].}

method postInitialize*(self: ScriptContextJs): bool =
  {.emit: ["return window.postInitialize ? window.postInitialize() : false;"].}

method handleCallback*(self: ScriptContextJs, id: int, arg: JsonNode): bool =
  let arg = ($arg).cstring
  {.emit: ["return window.handleCallback ? window.handleCallback(", id, ", JSON.parse(", arg, ")) : false;"].}