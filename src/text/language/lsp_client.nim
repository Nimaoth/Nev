import std/[json, strutils, strformat, macros, options, tables, sets, uri, sequtils, sugar, os, genasts]
import misc/[custom_logger, websocket, util, myjsonutils, custom_async, response]
import scripting/expose
import platform/filesystem
from workspaces/workspace as ws import nil
import lsp_types, dispatch_tables
from std/logging import nil

import misc/async_process

export lsp_types

var file {.threadvar.}: syncio.File
var logFileName {.threadvar.}: string
var fileLogger {.threadvar.}: logging.FileLogger

let mainThreadId = getThreadId()
template isMainThread(): untyped = getThreadId() == mainThreadId

proc logImpl(level: NimNode, args: NimNode, includeCategory: bool): NimNode {.used, gcsafe, raises: [].} =
  var args = args
  if includeCategory:
    args.insert(0, newLit("[" & "lsp-client" & "] "))

  return genAst(level, args):
    {.gcsafe.}:
      if file == nil:
        try:
          logFileName = getAppDir() / & "lsp.log"
          file = open(logFileName, fmWrite)
          fileLogger = logging.newFileLogger(file, logging.lvlAll, "", flushThreshold=logging.lvlAll)
        except IOError:
          discard

      try:
        if fileLogger != nil:
          logging.log(fileLogger, level, args)
        # setLastModificationTime(logFileName, getTime())
      except:
        discard

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
var logServerDebug = false

type
  LSPConnection = ref object of RootObj

  LSPClientResponseKind* = enum
    GetDefinition
    GetDeclaration
    GetTypeDefinition
    GetImplementation
    GetReferences
    GetSwitchSourceHeader
    GetHover
    GetInlayHint
    GetDocumentSymbol
    GetSymbol
    GetDiagnostic
    GetCompletion

  LSPClientResponse* = object
    id*: int
    case kind*: LSPClientResponseKind
    of GetDefinition: getDefinition*: Response[DefinitionResponse]
    of GetDeclaration: getDeclaration*: Response[DeclarationResponse]
    of GetTypeDefinition: getTypeDefinition*: Response[TypeDefinitionResponse]
    of GetImplementation: getImplementation*: Response[ImplementationResponse]
    of GetReferences: getReferences*: Response[ReferenceResponse]
    of GetSwitchSourceHeader: getSwitchSourceHeader*: Response[string]
    of GetHover: getHover*: Response[DocumentHoverResponse]
    of GetInlayHint: getInlayHint*: Response[InlayHintResponse]
    of GetDocumentSymbol: getDocumentSymbol*: Response[DocumentSymbolResponse]
    of GetSymbol: getSymbol*: Response[WorkspaceSymbolResponse]
    of GetDiagnostic: getDiagnostic*: Response[DocumentDiagnosticResponse]
    of GetCompletion: getCompletion*: Response[CompletionResponse]

  LSPClientRequest = object
    id: int
    meth: string
    body: JsonNode

  LSPClientObject* = object
    languageId*: string
    connection: LSPConnection
    nextId: int
    activeRequests: Table[int, tuple[meth: string, future: Future[Response[JsonNode]]]] # Worker Thread
    activeDefinitionRequests: Table[int, tuple[meth: string, future: Future[Response[DefinitionResponse]]]] # Main thread
    activeDeclarationRequests: Table[int, tuple[meth: string, future: Future[Response[DeclarationResponse]]]] # Main thread
    activeTypeDefinitionRequests: Table[int, tuple[meth: string, future: Future[Response[TypeDefinitionResponse]]]] # Main thread
    activeImplementationRequests: Table[int, tuple[meth: string, future: Future[Response[ImplementationResponse]]]] # Main thread
    activeReferencesRequests: Table[int, tuple[meth: string, future: Future[Response[ReferenceResponse]]]] # Main thread
    activeSwitchSourceHeaderRequests: Table[int, tuple[meth: string, future: Future[Response[string]]]] # Main thread
    activeHoverRequests: Table[int, tuple[meth: string, future: Future[Response[DocumentHoverResponse]]]] # Main thread
    activeInlayHintsRequests: Table[int, tuple[meth: string, future: Future[Response[InlayHintResponse]]]] # Main thread
    activeSymbolsRequests: Table[int, tuple[meth: string, future: Future[Response[DocumentSymbolResponse]]]] # Main thread
    activeWorkspaceSymbolsRequests: Table[int, tuple[meth: string, future: Future[Response[WorkspaceSymbolResponse]]]] # Main thread
    activeDiagnosticsRequests: Table[int, tuple[meth: string, future: Future[Response[DocumentDiagnosticResponse]]]] # Main thread
    activeCompletionsRequests: Table[int, tuple[meth: string, future: Future[Response[CompletionResponse]]]] # Main thread
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    idToMethod: Table[int, string]
    isInitialized: bool
    pendingRequests: seq[string]
    workspaceFolders: seq[string]
    workspaceInfo*: Option[ws.WorkspaceInfo]
    serverCapabilities: ServerCapabilities
    fullDocumentSync*: bool = false

    # initializedFuture: Future[bool]
    onWorkspaceConfiguration*: proc(params: ConfigurationParams): Future[seq[JsonNode]] {.gcsafe.}

    userInitializationOptions*: JsonNode
    serverExecutablePath: string
    args: seq[string]
    languagesServer: Option[(string, int)] = (string, int).none

    initializedChannel*: AsyncChannel[Option[ServerCapabilities]]
    workspaceConfigurationRequestChannel*: AsyncChannel[ConfigurationParams]
    workspaceConfigurationResponseChannel*: AsyncChannel[seq[JsonNode]]
    getCompletionsChannel*: AsyncChannel[string]
    messageChannel*: AsyncChannel[(MessageType, string)]
    diagnosticChannel*: AsyncChannel[PublicDiagnosticsParams]
    symbolsRequestChannel*: AsyncChannel[string]
    symbolsResponseChannel*: AsyncChannel[Response[DocumentSymbolResponse]]
    requestChannel*: AsyncChannel[LSPClientRequest]
    responseChannel*: AsyncChannel[LSPClientResponse]
    notifyTextDocumentOpenedChannel*: AsyncChannel[tuple[languageId: string, path: string, content: string]]
    notifyTextDocumentClosedChannel*: AsyncChannel[string]
    notifyConfigurationChangedChannel*: AsyncChannel[JsonNode]
    notifyTextDocumentChangedChannel*: AsyncChannel[tuple[path: string, version: int, changes: seq[TextDocumentContentChangeEvent], content: string]]

  LSPClient* = ptr LSPClientObject

