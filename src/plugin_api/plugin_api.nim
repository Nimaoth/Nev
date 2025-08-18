import std/[macros, strutils, os, strformat, sequtils, json, sets, pathnorm, locks, tables]
import misc/[custom_logger, custom_async, util, event, jsonex, timer, myjsonutils, render_command, binary_encoder, async_process]
import nimsumtree/[rope, sumtree, arc]
import service
import layout
import text/[text_editor, text_document]
import render_view, view
import platform/platform, platform_service
import config_provider, command_service
import plugin_service, document_editor, vfs, vfs_service, channel, register, terminal_service
import wasmtime, wit_host_module, plugin_api_base, wasi, plugin_thread_pool
from scripting_api import nil

{.push gcsafe, raises: [].}

logCategory "plugin-api-v0"

const apiVersion: int32 = 0

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

type
  HostContext* = ref object
    services: Services
    platform: Platform
    commands*: CommandService
    registers*: Registers
    terminals*: TerminalService
    editors*: DocumentEditorService
    layout*: LayoutService
    plugins*: PluginService
    settings*: ConfigStore
    vfsService*: VFSService
    vfs*: VFS
    timer*: Timer

  InstanceData = object of InstanceDataWasi
    resources*: WasmModuleResources
    isMainThread: bool
    engine: ptr WasmEngineT
    linker: ptr LinkerT
    module: ptr ModuleT
    instance: InstanceT
    store: ptr StoreT
    host: HostContext
    permissions: PluginPermissions
    commands: seq[CommandId]
    namespace: string
    args: string
    # channels: Arc[ChannelRegistry]
    destroyRequested: bool
    timer*: Timer

proc getMemoryFor(instance: ptr InstanceData, caller: ptr CallerT): Option[ExternT] =
  ExternT.none
  # var item: ExternT
  # item.kind = WASMTIME_EXTERN_SHAREDMEMORY
  # item.of_field.sharedmemory = host.sharedMemory
  # item.some

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

proc `=destroy`*(self: RenderViewResource) =
  if self.setRender and self.view != nil:
    self.view.onRender = nil

proc `=destroy`*(self: ReadChannelResource) =
  if self.channel.isNotNil:
    when defined(debugChannelDestroy):
      echo "=destroy ReadChannelResource ", self.channel.count
    `=destroy`(self.channel)

proc `=destroy`*(self: WriteChannelResource) =
  if self.channel.isNotNil:
    when defined(debugChannelDestroy):
      echo "=destroy WriteChannelResource ", self.channel.count
    `=destroy`(self.channel)

when defined(witRebuild):
  static: hint("Rebuilding plugin_api.wit")
  importWit "../../wit/v0/api.wit", InstanceData:
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
  InstanceDataImpl = object of InstanceData
    funcs: ExportedFuncs

  WasmModuleInstanceImpl* = ref object of WasmModuleInstance
    instance*: Arc[InstanceDataImpl]

###################################### PluginApi #####################################

type
  PluginApi* = ref object of PluginApiBase
    engine: ptr WasmEngineT
    linkerWasiNone: ptr LinkerT
    linkerWasiReduced: ptr LinkerT
    linkerWasiFull: ptr LinkerT
    host: HostContext
    instances: seq[WasmModuleInstanceImpl]
    # channels: Arc[ChannelRegistry]

method init*(self: PluginApi, services: Services, engine: ptr WasmEngineT) =
  self.host = HostContext()
  self.host.services = services
  self.host.platform = services.getService(PlatformService).get.platform
  self.host.commands = services.getService(CommandService).get
  self.host.registers = services.getService(Registers).get
  self.host.terminals = services.getService(TerminalService).get
  self.host.editors = services.getService(DocumentEditorService).get
  self.host.layout = services.getService(LayoutService).get
  self.host.plugins = services.getService(PluginService).get
  self.host.settings = services.getService(ConfigService).get.runtime
  self.host.vfsService = services.getService(VFSService).get
  self.host.vfs = self.host.vfsService.vfs
  self.host.timer = startTimer()

  # self.channels = Arc[ChannelRegistry].new()
  # self.channels.getMut.lock.initLock()

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
  defineComponent(self.linkerWasiNone).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

  defineComponent(self.linkerWasiReduced).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

  defineComponent(self.linkerWasiFull).okOr(err):
    log lvlError, "Failed to define component: " & err.msg
    return

