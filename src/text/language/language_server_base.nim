import std/[options, json]
import misc/[custom_async, custom_logger, event, response]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import workspaces/workspace
import document

from lsp_types as lsp_types import CompletionItem

{.push gcsafe.}
{.push raises: [].}

type LanguageServer* = ref object of RootObj
  onMessage*: Event[tuple[verbosity: lsp_types.MessageType, message: string]]
  onDiagnostics*: Event[lsp_types.PublicDiagnosticsParams]

type SymbolType* {.pure.} = enum
  Unknown = 0
  File = 1
  Module = 2
  Namespace = 3
  Package = 4
  Class = 5
  Method = 6
  Property = 7
  Field = 8
  Constructor = 9
  Enum = 10
  Interface = 11
  Function = 12
  Variable = 13
  Constant = 14
  String = 15
  Number = 16
  Boolean = 17
  Array = 18
  Object = 19
  Key = 20
  Null = 21
  EnumMember = 22
  Struct = 23
  Event = 24
  Operator = 25
  TypeParameter = 26

type InlayHintKind* = enum Type, Parameter

type TextEdit* = object
  selection*: Selection
  newText*: string


type Definition* = object
  location*: Cursor
  filename*: string

type Symbol* = object
  location*: Cursor
  name*: string
  symbolType*: SymbolType
  filename*: string
  score*: Option[float]

type InlayHint* = object
  location*: Cursor
  label*: string # | InlayHintLabelPart[] # todo
  kind*: Option[InlayHintKind]
  textEdits*: seq[TextEdit]
  tooltip*: Option[string] # | MarkupContent # todo
  paddingLeft*: bool
  paddingRight*: bool
  data*: Option[JsonNode]

type Diagnostic* = object
  selection*: Selection
  severity*: Option[lsp_types.DiagnosticSeverity]
  code*: Option[JsonNode]
  codeDescription*: lsp_types.CodeDescription
  source*: Option[string]
  message*: string
  tags*: seq[lsp_types.DiagnosticTag]
  relatedInformation*: Option[seq[lsp_types.DiagnosticRelatedInformation]]
  data*: Option[JsonNode]
  removed*: bool = false

var getOrCreateLanguageServer*: proc(languageId: string, filename: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none, workspace = Workspace.none): Future[Option[LanguageServer]] {.gcsafe, raises: [].} = nil

method start*(self: LanguageServer): Future[void] {.base, gcsafe, raises: [].} = discard
method stop*(self: LanguageServer) {.base, gcsafe, raises: [].} = discard
method deinit*(self: LanguageServer) {.base, gcsafe, raises: [].} = discard
method connect*(self: LanguageServer, document: Document) {.base, gcsafe, raises: [].} = discard
method disconnect*(self: LanguageServer, document: Document) {.base, gcsafe, raises: [].} = discard
method getDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = discard
method getDeclaration*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = discard
method getImplementation*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = discard
method getTypeDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = discard
method getReferences*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = discard
method switchSourceHeader*(self: LanguageServer, filename: string): Future[Option[string]] {.base, gcsafe, raises: [].} = discard
method getCompletions*(self: LanguageServer, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.base, gcsafe, raises: [].} = discard
method getSymbols*(self: LanguageServer, filename: string): Future[seq[Symbol]] {.base, gcsafe, raises: [].} = discard
method getWorkspaceSymbols*(self: LanguageServer, query: string): Future[seq[Symbol]] {.base, gcsafe, raises: [].} = discard
method getHover*(self: LanguageServer, filename: string, location: Cursor): Future[Option[string]] {.base, gcsafe, raises: [].} = discard
method getInlayHints*(self: LanguageServer, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.base, gcsafe, raises: [].} = discard
method getDiagnostics*(self: LanguageServer, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.base, gcsafe, raises: [].} = discard
method getCompletionTriggerChars*(self: LanguageServer): set[char] {.base, gcsafe, raises: [].} = {}

proc toLspPosition*(cursor: Cursor): lsp_types.Position = lsp_types.Position(line: cursor.line, character: cursor.column)
proc toLspRange*(selection: Selection): lsp_types.Range = lsp_types.Range(start: selection.first.toLspPosition, `end`: selection.last.toLspPosition)
proc toCursor*(position: lsp_types.Position): Cursor = (position.line, position.character)
proc toSelection*(`range`: lsp_types.Range): Selection = (`range`.start.toCursor, `range`.`end`.toCursor)