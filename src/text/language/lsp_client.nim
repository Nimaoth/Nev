import std/[json, strutils, strformat, macros, options, tables, sets, uri, sequtils, sugar, os, genasts]
import misc/[custom_logger, async_http_client, websocket, util, event, myjsonutils, custom_async, response]
import scripting/expose
import platform/filesystem
from workspaces/workspace as ws import nil
import lsp_types, dispatch_tables
from std/logging import nil

import misc/async_process

export lsp_types

# logCategory "lsp"
proc logImpl(level: NimNode, args: NimNode, includeCategory: bool): NimNode {.used.} =
  var args = args
  if includeCategory:
    args.insert(0, newLit("[" & "lsp" & "] "))

  return genAst(level, args):
    # logging.log(level, args)
    echo level, ": ", args

macro log(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
  return logImpl(level, args, true)

macro logNoCategory(level: logging.Level, args: varargs[untyped, `$`]): untyped {.used.} =
  return logImpl(level, args, false)

template measureBlock(description: string, body: untyped): untyped {.used.} =
  # let timer = startTimer()
  body
  # block:
  #   let descriptionString = description
  #   logging.log(lvlInfo, "[" & "lsp" & "] " & descriptionString & " took " & $timer.elapsed.ms & " ms")

template logScope(level: logging.Level, text: string): untyped {.used.} =
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

  LSPClientObject* = object
    connection: LSPConnection
    nextId: int
    activeRequests: Table[int, tuple[meth: string, future: ResolvableFuture[Response[JsonNode]]]]
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    isInitialized: bool
    pendingRequests: seq[string]
    workspaceFolders: seq[string]
    workspaceInfo*: Option[ws.WorkspaceInfo]
    serverCapabilities: ServerCapabilities
    fullDocumentSync*: bool = false

    # initializedFuture: ResolvableFuture[bool]
    onWorkspaceConfiguration*: proc(params: ConfigurationParams): Future[seq[JsonNode]] {.gcsafe.}

    userInitializationOptions*: JsonNode
    serverExecutablePath: string
    args: seq[string]
    languagesServer: Option[(string, int)] = (string, int).none

    initializedChannel*: AsyncChannel[bool]
    workspaceConfigurationRequestChannel*: AsyncChannel[ConfigurationParams]
    workspaceConfigurationResponseChannel*: AsyncChannel[seq[JsonNode]]
    getCompletionsChannel*: AsyncChannel[string]
    messageChannel*: AsyncChannel[(MessageType, string)]
    diagnosticChannel*: AsyncChannel[PublicDiagnosticsParams]
    symbolsRequestChannel*: AsyncChannel[string]
    symbolsResponseChannel*: AsyncChannel[Response[DocumentSymbolResponse]]
    notifyTextDocumentOpenedChannel*: AsyncChannel[tuple[languageId: string, path: string, content: string]]
    notifyTextDocumentClosedChannel*: AsyncChannel[string]
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
    initializedChannel: newAsyncChannel[bool](),
    workspaceConfigurationRequestChannel: newAsyncChannel[ConfigurationParams](),
    workspaceConfigurationResponseChannel: newAsyncChannel[seq[JsonNode]](),
    getCompletionsChannel: newAsyncChannel[string](),
    messageChannel: newAsyncChannel[(MessageType, string)](),
    diagnosticChannel: newAsyncChannel[PublicDiagnosticsParams](),
    symbolsRequestChannel: newAsyncChannel[string](),
    symbolsResponseChannel: newAsyncChannel[Response[DocumentSymbolResponse]](),
    notifyTextDocumentOpenedChannel: newAsyncChannel[tuple[languageId: string, path: string, content: string]](),
    notifyTextDocumentClosedChannel: newAsyncChannel[string](),
    notifyTextDocumentChangedChannel: newAsyncChannel[tuple[path: string, version: int, changes: seq[TextDocumentContentChangeEvent], content: string]](),
  )

  return client

proc notifyConfigurationChanged*(client: LSPClient, settings: JsonNode) {.async.}

# proc waitInitialized*(client: LSPCLient): Future[bool] = client.initializedFuture.future

method close(connection: LSPConnection) {.base, gcsafe.} = discard
method recvLine(connection: LSPConnection): Future[string] {.base, gcsafe.} = discard
method recv(connection: LSPConnection, length: int): Future[string] {.base, gcsafe.} = discard
method send(connection: LSPConnection, data: string): Future[void] {.base, gcsafe.} = discard

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

proc encodePathUri(path: string): string = path.normalizePathUnix.split("/").mapIt(it.encodeUrl(false)).join("/")

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
  # debugf"sendNotification {meth}, {params}"
  await client.sendRPC(meth, params, int.none)

