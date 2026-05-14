#use lisp
import language_server
import config_provider

const currentSourcePath2 = currentSourcePath()
include module_base

declareSettings LspMergeSettings, "lsp-merge":
  ## Timeout for LSP requests in milliseconds
  declare timeout, int, 10000

type
  LanguageServerList* = ref object of LanguageServer
    config: ConfigStore
    mergeConfig: LspMergeSettings
    languageServers*: seq[LanguageServer]
    timeout: int

{.push modrtl, gcsafe, raises: [].}
proc newLanguageServerList*(config: ConfigStore): LanguageServerList
proc lspListAddLanguageServer(self: LanguageServerList, languageServer: LanguageServer): bool
proc lspListRemoveLanguageServer(self: LanguageServerList, languageServer: LanguageServer): bool
proc lspListHasLanguageServer(self: LanguageServerList, languageServer: LanguageServer): bool
{.pop.}

proc addLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool = lspListAddLanguageServer(self, languageServer)
proc removeLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool = lspListRemoveLanguageServer(self, languageServer)
proc hasLanguageServer*(self: LanguageServerList, languageServer: LanguageServer): bool = lspListHasLanguageServer(self, languageServer)

when implModule:
  import std/[options, tables, json, sequtils, algorithm, sugar]
  import misc/[custom_logger, custom_async, util, response, event]
  import nimsumtree/rope
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import document

  logCategory "language-server-list"

  proc updateRefetchWorkspaceSymbolsOnQueryChange*(self: LanguageServerList) =
    self.refetchWorkspaceSymbolsOnQueryChange = false
    for ls in self.languageServers:
      if ls.refetchWorkspaceSymbolsOnQueryChange:
        self.refetchWorkspaceSymbolsOnQueryChange = true
        break

  proc lspListAddLanguageServer(self: LanguageServerList, languageServer: LanguageServer): bool =
    if languageServer in self.languageServers:
      return false

    proc configPriority(languageServer: LanguageServer): int =
      return self.config.get("lsp." & languageServer.name & ".priority", 0)

    self.languageServers.add(languageServer)
    self.languageServers.sort((a, b) => cmp(configPriority(b), configPriority(a)))
    self.updateRefetchWorkspaceSymbolsOnQueryChange()
    return true

  proc lspListRemoveLanguageServer(self: LanguageServerList, languageServer: LanguageServer): bool =
    let index = self.languageServers.find(languageServer)
    if index != -1:
      self.languageServers.removeShift(index)
      self.updateRefetchWorkspaceSymbolsOnQueryChange()
      return true
    return false

  proc lspListHasLanguageServer(self: LanguageServerList, languageServer: LanguageServer): bool =
    return self.languageServers.find(languageServer) != -1

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

  proc lslConnect(self: LanguageServer, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerList
    for ls in self.languageServers:
      ls.connect(document)

  proc lslDisconnect(self: LanguageServer, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerList
    for ls in self.languageServers:
      ls.disconnect(document)

  proc lslGetDefinition(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Definition, ls.getDefinition(filename, location), "getDefinition")

  proc lslGetDeclaration(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Definition, ls.getDeclaration(filename, location), "getDeclaration")

  proc lslGetImplementation(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Definition, ls.getImplementation(filename, location), "getImplementation")

  proc lslGetTypeDefinition(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Definition, ls.getTypeDefinition(filename, location), "getTypeDefinition")

  proc lslGetReferences(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Definition, ls.getReferences(filename, location), "getReferences")

  proc lslSwitchSourceHeader(self: LanguageServer, filename: string): Future[Option[string]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeOption(string, ls.switchSourceHeader(filename), "switchSourceHeader")

  proc lslGetCompletions(self: LanguageServer, filename: string, location: Cursor): Future[Response[language_server.CompletionList]] {.async.} =
    try:
      let self = self.LanguageServerList
      let timeout = self.mergeConfig.timeout.get()
      var futs = newSeq[Future[Response[language_server.CompletionList]]]()
      var futsTimeout = newSeq[Future[bool]]()
      for ls in self.languageServers:
        let fut = ls.getCompletions(filename, location)
        futs.add fut
        futsTimeout.add fut.withTimeout(timeout.milliseconds)

      await allFutures(futsTimeout)

      var items: seq[language_server.CompletionItem]
      var isIncomplete = false
      for fut in futs:
        if fut.completed:
          let r = fut.read()
          if r.isSuccess:
            items.add r.result.items
            if r.result.isIncomplete:
              isIncomplete = true

      return success(language_server.CompletionList(isIncomplete: isIncomplete, items: items))
    except CatchableError as e:
      return errorResponse[language_server.CompletionList](500, e.msg)

  proc lslGetSymbols(self: LanguageServer, filename: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Symbol, ls.getSymbols(filename), "getSymbols")

  proc lslGetWorkspaceSymbols(self: LanguageServer, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(Symbol, ls.getWorkspaceSymbols(filename, query), "getWorkspaceSymbols")

  proc lslGetWorkspaceSymbolsRaw(self: LanguageServer, filename: string, query: string): Future[seq[language_server.WorkspaceSymbolRaw]] {.async.} =
    let self = self.LanguageServerList
    return self.merge(language_server.WorkspaceSymbolRaw, ls.getWorkspaceSymbolsRaw(filename, query), "getWorkspaceSymbolsRaw")

  proc lslResolveWorkspaceSymbol(self: LanguageServer, symbol: language_server.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeOption(Definition, ls.resolveWorkspaceSymbol(symbol), "resolveWorkspaceSymbol")

  proc lslGetHover(self: LanguageServer, filename: string, location: Cursor): Future[Option[string]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeOption(string, ls.getHover(filename, location), "getHover")

  proc lslGetSignatureHelp(self: LanguageServer, filename: string, location: Cursor): Future[Response[seq[language_server.SignatureHelpResponse]]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeResponse(language_server.SignatureHelpResponse, ls.getSignatureHelp(filename, location), "getSignatureHelp")

  proc lslGetInlayHints(self: LanguageServer, filename: string, selection: Selection): Future[Response[seq[language_server.InlayHint]]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeResponse(language_server.InlayHint, ls.getInlayHints(filename, selection), "getInlayHints")

  proc lslGetDiagnostics(self: LanguageServer, filename: string): Future[Response[seq[language_server.LspDiagnostic]]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeResponse(language_server.LspDiagnostic, ls.getDiagnostics(filename), "getDiagnostics")

  proc lslGetCompletionTriggerChars(self: LanguageServer): set[char] {.gcsafe, raises: [].} =
    let self = self.LanguageServerList
    for ls in self.languageServers:
      result.incl ls.getCompletionTriggerChars()

  proc lslGetCodeActions(self: LanguageServer, filename: string, selection: Selection, diagnostics: seq[language_server.LspDiagnostic]): Future[Response[language_server.CodeActionResponse]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeResponse(language_server.CodeActionResponseVariant, ls.getCodeActions(filename, selection, diagnostics), "getCodeActions")

  proc lslRename(self: LanguageServer, filename: string, position: Cursor, newName: string): Future[Response[seq[language_server.WorkspaceEdit]]] {.async.} =
    let self = self.LanguageServerList
    return self.mergeResponse(language_server.WorkspaceEdit, ls.rename(filename, position, newName), "rename")

  proc lslExecuteCommand(self: LanguageServer, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
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
