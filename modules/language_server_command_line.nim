#use input_handler layout
import std/[options, tables, strutils, json]
import text/language/[language_server_base]
import service

const currentSourcePath2 = currentSourcePath()
include module_base

type
  LanguageServerCommandLine* = ref object of LanguageServer
    files: Table[string, string]
    commandHistory*: seq[string]

  LanguageServerCommandLineService* = ref object of DynamicService
    languageServer*: LanguageServerCommandLine

func serviceName*(_: typedesc[LanguageServerCommandLineService]): string = "LanguageServerCommandLineService"

when implModule:
  import nimsumtree/rope
  import misc/[custom_logger, custom_async, util, response, rope_utils, event, myjsonutils]
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
  import text/language/[lsp_types]
  import dispatch_tables, document_editor, layout/layout, input_handler/input_handler, config_provider, command_service
  import document, text_component, move_component, language_component, language_server_component, session

  logCategory "language-server-command-line"

  proc newLanguageServerCommandLine(): LanguageServerCommandLine {.gcsafe, raises: [].}

  proc newLanguageServerCommandLineService(): LanguageServerCommandLineService =
    let self = LanguageServerCommandLineService()
    self.languageServer = newLanguageServerCommandLine()
    let documents = getServiceChecked(DocumentEditorService)
    discard documents.onEditorRegistered.subscribe proc(editor: DocumentEditor) =
      let doc = editor.currentDocument
      let language = doc.getLanguageComponent().getOr:
        return
      let lsps = doc.getLanguageServerComponent().getOr:
        return
      let languages = getServiceChecked(ConfigService).runtime.get("lsp.command-line.languages", @["command-line"])
      if language.languageId in languages and not lsps.hasLanguageServer(self.languageServer):
        discard lsps.addLanguageServer(self.languageServer)

    let session = getServiceChecked(SessionService)
    proc save(): JsonNode =
      return self.languageServer.commandHistory.toJson()

    proc load(data: JsonNode) =
      try:
        self.languageServer.commandHistory = data.jsonTo(seq[string])
      except Exception as e:
        log lvlError, &"Failed to restore command line history: {e.msg}"

    session.addSaveHandler "command-line-history", save, load
    return self

  proc lspCommandLineGetDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
    let self = self.LanguageServerCommandLine
    return newSeq[Definition]()

  proc lspCommandLineGetCompletions*(self: LanguageServer, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
    let self = self.LanguageServerCommandLine
    let layout = getServiceChecked(LayoutService)
    let events = getServiceChecked(EventHandlerService)
    let documents = getServiceChecked(DocumentEditorService)

    var completions = newSeq[CompletionItem]()

    var useActive = false
    if documents.getDocumentByPath(filename).getSome(document):
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
            if events.commandInfos.getInfos(value.name).getSome(infos):
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
      let commands = getServiceChecked(CommandService)
      {.gcsafe.}:
        for (name, command) in commands.commands.pairs:
          var docs = ""
          if events.commandInfos.getInfos(name).getSome(infos):
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

  proc lspCommandLineGetSymbols*(self: LanguageServer, filename: string): Future[seq[Symbol]] {.async.} =
    let self = self.LanguageServerCommandLine
    var completions: seq[Symbol]
    return completions

  proc lspCommandLineGetHover*(self: LanguageServer, filename: string, location: Cursor): Future[Option[string]] {.async.} =
    let self = self.LanguageServerCommandLine
    return string.none

  proc lspCommandLineGetInlayHints*(self: LanguageServer, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
    let self = self.LanguageServerCommandLine
    return success[seq[language_server_base.InlayHint]](@[])

  proc lspCommandLineGetDiagnostics*(self: LanguageServer, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
    let self = self.LanguageServerCommandLine
    return success[seq[lsp_types.Diagnostic]](@[])

  proc newLanguageServerCommandLine(): LanguageServerCommandLine =
    var server = new LanguageServerCommandLine
    server.name = "command-line"
    server.capabilities.completionProvider = lsp_types.CompletionOptions().some
    server.getDefinitionImpl = lspCommandLineGetDefinition
    server.getCompletionsImpl = lspCommandLineGetCompletions
    server.getSymbolsImpl = lspCommandLineGetSymbols
    server.getHoverImpl = lspCommandLineGetHover
    server.getInlayHintsImpl = lspCommandLineGetInlayHints
    server.getDiagnosticsImpl = lspCommandLineGetDiagnostics
    return server

  proc init_module_language_server_command_line*() {.cdecl, exportc, dynlib.} =
    getServices().addService(newLanguageServerCommandLineService())
