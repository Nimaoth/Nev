import std/[json, strutils, strformat, macros, options]
import misc/[custom_logger, async_http_client, websocket, util, event]
import scripting/expose
from workspaces/workspace as ws import nil

logCategory "lsp"

var logVerbose = false
var logServerDebug = false

import std/[tables, sets, options, uri, sequtils, sugar, os]
import misc/[myjsonutils, util, custom_async]
import lsp_types

export lsp_types

type
  LSPConnection = ref object of RootObj

  ResolvableFuture[T] = object
    future: Future[T]
    when defined(js):
      resolve: proc(result: T)

  LSPClient* = ref object
    connection: LSPConnection
    nextId: int
    activeRequests: Table[int, tuple[meth: string, future: ResolvableFuture[Response[JsonNode]]]]
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    isInitialized: bool
    pendingRequests: seq[string]
    workspaceFolders: seq[string]
    workspace*: Option[ws.WorkspaceFolder]
    serverCapabilities: ServerCapabilities
    fullDocumentSync*: bool = false
    onMessage*: Event[tuple[verbosity: MessageType, message: string]]
    onDiagnostics*: Event[PublicDiagnosticsParams]

    onWorkspaceConfiguration*: proc(params: ConfigurationParams): Future[seq[JsonNode]]

proc complete[T](future: ResolvableFuture[T], result: T) =
  when defined(js):
    future.resolve(result)
  else:
    future.future.complete(result)

method close(connection: LSPConnection) {.base.} = discard
method recvLine(connection: LSPConnection): Future[string] {.base.} = discard
method recv(connection: LSPConnection, length: int): Future[string] {.base.} = discard
method send(connection: LSPConnection, data: string): Future[void] {.base.} = discard

when not defined(js):
  import misc/[async_process]
  type LSPConnectionAsyncProcess = ref object of LSPConnection
    process: AsyncProcess

  method close(connection: LSPConnectionAsyncProcess) = connection.process.destroy
  method recvLine(connection: LSPConnectionAsyncProcess): Future[string] = connection.process.recvLine
  method recv(connection: LSPConnectionAsyncProcess, length: int): Future[string] = connection.process.recv(length)
  method send(connection: LSPConnectionAsyncProcess, data: string): Future[void] = connection.process.send(data)

type LSPConnectionWebsocket = ref object of LSPConnection
  websocket: WebSocket
  buffer: string
  processId: int

method close(connection: LSPConnectionWebsocket) = connection.websocket.close()
method recvLine(connection: LSPConnectionWebsocket): Future[string] {.async.} =
  var newLineIndex = connection.buffer.find("\r\n")
  while newLineIndex == -1:
    let next = connection.websocket.receiveStrPacket().await
    connection.buffer.append next
    newLineIndex = connection.buffer.find("\r\n")

  let line = connection.buffer[0..<newLineIndex]
  connection.buffer = connection.buffer[newLineIndex + 2..^1]
  return line

method recv(connection: LSPConnectionWebsocket, length: int): Future[string] {.async.} =
  while connection.buffer.len < length:
    connection.buffer.add connection.websocket.receiveStrPacket().await

  let res = connection.buffer[0..<length]
  connection.buffer = connection.buffer[length..^1]
  return res

method send(connection: LSPConnectionWebsocket, data: string): Future[void] = connection.websocket.send(data)

proc encodePathUri(path: string): string = path.myNormalizedPath.split("/").mapIt(it.encodeUrl(false)).join("/")

when defined(js):
  # todo
  proc absolutePath(path: string): string = path

proc toUri*(path: string): Uri =
  return parseUri("file:///" & path.absolutePath.encodePathUri) # todo: use file://{} for linux

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
  client.requestsPerMethod.clear()
  client.canceledRequests.clear()
  client.isInitialized = false
  client.pendingRequests.setLen 0

proc parseResponse(client: LSPClient): Future[JsonNode] {.async.} =
  # debugf"[parseResponse]"
  var headers = initTable[string, string]()
  var line = await client.connection.recvLine
  while client.connection.isNotNil and line == "":
    line = await client.connection.recvLine

  if client.connection.isNil:
    log(lvlError, "[parseResponse] Connection is nil")
    return JsonNode(nil)

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

proc sendRPC(client: LSPClient, meth: string, params: JsonNode, id: Option[int]) {.async.} =
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

  await client.connection.send(msg)

