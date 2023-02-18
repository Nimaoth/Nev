import std/[options]
import custom_async
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

type LanguageServer* = ref object of RootObj
  discard

type SymbolType* = enum Unknown, Procedure, Function

type Definition* = object
  location*: Cursor
  filename*: string

type TextCompletion* = object
  name*: string
  scope*: string
  location*: Cursor
  filename*: string
  kind*: SymbolType
  typ*: string
  doc*: string

method start*(self: LanguageServer) {.base.} = discard
method stop*(self: LanguageServer) {.base.} = discard
method getDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[Option[Definition]] {.base.} = discard
method getCompletions*(self: LanguageServer, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.base.} = discard