method setPermissions*(instance: WasmModuleInstanceImpl, permissions: PluginPermissions) =
  instance.instance.getMut.permissions = permissions

method createModule*(self: PluginApi, module: ptr ModuleT, plugin: Plugin): WasmModuleInstance =
  var instanceData = Arc[InstanceDataImpl].new()
  instanceData.getMut.isMainThread = true
  instanceData.getMut.store = self.engine.newStore(instanceData.get.addr, nil)
  instanceData.getMut.engine = self.engine
  instanceData.getMut.module = module
  instanceData.getMut.permissions = plugin.permissions
  instanceData.getMut.namespace = plugin.manifest.id
  instanceData.getMut.host = self.host
  instanceData.getMut.stdin = newInMemoryChannel()
  instanceData.getMut.stdout = newInMemoryChannel()
  instanceData.getMut.stderr = newInMemoryChannel()
  # instanceData.getMut.channels = self.channels
  instanceData.getMut.timer = startTimer()
  let ctx = instanceData.get.store.context

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

  instanceData.getMut.linker = linker

  var trap: ptr WasmTrapT = nil
  instanceData.getMut.instance = linker.instantiate(ctx, module, trap.addr).okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  trap.okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  collectExports(instanceData.getMut.funcs, instanceData.get.instance, ctx)

  let instance = WasmModuleInstanceImpl(instance: instanceData)
  self.instances.add(instance)

  instanceData.get.funcs.initPlugin().okOr(err):
    log lvlError, "Failed to call init-plugin: " & err.msg
    self.instances.removeShift(instance)
    return

  let options = scripting_api.CreateTerminalOptions(
    group: plugin.manifest.id,
  )
  self.host.layout.registerView(self.host.terminals.createTerminalView(instanceData.get.stdin, instanceData.get.stdout, options))

  return instance

method destroyInstance*(self: PluginApi, instance: WasmModuleInstance) =
  let instance = instance.WasmModuleInstanceImpl
  let instanceData = instance.instance

  for commandId in instanceData.get.commands:
    self.host.commands.unregisterCommand(commandId)

  instanceData.getMutUnsafe.resources.dropResources(instanceData.get.store.context, callDestroy = true)
  instanceData.get.store.delete()
  self.instances.removeShift(instance)

template funcs(instance: ptr InstanceData): var ExportedFuncs = cast[ptr InstanceDataImpl](instance).funcs

method cloneInstance*(instance: ptr InstanceData): Arc[InstanceDataImpl] =
  var instanceData = Arc[InstanceDataImpl].new()
  instanceData.getMut.isMainThread = false
  instanceData.getMut.store = instance.engine.newStore(instanceData.get.addr, nil)
  instanceData.getMut.engine = instance.engine
  instanceData.getMut.linker = instance.linker
  instanceData.getMut.module = instance.module
  instanceData.getMut.permissions = instance.permissions
  instanceData.getMut.namespace = instance.namespace
  instanceData.getMut.host = instance.host
  # instanceData.getMut.channels = instance.channels
  instanceData.getMut.timer = startTimer()
  let ctx = instanceData.get.store.context

  let wasiConfig = newWasiConfig()
  wasiConfig.inheritStdin()
  wasiConfig.inheritStderr()
  wasiConfig.inheritStdout()

  if not instance.permissions.filesystemRead.disallowAll.get(false):
    for dir in instance.permissions.wasiPreopenDirs:
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

  var trap: ptr WasmTrapT = nil
  instanceData.getMut.instance = instance.linker.instantiate(ctx, instance.module, trap.addr).okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  trap.okOr(err):
    log lvlError, "Failed to create module instance: " & err.msg
    return

  collectExports(instanceData.getMut.funcs, instanceData.get.instance, ctx)
  return instanceData

proc runInstanceThread(instance: sink Arc[InstanceDataImpl]) =
  instance.getMutUnsafe.isMainThread = false
  instance.get.funcs.initPlugin().okOr(err):
    return

  while not instance.get.destroyRequested:
    poll(2000)

  instance.getMutUnsafe.resources.dropResources(instance.get.store.context, callDestroy = true)
  instance.get.store.delete()

# todo: make the size configurable
var threadPool = newPluginThreadPool[InstanceDataImpl](10, runInstanceThread)

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

proc editorActiveEditor(instance: ptr InstanceData): Option[Editor] =
  if instance.host == nil:
    return
  if instance.host.layout.tryGetCurrentEditorView().getSome(view):
    return Editor(id: view.editor.DocumentEditor.id.uint64).some
  return Editor.none

