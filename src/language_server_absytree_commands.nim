import std/[options, tables, strutils]
import misc/[custom_logger, custom_async, util]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]
import platform/filesystem
import dispatch_tables

logCategory "language_server_absytree_commands"

type LanguageServerAbsytreeCommands* = ref object of LanguageServer
  files: Table[string, string]

proc newLanguageServerAbsytreeCommands*(): LanguageServer =
  var server = new LanguageServerAbsytreeCommands
  return server

method getDefinition*(self: LanguageServerAbsytreeCommands, filename: string, location: Cursor): Future[Option[Definition]] {.async.} =
  return Definition.none

method saveTempFile*(self: LanguageServerAbsytreeCommands, filename: string, content: string): Future[void] {.async.} =
  # debugf"LanguageServerAbsytreeCommands.saveTempFile '{filename}' '{content}'"
  self.files[filename] = content

method getCompletions*(self: LanguageServerAbsytreeCommands, languageId: string, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  await self.requestSave(filename, filename)

  var useActive = false
  if self.files.contains(filename):
    if self.files[filename].startsWith("."):
      useActive = true

  var completions: seq[CompletionItem]
  if useActive:
    for table in activeDispatchTables.mitems:
      for value in table.functions.values:
        completions.add CompletionItem(
          label: value.name,
          # scope: table.scope,
          kind: CompletionKind.Function,
          detail: value.signature.some,
          documentation: CompletionItemDocumentationVariant.init(value.docs).some,
        )
  else:
    for table in globalDispatchTables.mitems:
      for value in table.functions.values:
        completions.add CompletionItem(
          label: value.name,
          # scope: table.scope,
          kind: CompletionKind.Function,
          detail: value.signature.some,
          documentation: CompletionItemDocumentationVariant.init(value.docs).some,
        )

  return CompletionList(items: completions).success

method getSymbols*(self: LanguageServerAbsytreeCommands, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]
  return completions

method getHover*(self: LanguageServerAbsytreeCommands, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  return string.none

method getInlayHints*(self: LanguageServerAbsytreeCommands, filename: string, selection: Selection): Future[seq[language_server_base.InlayHint]] {.async.} =
  return newSeq[language_server_base.InlayHint]()