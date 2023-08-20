import std/[strutils, options, json, os, tables, macros, strformat, sugar]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import language_server_base, util
import custom_logger, custom_async, async_http_client, websocket
import platform/filesystem

logCategory "ls-nimsuggest"

when not defined(js):
  import std/[asyncdispatch, osproc, asyncnet, tempfiles]
else:
  type Port* = distinct uint16

type
  LanguageServerImplKind = enum Process, LanguagesServer
  LanguageServerImpl = object
    case kind: LanguageServerImplKind
    of Process:
      when not defined(js):
        process: Process
    of LanguagesServer:
      url: string
      port: Port
      socket: WebSocket

type LanguageServerNimSuggest* = ref object of LanguageServer
  workspaceFilename: string
  filename: string
  tempFilename: string
  port: Port
  impl: LanguageServerImpl
  retryCount: int
  maxRetries: int

proc tryGetPortFromLanguagesServer(self: LanguageServerNimSuggest, url: string, port: Port): Future[void] {.async.} =
  try:
    let response = await httpGet(fmt"http://{url}:{port.int}/nimsuggest/open/{self.workspaceFilename}")
    let json = response.parseJson
    if not json.hasKey("port") or json["port"].kind != JInt:
      return
    if not json.hasKey("tempFilename") or json["tempFilename"].kind != JString:
      return
    self.tempFilename = json["tempFilename"].str.normalizePathUnix
    self.port = json["port"].num.int.Port
    var socket = await newWebSocket(fmt"ws://localhost:{self.port.int}")
    self.impl = LanguageServerImpl(kind: LanguagesServer, url: url, port: port, socket: socket)
  except CatchableError:
    log(lvlError, fmt"Failed to connect to languages server {url}:{port.int}: {getCurrentExceptionMsg()}")

when not defined(js):
  import std/asynchttpserver
  proc getFreePort*(): Port =
    var server = newAsyncHttpServer()
    server.listen(Port(0))
    let port = server.getPort()
    server.close()
    return port

proc splitWorkspacePath*(path: string): tuple[name: string, path: string] =
  if not path.startsWith('@'):
    return ("", path)

  let i = path.find('/')
  if i == -1:
    return (path[1..^1], "")
  return (path[1..<i], path[(i+1)..^1])

proc newLanguageServerNimSuggest*(filename: string, languagesServer: Option[(string, Port)] = (string, Port).none): Future[Option[LanguageServerNimSuggest]] {.async.} =
  var server = new LanguageServerNimSuggest
  server.workspaceFilename = filename
  let (_, filename) = filename.splitWorkspacePath
  server.filename = filename
  server.maxRetries = 1

  when not defined(js):
    try:
      let parts = filename.splitFile
      server.port = getFreePort()
      server.tempFilename = genTempPath("absytree_", "_" & parts.name & parts.ext).replace('\\', '/')
      let process = startProcess("nimsuggest", args = ["--port:" & $server.port.int, filename], options={poUsePath, poDaemon})
      if process.isNil:
        raise newException(IOError, "Failed to start process nimguggest")
      server.impl = LanguageServerImpl(kind: Process, process: process)
      return server.some
    except CatchableError:
      log(lvlWarn, fmt"Couldn't open nimsuggest locally")

  if languagesServer.getSome(config):
    await server.tryGetPortFromLanguagesServer(config[0], config[1])
    return server.some

  return LanguageServerNimSuggest.none

proc restart*(self: LanguageServerNimSuggest): Future[void] {.async.} =
  case self.impl.kind:
  of LanguagesServer:
    await self.tryGetPortFromLanguagesServer(self.impl.url, self.impl.port)
  of Process:
    discard

method start*(self: LanguageServerNimSuggest): Future[void] {.async.} =
  log(lvlInfo, fmt"Starting language server for {self.filename}")

method stop*(self: LanguageServerNimSuggest) =
  log(lvlInfo, fmt"Stopping language server for {self.filename}")
  # self.nimsuggest.terminate()
  # removeFile(self.tempFilename)

method connect*(self: LanguageServerNimSuggest) =
  log lvlInfo, fmt"Connecting document"

