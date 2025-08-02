import std/[strformat, json, jsonutils]
import wit_guest

when defined(witRebuild):
  static: echo "Rebuilding plugin_api.wit"
  importWit "../../wit/v0":
    world = "plugin"
    cacheFile = "plugin_api_guest.nim"
else:
  static: echo "Using cached plugin_api.wit (plugin_api_guest.nim)"

include plugin_api_guest

proc emscripten_notify_memory_growth*(a: int32) {.exportc.} =
  echo "emscripten_notify_memory_growth"

proc emscripten_stack_init() {.importc.}

proc NimMain() {.importc.}

############################ exported functions ############################

proc initPlugin() =
  emscripten_stack_init()
  NimMain()

proc handleModeChanged(fun: uint32, old: WitString; new: WitString) =
  let fun = cast[proc(old: WitString, new: WitString) {.cdecl.}](fun)
  fun(old, new)

proc handleViewRenderCallback(id: int32; fun: uint32; data: uint32): void =
  let fun = cast[proc(id: int32, data: uint32) {.cdecl.}](fun)
  fun(id, data)

proc handleCommand(name: WitString; arg: WitString): WitString =
  echo "[guest] handleCommand ", name, ", ", arg
  return stackWitString ($name & "-" & $arg)

############################ nice wrappers around the raw api ############################

proc getSetting*(name: string, T: typedesc): T =
  try:
    return getSettingRaw(name).parseJson().jsonTo(T)
  except:
    return T.default

proc getSetting*[T](name: string, def: T): T =
  try:
    return ($getSettingRaw(ws(name))).parseJson().jsonTo(T)
  except:
    return def

proc addModeChangedHandler*(fun: proc(old: WitString, new: WitString) {.cdecl.}) =
  discard addModeChangedHandler(cast[uint32](fun))
