#use language_server_lsp language_server_regex event_service language_server_component

# language_server_ue_cpp: Unreal Engine C++ language server module.
#
# Wraps clangd (C++ LSP) and angel-lsp (AngelScript LSP) and a regex-based
# searcher to provide a unified language server for UE C++ files.
#
# Features:
#   - Go to definition/declaration/implementation/type-definition via clangd,
#     with generated file filtering (.generated.h, .gen.cpp excluded)
#   - Go to implementation: merges clangd results with AngelScript workspace
#     symbol lookup and regex-based goto (searches ws0://Script)
#   - Find references for C++ symbols via clangd
#   - Find references for AngelScript usages of C++ symbols:
#       * Function calls:  \b<name>\b\(
#       * Type references: \b<name>\b  (when word starts with F/T/U/A/E/I prefix)
#       * Field references (dot-prefixed): \.<name>\b
#       * Bare field references in subclasses: \b<name>\b searched only in files
#         that declare an AngelScript class inheriting from the C++ containing
#         class (recursively, transitive subclasses included)
#   - Subclass discovery: getAngelscriptSubclasses searches ws0://Script for
#     `class X : ClassName` patterns
#   - Workspace symbols: merged from clangd + angel-lsp

const currentSourcePath2 = currentSourcePath()
include module_base

when defined(appLspUeCpp):
  import language_server_dynamic

  proc getLanguageServerUECpp*(): LanguageServerDynamic {.rtl, gcsafe, raises: [].}

else:
  static:
    echo "DONT build lsp ue cpp"

