import std/[strutils, options, json, jsonutils, os, tables, uri, strformat]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import language_server_base, event, util, editor, text_document, custom_logger, custom_async, lsp_client

type LanguageServerLSP* = ref object of LanguageServer
  client: LSPClient

var languageServers = initTable[string, LanguageServerLSP]()

proc toPosition*(cursor: Cursor): Position = Position(line: cursor.line, character: cursor.column)
proc toRange*(selection: Selection): Range = Range(start: selection.first.toPosition, `end`: selection.last.toPosition)

proc getOrCreateLanguageServerLSP*(languageId: string): Future[Option[LanguageServerLSP]] {.async.} =
  if not languageServers.contains(languageId):
    let config = getOption[JsonNode](gEditor, "editor.text.lsp." & languageId)
    if config.isNil:
      return LanguageServerLSP.none

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
    logger.log(lvlError, fmt"[LSP] Error: {response.error}")
    return Definition.none


  let parsedResponse = response.result
  # echo parsedResponse
  if parsedResponse.asLocation().getSome(location):
    return Definition(filename: location.uri.parseUri.path, location: (line: location.`range`.start.line, column: location.`range`.start.character)).some

  if parsedResponse.asLocationSeq().getSome(locations) and locations.len > 0:
    let location = locations[0]
    return Definition(filename: location.uri.parseUri.path, location: (line: location.`range`.start.line, column: location.`range`.start.character)).some

  if parsedResponse.asLocationLinkSeq().getSome(locations) and locations.len > 0:
    let location = locations[0]
    return Definition(
      filename: location.targetUri.parseUri.path,
      location: (line: location.targetSelectionRange.start.line, column: location.targetSelectionRange.start.character)).some

  logger.log(lvlError, "No definition found")
  return Definition.none


method getCompletions*(self: LanguageServerLSP, languageId: string, filename: string, location: Cursor): Future[seq[TextCompletion]] {.async.} =
  let response = await self.client.getCompletions(filename, location.line, location.column)
  if response.isError:
    logger.log(lvlError, fmt"[LSP] Error: {response.error}")
    return @[]

  let completions = response.result
  logger.log(lvlError, fmt"[LSP] getCompletions: {completions.items.len}")
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