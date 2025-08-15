import std/[macros, strutils, os, strformat, sequtils, json, sets, pathnorm]
import misc/[custom_logger, custom_async, util, event, jsonex, timer, myjsonutils, render_command, binary_encoder, async_process]
import nimsumtree/[rope, sumtree, arc]
import service
import layout
import text/[text_editor, text_document]
import render_view, view
import platform/platform, platform_service
import config_provider, command_service
import plugin_service, document_editor, vfs, vfs_service, channel
import wasmtime, wit_host_module, plugin_api_base, wasi
from scripting_api import nil

{.push gcsafe, raises: [].}

logCategory "plugin-api-v0"

const apiVersion: int32 = 0

type
  HostContext* = ref object
    resources*: WasmModuleResources
    services: Services
    platform: Platform
    commands*: CommandService
    editors*: DocumentEditorService
    layout*: LayoutService
    plugins*: PluginService
    settings*: ConfigStore
    vfsService*: VFSService
    vfs*: VFS
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

type RopeResource = object
  rope: RopeSlice[Point]

type RenderViewResource = object
  setRender: bool = false
  view: RenderView

type ReadChannelResource = object
  channel: Arc[BaseChannel]
  listenId: ListenId

type WriteChannelResource = object
  channel: Arc[BaseChannel]

type ProcessResource = object
  process: AsyncProcess
  stdin: Arc[BaseChannel]
  stdout: Arc[BaseChannel]
  stderr: Arc[BaseChannel]

proc `=destroy`*(self: RenderViewResource) =
  if self.setRender and self.view != nil:
    self.view.onRender = nil

proc `=destroy`*(self: ReadChannelResource) =
  if self.channel.isNotNil:
    when defined(debugChannelDestroy):
      echo "=destroy ReadChannelResource ", self.channel.count
    # self.channel.stopListening(self.listenId)
    `=destroy`(self.channel)

proc `=destroy`*(self: WriteChannelResource) =
  if self.channel.isNotNil:
    when defined(debugChannelDestroy):
      echo "=destroy WriteChannelResource ", self.channel.count
    `=destroy`(self.channel)

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../../wit/v0/api.wit", HostContext:
    world = "plugin"
    cacheFile = "../generated/plugin_api_host.nim"
    mapName "rope", RopeResource
    mapName "render-view", RenderViewResource
    mapName "read-channel", ReadChannelResource
    mapName "write-channel", WriteChannelResource
    mapName "process", ProcessResource

else:
  static: hint("Using cached plugin_api.wit (plugin_api_host.nim)")

include generated/plugin_api_host

type
  InstanceData = object
    instance: InstanceT
    store: ptr StoreT
    funcs: ExportedFuncs
    permissions: PluginPermissions
    commands: seq[CommandId]
    namespace: string

  WasmModuleInstanceImpl* = ref object of WasmModuleInstance
    instance*: Arc[InstanceData]

###################################### PluginApi #####################################

type
  PluginApi* = ref object of PluginApiBase
    engine: ptr WasmEngineT
    linkerWasiNone: ptr LinkerT
    linkerWasiReduced: ptr LinkerT
    linkerWasiFull: ptr LinkerT
    host: HostContext
    instances: seq[WasmModuleInstanceImpl]

method init*(self: PluginApi, services: Services, engine: ptr WasmEngineT) =
  self.host = HostContext()
  self.host.services = services
  self.host.platform = services.getService(PlatformService).get.platform
  self.host.commands = services.getService(CommandService).get
  self.host.editors = services.getService(DocumentEditorService).get
  self.host.layout = services.getService(LayoutService).get
  self.host.plugins = services.getService(PluginService).get
  self.host.settings = services.getService(ConfigService).get.runtime
  self.host.vfsService = services.getService(VFSService).get
  self.host.vfs = self.host.vfsService.vfs
  self.host.timer = startTimer()

  self.engine = engine
  self.linkerWasiNone = engine.newLinker()
  self.linkerWasiReduced = engine.newLinker()
  self.linkerWasiFull = engine.newLinker()

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

  # Link wasi
  self.linkerWasiReduced.definePluginWasi(getMemory).okOr(e):
    log lvlError, "Failed to define wasi imports: " & e.msg
    return

  self.linkerWasiFull.defineWasi().okOr(e):
    log lvlError, "Failed to define wasi imports: " & e.msg
    return

  # Link plugin API
  defineComponent(self.linkerWasiNone, self.host).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

  defineComponent(self.linkerWasiReduced, self.host).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

  defineComponent(self.linkerWasiFull, self.host).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

