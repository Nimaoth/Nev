import std/[macros, macrocache, json, options, tables, genasts]
import misc/[custom_logger, custom_async, util, array_buffer]
import platform/filesystem

logCategory "wasi"

when defined(js):
  import std/jsffi
  export jsffi

  type WasmPtr* = distinct uint32

  type WasmModule* = ref object
    env: JsObject
    memory: JsObject
    myAlloc: proc(size: uint32): WasmPtr
    myDealloc: proc(p: WasmPtr)
    myStackAlloc: proc(size: uint32): WasmPtr
    myStackSave: proc(): WasmPtr
    myStackRestore: proc(p: WasmPtr)

  type WasmImports* = ref object
    namespace*: string
    functions: Table[cstring, proc()]
    module: WasmModule

  type WasmError* = object of CatchableError

  proc newUint8Array(memory: JsObject) {.importjs: "new Uint8Array(#.buffer)".}
  proc newUint16Array(memory: JsObject) {.importjs: "new Uint16Array(#.buffer)".}
  proc newUint32Array(memory: JsObject) {.importjs: "new Uint32Array(#.buffer)".}
  proc newInt8Array(memory: JsObject) {.importjs: "new Int8Array(#.buffer)".}
  proc newInt16Array(memory: JsObject) {.importjs: "new Int16Array(#.buffer)".}
  proc newInt32Array(memory: JsObject) {.importjs: "new Int32Array(#.buffer)".}
  proc newFloat32Array(memory: JsObject) {.importjs: "new Float32Array(#.buffer)".}
  proc newFloat64Array(memory: JsObject) {.importjs: "new Float64Array(#.buffer)".}

else:
  import wasm3, wasm3/[wasm3c, wasmconversions]

  export WasmPtr

  type WasmModule* = ref object
    env: WasmEnv

  type WasmImports* = object
    namespace*: string
    functions: seq[WasmHostProc]
    module: WasmModule

proc `$`*(p: WasmPtr): string {.borrow.}
proc `+`*(p: WasmPtr, offset: SomeNumber): WasmPtr =
  return WasmPtr(p.int + offset.int)

proc alloc*(module: WasmModule, size: uint32): WasmPtr =
  when defined(js):
    return module.myAlloc(size)
  else:
    return module.env.alloc(size)

proc stackAlloc*(module: WasmModule, size: uint32): WasmPtr =
  when defined(js):
    return module.myStackAlloc(size)
  else:
    return module.env.stackAlloc(size)

proc stackSave*(module: WasmModule): WasmPtr =
  when defined(js):
    return module.myStackSave()
  else:
    return module.env.stackSave()

proc stackRestore*(module: WasmModule, p: WasmPtr) =
  when defined(js):
    module.myStackRestore(p)
  else:
    module.env.stackRestore(p)

proc dealloc*(module: WasmModule, p: WasmPtr) =
  when defined(js):
    module.myDealloc(p)
  else:
    module.env.dealloc(p)

