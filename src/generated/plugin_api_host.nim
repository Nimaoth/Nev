
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wasmtime

{.pop.}
type
  Cursor* = object
    line*: int32
    column*: int32
  Selection* = object
    first*: Cursor
    last*: Cursor
  Vec2f* = object
    x*: float32
    y*: float32
when not declared(ViewResource):
  {.error: "Missing resource type definition for " & "ViewResource" &
      ". Define the type before the importWit statement.".}
when not declared(RopeResource):
  {.error: "Missing resource type definition for " & "RopeResource" &
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
  let f_8438941171 = instance.getExport(context, "init_plugin")
  if f_8438941171.isSome:
    assert f_8438941171.get.kind == WASMTIME_EXTERN_FUNC
    funcs.initPlugin = f_8438941171.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "init_plugin", "\'"
  let f_8438941187 = instance.getExport(context, "handle_command")
  if f_8438941187.isSome:
    assert f_8438941187.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleCommand = f_8438941187.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_command", "\'"
  let f_8438941237 = instance.getExport(context, "handle_mode_changed")
  if f_8438941237.isSome:
    assert f_8438941237.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleModeChanged = f_8438941237.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_mode_changed", "\'"
  let f_8438941238 = instance.getExport(context, "handle_view_render_callback")
  if f_8438941238.isSome:
    assert f_8438941238.get.kind == WASMTIME_EXTERN_FUNC
    funcs.handleViewRenderCallback = f_8438941238.get.of_field.func_field
  else:
    echo "Failed to find exported function \'", "handle_view_render_callback",
         "\'"

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
  if res.isErr:
    return res.toResult(void)
  
proc handleCommand*(funcs: ExportedFuncs; name: string; arg: string): WasmtimeResult[
    string] =
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
  var dataPtrWasm1: WasmPtr
  if name.len > 0:
    dataPtrWasm0 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (name.len * 1).int32, 4)
      if temp.isErr:
        return temp.toResult(string)
      temp.val
    args[0] = toWasmVal(cast[int32](dataPtrWasm0))
    block:
      for i0 in 0 ..< name.len:
        memory[dataPtrWasm0 + i0] = cast[uint8](name[i0])
  else:
    args[0] = toWasmVal(0.int32)
  args[1] = toWasmVal(cast[int32](name.len))
  if arg.len > 0:
    dataPtrWasm1 = block:
      let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field,
                            funcs.mContext, (arg.len * 1).int32, 4)
      if temp.isErr:
        return temp.toResult(string)
      temp.val
    args[2] = toWasmVal(cast[int32](dataPtrWasm1))
    block:
      for i0 in 0 ..< arg.len:
        memory[dataPtrWasm1 + i0] = cast[uint8](arg[i0])
  else:
    args[2] = toWasmVal(0.int32)
  args[3] = toWasmVal(cast[int32](arg.len))
  let res = funcs.handleCommand.addr.call(funcs.mContext,
      args.toOpenArray(0, 4 - 1), results.toOpenArray(0, 1 - 1), trap.addr).toResult(
      string)
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
  if res.isErr:
    return res.toResult(void)
  
proc textEditorGetSelection(host: HostContext; store: ptr ContextT): Selection
proc textEditorAddModeChangedHandler(host: HostContext; store: ptr ContextT;
                                     fun: uint32): int32
proc textNewRope(host: HostContext; store: ptr ContextT; content: sink string): RopeResource
proc textClone(host: HostContext; store: ptr ContextT; self: var RopeResource): RopeResource
proc textText(host: HostContext; store: ptr ContextT; self: var RopeResource): string
proc textDebug(host: HostContext; store: ptr ContextT; self: var RopeResource): string
proc textSlice(host: HostContext; store: ptr ContextT; self: var RopeResource;
               a: int64; b: int64): RopeResource
proc textSlicePoints(host: HostContext; store: ptr ContextT;
                     self: var RopeResource; a: Cursor; b: Cursor): RopeResource
proc textGetCurrentEditorRope(host: HostContext; store: ptr ContextT): RopeResource
proc coreApiVersion(host: HostContext; store: ptr ContextT): int32
proc coreGetTime(host: HostContext; store: ptr ContextT): float64
proc coreBindKeys(host: HostContext; store: ptr ContextT; context: sink string;
                  subcontext: sink string; keys: sink string;
                  action: sink string; arg: sink string;
                  description: sink string; source: sink (string, int32, int32)): void
proc coreDefineCommand(host: HostContext; store: ptr ContextT;
                       name: sink string; active: bool; docs: sink string;
                       params: sink seq[(string, string)];
                       returntype: sink string; context: sink string): void
proc coreRunCommand(host: HostContext; store: ptr ContextT; name: sink string;
                    args: sink string): void
proc coreGetSettingRaw(host: HostContext; store: ptr ContextT; name: sink string): string
proc coreSetSettingRaw(host: HostContext; store: ptr ContextT;
                       name: sink string; value: sink string): void
