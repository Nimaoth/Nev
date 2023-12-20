import std/[os, osproc, asynchttpserver, strutils, strformat]
import misc/[custom_async, async_process, util]
import ws

## This program exposes a local process' std in and std out through a web socket

proc uiae(ws: WebSocket) {.async.} =
  while true:
    await sleepAsync(1000)
    await ws.send("hi")

var port = 4000
var program = ""
var forwardedArgs: seq[string]
when isMainModule:
  var isForwarding = false

  for arg in commandLineParams():
    if isForwarding:
      forwardedArgs.add arg
    elif arg.startsWith("--port:"):
      port = arg[7..^1].parseInt
    elif arg == "--":
      isForwarding = true
    elif program == "":
      program = arg
    else:
      echo "Unexpected argument '", arg, "'"
      quit(1)

  echo fmt"Exposing '{program} {forwardedArgs}' under ws://localhost:{port}"

  # let process = startProcess(program, args = ["--port:" & $6000, filename])
  # let process = startProcess(program, args=forwardedArgs)
  # process.inputStream()

  proc handleLineRead(process: AsyncProcess, ws: WebSocket) {.async.} =
    while true:
      let line = await process.recvLine()
      # echo "> "
      # echo "> ", line
      await ws.send(line)

  var server = newAsyncHttpServer()

  proc startProgram(ws: WebSocket): Future[AsyncProcess] {.async.} =
    {.gcsafe.}:
      var process = startAsyncProcess(program, args=forwardedArgs, autoRestart=false)
      asyncCheck process.handleLineRead(ws)
      return process

  proc callback(req: Request): Future[void] {.async.} =
    var process: AsyncProcess = nil

    try:
      var ws = await newWebSocket(req)
      process = await startProgram(ws)

      while ws.readyState == Open:
        let packet = await ws.receiveStrPacket()
        echo "< ", packet
        await process.send(packet)
    except WebSocketClosedError:
      echo "Socket closed. "
    except WebSocketProtocolMismatchError:
      echo "Socket tried to use an unknown protocol: ", getCurrentExceptionMsg()
    except WebSocketError:
      echo "Unexpected socket error: ", getCurrentExceptionMsg()

    if process.isNotNil:
      process.destroy()
    await req.respond(Http200, "Hello world")

  waitFor server.serve(Port(port), callback)