import std/[strutils]
import misc/[websocket, util, custom_async, custom_asyncnet, custom_logger]

logCategory "connections"

type Connection* = ref object of RootObj

method close*(connection: Connection) {.base.} = discard
method recvLine*(connection: Connection): Future[string] {.base.} = discard
method recv*(connection: Connection, length: int): Future[string] {.base.} = discard
method send*(connection: Connection, data: string): Future[void] {.base.} = discard

when not defined(js):
  import misc/[async_process]
  type ConnectionAsyncProcess = ref object of Connection
    process: AsyncProcess

  method close*(connection: ConnectionAsyncProcess) =
    connection.process.destroy()

  method recvLine*(connection: ConnectionAsyncProcess): Future[string] =
    connection.process.recvLine()

  method recv*(connection: ConnectionAsyncProcess, length: int): Future[string] =
    connection.process.recv(length)

  method send*(connection: ConnectionAsyncProcess, data: string): Future[void] =
    connection.process.send(data)

  proc asyncVoid() {.async.} =
    discard

  proc newAsyncProcessConnection*(path: string, args: seq[string]):
      Future[ConnectionAsyncProcess] {.async.} =

    log lvlInfo, fmt"Creating async process connection at {path} {args}"

    let process = startAsyncProcess(path, args, autoRestart=false)

    var fut = newResolvableFuture[void]("newAsyncProcessConnection")
    process.onRestarted = proc(): Future[void] =
      fut.complete()
      return asyncVoid()

    await fut.future
    return ConnectionAsyncProcess(process: process)

type ConnectionAsyncSocket* = ref object of Connection
  socket: AsyncSocket
  activeRequests: int = 0 # Required because AsyncSocket asserts that we don't close the socket while
                          # recvLine is in progress
  closeRequested: bool = false

method close*(connection: ConnectionAsyncSocket) =
  if connection.activeRequests > 0:
    connection.closeRequested = true
  else:
    connection.socket.close()
    connection.socket = nil

template handleClose(connection: Connection): untyped =
  inc connection.activeRequests
  defer:
    dec connection.activeRequests
    if connection.closeRequested and connection.activeRequests == 0:
      connection.closeRequested = false
      connection.close()

method recvLine*(connection: ConnectionAsyncSocket): Future[string] {.async.} =
  if connection.socket.isNil or connection.socket.isClosed:
    return ""

  connection.handleClose()
  return await connection.socket.recvLine()

method recv*(connection: ConnectionAsyncSocket, length: int): Future[string] {.async.} =
  if connection.socket.isNil or connection.socket.isClosed:
    return ""

  connection.handleClose()
  return await connection.socket.recv(length)

method send*(connection: ConnectionAsyncSocket, data: string): Future[void] {.async.} =
  if connection.socket.isNil or connection.socket.isClosed:
    return

  connection.handleClose()
  await connection.socket.send(data)

proc newAsyncSocketConnection*(host: string, port: Port): Future[ConnectionAsyncSocket] {.async.} =
  log lvlInfo, fmt"Creating async socket connection at {host}:{port.int}"
  let socket = newAsyncSocket()
  await socket.connect(host, port)
  return ConnectionAsyncSocket(socket: socket)

type ConnectionWebsocket* = ref object of Connection
  websocket: WebSocket
  buffer: string
  processId: int

method close*(connection: ConnectionWebsocket) =
  connection.websocket.close()

method recvLine*(connection: ConnectionWebsocket): Future[string] {.async.} =
  var newLineIndex = connection.buffer.find("\r\n")
  while newLineIndex == -1:
    let next = connection.websocket.receiveStrPacket().await
    connection.buffer.append next
    newLineIndex = connection.buffer.find("\r\n")

  let line = connection.buffer[0..<newLineIndex]
  connection.buffer = connection.buffer[newLineIndex + 2..^1]
  return line

method recv*(connection: ConnectionWebsocket, length: int): Future[string] {.async.} =
  while connection.buffer.len < length:
    connection.buffer.add connection.websocket.receiveStrPacket().await

  let res = connection.buffer[0..<length]
  connection.buffer = connection.buffer[length..^1]
  return res

method send*(connection: ConnectionWebsocket, data: string): Future[void] =
  connection.websocket.send(data)