when defined(js):
  proc validateMemory(module: WasmModule) =
    proc isDetached(arr: JsObject): bool {.importjs: "#.length == 0".}
    if module.memory["HEAPU8"].isDetached:
      let memory = module.memory["memory"]
      module.memory["HEAPU32"] = newUint32Array(memory)
      module.memory["HEAPU16"] = newUint16Array(memory)
      module.memory["HEAPU8"] = newUint8Array(memory)
      module.memory["HEAP32"] = newInt32Array(memory)
      module.memory["HEAP16"] = newInt16Array(memory)
      module.memory["HEAP8"] = newInt8Array(memory)
      module.memory["HEAPF32"] = newFloat32Array(memory)
      module.memory["HEAPF64"] = newFloat64Array(memory)

  proc copyMem*(module: WasmModule, dest: WasmPtr, source: JsObject, len: int, offset = 0u32) =
    proc setJs(arr: JsObject, source: JsObject, pos: WasmPtr) {.importjs: "#.set(#, #)".}
    proc slice(arr: JsObject, first: int, last: int): JsObject {.importjs: "#.slice(#, #)".}

    module.validateMemory()

    let heap = module.memory["HEAPU8"]
    let s = source.slice(0, len)
    heap.setJs(s, dest)

  proc setInt32*(module: WasmModule, dest: WasmPtr, value: int32) =
    proc setJs(arr: JsObject, dest: int32, value: int32) {.importjs: "#[#] = #".}
    module.validateMemory()
    if dest.int32 mod 4 == 0:
      let heap = module.memory["HEAP32"]
      heap.setJs(dest.int32 div 4, value)
    else:
      let heap = module.memory["HEAPU8"]
      heap.setJs(dest.int32 + 0, 0xFF and (value shr 0))
      heap.setJs(dest.int32 + 1, 0xFF and (value shr 8))
      heap.setJs(dest.int32 + 2, 0xFF and (value shr 16))
      heap.setJs(dest.int32 + 3, 0xFF and (value shr 24))

  proc getInt32*(module: WasmModule, dest: WasmPtr): int32 =
    proc getJs(arr: JsObject, dest: int32): int32 {.importjs: "#[#]".}
    module.validateMemory()
    if dest.int32 mod 4 == 0:
      let heap = module.memory["HEAP32"]
      return heap.getJs(dest.int32 div 4)
    else:
      let heap = module.memory["HEAPU8"]
      result = 0
      result = result or (heap.getJs(dest.int32 + 0) shl 0)
      result = result or (heap.getJs(dest.int32 + 1) shl 8)
      result = result or (heap.getJs(dest.int32 + 2) shl 16)
      result = result or (heap.getJs(dest.int32 + 3) shl 24)

else:
  proc copyMem*(module: WasmModule, dest: WasmPtr, source: pointer, len: int, offset = 0u32) =
    module.env.copyMem(dest, source, len, offset)

  proc setInt32*(module: WasmModule, dest: WasmPtr, value: int32) =
    module.env.setMem(value, dest.uint32)

  proc getInt32*(module: WasmModule, dest: WasmPtr): int32 =
    return module.env.getFromMem(int32, dest.uint32)

proc getString*(module: WasmModule, pos: WasmPtr): cstring =
  when defined(js):
    proc indexOf(arr: JsObject, elem: uint8, start: WasmPtr): WasmPtr {.importjs: "#.indexOf(#, #)".}
    proc slice(arr: JsObject, first: WasmPtr, last: WasmPtr): JsObject {.importjs: "#.slice(#, #)".}
    proc jsDecodeString(str: JsObject): cstring {.importc.}

    module.validateMemory()

    let heap = module.memory["HEAPU8"]
    let terminator = heap.indexOf(0, pos)
    let s = heap.slice(pos, terminator)

    return jsDecodeString(s)

  else:
    return module.env.getString(pos)

proc replace(node: NimNode, target: string, newNodes: openArray[NimNode]): bool =
  for i, c in node:
    if c.kind == nnkAccQuoted and c[0].strVal == target:
      node.del(i)
      for k, newNode in newNodes:
        node.insert(i + k, newNode)
      return true
    if c.replace(target, newNodes):
      return true
  return false

# Stuff for wrapping functions
when defined(js):
  proc jsEncodeString(str: cstring): JsObject {.importc.}