proc newLSPClient*(info: Option[ws.WorkspaceInfo], userOptions: JsonNode, serverExecutablePath: string, workspaces: seq[string], args: seq[string], languagesServer: Option[(string, int)] = (string, int).none): LSPClient =
  var client = cast[LSPClient](allocShared0(sizeof(LSPClientObject)))
  client[] = LSPClientObject(
    workspaceInfo: info,
    userInitializationOptions: userOptions,
    serverExecutablePath: serverExecutablePath,
    workspaceFolders: workspaces,
    args: args,
    languagesServer: languagesServer,
    initializedChannel: newAsyncChannel[Option[ServerCapabilities]](),
    workspaceConfigurationRequestChannel: newAsyncChannel[ConfigurationParams](),
    workspaceConfigurationResponseChannel: newAsyncChannel[seq[JsonNode]](),
    getCompletionsChannel: newAsyncChannel[string](),
    messageChannel: newAsyncChannel[(MessageType, string)](),
    diagnosticChannel: newAsyncChannel[PublicDiagnosticsParams](),
    symbolsRequestChannel: newAsyncChannel[string](),
    symbolsResponseChannel: newAsyncChannel[Response[DocumentSymbolResponse]](),
    requestChannel: newAsyncChannel[LSPClientRequest](),
    responseChannel: newAsyncChannel[LSPClientResponse](),
    notifyTextDocumentOpenedChannel: newAsyncChannel[tuple[languageId: string, path: string, content: string]](),
    notifyTextDocumentClosedChannel: newAsyncChannel[string](),
    notifyConfigurationChangedChannel: newAsyncChannel[JsonNode](),
    notifyTextDocumentChangedChannel: newAsyncChannel[tuple[path: string, version: int, changes: seq[TextDocumentContentChangeEvent], content: string]](),
  )

  return client

# proc waitInitialized*(client: LSPCLient): Future[bool] = client.initializedFuture.future

method close(connection: LSPConnection) {.base, gcsafe.} = discard
method recvLine(connection: LSPConnection): Future[string] {.base, gcsafe.} = discard
method recv(connection: LSPConnection, length: int): Future[string] {.base, gcsafe.} = discard
method send(connection: LSPConnection, data: string): Future[void] {.base, gcsafe.} = discard

when not defined(js):
  type LSPConnectionAsyncProcess = ref object of LSPConnection
    process: AsyncProcess

  method close(connection: LSPConnectionAsyncProcess) = connection.process.destroy
  method recvLine(connection: LSPConnectionAsyncProcess): Future[string] = connection.process.recvLine
  method recv(connection: LSPConnectionAsyncProcess, length: int): Future[string] = connection.process.recv(length)
  method send(connection: LSPConnectionAsyncProcess, data: string): Future[void] = connection.process.send(data)

proc encodePathUri(path: string): string = path.normalizePathUnix.split("/").mapIt(it.encodeUrl(false)).join("/")

when defined(js):
  # todo
  proc absolutePath(path: string): string = path

proc toUri*(path: string): Uri =
  when defined(linux):
    return parseUri("file://" & path.absolutePath.encodePathUri)
  else:
    return parseUri("file:///" & path.absolutePath.encodePathUri)

proc createHeader*(contentLength: int): string =
  let header = fmt"Content-Length: {contentLength}" & "\r\n\r\n"
  return header

