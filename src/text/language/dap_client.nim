import std/[json, strutils, strformat, macros, options, tables, sets, uri, sequtils, sugar, os]
import misc/[custom_logger, async_http_client, websocket, util, event, myjsonutils, custom_async, response]
import platform/filesystem
import scripting/expose
import dispatch_tables

logCategory "dap"

var logVerbose = true
var logServerDebug = true

proc fromJsonHook*[T](a: var Response[T], b: JsonNode, opt = Joptions()) =
  if not b["success"].getBool:
    a = Response[T](
      id: b["request_seq"].getInt,
      kind: ResponseKind.Error,
      error: ResponseError(
        message:  b["message"].getStr,
        data: b.getOrDefault("body"),
      )
    )
  else:
    a = Response[JsonNode](id: b["request_seq"].getInt, kind: ResponseKind.Success, result: b.getOrDefault("body")).to T

proc toResponse*(node: JsonNode, T: typedesc): Response[T] =
  fromJsonHook[T](result, node)

type
  StartMethod* = enum
    Launch = "launch"
    Attach = "attach"
    AttachForSuspendedLaunch = "attachForSuspendedLaunch"

  GroupKind* = enum
    Start = "start"
    StartCollapsed = "startCollapsed"
    End = "end"

  ChecksumAlgorithm* = enum
    MD5 = "MD5"
    SHA1 = "SHA1"
    SHA256 = "SHA256"
    Timestamp = "timestamp"

  Checksum* = object
    algorithm*: ChecksumAlgorithm
    checksum*: string

  Source* = object
    name*: Option[string]
    path*: Option[string]
    sourceReference*: Option[int]
    presentationHint*: Option[string]
    origin*: Option[string]
    sources*: seq[Source]
    adapterData*: Option[JsonNode]
    checksums*: seq[Checksum]

  Breakpoint* = object
    id*: Option[int]
    verified*: bool
    message*: Option[string]
    source*: Option[Source]
    line*: Option[int]
    column*: Option[int]
    endLine*: Option[int]
    endColumn*: Option[int]
    instructionReference*: Option[string]
    offset*: Option[int]
    reason*: Option[string]

  Module* = object
    id*: Option[JsonNode] # number | string
    name*: Option[string]
    path*: Option[string]
    isOptimized*: Option[bool]
    isUserCode*: Option[bool]
    version*: Option[string]
    symbolStatus*: Option[string]
    symbolFilePath*: Option[string]
    dateTimeStamp*: Option[string]
    addressRange*: Option[string]

  Capabilities* = object
    supportsConfigurationDoneRequest*: Option[bool]
    supportsFunctionBreakpoints*: Option[bool]
    supportsConditionalBreakpoints*: Option[bool]
    supportsHitConditionalBreakpoints*: Option[bool]
    supportsEvaluateForHovers*: Option[bool]
    exceptionBreakpointFilters*: seq[ExceptionBreakpointsFilter]
    supportsStepBack*: Option[bool]
    supportsSetVariable*: Option[bool]
    supportsRestartFrame*: Option[bool]
    supportsGotoTargetsRequest*: Option[bool]
    supportsCompletionsRequest*: Option[bool]
    completionTriggerCharacters*: seq[string]
    supportsModulesRequest*: Option[bool]
    additionalModuleColumns*: seq[ColumnDescriptor]
    supportedChecksumAlgorithms*: seq[ChecksumAlgorithm]
    supportsRestartRequest*: Option[bool]
    supportsExceptionOptions*: Option[bool]
    supportsValueFormattingOptions*: Option[bool]
    supportsExceptionInfoRequest*: Option[bool]
    supportsTerminateDebuggee*: Option[bool]
    supportsSuspendDebuggee*: Option[bool]
    supportsDelayedStackTraceLoading*: Option[bool]
    supportsLoadedSourcesRequest*: Option[bool]
    supportsLogPoints*: Option[bool]
    supportsTerminateThreadsRequest*: Option[bool]
    supportsSetExpressions*: Option[bool]
    supportsTerminateRequest*: Option[bool]
    supportsDataBreakpoints*: Option[bool]
    supportsReadMemoryRequest*: Option[bool]
    supportsWriteMemoryRequest*: Option[bool]
    supportsDisassembleRequest*: Option[bool]
    supportsCancelRequest*: Option[bool]
    supportsBreakpointLocationsRequest*: Option[bool]
    supportsClipboardContext*: Option[bool]
    supportsSteppingGranularity*: Option[bool]
    supportsInstructionBreakpoints*: Option[bool]
    supportsExceptionFilterOptions*: Option[bool]
    supportsSingleThreadExecutionRequests*: Option[bool]
    breakpointModes*: seq[BreakpointMode]

  InvalidatedAreas* = object
    name*: Option[string]

  ExceptionBreakpointsFilter* = object
    name*: Option[string]

  ColumnDescriptor* = object
    name*: Option[string]

  BreakpointMode* = object
    name*: Option[string]

  OnInitializedData* = void

  OnStoppedData* = object
    reason*: string
    description*: Option[string]
    threadId*: Option[int]
    preserveFocusHint*: Option[bool]
    text*: Option[string]
    allThreadsStopped*: Option[bool]
    hitBreakpointIds*: seq[int]

  OnContinuedData* = object
    threadId*: int
    allThreadsContinued*: Option[bool]

  OnExitedData* = object
    exitCode*: int

  OnTerminatedData* = object
    restart*: Option[JsonNode]

  OnThreadData* = object
    reason*: string
    threadId*: int

  OnOutputData* = object
    category*: Option[string]
    output*: string
    group*: Option[GroupKind]
    variablesReference*: Option[int]
    source*: Option[Source]
    line*: Option[int]
    column*: Option[int]
    data*: Option[JsonNode]

  OnBreakpointData* = object
    reason*: string
    breakpoint*: Breakpoint

  OnModuleData* = object
    reason*: string
    module*: Module

  OnLoadedSourceData* = object
    reason*: string
    source*: Source

  OnProcessData* = object
    name*: string
    systemProcessId*: Option[int]
    isLocalProcess: Option[bool]
    startMethod: Option[StartMethod]
    pointerSize: Option[int]

  OnCapabilitiesData* = object
    capabilities*: Capabilities

  OnProgressStartData* = object
    progressId*: string
    title*: string
    requestId*: Option[int]
    cancellable*: Option[bool]
    message*: Option[string]
    percentage*: Option[float]

  OnProgressUpdateData* = object
    progressId*: string
    message*: Option[string]
    percentage*: Option[float]

  OnProgressEndData* = object
    progressId*: string
    message*: Option[string]

  OnInvalidatedData* = object
    areas*: seq[InvalidatedAreas]
    threadId*: Option[int]
    stackFrameId*: Option[int]

  OnMemoryData* = object
    memoryReference*: string
    offset*: int
    count*: int

