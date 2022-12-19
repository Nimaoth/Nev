import asyncdispatch, asyncnet, json, strutils, strformat, tables, os, osproc, asyncfile, streams, threadpool, options, macros, algorithm, sugar, uri
import myjsonutils, util, async_process, lsp_types

macro `?`(node: JsonNode, access: untyped): untyped =
  # defer:
    # echo result.treeRepr
    # echo result.repr
  # echo access.treeRepr
  # echo access.repr

  var resultSym = genSym(nskVar, "result")
  var assignmentsSym = genSym(nskLabel, "assignments")

  result = nnkBlockStmt.newTree
  result = quote do:
    block:
      var `resultSym`: JsonNode
      block `assignmentsSym`:
        `resultSym` = `node`

  var accesses: seq[(NimNodeKind, NimNode)]
  var current = access
  var default: Option[NimNode] = NimNode.none

  if current.kind == nnkInfix and current[0].eqIdent "or":
    default = current[2].some
    current = current[1]

  while true:
    case current.kind
    of nnkDotExpr, nnkBracketExpr:
      accesses.add (current.kind, current[1])
      current = current[0]
    of nnkIdent:
      accesses.add (nnkDotExpr, current)
      break
    else:
      break

  accesses.reverse

  for a in accesses:
    # echo a[0], ", ", a[1].treeRepr

    case a[0]
    of nnkBracketExpr:
      let index = a[1]
      result[1][1][1].add quote do:
        let index = `index`
        if `resultSym`.isNil or `resultSym`.kind != JArray or index < 0 or index >= `resultSym`.elems.len:
          `resultSym` = nil
          break `assignmentsSym`
        `resultSym` = `resultSym`[index]

    of nnkDotExpr:
      let member = a[1].strVal
      result[1][1][1].add quote do:
        if `resultSym`.isNil or `resultSym`.kind != JObject or not `resultSym`.hasKey(`member`):
          `resultSym` = nil
          break `assignmentsSym`
        `resultSym` = `resultSym`[`member`]

    else:
      assert false

  if default.isSome:
    let default = default.get
    result[1].add quote do:
      if `resultSym`.isNil:
        `default`
      else:
        when typeof(`default`) is int:
          `resultSym`.getInt `default`
        elif typeof(`default`) is float:
          `resultSym`.getFloat `default`
        elif typeof(`default`) is string:
          `resultSym`.getStr `default`
        elif typeof(`default`) is bool:
          `resultSym`.getBool `default`
        else:
          `resultSym`
  else:
    result[1].add quote do:
      if `resultSym`.isNil:
        `resultSym` = newJNull()
      `resultSym`

type
  LSPClient = ref object
    # socket: AsyncSocket
    process: AsyncProcess
    nextId: int
    activeRequests: Table[int, Future[Response[JsonNode]]]
    isInitialized: bool
    pendingRequests: seq[string]

  MessageType* = enum
    Error = 1
    Warning = 2
    Info = 3
    Log = 4

  FilePosition = tuple[filename: string, line: int, column: int]

  ServerInfo* = object
    name: string
    version: string

proc toUri*(path: string): Uri =
  return parseUri("file:///" & path) # todo: use file://{} for linux

proc createHeader*(contentLength: int): string =
  let header = fmt"Content-Length: {contentLength}" & "\r\n\r\n"
  return header

proc parseResponse*(client: LSPClient): Future[JsonNode] {.async.} =
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
      line = await client.process.recvLine
      lines.add line
      success = false
      continue
    let name = parts[0]
    let value = parts[1]
    headers[name] = value.strip
    # line = await client.socket.recvLine
    line = await client.process.recvLine
    # echo "< " & line

  # echo "[headers] ", headers
  if not success or not headers.contains("Content-Length"):
    echo "[parseResponse] Failed to parse response:"
    for line in lines:
      echo line
    return newJNull()

  let contentLength = headers["Content-Length"].parseInt
  # let data = await client.socket.recv(contentLength)
  let data = await client.process.recv(contentLength)
  return parseJson(data)

proc sendRPC*(client: LSPClient, meth: string, params: JsonNode, id: Option[int]) {.async.} =
  var request = %*{
    "jsonrpc": "2.0",
    "method": meth,
    "params": params,
  }
  if id.getSome(id):
    request["id"] = newJInt(id)

  if not client.isInitialized and meth != "initialize":
    echo fmt"[sendRPC] client not initialized, add to pending ({meth})"
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
  client.activeRequests[id] = requestFuture
  return await requestFuture

