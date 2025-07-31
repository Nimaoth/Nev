import std/[macros, macrocache, genasts, json, strutils, os, strformat]
import misc/[custom_logger, custom_async, util, event]
import scripting/scripting_base, document_editor, scripting/expose, vfs, service
import nimsumtree/[rope, sumtree, arc]
import layout
import text/[text_editor, text_document]

import wasmtime, wit_host_module

export scripting_base

logCategory "scripting-wasm-comp"

type WasmContext = ref object
  resources: WasmModuleResources
  counter: int
  layout: LayoutService
  plugins: PluginService
  callbacks: seq[int32] = @[]

func createRope(str: string): Rope =
  Rope.new(str)

type RopeResource = object
  rope: RopeSlice[Point]

proc `=destroy`*(self: RopeResource) =
  if not self.rope.rope.tree.isNil:
    let l = min(50, self.rope.len)
    echo &"destroy rope {self.rope[0...l]}"

template typeId*(_: typedesc[RopeResource]): int = 123

proc getMemoryFor(host: WasmContext, caller: ptr CallerT): Option[ExternT] =
  # echo &"[host] getMemoryFor"
  ExternT.none
  # var item: ExternT
  # item.kind = WASMTIME_EXTERN_SHAREDMEMORY
  # item.of_field.sharedmemory = host.sharedMemory
  # item.some

proc getMemory(caller: ptr CallerT, store: ptr ContextT, host: WasmContext): WasmMemory =
  var mainMemory = caller.getExport("memory")
  if mainMemory.isNone:
    mainMemory = host.getMemoryFor(caller)
  if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
    return initWasmMemory(mainMemory.get.of_field.sharedmemory)
  elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
    return initWasmMemory(store, mainMemory.get.of_field.memory.addr)
  else:
    assert false

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../scripting/plugin_api.wit", WasmContext:
    world = "plugin"
    cacheFile = "generated/plugin_api_host.nim"
    mapName "rope", RopeResource

else:
  static: hint("Using cached plugin_api.wit (plugin_api_host.nim)")
  include generated/plugin_api_host

type
  WasmModule = object
    instance: InstanceT
    store: ptr StoreT
    funcs: ExportedFuncs

  WasmPluginSystem* = ref object of ScriptContext
    engine: ptr WasmEngineT
    linker: ptr LinkerT
    moduleVfs*: VFS
    vfs*: VFS
    services*: Services

    context: WasmContext
    modules: seq[Arc[WasmModule]]

proc call[T](instance: InstanceT, context: ptr ContextT, name: string, parameters: openArray[ValT], nresults: static[int]): T =

  echo &"[host] ------------------------------- call {name}, {parameters} -------------------------------------"

  let fun = instance.getExport(context, name)
  if fun.isNone:
    echo &"Failed to find export '{name}'"
    return

  var trap: ptr WasmTrapT = nil
  var res: array[max(nresults, 1), ValT]
  fun.get.of_field.func_field.addr.call(context, parameters, res.toOpenArray(0, nresults - 1), trap.addr).toResult(void).okOr(err):
    log lvlError, &"[host] Failed to call func '{name}': {err.msg}"
    return

  if nresults > 0:
    echo &"[host] call func {name} -> {res}"

  when T isnot void:
    res[0].to(T)

