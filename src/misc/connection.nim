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

proc logProcessDebugOutput*(process: AsyncProcess) {.async.} =
  try:
    while process.isAlive:
      let line = await process.recvErrorLine
      if true:
        log(lvlDebug, fmt"[server] {line}")
  except IOError:
    discard

proc newAsyncProcessConnection*(path: string, args: seq[string]):
    Future[ConnectionAsyncProcess] {.async.} =

  log lvlInfo, fmt"Creating async process connection at {path} {args}"

  let process = startAsyncProcess(path, args, autoRestart=false, autoStart=false, killOnExit=true)
  discard process.start()
  # asyncSpawn process.logProcessDebugOutput()

  return ConnectionAsyncProcess(process: process)

import chronos/transports/stream

type ConnectionAsyncSocket* = ref object of Connection
  # socket: AsyncSocket
  transport: StreamTransport
  activeRequests: int = 0 # Required because AsyncSocket asserts that we don't close the socket while
                          # recvLine is in progress
  closeRequested: bool = false

method close*(connection: ConnectionAsyncSocket) =
  try:
    if connection.activeRequests > 0:
      connection.closeRequested = true
    else:
      connection.transport.close()
      connection.transport = nil
  except Exception:
    discard

template handleClose(connection: Connection): untyped =
  inc connection.activeRequests
  defer:
    dec connection.activeRequests
    if connection.closeRequested and connection.activeRequests == 0:
      connection.closeRequested = false
      try:
        connection.close()
      except Exception:
        discard

method recvLine*(connection: ConnectionAsyncSocket): Future[string] {.async.} =
  if connection.transport.isNil or connection.transport.closed:
    return ""

  connection.handleClose()
  return await connection.transport.readLine()

method recv*(connection: ConnectionAsyncSocket, length: int): Future[string] {.async.} =
  if connection.transport.isNil or connection.transport.closed:
    return ""

  connection.handleClose()
  let bytes = await connection.transport.read(length)
  var res = newString(bytes.len)
  if bytes.len > 0:
    copyMem(res[0].addr, bytes[0].addr, bytes.len)
  return res

method send*(connection: ConnectionAsyncSocket, data: string): Future[void] {.async.} =
  if connection.transport.isNil or connection.transport.closed:
    return

  connection.handleClose()
  if data.len > 0:
    discard await connection.transport.write(data[0].addr, data.len)

proc newAsyncSocketConnection*(host: string, port: Port): Future[ConnectionAsyncSocket] {.async.} =
  log lvlInfo, fmt"Creating async socket connection at {host}:{port.int}"

  let ipAddress = host
  let port = port.int
  let addressess = resolveTAddress(ipAddress & ":" & $port)
  if addressess.len == 0:
    raise newException(IOError, &"Failed to resolve address '{ipAddress}:{port}'")

  let address = addressess[0]
  let transport = await connect(address, bufferSize = 1024 * 1024)

  # let socket = newAsyncSocket()
  # await socket.connect(host, port)
  return ConnectionAsyncSocket(transport: transport)
