
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
  ActiveEditorFlag* = enum
    IncludeCommandLine = "include-command-line",
    IncludePopups = "include-popups"
  ActiveEditorFlags* = set[ActiveEditorFlag]
  Lamport* = object
    replicaId*: uint16
    value*: uint32
  Bias* = enum
    Left = "left", Right = "right"
  Anchor* = object
    timestamp*: Lamport
    offset*: uint32
    bias*: Bias
  ## Shared reference to a byte buffer. The data is stored in the editor, not in the plugin, so shared buffers
  ## can be used to efficiently share data with another plugin or another thread.
  ## Buffers are reference counted internally, and this resource also affects that reference count.
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
  Platform* = enum
    Gui = "gui", Tui = "tui"
  BackgroundExecutor* = enum
    Thread = "thread", ThreadPool = "thread-pool"
  CommandError* = enum
    NotAllowed = "not-allowed", NotFound = "not-found"
  VfsError* = enum
    NotAllowed = "not-allowed", NotFound = "not-found"
  ReadFlag* = enum
    Binary = "binary"
  ReadFlags* = set[ReadFlag]
  ScrollBehaviour* = enum
    CenterAlways = "center-always", CenterOffscreen = "center-offscreen",
    CenterMargin = "center-margin", ScrollToMargin = "scroll-to-margin",
    TopOfScreen = "top-of-screen"
  ScrollSnapBehaviour* = enum
    Never = "never", Always = "always",
    MinDistanceOffscreen = "min-distance-offscreen",
    MinDistanceCenter = "min-distance-center"
  AudioArgs* = object
    bufferLen*: int64
    index*: int64
    sampleRate*: int64
when not declared(SharedBufferResource):
  {.error: "Missing resource type definition for " & "SharedBufferResource" &
      ". Define the type before the importWit statement.".}
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
    handleMove*: FuncT
    handleAudioCallback*: FuncT
    savePluginState*: FuncT
    loadPluginState*: FuncT
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
  let f_9462351555 = instance.getExport(context, "init_plugin")
  if f_9462351555.isSome:
    assert f_9462351555.get.kind == WASMTIME_EXTERN_FUNC
    funcs.initPlugin = f_9462351555.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "init_plugin", "\'"
  let f_9462351571 = instance.getExport(context, "handle_command")
  if f_9462351571.isSome:
    assert f_9462351571.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleCommand = f_9462351571.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_command", "\'"
  let f_9462351621 = instance.getExport(context, "handle_mode_changed")
  if f_9462351621.isSome:
    assert f_9462351621.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleModeChanged = f_9462351621.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_mode_changed", "\'"
  let f_9462351622 = instance.getExport(context, "handle_view_render_callback")
  if f_9462351622.isSome:
    assert f_9462351622.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleViewRenderCallback = f_9462351622.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_view_render_callback",
         "\'"
  let f_9462351646 = instance.getExport(context, "handle_channel_update")
  if f_9462351646.isSome:
    assert f_9462351646.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleChannelUpdate = f_9462351646.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_channel_update", "\'"
  let f_9462351647 = instance.getExport(context, "notify_task_complete")
  if f_9462351647.isSome:
    assert f_9462351647.get.kind == WASMTIME_EXTERN_FUNC
    funcs.notifyTaskComplete = f_9462351647.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "notify_task_complete", "\'"
  let f_9462351648 = instance.getExport(context, "handle_move")
  if f_9462351648.isSome:
    assert f_9462351648.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleMove = f_9462351648.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_move", "\'"
  let f_9462351660 = instance.getExport(context, "handle_audio_callback")
  if f_9462351660.isSome:
    assert f_9462351660.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleAudioCallback = f_9462351660.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_audio_callback", "\'"
  let f_9462351661 = instance.getExport(context, "save_plugin_state")
  if f_9462351661.isSome:
    assert f_9462351661.get.kind == WASMTIME_EXTERN_FUNC
    funcs.savePluginState = f_9462351661.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "save_plugin_state", "\'"
  let f_9462351662 = instance.getExport(context, "load_plugin_state")
  if f_9462351662.isSome:
    assert f_9462351662.get.kind == WASMTIME_EXTERN_FUNC
    funcs.loadPluginState = f_9462351662.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "load_plugin_state", "\'"

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
  
proc handleMove*(funcs: ExportedFuncs; fun: uint32; data: uint32; text: uint32;
                 selections: seq[Selection]; count: int32; eol: bool): WasmtimeResult[
    seq[Selection]] =
  var args: array[max(1, 7), ValT]
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
  args[2] = toWasmVal(text)
  if selections.len > 0:
    dataPtrWasm0 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (selections.len * 16).int32, 4)
      if temp.isErr:
        return temp.toResult(seq[Selection])
      temp.val
    args[3] = toWasmVal(cast[int32](dataPtrWasm0))
    block:
      for i0 in 0 ..< selections.len:
        cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 0].addr)[] = selections[
            i0].first.line
        cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 4].addr)[] = selections[
            i0].first.column
        cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 8].addr)[] = selections[
            i0].last.line
        cast[ptr int32](memory[dataPtrWasm0 + i0 * 16 + 12].addr)[] = selections[
            i0].last.column
  else:
    args[3] = toWasmVal(0.int32)
  args[4] = toWasmVal(cast[int32](selections.len))
  args[5] = toWasmVal(count)
  args[6] = toWasmVal(eol)
  let res = funcs.handleMove.addr.call(funcs.mContext,
                                       args.toOpenArray(0, 7 - 1),
                                       results.toOpenArray(0, 1 - 1), trap.addr).toResult(
      seq[Selection])
  if trap != nil:
    return trap.toResult(seq[Selection])
  if res.isErr:
    return res.toResult(seq[Selection])
  var retVal: seq[Selection]
  let retArea: ptr UncheckedArray[uint8] = memory.getRawPtr(
      results[0].to(WasmPtr))
  block:
    let p0 = cast[ptr UncheckedArray[uint8]](memory.getRawPtr(
        cast[ptr int32](retArea[0].addr)[].WasmPtr))
    retVal = newSeq[typeof(retVal[0])](cast[ptr int32](retArea[4].addr)[])
    for i0 in 0 ..< retVal.len:
      retVal[i0].first.line = convert(cast[ptr int32](p0[i0 * 16 + 0].addr)[],
                                      int32)
      retVal[i0].first.column = convert(cast[ptr int32](p0[i0 * 16 + 4].addr)[],
                                        int32)
      retVal[i0].last.line = convert(cast[ptr int32](p0[i0 * 16 + 8].addr)[],
                                     int32)
      retVal[i0].last.column = convert(cast[ptr int32](p0[i0 * 16 + 12].addr)[],
                                       int32)
  return wasmtime.ok(retVal)

proc handleAudioCallback*(funcs: ExportedFuncs; fun: uint32; data: uint32;
                          info: AudioArgs): WasmtimeResult[uint32] =
  var args: array[max(1, 5), ValT]
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
  args[2] = toWasmVal(info.bufferLen)
  args[3] = toWasmVal(info.index)
  args[4] = toWasmVal(info.sampleRate)
  let res = funcs.handleAudioCallback.addr.call(funcs.mContext,
      args.toOpenArray(0, 5 - 1), results.toOpenArray(0, 1 - 1), trap.addr).toResult(
      uint32)
  if trap != nil:
    return trap.toResult(uint32)
  if res.isErr:
    return res.toResult(uint32)
  var retVal: uint32
  retVal = convert(results[0].to(uint32), uint32)
  return wasmtime.ok(retVal)

