import std/[options]
import custom_async, util

import language_server_base

import language_server_nimsuggest

when not defined(js):
  import language_server_lsp

{.used.}

proc getOrCreateLanguageServerImpl*(languageId: string, filename: string, languagesServer: Option[(string, int)] = (string, int).none): Future[Option[LanguageServer]] {.async.} =

  when not defined(js):
    let lsp = await getOrCreateLanguageServerLSP(languageId)
    if lsp.getSome(server):
      return server.LanguageServer.some

  if languageId == "nim":
    let nimsuggest = await getOrCreateLanguageServerNimSuggest(languageId, filename, languagesServer)
    if nimsuggest.getSome(server):
      return server.LanguageServer.some

  return LanguageServer.none

getOrCreateLanguageServer = getOrCreateLanguageServerImpl