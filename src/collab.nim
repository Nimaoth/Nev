import std/[strformat, strutils, tables, options, json, sugar, algorithm]
import chronos/transports/stream

import misc/[util, event, myjsonutils, custom_logger, custom_async, delayed_task]
import scripting/[expose]
import config_provider, app_interface, dispatch_tables, document_editor
import document
import toast, layout
import scripting_api except TextDocumentEditor

import text/text_document, signs_component
import text/text_editor

import nimsumtree/[buffer, clock, rope]

logCategory "collab"

let highlightId = newId()

proc handleSelections(line: string, editors: DocumentEditorService) =
  let parts = line[4..^1]
  var i = 0
  template getNextPart(): string =
    block:
      var temp = parts.find("\t", i)
      if temp == -1:
        temp = parts.len
      let part = parts[i..<temp]
      i = temp + 1
      part

  let filename = getNextPart()
  let selections = getNextPart().parseJson.jsonTo(seq[Selection])
  if editors.getDocument(filename).getSome(doc):
    for editor in editors.getEditorsForDocument(doc):
      if editor of text_editor.TextDocumentEditor:
        let textEditor = editor.TextDocumentEditor
        textEditor.decorations.clearCustomHighlights(highlightId)
        for s in selections:
          var sel = s
          if sel.isEmpty:
            sel.last.column += 1
          textEditor.decorations.addCustomHighlight(highlightId, sel, "collabClientSelections")

proc connectCollaboratorAsync(port: int) {.async.} =
  ############### CLIENT
  try:
    let services: Services = ({.gcsafe.}: getServices())
    let editors = services.getService(DocumentEditorService).get
    let config = services.getService(ConfigService).get
    let delay = config.runtime.get("sync.delay", 100)

    var opsToSend = newSeq[(string, Operation)]()
    var selectionsToSend = newTable[string, seq[Selection]]()
    var transp = await connect(initTAddress("127.0.0.1:" & $port))
    var reader = newAsyncStreamReader(transp)
    var writer = newAsyncStreamWriter(transp)

    log lvlInfo, &"[collab-client] Connected to port {port.int}"

    var sendOpsTask = startDelayedPausedAsync(delay, repeat=false):
      if not transp.closed:
        let ops = opsToSend.move
        for op in ops:
          try:
            let encoded = op[1].toJson
            await writer.write(&"op {op[0]}\n{encoded}\n")
          except:
            raiseAssert("Failed to encode op " & $op)
        try:
          for file, selections in selectionsToSend.mpairs:
            let encoded = selections.toJson
            await writer.write(&"sel {file}\t{encoded}\n")
        except:
          discard
        selectionsToSend.clear()

    proc scheduleSync() =
      sendOpsTask.interval = config.runtime.get("sync.delay", 100).int64
      sendOpsTask.schedule()

    var docs = initTable[string, TextDocument]()

    while not transp.closed:
      debugf"[client] readLine"
      let line = await reader.readLine(sep = "\n")
      if line.len == 0:
        break

      debugf"[client] readLine -> '{line}'"
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
        if length > 0:
          await reader.readExactly(content[0].addr, length)

        var ops = opsJson.parseJson.jsonTo(seq[Operation]).catch:
          log lvlError, &"[collab][open {file}] Failed to parse operations: {getCurrentExceptionMsg()}\nops: {opsJson}\n{getCurrentException().getStackTrace()}"
          continue

        if editors.getOrOpenDocument(file).getSome(doc):
          if doc of TextDocument:
            let doc = doc.TextDocument
            docs[file] = doc
            doc.rebuildBuffer(1.ReplicaId, bufferId, content)
            doc.applyRemoteChanges(ops.move)

            discard doc.onOperation.subscribe proc(arg: tuple[document: TextDocument, op: Operation]) =
              opsToSend.add (arg.document.filename, arg.op.clone())
              scheduleSync()

            for editor in editors.getEditorsForDocument(doc):
              if editor of text_editor.TextDocumentEditor:
                let textEditor = editor.TextDocumentEditor
                discard textEditor.onSelectionsChanged.subscribe proc(args: tuple[editor: TextDocumentEditor]) =
                  if args.editor.document != nil:
                    selectionsToSend[args.editor.getFileName()] = args.editor.selections
                    scheduleSync()
        else:
          log lvlError, &"[collab-client] Document not found: '{file}', message: '{line}'"

      elif line.startsWith("op "):
        let file = line[3..^1]
        let encoded = await reader.readLine(sep = "\n")
        var op = encoded.parseJson().jsonTo(Operation).catch:
          log lvlError, &"Failed to parse operation: '{line}'"
          continue

        if editors.getOrOpenDocument(file).getSome(doc) and doc of TextDocument:
          doc.TextDocument.applyRemoteChanges(@[op.move])

      elif line.startsWith("sel "):
        handleSelections(line, editors)

      else:
        log lvlError,  &"[collab-client] Unknown command '{line}'"

  except:
    log lvlError, &"[collab-client] Failed to connect to port {port.int}: {getCurrentExceptionMsg()}"
    return