method setPermissions*(instance: WasmModuleInstanceImpl, permissions: PluginPermissions) =
  instance.instance.getMut.permissions = permissions

method createModule*(self: PluginApi, module: ptr ModuleT, plugin: Plugin): WasmModuleInstance =
  var wasmModule = Arc[InstanceData].new()
  wasmModule.getMut.store = self.engine.newStore(wasmModule.get.addr, nil)
  wasmModule.getMut.permissions = plugin.permissions
  wasmModule.getMut.namespace = plugin.manifest.id
  let ctx = wasmModule.get.store.context

  let wasiConfig = newWasiConfig()
  wasiConfig.inheritStdin()
  wasiConfig.inheritStderr()
  wasiConfig.inheritStdout()

  if not plugin.permissions.filesystemRead.disallowAll.get(false):
    for dir in plugin.permissions.wasiPreopenDirs:
      var dirPermissions: csize_t = 0
      var filePermissions: csize_t = 0
      if dir.read:
        dirPermissions = dirPermissions or WasiDirPermsRead.csize_t
        filePermissions = filePermissions or WasiFilePermsRead.csize_t
      if dir.write:
        dirPermissions = dirPermissions or WasiDirPermsWrite.csize_t
        filePermissions = filePermissions or WasiFilePermsWrite.csize_t
      let ok = wasiConfig.preopenDir(dir.host.cstring, dir.guest.cstring, dirPermissions, filePermissions)

  ctx.setWasi(wasiConfig).toResult(void).okOr(err):
    log lvlError, "Failed to setup wasi: " & err.msg
    return

  let linker = case plugin.permissions.wasi.get(Reduced)
  of None: self.linkerWasiNone
  of Reduced: self.linkerWasiReduced
  of Full: self.linkerWasiFull

  var trap: ptr WasmTrapT = nil
  wasmModule.getMut.instance = linker.instantiate(ctx, module, trap.addr).okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  trap.okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  collectExports(wasmModule.getMut.funcs, wasmModule.get.instance, ctx)

  let instance = WasmModuleInstanceImpl(instance: wasmModule)
  self.instances.add(instance)

  initPlugin(wasmModule.get.funcs).okOr(err):
    log lvlError, "Failed to call init-plugin: " & err.msg
    self.instances.removeShift(instance)
    return

  return instance

method destroyInstance*(self: PluginApi, instance: WasmModuleInstance) =
  let instance = instance.WasmModuleInstanceImpl
  let instanceData = instance.instance

  for commandId in instanceData.get.commands:
    self.host.commands.unregisterCommand(commandId)

  self.host.resources.dropResources(instanceData.get.store.context, callDestroy = true)
  instanceData.get.store.delete()
  self.instances.removeShift(instance)

###################################### Conversion functions #####################################

proc toInternal(c: Cursor): scripting_api.Cursor = (c.line.int, c.column.int)
proc toInternal(c: Selection): scripting_api.Selection = (c.first.toInternal, c.last.toInternal)

proc toWasm(c: scripting_api.Cursor): Cursor = Cursor(line: c.line.int32, column: c.column.int32)
proc toWasm(c: scripting_api.Selection): Selection = Selection(first: c.first.toWasm, last: c.last.toWasm)

proc toInternal(flags: ReadFlags): set[vfs.ReadFlag] =
  result = {}
  if ReadFlag.Binary in flags:
    result.incl vfs.ReadFlag.Binary

###################################### API implementations #####################################

