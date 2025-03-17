import std/[strutils, options, json, tables, uri, strformat, sequtils, typedthreads]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import misc/[event, util, custom_logger, custom_async, myjsonutils, custom_unicode, id, response, async_process]
import language_server_base, app_interface, config_provider, lsp_client, document, service, vfs, vfs_service
import workspaces/workspace as ws

import nimsumtree/buffer
import nimsumtree/rope except Cursor

logCategory "lsp"

type LanguageServerLSP* = ref object of LanguageServer
  client: LSPClient
  languageId: string
  initializedFuture: Future[bool]

  documentHandles: seq[tuple[document: Document, onEditHandle: Id]]

  thread: Thread[LSPClient]
  serverCapabilities*: ServerCapabilities
  fullDocumentSync: bool = false

  vfs: VFS
  localVfs: VFS

var languageServers = initTable[string, LanguageServerLSP]()

proc deinitLanguageServers*() =
  {.gcsafe.}:
    for languageServer in languageServers.values:
      languageServer.stop()

    languageServers.clear()

proc handleWorkspaceConfigurationRequest*(self: LanguageServerLSP, params: lsp_types.ConfigurationParams):
    Future[seq[JsonNode]] {.gcsafe, async.} =
  var res = newSeq[JsonNode]()

  logScope lvlInfo, &"handleWorkspaceConfigurationRequest {params}"
  # todo: this function is quite slow (up to 100ms)

  {.gcsafe.}:
    let config = gServices.getService(ConfigService).get
    let workspaceConfigName = config.runtime.get("lsp." & self.languageId & ".workspace-configuration-name", "settings")

    for item in params.items:
      # todo: implement scopeUri support
      if item.section.isNone:
        let key = ["lsp", self.languageId, workspaceConfigName].filterIt(it.len > 0).join(".")
        res.add config.runtime.get(key, newJNull())
        continue

      let key = ["lsp", self.languageId, workspaceConfigName, item.section.get].filterIt(it.len > 0).join(".")
      res.add config.runtime.get(key, newJNull())

  return res

proc handleWorkspaceConfigurationRequests(lsp: LanguageServerLSP) {.async.} =
  while lsp.client != nil:
    let params = lsp.client.workspaceConfigurationRequestChannel.recv().await.getOr:
      log lvlInfo, &"handleWorkspaceConfigurationRequests: channel closed"
      return

    if lsp.client.isNil:
      break

    let response = await lsp.handleWorkspaceConfigurationRequest(params)
    await lsp.client.workspaceConfigurationResponseChannel.send(response)

  log lvlInfo, &"handleWorkspaceConfigurationRequests: client gone"

proc handleMessages(lsp: LanguageServerLSP) {.async.} =
  while lsp.client != nil:
    let (messageType, message) = lsp.client.messageChannel.recv().await.getOr:
      log lvlInfo, &"handleMessages: channel closed"
      return

    if lsp.client.isNil:
      break

    log lvlInfo, &"{messageType}: {message}"
    lsp.onMessage.invoke (messageType, message)

  log lvlInfo, &"handleMessages: client gone"

proc handleDiagnostics(lsp: LanguageServerLSP) {.async.} =
  while lsp.client != nil:
    let diagnostics = lsp.client.diagnosticChannel.recv().await.getOr:
      log lvlInfo, &"handleDiagnostics: channel closed"
      return

    if lsp.client.isNil:
      break

    # debugf"textDocument/publishDiagnostics: {diagnostics}"
    lsp.onDiagnostics.invoke diagnostics

  log lvlInfo, &"handleDiagnostics: client gone"

