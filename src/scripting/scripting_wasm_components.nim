import std/[macros, macrocache, genasts, json, strutils, os]
import misc/[custom_logger, custom_async, util]
import scripting_base, document_editor, expose, vfs

import wasmtime, wit_host

export scripting_base

{.push gcsafe.}

logCategory "scripting-wasm-comp"

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../../scripting/plugin_api.wit", "plugin_api_host.nim"
else:
  static: hint("Using cached plugin_api.wit (plugin_api_host.nim)")
  include plugin_api_host

type
  ScriptContextWasmComp* = ref object of ScriptContext
    engine: ptr WasmEngineT
    store: ptr ComponentStoreT
    linker: ptr ComponentLinkerT
    moduleVfs*: VFS
    vfs*: VFS

proc call(instance: ptr ComponentInstanceT, context: ptr ComponentContextT, name: string, params: openArray[ComponentValT], nresults: static[int]) =
  var f: ptr ComponentFuncT = nil
  if not instance.getFunc(context, cast[ptr uint8](name[0].addr), name.len.csize_t, f.addr):
    log lvlError, &"[host] Failed to get func '{name}'"
    return

  if f == nil:
    log lvlError, &"[host] Failed to get func '{name}'"
    return

  var res: array[max(nresults, 1), ComponentValT]
  echo &"[host] ------------------------------- call {name}, {params} -------------------------------------"
  f.call(context, params, res.toOpenArray(0, nresults - 1)).okOr(e):
    log lvlError, &"[host] Failed to call func '{name}': {e.msg}"
    return

  if nresults > 0:
    echo &"[host] call func {name} -> {res}"

proc loadModules(self: ScriptContextWasmComp, path: string): Future[void] {.async.} =
  let listing = await self.vfs.getDirectoryListing(path)

  # {.gcsafe.}:
  #   var editorImports = createEditorWasmImports()

  for file2 in listing.files:
    if not file2.endsWith(".c.wasm"):
      continue

    let file = path // file2

    let wasmBytes = self.vfs.read(file, {Binary}).await
    let component = self.engine.newComponent(wasmBytes).okOr(err):
      log lvlError, "[host] Failed to create wasm component: {err.msg}"
      continue

    var trap: ptr WasmTrapT = nil
    var instance: ptr ComponentInstanceT = nil
    self.linker.instantiate(self.store.context, component, instance.addr, trap.addr).okOr(err):
      log lvlError, "[host] Failed to create component instance: {err.msg}"
      continue

    trap.okOr(err):
      log lvlError, "[host][trap] Failed to create component instance: {err.msg}"
      continue

    assert instance != nil

    instance.call(self.store.context, "init-plugin", [], 0)

method init*(self: ScriptContextWasmComp, path: string, vfs: VFS): Future[void] {.async.} =
  self.vfs = vfs

  let config = newConfig()
  self.engine = newEngine(config)
  self.linker = self.engine.newComponentLinker()
  self.store = self.engine.newComponentStore(nil, nil)

  var trap: ptr WasmTrapT = nil
  self.linker.linkWasi(trap.addr).okOr(err):
    log lvlError, "Failed to link wasi: {err.msg}"
    return

  trap.okOr(err):
    log lvlError, "[trap] Failed to link wasi: {err.msg}"
    return

  block:
    proc cb(ctx: pointer, params: openArray[ComponentValT], results: var openArray[ComponentValT]) =
      results[0] = Selection(first: Cursor(line: 1, column: 2), last: Cursor(line: 6, column: 9)).toVal
      echo &"[host][get-selection]:\n     {params}\n  -> {results}"

    echo "func new"
    let funcName = "get-selection"
    self.linker.funcNew("nev:plugins/text-editor", funcName, cb).okOr(err):
      log lvlError, &"[host][trap] Failed to link func {funcName}: {err.msg}"

  await self.loadModules("app://config/wasm")

method deinit*(self: ScriptContextWasmComp) = discard

method reload*(self: ScriptContextWasmComp): Future[void] {.async.} =
  await self.loadModules("app://config/wasm")
