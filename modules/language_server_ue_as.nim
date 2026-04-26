#use language_server_lsp language_server_regex

# language_server_ue_as: Unreal Engine AngelScript language server module.
#
# Wraps angel-lsp (AngelScript LSP) as the primary backend, with clangd as a
# fallback for cross-language symbol lookup from .as files into C++ code.
#
# Features:
#   - Go to definition: tries angel-lsp first; falls back to clangd workspace symbol search
#     (filtered to exclude .generated.h / .gen.cpp) when angel-lsp returns no results
#   - Workspace symbols: merged from angel-lsp (primary) + clangd (secondary),
#     with clangd results filtered for generated files; raw and resolved forms
#   - Symbol resolution: routes to angel-lsp for .as files, clangd otherwise

const currentSourcePath2 = currentSourcePath()
include module_base

when defined(appLspUeAs):
  import language_server_dynamic

  proc getLanguageServerUEAs*(): LanguageServerDynamic {.rtl, gcsafe, raises: [].}

else:
  static:
    echo "DONT build lsp ue as"

when implModule and defined(appLspUeAs):
  import std/[options, json, strutils]
  import nimsumtree/[arc, rope]
  import misc/[custom_logger, util, event, custom_async, response, rope_utils, jsonex]
  import text/language/[language_server_base, lsp_types]
  import service, event_service, document_editor, config_provider
  import language_server_lsp/language_server_lsp, language_server_regex
  import workspaces/workspace
  import vfs, vfs_service
  import document, language_server_component, config_component, language_component, move_component, text_component
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  logCategory "language-server-ue-as"

  type
    LanguageServerUEAs* = ref object of LanguageServerDynamic
      services: Services
      config: ConfigStore
      documents: DocumentEditorService
      eventBus: EventService
      angelLsDiagnosticsHandle: Id
      clangd: LanguageServerDynamic
      angelLs: LanguageServerDynamic
      regexLs: LanguageServerRegex
      vfs*: Arc[VFS2]
      workspace*: Workspace

  proc getClangd(self: LanguageServerDynamic): Future[Option[LanguageServerDynamic]] {.async.} =
    let self = self.LanguageServerUEAs
    result = await getOrCreateLanguageServerLSP("clangd")
    if result.isSome and result.get != self.clangd:
      self.clangd = result.get

  proc getAngelLs(self: LanguageServerDynamic): Future[Option[LanguageServerDynamic]] {.async.} =
    let self = self.LanguageServerUEAs
    result = await getOrCreateLanguageServerLSP("angel-lsp")
    if result.isSome and result.get != self.angelLs:
      self.angelLs = result.get
      if self.angelLs != nil:
        self.angelLs.onDiagnostics.unsubscribe(self.angelLsDiagnosticsHandle)
      self.angelLs = result.get
      self.angelLsDiagnosticsHandle = self.angelLs.onDiagnostics.subscribe proc(params: lsp_types.PublicDiagnosticsParams) =
        self.onDiagnostics.invoke params

  proc symbolNameMatches(symbolName: string, wordText: string): bool =
    let baseName = symbolName.split('(')[0].replace("::", ".")
    for part in baseName.split('.'):
      if part == wordText:
        return true
    return false

  proc getDefinitionCpp*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerUEAs
    let clangd = (await self.getClangd()).getOr: return @[]

    let doc = self.documents.getDocumentByPath(filename).getOr:
      return @[]
    let moves = doc.getMoveComponent().getOr:
      return @[]
    let text = doc.getTextComponent().getOr:
      return @[]

    let wordRange = moves.applyMove(location.toSelection.toRange, "language-word")
    let wordText = text.content(wordRange)
    if wordText.len == 0:
      return @[]

    let symbols = await clangd.getWorkspaceSymbolsRaw(filename, wordText)

    var res: seq[Definition]
    for sym in symbols:
      if sym.path.endsWith(".generated.h") or sym.path.endsWith(".gen.cpp"):
        continue
      if sym.symbol.name.symbolNameMatches(wordText):
        if sym.symbol.location.asUriObject().isSome:
          let resolved = await clangd.resolveWorkspaceSymbol(sym.symbol)
          if resolved.getSome(d):
            res.add d
        elif sym.location.getSome(loc):
          res.add Definition(location: loc, filename: sym.path)
        else:
          res.add Definition(filename: sym.path)
    return res

  proc getDefinitionCppRegex*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    ## Searches C++ header files in the workspace for declarations matching the
    ## word under the cursor. Uses different regexes depending on the kind of
    ## symbol: function, type/class, or field/variable.
    let self = self.LanguageServerUEAs

    let doc = self.documents.getDocumentByPath(filename).getOr:
      return @[]
    let moves = doc.getMoveComponent().getOr:
      return @[]
    let text = doc.getTextComponent().getOr:
      return @[]
    let config = doc.getConfigComponent().getOr:
      return @[]

    let wordRange = moves.applyMove(location.toSelection.toRange, "language-word")
    let wordText = text.content(wordRange)
    if wordText.len == 0:
      return @[]

    let nextChar = text.content(wordRange.b...wordRange.b, inclusiveEnd = true)
    let prevCharCursor = if wordRange.a.column > 0: point(wordRange.a.row, wordRange.a.column - 1) else: wordRange.a
    let prevChar = text.content(prevCharCursor...prevCharCursor, inclusiveEnd = true)
    let isType = wordText.len >= 2 and wordText[0].isUpperAscii and wordText[1].isUpperAscii and wordText[0] in {'F', 'T', 'U', 'A', 'E', 'I'}

    let regexTemplate = if nextChar == "(":
      config.get("lsp.ue-as.definition-cpp-regex-function", newJexString(r"\b[[0]]\b\s*\("))
    elif isType:
      config.get("lsp.ue-as.definition-cpp-regex-type", newJexString(r"^(class|struct|enum class|enum)\s+(\w+_API\s+)?\b[[0]]\b"))
    elif prevChar == ":":
      config.get("lsp.ue-as.definition-cpp-regex-enum-value", newJexString(r"\b[[0]]\b"))
    else:
      config.get("lsp.ue-as.definition-cpp-regex-field", newJexString(r"\b[[0]]\b\s*[;=({]"))

    let searchString = regexTemplate.decodeRegex("").replace("[[0]]", wordText)

    let cppPath = self.vfs.localize("ws0://")
    let enginePath = self.vfs.localize("D:/GlazeEngine/Engine/Source/")
    let searchResults = await self.workspace.search(@[cppPath, enginePath], searchString, 100, @["--glob=*.h"])

    var res: seq[Definition]
    for info in searchResults:
      if info.path.endsWith(".generated.h") or info.path.endsWith(".gen.cpp"):
        continue
      if isType and info.text.strip().endsWith(";"):
        # Looking for a type, skip things which are most likely forward declarations
        continue
      res.add Definition(filename: "local://" // info.path, location: (info.line - 1, info.column - 1))
    return res

  proc ueGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let angelLs = await self.getAngelLs()
    if angelLs.isSome:
      let angelDef = await angelLs.get.getDefinition(filename, location)
      if angelDef.len > 0:
        return angelDef

    return await self.getDefinitionCppRegex(filename, location)
    # let cppFut = self.getDefinitionCpp(filename, location)
    # let regexFut = self.getDefinitionCppRegex(filename, location)
    # await allFutures(cppFut, regexFut)
    # return cppFut.read.catch(@[]) & regexFut.read.catch(@[])

  proc ueGetDeclaration*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getDeclaration(filename, location)

  proc ueGetImplementation*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getImplementation(filename, location)

  proc ueGetTypeDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getTypeDefinition(filename, location)

  proc ueGetReferences*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getReferences(filename, location)

  proc ueSwitchSourceHeader*(self: LanguageServerDynamic, filename: string): Future[Option[string]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return string.none
    return await angelLs.switchSourceHeader(filename)

  proc ueGetCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Response[lsp_types.CompletionList].default
    return await angelLs.getCompletions(filename, location)

  proc ueGetSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getSymbols(filename)

  proc getWorkspaceSymbolsClangd*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    return await clangd.getWorkspaceSymbols(filename, query)

  proc getWorkspaceSymbolsAngelscript*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getWorkspaceSymbols(filename, query)

  proc ueGetWorkspaceSymbols*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let clangdSymbols = self.getWorkspaceSymbolsClangd(filename, query)
    let angelscriptSymbols = self.getWorkspaceSymbolsAngelscript(filename, query)
    return angelscriptSymbols.await & clangdSymbols.await

  proc getWorkspaceSymbolsRawClangd*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[WorkspaceSymbolRaw]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    let res = await clangd.getWorkspaceSymbolsRaw(filename, query)
    result = newSeqOfCap[WorkspaceSymbolRaw](res.len)
    for r in res:
      if r.path.endsWith(".generated.h") or r.path.endsWith(".gen.cpp"):
        continue
      result.add r

  proc getWorkspaceSymbolsRawAngelscript*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[WorkspaceSymbolRaw]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    result = await angelLs.getWorkspaceSymbolsRaw(filename, query)

  proc ueGetWorkspaceSymbolsRaw*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[WorkspaceSymbolRaw]] {.async.} =
    let clangdSymbolsFut = self.getWorkspaceSymbolsRawClangd(filename, query)
    let angelscriptSymbolsFut = self.getWorkspaceSymbolsRawAngelscript(filename, query)
    let clangdSymbols = await clangdSymbolsFut
    let angelscriptSymbols = await angelscriptSymbolsFut
    result = angelscriptSymbols & clangdSymbols

  proc resolveWorkspaceSymbolClangd*(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Definition.none
    return await clangd.resolveWorkspaceSymbol(symbol)

  proc resolveWorkspaceSymbolAngelscript*(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Definition.none
    return await angelLs.resolveWorkspaceSymbol(symbol)

  proc ueResolveWorkspaceSymbol*(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    if symbol.location.asUriObject().getSome(uri) and not uri.uri.endsWith(".as"):
      return await self.resolveWorkspaceSymbolClangd(symbol)
    return await self.resolveWorkspaceSymbolAngelscript(symbol)

  proc ueGetHover*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return string.none
    return await angelLs.getHover(filename, location)

  proc ueGetSignatureHelp*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Response[seq[lsp_types.SignatureHelpResponse]].default
    return await angelLs.getSignatureHelp(filename, location)

  proc ueGetInlayHints*(self: LanguageServerDynamic, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Response[seq[language_server_base.InlayHint]].default
    return await angelLs.getInlayHints(filename, selection)

  proc ueGetDiagnostics*(self: LanguageServerDynamic, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Response[seq[lsp_types.Diagnostic]].default
    return await angelLs.getDiagnostics(filename)

  proc ueGetCompletionTriggerChars*(self: LanguageServerDynamic): set[char] =
    return {'.', '>', ':'}

  proc ueGetCodeActions*(self: LanguageServerDynamic, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Response[lsp_types.CodeActionResponse].default
    return await angelLs.getCodeActions(filename, selection, diagnostics)

  proc ueRename*(self: LanguageServerDynamic, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Response[seq[lsp_types.WorkspaceEdit]].default
    return await angelLs.rename(filename, position, newName)

  proc ueExecuteCommand*(self: LanguageServerDynamic, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return errorResponse[JsonNode](0, "ue-as: no angelLs instance")
    return await angelLs.executeCommand(command, arguments)

  proc ueConnect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerUEAs
    proc doConnect() {.async.} =
      let angelLs = (await self.getAngelLs()).getOr: return
      angelLs.connect(document)
    asyncSpawn doConnect()

  proc ueDisconnect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerUEAs
    proc doDisconnect() {.async.} =
      let angelLs = (await self.getAngelLs()).getOr: return
      angelLs.disconnect(document)
    asyncSpawn doDisconnect()

  proc newLanguageServerClangdUE(services: Services): LanguageServerUEAs =
    result = new LanguageServerUEAs
    result.capabilities.completionProvider = lsp_types.CompletionOptions().some
    result.regexLs = newLanguageServerRegex(services)
    result.name = "ue-as"
    result.services = services
    result.documents = services.getService(DocumentEditorService).get
    result.eventBus = services.getService(EventService).get
    result.config = services.getService(ConfigService).get.runtime
    result.vfs = services.getService(VFSService).get.vfs2
    result.workspace = services.getService(Workspace).get
    result.refetchWorkspaceSymbolsOnQueryChange = true
    result.connectImpl = ueConnect
    result.disconnectImpl = ueDisconnect
    result.getDefinitionImpl = ueGetDefinition
    result.getDeclarationImpl = ueGetDeclaration
    result.getImplementationImpl = ueGetImplementation
    result.getTypeDefinitionImpl = ueGetTypeDefinition
    result.getReferencesImpl = ueGetReferences
    result.switchSourceHeaderImpl = ueSwitchSourceHeader
    result.getCompletionsImpl = ueGetCompletions
    result.getSymbolsImpl = ueGetSymbols
    result.getWorkspaceSymbolsImpl = ueGetWorkspaceSymbols
    result.getWorkspaceSymbolsRawImpl = ueGetWorkspaceSymbolsRaw
    result.resolveWorkspaceSymbolImpl = ueResolveWorkspaceSymbol
    result.getHoverImpl = ueGetHover
    result.getSignatureHelpImpl = ueGetSignatureHelp
    result.getInlayHintsImpl = ueGetInlayHints
    result.getDiagnosticsImpl = ueGetDiagnostics
    result.getCompletionTriggerCharsImpl = ueGetCompletionTriggerChars
    result.getCodeActionsImpl = ueGetCodeActions
    result.renameImpl = ueRename
    result.executeCommandImpl = ueExecuteCommand

  var gls: LanguageServerUEAs = nil

  proc getLanguageServerUEAs*(): LanguageServerDynamic {.gcsafe, raises: [].} =
    {.gcsafe.}:
      return gls

  proc init_module_language_server_ue_as*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize language_server_ue_as: no services found"
      return

    var ls = newLanguageServerClangdUE(services)
    {.gcsafe.}:
      gls = ls

    let events = services.getService(EventService)
    let documents = services.getService(DocumentEditorService).get

    proc handleEditorRegistered(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.EditorIdNew
        if documents.getEditor(id).getSome(editor):
          let doc = editor.getEditorDocument()
          let config = doc.getConfigComponent().getOr:
            return
          let lsps = doc.getLanguageServerComponent().getOr:
            return
          let language = doc.getLanguageComponent().getOr:
            return

          let languages = config.get("lsp.ue-as.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"

    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
