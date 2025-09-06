import std/[strformat, json, jsonutils, strutils, sequtils, sugar, os, terminal, colors, unicode]
import wit_guest, wit_types, wit_runtime, generational_seq, event, util
export wit_types, wit_runtime
import async
export async

# todo: remove this eventually
from "../../src/scripting_api.nim" as sca import nil

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

######### todo: move these to wit_types

proc `==`*(a, b: WitString): bool =
  if a.len != b.len:
    return false
  return a.toOpenArray() == b.toOpenArray()

############################ exported functions ############################

type CommandHandler = proc(data: uint32, args: WitString): WitString {.cdecl.}
type ChannelUpdateHandler = proc(data: uint32, closed: bool): ChannelListenResponse {.cdecl, raises: [].}
type MoveHandler = proc(data: uint32, text: sink Rope, selections: openArray[Selection], count: int, includeEol: bool): seq[Selection] {.cdecl, raises: [].}

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

proc handleMove(fun: uint32; data: uint32; text: uint32; selections: WitList[Selection]; count: int32; eol: bool): WitList[Selection] =
  var text = Rope(handle: text.int32 + 1)
  let fun = cast[MoveHandler](fun)
  return stackWitList(fun(data, text.ensureMove, selections.toOpenArray(), count.int, eol))

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

  proc getSetting*(editor: TextEditor, name: string, T: typedesc): T =
    try:
      return getSettingRaw(editor, name).parseJson().jsonTo(T)
    except:
      return T.default

  proc getSetting*[T](editor: TextEditor, name: string, def: T): T =
    try:
      return ($getSettingRaw(editor, ws(name))).parseJson().jsonTo(T)
    except:
      return def

  proc setSetting*[T](name: string, value: T) =
    try:
      setSettingRaw(name.ws, stackWitString($value.toJson))
    except:
      discard

  proc setSetting*[T](editor: TextEditor, name: string, value: T) =
    try:
      editor.setSettingRaw(name.ws, stackWitString($value.toJson))
    except:
      discard

  func `$`*(cursor: Cursor): string =
    return $cursor.line & ":" & $cursor.column

  func `$`*(selection: Selection): string =
    return $selection.first & "-" & $selection.last

  func `<`*(a: Cursor, b: Cursor): bool =
    ## Returns true if the cursor `a` comes before `b`
    if a.line < b.line:
      return true
    elif a.line == b.line and a.column < b.column:
      return true
    else:
      return false

  func `<=`*(a: Cursor, b: Cursor): bool =
    return a == b or a < b

  func min*(a: Cursor, b: Cursor): Cursor =
    if a < b:
      return a
    return b

  func max*(a: Cursor, b: Cursor): Cursor =
    if a >= b:
      return a
    return b

  func isBackwards*(selection: Selection): bool =
    ## Returns true if the first cursor of the selection is after the second cursor
    return selection.first > selection.last

  func normalized*(selection: Selection): Selection =
    ## Returns the normalized selection, i.e. where first < last.
    ## Switches first and last if backwards.
    if selection.isBackwards:
      return Selection(first: selection.last, last: selection.first)
    else:
      return selection

  func `in`*(a: Cursor, b: Selection): bool =
    ## Returns true if the cursor is contained within the selection
    let b = b.normalized
    return a >= b.first and a <= b.last

  func reverse*(selection: Selection): Selection = Selection(first: selection.last, last: selection.first)

  func isEmpty*(selection: Selection): bool = selection.first == selection.last
  func allEmpty*(selections: openArray[Selection]): bool = selections.allIt(it.isEmpty)

  func contains*(selection: Selection, cursor: Cursor): bool = (cursor >= selection.first and cursor <= selection.last)
  func contains*(selection: Selection, other: Selection): bool = (other.first >= selection.first and other.last <= selection.last)

  func contains*(self: openArray[Selection], cursor: Cursor): bool = self.`any` (s) => s.contains(cursor)
  func contains*(self: openArray[Selection], other: Selection): bool = self.`any` (s) => s.contains(other)

  func `or`*(a: Selection, b: Selection): Selection =
    let an = a.normalized
    let bn = b.normalized
    return Selection(first: min(an.first, bn.first), last: max(an.last, bn.last))

  converter toCursor*(c: (int, int)): Cursor = Cursor(line: c[0].int32, column: c[1].int32)
  converter toCursor*(c: (int32, int32)): Cursor = Cursor(line: c[0], column: c[1])
  converter toSelection*(c: tuple[line, column: int]): Selection = Selection(first: c.toCursor, last: c.toCursor)
  converter toSelection*(c: tuple[first, last: Cursor]): Selection = Selection(first: c.first, last: c.last)
  proc toSelection*(c: Cursor): Selection = Selection(first: c, last: c)

  proc defineCommand*(name: WitString; active: bool; docs: WitString; params: WitList[(WitString, WitString)]; returntype: WitString; context: WitString; data: uint32; handler: CommandHandler) =
    defineCommand(name, active, docs, params, returntype, context, cast[uint32](handler), cast[uint32](data))

  proc addModeChangedHandler*(fun: proc(old: WitString, new: WitString) {.cdecl.}) =
    discard addModeChangedHandler(cast[uint32](fun))

  proc selections*(editor: TextEditor): WitList[Selection] =
    return editor.getSelections()

  proc setSelections*(editor: TextEditor, s: openArray[Selection]) =
    editor.setSelections(@@s)

  proc lineCount*(editor: TextEditor): int =
    editor.content.lines.int

  proc setMode*(editor: TextEditor, mode: string) =
    editor.setMode(ws(mode), exclusive = true)

  proc applyMove*(editor: TextEditor, cursor: Cursor, move: string, count: int = 1, wrap: bool = true, includeEol: bool = true): Selection =
    return editor.applyMove(cursor.toSelection, move.ws, count, wrap, includeEol)[0]

  proc scrollToCursor*(editor: TextEditor) =
    editor.scrollToCursor(ScrollBehaviour.none)

  proc addCustomTextMove*(name: string, move: MoveHandler) =
    defineMove(name.ws, cast[uint32](move), 0)

