import std/[options, tables, json, sequtils, algorithm, sugar]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response, event]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import document, config_provider, language_server_dynamic

export language_server_dynamic

logCategory "language-server-list"

declareSettings LspMergeSettings, "lsp-merge":
  ## Timeout for LSP requests in milliseconds
  declare timeout, int, 10000

type
  # todo
  MergeStrategy* = enum First, All, FirstThenTimeout, AnyThenTimeout
  LanguageServerList* = ref object of LanguageServerDynamic
    config: ConfigStore
    mergeConfig: LspMergeSettings
    languageServers*: seq[LanguageServerDynamic]
    timeout: int

proc updateRefetchWorkspaceSymbolsOnQueryChange*(self: LanguageServerList) =
  self.refetchWorkspaceSymbolsOnQueryChange = false
  for ls in self.languageServers:
    if ls.refetchWorkspaceSymbolsOnQueryChange:
      self.refetchWorkspaceSymbolsOnQueryChange = true
      break

proc addLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool =
  if not (languageServer of LanguageServerDynamic):
    return false
  let languageServer = languageServer.LanguageServerDynamic
  if languageServer in self.languageServers:
    return false

  proc configPriority(languageServer: LanguageServer): int =
    return self.config.get("lsp." & languageServer.name & ".priority", 0)

  self.languageServers.add(languageServer)
  self.languageServers.sort((a, b) => cmp(configPriority(b), configPriority(a)))
  self.updateRefetchWorkspaceSymbolsOnQueryChange()
  return true

proc removeLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool =
  if not (languageServer of LanguageServerDynamic):
    return false
  let languageServer = languageServer.LanguageServerDynamic
  let index = self.languageServers.find(languageServer)
  if index != -1:
    self.languageServers.removeShift(index)
    self.updateRefetchWorkspaceSymbolsOnQueryChange()
    return true
  return false