proc loadModules(self: WasmPluginSystem, path: string): Future[void] {.async.} =
  let listing = await self.vfs.getDirectoryListing(path)

  # {.gcsafe.}:
  #   var editorImports = createEditorWasmImports()

  await sleepAsync(1.seconds)

  # let ctx = self.store.context

  for file2 in listing.files:
    if not file2.endsWith(".m.wasm"):
      continue

    let file = path // file2

    let wasmBytes = self.vfs.read(file, {Binary}).await
    let module = self.engine.newModule(wasmBytes).okOr(err):
      log lvlError, &"[host] Failed to create wasm module: {err.msg}"
      continue

    var wasmModule = Arc[WasmModule].new()
    wasmModule.getMut.store = self.engine.newStore(wasmModule.get.addr, nil)
    let ctx = wasmModule.get.store.context

    let wasiConfig = newWasiConfig()
    wasiConfig.inheritStdin()
    wasiConfig.inheritStderr()
    wasiConfig.inheritStdout()
    ctx.setWasi(wasiConfig).toResult(void).okOr(err):
      echo "[host] Failed to setup wasi: ", err.msg
      continue

    var trap: ptr WasmTrapT = nil
    wasmModule.getMut.instance = self.linker.instantiate(ctx, module, trap.addr).okOr(err):
      log lvlError, &"[host] Failed to create module instance: {err.msg}"
      continue

    trap.okOr(err):
      log lvlError, &"[host][trap] Failed to create module instance: {err.msg}"
      continue

    wasmModule.getMut.funcs.collectExports(wasmModule.get.instance, ctx)
    self.modules.add wasmModule

    # wasmModule.get.instance.call[:void](ctx, "init_plugin", [], 0)

    wasmModule.get.funcs.initPlugin().okOr(err):
      echo &"Failed to call init-plugin: {err}"
      continue
    let res = wasmModule.get.funcs.handleCommand("hello", "world").okOr(err):
      echo &"Failed to call init-plugin: {err}"
      continue
    echo &"[host] handleCommand -> '{res}'"
    # wasmModule.get.instance.call[:void](ctx, "init_plugin", [], 0)

    let functionTableExport = wasmModule.get.instance.getExport(ctx, "__indirect_function_table")
    var functionTable = functionTableExport.get.of_field.table
    echo &"function table {ctx.size(functionTable.addr)}"

    for cb in self.context.callbacks:
      echo &"[host] ============== call callback {cb}"
      let fun = functionTable.get(ctx, cb)
      if fun.isNone:
        echo &"[host] Failed to find callback {cb}"
        continue

      var results: array[1, ValT]
      fun.get.of_field.funcref.addr.call(ctx, [38.int32.toWasmVal], results, trap.addr).toResult(void).okOr(err):
        echo &"[host] Failed to call callback {cb}: ", err.msg
        continue

      echo &"[host] callback {cb} -> {results[0].of_field.i32}"

proc textEditorGetSelection(host: WasmContext; store: ptr ContextT): Selection =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    let s = editor.selection
    Selection(first: Cursor(line: s.first.line.int32, column: s.first.column.int32), last: Cursor(line: s.last.line.int32, column: s.last.column.int32))
  else:
    Selection(first: Cursor(line: 1, column: 2), last: Cursor(line: 6, column: 9))

proc textEditorAddModeChangedHandler(host: WasmContext, store: ptr ContextT, fun: uint32): int32 =
  echo &"[host] textEditorAddModeChangedHandler {fun}"
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    discard editor.onModeChanged.subscribe proc(args: tuple[removed: seq[string], added: seq[string]]) =
      echo &"[host] textEditorAddModeChangedHandler {args.removed} -> {args.added}"

      let module = cast[ptr WasmModule](store.getData())
      # let str = module[].instance.call[:string](store, "handle_mode_changed", [cast[int32](fun).toWasmVal], 0)

      let res = module[].funcs.handleModeChanged(fun, $args.removed, $args.added)
      if res.isErr:
        echo &"[host] failed to call handleModeChanged: {res}"
  return 123

proc textNewRope(host: WasmContext; store: ptr ContextT, content: string): RopeResource =
  RopeResource(rope: createRope(content).slice().suffix(Point()))

proc textClone(host: WasmContext, store: ptr ContextT, self: var RopeResource): RopeResource =
  RopeResource(rope: self.rope.clone())

proc textText(host: WasmContext, store: ptr ContextT, self: var RopeResource): string =
  $self.rope

