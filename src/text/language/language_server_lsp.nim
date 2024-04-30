import std/[strutils, options, json, tables, uri, strformat, sequtils]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import misc/[event, util, custom_logger, custom_async, myjsonutils, custom_unicode]
import platform/filesystem
import text/text_editor
import language_server_base, app, app_interface, config_provider, lsp_client
import workspaces/workspace as ws

logCategory "lsp"

type LanguageServerLSP* = ref object of LanguageServer
  client: LSPClient
  connected: int = 0
  languageId: string

var languageServers = initTable[string, LanguageServerLSP]()

proc deinitLanguageServers*() =
  for languageServer in languageServers.values:
    languageServer.stop()

  languageServers.clear()

method connect*(self: LanguageServerLSP) =
  log lvlInfo, fmt"Connecting document"
  self.connected.inc

method disconnect*(self: LanguageServerLSP) =
  log lvlInfo, fmt"Disconnecting document"
  self.connected.dec
  if self.connected == 0:
    self.stop()
    # todo: remove from languageServers

proc handleWorkspaceConfigurationRequest*(self: LanguageServerLSP, params: lsp_types.ConfigurationParams): Future[seq[JsonNode]] {.async.} =
  var res = newSeq[JsonNode]()

  for item in params.items:
    if item.section.isNone:
      continue

    res.add gAppInterface.configProvider.getValue("editor.text.lsp." & item.section.get & ".workspace", newJNull())

  return res

proc handleEditorRegistered(lsp: LanguageServerLSP, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  let textDocumentEditor = TextDocumentEditor(editor)
  # debugf"EDITOR REGISTERED {textDocumentEditor.document.fullPath}"

  if textDocumentEditor.document.languageId != lsp.languageId:
    return

  if textDocumentEditor.document.isLoadingAsync:
    discard textDocumentEditor.document.onLoaded.subscribe proc(document: TextDocument): void =
      asyncCheck lsp.client.notifyOpenedTextDocument(lsp.languageId, document.fullPath, document.contentString)
  else:
    asyncCheck lsp.client.notifyOpenedTextDocument(lsp.languageId, textDocumentEditor.document.fullPath, textDocumentEditor.document.contentString)

  discard textDocumentEditor.document.textInserted.subscribe proc(args: auto): void =
    # debugf"TEXT INSERTED {args.document.fullPath}:{args.location}: {args.text}"

    if lsp.client.fullDocumentSync:
      asyncCheck lsp.client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, args.document.contentString)
    else:
      let changes = @[TextDocumentContentChangeEvent(`range`: args.location.first.toSelection.toRange, text: args.text)]
      asyncCheck lsp.client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, changes)

  discard textDocumentEditor.document.textDeleted.subscribe proc(args: auto): void =
    # debugf"TEXT DELETED {args.document.fullPath}: {args.location}"
    if lsp.client.fullDocumentSync:
      asyncCheck lsp.client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, args.document.contentString)
    else:
      let changes = @[TextDocumentContentChangeEvent(`range`: args.location.toRange)]
      asyncCheck lsp.client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, changes)

proc handleEditorDeregistered(lsp: LanguageServerLSP, editor: DocumentEditor) =
  if not (editor of TextDocumentEditor):
    return

  let textDocumentEditor = TextDocumentEditor(editor)
  # debugf"EDITOR DEREGISTERED {textDocumentEditor.document.fullPath}"
  if textDocumentEditor.document.languageId != lsp.languageId:
    return

  asyncCheck lsp.client.notifyClosedTextDocument(textDocumentEditor.document.fullPath)

