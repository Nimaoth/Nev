#use language_server_lsp terminal workspace_edit language_server_ue_as language_server_ue_cpp language_server_regex layout

const currentSourcePath2 = currentSourcePath()
include module_base

{.push gcsafe.}
{.push raises: [].}

when not defined(appLspServer):
  static:
    echo "DONT build lsp server"

when implModule and defined(appLspServer):
  import std/[strutils, strformat, options, tables, json, uri, sequtils]
  import misc/[custom_logger, util, custom_async, event, connection, response]
  import channel
  import nimsumtree/arc
  import service, command_service, layout/layout
  import vfs
  import terminal/terminal
  import scripting_api, language_server_ue_as, language_server_ue_cpp

  logCategory "lsp-server"

  when defined(windows):
    import winim/lean except POINT

  import misc/[custom_unicode, myjsonutils, rope_utils, jsonex, generational_seq]
  import nimsumtree/rope
  import text_component, language_server_component
  import document_editor, vfs_service
  import text/language/lsp_types as lsp_types
  import language_server_dynamic
  import language_server_lsp/language_server_lsp
  import workspaces/workspace

  proc toJsonHook*(item: lsp_types.CompletionItem): JsonNode =
    result = newJObject()
    for k, v in item.fieldPairs:
      when v is Option:
        if v.isSome:
          result[k] = toJson(v.get)
      elif v is seq:
        if v.len > 0:
          result[k] = toJson(v)
      else:
        result[k] = toJson(v)

  const
    ansiReset  = "\e[0m"
    ansiGreen  = "\e[32m"   ## received: stdin → Nev
    ansiYellow = "\e[33m"   ## sent:     Nev → stdout
    ansiRed    = "\e[31m"   ## error log lines

  type
    StdinThreadState = object
      channel: Arc[BaseChannel]
      logChannel: Arc[BaseChannel]   ## optional; mirrors received bytes in green

    StdoutThreadState = object
      channel: Arc[BaseChannel]
      logChannel: Arc[BaseChannel]   ## optional; mirrors sent bytes in yellow

    LSPServerConnectionStdin* = ref object of Connection
      readChannel: Arc[BaseChannel]   ## stdin thread writes here; async reads here
      writeChannel: Arc[BaseChannel]  ## send() writes here; stdout thread reads here
      logChannel: Arc[BaseChannel]    ## optional; log messages written here

    LspServerService* = ref object of DynamicService
      stdinThread: Thread[ptr StdinThreadState]
      stdinThreadState: StdinThreadState
      stdoutThread: Thread[ptr StdoutThreadState]
      stdoutThreadState: StdoutThreadState
      activeConnection: LSPServerConnectionStdin
      terminals: TerminalService
      layout: LayoutService
      editors: DocumentEditorService
      workspace: Workspace
      vfs: Arc[VFS2]
      debugLogStdin: Arc[BaseChannel]
      debugLogStdout: Arc[BaseChannel]
      diagnosticsHandle: Id

  func serviceName*(_: typedesc[LspServerService]): string = "LspServerService"

  proc logLine(chan: Arc[BaseChannel], level = lvlInfo, msg: string) =
    if chan.isNil:
      return
    try:
      if level >= lvlError:
        chan.write(ansiRed)
      chan.write("\r\n" & msg.replace("\n", "\r\n") & "\r\n")
      if level >= lvlError:
        chan.write(ansiReset)
    except IOError:
      discard

  proc stdinAvailable(): int =
    ## Returns how many bytes can be read from stdin right now without blocking.
    ## Returns -1 on error (pipe broken).
    when defined(windows):
      var bytesAvail: DWORD = 0
      if PeekNamedPipe(GetStdHandle(STD_INPUT_HANDLE), nil, 0, nil, bytesAvail.addr, nil) == 0:
        return -1
      result = bytesAvail.int
    else:
      var n: cint = 0
      if ioctl(STDIN_FILENO, FIONREAD, n.addr) < 0:
        return -1
      result = n.int

  proc stdinReaderThread(state: ptr StdinThreadState) {.thread.} =
    let chan = state.channel
    var buf: array[4096, uint8]
    while true:
      try:
        # Block until at least 1 byte arrives, then grab everything available.
        let first = stdin.readBuffer(buf[0].addr, 1)
        if first <= 0:
          chan.close()
          break

        var n = 1
        let avail = stdinAvailable()
        if avail > 0:
          let extra = min(avail, buf.len - 1)
          let m = stdin.readBuffer(buf[1].addr, extra)
          if m > 0:
            n += m

        chan.write(buf.toOpenArray(0, n - 1))
        if not state.logChannel.isNil:
          state.logChannel.write(ansiGreen)
          state.logChannel.write(buf.toOpenArray(0, n - 1))
          state.logChannel.write(ansiReset)
      except IOError, EOFError:
        chan.close()
        break

  proc stdoutWriterThread(state: ptr StdoutThreadState) {.thread.} =
    let chan = state.channel
    var buf: array[4096, uint8]
    try:
      while chan.isOpen or chan.flushRead() > 0:
        try:
          chan.get.signal.wait().waitFor()
        except CatchableError:
          discard
        while true:
          let n = chan.read(buf)
          if n <= 0:
            break
          if not state.logChannel.isNil:
            try:
              state.logChannel.write(ansiYellow)
              state.logChannel.write(buf.toOpenArray(0, n - 1))
              state.logChannel.write(ansiReset)
            except IOError:
              discard
          try:
            let written = stdout.writeBuffer(buf[0].addr, n)
            if written < n:
              break
          except IOError:
            break
        stdout.flushFile()
    except IOError:
      discard

  method close*(conn: LSPServerConnectionStdin) =
    conn.readChannel.close()
    conn.writeChannel.close()

  method recvLine*(conn: LSPServerConnectionStdin): Future[string] =
    conn.readChannel.readLine()

  method recv*(conn: LSPServerConnectionStdin, length: int): Future[string] =
    conn.readChannel.readAsync(length)

  method send*(conn: LSPServerConnectionStdin, data: string): Future[void] {.async: (raises: [IOError]).} =
    conn.writeChannel.write(data.toOpenArray(0, data.high))

  proc sendResponse(conn: LSPServerConnectionStdin, id: JsonNode, body: JsonNode) {.async: (raises: []).} =
    try:
      let body = $(%*{"jsonrpc": "2.0", "id": id, "result": body})
      let msg = "Content-Length: " & $body.len & "\r\n\r\n" & body
      await conn.send(msg)
    except CatchableError as e:
      conn.logChannel.logLine(lvlError, &"[sendResponse] {e.msg}")

  proc sendNotification(conn: LSPServerConnectionStdin, meth: string, params: JsonNode) {.async: (raises: []).} =
    try:
      let body = $(%*{"jsonrpc": "2.0", "method": meth, "params": params})
      let msg = "Content-Length: " & $body.len & "\r\n\r\n" & body
      await conn.send(msg)
    except CatchableError as e:
      conn.logChannel.logLine(lvlError, &"[sendNotification] {e.msg}")

  proc readMessage(conn: LSPServerConnectionStdin): Future[JsonNode] {.async: (raises: []).} =
    try:
      var line = await conn.recvLine()
      while line == "" or line == "\r\n":
        line = await conn.recvLine()

      var headers = initTable[string, string]()
      while line != "" and line != "\r\n":
        let parts = line.split(":", 1)
        if parts.len != 2:
          conn.logChannel.logLine(lvlError, &"[readMessage] Invalid header: '{line}'")
          return newJNull()
        headers[parts[0]] = parts[1].strip()
        line = await conn.recvLine()

      if not headers.contains("Content-Length"):
        conn.logChannel.logLine(lvlError, "[readMessage] Missing Content-Length header")
        return newJNull()

      let contentLength = headers["Content-Length"].parseInt
      let data = await conn.recv(contentLength)
      return parseJson(data)

    except CatchableError as e:
      conn.logChannel.logLine(lvlError, &"[readMessage] {e.msg}")
      return newJNull()

  proc uriToPath(uri: string, vfs: Arc[VFS2]): string =
    ## Converts a LSP file:// URI to a native filesystem path.
    ## e.g. "file:///C:/foo/bar.nim" -> "C:/foo/bar.nim" (Windows)
    ##      "file:///home/user/foo.nim" -> "/home/user/foo.nim" (Unix)
    let parsed = parseUri(uri)
    result = vfs.normalize(parsed.path.decodeUrl.normalizeNativePath)

  proc toUri*(path: string): Uri =
    proc encodePathUri(path: string): string = path.normalizePathUnix.split("/").mapIt(it.encodeUrl(false)).join("/")
    try:
      when defined(linux):
        return parseUri("file://" & path.absolutePath.encodePathUri)
      else:
        return parseUri("file:///" & path.absolutePath.encodePathUri)
    except CatchableError:
      when defined(linux):
        return parseUri("file://" & path.encodePathUri)
      else:
        return parseUri("file:///" & path.encodePathUri)

  proc textDocumentUriToPath(params: JsonNode, vfs: Arc[VFS2]): string =
    ## Extracts the URI from a textDocument params node and converts it to a path.
    ## Returns "" if the URI is missing or empty.
    let uri = params{"textDocument"}{"uri"}.getStr
    if uri == "": return ""
    uriToPath(uri, vfs)

  proc getLspBackup(self: LspServerService, name: string): Option[LanguageServerDynamic] =
    if name.endsWith(".as"):
      return getLanguageServerUEAs().some
    if name.endsWith(".h") or name.endsWith(".cpp"):
      return getLanguageServerUECpp().some
    return LanguageServerDynamic.none

  proc getLsp(self: LspServerService, name: string): Future[Option[LanguageServerDynamic]] {.async: (raises: []).} =
    ## Returns the named LSP instance (creating it if necessary), or none if
    ## the language_server_lsp module is unavailable or the server fails to start.
    let doc = self.editors.getDocumentByPath(name).getOr:
      return self.getLspBackup(name)
    let lsp = doc.getLanguageServerComponent().getOr:
      return self.getLspBackup(name)
    return lsp.languageServer.some

  proc runeSelectionToSelection(rope: Rope, cursor: RuneSelection): Selection =
    proc runeCursorToCursor(rope: Rope, c: RuneCursor): Cursor =
      if c.line < 0:
        return (0, 0)
      if c.line >= rope.lines:
        return rope.endPoint.toCursor
      return (c.line, rope.byteOffsetInLine(c.line, c.column))
    return (rope.runeCursorToCursor(cursor.first), rope.runeCursorToCursor(cursor.last))

  proc applyContentChanges(conn: LSPServerConnectionStdin, service: LspServerService, path: string, changes: JsonNode) =
    let doc = service.editors.getDocumentByPath(path).getOr:
      conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/didChange: document not open: {path}")
      return
    let text = doc.getTextComponent().getOr:
      conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/didChange: not a text document: {path}")
      return

    if changes.kind != JArray or changes.len == 0:
      return

    var selections = newSeq[Range[Point]]()
    var texts = newSeq[string]()

    for change in changes:
      let newText = change{"text"}.getStr
      let rangeNode = change{"range"}
      if rangeNode.isNil or rangeNode.kind == JNull:
        # Full sync: replace entire document
        let endPoint = text.content.summary().lines
        selections = @[Point.default...endPoint]
        texts = @[newText]
        break
      else:
        # Incremental: convert LSP range to internal selection
        try:
          let r = rangeNode.jsonTo(lsp_types.Range, Joptions(allowMissingKeys: true, allowExtraKeys: true))
          let runeSelection = (
            (r.start.line, r.start.character.RuneIndex),
            (r.`end`.line, r.`end`.character.RuneIndex))
          selections.add(text.content.runeSelectionToSelection(runeSelection).toRange)
          texts.add(newText)
        except CatchableError as e:
          conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/didChange: failed to parse range: {e.msg}")
          return

    if selections.len > 0:
      discard text.edit(selections, @[], texts, checkpoint = "insert")

  proc handleMessage(conn: LSPServerConnectionStdin, service: LspServerService, msg: JsonNode) {.async: (raises: []).} =
    let meth = msg{"method"}.getStr
    let id = msg{"id"}
    try:
      case meth
      of "initialize":
        let rootUri = msg{"params"}{"rootUri"}.getStr
        let rootPath = msg{"params"}{"rootPath"}.getStr
        let folders = msg{"params"}{"workspaceFolders"}
        let firstFolderUri = block:
          if folders != nil and folders.kind == JArray and folders.len > 0:
            folders[0]{"uri"}.getStr
          else:
            ""
        let workspaceRoot = if rootUri != "":
          parseUri(rootUri).path.decodeUrl.normalizeNativePath
        elif rootPath != "":
          rootPath
        elif firstFolderUri != "":
          parseUri(firstFolderUri).path.decodeUrl.normalizeNativePath
        else:
          ""
        if workspaceRoot != "" and service.workspace != nil:
          conn.logChannel.logLine(lvlError, &"[lsp-server] set workspace: {workspaceRoot}")
          service.workspace.setWorkspaceFolder(workspaceRoot)
          # if folders != nil and folders.kind == JArray and folders.len > 0:
          #   for f in 1..folders.elems.high:
          #     service.workspace.addWorkspaceFolder(f.elems[i]{"uri"}.getStr)

        let result = %*{
          "capabilities": %*{
            "positionEncoding": "utf-8",
            "textDocumentSync": 2,
            "completionProvider": %*{},
            "hoverProvider": true,
            "signatureHelpProvider": %*{},
            "definitionProvider": true,
            "declarationProvider": true,
            "typeDefinitionProvider": true,
            "implementationProvider": true,
            "referencesProvider": true,
            "documentSymbolProvider": true,
            "workspaceSymbolProvider": true,
            "codeActionProvider": true,
            "renameProvider": true,
            "inlayHintProvider": true,
          },
          "serverInfo": %*{
            "name": "nev",
          },
        }
        await conn.sendResponse(id, result)
      of "initialized":
        discard
      of "textDocument/didOpen":
        conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/didOpen {msg}")
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        if path != "":
          if service.editors.getDocumentByPath(path).isNone:
            let doc = service.editors.createDocument("text", path, load = false, %%*{"createLanguageServer": true})
            let initialText = msg{"params"}{"textDocument"}{"text"}.getStr
            conn.applyContentChanges(service, path, %*[{"text": initialText}])
            if service.editors.createEditorForDocument(doc).getSome(editor):
              let view = newEditorView(editor, doc)
              service.layout.addView(view, "*.right.+", focus = false)

            # let angelLs = await service.getLsp(path)
            # if angelLs.isSome:
            #   conn.logChannel.logLine(lvlError, &"[lsp-server] connect {msg}")
            #   angelLs.get.connect(doc)

      of "textDocument/didChange":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let changes = msg{"params"}{"contentChanges"}
        if changes != nil and path != "":
          conn.applyContentChanges(service, path, changes)

      of "textDocument/definition", "textDocument/implementation",
         "textDocument/declaration", "textDocument/typeDefinition",
         "textDocument/references":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let line = msg{"params"}{"position"}{"line"}.getInt
        let character = msg{"params"}{"position"}{"character"}.getInt
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          conn.logChannel.logLine(lvlError, &"[lsp-server] {meth} {path}, {line}, {character}")
          let locs = case meth
            of "textDocument/definition":
              await angelLs.get.getDefinition(path, (line, character))
            of "textDocument/declaration":
              await angelLs.get.getDeclaration(path, (line, character))
            of "textDocument/typeDefinition":
              await angelLs.get.getTypeDefinition(path, (line, character))
            of "textDocument/references":
              await angelLs.get.getReferences(path, (line, character))
            else:
              await angelLs.get.getImplementation(path, (line, character))
          conn.logChannel.logLine(lvlError, &"[lsp-server] {meth} {locs}")
          if locs.len > 0:
            var locations = newJArray()
            for d in locs:
              let localPath = service.vfs.localize(d.filename)
              locations.add %*{
                "uri": $localPath.toUri,
                "range": {
                  "start": {"line": d.location.line, "character": d.location.column},
                  "end": {"line": d.location.line, "character": d.location.column},
                }
              }
            await conn.sendResponse(id, locations)
          else:
            await conn.sendResponse(id, newJArray())
        else:
          await conn.sendResponse(id, newJArray())

      of "textDocument/hover":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let line = msg{"params"}{"position"}{"line"}.getInt
        let character = msg{"params"}{"position"}{"character"}.getInt
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          conn.logChannel.logLine(lvlError, &"[lsp-server] hover {path}, {line}, {character}")
          let hoverText = await angelLs.get.getHover(path, (line, character))
          conn.logChannel.logLine(lvlError, &"[lsp-server] hover -> {hoverText}")
          if hoverText.isSome:
            await conn.sendResponse(id, %*{"contents": {"kind": "markdown", "value": hoverText.get}})
          else:
            await conn.sendResponse(id, newJNull())
        else:
          await conn.sendResponse(id, newJNull())

      of "textDocument/completion":
        # Right now we need to sleep a bit here because this function is triggered by textInserted and
        # the update to the LSP is also sent in textInserted, but it's bound after this and so it would be called
        # to late. The sleep makes sure we run the getCompletions call below after the server got the file change.
        await sleepAsync(2.milliseconds)
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let line = msg{"params"}{"position"}{"line"}.getInt
        let character = msg{"params"}{"position"}{"character"}.getInt
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          conn.logChannel.logLine(lvlError, &"[lsp-server] completion {path}, {line}, {character}")
          let completions = await angelLs.get.getCompletions(path, (line, character))
          conn.logChannel.logLine(lvlError, &"[lsp-server] completion -> {completions.kind}")
          if completions.isSuccess:
            var items = newJArray()
            for item in completions.result.items:
              items.add item.toJson
            await conn.sendResponse(id, items)
          else:
            await conn.sendResponse(id, newJArray())
        else:
          await conn.sendResponse(id, newJArray())

      of "textDocument/documentSymbol":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/documentSymbol {path}")
          let symbols = await angelLs.get.getSymbols(path)
          conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/documentSymbol -> {symbols.len} results")
          var items = newJArray()
          for s in symbols:
            let pos = %*{"line": s.location.line, "character": s.location.column}
            let range = %*{"start": pos, "end": pos}
            items.add %*{
              "name": s.name,
              "kind": s.symbolType.int,
              "range": range,
              "selectionRange": range,
            }
          await conn.sendResponse(id, items)
        else:
          await conn.sendResponse(id, newJArray())

      of "workspace/symbol":
        let query = msg{"params"}{"query"}.getStr
        # let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let angelLs = await service.getLsp(".as")
        if angelLs.isSome:
          conn.logChannel.logLine(lvlError, &"[lsp-server] workspace/symbol '{query}'")
          let symbols = await angelLs.get.getWorkspaceSymbolsRaw("temp.as", query)
          conn.logChannel.logLine(lvlError, &"[lsp-server] workspace/symbol -> {symbols.len} results")
          var items = newJArray()
          for s in symbols:
            let localPath = service.vfs.localize(s.path)
            var item = toJson(s.symbol)
            # patch the uri to use the local path
            if item{"location"} != nil:
              item["location"]["uri"] = %($localPath.toUri)
            items.add item
          await conn.sendResponse(id, items)
        else:
          await conn.sendResponse(id, newJArray())

      of "textDocument/codeAction":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let r = msg{"params"}{"range"}
        let startLine = r{"start"}{"line"}.getInt
        let startChar = r{"start"}{"character"}.getInt
        let endLine = r{"end"}{"line"}.getInt
        let endChar = r{"end"}{"character"}.getInt
        let contextDiags = msg{"params"}{"context"}{"diagnostics"}
        var diagnostics: seq[lsp_types.Diagnostic]
        if contextDiags != nil and contextDiags.kind == JArray:
          try:
            diagnostics = contextDiags.jsonTo(seq[lsp_types.Diagnostic], Joptions(allowMissingKeys: true, allowExtraKeys: true))
          except CatchableError as e:
            conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/codeAction: failed to parse diagnostics: {e.msg}")
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          let res = await angelLs.get.getCodeActions(path, ((startLine, startChar), (endLine, endChar)), diagnostics)
          if res.isSuccess:
            await conn.sendResponse(id, toJson(res.result))
          else:
            await conn.sendResponse(id, newJArray())
        else:
          await conn.sendResponse(id, newJArray())

      of "workspaceSymbol/resolve":
        let angelLs = await service.getLsp(".as")
        if angelLs.isSome:
          try:
            let symbol = msg{"params"}.jsonTo(lsp_types.WorkspaceSymbol, Joptions(allowMissingKeys: true, allowExtraKeys: true))
            let definition = await angelLs.get.resolveWorkspaceSymbol(symbol)
            if definition.isSome:
              let d = definition.get
              let localPath = service.vfs.localize(d.filename)
              var item = toJson(symbol)
              item["location"] = %*{
                "uri": $localPath.toUri,
                "range": {
                  "start": {"line": d.location.line, "character": d.location.column},
                  "end": {"line": d.location.line, "character": d.location.column},
                }
              }
              await conn.sendResponse(id, item)
            else:
              await conn.sendResponse(id, toJson(symbol))
          except CatchableError as e:
            conn.logChannel.logLine(lvlError, &"[lsp-server] workspaceSymbol/resolve: failed to parse symbol: {e.msg}")
            await conn.sendResponse(id, newJNull())
        else:
          await conn.sendResponse(id, newJNull())

      of "workspace/executeCommand":
        let command = msg{"params"}{"command"}.getStr
        let argsNode = msg{"params"}{"arguments"}
        var arguments: seq[JsonNode]
        if argsNode != nil and argsNode.kind == JArray:
          arguments = argsNode.elems
        let angelLs = await service.getLsp(".as")
        if angelLs.isSome:
          let res = await angelLs.get.executeCommand(command, arguments)
          if res.isSuccess:
            await conn.sendResponse(id, res.result)
          else:
            await conn.sendResponse(id, newJNull())
        else:
          await conn.sendResponse(id, newJNull())

      of "textDocument/signatureHelp":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let line = msg{"params"}{"position"}{"line"}.getInt
        let character = msg{"params"}{"position"}{"character"}.getInt
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          let res = await angelLs.get.getSignatureHelp(path, (line, character))
          if res.isSuccess and res.result.len > 0:
            await conn.sendResponse(id, toJson(res.result[0]))
          else:
            await conn.sendResponse(id, newJNull())
        else:
          await conn.sendResponse(id, newJNull())

      of "textDocument/inlayHint":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let r = msg{"params"}{"range"}
        let startLine = r{"start"}{"line"}.getInt
        let startChar = r{"start"}{"character"}.getInt
        let endLine = r{"end"}{"line"}.getInt
        let endChar = r{"end"}{"character"}.getInt
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          let res = await angelLs.get.getInlayHints(path, ((startLine, startChar), (endLine, endChar)))
          if res.isSuccess:
            var items = newJArray()
            for h in res.result:
              var item = %*{
                "position": {"line": h.location.line, "character": h.location.column},
                "label": h.label,
                "paddingLeft": h.paddingLeft,
                "paddingRight": h.paddingRight,
              }
              if h.kind.isSome:
                item["kind"] = %(h.kind.get.ord + 1)
              if h.tooltip.isSome:
                item["tooltip"] = %h.tooltip.get
              if h.textEdits.len > 0:
                item["textEdits"] = toJson(h.textEdits)
              items.add item
            await conn.sendResponse(id, items)
          else:
            await conn.sendResponse(id, newJArray())
        else:
          await conn.sendResponse(id, newJArray())

      of "textDocument/rename":
        let path = textDocumentUriToPath(msg{"params"}, service.vfs)
        let line = msg{"params"}{"position"}{"line"}.getInt
        let character = msg{"params"}{"position"}{"character"}.getInt
        let newName = msg{"params"}{"newName"}.getStr
        let angelLs = await service.getLsp(path)
        if path != "" and angelLs.isSome:
          conn.logChannel.logLine(lvlError, &"[lsp-server] textDocument/rename {path}, {line}, {character}, '{newName}'")
          let res = await angelLs.get.rename(path, (line, character), newName)
          if res.isSuccess and res.result.len > 0:
            await conn.sendResponse(id, toJson(res.result[0]))
          else:
            await conn.sendResponse(id, newJNull())
        else:
          await conn.sendResponse(id, newJNull())

      of "shutdown":
        await conn.sendResponse(id, newJNull())
      of "exit":
        conn.readChannel.close()
      else:
        conn.logChannel.logLine(lvlInfo, &"[lsp-server] unhandled method: {meth}")
    except CatchableError as e:
      conn.logChannel.logLine(lvlError, &"[lsp-server] error while handling method {meth} @ {id}: {e.msg}")

  proc run(conn: LSPServerConnectionStdin, service: LspServerService) {.async: (raises: []).} =
    while conn.readChannel.isOpen:
      let msg = await conn.readMessage()
      if msg.kind == JNull:
        conn.logChannel.logLine lvlError, &"null msg"
        if not conn.readChannel.isOpen:
          break
        continue
      asyncSpawn conn.handleMessage(service, msg)

  proc hookDiagnostics(self: LspServerService) {.async: (raises: []).} =
    if self.diagnosticsHandle != Id.default:
      return
    let ls = await self.getLsp(".as")
    if ls.isNone:
      self.debugLogStdout.logLine(lvlError, "hookDiagnostics: no ls found")
      return
    self.diagnosticsHandle = ls.get.onDiagnostics.subscribe proc(params: lsp_types.PublicDiagnosticsParams) =
      let conn = self.activeConnection
      if conn == nil:
        return
      let path = uriToPath(params.uri, self.vfs)
      let localPath = self.vfs.localize(path)
      var diags = newJArray()
      for d in params.diagnostics:
        diags.add toJson(d)
      asyncSpawn conn.sendNotification("textDocument/publishDiagnostics", %*{
        "uri": $localPath.toUri,
        "diagnostics": diags,
      })

  proc startConnection(self: LspServerService) =
    if self.activeConnection != nil:
      self.debugLogStdout.logLine(lvlInfo, "lsp-server.start: already running")
      return
    try:
      let conn = LSPServerConnectionStdin(
        readChannel: newInMemoryChannel(),
        writeChannel: newInMemoryChannel(),
        logChannel: self.debugLogStdout,
      )
      self.stdinThreadState = StdinThreadState(channel: conn.readChannel, logChannel: self.debugLogStdout)
      self.stdinThread.createThread(stdinReaderThread, self.stdinThreadState.addr)
      self.stdoutThreadState = StdoutThreadState(channel: conn.writeChannel, logChannel: self.debugLogStdout)
      self.stdoutThread.createThread(stdoutWriterThread, self.stdoutThreadState.addr)
      self.activeConnection = conn
      asyncSpawn conn.run(self)
      asyncSpawn self.hookDiagnostics()
      self.debugLogStdout.logLine(lvlInfo, "lsp-server.start: stdin connection started")
    except CatchableError as e:
      self.debugLogStdout.logLine(lvlError, &"Failed to start lsp server: {e.msg}")

  proc stopConnection(self: LspServerService) =
    if self.diagnosticsHandle != Id.default:
      let ls = getLanguageServerUEAs()
      if ls != nil:
        ls.onDiagnostics.unsubscribe(self.diagnosticsHandle)
      self.diagnosticsHandle = Id.default
    if self.activeConnection != nil:
      self.activeConnection.close()
      self.activeConnection = nil

  proc createLogTerminal(self: LspServerService) =
    self.terminals = self.services.getService(TerminalService).get(nil)
    self.layout = self.services.getService(LayoutService).get
    if self.terminals == nil or self.layout == nil:
      return
    self.debugLogStdin = newInMemoryChannel()
    self.debugLogStdout = newInMemoryChannel()
    let options = CreateTerminalOptions(group: "lsp-server", closeOnTerminate: false, slot: "#default")
    let view = self.terminals.createTerminalView(self.debugLogStdin, self.debugLogStdout, options)
    self.layout.addView(view, "#default", focus = true)

    const dummyBody = "{}"
    const dummyMsg = "Content-Length: " & $dummyBody.len & "\r\n\r\n" & dummyBody & "\r\n"
    try:
      self.debugLogStdout.write(ansiYellow)
      self.debugLogStdout.write(dummyMsg)
      self.debugLogStdout.write(ansiReset)
    except IOError:
      discard

  proc initService(self: LspServerService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    self.terminals = self.services.getService(TerminalService).get(nil)
    self.layout = self.services.getService(LayoutService).get
    self.editors = self.services.getService(DocumentEditorService).get(nil)
    self.workspace = self.services.getService(Workspace).get(nil)
    self.vfs = self.services.getService(VFSService).get.vfs2

    let commands = self.services.getService(CommandService).get

    discard commands.registerCommand(command_service.Command(
      namespace: "",
      name: "lsp-server.start",
      description: "Start LSP server, reading from stdin",
      parameters: @[],
      returnType: "void",
      execute: proc(args: string): string {.gcsafe, raises: [CatchableError].} =
        self.createLogTerminal()
        self.startConnection()
        return ""
    ))

    return ok()

  proc init_module_lsp_server*() {.cdecl, exportc, dynlib.} =
    log lvlInfo, "init_module_lsp_server"
    let services = getServices()
    if services == nil:
      log lvlWarn, "init_module_lsp_server: no services found"
      return

    let service = LspServerService()
    service.initImpl = proc(self: Service): Future[Result[void, ref CatchableError]] {.gcsafe, async: (raises: []).} =
      return await self.LspServerService.initService()

    services.addService(service)

  proc shutdown_module_lsp_server*() {.cdecl, exportc, dynlib.} =
    log lvlInfo, "shutdown_module_lsp_server"
    let services = getServices()
    if services == nil:
      return
    if services.getService(LspServerService).getSome(service):
      service.stopConnection()
