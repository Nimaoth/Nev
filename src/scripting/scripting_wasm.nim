import std/[macros, macrocache, genasts, json]
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

  unknownPopupActions: seq[tuple[module: WasmModule, callback: proc(popup: int32, action: cstring, arg: cstring): bool]]
  unknownEditorActions: seq[tuple[module: WasmModule, callback: proc(editor: int32, action: cstring, arg: cstring): bool]]
  unknownGlobalActions: seq[tuple[module: WasmModule, callback: proc(action: cstring, arg: cstring): bool]]
  editorModeChangedCallbacks: seq[tuple[module: WasmModule, callback: proc(editor: int32, oldMode: cstring, newMode: cstring): void]]
  postInitializeCallbacks: seq[tuple[module: WasmModule, callback: proc(): bool]]
  handleCallbackCallbacks: seq[tuple[module: WasmModule, callback: proc(id: int32, args: cstring): bool]]
  handleAnyCallbackCallbacks: seq[tuple[module: WasmModule, callback: proc(id: int32, args: cstring): cstring]]
  handleScriptActionCallbacks: seq[tuple[module: WasmModule, callback: proc(name: cstring, args: cstring): cstring]]

var createEditorWasmImports: proc(): WasmImports

macro invoke*(self: ScriptContextWasm; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

method init*(self: ScriptContextWasm, path: string): Future[void] {.async.} =
  proc loadModules(path: string): Future[void] {.async.} =
    # let (_, _, ext) = path.splitFile

    var files: seq[string] = @[]

    # if ext == "":
    #   # todo: Directory
    #   for f in walkFiles(path):
    #     echo f
    #     files.add f
    # else:
    files.add path

    var editorImports = createEditorWasmImports()

    for file in files:
      let module = await newWasmModule(file, @[editorImports])
      if module.getSome(module):
        log(lvlInfo, fmt"Loaded wasm module {file}")

        if findFunction(module, "handleUnknownPopupActionWasm", bool, proc(popup: int32, action: cstring, arg: cstring): bool).getSome(f):
          self.unknownPopupActions.add (module, f)

        if findFunction(module, "handleUnknownDocumentEditorActionWasm", bool, proc(editor: int32, action: cstring, arg: cstring): bool).getSome(f):
          self.unknownEditorActions.add (module, f)

        if findFunction(module, "handleGlobalActionWasm", bool, proc(action: cstring, arg: cstring): bool).getSome(f):
          self.unknownGlobalActions.add (module, f)

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

        if findFunction(module, "absytree_main", void, proc(): void).getSome(f):
          f()

        self.modules.add module

      else:
        log(lvlError, fmt"Failed to create wasm module for file {file}")

  await loadModules("./config/absytree_config_wasm.wasm")

method reload*(self: ScriptContextWasm) = discard

method handleUnknownPopupAction*(self: ScriptContextWasm, popup: Popup, action: string, arg: JsonNode): bool =
  result = false

  let argStr = $arg
  for (m, f) in self.unknownPopupActions:
    if f(popup.id.int32, action.cstring, argStr.cstring):
      return true

method handleUnknownDocumentEditorAction*(self: ScriptContextWasm, editor: DocumentEditor, action: string, arg: JsonNode): bool =
  result = false

  let argStr = $arg
  for (m, f) in self.unknownEditorActions:
    if f(editor.id.int32, action.cstring, argStr.cstring):
      return true

method handleGlobalAction*(self: ScriptContextWasm, action: string, arg: JsonNode): bool =
  result = false

  let argStr = $arg
  for (m, f) in self.unknownGlobalActions:
    if f(action.cstring, argStr.cstring):
      return true

method handleEditorModeChanged*(self: ScriptContextWasm, editor: DocumentEditor, oldMode: string, newMode: string) =
  for (m, f) in self.editorModeChangedCallbacks:
    f(editor.id.int32, oldMode.cstring, newMode.cstring)

method postInitialize*(self: ScriptContextWasm): bool =
  result = false
  for (m, f) in self.postInitializeCallbacks:
    result = f() or result

method handleCallback*(self: ScriptContextWasm, id: int, arg: JsonNode): bool =
  result = false
  let argStr = $arg
  for (m, f) in self.handleCallbackCallbacks:
    if f(id.int32, argStr.cstring):
      return true

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
  let argStr = $args
  for (m, f) in self.handleScriptActionCallbacks:
    let res = f(name.cstring, argStr.cstring)
    if res.isNotNil:
      return ($res).parseJson
  return newJNull()

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
