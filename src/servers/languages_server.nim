import std/[os, osproc, asynchttpserver, strutils, strformat, uri, asyncfile, json]
import custom_async, util, router, server_utils

var processes: seq[Process] = @[]

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

      let port = getFreePort()
      echo fmt"start nimsuggest on localhost:{port} for '{path}'"

      try:
        let nimsuggest = getCurrentDir() / "nimsuggest-ws.exe"
        let process = startProcess(nimsuggest, args=[fmt"--port:{port}", "--", path])

        {.gcsafe.}:
          processes.add process

        let response = %*{
          "port": port.int,
          "tempFilename": "_temp" / path,
        }

        await req.respond(Http200, response.pretty, headers)

      except CatchableError:
        await req.respond(Http500, "failed to start nimsuggest: " & getCurrentExceptionMsg(), headers)

    post "/nimsuggest/temp-file/":
      if path.isAbsolute or path.contains(".."):
        await req.respond(Http403, "illegal path", headers)
        break

      let fullPath = getCurrentDir() / "_temp" / path
      echo fmt"set content temp file of '{fullPath}'"

      try:
        createDir(fullPath.splitFile.dir)

        var file = openAsync(fullPath, FileMode.fmWrite)
        await file.write(req.body)
        file.close()

        await req.respond(Http200, "", headers)

      except CatchableError:
        await req.respond(Http500, "failed to save: " & getCurrentExceptionMsg(), headers)

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
