import std/[macros, json]
import custom_logger, scripting_base, popup, document_editor
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