proc editorActiveEditor(host: HostContext; store: ptr ContextT): Option[Editor] =
  if host.layout.tryGetCurrentEditorView().getSome(view):
    return Editor(id: view.editor.DocumentEditor.idNew.uint64).some
  return Editor.none

proc editorGetDocument(host: HostContext; store: ptr ContextT; editor: Editor): Option[Document] =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor):
    let document = editor.getDocument()
    if document != nil:
      return Document(id: document.id.uint64).some
  return Document.none

proc textEditorActiveTextEditor(host: HostContext; store: ptr ContextT): Option[TextEditor] =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    return TextEditor(id: view.editor.TextDocumentEditor.idNew.uint64).some
  return TextEditor.none

proc textEditorGetDocument(host: HostContext; store: ptr ContextT; editor: TextEditor): Option[TextDocument] =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor):
    let document = editor.getDocument()
    if document != nil and document of text_document.TextDocument:
      return TextDocument(id: document.id.uint64).some
  return TextDocument.none

proc textEditorAsTextEditor(host: HostContext; store: ptr ContextT; editor: Editor): Option[TextEditor] =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    return TextEditor(id: editor.TextDocumentEditor.idNew.uint64).some
  return TextEditor.none

proc textEditorAsTextDocument(host: HostContext; store: ptr ContextT; document: Document): Option[TextDocument] =
  if host.editors.getDocument(document.id.DocumentId).getSome(document) and document of text_document.TextDocument:
    return TextDocument(id: text_document.TextDocument(document).id.uint64).some
  return TextDocument.none

proc textEditorSetSelection(host: HostContext; store: ptr ContextT; editor: TextEditor; s: Selection): void =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    textEditor.selection = ((s.first.line.int, s.first.column.int), (s.last.line.int, s.last.column.int))

proc textEditorGetSelection(host: HostContext; store: ptr ContextT; editor: TextEditor): Selection =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    let s = textEditor.selection
    Selection(first: Cursor(line: s.first.line.int32, column: s.first.column.int32), last: Cursor(line: s.last.line.int32, column: s.last.column.int32))
  else:
    Selection(first: Cursor(line: 1, column: 2), last: Cursor(line: 6, column: 9))

proc textEditorEdit(host: HostContext; store: ptr ContextT; editor: TextEditor; selections: sink seq[Selection]; contents: sink seq[string]): seq[Selection] =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let selections = selections.mapIt(it.toInternal)
    let res = editor.TextDocumentEditor.edit(selections, contents)
    return res.mapIt(it.toWasm)
  return selections

proc textEditor_addModeChangedHandler(host: HostContext, store: ptr ContextT, fun: uint32): int32 =
  if host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    discard editor.onModeChanged.subscribe proc(args: tuple[removed: seq[string], added: seq[string]]) =
      let module = cast[ptr InstanceData](store.getData())
      let res = module[].funcs.handleModeChanged(fun, $args.removed, $args.added)
      if res.isErr:
        log lvlError, "Failed to call handleModeChanged: " & res.err.msg
  return 0

proc textEditorCommand(host: HostContext, store: ptr ContextT; editor: TextEditor, name: sink string, arguments: sink string): Result[string, CommandError] =
  let instance = cast[ptr InstanceData](store.getData())
  if not host.commands.checkPermissions(name, instance.permissions.commands):
    result.err(CommandError.NotAllowed)
    return
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    if editor.handleAction(name, arguments, true).getSome(res):
      return results.ok($res)
  result.err(CommandError.NotFound)

proc textEditorContent(host: HostContext; store: ptr ContextT; editor: TextEditor): RopeResource =
  if host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    if textEditor.document != nil:
      return RopeResource(rope: textEditor.document.rope.clone().slice().suffix(Point()))
  return RopeResource(rope: createRope("").slice().suffix(Point()))

proc textDocumentContent(host: HostContext; store: ptr ContextT; document: TextDocument): RopeResource =
  if host.editors.getDocument(document.id.DocumentId).getSome(document) and document of text_document.TextDocument:
    let textDocument = text_document.TextDocument(document)
    return RopeResource(rope: textDocument.rope.clone().slice().suffix(Point()))
  return RopeResource(rope: createRope("").slice().suffix(Point()))

