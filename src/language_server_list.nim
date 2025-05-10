import std/[options, tables, strutils, os, json]
import nimsumtree/rope
import misc/[custom_logger, custom_async, util, response, event]
import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor
import text/language/[language_server_base, lsp_types]

logCategory "language-server-list"

type
  LanguageServerList* = ref object of LanguageServer
    languageServers*: seq[LanguageServer]

proc newLanguageServerList*(): LanguageServerList =
  var server = new LanguageServerList
  return server

template merge(T: untyped, subCall: untyped, name: untyped): untyped =
  block:
    var futs = newSeq[Future[seq[T]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for lss in self.languageServers:
      let ls {.inject.} = lss
      let fut = subCall
      futs.add fut
      futsTimeout.add fut.withTimeout(500.milliseconds)

    await allFutures(futsTimeout)

    var res = newSeq[T]()
    for fut in futs:
      if fut.completed:
        res.add fut.read()

    res

template mergeOption(T: untyped, subCall: untyped, name: untyped): untyped =
  block:
    var futs = newSeq[Future[Option[T]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for lss in self.languageServers:
      let ls {.inject.} = lss
      let fut = subCall
      futs.add fut
      futsTimeout.add fut.withTimeout(500.milliseconds)

    await allFutures(futsTimeout)

    var res = T.none
    for fut in futs:
      if fut.completed:
        let r = fut.read()
        if r.isSome:
          res = r

    res

template mergeResponse(T: untyped, subCall: untyped, name: untyped): untyped =
  block:
    var futs = newSeq[Future[Response[seq[T]]]]()
    var futsTimeout = newSeq[Future[bool]]()
    for lss in self.languageServers:
      let ls {.inject.} = lss
      let fut = subCall
      futs.add fut
      futsTimeout.add fut.withTimeout(500.milliseconds)

    await allFutures(futsTimeout)

    var res = newSeq[T]()
    for fut in futs:
      if fut.completed:
        let r = fut.read()
        if r.isSuccess:
          res.add r.result

    res.success

method getDefinition*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return merge(Definition, ls.getDefinition(filename, location), "getDefinition")

method getDeclaration*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return merge(Definition, ls.getDeclaration(filename, location), "getDeclaration")

method getImplementation*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return merge(Definition, ls.getImplementation(filename, location), "getImplementation")

method getTypeDefinition*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return merge(Definition, ls.getTypeDefinition(filename, location), "getTypeDefinition")

method getReferences*(self: LanguageServerList, filename: string, location: Cursor): Future[seq[Definition]] {.async.} =
  return merge(Definition, ls.getReferences(filename, location), "getReferences")

method switchSourceHeader*(self: LanguageServerList, filename: string): Future[Option[string]] {.async.} =
  return mergeOption(string, ls.switchSourceHeader(filename), "switchSourceHeader")

method getCompletions*(self: LanguageServerList, filename: string, location: Cursor): Future[Response[lsp_types.CompletionList]] {.async.} =
  # completions are handled by the completion provider as separate providers, so no need to implement this right now
  discard

method getSymbols*(self: LanguageServerList, filename: string): Future[seq[Symbol]] {.async.} =
  return merge(Symbol, ls.getSymbols(filename), "getSymbols")

method getWorkspaceSymbols*(self: LanguageServerList, query: string): Future[seq[Symbol]] {.async.} =
  return merge(Symbol, ls.getWorkspaceSymbols(query), "getWorkspaceSymbols")

method getHover*(self: LanguageServerList, filename: string, location: Cursor): Future[Option[string]] {.async.} =
  return mergeOption(string, ls.getHover(filename, location), "getHover")

method getInlayHints*(self: LanguageServerList, filename: string, selection: Selection): Future[Response[seq[language_server_base.InlayHint]]] {.async.} =
  return mergeResponse(language_server_base.InlayHint, ls.getInlayHints(filename, selection), "getInlayHints")

method getDiagnostics*(self: LanguageServerList, filename: string): Future[Response[seq[lsp_types.Diagnostic]]] {.async.} =
  return mergeResponse(lsp_types.Diagnostic, ls.getDiagnostics(filename), "getDiagnostics")

method getCompletionTriggerChars*(self: LanguageServerList): set[char] =
  for ls in self.languageServers:
    result.incl ls.getCompletionTriggerChars()

method getCodeActions*(self: LanguageServerList, filename: string, selection: Selection, diagnostics: seq[lsp_types.Diagnostic]): Future[Response[lsp_types.CodeActionResponse]] {.async.} =
  return mergeResponse(lsp_types.CodeActionResponseVariant, ls.getCodeActions(filename, selection, diagnostics), "getCodeActions")

method rename*(self: LanguageServerList, filename: string, position: Cursor, newName: string): Future[Response[seq[lsp_types.WorkspaceEdit]]] {.async.} =
  return mergeResponse(lsp_types.WorkspaceEdit, ls.rename(filename, position, newName), "rename")

method executeCommand*(self: LanguageServerList, command: string, arguments: seq[JsonNode]): Future[Response[JsonNode]] {.async.} =
  var futs = newSeq[Future[Response[JsonNode]]]()
  var futsTimeout = newSeq[Future[bool]]()
  for lss in self.languageServers:
    let ls {.inject.} = lss
    let fut = ls.executeCommand(command, arguments)
    futs.add fut
    futsTimeout.add fut.withTimeout(500.milliseconds)

  await allFutures(futsTimeout)

  var res = errorResponse[JsonNode](0, "Command not found: " & command)
  for fut in futs:
    if fut.completed:
      res = fut.read()
      if res.isSuccess:
        return res

  return res
