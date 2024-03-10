import std/[os, asynchttpserver, strutils, strformat, uri, asyncfile, json, sugar, sequtils]
import glob
import misc/[custom_async, util, myjsonutils, custom_logger]
import router, server_utils

logCategory "workspace"

type DirInfo = object
  files: seq[string]
  folders: seq[string]

var ignoredPatterns: seq[Glob]
var allowedPatterns: seq[Glob]

proc shouldIgnore(path: string): bool =
  {.gcsafe.}:
    for pattern in ignoredPatterns:
      if path.matches(pattern):
        debugf "ignore pattern '{pattern.pattern}' matches {path}"
        return true

  return false

proc isAllowed(path: string): bool =
  {.gcsafe.}:
    for pattern in allowedPatterns:
      if path.matches(pattern):
        debugf "allow pattern '{pattern.pattern}' matches {path}"
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

proc translatePath(path: string): Option[string] =
  if path.isAbsolute or path.contains(".."):
    let absolutePath = path.absolutePath.normalizedPath
    if not isAllowed(absolutePath):
      return string.none
    return absolutePath.some

  return path.absolutePath.normalizedPath.some

proc callback(req: Request): Future[void] {.async.} =
  debugf"{req.reqMethod} {req.url}"

  let (workspaceName, hostedFolders) = block:
    {.gcsafe.}:
      (workspaceName, hostedFolders)

  let headers = newHttpHeaders([
    ("Access-Control-Allow-Origin", "*"),
    ("Access-Control-Allow-Headers", "authorization, content-type"),
    ("Access-Control-Allow-Methods", "GET,HEAD,PUT,PATCH,POST,DELETE"),
  ])

  withRequest req:
    options "/":
      await req.respond(Http204, "", headers)

    get "/info/name":
      await req.respond(Http200, workspaceName, headers)

    get "/info/workspace-folders":
      let message = %hostedFolders.mapIt(%*{
        "path": it.path,
        "name": it.name,
      })
      await req.respond(Http200, $message, headers)

    get "/relative-path/":
      ##
      var relativePath = ""

      let (name, actualPath) = path.splitWorkspacePath
      let absolutePath = actualPath.normalizedPath
      for i, folder in hostedFolders:
        if absolutePath.startsWith(folder.path):
          # todo
          let name = folder.name.get($i)
          relativePath = "@" & name & "/" & absolutePath[folder.path.len..^1].strip(chars={'/', '\\'}).replace('\\', '/')

      debug "get relative path ", absolutePath, " -> ", relativePath

      await req.respond(Http200, relativePath, headers)

    get "/list/":
      let absolutePath = translatePath(path).getOr:
        log lvlError, fmt"list '{path}' -> illegal"
        await req.respond(Http403, "illegal path", headers)
        break

      debug "list files in ", absolutePath

      let result = await readDir(absolutePath)
      let response = result.toJson

      await req.respond(Http200, $response, headers)

    get "/list":
      debug "list files in ."
      let result = if hostedFolders.len == 0:
        await readDir(".")
      else:
        var folders: seq[string]
        for i, f in hostedFolders:
          # todo
          # folders.add "@" & f.name.get($i)
          folders.add f.path
        DirInfo(folders: folders)

      let response = result.toJson
      await req.respond(Http200, $response, headers)

    get "/contents/":
      let absolutePath = translatePath(path).getOr:
        log lvlError, fmt"get content of '{path}' -> illegal"
        await req.respond(Http403, "illegal path", headers)
        break

      log lvlInfo, fmt"get content of '{path}' -> '{absolutePath}'"

      try:
        var file = openAsync(absolutePath, FileMode.fmRead)
        let content = await file.readAll()
        file.close()

        await req.respond(Http200, content, headers)

      except CatchableError:
        await req.respond(Http500, "failed to save: " & getCurrentExceptionMsg(), headers)

    post "/contents/":
      let absolutePath = translatePath(path).getOr:
        log lvlError, fmt"set content of '{path}' -> illegal"
        await req.respond(Http403, "illegal path", headers)
        break

      log lvlInfo, fmt"set content of '{path}' -> {absolutePath}"

      try:
        createDir(absolutePath.splitFile.dir)

        var file = openAsync(absolutePath, FileMode.fmWrite)
        await file.write(req.body)
        file.close()

        await req.respond(Http200, "", headers)

      except CatchableError:
        await req.respond(Http500, "failed to save: " & getCurrentExceptionMsg(), headers)

    fallback:
      await req.respond(Http404, "", headers)

proc readGlobFile(path: string): seq[Glob] =
  try:
    for line in readFile(path).splitLines():
      if line.isEmptyOrWhitespace:
        continue

      result.add glob(line)
  except CatchableError:
    log lvlInfo, fmt"no '{path}' file"

proc runWorkspaceServer*(port: Port) {.async.} =
  ignoredPatterns = readGlobFile(".absytree-ignore")
  allowedPatterns = readGlobFile(".absytree-allow")

  for g in ignoredPatterns:
    debugf "ignoring: {g.pattern}"
  for g in allowedPatterns:
    debugf "allowing: {g.pattern}"

  try:
    if fileExists(".absytree-workspace"):
      hostedFolders.setLen 0

      for line in readFile(".absytree-workspace").splitLines():
        if line.isEmptyOrWhitespace or line.strip().startsWith("#"):
          continue

        if line.startsWith("name: "):
          workspaceName = line["name: ".len..^1]
        else:

          hostedFolders.add (line.absolutePath.normalizedPath, string.none)
  except CatchableError:
    log lvlInfo, "no ignore file"

  log lvlInfo, fmt"hosting as {workspaceName}: {hostedFolders}"

  var server = newAsyncHttpServer()
  await server.serve(port, callback)

when isMainModule:
  const portArg = "--port:"
  var port = 3000
  for arg in commandLineParams():
    if arg.startsWith(portArg):
      port = arg[portArg.len..^1].parseInt
    else:
      log lvlError, fmt"Unexpected argument '{arg}'"
      quit(1)

  workspaceName = getCurrentDir().splitFile.name
  hostedFolders = @[getCurrentDir()]

  waitFor runWorkspaceServer(Port(port))
