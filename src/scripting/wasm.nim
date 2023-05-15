import std/[macros, os, macrocache, strutils, json, options, tables]
import custom_logger, custom_async, compilation_config, util
import platform/filesystem

when defined(js):
  import std/jsffi

  type WasmModule* = ref object
    env: JsObject

  type WasmImports* = object
    functions: Table[cstring, proc()]

else:
  import wasm3

  type WasmModule* = ref object
    env: WasmEnv

  type WasmImports* = object
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
    self.functions.add toWasmHostProc(function, "imports", name, getWasmSignature(function))
    discard

proc newWasmModule*(path: string, imports: WasmImports): Future[WasmModule] {.async.} =
  when defined(js):
    proc loadWasmModule(path: cstring, importObject: JsObject): Future[JsObject] {.importc.}

    let importObject = newJsObject()

    importObject["imports"] = block:
      var obj = newJsObject()

      for key, value in imports.functions.pairs:
        obj[key.cstring] = value

      obj

    var module = await loadWasmModule(path.cstring, importObject)
    return WasmModule(env: module)

  else:
    let env = loadWasmEnv(readFile(path), hostProcs=imports.functions)
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

# BracketExpr
#   Sym "typeDesc"
#   BracketExpr
#     Sym "proc"
#     Sym "int32"
#     Sym "float32"
macro newProcWithType(returnType: typedesc, typ: typedesc, body: untyped): untyped =
  var params: seq[NimNode] = @[]
  var args: seq[NimNode] = @[]
  for i, p in typ.getType[1][1..^1]:
    echo p.treeRepr
    if i == 0:
      params.add p
    else:
      let arg = genSym(nskParam, "p" & $i)
      params.add nnkIdentDefs.newTree(arg, p, newEmptyNode())
      args.add(arg)

  echo body.repr
  defer:
    echo result.repr
    echo result.treeRepr

  # let returnType = typ.getType[1][1]

  echo body.treeRepr

  # var body = body.copy
  discard body.replace("returnType", [returnType])
  discard body.replace("parameters", args)

  if returnType.repr != "void":
    body[0] = nnkReturnStmt.newTree(body[0])
  echo body.repr

  return newProc(params=params, body=body)

dumpTree:
  proc a(a: int32): float32 = discard

proc findFunction*(module: WasmModule, name: string, R: typedesc, T: typedesc): Option[T] =
  when defined(js):
    let exports = module.env["instance"]["exports"]

    if module.env["instance"]["exports"][name.cstring].isUndefined:
      return

    let f = newProcWithType(R, T):
      (`.()`(exports, exported_func, `parameters`)).to(`returnType`)


    # let f = proc() =
    #   `.()`(exports, exported_func)

    return f.some
  else:
    let f = module.env.findFunction(name)
    if f.isNil:
      return

    let wrapper = newProcWithType(R, T):
      # echo "lol"
      f.call(`returnType`, `parameters`)

    # let wrapper = proc() =
    #   f.call(void)

    return wrapper.some

# ----------------------------------------------------------------------------

proc imported_func(a: int32) =
  echo "2 nim imported func: ", a

proc uiae(): Future[void] {.async.} =
  echo "uiea"

  var imports = WasmImports()
  imports.addFunction("imported_func", imported_func)

  let module = await newWasmModule("simple.wasm", imports)
  echo "loaded module "
  if findFunction(module, "exported_func", int32, proc(a: int64, b: float64): int32).getSome(f):
    echo "Call exportedFunc"
    echo f(456, 123.45)

asyncCheck uiae()

when not defined(js):
  quit()