proc deinit*(client: LSPClient) =
  assert client.connection.isNotNil, "LSP Client process should not be nil"

  log lvlInfo, "Deinitializing LSP client"
  client.connection.close()
  client.connection = nil
  client.nextId = 0
  client.activeRequests.clear()
  client.activeDefinitionRequests.clear()
  client.activeDeclarationRequests.clear()
  client.activeTypeDefinitionRequests.clear()
  client.activeImplementationRequests.clear()
  client.activeReferencesRequests.clear()
  client.activeSwitchSourceHeaderRequests.clear()
  client.activeHoverRequests.clear()
  client.activeInlayHintsRequests.clear()
  client.activeSymbolsRequests.clear()
  client.activeWorkspaceSymbolsRequests.clear()
  client.activeDiagnosticsRequests.clear()
  client.activeCompletionsRequests.clear()
  client.requestsPerMethod.clear()
  client.canceledRequests.clear()
  client.isInitialized = false
  client.pendingRequests.setLen 0

proc parseResponse(client: LSPClient): Future[JsonNode] {.async.} =
  try:
    # debugf"[parseResponse]"
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

  except:
    return newJNull()

proc sendRPC(client: LSPClient, meth: string, params: JsonNode, id: Option[int]) {.gcsafe, async.} =
  var request = %*{
    "jsonrpc": "2.0",
    "method": meth,
    "params": params,
  }
  if id.getSome(id):
    request["id"] = newJInt(id)

  if logVerbose:
    let str = $params
    debug "[sendRPC] ", meth, ": ", str[0..min(str.high, 500)]

  if not client.isInitialized and meth != "initialize":
    log(lvlInfo, fmt"[sendRPC] client not initialized, add to pending ({meth})")
    client.pendingRequests.add $request
    return

  let data = $request
  let header = createHeader(data.len)
  let msg = header & data

  if logVerbose:
    debugf"[send] {msg[0..min(msg.high, 500)]}"

  try:
    await client.connection.send(msg)
  except:
    discard

proc sendNotification(client: LSPClient, meth: string, params: JsonNode) {.gcsafe, async.} =
  # debugf"sendNotification {meth}, {params}"
  await client.sendRPC(meth, params, int.none)

proc sendResult(client: LSPClient, id: int, res: JsonNode) {.async, gcsafe.} =
  var request = %*{
    "jsonrpc": "2.0",
    "id": id,
    "result": res,
  }

  let data = $request

  if logVerbose:
    debug "[sendResult] ", data[0..min(data.high, 500)]

  let header = createHeader(data.len)
  let msg = header & data

  try:
    await client.connection.send(msg)
  except:
    discard


proc sendRequestInternal(client: LSPClient, meth: string, params: JsonNode): Future[Response[JsonNode]] {.async.} =
  assert not isMainThread()

  let id = client.nextId
  inc client.nextId
  await client.sendRPC(meth, params, id.some)

  let requestFuture = newFuture[Response[JsonNode]]("LSPCLient.initialize")

  client.activeRequests[id] = (meth, requestFuture)
  if not client.requestsPerMethod.contains(meth):
    client.requestsPerMethod[meth] = @[]
  client.requestsPerMethod[meth].add id

  return await requestFuture

proc handleRequests(client: LSPClient) {.async, gcsafe.} =
  assert not isMainThread()

  while client != nil:
    let request = client.requestChannel.recv().await.getOr:
      log lvlInfo, &"handleRequests: channel closed"
      return

    debugf"handleRequest: {request}"

    client.idToMethod[request.id] = request.meth
    await client.sendRPC(request.meth, request.body, request.id.some)

  log lvlInfo, &"handleRequests: client gone"

proc handleResponses*(client: LSPClient) {.async, gcsafe.} =
  assert isMainThread()

  while client != nil:
    let response = client.responseChannel.recv().await.getOr:
      log lvlInfo, &"handleResponses: channel closed"
      return

    debugf"handleResponse: {response.id}"
    let id = response.id

    template dispatch(requests: untyped, parsedResponse: untyped): untyped =
      try:
        if requests.contains(id):
          # debugf"[LSP.run] Complete request {id}"
          let (meth, future) = requests[id]
          defer: requests.del(id)
          future.complete parsedResponse
          let index = client.requestsPerMethod[meth].find(id)
          if index != -1:
            client.requestsPerMethod[meth].delete index
          else:
            let temp {.inject.} = meth
            log lvlError, &"Request not found: {id}, {temp}, {client.requestsPerMethod[temp]}"
        elif client.canceledRequests.contains(id):
          # Request was canceled
          # debugf"[LSP.run] Received response for canceled request {id}"
          client.canceledRequests.excl id
        else:
          log lvlError, &"[handleResponses] received response with id {id} but got no active request for that id: {response}"
      except:
        log lvlError, &"[handleResponses] Failed to dispatch response: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

    case response.kind
    of GetDefinition: dispatch(client.activeDefinitionRequests, response.getDefinition)
    of GetDeclaration: dispatch(client.activeDeclarationRequests, response.getDeclaration)
    of GetTypeDefinition: dispatch(client.activeTypeDefinitionRequests, response.getTypeDefinition)
    of GetImplementation: dispatch(client.activeImplementationRequests, response.getImplementation)
    of GetReferences: dispatch(client.activeReferencesRequests, response.getReferences)
    of GetSwitchSourceHeader: dispatch(client.activeSwitchSourceHeaderRequests, response.getSwitchSourceHeader)
    of GetHover: dispatch(client.activeHoverRequests, response.getHover)
    of GetInlayHint: dispatch(client.activeInlayHintsRequests, response.getInlayHint)
    of GetDocumentSymbol: dispatch(client.activeSymbolsRequests, response.getDocumentSymbol)
    of GetSymbol: dispatch(client.activeWorkspaceSymbolsRequests, response.getSymbol)
    of GetDiagnostic: dispatch(client.activeDiagnosticsRequests, response.getDiagnostic)
    of GetCompletion: dispatch(client.activeCompletionsRequests, response.getCompletion)

  log lvlInfo, &"handleResponses: client gone"