proc sendNotification(client: LSPClient, meth: string, params: JsonNode) {.async.} =
  await client.sendRPC(meth, params, int.none)

proc sendResult(client: LSPClient, meth: string, id: int, res: JsonNode) {.async.} =
  var request = %*{
    "jsonrpc": "2.0",
    "id": id,
    "method": meth,
    "result": res,
  }

  if logVerbose:
    let str = $res
    debug "[sendResult] ", meth, ": ", str[0..min(str.high, 500)]

  if not client.isInitialized and meth != "initialize":
    log(lvlInfo, fmt"[sendResult] client not initialized, add to pending ({meth})")
    client.pendingRequests.add $request
    return

  let data = $request
  let header = createHeader(data.len)
  let msg = header & data

  await client.connection.send(msg)

proc sendRequest(client: LSPClient, meth: string, params: JsonNode): Future[Response[JsonNode]] {.async.} =
  let id = client.nextId
  inc client.nextId
  await client.sendRPC(meth, params, id.some)

  when defined(js):
    var resolveFunc: proc(response: Response[JsonNode]) = nil
    var requestFuture = newPromise[Response[JsonNode]](proc(resolve: proc(response: Response[JsonNode])) =
      resolveFunc = resolve
    )
    let resolvableFuture = ResolvableFuture[Response[JsonNode]](future: requestFuture, resolve: resolveFunc)

  else:
    var requestFuture = newFuture[Response[JsonNode]]("LSPCLient.initialize")
    let resolvableFuture = ResolvableFuture[Response[JsonNode]](future: requestFuture)

  client.activeRequests[id] = (meth, resolvableFuture)
  if not client.requestsPerMethod.contains(meth):
    client.requestsPerMethod[meth] = @[]
  client.requestsPerMethod[meth].add id

  return await requestFuture

proc cancelAllOf*(client: LSPClient, meth: string) =
  if not client.requestsPerMethod.contains(meth):
    return

  var futures: seq[(int, ResolvableFuture[Response[JsonNode]])]
  for id in client.requestsPerMethod[meth]:
    let (_, future) = client.activeRequests[id]
    futures.add (id, future)
    client.activeRequests.del id
    client.canceledRequests.incl id

  client.requestsPerMethod[meth].setLen 0

  for (id, future) in futures:
    future.complete error[JsonNode](-1, fmt"{meth}:{id} canceled")

