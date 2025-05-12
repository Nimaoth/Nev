import std/[strutils, options, json, tables, uri, strformat, sequtils, typedthreads]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import misc/[event, util, custom_logger, custom_async, myjsonutils, custom_unicode, id, response, async_process, jsonex, rope_utils]
import language_server_base, app_interface, config_provider, lsp_client, document, document_editor, service, vfs, vfs_service
import workspaces/workspace as ws
import text/text_document

import nimsumtree/buffer
import nimsumtree/rope except Cursor
import text/workspace_edit

logCategory "lsp"

type
  LanguageServerLSP* = ref object of LanguageServer
    client: LSPClient
    initializedFuture: Future[bool]

    documentHandles: seq[tuple[document: Document, onEditHandle: Id]]

    thread: Thread[LSPClient]
    serverCapabilities*: ServerCapabilities
    fullDocumentSync: bool = false

    vfs: VFS
    localVfs: VFS

  LanguageServerLspService* = ref object of Service
    documents: DocumentEditorService
    workspace: Workspace
    config: ConfigService
    languageServers: Table[string, LanguageServerLSP]
    languageServersPerDocument*: Table[DocumentId, seq[LanguageServerLSP]]
    languageChangedHandles*: Table[DocumentId, Id]

func serviceName*(_: typedesc[LanguageServerLspService]): string = "LanguageServerLspService"

addBuiltinService(LanguageServerLspService, DocumentEditorService)

proc getOrCreateLanguageServerLSP*(self: LanguageServerLspService, name: string): Future[Option[LanguageServerLSP]] {.async.}

proc updateLanguageServersForDocument(self: LanguageServerLspService, doc: TextDocument) {.async.} =
  if self.languageServersPerDocument.contains(doc.id):
    for ls in self.languageServersPerDocument[doc.id]:
      discard doc.removeLanguageServer(ls)
    self.languageServersPerDocument.del(doc.id)

  let languageId = doc.languageId
  if languageId == "":
    return

  let lsps = self.config.runtime.get("lsp", newJexObject())
  if lsps == nil or lsps.kind != JObject:
    return

  var languageServers = newSeq[LanguageServerLSP]()
  for name, config in lsps.fields.pairs:
    try:
      if config.kind != JObject:
        if config.kind != JNull:
          log lvlError, &"Invalid LSP config (expected object): {config}"
        continue

      if not config.hasKey("command"):
        continue

      type LspConfig = object
        languages: seq[string]

      let lspConfig = config.jsonTo(LspConfig, Joptions(allowExtraKeys: true, allowMissingKeys: false))
      if languageId in lspConfig.languages or "*" in lspConfig.languages:
        if self.getOrCreateLanguageServerLSP(name).await.getSome(ls):
          languageServers.add(ls)
    except:
      discard

  if not doc.isInitialized or doc.languageId != languageId:
    return

  var languageServersAdded = newSeq[LanguageServerLSP]()
  for ls in languageServers:
    if doc.addLanguageServer(ls):
      languageServersAdded.add(ls)

  if languageServersAdded.len > 0:
    self.languageServersPerDocument[doc.id] = languageServersAdded

