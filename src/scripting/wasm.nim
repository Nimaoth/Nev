import std/[macros, os, macrocache, strutils, json, options, tables]
import custom_logger, custom_async, compilation_config, util
import platform/filesystem

when defined(js):
  import std/jsffi

  type WasmModule* = ref object
    env: JsObject

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

when defined(js):
  proc castFunction[T: proc](f: T): (proc()) {.importjs: "#".}
  template addFunction*(self: var WasmImports, name: string, function: static proc) =
    self.functions[name.cstring] = castFunction(function)

else:
  proc getWasmType(typ: NimNode): string =
    echo typ.treeRepr
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

    return WasmModule(env: module)

  else:
    var allFunctions: seq[WasmHostProc] = @[]
    for imp in importsOld:
      allFunctions.add imp.functions

    let env = loadWasmEnv(readFile(path), hostProcs=allFunctions)
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

macro newProcWithType(returnType: typedesc, typ: typedesc, body: untyped): untyped =
  var params: seq[NimNode] = @[]
  var args: seq[NimNode] = @[]

  params.add returnType.getType[1]
  for i, p in typ.getType[1][2..^1]:
    let arg = genSym(nskParam, "p" & $i)
    params.add nnkIdentDefs.newTree(arg, p, newEmptyNode())
    args.add(arg)

  discard body.replace("returnType", [returnType])
  discard body.replace("parameters", args)

  if returnType.getType[1].repr != "void":
    body[0] = nnkReturnStmt.newTree(body[0])

  defer:
    echo result.repr

  return newProc(params=params, body=body)

dumpTree:
  proc a(a: int32): float32 = discard

proc findFunction*(module: WasmModule, name: string, R: typedesc, T: typedesc): Option[T] =
  when defined(js):
    let exports = module.env["instance"]["exports"]

    let function = module.env["instance"]["exports"][name.cstring]
    if function.isUndefined:
      return

    let f = newProcWithType(R, T):
      (`.()`(function, call, nil, `parameters`)).to(`returnType`)
      # (`.()`(exports, exported_func, `parameters`)).to(`returnType`)

    return f.some
  else:
    let f = module.env.findFunction(name)
    if f.isNil:
      return

    let wrapper = newProcWithType(R, T):
      f.call(`returnType`, `parameters`)

    return wrapper.some

# ----------------------------------------------------------------------------

proc imported_func(a: int32) =
  echo "2 nim imported func: ", a

proc uiae(a: int64, b: cstring) =
  echo "uiae: ", a, ", ", b

proc xvlc(): Future[void] {.async.} =
  echo "xvlc"

  var imports = WasmImports(namespace: "imports")
  imports.addFunction("imported_func", imported_func)

  let module = await newWasmModule("simple.wasm", @[imports])
  if findFunction(module, "exported_func", void, proc(): void).getSome(f):
    echo "Call exportedFunc"
    f()


  var imports2 = WasmImports(namespace: "env")
  imports2.addFunction("uiae", uiae)

  let module2 = await newWasmModule("maths.wasm", @[imports2])
  if findFunction(module2, "barc", cstring, proc(a: cstring): cstring).getSome(f):
    echo f("barc")
  if findFunction(module2, "barc2", cstring, proc(a: cstring): cstring).getSome(f):
    echo f("barc2")


asyncCheck xvlc()

when not defined(js):
  quit()
