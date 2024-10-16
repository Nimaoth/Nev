import std/[macros, macrocache, genasts, json, strutils, os, unicode]
import misc/[custom_logger, custom_async, util, id]
import platform/filesystem
import scripting_base, document_editor, expose, vfs
import wasm
import wasm3, wasm3/wasmconversions

export scripting_base, wasm

{.push gcsafe.}

logCategory "scripting-wasm"

type
  ScriptContextWasm* = ref object of ScriptContext
    modules: seq[WasmModule]

    editorModeChangedCallbacks: seq[tuple[module: WasmModule, pfun: PFunction, callback: proc(module: WasmModule, pfun: PFunction, editor: int32, oldMode: cstring, newMode: cstring): void {.gcsafe.}]]
    postInitializeCallbacks: seq[tuple[module: WasmModule, pfun: PFunction, callback: proc(module: WasmModule, pfun: PFunction): bool {.gcsafe.}]]
    handleCallbackCallbacks: seq[tuple[module: WasmModule, pfun: PFunction, callback: proc(module: WasmModule, pfun: PFunction, id: int32, args: cstring): bool {.gcsafe.}]]
    handleAnyCallbackCallbacks: seq[tuple[module: WasmModule, pfun: PFunction, callback: proc(module: WasmModule, pfun: PFunction, id: int32, args: cstring): cstring {.gcsafe.}]]
    handleScriptActionCallbacks: seq[tuple[module: WasmModule, pfun: PFunction, callback: proc(module: WasmModule, pfun: PFunction, name: cstring, args: cstring): cstring {.gcsafe.}]]

    stack: seq[WasmModule]

    vfs*: VFSWasmContext

  VFSWasmContext* = ref object of VFS

method readImpl*(self: VFSWasmContext, path: string): Future[Option[string]] {.async.} =
  log lvlError, &"[VFSWasmContext] read({path}): not found"
  return string.none

var createEditorWasmImports*: proc(): WasmImports {.raises: [].}

method getCurrentContext*(self: ScriptContextWasm): string =
  result = "plugs://"
  if self.stack.len > 0:
    result.add self.stack[^1].path.splitFile.name
    result.add "/"

