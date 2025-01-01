import std/[options, tables, strutils]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import dispatch_tables, document_editor, service, layout, events
import text/text_document

logCategory "language-server-command-line"

type LanguageServerCommandLine* = ref object of LanguageServer
  services: Services
  documents: DocumentEditorService
  events: EventHandlerService
  files: Table[string, string]
  commandHistory*: seq[string]

proc newLanguageServerCommandLine*(services: Services): LanguageServer =
  var server = new LanguageServerCommandLine
  server.services = services
  server.events = services.getService(EventHandlerService).get
  server.documents = services.getService(DocumentEditorService).get
  return server

method getDefinition*(self: LanguageServerCommandLine, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
  return newSeq[Definition]()

method getCompletions*(self: LanguageServerCommandLine, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  let layout = self.services.getService(LayoutService).get

  var useActive = false
  if self.documents.getDocument(filename).getSome(document) and document of TextDocument:
    if document.TextDocument.rope.startsWith("."):
      useActive = true

  var completions: seq[CompletionItem]
  if useActive:
    let currentNamespace = layout.getActiveViewEditor().mapIt(it.getNamespace)
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
      for table in globalDispatchTables.mitems:
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