proc typesNewRope(host: HostContext; store: ptr ContextT, content: sink string): RopeResource =
  return RopeResource(rope: createRope(content).slice().suffix(Point()))

proc typesClone(host: HostContext, store: ptr ContextT, self: var RopeResource): RopeResource =
  return RopeResource(rope: self.rope.clone())

proc typesText(host: HostContext, store: ptr ContextT, self: var RopeResource): string =
  return $self.rope

proc typesBytes(host: HostContext, store: ptr ContextT, self: var RopeResource): int64 =
  return self.rope.bytes.int64

proc typesRunes(host: HostContext, store: ptr ContextT, self: var RopeResource): int64 =
  return self.rope.runeLen.int64

proc typesLines(host: HostContext, store: ptr ContextT, self: var RopeResource): int64 =
  return self.rope.lines.int64

proc typesSlice(host: HostContext, store: ptr ContextT, self: var RopeResource, a: int64, b: int64): RopeResource =
  let a = min(a, b).clamp(0, self.rope.len)
  let b = max(a, b).clamp(0, self.rope.len)
  return RopeResource(rope: self.rope[a.int...b.int].suffix(Point()))

proc typesSlicePoints(host: HostContext, store: ptr ContextT, self: var RopeResource, a: Cursor, b: Cursor): RopeResource =
  let range = Point(row: a.line.uint32, column: a.column.uint32)...Point(row: a.line.uint32, column: a.column.uint32)
  return RopeResource(rope: self.rope[range])

proc isAllowed*(permissions: FilesystemPermissions, path: string, vfs: VFS): bool =
  if permissions.disallowAll.get(false):
    return false
  for prefix in permissions.disallow:
    if path.startsWith(vfs.normalize(prefix)):
      return false
  if permissions.allowAll.get(false):
    return true
  for prefix in permissions.allow:
    if path.startsWith(vfs.normalize(prefix)):
      return true
  return false

proc vfsReadSync(host: HostContext, store: ptr ContextT, path: sink string, readFlags: ReadFlags): Result[string, VfsError] =
  try:
    let instance = cast[ptr InstanceData](store.getData())
    let normalizedPath = host.vfs.normalize(path)
    if not instance.permissions.filesystemRead.isAllowed(normalizedPath, host.vfs):
      result.err(VfsError.NotAllowed)
      return
    return results.ok(host.vfs.read(normalizedPath, readFlags.toInternal).waitFor())
  except IOError as e:
    log lvlWarn, &"Failed to read file for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsReadRopeSync(host: HostContext, store: ptr ContextT, path: sink string, readFlags: ReadFlags): Result[RopeResource, VfsError] =
  try:
    let instance = cast[ptr InstanceData](store.getData())
    let normalizedPath = host.vfs.normalize(path)
    if not instance.permissions.filesystemRead.isAllowed(normalizedPath, host.vfs):
      result.err(VfsError.NotAllowed)
      return
    var rope: Rope = Rope.new()
    waitFor host.vfs.readRope(normalizedPath, rope.addr)
    return results.ok(RopeResource(rope: rope.slice().suffix(Point())))
  except IOError as e:
    log lvlWarn, &"Failed to read file for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsWriteSync(host: HostContext, store: ptr ContextT, path: sink string, content: sink string): Result[bool, VfsError] =
  try:
    let instance = cast[ptr InstanceData](store.getData())
    let normalizedPath = host.vfs.normalize(path)
    if not instance.permissions.filesystemWrite.isAllowed(normalizedPath, host.vfs):
      result.err(VfsError.NotAllowed)
      return
    host.vfs.write(normalizedPath, content).waitFor()
    return results.ok(true)
  except IOError as e:
    log lvlWarn, &"Failed to write file '{path}' for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsWriteRopeSync(host: HostContext, store: ptr ContextT, path: sink string, rope: sink RopeResource): Result[bool, VfsError] =
  try:
    let instance = cast[ptr InstanceData](store.getData())
    let normalizedPath = host.vfs.normalize(path)
    if not instance.permissions.filesystemWrite.isAllowed(normalizedPath, host.vfs):
      result.err(VfsError.NotAllowed)
      return
    host.vfs.write(normalizedPath, rope.rope.slice(int)).waitFor()
    return results.ok(true)
  except IOError as e:
    log lvlWarn, &"Failed to write file '{path}' for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsLocalize(host: HostContext, store: ptr ContextT, path: sink string): string =
  return host.vfs.localize(path)

