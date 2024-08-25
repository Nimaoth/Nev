import std/[strutils, options, json, tables, uri, strformat, sequtils, typedthreads]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import misc/[event, util, custom_logger, custom_async, myjsonutils, custom_unicode, id, response, async_process]
import platform/filesystem
import language_server_base, app_interface, config_provider, lsp_client, document
import workspaces/workspace as ws

logCategory "lsp"

type LanguageServerLSP* = ref object of LanguageServer
  client: LSPClient
  languageId: string
  initializedFuture: ResolvableFuture[bool]

  documentHandles: seq[tuple[document: Document, textInserted, textDeleted: Id]]

  thread: Thread[LSPClient]
  serverCapabilities*: ServerCapabilities
  fullDocumentSync: bool = false

var languageServers = initTable[string, LanguageServerLSP]()

proc deinitLanguageServers*() =
  for languageServer in languageServers.values:
    languageServer.stop()

  languageServers.clear()

proc handleWorkspaceConfigurationRequest*(self: LanguageServerLSP, params: lsp_types.ConfigurationParams):
    Future[seq[JsonNode]] {.async.} =
  var res = newSeq[JsonNode]()

  logScope lvlInfo, &"handleWorkspaceConfigurationRequest {params}"
  # todo: this function is quite slow (up to 100ms)

  let workspaceConfigName = gAppInterface.configProvider.getValue("lsp." & self.languageId & ".workspace-configuration-name", "settings")

  for item in params.items:
    # todo: implement scopeUri support
    if item.section.isNone:
      continue

    let key = ["lsp", self.languageId, workspaceConfigName, item.section.get].filterIt(it.len > 0).join(".")
    res.add gAppInterface.configProvider.getValue(key, newJNull())

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

    let level = case messageType
    of Error: lvlError
    of Warning: lvlWarn
    of Info: lvlInfo
    of Log: lvlDebug

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
    Future[Option[LanguageServerLSP]] {.async.} =

  if languageServers.contains(languageId):
    let lsp = languageServers[languageId]

    let initialized = await lsp.initializedFuture.future
    if not initialized:
      return LanguageServerLSP.none

    return lsp.some

  let config = gAppInterface.configProvider.getValue("lsp." & languageId, newJObject())
  if config.isNil:
    return LanguageServerLSP.none

  log lvlInfo, fmt"Starting language server for {languageId} with config {config}"

  if not config.hasKey("path"):
    log lvlError, &"Missing path in config for language server {languageId}"
    return LanguageServerLSP.none

  let exePath = config["path"].jsonTo(string)
  let args: seq[string] = if config.hasKey("args"):
    config["args"].jsonTo(seq[string])
  else:
    @[]

  let initializationOptionsName = config.fields.getOrDefault("initialization-options-name", newJNull()).jsonTo(string).catch("settings")
  let userOptions = gAppInterface.configProvider.getValue(
    "lsp." & languageId & "." & initializationOptionsName, newJNull())

  let workspaceInfo = if workspace.getSome(workspace):
    workspace.info.await.some
  else:
    ws.WorkspaceInfo.none

  var client = newLSPClient(workspaceInfo, userOptions, exePath, workspaces, args, languagesServer)
  client.languageId = languageId

  var lsp = LanguageServerLSP(client: client, languageId: languageId)
  lsp.initializedFuture = newResolvableFuture[bool]("lsp.initializedFuture")
  languageServers[languageId] = lsp

  asyncCheck lsp.handleWorkspaceConfigurationRequests()
  asyncCheck lsp.handleMessages()
  asyncCheck lsp.handleDiagnostics()
  asyncCheck client.handleResponses()

  lsp.thread.createThread(lspClientRunner, client)

  log lvlInfo, fmt"Started language server for '{languageId}'"
  let serverCapabilities = client.initializedChannel.recv().await.get(ServerCapabilities.none)
  if serverCapabilities.getSome(capabilities):
    lsp.serverCapabilities = capabilities
    lsp.initializedFuture.complete(true)

    let initialConfig = config.fields.getOrDefault("initial-configuration", newJNull())
    if initialConfig.kind != JNull:
      asyncCheck client.notifyConfigurationChangedChannel.send(initialConfig)

    if capabilities.textDocumentSync.asTextDocumentSyncKind().getSome(syncKind):
      if syncKind == TextDocumentSyncKind.Full:
        lsp.fullDocumentSync = true

    elif capabilities.textDocumentSync.asTextDocumentSyncOptions().getSome(syncOptions):
      if syncOptions.change == TextDocumentSyncKind.Full:
        lsp.fullDocumentSync = true

  else:
    lsp.initializedFuture.complete(false)
    lsp.stop()
    return LanguageServerLSP.none

  return languageServers[languageId].some

method start*(self: LanguageServerLSP): Future[void] = discard
method stop*(self: LanguageServerLSP) =
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
    if parsedResponse.asLocation().getSome(location):
      @[Definition(
        filename: location.uri.decodeUrl.parseUri.path.normalizePathUnix,
        location: (line: location.`range`.start.line, column: location.`range`.start.character)
      )]

    elif parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
      var res = newSeq[Definition]()
      for location in locations:
        res.add Definition(
          filename: location.uri.decodeUrl.parseUri.path.normalizePathUnix,
          location: (line: location.`range`.start.line, column: location.`range`.start.character)
        )
      res

    elif parsedResponse.asLocationLinkSeq().getSome(locations) and locations.len > 0:
      var res = newSeq[Definition]()
      for location in locations:
        res.add Definition(
          filename: location.targetUri.decodeUrl.parseUri.path.normalizePathUnix,
          location: (
            line: location.targetSelectionRange.start.line,
            column: location.targetSelectionRange.start.character
          )
        )
      res

    else:
      newSeq[Definition]()

