import std/[strutils, options, json, tables, uri, strformat]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import language_server_base, event, util, app, app_interface, config_provider, text/text_editor, custom_logger, custom_async, lsp_client, myjsonutils

logCategory "lsp"

type LanguageServerLSP* = ref object of LanguageServer
  client: LSPClient
  connected: int = 0

var languageServers = initTable[string, LanguageServerLSP]()

proc toPosition*(cursor: Cursor): Position = Position(line: cursor.line, character: cursor.column)
proc toRange*(selection: Selection): Range = Range(start: selection.first.toPosition, `end`: selection.last.toPosition)

method connect*(self: LanguageServerLSP) =
  log lvlInfo, fmt"Connecting document"
  self.connected.inc

method disconnect*(self: LanguageServerLSP) =
  log lvlInfo, fmt"Disconnecting document"
  self.connected.dec
  if self.connected == 0:
    self.stop()

proc getOrCreateLanguageServerLSP*(languageId: string, workspaces: seq[string]): Future[Option[LanguageServerLSP]] {.async.} =
  if not languageServers.contains(languageId):
    let config = gAppInterface.configProvider.getValue("editor.text.lsp." & languageId, newJObject())
    if config.isNil:
      return LanguageServerLSP.none

    if not config.hasKey("path"):
      return LanguageServerLSP.none

    var client = LSPClient()
    languageServers[languageId] = LanguageServerLSP(client: client)
    await client.connect(config["path"].jsonTo(string), workspaces)
    client.run()

    discard gEditor.onEditorRegistered.subscribe proc(editor: auto) =
      if not (editor of TextDocumentEditor):
        return

      let textDocumentEditor = TextDocumentEditor(editor)
      # echo fmt"EDITOR REGISTERED {textDocumentEditor.document.fullPath}"

      if textDocumentEditor.document.languageId != languageId:
        return

      asyncCheck client.notifyOpenedTextDocument(languageId, textDocumentEditor.document.fullPath, textDocumentEditor.document.contentString)
      discard textDocumentEditor.document.textInserted.subscribe proc(args: auto) =
        # echo fmt"TEXT INSERTED {args.document.fullPath}:{args.location}: {args.text}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.location.toSelection.toRange, text: args.text)]
        asyncCheck client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, changes)

      discard textDocumentEditor.document.textDeleted.subscribe proc(args: auto) =
        # echo fmt"TEXT DELETED {args.document.fullPath}: {args.selection}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.selection.toRange)]
        asyncCheck client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, changes)


    discard gEditor.onEditorDeregistered.subscribe proc(editor: auto) =
      if not (editor of TextDocumentEditor):
        return

      let textDocumentEditor = TextDocumentEditor(editor)
      # echo fmt"EDITOR DEREGISTERED {textDocumentEditor.document.fullPath}"
      if textDocumentEditor.document.languageId != languageId:
        return

      asyncCheck client.notifyClosedTextDocument(textDocumentEditor.document.fullPath)

    for editor in gEditor.editors.values:
      if not (editor of TextDocumentEditor):
        continue

      let textDocumentEditor = TextDocumentEditor(editor)
      if textDocumentEditor.document.languageId != languageId:
        continue

      # echo "Register events for ", textDocumentEditor.document.fullPath
      asyncCheck client.notifyOpenedTextDocument(languageId, textDocumentEditor.document.fullPath, textDocumentEditor.document.contentString)

      discard textDocumentEditor.document.textInserted.subscribe proc(args: auto) =
        # echo fmt"TEXT INSERTED {args.document.fullPath}:{args.location}: {args.text}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.location.toSelection.toRange, text: args.text)]
        asyncCheck client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, changes)

      discard textDocumentEditor.document.textDeleted.subscribe proc(args: auto) =
        # echo fmt"TEXT DELETED {args.document.fullPath}: {args.selection}"
        let changes = @[TextDocumentContentChangeEvent(`range`: args.selection.toRange)]
        asyncCheck client.notifyTextDocumentChanged(args.document.fullPath, args.document.version, changes)

  return languageServers[languageId].some


method start*(self: LanguageServerLSP): Future[void] = discard
method stop*(self: LanguageServerLSP) =
  log lvlInfo, fmt"Stopping language server"
  self.client.close()

method getDefinition*(self: LanguageServerLSP, filename: string, location: Cursor): Future[Option[Definition]] {.async.} =
  let response = await self.client.getDefinition(filename, location.line, location.column)
  if response.isError:
    log(lvlError, fmt"Error: {response.error}")
    return Definition.none


  let parsedResponse = response.result
  # echo parsedResponse
  if parsedResponse.asLocation().getSome(location):
    return Definition(filename: location.uri.parseUri.path.myNormalizedPath, location: (line: location.`range`.start.line, column: location.`range`.start.character)).some

  if parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
    let location = locations[0]
    return Definition(filename: location.uri.parseUri.path.myNormalizedPath, location: (line: location.`range`.start.line, column: location.`range`.start.character)).some

  if parsedResponse.asLocationLinkSeq().getSome(locations) and locations.len > 0:
    let location = locations[0]
    return Definition(
      filename: location.targetUri.parseUri.path.myNormalizedPath,
      location: (line: location.targetSelectionRange.start.line, column: location.targetSelectionRange.start.character)).some

  log(lvlError, "No definition found")
  return Definition.none


method getCompletions*(self: LanguageServerLSP, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.async.} =
  let response = await self.client.getCompletions(filename, location.line, location.column)
  if response.isError:
    log(lvlError, fmt"Error: {response.error}")
    return @[]

  let completions = response.result
  # debugf"getCompletions: {completions.items.len}"
  var completionsResult: seq[TextCompletion]
  for c in completions.items:
    # echo c
    completionsResult.add(TextCompletion(
      name: c.label,
      scope: "lsp",
      location: location,
      filename: "",
      kind: SymbolType.Function,
      typ: "",
      doc: ""
    ))

    # if completionsResult.len == 10:
    #   break

  return completionsResult