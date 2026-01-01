import std/[options, tables, json, sequtils, algorithm, sugar]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response, event]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import document, config_provider

logCategory "language-server-list"

declareSettings LspMergeSettings, "lsp-merge":
  ## Timeout for LSP requests in milliseconds
  declare timeout, int, 10000

type
  # todo
  MergeStrategy* = enum First, All, FirstThenTimeout, AnyThenTimeout
  LanguageServerList* = ref object of LanguageServer
    config: ConfigStore
    mergeConfig: LspMergeSettings
    languageServers*: seq[LanguageServer]
    timeout: int

proc newLanguageServerList*(config: ConfigStore): LanguageServerList =
  var server = new LanguageServerList
  server.config = config
  server.mergeConfig = LspMergeSettings.new(server.config)
  return server

proc updateRefetchWorkspaceSymbolsOnQueryChange*(self: LanguageServerList) =
  self.refetchWorkspaceSymbolsOnQueryChange = false
  for ls in self.languageServers:
    if ls.refetchWorkspaceSymbolsOnQueryChange:
      self.refetchWorkspaceSymbolsOnQueryChange = true
      break

proc addLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool =
  if languageServer in self.languageServers:
    return false

  proc configPriority(languageServer: LanguageServer): int =
    return self.config.get("lsp." & languageServer.name & ".priority", 0)

  self.languageServers.add(languageServer)
  self.languageServers.sort((a, b) => cmp(configPriority(b), configPriority(a)))
  self.updateRefetchWorkspaceSymbolsOnQueryChange()
  return true

proc removeLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool =
  let index = self.languageServers.find(languageServer)
  if index != -1:
    self.languageServers.removeShift(index)
    return true
  self.updateRefetchWorkspaceSymbolsOnQueryChange()
  return false

template merge(self: LanguageServerList, T: untyped, subCall: untyped, name: untyped): untyped =
  block:
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

template mergeOption(self: LanguageServerList, T: untyped, subCall: untyped, name: untyped): untyped =
  block:
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

template mergeResponse(self: LanguageServerList, T: untyped, subCall: untyped, name: untyped): untyped =
  block:
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

method connect*(self: LanguageServerList, document: Document) {.gcsafe, raises: [].} =
  for ls in self.languageServers:
    ls.connect(document)

method disconnect*(self: LanguageServerList, document: Document) {.gcsafe, raises: [].} =
  for ls in self.languageServers:
    ls.disconnect(document)

method getDefinition*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return self.merge(Definition, ls.getDefinition(filename, location), "getDefinition")

method getDeclaration*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return self.merge(Definition, ls.getDeclaration(filename, location), "getDeclaration")

method getImplementation*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return self.merge(Definition, ls.getImplementation(filename, location), "getImplementation")

method getTypeDefinition*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return self.merge(Definition, ls.getTypeDefinition(filename, location), "getTypeDefinition")

method getReferences*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return self.merge(Definition, ls.getReferences(filename, location), "getReferences")

method switchSourceHeader*(self: LanguageServerList, filename: string): Future[Option[string]] {.async.} =
  return self.mergeOption(string, ls.switchSourceHeader(filename), "switchSourceHeader")

method getCompletions*(self: LanguageServerList, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
  # completions are handled by the completion provider as separate providers, so no need to implement this right now
  discard

method getSymbols*(self: LanguageServerList, filename: string): Future[seq[Symbol]] {.async.} =
  return self.merge(Symbol, ls.getSymbols(filename), "getSymbols")

method getWorkspaceSymbols*(self: LanguageServerList, filename: string, query: string): Future[seq[Symbol]] {.async.} =
  return self.merge(Symbol, ls.getWorkspaceSymbols(filename, query), "getWorkspaceSymbols")

method getHover*(self: LanguageServerList, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  return self.mergeOption(string, ls.getHover(filename, location), "getHover")

method getSignatureHelp*(self: LanguageServerList, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
  return self.mergeResponse(lsp_types.SignatureHelpResponse, ls.getSignatureHelp(filename, location), "getSignatureHelp")

method getInlayHints*(self: LanguageServerList, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
  return self.mergeResponse(language_server_base.InlayHint, ls.getInlayHints(filename, selection), "getInlayHints")

method getDiagnostics*(self: LanguageServerList, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  return self.mergeResponse(lsp_types.Diagnostic, ls.getDiagnostics(filename), "getDiagnostics")

method getCompletionTriggerChars*(self: LanguageServerList): set[char] =
  for ls in self.languageServers:
    result.incl ls.getCompletionTriggerChars()

method getCodeActions*(self: LanguageServerList, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async.} =
  return self.mergeResponse(lsp_types.CodeActionResponseVariant, ls.getCodeActions(filename, selection, diagnostics), "getCodeActions")

method rename*(self: LanguageServerList, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
  return self.mergeResponse(lsp_types.WorkspaceEdit, ls.rename(filename, position, newName), "rename")

method executeCommand*(self: LanguageServerList, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
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
