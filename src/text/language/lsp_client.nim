import std/[json, strutils, strformat, macros]
import misc/[custom_logger, async_http_client, websocket]
import scripting/expose

logCategory "lsp"

var logVerbose = false

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
    onRestarted: proc(): Future[void]
    nextId: int
    activeRequests: Table[int, tuple[meth: string, future: ResolvableFuture[Response[JsonNode]]]]
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    isInitialized: bool
    pendingRequests: seq[string]

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

method close(connection: LSPConnectionWebsocket) = connection.websocket.close()
method recvLine(connection: LSPConnectionWebsocket): Future[string] {.async.} =
  var newLineIndex = connection.buffer.find("\r\n")
  while newLineIndex == -1:
    connection.buffer.add connection.websocket.receiveStrPacket().await
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

proc close*(client: LSPClient) =
  assert client.connection.isNotNil, "LSP Client process should not be nil"

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
  while line == "":
    line = await client.connection.recvLine

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
    debug "[send] ", meth, ": ", str[0..min(str.high, 500)]

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

proc initialize(client: LSPClient, workspaceFolders: seq[string]): Future[Response[JsonNode]] {.async.} =
  let workspacePath = if workspaceFolders.len > 0:
    workspaceFolders[0].myNormalizedPath.some
  else:
    string.none

  let workspaces = workspaceFolders.mapIt(WorkspaceFolder(uri: $it.toUri, name: it.splitFile.name))

  let processId = when defined(js):
    # todo
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
        "documentSymbol": %*{
        },
      },
      "window": %*{
        "showDocument": %*{
          "support": true,
        },
      },
    },
  }

  log(lvlInfo, fmt"[initialize] {params.pretty}")

  result = await client.sendRequest("initialize", params)
  client.isInitialized = true

  await client.sendNotification("initialized", newJObject())

  for req in client.pendingRequests:
    if logVerbose:
      debug "[initialize] sending pending request", req[0..min(req.high, 500)]
    let header = createHeader(req.len)
    await client.connection.send(header & req)

proc tryGetPortFromLanguagesServer(url: string, port: int, exePath: string, args: seq[string]): Future[Option[int]] {.async.} =
  # return 3333.some
  debugf"tryGetPortFromLanguagesServer {url}, {port}, {exePath}, {args}"
  try:
    let body = $ %*{
      "path": exePath,
      "args": args,
    }

    let response = await httpPost(fmt"http://{url}:{port}/lsp/start", body)
    let json = response.parseJson
    if not json.hasKey("port") or json["port"].kind != JInt:
      return int.none

    return json["port"].num.int.some
  except CatchableError:
    log(lvlError, fmt"Failed to connect to languages server {url}:{port}: {getCurrentExceptionMsg()}")
    return int.none

when not defined(js):
  proc logProcessDebugOutput(process: AsyncProcess) {.async.} =
    while process.isAlive:
      let line = await process.recvErrorLine
      log(lvlDebug, fmt"[debug] {line}")

proc connect*(client: LSPClient, serverExecutablePath: string, workspaces: seq[string], args: seq[string], languagesServer: Option[(string, int)] = (string, int).none) {.async.} =
  client.onRestarted = proc() {.async.} =
    log(lvlInfo, "Initializing client...")
    let response = await client.initialize(workspaces)
    if response.isError:
      log(lvlError, fmt"[onRestarted] Got error response: {response}")
      return
    var serverCapabilities: ServerCapabilities = response.result["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
    log(lvlInfo, "Server capabilities: ", serverCapabilities)

  if languagesServer.getSome(lsConfig):
    log lvlInfo, fmt"Using languages server at '{lsConfig[0]}:{lsConfig[1]}' to find LSP connection"
    let port = await tryGetPortFromLanguagesServer(lsConfig[0], lsConfig[1], serverExecutablePath, args)
    if port.isNone:
      log(lvlError, "Failed to connect to languages server: no port found")
      return

    log lvlInfo, fmt"Using websocket connection on port {port.get} as LSP connection"
    var socket = await newWebSocket(fmt"ws://localhost:{port.get}")
    let connection = LSPConnectionWebsocket(websocket: socket)
    client.connection = connection
    asyncCheck client.onRestarted()

  else:
    when not defined(js):
      log lvlInfo, fmt"Using process '{serverExecutablePath} {args}' as LSP connection"
      let process = startAsyncProcess(serverExecutablePath, args)
      let connection = LSPConnectionAsyncProcess(process: process)
      connection.process.onRestarted = proc() {.async.} =
        asyncCheck logProcessDebugOutput(process)
        client.onRestarted().await
      client.connection = connection

    else:
      log lvlError, "LSP connection not implemented for JS"
      return

proc notifyOpenedTextDocument*(client: LSPClient, languageId: string, path: string, content: string) {.async.} =
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
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
    },
  }

  await client.sendNotification("textDocument/didClose", params)

proc notifyTextDocumentChanged*(client: LSPClient, path: string, version: int, changes: seq[TextDocumentContentChangeEvent]) {.async.} =
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "version": version,
    },
    "contentChanges": changes.toJson
  }

  await client.sendNotification("textDocument/didChange", params)

proc getDefinition*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DefinitionResponse]] {.async.} =
  # debugf"[getDefinition] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/definition")

  let params = DefinitionParams(
    textDocument: TextDocumentIdentifier(uri: $filename.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/definition", params)).to DefinitionResponse

proc getDeclaration*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DeclarationResponse]] {.async.} =
  # debugf"[getDeclaration] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/declaration")

  let params = DeclarationParams(
    textDocument: TextDocumentIdentifier(uri: $filename.toUri),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/declaration", params)).to DeclarationResponse

proc getSymbols*(client: LSPClient, filename: string): Future[Response[DocumentSymbolResponse]] {.async.} =
  # debugf"[getCompletions] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/documentSymbol")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $filename.toUri),
  ).toJson

  return (await client.sendRequest("textDocument/documentSymbol", params)).to DocumentSymbolResponse

proc getCompletions*(client: LSPClient, filename: string, line: int, column: int): Future[Response[CompletionList]] {.async.} =
  # debugf"[getCompletions] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/completion")

  let params = CompletionParams(
    textDocument: TextDocumentIdentifier(uri: $filename.toUri),
    position: Position(
      line: line,
      character: column
    )
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

proc runAsync*(client: LSPClient) {.async.} =
  while true:
    # debugf"[run] Waiting for response {(client.activeRequests.len)}"
    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      log(lvlError, fmt"[run] Bad response: {response}")
      continue

    if not response.hasKey("id"):
      # Response has no id, it's a notification
      let meth = response["method"].getStr
      case meth
      of "window/logMessage", "window/showMessage":
        let messageType =  response["params"]["type"].jsonTo MessageType
        let level = case messageType
        of Error: lvlError
        of Warning: lvlWarn
        of Info: lvlInfo
        of Log: lvlDebug
        let message = response["params"]["message"].jsonTo string
        log(level, fmt"[{meth}] {message}")
      of "textDocument/publishDiagnostics":
        # todo
        # debugf"textDocument/publishDiagnostics"
        discard
      else:
        log(lvlInfo, fmt"[run] {response}")

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

proc run*(client: LSPClient) =
  asyncCheck client.runAsync()

# exposed api

proc lspLogVerbose*(val: bool) {.expose("lsp").} =
  debugf"lspLogVerbose {val}"
  logVerbose = val