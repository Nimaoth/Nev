import std/[json, strutils, strformat, macros, options, tables, sets, uri, sequtils, sugar, os, parseopt]
import misc/[custom_logger, util, event, myjsonutils, custom_async, response, connection]
import platform/filesystem
import scripting/expose
import dispatch_tables

when not defined(js):
  import misc/[async_process]

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
    a = Response[JsonNode](
      id: b["request_seq"].getInt,
      kind: ResponseKind.Success, result: b.getOrDefault("body")
    ).to T

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

  SteppingGranularity* = enum
    Statement = "statement"
    Line = "line"
    Instruction = "instruction"

  PresentationHint* = enum
    Normal = "normal"
    Label = "label"
    Subtle = "subtle"

  Checksum* = object
    algorithm*: ChecksumAlgorithm
    checksum*: string

  ThreadInfo* = object
    id*: int
    name*: string

  Threads* = object
    threads*: seq[ThreadInfo]

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

  ValueFormat* {.inheritable.} = object
    hex*: Option[bool]

  StackFrameFormat* = object of ValueFormat
    parameters*: Option[bool]
    parameterTypes*: Option[bool]
    parameterNames*: Option[bool]
    parameterValues*: Option[bool]
    line*: Option[bool]
    module*: Option[bool]
    includeAll*: Option[bool]

  StackFrame* = object
    id*: int
    name*: string
    source*: Option[Source]
    line*: int
    column*: int
    endLine*: Option[int]
    endColumn*: Option[int]
    canRestart*: Option[bool]
    instructionPointerReference*: Option[string]
    moduleId*: Option[JsonNode]
    presentationHint*: PresentationHint

  StackTraceResponse* = object
    stackFrames*: seq[StackFrame]
    totalFrames*: Option[int]

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
  DAPClient* = ref object
    connection: Connection
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

  let requestFuture = newResolvableFuture[Response[JsonNode]]("DAPCLient.sendRequest " & command)

  client.activeRequests[id] = (command, requestFuture)
  if not client.requestsPerMethod.contains(command):
    client.requestsPerMethod[command] = @[]
  client.requestsPerMethod[command].add id

  asyncCheck client.sendRPC("request", command, args, id)
  return await requestFuture.future

proc cancelAllOf*(client: DAPClient, command: string) =
  if not client.requestsPerMethod.contains(command):
    return

  var futures: seq[(int, ResolvableFuture[Response[JsonNode]])]
  for id in client.requestsPerMethod[command]:
    # log lvlError, &"Cancel request {command}:{id}"
    let (_, future) = client.activeRequests[id]
    futures.add (id, future)
    client.activeRequests.del id
    client.canceledRequests.incl id

  client.requestsPerMethod[command].setLen 0

  for (id, future) in futures:
    future.complete canceled[JsonNode]()

when not defined(js):
  proc logProcessDebugOutput(process: AsyncProcess) {.async.} =
    while process.isAlive:
      let line = await process.recvErrorLine
      if logServerDebug:
        log(lvlDebug, fmt"[debug] {line}")

proc launch*(client: DAPClient, args: JsonNode) {.async.} =
  log lvlInfo, &"Launch '{args}'"
  let res = await client.sendRequest("launch", args.some)
  if res.isError:
    log lvlError, &"Failed to launch: {res}"

proc attach*(client: DAPClient, args: JsonNode) {.async.} =
  log lvlInfo, &"Attach '{args}'"
  let res = await client.sendRequest("attach", args.some)
  if res.isError:
    log lvlError, &"Failed to attach: {res}"