macro invoke*(self: ScriptContextWasm; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

var lineBuffer {.global.} = ""

proc printI32(a: int32) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printU32(a: uint32) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printI64(a: int64) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printU64(a: uint64) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printF32(a: float32) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printF64(a: float64) =
  {.gcsafe.}:
    if lineBuffer.len > 0:
      lineBuffer.add " "
    lineBuffer.add $a

proc printChar(a: int32) =
  {.gcsafe.}:
    lineBuffer.add $a.Rune

proc printString(a: cstring, len: int32) =
  {.gcsafe.}:
    let str = $a
    assert len <= a.len
    lineBuffer.add str[0..<len]

proc printLine() =
  {.gcsafe.}:
    let l = lineBuffer
    lineBuffer = ""
    log lvlInfo, l

proc intToString(a: int32): cstring =
  let res = $a
  return res.cstring

proc loadAppFile(a: cstring): cstring =
  {.gcsafe.}:
    let file = fs.loadApplicationFile($a)
    # log lvlInfo, fmt"loadAppFile {a} -> {file}"
    return file.cstring

proc loadModules(self: ScriptContextWasm, path: string): Future[void] {.async.} =
  let (files, _) = await self.fs.getApplicationDirectoryListing(path)

  {.gcsafe.}:
    var editorImports = createEditorWasmImports()
    editorImports.addFunction("loadAppFile", loadAppFile)

  var modelImports = WasmImports(namespace: "model_env")
  modelImports.addFunction("print_i32", printI32)
  modelImports.addFunction("print_u32", printU32)
  modelImports.addFunction("print_i64", printI64)
  modelImports.addFunction("print_u64", printU64)
  modelImports.addFunction("print_f32", printF32)
  modelImports.addFunction("print_f64", printF64)
  modelImports.addFunction("print_char", printChar)
  modelImports.addFunction("print_string", printString)
  modelImports.addFunction("print_line", printLine)
  modelImports.addFunction("intToString", intToString)

  for file in files:
    if not file.endsWith(".wasm"):
      continue

    try:
      log lvlInfo, fmt"Try to load wasm module '{file}' from app directory"
      let module = await newWasmModule(file, @[editorImports, modelImports], self.fs)

      if module.getSome(module):
        self.vfs.mount(file.splitFile.name & "/", newInMemoryVFS())
        self.stack.add module
        defer: discard self.stack.pop

        log(lvlInfo, fmt"Loaded wasm module '{file}'")

        # todo: shouldn't need to specify gcsafe here, findFunction should handle that
        if findFunction(module, "handleEditorModeChangedWasm", void, proc(module: WasmModule, fun: PFunction, editor: int32, oldMode: cstring, newMode: cstring): void {.gcsafe.}).getSome(f):
          self.editorModeChangedCallbacks.add (module, f.pfun, f.fun)

        if findFunction(module, "postInitializeWasm", bool, proc(module: WasmModule, fun: PFunction): bool {.gcsafe.}).getSome(f):
          self.postInitializeCallbacks.add (module, f.pfun, f.fun)

        if findFunction(module, "handleCallbackWasm", bool, proc(module: WasmModule, fun: PFunction, id: int32, arg: cstring): bool {.gcsafe.}).getSome(f):
          self.handleCallbackCallbacks.add (module, f.pfun, f.fun)

        if findFunction(module, "handleAnyCallbackWasm", cstring, proc(module: WasmModule, fun: PFunction, id: int32, arg: cstring): cstring {.gcsafe.}).getSome(f):
          self.handleAnyCallbackCallbacks.add (module, f.pfun, f.fun)

        if findFunction(module, "handleScriptActionWasm", cstring, proc(module: WasmModule, fun: PFunction, name: cstring, arg: cstring): cstring {.gcsafe.}).getSome(f):
          self.handleScriptActionCallbacks.add (module, f.pfun, f.fun)

        self.modules.add module

        if findFunction(module, "plugin_main", void, proc(module: WasmModule, fun: PFunction): void {.gcsafe.}).getSome(f):
          log lvlInfo, "Run plugin_main"
          f.fun(module, f.pfun)
          log lvlInfo, "Finished plugin_main"

      else:
        log(lvlError, fmt"Failed to create wasm module for file {file}")

    except:
      log lvlError, &"Failde to load wasm module '{file}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

{.push raises: [].}

method init*(self: ScriptContextWasm, path: string, fs: Filesystem): Future[void] {.async.} =
  self.fs = fs
  await self.loadModules("./config/wasm")

method deinit*(self: ScriptContextWasm) = discard

method reload*(self: ScriptContextWasm): Future[void] {.async.} =
  self.editorModeChangedCallbacks.setLen 0
  self.postInitializeCallbacks.setLen 0
  self.handleCallbackCallbacks.setLen 0
  self.handleAnyCallbackCallbacks.setLen 0
  self.handleScriptActionCallbacks.setLen 0

  self.modules.setLen 0

  await self.loadModules("./config/wasm")

method handleEditorModeChanged*(self: ScriptContextWasm, editor: DocumentEditor, oldMode: string, newMode: string) =
  try:
    for (m, p, f) in self.editorModeChangedCallbacks:
      f(m, p, editor.id.int32, oldMode.cstring, newMode.cstring)
  except:
    log lvlError, &"Failed to run handleEditorModeChanged: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

method postInitialize*(self: ScriptContextWasm): bool =
  result = false
  try:
    for (m, p, f) in self.postInitializeCallbacks:
      self.stack.add m
      defer: discard self.stack.pop
      result = f(m, p) or result
  except:
    log lvlError, &"Failed to run post initialize: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

method handleCallback*(self: ScriptContextWasm, id: int, arg: JsonNode): bool =
  result = false
  try:
    let argStr = $arg
    for (m, p, f) in self.handleCallbackCallbacks:
      self.stack.add m
      defer: discard self.stack.pop
      if f(m, p, id.int32, argStr.cstring):
        return true
  except:
    log lvlError, &"Failed to run callback: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

method handleAnyCallback*(self: ScriptContextWasm, id: int, arg: JsonNode): JsonNode =
  try:
    result = nil
    let argStr = $arg
    for (m, p, f) in self.handleAnyCallbackCallbacks:
      self.stack.add m
      defer: discard self.stack.pop
      let str = $f(m, p, id.int32, argStr.cstring)
      if str.len == 0:
        continue

      try:
        return str.parseJson
      except:
        log lvlError, &"Failed to parse json from callback {id}({arg}): '{str}' is not valid json.\n{getCurrentExceptionMsg()}"
        continue
  except:
    log lvlError, &"Failed to run handleAnyCallback: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"


method handleScriptAction*(self: ScriptContextWasm, name: string, args: JsonNode): JsonNode =
  try:
    result = nil
    let argStr = $args
    for (m, p, f) in self.handleScriptActionCallbacks:
      self.stack.add m
      defer: discard self.stack.pop
      let res = $f(m, p, name.cstring, argStr.cstring)
      if res.len == 0:
        continue

      try:
        return res.parseJson
      except:
        log lvlError, &"Failed to parse json from script action {name}({args}): '{res}' is not valid json.\n{getCurrentExceptionMsg()}"
        continue
  except:
    log lvlError, &"Failed to run handleScriptAction: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

# Sets the implementation of createEditorWasmImports. This needs to happen late during compilation after any expose pragmas have been executed,
# because this goes through all exposed functions at compile time to create the wasm import data.
# That's why it's in a template
template createEditorWasmImportConstructor*() =
  proc createEditorWasmImportsImpl(): WasmImports =
    macro addEditorFunctions(imports: WasmImports): untyped =
      var list = nnkStmtList.newTree()
      for m, l in wasmImportedFunctions:
        for f in l:
          let name = f[0].strVal.newLit
          let function = f[0]

          let id = taggedId("editor.wasm_api." & f[0].strVal)
          let argId = taggedId("editor.wasm_api.arg." & f[0].strVal)

          let imp = genAst(imports, name, function, idStr = $id, argIdStr = $argId):
            imports.addFunction(name, function, idStr.parseId, argIdStr.parseId)
          list.add imp

      return list

    var imports = WasmImports(namespace: "env")
    addEditorFunctions(imports)
    return imports

  createEditorWasmImports = createEditorWasmImportsImpl