proc editorGetDocument(instance: ptr InstanceData; editor: Editor): Option[Document] =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor):
    let document = editor.getDocument()
    if document != nil:
      return Document(id: document.id.uint64).some
  return Document.none

proc textEditorActiveTextEditor(instance: ptr InstanceData): Option[TextEditor] =
  if instance.host == nil:
    return
  if instance.host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    return TextEditor(id: view.editor.TextDocumentEditor.id.uint64).some
  return TextEditor.none

proc textEditorGetDocument(instance: ptr InstanceData; editor: TextEditor): Option[TextDocument] =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor):
    let document = editor.getDocument()
    if document != nil and document of text_document.TextDocument:
      return TextDocument(id: document.id.uint64).some
  return TextDocument.none

proc textEditorAsTextEditor(instance: ptr InstanceData; editor: Editor): Option[TextEditor] =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    return TextEditor(id: editor.TextDocumentEditor.id.uint64).some
  return TextEditor.none

proc textEditorAsTextDocument(instance: ptr InstanceData; document: Document): Option[TextDocument] =
  if instance.host == nil:
    return
  if instance.host.editors.getDocument(document.id.DocumentId).getSome(document) and document of text_document.TextDocument:
    return TextDocument(id: text_document.TextDocument(document).id.uint64).some
  return TextDocument.none

proc textEditorLineLength(instance: ptr InstanceData; editor: TextEditor; line: int32): int32 =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    return editor.TextDocumentEditor.lineLength(line.int).int32

proc textEditorClearTabStops(instance: ptr InstanceData; editor: TextEditor): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.clearTabStops()

proc textEditorSelectNextTabStop(instance: ptr InstanceData; editor: TextEditor): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.selectNextTabStop()

proc textEditorSelectPrevTabStop(instance: ptr InstanceData; editor: TextEditor): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.selectPrevTabStop()

proc textEditorUndo(instance: ptr InstanceData; editor: TextEditor, checkpoint: sink string): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.undo(checkpoint)

proc textEditorRedo(instance: ptr InstanceData; editor: TextEditor, checkpoint: sink string): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.redo(checkpoint)

proc textEditorAddNextCheckpoint(instance: ptr InstanceData; editor: TextEditor, checkpoint: sink string): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.addNextCheckpoint(checkpoint)

proc textEditorCopy(instance: ptr InstanceData; editor: TextEditor, register: sink string, inclusiveEnd: bool): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.copy(register, inclusiveEnd)

proc textEditorPaste(instance: ptr InstanceData; editor: TextEditor, register: sink string, inclusiveEnd: bool): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.paste(register, inclusiveEnd)

proc textEditorApplyMove(instance: ptr InstanceData; editor: TextEditor; selection: Selection; move: sink string; count: int32; wrap: bool; includeEol: bool): seq[Selection] =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    return @[textEditor.getSelectionForMove(selection.last.toInternal, move, count).toWasm]

proc textEditorSetSelection(instance: ptr InstanceData; editor: TextEditor; s: Selection): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    textEditor.selection = ((s.first.line.int, s.first.column.int), (s.last.line.int, s.last.column.int))

proc textEditorSetSelections(instance: ptr InstanceData; editor: TextEditor; s: sink seq[Selection]): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    textEditor.selections = s.mapIt(it.toInternal)

proc textEditorGetSelection(instance: ptr InstanceData; editor: TextEditor): Selection =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    let s = textEditor.selection
    Selection(first: Cursor(line: s.first.line.int32, column: s.first.column.int32), last: Cursor(line: s.last.line.int32, column: s.last.column.int32))
  else:
    Selection(first: Cursor(line: 1, column: 2), last: Cursor(line: 6, column: 9))

proc textEditorGetSelections(instance: ptr InstanceData; editor: TextEditor): seq[Selection] =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    let s = textEditor.selection
    return editor.TextDocumentEditor.selections.mapIt(it.toWasm)

proc textEditorEdit(instance: ptr InstanceData; editor: TextEditor; selections: sink seq[Selection]; contents: sink seq[string]): seq[Selection] =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let selections = selections.mapIt(it.toInternal)
    let res = editor.TextDocumentEditor.edit(selections, contents)
    return res.mapIt(it.toWasm)
  return selections

