import std/[os, osproc, asynchttpserver, strutils, strformat, asyncnet]
import custom_async, util, timer
import ws

## This program exposes a local process' std in and std out through a web socket
##

proc getFreePort*(): Port =
  var server = newAsyncHttpServer()
  server.listen(Port(0))
  let port = server.getPort()
  server.close()
  return port

var nimsuggestPort = getFreePort()

var port = 4000
var forwardedArgs: seq[string] = @["--port:" & $nimsuggestPort.int]
var isForwarding = false

echo "Using free port ", nimsuggestPort.int

for arg in commandLineParams():
  if isForwarding:
    forwardedArgs.add arg
  elif arg.startsWith("--port:"):
    port = arg[7..^1].parseInt
  elif arg == "--":
    isForwarding = true
  else:
    echo "Unexpected argument '", arg, "'"
    quit(1)

echo fmt"Exposing 'nimsuggest {forwardedArgs}' under ws://localhost:{port}"

let process = startProcess("nimsuggest", args = forwardedArgs)

var server = newAsyncHttpServer()

proc connectToNimsuggest(): Future[AsyncSocket] {.async.} =
  {.gcsafe.}:
    var socket = newAsyncSocket()
    await socket.connect("", Port(nimsuggestPort))
    return socket

proc callback(req: Request): Future[void] {.async.} =
  try:
    var ws = await newWebSocket(req)

    while ws.readyState == Open:
      var socket = await connectToNimsuggest()
      defer: socket.close()

      let packet = await ws.receiveStrPacket()
      echo "< ", packet

      await socket.send(packet & "\r\n")

      var totalTime = startTimer()
      while true:
        let response = await socket.recvLine()

        if response == "\r\n" or response == "":
          asyncCheck ws.send("")
          echo "Served request in ", totalTime.elapsed.ms, "ms"
          break

        await ws.send(response)

  except WebSocketClosedError:
    echo "Socket closed. "
  except WebSocketProtocolMismatchError:
    echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
  except WebSocketError:
    echo "Unexpected socket error: ", getCurrentExceptionMsg()

  {.gcsafe.}:
    process.terminate()

  await req.respond(Http200, "Hello world")

  quit(0)

proc checkRunning(): Future[void] {.async.} =
  while true:
    await sleepAsync(10)
    if not process.running:
      echo "nimsuggest stopped. quit"
      quit(1)

asyncCheck checkRunning()

waitFor server.serve(Port(port), callback)
