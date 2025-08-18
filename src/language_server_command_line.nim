import std/[options, tables, sequtils, strutils]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response, rope_utils, event]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import dispatch_tables, document_editor, service, layout, events, config_provider, command_service
import text/text_document

logCategory "language-server-command-line"

type
  LanguageServerCommandLine* = ref object of LanguageServer
    services: Services
    commands: CommandService
    documents: DocumentEditorService
    events: EventHandlerService
    files: Table[string, string]
    commandHistory*: seq[string]

  LanguageServerCommandLineService* = ref object of Service
    languageServer*: LanguageServerCommandLine
    config: ConfigStore

proc newLanguageServerCommandLine(services: Services): LanguageServerCommandLine =
  var server = new LanguageServerCommandLine
  server.name = "command-line"
  server.services = services
  server.commands = services.getService(CommandService).get
  server.events = services.getService(EventHandlerService).get
  server.documents = services.getService(DocumentEditorService).get
  server.capabilities.completionProvider = lsp_types.CompletionOptions().some
  return server

func serviceName*(_: typedesc[LanguageServerCommandLineService]): string = "LanguageServerCommandLineService"

addBuiltinService(LanguageServerCommandLineService, DocumentEditorService, EventHandlerService, CommandService)

method init*(self: LanguageServerCommandLineService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.languageServer = newLanguageServerCommandLine(self.services)
  self.config = self.services.getService(ConfigService).get.runtime
  discard self.languageServer.documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
    let doc = editor.getDocument()
    if doc of TextDocument:
      let textDoc = doc.TextDocument
      let languages = self.config.get("lsp.command-line.languages", newSeq[string]())
      if textDoc.languageId in languages and not textDoc.hasLanguageServer(self.languageServer):
        discard textDoc.addLanguageServer(self.languageServer)
  return ok()

method getDefinition*(self: LanguageServerCommandLine, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
  return newSeq[Definition]()

method getCompletions*(self: LanguageServerCommandLine, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  let layout = self.services.getService(LayoutService).get

  var completions: seq[CompletionItem]

  var useActive = false
  if self.documents.getDocument(filename).getSome(document) and document of TextDocument:
    let textDoc = document.TextDocument
    if textDoc.rope.startsWith(".") or document.TextDocument.rope.startsWith("^"):
      useActive = true

    let rope = textDoc.rope

    if location.line >= rope.lines:
      return CompletionList(items: completions).success

    if location.column > rope.lineLen(location.line):
      return CompletionList(items: completions).success

    let spaceIndex = rope.slice(point(location.line, 0)...location.toPoint).find(" ")
    if spaceIndex >= 0:
      return CompletionList(items: completions).success

  if useActive:
    let currentNamespace = if layout.popups.len > 0:
      "popup.selector".some
    else:
      layout.getActiveViewEditor().mapIt(it.getNamespace)
    {.gcsafe.}:
      for table in activeDispatchTables.mitems:
        if not table.global and table.namespace.some != currentNamespace:
          continue

        for value in table.functions.values:

          var docs = ""
          if self.events.commandInfos.getInfos(value.name).getSome(infos):
            for i, info in infos:
              if i > 0:
                docs.add "\n"
              docs.add &"[{info.context}] {info.keys} -> {info.command}"
            docs.add "\n\n"

          docs.add value.docs

          completions.add CompletionItem(
            label: value.name,
            # scope: table.scope,
            kind: CompletionKind.Function,
            detail: value.signature.some,
            documentation: CompletionItemDocumentationVariant.init(docs).some,
          )

      for (name, command) in self.commands.activeCommands.pairs:
        var docs = ""
        if self.events.commandInfos.getInfos(name).getSome(infos):
          for i, info in infos:
            if i > 0:
              docs.add "\n"
            docs.add &"[{info.context}] {info.keys} -> {info.command}"
          docs.add "\n\n"

        docs.add command.description

        completions.add CompletionItem(
          label: name,
          kind: CompletionKind.Function,
          detail: command.signature.some,
          documentation: CompletionItemDocumentationVariant.init(docs).some,
        )

  else:
    {.gcsafe.}:
      for (name, command) in self.commands.commands.pairs:
        var docs = ""
        if self.events.commandInfos.getInfos(name).getSome(infos):
          for i, info in infos:
            if i > 0:
              docs.add "\n"
            docs.add &"[{info.context}] {info.keys} -> {info.command}"
          docs.add "\n\n"

        docs.add command.description

        completions.add CompletionItem(
          label: name,
          kind: CompletionKind.Function,
          detail: command.signature.some,
          documentation: CompletionItemDocumentationVariant.init(docs).some,
        )

  for h in self.commandHistory:
    completions.add CompletionItem(
      label: h,
      kind: CompletionKind.Function,
    )

  return CompletionList(items: completions).success

method getSymbols*(self: LanguageServerCommandLine, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]
  return completions

method getHover*(self: LanguageServerCommandLine, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  return string.none

method getInlayHints*(self: LanguageServerCommandLine, filename: string, selection: Selection):
    Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
  return success[seq[language_server_base.InlayHint]](@[])

method getDiagnostics*(self: LanguageServerCommandLine, filename: string):
    Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  return success[seq[lsp_types.Diagnostic]](@[])