type
  DAPConnection = ref object of RootObj

  DAPClient* = ref object
    connection: DAPConnection
    nextId: int = 1
    activeRequests: Table[int, tuple[command: string, future: ResolvableFuture[Response[JsonNode]]]]
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    isInitialized: bool
    initializedFuture: ResolvableFuture[bool]

    onInitialized*: Event[OnInitializedData]
    onStopped*: Event[OnStoppedData]
    onContinued*: Event[OnContinuedData]
    onExited*: Event[OnExitedData]
    onTerminated*: Event[OnTerminatedData]
    onThread*: Event[OnThreadData]
    onOutput*: Event[OnOutputData]
    onBreakpoint*: Event[OnBreakpointData]
    onModule*: Event[OnModuleData]
    onLoadedSource*: Event[OnLoadedSourceData]
    onProcess*: Event[OnProcessData]
    onCapabilities*: Event[OnCapabilitiesData]
    onProgressStart*: Event[OnProgressStartData]
    onProgressUpdate*: Event[OnProgressUpdateData]
    onProgressEnd*: Event[OnProgressEndData]
    onInvalidated*: Event[OnInvalidatedData]
    onMemory*: Event[OnMemoryData]

proc waitInitialized*(client: DAPCLient): Future[bool] = client.initializedFuture.future

method close(connection: DAPConnection) {.base.} = discard
method recvLine(connection: DAPConnection): Future[string] {.base.} = discard
method recv(connection: DAPConnection, length: int): Future[string] {.base.} = discard
method send(connection: DAPConnection, data: string): Future[void] {.base.} = discard

when not defined(js):
  import misc/[async_process]
  type DAPConnectionAsyncProcess = ref object of DAPConnection
    process: AsyncProcess

  method close(connection: DAPConnectionAsyncProcess) = connection.process.destroy
  method recvLine(connection: DAPConnectionAsyncProcess): Future[string] = connection.process.recvLine
  method recv(connection: DAPConnectionAsyncProcess, length: int): Future[string] = connection.process.recv(length)
  method send(connection: DAPConnectionAsyncProcess, data: string): Future[void] = connection.process.send(data)

