
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wasmtime

{.pop.}
type
  ## Represents a cursor in a text editor. Line and column are both zero based.
  ## The column is in bytes.
  Cursor* = object
    line*: int32
    column*: int32
  ## The column of 'last' is exclusive.
  Selection* = object
    first*: Cursor
    last*: Cursor
  Vec2f* = object
    x*: float32
    y*: float32
  Rect* = object
    pos*: Vec2f
    size*: Vec2f
  ## Shared reference to a rope. The rope data is stored in the editor, not in the plugin, so ropes
  ## can be used to efficiently access any document content or share a string with another plugin.
  ## Ropes are reference counted internally, and this resource also affects that reference count.
  ## Non-owning handle to an editor.
  Editor* = object
    id*: uint64
  ## Non-owning handle to a text editor.
  TextEditor* = object
    id*: uint64
  ## Non-owning handle to a document.
  Document* = object
    id*: uint64
  ## Non-owning handle to a text document.
  TextDocument* = object
    id*: uint64
  Task* = object
    id*: uint64
  ChannelListenResponse* = enum
    Continue = "continue", Stop = "stop"
  ## Represents the read end of a channel. All APIs are non-blocking.
  ## Represents the write end of a channel. All APIs are non-blocking.
  ## Resource which represents a running process started by a plugin.
  ## Shared handle for a view.
  View* = object
    id*: int32
  ## Shared handle to a custom render view
  CommandError* = enum
    NotAllowed = "not-allowed", NotFound = "not-found"
  Platform* = enum
    Gui = "gui", Tui = "tui"
  VfsError* = enum
    NotAllowed = "not-allowed", NotFound = "not-found"
  ReadFlag* = enum
    Binary = "binary"
  ReadFlags* = set[ReadFlag]
when not declared(RopeResource):
  {.error: "Missing resource type definition for " & "RopeResource" &
      ". Define the type before the importWit statement.".}
when not declared(ReadChannelResource):
  {.error: "Missing resource type definition for " & "ReadChannelResource" &
      ". Define the type before the importWit statement.".}
when not declared(WriteChannelResource):
  {.error: "Missing resource type definition for " & "WriteChannelResource" &
      ". Define the type before the importWit statement.".}
when not declared(ProcessResource):
  {.error: "Missing resource type definition for " & "ProcessResource" &
      ". Define the type before the importWit statement.".}
when not declared(RenderViewResource):
  {.error: "Missing resource type definition for " & "RenderViewResource" &
      ". Define the type before the importWit statement.".}
type
  ExportedFuncs* = object
    mContext*: ptr ContextT
    mMemory*: Option[ExternT]
    mRealloc*: Option[ExternT]
    mDealloc*: Option[ExternT]
    mStackAlloc*: Option[ExternT]
    mStackSave*: Option[ExternT]
    mStackRestore*: Option[ExternT]
    initPlugin*: FuncT
    handleCommand*: FuncT
    handleModeChanged*: FuncT
    handleViewRenderCallback*: FuncT
    handleChannelUpdate*: FuncT
    notifyTaskComplete*: FuncT
proc mem(funcs: ExportedFuncs): WasmMemory =
  if funcs.mMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
    return initWasmMemory(funcs.mMemory.get.of_field.sharedmemory)
  elif funcs.mMemory.get.kind == WASMTIME_EXTERN_MEMORY:
    return initWasmMemory(funcs.mContext, funcs.mMemory.get.of_field.memory.addr)

proc collectExports*(funcs: var ExportedFuncs; instance: InstanceT;
                     context: ptr ContextT) =
  funcs.mContext = context
  funcs.mMemory = instance.getExport(context, "memory")
  funcs.mRealloc = instance.getExport(context, "cabi_realloc")
  funcs.mDealloc = instance.getExport(context, "cabi_dealloc")
  funcs.mStackAlloc = instance.getExport(context, "mem_stack_alloc")
  funcs.mStackSave = instance.getExport(context, "mem_stack_save")
  funcs.mStackRestore = instance.getExport(context, "mem_stack_restore")
  let f_8237614692 = instance.getExport(context, "init_plugin")
  if f_8237614692.isSome:
    assert f_8237614692.get.kind == WASMTIME_EXTERN_FUNC
    funcs.initPlugin = f_8237614692.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "init_plugin", "\'"
  let f_8237614708 = instance.getExport(context, "handle_command")
  if f_8237614708.isSome:
    assert f_8237614708.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleCommand = f_8237614708.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_command", "\'"
  let f_8237614758 = instance.getExport(context, "handle_mode_changed")
  if f_8237614758.isSome:
    assert f_8237614758.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleModeChanged = f_8237614758.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_mode_changed", "\'"
  let f_8237614759 = instance.getExport(context, "handle_view_render_callback")
  if f_8237614759.isSome:
    assert f_8237614759.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleViewRenderCallback = f_8237614759.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_view_render_callback",
         "\'"
  let f_8237614783 = instance.getExport(context, "handle_channel_update")
  if f_8237614783.isSome:
    assert f_8237614783.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleChannelUpdate = f_8237614783.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_channel_update", "\'"
  let f_8237614784 = instance.getExport(context, "notify_task_complete")
  if f_8237614784.isSome:
    assert f_8237614784.get.kind == WASMTIME_EXTERN_FUNC
    funcs.notifyTaskComplete = f_8237614784.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "notify_task_complete", "\'"

