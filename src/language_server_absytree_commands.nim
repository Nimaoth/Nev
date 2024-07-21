import std/[options, tables, strutils]
import misc/[custom_logger, custom_async, util, response]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import platform/filesystem
import dispatch_tables, app_interface, document_editor, command_info

logCategory "language_server_absytree_commands"

type LanguageServerAbsytreeCommands* = ref object of LanguageServer
  app: AppInterface
  files: Table[string, string]
  commandInfos: CommandInfos

proc newLanguageServerAbsytreeCommands*(app: AppInterface, commandInfos: CommandInfos): LanguageServer =
  var server = new LanguageServerAbsytreeCommands
  server.app = app
  server.commandInfos = commandInfos
  return server

method getDefinition*(self: LanguageServerAbsytreeCommands, filename: string, location: Cursor):
    Future[seq[Definition]] {.async.} =
  return newSeq[Definition]()

method saveTempFile*(self: LanguageServerAbsytreeCommands, filename: string, content: string): Future[void] {.async.} =
  # debugf"LanguageServerAbsytreeCommands.saveTempFile '{filename}' '{content}'"
  self.files[filename] = content

method getCompletions*(self: LanguageServerAbsytreeCommands, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
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

method getSymbols*(self: LanguageServerAbsytreeCommands, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]
  return completions

method getHover*(self: LanguageServerAbsytreeCommands, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  return string.none

method getInlayHints*(self: LanguageServerAbsytreeCommands, filename: string, selection: Selection): Future[seq[language_server_base.InlayHint]] {.async.} =
  return newSeq[language_server_base.InlayHint]()