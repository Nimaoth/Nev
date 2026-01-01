import std/[options, tables, strutils, sugar, sequtils, sets, os]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, rope_utils, event, rope_regex, myjsonutils, jsonex, interned_string, timer, delayed_task, async_process, response]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import document_editor, service, vfs_service, vfs, config_provider, event_service
import workspaces/workspace
import text/[text_document, text_editor]

logCategory "language-server-ctags"

type
  CTagsDefinition = object
    name: string
    path: string
    kind: SymbolType
    kindRaw: string
    address: int
    line: int
    language: string
    signature: string

  CTagsFile = object
    path: string
    updateTask: DelayedTask
    files: HashSet[string]

  CTagsSymbols = object
    sourceFile: string
    definitions: seq[CTagsDefinition]
    completions: seq[lsp_types.CompletionItem]
    symbols: seq[Symbol]
    moduleCompletions: seq[lsp_types.CompletionItem]

  LanguageServerCTags* = ref object of LanguageServer
    services: Services
    config: ConfigStore
    documents: DocumentEditorService
    eventBus: EventService
    vfs: VFS
    commandHistory*: seq[string]
    workspace: Workspace

    importMap: Table[string, HashSet[string]]    # Map from import name to file paths
    files: Table[string, CTagsSymbols]  # Code file path to parsed ctags
    ctags: Table[string, CTagsFile]    # CTags file path to parsed ctags
    fileToCTags: Table[string, string] # Code file path to ctags file path
    workspaceSymbols: seq[Symbol]

  LanguageServerCTagsService* = ref object of Service
    languageServer: LanguageServerCTags

proc updateCTagFiles(self: LanguageServerCTags) {.async.}
proc loadCTagsCommand(self: LanguageServerCTags, path: string) {.async.}

proc newLanguageServerCTags(services: Services): LanguageServerCTags =
  var server = new LanguageServerCTags
  server.name = "ctags"
  server.services = services
  server.documents = services.getService(DocumentEditorService).get
  server.vfs = services.getService(VFSService).get.vfs
  server.config = services.getService(ConfigService).get.runtime
  server.workspace = services.getService(Workspace).get
  server.eventBus = services.getService(EventService).get
  server.refetchWorkspaceSymbolsOnQueryChange = false
  server.capabilities.completionProvider = lsp_types.CompletionOptions().some

  proc cb(event, payload: string) {.gcsafe, raises: [].} =
    try:
      debugf"handle saved '{event}' '{payload}'"
      let id = payload.parseInt.DocumentId
      if server.documents.getDocument(id).getSome(doc) and doc of TextDocument and doc.TextDocument.hasLanguageServer(server):
        asyncSpawn server.loadCTagsCommand(doc.filename)
    except CatchableError as e:
      log lvlError, &"Error: {e.msg}"
  server.eventBus.listen(newId(), "document/*/saved", cb)

  discard server.config.onConfigChanged.subscribe proc(key: string) =
    if key == "" or key == "lsp" or key == "lsp.ctags" or key == "lsp.ctags.paths":
      asyncSpawn server.updateCTagFiles()

  asyncSpawn server.updateCTagFiles()
  return server

func serviceName*(_: typedesc[LanguageServerCTagsService]): string = "LanguageServerCTagsService"

addBuiltinService(LanguageServerCTagsService, VFSService, DocumentEditorService, EventService)

proc toSymbolType(str: string): SymbolType =
  case str
  of "type": return SymbolType.Class
  of "proc", "func", "method", "template", "macro", "iterator", "converter": return SymbolType.Function
  of "module": return SymbolType.Module
  of "var", "const", "let": return SymbolType.Variable
  else:
    log lvlWarn, &"Unknown symbol type '{str}'"
    return SymbolType.Unknown