proc renderNewView(host: HostContext; store: ptr ContextT): ViewResource
proc renderId(host: HostContext; store: ptr ContextT; self: var ViewResource): int32
proc renderSize(host: HostContext; store: ptr ContextT; self: var ViewResource): Vec2f
proc renderSetRenderInterval(host: HostContext; store: ptr ContextT;
                             self: var ViewResource; ms: int32): void
proc renderSetRenderCommandsRaw(host: HostContext; store: ptr ContextT;
                                self: var ViewResource; buffer: uint32;
                                len: uint32): void
proc renderSetRenderCommands(host: HostContext; store: ptr ContextT;
                             self: var ViewResource; data: sink seq[uint8]): void
proc renderSetRenderWhenInactive(host: HostContext; store: ptr ContextT;
                                 self: var ViewResource; enabled: bool): void
proc renderSetPreventThrottling(host: HostContext; store: ptr ContextT;
                                self: var ViewResource; enabled: bool): void
proc renderMarkDirty(host: HostContext; store: ptr ContextT;
                     self: var ViewResource): void
proc renderSetRenderCallback(host: HostContext; store: ptr ContextT;
                             self: var ViewResource; fun: uint32; data: uint32): void
proc renderCreate(host: HostContext; store: ptr ContextT): ViewResource
proc renderFromId(host: HostContext; store: ptr ContextT; id: int32): ViewResource
proc defineComponent*(linker: ptr LinkerT; host: HostContext): WasmtimeResult[
    void] =
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/render", "[resource-drop]view",
                                 newFunctype([WasmValkind.I32], [])):
        ?host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      linker.defineFuncUnchecked("nev:plugins/text", "[resource-drop]rope",
                                 newFunctype([WasmValkind.I32], [])):
        ?host.resources.resourceDrop(parameters[0].i32, callDestroy = true)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
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
        let res = textEditorGetSelection(host, store)
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
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text", "[constructor]rope", ty):
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
        let res = textNewRope(host, store, content)
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text", "[method]rope.clone", ty):
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = textClone(host, store, self[])
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/text", "[method]rope.text", ty):
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
        let reallocImpl = caller.getExport("cabi_realloc").get.of_field.func_field
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = textText(host, store, self[])
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = block:
            var t: ptr WasmTrapT = nil
            var args: array[4, ValT]
            args[0].kind = WasmValkind.I32.ValkindT
            args[0].of_field.i32 = 0
            args[1].kind = WasmValkind.I32.ValkindT
            args[1].of_field.i32 = 0
            args[2].kind = WasmValkind.I32.ValkindT
            args[2].of_field.i32 = 4
            args[3].kind = WasmValkind.I32.ValkindT
            args[3].of_field.i32 = (res.len * 1).int32
            var results: array[1, ValT]
            ?reallocImpl.addr.call(store, args, results, t.addr)
            assert results[0].kind == WasmValkind.I32.ValkindT
            results[0].of_field.i32
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
      linker.defineFuncUnchecked("nev:plugins/text", "[method]rope.debug", ty):
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
        let reallocImpl = caller.getExport("cabi_realloc").get.of_field.func_field
        var self: ptr RopeResource
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        let res = textDebug(host, store, self[])
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = block:
            var t: ptr WasmTrapT = nil
            var args: array[4, ValT]
            args[0].kind = WasmValkind.I32.ValkindT
            args[0].of_field.i32 = 0
            args[1].kind = WasmValkind.I32.ValkindT
            args[1].of_field.i32 = 0
            args[2].kind = WasmValkind.I32.ValkindT
            args[2].of_field.i32 = 4
            args[3].kind = WasmValkind.I32.ValkindT
            args[3].of_field.i32 = (res.len * 1).int32
            var results: array[1, ValT]
            ?reallocImpl.addr.call(store, args, results, t.addr)
            assert results[0].kind == WasmValkind.I32.ValkindT
            results[0].of_field.i32
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
      linker.defineFuncUnchecked("nev:plugins/text", "[method]rope.slice", ty):
        var self: ptr RopeResource
        var a: int64
        var b: int64
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        a = convert(parameters[1].i64, int64)
        b = convert(parameters[2].i64, int64)
        let res = textSlice(host, store, self[], a, b)
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text",
                                 "[method]rope.slice-points", ty):
        var self: ptr RopeResource
        var a: Cursor
        var b: Cursor
        self = ?host.resources.resourceHostData(parameters[0].i32, RopeResource)
        a.line = convert(parameters[1].i32, int32)
        a.column = convert(parameters[2].i32, int32)
        b.line = convert(parameters[3].i32, int32)
        b.column = convert(parameters[4].i32, int32)
        let res = textSlicePoints(host, store, self[], a, b)
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/text",
                                 "[static]rope.get-current-editor-rope", ty):
        let res = textGetCurrentEditorRope(host, store)
        parameters[0].i32 = ?host.resources.resourceNew(res)
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
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/core", "bind-keys", ty):
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
        var context: string
        var subcontext: string
        var keys: string
        var action: string
        var arg: string
        var description: string
        var source: (string, int32, int32)
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          context = newString(parameters[1].i32)
          for i0 in 0 ..< context.len:
            context[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          subcontext = newString(parameters[3].i32)
          for i0 in 0 ..< subcontext.len:
            subcontext[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[4].i32].addr)
          keys = newString(parameters[5].i32)
          for i0 in 0 ..< keys.len:
            keys[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[6].i32].addr)
          action = newString(parameters[7].i32)
          for i0 in 0 ..< action.len:
            action[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[8].i32].addr)
          arg = newString(parameters[9].i32)
          for i0 in 0 ..< arg.len:
            arg[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[10].i32].addr)
          description = newString(parameters[11].i32)
          for i0 in 0 ..< description.len:
            description[i0] = p0[i0]
        block:
          let p1 = cast[ptr UncheckedArray[char]](memory[parameters[12].i32].addr)
          source[0] = newString(parameters[13].i32)
          for i1 in 0 ..< source[0].len:
            source[0][i1] = p1[i1]
        source[1] = convert(parameters[14].i32, int32)
        source[2] = convert(parameters[15].i32, int32)
        coreBindKeys(host, store, context, subcontext, keys, action, arg,
                     description, source)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32,
          WasmValkind.I32], [])
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
        coreDefineCommand(host, store, name, active, docs, params, returntype,
                          context)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32, WasmValkind.I32],
          [])
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
        var name: string
        var args: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[2].i32].addr)
          args = newString(parameters[3].i32)
          for i0 in 0 ..< args.len:
            args[i0] = p0[i0]
        coreRunCommand(host, store, name, args)
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
        let reallocImpl = caller.getExport("cabi_realloc").get.of_field.func_field
        var name: string
        block:
          let p0 = cast[ptr UncheckedArray[char]](memory[parameters[0].i32].addr)
          name = newString(parameters[1].i32)
          for i0 in 0 ..< name.len:
            name[i0] = p0[i0]
        let res = coreGetSettingRaw(host, store, name)
        let retArea = parameters[^1].i32
        if res.len > 0:
          let dataPtrWasm0 = block:
            var t: ptr WasmTrapT = nil
            var args: array[4, ValT]
            args[0].kind = WasmValkind.I32.ValkindT
            args[0].of_field.i32 = 0
            args[1].kind = WasmValkind.I32.ValkindT
            args[1].of_field.i32 = 0
            args[2].kind = WasmValkind.I32.ValkindT
            args[2].of_field.i32 = 4
            args[3].kind = WasmValkind.I32.ValkindT
            args[3].of_field.i32 = (res.len * 1).int32
            var results: array[1, ValT]
            ?reallocImpl.addr.call(store, args, results, t.addr)
            assert results[0].kind == WasmValkind.I32.ValkindT
            results[0].of_field.i32
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
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render", "[constructor]view", ty):
        let res = renderNewView(host, store)
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render", "[method]view.id", ty):
        var self: ptr ViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        let res = renderId(host, store, self[])
        parameters[0].i32 = cast[int32](res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render", "[method]view.size", ty):
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
        var self: ptr ViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        let res = renderSize(host, store, self[])
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
                                 "[method]view.set-render-interval", ty):
        var self: ptr ViewResource
        var ms: int32
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        ms = convert(parameters[1].i32, int32)
        renderSetRenderInterval(host, store, self[], ms)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]view.set-render-commands-raw", ty):
        var self: ptr ViewResource
        var buffer: uint32
        var len: uint32
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
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
                                 "[method]view.set-render-commands", ty):
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
        var self: ptr ViewResource
        var data: seq[uint8]
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
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
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]view.set-render-when-inactive", ty):
        var self: ptr ViewResource
        var enabled: bool
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        enabled = parameters[1].i32.bool
        renderSetRenderWhenInactive(host, store, self[], enabled)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]view.set-prevent-throttling", ty):
        var self: ptr ViewResource
        var enabled: bool
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        enabled = parameters[1].i32.bool
        renderSetPreventThrottling(host, store, self[], enabled)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]view.mark-dirty", ty):
        var self: ptr ViewResource
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        renderMarkDirty(host, store, self[])
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype(
          [WasmValkind.I32, WasmValkind.I32, WasmValkind.I32], [])
      linker.defineFuncUnchecked("nev:plugins/render",
                                 "[method]view.set-render-callback", ty):
        var self: ptr ViewResource
        var fun: uint32
        var data: uint32
        self = ?host.resources.resourceHostData(parameters[0].i32, ViewResource)
        fun = convert(parameters[1].i32, uint32)
        data = convert(parameters[2].i32, uint32)
        renderSetRenderCallback(host, store, self[], fun, data)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([], [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render", "[static]view.create", ty):
        let res = renderCreate(host, store)
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
  block:
    let e = block:
      var ty: ptr WasmFunctypeT = newFunctype([WasmValkind.I32],
          [WasmValkind.I32])
      linker.defineFuncUnchecked("nev:plugins/render", "[static]view.from-id",
                                 ty):
        var id: int32
        id = convert(parameters[0].i32, int32)
        let res = renderFromId(host, store, id)
        parameters[0].i32 = ?host.resources.resourceNew(res)
    if e.isErr:
      return e