proc initialize(client: LSPClient): Future[Response[JsonNode]] {.async.} =
  var workspacePath = if client.workspaceFolders.len > 0:
    client.workspaceFolders[0].myNormalizedPath.some
  else:
    string.none

  var workspaces = client.workspaceFolders.mapIt(WorkspaceFolder(uri: $it.toUri, name: it.splitFile.name))

  if client.workspace.getSome workspace:
    while workspace.info.isNil:
      debugf"workspace await info is nil"
      await sleepAsync(100)

    let info = workspace.info.await

    if info.folders.len > 0:
      log lvlInfo, "Using workspace info ({info}) as lsp workspace"
      workspacePath = info.folders[0].path.some
      workspaces = info.folders.mapIt(WorkspaceFolder(uri: $it.path.toUri, name: it.name.get("???")))

  let processId = when defined(js):
    if client.connection of LSPConnectionWebsocket:
      client.connection.LSPConnectionWebsocket.processId
    else:
      0
  else:
    os.getCurrentProcessId()

  let params = %*{
    "processId": processId,
    "rootPath": workspacePath.map((p) => p.toJson).get(newJNull()),
    "rootUri": workspacePath.map((p) => p.toUri.toJson).get(newJNull()),
    "workspaceFolders": workspaces,
    "trace": "verbose",
    "capabilities": %*{
      "workspace": %*{
        "workspaceFolders": true,
        "fileOperations": %*{
          "didOpen": true,
          "didClose": true,
          "didChange": true,
        },
        "configuration": true,
        "didChangeConfiguration": {},
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

  let res = await client.sendRequest("initialize", params)
  client.isInitialized = true

  await client.sendNotification("initialized", newJObject())

  for req in client.pendingRequests:
    if logVerbose:
      debug "[initialize] sending pending request", req[0..min(req.high, 500)]
    let header = createHeader(req.len)
    await client.connection.send(header & req)

  return res

proc tryGetPortFromLanguagesServer(url: string, port: int, exePath: string, args: seq[string]): Future[Option[tuple[port, processId: int]]] {.async.} =
  debugf"tryGetPortFromLanguagesServer {url}, {port}, {exePath}, {args}"
  try:
    let body = $ %*{
      "path": exePath,
      "args": args,
    }

    let response = await httpPost(fmt"http://{url}:{port}/lsp/start", body)
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

proc sendInitializationRequest(client: LSPClient) {.async.} =
  log(lvlInfo, "Initializing client...")
  let response = await client.initialize()
  if response.isError:
    log(lvlError, fmt"[sendInitializationRequest] Got error response: {response}")
    return

  client.serverCapabilities = response.result["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
  log(lvlInfo, "Server capabilities: ", client.serverCapabilities)

  if client.serverCapabilities.textDocumentSync.asTextDocumentSyncKind().getSome(syncKind):
    if syncKind == TextDocumentSyncKind.Full:
      client.fullDocumentSync = true

  elif client.serverCapabilities.textDocumentSync.asTextDocumentSyncOptions().getSome(syncOptions):
    if syncOptions.change == TextDocumentSyncKind.Full:
      client.fullDocumentSync = true

proc connect*(client: LSPClient, serverExecutablePath: string, workspaces: seq[string], args: seq[string], languagesServer: Option[(string, int)] = (string, int).none) {.async.} =
  client.workSpaceFolders = workspaces

  if languagesServer.getSome(lsConfig):
    log lvlInfo, fmt"Using languages server at '{lsConfig[0]}:{lsConfig[1]}' to find LSP connection"
    let serverConfig = await tryGetPortFromLanguagesServer(lsConfig[0], lsConfig[1], serverExecutablePath, args)
    if serverConfig.isNone:
      log(lvlError, "Failed to connect to languages server: no port found")
      return

    log lvlInfo, fmt"Using websocket connection on port {serverConfig.get.port} as LSP connection"
    var socket = await newWebSocket(fmt"ws://localhost:{serverConfig.get.port}")
    let connection = LSPConnectionWebsocket(websocket: socket, processId: serverConfig.get.processId)
    client.connection = connection
    asyncCheck client.sendInitializationRequest()

  else:
    when not defined(js):
      log lvlInfo, fmt"Using process '{serverExecutablePath} {args}' as LSP connection"
      let process = startAsyncProcess(serverExecutablePath, args)
      let connection = LSPConnectionAsyncProcess(process: process)
      connection.process.onRestarted = proc(): Future[void] =
        asyncCheck logProcessDebugOutput(process)
        return client.sendInitializationRequest()
      client.connection = connection

    else:
      log lvlError, "LSP connection not implemented for JS"
      return

proc translatePath(client: LSPClient, path: string): Future[string] {.async.} =
  if path.startsWith("@") and client.workspace.getSome workspace:
    try:
      let endOffset = path.find("/")
      let index = path[1..<endOffset].parseInt
      let info = workspace.info.await
      if index < info.folders.len:
        return info.folders[index].path / path[endOffset + 1..^1]
    except:
      log lvlError, &"Failed to translate path '{path}': {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

  return path

proc notifyOpenedTextDocument*(client: LSPClient, languageId: string, path: string, content: string) {.async.} =
  let path = client.translatePath(path).await
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "languageId": languageId,
      "version": 0,
      "text": content,
    },
  }

  await client.sendNotification("textDocument/didOpen", params)

proc notifyClosedTextDocument*(client: LSPClient, path: string) {.async.} =
  let path = client.translatePath(path).await
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
    },
  }

  await client.sendNotification("textDocument/didClose", params)

proc notifyTextDocumentChanged*(client: LSPClient, path: string, version: int, changes: seq[TextDocumentContentChangeEvent]) {.async.} =
  let path = client.translatePath(path).await
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "version": version,
    },
    "contentChanges": changes.toJson
  }

  await client.sendNotification("textDocument/didChange", params)

proc notifyTextDocumentChanged*(client: LSPClient, path: string, version: int, content: string) {.async.} =
  let path = client.translatePath(path).await
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

  await client.sendNotification("textDocument/didChange", params)

proc getDefinition*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DefinitionResponse]] {.async.} =
  # debugf"[getDefinition] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename).await

  client.cancelAllOf("textDocument/definition")

  let params = DefinitionParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/definition", params)).to DefinitionResponse

proc getDeclaration*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DeclarationResponse]] {.async.} =
  # debugf"[getDeclaration] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename).await

  client.cancelAllOf("textDocument/declaration")

  let params = DeclarationParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/declaration", params)).to DeclarationResponse

