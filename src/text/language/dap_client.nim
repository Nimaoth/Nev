import std/[json, strutils, strformat, macros, options, tables, sets, hashes, genasts, os]
import misc/[custom_logger, util, event, myjsonutils, custom_async, response, connection, async_process]
import scripting/expose
from std/logging import nil

{.push gcsafe.}
{.push raises: [].}


var file {.threadvar.}: syncio.File
var logFileName {.threadvar.}: string
var fileLogger {.threadvar.}: logging.FileLogger

let mainThreadId = getThreadId()
template isMainThread(): untyped = getThreadId() == mainThreadId

proc logImpl(level: NimNode, args: NimNode, includeCategory: bool): NimNode {.used, gcsafe, raises: [].} =
  var args = args
  if includeCategory:
    args.insert(0, newLit("[" & "dap-client" & "] "))

  return genAst(level, args):
    {.gcsafe.}:
      if file == nil:
        try:
          logFileName = getAppDir() / "logs/dap.log"
          createDir(getAppDir() / "logs")
          file = open(logFileName, fmWrite)
          fileLogger = logging.newFileLogger(file, logging.lvlAll, "", flushThreshold=logging.lvlAll)
        except IOError, OSError:
          discard

      {.push warning[BareExcept]:off.}
      try:
        if fileLogger != nil:
          logging.log(fileLogger, level, args)
        # setLastModificationTime(logFileName, getTime())
      except Exception:
        discard
      {.pop.}

