import std/[json, strutils, strformat, tables, sets, os, options, macros, uri]
import myjsonutils, util, async_process, lsp_types
import custom_logger, custom_async

export lsp_types

logCategory "lsp"

type
  LSPClient* = ref object
    # socket: AsyncSocket
    process: AsyncProcess
    nextId: int
    activeRequests: Table[int, tuple[meth: string, future: Future[Response[JsonNode]]]]
    requestsPerMethod: Table[string, seq[int]]
    canceledRequests: HashSet[int]
    isInitialized: bool
    pendingRequests: seq[string]

proc toUri*(path: string): Uri =
  return parseUri("file://" & path) # todo: use file://{} for linux

proc createHeader*(contentLength: int): string =
  let header = fmt"Content-Length: {contentLength}" & "\r\n\r\n"
  return header

proc close*(client: LSPClient) =
  client.process.destroy()
  client.process = nil
  client.nextId = 0
  client.activeRequests.clear()
  client.requestsPerMethod.clear()
  client.canceledRequests.clear()
  client.isInitialized = false
  client.pendingRequests.setLen 0

proc parseResponse(client: LSPClient): Future[JsonNode] {.async.} =
  # echo "[parseResponse]"
  var headers = initTable[string, string]()
  # var line = await client.socket.recvLine
  var line = await client.process.recvLine
  # echo "< " & line

  var success = true
  var lines = @[line]

  while line != "" and line != "\r\n":
    let parts = line.split(":")
    if parts.len != 2:
      success = false
      return newJString(line)

    let name = parts[0]
    if name != "Content-Length" and name != "Content-Type":
      success = false
      return newJString(line)

    let value = parts[1]
    headers[name] = value.strip
    # line = await client.socket.recvLine
    line = await client.process.recvLine
    # echo "< " & line

  # echo "[headers] ", headers
  if not success or not headers.contains("Content-Length"):
    log(lvlError, "[parseResponse] Failed to parse response:")
    for line in lines:
      log(lvlError, line)
    return newJNull()

  let contentLength = headers["Content-Length"].parseInt
  # let data = await client.socket.recv(contentLength)
  let data = await client.process.recv(contentLength)
  return parseJson(data)

proc sendRPC(client: LSPClient, meth: string, params: JsonNode, id: Option[int]) {.async.} =
  var request = %*{
    "jsonrpc": "2.0",
    "method": meth,
    "params": params,
  }
  if id.getSome(id):
    request["id"] = newJInt(id)

  if not client.isInitialized and meth != "initialize":
    log(lvlInfo, fmt"[sendRPC] client not initialized, add to pending ({meth})")
    client.pendingRequests.add $request
    return

  let data = $request
  let header = createHeader(data.len)
  await client.process.send(header & data)

proc sendNotification(client: LSPClient, meth: string, params: JsonNode) {.async.} =
  await client.sendRPC(meth, params, int.none)

proc sendRequest(client: LSPClient, meth: string, params: JsonNode): Future[Response[JsonNode]] {.async.} =
  let id = client.nextId
  inc client.nextId
  await client.sendRPC(meth, params, id.some)

  var requestFuture = newFuture[Response[JsonNode]]("LSPCLient.initialize")
  client.activeRequests[id] = (meth, requestFuture)
  if not client.requestsPerMethod.contains(meth):
    client.requestsPerMethod[meth] = @[]
  client.requestsPerMethod[meth].add id

  return await requestFuture

proc cancelAllOf*(client: LSPClient, meth: string) =
  if not client.requestsPerMethod.contains(meth):
    return

  var futures: seq[(int, Future[Response[JsonNode]])]
  for id in client.requestsPerMethod[meth]:
    let (_, future) = client.activeRequests[id]
    futures.add (id, future)
    client.activeRequests.del id
    client.canceledRequests.incl id

  client.requestsPerMethod[meth].setLen 0

  for (id, future) in futures:
    future.complete error[JsonNode](-1, fmt"{meth}:{id} canceled")

proc initialize(client: LSPClient): Future[Response[JsonNode]] {.async.} =
  let workspacePath = "D:/dev/Nim/Absytree"
  let params = %*{
    "processId": os.getCurrentProcessId(),
    "rootPath": workspacePath,
    "rootUri": "file://" & workspacePath,
    "workspaceFolders": %*[WorkspaceFolder(uri: "file://" & workspacePath, name: "test-name").toJson],
    "capabilities": %*{
      "general": %*{
        "positionEncodings": %*["utf-8"]
      },
      "textDocument": %*{
        "completion": %*{
          "completionItem": %*{
            "snippetSupport": true
          },
          "completionProvider": true
        },
        "definition": %*{
          "linkSupport": true
        },
        "declaration": %*{
          "linkSupport": true
        }
      }
    }
  }

  log(lvlInfo, fmt"[initialize] {params}")

  result = await client.sendRequest("initialize", params)
  client.isInitialized = true

  await client.sendNotification("initialized", newJObject())

  for req in client.pendingRequests:
    log(lvlInfo, fmt"[initialize] sending pending request {req}")
    let header = createHeader(req.len)
    await client.process.send(header & req)

