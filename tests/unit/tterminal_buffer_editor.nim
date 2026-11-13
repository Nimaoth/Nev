discard """
  action: "run"
  cmd: "nim $target --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[unittest, options, tables]
import terminal/[terminal, types_impl, render]
import document_editor, document, service, vfs_service, view
import input_handler/input_handler
import misc/[custom_async, event, id, jsonex]
import nimsumtree/rope
import nuigi
import nuigi/core/vecmath as nuiMath
import platform, event_service, move_database, workspace, command_service

gServices = Services()
gServices.addBuiltinServices()
gServices.getServiceChecked(PlatformService).setPlatform(Platform())
init_module_command_service()
init_module_vfs_service()
init_module_workspace()
init_module_event_service()
init_module_move_database()
gServices.waitForServices()

type
  SnapshotDocument = ref object of Document
    disposed: bool
  SnapshotEditor = ref object of DocumentEditor
    disposed: bool
    handler: EventHandler
  Fixture = object
    view: TerminalView
    editors: DocumentEditorService
    vfs: VFS

proc newFixture(): Fixture =
  let services = Services()
  result.editors = DocumentEditorService()
  result.vfs = newVFS()
  result.vfs.mount("ed://", newVFSInMemory())
  services.addService(result.editors)
  services.addService(VFSService(vfs: result.vfs))
  services.waitForServices()
  let documents = DocumentFactory()
  documents.canOpenFileImpl = proc(self: DocumentFactory, path: string): bool = true
  documents.createDocumentImpl = proc(self: DocumentFactory, services: Services,
      path: string, load: bool, options: JsonNodeEx, id: Option[Id]): Document =
    let document = SnapshotDocument(filename: path)
    document.deinitImpl = proc(self: Document) =
      self.SnapshotDocument.disposed = true
    document
  result.editors.addDocumentFactory(documents)
  let factory = DocumentEditorFactory()
  factory.canEditDocumentImpl = proc(self: DocumentEditorFactory,
      document: Document, options: JsonNodeEx): bool = true
  factory.createEditorImpl = proc(self: DocumentEditorFactory, services: Services,
      document: Document, options: JsonNodeEx): DocumentEditor =
    let editor = SnapshotEditor(currentDocument: document, handler: EventHandler())
    editor.init()
    editor.renderNuiImpl = proc(self: DocumentEditor, builder: var UiBuilder) =
      builder.node:
        discard builder.fill().text("Snapshot editor")
    editor.getEventHandlersImpl = proc(self: DocumentEditor,
        inject: Table[string, EventHandler]): seq[EventHandler] =
      @[self.SnapshotEditor.handler]
    editor.deinitImpl = proc(self: DocumentEditor) =
      self.SnapshotEditor.disposed = true
      services.getServiceChecked(DocumentEditorService).unregisterEditor(self)
    services.getServiceChecked(DocumentEditorService).registerEditor(editor)
    editor
  result.editors.addDocumentEditorFactory(factory)
  let terminal = Terminal(id: 42, width: 80, height: 24)
  terminal.inputChannel = cast[ptr system.Channel[InputEvent]](
    allocShared0(sizeof(system.Channel[InputEvent])))
  terminal.inputChannel[].open()
  terminal.handles.inputEventSignal = ThreadSignalPtr.new().value
  result.view = TerminalView(terminal: terminal, active: true,
    terminals: TerminalServiceImpl(services: services),
    onToggleBufferEditor: toggleBufferEditor)

proc cleanup(fixture: Fixture) =
  if fixture.view.bufferEditor != nil:
    fixture.view.toggleBufferEditor()
  if not fixture.view.terminal.threadTerminated:
    fixture.view.terminal.inputChannel[].close()
    deallocShared(fixture.view.terminal.inputChannel)
    discard fixture.view.terminal.handles.inputEventSignal.close()

proc deliverSnapshot(fixture: Fixture, content: string) =
  var event = fixture.view.terminal.inputChannel[].recv()
  while event.kind == InputEventKind.Viewport:
    event = fixture.view.terminal.inputChannel[].recv()
  doAssert event.kind == InputEventKind.RequestRope
  let snapshot = cast[ptr Rope](event.rope)
  snapshot[] = Rope.new(content)
  fixture.view.terminal.onRope.invoke(snapshot)
  waitFor sleepAsync(40.milliseconds)

proc measureText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  result.size = nuiMath.vec2(text.len.float32 * 8, 20)

proc renderFrame(view: TerminalView, builder: var UiBuilder,
    input = UiInputSnapshot()) =
  discard builder.beginUiFrame(800, 600, input)
  let parent = builder.currentNodeIndex
  var width, height, cellWidth, cellHeight: int
  view.renderTerminalNui(builder, width, height, cellWidth, cellHeight)
  doAssert builder.currentNodeIndex == parent
  builder.endUiFrame(buildMeshRenderCommands = false)

proc findText(builder: UiBuilder, text: string): int =
  for i in 0 ..< builder.frame.nodes.len:
    if builder.nodeText(i).text == text.uiString:
      return i
  -1

proc countText(builder: UiBuilder, text: string): int =
  for i in 0 ..< builder.frame.nodes.len:
    if builder.nodeText(i).text == text.uiString:
      inc result

suite "Terminal embedded text editor":
  test "hover-only Text button switches the live terminal body on both backends":
    for backend in [UiBackendType.Graphical, UiBackendType.Terminal]:
      let fixture = newFixture()
      defer: fixture.cleanup()
      var builder = newBuilder(measureText)
      builder.backendType = backend
      fixture.view.renderFrame(builder)
      check builder.findText("Text") == -1
      let title = builder.findText("Terminal")
      let header = builder.frame.nodes[builder.frame.nodes[title].parent].parent
      let headerHeight = builder.frame.nodes[header].size.y
      var input = UiInputSnapshot(mouse: builder.absoluteNodePos(title) + nuiMath.vec2(1, 1))
      fixture.view.renderFrame(builder, input)
      check builder.frame.nodes[header].size.y == headerHeight
      let button = builder.findText("Text")
      require button >= 0
      input.mouse = builder.absoluteNodePos(button) + nuiMath.vec2(1, 1)
      input.mousePressed = {MouseLeft}
      input.mouseDown = {MouseLeft}
      fixture.view.renderFrame(builder, input)
      input.mousePressed = {}
      input.mouseDown = {}
      input.mouseReleased = {MouseLeft}
      fixture.view.renderFrame(builder, input)
      check not fixture.view.loadingBufferEditor
      builder.flushNextFrameActions()
      check fixture.view.loadingBufferEditor
      fixture.deliverSnapshot("live output")
      fixture.view.renderFrame(builder)
      check builder.findText("Snapshot editor") >= 0

  test "toggle captures fresh output in the same view and disposes the snapshot on return":
    let fixture = newFixture()
    defer: fixture.cleanup()
    let terminal = fixture.view.terminal
    fixture.view.toggleBufferEditor()
    check fixture.view.loadingBufferEditor
    fixture.view.toggleBufferEditor()
    check terminal.inputChannel[].peek() == 1
    fixture.deliverSnapshot("first output")
    let editor = fixture.view.bufferEditor.SnapshotEditor
    require editor != nil
    check not fixture.view.loadingBufferEditor
    check not editor.renderHeader
    check editor.active
    check waitFor(fixture.vfs.read("ed://42.terminal-text")) == "first output"
    check fixture.view.getEventHandlers(initTable[string, EventHandler]()) == @[editor.handler]
    fixture.view.deactivateTerminalView()
    check not editor.active
    fixture.view.activateTerminalView()
    check editor.active
    fixture.view.toggleBufferEditor()
    check fixture.view.bufferEditor == nil
    check editor.disposed
    check editor.currentDocument.SnapshotDocument.disposed
    check fixture.view.open
    check fixture.view.terminal == terminal
    check terminal.inputChannel[].peek() == 0
    fixture.view.toggleBufferEditor()
    fixture.deliverSnapshot("new output")
    check fixture.view.bufferEditor != editor
    check waitFor(fixture.vfs.read("ed://42.terminal-text")) == "new output"

  test "editor body retains a hover-only return button with deferred dispatch":
    let fixture = newFixture()
    defer: fixture.cleanup()
    fixture.view.toggleBufferEditor()
    fixture.deliverSnapshot("output")
    var builder = newBuilder(measureText)
    fixture.view.renderFrame(builder)
    check builder.findText("Snapshot editor") >= 0
    check builder.countText("Terminal") == 1
    let title = builder.findText("Terminal")
    var input = UiInputSnapshot(mouse: builder.absoluteNodePos(title) + nuiMath.vec2(1, 1))
    fixture.view.renderFrame(builder, input)
    check builder.countText("Terminal") == 2
    # The right-side actions precede the title in reverse header layout.
    let button = builder.findText("Terminal")
    input.mouse = builder.absoluteNodePos(button) + nuiMath.vec2(1, 1)
    input.mousePressed = {MouseLeft}
    input.mouseDown = {MouseLeft}
    fixture.view.renderFrame(builder, input)
    input.mousePressed = {}
    input.mouseDown = {}
    input.mouseReleased = {MouseLeft}
    fixture.view.renderFrame(builder, input)
    check fixture.view.bufferEditor != nil
    builder.flushNextFrameActions()
    check fixture.view.bufferEditor == nil

  test "closing a terminal disposes its embedded editor":
    let fixture = newFixture()
    defer: fixture.cleanup()
    fixture.view.toggleBufferEditor()
    fixture.deliverSnapshot("output")
    let editor = fixture.view.bufferEditor.SnapshotEditor
    let terminal = fixture.view.terminal
    terminal.useChannels = true
    terminal.threadTerminated = true
    terminal.outputChannel = cast[ptr system.Channel[OutputEvent]](
      allocShared0(sizeof(system.Channel[OutputEvent])))
    terminal.outputChannel[].open()
    fixture.view.closeTerminalView()
    check not fixture.view.open
    check fixture.view.bufferEditor == nil
    check editor.disposed
    check editor.currentDocument.SnapshotDocument.disposed

  test "closing while a snapshot is pending does not create an editor":
    let fixture = newFixture()
    defer: fixture.cleanup()
    fixture.view.toggleBufferEditor()
    fixture.view.open = false
    fixture.deliverSnapshot("output after close")
    check fixture.view.bufferEditor == nil
    check not fixture.view.loadingBufferEditor
