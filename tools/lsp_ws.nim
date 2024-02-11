import std/[os, osproc, asynchttpserver, strutils, strformat, asyncnet]
import misc/[custom_async, util, timer, async_process]
import ws

## This program exposes a local process' std in and std out through a web socket
##

var port = 4000
var forwardedArgs: seq[string] = @[]
var isForwarding = false
var executablePath = ""

for arg in commandLineParams():
  if isForwarding:
    forwardedArgs.add arg
  elif arg.startsWith("--port:"):
    port = arg[7..^1].parseInt
  elif arg.startsWith("--exe:"):
    executablePath = arg["--exe:".len..^1]
  elif arg == "--":
    isForwarding = true
  else:
    echo "Unexpected argument '", arg, "'"
    quit(1)

# echo fmt"Exposing '{executablePath} {forwardedArgs}' under ws://localhost:{port}"

let process = startAsyncProcess(executablePath, forwardedArgs)

proc sender(process: AsyncProcess, ws: WebSocket): Future[void] {.async.} =
  while ws.readyState == Open:
    let packet = await ws.receiveStrPacket()
    # echo "\n\n<<<<<<<<<<<<<<<<<<<<<<< ws to process begin\n", packet[0..min(packet.high, 300)], "\n<<<<<<<<<<<<<<<<<<<<<<< ws to process end\n\n"
    await process.send(packet)

proc receiver(process: AsyncProcess, ws: WebSocket): Future[void] {.async.} =
  while ws.readyState == Open:
    var message = ""
    var contentLength = 0

    var line = await process.recvLine
    while line.len == 0:
      line = await process.recvLine

    while line != "" and line != "\r\n":
      message.add line
      message.add "\r\n"

      if line.startsWith("Content-Length: "):
        contentLength = line[16..^1].strip.parseInt

      line = await process.recvLine

    message.add "\r\n"

    let data: string = await process.recv(contentLength)
    message.add data

    # echo "\n\n>>>>>>>>>>>>>>>>>>>>>>> process to ws start\n", message[0..min(message.high, 300)], "\n>>>>>>>>>>>>>>>>>>>>>>> process to ws end\n\n"
    await ws.send(message)

proc logErrors(process: AsyncProcess): Future[void] {.async.} =
  while true:
    let line = await process.recvErrorLine()
    echo "--- ", line

proc callback(req: Request): Future[void] {.async.} =
  # echo fmt"Connection requested from {req}"
  let process: AsyncProcess = ({.gcsafe.}: process)

  try:
    var ws = await newWebSocket(req)

    asyncCheck process.sender(ws)
    asyncCheck process.receiver(ws)
    # asyncCheck process.logErrors()

    while ws.readyState == Open:
      await sleepAsync(5000)

  except WebSocketClosedError:
    echo "Socket closed. "
  except WebSocketProtocolMismatchError:
    echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
  except WebSocketError:
    echo "Unexpected socket error: ", getCurrentExceptionMsg()

  process.destroy()

  quit(0)

proc checkProcessStatus(): Future[void] {.async.} =
  while true:
    await sleepAsync(1000)
    if not process.isAlive:
      echo "Process died"
      quit(1)

process.onRestarted = proc() {.async.} =
  asyncCheck checkProcessStatus()
  var server = newAsyncHttpServer()
  await server.serve(Port(port), callback)

while true:
  poll(1000)