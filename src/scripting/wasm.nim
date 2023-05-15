import std/[macros, os, macrocache, strutils, json, options, tables, genasts]
import custom_logger, custom_async, compilation_config, util
import platform/filesystem

when defined(js):
  import std/jsffi

  type WasmPtr = distinct uint32

  type WasmModule* = ref object
    env: JsObject
    memory: JsObject
    myAlloc: proc(size: uint32): WasmPtr
    myDealloc: proc(size: uint32): WasmPtr

  type WasmImports* = object
    namespace: string
    functions: Table[cstring, proc()]

else:
  import wasm3

  type WasmModule* = ref object
    env: WasmEnv

  type WasmImports* = object
    namespace: string
    functions: seq[WasmHostProc]

func `-`(a, b: WasmPtr): int32 = a.int32 - b.int32

when defined(js):
  proc castFunction[T: proc](f: T): (proc()) {.importjs: "#".}
  proc toFunction(f: JsObject, R: typedesc): R {.importjs: "#".}
  template addFunction*(self: var WasmImports, name: string, function: static proc) =
    self.functions[name.cstring] = castFunction(function)

  proc encodeStringJs(str: cstring): JsObject {.importc.}
  proc decodeStringJs(str: JsObject): cstring {.importc.}

else:
  proc getWasmType(typ: NimNode): string =
    # echo typ.treeRepr
    if typ.repr == "void":
      return "v"
    elif typ.repr == "int32":
      return "i"
    elif typ.repr == "int64":
      return "I"
    elif typ.repr == "float32":
      return "f"
    elif typ.repr == "float64":
      return "F"
    elif typ.repr == "cstring":
      return "*"
    elif typ.repr == "string":
      return "*"
    elif typ.repr == "pointer":
      return "*"
    return ""

  macro getWasmSignature(function: typed): string =
    let types = function.getType
    let returnType = types[1].getWasmType
    if returnType == "":
      error("Invalid return type " & types[1].repr, function)

    var signature = returnType & "("

    for i in 2..<types.len:
      let argType = types[i].getWasmType
      if argType == "":
        error($(i-2) & ": Invalid argument type " & types[i].repr, function)
      signature.add argType

    signature.add ")"

    # echo function.getType.treeRepr, " -> ", signature
    return newLit(signature)

  template addFunction*(self: var WasmImports, name: string, function: static proc) =
    self.functions.add toWasmHostProc(function, self.namespace, name, getWasmSignature(function))
    discard

type
  WasiFD* = distinct uint32


when defined(js):
  proc createWasiJsImports(context: JsObject): WasmImports =
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

      return 0

proc newWasmModule*(path: string, importsOld: seq[WasmImports]): Future[WasmModule] {.async.} =
  when defined(js):
    proc loadWasmModule(path: cstring, importObject: JsObject): Future[JsObject] {.importc.}

    let importObject = newJsObject()

    var context = newJsObject()

    var imports = @importsOld
    imports.add createWasiJsImports(context)

    for imp in imports:
      var obj = newJsObject()

      for key, value in imp.functions.pairs:
        obj[key.cstring] = value

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
    let myDealloc = module["instance"]["exports"]["my_dealloc"].toFunction proc(size: uint32): WasmPtr

    return WasmModule(env: module, memory: context, myAlloc: myAlloc, myDealloc: myDealloc)

  else:
    var allFunctions: seq[WasmHostProc] = @[]
    for imp in importsOld:
      allFunctions.add imp.functions

    let env = loadWasmEnv(readFile(path), hostProcs=allFunctions, loadAlloc=true, allocName="my_alloc", deallocName="my_dealloc")
    return WasmModule(env: env)

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


proc alloc*(module: WasmModule, size: uint32): WasmPtr =
  when defined(js):
    return module.myAlloc(size)
  else:
    return module.env.alloc(size)

when defined(js):
  proc copyMem*(module: WasmModule, pos: WasmPtr, p: JsObject, len: int, offset = 0u32) =
    let heap = module.memory["HEAPU8"]
    proc setJs(arr: JsObject, source: JsObject, pos: WasmPtr) {.importjs: "#.set(#, #)".}
    proc slice(arr: JsObject, first: int, last: int): JsObject {.importjs: "#.slice(#, #)".}

    let s = p.slice(0, len)
    heap.setJs(s, pos)

else:
  proc copyMem*(module: WasmModule, pos: WasmPtr, p: pointer, len: int, offset = 0u32) =
    module.env.copyMem(pos, p, len, offset)

