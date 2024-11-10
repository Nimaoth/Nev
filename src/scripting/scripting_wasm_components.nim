import std/[macros, macrocache, genasts, json, strutils, os]
import misc/[custom_logger, custom_async, util]
import scripting_base, document_editor, expose, vfs, service
import nimsumtree/[rope, sumtree]
import layout
import text/[text_editor, text_document]

import wasmtime, wit_host

export scripting_base

{.push gcsafe.}

logCategory "scripting-wasm-comp"

type WasmContext = ref object
  counter: int
  layout: LayoutService

func createRope(str: string): Rope =
  Rope.new(str)

type RopeResource = object
  rope: RopeSlice[Point]

proc `=destroy`*(self: RopeResource) =
  if not self.rope.rope.tree.isNil:
    let l = min(50, self.rope.len)
    echo &"destroy rope {self.rope[0...l]}"

template typeId*(_: typedesc[RopeResource]): int = 123

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../../scripting/plugin_api.wit", WasmContext:
    cacheFile = "plugin_api_host.nim"
    mapName "rope", RopeResource

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
    services*: Services

proc call(instance: ptr ComponentInstanceT, context: ptr ComponentContextT, name: string, parameters: openArray[ComponentValT], nresults: static[int]) =
  var f: ptr ComponentFuncT = nil
  if not instance.getFunc(context, cast[ptr uint8](name[0].addr), name.len.csize_t, f.addr):
    log lvlError, &"[host] Failed to get func '{name}'"
    return

  if f == nil:
    log lvlError, &"[host] Failed to get func '{name}'"
    return

  var res: array[max(nresults, 1), ComponentValT]
  echo &"[host] ------------------------------- call {name}, {parameters} -------------------------------------"
  f.call(context, parameters, res.toOpenArray(0, nresults - 1)).okOr(e):
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
      log lvlError, &"[host] Failed to create wasm component: {err.msg}"
      continue

    var trap: ptr WasmTrapT = nil
    var instance: ptr ComponentInstanceT = nil
    self.linker.instantiate(self.store.context, component, instance.addr, trap.addr).okOr(err):
      log lvlError, &"[host] Failed to create component instance: {err.msg}"
      continue

    trap.okOr(err):
      log lvlError, &"[host][trap] Failed to create component instance: {err.msg}"
      continue

    assert instance != nil

    instance.call(self.store.context, "init-plugin", [], 0)

proc textEditorGetSelection(host: WasmContext; store: ptr ComponentContextT): Selection =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    let s = editor.selection
    Selection(first: Cursor(line: s.first.line.int32, column: s.first.column.int32), last: Cursor(line: s.last.line.int32, column: s.last.column.int32))
  else:
    Selection(first: Cursor(line: 1, column: 2), last: Cursor(line: 6, column: 9))

proc textNewRope(host: WasmContext; store: ptr ComponentContextT, content: string): RopeResource =
  RopeResource(rope: createRope(content).slice().suffix(Point()))

proc textClone(host: WasmContext, store: ptr ComponentContextT, self: var RopeResource): RopeResource =
  RopeResource(rope: self.rope.clone())

proc textText(host: WasmContext, store: ptr ComponentContextT, self: var RopeResource): string =
  $self.rope

proc textDebug(host: WasmContext, store: ptr ComponentContextT, self: var RopeResource): string =
  &"Rope({self.rope.range}, {self.rope.summary}, {self.rope})"

proc textSlice(host: WasmContext, store: ptr ComponentContextT, self: var RopeResource, a: int64, b: int64): RopeResource =
  RopeResource(rope: self.rope[a.int...b.int].suffix(Point()))

proc textSlicePoints(host: WasmContext, store: ptr ComponentContextT, self: var RopeResource, a: Cursor, b: Cursor): RopeResource =
  let range = Point(row: a.line.uint32, column: a.column.uint32)...Point(row: a.line.uint32, column: a.column.uint32)
  RopeResource(rope: self.rope[range])

proc textGetCurrentEditorRope(host: WasmContext, store: ptr ComponentContextT): RopeResource =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    RopeResource(rope: editor.document.rope.clone().slice().suffix(Point()))
  else:
    RopeResource(rope: createRope("no editor").slice().suffix(Point()))

method init*(self: ScriptContextWasmComp, path: string, vfs: VFS): Future[void] {.async.} =
  self.vfs = vfs

  let config = newConfig()
  self.engine = newEngine(config)
  self.linker = self.engine.newComponentLinker()
  self.store = self.engine.newComponentStore(nil, nil)

  var trap: ptr WasmTrapT = nil
  self.linker.linkWasi(trap.addr).okOr(err):
    log lvlError, &"Failed to link wasi: {err.msg}"
    return

  trap.okOr(err):
    log lvlError, &"[trap] Failed to link wasi: {err.msg}"
    return

  var ctx = WasmContext(counter: 1)
  ctx.layout = self.services.getService(LayoutService).get

  self.linker.defineComponent(ctx).okOr(err):
    echo "[host] Failed to define component: ", err.msg
    return

  await self.loadModules("app://config/wasm")

method deinit*(self: ScriptContextWasmComp) = discard

method reload*(self: ScriptContextWasmComp): Future[void] {.async.} =
  await self.loadModules("app://config/wasm")