macro createHostWrapper(module: WasmModule, function: typed, outFunction: untyped): untyped =
  # echo "createHostWrapper ", function.repr

  let functionBody = if function.kind == nnkSym:
    function.getImpl
  else:
    function

  var params: seq[NimNode] = @[]
  var args: seq[NimNode] = @[]

  let returnType = if functionBody[3][0].kind == nnkEmpty: bindSym"void" else: functionBody[3][0]
  let argTypes = functionBody[3]

  let returnCString = returnType.repr == "cstring"
  let returnString = returnType.repr == "string"

  if returnCString:
    params.add bindSym"WasmPtr"
  elif returnString:
    params.add bindSym"uint64"
  else:
    params.add returnType

  for i, p in argTypes[1..^1]:
    let paramType = p[1]
    # echo paramType.treeRepr

    var arg = genSym(nskParam, "p" & $i)

    let isCString = paramType.repr == "cstring"
    let isWasmModule = paramType.repr == "WasmModule" # todo: nicer way to detect WasmModule?

    if isCString:
      params.add nnkIdentDefs.newTree(arg, bindSym"WasmPtr", newEmptyNode())

      arg = genAst(arg, module):
        block:
          let res = module.getString(arg)
          res

    elif isWasmModule:
      arg = genAst(module):
        module

    else:
      params.add nnkIdentDefs.newTree(arg, paramType, newEmptyNode())

    args.add(arg)

  var body = if returnType.repr == "void":
    genAst(function):
      let x = function
      x(`parameters`)

  elif returnCString:
    when defined(js):
      genAst(function, module):
        let x = function
        let str = x(`parameters`)
        let a = jsEncodeString(str)
        proc len(arr: JsObject): int {.importjs: "#.length".}
        let p: WasmPtr = module.alloc(a.len.uint32 + 1)
        module.copyMem(p, a, a.len + 1)
        return p

    else:
      genAst(function, module):
        let x = function
        let str = x(`parameters`)
        let len = str.len
        let p: WasmPtr = module.alloc(len.uint32 + 1)
        module.copyMem(p, cast[pointer](str), len + 1)
        return p

  elif returnString:
    when defined(js):
      genAst(function, module):
        let x = function
        let str = x(`parameters`)
        let a = jsEncodeString(str.cstring)
        proc len(arr: JsObject): int {.importjs: "#.length".}
        let p: WasmPtr = module.alloc(a.len.uint32 + 1)
        module.copyMem(p, a, a.len + 1)
        return p.uint64 or (str.len.uint64 shl 32)

    else:
      genAst(function, module):
        let x = function
        let str = x(`parameters`)
        let len = str.len
        let p: WasmPtr = module.alloc(len.uint32 + 1)
        module.copyMem(p, cast[pointer](str[0].addr), len + 1)
        return p.uint64 or (len.uint64 shl 32)

  else:
    genAst(function):
      let x = function
      let res = x(`parameters`)
      return res

  discard body.replace("parameters", args)

  # defer:
  #   echo result.repr
  result = newProc(outFunction, params=params, body=body)

when defined(js):
  proc castFunction[T: proc](f: T): (proc()) {.importjs: "#".}
  proc toFunction(f: JsObject, R: typedesc): R {.importjs: "#".}

  template addFunction*(self: var WasmImports, name: static string, function: static proc) =
    block:
      createHostWrapper(self.module, function, generatedFunctionName)
      self.functions[name.cstring] = castFunction(generatedFunctionName)

else:
  proc getWasmType(typ: NimNode): string =
    # echo typ.treeRepr
    case typ.repr
    of "void": return "v"
    of "int32", "uint32", "bool": return "i"
    of "int64", "uint64": return "I"
    of "float32": return "f"
    of "float64", "float": return "F"
    of "cstring", "pointer", "WasmPtr": return "*"
    of "string": return "I"
    else:
      error(fmt"getWasmType: Invalid type {typ.repr}", typ)

  macro getWasmSignature(function: typed): string =
    # echo "getWasmSignature"
    # echo function.treeRepr

    let types = function.getType
    # echo types.treeRepr
    let returnType = if types[1].kind == nnkBracketExpr:
      types[1][1]
    else:
      types[1]

    let returnTypeWasm = returnType.getWasmType
    if returnTypeWasm == "":
      error("Invalid return type " & returnType.repr, function)

    var signature = returnTypeWasm & "("

    for i in 2..<types.len:
      if types[i].repr == "ref[WasmModule:ObjectType]":
        # todo: nicer way to ignore WasmModule?
        continue

      let argType = types[i].getWasmType
      if argType == "":
        error($(i-2) & ": Invalid argument type " & types[i].repr, function)
      signature.add argType

    signature.add ")"

    # echo function.getType.repr, " -> ", signature
    return newLit(signature)

  template addFunction*(self: var WasmImports, name: string, function: static proc) =
    block:
      template buildFunction(runtime, outFunction: untyped) =
        let module = cast[WasmModule](m3_GetUserData(runtime))
        createHostWrapper(module, function, outFunction)
      self.functions.add toWasmHostProcTemplate(buildFunction, self.namespace, name, getWasmSignature(function))

