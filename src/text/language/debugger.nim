import std/[strutils, options, json, tables, sugar]
import misc/[id, custom_async, custom_logger, util, connection, myjsonutils, event, response]
import scripting/expose
import dap_client, dispatch_tables, app_interface, config_provider, selector_popup_builder
import text/text_editor
import platform/platform
import finder/[previewer, finder, data_previewer]

import chroma

import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
from scripting_api as api import nil

when not defined(js):
  import std/[asynchttpserver, osproc]

logCategory "debugger"

let debuggerCurrentLineId = newId()

type
  DebuggerConnectionKind = enum Tcp = "tcp", Stdio = "stdio", Websocket = "websocket"

  Debugger* = ref object
    app: AppInterface
    client: Option[DapClient]
    lastConfiguration: Option[string]

    # Data setup in the editor and sent to the server
    breakpoints: Table[string, seq[SourceBreakpoint]]

    # Cached data from server
    threads: seq[ThreadInfo]
    stackTraces: Table[int, StackTraceResponse]

    # Other stuff
    currentThreadIndex: int

    lastEditor: Option[TextDocumentEditor]

    outputEditor*: TextDocumentEditor

proc applyBreakpointSignsToEditor(self: Debugger, editor: TextDocumentEditor)

var gDebugger: Debugger = nil

proc getDebugger*(): Option[Debugger] =
  if gDebugger.isNil: return Debugger.none
  return gDebugger.some

static:
  addInjector(Debugger, getDebugger)

proc getStateJson*(self: Debugger): JsonNode =
  return %*{
    "breakpoints": self.breakpoints,
  }

