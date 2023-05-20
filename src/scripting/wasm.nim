import std/[macros, macrocache, strutils, json, options, tables, genasts, sequtils]
import custom_logger, custom_async, util
import platform/filesystem

when defined(js):
  import std/jsffi
  export jsffi

  type WasmPtr = distinct uint32

  type WasmModule* = ref object
    env: JsObject
    memory: JsObject
    myAlloc: proc(size: uint32): WasmPtr
    myDealloc: proc(p: WasmPtr)

  type WasmImports* = ref object
    namespace*: string
    functions: Table[cstring, proc()]
    module: WasmModule

else:
  import wasm3, wasm3/wasm3c

  export wasm3

  type WasmModule* = ref object
    env: WasmEnv

  type WasmImports* = object
    namespace*: string
    functions: seq[WasmHostProc]
    module: WasmModule

proc alloc*(module: WasmModule, size: uint32): WasmPtr =
  when defined(js):
    return module.myAlloc(size)
  else:
    return module.env.alloc(size)

proc dealloc*(module: WasmModule, p: WasmPtr) =
  when defined(js):
    module.myDealloc(p)
  else:
    module.env.dealloc(p)

when defined(js):
  proc copyMem*(module: WasmModule, dest: WasmPtr, source: JsObject, len: int, offset = 0u32) =
    let heap = module.memory["HEAPU8"]
    proc setJs(arr: JsObject, source: JsObject, pos: WasmPtr) {.importjs: "#.set(#, #)".}
    proc slice(arr: JsObject, first: int, last: int): JsObject {.importjs: "#.slice(#, #)".}

    let s = source.slice(0, len)
    heap.setJs(s, dest)

else:
  proc copyMem*(module: WasmModule, dest: WasmPtr, source: pointer, len: int, offset = 0u32) =
    module.env.copyMem(dest, source, len, offset)

proc getString*(module: WasmModule, pos: WasmPtr): cstring =
  when defined(js):
    proc indexOf(arr: JsObject, elem: uint8, start: WasmPtr): WasmPtr {.importjs: "#.indexOf(#, #)".}
    proc slice(arr: JsObject, first: WasmPtr, last: WasmPtr): JsObject {.importjs: "#.slice(#, #)".}
    proc decodeStringJs(str: JsObject): cstring {.importc.}

    let heap = module.memory["HEAPU8"]
    let terminator = heap.indexOf(0, pos)
    let s = heap.slice(pos, terminator)

    return decodeStringJs(s)

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
  proc encodeStringJs(str: cstring): JsObject {.importc.}

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

  if returnCString:
    params.add bindSym"WasmPtr"
  else:
    params.add returnType

  for i, p in argTypes[1..^1]:
    let paramType = p[1]
    # echo paramType.treeRepr

    var arg = genSym(nskParam, "p" & $i)

    let isCString = paramType.repr == "cstring"

    if isCString:
      params.add nnkIdentDefs.newTree(arg, bindSym"WasmPtr", newEmptyNode())

      let arg = genAst(arg, module):
        block:
          let res = module.getString(arg)
          res

      args.add(arg)
    else:
      params.add nnkIdentDefs.newTree(arg, paramType, newEmptyNode())
      args.add(arg)

  var body = if returnType.repr == "void":
    genAst(function):
      let f = function
      f(`parameters`)

  elif returnCString:
    when defined(js):
      genAst(function, module):
        let f = function
        let str = f(`parameters`)
        let a = encodeStringJs(str)
        proc len(arr: JsObject): int {.importjs: "#.length".}
        let p: WasmPtr = module.alloc(a.len.uint32 + 1)
        module.copyMem(p, a, a.len + 1)
        return p

    else:
      genAst(function, module):
        let f = function
        let str = f(`parameters`)
        let len = str.len
        let p: WasmPtr = module.alloc(len.uint32 + 1)
        module.copyMem(p, cast[pointer](str), len + 1)
        return p

  else:
    genAst(function):
      let f = function
      let res = f(`parameters`)
      return res

  discard body.replace("parameters", args)

  # defer:
  #   echo result.repr
  result = newProc(outFunction, params=params, body=body)