proc getOrCreateLanguageServerLSP*(languageId: string, workspaces: seq[string],
    languagesServer: Option[(string, int)] = (string, int).none, workspace = ws.Workspace.none):
    Future[Option[LanguageServer]] {.gcsafe, async.} =

  try:
    {.gcsafe.}:
      if languageServers.contains(languageId):
        let lsp = languageServers[languageId]

        let initialized = await lsp.initializedFuture
        if not initialized:
          return LanguageServer.none

        return lsp.LanguageServer.some

    {.gcsafe.}:
      let services = gServices

    let configs = services.getService(ConfigService).get

    let config = configs.runtime.get("lsp." & languageId, newJObject())
    if config.isNil:
      return LanguageServer.none

    log lvlInfo, fmt"Starting language server for {languageId} with config {config}"

    if not config.hasKey("path"):
      log lvlError, &"Missing path in config for language server {languageId}"
      return LanguageServer.none

    let exePath = config["path"].jsonTo(string)
    let args: seq[string] = if config.hasKey("args"):
      config["args"].jsonTo(seq[string])
    else:
      @[]

    let initializationOptionsName = config.fields.getOrDefault("initialization-options-name", newJNull()).jsonTo(string).catch("settings")
    let userOptions = configs.runtime.get(
      "lsp." & languageId & "." & initializationOptionsName, newJNull())

    let workspaceInfo = if workspace.getSome(workspace):
      workspace.info.some
    else:
      ws.WorkspaceInfo.none

    var client = newLSPClient(workspaceInfo, userOptions, exePath, workspaces, args, languagesServer)
    client.languageId = languageId

    var lsp = LanguageServerLSP(client: client, languageId: languageId)
    lsp.initializedFuture = newFuture[bool]("lsp.initializedFuture")
    {.gcsafe.}:
      languageServers[languageId] = lsp
    lsp.vfs = services.getService(VFSService).get.vfs
    lsp.localVfs = lsp.vfs.getVFS("local://").vfs # todo

    asyncSpawn lsp.handleWorkspaceConfigurationRequests()
    asyncSpawn lsp.handleMessages()
    asyncSpawn lsp.handleDiagnostics()
    asyncSpawn client.handleResponses()

    lsp.thread.createThread(lspClientRunner, client)

    log lvlInfo, fmt"Started language server for '{languageId}'"
    let serverCapabilities = client.initializedChannel.recv().await.get(ServerCapabilities.none)
    if serverCapabilities.getSome(capabilities):
      lsp.serverCapabilities = capabilities
      lsp.initializedFuture.complete(true)

      let initialConfig = config.fields.getOrDefault("initial-configuration", newJNull())
      if initialConfig.kind != JNull:
        asyncSpawn client.notifyConfigurationChangedChannel.send(initialConfig)

      if capabilities.textDocumentSync.asTextDocumentSyncKind().getSome(syncKind):
        if syncKind == TextDocumentSyncKind.Full:
          lsp.fullDocumentSync = true

      elif capabilities.textDocumentSync.asTextDocumentSyncOptions().getSome(syncOptions):
        if syncOptions.change == TextDocumentSyncKind.Full:
          lsp.fullDocumentSync = true

    else:
      lsp.initializedFuture.complete(false)
      lsp.stop()
      return LanguageServer.none

    {.gcsafe.}:
      return languageServers[languageId].LanguageServer.some
  except:
    return LanguageServer.none

proc toVfsPath(self: LanguageServerLSP, lspPath: string): string =
  let localPath = lspPath.decodeUrl.parseUri.path.normalizePathUnix
  return self.localVfs.normalize(localPath)

method start*(self: LanguageServerLSP): Future[void] = discard
method stop*(self: LanguageServerLSP) {.gcsafe, raises: [].} =
  log lvlInfo, fmt"Stopping language server for '{self.languageId}'"
  # self.client.deinit()
  # todo: properly deinit client
  self.client = nil

method getCompletionTriggerChars*(self: LanguageServerLSP): set[char] =
  if self.serverCapabilities.completionProvider.getSome(opts):
    for s in opts.triggerCharacters:
      if s.len == 0: continue
      result.incl s[0]

template locationsResponseToDefinitions(parsedResponse: untyped): untyped =
  block:
    if parsedResponse.asLocation().getSome(loc):
      @[Definition(
        filename: self.toVfsPath(loc.uri),
        location: (line: loc.`range`.start.line, column: loc.`range`.start.character)
      )]

    elif parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
      var res = newSeq[Definition]()
      for location in locations:
        res.add Definition(
          filename: self.toVfsPath(location.uri),
          location: (line: location.`range`.start.line, column: location.`range`.start.character)
        )
      res

    elif parsedResponse.asLocationLinkSeq().getSome(locations) and locations.len > 0:
      var res = newSeq[Definition]()
      for location in locations:
        res.add Definition(
          filename: self.toVfsPath(location.targetUri),
          location: (
            line: location.targetSelectionRange.start.line,
            column: location.targetSelectionRange.start.character
          )
        )
      res

    else:
      newSeq[Definition]()