method getDefinition*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  debugf"[getDefinition] {filename}"
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

method getDeclaration*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
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

method getTypeDefinition*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
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

method getImplementation*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
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

method getReferences*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
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
        filename: location.uri.decodeUrl.parseUri.path.normalizePathUnix,
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

method getHover*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[Option[string]] {.async.} =
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
  return error[seq[language_server_base.InlayHint]](-1, "Invalid response")

proc toInternalSymbolKind(symbolKind: SymbolKind): SymbolType =
  try:
    return SymbolType(symbolKind.ord)
  except:
    return SymbolType.Unknown

method getSymbols*(self: LanguageServerLSP, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]

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
        filename: filename,
      )

      for child in r.children:
        completions.add Symbol(
          location: (line: child.range.start.line, column: child.range.start.character),
          name: child.name,
          symbolType: child.kind.toInternalSymbolKind,
          filename: filename,
        )


  elif parsedResponse.asSymbolInformationSeq().getSome(symbols):
    for r in symbols:
      let symbolKind = r.kind.toInternalSymbolKind

      completions.add Symbol(
        location: (line: r.location.range.start.line, column: r.location.range.start.character),
        name: r.name,
        symbolType: symbolKind,
        filename: r.location.uri.decodeUrl.parseUri.path.normalizePathUnix,
      )

  return completions

method getWorkspaceSymbols*(self: LanguageServerLSP, query: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]

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
        (location.uri.parseUri.path.decodeUrl.normalizePathUnix, cursor.some)
      elif r.location.asUriObject().getSome(uri):
        (uri.uri.parseUri.path.decodeUrl.normalizePathUnix, Cursor.none)
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
        filename: r.location.uri.parseUri.path.decodeUrl.normalizePathUnix,
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
  return error[seq[lsp_types.Diagnostic]](-1, "Invalid response")

method getCompletions*(self: LanguageServerLSP, filename: string, location: Cursor):
    Future[Response[CompletionList]] {.async.} =
  return await self.client.getCompletions(filename, location.line, location.column)

import text/[text_editor, text_document]

method connect*(self: LanguageServerLSP, document: Document) =
  if not (document of TextDocument):
    return

  let document = document.TextDocument

  log lvlInfo, fmt"Connecting document (loadingAsync: {document.isLoadingAsync}) '{document.filename}'"

  if document.isLoadingAsync:
    var handle = new Id
    handle[] = document.onLoaded.subscribe proc(document: TextDocument): void =
      document.onLoaded.unsubscribe handle[]
      asyncCheck self.client.notifyTextDocumentOpenedChannel.send (self.languageId, document.fullPath, document.contentString)
  else:
    asyncCheck self.client.notifyTextDocumentOpenedChannel.send (self.languageId, document.fullPath, document.contentString)

  let textInsertedHandle = document.textInserted.subscribe proc(args: auto): void =
    # debugf"TEXT INSERTED {args.document.fullPath}:{args.location}: {args.text}"

    if self.fullDocumentSync:
      asyncCheck self.client.notifyTextDocumentChangedChannel.send (args.document.fullPath, args.document.version, @[], args.document.contentString)
      discard
    else:
      let changes = @[TextDocumentContentChangeEvent(
        `range`: args.location.first.toSelection.toRange, text: args.text)]
      asyncCheck self.client.notifyTextDocumentChangedChannel.send (args.document.fullPath, args.document.version, changes, "")

  let textDeletedHandle = document.textDeleted.subscribe proc(args: auto): void =
    # debugf"TEXT DELETED {args.document.fullPath}: {args.location}"
    if self.fullDocumentSync:
      asyncCheck self.client.notifyTextDocumentChangedChannel.send (args.document.fullPath, args.document.version, @[], args.document.contentString)
      discard
    else:
      let changes = @[TextDocumentContentChangeEvent(`range`: args.location.toRange)]
      asyncCheck self.client.notifyTextDocumentChangedChannel.send (args.document.fullPath, args.document.version, changes, "")

  self.documentHandles.add (document.Document, textInsertedHandle, textDeletedHandle)

method disconnect*(self: LanguageServerLSP, document: Document) =
  if not (document of TextDocument):
    return

  let document = document.TextDocument

  log lvlInfo, fmt"Disconnecting document '{document.filename}'"

  for i, d in self.documentHandles:
    if d.document != document:
      continue

    document.textInserted.unsubscribe d.textInserted
    document.textDeleted.unsubscribe d.textDeleted
    self.documentHandles.removeSwap i
    break

  # asyncCheck self.client.notifyClosedTextDocument(document.fullPath)
  asyncCheck self.client.notifyTextDocumentClosedChannel.send(document.fullPath)

  if self.documentHandles.len == 0:
    self.stop()

    for (language, ls) in languageServers.pairs:
      if ls == self:
        log lvlInfo, &"Removed language server for '{language}' from global language server list"
        languageServers.del language
        break