type DAPConnectionWebsocket = ref object of DAPConnection
  websocket: WebSocket
  buffer: string
  processId: int

method close(connection: DAPConnectionWebsocket) = connection.websocket.close()
method recvLine(connection: DAPConnectionWebsocket): Future[string] {.async.} =
  var newLineIndex = connection.buffer.find("\r\n")
  while newLineIndex == -1:
    let next = connection.websocket.receiveStrPacket().await
    connection.buffer.append next
    newLineIndex = connection.buffer.find("\r\n")

  let line = connection.buffer[0..<newLineIndex]
  connection.buffer = connection.buffer[newLineIndex + 2..^1]
  return line

method recv(connection: DAPConnectionWebsocket, length: int): Future[string] {.async.} =
  while connection.buffer.len < length:
    connection.buffer.add connection.websocket.receiveStrPacket().await

  let res = connection.buffer[0..<length]
  connection.buffer = connection.buffer[length..^1]
  return res

method send(connection: DAPConnectionWebsocket, data: string): Future[void] = connection.websocket.send(data)

proc encodePathUri(path: string): string = path.normalizePathUnix.split("/").mapIt(it.encodeUrl(false)).join("/")

when defined(js):
  # todo
  proc absolutePath(path: string): string = path

proc toUri*(path: string): Uri =
  return parseUri("file:///" & path.absolutePath.encodePathUri) # todo: use file://{} for linux

proc createHeader*(contentLength: int): string =
  let header = fmt"Content-Length: {contentLength}" & "\r\n\r\n"
  return header

proc deinit*(client: DAPClient) =
  assert client.connection.isNotNil, "DAP Client process should not be nil"

  log lvlInfo, "Deinitializing DAP client"
  client.connection.close()
  client.connection = nil
  client.nextId = 0
  client.activeRequests.clear()
  client.requestsPerMethod.clear()
  client.canceledRequests.clear()
  client.isInitialized = false

proc parseResponse(client: DAPClient): Future[JsonNode] {.async.} =
  debugf"[parseResponse]"
  var headers = initTable[string, string]()
  var line = await client.connection.recvLine
  while client.connection.isNotNil and line == "":
    line = await client.connection.recvLine

  if client.connection.isNil:
    log(lvlError, "[parseResponse] Connection is nil")
    return newJNull()

  var success = true
  var lines = @[line]

  while line != "" and line != "\r\n":
    let parts = line.split(":")
    if parts.len != 2:
      success = false
      log lvlError, fmt"[parseResponse] Failed to parse response, no valid header format: '{line}'"
      return newJString(line)

    let name = parts[0]
    if name != "Content-Length" and name != "Content-Type":
      success = false
      log lvlError, fmt"[parseResponse] Failed to parse response, unknown header: '{line}'"
      return newJString(line)

    let value = parts[1]
    headers[name] = value.strip
    line = await client.connection.recvLine
    lines.add line

  if not success or not headers.contains("Content-Length"):
    log(lvlError, "[parseResponse] Failed to parse response:")
    for line in lines:
      log(lvlError, line)
    return newJNull()

  let contentLength = headers["Content-Length"].parseInt
  # let data = await client.socket.recv(contentLength)
  let data = await client.connection.recv(contentLength)
  if logVerbose:
    debug "[recv] ", data[0..min(data.high, 500)]
  return parseJson(data)

proc sendRPC(client: DAPClient, meth: string, command: string, args: Option[JsonNode], id: int)
    {.async.} =

  var request = %*{
    "type": meth,
    "seq": id,
    "command": command,
  }
  if args.getSome(args):
    request["arguments"] = args

  if logVerbose:
    let str = $args
    debugf"[sendRPC] {id} {meth}, {command}: {str[0..min(str.high, 500)]}"

  let data = $request
  let header = createHeader(data.len)
  let msg = header & data

  await client.connection.send(msg)

proc sendRequest(client: DAPClient, command: string, args: Option[JsonNode]): Future[Response[JsonNode]] {.async.} =
  let id = client.nextId
  inc client.nextId
  await client.sendRPC("request", command, args, id)

  let requestFuture = newResolvableFuture[Response[JsonNode]]("DAPCLient.initialize")

  client.activeRequests[id] = (command, requestFuture)
  if not client.requestsPerMethod.contains(command):
    client.requestsPerMethod[command] = @[]
  client.requestsPerMethod[command].add id

  return await requestFuture.future

