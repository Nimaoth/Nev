import std/[os, strutils]
import misc/[custom_async, util, custom_logger]
import languages_server, workspace_server

logCategory "server"

when isMainModule:
  const workspaceServerPortArg = "--workspace-port:"
  const languagesServerPortArg = "--languages-port:"
  var workspaceServerPort = 3000
  var languagesServerPort = 3001

  logger.enableConsoleLogger()

  for arg in commandLineParams():
    if arg.startsWith(workspaceServerPortArg):
      workspaceServerPort = arg[workspaceServerPortArg.len..^1].parseInt
    elif arg.startsWith(languagesServerPortArg):
      languagesServerPort = arg[languagesServerPortArg.len..^1].parseInt
    else:
      log lvlError, fmt"Unexpected argument '{arg}'"
      quit(1)

  if languagesServerPort == workspaceServerPort:
    log lvlError, fmt"Can't use port {languagesServerPort} for both servers"
    quit(1)

  var workspace = runWorkspaceServer(Port(workspaceServerPort))
  var languages = runLanguagesServer(Port(languagesServerPort))

  while not workspace.finished and not languages.finished:
    poll()