proc sendResult(client: LSPClient, meth: string, id: int, res: JsonNode) {.async, gcsafe.} =
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

  let requestFuture = newResolvableFuture[Response[JsonNode]]("LSPCLient.initialize")

  client.activeRequests[id] = (meth, requestFuture)
  if not client.requestsPerMethod.contains(meth):
    client.requestsPerMethod[meth] = @[]
  client.requestsPerMethod[meth].add id

  return await requestFuture.future

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

  let res = await client.sendRequest("initialize", params)
  if res.isError:
    log lvlError, &"Failed to initialize lsp: {res.error}"
    # client.initializedFuture.complete(false)
    await client.initializedChannel.send(false)
    return res

  assert not res.isCanceled

  client.isInitialized = true

  await client.sendNotification("initialized", newJObject())

  # client.initializedFuture.complete(true)
  await client.initializedChannel.send(true)

  for req in client.pendingRequests:
    if logVerbose:
      debug "[initialize] sending pending request", req[0..min(req.high, 500)]
    let header = createHeader(req.len)
    await client.connection.send(header & req)

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
        log(lvlDebug, fmt"[debug] {line}")

proc sendInitializationRequest(client: LSPClient) {.async, gcsafe.} =
  log(lvlInfo, "Initializing client...")
  let response = await client.initialize()
  if response.isError:
    log(lvlError, fmt"[sendInitializationRequest] Got error response: {response}")
    return

  assert not response.isCanceled

  client.serverCapabilities = response.result["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
  log(lvlInfo, "Server capabilities: ", client.serverCapabilities)

  if client.serverCapabilities.textDocumentSync.asTextDocumentSyncKind().getSome(syncKind):
    if syncKind == TextDocumentSyncKind.Full:
      client.fullDocumentSync = true

  elif client.serverCapabilities.textDocumentSync.asTextDocumentSyncOptions().getSome(syncOptions):
    if syncOptions.change == TextDocumentSyncKind.Full:
      client.fullDocumentSync = true

proc connect*(client: LSPClient) {.async, gcsafe.} =
  # client.initializedFuture = newResolvableFuture[bool]("client.initializedFuture")

  if client.languagesServer.getSome(lsConfig):
    log lvlInfo, fmt"Using languages server at '{lsConfig[0]}:{lsConfig[1]}' to find LSP connection"
    let serverConfig = await tryGetPortFromLanguagesServer(lsConfig[0], lsConfig[1], client.serverExecutablePath, client.args)
    if serverConfig.isNone:
      log(lvlError, "Failed to connect to languages server: no port found")
      return

  #   # log lvlInfo, fmt"Using websocket connection on port {serverConfig.get.port} as LSP connection"
  #   var socket = await newWebSocket(fmt"ws://localhost:{serverConfig.get.port}")
  #   let connection = LSPConnectionWebsocket(websocket: socket, processId: serverConfig.get.processId)
  #   client.connection = connection
  #   asyncCheck client.sendInitializationRequest()

  else:
    when not defined(js):
      log lvlInfo, fmt"Using process '{client.serverExecutablePath} {client.args}' as LSP connection"
      let process = startAsyncProcess(client.serverExecutablePath, client.args)
      let connection = LSPConnectionAsyncProcess(process: process)
      connection.process.onRestarted = proc(): Future[void] {.gcsafe.} =
        asyncCheck logProcessDebugOutput(process)
        return client.sendInitializationRequest()
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

proc notifyOpenedTextDocument*(client: LSPClient, languageId: string, path: string, content: string) {.async.} =
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

proc notifyClosedTextDocument*(client: LSPClient, path: string) {.async.} =
  let path = client.translatePath(path)
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
    },
  }

  debugf"notifyClosedTextDocument {path}"
  await client.sendNotification("textDocument/didClose", params)

proc notifyTextDocumentChanged*(client: LSPClient, path: string, version: int,
    changes: seq[TextDocumentContentChangeEvent]) {.async.} =
  let path = client.translatePath(path)
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "version": version,
    },
    "contentChanges": changes.toJson
  }

  debugf"notifyTextDocumentChanged {path}, {version}"
  await client.sendNotification("textDocument/didChange", params)

proc notifyConfigurationChanged*(client: LSPClient, settings: JsonNode) {.async.} =
  await client.sendNotification("textDocument/didChangeConfiguration", settings)

proc notifyTextDocumentChanged*(client: LSPClient, path: string, version: int, content: string) {.async.} =
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

  debugf"notifyTextDocumentChanged {path}, {version}"
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

  return (await client.sendRequest("textDocument/definition", params)).to DefinitionResponse

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

  return (await client.sendRequest("textDocument/declaration", params)).to DeclarationResponse

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

  return (await client.sendRequest("textDocument/typeDefinition", params)).to TypeDefinitionResponse

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

  return (await client.sendRequest("textDocument/implementation", params)).to ImplementationResponse

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

  return (await client.sendRequest("textDocument/references", params)).to ReferenceResponse