proc cancelAllOf*(client: DAPClient, command: string) =
  if not client.requestsPerMethod.contains(command):
    return

  var futures: seq[(int, ResolvableFuture[Response[JsonNode]])]
  for id in client.requestsPerMethod[command]:
    let (_, future) = client.activeRequests[id]
    futures.add (id, future)
    client.activeRequests.del id
    client.canceledRequests.incl id

  client.requestsPerMethod[command].setLen 0

  for (id, future) in futures:
    future.complete canceled[JsonNode]()

proc tryGetPortFromLanguagesServer(url: string, port: int, exePath: string, args: seq[string]): Future[Option[tuple[port, processId: int]]] {.async.} =
  debugf"tryGetPortFromLanguagesServer {url}, {port}, {exePath}, {args}"
  try:
    let body = $ %*{
      "path": exePath,
      "args": args,
    }

    let response = await httpPost(fmt"http://{url}:{port}/dap/start", body)
    let json = response.parseJson
    if not json.hasKey("port") or json["port"].kind != JInt:
      return (int, int).none
    if not json.hasKey("processId") or json["processId"].kind != JInt:
      return (int, int).none

    # return (3333, 0).some
    let port = json["port"].num.int
    let processId = json["processId"].num.int
    return (port, processId).some
  except CatchableError:
    log lvlError, &"Failed to connect to languages server {url}:{port}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
    return (int, int).none

when not defined(js):
  proc logProcessDebugOutput(process: AsyncProcess) {.async.} =
    while process.isAlive:
      let line = await process.recvErrorLine
      if logServerDebug:
        log(lvlDebug, fmt"[debug] {line}")

proc launch(client: DAPClient, args: JsonNode) {.async.} =
  log(lvlInfo, &"Launch '{args}'")
  let res = await client.sendRequest("launch", args.some)
  if res.isError:
    log lvlError, &"Failed to launch: {res}"

proc initialize(client: DAPClient) {.async.} =
  log(lvlInfo, "Initialized client")

  let args = some %*{
    "adapterID": "test-adapterID",
    # "pathFormat": "uri",
  }

  let res = await client.sendRequest("initialize", args)
  debugf"initialized: {res}"
  if res.isError:
    client.initializedFuture.complete(false)
    log lvlError, &"Failed to initialized dap client: {res}"
    return

  client.isInitialized = true
  client.initializedFuture.complete(true)

proc connect*(client: DAPClient, serverExecutablePath: string, args: seq[string]) {.async.} =
  client.initializedFuture = newResolvableFuture[bool]("client.initializedFuture")

  when not defined(js):
    log lvlInfo, fmt"Using process '{serverExecutablePath} {args}' as DAP connection"
    let process = startAsyncProcess(serverExecutablePath, args)
    let connection = DAPConnectionAsyncProcess(process: process)
    connection.process.onRestarted = proc(): Future[void] =
      asyncCheck logProcessDebugOutput(process)
      return client.initialize()
    client.connection = connection

  else:
    log lvlError, "DAP connection not implemented for JS"
    return

proc dispatchEvent*(client: DAPClient, event: string, body: JsonNode) =
  let opts = JOptions(allowMissingKeys: true, allowExtraKeys: true)
  case event
  of "initialized": client.onInitialized.invoke
  of "stopped": client.onStopped.invoke body.jsonTo(OnStoppedData, opts)
  of "continued": client.onContinued.invoke body.jsonTo(OnContinuedData, opts)
  of "exited": client.onExited.invoke body.jsonTo(OnExitedData, opts)
  of "terminated": client.onTerminated.invoke body.jsonTo(OnTerminatedData, opts)
  of "thread": client.onThread.invoke body.jsonTo(OnThreadData, opts)
  of "output": client.onOutput.invoke body.jsonTo(OnOutputData, opts)
  of "breakpoint": client.onBreakpoint.invoke body.jsonTo(OnBreakpointData, opts)
  of "module": client.onModule.invoke body.jsonTo(OnModuleData, opts)
  of "loadedSource": client.onLoadedSource.invoke body.jsonTo(OnLoadedSourceData, opts)
  of "process": client.onProcess.invoke body.jsonTo(OnProcessData, opts)
  of "capabilities": client.onCapabilities.invoke body.jsonTo(OnCapabilitiesData, opts)
  of "progressStart": client.onProgressStart.invoke body.jsonTo(OnProgressStartData, opts)
  of "progressUpdate": client.onProgressUpdate.invoke body.jsonTo(OnProgressUpdateData, opts)
  of "progressEnd": client.onProgressEnd.invoke body.jsonTo(OnProgressEndData, opts)
  of "invalidated": client.onInvalidated.invoke body.jsonTo(OnInvalidatedData, opts)
  of "memory": client.onMemory.invoke body.jsonTo(OnMemoryData, opts)
  else:
    log lvlError, &"Unhandled event {event} ({body})"

