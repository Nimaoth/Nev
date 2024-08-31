import std/[macros, macrocache, genasts, json, strutils]
import misc/[custom_logger, custom_async, util]
import platform/filesystem
import scripting_base, popup, document_editor, expose

import wasm

when not defined(js):
  import wasm3, wasm3/wasmconversions

export scripting_base, wasm

logCategory "scripting-wasm"

type ScriptContextWasm* = ref object of ScriptContext
  modules: seq[WasmModule]

  editorModeChangedCallbacks: seq[tuple[module: WasmModule, callback: proc(editor: int32, oldMode: cstring, newMode: cstring): void]]
  postInitializeCallbacks: seq[tuple[module: WasmModule, callback: proc(): bool]]
  handleCallbackCallbacks: seq[tuple[module: WasmModule, callback: proc(id: int32, args: cstring): bool]]
  handleAnyCallbackCallbacks: seq[tuple[module: WasmModule, callback: proc(id: int32, args: cstring): cstring]]
  handleScriptActionCallbacks: seq[tuple[module: WasmModule, callback: proc(name: cstring, args: cstring): cstring]]

var createEditorWasmImports: proc(): WasmImports

macro invoke*(self: ScriptContextWasm; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

proc loadModules(self: ScriptContextWasm, path: string): Future[void] {.async.} =
  let (files, _) = await fs.getApplicationDirectoryListing(path)

  var editorImports = createEditorWasmImports()

  for file in files:
    if not file.endsWith(".wasm"):
      continue

    try:
      log lvlInfo, fmt"Try to load wasm module '{file}' from app directory"
      let module = await newWasmModule(file, @[editorImports])
      if module.getSome(module):
        log(lvlInfo, fmt"Loaded wasm module '{file}'")

        if findFunction(module, "handleEditorModeChangedWasm", void, proc(editor: int32, oldMode: cstring, newMode: cstring): void).getSome(f):
          self.editorModeChangedCallbacks.add (module, f)

        if findFunction(module, "postInitializeWasm", bool, proc(): bool).getSome(f):
          self.postInitializeCallbacks.add (module, f)

        if findFunction(module, "handleCallbackWasm", bool, proc(id: int32, arg: cstring): bool).getSome(f):
          self.handleCallbackCallbacks.add (module, f)

        if findFunction(module, "handleAnyCallbackWasm", cstring, proc(id: int32, arg: cstring): cstring).getSome(f):
          self.handleAnyCallbackCallbacks.add (module, f)

        if findFunction(module, "handleScriptActionWasm", cstring, proc(name: cstring, arg: cstring): cstring).getSome(f):
          self.handleScriptActionCallbacks.add (module, f)

        if findFunction(module, "plugin_main", void, proc(): void).getSome(f):
          log lvlInfo, "Run plugin_main"
          f()
          log lvlInfo, "Finished plugin_main"

        self.modules.add module

      else:
        log(lvlError, fmt"Failed to create wasm module for file {file}")

    except:
      log lvlError, &"Failde to load wasm module '{file}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

method init*(self: ScriptContextWasm, path: string): Future[void] {.async.} =
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
  for (m, f) in self.editorModeChangedCallbacks:
    f(editor.id.int32, oldMode.cstring, newMode.cstring)

method postInitialize*(self: ScriptContextWasm): bool =
  result = false
  try:
    for (m, f) in self.postInitializeCallbacks:
      result = f() or result
  except:
    log lvlError, &"Failed to run post initialize: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

method handleCallback*(self: ScriptContextWasm, id: int, arg: JsonNode): bool =
  result = false
  try:
    let argStr = $arg
    for (m, f) in self.handleCallbackCallbacks:
      if f(id.int32, argStr.cstring):
        return true
  except:
    log lvlError, &"Failed to run callback: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

method handleAnyCallback*(self: ScriptContextWasm, id: int, arg: JsonNode): JsonNode =
  result = nil
  let argStr = $arg
  for (m, f) in self.handleAnyCallbackCallbacks:
    let str = $f(id.int32, argStr.cstring)
    if str.len == 0:
      continue

    try:
      return str.parseJson
    except:
      log lvlError, &"Failed to parse json from callback {id}({arg}): '{str}' is not valid json.\n{getCurrentExceptionMsg()}"
      continue

method handleScriptAction*(self: ScriptContextWasm, name: string, args: JsonNode): JsonNode =
  result = nil
  let argStr = $args
  for (m, f) in self.handleScriptActionCallbacks:
    let res = $f(name.cstring, argStr.cstring)
    if res.len == 0:
      continue

    try:
      return res.parseJson
    except:
      log lvlError, &"Failed to parse json from script action {name}({args}): '{res}' is not valid json.\n{getCurrentExceptionMsg()}"
      continue

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

          let imp = genAst(imports, name, function):
            imports.addFunction(name, function)
          list.add imp

      return list

    var imports = WasmImports(namespace: "env")
    addEditorFunctions(imports)
    return imports

  createEditorWasmImports = createEditorWasmImportsImpl