proc disconnect*(client: DAPClient, restart: bool,
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

proc setBreakpoints*(client: DAPClient, source: Source, breakpoints: seq[SourceBreakpoint], sourceModified = bool.none) {.async.} =
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

proc configurationDone*(client: DAPClient) {.async.} =
  log lvlInfo, &"configurationDone"
  let res = await client.sendRequest("configurationDone", JsonNode.none)
  if res.isError:
    log lvlError, &"Failed to finish configuration: {res}"
    return

proc continueExecution*(client: DAPClient, threadId: int, singleThreaded = bool.none) {.async.} =
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

proc next*(client: DAPClient, threadId: int, singleThreaded = bool.none,
    granularity = SteppingGranularity.none) {.async.} =

  log lvlInfo, &"next (threadId={threadId}, singleThreaded={singleThreaded}, granularity={granularity})"

  var args = %*{
    "threadId": threadId,
  }
  if singleThreaded.getSome(singleThreaded):
    args["singleThreaded"] = singleThreaded.toJson
  if granularity.getSome(granularity):
    args["granularity"] = granularity.toJson

  let res = await client.sendRequest("next", args.some)
  if res.isError:
    log lvlError, &"'next' failed: {res}"
    return

proc stepIn*(client: DAPClient, threadId: int, singleThreaded = bool.none, targetId = int.none,
    granularity = SteppingGranularity.none) {.async.} =

  log lvlInfo, &"stepIn (threadId={threadId}, singleThreaded={singleThreaded}, targetId={targetId}, granularity={granularity})"

  var args = %*{
    "threadId": threadId,
  }
  if singleThreaded.getSome(singleThreaded):
    args["singleThreaded"] = singleThreaded.toJson
  if targetId.getSome(targetId):
    args["targetId"] = targetId.toJson
  if granularity.getSome(granularity):
    args["granularity"] = granularity.toJson

  let res = await client.sendRequest("stepIn", args.some)
  if res.isError:
    log lvlError, &"'stepIn' failed: {res}"
    return

proc stepOut*(client: DAPClient, threadId: int, singleThreaded = bool.none,
    granularity = SteppingGranularity.none) {.async.} =

  log lvlInfo, &"stepOut (threadId={threadId}, singleThreaded={singleThreaded}, granularity={granularity})"

  var args = %*{
    "threadId": threadId,
  }
  if singleThreaded.getSome(singleThreaded):
    args["singleThreaded"] = singleThreaded.toJson
  if granularity.getSome(granularity):
    args["granularity"] = granularity.toJson

  let res = await client.sendRequest("stepOut", args.some)
  if res.isError:
    log lvlError, &"'stepOut' failed: {res}"
    return

proc stackTrace*(client: DAPClient, threadId: int, startFrame = int.none, levels = int.none,
    format = StackFrameFormat.none): Future[Response[StackTraceResponse]] {.async.} =

  log lvlInfo, &"stackTrace (threadId={threadId}, startFrame={startFrame}, levels={levels}, format={format})"

  var args = %*{
    "threadId": threadId,
  }
  if startFrame.getSome(startFrame):
    args["startFrame"] = startFrame.toJson
  if levels.getSome(levels):
    args["levels"] = levels.toJson
  if format.getSome(format):
    args["format"] = format.toJson

  let res = await client.sendRequest("stackTrace", args.some)
  if res.isError:
    log lvlError, &"'stackTrace' failed: {res}"
    return res.to(StackTraceResponse)

  return res.to(StackTraceResponse)

proc getThreads*(client: DAPClient): Future[Response[Threads]] {.async.} =
  log lvlInfo, &"getThreads"
  let res = await client.sendRequest("threads", JsonNode.none)
  if res.isError:
    log lvlError, &"Failed get threads: {res}"
    return res.to(Threads)
  return res.to(Threads)

proc initialize*(client: DAPClient) {.async.} =
  log lvlInfo, "Initialize client"
  client.run()

  let args = some %*{
    "adapterID": "test-adapterID",
    # "pathFormat": "uri", # todo
  }

  let res = await client.sendRequest("initialize", args)
  if res.isError:
    client.initializedFuture.complete(false)
    log lvlError, &"Failed to initialized dap client: {res}"
    return

  log lvlInfo, &"[initialize]: Server capabilities: {res.result.pretty}"
  client.isInitialized = true
  client.initializedFuture.complete(true)

proc newDAPClient*(connection: Connection): DAPCLient =
  var client = DAPCLient(
    initializedFuture: newResolvableFuture[bool]("client.initializedFuture"),
    initializedEventFuture: newResolvableFuture[void]("client.initializedEventFuture"),
  )

  client.connection = connection
  client

proc dispatchEvent(client: DAPClient, event: string, body: JsonNode) =
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

proc handleResponse(client: DAPClient, response: JsonNode) =
  if logVerbose:
    debugf"[handleResponse] {response}"

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
      debugf"[handleResponse] Received response for canceled request {id}"
    client.canceledRequests.excl id

  else:
    log lvlError, &"[handleResponse] error: received response ({id}) without active request: {response}"

proc runAsync*(client: DAPClient) {.async.} =
  while client.connection.isNotNil:
    if logVerbose:
      debugf"[run] Waiting for response {(client.activeRequests.len)}"

    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      log lvlError, fmt"[run] Bad response: {response}"
      continue

    if logVerbose:
      debugf"[run] Response: {response.pretty}"

    try:
      case response["type"].getStr
      of "event":
        let event = response["event"].getStr
        let body = response.fields.getOrDefault("body", newJNull())
        client.dispatchEvent(event, body)

      of "response":
        client.handleResponse(response)

      else:
        log lvlWarn, &"Invalid DAP message, expected 'event' or 'response': {response}"

    except:
      log lvlError, &"[run] error: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc run*(client: DAPClient) =
  asyncCheck client.runAsync()

# proc dapLogVerbose*(val: bool) {.expose("dap").} =
#   debugf"dapLogVerbose {val}"
#   logVerbose = val

# proc dapToggleLogServerDebug*() {.expose("dap").} =
#   logServerDebug = not logServerDebug
#   debugf"dapToggleLogServerDebug {logServerDebug}"

# proc dapLogServerDebug*(val: bool) {.expose("dap").} =
#   debugf"dapLogServerDebug {val}"
#   logServerDebug = val

# addActiveDispatchTable "dap", genDispatchTable("dap"), global=true

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

    var connection: Connection
    if port >= 0:
      connection = await newAsyncSocketConnection("127.0.0.1", port.Port)
    else:
      connection = await newAsyncProcessConnection(lldpDapPath, @[])

    var client = newDAPClient(connection)

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

      await sleepAsync(2000)

      let stackTrace = await client.stackTrace(threads.result.threads[0].id)
      debugf"stacktrace: {stackTrace}"

      await client.continueExecution(threads.result.threads[0].id)
      await sleepAsync(1000)
      await client.next(threads.result.threads[0].id)

      await sleepAsync(2000)
      await client.disconnect(restart=false)

  try:
    waitFor test()
  except ValueError:
    discard
