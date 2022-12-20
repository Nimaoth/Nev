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