proc textEditor_addModeChangedHandler(instance: ptr InstanceData, fun: uint32): int32 =
  if instance.host == nil:
    return
  if instance.host.layout.tryGetCurrentEditorView().getSome(view) and view.editor of TextDocumentEditor:
    let editor = view.editor.TextDocumentEditor
    discard editor.onModeChanged.subscribe proc(args: tuple[removed: seq[string], added: seq[string]]) =
      let res = instance.funcs.handleModeChanged(fun, $args.removed, $args.added)
      if res.isErr:
        log lvlError, "Failed to call handleModeChanged: " & res.err.msg
  return 0

proc textEditorSetMode(instance: ptr InstanceData; editor: TextEditor, mode: sink string, exclusive: bool): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.setMode(mode, exclusive)

proc textEditorMode(instance: ptr InstanceData; editor: TextEditor): string =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    return editor.TextDocumentEditor.mode()

proc textEditorCommand(instance: ptr InstanceData; editor: TextEditor, name: sink string, arguments: sink string): Result[string, CommandError] =
  if instance.host == nil:
    return
  if not instance.host.commands.checkPermissions(name, instance.permissions.commands):
    result.err(CommandError.NotAllowed)
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    if editor.handleAction(name, arguments, true).getSome(res):
      return results.ok($res)
  result.err(CommandError.NotFound)

proc textEditorRecordCurrentCommand(instance: ptr InstanceData; editor: TextEditor; registers: sink seq[string]): void =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    editor.TextDocumentEditor.recordCurrentCommand(registers)

proc textEditorGetUsage(instance: ptr InstanceData; editor: TextEditor): string =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    return editor.TextDocumentEditor.getUsage()

proc textEditorGetRevision(instance: ptr InstanceData; editor: TextEditor): int32 =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    return editor.TextDocumentEditor.getRevision().int32

proc textEditorContent(instance: ptr InstanceData; editor: TextEditor): RopeResource =
  if instance.host == nil:
    return
  if instance.host.editors.getEditor(editor.id.EditorIdNew).getSome(editor) and editor of TextDocumentEditor:
    let textEditor = editor.TextDocumentEditor
    if textEditor.document != nil:
      return RopeResource(rope: textEditor.document.rope.clone().slice().suffix(Point()))
  return RopeResource(rope: createRope("").slice().suffix(Point()))

proc textDocumentContent(instance: ptr InstanceData; document: TextDocument): RopeResource =
  if instance.host == nil:
    return
  if instance.host.editors.getDocument(document.id.DocumentId).getSome(document) and document of text_document.TextDocument:
    let textDocument = text_document.TextDocument(document)
    return RopeResource(rope: textDocument.rope.clone().slice().suffix(Point()))
  return RopeResource(rope: createRope("").slice().suffix(Point()))

proc typesNewRope(instance: ptr InstanceData, content: sink string): RopeResource =
  return RopeResource(rope: createRope(content).slice().suffix(Point()))

proc typesClone(instance: ptr InstanceData, self: var RopeResource): RopeResource =
  return RopeResource(rope: self.rope.clone())

proc typesText(instance: ptr InstanceData, self: var RopeResource): string =
  return $self.rope

proc typesBytes(instance: ptr InstanceData, self: var RopeResource): int64 =
  return self.rope.bytes.int64

proc typesRunes(instance: ptr InstanceData, self: var RopeResource): int64 =
  return self.rope.runeLen.int64

proc typesLines(instance: ptr InstanceData, self: var RopeResource): int64 =
  return self.rope.lines.int64

proc typesSlice(instance: ptr InstanceData, self: var RopeResource, a: int64, b: int64): RopeResource =
  let a = min(a, b).clamp(0, self.rope.len)
  let b = max(a, b).clamp(0, self.rope.len)
  return RopeResource(rope: self.rope[a.int...b.int].suffix(Point()))

proc typesSlicePoints(instance: ptr InstanceData, self: var RopeResource, a: Cursor, b: Cursor): RopeResource =
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