type
  WasiFD* = distinct uint32

when defined(js):
  proc createWasiJsImports(context: JsObject): WasmImports =
    new result
    result.namespace = "wasi_snapshot_preview1"
    result.addFunction "proc_exit", proc(code: int32) =
      echo "[WASI] proc_exit"

    result.addFunction "fd_close", proc(fd: int32) =
      echo "[WASI] fd_close"

    result.addFunction "fd_seek", proc(fd: int32, offset: int32, whence: int64, ret: WasmPtr): int32 =
      debugf"fd_seek {fd}, {offset}, {whence}"
      return 70

    result.addFunction "clock_time_get", proc(clk_id: int32, ignored_precision: int64, ptime: WasmPtr): int32 =
      proc js_clock_time_get(context: JsObject, clk_id: int32, ignored_precision: int64, ptime: WasmPtr): int32 {.importc.}
      return js_clock_time_get(context, clk_id, ignored_precision, ptime)

    result.addFunction "fd_fdstat_get", proc(clk_id: int32, ignored_precision: int32): int32 =
      return 0

    result.addFunction "fd_write", proc(fd: int32, iovs: WasmPtr, len: int64, ret: WasmPtr): int32 =
      let memory = context["memory"]
      # debugf"fd_write {fd}, {len}"

      proc js_fd_write(memory: JsObject, fd: int32, iovs: WasmPtr, len: int64, ret: WasmPtr): int32 {.importc.}

      if not memory.isUndefined:
        return js_fd_write(context, fd, iovs, len, ret)

proc newWasmModule*(wasmData: ArrayBuffer, importsOld: seq[WasmImports]): Future[Option[WasmModule]] {.async.} =
  try:
    when defined(js):
      proc jsLoadWasmModuleSync(wasmData: ArrayBuffer, importObject: JsObject): Future[JsObject] {.importc.}

      let importObject = newJsObject()

      var context = newJsObject()

      var imports = @importsOld
      imports.add createWasiJsImports(context)

      for imp in imports:
        var obj = newJsObject()

        for key, value in imp.functions.pairs:
          obj[key] = value

        importObject[imp.namespace.cstring] = obj

      var instance: JsObject
      try:
        instance = await jsLoadWasmModuleSync(wasmData, importObject)
      except JsError:
        raise newException(WasmError, getCurrentExceptionMsg())

      let memory = instance["exports"]["memory"]
      if not memory.isUndefined:
        context["memory"] = memory

        proc newUint8Array(memory: JsObject) {.importjs: "new Uint8Array(#.buffer)".}
        proc newUint16Array(memory: JsObject) {.importjs: "new Uint16Array(#.buffer)".}
        proc newUint32Array(memory: JsObject) {.importjs: "new Uint32Array(#.buffer)".}
        proc newInt8Array(memory: JsObject) {.importjs: "new Int8Array(#.buffer)".}
        proc newInt16Array(memory: JsObject) {.importjs: "new Int16Array(#.buffer)".}
        proc newInt32Array(memory: JsObject) {.importjs: "new Int32Array(#.buffer)".}
        proc newFloat32Array(memory: JsObject) {.importjs: "new Float32Array(#.buffer)".}
        proc newFloat64Array(memory: JsObject) {.importjs: "new Float64Array(#.buffer)".}

        context["HEAPU32"] = newUint32Array(memory)
        context["HEAPU16"] = newUint16Array(memory)
        context["HEAPU8"] = newUint8Array(memory)
        context["HEAP32"] = newInt32Array(memory)
        context["HEAP16"] = newInt16Array(memory)
        context["HEAP8"] = newInt8Array(memory)
        context["HEAPF32"] = newFloat32Array(memory)
        context["HEAPF64"] = newFloat64Array(memory)

      let myAlloc = instance["exports"]["my_alloc"].toFunction proc(size: uint32): WasmPtr
      let myDealloc = instance["exports"]["my_dealloc"].toFunction proc(p: WasmPtr)

      let myStackAlloc = instance["exports"]["stackAlloc"].toFunction proc(size: uint32): WasmPtr
      let myStackSave = instance["exports"]["stackSave"].toFunction proc(): WasmPtr
      let myStackRestore = instance["exports"]["stackRestore"].toFunction proc(p: WasmPtr)

      var res = WasmModule(env: instance, memory: context, myAlloc: myAlloc, myDealloc: myDealloc, myStackAlloc: myStackAlloc, myStackSave: myStackSave, myStackRestore: myStackRestore)
      for imp in imports.mitems:
        imp.module = res
      return res.some

    else:
      var allFunctions: seq[WasmHostProc] = @[]
      for imp in importsOld:
        allFunctions.add imp.functions

      let res = WasmModule()

      try:
        res.env = loadWasmEnv(wasmData.buffer, hostProcs=allFunctions, loadAlloc=true, allocName="my_alloc", deallocName="my_dealloc", userdata=cast[pointer](res))
      except CatchableError:
        log lvlError, &"Failed to create wasm env: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        return WasmModule.none

      var imports = @importsOld
      for imp in imports.mitems:
        imp.module = res
      return res.some

  except CatchableError:
    log lvlError, &"Failed to load wasm binary from array buffer: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return WasmModule.none