proc coreGetTime(host: HostContext; store: ptr ContextT): float64 =
  let instance = cast[ptr InstanceData](store.getData())
  if not instance.permissions.time:
    return 0
  return host.timer.elapsed.ms

proc coreGetPlatform(host: HostContext, store: ptr ContextT): Platform =
  case host.platform.backend
  of scripting_api.Backend.Gui: return Platform.Gui
  of scripting_api.Backend.Terminal: return Platform.Tui

proc coreApiVersion(host: HostContext, store: ptr ContextT): int32 =
  return apiVersion

proc coreDefineCommand(host: HostContext, store: ptr ContextT, name: sink string, active: bool, docs: sink string,
                       params: sink seq[(string, string)], returnType: sink string, context: sink string; fun: uint32; data: uint32): void =
  let instance = cast[ptr InstanceData](store.getData())
  let command = Command(
    name: instance.namespace & "." & name.ensureMove,
    parameters: params.mapIt((it[0], it[1])),
    returnType: returnType.ensureMove,
    description: docs.ensureMove,
    execute: (proc(args: string): string {.gcsafe.} =
      let instance = cast[ptr InstanceData](store.getData())
      let res = instance[].funcs.handleCommand(fun, data, args).okOr(err):
        log lvlError, "Failed to call handleCommand: " & err.msg
        return ""

      return res
    ),
  )
  instance.commands.add(host.commands.registerCommand(command, override = true))

proc coreRunCommand(host: HostContext, store: ptr ContextT, name: sink string, arguments: sink string): Result[string, CommandError] =
  let instance = cast[ptr InstanceData](store.getData())
  if not host.commands.checkPermissions(name, instance.permissions.commands):
    result.err(CommandError.NotAllowed)
    return
  if host.commands.handleCommand(name & " " & arguments).getSome(res):
    return results.ok(res)
  result.err(CommandError.NotFound)

proc coreGetSettingRaw(host: HostContext, store: ptr ContextT, name: sink string): string =
  return $host.settings.get(name, JsonNodeEx)

proc coreSetSettingRaw(host: HostContext, store: ptr ContextT, name: sink string, value: sink string) =
  try:
    # todo: permissions
    host.settings.set(name, parseJsonex(value))
  except CatchableError as e:
    log lvlError, "coreSetSettingRaw: Failed to set setting '{name}' to {value}: {e.msg}"

proc renderNewRenderView(host: HostContext; store: ptr ContextT): RenderViewResource =
  let view = newRenderView(host.services)
  host.layout.registerView(view)
  return RenderViewResource(view: view)

proc layoutShow(host: HostContext; store: ptr ContextT; v: View, slot: sink string, focus: bool, addToHistory: bool) =
  host.layout.showView(v.id, slot.ensureMove, focus, addToHistory)

proc layoutClose(host: HostContext; store: ptr ContextT; v: View, keepHidden: bool, restoreHidden: bool) =
  host.layout.closeView(v.id, keepHidden, restoreHidden)

proc layoutFocus(host: HostContext; store: ptr ContextT, slot: sink string) =
  host.layout.focusView(slot.ensureMove)

proc renderRenderViewFromUserId(host: HostContext; store: ptr ContextT; id: sink string): Option[RenderViewResource] =
  if renderViewFromUserId(host.layout, id).getSome(view):
    return RenderViewResource(view: view).some
  return RenderViewResource.none

proc renderRenderViewFromView(host: HostContext; store: ptr ContextT; v: View): Option[RenderViewResource] =
  if host.layout.getView(v.id).getSome(view) and view of RenderView:
    return RenderViewResource(view: view.RenderView).some
  return RenderViewResource.none