template merge(self: LanguageServerList, T: untyped, subCall: untyped, name: untyped): untyped =
  try:
    let timeout = self.mergeConfig.timeout.get()
    var futs = newSeq[Future[seq[T]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for lss in self.languageServers:
      let ls {.inject.} = lss
      let fut = subCall
      futs.add fut
      futsTimeout.add fut.withTimeout(timeout.milliseconds)

    await allFutures(futsTimeout)

    var total: int = 0
    for fut in futs:
      if fut.completed:
        total += fut.read().len
    var res = newSeqOfCap[T](total)
    for fut in futs:
      if fut.completed:
        res.add fut.read()

    res
  except CatchableError:
    newSeq[T]()

template mergeOption(self: LanguageServerList, T: untyped, subCall: untyped, name: untyped): untyped =
  try:
    let timeout = self.mergeConfig.timeout.get()
    var futs = newSeq[Future[Option[T]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for lss in self.languageServers:
      let ls {.inject.} = lss
      let fut = subCall
      futs.add fut
      futsTimeout.add fut.withTimeout(timeout.milliseconds)

    await allFutures(futsTimeout)

    var res = T.none
    for fut in futs:
      if fut.completed:
        let r = fut.read()
        if r.isSome:
          res = r

    res
  except CatchableError:
    T.none

template mergeResponse(self: LanguageServerList, T: untyped, subCall: untyped, name: untyped): untyped =
  try:
    let timeout = self.mergeConfig.timeout.get()
    var futs = newSeq[Future[Response[seq[T]]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for lss in self.languageServers:
      let ls {.inject.} = lss
      let fut = subCall
      futs.add fut
      futsTimeout.add fut.withTimeout(timeout.milliseconds)

    await allFutures(futsTimeout)

    var res = newSeq[T]()
    for fut in futs:
      if fut.completed:
        let r = fut.read()
        if r.isSuccess:
          res.add r.result

    res.success
  except CatchableError as e:
    errorResponse[seq[T]](500, e.msg)

proc lslConnect(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
  let self = self.LanguageServerList
  for ls in self.languageServers:
    ls.connect(document)

proc lslDisconnect(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
  let self = self.LanguageServerList
  for ls in self.languageServers:
    ls.disconnect(document)

proc lslGetDefinition(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Definition, ls.getDefinition(filename, location), "getDefinition")

proc lslGetDeclaration(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Definition, ls.getDeclaration(filename, location), "getDeclaration")

proc lslGetImplementation(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Definition, ls.getImplementation(filename, location), "getImplementation")

proc lslGetTypeDefinition(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Definition, ls.getTypeDefinition(filename, location), "getTypeDefinition")

proc lslGetReferences(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Definition, ls.getReferences(filename, location), "getReferences")

proc lslSwitchSourceHeader(self: LanguageServerDynamic, filename: string): Future[Option[string]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeOption(string, ls.switchSourceHeader(filename), "switchSourceHeader")

proc lslGetCompletions(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
  try:
    let self = self.LanguageServerList
    let timeout = self.mergeConfig.timeout.get()
    var futs = newSeq[Future[Response[lsp_types.CompletionList]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for ls in self.languageServers:
      let fut = ls.getCompletions(filename, location)
      futs.add fut
      futsTimeout.add fut.withTimeout(timeout.milliseconds)

    await allFutures(futsTimeout)

    var items: seq[lsp_types.CompletionItem]
    var isIncomplete = false
    for fut in futs:
      if fut.completed:
        let r = fut.read()
        if r.isSuccess:
          items.add r.result.items
          if r.result.isIncomplete:
            isIncomplete = true

    return success(lsp_types.CompletionList(isIncomplete: isIncomplete, items: items))
  except CatchableError as e:
    return errorResponse[lsp_types.CompletionList](500, e.msg)

proc lslGetSymbols(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Symbol, ls.getSymbols(filename), "getSymbols")

proc lslGetWorkspaceSymbols(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(Symbol, ls.getWorkspaceSymbols(filename, query), "getWorkspaceSymbols")

proc lslGetWorkspaceSymbolsRaw(self: LanguageServerDynamic, filename: string, query: string): Future[seq[language_server_base.WorkspaceSymbolRaw]] {.async.} =
  let self = self.LanguageServerList
  return self.merge(language_server_base.WorkspaceSymbolRaw, ls.getWorkspaceSymbolsRaw(filename, query), "getWorkspaceSymbolsRaw")

proc lslResolveWorkspaceSymbol(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeOption(Definition, ls.resolveWorkspaceSymbol(symbol), "resolveWorkspaceSymbol")

proc lslGetHover(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeOption(string, ls.getHover(filename, location), "getHover")

proc lslGetSignatureHelp(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeResponse(lsp_types.SignatureHelpResponse, ls.getSignatureHelp(filename, location), "getSignatureHelp")

proc lslGetInlayHints(self: LanguageServerDynamic, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeResponse(language_server_base.InlayHint, ls.getInlayHints(filename, selection), "getInlayHints")

proc lslGetDiagnostics(self: LanguageServerDynamic, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeResponse(lsp_types.Diagnostic, ls.getDiagnostics(filename), "getDiagnostics")

proc lslGetCompletionTriggerChars(self: LanguageServerDynamic): set[char] {.gcsafe, raises: [].} =
  let self = self.LanguageServerList
  for ls in self.languageServers:
    result.incl ls.getCompletionTriggerChars()

proc lslGetCodeActions(self: LanguageServerDynamic, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeResponse(lsp_types.CodeActionResponseVariant, ls.getCodeActions(filename, selection, diagnostics), "getCodeActions")

proc lslRename(self: LanguageServerDynamic, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
  let self = self.LanguageServerList
  return self.mergeResponse(lsp_types.WorkspaceEdit, ls.rename(filename, position, newName), "rename")

proc lslExecuteCommand(self: LanguageServerDynamic, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
  try:
    let self = self.LanguageServerList
    let timeout = self.mergeConfig.timeout.get()
    var futs = newSeq[Future[Response[JsonNode]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for ls in self.languageServers:
      if ls.capabilities.executeCommandProvider.isSome and command in ls.capabilities.executeCommandProvider.get.commands:
        let fut = ls.executeCommand(command, arguments)
        futs.add fut
        futsTimeout.add fut.withTimeout(timeout.milliseconds)

    var res = errorResponse[JsonNode](0, "Command not found: " & command)

    if futs.len > 0:
      await allFutures(futsTimeout)

      for fut in futs:
        if fut.completed:
          res = fut.read()
          if res.isSuccess:
            return res

    return res
  except CatchableError as e:
    return errorResponse[JsonNode](500, e.msg)

proc newLanguageServerList*(config: ConfigStore): LanguageServerList =
  var server = new LanguageServerList
  server.config = config
  server.mergeConfig = LspMergeSettings.new(server.config)
  server.connectImpl = lslConnect
  server.disconnectImpl = lslDisconnect
  server.getDefinitionImpl = lslGetDefinition
  server.getDeclarationImpl = lslGetDeclaration
  server.getImplementationImpl = lslGetImplementation
  server.getTypeDefinitionImpl = lslGetTypeDefinition
  server.getReferencesImpl = lslGetReferences
  server.switchSourceHeaderImpl = lslSwitchSourceHeader
  server.getCompletionsImpl = lslGetCompletions
  server.getSymbolsImpl = lslGetSymbols
  server.getWorkspaceSymbolsImpl = lslGetWorkspaceSymbols
  server.getWorkspaceSymbolsRawImpl = lslGetWorkspaceSymbolsRaw
  server.resolveWorkspaceSymbolImpl = lslResolveWorkspaceSymbol
  server.getHoverImpl = lslGetHover
  server.getSignatureHelpImpl = lslGetSignatureHelp
  server.getInlayHintsImpl = lslGetInlayHints
  server.getDiagnosticsImpl = lslGetDiagnostics
  server.getCompletionTriggerCharsImpl = lslGetCompletionTriggerChars
  server.getCodeActionsImpl = lslGetCodeActions
  server.renameImpl = lslRename
  server.executeCommandImpl = lslExecuteCommand
  return server
