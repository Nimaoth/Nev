import std/[options]
import misc/[custom_async, util]
import language_server_base, language_server_nimsuggest

when not defined(js):
  import language_server_lsp

{.used.}

proc getOrCreateLanguageServerImpl*(languageId: string, filename: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none): Future[Option[LanguageServer]] {.async.} =

  when not defined(js):
    let lsp = await getOrCreateLanguageServerLSP(languageId, workspaces)
    if lsp.getSome(server):
      return server.LanguageServer.some

  if languageId == "nim":
    let nimsuggest = await getOrCreateLanguageServerNimSuggest(languageId, filename, languagesServer)
    if nimsuggest.getSome(server):
      return server.LanguageServer.some

  return LanguageServer.none

getOrCreateLanguageServer = getOrCreateLanguageServerImpl