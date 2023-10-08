import std/[options, tables]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import language/language_server_base, util
import custom_logger, custom_async, dispatch_tables
import platform/filesystem

type LanguageServerAbsytreeCommands* = ref object of LanguageServer
  discard

proc newLanguageServerAbsytreeCommands*(): LanguageServer =
  var server = new LanguageServerAbsytreeCommands
  return server

method getDefinition*(self: LanguageServerAbsytreeCommands, filename: string, location: Cursor): Future[Option[Definition]] {.async.} =
  return Definition.none

method getCompletions*(self: LanguageServerAbsytreeCommands, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.async.} =
  var completions: seq[TextCompletion]

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