proc initPlugin*(funcs: ExportedFuncs): WasmtimeResult[void] =
  var args: array[max(1, 0), ValT]
  var results: array[max(1, 0), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  let res = funcs.initPlugin.addr.call(funcs.mContext,
                                       args.toOpenArray(0, 0 - 1),
                                       results.toOpenArray(0, 0 - 1), trap.addr).toResult(
      void)
  if trap != nil:
    return trap.toResult(void)
  if res.isErr:
    return res.toResult(void)
  
proc handleCommand*(funcs: ExportedFuncs; fun: uint32; data: uint32;
                    arguments: string): WasmtimeResult[string] =
  var args: array[max(1, 4), ValT]
  var results: array[max(1, 1), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  var dataPtrWasm0: WasmPtr
  args[0] = toWasmVal(fun)
  args[1] = toWasmVal(data)
  if arguments.len > 0:
    dataPtrWasm0 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (arguments.len * 1).int32, 4)
      if temp.isErr:
        return temp.toResult(string)
      temp.val
    args[2] = toWasmVal(cast[int32](dataPtrWasm0))
    block:
      for i0 in 0 ..< arguments.len:
        memory[dataPtrWasm0 + i0] = cast[uint8](arguments[i0])
  else:
    args[2] = toWasmVal(0.int32)
  args[3] = toWasmVal(cast[int32](arguments.len))
  let res = funcs.handleCommand.addr.call(funcs.mContext,
      args.toOpenArray(0, 4 - 1), results.toOpenArray(0, 1 - 1), trap.addr).toResult(
      string)
  if trap != nil:
    return trap.toResult(string)
  if res.isErr:
    return res.toResult(string)
  var retVal: string
  let retArea: ptr UncheckedArray[uint8] = memory.getRawPtr(
      results[0].to(WasmPtr))
  block:
    let p0 = cast[ptr UncheckedArray[char]](memory.getRawPtr(
        cast[ptr int32](retArea[0].addr)[].WasmPtr))
    retVal = newString(cast[ptr int32](retArea[4].addr)[])
    for i0 in 0 ..< retVal.len:
      retVal[i0] = p0[i0]
  return wasmtime.ok(retVal)

proc handleModeChanged*(funcs: ExportedFuncs; fun: uint32; old: string;
                        new: string): WasmtimeResult[void] =
  var args: array[max(1, 5), ValT]
  var results: array[max(1, 0), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  var dataPtrWasm0: WasmPtr
  var dataPtrWasm1: WasmPtr
  args[0] = toWasmVal(fun)
  if old.len > 0:
    dataPtrWasm0 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (old.len * 1).int32, 4)
      if temp.isErr:
        return temp.toResult(void)
      temp.val
    args[1] = toWasmVal(cast[int32](dataPtrWasm0))
    block:
      for i0 in 0 ..< old.len:
        memory[dataPtrWasm0 + i0] = cast[uint8](old[i0])
  else:
    args[1] = toWasmVal(0.int32)
  args[2] = toWasmVal(cast[int32](old.len))
  if new.len > 0:
    dataPtrWasm1 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (new.len * 1).int32, 4)
      if temp.isErr:
        return temp.toResult(void)
      temp.val
    args[3] = toWasmVal(cast[int32](dataPtrWasm1))
    block:
      for i0 in 0 ..< new.len:
        memory[dataPtrWasm1 + i0] = cast[uint8](new[i0])
  else:
    args[3] = toWasmVal(0.int32)
  args[4] = toWasmVal(cast[int32](new.len))
  let res = funcs.handleModeChanged.addr.call(funcs.mContext,
      args.toOpenArray(0, 5 - 1), results.toOpenArray(0, 0 - 1), trap.addr).toResult(
      void)
  if trap != nil:
    return trap.toResult(void)
  if res.isErr:
    return res.toResult(void)
  
