import std/[strformat, strutils, tables, options, json, sugar, algorithm]
import chronos/transports/stream

import misc/[util, event, myjsonutils, custom_logger, custom_async, delayed_task]
import scripting/[expose]
import config_provider, app_interface, dispatch_tables
import document

import text/text_document
import text/text_editor

import nimsumtree/[buffer, clock, rope]

logCategory "collab"

proc connectCollaboratorAsync(port: int) {.async.} =
  ############### CLIENT
  try:
    let app: AppInterface = ({.gcsafe.}: gAppInterface)
    let delay = app.configProvider.getValue[:int]("sync.delay", 100)

    var opsToSend = newSeq[(string, Operation)]()
    var transp = await connect(initTAddress("127.0.0.1:" & $port))
    var reader = newAsyncStreamReader(transp)
    var writer = newAsyncStreamWriter(transp)

    log lvlInfo, &"[collab-client] Connected to port {port.int}"

    var sendOpsTask = startDelayedAsync(delay, repeat=false):
      if not transp.closed:
        let ops = opsToSend.move
        for op in ops:
          try:
            let encoded = op[1].toJson
            await writer.write(&"op {op[0]}\n{encoded}\n")
          except:
            raiseAssert("Failed to encode op " & $op)

    sendOpsTask.pause()

    var docs = initTable[string, TextDocument]()

    while not transp.closed:
      let line = await reader.readLine(sep = "\n")
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

        var content = ""
        content.setLen(length)
        await reader.readExactly(content[0].addr, length)

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
        let encoded = await reader.readLine(sep = "\n")
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
  asyncSpawn connectCollaboratorAsync(port)

proc processCollabClient(server: StreamServer, transp: StreamTransport) {.async: (raises: []).} =
  ############### SERVER
  log lvlInfo, &"[collab-server] Process collab client"
  try:
    let app: AppInterface = ({.gcsafe.}: gAppInterface)
    let delay = app.configProvider.getValue[:int]("sync.delay", 100)

    var opsToSend = newSeq[(string, Operation)]()
    var reader = newAsyncStreamReader(transp)
    var writer = newAsyncStreamWriter(transp)

    var sendOpsTask = startDelayedAsync(delay, repeat=false):
      if not transp.closed:
        let ops = opsToSend.move
        for op in ops:
          try:
            let encoded = op[1].toJson
            await writer.write(&"op {op[0]}\n{encoded}\n")
          except:
            raiseAssert("Failed to encode op " & $op)

    sendOpsTask.pause()

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
          await writer.write(&"open {content.len}\t{doc.buffer.remoteId}\t{doc.filename}\t{opsJson}\n")
          await writer.write(content)

          discard doc.onOperation.subscribe proc(arg: tuple[document: TextDocument, op: Operation]) {.gcsafe, raises: [].} =
            opsToSend.add (arg.document.filename, arg.op.clone())
            sendOpsTask.schedule()

    while not server.closed:
      let line = await reader.readLine(sep = "\n")
      if line.len == 0:
        break

      if line.startsWith("op "):
        let file = line[3..^1]
        let encoded = await reader.readLine(sep = "\n")
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
  var server: StreamServer

  try:
    server = createStreamServer(initTAddress("127.0.0.1:" & $port), processCollabClient, {ReuseAddr})
    server.start()
    let localAddress = server.localAddress()
    log lvlInfo, &"[collab-server] Listen for connections on port {localAddress}"
  except:
    log lvlError, &"[collab-server] Failed to create server on port {port.int}: {getCurrentExceptionMsg()}"
    return

proc hostCollaborator*(port: int = 6969) {.expose("collab").} =
  asyncSpawn hostCollaboratorAsync(port)

genDispatcher("collab")
addGlobalDispatchTable "collab", genDispatchTable("collab")

proc dispatchEvent*(action: string, args: JsonNode): Option[JsonNode] =
  dispatch(action, args)
