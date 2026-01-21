import std/[strformat, strutils, os, sets, tables, options, json]
import misc/[delayed_task, id, custom_logger, util, custom_async, timer, async_process, event, response, rope_utils, arena, array_view]
import text/language/[language_server_base, lsp_types]
import nimsumtree/[arc, rope]
import service, event_service, language_server_dynamic, document_editor, document, config_provider, vfs, vfs_service
import text/[treesitter_type_conv]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

const currentSourcePath2 = currentSourcePath()
include module_base

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

  LanguageServerCTags* = ref object of LanguageServerDynamic
    services: Services
    config: ConfigStore
    documents: DocumentEditorService
    eventBus: EventService
    vfs: Arc[VFS2]
    commandHistory*: seq[string]

    importMap: Table[string, HashSet[string]]    # Map from import name to file paths
    files: Table[string, CTagsSymbols]  # Code file path to parsed ctags
    ctags: Table[string, CTagsFile]    # CTags file path to parsed ctags
    fileToCTags: Table[string, string] # Code file path to ctags file path
    workspaceSymbols: seq[Symbol]

when implModule:
  import language_server_component, config_component, move_component, text_component, treesitter_component, language_component

  proc c_malloc*(size: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
  proc c_calloc*(nmemb, size: csize_t): pointer {.importc: "calloc", header: "<stdlib.h>".}
  proc c_free*(p: pointer) {.importc: "free", header: "<stdlib.h>".}
  proc c_realloc*(p: pointer, newsize: csize_t): pointer {.importc: "realloc", header: "<stdlib.h>".}

  var abc = c_malloc(1)
  c_free(abc)
  abc = c_calloc(1, 1)
  abc = c_realloc(abc, 2)

  logCategory "language_server_ctags"

  proc getDefinitions(self: LanguageServerCTags, doc: Document, location: Cursor): Future[seq[Definition]] {.async.} =
    let moves = doc.getMoveComponent().getOr:
      return @[]
    let text = doc.getTextComponent().getOr:
      return @[]

    let s = moves.applyMove(location.toSelection.toRange, "language-word")
    let wordText = text.content(s)
    var res: seq[Definition]
    for file in self.files.values:
      for def in file.symbols:
        if (def.name.len > 0 and def.name == wordText) or (def.name == wordText):
          res.add Definition(
            location: def.location,
            filename: if def.filename.len > 0: def.filename else: $def.filename)
    return res

  proc ctagsGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerCTags
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.getDefinitions(doc, location)
    return @[]

  proc ctagsGetDeclaration*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerCTags
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.getDefinitions(doc, location)
    return @[]

  proc ctagsGetImplementation*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerCTags
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.getDefinitions(doc, location)
    return @[]

  proc ctagsGetTypeDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerCTags
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.getDefinitions(doc, location)
    return @[]

  proc ctagsGetReferences*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerCTags
    if self.documents.getDocumentByPath(filename).getSome(doc):
      return await self.getDefinitions(doc, location)
    return @[]

  proc ctagsGetSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerCTags
    if filename in self.files:
      return self.files[filename].symbols

    return @[]

  proc ctagsGetWorkspaceSymbols*(self: LanguageServerDynamic, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerCTags
    var total: int = 0
    for file in self.files.values:
      total += file.symbols.len
    var allSymbols: seq[Symbol] = newSeqOfCap[language_server_base.Symbol](total)
    for file in self.files.values:
      allSymbols.add file.symbols
    return allSymbols

  proc ctagsGetHover*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] {.async.} =
    let self = self.LanguageServerCTags
    var res = ""
    if self.documents.getDocumentByPath(filename).getSome(doc):
      let moves = doc.getMoveComponent().getOr:
        return
      let text = doc.getTextComponent().getOr:
        return

      let s = moves.applyMove(location.toSelection.toRange, "language-word")
      let funcText = text.content(s)

      for file in self.files.values:
        for def in file.definitions:
          if funcText == def.name:
            if res.len > 0:
              res.add "\n"
            res.add &"{def.kindRaw} {def.signature} - {def.path}"

    if res.len > 0:
      return res.some
    else:
      return string.none

  proc ctagsGetSignatureHelp*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.async.} =
    let self = self.LanguageServerCTags
    var res = newSeq[lsp_types.SignatureInformation]()
    if self.documents.getDocumentByPath(filename).getSome(doc):
      let config = doc.getConfigComponent().getOr:
        return
      let moves = doc.getMoveComponent().getOr:
        return
      let text = doc.getTextComponent().getOr:
        return


      let move = config.get("lsp.ctags.callee-move", "(ts 'call.func') (last) (inclusive)")
      let s = moves.applyMove(@[location.toSelection.toRange], move)
      if s.len == 0:
        return
      let funcText = text.content(s[0])

      for file in self.files.values:
        for def in file.definitions:
          if def.signature.len > 0 and (funcText == def.name or funcText.endsWith("." & def.name)):
            res.add lsp_types.SignatureInformation(
              label: def.signature,
              parameters: @[lsp_types.ParameterInformation(label: newJString(def.signature))]
            )

    return @[lsp_types.SignatureHelpResponse(
      signatures: res,
    )].success

  proc getImportedFiles*(treesitter: TreesitterComponent, text: TextComponent): Future[Option[seq[string]]] {.async.} =
    result = seq[string].none
    if treesitter.currentTree.isNil:
      return

    let query = await treesitter.query("imports")
    if query.isNone or treesitter.currentTree.isNil:
      return

    let endPoint = text.content.endPoint
    var arena = initArena()

    var res = newSeq[string]()
    for match in query.get.matches(treesitter.currentTree.root, tsRange(tsPoint(0, 0), tsPoint(endPoint.row.int, endPoint.column.int)), arena):
      for capture in match.captures:
        var sel = capture.node.getRange().toRange
        if capture.name == "import":
          res.add text.content(sel, false)

    return res.some

  proc ctagsGetCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
    let self = self.LanguageServerCTags

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
    if self.documents.getDocumentByPath(filename).getSome(doc):
      let moves = doc.getMoveComponent().getOr:
        return
      let text = doc.getTextComponent().getOr:
        return
      let ts = doc.getTreesitterComponent().getOr:
        return

      let s = moves.applyMove(location.toSelection.toRange, "language-word")
      let config = doc.getConfigComponent().getOr:
        return

      completionText = text.content(s)
      let tsImportedFiles = await getImportedFiles(ts, text)
      if tsImportedFiles.isSome:
        importedFiles = tsImportedFiles
        try:
          for autoImport in config.get("lsp.ctags.auto-imports", newSeq[string]()):
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

  proc newLanguageServerCTags*(services: Services): LanguageServerCTags =
    result = new LanguageServerCTags
    result.name = "ctags"
    result.services = services
    result.documents = services.getService(DocumentEditorService).get
    result.vfs = services.getService(VFSService).get.vfs2
    result.config = services.getService(ConfigService).get.runtime
    result.eventBus = services.getService(EventService).get
    result.refetchWorkspaceSymbolsOnQueryChange = false
    result.capabilities.completionProvider = lsp_types.CompletionOptions().some

    result.getSymbolsImpl = ctagsGetSymbols
    result.getDefinitionImpl = ctagsGetDefinition
    result.getDeclarationImpl = ctagsGetDeclaration
    result.getImplementationImpl = ctagsGetImplementation
    result.getTypeDefinitionImpl = ctagsGetTypeDefinition
    result.getReferencesImpl = ctagsGetReferences
    result.getWorkspaceSymbolsImpl = ctagsGetWorkspaceSymbols
    result.getCompletionsImpl = ctagsGetCompletions
    result.getHoverImpl = ctagsGetHover
    result.getSignatureHelpImpl = ctagsGetSignatureHelp

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

      log lvlInfo, &"Loaded {total} symbols for {seenFiles.len} files from '{path}'"
      self.ctags[path].files = seenFiles

    except CatchableError as e:
      log lvlWarn, &"Failed to read ctags file '{path}': {e.msg}"

  proc loadCTags(self: LanguageServerCTags, path: string) {.async.} =
    # asm "int3"
    let f = await self.vfs.read(path)
    await self.loadCTags(path, f)

  proc loadCTagsCommand(self: LanguageServerCTags, languageId: string, path: string) {.async.} =
    try:
      let args = @["-f", "-", "-p", self.vfs.localize(path)]
      let ctagsGeneratorPath = self.config.get(&"lang.{languageId}.lsp.ctags.generator", "ctags")
      let ctagsGeneratorPathLocal = self.vfs.localize(ctagsGeneratorPath)
      let output = runProcessAsyncOutput(ctagsGeneratorPathLocal, args, maxLines=100000).await.output
      self.ctags[path] = CTagsFile(path: path)
      await self.loadCTags(path, output)
    except CatchableError as e:
      log lvlWarn, &"Failed to load ctags from file using command: '{path}': {e.msg}"

  proc updateCTagFile(self: LanguageServerCTags, path: string) {.async.} =
    try:
      if path notin self.ctags:
        discard self.vfs.watch(path, proc(events: seq[PathEvent]) =
          if self.ctags[path].updateTask != nil:
            self.ctags[path].updateTask.reschedule()
        )
      self.ctags[path] = CTagsFile(path: path)
      self.ctags[path].updateTask = startDelayedPaused(500, repeat=false):
        asyncSpawn self.loadCTags(path)

      await self.loadCTags(path)
    except CatchableError as e:
      log lvlWarn, &"Failed to update ctag file '{path}': {e.msg}"

  proc updateCTagFiles(self: LanguageServerCTags) {.async.} =
    try:
      let paths = self.config.get("lsp.ctags.paths", newSeq[string]())
      for path in paths:
        if path in self.ctags:
          continue
        asyncSpawn self.updateCTagFile(path)
    except CatchableError as e:
      log lvlWarn, &"Failed to update ctag files: {e.msg}"

  proc init_module_language_server_ctags*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_language_server_ctags: no services found"
      return

    var ls: LanguageServerCTags = newLanguageServerCTags(services)

    let events = services.getService(EventService)
    let documents = services.getService(DocumentEditorService).get

    proc handleDocumentSaved(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.DocumentId
        if documents.getDocument(id).getSome(doc):
          let language = doc.getLanguageComponent().getOr:
            return
          if doc.getLanguageServerComponent().getSome(comp):
            if comp.hasLanguageServer(ls):
              asyncSpawn ls.loadCTagsCommand(language.languageId, doc.filename)
      except CatchableError as e:
        log lvlWarn, &"Error: {e.msg}"
    events.get.listen(newId(), "document/*/saved", handleDocumentSaved)

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

          let languages = config.get("lsp.ctags.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlWarn, &"Error: {e.msg}"
    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)

    discard ls.config.onConfigChanged.subscribe proc(key: string) =
      if key == "" or key == "lsp" or key == "lsp.ctags" or key == "lsp.ctags.paths":
        asyncSpawn ls.updateCTagFiles()

    asyncSpawn ls.updateCTagFiles()