proc connectCollaborator*(port: int = 6969) {.expose("collab").} =
  asyncSpawn connectCollaboratorAsync(port)

proc processCollabClient(server: StreamServer, transp: StreamTransport) {.async: (raises: []).} =
  ############### SERVER

  try:
    log lvlInfo, &"[server] Client connected to collaborative editing session {transp.remoteAddress}"
    let toasts = getServices().getService(ToastService).get
    let layout = getServices().getService(LayoutService).get
    toasts.showToast("Collab", &"Client connected to collaborative editing session {transp.remoteAddress}", "info")
    let text = await layout.prompt(@["No", "Yes"], &"Accept connection from {transp.remoteAddress}")
    if text != "Yes".some:
      toasts.showToast("Collab", &"Denied connection from {transp.remoteAddress}", "info")
      return

    let services: Services = ({.gcsafe.}: getServices())
    let editors = services.getService(DocumentEditorService).get
    let config = services.getService(ConfigService).get
    let delay = config.runtime.get("sync.delay", 100)

    var opsToSend = newSeq[(string, Operation)]()
    var selectionsToSend = newTable[string, seq[Selection]]()
    var reader = newAsyncStreamReader(transp)
    var writer = newAsyncStreamWriter(transp)

    var sendOpsTask = startDelayedPausedAsync(delay, repeat=false):
      if not transp.closed:
        let ops = opsToSend.move
        for op in ops:
          try:
            let encoded = op[1].toJson
            await writer.write(&"op {op[0]}\n{encoded}\n")
          except:
            raiseAssert("Failed to encode op " & $op)
        try:
          for file, selections in selectionsToSend.mpairs:
            let encoded = selections.toJson
            await writer.write(&"sel {file}\t{encoded}\n")
        except:
          discard
        selectionsToSend.clear()

    proc scheduleSync() =
      sendOpsTask.interval = config.runtime.get("sync.delay", 100).int64
      sendOpsTask.schedule()

    log lvlInfo, &"[server] Open documents on client"
    for doc in editors.getAllDocuments():
      if doc of TextDocument:
        let doc = doc.TextDocument
        if doc.usage == "" and doc.filename != "" and doc.filename != "log":
          debugf"open '{doc.filename}'"
          let content = $doc.buffer.history.baseText
          var allOps = newSeqOfCap[Operation](doc.buffer.history.operations.len)
          for op in doc.buffer.history.operations.mvalues:
            allOps.add(op.clone())

          allOps.sort((a, b) => cmp(a.timestamp, b.timestamp))

          let opsJson = allOps.toJson
          await writer.write(&"open {content.len}\t{doc.buffer.remoteId}\t{doc.filename}\t{opsJson}\n")
          if content.len > 0:
            await writer.write(content)

          discard doc.onOperation.subscribe proc(arg: tuple[document: TextDocument, op: Operation]) {.gcsafe, raises: [].} =
            opsToSend.add (arg.document.filename, arg.op.clone())
            scheduleSync()

          for editor in editors.getEditorsForDocument(doc):
            if editor of text_editor.TextDocumentEditor:
              let textEditor = editor.TextDocumentEditor
              discard textEditor.onSelectionsChanged.subscribe proc(args: tuple[editor: TextDocumentEditor]) =
                if args.editor.document != nil:
                  selectionsToSend[args.editor.getFileName()] = args.editor.selections
                  scheduleSync()

    while not server.closed:
      debugf"[server] readLine"
      let line = await reader.readLine(sep = "\n")
      if line.len == 0:
        break

      debugf"[server] readLine -> '{line}'"
      if line.startsWith("op "):
        let file = line[3..^1]
        let encoded = await reader.readLine(sep = "\n")
        var op = encoded.parseJson().jsonTo(Operation).catch:
          log lvlError, &"[collab-server] Failed to parse operation: '{line}'"
          continue

        if editors.getOrOpenDocument(file).getSome(doc) and doc of TextDocument:
          doc.TextDocument.applyRemoteChanges(@[op.move])

      elif line.startsWith("sel "):
        handleSelections(line, editors)

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
    # while true:
    #   let client = await server.accept()
    #   log lvlInfo, &"Client connected to collaborative editing session {client.remoteAddress}"
    #   if toasts.isSome:
    #     toasts.showToast("Collab", &"Client connected to collaborative editing session {client.remoteAddress}", "info")
    #   asyncSpawn server.processCollabClient(client)
  except:
    log lvlError, &"[collab-server] Failed to create server on port {port.int}: {getCurrentExceptionMsg()}"
    return

proc hostCollaborator*(port: int = 6969) {.expose("collab").} =
  asyncSpawn hostCollaboratorAsync(port)

addGlobalDispatchTable "collab", genDispatchTable("collab")