proc getOrCreateLanguageServerLSP*(languageId: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none, workspace = ws.WorkspaceFolder.none):
  Future[Option[LanguageServerLSP]] {.async.} =

  if languageServers.contains(languageId):
    return languageServers[languageId].some

  let config = gAppInterface.configProvider.getValue("editor.text.lsp." & languageId, newJObject())
  if config.isNil:
    return LanguageServerLSP.none

  log lvlInfo, fmt"Starting language server for {languageId} with config {config}"

  if not config.hasKey("path"):
    log lvlError, &"Missing path in config for language server {languageId}"
    return LanguageServerLSP.none

  let exePath = config["path"].jsonTo(string)
  let args: seq[string] = if config.hasKey("args"):
    config["args"].jsonTo(seq[string])
  else:
    @[]

  var client = LSPClient(workspace: workspace)
  var lsp = LanguageServerLSP(client: client, languageId: languageId)
  languageServers[languageId] = lsp
  await client.connect(exePath, workspaces, args, languagesServer)
  client.run()

  discard client.onMessage.subscribe proc(message: tuple[verbosity: lsp_types.MessageType, message: string]): void =
    let level = case message.verbosity
    of Error: lvlError
    of Warning: lvlWarn
    of Info: lvlInfo
    of Log: lvlDebug
    log(level, fmt"{message} -----------------------------------------")

    lsp.onMessage.invoke message

  client.onWorkspaceConfiguration = proc(params: lsp_types.ConfigurationParams): Future[seq[JsonNode]] {.async.} =
    return lsp.handleWorkspaceConfigurationRequest(params).await

  discard client.onDiagnostics.subscribe proc(diagnostics: lsp_types.PublicDiagnosticsParams): void =
    # debugf"textDocument/publishDiagnostics: {diagnostics}"
    lsp.onDiagnostics.invoke diagnostics

  discard gEditor.onEditorRegistered.subscribe proc(editor: DocumentEditor): void =
    lsp.handleEditorRegistered(editor)

  discard gEditor.onEditorDeregistered.subscribe proc(editor: DocumentEditor): void =
    lsp.handleEditorDeregistered(editor)

  for editor in gEditor.editors.values:
    lsp.handleEditorRegistered(editor)

  log lvlInfo, fmt"Started language server for {languageId}"
  return languageServers[languageId].some


method start*(self: LanguageServerLSP): Future[void] = discard
method stop*(self: LanguageServerLSP) =
  log lvlInfo, fmt"Stopping language server"
  self.client.deinit()

template locationsResponseToDefinitions(parsedResponse: untyped): untyped =
  block:
    if parsedResponse.asLocation().getSome(location):
      @[Definition(filename: location.uri.decodeUrl.parseUri.path.normalizePathUnix, location: (line: location.`range`.start.line, column: location.`range`.start.character))]

    elif parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
      var res = newSeq[Definition]()
      for location in locations:
        res.add Definition(filename: location.uri.decodeUrl.parseUri.path.normalizePathUnix, location: (line: location.`range`.start.line, column: location.`range`.start.character))
      res

    elif parsedResponse.asLocationLinkSeq().getSome(locations) and locations.len > 0:
      var res = newSeq[Definition]()
      for location in locations:
        res.add Definition(
          filename: location.targetUri.decodeUrl.parseUri.path.normalizePathUnix,
          location: (line: location.targetSelectionRange.start.line, column: location.targetSelectionRange.start.character))
      res

    else:
      newSeq[Definition]()

