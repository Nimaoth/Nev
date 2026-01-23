import std/[strformat, strutils, os, sets, tables, options, json, sequtils, uri]
import misc/[delayed_task, id, custom_logger, util, custom_async, timer, async_process, event, response, rope_utils, arena, array_view, jsonex, myjsonutils]
import text/language/[language_server_base, lsp_types]
import nimsumtree/[arc, rope, buffer]
import service, event_service, language_server_dynamic, document_editor, document, config_provider, vfs, vfs_service
import text/[treesitter_type_conv]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import workspaces/workspace as ws
import lsp_client

# import std/[typedthreads]
# import misc/[custom_unicode, id, jsonex]

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import language_server_component, config_component, move_component, text_component, treesitter_component, language_component

  logCategory "language-server-lsp"

  type
    LanguageServerLSP* = ref object of LanguageServerDynamic
      client: LSPClient
      initializedFuture: Future[bool]

      documentHandles: seq[tuple[document: Document, onEditHandle: Id]]

      thread: Thread[LSPClient]
      serverCapabilities*: ServerCapabilities
      fullDocumentSync: bool = false

      vfs: VFS
      localVfs: VFS

    LanguageServerLspService* = ref object of DynamicService
      documents: DocumentEditorService
      workspace: Workspace
      config: ConfigService
      languageServers: Table[string, LanguageServerLSP]
      languageServersPerDocument*: Table[DocumentId, seq[LanguageServerLSP]]
      languageChangedHandles*: Table[DocumentId, Id]

  func serviceName*(_: typedesc[LanguageServerLspService]): string = "LanguageServerLspService"

  proc getOrCreateLanguageServerLSP*(self: LanguageServerLspService, name: string): Future[Option[LanguageServerLSP]] {.async.}

  proc updateLanguageServersForDocument(self: LanguageServerLspService, doc: Document) {.async.} =
    # log lvlWarn, &"updateLanguageServersForDocument {doc.filename}"
    let lsComp = doc.getLanguageServerComponent().getOr:
      return
    let language = doc.getLanguageComponent().getOr:
      return

    if self.languageServersPerDocument.contains(doc.id):
      for ls in self.languageServersPerDocument[doc.id]:
        discard lsComp.removeLanguageServer(ls)
      self.languageServersPerDocument.del(doc.id)

    let languageId = language.languageId
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

        if config.hasKey("enabled"):
          let enabled = config["enabled"]
          if enabled.kind == JBool and enabled.getBool == false:
            continue

        if not config.hasKey("command"):
          continue

        type LspConfig = object
          languages: seq[string]

        let lspConfig = config.jsonTo(LspConfig, Joptions(allowExtraKeys: true, allowMissingKeys: false))
        if languageId in lspConfig.languages or "*" in lspConfig.languages:
          let ls = self.getOrCreateLanguageServerLSP(name).await
          if ls.isSome:
            languageServers.add(ls.get)
      except:
        discard

    if not doc.isInitialized or language.languageId != languageId:
      return

    var languageServersAdded = newSeq[LanguageServerLSP]()
    for ls in languageServers:
      if lsComp.addLanguageServer(ls):
        languageServersAdded.add(ls)

    if languageServersAdded.len > 0:
      self.languageServersPerDocument[doc.id] = languageServersAdded

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
    discard

    # todo: nice error messages when failing
    # todo
    # if applyWorkspaceEdit(nil, nil, params.edit).await:
    #   return lsp_types.ApplyWorkspaceEditResponse(
    #     applied: true,
    #   )
    # else:
    #   return lsp_types.ApplyWorkspaceEditResponse(
    #     applied: false,
    #     failureReason: "Internal error".some,
    #   )

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

  method start*(self: LanguageServerLSP): Future[void] = discard
  method stop*(self: LanguageServerLSP) {.gcsafe, raises: [].} =
    log lvlInfo, fmt"[{self.name}] Stopping language server for '{self.name}'"
    asyncSpawn self.client.stop()
    self.client = nil

  proc toVfsPath*(self: LanguageServerLSP, lspPath: string): string =
    let localPath = lspPath.decodeUrl.parseUri.path.normalizePathUnix
    return self.localVfs.normalize(localPath)

  proc lspGetCompletionTriggerChars*(self: LanguageServerDynamic): set[char] =
    let self = self.LanguageServerLSP
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
  proc lspGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerLSP
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
  proc lspGetDeclaration*(self: LanguageServerDynamic, filename: string, location: Cursor):
      Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerLSP

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
  proc lspGetTypeDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor):
      Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerLSP

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
  proc lspGetImplementation*(self: LanguageServerDynamic, filename: string, location: Cursor):
      Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerLSP

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
  proc lspGetReferences*(self: LanguageServerDynamic, filename: string, location: Cursor):
      Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerLSP

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

  proc lspSwitchSourceHeader*(self: LanguageServerDynamic, filename: string): Future[Option[string]] {.async.} =
    let self = self.LanguageServerLSP
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
  proc lspGetHover*(self: LanguageServerDynamic, filename: string, location: Cursor):
      Future[Option[string]] {.async.} =
    let self = self.LanguageServerLSP

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
        if markedString.asString().getSome(str) and str.len > 0:
          return str.some
        if markedString.asMarkedStringObject().getSome(str) and str.value.len > 0:
          # todo: language
          return str.value.some

      return string.none

    if parsedResponse.contents.asMarkupContent().getSome(markupContent) and markupContent.value.len > 0:
      return markupContent.value.some

    if parsedResponse.contents.asMarkedStringVariant().getSome(markedString):
      debugf"marked string variant: {markedString}"

      if markedString.asString().getSome(str) and str.len > 0:
        debugf"string: {str}"
        return str.some

      if markedString.asMarkedStringObject().getSome(str) and str.value.len > 0:
        debugf"string object lang: {str.language}, value: {str.value}"
        return str.value.some

      return string.none

    return string.none

  proc lspGetSignatureHelp*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
    let self = self.LanguageServerLSP

    if self.serverCapabilities.signatureHelpProvider.isNone:
      return success[seq[lsp_types.SignatureHelpResponse]](@[])

    let localizedPath = self.vfs.localize(filename)
    let response = await self.client.getSignatureHelp(localizedPath, location.line, location.column)
    if response.isError:
      log(lvlWarn, &"[{self.name}] Error in getSignatureHelp('{filename}', {location}): {response.error}")
      return response.to(seq[lsp_types.SignatureHelpResponse])

    if response.isCanceled:
      # log(lvlInfo, &"[{self.name}] Canceled inlay hints ({response.id}) for '{filename}':{selection} ")
      return response.to(seq[lsp_types.SignatureHelpResponse])

    let parsedResponse = response.result
    var res = newSeq[lsp_types.SignatureHelpResponse](1)
    res[0] = parsedResponse
    return success[seq[lsp_types.SignatureHelpResponse]](res)

  proc lspGetInlayHints*(self: LanguageServerDynamic, filename: string, selection: Selection):
      Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
    let self = self.LanguageServerLSP

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
  proc lspGetSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerLSP
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
          filename: self.toVfsPath(r.location.uri),
        )

    return completions

  # todo: change return type to Response
  proc lspGetWorkspaceSymbols*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerLSP
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

  proc lspGetDiagnostics*(self: LanguageServerDynamic, filename: string):
      Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
    let self = self.LanguageServerLSP
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

  proc lspGetCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor):
      Future[Response[CompletionList]] {.async.} =
    let self = self.LanguageServerLSP
    if self.serverCapabilities.completionProvider.isNone:
      return success(CompletionList())
    let localizedPath = self.vfs.localize(filename)
    return await self.client.getCompletions(localizedPath, location.line, location.column)

  proc lspGetCodeActions*(self: LanguageServerDynamic, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]):
      Future[Response[lsp_types.CodeActionResponse]] {.async.} =
    let self = self.LanguageServerLSP
    if self.serverCapabilities.codeActionProvider.isNone:
      return success(lsp_types.CodeActionResponse.default)
    let localizedPath = self.vfs.localize(filename)
    return await self.client.getCodeActions(localizedPath, selection, diagnostics)

  proc lspRename*(self: LanguageServerDynamic, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
    let self = self.LanguageServerLSP
    let localizedPath = self.vfs.localize(filename)
    let res = await self.client.rename(localizedPath, position, newName)
    if res.isSuccess and res.result.getSome(edit):
      return success(@[edit])
    return res.to(seq[lsp_types.WorkspaceEdit])

  proc lspExecuteCommand*(self: LanguageServerDynamic, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
    let self = self.LanguageServerLSP
    return await self.client.executeCommand(command, arguments)

  proc lspConnect*(self: LanguageServerDynamic, document: Document) =
    let self = self.LanguageServerLSP
    log lvlInfo, fmt"[{self.name}] Connecting document (loadingAsync: {document.isLoadingAsync}, requiresLoad: {document.requiresLoad}) '{document.filename}'"
    let text = document.getTextComponent().getOr:
      return
    let language = document.getLanguageComponent().getOr:
      return

    if document.requiresLoad or document.isLoadingAsync:
      var handle = new Id
      handle[] = document.onDocumentLoaded.subscribe proc(document: Document): void =
        document.onDocumentLoaded.unsubscribe handle[]
        asyncSpawn self.client.notifyOpenedTextDocumentMain(language.languageId, document.localizedPath, $text.content)
    else:
      asyncSpawn self.client.notifyOpenedTextDocumentMain(language.languageId, document.localizedPath, $text.content)

    let onEditHandle = text.onEdit.subscribe proc(patch: Patch[Point]): void {.gcsafe, raises: [].} =
      # debugf"TEXT INSERTED {args.document.localizedPath}:{args.location}: {args.text}"
      # todo: we should batch these, as onEdit can be called multiple times per frame
      # especially for full document sync
      let version = text.buffer.history.versions.high
      let localizedPath = document.localizedPath

      if self.fullDocumentSync:
        asyncSpawn self.client.notifyTextDocumentChangedMain(localizedPath, version, $text.content)
      else:
        var c = text.content.cursorT(Point)
        # todo: currently relies on edits being sorted
        let changes = patch.edits.mapIt(block:
          c.seekForward(it.new.a)
          let text = c.slice(it.new.b)
          var oldAdjusted: rope.Range[Point]
          oldAdjusted.a = it.new.a
          oldAdjusted.b = oldAdjusted.a + (it.old.b - it.old.a).toPoint
          TextDocumentContentChangeEvent(range: language_server_base.toLspRange(oldAdjusted.toSelection), text: $text)
        )
        asyncSpawn self.client.notifyTextDocumentChangedMain(localizedPath, version, changes)

    self.documentHandles.add (document.Document, onEditHandle)

  proc lspDisconnect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerLSP
    log lvlInfo, fmt"[{self.name}] Disconnecting document '{document.filename}'"
    let text = document.getTextComponent().getOr:
      return

    for i, d in self.documentHandles:
      if d.document != document:
        continue

      text.onEdit.unsubscribe d.onEditHandle
      self.documentHandles.removeSwap i
      break

    asyncSpawn self.client.notifyClosedTextDocumentMain(document.localizedPath)

    if self.documentHandles.len == 0:
      self.stop()

      if ({.gcsafe.}: gServices) == nil:
        # during shutdown
        return
      let service = ({.gcsafe.}: gServices.getService(LanguageServerLspService).get)
      for (language, ls) in service.languageServers.pairs:
        if ls == self:
          log lvlInfo, &"[{self.name}] Removed language server for '{language}' from global language server list"
          service.languageServers.del language
          break

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
      if command.len == 0:
        log lvlError, &"Empty command in config for language server '{name}'"
        return LanguageServerLSP.none

      let initializationOptionsName = config.fields.getOrDefault("initialization-options-name", newJexNull()).jsonTo(string).catch("settings")
      let userOptions = config.fields.getOrDefault(initializationOptionsName, newJexNull()).toJson

      let workspaceInfo = self.workspace.info.some
      let killOnExit = config.fields.getOrDefault("kill-on-exit", newJexBool(true)).jsonTo(bool).catch(true)

      let exePath = command[0]
      var args = newSeq[string]()
      if command.len > 1:
        args = command[1..^1]

      let workspaces = @[self.workspace.getWorkspacePath()]
      var client = newLSPClient(workspaceInfo, userOptions, exePath, workspaces, args, killOnExit)
      client.name = name

      var lsp = LanguageServerLSP(client: client, name: name)
      lsp.getCompletionTriggerCharsImpl = lspGetCompletionTriggerChars
      lsp.getDefinitionImpl = lspGetDefinition
      lsp.getDeclarationImpl = lspGetDeclaration
      lsp.getTypeDefinitionImpl = lspGetTypeDefinition
      lsp.getImplementationImpl = lspGetImplementation
      lsp.getReferencesImpl = lspGetReferences
      lsp.switchSourceHeaderImpl = lspSwitchSourceHeader
      lsp.getHoverImpl = lspGetHover
      lsp.getSignatureHelpImpl = lspGetSignatureHelp
      lsp.getInlayHintsImpl = lspGetInlayHints
      lsp.getSymbolsImpl = lspGetSymbols
      lsp.getWorkspaceSymbolsImpl = lspGetWorkspaceSymbols
      lsp.getDiagnosticsImpl = lspGetDiagnostics
      lsp.getCompletionsImpl = lspGetCompletions
      lsp.getCodeActionsImpl = lspGetCodeActions
      lsp.renameImpl = lspRename
      lsp.executeCommandImpl = lspExecuteCommand
      lsp.connectImpl = lspConnect
      lsp.disconnectImpl = lspDisconnect

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
      log lvlError, &"Failed to create language server '{name}': {getCurrentExceptionMsg()}"
      return LanguageServerLSP.none

  proc init_module_language_server_lsp*() {.cdecl, exportc, dynlib.} =
    log lvlWarn, &"init_module_language_server_lsp"
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_language_server_lsp: no services found"
      return

    let lspService = LanguageServerLspService()
    lspService.documents = services.getService(DocumentEditorService).get
    lspService.workspace = services.getService(Workspace).get
    lspService.config = services.getService(ConfigService).get

    services.addService(lspService)

    let events = services.getService(EventService)
    let documents = services.getService(DocumentEditorService).get

    proc handleEditorRegistered(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.EditorIdNew
        if documents.getEditor(id).getSome(editor):
          let doc = editor.getEditorDocument()
          if doc.id in lspService.languageChangedHandles:
            return
          let language = doc.getLanguageComponent().getOr:
            return

          asyncSpawn lspService.updateLanguageServersForDocument(doc)

          proc handleLanguageChanged(l: LanguageComponent) {.raises: [].} =
            log lvlWarn, &"handleLanguageChanged {doc.filename}"
            asyncSpawn lspService.updateLanguageServersForDocument(doc)
          lspService.languageChangedHandles[doc.id] = language.onLanguageChanged.subscribe(handleLanguageChanged)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"
    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)

  proc shutdown_module_language_server_lsp*() {.cdecl, exportc, dynlib.} =
    log lvlInfo, &"shutdown_module_language_server_lsp"
    let service = getServices().getService(LanguageServerLspService).get
    for languageServer in service.languageServers.values:
      if languageServer.client == nil:
        continue
      languageServer.stop()

    service.languageServers.clear()
