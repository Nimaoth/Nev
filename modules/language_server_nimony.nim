#use language_server_lsp language_server_regex event_service language_server_component language_server_ctags

const currentSourcePath2 = currentSourcePath()
include module_base

when implModule:
  import std/[options, json, strutils, os, tables]
  import nimsumtree/[arc, rope]
  import misc/[custom_logger, util, event, custom_async, response, rope_utils, jsonex, channel, async_process, timer]
  import workspace
  import vfs, vfs_service
  import document, language_server_component, config_component, language_component, move_component, text_component
  import language_server_lsp/language_server_lsp, language_server_regex, language_server_ctags
  import service, event_service, document_editor, config_provider
  import language_server
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  logCategory "language-server-nimony"

  type
    LanguageServerNimony* = ref object of LanguageServer
      services: Services
      config: ConfigStore
      documents: DocumentEditorService
      eventBus: EventService
      clangdDiagnosticsHandle: Id
      clangd: LanguageServer
      regexLs: LanguageServerRegex
      ctagsLs: LanguageServerCtags
      vfs*: VFS
      workspace*: Workspace
      fileCheckQueue: seq[string]
      processingFileChecks: bool
      diagnostics: Table[string, seq[language_server.LspDiagnostic]]

  proc readStderr(stderr: Arc[BaseChannel]): Future[void] {.gcsafe, async: (raises: []).} =
    try:
      var t = ""
      while true:
        let available = stderr.flushRead()
        if available == 0 and not stderr.isOpen:
          break
        t.setLen(available)
        if available > 0:
          discard stderr.read(t.toOpenArrayByte(0, t.high))
          log lvlWarn, &"[nimony] {t}"
        await sleepAsync(1.milliseconds)
    except CatchableError:
      discard

  proc runNimony(args: seq[string], workingDir: string): Future[(string, string)] {.async.} =
    var process = startAsyncProcess("nimony", args, killOnExit = true, autoStart = false, workingDir = workingDir)
    discard process.start()
    process.stdin.close()

    var stdoutResult = newStringOfCap(100)
    var buf = ""
    var ti = startTimer()
    while not process.stdout.atEnd:
      let available = process.stdout.flushRead()
      if available == 0:
        await sleepAsync(1.milliseconds)
        if not process.isAlive and process.stdout.flushRead() == 0:
          break
        continue
      buf.setLen(available)
      if available > 0:
        discard process.stdout.read(buf.toOpenArrayByte(0, buf.high))
        stdoutResult.add buf
      if ti.elapsed.ms > 5:
        await sleepAsync(1.milliseconds)

    var stderrResult = newStringOfCap(100)
    while not process.stderr.atEnd:
      let available = process.stderr.flushRead()
      if available == 0:
        await sleepAsync(1.milliseconds)
        if not process.isAlive and process.stderr.flushRead() == 0:
          break
        continue
      buf.setLen(available)
      if available > 0:
        discard process.stderr.read(buf.toOpenArrayByte(0, buf.high))
        stderrResult.add buf
      if ti.elapsed.ms > 5:
        await sleepAsync(1.milliseconds)

    return (stdoutResult, stderrResult)

  proc parseNimonyDiagnostics(self: LanguageServerNimony, output: string, workspaceFolder: string) =
    echo output
    echo "---------------"
    var diagnostics = initTable[string, seq[language_server.LspDiagnostic]]()
    var currentDiagnostic = language_server.LspDiagnostic()
    var hasCurrent = false
    var filename = ""

    proc flushCurrentDiagnostic() =
      if hasCurrent and filename != "":
        echo "+++ new diagnostic for ", filename, ": ", currentDiagnostic
        diagnostics.mgetOrPut(filename, @[]).add currentDiagnostic
        currentDiagnostic = language_server.LspDiagnostic()
        hasCurrent = false

    for l in output.splitLines:
      echo l

      var startedDiagnostic = false
      var index = -1
      if (index = l.find("Error: "); index != -1):
        flushCurrentDiagnostic()
        currentDiagnostic.severity = DiagnosticSeverity.Error.some
        startedDiagnostic = true
      elif (index = l.find("Warning: "); index != -1):
        flushCurrentDiagnostic()
        currentDiagnostic.severity = DiagnosticSeverity.Warning.some
        startedDiagnostic = true
      elif (index = l.find("Trace: "); index != -1):
        flushCurrentDiagnostic()
        currentDiagnostic.severity = DiagnosticSeverity.Hint.some
        startedDiagnostic = true

      if index > 0:
        hasCurrent = true
        currentDiagnostic.message = l[index..^1]

      if startedDiagnostic:
        let fileInfo = l[0..<index]
        let lineInfoStart = fileInfo.rfind('(')
        if lineInfoStart != -1:
          let lineInfo = fileInfo[(lineInfoStart + 1)..< ^2].split(", ")
          let file = fileInfo[0..<lineInfoStart]
          let absolutePath = if isAbsolute(file):
            file.normalizePathUnix
          else:
            (workspaceFolder // file)
          filename = "file:///" & absolutePath
          let line = lineInfo[0].parseInt - 1
          let col = lineInfo[1].parseInt - 1
          currentDiagnostic.`range` = language_server.Range(
            start: language_server.Position(
              line: line,
              character: col
            ),
            `end`: language_server.Position(
              line: line,
              character: col + 1
            ),
          )
      elif hasCurrent:
        echo "context: ", l
        currentDiagnostic.message.add "\n" & l

      else:
        discard

    flushCurrentDiagnostic()

    for file in self.diagnostics.keys:
      if file notin diagnostics:
        # clear existing diagnostics
        self.onDiagnostics.invoke PublicDiagnosticsParams(uri: file, diagnostics: @[])

    self.diagnostics = diagnostics
    for file, d in self.diagnostics.pairs:
      self.onDiagnostics.invoke PublicDiagnosticsParams(
        uri: file,
        diagnostics: d,
      )

  proc processFileChecks(self: LanguageServerNimony) {.async.} =
    self.processingFileChecks = true
    defer:
      self.processingFileChecks = false

    while self.fileCheckQueue.len > 0:
      let file = self.fileCheckQueue.pop()
      let filename = self.vfs.localize(file)
      let filenameRel = self.workspace.getRelativePathSync(filename).get(filename)
      var workspaceFolder = filename
      workspaceFolder.removeSuffix(filenameRel)
      let res = await runNimony(@["check", filenameRel.quoteShell], workspaceFolder)
      self.parseNimonyDiagnostics(res[0] & "\n" & res[1], workspaceFolder)

  proc enqueueFileCheck(self: LanguageServerNimony, document: Document) =
    self.fileCheckQueue.add(document.filename)
    if not self.processingFileChecks:
      asyncSpawn self.processFileChecks()

  proc getNimonyUsages(self: LanguageServerNimony, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let filename = self.vfs.localize(filename)
    let filenameRel = self.workspace.getRelativePathSync(filename).get(filename)
    var workspaceFolder = filename
    workspaceFolder.removeSuffix(filenameRel)
    let arg = &"--usages:{filenameRel},{location.line + 1},{location.column + 1}"
    let res = await runNimony(@[arg.quoteShell, "check", filenameRel.quoteShell], workspaceFolder)
    for line in res[0].splitLines:
      if line.startsWith("use\t"):
        let parts = line.split("\t")
        if parts.len >= 8:
          try:
            # let x1 = parts[0]
            # let x2 = parts[1]
            let id = parts[2]
            # let x4 = parts[3]
            # let x5 = parts[4]
            let file = parts[5]
            let line = parts[6].parseInt
            let column = parts[7].parseInt
            var absolutePath = file
            if not isAbsolute(file):
              absolutePath = workspaceFolder // file
            result.add Definition(
              location: (line - 1, column),
              filename: absolutePath,
            )
          except:
            echo getCurrentExceptionMsg()
        else:
          echo line
      else:
        echo line
    echo "error:"
    echo res[1]

  proc getNimonyDefinition(self: LanguageServerNimony, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let filename = self.vfs.localize(filename)
    let filenameRel = self.workspace.getRelativePathSync(filename).get(filename)
    var workspaceFolder = filename
    workspaceFolder.removeSuffix(filenameRel)
    let arg = &"--def:{filenameRel},{location.line + 1},{location.column + 1}"
    let res = await runNimony(@[arg.quoteShell, "check", filenameRel.quoteShell], workspaceFolder)
    for line in res[0].splitLines:
      if line.startsWith("def\t"):
        let parts = line.split("\t")
        if parts.len >= 8:
          try:
            # let x1 = parts[0]
            # let x2 = parts[1]
            let id = parts[2]
            # let x4 = parts[3]
            # let x5 = parts[4]
            let file = parts[5]
            let line = parts[6].parseInt
            let column = parts[7].parseInt
            var absolutePath = file
            if not isAbsolute(file):
              absolutePath = workspaceFolder // file
            result.add Definition(
              location: (line - 1, column),
              filename: absolutePath,
            )
          except:
            echo getCurrentExceptionMsg()
        else:
          echo line
      else:
        echo line
    echo "error:"
    echo res[1]

  proc getClangd(self: LanguageServer): Future[Option[LanguageServer]] {.async.} =
    let self = self.LanguageServerNimony
    return LanguageServer.none

  proc nimonyGetDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerNimony
    result = await self.getNimonyDefinition(filename, location)
    if result.len == 0:
      if self.ctagsLs == nil:
        echo "no ctags :("
        return
      result = await self.ctagsLs.getDefinition(filename, location)

  proc nimonyGetDeclaration*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerNimony
    result = await self.getNimonyDefinition(filename, location)
    if result.len == 0:
      result = await self.ctagsLs.getDeclaration(filename, location)

  proc nimonyGetImplementation*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerNimony
    result = await self.getNimonyDefinition(filename, location)
    if result.len == 0:
      result = await self.ctagsLs.getImplementation(filename, location)

  proc nimonyGetTypeDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerNimony
    result = await self.getNimonyDefinition(filename, location)
    if result.len == 0:
      result = await self.ctagsLs.getTypeDefinition(filename, location)

  proc nimonyGetReferences*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerNimony
    result = await self.getNimonyUsages(filename, location)
    if result.len == 0:
      result = await self.regexLs.getReferences(filename, location)

  proc nimonyGetCompletions*(self: LanguageServer, filename: string, location: Cursor): Future[Response[language_server.CompletionList]] {.async.} =
    let self = self.LanguageServerNimony
    return await self.ctagsLs.getCompletions(filename, location)

  proc nimonyGetSymbols*(self: LanguageServer, filename: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerNimony
    return await self.ctagsLs.getSymbols(filename)

  proc nimonyGetWorkspaceSymbols*(self: LanguageServer, filename: string, query: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerNimony
    return await self.ctagsLs.getWorkspaceSymbols(filename, query)

  proc nimonyGetWorkspaceSymbolsRaw*(self: LanguageServer, filename: string, query: string): Future[seq[WorkspaceSymbolRaw]] {.async.} =
    let self = self.LanguageServerNimony
    return await self.ctagsLs.getWorkspaceSymbolsRaw(filename, query)

  proc nimonyResolveWorkspaceSymbol*(self: LanguageServer, symbol: language_server.WorkspaceSymbol): Future[Option[Definition]] {.async.} =
    let self = self.LanguageServerNimony
    return await self.ctagsLs.resolveWorkspaceSymbol(symbol)

  proc nimonyGetHover*(self: LanguageServer, filename: string, location: Cursor): Future[Option[string]] {.async.} =
    let self = self.LanguageServerNimony
    let clangd = (await self.getClangd()).getOr: return string.none
    return await clangd.getHover(filename, location)

  proc nimonyGetSignatureHelp*(self: LanguageServer, filename: string, location: Cursor): Future[Response[seq[language_server.SignatureHelpResponse]]] {.async.} =
    let self = self.LanguageServerNimony
    let clangd = (await self.getClangd()).getOr: return Response[seq[language_server.SignatureHelpResponse]].default
    return await clangd.getSignatureHelp(filename, location)

  proc nimonyGetInlayHints*(self: LanguageServer, filename: string, selection: Selection): Future[Response[seq[language_server.InlayHint]]] {.async.} =
    let self = self.LanguageServerNimony
    let clangd = (await self.getClangd()).getOr: return Response[seq[language_server.InlayHint]].default
    return await clangd.getInlayHints(filename, selection)

  proc nimonyGetDiagnostics*(self: LanguageServer, filename: string): Future[Response[seq[language_server.LspDiagnostic]]] {.async.} =
    let self = self.LanguageServerNimony
    let clangd = (await self.getClangd()).getOr: return Response[seq[language_server.LspDiagnostic]].default
    return await clangd.getDiagnostics(filename)

  proc nimonyGetCompletionTriggerChars*(self: LanguageServer): set[char] =
    return {'.', '>', ':'}

  proc nimonyGetCodeActions*(self: LanguageServer, filename: string, selection: Selection, diagnostics: seq[language_server.LspDiagnostic]): Future[Response[language_server.CodeActionResponse]] {.async.} =
    let self = self.LanguageServerNimony
    return Response[language_server.CodeActionResponse].default

  proc nimonyRename*(self: LanguageServer, filename: string, position: Cursor, newName: string): Future[Response[seq[language_server.WorkspaceEdit]]] {.async.} =
    let self = self.LanguageServerNimony
    return errorResponse[seq[language_server.WorkspaceEdit]](0, "nimony: rename not implemented")

  proc nimonyExecuteCommand*(self: LanguageServer, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
    let self = self.LanguageServerNimony
    return errorResponse[JsonNode](0, "nimony: executeCommand not implemented")

  proc nimonyConnect*(self: LanguageServer, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerNimony

  proc nimonyDisconnect*(self: LanguageServer, document: Document) {.gcsafe, raises: [].} =
    let self = self.LanguageServerNimony

  proc newLanguageServerNimony(services: Services): LanguageServerNimony =
    result = new LanguageServerNimony
    result.capabilities.completionProvider = language_server.CompletionOptions().some
    result.capabilities.diagnosticProvider = language_server.DiagnosticProviderVariant().some
    result.regexLs = newLanguageServerRegex(services)
    result.ctagsLs = getLanguageServerCTags()
    result.name = "nimony"
    result.services = services
    result.documents = services.getServiceChecked(DocumentEditorService)
    result.eventBus = services.getServiceChecked(EventService)
    result.config = services.getServiceChecked(ConfigService).runtime
    result.vfs = services.getServiceChecked(VFSService).vfs
    result.workspace = services.getServiceChecked(Workspace)
    result.refetchWorkspaceSymbolsOnQueryChange = true
    result.connectImpl = nimonyConnect
    result.disconnectImpl = nimonyDisconnect
    result.getDefinitionImpl = nimonyGetDefinition
    result.getDeclarationImpl = nimonyGetDeclaration
    result.getImplementationImpl = nimonyGetImplementation
    result.getTypeDefinitionImpl = nimonyGetTypeDefinition
    result.getReferencesImpl = nimonyGetReferences
    result.getCompletionsImpl = nimonyGetCompletions
    result.getSymbolsImpl = nimonyGetSymbols
    result.getWorkspaceSymbolsImpl = nimonyGetWorkspaceSymbols
    result.getWorkspaceSymbolsRawImpl = nimonyGetWorkspaceSymbolsRaw
    result.resolveWorkspaceSymbolImpl = nimonyResolveWorkspaceSymbol
    result.getHoverImpl = nimonyGetHover
    result.getSignatureHelpImpl = nimonyGetSignatureHelp
    result.getInlayHintsImpl = nimonyGetInlayHints
    result.getDiagnosticsImpl = nimonyGetDiagnostics
    result.getCompletionTriggerCharsImpl = nimonyGetCompletionTriggerChars
    result.getCodeActionsImpl = nimonyGetCodeActions
    result.renameImpl = nimonyRename
    result.executeCommandImpl = nimonyExecuteCommand

  var gls: LanguageServerNimony = nil

  proc init_module_language_server_nimony*() {.cdecl, exportc, dynlib.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, "Failed to initialize language_server_nimony: no services found"
      return

    var ls = newLanguageServerNimony(services)
    {.gcsafe.}:
      gls = ls

    let events = services.getService(EventService)
    let documents = services.getServiceChecked(DocumentEditorService)

    proc handleDocumentSaved(event, payload: string) {.gcsafe, raises: [].} =
      try:
        let id = payload.parseInt.DocumentId
        if documents.getDocument(id).getSome(doc):
          let language = doc.getLanguageComponent().getOr:
            return
          if doc.getLanguageServerComponent().getSome(comp):
            if comp.hasLanguageServer(ls):
              ls.enqueueFileCheck(doc)
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

          let languages = config.get("lsp.nimony.languages", newSeq[string]())
          if language.languageId in languages or "*" in languages:
            discard lsps.addLanguageServer(ls)
      except CatchableError as e:
        log lvlError, &"Error: {e.msg}"

    events.get.listen(newId(), "editor/*/registered", handleEditorRegistered)
