import std/[macros, macrocache, genasts, json, sugar, os]
import custom_logger, custom_async, scripting_base, popup, document_editor, util, expose
import platform/filesystem

import wasm

export scripting_base, wasm

type ScriptContextWasm* = ref object of ScriptContext
  modules: seq[WasmModule]

  unknownPopupActions: seq[tuple[module: WasmModule, callback: proc(popup: int32, action: cstring, arg: cstring): bool]]
  unknownEditorActions: seq[tuple[module: WasmModule, callback: proc(editor: int32, action: cstring, arg: cstring): bool]]
  unknownGlobalActions: seq[tuple[module: WasmModule, callback: proc(action: cstring, arg: cstring): bool]]

var createEditorWasmImports: proc(): WasmImports

macro invoke*(self: ScriptContextWasm; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

method init*(self: ScriptContextWasm, path: string) =
  proc loadModules(path: string): Future[void] {.async.} =
    let (_, _, ext) = path.splitFile

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
        logger.log(lvlInfo, fmt"[scripting-wasm] Loaded wasm module {file}")

        if findFunction(module, "handleUnknownPopupActionWasm", bool, proc(popup: int32, action: cstring, arg: cstring): bool).getSome(f):
          self.unknownPopupActions.add (module, f)

        if findFunction(module, "handleUnknownDocumentEditorActionWasm", bool, proc(editor: int32, action: cstring, arg: cstring): bool).getSome(f):
          self.unknownEditorActions.add (module, f)

        if findFunction(module, "handleGlobalActionWasm", bool, proc(action: cstring, arg: cstring): bool).getSome(f):
          self.unknownGlobalActions.add (module, f)

        if findFunction(module, "absytree_main", void, proc(): void).getSome(f):
          echo "run absytree_main"
          f()
        self.modules.add module
      else:
        logger.log(lvlError, fmt"Failed to create wasm module for file {file}")

  asyncCheck loadModules("./config/absytree_config_wasm.wasm")

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