proc sendRequest[T](client: LSPClient, requests: ptr Table[int, tuple[meth: string, future: Future[T]]], meth: string, params: JsonNode): Future[T] {.async.} =
  assert isMainThread()

  let id = client.nextId
  inc client.nextId

  let requestFuture = newFuture[T]("LSPCLient.sendRequest")

  requests[][id] = (meth, requestFuture)

  if not client.requestsPerMethod.contains(meth):
    client.requestsPerMethod[meth] = @[]
  client.requestsPerMethod[meth].add id

  await client.requestChannel.send(LSPClientRequest(id: id, meth: meth, body: params))
  return await requestFuture

proc cancelAllOf*(client: LSPClient, meth: string) =
  assert isMainThread()

  if not client.requestsPerMethod.contains(meth):
    return

  var futures: seq[(int, Future[Response[JsonNode]])]
  for id in client.requestsPerMethod[meth]:
    template cancel(requests, typ: untyped): untyped =
      defer: requests.del(id)
      try:
        requests[id].future.complete(canceled[typ]())
      except:
        log lvlError, &"[cancelAllOf] Failed to cancel '{meth}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

    case meth
    of "textDocument/definition": cancel(client.activeDefinitionRequests, DefinitionResponse)
    of "textDocument/declaration": cancel(client.activeDeclarationRequests, DeclarationResponse)
    of "textDocument/typeDefinition": cancel(client.activeTypeDefinitionRequests, TypeDefinitionResponse)
    of "textDocument/implementation": cancel(client.activeImplementationRequests, ImplementationResponse)
    of "textDocument/references": cancel(client.activeReferencesRequests, ReferenceResponse)
    of "textDocument/switchSourceHeader": cancel(client.activeSwitchSourceHeaderRequests, string)
    of "textDocument/hover": cancel(client.activeHoverRequests, DocumentHoverResponse)
    of "textDocument/inlayHint": cancel(client.activeInlayHintsRequests, InlayHintResponse)
    of "textDocument/documentSymbol": cancel(client.activeSymbolsRequests, DocumentSymbolResponse)
    of "workspace/symbol": cancel(client.activeWorkspaceSymbolsRequests, WorkspaceSymbolResponse)
    of "textDocument/diagnostic": cancel(client.activeDiagnosticsRequests, DocumentDiagnosticResponse)
    of "textDocument/completion": cancel(client.activeCompletionsRequests, CompletionResponse)
    else: continue

    client.activeRequests.del id
    client.canceledRequests.incl id

  client.requestsPerMethod[meth].setLen 0

  for (id, future) in futures:
    future.complete canceled[JsonNode]()