# todo: change return type to Response[seq[Definition]]
method getDefinition*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.serverCapabilities.definitionProvider.isNone:
    return @[]

  let response = await self.client.getDefinition(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"Canceled get definition ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No definitions found")
  return res

# todo: change return type to Response[seq[Definition]]
method getDeclaration*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.declarationProvider.isNone:
    return @[]

  let response = await self.client.getDeclaration(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"Canceled get declaration ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No declaration found")
  return res

# todo: change return type to Response[seq[Definition]]
method getTypeDefinition*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.typeDefinitionProvider.isNone:
    return @[]

  let response = await self.client.getTypeDefinitions(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"Canceled get type definition ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No type definitions found")
  return res

# todo: change return type to Response[seq[Definition]]
method getImplementation*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.implementationProvider.isNone:
    return @[]

  let response = await self.client.getImplementation(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"Canceled get implementation ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No implementations found")
  return res

# todo: change return type to Response[seq[Definition]]
method getReferences*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.referencesProvider.isNone:
    return @[]

  let response = await self.client.getReferences(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"Canceled get references ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  if parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
    var res = newSeq[Definition]()
    for location in locations:
      res.add Definition(
        filename: self.toVfsPath(location.uri),
        location: (line: location.`range`.start.line, column: location.`range`.start.character)
      )
    return res

  log(lvlError, "No references found")
  return newSeq[Definition]()

method switchSourceHeader*(self: LanguageServerLSP, filename: string): Future[Option[string]] {.async.} =
  let response = await self.client.switchSourceHeader(filename)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return string.none

  if response.isCanceled:
    # log(lvlInfo, &"Canceled switch source header ({response.id}) for '{filename}'")
    return string.none

  if response.result.len == 0:
    return string.none

  return response.result.decodeUrl.parseUri.path.normalizePathUnix.some

# todo: change return type to Response
method getHover*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[Option[string]] {.async.} =

  if self.serverCapabilities.hoverProvider.isNone:
    return string.none

  let response = await self.client.getHover(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return string.none

  if response.isCanceled:
    # log(lvlInfo, &"Canceled hover ({response.id}) for '{filename}':{location} ")
    return string.none

  let parsedResponse = response.result

  # important: the order of these checks is important
  if parsedResponse.contents.asMarkedStringVariantSeq().getSome(markedStrings):
    for markedString in markedStrings:
      if markedString.asString().getSome(str):
        return str.some
      if markedString.asMarkedStringObject().getSome(str):
        # todo: language
        return str.value.some

    return string.none

  if parsedResponse.contents.asMarkupContent().getSome(markupContent):
    return markupContent.value.some

  if parsedResponse.contents.asMarkedStringVariant().getSome(markedString):
    debugf"marked string variant: {markedString}"

    if markedString.asString().getSome(str):
      debugf"string: {str}"
      return str.some

    if markedString.asMarkedStringObject().getSome(str):
      debugf"string object lang: {str.language}, value: {str.value}"
      return str.value.some

    return string.none

  return string.none

method getInlayHints*(self: LanguageServerLSP, filename: string, selection: Selection):
    Future[Response[seq[language_server_base.InlayHint]]] {.async.} =

  if self.serverCapabilities.inlayHintProvider.isNone:
    return success[seq[language_server_base.InlayHint]](@[])

  let response = await self.client.getInlayHints(filename, selection)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return response.to(seq[language_server_base.InlayHint])

  if response.isCanceled:
    # log(lvlInfo, &"Canceled inlay hints ({response.id}) for '{filename}':{selection} ")
    return response.to(seq[language_server_base.InlayHint])

  let parsedResponse = response.result

  if parsedResponse.getSome(inlayHints):
    var hints: seq[language_server_base.InlayHint]
    for hint in inlayHints:
      let label = case hint.label.kind:
        of JString: hint.label.getStr
        of JArray:
          if hint.label.elems.len == 0:
            ""
          else:
            hint.label.elems[0]["value"].getStr
        else:
          ""

      hints.add language_server_base.InlayHint(
        location: (hint.position.line, hint.position.character),
        label: label,
        kind: hint.kind.mapIt(case it
          of lsp_types.InlayHintKind.Type: language_server_base.InlayHintKind.Type
          of lsp_types.InlayHintKind.Parameter: language_server_base.InlayHintKind.Parameter
        ),
        textEdits: hint.textEdits.mapIt(
          language_server_base.TextEdit(selection: it.`range`.toSelection, newText: it.newText)),
        # tooltip*: Option[string] # | MarkupContent # todo
        paddingLeft: hint.paddingLeft.get(false),
        paddingRight: hint.paddingRight.get(false),
        data: hint.data
      )

    return success[seq[language_server_base.InlayHint]](hints)

  # todo: better error message
  return errorResponse[seq[language_server_base.InlayHint]](-1, "Invalid response")

proc toInternalSymbolKind(symbolKind: SymbolKind): SymbolType =
  try:
    return SymbolType(symbolKind.ord)
  except:
    return SymbolType.Unknown

# todo: change return type to Response
method getSymbols*(self: LanguageServerLSP, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]

  if self.serverCapabilities.documentSymbolProvider.isNone:
    return completions

  debugf"[getSymbols] {filename}"
  let response = await self.client.getSymbols(filename)

  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return completions

  if response.isCanceled:
    # log(lvlInfo, &"Canceled symbols ({response.id}) for '{filename}' ")
    return completions

  let parsedResponse = response.result

  if parsedResponse.asDocumentSymbolSeq().getSome(symbols):
    for r in symbols:
      completions.add Symbol(
        location: (line: r.range.start.line, column: r.range.start.character),
        name: r.name,
        symbolType: r.kind.toInternalSymbolKind,
        filename: self.localVfs.normalize(filename),
      )

      for child in r.children:
        completions.add Symbol(
          location: (line: child.range.start.line, column: child.range.start.character),
          name: child.name,
          symbolType: child.kind.toInternalSymbolKind,
          filename: self.localVfs.normalize(filename),
        )


  elif parsedResponse.asSymbolInformationSeq().getSome(symbols):
    for r in symbols:
      let symbolKind = r.kind.toInternalSymbolKind

      completions.add Symbol(
        location: (line: r.location.range.start.line, column: r.location.range.start.character),
        name: r.name,
        symbolType: symbolKind,
        filename: self.toVfsPath(r.location.uri),
      )

  return completions

# todo: change return type to Response
method getWorkspaceSymbols*(self: LanguageServerLSP, query: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]

  if self.serverCapabilities.workspaceSymbolProvider.isNone:
    return completions

  let response = await self.client.getWorkspaceSymbols(query)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return completions

  if response.isCanceled:
    # log(lvlInfo, &"Canceled workspace symbols ({response.id}) for '{query}' ")
    return completions

  let parsedResponse = response.result

  if parsedResponse.asWorkspaceSymbolSeq().getSome(symbols):
    for r in symbols:
      let (path, location) = if r.location.asLocation().getSome(location):
        let cursor = (line: location.range.start.line, column: location.range.start.character)
        (self.toVfsPath(location.uri), cursor.some)
      elif r.location.asUriObject().getSome(uri):
        (self.toVfsPath(uri.uri), Cursor.none)
      else:
        log lvlError, fmt"Failed to parse workspace symbol location: {r.location}"
        continue

      let symbolKind = r.kind.toInternalSymbolKind

      completions.add Symbol(
        location: location.get((0, 0)),
        name: r.name,
        symbolType: symbolKind,
        filename: path,
      )

  elif parsedResponse.asSymbolInformationSeq().getSome(symbols):
    for r in symbols:
      let symbolKind = r.kind.toInternalSymbolKind

      completions.add Symbol(
        location: (line: r.location.range.start.line, column: r.location.range.start.character),
        name: r.name,
        symbolType: symbolKind,
        filename: self.toVfsPath(r.location.uri),
      )

  else:
    log lvlError, &"Failed to parse getWorkspaceSymbols response"

  return completions

method getDiagnostics*(self: LanguageServerLSP, filename: string):
    Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  # debugf"getDiagnostics: {filename}"

  if self.serverCapabilities.diagnosticProvider.isNone:
    return success[seq[lsp_types.Diagnostic]](@[])

  let response = await self.client.getDiagnostics(filename)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return response.to(seq[lsp_types.Diagnostic])

  if response.isCanceled:
    # log(lvlInfo, &"Canceled diagnostics ({response.id}) for '{filename}' ")
    return response.to(seq[lsp_types.Diagnostic])

  let report = response.result

  if report.asRelatedFullDocumentDiagnosticReport().getSome(report):
    return success[seq[lsp_types.Diagnostic]](report.items)

  # todo: better error message
  return errorResponse[seq[lsp_types.Diagnostic]](-1, "Invalid response")

method getCompletions*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[Response[CompletionList]] {.async.} =
  if self.serverCapabilities.completionProvider.isNone:
    return success(CompletionList())
  let localizedPath = self.vfs.localize(filename)
  return await self.client.getCompletions(localizedPath, location.line, location.column)

import text/[text_editor, text_document]

method connect*(self: LanguageServerLSP, document: Document) =
  if not (document of TextDocument):
    return

  let document = document.TextDocument

  log lvlInfo, fmt"Connecting document (loadingAsync: {document.isLoadingAsync}) '{document.filename}'"

  if document.requiresLoad or document.isLoadingAsync:
    var handle = new Id
    handle[] = document.onLoaded.subscribe proc(document: TextDocument): void =
      document.onLoaded.unsubscribe handle[]
      asyncSpawn self.client.notifyTextDocumentOpenedChannel.send (self.languageId, document.localizedPath, document.contentString)
  else:
    asyncSpawn self.client.notifyTextDocumentOpenedChannel.send (self.languageId, document.localizedPath, document.contentString)

  let onEditHandle = document.onEdit.subscribe proc(args: auto): void {.gcsafe, raises: [].} =
    # debugf"TEXT INSERTED {args.document.localizedPath}:{args.location}: {args.text}"
    # todo: we should batch these, as onEdit can be called multiple times per frame
    # especially for full document sync
    let version = args.document.buffer.history.versions.high
    let localizedPath = args.document.localizedPath

    if self.fullDocumentSync:
      asyncSpawn self.client.notifyTextDocumentChangedChannel.send (localizedPath, version, @[], args.document.contentString)
    else:
      var c = args.document.buffer.visibleText.cursorT(Point)
      # todo: currently relies on edits being sorted
      let changes = args.edits.mapIt(block:
        c.seekForward(Point.init(it.new.first.line, it.new.first.column))
        let text = c.slice(Point.init(it.new.last.line, it.new.last.column))
        TextDocumentContentChangeEvent(range: language_server_base.toLspRange(it.old), text: $text)
      )
      asyncSpawn self.client.notifyTextDocumentChangedChannel.send (localizedPath, version, changes, "")

  self.documentHandles.add (document.Document, onEditHandle)

method disconnect*(self: LanguageServerLSP, document: Document) {.gcsafe, raises: [].} =
  if not (document of TextDocument):
    return

  let document = document.TextDocument

  log lvlInfo, fmt"Disconnecting document '{document.filename}'"

  for i, d in self.documentHandles:
    if d.document != document:
      continue

    document.onEdit.unsubscribe d.onEditHandle
    self.documentHandles.removeSwap i
    break

  # asyncSpawn self.client.notifyClosedTextDocument(document.localizedPath)
  asyncSpawn self.client.notifyTextDocumentClosedChannel.send(document.localizedPath)

  if self.documentHandles.len == 0:
    self.stop()

    let languageServers = ({.gcsafe.}: languageServers.addr)
    for (language, ls) in languageServers[].pairs:
      if ls == self:
        log lvlInfo, &"Removed language server for '{language}' from global language server list"
        languageServers[].del language
        break