when defined(js):
  proc castFunction[T: proc](f: T): (proc()) {.importjs: "#".}
  proc toFunction(f: JsObject, R: typedesc): R {.importjs: "#".}

  template addFunction*(self: var WasmImports, name: string, function: static proc) =
    block:
      # let module = self.module
      createHostWrapper(self.module, function, f)
      self.functions[name.cstring] = castFunction(f)

else:
  proc getWasmType(typ: NimNode): string =
    # echo typ.treeRepr
    case typ.repr
    of "void": return "v"
    of "int32", "uint32": return "i"
    of "int64", "uint64": return "I"
    of "float32": return "f"
    of "float64": return "F"
    of "cstring", "pointer", "WasmPtr": return "*"
    else:
      return ""

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

    result.addFunction "fd_seek", proc(fd: int32, offset: int32, whence: int64, ret: pointer): int32 =
      debugf"[WASI] fd_seek {fd}, {offset}, {whence}"
      return 70

    result.addFunction "fd_write", proc(fd: int32, iovs: pointer, len: int64, ret: pointer): int32 =
      let memory = context["memory"]
      # debugf"[WASI] fd_write {fd}, {len}"

      proc js_fd_write(memory: JsObject, fd: int32, iovs: pointer, len: int64, ret: pointer): int32 {.importc.}

      if not memory.isUndefined:
        return js_fd_write(context, fd, iovs, len, ret)

proc newWasmModule*(path: string, importsOld: seq[WasmImports]): Future[Option[WasmModule]] {.async.} =
  when defined(js):
    proc loadWasmModule(path: cstring, importObject: JsObject): Future[JsObject] {.importc.}

    let importObject = newJsObject()

    var context = newJsObject()

    var imports = @importsOld
    imports.add createWasiJsImports(context)

    for imp in imports:
      var obj = newJsObject()

      for key, value in imp.functions.pairs:
        obj[key] = value

      importObject[imp.namespace.cstring] = obj

    var module = await loadWasmModule(path.cstring, importObject)

    let memory = module["instance"]["exports"]["memory"]
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

    let myAlloc = module["instance"]["exports"]["my_alloc"].toFunction proc(size: uint32): WasmPtr
    let myDealloc = module["instance"]["exports"]["my_dealloc"].toFunction proc(p: WasmPtr)

    var res = WasmModule(env: module, memory: context, myAlloc: myAlloc, myDealloc: myDealloc)
    for imp in imports.mitems:
      imp.module = res
    return res.some

  else:
    var allFunctions: seq[WasmHostProc] = @[]
    for imp in importsOld:
      allFunctions.add imp.functions

    let res = WasmModule()

    try:
      res.env = loadWasmEnv(readFile(path), hostProcs=allFunctions, loadAlloc=true, allocName="my_alloc", deallocName="my_dealloc", userdata=cast[pointer](res))
    except CatchableError:
      return WasmModule.none

    var imports = @importsOld
    for imp in imports.mitems:
      imp.module = res
    return res.some

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
    var arg = genSym(nskParam, "p" & $i)

    let isCString = p.repr == "cstring"

    params.add nnkIdentDefs.newTree(arg, p, newEmptyNode())

    when defined(js):
      if isCString:
        arg = genAst(arg):
          block:
            let a = encodeStringJs(arg)
            proc len(arr: JsObject): int {.importjs: "#.length".}
            let p: WasmPtr = module.alloc(a.len.uint32 + 1)
            module.copyMem(p, a, arg.len + 1)
            p

    else:
      if isCString:
        arg = genAst(arg):
          block:
            let p: WasmPtr = module.alloc(arg.len.uint32 + 1)
            module.copyMem(p, cast[pointer](arg), arg.len + 1)
            p

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
    let function = module.env["instance"]["exports"][name.cstring]
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

      return wrapper.some
    except CatchableError:
      return T.none