proc initialize(client: LSPClient): Future[Response[JsonNode]] {.async, gcsafe.} =
  var workspacePath = if client.workspaceFolders.len > 0:
    client.workspaceFolders[0].normalizePathUnix.some
  else:
    string.none

  var workspaces = client.workspaceFolders.mapIt(WorkspaceFolder(uri: $it.toUri, name: it.splitFile.name))

  if client.workspaceInfo.getSome workspaceInfo:
    if workspaceInfo.folders.len > 0:
      log lvlInfo, &"Using workspace info ({workspaceInfo}) as lsp workspace"
      workspacePath = workspaceInfo.folders[0].path.some
      workspaces = workspaceInfo.folders.mapIt(WorkspaceFolder(uri: $it.path.toUri, name: it.name.get("???")))

  let processId = os.getCurrentProcessId()

  let params = %*{
    "processId": processId,
    "rootPath": workspacePath.map((p) => p.toJson).get(newJNull()),
    "rootUri": workspacePath.map((p) => p.toUri.toJson).get(newJNull()),
    "workspaceFolders": workspaces,
    "trace": "verbose",
    "initializationOptions": client.userInitializationOptions,
    "capabilities": %*{
      "workspace": %*{
        "workspaceFolders": true,
        "fileOperations": %*{
          "didOpen": true,
          "didClose": true,
          "didChange": true,
        },
        "configuration": true,
        "didChangeConfiguration": %*{},
        "symbol": %*{
          # "symbolKind": %*{}
        },
      },
      "general": %*{
        "positionEncodings": %*["utf-8"],
      },
      "textDocument": %*{
        "completion": %*{
          "completionItem": %*{
            "snippetSupport": true,
          },
          "completionProvider": true,
        },
        "definition": %*{
          "linkSupport": true,
        },
        "declaration": %*{
          "linkSupport": true,
        },
        "typeDefinition": %*{
          "linkSupport": true,
        },
        "implementation": %*{
          "linkSupport": true,
        },
        "references": %*{},
        "codeAction": %*{
          "linkSupport": true,
        },
        "rename": %*{
          "linkSupport": true,
        },
        "documentSymbol": %*{},
        "inlayHint": %*{},
        "hover": %*{},
        "publishDiagnostics": %*{
          "relatedInformation": true,
          "versionSupport": false,
          "tagSupport": %*{
              "valueSet": %*[1, 2]
          },
          "codeDescriptionSupport": true,
          "dataSupport": true
        },
        # "diagnostic": %*{},
      },
      "window": %*{
        "showDocument": %*{
          "support": true,
        },
      },
    },
  }

  log(lvlInfo, fmt"[initialize] {params.pretty}")

  let res = await client.sendRequestInternal("initialize", params)
  if res.isError:
    log lvlError, &"Failed to initialize lsp: {res.error}"
    # client.initializedFuture.complete(false)
    await client.initializedChannel.send(ServerCapabilities.none)
    return res

  assert not res.isCanceled

  try:
    client.serverCapabilities = res.result["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
  except:
    await client.initializedChannel.send(ServerCapabilities.none)
    return errorResponse[JsonNode](0, &"Failed to parse server capabilities: {getCurrentExceptionMsg()}\n{res.result.pretty}")

  client.isInitialized = true
  log lvlInfo, "Server capabilities: ", client.serverCapabilities

  await client.sendNotification("initialized", newJObject())
  await client.initializedChannel.send(client.serverCapabilities.some)

  for req in client.pendingRequests:
    if logVerbose:
      debug "[initialize] sending pending request", req[0..min(req.high, 500)]
    let header = createHeader(req.len)
    try:
      await client.connection.send(header & req)
    except:
      log lvlError, &"Failed to send pending request"

  return res

proc tryGetPortFromLanguagesServer(url: string, port: int, exePath: string, args: seq[string]): Future[Option[tuple[port, processId: int]]] {.async.} =
  debugf"tryGetPortFromLanguagesServer {url}, {port}, {exePath}, {args}"
  discard
  return
  # try:
  #   let body = $ %*{
  #     "path": exePath,
  #     "args": args,
  #   }

  #   let response = await httpPost(fmt"http://{url}:{port}/lsp/start", body)
  #   let json = response.parseJson
  #   if not json.hasKey("port") or json["port"].kind != JInt:
  #     return (int, int).none
  #   if not json.hasKey("processId") or json["processId"].kind != JInt:
  #     return (int, int).none

  #   # return (3333, 0).some
  #   let port = json["port"].num.int
  #   let processId = json["processId"].num.int
  #   return (port, processId).some
  # except CatchableError:
  #   # log lvlError, &"Failed to connect to languages server {url}:{port}: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
  #   return (int, int).none

when not defined(js):
  proc logProcessDebugOutput(process: AsyncProcess) {.async.} =
    while process.isAlive:
      let line = await process.recvErrorLine
      if logServerDebug:
        log(lvlDebug, fmt"[server] {line}")

proc sendInitializationRequest(client: LSPClient) {.async, gcsafe.} =
  log(lvlInfo, "Initializing client...")
  let response = await client.initialize()
  if response.isError:
    log(lvlError, fmt"[sendInitializationRequest] Got error response: {response}")
    return

  assert not response.isCanceled

proc connect*(client: LSPClient) {.async, gcsafe.} =
  # client.initializedFuture = newFuture[bool]("client.initializedFuture")

  if client.languagesServer.getSome(lsConfig):
    log lvlInfo, fmt"Using languages server at '{lsConfig[0]}:{lsConfig[1]}' to find LSP connection"
    let serverConfig = await tryGetPortFromLanguagesServer(lsConfig[0], lsConfig[1], client.serverExecutablePath, client.args)
    if serverConfig.isNone:
      log(lvlError, "Failed to connect to languages server: no port found")
      await client.initializedChannel.send(ServerCapabilities.none)
      return

  #   # log lvlInfo, fmt"Using websocket connection on port {serverConfig.get.port} as LSP connection"
  #   var socket = await newWebSocket(fmt"ws://localhost:{serverConfig.get.port}")
  #   let connection = LSPConnectionWebsocket(websocket: socket, processId: serverConfig.get.processId)
  #   client.connection = connection
  #   asyncSpawn client.sendInitializationRequest()

  else:
    when not defined(js):
      log lvlInfo, fmt"Using process '{client.serverExecutablePath} {client.args}' as LSP connection"
      let process = startAsyncProcess(client.serverExecutablePath, client.args)
      let connection = LSPConnectionAsyncProcess(process: process)

      connection.process.onRestarted = proc(): Future[void] {.gcsafe.} =
        asyncSpawn logProcessDebugOutput(process)
        return client.sendInitializationRequest()

      connection.process.onRestartFailed = proc(): Future[void] {.gcsafe.} =
        return client.initializedChannel.send(ServerCapabilities.none)

      client.connection = connection

    else:
      log lvlError, "LSP connection not implemented for JS"
      return

proc translatePath(client: LSPClient, path: string): string =
  if path.startsWith("@") and client.workspaceInfo.getSome info:
    try:
      let endOffset = path.find("/")
      let index = path[1..<endOffset].parseInt
      if index < info.folders.len:
        return info.folders[index].path / path[endOffset + 1..^1]
    except:
      log lvlError, &"Failed to translate path '{path}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      discard

  return path

proc notifyOpenedTextDocument(client: LSPClient, languageId: string, path: string, content: string) {.async.} =
  let path = client.translatePath(path)
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "languageId": languageId,
      "version": 0,
      "text": content,
    },
  }

  debugf"notifyOpenedTextDocument {languageId}, {path}"
  await client.sendNotification("textDocument/didOpen", params)