proc getString*(module: WasmModule, pos: WasmPtr): cstring =
  when defined(js):
    let heap = module.memory["HEAPU8"]

    proc indexOf(arr: JsObject, elem: uint8, start: WasmPtr): WasmPtr {.importjs: "#.indexOf(#, #)".}
    proc slice(arr: JsObject, first: WasmPtr, last: WasmPtr): JsObject {.importjs: "#.slice(#, #)".}

    let terminator = heap.indexOf(0, pos)
    let len = terminator - pos

    let s = heap.slice(pos, terminator)

    return decodeStringJs(s)

  else:
    return module.env.getString(pos)

macro newProcWithType(module: WasmModule, returnType: typedesc, typ: typedesc, body: untyped): untyped =
  var params: seq[NimNode] = @[]
  var args: seq[NimNode] = @[]

  let returnCString = returnType.getType[1].repr == "cstring"

  echo "newProcWithType"
  echo returnType.getTypeImpl.treeRepr
  var actualReturnType = if returnCString:
    var actualReturnType = genAst():
      typedesc[WasmPtr]
    actualReturnType
  else:
    returnType

  params.add returnType.getType[1]

  echo actualReturnType.treeRepr

  for i, p in typ.getType[1][2..^1]:
    var arg = genSym(nskParam, "p" & $i)

    let isCString = p.repr == "cstring"

    params.add nnkIdentDefs.newTree(arg, p, newEmptyNode())

    when defined(js):
      if isCString:
        arg = genAst(arg):
          let a = encodeStringJs(arg)
          proc len(arr: JsObject): int {.importjs: "#.length".}
          let p: WasmPtr = module.alloc(a.len.uint32 + 1)
          module.copyMem(p, a, arg.len + 1)
          p

    else:
      if isCString:
        arg = genAst(arg):
          block:
            # echo "convert arg"
            let p: WasmPtr = module.alloc(arg.len.uint32 + 1)
            # echo p.uint32

            # echo a
            module.copyMem(p, cast[pointer](arg), arg.len + 1)
            # echo wasm3.getString(module.env, p)
            p

    # echo arg.repr

    args.add(arg)

  discard body.replace("returnType", [actualReturnType])
  discard body.replace("parameters", args)

  if returnType.getType[1].repr != "void":
    if returnCString:
      body[0] = genAst(value = body[0]):
        let p = value
        # echo "convert return value"
        # echo p.uint32

        let res = module.getString(p)
        # echo cast[uint64](res.addr)
        return res
    else:
      body[0] = nnkReturnStmt.newTree(body[0])

  defer:
    echo result.repr

  return newProc(params=params, body=body)

proc findFunction*(module: WasmModule, name: string, R: typedesc, T: typedesc): Option[T] =
  when defined(js):
    let exports = module.env["instance"]["exports"]

    let function = module.env["instance"]["exports"][name.cstring]
    if function.isUndefined:
      return

    let f = newProcWithType(module, R, T):
      (`.()`(function, call, nil, `parameters`)).to(`returnType`)
      # (`.()`(exports, exported_func, `parameters`)).to(`returnType`)

    return f.some
  else:
    let f = module.env.findFunction(name)
    if f.isNil:
      return

    let wrapper = newProcWithType(module, R, T):
      f.call(`returnType`, `parameters`)

    return wrapper.some

# ----------------------------------------------------------------------------

proc imported_func(a: int32) =
  echo "2 nim imported func: ", a

proc uiae(a: int32, b: cstring) =
  echo "uiae: ", a, ", ", b

proc xvlc(): Future[void] {.async.} =
  echo "xvlc"

  var imports = WasmImports(namespace: "imports")
  imports.addFunction("imported_func", imported_func)

  # let module = await newWasmModule("simple.wasm", @[imports])
  # if findFunction(module, "exported_func", void, proc(): void).getSome(f):
  #   echo "Call exportedFunc"
  #   f()


  var imports2 = WasmImports(namespace: "env")
  imports2.addFunction("uiae", uiae)

  when defined(js):
    let module2 = await newWasmModule("maths.wasm", @[imports2])
  else:
    let module2 = await newWasmModule("temp/wasm/maths.wasm", @[imports2])
  if findFunction(module2, "foo", int32, proc(a: int32, b: int32): int32).getSome(f):
    echo f(2, 3)
  if findFunction(module2, "barc", cstring, proc(a: cstring): cstring).getSome(f):
    echo f("xvlc")
  if findFunction(module2, "barc2", cstring, proc(a: cstring): cstring).getSome(f):
    echo f("uiae")


asyncCheck xvlc()

when not defined(js):
  quit()