proc initialize*(client: LSPClient): Future[Response[JsonNode]] {.async.} =
  echo "[initialize]"
  let params = %*{
    "processId": os.getCurrentProcessId(),
    # "workspaceFolders": ["D:/dev/Nim/Absytree/temp"],
    "rootPath": "D:/dev/Nim/Absytree/temp",
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
        }
      }
    }
  }

  result = await client.sendRequest("initialize", params)
  client.isInitialized = true

  await client.sendNotification("initialized", newJObject())

  for req in client.pendingRequests:
    echo "[initialize] sending pending request"
    let header = createHeader(req.len)
    await client.process.send(header & req)

proc connect*(client: LSPClient, port: int) {.async.} =
  # Initialize the socket
  # client.socket = newAsyncSocket()
  # await client.socket.connect("", Port(port))
  client.process = startAsyncProcess("zls")
  client.process.onRestarted = proc() {.async.} =
    echo "Initializing client..."
    let response = await client.initialize()
    if response.isError:
      echo fmt"[onRestarted] Got error response: {response}"
      return
    var serverCapabilities: ServerCapabilities = response.result["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
    echo "Server capabilities:"
    echo serverCapabilities
  # client.process = startAsyncProcess("C:/Users/nimao/.vscode/extensions/rust-lang.rust-analyzer-0.3.1317-win32-x64/server/rust-analyzer.exe")

proc notifyOpenedTextDocument*(client: LSPClient, path: string, content: string) {.async.} =
  let params = %*{
    "textDocument": %*{
      "uri": $path.toUri,
      "languageId": "zig",
      "version": 0,
      "text": content,
    },
  }

  await client.sendNotification("textDocument/didOpen", params)

proc getCompletions*(client: LSPClient, fp: FilePosition): Future[Response[CompletionList]] {.async.} =
  echo fmt"[getCompletions] {fp}"

  let params = CompletionParams(
    textDocument: TextDocumentIdentifier(uri: fp.filename.toUri),
    position: Position(
      line: fp.line + 1,
      character: fp.column
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

  echo fmt"[getCompletions] {fp}: no completions found"
  return error[CompletionList](-1, fmt"[getCompletions] {fp}: no completions found")

proc runAsync*(client: LSPClient) {.async.} =
  while true:
    # echo fmt"[run] Waiting for response {(client.activeRequests.len)}"
    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      echo "[bad response] ", response
      continue

    if not response.hasKey("id"):
      # Response has no id, it's a notification

      case response["method"].getStr
      of "window/logMessage":
        let messageType = MessageType(response ? params.type or 4)
        let prefix = case messageType
        of Error: "[lsp-error]"
        of Warning: "[lsp-warning]"
        of Info: "[lsp-info]"
        of Log: "[lsp-log]"
        let message = response ? params.message or ""
        echo fmt"{prefix} {message}"
      else:
        echo fmt"[run] {response}"

    else:
      # echo fmt"[run] {response}"
      let id = response["id"].getInt
      if client.activeRequests.contains(id):
        # echo fmt"[run] Complete request {id}"
        let parsedResponse = response.toResponse JsonNode
        client.activeRequests[id].complete parsedResponse
        client.activeRequests.del(id)
      else:
        echo fmt"[run] error: received response with id {id} but got no active request for that id: {response}"

proc run*(client: LSPClient) =
  asyncCheck client.runAsync()

# let server = startProcess("zls")
var client = LSPClient()
waitFor client.connect(12345)
client.run()

let testUri = "D:/dev/Nim/Absytree/temp/test.zig"
waitFor client.notifyOpenedTextDocument(testUri, readFile(testUri))

# serverCapabilities.definitionProvider = some(DefinitionProviderVariant(node: %*{
#   "workDoneProgress": true
# }))

# if serverCapabilities.definitionProvider.asBool.getSome(enabled):
#   echo fmt"definition: {enabled}"

# if serverCapabilities.definitionProvider.asDefinitionOptions.getSome(options):
#   echo fmt"definition: {options}"

# echo "init sent"
# let completions = waitFor(client.getCompletions(("temp/test.zig", 4, 18)))
# echo completions


var messageFlowVar = spawn stdin.readLine()
while true:
  poll()

  if messageFlowVar.isReady:
    let line = ^messageFlowVar
    let parts = line.split " "
    if parts.len == 0:
      continue
    case parts[0]:
    of "c":
      if parts.len != 3:
        continue
      let line = parts[1].parseInt
      let column = parts[2].parseInt
      client.getCompletions((testUri, line, column)).addCallback proc (f: Future[Response[CompletionList]]) =
        let response = f.read
        if response.isError:
          echo fmt"Failed to get completions: {response.error}"
          return

        let completionList = response.result
        echo "isIncomplete: ", completionList.isIncomplete, ", len: ", completionList.items.len
    messageFlowVar = spawn stdin.readLine()