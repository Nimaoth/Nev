import std/[strutils, options, json, jsonutils, os, tables, macros, uri, strformat]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import language_server_base, event, util
import editor, text_document, custom_logger, custom_async

import std/[asyncdispatch, osproc, asyncnet, tempfiles]

type LanguageServerNimSuggest* = ref object of LanguageServer
  filename: string
  tempFilename: string
  nimsuggest: Process

let port = 6000
proc newLanguageServerNimSuggest*(filename: string): LanguageServerNimSuggest =
  new result
  result.filename = filename
  let parts = filename.splitFile
  result.tempFilename = genTempPath("absytree_", "_" & parts.name & parts.ext).replace('\\', '/')

method start*(self: LanguageServerNimSuggest) =
  logger.log(lvlInfo, fmt"Starting language server for {self.filename}")
  self.nimsuggest = startProcess("nimsuggest", args = ["--port:" & $port, self.filename])

method stop*(self: LanguageServerNimSuggest) =
  logger.log(lvlInfo, fmt"Stopping language server for {self.filename}")
  self.nimsuggest.terminate()
  removeFile(self.tempFilename)

proc connectToNimsuggest(self: LanguageServerNimSuggest): Future[AsyncSocket] {.async.} =
  var socket = newAsyncSocket()
  await socket.connect("", Port(port))
  return socket

type QueryResult = object
  query: string
  symbolKind: NimSymKind
  symbol: string
  typ: string
  filename: string
  location: Cursor
  doc: string
  other: int

proc unescape(str: string): string =
  var i = 0
  while i < str.len:
    if str[i] == '\\':
      if i + 1 < str.len and str[i + 1] == 'x':
        let hex = $str[i + 2] & $str[i + 3]
        let c = hex.parseHexInt.char
        result.add c
        i += 4
      else:
        result.add str[i + 1]
        i += 2
    else:
      result.add str[i]
      inc i

proc sendQuery(self: LanguageServerNimSuggest, query: string, location: Cursor): Future[seq[QueryResult]] {.async.} =
  let saveTempFileFuture = self.requestSave(self.filename, self.tempFilename)

  let socket = await self.connectToNimsuggest()
  defer: socket.close()

  await saveTempFileFuture

  let line = location.line + 1
  let column = location.column
  let msg = query & " \"" & self.filename & "\";\"" & self.tempFilename & "\" " & $line & " " & $column
  await socket.send(msg & "\r\L")

  var results: seq[QueryResult] = @[]
  while true:
    let response = await socket.recvLine()
    let parts = response.split("\t")
    if parts.len < 9:
      break

    var queryResult = QueryResult()
    queryResult.query = parts[0]
    queryResult.symbolKind = parseEnum[NimSymKind]("n" & parts[1], nskUnknown)
    queryResult.symbol = parts[2]
    queryResult.typ = parts[3].unescape
    queryResult.filename = parts[4].unescape
    queryResult.location = (parts[5].parseInt - 1, parts[6].parseInt)
    queryResult.doc = parts[7][1..^2].unescape
    queryResult.other = parts[8].parseInt

    results.add(queryResult)


  return results

method getDefinition*(self: LanguageServerNimSuggest, filename: string, location: Cursor): Future[Option[Definition]] {.async.} =
  # debugf"getDefinition {filename}, {location}"
  let results = await self.sendQuery("def", location)

  for r in results:
    return Definition(location: r.location, filename: r.filename).some

  return Definition.none

proc nimSkTypeToDeclarationType(symbolKind: NimSymKind): SymbolType =
  result = case symbolKind
  of nskUnknown: Unknown
  of nskConditional: Unknown
  of nskDynLib: Unknown
  of nskParam: Unknown
  of nskGenericParam: Unknown
  of nskTemp: Unknown
  of nskModule: Unknown
  of nskType: Unknown
  of nskVar: Unknown
  of nskLet: Unknown
  of nskConst: Unknown
  of nskResult: Unknown
  of nskProc: Unknown
  of nskFunc: Unknown
  of nskMethod: Unknown
  of nskIterator: Unknown
  of nskConverter: Unknown
  of nskMacro: Unknown
  of nskTemplate: Unknown
  of nskField: Unknown
  of nskEnumField: Unknown
  of nskForVar: Unknown
  of nskLabel: Unknown
  of nskStub: Unknown

method getCompletions*(self: LanguageServerNimSuggest, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.async.} =
  let results = await self.sendQuery("sug", location)
  var completions: seq[TextCompletion]
  for r in results:
    let i = r.symbol.rfind('.')
    let (name, scope) = if i != -1:
      (r.symbol[i+1..^1].replace("`", ""), r.symbol[0..<i])
    else:
      (r.symbol, "")
    completions.add TextCompletion(
      name: name,
      scope: scope,
      location: r.location,
      filename: r.filename,
      kind: nimSkTypeToDeclarationType(r.symbolKind),
      typ: r.typ,
      doc: r.doc
    )

  return completions

# Map from filename to server
var languageServers = initTable[string, LanguageServerNimSuggest]()

proc getOrCreateLanguageServerNimSuggest*(languageId: string, filename: string): Future[Option[LanguageServerNimSuggest]] {.async.} =
  assert languageId == "nim"

  if not languageServers.contains(filename):
    let server = newLanguageServerNimSuggest(filename)
    server.start()
    languageServers[filename] = server

  return languageServers[filename].some