proc savePluginState*(funcs: ExportedFuncs): WasmtimeResult[seq[uint8]] =
  var args: array[max(1, 0), ValT]
  var results: array[max(1, 1), ValT]
  var trap: ptr WasmTrapT = nil
  var memory = funcs.mem
  let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field,
                            funcs.mContext)
  defer:
    discard stackRestore(funcs.mStackRestore.get.of_field.func_field,
                         funcs.mContext, savePoint.val)
  let res = funcs.savePluginState.addr.call(funcs.mContext,
      args.toOpenArray(0, 0 - 1), results.toOpenArray(0, 1 - 1), trap.addr).toResult(
      seq[uint8])
  if trap != nil:
    return trap.toResult(seq[uint8])
  if res.isErr:
    return res.toResult(seq[uint8])
  var retVal: seq[uint8]
  let retArea: ptr UncheckedArray[uint8] = memory.getRawPtr(
      results[0].to(WasmPtr))
  block:
    let p0 = cast[ptr UncheckedArray[uint8]](memory.getRawPtr(
        cast[ptr int32](retArea[0].addr)[].WasmPtr))
    retVal = newSeq[typeof(retVal[0])](cast[ptr int32](retArea[4].addr)[])
    for i0 in 0 ..< retVal.len:
      retVal[i0] = convert(cast[ptr uint8](p0[i0 * 1 + 0].addr)[], uint8)
  return wasmtime.ok(retVal)

proc loadPluginState*(funcs: ExportedFuncs; state: seq[uint8]): WasmtimeResult[
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
  var dataPtrWasm0: WasmPtr
  if state.len > 0:
    dataPtrWasm0 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (state.len * 1).int32, 4)
      if temp.isErr:
        return temp.toResult(void)
      temp.val
    args[0] = toWasmVal(cast[int32](dataPtrWasm0))
    block:
      for i0 in 0 ..< state.len:
        cast[ptr uint8](memory[dataPtrWasm0 + i0 * 1 + 0].addr)[] = state[i0]
  else:
    args[0] = toWasmVal(0.int32)
  args[1] = toWasmVal(cast[int32](state.len))
  let res = funcs.loadPluginState.addr.call(funcs.mContext,
      args.toOpenArray(0, 2 - 1), results.toOpenArray(0, 0 - 1), trap.addr).toResult(
      void)
  if trap != nil:
    return trap.toResult(void)
  if res.isErr:
    return res.toResult(void)
  
proc coreApiVersion*(instance: ptr InstanceData): int32
proc coreGetTime*(instance: ptr InstanceData): float64
proc coreGetPlatform*(instance: ptr InstanceData): Platform
proc coreIsMainThread*(instance: ptr InstanceData): bool
proc coreGetArguments*(instance: ptr InstanceData): string
proc coreSpawnBackground*(instance: ptr InstanceData; args: sink string;
                          executor: BackgroundExecutor): void
proc coreFinishBackground*(instance: ptr InstanceData): void
proc commandsDefineCommand*(instance: ptr InstanceData; name: sink string;
                            active: bool; docs: sink string;
                            params: sink seq[(string, string)];
                            returntype: sink string; context: sink string;
                            fun: uint32; data: uint32): void
proc commandsRunCommand*(instance: ptr InstanceData; name: sink string;
                         arguments: sink string): Result[string, CommandError]
proc commandsExitCommandLine*(instance: ptr InstanceData): void
proc settingsGetSettingRaw*(instance: ptr InstanceData; name: sink string): string
proc settingsSetSettingRaw*(instance: ptr InstanceData; name: sink string;
                            value: sink string): void
proc typesNewSharedBuffer*(instance: ptr InstanceData; size: int64): SharedBufferResource
proc typesCloneRef*(instance: ptr InstanceData; self: var SharedBufferResource): SharedBufferResource
proc typesLen*(instance: ptr InstanceData; self: var SharedBufferResource): int64
proc typesWrite*(instance: ptr InstanceData; self: var SharedBufferResource;
                 index: int64; data: sink seq[uint8]): void
proc typesReadInto*(instance: ptr InstanceData; self: var SharedBufferResource;
                    index: int64; dst: uint32; len: int32): void
proc typesRead*(instance: ptr InstanceData; self: var SharedBufferResource;
                index: int64; len: int32): seq[uint8]
proc typesSharedBufferOpen*(instance: ptr InstanceData; path: sink string): Option[
    SharedBufferResource]
proc typesSharedBufferMount*(instance: ptr InstanceData;
                             buffer: sink SharedBufferResource;
                             path: sink string; unique: bool): string
proc typesNewRope*(instance: ptr InstanceData; content: sink string): RopeResource
proc typesClone*(instance: ptr InstanceData; self: var RopeResource): RopeResource
proc typesBytes*(instance: ptr InstanceData; self: var RopeResource): int64
proc typesRunes*(instance: ptr InstanceData; self: var RopeResource): int64
proc typesLines*(instance: ptr InstanceData; self: var RopeResource): int64
proc typesText*(instance: ptr InstanceData; self: var RopeResource): string
proc typesSlice*(instance: ptr InstanceData; self: var RopeResource; a: int64;
                 b: int64; inclusive: bool): RopeResource
proc typesSliceSelection*(instance: ptr InstanceData; self: var RopeResource;
                          s: Selection; inclusive: bool): RopeResource
proc typesFind*(instance: ptr InstanceData; self: var RopeResource;
                sub: sink string; start: int64): Option[int64]
proc typesSlicePoints*(instance: ptr InstanceData; self: var RopeResource;
                       a: Cursor; b: Cursor): RopeResource
proc typesLineLength*(instance: ptr InstanceData; self: var RopeResource;
                      line: int64): int64
proc typesRuneAt*(instance: ptr InstanceData; self: var RopeResource; a: Cursor): Rune
proc typesByteAt*(instance: ptr InstanceData; self: var RopeResource; a: Cursor): uint8
proc editorActiveEditor*(instance: ptr InstanceData; options: ActiveEditorFlags): Option[
    Editor]
proc editorGetDocument*(instance: ptr InstanceData; editor: Editor): Option[
    Document]
proc textEditorActiveTextEditor*(instance: ptr InstanceData;
                                 options: ActiveEditorFlags): Option[TextEditor]
proc textEditorGetDocument*(instance: ptr InstanceData; editor: TextEditor): Option[
    TextDocument]
proc textEditorAsTextEditor*(instance: ptr InstanceData; editor: Editor): Option[
    TextEditor]
proc textEditorAsTextDocument*(instance: ptr InstanceData; document: Document): Option[
    TextDocument]
proc textEditorCommand*(instance: ptr InstanceData; editor: TextEditor;
                        name: sink string; arguments: sink string): Result[
    string, CommandError]
proc textEditorRecordCurrentCommand*(instance: ptr InstanceData;
                                     editor: TextEditor;
                                     registers: sink seq[string]): void
proc textEditorHideCompletions*(instance: ptr InstanceData; editor: TextEditor): void
proc textEditorScrollToCursor*(instance: ptr InstanceData; editor: TextEditor;
                               behaviour: Option[ScrollBehaviour];
                               relativePosition: float32): void
proc textEditorSetNextSnapBehaviour*(instance: ptr InstanceData;
                                     editor: TextEditor;
                                     behaviour: ScrollSnapBehaviour): void
proc textEditorUpdateTargetColumn*(instance: ptr InstanceData;
                                   editor: TextEditor): void
proc textEditorGetUsage*(instance: ptr InstanceData; editor: TextEditor): string
proc textEditorGetRevision*(instance: ptr InstanceData; editor: TextEditor): int32
proc textEditorSetMode*(instance: ptr InstanceData; editor: TextEditor;
                        mode: sink string; exclusive: bool): void
proc textEditorMode*(instance: ptr InstanceData; editor: TextEditor): string
proc textEditorModes*(instance: ptr InstanceData; editor: TextEditor): seq[
    string]
proc textEditorClearTabStops*(instance: ptr InstanceData; editor: TextEditor): void
proc textEditorUndo*(instance: ptr InstanceData; editor: TextEditor;
                     checkpoint: sink string): void
