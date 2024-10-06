import std/[options]
import misc/[custom_async, util]
import language_server_base
import workspaces/workspace

import language_server_lsp

{.used.}

proc getOrCreateLanguageServerImpl*(languageId: string, filename: string, workspaces: seq[string], languagesServer: Option[(string, int)] = (string, int).none, workspace = Workspace.none): Future[Option[LanguageServer]] {.gcsafe, raises: [].} =
  return getOrCreateLanguageServerLSP(languageId, workspaces, languagesServer, workspace)

getOrCreateLanguageServer = getOrCreateLanguageServerImpl