macro log(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
  return logImpl(level, args, true)

macro logNoCategory(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
  return logImpl(level, args, false)

template measureBlock(description: string, body: untyped): untyped {.used.} =
  # todo
  # let timer = startTimer()
  body
  # block:
  #   let descriptionString = description
  #   logging.log(lvlInfo, "[" & "lsp" & "] " & descriptionString & " took " & $timer.elapsed.ms & " ms")

template logScope(level: logging.Level, text: string): untyped {.used.} =
  # todo
  let txt = text
  # logging.log(level, "[" & "lsp" & "] " & txt)
  # inc logger.indentLevel
  # let timer = startTimer()
  # defer:
  #   block:
  #     let elapsedMs = timer.elapsed.ms
  #     let split = elapsedMs.splitDecimal
  #     let elapsedMsInt = split.intpart.int
  #     let elapsedUsInt = (split.floatpart * 1000).int
  #     dec logger.indentLevel
  #     logging.log(level, "[" & "lsp" & "] " & txt & " finished. (" & $elapsedMsInt & " ms " & $elapsedUsInt & " us)")

macro debug(x: varargs[typed, `$`]): untyped {.used.} =
  let level = genAst(): lvlDebug
  let arg = genAst(x):
    x.join ""
  return logImpl(level, nnkArgList.newTree(arg), true)

macro debugf(x: static string): untyped {.used.} =
  let level = genAst(): lvlDebug
  let arg = genAst(str = x):
    fmt str
  return logImpl(level, nnkArgList.newTree(arg), true)

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
  ThreadId* = distinct int
  VariablesReference* = distinct int
  FrameId* = distinct int

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
    id*: ThreadId
    name*: string

  Threads* = object
    threads*: seq[ThreadInfo]

  Source* = object
    name*: Option[string]
    path*: Option[string]
    sourceReference*: Option[int]
    presentationHint*: Option[JsonNode]
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
    id*: FrameId
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

  Scope* = object
    name*: string
    presentationHint*: Option[JsonNode]
    variablesReference*: VariablesReference
    namedVariables*: Option[int]
    indexedVariables*: Option[int]
    expensive*: bool
    source*: Option[Source]
    line*: Option[int]
    column*: Option[int]
    endLine*: Option[int]
    endColumn*: Option[int]

  Scopes* = object
    scopes*: seq[Scope]

  Variable* = object
    name*: string
    value*: string
    `type`*: Option[string]
    presentationHint*: Option[JsonNode]
    evaluateName*: Option[string]
    variablesReference*: VariablesReference
    namedVariables*: Option[int]
    indexedVariables*: Option[int]
    memoryReference*: Option[string]

  Variables* = object
    variables*: seq[Variable]

  OnInitializedData* = void

  OnStoppedData* = object
    reason*: string
    description*: Option[string]
    threadId*: Option[ThreadId]
    preserveFocusHint*: Option[bool]
    text*: Option[string]
    allThreadsStopped*: Option[bool]
    hitBreakpointIds*: seq[int]

  OnContinuedData* = object
    threadId*: ThreadId
    allThreadsContinued*: Option[bool]

  OnExitedData* = object
    exitCode*: int

  OnTerminatedData* = object
    restart*: Option[JsonNode]

  OnThreadData* = object
    reason*: string
    threadId*: ThreadId

  OnOutputData* = object
    category*: Option[string]
    output*: string
    group*: Option[GroupKind]
    variablesReference*: Option[VariablesReference]
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
    threadId*: Option[ThreadId]
    stackFrameId*: Option[int]

  OnMemoryData* = object
    memoryReference*: string
    offset*: int
    count*: int

type
  DAPClient* = ref object
    connection: Connection
    nextId: int = 1
    activeRequests: Table[int, tuple[command: string, future: Future[Response[JsonNode]]]]
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    isInitialized: bool
    initializedFuture: Future[bool]
    initializedEventFuture: Future[void]

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

proc waitInitialized*(client: DAPCLient): Future[bool] = client.initializedFuture
proc waitInitializedEventReceived*(client: DAPCLient): Future[void] = client.initializedEventFuture

proc `==`*(a, b: VariablesReference): bool {.borrow.}
proc hash*(vr: VariablesReference): Hash {.borrow.}
proc `$`*(vr: VariablesReference): string {.borrow.}
proc `%`*(vr: VariablesReference): JsonNode {.borrow.}

proc `==`*(a, b: ThreadId): bool {.borrow.}
proc hash*(vr: ThreadId): Hash {.borrow.}
proc `$`*(vr: ThreadId): string {.borrow.}
proc `%`*(vr: ThreadId): JsonNode {.borrow.}

proc `==`*(a, b: FrameId): bool {.borrow.}
proc hash*(vr: FrameId): Hash {.borrow.}
proc `$`*(vr: FrameId): string {.borrow.}
proc `%`*(vr: FrameId): JsonNode {.borrow.}

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
  try:
    var headers = initTable[string, string]()
    var line = await client.connection.recvLine

    var sleepCounter = 0
    while client.connection.isNotNil and line == "":
      inc sleepCounter
      if sleepCounter > 3:
        await sleepAsync(30.milliseconds)
        sleepCounter = 0
        continue

      line = await client.connection.recvLine

    if client.connection.isNil:
      return newJNull()

    var success = true
    var lines = @[line]

    while line != "" and line != "\r\n":
      if client.connection.isNil:
        return newJNull()

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

    if client.connection.isNil:
      return newJNull()

    if not success or not headers.contains("Content-Length"):
      log(lvlError, "[parseResponse] Failed to parse response:")
      for line in lines:
        log(lvlError, line)
      return newJNull()

    let contentLength = headers["Content-Length"].parseInt
    let data = await client.connection.recv(contentLength)
    if logVerbose:
      debugf"[recv] {data[0..min(data.high, 500)]}"
    return parseJson(data)

  except CatchableError:
    return newJNull()

proc sendRPC(client: DAPClient, meth: string, command: string, args: Option[JsonNode], id: int)
    {.async.} =

  try:
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
  except CatchableError:
    discard

proc sendRequest(client: DAPClient, command: string, args: Option[JsonNode]): Future[Response[JsonNode]] {.async.} =
  let id = client.nextId
  inc client.nextId

  let requestFuture = newFuture[Response[JsonNode]]("DAPCLient.sendRequest")

  client.activeRequests[id] = (command, requestFuture)
  client.requestsPerMethod.mgetOrPut(command, @[]).add id

  asyncSpawn client.sendRPC("request", command, args, id)
  try:
    return await requestFuture
  except CatchableError:
    return errorResponse[JsonNode](0, getCurrentExceptionMsg())

proc cancelAllOf*(client: DAPClient, command: string) =
  client.requestsPerMethod.withValue(command, requests):
    var futures: seq[(int, Future[Response[JsonNode]])]
    for id in requests[]:
      # log lvlError, &"Cancel request {command}:{id}"
      let (_, future) = client.activeRequests[id]
      futures.add (id, future)
      client.activeRequests.del id
      client.canceledRequests.incl id

    requests[].setLen 0

    for (id, future) in futures:
      future.complete canceled[JsonNode]()

proc logProcessDebugOutput*(process: AsyncProcess) {.async.} =
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

  try:
    var args = newJObject()
    args["source"] = source.toJson
    args["breakpoints"] = breakpoints.toJson

    var lines = newSeqOfCap[int](breakpoints.len)
    for b in breakpoints:
      lines.add b.line
    args["lines"] = lines.toJson

    let res = await client.sendRequest("setBreakpoints", args.some)
    if res.isError:
      log lvlError, &"Failed to set breakpoints: {res}"
      return

  except:
    discard

  # debugf"{res.result.pretty}"

proc configurationDone*(client: DAPClient) {.async.} =
  log lvlInfo, &"configurationDone"
  let res = await client.sendRequest("configurationDone", JsonNode.none)
  if res.isError:
    log lvlError, &"Failed to finish configuration: {res}"
    return

proc continueExecution*(client: DAPClient, threadId: ThreadId, singleThreaded = bool.none) {.async.} =
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

proc next*(client: DAPClient, threadId: ThreadId, singleThreaded = bool.none,
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

proc stepIn*(client: DAPClient, threadId: ThreadId, singleThreaded = bool.none, targetId = int.none,
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

proc stepOut*(client: DAPClient, threadId: ThreadId, singleThreaded = bool.none,
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

proc stackTrace*(client: DAPClient, threadId: ThreadId, startFrame = int.none, levels = int.none,
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

proc scopes*(client: DAPClient, frameId: FrameId): Future[Response[Scopes]] {.async.} =
  log lvlInfo, &"scopes"
  var args = %*{
    "frameId": frameId,
  }
  let res = await client.sendRequest("scopes", args.some)
  if res.isError:
    log lvlError, &"Failed get scopes: {res}"
    return res.to(Scopes)
  return res.to(Scopes)

proc variables*(client: DAPClient, variablesReference: VariablesReference): Future[Response[Variables]] {.async.} =
  log lvlInfo, &"variables"
  var args = %*{
    "variablesReference": variablesReference,
  }
  let res = await client.sendRequest("variables", args.some)
  if res.isError:
    log lvlError, &"Failed get variables: {res}"
    return res.to(Variables)
  return res.to(Variables)

proc initialize*(client: DAPClient) {.async.} =
  log lvlInfo, "Initialize client"
  client.run()

  let args = some %*{
    "adapterID": "test-adapterID",
    "pathFormat": "path", # todo (uri)
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
    initializedFuture: newFuture[bool]("client.initializedFuture"),
    initializedEventFuture: newFuture[void]("client.initializedEventFuture"),
  )

  client.connection = connection
  client

proc dispatchEvent(client: DAPClient, event: string, body: JsonNode) =
  try:
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
  except ValueError as e:
    log lvlError, &"Failed to dispatch dap event '{event}': {e.msg}\n{body}"

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

    let response = try:
      await client.parseResponse()
    except:
      log lvlError, &"Failed to parse response: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      continue

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
  asyncSpawn client.runAsync()

proc dapLogVerbose*(val: bool) {.expose("dap").} =
  debugf"dapLogVerbose {val}"
  logVerbose = val

proc dapToggleLogServerDebug*() {.expose("dap").} =
  logServerDebug = not logServerDebug
  debugf"dapToggleLogServerDebug {logServerDebug}"

proc dapLogServerDebug*(val: bool) {.expose("dap").} =
  debugf"dapLogServerDebug {val}"
  logServerDebug = val

# addActiveDispatchTable "dap", genDispatchTable("dap"), global=true