proc textEditorRedo*(instance: ptr InstanceData; editor: TextEditor;
                     checkpoint: sink string): void
proc textEditorAddNextCheckpoint*(instance: ptr InstanceData;
                                  editor: TextEditor; checkpoint: sink string): void
proc textEditorCopy*(instance: ptr InstanceData; editor: TextEditor;
                     register: sink string; inclusiveEnd: bool): void
proc textEditorPaste*(instance: ptr InstanceData; editor: TextEditor;
                      selections: sink seq[Selection]; register: sink string;
                      inclusiveEnd: bool): void
proc textEditorAutoShowCompletions*(instance: ptr InstanceData;
                                    editor: TextEditor): void
proc textEditorToggleLineComment*(instance: ptr InstanceData; editor: TextEditor): void
proc textEditorInsertText*(instance: ptr InstanceData; editor: TextEditor;
                           text: sink string; autoIndent: bool): void
proc textEditorOpenSearchBar*(instance: ptr InstanceData; editor: TextEditor;
                              query: sink string; scrollToPreview: bool;
                              selectResult: bool): void
proc textEditorSetSearchQueryFromMove*(instance: ptr InstanceData;
                                       editor: TextEditor; move: sink string;
                                       count: int32; prefix: sink string;
                                       suffix: sink string): Selection
proc textEditorSetSearchQuery*(instance: ptr InstanceData; editor: TextEditor;
                               query: sink string; escapeRegex: bool;
                               prefix: sink string; suffix: sink string): bool
proc textEditorGetSearchQuery*(instance: ptr InstanceData; editor: TextEditor): string
proc textEditorApplyMove*(instance: ptr InstanceData; editor: TextEditor;
                          selection: Selection; move: sink string; count: int32;
                          wrap: bool; includeEol: bool): seq[Selection]
proc textEditorMultiMove*(instance: ptr InstanceData; editor: TextEditor;
                          selections: sink seq[Selection]; move: sink string;
                          count: int32; wrap: bool; includeEol: bool): seq[
    Selection]
proc textEditorSetSelection*(instance: ptr InstanceData; editor: TextEditor;
                             s: Selection): void
proc textEditorSetSelections*(instance: ptr InstanceData; editor: TextEditor;
                              s: sink seq[Selection]): void
proc textEditorGetSelection*(instance: ptr InstanceData; editor: TextEditor): Selection
proc textEditorGetSelections*(instance: ptr InstanceData; editor: TextEditor): seq[
    Selection]
proc textEditorLineLength*(instance: ptr InstanceData; editor: TextEditor;
                           line: int32): int32
proc textEditorAddModeChangedHandler*(instance: ptr InstanceData; fun: uint32): int32
proc textEditorGetSettingRaw*(instance: ptr InstanceData; editor: TextEditor;
                              name: sink string): string
proc textEditorSetSettingRaw*(instance: ptr InstanceData; editor: TextEditor;
                              name: sink string; value: sink string): void
proc textEditorEvaluateExpressions*(instance: ptr InstanceData;
                                    editor: TextEditor;
                                    selections: sink seq[Selection];
                                    inclusive: bool; prefix: sink string;
                                    suffix: sink string; addSelectionIndex: bool): void
proc textEditorIndent*(instance: ptr InstanceData; editor: TextEditor;
                       delta: int32): void
proc textEditorGetCommandCount*(instance: ptr InstanceData; editor: TextEditor): int32
proc textEditorSetCursorScrollOffset*(instance: ptr InstanceData;
                                      editor: TextEditor; cursor: Cursor;
                                      scrollOffset: float32): void
proc textEditorGetVisibleLineCount*(instance: ptr InstanceData;
                                    editor: TextEditor): int32
proc textEditorCreateAnchors*(instance: ptr InstanceData; editor: TextEditor;
                              selections: sink seq[Selection]): seq[
    (Anchor, Anchor)]
proc textEditorResolveAnchors*(instance: ptr InstanceData; editor: TextEditor;
                               anchors: sink seq[(Anchor, Anchor)]): seq[
    Selection]
proc textEditorEdit*(instance: ptr InstanceData; editor: TextEditor;
                     selections: sink seq[Selection];
                     contents: sink seq[string]; inclusive: bool): seq[Selection]
proc textEditorDefineMove*(instance: ptr InstanceData; move: sink string;
                           fun: uint32; data: uint32): void
proc textEditorContent*(instance: ptr InstanceData; editor: TextEditor): RopeResource
proc textDocumentContent*(instance: ptr InstanceData; document: TextDocument): RopeResource
proc layoutShow*(instance: ptr InstanceData; v: View; slot: sink string;
                 focus: bool; addToHistory: bool): void
proc layoutClose*(instance: ptr InstanceData; v: View; keepHidden: bool;
                  restoreHidden: bool): void
proc layoutFocus*(instance: ptr InstanceData; slot: sink string): void
proc layoutCloseActiveView*(instance: ptr InstanceData; closeOpenPopup: bool;
                            restoreHidden: bool): void
proc renderNewRenderView*(instance: ptr InstanceData): RenderViewResource
proc renderRenderViewFromUserId*(instance: ptr InstanceData; id: sink string): Option[
    RenderViewResource]
proc renderRenderViewFromView*(instance: ptr InstanceData; v: View): Option[
    RenderViewResource]
proc renderView*(instance: ptr InstanceData; self: var RenderViewResource): View
proc renderId*(instance: ptr InstanceData; self: var RenderViewResource): int32
proc renderSize*(instance: ptr InstanceData; self: var RenderViewResource): Vec2f
proc renderKeyDown*(instance: ptr InstanceData; self: var RenderViewResource;
                    key: int64): bool
proc renderMousePos*(instance: ptr InstanceData; self: var RenderViewResource): Vec2f
proc renderMouseDown*(instance: ptr InstanceData; self: var RenderViewResource;
                      button: int64): bool
proc renderScrollDelta*(instance: ptr InstanceData; self: var RenderViewResource): Vec2f
proc renderSetRenderInterval*(instance: ptr InstanceData;
                              self: var RenderViewResource; ms: int32): void
proc renderSetRenderCommandsRaw*(instance: ptr InstanceData;
                                 self: var RenderViewResource; buffer: uint32;
                                 len: uint32): void
proc renderSetRenderCommands*(instance: ptr InstanceData;
                              self: var RenderViewResource;
                              data: sink seq[uint8]): void
proc renderSetRenderWhenInactive*(instance: ptr InstanceData;
                                  self: var RenderViewResource; enabled: bool): void
proc renderSetPreventThrottling*(instance: ptr InstanceData;
                                 self: var RenderViewResource; enabled: bool): void
proc renderSetUserId*(instance: ptr InstanceData; self: var RenderViewResource;
                      id: sink string): void
proc renderGetUserId*(instance: ptr InstanceData; self: var RenderViewResource): string
proc renderMarkDirty*(instance: ptr InstanceData; self: var RenderViewResource): void
proc renderSetRenderCallback*(instance: ptr InstanceData;
                              self: var RenderViewResource; fun: uint32;
                              data: uint32): void
proc renderSetModes*(instance: ptr InstanceData; self: var RenderViewResource;
                     modes: sink seq[string]): void
proc renderAddMode*(instance: ptr InstanceData; self: var RenderViewResource;
                    mode: sink string): void
proc renderRemoveMode*(instance: ptr InstanceData; self: var RenderViewResource;
                       mode: sink string): void
proc vfsReadSync*(instance: ptr InstanceData; path: sink string;
                  readFlags: ReadFlags): Result[string, VfsError]
proc vfsReadRopeSync*(instance: ptr InstanceData; path: sink string;
                      readFlags: ReadFlags): Result[RopeResource, VfsError]
proc vfsReadBufferSync*(instance: ptr InstanceData; path: sink string): Result[
    SharedBufferResource, VfsError]
