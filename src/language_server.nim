import std/[strutils, logging, sequtils, sugar, options, json, jsonutils, streams, strformat, os, re, tables, deques, asyncdispatch, osproc, asyncnet, tempfiles, macros, uri]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import lsp_client, language_server_base, event, util
import editor, text_document

type LanguageServerNimSuggest* = ref object of LanguageServer
  filename: string
  tempFilename: string
  nimsuggest: Process
  saveTempFile: proc(filename: string): Future[void]

type LanguageServerLSP* = ref object of LanguageServer
  client: LSPClient

method start*(self: LanguageServer) {.base.} = discard
method stop*(self: LanguageServer) {.base.} = discard
method getDefinition*(self: LanguageServer, filename: string, location: Cursor): Future[Option[Definition]] {.base.} = discard
method getCompletions*(self: LanguageServer, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.base.} = discard

let port = 6000
proc newLanguageServerNimSuggest*(filename: string, saveTempFile: proc(filename: string): Future[void]): LanguageServerNimSuggest =
  new result
  result.filename = filename
  let parts = filename.splitFile
  result.tempFilename = genTempPath("absytree_", "_" & parts.name & parts.ext).replace('\\', '/')
  echo result.tempFilename
  result.saveTempFile = saveTempFile

method start*(self: LanguageServerNimSuggest) =
  echo "Starting language server for ", self.filename
  self.nimsuggest = startProcess("nimsuggest", args = ["--port:" & $port, self.filename])

method stop*(self: LanguageServerNimSuggest) =
  echo "Stopping language server for ", self.filename
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
  let saveTempFileFuture = self.saveTempFile(self.tempFilename)

  let socket = await self.connectToNimsuggest()
  defer: socket.close()

  await saveTempFileFuture

  let line = location.line + 1
  let column = location.column
  let msg = query & " \"" & self.filename & "\";\"" & self.tempFilename & "\" " & $line & " " & $column
  echo msg
  await socket.send(msg & "\r\L")

  var results: seq[QueryResult] = @[]
  while true:
    let response = await socket.recvLine()
    let parts = response.split("\t")
    if parts.len < 9:
      # echo parts
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

    # echo parts
    # echo queryResult
    results.add(queryResult)


  return results

method getDefinition*(self: LanguageServerNimSuggest, filename: string, location: Cursor): Future[Option[Definition]] {.async.} =
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

var languageServers = initTable[string, LanguageServerLSP]()

proc toPosition*(cursor: Cursor): Position = Position(line: cursor.line, character: cursor.column)
proc toRange*(selection: Selection): Range = Range(start: selection.first.toPosition, `end`: selection.last.toPosition)

proc getOrCreateLanguageServerLSP*(languageId: string): Future[Option[LanguageServerLSP]] {.async.} =
  if not languageServers.contains(languageId):
    let config = getOption[JsonNode](gEditor, "editor.text.lsp." & languageId)
    if config.isNil:
      return LanguageServerLSP.none
    echo config

    if not config.hasKey("path"):
      return LanguageServerLSP.none

    var client = LSPClient()
    languageServers[languageId] = LanguageServerLSP(client: client)
    await client.connect(config["path"].jsonTo string)
    client.run()

    discard gEditor.onEditorRegistered.subscribe proc(editor: auto) =
      if not (editor of TextDocumentEditor):
        return

      let textDocumentEditor = TextDocumentEditor(editor)
      # echo fmt"EDITOR REGISTERED {textDocumentEditor.document.filename}"

      if textDocumentEditor.document.languageId != languageId:
        return

      asyncCheck client.notifyOpenedTextDocument(languageId, textDocumentEditor.document.filename, textDocumentEditor.document.contentString)
      discard textDocumentEditor.document.textInserted.subscribe proc(args: auto) =
        # echo fmt"TEXT INSERTED {args.document.filename}:{args.location}: {args.text}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.location.toSelection.toRange, text: args.text)]
        asyncCheck client.notifyTextDocumentChanged(args.document.filename, args.document.version, changes)

      discard textDocumentEditor.document.textDeleted.subscribe proc(args: auto) =
        # echo fmt"TEXT DELETED {args.document.filename}: {args.selection}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.selection.toRange)]
        asyncCheck client.notifyTextDocumentChanged(args.document.filename, args.document.version, changes)


    discard gEditor.onEditorDeregistered.subscribe proc(editor: auto) =
      if not (editor of TextDocumentEditor):
        return

      let textDocumentEditor = TextDocumentEditor(editor)
      # echo fmt"EDITOR DEREGISTERED {textDocumentEditor.document.filename}"
      if textDocumentEditor.document.languageId != languageId:
        return

      asyncCheck client.notifyClosedTextDocument(textDocumentEditor.document.filename)

    for editor in gEditor.editors.values:
      if not (editor of TextDocumentEditor):
        continue

      let textDocumentEditor = TextDocumentEditor(editor)
      if textDocumentEditor.document.languageId != languageId:
        continue

      # echo "Register events for ", textDocumentEditor.document.filename
      asyncCheck client.notifyOpenedTextDocument(languageId, textDocumentEditor.document.filename, textDocumentEditor.document.contentString)

      discard textDocumentEditor.document.textInserted.subscribe proc(args: auto) =
        # echo fmt"TEXT INSERTED {args.document.filename}:{args.location}: {args.text}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.location.toSelection.toRange, text: args.text)]
        asyncCheck client.notifyTextDocumentChanged(args.document.filename, args.document.version, changes)

      discard textDocumentEditor.document.textDeleted.subscribe proc(args: auto) =
        # echo fmt"TEXT DELETED {args.document.filename}: {args.selection}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.selection.toRange)]
        asyncCheck client.notifyTextDocumentChanged(args.document.filename, args.document.version, changes)

  return languageServers[languageId].some


method start*(self: LanguageServerLSP) = discard
method stop*(self: LanguageServerLSP) =
  self.client.close()

method getDefinition*(self: LanguageServerLSP, filename: string, location: Cursor): Future[Option[Definition]] {.async.} =
  let response = await self.client.getDefinition(filename, location.line, location.column)
  if response.isError:
    echo "[LSP] Error: ", response.error
    return Definition.none


  let parsedResponse = response.result
  echo parsedResponse
  if parsedResponse.asLocation().getSome(location):
    return Definition(filename: location.uri.parseUri.path, location: (line: location.`range`.start.line, column: location.`range`.start.character)).some

  if parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
    echo "got location seq"
    echo locations
    let location = locations[0]
    return Definition(filename: location.uri.parseUri.path, location: (line: location.`range`.start.line, column: location.`range`.start.character)).some

  if parsedResponse.asLocationLinkSeq().getSome(locations) and locations.len > 0:
    echo "got location link seq"
    let location = locations[0]
    echo locations
    echo location
    return Definition(
      filename: location.targetUri.parseUri.path,
      location: (line: location.targetSelectionRange.start.line, column: location.targetSelectionRange.start.character)).some

  echo "No definition found"
  return Definition.none


method getCompletions*(self: LanguageServerLSP, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.async.} =
  let response = await self.client.getCompletions(filename, location.line, location.column)
  if response.isError:
    echo "[LSP] Error: ", response.error
    return @[]

  let completions = response.result
  echo "[LSP] getCompletions: ", completions.items.len
  var completionsResult: seq[TextCompletion]
  for c in completions.items:
    # echo c
    completionsResult.add(TextCompletion(
      name: c.label,
      scope: "",
      location: location,
      filename: "",
      kind: SymbolType.Function,
      typ: "",
      doc: ""
    ))

    # if completionsResult.len == 10:
    #   break

  return completionsResult