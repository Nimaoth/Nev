import std/[macros, macrocache, json, options, tables, genasts]
import misc/[custom_logger, custom_async, util, array_buffer, id]
import vfs

logCategory "wasi"

import wasm3, wasm3/[wasm3c, wasmconversions]

export WasmPtr, PFunction

type WasmModule* = ref object
  env: WasmEnv
  path*: string
  userData: Table[string, ref RootObj]

type WasmImports* = object
  namespace*: string
  functions: seq[WasmHostProc]
  module: WasmModule

proc `$`*(p: WasmPtr): string {.borrow.}
proc `+`*(p: WasmPtr, offset: SomeNumber): WasmPtr =
  return WasmPtr(p.int + offset.int)

proc addUserData*[T](self: WasmModule, userData: T) =
  mixin wasmUserDataKey
  let key = T.wasmUserDataKey
  self.userData[key] = userData

proc getUserData*(self: WasmModule, T: typedesc): T =
  mixin wasmUserDataKey
  let key = T.wasmUserDataKey
  self.userData.withValue(key, val):
    return val[].T
  raiseAssert("No userdata for " & $T)

proc alloc*(module: WasmModule, size: uint32): WasmPtr =
  return module.env.alloc(size)

proc stackAlloc*(module: WasmModule, size: uint32): WasmPtr =
  return module.env.stackAlloc(size)

proc stackSave*(module: WasmModule): WasmPtr =
  return module.env.stackSave()

proc stackRestore*(module: WasmModule, p: WasmPtr) =
  module.env.stackRestore(p)

proc dealloc*(module: WasmModule, p: WasmPtr) =
  module.env.dealloc(p)

proc copyMem*(module: WasmModule, dest: WasmPtr, source: pointer, len: int, offset = 0u32) =
  module.env.copyMem(dest, source, len, offset)

proc setInt32*(module: WasmModule, dest: WasmPtr, value: int32) =
  module.env.setMem(value, dest.uint32)

proc getInt32*(module: WasmModule, dest: WasmPtr): int32 =
  return module.env.getFromMem(int32, dest.uint32)

proc getString*(module: WasmModule, pos: WasmPtr): cstring =
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
    genAst(function, module):
      let x = function
      let str = x(`parameters`)
      let len = str.len
      let p: WasmPtr = module.alloc(len.uint32 + 1)
      module.copyMem(p, cast[pointer](str), len + 1)
      return p

  elif returnString:
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
  result.addPragma(nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree(bindSym"CatchableError")))

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
      {.push hint[XCannotRaiseY]:off.}
      createHostWrapper(module, function, outFunction)
      {.pop.}
    self.functions.add toWasmHostProcTemplate(buildFunction, self.namespace, name, getWasmSignature(function))

type
  WasiFD* = distinct uint32

proc newWasmModule*(wasmData: ArrayBuffer, importsOld: seq[WasmImports]): Future[Option[WasmModule]] {.async.} =
  try:
    var allFunctions: seq[WasmHostProc] = @[]
    for imp in importsOld:
      allFunctions.add imp.functions

    let res = WasmModule()

    try:
      res.env = loadWasmEnv(wasmData.buffer, hostProcs=allFunctions, loadAlloc=true, allocName="my_alloc", deallocName="my_dealloc", userdata=cast[pointer](res))
    except:
      log lvlError, &"Failed to create wasm env: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return WasmModule.none

    var imports = @importsOld
    for imp in imports.mitems:
      imp.module = res
    return res.some

  except CatchableError:
    log lvlError, &"Failed to load wasm binary from array buffer: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return WasmModule.none

proc newWasmModule*(path: string, importsOld: seq[WasmImports], vfs: VFS): Future[Option[WasmModule]] {.async.} =
  try:
    var allFunctions: seq[WasmHostProc] = @[]
    for imp in importsOld:
      allFunctions.add imp.functions

    let res = WasmModule(path: path)

    var content: string
    try:
      content = await vfs.read(path, {Binary})

      if content.len == 0:
        log lvlError, &"Failed to load wasm module file {path}"
        return WasmModule.none
    except CatchableError:
      log lvlError, &"Failed to load wasm module file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return WasmModule.none

    try:
      res.env = loadWasmEnv(content, hostProcs=allFunctions, loadAlloc=true, allocName="my_alloc", deallocName="my_dealloc", userdata=cast[pointer](res))
    except:
      log lvlError, &"Failed to create wasm env for {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      return WasmModule.none

    var imports = @importsOld
    for imp in imports.mitems:
      imp.module = res
    return res.some

  except CatchableError:
    log lvlError, &"Failed to load wasm binary from file {path}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return WasmModule.none

macro createWasmWrapper(returnType: typedesc, typ: typedesc, body: untyped): untyped =
  # echo "createWasmWrapper"

  var params: seq[NimNode] = @[]
  var args: seq[NimNode] = @[]

  let returnCString = returnType.getType[1].repr == "cstring"

  var actualReturnType = if returnCString:
    var actualReturnType = genAst():
      typedesc[WasmPtr]
    actualReturnType
  else:
    returnType

  params.add returnType.getType[1]

  let moduleSym = genSym(nskParam, "module")
  let pfunSym = genSym(nskParam, "pfun")
  params.add nnkIdentDefs.newTree(moduleSym, typ.getType[1][2], newEmptyNode())
  params.add nnkIdentDefs.newTree(pfunSym, typ.getType[1][3], newEmptyNode())

  for i, p in typ.getType[1][4..^1]:
    let argSym = genSym(nskParam, "p" & $i)
    let repr = p.repr
    let isCString = p.repr == "cstring"
    let isString = p.repr == "string"

    params.add nnkIdentDefs.newTree(argSym, p, newEmptyNode())

    var arg = argSym

    if isCString:
      arg = genAst(argSym, moduleSym):
        block:
          let p: WasmPtr = moduleSym.alloc(argSym.len.uint32 + 1)
          moduleSym.copyMem(p, cast[pointer](argSym), argSym.len + 1)
          p
    elif isString:
      arg = genAst(argSym, moduleSym):
        block:
          let p: WasmPtr = moduleSym.alloc(argSym.len.uint32 + 1)
          moduleSym.copyMem(p, cast[ptr char](argSym.cstring), argSym.len + 1)
          p.uint64 or (argSym.len.uint64 shl 32)

    args.add(arg)

  discard body.replace("returnType", [actualReturnType])
  discard body.replace("parameters", args)
  discard body.replace("f", [pfunSym])

  if returnType.getType[1].repr != "void":
    if returnCString:
      body[0] = genAst(value = body[0], moduleSym):
        let p = value
        let res = moduleSym.getString(p)
        return res
    else:
      body[0] = nnkReturnStmt.newTree(body[0])

  # defer:
  #   echo result.repr

  result = newProc(params=params, body=body)
  result.addPragma(ident"gcsafe")
  result.addPragma(nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree(bindSym"CatchableError")))

proc findFunction*(module: WasmModule, name: string, R: typedesc, T: typedesc): Option[tuple[pfun: PFunction, fun: T]] =
  try:
    let f = module.env.findFunction(name)
    if f.isNil:
      return

    {.push hint[XCannotRaiseY]:off.}
    let wrapper = createWasmWrapper(R, T):
      try:
        `f`.call(`returnType`, `parameters`)
      except WasmError as e:
        raise newException(CatchableError, "Failed to call function " & e.msg, e)
    {.pop.}

    result = typeof(result.get).default.some
    result.get.pfun = f
    result.get.fun = wrapper
  except CatchableError as e:
    log lvlError, &"Failed to find function {name}: {e.msg}"
    return
