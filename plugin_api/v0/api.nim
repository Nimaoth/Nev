import std/[strformat, json, jsonutils]
import wit_guest, wit_types, wit_runtime
export wit_types, wit_runtime

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

type CommandHandler = proc(data: uint32, args: WitString): WitString {.cdecl.}
type ChannelUpdateHandler = proc(data: uint32): ChannelListenResponse {.cdecl, raises: [].}

proc initPlugin() =
  emscripten_stack_init()
  NimMain()

proc handleModeChanged(fun: uint32, old: WitString; new: WitString) =
  let fun = cast[proc(old: WitString, new: WitString) {.cdecl.}](fun)
  fun(old, new)

proc handleViewRenderCallback(id: int32; fun: uint32; data: uint32): void =
  let fun = cast[proc(id: int32, data: uint32) {.cdecl.}](fun)
  fun(id, data)

proc handleCommand(fun: uint32, data: uint32; arguments: WitString): WitString =
  let fun = cast[CommandHandler](fun)
  return fun(data, arguments)

proc handleChannelUpdate(fun: uint32, data: uint32): ChannelListenResponse =
  let fun = cast[ChannelUpdateHandler](fun)
  fun(data)

############################ nice wrappers around the raw api ############################

proc wl*[T](): WitList[T] = WitList[T].default()

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

proc toSelection*(c: Cursor): Selection = Selection(first: c, last: c)

proc defineCommand*(name: WitString; active: bool; docs: WitString; params: WitList[(WitString, WitString)]; returntype: WitString; context: WitString; data: uint32; handler: CommandHandler) =
  defineCommand(name, active, docs, params, returntype, context, cast[uint32](handler), cast[uint32](data))

proc addModeChangedHandler*(fun: proc(old: WitString, new: WitString) {.cdecl.}) =
  discard addModeChangedHandler(cast[uint32](fun))

proc asEditor*(editor: TextEditor): Editor = Editor(id: editor.id)
proc asDocument*(document: TextDocument): Document = Document(id: document.id)

proc listen*(self: ReadChannel, data: uint32, fun: ChannelUpdateHandler) =
  self.listen(cast[uint32](fun), data)

proc listen*(self: ReadChannel, fun: proc(): ChannelListenResponse {.raises: [].}) =
  type Data = object
    fun: proc(): ChannelListenResponse {.raises: [].}
  proc cb(data: uint32): ChannelListenResponse {.cdecl.} =
    let data = cast[ptr Data](data)
    data.fun()

  # todo: this needs to get freed at some point
  var data = cast[ptr Data](allocShared0(sizeof(Data)))
  data[].fun = fun
  self.listen(cast[uint32](data), cb)