proc notifyClosedTextDocument(client: LSPClient, path: string) {.async.} =
  let path = client.translatePath(path)
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
    },
  }

  debugf"notifyClosedTextDocument {path}"
  await client.sendNotification("textDocument/didClose", params)

proc notifyTextDocumentChanged(client: LSPClient, path: string, version: int,
    changes: seq[TextDocumentContentChangeEvent]) {.async.} =
  let path = client.translatePath(path)
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "version": version,
    },
    "contentChanges": changes.toJson
  }

  debugf"notifyTextDocumentChangedPartial {path}, {version}"
  await client.sendNotification("textDocument/didChange", params)

proc notifyConfigurationChanged(client: LSPClient, settings: JsonNode) {.gcsafe, async.} =
  await client.sendNotification("workspace/didChangeConfiguration", %{"settings": settings})

proc notifyTextDocumentChanged(client: LSPClient, path: string, version: int, content: string) {.async.} =
  let path = client.translatePath(path)
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "version": version,
    },
    "contentChanges": %*[
      %*{
        "range": %Range(),
        "text": content,
      },
    ],
  }

  debugf"notifyTextDocumentChangedFull {path}, {version}"
  await client.sendNotification("textDocument/didChange", params)

proc getDefinition*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DefinitionResponse]] {.async.} =
  debugf"[getDefinition] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/definition")

  let params = DefinitionParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return await client.sendRequest(client.activeDefinitionRequests.addr, "textDocument/definition", params)

proc getDeclaration*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DeclarationResponse]] {.async.} =
  debugf"[getDeclaration] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/declaration")

  let params = DeclarationParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return await client.sendRequest(client.activeDeclarationRequests.addr, "textDocument/declaration", params)

proc getTypeDefinitions*(client: LSPClient, filename: string, line: int, column: int): Future[Response[TypeDefinitionResponse]] {.async.} =
  debugf"[getDeclaration] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/typeDefinition")

  let params = TypeDefinitionParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return await client.sendRequest(client.activeTypeDefinitionRequests.addr, "textDocument/typeDefinition", params)

proc getImplementation*(client: LSPClient, filename: string, line: int, column: int): Future[Response[ImplementationResponse]] {.async.} =
  debugf"[getDeclaration] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/implementation")

  let params = ImplementationParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return await client.sendRequest(client.activeImplementationRequests.addr, "textDocument/implementation", params)

proc getReferences*(client: LSPClient, filename: string, line: int, column: int): Future[Response[ReferenceResponse]] {.async.} =
  debugf"[getDeclaration] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/references")

  let params = ReferenceParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    ),
    context: ReferenceContext(includeDeclaration: true)
  ).toJson

  return await client.sendRequest(client.activeReferencesRequests.addr, "textDocument/references", params)

proc switchSourceHeader*(client: LSPClient, filename: string): Future[Response[string]] {.async.} =
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/switchSourceHeader")

  let params = TextDocumentIdentifier(uri: $path.toUri).toJson

  return await client.sendRequest(client.activeSwitchSourceHeaderRequests.addr, "textDocument/switchSourceHeader", params)

proc getHover*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DocumentHoverResponse]] {.async.} =
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/hover")

  let params = DocumentHoverParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return await client.sendRequest(client.activeHoverRequests.addr, "textDocument/hover", params)

proc getInlayHints*(client: LSPClient, filename: string, selection: ((int, int), (int, int))): Future[Response[InlayHintResponse]] {.async.} =
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/inlayHint")

  let params = InlayHintParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    `range`: Range(
      start: Position(
        line: selection[0][0],
        character: selection[0][1],
      ),
      `end`: Position(
        line: selection[1][0],
        character: selection[1][1],
      ),
    )
  ).toJson

  return await client.sendRequest(client.activeInlayHintsRequests.addr, "textDocument/inlayHint", params)