proc newWasmModule*(path: string, importsOld: seq[WasmImports]): Future[Option[WasmModule]] {.async.} =
  try:
    when defined(js):
      proc jsLoadWasmModuleAsync(path: cstring, importObject: JsObject): Future[JsObject] {.importc.}

      let importObject = newJsObject()

      var context = newJsObject()

      var imports = @importsOld
      imports.add createWasiJsImports(context)

      for imp in imports:
        var obj = newJsObject()

        for key, value in imp.functions.pairs:
          obj[key] = value

        importObject[imp.namespace.cstring] = obj

      var instance: JsObject
      try:
        instance = await jsLoadWasmModuleAsync(path.cstring, importObject)
      except JsError:
        raise newException(WasmError, getCurrentExceptionMsg())

      let memory = instance["exports"]["memory"]
      if not memory.isUndefined:
        context["memory"] = memory

        proc newUint8Array(memory: JsObject) {.importjs: "new Uint8Array(#.buffer)".}
        proc newUint16Array(memory: JsObject) {.importjs: "new Uint16Array(#.buffer)".}
        proc newUint32Array(memory: JsObject) {.importjs: "new Uint32Array(#.buffer)".}
        proc newInt8Array(memory: JsObject) {.importjs: "new Int8Array(#.buffer)".}
        proc newInt16Array(memory: JsObject) {.importjs: "new Int16Array(#.buffer)".}
        proc newInt32Array(memory: JsObject) {.importjs: "new Int32Array(#.buffer)".}
        proc newFloat32Array(memory: JsObject) {.importjs: "new Float32Array(#.buffer)".}
        proc newFloat64Array(memory: JsObject) {.importjs: "new Float64Array(#.buffer)".}

        context["HEAPU32"] = newUint32Array(memory)
        context["HEAPU16"] = newUint16Array(memory)
        context["HEAPU8"] = newUint8Array(memory)
        context["HEAP32"] = newInt32Array(memory)
        context["HEAP16"] = newInt16Array(memory)
        context["HEAP8"] = newInt8Array(memory)
        context["HEAPF32"] = newFloat32Array(memory)
        context["HEAPF64"] = newFloat64Array(memory)

      let myAlloc = instance["exports"]["my_alloc"].toFunction proc(size: uint32): WasmPtr
      let myDealloc = instance["exports"]["my_dealloc"].toFunction proc(p: WasmPtr)

      let myStackAlloc = instance["exports"]["stackAlloc"].toFunction proc(size: uint32): WasmPtr
      let myStackSave = instance["exports"]["stackSave"].toFunction proc(): WasmPtr
      let myStackRestore = instance["exports"]["stackRestore"].toFunction proc(p: WasmPtr)

      var res = WasmModule(env: instance, memory: context, myAlloc: myAlloc, myDealloc: myDealloc, myStackAlloc: myStackAlloc, myStackSave: myStackSave, myStackRestore: myStackRestore)
      for imp in imports.mitems:
        imp.module = res
      return res.some

    else:
      var allFunctions: seq[WasmHostProc] = @[]
      for imp in importsOld:
        allFunctions.add imp.functions

      let res = WasmModule()

      try:
        res.env = loadWasmEnv(fs.loadApplicationFile(path), hostProcs=allFunctions, loadAlloc=true, allocName="my_alloc", deallocName="my_dealloc", userdata=cast[pointer](res))
      except CatchableError:
        log lvlError, &"Failed to create wasm env for {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
        return WasmModule.none

      var imports = @importsOld
      for imp in imports.mitems:
        imp.module = res
      return res.some

  except CatchableError:
    log lvlError, &"Failed to load wasm binary from file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return WasmModule.none