proc getHover*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DocumentHoverResponse]] {.async.} =
  let path = client.translatePath(filename).await

  client.cancelAllOf("textDocument/hover")

  let params = DocumentHoverParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/hover", params)).to DocumentHoverResponse

proc getInlayHints*(client: LSPClient, filename: string, selection: ((int, int), (int, int))): Future[Response[InlayHintResponse]] {.async.} =
  let path = client.translatePath(filename).await

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

  return (await client.sendRequest("textDocument/inlayHint", params)).to InlayHintResponse

proc getSymbols*(client: LSPClient, filename: string): Future[Response[DocumentSymbolResponse]] {.async.} =
  # debugf"[getSymbols] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename).await

  client.cancelAllOf("textDocument/documentSymbol")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
  ).toJson

  return (await client.sendRequest("textDocument/documentSymbol", params)).to DocumentSymbolResponse

proc getDiagnostics*(client: LSPClient, filename: string): Future[Response[DocumentDiagnosticResponse]] {.async.} =
  # debugf"[getSymbols] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename).await

  client.cancelAllOf("textDocument/diagnostic")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
  ).toJson

  return (await client.sendRequest("textDocument/diagnostic", params)).to DocumentDiagnosticResponse

proc getCompletions*(client: LSPClient, filename: string, line: int, column: int): Future[Response[CompletionList]] {.async.} =
  # debugf"[getCompletions] {filename.absolutePath}:{line}:{column}"
  let path = client.translatePath(filename).await

  client.cancelAllOf("textDocument/completion")

  let params = CompletionParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
    position: Position(
      line: line,
      character: column
    ),
    context: CompletionContext(
      triggerKind: CompletionTriggerKind.Invoked
    ).some
  ).toJson

  let response = (await client.sendRequest("textDocument/completion", params)).to CompletionResponse

  if response.isError:
    return response.to CompletionList

  let parsedResponse = response.result
  if parsedResponse.asCompletionItemSeq().getSome(items):
    return CompletionList(isIncomplete: false, items: items).success
  if parsedResponse.asCompletionList().getSome(list):
    return list.success

  # debugf"[getCompletions] {filename}:{line}:{column}: no completions found"
  return error[CompletionList](-1, fmt"[getCompletions] {filename}:{line}:{column}: no completions found")

proc handleWorkspaceConfigurationRequest(client: LSPClient, id: int, params: ConfigurationParams) {.async.} =
  if client.onWorkspaceConfiguration.isNil:
    log lvlWarn, fmt"No workspace configuration handler set"
    await client.sendResult("workspace/configuration", id, newJArray())
    return

  let res = client.onWorkspaceConfiguration(params).await
  await client.sendResult("workspace/configuration", id, %res)

proc runAsync*(client: LSPClient) {.async.} =
  while client.connection.isNotNil:
    # debugf"[run] Waiting for response {(client.activeRequests.len)}"
    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      log(lvlError, fmt"[run] Bad response: {response}")
      continue

    try:

      if not response.hasKey("id"):
        # Response has no id, it's a notification
        let meth = response["method"].getStr
        case meth
        of "window/logMessage", "window/showMessage":
          let messageType =  response["params"]["type"].jsonTo MessageType
          let message = response["params"]["message"].jsonTo string
          client.onMessage.invoke (messageType, message)

        of "textDocument/publishDiagnostics":
          let params = response["params"].jsonTo(PublicDiagnosticsParams, JOptions(allowMissingKeys: true, allowExtraKeys: true))
          client.onDiagnostics.invoke params

        else:
          log(lvlInfo, fmt"[run] {response}")

      elif response.hasKey("method"):
        # Not a response, but a server request
        let id = response["id"].getInt

        let meth = response["method"].getStr
        case meth
        of "workspace/configuration":
          let params = response["params"].jsonTo(ConfigurationParams, JOptions(allowMissingKeys: true, allowExtraKeys: true))
          asyncCheck client.handleWorkspaceConfigurationRequest(id, params)
        else:
          log lvlWarn, fmt"[run] Received request with id {id} and method {meth} but don't know how to handle it"

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
        else:
          log(lvlError, fmt"[run] error: received response with id {id} but got no active request for that id: {response}")
    except:
      log lvlError, &"[run] error: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"

proc run*(client: LSPClient) =
  asyncCheck client.runAsync()

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