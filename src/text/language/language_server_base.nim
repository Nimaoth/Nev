import std/[options, tables, json]
import misc/[custom_async, custom_logger, event, custom_unicode]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import workspaces/workspace

from lsp_types as lsp_types import CompletionItem

type OnRequestSaveHandle* = distinct int

proc `==`(x, y: OnRequestSaveHandle): bool {.borrow.}

type LanguageServer* = ref object of RootObj
  onRequestSave: Table[OnRequestSaveHandle, proc(targetFilename: string): Future[void]]
  onRequestSaveIndex: Table[string, seq[OnRequestSaveHandle]]
  onMessage*: Event[tuple[verbosity: lsp_types.MessageType, message: string]]
  onDiagnostics*: Event[lsp_types.PublicDiagnosticsParams]

type SymbolType* {.pure.} = enum
  Unknown = 0
  Text = 1
  Method = 2
  Function = 3
  Constructor = 4
  Field = 5
  Variable = 6
  Class = 7
  Interface = 8
  Module = 9
  Property = 10
  Unit = 11
  Value = 12
  Enum = 13
  Keyword = 14
  Snippet = 15
  Color = 16
  File = 17
  Reference = 18
  Folder = 19
  EnumMember = 20
  Constant = 21
  Struct = 22
  Event = 23
  Operator = 24
  TypeParameter = 25

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

var getOrCreateLanguageServer*: proc(languageId: string, filename: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none, workspace = WorkspaceFolder.none): Future[Option[LanguageServer]] = nil

method start*(self: LanguageServer): Future[void] {.base.} = discard
method stop*(self: LanguageServer) {.base.} = discard
method deinit*(self: LanguageServer) {.base.} = discard
method connect*(self: LanguageServer) {.base.} = discard
method disconnect*(self: LanguageServer) {.base.} = discard
method getDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base.} = discard
method getDeclaration*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base.} = discard
method getImplementation*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base.} = discard
method getTypeDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base.} = discard
method getReferences*(self: LanguageServer, filename: string, location: Cursor): Future[seq[Definition]] {.base.} = discard
method getCompletions*(self: LanguageServer, languageId: string, filename: string, location: Cursor): Future[lsp_types.Response[lsp_types.CompletionList]] {.base.} = discard
method saveTempFile*(self: LanguageServer, filename: string, content: string): Future[void] {.base.} = discard
method getSymbols*(self: LanguageServer, filename: string): Future[seq[Symbol]] {.base.} = discard
method getHover*(self: LanguageServer, filename: string, location: Cursor): Future[Option[string]] {.base.} = discard
method getInlayHints*(self: LanguageServer, filename: string, selection: Selection): Future[seq[InlayHint]] {.base.} = discard
method getDiagnostics*(self: LanguageServer, filename: string): Future[lsp_types.Response[seq[Diagnostic]]] {.base.} = discard

var handleIdCounter = 1

proc requestSave*(self: LanguageServer, filename: string, targetFilename: string): Future[void] {.async.} =
  if self.onRequestSaveIndex.contains(filename):
    for handle in self.onRequestSaveIndex[filename]:
      await self.onRequestSave[handle](targetFilename)

proc addOnRequestSaveHandler*(self: LanguageServer, filename: string, handler: proc(targetFilename: string): Future[void]): OnRequestSaveHandle =
  result = handleIdCounter.OnRequestSaveHandle
  handleIdCounter.inc
  self.onRequestSave[result] = handler

  if self.onRequestSaveIndex.contains(filename):
    self.onRequestSaveIndex[filename].add result
  else:
    self.onRequestSaveIndex[filename] = @[result]


proc removeOnRequestSaveHandler*(self: LanguageServer, handle: OnRequestSaveHandle) =
  if self.onRequestSave.contains(handle):
    self.onRequestSave.del(handle)
    for (_, list) in self.onRequestSaveIndex.mpairs:
      let index = list.find(handle)
      if index >= 0:
        list.delete index

proc toPosition*(cursor: Cursor): lsp_types.Position = lsp_types.Position(line: cursor.line, character: cursor.column)
proc toRange*(selection: Selection): lsp_types.Range = lsp_types.Range(start: selection.first.toPosition, `end`: selection.last.toPosition)
proc toCursor*(position: lsp_types.Position): Cursor = (position.line, position.character)
proc toSelection*(`range`: lsp_types.Range): Selection = (`range`.start.toCursor, `range`.`end`.toCursor)