proc getSymbols*(client: LSPClient, filename: string): Future[Response[DocumentSymbolResponse]] {.async.} =
  assert isMainThread()

  debugf"[getSymbols] {filename.absolutePath}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/documentSymbol")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
  ).toJson

  return await client.sendRequest(client.activeSymbolsRequests.addr, "textDocument/documentSymbol", params)

proc getWorkspaceSymbols*(client: LSPClient, query: string): Future[Response[WorkspaceSymbolResponse]] {.async.} =
  debugf"[getWorkspaceSymbols]"
  client.cancelAllOf("workspace/symbol")

  let params = WorkspaceSymbolParams(
    query: query
  ).toJson

  return await client.sendRequest(client.activeWorkspaceSymbolsRequests.addr, "workspace/symbol", params)

proc getDiagnostics*(client: LSPClient, filename: string): Future[Response[DocumentDiagnosticResponse]] {.async.} =
  # debugf"[getDiagnostics] {filename.absolutePath}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/diagnostic")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
  ).toJson

  return await client.sendRequest(client.activeDiagnosticsRequests.addr, "textDocument/diagnostic", params)

proc getCompletions*(client: LSPClient, filename: string, line: int, column: int): Future[Response[CompletionList]] {.async.} =
  debugf"[getCompletions] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/completion")

  # todo
  let params = %*{
    "textDocument": TextDocumentIdentifier(uri: $path.toUri),
    "position": Position(
      line: line,
      character: column
    ),
    "context": %*{
      "triggerKind": CompletionTriggerKind.Invoked.int
    },
  }

  let response = await client.sendRequest(client.activeCompletionsRequests.addr, "textDocument/completion", params)

  if response.isError or response.isCanceled:
    return response.to CompletionList

  let parsedResponse = response.result
  if parsedResponse.asCompletionItemSeq().getSome(items):
    return CompletionList(isIncomplete: false, items: items).success
  if parsedResponse.asCompletionList().getSome(list):
    return list.success

  debugf"[getCompletions] {filename}:{line}:{column}: no completions found"
  return errorResponse[CompletionList](-1, fmt"[getCompletions] {filename}:{line}:{column}: no completions found")

proc handleWorkspaceConfigurationRequest(client: LSPClient, id: int, params: ConfigurationParams) {.async, gcsafe.} =
  debugf"handleWorkspaceConfigurationRequest {id}, {params}"
  await client.workspaceConfigurationRequestChannel.send(params)
  let res = await client.workspaceConfigurationResponseChannel.recv()

  await client.sendResult(id, %res)

proc runAsync*(client: LSPClient) {.async, gcsafe.} =
  while client.connection.isNotNil:
    # debugf"[run] Waiting for response {(client.activeRequests.len)}"

    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      log(lvlError, fmt"[run] Bad response: {response}")
      continue

    if logVerbose:
      debugf"[run] Got response: {response}"

    try:
      if not response.hasKey("id"):
        # Response has no id, it's a notification
        let meth = response["method"].getStr
        case meth
        of "window/logMessage", "window/showMessage":
          let messageType =  response["params"]["type"].jsonTo MessageType
          let message = response["params"]["message"].jsonTo string
          asyncSpawn client.messageChannel.send (messageType, message)

        of "textDocument/publishDiagnostics":
          let params = response["params"].jsonTo(PublicDiagnosticsParams, JOptions(allowMissingKeys: true, allowExtraKeys: true))
          asyncSpawn client.diagnosticChannel.send params

        else:
          log(lvlInfo, fmt"[run] {response}")
          discard

      elif response.hasKey("method"):
        # Not a response, but a server request
        let id = response["id"].getInt

        let meth = response["method"].getStr
        case meth
        of "workspace/configuration":
          let params = response["params"].jsonTo(ConfigurationParams, JOptions(allowMissingKeys: true, allowExtraKeys: true))
          asyncSpawn client.handleWorkspaceConfigurationRequest(id, params)
        else:
          log lvlWarn, fmt"[run] Received request with id {id} and method {meth} but don't know how to handle it"
          discard

      else:
        # debugf"[LSP.run] {response}"
        let id = response["id"].getInt

        if client.activeRequests.contains(id):
          # debugf"[LSP.run] Complete request {id}"
          let parsedResponse = response.toResponse JsonNode
          let (meth, future) = client.activeRequests[id]
          future.complete parsedResponse
          client.activeRequests.del(id)
          let index = client.requestsPerMethod[meth].find(id)
          assert index != -1
          client.requestsPerMethod[meth].delete index
        elif client.canceledRequests.contains(id):
          # Request was canceled
          # debugf"[LSP.run] Received response for canceled request {id}"
          client.canceledRequests.excl id
        elif client.idToMethod.contains(id):
          let meth = client.idToMethod[id]
          client.idToMethod.del(id)
          debugf"[run] received response with id {id} and method {meth}"
          let parsedResponse = response.toResponse JsonNode
          case meth

          of "textDocument/definition": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetDefinition, getDefinition: parsedResponse.to(DefinitionResponse)))
          of "textDocument/declaration": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetDeclaration, getDeclaration: parsedResponse.to(DeclarationResponse)))
          of "textDocument/typeDefinition": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetTypeDefinition, getTypeDefinition: parsedResponse.to(TypeDefinitionResponse)))
          of "textDocument/implementation": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetImplementation, getImplementation: parsedResponse.to(ImplementationResponse)))
          of "textDocument/references": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetReferences, getReferences: parsedResponse.to(ReferenceResponse)))
          of "textDocument/switchSourceHeader": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetSwitchSourceHeader, getSwitchSourceHeader: parsedResponse.to(string)))
          of "textDocument/hover": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetHover, getHover: parsedResponse.to(DocumentHoverResponse)))
          of "textDocument/inlayHint": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetInlayHint, getInlayHint: parsedResponse.to(InlayHintResponse)))
          of "textDocument/documentSymbol": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetDocumentSymbol, getDocumentSymbol: parsedResponse.to(DocumentSymbolResponse)))
          of "workspace/symbol": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetSymbol, getSymbol: parsedResponse.to(WorkspaceSymbolResponse)))
          of "textDocument/diagnostic": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetDiagnostic, getDiagnostic: parsedResponse.to(DocumentDiagnosticResponse)))
          of "textDocument/completion": await client.responseChannel.send(LSPClientResponse(
              id: id, kind: GetCompletion, getCompletion: parsedResponse.to(CompletionResponse)))

        else:
          log(lvlError, fmt"[run] error: received response with id {id} but got no active request for that id: {response}")

    except:
      log lvlError, &"[run] error: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      discard

