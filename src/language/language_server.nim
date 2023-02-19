import std/[options]
import custom_async, util

import language_server_base

when not defined(js):
  import language_server_nimsuggest
  import language_server_lsp

proc getOrCreateLanguageServer*(languageId: string, filename: string): Future[Option[LanguageServer]] {.async.} =

  when not defined(js):
    let lsp = await getOrCreateLanguageServerLSP(languageId)
    if lsp.getSome(server):
      return server.LanguageServer.some

    let nimsuggest = await getOrCreateLanguageServerNimSuggest(languageId, filename)
    if nimsuggest.getSome(server):
      return server.LanguageServer.some

  return LanguageServer.none