proc vfsReadSync(instance: ptr InstanceData, path: sink string, readFlags: ReadFlags): Result[string, VfsError] =
  if instance.host == nil:
    return
  try:
    let normalizedPath = instance.host.vfs.normalize(path)
    if not instance.permissions.filesystemRead.isAllowed(normalizedPath, instance.host.vfs):
      result.err(VfsError.NotAllowed)
      return
    return results.ok(instance.host.vfs.read(normalizedPath, readFlags.toInternal).waitFor())
  except IOError as e:
    log lvlWarn, &"Failed to read file for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsReadRopeSync(instance: ptr InstanceData, path: sink string, readFlags: ReadFlags): Result[RopeResource, VfsError] =
  if instance.host == nil:
    return
  try:
    let normalizedPath = instance.host.vfs.normalize(path)
    if not instance.permissions.filesystemRead.isAllowed(normalizedPath, instance.host.vfs):
      result.err(VfsError.NotAllowed)
      return
    var rope: Rope = Rope.new()
    waitFor instance.host.vfs.readRope(normalizedPath, rope.addr)
    return results.ok(RopeResource(rope: rope.slice().suffix(Point())))
  except IOError as e:
    log lvlWarn, &"Failed to read file for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsWriteSync(instance: ptr InstanceData, path: sink string, content: sink string): Result[bool, VfsError] =
  if instance.host == nil:
    return
  try:
    let normalizedPath = instance.host.vfs.normalize(path)
    if not instance.permissions.filesystemWrite.isAllowed(normalizedPath, instance.host.vfs):
      result.err(VfsError.NotAllowed)
      return
    instance.host.vfs.write(normalizedPath, content).waitFor()
    return results.ok(true)
  except IOError as e:
    log lvlWarn, &"Failed to write file '{path}' for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsWriteRopeSync(instance: ptr InstanceData, path: sink string, rope: sink RopeResource): Result[bool, VfsError] =
  if instance.host == nil:
    return
  try:
    let normalizedPath = instance.host.vfs.normalize(path)
    if not instance.permissions.filesystemWrite.isAllowed(normalizedPath, instance.host.vfs):
      result.err(VfsError.NotAllowed)
      return
    instance.host.vfs.write(normalizedPath, rope.rope.slice(int)).waitFor()
    return results.ok(true)
  except IOError as e:
    log lvlWarn, &"Failed to write file '{path}' for plugin: {e.msg}"
    result.err(VfsError.NotFound)

proc vfsLocalize(instance: ptr InstanceData, path: sink string): string =
  if instance.host == nil:
    return
  return instance.host.vfs.localize(path)

proc coreGetTime(instance: ptr InstanceData): float64 =
  if instance.host == nil:
    return
  if not instance.permissions.time:
    return 0
  return instance.host.timer.elapsed.ms

proc coreGetPlatform(instance: ptr InstanceData): Platform =
  if instance.host == nil:
    return
  case instance.host.platform.backend
  of scripting_api.Backend.Gui: return Platform.Gui
  of scripting_api.Backend.Terminal: return Platform.Tui

proc coreApiVersion(instance: ptr InstanceData): int32 =
  return apiVersion

proc coreIsMainThread(instance: ptr InstanceData): bool =
  return instance.isMainThread

proc coreGetArguments(instance: ptr InstanceData): string =
  return instance.args

type ThreadState = object
  instance: Arc[InstanceDataImpl]
  thread: Arc[typedthreads.Thread[ThreadState]]

proc threadFunc(s: ThreadState) {.thread, nimcall.} =
  chronosDontSkipCallbacksAtStart = true
  runInstanceThread(s.instance)

proc coreSpawnBackground(instance: ptr InstanceData, args: sink string, executor: BackgroundExecutor) =
  let newInstance = cloneInstance(instance)
  newInstance.getMutUnsafe.host = nil
  newInstance.getMutUnsafe.args = args.ensureMove

  case executor
  of BackgroundExecutor.Thread:
    var thread = Arc[typedthreads.Thread[ThreadState]].new()
    try:
      var state = ThreadState(
        thread: thread,
        instance: newInstance,
      )
      thread.getMutUnsafe.createThread(threadFunc, state)
    except ResourceExhaustedError as e:
      log lvlError, &"Failed to spawn plugin in background: {e.msg}"

  of BackgroundExecutor.ThreadPool:
    {.gcsafe.}: # threadPool is thread safe
      threadPool.addTask(newInstance)

proc coreFinishBackground(instance: ptr InstanceData) =
  instance.destroyRequested = true

proc registersIsReplayingCommands(instance: ptr InstanceData): bool =
  if instance.host == nil:
    return false
  return instance.host.registers.isReplayingCommands()

proc registersIsRecordingCommands(instance: ptr InstanceData; register: sink string): bool =
  if instance.host == nil:
    return false
  return instance.host.registers.isRecordingCommands(register)

