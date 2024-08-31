import std/[options, tables, strutils]
import misc/[custom_logger, custom_async, util, response]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import platform/filesystem
import dispatch_tables, app_interface, document_editor, command_info

logCategory "language_server_absytree_commands"

type LanguageServerCommandLine* = ref object of LanguageServer
  app: AppInterface
  files: Table[string, string]
  commandInfos: CommandInfos

proc newLanguageServerCommandLine*(app: AppInterface, commandInfos: CommandInfos): LanguageServer =
  var server = new LanguageServerCommandLine
  server.app = app
  server.commandInfos = commandInfos
  return server

method getDefinition*(self: LanguageServerCommandLine, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
  return newSeq[Definition]()

method saveTempFile*(self: LanguageServerCommandLine, filename: string, content: string): Future[void] {.async.} =
  # debugf"LanguageServerCommandLine.saveTempFile '{filename}' '{content}'"
  self.files[filename] = content

method getCompletions*(self: LanguageServerCommandLine, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  await self.requestSave(filename, filename)

  var useActive = false
  if self.files.contains(filename):
    let commandName = self.files[filename]
    if commandName.startsWith("."):
      useActive = true

  var completions: seq[CompletionItem]
  if useActive:
    let currentNamespace = self.app.getActiveEditor().mapIt(it.getNamespace)
    for table in activeDispatchTables.mitems:
      if not table.global and table.namespace.some != currentNamespace:
        continue

      for value in table.functions.values:

        var docs = ""
        if self.commandInfos.getInfos(value.name).getSome(infos):
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
    for table in globalDispatchTables.mitems:
      for value in table.functions.values:
        var docs = ""
        if self.commandInfos.getInfos(value.name).getSome(infos):
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