proc loadCTags(self: LanguageServerCTags, path: string, content: string) {.async.} =
  try:
    var lastLine = ""
    var t = startTimer()
    var seenFiles = initHashSet[string]()

    # Clear previous values
    for f in self.ctags[path].files:
      self.files[f] = CTagsSymbols(sourceFile: path)

    var total = 0
    for line in content.splitLines:
      if line.startsWith("!_"):
        continue

      if line == lastLine:
        continue
      lastLine = line

      var i = 0
      proc nextPart(line: string, i: var int): string =
        let k = line.find('\t', i)
        let oldI = i
        if k == -1:
          i = line.len
          line[oldI..^1]
        else:
          i = k + 1
          line[oldI..<k]

      var def = CTagsDefinition()
      def.name = nextPart(line, i)
      let nativePath = nextPart(line, i)
      def.path = "local://" // nativePath.normalizeNativePath()
      let address = nextPart(line, i)
      if address.endsWith(";\""):
        while i < line.len:
          let part = nextPart(line, i)
          let k = part.find(':')
          if k != -1:
            let key = part[0..<k]
            let value = part[(k + 1)..^1]
            case key
            of "kind":
              def.kindRaw = value
              def.kind = value.toSymbolType()
            of "line":
              def.line = value.parseInt.catch(0)
            of "signature":
              def.signature = value
            of "language":
              def.language = value.toLowerAscii
            else:
              log lvlWarn, &"Unknown key '{part}'"
              continue
          else:
            log lvlWarn, &"Invalid part '{part}'"
            continue

      let cursor = (def.line - 1, 0)
      if def.name != "":
        # Clear all symbols for the file of this symbol the first time we see a symbol for this file
        if def.path notin seenFiles:
          self.files[def.path] = CTagsSymbols(sourceFile: path)
          seenFiles.incl def.path
          let name = def.path.splitFile.name
          if name in self.importMap:
            self.importMap[name].incl def.path
          else:
            self.importMap[name] = [def.path].toHashSet

        self.files.withValue(def.path, s):
          total.inc()
          s[].symbols.add Symbol(
            location: cursor,
            name: def.name,
            symbolType: def.kind,
            filename: def.path,
          )
          s[].definitions.add def

          let edit = lsp_types.TextEdit(
            `range`: lsp_types.Range(
              start: lsp_types.Position(line: -1, character: -1),
              `end`: lsp_types.Position(line: -1, character: -1),
            ),
            newText: def.name,
          )
          let detail = if def.signature.len > 0: def.signature else: def.kindRaw
          let completion = CompletionItem(
            kind: lsp_types.CompletionKind.Text,
            label: def.name,
            detail: detail.some,
            documentation: lsp_types.init(lsp_types.CompletionItemDocumentationVariant, def.path).some,
            insertTextFormat: InsertTextFormat.PlainText.some,
            textEdit: lsp_types.init(lsp_types.CompletionItemTextEditVariant, edit).some,
          )
          case def.kind
          of SymbolType.File, SymbolType.Module, SymbolType.Namespace, SymbolType.Package:
            s[].moduleCompletions.add completion
          else:
            s[].completions.add completion

      if t.elapsed.ms > 10:
        try:
          await sleepAsync(1.milliseconds)
          t = startTimer()
        except:
          discard

    log lvlWarn, &"Loaded {total} symbols for {seenFiles.len} files from '{path}'"
    self.ctags[path].files = seenFiles

  except CatchableError as e:
    log lvlError, &"Failed to read ctags file '{path}': {e.msg}"

proc loadCTags(self: LanguageServerCTags, path: string) {.async.} =
  let f = await self.vfs.read(path)
  await self.loadCTags(path, f)

proc loadCTagsCommand(self: LanguageServerCTags, path: string) {.async.} =
  try:
    let args = @["-f", "-", "-p", self.vfs.localize(path)]
    let ntaggerPath = self.vfs.localize("nimble://ntagger-0.6.2-ae571e58e450c166b444117f5f7b4244cd67267d/ntagger.exe")
    let output = runProcessAsyncOutput(ntaggerPath, args, maxLines=100000).await.output
    self.ctags[path] = CTagsFile(path: path)
    await self.loadCTags(path, output)
  except CatchableError as e:
    log lvlError, &"Failed to load ctags from file using command: '{path}': {e.msg}"

proc updateCTagFile(self: LanguageServerCTags, path: string) {.async.} =
  try:
    if path notin self.ctags:
      discard self.vfs.watch(path, proc(events: seq[PathEvent]) =
        let changedFiles = events.mapIt(it.name.normalizeNativePath)
        if self.ctags[path].updateTask != nil:
          self.ctags[path].updateTask.reschedule()
      )
    self.ctags[path] = CTagsFile(path: path)
    self.ctags[path].updateTask = startDelayedPaused(500, repeat=false):
      asyncSpawn self.loadCTags(path)

    await self.loadCTags(path)
  except CatchableError as e:
    log lvlError, &"Failed to update ctag file '{path}': {e.msg}"

proc updateCTagFiles(self: LanguageServerCTags) {.async.} =
  try:
    let paths = self.config.get("lsp.ctags.paths", newSeq[string]())
    for path in paths:
      if path in self.ctags:
        continue
      asyncSpawn self.updateCTagFile(path)
  except CatchableError as e:
    log lvlError, &"Failed to update ctag files: {e.msg}"

