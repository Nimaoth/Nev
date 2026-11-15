import std/[strformat, os, macros, strutils, json, genasts, options, tables, sugar]
import wit, wit_gen, wasmtime

when not declared(buildOS):
  const buildOS {.magic: "BuildOS".}: string = hostOS
const windowsHost = buildOS == "windows"
const cmdPrefix = when windowsHost: "cmd /E:ON /C " else: ""

type
  Slot = object
    store*: ptr ContextT
    data: pointer
    drop: proc(data: pointer, callDestroy: bool) {.cdecl, gcsafe, raises: [].}

  WasmModuleResources* = object
    resources: seq[Slot]

proc resourceNew*[T](self: var WasmModuleResources, store: ptr ContextT, data: sink T): WasmtimeResult[int32] {.gcsafe, raises: [].} =
  proc dropImpl(b: pointer, callDestroy: bool) {.cdecl, gcsafe, raises: [].} =
    let b = cast[ptr T](b)
    if callDestroy:
      `=destroy`(b[])
    deallocShared(b)

  let d = createShared(T)
  d[] = data.ensureMove

  var index = self.resources.len
  for i, r in self.resources:
    if r.data == nil:
      index = i
      break

  if index == self.resources.len:
    self.resources.add Slot()

  self.resources[index] = Slot(store: store, data: d, drop: dropImpl)

  return wasmtime.ok(index.int32)

proc resourceHostData*(self: var WasmModuleResources, handle: int32, T: typedesc): WasmtimeResult[ptr T] {.gcsafe, raises: [].} =
  if handle < 0 or handle >= self.resources.len or self.resources[handle].data == nil:
    return wasmtime.err((ptr T), "Invalid resource index " & $handle)
  return wasmtime.ok(cast[ptr T](self.resources[handle].data))

proc resourceDrop*(self: var WasmModuleResources, handle: int32, callDestroy: bool): WasmtimeResult[void] {.gcsafe, raises: [].} =
  if handle < 0 or handle >= self.resources.len or self.resources[handle].data == nil:
    return wasmtime.err(void, "Invalid resource index " & $handle)
  self.resources[handle].drop(self.resources[handle].data, callDestroy)
  self.resources[handle] = Slot()

proc dropResources*(self: var WasmModuleResources, store: ptr ContextT, callDestroy: bool) {.gcsafe, raises: [].} =
  for r in self.resources.mitems:
    if r.store == store:
      assert r.data != nil
      r.drop(r.data, callDestroy)
      r = Slot()

func hostQuoteShell(s: string): string =
  ## Quote ``s``, so it can be safely passed to shell.
  when not defined(windows) and windowsHost:
    result = quoteShellWindows(s)
  else:
    result = quoteShell(s)


proc coreTypeToFieldName(t: CoreType): string =
  case t
  of I32: "i32"
  of I64: "i64"
  of F32: "f32"
  of F64: "f64"
  # todo
  # of V128: "v128"
  # of AnyRef: "anyref"
  # of ExternRef: "externref"
  # of FuncRef: "funcref"

proc coreTypeToWasmValkindName(t: CoreType): string =
  case t
  of I32: "I32"
  of I64: "I64"
  of F32: "F32"
  of F64: "F64"
  # todo
  # of V128: "
  # of AnyRef: "anyref"
  # of ExternRef: "externref"
  # of FuncRef: "funcref"

