import std/[macros, strutils, os, strformat]
import misc/[custom_logger, custom_async, util, event, jsonex, timer]
import nimsumtree/[rope, sumtree, arc]
import service
import layout
import text/[text_editor, text_document]
import render_view, view
import ui/render_command
import scripting/binary_encoder, config_provider
import scripting/scripting_base

import wasmtime, wit_host_module, plugin_api_base, wasi

{.push gcsafe, raises: [].}

logCategory "plugin-api-v0"

const apiVersion: int32 = 0

type
  HostContext* = ref object
    resources*: WasmModuleResources
    services: Services
    layout*: LayoutService
    plugins*: PluginService
    settings*: ConfigStore
    timer*: Timer

proc getMemoryFor(host: HostContext, caller: ptr CallerT): Option[ExternT] =
  ExternT.none
  # var item: ExternT
  # item.kind = WASMTIME_EXTERN_SHAREDMEMORY
  # item.of_field.sharedmemory = host.sharedMemory
  # item.some

proc getMemory*(caller: ptr CallerT, store: ptr ContextT, host: HostContext): WasmMemory =
  var mainMemory = caller.getExport("memory")
  if mainMemory.isNone:
    mainMemory = host.getMemoryFor(caller)
  if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
    return initWasmMemory(mainMemory.get.of_field.sharedmemory)
  elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
    return initWasmMemory(store, mainMemory.get.of_field.memory.addr)
  else:
    assert false

func createRope(str: string): Rope =
  Rope.new(str)

type TextEditorResource = object
  editor: TextDocumentEditor

type RopeResource = object
  rope: RopeSlice[Point]

type ViewResource = object
  view: RenderView

# proc `=destroy`*(self: RopeResource) =
#   if not self.rope.rope.tree.isNil:
#     let l = min(50, self.rope.len)

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../../wit/v0/api.wit", HostContext:
    world = "plugin"
    cacheFile = "../generated/plugin_api_host.nim"
    mapName "rope", RopeResource
    mapName "view", ViewResource
    mapName "editor", TextEditorResource

else:
  static: hint("Using cached plugin_api.wit (plugin_api_host.nim)")

include generated/plugin_api_host

type
  WasmModule* = object
    instance*: InstanceT
    store*: ptr StoreT
    funcs*: ExportedFuncs

###################################### PluginApi #####################################

type
  PluginApi* = ref object of PluginApiBase
    engine: ptr WasmEngineT
    linker: ptr LinkerT
    host: HostContext
    modules: seq[Arc[WasmModule]]

method init*(self: PluginApi, services: Services, engine: ptr WasmEngineT) =
  self.host = HostContext()
  self.host.services = services
  self.host.layout = services.getService(LayoutService).get
  self.host.plugins = services.getService(PluginService).get
  self.host.settings = services.getService(ConfigService).get.runtime
  self.host.timer = startTimer()

  self.engine = engine
  self.linker = engine.newLinker()

  proc getMemory(caller: ptr CallerT, store: ptr ContextT): WasmMemory =
    var mainMemory = caller.getExport("memory")
    # if mainMemory.isNone:
    #   mainMemory = host.getMemoryFor(caller)
    if mainMemory.get.kind == WASMTIME_EXTERN_SHAREDMEMORY:
      return initWasmMemory(mainMemory.get.of_field.sharedmemory)
    elif mainMemory.get.kind == WASMTIME_EXTERN_MEMORY:
      return initWasmMemory(store, mainMemory.get.of_field.memory.addr)
    else:
      assert false


  when false:
    self.linker.defineWasi().okOr(e):
      log lvlError, "Failed to define wasi imports: " & e.msg
      return
  else:
    self.linker.definePluginWasi(getMemory).okOr(e):
      log lvlError, "Failed to define wasi imports: " & e.msg
      return

  defineComponent(self.linker, self.host).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

