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

let params = %*{
  "rootPath": "D:/dev/Nim/Absytree/temp",
  "capabilities": %*{
    "textDocument": %*{
      "completion": %*{
        "completionItem": %*{
          "snippetSupport": true
        },
        "completionProvider": true
      }
    },
    "array": %*[
      true,
      false,
      %*{
        "lol": 123,
        "xvlc": "nrtd"
      }
    ]
  }
}

# echo params ? capabilities.array[2].xvlc or newJString("uiae")
# echo params ? capabilities.array[2].xvlc
# echo params ? capabilities.array[2].xvl or newJString("uiae")
# echo params ? capabilities.array[2].xvl or "uiae"
# echo params ? capabilities.array[2].xvl



type
  LSPClient = ref object
    # socket: AsyncSocket
    process: AsyncProcess
    nextId: int
    activeRequests: Table[int, Future[JsonNode]]
    isInitialized: bool
    pendingRequests: seq[string]

  CompletionKind = enum
    Text = 1
    Method = 2
    Function = 3
    Constructor = 4
    Field = 5
    Variable = 6
    Class = 7
    Interface = 8
    Module = 9
    Property = 10
    Unit = 11
    Value = 12
    Enum = 13
    Keyword = 14
    Snippet = 15
    Color = 16
    File = 17
    Reference = 18
    Folder = 19
    EnumMember = 20
    Constant = 21
    Struct = 22
    Event = 23
    Operator = 24
    TypeParameter = 25

  MessageType* = enum
    Error = 1
    Warning = 2
    Info = 3
    Log = 4

  FilePosition = tuple[filename: string, line: int, column: int]
  Completion = object
    label: string
    kind: CompletionKind
    detail: string
    documentation: string

  ServerInfo* = object
    name: string
    version: string

proc toUri*(path: string): string =
  return "file:///" & path # todo: use file://{} for linux

proc sendHeader*(client: LSPClient, contentLength: int) {.async.} =
  let header = fmt"Content-Length: {contentLength}" & "\r\n\r\n"
  # echo header
  # await client.socket.send(header)
  await client.process.send(header)

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
  await client.sendHeader(data.len)
  # await client.socket.send(data)
  await client.process.send(data)
  # echo data, "\n"

proc sendNotification(client: LSPClient, meth: string, params: JsonNode) {.async.} =
  await client.sendRPC(meth, params, int.none)

proc sendRequest(client: LSPClient, meth: string, params: JsonNode): Future[JsonNode] {.async.} =
  let id = client.nextId
  inc client.nextId
  await client.sendRPC(meth, params, id.some)

  var requestFuture = newFuture[JsonNode]("LSPCLient.initialize")
  client.activeRequests[id] = requestFuture
  return await requestFuture

proc initialize*(client: LSPClient): Future[JsonNode] {.async.} =
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
  # echo "[initialize] got response"
  client.isInitialized = true

  await client.sendNotification("initialized", newJObject())

  for req in client.pendingRequests:
    echo "[initialize] sending pending request"
    await client.sendHeader(req.len)
    await client.process.send(req)

proc connect*(client: LSPClient, port: int) {.async.} =
  # Initialize the socket
  # client.socket = newAsyncSocket()
  # await client.socket.connect("", Port(port))
  client.process = startAsyncProcess("zls")
  client.process.onRestarted = proc() {.async.} =
    echo "Initializing client..."
    let response = await client.initialize()
    var serverCapabilities: ServerCapabilities = response["capabilities"].jsonTo(ServerCapabilities, Joptions(allowMissingKeys: true, allowExtraKeys: true))
    echo "Server capabilities:"
    echo serverCapabilities
  # client.process = startAsyncProcess("C:/Users/nimao/.vscode/extensions/rust-lang.rust-analyzer-0.3.1317-win32-x64/server/rust-analyzer.exe")

proc notifyOpenedTextDocument*(client: LSPClient, path: string, content: string) {.async.} =
  let params = %*{
    "textDocument": %*{
      "uri": path.toUri,
      "languageId": "zig",
      "version": 0,
      "text": content,
    },
  }

  await client.sendNotification("textDocument/didOpen", params)

proc parseCompletions(response: JsonNode): seq[Completion] =
  # Parse the completions from the response
  var completions = response["items"].elems
  result = @[]
  for completionJson in completions:
    var kind = cast[CompletionKind](completionJson["kind"].num)
    var completion = Completion(label: completionJson["label"].str, kind: kind)
    completion.detail = completionJson ? detail or ""
    completion.documentation = completionJson ? documentation or ""
    result.add completion

proc getCompletions*(client: LSPClient, fp: FilePosition): Future[seq[Completion]] {.async.} =
  # Create the LSP request for completions
  echo fmt"getCompletions({fp})"

  let params = %*{
    "textDocument": {
      "uri": fp.filename.toUri
    },
    "position": {
      "line": fp.line + 1,
      "character": fp.column
    }
  }

  return parseCompletions await client.sendRequest("textDocument/completion", params)

proc runAsync*(client: LSPClient) {.async.} =
  while true:
    # echo fmt"[run] Waiting for response {(client.activeRequests.len)}"
    let response = await client.parseResponse()
    if response.isNil or response.kind != JObject:
      echo "[bad response] ", response
      continue

    if response.hasKey("error"):
      let message = response ? error.message or "unknown error"
      let code = response ? error.code or 0
      let data = response ? error.data
      echo fmt"[error-{code}] {message} ({data})"

    elif not response.hasKey("id"):
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
        client.activeRequests[id].complete(response["result"])
        client.activeRequests.del(id)
      else:
        echo fmt"[run] error: received response with id {id} but got no active request for that id"

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
      client.getCompletions((testUri, line, column)).addCallback proc (f: Future[seq[Completion]]) =
        echo f.read
    messageFlowVar = spawn stdin.readLine()