method getDefinition*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let response = await self.client.getDefinition(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No definitions found")
  return res

method getDeclaration*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let response = await self.client.getDeclaration(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No declaration found")
  return res

method getTypeDefinition*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let response = await self.client.getTypeDefinitions(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No type definitions found")
  return res

method getImplementation*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let response = await self.client.getImplementation(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  let res = parsedResponse.locationsResponseToDefinitions()
  if res.len == 0:
    log(lvlError, "No implementations found")
  return res

method getReferences*(self: LanguageServerLSP, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  let response = await self.client.getReferences(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[Definition]()

  let parsedResponse = response.result

  if parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
    var res = newSeq[Definition]()
    for location in locations:
      res.add Definition(filename: location.uri.decodeUrl.parseUri.path.normalizePathUnix, location: (line: location.`range`.start.line, column: location.`range`.start.character))
    return res

  log(lvlError, "No references found")
  return newSeq[Definition]()

method switchSourceHeader*(self: LanguageServerLSP, filename: string): Future[Option[string]] {.async.} =
  let response = await self.client.switchSourceHeader(filename)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return string.none

  if response.result.len == 0:
    return string.none

  return response.result.decodeUrl.parseUri.path.normalizePathUnix.some

method getHover*(self: LanguageServerLSP, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  let response = await self.client.getHover(filename, location.line, location.column)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return string.none

  let parsedResponse = response.result

  # important: the order of these checks is important
  if parsedResponse.contents.asMarkedStringVariantSeq().getSome(markedStrings):
    for markedString in markedStrings:
      if markedString.asString().getSome(str):
        return str.some
      if markedString.asMarkedStringObject().getSome(str):
        # todo: language
        return str.value.some

    return string.none

  if parsedResponse.contents.asMarkupContent().getSome(markupContent):
    return markupContent.value.some

  if parsedResponse.contents.asMarkedStringVariant().getSome(markedString):
    debugf"marked string variant: {markedString}"

    if markedString.asString().getSome(str):
      debugf"string: {str}"
      return str.some

    if markedString.asMarkedStringObject().getSome(str):
      debugf"string object lang: {str.language}, value: {str.value}"
      return str.value.some

    return string.none

  return string.none

method getInlayHints*(self: LanguageServerLSP, filename: string, selection: Selection): Future[seq[language_server_base.InlayHint]] {.async.} =
  let response = await self.client.getInlayHints(filename, selection)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return newSeq[language_server_base.InlayHint]()

  let parsedResponse = response.result

  if parsedResponse.getSome(inlayHints):
    var hints: seq[language_server_base.InlayHint]
    for hint in inlayHints:
      let label = case hint.label.kind:
        of JString: hint.label.getStr
        of JArray:
          if hint.label.elems.len == 0:
            ""
          else:
            hint.label.elems[0]["value"].getStr
        else:
          ""

      hints.add language_server_base.InlayHint(
        location: (hint.position.line, hint.position.character),
        label: label,
        kind: hint.kind.mapIt(case it
          of lsp_types.InlayHintKind.Type: language_server_base.InlayHintKind.Type
          of lsp_types.InlayHintKind.Parameter: language_server_base.InlayHintKind.Parameter
        ),
        textEdits: hint.textEdits.mapIt(language_server_base.TextEdit(selection: it.`range`.toSelection, newText: it.newText)),
        # tooltip*: Option[string] # | MarkupContent # todo
        paddingLeft: hint.paddingLeft.get(false),
        paddingRight: hint.paddingRight.get(false),
        data: hint.data
      )

    return hints

  return newSeq[language_server_base.InlayHint]()

method getSymbols*(self: LanguageServerLSP, filename: string): Future[seq[Symbol]] {.async.} =
  var completions: seq[Symbol]

  let response = await self.client.getSymbols(filename)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return completions

  let parsedResponse = response.result

  if parsedResponse.asDocumentSymbolSeq().getSome(symbols):
    for s in symbols:
      debug s

  elif parsedResponse.asSymbolInformationSeq().getSome(symbols):
    for r in symbols:
      let symbolKind: SymbolType = case r.kind
      # of File: 1
      # of Module: 2
      # of Namespace: 3
      # of Package: 4
      # of Class: 5
      of Method: SymbolType.Method
      # of Property: 7
      # of Field: 8
      # of Constructor: 9
      # of Enum: 10
      # of Interface: 11
      of Function: Function
      of Variable: Variable
      # of Constant: 14
      # of String: 15
      # of Number: 16
      # of Boolean: 17
      # of Array: 18
      # of Object: 19
      # of Key: 20
      # of Null: 21
      # of EnumMember: 22
      # of Struct: 23
      # of Event: 24
      # of Operator: 25
      # of TypeParameter: 26
      else: Unknown

      completions.add Symbol(
        location: (line: r.location.range.start.line, column: r.location.range.start.character),
        name: r.name,
        symbolType: symbolKind,
        filename: r.location.uri.decodeUrl.parseUri.path.normalizePathUnix,
      )

  return completions

method getDiagnostics*(self: LanguageServerLSP, filename: string): Future[Response[seq[language_server_base.Diagnostic]]] {.async.} =
  debugf"getDiagnostics: {filename}"

  let response = await self.client.getDiagnostics(filename)
  if response.isError:
    log(lvlError, &"Error: {response.error}")
    return response.to(seq[language_server_base.Diagnostic])

  let report = response.result
  debugf"getDiagnostics: {report}"

  var res: seq[language_server_base.Diagnostic]

  if report.asRelatedFullDocumentDiagnosticReport().getSome(report):
    # todo: selection from rune index to byte index
    for d in report.items:
      res.add language_server_base.Diagnostic(
        # selection: ((d.`range`.start.line, d.`range`.start.character.RuneIndex), (d.`range`.`end`.line, d.`range`.`end`.character.RuneIndex)),
        severity: d.severity,
        code: d.code,
        codeDescription: d.codeDescription,
        source: d.source,
        message: d.message,
        tags: d.tags,
        relatedInformation: d.relatedInformation,
        data: d.data,
      )
    debugf"items: {res.len}: {res}"

  return res.success

# todo: romve languageId
method getCompletions*(self: LanguageServerLSP, languageId: string, filename: string, location: Cursor): Future[Response[CompletionList]] {.async.} =
  return await self.client.getCompletions(filename, location.line, location.column)