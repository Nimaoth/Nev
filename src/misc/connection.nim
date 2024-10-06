import misc/[util, custom_async, custom_logger, async_process]

{.push gcsafe.}

logCategory "connections"

type Connection* = ref object of RootObj

{.push hint[XCannotRaiseY]:off.}

method close*(connection: Connection) {.base, gcsafe, raises: [].} = discard
method recvLine*(connection: Connection): Future[string] {.base, gcsafe, raises: [IOError].} = discard
method recv*(connection: Connection, length: int): Future[string] {.base, gcsafe, raises: [IOError].} = discard
method send*(connection: Connection, data: string): Future[void] {.base, gcsafe, raises: [IOError].} = discard

{.pop.}

type ConnectionAsyncProcess = ref object of Connection
  process: AsyncProcess

method close*(connection: ConnectionAsyncProcess) =
  try:
    connection.process.destroy()
  except OSError:
    discard

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

  var fut = newFuture[void]("newAsyncProcessConnection")
  process.onRestarted = proc(): Future[void] =
    fut.complete()
    return asyncVoid()

  await fut
  return ConnectionAsyncProcess(process: process)

# todo
# type ConnectionAsyncSocket* = ref object of Connection
#   socket: AsyncSocket
#   activeRequests: int = 0 # Required because AsyncSocket asserts that we don't close the socket while
#                           # recvLine is in progress
#   closeRequested: bool = false

# method close*(connection: ConnectionAsyncSocket) =
#   if connection.activeRequests > 0:
#     connection.closeRequested = true
#   else:
#     connection.socket.close()
#     connection.socket = nil

# template handleClose(connection: Connection): untyped =
#   inc connection.activeRequests
#   defer:
#     dec connection.activeRequests
#     if connection.closeRequested and connection.activeRequests == 0:
#       connection.closeRequested = false
#       connection.close()

# method recvLine*(connection: ConnectionAsyncSocket): Future[string] {.async.} =
#   if connection.socket.isNil or connection.socket.isClosed:
#     return ""

#   connection.handleClose()
#   return await connection.socket.recvLine()

# method recv*(connection: ConnectionAsyncSocket, length: int): Future[string] {.async.} =
#   if connection.socket.isNil or connection.socket.isClosed:
#     return ""

#   connection.handleClose()
#   return await connection.socket.recv(length)

# method send*(connection: ConnectionAsyncSocket, data: string): Future[void] {.async.} =
#   if connection.socket.isNil or connection.socket.isClosed:
#     return

#   connection.handleClose()
#   await connection.socket.send(data)

# proc newAsyncSocketConnection*(host: string, port: Port): Future[ConnectionAsyncSocket] {.async.} =
#   log lvlInfo, fmt"Creating async socket connection at {host}:{port.int}"
#   let socket = newAsyncSocket()
#   await socket.connect(host, port)
#   return ConnectionAsyncSocket(socket: socket)
