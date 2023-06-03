import std/[asynchttpserver]
import custom_async

proc `$`*(p: Port): string {.borrow.}

proc getFreePort*(): Port =
  var server = newAsyncHttpServer()
  server.listen(Port(0))
  let port = server.getPort()
  server.close()
  return port