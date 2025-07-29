import std/[options, tables, strutils, sugar, sequtils]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, rope_utils, event, rope_regex, myjsonutils, jsonex]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base]
import document_editor, service, vfs_service, vfs, config_provider
import workspaces/workspace
import text/[text_document, text_editor]

logCategory "language-server-regex"

type
  LanguageServerRegex* = ref object of LanguageServer
    services: Services
    config: ConfigStore
    documents: DocumentEditorService
    vfs: VFS
    files: Table[string, string]
    commandHistory*: seq[string]
    workspace: Workspace

  LanguageServerRegexService* = ref object of Service
    languageServer: LanguageServerRegex

proc newLanguageServerRegex(services: Services): LanguageServerRegex =
  var server = new LanguageServerRegex
  server.name = "regex"
  server.services = services
  server.documents = services.getService(DocumentEditorService).get
  server.vfs = services.getService(VFSService).get.vfs
  server.config = services.getService(ConfigService).get.runtime
  server.workspace = services.getService(Workspace).get
  server.refetchWorkspaceSymbolsOnQueryChange = false
  return server

func serviceName*(_: typedesc[LanguageServerRegexService]): string = "LanguageServerRegexService"

addBuiltinService(LanguageServerRegexService, VFSService, DocumentEditorService)

method init*(self: LanguageServerRegexService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.languageServer = newLanguageServerRegex(self.services)
  discard self.languageServer.documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
    let doc = editor.getDocument()
    if doc of TextDocument:
      let textDoc = doc.TextDocument
      let languages = self.languageServer.config.get("lsp.regex.languages", newSeq[string]())
      if textDoc.languageId in languages or "*" in languages:
        discard textDoc.addLanguageServer(self.languageServer)
  return ok()

proc gotoRegexLocation(self: LanguageServerRegex, doc: TextDocument, location: Cursor, regexTemplate: Option[string]): Future[seq[Definition]] {.async.} =

  let s = doc.findWordBoundary(location)
  let text = doc.contentString(s)
  let searchString = if regexTemplate.getSome(regexTemplate):
    regexTemplate.replace("[[0]]", text)
  else:
    "\\b" & text & "\\b"

  let rgLanguageId = doc.settings.searchRegexes.rgLanguage.get().get(doc.languageId)
  log lvlInfo, &"Find '{text}' using regex '{searchString}'"
  let customArgs = @["--type", rgLanguageId, "--only-matching"]
  let searchResults = await self.workspace.searchWorkspace(searchString, 100, customArgs)

  var locations: seq[Definition]
  for info in searchResults:
    locations.add Definition(filename: "local://" // info.path, location: (info.line - 1, info.column))

  return locations

method getDefinition*(self: LanguageServerRegex, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let t = doc.TextDocument.settings.searchRegexes.gotoDefinition.getRegex()
    return await self.gotoRegexLocation(doc.TextDocument, location, t)
  return @[]

method getDeclaration*(self: LanguageServerRegex, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let t = doc.TextDocument.settings.searchRegexes.gotoDeclaration.getRegex()
    return await self.gotoRegexLocation(doc.TextDocument, location, t)
  return @[]

method getImplementation*(self: LanguageServerRegex, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let t = doc.TextDocument.settings.searchRegexes.gotoImplementation.getRegex()
    return await self.gotoRegexLocation(doc.TextDocument, location, t)
  return @[]

method getTypeDefinition*(self: LanguageServerRegex, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let t = doc.TextDocument.settings.searchRegexes.gotoTypeDefinition.getRegex()
    return await self.gotoRegexLocation(doc.TextDocument, location, t)
  return @[]

method getReferences*(self: LanguageServerRegex, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let t = doc.TextDocument.settings.searchRegexes.gotoReferences.getRegex()
    return await self.gotoRegexLocation(doc.TextDocument, location, t)
  return @[]

method getSymbols*(self: LanguageServerRegex, filename: string): Future[seq[Symbol]] {.async.} =
  if self.documents.getDocument(filename).getSome(d) and d of TextDocument:
    let doc = d.TextDocument
    let searchString = doc.settings.searchRegexes.symbols.getRegex()
    if searchString.isNone:
      return @[]

    log lvlInfo, &"Find symbols using regex '{searchString.get}'"
    let rope = doc.rope.clone()
    let searchResults = await findAllAsync(rope.slice(int), searchString.get)

    var locations: seq[Symbol]
    for r in searchResults:
      if locations.len > 1000:
        log lvlWarn, &"gotoSymbolRegex: too many results ({searchResults.len}), truncate at 1000"
        break
      let name = $rope.slice(r)
      locations.add Symbol(
        location: r.a.toCursor,
        name: name,
        filename: doc.filename,
      )

    return locations

  return @[]

method getWorkspaceSymbols*(self: LanguageServerRegex, filename: string, query: string): Future[seq[Symbol]] {.async.} =
  if self.documents.getDocument(filename).getSome(d) and d of TextDocument:
    let doc = d.TextDocument
    let searchStringByKind = doc.settings.searchRegexes.workspaceSymbolsByKind.get()
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

    elif doc.settings.searchRegexes.workspaceSymbols.getRegex().getSome(regex):
      @[(SymbolType.Unknown, regex)]
    else:
      @[]

    if searchStrings.len == 0:
      return

    let rgLanguageId = doc.settings.searchRegexes.rgLanguage.get().get(doc.languageId)
    let maxResults = 50_000 # doc.settings.searchWorkspaceRegexMaxResults.get() # todo
    var customArgs = @["--type", rgLanguageId]
    if doc.settings.searchRegexes.showOnlyMatchingPart.get():
      customArgs.add("--only-matching")
    let futures = collect:
      for (symbolType, searchString) in searchStrings:
        self.workspace.searchWorkspace(searchString, maxResults, customArgs)

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