proc run*(client: LSPClient) =
  asyncSpawn client.runAsync()

# exposed api

proc lspLogVerbose*(val: bool) {.expose("lsp").} =
  debugf"lspLogVerbose {val}"
  logVerbose = val

proc lspToggleLogServerDebug*() {.expose("lsp").} =
  logServerDebug = not logServerDebug
  debugf"lspToggleLogServerDebug {logServerDebug}"

proc lspLogServerDebug*(val: bool) {.expose("lsp").} =
  debugf"lspLogServerDebug {val}"
  logServerDebug = val

genDispatcher("lsp")
addActiveDispatchTable "lsp", genDispatchTable("lsp"), global=true

proc dispatchEvent*(action: string, args: JsonNode): Option[JsonNode] =
  dispatch(action, args)

proc handleNotifiesOpened(client: LSPClient) {.async, gcsafe.} =
  while client != nil:
    let (languageId, path, content) = client.notifyTextDocumentOpenedChannel.recv().await.getOr:
      log lvlInfo, &"handleNotifiesOpened: channel closed"
      return

    await client.notifyOpenedTextDocument(languageId, path, content)

  log lvlInfo, &"handleNotifiesOpened: client gone"

proc handleNotifiesClosed(client: LSPClient) {.async, gcsafe.} =
  while client != nil:
    let path = client.notifyTextDocumentClosedChannel.recv().await.getOr:
      log lvlInfo, &"handleNotifiesClosed: channel closed"
      return

    await client.notifyClosedTextDocument(path)

  log lvlInfo, &"handleNotifiesClosed: client gone"

proc handleNotifiesChanged(client: LSPClient) {.async, gcsafe.} =
  while client != nil:
    let (path, version, changes, content) = client.notifyTextDocumentChangedChannel.recv().await.getOr:
      log lvlInfo, &"handleNotifiesChanged: channel closed"
      return

    if changes.len > 0:
      await client.notifyTextDocumentChanged(path, version, changes)
    else:
      await client.notifyTextDocumentChanged(path, version, content)

  log lvlInfo, &"handleNotifiesChanged: client gone"

proc handleNotifiesConfigurationChanged(client: LSPClient) {.async, gcsafe.} =
  while client != nil:
    let value = client.notifyConfigurationChangedChannel.recv().await.getOr:
      log lvlInfo, &"handleNotifiesConfigurationChanged: channel closed"
      return

    await client.notifyConfigurationChanged(value)

  log lvlInfo, &"handleNotifiesConfigurationChanged: client gone"

proc lspClientRunner*(client: LSPClient) {.thread, nimcall.} =
  logFileName = getAppDir() / &"lsp.{client.languageId}.log"
  file = open(logFileName, fmWrite)
  fileLogger = logging.newFileLogger(file, logging.lvlAll, "", flushThreshold=logging.lvlAll)
  defer:
    file.close()

  asyncSpawn client.connect()
  asyncSpawn client.runAsync()
  asyncSpawn client.handleNotifiesOpened()
  asyncSpawn client.handleNotifiesClosed()
  asyncSpawn client.handleNotifiesChanged()
  asyncSpawn client.handleNotifiesConfigurationChanged()
  asyncSpawn client.handleRequests()

  # todo: cleanup
  while true:
    poll(10)