proc genExport*(ctx: WitContext, collectExportsBody: NimNode, funcList: NimNode, fun: WitFunc) =
  # echo &"genExport {fun}"

  let (flatFuncType, flatFuncTargetType) = ctx.flattenFuncType(fun, Lift)

  let name = fun.name.toCamelCase(false)

  let memory = ident"memory"
  let linker = ident"linker"
  let instance = ident"instance"
  let store = genAst(funcs = ident"funcs", store = ident"mContext", funcs.store)

  let returnType = if fun.results.len == 0:
    ident"void"
  elif fun.results.len == 1:
    ctx.getTypeName(fun.results[0], Return)
  else:
    var t = nnkTupleTy.newTree()
    for r in fun.results:
      t.add(ctx.getTypeName(fun.results[0], Return))
    t

  let getExportCode = genAst(name = ident(name),
      nameStr = fun.name.replace('-', '_'),
      instance = ident"instance",
      context = ident"context",
      f = ident("f"),
      funcs = ident"funcs",
      errors = ident"result",
      ):

    block:
      let f = instance.getExport(context, nameStr)
      if f.isSome:
        assert f.get.kind == WASMTIME_EXTERN_FUNC
        funcs.name = f.get.of_field.func_field
      else:
        errors.add  "Failed to find exported function '" & $nameStr & "'"

  collectExportsBody.add getExportCode

  var lowerCode = nnkStmtList.newTree()
  var liftCode = nnkStmtList.newTree()

  let args = collect:
    for p in fun.params:
      ident(p.name.toCamelCase(false))

  var dataPtrs = nnkStmtList.newTree()
  var frees = nnkStmtList.newTree()

  proc addDataPtr(): NimNode =
    result = ident("dataPtrWasm" & $dataPtrs.len)
    let c = genAst(name = result):
      var name: WasmPtr
    dataPtrs.add(c)

  var needsMemory = false
  if flatFuncType.paramsFlat:
    let loweredArgs = collect:
      for i in 0..flatFuncTargetType.params.high:
        genAst(args = ident("args"), index = i):
          args[index]

    proc storeArg(arg: NimNode, param: NimNode, typ: WitType): NimNode =
      return genAst(arg, param):
        arg = toWasmVal(param)

    proc memoryAccess(a: NimNode): NimNode =
      needsMemory = true
      genAst(memory, a):
        memory[a].addr

    proc memoryAlloc(param: NimNode, typ: WitType, depth: int): tuple[code: NimNode, dataPtr: NimNode] =
      # needsRealloc = true
      needsMemory = true
      result.dataPtr = addDataPtr() # ident("dataPtrWasm" & $depth)

      let byteSize = if typ.builtin == "string":
        1
      else:
        let userType = ctx.types[typ.index]
        ctx.byteSize(userType.listTarget)

      result.code = genAst(store, memory, param, byteSize, dataPtr = result.dataPtr, temp = ident"temp", t = ident"t", args = ident"args", results = ident"results", returnType):
        dataPtr = block:
          # todo: this memory needs to be freed
          # let temp = realloc(funcs.mRealloc.get.of_field.func_field, funcs.mContext, 0.WasmPtr, 0, 4, (param.len * byteSize).int32)
          let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field, funcs.mContext, (param.len * byteSize).int32, 4)
          if temp.isErr:
            return temp.toResult(returnType)
          temp.val
        # echo "allocated ", param.len, " * ", byteSize, " = ", (param.len * byteSize), " bytes at ", dataPtr.int

      let c = genAst(dataPtr = result.dataPtr, param, byteSize):
        ?dealloc(funcs.mDealloc.get.of_field.func_field, funcs.mContext, dataPtr, (param.len * byteSize).int32, 4)

      discard frees.add(c)

    let lowerContext = WitLowerContext(
      storeArg: storeArg,
      memoryAccess: memoryAccess,
      memoryAlloc: memoryAlloc,
      convertToCoreTypes: false,
      copyMemory: true,
    )
    ctx.lower(loweredArgs, args, fun.params, lowerCode, Parameter, lowerContext)

  else: # flatFuncType.paramsFlat
    let paramsMem = ident("paramsMem")

    let needsRetArea = not flatFuncType.paramsFlat or not flatFuncType.resultsFlat
    let paramsMemSize = max(flatFuncTargetType.toCoreType.paramsByteSize, flatFuncTargetType.toCoreType.resultsByteSize)
    if needsRetArea or true:
      let c = genAst(paramsMem, byteSize = paramsMemSize, temp = ident"temp", args = ident("args"), returnType):
        let paramsMem: WasmPtr = block:
          # let temp = realloc(funcs.mRealloc.get.of_field.func_field, funcs.mContext, 0.WasmPtr, 0, 4, byteSize.int32)
          let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field, funcs.mContext, byteSize.int32, 4)
          if temp.isErr:
            return temp.toResult(returnType)
          temp.val
        args[0] = paramsMem.int32.toWasmVal
        # echo "allocated ", param.len, " * ", byteSize, " = ", (param.len * byteSize), " bytes at ", dataPtr.int

      lowerCode.add c

    let loweredArgs = collect:
      for i in 0..flatFuncTargetType.params.high:
        genAst(args = ident("args"), index = i):
          args[index]

    var loweredPtrArgs: seq[NimNode]
    var i = 0
    for p in flatFuncTargetType.params:
      while i mod p.byteAlignment != 0:
        inc i
      let code = genAst(memory, paramsMem, nimType = p.nimTypeName.ident, index = newLit(i)):
        cast[ptr nimType](memory[paramsMem + index].addr)[]
      loweredPtrArgs.add code
      i += p.byteSize

    proc storeArg(arg: NimNode, param: NimNode, typ: WitType): NimNode =
      return genAst(arg, param):
        arg = toWasmVal(param)

    proc memoryAccess(a: NimNode): NimNode =
      needsMemory = true
      genAst(memory, a):
        memory[a].addr

    proc memoryAlloc(param: NimNode, typ: WitType, depth: int): tuple[code: NimNode, dataPtr: NimNode] =
      # needsRealloc = true
      needsMemory = true
      # result.dataPtr = ident("dataPtrWasm" & $depth)
      result.dataPtr = addDataPtr() # ident("dataPtrWasm" & $depth)

      let byteSize = if typ.builtin == "string":
        1
      else:
        let userType = ctx.types[typ.index]
        ctx.byteSize(userType.listTarget)

      result.code = genAst(store, memory, param, byteSize, dataPtr = result.dataPtr, temp = ident"temp", t = ident"t", args = ident"args", results = ident"results", returnType):
        dataPtr = block:
          # let temp = realloc(funcs.mRealloc.get.of_field.func_field, funcs.mContext, 0.WasmPtr, 0, 4, (param.len * byteSize).int32)
          let temp = stackAlloc(funcs.mStackAlloc.get.of_field.func_field, funcs.mContext, byteSize.int32, 4)
          if temp.isErr:
            return temp.toResult(returnType)
          temp.val
        # echo "allocated ", param.len, " * ", byteSize, " = ", (param.len * byteSize), " bytes at ", dataPtr.int

      let c = genAst(dataPtr = result.dataPtr, param, byteSize):
        ?dealloc(funcs.mDealloc.get.of_field.func_field, funcs.mContext, dataPtr, (param.len * byteSize).int32, 4)

      discard frees.add(c)

    let lowerContext = WitLowerContext(
      memoryAccess: memoryAccess,
      memoryAlloc: memoryAlloc,
      convertToCoreTypes: false,
      copyMemory: true,
    )
    ctx.lower(loweredPtrArgs, args, fun.params, lowerCode, Parameter, lowerContext)

  let results = if fun.results.len == 1:
    @[ident"retVal"]
  else:
    collect:
      for i in 0..fun.results.high:
        nnkBracketExpr.newTree(ident"retVal", newLit(i))
        # ident"retVal"

  # let (flatFuncTypeLift, flatFuncTargetTypeLift) = ctx.flattenFuncType(fun, Lift)
  # echo flatFuncTypeLift
  # echo flatFuncTargetTypeLift
  if flatFuncType.resultsFlat:
    if fun.results.len > 0:
      liftCode.add block:
        let t = ctx.getTypeName(fun.results[0], Return)
        genAst(retVal = ident"retVal", t):
          var retVal: t
      let resultName = genAst(results = ident"results", t = ident(flatFuncType.results[0].nimTypeName)):
        results[0].to(t)
      proc memoryAccess(a: NimNode): NimNode =
        genAst(a):
          memoryAccess(a)
      var liftContext = WitLiftContext(memoryAccess: memoryAccess)
      ctx.lift(@[resultName], results, fun.results, liftCode, Return, liftContext)

      liftCode.add block:
        genAst(retVal = ident"retVal", wasmtime = ident"wasmtime", ok = ident"ok"):
          return wasmtime.ok(retVal)

  else:
    let retArea = ident"retArea"
    # call.add retAreaPtr
    if fun.results.len == 1:
      let t = ctx.getTypeName(fun.results[0], Return)
      liftCode.add block:
        genAst(retVal = ident"retVal", returnType, results = ident"results", retArea, memory):
          var retVal: returnType
          let retArea: ptr UncheckedArray[uint8] = memory.getRawPtr(results[0].to(WasmPtr))
    else:
      liftCode.add block:
        genAst(retVal = ident"retVal", returnType, results = ident"results", retArea, memory):
          var retVal: returnType
          let retArea: ptr UncheckedArray[uint8] = memory.getRawPtr(results[0].to(WasmPtr))

    var loweredPtrArgs: seq[NimNode]
    var i = 0
    for r in flatFuncTargetType.results:
      while i mod r.byteAlignment != 0:
        inc i
      let code = genAst(retArea, nimType = r.nimTypeName.ident, index = newLit(i)):
        cast[ptr nimType](retArea[index].addr)[]
      loweredPtrArgs.add code
      i += r.byteSize

    proc memoryAccess(a: NimNode): NimNode =
      needsMemory = true
      genAst(memory, a):
        # memory[a].addr
        memory.getRawPtr(a.WasmPtr)

    var liftContext = WitLiftContext(memoryAccess: memoryAccess)
    ctx.lift(loweredPtrArgs, results, fun.results, liftCode, Return, liftContext)

    liftCode.add block:
      genAst(retVal = ident"retVal", wasmtime = ident"wasmtime", ok = ident"ok"):
        return wasmtime.ok(retVal)

  let f = genAst(name = ident(name),
      instance = ident"instance",
      context = ident"mContext",
      f = ident"f",
      args = ident"args",
      results = ident"results",
      trap = ident"trap",
      funcsType = ident"ExportedFuncs",
      funcs = ident"funcs",
      err = ident"err",
      res = ident"res",
      savePoint = ident"savePoint",
      numArgs = flatFuncType.params.len,
      numResults = flatFuncType.results.len,
      memory,
      lowerCode,
      liftCode,
      dataPtrs,
      frees,
      returnType
      ):

    proc name*(funcs: funcsType): WasmtimeResult[returnType] =
      var args: array[max(1, numArgs), ValT]
      var results: array[max(1, numResults), ValT]
      var trap: ptr WasmTrapT = nil
      # todo: don't add if not needed
      var memory = funcs.mem
      let savePoint = stackSave(funcs.mStackSave.get.of_field.func_field, funcs.mContext)
      defer:
        # if savePoint.isOk:
        discard stackRestore(funcs.mStackRestore.get.of_field.func_field, funcs.mContext, savePoint.val)
      dataPtrs
      lowerCode
      let res = funcs.name.addr.call(funcs.context,
          args.toOpenArray(0, numArgs - 1), results.toOpenArray(0, numResults - 1), trap.addr).toResult(returnType)

      if trap != nil:
        return trap.toResult(returnType)

      # frees

      if res.isErr:
        return res.toResult(returnType)

      liftCode

      # todo: results

  for p in fun.params:
    let t = ctx.getTypeName(p.typ, Parameter)
    f[3].add(nnkIdentDefs.newTree(ident(p.name.toCamelCase(false)), t, newEmptyNode()))

  funcList.add f