method createModule*(self: PluginApi, module: ptr ModuleT) =
  var wasmModule = Arc[WasmModule].new()
  wasmModule.getMut.store = self.engine.newStore(wasmModule.get.addr, nil)
  let ctx = wasmModule.get.store.context

  let wasiConfig = newWasiConfig()
  wasiConfig.inheritStdin()
  wasiConfig.inheritStderr()
  wasiConfig.inheritStdout()
  ctx.setWasi(wasiConfig).toResult(void).okOr(err):
    log lvlError, "Failed to setup wasi: " & err.msg
    return

  var trap: ptr WasmTrapT = nil
  wasmModule.getMut.instance = self.linker.instantiate(ctx, module, trap.addr).okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  trap.okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  collectExports(wasmModule.getMut.funcs, wasmModule.get.instance, ctx)
  self.modules.add wasmModule

  initPlugin(wasmModule.get.funcs).okOr(err):
    log lvlError, "Failed to call init-plugin: " & err.msg
    return

###################################### API implementations #####################################

proc textEditorGetSelection(host: HostContext; store: ptr ContextT): Selection =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    let s = editor.selection
    Selection(first: Cursor(line: s.first.line.int32, column: s.first.column.int32), last: Cursor(line: s.last.line.int32, column: s.last.column.int32))
  else:
    Selection(first: Cursor(line: 1, column: 2), last: Cursor(line: 6, column: 9))

proc textEditor_addModeChangedHandler(host: HostContext, store: ptr ContextT, fun: uint32): int32 =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    discard editor.onModeChanged.subscribe proc(args: tuple[removed: seq[string], added: seq[string]]) =
      let module = cast[ptr WasmModule](store.getData())
      let res = module[].funcs.handleModeChanged(fun, $args.removed, $args.added)
      if res.isErr:
        log lvlError, "Failed to call handleModeChanged: " & $res
  return 123

proc textEditorCurrent(host: HostContext; store: ptr ContextT): Option[TextEditorResource] =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    return TextEditorResource(editor: editor).some
  return  TextEditorResource.none

proc textRope(host: HostContext; store: ptr ContextT; self: var TextEditorResource): RopeResource =
  if self.editor == nil:
    return RopeResource(rope: createRope("no editor").slice().suffix(Point()))
  elif self.editor.document == nil:
    return RopeResource(rope: createRope("no document").slice().suffix(Point()))
  return RopeResource(rope: self.editor.document.rope.clone().slice().suffix(Point()))

proc textNewRope(host: HostContext; store: ptr ContextT, content: sink string): RopeResource =
  RopeResource(rope: createRope(content).slice().suffix(Point()))

proc textClone(host: HostContext, store: ptr ContextT, self: var RopeResource): RopeResource =
  RopeResource(rope: self.rope.clone())

proc textText(host: HostContext, store: ptr ContextT, self: var RopeResource): string =
  $self.rope

proc textDebug(host: HostContext, store: ptr ContextT, self: var RopeResource): string =
  &"Rope({self.rope.range}, {self.rope.summary}, {self.rope})"

proc textSlice(host: HostContext, store: ptr ContextT, self: var RopeResource, a: int64, b: int64): RopeResource =
  let a = min(a, b).clamp(0, self.rope.len)
  let b = max(a, b).clamp(0, self.rope.len)
  RopeResource(rope: self.rope[a.int...b.int].suffix(Point()))

proc textSlicePoints(host: HostContext, store: ptr ContextT, self: var RopeResource, a: Cursor, b: Cursor): RopeResource =
  let range = Point(row: a.line.uint32, column: a.column.uint32)...Point(row: a.line.uint32, column: a.column.uint32)
  RopeResource(rope: self.rope[range])

proc coreGetTime(host: HostContext; store: ptr ContextT): float64 =
  return host.timer.elapsed.ms

proc coreApiVersion(host: HostContext, store: ptr ContextT): int32 =
  return apiVersion