proc runAsync*(client: DAPClient) {.async.} =
  while client.connection.isNotNil:
    debugf"[run] Waiting for response {(client.activeRequests.len)}"

    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      log(lvlError, fmt"[run] Bad response: {response}")
      continue

    try:
      let meth = response["type"].getStr

      case meth
      of "event":
        let event = response["event"].getStr
        let body = response.fields.getOrDefault("body", newJNull())
        client.dispatchEvent(event, body)

      of "response":
        let id = response["request_seq"].getInt
        debugf"[DAP.run] {response}"
        if client.activeRequests.contains(id):
          debugf"[DAP.run] Complete request {id}"
          let parsedResponse = response.toResponse JsonNode
          let (command, future) = client.activeRequests[id]
          future.complete parsedResponse
          client.activeRequests.del(id)
          let index = client.requestsPerMethod[command].find(id)
          assert index != -1
          client.requestsPerMethod[command].delete index
        elif client.canceledRequests.contains(id):
          # Request was canceled
          debugf"[DAP.run] Received response for canceled request {id}"
          client.canceledRequests.excl id
        else:
          log(lvlError, fmt"[run] error: received response with id {id} but got no active request for that id: {response}")
      else:
        log lvlWarn, &"Unhandled: {response}"

    except:
      log lvlError, &"[run] error: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc run*(client: DAPClient) =
  asyncCheck client.runAsync()

# exposed api

proc lspLogVerbose*(val: bool) {.expose("dap").} =
  debugf"lspLogVerbose {val}"
  logVerbose = val

proc lspToggleLogServerDebug*() {.expose("dap").} =
  logServerDebug = not logServerDebug
  debugf"lspToggleLogServerDebug {logServerDebug}"

proc lspLogServerDebug*(val: bool) {.expose("dap").} =
  debugf"lspLogServerDebug {val}"
  logServerDebug = val

addActiveDispatchTable "dap", genDispatchTable("dap"), global=true

when isMainModule:
  logger.enableConsoleLogger()

  proc test() {.async.} =
    var client = DAPClient()

    when defined(windows):
      await client.connect("D:/llvm/bin/lldb-dap.exe", @[])
    else:
      await client.connect("/bin/lldb-dap-18", @[])

    discard client.onInitialized.subscribe (data: OnInitializedData) => echo &"onInitialized"
    discard client.onStopped.subscribe (data: OnStoppedData) => echo &"onStopped {data}"
    discard client.onContinued.subscribe (data: OnContinuedData) => echo &"onContinued {data}"
    discard client.onExited.subscribe (data: OnExitedData) => echo &"onExited {data}"
    discard client.onTerminated.subscribe (data: OnTerminatedData) => echo &"onTerminated {data}"
    discard client.onThread.subscribe (data: OnThreadData) => echo &"onThread {data}"
    discard client.onOutput.subscribe (data: OnOutputData) => echo &"onOutput {data}"
    discard client.onBreakpoint.subscribe (data: OnBreakpointData) => echo &"onBreakpoint {data}"
    discard client.onModule.subscribe (data: OnModuleData) => echo &"onModule {data}"
    discard client.onLoadedSource.subscribe (data: OnLoadedSourceData) => echo &"onLoadedSource {data}"
    discard client.onProcess.subscribe (data: OnProcessData) => echo &"onProcess {data}"
    discard client.onCapabilities.subscribe (data: OnCapabilitiesData) => echo &"onCapabilities {data}"
    discard client.onProgressStart.subscribe (data: OnProgressStartData) => echo &"onProgressStart {data}"
    discard client.onProgressUpdate.subscribe (data: OnProgressUpdateData) => echo &"onProgressUpdate {data}"
    discard client.onProgressEnd.subscribe (data: OnProgressEndData) => echo &"onProgressEnd {data}"
    discard client.onInvalidated.subscribe (data: OnInvalidatedData) => echo &"onInvalidated {data}"
    discard client.onMemory.subscribe (data: OnMemoryData) => echo &"onMemory {data}"

    client.run()

    if client.waitInitialized.await:
      await client.launch %*{
        "program": "/mnt/c/Absytree/test_dbg",
      }

  waitFor test()

  while true:
    poll(10)