proc renderView(host: HostContext; store: ptr ContextT; self: var RenderViewResource): View =
  return View(id: self.view.id2)

proc renderSetUserId(host: HostContext; store: ptr ContextT; self: var RenderViewResource, id: sink string) =
  self.view.userId = id.ensureMove

proc renderGetUserId(host: HostContext; store: ptr ContextT; self: var RenderViewResource): string =
  return self.view.userId

proc renderId(host: HostContext; store: ptr ContextT; self: var RenderViewResource): int32 =
  return self.view.id2

proc renderSize(host: HostContext; store: ptr ContextT; self: var RenderViewResource): Vec2f =
  return Vec2f(x: self.view.size.x, y: self.view.size.y)

proc renderKeyDown(host: HostContext; store: ptr ContextT; self: var RenderViewResource, key: int64): bool =
  return key in self.view.keyStates

proc renderSetRenderWhenInactive(host: HostContext; store: ptr ContextT; self: var RenderViewResource; enabled: bool): void =
  self.view.setRenderWhenInactive(enabled)

proc renderSetPreventThrottling(host: HostContext; store: ptr ContextT; self: var RenderViewResource; enabled: bool): void =
  self.view.preventThrottling = enabled

proc renderSetRenderInterval(host: HostContext; store: ptr ContextT; self: var RenderViewResource; ms: int32): void =
  self.view.setRenderInterval(ms.int)

proc renderSetRenderCommands(host: HostContext; store: ptr ContextT; self: var RenderViewResource; data: sink seq[uint8]): void =
  self.view.commands.raw = data.ensureMove

proc renderSetRenderCommandsRaw(host: HostContext; store: ptr ContextT; self: var RenderViewResource; buffer: uint32; len: uint32): void =
  let instance = cast[ptr InstanceData](store.getData())
  let mem = instance[].funcs.mem
  let buffer = buffer.WasmPtr
  let len = len.int

  self.view.commands.clear()
  var decoder = BinaryDecoder.init(mem.getOpenArray[:byte](buffer, len))
  try:
    for command in decoder.decodeRenderCommands():
      self.view.commands.commands.add(command)
  except ValueError as e:
    discard

proc renderMarkDirty(host: HostContext; store: ptr ContextT; self: var RenderViewResource): void =
  self.view.markDirty()

proc renderSetRenderCallback(host: HostContext; store: ptr ContextT; self: var RenderViewResource; fun: uint32; data: uint32): void =
  self.setRender = true
  self.view.onRender = proc(view: RenderView) =
    let instance = cast[ptr InstanceData](store.getData())
    instance[].funcs.handleViewRenderCallback(view.id2, fun, data).okOr(err):
      log lvlError, "Failed to call handleViewRenderCallback: " & err.msg

proc renderSetModes(host: HostContext; store: ptr ContextT; self: var RenderViewResource; modes: sink seq[string]): void =
  self.view.modes = modes

proc renderAddMode(host: HostContext; store: ptr ContextT; self: var RenderViewResource; mode: sink string): void =
  self.view.modes.add(mode)

proc renderRemoveMode(host: HostContext; store: ptr ContextT; self: var RenderViewResource; mode: sink string): void =
  self.view.modes.removeShift(mode)


###################### Channel

proc channelCanRead(host: HostContext; store: ptr ContextT; self: var ReadChannelResource): bool =
  return self.channel.isOpen

proc channelAtEnd(host: HostContext; store: ptr ContextT; self: var ReadChannelResource): bool =
  return self.channel.atEnd

proc channelPeek(host: HostContext; store: ptr ContextT; self: var ReadChannelResource): int32 =
  return self.channel.peek.int32