##### patch begin - Avoid Nim 2.4 VM corruption by moving the macro body into a procedure
proc importWitImplGen(witPath: string, cacheFile: string, nameMap: Table[string, string], worldName: string, dir: string, instanceType: NimNode): NimNode =
  ##### patch end
  let path = if witPath.isAbsolute:
    witPath
  else:
    dir / witPath

  let cmd = &"wasm-tools component wit {path.hostQuoteShell} --json"
  hint "Running: " & cmdPrefix & cmd
  let res = gorgeEx(cmdPrefix & cmd)
  if res.exitCode != 0:
    error("Failed to read wit files:\n" & res.output)

  let json = try:
    res.output.parseJson()
  except Exception as e:
    error("Failed to decode json from wit: " & e.msg & "\n" & res.output)

  var ctx = newWitContext(json)
  ctx.nameMap = nameMap
  ctx.useCustomBuiltinTypes = false

  let typeSection = ctx.genTypeSection(host=true)

  var linker = ident"linker"
  let instance = ident"instance"
  var store = ident"store"
  var stackAllocFunc = ident"stackAllocFunc"
  var defineComponentFun = genAst(linker):
    proc defineComponent*(linker: ptr LinkerT): WasmtimeResult[void] =
      discard

  let funDeclTempl = genAst(instance, instanceType):
    proc name*(instance: ptr instanceType): void

  var funDeclarations = nnkStmtList.newTree()
  var defines = nnkStmtList.newTree()
  defineComponentFun[6] = defines

  let world = ctx.getWorld(worldName)

  for t in ctx.types:
    if t.refIndex.isSome:
      continue

    case t.kind
    of Resource:
      let dropName = "[resource-drop]" & t.name
      let code = genAst(instance, instanceType, linker, env = t.env, name = t.name, dropName, typ = ident(ctx.getNimName(t.name, true)), e = ident"e"):
        block:
          let e = block:
            linker.defineFuncUnchecked(env, dropName, newFunctype([WasmValkind.I32], [])):
              var instance = cast[ptr instanceType](store.getData())
              instance.resources.resourceDrop(parameters[0].i32, callDestroy=true)
          if e.isErr:
            return e

      defines.add code
      discard

    else:
      discard

  var exportedFuncsType = genAst(name = ident"ExportedFuncs"):
    type name* = object
      mContext*: ptr ContextT
      mMemory*: Option[ExternT]
      mRealloc*: Option[ExternT]
      mDealloc*: Option[ExternT]
      mStackAlloc*: Option[ExternT]
      mStackSave*: Option[ExternT]
      mStackRestore*: Option[ExternT]

  let collectExports = genAst(name = ident"collectExports",
      instance = ident"instance",
      context = ident"context",
      mContext = ident"mContext",
      mMemory = ident"mMemory",
      mRealloc = ident"mRealloc",
      mDealloc = ident"mDealloc",
      mStackAlloc = ident"mStackAlloc",
      mStackSave = ident"mStackSave",
      mStackRestore = ident"mStackRestore",
      f = ident"f",
      numArgs = ident"numArgs",
      numResults = ident"numResults",
      args = ident"args",
      results = ident"results",
      trap = ident"trap",
      funcsType = ident"ExportedFuncs",
      funcs = ident"funcs",
      err = ident"err"):

    proc name*(funcs: var funcsType, instance: InstanceT, context: ptr ContextT): seq[string] =
      funcs.mContext = context
      funcs.mMemory = instance.getExport(context, "memory")
      funcs.mRealloc = instance.getExport(context, "cabi_realloc")
      funcs.mDealloc = instance.getExport(context, "cabi_dealloc")
      funcs.mStackAlloc = instance.getExport(context, "mem_stack_alloc")
      funcs.mStackSave = instance.getExport(context, "mem_stack_save")
      funcs.mStackRestore = instance.getExport(context, "mem_stack_restore")

  let getMem = genAst(name = ident"mem",
      instance = ident"instance",
      context = ident"context",
      mContext = ident"mContext",
      mMemory = ident"mMemory",
      f = ident"f",
      numArgs = ident"numArgs",
      numResults = ident"numResults",
      args = ident"args",
      results = ident"results",
      trap = ident"trap",
      funcsType = ident"ExportedFuncs",
      funcs = ident"funcs",
      err = ident"err"):
    proc mem(funcs: funcsType): WasmMemory =
      if funcs.mMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
        return initWasmMemory(funcs.mMemory.get.of_field.sharedmemory)
      elif funcs.mMemory.get.kind == WASMTIME_EXTERN_MEMORY:
        return initWasmMemory(funcs.mContext, funcs.mMemory.get.of_field.memory.addr)

  for f in world.exports:
    exportedFuncsType[0][2][2].add nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident"*", ident(f.name.toCamelCase(false))),
      ident"FuncT", newEmptyNode())
    ctx.genExport(collectExports[6], funDeclarations, f)

  for fun in world.funcs:
    var body = nnkStmtList.newTree()

    let funcNimName = case fun.kind
    of Freestanding:
      fun.name
    of Constructor:
      let i = fun.name.find("]")
      assert i != -1
      "new-" & fun.name[i + 1..^1]

    of Static:
      let i = fun.name.find(".")
      assert i != -1
      let typeName = fun.name["[static]".len..<i]
      let funName = fun.name[i + 1..^1]
      typeName.toCamelCase(false) & funName.toCamelCase(true)

    of Method:
      let i = fun.name.find(".")
      assert i != -1
      fun.name[i + 1..^1]

    let (flatFuncType, flatFuncTargetType) = ctx.flattenFuncType(fun, Lift)

    let implName = if fun.interfac.isSome:
      ident(fun.interfaceName.toCamelCase(false) & funcNimName.toCamelCase(true) & "")
    else:
      ident(funcNimName.toCamelCase(false) & "")

    let memory = ident"memory"
    var needsMemory = false
    var needsRealloc = false

    var decl = funDeclTempl.copy()
    decl[0] = nnkPostfix.newTree(ident"*", implName)

    var call = nnkCall.newTree(implName, instance)
    funDeclarations.add decl

    if fun.results.len > 0:
      # todo: multiple return values
      decl[3][0] = ctx.getTypeName(fun.results[0], Return)

    # args
    for i, p in fun.params:
      var name = ident(p.name.toCamelCase(false))

      let paramKind = ctx.getParamTypeKind(p.typ)

      if paramKind == BorrowedResource:
        let c = genAst(name):
          name[]
        call.add c
      else:
        call.add name

      proc passAsSink(t: WitType): bool =
        if t.builtin == "string":
          return true
        elif t.builtin != "":
          return false
        let kind = ctx.types[t.index].kind
        case kind
        of List:
          return true
        of Record, Variant, Tuple:
          for f in ctx.types[t.index].fields:
            if f.typ.passAsSink:
              return true
        of Option:
          return ctx.types[t.index].optionTarget.passAsSink()
        of Result:
          if ctx.types[t.index].resultOkTarget.passAsSink():
            return true
          if ctx.types[t.index].resultErrTarget.passAsSink():
            return true
        else:
          discard
        return false

      var declParamType = ctx.getTypeName(p.typ, Parameter)
      if paramKind == BorrowedResource:
        declParamType = nnkVarTy.newTree(declParamType)
      elif p.typ.passAsSink():
        declParamType = nnkCommand.newTree(ident"sink", declParamType)

      decl[3].add nnkIdentDefs.newTree(name, declParamType, newEmptyNode())

      if p.typ.builtin != "":
        let typ = ctx.getTypeName(p.typ, Field)
        let c = genAst(name, typ, i):
          var name: typ
        body.add c

      else:
        let userType = ctx.types[p.typ.index]
        if userType.kind == Handle:
          let typ = ctx.getTypeName(p.typ, Field)
          if userType.owned:
            let c = genAst(name, ptrName = ident(name.repr & "Ptr"), typ, i):
              var name: typ
            body.add c

          else:
            let c = genAst(name, typ, i):
              var name: ptr typ
            body.add c

        else:
          let typ = ctx.getTypeName(p.typ, Field)
          let c = genAst(name, typ, i):
            var name: typ
          body.add c

    proc resourceAccess(typ: WitType, arg: NimNode, param: NimNode): NimNode =
      let userType = ctx.types[typ.index]
      assert userType.kind == Handle
      let typ = ctx.getTypeName(typ, Field)
      if userType.owned:
        return genAst(instance, arg, param, ptrName = ident("resPtr"), typ):
          block:
            let ptrName = ?instance.resources.resourceHostData(arg, typ)
            # Would be nicer to do:
            #   param = ptrName[].ensureMove
            # but that doesn't compile, so to avoid the `=copy` hook use raw memory copy
            copyMem(param.addr, ptrName, sizeof(typeof(param)))
            ?instance.resources.resourceDrop(arg, callDestroy=false)

      else:
        return genAst(instance, arg, param, typ):
          param = ?instance.resources.resourceHostData(arg, typ)

    # lift parameters
    if flatFuncType.paramsFlat:
      let args = collect:
        for p in fun.params:
          ident(p.name.toCamelCase(false))

      let loweredArgs = collect:
        for i in 0..flatFuncTargetType.params.high:
          let field = flatFuncTargetType.params[i].toCoreType.coreTypeToFieldName
          genAst(i, field = ident(field)):
            parameters[i].field

      proc memoryAccess(a: NimNode): NimNode =
        needsMemory = true
        genAst(memory, a):
          memory[a].addr

      var liftContext = WitLiftContext(memoryAccess: memoryAccess, resourceAccess: resourceAccess)
      ctx.lift(loweredArgs, args, fun.params, body, Parameter, liftContext)
    else:
      let args = collect:
        for p in fun.params:
          ident(p.name.toCamelCase(false))

      var i = 0
      let loweredArgs = collect:
        for p in flatFuncTargetType.params:
          while i mod p.byteAlignment != 0:
            inc i
          needsMemory = true
          let field = p.toCoreType.coreTypeToFieldName
          let c = genAst(i, memory, t = p.nimTypeName.ident, field = ident(field)):
            cast[ptr t](memory[parameters[0].i32 + i].addr)[]
          i += p.byteSize
          c

      proc memoryAccess(a: NimNode): NimNode =
        needsMemory = true
        genAst(memory, a):
          memory[a].addr

      var liftContext = WitLiftContext(memoryAccess: memoryAccess, resourceAccess: resourceAccess)
      ctx.lift(loweredArgs, args, fun.params, body, Parameter, liftContext)

    # call
    if fun.results.len > 0:
      var res = ident"res"

      var callAndResult = genAst(res, call):
        let res = call
        # parameters[0] = res.toVal # todo

      proc lowerHandle(param: NimNode): NimNode =
        return genAst(instance, param):
          ?instance.resources.resourceNew(store, param)

      let r = fun.results[0]
      if ctx.isOwnedHandle(r):
        callAndResult = genAst(instance, res, call):
          let res = call
          parameters[0].i32 = ?instance.resources.resourceNew(store, res)

        body.add callAndResult

      else:
        body.add callAndResult

        # lower results
        if flatFuncType.resultsFlat:
          # todo: multi return values
          let field = ident(flatFuncType.results[0].toCoreType.coreTypeToFieldName)
          let t = ident(flatFuncType.results[0].toCoreType.nimTypeName)
          let c = genAst(field, t, res):
            parameters[0].field = cast[t](res)
          body.add c
        else:
          let retArea = ident"retArea"
          block:
            let c = genAst(retArea):
              let retArea = parameters[^1].i32
            body.add c

          var loweredPtrArgs: seq[NimNode]
          var i = 0
          for r in flatFuncTargetType.results:
            while i mod r.byteAlignment != 0:
              inc i
            needsMemory = true
            let code = genAst(memory, retArea, nimType = r.nimTypeName.ident, index = i):
              # cast[ptr nimType](memory[retArea + index].addr)[]
              memory[retArea + index].addr
            loweredPtrArgs.add code
            i += r.byteSize

          let results = if fun.results.len == 1:
            @[res]
          else:
            collect:
              for i in 0..fun.results.high:
                nnkBracketExpr.newTree(res, newLit(i))

          proc storeArg(arg: NimNode, param: NimNode, typ: WitType): NimNode =
            let r = ctx.flattenType(typ)[0] # todo: this could be done more efficiently
            return genAst(arg, param, nimType = r.nimTypeName.ident):
              cast[ptr nimType](arg)[] = param

          proc memoryAccess(a: NimNode): NimNode =
            needsMemory = true
            genAst(memory, a):
              memory[a].addr

          proc memoryAlloc(param: NimNode, typ: WitType, depth: int): tuple[code: NimNode, dataPtr: NimNode] =
            needsRealloc = true
            needsMemory = true
            result.dataPtr = ident("dataPtrWasm" & $depth)

            let byteSize = if typ.builtin == "string":
              1
            else:
              let userType = ctx.types[typ.index]
              ctx.byteSize(userType.listTarget)

            result.code = genAst(store, stackAllocFunc, param, byteSize, dataPtr = result.dataPtr, t = ident"t", args = ident"args", results = ident"results", temp = ident"temp"):
              let dataPtr = int32(?stackAlloc(stackAllocFunc, store, (param.len * byteSize).int32, 4))

          var lowerContext = WitLowerContext(memoryAccess: memoryAccess, memoryAlloc: memoryAlloc, convertToCoreTypes: false, copyMemory: true, lowerHandle: lowerHandle, storeArg: storeArg)
          ctx.lower(loweredPtrArgs, results, fun.results, body, Return, lowerContext)
          discard

    else:
      body.add call

    var parameterTypes = nnkBracket.newTree()
    var resultTypes = nnkBracket.newTree()

    for t in flatFuncType.params:
      let name = t.toCoreType.coreTypeToWasmValkindName
      parameterTypes.add nnkDotExpr.newTree(ident"WasmValkind", ident(name))

    for t in flatFuncType.results:
      let name = t.toCoreType.coreTypeToWasmValkindName
      if flatFuncType.resultsFlat:
        resultTypes.add nnkDotExpr.newTree(ident"WasmValkind", ident(name))
      else:
        parameterTypes.add nnkDotExpr.newTree(ident"WasmValkind", ident(name))

    let instanceDecl = genAst(instance, instanceType, store):
      var instance = cast[ptr instanceType](store.getData())

    var memoryDecl = if needsMemory:
      genAst(instance, store, memoryName = memory, mainMemory = ident"mainMemory"):
        var mainMemory = caller.getExport("memory")
        if mainMemory.isNone:
          mainMemory = instance.getMemoryFor(caller)
        var memoryName: ptr UncheckedArray[uint8] = nil
        if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
          memoryName = cast[ptr UncheckedArray[uint8]](data(mainMemory.get.of_field.sharedmemory))
        elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
          memoryName = cast[ptr UncheckedArray[uint8]](store.data(mainMemory.get.of_field.memory.addr))
        else:
          assert false
    else:
      nnkStmtList.newTree()

    var stackAllocDecl = if needsRealloc:
      genAst(stackAllocFunc):
        let stackAllocFunc = caller.getExport("mem_stack_alloc").get.of_field.func_field
    else:
      nnkStmtList.newTree()

    let code = genAst(linker, env = fun.env, name = fun.name, body, e = ident"e", ty = ident"ty", parameterTypes, resultTypes, instanceDecl, memoryDecl, stackAllocDecl):
      block:
        let e = block:
          var ty: ptr WasmFunctypeT = newFunctype(parameterTypes, resultTypes)
          linker.defineFuncUnchecked(env, name, ty):
            instanceDecl
            memoryDecl
            stackAllocDecl
            body

        if e.isErr:
          return e

    defines.add code

  let code = genAst(typeSection, funDeclarations, defineComponentFun, exportedFuncsType, collectExports, getMem):
    {.push hint[DuplicateModuleImport]:off.}
    import std/[options]
    from std/unicode import Rune
    import results, wasmtime
    {.pop.}

    typeSection

    exportedFuncsType

    getMem
    collectExports

    funDeclarations

    defineComponentFun

  let cacheFile = if cacheFile.isAbsolute:
    cacheFile
  else:
    dir / cacheFile

  hint "Write api to " & cacheFile
  writeFile(cacheFile, code.repr)

  return nnkStmtList.newTree()

##### patch begin - Delegate the macro to the generator procedure
macro importWitImpl(witPath: static[string], cacheFile: static[string], nameMap: static[Table[string, string]], worldName: static[string], dir: static[string], instanceType: untyped): untyped =
  importWitImplGen(witPath, cacheFile, nameMap, worldName, dir, instanceType)
##### patch end

template importWit*(witPath: static[string], instanceType: untyped, body: untyped): untyped =
  var cacheFile {.compiletime, inject.} = "host.nim"
  var world {.compiletime, inject.} = ""
  var nameMap {.compiletime.} = initTable[string, string]()
  template mapName(name: static[string], newName: untyped): untyped =
    nameMap[name] = $newName

  static:
    body

  importWitImpl(witPath, cacheFile, nameMap, world, instantiationInfo(-1, true).filename.replace("\\", "/").splitPath.head, instanceType)
