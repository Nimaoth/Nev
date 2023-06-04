import std/[os, asynchttpserver, options]
import custom_async

proc `$`*(p: Port): string {.borrow.}

var hostedFolders*: seq[tuple[path: string, name: Option[string]]]

proc getFreePort*(): Port =
  var server = newAsyncHttpServer()
  server.listen(Port(0))
  let port = server.getPort()
  server.close()
  return port

proc splitWorkspacePath*(path: string): tuple[name: string, path: string] =
  let i = path.find(':')
  if i == -1 or i >= path.high or path[i + 1] != ':':
    return ("", path)
  return (path[0..<i], path[(i+2)..^1])

proc getActualPathAbs*(path: string): string =
  let (name, actualPath) = path.splitWorkspacePath
  {.gcsafe.}:
    for i, f in hostedFolders:
      if f.name.get($i) == name:
        return f.path / actualPath
  return getCurrentDir() / path