proc registersSetRegisterText(instance: ptr InstanceData; text: sink string; register: sink string): void =
  if instance.host == nil:
    return
  instance.host.registers.setRegisterText(text, register)

proc registersGetRegisterText(instance: ptr InstanceData; register: sink string): string =
  if instance.host == nil:
    return
  return instance.host.registers.getRegisterText(register)

proc registersStartRecordingCommands(instance: ptr InstanceData; register: sink string): void =
  if instance.host == nil:
    return
  instance.host.registers.startRecordingCommands(register)

proc registersStopRecordingCommands(instance: ptr InstanceData; register: sink string): void =
  if instance.host == nil:
    return
  instance.host.registers.stopRecordingCommands(register)

proc commandsDefineCommand(instance: ptr InstanceData, name: sink string, active: bool, docs: sink string,
                       params: sink seq[(string, string)], returnType: sink string, context: sink string; fun: uint32; data: uint32): void =
  if instance.host == nil:
    return
  let command = Command(
    name: instance.namespace & "." & name.ensureMove,
    parameters: params.mapIt((it[0], it[1])),
    returnType: returnType.ensureMove,
    description: docs.ensureMove,
    execute: (proc(args: string): string {.gcsafe.} =
      let res = instance.funcs.handleCommand(fun, data, args).okOr(err):
        log lvlError, "Failed to call handleCommand: " & err.msg
        return ""

      return res
    ),
  )
  if active:
    instance.commands.add(instance.host.commands.registerActiveCommand(command, override = true))
  else:
    instance.commands.add(instance.host.commands.registerCommand(command, override = true))

proc commandsRunCommand(instance: ptr InstanceData, name: sink string, arguments: sink string): Result[string, CommandError] =
  if instance.host == nil:
    return
  if not instance.host.commands.checkPermissions(name, instance.permissions.commands):
    result.err(CommandError.NotAllowed)
    return
  if instance.host.commands.handleCommand(name & " " & arguments).getSome(res):
    return results.ok(res)
  result.err(CommandError.NotFound)

proc settingsGetSettingRaw(instance: ptr InstanceData, name: sink string): string =
  return $instance.host.settings.get(name, JsonNodeEx)

proc settingsSetSettingRaw(instance: ptr InstanceData, name: sink string, value: sink string) =
  try:
    # todo: permissions
    instance.host.settings.set(name, parseJsonex(value))
  except CatchableError as e:
    log lvlError, "coreSetSettingRaw: Failed to set setting '{name}' to {value}: {e.msg}"

proc renderNewRenderView(instance: ptr InstanceData): RenderViewResource =
  let view = newRenderView(instance.host.services)
  instance.host.layout.registerView(view)
  return RenderViewResource(view: view)

proc layoutShow(instance: ptr InstanceData; v: View, slot: sink string, focus: bool, addToHistory: bool) =
  instance.host.layout.showView(v.id, slot.ensureMove, focus, addToHistory)

proc layoutClose(instance: ptr InstanceData; v: View, keepHidden: bool, restoreHidden: bool) =
  instance.host.layout.closeView(v.id, keepHidden, restoreHidden)

proc layoutFocus(instance: ptr InstanceData, slot: sink string) =
  instance.host.layout.focusView(slot.ensureMove)

proc renderRenderViewFromUserId(instance: ptr InstanceData; id: sink string): Option[RenderViewResource] =
  if renderViewFromUserId(instance.host.layout, id).getSome(view):
    return RenderViewResource(view: view).some
  return RenderViewResource.none

proc renderRenderViewFromView(instance: ptr InstanceData; v: View): Option[RenderViewResource] =
  if instance.host.layout.getView(v.id).getSome(view) and view of RenderView:
    return RenderViewResource(view: view.RenderView).some
  return RenderViewResource.none

proc renderView(instance: ptr InstanceData; self: var RenderViewResource): View =
  return View(id: self.view.id2)

proc renderSetUserId(instance: ptr InstanceData; self: var RenderViewResource, id: sink string) =
  self.view.userId = id.ensureMove

proc renderGetUserId(instance: ptr InstanceData; self: var RenderViewResource): string =
  return self.view.userId

proc renderId(instance: ptr InstanceData; self: var RenderViewResource): int32 =
  return self.view.id2

proc renderSize(instance: ptr InstanceData; self: var RenderViewResource): Vec2f =
  return Vec2f(x: self.view.size.x, y: self.view.size.y)