when implModule and defined(appLspUeCpp):
  import std/[options, json, strutils]
  import nimsumtree/[arc, rope]
  import misc/[custom_logger, util, event, custom_async, response, rope_utils, jsonex]
  import workspaces/workspace
  import vfs, vfs_service
  import document, language_server_component, config_component, language_component, move_component, text_component
  import language_server_lsp/language_server_lsp, language_server_regex
  import service, event_service, document_editor, config_provider
  import text/language/[language_server_base, lsp_types]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  logCategory "language-server-ue-cpp"

  type
    LanguageServerUECpp* = ref object of LanguageServerDynamic
      services: Services
      config: ConfigStore
      documents: DocumentEditorService
      eventBus: EventService
      clangdDiagnosticsHandle: Id
      clangd: LanguageServerDynamic
      angelLs: LanguageServerDynamic
      regexLs: LanguageServerRegex
      vfs*: Arc[VFS2]
      workspace*: Workspace

  proc getWorkspaceSymbolsRawClangd*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[WorkspaceSymbolRaw]] {.async.}
  proc getAngelscriptSubclasses(self: LanguageServerUECpp, className: string, recurse: bool = false): Future[seq[tuple[class: string, path: string, location: Cursor]]] {.async.}

  proc filterGenerated(definitions: sink seq[Definition]): seq[Definition] =
    result = newSeqOfCap[Definition](definitions.len)
    for r in definitions:
      if r.filename.endsWith(".generated.h") or r.filename.endsWith(".gen.cpp"):
        continue
      result.add r

  proc symbolNameMatches(symbolName: string, wordText: string): bool =
    let baseName = symbolName.split('(')[0].replace("::", ".")
    for part in baseName.split('.'):
      if part == wordText:
        return true
    return false

  static:
    assert symbolNameMatches("Class.Func(...)", "Class")
    assert symbolNameMatches("Class.Func(...)", "Func")
    assert symbolNameMatches("Class", "Class")
    assert symbolNameMatches("Func(...)", "Func")
    assert symbolNameMatches("Class.Field", "Class")
    assert symbolNameMatches("Class.Field", "Field")
    assert symbolNameMatches("Class::Field", "Class")
    assert symbolNameMatches("Class::Field", "Field")
    assert symbolNameMatches("Class::Func(...)", "Class")
    assert symbolNameMatches("Class::Func(...)", "Func")

    assert not symbolNameMatches("Class.Func(...)", "Clas")
    assert not symbolNameMatches("Class.Func(...)", "Fun")
    assert not symbolNameMatches("Class", "Clas")
    assert not symbolNameMatches("Func(...)", "Fun")
    assert not symbolNameMatches("Class.Field", "Clas")
    assert not symbolNameMatches("Class.Field", "Fiel")
    assert not symbolNameMatches("Class::Field", "Clas")
    assert not symbolNameMatches("Class::Field", "Fiel")
    assert not symbolNameMatches("Class::Func(...)", "Clas")
    assert not symbolNameMatches("Class::Func(...)", "Fun")

  proc getClangd(self: LanguageServerDynamic): Future[Option[LanguageServerDynamic]] {.async.} =
    let self = self.LanguageServerUECpp
    result = await getOrCreateLanguageServerLSP("clangd")
    if result.isSome and result.get != self.clangd:
      if self.clangd != nil:
        self.clangd.onDiagnostics.unsubscribe(self.clangdDiagnosticsHandle)
      self.clangd = result.get
      self.clangdDiagnosticsHandle = self.clangd.onDiagnostics.subscribe proc(params: lsp_types.PublicDiagnosticsParams) =
        self.onDiagnostics.invoke params

  proc getAngelLs(self: LanguageServerDynamic): Future[Option[LanguageServerDynamic]] {.async.} =
    let self = self.LanguageServerUECpp
    result = await getOrCreateLanguageServerLSP("angel-lsp")
    if result.isSome and result.get != self.angelLs:
      self.angelLs = result.get

  proc getDefinitionClangd*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    result = await clangd.getDefinition(filename, location)
    result = result.filterGenerated()

  proc getImplementationClangd*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    result = await clangd.getImplementation(filename, location)
    result = result.filterGenerated()

  proc getImplementationAngelscript*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerUECpp
    let angelLs = (await self.getAngelLs()).getOr: return @[]

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

    var res: seq[Definition]

    let symbolsFut = angelLs.getWorkspaceSymbolsRaw(filename, wordText)

    let isType = wordText.len >= 2 and wordText[0].isUpperAscii and wordText[1].isUpperAscii and wordText[0] in {'F', 'T', 'U', 'A', 'E', 'I'}
    if isType:
      let subclasses = await self.getAngelscriptSubclasses(wordText, recurse = true)
      debugf"getAngelscriptReferences: found {subclasses.len} AngelScript subclass entries for '{wordText}'"
      for entry in subclasses:
        res.add Definition(location: entry.location, filename: entry.path)

    let symbols = symbolsFut.await
    for sym in symbols:
      if sym.symbol.name.symbolNameMatches(wordText):
        if sym.symbol.location.asUriObject().isSome:
          let resolved = await angelLs.resolveWorkspaceSymbol(sym.symbol)
          if resolved.getSome(d):
            res.add d
        elif sym.location.getSome(loc):
          res.add Definition(location: loc, filename: sym.path)
        else:
          res.add Definition(filename: sym.path)
    return res

  proc getImplementationRegex*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerUECpp
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.regexLs.gotoRegexLocation(doc, location, "goto-implementation")
    return @[]

  proc ueGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let cppDefinitionsFut = self.getDefinitionClangd(filename, location)
    let angelscriptDefinitions1Fut = self.getImplementationAngelscript(filename, location)
    await allFutures(cppDefinitionsFut, angelscriptDefinitions1Fut)
    return cppDefinitionsFut.read & angelscriptDefinitions1Fut.read

  proc ueGetDeclaration*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    result = await clangd.getDeclaration(filename, location)
    result = result.filterGenerated()

  proc ueGetImplementation*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let cppDefinitionsFut = self.getImplementationClangd(filename, location)
    let angelscriptDefinitions1Fut = self.getImplementationAngelscript(filename, location)
    await allFutures(cppDefinitionsFut, angelscriptDefinitions1Fut)
    return cppDefinitionsFut.read & angelscriptDefinitions1Fut.read

  proc ueGetTypeDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    result = await clangd.getTypeDefinition(filename, location)
    result = result.filterGenerated()

  proc searchWorkspace(self: LanguageServerUECpp, searchString: string, paths: sink seq[string], extraArgs: sink seq[string]): Future[seq[Definition]] {.async.} =
    let searchResults = self.workspace.search(paths, searchString, 1000, extraArgs)

    let dotResults = await searchResults
    var locations: seq[Definition]
    for info in dotResults:
      locations.add Definition(filename: "local://" // info.path, location: (info.line - 1, info.column))

    return locations

  proc searchWorkspace(self: LanguageServerUECpp, regexTemplate: JsonNodeEx, wordText: string, extraArgs: sink seq[string]): Future[seq[Definition]] {.async.} =
    if regexTemplate == nil or regexTemplate.kind == JNull:
      return @[]

    let searchString = regexTemplate.decodeRegex("").replace("[[0]]", wordText)
    let scriptPath = self.vfs.localize("ws0://Script")
    return await self.searchWorkspace(searchString, @[scriptPath], extraArgs)

  proc getContainingCppClass(self: LanguageServerUECpp, filename: string, location: Cursor, fieldName: string): Future[Option[string]] {.async.} =
    ## Searches for the class declaring `fieldName`.
    ## Returns the class name (e.g. "UMyComponent") or none.
    debugf"getContainingCppClass: regex search in '{filename}'"
    let classRegex = self.config.get("lsp.ue-cpp.containing-class-regex", newJexString(r"^\s*(class|struct)(\s+[A-Z0-9_]+_API)?\s+\w+")).decodeRegex("")
    let localFilename = self.vfs.localize(filename)
    let searchResults = await self.workspace.search(@[localFilename], classRegex, 10000, @["--only-matching"])
    var bestLine = -1
    var bestMatch = ""
    for info in searchResults:
      let matchLine = info.line - 1  # info.line is 1-based
      if matchLine <= location.line and matchLine > bestLine:
        bestLine = matchLine
        bestMatch = info.text
    if bestMatch.len > 0:
      let parts = bestMatch.splitWhitespace()
      if parts.len > 0:
        let cn = parts[^1]
        debugf"getContainingCppClass: fallback found class '{cn}' at line {bestLine}"
        return cn.some

    debugf"getContainingCppClass: no class found for '{fieldName}'"
    return string.none

  proc getAngelscriptSubclasses(self: LanguageServerUECpp, className: string, recurse: bool = false): Future[seq[tuple[class: string, path: string, location: Cursor]]] {.async.} =
    ## Searches .as files under ws0://Script for AngelScript class declarations
    ## that inherit from `className`. Returns (subclass name, file path, location) tuples.
    ## If recurse is true, also includes transitive subclasses.
    debugf"getAngelscriptSubclasses: looking for AngelScript subclasses of '{className}' (recurse={recurse})"
    let regexTemplate = self.config.get("lsp.ue-cpp.angelscript-subclass-regex", newJexString(r"class\s+\w+\s*:\s*[[0]]\b"))
    let searchString = regexTemplate.decodeRegex("").replace("[[0]]", className)
    let scriptPath = self.vfs.localize("ws0://Script")
    let searchResults = await self.workspace.search(@[scriptPath], searchString, 10000, @["--only-matching"])

    var seen: seq[tuple[class: string, path: string, location: Cursor]]
    var subclassNames: seq[string]
    for info in searchResults:
      let parts = info.text.splitWhitespace()
      if parts.len < 2:
        continue
      let subName = parts[1]
      let entry = (class: subName, path: info.path, location: (info.line - 1, info.column))
      if entry notin seen:
        seen.add entry
      if recurse and subName notin subclassNames:
        subclassNames.add subName

    if recurse and subclassNames.len > 0:
      var futs = newSeqOfCap[Future[seq[tuple[class: string, path: string, location: Cursor]]]](subclassNames.len)
      for subName in subclassNames:
        futs.add self.getAngelscriptSubclasses(subName, recurse = true)
      await allFutures(futs)
      for fut in futs:
        for entry in fut.read:
          if entry notin seen:
            seen.add entry

    debugf"getAngelscriptSubclasses: found {seen.len} subclass entries for '{className}'"
    return seen

  proc getSubclassFieldReferences(self: LanguageServerUECpp, regexTemplate: JsonNodeEx, fieldName: string, subclassPaths: seq[string], extraArgs: seq[string]): Future[seq[Definition]] {.async.} =
    ## Searches the given AngelScript files for bare (no period) usages of `fieldName`.
    if regexTemplate == nil or regexTemplate.kind == JNull:
      return @[]

    debugf"getSubclassFieldReferences: searching {subclassPaths.len} files for '{fieldName}' using {regexTemplate}"
    let searchString = regexTemplate.decodeRegex("").replace("[[0]]", fieldName)
    return await self.searchWorkspace(searchString, subclassPaths, extraArgs)

  proc getAngelscriptReferences(self: LanguageServerUECpp, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let doc = self.documents.getDocumentByPath(filename).getOr:
      return @[]
    let moves = doc.getMoveComponent().getOr:
      return @[]
    let text = doc.getTextComponent().getOr:
      return @[]
    let config = doc.getConfigComponent().getOr:
      return @[]
    let language = doc.getLanguageComponent().getOr:
      return @[]

    let s = moves.applyMove(location.toSelection.toRange, "language-word")
    let wordText = text.content(s)
    let nextChar = text.content(s.b...s.b, inclusiveEnd = true)
    let isType = wordText.len >= 2 and wordText[0].isUpperAscii and wordText[1].isUpperAscii and wordText[0] in {'F', 'T', 'U', 'A', 'E', 'I'}

    var customArgs = @["--only-matching"] #, "--type-add", "as:*.as", "--type", "as"]
    customArgs.add config.get("text.ripgrep.extra-args", seq[string])

    let isField = nextChar == ";"
    if nextChar == "(":
      return await self.searchWorkspace(
        config.get(&"lsp.ue-cpp.find-references-angelscript-regex-function", newJexString("\\b[[0]]\\b\\(")),
        wordText, customArgs)
    elif isType:
      return await self.searchWorkspace(
        config.get(&"lsp.ue-cpp.find-references-angelscript-regex-type", newJexString("\\b[[0]]\\b")),
        wordText, customArgs)
    elif isField:
      let fieldsFut = self.searchWorkspace(
        config.get(&"lsp.ue-cpp.find-references-angelscript-regex-field", newJexString("\\.\\b[[0]]\\b")),
        wordText, customArgs)
      var thisFields: seq[Definition] = @[]
      let containingClass = await self.getContainingCppClass(filename, location, wordText)
      if containingClass.isSome:
        let subclasses = await self.getAngelscriptSubclasses(containingClass.get, recurse = true)
        debugf"getAngelscriptReferences: found {subclasses.len} AngelScript subclass entries for '{containingClass.get}'"
        if subclasses.len > 0:
          var uniquePaths: seq[string]
          for entry in subclasses:
            if entry.path notin uniquePaths:
              uniquePaths.add entry.path
          let fieldRegex = config.get(&"lsp.ue-cpp.find-references-angelscript-regex-this-field", newJexString("\\b[[0]]\\b"))
          thisFields = await self.getSubclassFieldReferences(fieldRegex, wordText, uniquePaths, customArgs)
      else:
        debugf"getAngelscriptReferences: no containing class found for field '{wordText}', skipping subclass search"

      let fields = await fieldsFut
      debugf"getAngelscriptReferences: {fields.len} dot-prefixed field refs, {thisFields.len} bare subclass field refs"
      return thisFields & fields
    else:
      return await self.searchWorkspace(
        config.get(&"lsp.ue-cpp.find-references-angelscript-regex", newJexString("\\b[[0]]\\b")),
        wordText, customArgs)

  proc getCppReferences(self: LanguageServerUECpp, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    result = await clangd.getReferences(filename, location)
    result = result.filterGenerated()

  proc ueGetReferences*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerUECpp
    let asReferencesFut = self.getAngelscriptReferences(filename, location)
    let cppReferencesFut = self.getCppReferences(filename, location)
    let asReferences = asReferencesFut.await.catch(@[])
    let cppReferences = cppReferencesFut.await.catch(@[])
    return asReferences & cppReferences

  proc ueSwitchSourceHeader*(self: LanguageServerDynamic, filename: string): Future[Option[string]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return string.none
    return await clangd.switchSourceHeader(filename)

  proc ueGetCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Response[lsp_types.CompletionList].default
    return await clangd.getCompletions(filename, location)

  proc ueGetSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    return await clangd.getSymbols(filename)

  proc getWorkspaceSymbolsClangd*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return @[]
    return await clangd.getWorkspaceSymbols(filename, query)

  proc getWorkspaceSymbolsAngelscript*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return @[]
    return await angelLs.getWorkspaceSymbols(filename, query)

  proc ueGetWorkspaceSymbols*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let clangdSymbols = self.getWorkspaceSymbolsClangd(filename, query)
    let angelscriptSymbols = self.getWorkspaceSymbolsAngelscript(filename, query)
    return clangdSymbols.await & angelscriptSymbols.await

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
    # return clangdSymbolsFut.await & angelscriptSymbolsFut.await
    let clangdSymbols = await clangdSymbolsFut
    let angelscriptSymbols = await angelscriptSymbolsFut
    result = clangdSymbols & angelscriptSymbols

  proc resolveWorkspaceSymbolClangd*(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Definition.none
    return await clangd.resolveWorkspaceSymbol(symbol)

  proc resolveWorkspaceSymbolAngelscript*(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    let angelLs = (await self.getAngelLs()).getOr: return Definition.none
    return await angelLs.resolveWorkspaceSymbol(symbol)

  proc ueResolveWorkspaceSymbol*(self: LanguageServerDynamic, symbol: lsp_types.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    if symbol.location.asUriObject().getSome(uri) and uri.uri.endsWith(".as"):
      return await self.resolveWorkspaceSymbolAngelscript(symbol)
    return await self.resolveWorkspaceSymbolClangd(symbol)

  proc ueGetHover*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return string.none
    return await clangd.getHover(filename, location)

  proc ueGetSignatureHelp*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Response[seq[lsp_types.SignatureHelpResponse]].default
    return await clangd.getSignatureHelp(filename, location)

  proc ueGetInlayHints*(self: LanguageServerDynamic, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Response[seq[language_server_base.InlayHint]].default
    return await clangd.getInlayHints(filename, selection)

  proc ueGetDiagnostics*(self: LanguageServerDynamic, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Response[seq[lsp_types.Diagnostic]].default
    return await clangd.getDiagnostics(filename)

  proc ueGetCompletionTriggerChars*(self: LanguageServerDynamic): set[char] =
    return {'.', '>', ':'}

  proc ueGetCodeActions*(self: LanguageServerDynamic, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Response[lsp_types.CodeActionResponse].default
    return await clangd.getCodeActions(filename, selection, diagnostics)

  proc ueRename*(self: LanguageServerDynamic, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return Response[seq[lsp_types.WorkspaceEdit]].default
    return await clangd.rename(filename, position, newName)

  proc ueExecuteCommand*(self: LanguageServerDynamic, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
    let clangd = (await self.getClangd()).getOr: return errorResponse[JsonNode](0, "ue-cpp: no clangd instance")
    return await clangd.executeCommand(command, arguments)

  proc ueConnect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerUECpp
    proc doConnect() {.async.} =
      let clangd = (await self.getClangd()).getOr: return
      clangd.connect(document)
    asyncSpawn doConnect()

  proc ueDisconnect*(self: LanguageServerDynamic, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerUECpp
    proc doDisconnect() {.async.} =
      let clangd = (await self.getClangd()).getOr: return
      clangd.disconnect(document)
    asyncSpawn doDisconnect()

  proc newLanguageServerUECpp(services: Services): LanguageServerUECpp =
    result = new LanguageServerUECpp
    result.capabilities.completionProvider = lsp_types.CompletionOptions().some
    result.regexLs = newLanguageServerRegex(services)
    result.name = "ue-cpp"
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

  var gls: LanguageServerUECpp = nil

  proc getLanguageServerUECpp*(): LanguageServerDynamic {.gcsafe, raises: [].} =
    {.gcsafe.}:
      return gls

  proc init_module_language_server_ue_cpp*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize language_server_ue_cpp: no services found"
      return

    var ls = newLanguageServerUECpp(services)
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

          let languages = config.get("lsp.ue-cpp.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"

    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
