import std/[strformat, json, jsonutils, strutils, sequtils]
import wit_guest, wit_types, wit_runtime, generational_seq, event
export wit_types, wit_runtime
import async
export async

const pluginWorld {.strdefine.} = "plugin"

when defined(witRebuild):
  static: echo "Rebuilding plugin_api.wit"
  importWit "../../wit/v0":
    world = pluginWorld
    cacheFile = pluginWorld.replace("-", "_") & "_api_guest.nim"
else:
  static: echo "Using cached plugin_api.wit (plugin_api_guest.nim)"

macro includePluginApi() =
  let path = ident(pluginWorld.replace("-", "_") & "_api_guest")
  return quote do:
    include `path`

includePluginApi()

proc emscripten_notify_memory_growth*(a: int32) {.exportc.} =
  echo "emscripten_notify_memory_growth"

proc emscripten_stack_init() {.importc.}

proc NimMain() {.importc.}

############################ exported functions ############################

type CommandHandler = proc(data: uint32, args: WitString): WitString {.cdecl.}
type ChannelUpdateHandler = proc(data: uint32, closed: bool): ChannelListenResponse {.cdecl, raises: [].}

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

proc handleChannelUpdate(fun: uint32, data: uint32, closed: bool): ChannelListenResponse =
  let fun = cast[ChannelUpdateHandler](fun)
  fun(data, closed)

type TaskId = distinct uint64
type TaskWrapper = object
  done: proc() {.raises: [].}

var tasks: GenerationalSeq[TaskWrapper, TaskId]

proc notifyTaskComplete(task: uint64, canceled: bool) =
  let id = task.TaskId
  let task = tasks.tryGet(id)
  if task.isSome:
    task.get.done()
    tasks.del(id)

proc notifyTasksComplete(tasks: WitList[tuple[task: uint64, canceled: bool]]) =
  for (task, canceled) in tasks:
    notifyTaskComplete(task, canceled)

############################ nice wrappers around the raw api ############################

proc wl*[T](): WitList[T] = WitList[T].default()

when pluginWorld == "plugin":
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
  proc cb(data: uint32, closed: bool): ChannelListenResponse {.cdecl.} =
    let data = cast[ptr Data](data)
    result = data.fun()
    if closed or result == Stop:
      `=destroy`(data[])
      `=wasMoved`(data[])
      freeShared(data)

  # todo: this needs to get freed at some point
  var data = cast[ptr Data](allocShared0(sizeof(Data)))
  data[].fun = fun
  self.listen(cast[uint32](data), cb)

proc ready*(self: ReadChannel, num: int32 = 1): Future[void] =
  var fut = newFuture[void]("ready")
  let id = tasks.add(TaskWrapper())
  if self.waitRead(id.uint64, num.int32):
    tasks.del(id)
    fut.complete()
  else:
    proc done() {.raises: [].} =
      fut.complete()
    tasks.set(id, TaskWrapper(done: done))
  return fut

proc read*(self: ReadChannel, num: int32): Future[string] =
  var fut = newFuture[string]("read")
  let id = tasks.add(TaskWrapper())
  if self.waitRead(id.uint64, num):
    tasks.del(id)
    fut.complete($self.readString(num))
  else:
    proc done() {.raises: [].} =
      fut.complete($self.readString(num))
    tasks.set(id, TaskWrapper(done: done))
  return fut

type BufferedReadChannel* = ref object
  chan*: ReadChannel
  buffer: string

proc buffered*(self: sink ReadChannel): BufferedReadChannel = BufferedReadChannel(chan: self.ensureMove)

proc atEnd*(self: BufferedReadChannel): bool = self.buffer.len == 0 and self.chan.atEnd

proc readLine*(self: BufferedReadChannel): Future[string] {.async.} =
  while true:
    let nl = self.buffer.find("\n")
    if nl != -1:
      result = self.buffer[0..<nl]
      self.buffer = self.buffer[(nl + 1)..^1] # todo: make this more efficient
      return

    if self.chan.atEnd:
      result = self.buffer
      self.buffer.setLen(0)
      return

    await self.chan.ready()
    let str = self.chan.readAllString()
    if str.len > 0:
      let prevLen = self.buffer.len
      self.buffer.setLen(prevLen + str.len)
      copyMem(self.buffer[prevLen].addr, str.data[0].addr, str.len)

proc readAvailableString*(self: BufferedReadChannel): string =
  result = self.buffer
  self.buffer.setLen(0)
  result.add $self.chan.readAllString()

proc readAllString*(self: BufferedReadChannel): Future[string] {.async.} =
  result = self.buffer
  self.buffer.setLen(0)
  while self.chan.canRead:
    await self.chan.ready(int32.high)
  result.add $self.chan.readAllString()

proc readString*(self: BufferedReadChannel, len: int): Future[string] {.async.} =
  if self.buffer.len < len:
    await self.chan.ready(len - self.buffer.len)
    self.buffer.add $self.chan.readAllString()

  let len = min(self.buffer.len, len)
  result = self.buffer[0..<len]
  self.buffer = self.buffer[len..^1]
