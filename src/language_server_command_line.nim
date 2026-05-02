import std/[options, tables, strutils]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response, rope_utils, event]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types], language_server_dynamic
import dispatch_tables, document_editor, service, layout/layout, events, config_provider, command_service
import document, text_component, move_component, language_component, language_server_component

logCategory "language-server-command-line"

type
  LanguageServerCommandLine* = ref object of LanguageServerDynamic
    services: Services
    commands: CommandServiceImpl
    documents: DocumentEditorService
    events: EventHandlerService
    files: Table[string, string]
    commandHistory*: seq[string]

  LanguageServerCommandLineService* = ref object of Service
    languageServer*: LanguageServerCommandLine
    config: ConfigStore

func serviceName*(_: typedesc[LanguageServerCommandLineService]): string = "LanguageServerCommandLineService"

addBuiltinService(LanguageServerCommandLineService, DocumentEditorService, EventHandlerService, CommandService)

proc newLanguageServerCommandLine(services: Services): LanguageServerCommandLine {.gcsafe, raises: [].}

method init*(self: LanguageServerCommandLineService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  self.languageServer = newLanguageServerCommandLine(self.services)
  self.config = self.services.getService(ConfigService).get.runtime
  discard self.languageServer.documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
    let doc = editor.currentDocument
    let language = doc.getLanguageComponent().getOr:
      return
    let lsps = doc.getLanguageServerComponent().getOr:
      return
    let languages = self.config.get("lsp.command-line.languages", newSeq[string]())
    if language.languageId in languages and not lsps.hasLanguageServer(self.languageServer):
      discard lsps.addLanguageServer(self.languageServer)
  return ok()

proc lspCommandLineGetDefinition*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let self = self.LanguageServerCommandLine
  return newSeq[Definition]()

proc lspCommandLineGetCompletions*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  let self = self.LanguageServerCommandLine
  let layout = self.services.getService(LayoutService).get

  var completions = newSeq[CompletionItem]()

  var useActive = false
  if self.documents.getDocument(filename).getSome(document):
    let text = document.getTextComponent().getOr:
      return CompletionList(items: completions).success

    if text.content.startsWith(".") or text.content.startsWith("^"):
      useActive = true

    if location.line >= text.content.lines:
      return CompletionList(items: completions).success

    if location.column > text.content.lineLen(location.line):
      return CompletionList(items: completions).success

    let spaceIndex = text.content.slice(point(location.line, 0)...location.toPoint).find(" ")
    if spaceIndex >= 0:
      return CompletionList(items: completions).success

  if useActive:
    let currentNamespace = if layout.popups.len > 0:
      "popup.selector".some
    else:
      layout.getActiveEditor(includeCommandLine = false).mapIt(it.namespace)
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

proc lspCommandLineGetSymbols*(self: LanguageServerDynamic, filename: string): Future[seq[Symbol]] {.async.} =
  let self = self.LanguageServerCommandLine
  var completions: seq[Symbol]
  return completions

proc lspCommandLineGetHover*(self: LanguageServerDynamic, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  let self = self.LanguageServerCommandLine
  return string.none

proc lspCommandLineGetInlayHints*(self: LanguageServerDynamic, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
  let self = self.LanguageServerCommandLine
  return success[seq[language_server_base.InlayHint]](@[])

proc lspCommandLineGetDiagnostics*(self: LanguageServerDynamic, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  let self = self.LanguageServerCommandLine
  return success[seq[lsp_types.Diagnostic]](@[])

proc newLanguageServerCommandLine(services: Services): LanguageServerCommandLine =
  var server = new LanguageServerCommandLine
  server.name = "command-line"
  server.services = services
  server.commands = services.getService(CommandServiceImpl).get
  server.events = services.getService(EventHandlerService).get
  server.documents = services.getService(DocumentEditorService).get
  server.capabilities.completionProvider = lsp_types.CompletionOptions().some
  server.getDefinitionImpl = lspCommandLineGetDefinition
  server.getCompletionsImpl = lspCommandLineGetCompletions
  server.getSymbolsImpl = lspCommandLineGetSymbols
  server.getHoverImpl = lspCommandLineGetHover
  server.getInlayHintsImpl = lspCommandLineGetInlayHints
  server.getDiagnosticsImpl = lspCommandLineGetDiagnostics
  return server
