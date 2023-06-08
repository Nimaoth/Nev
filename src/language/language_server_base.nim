import std/[options, tables]
import custom_async, custom_logger
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

type OnRequestSaveHandle* = distinct int

proc `==`(x, y: OnRequestSaveHandle): bool {.borrow.}

type LanguageServer* = ref object of RootObj
  onRequestSave: Table[OnRequestSaveHandle, proc(targetFilename: string): Future[void]]
  onRequestSaveIndex: Table[string, seq[OnRequestSaveHandle]]

type SymbolType* = enum Unknown, Procedure, Function, MutableVariable, ImmutableVariable, Constant, Parameter, Type

type Definition* = object
  location*: Cursor
  filename*: string

type Symbol* = object
  location*: Cursor
  name*: string
  symbolType*: SymbolType
  filename*: string

type TextCompletion* = object
  name*: string
  scope*: string
  location*: Cursor
  filename*: string
  kind*: SymbolType
  typ*: string
  doc*: string

var getOrCreateLanguageServer*: proc(languageId: string, filename: string, languagesServer: Option[(string, int)] = (string, int).none): Future[Option[LanguageServer]] = nil

method start*(self: LanguageServer): Future[void] {.base.} = discard
method stop*(self: LanguageServer) {.base.} = discard
method getDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[Option[Definition]] {.base.} = discard
method getCompletions*(self: LanguageServer, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.base.} = discard
method saveTempFile*(self: LanguageServer, filename: string, content: string): Future[void] {.base.} = discard
method getSymbols*(self: LanguageServer, filename: string): Future[seq[Symbol]] {.base.} = discard

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