proc renderKeyDown(instance: ptr InstanceData; self: var RenderViewResource, key: int64): bool =
  return key in self.view.keyStates

proc renderSetRenderWhenInactive(instance: ptr InstanceData; self: var RenderViewResource; enabled: bool): void =
  self.view.setRenderWhenInactive(enabled)

proc renderSetPreventThrottling(instance: ptr InstanceData; self: var RenderViewResource; enabled: bool): void =
  self.view.preventThrottling = enabled

proc renderSetRenderInterval(instance: ptr InstanceData; self: var RenderViewResource; ms: int32): void =
  self.view.setRenderInterval(ms.int)

proc renderSetRenderCommands(instance: ptr InstanceData; self: var RenderViewResource; data: sink seq[uint8]): void =
  self.view.commands.raw = data.ensureMove

proc renderSetRenderCommandsRaw(instance: ptr InstanceData; self: var RenderViewResource; buffer: uint32; len: uint32): void =
  let mem = instance.funcs.mem
  let buffer = buffer.WasmPtr
  let len = len.int

  self.view.commands.clear()
  var decoder = BinaryDecoder.init(mem.getOpenArray[:byte](buffer, len))
  try:
    for command in decoder.decodeRenderCommands():
      self.view.commands.commands.add(command)
  except ValueError as e:
    discard

proc renderMarkDirty(instance: ptr InstanceData; self: var RenderViewResource): void =
  self.view.markDirty()

proc renderSetRenderCallback(instance: ptr InstanceData; self: var RenderViewResource; fun: uint32; data: uint32): void =
  self.setRender = true
  self.view.onRender = proc(view: RenderView) =
    instance.funcs.handleViewRenderCallback(view.id2, fun, data).okOr(err):
      log lvlError, "Failed to call handleViewRenderCallback: " & err.msg

proc renderSetModes(instance: ptr InstanceData; self: var RenderViewResource; modes: sink seq[string]): void =
  self.view.modes = modes

proc renderAddMode(instance: ptr InstanceData; self: var RenderViewResource; mode: sink string): void =
  self.view.modes.add(mode)

proc renderRemoveMode(instance: ptr InstanceData; self: var RenderViewResource; mode: sink string): void =
  self.view.modes.removeShift(mode)


###################### Channel

proc channelCanRead(instance: ptr InstanceData; self: var ReadChannelResource): bool =
  return self.channel.isOpen

proc channelAtEnd(instance: ptr InstanceData; self: var ReadChannelResource): bool =
  return self.channel.atEnd

proc channelPeek(instance: ptr InstanceData; self: var ReadChannelResource): int32 =
  return self.channel.peek.int32

proc channelFlushRead(instance: ptr InstanceData; self: var ReadChannelResource): int32 =
  try:
    return self.channel.flushRead().int32
  except IOError:
    return self.channel.peek.int32

