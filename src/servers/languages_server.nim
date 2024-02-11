import std/[os, osproc, asynchttpserver, strutils, strformat, uri, asyncfile, json]
import misc/[custom_async, util, myjsonutils]
import router, server_utils

var processes: seq[Process] = @[]
var nimsuggestPath* = "nimsuggest"

proc callback(req: Request): Future[void] {.async.} =
  echo "[LS] ", req.reqMethod, " ", req.url

  let headers = newHttpHeaders([("Access-Control-Allow-Origin", "*")])

  withRequest req:
    options "/":
      let headers = newHttpHeaders([
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Headers", "authorization"),
        ("Access-Control-Allow-Methods", "GET,HEAD,PUT,PATCH,POST,DELETE"),
      ])
      await req.respond(Http204, "", headers)

    get "/nimsuggest/open/":
      if path.isAbsolute or path.contains(".."):
        await req.respond(Http403, "illegal path", headers)
        break

      let (_, relativePath) = path.splitWorkspacePath
      let fullPath = path.getActualPathAbs

      let port = getFreePort()

      try:
        let nimsuggestPath = block:
          {.gcsafe.}:
            nimsuggestPath

        echo fmt"start {nimsuggestPath} on localhost:{port} for '{fullPath}'"

        let nimsuggest = getCurrentDir() / "tools/nimsuggest-ws.exe"
        let process = startProcess(nimsuggest, args=[fmt"--port:{port}", fmt"--nimsuggest:{nimsuggestPath}", "--", fullPath], options={poUsePath, poDaemon})

        {.gcsafe.}:
          processes.add process

        let response = %*{
          "port": port.int,
          "tempFilename": "_temp" / relativePath,
        }

        await req.respond(Http200, response.pretty, headers)

      except CatchableError:
        await req.respond(Http500, "failed to start nimsuggest: " & getCurrentExceptionMsg(), headers)

    post "/nimsuggest/temp-file/":
      if path.isAbsolute or path.contains(".."):
        await req.respond(Http403, "illegal path", headers)
        break

      let (_, actualPath) = path.splitWorkspacePath


      let fullPath = getCurrentDir() / "_temp" / actualPath
      echo fmt"set content temp file of '{fullPath}'"

      try:
        createDir(fullPath.splitFile.dir)

        var file = openAsync(fullPath, FileMode.fmWrite)
        await file.write(req.body)
        file.close()

        await req.respond(Http200, "", headers)

      except CatchableError:
        await req.respond(Http500, "failed to save: " & getCurrentExceptionMsg(), headers)

    post "/lsp/start":
      let port = getFreePort()

      try:
        let reqBody = parseJson(req.body)
        let executablePath = reqBody["path"].str
        let additionalArgs = reqBody["args"].jsonTo seq[string]
        let nimsuggest = getCurrentDir() / "tools/lsp-ws.exe"
        let args = @[fmt"--port:{port}", fmt"--exe:{executablePath}", "--"] & additionalArgs
        let process = startProcess(nimsuggest, args=args, options={poUsePath, poDaemon})

        {.gcsafe.}:
          processes.add process

        let response = %*{
          "port": port.int
        }

        await req.respond(Http200, response.pretty, headers)

      except CatchableError:
        await req.respond(Http500, "failed to start nimsuggest: " & getCurrentExceptionMsg(), headers)

    fallback:
      await req.respond(Http404, "", headers)

proc runLanguagesServer*(port: Port) {.async.} =
  var server = newAsyncHttpServer()
  await server.serve(port, callback)

when isMainModule:
  const portArg = "--port:"
  const nimsuggestPathArg = "--nimsuggest:"
  var port = 3001
  for arg in commandLineParams():
    if arg.startsWith(portArg):
      port = arg[portArg.len..^1].parseInt
    elif arg.startsWith(nimsuggestPathArg):
      nimsuggestPath = arg[nimsuggestPathArg.len..^1]
    else:
      echo "Unexpected argument '", arg, "'"
      quit(1)

  waitFor runLanguagesServer(Port(port))
