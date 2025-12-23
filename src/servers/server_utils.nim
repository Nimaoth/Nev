import std/[os, options, strutils]
import misc/[custom_async]

proc `$`*(p: Port): string {.borrow.}

var hostedFolders*: seq[tuple[path: string, name: Option[string]]]
var workspaceName*: string

proc getFreePort*(): Port =
  var server = newAsyncHttpServer()
  server.listen(Port(0))
  let port = server.getPort()
  server.close()
  return port

proc splitWorkspacePath*(path: string): tuple[name: string, path: string] =
  if not path.startsWith('@'):
    return ("", path)

  let i = path.find('/')
  if i == -1:
    return (path[1..^1], "")
  return (path[1..<i], path[(i+1)..^1])

proc getActualPathAbs*(path: string): string =
  let (name, actualPath) = path.splitWorkspacePath
  {.gcsafe.}:
    for i, f in hostedFolders:
      if f.name.get($i) == name:
        return f.path / actualPath
  return getCurrentDir() / path