proc connect*(client: LSPClient, serverExecutablePath: string) {.async.} =
  client.process = startAsyncProcess(serverExecutablePath)
  client.process.onRestarted = proc() {.async.} =
    log(lvlInfo, "Initializing client...")
    let response = await client.initialize()
    if response.isError:
      log(lvlError, fmt"[onRestarted] Got error response: {response}")
      return
    var serverCapabilities: ServerCapabilities = response.result["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
    log(lvlInfo, "Server capabilities: ", serverCapabilities)

proc notifyOpenedTextDocument*(client: LSPClient, languageId: string, path: string, content: string) {.async.} =
  let params = %*{
    "textDocument": %*{
      "uri": "file://" & path.absolutePath,
      "languageId": languageId,
      "version": 0,
      "text": content,
    },
  }

  await client.sendNotification("textDocument/didOpen", params)

proc notifyClosedTextDocument*(client: LSPClient, path: string) {.async.} =
  let params = %*{
    "textDocument": %*{
      "uri": "file://" & path.absolutePath,
    },
  }

  await client.sendNotification("textDocument/didClose", params)

proc notifyTextDocumentChanged*(client: LSPClient, path: string, version: int, changes: seq[TextDocumentContentChangeEvent]) {.async.} =
  let params = %*{
    "textDocument": %*{
      "uri": "file://" & path.absolutePath,
      "version": version,
    },
    "contentChanges": changes.toJson
  }

  await client.sendNotification("textDocument/didChange", params)

proc getDefinition*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DefinitionResponse]] {.async.} =
  # echo fmt"[getDefinition] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/definition")

  let params = DefinitionParams(
    textDocument: TextDocumentIdentifier(uri: "file://" & filename.absolutePath),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/definition", params)).to DefinitionResponse

proc getDeclaration*(client: LSPClient, filename: string, line: int, column: int): Future[Response[DeclarationResponse]] {.async.} =
  # echo fmt"[getDeclaration] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/declaration")

  let params = DeclarationParams(
    textDocument: TextDocumentIdentifier(uri: "file://" & filename.absolutePath),
    position: Position(
      line: line,
      character: column
    )
  ).toJson

  return (await client.sendRequest("textDocument/declaration", params)).to DeclarationResponse

proc getCompletions*(client: LSPClient, filename: string, line: int, column: int): Future[Response[CompletionList]] {.async.} =
  # echo fmt"[getCompletions] {filename.absolutePath}:{line}:{column}"

  client.cancelAllOf("textDocument/completion")

  let params = CompletionParams(
    textDocument: TextDocumentIdentifier(uri: "file://" & filename.absolutePath),
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

  # echo fmt"[getCompletions] {filename}:{line}:{column}: no completions found"
  return error[CompletionList](-1, fmt"[getCompletions] {filename}:{line}:{column}: no completions found")

proc runAsync*(client: LSPClient) {.async.} =
  while true:
    # echo fmt"[run] Waiting for response {(client.activeRequests.len)}"
    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      log(lvlError, fmt"[run] Bad response: {response}")
      continue

    if not response.hasKey("id"):
      # Response has no id, it's a notification

      case response["method"].getStr
      of "window/logMessage", "window/showMessage":
        let messageType =  response["params"]["type"].jsonTo MessageType
        let level = case messageType
        of Error: lvlError
        of Warning: lvlWarn
        of Info: lvlInfo
        of Log: lvlDebug
        let message = response["params"]["message"].jsonTo string
        log(level, message)
      of "textDocument/publishDiagnostics":
        # todo
        # echo "textDocument/publishDiagnostics"
        discard
      else:
        log(lvlInfo, fmt"[run] {response}")

    else:
      # echo fmt"[LSP.run] {response}"
      let id = response["id"].getInt
      if client.activeRequests.contains(id):
        # echo fmt"[LSP.run] Complete request {id}"
        let parsedResponse = response.toResponse JsonNode
        let (meth, future) = client.activeRequests[id]
        future.complete parsedResponse
        client.activeRequests.del(id)
        let index = client.requestsPerMethod[meth].find(id)
        assert index != -1
        client.requestsPerMethod[meth].delete index
      elif client.canceledRequests.contains(id):
        # Request was canceled
        # echo fmt"[LSP.run] Received response for canceled request {id}"
        client.canceledRequests.excl id
      else:
        log(lvlError, fmt"[run] error: received response with id {id} but got no active request for that id: {response}")

proc run*(client: LSPClient) =
  asyncCheck client.runAsync()