method init*(self: LanguageServerCTagsService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.languageServer = newLanguageServerCTags(self.services)
  discard self.languageServer.documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
    let doc = editor.getDocument()
    if doc of TextDocument:
      let textDoc = doc.TextDocument
      let languages = self.languageServer.config.get("lsp.ctags.languages", newSeq[string]())
      if textDoc.languageId in languages or "*" in languages:
        discard textDoc.addLanguageServer(self.languageServer)

  return ok()

proc getDefinitions(self: LanguageServerCTags, doc: TextDocument, location: Cursor): Future[seq[Definition]] {.async.} =
  let s = doc.getLanguageWordBoundary(location)
  let text = doc.contentString(s)
  var res: seq[Definition]
  for file in self.files.values:
    for def in file.symbols:
      if (def.name.len > 0 and def.name == text) or (def.name == text):
        res.add Definition(
          location: def.location,
          filename: if def.filename.len > 0: def.filename else: $def.filename)
  return res

method getDefinition*(self: LanguageServerCTags, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    return await self.getDefinitions(doc.TextDocument, location)
  return @[]

method getDeclaration*(self: LanguageServerCTags, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    return await self.getDefinitions(doc.TextDocument, location)
  return @[]

method getImplementation*(self: LanguageServerCTags, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    return await self.getDefinitions(doc.TextDocument, location)
  return @[]

method getTypeDefinition*(self: LanguageServerCTags, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    return await self.getDefinitions(doc.TextDocument, location)
  return @[]

method getReferences*(self: LanguageServerCTags, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    return await self.getDefinitions(doc.TextDocument, location)
  return @[]

method getSymbols*(self: LanguageServerCTags, filename: string): Future[seq[Symbol]] {.async.} =
  if filename in self.files:
    return self.files[filename].symbols

  return @[]

method getWorkspaceSymbols*(self: LanguageServerCTags, filename: string, query: string): Future[seq[Symbol]] {.async.} =
  var total: int = 0
  for file in self.files.values:
    total += file.symbols.len
  var allSymbols: seq[Symbol] = newSeqOfCap[language_server_base.Symbol](total)
  for file in self.files.values:
    allSymbols.add file.symbols
  return allSymbols

method getHover*(self: LanguageServerCTags, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  var res = ""
  let editors = self.documents.getEditors(filename)
  for editor in editors:
    if editor of TextDocumentEditor and editor.getDocument() != nil:
      let d = editor.getDocument().TextDocument
      let s = d.getLanguageWordBoundary(location)
      let funcText = d.contentString(s)

      for file in self.files.values:
        for def in file.definitions:
          if funcText == def.name:
            if res.len > 0:
              res.add "\n"
            res.add &"{def.kindRaw} {def.signature} - {def.path}"

      break

  if res.len > 0:
    return res.some
  else:
    return string.none

method getSignatureHelp*(self: LanguageServerCTags, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
  var res = newSeq[lsp_types.SignatureInformation]()
  let editors = self.documents.getEditors(filename)
  for editor in editors:
    if editor of TextDocumentEditor and editor.getDocument() != nil:
      let e = editor.TextDocumentEditor
      let d = editor.getDocument().TextDocument
      let move = d.config.get("lsp.ctags.callee-move", "(ts 'call.func') (last) (inclusive)")
      let s = e.getSelectionForMove(location, move)
      let funcText = d.contentString(s)

      for file in self.files.values:
        for def in file.definitions:
          if def.signature.len > 0 and (funcText == def.name or funcText.endsWith("." & def.name)):
            res.add lsp_types.SignatureInformation(
              label: def.signature,
              parameters: @[lsp_types.ParameterInformation(label: newJString(def.signature))]
            )

      break

  return @[lsp_types.SignatureHelpResponse(
    signatures: res,
  )].success

method getCompletions*(self: LanguageServerCTags, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
  var t2 = startTimer()
  var t = startTimer()
  var total: int = 0
  for file in self.files.values:
    total += file.symbols.len

  template maybeSleep(): untyped =
    if t.elapsed.ms > 3:
      try:
        await sleepAsync(5.milliseconds)
        t = startTimer()
      except:
        discard

  var completionText = ""
  var importedFiles = seq[string].none
  if self.documents.getDocument(filename).getSome(doc) and doc of TextDocument:
    let s = doc.TextDocument.getLanguageWordBoundary(location)
    completionText = doc.TextDocument.contentString(s)
    let tsImportedFiles = await doc.TextDocument.getImportedFiles()
    if tsImportedFiles.isSome:
      importedFiles = tsImportedFiles
      try:
        for autoImport in doc.TextDocument.config.get("lsp.ctags.auto-imports", newSeq[string]()):
          importedFiles.get.add autoImport
      except CatchableError:
        discard

  var importedFilePaths = initHashSet[string]()
  if importedFiles.isSome:
    importedFilePaths.incl filename
    for f in importedFiles.get:
      self.importMap.withValue(f, paths):
        for path in paths[]:
          importedFilePaths.incl path
          maybeSleep()

  var res: seq[CompletionItem] = newSeqOfCap[lsp_types.CompletionItem](total)
  for (path, file) in self.files.pairs:
    maybeSleep()

    res.add file.moduleCompletions
    if importedFilePaths.len > 0 and not importedFilePaths.contains(path):
      continue

    res.add file.completions

  # debugf"{t2.elapsed.ms} ms, {res.len} completions"
  return lsp_types.CompletionList(
    items: res,
  ).success
