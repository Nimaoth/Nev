
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
when not declared(RopeResource):
  {.error: "Missing resource type definition for " & "RopeResource" &
      ". Define the type before the importWit statement.".}
proc textEditorGetSelection(host: WasmContext; store: ptr ContextT): Selection
proc textNewRope(host: WasmContext; store: ptr ContextT; content: string): RopeResource
proc textClone(host: WasmContext; store: ptr ContextT; self: var RopeResource): RopeResource
proc textText(host: WasmContext; store: ptr ContextT; self: var RopeResource): string
proc textDebug(host: WasmContext; store: ptr ContextT; self: var RopeResource): string
proc textSlice(host: WasmContext; store: ptr ContextT; self: var RopeResource;
               a: int64; b: int64): RopeResource
proc textSlicePoints(host: WasmContext; store: ptr ContextT;
                     self: var RopeResource; a: Cursor; b: Cursor): RopeResource
proc textGetCurrentEditorRope(host: WasmContext; store: ptr ContextT): RopeResource
proc coreBindKeys(host: WasmContext; store: ptr ContextT; context: string;
                  subcontext: string; keys: string; action: string; arg: string;
                  description: string; source: (string, int32, int32)): void
proc coreDefineCommand(host: WasmContext; store: ptr ContextT; name: string;
                       active: bool; docs: string;
                       params: seq[(string, string)]; returntype: string;
                       context: string): void
proc coreRunCommand(host: WasmContext; store: ptr ContextT; name: string;
                    args: string): void
proc defineComponent*(linker: ptr LinkerT; host: WasmContext): WasmtimeResult[
    void] =
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
              cast[ptr char](memory[dataPtrWasm0 + i0].addr)[] = res[i0]
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0
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
              cast[ptr char](memory[dataPtrWasm0 + i0].addr)[] = res[i0]
        else:
          cast[ptr int32](memory[retArea + 0].addr)[] = 0
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
        a = cast[int64](parameters[1].i64)
        b = cast[int64](parameters[2].i64)
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
        a.line = cast[int32](parameters[1].i32)
        a.column = cast[int32](parameters[2].i32)
        b.line = cast[int32](parameters[3].i32)
        b.column = cast[int32](parameters[4].i32)
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
        source[1] = cast[int32](parameters[14].i32)
        source[2] = cast[int32](parameters[15].i32)
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