proc handleEditorRegistered*(self: Debugger, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return
  let editor = editor.TextDocumentEditor
  if editor.document.isNil:
    return

  if editor.document.isLoadingAsync:
    var id = new Id
    id[] = editor.document.onLoaded.subscribe proc(document: TextDocument) =
      document.onLoaded.unsubscribe(id[])
      self.applyBreakpointSignsToEditor(editor)
  else:
    self.applyBreakpointSignsToEditor(editor)

proc createDebugger*(app: AppInterface, state: JsonNode) =
  gDebugger = Debugger(app: app)

  let document = newTextDocument(app.configProvider, createLanguageServer=false)
  gDebugger.outputEditor = newTextEditor(document, app, app.configProvider)
  gDebugger.outputEditor.usage = "debugger-output"
  gDebugger.outputEditor.renderHeader = false
  gDebugger.outputEditor.disableCompletions = true

  discard app.onEditorRegisteredEvent.subscribe (e: DocumentEditor) => gDebugger.handleEditorRegistered(e)

  try:
    gDebugger.breakpoints = state["breakpoints"].jsonTo(Table[string, seq[SourceBreakpoint]])
  except:
    discard

  discard gDebugger.outputEditor.onMarkedDirty.subscribe () =>
    gDebugger.app.platform.requestRender()

proc currentThread*(self: Debugger): Option[ThreadInfo] =
  if self.currentThreadIndex >= 0 and self.currentThreadIndex < self.threads.len:
    return self.threads[self.currentThreadIndex].some
  return ThreadInfo.none

proc getThreads*(self: Debugger): lent seq[ThreadInfo] =
  return self.threads

proc getStackTrace*(self: Debugger, threadId: int): Option[StackTraceResponse] =
  if self.stackTraces.contains(threadId):
    return self.stackTraces[threadId].some
  return StackTraceResponse.none

proc stopDebugSession*(self: Debugger) {.expose("debugger").} =
  debugf"[stopDebugSession] Stopping session"
  if self.client.isNone:
    log lvlWarn, "No active debug session"
    return

  asyncCheck self.client.get.disconnect(restart=false)
  self.client.get.deinit()
  self.client = DapClient.none

proc stopDebugSessionDelayedAsync*(self: Debugger) {.async.} =
  let oldClient = self.client.getOr:
    return

  await sleepAsync(500)

  # Make sure to not stop the debug session if the client changed since this was triggered
  if self.client.getSome(client) and client == oldClient:
    self.stopDebugSession()

proc stopDebugSessionDelayed*(self: Debugger) {.expose("debugger").} =
  asyncCheck self.stopDebugSessionDelayedAsync()

template tryGet(json: untyped, field: untyped, T: untyped, default: untyped, els: untyped): untyped =
  block:
    let val = json.fields.getOrDefault(field, default)
    val.jsonTo(T).catch:
      els

when not defined(js):
  proc getFreePort*(): Port =
    var server = newAsyncHttpServer()
    server.listen(Port(0))
    let port = server.getPort()
    server.close()
    return port

proc createConnectionWithType(self: Debugger, name: string): Future[Option[Connection]] {.async.} =
  log lvlInfo, &"Try create debugger connection '{name}'"

  let config = self.app.configProvider.getValue[:JsonNode]("debugger.type." & name, newJNull())
  if config.isNil or config.kind != JObject:
    log lvlError, &"No/invalid debugger type configuration with name '{name}' found: {config}"
    return Connection.none

  let connectionType = config.tryGet("connection", DebuggerConnectionKind, "stdio".newJString):
    log lvlError, &"No/invalid debugger connection type in {config.pretty}"
    return Connection.none

  case connectionType
  of Tcp:
    when not defined(js):

      if config.hasKey("path"):
        let path = config.tryGet("path", string, newJNull()):
          log lvlError, &"No/invalid debugger executable path in {config.pretty}"
          return Connection.none

        let port = getFreePort().int
        log lvlInfo, &"Start process {path} with port {port}"
        discard startProcess(path, args = @["-p", $port], options = {poUsePath, poDaemon})

        # todo: need to wait for process to open port?
        await sleepAsync(500)

        return newAsyncSocketConnection("127.0.0.1", port.Port).await.Connection.some

      else:
        let host = config.tryGet("host", string, "127.0.0.1".newJString):
          log lvlError, &"No/invalid debugger host in {config.pretty}"
          return Connection.none
        let port = config.tryGet("port", int, 5678.newJInt):
          log lvlError, &"No/invalid debugger port in {config.pretty}"
          return Connection.none
        return newAsyncSocketConnection(host, port.Port).await.Connection.some

  of Stdio:
    when not defined(js):
      let exePath = config.tryGet("path", string, newJNull()):
        log lvlError, &"No/invalid debugger path in {config.pretty}"
        return Connection.none
      let args = config.tryGet("args", seq[string], newJArray()):
        log lvlError, &"No/invalid debugger args in {config.pretty}"
        return Connection.none
      debugf"{exePath}, {args}"
      return newAsyncProcessConnection(exePath, args).await.Connection.some

  of Websocket:
    log lvlError, &"Websocket connection not implemented yet!"

  return Connection.none

proc updateStackTrace(self: Debugger, threadId: Option[int]): Future[Option[int]] {.async.} =
  let threadId = if threadId.getSome(id):
    id
  elif self.currentThread.getSome(thread):
    thread.id
  else:
    return int.none

  if self.client.getSome(client):
    let stackTrace = await client.stackTrace(threadId)
    if stackTrace.isError:
      return int.none
    self.stackTraces[threadId] = stackTrace.result

  return threadId.some

proc handleStoppedAsync(self: Debugger, data: OnStoppedData) {.async.} =
  log(lvlInfo, &"onStopped {data}")

  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor = TextDocumentEditor.none

  let threadId = await self.updateStackTrace(data.threadId)

  if threadId.getSome(threadId) and self.stackTraces.contains(threadId):
    let stack {.cursor.} = self.stackTraces[threadId]

    if stack.stackFrames.len == 0:
      return

    let frame {.cursor.} = stack.stackFrames[0]

    if frame.source.isSome and frame.source.get.path.getSome(path):
      let editor = self.app.openWorkspaceFile(path, nil)

      if editor.getSome(editor) and editor of TextDocumentEditor:
        let textEditor = editor.TextDocumentEditor
        let location: Cursor = (frame.line - 1, frame.column - 1)
        textEditor.targetSelection = location.toSelection

        let lineSelection = ((location.line, 0), (location.line, textEditor.lineLength(location.line)))
        textEditor.addCustomHighlight(debuggerCurrentLineId, lineSelection, "editorError.foreground", color(1, 1, 1, 0.3))
        self.lastEditor = textEditor.some

proc handleStopped(self: Debugger, data: OnStoppedData) =
  asyncCheck self.handleStoppedAsync(data)

proc handleContinued(self: Debugger, data: OnContinuedData) =
  log(lvlInfo, &"onContinued {data}")

proc handleTerminated(self: Debugger, data: Option[OnTerminatedData]) =
  log(lvlInfo, &"onTerminated {data}")
  if self.lastEditor.isSome:
    self.lastEditor.get.clearCustomHighlights(debuggerCurrentLineId)
    self.lastEditor = TextDocumentEditor.none
  self.stopDebugSessionDelayed()

proc handleOutput(self: Debugger, data: OnOutputData) =
  if self.outputEditor.isNil:
    log(lvlInfo, &"[dap-{data.category}] {data.output}")
    return

  if data.category == "stdout".some:
    let document = self.outputEditor.document

    let selection = document.lastCursor.toSelection
    discard document.insert([selection], [selection], [data.output.replace("\r\n", "\n")])

    if self.outputEditor.selection == selection:
      self.outputEditor.selection = document.lastCursor.toSelection
      self.outputEditor.scrollToCursor()

  else:
    log(lvlInfo, &"[dap-{data.category}] {data.output}")

proc setClient(self: Debugger, client: DAPClient) =
  assert self.client.isNone
  self.client = client.some

  discard client.onInitialized.subscribe (data: OnInitializedData) =>
    log(lvlInfo, &"onInitialized")
  discard client.onStopped.subscribe (data: OnStoppedData) => self.handleStopped(data)
  discard client.onContinued.subscribe (data: OnContinuedData) => self.handleContinued(data)
  discard client.onExited.subscribe (data: OnExitedData) =>
    log(lvlInfo, &"onExited {data}")
  discard client.onTerminated.subscribe (data: Option[OnTerminatedData]) => self.handleTerminated(data)
  discard client.onThread.subscribe (data: OnThreadData) =>
    log(lvlInfo, &"onThread {data}")
  discard client.onOutput.subscribe (data: OnOutputData) => self.handleOutput(data)
  discard client.onBreakpoint.subscribe (data: OnBreakpointData) =>
    log(lvlInfo, &"onBreakpoint {data}")
  discard client.onModule.subscribe (data: OnModuleData) =>
    log(lvlInfo, &"onModule {data}")
  discard client.onLoadedSource.subscribe (data: OnLoadedSourceData) =>
    log(lvlInfo, &"onLoadedSource {data}")
  discard client.onProcess.subscribe (data: OnProcessData) =>
    log(lvlInfo, &"onProcess {data}")
  discard client.onCapabilities.subscribe (data: OnCapabilitiesData) =>
    log(lvlInfo, &"onCapabilities {data}")
  discard client.onProgressStart.subscribe (data: OnProgressStartData) =>
    log(lvlInfo, &"onProgressStart {data}")
  discard client.onProgressUpdate.subscribe (data: OnProgressUpdateData) =>
    log(lvlInfo, &"onProgressUpdate {data}")
  discard client.onProgressEnd.subscribe (data: OnProgressEndData) =>
    log(lvlInfo, &"onProgressEnd {data}")
  discard client.onInvalidated.subscribe (data: OnInvalidatedData) =>
    log(lvlInfo, &"onInvalidated {data}")
  discard client.onMemory.subscribe (data: OnMemoryData) =>
    log(lvlInfo, &"onMemory {data}")

proc runConfigurationAsync(self: Debugger, name: string) {.async.} =
  if self.client.isSome:
    self.stopDebugSession()

  assert self.client.isNone
  debugf"[runConfigurationAsync] Launch '{name}'"

  let config = self.app.configProvider.getValue[:JsonNode]("debugger.configuration." & name, newJNull())
  if config.isNil or config.kind != JObject:
    log lvlError, &"No/invalid configuration with name '{name}' found: {config}"
    return

  let request = config.tryGet("request", string, "launch".newJString):
    log lvlError, &"No/invalid debugger request in {config.pretty}"
    return

  let typ = config.tryGet("type", string, newJNull()):
    log lvlError, &"No/invalid debugger type in {config.pretty}"
    return

  let connection = await self.createConnectionWithType(typ)
  if connection.isNone:
    log lvlError, &"Failed to create connection for typ '{typ}'"
    return

  self.lastConfiguration = name.some

  let client = newDAPClient(connection.get)
  self.setClient(client)
  await client.initialize()
  if not client.waitInitialized.await:
    log lvlError, &"Client failed to initialized"
    client.deinit()
    self.client = DAPClient.none
    return

  case request
  of "launch":
    await client.launch(config)

  of "attach":
    await client.attach(config)

  else:
    log lvlError, &"Invalid request type '{request}', expected 'launch' or 'attach'"
    self.client = DAPClient.none
    client.deinit()
    return

  when defined(linux):
    let sourcePath = "/mnt/c/Absytree/temp/test.cpp" # todo
  else:
    let sourcePath = "C:/Absytree/temp/test.cpp" # todo
  await client.setBreakpoints(
    Source(path: sourcePath.some),
    @[
      SourceBreakpoint(line: 31),
      SourceBreakpoint(line: 42),
      SourceBreakpoint(line: 52),
    ]
  )

  let threads = await client.getThreads
  if threads.isError:
    log lvlError, &"Failed to get threads: {threads}"
    return

  self.threads = threads.result.threads

  await client.configurationDone()

proc runConfiguration*(self: Debugger, name: string) {.expose("debugger").} =
  asyncCheck self.runConfigurationAsync(name)

proc chooseRunConfiguration(self: Debugger) {.expose("debugger").} =
  var builder = SelectorPopupBuilder()
  builder.scope = "choose-run-configuration".some
  builder.previewScale = 0.7
  builder.scaleX = 0.5
  builder.scaleY = 0.5

  let config = self.app.configProvider.getValue[:JsonNode]("debugger.configuration", newJObject())
  if config.kind != JObject:
    log lvlError, &"No/invalid debugger configuration: {config}"
    return

  var res = newSeq[FinderItem]()
  for (name, config) in config.fields.pairs:
    res.add FinderItem(
      displayName: name,
      data: config.pretty,
    )

  builder.previewer = newDataPreviewer(self.app.configProvider, language="javascript".some).Previewer.some

  let finder = newFinder(newStaticDataSource(res), filterAndSort=true)
  builder.finder = finder.some

  builder.handleItemConfirmed = proc(popup: ISelectorPopup, item: FinderItem): bool =
    self.runConfiguration(item.displayName)
    true

  discard self.app.pushSelectorPopup(builder)

proc runLastConfiguration*(self: Debugger) {.expose("debugger").} =
  if self.lastConfiguration.getSome(name):
    asyncCheck self.runConfigurationAsync(name)
  else:
    self.chooseRunConfiguration()

proc applyBreakpointSignsToEditor(self: Debugger, editor: TextDocumentEditor) =
  editor.clearSigns("breakpoints")

  if editor.document.isNil:
    return

  if not self.breakpoints.contains(editor.document.filename):
    return

  for  breakpoint in self.breakpoints[editor.document.filename]:
    discard editor.TextDocumentEditor.addSign(idNone(), breakpoint.line, "🛑", group = "breakpoints")

proc addBreakpoint*(self: Debugger, editorId: EditorId, line: int) {.expose("debugger").} =
  if self.app.getEditorForId(editorId).getSome(editor) and editor of TextDocumentEditor:
    let path = editor.TextDocumentEditor.document.filename
    if not self.breakpoints.contains(path):
      self.breakpoints[path] = @[]

    for i, breakpoint in self.breakpoints[path]:
      if breakpoint.line == line:
        # Breakpoint already exists, remove
        self.breakpoints[path].removeSwap(i)
        self.applyBreakpointSignsToEditor(editor.TextDocumentEditor)
        return

    self.breakpoints[path].add SourceBreakpoint(line: line)
    self.applyBreakpointSignsToEditor(editor.TextDocumentEditor)

proc continueExecution*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncCheck client.continueExecution(thread.id)

proc stepOver*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncCheck client.next(thread.id)

proc stepIn*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncCheck client.stepIn(thread.id)

proc stepOut*(self: Debugger) {.expose("debugger").} =
  if self.currentThread.getSome(thread) and self.client.getSome(client):
    asyncCheck client.stepOut(thread.id)

genDispatcher("debugger")
addGlobalDispatchTable "debugger", genDispatchTable("debugger")

proc dispatchEvent*(action: string, args: JsonNode): bool =
  dispatch(action, args).isSome