proc handleViewRenderCallback*(funcs: ExportedFuncs; id: int32; fun: uint32;
                               data: uint32): WasmtimeResult[void] =
  var args: array[max(1, 3), ValT]
  var results: array[max(1, 0), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  args[0] = toWasmVal(id)
  args[1] = toWasmVal(fun)
  args[2] = toWasmVal(data)
  let res = funcs.handleViewRenderCallback.addr.call(funcs.mContext,
      args.toOpenArray(0, 3 - 1), results.toOpenArray(0, 0 - 1), trap.addr).toResult(
      void)
  if trap != nil:
    return trap.toResult(void)
  if res.isErr:
    return res.toResult(void)
  
proc handleChannelUpdate*(funcs: ExportedFuncs; fun: uint32; data: uint32;
                          closed: bool): WasmtimeResult[ChannelListenResponse] =
  var args: array[max(1, 3), ValT]
  var results: array[max(1, 1), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  args[0] = toWasmVal(fun)
  args[1] = toWasmVal(data)
  args[2] = toWasmVal(closed)
  let res = funcs.handleChannelUpdate.addr.call(funcs.mContext,
      args.toOpenArray(0, 3 - 1), results.toOpenArray(0, 1 - 1), trap.addr).toResult(
      ChannelListenResponse)
  if trap != nil:
    return trap.toResult(ChannelListenResponse)
  if res.isErr:
    return res.toResult(ChannelListenResponse)
  var retVal: ChannelListenResponse
  retVal = cast[ChannelListenResponse](results[0].to(int8))
  return wasmtime.ok(retVal)

proc notifyTaskComplete*(funcs: ExportedFuncs; task: uint64; canceled: bool): WasmtimeResult[
    void] =
  var args: array[max(1, 2), ValT]
  var results: array[max(1, 0), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  args[0] = toWasmVal(task)
  args[1] = toWasmVal(canceled)
  let res = funcs.notifyTaskComplete.addr.call(funcs.mContext,
      args.toOpenArray(0, 2 - 1), results.toOpenArray(0, 0 - 1), trap.addr).toResult(
      void)
  if trap != nil:
    return trap.toResult(void)
  if res.isErr:
    return res.toResult(void)
  
proc typesNewRope(host: HostContext; store: ptr ContextT; content: sink string): RopeResource
proc typesClone(host: HostContext; store: ptr ContextT; self: var RopeResource): RopeResource
proc typesBytes(host: HostContext; store: ptr ContextT; self: var RopeResource): int64
proc typesRunes(host: HostContext; store: ptr ContextT; self: var RopeResource): int64
proc typesLines(host: HostContext; store: ptr ContextT; self: var RopeResource): int64
proc typesText(host: HostContext; store: ptr ContextT; self: var RopeResource): string
proc typesSlice(host: HostContext; store: ptr ContextT; self: var RopeResource;
                a: int64; b: int64): RopeResource
proc typesSlicePoints(host: HostContext; store: ptr ContextT;
                      self: var RopeResource; a: Cursor; b: Cursor): RopeResource
proc editorActiveEditor(host: HostContext; store: ptr ContextT): Option[Editor]
proc editorGetDocument(host: HostContext; store: ptr ContextT; editor: Editor): Option[
    Document]
proc coreApiVersion(host: HostContext; store: ptr ContextT): int32
proc coreGetTime(host: HostContext; store: ptr ContextT): float64
proc coreGetPlatform(host: HostContext; store: ptr ContextT): Platform
proc coreDefineCommand(host: HostContext; store: ptr ContextT;
                       name: sink string; active: bool; docs: sink string;
                       params: sink seq[(string, string)];
                       returntype: sink string; context: sink string;
                       fun: uint32; data: uint32): void
proc coreRunCommand(host: HostContext; store: ptr ContextT; name: sink string;
                    arguments: sink string): Result[string, CommandError]
proc coreGetSettingRaw(host: HostContext; store: ptr ContextT; name: sink string): string
proc coreSetSettingRaw(host: HostContext; store: ptr ContextT;
                       name: sink string; value: sink string): void
proc textEditorActiveTextEditor(host: HostContext; store: ptr ContextT): Option[
    TextEditor]
proc textEditorGetDocument(host: HostContext; store: ptr ContextT;
                           editor: TextEditor): Option[TextDocument]
proc textEditorAsTextEditor(host: HostContext; store: ptr ContextT;
                            editor: Editor): Option[TextEditor]
proc textEditorAsTextDocument(host: HostContext; store: ptr ContextT;
                              document: Document): Option[TextDocument]
proc textEditorCommand(host: HostContext; store: ptr ContextT;
                       editor: TextEditor; name: sink string;
                       arguments: sink string): Result[string, CommandError]
proc textEditorSetSelection(host: HostContext; store: ptr ContextT;
                            editor: TextEditor; s: Selection): void
proc textEditorGetSelection(host: HostContext; store: ptr ContextT;
                            editor: TextEditor): Selection
proc textEditorAddModeChangedHandler(host: HostContext; store: ptr ContextT;
                                     fun: uint32): int32
proc textEditorEdit(host: HostContext; store: ptr ContextT; editor: TextEditor;
                    selections: sink seq[Selection]; contents: sink seq[string]): seq[
    Selection]
proc textEditorContent(host: HostContext; store: ptr ContextT;
                       editor: TextEditor): RopeResource
proc textDocumentContent(host: HostContext; store: ptr ContextT;
                         document: TextDocument): RopeResource
proc layoutShow(host: HostContext; store: ptr ContextT; v: View;
                slot: sink string; focus: bool; addToHistory: bool): void
proc layoutClose(host: HostContext; store: ptr ContextT; v: View;
                 keepHidden: bool; restoreHidden: bool): void
proc layoutFocus(host: HostContext; store: ptr ContextT; slot: sink string): void
proc renderNewRenderView(host: HostContext; store: ptr ContextT): RenderViewResource
proc renderRenderViewFromUserId(host: HostContext; store: ptr ContextT;
                                id: sink string): Option[RenderViewResource]
proc renderRenderViewFromView(host: HostContext; store: ptr ContextT; v: View): Option[
    RenderViewResource]
proc renderView(host: HostContext; store: ptr ContextT;
                self: var RenderViewResource): View
proc renderId(host: HostContext; store: ptr ContextT;
              self: var RenderViewResource): int32
proc renderSize(host: HostContext; store: ptr ContextT;
                self: var RenderViewResource): Vec2f
proc renderKeyDown(host: HostContext; store: ptr ContextT;
                   self: var RenderViewResource; key: int64): bool
proc renderSetRenderInterval(host: HostContext; store: ptr ContextT;
                             self: var RenderViewResource; ms: int32): void
proc renderSetRenderCommandsRaw(host: HostContext; store: ptr ContextT;
                                self: var RenderViewResource; buffer: uint32;
                                len: uint32): void
proc renderSetRenderCommands(host: HostContext; store: ptr ContextT;
                             self: var RenderViewResource; data: sink seq[uint8]): void
proc renderSetRenderWhenInactive(host: HostContext; store: ptr ContextT;
                                 self: var RenderViewResource; enabled: bool): void
proc renderSetPreventThrottling(host: HostContext; store: ptr ContextT;
                                self: var RenderViewResource; enabled: bool): void
proc renderSetUserId(host: HostContext; store: ptr ContextT;
                     self: var RenderViewResource; id: sink string): void
proc renderGetUserId(host: HostContext; store: ptr ContextT;
                     self: var RenderViewResource): string
proc renderMarkDirty(host: HostContext; store: ptr ContextT;
                     self: var RenderViewResource): void
proc renderSetRenderCallback(host: HostContext; store: ptr ContextT;
                             self: var RenderViewResource; fun: uint32;
                             data: uint32): void
proc renderSetModes(host: HostContext; store: ptr ContextT;
                    self: var RenderViewResource; modes: sink seq[string]): void
proc renderAddMode(host: HostContext; store: ptr ContextT;
                   self: var RenderViewResource; mode: sink string): void
proc renderRemoveMode(host: HostContext; store: ptr ContextT;
                      self: var RenderViewResource; mode: sink string): void
proc vfsReadSync(host: HostContext; store: ptr ContextT; path: sink string;
                 readFlags: ReadFlags): Result[string, VfsError]
proc vfsReadRopeSync(host: HostContext; store: ptr ContextT; path: sink string;
                     readFlags: ReadFlags): Result[RopeResource, VfsError]
proc vfsWriteSync(host: HostContext; store: ptr ContextT; path: sink string;
                  content: sink string): Result[bool, VfsError]
proc vfsWriteRopeSync(host: HostContext; store: ptr ContextT; path: sink string;
                      rope: sink RopeResource): Result[bool, VfsError]
proc vfsLocalize(host: HostContext; store: ptr ContextT; path: sink string): string
proc channelCanRead(host: HostContext; store: ptr ContextT;
                    self: var ReadChannelResource): bool
proc channelAtEnd(host: HostContext; store: ptr ContextT;
                  self: var ReadChannelResource): bool
proc channelPeek(host: HostContext; store: ptr ContextT;
                 self: var ReadChannelResource): int32
proc channelReadString(host: HostContext; store: ptr ContextT;
                       self: var ReadChannelResource; num: int32): string
proc channelReadBytes(host: HostContext; store: ptr ContextT;
                      self: var ReadChannelResource; num: int32): seq[uint8]
proc channelReadAllString(host: HostContext; store: ptr ContextT;
                          self: var ReadChannelResource): string
proc channelReadAllBytes(host: HostContext; store: ptr ContextT;
                         self: var ReadChannelResource): seq[uint8]
proc channelListen(host: HostContext; store: ptr ContextT;
                   self: var ReadChannelResource; fun: uint32; data: uint32): void
proc channelWaitRead(host: HostContext; store: ptr ContextT;
                     self: var ReadChannelResource; task: uint64; num: int32): bool
proc channelClose(host: HostContext; store: ptr ContextT;
                  self: var WriteChannelResource): void
proc channelCanWrite(host: HostContext; store: ptr ContextT;
                     self: var WriteChannelResource): bool
proc channelWriteString(host: HostContext; store: ptr ContextT;
                        self: var WriteChannelResource; data: sink string): void
proc channelWriteBytes(host: HostContext; store: ptr ContextT;
                       self: var WriteChannelResource; data: sink seq[uint8]): void
proc channelNewInMemoryChannel(host: HostContext; store: ptr ContextT): (
    ReadChannelResource, WriteChannelResource)
proc processProcessStart(host: HostContext; store: ptr ContextT;
                         name: sink string; args: sink seq[string]): ProcessResource
proc processStderr(host: HostContext; store: ptr ContextT;
                   self: var ProcessResource): ReadChannelResource
proc processStdout(host: HostContext; store: ptr ContextT;
                   self: var ProcessResource): ReadChannelResource
proc processStdin(host: HostContext; store: ptr ContextT;
                  self: var ProcessResource): WriteChannelResource
proc defineComponent*(linker: ptr LinkerT; host: HostContext): WasmtimeResult[
    void] =
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/types", "[resource-drop]rope",
                                 newFunctype([WasmValkind.I32], [])):
        host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[resource-drop]read-channel",
                                 newFunctype([WasmValkind.I32], [])):
        host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[resource-drop]write-channel",
                                 newFunctype([WasmValkind.I32], [])):
        host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/process",
                                 "[resource-drop]process",
                                 newFunctype([WasmValkind.I32], [])):
        host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[resource-drop]render-view",
                                 newFunctype([WasmValkind.I32], [])):
        host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[constructor]rope", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var content: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          content = newString(parameters[1].i32)
          for i0 in 0 ..< content.len:
            content[i0] = p0[i0]
        let res = typesNewRope(host, store, content)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.clone", ty):
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = typesClone(host, store, self[])
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.bytes", ty):
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = typesBytes(host, store, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.runes", ty):
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = typesRunes(host, store, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.lines", ty):
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = typesLines(host, store, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.text", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = typesText(host, store, self[])
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              memory[dataPtrWasm0 + i0] = cast[uint8](res[i0])
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I64], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.slice", ty):
        var self: ptr RopeResource
        var a: int64
        var b: int64
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        a = convert(parameters[1].i64, int64)
        b = convert(parameters[2].i64, int64)
        let res = typesSlice(host, store, self[], a, b)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]rope.slice-points", ty):
        var self: ptr RopeResource
        var a: Cursor
        var b: Cursor
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        a.line = convert(parameters[1].i32, int32)
        a.column = convert(parameters[2].i32, int32)
        b.line = convert(parameters[2].i32, int32)
        b.column = convert(parameters[3].i32, int32)
        let res = typesSlicePoints(host, store, self[], a, b)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/editor", "active-editor", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let res = editorActiveEditor(host, store)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/editor", "get-document", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var editor: Editor
        editor.id = convert(parameters[0].i64, uint64)
        let res = editorGetDocument(host, store, editor)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/core", "api-version", ty):
        let res = coreApiVersion(host, store)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.F64])
      linker.defineFuncUnchecked("nev:plugins/core", "get-time", ty):
        let res = coreGetTime(host, store)
        parameters[0].f64 = cast[float64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/core", "get-platform", ty):
        let res = coreGetPlatform(host, store)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/core", "define-command", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var name: string
        var active: bool
        var docs: string
        var params: seq[(string, string)]
        var returntype: string
        var context: string
        var fun: uint32
        var data: uint32
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        active = parameters[2].i32.bool
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[3].i32].addr)
          docs = newString(parameters[4].i32)
          for i0 in 0 ..< docs.len:
            docs[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[5].i32].addr)
          params = newSeq[typeof(params[0])](parameters[6].i32)
          for i0 in 0 ..< params.len:
            block:
              let p2 = cast[ptr UncheckedArray[char]](memory[
                  cast[ptr int32](p0[i0 * 16 + 0].addr)[]].addr)
              params[i0][0] = newString(cast[ptr int32](p0[i0 * 16 + 4].addr)[])
              for i2 in 0 ..< params[i0][0].len:
                params[i0][0][i2] = p2[i2]
            block:
              let p2 = cast[ptr UncheckedArray[char]](memory[
                  cast[ptr int32](p0[i0 * 16 + 8].addr)[]].addr)
              params[i0][1] = newString(cast[ptr int32](p0[i0 * 16 + 12].addr)[])
              for i2 in 0 ..< params[i0][1].len:
                params[i0][1][i2] = p2[i2]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[7].i32].addr)
          returntype = newString(parameters[8].i32)
          for i0 in 0 ..< returntype.len:
            returntype[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[9].i32].addr)
          context = newString(parameters[10].i32)
          for i0 in 0 ..< context.len:
            context[i0] = p0[i0]
        fun = convert(parameters[11].i32, uint32)
        data = convert(parameters[12].i32, uint32)
        coreDefineCommand(host, store, name, active, docs, params, returntype,
                          context, fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/core", "run-command", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var name: string
        var arguments: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          arguments = newString(parameters[3].i32)
          for i0 in 0 ..< arguments.len:
            arguments[i0] = p0[i0]
        let res = coreRunCommand(host, store, name, arguments)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isErr.int32
        if res.isOk:
          if res.value.len > 0:
            let dataPtrWasm1 = int32(?stackAlloc(stackAllocFunc, store,
                (res.value.len * 1).int32, 4))
            cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](dataPtrWasm1)
            block:
              for i1 in 0 ..< res.value.len:
                memory[dataPtrWasm1 + i1] = cast[uint8](res.value[i1])
          else:
            cast[ptr int32](memory[retArea + 4].addr)[] = 0.int32
          cast[ptr int32](memory[retArea + 8].addr)[] = cast[int32](res.value.len)
        else:
          cast[ptr int8](memory[retArea + 4].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/core", "get-setting-raw", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var name: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        let res = coreGetSettingRaw(host, store, name)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              memory[dataPtrWasm0 + i0] = cast[uint8](res[i0])
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/core", "set-setting-raw", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var name: string
        var value: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          value = newString(parameters[3].i32)
          for i0 in 0 ..< value.len:
            value[i0] = p0[i0]
        coreSetSettingRaw(host, store, name, value)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "active-text-editor", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let res = textEditorActiveTextEditor(host, store)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-document", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetDocument(host, store, editor)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "as-text-editor", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var editor: Editor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorAsTextEditor(host, store, editor)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "as-text-document",
                                 ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var document: Document
        document.id = convert(parameters[0].i64, uint64)
        let res = textEditorAsTextDocument(host, store, document)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "command", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var editor: TextEditor
        var name: string
        var arguments: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          name = newString(parameters[2].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[3].i32].addr)
          arguments = newString(parameters[4].i32)
          for i0 in 0 ..< arguments.len:
            arguments[i0] = p0[i0]
        let res = textEditorCommand(host, store, editor, name, arguments)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isErr.int32
        if res.isOk:
          if res.value.len > 0:
            let dataPtrWasm1 = int32(?stackAlloc(stackAllocFunc, store,
                (res.value.len * 1).int32, 4))
            cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](dataPtrWasm1)
            block:
              for i1 in 0 ..< res.value.len:
                memory[dataPtrWasm1 + i1] = cast[uint8](res.value[i1])
          else:
            cast[ptr int32](memory[retArea + 4].addr)[] = 0.int32
          cast[ptr int32](memory[retArea + 8].addr)[] = cast[int32](res.value.len)
        else:
          cast[ptr int8](memory[retArea + 4].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "set-selection", ty):
        var editor: TextEditor
        var s: Selection
        editor.id = convert(parameters[0].i64, uint64)
        s.first.line = convert(parameters[1].i32, int32)
        s.first.column = convert(parameters[2].i32, int32)
        s.last.line = convert(parameters[3].i32, int32)
        s.last.column = convert(parameters[4].i32, int32)
        textEditorSetSelection(host, store, editor, s)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-selection", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetSelection(host, store, editor)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.first.line
        cast[ptr int32](memory[retArea + 4].addr)[] = res.first.column
        cast[ptr int32](memory[retArea + 8].addr)[] = res.last.line
        cast[ptr int32](memory[retArea + 12].addr)[] = res.last.column
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "add-mode-changed-handler", ty):
        var fun: uint32
        fun = convert(parameters[0].i32, uint32)
        let res = textEditorAddModeChangedHandler(host, store, fun)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "edit", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var editor: TextEditor
        var selections: seq[Selection]
        var contents: seq[string]
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          selections = newSeq[typeof(selections[0])](parameters[2].i32)
          for i0 in 0 ..< selections.len:
            selections[i0].first.line = convert(
                cast[ptr int32](p0[i0 * 16 + 0].addr)[], int32)
            selections[i0].first.column = convert(
                cast[ptr int32](p0[i0 * 16 + 4].addr)[], int32)
            selections[i0].last.line = convert(
                cast[ptr int32](p0[i0 * 16 + 8].addr)[], int32)
            selections[i0].last.column = convert(
                cast[ptr int32](p0[i0 * 16 + 12].addr)[], int32)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[3].i32].addr)
          contents = newSeq[typeof(contents[0])](parameters[4].i32)
          for i0 in 0 ..< contents.len:
            block:
              let p1 = cast[ptr UncheckedArray[char]](memory[
                  cast[ptr int32](p0[i0 * 8 + 0].addr)[]].addr)
              contents[i0] = newString(cast[ptr int32](p0[i0 * 8 + 4].addr)[])
              for i1 in 0 ..< contents[i0].len:
                contents[i0][i1] = p1[i1]
        let res = textEditorEdit(host, store, editor, selections, contents)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 16).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 0].addr)[] = res[
                  i0].first.line
              cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 4].addr)[] = res[
                  i0].first.column
              cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 8].addr)[] = res[
                  i0].last.line
              cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 12].addr)[] = res[
                  i0].last.column
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "content", ty):
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorContent(host, store, editor)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-document", "content", ty):
        var document: TextDocument
        document.id = convert(parameters[0].i64, uint64)
        let res = textDocumentContent(host, store, document)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "show", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var v: View
        var slot: string
        var focus: bool
        var addToHistory: bool
        v.id = convert(parameters[0].i32, int32)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          slot = newString(parameters[2].i32)
          for i0 in 0 ..< slot.len:
            slot[i0] = p0[i0]
        focus = parameters[3].i32.bool
        addToHistory = parameters[4].i32.bool
        layoutShow(host, store, v, slot, focus, addToHistory)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "close", ty):
        var v: View
        var keepHidden: bool
        var restoreHidden: bool
        v.id = convert(parameters[0].i32, int32)
        keepHidden = parameters[1].i32.bool
        restoreHidden = parameters[2].i32.bool
        layoutClose(host, store, v, keepHidden, restoreHidden)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "focus", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var slot: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          slot = newString(parameters[1].i32)
          for i0 in 0 ..< slot.len:
            slot[i0] = p0[i0]
        layoutFocus(host, store, slot)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[constructor]render-view", ty):
        let res = renderNewRenderView(host, store)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[static]render-view.from-user-id", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var id: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          id = newString(parameters[1].i32)
          for i0 in 0 ..< id.len:
            id[i0] = p0[i0]
        let res = renderRenderViewFromUserId(host, store, id)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?host.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[static]render-view.from-view", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var v: View
        v.id = convert(parameters[0].i32, int32)
        let res = renderRenderViewFromView(host, store, v)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?host.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.view", ty):
        var self: ptr RenderViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderView(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render", "[method]render-view.id",
                                 ty):
        var self: ptr RenderViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderId(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.size", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RenderViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderSize(host, store, self[])
        let retArea = parameters[^1].i32
        cast[ptr float32](memory[retArea + 0].addr)[] = res.x
        cast[ptr float32](memory[retArea + 4].addr)[] = res.y
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.key-down", ty):
        var self: ptr RenderViewResource
        var key: int64
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        key = convert(parameters[1].i64, int64)
        let res = renderKeyDown(host, store, self[], key)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-interval", ty):
        var self: ptr RenderViewResource
        var ms: int32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        ms = convert(parameters[1].i32, int32)
        renderSetRenderInterval(host, store, self[], ms)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-commands-raw",
                                 ty):
        var self: ptr RenderViewResource
        var buffer: uint32
        var len: uint32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        buffer = convert(parameters[1].i32, uint32)
        len = convert(parameters[2].i32, uint32)
        renderSetRenderCommandsRaw(host, store, self[], buffer, len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-commands", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RenderViewResource
        var data: seq[uint8]
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          data = newSeq[typeof(data[0])](parameters[2].i32)
          for i0 in 0 ..< data.len:
            data[i0] = convert(cast[ptr uint8](p0[i0 * 1 + 0].addr)[], uint8)
        renderSetRenderCommands(host, store, self[], data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render", "[method]render-view.set-render-when-inactive",
                                 ty):
        var self: ptr RenderViewResource
        var enabled: bool
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        enabled = parameters[1].i32.bool
        renderSetRenderWhenInactive(host, store, self[], enabled)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-prevent-throttling",
                                 ty):
        var self: ptr RenderViewResource
        var enabled: bool
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        enabled = parameters[1].i32.bool
        renderSetPreventThrottling(host, store, self[], enabled)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-user-id", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RenderViewResource
        var id: string
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          id = newString(parameters[2].i32)
          for i0 in 0 ..< id.len:
            id[i0] = p0[i0]
        renderSetUserId(host, store, self[], id)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.get-user-id", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var self: ptr RenderViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderGetUserId(host, store, self[])
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              memory[dataPtrWasm0 + i0] = cast[uint8](res[i0])
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.mark-dirty", ty):
        var self: ptr RenderViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        renderMarkDirty(host, store, self[])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-callback", ty):
        var self: ptr RenderViewResource
        var fun: uint32
        var data: uint32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        fun = convert(parameters[1].i32, uint32)
        data = convert(parameters[2].i32, uint32)
        renderSetRenderCallback(host, store, self[], fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-modes", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RenderViewResource
        var modes: seq[string]
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          modes = newSeq[typeof(modes[0])](parameters[2].i32)
          for i0 in 0 ..< modes.len:
            block:
              let p1 = cast[ptr UncheckedArray[char]](memory[
                  cast[ptr int32](p0[i0 * 8 + 0].addr)[]].addr)
              modes[i0] = newString(cast[ptr int32](p0[i0 * 8 + 4].addr)[])
              for i1 in 0 ..< modes[i0].len:
                modes[i0][i1] = p1[i1]
        renderSetModes(host, store, self[], modes)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.add-mode", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RenderViewResource
        var mode: string
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          mode = newString(parameters[2].i32)
          for i0 in 0 ..< mode.len:
            mode[i0] = p0[i0]
        renderAddMode(host, store, self[], mode)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.remove-mode", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RenderViewResource
        var mode: string
        self = ?host.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          mode = newString(parameters[2].i32)
          for i0 in 0 ..< mode.len:
            mode[i0] = p0[i0]
        renderRemoveMode(host, store, self[], mode)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "read-sync", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var path: string
        var readFlags: ReadFlags
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        readFlags = cast[ReadFlags](parameters[2].i32)
        let res = vfsReadSync(host, store, path, readFlags)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isErr.int32
        if res.isOk:
          if res.value.len > 0:
            let dataPtrWasm1 = int32(?stackAlloc(stackAllocFunc, store,
                (res.value.len * 1).int32, 4))
            cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](dataPtrWasm1)
            block:
              for i1 in 0 ..< res.value.len:
                memory[dataPtrWasm1 + i1] = cast[uint8](res.value[i1])
          else:
            cast[ptr int32](memory[retArea + 4].addr)[] = 0.int32
          cast[ptr int32](memory[retArea + 8].addr)[] = cast[int32](res.value.len)
        else:
          cast[ptr int8](memory[retArea + 4].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "read-rope-sync", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var path: string
        var readFlags: ReadFlags
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        readFlags = cast[ReadFlags](parameters[2].i32)
        let res = vfsReadRopeSync(host, store, path, readFlags)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isErr.int32
        if res.isOk:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?host.resources.resourceNew(
              store, res.value)
        else:
          cast[ptr int8](memory[retArea + 4].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "write-sync", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var path: string
        var content: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          content = newString(parameters[3].i32)
          for i0 in 0 ..< content.len:
            content[i0] = p0[i0]
        let res = vfsWriteSync(host, store, path, content)
        let retArea = parameters[^1].i32
        cast[ptr int8](memory[retArea + 0].addr)[] = res.isErr.int8
        if res.isOk:
          cast[ptr bool](memory[retArea + 1].addr)[] = res.value
        else:
          cast[ptr int8](memory[retArea + 1].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "write-rope-sync", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var path: string
        var rope: RopeResource
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        block:
          let resPtr = ?host.resources.resourceHostData(parameters[2].i32,
              RopeResource)
          copyMem(rope.addr, resPtr, sizeof(typeof(rope)))
          ?host.resources.resourceDrop(parameters[2].i32, callDestroy = false)
        let res = vfsWriteRopeSync(host, store, path, rope)
        let retArea = parameters[^1].i32
        cast[ptr int8](memory[retArea + 0].addr)[] = res.isErr.int8
        if res.isOk:
          cast[ptr bool](memory[retArea + 1].addr)[] = res.value
        else:
          cast[ptr int8](memory[retArea + 1].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "localize", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var path: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        let res = vfsLocalize(host, store, path)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              memory[dataPtrWasm0 + i0] = cast[uint8](res[i0])
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.can-read", ty):
        var self: ptr ReadChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelCanRead(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.at-end", ty):
        var self: ptr ReadChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelAtEnd(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.peek", ty):
        var self: ptr ReadChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelPeek(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.read-string", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var self: ptr ReadChannelResource
        var num: int32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        num = convert(parameters[1].i32, int32)
        let res = channelReadString(host, store, self[], num)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              memory[dataPtrWasm0 + i0] = cast[uint8](res[i0])
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.read-bytes", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var self: ptr ReadChannelResource
        var num: int32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        num = convert(parameters[1].i32, int32)
        let res = channelReadBytes(host, store, self[], num)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              cast[ptr uint8](memory[dataPtrWasm0 + i0 * 1 + 0].addr)[] = res[i0]
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.read-all-string", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var self: ptr ReadChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelReadAllString(host, store, self[])
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              memory[dataPtrWasm0 + i0] = cast[uint8](res[i0])
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.read-all-bytes", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
        var self: ptr ReadChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelReadAllBytes(host, store, self[])
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 1).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              cast[ptr uint8](memory[dataPtrWasm0 + i0 * 1 + 0].addr)[] = res[i0]
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.listen", ty):
        var self: ptr ReadChannelResource
        var fun: uint32
        var data: uint32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        fun = convert(parameters[1].i32, uint32)
        data = convert(parameters[2].i32, uint32)
        channelListen(host, store, self[], fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.wait-read", ty):
        var self: ptr ReadChannelResource
        var task: uint64
        var num: int32
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        task = convert(parameters[1].i64, uint64)
        num = convert(parameters[2].i32, int32)
        let res = channelWaitRead(host, store, self[], task, num)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.close", ty):
        var self: ptr WriteChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        channelClose(host, store, self[])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.can-write", ty):
        var self: ptr WriteChannelResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        let res = channelCanWrite(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.write-string", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr WriteChannelResource
        var data: string
        self = ?host.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          data = newString(parameters[2].i32)
          for i0 in 0 ..< data.len:
            data[i0] = p0[i0]
        channelWriteString(host, store, self[], data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.write-bytes", ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr WriteChannelResource
        var data: seq[uint8]
        self = ?host.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          data = newSeq[typeof(data[0])](parameters[2].i32)
          for i0 in 0 ..< data.len:
            data[i0] = convert(cast[ptr uint8](p0[i0 * 1 + 0].addr)[], uint8)
        channelWriteBytes(host, store, self[], data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel", "new-in-memory-channel",
                                 ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let res = channelNewInMemoryChannel(host, store)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = ?host.resources.resourceNew(
            store, res[0])
        cast[ptr int32](memory[retArea + 4].addr)[] = ?host.resources.resourceNew(
            store, res[1])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process", "[static]process.start",
                                 ty):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = host.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var name: string
        var args: seq[string]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[2].i32].addr)
          args = newSeq[typeof(args[0])](parameters[3].i32)
          for i0 in 0 ..< args.len:
            block:
              let p1 = cast[ptr UncheckedArray[char]](memory[
                  cast[ptr int32](p0[i0 * 8 + 0].addr)[]].addr)
              args[i0] = newString(cast[ptr int32](p0[i0 * 8 + 4].addr)[])
              for i1 in 0 ..< args[i0].len:
                args[i0][i1] = p1[i1]
        let res = processProcessStart(host, store, name, args)
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process",
                                 "[method]process.stderr", ty):
        var self: ptr ProcessResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ProcessResource)
        let res = processStderr(host, store, self[])
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process",
                                 "[method]process.stdout", ty):
        var self: ptr ProcessResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ProcessResource)
        let res = processStdout(host, store, self[])
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process", "[method]process.stdin",
                                 ty):
        var self: ptr ProcessResource
        self = ?host.resources.resourceHostData(parameters[0].i32,
            ProcessResource)
        let res = processStdin(host, store, self[])
        parameters[0].i32 = ?host.resources.resourceNew(store, res)
    if e.isErr:
      return e
