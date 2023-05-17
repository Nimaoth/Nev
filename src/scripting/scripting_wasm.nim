import std/[macros, json]
import custom_logger, custom_async, scripting_base, popup, document_editor, util
import platform/filesystem

import wasm

export scripting_base

type ScriptContextWasm* = ref object of ScriptContext
  discard

macro invoke*(self: ScriptContextWasm; pName: untyped; args: varargs[typed]; returnType: typedesc): untyped =
  result = quote do:
    default(`returnType`)

method init*(self: ScriptContextWasm, path: string) = discard
method reload*(self: ScriptContextWasm) = discard

method handleUnknownPopupAction*(self: ScriptContextWasm, popup: Popup, action: string, arg: JsonNode): bool = discard
method handleUnknownDocumentEditorAction*(self: ScriptContextWasm, editor: DocumentEditor, action: string, arg: JsonNode): bool = discard
method handleGlobalAction*(self: ScriptContextWasm, action: string, arg: JsonNode): bool = discard

# ----------------------------------------------------------------------------

proc imported_func(a: int32) =
  echo "2 nim imported func: ", a

proc uiae(a: int32, b: cstring) =
  echo "uiae: ", a, ", ", b

proc xvlc(a: int32, b: cstring): cstring =
  echo "xvlc: ", a, ", ", b
  return b

proc test(): Future[void] {.async.} =
  echo "xvlc"

  # var imports = WasmImports(namespace: "imports")
  # imports.addFunction("imported_func", imported_func)

  # let module = await newWasmModule("simple.wasm", @[imports])
  # if findFunction(module, "exported_func", void, proc(): void).getSome(f):
  #   echo "Call exportedFunc"
  #   f()


  var imports2 = WasmImports(namespace: "env")
  imports2.addFunction("uiae", uiae)
  imports2.addFunction("xvlc", xvlc)


  when defined(js):
    let module2 = await newWasmModule("maths.wasm", @[imports2])
  else:
    let module2 = await newWasmModule("temp/wasm/maths.wasm", @[imports2])
  if findFunction(module2, "foo", int32, proc(a: int32, b: int32): int32).getSome(f):
    echo "foo in nim: ", f(2, 3)
  if findFunction(module2, "foo2", int32, proc(a: int32, b: int32): int32).getSome(f):
    echo "foo2 in nim: ", f(7, 8)
  if findFunction(module2, "barc", cstring, proc(a: cstring): cstring).getSome(f):
    echo f("xvlc")
  if findFunction(module2, "barc2", cstring, proc(a: cstring): cstring).getSome(f):
    echo f("uiae")


asyncCheck test()

when isMainModule and not defined(js):
  quit()

# {.error: "uiae".}