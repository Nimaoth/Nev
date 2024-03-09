import std/[os, osproc, asynchttpserver, strutils, strformat, uri, asyncfile, json, sequtils]
import misc/[custom_async, util, myjsonutils]
import router, server_utils

var processes: seq[Process] = @[]

proc callback(req: Request): Future[void] {.async.} =
  echo "[LS] ", req.reqMethod, " ", req.url

  let headers = newHttpHeaders([("Access-Control-Allow-Origin", "*")])

  let (workspaceName, hostedFolders) = block:
    {.gcsafe.}:
      (workspaceName, hostedFolders)

  withRequest req:
    options "/":
      let headers = newHttpHeaders([
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Headers", "authorization"),
        ("Access-Control-Allow-Methods", "GET,HEAD,PUT,PATCH,POST,DELETE"),
      ])
      await req.respond(Http204, "", headers)

    post "/lsp/start":
      let port = getFreePort()

      try:
        let reqBody = parseJson(req.body)
        let executablePath = reqBody["path"].str
        let additionalArgs = reqBody["args"].jsonTo seq[string]
        let proxyPath = getCurrentDir() / "tools/lsp-ws.exe"

        let directories = hostedFolders.mapIt(fmt"{it.path}").join(";")
        let args = @[fmt"--port:{port}", fmt"--exe:{executablePath}", fmt"--log:lsp-ws-{port}.log", fmt"--workspace:{workspaceName}", fmt"--directories:{directories}", "--"] & additionalArgs
        let process = startProcess(proxyPath, args=args, options={poUsePath, poDaemon})

        {.gcsafe.}:
          processes.add process

        let response = %*{
          "port": port.int,
          "processId": os.getCurrentProcessId()
        }

        await req.respond(Http200, response.pretty, headers)

      except CatchableError:
        await req.respond(Http500, "failed to start language server websocket proxy: " & getCurrentExceptionMsg(), headers)

    fallback:
      await req.respond(Http404, "", headers)

proc runLanguagesServer*(port: Port) {.async.} =
  var server = newAsyncHttpServer()
  await server.serve(port, callback)

when isMainModule:
  const portArg = "--port:"
  var port = 3001
  for arg in commandLineParams():
    if arg.startsWith(portArg):
      port = arg[portArg.len..^1].parseInt
    else:
      echo "Unexpected argument '", arg, "'"
      quit(1)

  waitFor runLanguagesServer(Port(port))
