import std/[os, asynchttpserver, strutils, strformat, uri, asyncfile, json, jsonutils]
import custom_async, util, router
import glob

type DirInfo = object
  files: seq[string]
  folders: seq[string]

var ignoredPatterns: seq[Glob]

proc shouldIgnore(path: string): bool =
  {.gcsafe.}:
    for pattern in ignoredPatterns:
      if path.matches(pattern):
        echo pattern.pattern, " matches ", path
        return true

  return false

proc readDir(path: string): Future[DirInfo] {.async.} =
  var info = DirInfo()
  for (kind, item) in walkDir(path, relative=true, skipSpecial=true):
    if kind == pcFile and not shouldIgnore(item):
      info.files.add item
    elif kind == pcDir and not shouldIgnore(item):
      info.folders.add item

  return info

proc callback(req: Request): Future[void] {.async.} =
  echo "[WS] ", req.reqMethod, " ", req.url

  let headers = newHttpHeaders([
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Headers", "authorization"),
    ("Access-Control-Allow-Methods", "GET,HEAD,PUT,PATCH,POST,DELETE"),
  ])

  withRequest req:
    options "/":
      await req.respond(Http204, "", headers)

    get "/info/name":
      let name = getCurrentDir().splitFile.name
      await req.respond(Http200, name, headers)

    get "/list/":
      if path.isAbsolute or path.contains(".."):
        await req.respond(Http403, "illegal path", headers)
        break

      echo "list files in ", path

      let result = await readDir(path)
      let response = result.toJson

      await req.respond(Http200, $response, headers)

    get "/list":
      echo "list files in ."
      let result = await readDir(".")
      let response = result.toJson
      await req.respond(Http200, $response, headers)

    get "/contents/":
      if path.isAbsolute or path.contains(".."):
        await req.respond(Http403, "illegal path", headers)
        break

      let fullPath = getCurrentDir() / path
      echo fmt"get content of '{fullPath}'"

      try:
        var file = openAsync(fullPath, FileMode.fmRead)
        let content = await file.readAll()
        file.close()

        await req.respond(Http200, content, headers)

      except CatchableError:
        await req.respond(Http500, "failed to save: " & getCurrentExceptionMsg(), headers)

    post "/contents/":
      if path.isAbsolute or path.contains(".."):
        await req.respond(Http403, "illegal path", headers)
        break

      let fullPath = getCurrentDir() / path
      echo fmt"set content of '{fullPath}'"

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

proc runWorkspaceServer*(port: Port) {.async.} =
  try:
    for line in readFile(".absytreeignore").splitLines():
      if line.isEmptyOrWhitespace:
        continue
      echo "Ignoring ", line

      ignoredPatterns.add glob(line)
  except CatchableError:
    echo "[WS] no ignore file"

  var server = newAsyncHttpServer()
  await server.serve(port, callback)

when isMainModule:
  const portArg = "--port:"
  var port = 3000
  for arg in commandLineParams():
    if arg.startsWith(portArg):
      port = arg[portArg.len..^1].parseInt
    else:
      echo "Unexpected argument '", arg, "'"
      quit(1)

  waitFor runWorkspaceServer(Port(port))
