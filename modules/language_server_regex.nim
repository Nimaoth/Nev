import std/[options, tables, strutils, os, strformat, sugar, sequtils]
import misc/[custom_logger, custom_async, util, rope_utils, event, rope_regex, myjsonutils, jsonex]
import text/language/[language_server_base]
import nimsumtree/[arc, rope]
import service, event_service, language_server_dynamic, document_editor, document, config_provider, vfs, vfs_service
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import workspaces/workspace

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import language_server_component, config_component, move_component, text_component, language_component
  logCategory "language_server_regex"

  type
    LanguageServerRegex* = ref object of LanguageServerDynamic
      services: Services
      config: ConfigStore
      documents: DocumentEditorService
      vfs: Arc[VFS2]
      files: Table[string, string]
      commandHistory*: seq[string]
      workspace: Workspace

  proc gotoRegexLocation(self: LanguageServerRegex, doc: Document, location: Cursor, regexName: string): Future[seq[Definition]] {.async.} =
    let moves = doc.getMoveComponent().getOr:
      return @[]
    let text = doc.getTextComponent().getOr:
      return @[]
    let config = doc.getConfigComponent().getOr:
      return @[]
    let language = doc.getLanguageComponent().getOr:
      return

    let s = moves.applyMove(location.toSelection.toRange, "language-word")
    let wordText = text.content(s)
    let regexTemplate = config.get(&"text.search-regexes.{regexName}", newJexNull())

    log lvlWarn, &"gotoRegexLocation {regexTemplate}"
    let searchString = if regexTemplate != nil and regexTemplate.kind != JNull:
      regexTemplate.decodeRegex("").replace("[[0]]", wordText)
    else:
      "\\b" & wordText & "\\b"

    log lvlInfo, &"Find '{wordText}' using regex '{searchString}'"
    var customArgs = @["--only-matching"]
    customArgs.add config.get("text.ripgrep.extra-args", seq[string])
    if config.get("text.ripgrep.pass-type", true):
      let fileType = config.get("text.ripgrep.file-type", language.languageId)
      customArgs.add ["--type", fileType]

    let searchResults = await self.workspace.search(searchString, 100, customArgs)

    var locations: seq[Definition]
    for info in searchResults:
      locations.add Definition(filename: "local://" // info.path, location: (info.line - 1, info.column))

    return locations

  proc regexGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.gotoRegexLocation(doc, location, "goto-definition")
    return @[]

  proc regexGetDeclaration*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.gotoRegexLocation(doc, location, "goto-declaration")
    return @[]

  proc regexGetImplementation*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.gotoRegexLocation(doc, location, "goto-implementation")
    return @[]

  proc regexGetTypeDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.gotoRegexLocation(doc, location, "goto-type-definition")
    return @[]

  proc regexGetReferences*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.gotoRegexLocation(doc, location, "goto-references")
    return @[]

  proc regexGetSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      let text = doc.getTextComponent().getOr:
        return @[]
      let config = doc.getConfigComponent().getOr:
        return @[]

      let regexTemplate = config.get(&"text.search-regexes.symbols", newJexNull())
      if regexTemplate == nil or regexTemplate.kind == JNull:
        return @[]
      let searchString = regexTemplate.decodeRegex("")
      if searchString == "":
        return @[]

      log lvlInfo, &"Find symbols using regex '{searchString}'"
      let rope = text.content.clone()
      let searchResults = await findAllAsync(rope.slice(int), searchString)

      var locations: seq[Symbol]
      for r in searchResults:
        if locations.len > 1000:
          log lvlWarn, &"gotoSymbolRegex: too many results ({searchResults.len}), truncate at 1000"
          break
        let name = $rope.slice(r)
        locations.add Symbol(
          location: r.a.toCursor,
          name: name,
          filename: filename,
        )

      return locations

    return @[]

  proc regexGetWorkspaceSymbols*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerRegex
    if self.documents.getDocumentByPath(filename).getSome(doc):
      let text = doc.getTextComponent().getOr:
        return @[]
      let config = doc.getConfigComponent().getOr:
        return @[]
      let language = doc.getLanguageComponent().getOr:
        return @[]

      let regexTemplate = config.get(&"text.search-regexes.symbols", newJexNull())
      if regexTemplate == nil or regexTemplate.kind == JNull:
        return @[]

      let searchStringByKind = config.get(&"text.search-regexes.workspace-symbols-by-kind", Table[string, RegexSetting].none)
      let searchStrings = if searchStringByKind.isSome:
        var searchStrings: seq[(SymbolType, string)]
        for sk, searchString in searchStringByKind.get.pairs:
          let r = searchString.decodeRegex()
          if r.len == 0:
            continue
          try:
            let symbolType = parseEnum[SymbolType](sk)
            searchStrings.add (symbolType, r)
          except Exception as e:
            log lvlInfo, &"Invalid symbol kind '{sk}' in config {r}: {e.msg}"

        searchStrings

      elif (let ws = config.get(&"text.search-regexes.workspace-symbols", newJexNull()); ws.kind != JNull):
        @[(SymbolType.Unknown, ws.decodeRegex(""))]
      else:
        @[]

      if searchStrings.len == 0:
        return

      var customArgs: seq[string] = @[]
      customArgs.add config.get("text.ripgrep.extra-args", seq[string])
      if config.get("text.ripgrep.pass-type", true):
        let fileType = config.get("text.ripgrep.file-type", language.languageId)
        customArgs.add ["--type", fileType]

      let maxResults = 50_000 # doc.settings.searchWorkspaceRegexMaxResults.get() # todo
      if config.get("text.search-regexes.show-only-matching-part", true):
        customArgs.add("--only-matching")
      let futures = collect:
        for (symbolType, searchString) in searchStrings:
          self.workspace.search(searchString, maxResults, customArgs)

      let res = futures.allFinished.await.mapIt(it.read)
      var locations: seq[Symbol]
      for i in 0..res.high:
        for info in res[i]:
          let cursor = (info.line - 1, info.column)
          locations.add Symbol(
            location: cursor,
            name: info.text,
            symbolType: searchStrings[i][0],
            filename: "local://" // info.path)
      return locations

    return @[]

  proc newLanguageServerRegex(services: Services): LanguageServerRegex =
    result = new LanguageServerRegex
    result.name = "regex"
    result.services = services
    result.documents = services.getService(DocumentEditorService).get
    result.vfs = services.getService(VFSService).get.vfs2
    result.config = services.getService(ConfigService).get.runtime
    result.workspace = services.getService(Workspace).get
    result.refetchWorkspaceSymbolsOnQueryChange = false

    result.getDefinitionImpl = regexGetDefinition
    result.getDeclarationImpl = regexGetDeclaration
    result.getImplementationImpl = regexGetImplementation
    result.getTypeDefinitionImpl = regexGetTypeDefinition
    result.getReferencesImpl = regexGetReferences
    result.getSymbolsImpl = regexGetSymbols
    result.getWorkspaceSymbolsImpl = regexGetWorkspaceSymbols

  proc init_module_language_server_regex*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_language_server_regex: no services found"
      return

    var ls = newLanguageServerRegex(services)

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

          let languages = config.get("lsp.regex.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"
    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
