import std/[os, strutils]
import custom_async, util
import languages_server, workspace_server

when isMainModule:
  const workspaceServerPortArg = "--workspace-port:"
  const languagesServerPortArg = "--languages-port:"
  const nimsuggestPathArg = "--nimsuggest:"
  var workspaceServerPort = 3000
  var languagesServerPort = 3001

  for arg in commandLineParams():
    if arg.startsWith(workspaceServerPortArg):
      workspaceServerPort = arg[workspaceServerPortArg.len..^1].parseInt
    elif arg.startsWith(languagesServerPortArg):
      languagesServerPort = arg[languagesServerPortArg.len..^1].parseInt
    elif arg.startsWith(nimsuggestPathArg):
      nimsuggestPath = arg[nimsuggestPathArg.len..^1]
    else:
      echo "Unexpected argument '", arg, "'"
      quit(1)

  if languagesServerPort == workspaceServerPort:
    echo "Can't use port ", languagesServerPort, " for both servers"
    quit(1)

  var workspace = runWorkspaceServer(Port(workspaceServerPort))
  var languages = runLanguagesServer(Port(languagesServerPort))

  while not workspace.finished and not languages.finished:
    poll()