proc coreBindKeys(host: HostContext, store: ptr ContextT, context: sink string, subContext: sink string, keys: sink string,
    action: sink string, arg: sink string, description: sink string, source: sink (string, int32, int32)): void =
  host.plugins.bindKeys(context, subContext, keys, action, arg, description, (source[0], source[1].int, source[2].int))

proc coreDefineCommand(host: HostContext, store: ptr ContextT, name: sink string, active: bool, docs: sink string,
                       params: sink seq[(string, string)], returnType: sink string, context: sink string): void =
  host.plugins.addScriptAction(name, docs, params, returnType, active, context)

proc coreRunCommand(host: HostContext, store: ptr ContextT, name: sink string, args: sink string): void =
  # todo
  discard

proc coreGetSettingRaw(host: HostContext, store: ptr ContextT, name: sink string): string =
  return $host.settings.get(name, JsonNodeEx)

proc coreSetSettingRaw(host: HostContext, store: ptr ContextT, name: sink string, value: sink string) =
  try:
    host.settings.set(name, parseJsonex(value))
  except CatchableError as e:
    log lvlError, "coreSetSettingRaw: Failed to set setting '{name}' to {value}: {e.msg}"

proc renderNewView(host: HostContext; store: ptr ContextT): ViewResource =
  let view = newRenderView(host.services)
  host.layout.addView(view, "**")
  return ViewResource(view: view)

proc renderViewCreate(host: HostContext; store: ptr ContextT): ViewResource =
  let view = newRenderView(host.services)
  host.layout.addView(view, "**")
  return ViewResource(view: view)

proc renderViewFromId(host: HostContext; store: ptr ContextT; id: int32): ViewResource =
  let view = newRenderView(host.services)
  host.layout.addView(view, "**")
  return ViewResource(view: view)

proc renderId(host: HostContext; store: ptr ContextT; self: var ViewResource): int32 =
  return self.view.id2

proc renderSize(host: HostContext; store: ptr ContextT; self: var ViewResource): Vec2f =
  return Vec2f(x: self.view.size.x, y: self.view.size.y)

proc renderSetRenderWhenInactive(host: HostContext; store: ptr ContextT; self: var ViewResource; enabled: bool): void =
  self.view.setRenderWhenInactive(enabled)

proc renderSetPreventThrottling(host: HostContext; store: ptr ContextT; self: var ViewResource; enabled: bool): void =
  self.view.preventThrottling = enabled

proc renderSetRenderInterval(host: HostContext; store: ptr ContextT; self: var ViewResource; ms: int32): void =
  self.view.setRenderInterval(ms.int)

proc renderSetRenderCommands(host: HostContext; store: ptr ContextT; self: var ViewResource; data: sink seq[uint8]): void =
  self.view.commands.raw = data.ensureMove

proc renderSetRenderCommandsRaw(host: HostContext; store: ptr ContextT; self: var ViewResource; buffer: uint32; len: uint32): void =
  let module = cast[ptr WasmModule](store.getData())
  let mem = module[].funcs.mem
  let buffer = buffer.WasmPtr
  let len = len.int

  self.view.commands.clear()
  var decoder = BinaryDecoder.init(mem.getOpenArray[:byte](buffer, len))
  try:
    for command in decoder.decodeRenderCommands():
      self.view.commands.commands.add(command)
  except ValueError as e:
    discard

proc renderMarkDirty(host: HostContext; store: ptr ContextT; self: var ViewResource): void =
  self.view.markDirty()

proc renderSetRenderCallback(host: HostContext; store: ptr ContextT; self: var ViewResource; fun: uint32; data: uint32): void =
  self.view.onRender = proc(view: RenderView) =
    let module = cast[ptr WasmModule](store.getData())
    module[].funcs.handleViewRenderCallback(view.id2, fun, data).okOr(err):
      log lvlError, "Failed to call handleViewRenderCallback: " & $err