proc channelReadString(instance: ptr InstanceData; self: var ReadChannelResource; num: int32): string =
  try:
    if num > 0:
      result.setLen(num)
      let read = self.channel.read(result.toOpenArrayByte(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelReadBytes(instance: ptr InstanceData; self: var ReadChannelResource; num: int32): seq[uint8] =
  try:
    if num > 0:
      result.setLen(num)
      let read = self.channel.read(result.toOpenArray(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelReadAllString(instance: ptr InstanceData; self: var ReadChannelResource): string =
  try:
    result.setLen(self.channel.peek)
    if result.len > 0:
      let read = self.channel.read(result.toOpenArrayByte(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelReadAllBytes(instance: ptr InstanceData; self: var ReadChannelResource): seq[uint8] =
  try:
    result.setLen(self.channel.peek)
    if result.len > 0:
      let read = self.channel.read(result.toOpenArray(0, result.high))
      result.setLen(read)
  except IOError:
    discard

proc channelListen(instance: ptr InstanceData; self: var ReadChannelResource, fun: uint32, data: uint32) =
  self.channel.stopListening(self.listenId)
  self.listenId = self.channel.listen proc(chan: var BaseChannel, closed: bool): channel.ChannelListenResponse {.gcsafe, raises: [].} =
    let res = instance.funcs.handleChannelUpdate(fun, data, closed)
    if res.isErr:
      log lvlError, "Failed to call handleChannelUpdate: " & res.err.msg
      return channel.Stop
    case res.val
    of Continue:
      return channel.Continue
    of Stop:
      return channel.Stop

proc channelWaitRead(instance: ptr InstanceData; self: var ReadChannelResource; task: uint64; num: int32): bool =
  if self.channel.peek >= num.int or not self.channel.isOpen():
    return true

  self.listenId = self.channel.listen proc(chan: var BaseChannel, closed: bool): channel.ChannelListenResponse {.gcsafe, raises: [].} =
    let available = chan.peek
    if available >= num.int or not chan.isOpen():
      let res = instance.funcs.notifyTaskComplete(task, canceled = available < num.int)
      if res.isErr:
        log lvlError, "Failed to call notifyTaskComplete: " & res.err.msg
        return channel.Stop
      return channel.Stop
    return channel.Continue
  return false

proc channelClose(instance: ptr InstanceData; self: var WriteChannelResource): void =
  self.channel.close()

proc channelCanWrite(instance: ptr InstanceData; self: var WriteChannelResource): bool =
  return self.channel.isOpen

proc channelWriteString(instance: ptr InstanceData; self: var WriteChannelResource; data: sink string): void =
  try:
    if data.len > 0:
      self.channel.write(data.toOpenArrayByte(0, data.high))
  except CatchableError:
    discard

proc channelWriteBytes(instance: ptr InstanceData; self: var WriteChannelResource; data: sink seq[uint8]): void =
  try:
    self.channel.write(data)
  except CatchableError:
    discard

proc channelReadChannelOpen(instance: ptr InstanceData; path: sink string): Option[ReadChannelResource] =
  let chan = openGlobalReadChannel(path)
  if chan.isSome:
    return ReadChannelResource(channel: chan.get).some
  # let channels = instance.channels.getMutUnsafe.addr
  # withLock(channels.lock):
  #   var chan: ReadChannelResource
  #   if channels.readChannels.take(path, chan):
  #     return chan.some
  # return ReadChannelResource.none

proc channelReadChannelMount(instance: ptr InstanceData; channel: sink ReadChannelResource; path: sink string; unique: bool): string =
  mountGlobalReadChannel(path, channel.channel, unique)
  # var path = path
  # if unique:
  #   path.add "-" & $newId()
  # let channels = instance.channels.getMutUnsafe.addr
  # withLock(channels.lock):
  #   channels.readChannels[path] = channel
  #   return path

proc channelWriteChannelOpen(instance: ptr InstanceData; path: sink string): Option[WriteChannelResource] =
  let chan = openGlobalWriteChannel(path)
  if chan.isSome:
    return WriteChannelResource(channel: chan.get).some
  # let channels = instance.channels.getMutUnsafe.addr
  # withLock(channels.lock):
  #   var chan: WriteChannelResource
  #   if channels.writeChannels.take(path, chan):
  #     return chan.some
  # return WriteChannelResource.none

proc channelWriteChannelMount(instance: ptr InstanceData; channel: sink WriteChannelResource; path: sink string; unique: bool): string =
  mountGlobalWriteChannel(path, channel.channel, unique)
  # var path = path
  # if unique:
  #   path.add "-" & $newId()
  # let channels = instance.channels.getMutUnsafe.addr
  # withLock(channels.lock):
  #   channels.writeChannels[path] = channel
  #   return path

proc channelNewInMemoryChannel(instance: ptr InstanceData): (ReadChannelResource, WriteChannelResource) =
  var c = newInMemoryChannel()
  return (ReadChannelResource(channel: c), WriteChannelResource(channel: c))

######################### Process

proc processProcessStart(instance: ptr InstanceData; name: sink string; args: sink seq[string]): ProcessResource =
  try:
    var process = startAsyncProcess(name, args, killOnExit = true, autoStart = false)
    discard process.start()
    return ProcessResource(process: process)
  except CatchableError:
    discard

proc processStdout(instance: ptr InstanceData; self: var ProcessResource): ReadChannelResource =
  if self.stdout.isNil:
    self.stdout = newProcessOutputChannel(self.process)
  return ReadChannelResource(channel: self.stdout)

proc processStderr(instance: ptr InstanceData; self: var ProcessResource): ReadChannelResource =
  # todo
  discard

proc processStdin(instance: ptr InstanceData; self: var ProcessResource): WriteChannelResource =
  if self.stdin.isNil:
    self.stdin = newProcessInputChannel(self.process)
  return WriteChannelResource(channel: self.stdin)
