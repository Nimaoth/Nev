import std/[strutils, options, json, asynchttpserver, tables, sugar]
import misc/[id, custom_async, custom_logger, util, connection, myjsonutils, event]
import scripting/expose
import dap_client, dispatch_tables, app_interface, config_provider

logCategory "debugger"

type
  DebuggerConnectionKind = enum Tcp = "tcp", Stdio = "stdio", Websocket = "websocket"

  Debugger* = ref object
    app: AppInterface
    breakpoints: seq[SourceBreakpoint]

    client: Option[DapClient]

var gDebugger: Debugger = nil

proc getDebugger(): Option[Debugger] =
  if gDebugger.isNil: return Debugger.none
  return gDebugger.some

static:
  addInjector(Debugger, getDebugger)

proc createDebugger*(app: AppInterface) =
  gDebugger = Debugger(app: app)

proc stopDebugSession*(self: Debugger) {.expose("debugger").} =
  debugf"[stopDebugSession] Stopping session"
  if self.client.isNone:
    log lvlWarn, "No active debug session"
    return

  asyncCheck self.client.get.disconnect(restart=false)
  self.client = DapClient.none

template tryGet(json: untyped, field: untyped, T: untyped, default: untyped, els: untyped): untyped =
  block:
    let val = json.fields.getOrDefault(field, default)
    val.jsonTo(T).catch:
      els

proc getFreePort*(): Port =
  var server = newAsyncHttpServer()
  server.listen(Port(0))
  let port = server.getPort()
  server.close()
  return port

proc createConnectionWithType(self: Debugger, name: string): Future[Option[Connection]] {.async.} =
  log lvlInfo, &"Try create debugger connection '{name}'"

  let config = self.app.configProvider.getValue[:JsonNode]("debugger.type." & name, nil)
  if config.isNil or config.kind != JObject:
    log lvlError, &"No/invalid debugger type configuration with name '{name}' found: {config}"
    return Connection.none

  debugf"config: {config}"

  let connectionType = config.tryGet("connection", DebuggerConnectionKind, "stdio".newJString):
    log lvlError, &"No/invalid debugger connection type in {config.pretty}"
    return Connection.none

  debugf"{connectionType}"

  case connectionType
  of Tcp:
    when not defined(js):
      let host = config.tryGet("host", string, "127.0.0.1".newJString):
        log lvlError, &"No/invalid debugger connection type in {config.pretty}"
        return Connection.none
      let port = getFreePort()
      return newAsyncSocketConnection(host, port).await.Connection.some

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

proc setClient(self: Debugger, client: DAPClient) =
  assert self.client.isNone
  self.client = client.some

  discard client.onInitialized.subscribe (data: OnInitializedData) =>
    log(lvlInfo, &"onInitialized")
  discard client.onStopped.subscribe (data: OnStoppedData) =>
    log(lvlInfo, &"onStopped {data}")
  discard client.onContinued.subscribe (data: OnContinuedData) =>
    log(lvlInfo, &"onContinued {data}")
  discard client.onExited.subscribe (data: OnExitedData) =>
    log(lvlInfo, &"onExited {data}")
  discard client.onTerminated.subscribe (data: Option[OnTerminatedData]) =>
    log(lvlInfo, &"onTerminated {data}")
  discard client.onThread.subscribe (data: OnThreadData) =>
    log(lvlInfo, &"onThread {data}")
  discard client.onOutput.subscribe (data: OnOutputData) =>
    log(lvlInfo, &"[dap-{data.category}] {data.output}")
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

  let config = self.app.configProvider.getValue[:JsonNode]("debugger.configuration." & name, nil)
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

  let sourcePath = "/mnt/c/Absytree/temp/test.cpp" # todo
  await client.setBreakpoints(
    Source(path: sourcePath.some),
    @[
      SourceBreakpoint(line: 42),
      SourceBreakpoint(line: 52),
    ]
  )

  await client.configurationDone()

proc runConfiguration*(self: Debugger, name: string) {.expose("debugger").} =
  asyncCheck self.runConfigurationAsync(name)

proc addBreakpoint*(self: Debugger, file: string, line: int) {.expose("debugger").} =
  debugf"[addBreakpoint] '{file}' in line {line}"

genDispatcher("debugger")
addGlobalDispatchTable "debugger", genDispatchTable("debugger")

proc dispatchEvent*(action: string, args: JsonNode): bool =
  dispatch(action, args).isSome