macro createWasmWrapper(module: WasmModule, returnType: typedesc, typ: typedesc, body: untyped): untyped =
  var params: seq[NimNode] = @[]
  var args: seq[NimNode] = @[]

  let returnCString = returnType.getType[1].repr == "cstring"

  # echo "createWasmWrapper"
  # echo returnType.getTypeImpl.treeRepr
  var actualReturnType = if returnCString:
    var actualReturnType = genAst():
      typedesc[WasmPtr]
    actualReturnType
  else:
    returnType

  params.add returnType.getType[1]

  # echo actualReturnType.treeRepr

  for i, p in typ.getType[1][2..^1]:
    let argSym = genSym(nskParam, "p" & $i)

    let isCString = p.repr == "cstring"
    let isString = p.repr == "string"

    params.add nnkIdentDefs.newTree(argSym, p, newEmptyNode())

    var arg = argSym

    when defined(js):
      if isCString:
        arg = genAst(argSym):
          block:
            let a = jsEncodeString(argSym)
            proc len(arr: JsObject): int {.importjs: "#.length".}
            let p: WasmPtr = module.alloc(a.len.uint32 + 1)
            module.copyMem(p, a, argSym.len + 1)
            p

      elif isString:
        arg = genAst(argSym):
          block:
            let a = jsEncodeString(argSym.cstring)
            let p: WasmPtr = module.alloc(argSym.len.uint32 + 1)
            module.copyMem(p, a, argSym.len + 1)
            p.uint64 or (argSym.len.uint64 shl 32)

    else:
      if isCString:
        arg = genAst(argSym):
          block:
            let p: WasmPtr = module.alloc(argSym.len.uint32 + 1)
            module.copyMem(p, cast[pointer](argSym), argSym.len + 1)
            p
      elif isString:
        arg = genAst(argSym):
          block:
            let p: WasmPtr = module.alloc(argSym.len.uint32 + 1)
            module.copyMem(p, cast[ptr char](argSym.cstring), argSym.len + 1)
            p.uint64 or (argSym.len.uint64 shl 32)

    args.add(arg)

  discard body.replace("returnType", [actualReturnType])
  discard body.replace("parameters", args)

  if returnType.getType[1].repr != "void":
    if returnCString:
      body[0] = genAst(value = body[0]):
        let p = value
        let res = module.getString(p)
        return res
    else:
      body[0] = nnkReturnStmt.newTree(body[0])

  # defer:
  #   echo result.repr

  return newProc(params=params, body=body)

proc findFunction*(module: WasmModule, name: string, R: typedesc, T: typedesc): Option[T] =
  when defined(js):
    let function = module.env["exports"][name.cstring]
    if function.isUndefined:
      return T.none

    let wrapper = createWasmWrapper(module, R, T):
      function.call(nil, `parameters`).to(`returnType`)

    return wrapper.some
  else:
    try:
      let f = module.env.findFunction(name)
      if f.isNil:
        return T.none

      let wrapper = createWasmWrapper(module, R, T):
        f.call(`returnType`, `parameters`)

      return wrapper.T.some
    except CatchableError:
      return T.none