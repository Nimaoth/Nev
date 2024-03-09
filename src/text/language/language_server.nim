import std/[options]
import misc/[custom_async, util]
import language_server_base
import workspaces/workspace

import language_server_lsp

{.used.}

proc getOrCreateLanguageServerImpl*(languageId: string, filename: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none, workspace = WorkspaceFolder.none): Future[Option[LanguageServer]] {.async.} =
  let lsp = await getOrCreateLanguageServerLSP(languageId, workspaces, languagesServer, workspace)
  if lsp.getSome(server):
    return server.LanguageServer.some

  return LanguageServer.none

getOrCreateLanguageServer = getOrCreateLanguageServerImpl