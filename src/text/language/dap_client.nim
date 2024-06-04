import std/[json, strutils, strformat, macros, options, tables, sets, uri, sequtils, sugar, os, parseopt]
import misc/[custom_logger, async_http_client, websocket, util, event, myjsonutils, custom_async, response]
import platform/filesystem
import scripting/expose
import dispatch_tables

import misc/custom_asyncnet

logCategory "dap"

var logVerbose = false
var logServerDebug = true

proc fromJsonHook*[T](a: var Response[T], b: JsonNode, opt = Joptions()) =
  if not b["success"].getBool:
    a = Response[T](
      id: b["request_seq"].getInt,
      kind: ResponseKind.Error,
      error: ResponseError(
        message:  b.fields.getOrDefault("message", newJString("")).getStr,
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

  Thread* = object
    id*: int
    name*: string

  Threads* = object
    threads*: seq[Thread]

  Source* = object
    name*: Option[string]
    path*: Option[string]
    sourceReference*: Option[int]
    presentationHint*: Option[string]
    origin*: Option[string]
    sources*: seq[Source]
    adapterData*: Option[JsonNode]
    checksums*: seq[Checksum]

  SourceBreakpoint* = object
    line*: int
    column*: Option[int]
    condition*: Option[string]
    hitCondition*: Option[string]
    logMessage*: Option[string]
    mode*: Option[string]

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

  ExceptionBreakpointsFilter* = object
    filter*: string
    label*: string
    description*: Option[string]
    default*: Option[bool]
    supportsCondition*: Option[bool]
    conditionDescription*: Option[string]

  ColumnDescriptor* = object
    attributeName*: string
    label*: string
    format*: Option[string]
    `type`*: Option[string]
    width*: Option[int]

  BreakpointMode* = object
    mode*: string
    label*: string
    description*: Option[string]
    appliesTo*: seq[string]

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
    areas*: seq[string]
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
    initializedEventFuture: ResolvableFuture[void]

    onInitialized*: Event[OnInitializedData]
    onStopped*: Event[OnStoppedData]
    onContinued*: Event[OnContinuedData]
    onExited*: Event[OnExitedData]
    onTerminated*: Event[Option[OnTerminatedData]]
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

proc run*(client: DAPClient)

proc waitInitialized*(client: DAPCLient): Future[bool] = client.initializedFuture.future
proc waitInitializedEventReceived*(client: DAPCLient): Future[void] = client.initializedEventFuture.future

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

type DAPConnectionAsyncSocket = ref object of DAPConnection
  socket: AsyncSocket

method close(connection: DAPConnectionAsyncSocket) =
  connection.socket.close()
method recvLine(connection: DAPConnectionAsyncSocket): Future[string] =
  connection.socket.recvLine()
method recv(connection: DAPConnectionAsyncSocket, length: int): Future[string] =
  connection.socket.recv(length)
method send(connection: DAPConnectionAsyncSocket, data: string): Future[void] =
  connection.socket.send(data)

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
  log lvlInfo, &"Launch '{args}'"
  let res = await client.sendRequest("launch", args.some)
  if res.isError:
    log lvlError, &"Failed to launch: {res}"

proc attach(client: DAPClient, args: JsonNode) {.async.} =
  log lvlInfo, &"Attach '{args}'"
  let res = await client.sendRequest("attach", args.some)
  if res.isError:
    log lvlError, &"Failed to attach: {res}"

proc disconnect(client: DAPClient, restart: bool,
    terminateDebuggee = bool.none, suspendDebuggee = bool.none) {.async.} =

  log lvlInfo, &"disconnect (restart={restart}, terminateDebuggee={terminateDebuggee}, suspendDebuggee={suspendDebuggee})"

  var args = %*{
    "restart": restart,
  }
  if terminateDebuggee.getSome(terminateDebuggee):
    args["terminateDebuggee"] = terminateDebuggee.toJson
  if suspendDebuggee.getSome(suspendDebuggee):
    args["suspendDebuggee"] = suspendDebuggee.toJson

  let res = await client.sendRequest("disconnect", args.some)
  if res.isError:
    log lvlError, &"Failed to disconnect: {res}"

proc setBreakpoints(client: DAPClient, source: Source, breakpoints: seq[SourceBreakpoint], sourceModified = bool.none) {.async.} =
  log lvlInfo, &"setBreakpoints"

  var args = %*{
    "source": source,
    "breakpoints": breakpoints,
  }

  let res = await client.sendRequest("setBreakpoints", args.some)
  if res.isError:
    log lvlError, &"Failed to set breakpoints: {res}"
    return

  # debugf"{res.result.pretty}"

proc configurationDone(client: DAPClient) {.async.} =
  log lvlInfo, &"configurationDone"
  let res = await client.sendRequest("configurationDone", JsonNode.none)
  if res.isError:
    log lvlError, &"Failed to finish configuration: {res}"
    return

proc continueExecution(client: DAPClient, threadId: int, singleThreaded = bool.none) {.async.} =
  log lvlInfo, &"continueExecution (threadId={threadId}, singleThreaded={singleThreaded})"

  var args = %*{
    "threadId": threadId,
  }
  if singleThreaded.getSome(singleThreaded):
    args["singleThreaded"] = singleThreaded.toJson

  let res = await client.sendRequest("continue", args.some)
  if res.isError:
    log lvlError, &"Failed to continue execution: {res}"
    return

  # debugf"{res.result.pretty}"

proc getThreads(client: DAPClient): Future[Response[Threads]] {.async.} =
  log lvlInfo, &"getThreads"
  let res = await client.sendRequest("threads", JsonNode.none)
  if res.isError:
    log lvlError, &"Failed get threads: {res}"
    return res.to(Threads)
  return res.to(Threads)

proc initialize(client: DAPClient) {.async.} =
  log(lvlInfo, "Initialize client")
  client.run()

  let args = some %*{
    "adapterID": "test-adapterID",
    # "pathFormat": "uri",
  }

  let res = await client.sendRequest("initialize", args)
  if res.isError:
    client.initializedFuture.complete(false)
    log lvlError, &"Failed to initialized dap client: {res}"
    return

  debugf"initialize: Finished {res.result.pretty}"
  client.isInitialized = true
  client.initializedFuture.complete(true)

proc newAsyncSocketConnection*(host: string, port: Port): Future[DAPConnectionAsyncSocket] {.async.} =
  log lvlInfo, fmt"Creating async socket connection at {host}:{port.int}"
  let socket = newAsyncSocket()
  await socket.connect(host, port)
  return DAPConnectionAsyncSocket(socket: socket)

proc asyncVoid() {.async.} =
  discard

proc newAsyncProcessConnection*(path: string, args: seq[string]):
    Future[DAPConnectionAsyncProcess] {.async.} =

  log lvlInfo, fmt"Creating async process connection at {path} {args}"

  let process = startAsyncProcess(path, args, autoRestart=false)

  var fut = newResolvableFuture[void]("newAsyncProcessConnection")
  process.onRestarted = proc(): Future[void] =
    asyncCheck logProcessDebugOutput(process)
    fut.complete()
    return asyncVoid()

  await fut.future
  return DAPConnectionAsyncProcess(process: process)

proc newDAPClient*(connection: DAPConnection): DAPCLient =
  var client = DAPCLient(
    initializedFuture: newResolvableFuture[bool]("client.initializedFuture"),
    initializedEventFuture: newResolvableFuture[void]("client.initializedEventFuture"),
  )

  client.connection = connection
  client

proc dispatchEvent*(client: DAPClient, event: string, body: JsonNode) =
  let opts = JOptions(allowMissingKeys: true, allowExtraKeys: true)
  case event
  of "initialized":
    client.initializedEventFuture.complete()
    client.onInitialized.invoke
  of "stopped": client.onStopped.invoke body.jsonTo(OnStoppedData, opts)
  of "continued": client.onContinued.invoke body.jsonTo(OnContinuedData, opts)
  of "exited": client.onExited.invoke body.jsonTo(OnExitedData, opts)
  of "terminated": client.onTerminated.invoke if body.kind == JObject:
      body.jsonTo(OnTerminatedData, opts).some
    else:
      OnTerminatedData.none
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
    if logVerbose:
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
        if logVerbose:
          debugf"[DAP.run] {response}"

        let id = response["request_seq"].getInt
        if client.activeRequests.contains(id):
          # debugf"[DAP.run] Complete request {id}"
          let parsedResponse = response.toResponse JsonNode
          let (command, future) = client.activeRequests[id]
          future.complete parsedResponse
          client.activeRequests.del(id)
          let index = client.requestsPerMethod[command].find(id)
          assert index != -1
          client.requestsPerMethod[command].delete index
        elif client.canceledRequests.contains(id):
          # Request was canceled
          if logVerbose:
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

proc dapLogVerbose*(val: bool) {.expose("dap").} =
  debugf"dapLogVerbose {val}"
  logVerbose = val

proc dapToggleLogServerDebug*() {.expose("dap").} =
  logServerDebug = not logServerDebug
  debugf"dapToggleLogServerDebug {logServerDebug}"

proc dapLogServerDebug*(val: bool) {.expose("dap").} =
  debugf"dapLogServerDebug {val}"
  logServerDebug = val

addActiveDispatchTable "dap", genDispatchTable("dap"), global=true

when isMainModule:
  logger.enableConsoleLogger()

  var port = -1

  var optParser = initOptParser("")
  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      discard

    of cmdLongOption, cmdShortOption:
      case key
      of "port", "p":
        port = val.parseInt

    else:
      discard

  proc test() {.async.} =

    when defined(windows):
      const lldpDapPath = "D:/llvm/bin/lldb-dap.exe"
      # const lldpDapPath = "lldb-dap.exe"
    else:
      const lldpDapPath = "/bin/lldb-dap-18"
      # const lldpDapPath = "/home/nimaoth/dev/llvm-project/build_lldb/bin/lldb-dap"

    var connection: DAPConnection
    if port >= 0:
      connection = await newAsyncSocketConnection("127.0.0.1", port.Port)
    else:
      connection = await newAsyncProcessConnection(lldpDapPath, @[])

    var client = newDAPClient(connection)

    discard client.onInitialized.subscribe (data: OnInitializedData) => debugf"onInitialized"
    discard client.onStopped.subscribe (data: OnStoppedData) => debugf"onStopped {data}"
    discard client.onContinued.subscribe (data: OnContinuedData) => debugf"onContinued {data}"
    discard client.onExited.subscribe (data: OnExitedData) => debugf"onExited {data}"
    discard client.onTerminated.subscribe (data: Option[OnTerminatedData]) => debugf"onTerminated {data}"
    discard client.onThread.subscribe (data: OnThreadData) => debugf"onThread {data}"
    discard client.onOutput.subscribe (data: OnOutputData) => debugf"[dap-{data.category}] {data.output}"
    discard client.onBreakpoint.subscribe (data: OnBreakpointData) => debugf"onBreakpoint {data}"
    discard client.onModule.subscribe (data: OnModuleData) => debugf"onModule {data}"
    discard client.onLoadedSource.subscribe (data: OnLoadedSourceData) => debugf"onLoadedSource {data}"
    discard client.onProcess.subscribe (data: OnProcessData) => debugf"onProcess {data}"
    discard client.onCapabilities.subscribe (data: OnCapabilitiesData) => debugf"onCapabilities {data}"
    discard client.onProgressStart.subscribe (data: OnProgressStartData) => debugf"onProgressStart {data}"
    discard client.onProgressUpdate.subscribe (data: OnProgressUpdateData) => debugf"onProgressUpdate {data}"
    discard client.onProgressEnd.subscribe (data: OnProgressEndData) => debugf"onProgressEnd {data}"
    discard client.onInvalidated.subscribe (data: OnInvalidatedData) => debugf"onInvalidated {data}"
    discard client.onMemory.subscribe (data: OnMemoryData) => debugf"onMemory {data}"

    await client.initialize()

    when defined(linux):
      let sourcePath = "/mnt/c/Absytree/temp/test.cpp"
      let exePath = "/mnt/c/Absytree/temp/test_dbg"
      # let sourcePath = "/mnt/c/Absytree/temp/test.py"
      # let exePath = "/mnt/c/Absytree/temp/test.py"
    else:
      let sourcePath = "C:\\Absytree\\temp\\test.cpp"
      let exePath = "C:\\Absytree\\temp\\test_dbg.exe"

    if client.waitInitialized.await:
      # await client.attach %*{
      #   "program": exePath,
      # }

      await client.launch %*{
        "program": exePath,
      }

      let threads = await client.getThreads
      if threads.isError:
        log lvlError, &"Failed to get threads: {threads}"
        return

      debugf"waiting for initialized event"
      await client.waitInitializedEventReceived

      await client.setBreakpoints(
        Source(path: sourcePath.some),
        @[
          SourceBreakpoint(line: 42),
          SourceBreakpoint(line: 52),
        ]
      )

      await client.configurationDone()

      await sleepAsync(5000)
      await client.continueExecution(threads.result.threads[0].id)

      await sleepAsync(5000)
      await client.disconnect(restart=false)

  try:
    waitFor test()
  except ValueError:
    discard