method disconnect*(self: LanguageServerNimSuggest) =
  log lvlInfo, fmt"Disconnecting document"
  self.stop()

method saveTempFile*(self: LanguageServerNimSuggest, filename: string, content: string): Future[void] {.async.} =
  case self.impl.kind
  of LanguagesServer:
    await httpPost(fmt"http://{self.impl.url}:{self.impl.port.int}/nimsuggest/temp-file/{self.filename}", content)
  of Process:
    when not defined(js):
      var file = openAsync(filename, fmWrite)
      await file.write content
      file.close()

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

proc parseResponse(line: string): Option[QueryResult] =
  let parts = line.split("\t")
  if parts.len < 9:
    return QueryResult.none

  var queryResult = QueryResult()
  queryResult.query = parts[0]
  queryResult.symbolKind = parseEnum[NimSymKind]("n" & parts[1], nskUnknown)
  queryResult.symbol = parts[2]
  queryResult.typ = parts[3].unescape
  queryResult.filename = parts[4]
  queryResult.location = (parts[5].parseInt - 1, parts[6].parseInt)
  queryResult.doc = parts[7][1..^2].unescape
  queryResult.other = parts[8].parseInt
  return queryResult.some

proc sendQuery(self: LanguageServerNimSuggest, query: string, location: Cursor): Future[seq[QueryResult]] {.async.} =
  let saveTempFileFuture = self.requestSave(self.workspaceFilename, self.tempFilename)

  let line = location.line + 1
  let column = location.column
  let msg = query & " \"" & self.filename & "\";\"" & self.tempFilename & "\" " & $line & " " & $column

  var results: seq[QueryResult] = @[]

  case self.impl.kind
  of LanguagesServer:
    await saveTempFileFuture

    try:
      await self.impl.socket.send(msg)

      while true:
        let response = await self.impl.socket.receiveStrPacket()
        if response.parseResponse().getSome(res):
          results.add(res)
        else:
          break

      self.retryCount = 0
    except CatchableError:
      echo "Failed to send request to nimsuggest-ws: ", getCurrentExceptionMsg()
      if self.retryCount < self.maxRetries:
        echo "Restarting language server"
        inc self.retryCount
        await self.restart()
        return await self.sendQuery(query, location)

    return results

  of Process:
    when not defined(js):
      var socket = newAsyncSocket()
      await socket.connect("", self.port)
      defer: socket.close()

      await saveTempFileFuture
      await socket.send(msg & "\r\L")

      while true:
        let response = await socket.recvLine()
        if response.parseResponse().getSome(res):
          results.add(res)
        else:
          break

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
  of nskParam: Parameter
  of nskGenericParam: Unknown
  of nskTemp: Unknown
  of nskModule: Unknown
  of nskType: Type
  of nskVar: MutableVariable
  of nskLet: ImmutableVariable
  of nskConst: Constant
  of nskResult: Unknown
  of nskProc: Procedure
  of nskFunc: Function
  of nskMethod: Procedure
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

method getSymbols*(self: LanguageServerNimSuggest, filename: string): Future[seq[Symbol]] {.async.} =
  let results = await self.sendQuery("outline", (0, 0))
  var completions: seq[Symbol]
  for r in results:
    let i = r.symbol.rfind('.')
    let (name, _) = if i != -1:
      (r.symbol[i+1..^1].replace("`", ""), r.symbol[0..<i])
    else:
      (r.symbol, "")

    completions.add Symbol(
      location: r.location,
      name: name,
      symbolType: nimSkTypeToDeclarationType(r.symbolKind),
      filename: r.filename
    )

  return completions

# Map from filename to server
var languageServers = initTable[string, LanguageServerNimSuggest]()

proc getOrCreateLanguageServerNimSuggest*(languageId: string, filename: string, languagesServer: Option[(string, int)] = (string, int).none): Future[Option[LanguageServerNimSuggest]] {.async.} =
  assert languageId == "nim"

  if not languageServers.contains(filename):
    let server = await newLanguageServerNimSuggest(filename, languagesServer.map (m) => (m[0], Port(m[1])))
    if server.getSome(server):
      await server.start()
      languageServers[filename] = server
    else:
      return LanguageServerNimSuggest.none

  return languageServers[filename].some