proc vfsWriteSync*(instance: ptr InstanceData; path: sink string;
                   content: sink string): Result[bool, VfsError]
proc vfsWriteRopeSync*(instance: ptr InstanceData; path: sink string;
                       rope: sink RopeResource): Result[bool, VfsError]
proc vfsLocalize*(instance: ptr InstanceData; path: sink string): string
proc channelCanRead*(instance: ptr InstanceData; self: var ReadChannelResource): bool
proc channelAtEnd*(instance: ptr InstanceData; self: var ReadChannelResource): bool
proc channelPeek*(instance: ptr InstanceData; self: var ReadChannelResource): int32
proc channelFlushRead*(instance: ptr InstanceData; self: var ReadChannelResource): int32
proc channelReadString*(instance: ptr InstanceData;
                        self: var ReadChannelResource; num: int32): string
proc channelReadBytes*(instance: ptr InstanceData;
                       self: var ReadChannelResource; num: int32): seq[uint8]
proc channelReadAllString*(instance: ptr InstanceData;
                           self: var ReadChannelResource): string
proc channelReadAllBytes*(instance: ptr InstanceData;
                          self: var ReadChannelResource): seq[uint8]
proc channelListen*(instance: ptr InstanceData; self: var ReadChannelResource;
                    fun: uint32; data: uint32): void
proc channelWaitRead*(instance: ptr InstanceData; self: var ReadChannelResource;
                      task: uint64; num: int32): bool
proc channelReadChannelOpen*(instance: ptr InstanceData; path: sink string): Option[
    ReadChannelResource]
proc channelReadChannelMount*(instance: ptr InstanceData;
                              channel: sink ReadChannelResource;
                              path: sink string; unique: bool): string
proc channelClose*(instance: ptr InstanceData; self: var WriteChannelResource): void
proc channelCanWrite*(instance: ptr InstanceData; self: var WriteChannelResource): bool
proc channelWriteString*(instance: ptr InstanceData;
                         self: var WriteChannelResource; data: sink string): void
proc channelWriteBytes*(instance: ptr InstanceData;
                        self: var WriteChannelResource; data: sink seq[uint8]): void
proc channelWriteChannelOpen*(instance: ptr InstanceData; path: sink string): Option[
    WriteChannelResource]
proc channelWriteChannelMount*(instance: ptr InstanceData;
                               channel: sink WriteChannelResource;
                               path: sink string; unique: bool): string
proc channelNewInMemoryChannel*(instance: ptr InstanceData): (
    ReadChannelResource, WriteChannelResource)
proc channelCreateTerminal*(instance: ptr InstanceData;
                            stdin: sink WriteChannelResource;
                            stdout: sink ReadChannelResource; group: sink string): void
proc processProcessStart*(instance: ptr InstanceData; name: sink string;
                          args: sink seq[string]): ProcessResource
proc processStderr*(instance: ptr InstanceData; self: var ProcessResource): ReadChannelResource
proc processStdout*(instance: ptr InstanceData; self: var ProcessResource): ReadChannelResource
proc processStdin*(instance: ptr InstanceData; self: var ProcessResource): WriteChannelResource
proc registersIsReplayingCommands*(instance: ptr InstanceData): bool
proc registersIsRecordingCommands*(instance: ptr InstanceData;
                                   register: sink string): bool
proc registersSetRegisterText*(instance: ptr InstanceData; text: sink string;
                               register: sink string): void
proc registersGetRegisterText*(instance: ptr InstanceData; register: sink string): string
proc registersStartRecordingCommands*(instance: ptr InstanceData;
                                      register: sink string): void
proc registersStopRecordingCommands*(instance: ptr InstanceData;
                                     register: sink string): void
proc registersReplayCommands*(instance: ptr InstanceData; register: sink string): void
proc audioAddAudioCallback*(instance: ptr InstanceData; fun: uint32;
                            data: uint32): void
