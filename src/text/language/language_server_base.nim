import std/[options, json]
import misc/[custom_async, custom_logger, event, response]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

from lsp_types as lsp_types import CompletionItem, WorkspaceEdit, ServerCapabilities
export ServerCapabilities

include dynlib_export

logCategory "language-server-base"

{.push gcsafe.}
{.push raises: [].}

type LanguageServer* = ref object of RootObj
  name*: string
  priority*: int
  onMessage*: Event[tuple[verbosity: lsp_types.MessageType, message: string]]
  onDiagnostics*: Event[lsp_types.PublicDiagnosticsParams]
  capabilities*: ServerCapabilities
  refetchWorkspaceSymbolsOnQueryChange*: bool = false

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
  codeDescription*: Option[lsp_types.CodeDescription]
  source*: Option[string]
  message*: string
  tags*: Option[seq[lsp_types.DiagnosticTag]]
  relatedInformation*: Option[seq[lsp_types.DiagnosticRelatedInformation]]
  data*: Option[JsonNode]
  removed*: bool = false
  codeActionRequested*: bool = false

when implModule:
  import document, document_editor, service
  import workspaces/workspace
  import config_provider

  type
    LanguageServerService* = ref object of Service
      config: ConfigStore

  func serviceName*(_: typedesc[LanguageServerService]): string = "LanguageServerService"

  addBuiltinService(LanguageServerService, ConfigService)

  method init*(self: LanguageServerService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
    log lvlInfo, &"LanguageServerService.init"
    self.config = self.services.getService(ConfigService).get.runtime
    return ok()

  var getOrCreateLanguageServer*: proc(languageId: string, filename: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none, workspace = Workspace.none): Future[Option[LanguageServer]] {.gcsafe, raises: [].} = nil

  method start*(self: LanguageServer): Future[void] {.base, gcsafe, raises: [].} = doneFuture()
  method stop*(self: LanguageServer) {.base, gcsafe, raises: [].} = discard
  method deinit*(self: LanguageServer) {.base, gcsafe, raises: [].} = discard
  method connect*(self: LanguageServer, document: Document) {.base, gcsafe, raises: [].} = discard
  method disconnect*(self: LanguageServer, document: Document) {.base, gcsafe, raises: [].} = discard
  method getDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = newSeq[Definition]().toFuture
  method getDeclaration*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = newSeq[Definition]().toFuture
  method getImplementation*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = newSeq[Definition]().toFuture
  method getTypeDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = newSeq[Definition]().toFuture
  method getReferences*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base, gcsafe, raises: [].} = newSeq[Definition]().toFuture
  method switchSourceHeader*(self: LanguageServer, filename: string): Future[Option[string]] {.base, gcsafe, raises: [].} = Option[string].default.toFuture
  method getCompletions*(self: LanguageServer, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.base, gcsafe, raises: [].} = Response[lsp_types.CompletionList].default.toFuture
  method getSymbols*(self: LanguageServer, filename: string): Future[seq[Symbol]] {.base, gcsafe, raises: [].} = seq[Symbol].default.toFuture
  method getWorkspaceSymbols*(self: LanguageServer, filename: string, query: string): Future[seq[Symbol]] {.base, gcsafe, raises: [].} = seq[Symbol].default.toFuture
  method getHover*(self: LanguageServer, filename: string, location: Cursor): Future[Option[string]] {.base, gcsafe, raises: [].} = Option[string].default.toFuture
  method getSignatureHelp*(self: LanguageServer, filename: string, location: Cursor): Future[Response[seq[lsp_types.SignatureHelpResponse]]] {.base, gcsafe, raises: [].} = Response[seq[lsp_types.SignatureHelpResponse]].default.toFuture
  method getInlayHints*(self: LanguageServer, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.base, gcsafe, raises: [].} = seq[language_server_base.InlayHint].default.success.toFuture
  method getDiagnostics*(self: LanguageServer, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.base, gcsafe, raises: [].} = seq[lsp_types.Diagnostic].default.success.toFuture
  method getCompletionTriggerChars*(self: LanguageServer): set[char] {.base, gcsafe, raises: [].} = {}
  method getCodeActions*(self: LanguageServer, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.base, gcsafe, raises: [].} = lsp_types.CodeActionResponse.default.success.toFuture
  method rename*(self: LanguageServer, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.base, gcsafe, raises: [].} = newSeq[lsp_types.WorkspaceEdit]().success.toFuture
  method executeCommand*(self: LanguageServer, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.base, gcsafe, raises: [].} = errorResponse[JsonNode](0, "Command not found: " & command).toFuture

  proc toLspPosition*(cursor: Cursor): lsp_types.Position = lsp_types.Position(line: cursor.line, character: cursor.column)
  proc toLspRange*(selection: Selection): lsp_types.Range = lsp_types.Range(start: selection.first.toLspPosition, `end`: selection.last.toLspPosition)
  proc toCursor*(position: lsp_types.Position): Cursor = (position.line, position.character)
  proc toSelection*(`range`: lsp_types.Range): Selection = (`range`.start.toCursor, `range`.`end`.toCursor)