proc textDebug(host: WasmContext, store: ptr ContextT, self: var RopeResource): string =
  &"Rope({self.rope.range}, {self.rope.summary}, {self.rope})"

proc textSlice(host: WasmContext, store: ptr ContextT, self: var RopeResource, a: int64, b: int64): RopeResource =
  RopeResource(rope: self.rope[a.int...b.int].suffix(Point()))

proc textSlicePoints(host: WasmContext, store: ptr ContextT, self: var RopeResource, a: Cursor, b: Cursor): RopeResource =
  let range = Point(row: a.line.uint32, column: a.column.uint32)...Point(row: a.line.uint32, column: a.column.uint32)
  RopeResource(rope: self.rope[range])

proc textGetCurrentEditorRope(host: WasmContext, store: ptr ContextT): RopeResource =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    RopeResource(rope: editor.document.rope.clone().slice().suffix(Point()))
  else:
    RopeResource(rope: createRope("no editor").slice().suffix(Point()))

proc coreBindKeys(host: WasmContext, store: ptr ContextT, context: string, subContext: string, keys: string,
                  action: string, arg: string, description: string, source: (string, int32, int32)): void =
  host.plugins.bindKeys(context, subContext, keys, action, arg, description, (source[0], source[1].int, source[2].int))

proc coreDefineCommand(host: WasmContext, store: ptr ContextT, name: string, active: bool, docs: string,
                       params: seq[(string, string)], returnType: string, context: string): void =
  host.plugins.addScriptAction(name, docs, params, returnType, active, context)

var scriptRunActionImpl*: proc(action: string, arg: string): JsonNode = nil

proc coreRunCommand(host: WasmContext, store: ptr ContextT, name: string, args: string): void =
  {.gcsafe.}:
    discard scriptRunActionImpl(name, args)

proc initWasm(self: WasmPluginSystem) =
  let config = newConfig()
  self.engine = newEngine(config)
  self.linker = self.engine.newLinker()

  self.linker.defineWasi().okOr(err):
    echo "[host] Failed to create linker: ", err.msg
    return

  let e = block:
    self.linker.defineFuncUnchecked("env", "addCallback", newFunctype([WasmValkind.I32], [])):
      discard
      let mem = getMemory(caller, store, self.context)
      let funcIdxPtr = parameters[0].i32.WasmPtr
      let funcIdx = mem.read[:int32](funcIdxPtr)
      echo &"[host] addCallback {funcIdxPtr.int} -> {funcIdx}"
      self.context.callbacks.add(funcIdx)
  if e.isErr:
    echo "[host] Failed to define component: ", e.err.msg

  self.context = WasmContext(counter: 1)
  self.context.layout = self.services.getService(LayoutService).get
  self.context.plugins = self.services.getService(PluginService).get

  self.linker.defineComponent(self.context).okOr(err):
    echo "[host] Failed to define component: ", err.msg
    return

method init*(self: WasmPluginSystem, path: string, vfs: VFS): Future[void] {.async.} =
  self.vfs = vfs
  self.initWasm()
  await self.loadModules("app://config/wasm")

method deinit*(self: WasmPluginSystem) = discard

method reload*(self: WasmPluginSystem): Future[void] {.async.} =
  await self.loadModules("app://config/wasm")

method handleScriptAction*(self: WasmPluginSystem, name: string, arg: JsonNode): JsonNode =
  echo &"handleScriptAction {name}, {arg}"
  try:
    result = nil
    let argStr = $arg
    for module in self.modules:
      # self.stack.add m
      # defer: discard self.stack.pop
      try:
        discard
        # let str = module.instance.call[:string](module.store.context, "handle-command", [name.toWasmVal, argStr.toWasmVal], 1)
        # return str.parseJson
      except:
        # log lvlError, &"Failed to parse json from callback {id}({arg}): '{str}' is not valid json.\n{getCurrentExceptionMsg()}"
        continue
  except:
    log lvlError, &"Failed to run handleScriptAction: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