proc channelReadString(host: HostContext; store: ptr ContextT; self: var ReadChannelResource; num: int32): string =
  try:
    if num > 0:
      result.setLen(num)
      let read = self.channel.read(result.toOpenArrayByte(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelReadBytes(host: HostContext; store: ptr ContextT; self: var ReadChannelResource; num: int32): seq[uint8] =
  try:
    if num > 0:
      result.setLen(num)
      let read = self.channel.read(result.toOpenArray(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelReadAllString(host: HostContext; store: ptr ContextT; self: var ReadChannelResource): string =
  try:
    result.setLen(self.channel.peek)
    if result.len > 0:
      let read = self.channel.read(result.toOpenArrayByte(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelReadAllBytes(host: HostContext; store: ptr ContextT; self: var ReadChannelResource): seq[uint8] =
  try:
    result.setLen(self.channel.peek)
    if result.len > 0:
      let read = self.channel.read(result.toOpenArray(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelListen(host: HostContext; store: ptr ContextT; self: var ReadChannelResource, fun: uint32, data: uint32) =
  self.channel.stopListening(self.listenId)
  self.listenId = self.channel.listen proc(chan: var BaseChannel, closed: bool): channel.ChannelListenResponse {.gcsafe, raises: [].} =
    let module = cast[ptr InstanceData](store.getData())
    let res = module[].funcs.handleChannelUpdate(fun, data, closed)
    if res.isErr:
      log lvlError, "Failed to call handleChannelUpdate: " & res.err.msg
      return channel.Stop
    case res.val
    of Continue:
      return channel.Continue
    of Stop:
      return channel.Stop

proc channelWaitRead(host: HostContext; store: ptr ContextT; self: var ReadChannelResource; task: uint64; num: int32): bool =
  if self.channel.peek >= num.int or not self.channel.isOpen():
    return true

  self.listenId = self.channel.listen proc(chan: var BaseChannel, closed: bool): channel.ChannelListenResponse {.gcsafe, raises: [].} =
    let available = chan.peek
    if available >= num.int or not chan.isOpen():
      let module = cast[ptr InstanceData](store.getData())
      let res = module[].funcs.notifyTaskComplete(task, canceled = available < num.int)
      if res.isErr:
        log lvlError, "Failed to call notifyTaskComplete: " & res.err.msg
        return channel.Stop
      return channel.Stop
    return channel.Continue
  return false

proc channelClose(host: HostContext; store: ptr ContextT; self: var WriteChannelResource): void =
  self.channel.close()

proc channelCanWrite(host: HostContext; store: ptr ContextT; self: var WriteChannelResource): bool =
  return self.channel.isOpen

proc channelWriteString(host: HostContext; store: ptr ContextT; self: var WriteChannelResource; data: sink string): void =
  try:
    if data.len > 0:
      self.channel.write(data.toOpenArrayByte(0, data.high))
  except:
    discard

proc channelWriteBytes(host: HostContext; store: ptr ContextT; self: var WriteChannelResource; data: sink seq[uint8]): void =
  try:
    self.channel.write(data)
  except:
    discard

proc channelNewInMemoryChannel(host: HostContext; store: ptr ContextT): (ReadChannelResource, WriteChannelResource) =
  var c = newInMemoryChannel()
  return (ReadChannelResource(channel: c), WriteChannelResource(channel: c))

######################### Process

proc processProcessStart(host: HostContext; store: ptr ContextT; name: sink string; args: sink seq[string]): ProcessResource =
  try:
    var process = startAsyncProcess(name, args, killOnExit = true, autoStart = false)
    discard process.start()
    return ProcessResource(process: process)
  except:
    discard

proc processStdout(host: HostContext; store: ptr ContextT; self: var ProcessResource): ReadChannelResource =
  try:
    if self.stdout.isNil:
      self.stdout = newProcessOutputChannel(self.process)
    return ReadChannelResource(channel: self.stdout)
  except:
    discard

proc processStderr(host: HostContext; store: ptr ContextT; self: var ProcessResource): ReadChannelResource =
  # todo
  discard

proc processStdin(host: HostContext; store: ptr ContextT; self: var ProcessResource): WriteChannelResource =
  try:
    if self.stdin.isNil:
      self.stdin = newProcessInputChannel(self.process)
    return WriteChannelResource(channel: self.stdin)
  except:
    discard
