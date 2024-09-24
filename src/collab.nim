import std/[strformat, strutils, tables, options, json, sugar, algorithm, asyncnet]
import misc/[util, event, myjsonutils, custom_logger, custom_async, delayed_task]
import scripting/[expose]
import config_provider, app_interface, dispatch_tables
import document

import text/text_document
import text/text_editor

import nimsumtree/[buffer, clock, rope]

logCategory "collab"

var sendOpsTask: DelayedTask
var opsToSend = newSeq[(string, Operation)]()
var currentServer: AsyncSocket = nil

proc sendOps(server: AsyncSocket) {.async.} =
  for op in opsToSend:
    let encoded = $op[1].toJson
    await server.send(&"op {op[0]}\n{encoded}\n")
  opsToSend.setLen(0)

proc connectCollaboratorAsync(port: int) {.async.} =
  ############### CLIENT
  var server: AsyncSocket

  let app: AppInterface = ({.gcsafe.}: gAppInterface)

  if currentServer != nil:
    opsToSend.setLen(0)
    sendOpsTask.pause()
    currentServer.close()
    currentServer = nil

  try:
    server = newAsyncSocket()
    currentServer = server
    await server.connect("localhost", port.Port)
    log lvlInfo, &"[collab-client] Connected to port {port.int}"

    let delay = app.configProvider.getValue[:int]("sync.delay", 100)
    sendOpsTask = startDelayed(delay, repeat=false):
      if not server.isClosed:
        asyncCheck sendOps(server)
    sendOpsTask.pause()

    var docs = initTable[string, TextDocument]()

    while not server.isClosed:
      let line = await server.recvLine()
      if line.len == 0:
        break

      if line.startsWith("open "):
        # line format: open <len>\t<filename>\t<operations>\n
        # next line <len> bytes
        let parts = line[5..^1]
        var i = 0
        template getNextPart(): string =
          block:
            let temp = parts.find("\t", i)
            let part = parts[i..<temp]
            i = temp + 1
            part

        let length = getNextPart().parseInt.catch:
          log lvlError, &"[collab-client] Invalid length: '{line}'"
          return

        let bufferId = getNextPart().parseInt.BufferId.catch:
          log lvlError, &"[collab-client] Invalid bufferId: '{line}'"
          return

        let file = getNextPart()
        let opsJson = parts[i..^1]
        let content = await server.recv(length)

        var ops = opsJson.parseJson.jsonTo(seq[Operation]).catch:
          log lvlError, &"[collab][open {file}] Failed to parse operations: {getCurrentExceptionMsg()}\nops: {opsJson}\n{getCurrentException().getStackTrace()}"
          continue

        if app.getOrOpenDocument(file).getSome(doc):
          if doc of TextDocument:
            let doc = doc.TextDocument
            docs[file] = doc
            doc.rebuildBuffer(1.ReplicaId, bufferId, content)
            doc.applyRemoteChanges(ops.move)

            discard doc.onOperation.subscribe proc(arg: tuple[document: TextDocument, op: Operation]) =
              opsToSend.add (arg.document.filename, arg.op.clone())
              sendOpsTask.schedule()
        else:
          log lvlError, &"[collab-client] Document not found: '{file}', message: '{line}'"

      elif line.startsWith("op "):
        let file = line[3..^1]
        let encoded = await server.recvLine()
        var op = encoded.parseJson().jsonTo(Operation).catch:
          log lvlError, &"Failed to parse operation: '{line}'"
          continue

        if app.getOrOpenDocument(file).getSome(doc) and doc of TextDocument:
          doc.TextDocument.applyRemoteChanges(@[op.move])

      else:
        log lvlError,  &"[collab-client] Unknown command '{line}'"

  except:
    log lvlError, &"[collab-client] Failed to connect to port {port.int}: {getCurrentExceptionMsg()}"
    return

proc connectCollaborator*(port: int = 6969) {.expose("collab").} =
  asyncCheck connectCollaboratorAsync(port)

proc processCollabClient(client: AsyncSocket) {.async.} =
  log lvlInfo, &"[collab-server] Process collab client"
  ############### SERVER

  let app: AppInterface = ({.gcsafe.}: gAppInterface)

  let delay = app.configProvider.getValue[:int]("sync.delay", 100)
  sendOpsTask = startDelayed(delay, repeat=false):
    if not client.isClosed:
      asyncCheck sendOps(client)
  sendOpsTask.pause()

  try:
    for doc in app.getAllDocuments():
      if doc of TextDocument:
        let doc = doc.TextDocument
        if doc.filename != "" and doc.filename != "log":
          let content = $doc.buffer.history.baseText
          var allOps = newSeqOfCap[Operation](doc.buffer.history.operations.len)
          for op in doc.buffer.history.operations.mvalues:
            allOps.add(op.clone())

          allOps.sort((a, b) => cmp(a.timestamp, b.timestamp))

          let opsJson = allOps.toJson
          await client.send(&"open {content.len}\t{doc.buffer.remoteId}\t{doc.filename}\t{opsJson}\n")
          await client.send(content)

          discard doc.onOperation.subscribe proc(arg: tuple[document: TextDocument, op: Operation]) =
            opsToSend.add (arg.document.filename, arg.op.clone())
            sendOpsTask.schedule()

    while not client.isClosed:
      let line = await client.recvLine()
      if line.len == 0:
        break

      if line.startsWith("op "):
        let file = line[3..^1]
        let encoded = await client.recvLine()
        var op = encoded.parseJson().jsonTo(Operation).catch:
          log lvlError, &"[collab-server] Failed to parse operation: '{line}'"
          continue

        if app.getOrOpenDocument(file).getSome(doc) and doc of TextDocument:
          doc.TextDocument.applyRemoteChanges(@[op.move])

      else:
        log lvlError,  &"[collab-server] Unknown command '{line}'"

    log lvlInfo, &"[collab-server] Client disconnected"
  except:
    log lvlError, &"[collab-server] Failed to read data from connection: {getCurrentExceptionMsg()}"

proc hostCollaboratorAsync(port: int) {.async.} =
  var server: AsyncSocket

  try:
    server = newAsyncSocket()
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(port.Port)
    server.listen()
    let actualPort = server.getLocalAddr()[1]
    log lvlInfo, &"[collab-server] Listen for connections on port {actualPort.int}"
  except:
    log lvlError, &"[collab-server] Failed to create server on port {port.int}: {getCurrentExceptionMsg()}"
    return

  while true:
    let client = await server.accept()

    asyncCheck processCollabClient(client)

proc hostCollaborator*(port: int = 6969) {.expose("collab").} =
  asyncCheck hostCollaboratorAsync(port)

genDispatcher("collab")
addGlobalDispatchTable "collab", genDispatchTable("collab")

proc dispatchEvent*(action: string, args: JsonNode): Option[JsonNode] =
  dispatch(action, args)
