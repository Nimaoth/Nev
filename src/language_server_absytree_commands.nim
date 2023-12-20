import std/[options, tables, strutils]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/language_server_base, util
import custom_logger, custom_async, dispatch_tables
import platform/filesystem

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

method getCompletions*(self: LanguageServerAbsytreeCommands, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.async.} =
  await self.requestSave(filename, filename)

  var useActive = false
  if self.files.contains(filename):
    if self.files[filename].startsWith("."):
      useActive = true

  var completions: seq[TextCompletion]
  if useActive:
    for table in activeDispatchTables.mitems:
      for value in table.functions.values:
        completions.add TextCompletion(
          name: value.name,
          scope: table.scope,
          kind: SymbolType.Function,
          typ: value.signature,
          doc: value.docs,
        )
  else:
    for table in globalDispatchTables.mitems:
      for value in table.functions.values:
        completions.add TextCompletion(
          name: value.name,
          scope: table.scope,
          kind: SymbolType.Function,
          typ: value.signature,
          doc: value.docs,
        )

  return completions

method getSymbols*(self: LanguageServerAbsytreeCommands, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]
  return completions