method init*(self: LanguageServerLspService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.documents = self.services.getService(DocumentEditorService).get
  self.workspace = self.services.getService(Workspace).get
  self.config = self.services.getService(ConfigService).get

  discard self.documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
    let d = editor.getDocument()
    if d of TextDocument:
      let doc = d.TextDocument
      if doc.id notin self.languageChangedHandles:
        asyncSpawn self.updateLanguageServersForDocument(doc)
        proc handleLanguageChanged(args: tuple[document: TextDocument]) {.raises: [].} =
          asyncSpawn self.updateLanguageServersForDocument(args.document)
        self.languageChangedHandles[doc.id] = doc.onLanguageChanged.subscribe(handleLanguageChanged)

  return ok()

proc deinitLanguageServers*() =
  {.gcsafe.}:
    let service = gServices.getService(LanguageServerLspService).get
    for languageServer in service.languageServers.values:
      if languageServer.client == nil:
        continue
      languageServer.stop()

    service.languageServers.clear()

proc handleWorkspaceConfigurationRequest*(self: LanguageServerLSP, params: lsp_types.ConfigurationParams):
    Future[seq[JsonNode]] {.gcsafe, async.} =
  var res = newSeq[JsonNode]()

  # logScope lvlInfo, &"handleWorkspaceConfigurationRequest {params}"
  # todo: this function is quite slow (up to 100ms)

  {.gcsafe.}:
    let config = gServices.getService(ConfigService).get
    let workspaceConfigName = config.runtime.get("lsp." & self.name & ".workspace-configuration-name", "settings")

    for item in params.items:
      # todo: implement scopeUri support
      if item.section.isNone:
        let key = ["lsp", self.name, workspaceConfigName].filterIt(it.len > 0).join(".")
        res.add config.runtime.get(key, newJNull())
        continue

      let key = ["lsp", self.name, workspaceConfigName, item.section.get].filterIt(it.len > 0).join(".")
      res.add config.runtime.get(key, newJNull())

  return res

proc handleApplyWorkspaceEditRequest*(self: LanguageServerLSP, params: lsp_types.ApplyWorkspaceEditParams):
    Future[lsp_types.ApplyWorkspaceEditResponse] {.gcsafe, async.} =

  # todo: nice error messages when failing
  if applyWorkspaceEdit(nil, nil, params.edit).await:
    return lsp_types.ApplyWorkspaceEditResponse(
      applied: true,
    )
  else:
    return lsp_types.ApplyWorkspaceEditResponse(
      applied: false,
      failureReason: "Internal error".some,
    )

proc handleWorkspaceConfigurationRequests(self: LanguageServerLSP) {.async.} =
  while self.client != nil:
    let params = self.client.workspaceConfigurationRequestChannel.recv().await.getOr:
      log lvlInfo, &"[{self.name}] handleWorkspaceConfigurationRequests: channel closed"
      return

    if self.client.isNil:
      break

    let response = await self.handleWorkspaceConfigurationRequest(params)
    await self.client.workspaceConfigurationResponseChannel.send(response)

  log lvlInfo, &"[{self.name}] handleWorkspaceConfigurationRequests: client gone"

proc handleApplyWorkspaceEditRequests(self: LanguageServerLSP) {.async.} =
  while self.client != nil:
    let params = self.client.workspaceApplyEditRequestChannel.recv().await.getOr:
      log lvlInfo, &"[{self.name}] handleApplyWorkspaceEditRequests: channel closed"
      return

    if self.client.isNil:
      break

    let response = await self.handleApplyWorkspaceEditRequest(params)
    await self.client.workspaceApplyEditResponseChannel.send(response)

  log lvlInfo, &"[{self.name}] handleApplyWorkspaceEditRequests: client gone"

proc handleMessages(self: LanguageServerLSP) {.async.} =
  while self.client != nil:
    let (messageType, message) = self.client.messageChannel.recv().await.getOr:
      log lvlInfo, &"[{self.name}] handleMessages: channel closed"
      return

    if self.client.isNil:
      break

    log lvlInfo, &"[{self.name}] {messageType}: {message}"
    self.onMessage.invoke (messageType, message)

  log lvlInfo, &"[{self.name}] handleMessages: client gone"

proc handleDiagnostics(self: LanguageServerLSP) {.async.} =
  while self.client != nil:
    let diagnostics = self.client.diagnosticChannel.recv().await.getOr:
      log lvlInfo, &"[{self.name}] handleDiagnostics: channel closed"
      return

    if self.client.isNil:
      break

    # debugf"textDocument/publishDiagnostics: {diagnostics}"
    self.onDiagnostics.invoke diagnostics

  log lvlInfo, &"[{self.name}] handleDiagnostics: client gone"

proc getOrCreateLanguageServerLSP*(self: LanguageServerLspService, name: string): Future[Option[LanguageServerLSP]] {.gcsafe, async.} =

  try:
    if self.languageServers.contains(name):
      let ls = self.languageServers[name]

      let initialized = await ls.initializedFuture
      if not initialized:
        return LanguageServerLSP.none

      return ls.some

    let config = self.config.runtime.get("lsp." & name, newJexNull())
    if config.isNil or config.kind != JObject:
      return LanguageServerLSP.none

    log lvlInfo, fmt"Starting language server for {name} with config {config}"

    if not config.hasKey("command"):
      log lvlError, &"Missing command in config for language server '{name}'"
      return LanguageServerLSP.none

    let command = config["command"].jsonTo(seq[string])

    let initializationOptionsName = config.fields.getOrDefault("initialization-options-name", newJexNull()).jsonTo(string).catch("settings")
    let userOptions = config.fields.getOrDefault(initializationOptionsName, newJexNull()).toJson

    let workspaceInfo = self.workspace.info.some
    let killOnExit = config.fields.getOrDefault("kill-on-exit", newJexBool(true)).jsonTo(bool).catch(true)

    let (exePath, args) = (command[0], command[1..^1])
    let workspaces = @[self.workspace.getWorkspacePath()]
    var client = newLSPClient(workspaceInfo, userOptions, exePath, workspaces, args, killOnExit)
    client.name = name

    var lsp = LanguageServerLSP(client: client, name: name)
    lsp.initializedFuture = newFuture[bool]("lsp.initializedFuture")
    self.languageServers[name] = lsp
    lsp.vfs = self.services.getService(VFSService).get.vfs
    lsp.localVfs = lsp.vfs.getVFS("local://").vfs # todo
    lsp.refetchWorkspaceSymbolsOnQueryChange = true

    asyncSpawn lsp.handleWorkspaceConfigurationRequests()
    asyncSpawn lsp.handleApplyWorkspaceEditRequests()
    asyncSpawn lsp.handleMessages()
    asyncSpawn lsp.handleDiagnostics()
    asyncSpawn client.handleResponses()

    lsp.thread.createThread(lspClientRunner, client)

    log lvlInfo, fmt"Started language server '{name}'"
    let serverCapabilities = client.initializedChannel.recv().await.get(ServerCapabilities.none)
    if serverCapabilities.getSome(capabilities):
      lsp.serverCapabilities = capabilities
      lsp.capabilities = capabilities
      lsp.initializedFuture.complete(true)

      let initialConfig = config.fields.getOrDefault("initial-configuration", newJexNull()).toJson
      if initialConfig.kind != JNull:
        asyncSpawn client.notifyConfigurationChangedChannel.send(initialConfig)

      if capabilities.textDocumentSync.asTextDocumentSyncKind().getSome(syncKind):
        if syncKind == TextDocumentSyncKind.Full:
          lsp.fullDocumentSync = true

      elif capabilities.textDocumentSync.asTextDocumentSyncOptions().getSome(syncOptions):
        if syncOptions.change == TextDocumentSyncKind.Full:
          lsp.fullDocumentSync = true

      return self.languageServers[name].some

    else:
      lsp.initializedFuture.complete(false)
      lsp.stop()
      self.languageServers.del(name)
      return LanguageServerLSP.none
  except:
    return LanguageServerLSP.none

proc toVfsPath*(self: LanguageServerLSP, lspPath: string): string =
  let localPath = lspPath.decodeUrl.parseUri.path.normalizePathUnix
  return self.localVfs.normalize(localPath)

method start*(self: LanguageServerLSP): Future[void] = discard
method stop*(self: LanguageServerLSP) {.gcsafe, raises: [].} =
  log lvlInfo, fmt"[{self.name}] Stopping language server for '{self.name}'"
  asyncSpawn self.client.stop()
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

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getDefinition(localizedPath, location.line, location.column)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getDefinition('{filename}', {location}): {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled get definition ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  return res

# todo: change return type to Response[seq[Definition]]
method getDeclaration*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.declarationProvider.isNone:
    return @[]

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getDeclaration(localizedPath, location.line, location.column)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getDeclaration('{filename}', {location}): {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled get declaration ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  return res

# todo: change return type to Response[seq[Definition]]
method getTypeDefinition*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.typeDefinitionProvider.isNone:
    return @[]

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getTypeDefinitions(localizedPath, location.line, location.column)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getTypeDefinition('{filename}', {location}): {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled get type definition ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  return res

# todo: change return type to Response[seq[Definition]]
method getImplementation*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.implementationProvider.isNone:
    return @[]

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getImplementation(localizedPath, location.line, location.column)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getImplementation('{filename}', {location}): {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled get implementation ({response.id}) for '{filename}':{location}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  return res

# todo: change return type to Response[seq[Definition]]
method getReferences*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =

  if self.serverCapabilities.referencesProvider.isNone:
    return @[]

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getReferences(localizedPath, location.line, location.column)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getReferences('{filename}', {location}): {response.error}")
    return newSeq[Definition]()

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled get references ({response.id}) for '{filename}':{location}")
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

  return newSeq[Definition]()

method switchSourceHeader*(self: LanguageServerLSP, filename: string): Future[Option[string]] {.async.} =
  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.switchSourceHeader(localizedPath)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in switchSourceHeader('{filename}'): {response.error}")
    return string.none

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled switch source header ({response.id}) for '{filename}'")
    return string.none

  if response.result.len == 0:
    return string.none

  return response.result.decodeUrl.parseUri.path.normalizePathUnix.some

# todo: change return type to Response
method getHover*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[Option[string]] {.async.} =

  if self.serverCapabilities.hoverProvider.isNone:
    return string.none

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getHover(localizedPath, location.line, location.column)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getHover('{filename}', {location}): {response.error}")
    return string.none

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled hover ({response.id}) for '{filename}':{location} ")
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

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getInlayHints(localizedPath, selection)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getInlayHints('{filename}', {selection}): {response.error}")
    return response.to(seq[language_server_base.InlayHint])

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled inlay hints ({response.id}) for '{filename}':{selection} ")
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
  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getSymbols(localizedPath)

  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getSymbols('{filename}'): {response.error}")
    return completions

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled symbols ({response.id}) for '{filename}' ")
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
method getWorkspaceSymbols*(self: LanguageServerLSP, filename: string, query: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]

  if self.serverCapabilities.workspaceSymbolProvider.isNone:
    return completions

  let response = await self.client.getWorkspaceSymbols(query)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getWorkspaceSymbols('{query}'): {response.error}")
    return completions

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled workspace symbols ({response.id}) for '{query}' ")
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
        log lvlWarn, fmt"[{self.name}] Failed to parse workspace symbol location: {r.location}"
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
    log lvlWarn, &"[{self.name}] Failed to parse getWorkspaceSymbols response"

  return completions

method getDiagnostics*(self: LanguageServerLSP, filename: string):
    Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  # debugf"getDiagnostics: {filename}"

  if self.serverCapabilities.diagnosticProvider.isNone:
    return success[seq[lsp_types.Diagnostic]](@[])

  let localizedPath = self.vfs.localize(filename)
  let response = await self.client.getDiagnostics(localizedPath)
  if response.isError:
    log(lvlWarn, &"[{self.name}] Error in getDiagnostics('{filename}'): {response.error}")
    return response.to(seq[lsp_types.Diagnostic])

  if response.isCanceled:
    # log(lvlInfo, &"[{self.name}] Canceled diagnostics ({response.id}) for '{filename}' ")
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

method getCodeActions*(self: LanguageServerLSP, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]):
    Future[Response[lsp_types.CodeActionResponse]] {.async.} =
  if self.serverCapabilities.codeActionProvider.isNone:
    return success(lsp_types.CodeActionResponse.default)
  let localizedPath = self.vfs.localize(filename)
  return await self.client.getCodeActions(localizedPath, selection, diagnostics)

method rename*(self: LanguageServerLSP, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
  let localizedPath = self.vfs.localize(filename)
  let res = await self.client.rename(localizedPath, position, newName)
  if res.isSuccess and res.result.getSome(edit):
    return success(@[edit])
  return res.to(seq[lsp_types.WorkspaceEdit])

method executeCommand*(self: LanguageServerLSP, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
  return await self.client.executeCommand(command, arguments)

import text/[text_editor, text_document]

method connect*(self: LanguageServerLSP, document: Document) =
  if not (document of TextDocument):
    return

  let document = document.TextDocument

  log lvlInfo, fmt"[{self.name}] Connecting document (loadingAsync: {document.isLoadingAsync}, requiresLoad: {document.requiresLoad}) '{document.filename}'"

  if document.requiresLoad or document.isLoadingAsync:
    var handle = new Id
    handle[] = document.onLoaded.subscribe proc(args: tuple[document: TextDocument, changed: seq[Selection]]): void =
      document.onLoaded.unsubscribe handle[]
      asyncSpawn self.client.notifyOpenedTextDocumentMain(document.languageId, args.document.localizedPath, args.document.contentString)
  else:
    asyncSpawn self.client.notifyOpenedTextDocumentMain(document.languageId, document.localizedPath, document.contentString)

  let onEditHandle = document.onEdit.subscribe proc(args: auto): void {.gcsafe, raises: [].} =
    # debugf"TEXT INSERTED {args.document.localizedPath}:{args.location}: {args.text}"
    # todo: we should batch these, as onEdit can be called multiple times per frame
    # especially for full document sync
    let version = args.document.buffer.history.versions.high
    let localizedPath = args.document.localizedPath

    if self.fullDocumentSync:
      asyncSpawn self.client.notifyTextDocumentChangedMain(localizedPath, version, args.document.contentString)
    else:
      var c = args.document.buffer.visibleText.cursorT(Point)
      # todo: currently relies on edits being sorted
      let changes = args.edits.mapIt(block:
        c.seekForward(Point.init(it.new.first.line, it.new.first.column))
        let text = c.slice(Point.init(it.new.last.line, it.new.last.column))
        let old = it.old.toRange
        var oldAdjusted: rope.Range[Point]
        oldAdjusted.a = it.new.first.toPoint
        oldAdjusted.b = oldAdjusted.a + (old.b - old.a).toPoint
        TextDocumentContentChangeEvent(range: language_server_base.toLspRange(oldAdjusted.toSelection), text: $text)
      )
      asyncSpawn self.client.notifyTextDocumentChangedMain(localizedPath, version, changes)

  self.documentHandles.add (document.Document, onEditHandle)

method disconnect*(self: LanguageServerLSP, document: Document) {.gcsafe, raises: [].} =
  if not (document of TextDocument):
    return

  let document = document.TextDocument

  log lvlInfo, fmt"[{self.name}] Disconnecting document '{document.filename}'"

  for i, d in self.documentHandles:
    if d.document != document:
      continue

    document.onEdit.unsubscribe d.onEditHandle
    self.documentHandles.removeSwap i
    break

  asyncSpawn self.client.notifyClosedTextDocumentMain(document.localizedPath)

  if self.documentHandles.len == 0:
    self.stop()

    let service = ({.gcsafe.}: gServices.getService(LanguageServerLspService).get)
    for (language, ls) in service.languageServers.pairs:
      if ls == self:
        log lvlInfo, &"[{self.name}] Removed language server for '{language}' from global language server list"
        service.languageServers.del language
        break