func toSelection*(cursor: Cursor, default: Selection, which: sca.SelectionCursor): Selection =
  case which
  of sca.SelectionCursor.Config: return default
  of sca.SelectionCursor.Both: return (cursor, cursor).toSelection
  of sca.SelectionCursor.First: return (cursor, default.last).toSelection
  of sca.SelectionCursor.Last: return (default.first, cursor).toSelection
  of sca.SelectionCursor.LastToFirst: return (default.last, cursor).toSelection

proc charAt*(rope: Rope, cursor: Cursor): char = rope.byteAt(cursor).char
proc slice*(rope: Rope, a: Natural, b: Natural): Rope = rope.slice(a.int64, b.int64, inclusive = false)

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

    discard self.chan.flushRead()
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

type BackgroundTask* = ref object
  writer*: WriteChannel
  reader*: BufferedReadChannel

proc defaultThreadHandler*(): bool =
  let args = $getArguments()
  var nl = args.find("\n")
  if nl == -1:
    nl = args.len
  try:
    let funAddr = args[0..<nl].parseInt
    let fn = cast[proc(task: BackgroundTask): Future[void] {.nimcall.}](funAddr)
    let paths = args[min(args.len, nl + 1)..^1].split("\n")
    var reader = readChannelOpen(ws(paths[0]))
    var writer = writeChannelOpen(ws(paths[1]))
    if reader.isSome and writer.isSome:
      var task = BackgroundTask(writer: writer.take, reader: reader.take.buffered)
      discard fn(task)
  except CatchableError:
    return false

proc runInBackground*(executor: BackgroundExecutor, p: proc(task: BackgroundTask): Future[void] {.nimcall.}): BackgroundTask =
  var (reader1, writer1) = newInMemoryChannel()
  var (reader2, writer2) = newInMemoryChannel()

  result = BackgroundTask(writer: writer1.ensureMove, reader: reader2.buffered)

  let readerPath = reader1.readChannelMount(ws"reader", true)
  let writerPath = writer2.writeChannelMount(ws"writer", true)

  let args = &"{cast[int](p)}\n{readerPath}\n{writerPath}"
  spawnBackground(stackWitString(args), executor)

############################# logging ############################

type LogLevel* = enum lvlInfo, lvlNotice, lvlDebug, lvlWarn, lvlError

proc log*(level: LogLevel, str: string) =
  let color = case level
  of lvlDebug: rgb(100, 100, 200)
  of lvlInfo: rgb(200, 200, 200)
  of lvlNotice: rgb(200, 255, 255)
  of lvlWarn: rgb(200, 200, 100)
  of lvlError: rgb(255, 150, 150)
  # of lvlFatal: rgb(255, 0, 0)
  else: rgb(255, 255, 255)
  try:
    {.gcsafe.}:
      stdout.write(ansiForegroundColorCode(color))
      stdout.write("[vim] ")
      stdout.write(str)
      stdout.write("\r\n")
  except IOError:
    discard

template debugf*(x: static string) =
  log lvlDebug, fmt(x)