proc audioNextAudioSample*(instance: ptr InstanceData): int64
proc audioSetBufferSize*(instance: ptr InstanceData; size: int32): void
proc audioEnableTripleBuffering*(instance: ptr InstanceData; enabled: bool): void
proc defineComponent*(linker: ptr LinkerT): WasmtimeResult[void] =
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[resource-drop]shared-buffer",
                                 newFunctype([WasmValkind.I32], [])):
        var instance = cast[ptr InstanceData](store.getData())
        instance.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/types", "[resource-drop]rope",
                                 newFunctype([WasmValkind.I32], [])):
        var instance = cast[ptr InstanceData](store.getData())
        instance.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[resource-drop]read-channel",
                                 newFunctype([WasmValkind.I32], [])):
        var instance = cast[ptr InstanceData](store.getData())
        instance.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[resource-drop]write-channel",
                                 newFunctype([WasmValkind.I32], [])):
        var instance = cast[ptr InstanceData](store.getData())
        instance.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/process",
                                 "[resource-drop]process",
                                 newFunctype([WasmValkind.I32], [])):
        var instance = cast[ptr InstanceData](store.getData())
        instance.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[resource-drop]render-view",
                                 newFunctype([WasmValkind.I32], [])):
        var instance = cast[ptr InstanceData](store.getData())
        instance.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/core", "api-version", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = coreApiVersion(instance)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.F64])
      linker.defineFuncUnchecked("nev:plugins/core", "get-time", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = coreGetTime(instance)
        parameters[0].f64 = cast[float64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/core", "get-platform", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = coreGetPlatform(instance)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/core", "is-main-thread", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = coreIsMainThread(instance)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/core", "get-arguments", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = coreGetArguments(instance)
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
      linker.defineFuncUnchecked("nev:plugins/core", "spawn-background", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var args: string
        var executor: BackgroundExecutor
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          args = newString(parameters[1].i32)
          for i0 in 0 ..< args.len:
            args[i0] = p0[i0]
        executor = cast[BackgroundExecutor](parameters[2].i32)
        coreSpawnBackground(instance, args, executor)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [])
      linker.defineFuncUnchecked("nev:plugins/core", "finish-background", ty):
        var instance = cast[ptr InstanceData](store.getData())
        coreFinishBackground(instance)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/commands", "define-command", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        commandsDefineCommand(instance, name, active, docs, params, returntype,
                              context, fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/commands", "run-command", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = commandsRunCommand(instance, name, arguments)
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
      var ty: ptr WasmFunctypeT = newFunctype([], [])
      linker.defineFuncUnchecked("nev:plugins/commands", "exit-command-line", ty):
        var instance = cast[ptr InstanceData](store.getData())
        commandsExitCommandLine(instance)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/settings", "get-setting-raw", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = settingsGetSettingRaw(instance, name)
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
      linker.defineFuncUnchecked("nev:plugins/settings", "set-setting-raw", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        settingsSetSettingRaw(instance, name, value)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[constructor]shared-buffer", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var size: int64
        size = convert(parameters[0].i64, int64)
        let res = typesNewSharedBuffer(instance, size)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]shared-buffer.clone-ref", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr SharedBufferResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            SharedBufferResource)
        let res = typesCloneRef(instance, self[])
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]shared-buffer.len", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr SharedBufferResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            SharedBufferResource)
        let res = typesLen(instance, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]shared-buffer.write", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr SharedBufferResource
        var index: int64
        var data: seq[uint8]
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            SharedBufferResource)
        index = convert(parameters[1].i64, int64)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[2].i32].addr)
          data = newSeq[typeof(data[0])](parameters[3].i32)
          for i0 in 0 ..< data.len:
            data[i0] = convert(cast[ptr uint8](p0[i0 * 1 + 0].addr)[], uint8)
        typesWrite(instance, self[], index, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]shared-buffer.read-into", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr SharedBufferResource
        var index: int64
        var dst: uint32
        var len: int32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            SharedBufferResource)
        index = convert(parameters[1].i64, int64)
        dst = convert(parameters[2].i32, uint32)
        len = convert(parameters[3].i32, int32)
        typesReadInto(instance, self[], index, dst, len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]shared-buffer.read", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var self: ptr SharedBufferResource
        var index: int64
        var len: int32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            SharedBufferResource)
        index = convert(parameters[1].i64, int64)
        len = convert(parameters[2].i32, int32)
        let res = typesRead(instance, self[], index, len)
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
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[static]shared-buffer.open", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        let res = typesSharedBufferOpen(instance, path)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[static]shared-buffer.mount", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var buffer: SharedBufferResource
        var path: string
        var unique: bool
        block:
          let resPtr = ?instance.resources.resourceHostData(
              parameters[0].i32, SharedBufferResource)
          copyMem(buffer.addr, resPtr, sizeof(typeof(buffer)))
          ?instance.resources.resourceDrop(parameters[0].i32,
              callDestroy = false)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          path = newString(parameters[2].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        unique = parameters[3].i32.bool
        let res = typesSharedBufferMount(instance, buffer, path, unique)
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
          [WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[constructor]rope", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = typesNewRope(instance, content)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.clone", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        let res = typesClone(instance, self[])
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.bytes", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        let res = typesBytes(instance, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.runes", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        let res = typesRunes(instance, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.lines", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        let res = typesLines(instance, self[])
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.text", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        let res = typesText(instance, self[])
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
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I64, WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.slice", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        var a: int64
        var b: int64
        var inclusive: bool
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        a = convert(parameters[1].i64, int64)
        b = convert(parameters[2].i64, int64)
        inclusive = parameters[3].i32.bool
        let res = typesSlice(instance, self[], a, b, inclusive)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]rope.slice-selection", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        var s: Selection
        var inclusive: bool
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        s.first.line = convert(parameters[1].i32, int32)
        s.first.column = convert(parameters[2].i32, int32)
        s.last.line = convert(parameters[3].i32, int32)
        s.last.column = convert(parameters[4].i32, int32)
        inclusive = parameters[5].i32.bool
        let res = typesSliceSelection(instance, self[], s, inclusive)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.find", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var self: ptr RopeResource
        var sub: string
        var start: int64
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          sub = newString(parameters[2].i32)
          for i0 in 0 ..< sub.len:
            sub[i0] = p0[i0]
        start = convert(parameters[3].i64, int64)
        let res = typesFind(instance, self[], sub, start)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
        if res.isSome:
          cast[ptr int64](memory[retArea + 8].addr)[] = res.get
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]rope.slice-points", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        var a: Cursor
        var b: Cursor
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        a.line = convert(parameters[1].i32, int32)
        a.column = convert(parameters[2].i32, int32)
        b.line = convert(parameters[3].i32, int32)
        b.column = convert(parameters[4].i32, int32)
        let res = typesSlicePoints(instance, self[], a, b)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64], [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/types",
                                 "[method]rope.line-length", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        var line: int64
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        line = convert(parameters[1].i64, int64)
        let res = typesLineLength(instance, self[], line)
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.rune-at", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        var a: Cursor
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        a.line = convert(parameters[1].i32, int32)
        a.column = convert(parameters[2].i32, int32)
        let res = typesRuneAt(instance, self[], a)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/types", "[method]rope.byte-at", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RopeResource
        var a: Cursor
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RopeResource)
        a.line = convert(parameters[1].i32, int32)
        a.column = convert(parameters[2].i32, int32)
        let res = typesByteAt(instance, self[], a)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/editor", "active-editor", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var options: ActiveEditorFlags
        options = cast[ActiveEditorFlags](parameters[0].i32)
        let res = editorActiveEditor(instance, options)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/editor", "get-document", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = editorGetDocument(instance, editor)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "active-text-editor", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var options: ActiveEditorFlags
        options = cast[ActiveEditorFlags](parameters[0].i32)
        let res = textEditorActiveTextEditor(instance, options)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-document", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = textEditorGetDocument(instance, editor)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
        if res.isSome:
          cast[ptr uint64](memory[retArea + 8].addr)[] = res.get.id
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "as-text-editor", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = textEditorAsTextEditor(instance, editor)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = textEditorAsTextDocument(instance, document)
        let retArea = parameters[^1].i32
        cast[ptr int64](memory[retArea + 0].addr)[] = res.isSome.int64
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = textEditorCommand(instance, editor, name, arguments)
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
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "record-current-command", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var registers: seq[string]
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          registers = newSeq[typeof(registers[0])](parameters[2].i32)
          for i0 in 0 ..< registers.len:
            block:
              let p1 = cast[ptr UncheckedArray[char]](memory[
                  cast[ptr int32](p0[i0 * 8 + 0].addr)[]].addr)
              registers[i0] = newString(cast[ptr int32](p0[i0 * 8 + 4].addr)[])
              for i1 in 0 ..< registers[i0].len:
                registers[i0][i1] = p1[i1]
        textEditorRecordCurrentCommand(instance, editor, registers)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "hide-completions",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        textEditorHideCompletions(instance, editor)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.F32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "scroll-to-cursor",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        var behaviour: Option[ScrollBehaviour]
        var relativePosition: float32
        editor.id = convert(parameters[0].i64, uint64)
        if parameters[1].i32 != 0:
          var temp: ScrollBehaviour
          temp = cast[ScrollBehaviour](parameters[2].i32)
          behaviour = temp.some
        relativePosition = convert(parameters[3].f32, float32)
        textEditorScrollToCursor(instance, editor, behaviour, relativePosition)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "set-next-snap-behaviour", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        var behaviour: ScrollSnapBehaviour
        editor.id = convert(parameters[0].i64, uint64)
        behaviour = cast[ScrollSnapBehaviour](parameters[1].i32)
        textEditorSetNextSnapBehaviour(instance, editor, behaviour)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "update-target-column", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        textEditorUpdateTargetColumn(instance, editor)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-usage", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetUsage(instance, editor)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-revision", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetRevision(instance, editor)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "set-mode", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var mode: string
        var exclusive: bool
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          mode = newString(parameters[2].i32)
          for i0 in 0 ..< mode.len:
            mode[i0] = p0[i0]
        exclusive = parameters[3].i32.bool
        textEditorSetMode(instance, editor, mode, exclusive)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "mode", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorMode(instance, editor)
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
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "modes", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorModes(instance, editor)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 8).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              if res[i0].len > 0:
                let dataPtrWasm1 = int32(?stackAlloc(stackAllocFunc, store,
                    (res[i0].len * 1).int32, 4))
                cast[ptr int32](memory[dataPtrWasm0 + i0 * 8 + 0].addr)[] = cast[int32](dataPtrWasm1)
                block:
                  for i1 in 0 ..< res[i0].len:
                    memory[dataPtrWasm1 + i1] = cast[uint8](res[i0][i1])
              else:
                cast[ptr int32](memory[dataPtrWasm0 + i0 * 8 + 0].addr)[] = 0.int32
              cast[ptr int32](memory[dataPtrWasm0 + i0 * 8 + 4].addr)[] = cast[int32](res[
                  i0].len)
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "clear-tab-stops",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        textEditorClearTabStops(instance, editor)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "undo", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var checkpoint: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          checkpoint = newString(parameters[2].i32)
          for i0 in 0 ..< checkpoint.len:
            checkpoint[i0] = p0[i0]
        textEditorUndo(instance, editor, checkpoint)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "redo", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var checkpoint: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          checkpoint = newString(parameters[2].i32)
          for i0 in 0 ..< checkpoint.len:
            checkpoint[i0] = p0[i0]
        textEditorRedo(instance, editor, checkpoint)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "add-next-checkpoint", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var checkpoint: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          checkpoint = newString(parameters[2].i32)
          for i0 in 0 ..< checkpoint.len:
            checkpoint[i0] = p0[i0]
        textEditorAddNextCheckpoint(instance, editor, checkpoint)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "copy", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var register: string
        var inclusiveEnd: bool
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          register = newString(parameters[2].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        inclusiveEnd = parameters[3].i32.bool
        textEditorCopy(instance, editor, register, inclusiveEnd)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "paste", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var selections: seq[Selection]
        var register: string
        var inclusiveEnd: bool
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
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[3].i32].addr)
          register = newString(parameters[4].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        inclusiveEnd = parameters[5].i32.bool
        textEditorPaste(instance, editor, selections, register, inclusiveEnd)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "auto-show-completions", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        textEditorAutoShowCompletions(instance, editor)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "toggle-line-comment", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        textEditorToggleLineComment(instance, editor)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "insert-text", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var text: string
        var autoIndent: bool
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          text = newString(parameters[2].i32)
          for i0 in 0 ..< text.len:
            text[i0] = p0[i0]
        autoIndent = parameters[3].i32.bool
        textEditorInsertText(instance, editor, text, autoIndent)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "open-search-bar",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var query: string
        var scrollToPreview: bool
        var selectResult: bool
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          query = newString(parameters[2].i32)
          for i0 in 0 ..< query.len:
            query[i0] = p0[i0]
        scrollToPreview = parameters[3].i32.bool
        selectResult = parameters[4].i32.bool
        textEditorOpenSearchBar(instance, editor, query, scrollToPreview,
                                selectResult)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "set-search-query-from-move", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var move: string
        var count: int32
        var prefix: string
        var suffix: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          move = newString(parameters[2].i32)
          for i0 in 0 ..< move.len:
            move[i0] = p0[i0]
        count = convert(parameters[3].i32, int32)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[4].i32].addr)
          prefix = newString(parameters[5].i32)
          for i0 in 0 ..< prefix.len:
            prefix[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[6].i32].addr)
          suffix = newString(parameters[7].i32)
          for i0 in 0 ..< suffix.len:
            suffix[i0] = p0[i0]
        let res = textEditorSetSearchQueryFromMove(instance, editor, move,
            count, prefix, suffix)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.first.line
        cast[ptr int32](memory[retArea + 4].addr)[] = res.first.column
        cast[ptr int32](memory[retArea + 8].addr)[] = res.last.line
        cast[ptr int32](memory[retArea + 12].addr)[] = res.last.column
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "set-search-query",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var query: string
        var escapeRegex: bool
        var prefix: string
        var suffix: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          query = newString(parameters[2].i32)
          for i0 in 0 ..< query.len:
            query[i0] = p0[i0]
        escapeRegex = parameters[3].i32.bool
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[4].i32].addr)
          prefix = newString(parameters[5].i32)
          for i0 in 0 ..< prefix.len:
            prefix[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[6].i32].addr)
          suffix = newString(parameters[7].i32)
          for i0 in 0 ..< suffix.len:
            suffix[i0] = p0[i0]
        let res = textEditorSetSearchQuery(instance, editor, query, escapeRegex,
            prefix, suffix)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-search-query",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetSearchQuery(instance, editor)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "apply-move", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var selection: Selection
        var move: string
        var count: int32
        var wrap: bool
        var includeEol: bool
        editor.id = convert(parameters[0].i64, uint64)
        selection.first.line = convert(parameters[1].i32, int32)
        selection.first.column = convert(parameters[2].i32, int32)
        selection.last.line = convert(parameters[3].i32, int32)
        selection.last.column = convert(parameters[4].i32, int32)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[5].i32].addr)
          move = newString(parameters[6].i32)
          for i0 in 0 ..< move.len:
            move[i0] = p0[i0]
        count = convert(parameters[7].i32, int32)
        wrap = parameters[8].i32.bool
        includeEol = parameters[9].i32.bool
        let res = textEditorApplyMove(instance, editor, selection, move, count,
                                      wrap, includeEol)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "multi-move", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var move: string
        var count: int32
        var wrap: bool
        var includeEol: bool
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
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[3].i32].addr)
          move = newString(parameters[4].i32)
          for i0 in 0 ..< move.len:
            move[i0] = p0[i0]
        count = convert(parameters[5].i32, int32)
        wrap = parameters[6].i32.bool
        includeEol = parameters[7].i32.bool
        let res = textEditorMultiMove(instance, editor, selections, move, count,
                                      wrap, includeEol)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "set-selection", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        var s: Selection
        editor.id = convert(parameters[0].i64, uint64)
        s.first.line = convert(parameters[1].i32, int32)
        s.first.column = convert(parameters[2].i32, int32)
        s.last.line = convert(parameters[3].i32, int32)
        s.last.column = convert(parameters[4].i32, int32)
        textEditorSetSelection(instance, editor, s)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "set-selections", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var s: seq[Selection]
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          s = newSeq[typeof(s[0])](parameters[2].i32)
          for i0 in 0 ..< s.len:
            s[i0].first.line = convert(cast[ptr int32](p0[i0 * 16 + 0].addr)[],
                                       int32)
            s[i0].first.column = convert(
                cast[ptr int32](p0[i0 * 16 + 4].addr)[], int32)
            s[i0].last.line = convert(cast[ptr int32](p0[i0 * 16 + 8].addr)[],
                                      int32)
            s[i0].last.column = convert(cast[ptr int32](p0[i0 * 16 + 12].addr)[],
                                        int32)
        textEditorSetSelections(instance, editor, s)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-selection", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = textEditorGetSelection(instance, editor)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.first.line
        cast[ptr int32](memory[retArea + 4].addr)[] = res.first.column
        cast[ptr int32](memory[retArea + 8].addr)[] = res.last.line
        cast[ptr int32](memory[retArea + 12].addr)[] = res.last.column
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-selections", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetSelections(instance, editor)
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
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "line-length", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        var line: int32
        editor.id = convert(parameters[0].i64, uint64)
        line = convert(parameters[1].i32, int32)
        let res = textEditorLineLength(instance, editor, line)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "add-mode-changed-handler", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var fun: uint32
        fun = convert(parameters[0].i32, uint32)
        let res = textEditorAddModeChangedHandler(instance, fun)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-setting-raw",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          name = newString(parameters[2].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        let res = textEditorGetSettingRaw(instance, editor, name)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "set-setting-raw",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var name: string
        var value: string
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          name = newString(parameters[2].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[3].i32].addr)
          value = newString(parameters[4].i32)
          for i0 in 0 ..< value.len:
            value[i0] = p0[i0]
        textEditorSetSettingRaw(instance, editor, name, value)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "evaluate-expressions", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var selections: seq[Selection]
        var inclusive: bool
        var prefix: string
        var suffix: string
        var addSelectionIndex: bool
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
        inclusive = parameters[3].i32.bool
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[4].i32].addr)
          prefix = newString(parameters[5].i32)
          for i0 in 0 ..< prefix.len:
            prefix[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[6].i32].addr)
          suffix = newString(parameters[7].i32)
          for i0 in 0 ..< suffix.len:
            suffix[i0] = p0[i0]
        addSelectionIndex = parameters[8].i32.bool
        textEditorEvaluateExpressions(instance, editor, selections, inclusive,
                                      prefix, suffix, addSelectionIndex)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "indent", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        var delta: int32
        editor.id = convert(parameters[0].i64, uint64)
        delta = convert(parameters[1].i32, int32)
        textEditorIndent(instance, editor, delta)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "get-command-count",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetCommandCount(instance, editor)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.F32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "set-cursor-scroll-offset", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        var cursor: Cursor
        var scrollOffset: float32
        editor.id = convert(parameters[0].i64, uint64)
        cursor.line = convert(parameters[1].i32, int32)
        cursor.column = convert(parameters[2].i32, int32)
        scrollOffset = convert(parameters[3].f32, float32)
        textEditorSetCursorScrollOffset(instance, editor, cursor, scrollOffset)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor",
                                 "get-visible-line-count", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorGetVisibleLineCount(instance, editor)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "create-anchors", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = textEditorCreateAnchors(instance, editor, selections)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = int32(?stackAlloc(stackAllocFunc, store,
              (res.len * 28).int32, 4))
          cast[ptr int32](memory[retArea + 0].addr)[] = cast[int32](dataPtrWasm0)
          block:
            for i0 in 0 ..< res.len:
              cast[ptr uint16](memory[dataPtrWasm0 + i0 * 28 + 0].addr)[] = res[
                  i0][0].timestamp.replicaId
              cast[ptr uint32](memory[dataPtrWasm0 + i0 * 28 + 4].addr)[] = res[
                  i0][0].timestamp.value
              cast[ptr uint32](memory[dataPtrWasm0 + i0 * 28 + 8].addr)[] = res[
                  i0][0].offset
              cast[ptr int8](memory[dataPtrWasm0 + i0 * 28 + 12].addr)[] = cast[int8](res[
                  i0][0].bias)
              cast[ptr uint16](memory[dataPtrWasm0 + i0 * 28 + 14].addr)[] = res[
                  i0][1].timestamp.replicaId
              cast[ptr uint32](memory[dataPtrWasm0 + i0 * 28 + 16].addr)[] = res[
                  i0][1].timestamp.value
              cast[ptr uint32](memory[dataPtrWasm0 + i0 * 28 + 20].addr)[] = res[
                  i0][1].offset
              cast[ptr int8](memory[dataPtrWasm0 + i0 * 28 + 24].addr)[] = cast[int8](res[
                  i0][1].bias)
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0.int32
        cast[ptr int32](memory[retArea + 4].addr)[] = cast[int32](res.len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I64, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "resolve-anchors",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var anchors: seq[(Anchor, Anchor)]
        editor.id = convert(parameters[0].i64, uint64)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          anchors = newSeq[typeof(anchors[0])](parameters[2].i32)
          for i0 in 0 ..< anchors.len:
            anchors[i0][0].timestamp.replicaId = convert(
                cast[ptr uint16](p0[i0 * 28 + 0].addr)[], uint16)
            anchors[i0][0].timestamp.value = convert(
                cast[ptr uint32](p0[i0 * 28 + 4].addr)[], uint32)
            anchors[i0][0].offset = convert(
                cast[ptr uint32](p0[i0 * 28 + 8].addr)[], uint32)
            anchors[i0][0].bias = cast[Bias](cast[ptr int8](p0[i0 * 28 + 12].addr)[])
            anchors[i0][1].timestamp.replicaId = convert(
                cast[ptr uint16](p0[i0 * 28 + 14].addr)[], uint16)
            anchors[i0][1].timestamp.value = convert(
                cast[ptr uint32](p0[i0 * 28 + 16].addr)[], uint32)
            anchors[i0][1].offset = convert(
                cast[ptr uint32](p0[i0 * 28 + 20].addr)[], uint32)
            anchors[i0][1].bias = cast[Bias](cast[ptr int8](p0[i0 * 28 + 24].addr)[])
        let res = textEditorResolveAnchors(instance, editor, anchors)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "edit", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var inclusive: bool
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
        inclusive = parameters[5].i32.bool
        let res = textEditorEdit(instance, editor, selections, contents,
                                 inclusive)
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
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "define-move", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var move: string
        var fun: uint32
        var data: uint32
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          move = newString(parameters[1].i32)
          for i0 in 0 ..< move.len:
            move[i0] = p0[i0]
        fun = convert(parameters[2].i32, uint32)
        data = convert(parameters[3].i32, uint32)
        textEditorDefineMove(instance, move, fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-editor", "content", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var editor: TextEditor
        editor.id = convert(parameters[0].i64, uint64)
        let res = textEditorContent(instance, editor)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I64],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text-document", "content", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var document: TextDocument
        document.id = convert(parameters[0].i64, uint64)
        let res = textDocumentContent(instance, document)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "show", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        layoutShow(instance, v, slot, focus, addToHistory)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "close", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var v: View
        var keepHidden: bool
        var restoreHidden: bool
        v.id = convert(parameters[0].i32, int32)
        keepHidden = parameters[1].i32.bool
        restoreHidden = parameters[2].i32.bool
        layoutClose(instance, v, keepHidden, restoreHidden)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "focus", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        layoutFocus(instance, slot)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/layout", "close-active-view", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var closeOpenPopup: bool
        var restoreHidden: bool
        closeOpenPopup = parameters[0].i32.bool
        restoreHidden = parameters[1].i32.bool
        layoutCloseActiveView(instance, closeOpenPopup, restoreHidden)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[constructor]render-view", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = renderNewRenderView(instance)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[static]render-view.from-user-id", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = renderRenderViewFromUserId(instance, id)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[static]render-view.from-view", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = renderRenderViewFromView(instance, v)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.view", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderView(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render", "[method]render-view.id",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderId(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.size", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderSize(instance, self[])
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
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var key: int64
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        key = convert(parameters[1].i64, int64)
        let res = renderKeyDown(instance, self[], key)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.mouse-pos", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderMousePos(instance, self[])
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
                                 "[method]render-view.mouse-down", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var button: int64
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        button = convert(parameters[1].i64, int64)
        let res = renderMouseDown(instance, self[], button)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.scroll-delta", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderScrollDelta(instance, self[])
        let retArea = parameters[^1].i32
        cast[ptr float32](memory[retArea + 0].addr)[] = res.x
        cast[ptr float32](memory[retArea + 4].addr)[] = res.y
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-interval", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var ms: int32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        ms = convert(parameters[1].i32, int32)
        renderSetRenderInterval(instance, self[], ms)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-commands-raw",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var buffer: uint32
        var len: uint32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        buffer = convert(parameters[1].i32, uint32)
        len = convert(parameters[2].i32, uint32)
        renderSetRenderCommandsRaw(instance, self[], buffer, len)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-commands", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          data = newSeq[typeof(data[0])](parameters[2].i32)
          for i0 in 0 ..< data.len:
            data[i0] = convert(cast[ptr uint8](p0[i0 * 1 + 0].addr)[], uint8)
        renderSetRenderCommands(instance, self[], data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render", "[method]render-view.set-render-when-inactive",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var enabled: bool
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        enabled = parameters[1].i32.bool
        renderSetRenderWhenInactive(instance, self[], enabled)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-prevent-throttling",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var enabled: bool
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        enabled = parameters[1].i32.bool
        renderSetPreventThrottling(instance, self[], enabled)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-user-id", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          id = newString(parameters[2].i32)
          for i0 in 0 ..< id.len:
            id[i0] = p0[i0]
        renderSetUserId(instance, self[], id)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.get-user-id", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        let res = renderGetUserId(instance, self[])
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
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        renderMarkDirty(instance, self[])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-render-callback", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr RenderViewResource
        var fun: uint32
        var data: uint32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        fun = convert(parameters[1].i32, uint32)
        data = convert(parameters[2].i32, uint32)
        renderSetRenderCallback(instance, self[], fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.set-modes", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
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
        renderSetModes(instance, self[], modes)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.add-mode", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          mode = newString(parameters[2].i32)
          for i0 in 0 ..< mode.len:
            mode[i0] = p0[i0]
        renderAddMode(instance, self[], mode)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]render-view.remove-mode", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            RenderViewResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          mode = newString(parameters[2].i32)
          for i0 in 0 ..< mode.len:
            mode[i0] = p0[i0]
        renderRemoveMode(instance, self[], mode)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "read-sync", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = vfsReadSync(instance, path, readFlags)
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = vfsReadRopeSync(instance, path, readFlags)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isErr.int32
        if res.isOk:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
              store, res.value)
        else:
          cast[ptr int8](memory[retArea + 4].addr)[] = cast[int8](res.error)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/vfs", "read-buffer-sync", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        let res = vfsReadBufferSync(instance, path)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isErr.int32
        if res.isOk:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = vfsWriteSync(instance, path, content)
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
          let resPtr = ?instance.resources.resourceHostData(
              parameters[2].i32, RopeResource)
          copyMem(rope.addr, resPtr, sizeof(typeof(rope)))
          ?instance.resources.resourceDrop(parameters[2].i32,
              callDestroy = false)
        let res = vfsWriteRopeSync(instance, path, rope)
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = vfsLocalize(instance, path)
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
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ReadChannelResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelCanRead(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.at-end", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ReadChannelResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelAtEnd(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.peek", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ReadChannelResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelPeek(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.flush-read", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ReadChannelResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelFlushRead(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.read-string", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        num = convert(parameters[1].i32, int32)
        let res = channelReadString(instance, self[], num)
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        num = convert(parameters[1].i32, int32)
        let res = channelReadBytes(instance, self[], num)
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelReadAllString(instance, self[])
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
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        let res = channelReadAllBytes(instance, self[])
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
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ReadChannelResource
        var fun: uint32
        var data: uint32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        fun = convert(parameters[1].i32, uint32)
        data = convert(parameters[2].i32, uint32)
        channelListen(instance, self[], fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I64, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]read-channel.wait-read", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ReadChannelResource
        var task: uint64
        var num: int32
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ReadChannelResource)
        task = convert(parameters[1].i64, uint64)
        num = convert(parameters[2].i32, int32)
        let res = channelWaitRead(instance, self[], task, num)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[static]read-channel.open", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        let res = channelReadChannelOpen(instance, path)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[static]read-channel.mount", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var channel: ReadChannelResource
        var path: string
        var unique: bool
        block:
          let resPtr = ?instance.resources.resourceHostData(
              parameters[0].i32, ReadChannelResource)
          copyMem(channel.addr, resPtr, sizeof(typeof(channel)))
          ?instance.resources.resourceDrop(parameters[0].i32,
              callDestroy = false)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          path = newString(parameters[2].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        unique = parameters[3].i32.bool
        let res = channelReadChannelMount(instance, channel, path, unique)
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
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.close", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr WriteChannelResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        channelClose(instance, self[])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.can-write", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr WriteChannelResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        let res = channelCanWrite(instance, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.write-string", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          data = newString(parameters[2].i32)
          for i0 in 0 ..< data.len:
            data[i0] = p0[i0]
        channelWriteString(instance, self[], data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[method]write-channel.write-bytes", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            WriteChannelResource)
        block:
          let p0 = cast[ptr UncheckedArray[uint8]](memory[parameters[1].i32].addr)
          data = newSeq[typeof(data[0])](parameters[2].i32)
          for i0 in 0 ..< data.len:
            data[i0] = convert(cast[ptr uint8](p0[i0 * 1 + 0].addr)[], uint8)
        channelWriteBytes(instance, self[], data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[static]write-channel.open", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          path = newString(parameters[1].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        let res = channelWriteChannelOpen(instance, path)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = res.isSome.int32
        if res.isSome:
          cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
              store, res.get)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/channel",
                                 "[static]write-channel.mount", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var channel: WriteChannelResource
        var path: string
        var unique: bool
        block:
          let resPtr = ?instance.resources.resourceHostData(
              parameters[0].i32, WriteChannelResource)
          copyMem(channel.addr, resPtr, sizeof(typeof(channel)))
          ?instance.resources.resourceDrop(parameters[0].i32,
              callDestroy = false)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[1].i32].addr)
          path = newString(parameters[2].i32)
          for i0 in 0 ..< path.len:
            path[i0] = p0[i0]
        unique = parameters[3].i32.bool
        let res = channelWriteChannelMount(instance, channel, path, unique)
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
      linker.defineFuncUnchecked("nev:plugins/channel", "new-in-memory-channel",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        let res = channelNewInMemoryChannel(instance)
        let retArea = parameters[^1].i32
        cast[ptr int32](memory[retArea + 0].addr)[] = ?instance.resources.resourceNew(
            store, res[0])
        cast[ptr int32](memory[retArea + 4].addr)[] = ?instance.resources.resourceNew(
            store, res[1])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/channel", "create-terminal", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var stdin: WriteChannelResource
        var stdout: ReadChannelResource
        var group: string
        block:
          let resPtr = ?instance.resources.resourceHostData(
              parameters[0].i32, WriteChannelResource)
          copyMem(stdin.addr, resPtr, sizeof(typeof(stdin)))
          ?instance.resources.resourceDrop(parameters[0].i32,
              callDestroy = false)
        block:
          let resPtr = ?instance.resources.resourceHostData(
              parameters[1].i32, ReadChannelResource)
          copyMem(stdout.addr, resPtr, sizeof(typeof(stdout)))
          ?instance.resources.resourceDrop(parameters[1].i32,
              callDestroy = false)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          group = newString(parameters[3].i32)
          for i0 in 0 ..< group.len:
            group[i0] = p0[i0]
        channelCreateTerminal(instance, stdin, stdout, group)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process", "[static]process.start",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        let res = processProcessStart(instance, name, args)
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process",
                                 "[method]process.stderr", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ProcessResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ProcessResource)
        let res = processStderr(instance, self[])
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process",
                                 "[method]process.stdout", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ProcessResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ProcessResource)
        let res = processStdout(instance, self[])
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/process", "[method]process.stdin",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var self: ptr ProcessResource
        self = ?instance.resources.resourceHostData(parameters[0].i32,
            ProcessResource)
        let res = processStdin(instance, self[])
        parameters[0].i32 = ?instance.resources.resourceNew(store, res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/registers",
                                 "is-replaying-commands", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = registersIsReplayingCommands(instance)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/registers",
                                 "is-recording-commands", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var register: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          register = newString(parameters[1].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        let res = registersIsRecordingCommands(instance, register)
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
      linker.defineFuncUnchecked("nev:plugins/registers", "set-register-text",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var text: string
        var register: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          text = newString(parameters[1].i32)
          for i0 in 0 ..< text.len:
            text[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          register = newString(parameters[3].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        registersSetRegisterText(instance, text, register)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/registers", "get-register-text",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
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
        var register: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          register = newString(parameters[1].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        let res = registersGetRegisterText(instance, register)
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
      linker.defineFuncUnchecked("nev:plugins/registers",
                                 "start-recording-commands", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var register: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          register = newString(parameters[1].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        registersStartRecordingCommands(instance, register)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/registers",
                                 "stop-recording-commands", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var register: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          register = newString(parameters[1].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        registersStopRecordingCommands(instance, register)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/registers", "replay-commands", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memory: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memory = cast[ptr UncheckedArray[uint8]](data(
              mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memory = cast[ptr UncheckedArray[uint8]](store.data(
              mainMemory.get.of_field.memory.addr))
        else:
          assert false
        var register: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          register = newString(parameters[1].i32)
          for i0 in 0 ..< register.len:
            register[i0] = p0[i0]
        registersReplayCommands(instance, register)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/audio", "add-audio-callback", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var fun: uint32
        var data: uint32
        fun = convert(parameters[0].i32, uint32)
        data = convert(parameters[1].i32, uint32)
        audioAddAudioCallback(instance, fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I64])
      linker.defineFuncUnchecked("nev:plugins/audio", "next-audio-sample", ty):
        var instance = cast[ptr InstanceData](store.getData())
        let res = audioNextAudioSample(instance)
        parameters[0].i64 = cast[int64](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/audio", "set-buffer-size", ty):
        var instance = cast[ptr InstanceData](store.getData())
        var size: int32
        size = convert(parameters[0].i32, int32)
        audioSetBufferSize(instance, size)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/audio", "enable-triple-buffering",
                                 ty):
        var instance = cast[ptr InstanceData](store.getData())
        var enabled: bool
        enabled = parameters[0].i32.bool
        audioEnableTripleBuffering(instance, enabled)
    if e.isErr:
      return e
