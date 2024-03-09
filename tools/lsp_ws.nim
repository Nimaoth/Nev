import std/[os, osproc, asynchttpserver, strutils, strformat, asyncnet, options, sequtils, json]
import misc/[custom_async, util, timer, async_process, custom_logger, myjsonutils]
import ws

## This program exposes a local process' std in and std out through a web socket
##

var port = 4000
var forwardedArgs: seq[string] = @[]
var isForwarding = false
var executablePath = ""
var logFile = string.none
var messageLengthLimit = 2000
var workspaceName = ""
var workspaceFolders: seq[tuple[path: string, name: Option[string]]] = @[]

template matchArg(arg: string, name: string, body: untyped): untyped =
  if arg.startsWith("--" & name & ":"):
    let value {.inject.} = arg[(name.len+3)..^1]
    body

for arg in commandLineParams():
  if isForwarding:
    forwardedArgs.add arg
  elif arg.startsWith("--port:"):
    port = arg[7..^1].parseInt
  elif arg.startsWith("--exe:"):
    executablePath = arg["--exe:".len..^1]
  elif arg.startsWith("--log:"):
    logFile = arg["--log:".len..^1].some
  elif arg == "--":
    isForwarding = true
  else:
    arg.matchArg "workspace":
      workspaceName = value
      continue
    arg.matchArg "directories":
      workspaceFolders = value.split(";").mapIt((it, string.none))
      continue

    echo "Unexpected argument '", arg, "'"
    quit(1)

if logFile.getSome logFile:
  logger.enableFileLogger(logFile)

logCategory "ws"

log lvlInfo, fmt"Exposing '{executablePath} {forwardedArgs}' under ws://localhost:{port}"
log lvlInfo, fmt"Workspace: {workspaceName}, directories: {workspaceFolders}"
logger.flush()

let process = startAsyncProcess(executablePath, forwardedArgs)

proc sender(process: AsyncProcess, ws: WebSocket): Future[void] {.async.} =
  while ws.readyState == Open:
    let packet = await ws.receiveStrPacket()
    debug "\n\n<<<<<<<<<<<<<<<<<<<<<<< ws to process begin\n", packet[0..min(packet.high, messageLengthLimit)], "\n<<<<<<<<<<<<<<<<<<<<<<< ws to process end\n\n"
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

    debug "\n\n>>>>>>>>>>>>>>>>>>>>>>> process to ws start\n", message[0..min(message.high, messageLengthLimit)], "\n>>>>>>>>>>>>>>>>>>>>>>> process to ws end\n\n"
    await ws.send(message)

proc logErrors(process: AsyncProcess): Future[void] {.async.} =
  while true:
    let line = await process.recvErrorLine()
    log lvlError, "[stderr] ", line

proc callback(req: Request): Future[void] {.async.} =
  log lvlInfo, fmt"Connection requested from {req}"
  let process: AsyncProcess = ({.gcsafe.}: process)

  try:
    var ws = await newWebSocket(req)

    asyncCheck process.sender(ws)
    asyncCheck process.receiver(ws)
    asyncCheck process.logErrors()

    while ws.readyState == Open:
      await sleepAsync(5000)

  except WebSocketClosedError:
    log lvlError, "Socket closed. "
  except WebSocketProtocolMismatchError:
    log lvlError, fmt"Socket tried to use an unknown protocol: {getCurrentExceptionMsg()}"
  except WebSocketError:
    log lvlError, fmt"Unexpected socket error: {getCurrentExceptionMsg()}"

  process.destroy()

  quit(0)

proc checkProcessStatus(): Future[void] {.async.} =
  while true:
    await sleepAsync(1000)
    if not process.isAlive:
      log lvlError, "Process died"
      quit(1)

process.onRestarted = proc() {.async.} =
  asyncCheck checkProcessStatus()
  var server = newAsyncHttpServer()
  await server.serve(Port(port), callback)

while hasPendingOperations():
  poll(1000)