proc switchSourceHeader*(client: LSPClient, filename: string): Future[Response[string]] {.async.} =
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/switchSourceHeader")

  let params = TextDocumentIdentifier(uri: $path.toUri).toJson

  return (await client.sendRequest("textDocument/switchSourceHeader", params)).to string

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

  return (await client.sendRequest("textDocument/hover", params)).to DocumentHoverResponse

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

  return (await client.sendRequest("textDocument/inlayHint", params)).to InlayHintResponse

proc getSymbols*(client: LSPClient, filename: string): Future[Response[DocumentSymbolResponse]] {.async.} =
  debugf"[getSymbols] {filename.absolutePath}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/documentSymbol")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
  ).toJson

  return (await client.sendRequest("textDocument/documentSymbol", params)).to DocumentSymbolResponse

proc getWorkspaceSymbols*(client: LSPClient, query: string): Future[Response[WorkspaceSymbolResponse]] {.async.} =
  debugf"[getWorkspaceSymbols]"
  client.cancelAllOf("workspace/symbol")

  let params = WorkspaceSymbolParams(
    query: query
  ).toJson

  return (await client.sendRequest("workspace/symbol", params)).to WorkspaceSymbolResponse

proc getDiagnostics*(client: LSPClient, filename: string): Future[Response[DocumentDiagnosticResponse]] {.async.} =
  debugf"[getSymbols] {filename.absolutePath}"
  let path = client.translatePath(filename)

  client.cancelAllOf("textDocument/diagnostic")

  let params = DocumentSymbolParams(
    textDocument: TextDocumentIdentifier(uri: $path.toUri),
  ).toJson

  return (await client.sendRequest("textDocument/diagnostic", params)).to DocumentDiagnosticResponse

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

  let response = (await client.sendRequest("textDocument/completion", params)).to CompletionResponse

  if response.isError or response.isCanceled:
    return response.to CompletionList

  let parsedResponse = response.result
  if parsedResponse.asCompletionItemSeq().getSome(items):
    return CompletionList(isIncomplete: false, items: items).success
  if parsedResponse.asCompletionList().getSome(list):
    return list.success

  debugf"[getCompletions] {filename}:{line}:{column}: no completions found"
  return error[CompletionList](-1, fmt"[getCompletions] {filename}:{line}:{column}: no completions found")

proc handleWorkspaceConfigurationRequest(client: LSPClient, id: int, params: ConfigurationParams) {.async, gcsafe.} =
  await client.workspaceConfigurationRequestChannel.send(params)
  let res = await client.workspaceConfigurationResponseChannel.recv()
  await client.sendResult("workspace/configuration", id, %res)

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
      discard

      if not response.hasKey("id"):
        # Response has no id, it's a notification
        let meth = response["method"].getStr
        case meth
        of "window/logMessage", "window/showMessage":
          let messageType =  response["params"]["type"].jsonTo MessageType
          let message = response["params"]["message"].jsonTo string
          asyncCheck client.messageChannel.send (messageType, message)

        of "textDocument/publishDiagnostics":
          let params = response["params"].jsonTo(PublicDiagnosticsParams, JOptions(allowMissingKeys: true, allowExtraKeys: true))
          asyncCheck client.diagnosticChannel.send params

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
          asyncCheck client.handleWorkspaceConfigurationRequest(id, params)
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
        else:
          log(lvlError, fmt"[run] error: received response with id {id} but got no active request for that id: {response}")
    except:
      log lvlError, &"[run] error: {getCurrentExceptionMsg()}\n{getCurrentException().getStackTrace()}"
      discard

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

genDispatcher("lsp")
addActiveDispatchTable "lsp", genDispatchTable("lsp"), global=true

proc dispatchEvent*(action: string, args: JsonNode): bool =
  dispatch(action, args).isSome

proc handleGetSymbols(client: LSPClient) {.async, gcsafe.} =
  while client != nil:
    let filename = client.symbolsRequestChannel.recv().await.getOr:
      log lvlInfo, &"handleGetSymbols: channel closed"
      return

    let response = await client.getSymbols(filename)
    await client.symbolsResponseChannel.send(response)

  log lvlInfo, &"handleGetSymbols: client gone"

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

proc lspClientRunner*(client: LSPClient) {.thread, nimcall.} =
  asyncCheck client.connect()
  asyncCheck client.runAsync()
  asyncCheck client.handleGetSymbols()
  asyncCheck client.handleNotifiesOpened()
  asyncCheck client.handleNotifiesClosed()
  asyncCheck client.handleNotifiesChanged()

  while true:
    if hasPendingOperations():
      poll()
